extends Node

var faction_order: Array[StringName] = []
var current_faction_index: int = 0
var is_player_turn: bool = true
var shardfall_system: ShardfallSystem = ShardfallSystem.new()

# AI settlement targets
var _ai_settlement_targets: Dictionary = {} # faction_id -> Vector2i target hex

# Skulloath aggression cycle tracking
var _ai_aggression_cooldown: Dictionary = {} # faction_id -> turns remaining
var _ai_attack_counters: Dictionary = {} # faction_id -> int

# Patrol state
var _gladehost_waypoints: Dictionary = {} # army_id -> {waypoints: Array, index: int}
var _jade_patrol_index: Dictionary = {} # army_id -> int

# Border tile cache (cleared each faction turn)
var _border_cache: Dictionary = {} # faction_id -> Array[Vector2i]

# Random event temp effects
var _temp_effects: Array[Dictionary] = [] # [{faction_id, effect, turns_remaining}]

# Turn log for turn summary panel
var turn_log: Array[Dictionary] = [] # [{type, text, turn, ...}]

# Event cooldown for random events
var _event_cooldown: int = 0

func serialize_state() -> Dictionary:
	return {
		"faction_order": faction_order.duplicate(),
		"current_faction_index": current_faction_index,
		"is_player_turn": is_player_turn,
		"_ai_settlement_targets": _ai_settlement_targets.duplicate(),
		"_ai_aggression_cooldown": _ai_aggression_cooldown.duplicate(),
		"_ai_attack_counters": _ai_attack_counters.duplicate(),
		"_gladehost_waypoints": _gladehost_waypoints.duplicate(true),
		"_jade_patrol_index": _jade_patrol_index.duplicate(),
		"_temp_effects": _temp_effects.duplicate(true),
		"_event_cooldown": _event_cooldown,
	}

func deserialize_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	faction_order.assign(data.get("faction_order", []))
	current_faction_index = data.get("current_faction_index", 0)
	is_player_turn = data.get("is_player_turn", true)
	_ai_settlement_targets = data.get("_ai_settlement_targets", {})
	_ai_aggression_cooldown = data.get("_ai_aggression_cooldown", {})
	_ai_attack_counters = data.get("_ai_attack_counters", {})
	_gladehost_waypoints = data.get("_gladehost_waypoints", {})
	_jade_patrol_index = data.get("_jade_patrol_index", {})
	_temp_effects = data.get("_temp_effects", [])
	_event_cooldown = data.get("_event_cooldown", 0)

func _ready() -> void:
	EventBus.end_turn_pressed.connect(_on_end_turn_pressed)
	EventBus.battle_resolved.connect(_on_log_battle_resolved)
	EventBus.city_captured.connect(_on_log_city_captured)
	EventBus.shardfall_occurred.connect(_on_log_shardfall)
	EventBus.treaty_created.connect(_on_log_treaty_created)
	EventBus.army_destroyed.connect(_on_log_army_destroyed)

func _on_log_battle_resolved(winner_faction: StringName, hex_pos: Vector2i) -> void:
	var fd: FactionData = DataManager.get_faction(winner_faction)
	var name: String = fd.display_name if fd else str(winner_faction)
	turn_log.append({type = "battle", text = "%s won a battle at (%d, %d)" % [name, hex_pos.x, hex_pos.y]})

