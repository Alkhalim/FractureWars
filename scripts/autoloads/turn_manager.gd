extends Node

var faction_order: Array[StringName] = []
var current_faction_index: int = 0
var is_player_turn: bool = true
var shardfall_system: ShardfallSystem = ShardfallSystem.new()

# AI turn speed controls
var ai_speed_multiplier: float = 1.0
var skip_ai_turn: bool = false
var _ai_wait_counter: int = 0

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

# Turn on which the first follower is guaranteed (randomized once at start, range 3-7)
var _first_follower_turn: int = -1

# Terrain type to string mapping for follower terrain_tags filtering
const TERRAIN_TO_STRING: Dictionary = {
	Enums.TerrainType.PLAINS: &"plains",
	Enums.TerrainType.FOREST: &"forest",
	Enums.TerrainType.MOUNTAINS: &"mountains",
	Enums.TerrainType.DESERT: &"desert",
	Enums.TerrainType.SWAMP: &"swamp",
	Enums.TerrainType.WETLANDS: &"wetlands",
	Enums.TerrainType.TUNDRA: &"tundra",
	Enums.TerrainType.SHARD_WASTES: &"shard_wastes",
	Enums.TerrainType.JUNGLE: &"jungle",
}

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
		"_first_follower_turn": _first_follower_turn,
		"_diplomacy_extra": GameManager.diplomacy_system.serialize_diplomacy_extra() if GameManager.diplomacy_system else {},
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
	_first_follower_turn = data.get("_first_follower_turn", -1)
	if GameManager.diplomacy_system:
		GameManager.diplomacy_system.deserialize_diplomacy_extra(data.get("_diplomacy_extra", {}))

func _ready() -> void:
	EventBus.end_turn_pressed.connect(_on_end_turn_pressed)
	EventBus.battle_resolved.connect(_on_log_battle_resolved)
	EventBus.city_captured.connect(_on_log_city_captured)
	EventBus.shardfall_occurred.connect(_on_log_shardfall)
	EventBus.treaty_created.connect(_on_log_treaty_created)
	EventBus.army_destroyed.connect(_on_log_army_destroyed)
	EventBus.dilemma_resolved.connect(_on_faction_dilemma_resolved)

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

# ── Faction Mechanic Dilemma Resolution ──────────────────────
func _on_faction_dilemma_resolved(faction_id: StringName, dilemma_type: StringName, choice_effect: String) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	match dilemma_type:
		"imperial_edict":
			match choice_effect:
				"edict_military": _apply_empire_edict(fs, 1)
				"edict_economic": _apply_empire_edict(fs, 2)
				"edict_cultural": _apply_empire_edict(fs, 3)
				"edict_diplomatic": _apply_empire_edict(fs, 4)
		"taint_focus":
			match choice_effect:
				"taint_focus_1": fs.taint_focus = 1
				"taint_focus_2": fs.taint_focus = 2
				"taint_focus_3": fs.taint_focus = 3
		"lunar_ritual":
			match choice_effect:
				"lunar_extend":
					if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 40 and fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) >= 5:
						fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 40
						fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) - 5
						fs.lunar_ritual_extended = 3
				"lunar_skip":
					if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 20 and fs.lunar_skip_cooldown <= 0:
						fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 20
						fs.lunar_phase = (fs.lunar_phase + 1) % 4
						fs.lunar_skip_cooldown = 8
				"lunar_accept":
					pass
		"storm_ability":
			match choice_effect:
				"storm_march": _apply_storm_ability(fs, faction_id, "storm_march")
				"storm_wall": _apply_storm_ability(fs, faction_id, "storm_wall")
				"storm_harvest": _apply_storm_ability(fs, faction_id, "storm_harvest")
				"storm_hold": pass
		"dark_bargain":
			_apply_dark_bargain(fs, choice_effect)
		"season_festival":
			_apply_season_festival(fs, choice_effect)
		"espionage_op":
			_apply_espionage_operation(fs, choice_effect, fs.espionage_op_target)
			fs.espionage_op_target = &""
		"golden_age":
			_apply_golden_age(fs, faction_id, choice_effect)
		"forge_allocation":
			if choice_effect.begins_with("build_fort_"):
				# Build fortress at a settlement
				var target_cid: StringName = StringName(choice_effect.substr(11))
				var flv: int = fs.border_fortresses.get(target_cid, 0)
				if flv < 3:
					var cost_scrap = [10, 20, 35][mini(flv, 2)]
					if fs.scavenge_stockpile >= cost_scrap:
						fs.scavenge_stockpile -= cost_scrap
						fs.border_fortresses[target_cid] = flv + 1
			else:
				match choice_effect:
					"forge_war": fs.forge_shift_queued = 10
					"forge_balanced": fs.forge_shift_queued = 0
					"forge_peace": fs.forge_shift_queued = -10
					"forge_emergency":
						if fs.resources.get(Enums.ResourceType.IRON, 0) >= 30:
							fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) - 30
							fs.forge_shift_queued = 20
		"dragon_raid":
			var raid_target: StringName = fs.dragon_raid_target
			match choice_effect:
				"dragon_defend":
					var fort_lv: int = fs.border_fortresses.get(raid_target, 0)
					var defense_score := fort_lv * 25 + fs.border_vigilance / 4 + randi() % 30
					if defense_score >= 45:
						fs.scavenge_stockpile += 15
						fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 5
						fs.border_vigilance = clampi(fs.border_vigilance + 5, 0, 100)
						fs.dragon_raids_survived += 1
					else:
						_apply_dragon_damage(fs, raid_target)
				"dragon_evacuate":
					var fort_lv: int = fs.border_fortresses.get(raid_target, 0)
					if fort_lv > 0:
						fs.border_fortresses[raid_target] = fort_lv - 1
					fs.border_vigilance = clampi(fs.border_vigilance - 10, 0, 100)
					# Move population to capital
					var target_city: CityState = GameManager.state.cities.get(raid_target)
					if target_city:
						var evacuees := mini(target_city.population / 3, 30)
						target_city.population -= evacuees
						for cid in fs.owned_cities:
							var cap_city: CityState = GameManager.state.cities.get(cid)
							if cap_city and cap_city.is_capital:
								cap_city.population += evacuees
								break
				"dragon_trap":
					if fs.resources.get(Enums.ResourceType.IRON, 0) >= 20:
						fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) - 20
						var fort_lv: int = fs.border_fortresses.get(raid_target, 0)
						var success := (fort_lv * 20 + 40 + randi() % 30) >= 50
						if success:
							fs.scavenge_stockpile += 25
							fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 8
							fs.dragon_raids_survived += 1
						else:
							_apply_dragon_damage(fs, raid_target)
				"dragon_fortify":
					if fs.scavenge_stockpile >= 15:
						fs.scavenge_stockpile -= 15
						var fort_lv: int = fs.border_fortresses.get(raid_target, 0)
						if fort_lv < 3:
							fs.border_fortresses[raid_target] = fort_lv + 1
						# Then auto-defend with improved fortress
						var new_fort_lv: int = fs.border_fortresses.get(raid_target, 0)
						var defense_score := new_fort_lv * 25 + fs.border_vigilance / 4 + randi() % 30
						if defense_score >= 45:
							fs.scavenge_stockpile += 15
							fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 5
							fs.dragon_raids_survived += 1
						else:
							_apply_dragon_damage(fs, raid_target)
			fs.dragon_raid_target = &""
		"relic_expedition":
			match choice_effect:
				"relic_fund":
					if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 30 and fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) >= 5:
						fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 30
						fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) - 5
						fs.relic_expedition_cooldown = 5
						var roll := randf()
						if roll < 0.65: # Find relic
							fs.relic_power = mini(fs.relic_power + 8, 50)
							# Grant a random relic-themed commander item
							var relic_items: Array[StringName] = [&"qareth_hieroglyph_tablet", &"tomb_kings_scarab", &"scepter_of_ages", &"void_shard_amulet", &"crystal_shard_blade", &"bone_dice_set"]
							fs.item_storage.append(relic_items[randi() % relic_items.size()])
						elif roll < 0.85: # Find knowledge
							fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
						else: # Danger
							fs.relic_power = maxi(0, fs.relic_power - 5)
				"relic_study":
					fs.relic_power = mini(fs.relic_power + 2, 50)
					fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 5
					fs.relic_expedition_cooldown = 5
				"relic_fortify":
					fs.relic_expedition_cooldown = 5
					# Add defense to all cities for 3 turns (tracked via leader_bonuses)
					fs.leader_bonuses["relic_defense_turns"] = 3
				"pyramid_invest":
					if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 40 and fs.resources.get(Enums.ResourceType.IRON, 0) >= 15 and fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) >= 5 and not fs.owned_shards.is_empty():
						fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 40
						fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) - 15
						fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) - 5
						# Consume a claimed shard crystal
						var shard_id: StringName = fs.owned_shards[0]
						fs.owned_shards.erase(shard_id)
						if GameManager.state.active_shards.has(shard_id):
							GameManager.state.active_shards.erase(shard_id)
						fs.pyramid_restoration = mini(fs.pyramid_restoration + 15, 100)
						if fs.pyramid_restoration >= 100:
							fs.pyramid_restored = true
						fs.relic_expedition_cooldown = 5
	AudioManager.play_sfx(&"scroll_open")

func _ai_wait() -> void:
	# Batched yielding: yield often enough that the window keeps painting (the
	# old every-8th-call rate let whole AI factions run inside one frame, which
	# read as a multi-second freeze)
	_ai_wait_counter += 1
	if skip_ai_turn:
		if _ai_wait_counter % 8 == 0:
			await get_tree().process_frame
		return
	if _ai_wait_counter % 3 == 0:
		await get_tree().process_frame

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
	_ai_wait_counter = 0
	if is_player_turn:
		is_processing_round = false
	else:
		# Yield at least once per AI faction: keeps the window pumping OS
		# messages (no "not responding") and lets the busy overlay repaint
		await get_tree().process_frame

	# Refresh caches for this faction's turn
	GameManager.movement_system.refresh_caches()
	GameManager.rebuild_faction_army_cache()
	_special_effect_sums_cache.clear()

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

	# Process research/building diplomacy standing bonuses
	_apply_diplomacy_bonuses(faction_id)

	# Heal armies in settlements/friendly territory
	_heal_armies_in_settlements(faction_id)

	# Terrain attrition: damage/heal armies based on terrain they occupy
	_apply_terrain_attrition(faction_id)

	# Grant passive XP to commanders
	_grant_passive_commander_xp(faction_id)

	# Reset army movement for this faction (skip garrisons)
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		if army.is_garrison:
			continue
		if army.is_camp:
			army.movement_remaining = 0.0 # Camped armies cannot move
		else:
			army.movement_remaining = army.get_max_movement()
			# Stormcrystal: +% army movement
			var storm_mod := SpecialResourceSystem.modifier_strength(faction_id, &"stormcrystal")
			if storm_mod > 0.0:
				army.movement_remaining *= (1.0 + storm_mod)
			# Road bonus: +0.6 MP per road level
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile and tile.road_level >= 1:
				army.movement_remaining += 0.6 * tile.road_level
			# Building special_effects: army_movement_bonus
			var army_city := GameManager.city_system.get_city_at_hex(army.hex_pos)
			if army_city and army_city.faction_id == faction_id:
				for bid in army_city.buildings:
					var bld := DataManager.get_building(bid)
					if bld and bld.special_effects.has("army_movement_bonus"):
						army.movement_remaining += float(bld.special_effects["army_movement_bonus"])
		army.has_moved = false
		army.battle_exhausted = false

	# Decay temp effects
	_decay_temp_effects(faction_id)

	EventBus.turn_started.emit(GameManager.state.current_turn, faction_id)

	if is_player_turn:
		skip_ai_turn = false
		_check_random_events(faction_id)
		GameManager.diplomacy_system.generate_ai_offer_to_player()
	else:
		# Breathe between the heavy AI phases so each one lands in its own
		# frame instead of stacking into a single long hitch
		_ai_assign_commanders(faction_id)
		_consolidate_ai_armies(faction_id)
		await get_tree().process_frame
		_execute_ai_city_management(faction_id)
		await get_tree().process_frame
		_execute_ai_settlement_building(faction_id)
		GameManager.diplomacy_system.execute_ai_diplomacy(faction_id)
		await get_tree().process_frame
		GameManager.research_system.execute_ai_research(faction_id)
		GameManager.research_system.execute_ai_socketing(faction_id)
		if faction_id == &"empire":
			_ai_handle_forsaken_offer(faction_id)
			_ai_handle_senate_dilemma(faction_id)
		await _ai_wait()
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

## True while the AI round is being processed — blocks re-entrant end-turn
## presses (click-spamming during the busy phase could corrupt the faction
## index or stack multiple round advances)
var is_processing_round := false

func _on_end_turn_pressed() -> void:
	if not is_player_turn or is_processing_round:
		return
	is_processing_round = true
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
	_border_cache.clear()  # Reset for next round (territory may have changed mid-round)
	_unit_stat_cache.clear()  # Reset unit stat cache for next round
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

	# Yield before starting the next round to keep the game responsive
	await get_tree().process_frame

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
		var has_armies := GameManager.get_faction_armies(faction_id).size() > 0
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
				EventBus.faction_defeated.emit(faction_id)
				continue
		elif not has_cities and not has_armies:
			fs.is_defeated = true
			if is_player:
				_trigger_game_over(faction_id, Enums.VictoryType.DEFEAT, true)
				return
			EventBus.faction_defeated.emit(faction_id)
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
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		if army.commander:
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
			# Building special_effects: commander_xp_bonus
			if city:
				for bid in city.buildings:
					var bld := DataManager.get_building(bid)
					if bld and bld.special_effects.has("commander_xp_bonus"):
						base_xp = int(float(base_xp) * (1.0 + float(bld.special_effects["commander_xp_bonus"])))
			CommanderSystem.grant_passive_xp(army.commander, context, base_xp)
			# Evaluate traits based on current context
			var trait_changes := CommanderSystem.evaluate_traits(army.commander, context)
			for change in trait_changes:
				EventBus.commander_trait_changed.emit(army.commander, change.action, change.trait_id)

# ── AI Commander Assignment ──────────────────────────────────

func _ai_assign_commanders(faction_id: StringName) -> void:
	var available := GameManager.get_available_commanders(faction_id)
	if available.is_empty():
		return
	# Get armies without commanders, sorted by size (largest first)
	var armies_no_cmd: Array[ArmyState] = []
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		if army.commander == null and not army.is_garrison:
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
	var recruit_census: Dictionary = {} # computed once on first recruiting city

	# Per-faction building priorities — using each faction's own buildings
	var faction_build_priorities := {
		&"empire": [&"cohort_barracks", &"grain_fields", &"iron_pit", &"lumber_camp_empire", &"market_square", &"tavern", &"scriptorium_empire", &"village_gathering_place"],
		&"skulloath": [&"raiders_den", &"herders_camp", &"bone_workshop", &"ancestor_shrine", &"trade_post_skulloath", &"steppe_watchtower", &"blood_altar", &"pale_waif_altar", &"beast_pens"],
		&"gladehost": [&"ranger_outpost", &"harvest_clearing", &"rootwood_lodge", &"sacred_grove", &"seasonal_shrine", &"grove_ironworks", &"forest_market", &"embassy_grove", &"living_fortress", &"beastkeepers_glade"],
		&"tainted_jade": [&"serpent_pit", &"vine_shelter", &"jade_forge", &"root_altar", &"thrall_quarters", &"jade_market", &"jungle_traps", &"taint_suppressor", &"hunting_ground"],
		&"shardhorde": [&"crystal_nursery", &"shard_conduit", &"crystal_forge", &"shard_harvester", &"chitin_walls"],
		&"moonspear": [&"sentinel_hall", &"frost_pastures", &"silver_vein", &"moon_shrine", &"starlight_market", &"frost_kennels", &"pilgrims_rest", &"frost_walls"],
		&"sunblessed": [&"pilgrim_training_grounds", &"pilgrim_gardens", &"sunfire_altar", &"sunfire_forge", &"golden_bazaar", &"sacred_oasis", &"sacred_aviary", &"sacred_ward"],
		&"thunderswarm": [&"warriors_longhouse", &"highland_terrace", &"thunderpeak_mine", &"lightning_shrine", &"windtrade_post", &"storm_kennels", &"mountain_watchtower"],
		&"cinderguard": [&"cinder_watchtower", &"oasis_farm", &"cinder_mine", &"sandstone_walls", &"ember_shrine", &"desert_bazaar", &"scorpion_pit"],
		&"forsaken": [&"wretched_pit", &"scavenger_camp", &"scrap_pit", &"black_alley_market", &"crypt_court", &"thrall_quarters", &"makeshift_barricades"],
		&"ivoryscar": [&"seekers_lodge", &"dust_fields", &"bone_quarry", &"relic_shrine", &"caravan_depot", &"relic_workshop", &"ancestor_crypt", &"bone_palisade"],
	}
	var priority_list: Array = faction_build_priorities.get(faction_id, [])
	if priority_list.is_empty():
		# Minor factions use parent faction's building priorities
		var parent_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, &"")
		if parent_id != &"":
			priority_list = faction_build_priorities.get(parent_id, [])
	if priority_list.is_empty():
		priority_list = [&"cohort_barracks", &"grain_fields", &"iron_pit", &"market_square"]

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

		# Recruit units with threat-aware composition. The faction-wide census
		# is loop-invariant (recruits only enter the queue), so compute it once
		# on first need instead of per city.
		if city.recruit_queue.is_empty() and GameManager.city_system.get_province_population(city) > 120:
			if recruit_census.is_empty():
				recruit_census = _compute_ai_recruit_census(faction_id)
			_ai_recruit_with_composition(city, faction_id, recruit_census)

func _compute_ai_recruit_census(faction_id: StringName) -> Dictionary:
	# Count existing army composition (cache unit data lookups)
	var tag_counts := {"infantry": 0, "ranged": 0, "cavalry": 0, "mage": 0}
	var total_units := 0
	var _unit_cache: Dictionary = {} # unit_data_id -> UnitData
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		for unit in army.units:
			var ud: UnitData = _unit_cache.get(unit.unit_data_id)
			if ud == null:
				ud = DataManager.get_unit(unit.unit_data_id)
				if ud == null:
					continue
				_unit_cache[unit.unit_data_id] = ud
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
		for enemy_army: ArmyState in GameManager.get_faction_armies(other_id):
			enemy_units += enemy_army.units.size()
		max_enemy_units = maxi(max_enemy_units, enemy_units)

	return {tag_counts = tag_counts, total_units = total_units, max_enemy_units = max_enemy_units}

# Faction identity weights for AI recruiting: units carrying these tags score
# higher, so AI stacks visibly reflect each faction's flavor (raider cavalry,
# undead swarms, missile zealots...) instead of one generic attack+defense pick.
# Keyed by PARENT faction — minors inherit their parent's doctrine.
const FACTION_RECRUIT_TAG_WEIGHTS := {
	&"empire": {"heavy": 15, "infantry": 8},
	&"skulloath": {"cavalry": 20, "fast": 8},
	&"forsaken": {"swarm": 15, "undead": 12, "flying": 6},
	&"sunblessed": {"ranged": 15, "flying": 8, "monster": 8},
	&"moonspear": {"heavy": 12, "ranged": 8},
	&"cinderguard": {"heavy": 15, "desertstrider": 8},
	&"thunderswarm": {"flying": 15, "fast": 10},
	&"gladehost": {"support": 10, "beast": 8, "ranged": 6},
	&"ivoryscar": {"undead": 12, "heavy": 10},
	&"tainted_jade": {"junglestrider": 10, "swarm": 8, "mage": 6},
}

