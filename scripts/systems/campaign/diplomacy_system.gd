class_name DiplomacySystem
extends RefCounted

# Gift tiers: Small / Medium / Large
const GIFT_TIERS := [15, 40, 80]

# ── Standing Management ─────────────────────────────────────

func get_standing(faction_a: StringName, faction_b: StringName) -> int:
	if faction_a == faction_b:
		return 100
	var key := _standing_key(faction_a, faction_b)
	return GameManager.state.diplomacy_state.standing.get(key, 0)

func modify_standing(faction_a: StringName, faction_b: StringName, delta: int) -> void:
	var key := _standing_key(faction_a, faction_b)
	var current: int = GameManager.state.diplomacy_state.standing.get(key, 0)
	var new_val := clampi(current + delta, -100, 100)
	GameManager.state.diplomacy_state.standing[key] = new_val
	# Mirror: standing is symmetric
	var mirror_key := _standing_key(faction_b, faction_a)
	GameManager.state.diplomacy_state.standing[mirror_key] = new_val
	EventBus.standing_changed.emit(faction_a, faction_b, new_val)

func _standing_key(a: StringName, b: StringName) -> String:
	return str(a) + ":" + str(b)

# ── Cooldown helpers ────────────────────────────────────────

func _get_cooldown(faction_a: StringName, faction_b: StringName, action: String) -> int:
	var key := str(faction_a) + ":" + str(faction_b) + ":" + action
	return GameManager.state.diplomacy_state.cooldowns.get(key, 0)

func _set_cooldown(faction_a: StringName, faction_b: StringName, action: String, turns: int) -> void:
	var key := str(faction_a) + ":" + str(faction_b) + ":" + action
	GameManager.state.diplomacy_state.cooldowns[key] = turns

# ── Gift Tracking ──────────────────────────────────────────

func has_gifted_this_turn(from: StringName, to: StringName) -> bool:
	var key := str(from) + ":" + str(to)
	return GameManager.state.diplomacy_state.gifts_this_turn.get(key, false)

func _mark_gifted(from: StringName, to: StringName) -> void:
	var key := str(from) + ":" + str(to)
	GameManager.state.diplomacy_state.gifts_this_turn[key] = true

func reset_gifts_this_turn() -> void:
	GameManager.state.diplomacy_state.gifts_this_turn.clear()

# ── War Exhaustion ──────────────────────────────────────────

func _calculate_war_exhaustion(faction_id: StringName) -> float:
	# Higher exhaustion = more willing to accept peace
	var exhaustion := 0.0
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return 0.0
	# Fewer armies = more exhausted
	var army_count := 0
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and not army.is_garrison:
			army_count += 1
	if army_count <= 1:
		exhaustion += 0.5
	# Cities under siege
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id and city.is_under_siege:
			exhaustion += 0.3
	# Low resources
	var gold: int = fs.resources.get(Enums.ResourceType.GOLD, 0)
	if gold < 50:
		exhaustion += 0.2
	return minf(exhaustion, 1.0)

# ── Strength Comparison ─────────────────────────────────────

func _calculate_faction_strength(faction_id: StringName) -> int:
	var strength := 0
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == faction_id and not army.is_garrison:
			for unit in army.units:
				var ud := DataManager.get_unit(unit.unit_data_id)
				if ud:
					# Factor in combat stats, HP, and current health
					var base := ud.attack + ud.defense
					var hp_factor := ud.max_hp / 500.0  # normalize so ~500 HP = 1.0
					var hp_ratio := float(unit.current_hp) / float(ud.max_hp) if ud.max_hp > 0 else 1.0
					# Expensive units are more intimidating — total upkeep adds weight
					var upkeep_bonus := 0.0
					for res_type in ud.upkeep_cost:
						upkeep_bonus += ud.upkeep_cost[res_type]
					var upkeep_factor := 1.0 + upkeep_bonus * 0.1  # +10% per 1 upkeep point
					strength += int(base * hp_factor * hp_ratio * upkeep_factor)
	return strength

func get_strength_ratio(faction_a: StringName, faction_b: StringName) -> float:
	var a_str := _calculate_faction_strength(faction_a)
	var b_str := _calculate_faction_strength(faction_b)
	if b_str <= 0:
		return 10.0
	return float(a_str) / float(b_str)