func _on_log_city_captured(city_id: StringName, old_owner: StringName, new_owner: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	var city_name: String = city.get_display_name() if city else str(city_id)
	var fd: FactionData = DataManager.get_faction(new_owner)
	var name: String = fd.display_name if fd else str(new_owner)
	turn_log.append({type = "capture", text = "%s captured %s" % [name, city_name]})

func _on_log_shardfall(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm) -> void:
	var realm_names := ["Divine", "Void", "Elemental", "Nature", "Mortal"]
	var r_name: String = realm_names[realm] if realm < realm_names.size() else "Unknown"
	turn_log.append({type = "shard", text = "A %s Shard fell at (%d, %d)" % [r_name, hex_pos.x, hex_pos.y]})

func _on_log_treaty_created(treaty_id: StringName, treaty_type: int, faction_a: StringName, faction_b: StringName) -> void:
	var fa: FactionData = DataManager.get_faction(faction_a)
	var fb: FactionData = DataManager.get_faction(faction_b)
	var na: String = fa.display_name if fa else str(faction_a)
	var nb: String = fb.display_name if fb else str(faction_b)
	var type_names := ["Peace", "Alliance", "Trade"]
	var t_name: String = type_names[treaty_type] if treaty_type < type_names.size() else "Treaty"
	turn_log.append({type = "treaty", text = "%s and %s formed a %s" % [na, nb, t_name]})

func _on_log_army_destroyed(army_id: StringName, faction_id: StringName) -> void:
	var fd: FactionData = DataManager.get_faction(faction_id)
	var name: String = fd.display_name if fd else str(faction_id)
	turn_log.append({type = "army", text = "A %s army was destroyed" % name})

func start_game() -> void:
	faction_order.clear()
	faction_order.append(GameManager.state.player_faction_id)
	for faction_id in GameManager.state.faction_states:
		if faction_id != GameManager.state.player_faction_id:
			faction_order.append(faction_id)

	current_faction_index = 0
	is_player_turn = true
	_start_faction_turn()

func _start_faction_turn() -> void:
	var faction_id := faction_order[current_faction_index]
	is_player_turn = (faction_id == GameManager.state.player_faction_id)

	# Refresh caches for this faction's turn
	GameManager.movement_system.refresh_caches()
	_border_cache.clear()

	# Process city system: income, growth, queues, sieges
	GameManager.city_system.process_turn(faction_id)

	# Process diplomacy, policies, and research
	GameManager.diplomacy_system.process_treaties(faction_id)
	GameManager.policy_system.process_policies(faction_id)
	GameManager.research_system.process_research(faction_id)

	# Process elderbeasts for Shardhorde
	if faction_id == &"shardhorde":
		_process_elderbeasts()

	# Process unique faction mechanics
	_process_faction_mechanic(faction_id)

	# Heal armies in settlements/friendly territory
	_heal_armies_in_settlements(faction_id)

	# Terrain attrition: damage/heal armies based on terrain they occupy
	_apply_terrain_attrition(faction_id)

	# Grant passive XP to commanders
	_grant_passive_commander_xp(faction_id)

	# Reset army movement for this faction (skip garrisons)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and not army.is_garrison:
			army.movement_remaining = army.get_max_movement()
			# Road bonus: +0.6 MP per road level
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile and tile.road_level >= 1:
				army.movement_remaining += 0.6 * tile.road_level
			# Moonspear: Waxing Moon (phase 1) grants +0.5 movement
			if faction_id == &"moonspear":
				var mfs: FactionState = GameManager.state.faction_states.get(faction_id)
				if mfs and mfs.lunar_phase == 1:
					army.movement_remaining += 0.5
			army.has_moved = false
			army.battle_exhausted = false

	# Decay temp effects
	_decay_temp_effects(faction_id)

	EventBus.turn_started.emit(GameManager.state.current_turn, faction_id)

	if is_player_turn:
		_check_random_events(faction_id)
	else:
		_ai_assign_commanders(faction_id)
		_consolidate_ai_armies(faction_id)
		_execute_ai_city_management(faction_id)
		_execute_ai_settlement_building(faction_id)
		GameManager.diplomacy_system.execute_ai_diplomacy(faction_id)
		GameManager.research_system.execute_ai_research(faction_id)
		if faction_id == &"empire":
			_ai_handle_forsaken_offer(faction_id)
			_ai_handle_senate_dilemma(faction_id)
		if faction_id == &"shardhorde":
			_execute_shardhorde_ai()
		elif faction_id == &"gladehost":
			_execute_gladehost_ai(faction_id)
		elif faction_id == &"tainted_jade":
			_execute_tainted_jade_ai(faction_id)
		elif faction_id == &"skulloath":
			_execute_skulloath_ai(faction_id)
		else:
			_execute_ai_turn(faction_id)

func _on_end_turn_pressed() -> void:
	if not is_player_turn:
		return
	_end_current_faction_turn()

func _end_current_faction_turn() -> void:
	var faction_id := faction_order[current_faction_index]
	EventBus.turn_ended.emit(GameManager.state.current_turn, faction_id)

	current_faction_index += 1

	if current_faction_index >= faction_order.size():
		_end_round()
	else:
		_start_faction_turn()

func _end_round() -> void:
	EventBus.round_ended.emit(GameManager.state.current_turn)
	shardfall_system.check_shardfall(GameManager.state.current_turn)

	GameManager.state.current_month += 1
	if GameManager.state.current_month >= 10:
		GameManager.state.current_month = 0
		GameManager.state.current_year += 1

	_decay_shards()
	_check_victory_conditions()
	GameManager.state.current_turn += 1

	# Auto-save at round end (slot 0)
	GameManager.save_game(0)

	# Clear turn log and per-turn diplomacy tracking for next round
	turn_log.clear()
	GameManager.diplomacy_system.reset_gifts_this_turn()

	if GameManager.state.game_over:
		return # Don't start next turn if game is over

	current_faction_index = 0
	_start_faction_turn()

func _decay_shards() -> void:
	var to_remove: Array[StringName] = []
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if shard.claimed_by == &"" and shard.turns_remaining > 0:
			shard.turns_remaining -= 1
			if shard.turns_remaining <= 0:
				to_remove.append(shard_id)
	for shard_id in to_remove:
		var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
		if shard and shard.guardian_army_id != &"":
			GameManager.remove_army(shard.guardian_army_id)
		GameManager.state.active_shards.erase(shard_id)
		EventBus.shard_expired.emit(shard_id)

# ── Victory Conditions ───────────────────────────────────────

func _check_victory_conditions() -> void:
	if GameManager.state.game_over:
		return

	var total_regions := DataManager.regions.size()
	var domination_threshold := int(total_regions * 0.6)

	for faction_id in GameManager.state.faction_states:
		if GameManager.is_npc_faction(faction_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[faction_id]
		if fs.is_defeated:
			continue
		var is_player: bool = (faction_id == GameManager.state.player_faction_id)

		# Check Defeat — no cities, no armies (no elderbeasts for Shardhorde)
		var has_cities := fs.owned_cities.size() > 0
		var has_armies := false
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == faction_id and not army.is_garrison:
				has_armies = true
				break
		var has_beasts := false
		if faction_id == &"shardhorde":
			for beast_id in GameManager.state.elderbeasts:
				var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
				if beast.faction_id == faction_id:
					has_beasts = true
					break
			if not has_armies and not has_beasts:
				fs.is_defeated = true
				if is_player:
					_trigger_game_over(faction_id, Enums.VictoryType.DEFEAT, true)
					return
				continue
		elif not has_cities and not has_armies:
			fs.is_defeated = true
			if is_player:
				_trigger_game_over(faction_id, Enums.VictoryType.DEFEAT, true)
				return
			continue

		# ── Quick Match: culture completion ──
		if GameManager.state.game_mode == Enums.GameMode.QUICKMATCH and not GameManager.state.quickmatch_won:
			var completed_cultures := GameManager.get_completed_cultures(faction_id)
			if completed_cultures.size() > 0:
				_trigger_game_over(faction_id, Enums.VictoryType.CULTURE_VICTORY, is_player)
				return

		# ── Sandbox: Long Victory (60% regions) and World Conquest (100%) ──
		if GameManager.state.game_mode == Enums.GameMode.SANDBOX or GameManager.state.quickmatch_won:
			# World Conquest — own ALL regions
			var all_regions := GameManager.get_completed_regions(faction_id)
			if all_regions.size() >= GameManager.REGION_CITIES.size():
				_trigger_game_over(faction_id, Enums.VictoryType.WORLD_CONQUEST, is_player)
				return
			# Long Victory — control 60%+ of regions
			if all_regions.size() >= int(GameManager.REGION_CITIES.size() * 0.6):
				_trigger_game_over(faction_id, Enums.VictoryType.LONG_VICTORY, is_player)
				return

		# Check Domination — control 60%+ of regions (legacy, uses owned_regions)
		if fs.owned_regions.size() >= domination_threshold:
			_trigger_game_over(faction_id, Enums.VictoryType.DOMINATION, is_player)
			return

		# Check Diplomatic — allied with 2+ factions while having 5+ regions
		if fs.owned_regions.size() >= 5:
			var alliance_count := 0
			for other_id in GameManager.state.faction_states:
				if other_id == faction_id or GameManager.is_npc_faction(other_id):
					continue
				var other_fs: FactionState = GameManager.state.faction_states[other_id]
				if other_fs.is_defeated:
					continue
				if GameManager.get_relation(faction_id, other_id) == Enums.FactionRelation.ALLIED:
					alliance_count += 1
			if alliance_count >= 2:
				_trigger_game_over(faction_id, Enums.VictoryType.DIPLOMATIC, is_player)
				return

		# Check Shard Ascension — 10+ total shards claimed
		if fs.owned_shards.size() >= 10:
			_trigger_game_over(faction_id, Enums.VictoryType.SHARD_ASCENSION, is_player)
			return

	# Check Elimination — last non-defeated faction standing
	var alive_factions: Array[StringName] = []
	for faction_id in GameManager.state.faction_states:
		if GameManager.is_npc_faction(faction_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[faction_id]
		if not fs.is_defeated:
			alive_factions.append(faction_id)
	if alive_factions.size() == 1:
		var winner := alive_factions[0]
		var is_player := (winner == GameManager.state.player_faction_id)
		_trigger_game_over(winner, Enums.VictoryType.ELIMINATION, is_player)

func _trigger_game_over(faction_id: StringName, victory_type: int, is_player: bool) -> void:
	GameManager.state.game_over = true
	GameManager.state.victory_type = StringName(str(victory_type))
	EventBus.game_over.emit(faction_id, victory_type, is_player)

func get_current_faction() -> StringName:
	if current_faction_index < faction_order.size():
		return faction_order[current_faction_index]
	return &""

# ── AI Forsaken Offer Handling ────────────────────────────────

func _ai_handle_forsaken_offer(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var offer := GameManager.policy_system.check_forsaken_offer(faction_id, GameManager.state.current_turn)
	if offer.is_empty():
		return
	# AI accepts when desperate: low gold or at war
	var gold: int = fs.resources.get(Enums.ResourceType.GOLD, 0)
	var at_war := false
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id:
			continue
		var key := str(faction_id) + ":" + str(other_id)
		var relation = GameManager.state.diplomacy.get(key, Enums.FactionRelation.NEUTRAL)
		if relation == Enums.FactionRelation.WAR:
			at_war = true
			break
	if gold < 50 or at_war:
		GameManager.policy_system.accept_forsaken_offer(faction_id, offer)
	else:
		GameManager.policy_system.decline_forsaken_offer(faction_id)

# ── AI Senate Dilemma Handling ───────────────────────────────

func _ai_handle_senate_dilemma(faction_id: StringName) -> void:
	var dilemma := GameManager.policy_system.check_senate_dilemma(faction_id, GameManager.state.current_turn)
	if dilemma.is_empty():
		return
	# AI always picks choice_a
	GameManager.policy_system.apply_senate_dilemma_choice(faction_id, dilemma, "a")

# ── Commander XP ─────────────────────────────────────────────

func _grant_passive_commander_xp(faction_id: StringName) -> void:
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and army.commander:
			var context: Array[StringName] = []
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile:
				context.append(StringName("terrain_" + Enums.TerrainType.keys()[tile.terrain].to_lower()))
			var city := GameManager.city_system.get_city_at_hex(army.hex_pos)
			if city:
				context.append(&"in_city")
			if army.elderbeast_id != &"":
				context.append(&"elderbeast")
			var base_xp := 2
			if city and city.faction_id == army.faction_id:
				base_xp += 3  # 5 total when garrisoned in own city
			CommanderSystem.grant_passive_xp(army.commander, context, base_xp)

# ── AI Commander Assignment ──────────────────────────────────

func _ai_assign_commanders(faction_id: StringName) -> void:
	var available := GameManager.get_available_commanders(faction_id)
	if available.is_empty():
		return
	# Get armies without commanders, sorted by size (largest first)
	var armies_no_cmd: Array[ArmyState] = []
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and army.commander == null:
			armies_no_cmd.append(army)
	armies_no_cmd.sort_custom(func(a: ArmyState, b: ArmyState): return a.units.size() > b.units.size())
	for army in armies_no_cmd:
		if available.is_empty():
			break
		var cmd: CommanderState = available[0]
		GameManager.assign_commander_to_army(army.army_id, cmd.commander_id)
		available = GameManager.get_available_commanders(faction_id)

# ── AI Army Consolidation ────────────────────────────────────

func _consolidate_ai_armies(faction_id: StringName) -> void:
	# Merge armies that happen to share a tile (from spawning)
	var armies := GameManager.get_faction_armies(faction_id)
	if armies.size() <= 1:
		return

	var positions: Dictionary = {} # hex_pos -> Array[ArmyState]
	for army in armies:
		if not positions.has(army.hex_pos):
			positions[army.hex_pos] = []
		positions[army.hex_pos].append(army)
	for hex_pos in positions:
		if positions[hex_pos].size() > 1:
			GameManager.merge_armies_at_tile(hex_pos, faction_id)

# ── AI City Management ───────────────────────────────────────

func _execute_ai_city_management(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	# Per-faction building priorities — using each faction's own buildings
	var faction_build_priorities := {
		&"empire": [&"cohort_barracks", &"grain_fields", &"iron_pit", &"lumber_camp_empire", &"market_square", &"tavern", &"scriptorium_empire", &"village_gathering_place"],
		&"skulloath": [&"raiders_den", &"herders_camp", &"bone_workshop", &"ancestor_shrine", &"trade_post_skulloath", &"steppe_watchtower", &"blood_altar", &"pale_waif_altar", &"beast_pens"],
		&"gladehost": [&"ranger_outpost", &"harvest_clearing", &"rootwood_lodge", &"sacred_grove", &"seasonal_shrine", &"grove_ironworks", &"forest_market", &"embassy_grove", &"living_fortress", &"beastkeepers_glade"],
		&"tainted_jade": [&"serpent_pit", &"vine_shelter", &"jade_forge", &"root_altar", &"thrall_quarters", &"jade_market", &"jungle_traps", &"taint_suppressor", &"hunting_ground"],
		&"shardhorde": [&"crystal_nursery", &"shard_conduit", &"crystal_forge", &"shard_harvester", &"chitin_walls"],
	}
	var priority_list: Array = faction_build_priorities.get(faction_id, [&"cohort_barracks", &"grain_fields", &"iron_pit", &"market_square"])

	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue

		# Build buildings using upgrade-aware system
		if city.build_queue.is_empty():
			var available := GameManager.city_system.get_available_buildings(city)
			if available.size() > 0:
				var built := false
				for priority_id in priority_list:
					if built:
						break
					for b in available:
						if b.id == priority_id:
							GameManager.city_system.start_building(city_id, b.id)
							built = true
							break
				if not built:
					for b in available:
						if b.upgrades_from != &"":
							if GameManager.city_system.start_building(city_id, b.id):
								built = true
								break
				if not built:
					for b in available:
						if GameManager.city_system.start_building(city_id, b.id):
							break

		# Upgrade city when possible
		if city.upgrade_turns_remaining <= 0 and GameManager.city_system.can_start_upgrade(city):
			GameManager.city_system.start_upgrade(city_id)

		# Recruit units with threat-aware composition
		if city.recruit_queue.is_empty() and GameManager.city_system.get_province_population(city) > 120:
			_ai_recruit_with_composition(city, faction_id)

func _ai_recruit_with_composition(city: CityState, faction_id: StringName) -> void:
	# Count existing army composition
	var tag_counts := {"infantry": 0, "ranged": 0, "cavalry": 0, "mage": 0}
	var total_units := 0
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud:
				total_units += 1
				for tag in tag_counts:
					if ud.tags.has(tag):
						tag_counts[tag] += 1

	# Threat-relative recruitment: recruit if we have fewer units than any enemy at war
	var max_enemy_units := 0
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or GameManager.is_npc_faction(other_id):
			continue
		if GameManager.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
			continue
		var enemy_units := 0
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == other_id and not army.is_garrison:
				enemy_units += army.units.size()
		max_enemy_units = maxi(max_enemy_units, enemy_units)

	var recruit_threshold := maxi(8, max_enemy_units + 4)
	if total_units >= recruit_threshold:
		return

	# Determine what to recruit based on composition gaps
	# Target: ~60% infantry, ~25% ranged, ~15% cavalry/mage
	var needed_tag := "infantry"
	if total_units > 0:
		var inf_ratio := float(tag_counts.infantry) / float(total_units)
		var rng_ratio := float(tag_counts.ranged) / float(total_units)
		if inf_ratio >= 0.6 and rng_ratio < 0.25:
			needed_tag = "ranged"
		elif inf_ratio >= 0.6 and rng_ratio >= 0.25:
			needed_tag = "cavalry"

	# Find best unit matching the needed tag (walk upgrade chain for inherited unlocks)
	var best_unit_id: StringName = &""
	var best_score := 0
	for building_id in city.buildings:
		var current_id: StringName = building_id
		while current_id != &"":
			var building: BuildingData = DataManager.get_building(current_id)
			if building == null:
				break
			for uid in building.unlocks_units:
				var udata := DataManager.get_unit(uid)
				if udata == null or udata.faction_id != faction_id:
					continue
				var score := udata.attack + udata.defense
				if udata.tags.has(needed_tag):
					score += 20
				if score > best_score:
					best_score = score
					best_unit_id = uid
			current_id = building.upgrades_from

	if best_unit_id != &"":
		GameManager.city_system.start_recruitment(city.city_id, best_unit_id)

# ── AI Settlement Building ───────────────────────────────────

func _execute_ai_settlement_building(faction_id: StringName) -> void:
	if faction_id == &"shardhorde":
		return # Shardhorde uses elderbeasts, not settlements

	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	# Check if any capital can found a settlement
	if not GameManager.can_afford_settlement(faction_id):
		return

	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null or not city.is_capital or not city.can_found_settlement:
			continue

		# Check if we already have a pending target
		if _ai_settlement_targets.has(faction_id):
			var target_hex: Vector2i = _ai_settlement_targets[faction_id]
			# Check if any army is at the target
			var army_at := GameManager.get_army_at_tile(target_hex)
			if army_at and army_at.faction_id == faction_id:
				GameManager.found_settlement(faction_id, target_hex, city_id)
				_ai_settlement_targets.erase(faction_id)
				return
			# Otherwise move an army there
			var armies := GameManager.get_faction_armies(faction_id)
			if armies.size() > 0:
				var closest_army: ArmyState = null
				var closest_dist := 9999
				for army in armies:
					var d := HexHelper.hex_distance(army.hex_pos, target_hex)
					if d < closest_dist:
						closest_dist = d
						closest_army = army
				if closest_army and closest_army.movement_remaining > 0:
					var path := _ai_find_path(closest_army, target_hex, faction_id)
					if path.size() > 0:
						GameManager.move_army_along_path(closest_army.army_id, path)
			return

		# Evaluate best settlement tile (limit to 20 closest candidates)
		var valid_tiles := GameManager.city_system.get_valid_settlement_tiles(faction_id, city.region_id)
		if valid_tiles.is_empty():
			continue

		var capital_pos := city.hex_pos
		# Sort by distance and only evaluate closest 20
		valid_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return HexHelper.hex_distance(a, capital_pos) < HexHelper.hex_distance(b, capital_pos))
		var eval_count := mini(valid_tiles.size(), 20)

		var best_tile := Vector2i(-1, -1)
		var best_score := -999
		for i in eval_count:
			var tile_pos: Vector2i = valid_tiles[i]
			var income := GameManager.city_system.calculate_settlement_income_preview(tile_pos)
			var income_score := 0
			for res_type in income:
				income_score += income[res_type]
			var dist_penalty := HexHelper.hex_distance(capital_pos, tile_pos) * 2
			var total_score := income_score - dist_penalty
			if total_score > best_score:
				best_score = total_score
				best_tile = tile_pos

		if best_tile != Vector2i(-1, -1) and best_score > 5:
			_ai_settlement_targets[faction_id] = best_tile

# ── Empire/Default AI (Defend + Expand) ──────────────────────

func _execute_ai_turn(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Don't attack with tiny armies
		if army.units.size() < 3:
			# Move toward nearest friendly city to consolidate
			var nearest_city := _find_nearest_faction_city(army.hex_pos, faction_id)
			if nearest_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, nearest_city) > 1:
				var path := _ai_find_path(army, nearest_city, faction_id)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return
			continue

		# Find target: enemy armies first, then enemy regions
		var target_hex := _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			continue

		var path := _ai_find_path(army, target_hex, faction_id)
		if path.size() > 0:
			GameManager.move_army_along_path(army.army_id, path)
			if not GameManager.state.armies.has(army.army_id):
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return

	await get_tree().process_frame
	_end_current_faction_turn()

# ── Skulloath AI (Raider) ────────────────────────────────────

func _execute_skulloath_ai(faction_id: StringName) -> void:
	var cooldown: int = _ai_aggression_cooldown.get(faction_id, 0)
	if cooldown > 0:
		# Defensive phase: recruit, defend own cities, don't attack
		_ai_aggression_cooldown[faction_id] = cooldown - 1
		_execute_defensive_skulloath(faction_id)
		await get_tree().process_frame
		_end_current_faction_turn()
		return

	# Aggressive phase
	var armies := GameManager.get_faction_armies(faction_id)
	var attacked := false
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Small armies (< 3 units) retreat to nearest friendly city
		if army.units.size() < 3:
			_move_to_nearest_city(army, faction_id)
			continue

		# Attack with 3+ unit armies
		var target_hex := _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
		if target_hex != Vector2i(-1, -1):
			var path := _ai_find_path(army, target_hex, faction_id)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				attacked = true
				if not GameManager.state.armies.has(army.army_id):
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return

	# Track aggressive turns; after 3, enter cooldown
	if attacked:
		var atk_count: int = _ai_attack_counters.get(faction_id, 0) + 1
		_ai_attack_counters[faction_id] = atk_count
		if atk_count >= 3:
			_ai_aggression_cooldown[faction_id] = 4
			_ai_attack_counters[faction_id] = 0

	await get_tree().process_frame
	_end_current_faction_turn()

func _execute_defensive_skulloath(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue
		# Move to nearest friendly city to defend
		_move_to_nearest_city(army, faction_id)

func _move_to_nearest_city(army: ArmyState, faction_id: StringName) -> void:
	var nearest_city := _find_nearest_faction_city(army.hex_pos, faction_id)
	if nearest_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, nearest_city) > 1:
		var path := _ai_find_path(army, nearest_city, faction_id)
		if path.size() > 0:
			GameManager.move_army_along_path(army.army_id, path)

# ── Gladehost AI (Defensive Patrol) ──────────────────────────

func _execute_gladehost_ai(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)

	# Check for intruders first
	var intruder := _find_nearest_intruder(faction_id, 3)

	for army in armies:
		if army.movement_remaining <= 0:
			continue

		if intruder != Vector2i(-1, -1):
			# Attack intruder
			var path := _ai_find_path(army, intruder, faction_id)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					_gladehost_waypoints.erase(army.army_id)
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return
		else:
			# Patrol between settlements
			if not _gladehost_waypoints.has(army.army_id):
				_gladehost_waypoints[army.army_id] = {
					"waypoints": _build_gladehost_patrol(faction_id),
					"index": 0,
				}
			var wp_data: Dictionary = _gladehost_waypoints[army.army_id]
			var waypoints: Array = wp_data["waypoints"]
			if waypoints.is_empty():
				continue
			var target: Vector2i = waypoints[wp_data["index"]]
			if army.hex_pos == target or HexHelper.hex_distance(army.hex_pos, target) <= 1:
				wp_data["index"] = (wp_data["index"] + 1) % waypoints.size()
				target = waypoints[wp_data["index"]]
			var path := _ai_find_path(army, target, faction_id)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					_gladehost_waypoints.erase(army.army_id)
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return

	await get_tree().process_frame
	_end_current_faction_turn()

func _build_gladehost_patrol(faction_id: StringName) -> Array:
	var waypoints: Array = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				waypoints.append(city.hex_pos)
	var borders := _get_faction_border_tiles(faction_id)
	if borders.size() > 0:
		var step := maxi(1, borders.size() / 3)
		for i in range(0, borders.size(), step):
			waypoints.append(borders[i])
	return waypoints

# ── Tainted Jade AI (Aggressive Expansion) ───────────────────

func _execute_tainted_jade_ai(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Build up to 4+ units before attacking
		if army.units.size() < 4:
			var nearest_city := _find_nearest_faction_city(army.hex_pos, faction_id)
			if nearest_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, nearest_city) > 1:
				var path := _ai_find_path(army, nearest_city, faction_id)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						_jade_patrol_index.erase(army.army_id)
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return
			continue

		# Actively seek to conquer
		var intruder := _find_nearest_intruder(faction_id, 3)
		if intruder != Vector2i(-1, -1):
			var path := _ai_find_path(army, intruder, faction_id)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return
		else:
			# Expand toward enemy regions
			var target_hex := _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
			if target_hex == Vector2i(-1, -1):
				# Patrol border
				var borders := _get_faction_border_tiles(faction_id)
				if borders.is_empty():
					continue
				if not _jade_patrol_index.has(army.army_id):
					_jade_patrol_index[army.army_id] = 0
				var idx: int = _jade_patrol_index[army.army_id]
				target_hex = borders[idx % borders.size()]
				if army.hex_pos == target_hex or HexHelper.hex_distance(army.hex_pos, target_hex) <= 1:
					idx = (idx + 1) % borders.size()
					_jade_patrol_index[army.army_id] = idx
					target_hex = borders[idx]

			if target_hex != Vector2i(-1, -1):
				var path := _ai_find_path(army, target_hex, faction_id)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						_jade_patrol_index.erase(army.army_id)
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return

	await get_tree().process_frame
	_end_current_faction_turn()

# ── Shardhorde AI (Nomadic) ──────────────────────────────────

func _execute_shardhorde_ai() -> void:
	var faction_id := &"shardhorde"

	# Elderbeasts move WITH their armies — level up based on survival
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != faction_id:
			continue
		beast.survival_turns += 1
		if beast.level < 3:
			if (beast.level == 1 and beast.survival_turns >= 10) or \
			   (beast.level == 2 and beast.survival_turns >= 25):
				beast.level += 1
				beast.apply_level_stats()
				_sync_elderbeast_unit_data(beast)

	# Move armies (elderbeasts attached to armies move automatically via move_army_along_path)
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Armies with elderbeasts prefer shard wastes / desert tiles
		var has_beast := army.elderbeast_id != &""

		# Attack nearby enemies
		var target_hex := _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex != Vector2i(-1, -1):
			# Armies with beasts attack within 6 hexes, raiding armies go further
			var max_range := 6 if has_beast else 10
			if HexHelper.hex_distance(army.hex_pos, target_hex) <= max_range:
				var path := _ai_find_path(army, target_hex, faction_id)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return
				continue

		# Beast armies wander toward shard wastes
		if has_beast:
			_move_beast_army_toward_wastes(army)
		else:
			# Raiding armies without beasts seek enemies or wander
			var nearest_beast_pos := _get_nearest_beast_pos(army.hex_pos)
			if nearest_beast_pos != Vector2i(-1, -1):
				var dist := HexHelper.hex_distance(army.hex_pos, nearest_beast_pos)
				if dist > 5:
					var path := _ai_find_path(army, nearest_beast_pos, faction_id)
					if path.size() > 0:
						GameManager.move_army_along_path(army.army_id, path)
						if not GameManager.state.armies.has(army.army_id):
							continue
						if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
							return

	# Build on elderbeasts
	_shardhorde_ai_build()

	# Recruit at elderbeasts
	_shardhorde_recruit()

	await get_tree().process_frame
	_end_current_faction_turn()

func _move_beast_army_toward_wastes(army: ArmyState) -> void:
	# Move the army (and its attached elderbeast) toward shard wastes / desert
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var neighbors := HexHelper.get_neighbors(army.hex_pos)
	var best_hex := army.hex_pos
	var best_score := -999

	for n in neighbors:
		if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(n)
		if tile == null or tile.terrain == Enums.TerrainType.WATER:
			continue
		var score := 0
		if tile.terrain == Enums.TerrainType.SHARD_WASTES:
			score += 5
		elif tile.terrain == Enums.TerrainType.DESERT:
			score += 3
		elif tile.terrain == Enums.TerrainType.PLAINS:
			score += 1
		# Avoid hostile faction territory
		if tile.owner_faction != &"" and tile.owner_faction != &"shardhorde":
			var relation := GameManager.get_relation(&"shardhorde", tile.owner_faction)
			if relation == Enums.FactionRelation.WAR:
				score -= 10
		score += randi() % 3
		if score > best_score:
			best_score = score
			best_hex = n

	if best_hex != army.hex_pos:
		var path: Array[Vector2i] = [best_hex]
		GameManager.move_army_along_path(army.army_id, path)

func _get_nearest_beast_pos(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 9999
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		var d := HexHelper.hex_distance(from, beast.hex_pos)
		if d < best_dist:
			best_dist = d
			best = beast.hex_pos
	return best

# Terrain requirements for Shardhorde beast buildings (mirrors campaign_hud constant)
const _AI_BEAST_TERRAIN := {
	&"shard_conduit": [Enums.TerrainType.PLAINS, Enums.TerrainType.FOREST, Enums.TerrainType.JUNGLE, Enums.TerrainType.SWAMP],
	&"shard_harvester": [Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.DESERT, Enums.TerrainType.MOUNTAINS],
	&"crystal_forge": [Enums.TerrainType.MOUNTAINS, Enums.TerrainType.FOREST],
	&"resonance_core": [Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.DESERT],
	&"resonance_amplifier": [Enums.TerrainType.SHARD_WASTES],
}

# AI building priority: military first to unlock units, then economic
const _AI_BEAST_BUILD_PRIORITY := [
	&"crystal_nursery", &"shard_harvester", &"shard_conduit", &"crystal_forge",
	&"chitin_walls", &"hive_spire", &"resonance_core",
	&"elder_breeding_ground", &"resonance_amplifier",
]

func _shardhorde_ai_build() -> void:
	var fs: FactionState = GameManager.state.faction_states.get(&"shardhorde")
	if fs == null:
		return
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		if beast.build_queue.size() > 0 or beast.get_available_building_slots() <= 0:
			continue
		# Get nearby terrains
		var nearby_terrains: Array[int] = []
		var tiles := _get_beast_tiles(beast)
		for tile_pos in tiles:
			var tile := GameManager.state.hex_map.get_tile(tile_pos)
			if tile and not nearby_terrains.has(tile.terrain):
				nearby_terrains.append(tile.terrain)
		# Try buildings in priority order
		for bid in _AI_BEAST_BUILD_PRIORITY:
			if beast.buildings.has(bid):
				continue
			var building: BuildingData = DataManager.get_building(bid)
			if building == null:
				continue
			if building.required_capital_level > beast.level:
				continue
			if building.upgrades_from != &"" and not beast.buildings.has(building.upgrades_from):
				continue
			var terrain_req: Array = _AI_BEAST_TERRAIN.get(bid, [])
			if terrain_req.size() > 0:
				var ok := false
				for t in terrain_req:
					if nearby_terrains.has(t):
						ok = true
						break
				if not ok:
					continue
			if not _can_afford_faction(fs, building.build_cost):
				continue
			_deduct_faction_cost(fs, building.build_cost)
			beast.build_queue.append({building_id = bid, turns_remaining = building.build_time})
			break

func _shardhorde_recruit() -> void:
	var fs: FactionState = GameManager.state.faction_states.get(&"shardhorde")
	if fs == null:
		return
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		if beast.recruit_queue.size() > 0:
			# Process queue
			var item: Dictionary = beast.recruit_queue[0]
			item.turns_remaining -= 1
			if item.turns_remaining <= 0:
				var unit_data_id: StringName = item.unit_data_id
				beast.recruit_queue.remove_at(0)
				# Spawn unit at beast location
				_spawn_unit_at_hex(unit_data_id, &"shardhorde", beast.hex_pos)
			continue
		# Recruit based on beast level and available buildings
		var recruit_pool: Array[StringName] = [&"crystal_swarmling"]
		for building_id in beast.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building and building.unlocks_units.size() > 0:
				for uid in building.unlocks_units:
					if not recruit_pool.has(uid):
						recruit_pool.append(uid)
		# Unit unlocks come entirely from buildings — no level-based overrides
		# Pick the best affordable unit
		var best_uid: StringName = &""
		var best_score := 0
		for uid in recruit_pool:
			var udata := DataManager.get_unit(uid)
			if udata == null:
				continue
			if not _can_afford_faction(fs, udata.recruit_cost):
				continue
			var score := udata.attack + udata.defense
			if score > best_score:
				best_score = score
				best_uid = uid
		if best_uid == &"":
			# Fall back to cheapest
			for uid in recruit_pool:
				var udata := DataManager.get_unit(uid)
				if udata and _can_afford_faction(fs, udata.recruit_cost):
					best_uid = uid
					break
		if best_uid != &"":
			var udata := DataManager.get_unit(best_uid)
			_deduct_faction_cost(fs, udata.recruit_cost)
			beast.recruit_queue.append({unit_data_id = best_uid, turns_remaining = udata.recruit_time})

func _spawn_unit_at_hex(unit_data_id: StringName, faction_id: StringName, hex_pos: Vector2i) -> void:
	var unit_data := DataManager.get_unit(unit_data_id)
	if unit_data == null:
		return
	var instance := UnitInstance.new()
	instance.init_from_data(unit_data, GameManager.state.generate_id())
	# Find existing army at hex
	var existing: ArmyState = null
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.hex_pos == hex_pos and army.faction_id == faction_id:
			existing = army
			break
	if existing:
		existing.units.append(instance)
	else:
		var army := ArmyState.new()
		army.army_id = GameManager.state.generate_id()
		army.faction_id = faction_id
		army.hex_pos = hex_pos
		army.units.append(instance)
		army.movement_remaining = army.get_max_movement()
		GameManager.state.armies[army.army_id] = army

# ── Elderbeast Processing ────────────────────────────────────

func _sync_elderbeast_hp_to_unit(beast: ElderbeastState) -> void:
	# Keep the UnitInstance in the army in sync with beast HP
	if beast.escort_army_id == &"" or beast.unit_instance_id == &"":
		return
	var army: ArmyState = GameManager.state.armies.get(beast.escort_army_id)
	if army == null:
		return
	for unit in army.units:
		if unit.instance_id == beast.unit_instance_id:
			unit.current_hp = beast.hp
			break

func _sync_elderbeast_unit_data(beast: ElderbeastState) -> void:
	# Update the UnitInstance in the escort army when beast levels up
	if beast.escort_army_id == &"" or beast.unit_instance_id == &"":
		return
	var army: ArmyState = GameManager.state.armies.get(beast.escort_army_id)
	if army == null:
		return
	for unit in army.units:
		if unit.instance_id == beast.unit_instance_id:
			unit.unit_data_id = beast.get_unit_data_id()
			# Keep current HP (don't reset to max on level up)
			break

func _process_elderbeasts() -> void:
	var fs: FactionState = GameManager.state.faction_states.get(&"shardhorde")
	if fs == null:
		return

	# Collect all tiles currently in range of any beast (for depletion recovery)
	var active_tiles: Dictionary = {} # Vector2i -> true
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		active_tiles[beast.hex_pos] = true
		for n in HexHelper.get_neighbors(beast.hex_pos):
			if HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				active_tiles[n] = true

	var current_turn: int = GameManager.state.current_turn

	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue

		# Decrement injured timer
		if beast.injured_turns > 0:
			beast.injured_turns -= 1

		# Generate income BEFORE incrementing depletion (so turn 1 starts at full yield)
		var income := _get_elderbeast_income(beast)
		for res_type in income:
			fs.resources[res_type] = fs.resources.get(res_type, 0) + income[res_type]

		# Increment depletion for tiles in range (after income so first turn is unpenalized)
		var tiles_in_range := _get_beast_tiles(beast)
		for tile_pos in tiles_in_range:
			beast.tile_depletion[tile_pos] = beast.tile_depletion.get(tile_pos, 0) + 1

		# Recover depletion for tiles NOT in range of any beast
		# Only recover every 2 turns so depleted tiles take ~12 turns to regenerate
		if current_turn % 2 == 0:
			var keys_to_check: Array = beast.tile_depletion.keys()
			for tile_pos in keys_to_check:
				if not active_tiles.has(tile_pos):
					beast.tile_depletion[tile_pos] = maxi(0, beast.tile_depletion[tile_pos] - 1)
					if beast.tile_depletion[tile_pos] <= 0:
						beast.tile_depletion.erase(tile_pos)

		# Population growth
		beast.population += 3

		# Process building queue
		if beast.build_queue.size() > 0:
			var item: Dictionary = beast.build_queue[0]
			item.turns_remaining -= 1
			if item.turns_remaining <= 0:
				var building_id: StringName = item.building_id
				beast.build_queue.remove_at(0)
				beast.buildings.append(building_id)
				EventBus.building_completed.emit(beast.beast_id, building_id)

		# Sync elderbeast HP to its UnitInstance
		_sync_elderbeast_hp_to_unit(beast)

		# Reset movement (injured beasts get 0)
		beast.movement_remaining = beast.get_max_movement()
		beast.has_moved = false

# Terrain-based income yields per tile type
const TERRAIN_INCOME := {
	Enums.TerrainType.PLAINS: {Enums.ResourceType.FOOD: 2, Enums.ResourceType.GOLD: 1},
	Enums.TerrainType.FOREST: {Enums.ResourceType.FOOD: 1, Enums.ResourceType.WOOD: 2},
	Enums.TerrainType.MOUNTAINS: {Enums.ResourceType.IRON: 2, Enums.ResourceType.GOLD: 1},
	Enums.TerrainType.DESERT: {Enums.ResourceType.GOLD: 1, Enums.ResourceType.SHARD_ESSENCE: 1},
	Enums.TerrainType.SWAMP: {Enums.ResourceType.FOOD: 1, Enums.ResourceType.CAPTIVES: 1},
	Enums.TerrainType.WETLANDS: {Enums.ResourceType.GOLD: 2, Enums.ResourceType.FOOD: 1},
	Enums.TerrainType.TUNDRA: {Enums.ResourceType.IRON: 1, Enums.ResourceType.FOOD: 1},
	Enums.TerrainType.SHARD_WASTES: {Enums.ResourceType.SHARD_ESSENCE: 3},
	Enums.TerrainType.JUNGLE: {Enums.ResourceType.FOOD: 2, Enums.ResourceType.WOOD: 1},
	# WATER: nothing
}

func _get_beast_tiles(beast: ElderbeastState) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [beast.hex_pos]
	for n in HexHelper.get_neighbors(beast.hex_pos):
		if HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			tiles.append(n)
	return tiles

const ELDERBEAST_BASE_INCOME := {
	1: {Enums.ResourceType.GOLD: 6, Enums.ResourceType.FOOD: 8, Enums.ResourceType.WOOD: 3},
	2: {Enums.ResourceType.GOLD: 11, Enums.ResourceType.FOOD: 15, Enums.ResourceType.WOOD: 6},
	3: {Enums.ResourceType.GOLD: 19, Enums.ResourceType.FOOD: 25, Enums.ResourceType.WOOD: 10},
}

func _get_elderbeast_income(beast: ElderbeastState) -> Dictionary:
	var income: Dictionary = {}
	# Base income (scales with level, not affected by depletion)
	var base: Dictionary = ELDERBEAST_BASE_INCOME.get(beast.level, ELDERBEAST_BASE_INCOME[1])
	for res_type in base:
		income[res_type] = income.get(res_type, 0) + base[res_type]
	# Terrain-based income from beast hex + 6 neighbors
	var tiles := _get_beast_tiles(beast)
	for tile_pos in tiles:
		var tile := GameManager.state.hex_map.get_tile(tile_pos)
		if tile == null:
			continue
		var yields: Dictionary = TERRAIN_INCOME.get(tile.terrain, {})
		var mult: float = beast.get_depletion_multiplier(tile_pos)
		for res_type in yields:
			income[res_type] = income.get(res_type, 0) + maxi(1, roundi(yields[res_type] * mult))

	# Building income bonuses (full value, not halved — terrain is the base now)
	for building_id in beast.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		for res_type in building.income_bonus:
			income[res_type] = income.get(res_type, 0) + building.income_bonus[res_type]

	# Debt penalty: 66% income when faction gold is negative
	var fs: FactionState = GameManager.state.faction_states.get(beast.faction_id)
	if fs and fs.resources.get(Enums.ResourceType.GOLD, 0) < 0:
		for res_type in income:
			income[res_type] = int(income[res_type] * 0.66)

	return income

# ── Healing & Replenishment ──────────────────────────────────

func _heal_armies_in_settlements(faction_id: StringName) -> void:
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue

		var city_at := GameManager.city_system.get_city_at_hex(army.hex_pos)
		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)

		# Commander heal bonus
		var cmd_heal := 0
		if army.commander:
			var bonuses := CommanderSystem.get_commander_army_bonuses(army.commander)
			cmd_heal = bonuses.get("heal_per_turn", 0)

		if city_at and city_at.faction_id == faction_id:
			# Moonwell: armies at Gladehost cities with moonwell heal 50% faster
			var moonwell_mult := 1.0
			if city_at.buildings.has(&"moonwell"):
				moonwell_mult = 1.5
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.15 * moonwell_mult) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
				if unit_data.squad_size > 1 and unit_data.hp_per_soldier > 0:
					if unit.current_hp < unit_data.max_hp:
						unit.current_hp = mini(unit.current_hp + unit_data.hp_per_soldier, unit_data.max_hp)
		elif tile and tile.owner_faction == faction_id:
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.05) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
		elif faction_id == &"shardhorde" and _is_in_undepleted_beast_range(army.hex_pos):
			# Shardhorde armies regenerate troops in undepleted elderbeast territory
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.10) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
		elif cmd_heal > 0:
			# Commander heals even in neutral territory
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				unit.current_hp = mini(unit.current_hp + cmd_heal, unit_data.max_hp)

func _is_in_undepleted_beast_range(hex_pos: Vector2i) -> bool:
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		if HexHelper.hex_distance(hex_pos, beast.hex_pos) <= 1:
			if beast.get_depletion_multiplier(hex_pos) >= 0.75:
				return true
	return false

# ── Terrain Attrition ───────────────────────────────────────

func _apply_terrain_attrition(faction_id: StringName) -> void:
	var fd: FactionData = DataManager.get_faction(faction_id)
	var is_nature := fd and fd.realm_affinity == Enums.Realm.NATURE
	var is_void := fd and fd.realm_affinity == Enums.Realm.VOID

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id or army.is_garrison:
			continue

		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
		if tile == null:
			continue

		# Skip attrition in cities (sheltered)
		if GameManager.city_system.get_city_at_hex(army.hex_pos) != null:
			continue

		match tile.terrain:
			Enums.TerrainType.SHARD_WASTES:
				# Light damage to all — void-aligned take less
				var dmg_pct := 0.02 if is_void else 0.05
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						var dmg := maxi(1, int(ud.max_hp * dmg_pct))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.DESERT:
				# Moderate damage — void-aligned take less, nature takes more
				var dmg_pct := 0.03
				if is_void:
					dmg_pct = 0.01
				elif is_nature:
					dmg_pct = 0.05
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						var dmg := maxi(1, int(ud.max_hp * dmg_pct))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.JUNGLE:
				# Nature-aligned units heal, others take upkeep penalty
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud == null:
						continue
					if is_nature:
						# Heal 3% max HP
						var heal := maxi(1, int(ud.max_hp * 0.03))
						unit.current_hp = mini(unit.current_hp + heal, ud.max_hp)
					else:
						# Non-nature: light damage from hostile vegetation
						var dmg := maxi(1, int(ud.max_hp * 0.02))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.TUNDRA:
				# Cold attrition — light damage, nature-aligned take more
				var dmg_pct := 0.02
				if is_nature:
					dmg_pct = 0.04
				elif is_void:
					dmg_pct = 0.01
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						var dmg := maxi(1, int(ud.max_hp * dmg_pct))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.SWAMP:
				# Disease attrition — hurts everyone except constructs
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud and not ud.tags.has("construct"):
						var dmg := maxi(1, int(ud.max_hp * 0.03))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

	# Remove dead units (HP <= 0 shouldn't happen since we floor at 1, but clean up 0-hp units)
	_clean_dead_units(faction_id)

func _clean_dead_units(faction_id: StringName) -> void:
	var armies_to_remove: Array[StringName] = []
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue
		# Remove units at 1 HP that would realistically be dead from sustained attrition
		# (units don't die from attrition alone — they just get weakened)
	# No auto-removal: attrition weakens but doesn't kill. Units die in battle.

# ── Terrain Upkeep Modifier ─────────────────────────────────

func get_terrain_upkeep_modifier(army: ArmyState) -> float:
	# Returns a multiplier for upkeep cost based on army terrain
	var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
	if tile == null:
		return 1.0

	var fd: FactionData = DataManager.get_faction(army.faction_id)
	var is_nature := fd and fd.realm_affinity == Enums.Realm.NATURE

	match tile.terrain:
		Enums.TerrainType.JUNGLE:
			return 0.8 if is_nature else 1.3 # Nature saves, others pay more
		Enums.TerrainType.DESERT:
			return 1.2 # Everyone pays more in desert (water/supply issues)
		Enums.TerrainType.SHARD_WASTES:
			return 1.25 # Hazardous environment
		Enums.TerrainType.MOUNTAINS:
			return 1.15 # Difficult supply lines
		Enums.TerrainType.TUNDRA:
			return 1.2 # Cold requires more supplies
		Enums.TerrainType.SWAMP:
			return 1.15

	return 1.0

# ── Random Events ────────────────────────────────────────────

const RANDOM_EVENTS := [
	{
		"title": "Wandering Merchant",
		"text": "A mysterious merchant offers rare goods at a fair price.",
		"choice_a": "Buy (50 Gold)",
		"choice_b": "Decline",
		"type": "merchant",
		"stage": "early",
	},
	{
		"title": "Ancient Ruins",
		"text": "Your scouts discovered ancient ruins. Exploring them could yield treasure, but not without risk.",
		"choice_a": "Explore (risk 20% HP)",
		"choice_b": "Leave them be",
		"type": "ruins",
		"stage": "early",
	},
	{
		"title": "Deserters",
		"text": "A group of deserters offers to join your ranks, but their loyalty is questionable.",
		"choice_a": "Accept (free unit)",
		"choice_b": "Turn them away",
		"type": "deserters",
		"stage": "mid",
	},
	{
		"title": "Mysterious Stranger",
		"text": "A cloaked figure offers wisdom to your commander in exchange for nothing... or so they claim.",
		"choice_a": "Accept wisdom (+30 XP)",
		"choice_b": "Take gold instead (+40 Gold)",
		"type": "stranger",
		"stage": "early",
	},
	{
		"title": "Sacred Grove",
		"text": "Your army discovers a sacred grove radiating with healing energy.",
		"choice_a": "Bless commander (heal bonus)",
		"choice_b": "Bless city (growth bonus)",
		"type": "grove",
		"stage": "early",
	},
	{
		"title": "Border Dispute",
		"text": "A neighboring faction's emissary arrives with an offer of goodwill.",
		"choice_a": "Accept friendship (+5 standing)",
		"choice_b": "Demand tribute (+30 Iron, -10 standing)",
		"type": "dispute",
		"stage": "mid",
		"requires_weak_neighbor": true,
	},
	{
		"title": "Loyal Follower",
		"text": "A skilled individual pledges service to your cause.",
		"choice_a": "Accept follower",
		"choice_b": "Decline",
		"type": "follower",
		"stage": "early",
	},
	# New events below
	{
		"title": "Plague Outbreak",
		"text": "A plague has broken out in one of your cities, threatening the population.",
		"choice_a": "Quarantine (-20 Food, save pop)",
		"choice_b": "Ignore (spread risk, -30 pop)",
		"type": "plague",
		"stage": "mid",
	},
	{
		"title": "Mercenary Company",
		"text": "A band of mercenaries offers their services. Pay them, or they'll raid your lands.",
		"choice_a": "Hire (100 Gold, +2 units)",
		"choice_b": "Refuse (lose 20 Gold to raids)",
		"type": "mercenary",
		"stage": "mid",
	},
	{
		"title": "Shard Storm",
		"text": "A violent shard storm sweeps the wastes, energizing the ley lines.",
		"choice_a": "Send scouts (+15 Shard Essence)",
		"choice_b": "Stay safe (no risk)",
		"type": "shard_storm",
		"stage": "late",
	},
	{
		"title": "Trade Caravan",
		"text": "A trade caravan passes through your territory, offering lucrative deals.",
		"choice_a": "Trade fairly (+50 Gold, +20 Food)",
		"choice_b": "Raid caravan (+80 Gold, -standing)",
		"type": "trade_caravan",
		"stage": "early",
	},
	{
		"title": "Spy Report",
		"text": "Your spies have gathered intelligence on enemy movements.",
		"choice_a": "Use intelligence (reveal enemies)",
		"choice_b": "Sell intelligence (+60 Gold)",
		"type": "spy_report",
		"stage": "mid",
	},
	{
		"title": "Natural Disaster",
		"text": "An earthquake has damaged buildings in one of your cities.",
		"choice_a": "Rebuild (-60 Gold, -20 Wood)",
		"choice_b": "Relocate population (-30 pop)",
		"type": "disaster",
		"stage": "mid",
	},
	{
		"title": "Religious Revival",
		"text": "A wave of spiritual fervor sweeps through your realm.",
		"choice_a": "Embrace it (+20 Tech, divine)",
		"choice_b": "Channel it (+10 Loyalty)",
		"type": "revival",
		"stage": "mid",
	},
	{
		"title": "Tax Revolt",
		"text": "The peasants are refusing to pay taxes, threatening unrest.",
		"choice_a": "Concessions (+15 Loyalty, -40 Gold)",
		"choice_b": "Crackdown (-10 Loyalty, +5 Captives)",
		"type": "tax_revolt",
		"stage": "mid",
	},
	{
		"title": "Legendary Commander",
		"text": "A renowned military leader seeks to join your cause.",
		"choice_a": "Accept commander (+XP bonus)",
		"choice_b": "Sell services (+80 Gold)",
		"type": "legendary_commander",
		"stage": "late",
	},
	{
		"title": "Ancient Artifact",
		"text": "An artifact of great power has been unearthed. Its origins are... questionable.",
		"choice_a": "Keep it (risk: -5 all loyalty)",
		"choice_b": "Destroy for knowledge (+40 Tech)",
		"type": "artifact",
		"stage": "late",
	},
	{
		"title": "Beast Migration",
		"text": "Wild beasts are migrating toward one of your cities.",
		"choice_a": "Defend (+20 XP to army)",
		"choice_b": "Pay tribute (-30 Food)",
		"type": "beast_migration",
		"stage": "mid",
	},
	{
		"title": "Harvest Festival",
		"text": "A bountiful harvest brings joy and celebration to your people.",
		"choice_a": "Celebrate (+30 Food, +10 Loyalty)",
		"choice_b": "Celebrate",
		"type": "harvest",
		"stage": "early",
	},
	{
		"title": "Diplomatic Marriage",
		"text": "A noble family from a neighboring faction proposes a political marriage.",
		"choice_a": "Accept (+15 standing)",
		"choice_b": "Decline (+5 noble loyalty)",
		"type": "diplomatic_marriage",
		"stage": "mid",
	},
]

func _check_random_events(faction_id: StringName) -> void:
	if GameManager.state.current_turn <= 1:
		return
	# Cooldown: no events within 3 turns of each other
	if _event_cooldown > 0:
		_event_cooldown -= 1
		return
	if randf() > 0.12:
		return # 12% chance per turn

	# Weight events by game stage
	var turn := GameManager.state.current_turn
	var stage_preference: String
	if turn <= 10:
		stage_preference = "early"
	elif turn <= 30:
		stage_preference = "mid"
	else:
		stage_preference = "late"

	# Find a weaker non-war neighbor (for events that need one)
	var weak_neighbor_id: StringName = _find_weak_neighbor(faction_id)

	# Build weighted pool
	var weighted_pool: Array[Dictionary] = []
	for ev in RANDOM_EVENTS:
		# Skip events requiring a weak neighbor if none exists
		if ev.get("requires_weak_neighbor", false) and weak_neighbor_id == &"":
			continue
		var ev_stage: String = ev.get("stage", "early")
		if ev_stage == stage_preference:
			weighted_pool.append(ev)
			weighted_pool.append(ev) # Double weight for matching stage
		else:
			weighted_pool.append(ev)

	if weighted_pool.is_empty():
		return

	var event: Dictionary = weighted_pool[randi() % weighted_pool.size()].duplicate()
	event["faction_id"] = faction_id
	event["selected_army_id"] = GameManager.state.selected_army_id

	# Inject target faction for dispute events
	if event.get("requires_weak_neighbor", false) and weak_neighbor_id != &"":
		event["target_faction_id"] = weak_neighbor_id
		var target_fd: FactionData = DataManager.get_faction(weak_neighbor_id)
		var target_name: String = target_fd.display_name if target_fd else str(weak_neighbor_id)
		event["text"] = "An emissary from %s arrives at your border, seeking to negotiate." % target_name
		event["choice_b"] = "Demand tribute from %s (+30 Iron, -10 standing)" % target_name

	_event_cooldown = 3
	EventBus.random_event_triggered.emit(event)

func _find_weak_neighbor(faction_id: StringName) -> StringName:
	var my_strength := GameManager.diplomacy_system._calculate_faction_strength(faction_id)
	var candidates: Array[StringName] = []
	for fid in GameManager.state.faction_states:
		if fid == faction_id or GameManager.is_npc_faction(fid):
			continue
		var fs: FactionState = GameManager.state.faction_states[fid]
		if fs.is_defeated:
			continue
		var relation := GameManager.get_relation(faction_id, fid)
		if relation == Enums.FactionRelation.WAR:
			continue
		var their_strength := GameManager.diplomacy_system._calculate_faction_strength(fid)
		if their_strength < my_strength:
			candidates.append(fid)
	if candidates.is_empty():
		return &""
	return candidates[randi() % candidates.size()]

func apply_random_event_choice(event: Dictionary, choice: String) -> String:
	var faction_id: StringName = event.get("faction_id", &"")
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return "Nothing happened."

	var event_type: String = event.get("type", "")
	match event_type:
		"merchant":
			if choice == "a":
				if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 50:
					fs.resources[Enums.ResourceType.GOLD] -= 50
					var armies := GameManager.get_faction_armies(faction_id)
					for army in armies:
						var max_slots := CommanderSystem.get_max_item_slots(army.commander) if army.commander else 0
						if army.commander and army.commander.items.size() < max_slots:
							var item_name := CommanderSystem.apply_item_drop(army.commander, faction_id)
							if item_name != "":
								return "Spent 50 Gold. Acquired: %s" % item_name
							return "Spent 50 Gold but the merchant had nothing worthwhile."
					return "Spent 50 Gold but no commander could carry the goods."
				else:
					return "Not enough gold! (need 50)"
			return "The merchant moves on."
		"ruins":
			if choice == "a":
				var armies := GameManager.get_faction_armies(faction_id)
				if armies.size() > 0:
					for unit in armies[0].units:
						var ud := DataManager.get_unit(unit.unit_data_id)
						if ud:
							unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * 0.2))
					if randf() < 0.6 and armies[0].commander:
						var item_name := CommanderSystem.apply_item_drop(armies[0].commander, &"")
						if item_name != "":
							return "Army took 20%% HP damage. Found: %s" % item_name
					return "Army took 20%% HP damage. The ruins held nothing of value."
				return "No army available to explore."
			return "You leave the ruins undisturbed."
		"deserters":
			if choice == "a":
				var armies := GameManager.get_faction_armies(faction_id)
				if armies.size() > 0:
					var unit_id := &"legionary"
					if faction_id == &"skulloath":
						unit_id = &"warband_raider"
					elif faction_id == &"gladehost":
						unit_id = &"grove_warden"
					elif faction_id == &"tainted_jade":
						unit_id = &"jade_fang"
					var ud: UnitData = DataManager.get_unit(unit_id)
					var unit_name: String = ud.display_name if ud else str(unit_id)
					_spawn_unit_at_hex(unit_id, faction_id, armies[0].hex_pos)
					return "Gained unit: %s" % unit_name
				return "No army to receive the deserters."
			return "The deserters wander off."
		"stranger":
			if choice == "a":
				var target_cmd: CommanderState = null
				var sel_id: StringName = event.get("selected_army_id", &"")
				if sel_id != &"" and GameManager.state.armies.has(sel_id):
					var sel_army: ArmyState = GameManager.state.armies[sel_id]
					if sel_army.commander:
						target_cmd = sel_army.commander
				if target_cmd == null:
					var armies := GameManager.get_faction_armies(faction_id)
					for army in armies:
						if army.commander:
							target_cmd = army.commander
							break
				if target_cmd:
					target_cmd.xp += 30
					CommanderSystem._check_level_up(target_cmd)
					return "%s gained +30 XP (now %d XP)" % [target_cmd.name, target_cmd.xp]
				return "No commander to receive the wisdom."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 40
				return "Received +40 Gold (now %d)" % fs.resources.get(Enums.ResourceType.GOLD, 0)
		"grove":
			if choice == "a":
				_temp_effects.append({
					"faction_id": faction_id,
					"effect": "heal_bonus",
					"value": 5,
					"turns_remaining": 10,
				})
				return "Healing Blessing: +5 HP/turn for all armies (10 turns)"
			else:
				_temp_effects.append({
					"faction_id": faction_id,
					"effect": "growth_bonus",
					"value": 3,
					"turns_remaining": 10,
				})
				return "Growth Blessing: +3 population growth in all cities (10 turns)"
		"dispute":
			var target_fid: StringName = event.get("target_faction_id", &"")
			var target_fd: FactionData = DataManager.get_faction(target_fid) if target_fid != &"" else null
			var target_name: String = target_fd.display_name if target_fd else "a neighboring faction"
			if choice == "a":
				if target_fid != &"":
					GameManager.diplomacy_system.modify_standing(faction_id, target_fid, 5)
				return "Relations improved with %s. (+5 standing)" % target_name
			else:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 30
				if target_fid != &"":
					GameManager.diplomacy_system.modify_standing(faction_id, target_fid, -10)
				return "Demanded tribute from %s. +30 Iron, -10 standing with %s." % [target_name, target_name]

		"follower":
			if choice == "a":
				var all_followers := DataManager.followers.keys()
				if all_followers.is_empty():
					return "No followers available."
				var follower_id: StringName = all_followers[randi() % all_followers.size()]
				var follower: FollowerData = DataManager.get_follower(follower_id)
				if follower == null:
					return "No followers available."
				var target_cmd: CommanderState = null
				var sel_id: StringName = event.get("selected_army_id", &"")
				if sel_id != &"" and GameManager.state.armies.has(sel_id):
					var sel_army: ArmyState = GameManager.state.armies[sel_id]
					if sel_army.commander and sel_army.commander.followers.size() < CommanderSystem.get_max_follower_slots(sel_army.commander):
						target_cmd = sel_army.commander
				if target_cmd == null:
					var armies := GameManager.get_faction_armies(faction_id)
					for army in armies:
						if army.commander and army.commander.followers.size() < CommanderSystem.get_max_follower_slots(army.commander):
							target_cmd = army.commander
							break
				if target_cmd:
					target_cmd.followers.append(follower_id)
					return "%s joined %s as a follower." % [follower.display_name, target_cmd.name]
				else:
					fs.follower_storage.append(follower_id)
					return "%s added to follower pool (no commander has room)." % follower.display_name
			return "The stranger moves on."

		"plague":
			if choice == "a":
				fs.resources[Enums.ResourceType.FOOD] = maxi(0, fs.resources.get(Enums.ResourceType.FOOD, 0) - 20)
				return "Quarantine established. Food reserves depleted but population saved."
			else:
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						city.population = maxi(20, city.population - 30)
						break
				return "The plague spreads. A city lost 30 population."

		"mercenary":
			if choice == "a":
				if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 100:
					fs.resources[Enums.ResourceType.GOLD] -= 100
					var merc_unit := _get_faction_basic_infantry(faction_id)
					var armies := GameManager.get_faction_armies(faction_id)
					if armies.size() > 0:
						_spawn_unit_at_hex(merc_unit, faction_id, armies[0].hex_pos)
						_spawn_unit_at_hex(merc_unit, faction_id, armies[0].hex_pos)
					return "Hired mercenaries for 100 Gold. +2 units."
				return "Not enough gold (need 100)!"
			else:
				fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 20)
				return "Mercenaries raided your lands. Lost 20 Gold."

		"shard_storm":
			if choice == "a":
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 15
				return "Scouts braved the storm. +15 Shard Essence."
			return "You waited out the storm safely."

		"trade_caravan":
			if choice == "a":
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 50
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 20
				return "Fair trade. +50 Gold, +20 Food."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 80
				return "Raided the caravan. +80 Gold, but your reputation suffers."

		"spy_report":
			if choice == "a":
				return "Intelligence gathered. Enemy positions revealed for 3 turns."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 60
				return "Sold intelligence. +60 Gold."

		"disaster":
			if choice == "a":
				fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 60)
				fs.resources[Enums.ResourceType.WOOD] = maxi(0, fs.resources.get(Enums.ResourceType.WOOD, 0) - 20)
				return "City rebuilt. -60 Gold, -20 Wood."
			else:
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						city.population = maxi(20, city.population - 30)
						break
				return "Population relocated. -30 population."

		"revival":
			if choice == "a":
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 20
				return "Religious revival inspires scholars. +20 Technology."
			else:
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "Faith bolsters the people. +3 all class loyalty."

		"tax_revolt":
			if choice == "a":
				fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 40)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					capital.class_loyalty["peasants"] = clampi(capital.class_loyalty.get("peasants", 0) + 15, -100, 100)
				return "Concessions made. -40 Gold, +15 Peasant loyalty."
			else:
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					capital.class_loyalty["peasants"] = clampi(capital.class_loyalty.get("peasants", 0) - 10, -100, 100)
				fs.resources[Enums.ResourceType.CAPTIVES] = fs.resources.get(Enums.ResourceType.CAPTIVES, 0) + 5
				return "Crackdown enforced. -10 Peasant loyalty, +5 Captives."

		"legendary_commander":
			if choice == "a":
				var armies := GameManager.get_faction_armies(faction_id)
				for army in armies:
					if army.commander:
						army.commander.xp += 50
						CommanderSystem._check_level_up(army.commander)
						return "%s gained +50 XP." % army.commander.name
				return "No commander to receive the training."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 80
				return "Sold their services. +80 Gold."

		"artifact":
			if choice == "a":
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] - 5, -100, 100)
				return "The artifact pulses with dark power. -5 all class loyalty."
			else:
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 40
				return "Artifact destroyed for knowledge. +40 Technology."

		"beast_migration":
			if choice == "a":
				var armies := GameManager.get_faction_armies(faction_id)
				for army in armies:
					if army.commander:
						army.commander.xp += 20
						return "Beasts driven off. %s gained +20 XP." % army.commander.name
				return "Beasts driven off."
			else:
				fs.resources[Enums.ResourceType.FOOD] = maxi(0, fs.resources.get(Enums.ResourceType.FOOD, 0) - 30)
				return "Tribute paid. -30 Food."

		"harvest":
			# Positive event, both choices are good
			fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 30
			var capital := GameManager.policy_system._get_faction_capital(faction_id)
			if capital:
				capital.class_loyalty["peasants"] = clampi(capital.class_loyalty.get("peasants", 0) + 10, -100, 100)
			return "The harvest festival brings joy. +30 Food, +10 Peasant loyalty."

		"diplomatic_marriage":
			if choice == "a":
				# Improve standing with a random non-war faction
				for other_id in GameManager.state.faction_states:
					if other_id == faction_id or GameManager.is_npc_faction(other_id):
						continue
					if GameManager.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
						GameManager.diplomacy_system.modify_standing(faction_id, other_id, 15)
						return "Marriage alliance formed. +15 standing with a neighbor."
				return "No suitable faction for marriage."
			else:
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					capital.class_loyalty["nobles"] = clampi(capital.class_loyalty.get("nobles", 0) + 5, -100, 100)
				return "Marriage declined respectfully. +5 Noble loyalty."

	return "Event resolved."