func _ai_recruit_with_composition(city: CityState, faction_id: StringName, census: Dictionary) -> void:
	var tag_counts: Dictionary = census.tag_counts
	var total_units: int = census.total_units
	var max_enemy_units: int = census.max_enemy_units

	var turn_bonus := mini(GameManager.state.current_turn / 10, 4)
	var recruit_threshold := maxi(8 + turn_bonus, max_enemy_units + 4)
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
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var identity_weights: Dictionary = FACTION_RECRUIT_TAG_WEIGHTS.get(parent_fid, {})
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
				var score := udata.attack + udata.get_avg_defense()
				if udata.tags.has(needed_tag):
					score += 20
				# Faction identity: favor units that match the faction's doctrine
				for w_tag in identity_weights:
					if udata.tags.has(w_tag):
						score += identity_weights[w_tag]
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
					_ai_move_army_safe(closest_army, target_hex, faction_id)
			return

		# Evaluate best settlement tile (limit to 20 closest candidates)
		var valid_tiles := GameManager.city_system.get_valid_settlement_tiles(faction_id, city.region_id)
		if valid_tiles.is_empty():
			continue

		var capital_pos := city.hex_pos
		# Sort by distance and only evaluate closest 20. Distances precomputed
		# once per tile instead of per comparison — the comparator sees the
		# same boolean outcomes, so the ordering is identical.
		var keyed: Array = []
		for t in valid_tiles:
			keyed.append([HexHelper.hex_distance(t, capital_pos), t])
		keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var eval_count := mini(keyed.size(), 20)

		var best_tile := Vector2i(-1, -1)
		var best_score := -999
		for i in eval_count:
			var tile_pos: Vector2i = keyed[i][1]
			var income := GameManager.city_system.calculate_settlement_income_preview(tile_pos)
			var income_score := 0
			for res_type in income:
				income_score += income[res_type]
			var dist_penalty: int = keyed[i][0] * 2
			var total_score := income_score - dist_penalty
			if total_score > best_score:
				best_score = total_score
				best_tile = tile_pos

		if best_tile != Vector2i(-1, -1) and best_score > 5:
			_ai_settlement_targets[faction_id] = best_tile

# ── Empire/Default AI (Defend + Expand) ──────────────────────

func _army_is_holding_siege(army: ArmyState) -> bool:
	var city := GameManager.city_system.get_city_at_hex(army.hex_pos)
	if city == null or not city.is_under_siege:
		return false
	if city.siege_faction != army.faction_id or city.faction_id == army.faction_id:
		return false
	return GameManager.city_system._army_siege_weight(army) > 0.0

# Returns true if the army was left in place holding a siege (caller should skip
# re-targeting it this turn); false if it is free to act.
func _maybe_hold_siege_or_retarget(army: ArmyState, faction_id: StringName) -> bool:
	if _army_is_holding_siege(army):
		army.movement_remaining = 0.0
		return true
	return false

func _nearest_own_siege_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not city.is_under_siege or city.siege_faction != faction_id:
			continue
		var d := HexHelper.hex_distance(from, city.hex_pos)
		if d < best_d:
			best_d = d
			best = city.hex_pos
	return best

## Faction posture for the shared army loop. Keys on the PARENT faction so
## minor factions inherit their parent's doctrine. Postures:
##  "normal"    — generic attack-nearest behavior
##  "defensive" — hunt intruders in own lands, otherwise garrison cities
##  "pilgrim"   — Sunblessed at peace: park armies near friendly foreign
##                cities to farm faith/wisdom proximity (their core mechanic)
func _ai_army_posture(faction_id: StringName) -> String:
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null and parent_fid != faction_id:
		fs = GameManager.state.faction_states.get(parent_fid)
	if fs == null:
		return "normal"
	match parent_fid:
		&"thunderswarm":
			# Ride the fury: only take the field while the storm buff is live
			if fs.storm_fury < 30:
				return "defensive"
		&"moonspear":
			# Strike under the New/Waxing moon, hold under Full/Waning
			if fs.lunar_phase >= 2:
				return "defensive"
		&"cinderguard":
			# Fortress doctrine until the forges swing to war production
			if fs.border_vigilance < 60:
				return "defensive"
		&"ivoryscar":
			# Turtle until relic power or the Pyramid makes the tomb legions strong
			if fs.relic_power < 30 and not fs.pyramid_restored:
				return "defensive"
		&"sunblessed":
			if not _faction_has_any_war(faction_id):
				return "pilgrim"
	return "normal"

func _faction_has_any_war(faction_id: StringName) -> bool:
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, other_id) == Enums.FactionRelation.WAR:
			return true
	return false

## Pilgrim posture target: nearest foreign city worth teaching at (standing
## >= 20 matches the wisdom-farm threshold; fall back to any non-hostile).
## Returns the CITY hex — callers must stop at distance 2, never enter it.
func _find_pilgrimage_city_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var best_fallback := Vector2i(-1, -1)
	var best_fallback_d := 1 << 30
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id or city.faction_id == &"independent":
			continue
		if GameManager.get_relation(faction_id, city.faction_id) == Enums.FactionRelation.WAR:
			continue
		var d := HexHelper.hex_distance(from, city.hex_pos)
		var standing := GameManager.diplomacy_system.get_standing(faction_id, city.faction_id)
		if standing >= 20:
			if d < best_d:
				best_d = d
				best = city.hex_pos
		elif standing >= 0 and d < best_fallback_d:
			best_fallback_d = d
			best_fallback = city.hex_pos
	return best if best != Vector2i(-1, -1) else best_fallback

func _execute_ai_turn(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	var posture := _ai_army_posture(faction_id)
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	# Empire doctrine: legions consolidate into larger stacks before marching
	var min_attack_size := 5 if parent_fid == &"empire" else 3
	var intruder := Vector2i(-1, -1)
	if posture == "defensive":
		intruder = _find_nearest_intruder(faction_id, 3)
	var army_count := 0
	for army in armies:
		army_count += 1
		if army_count % 2 == 0:
			await _ai_wait()
		if army.movement_remaining <= 0:
			continue

		if _maybe_hold_siege_or_retarget(army, faction_id):
			continue

		# Defensive posture: repel intruders, otherwise garrison the nearest city
		if posture == "defensive":
			if intruder != Vector2i(-1, -1) and army.units.size() >= 3:
				_ai_move_army_safe(army, intruder, faction_id)
			else:
				_move_to_nearest_city(army, faction_id)
			if not GameManager.state.armies.has(army.army_id):
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return
			continue

		# Pilgrim posture: walk toward friendly foreign cities and hold at
		# distance 2 — solar_faith/wisdom grow from army proximity
		if posture == "pilgrim":
			var pilgrim_city := _find_pilgrimage_city_hex(army.hex_pos, faction_id)
			if pilgrim_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, pilgrim_city) > 2:
				# Aim for a tile beside the city, never the city hex itself
				var approach := pilgrim_city
				for n in HexHelper.get_neighbors(pilgrim_city):
					if HexHelper.hex_distance(army.hex_pos, n) < HexHelper.hex_distance(army.hex_pos, approach):
						approach = n
				if approach != pilgrim_city:
					_ai_move_army_safe(army, approach, faction_id)
			if not GameManager.state.armies.has(army.army_id):
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return
			continue

		# Don't attack with tiny armies
		if army.units.size() < min_attack_size:
			# Move toward nearest friendly city to consolidate
			var nearest_city := _find_nearest_faction_city(army.hex_pos, faction_id)
			if nearest_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, nearest_city) > 1:
				_ai_move_army_safe(army, nearest_city, faction_id)
				if not GameManager.state.armies.has(army.army_id):
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return
			continue

		# Find target: enemy armies first, then enemy regions.
		# Empire marches on territory; Forsaken only picks fights it can win.
		var target_hex := Vector2i(-1, -1)
		if parent_fid == &"empire":
			target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
			if target_hex == Vector2i(-1, -1):
				target_hex = _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		elif parent_fid == &"forsaken":
			target_hex = _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
			if target_hex != Vector2i(-1, -1):
				var prey: ArmyState = GameManager.get_army_at_tile(target_hex)
				if prey and prey.units.size() >= army.units.size():
					target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
		else:
			target_hex = _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			# No enemies — expand toward independent cities
			var fd: FactionData = DataManager.get_faction(faction_id)
			var expansion: float = fd.ai_personality.get("expansion", 0.3) if fd else 0.3
			if army.units.size() >= 4 and randf() < expansion:
				target_hex = _find_nearest_independent_city_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			continue

		# Prefer finishing an in-progress siege over opening a new front.
		var ongoing := _nearest_own_siege_hex(army.hex_pos, faction_id)
		if ongoing != Vector2i(-1, -1):
			target_hex = ongoing

		_ai_move_army_safe(army, target_hex, faction_id)
		if not GameManager.state.armies.has(army.army_id):
			continue
		if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
			return

	_end_current_faction_turn()

# ── Skulloath AI (Raider) ────────────────────────────────────

func _execute_skulloath_ai(faction_id: StringName) -> void:
	var cooldown: int = _ai_aggression_cooldown.get(faction_id, 0)
	if cooldown > 0:
		# Defensive phase: recruit, defend own cities, don't attack
		_ai_aggression_cooldown[faction_id] = cooldown - 1
		_execute_defensive_skulloath(faction_id)
		_end_current_faction_turn()
		return

	# Aggressive phase
	var armies := GameManager.get_faction_armies(faction_id)
	var attacked := false
	var army_count := 0
	for army in armies:
		army_count += 1
		if army_count % 2 == 0:
			await _ai_wait()
		if army.movement_remaining <= 0:
			continue

		if _maybe_hold_siege_or_retarget(army, faction_id):
			continue

		# Small armies (< 3 units) retreat to nearest friendly city
		if army.units.size() < 3:
			_move_to_nearest_city(army, faction_id)
			continue

		# Attack with 3+ unit armies
		var target_hex := _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			target_hex = _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			# Skulloath: raid independent cities when no enemies
			var fd: FactionData = DataManager.get_faction(faction_id)
			var expansion: float = fd.ai_personality.get("expansion", 0.4) if fd else 0.4
			if army.units.size() >= 4 and randf() < expansion:
				target_hex = _find_nearest_independent_city_hex(army.hex_pos, faction_id)
		if target_hex != Vector2i(-1, -1):
			if _ai_move_army_safe(army, target_hex, faction_id):
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
		_ai_move_army_safe(army, nearest_city, faction_id)

# ── Gladehost AI (Defensive Patrol) ──────────────────────────

func _execute_gladehost_ai(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)

	# Check for intruders first
	var intruder := _find_nearest_intruder(faction_id, 3)

	var army_count := 0
	for army in armies:
		army_count += 1
		if army_count % 2 == 0:
			await _ai_wait()
		if army.movement_remaining <= 0:
			continue

		if intruder != Vector2i(-1, -1):
			# Attack intruder
			_ai_move_army_safe(army, intruder, faction_id)
			if not GameManager.state.armies.has(army.army_id):
				_gladehost_waypoints.erase(army.army_id)
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return
		elif army.units.size() >= 4:
			# Gladehost: cautiously expand toward nearby independent cities
			var fd: FactionData = DataManager.get_faction(faction_id)
			var expansion: float = fd.ai_personality.get("expansion", 0.3) if fd else 0.3
			if randf() < expansion:
				var indie_hex := _find_nearest_independent_city_hex(army.hex_pos, faction_id)
				if indie_hex != Vector2i(-1, -1):
					_ai_move_army_safe(army, indie_hex, faction_id)
					if not GameManager.state.armies.has(army.army_id):
						_gladehost_waypoints.erase(army.army_id)
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return
					continue
		if intruder == Vector2i(-1, -1):
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
			_ai_move_army_safe(army, target, faction_id)
			if not GameManager.state.armies.has(army.army_id):
				_gladehost_waypoints.erase(army.army_id)
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return

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
	# Hoisted intruder scan (faction-relative, loop-invariant). Revalidated
	# whenever a battle changed the army set or the intruder hex emptied —
	# the only ways the per-army result could differ (enemies don't move and
	# regions only change via battles during our turn).
	var jade_intruder := _find_nearest_intruder(faction_id, 3)
	var jade_intruder_army_count := GameManager.state.armies.size()
	var army_count := 0
	for army in armies:
		army_count += 1
		if army_count % 2 == 0:
			await _ai_wait()
		if army.movement_remaining <= 0:
			continue

		# Build up to 4+ units before attacking
		if army.units.size() < 4:
			var nearest_city := _find_nearest_faction_city(army.hex_pos, faction_id)
			if nearest_city != Vector2i(-1, -1) and HexHelper.hex_distance(army.hex_pos, nearest_city) > 1:
				_ai_move_army_safe(army, nearest_city, faction_id)
				if not GameManager.state.armies.has(army.army_id):
					_jade_patrol_index.erase(army.army_id)
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return
			continue

		# Actively seek to conquer
		if GameManager.state.armies.size() != jade_intruder_army_count \
				or (jade_intruder != Vector2i(-1, -1) and GameManager.get_enemies_at_tile(jade_intruder, faction_id).is_empty()):
			jade_intruder = _find_nearest_intruder(faction_id, 3)
			jade_intruder_army_count = GameManager.state.armies.size()
		var intruder := jade_intruder
		if intruder != Vector2i(-1, -1):
			_ai_move_army_safe(army, intruder, faction_id)
			if not GameManager.state.armies.has(army.army_id):
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return
		else:
			# Expand toward enemy regions
			var target_hex := _find_nearest_enemy_region_hex(army.hex_pos, faction_id)
			if target_hex == Vector2i(-1, -1):
				# Tainted Jade: aggressively expand toward independent cities
				var fd: FactionData = DataManager.get_faction(faction_id)
				var expansion: float = fd.ai_personality.get("expansion", 0.5) if fd else 0.5
				if randf() < expansion:
					target_hex = _find_nearest_independent_city_hex(army.hex_pos, faction_id)
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
				_ai_move_army_safe(army, target_hex, faction_id)
				if not GameManager.state.armies.has(army.army_id):
					_jade_patrol_index.erase(army.army_id)
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return

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
	var army_count := 0
	for army in armies:
		army_count += 1
		if army_count % 2 == 0:
			await _ai_wait()
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
				_ai_move_army_safe(army, target_hex, faction_id)
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
					_ai_move_army_safe(army, nearest_beast_pos, faction_id)
					if not GameManager.state.armies.has(army.army_id):
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return

	# Build on elderbeasts
	_shardhorde_ai_build()

	# Recruit at elderbeasts
	_shardhorde_recruit()

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
			var score := udata.attack + udata.get_avg_defense()
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
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		if army.hex_pos == hex_pos:
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
		GameManager.invalidate_faction_army_cache()

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
	# Cache unit data lookups to avoid repeated DataManager calls for the same unit type
	var _unit_cache: Dictionary = {} # unit_data_id -> UnitData
	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		# Wounded commanders recover one turn at a time
		if army.commander and army.commander.wounded_turns > 0:
			army.commander.wounded_turns -= 1

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
				var unit_data: UnitData = _unit_cache.get(unit.unit_data_id)
				if unit_data == null:
					unit_data = DataManager.get_unit(unit.unit_data_id)
					if unit_data == null:
						continue
					_unit_cache[unit.unit_data_id] = unit_data
				var heal_amount := int(unit_data.max_hp * 0.15 * moonwell_mult) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
				if unit_data.squad_size > 1 and unit_data.hp_per_soldier > 0:
					if unit.current_hp < unit_data.max_hp:
						unit.current_hp = mini(unit.current_hp + unit_data.hp_per_soldier, unit_data.max_hp)
		elif tile and tile.owner_faction == faction_id:
			for unit in army.units:
				var unit_data: UnitData = _unit_cache.get(unit.unit_data_id)
				if unit_data == null:
					unit_data = DataManager.get_unit(unit.unit_data_id)
					if unit_data == null:
						continue
					_unit_cache[unit.unit_data_id] = unit_data
				var heal_amount := int(unit_data.max_hp * 0.05) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
		elif faction_id == &"shardhorde" and _is_in_undepleted_beast_range(army.hex_pos):
			# Shardhorde armies regenerate troops in undepleted elderbeast territory
			for unit in army.units:
				var unit_data: UnitData = _unit_cache.get(unit.unit_data_id)
				if unit_data == null:
					unit_data = DataManager.get_unit(unit.unit_data_id)
					if unit_data == null:
						continue
					_unit_cache[unit.unit_data_id] = unit_data
				var heal_amount := int(unit_data.max_hp * 0.10) + cmd_heal
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
		elif cmd_heal > 0:
			# Commander heals even in neutral territory
			for unit in army.units:
				var unit_data: UnitData = _unit_cache.get(unit.unit_data_id)
				if unit_data == null:
					unit_data = DataManager.get_unit(unit.unit_data_id)
					if unit_data == null:
						continue
					_unit_cache[unit.unit_data_id] = unit_data
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

# ── Diplomacy Standing Bonuses (from research + buildings) ──
func _apply_diplomacy_bonuses(faction_id: StringName) -> void:
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var r_eff := GameManager.research_system.get_research_effects(parent_fid)
	var standing_per_turn: int = r_eff.get("standing_per_turn", 0)
	var diplo_bonus: int = r_eff.get("diplomacy_standing_bonus", 0)
	# Building special_effects: diplomacy_standing_bonus
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for bid in city.buildings:
					var bld := DataManager.get_building(bid)
					if bld and bld.special_effects.has("diplomacy_standing_bonus"):
						diplo_bonus += int(bld.special_effects["diplomacy_standing_bonus"])
	var total_bonus := standing_per_turn + diplo_bonus
	if total_bonus > 0 and GameManager.diplomacy_system:
		for other_id in GameManager.state.faction_states:
			if other_id == faction_id or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if GameManager.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
				GameManager.diplomacy_system.modify_standing(faction_id, other_id, total_bonus, "Diplomatic influence")

# ── Terrain Attrition ───────────────────────────────────────

