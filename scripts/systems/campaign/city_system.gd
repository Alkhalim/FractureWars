class_name CitySystem
extends RefCounted

const BUILDING_INCOME_MULTIPLIER := 0.85

const DEFAULT_BUILDING_UPKEEP := {
	1: {0: 2, 5: 1},        # T1: 2 gold, 1 wood
	2: {1: 3, 5: 3},        # T2: 3 iron, 3 wood
	3: {0: 5, 1: 5},        # T3: 5 gold, 5 iron
}

# Region/faction-wide building effects
const REGION_WIDE_BUILDING_EFFECTS := {
	&"caravan_depot": {"scope": "region", "effect": "gold_income_pct", "value": 5},
	&"lunar_observatory": {"scope": "region", "effect": "tech_flat", "value": 2},
	&"warriors_longhouse": {"scope": "region", "effect": "defense_flat", "value": 1},
}
const FACTION_WIDE_BUILDING_EFFECTS := {
	&"cathedral_of_dawn": {"effect": "loyalty_flat", "value": 3, "faction_filter": &"sunblessed"},
	&"astral_bazaar": {"effect": "trade_income_pct", "value": 3},
	&"relic_traders_guild": {"effect": "gold_per_relic_building", "value": 2},
}

func process_turn(faction_id: StringName) -> void:
	# Calculate projected food income for growth modifier
	var food_income := _calculate_food_income(faction_id)

	# Province-shared growth: process once per province, not per city
	var processed_provinces: Dictionary = {}  # region_id -> true

	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue

		# Skip income/growth for cities under siege. Evacuated settlements
		# (Cinderguard dragon raid) skip income WHOLESALE like sieged cities —
		# gating only calculate_city_income would leak the later
		# _generate_income stages (region-completion bonus, population food
		# consumption) into a settlement that is supposed to be fully offline.
		if not city.is_under_siege and city.production_disabled_turns <= 0:
			_generate_income(city, faction_id)

		# Evacuated settlements: count down toward resuming production,
		# independent of siege status. Ticked AFTER this turn's income
		# calculation so a fresh production_disabled_turns=3 blocks exactly
		# 3 turns of income before resuming.
		if city.production_disabled_turns > 0:
			city.production_disabled_turns -= 1

		# Province growth: only calculate once per province, apply to capital
		if not city.is_under_siege and not processed_provinces.has(city.region_id):
			processed_provinces[city.region_id] = true
			_add_province_growth(city.region_id, faction_id, food_income)

		_process_build_queue(city)
		_process_recruit_queue(city, faction_id)
		_process_upgrade(city)

		# Garrison HP regeneration: heals +15% per turn when not under siege
		if not city.is_under_siege and city.garrison_hp_ratio < 1.0:
			if city.garrison_hp_ratio <= 0.0:
				city.garrison_hp_ratio = 0.1 # Respawn at 10% when no longer sieged
			else:
				city.garrison_hp_ratio = minf(city.garrison_hp_ratio + 0.15, 1.0)

		# Independent city garrison growth: +1 unit every 5 turns, max 9
		if city.faction_id == &"independent" and city.garrison_units.size() > 0:
			_grow_independent_garrison(city)

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

	# Faction-level percentage/flat stages below are small PURE helpers (income
	# in, delta out) shared with the income breakdown tooltip in
	# campaign_hud._calculate_income_breakdown, so the two can never drift
	# apart. Order matters: each stage reads the income AFTER prior stages
	# were merged in, exactly like the inline math this replaced.
	_merge_income_delta(income, apply_research_income_percentages(faction_id, income))
	# Heartwood: +% food income (special_resources_design) — compounds on top
	# of the research food_pct bonus just applied above.
	_merge_income_delta(income, apply_heartwood_income_bonus(faction_id, income))
	# Research: trade income bonus (flat gold per active trade treaty)
	_merge_income_delta(income, apply_trade_income_bonus(faction_id, income))
	# Apply senate majority income effects (Empire only — other factions have no senate)
	_merge_income_delta(income, apply_senate_income_percentages(faction_id, income))
	# Region completion bonus: +2 to all resources for each city in completed regions
	_merge_income_delta(income, region_completion_income_bonus(faction_id, city))
	# Culture completion bonuses
	_merge_income_delta(income, apply_culture_income_bonuses(faction_id, income))
	# Research: shard_essence_pct and shard_harvest_bonus
	_merge_income_delta(income, apply_shard_research_income(faction_id, income))
	# Debt penalty: buildings produce 66% income when faction gold is negative
	_merge_income_delta(income, apply_debt_penalty(fs, income))

	# Faction-specific income modifiers (also consumes captives / mechanic
	# meters as a side effect — see compute_faction_income_modifier_effects)
	_apply_faction_income_modifier(income, faction_id, fs, city)

	# Global wood production reduction (-10%) to offset lower building costs
	_merge_income_delta(income, apply_wood_production_reduction(income))

	# Population food consumption: larger populations eat more
	var food_consumed := population_food_consumption(city)
	if food_consumed > 0 and income.has(Enums.ResourceType.FOOD):
		income[Enums.ResourceType.FOOD] -= food_consumed
	elif food_consumed > 0:
		income[Enums.ResourceType.FOOD] = -food_consumed

	for res_type in income:
		if fs.resources.has(res_type):
			fs.resources[res_type] += income[res_type]
		else:
			fs.resources[res_type] = income[res_type]

func _merge_income_delta(income: Dictionary, delta: Dictionary) -> void:
	for res_type in delta:
		income[res_type] = income.get(res_type, 0) + delta[res_type]

# ── Faction-level income stages (single source of truth) ──────────────────
# Each function below is PURE: given the running per-city income (and
# whatever faction/city context it needs), it returns the DELTA that stage
# would add — it never mutates its inputs. _generate_income calls them in
# sequence via _merge_income_delta. campaign_hud._calculate_income_breakdown
# calls the SAME functions per owned city to build labeled tooltip rows, so
# the tooltip can never drift out of sync with what actually gets credited.

func apply_research_income_percentages(faction_id: StringName, income: Dictionary) -> Dictionary:
	var research_effects := GameManager.research_system.get_research_effects(faction_id)
	var gold_pct: int = research_effects.get("income_gold_pct", 0)
	var food_pct: int = research_effects.get("income_food_pct", 0)
	var iron_pct: int = research_effects.get("income_iron_pct", 0)
	var wood_pct: int = research_effects.get("income_wood_pct", 0)
	var all_pct: int = research_effects.get("income_all_pct", 0)
	var delta: Dictionary = {}
	if gold_pct + all_pct != 0 and income.has(Enums.ResourceType.GOLD):
		delta[Enums.ResourceType.GOLD] = int(income[Enums.ResourceType.GOLD] * (gold_pct + all_pct) / 100.0)
	if food_pct + all_pct != 0 and income.has(Enums.ResourceType.FOOD):
		delta[Enums.ResourceType.FOOD] = int(income[Enums.ResourceType.FOOD] * (food_pct + all_pct) / 100.0)
	if iron_pct + all_pct != 0 and income.has(Enums.ResourceType.IRON):
		delta[Enums.ResourceType.IRON] = int(income[Enums.ResourceType.IRON] * (iron_pct + all_pct) / 100.0)
	if wood_pct + all_pct != 0 and income.has(Enums.ResourceType.WOOD):
		delta[Enums.ResourceType.WOOD] = int(income[Enums.ResourceType.WOOD] * (wood_pct + all_pct) / 100.0)
	return delta

func apply_heartwood_income_bonus(faction_id: StringName, income: Dictionary) -> Dictionary:
	var heart_mod := SpecialResourceSystem.modifier_strength(faction_id, &"heartwood")
	if heart_mod <= 0.0 or not income.has(Enums.ResourceType.FOOD):
		return {}
	var boosted := int(income[Enums.ResourceType.FOOD] * (1.0 + heart_mod))
	return {Enums.ResourceType.FOOD: boosted - income[Enums.ResourceType.FOOD]}

func apply_trade_income_bonus(faction_id: StringName, income: Dictionary) -> Dictionary:
	var research_effects := GameManager.research_system.get_research_effects(faction_id)
	var trade_bonus: int = research_effects.get("trade_income_bonus", 0)
	if trade_bonus <= 0 or not income.has(Enums.ResourceType.GOLD):
		return {}
	var trade_count := 0
	if GameManager.diplomacy_system:
		for tid in GameManager.state.diplomacy_state.treaties:
			var treaty = GameManager.state.diplomacy_state.treaties[tid]
			if treaty.treaty_type == Enums.TreatyType.TRADE_DEAL or treaty.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
				if treaty.faction_a == faction_id or treaty.faction_b == faction_id:
					trade_count += 1
	if trade_count == 0:
		return {}
	return {Enums.ResourceType.GOLD: trade_bonus * trade_count}