# ── Third-Party Standing Effects ────────────────────────────

func _apply_friendly_action_ripple(actor: StringName, target: StringName, magnitude: int) -> void:
	# Factions at war with target dislike the actor for being friendly
	for other_id in GameManager.state.faction_states:
		if other_id == actor or other_id == target or GameManager.is_npc_faction(other_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[other_id]
		if fs.is_defeated:
			continue
		var their_relation_to_target := GameManager.get_relation(other_id, target)
		if their_relation_to_target == Enums.FactionRelation.WAR:
			modify_standing(actor, other_id, -magnitude)

func _apply_hostile_action_ripple(actor: StringName, target: StringName, magnitude: int) -> void:
	# Factions at war with target like the actor for being hostile to their enemy
	for other_id in GameManager.state.faction_states:
		if other_id == actor or other_id == target or GameManager.is_npc_faction(other_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[other_id]
		if fs.is_defeated:
			continue
		var their_relation_to_target := GameManager.get_relation(other_id, target)
		if their_relation_to_target == Enums.FactionRelation.WAR:
			modify_standing(actor, other_id, magnitude)

# ── Player Actions ──────────────────────────────────────────

func declare_war(attacker: StringName, target: StringName) -> void:
	var key_ab := StringName(str(attacker) + ":" + str(target))
	var key_ba := StringName(str(target) + ":" + str(attacker))
	GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.WAR
	GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.WAR
	_cancel_treaties_between(attacker, target)
	modify_standing(attacker, target, -30)
	_apply_hostile_action_ripple(attacker, target, 5)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DECLARE_WAR, attacker, target)

func propose_peace(proposer: StringName, target: StringName) -> Dictionary:
	if _get_cooldown(proposer, target, "peace") > 0:
		return {accepted = false, reason = "Peace cooldown active"}
	var score := _evaluate_peace(proposer, target)
	if score > 0:
		var key_ab := StringName(str(proposer) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(proposer))
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
		modify_standing(proposer, target, 10)
		_set_cooldown(proposer, target, "peace", 3)
		_set_cooldown(target, proposer, "peace", 3)
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.PEACE
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = -1
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		_apply_friendly_action_ripple(proposer, target, 3)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_PEACE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.PEACE, proposer, target)
		return {accepted = true, reason = "Peace accepted"}
	return {accepted = false, reason = "They are not ready for peace"}

func propose_alliance(proposer: StringName, target: StringName) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
		return {accepted = false, reason = "Relations too poor"}
	var score := _evaluate_alliance(proposer, target)
	if score > 0:
		var key_ab := StringName(str(proposer) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(proposer))
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.ALLIED
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.ALLIED
		modify_standing(proposer, target, 15)
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.ALLIANCE
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = -1
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		_apply_friendly_action_ripple(proposer, target, 5)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_ALLIANCE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.ALLIANCE, proposer, target)
		return {accepted = true, reason = "Alliance formed"}
	return {accepted = false, reason = "They decline the alliance"}

func propose_trade(proposer: StringName, target: StringName, give_res: int, give_amt: int, recv_res: int, recv_amt: int, duration: int) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if relation == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "Cannot trade during war"}
	if give_res == recv_res:
		return {accepted = false, reason = "Cannot trade the same resource for itself"}
	var score := _evaluate_trade(proposer, target, give_res, give_amt, recv_res, recv_amt)
	if score > 0:
		modify_standing(proposer, target, 5)
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.TRADE_DEAL
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = duration
		treaty.terms = {
			give_resource = give_res,
			give_amount = give_amt,
			receive_resource = recv_res,
			receive_amount = recv_amt,
		}
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		_apply_friendly_action_ripple(proposer, target, 2)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRADE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_DEAL, proposer, target)
		return {accepted = true, reason = "Trade deal accepted"}
	return {accepted = false, reason = "They find the terms unfavorable"}