func _apply_terrain_attrition(faction_id: StringName) -> void:
	var fd: FactionData = DataManager.get_faction(faction_id)
	var is_nature := fd and fd.realm_affinity == Enums.Realm.NATURE
	var is_void := fd and fd.realm_affinity == Enums.Realm.VOID
	# Cache unit data lookups to avoid repeated calls for the same unit type
	var _unit_cache: Dictionary = {} # unit_data_id -> UnitData

	for army: ArmyState in GameManager.get_all_faction_armies(faction_id):
		if army.is_garrison:
			continue

		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
		if tile == null:
			continue

		# Skip attrition in cities (sheltered)
		if GameManager.city_system.get_city_at_hex(army.hex_pos) != null:
			continue

		# Research: attrition reduction
		var attrition_reduction := army.get_attrition_reduction()

		match tile.terrain:
			Enums.TerrainType.SHARD_WASTES:
				# Light damage to all — void-aligned take less
				var dmg_pct := 0.02 if is_void else 0.05
				dmg_pct *= (1.0 - attrition_reduction)
				for unit in army.units:
					var ud: UnitData = _unit_cache.get(unit.unit_data_id)
					if ud == null:
						ud = DataManager.get_unit(unit.unit_data_id)
						if ud == null:
							continue
						_unit_cache[unit.unit_data_id] = ud
					var dmg := maxi(1, int(ud.max_hp * dmg_pct))
					unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.DESERT:
				# Moderate damage — void-aligned take less, nature takes more
				var dmg_pct := 0.03
				if is_void:
					dmg_pct = 0.01
				elif is_nature:
					dmg_pct = 0.05
				dmg_pct *= (1.0 - attrition_reduction)
				for unit in army.units:
					var ud: UnitData = _unit_cache.get(unit.unit_data_id)
					if ud == null:
						ud = DataManager.get_unit(unit.unit_data_id)
						if ud == null:
							continue
						_unit_cache[unit.unit_data_id] = ud
					var dmg := maxi(1, int(ud.max_hp * dmg_pct))
					unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.JUNGLE:
				# Nature-aligned units heal, others take upkeep penalty
				for unit in army.units:
					var ud: UnitData = _unit_cache.get(unit.unit_data_id)
					if ud == null:
						ud = DataManager.get_unit(unit.unit_data_id)
						if ud == null:
							continue
						_unit_cache[unit.unit_data_id] = ud
					if is_nature:
						# Heal 3% max HP
						var heal := maxi(1, int(ud.max_hp * 0.03))
						unit.current_hp = mini(unit.current_hp + heal, ud.max_hp)
					else:
						# Non-nature: light damage from hostile vegetation
						var dmg_pct := 0.02 * (1.0 - attrition_reduction)
						var dmg := maxi(1, int(ud.max_hp * dmg_pct))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.TUNDRA:
				# Cold attrition — light damage, nature-aligned take more
				var dmg_pct := 0.02
				if is_nature:
					dmg_pct = 0.04
				elif is_void:
					dmg_pct = 0.01
				dmg_pct *= (1.0 - attrition_reduction)
				for unit in army.units:
					var ud: UnitData = _unit_cache.get(unit.unit_data_id)
					if ud == null:
						ud = DataManager.get_unit(unit.unit_data_id)
						if ud == null:
							continue
						_unit_cache[unit.unit_data_id] = ud
					var dmg := maxi(1, int(ud.max_hp * dmg_pct))
					unit.current_hp = maxi(1, unit.current_hp - dmg)

			Enums.TerrainType.SWAMP:
				# Disease attrition — hurts everyone except constructs
				for unit in army.units:
					var ud: UnitData = _unit_cache.get(unit.unit_data_id)
					if ud == null:
						ud = DataManager.get_unit(unit.unit_data_id)
						if ud == null:
							continue
						_unit_cache[unit.unit_data_id] = ud
					if not ud.tags.has("construct"):
						var dmg_pct := 0.03 * (1.0 - attrition_reduction)
						var dmg := maxi(1, int(ud.max_hp * dmg_pct))
						unit.current_hp = maxi(1, unit.current_hp - dmg)

	# Remove dead units (HP <= 0 shouldn't happen since we floor at 1, but clean up 0-hp units)
	_clean_dead_units(faction_id)

func _clean_dead_units(_faction_id: StringName) -> void:
	# No auto-removal: attrition weakens but doesn't kill. Units die in battle.
	pass

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
		"text": "A mysterious merchant offers rare goods. The price depends on the quality of their wares.",
		"choice_a": "Buy goods",
		"choice_b": "Trade provisions instead",
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
		"choice_a": "Accept commander (new Lv3 commander)",
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

const FACTION_DILEMMAS := {
	&"skulloath": [
		{
			"title": "Dark Communion",
			"text": "Shamans urge a blood ritual to commune with the Pale Waif. Power flows freely... at a cost.",
			"choice_a": "Perform the ritual (+15 Corruption, +20 Gold)",
			"choice_b": "Refuse the darkness (-5 Corruption, +10 Loyalty)",
			"type": "skulloath_dark_communion",
		},
		{
			"title": "Tainted Grazing",
			"text": "Void-touched pastures yield unnatural bounty, but the herds grow sickly and wrong.",
			"choice_a": "Graze the tainted fields (+8 Corruption, +30 Food)",
			"choice_b": "Purify the water (-3 Corruption, -15 Food)",
			"type": "skulloath_tainted_grazing",
		},
		{
			"title": "Spirit Pact",
			"text": "Ancestor spirits demand a blood tribute in exchange for warriors from beyond the veil.",
			"choice_a": "Blood tribute (+10 Corruption, free unit)",
			"choice_b": "Peace offering (-5 Corruption, +15 Tech)",
			"type": "skulloath_spirit_pact",
		},
		{
			"title": "Raiding Frenzy",
			"text": "Your riders are drunk on bloodlust. Let them raid... or rein them in?",
			"choice_a": "Raid (+12 Corruption, +40 Gold, -8 standing)",
			"choice_b": "Discipline (-8 Corruption, +5 Loyalty)",
			"type": "skulloath_raiding_frenzy",
		},
		{
			"title": "Bone Oracle",
			"text": "A bone-reader offers forbidden knowledge scrawled in void-script.",
			"choice_a": "Study the dark texts (+20 Corruption, +30 Tech)",
			"choice_b": "Reject the oracle (-10 Corruption, +15 Loyalty)",
			"type": "skulloath_bone_oracle",
		},
		{
			"title": "Runic Corruption",
			"text": "Void runes pulse beneath a captured shard site. Feed them... or cleanse?",
			"choice_a": "Feed the runes (+15 Corruption, +atk buff 8 turns)",
			"choice_b": "Purify the runes (-10 Corruption)",
			"type": "skulloath_runic_corruption",
		},
	],
	&"sunblessed": [
		{
			"title": "Solar Pilgrimage",
			"text": "Faithful citizens wish to embark on a pilgrimage to the Solar Citadel. It will cost resources but inspire the nation.",
			"choice_a": "Fund the pilgrimage (+15 Faith, -20 Gold)",
			"choice_b": "Put them to work (-5 Faith, +15 Iron)",
			"type": "sunblessed_pilgrimage",
		},
		{
			"title": "Heretic Purge",
			"text": "Heretical sects have been found spreading doubt. The faithful demand purification.",
			"choice_a": "Purge the heretics (+20 Faith, -10 Loyalty)",
			"choice_b": "Show mercy (+10 Loyalty, -5 Faith)",
			"type": "sunblessed_heretic_purge",
		},
		{
			"title": "Dawn Revelation",
			"text": "A priest receives a divine vision. Share it with allies, or study it privately?",
			"choice_a": "Share revelation (+10 Faith, +10 standing)",
			"choice_b": "Hoard knowledge (+15 Tech, -5 Faith)",
			"type": "sunblessed_dawn_revelation",
		},
	],
	&"gladehost": [
		{
			"title": "Forest Expansion",
			"text": "Druids wish to plant sacred groves, but it requires precious lumber.",
			"choice_a": "Plant sacred trees (+10 Harmony, -20 Wood)",
			"choice_b": "Harvest timber (-8 Harmony, +30 Wood)",
			"type": "gladehost_forest_expansion",
		},
		{
			"title": "Grove Preservation",
			"text": "Settlers wish to clear an ancient grove for farmland. The grove-wardens protest.",
			"choice_a": "Protect the grove (+15 Harmony, -15 Gold)",
			"choice_b": "Clear for farmland (-12 Harmony, +25 Food)",
			"type": "gladehost_grove_preservation",
		},
		{
			"title": "Ancient Seed",
			"text": "An ancient seed from the World Tree has been found. It hums with primal power.",
			"choice_a": "Nurture the seed (+12 Harmony, +10 Tech)",
			"choice_b": "Sell to scholars (-5 Harmony, +30 Gold)",
			"type": "gladehost_ancient_seed",
		},
	],
	&"thunderswarm": [
		{
			"title": "Storm Fury Surge",
			"text": "Lightning strikes the mountain peak. The storm-callers can channel this energy... or let it dissipate safely.",
			"choice_a": "Channel the fury (+15 Storm Fury, +20 Iron)",
			"choice_b": "Let it pass (-10 Storm Fury, +15 Food)",
			"type": "thunderswarm_fury_surge",
		},
		{
			"title": "Thunder Beast Taming",
			"text": "A wild storm beast rampages near your camp. Break it... or befriend it?",
			"choice_a": "Wild taming (+10 Storm Fury, free unit)",
			"choice_b": "Gentle approach (-8 Storm Fury, +10 Loyalty)",
			"type": "thunderswarm_beast_taming",
		},
		{
			"title": "Lightning Strike",
			"text": "A massive storm gathers. Ride into it for glory, or shelter your people?",
			"choice_a": "Ride the storm (+20 Storm Fury, +XP)",
			"choice_b": "Shelter (-10 Storm Fury, +20 Gold)",
			"type": "thunderswarm_lightning_strike",
		},
	],
	&"cinderguard": [
		{
			"title": "Scavenger Report",
			"text": "Scouts found a wrecked caravan in the wastes. Salvage the iron, or search for survivors?",
			"choice_a": "Strip it for parts (+15 Scrap, +10 Iron)",
			"choice_b": "Search for survivors (+3 Pop to nearest settlement, +5 Gold)",
			"type": "cinderguard_scavenge",
		},
		{
			"title": "Drake Sighting",
			"text": "A young drake has been spotted near the border. The hunters want to bring it down for materials.",
			"choice_a": "Hunt the drake (+10 Vigilance, +20 Iron, +8 Scrap)",
			"choice_b": "Let it pass (-5 Vigilance, +10 Gold — peaceful trade route stays open)",
			"type": "cinderguard_drake_sighting",
		},
		{
			"title": "Outpost in Peril",
			"text": "A border settlement reports their walls are crumbling. They need supplies, or they'll abandon the post.",
			"choice_a": "Send supplies (-15 Iron, +10 Scrap to stockpile, +5 Loyalty)",
			"choice_b": "Order them to hold (-8 Loyalty, +12 Vigilance)",
			"type": "cinderguard_outpost_peril",
		},
	],
	&"moonspear": [
		{
			"title": "Lunar Ritual",
			"text": "The moon-priests can force an eclipse to gain power, disrupting the natural phase cycle.",
			"choice_a": "Force the eclipse (advance phase +2, +20 Tech)",
			"choice_b": "Honor the cycle (+15 Gold)",
			"type": "moonspear_lunar_ritual",
		},
		{
			"title": "Moonstone Discovery",
			"text": "A cache of moonstones pulses with lunar energy. Empower your warriors, or trade them?",
			"choice_a": "Empower army (+atk buff 8 turns)",
			"choice_b": "Sell moonstones (+40 Gold)",
			"type": "moonspear_moonstone",
		},
		{
			"title": "Celestial Alignment",
			"text": "The stars align in a once-in-a-generation pattern. The moon-priests can harness it.",
			"choice_a": "Harness the alignment (+20 Tech, +10 Loyalty)",
			"choice_b": "Observe only (+25 Gold)",
			"type": "moonspear_celestial",
		},
	],
	&"tainted_jade": [
		{
			"title": "Jungle Communion",
			"text": "The jungle itself whispers of power hidden in corrupted roots. Drink deep... or resist.",
			"choice_a": "Absorb the power (+15 Taint, +20 Food)",
			"choice_b": "Resist the call (-10 Taint, +10 Loyalty)",
			"type": "tainted_jade_communion",
		},
		{
			"title": "Corruption Spread",
			"text": "Tainted vines creep toward allied territory. Embrace the spread, or contain it?",
			"choice_a": "Embrace the spread (+12 Taint, -10 standing)",
			"choice_b": "Contain it (-8 Taint, +15 Tech)",
			"type": "tainted_jade_corruption_spread",
		},
		{
			"title": "Serpent Vision",
			"text": "The great serpent sends visions of hidden paths. Following them requires... sacrifice.",
			"choice_a": "Follow the vision (+10 Taint, +XP)",
			"choice_b": "Ignore the serpent (-5 Taint, +20 Gold)",
			"type": "tainted_jade_serpent_vision",
		},
	],
}