func apply_senate_income_percentages(faction_id: StringName, income: Dictionary) -> Dictionary:
	if faction_id != &"empire":
		return {}
	var senate_effects := GameManager.policy_system.get_senate_majority_effects(faction_id)
	var delta: Dictionary = {}
	var senate_gold_pct: int = senate_effects.get("gold_income_pct", 0)
	var senate_tech_pct: int = senate_effects.get("tech_income_pct", 0)
	var senate_iron_pct: int = senate_effects.get("iron_income_pct", 0)
	var senate_wood_pct: int = senate_effects.get("wood_income_pct", 0)
	if senate_gold_pct != 0 and income.has(Enums.ResourceType.GOLD):
		delta[Enums.ResourceType.GOLD] = int(income[Enums.ResourceType.GOLD] * senate_gold_pct / 100.0)
	if senate_tech_pct != 0 and income.has(Enums.ResourceType.TECHNOLOGY):
		delta[Enums.ResourceType.TECHNOLOGY] = int(income[Enums.ResourceType.TECHNOLOGY] * senate_tech_pct / 100.0)
	if senate_iron_pct != 0 and income.has(Enums.ResourceType.IRON):
		delta[Enums.ResourceType.IRON] = int(income[Enums.ResourceType.IRON] * senate_iron_pct / 100.0)
	if senate_wood_pct != 0 and income.has(Enums.ResourceType.WOOD):
		delta[Enums.ResourceType.WOOD] = int(income[Enums.ResourceType.WOOD] * senate_wood_pct / 100.0)
	return delta

func region_completion_income_bonus(faction_id: StringName, city: CityState) -> Dictionary:
	var completed_regions := GameManager.get_completed_regions(faction_id)
	if not city.region_id in completed_regions:
		return {}
	var delta: Dictionary = {}
	for res_type in [Enums.ResourceType.GOLD, Enums.ResourceType.IRON, Enums.ResourceType.FOOD, Enums.ResourceType.WOOD, Enums.ResourceType.TECHNOLOGY]:
		delta[res_type] = 2
	return delta

func apply_culture_income_bonuses(faction_id: StringName, income: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	if GameManager.has_culture_bonus(faction_id, "food_bonus") and income.has(Enums.ResourceType.FOOD):
		var val := GameManager.get_culture_bonus_value(faction_id, "food_bonus")
		delta[Enums.ResourceType.FOOD] = int(income[Enums.ResourceType.FOOD] * val)
	if GameManager.has_culture_bonus(faction_id, "tech_bonus") and income.has(Enums.ResourceType.TECHNOLOGY):
		var val := GameManager.get_culture_bonus_value(faction_id, "tech_bonus")
		delta[Enums.ResourceType.TECHNOLOGY] = int(income[Enums.ResourceType.TECHNOLOGY] * val)
	if GameManager.has_culture_bonus(faction_id, "iron_bonus") and income.has(Enums.ResourceType.IRON):
		var val := GameManager.get_culture_bonus_value(faction_id, "iron_bonus")
		delta[Enums.ResourceType.IRON] = int(income[Enums.ResourceType.IRON] * val)
	if GameManager.has_culture_bonus(faction_id, "shard_bonus") and income.has(Enums.ResourceType.SHARD_ESSENCE):
		var val := GameManager.get_culture_bonus_value(faction_id, "shard_bonus")
		delta[Enums.ResourceType.SHARD_ESSENCE] = int(income[Enums.ResourceType.SHARD_ESSENCE] * val)
	return delta

func apply_shard_research_income(faction_id: StringName, income: Dictionary) -> Dictionary:
	var research_effects := GameManager.research_system.get_research_effects(faction_id)
	var shard_pct: int = research_effects.get("shard_essence_pct", 0)
	var shard_flat: int = research_effects.get("shard_harvest_bonus", 0)
	var delta: Dictionary = {}
	if shard_pct > 0 and income.has(Enums.ResourceType.SHARD_ESSENCE):
		delta[Enums.ResourceType.SHARD_ESSENCE] = int(income[Enums.ResourceType.SHARD_ESSENCE] * shard_pct / 100.0)
	if shard_flat > 0:
		delta[Enums.ResourceType.SHARD_ESSENCE] = delta.get(Enums.ResourceType.SHARD_ESSENCE, 0) + shard_flat
	return delta

func apply_debt_penalty(fs: FactionState, income: Dictionary, gold_override: Variant = null) -> Dictionary:
	# gold_override lets a caller thread a SIMULATED running gold balance
	# (e.g. the breakdown looping over multiple owned cities for one turn
	# projection) instead of re-reading the real fs.resources[GOLD] each
	# time. _generate_income() itself never passes it, so the real per-city
	# turn pass keeps reading the live (and, mid-turn, actually-changing)
	# balance exactly as before.
	var current_gold: int = gold_override if gold_override != null else fs.resources.get(Enums.ResourceType.GOLD, 0)
	if current_gold >= 0:
		return {}
	var delta: Dictionary = {}
	for res_type in income:
		delta[res_type] = int(income[res_type] * 0.66) - income[res_type]
	return delta

func apply_wood_production_reduction(income: Dictionary) -> Dictionary:
	if not income.has(Enums.ResourceType.WOOD):
		return {}
	var reduced := int(income[Enums.ResourceType.WOOD] * 0.90)
	return {Enums.ResourceType.WOOD: reduced - income[Enums.ResourceType.WOOD]}

func population_food_consumption(city: CityState) -> int:
	# Population eats less than it used to (pop/60): food income was being
	# almost entirely swallowed by mouths to feed
	return get_province_population(city) / 60

func get_province_population(city: CityState) -> int:
	return LoyaltySystem.get_province_population(city.region_id, city.faction_id)

# Coastal waters: cities adjacent to open water get a real fishing/trade
# bump — +2 food and +1 gold per 2 water(8) hex neighbors (int div), scaled
# by the city's HexHelper neighbor count (6 max). PURE (city in, delta out,
# no mutation) — the single source of truth calculate_city_income() folds
# this into real income. A landlocked city (0 water neighbors) returns {},
# i.e. gains exactly 0.
func apply_coastal_income_bonus(city: CityState) -> Dictionary:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return {}
	var water_neighbors := 0
	for n in HexHelper.get_neighbors(city.hex_pos):
		var tile: HexMapData.TileState = hex_map.get_tile(n)
		if tile != null and tile.terrain == Enums.TerrainType.WATER:
			water_neighbors += 1
	if water_neighbors <= 0:
		return {}
	return {
		Enums.ResourceType.FOOD: water_neighbors * 2,
		Enums.ResourceType.GOLD: water_neighbors / 2,
	}

func calculate_city_income(city: CityState) -> Dictionary:
	# Evacuated (Cinderguard dragon-raid "Evacuate" choice): the settlement is
	# offline for a fixed number of turns — no income at all, not even the
	# base region trickle.
	if city.production_disabled_turns > 0:
		return {}
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
	var captive_buildings: Array[StringName] = [&"labor_camp", &"thrall_quarters", &"captive_processing_camp", &"imperial_work_yard"]
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
			# Lower normal building income by 15%
			bonus = int(float(bonus) * BUILDING_INCOME_MULTIPLIER)
			# Sunstone: +% income from cultural buildings (special_resources_design)
			if building.category == &"cultural":
				var sun_mod := SpecialResourceSystem.modifier_strength(city.faction_id, &"sunstone")
				if sun_mod > 0.0:
					bonus = int(bonus * (1.0 + sun_mod))
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

	# Claimed tier-1 bounty resources (special_resources_design)
	var bounty_income := BountySystem.income_bonus_for_city(city)
	for b_res in bounty_income:
		income[b_res] = income.get(b_res, 0) + bounty_income[b_res]

	# Apply region/faction-wide building effects
	apply_region_effects(income, city)

	# Mobile camp penalty: 80% income when Sunblessed camp is on the move
	if city.is_mobile_camp:
		for res_type in income:
			income[res_type] = int(float(income[res_type]) * 0.8)

	# Coastal waters bonus: added last so it isn't itself diluted by the
	# region-effects/mobile-camp scaling above — the advertised formula
	# (+2 food, +1 gold per 2 water neighbors) always lands exactly.
	_merge_income_delta(income, apply_coastal_income_bonus(city))

	return income

# Ordered special-building effect entries per parent faction. Effects compound
# sequentially (percentage bonuses apply to the running income), so the cache
# preserves the exact scan order (cities in insertion order, buildings in array
# order) and apply_region_effects replays it. Invalidated on building
# add/remove and city ownership changes.
var _region_effects_cache: Dictionary = {} # parent_faction_id -> Array[Dictionary]

func invalidate_region_effects_cache() -> void:
	_region_effects_cache.clear()
	# Building/ownership changes also shift incomes and trade routes
	GameManager.city_topology_epoch += 1

func _get_region_effect_entries(parent_fid: StringName) -> Array:
	if _region_effects_cache.has(parent_fid):
		return _region_effects_cache[parent_fid]
	var entries: Array = []
	for scan_city_id in GameManager.state.cities:
		var scan_city: CityState = GameManager.state.cities[scan_city_id]
		var scan_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(scan_city.faction_id, scan_city.faction_id)
		if scan_parent != parent_fid:
			continue
		for building_id in scan_city.buildings:
			if REGION_WIDE_BUILDING_EFFECTS.has(building_id):
				entries.append({table = 0, region_id = scan_city.region_id, effect = REGION_WIDE_BUILDING_EFFECTS[building_id]})
			if FACTION_WIDE_BUILDING_EFFECTS.has(building_id):
				entries.append({table = 1, effect = FACTION_WIDE_BUILDING_EFFECTS[building_id]})
	_region_effects_cache[parent_fid] = entries
	return entries

func apply_region_effects(income: Dictionary, city: CityState) -> void:
	var faction_id := city.faction_id
	var region_id := city.region_id
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)

	# Replay the cached effect entries in original scan order (see cache note)
	for entry: Dictionary in _get_region_effect_entries(parent_fid):
		var eff: Dictionary = entry.effect
		if entry.table == 0:
			# Region-wide effects: only apply if same region
			if entry.region_id != region_id:
				continue
			match eff.effect:
				"gold_income_pct":
					var gold_bonus := int(income.get(Enums.ResourceType.GOLD, 0) * eff.value / 100.0)
					income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + gold_bonus
				"tech_flat":
					income[Enums.ResourceType.TECHNOLOGY] = income.get(Enums.ResourceType.TECHNOLOGY, 0) + eff.value
				"defense_flat":
					pass  # Defense is not in income; handled in garrison/battle calculations
		else:
			# Faction-wide effects: apply to all faction cities
			if eff.has("faction_filter"):
				if parent_fid != eff.faction_filter:
					continue
			match eff.effect:
				"loyalty_flat":
					pass  # Loyalty bonuses are applied in _update_loyalty, not income
				"trade_income_pct":
					var gold_bonus := int(income.get(Enums.ResourceType.GOLD, 0) * eff.value / 100.0)
					income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + gold_bonus
				"gold_per_relic_building":
					# Count relic/cultural buildings in this city
					var relic_count := 0
					for bid in city.buildings:
						var bld := DataManager.get_building(bid)
						if bld and bld.category == &"cultural":
							relic_count += 1
					income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + relic_count * eff.value

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

	# Don't add growth when population is already at or above cap
	var pop_cap := target_city.get_population_cap()
	if target_city.population >= pop_cap:
		growth = 0

	# Apply growth
	target_city.growth_points += growth
	target_city.population = maxi(0, target_city.population + growth)

	# Population cap: 120% of next level-up threshold — decay excess faster (33% per turn)
	if target_city.population > pop_cap:
		var excess := target_city.population - pop_cap
		var decay := maxi(1, excess / 3)  # Lose 33% of excess per turn
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
	# Worldroot Nexus (Landmark): +1 growth in its own and adjacent regions (any
	# faction's province benefits only from ITS OWN faction's worldroot)
	var wr_region: StringName = LandmarkSystem.worldroot_region_of_faction(faction_id)
	if wr_region != &"":
		if region_id == wr_region or GameManager.state.hex_map.regions_adjacent(region_id, wr_region):
			base_growth += 1
	# special_effects: region_population_growth_bonus (applied once for the whole province)
	for scan_city_id in GameManager.state.cities:
		var scan_city: CityState = GameManager.state.cities[scan_city_id]
		if scan_city.region_id != region_id:
			continue
		if scan_city.faction_id != faction_id:
			continue
		for bid in scan_city.buildings:
			var bld := DataManager.get_building(bid)
			if bld and bld.special_effects.has("region_population_growth_bonus"):
				base_growth += bld.special_effects["region_population_growth_bonus"]
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
		total_food -= province_pop / 60
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
		# Cinderguard: any city/settlement can found new settlements on level-up
		var cg_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
		if cg_parent == &"cinderguard" and city.level >= 2:
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
		invalidate_region_effects_cache()
		# Landmark buildings (e.g. Leyline Well's attunement_circle) change research
		# effects the moment they complete — stale caches would persist for a session.
		if building and building.requires_region_landmark != &"":
			GameManager.research_system._invalidate_cache(city.faction_id)
		EventBus.building_completed.emit(city.city_id, building_id)

