class_name CitySystem
extends RefCounted

func process_turn(faction_id: StringName) -> void:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue

		# Skip income/growth for cities under siege
		if not city.is_under_siege:
			_generate_income(city, faction_id)
			_add_growth(city)
			_check_level_up(city)

		_process_build_queue(city)
		_process_recruit_queue(city, faction_id)

	_process_sieges(faction_id)
	_deduct_upkeep(faction_id)

func _generate_income(city: CityState, faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	var income := calculate_city_income(city)
	for res_type in income:
		if fs.resources.has(res_type):
			fs.resources[res_type] += income[res_type]
		else:
			fs.resources[res_type] = income[res_type]

func calculate_city_income(city: CityState) -> Dictionary:
	var region: RegionData = DataManager.get_region(city.region_id)
	if region == null:
		return {}

	# Population multiplier: base_income * (population / 100.0), capped at level * 1.0
	var pop_mult := minf(float(city.population) / 100.0, float(city.level))

	var income: Dictionary = {}

	# Base region income scaled by population
	for res_type in region.base_income:
		income[res_type] = int(region.base_income[res_type] * pop_mult)

	# Building bonuses (flat, not scaled by pop)
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		for res_type in building.income_bonus:
			if income.has(res_type):
				income[res_type] += building.income_bonus[res_type]
			else:
				income[res_type] = building.income_bonus[res_type]

	return income

func _add_growth(city: CityState) -> void:
	var growth := calculate_growth(city)
	city.growth_points += growth
	city.population += growth

func calculate_growth(city: CityState) -> int:
	var base_growth := 5
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building:
			base_growth += building.population_growth_bonus
	return base_growth

func _check_level_up(city: CityState) -> void:
	var threshold := city.get_growth_threshold()
	if threshold < 0:
		return # already max level
	if city.growth_points >= threshold:
		city.level = mini(city.level + 1, 5)
		city.growth_points -= threshold
		# Grant settlement founding ability on capital level-up
		if city.is_capital:
			city.can_found_settlement = true

func _process_build_queue(city: CityState) -> void:
	if city.build_queue.is_empty():
		return

	var item: Dictionary = city.build_queue[0]
	item.turns_remaining -= 1
	if item.turns_remaining <= 0:
		city.buildings.append(item.building_id)
		city.build_queue.remove_at(0)
		EventBus.building_completed.emit(city.city_id, item.building_id)

func _process_recruit_queue(city: CityState, faction_id: StringName) -> void:
	if city.recruit_queue.is_empty():
		return

	var item: Dictionary = city.recruit_queue[0]
	item.turns_remaining -= 1
	if item.turns_remaining <= 0:
		var unit_data_id: StringName = item.unit_data_id
		city.recruit_queue.remove_at(0)
		_spawn_recruited_unit(city, unit_data_id, faction_id)

func _spawn_recruited_unit(city: CityState, unit_data_id: StringName, faction_id: StringName) -> void:
	var unit_data := DataManager.get_unit(unit_data_id)
	if unit_data == null:
		return

	# Check if there's already a friendly army at the city hex
	var existing_army: ArmyState = null
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.hex_pos == city.hex_pos and army.faction_id == faction_id:
			existing_army = army
			break

	var instance := UnitInstance.new()
	instance.init_from_data(unit_data, GameManager.state.generate_id())

	if existing_army:
		existing_army.units.append(instance)
		EventBus.unit_recruited.emit(city.city_id, unit_data_id, existing_army.army_id)
	else:
		# Create new army at capital
		var army := ArmyState.new()
		army.army_id = GameManager.state.generate_id()
		army.faction_id = faction_id
		army.hex_pos = city.hex_pos
		army.units.append(instance)
		army.movement_remaining = army.get_max_movement()
		GameManager.state.armies[army.army_id] = army
		EventBus.unit_recruited.emit(city.city_id, unit_data_id, army.army_id)

func _process_sieges(faction_id: StringName) -> void:
	# Process sieges where this faction's cities are being besieged
	# (siege_turns increment at the start of the besieging faction's turn)
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not city.is_under_siege:
			continue
		if city.siege_faction != faction_id:
			continue

		city.siege_turns += 1
		if city.siege_turns >= 2:
			_capture_city(city)

func _capture_city(city: CityState) -> void:
	var old_owner := city.faction_id
	var new_owner := city.siege_faction

	# Remove from old owner's city list
	var old_fs: FactionState = GameManager.state.faction_states.get(old_owner)
	if old_fs:
		old_fs.owned_cities.erase(city.city_id)

	# Change city ownership
	city.faction_id = new_owner
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0

	# Add to new owner's city list
	var new_fs: FactionState = GameManager.state.faction_states.get(new_owner)
	if new_fs and not new_fs.owned_cities.has(city.city_id):
		new_fs.owned_cities.append(city.city_id)

	# Change region ownership
	GameManager.change_region_owner(city.region_id, new_owner)

	EventBus.city_captured.emit(city.city_id, old_owner, new_owner)

func _deduct_upkeep(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue
		for unit in army.units:
			var unit_data := DataManager.get_unit(unit.unit_data_id)
			if unit_data == null:
				continue
			for res_type in unit_data.upkeep_cost:
				if fs.resources.has(res_type):
					fs.resources[res_type] -= unit_data.upkeep_cost[res_type]

# ── Public API ────────────────────────────────────────────────

func start_building(city_id: StringName, building_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false

	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return false

	# Validate
	if city.get_available_building_slots() <= 0:
		return false
	if city.level < building.required_capital_level:
		return false
	if city.buildings.has(building_id):
		return false
	# Check if already in queue
	for item in city.build_queue:
		if item.building_id == building_id:
			return false

	# Check and deduct cost
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	if not _can_afford(fs, building.build_cost):
		return false
	_deduct_cost(fs, building.build_cost)

	city.build_queue.append({building_id = building_id, turns_remaining = building.build_time})
	return true

func start_recruitment(city_id: StringName, unit_data_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false

	if not city.can_recruit(unit_data_id):
		return false

	var unit_data := DataManager.get_unit(unit_data_id)
	if unit_data == null:
		return false

	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false

	# Check recruit cost
	if not _can_afford(fs, unit_data.recruit_cost):
		return false

	# Check population
	if city.population < unit_data.squad_size:
		return false

	# Deduct
	_deduct_cost(fs, unit_data.recruit_cost)
	city.population -= unit_data.squad_size

	# Calculate recruit time with building bonuses
	var recruit_time := unit_data.recruit_time
	for bid in city.buildings:
		var b: BuildingData = DataManager.get_building(bid)
		if b:
			recruit_time -= b.recruit_speed_bonus
	recruit_time = maxi(1, recruit_time)

	city.recruit_queue.append({unit_data_id = unit_data_id, turns_remaining = recruit_time})
	return true

func _can_afford(fs: FactionState, cost: Dictionary) -> bool:
	for res_type in cost:
		var have: int = fs.resources.get(res_type, 0)
		if have < cost[res_type]:
			return false
	return true

func _deduct_cost(fs: FactionState, cost: Dictionary) -> void:
	for res_type in cost:
		if fs.resources.has(res_type):
			fs.resources[res_type] -= cost[res_type]

# ── Siege helpers ─────────────────────────────────────────────

func start_siege(city_id: StringName, attacking_faction: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or city.faction_id == attacking_faction:
		return
	city.is_under_siege = true
	city.siege_faction = attacking_faction
	city.siege_turns = 0
	EventBus.siege_started.emit(city_id, attacking_faction)

func break_siege(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or not city.is_under_siege:
		return
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0
	EventBus.siege_broken.emit(city_id)

func get_city_at_hex(hex_pos: Vector2i) -> CityState:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.hex_pos == hex_pos:
			return city
	return null

# ── Settlement founding ───────────────────────────────────────

const TILE_INCOME := {
	Enums.TerrainType.PLAINS:    {0: 2, 3: 3, 5: 0},
	Enums.TerrainType.FOREST:    {0: 1, 3: 1, 5: 3},
	Enums.TerrainType.MOUNTAINS: {0: 1, 1: 3, 5: 0},
	Enums.TerrainType.DESERT:    {0: 3, 3: 0, 5: 0},
	Enums.TerrainType.JUNGLE:    {0: 1, 3: 2, 5: 2},
	Enums.TerrainType.SWAMP:     {0: 1, 3: 2, 5: 1},
	Enums.TerrainType.COAST:     {0: 2, 3: 2, 5: 0},
	Enums.TerrainType.TUNDRA:    {0: 1, 3: 1, 1: 1},
}

const SETTLEMENT_SPHERE_RADIUS := 2

func is_in_settlement_sphere(hex_pos: Vector2i) -> bool:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if HexHelper.hex_distance(hex_pos, city.hex_pos) <= SETTLEMENT_SPHERE_RADIUS:
			return true
	return false

func get_valid_settlement_tiles(faction_id: StringName, region_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return result
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id != region_id:
			continue
		if tile.owner_faction != faction_id:
			continue
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if is_in_settlement_sphere(coord):
			continue
		result.append(coord)
	return result

func calculate_settlement_income_preview(hex_pos: Vector2i) -> Dictionary:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return {}
	var tile := hex_map.get_tile(hex_pos)
	if tile == null:
		return {}

	var income: Dictionary = {}
	# Base income from center tile
	var base: Dictionary = TILE_INCOME.get(tile.terrain, {})
	for res_type in base:
		income[res_type] = base[res_type]

	# Adjacency bonus from surrounding tiles within 2 radius
	var center_terrain: int = tile.terrain
	for r in range(1, SETTLEMENT_SPHERE_RADIUS + 1):
		var ring := _get_hex_ring(hex_pos, r)
		for ring_coord in ring:
			if not HexHelper.is_valid(ring_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var rtile := hex_map.get_tile(ring_coord)
			if rtile == null or rtile.terrain == Enums.TerrainType.WATER:
				continue
			if is_in_settlement_sphere(ring_coord):
				continue
			var adj_income: Dictionary = TILE_INCOME.get(rtile.terrain, {})
			# If same terrain as center, +1 to primary resource
			if rtile.terrain == center_terrain:
				var primary_res := _get_primary_resource(rtile.terrain)
				if primary_res >= 0:
					income[primary_res] = income.get(primary_res, 0) + 1
			else:
				# Small contribution from different terrain
				for res_type in adj_income:
					if adj_income[res_type] > 0:
						income[res_type] = income.get(res_type, 0) + max(1, adj_income[res_type] / 3)
	return income

func _get_primary_resource(terrain: Enums.TerrainType) -> int:
	match terrain:
		Enums.TerrainType.PLAINS: return 3  # Food
		Enums.TerrainType.FOREST: return 5  # Wood
		Enums.TerrainType.MOUNTAINS: return 1  # Iron
		Enums.TerrainType.DESERT: return 0  # Gold
		Enums.TerrainType.JUNGLE: return 5  # Wood
		Enums.TerrainType.SWAMP: return 3  # Food
		Enums.TerrainType.COAST: return 0  # Gold
		Enums.TerrainType.TUNDRA: return 1  # Iron
	return -1

func _get_hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	if radius <= 0:
		results.append(center)
		return results
	# Walk around the ring using cube coordinates
	var cube := HexHelper.offset_to_cube(center.x, center.y)
	# Start at the "south-west" direction scaled by radius
	cube = Vector3i(cube.x - radius, cube.y + radius, cube.z)
	# 6 directions in cube space
	var dirs := [
		Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1),
		Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1),
	]
	for d in 6:
		for _s in radius:
			var offset := HexHelper.cube_to_offset(cube)
			if HexHelper.is_valid(offset, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				results.append(offset)
			cube = cube + dirs[d]
	return results
