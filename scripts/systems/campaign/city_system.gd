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
	_process_captive_decay(faction_id)

	# Tainted Jade jungle spread: tiles near their cities convert to jungle
	var jade_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	if faction_id == &"tainted_jade" or jade_parent == &"tainted_jade":
		_process_jungle_spread(faction_id)

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
	var iron_pct: int = research_effects.get("income_iron_pct", 0)
	var wood_pct: int = research_effects.get("income_wood_pct", 0)
	var all_pct: int = research_effects.get("income_all_pct", 0)
	if gold_pct + all_pct != 0 and income.has(Enums.ResourceType.GOLD):
		income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * (gold_pct + all_pct) / 100.0)
	if food_pct + all_pct != 0 and income.has(Enums.ResourceType.FOOD):
		income[Enums.ResourceType.FOOD] += int(income[Enums.ResourceType.FOOD] * (food_pct + all_pct) / 100.0)
	if iron_pct + all_pct != 0 and income.has(Enums.ResourceType.IRON):
		income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * (iron_pct + all_pct) / 100.0)
	if wood_pct + all_pct != 0 and income.has(Enums.ResourceType.WOOD):
		income[Enums.ResourceType.WOOD] += int(income[Enums.ResourceType.WOOD] * (wood_pct + all_pct) / 100.0)

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

	# Region completion bonus: +2 to all resources for each city in completed regions
	var completed_regions := GameManager.get_completed_regions(faction_id)
	if city.region_id in completed_regions:
		for res_type in [Enums.ResourceType.GOLD, Enums.ResourceType.IRON, Enums.ResourceType.FOOD, Enums.ResourceType.WOOD, Enums.ResourceType.TECHNOLOGY]:
			income[res_type] = income.get(res_type, 0) + 2

	# Culture completion bonuses
	if GameManager.has_culture_bonus(faction_id, "food_bonus"):
		var val := GameManager.get_culture_bonus_value(faction_id, "food_bonus")
		if income.has(Enums.ResourceType.FOOD):
			income[Enums.ResourceType.FOOD] += int(income[Enums.ResourceType.FOOD] * val)
	if GameManager.has_culture_bonus(faction_id, "tech_bonus"):
		var val := GameManager.get_culture_bonus_value(faction_id, "tech_bonus")
		if income.has(Enums.ResourceType.TECHNOLOGY):
			income[Enums.ResourceType.TECHNOLOGY] += int(income[Enums.ResourceType.TECHNOLOGY] * val)
	if GameManager.has_culture_bonus(faction_id, "iron_bonus"):
		var val := GameManager.get_culture_bonus_value(faction_id, "iron_bonus")
		if income.has(Enums.ResourceType.IRON):
			income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * val)
	if GameManager.has_culture_bonus(faction_id, "shard_bonus"):
		var val := GameManager.get_culture_bonus_value(faction_id, "shard_bonus")
		if income.has(Enums.ResourceType.SHARD_ESSENCE):
			income[Enums.ResourceType.SHARD_ESSENCE] += int(income[Enums.ResourceType.SHARD_ESSENCE] * val)

	# Debt penalty: buildings produce 66% income when faction gold is negative
	if fs.resources.get(Enums.ResourceType.GOLD, 0) < 0:
		for res_type in income:
			income[res_type] = int(income[res_type] * 0.66)

	# Faction-specific income modifiers
	_apply_faction_income_modifier(income, faction_id, fs, city)

	# Global wood production reduction (-10%) to offset lower building costs
	if income.has(Enums.ResourceType.WOOD):
		income[Enums.ResourceType.WOOD] = int(income[Enums.ResourceType.WOOD] * 0.90)

	# Population food consumption: larger populations eat more
	var province_pop := get_province_population(city)
	var food_consumed := province_pop / 40
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
	# Low population malus: below 50 pop, production suffers — but floor at 0.3 to prevent death spiral
	if province_pop < 50:
		pop_mult *= maxf(0.3, float(province_pop) / 50.0)

	var income: Dictionary = {}

	# Base region income scaled by population
	for res_type in region.base_income:
		income[res_type] = int(region.base_income[res_type] * pop_mult)

	# Building bonuses — slightly scaled by population (except food)
	# At pop 100: no bonus. At pop 200: +10%. At pop 500: +40%.
	var building_pop_mult := maxf(1.0, 1.0 + (float(province_pop) - 100.0) * 0.001)
	# Captive-dependent buildings produce less without captives
	var fs_for_captives: FactionState = GameManager.state.faction_states.get(city.faction_id)
	var faction_captives: int = fs_for_captives.resources.get(Enums.ResourceType.CAPTIVES, 0) if fs_for_captives else 0
	var captive_buildings: Array[StringName] = [&"labor_camp", &"thrall_quarters", &"captive_processing_camp"]
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		# Labor camp buildings: scale effectiveness with captive count
		# 0 captives = 25% output, 10+ captives = 100% output
		var captive_mult := 1.0
		if building_id in captive_buildings:
			captive_mult = clampf(0.25 + 0.75 * (float(faction_captives) / 10.0), 0.25, 1.0)
		for res_type in building.income_bonus:
			var bonus: int = building.income_bonus[res_type]
			# Food production stays flat — growth is handled separately
			if res_type != Enums.ResourceType.FOOD:
				bonus = int(float(bonus) * building_pop_mult)
			bonus = int(float(bonus) * captive_mult)
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
	# Research population growth bonus
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	var pop_growth_pct: int = r_eff.get("population_growth_pct", 0)
	if pop_growth_pct != 0:
		base_growth += int(float(base_growth) * pop_growth_pct / 100.0)
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
		# Food consumption (quartered rate)
		var province_pop := get_province_population(city)
		total_food -= province_pop / 40
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
	# Floor at 30 pop to prevent death spirals — at 30 pop, food consumption is low enough to recover
	var loss_per_city := maxi(1, absi(food_total) / (faction_cities.size() * 5))
	for city in faction_cities:
		city.population = maxi(30, city.population - loss_per_city)

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
	for army: ArmyState in GameManager.get_armies_at_tile(city.hex_pos):
		if army.faction_id == faction_id:
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
			for army: ArmyState in GameManager.get_armies_at_tile(city.hex_pos):
				if army.faction_id == faction_id:
					for unit in army.units:
						var ud := DataManager.get_unit(unit.unit_data_id)
						if ud:
							unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * 0.05))

		# Steppe Watchtower: extends siege time by 1 (requires 5 turns instead of 4)
		var siege_threshold := 4
		if city.buildings.has(&"steppe_watchtower"):
			siege_threshold = 5
		if city.siege_turns >= siege_threshold:
			# Skulloath player gets a choice: capture, loot, or raze
			if faction_id == &"skulloath" and faction_id == GameManager.state.player_faction_id:
				EventBus.siege_choice_needed.emit(city.city_id, faction_id)
			else:
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