func _process_recruit_queue(city: CityState, faction_id: StringName) -> void:
	# Process basic/levy queue (one unit per turn)
	if not city.recruit_queue.is_empty():
		var item: Dictionary = city.recruit_queue[0]
		item.turns_remaining -= 1
		if item.turns_remaining <= 0:
			var unit_data_id: StringName = item.unit_data_id
			city.recruit_queue.remove_at(0)
			_spawn_recruited_unit(city, unit_data_id, faction_id)

	# Process per-building queues (one unit per building per turn — parallel training)
	var finished_keys: Array[StringName] = []
	for building_id in city.building_recruit_queues:
		var queue: Array = city.building_recruit_queues[building_id]
		if queue.is_empty():
			finished_keys.append(building_id)
			continue
		var item: Dictionary = queue[0]
		item.turns_remaining -= 1
		if item.turns_remaining <= 0:
			var unit_data_id: StringName = item.unit_data_id
			queue.remove_at(0)
			_spawn_recruited_unit(city, unit_data_id, faction_id)
	# Clean up empty queues
	for key in finished_keys:
		city.building_recruit_queues.erase(key)

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
	# Titan Forge-Ruin: constructs muster already Trained
	if unit_data.tags.has("construct") and LandmarkSystem.has_landmark(faction_id, &"titan_forge_ruin"):
		instance.veterancy_level = 1
		instance.experience = UnitInstance.VETERANCY_XP_THRESHOLDS[0]

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

# ── Siege pressure model ─────────────────────────────────────
# siege_turns is accumulated pressure (float) vs get_siege_threshold(city).
const SIEGE_FILL_BASE := 0.75          # infantry-army blockade fill per turn
const SIEGE_FACTOR_ENGINE := 1.8       # construct / tiles>=4 (batters walls)
const SIEGE_FACTOR_HEAVY := 1.3        # heavy / monster / beast
const SIEGE_FACTOR_BASE := 1.0         # infantry / ranged baseline
const SIEGE_FACTOR_LIGHT := 0.5        # light / fast raiders
const SIEGE_OVERRUN_BONUS := 2.0       # garrison overrun (decisive)
const SIEGE_RELIEF_WIN := 1.0          # besieger wins a relief battle on the hex
const SIEGE_RELIEF_STALEMATE := 0.4    # both survive, roughly even
const SIEGE_POINTWIN_GAP := 0.25       # strength-fraction gap that counts as a point win
const SIEGE_DECAY_ABSENT := 1.0        # drain per turn when no besieger present
const SIEGE_RELIEF_LOSS := 2.0         # drain when a relief army beats the besieger
const SIEGE_BESIEGER_ATTRITION := 0.025 # 2.5% max_hp/turn to besieging units
const SIEGE_GARRISON_ATTRITION := 0.09  # 9%/turn garrison_hp_ratio decline (besieged suffer more)

func get_siege_threshold(city: CityState) -> int:
	var t := 4
	if city.buildings.has(&"steppe_watchtower"):
		t = 5
	var parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
	var eff := GameManager.research_system.get_research_effects(parent)
	var rdef: int = eff.get("defense_bonus", 0)
	var cpct: int = eff.get("city_defense_pct", 0)
	if rdef >= 5 or cpct >= 15:
		t += 1
	if rdef >= 10 or cpct >= 30:
		t += 1
	return t

func _unit_siege_factor(ud: UnitData) -> float:
	if ud == null:
		return SIEGE_FACTOR_BASE
	if ud.tags.has("construct") or ud.tiles_per_entity >= 4:
		return SIEGE_FACTOR_ENGINE
	if ud.tags.has("heavy") or ud.tags.has("monster") or ud.tags.has("beast"):
		return SIEGE_FACTOR_HEAVY
	if ud.tags.has("light") or ud.tags.has("fast"):
		return SIEGE_FACTOR_LIGHT
	return SIEGE_FACTOR_BASE

func _army_siege_weight(army: ArmyState) -> float:
	if army == null or army.units.is_empty():
		return 0.0
	var total := 0.0
	for unit in army.units:
		total += _unit_siege_factor(DataManager.get_unit(unit.unit_data_id))
	return total / float(army.units.size())

func add_siege_pressure(city: CityState, amount: float) -> void:
	if city == null or not city.is_under_siege:
		return
	city.siege_turns = maxf(0.0, city.siege_turns + amount)
	EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))

func award_siege_overrun(city: CityState) -> void:
	add_siege_pressure(city, SIEGE_OVERRUN_BONUS)

func award_siege_battle(city: CityState, besieger_alive: bool, enemy_alive: bool, besieger_frac: float, enemy_frac: float) -> void:
	if besieger_alive and not enemy_alive:
		add_siege_pressure(city, SIEGE_RELIEF_WIN)
	elif besieger_alive and enemy_alive:
		if besieger_frac - enemy_frac >= SIEGE_POINTWIN_GAP:
			add_siege_pressure(city, SIEGE_RELIEF_WIN)
		else:
			add_siege_pressure(city, SIEGE_RELIEF_STALEMATE)
	elif not besieger_alive:
		add_siege_pressure(city, -SIEGE_RELIEF_LOSS)

func _process_sieges(faction_id: StringName) -> void:
	# Pressure model: fill while the besieger holds the hex, decay when absent.
	# Runs on the besieging faction's turn (siege_faction == faction_id).
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not city.is_under_siege:
			continue
		if city.siege_faction != faction_id:
			continue

		var besiegers := _besiegers_present(city)

		if besiegers.is_empty():
			# No one holding the siege — drain, and lift at zero.
			city.siege_turns = maxf(0.0, city.siege_turns - SIEGE_DECAY_ABSENT)
			if city.siege_turns <= 0.0:
				break_siege(city.city_id)
			else:
				EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))
			continue

		# Fill scaled by the best besieging army's composition.
		var weight := 0.0
		for a: ArmyState in besiegers:
			weight = maxf(weight, _army_siege_weight(a))
		city.siege_turns += SIEGE_FILL_BASE * weight

		# Attrition: besieged garrison suffers more than the besieger.
		_apply_besieger_attrition(besiegers)
		city.garrison_hp_ratio = maxf(0.0, city.garrison_hp_ratio - SIEGE_GARRISON_ATTRITION)

		# Attrition walls (Jungle Traps, Serpent's Maze): buildings that carry
		# a besieger_attrition special_effect bleed the besieging armies every
		# siege turn, on top of the baseline attrition above. Data-driven so
		# any faction's attrition-style wall gets the same behavior.
		_apply_wall_besieger_attrition(city, besiegers)

		EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))

		if city.siege_turns >= get_siege_threshold(city):
			# Skulloath player gets a choice: capture, loot, or raze.
			if faction_id == &"skulloath" and faction_id == GameManager.state.player_faction_id:
				EventBus.siege_choice_needed.emit(city.city_id, faction_id)
			else:
				_capture_city(city)