func _check_random_events(faction_id: StringName) -> void:
	if GameManager.state.current_turn <= 1:
		return
	# Cooldown: no events within 2 turns of each other
	if _event_cooldown > 0:
		_event_cooldown -= 1
		return

	var turn := GameManager.state.current_turn
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)

	# Check if player has any free follower slots across all commanders
	var has_follower_slots := false
	if fs:
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == faction_id and army.commander:
				if army.commander.followers.size() < CommanderSystem.get_max_follower_slots(army.commander):
					has_follower_slots = true
					break
		if not has_follower_slots and fs.follower_storage.size() > 0:
			has_follower_slots = false # storage has items but no slots - skip follower events

	# Check if player has no followers yet (for guaranteed first follower)
	var has_no_followers := true
	if fs:
		if fs.follower_storage.size() > 0:
			has_no_followers = false
		else:
			for army_id in GameManager.state.armies:
				var army: ArmyState = GameManager.state.armies[army_id]
				if army.faction_id == faction_id and army.commander and army.commander.followers.size() > 0:
					has_no_followers = false
					break

	# Guaranteed first follower on a random turn in 3-7 if player has none
	var force_follower := false
	if has_no_followers and faction_id == GameManager.state.player_faction_id:
		# Pick the guaranteed turn once (persisted across saves)
		if _first_follower_turn < 0:
			_first_follower_turn = 3 + randi() % 5  # 3, 4, 5, 6, or 7
		if turn == _first_follower_turn:
			force_follower = true

	if not force_follower and randf() > 0.20:
		return # 20% chance per turn (up from 12%)

	# Weight events by game stage
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
		var ev_type: String = ev.get("type", "")
		# Skip follower events if no slots available
		if ev_type == "follower" and not has_follower_slots and (fs == null or fs.follower_storage.size() == 0):
			continue
		var ev_stage: String = ev.get("stage", "early")
		if ev_stage == stage_preference:
			weighted_pool.append(ev)
			weighted_pool.append(ev) # Double weight for matching stage
		else:
			weighted_pool.append(ev)
		# Give follower events 3x weight when player has free slots
		if ev_type == "follower" and has_follower_slots:
			weighted_pool.append(ev)
			weighted_pool.append(ev) # +2 extra copies = 3x total base weight

	if weighted_pool.is_empty():
		return

	# If forcing follower event, pick the follower event directly
	var event: Dictionary
	if force_follower:
		for ev in RANDOM_EVENTS:
			if ev.get("type", "") == "follower":
				event = ev.duplicate()
				break
		if event.is_empty():
			return
	else:
		# 30% chance to pick a faction-specific dilemma instead of generic event
		var faction_pool: Array = FACTION_DILEMMAS.get(faction_id, [])
		if faction_pool.size() > 0 and randf() < 0.30:
			event = faction_pool[randi() % faction_pool.size()].duplicate()
		else:
			event = weighted_pool[randi() % weighted_pool.size()].duplicate()

	event["faction_id"] = faction_id
	event["selected_army_id"] = GameManager.state.selected_army_id

	# Inject target faction for dispute events
	if event.get("requires_weak_neighbor", false) and weak_neighbor_id != &"":
		event["target_faction_id"] = weak_neighbor_id
		var target_fd: FactionData = DataManager.get_faction(weak_neighbor_id)
		var target_name: String = target_fd.display_name if target_fd else str(weak_neighbor_id)
		event["text"] = "An emissary from %s arrives at your border, seeking to negotiate." % target_name
		event["choice_b"] = "Demand tribute from %s (+30 Iron, -10 standing)" % target_name

	_event_cooldown = 2
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
				# Variable gold cost based on game stage
				var turn: int = GameManager.state.current_turn if GameManager.state else 1
				var gold_cost := 40
				if turn >= 30:
					gold_cost = 80
				elif turn >= 15:
					gold_cost = 60
				if fs.resources.get(Enums.ResourceType.GOLD, 0) >= gold_cost:
					fs.resources[Enums.ResourceType.GOLD] -= gold_cost
					var armies := GameManager.get_faction_armies(faction_id)
					for army in armies:
						var max_slots := CommanderSystem.get_max_item_slots(army.commander) if army.commander else 0
						if army.commander and army.commander.items.size() < max_slots:
							var item_name := CommanderSystem.apply_item_drop(army.commander, faction_id)
							if item_name != "":
								return "Spent %d Gold. Acquired: %s" % [gold_cost, item_name]
							return "Spent %d Gold but the merchant had nothing worthwhile." % gold_cost
					return "Spent %d Gold but no commander could carry the goods." % gold_cost
				else:
					return "Not enough gold! (need %d)" % gold_cost
			else:
				# Declining gives food and some wood from trading provisions
				var food_gain := 20 + randi() % 15
				var wood_gain := 10 + randi() % 10
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + food_gain
				fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + wood_gain
				return "The merchant trades provisions instead. +%d Food, +%d Wood." % [food_gain, wood_gain]
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
					GameManager.diplomacy_system.modify_standing(faction_id, target_fid, 5, "Diplomatic envoy")
				return "Relations improved with %s. (+5 standing)" % target_name
			else:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 30
				if target_fid != &"":
					GameManager.diplomacy_system.modify_standing(faction_id, target_fid, -10, "Demanded tribute")
				return "Demanded tribute from %s. +30 Iron, -10 standing with %s." % [target_name, target_name]

		"follower":
			if choice == "a":
				# Determine army terrain for follower filtering
				var army_terrain_str: StringName = &""
				var sel_aid: StringName = event.get("selected_army_id", &"")
				var ref_army: ArmyState = null
				if sel_aid != &"" and GameManager.state.armies.has(sel_aid):
					ref_army = GameManager.state.armies[sel_aid]
				else:
					# Fallback: pick any army belonging to this faction
					for a_id in GameManager.state.armies:
						var a: ArmyState = GameManager.state.armies[a_id]
						if a.faction_id == faction_id:
							ref_army = a
							break
				if ref_army:
					var tile := GameManager.state.hex_map.get_tile(ref_army.hex_pos)
					if tile:
						army_terrain_str = TERRAIN_TO_STRING.get(tile.terrain, &"")

				# Filter followers by terrain tags
				var all_followers := DataManager.followers.keys()
				var terrain_filtered: Array[StringName] = []
				for fid in all_followers:
					var fd: FollowerData = DataManager.get_follower(fid)
					if fd == null:
						continue
					if fd.terrain_tags.is_empty():
						terrain_filtered.append(fid)  # universal follower
					elif army_terrain_str != &"" and fd.terrain_tags.has(army_terrain_str):
						terrain_filtered.append(fid)
				if terrain_filtered.is_empty():
					# Fallback to full pool if nothing matched
					terrain_filtered.assign(all_followers)
				if terrain_filtered.is_empty():
					return "No followers available."
				var follower_id: StringName = terrain_filtered[randi() % terrain_filtered.size()]
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
					# Clamp movement_remaining for all armies with this commander
					for a_id in GameManager.state.armies:
						var a: ArmyState = GameManager.state.armies[a_id]
						if a.commander == target_cmd:
							var new_max := a.get_max_movement()
							a.movement_remaining = minf(a.movement_remaining, new_max)
					# Invalidate movement cache so reachable tiles refresh
					GameManager.movement_system._cache_valid = false
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
				var new_cmd := GameManager._create_commander(faction_id)
				new_cmd.level = 3
				new_cmd.xp = CommanderState.XP_THRESHOLDS[2] if CommanderState.XP_THRESHOLDS.size() > 2 else 120
				fs.commander_pool.append(new_cmd)
				return "%s (Lv3) joined your commander pool." % new_cmd.name
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
						GameManager.diplomacy_system.modify_standing(faction_id, other_id, 15, "Marriage alliance")
						return "Marriage alliance formed. +15 standing with a neighbor."
				return "No suitable faction for marriage."
			else:
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					capital.class_loyalty["nobles"] = clampi(capital.class_loyalty.get("nobles", 0) + 5, -100, 100)
				return "Marriage declined respectfully. +5 Noble loyalty."

		# ── Skulloath Corruption Dilemmas ──
		"skulloath_dark_communion":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 15, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 20
				return "The ritual is done. Corruption surges. +15 Corruption, +20 Gold."
			else:
				fs.corruption = clampi(fs.corruption - 5, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "The shamans are turned away. -5 Corruption, +loyalty."

		"skulloath_tainted_grazing":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 8, 0, 100)
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 30
				return "The herds feed on cursed pastures. +8 Corruption, +30 Food."
			else:
				fs.corruption = clampi(fs.corruption - 3, 0, 100)
				fs.resources[Enums.ResourceType.FOOD] = maxi(0, fs.resources.get(Enums.ResourceType.FOOD, 0) - 15)
				return "Clean water purifies the land. -3 Corruption, -15 Food."

		"skulloath_spirit_pact":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 10, 0, 100)
				var armies := GameManager.get_faction_armies(faction_id)
				if armies.size() > 0:
					_spawn_unit_at_hex(&"pale_touched", faction_id, armies[0].hex_pos)
					return "Blood spilled. A spirit warrior manifests. +10 Corruption, +Pale Touched."
				return "Blood spilled, but no army to receive the spirit. +10 Corruption."
			else:
				fs.corruption = clampi(fs.corruption - 5, 0, 100)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
				return "Ancestors share wisdom peacefully. -5 Corruption, +15 Tech."

		"skulloath_raiding_frenzy":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 12, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 40
				for other_id in GameManager.state.faction_states:
					if other_id == faction_id or GameManager.is_npc_faction(other_id):
						continue
					if not GameManager.state.faction_states[other_id].is_defeated:
						GameManager.diplomacy_system.modify_standing(faction_id, other_id, -8, "Raiding frenzy")
						break
				return "Riders unleashed! +12 Corruption, +40 Gold, -8 standing."
			else:
				fs.corruption = clampi(fs.corruption - 8, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 2, -100, 100)
				return "Discipline restored. -8 Corruption, +loyalty."

		"skulloath_bone_oracle":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 20, 0, 100)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 30
				return "Forbidden texts consumed. +20 Corruption, +30 Tech."
			else:
				fs.corruption = clampi(fs.corruption - 10, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 4, -100, 100)
				return "The oracle is banished. -10 Corruption, +loyalty."

		"skulloath_runic_corruption":
			if choice == "a":
				fs.corruption = clampi(fs.corruption + 15, 0, 100)
				_temp_effects.append({
					"faction_id": faction_id,
					"effect": "attack_bonus",
					"value": 3,
					"turns_remaining": 8,
				})
				return "Void runes empowered! +15 Corruption, +3 attack for 8 turns."
			else:
				fs.corruption = clampi(fs.corruption - 10, 0, 100)
				return "Runes cleansed. -10 Corruption."

		# ── Sunblessed Solar Faith Dilemmas ──
		"sunblessed_pilgrimage":
			if choice == "a":
				fs.solar_faith = clampi(fs.solar_faith + 15, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 20)
				return "The pilgrimage inspires the faithful. +15 Faith, -20 Gold."
			else:
				fs.solar_faith = clampi(fs.solar_faith - 5, 0, 100)
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 15
				return "Workers sent to the mines instead. -5 Faith, +15 Iron."

		"sunblessed_heretic_purge":
			if choice == "a":
				fs.solar_faith = clampi(fs.solar_faith + 20, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] - 3, -100, 100)
				return "Heretics purged. The temple burns bright. +20 Faith, -loyalty."
			else:
				fs.solar_faith = clampi(fs.solar_faith - 5, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "Mercy shown to the doubters. +loyalty, -5 Faith."

		"sunblessed_dawn_revelation":
			if choice == "a":
				fs.solar_faith = clampi(fs.solar_faith + 10, 0, 100)
				for other_id in GameManager.state.faction_states:
					if other_id == faction_id or GameManager.is_npc_faction(other_id):
						continue
					if not GameManager.state.faction_states[other_id].is_defeated:
						GameManager.diplomacy_system.modify_standing(faction_id, other_id, 10, "Shared revelation")
						break
				return "Revelation shared with allies. +10 Faith, +10 standing."
			else:
				fs.solar_faith = clampi(fs.solar_faith - 5, 0, 100)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
				return "Knowledge hoarded. +15 Tech, -5 Faith."

		# ── Gladehost Harmony Dilemmas ──
		"gladehost_forest_expansion":
			if choice == "a":
				fs.harmony = clampi(fs.harmony + 10, 0, 100)
				fs.resources[Enums.ResourceType.WOOD] = maxi(0, fs.resources.get(Enums.ResourceType.WOOD, 0) - 20)
				return "Sacred groves planted. +10 Harmony, -20 Wood."
			else:
				fs.harmony = clampi(fs.harmony - 8, 0, 100)
				fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + 30
				return "Timber harvested. -8 Harmony, +30 Wood."

		"gladehost_grove_preservation":
			if choice == "a":
				fs.harmony = clampi(fs.harmony + 15, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 15)
				return "The grove stands protected. +15 Harmony, -15 Gold."
			else:
				fs.harmony = clampi(fs.harmony - 12, 0, 100)
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 25
				return "Farmland cleared. -12 Harmony, +25 Food."

		"gladehost_ancient_seed":
			if choice == "a":
				fs.harmony = clampi(fs.harmony + 12, 0, 100)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 10
				return "The seed grows, sharing ancient wisdom. +12 Harmony, +10 Tech."
			else:
				fs.harmony = clampi(fs.harmony - 5, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 30
				return "Scholars pay handsomely. -5 Harmony, +30 Gold."

		# ── Thunderswarm Storm Fury Dilemmas ──
		"thunderswarm_fury_surge":
			if choice == "a":
				fs.storm_fury = clampi(fs.storm_fury + 15, 0, 100)
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 20
				return "Lightning channeled into the armories! +15 Storm Fury, +20 Iron."
			else:
				fs.storm_fury = clampi(fs.storm_fury - 10, 0, 100)
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 15
				return "The storm passes peacefully. -10 Storm Fury, +15 Food."

		"thunderswarm_beast_taming":
			if choice == "a":
				fs.storm_fury = clampi(fs.storm_fury + 10, 0, 100)
				var armies := GameManager.get_faction_armies(faction_id)
				if armies.size() > 0:
					_spawn_unit_at_hex(&"windrunner", faction_id, armies[0].hex_pos)
					return "Beast broken to the saddle! +10 Storm Fury, +Windrunner."
				return "No army nearby to receive the beast. +10 Storm Fury."
			else:
				fs.storm_fury = clampi(fs.storm_fury - 8, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "The beast is calmed and released. -8 Storm Fury, +loyalty."

		"thunderswarm_lightning_strike":
			if choice == "a":
				fs.storm_fury = clampi(fs.storm_fury + 20, 0, 100)
				var armies := GameManager.get_faction_armies(faction_id)
				for army in armies:
					if army.commander:
						army.commander.xp += 30
						CommanderSystem._check_level_up(army.commander)
						return "Rode the storm's heart! +20 Storm Fury, %s +30 XP." % army.commander.name
				return "Rode the storm! +20 Storm Fury."
			else:
				fs.storm_fury = clampi(fs.storm_fury - 10, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 20
				return "Sheltered from the tempest. -10 Storm Fury, +20 Gold."

		# ── Cinderguard Border Vigilance Dilemmas ──
		"cinderguard_scavenge":
			if choice == "a":
				fs.scavenge_stockpile += 15
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 10
				return "The wreck yielded good salvage. +15 Scrap, +10 Iron."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 5
				# Add pop to nearest settlement
				for cid in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(cid)
					if city and city.is_settlement:
						city.population += 3
						break
				return "Survivors rescued and brought to the nearest outpost. +3 Pop, +5 Gold."

		"cinderguard_drake_sighting":
			if choice == "a":
				fs.border_vigilance = clampi(fs.border_vigilance + 10, 0, 100)
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 20
				fs.scavenge_stockpile += 8
				return "Drake brought down! The carcass yields scales and bones. +10 Vigilance, +20 Iron, +8 Scrap."
			else:
				fs.border_vigilance = clampi(fs.border_vigilance - 5, 0, 100)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 10
				return "The drake passes peacefully. Trade routes remain safe. -5 Vigilance, +10 Gold."

		"cinderguard_outpost_peril":
			if choice == "a":
				fs.resources[Enums.ResourceType.IRON] = maxi(0, fs.resources.get(Enums.ResourceType.IRON, 0) - 15)
				fs.scavenge_stockpile += 10
				for cid in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(cid)
					if city and city.is_settlement:
						for cls in city.class_loyalty:
							if cls != "captives":
								city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 5, -100, 100)
						break
				return "Supplies sent to the outpost. The settlers are grateful. -15 Iron, +10 Scrap, +5 Loyalty."
			else:
				fs.border_vigilance = clampi(fs.border_vigilance + 12, 0, 100)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] - 3, -100, 100)
				return "The settlers hold the line despite crumbling walls. +12 Vigilance, -loyalty."

		# ── Moonspear Lunar Phase Dilemmas ──
		"moonspear_lunar_ritual":
			if choice == "a":
				fs.lunar_phase = (fs.lunar_phase + 2) % 4
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 20
				var phase_names := ["New Moon", "Waxing Moon", "Full Moon", "Waning Moon"]
				return "Eclipse forced! Phase shifted to %s. +20 Tech." % phase_names[fs.lunar_phase]
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 15
				return "The natural cycle continues. +15 Gold."

		"moonspear_moonstone":
			if choice == "a":
				_temp_effects.append({
					"faction_id": faction_id,
					"effect": "attack_bonus",
					"value": 2,
					"turns_remaining": 8,
				})
				return "Warriors empowered by moonstone! +2 attack for 8 turns."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 40
				return "Moonstones sold to merchants. +40 Gold."

		"moonspear_celestial":
			if choice == "a":
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 20
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "Celestial power harnessed! +20 Tech, +loyalty."
			else:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 25
				return "A rare sight, nothing more. +25 Gold."

		# ── Tainted Jade Taint Power Dilemmas ──
		"tainted_jade_communion":
			if choice == "a":
				fs.taint_power = clampi(fs.taint_power + 15, 0, 100)
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 20
				return "The jungle's corruption feeds your people. +15 Taint, +20 Food."
			else:
				fs.taint_power = maxi(0, fs.taint_power - 10)
				var capital := GameManager.policy_system._get_faction_capital(faction_id)
				if capital:
					for cls in capital.class_loyalty:
						if cls != "captives":
							capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] + 3, -100, 100)
				return "The call resisted. -10 Taint, +loyalty."

		"tainted_jade_corruption_spread":
			if choice == "a":
				fs.taint_power = clampi(fs.taint_power + 12, 0, 100)
				for other_id in GameManager.state.faction_states:
					if other_id == faction_id or GameManager.is_npc_faction(other_id):
						continue
					if not GameManager.state.faction_states[other_id].is_defeated:
						GameManager.diplomacy_system.modify_standing(faction_id, other_id, -10, "Corruption spread")
						break
				return "Tainted vines spread unchecked. +12 Taint, -10 standing."
			else:
				fs.taint_power = maxi(0, fs.taint_power - 8)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
				return "Corruption contained and studied. -8 Taint, +15 Tech."

		"tainted_jade_serpent_vision":
			if choice == "a":
				fs.taint_power = clampi(fs.taint_power + 10, 0, 100)
				var armies := GameManager.get_faction_armies(faction_id)
				for army in armies:
					if army.commander:
						army.commander.xp += 25
						CommanderSystem._check_level_up(army.commander)
						return "The serpent reveals hidden paths. +10 Taint, %s +25 XP." % army.commander.name
				return "Vision followed but no commander to guide. +10 Taint."
			else:
				fs.taint_power = maxi(0, fs.taint_power - 5)
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 20
				return "The serpent's whispers ignored. -5 Taint, +20 Gold."

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

# Per-turn unit stat cache for army strength calculations (cleared each faction turn via _border_cache clear)
var _unit_stat_cache: Dictionary = {} # unit_data_id -> {attack: int, defense: int}

func _get_army_strength(army: ArmyState) -> int:
	var strength := 0
	for unit in army.units:
		var cached = _unit_stat_cache.get(unit.unit_data_id)
		if cached == null:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud:
				cached = {attack = ud.attack, defense = ud.get_avg_defense()}
				_unit_stat_cache[unit.unit_data_id] = cached
			else:
				continue
		strength += cached.attack + cached.defense
	return strength

func _find_nearest_enemy_army_hex(from: Vector2i, faction_id: StringName, min_strength: int = 0) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	# Only iterate armies of factions we're at war with
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
			continue
		for army: ArmyState in GameManager.get_faction_armies(other_id):
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

func _find_nearest_independent_city_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != &"independent":
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
	# Only iterate armies of factions at war with us
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
			continue
		for army: ArmyState in GameManager.get_faction_armies(other_id):
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
		army.hex_pos, target, faction_id, max_cost, &"", army.can_cross_mountains(), army)
	if path.is_empty():
		return path
	# Truncate path to what the army can actually walk this turn
	var truncated: Array[Vector2i] = []
	var remaining := army.movement_remaining
	for coord in path:
		var cost := GameManager.state.hex_map.get_movement_cost(coord, faction_id)
		var tile := GameManager.state.hex_map.get_tile(coord)
		if tile:
			cost *= army.get_terrain_stride_modifier(tile.terrain)
		if remaining < cost:
			break
		remaining -= cost
		truncated.append(coord)
	return truncated

## Convenience wrapper: find a path and move the army along it.
## Returns true if the army actually moved (path was found and non-empty).
func _ai_move_army_safe(army: ArmyState, target: Vector2i, faction_id: StringName) -> bool:
	if army.hex_pos == target:
		return false
	var path := _ai_find_path(army, target, faction_id)
	if path.is_empty():
		return false
	GameManager.move_army_along_path(army.army_id, path)
	return true

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

# One walk over cities x buildings accumulates ALL special_effects keys; the
# 2-3 per-turn queries per faction then read from the dict. Cleared every
# _start_faction_turn (building completion runs before any mechanic reads).
var _special_effect_sums_cache: Dictionary = {} # faction_id -> {key: float}

func _sum_building_special_effect(fs: FactionState, key: String) -> float:
	## Sum a special_effects key across all buildings in all of a faction's cities.
	var sums: Variant = _special_effect_sums_cache.get(fs.faction_data_id)
	if sums == null:
		sums = {}
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city == null:
				continue
			for building_id in city.buildings:
				var bd: BuildingData = DataManager.get_building(building_id)
				if bd == null:
					continue
				for k in bd.special_effects:
					var v: Variant = bd.special_effects[k]
					if v is int or v is float or v is bool or v is String:
						sums[k] = sums.get(k, 0.0) + float(v)
		_special_effect_sums_cache[fs.faction_data_id] = sums
	return sums.get(key, 0.0)

func _process_faction_mechanic(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.is_defeated:
		return
	# Sub-factions also process parent faction mechanics
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var mechanic_fid := parent_fid  # Use parent faction to determine which mechanic to run
	match mechanic_fid:
		&"empire":
			_process_empire_authority(fs)
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
			_process_thunderswarm_fury(fs, faction_id)
		&"cinderguard":
			_process_cinderguard_forge(fs)
		&"forsaken":
			_process_forsaken_espionage(fs)
		&"ivoryscar":
			_process_ivoryscar_relics(fs)
		&"sunblessed":
			_process_sunblessed_faith(fs, faction_id)
			_process_sunblessed_wisdom(fs, faction_id)

# ── Empire: Imperial Authority ─────────────────────────────
# 0-100. Rises from large territory, tech lead, cultural buildings.
# Falls from lost battles/cities. High = tribute/diplomacy/cheaper recruits.
# Low = rebellion risk. Every 5 turns: player picks an Imperial Edict.

func _process_empire_authority(fs: FactionState) -> void:
	# Authority drifts based on empire size and prestige
	var auth_drift := 0
	# Territory size: +1 per 3 regions over 3
	var region_count := fs.owned_regions.size()
	if region_count > 3:
		auth_drift += (region_count - 3) / 3
	elif region_count <= 1:
		auth_drift -= 3
	# Cultural buildings boost authority
	var cultural_count := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			var bd: BuildingData = DataManager.get_building(building_id)
			if bd and bd.category == &"cultural":
				cultural_count += 1
	auth_drift += mini(cultural_count / 2, 3)
	# Building special_effects: imperial_authority_bonus
	auth_drift += int(_sum_building_special_effect(fs, "imperial_authority_bonus"))
	# Tech lead: +2 if most completed research
	var max_tech := 0
	for other_id in GameManager.state.faction_states:
		if other_id == &"empire":
			continue
		var other_fs: FactionState = GameManager.state.faction_states[other_id]
		if not other_fs.is_defeated:
			max_tech = maxi(max_tech, other_fs.completed_research.size())
	if fs.completed_research.size() > max_tech:
		auth_drift += 2
	# Natural drift toward 50 equilibrium (slow)
	if auth_drift == 0:
		auth_drift = 1 if fs.imperial_authority < 50 else (-1 if fs.imperial_authority > 50 else 0)
	fs.imperial_authority = clampi(fs.imperial_authority + auth_drift, 0, 100)

	# ── Authority effects ──
	# High authority (75+): Empire at peak — tribute, diplomacy, cheaper recruits
	if fs.imperial_authority >= 75:
		# Tribute: +10% gold income equivalent (flat +8 gold)
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 8
		# Diplomacy bonus
		for other_id in GameManager.state.faction_states:
			if other_id == &"empire" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated:
				GameManager.diplomacy_system.modify_standing(&"empire", other_id, 1, "Imperial authority")
	# Moderate authority (50-74): stable governance
	elif fs.imperial_authority >= 50:
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 3
	# Declining authority (25-49): unrest grows
	elif fs.imperial_authority >= 25:
		for other_id in GameManager.state.faction_states:
			if other_id == &"empire" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated:
				GameManager.diplomacy_system.modify_standing(&"empire", other_id, -1, "Weakening authority")
	# Crisis authority (<25): rebellion risk, loyalty decay across all cities
	if fs.imperial_authority < 25:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 3, -100, 100)
		fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 5)

	# Process active edict
	if fs.imperial_edict_turns > 0:
		fs.imperial_edict_turns -= 1
		match fs.imperial_edict:
			1: # Military Expansion: armies fight harder
				pass # +12% attack applied in battle_simulator_v3
			2: # Economic Reform: gold bonus
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 6
			3: # Cultural Campaign: loyalty to all cities
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						for cls in city.class_loyalty:
							if cls != "captives":
								city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
			4: # Diplomatic Push: standing bonus
				for other_id in GameManager.state.faction_states:
					if other_id == &"empire" or GameManager.is_npc_faction(other_id):
						continue
					var other_fs: FactionState = GameManager.state.faction_states[other_id]
					if not other_fs.is_defeated:
						GameManager.diplomacy_system.modify_standing(&"empire", other_id, 2, "Imperial diplomatic push")
		if fs.imperial_edict_turns <= 0:
			fs.imperial_edict = 0

	# Trigger edict dilemma every 5 turns
	if GameManager.state.current_turn % 5 == 0 and fs.imperial_edict_turns <= 0:
		if fs.faction_data_id == GameManager.state.player_faction_id:
			EventBus.dilemma_triggered.emit(&"empire", "imperial_edict", {
				"title": "Imperial Edict",
				"description": "The Senate awaits your decree. Choose the Empire's focus for the next 5 turns.",
				"choices": [
					{"label": "Military Expansion", "description": "+12% attack to all armies, -3 Authority", "effect": "edict_military"},
					{"label": "Economic Reform", "description": "+6 gold/turn, +3 Authority", "effect": "edict_economic"},
					{"label": "Cultural Campaign", "description": "+2 loyalty/turn to all cities, +5 Authority", "effect": "edict_cultural"},
					{"label": "Diplomatic Push", "description": "+2 standing/turn with all factions, +2 Authority", "effect": "edict_diplomatic"},
				]
			})
		else:
			# AI auto-picks based on personality
			var fd: FactionData = DataManager.get_faction(&"empire")
			if fd:
				var aggro: float = fd.ai_personality.get("aggression", 0.4)
				if aggro >= 0.6:
					_apply_empire_edict(fs, 1) # military
				elif fs.imperial_authority < 40:
					_apply_empire_edict(fs, 3) # cultural to recover authority
				else:
					_apply_empire_edict(fs, 2) # economic default

