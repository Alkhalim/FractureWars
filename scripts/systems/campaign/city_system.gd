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

		_process_build_queue(city)
		_process_recruit_queue(city, faction_id)
		_process_upgrade(city)

		# Loyalty update (capitals compute; settlements inherit)
		_update_loyalty(city, faction_id)
		if city.turns_since_capture >= 0:
			city.turns_since_capture += 1
		if LoyaltySystem.check_revolt(city):
			_trigger_revolt(city, faction_id)

	_process_sieges(faction_id)
	_deduct_upkeep(faction_id)

func _generate_income(city: CityState, faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	var income := calculate_city_income(city)

	# Apply social class bonuses
	var pcts := LoyaltySystem.calculate_class_percentages(city, faction_id)
	income = LoyaltySystem.apply_class_bonuses(income, pcts)

	# Apply loyalty income multiplier
	var loyalty_mult := LoyaltySystem.get_loyalty_multiplier(city.loyalty)
	if loyalty_mult < 1.0:
		for res_type in income:
			income[res_type] = int(float(income[res_type]) * loyalty_mult)

	# Apply research percentage bonuses
	var research_effects := GameManager.research_system.get_research_effects(faction_id)
	var gold_pct: int = research_effects.get("income_gold_pct", 0)
	var food_pct: int = research_effects.get("income_food_pct", 0)
	if gold_pct != 0 and income.has(Enums.ResourceType.GOLD):
		income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * gold_pct / 100.0)
	if food_pct != 0 and income.has(Enums.ResourceType.FOOD):
		income[Enums.ResourceType.FOOD] += int(income[Enums.ResourceType.FOOD] * food_pct / 100.0)

	# Apply senate majority income effects
	var senate_effects := GameManager.policy_system.get_senate_majority_effects(faction_id)
	var senate_gold_pct: int = senate_effects.get("gold_income_pct", 0)
	var senate_tech_pct: int = senate_effects.get("tech_income_pct", 0)
	var senate_iron_pct: int = senate_effects.get("iron_income_pct", 0)
	var senate_wood_pct: int = senate_effects.get("wood_income_pct", 0)
	if senate_gold_pct != 0 and income.has(Enums.ResourceType.GOLD):
		income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * senate_gold_pct / 100.0)
	if senate_tech_pct != 0 and income.has(Enums.ResourceType.TECHNOLOGY):
		income[Enums.ResourceType.TECHNOLOGY] += int(income[Enums.ResourceType.TECHNOLOGY] * senate_tech_pct / 100.0)
	if senate_iron_pct != 0 and income.has(Enums.ResourceType.IRON):
		income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * senate_iron_pct / 100.0)
	if senate_wood_pct != 0 and income.has(Enums.ResourceType.WOOD):
		income[Enums.ResourceType.WOOD] += int(income[Enums.ResourceType.WOOD] * senate_wood_pct / 100.0)

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
	# Low population malus: below 50 pop, production suffers
	if city.population < 50:
		pop_mult *= maxf(0.1, float(city.population) / 50.0)

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

	# Commander influence: friendly commanders within influence_radius boost gold
	var cmd_gold_bonus := _get_commander_gold_bonus(city)
	if cmd_gold_bonus > 0:
		income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + cmd_gold_bonus

	return income

func _add_growth(city: CityState) -> void:
	var growth := calculate_growth(city)
	city.growth_points += growth
	city.population = maxi(0, city.population + growth)

func calculate_growth(city: CityState) -> int:
	var base_growth := 5
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building:
			base_growth += building.population_growth_bonus
	# Commander influence: friendly commanders within radius boost growth
	base_growth += _get_commander_growth_bonus(city)
	# Loyalty penalty on population growth
	var loyalty_growth_mult := _get_loyalty_growth_multiplier(city.loyalty)
	if loyalty_growth_mult < 1.0:
		base_growth = int(float(base_growth) * loyalty_growth_mult)
	return base_growth

static func _get_loyalty_growth_multiplier(loyalty_value: int) -> float:
	if loyalty_value >= 50:
		return 1.0
	elif loyalty_value >= 25:
		return 0.85
	elif loyalty_value >= 0:
		return 0.6
	elif loyalty_value >= -25:
		return 0.3
	elif loyalty_value >= -50:
		return 0.1
	else:
		return 0.0  # Active revolt: no growth

func _process_upgrade(city: CityState) -> void:
	if city.upgrade_turns_remaining <= 0:
		return
	city.upgrade_turns_remaining -= 1
	if city.upgrade_turns_remaining <= 0:
		city.level = mini(city.level + 1, 5)
		# Grant settlement founding ability on capital level-up
		if city.is_capital:
			city.can_found_settlement = true

func can_start_upgrade(city: CityState) -> bool:
	if not city.is_upgrade_available():
		return false
	var cost := city.get_upgrade_cost()
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	for res_type in cost:
		if fs.resources.get(res_type, 0) < cost[res_type]:
			return false
	return true