## Called by the Skulloath siege choice dialog to execute the "capture" option.
func apply_siege_choice_capture(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return
	_capture_city(city)

## Skulloath "Loot" option: steal large resources from the city but don't take it.
## The city remains with its original owner but loses population and loyalty.
func apply_siege_choice_loot(city_id: StringName) -> Dictionary:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return {}
	var looter_id := city.siege_faction
	var fs: FactionState = GameManager.state.faction_states.get(looter_id)
	if fs == null:
		return {}

	# Loot amounts scale with city level and population
	var loot_mult: float = 1.0 + city.level * 0.3
	var gold_loot: int = int(60 * loot_mult)
	var wood_loot: int = int(45 * loot_mult)
	var iron_loot: int = int(25 * loot_mult)
	var food_loot: int = int(35 * loot_mult)

	fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + gold_loot
	fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + wood_loot
	fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + iron_loot
	fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + food_loot

	# City suffers: population halved, loyalty tanks
	city.population = maxi(20, city.population / 2)
	city.loyalty = clampi(city.loyalty - 40, -100, 100)
	for cls in city.class_loyalty:
		city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 30, -100, 100)

	# End siege
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0

	# Diplomacy hit with all factions
	for other_fid in GameManager.state.faction_states:
		if other_fid != looter_id and not GameManager.is_npc_faction(other_fid):
			GameManager.diplomacy_system.modify_standing(looter_id, other_fid, -5, "Looted a city")

	return {"gold": gold_loot, "wood": wood_loot, "iron": iron_loot, "food": food_loot}