func gift_resources(from: StringName, to: StringName, res_type: int, amount: int) -> bool:
	var from_fs: FactionState = GameManager.state.faction_states.get(from)
	var to_fs: FactionState = GameManager.state.faction_states.get(to)
	if from_fs == null or to_fs == null:
		return false
	if has_gifted_this_turn(from, to):
		return false
	if from_fs.resources.get(res_type, 0) < amount:
		return false
	from_fs.resources[res_type] -= amount
	to_fs.resources[res_type] = to_fs.resources.get(res_type, 0) + amount
	var standing_gain := clampi(amount / 5, 1, 20)
	modify_standing(from, to, standing_gain)
	_mark_gifted(from, to)
	_apply_friendly_action_ripple(from, to, 2)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.GIFT_RESOURCES, from, to)
	return true

func offer_shard(from: StringName, to: StringName, shard_id: StringName) -> void:
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null or shard.claimed_by != from:
		return
	var from_fs: FactionState = GameManager.state.faction_states.get(from)
	var to_fs: FactionState = GameManager.state.faction_states.get(to)
	if from_fs == null or to_fs == null:
		return
	from_fs.owned_shards.erase(shard_id)
	to_fs.owned_shards.append(shard_id)
	shard.claimed_by = to
	var standing_gain := shard.power_level * 5
	modify_standing(from, to, standing_gain)
	_apply_friendly_action_ripple(from, to, 3)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_SHARD, from, to)

func threaten(threatener: StringName, target: StringName, last_offer: Dictionary) -> Dictionary:
	# Threatening always costs standing
	modify_standing(threatener, target, -10)
	_apply_hostile_action_ripple(threatener, target, 3)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.THREATEN, threatener, target)

	var ratio := get_strength_ratio(threatener, target)
	var accepted := false
	if ratio >= 2.0:
		# Much stronger: they capitulate
		accepted = true
	elif ratio >= 1.5:
		# Stronger: 75% chance
		accepted = randf() < 0.75
	elif ratio >= 1.0:
		# Roughly equal: 35% chance
		accepted = randf() < 0.35
	# Weaker: never works

	if not accepted:
		return {accepted = false, reason = "They are not intimidated by your threats."}

	# Re-execute the original offer
	var action: String = last_offer.get("action", "")
	match action:
		"peace":
			var key_ab := StringName(str(threatener) + ":" + str(target))
			var key_ba := StringName(str(target) + ":" + str(threatener))
			GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
			GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
			_set_cooldown(threatener, target, "peace", 3)
			_set_cooldown(target, threatener, "peace", 3)
			var treaty := TreatyInstance.new()
			treaty.treaty_id = GameManager.state.generate_id()
			treaty.treaty_type = Enums.TreatyType.PEACE
			treaty.faction_a = threatener
			treaty.faction_b = target
			treaty.turns_remaining = -1
			GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
			EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.PEACE, threatener, target)
			return {accepted = true, reason = "Intimidated, they agree to peace."}
		"alliance":
			var key_ab := StringName(str(threatener) + ":" + str(target))
			var key_ba := StringName(str(target) + ":" + str(threatener))
			GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.ALLIED
			GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.ALLIED
			var treaty := TreatyInstance.new()
			treaty.treaty_id = GameManager.state.generate_id()
			treaty.treaty_type = Enums.TreatyType.ALLIANCE
			treaty.faction_a = threatener
			treaty.faction_b = target
			treaty.turns_remaining = -1
			GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
			EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.ALLIANCE, threatener, target)
			return {accepted = true, reason = "Under pressure, they accept the alliance."}
		"trade":
			var give_res: int = last_offer.get("give_res", 0)
			var give_amt: int = last_offer.get("give_amt", 0)
			var recv_res: int = last_offer.get("recv_res", 0)
			var recv_amt: int = last_offer.get("recv_amt", 0)
			var duration: int = last_offer.get("duration", 5)
			var treaty := TreatyInstance.new()
			treaty.treaty_id = GameManager.state.generate_id()
			treaty.treaty_type = Enums.TreatyType.TRADE_DEAL
			treaty.faction_a = threatener
			treaty.faction_b = target
			treaty.turns_remaining = duration
			treaty.terms = {
				give_resource = give_res,
				give_amount = give_amt,
				receive_resource = recv_res,
				receive_amount = recv_amt,
			}
			GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
			EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_DEAL, threatener, target)
			return {accepted = true, reason = "Coerced, they accept the trade deal."}

	return {accepted = false, reason = "Invalid threat target."}