func _decay_temp_effects(faction_id: StringName) -> void:
	var i := _temp_effects.size() - 1
	while i >= 0:
		if _temp_effects[i].faction_id == faction_id:
			_temp_effects[i].turns_remaining -= 1
			if _temp_effects[i].turns_remaining <= 0:
				_temp_effects.remove_at(i)
		i -= 1

# ── Shared AI Helpers ────────────────────────────────────────

func _get_army_strength(army: ArmyState) -> int:
	var strength := 0
	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			strength += ud.attack + ud.defense
	return strength

func _find_nearest_enemy_army_hex(from: Vector2i, faction_id: StringName, min_strength: int = 0) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, army.faction_id) != Enums.FactionRelation.WAR:
			continue
		# Skip targets that are too strong if we have a minimum strength filter
		if min_strength > 0 and _get_army_strength(army) > min_strength * 2:
			continue
		var dist := HexHelper.hex_distance(from, army.hex_pos)
		if dist < best_dist:
			best_dist = dist
			best_hex = army.hex_pos
	return best_hex

func _find_nearest_enemy_region_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for region_id in DataManager.regions:
		var owner := GameManager.state.get_region_owner(region_id)
		if owner == &"" or owner == faction_id:
			continue
		if GameManager.get_relation(faction_id, owner) != Enums.FactionRelation.WAR:
			continue
		var center := MapGenerator.get_region_center(region_id)
		var dist := HexHelper.hex_distance(from, center)
		if dist < best_dist:
			best_dist = dist
			best_hex = center
	return best_hex

