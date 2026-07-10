extends SceneTree
## Plan C Task 1: memoized income breakdown must be identical to the verbatim
## pre-memo implementation (extracted from git HEAD) for all resource types.
## Run: godot --headless --path . -s res://tests/test_income_breakdown_equivalence.gd

var _fails := 0
var _gm: Node
var _dm: Node
var _tm: Node
var _cmds: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_tm = root.get_node("/root/TurnManager")
	_cmds = root.get_node("/root/CommanderSystem")
	_gm.new_game(&"empire")
	_compare_all("initial empire state")
	# Loyalty drop (changes step 3)
	var fs: FactionState = _gm.state.faction_states[_gm.state.player_faction_id]
	if fs.owned_cities.size() > 0:
		var c0: CityState = _gm.state.cities[fs.owned_cities[0]]
		c0.loyalty = 20
	_compare_all("after loyalty change")
	# Siege a city (changes memo membership / steps 1-3 + food consumption)
	if fs.owned_cities.size() > 1:
		var c1: CityState = _gm.state.cities[fs.owned_cities[1]]
		c1.is_under_siege = true
	_compare_all("after siege change")
	if _fails == 0:
		print("INCOME EQUIVALENCE TEST PASSED")
		quit(0)
	else:
		print("INCOME EQUIVALENCE TEST FAILED (%d)" % _fails)
		quit(1)

