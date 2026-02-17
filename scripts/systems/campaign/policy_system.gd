class_name PolicySystem
extends RefCounted

const MAX_ACTIVE_POLICIES := 3
const CATEGORY_COOLDOWN_TURNS := 3
const TOTAL_SENATE_SEATS := 50

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
	# Apply active policy effects
	var to_revoke: Array[StringName] = []
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data == null:
			continue
		# Apply resource effects
		for res_type in data.resource_effects:
			fs.resources[res_type] = fs.resources.get(res_type, 0) + data.resource_effects[res_type]
		# Apply class loyalty effects to capital
		if capital:
			for cls in data.class_loyalty_effects:
				if capital.class_loyalty.has(cls):
					capital.class_loyalty[cls] = clampi(
						capital.class_loyalty[cls] + data.class_loyalty_effects[cls], -100, 100)
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
	# Apply senate majority loyalty bonus
	if capital:
		var majority := get_senate_majority(faction_id)
		if majority == &"nobles":
			capital.class_loyalty["nobles"] = clampi(capital.class_loyalty.get("nobles", 0) + 1, -100, 100)
		elif majority == &"scholars":
			capital.class_loyalty["scholars"] = clampi(capital.class_loyalty.get("scholars", 0) + 1, -100, 100)
		elif majority == &"artisans":
			capital.class_loyalty["artisans"] = clampi(capital.class_loyalty.get("artisans", 0) + 1, -100, 100)
		elif majority == &"forsaken":
			for cls in capital.class_loyalty:
				capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] - 3, -100, 100)
	# Process Forsaken crisis
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
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	var changes: Dictionary = {} # class_name -> int change per turn
	for policy_id in fs.active_policies:
		var data: PolicyData = DataManager.policies.get(policy_id)
		if data == null:
			continue
		for cls in data.class_loyalty_effects:
			changes[cls] = changes.get(cls, 0) + data.class_loyalty_effects[cls]
	# Include senate majority loyalty effects
	var majority := get_senate_majority(faction_id)
	if majority == &"nobles":
		changes["nobles"] = changes.get("nobles", 0) + 1
	elif majority == &"scholars":
		changes["scholars"] = changes.get("scholars", 0) + 1
	elif majority == &"artisans":
		changes["artisans"] = changes.get("artisans", 0) + 1
	elif majority == &"forsaken":
		var capital := _get_faction_capital(faction_id)
		if capital:
			for cls in capital.class_loyalty:
				changes[cls] = changes.get(cls, 0) - 3
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

func get_senate_majority_effects(faction_id: StringName) -> Dictionary:
	var majority := get_senate_majority(faction_id)
	match majority:
		&"nobles":
			return {gold_income_pct = 10, tech_income_pct = -5}
		&"scholars":
			return {tech_income_pct = 10, gold_income_pct = -5}
		&"artisans":
			return {iron_income_pct = 5, wood_income_pct = 5}
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
	var resource_options := [
		{resource_type = Enums.ResourceType.GOLD, display = "Gold"},
		{resource_type = Enums.ResourceType.IRON, display = "Iron"},
		{resource_type = Enums.ResourceType.WOOD, display = "Wood"},
	]
	var chosen := resource_options[randi() % resource_options.size()]
	var amount := base_amount if chosen.resource_type == Enums.ResourceType.GOLD else int(base_amount * 0.5)
	var seats_requested := randi_range(2, 4)

	var flavors := [
		"The shadows whisper of mutual benefit...",
		"A hooded emissary offers a sealed chest.",
		"Dark coin flows from places best left unnamed.",
		"The Forsaken extend an open hand... for now.",
	]

	return {
		resource_type = chosen.resource_type,
		resource_name = chosen.display,
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
	var seats := calculate_senate_seats(faction_id)
	var forsaken_count: int = seats[3]
	var has_majority := forsaken_count >= TOTAL_SENATE_SEATS / 2

	if not has_majority:
		fs.forsaken_crisis_stage = 0
		return

	fs.forsaken_crisis_stage += 1

	match fs.forsaken_crisis_stage:
		1:
			# "Whispers of Corruption" — loyalty drop, senate paralyzed
			if capital:
				for cls in capital.class_loyalty:
					capital.class_loyalty[cls] = clampi(capital.class_loyalty[cls] - 5, -100, 100)
		3:
			# "The Forsaken Demand" — dilemma handled by UI via signal
			EventBus.forsaken_offer.emit(faction_id, {type = "crisis_dilemma", stage = 3})
		6:
			# "Civil Unrest" — capital loyalty crashes
			if capital:
				capital.loyalty = -50
			# Random army deserts if still Forsaken majority
			var armies := GameManager.get_faction_armies(faction_id)
			if armies.size() > 0:
				var victim: ArmyState = armies[randi() % armies.size()]
				GameManager.remove_army(victim.army_id)

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