func _apply_empire_edict(fs: FactionState, edict_type: int) -> void:
	fs.imperial_edict = edict_type
	fs.imperial_edict_turns = 5
	match edict_type:
		1: fs.imperial_authority = maxi(0, fs.imperial_authority - 3) # Military costs authority
		2: fs.imperial_authority = mini(100, fs.imperial_authority + 3)
		3: fs.imperial_authority = mini(100, fs.imperial_authority + 5)
		4: fs.imperial_authority = mini(100, fs.imperial_authority + 2)

# ── Skulloath: Corruption Duality ──────────────────────────
# 0-20 Traditional Pure: +3 loyalty, +15% food, +1 diplo, -10% attack
# 21-40 Traditional: +2 loyalty, +10% food, +1 diplo
# 41-60 Balanced: minor effects
# 61-80 Corrupted: captive→iron, +18% attack, -1 loyalty, -1 diplo
# 81-100 Deep: captive→food, +30% attack, -3 loyalty, -2 diplo, fear aura

func _process_skulloath_corruption(fs: FactionState) -> void:
	# Corruption drifts based on buildings (hardcoded paths + special_effects)
	var drift := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			var bd: BuildingData = DataManager.get_building(building_id)
			if bd and bd.special_effects.has("corruption_drift"):
				drift += int(bd.special_effects["corruption_drift"])
			elif building_id in [&"herders_camp", &"steppe_pastures", &"spirit_lodge", &"trade_post_skulloath", &"steppe_watchtower"]:
				drift -= 1
			elif building_id in [&"pale_waif_altar", &"void_sanctum", &"demon_gate"]:
				drift += 2

	# Battle activity raises corruption (captured souls feed the Waif)
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	if captives >= 10:
		drift += 1
	# Research: corruption_per_turn modifies drift rate
	var sk_r_eff := GameManager.research_system.get_research_effects(&"skulloath")
	drift += sk_r_eff.get("corruption_per_turn", 0)
	fs.corruption = clampi(fs.corruption + drift, 0, 100)

	# ── Apply corruption effects to ALL cities (not just capital) ──
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue

		if fs.corruption <= 20:
			# Traditional Pure: stable pastoralist — strong loyalty, food, weak military
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 3, -100, 100)
			city.population += 2
		elif fs.corruption <= 40:
			# Traditional: good loyalty, moderate food
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
			if city.is_capital:
				city.population += 1
		elif fs.corruption >= 81:
			# Deep corruption: massive attack bonus (in battle), auto-sacrifice captives
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 3, -100, 100)
		elif fs.corruption >= 61:
			# Corrupted: moderate attack bonus, captive-to-iron
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 1, -100, 100)

	# Captive conversion (scales with corruption)
	# Bloodsalt: +% captive conversion (affinity: skulloath/tainted_jade doubled)
	var bloodsalt_mod := SpecialResourceSystem.modifier_strength(fs.faction_data_id, &"bloodsalt")
	if fs.corruption >= 81 and captives > 0:
		var converted := mini(captives, 6)
		fs.resources[Enums.ResourceType.CAPTIVES] = captives - converted
		fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + int(converted * 10 * (1.0 + bloodsalt_mod))
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + int(converted / 2 * (1.0 + bloodsalt_mod))
	elif fs.corruption >= 61 and captives > 0:
		var converted := mini(captives, 4)
		fs.resources[Enums.ResourceType.CAPTIVES] = captives - converted
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + int(converted * 6 * (1.0 + bloodsalt_mod))

	# Traditional food bonus (applied as faction-wide)
	if fs.corruption <= 20:
		fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 8
	elif fs.corruption <= 40:
		fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 4

	# Diplomacy effects (scaled by corruption level)
	for other_id in GameManager.state.faction_states:
		if other_id == &"skulloath" or GameManager.is_npc_faction(other_id):
			continue
		var other_fs: FactionState = GameManager.state.faction_states[other_id]
		if other_fs.is_defeated:
			continue
		var fd: FactionData = DataManager.get_faction(other_id)
		if fs.corruption >= 81:
			# Deep corruption: feared by all non-void factions
			if fd and fd.realm_affinity != Enums.Realm.VOID:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, -2, "Deep corruption")
			else:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, 1, "Void kinship")
		elif fs.corruption >= 61:
			if fd and fd.realm_affinity != Enums.Realm.VOID:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, -1, "High corruption")
		elif fs.corruption <= 30:
			if GameManager.get_relation(&"skulloath", other_id) != Enums.FactionRelation.WAR:
				GameManager.diplomacy_system.modify_standing(&"skulloath", other_id, 1, "Traditional path")

	# Research bonus at balanced corruption (diverse knowledge)
	if fs.corruption >= 35 and fs.corruption <= 65:
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 3

	# ── Dark Bargain dilemma: the player STEERS corruption instead of only
	# drifting via buildings/captives (every 4 turns, offset from other dilemmas)
	if GameManager.state.current_turn % 4 == 2 and GameManager.state.current_turn > 2:
		var sk_captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
		if fs.faction_data_id == GameManager.state.player_faction_id:
			var choices := [
				{"label": "Walk the Line", "description": "Hold the balance. +3 Technology from diverse knowledge.", "effect": "bargain_balance"},
				{"label": "Ancestral Rites", "description": "Purge the darkness: -12 Corruption, +2 loyalty in all cities. Costs 40 Gold.", "effect": "bargain_purge", "cost": {0: 40}},
			]
			if sk_captives >= 10:
				choices.insert(0, {"label": "Feed the Hunger", "description": "Sacrifice 10 Captives: +12 Corruption, +10 Iron.", "effect": "bargain_embrace", "cost": {6: 10}})
			EventBus.dilemma_triggered.emit(fs.faction_data_id, "dark_bargain", {
				"title": "Dark Bargain (Corruption: %d)" % fs.corruption,
				"description": "The old spirits and the demon whisper alike. Choose whose voice grows louder.",
				"choices": choices,
			})
		else:
			# AI: embrace toward the demonic band when at war with captives to spare
			if sk_captives >= 10 and fs.corruption < 81:
				for other_id in GameManager.state.faction_states:
					if other_id != fs.faction_data_id and GameManager.get_relation(fs.faction_data_id, other_id) == Enums.FactionRelation.WAR:
						_apply_dark_bargain(fs, "bargain_embrace")
						break

func _apply_dark_bargain(fs: FactionState, effect: String) -> void:
	match effect:
		"bargain_embrace":
			if fs.resources.get(Enums.ResourceType.CAPTIVES, 0) >= 10:
				fs.resources[Enums.ResourceType.CAPTIVES] = fs.resources.get(Enums.ResourceType.CAPTIVES, 0) - 10
				fs.corruption = clampi(fs.corruption + 12, 0, 100)
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 10
		"bargain_purge":
			if fs.resources.get(Enums.ResourceType.GOLD, 0) >= 40:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 40
				fs.corruption = clampi(fs.corruption - 12, 0, 100)
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						for cls in city.class_loyalty:
							if cls != "captives":
								city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
		"bargain_balance":
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 3

# ── Tainted Jade: Taint Power + Taint Focus ───────────────
# Taint Focus (player choice): 0=balanced, 1=verdant growth, 2=venomous war, 3=creeping doom
# Each focus changes how taint power manifests across multiple game systems.
# Taint rises from captive labor, shard destruction, jungle buildings.
# HIGH IMPACT: defense bonuses, shard suppression, anti-magic, captive economy,
# jungle terrain bonuses, population trade-offs, diplomacy with anti-shard factions.

func _process_tainted_jade_taint(fs: FactionState) -> void:
	# Taint power sources: captive processing generates taint residue
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	var has_thrall_quarters := false
	var has_captive_camp := false
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			if city.buildings.has(&"thrall_quarters"):
				has_thrall_quarters = true
			if city.buildings.has(&"captive_processing_camp"):
				has_captive_camp = true

	if has_thrall_quarters and captives >= 5:
		var processed := mini(captives / 5, 3)
		# Building special_effects: captive_conversion_rate amplifies resource output
		var conv_rate := _sum_building_special_effect(fs, "captive_conversion_rate")
		# Bloodsalt: +% captive conversion (affinity: skulloath/tainted_jade doubled)
		conv_rate += SpecialResourceSystem.modifier_strength(fs.faction_data_id, &"bloodsalt")
		var camp_mult := 1.0 + conv_rate if conv_rate > 0.0 else (2.0 if has_captive_camp else 1.0)
		fs.resources[Enums.ResourceType.CAPTIVES] = captives - processed * 5
		fs.taint_power += processed * 3
		fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + int(processed * 5 * camp_mult)
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + int(processed * 4 * camp_mult)

	# Building special_effects: taint_generation
	fs.taint_power += int(_sum_building_special_effect(fs, "taint_generation"))
	# Research: taint_per_turn
	var tj_r_eff := GameManager.research_system.get_research_effects(&"tainted_jade")
	fs.taint_power += tj_r_eff.get("taint_per_turn", 0)
	# Natural decay (reduced by jungle cities and taint buildings)
	var jungle_cities := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			var tile := GameManager.state.hex_map.get_tile(city.hex_pos)
			if tile and tile.terrain == Enums.TerrainType.JUNGLE:
				jungle_cities += 1
	var decay := maxi(1, 2 - jungle_cities)
	if fs.taint_power > 0:
		fs.taint_power = maxi(fs.taint_power - decay, 0)

	# ── Taint Focus effects (player-chosen direction) ──
	match fs.taint_focus:
		1: # Verdant Growth: food, population, healing
			if fs.taint_power >= 20:
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 6
			if fs.taint_power >= 40:
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						city.population += 2
			# Heal armies in jungle
			if fs.taint_power >= 30:
				for army: ArmyState in GameManager.get_faction_armies(&"tainted_jade"):
					var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
					if tile and tile.terrain == Enums.TerrainType.JUNGLE:
						for unit in army.units:
							var ud := DataManager.get_unit(unit.unit_data_id)
							if ud:
								unit.current_hp = mini(unit.current_hp + 4, ud.max_hp * ud.squad_size)
		2: # Venomous War: attack bonuses, poison, anti-magic (applied in battle_simulator)
			# Iron bonus for war production
			if fs.taint_power >= 20:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 4
			if fs.taint_power >= 40:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 3
		3: # Creeping Doom: territory control, movement denial, shard suppression
			# Extra shard decay acceleration
			if fs.taint_power >= 30:
				for shard_id in GameManager.state.active_shards:
					var shard: ShardInstance = GameManager.state.active_shards[shard_id]
					if shard.claimed_by != &"tainted_jade" and shard.claimed_by != &"" and shard.turns_remaining > 0:
						shard.turns_remaining = maxi(shard.turns_remaining - 1, 1)
			# Territorial intimidation: enemy border factions lose loyalty
			if fs.taint_power >= 50:
				for other_id in GameManager.state.faction_states:
					if other_id == &"tainted_jade" or GameManager.is_npc_faction(other_id):
						continue
					var other_fs: FactionState = GameManager.state.faction_states[other_id]
					if other_fs.is_defeated:
						continue
					# Find if they share a border
					for r_id in fs.owned_regions:
						for or_id in other_fs.owned_regions:
							if GameManager.state.hex_map.regions_adjacent(r_id, or_id):
								# Border city loyalty erosion
								for c_id in other_fs.owned_cities:
									var c: CityState = GameManager.state.cities.get(c_id)
									if c and c.region_id == or_id:
										for cls in c.class_loyalty:
											if cls != "captives":
												c.class_loyalty[cls] = clampi(c.class_loyalty[cls] - 1, -100, 100)
								break

	# ── Base taint effects (always active regardless of focus) ──
	# 50+ taint: accelerate enemy shard decay (base effect)
	if fs.taint_power >= 50:
		for shard_id in GameManager.state.active_shards:
			var shard: ShardInstance = GameManager.state.active_shards[shard_id]
			if shard.claimed_by != &"tainted_jade" and shard.claimed_by != &"" and shard.turns_remaining > 0:
				shard.turns_remaining = maxi(shard.turns_remaining - 1, 1)

	# Tech bonus from studying taint (always active)
	if fs.taint_power >= 25:
		var tech_gain := mini(fs.taint_power / 15, 4)
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_gain

	# Diplomacy: anti-shard factions respect high taint
	if fs.taint_power >= 30:
		for other_id in GameManager.state.faction_states:
			if other_id == &"tainted_jade" or GameManager.is_npc_faction(other_id) or other_id == &"shardhorde":
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if other_fs.owned_shards.size() <= 2:
				GameManager.diplomacy_system.modify_standing(&"tainted_jade", other_id, 1, "Anti-shard stance")
			# But shard-heavy factions dislike you
			if other_fs.owned_shards.size() >= 3:
				GameManager.diplomacy_system.modify_standing(&"tainted_jade", other_id, -2, "Shard enemies")

	# Very high taint: population penalty (land is scarred)
	if fs.taint_power >= 70:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				city.population = maxi(20, city.population - 1)

	# AI: shatter a spare claimed shard for taint (keep one in reserve)
	if fs.faction_data_id != GameManager.state.player_faction_id and fs.owned_shards.size() >= 2 and fs.taint_power < 60:
		destroy_shard_for_taint(fs.faction_data_id, fs.owned_shards[0])

	# Trigger taint focus dilemma every 4 turns
	if GameManager.state.current_turn % 4 == 0 and fs.taint_power >= 15:
		if fs.faction_data_id == GameManager.state.player_faction_id:
			EventBus.dilemma_triggered.emit(&"tainted_jade", "taint_focus", {
				"title": "Taint Focus",
				"description": "The jungle pulses with power (Taint: %d). Direct the serpent's will." % fs.taint_power,
				"choices": [
					{"label": "Verdant Growth", "description": "Food, population, army healing in jungle. Nurture the land.", "effect": "taint_focus_1"},
					{"label": "Venomous War", "description": "+15% attack in jungle/swamp, anti-magic field, iron production.", "effect": "taint_focus_2"},
					{"label": "Creeping Doom", "description": "Accelerate shard decay, erode enemy border loyalty, movement denial.", "effect": "taint_focus_3"},
				]
			})
		else:
			# AI picks a focus by posture: at war -> Venomous War; many border
			# rivals with shards -> Creeping Doom; otherwise grow
			var at_war := false
			for other_id in GameManager.state.faction_states:
				if other_id != fs.faction_data_id and GameManager.get_relation(fs.faction_data_id, other_id) == Enums.FactionRelation.WAR:
					at_war = true
					break
			if at_war:
				fs.taint_focus = 2
			elif fs.taint_power >= 50:
				fs.taint_focus = 3
			else:
				fs.taint_focus = 1

# ── Gladehost: Seasonal Cycle ──────────────────────────────
# Harmony (0-100) scales ALL seasonal bonuses multiplicatively.
# Each season has strong, distinct effects on economy, military, diplomacy, population.
# Seasonal Festival dilemma at each season change gives player a bonus choice.

func _apply_season_festival(fs: FactionState, effect: String) -> void:
	match effect:
		"festival_grand":
			if fs.resources.get(Enums.ResourceType.FOOD, 0) >= 30:
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) - 30
				fs.harmony = mini(fs.harmony + 15, 100)
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						for cls in city.class_loyalty:
							if cls != "captives":
								city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
		"festival_toil":
			fs.harmony = maxi(fs.harmony - 8, 0)
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 25
			fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + 12
		"festival_quiet":
			fs.harmony = mini(fs.harmony + 5, 100)

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
	var total_buildings := 0
	var nature_tiles := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			total_buildings += city.buildings.size()
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and (tile.terrain == Enums.TerrainType.FOREST or tile.terrain == Enums.TerrainType.JUNGLE):
				nature_tiles += 1

	# Harmony drift: over-building lowers, under-building raises, nature restores
	var target := fs.owned_cities.size() * 3
	if total_buildings > target:
		fs.harmony = maxi(fs.harmony - (total_buildings - target), 15)
	elif total_buildings < target:
		fs.harmony = mini(fs.harmony + 1, 100)
	var nature_bonus := mini(nature_tiles / 8, 4) # Slightly more impactful
	fs.harmony = mini(fs.harmony + nature_bonus, 100)

	# Seasonal shrine chain: +harmony per turn
	var shrine_bonus := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			if city.buildings.has(&"eternal_cycle"):
				shrine_bonus = maxi(shrine_bonus, 5)
			elif city.buildings.has(&"solstice_altar"):
				shrine_bonus = maxi(shrine_bonus, 3)
			elif city.buildings.has(&"seasonal_shrine"):
				shrine_bonus = maxi(shrine_bonus, 2)
	fs.harmony = mini(fs.harmony + shrine_bonus, 100)
	# Building special_effects: harmony_bonus
	fs.harmony = mini(fs.harmony + int(_sum_building_special_effect(fs, "harmony_bonus")), 100)
	# Research: harmony_regen (+X harmony per turn)
	var gh_r_eff := GameManager.research_system.get_research_effects(&"gladehost")
	fs.harmony = mini(fs.harmony + gh_r_eff.get("harmony_regen", 0), 100)
	# Research: harmony_income_scaling (+X% income per 10 harmony)
	var harm_income_scale: int = gh_r_eff.get("harmony_income_scaling", 0)
	if harm_income_scale > 0 and fs.harmony > 0:
		var gold_bonus := int(float(harm_income_scale) * float(fs.harmony) / 100.0)
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + gold_bonus

	var season := get_current_season()

	# ── Seasonal Festival dilemma on every season change ──
	if season != fs.last_season:
		var first_season := fs.last_season == -1
		fs.last_season = season
		if not first_season:
			if fs.faction_data_id == GameManager.state.player_faction_id:
				EventBus.dilemma_triggered.emit(fs.faction_data_id, "season_festival", {
					"title": "%s Rites (Harmony: %d)" % [get_season_name(season), fs.harmony],
					"description": "The season turns. How will the Gladehost greet it?",
					"choices": [
						{"label": "Grand Festival", "description": "Spend 30 Food: +15 Harmony and +2 loyalty in all cities.", "effect": "festival_grand", "cost": {3: 30}},
						{"label": "Season of Toil", "description": "Work through the rites: +25 Gold, +12 Wood, but -8 Harmony.", "effect": "festival_toil"},
						{"label": "Quiet Observance", "description": "Honor the cycle simply. +5 Harmony.", "effect": "festival_quiet"},
					],
				})
			else:
				# AI: restore harmony when low, cash in when high
				if fs.harmony < 55 and fs.resources.get(Enums.ResourceType.FOOD, 0) >= 30:
					_apply_season_festival(fs, "festival_grand")
				elif fs.harmony > 75:
					_apply_season_festival(fs, "festival_toil")
				else:
					_apply_season_festival(fs, "festival_quiet")

	# Building special_effects: seasonal_multiplier amplifies harmony
	var seasonal_amp := _sum_building_special_effect(fs, "seasonal_multiplier")
	var harmony_mult := float(fs.harmony) / 100.0 * (1.0 + seasonal_amp) # Amplified by buildings

	# ── Strong seasonal effects (scaled by harmony) ──
	match season:
		0: # Spring: birth, growth, renewal
			var food_bonus := int(10.0 * harmony_mult)
			fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + food_bonus
			for city_id in fs.owned_cities:
				var city: CityState = GameManager.state.cities.get(city_id)
				if city:
					city.population += (3 if fs.harmony >= 60 else 1)
					# Spring healing: armies recover
			for army: ArmyState in GameManager.get_faction_armies(&"gladehost"):
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = mini(unit.current_hp + int(3.0 * harmony_mult), ud.max_hp * ud.squad_size)
		1: # Summer: strength, iron, military readiness
			var iron_bonus := int(6.0 * harmony_mult)
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + iron_bonus
			var gold_bonus := int(4.0 * harmony_mult)
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + gold_bonus
		2: # Autumn: harvest, trade, diplomacy
			var gold_bonus := int(10.0 * harmony_mult)
			var wood_bonus := int(6.0 * harmony_mult)
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + gold_bonus
			fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + wood_bonus
			# Autumn diplomacy: harvest festivals impress neighbors
			if fs.harmony >= 50:
				for other_id in GameManager.state.faction_states:
					if other_id == &"gladehost" or GameManager.is_npc_faction(other_id):
						continue
					var other_fs: FactionState = GameManager.state.faction_states[other_id]
					if not other_fs.is_defeated and GameManager.get_relation(&"gladehost", other_id) != Enums.FactionRelation.WAR:
						GameManager.diplomacy_system.modify_standing(&"gladehost", other_id, 2, "Autumn harvest festival")
		3: # Winter: hardship, defense, endurance
			var food_penalty := int(6.0 * (1.0 - harmony_mult * 0.5)) # Shrine reduces penalty
			fs.resources[Enums.ResourceType.FOOD] = maxi(0, fs.resources.get(Enums.ResourceType.FOOD, 0) - food_penalty)
			if fs.harmony < 40:
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						city.population = maxi(20, city.population - 2)
			# Winter hardening: defense bonus to armies (applied in battle_simulator)

	# ── Loyalty effects (all cities, not just capital) ──
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		if fs.harmony >= 70:
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
		elif fs.harmony >= 50:
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 1, -100, 100)
		elif fs.harmony <= 30:
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 2, -100, 100)

	# High harmony: diplomacy bonus
	var has_embassy := false
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and (city.buildings.has(&"embassy_grove") or city.buildings.has(&"council_of_groves")):
			has_embassy = true
			break
	if fs.harmony >= 60 or has_embassy:
		var diplo_bonus := 1
		if has_embassy and fs.harmony >= 70:
			diplo_bonus = 3
		elif has_embassy or fs.harmony >= 80:
			diplo_bonus = 2
		for other_id in GameManager.state.faction_states:
			if other_id == &"gladehost" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated and GameManager.get_relation(&"gladehost", other_id) != Enums.FactionRelation.WAR:
				GameManager.diplomacy_system.modify_standing(&"gladehost", other_id, diplo_bonus, "Harmony of the groves")