# ── Trade Relations ────────────────────────────────────────

func get_top_produced_resource(faction_id: StringName) -> int:
	# Returns the ResourceType the faction produces the most (based on city income totals)
	# Excludes CAPTIVES and SHARD_ESSENCE as they are special
	var totals: Dictionary = {} # ResourceType -> int
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		if city.is_under_siege:
			continue
		var income := GameManager.city_system.calculate_city_income(city)
		for res_type in income:
			if res_type == Enums.ResourceType.CAPTIVES or res_type == Enums.ResourceType.SHARD_ESSENCE:
				continue
			totals[res_type] = totals.get(res_type, 0) + income[res_type]
	var best_type: int = Enums.ResourceType.GOLD
	var best_amount: int = 0
	for res_type in totals:
		if totals[res_type] > best_amount:
			best_amount = totals[res_type]
			best_type = res_type
	return best_type

func get_faction_resource_income(faction_id: StringName, res_type: int) -> int:
	var total := 0
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id or city.is_under_siege:
			continue
		var income := GameManager.city_system.calculate_city_income(city)
		total += income.get(res_type, 0)
	return total

func get_trade_relations_share(turns_active: int) -> float:
	# Starts at 5%, +0.5% per turn, caps at 15%
	return minf(5.0 + float(turns_active) * 0.5, 15.0)

func propose_trade_relations(proposer: StringName, target: StringName) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
		return {accepted = false, reason = "Relations too poor for trade"}
	# Check if already have trade relations
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				return {accepted = false, reason = "Trade relations already established"}
	var score := _evaluate_trade_relations(proposer, target)
	if score > 0:
		var res_a := get_top_produced_resource(proposer)
		var res_b := get_top_produced_resource(target)
		modify_standing(proposer, target, 5)
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.TRADE_RELATIONS
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = -1 # permanent until cancelled or war
		treaty.terms = {
			resource_a = res_a,
			resource_b = res_b,
			turns_active = 0,
		}
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		_apply_friendly_action_ripple(proposer, target, 2)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRADE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_RELATIONS, proposer, target)
		return {accepted = true, reason = "Trade relations established!"}
	return {accepted = false, reason = "They see no benefit in trade relations"}

func _evaluate_trade_relations(proposer: StringName, target: StringName) -> float:
	var standing := get_standing(proposer, target)
	if standing <= -30:
		return -100.0
	# Friendlier factions are more willing; baseline at standing 0 is ~40% likely
	return standing * 0.6 + 10.0

func _execute_trade_relations(treaty: TreatyInstance) -> void:
	var fs_a: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
	var fs_b: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
	if fs_a == null or fs_b == null:
		return
	var turns_active: int = treaty.terms.get("turns_active", 0)
	var share_pct := get_trade_relations_share(turns_active) / 100.0
	var res_a: int = treaty.terms.get("resource_a", 0)
	var res_b: int = treaty.terms.get("resource_b", 0)
	# Faction A shares their top resource with B
	var income_a := get_faction_resource_income(treaty.faction_a, res_a)
	var transfer_to_b := maxi(1, int(float(income_a) * share_pct))
	fs_b.resources[res_a] = fs_b.resources.get(res_a, 0) + transfer_to_b
	# Faction B shares their top resource with A
	var income_b := get_faction_resource_income(treaty.faction_b, res_b)
	var transfer_to_a := maxi(1, int(float(income_b) * share_pct))
	fs_a.resources[res_b] = fs_a.resources.get(res_b, 0) + transfer_to_a
	# Increment turns active
	treaty.terms["turns_active"] = turns_active + 1
	# Standing bonus every 3 turns
	if (turns_active + 1) % 3 == 0:
		modify_standing(treaty.faction_a, treaty.faction_b, 1)

# ── Per-Turn Processing ─────────────────────────────────────

