extends Node

var faction_order: Array[StringName] = []
var current_faction_index: int = 0
var is_player_turn: bool = true
var shardfall_system: ShardfallSystem = ShardfallSystem.new()

func _ready() -> void:
	EventBus.end_turn_pressed.connect(_on_end_turn_pressed)

func start_game() -> void:
	# Build faction order: player first, then AI factions
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

	# Heal armies in settlements/friendly territory
	_heal_armies_in_settlements(faction_id)

	# Reset army movement for this faction
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id:
			army.movement_remaining = army.get_max_movement()
			army.has_moved = false

	EventBus.turn_started.emit(GameManager.state.current_turn, faction_id)

	if not is_player_turn:
		_execute_ai_city_management(faction_id)
		if faction_id == &"gladehost":
			_execute_gladehost_ai(faction_id)
		elif faction_id == &"tainted_jade":
			_execute_tainted_jade_ai(faction_id)
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

	# Check for shardfall
	shardfall_system.check_shardfall(GameManager.state.current_turn)

	# Advance calendar
	GameManager.state.current_month += 1
	if GameManager.state.current_month >= 10:
		GameManager.state.current_month = 0
		GameManager.state.current_year += 1

	# Decay unclaimed shards
	_decay_shards()

	# Advance turn counter
	GameManager.state.current_turn += 1

	# Start next round
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

func _execute_ai_turn(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Find nearest player army hex to move toward
		var target_hex := _find_nearest_player_army_hex(army.hex_pos, faction_id)
		if target_hex == Vector2i(-1, -1):
			# No player army; find nearest player-owned region center
			target_hex = _find_nearest_player_region_hex(army.hex_pos)
		if target_hex == Vector2i(-1, -1):
			continue

		# Use A* to find full path (INF cost limit), then move_army_along_path handles partial movement
		var path := GameManager.movement_system.find_path(
			army.hex_pos, target_hex, faction_id, INF)

		if path.size() > 0:
			GameManager.move_army_along_path(army.army_id, path)

			# Check if battle was triggered (army may have been removed or scene changed)
			if not GameManager.state.armies.has(army.army_id):
				return
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return

	# AI turn done, proceed
	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

func _execute_ai_city_management(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue

		# Build buildings if slots available and nothing in queue
		if city.get_available_building_slots() > 0 and city.build_queue.is_empty():
			var has_barracks := city.buildings.has(&"barracks")
			var has_market := city.buildings.has(&"market")
			var has_granary := city.buildings.has(&"granary")

			if not has_barracks:
				GameManager.city_system.start_building(city_id, &"barracks")
			elif not has_market:
				GameManager.city_system.start_building(city_id, &"market")
			elif not has_granary:
				GameManager.city_system.start_building(city_id, &"granary")
			elif city.level >= 2 and not city.buildings.has(&"walls"):
				GameManager.city_system.start_building(city_id, &"walls")
			elif city.level >= 3 and not city.buildings.has(&"armory"):
				GameManager.city_system.start_building(city_id, &"armory")

		# Recruit units if barracks and sufficient resources/pop
		if city.buildings.has(&"barracks") and city.recruit_queue.is_empty() and city.population > 150:
			# Find the faction's strongest available unit
			var best_unit_id: StringName = &""
			var best_attack := 0
			for building_id in city.buildings:
				var building: BuildingData = DataManager.get_building(building_id)
				if building == null:
					continue
				for uid in building.unlocks_units:
					var udata := DataManager.get_unit(uid)
					if udata and udata.faction_id == faction_id and udata.attack > best_attack:
						best_attack = udata.attack
						best_unit_id = uid

			if best_unit_id != &"":
				GameManager.city_system.start_recruitment(city_id, best_unit_id)

func _find_nearest_player_army_hex(from: Vector2i, ai_faction: StringName) -> Vector2i:
	var player_id := GameManager.state.player_faction_id
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id:
			var dist := HexHelper.hex_distance(from, army.hex_pos)
			if dist < best_dist:
				best_dist = dist
				best_hex = army.hex_pos

	return best_hex

func _find_nearest_player_region_hex(from: Vector2i) -> Vector2i:
	var player_id := GameManager.state.player_faction_id
	var best_hex := Vector2i(-1, -1)
	var best_dist := 9999

	for region_id in DataManager.regions:
		var owner := GameManager.state.get_region_owner(region_id)
		if owner == player_id:
			var center := MapGenerator.get_region_center(region_id)
			var dist := HexHelper.hex_distance(from, center)
			if dist < best_dist:
				best_dist = dist
				best_hex = center

	return best_hex

func get_current_faction() -> StringName:
	if current_faction_index < faction_order.size():
		return faction_order[current_faction_index]
	return &""

# ── Healing & Replenishment ──────────────────────────────────

func _heal_armies_in_settlements(faction_id: StringName) -> void:
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue

		var city_at := GameManager.city_system.get_city_at_hex(army.hex_pos)
		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)

		if city_at and city_at.faction_id == faction_id:
			# In friendly settlement: heal 15% max HP + replenish 1 soldier
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.15)
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)
				# Replenish soldiers for squad units
				if unit_data.squad_size > 1 and unit_data.hp_per_soldier > 0:
					if unit.current_hp < unit_data.max_hp:
						unit.current_hp = mini(unit.current_hp + unit_data.hp_per_soldier, unit_data.max_hp)
		elif tile and tile.owner_faction == faction_id:
			# In friendly territory (not settlement): heal 5% max HP only
			for unit in army.units:
				var unit_data := DataManager.get_unit(unit.unit_data_id)
				if unit_data == null:
					continue
				var heal_amount := int(unit_data.max_hp * 0.05)
				unit.current_hp = mini(unit.current_hp + heal_amount, unit_data.max_hp)