# ── Shardhorde: Shard Resonance ────────────────────────────
# Consuming shards grants powerful realm-specific buffs for multiple turns.
# Each realm provides distinct bonuses to different game systems.
# Elderbeasts grow faster near shard wastes and heal from active resonance.
# Multiple active resonances stack for elderbeasts and provide escalating bonuses.

func _process_shardhorde_resonance(fs: FactionState) -> void:
	# Decay resonance buffs
	var to_remove: Array = []
	for realm_key in fs.shard_resonance:
		fs.shard_resonance[realm_key] -= 1
		if fs.shard_resonance[realm_key] <= 0:
			to_remove.append(realm_key)
	for key in to_remove:
		fs.shard_resonance.erase(key)

	var resonance_count := fs.shard_resonance.size()

	# Active resonance heals elderbeasts (scales with count)
	if resonance_count > 0:
		for beast_id in GameManager.state.elderbeasts:
			var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
			if beast.faction_id == &"shardhorde" and beast.hp < beast.max_hp:
				beast.hp = mini(beast.hp + 25 * resonance_count, beast.max_hp)

	# Elderbeasts on shard wastes gain survival turns faster
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		var tile := GameManager.state.hex_map.get_tile(beast.hex_pos)
		if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
			beast.survival_turns += 1

	# ── Per-realm resonance income (much stronger than before) ──
	for realm_key in fs.shard_resonance:
		match realm_key:
			Enums.Realm.DIVINE:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 20
				# Divine resonance: heal armies
				for army: ArmyState in GameManager.get_faction_armies(&"shardhorde"):
					for unit in army.units:
						var ud := DataManager.get_unit(unit.unit_data_id)
						if ud:
							unit.current_hp = mini(unit.current_hp + 3, ud.max_hp * ud.squad_size)
			Enums.Realm.ELEMENTAL:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 25
			Enums.Realm.NATURE:
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 25
				# Population growth while nature resonance active
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city:
						city.population += 2
			Enums.Realm.MORTAL:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 12
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 12
			Enums.Realm.VOID:
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 20
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 3

	# Multi-resonance bonus: 3+ active realms = diplomatic intimidation
	if resonance_count >= 3:
		for other_id in GameManager.state.faction_states:
			if other_id == &"shardhorde" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated:
				GameManager.diplomacy_system.modify_standing(&"shardhorde", other_id, -1, "Overwhelming shard power")

	# AI: consume a claimed shard whenever its realm resonance is inactive
	# (players do this via the Shard Reserve dialog on the top-bar shard label)
	if fs.faction_data_id != GameManager.state.player_faction_id and not fs.owned_shards.is_empty():
		var best_id: StringName = &""
		var best_power := -1
		for shard_id in fs.owned_shards:
			var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
			if shard == null or fs.shard_resonance.has(shard.realm):
				continue
			if shard.power_level > best_power:
				best_power = shard.power_level
				best_id = shard_id
		if best_id != &"":
			consume_shard_for_resonance(fs.faction_data_id, best_id)

	# Shard wastes passive essence
	var wastes_count := 0
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
				wastes_count += 1
	if wastes_count > 0:
		var essence_gain := mini(wastes_count / 4, 10) # Slightly more generous
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
	# Grant resonance buff: 6 turns of realm bonus (12 if Resonance Amplifier built)
	var resonance_duration := 6
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			if beast.buildings.has(&"resonance_amplifier"):
				resonance_duration = 12
				break
	fs.shard_resonance[shard.realm] = resonance_duration
	# Immediate elderbeast healing on consume
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			beast.hp = mini(beast.hp + 75, beast.max_hp)

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
	fs.taint_power += shard.power_level * 12
	fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 8

# ── Moonspear: Lunar Phase ────────────────────────────────
# 4-phase cycle with STRONG, distinct effects per phase.
# Player can extend current phase via Lunar Ritual dilemma (costs resources).
# Each phase affects: battles, economy, armies, loyalty, research differently.
# 0=New Moon (+atk, stealth), 1=Waxing (+move, +gold, +research),
# 2=Full Moon (+def, +loyalty, +pop), 3=Waning (+heal, +shard, +tech)

func _process_moonspear_lunar(fs: FactionState) -> void:
	# Handle ritual extension
	if fs.lunar_ritual_extended > 0:
		fs.lunar_ritual_extended -= 1
	elif GameManager.state.current_turn % 4 == 0:
		var old_phase := fs.lunar_phase
		fs.lunar_phase = (fs.lunar_phase + 1) % 4
		# Trigger ritual dilemma on phase change (player can extend or skip)
		if fs.faction_data_id == GameManager.state.player_faction_id:
			EventBus.dilemma_triggered.emit(&"moonspear", "lunar_ritual", {
				"title": "Lunar Ritual — %s" % get_lunar_phase_name(fs.lunar_phase),
				"description": "The moon shifts to %s. Your mystics can channel its power." % get_lunar_phase_name(fs.lunar_phase),
				"choices": [
					{"label": "Extend Phase", "description": "Hold this phase 3 extra turns. Costs 40 Gold + 5 Shard Essence.", "effect": "lunar_extend", "cost": {0: 40, 4: 5}},
					{"label": "Accept the Cycle", "description": "Let the moon follow its natural path.", "effect": "lunar_accept"},
					{"label": "Rush Forward", "description": "Skip to next phase immediately (costs 20 Gold).", "effect": "lunar_skip", "cost": {0: 20}},
				]
			})
		else:
			# AI: hold Full Moon while at war (defensive phase), if affordable
			if fs.lunar_phase == 2 and fs.resources.get(Enums.ResourceType.GOLD, 0) >= 80 and fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) >= 10:
				var ai_at_war := false
				for other_id in GameManager.state.faction_states:
					if other_id != fs.faction_data_id and GameManager.get_relation(fs.faction_data_id, other_id) == Enums.FactionRelation.WAR:
						ai_at_war = true
						break
				if ai_at_war:
					fs.resources[Enums.ResourceType.GOLD] -= 40
					fs.resources[Enums.ResourceType.SHARD_ESSENCE] -= 5
					fs.lunar_ritual_extended = 3

	# Cooldown tracking for skip
	if fs.lunar_skip_cooldown > 0:
		fs.lunar_skip_cooldown -= 1

	# Building special_effects: lunar_phase_tech_bonus amplifies phase resource gains
	var lunar_bld_bonus := int(_sum_building_special_effect(fs, "lunar_phase_tech_bonus"))

	# ── Strong phase effects ──
	match fs.lunar_phase:
		0: # New Moon: aggression, stealth, hunting
			# Battle bonus: +15% attack applied in battle_simulator_v3
			# Economy: iron bonus from night raids
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 4 + lunar_bld_bonus
			# Research: night study
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 2 + lunar_bld_bonus
		1: # Waxing Moon: growth, trade, movement
			# Movement bonus applied in movement_system
			# Economy: trade flourishes under growing moon
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 8 + lunar_bld_bonus
			# Research boost
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 4 + lunar_bld_bonus
		2: # Full Moon: defense, loyalty, population, diplomacy
			# Battle bonus: +15% defense applied in battle_simulator_v3
			# Loyalty boost to ALL cities
			for city_id in fs.owned_cities:
				var city: CityState = GameManager.state.cities.get(city_id)
				if city:
					for cls in city.class_loyalty:
						if cls != "captives":
							city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
					city.population += 2
			# Diplomacy: divine factions respect the full moon
			for other_id in GameManager.state.faction_states:
				if other_id == &"moonspear" or GameManager.is_npc_faction(other_id):
					continue
				var other_fs: FactionState = GameManager.state.faction_states[other_id]
				if not other_fs.is_defeated:
					var fd: FactionData = DataManager.get_faction(other_id)
					if fd and fd.realm_affinity == Enums.Realm.DIVINE:
						GameManager.diplomacy_system.modify_standing(&"moonspear", other_id, 2, "Full moon radiance")
					elif GameManager.get_relation(&"moonspear", other_id) != Enums.FactionRelation.WAR:
						GameManager.diplomacy_system.modify_standing(&"moonspear", other_id, 1, "Full moon")
		3: # Waning Moon: healing, shard power, reflection
			# Heal ALL armies significantly
			for army: ArmyState in GameManager.get_faction_armies(&"moonspear"):
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = mini(unit.current_hp + 10, ud.max_hp * ud.squad_size)
			# Shard essence bonus
			fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 3
			# Tech bonus from contemplation
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 6

func get_lunar_phase_name(phase: int) -> String:
	match phase:
		0: return "New Moon"
		1: return "Waxing Moon"
		2: return "Full Moon"
		3: return "Waning Moon"
		_: return "Unknown"

# ── Thunderswarm: Storm Fury ──────────────────────────────
# Fury rises from battles, mountains, storm buildings. Decays naturally.
# Now a SPENDABLE resource: player can activate storm abilities via dilemmas.
# Passive bonuses at thresholds + active abilities when fury is high enough.
# Affects: battles, armies, cities, economy, diplomacy.

func _process_thunderswarm_fury(fs: FactionState, fid: StringName = &"thunderswarm") -> void:
	# Natural decay: -3/turn (reduced from -5 to make fury more persistent)
	if fs.storm_fury > 0:
		fs.storm_fury = maxi(fs.storm_fury - 3, 0)

	# Mountain armies generate fury (+3 per army on mountains)
	for army: ArmyState in GameManager.get_faction_armies(fid):
		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
		if tile and tile.terrain == Enums.TerrainType.MOUNTAINS:
			fs.storm_fury = mini(fs.storm_fury + 3, 100)

	# Storm buildings generate fury (hardcoded + special_effects)
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			if city.buildings.has(&"lightning_spire"):
				fs.storm_fury = mini(fs.storm_fury + 2, 100)
			for building_id in city.buildings:
				var bd: BuildingData = DataManager.get_building(building_id)
				if bd and bd.special_effects.has("storm_fury_generation"):
					fs.storm_fury = mini(fs.storm_fury + int(bd.special_effects["storm_fury_generation"]), 100)
	# Research: storm_fury_per_turn (+X fury per turn)
	var ts_r_eff := GameManager.research_system.get_research_effects(fid)
	fs.storm_fury = mini(fs.storm_fury + ts_r_eff.get("storm_fury_per_turn", 0), 100)

	# ── Passive fury effects (scaled by level) ──
	if fs.storm_fury >= 30:
		# Low fury: minor iron bonus from storm-charged forges
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 2
	if fs.storm_fury >= 50:
		# Moderate fury: serious iron production + intimidation
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 4
	if fs.storm_fury >= 70:
		# High fury: gold from tribute (storms intimidate trade partners)
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 5

	# Diplomacy: high fury intimidates (penalty) but also earns respect from warriors
	if fs.storm_fury >= 80:
		for other_id in GameManager.state.faction_states:
			if other_id == fid or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			var fd: FactionData = DataManager.get_faction(other_id)
			if fd and fd.ai_personality.get("aggression", 0.0) >= 0.6:
				GameManager.diplomacy_system.modify_standing(fid, other_id, 1, "Warrior respect")
			else:
				GameManager.diplomacy_system.modify_standing(fid, other_id, -1, "Storm terror")

	# Storm wall city defense (from previous ability activation)
	if fs.storm_wall_turns > 0:
		fs.storm_wall_turns -= 1
		if fs.storm_wall_turns <= 0:
			fs.storm_wall_city = &""

	# Cooldown tracking
	if fs.storm_ability_cooldown > 0:
		fs.storm_ability_cooldown -= 1

	# Trigger storm ability dilemma when fury is high enough
	if fs.storm_fury >= 35 and fs.storm_ability_cooldown <= 0 and GameManager.state.current_turn % 3 == 0:
		if fs.faction_data_id == GameManager.state.player_faction_id:
			var choices := [
				{"label": "Hold the Storm", "description": "Let fury build. Passive bonuses continue.", "effect": "storm_hold"},
			]
			if fs.storm_fury >= 40:
				choices.append({"label": "Storm March", "description": "Spend 15 Fury: +2 movement to all armies this turn.", "effect": "storm_march"})
			if fs.storm_fury >= 50:
				choices.append({"label": "Thunder Wall", "description": "Spend 20 Fury: +8 defense to one city for 4 turns.", "effect": "storm_wall"})
			if fs.storm_fury >= 60:
				choices.append({"label": "Tempest Harvest", "description": "Spend 30 Fury: Gain +40 iron, +25 gold immediately.", "effect": "storm_harvest"})
			EventBus.dilemma_triggered.emit(fid, "storm_ability", {
				"title": "Storm Command (Fury: %d)" % fs.storm_fury,
				"description": "The storms obey. How will you channel the fury?",
				"choices": choices,
			})
		else:
			# AI auto-uses abilities
			if fs.storm_fury >= 60 and fs.resources.get(Enums.ResourceType.IRON, 0) < 30:
				_apply_storm_ability(fs, fid, "storm_harvest")
			elif fs.storm_fury >= 50:
				_apply_storm_ability(fs, fid, "storm_wall")

func _apply_storm_ability(fs: FactionState, fid: StringName, ability: String) -> void:
	match ability:
		"storm_march":
			fs.storm_fury = maxi(0, fs.storm_fury - 15)
			fs.storm_ability_cooldown = 3
			for army: ArmyState in GameManager.get_faction_armies(fid):
				army.movement_remaining += 2.0
		"storm_wall":
			fs.storm_fury = maxi(0, fs.storm_fury - 20)
			fs.storm_ability_cooldown = 3
			# Apply to capital (or first city)
			if fs.owned_cities.size() > 0:
				fs.storm_wall_city = fs.owned_cities[0]
				fs.storm_wall_turns = 4
				for city_id in fs.owned_cities:
					var city: CityState = GameManager.state.cities.get(city_id)
					if city and city.is_capital:
						fs.storm_wall_city = city_id
						break
		"storm_harvest":
			fs.storm_fury = maxi(0, fs.storm_fury - 30)
			fs.storm_ability_cooldown = 3
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 40
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 25

# ── Cinderguard: Border Vigilance / Frontier Allocation ──────
# Player-directed: dilemma every 3 turns to shift vigilance ±10.
# Buildings still provide passive drift. Creates real tension between:
# FORTRESS MODE (low): +20% def, +pop, +loyalty, -iron
# WAR FOOTING MODE (high): +15% atk, +iron, +recruit speed, -food, -diplomacy
# BALANCED: moderate bonuses to both sides.

