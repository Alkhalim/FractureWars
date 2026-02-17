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

# Random event temp effects
var _temp_effects: Array[Dictionary] = [] # [{faction_id, effect, turns_remaining}]

func _ready() -> void:
	EventBus.end_turn_pressed.connect(_on_end_turn_pressed)

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

	# Process city system: income, growth, queues, sieges
	GameManager.city_system.process_turn(faction_id)

	# Process elderbeasts for Shardhorde
	if faction_id == &"shardhorde":
		_process_elderbeasts()

	# Heal armies in settlements/friendly territory
	_heal_armies_in_settlements(faction_id)

	# Grant passive XP to commanders
	_grant_passive_commander_xp(faction_id)

	# Reset army movement for this faction (skip garrisons)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and not army.is_garrison:
			army.movement_remaining = army.get_max_movement()
			army.has_moved = false

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
	GameManager.state.current_turn += 1

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
		GameManager.state.active_shards.erase(shard_id)

func get_current_faction() -> StringName:
	if current_faction_index < faction_order.size():
		return faction_order[current_faction_index]
	return &""

# ── Commander XP ─────────────────────────────────────────────

func _grant_passive_commander_xp(faction_id: StringName) -> void:
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and army.commander:
			CommanderSystem.grant_passive_xp(army.commander)

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

	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue

		# Build buildings using upgrade-aware system
		if city.build_queue.is_empty():
			var available := GameManager.city_system.get_available_buildings(city)
			if available.size() > 0:
				# Priority: first available building by priority, then upgrades
				var built := false
				for priority_id in [&"cohort_barracks", &"grain_fields", &"iron_pit", &"lumber_camp_empire", &"tavern", &"market_square"]:
					if built:
						break
					for b in available:
						if b.id == priority_id:
							GameManager.city_system.start_building(city_id, b.id)
							built = true
							break
				if not built:
					# Try upgrades for existing buildings
					for b in available:
						if b.upgrades_from != &"":
							if GameManager.city_system.start_building(city_id, b.id):
								built = true
								break
				if not built:
					# Try any remaining building
					for b in available:
						if GameManager.city_system.start_building(city_id, b.id):
							break

		# Upgrade city when possible
		if city.upgrade_turns_remaining <= 0 and GameManager.city_system.can_start_upgrade(city):
			GameManager.city_system.start_upgrade(city_id)

		# Recruit units with composition awareness
		if city.recruit_queue.is_empty() and city.population > 120:
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

	# Only recruit aggressively if needed
	if total_units >= 12:
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
					var path := GameManager.movement_system.find_path(
						closest_army.hex_pos, target_hex, faction_id, INF)
					if path.size() > 0:
						GameManager.move_army_along_path(closest_army.army_id, path)
			return

		# Evaluate best settlement tile
		var valid_tiles := GameManager.city_system.get_valid_settlement_tiles(faction_id, city.region_id)
		if valid_tiles.is_empty():
			continue

		var best_tile := Vector2i(-1, -1)
		var best_score := -999
		var capital_pos := city.hex_pos
		for tile_pos in valid_tiles:
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
				var path := GameManager.movement_system.find_path(
					army.hex_pos, nearest_city, faction_id, INF)
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

		var path := GameManager.movement_system.find_path(
			army.hex_pos, target_hex, faction_id, INF)
		if path.size() > 0:
			GameManager.move_army_along_path(army.army_id, path)
			if not GameManager.state.armies.has(army.army_id):
				continue
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return

	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

# ── Skulloath AI (Raider) ────────────────────────────────────

func _execute_skulloath_ai(faction_id: StringName) -> void:
	var cooldown: int = _ai_aggression_cooldown.get(faction_id, 0)
	if cooldown > 0:
		# Defensive phase: recruit, defend own cities, don't attack
		_ai_aggression_cooldown[faction_id] = cooldown - 1
		_execute_defensive_skulloath(faction_id)
		await get_tree().create_timer(0.5).timeout
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
			var path := GameManager.movement_system.find_path(
				army.hex_pos, target_hex, faction_id, INF)
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

	await get_tree().create_timer(0.5).timeout
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
		var path := GameManager.movement_system.find_path(
			army.hex_pos, nearest_city, faction_id, INF)
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
			var path := GameManager.movement_system.find_path(
				army.hex_pos, intruder, faction_id, INF)
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
			var path := GameManager.movement_system.find_path(
				army.hex_pos, target, faction_id, INF)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					_gladehost_waypoints.erase(army.army_id)
					continue
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return

	await get_tree().create_timer(0.5).timeout
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
				var path := GameManager.movement_system.find_path(
					army.hex_pos, nearest_city, faction_id, INF)
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
			var path := GameManager.movement_system.find_path(
				army.hex_pos, intruder, faction_id, INF)
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
				var path := GameManager.movement_system.find_path(
					army.hex_pos, target_hex, faction_id, INF)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						_jade_patrol_index.erase(army.army_id)
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return

	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