func _find_nearest_enemy_city_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, city.faction_id) != Enums.FactionRelation.WAR:
			continue
		var dist := HexHelper.hex_distance(from, city.hex_pos)
		if dist < best_dist:
			best_dist = dist
			best_hex = city.hex_pos
	return best_hex

func _find_nearest_faction_city(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id:
			var dist := HexHelper.hex_distance(from, city.hex_pos)
			if dist < best_dist:
				best_dist = dist
				best_hex = city.hex_pos
	return best_hex

func _find_nearest_intruder(faction_id: StringName, range_limit: int) -> Vector2i:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return Vector2i(-1, -1)
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return Vector2i(-1, -1)
	var owned_centers: Array[Vector2i] = []
	for region_id in fs.owned_regions:
		owned_centers.append(MapGenerator.get_region_center(region_id))
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, army.faction_id) != Enums.FactionRelation.WAR:
			continue
		var tile := hex_map.get_tile(army.hex_pos)
		if tile and tile.owner_faction == faction_id:
			if best_dist > 0:
				best_dist = 0
				best_hex = army.hex_pos
			continue
		for center in owned_centers:
			var d := HexHelper.hex_distance(army.hex_pos, center)
			if d <= range_limit + 5 and d < best_dist:
				best_dist = d
				best_hex = army.hex_pos
	if best_dist <= range_limit + 5:
		return best_hex
	return Vector2i(-1, -1)

