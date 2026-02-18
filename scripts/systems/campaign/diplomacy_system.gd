class_name DiplomacySystem
extends RefCounted

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
					strength += ud.attack + ud.defense
	return strength

# ── Player Actions ──────────────────────────────────────────

func declare_war(attacker: StringName, target: StringName) -> void:
	# Set relation WAR both directions
	var key_ab := StringName(str(attacker) + ":" + str(target))
	var key_ba := StringName(str(target) + ":" + str(attacker))
	GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.WAR
	GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.WAR
	# Cancel all treaties between them
	_cancel_treaties_between(attacker, target)
	# Standing penalty
	modify_standing(attacker, target, -30)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DECLARE_WAR, attacker, target)

func propose_peace(proposer: StringName, target: StringName) -> Dictionary:
	# Check cooldown
	if _get_cooldown(proposer, target, "peace") > 0:
		return {accepted = false, reason = "Peace cooldown active"}
	# AI evaluation
	var score := _evaluate_peace(proposer, target)
	if score > 0:
		# Accept peace
		var key_ab := StringName(str(proposer) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(proposer))
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
		modify_standing(proposer, target, 10)
		_set_cooldown(proposer, target, "peace", 3)
		_set_cooldown(target, proposer, "peace", 3)
		# Create peace treaty
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.PEACE
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = -1
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_PEACE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.PEACE, proposer, target)
		return {accepted = true, reason = "Peace accepted"}
	return {accepted = false, reason = "They are not ready for peace"}

func propose_alliance(proposer: StringName, target: StringName) -> Dictionary:
	# Requires FRIENDLY relation
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
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_ALLIANCE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.ALLIANCE, proposer, target)
		return {accepted = true, reason = "Alliance formed"}
	return {accepted = false, reason = "They decline the alliance"}

func propose_trade(proposer: StringName, target: StringName, give_res: int, give_amt: int, recv_res: int, recv_amt: int, duration: int) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if relation == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "Cannot trade during war"}
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
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRADE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_DEAL, proposer, target)
		return {accepted = true, reason = "Trade deal accepted"}
	return {accepted = false, reason = "They find the terms unfavorable"}

func gift_resources(from: StringName, to: StringName, res_type: int, amount: int) -> void:
	var from_fs: FactionState = GameManager.state.faction_states.get(from)
	var to_fs: FactionState = GameManager.state.faction_states.get(to)
	if from_fs == null or to_fs == null:
		return
	if from_fs.resources.get(res_type, 0) < amount:
		return
	from_fs.resources[res_type] -= amount
	to_fs.resources[res_type] = to_fs.resources.get(res_type, 0) + amount
	var standing_gain := mini(amount / 10, 15)
	modify_standing(from, to, standing_gain)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.GIFT_RESOURCES, from, to)

func offer_shard(from: StringName, to: StringName, shard_id: StringName) -> void:
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null or shard.claimed_by != from:
		return
	var from_fs: FactionState = GameManager.state.faction_states.get(from)
	var to_fs: FactionState = GameManager.state.faction_states.get(to)
	if from_fs == null or to_fs == null:
		return
	# Transfer shard ownership
	from_fs.owned_shards.erase(shard_id)
	to_fs.owned_shards.append(shard_id)
	shard.claimed_by = to
	var standing_gain := shard.power_level * 5
	modify_standing(from, to, standing_gain)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_SHARD, from, to)

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

func _execute_trade(treaty: TreatyInstance) -> void:
	var fs_a: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
	var fs_b: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
	if fs_a == null or fs_b == null:
		return
	var give_res: int = treaty.terms.get("give_resource", 0)
	var give_amt: int = treaty.terms.get("give_amount", 0)
	var recv_res: int = treaty.terms.get("receive_resource", 0)
	var recv_amt: int = treaty.terms.get("receive_amount", 0)
	# faction_a gives, faction_b receives
	var actual_give := mini(give_amt, fs_a.resources.get(give_res, 0))
	fs_a.resources[give_res] = fs_a.resources.get(give_res, 0) - actual_give
	fs_b.resources[give_res] = fs_b.resources.get(give_res, 0) + actual_give
	# faction_b gives, faction_a receives
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
	# Simple fairness: compare raw amounts (could be refined with resource value weights)
	var fairness := 0.0
	if give_amt > 0:
		fairness = float(recv_amt) / float(give_amt)
	else:
		fairness = 2.0 if recv_amt > 0 else 1.0
	return fairness * 40.0 + standing * 0.2 - 10.0

# ── AI Diplomacy Turn ───────────────────────────────────────

func execute_ai_diplomacy(faction_id: StringName) -> void:
	# Only run every 5 turns
	if GameManager.state.current_turn % 5 != 0:
		return

	# Find who we're at war with
	var my_enemies: Array[StringName] = []
	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or other_id == &"rebels":
			continue
		if GameManager.get_relation(faction_id, other_id) == Enums.FactionRelation.WAR:
			my_enemies.append(other_id)

	for other_id in GameManager.state.faction_states:
		if other_id == faction_id or other_id == &"rebels":
			continue
		var other_fs: FactionState = GameManager.state.faction_states[other_id]
		if other_fs.is_defeated:
			continue
		var relation := GameManager.get_relation(faction_id, other_id)

		# Exhausted factions propose peace
		if relation == Enums.FactionRelation.WAR:
			var exhaustion := _calculate_war_exhaustion(faction_id)
			if exhaustion >= 0.5:
				propose_peace(faction_id, other_id)

		# Alliance proposals when sharing an enemy
		elif relation == Enums.FactionRelation.FRIENDLY or relation == Enums.FactionRelation.NEUTRAL:
			var shared_enemies := 0
			for enemy_id in my_enemies:
				if GameManager.get_relation(other_id, enemy_id) == Enums.FactionRelation.WAR:
					shared_enemies += 1
			if shared_enemies > 0 and relation == Enums.FactionRelation.FRIENDLY:
				var standing := get_standing(faction_id, other_id)
				if standing >= 20:
					propose_alliance(faction_id, other_id)
			# Trade proposals when at peace with positive standing
			elif relation != Enums.FactionRelation.WAR:
				var standing := get_standing(faction_id, other_id)
				if standing >= 10:
					var fs: FactionState = GameManager.state.faction_states.get(faction_id)
					if fs:
						# Offer our surplus for what we need most
						var my_gold: int = fs.resources.get(Enums.ResourceType.GOLD, 0)
						var my_iron: int = fs.resources.get(Enums.ResourceType.IRON, 0)
						if my_gold > 200 and my_iron < 50:
							propose_trade(faction_id, other_id, Enums.ResourceType.GOLD, 20, Enums.ResourceType.IRON, 10, 5)
						elif my_iron > 100 and my_gold < 100:
							propose_trade(faction_id, other_id, Enums.ResourceType.IRON, 10, Enums.ResourceType.GOLD, 20, 5)

		# Friendly factions consider alliances
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

func get_treaties_between(faction_a: StringName, faction_b: StringName) -> Array[TreatyInstance]:
	var result: Array[TreatyInstance] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if (treaty.faction_a == faction_a and treaty.faction_b == faction_b) or \
		   (treaty.faction_a == faction_b and treaty.faction_b == faction_a):
			result.append(treaty)
	return result