# ── Gladehost AI (Patrol) ───────────────────────────────────

var _gladehost_waypoints: Dictionary = {} # army_id -> {waypoints: Array, index: int}

func _execute_gladehost_ai(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Build or retrieve patrol waypoints
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
				return
			if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
				return

	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

func _build_gladehost_patrol(faction_id: StringName) -> Array:
	var waypoints: Array = []
	# Get settlement positions
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				waypoints.append(city.hex_pos)

	# Add border tiles
	var borders := _get_faction_border_tiles(faction_id)
	if borders.size() > 0:
		# Pick a few spread-out border points
		var step := maxi(1, borders.size() / 3)
		for i in range(0, borders.size(), step):
			waypoints.append(borders[i])

	return waypoints

# ── Tainted Jade AI (Guard & Attack) ────────────────────────

var _jade_patrol_index: Dictionary = {} # army_id -> int

func _execute_tainted_jade_ai(faction_id: StringName) -> void:
	var armies := GameManager.get_faction_armies(faction_id)
	for army in armies:
		if army.movement_remaining <= 0:
			continue

		# Check for intruders within 3 hex tiles of any owned tile
		var intruder := _find_nearest_intruder(faction_id, 3)
		if intruder != Vector2i(-1, -1):
			# Attack intruder
			var path := GameManager.movement_system.find_path(
				army.hex_pos, intruder, faction_id, INF)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					return
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return
		else:
			# Patrol border
			var borders := _get_faction_border_tiles(faction_id)
			if borders.is_empty():
				continue
			if not _jade_patrol_index.has(army.army_id):
				_jade_patrol_index[army.army_id] = 0
			var idx: int = _jade_patrol_index[army.army_id]
			var target: Vector2i = borders[idx % borders.size()]
			if army.hex_pos == target or HexHelper.hex_distance(army.hex_pos, target) <= 1:
				idx = (idx + 1) % borders.size()
				_jade_patrol_index[army.army_id] = idx
				target = borders[idx]

			var path := GameManager.movement_system.find_path(
				army.hex_pos, target, faction_id, INF)
			if path.size() > 0:
				GameManager.move_army_along_path(army.army_id, path)
				if not GameManager.state.armies.has(army.army_id):
					_jade_patrol_index.erase(army.army_id)
					return
				if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
					return

	await get_tree().create_timer(0.5).timeout
	_end_current_faction_turn()

func _find_nearest_intruder(faction_id: StringName, range_limit: int) -> Vector2i:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return Vector2i(-1, -1)

	# Build a list of owned region centers for faster proximity check
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
		# Check if this army is near any owned region center (within range_limit + region radius)
		var tile := hex_map.get_tile(army.hex_pos)
		if tile and tile.owner_faction == faction_id:
			# Army is directly on our territory
			if best_dist > 0:
				best_dist = 0
				best_hex = army.hex_pos
			continue
		# Check distance to nearest owned region center
		for center in owned_centers:
			var d := HexHelper.hex_distance(army.hex_pos, center)
			if d <= range_limit + 5 and d < best_dist:
				best_dist = d
				best_hex = army.hex_pos

	if best_dist <= range_limit + 5:
		return best_hex
	return Vector2i(-1, -1)

# ── Shared AI Helpers ────────────────────────────────────────

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