## Skulloath "Raze" option: burn the city, downgrading all buildings by 1 tier.
## Tier 1 buildings are destroyed. City stays with original owner in ruins.
func apply_siege_choice_raze(city_id: StringName) -> Dictionary:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return {}
	var razer_id := city.siege_faction

	# Downgrade or destroy each building
	var destroyed_count := 0
	var downgraded_count := 0
	var new_buildings: Array[StringName] = []
	for bld_id in city.buildings:
		var bld_data: BuildingData = DataManager.get_building(bld_id)
		if bld_data == null:
			continue
		# Find if this building is an upgrade of something (has upgrades_from)
		if bld_data.upgrades_from != &"":
			# Downgrade to parent building
			new_buildings.append(bld_data.upgrades_from)
			downgraded_count += 1
		else:
			# Tier 1 building: destroy it
			destroyed_count += 1
	city.buildings = new_buildings

	# Small loot from razing (less than looting)
	var fs: FactionState = GameManager.state.faction_states.get(razer_id)
	var gold_loot := 30
	var wood_loot := 20
	if fs:
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + gold_loot
		fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + wood_loot

	# City devastated: population and loyalty crushed
	city.population = maxi(10, city.population / 3)
	city.loyalty = clampi(city.loyalty - 60, -100, 100)
	for cls in city.class_loyalty:
		city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 50, -100, 100)

	# End siege
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0

	# Major diplomacy hit
	for other_fid in GameManager.state.faction_states:
		if other_fid != razer_id and not GameManager.is_npc_faction(other_fid):
			GameManager.diplomacy_system.modify_standing(razer_id, other_fid, -10, "Razed a city")

	return {"destroyed": destroyed_count, "downgraded": downgraded_count, "gold": gold_loot, "wood": wood_loot}