func _besiegers_present(city: CityState) -> Array:
	var out: Array = []
	for a: ArmyState in GameManager.get_armies_at_tile(city.hex_pos):
		if a.faction_id == city.siege_faction and not a.is_garrison:
			out.append(a)
	return out

func _apply_besieger_attrition(besiegers: Array) -> void:
	for army: ArmyState in besiegers:
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud:
				unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * SIEGE_BESIEGER_ATTRITION))

## Attrition walls: sums the besieged city's buildings' besieger_attrition
## special_effect (Jungle Traps, Serpent's Maze — Tainted Jade's "traps" wall
## line) and, if any, deals attrition_sum% of EACH besieging unit's max HP
## per siege turn (e.g. jungle_traps 2.0 -> 2% per unit; serpents_maze 4.0 ->
## 4%; the two don't stack in practice since maze replaces traps on upgrade,
## but the sum applies if somehow both are present). Per-unit percentage
## (not a flat pool split across the army) so large siege stacks — the
## fantasy this wall targets — still take real, size-scaling damage; a flat
## shared pool rounds to 0 per unit once an army is large enough to dilute
## it, which would make the wall inert exactly when it matters most. Unlike
## the flat SIEGE_BESIEGER_ATTRITION drip above, this can kill units
## outright — see _apply_army_wall_damage. Logs a turn_log line when it
## draws blood.
func _apply_wall_besieger_attrition(city: CityState, besiegers: Array) -> void:
	var attrition_sum := 0.0
	var source_name := ""
	for b_id in city.buildings:
		var bd: BuildingData = DataManager.get_building(b_id)
		if bd == null:
			continue
		var v: float = float(bd.special_effects.get("besieger_attrition", 0.0))
		if v > 0.0:
			attrition_sum += v
			if source_name == "":
				source_name = bd.display_name

	if attrition_sum <= 0.0:
		return

	var dealt := 0
	for army: ArmyState in besiegers:
		dealt += _apply_army_wall_damage(army, attrition_sum)

	if dealt > 0:
		TurnManager.turn_log.append({
			"type": "siege",
			"text": "%s bleed the besiegers at %s: %d damage" % [source_name, city.get_display_name(), dealt],
		})

## Deals attrition_pct% of each besieging unit's max HP (min 1 HP per unit,
## mirroring the floor used by _apply_besieger_attrition/_apply_terrain_attrition
## elsewhere in this file), but — unlike those flat drips — kills units whose
## HP drops to 0 or below and removes them from the army, disbanding the
## army entirely if none survive (mirrors the emptied-army cleanup in
## _desert_unpaid_units). Returns the actual HP removed (<= the nominal
## per-unit total if a unit died before absorbing its full share).
func _apply_army_wall_damage(army: ArmyState, attrition_pct: float) -> int:
	if army == null or army.units.is_empty():
		return 0

	var dealt := 0
	var survivors: Array[UnitInstance] = []
	for unit: UnitInstance in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			survivors.append(unit)
			continue
		var per_unit := maxi(1, int(ud.max_hp * attrition_pct * 0.01))
		var actual := mini(per_unit, unit.current_hp)
		unit.current_hp -= actual
		dealt += actual
		if unit.current_hp > 0:
			survivors.append(unit)
	army.units = survivors

	if army.units.is_empty():
		GameManager.remove_army(army.army_id)

	return dealt

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

	GameManager.invalidate_completion_cache()
	invalidate_region_effects_cache()
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
	# Research: loot_bonus_pct increases loot
	var loot_parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(looter_id, looter_id)
	var loot_r_eff := GameManager.research_system.get_research_effects(loot_parent_fid)
	var loot_bonus: float = 1.0 + float(loot_r_eff.get("loot_bonus_pct", 0)) / 100.0
	var gold_loot: int = int(60 * loot_mult * loot_bonus)
	var wood_loot: int = int(45 * loot_mult * loot_bonus)
	var iron_loot: int = int(25 * loot_mult * loot_bonus)
	var food_loot: int = int(35 * loot_mult * loot_bonus)

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
	invalidate_region_effects_cache()

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

	# Field units that draw gold upkeep, so bankruptcy desertion can pick the
	# most expensive ones first. Garrisons and elderbeasts are exempt.
	var desertion_candidates: Array = []
	for army: ArmyState in GameManager.get_faction_armies(faction_id):
		# Terrain upkeep modifier (jungle/desert/wastes etc.)
		var terrain_mult: float = TurnManager.get_terrain_upkeep_modifier(army)
		var can_desert: bool = not army.is_garrison and army.elderbeast_id == &""
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
						if can_desert and cost > 0:
							desertion_candidates.append({"army": army, "unit": unit, "gold": cost})
					fs.resources[res_type] -= cost
		# Commander upkeep (only while assigned to army; skip for elderbeast armies)
		if army.commander != null and army.elderbeast_id == &"":
			var level_mult := 1.0 + (army.commander.level - 1) * 0.5
			for res_type in CommanderSystem.COMMANDER_UPKEEP:
				var cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				if fs.resources.has(res_type):
					fs.resources[res_type] -= cost

	# Building upkeep: deduct per-building costs from faction resources
	var has_city := false
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		has_city = true
		for building_id in city.buildings:
			var bld: BuildingData = DataManager.get_building(building_id)
			if bld == null:
				continue
			var upkeep := get_building_upkeep(bld)
			for res_type in upkeep:
				var cost: int = upkeep[res_type]
				if upkeep_red_pct > 0:
					cost = int(cost * (1.0 - upkeep_red_pct))
				if fs.resources.has(res_type):
					fs.resources[res_type] -= cost

	# Bankruptcy desertion: if the treasury is in the red after upkeep AND the
	# standing army costs more gold than the economy earns, the highest-paid
	# soldiers desert until the army is affordable again. This trims an
	# over-recruited army down to what income supports instead of leaving the
	# faction in a silent, permanent negative-gold softlock. Deserters' unpaid
	# wages are credited back. See docs/economy_audit.md §1.
	# City-less nomads (Shardhorde/Sunblessed) are exempt — their zero-gold
	# economy is a separate structural issue, not an over-recruit.
	if has_city and fs.resources.get(Enums.ResourceType.GOLD, 0) < 0 and not desertion_candidates.is_empty():
		_desert_unpaid_units(faction_id, fs, desertion_candidates)

## Removes the most expensive field units until the army's gold upkeep no longer
## exceeds the faction's gold income ("desert until income balances"), crediting
## back each deserter's unpaid wages. Does nothing if the army is already
## affordable (the deficit is then building/commander-driven, not the army).
func _desert_unpaid_units(faction_id: StringName, fs: FactionState, candidates: Array) -> void:
	var gold_income: int = GameManager.diplomacy_system.get_faction_resource_income(faction_id, Enums.ResourceType.GOLD)
	var army_gold_upkeep := 0
	for entry in candidates:
		army_gold_upkeep += int(entry["gold"])
	if army_gold_upkeep <= gold_income:
		return  # army is affordable; the shortfall isn't the army's fault

	candidates.sort_custom(func(a, b): return a["gold"] > b["gold"])
	var deserted_names: Array = []
	var emptied_armies: Array[StringName] = []
	for entry in candidates:
		if army_gold_upkeep <= gold_income:
			break
		var army: ArmyState = entry["army"]
		var unit: UnitInstance = entry["unit"]
		var idx := army.units.find(unit)
		if idx == -1:
			continue
		army.units.remove_at(idx)
		army_gold_upkeep -= int(entry["gold"])
		fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + int(entry["gold"])
		var ud := DataManager.get_unit(unit.unit_data_id)
		deserted_names.append(ud.display_name if ud else String(unit.unit_data_id))
		if army.units.is_empty() and not emptied_armies.has(army.army_id):
			emptied_armies.append(army.army_id)
	for army_id in emptied_armies:
		GameManager.remove_army(army_id)
	if not deserted_names.is_empty():
		EventBus.units_deserted.emit(faction_id, deserted_names, deserted_names.size())

func get_building_upkeep(building: BuildingData) -> Dictionary:
	if not building.upkeep_cost.is_empty():
		return building.upkeep_cost
	return DEFAULT_BUILDING_UPKEEP.get(clampi(building.required_capital_level, 1, 3), {0: 3})