func _process_cinderguard_forge(fs: FactionState) -> void:
	var cg_r_eff := GameManager.research_system.get_research_effects(&"cinderguard")
	var faction_id: StringName = fs.faction_data_id

	# ── Count settlements and gather info ──
	var settlement_count := 0
	var settlement_ids: Array[StringName] = []
	var forge_count := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		if city.is_settlement:
			settlement_count += 1
			settlement_ids.append(city_id)
		for b_id in city.buildings:
			if b_id in [&"ember_forge", &"war_forge", &"molten_foundry", &"siege_works", &"ember_foundry"]:
				forge_count += 1

	# ── Border Vigilance (kept, but now also scales with fortress count) ──
	var drift := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			var bd: BuildingData = DataManager.get_building(building_id)
			if bd and bd.special_effects.has("vigilance_drift"):
				drift += int(bd.special_effects["vigilance_drift"])
			elif building_id in [&"ember_forge", &"war_forge", &"siege_works", &"fire_barracks", &"molten_foundry"]:
				drift += 1
			elif building_id in [&"stone_bastion", &"iron_wall", &"market", &"granary", &"temple"]:
				drift -= 1
	# Fortresses passively raise vigilance
	var total_fort_level := 0
	for cid in settlement_ids:
		total_fort_level += fs.border_fortresses.get(cid, 0)
	drift += total_fort_level / 2

	drift += cg_r_eff.get("vigilance_per_turn", 0)
	drift += fs.forge_shift_queued
	fs.forge_shift_queued = 0
	if drift == 0:
		if fs.border_vigilance > 50:
			drift = -1
		elif fs.border_vigilance < 50:
			drift = 1
	fs.border_vigilance = clampi(fs.border_vigilance + drift, 0, 100)

	# ── Vigilance mode bonuses (unchanged core) ──
	if fs.border_vigilance <= 30:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				city.population += 2
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
		fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + 6
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 4
		for other_id in GameManager.state.faction_states:
			if other_id == faction_id or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated:
				GameManager.diplomacy_system.modify_standing(faction_id, other_id, 1, "Peaceful borders")
	elif fs.border_vigilance >= 75:
		var iron_bonus := 8 if fs.border_vigilance >= 90 else 5
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + iron_bonus
		fs.resources[Enums.ResourceType.FOOD] = maxi(0, fs.resources.get(Enums.ResourceType.FOOD, 0) - 3)
		if fs.border_vigilance >= 85:
			for other_id in GameManager.state.faction_states:
				if other_id == faction_id or GameManager.is_npc_faction(other_id):
					continue
				var other_fs: FactionState = GameManager.state.faction_states[other_id]
				if not other_fs.is_defeated:
					GameManager.diplomacy_system.modify_standing(faction_id, other_id, -1, "War mobilization")
	else:
		var iron_bonus := 2 if fs.border_vigilance >= 50 else 1
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + iron_bonus
		if fs.border_vigilance <= 45:
			for city_id in fs.owned_cities:
				var city: CityState = GameManager.state.cities.get(city_id)
				if city and city.is_capital:
					city.population += 1

	# ── Scavenging: settlements generate scrap ──
	# Each settlement produces scavenge based on level + fortress level
	var scavenge_gain := 0
	for cid in settlement_ids:
		var city: CityState = GameManager.state.cities.get(cid)
		if city:
			scavenge_gain += city.level + fs.border_fortresses.get(cid, 0)
	scavenge_gain += cg_r_eff.get("scavenge_per_turn", 0)
	fs.scavenge_stockpile += scavenge_gain

	# ── Settlement bonuses: each settlement provides iron + food scaled by level ──
	for cid in settlement_ids:
		var city: CityState = GameManager.state.cities.get(cid)
		if city:
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + city.level
			fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + city.level
			# Fortified settlements grow population faster
			var fort_lv: int = fs.border_fortresses.get(cid, 0)
			if fort_lv >= 2:
				city.population += 1
			if fort_lv >= 3:
				city.population += 1
				# Full border forts provide tech from frontier engineering
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 1

	# Forge tech bonus (always active)
	if forge_count >= 2:
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + mini(forge_count, 4)

	# ── Dragon Raid milestone bonuses ──
	if fs.dragon_raids_survived >= 3:
		# Veterans: +2 iron/turn from scavenged dragon parts
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 2
	if fs.dragon_raids_survived >= 6:
		# Dragonslayers: +3 tech from studying dragon anatomy
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 3
	if fs.dragon_raids_survived >= 10:
		# Dragon Tamers: +5 gold/turn from dragonbone trade, all settlements +pop
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 5
		for cid in settlement_ids:
			var city: CityState = GameManager.state.cities.get(cid)
			if city:
				city.population += 1

	# ── Dragon Raid event ──
	if fs.dragon_raid_cooldown > 0:
		fs.dragon_raid_cooldown -= 1

	# Dragon raids target a random settlement every 4-6 turns
	if fs.dragon_raid_cooldown <= 0 and not settlement_ids.is_empty():
		# Pick a random settlement (prefer unfortified ones)
		var target_id: StringName = &""
		var unfortified: Array[StringName] = []
		for cid in settlement_ids:
			if fs.border_fortresses.get(cid, 0) < 2:
				unfortified.append(cid)
		if not unfortified.is_empty():
			target_id = unfortified[randi() % unfortified.size()]
		else:
			target_id = settlement_ids[randi() % settlement_ids.size()]
		fs.dragon_raid_target = target_id
		fs.dragon_raid_cooldown = 4 + randi() % 3 # 4-6 turns

		var target_city: CityState = GameManager.state.cities.get(target_id)
		var fort_lv: int = fs.border_fortresses.get(target_id, 0)
		var target_name := target_city.get_display_name() if target_city else str(target_id)
		var fort_desc = ["undefended", "watchtower", "palisade", "border fort"][mini(fort_lv, 3)]

		if faction_id == GameManager.state.player_faction_id:
			var choices := [
				{"label": "Man the Walls", "description": "Defend with garrison. Fortress level helps. Success: +15 Scrap, +Iron, +Vigilance.", "effect": "dragon_defend"},
				{"label": "Evacuate Villagers", "description": "Abandon the settlement to save lives. -1 Fortress level, +3 Pop to capital, -10 Vigilance.", "effect": "dragon_evacuate"},
				{"label": "Set Dragon Traps", "description": "Spend 20 Iron to lay traps. High success: +25 Scrap, +Tech. Costs 20 Iron.", "effect": "dragon_trap", "cost": {1: 20}},
			]
			if fs.scavenge_stockpile >= 15 and fort_lv < 3:
				choices.append({"label": "Rush Fortifications", "description": "Spend 15 Scrap to upgrade fortress before the attack. +1 Fortress level, then defend.", "effect": "dragon_fortify"})
			EventBus.dilemma_triggered.emit(faction_id, "dragon_raid", {
				"title": "Dragon Raid on %s (%s | Raids survived: %d)" % [target_name, fort_desc, fs.dragon_raids_survived],
				"description": "A fire-drake descends on %s! The settlement is %s. How do you respond?" % [target_name, fort_desc],
				"choices": choices,
			})
		else:
			_ai_handle_dragon_raid(fs, target_id)

	# ── Frontier Orders dilemma (every 4 turns, offset from raids) ──
	if GameManager.state.current_turn % 4 == 2:
		if faction_id == GameManager.state.player_faction_id:
			var fort_choices := [
				{"label": "War Footing", "description": "+10 Vigilance. More iron and attack, less food.", "effect": "forge_war"},
				{"label": "Maintain Balance", "description": "No shift. Let buildings determine drift.", "effect": "forge_balanced"},
				{"label": "Stand Down", "description": "-10 Vigilance. More food and loyalty, less iron.", "effect": "forge_peace"},
				{"label": "Emergency Mobilization", "description": "+20 Vigilance instantly. Costs 30 Iron.", "effect": "forge_emergency", "cost": {1: 30}},
			]
			# Fortress building option (if settlements exist with room to upgrade)
			for cid in settlement_ids:
				var flv: int = fs.border_fortresses.get(cid, 0)
				if flv < 3:
					var cost_scrap = [10, 20, 35][mini(flv, 2)]
					var next_name = ["Watchtower", "Palisade", "Border Fort"][mini(flv, 2)]
					var city: CityState = GameManager.state.cities.get(cid)
					var cname := city.get_display_name() if city else str(cid)
					if fs.scavenge_stockpile >= cost_scrap:
						fort_choices.append({"label": "Build %s at %s" % [next_name, cname], "description": "Spend %d Scrap. Fortify the settlement (+defense, +slots, +scavenge)." % cost_scrap, "effect": "build_fort_%s" % cid})
					break # Only offer one fortress upgrade per dilemma
			EventBus.dilemma_triggered.emit(faction_id, "forge_allocation", {
				"title": "Frontier Orders (Vigilance: %d | Scrap: %d)" % [fs.border_vigilance, fs.scavenge_stockpile],
				"description": "The frontier awaits your orders. Settlements: %d, Fortresses: %d levels total." % [settlement_count, total_fort_level],
				"choices": fort_choices,
			})
		else:
			# AI: build fortresses when affordable, otherwise manage vigilance
			_ai_handle_frontier_orders(fs, settlement_ids)

func _ai_handle_dragon_raid(fs: FactionState, target_id: StringName) -> void:
	var fort_lv: int = fs.border_fortresses.get(target_id, 0)
	# AI: trap if affordable and fort is decent, otherwise defend
	if fs.resources.get(Enums.ResourceType.IRON, 0) >= 20 and fort_lv >= 1:
		# Trap
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) - 20
		var success := (fort_lv * 20 + 40 + randi() % 30) >= 50
		if success:
			fs.scavenge_stockpile += 25
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 8
			fs.dragon_raids_survived += 1
		else:
			_apply_dragon_damage(fs, target_id)
	else:
		# Defend
		var defense_score := fort_lv * 25 + fs.border_vigilance / 4 + randi() % 30
		if defense_score >= 45:
			fs.scavenge_stockpile += 15
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 5
			fs.border_vigilance = clampi(fs.border_vigilance + 5, 0, 100)
			fs.dragon_raids_survived += 1
		else:
			_apply_dragon_damage(fs, target_id)

func _ai_handle_frontier_orders(fs: FactionState, settlement_ids: Array[StringName]) -> void:
	# Priority: build fortresses > manage vigilance
	for cid in settlement_ids:
		var flv: int = fs.border_fortresses.get(cid, 0)
		if flv < 3:
			var cost_scrap = [10, 20, 35][mini(flv, 2)]
			if fs.scavenge_stockpile >= cost_scrap:
				fs.scavenge_stockpile -= cost_scrap
				fs.border_fortresses[cid] = flv + 1
				return
	# Vigilance management
	var at_war := false
	for other_id in GameManager.state.faction_states:
		if GameManager.get_relation(fs.faction_data_id, other_id) == Enums.FactionRelation.WAR:
			at_war = true
			break
	if at_war and fs.border_vigilance < 70:
		fs.forge_shift_queued = 10
	elif not at_war and fs.border_vigilance > 60:
		fs.forge_shift_queued = -10

func _apply_dragon_damage(fs: FactionState, target_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(target_id)
	if city:
		# Population loss
		city.population = maxi(city.population - 20, 10)
		# Loyalty hit
		for cls in city.class_loyalty:
			if cls != "captives":
				city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 8, -100, 100)
		# Destroy a random building if any
		if not city.buildings.is_empty():
			var destroyed: StringName = city.buildings[randi() % city.buildings.size()]
			city.buildings.erase(destroyed)
			GameManager.city_system.invalidate_region_effects_cache()
			city.building_tiles.erase(destroyed)
	# Fortress level drops
	var fort_lv: int = fs.border_fortresses.get(target_id, 0)
	if fort_lv > 0:
		fs.border_fortresses[target_id] = fort_lv - 1
	# Small scrap from rubble
	fs.scavenge_stockpile += 3
	fs.border_vigilance = clampi(fs.border_vigilance - 5, 0, 100)

# ── Forsaken: Espionage Network ──────────────────────────
# Grows from regions + espionage buildings. Threshold effects:
# 10+: enemy capitals revealed through fog (at-war, player only).
# 15+: ambush attack/speed bonus when attacking + passive tech income.
# 20+: steal gold op. 25+: steal research op. 30+: border loyalty erosion op.
# 35+: sabotage op (destroys a construction in progress).
# 40+: 30% chance per op to wound an enemy commander (3 turns, no bonuses).
# Sabotage has cooldown and detection risk (caught = standing penalty).

func _process_forsaken_espionage(fs: FactionState) -> void:
	# Network grows from territorial control
	var region_count := fs.owned_regions.size()
	var growth := region_count / 3
	# Research: espionage_per_turn
	var fk_r_eff := GameManager.research_system.get_research_effects(&"forsaken")
	growth += fk_r_eff.get("espionage_per_turn", 0)
	# Espionage buildings accelerate growth (hardcoded + special_effects: espionage_growth)
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city:
			if city.buildings.has(&"shadow_network"):
				growth += 1
			if city.buildings.has(&"void_pit"):
				growth += 1
			for building_id in city.buildings:
				var bd: BuildingData = DataManager.get_building(building_id)
				if bd and bd.special_effects.has("espionage_growth"):
					growth += int(bd.special_effects["espionage_growth"])
	fs.espionage_network = mini(fs.espionage_network + growth, 50)

	# Decay if losing territory
	if region_count <= 1:
		fs.espionage_network = maxi(fs.espionage_network - 2, 0)

	# Cooldown tracking
	if fs.espionage_sabotage_cooldown > 0:
		fs.espionage_sabotage_cooldown -= 1

	# ── 10+ Espionage: agents reveal enemy capitals (player fog only) ──
	if fs.espionage_network >= 10 and fs.faction_data_id == GameManager.state.player_faction_id:
		for other_id in GameManager.state.faction_states:
			if other_id == fs.faction_data_id or GameManager.is_npc_faction(other_id):
				continue
			if GameManager.get_relation(fs.faction_data_id, other_id) != Enums.FactionRelation.WAR:
				continue
			var other_fs_cap: FactionState = GameManager.state.faction_states[other_id]
			for cap_cid in other_fs_cap.owned_cities:
				var cap_city: CityState = GameManager.state.cities.get(cap_cid)
				if cap_city == null or not cap_city.is_capital:
					continue
				# Reveal the capital and a radius-2 ring around it
				var frontier: Array[Vector2i] = [cap_city.hex_pos]
				GameManager.explored_tiles[cap_city.hex_pos] = true
				for _ring in 2:
					var next_frontier: Array[Vector2i] = []
					for fcoord in frontier:
						for ncoord in HexHelper.get_neighbors(fcoord):
							if not GameManager.explored_tiles.has(ncoord):
								GameManager.explored_tiles[ncoord] = true
								next_frontier.append(ncoord)
					frontier = next_frontier

	# ── 20+ Espionage: Major sabotage operations ──
	if fs.espionage_network >= 20 and fs.espionage_sabotage_cooldown <= 0:
		var best_target: StringName = &""
		var best_gold := 0
		for other_id in GameManager.state.faction_states:
			if other_id == &"forsaken" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			if GameManager.get_relation(&"forsaken", other_id) == Enums.FactionRelation.WAR:
				var their_gold: int = other_fs.resources.get(Enums.ResourceType.GOLD, 0)
				if their_gold > best_gold:
					best_gold = their_gold
					best_target = other_id

		if best_target != &"" and best_gold > 15:
			if fs.faction_data_id == GameManager.state.player_faction_id:
				# Player picks the operation — the network is a tool, not an autopilot
				fs.espionage_op_target = best_target
				var target_fd: FactionData = DataManager.get_faction(best_target)
				var tname: String = target_fd.display_name if target_fd else str(best_target)
				var choices := [
					{"label": "Steal Treasury", "description": "Drain %s's gold reserves. 20%% detection risk." % tname, "effect": "spy_gold"},
					{"label": "Lie Low", "description": "No operation. Agents mend cover: improves standing with factions that caught you.", "effect": "spy_lielow"},
				]
				if fs.espionage_network >= 25:
					choices.insert(1, {"label": "Steal Research", "description": "Copy %s's research archives. 15%% detection risk." % tname, "effect": "spy_tech"})
				if fs.espionage_network >= 30:
					choices.insert(2, {"label": "Undermine Loyalty", "description": "Agitate %s's border cities (-3 loyalty). 25%% detection risk." % tname, "effect": "spy_loyalty"})
				if fs.espionage_network >= 35:
					choices.insert(3, {"label": "Sabotage Structures", "description": "Destroy %s's construction in progress. 25%% detection risk." % tname, "effect": "spy_sabotage"})
				EventBus.dilemma_triggered.emit(fs.faction_data_id, "espionage_op", {
					"title": "Shadow Operations (Network: %d)" % fs.espionage_network,
					"description": "Your handlers await orders. Target of opportunity: %s." % tname,
					"choices": choices,
				})
			else:
				# AI runs the full classic sweep
				_apply_espionage_operation(fs, "spy_gold", best_target)
				if fs.espionage_network >= 25:
					_apply_espionage_operation(fs, "spy_tech", best_target)
				if fs.espionage_network >= 30:
					_apply_espionage_operation(fs, "spy_loyalty", best_target)
				if fs.espionage_network >= 35:
					_apply_espionage_operation(fs, "spy_sabotage", best_target)
			fs.espionage_sabotage_cooldown = 2 # Every 2 turns

	# Passive tech income from intelligence gathering
	if fs.espionage_network >= 15:
		var tech_gain := mini(fs.espionage_network / 10, 3)
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_gain

## One espionage operation against a target faction (shared by AI + dilemma)
func _apply_espionage_operation(fs: FactionState, op: String, target: StringName) -> void:
	var enemy_fs: FactionState = GameManager.state.faction_states.get(target)
	if enemy_fs == null and op != "spy_lielow":
		return
	var detection := 0.0
	match op:
		"spy_gold":
			var their_gold: int = enemy_fs.resources.get(Enums.ResourceType.GOLD, 0)
			var stolen := mini(their_gold / 5, 25 + fs.espionage_network / 2)
			enemy_fs.resources[Enums.ResourceType.GOLD] = maxi(0, their_gold - stolen)
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + stolen
			detection = 0.20
		"spy_tech":
			var their_tech: int = enemy_fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)
			var tech_stolen := mini(their_tech / 4, 10)
			enemy_fs.resources[Enums.ResourceType.TECHNOLOGY] = maxi(0, their_tech - tech_stolen)
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_stolen
			detection = 0.15
		"spy_loyalty":
			for c_id in enemy_fs.owned_cities:
				var c: CityState = GameManager.state.cities.get(c_id)
				if c == null:
					continue
				for fr_id in fs.owned_regions:
					if GameManager.state.hex_map.regions_adjacent(c.region_id, fr_id):
						for cls in c.class_loyalty:
							if cls != "captives":
								c.class_loyalty[cls] = clampi(c.class_loyalty[cls] - 3, -100, 100)
						break
			detection = 0.25
		"spy_sabotage":
			# Destroy the target's most advanced construction in progress
			var sab_city: CityState = null
			for c_id2 in enemy_fs.owned_cities:
				var c2: CityState = GameManager.state.cities.get(c_id2)
				if c2 and not c2.build_queue.is_empty():
					if sab_city == null or c2.level > sab_city.level:
						sab_city = c2
			if sab_city:
				var sab_item: Dictionary = sab_city.build_queue[0]
				sab_city.build_queue.remove_at(0)
				var sab_bd: BuildingData = DataManager.get_building(sab_item.get("building_id", &""))
				var sab_name: String = sab_bd.display_name if sab_bd else "a structure"
				turn_log.append({type = "army", text = "Saboteurs destroyed %s under construction in %s!" % [sab_name, sab_city.get_display_name()]})
			detection = 0.25
		"spy_lielow":
			# Mend cover: recover standing with factions that caught your agents
			for caught_id in fs.espionage_caught_by:
				GameManager.diplomacy_system.modify_standing(fs.faction_data_id, caught_id, 2, "Spies lie low")
			fs.espionage_caught_by.clear()
			return
	# 40+ network: master assassins — chance to wound an enemy commander during any op
	if fs.espionage_network >= 40 and randf() < 0.30:
		var wound_candidates: Array = []
		for e_army: ArmyState in GameManager.get_faction_armies(target):
			if e_army.commander and e_army.commander.wounded_turns <= 0 and not e_army.commander.is_elderbeast:
				wound_candidates.append(e_army.commander)
		if not wound_candidates.is_empty():
			var wounded: CommanderState = wound_candidates[randi() % wound_candidates.size()]
			wounded.wounded_turns = 3
			turn_log.append({type = "army", text = "%s was wounded by shadow agents (no command bonuses for 3 turns)" % wounded.name})
	if randf() < detection:
		fs.espionage_caught_by.append(target)
		for other_id in GameManager.state.faction_states:
			if other_id == fs.faction_data_id or GameManager.is_npc_faction(other_id):
				continue
			var other_fs2: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs2.is_defeated:
				GameManager.diplomacy_system.modify_standing(fs.faction_data_id, other_id, -3, "Espionage detected")