func process_treaties(faction_id: StringName) -> void:
	var to_expire: Array[StringName] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		# Only process on faction_a's turn to avoid double-processing
		if treaty.faction_a != faction_id:
			continue
		# Execute trade transfers
		if treaty.treaty_type == Enums.TreatyType.TRADE_DEAL:
			_execute_trade(treaty)
		elif treaty.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
			_execute_trade_relations(treaty)
		# Active treaties cause ongoing malus with treaty partner's enemies
		_apply_treaty_enemy_malus(faction_id, treaty)
		# Decrement duration
		if treaty.turns_remaining > 0:
			treaty.turns_remaining -= 1
			if treaty.turns_remaining <= 0:
				to_expire.append(treaty_id)
	# Expire finished treaties
	for treaty_id in to_expire:
		GameManager.state.diplomacy_state.treaties.erase(treaty_id)
		EventBus.treaty_expired.emit(treaty_id)
	# Decrement cooldowns for this faction
	var keys_to_remove: Array = []
	for key in GameManager.state.diplomacy_state.cooldowns:
		var key_str: String = str(key)
		if key_str.begins_with(str(faction_id) + ":"):
			GameManager.state.diplomacy_state.cooldowns[key] -= 1
			if GameManager.state.diplomacy_state.cooldowns[key] <= 0:
				keys_to_remove.append(key)
	for key in keys_to_remove:
		GameManager.state.diplomacy_state.cooldowns.erase(key)