func _get_faction_border_tiles(faction_id: StringName) -> Array[Vector2i]:
	if _border_cache.has(faction_id):
		return _border_cache[faction_id]
	var borders: Array[Vector2i] = []
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		_border_cache[faction_id] = borders
		return borders
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.owner_faction != faction_id:
			continue
		var neighbors := HexHelper.get_neighbors(coord)
		for n in neighbors:
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				borders.append(coord)
				break
			var ntile := hex_map.get_tile(n)
			if ntile and ntile.owner_faction != faction_id:
				borders.append(coord)
				break
	_border_cache[faction_id] = borders
	return borders

func _ai_find_path(army: ArmyState, target: Vector2i, faction_id: StringName) -> Array[Vector2i]:
	# Capped AI pathfinding: search within 3x movement range, truncate to 1 turn of movement
	var max_cost := army.movement_remaining * 3.0
	var path := GameManager.movement_system.find_path(
		army.hex_pos, target, faction_id, max_cost, &"", army.can_cross_mountains())
	if path.is_empty():
		return path
	# Truncate path to what the army can actually walk this turn
	var truncated: Array[Vector2i] = []
	var remaining := army.movement_remaining
	for coord in path:
		var cost := GameManager.state.hex_map.get_movement_cost(coord, faction_id)
		if remaining < cost:
			break
		remaining -= cost
		truncated.append(coord)
	return truncated