# ── Shardhorde AI (Nomadic) ──────────────────────────────────

func _execute_shardhorde_ai() -> void:
	var faction_id := &"shardhorde"

	# Move elderbeasts
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != faction_id:
			continue
		_move_elderbeast(beast)

	# Move armies
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Check if this is an escort army - stay adjacent to beast
		var is_escort := false
		for beast_id in GameManager.state.elderbeasts:
			var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
			if beast.escort_army_id == army.army_id:
				is_escort = true
				var dist_to_beast := HexHelper.hex_distance(army.hex_pos, beast.hex_pos)
				if dist_to_beast > 1:
					# Move to adjacent tile near beast
					var best_neighbor := Vector2i(-1, -1)
					var best_dist := 9999
					for n in HexHelper.get_neighbors(beast.hex_pos):
						if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
							continue
						var tile := GameManager.state.hex_map.get_tile(n)
						if tile == null or tile.terrain == Enums.TerrainType.WATER:
							continue
						if GameManager.movement_system._is_tile_blocked(n, faction_id, army.army_id):
							continue
						var d := HexHelper.hex_distance(army.hex_pos, n)
						if d < best_dist:
							best_dist = d
							best_neighbor = n
					if best_neighbor != Vector2i(-1, -1):
						var path := GameManager.movement_system.find_path(
							army.hex_pos, best_neighbor, faction_id, INF, army.army_id)
						if path.size() > 0:
							GameManager.move_army_along_path(army.army_id, path)
							if not GameManager.state.armies.has(army.army_id):
								beast.escort_army_id = &""
				break

		if is_escort:
			continue

		# Raiding armies: attack nearby enemies within 6 hexes of nearest beast
		var nearest_beast_pos := _get_nearest_beast_pos(army.hex_pos)
		var target_hex := _find_nearest_enemy_army_hex(army.hex_pos, faction_id)
		if target_hex != Vector2i(-1, -1):
			var dist_to_beast := 999
			if nearest_beast_pos != Vector2i(-1, -1):
				dist_to_beast = HexHelper.hex_distance(target_hex, nearest_beast_pos)
			if dist_to_beast <= 6:
				var path := GameManager.movement_system.find_path(
					army.hex_pos, target_hex, faction_id, INF)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return
				continue

		# Wander near beasts
		if nearest_beast_pos != Vector2i(-1, -1):
			var dist := HexHelper.hex_distance(army.hex_pos, nearest_beast_pos)
			if dist > 5:
				# Too far, move back toward beast
				var path := GameManager.movement_system.find_path(
					army.hex_pos, nearest_beast_pos, faction_id, INF)
				if path.size() > 0:
					GameManager.move_army_along_path(army.army_id, path)
					if not GameManager.state.armies.has(army.army_id):
						continue
					if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
						return

	# Recruit at elderbeasts
	_shardhorde_recruit()

	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

func _move_elderbeast(beast: ElderbeastState) -> void:
	beast.survival_turns += 1
	# Level up based on survival
	if beast.level < 3:
		if (beast.level == 1 and beast.survival_turns >= 10) or \
		   (beast.level == 2 and beast.survival_turns >= 25):
			beast.level += 1

	# Move 1 hex toward SHARD_WASTES or DESERT terrain, avoid water
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var neighbors := HexHelper.get_neighbors(beast.hex_pos)
	var best_hex := beast.hex_pos
	var best_score := -999

	for n in neighbors:
		if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(n)
		if tile == null or tile.terrain == Enums.TerrainType.WATER:
			continue
		# Skip tiles occupied by any army
		if GameManager.get_armies_at_tile(n).size() > 0:
			continue
		# Skip tiles with other elderbeasts
		var has_beast := false
		for bid in GameManager.state.elderbeasts:
			var b: ElderbeastState = GameManager.state.elderbeasts[bid]
			if b.beast_id != beast.beast_id and b.hex_pos == n:
				has_beast = true
				break
		if has_beast:
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
		# Random wander factor
		score += randi() % 3
		if score > best_score:
			best_score = score
			best_hex = n

	if best_hex != beast.hex_pos:
		var old_pos := beast.hex_pos
		beast.hex_pos = best_hex
		EventBus.elderbeast_moved.emit(beast.beast_id, old_pos, best_hex)

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
		# Start new recruitment
		if not beast.buildings.has(&"barracks"):
			continue
		# Recruit crystal_swarmling (cheapest)
		var uid := &"crystal_swarmling"
		var udata := DataManager.get_unit(uid)
		if udata == null:
			continue
		if not _can_afford_faction(fs, udata.recruit_cost):
			continue
		_deduct_faction_cost(fs, udata.recruit_cost)
		beast.recruit_queue.append({unit_data_id = uid, turns_remaining = udata.recruit_time})

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

