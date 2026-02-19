class_name CitySystem
extends RefCounted

func process_turn(faction_id: StringName) -> void:
	# Calculate projected food income for growth modifier
	var food_income := _calculate_food_income(faction_id)

	# Province-shared growth: process once per province, not per city
	var processed_provinces: Dictionary = {}  # region_id -> true

	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue

		# Skip income/growth for cities under siege
		if not city.is_under_siege:
			_generate_income(city, faction_id)

		# Province growth: only calculate once per province, apply to capital
		if not city.is_under_siege and not processed_provinces.has(city.region_id):
			processed_provinces[city.region_id] = true
			_add_province_growth(city.region_id, faction_id, food_income)

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

	# Starvation: if faction food reserves are negative, cities lose population
	_apply_starvation(faction_id)

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

	# Apply senate majority income effects (Empire only — other factions have no senate)
	if faction_id == &"empire":
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

	# Faction-specific income modifiers
	_apply_faction_income_modifier(income, faction_id, fs, city)

	# Population food consumption: larger populations eat more
	var province_pop := get_province_population(city)
	var food_consumed := province_pop / 10
	if food_consumed > 0 and income.has(Enums.ResourceType.FOOD):
		income[Enums.ResourceType.FOOD] -= food_consumed
	elif food_consumed > 0:
		income[Enums.ResourceType.FOOD] = -food_consumed

	for res_type in income:
		if fs.resources.has(res_type):
			fs.resources[res_type] += income[res_type]
		else:
			fs.resources[res_type] = income[res_type]

func get_province_population(city: CityState) -> int:
	return LoyaltySystem.get_province_population(city.region_id, city.faction_id)

func calculate_city_income(city: CityState) -> Dictionary:
	var region: RegionData = DataManager.get_region(city.region_id)
	if region == null:
		return {}

	# Province-shared population: use total province pop for multiplier
	var province_pop := get_province_population(city)
	var pop_mult := minf(float(province_pop) / 100.0, float(city.level))
	# Low population malus: below 50 pop, production suffers
	if province_pop < 50:
		pop_mult *= maxf(0.1, float(province_pop) / 50.0)

	var income: Dictionary = {}

	# Base region income scaled by population
	for res_type in region.base_income:
		income[res_type] = int(region.base_income[res_type] * pop_mult)

	# Building bonuses — slightly scaled by population (except food)
	# At pop 100: no bonus. At pop 200: +10%. At pop 500: +40%.
	var building_pop_mult := maxf(1.0, 1.0 + (float(province_pop) - 100.0) * 0.001)
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		for res_type in building.income_bonus:
			var bonus: int = building.income_bonus[res_type]
			# Food production stays flat — growth is handled separately
			if res_type != Enums.ResourceType.FOOD:
				bonus = int(float(bonus) * building_pop_mult)
			if income.has(res_type):
				income[res_type] += bonus
			else:
				income[res_type] = bonus

	# Capital bonus: +5 gold
	if city.is_capital:
		income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + 5

	# Commander influence: friendly commanders within influence_radius boost gold
	var cmd_gold_bonus := _get_commander_gold_bonus(city)
	if cmd_gold_bonus > 0:
		income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + cmd_gold_bonus

	return income

func _add_province_growth(region_id: StringName, faction_id: StringName, food_income: int = 0) -> void:
	var growth := calculate_province_growth(region_id, faction_id)
	# Apply growth to the capital city (or first city if no capital)
	var target_city: CityState = null
	for city in LoyaltySystem.get_province_cities(region_id, faction_id):
		if city.is_capital:
			target_city = city
			break
		if target_city == null:
			target_city = city
	if target_city == null:
		return

	# Negative food income slows growth (reaches 0 at -40 food income)
	if food_income < 0:
		var penalty := clampf(1.0 + float(food_income) / 40.0, 0.0, 1.0)
		growth = int(float(growth) * penalty)

	# Apply growth
	target_city.growth_points += growth
	target_city.population = maxi(0, target_city.population + growth)

	# Population cap: 150% of next level-up threshold — decay excess
	var pop_cap := target_city.get_population_cap()
	if target_city.population > pop_cap:
		var excess := target_city.population - pop_cap
		var decay := maxi(1, excess / 5)  # Lose 20% of excess per turn
		target_city.population = maxi(pop_cap, target_city.population - decay)

