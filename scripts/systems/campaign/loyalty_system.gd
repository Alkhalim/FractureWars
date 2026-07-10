class_name LoyaltySystem
extends RefCounted

# ── Province Helpers ─────────────────────────────────────────

# Province index: one pass over all cities serves every (region, faction)
# query until city topology changes (ownership epoch or city count). Callers
# receive SHARED arrays and must not mutate them (all current callers only
# iterate). Insertion order matches the old per-call scan (cities dict order).
static var _province_index: Dictionary = {} # "region|faction" -> Array[CityState]
static var _province_index_epoch: int = -1
static var _province_index_city_count: int = -1

static func get_province_cities(region_id: StringName, faction_id: StringName) -> Array[CityState]:
	var cities: Dictionary = GameManager.state.cities
	if _province_index_epoch != GameManager.city_topology_epoch \
			or _province_index_city_count != cities.size():
		_province_index.clear()
		for city_id in cities:
			var city: CityState = cities[city_id]
			var key := "%s|%s" % [city.region_id, city.faction_id]
			if _province_index.has(key):
				_province_index[key].append(city)
			else:
				var arr: Array[CityState] = [city]
				_province_index[key] = arr
		_province_index_epoch = GameManager.city_topology_epoch
		_province_index_city_count = cities.size()
	var result: Variant = _province_index.get("%s|%s" % [region_id, faction_id])
	if result == null:
		var empty: Array[CityState] = []
		return empty
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
				count += building.required_capital_level  # Tier 1=1, Tier 2=2, Tier 3=3
	return count

static func _has_food_production(region_id: StringName, faction_id: StringName) -> bool:
	for city in get_province_cities(region_id, faction_id):
		for building_id in city.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building and building.income_bonus.get(Enums.ResourceType.FOOD, 0) > 0:
				return true
	return false

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