func start_upgrade(city_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or not can_start_upgrade(city):
		return false
	var cost := city.get_upgrade_cost()
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	# Deduct resources
	for res_type in cost:
		fs.resources[res_type] = fs.resources.get(res_type, 0) - cost[res_type]
	city.upgrade_turns_remaining = city.get_upgrade_time()
	return true

func _process_build_queue(city: CityState) -> void:
	if city.build_queue.is_empty():
		return

	var item: Dictionary = city.build_queue[0]
	item.turns_remaining -= 1
	if item.turns_remaining <= 0:
		var building_id: StringName = item.building_id
		var building: BuildingData = DataManager.get_building(building_id)
		# Handle upgrades: remove the old building before adding the new one
		if building and building.upgrades_from != &"":
			city.buildings.erase(building.upgrades_from)
		city.buildings.append(building_id)
		city.build_queue.remove_at(0)
		EventBus.building_completed.emit(city.city_id, building_id)

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
	var was_capital := city.is_capital

	# Remove from old owner's city list
	var old_fs: FactionState = GameManager.state.faction_states.get(old_owner)
	if old_fs:
		old_fs.owned_cities.erase(city.city_id)

	# Change city ownership
	city.faction_id = new_owner
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0
	city.is_capital = false
	city.can_found_settlement = false
	city.loyalty = 0
	city.class_loyalty = {
		"peasants": 0, "artisans": 0, "scholars": 0, "nobles": 0, "captives": 0
	}
	city.turns_since_capture = 0

	# Add to new owner's city list
	var new_fs: FactionState = GameManager.state.faction_states.get(new_owner)
	if new_fs and not new_fs.owned_cities.has(city.city_id):
		new_fs.owned_cities.append(city.city_id)

	# Change region ownership
	GameManager.change_region_owner(city.region_id, new_owner)

	EventBus.city_captured.emit(city.city_id, old_owner, new_owner)

	# If old owner lost their capital, promote their largest remaining city
	if was_capital and old_fs and old_fs.owned_cities.size() > 0:
		var best_city: CityState = null
		var best_pop := -1
		for cid in old_fs.owned_cities:
			var c: CityState = GameManager.state.cities.get(cid)
			if c and c.population > best_pop:
				best_pop = c.population
				best_city = c
		if best_city:
			best_city.is_capital = true

	# If old owner has no cities left, mark defeated
	if old_fs and old_fs.owned_cities.is_empty():
		old_fs.is_defeated = true

func _deduct_upkeep(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != faction_id:
			continue
		if army.is_garrison:
			continue # garrison armies don't cost upkeep
		# Unit upkeep
		for unit in army.units:
			var unit_data := DataManager.get_unit(unit.unit_data_id)
			if unit_data == null:
				continue
			for res_type in unit_data.upkeep_cost:
				if fs.resources.has(res_type):
					fs.resources[res_type] -= unit_data.upkeep_cost[res_type]
		# Commander upkeep (only while assigned to army)
		if army.commander != null:
			var level_mult := 1.0 + (army.commander.level - 1) * 0.5
			for res_type in CommanderSystem.COMMANDER_UPKEEP:
				var cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				if fs.resources.has(res_type):
					fs.resources[res_type] -= cost

# ── Loyalty helpers ───────────────────────────────────────────

func _update_loyalty(city: CityState, faction_id: StringName) -> void:
	if not city.is_capital:
		var capital := _find_province_capital(city.region_id, faction_id)
		if capital:
			city.class_loyalty = capital.class_loyalty.duplicate()
			city.loyalty = capital.loyalty
		return
	# Update each class's loyalty
	var deltas := LoyaltySystem.calculate_class_loyalty_deltas(city, faction_id)
	for cls in city.class_loyalty:
		if cls == "captives":
			city.class_loyalty[cls] = 0
		else:
			city.class_loyalty[cls] = clampi(city.class_loyalty[cls] + deltas.get(cls, 0), -100, 100)
	# Compute weighted average as the province loyalty
	city.loyalty = LoyaltySystem.calculate_province_loyalty(city, faction_id)

func _find_province_capital(region_id: StringName, faction_id: StringName) -> CityState:
	for city_id in GameManager.state.cities:
		var c: CityState = GameManager.state.cities[city_id]
		if c.region_id == region_id and c.faction_id == faction_id and c.is_capital:
			return c
	return null

func _trigger_revolt(city: CityState, faction_id: StringName) -> void:
	# Spawn rebel army at city hex
	var rebel_army := ArmyState.new()
	rebel_army.army_id = GameManager.state.generate_id()
	rebel_army.faction_id = &"rebels"
	rebel_army.hex_pos = city.hex_pos

	# Composition scales with population (1-4 units)
	var num_units := clampi(city.population / 75, 1, 4)
	# Use a generic rebel unit - pick the first available unit as a template
	var rebel_unit_id := &"warband_raider"  # Fallback rebel unit
	for _i in num_units:
		var unit_data := DataManager.get_unit(rebel_unit_id)
		if unit_data:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, GameManager.state.generate_id())
			rebel_army.units.append(instance)

	rebel_army.movement_remaining = 0.0
	GameManager.state.armies[rebel_army.army_id] = rebel_army

	# Put city under siege by rebels
	city.is_under_siege = true
	city.siege_faction = &"rebels"
	city.siege_turns = 0

	# Reduce population by 10%
	city.population = maxi(10, int(city.population * 0.9))

	EventBus.revolt_triggered.emit(city.city_id, faction_id)

# ── Terrain helpers ───────────────────────────────────────────

func _has_adjacent_terrain(city: CityState, terrain: int) -> bool:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return false
	for neighbor in HexHelper.get_neighbors(city.hex_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(neighbor)
		if tile and tile.terrain == terrain:
			return true
	return false

# ── Public API ────────────────────────────────────────────────

func get_available_buildings(city: CityState) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for building_id in DataManager.buildings:
		var building: BuildingData = DataManager.buildings[building_id]
		# Skip faction-specific buildings that don't belong to this city's faction
		if building.faction_id != &"" and building.faction_id != city.faction_id:
			continue
		# Skip buildings already owned
		if city.buildings.has(building_id):
			continue
		# Skip buildings already in queue
		var in_queue := false
		for item in city.build_queue:
			if item.building_id == building_id:
				in_queue = true
				break
		if in_queue:
			continue
		# Skip if city level too low
		if city.level < building.required_capital_level:
			continue
		# Skip if terrain requirement not met
		if building.required_terrain >= 0:
			if not _has_adjacent_terrain(city, building.required_terrain):
				continue
		if building.upgrades_from == &"":
			# Base building: city must not already have it
			result.append(building)
		else:
			# Upgrade building: city must have the prerequisite
			if city.buildings.has(building.upgrades_from):
				result.append(building)
	return result

func start_building(city_id: StringName, building_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false

	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return false

	# Validate
	var is_upgrade := building.upgrades_from != &""
	if is_upgrade:
		# Upgrade: must have prerequisite, doesn't consume a new slot
		if not city.buildings.has(building.upgrades_from):
			return false
	else:
		# New building: needs a free slot
		if city.get_available_building_slots() <= 0:
			return false
	if city.level < building.required_capital_level:
		return false
	if building.required_terrain >= 0:
		if not _has_adjacent_terrain(city, building.required_terrain):
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
	var pop_cost := unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
	if city.population < pop_cost:
		return false

	# Deduct
	_deduct_cost(fs, unit_data.recruit_cost)
	city.population -= pop_cost

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

# ── Garrison ─────────────────────────────────────────────────

# Garrison units spawned when a city is attacked with no defending army
# {level: [{unit_id, count}]}
const GARRISON_BY_LEVEL := {
	1: [{unit_id = &"levy_conscripts", count = 1}],
	2: [{unit_id = &"levy_conscripts", count = 1}, {unit_id = &"legionary", count = 1}],
	3: [{unit_id = &"levy_conscripts", count = 2}, {unit_id = &"legionary", count = 1}],
	4: [{unit_id = &"levy_conscripts", count = 2}, {unit_id = &"legionary", count = 2}],
	5: [{unit_id = &"levy_conscripts", count = 3}, {unit_id = &"legionary", count = 2}],
}

func create_garrison_army(city: CityState) -> ArmyState:
	var garrison_def: Array = GARRISON_BY_LEVEL.get(city.level, GARRISON_BY_LEVEL[1])
	var army := ArmyState.new()
	army.army_id = GameManager.state.generate_id()
	army.faction_id = city.faction_id
	army.hex_pos = city.hex_pos
	army.movement_remaining = 0.0
	army.has_moved = true # garrison doesn't move
	army.is_garrison = true

	for entry in garrison_def:
		var uid: StringName = entry.unit_id
		var unit_data := DataManager.get_unit(uid)
		if unit_data == null:
			continue
		for i in entry.count:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, GameManager.state.generate_id())
			army.units.append(instance)

	return army

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

const SETTLEMENT_FOUNDING_COST := {
	Enums.ResourceType.GOLD: 80,
	Enums.ResourceType.WOOD: 40,
	Enums.ResourceType.FOOD: 30,
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

# ── Commander influence helpers ───────────────────────────────

func _get_nearby_friendly_commanders(city: CityState) -> Array[CommanderState]:
	var result: Array[CommanderState] = []
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != city.faction_id:
			continue
		if army.commander == null:
			continue
		if HexHelper.hex_distance(army.hex_pos, city.hex_pos) <= army.commander.influence_radius:
			result.append(army.commander)
	return result

func _get_commander_gold_bonus(city: CityState) -> int:
	var bonus := 0
	for commander in _get_nearby_friendly_commanders(city):
		var effects := CommanderSystem.get_commander_city_effects(commander, true)
		bonus += effects.get("city_gold_bonus", 0)
	return bonus

func _get_commander_growth_bonus(city: CityState) -> int:
	var bonus := 0
	for commander in _get_nearby_friendly_commanders(city):
		var effects := CommanderSystem.get_commander_city_effects(commander, true)
		bonus += effects.get("city_growth_bonus", 0)
	return bonus

func _get_commander_defense_bonus(city: CityState) -> int:
	var bonus := 0
	for commander in _get_nearby_friendly_commanders(city):
		var effects := CommanderSystem.get_commander_city_effects(commander, true)
		bonus += effects.get("city_defense_bonus", 0)
	return bonus

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