func calculate_province_growth(region_id: StringName, faction_id: StringName) -> int:
	var base_growth := 5
	var best_loyalty := 0
	var city_count := 0
	for city in LoyaltySystem.get_province_cities(region_id, faction_id):
		if city.is_under_siege:
			continue
		city_count += 1
		# Sum growth bonuses from all buildings in all province cities
		for building_id in city.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building:
				base_growth += building.population_growth_bonus
		# Commander influence from any city in the province
		base_growth += _get_commander_growth_bonus(city)
		if city.loyalty > best_loyalty:
			best_loyalty = city.loyalty
	# Loyalty penalty based on best city's loyalty
	var loyalty_growth_mult := _get_loyalty_growth_multiplier(best_loyalty)
	if loyalty_growth_mult < 1.0:
		base_growth = int(float(base_growth) * loyalty_growth_mult)
	return base_growth

func calculate_growth(city: CityState) -> int:
	# Legacy per-city growth (used by UI for projection)
	return calculate_province_growth(city.region_id, city.faction_id)

func _calculate_food_income(faction_id: StringName) -> int:
	var total_food := 0
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id or city.is_under_siege:
			continue
		# Building food income
		for building_id in city.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building and building.income_bonus.has(Enums.ResourceType.FOOD):
				total_food += building.income_bonus[Enums.ResourceType.FOOD]
		# Region base food income
		var region: RegionData = DataManager.get_region(city.region_id)
		if region and region.base_income.has(Enums.ResourceType.FOOD):
			var province_pop := get_province_population(city)
			var pop_mult := minf(float(province_pop) / 100.0, float(city.level))
			total_food += int(region.base_income[Enums.ResourceType.FOOD] * pop_mult)
		# Food consumption
		var province_pop := get_province_population(city)
		total_food -= province_pop / 10
	return total_food

func _apply_starvation(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var food_total: int = fs.resources.get(Enums.ResourceType.FOOD, 0)
	if food_total >= 0:
		return
	# Distribute population loss across all cities proportional to deficit
	var faction_cities: Array[CityState] = []
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id:
			faction_cities.append(city)
	if faction_cities.is_empty():
		return
	# Lose population: severity scales with deficit magnitude
	var loss_per_city := maxi(1, absi(food_total) / (faction_cities.size() * 5))
	for city in faction_cities:
		city.population = maxi(10, city.population - loss_per_city)

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
	if city.upgrade_turns_remaining > 0:
		return false
	var threshold := city.get_growth_threshold()
	if threshold < 0:
		return false
	# Use province population for threshold check
	if get_province_population(city) < threshold:
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
			# Transfer tile from old building to new one
			if city.building_tiles.has(building.upgrades_from):
				city.building_tiles[building_id] = city.building_tiles[building.upgrades_from]
				city.building_tiles.erase(building.upgrades_from)
		elif item.has("tile_pos"):
			city.building_tiles[building_id] = item.tile_pos
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

		# Jungle Traps: besieging armies take attrition damage each siege turn
		if city.buildings.has(&"jungle_traps"):
			for army_id in GameManager.state.armies:
				var army: ArmyState = GameManager.state.armies[army_id]
				if army.faction_id == faction_id and army.hex_pos == city.hex_pos:
					for unit in army.units:
						var ud := DataManager.get_unit(unit.unit_data_id)
						if ud:
							unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * 0.05))

		# Steppe Watchtower: extends siege time by 1 (requires 5 turns instead of 4)
		var siege_threshold := 4
		if city.buildings.has(&"steppe_watchtower"):
			siege_threshold = 5
		if city.siege_turns >= siege_threshold:
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
		# Terrain upkeep modifier (jungle/desert/wastes etc.)
		var terrain_mult := TurnManager.get_terrain_upkeep_modifier(army)
		# Unit upkeep
		for unit in army.units:
			var unit_data := DataManager.get_unit(unit.unit_data_id)
			if unit_data == null:
				continue
			for res_type in unit_data.upkeep_cost:
				if fs.resources.has(res_type):
					fs.resources[res_type] -= int(unit_data.upkeep_cost[res_type] * terrain_mult)
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

	# Composition scales with province population (1-4 units)
	var num_units := clampi(get_province_population(city) / 75, 1, 4)
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
	return get_valid_tiles_for_building_terrain(city, terrain).size() > 0