func _deduct_upkeep(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return

	# Research upkeep reduction
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	var upkeep_red_pct: float = float(r_eff.get("upkeep_reduction_pct", 0)) / 100.0

	for army: ArmyState in GameManager.get_faction_armies(faction_id):
		# Terrain upkeep modifier (jungle/desert/wastes etc.)
		var terrain_mult: float = TurnManager.get_terrain_upkeep_modifier(army)
		# Unit upkeep
		for unit in army.units:
			var unit_data := DataManager.get_unit(unit.unit_data_id)
			if unit_data == null:
				continue
			for res_type in unit_data.upkeep_cost:
				if fs.resources.has(res_type):
					var cost := int(unit_data.upkeep_cost[res_type] * terrain_mult)
					if upkeep_red_pct > 0:
						cost = int(cost * (1.0 - upkeep_red_pct))
					# Global upkeep discounts: food -20%, gold -20%
					if res_type == Enums.ResourceType.FOOD:
						cost = int(cost * 0.80)
					elif res_type == Enums.ResourceType.GOLD:
						cost = int(cost * 0.80)
					fs.resources[res_type] -= cost
		# Commander upkeep (only while assigned to army; skip for elderbeast armies)
		if army.commander != null and army.elderbeast_id == &"":
			var level_mult := 1.0 + (army.commander.level - 1) * 0.5
			for res_type in CommanderSystem.COMMANDER_UPKEEP:
				var cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				if fs.resources.has(res_type):
					fs.resources[res_type] -= cost

func _process_captive_decay(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	if captives <= 0:
		return

	# Count labor-camp-type buildings across all faction cities
	var labor_camp_count := 0
	var thrall_count := 0
	var processing_camp_count := 0
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		if city.buildings.has(&"labor_camp"):
			labor_camp_count += 1
		if city.buildings.has(&"thrall_quarters"):
			thrall_count += 1
		if city.buildings.has(&"captive_processing_camp"):
			processing_camp_count += 1

	# Each camp-type building consumes captives per turn (they die, escape, get worked to death)
	var decay := 0
	decay += labor_camp_count * 2        # Labor Camp: -2 captives/turn each
	decay += thrall_count * 1             # Thrall Quarters: -1 captive/turn each
	decay += processing_camp_count * 3    # Captive Processing Camp: -3 captives/turn each

	# Blood Altar already consumes 3 captives in _apply_faction_income_modifier
	# Natural captive attrition: even without camps, 1 captive escapes/dies per 5 turns
	if decay == 0:
		# No camp buildings — slow natural decay
		if GameManager.state.current_turn % 5 == 0:
			decay = 1

	if decay > 0:
		fs.resources[Enums.ResourceType.CAPTIVES] = maxi(0, captives - decay)

func _process_jungle_spread(faction_id: StringName) -> void:
	# Tainted Jade: jungle spreads from cities, converting adjacent tiles
	# Fast + aggressive: 1-2 tiles per turn, disrupts enemy production
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# Collect all Tainted Jade city hex positions
	var jade_city_hexes: Array[Vector2i] = []
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id:
			jade_city_hexes.append(city.hex_pos)

	if jade_city_hexes.is_empty():
		return

	# Also spread from existing jungle tiles near Tainted Jade territory
	var spread_sources: Array[Vector2i] = []
	spread_sources.append_array(jade_city_hexes)

	# Add jungle tiles owned by Tainted Jade as spread sources
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.JUNGLE and tile.owner_faction == faction_id:
			spread_sources.append(coord)

	# Spread: each source tries to convert 1 random neighbor per turn
	var converted_this_turn := 0
	var max_conversions := jade_city_hexes.size() * 2 + 1  # Scale with city count
	var already_tried: Dictionary = {}
	spread_sources.shuffle()

	for source in spread_sources:
		if converted_this_turn >= max_conversions:
			break
		var neighbors := HexHelper.get_neighbors(source)
		neighbors.shuffle()
		for neighbor in neighbors:
			if already_tried.has(neighbor):
				continue
			already_tried[neighbor] = true
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile: HexMapData.TileState = hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			# Can't convert water, mountains, or existing jungle
			if ntile.terrain in [Enums.TerrainType.WATER, Enums.TerrainType.MOUNTAINS, Enums.TerrainType.JUNGLE]:
				continue
			# Shard wastes resist conversion (50% chance to fail)
			if ntile.terrain == Enums.TerrainType.SHARD_WASTES and randf() < 0.5:
				continue
			# Convert to jungle
			ntile.terrain = Enums.TerrainType.JUNGLE
			converted_this_turn += 1
			break  # Only 1 conversion per source per turn

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

# ── City Territory (Voronoi within region) ───────────────────

func get_city_territory_owner(hex_pos: Vector2i, region_id: StringName) -> StringName:
	var closest_city_id: StringName = &""
	var closest_dist := 999
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id != region_id:
			continue
		var dist := HexHelper.hex_distance(hex_pos, city.hex_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_city_id = city.city_id
	return closest_city_id

# ── Independent City Joining Logic ───────────────────────────

func check_independent_city_loyalty() -> void:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != &"independent":
			continue
		var culture: StringName = GameManager.REGION_CULTURE.get(city.region_id, &"")
		if culture == &"":
			continue
		# Find factions with territory adjacent to this city
		var candidates: Dictionary = {}  # faction_id -> tile_count
		for neighbor in HexHelper.get_neighbors(city.hex_pos):
			var tile := GameManager.state.hex_map.get_tile(neighbor)
			if tile and tile.owner_faction != &"" and tile.owner_faction != &"independent":
				candidates[tile.owner_faction] = candidates.get(tile.owner_faction, 0) + 1

		for faction_id in candidates:
			var standing := GameManager.diplomacy_system.get_standing(faction_id, culture)
			if standing >= 40:
				_independent_city_joins(city, faction_id)
				break

func _independent_city_joins(city: CityState, faction_id: StringName) -> void:
	city.faction_id = faction_id
	city.turns_since_capture = 0
	city.loyalty = 30
	city.class_loyalty = {
		"peasants": 30, "artisans": 30, "scholars": 30, "nobles": 30, "captives": 0
	}
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		fs.owned_cities.append(city.city_id)
	EventBus.city_joined.emit(city.city_id, faction_id)

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

	# Skulloath corruption-gated buildings: committing to one path locks out the other's T3
	var skulloath_corruption := -1
	var skulloath_parent_faction: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, &"")
	if city.faction_id == &"skulloath" or skulloath_parent_faction == &"skulloath":
		var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
		if fs == null and skulloath_parent_faction == &"skulloath":
			fs = GameManager.state.faction_states.get(&"skulloath")
		if fs:
			skulloath_corruption = fs.corruption

	var result: Array[BuildingData] = []
	for building_id in DataManager.buildings:
		var building: BuildingData = DataManager.buildings[building_id]
		# Skulloath dual-path restrictions: T3 tradition requires low corruption, T3 void requires high
		if skulloath_corruption >= 0:
			# Tradition T3: locked if corruption > 40
			if building_id in [&"ancestor_sanctum"] and skulloath_corruption > 40:
				continue
			# Void T3: locked if corruption < 60
			if building_id in [&"demon_gate"] and skulloath_corruption < 60:
				continue
		# Skip faction-specific buildings that don't belong to this city's faction
		if building.faction_id != &"" and building.faction_id != city.faction_id:
			var parent_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, &"")
			if parent_id == &"" or building.faction_id != parent_id or building.required_capital_level > 2:
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
	# Skulloath dual-path corruption gate
	var sk_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, &"")
	if city.faction_id == &"skulloath" or sk_parent == &"skulloath":
		var sk_fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
		if sk_fs == null and sk_parent == &"skulloath":
			sk_fs = GameManager.state.faction_states.get(&"skulloath")
		if sk_fs:
			if building_id == &"ancestor_sanctum" and sk_fs.corruption > 40:
				return false
			if building_id == &"demon_gate" and sk_fs.corruption < 60:
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

	# Check and deduct cost (with global -10 wood discount)
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	var adjusted_cost := building.build_cost.duplicate()
	if adjusted_cost.has(Enums.ResourceType.WOOD):
		adjusted_cost[Enums.ResourceType.WOOD] = maxi(0, adjusted_cost[Enums.ResourceType.WOOD] - 10)
	if not _can_afford(fs, adjusted_cost):
		return false
	_deduct_cost(fs, adjusted_cost)

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

	# Check recruit cost (with global -10% gold discount)
	var adjusted_recruit := unit_data.recruit_cost.duplicate()
	if adjusted_recruit.has(Enums.ResourceType.GOLD):
		adjusted_recruit[Enums.ResourceType.GOLD] = int(adjusted_recruit[Enums.ResourceType.GOLD] * 0.90)
	if not _can_afford(fs, adjusted_recruit):
		return false

	# Check province population (shared across all cities in province)
	var pop_cost := unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
	var province_pop := get_province_population(city)
	if province_pop < pop_cost:
		return false

	# Deduct resources and population from province (subtract from this city first, overflow to others)
	_deduct_cost(fs, adjusted_recruit)
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
	&"moonspear": [&"moonspear_sentinel", &"moonspear_sentinel"],
	&"thunderswarm": [&"thunderswarm_warrior", &"thunderswarm_warrior"],
	&"cinderguard": [&"cinderguard_forgeborn", &"cinderguard_forgeborn"],
	&"forsaken": [&"forsaken_wretch", &"forsaken_wretch"],
	&"ivoryscar": [&"ivoryscar_seeker", &"ivoryscar_seeker"],
	&"sunblessed": [&"sunblessed_pilgrim", &"sunblessed_pilgrim"],
}