func _process_captive_decay(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var captives: int = fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
	if captives <= 0:
		return

	# Each camp-type building consumes captives per turn (they die, escape, get
	# worked to death). Shared with the income breakdown tooltip's "Camp Decay"
	# row (see calculate_captive_camp_decay) so the two counts can't drift.
	var decay := calculate_captive_camp_decay(faction_id)
	# Note: Blood Altar, Void Pit, Wretched Pit, Tomb Scholar's Hall, Pilgrim's Rest,
	# Warriors' Longhouse, Ember Foundry, Lunar Observatory, Imperial Work Yard
	# all consume captives in _apply_faction_income_modifier() directly

	# Natural captive attrition: even without camps, 1 captive escapes/dies per 5 turns
	if decay == 0:
		# No camp buildings — slow natural decay
		if GameManager.state.current_turn % 5 == 0:
			decay = 1

	if decay > 0:
		fs.resources[Enums.ResourceType.CAPTIVES] = maxi(0, captives - decay)

func calculate_captive_camp_decay(faction_id: StringName) -> int:
	# Count labor-camp-type buildings across all faction cities and convert to
	# the per-turn captive decay they cause. Pure/read-only.
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
	var decay := 0
	decay += labor_camp_count * 3        # Labor Camp: -3 captives/turn each
	decay += thrall_count * 2             # Thrall Quarters: -2 captives/turn each
	decay += processing_camp_count * 4    # Captive Processing Camp: -4 captives/turn each
	return decay

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
	# Spawn rebel army at city hex using dedicated rebel units
	var rebel_army := ArmyState.new()
	rebel_army.army_id = GameManager.state.generate_id()
	rebel_army.faction_id = &"rebels"
	rebel_army.hex_pos = city.hex_pos

	# City development score determines rebel strength and variety
	var dev_score: int = city.population + city.buildings.size()
	var num_units := clampi(dev_score / 40, 2, 5)

	# Rebel unit pools by tier
	const REBEL_LOW: Array[StringName] = [&"rebel_militia", &"rebel_archer"]
	const REBEL_MID: Array[StringName] = [&"rebel_militia", &"rebel_archer", &"rebel_horseman"]
	const REBEL_HIGH: Array[StringName] = [&"rebel_militia", &"rebel_archer", &"rebel_horseman", &"rebel_warbeast", &"rebel_brutes"]

	var pool: Array[StringName]
	if dev_score < 30:
		pool = REBEL_LOW
	elif dev_score < 60:
		pool = REBEL_MID
	else:
		pool = REBEL_HIGH

	# Pick 2-3 different unit types for variety
	var num_types := clampi(dev_score / 40, 2, 3)
	var shuffled_pool := pool.duplicate()
	shuffled_pool.shuffle()
	var chosen_types: Array[UnitData] = []
	for i in mini(num_types, shuffled_pool.size()):
		var ud := DataManager.get_unit(shuffled_pool[i])
		if ud:
			chosen_types.append(ud)
	if chosen_types.is_empty():
		var fallback := DataManager.get_unit(&"rebel_militia")
		if fallback:
			chosen_types.append(fallback)

	# Distribute units across chosen types
	for i in num_units:
		var ud: UnitData = chosen_types[i % chosen_types.size()]
		var instance := UnitInstance.new()
		instance.init_from_data(ud, GameManager.state.generate_id())
		# Rebels are less experienced — reduce HP by 15%
		instance.current_hp = maxi(1, int(instance.current_hp * 0.85))
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
	GameManager.invalidate_completion_cache()
	invalidate_region_effects_cache()
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
		# Never allow building on water
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if terrain < 0 or tile.terrain == terrain:
			result.append(neighbor)
	return result

## The building_id a tile is exclusively reserved for (its deposit's extractor,
## or its landmark's unique building), or &"" if the tile carries no such
## reservation and is buildable by anything terrain-eligible.
func _tile_reservation_owner(tile: HexMapData.TileState) -> StringName:
	if tile.special_id != &"":
		return SpecialResourceSystem.SPECIAL_TYPES.get(tile.special_id, {}).get("extractor_id", &"")
	if tile.landmark_id != &"":
		return LandmarkSystem.LANDMARK_TYPES.get(tile.landmark_id, {}).get("building_id", &"")
	# Bounty tiles (bounty_id) stay generally buildable for now — that layer's
	# density is being doubled separately, so it is deliberately NOT reserved.
	return &""

## Single source of truth for the "deposit/landmark tiles are reserved" rule,
## applied on top of a terrain-filtered candidate list. Shared by the player
## build-tile UI, start_building's validation, and the AI auto-pick path (all
## three only ever call get_valid_tiles_for_building).
## - Generic buildings: reserved tiles (owned by a DIFFERENT building) are
##   dropped entirely; other candidates pass through unchanged.
## - The extractor/landmark building itself: if its own deposit/landmark tile
##   is among the candidates (i.e. within the city's adjacent build range),
##   ONLY that tile (those tiles) are valid — it cannot be built elsewhere.
## - Fallback: if that building's deposit/landmark is NOT within build range
##   (region-wide resources can sit anywhere in a possibly large region, and
##   landmarks are only guaranteed a city within distance 2, which is outside
##   the distance-1 neighbor ring used for building placement), it falls back
##   to any other unreserved candidate tile so it stays buildable somewhere.
func _apply_tile_reservation(building: BuildingData, candidates: Array[Vector2i]) -> Array[Vector2i]:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return candidates
	var own_tiles: Array[Vector2i] = []
	var free_tiles: Array[Vector2i] = []
	for coord in candidates:
		var tile := hex_map.get_tile(coord)
		if tile == null:
			continue
		var reserved_for: StringName = _tile_reservation_owner(tile)
		if reserved_for == &"":
			free_tiles.append(coord)
		elif reserved_for == building.id:
			own_tiles.append(coord)
		# else: reserved for a different building's deposit/landmark -> excluded
	if not own_tiles.is_empty():
		return own_tiles
	return free_tiles

func get_valid_tiles_for_building(city: CityState, building: BuildingData) -> Array[Vector2i]:
	# For upgrades, use the same tile as the building being upgraded
	if building.upgrades_from != &"" and city.building_tiles.has(building.upgrades_from):
		return [city.building_tiles[building.upgrades_from] as Vector2i]
	var candidates := get_valid_tiles_for_building_terrain(city, building.required_terrain)
	return _apply_tile_reservation(building, candidates)

func get_free_adjacent_tiles(city: CityState) -> Array[Vector2i]:
	# All adjacent tiles not occupied by a building (any terrain)
	return get_valid_tiles_for_building_terrain(city, -1)

# ── Public API ────────────────────────────────────────────────

func demolish_building(city_id: StringName, building_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false
	if not city.buildings.has(building_id):
		return false
	# Check no dependent upgrade is built on top
	for other_id in city.buildings:
		var other_bld: BuildingData = DataManager.get_building(other_id)
		if other_bld and other_bld.upgrades_from == building_id:
			return false  # Cannot demolish: an upgrade depends on this building
	# Also check build queue for pending upgrades from this building
	for item in city.build_queue:
		var queued_bld: BuildingData = DataManager.get_building(item.building_id)
		if queued_bld and queued_bld.upgrades_from == building_id:
			return false
	# Remove from city
	var building: BuildingData = DataManager.get_building(building_id)
	city.buildings.erase(building_id)
	city.building_tiles.erase(building_id)
	invalidate_region_effects_cache()
	# Landmark buildings change research effects when removed — invalidate cache to prevent staleness
	if building and building.requires_region_landmark != &"":
		GameManager.research_system._invalidate_cache(city.faction_id)
	# Refund 1/3 of build cost
	if building:
		var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
		if fs:
			for res_type in building.build_cost:
				var refund := int(building.build_cost[res_type] / 3.0)
				if refund > 0:
					fs.resources[res_type] = fs.resources.get(res_type, 0) + refund
	EventBus.building_demolished.emit(city_id, building_id)
	return true

func get_demolish_refund(building_id: StringName) -> Dictionary:
	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return {}
	var refund: Dictionary = {}
	for res_type in building.build_cost:
		var amount := int(building.build_cost[res_type] / 3.0)
		if amount > 0:
			refund[res_type] = amount
	return refund

func has_dependent_upgrade(city: CityState, building_id: StringName) -> bool:
	for other_id in city.buildings:
		var other_bld: BuildingData = DataManager.get_building(other_id)
		if other_bld and other_bld.upgrades_from == building_id:
			return true
	for item in city.build_queue:
		var queued_bld: BuildingData = DataManager.get_building(item.building_id)
		if queued_bld and queued_bld.upgrades_from == building_id:
			return true
	return false

func get_available_buildings(city: CityState, include_slot_blocked: bool = false) -> Array[BuildingData]:
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

	# Loop invariants hoisted out of the 246-building scan: the loop mutates
	# nothing, so slots and per-key valid-tile results cannot change inside it.
	# Keyed by (required_terrain, requires_region_resource, requires_region_landmark)
	# rather than terrain alone: those three fields are exactly what
	# get_valid_tiles_for_building's result depends on (see _apply_tile_reservation),
	# and in practice each non-empty resource/landmark id maps 1:1 to a single
	# building id, so buildings sharing a key always get the same tile list.
	var available_slots := city.get_available_building_slots()
	var valid_tiles_by_key: Dictionary = {} # "terrain|resource|landmark" -> Array[Vector2i]

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
		# Skip if required research not completed
		if building.requires_research != &"":
			var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
			var fstate: FactionState = GameManager.state.faction_states.get(parent_fid)
			if fstate == null or not fstate.completed_research.has(building.requires_research):
				continue
		# Extractors: only buildable where the city's region holds the deposit
		if building.requires_region_resource != &"":
			if SpecialResourceSystem.special_in_region(city.region_id) != building.requires_region_resource:
				continue
		# Landmark buildings: only buildable where the city's region holds the landmark
		if building.requires_region_landmark != &"":
			if LandmarkSystem.landmark_in_region(city.region_id) != building.requires_region_landmark:
				continue
		# Doctrine fork: if another building of the same exclusive_group exists
		# (or is queued) ANYWHERE in the faction, this one is locked forever
		if building.exclusive_group != &"" and _faction_has_exclusive_group(city.faction_id, building.exclusive_group, building_id):
			continue
		# Skip if city level too low
		if city.level < building.required_capital_level:
			continue
		# Skip capital-only buildings in non-capital cities
		if building.requires_capital and not city.is_capital:
			continue
		# Frontier structures are settlement-exclusive
		if building.settlement_only and not city.is_settlement:
			continue
		# Skip if no valid adjacent tile available (identical result to
		# get_valid_tiles_for_building, with the tile query memoized)
		var has_valid_tile: bool
		if building.upgrades_from != &"" and city.building_tiles.has(building.upgrades_from):
			has_valid_tile = true # upgrade reuses the existing building's tile
		else:
			var tile_key: String = "%d|%s|%s" % [building.required_terrain, building.requires_region_resource, building.requires_region_landmark]
			if not valid_tiles_by_key.has(tile_key):
				var terrain_candidates := get_valid_tiles_for_building_terrain(city, building.required_terrain)
				valid_tiles_by_key[tile_key] = _apply_tile_reservation(building, terrain_candidates)
			has_valid_tile = not (valid_tiles_by_key[tile_key] as Array).is_empty()
		if not has_valid_tile:
			continue
		if building.upgrades_from == &"":
			# Base building: needs a free slot
			if available_slots <= 0 and not include_slot_blocked:
				continue
			result.append(building)
		else:
			# Upgrade building: city must have the prerequisite
			if city.buildings.has(building.upgrades_from):
				result.append(building)
	return result

## True if any city of the faction owns (or is building) a DIFFERENT member of
## the given exclusive doctrine group
func _faction_has_exclusive_group(faction_id: StringName, group: StringName, except_building: StringName) -> bool:
	for oc_id in GameManager.state.cities:
		var oc: CityState = GameManager.state.cities[oc_id]
		if oc.faction_id != faction_id:
			continue
		for bid in oc.buildings:
			if bid == except_building:
				continue
			var bd: BuildingData = DataManager.get_building(bid)
			if bd and bd.exclusive_group == group:
				return true
		for item in oc.build_queue:
			if item.building_id == except_building:
				continue
			var qbd: BuildingData = DataManager.get_building(item.building_id)
			if qbd and qbd.exclusive_group == group:
				return true
	return false

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
	# Extractors: only buildable where the city's region holds the deposit
	if building.requires_region_resource != &"":
		if SpecialResourceSystem.special_in_region(city.region_id) != building.requires_region_resource:
			return false
	# Landmark buildings: only buildable where the city's region holds the landmark
	if building.requires_region_landmark != &"":
		if LandmarkSystem.landmark_in_region(city.region_id) != building.requires_region_landmark:
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
	# Research: building cost reduction
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
	var build_r_eff := GameManager.research_system.get_research_effects(parent_fid)
	var build_cost_red: int = build_r_eff.get("building_cost_reduction_pct", 0)
	if build_cost_red > 0:
		for res_type in adjusted_cost:
			adjusted_cost[res_type] = int(adjusted_cost[res_type] * (100 - build_cost_red) / 100.0)
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
	# Building special_effects: recruit_cost_discount_pct
	var total_discount_pct := 0
	for bid in city.buildings:
		var bld := DataManager.get_building(bid)
		if bld and bld.special_effects.has("recruit_cost_discount_pct"):
			total_discount_pct += int(bld.special_effects["recruit_cost_discount_pct"])
	# Research: recruitment cost reduction
	var recruit_parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
	var recruit_r_eff := GameManager.research_system.get_research_effects(recruit_parent_fid)
	total_discount_pct += recruit_r_eff.get("recruitment_cost_reduction", 0)
	total_discount_pct += BountySystem.recruit_discount_for(city, unit_data)
	# Moonsilver: heavy-unit recruit discount (special_resources_design)
	total_discount_pct += SpecialResourceSystem.recruit_discount_for(city.faction_id, unit_data)
	# Dragonbone Fields / Titan Forge-Ruin: landmark recruit discounts
	total_discount_pct += LandmarkSystem.recruit_discount_for(city.faction_id, unit_data)
	# Cap stacked discounts at 75% to prevent negative costs (resource-generation exploit)
	total_discount_pct = mini(total_discount_pct, 75)
	if total_discount_pct > 0:
		for res_type in adjusted_recruit:
			adjusted_recruit[res_type] = int(adjusted_recruit[res_type] * (100 - total_discount_pct) / 100.0)
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
	# Research: recruit speed bonus
	recruit_time -= recruit_r_eff.get("recruit_speed_bonus", 0)
	recruit_time = maxi(1, recruit_time)

	# Determine which building unlocks this unit (for per-building queue)
	var unlocking_building: StringName = &""
	for building_id in city.buildings:
		var current_id: StringName = building_id
		while current_id != &"":
			var building: BuildingData = DataManager.get_building(current_id)
			if building == null:
				break
			if building.unlocks_units.has(unit_data_id):
				unlocking_building = building_id # Use the actual built building, not predecessor
				break
			current_id = building.upgrades_from
		if unlocking_building != &"":
			break

	if unlocking_building == &"":
		# Basic/faction unit with no building — use shared queue
		city.recruit_queue.append({unit_data_id = unit_data_id, turns_remaining = recruit_time})
	else:
		# Per-building queue — parallel training
		if not city.building_recruit_queues.has(unlocking_building):
			city.building_recruit_queues[unlocking_building] = []
		city.building_recruit_queues[unlocking_building].append({unit_data_id = unit_data_id, turns_remaining = recruit_time})
	return true

func cancel_recruitment(city_id: StringName, queue_type: String, queue_index: int, building_id: StringName = &"") -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return false
	var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
	if fs == null:
		return false
	var item: Dictionary
	if queue_type == "basic":
		if queue_index < 0 or queue_index >= city.recruit_queue.size():
			return false
		item = city.recruit_queue[queue_index]
		city.recruit_queue.remove_at(queue_index)
	elif queue_type == "building":
		if not city.building_recruit_queues.has(building_id):
			return false
		var bq: Array = city.building_recruit_queues[building_id]
		if queue_index < 0 or queue_index >= bq.size():
			return false
		item = bq[queue_index]
		bq.remove_at(queue_index)
	else:
		return false
	# Refund 80% of recruitment cost
	var unit_data := DataManager.get_unit(item.unit_data_id)
	if unit_data:
		for res_type in unit_data.recruit_cost:
			var refund := int(unit_data.recruit_cost[res_type] * 0.8)
			fs.resources[res_type] = fs.resources.get(res_type, 0) + refund
		# Refund population
		var pop_cost := unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
		city.population += pop_cost
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
	&"cinderguard": [&"cinderguard_warden", &"cinderguard_warden"],
	&"forsaken": [&"shadow_thrall", &"shadow_thrall"],
	&"ivoryscar": [&"ivoryscar_seeker", &"ivoryscar_seeker"],
	&"sunblessed": [&"sunblessed_pilgrim", &"sunblessed_pilgrim"],
	&"independent": [&"citizen_phalanx", &"hoplite_guard"],
}

func _grow_independent_garrison(city: CityState) -> void:
	var turn: int = GameManager.state.current_turn
	if turn % 5 != 0:
		return
	# Count total units in garrison
	var total := 0
	for entry in city.garrison_units:
		total += entry.count
	if total >= 9:
		return
	# Build pool based on turn number
	var pool: Array[StringName] = [&"citizen_phalanx", &"toxotes"]
	if turn >= 15:
		pool.append(&"citizen_cavalry")
	if turn >= 20:
		pool.append(&"hoplite_guard")
	if turn >= 25:
		pool.append(&"war_ballista")
	var pick: StringName = pool[randi() % pool.size()]
	# Add to existing entry or create new one
	var found := false
	for entry in city.garrison_units:
		if entry.unit_id == pick:
			entry.count += 1
			found = true
			break
	if not found:
		city.garrison_units.append({unit_id = pick, count = 1})

func _get_garrison_bonus_units(city: CityState) -> Array[StringName]:
	var bonus_units: Array[StringName] = []
	for building_id in city.buildings:
		var bld := DataManager.get_building(building_id)
		if bld and bld.category == &"military" and not bld.unlocks_units.is_empty():
			bonus_units.append(bld.unlocks_units[0])
			if bonus_units.size() >= 4:
				break
	return bonus_units

func _get_garrison_composition(city: CityState) -> Array:
	var units: Array = GARRISON_UNITS.get(city.faction_id, GARRISON_UNITS[&"empire"])
	var militia: StringName = units[0]
	var regular: StringName = units[1]
	# Building bonus: +1 militia per military building (barracks, training_ground, etc.)
	var building_bonus := 0
	for bid in city.buildings:
		if bid in [&"barracks", &"training_ground", &"war_forge", &"fortification", &"watchtower"]:
			building_bonus += 1
	var result: Array = []
	match city.level:
		1: result = [{unit_id = militia, count = 5 + building_bonus}]
		2: result = [{unit_id = militia, count = 5 + building_bonus}, {unit_id = regular, count = 3}]
		3: result = [{unit_id = militia, count = 6 + building_bonus}, {unit_id = regular, count = 5}]
		4: result = [{unit_id = militia, count = 7 + building_bonus}, {unit_id = regular, count = 6}]
		5: result = [{unit_id = militia, count = 8 + building_bonus}, {unit_id = regular, count = 8}]
		_: result = [{unit_id = militia, count = 5 + building_bonus}]
	# Building special_effects: garrison_strength_bonus (adds extra militia)
	var garrison_bonus_count := 0
	for bid in city.buildings:
		var bld := DataManager.get_building(bid)
		if bld and bld.special_effects.has("garrison_strength_bonus"):
			garrison_bonus_count += int(float(bld.special_effects["garrison_strength_bonus"]) * 10)
	if garrison_bonus_count > 0 and result.size() > 0:
		result[0].count += garrison_bonus_count
	# Add bonus garrison units from military buildings
	var bonus := _get_garrison_bonus_units(city)
	for bonus_uid in bonus:
		result.append({unit_id = bonus_uid, count = 1})
	# Independent cities use persistent garrison that grows over time
	if city.faction_id == &"independent" and city.garrison_units.size() > 0:
		return city.garrison_units.duplicate(true)
	return result

func create_garrison_army(city: CityState) -> ArmyState:
	var garrison_def: Array = _get_garrison_composition(city)
	var army := ArmyState.new()
	army.army_id = GameManager.state.generate_id()
	army.faction_id = city.faction_id
	army.hex_pos = city.hex_pos
	army.movement_remaining = 0.0
	army.has_moved = true # garrison doesn't move
	army.is_garrison = true

	# Research: garrison strength bonus (extra HP for garrison units)
	var gar_parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
	var gar_r_eff := GameManager.research_system.get_research_effects(gar_parent_fid)
	var garrison_pct: float = float(gar_r_eff.get("garrison_strength_pct", 0)) / 100.0
	for entry in garrison_def:
		var uid: StringName = entry.unit_id
		var unit_data := DataManager.get_unit(uid)
		if unit_data == null:
			continue
		for i in entry.count:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, GameManager.state.generate_id())
			if garrison_pct > 0.0:
				instance.current_hp += int(float(instance.current_hp) * garrison_pct)
			army.units.append(instance)

	# Independent cities: order units with melee on flanks, ranged in middle
	if city.faction_id == &"independent" and army.units.size() > 1:
		var melee_units: Array[UnitInstance] = []
		var ranged_units: Array[UnitInstance] = []
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud and ud.attack_range >= 2:
				ranged_units.append(unit)
			else:
				melee_units.append(unit)
		army.units.clear()
		# Split melee: half left flank, half right flank
		var left_count := melee_units.size() / 2
		for i in left_count:
			army.units.append(melee_units[i])
		for unit in ranged_units:
			army.units.append(unit)
		for i in range(left_count, melee_units.size()):
			army.units.append(melee_units[i])

	# Apply garrison HP ratio (damaged garrison from previous battles)
	if city.garrison_hp_ratio <= 0.0:
		for unit in army.units:
			unit.current_hp = 1
	elif city.garrison_hp_ratio < 1.0:
		for unit in army.units:
			unit.current_hp = maxi(1, int(unit.current_hp * city.garrison_hp_ratio))

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