func get_valid_tiles_for_building_terrain(city: CityState, terrain: int) -> Array[Vector2i]:
	# Returns adjacent tiles that match the required terrain and are not occupied
	var result: Array[Vector2i] = []
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return result
	var occupied := city.get_occupied_tiles()
	for neighbor in HexHelper.get_neighbors(city.hex_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		if occupied.has(neighbor):
			continue
		var tile := hex_map.get_tile(neighbor)
		if tile == null:
			continue
		if terrain < 0 or tile.terrain == terrain:
			result.append(neighbor)
	return result

func get_valid_tiles_for_building(city: CityState, building: BuildingData) -> Array[Vector2i]:
	# For upgrades, use the same tile as the building being upgraded
	if building.upgrades_from != &"" and city.building_tiles.has(building.upgrades_from):
		return [city.building_tiles[building.upgrades_from] as Vector2i]
	return get_valid_tiles_for_building_terrain(city, building.required_terrain)

func get_free_adjacent_tiles(city: CityState) -> Array[Vector2i]:
	# All adjacent tiles not occupied by a building (any terrain)
	return get_valid_tiles_for_building_terrain(city, -1)

# ── Public API ────────────────────────────────────────────────

func get_available_buildings(city: CityState) -> Array[BuildingData]:
	# Build a set of all ancestor building IDs in chains already used by this city
	# e.g. if city has "imperial_granary" (upgrades_from "grain_fields"), "grain_fields" is used
	var used_chain_ancestors: Dictionary = {} # StringName -> true
	for owned_id in city.buildings:
		var b: BuildingData = DataManager.get_building(owned_id)
		if b == null:
			continue
		var ancestor_id := b.upgrades_from
		while ancestor_id != &"":
			used_chain_ancestors[ancestor_id] = true
			var ancestor: BuildingData = DataManager.get_building(ancestor_id)
			if ancestor == null:
				break
			ancestor_id = ancestor.upgrades_from
	for item in city.build_queue:
		var b: BuildingData = DataManager.get_building(item.building_id)
		if b == null:
			continue
		var ancestor_id := b.upgrades_from
		while ancestor_id != &"":
			used_chain_ancestors[ancestor_id] = true
			var ancestor: BuildingData = DataManager.get_building(ancestor_id)
			if ancestor == null:
				break
			ancestor_id = ancestor.upgrades_from

	var result: Array[BuildingData] = []
	for building_id in DataManager.buildings:
		var building: BuildingData = DataManager.buildings[building_id]
		# Skip faction-specific buildings that don't belong to this city's faction
		if building.faction_id != &"" and building.faction_id != city.faction_id:
			continue
		# Skip buildings already owned
		if city.buildings.has(building_id):
			continue
		# Skip buildings whose chain is already used (upgrade exists in city)
		if used_chain_ancestors.has(building_id):
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
		# Skip capital-only buildings in non-capital cities
		if building.requires_capital and not city.is_capital:
			continue
		# Skip if no valid adjacent tile available
		if get_valid_tiles_for_building(city, building).is_empty():
			continue
		if building.upgrades_from == &"":
			# Base building: needs a free slot
			if city.get_available_building_slots() <= 0:
				continue
			result.append(building)
		else:
			# Upgrade building: city must have the prerequisite
			if city.buildings.has(building.upgrades_from):
				result.append(building)
	return result

func start_building(city_id: StringName, building_id: StringName, tile_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false

	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return false

	# Validate
	var is_upgrade := building.upgrades_from != &""
	if is_upgrade:
		if not city.buildings.has(building.upgrades_from):
			return false
	else:
		if city.get_available_building_slots() <= 0:
			return false
	if city.level < building.required_capital_level:
		return false
	if building.requires_capital and not city.is_capital:
		return false
	if city.buildings.has(building_id):
		return false
	for item in city.build_queue:
		if item.building_id == building_id:
			return false

	# Validate tile placement
	var valid_tiles := get_valid_tiles_for_building(city, building)
	if valid_tiles.is_empty():
		return false
	# If no tile specified, auto-pick first valid tile (for AI)
	if tile_pos == Vector2i(-1, -1):
		tile_pos = valid_tiles[0]
	elif not valid_tiles.has(tile_pos):
		return false

	# Check and deduct cost
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	if not _can_afford(fs, building.build_cost):
		return false
	_deduct_cost(fs, building.build_cost)

	city.build_queue.append({building_id = building_id, turns_remaining = building.build_time, tile_pos = tile_pos})
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

	# Check province population (shared across all cities in province)
	var pop_cost := unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
	var province_pop := get_province_population(city)
	if province_pop < pop_cost:
		return false

	# Deduct resources and population from province (subtract from this city first, overflow to others)
	_deduct_cost(fs, unit_data.recruit_cost)
	_deduct_province_population(city, pop_cost)

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

func _deduct_province_population(city: CityState, amount: int) -> void:
	# Deduct population from the province pool, starting from the given city
	var remaining := amount
	# First deduct from this city
	var take := mini(remaining, city.population - 10)  # Keep at least 10
	if take > 0:
		city.population -= take
		remaining -= take
	# If still remaining, deduct from other cities in the province
	if remaining > 0:
		for other in LoyaltySystem.get_province_cities(city.region_id, city.faction_id):
			if other == city or remaining <= 0:
				continue
			take = mini(remaining, other.population - 10)
			if take > 0:
				other.population -= take
				remaining -= take

# ── Garrison ─────────────────────────────────────────────────

# Garrison units per faction: [militia_unit, regular_unit]
const GARRISON_UNITS := {
	&"empire": [&"levy_conscripts", &"legionary"],
	&"skulloath": [&"warband_raider", &"steppe_rider"],
	&"gladehost": [&"grove_warden", &"blade_dancer"],
	&"tainted_jade": [&"jade_fang", &"jungle_stalker"],
	&"shardhorde": [&"crystal_swarmling", &"shard_crawler"],
}

func _get_garrison_composition(city: CityState) -> Array:
	var units: Array = GARRISON_UNITS.get(city.faction_id, GARRISON_UNITS[&"empire"])
	var militia: StringName = units[0]
	var regular: StringName = units[1]
	match city.level:
		1: return [{unit_id = militia, count = 1}]
		2: return [{unit_id = militia, count = 1}, {unit_id = regular, count = 1}]
		3: return [{unit_id = militia, count = 2}, {unit_id = regular, count = 1}]
		4: return [{unit_id = militia, count = 2}, {unit_id = regular, count = 2}]
		5: return [{unit_id = militia, count = 3}, {unit_id = regular, count = 2}]
		_: return [{unit_id = militia, count = 1}]

func create_garrison_army(city: CityState) -> ArmyState:
	var garrison_def: Array = _get_garrison_composition(city)
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

# ── Faction-Specific Income Modifiers ─────────────────────

func _apply_faction_income_modifier(income: Dictionary, faction_id: StringName, fs: FactionState, city: CityState = null) -> void:
	match faction_id:
		&"skulloath":
			# Low corruption: +15% food. High corruption: -10% food
			if fs.corruption <= 30:
				if income.has(Enums.ResourceType.FOOD):
					income[Enums.ResourceType.FOOD] += int(income[Enums.ResourceType.FOOD] * 0.15)
			elif fs.corruption >= 70:
				if income.has(Enums.ResourceType.FOOD):
					income[Enums.ResourceType.FOOD] -= int(income[Enums.ResourceType.FOOD] * 0.10)
			# Blood Altar: consume 3 captives per turn for +20 iron and +15 gold
			if city and city.buildings.has(&"blood_altar"):
				var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
				if captives >= 3:
					fs.resources[Enums.ResourceType.CAPTIVES] -= 3
					income[Enums.ResourceType.IRON] = income.get(Enums.ResourceType.IRON, 0) + 20
					income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + 15
		&"gladehost":
			# Seasonal modifiers — Seasonal Shrine amplifies by 50%
			var season: int = GameManager.state.current_month
			var harmony_mult := fs.harmony / 100.0
			var shrine_mult := 1.5 if (city and city.buildings.has(&"seasonal_shrine")) else 1.0
			if season <= 2: # Spring: +food, +growth
				if income.has(Enums.ResourceType.FOOD):
					income[Enums.ResourceType.FOOD] += int(income[Enums.ResourceType.FOOD] * 0.20 * harmony_mult * shrine_mult)
			elif season <= 5: # Summer: +iron (arms production)
				if income.has(Enums.ResourceType.IRON):
					income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * 0.15 * harmony_mult * shrine_mult)
			elif season <= 7: # Autumn: +gold, +wood (harvest)
				if income.has(Enums.ResourceType.GOLD):
					income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * 0.20 * harmony_mult * shrine_mult)
				if income.has(Enums.ResourceType.WOOD):
					income[Enums.ResourceType.WOOD] += int(income[Enums.ResourceType.WOOD] * 0.20 * harmony_mult * shrine_mult)
			else: # Winter: -food (shrine reduces winter penalty)
				var winter_penalty := 0.20 if shrine_mult == 1.0 else 0.10
				if income.has(Enums.ResourceType.FOOD):
					income[Enums.ResourceType.FOOD] -= int(income[Enums.ResourceType.FOOD] * winter_penalty)
			# Living Fortress: seasonal defense scaling (bonus defense in spring/summer)
			if city and city.buildings.has(&"living_fortress"):
				if season <= 5: # Spring/Summer: trees grow, fortress strengthens
					income[Enums.ResourceType.WOOD] = income.get(Enums.ResourceType.WOOD, 0) + 5
		&"tainted_jade":
			# Taint power bonus: +5% iron when taint > 20 (hardened materials)
			if fs.taint_power >= 20:
				if income.has(Enums.ResourceType.IRON):
					income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * 0.05)
			# Captive conversion: each captive generates a small amount of wood/iron
			var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
			if captives > 0:
				# Captive Processing Camp doubles thrall output
				var camp_mult := 2 if (city and city.buildings.has(&"captive_processing_camp")) else 1
				var thrall_output := mini(captives / 5, 10) * camp_mult
				income[Enums.ResourceType.WOOD] = income.get(Enums.ResourceType.WOOD, 0) + thrall_output
				income[Enums.ResourceType.IRON] = income.get(Enums.ResourceType.IRON, 0) + thrall_output
			# Taint Suppressor: converts taint power into technology (shard neutralization research)
			if city and city.buildings.has(&"taint_suppressor"):
				if fs.taint_power >= 10:
					income[Enums.ResourceType.TECHNOLOGY] = income.get(Enums.ResourceType.TECHNOLOGY, 0) + int(fs.taint_power * 0.1)
			# Shard Breaker Forge: bonus shard essence from destroying shards (passive shard processing)
			if city and city.buildings.has(&"shard_breaker_forge"):
				income[Enums.ResourceType.SHARD_ESSENCE] = income.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 5
		&"shardhorde":
			# Active resonance buffs boost income
			for realm_key in fs.shard_resonance:
				var realm: int = realm_key
				match realm:
					Enums.Realm.DIVINE:
						income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + 15
					Enums.Realm.ELEMENTAL:
						income[Enums.ResourceType.IRON] = income.get(Enums.ResourceType.IRON, 0) + 20
					Enums.Realm.NATURE:
						income[Enums.ResourceType.FOOD] = income.get(Enums.ResourceType.FOOD, 0) + 20
					Enums.Realm.MORTAL:
						income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + 10
						income[Enums.ResourceType.FOOD] = income.get(Enums.ResourceType.FOOD, 0) + 10
					Enums.Realm.VOID:
						income[Enums.ResourceType.TECHNOLOGY] = income.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