func _apply_treaty_enemy_malus(faction_id: StringName, treaty: TreatyInstance) -> void:
	# Having a treaty with a faction makes their enemies dislike you slightly each turn
	var partner: StringName
	if treaty.faction_a == faction_id:
		partner = treaty.faction_b
	else:
		partner = treaty.faction_a
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or other_id == partner or GameManager.is_npc_faction(other_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[other_id]
		if fs.is_defeated:
			continue
		if GameManager.get_relation(other_id, partner) == Enums.FactionRelation.WAR:
			modify_standing(faction_id, other_id, -1)

func _execute_trade(treaty: TreatyInstance) -> void:
	var fs_a: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
	var fs_b: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
	if fs_a == null or fs_b == null:
		return
	var give_res: int = treaty.terms.get("give_resource", 0)
	var give_amt: int = treaty.terms.get("give_amount", 0)
	var recv_res: int = treaty.terms.get("receive_resource", 0)
	var recv_amt: int = treaty.terms.get("receive_amount", 0)
	var actual_give := mini(give_amt, fs_a.resources.get(give_res, 0))
	fs_a.resources[give_res] = fs_a.resources.get(give_res, 0) - actual_give
	fs_b.resources[give_res] = fs_b.resources.get(give_res, 0) + actual_give
	var actual_recv := mini(recv_amt, fs_b.resources.get(recv_res, 0))
	fs_b.resources[recv_res] = fs_b.resources.get(recv_res, 0) - actual_recv
	fs_a.resources[recv_res] = fs_a.resources.get(recv_res, 0) + actual_recv

# ── AI Evaluation ───────────────────────────────────────────

func _evaluate_peace(proposer: StringName, target: StringName) -> float:
	var standing := get_standing(proposer, target)
	var exhaustion := _calculate_war_exhaustion(target)
	var my_strength := _calculate_faction_strength(target)
	var their_strength := _calculate_faction_strength(proposer)
	var strength_comparison := 0.0
	if my_strength > 0:
		strength_comparison = (float(their_strength) / float(my_strength) - 1.0) * 20.0
	return standing * 0.3 + exhaustion * 40.0 + strength_comparison - 20.0

func _evaluate_alliance(proposer: StringName, target: StringName) -> float:
	var standing := get_standing(proposer, target)
	var my_strength := _calculate_faction_strength(target)
	var their_strength := _calculate_faction_strength(proposer)
	var strength_bonus := 0.0
	if my_strength > 0:
		strength_bonus = minf(float(their_strength) / float(my_strength), 2.0) * 10.0
	return standing * 0.5 + strength_bonus - 30.0

func _evaluate_trade(proposer: StringName, target: StringName, give_res: int, give_amt: int, recv_res: int, recv_amt: int) -> float:
	var standing := get_standing(proposer, target)
	if standing <= -50:
		return -100.0
	var fairness := 0.0
	if recv_amt > 0:
		fairness = float(give_amt) / float(recv_amt)
	else:
		fairness = 2.0 if give_amt > 0 else 0.0
	# Friendly factions are more generous — at standing 50: required ~0.4 (was 0.6)
	# Hostile factions demand more — at standing -40: required ~1.5
	var required_fairness := 1.0 - standing * 0.012
	return (fairness - required_fairness) * 50.0

# ── AI Diplomacy Turn ───────────────────────────────────────

func execute_ai_diplomacy(faction_id: StringName) -> void:
	if GameManager.state.current_turn % 5 != 0:
		return

	var my_enemies: Array[StringName] = []
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or GameManager.is_npc_faction(other_id):
			continue
		if GameManager.get_relation(faction_id, other_id) == Enums.FactionRelation.WAR:
			my_enemies.append(other_id)

	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or GameManager.is_npc_faction(other_id):
			continue
		var other_fs: FactionState = GameManager.state.faction_states[other_id]
		if other_fs.is_defeated:
			continue
		var relation := GameManager.get_relation(faction_id, other_id)

		if relation == Enums.FactionRelation.WAR:
			var exhaustion := _calculate_war_exhaustion(faction_id)
			if exhaustion >= 0.5:
				propose_peace(faction_id, other_id)

		elif relation == Enums.FactionRelation.FRIENDLY or relation == Enums.FactionRelation.NEUTRAL:
			var shared_enemies := 0
			for enemy_id in my_enemies:
				if GameManager.get_relation(other_id, enemy_id) == Enums.FactionRelation.WAR:
					shared_enemies += 1
			if shared_enemies > 0 and relation == Enums.FactionRelation.FRIENDLY:
				var standing := get_standing(faction_id, other_id)
				if standing >= 20:
					propose_alliance(faction_id, other_id)
			elif relation != Enums.FactionRelation.WAR:
				var standing := get_standing(faction_id, other_id)
				# Try trade relations first if standing is decent
				if standing >= 5:
					propose_trade_relations(faction_id, other_id)
				elif standing >= 10:
					var fs: FactionState = GameManager.state.faction_states.get(faction_id)
					if fs:
						var my_gold: int = fs.resources.get(Enums.ResourceType.GOLD, 0)
						var my_iron: int = fs.resources.get(Enums.ResourceType.IRON, 0)
						if my_gold > 200 and my_iron < 50:
							propose_trade(faction_id, other_id, Enums.ResourceType.GOLD, 20, Enums.ResourceType.IRON, 10, 5)
						elif my_iron > 100 and my_gold < 100:
							propose_trade(faction_id, other_id, Enums.ResourceType.IRON, 10, Enums.ResourceType.GOLD, 20, 5)

		elif relation == Enums.FactionRelation.FRIENDLY:
			var standing := get_standing(faction_id, other_id)
			if standing >= 30:
				propose_alliance(faction_id, other_id)

# ── Treaty Helpers ──────────────────────────────────────────

func _cancel_treaties_between(faction_a: StringName, faction_b: StringName) -> void:
	var to_remove: Array[StringName] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if (treaty.faction_a == faction_a and treaty.faction_b == faction_b) or \
		   (treaty.faction_a == faction_b and treaty.faction_b == faction_a):
			to_remove.append(treaty_id)
	for treaty_id in to_remove:
		GameManager.state.diplomacy_state.treaties.erase(treaty_id)
		EventBus.treaty_expired.emit(treaty_id)

func get_treaties_for_faction(faction_id: StringName) -> Array[TreatyInstance]:
	var result: Array[TreatyInstance] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if treaty.faction_a == faction_id or treaty.faction_b == faction_id:
			result.append(treaty)
	return result

func break_alliance_on_attack(attacker: StringName, defender: StringName) -> void:
	var relation := GameManager.get_relation(attacker, defender)
	if relation == Enums.FactionRelation.ALLIED:
		declare_war(attacker, defender)

func get_treaties_between(faction_a: StringName, faction_b: StringName) -> Array[TreatyInstance]:
	var result: Array[TreatyInstance] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if (treaty.faction_a == faction_a and treaty.faction_b == faction_b) or \
		   (treaty.faction_a == faction_b and treaty.faction_b == faction_a):
			result.append(treaty)
	return result
