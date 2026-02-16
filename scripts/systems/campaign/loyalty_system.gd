class_name LoyaltySystem
extends RefCounted

# ── Province Helpers ─────────────────────────────────────────

static func get_province_cities(region_id: StringName, faction_id: StringName) -> Array[CityState]:
	var result: Array[CityState] = []
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id == region_id and city.faction_id == faction_id:
			result.append(city)
	return result

static func get_province_population(region_id: StringName, faction_id: StringName) -> int:
	var total := 0
	for city in get_province_cities(region_id, faction_id):
		total += city.population
	return total

static func get_province_buildings(region_id: StringName, faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for city in get_province_cities(region_id, faction_id):
		for building_id in city.buildings:
			if not result.has(building_id):
				result.append(building_id)
	return result

static func _count_buildings_by_category(region_id: StringName, faction_id: StringName, category: StringName) -> int:
	var count := 0
	for city in get_province_cities(region_id, faction_id):
		for building_id in city.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building and building.category == category:
				count += 1
	return count

static func _get_province_city_level_sum(region_id: StringName, faction_id: StringName) -> int:
	var total := 0
	for city in get_province_cities(region_id, faction_id):
		total += city.level
	return total

static func _has_capital_in_province(region_id: StringName, faction_id: StringName) -> bool:
	for city in get_province_cities(region_id, faction_id):
		if city.is_capital:
			return true
	return false

# ── Social Class Percentages ────────────────────────────────

static func calculate_class_percentages(city: CityState, faction_id: StringName) -> Dictionary:
	var region_id := city.region_id
	var province_pop := get_province_population(region_id, faction_id)
	if province_pop <= 0:
		return {captives = 0.0, peasants = 1.0, artisans = 0.0, scholars = 0.0, nobles = 0.0}

	var cultural_count := _count_buildings_by_category(region_id, faction_id, &"cultural")
	var economic_count := _count_buildings_by_category(region_id, faction_id, &"economic")
	var city_level_sum := _get_province_city_level_sum(region_id, faction_id)
	var has_capital := _has_capital_in_province(region_id, faction_id)

	# Nobles: 2% per city level + 3% if capital
	var noble_pct := float(city_level_sum) * 0.02
	if has_capital:
		noble_pct += 0.03
	noble_pct = minf(noble_pct, 0.25)

	# Scholars: 3% per cultural building
	var scholar_pct := float(cultural_count) * 0.03
	scholar_pct = minf(scholar_pct, 0.20)

	# Artisans: 4% per economic building
	var artisan_pct := float(economic_count) * 0.04
	artisan_pct = minf(artisan_pct, 0.30)

	# Captives: faction's total CAPTIVES distributed proportionally by province pop
	var captive_pct := 0.0
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		var total_captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
		if total_captives > 0:
			var total_faction_pop := 0
			for cid in GameManager.state.cities:
				var c: CityState = GameManager.state.cities[cid]
				if c.faction_id == faction_id:
					total_faction_pop += c.population
			if total_faction_pop > 0:
				var captive_count := int(float(total_captives) * float(province_pop) / float(total_faction_pop))
				captive_pct = float(captive_count) / float(province_pop)

	# Peasants: remainder
	var peasant_pct := maxf(0.0, 1.0 - noble_pct - scholar_pct - artisan_pct - captive_pct)

	return {
		captives = captive_pct,
		peasants = peasant_pct,
		artisans = artisan_pct,
		scholars = scholar_pct,
		nobles = noble_pct,
	}

static func get_class_percentage_breakdown(city: CityState, faction_id: StringName, class_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region_id := city.region_id
	var cultural_count := _count_buildings_by_category(region_id, faction_id, &"cultural")
	var economic_count := _count_buildings_by_category(region_id, faction_id, &"economic")
	var city_level_sum := _get_province_city_level_sum(region_id, faction_id)
	var has_capital := _has_capital_in_province(region_id, faction_id)

	match class_key:
		"nobles":
			result.append({label = "City levels (x%d)" % city_level_sum, value = "%d%%" % int(float(city_level_sum) * 2.0)})
			if has_capital:
				result.append({label = "Capital bonus", value = "+3%"})
			result.append({label = "Max", value = "25%"})
		"scholars":
			result.append({label = "Cultural buildings (x%d)" % cultural_count, value = "%d%%" % int(float(cultural_count) * 3.0)})
			result.append({label = "Max", value = "20%"})
		"artisans":
			result.append({label = "Economic buildings (x%d)" % economic_count, value = "%d%%" % int(float(economic_count) * 4.0)})
			result.append({label = "Max", value = "30%"})
		"captives":
			var fs: FactionState = GameManager.state.faction_states.get(faction_id)
			var total_captives := 0
			if fs:
				total_captives = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
			result.append({label = "Faction captives", value = str(total_captives)})
			result.append({label = "Distributed by province pop", value = ""})
		"peasants":
			result.append({label = "Remainder after other classes", value = ""})
	return result

# ── Per-Class Loyalty Weight Tables ─────────────────────────

# Each modifier has weights: {peasants, artisans, scholars, nobles, captives}
const CLASS_NAMES := ["peasants", "artisans", "scholars", "nobles", "captives"]

const W_BASE_STABILITY := {peasants = 2, artisans = 2, scholars = 2, nobles = 2, captives = 1}
const W_SAME_CULTURE := {peasants = 2, artisans = 1, scholars = 4, nobles = 3, captives = 1}
const W_CULTURAL_BUILDINGS := {peasants = 1, artisans = 1, scholars = 3, nobles = 2, captives = 0}
const W_HIGH_POP := {peasants = 1, artisans = 1, scholars = 0, nobles = 0, captives = 0}
const W_FRIENDLY_NEIGHBORS := {peasants = 1, artisans = 1, scholars = 1, nobles = 2, captives = 0}
const W_LONG_OWNERSHIP := {peasants = 2, artisans = 1, scholars = 1, nobles = 1, captives = 1}
const W_CULTURAL_MISMATCH := {peasants = -2, artisans = -1, scholars = -4, nobles = -3, captives = -1}
const W_CAPTURED_ACUTE := {peasants = -6, artisans = -5, scholars = -8, nobles = -10, captives = -3}
const W_CAPTURED_LINGER := {peasants = -3, artisans = -2, scholars = -4, nobles = -5, captives = -2}
const W_CAPTURED_FADING := {peasants = -1, artisans = -1, scholars = -2, nobles = -3, captives = -1}
const W_WAR_NEIGHBOR := {peasants = -3, artisans = -2, scholars = -1, nobles = -1, captives = 0}
const W_UNDER_SIEGE := {peasants = -6, artisans = -5, scholars = -5, nobles = -4, captives = -2}
const W_LOW_POP := {peasants = -2, artisans = -1, scholars = 0, nobles = 0, captives = 0}
const W_HIGH_CAPTIVE_RATIO := {peasants = 0, artisans = 0, scholars = -1, nobles = -1, captives = 1}
const W_NO_CULTURAL := {peasants = -1, artisans = 0, scholars = -2, nobles = -1, captives = 0}
const W_ECONOMIC_BUILDINGS := {peasants = 1, artisans = 3, scholars = 0, nobles = 1, captives = 0}
const W_NO_ECONOMIC := {peasants = -1, artisans = -3, scholars = 0, nobles = 0, captives = 0}

# ── Per-Class Loyalty Delta ─────────────────────────────────

static func calculate_class_loyalty_deltas(city: CityState, faction_id: StringName) -> Dictionary:
	var result := {peasants = 0, artisans = 0, scholars = 0, nobles = 0, captives = 0}
	var breakdown := _get_active_modifiers(city, faction_id)
	for entry in breakdown:
		var weights: Dictionary = entry.weights
		var multiplier: int = entry.get("multiplier", 1)
		for cls in CLASS_NAMES:
			result[cls] += weights[cls] * multiplier
	return result

static func get_class_loyalty_breakdown(city: CityState, faction_id: StringName, class_name_str: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var breakdown := _get_active_modifiers(city, faction_id)
	for entry in breakdown:
		var weights: Dictionary = entry.weights
		var multiplier: int = entry.get("multiplier", 1)
		var value: int = weights.get(class_name_str, 0) * multiplier
		if value != 0:
			result.append({label = entry.label, value = value})
	return result

static func _get_active_modifiers(city: CityState, faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region_id := city.region_id
	var region: RegionData = DataManager.get_region(region_id)
	var faction: FactionData = DataManager.get_faction(faction_id)
	var province_pop := get_province_population(region_id, faction_id)
	var cultural_count := _count_buildings_by_category(region_id, faction_id, &"cultural")
	var economic_count := _count_buildings_by_category(region_id, faction_id, &"economic")
	var pcts := calculate_class_percentages(city, faction_id)

	# ── Positive modifiers ──

	# Base stability: always
	result.append({label = "Base Stability", weights = W_BASE_STABILITY, multiplier = 1})

	# Same culture
	if faction and region and faction.realm_affinity == region.realm_influence:
		result.append({label = "Same Realm Culture", weights = W_SAME_CULTURE, multiplier = 1})

	# Cultural buildings (per building)
	if cultural_count > 0:
		result.append({label = "Cultural Buildings (x%d)" % cultural_count, weights = W_CULTURAL_BUILDINGS, multiplier = cultural_count})

	# Economic buildings (per building)
	if economic_count > 0:
		result.append({label = "Economic Buildings (x%d)" % economic_count, weights = W_ECONOMIC_BUILDINGS, multiplier = economic_count})

	# High population
	if province_pop >= 300:
		result.append({label = "High Population", weights = W_HIGH_POP, multiplier = 1})

	# Friendly/Allied neighbors
	var friendly_neighbor_count := _count_neighbor_relations(region_id, faction_id, [Enums.FactionRelation.FRIENDLY, Enums.FactionRelation.ALLIED])
	if friendly_neighbor_count > 0:
		result.append({label = "Friendly Neighbors (x%d)" % friendly_neighbor_count, weights = W_FRIENDLY_NEIGHBORS, multiplier = friendly_neighbor_count})

	# Long ownership
	if city.turns_since_capture == -1 or city.turns_since_capture > 10:
		result.append({label = "Long Ownership", weights = W_LONG_OWNERSHIP, multiplier = 1})

	# ── Negative modifiers ──

	# Cultural mismatch
	if faction and region and faction.realm_affinity != region.realm_influence:
		result.append({label = "Cultural Mismatch", weights = W_CULTURAL_MISMATCH, multiplier = 1})

	# Recently captured
	if city.turns_since_capture >= 0 and city.turns_since_capture <= 3:
		result.append({label = "Recently Captured", weights = W_CAPTURED_ACUTE, multiplier = 1})
	elif city.turns_since_capture >= 4 and city.turns_since_capture <= 8:
		result.append({label = "Recently Captured (lingering)", weights = W_CAPTURED_LINGER, multiplier = 1})
	elif city.turns_since_capture >= 9 and city.turns_since_capture <= 15:
		result.append({label = "Recently Captured (fading)", weights = W_CAPTURED_FADING, multiplier = 1})

	# War neighbors
	var war_neighbor_count := _count_neighbor_relations(region_id, faction_id, [Enums.FactionRelation.WAR])
	if war_neighbor_count > 0:
		var war_names := _get_neighbor_war_faction_names(region_id, faction_id)
		var label_text := "At War (%s)" % ", ".join(war_names) if war_names.size() > 0 else "War Neighbors (x%d)" % war_neighbor_count
		result.append({label = label_text, weights = W_WAR_NEIGHBOR, multiplier = war_neighbor_count})

	# Under siege
	if city.is_under_siege:
		result.append({label = "Under Siege", weights = W_UNDER_SIEGE, multiplier = 1})

	# Low population
	if province_pop < 100:
		result.append({label = "Low Population", weights = W_LOW_POP, multiplier = 1})

	# High captive ratio
	if pcts.captives > 0.05:
		var captive_mult := int(pcts.captives * 10.0)
		if captive_mult > 0:
			result.append({label = "High Captive Ratio", weights = W_HIGH_CAPTIVE_RATIO, multiplier = captive_mult})

	# No cultural buildings
	if cultural_count == 0:
		result.append({label = "No Cultural Buildings", weights = W_NO_CULTURAL, multiplier = 1})

	# No economic buildings
	if economic_count == 0:
		result.append({label = "No Economic Buildings", weights = W_NO_ECONOMIC, multiplier = 1})

	return result

# ── Province Loyalty (Weighted Average) ─────────────────────

static func calculate_province_loyalty(city: CityState, faction_id: StringName) -> int:
	var pcts := calculate_class_percentages(city, faction_id)
	var weighted := 0.0
	for cls in city.class_loyalty:
		weighted += float(city.class_loyalty[cls]) * float(pcts.get(cls, 0.0))
	return int(weighted)

# ── Legacy Compatibility ────────────────────────────────────

static func calculate_loyalty_delta(city: CityState, faction_id: StringName) -> int:
	# Returns the weighted-average delta across all classes
	var deltas := calculate_class_loyalty_deltas(city, faction_id)
	var pcts := calculate_class_percentages(city, faction_id)
	var weighted := 0.0
	for cls in deltas:
		weighted += float(deltas[cls]) * float(pcts.get(cls, 0.0))
	return int(weighted)

static func get_loyalty_breakdown(city: CityState, faction_id: StringName) -> Array[Dictionary]:
	# Returns province-level modifier breakdown (weighted averages)
	var result: Array[Dictionary] = []
	var pcts := calculate_class_percentages(city, faction_id)
	var modifiers := _get_active_modifiers(city, faction_id)
	for entry in modifiers:
		var weights: Dictionary = entry.weights
		var multiplier: int = entry.get("multiplier", 1)
		var weighted_value := 0.0
		for cls in CLASS_NAMES:
			weighted_value += float(weights[cls]) * multiplier * float(pcts.get(cls, 0.0))
		var val := int(weighted_value)
		if val != 0:
			result.append({label = entry.label, value = val})
	return result

# ── Neighbor Helpers ────────────────────────────────────────

static func _count_neighbor_relations(region_id: StringName, faction_id: StringName, relations: Array) -> int:
	var neighbor_factions := _get_neighbor_region_factions(region_id, faction_id)
	var count := 0
	for other_faction in neighbor_factions:
		var relation := GameManager.get_relation(faction_id, other_faction)
		if relations.has(relation):
			count += 1
	return count

static func _get_neighbor_war_faction_names(region_id: StringName, faction_id: StringName) -> Array[String]:
	var names: Array[String] = []
	var neighbor_factions := _get_neighbor_region_factions(region_id, faction_id)
	for other_faction in neighbor_factions:
		if GameManager.get_relation(faction_id, other_faction) == Enums.FactionRelation.WAR:
			var fd: FactionData = DataManager.get_faction(other_faction)
			var display := fd.display_name if fd else str(other_faction)
			if not names.has(display):
				names.append(display)
	return names

static func _get_neighbor_region_factions(region_id: StringName, faction_id: StringName) -> Array[StringName]:
	# Find regions that border this one by checking hex neighbors
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return []
	var region_tiles := hex_map.get_region_tiles(region_id)
	var neighbor_factions: Array[StringName] = []
	for coord in region_tiles:
		for neighbor_coord in HexHelper.get_neighbors(coord):
			if not HexHelper.is_valid(neighbor_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var tile := hex_map.get_tile(neighbor_coord)
			if tile == null or tile.region_id == region_id:
				continue
			if tile.owner_faction != &"" and tile.owner_faction != faction_id:
				if not neighbor_factions.has(tile.owner_faction):
					neighbor_factions.append(tile.owner_faction)
	return neighbor_factions

# ── Income Multiplier from Loyalty ───────────────────────────

static func get_loyalty_multiplier(loyalty_value: int) -> float:
	if loyalty_value >= 50:
		return 1.0
	elif loyalty_value >= 25:
		return 0.9
	elif loyalty_value >= 0:
		return 0.75
	elif loyalty_value >= -25:
		return 0.5
	elif loyalty_value >= -50:
		return 0.25
	else:
		return 0.1

static func get_loyalty_status(loyalty_value: int) -> String:
	if loyalty_value >= 50:
		return "Loyal"
	elif loyalty_value >= 25:
		return "Uneasy"
	elif loyalty_value >= 0:
		return "Disgruntled"
	elif loyalty_value >= -25:
		return "Hostile"
	elif loyalty_value >= -50:
		return "Revolt Risk"
	else:
		return "Active Revolt"

static func get_loyalty_color(loyalty_value: int) -> Color:
	if loyalty_value >= 50:
		return Color(0.4, 0.85, 0.4)
	elif loyalty_value >= 25:
		return Color(0.65, 0.85, 0.35)
	elif loyalty_value >= 0:
		return Color(0.9, 0.85, 0.3)
	elif loyalty_value >= -25:
		return Color(0.9, 0.6, 0.25)
	else:
		return Color(0.9, 0.3, 0.25)

# ── Social Class Income Bonuses ──────────────────────────────

static func apply_class_bonuses(income: Dictionary, pcts: Dictionary) -> Dictionary:
	# pcts are 0.0-1.0 floats from calculate_class_percentages()
	var peasant_pct: float = pcts.get("peasants", 0.0) * 100.0
	var artisan_pct: float = pcts.get("artisans", 0.0) * 100.0
	var scholar_pct: float = pcts.get("scholars", 0.0) * 100.0
	var noble_pct: float = pcts.get("nobles", 0.0) * 100.0

	# Peasants: +0.5% Food per percentage point
	if income.has(Enums.ResourceType.FOOD):
		var bonus := float(income[Enums.ResourceType.FOOD]) * (peasant_pct * 0.005)
		income[Enums.ResourceType.FOOD] += int(bonus)

	# Artisans: +0.5% Iron/Wood per percentage point
	if income.has(Enums.ResourceType.IRON):
		var bonus := float(income[Enums.ResourceType.IRON]) * (artisan_pct * 0.005)
		income[Enums.ResourceType.IRON] += int(bonus)
	if income.has(Enums.ResourceType.WOOD):
		var bonus := float(income[Enums.ResourceType.WOOD]) * (artisan_pct * 0.005)
		income[Enums.ResourceType.WOOD] += int(bonus)

	# Scholars: +0.8% Tech per percentage point
	if income.has(Enums.ResourceType.TECHNOLOGY):
		var bonus := float(income[Enums.ResourceType.TECHNOLOGY]) * (scholar_pct * 0.008)
		income[Enums.ResourceType.TECHNOLOGY] += int(bonus)

	# Nobles: +0.6% Gold per percentage point
	if income.has(Enums.ResourceType.GOLD):
		var bonus := float(income[Enums.ResourceType.GOLD]) * (noble_pct * 0.006)
		income[Enums.ResourceType.GOLD] += int(bonus)

	return income

# ── Revolt Check ─────────────────────────────────────────────

static func check_revolt(city: CityState) -> bool:
	if city.loyalty >= -25:
		return false
	var chance := float(-city.loyalty - 25) / 150.0  # 0% at -25, ~50% at -100
	return randf() < chance

static func get_revolt_chance(loyalty_value: int) -> float:
	if loyalty_value >= -25:
		return 0.0
	return float(-loyalty_value - 25) / 150.0