func _process_elderbeasts() -> void:
	var fs: FactionState = GameManager.state.faction_states.get(&"shardhorde")
	if fs == null:
		return
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id != &"shardhorde":
			continue
		# Generate income (50% of equivalent city level)
		var income := _get_elderbeast_income(beast)
		for res_type in income:
			if fs.resources.has(res_type):
				fs.resources[res_type] += income[res_type]
			else:
				fs.resources[res_type] = income[res_type]

func _get_elderbeast_income(beast: ElderbeastState) -> Dictionary:
	var income: Dictionary = {}
	income[Enums.ResourceType.GOLD] = 2 * beast.level
	income[Enums.ResourceType.FOOD] = 3 * beast.level
	# Building bonuses
	for building_id in beast.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		for res_type in building.income_bonus:
			var bonus: int = building.income_bonus[res_type] / 2 # 50%
			income[res_type] = income.get(res_type, 0) + maxi(1, bonus)
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
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.15) + cmd_heal
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
		elif cmd_heal > 0:
			# Commander heals even in neutral territory
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				unit.current_hp = mini(unit.current_hp + cmd_heal, unit_data.max_hp)

# ── Random Events ────────────────────────────────────────────

const RANDOM_EVENTS := [
	{
		"title": "Wandering Merchant",
		"text": "A mysterious merchant offers rare goods at a fair price.",
		"choice_a": "Buy (50 Gold)",
		"choice_b": "Decline",
		"type": "merchant",
	},
	{
		"title": "Ancient Ruins",
		"text": "Your scouts discovered ancient ruins. Exploring them could yield treasure, but not without risk.",
		"choice_a": "Explore (risk 20% HP)",
		"choice_b": "Leave them be",
		"type": "ruins",
	},
	{
		"title": "Deserters",
		"text": "A group of deserters offers to join your ranks, but their loyalty is questionable.",
		"choice_a": "Accept (free unit)",
		"choice_b": "Turn them away",
		"type": "deserters",
	},
	{
		"title": "Mysterious Stranger",
		"text": "A cloaked figure offers wisdom to your commander in exchange for nothing... or so they claim.",
		"choice_a": "Accept wisdom (+30 XP)",
		"choice_b": "Take gold instead (+40 Gold)",
		"type": "stranger",
	},
	{
		"title": "Sacred Grove",
		"text": "Your army discovers a sacred grove radiating with healing energy.",
		"choice_a": "Bless commander (heal bonus)",
		"choice_b": "Bless city (growth bonus)",
		"type": "grove",
	},
	{
		"title": "Border Dispute",
		"text": "A neighboring faction's emissary arrives with an offer of goodwill.",
		"choice_a": "Accept friendship",
		"choice_b": "Demand tribute (+30 Iron)",
		"type": "dispute",
	},
]

func _check_random_events(faction_id: StringName) -> void:
	if GameManager.state.current_turn <= 1:
		return
	if randf() > 0.05:
		return # 5% chance
	var event: Dictionary = RANDOM_EVENTS[randi() % RANDOM_EVENTS.size()].duplicate()
	event["faction_id"] = faction_id
	event["selected_army_id"] = GameManager.state.selected_army_id
	EventBus.random_event_triggered.emit(event)

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
					var ud := DataManager.get_unit(unit_id)
					var unit_name := ud.display_name if ud else str(unit_id)
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
			if choice == "a":
				return "Relations improved with a neighboring faction."
			else:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + 30
				return "Received +30 Iron (now %d)" % fs.resources.get(Enums.ResourceType.IRON, 0)

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

func _find_nearest_enemy_army_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id:
			continue
		if GameManager.get_relation(faction_id, army.faction_id) != Enums.FactionRelation.WAR:
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
	var borders: Array[Vector2i] = []
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
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
	return borders

func _can_afford_faction(fs: FactionState, cost: Dictionary) -> bool:
	for res_type in cost:
		if fs.resources.get(res_type, 0) < cost[res_type]:
			return false
	return true

func _deduct_faction_cost(fs: FactionState, cost: Dictionary) -> void:
	for res_type in cost:
		if fs.resources.has(res_type):
			fs.resources[res_type] -= cost[res_type]