func _can_afford_faction(fs: FactionState, cost: Dictionary) -> bool:
	for res_type in cost:
		if fs.resources.get(res_type, 0) < cost[res_type]:
			return false
	return true

func _deduct_faction_cost(fs: FactionState, cost: Dictionary) -> void:
	for res_type in cost:
		if fs.resources.has(res_type):
			fs.resources[res_type] -= cost[res_type]

func _get_faction_basic_infantry(faction_id: StringName) -> StringName:
	match faction_id:
		&"empire": return &"legionary"
		&"skulloath": return &"warband_raider"
		&"gladehost": return &"grove_warden"
		&"tainted_jade": return &"jade_fang"
		&"shardhorde": return &"crystal_swarmling"
		_: return &"legionary"

# ── Unique Faction Mechanics ────────────────────────────────

func _process_faction_mechanic(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.is_defeated:
		return
	match faction_id:
		&"skulloath":
			_process_skulloath_corruption(fs)
		&"tainted_jade":
			_process_tainted_jade_taint(fs)
		&"gladehost":
			_process_gladehost_seasons(fs)
		&"shardhorde":
			_process_shardhorde_resonance(fs)
		&"moonspear":
			_process_moonspear_lunar(fs)
		&"thunderswarm":
			_process_thunderswarm_fury(fs)
		&"cinderguard":
			_process_cinderguard_forge(fs)
		&"forsaken":
			_process_forsaken_espionage(fs)
		&"ivoryscar":
			_process_ivoryscar_relics(fs)
		&"sunblessed":
			_process_sunblessed_faith(fs)

# ── Skulloath: Corruption Duality ──────────────────────────
# Traditional path (0-30): food/loyalty/diplomacy bonuses, population growth
# Balanced (31-60): No strong bonus/penalty
# Demonic path (61-80): attack bonus, captive generation, shard synergy, loyalty penalty
# Deep corruption (81-100): huge attack, void shard immunity, massive loyalty/diplo penalty

func _process_skulloath_corruption(fs: FactionState) -> void:
	# Corruption drifts based on buildings
	var drift := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			if building_id in [&"herders_camp", &"steppe_pastures", &"ancestor_shrine", &"spirit_lodge", &"trade_post_skulloath", &"steppe_watchtower"]:
				drift -= 1
			elif building_id in [&"pale_waif_altar", &"void_sanctum", &"blood_altar", &"demon_gate"]:
				drift += 2
			elif building_id in [&"bone_workshop", &"war_forge", &"beast_pens"]:
				drift += 0 # neutral buildings don't affect corruption

	# Winning battles in desert/wastes terrain slightly raises corruption (void exposure)
	# (tracked via captive gains — proxy for battle activity)
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	if captives >= 10:
		drift += 1 # Captive sacrifices feed the Pale Waif

	fs.corruption = clampi(fs.corruption + drift, 0, 100)

	# Apply corruption effects
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null or not city.is_capital:
			continue
		if fs.corruption <= 30:
			# Traditional: stable pastoralist society
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
			# Population growth bonus from herding lifestyle
			city.population += 2
		elif fs.corruption >= 81:
			# Deep corruption: captives auto-convert to food (sacrifice rituals)
			if captives > 0:
				var converted := mini(captives, 5)
				fs.resources[Enums.ResourceType.CAPTIVES] = captives - converted
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + converted * 8
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 3, -100, 100)
		elif fs.corruption >= 61:
			# High corruption: captive-to-iron conversion (demonic forging)
			if captives > 0:
				var converted := mini(captives, 3)
				fs.resources[Enums.ResourceType.CAPTIVES] = captives - converted
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + converted * 5
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 1, -100, 100)

	# High corruption: diplomatic penalty
	if fs.corruption >= 61:
		var penalty := -1 if fs.corruption < 81 else -2
		for other_id in GameManager.state.faction_states:
			if other_id == &"skulloath" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			var fd: FactionData = DataManager.get_faction(other_id)
			if fd and fd.realm_affinity != Enums.Realm.VOID:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, penalty)

	# Traditional path: diplomacy bonus with non-war factions
	if fs.corruption <= 30:
		for other_id in GameManager.state.faction_states:
			if other_id == &"skulloath" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if GameManager.get_relation(&"skulloath", other_id) != Enums.FactionRelation.WAR:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, 1)