# Hex -> city index. Insertions are caught by the size check; hex_pos moves
# (Sunblessed camps) and wholesale state replacement (new_game/load_game) must
# call invalidate_city_hex_index() explicitly.
var _city_hex_index: Dictionary = {} # Vector2i -> CityState
var _city_hex_index_dirty := true

func invalidate_city_hex_index() -> void:
	_city_hex_index_dirty = true
	_settlement_sphere_dirty = true
	GameManager.city_topology_epoch += 1

func get_city_at_hex(hex_pos: Vector2i) -> CityState:
	var cities: Dictionary = GameManager.state.cities
	if _city_hex_index_dirty or _city_hex_index.size() != cities.size():
		_city_hex_index.clear()
		for city_id in cities:
			var city: CityState = cities[city_id]
			# Preserve old first-match-in-insertion-order semantics on collision
			if not _city_hex_index.has(city.hex_pos):
				_city_hex_index[city.hex_pos] = city
		_city_hex_index_dirty = false
	return _city_hex_index.get(hex_pos)

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
	# Coastal waters: fishing/trade — food-primary, small gold trickle. Was
	# absent entirely (water tiles were skipped in the adjacency loop below),
	# which made the preview promise income a founded coastal city never
	# actually got from calculate_city_income().
	Enums.TerrainType.WATER:     {3: 4, 0: 1},
}