# ── Ivoryscar: Relic Power ───────────────────────────────
# Grows from shard_wastes control + owned shards. MUCH stronger scaling:
# 10+: +2 tech, +5% defense. 20+: +4 tech, +10% def, commander items stronger.
# 30+: +7 tech, +1 essence, +15% def. 40+: +10 tech, +2 essence, relic expeditions.
# Relic Expedition dilemma every 5 turns gives player active choices.

func _process_ivoryscar_relics(fs: FactionState) -> void:
	# Relic Defense (expedition choice): tick down the 3-turn city-defense ward
	var relic_def_turns: int = int(fs.leader_bonuses.get("relic_defense_turns", 0))
	if relic_def_turns > 0:
		fs.leader_bonuses["relic_defense_turns"] = relic_def_turns - 1

	# Relic power from shard wastes + shards
	var wastes_count := 0
	for region_id in fs.owned_regions:
		var region_tiles := GameManager.state.hex_map.get_region_tiles(region_id)
		for coord in region_tiles:
			var tile := GameManager.state.hex_map.get_tile(coord)
			if tile and tile.terrain == Enums.TerrainType.SHARD_WASTES:
				wastes_count += 1
	var shard_count := fs.owned_shards.size()
	var target_power := wastes_count / 3 + shard_count * 5

	# Research: relic_power_per_turn
	var iv_r_eff := GameManager.research_system.get_research_effects(&"ivoryscar")
	target_power += iv_r_eff.get("relic_power_per_turn", 0)
	# Building special_effects: relic_power_bonus
	target_power += int(_sum_building_special_effect(fs, "relic_power_bonus"))
	# Drift toward target (faster growth, slower decay)
	if fs.relic_power < target_power:
		fs.relic_power = mini(fs.relic_power + 3, 50)
	elif fs.relic_power > target_power:
		fs.relic_power = maxi(fs.relic_power - 1, 0)

	# ── Scaled tech and resource bonuses ──
	if fs.relic_power >= 10:
		var tech_bonus := 2
		if fs.relic_power >= 20:
			tech_bonus = 4
		if fs.relic_power >= 30:
			tech_bonus = 7
		if fs.relic_power >= 40:
			tech_bonus = 10
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_bonus

	# Shard essence generation
	if fs.relic_power >= 25:
		var essence := 1 if fs.relic_power < 40 else 2
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + essence

	# Gold income from relic trade
	if fs.relic_power >= 20:
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + mini(fs.relic_power / 5, 6)

	# Diplomacy: scholarly factions respect relic knowledge
	if fs.relic_power >= 20:
		for other_id in GameManager.state.faction_states:
			if other_id == &"ivoryscar" or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if other_fs.is_defeated:
				continue
			var fd: FactionData = DataManager.get_faction(other_id)
			if fd and &"scholarly" in fd.gift_likes:
				GameManager.diplomacy_system.modify_standing(&"ivoryscar", other_id, 1, "Relic knowledge")

	# ── Black Pyramid Restoration ──
	# Relic power passively fuels restoration, requires shard essence + claimed shards
	if not fs.pyramid_restored:
		var restoration_gain := fs.relic_power / 10 # 0-5 per turn based on relic power
		# Research bonus
		restoration_gain += iv_r_eff.get("pyramid_restoration_per_turn", 0)
		# Passive restoration consumes 1 shard essence per turn
		if restoration_gain > 0:
			var essence = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0)
			if essence >= 1:
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = essence - 1
				fs.pyramid_restoration = mini(fs.pyramid_restoration + restoration_gain, 100)
			# Without essence, restoration stalls (no progress)
		# Every 3 turns, consume a claimed shard crystal for a bonus +5 restoration
		if GameManager.state.current_turn % 3 == 0 and not fs.owned_shards.is_empty():
			var shard_id: StringName = fs.owned_shards[0]
			fs.owned_shards.erase(shard_id)
			if GameManager.state.active_shards.has(shard_id):
				GameManager.state.active_shards.erase(shard_id)
			fs.pyramid_restoration = mini(fs.pyramid_restoration + 5, 100)
		# Check if fully restored
		if fs.pyramid_restoration >= 100:
			fs.pyramid_restored = true
			fs.pyramid_restoration = 100

	# Pyramid milestone bonuses (applied every turn, stacking thresholds)
	if fs.pyramid_restoration >= 25:
		# Foundation Laid: +3 iron/turn, +2 defense to all cities
		fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 3
	if fs.pyramid_restoration >= 50:
		# Walls Rising: +4 tech/turn, +5 gold/turn from pilgrim tourism
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 4
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 5
	if fs.pyramid_restoration >= 75:
		# Inner Sanctum Unsealed: +2 shard essence/turn, all armies +5% attack
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 2
	if fs.pyramid_restored:
		# The Black Pyramid Restored: massive permanent bonuses
		# +8 gold, +6 tech, +3 shard essence, all armies +15% attack/defense
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 8
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 6
		fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 3

	# Expedition cooldown
	if fs.relic_expedition_cooldown > 0:
		fs.relic_expedition_cooldown -= 1

	# Relic Expedition dilemma every 5 turns (if power is high enough)
	if fs.relic_power >= 15 and fs.relic_expedition_cooldown <= 0 and GameManager.state.current_turn % 5 == 0:
		if fs.faction_data_id == GameManager.state.player_faction_id:
			var choices := [
				{"label": "Fund Expedition", "description": "Spend 30 Gold + 5 Tech. 65%: find relic (+8 power, +item). 20%: knowledge (+15 tech). 15%: danger (-5 power).", "effect": "relic_fund", "cost": {0: 30, 2: 5}},
				{"label": "Study Existing Relics", "description": "No cost. +5 Tech, +2 Relic Power.", "effect": "relic_study"},
				{"label": "Relic Defense", "description": "Fortify dig sites. +3 defense to all cities for 3 turns.", "effect": "relic_fortify"},
			]
			# Pyramid investment option (when not fully restored and have resources)
			if not fs.pyramid_restored:
				var has_shard := not fs.owned_shards.is_empty()
				var pyramid_desc := "Spend 40 Gold + 15 Iron + 5 Shard Essence + 1 Shard Crystal. Accelerate restoration by +15. (Current: %d/100)" % fs.pyramid_restoration
				if not has_shard:
					pyramid_desc += " [No Shard Crystal!]"
				choices.append({"label": "Invest in the Black Pyramid", "description": pyramid_desc, "effect": "pyramid_invest", "cost": {0: 40, 1: 15, 4: 5}, "requires_shard": true})
			EventBus.dilemma_triggered.emit(&"ivoryscar", "relic_expedition", {
				"title": "Relic Expedition (Power: %d | Pyramid: %d%%)" % [fs.relic_power, fs.pyramid_restoration],
				"description": "Your scholars have located a promising dig site. How shall we proceed?",
				"choices": choices,
			})
		else:
			# AI: prefer pyramid investment when affordable (resources + shard crystal)
			if not fs.pyramid_restored and not fs.owned_shards.is_empty() and fs.resources.get(Enums.ResourceType.GOLD, 0) >= 40 and fs.resources.get(Enums.ResourceType.IRON, 0) >= 15 and fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) >= 5:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 40
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) - 15
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) - 5
				var ai_shard_id: StringName = fs.owned_shards[0]
				fs.owned_shards.erase(ai_shard_id)
				if GameManager.state.active_shards.has(ai_shard_id):
					GameManager.state.active_shards.erase(ai_shard_id)
				fs.pyramid_restoration = mini(fs.pyramid_restoration + 15, 100)
				if fs.pyramid_restoration >= 100:
					fs.pyramid_restored = true
			elif fs.resources.get(Enums.ResourceType.GOLD, 0) >= 30 and fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) >= 5:
				# Fund expedition
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) - 30
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) - 5
				var roll := randf()
				if roll < 0.65:
					fs.relic_power = mini(fs.relic_power + 8, 50)
					var relic_items: Array[StringName] = [&"qareth_hieroglyph_tablet", &"tomb_kings_scarab", &"scepter_of_ages", &"void_shard_amulet", &"crystal_shard_blade", &"bone_dice_set"]
					fs.item_storage.append(relic_items[randi() % relic_items.size()])
				elif roll < 0.85:
					fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
				else:
					fs.relic_power = maxi(0, fs.relic_power - 5)
			else:
				fs.relic_power = mini(fs.relic_power + 2, 50)
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 5
			fs.relic_expedition_cooldown = 5

# ── Sunblessed: Solar Faith ──────────────────────────────
# 0-100. High faith = STRONG army healing, attack, defense, loyalty.
# Low faith = devastating penalties. Drifts toward 50 naturally.
# Much more impactful breakpoints than before.

func _process_sunblessed_faith(fs: FactionState, fid: StringName = &"sunblessed") -> void:
	# Natural drift toward 50
	if fs.solar_faith > 50:
		fs.solar_faith -= 1
	elif fs.solar_faith < 50:
		fs.solar_faith += 1
	# Research: solar_faith_per_turn and wisdom_per_turn
	var sb_r_eff := GameManager.research_system.get_research_effects(fid)
	fs.solar_faith = clampi(fs.solar_faith + sb_r_eff.get("solar_faith_per_turn", 0), 0, 100)
	fs.wisdom = clampi(fs.wisdom + sb_r_eff.get("wisdom_per_turn", 0), 0, 200)

	# Building special_effects: faith_stabilization slows faith decay
	var faith_stab := int(_sum_building_special_effect(fs, "faith_stabilization"))
	# Also add solar_faith_income from buildings
	var bld_faith := int(_sum_building_special_effect(fs, "solar_faith_income"))
	fs.solar_faith = clampi(fs.solar_faith + bld_faith, 0, 100)
	if faith_stab > 0 and fs.solar_faith > 50:
		fs.solar_faith = mini(fs.solar_faith + faith_stab, 100) # Counteract decay

	# Golden Age cooldown tick
	if fs.golden_age_cooldown > 0:
		fs.golden_age_cooldown -= 1

	# ── High Faith (85+): Radiant Blessing ──
	if fs.solar_faith >= 85:
		# Strong army healing in owned territory
		for army: ArmyState in GameManager.get_faction_armies(fid):
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile and tile.region_id in fs.owned_regions:
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = mini(unit.current_hp + 5, ud.max_hp * ud.squad_size)
		# Loyalty boost to ALL cities
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
		# Gold income from faithful donations
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 6

		# ── Golden Age dilemma: spend accumulated faith on a great work ──
		if fs.golden_age_cooldown <= 0:
			if fs.faction_data_id == GameManager.state.player_faction_id:
				EventBus.dilemma_triggered.emit(fid, "golden_age", {
					"title": "The Sun Stands High (Faith: %d)" % fs.solar_faith,
					"description": "The faithful overflow with devotion. Spend this radiance, or let it shine on.",
					"choices": [
						{"label": "Proclaim a Golden Age", "description": "Spend 30 Faith: +50 Gold, +25 Technology, heal all armies.", "effect": "golden_proclaim"},
						{"label": "Radiant Teachings", "description": "Spend 20 Faith: +30 Wisdom for the academies.", "effect": "golden_teach"},
						{"label": "Preserve the Flame", "description": "Keep the faith burning. Passive blessings continue.", "effect": "golden_preserve"},
					],
				})
				fs.golden_age_cooldown = 8
			else:
				# AI: build wisdom first, then cash in at very high faith
				if fs.wisdom < 100:
					_apply_golden_age(fs, fid, "golden_teach")
				elif fs.solar_faith >= 95:
					_apply_golden_age(fs, fid, "golden_proclaim")
				fs.golden_age_cooldown = 8

	# ── Moderate Faith (70-84): Warm Glow ──
	elif fs.solar_faith >= 70:
		for army: ArmyState in GameManager.get_faction_armies(fid):
			var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
			if tile and tile.region_id in fs.owned_regions:
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = mini(unit.current_hp + 3, ud.max_hp * ud.squad_size)
		# Capital loyalty only
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.is_capital:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 1, -100, 100)
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 3

	# ── Low Faith (25-39): Doubt Spreads ──
	elif fs.solar_faith <= 39 and fs.solar_faith > 24:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 1, -100, 100)

	# ── Crisis Faith (<25): Dark Night of the Soul ──
	elif fs.solar_faith <= 24:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for cls in city.class_loyalty:
					if cls != "captives":
						city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 3, -100, 100)
		# Gold loss from abandoned temples
		fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 5)
		# Diplomacy penalty with divine factions
		for other_id in GameManager.state.faction_states:
			if other_id == fid or GameManager.is_npc_faction(other_id):
				continue
			var other_fs: FactionState = GameManager.state.faction_states[other_id]
			if not other_fs.is_defeated:
				var fd: FactionData = DataManager.get_faction(other_id)
				if fd and fd.realm_affinity == Enums.Realm.DIVINE:
					GameManager.diplomacy_system.modify_standing(fid, other_id, -2, "Faith crisis")

	# Food bonus from faithful agriculture (always, scales with faith)
	if fs.solar_faith >= 40:
		fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + mini(fs.solar_faith / 15, 5)

	# Update mobile camp positions to follow their armies
	for army: ArmyState in GameManager.get_faction_armies(fid):
		if army.camp_city_id != &"" and not army.is_camp:
			var camp_city: CityState = GameManager.state.cities.get(army.camp_city_id)
			if camp_city and camp_city.is_mobile_camp:
				camp_city.hex_pos = army.hex_pos
				GameManager.city_system.invalidate_city_hex_index()
				var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
				if tile:
					camp_city.region_id = tile.region_id

	# Solar Faith proximity: gain faith near developed foreign cities (diminishing).
	# Inverted: instead of scanning all cities per army, query the ~37-hex
	# neighborhood via the O(1) city index. Multi-candidate ties resolve by
	# state.cities insertion order, matching the old first-match semantics.
	var proximity_faith := 0
	for army: ArmyState in GameManager.get_faction_armies(fid):
		var best_city: CityState = null
		var candidates: Array = []
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				var h := Vector2i(army.hex_pos.x + dx, army.hex_pos.y + dy)
				if HexHelper.hex_distance(army.hex_pos, h) > 3:
					continue
				var c: CityState = GameManager.city_system.get_city_at_hex(h)
				if c == null or c.faction_id == fid or c.faction_id == &"independent":
					continue
				candidates.append(c)
		if candidates.size() == 1:
			best_city = candidates[0]
		elif candidates.size() > 1:
			for city_id in GameManager.state.cities:
				var c2: CityState = GameManager.state.cities[city_id]
				if candidates.has(c2):
					best_city = c2
					break
		if best_city:
			proximity_faith += mini(best_city.level, 3) # Only one city per army counts
	if proximity_faith > 0:
		# Diminishing returns based on how long near cities
		fs.solar_faith_proximity_turns += 1
		var diminish := maxf(0.2, 1.0 - fs.solar_faith_proximity_turns * 0.1)
		var faith_gain := maxi(1, int(float(proximity_faith) * diminish))
		fs.solar_faith = mini(fs.solar_faith + faith_gain, 100)
	else:
		fs.solar_faith_proximity_turns = maxi(0, fs.solar_faith_proximity_turns - 1)

	# Apply Wanderer's Rest movement bonus + solar_faith_income
	for army: ArmyState in GameManager.get_faction_armies(fid):
		if army.camp_city_id == &"":
			continue
		var camp_city: CityState = GameManager.state.cities.get(army.camp_city_id)
		if camp_city == null:
			continue
		for bid in camp_city.buildings:
			var bdata: BuildingData = DataManager.get_building(bid)
			if bdata and bdata.special_effects.has("solar_faith_income"):
				fs.solar_faith = mini(fs.solar_faith + int(bdata.special_effects["solar_faith_income"]), 100)

# ── Sunblessed: Wisdom & Teaching ─────────────────────────
# Wisdom grows near allied cities. Effects: tech income (+1 per 8, cap +12),
# diplomacy standing (+1/+2/+3 at 25/40/60), educator aura (ally +4 tech,
# +2 loyalty, +1 standing), and research speed (+wisdom/400, up to +50% —
# applied in research_system._get_faction_research_speed_bonus).

func _apply_golden_age(fs: FactionState, fid: StringName, effect: String) -> void:
	match effect:
		"golden_proclaim":
			if fs.solar_faith >= 30:
				fs.solar_faith -= 30
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + 50
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 25
				for army: ArmyState in GameManager.get_faction_armies(fid):
					for unit in army.units:
						var ud := DataManager.get_unit(unit.unit_data_id)
						if ud:
							unit.current_hp = mini(unit.current_hp + 15, ud.max_hp * ud.squad_size)
		"golden_teach":
			if fs.solar_faith >= 20:
				fs.solar_faith -= 20
				fs.wisdom = clampi(fs.wisdom + 30, 0, 200)
		"golden_preserve":
			pass

func _process_sunblessed_wisdom(fs: FactionState, fid: StringName = &"sunblessed") -> void:
	var sunblessed_fid := fid
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var wisdom_gain := 0
	var educated_cities: Dictionary = {}
	var sunblessed_armies := GameManager.get_faction_armies(sunblessed_fid)
	# Union of hexes within distance 2 of any Sunblessed army — replaces the
	# per-city scan over all armies with an O(1) set lookup (any-match check,
	# so the inversion cannot change results).
	var near_army_hexes: Dictionary = {}
	for army: ArmyState in sunblessed_armies:
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var h := Vector2i(army.hex_pos.x + dx, army.hex_pos.y + dy)
				if HexHelper.hex_distance(army.hex_pos, h) <= 2:
					near_army_hexes[h] = true
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == sunblessed_fid or city.faction_id == &"independent":
			continue
		if educated_cities.has(city_id):
			continue
		if not near_army_hexes.has(city.hex_pos):
			continue
		var standing := GameManager.diplomacy_system.get_standing(sunblessed_fid, city.faction_id)
		if standing >= 20:
			educated_cities[city_id] = true
			wisdom_gain += 2
			# Educator aura: allied city gets +4 tech and +2 loyalty (stronger)
			var ally_fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
			if ally_fs:
				ally_fs.resources[Enums.ResourceType.TECHNOLOGY] = ally_fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + 4
			for cls in city.class_loyalty:
				if cls != "captives":
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + 2, -100, 100)
			# Wisdom near allies also boosts diplomacy with that faction
			GameManager.diplomacy_system.modify_standing(sunblessed_fid, city.faction_id, 1, "Educator presence")

	for other_fid in GameManager.state.faction_states:
		if other_fid == sunblessed_fid:
			continue
		var standing := GameManager.diplomacy_system.get_standing(sunblessed_fid, other_fid)
		if standing >= 40:
			wisdom_gain += 1

	fs.wisdom = mini(fs.wisdom + wisdom_gain, 200)

	# Wisdom tech income (stronger scaling)
	if fs.wisdom >= 10:
		var tech_bonus := mini(fs.wisdom / 8, 12) # +1 per 8 wisdom, max +12
		fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + tech_bonus

	# Wisdom diplomacy (stronger scaling)
	if fs.wisdom >= 25:
		var diplo_bonus := 1
		if fs.wisdom >= 60:
			diplo_bonus = 3
		elif fs.wisdom >= 40:
			diplo_bonus = 2
		for diplo_fid in GameManager.state.faction_states:
			if diplo_fid == sunblessed_fid:
				continue
			var standing := GameManager.diplomacy_system.get_standing(sunblessed_fid, diplo_fid)
			if standing > -30:
				GameManager.diplomacy_system.modify_standing(sunblessed_fid, diplo_fid, diplo_bonus, "Sunblessed wisdom")