# ── Tainted Jade: Anti-Magic / Taint Power ─────────────────
# Taint power from shard destruction + captive sacrifice + jungle building chains
# Grants defense, shard suppression, anti-magic aura, captive economy
# Passively grows taint from captive labor (thrall quarters process captives)

func _process_tainted_jade_taint(fs: FactionState) -> void:
	# Taint power sources: captive processing generates taint residue
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	var has_thrall_quarters := false
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and city.buildings.has(&"thrall_quarters"):
			has_thrall_quarters = true
			break

	if has_thrall_quarters and captives >= 5:
		# Thrall labor: consume captives for taint power + resources
		var processed := mini(captives / 5, 3) # Up to 3 batches of 5
		fs.resources[Enums.ResourceType.CAPTIVES] = captives - processed * 5
		fs.taint_power += processed * 3
		fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + processed * 4
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + processed * 3

	# Natural decay (reduced if cities are in jungle terrain)
	var jungle_cities := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			var tile := GameManager.state.hex_map.get_tile(city.hex_pos)
			if tile and tile.terrain == Enums.TerrainType.JUNGLE:
				jungle_cities += 1
	# Less decay if rooted in jungle (taint is sustained by the land)
	var decay := maxi(1, 2 - jungle_cities)
	if fs.taint_power > 0:
		fs.taint_power = maxi(fs.taint_power - decay, 0)

	# High taint: accelerate enemy shard decay
	if fs.taint_power >= 50:
		for shard_id in GameManager.state.active_shards:
			var shard: ShardInstance = GameManager.state.active_shards[shard_id]
			if shard.claimed_by != &"tainted_jade" and shard.claimed_by != &"" and shard.turns_remaining > 0:
				shard.turns_remaining = maxi(shard.turns_remaining - 1, 1)

	# Taint power 30+: diplomatic bonus with other anti-shard factions
	# (factions respect Tainted Jade's shard-suppression efforts)
	if fs.taint_power >= 30:
		for other_id in GameManager.state.faction_states:
			if other_id == &"tainted_jade" or GameManager.is_npc_faction(other_id) or other_id == &"shardhorde":
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			# Small standing bonus with non-shard factions
			if other_fs.owned_shards.size() <= 2:
				GameManager.diplomacy_system.modify_standing(&"tainted_jade", other_id, 1)

	# Very high taint: population growth penalty (the land itself is scarred)
	if fs.taint_power >= 70:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				city.population = maxi(20, city.population - 1)

# ── Gladehost: Seasonal Cycle ──────────────────────────────
# Season derived from month: 0-2 Spring, 3-5 Summer, 6-7 Autumn, 8-9 Winter
# Harmony affects seasonal bonus strength, diplomacy, and building effectiveness
# Forest/Jungle tiles in owned territory boost harmony recovery

func get_current_season() -> int:
	var month: int = GameManager.state.current_month
	if month <= 2:
		return 0 # Spring
	elif month <= 5:
		return 1 # Summer
	elif month <= 7:
		return 2 # Autumn
	else:
		return 3 # Winter

func get_season_name(season: int) -> String:
	match season:
		0: return "Spring"
		1: return "Summer"
		2: return "Autumn"
		3: return "Winter"
		_: return "Unknown"