const SETTLEMENT_FOUNDING_COST := {
	Enums.ResourceType.GOLD: 80,
	Enums.ResourceType.WOOD: 40,
	Enums.ResourceType.FOOD: 30,
}

const SETTLEMENT_SPHERE_RADIUS := 3

# Union of all city sphere hexes (hex_distance <= SETTLEMENT_SPHERE_RADIUS).
# Depends only on city positions — shares the hex-index invalidation triggers
# (size check + invalidate_city_hex_index sets the dirty flag).
var _settlement_sphere_set: Dictionary = {}
var _settlement_sphere_dirty := true
var _settlement_sphere_city_count := -1

func is_in_settlement_sphere(hex_pos: Vector2i) -> bool:
	var cities: Dictionary = GameManager.state.cities
	if _settlement_sphere_dirty or _settlement_sphere_city_count != cities.size():
		_settlement_sphere_set.clear()
		for city_id in cities:
			var city: CityState = cities[city_id]
			for dx in range(-SETTLEMENT_SPHERE_RADIUS - 1, SETTLEMENT_SPHERE_RADIUS + 2):
				for dy in range(-SETTLEMENT_SPHERE_RADIUS - 1, SETTLEMENT_SPHERE_RADIUS + 2):
					var h := Vector2i(city.hex_pos.x + dx, city.hex_pos.y + dy)
					if HexHelper.hex_distance(h, city.hex_pos) <= SETTLEMENT_SPHERE_RADIUS:
						_settlement_sphere_set[h] = true
		_settlement_sphere_city_count = cities.size()
		_settlement_sphere_dirty = false
	return _settlement_sphere_set.has(hex_pos)

func get_valid_settlement_tiles(faction_id: StringName, region_id: StringName, city_id: StringName = &"") -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return result
	# Region tile cache holds tiles in the same map-dict insertion order the
	# old full-map scan visited them, so result order is unchanged.
	for coord in hex_map.get_region_tiles(region_id):
		var tile: HexMapData.TileState = hex_map.tiles[coord]
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
			if rtile == null:
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
		Enums.TerrainType.WATER: return 3  # Food
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
	# Thin mutating wrapper around the pure compute function below: applies
	# the income delta plus whatever captive/mechanic-meter consumption it
	# says would happen. Keeping the side effects OUT of the pure function is
	# what lets the income breakdown tooltip call it safely for a preview
	# without silently draining captives every time the player hovers it.
	var result := compute_faction_income_modifier_effects(faction_id, fs, city, income)
	_merge_income_delta(income, result.income_delta)
	var mech_fs: FactionState = GameManager.state.faction_states.get(result.mech_faction_id)
	if mech_fs == null:
		return
	if result.captive_consumption != 0:
		mech_fs.resources[Enums.ResourceType.CAPTIVES] = mech_fs.resources.get(Enums.ResourceType.CAPTIVES, 0) - result.captive_consumption
	if result.storm_fury_delta != 0:
		mech_fs.storm_fury += result.storm_fury_delta
	if result.relic_power_delta != 0:
		mech_fs.relic_power += result.relic_power_delta
	if result.solar_faith_delta != 0:
		mech_fs.solar_faith += result.solar_faith_delta
	if result.population_delta != 0 and city:
		city.population += result.population_delta

