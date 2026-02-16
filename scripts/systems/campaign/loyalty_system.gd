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

# ── Social Class Calculation ─────────────────────────────────

static func calculate_social_classes(city: CityState, faction_id: StringName) -> Dictionary:
	var region_id := city.region_id
	var province_pop := get_province_population(region_id, faction_id)
	if province_pop <= 0:
		return {captives = 0, peasants = 0, artisans = 0, scholars = 0, nobles = 0}

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
	var captive_count := 0
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		var total_captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
		if total_captives > 0:
			# Get total faction population across all provinces
			var total_faction_pop := 0
			for cid in GameManager.state.cities:
				var c: CityState = GameManager.state.cities[cid]
				if c.faction_id == faction_id:
					total_faction_pop += c.population
			if total_faction_pop > 0:
				captive_count = int(float(total_captives) * float(province_pop) / float(total_faction_pop))

	# Calculate absolute numbers
	var nobles := int(float(province_pop) * noble_pct)
	var scholars := int(float(province_pop) * scholar_pct)
	var artisans := int(float(province_pop) * artisan_pct)
	var peasants := maxi(0, province_pop - nobles - scholars - artisans - captive_count)

	return {
		captives = captive_count,
		peasants = peasants,
		artisans = artisans,
		scholars = scholars,
		nobles = nobles,
	}

# ── Loyalty Delta Calculation ────────────────────────────────

static func calculate_loyalty_delta(city: CityState, faction_id: StringName) -> int:
	var breakdown := get_loyalty_breakdown(city, faction_id)
	var delta := 0
	for entry in breakdown:
		delta += entry.value
	return delta

static func get_loyalty_breakdown(city: CityState, faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region_id := city.region_id
	var region: RegionData = DataManager.get_region(region_id)
	var faction: FactionData = DataManager.get_faction(faction_id)
	var province_pop := get_province_population(region_id, faction_id)
	var cultural_count := _count_buildings_by_category(region_id, faction_id, &"cultural")
	var classes := calculate_social_classes(city, faction_id)

	# ── Positive modifiers ──

	# Base stability: +2 always
	result.append({label = "Base Stability", value = 2})

	# Same culture: +3 if faction realm_affinity matches region realm_influence
	if faction and region and faction.realm_affinity == region.realm_influence:
		result.append({label = "Same Realm Culture", value = 3})

	# Cultural buildings: +2 per cultural building
	if cultural_count > 0:
		result.append({label = "Cultural Buildings (x%d)" % cultural_count, value = 2 * cultural_count})

	# High population: +1 if province pop >= 300
	if province_pop >= 300:
		result.append({label = "High Population", value = 1})

	# Friendly/Allied neighbors: +1 per neighboring region that is FRIENDLY or ALLIED
	var friendly_neighbor_count := _count_neighbor_relations(region_id, faction_id, [Enums.FactionRelation.FRIENDLY, Enums.FactionRelation.ALLIED])
	if friendly_neighbor_count > 0:
		result.append({label = "Friendly Neighbors (x%d)" % friendly_neighbor_count, value = friendly_neighbor_count})

	# Long ownership: +1 if never captured or captured long ago
	if city.turns_since_capture == -1 or city.turns_since_capture > 10:
		result.append({label = "Long Ownership", value = 1})

	# ── Negative modifiers ──

	# Cultural mismatch: -3 if faction realm != region realm
	if faction and region and faction.realm_affinity != region.realm_influence:
		result.append({label = "Cultural Mismatch", value = -3})

	# Recently captured
	if city.turns_since_capture >= 0 and city.turns_since_capture <= 3:
		result.append({label = "Recently Captured", value = -8})
	elif city.turns_since_capture >= 4 and city.turns_since_capture <= 8:
		result.append({label = "Recently Captured (lingering)", value = -4})
	elif city.turns_since_capture >= 9 and city.turns_since_capture <= 15:
		result.append({label = "Recently Captured (fading)", value = -2})

	# War neighbors: -2 per neighboring region at WAR
	var war_neighbor_count := _count_neighbor_relations(region_id, faction_id, [Enums.FactionRelation.WAR])
	if war_neighbor_count > 0:
		var war_names := _get_neighbor_war_faction_names(region_id, faction_id)
		var label_text := "At War (%s)" % ", ".join(war_names) if war_names.size() > 0 else "War Neighbors (x%d)" % war_neighbor_count
		result.append({label = label_text, value = -2 * war_neighbor_count})

	# Under siege: -5
	if city.is_under_siege:
		result.append({label = "Under Siege", value = -5})

	# Low population: -2 if province pop < 100
	if province_pop < 100:
		result.append({label = "Low Population", value = -2})

	# High captive ratio: -1 per 10% captive ratio
	if province_pop > 0 and classes.captives > 0:
		var captive_ratio := float(classes.captives) / float(province_pop)
		var penalty := int(captive_ratio * 10.0)
		if penalty > 0:
			result.append({label = "High Captive Ratio", value = -penalty})

	# No cultural buildings: -1
	if cultural_count == 0:
		result.append({label = "No Cultural Buildings", value = -1})

	return result

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

static func apply_class_bonuses(income: Dictionary, classes: Dictionary, province_pop: int) -> Dictionary:
	if province_pop <= 0:
		return income

	# Calculate percentage points for each class
	var peasant_pct := float(classes.peasants) / float(province_pop) * 100.0
	var artisan_pct := float(classes.artisans) / float(province_pop) * 100.0
	var scholar_pct := float(classes.scholars) / float(province_pop) * 100.0
	var noble_pct := float(classes.nobles) / float(province_pop) * 100.0

	# Peasants: +0.5% Food per percentage point
	if income.has(Enums.ResourceType.FOOD):
		var bonus := income[Enums.ResourceType.FOOD] * (peasant_pct * 0.005)
		income[Enums.ResourceType.FOOD] += int(bonus)

	# Artisans: +0.5% Iron/Wood per percentage point
	if income.has(Enums.ResourceType.IRON):
		var bonus := income[Enums.ResourceType.IRON] * (artisan_pct * 0.005)
		income[Enums.ResourceType.IRON] += int(bonus)
	if income.has(Enums.ResourceType.WOOD):
		var bonus := income[Enums.ResourceType.WOOD] * (artisan_pct * 0.005)
		income[Enums.ResourceType.WOOD] += int(bonus)

	# Scholars: +0.8% Tech per percentage point
	if income.has(Enums.ResourceType.TECHNOLOGY):
		var bonus := income[Enums.ResourceType.TECHNOLOGY] * (scholar_pct * 0.008)
		income[Enums.ResourceType.TECHNOLOGY] += int(bonus)

	# Nobles: +0.6% Gold per percentage point
	if income.has(Enums.ResourceType.GOLD):
		var bonus := income[Enums.ResourceType.GOLD] * (noble_pct * 0.006)
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
