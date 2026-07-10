class_name PolicySystem
extends RefCounted

const MAX_ACTIVE_POLICIES := 3
const CATEGORY_COOLDOWN_TURNS := 3
const TOTAL_SENATE_SEATS := 80

func get_available_policies(faction_id: StringName) -> Array[PolicyData]:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return []
	var result: Array[PolicyData] = []
	for policy_id in DataManager.policies:
		var data: PolicyData = DataManager.policies[policy_id]
		if data.faction_id != &"" and data.faction_id != fs.faction_data_id:
			continue
		if fs.active_policies.has(policy_id):
			continue
		result.append(data)
	return result

func can_enact_policy(faction_id: StringName, policy_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return false
	var data: PolicyData = DataManager.policies.get(policy_id)
	if data == null:
		return false
	if fs.active_policies.has(policy_id):
		return false
	# Check faction
	if data.faction_id != &"" and data.faction_id != fs.faction_data_id:
		return false
	# Senate paralyzed during Forsaken crisis stage 1-2
	if fs.forsaken_crisis_stage >= 1 and fs.forsaken_crisis_stage <= 2:
		return false
	# Check category cooldown
	if fs.policy_cooldowns.get(data.category, 0) > 0:
		return false
	# Check if at max active policies (unless replacing same category)
	var existing_in_category := _get_active_policy_in_category(fs, data.category)
	if existing_in_category == &"" and fs.active_policies.size() >= MAX_ACTIVE_POLICIES:
		return false
	# Check required class loyalty
	var capital := _get_faction_capital(faction_id)
	if capital == null:
		return false
	for cls in data.required_class_loyalty:
		var required: int = data.required_class_loyalty[cls]
		var current: int = capital.class_loyalty.get(cls, 0)
		if current < required:
			return false
	return true

func enact_policy(faction_id: StringName, policy_id: StringName) -> bool:
	if not can_enact_policy(faction_id, policy_id):
		return false
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	var data: PolicyData = DataManager.policies.get(policy_id)
	if data == null:
		return false
	# Replace existing policy in same category (triggers category cooldown)
	var existing := _get_active_policy_in_category(fs, data.category)
	if existing != &"":
		fs.active_policies.erase(existing)
		fs.policy_cooldowns[data.category] = CATEGORY_COOLDOWN_TURNS
		EventBus.policy_revoked.emit(faction_id, existing)
	fs.active_policies.append(policy_id)
	EventBus.policy_enacted.emit(faction_id, policy_id)
	return true

func revoke_policy(faction_id: StringName, policy_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or not fs.active_policies.has(policy_id):
		return false
	var data: PolicyData = DataManager.policies.get(policy_id)
	fs.active_policies.erase(policy_id)
	if data:
		fs.policy_cooldowns[data.category] = CATEGORY_COOLDOWN_TURNS
	EventBus.policy_revoked.emit(faction_id, policy_id)
	return true

func process_policies(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var capital := _get_faction_capital(faction_id)
	# Apply active policy effects (resources only — loyalty handled by LoyaltySystem)
	var to_revoke: Array[StringName] = []
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data == null:
			continue
		# Apply resource effects
		for res_type in data.resource_effects:
			fs.resources[res_type] = fs.resources.get(res_type, 0) + data.resource_effects[res_type]
		# Auto-revoke if loyalty requirements no longer met
		if capital and not data.required_class_loyalty.is_empty():
			for cls in data.required_class_loyalty:
				var required: int = data.required_class_loyalty[cls]
				var current: int = capital.class_loyalty.get(cls, 0)
				if current < required:
					to_revoke.append(policy_id)
					break
	for policy_id in to_revoke:
		revoke_policy(faction_id, policy_id)
	# Process Forsaken crisis (Empire only)
	if faction_id == &"empire":
		_process_forsaken_crisis(faction_id, fs, capital)
	# Decrement category cooldowns
	var expired: Array[int] = []
	for category in fs.policy_cooldowns:
		fs.policy_cooldowns[category] -= 1
		if fs.policy_cooldowns[category] <= 0:
			expired.append(category)
	for category in expired:
		fs.policy_cooldowns.erase(category)

func get_policy_resource_effects(faction_id: StringName) -> Dictionary:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	var combined: Dictionary = {}
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data == null:
			continue
		for res_type in data.resource_effects:
			combined[res_type] = combined.get(res_type, 0) + data.resource_effects[res_type]
	return combined

func get_loyalty_change_forecast(faction_id: StringName) -> Dictionary:
	# Returns policy-only resource/loyalty forecast (loyalty deltas now handled by LoyaltySystem)
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	var changes: Dictionary = {}
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data == null:
			continue
		for cls in data.class_loyalty_effects:
			changes[cls] = changes.get(cls, 0) + data.class_loyalty_effects[cls]
	return changes

func _get_active_policy_in_category(fs: FactionState, category: int) -> StringName:
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data and data.category == category:
			return policy_id
	return &""

func _get_faction_capital(faction_id: StringName) -> CityState:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return null
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and city.is_capital:
			return city
	return null

# ── Senate Seat Calculation ───────────────────────────────────

func calculate_senate_seats(faction_id: StringName) -> Array[int]:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return [0, 0, 0, 0]
	var capital := _get_faction_capital(faction_id)
	if capital == null:
		return [0, 0, 0, fs.forsaken_seats]

	var pcts := LoyaltySystem.calculate_class_percentages(capital, faction_id)
	var noble_pct: float = pcts.get("nobles", 0.0)
	var scholar_pct: float = pcts.get("scholars", 0.0)
	var artisan_pct: float = pcts.get("artisans", 0.0)

	var forsaken := mini(fs.forsaken_seats, TOTAL_SENATE_SEATS)
	var available := TOTAL_SENATE_SEATS - forsaken

	var total_pct := noble_pct + scholar_pct + artisan_pct
	if total_pct <= 0.0:
		return [available, 0, 0, forsaken]

	# Normalize and distribute with largest-remainder method
	var raw_nobles := (noble_pct / total_pct) * available
	var raw_scholars := (scholar_pct / total_pct) * available
	var raw_artisans := (artisan_pct / total_pct) * available

	var s0 := int(raw_nobles)
	var s1 := int(raw_scholars)
	var s2 := int(raw_artisans)
	var r0 := raw_nobles - s0
	var r1 := raw_scholars - s1
	var r2 := raw_artisans - s2
	var assigned := s0 + s1 + s2
	var leftover := available - assigned

	var seats: Array[int] = [s0, s1, s2]
	var remainders: Array[float] = [r0, r1, r2]

	while leftover > 0:
		var best_idx := 0
		for i in 3:
			if remainders[i] > remainders[best_idx]:
				best_idx = i
		seats[best_idx] += 1
		remainders[best_idx] = -1.0
		leftover -= 1

	var result: Array[int] = [seats[0], seats[1], seats[2], forsaken]
	return result

func get_senate_majority(faction_id: StringName) -> StringName:
	var seats := calculate_senate_seats(faction_id)
	var names: Array[StringName] = [&"nobles", &"scholars", &"artisans", &"forsaken"]
	var best_idx := 0
	for i in 4:
		if seats[i] > seats[best_idx]:
			best_idx = i
	return names[best_idx]

func _get_majority_loyalty_scale(faction_id: StringName, majority: StringName) -> float:
	if majority == &"forsaken":
		return 1.0
	var capital := _get_faction_capital(faction_id)
	if capital == null:
		return 0.0
	var class_key := str(majority)
	var loyalty: int = capital.class_loyalty.get(class_key, 0)
	return clampf(float(loyalty) / 50.0, 0.0, 2.0)

func get_senate_majority_effects(faction_id: StringName) -> Dictionary:
	var majority := get_senate_majority(faction_id)
	var scale := _get_majority_loyalty_scale(faction_id, majority)
	match majority:
		&"nobles":
			return {gold_income_pct = int(10.0 * scale), tech_income_pct = int(-5.0 * scale)}
		&"scholars":
			return {tech_income_pct = int(10.0 * scale), gold_income_pct = int(-5.0 * scale)}
		&"artisans":
			return {iron_income_pct = int(5.0 * scale), wood_income_pct = int(5.0 * scale)}
		&"forsaken":
			return {gold_income_pct = -10, loyalty_all = -3}
	return {}

# ── Forsaken Offers ───────────────────────────────────────────

func check_forsaken_offer(faction_id: StringName, current_turn: int) -> Dictionary:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	if current_turn < fs.forsaken_next_offer_turn:
		return {}

	# Scale resources with game progression
	var base_amount := 80 + current_turn * 10
	var res_types: Array[int] = [Enums.ResourceType.GOLD, Enums.ResourceType.IRON, Enums.ResourceType.WOOD]
	var res_names: Array[String] = ["Gold", "Iron", "Wood"]

	# Offer the resource the faction is lowest on (weighted random)
	var weights: Array[float] = []
	var total_weight := 0.0
	for rt in res_types:
		var held: int = fs.resources.get(rt, 0)
		var w := 1.0 / maxf(1.0, float(held))  # Lower stock = higher weight
		weights.append(w)
		total_weight += w
	var roll := randf() * total_weight
	var pick := 0
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if roll <= cumulative:
			pick = i
			break

	var chosen_type: int = res_types[pick]
	var chosen_name: String = res_names[pick]
	var amount := base_amount if chosen_type == Enums.ResourceType.GOLD else int(base_amount * 0.5)
	var seats_requested := randi_range(2, 4)

	var flavors := [
		"The shadows whisper of mutual benefit...",
		"A hooded emissary offers a sealed chest.",
		"Dark coin flows from places best left unnamed.",
		"The Forsaken extend an open hand... for now.",
	]

	return {
		resource_type = chosen_type,
		resource_name = chosen_name,
		amount = amount,
		seats_requested = seats_requested,
		flavor_text = flavors[randi() % flavors.size()],
	}

func accept_forsaken_offer(faction_id: StringName, offer: Dictionary) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	fs.resources[offer.resource_type] = fs.resources.get(offer.resource_type, 0) + offer.amount
	fs.forsaken_seats += offer.seats_requested
	fs.forsaken_next_offer_turn = GameManager.state.current_turn + randi_range(4, 7)

func decline_forsaken_offer(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	fs.forsaken_next_offer_turn = GameManager.state.current_turn + randi_range(3, 5)

# ── Forsaken Crisis ───────────────────────────────────────────

func _process_forsaken_crisis(faction_id: StringName, fs: FactionState, capital: CityState) -> void:
	var forsaken_count: int = fs.forsaken_seats

	# Determine crisis stage from seat thresholds
	var new_stage := 0
	if forsaken_count >= 50: # Majority — Stage 3 Collapse
		new_stage = 3
	elif forsaken_count >= 35: # ~44% — Stage 2 Crisis
		new_stage = 2
	elif forsaken_count >= 20: # 25% — Stage 1 Tension
		new_stage = 1

	var old_stage := fs.forsaken_crisis_stage
	fs.forsaken_crisis_stage = new_stage

	# Stage 0: Normal — no effects
	if new_stage == 0:
		return

	# Stage 1 (Tension): Senate paralyzed, -10% income
	# Senate paralysis is handled in can_enact_policy() check
	# Income penalty applied during city income calculation via get_forsaken_income_penalty()

	# Stage 2 (Crisis): Loyalty penalty + random sabotage
	if new_stage >= 2:
		# -5 loyalty per turn to all classes in all cities
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city:
				for cls in city.class_loyalty:
					city.class_loyalty[cls] = clampi(city.class_loyalty[cls] - 5, -100, 100)
		# 15% chance of sabotage event
		if randf() < 0.15:
			_apply_forsaken_sabotage(faction_id, fs)

	# Stage 3 (Collapse): First time reaching stage 3, emit crisis dilemma
	if new_stage == 3 and old_stage < 3:
		EventBus.forsaken_offer.emit(faction_id, {type = "crisis_dilemma", stage = 3})

func get_forsaken_income_penalty(faction_id: StringName) -> float:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return 0.0
	match fs.forsaken_crisis_stage:
		1: return 0.10 # -10% income
		2: return 0.15 # -15% income
		3: return 0.30 # -30% income
	return 0.0

func _apply_forsaken_sabotage(faction_id: StringName, fs: FactionState) -> void:
	# Random sabotage: destroy a building or desert units
	var sabotage_roll := randf()
	if sabotage_roll < 0.5:
		# Building destroyed in random city
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and city.buildings.size() > 0:
				var destroyed := city.buildings[randi() % city.buildings.size()]
				city.buildings.erase(destroyed)
				GameManager.city_system.invalidate_region_effects_cache()
				break
	else:
		# Units desert from random army
		var armies := GameManager.get_faction_armies(faction_id)
		if armies.size() > 0:
			var victim: ArmyState = armies[randi() % armies.size()]
			if victim.units.size() > 1:
				victim.units.remove_at(randi() % victim.units.size())

func purge_forsaken_senate(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	fs.forsaken_seats = maxi(0, fs.forsaken_seats / 2)
	fs.forsaken_crisis_stage = 0
	# Nobility / scholars angered
	var capital := _get_faction_capital(faction_id)
	if capital:
		capital.class_loyalty["nobles"] = clampi(capital.class_loyalty.get("nobles", 0) - 15, -100, 100)
		capital.class_loyalty["scholars"] = clampi(capital.class_loyalty.get("scholars", 0) - 15, -100, 100)
	# Gold cost
	fs.resources[Enums.ResourceType.GOLD] = maxi(0, fs.resources.get(Enums.ResourceType.GOLD, 0) - 200)

func submit_to_forsaken(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	fs.forsaken_seats += 3
	# Income penalty handled via forsaken_crisis_stage staying active

# ── Senate Dilemmas ──────────────────────────────────────────

const SENATE_DILEMMAS := {
	&"nobles": [
		{
			title = "Noble Court Petition",
			text_loyal = "The noble houses, pleased with your rule, petition for expanded authority over trade routes.",
			text_disloyal = "The noble houses demand greater privileges, threatening to withdraw financial support.",
			choice_a_loyal = {label = "Grant Authority", tooltip = "Nobles manage trade: +60 Gold, +5 Noble loyalty", effects = {0: 60}, loyalty_effects = {nobles = 5}},
			choice_b_loyal = {label = "Decline Gracefully", tooltip = "Maintain balance: +20 Gold, -2 Noble loyalty", effects = {0: 20}, loyalty_effects = {nobles = -2}},
			choice_a_disloyal = {label = "Appease Nobles", tooltip = "Pay tribute: -80 Gold, +8 Noble loyalty", effects = {0: -80}, loyalty_effects = {nobles = 8}},
			choice_b_disloyal = {label = "Refuse Demands", tooltip = "Stand firm: -5 Noble loyalty", effects = {}, loyalty_effects = {nobles = -5}},
		},
		{
			title = "Marriage Alliance",
			text_loyal = "A loyal noble family proposes a political marriage to strengthen the realm.",
			text_disloyal = "A powerful noble family demands a marriage alliance or threatens rebellion.",
			choice_a_loyal = {label = "Accept Alliance", tooltip = "Strengthen bonds: +3 Noble loyalty, +2 Peasant loyalty", effects = {}, loyalty_effects = {nobles = 3, peasants = 2}},
			choice_b_loyal = {label = "Politely Decline", tooltip = "Stay independent: +40 Gold", effects = {0: 40}, loyalty_effects = {}},
			choice_a_disloyal = {label = "Accept Under Pressure", tooltip = "Avoid conflict: +5 Noble loyalty, -3 Scholar loyalty", effects = {}, loyalty_effects = {nobles = 5, scholars = -3}},
			choice_b_disloyal = {label = "Reject Firmly", tooltip = "Risk unrest: -6 Noble loyalty, +2 Scholar loyalty", effects = {}, loyalty_effects = {nobles = -6, scholars = 2}},
		},
		{
			title = "Tax Reform",
			text_loyal = "The senate nobles propose favorable tax reforms to reward loyal subjects.",
			text_disloyal = "The nobles demand tax exemptions for the aristocracy.",
			choice_a_loyal = {label = "Enact Reforms", tooltip = "Noble tax plan: +80 Gold, -2 Peasant loyalty", effects = {0: 80}, loyalty_effects = {peasants = -2, nobles = 3}},
			choice_b_loyal = {label = "Fair Taxation", tooltip = "Balance: +40 Gold, +1 Peasant loyalty", effects = {0: 40}, loyalty_effects = {peasants = 1}},
			choice_a_disloyal = {label = "Grant Exemptions", tooltip = "Costly peace: -60 Gold, +6 Noble loyalty", effects = {0: -60}, loyalty_effects = {nobles = 6}},
			choice_b_disloyal = {label = "Tax Everyone Equally", tooltip = "Anger nobles: -4 Noble loyalty, +3 Peasant loyalty", effects = {}, loyalty_effects = {nobles = -4, peasants = 3}},
		},
	],
	&"scholars": [
		{
			title = "Academic Petition",
			text_loyal = "The scholars request funding for a grand research initiative.",
			text_disloyal = "The scholarly class threatens to withhold discoveries unless funded.",
			choice_a_loyal = {label = "Fund Research", tooltip = "Invest in knowledge: -40 Gold, +30 Tech, +3 Scholar loyalty", effects = {0: -40, 2: 30}, loyalty_effects = {scholars = 3}},
			choice_b_loyal = {label = "Redirect Funds", tooltip = "Practical spending: +50 Gold", effects = {0: 50}, loyalty_effects = {scholars = -1}},
			choice_a_disloyal = {label = "Meet Demands", tooltip = "Pay for peace: -80 Gold, +40 Tech, +6 Scholar loyalty", effects = {0: -80, 2: 40}, loyalty_effects = {scholars = 6}},
			choice_b_disloyal = {label = "Refuse Funding", tooltip = "Risk brain drain: -5 Scholar loyalty", effects = {}, loyalty_effects = {scholars = -5}},
		},
		{
			title = "Forbidden Knowledge",
			text_loyal = "Trusted scholars discovered ancient texts and seek permission to study them.",
			text_disloyal = "Scholars are secretly studying forbidden texts. You must decide how to respond.",
			choice_a_loyal = {label = "Authorize Study", tooltip = "Risky knowledge: +50 Tech, -2 Peasant loyalty", effects = {2: 50}, loyalty_effects = {peasants = -2, scholars = 3}},
			choice_b_loyal = {label = "Seal the Texts", tooltip = "Play it safe: +2 Peasant loyalty, -1 Scholar loyalty", effects = {}, loyalty_effects = {peasants = 2, scholars = -1}},
			choice_a_disloyal = {label = "Confiscate Research", tooltip = "Seize findings: +30 Tech, -6 Scholar loyalty", effects = {2: 30}, loyalty_effects = {scholars = -6}},
			choice_b_disloyal = {label = "Look the Other Way", tooltip = "Ignore it: +20 Tech, +3 Scholar loyalty", effects = {2: 20}, loyalty_effects = {scholars = 3}},
		},
		{
			title = "University Expansion",
			text_loyal = "The scholars propose expanding the university to attract new minds.",
			text_disloyal = "The scholars demand a new university wing or they'll leave for rival courts.",
			choice_a_loyal = {label = "Expand University", tooltip = "Build: -60 Gold, -20 Wood, +4 Scholar loyalty, +20 Tech", effects = {0: -60, 5: -20, 2: 20}, loyalty_effects = {scholars = 4}},
			choice_b_loyal = {label = "Postpone", tooltip = "Save resources: -1 Scholar loyalty", effects = {}, loyalty_effects = {scholars = -1}},
			choice_a_disloyal = {label = "Build Immediately", tooltip = "Expensive: -100 Gold, -30 Wood, +8 Scholar loyalty", effects = {0: -100, 5: -30}, loyalty_effects = {scholars = 8}},
			choice_b_disloyal = {label = "Deny Request", tooltip = "Scholars leave: -6 Scholar loyalty, +2 Noble loyalty", effects = {}, loyalty_effects = {scholars = -6, nobles = 2}},
		},
	],
	&"artisans": [
		{
			title = "Guild Petition",
			text_loyal = "The artisan guilds request tax breaks to boost production.",
			text_disloyal = "The artisan guilds threaten a work stoppage unless conditions improve.",
			choice_a_loyal = {label = "Grant Tax Break", tooltip = "Boost industry: -30 Gold, +20 Iron, +20 Wood, +3 Artisan loyalty", effects = {0: -30, 1: 20, 5: 20}, loyalty_effects = {artisans = 3}},
			choice_b_loyal = {label = "Offer Contracts", tooltip = "Compromise: +10 Iron, +10 Wood", effects = {1: 10, 5: 10}, loyalty_effects = {artisans = 1}},
			choice_a_disloyal = {label = "Appease Guilds", tooltip = "Costly: -60 Gold, +6 Artisan loyalty", effects = {0: -60}, loyalty_effects = {artisans = 6}},
			choice_b_disloyal = {label = "Ignore Threats", tooltip = "Risk strike: -5 Artisan loyalty", effects = {}, loyalty_effects = {artisans = -5}},
		},
		{
			title = "Trade Route Dispute",
			text_loyal = "Artisans propose a new trade route that could enrich the province.",
			text_disloyal = "Rival artisan factions fight over trade routes, disrupting commerce.",
			choice_a_loyal = {label = "Open Route", tooltip = "New trade: +50 Gold, +15 Iron, +2 Artisan loyalty", effects = {0: 50, 1: 15}, loyalty_effects = {artisans = 2}},
			choice_b_loyal = {label = "Maintain Current", tooltip = "Stability: +20 Gold", effects = {0: 20}, loyalty_effects = {}},
			choice_a_disloyal = {label = "Mediate Dispute", tooltip = "Expensive peace: -40 Gold, +4 Artisan loyalty", effects = {0: -40}, loyalty_effects = {artisans = 4}},
			choice_b_disloyal = {label = "Let Them Fight", tooltip = "Chaos: -4 Artisan loyalty, +20 Iron (salvage)", effects = {1: 20}, loyalty_effects = {artisans = -4}},
		},
		{
			title = "Workshop Safety",
			text_loyal = "Artisans request improved workshop conditions to prevent accidents.",
			text_disloyal = "Workers demand safer conditions after a series of workshop accidents.",
			choice_a_loyal = {label = "Improve Workshops", tooltip = "Invest: -40 Gold, -15 Wood, +4 Artisan loyalty, +3 Peasant loyalty", effects = {0: -40, 5: -15}, loyalty_effects = {artisans = 4, peasants = 3}},
			choice_b_loyal = {label = "Minor Fixes", tooltip = "Token effort: -15 Gold, +1 Artisan loyalty", effects = {0: -15}, loyalty_effects = {artisans = 1}},
			choice_a_disloyal = {label = "Full Overhaul", tooltip = "Major cost: -80 Gold, -25 Wood, +7 Artisan loyalty", effects = {0: -80, 5: -25}, loyalty_effects = {artisans = 7}},
			choice_b_disloyal = {label = "Dismiss Concerns", tooltip = "Ignore: -5 Artisan loyalty, -2 Peasant loyalty", effects = {}, loyalty_effects = {artisans = -5, peasants = -2}},
		},
	],
}

func check_senate_dilemma(faction_id: StringName, current_turn: int) -> Dictionary:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	if current_turn < fs.senate_dilemma_next_turn:
		return {}
	var majority := get_senate_majority(faction_id)
	if majority == &"forsaken":
		return {}  # Forsaken has its own crisis system
	if not SENATE_DILEMMAS.has(majority):
		return {}
	var capital := _get_faction_capital(faction_id)
	if capital == null:
		return {}

	var templates: Array = SENATE_DILEMMAS[majority]
	var template: Dictionary = templates[randi() % templates.size()]
	var class_key := str(majority)
	var class_loyalty: int = capital.class_loyalty.get(class_key, 0)
	var is_loyal := class_loyalty >= 40

	var dilemma := {
		title = template.title,
		text = template.text_loyal if is_loyal else template.text_disloyal,
		choice_a = template.choice_a_loyal if is_loyal else template.choice_a_disloyal,
		choice_b = template.choice_b_loyal if is_loyal else template.choice_b_disloyal,
		majority = majority,
		is_loyal = is_loyal,
	}
	return dilemma

func apply_senate_dilemma_choice(faction_id: StringName, dilemma: Dictionary, choice: String) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	var chosen: Dictionary = dilemma.choice_a if choice == "a" else dilemma.choice_b
	# Apply resource effects
	var effects: Dictionary = chosen.get("effects", {})
	for res_type in effects:
		fs.resources[res_type] = fs.resources.get(res_type, 0) + effects[res_type]
	# Apply loyalty effects
	var capital := _get_faction_capital(faction_id)
	if capital:
		var loyalty_effects: Dictionary = chosen.get("loyalty_effects", {})
		for cls in loyalty_effects:
			capital.class_loyalty[cls] = clampi(capital.class_loyalty.get(cls, 0) + loyalty_effects[cls], -100, 100)
	# Set cooldown
	fs.senate_dilemma_next_turn = GameManager.state.current_turn + randi_range(5, 8)

func dismiss_senate_dilemma(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return
	fs.senate_dilemma_next_turn = GameManager.state.current_turn + randi_range(5, 8)