func _get_garrison_composition(city: CityState) -> Array:
	var units: Array = GARRISON_UNITS.get(city.faction_id, GARRISON_UNITS[&"empire"])
	var militia: StringName = units[0]
	var regular: StringName = units[1]
	# Building bonus: +1 militia per military building (barracks, training_ground, etc.)
	var building_bonus := 0
	for bid in city.buildings:
		if bid in [&"barracks", &"training_ground", &"war_forge", &"fortification", &"watchtower"]:
			building_bonus += 1
	match city.level:
		1: return [{unit_id = militia, count = 5 + building_bonus}]
		2: return [{unit_id = militia, count = 5 + building_bonus}, {unit_id = regular, count = 3}]
		3: return [{unit_id = militia, count = 6 + building_bonus}, {unit_id = regular, count = 5}]
		4: return [{unit_id = militia, count = 7 + building_bonus}, {unit_id = regular, count = 6}]
		5: return [{unit_id = militia, count = 8 + building_bonus}, {unit_id = regular, count = 8}]
		_: return [{unit_id = militia, count = 5 + building_bonus}]

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
	# Don't siege allied or friendly cities
	var relation := GameManager.get_relation(attacking_faction, city.faction_id)
	if relation == Enums.FactionRelation.ALLIED or relation == Enums.FactionRelation.FRIENDLY:
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
	Enums.TerrainType.WETLANDS:     {0: 2, 3: 2, 5: 0},
	Enums.TerrainType.TUNDRA:    {0: 1, 3: 1, 1: 1},
}