func compute_faction_income_modifier_effects(faction_id: StringName, fs: FactionState, city: CityState, income: Dictionary, state_override: Dictionary = {}) -> Dictionary:
	# PURE preview of the faction-specific income modifier stage: returns the
	# income delta this stage would add AND the captive/meter consumption it
	# would trigger, WITHOUT mutating fs or city. This is the single source
	# of truth for both the real mutation path (_apply_faction_income_modifier
	# above) and the income breakdown tooltip in campaign_hud.gd.
	#
	# state_override lets a caller thread a SIMULATED running captives/meter
	# state across several calls (e.g. the breakdown looping over multiple
	# owned cities for one turn projection) instead of re-reading the real,
	# undepleted fs each time. Recognized keys: captives, storm_fury,
	# relic_power, solar_faith.
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	# For parent mechanic checks, use parent's FactionState if sub-faction
	var mech_fs := fs
	if parent_fid != faction_id:
		var parent_fs: FactionState = GameManager.state.faction_states.get(parent_fid)
		if parent_fs:
			mech_fs = parent_fs

	var delta: Dictionary = {}
	var view := income.duplicate()
	var start_captives: int = state_override.get("captives", mech_fs.resources.get(Enums.ResourceType.CAPTIVES, 0))
	var start_storm_fury: int = state_override.get("storm_fury", mech_fs.storm_fury)
	var start_relic_power: int = state_override.get("relic_power", mech_fs.relic_power)
	var start_solar_faith: int = state_override.get("solar_faith", mech_fs.solar_faith)
	var local_captives := start_captives
	var local_storm_fury := start_storm_fury
	var local_relic_power := start_relic_power
	var local_solar_faith := start_solar_faith
	var population_delta := 0

	# Apply sub-faction-specific income bonuses
	match faction_id:
		&"miststriders":  # Fog traders: +15% gold
			if view.has(Enums.ResourceType.GOLD):
				var add := int(view[Enums.ResourceType.GOLD] * 0.15)
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + add
				view[Enums.ResourceType.GOLD] += add
		&"oaseans":  # Desert educators: +2 tech flat
			delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + 2
			view[Enums.ResourceType.TECHNOLOGY] = view.get(Enums.ResourceType.TECHNOLOGY, 0) + 2
		&"servants_of_reliquary":  # Building discount proxy: +10% iron (construction materials)
			if view.has(Enums.ResourceType.IRON):
				var add := int(view[Enums.ResourceType.IRON] * 0.10)
				delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + add
				view[Enums.ResourceType.IRON] += add
		&"salt_reavers":  # Raiders: +10% gold from raiding/trade
			if view.has(Enums.ResourceType.GOLD):
				var add := int(view[Enums.ResourceType.GOLD] * 0.10)
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + add
				view[Enums.ResourceType.GOLD] += add
	match parent_fid:
		&"skulloath":
			# Low corruption: +15% food. High corruption: -10% food
			if mech_fs.corruption <= 30:
				if view.has(Enums.ResourceType.FOOD):
					var add := int(view[Enums.ResourceType.FOOD] * 0.15)
					delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + add
					view[Enums.ResourceType.FOOD] += add
			elif mech_fs.corruption >= 70:
				if view.has(Enums.ResourceType.FOOD):
					var sub := int(view[Enums.ResourceType.FOOD] * 0.10)
					delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) - sub
					view[Enums.ResourceType.FOOD] -= sub
			# Blood Altar: consume 4 captives per turn for +20 iron and +15 gold
			if city and city.buildings.has(&"blood_altar") and local_captives >= 4:
				local_captives -= 4
				delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + 20
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + 15
				view[Enums.ResourceType.IRON] = view.get(Enums.ResourceType.IRON, 0) + 20
				view[Enums.ResourceType.GOLD] = view.get(Enums.ResourceType.GOLD, 0) + 15
		&"gladehost":
			# Seasonal modifiers — Seasonal Shrine amplifies by 50%
			var season: int = GameManager.state.current_month
			var harmony_mult := mech_fs.harmony / 100.0
			var has_shrine := city and (city.buildings.has(&"seasonal_shrine") or city.buildings.has(&"solstice_altar") or city.buildings.has(&"eternal_cycle"))
			var shrine_mult := 1.0
			if has_shrine:
				if city.buildings.has(&"eternal_cycle"):
					shrine_mult = 2.0
				elif city.buildings.has(&"solstice_altar"):
					shrine_mult = 1.75
				else:
					shrine_mult = 1.5
			if season <= 2: # Spring: +food, +growth
				if view.has(Enums.ResourceType.FOOD):
					var add := int(view[Enums.ResourceType.FOOD] * 0.20 * harmony_mult * shrine_mult)
					delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + add
					view[Enums.ResourceType.FOOD] += add
			elif season <= 5: # Summer: +iron (arms production)
				if view.has(Enums.ResourceType.IRON):
					var add := int(view[Enums.ResourceType.IRON] * 0.15 * harmony_mult * shrine_mult)
					delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + add
					view[Enums.ResourceType.IRON] += add
			elif season <= 7: # Autumn: +gold, +wood (harvest)
				if view.has(Enums.ResourceType.GOLD):
					var add_g := int(view[Enums.ResourceType.GOLD] * 0.20 * harmony_mult * shrine_mult)
					delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + add_g
					view[Enums.ResourceType.GOLD] += add_g
				if view.has(Enums.ResourceType.WOOD):
					var add_w := int(view[Enums.ResourceType.WOOD] * 0.20 * harmony_mult * shrine_mult)
					delta[Enums.ResourceType.WOOD] = delta.get(Enums.ResourceType.WOOD, 0) + add_w
					view[Enums.ResourceType.WOOD] += add_w
			else: # Winter: -food (shrine reduces winter penalty)
				var winter_penalty := 0.20 if shrine_mult == 1.0 else 0.10
				if view.has(Enums.ResourceType.FOOD):
					var sub := int(view[Enums.ResourceType.FOOD] * winter_penalty)
					delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) - sub
					view[Enums.ResourceType.FOOD] -= sub
			# Living Fortress: seasonal defense scaling (bonus defense in spring/summer)
			if city and city.buildings.has(&"living_fortress"):
				if season <= 5: # Spring/Summer: trees grow, fortress strengthens
					delta[Enums.ResourceType.WOOD] = delta.get(Enums.ResourceType.WOOD, 0) + 5
					view[Enums.ResourceType.WOOD] = view.get(Enums.ResourceType.WOOD, 0) + 5
		&"tainted_jade":
			# Taint power bonus: +5% iron when taint > 20 (hardened materials)
			if mech_fs.taint_power >= 20:
				if view.has(Enums.ResourceType.IRON):
					var add := int(view[Enums.ResourceType.IRON] * 0.05)
					delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + add
					view[Enums.ResourceType.IRON] += add
			# Captive conversion: each captive generates a small amount of wood/iron
			if local_captives > 0:
				# Captive Processing Camp doubles thrall output
				var camp_mult := 2 if (city and city.buildings.has(&"captive_processing_camp")) else 1
				var thrall_output := mini(local_captives / 5, 10) * camp_mult
				delta[Enums.ResourceType.WOOD] = delta.get(Enums.ResourceType.WOOD, 0) + thrall_output
				delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + thrall_output
				view[Enums.ResourceType.WOOD] = view.get(Enums.ResourceType.WOOD, 0) + thrall_output
				view[Enums.ResourceType.IRON] = view.get(Enums.ResourceType.IRON, 0) + thrall_output
			# Taint Suppressor: converts taint power into technology (shard neutralization research)
			if city and city.buildings.has(&"taint_suppressor"):
				if mech_fs.taint_power >= 10:
					delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + int(mech_fs.taint_power * 0.1)
			# Shard Breaker Forge: bonus shard essence from destroying shards (passive shard processing)
			if city and city.buildings.has(&"shard_breaker_forge"):
				delta[Enums.ResourceType.SHARD_ESSENCE] = delta.get(Enums.ResourceType.SHARD_ESSENCE, 0) + 5
		&"shardhorde":
			# Active resonance buffs boost income
			for realm_key in mech_fs.shard_resonance:
				var realm: int = realm_key
				match realm:
					Enums.Realm.DIVINE:
						delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + 15
					Enums.Realm.ELEMENTAL:
						delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + 20
					Enums.Realm.NATURE:
						delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + 20
					Enums.Realm.MORTAL:
						delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + 10
						delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + 10
					Enums.Realm.VOID:
						delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + 15
		&"moonspear":
			# Lunar Observatory: moonlit study of captives for arcane knowledge
			if city and (city.buildings.has(&"lunar_observatory") or city.buildings.has(&"astral_observatory")) and local_captives >= 3:
				local_captives -= 3
				delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + 10
			# Lunar phase: tech bonus at full moon
			if mech_fs.lunar_phase >= 3:
				delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + 4
		&"thunderswarm":
			# Warriors' Longhouse: trial by combat games with captives
			if city and (city.buildings.has(&"warriors_longhouse") or city.buildings.has(&"warchief_warcamp")) and local_captives >= 3:
				local_captives -= 3
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + 10
				local_storm_fury = mini(local_storm_fury + 3, 100)
			# Storm fury: +iron at high fury
			if local_storm_fury >= 50:
				delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + int(local_storm_fury * 0.08)
		&"cinderguard":
			# Forge chain labor: captives work the forges
			if city and (city.buildings.has(&"ember_foundry") or city.buildings.has(&"molten_core_forge")) and local_captives >= 4:
				local_captives -= 4
				delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + 18
		&"forsaken":
			# Shadow Barracks: consume captives as thrall fuel (blood-binding)
			if city and (city.buildings.has(&"wretched_pit") or city.buildings.has(&"necromancer_sanctum")) and local_captives >= 3:
				local_captives -= 3
				delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + 15
			# Void Pit: sacrifice captives to the void for gold
			if city and city.buildings.has(&"void_pit") and local_captives >= 3:
				local_captives -= 3
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + 12
		&"ivoryscar":
			# Tomb Scholar's Hall: captives excavate ancient tombs
			if city and (city.buildings.has(&"tomb_scholars_hall") or city.buildings.has(&"vault_of_ages")) and local_captives >= 3:
				local_captives -= 3
				delta[Enums.ResourceType.TECHNOLOGY] = delta.get(Enums.ResourceType.TECHNOLOGY, 0) + 8
				local_relic_power = mini(local_relic_power + 4, 100)
			# Relic power: +gold at high relic power
			if local_relic_power >= 30:
				delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + int(local_relic_power * 0.08)
		&"sunblessed":
			# Pilgrim's Rest: convert captives through religious redemption
			if city and (city.buildings.has(&"pilgrims_rest") or city.buildings.has(&"cathedral_of_dawn")) and local_captives >= 2:
				local_captives -= 2
				population_delta += 5 # Converted captives join the population
				local_solar_faith = mini(local_solar_faith + 3, 100)
			# Solar faith: +food at high faith
			if local_solar_faith >= 40:
				delta[Enums.ResourceType.FOOD] = delta.get(Enums.ResourceType.FOOD, 0) + int(local_solar_faith * 0.06)
		&"empire":
			# Labor Camp / Imperial Work Yard: empire captive processing
			if city and (city.buildings.has(&"imperial_work_yard") or city.buildings.has(&"labor_camp")):
				var consume := 4 if city.buildings.has(&"imperial_work_yard") else 3
				if local_captives >= consume:
					local_captives -= consume
					delta[Enums.ResourceType.GOLD] = delta.get(Enums.ResourceType.GOLD, 0) + consume * 5
					delta[Enums.ResourceType.IRON] = delta.get(Enums.ResourceType.IRON, 0) + consume * 3

	return {
		income_delta = delta,
		captive_consumption = start_captives - local_captives,
		storm_fury_delta = local_storm_fury - start_storm_fury,
		relic_power_delta = local_relic_power - start_relic_power,
		solar_faith_delta = local_solar_faith - start_solar_faith,
		population_delta = population_delta,
		mech_faction_id = parent_fid,
	}