static func calculate_class_pct_deltas(city: CityState, faction_id: StringName) -> Dictionary:
	# Returns per-class percentage point deltas (e.g. {peasants = -1.0, artisans = 2.0, ...})
	# by simulating next turn's building completions and level changes
	var region_id := city.region_id
	var current_pcts := calculate_class_percentages(city, faction_id)

	# Simulate next-turn state: check all province cities for building completions and level-ups
	var extra_cultural := 0
	var extra_economic := 0
	var extra_level := 0
	for pcity in get_province_cities(region_id, faction_id):
		for entry in pcity.build_queue:
			if entry.get("turns_remaining", 99) <= 1:
				var bd: BuildingData = DataManager.get_building(entry.get("building_id", &""))
				if bd:
					if bd.category == &"cultural":
						extra_cultural += bd.required_capital_level
					elif bd.category == &"economic":
						extra_economic += bd.required_capital_level
		# Check for upgrade completing next turn
		if pcity.upgrade_turns_remaining == 1:
			extra_level += 1

	if extra_cultural == 0 and extra_economic == 0 and extra_level == 0:
		return {peasants = 0.0, artisans = 0.0, scholars = 0.0, nobles = 0.0, captives = 0.0}

	# Recalculate with projected values
	var cultural_count := _count_buildings_by_category(region_id, faction_id, &"cultural") + extra_cultural
	var economic_count := _count_buildings_by_category(region_id, faction_id, &"economic") + extra_economic
	var city_level_sum := _get_province_city_level_sum(region_id, faction_id) + extra_level
	var has_capital := _has_capital_in_province(region_id, faction_id)

	var noble_pct := minf(float(city_level_sum) * 0.02 + (0.03 if has_capital else 0.0), 0.25)
	var scholar_pct := minf(float(cultural_count) * 0.03, 0.20)
	var artisan_pct := minf(float(economic_count) * 0.04, 0.30)

	# Captives stay same for projection
	var captive_pct: float = current_pcts.get("captives", 0.0)
	var peasant_pct := maxf(0.0, 1.0 - noble_pct - scholar_pct - artisan_pct - captive_pct)

	return {
		peasants = (peasant_pct - float(current_pcts.get("peasants", 0.0))) * 100.0,
		artisans = (artisan_pct - float(current_pcts.get("artisans", 0.0))) * 100.0,
		scholars = (scholar_pct - float(current_pcts.get("scholars", 0.0))) * 100.0,
		nobles = (noble_pct - float(current_pcts.get("nobles", 0.0))) * 100.0,
		captives = 0.0,
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
			result.append({label = "Cultural buildings (weight %d)" % cultural_count, value = "%d%%" % int(float(cultural_count) * 3.0)})
			result.append({label = "Max", value = "20%"})
		"artisans":
			result.append({label = "Economic buildings (weight %d)" % economic_count, value = "%d%%" % int(float(economic_count) * 4.0)})
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

const W_BASE_STABILITY := {peasants = 1, artisans = 1, scholars = 1, nobles = 1, captives = 0}
const W_SAME_CULTURE := {peasants = 2, artisans = 1, scholars = 3, nobles = 2, captives = 1}
const W_HIGH_POP := {peasants = 1, artisans = 1, scholars = 0, nobles = 0, captives = 0}
const W_FRIENDLY_NEIGHBORS := {peasants = 1, artisans = 1, scholars = 1, nobles = 2, captives = 0}
const W_LONG_OWNERSHIP := {peasants = 1, artisans = 1, scholars = 1, nobles = 1, captives = 0}
const W_CULTURAL_MISMATCH := {peasants = -3, artisans = -2, scholars = -5, nobles = -4, captives = -1}
const W_CAPTURED_ACUTE := {peasants = -8, artisans = -6, scholars = -10, nobles = -12, captives = -4}
const W_CAPTURED_LINGER := {peasants = -4, artisans = -3, scholars = -5, nobles = -6, captives = -2}
const W_CAPTURED_FADING := {peasants = -2, artisans = -1, scholars = -3, nobles = -4, captives = -1}
const W_WAR_NEIGHBOR := {peasants = -3, artisans = -2, scholars = -1, nobles = -1, captives = 0}
const W_UNDER_SIEGE := {peasants = -8, artisans = -6, scholars = -6, nobles = -5, captives = -3}
const W_LOW_POP := {peasants = -3, artisans = -2, scholars = 0, nobles = 0, captives = 0}
const W_HIGH_CAPTIVE_RATIO := {peasants = -2, artisans = -1, scholars = -4, nobles = 3, captives = 1}
# High loyalty decay — classes naturally drift toward 0 when loyalty is very high
const W_HIGH_LOYALTY_DECAY := {peasants = -1, artisans = -1, scholars = -2, nobles = -2, captives = 0}
# Population pressure — large populations have competing interests
const W_POPULATION_PRESSURE := {peasants = -1, artisans = -1, scholars = -1, nobles = -1, captives = 0}

# Military presence
const W_INFANTRY_PRESENCE := {peasants = 2, artisans = 0, scholars = 0, nobles = 0, captives = -1}
const W_CAVALRY_PRESENCE := {peasants = 0, artisans = 0, scholars = 0, nobles = 3, captives = -1}
const W_MAGE_PRESENCE := {peasants = -1, artisans = 0, scholars = 3, nobles = 0, captives = 0}
const W_CONSTRUCT_PRESENCE := {peasants = -1, artisans = 3, scholars = 0, nobles = 0, captives = 0}
const W_MONSTER_PRESENCE := {peasants = -4, artisans = -1, scholars = -1, nobles = -1, captives = 0}

# Commander presence — friendly commander nearby or in city boosts loyalty
const W_COMMANDER_NEARBY := {peasants = 2, artisans = 1, scholars = 1, nobles = 2, captives = 0}
const W_COMMANDER_IN_CITY := {peasants = 3, artisans = 2, scholars = 2, nobles = 4, captives = 0}

# Missing building type penalties
const W_NO_ECONOMIC_BUILDINGS := {peasants = 0, artisans = -3, scholars = 0, nobles = 0, captives = 0}
const W_NO_MILITARY_BUILDINGS := {peasants = 0, artisans = 0, scholars = 0, nobles = -3, captives = 0}
const W_NO_CULTURAL_BUILDINGS := {peasants = 0, artisans = 0, scholars = -3, nobles = 0, captives = 0}
const W_NO_FOOD_PRODUCTION := {peasants = -3, artisans = 0, scholars = 0, nobles = 0, captives = 0}

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
	var pcts := calculate_class_percentages(city, faction_id)

	# ── Positive modifiers ──

	# Base stability: always
	result.append({label = "Base Stability", weights = W_BASE_STABILITY, multiplier = 1})

	# Same culture
	if faction and region and faction.realm_affinity == region.realm_influence:
		result.append({label = "Same Realm Culture", weights = W_SAME_CULTURE, multiplier = 1})

	# Per-building class loyalty bonuses — grouped by category
	var building_category_totals: Dictionary = {} # category_name -> {peasants, artisans, ...}
	for city_in_prov in get_province_cities(region_id, faction_id):
		for building_id in city_in_prov.buildings:
			var building: BuildingData = DataManager.get_building(building_id)
			if building and not building.class_loyalty_bonus.is_empty():
				var cat: String = str(building.category) if building.category != &"" else "other"
				if not building_category_totals.has(cat):
					building_category_totals[cat] = {peasants = 0, artisans = 0, scholars = 0, nobles = 0, captives = 0}
				for cls in building.class_loyalty_bonus:
					building_category_totals[cat][cls] += building.class_loyalty_bonus[cls]
	var category_labels := {
		"military": "Military Buildings",
		"economic": "Economic Buildings",
		"cultural": "Cultural Buildings",
		"defensive": "Defensive Buildings",
	}
	for cat in building_category_totals:
		var bw: Dictionary = building_category_totals[cat]
		var has_nonzero := false
		for cls in bw:
			if bw[cls] != 0:
				has_nonzero = true
				break
		if has_nonzero:
			var label_text: String = category_labels.get(cat, cat.capitalize() + " Buildings")
			result.append({label = label_text, weights = bw, multiplier = 1})

	# Building special_effects: region_loyalty_bonus / morale_bonus
	var loyalty_bonus_total := 0
	for city_in_prov_2 in get_province_cities(region_id, faction_id):
		for building_id_2 in city_in_prov_2.buildings:
			var bld_2: BuildingData = DataManager.get_building(building_id_2)
			if bld_2:
				if bld_2.special_effects.has("region_loyalty_bonus"):
					loyalty_bonus_total += int(bld_2.special_effects["region_loyalty_bonus"])
				if bld_2.special_effects.has("morale_bonus"):
					loyalty_bonus_total += int(bld_2.special_effects["morale_bonus"])
	if loyalty_bonus_total != 0:
		result.append({label = "Special Buildings", weights = {peasants = loyalty_bonus_total, artisans = loyalty_bonus_total, scholars = loyalty_bonus_total, nobles = loyalty_bonus_total, captives = 0}, multiplier = 1})

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

	# High loyalty decay — complacency only for the class with the highest loyalty
	var max_class_loyalty := 0
	var max_class_name := &""
	for cls in CLASS_NAMES:
		var val: int = city.class_loyalty.get(cls, 0)
		if val > max_class_loyalty:
			max_class_loyalty = val
			max_class_name = cls
	if max_class_loyalty > 60 and max_class_name != &"":
		var decay_mult := int((max_class_loyalty - 60) / 20) + 1  # 1 at 61-80, 2 at 81-100
		var targeted_weights := {peasants = 0, artisans = 0, scholars = 0, nobles = 0, captives = 0}
		targeted_weights[max_class_name] = W_HIGH_LOYALTY_DECAY.get(max_class_name, -1)
		result.append({label = "Complacency Decay (%s)" % max_class_name.capitalize(), weights = targeted_weights, multiplier = decay_mult})

	# Population pressure — large cities have competing interests
	if province_pop >= 200:
		var pressure_mult := int(province_pop / 200)  # 1 at 200, 2 at 400, etc.
		result.append({label = "Population Pressure", weights = W_POPULATION_PRESSURE, multiplier = pressure_mult})

	# Missing building type penalties
	if _count_buildings_by_category(region_id, faction_id, &"economic") == 0:
		result.append({label = "No Economic Buildings", weights = W_NO_ECONOMIC_BUILDINGS, multiplier = 1})
	if _count_buildings_by_category(region_id, faction_id, &"military") == 0:
		result.append({label = "No Military Buildings", weights = W_NO_MILITARY_BUILDINGS, multiplier = 1})
	if _count_buildings_by_category(region_id, faction_id, &"cultural") == 0:
		result.append({label = "No Cultural Buildings", weights = W_NO_CULTURAL_BUILDINGS, multiplier = 1})
	if not _has_food_production(region_id, faction_id):
		result.append({label = "No Food Production", weights = W_NO_FOOD_PRODUCTION, multiplier = 1})

	# High captive ratio
	if pcts.captives > 0.05:
		var captive_mult := int(pcts.captives * 10.0)
		if captive_mult > 0:
			result.append({label = "High Captive Ratio", weights = W_HIGH_CAPTIVE_RATIO, multiplier = captive_mult})

	# Military presence
	var mil_tags := _count_military_tags_at_city(city)
	if mil_tags.infantry > 0:
		result.append({label = "Infantry Garrison (x%d)" % mil_tags.infantry, weights = W_INFANTRY_PRESENCE, multiplier = mil_tags.infantry})
	if mil_tags.cavalry > 0:
		result.append({label = "Cavalry Garrison (x%d)" % mil_tags.cavalry, weights = W_CAVALRY_PRESENCE, multiplier = mil_tags.cavalry})
	if mil_tags.mage > 0:
		result.append({label = "Mage Garrison (x%d)" % mil_tags.mage, weights = W_MAGE_PRESENCE, multiplier = mil_tags.mage})
	if mil_tags.construct > 0:
		result.append({label = "Construct Garrison (x%d)" % mil_tags.construct, weights = W_CONSTRUCT_PRESENCE, multiplier = mil_tags.construct})
	if mil_tags.monster > 0:
		result.append({label = "Monster Presence (x%d)" % mil_tags.monster, weights = W_MONSTER_PRESENCE, multiplier = mil_tags.monster})

	# Commander presence — friendly commanders boost loyalty
	var commander_in_city := false
	var commander_nearby := false
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.commander == null or army.faction_id != faction_id:
			continue
		if army.is_garrison:
			continue
		# Check if commander has negative loyalty aura (skip if so)
		var cmd_bonuses := CommanderSystem.get_commander_army_bonuses(army.commander)
		if cmd_bonuses.get("loyalty_aura", 0) < 0:
			continue
		if army.hex_pos == city.hex_pos:
			commander_in_city = true
			break
		elif HexHelper.hex_distance(army.hex_pos, city.hex_pos) <= 2:
			commander_nearby = true
	if commander_in_city:
		result.append({label = "Commander in City", weights = W_COMMANDER_IN_CITY, multiplier = 1})
	elif commander_nearby:
		result.append({label = "Commander Nearby", weights = W_COMMANDER_NEARBY, multiplier = 1})

	# ── Policy & Senate effects (Empire only) ──
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		# Active policy class loyalty effects
		for policy_id in fs.active_policies:
			var data: PolicyData = DataManager.policies.get(policy_id)
			if data and not data.class_loyalty_effects.is_empty():
				var pw := {peasants = 0, artisans = 0, scholars = 0, nobles = 0, captives = 0}
				for cls in data.class_loyalty_effects:
					pw[cls] = data.class_loyalty_effects[cls]
				result.append({label = "Policy: " + data.display_name, weights = pw, multiplier = 1})

		# Senate majority bonus (scaled by majority class loyalty)
		var majority := GameManager.policy_system.get_senate_majority(faction_id)
		if majority != &"":
			var scale := GameManager.policy_system._get_majority_loyalty_scale(faction_id, majority)
			var sw := {peasants = 0, artisans = 0, scholars = 0, nobles = 0, captives = 0}
			var majority_label := "Senate Majority: " + str(majority).capitalize()
			if majority == &"nobles":
				sw.nobles = roundi(1.0 * scale)
			elif majority == &"scholars":
				sw.scholars = roundi(1.0 * scale)
			elif majority == &"artisans":
				sw.artisans = roundi(1.0 * scale)
			elif majority == &"forsaken":
				sw = {peasants = -3, artisans = -3, scholars = -3, nobles = -3, captives = 0}
				majority_label = "Forsaken Senate Majority"
			result.append({label = majority_label, weights = sw, multiplier = 1})

	return result

# ── Province Loyalty (Weighted Average) ─────────────────────

static func calculate_province_loyalty(city: CityState, faction_id: StringName) -> int:
	var pcts := calculate_class_percentages(city, faction_id)
	var weighted := 0.0
	for cls in city.class_loyalty:
		weighted += float(city.class_loyalty[cls]) * float(pcts.get(cls, 0.0))
	return roundi(weighted)

# ── Legacy Compatibility ────────────────────────────────────

static func calculate_loyalty_delta(city: CityState, faction_id: StringName) -> int:
	# Returns the weighted-average delta across all classes
	var deltas := calculate_class_loyalty_deltas(city, faction_id)
	var pcts := calculate_class_percentages(city, faction_id)
	var weighted := 0.0
	for cls in deltas:
		weighted += float(deltas[cls]) * float(pcts.get(cls, 0.0))
	return roundi(weighted)

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

# ── Military Presence Helper ────────────────────────────────

static func _count_military_tags_at_city(city: CityState) -> Dictionary:
	var tags := {infantry = 0, cavalry = 0, mage = 0, construct = 0, monster = 0}
	for army: ArmyState in GameManager.get_armies_at_tile(city.hex_pos):
		if army.faction_id != city.faction_id:
			continue
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud == null:
				continue
			for tag in ud.tags:
				if tags.has(tag):
					tags[tag] += 1
			if ud.tags.has("monster") or ud.tags.has("beast"):
				if not ud.tags.has("monster"):
					tags["monster"] += 1

	return tags

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
		return 0.8
	elif loyalty_value >= -25:
		return 0.65
	elif loyalty_value >= -50:
		return 0.4
	else:
		return 0.2

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