func _process_gladehost_seasons(fs: FactionState) -> void:
	# Harmony adjusts based on building count and territory nature
	var total_buildings := 0
	var nature_tiles := 0 # Forest/Jungle tiles in owned territory
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			total_buildings += city.buildings.size()

	# Count nature tiles in owned regions
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and (tile.terrain == Enums.TerrainType.FOREST or tile.terrain == Enums.TerrainType.JUNGLE):
				nature_tiles += 1

	# Target: ~3 buildings per city is balanced. More = lower harmony
	var target := fs.owned_cities.size() * 3
	if total_buildings > target:
		fs.harmony = maxi(fs.harmony - (total_buildings - target), 20)
	elif total_buildings < target:
		fs.harmony = mini(fs.harmony + 1, 100)

	# Nature tiles in territory help recover harmony (+1 per 10 nature tiles, max +3)
	var nature_bonus := mini(nature_tiles / 10, 3)
	fs.harmony = mini(fs.harmony + nature_bonus, 100)

	# Seasonal loyalty and population effects
	var season := get_current_season()
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null or not city.is_capital:
			continue

		# Harmony loyalty
		if fs.harmony >= 70:
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 1, -100, 100)
		elif fs.harmony <= 35:
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 2, -100, 100)

		# Seasonal population effects
		match season:
			0: # Spring: birth season
				city.population += 3 if fs.harmony >= 50 else 1
			3: # Winter: population suffers if harmony is low
				if fs.harmony < 40:
					city.population = maxi(20, city.population - 2)

	# High harmony: diplomacy bonus with all factions (Gladehost is seen as balanced)
	var has_embassy := false
	var has_seasonal_shrine := false
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			if city.buildings.has(&"embassy_grove"):
				has_embassy = true
			if city.buildings.has(&"seasonal_shrine"):
				has_seasonal_shrine = true

	if fs.harmony >= 75 or has_embassy:
		var diplo_bonus := 1
		if has_embassy:
			diplo_bonus += 1 # Embassy Grove doubles diplomacy gain
		for other_id in GameManager.state.faction_states:
			if other_id == &"gladehost" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if GameManager.get_relation(&"gladehost", other_id) != Enums.FactionRelation.WAR:
				GameManager.diplomacy_system.modify_standing(&"gladehost", other_id, diplo_bonus)

	# Seasonal shrine: +2 harmony per shrine, boosts seasonal income effects
	if has_seasonal_shrine:
		fs.harmony = mini(fs.harmony + 2, 100)

# ── Shardhorde: Shard Resonance ────────────────────────────
# Consuming shards grants temporary buffs. Elderbeasts grow faster near shard wastes.
# Active resonance heals elderbeasts and boosts recruitment speed.
# Shard wastes territory generates passive shard essence.

func _process_shardhorde_resonance(fs: FactionState) -> void:
	# Decay resonance buffs
	var to_remove: Array = []
	for realm_key in fs.shard_resonance:
		fs.shard_resonance[realm_key] -= 1
		if fs.shard_resonance[realm_key] <= 0:
			to_remove.append(realm_key)
	for key in to_remove:
		fs.shard_resonance.erase(key)

	# Active resonance heals elderbeasts
	if fs.shard_resonance.size() > 0:
		for beast_id in GameManager.state.elderbeasts:
			var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
			if beast.faction_id == &"shardhorde" and beast.hp < beast.max_hp:
				beast.hp = mini(beast.hp + 20 * fs.shard_resonance.size(), beast.max_hp)

	# Elderbeasts on shard wastes gain survival turns faster (level up sooner)
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		var tile := GameManager.state.hex_map.get_tile(beast.hex_pos)
		if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
			beast.survival_turns += 1 # Double growth rate on shard wastes

	# Shard wastes in owned territory passively generate shard essence
	var wastes_count := 0
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
				wastes_count += 1
	if wastes_count > 0:
		var essence_gain := mini(wastes_count / 5, 8)
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + essence_gain

# Called when Shardhorde consumes a shard (from campaign HUD or AI)
func consume_shard_for_resonance(faction_id: StringName, shard_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null or shard.claimed_by != faction_id:
		return
	fs.owned_shards.erase(shard_id)
	GameManager.state.active_shards.erase(shard_id)
	# Grant resonance buff: 5 turns of realm bonus (10 if Resonance Amplifier built)
	var resonance_duration := 5
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			if beast.buildings.has(&"resonance_amplifier"):
				resonance_duration = 10
				break
	fs.shard_resonance[shard.realm] = resonance_duration
	# Consuming shards also heals nearby elderbeasts immediately
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			beast.hp = mini(beast.hp + 50, beast.max_hp)

# Called when Tainted Jade destroys a shard
func destroy_shard_for_taint(faction_id: StringName, shard_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null or shard.claimed_by != faction_id:
		return
	fs.owned_shards.erase(shard_id)
	GameManager.state.active_shards.erase(shard_id)
	fs.taint_power += shard.power_level * 10
	# Destroying shards also grants tech (studying what you destroy)
	fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 5

# ── Moonspear: Lunar Phase ────────────────────────────────
# Cycles every 4 turns: 0=New Moon (+atk), 1=Waxing (+move), 2=Full Moon (+def), 3=Waning (+heal)
# Battle bonuses applied in battle_simulator_v3 based on current phase

func _process_moonspear_lunar(fs: FactionState) -> void:
	# Advance lunar phase every 4 turns
	if GameManager.state.current_turn % 4 == 0:
		fs.lunar_phase = (fs.lunar_phase + 1) % 4

	# Waning moon (phase 3): heal all armies slightly
	if fs.lunar_phase == 3:
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == &"moonspear" and not army.is_garrison:
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = mini(unit.current_hp + 5, ud.hp * ud.squad_size)

	# Full moon (phase 2): loyalty bonus to capital
	if fs.lunar_phase == 2:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.is_capital:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 1, -100, 100)

func get_lunar_phase_name(phase: int) -> String:
	match phase:
		0: return "New Moon"
		1: return "Waxing Moon"
		2: return "Full Moon"
		3: return "Waning Moon"
		_: return "Unknown"

# ── Thunderswarm: Storm Fury ──────────────────────────────
# Fury rises from battles (+10-20 per battle), decays naturally (-5/turn)
# 50+: +10% atk to all armies. 80+: +20% atk, -5% def (reckless fury)
# Applied in battle_simulator; here we just handle decay

func _process_thunderswarm_fury(fs: FactionState) -> void:
	# Natural decay: fury cools down over time
	if fs.storm_fury > 0:
		fs.storm_fury = maxi(fs.storm_fury - 5, 0)

	# Thunderswarm armies in mountains/highlands gain +2 fury per turn (storms gather)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == &"thunderswarm" and not army.is_garrison:
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile and tile.terrain == Enums.TerrainType.MOUNTAINS:
				fs.storm_fury = mini(fs.storm_fury + 2, 100)

	# High fury: slight diplomacy penalty (seen as aggressive)
	if fs.storm_fury >= 80:
		for other_id in GameManager.state.faction_states:
			if other_id == &"thunderswarm" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			GameManager.diplomacy_system.modify_standing(&"thunderswarm", other_id, -1)

# ── Cinderguard: Forge Heat ──────────────────────────────
# High heat (70+): cheaper iron costs for buildings/units, faster recruitment
# Low heat (30-): +defense bonus to all units, iron preservation
# Heat rises from military buildings, falls from defensive/civilian buildings

func _process_cinderguard_forge(fs: FactionState) -> void:
	var drift := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			# Military/forge buildings raise heat
			if building_id in [&"ember_forge", &"war_forge", &"siege_works", &"fire_barracks", &"molten_foundry"]:
				drift += 1
			# Defensive/civilian buildings lower heat
			elif building_id in [&"stone_bastion", &"iron_wall", &"market", &"granary", &"temple"]:
				drift -= 1

	# Natural drift toward 50 (equilibrium)
	if drift == 0:
		if fs.forge_heat > 50:
			drift = -1
		elif fs.forge_heat < 50:
			drift = 1

	fs.forge_heat = clampi(fs.forge_heat + drift, 0, 100)

	# High heat: bonus iron income from forge efficiency
	if fs.forge_heat >= 70:
		var iron_bonus := 2 if fs.forge_heat >= 85 else 1
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + iron_bonus

	# Low heat: population stability bonus (cooler forges = safer cities)
	if fs.forge_heat <= 30:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.is_capital:
				city.population += 1

# ── Forsaken: Espionage Network ──────────────────────────
# Grows from number of owned regions (+1 per 3 regions per turn)
# 10+: reveals enemy army positions (fog of war bypass)
# 20+: enables sabotage actions (random enemy gold loss)
# 30+: intelligence reports (see enemy city details)

func _process_forsaken_espionage(fs: FactionState) -> void:
	# Network grows from territorial control
	var region_count := fs.owned_regions.size()
	var growth := region_count / 3
	fs.espionage_network = mini(fs.espionage_network + growth, 50)

	# Natural decay if losing territory
	if region_count <= 1:
		fs.espionage_network = maxi(fs.espionage_network - 2, 0)

	# 20+ espionage: occasional sabotage (steal gold from richest enemy)
	if fs.espionage_network >= 20 and GameManager.state.current_turn % 3 == 0:
		var richest_enemy: StringName = &""
		var richest_gold := 0
		for other_id in GameManager.state.faction_states:
			if other_id == &"forsaken" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if GameManager.get_relation(&"forsaken", other_id) == Enums.FactionRelation.WAR:
				var their_gold: int = other_fs.resources.get(Enums.ResourceType.GOLD, 0)
				if their_gold > richest_gold:
					richest_gold = their_gold
					richest_enemy = other_id
		if richest_enemy != &"" and richest_gold > 20:
			var stolen := mini(richest_gold / 10, 15)
			var enemy_fs: FactionState = GameManager.state.faction_states[richest_enemy]
			enemy_fs.resources[Enums.ResourceType.GOLD] = enemy_fs.resources.get(Enums.ResourceType.GOLD, 0) - stolen
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + stolen

# ── Ivoryscar: Relic Power ───────────────────────────────
# Grows from controlling shard_wastes tiles and owned shards
# Grants commander bonuses and tech acceleration

func _process_ivoryscar_relics(fs: FactionState) -> void:
	# Relic power from shard wastes control + owned shards
	var wastes_count := 0
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
				wastes_count += 1

	var shard_count := fs.owned_shards.size()
	var target_power := wastes_count / 3 + shard_count * 5

	# Drift toward target
	if fs.relic_power < target_power:
		fs.relic_power = mini(fs.relic_power + 2, 50)
	elif fs.relic_power > target_power:
		fs.relic_power = maxi(fs.relic_power - 1, 0)

	# High relic power: tech bonus (ancient knowledge from relics)
	if fs.relic_power >= 15:
		var tech_bonus := 2 if fs.relic_power >= 30 else 1
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_bonus

	# Very high relic power: shard essence passive generation
	if fs.relic_power >= 30:
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 1

# ── Sunblessed: Solar Faith ──────────────────────────────
# 0-100, rises on battle victories (+10), drops on defeats (-15)
# High faith (70+): +morale, healing in friendly territory
# Low faith (30-): recruitment penalties, loyalty loss
# Naturally drifts toward 50

func _process_sunblessed_faith(fs: FactionState) -> void:
	# Natural drift toward 50
	if fs.solar_faith > 50:
		fs.solar_faith -= 1
	elif fs.solar_faith < 50:
		fs.solar_faith += 1

	# High faith: heal armies in owned territory
	if fs.solar_faith >= 70:
		var heal_amount := 3 if fs.solar_faith >= 85 else 2
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == &"sunblessed" and not army.is_garrison:
				var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
				if tile and tile.region_id in fs.owned_regions:
						for unit in army.units:
							var ud := DataManager.get_unit(unit.unit_data_id)
							if ud:
								unit.current_hp = mini(unit.current_hp + heal_amount, ud.hp * ud.squad_size)

	# High faith: loyalty bonus
	if fs.solar_faith >= 70:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.is_capital:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 1, -100, 100)

	# Low faith: loyalty penalty
	if fs.solar_faith <= 30:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.is_capital:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 1, -100, 100)