const SETTLEMENT_FOUNDING_COST := {
	Enums.ResourceType.GOLD: 80,
	Enums.ResourceType.WOOD: 40,
	Enums.ResourceType.FOOD: 30,
}

const SETTLEMENT_SPHERE_RADIUS := 3

func is_in_settlement_sphere(hex_pos: Vector2i) -> bool:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if HexHelper.hex_distance(hex_pos, city.hex_pos) <= SETTLEMENT_SPHERE_RADIUS:
			return true
	return false

func get_valid_settlement_tiles(faction_id: StringName, region_id: StringName, city_id: StringName = &"") -> Array[Vector2i]:
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
		if tile.terrain == Enums.TerrainType.MOUNTAINS:
			continue
		if is_in_settlement_sphere(coord):
			continue
		if city_id != &"":
			var territory_owner := get_city_territory_owner(coord, region_id)
			if territory_owner != city_id:
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
		Enums.TerrainType.WETLANDS: return 0  # Gold
		Enums.TerrainType.TUNDRA: return 1  # Iron
	return -1

# ── Commander influence helpers ───────────────────────────────

func _get_nearby_friendly_commanders(city: CityState) -> Array[CommanderState]:
	var result: Array[CommanderState] = []
	for army: ArmyState in GameManager.get_all_faction_armies(city.faction_id):
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
	# Sub-factions inherit parent faction's income modifiers
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	# For parent mechanic checks, use parent's FactionState if sub-faction
	if parent_fid != faction_id:
		var parent_fs: FactionState = GameManager.state.faction_states.get(parent_fid)
		if parent_fs:
			fs = parent_fs
	# Apply sub-faction-specific income bonuses
	match faction_id:
		&"miststriders":  # Fog traders: +15% gold
			if income.has(Enums.ResourceType.GOLD):
				income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * 0.15)
		&"oaseans":  # Desert educators: +2 tech flat
			income[Enums.ResourceType.TECHNOLOGY] = income.get(Enums.ResourceType.TECHNOLOGY, 0) + 2
		&"servants_of_reliquary":  # Building discount proxy: +10% iron (construction materials)
			if income.has(Enums.ResourceType.IRON):
				income[Enums.ResourceType.IRON] += int(income[Enums.ResourceType.IRON] * 0.10)
		&"salt_reavers":  # Raiders: +10% gold from raiding/trade
			if income.has(Enums.ResourceType.GOLD):
				income[Enums.ResourceType.GOLD] += int(income[Enums.ResourceType.GOLD] * 0.10)
	match parent_fid:
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