func _compare_all(label: String) -> void:
	var hud = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()
	var projected: Dictionary = hud._calculate_projected_income()
	var display_types := [0, 1, 2, 3, 5, 6]
	if _gm.state.player_faction_id == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var expected := _reference_breakdown(res_type)
		var actual: Dictionary = hud._calculate_income_breakdown(res_type)
		var cached: Dictionary = hud._income_breakdown_cache.get(res_type, {})
		if expected != actual:
			_fails += 1
			print("MISMATCH (%s) res=%d direct:
  exp=%s
  act=%s" % [label, res_type, expected, actual])
		if expected != cached:
			_fails += 1
			print("MISMATCH (%s) res=%d cached" % [label, res_type])
		var exp_net: int = expected.net
		if exp_net != 0 and int(projected.get(res_type, 0)) != exp_net:
			_fails += 1
			print("MISMATCH (%s) res=%d projected net: exp=%d got=%s" % [label, res_type, exp_net, str(projected.get(res_type))])
		if exp_net == 0 and projected.has(res_type):
			_fails += 1
			print("MISMATCH (%s) res=%d projected should omit zero net" % [label, res_type])
	hud.free()

# === VERBATIM pre-memo implementation from git HEAD (autoload refs -> node vars) ===
func _reference_breakdown(res_type: int) -> Dictionary:
	# Returns {"cities": {city_name: amount}, "upkeep": {category: amount},
	#          "modifiers": [{label, amount}], "net": int}
	# Mirrors the actual _generate_income() logic in city_system.gd
	var breakdown = {"cities": {}, "upkeep": {}, "modifiers": [], "net": 0}
	var player_id = _gm.state.player_faction_id
	var fs: FactionState = _gm.state.faction_states.get(player_id)
	if fs == null:
		return breakdown

	# Step 1: Base city income (from buildings + region)
	var base_total = 0
	for city_id in fs.owned_cities:
		var city: CityState = _gm.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income = _gm.city_system.calculate_city_income(city)
			var amount: int = city_income.get(res_type, 0)
			if amount != 0:
				breakdown.cities[city.get_display_name()] = amount
				base_total += amount

	# Step 2: Class bonuses (applied per-city in _generate_income, aggregate here)
	var class_bonus_total = 0
	for city_id in fs.owned_cities:
		var city: CityState = _gm.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income = _gm.city_system.calculate_city_income(city)
			var raw: int = city_income.get(res_type, 0)
			if raw == 0:
				continue
			var pcts = LoyaltySystem.calculate_class_percentages(city, city.faction_id)
			var bonus = 0
			match res_type:
				Enums.ResourceType.FOOD:
					bonus = int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
					bonus = int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.TECHNOLOGY:
					bonus = int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
				Enums.ResourceType.GOLD:
					bonus = int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
			class_bonus_total += bonus
	if class_bonus_total != 0:
		var class_label = ""
		match res_type:
			Enums.ResourceType.FOOD: class_label = "Peasant Bonus"
			Enums.ResourceType.IRON, Enums.ResourceType.WOOD: class_label = "Artisan Bonus"
			Enums.ResourceType.TECHNOLOGY: class_label = "Scholar Bonus"
			Enums.ResourceType.GOLD: class_label = "Noble Bonus"
			_: class_label = "Class Bonus"
		breakdown.modifiers.append({label = class_label, amount = class_bonus_total})

	var income_subtotal = base_total + class_bonus_total

	# Step 3: Loyalty multiplier (applied per-city, aggregate the penalty)
	var loyalty_penalty = 0
	for city_id in fs.owned_cities:
		var city: CityState = _gm.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income = _gm.city_system.calculate_city_income(city)
			var raw: int = city_income.get(res_type, 0)
			if raw == 0:
				continue
			var pcts = LoyaltySystem.calculate_class_percentages(city, city.faction_id)
			var after_class = raw
			match res_type:
				Enums.ResourceType.FOOD:
					after_class += int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
					after_class += int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.TECHNOLOGY:
					after_class += int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
				Enums.ResourceType.GOLD:
					after_class += int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
			var loyalty_mult = LoyaltySystem.get_loyalty_multiplier(city.loyalty)
			if loyalty_mult < 1.0:
				loyalty_penalty += int(float(after_class) * loyalty_mult) - after_class
	if loyalty_penalty != 0:
		breakdown.modifiers.append({label = "Low Loyalty", amount = loyalty_penalty})
		income_subtotal += loyalty_penalty

	# Step 4: Research percentage bonuses
	var research_effects = _gm.research_system.get_research_effects(player_id)
	var research_bonus = 0
	match res_type:
		Enums.ResourceType.GOLD:
			var pct: int = research_effects.get("income_gold_pct", 0)
			if pct != 0:
				research_bonus = int(income_subtotal * pct / 100.0)
		Enums.ResourceType.FOOD:
			var pct: int = research_effects.get("income_food_pct", 0)
			if pct != 0:
				research_bonus = int(income_subtotal * pct / 100.0)
	if research_bonus != 0:
		breakdown.modifiers.append({label = "Research", amount = research_bonus})
		income_subtotal += research_bonus

	# Step 5: Senate majority effects (Empire only)
	if player_id == &"empire":
		var senate_effects = _gm.policy_system.get_senate_majority_effects(player_id)
		var senate_pct_key = ""
		match res_type:
			Enums.ResourceType.GOLD: senate_pct_key = "gold_income_pct"
			Enums.ResourceType.TECHNOLOGY: senate_pct_key = "tech_income_pct"
			Enums.ResourceType.IRON: senate_pct_key = "iron_income_pct"
			Enums.ResourceType.WOOD: senate_pct_key = "wood_income_pct"
		if senate_pct_key != "" and senate_effects.has(senate_pct_key):
			var pct: int = senate_effects[senate_pct_key]
			if pct != 0:
				var senate_amount = int(income_subtotal * pct / 100.0)
				breakdown.modifiers.append({label = "Senate Majority (%+d%%)" % pct, amount = senate_amount})
				income_subtotal += senate_amount

	# Step 6: Active trade agreements
	var trade_income = 0
	var trade_cost = 0
	for treaty_id in _gm.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = _gm.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_DEAL:
			continue
		var is_a = treaty.faction_a == player_id
		var is_b = treaty.faction_b == player_id
		if not is_a and not is_b:
			continue
		var give_res: int = treaty.terms.get("give_resource", -1)
		var give_amt: int = treaty.terms.get("give_amount", 0)
		var recv_res: int = treaty.terms.get("receive_resource", -1)
		var recv_amt: int = treaty.terms.get("receive_amount", 0)
		# faction_a gives give_res and receives recv_res
		# faction_b gives recv_res and receives give_res
		var partner_fd: FactionData
		if is_a:
			partner_fd = _dm.get_faction(treaty.faction_b)
			if give_res == res_type:
				trade_cost += give_amt
			if recv_res == res_type:
				trade_income += recv_amt
		else:
			partner_fd = _dm.get_faction(treaty.faction_a)
			if recv_res == res_type:
				trade_cost += recv_amt
			if give_res == res_type:
				trade_income += give_amt
		var partner_name: String = partner_fd.display_name if partner_fd else "Unknown"
		if (is_a and recv_res == res_type) or (is_b and give_res == res_type):
			var amt: int = recv_amt if is_a else give_amt
			breakdown.modifiers.append({label = "Trade (%s)" % partner_name, amount = amt})
		if (is_a and give_res == res_type) or (is_b and recv_res == res_type):
			var amt: int = give_amt if is_a else recv_amt
			breakdown.modifiers.append({label = "Trade (%s)" % partner_name, amount = -amt})
	income_subtotal += trade_income - trade_cost

	# Step 6b: Trade Relations (continuous resource sharing treaties)
	for treaty_id in _gm.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = _gm.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_RELATIONS:
			continue
		var is_a = treaty.faction_a == player_id
		var is_b = treaty.faction_b == player_id
		if not is_a and not is_b:
			continue
		var turns_active: int = treaty.terms.get("turns_active", 0)
		var share_pct = _gm.diplomacy_system.get_trade_relations_share(turns_active) / 100.0
		var res_a: int = treaty.terms.get("resource_a", 0)
		var res_b: int = treaty.terms.get("resource_b", 0)
		var partner_id: StringName = treaty.faction_b if is_a else treaty.faction_a
		var partner_fd: FactionData = _dm.get_faction(partner_id)
		var partner_name: String = partner_fd.display_name if partner_fd else "Unknown"
		# What we receive: their top resource shared to us
		var we_receive_res: int = res_b if is_a else res_a
		if we_receive_res == res_type:
			var their_income = _gm.diplomacy_system.get_faction_resource_income(partner_id, we_receive_res)
			var gain = maxi(1, int(float(their_income) * share_pct))
			breakdown.modifiers.append({label = "Trade Relations (%s)" % partner_name, amount = gain})
			income_subtotal += gain
		# What we share: our top resource given to them (shown as cost)
		var we_share_res: int = res_a if is_a else res_b
		if we_share_res == res_type:
			# Trade relations don't deduct resources — they grant copies. No cost line needed.
			pass

	# Elderbeast terrain + building income
	var beast_total = 0
	for beast_id in _gm.state.elderbeasts:
		var beast: ElderbeastState = _gm.state.elderbeasts[beast_id]
		if beast.faction_id == player_id:
			var beast_income = _tm._get_elderbeast_income(beast)
			var amount: int = beast_income.get(res_type, 0)
			if amount != 0:
				breakdown.cities[beast.name] = amount
				beast_total += amount
	income_subtotal += beast_total

	# Upkeep grouped by tag
	var upkeep_total = 0
	var upkeep_by_tag: Dictionary = {}
	for army_id in _gm.state.armies:
		var army: ArmyState = _gm.state.armies[army_id]
		if army.faction_id == player_id:
			for unit in army.units:
				var ud = _dm.get_unit(unit.unit_data_id)
				if ud and ud.upkeep_cost.has(res_type):
					var tag = "Other"
					for t in ["infantry", "ranged", "cavalry", "mage", "construct"]:
						if ud.tags.has(t):
							tag = t.capitalize()
							break
					upkeep_by_tag[tag] = upkeep_by_tag.get(tag, 0) + ud.upkeep_cost[res_type]
					upkeep_total += ud.upkeep_cost[res_type]
			# Commander upkeep
			if army.commander != null and _cmds.COMMANDER_UPKEEP.has(res_type):
				var level_mult = 1.0 + (army.commander.level - 1) * 0.5
				var cmd_cost = int(_cmds.COMMANDER_UPKEEP[res_type] * level_mult)
				upkeep_by_tag["Commanders"] = upkeep_by_tag.get("Commanders", 0) + cmd_cost
				upkeep_total += cmd_cost
	breakdown.upkeep = upkeep_by_tag

	# Population food consumption (quartered rate)
	var food_consumption = 0
	if res_type == Enums.ResourceType.FOOD:
		for city_id in fs.owned_cities:
			var city: CityState = _gm.state.cities.get(city_id)
			if city and not city.is_under_siege:
				var province_pop = _gm.city_system.get_province_population(city)
				food_consumption += province_pop / 40
		if food_consumption > 0:
			breakdown.modifiers.append({label = "Pop. Consumption", amount = -food_consumption})

	# Captive consumption from buildings (labor camps, faction-specific buildings)
	var captive_consumption = 0
	if res_type == Enums.ResourceType.CAPTIVES:
		var parent_fid: StringName = _gm.MINOR_FACTION_PARENTS.get(player_id, player_id)
		for city_id in fs.owned_cities:
			var city: CityState = _gm.state.cities.get(city_id)
			if city == null:
				continue
			# Base camp buildings
			if city.buildings.has(&"labor_camp"):
				captive_consumption += 3
			if city.buildings.has(&"thrall_quarters"):
				captive_consumption += 2
			if city.buildings.has(&"captive_processing_camp"):
				captive_consumption += 4
			# Faction-specific buildings
			match parent_fid:
				&"skulloath":
					if city.buildings.has(&"blood_altar"):
						captive_consumption += 4
				&"moonspear":
					if city.buildings.has(&"lunar_observatory") or city.buildings.has(&"astral_observatory"):
						captive_consumption += 3
				&"thunderswarm":
					if city.buildings.has(&"warriors_longhouse") or city.buildings.has(&"warchief_warcamp"):
						captive_consumption += 3
				&"cinderguard":
					if city.buildings.has(&"ember_foundry") or city.buildings.has(&"molten_core_forge"):
						captive_consumption += 4
				&"forsaken":
					if city.buildings.has(&"wretched_pit") or city.buildings.has(&"necromancer_sanctum"):
						captive_consumption += 3
					if city.buildings.has(&"void_pit"):
						captive_consumption += 3
				&"ivoryscar":
					if city.buildings.has(&"tomb_scholars_hall") or city.buildings.has(&"vault_of_ages"):
						captive_consumption += 3
				&"sunblessed":
					if city.buildings.has(&"pilgrims_rest") or city.buildings.has(&"cathedral_of_dawn"):
						captive_consumption += 2
				&"empire":
					if city.buildings.has(&"imperial_work_yard"):
						captive_consumption += 4
		if captive_consumption > 0:
			breakdown.modifiers.append({label = "Building Consumption", amount = -captive_consumption})

	# Trade route plunder income (player armies intercepting enemy trade routes)
	var plunder_income = 0
	if res_type == Enums.ResourceType.GOLD and _gm.diplomacy_system:
		var player_routes = _gm.diplomacy_system.get_active_trade_routes()
		for route in player_routes:
			# Only count routes where player is NOT a participant
			if route.faction_a == player_id or route.faction_b == player_id:
				continue
			var hex_path = DiplomacySystem.get_trade_route_hex_path(route.city_a_hex, route.city_b_hex)
			for army_id in _gm.state.armies:
				var army: ArmyState = _gm.state.armies[army_id]
				if army.faction_id != player_id or army.is_garrison:
					continue
				for coord in hex_path:
					if army.hex_pos == coord:
						# Estimate plunder: 25% of ~10 (rough per-route value)
						plunder_income += 3
						break
		if plunder_income > 0:
			breakdown.modifiers.append({label = "Trade Plunder", amount = plunder_income})
			income_subtotal += plunder_income

	breakdown.net = income_subtotal - upkeep_total - food_consumption - captive_consumption
	return breakdown
