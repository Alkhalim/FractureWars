class_name DiplomacySystem
extends RefCounted

# Gift tiers: Small / Medium / Large
const GIFT_TIERS := [15, 40, 80]

# AI offer cooldown: turns until AI can propose to player again
var _ai_offer_cooldown: int = 0

# ── Standing Management ─────────────────────────────────────

func get_standing(faction_a: StringName, faction_b: StringName) -> int:
	if faction_a == faction_b:
		return 100
	var key := _standing_key(faction_a, faction_b)
	return GameManager.state.diplomacy_state.standing.get(key, 0)

func modify_standing(faction_a: StringName, faction_b: StringName, delta: int, reason: String = "") -> void:
	var key := _standing_key(faction_a, faction_b)
	var current: int = GameManager.state.diplomacy_state.standing.get(key, 0)
	var new_val := clampi(current + delta, -100, 100)
	GameManager.state.diplomacy_state.standing[key] = new_val
	# Mirror: standing is symmetric
	var mirror_key := _standing_key(faction_b, faction_a)
	GameManager.state.diplomacy_state.standing[mirror_key] = new_val
	# Log the change (store under canonical key — sorted alphabetically)
	if reason != "" and delta != 0:
		var log_key := key if str(faction_a) < str(faction_b) else mirror_key
		var log: Array = GameManager.state.diplomacy_state.standing_log.get(log_key, [])
		var turn: int = GameManager.state.current_turn if GameManager.state else 0
		# Merge if same reason already exists for this turn
		var merged := false
		for i in range(log.size() - 1, -1, -1):
			var entry: Dictionary = log[i]
			if entry.get("reason", "") == reason and entry.get("turn", -1) == turn:
				entry["delta"] = entry.get("delta", 0) + delta
				merged = true
				break
		if not merged:
			log.append({reason = reason, delta = delta, turn = turn})
			# Keep only last 20 entries
			if log.size() > 20:
				log = log.slice(log.size() - 20)
		GameManager.state.diplomacy_state.standing_log[log_key] = log
	EventBus.standing_changed.emit(faction_a, faction_b, new_val)
	# Discover factions when the player's standing changes with them
	var player_id := GameManager.state.player_faction_id
	if faction_a == player_id and faction_b != &"" and faction_b != &"independent":
		GameManager.state.encountered_factions[faction_b] = true
	elif faction_b == player_id and faction_a != &"" and faction_a != &"independent":
		GameManager.state.encountered_factions[faction_a] = true

func get_standing_log(faction_a: StringName, faction_b: StringName) -> Array:
	var key := _standing_key(faction_a, faction_b)
	var mirror_key := _standing_key(faction_b, faction_a)
	var log_key := key if str(faction_a) < str(faction_b) else mirror_key
	return GameManager.state.diplomacy_state.standing_log.get(log_key, [])

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
	var army_count := GameManager.get_faction_armies(faction_id).size()
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
	for army: ArmyState in GameManager.get_faction_armies(faction_id):
		for unit in army.units:
				var ud := DataManager.get_unit(unit.unit_data_id)
				if ud:
					# Factor in combat stats, HP, and current health
					var base := ud.attack + ud.get_avg_defense()
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
	for other_id in GameManager.state.faction_states:
		if other_id == actor or other_id == target or GameManager.is_npc_faction(other_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[other_id]
		if fs.is_defeated:
			continue
		var their_relation_to_target := GameManager.get_relation(other_id, target)
		# Factions at war with target dislike the actor for being friendly
		if their_relation_to_target == Enums.FactionRelation.WAR:
			modify_standing(actor, other_id, -magnitude, "Befriended their enemy")
		# Friends/allies of target appreciate the actor's positive gesture
		elif their_relation_to_target == Enums.FactionRelation.ALLIED:
			modify_standing(actor, other_id, maxi(1, magnitude / 2), "Befriended their ally")
		elif their_relation_to_target == Enums.FactionRelation.FRIENDLY:
			modify_standing(actor, other_id, maxi(1, magnitude / 3), "Befriended their friend")

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
			modify_standing(actor, other_id, magnitude, "Fought their enemy")

# ── Player Actions ──────────────────────────────────────────

func declare_war(attacker: StringName, target: StringName) -> void:
	# Check for non-aggression pact — must break it first
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.NON_AGGRESSION_PACT:
			if (t.faction_a == attacker and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == attacker):
				break_treaty(attacker, treaty_id)
				break
	var key_ab := StringName(str(attacker) + ":" + str(target))
	var key_ba := StringName(str(target) + ":" + str(attacker))
	GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.WAR
	GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.WAR
	GameManager.clear_relation_cache()
	_cancel_treaties_between(attacker, target)
	modify_standing(attacker, target, -30, "Declared war")
	_apply_hostile_action_ripple(attacker, target, 5)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DECLARE_WAR, attacker, target)

func propose_peace(proposer: StringName, target: StringName, force_accept: bool = false) -> Dictionary:
	if _get_cooldown(proposer, target, "peace") > 0:
		return {accepted = false, reason = "Peace cooldown active"}
	var score := _evaluate_peace(proposer, target)
	if score > 0 or force_accept:
		var key_ab := StringName(str(proposer) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(proposer))
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
		GameManager.clear_relation_cache()
		modify_standing(proposer, target, 10, "Peace treaty signed")
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

func propose_alliance(proposer: StringName, target: StringName, force_accept: bool = false) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if not force_accept and (relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE):
		return {accepted = false, reason = "Relations too poor"}
	var score := _evaluate_alliance(proposer, target)
	if score > 0 or force_accept:
		var key_ab := StringName(str(proposer) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(proposer))
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.ALLIED
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.ALLIED
		GameManager.clear_relation_cache()
		modify_standing(proposer, target, 15, "Alliance formed")
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

func has_traded_this_turn(from: StringName, to: StringName) -> bool:
	var key := str(from) + ":" + str(to) + ":traded"
	return GameManager.state.diplomacy_state.gifts_this_turn.get(key, false)

func _mark_traded(from: StringName, to: StringName) -> void:
	var key := str(from) + ":" + str(to) + ":traded"
	GameManager.state.diplomacy_state.gifts_this_turn[key] = true

func propose_trade(proposer: StringName, target: StringName, give_res: int, give_amt: int, recv_res: int, recv_amt: int, duration: int, is_counter_offer_acceptance: bool = false) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if relation == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "Cannot trade during war"}
	if give_res == recv_res:
		return {accepted = false, reason = "Cannot trade the same resource for itself"}
	if has_traded_this_turn(proposer, target):
		return {accepted = false, reason = "Already completed a trade this turn"}
	# Limit 1 active trade deal per faction pair
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.TRADE_DEAL:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				return {accepted = false, reason = "Already have an active trade deal with this faction"}
	var score := _evaluate_trade(proposer, target, give_res, give_amt, recv_res, recv_amt)
	if is_counter_offer_acceptance or score > 0:
		modify_standing(proposer, target, 3, "Trade deal accepted")
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
		_apply_friendly_action_ripple(proposer, target, 3)
		_mark_traded(proposer, target)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRADE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_DEAL, proposer, target)
		return {accepted = true, reason = "Trade deal accepted"}
	# Generate a counter-offer if relations aren't abysmal
	var counter := _calculate_counter_offer(proposer, target, give_res, give_amt, recv_res, recv_amt)
	if not counter.is_empty():
		return {accepted = false, reason = "They find the terms unfavorable, but propose a counter-offer.", counter_offer = counter}
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
	modify_standing(from, to, standing_gain, "Gift of resources")
	_mark_gifted(from, to)
	_apply_friendly_action_ripple(from, to, 2)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.GIFT_RESOURCES, from, to)
	return true

func gift_item(from: StringName, to: StringName, item_id: StringName) -> Dictionary:
	var from_fs: FactionState = GameManager.state.faction_states.get(from)
	if from_fs == null:
		return {success = false, standing_change = 0, reaction = "Invalid faction"}
	if has_gifted_this_turn(from, to):
		return {success = false, standing_change = 0, reaction = "Already gifted this turn"}
	var idx := from_fs.item_storage.find(item_id)
	if idx == -1:
		return {success = false, standing_change = 0, reaction = "Item not in storage"}
	var standing_change := get_item_gift_standing(item_id, to)
	from_fs.item_storage.remove_at(idx)
	modify_standing(from, to, standing_change, "Gift of item")
	_mark_gifted(from, to)
	if standing_change > 0:
		_apply_friendly_action_ripple(from, to, 2)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.GIFT_ITEM, from, to)
	var reaction: String
	if standing_change >= 15:
		reaction = "They are delighted by your gift!"
	elif standing_change >= 8:
		reaction = "They appreciate your thoughtful gift."
	elif standing_change >= 1:
		reaction = "They accept your gift with a polite nod."
	elif standing_change == 0:
		reaction = "They seem indifferent to your gift."
	else:
		reaction = "They are insulted by your gift!"
	return {success = true, standing_change = standing_change, reaction = reaction}

func get_item_gift_standing(item_id: StringName, target: StringName) -> int:
	var item: CommanderItem = CommanderSystem.items.get(item_id)
	if item == null:
		return 0
	var base: int
	match item.rarity:
		&"legendary":
			base = 20
		&"rare":
			base = 12
		_:
			base = 5
	var prefs := _get_faction_gift_prefs(target)
	var likes: Array = prefs.get("likes", [])
	var dislikes: Array = prefs.get("dislikes", [])
	var like_bonus := 0
	var dislike_penalty := 0
	for tag in item.gift_tags:
		if tag in likes:
			like_bonus += 4
		if tag in dislikes:
			dislike_penalty += 4
	return clampi(base + like_bonus - dislike_penalty, -5, 30)

func _get_faction_gift_prefs(faction_id: StringName) -> Dictionary:
	# Resolve sub-factions to parent
	var resolved_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var fd: FactionData = DataManager.get_faction(resolved_id)
	if fd == null:
		return {likes = [], dislikes = []}
	return {likes = fd.gift_likes, dislikes = fd.gift_dislikes}

func demand_resources(demander: StringName, target: StringName, res_type: int, amount: int) -> Dictionary:
	var target_fs: FactionState = GameManager.state.faction_states.get(target)
	var demander_fs: FactionState = GameManager.state.faction_states.get(demander)
	if target_fs == null or demander_fs == null:
		return {accepted = false, reason = "Invalid factions"}
	if target_fs.resources.get(res_type, 0) < amount:
		return {accepted = false, reason = "They don't have enough resources"}
	# Evaluate: strength ratio + standing determine compliance
	var ratio := get_strength_ratio(demander, target)
	var standing := get_standing(demander, target)
	# Score: strong demander + low standing = more likely to comply
	var score := (ratio - 1.0) * 30.0 - float(standing) * 0.3 - float(amount) * 0.15
	if score > 0:
		target_fs.resources[res_type] -= amount
		demander_fs.resources[res_type] = demander_fs.resources.get(res_type, 0) + amount
		modify_standing(demander, target, -clampi(amount / 5, 2, 15), "Resource demand")
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DEMAND_RESOURCES, demander, target)
		return {accepted = true, reason = "They comply with your demand"}
	return {accepted = false, reason = "They refuse your demand"}

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
	modify_standing(from, to, standing_gain, "Shard offered")
	_apply_friendly_action_ripple(from, to, 3)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_SHARD, from, to)

func threaten(threatener: StringName, target: StringName, last_offer: Dictionary) -> Dictionary:
	# Threatening always costs standing
	modify_standing(threatener, target, -10, "Threatened")
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
			GameManager.clear_relation_cache()
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
			GameManager.clear_relation_cache()
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

func get_tributary_gold_amount(tributary_id: StringName, tribute_pct: float = 0.15) -> int:
	var gold_income := get_faction_resource_income(tributary_id, Enums.ResourceType.GOLD)
	return maxi(1, int(float(gold_income) * tribute_pct))

func get_trade_relations_share(turns_active: int) -> float:
	# Starts at 5%, +0.5% per turn, caps at 15%
	return minf(5.0 + float(turns_active) * 0.5, 15.0)

func propose_trade_relations(proposer: StringName, target: StringName, force_accept: bool = false) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if not force_accept and (relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE):
		return {accepted = false, reason = "Relations too poor for trade"}
	# Check if already have trade relations
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				return {accepted = false, reason = "Trade relations already established"}
	var score := _evaluate_trade_relations(proposer, target)
	if score > 0 or force_accept:
		var res_a := get_top_produced_resource(proposer)
		var res_b := get_top_produced_resource(target)
		modify_standing(proposer, target, 3, "Trade relations established")
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
		_apply_friendly_action_ripple(proposer, target, 3)
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRADE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRADE_RELATIONS, proposer, target)
		return {accepted = true, reason = "Trade relations established!"}
	return {accepted = false, reason = "They see no benefit in trade relations"}

func _evaluate_trade_relations(proposer: StringName, target: StringName) -> float:
	var standing := get_standing(proposer, target)
	if standing <= -30:
		return -100.0
	# Harder to accept: baseline at standing 0 is -10 (refuse); need standing 20+ to have a chance
	# Penalty for treaties with target's enemies
	var enemy_penalty := _count_enemy_treaties(proposer, target) * 8.0
	return standing * 0.5 - 10.0 - enemy_penalty

func _execute_trade_relations(treaty: TreatyInstance) -> void:
	var fs_a: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
	var fs_b: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
	if fs_a == null or fs_b == null:
		return
	var turns_active: int = treaty.terms.get("turns_active", 0)
	var share_pct := get_trade_relations_share(turns_active) / 100.0
	# Recalculate top resources each turn (adapts when production focus shifts)
	var res_a: int = get_top_produced_resource(treaty.faction_a)
	var res_b: int = get_top_produced_resource(treaty.faction_b)
	treaty.terms["resource_a"] = res_a
	treaty.terms["resource_b"] = res_b
	# Faction A shares their top resource with B
	var income_a := get_faction_resource_income(treaty.faction_a, res_a)
	var transfer_to_b := maxi(1, int(float(income_a) * share_pct))
	# Faction B shares their top resource with A
	var income_b := get_faction_resource_income(treaty.faction_b, res_b)
	var transfer_to_a := maxi(1, int(float(income_b) * share_pct))
	# Check for hostile army interception on trade route
	var theft_pct := _check_trade_interception(treaty, transfer_to_b + transfer_to_a)
	if theft_pct > 0.0:
		transfer_to_b = maxi(1, int(float(transfer_to_b) * (1.0 - theft_pct)))
		transfer_to_a = maxi(1, int(float(transfer_to_a) * (1.0 - theft_pct)))
	fs_b.resources[res_a] = fs_b.resources.get(res_a, 0) + transfer_to_b
	fs_a.resources[res_b] = fs_a.resources.get(res_b, 0) + transfer_to_a
	# Increment turns active
	treaty.terms["turns_active"] = turns_active + 1
	# Standing bonus every 3 turns
	if (turns_active + 1) % 3 == 0:
		modify_standing(treaty.faction_a, treaty.faction_b, 1, "Active trade relations")

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
		# Tributary: transfer gold each turn
		if treaty.treaty_type == Enums.TreatyType.TRIBUTARY:
			var overlord_fs: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
			var tributary_fs: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
			if overlord_fs and tributary_fs:
				var tribute_pct: float = treaty.terms.get("tribute_pct", 0.15)
				var gold_income: int = get_faction_resource_income(treaty.faction_b, Enums.ResourceType.GOLD)
				var tribute: int = maxi(1, int(float(gold_income) * tribute_pct))
				tributary_fs.resources[Enums.ResourceType.GOLD] = tributary_fs.resources.get(Enums.ResourceType.GOLD, 0) - tribute
				overlord_fs.resources[Enums.ResourceType.GOLD] = overlord_fs.resources.get(Enums.ResourceType.GOLD, 0) + tribute
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

func _count_enemy_treaties(proposer: StringName, target: StringName) -> int:
	# Count how many active treaties the proposer has with factions at war with target
	var count := 0
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		var partner: StringName = &""
		if treaty.faction_a == proposer:
			partner = treaty.faction_b
		elif treaty.faction_b == proposer:
			partner = treaty.faction_a
		else:
			continue
		if partner == target:
			continue
		if GameManager.get_relation(target, partner) == Enums.FactionRelation.WAR:
			count += 1
	return count

func _apply_treaty_enemy_malus(faction_id: StringName, treaty: TreatyInstance) -> void:
	# Having a treaty with a faction makes their enemies dislike you each turn
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
		var their_relation := GameManager.get_relation(other_id, partner)
		if their_relation == Enums.FactionRelation.WAR:
			modify_standing(faction_id, other_id, -2, "Treaty with their enemy")
		elif their_relation == Enums.FactionRelation.HOSTILE:
			modify_standing(faction_id, other_id, -1, "Treaty with hostile faction")

func _execute_trade(treaty: TreatyInstance) -> void:
	var fs_a: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
	var fs_b: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
	if fs_a == null or fs_b == null:
		return
	var give_res: int = treaty.terms.get("give_resource", 0)
	var give_amt: int = treaty.terms.get("give_amount", 0)
	var recv_res: int = treaty.terms.get("receive_resource", 0)
	var recv_amt: int = treaty.terms.get("receive_amount", 0)
	# Check for hostile army interception on trade route
	var theft_pct := _check_trade_interception(treaty, give_amt + recv_amt)
	if theft_pct > 0.0:
		give_amt = maxi(1, int(float(give_amt) * (1.0 - theft_pct)))
		recv_amt = maxi(1, int(float(recv_amt) * (1.0 - theft_pct)))
	# Trade deals are guaranteed transfers — both sides always pay the agreed amount
	# (resources can go negative, representing trade debt that is covered by future income)
	fs_a.resources[give_res] = fs_a.resources.get(give_res, 0) - give_amt
	fs_b.resources[give_res] = fs_b.resources.get(give_res, 0) + give_amt
	fs_b.resources[recv_res] = fs_b.resources.get(recv_res, 0) - recv_amt
	fs_a.resources[recv_res] = fs_a.resources.get(recv_res, 0) + recv_amt

func propose_non_aggression(proposer: StringName, target: StringName, force_accept: bool = false) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if not force_accept and relation == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "Cannot propose non-aggression during war"}
	# Check if already exists
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.NON_AGGRESSION_PACT:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				return {accepted = false, reason = "Non-aggression pact already active"}
	var standing := get_standing(proposer, target)
	var score := standing * 0.4 + 10.0  # Easier to accept than alliance
	if score > 0 or force_accept:
		modify_standing(proposer, target, 5, "Non-aggression pact signed")
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.NON_AGGRESSION_PACT
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = 15  # 15 turns duration
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_NON_AGGRESSION, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.NON_AGGRESSION_PACT, proposer, target)
		return {accepted = true, reason = "Non-aggression pact accepted"}
	return {accepted = false, reason = "They see no reason for a non-aggression pact"}

func demand_tributary(demander: StringName, target: StringName) -> Dictionary:
	var ratio := get_strength_ratio(demander, target)
	var standing := get_standing(demander, target)
	# Much harder to accept: requires military dominance
	var score := (ratio - 1.5) * 40.0 + standing * 0.2 - 20.0
	if score > 0:
		modify_standing(demander, target, -5, "Tributary demand accepted")
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.TRIBUTARY
		treaty.faction_a = demander  # overlord
		treaty.faction_b = target    # tributary
		treaty.turns_remaining = -1  # permanent until broken
		treaty.terms = {tribute_pct = 0.15}  # 15% of gold income
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		# Tributary prevents war
		var key_ab := StringName(str(demander) + ":" + str(target))
		var key_ba := StringName(str(target) + ":" + str(demander))
		if GameManager.state.diplomacy.get(key_ab, Enums.FactionRelation.NEUTRAL) == Enums.FactionRelation.WAR:
			GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
			GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
			GameManager.clear_relation_cache()
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DEMAND_TRIBUTARY, demander, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRIBUTARY, demander, target)
		return {accepted = true, reason = "They submit to your tributary demands"}
	return {accepted = false, reason = "They refuse to pay tribute"}

func offer_tributary(offerer: StringName, target: StringName) -> Dictionary:
	# Offering yourself as tributary — always accepted by the other side
	modify_standing(offerer, target, 10, "Offered to become tributary")
	var treaty := TreatyInstance.new()
	treaty.treaty_id = GameManager.state.generate_id()
	treaty.treaty_type = Enums.TreatyType.TRIBUTARY
	treaty.faction_a = target   # overlord
	treaty.faction_b = offerer  # tributary
	treaty.turns_remaining = -1
	treaty.terms = {tribute_pct = 0.15}
	GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
	var key_ab := StringName(str(offerer) + ":" + str(target))
	var key_ba := StringName(str(target) + ":" + str(offerer))
	if GameManager.state.diplomacy.get(key_ab, Enums.FactionRelation.NEUTRAL) == Enums.FactionRelation.WAR:
		GameManager.state.diplomacy[key_ab] = Enums.FactionRelation.NEUTRAL
		GameManager.state.diplomacy[key_ba] = Enums.FactionRelation.NEUTRAL
		GameManager.clear_relation_cache()
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_TRIBUTARY, offerer, target)
	EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.TRIBUTARY, offerer, target)
	return {accepted = true, reason = "They accept your tribute"}

func break_treaty(breaker: StringName, treaty_id: StringName) -> void:
	var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties.get(treaty_id)
	if treaty == null:
		return
	var other: StringName = treaty.faction_b if treaty.faction_a == breaker else treaty.faction_a
	var standing_penalty := -15
	match treaty.treaty_type:
		Enums.TreatyType.PEACE:
			standing_penalty = -25
		Enums.TreatyType.ALLIANCE:
			standing_penalty = -30
		Enums.TreatyType.NON_AGGRESSION_PACT:
			standing_penalty = -20
		Enums.TreatyType.TRIBUTARY:
			standing_penalty = -10
	modify_standing(breaker, other, standing_penalty, "Broke %s" % _treaty_type_name(treaty.treaty_type))
	# Reputation penalty with ALL factions for being dishonorable
	for fid in GameManager.state.faction_states:
		if fid == breaker or fid == other or GameManager.is_npc_faction(fid):
			continue
		var fs: FactionState = GameManager.state.faction_states[fid]
		if fs.is_defeated:
			continue
		modify_standing(breaker, fid, standing_penalty / 3, "Reputation: broke a treaty")
	GameManager.state.diplomacy_state.treaties.erase(treaty_id)
	EventBus.diplomacy_action.emit(Enums.DiplomacyAction.BREAK_TREATY, breaker, other)

func _treaty_type_name(treaty_type: int) -> String:
	match treaty_type:
		Enums.TreatyType.PEACE: return "Peace Treaty"
		Enums.TreatyType.ALLIANCE: return "Alliance"
		Enums.TreatyType.TRADE_DEAL: return "Trade Deal"
		Enums.TreatyType.TRADE_RELATIONS: return "Trade Relations"
		Enums.TreatyType.NON_AGGRESSION_PACT: return "Non-Aggression Pact"
		Enums.TreatyType.TRIBUTARY: return "Tributary Agreement"
	return "Treaty"

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
	# AI demands better deals: baseline required_fairness at standing 0 is 1.3 (proposer must over-offer)
	# Friendly factions slightly more generous — at standing 50: required ~1.0 (still fair)
	# Very friendly (standing 100): required ~0.7
	# Hostile factions demand much more — at standing -40: required ~1.8
	var required_fairness := 1.3 - standing * 0.006
	# Penalty if proposer has treaties with target's enemies
	var enemy_treaty_penalty := _count_enemy_treaties(proposer, target) * 0.10
	required_fairness += enemy_treaty_penalty
	return (fairness - required_fairness) * 50.0

func _calculate_counter_offer(proposer: StringName, target: StringName, give_res: int, give_amt: int, recv_res: int, recv_amt: int) -> Dictionary:
	## Generate a counter-offer the AI would accept.
	## Returns empty dictionary if standing is too low or no reasonable counter exists.
	var standing := get_standing(proposer, target)
	# No counteroffers if standing is very low or the faction hates the proposer
	if standing < -40:
		return {}
	# Calculate what the AI would require: the worse the standing, the more they demand
	# At standing 0 the AI wants ~1.3x value; at standing -30 they want ~1.66x
	var required_fairness := 1.3 - standing * 0.012
	# Add a small buffer so the counter-offer clearly passes evaluation
	var target_fairness := required_fairness + 0.1
	# Strategy: try increasing recv_amt first, then try decreasing give_amt
	# Option A: keep give_amt the same, increase recv_amt (AI gives more)
	var counter_recv_amt := recv_amt
	var counter_give_amt := give_amt
	if give_amt > 0 and target_fairness > 0:
		# Required: give_amt / counter_recv_amt >= target_fairness
		# So: counter_recv_amt <= give_amt / target_fairness
		var desired_recv := int(float(give_amt) / target_fairness)
		if desired_recv < recv_amt:
			# AI wants less from itself — reduce what the proposer receives
			counter_recv_amt = maxi(desired_recv, 5)
		else:
			# AI is fine with the recv amount; maybe wants more from proposer
			var desired_give := int(float(recv_amt) * target_fairness)
			if desired_give > give_amt:
				counter_give_amt = mini(desired_give, give_amt * 3) # Cap at 3x original
			counter_recv_amt = recv_amt
	elif recv_amt > 0:
		# Proposer offers 0 — AI wants something in return
		counter_give_amt = maxi(int(float(recv_amt) * target_fairness), 5)
	# Snap amounts to nearest 5 for cleaner values
	counter_give_amt = maxi(int(round(float(counter_give_amt) / 5.0)) * 5, 5)
	counter_recv_amt = maxi(int(round(float(counter_recv_amt) / 5.0)) * 5, 5)
	# If counter is the same as original, no point returning it
	if counter_give_amt == give_amt and counter_recv_amt == recv_amt:
		return {}
	return {
		give_resource = give_res,
		give_amount = counter_give_amt,
		receive_resource = recv_res,
		receive_amount = counter_recv_amt,
	}

# ── Package Evaluation (dry-run, no side effects) ──────────

func would_accept_proposal(proposer: StringName, target: StringName, proposal_type: String, params: Dictionary = {}) -> Dictionary:
	## Returns {accepted: bool, counter_offer: Dictionary (optional)}
	## Does NOT execute anything — purely evaluative.
	match proposal_type:
		"peace":
			var score := _evaluate_peace(proposer, target)
			return {accepted = score > 0}
		"alliance":
			var relation := GameManager.get_relation(proposer, target)
			if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
				return {accepted = false}
			return {accepted = _evaluate_alliance(proposer, target) > 0}
		"trade":
			var relation := GameManager.get_relation(proposer, target)
			if relation == Enums.FactionRelation.WAR:
				return {accepted = false}
			var g_res: int = params.get("give_res", 0)
			var g_amt: int = params.get("give_amt", 0)
			var r_res: int = params.get("recv_res", 0)
			var r_amt: int = params.get("recv_amt", 0)
			if g_res == r_res:
				return {accepted = false}
			var score := _evaluate_trade(proposer, target, g_res, g_amt, r_res, r_amt)
			if score > 0:
				return {accepted = true}
			var counter := _calculate_counter_offer(proposer, target, g_res, g_amt, r_res, r_amt)
			if not counter.is_empty():
				return {accepted = false, counter_offer = counter}
			return {accepted = false}
		"trade_relations":
			var relation := GameManager.get_relation(proposer, target)
			if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
				return {accepted = false}
			return {accepted = _evaluate_trade_relations(proposer, target) > 0}
		"non_aggression":
			var relation := GameManager.get_relation(proposer, target)
			if relation == Enums.FactionRelation.WAR:
				return {accepted = false}
			var standing := get_standing(proposer, target)
			return {accepted = (standing * 0.4 + 10.0) > 0}
		"demand_tributary":
			var ratio := get_strength_ratio(proposer, target)
			var standing := get_standing(proposer, target)
			return {accepted = ((ratio - 1.5) * 40.0 + standing * 0.2 - 20.0) > 0}
		"demand_resources":
			var ratio := get_strength_ratio(proposer, target)
			var standing := get_standing(proposer, target)
			var amount: int = params.get("amount", 0)
			var score := (ratio - 1.0) * 30.0 - float(standing) * 0.3 - float(amount) * 0.15
			return {accepted = score > 0}
		"free_passage":
			# Offering free passage is beneficial to both — easy to accept
			var relation := GameManager.get_relation(proposer, target)
			if relation == Enums.FactionRelation.WAR:
				return {accepted = false}
			var standing := get_standing(proposer, target)
			if standing < -30:
				return {accepted = false}
			var trade_bonus := 0.0
			for treaty_id in GameManager.state.diplomacy_state.treaties:
				var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
				if t.treaty_type == Enums.TreatyType.TRADE_DEAL or t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
					if (t.faction_a == proposer and t.faction_b == target) or \
					   (t.faction_a == target and t.faction_b == proposer):
						trade_bonus = 15.0
						break
			return {accepted = (standing * 0.5 + trade_bonus + 15.0) > 0}
		"offer_city":
			return {accepted = true}  # AI always accepts city gifts
		"demand_city":
			var ratio := get_strength_ratio(proposer, target)
			if ratio < 1.5:
				return {accepted = false}
			var standing := get_standing(proposer, target)
			var city_id: StringName = params.get("city_id", &"")
			var city_val := get_city_value(city_id)
			return {accepted = ((ratio - 1.5) * 30.0 - city_val * 0.5 + standing * 0.1) > 0}
	return {accepted = false}

# ── AI Diplomacy Turn ───────────────────────────────────────

func execute_ai_diplomacy(faction_id: StringName) -> void:
	# Splinterbrood never initiates diplomacy
	if faction_id == &"splinterbrood":
		return

	# Personality-driven frequency: aggressive factions act more often
	var fd: FactionData = DataManager.get_faction(faction_id)
	var freq: int = 5 if not fd else maxi(3, 5 - int(fd.ai_personality.get("aggression", 0.3) * 4.0))
	# Diplomatically active factions: Sunblessed most active, then Luminarch/Oaseans
	if faction_id == &"sunblessed":
		freq = mini(freq, 2)
	elif faction_id in [&"luminarch", &"oaseans", &"venerated"]:
		freq = mini(freq, 3)
	if GameManager.state.current_turn % freq != 0:
		return

	# Oaseans only do trade — never declare war or propose alliances
	var is_trade_only: bool = faction_id == &"oaseans"
	# Forsaken culture: only declare war with overwhelming advantage
	var is_forsaken_culture: bool = faction_id in [&"forsaken", &"bloodthrone", &"blightcoven"]

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

		elif relation == Enums.FactionRelation.HOSTILE and not is_trade_only:
			# Consider declaring war on hostile factions
			var aggression: float = fd.ai_personality.get("aggression", 0.3) if fd else 0.3
			var turn_factor: float = clampf((GameManager.state.current_turn - 15.0) / 30.0, 0.0, 1.0)
			var standing := get_standing(faction_id, other_id)
			var strength_ratio := get_strength_ratio(faction_id, other_id)
			var war_score: float = aggression * 40.0 + turn_factor * 20.0 + (strength_ratio - 1.0) * 25.0 - float(standing) * 0.5
			# Forsaken culture requires overwhelming advantage (1.5x strength)
			var min_strength: float = 1.5 if is_forsaken_culture else 0.8
			if war_score > 30.0 and strength_ratio >= min_strength:
				if my_enemies.size() < 2:
					declare_war(faction_id, other_id)
					my_enemies.append(other_id)

		elif relation == Enums.FactionRelation.FRIENDLY or relation == Enums.FactionRelation.NEUTRAL:
			if not is_trade_only:
				var shared_enemies := 0
				for enemy_id in my_enemies:
					if GameManager.get_relation(other_id, enemy_id) == Enums.FactionRelation.WAR:
						shared_enemies += 1
				if shared_enemies > 0 and relation == Enums.FactionRelation.FRIENDLY:
					var standing := get_standing(faction_id, other_id)
					if standing >= 20:
						propose_alliance(faction_id, other_id)
						continue
			# Trade logic (available to all including trade-only factions)
			if relation != Enums.FactionRelation.WAR:
				var standing := get_standing(faction_id, other_id)
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

		elif relation == Enums.FactionRelation.FRIENDLY and not is_trade_only:
			var standing := get_standing(faction_id, other_id)
			if standing >= 30:
				propose_alliance(faction_id, other_id)

# ── AI Offer to Player ──────────────────────────────────────

func generate_ai_offer_to_player() -> void:
	# No diplomatic offers in the early game
	if GameManager.state.current_turn < 5:
		return
	if _ai_offer_cooldown > 0:
		_ai_offer_cooldown -= 1
		return
	var player_id := GameManager.state.player_faction_id
	var candidates: Array[Dictionary] = []

	for other_id in GameManager.state.faction_states:
		if other_id == player_id or GameManager.is_npc_faction(other_id):
			continue
		# Splinterbrood never initiates diplomacy
		if other_id == &"splinterbrood":
			continue
		var fs: FactionState = GameManager.state.faction_states[other_id]
		if fs.is_defeated:
			continue
		var relation := GameManager.get_relation(other_id, player_id)
		var standing := get_standing(other_id, player_id)
		var is_trade_only: bool = other_id == &"oaseans"

		if relation == Enums.FactionRelation.WAR:
			if _calculate_war_exhaustion(other_id) >= 0.4:
				candidates.append({faction_id = other_id, offer_type = &"peace", priority = 3})
		elif relation == Enums.FactionRelation.HOSTILE and not is_trade_only:
			if standing >= -20:
				candidates.append({faction_id = other_id, offer_type = &"non_aggression", priority = 1})
		elif relation == Enums.FactionRelation.NEUTRAL:
			if standing >= 5:
				candidates.append({faction_id = other_id, offer_type = &"trade_relations", priority = 2})
		elif relation == Enums.FactionRelation.FRIENDLY and not is_trade_only:
			if standing >= 20:
				candidates.append({faction_id = other_id, offer_type = &"alliance", priority = 2})

	if candidates.is_empty():
		return
	# Pick highest priority, break ties randomly
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority > b.priority)
	var best: Dictionary = candidates[0]
	EventBus.ai_diplomacy_offer.emit(best.faction_id, best.offer_type, best)
	_ai_offer_cooldown = randi_range(4, 8)

func serialize_diplomacy_extra() -> Dictionary:
	return {"_ai_offer_cooldown": _ai_offer_cooldown}

func deserialize_diplomacy_extra(data: Dictionary) -> void:
	_ai_offer_cooldown = data.get("_ai_offer_cooldown", 0)

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

# ── Free Passage ───────────────────────────────────────────

func has_free_passage(faction_a: StringName, faction_b: StringName) -> bool:
	if faction_a == faction_b:
		return true
	# Allied factions always have free passage
	var relation := GameManager.get_relation(faction_a, faction_b)
	if relation == Enums.FactionRelation.ALLIED:
		return true
	# Check for active FREE_PASSAGE treaty
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.FREE_PASSAGE:
			if (t.faction_a == faction_a and t.faction_b == faction_b) or \
			   (t.faction_a == faction_b and t.faction_b == faction_a):
				return true
	return false

func propose_free_passage(proposer: StringName, target: StringName, force_accept: bool = false) -> Dictionary:
	var relation := GameManager.get_relation(proposer, target)
	if not force_accept and relation == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "Cannot propose free passage during war"}
	var standing := get_standing(proposer, target)
	if not force_accept and standing < -10:
		return {accepted = false, reason = "Standing too low for free passage"}
	# Check if already exists
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.FREE_PASSAGE:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				return {accepted = false, reason = "Free passage already active"}
	# AI acceptance: score = standing * 0.3 + (trade_active ? 15 : 0) - 10
	var trade_bonus := 0.0
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.TRADE_DEAL or t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
			if (t.faction_a == proposer and t.faction_b == target) or \
			   (t.faction_a == target and t.faction_b == proposer):
				trade_bonus = 15.0
				break
	var score := standing * 0.3 + trade_bonus - 10.0
	if score > 0 or force_accept:
		modify_standing(proposer, target, 5, "Free passage granted")
		var treaty := TreatyInstance.new()
		treaty.treaty_id = GameManager.state.generate_id()
		treaty.treaty_type = Enums.TreatyType.FREE_PASSAGE
		treaty.faction_a = proposer
		treaty.faction_b = target
		treaty.turns_remaining = 15
		GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.PROPOSE_FREE_PASSAGE, proposer, target)
		EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.FREE_PASSAGE, proposer, target)
		return {accepted = true, reason = "Free passage accepted"}
	return {accepted = false, reason = "They see no benefit in granting free passage"}

# ── City Transfer ──────────────────────────────────────────

func get_city_value(city_id: StringName) -> int:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return 0
	var building_count: int = city.buildings.size()
	return building_count * 5 + city.population / 20

func transfer_city(from_faction: StringName, to_faction: StringName, city_id: StringName) -> bool:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or city.faction_id != from_faction:
		return false
	# Cannot transfer last city
	var from_fs: FactionState = GameManager.state.faction_states.get(from_faction)
	if from_fs == null or from_fs.owned_cities.size() <= 1:
		return false

	var was_capital := city.is_capital

	# Remove from old owner
	from_fs.owned_cities.erase(city_id)

	# Change ownership — friendlier than capture: keep buildings intact
	city.faction_id = to_faction
	city.loyalty = 10
	city.turns_since_capture = 0
	city.is_capital = false
	city.is_under_siege = false
	city.siege_faction = &""
	city.siege_turns = 0

	# Add to new owner
	var to_fs: FactionState = GameManager.state.faction_states.get(to_faction)
	if to_fs and not to_fs.owned_cities.has(city_id):
		to_fs.owned_cities.append(city_id)

	# Update region ownership
	GameManager.change_region_owner(city.region_id, to_faction)

	# Standing boost for city gift
	modify_standing(from_faction, to_faction, 15, "City transferred")

	EventBus.city_captured.emit(city_id, from_faction, to_faction)

	# If old owner lost their capital, promote largest remaining city
	if was_capital and from_fs.owned_cities.size() > 0:
		var best_city: CityState = null
		var best_pop := -1
		for cid in from_fs.owned_cities:
			var c: CityState = GameManager.state.cities.get(cid)
			if c and c.population > best_pop:
				best_pop = c.population
				best_city = c
		if best_city:
			best_city.is_capital = true

	return true

func offer_city(offerer: StringName, target: StringName, city_id: StringName) -> Dictionary:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or city.faction_id != offerer:
		return {accepted = false, reason = "Invalid city"}
	# AI always accepts city gifts
	if transfer_city(offerer, target, city_id):
		EventBus.diplomacy_action.emit(Enums.DiplomacyAction.OFFER_CITY, offerer, target)
		return {accepted = true, reason = "City %s transferred" % city.city_name}
	return {accepted = false, reason = "Cannot transfer this city"}

func demand_city(demander: StringName, target: StringName, city_id: StringName) -> Dictionary:
	var ratio := get_strength_ratio(demander, target)
	if ratio < 1.5:
		return {accepted = false, reason = "Insufficient military dominance"}
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or city.faction_id != target:
		return {accepted = false, reason = "Invalid city"}
	var standing := get_standing(demander, target)
	var city_val := get_city_value(city_id)
	var score := (ratio - 1.5) * 30.0 - city_val * 0.5 + standing * 0.1
	if score > 0:
		if transfer_city(target, demander, city_id):
			# Demanding hurts standing (transfer_city gave +15 from transferor, offset it)
			modify_standing(demander, target, -20, "City demand accepted")
			EventBus.diplomacy_action.emit(Enums.DiplomacyAction.DEMAND_CITY, demander, target)
			return {accepted = true, reason = "They cede %s" % city.city_name}
	return {accepted = false, reason = "They refuse to surrender %s" % city.city_name}

# ── Trade Route Interception ──────────────────────────────────

func _check_trade_interception(treaty: TreatyInstance, total_value: int) -> float:
	## Checks if hostile armies block a trade route. Returns theft fraction (0.0 or 0.25).
	## Intercepting faction gains gold equal to 25% of total trade value.
	var routes := get_active_trade_routes()
	var route_info: Dictionary = {}
	for r in routes:
		if r.treaty_id == treaty.treaty_id:
			route_info = r
			break
	if route_info.is_empty():
		return 0.0
	var hex_path := get_trade_route_hex_path(route_info.city_a_hex, route_info.city_b_hex)
	var interceptors := get_intercepting_armies(hex_path, treaty.faction_a, treaty.faction_b)
	if interceptors.is_empty():
		return 0.0
	# First interceptor steals 25% as gold
	var stolen_gold := maxi(1, int(float(total_value) * 0.25))
	var interceptor_faction: StringName = interceptors[0].faction_id
	var fs_int: FactionState = GameManager.state.faction_states.get(interceptor_faction)
	if fs_int:
		fs_int.resources[0] = fs_int.resources.get(0, 0) + stolen_gold # 0 = GOLD
	EventBus.trade_intercepted.emit(interceptor_faction, treaty.treaty_id, stolen_gold)
	return 0.25

# ── Trade Route Visualization ─────────────────────────────────

func get_active_trade_routes() -> Array[Dictionary]:
	## Returns active trade routes with closest city pairs for visualization.
	var routes: Array[Dictionary] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_DEAL and treaty.treaty_type != Enums.TreatyType.TRADE_RELATIONS:
			continue
		# Find closest city pair between the two factions
		var best_dist := 999999
		var best_a := Vector2i(-1, -1)
		var best_b := Vector2i(-1, -1)
		for city_id_a in GameManager.state.cities:
			var ca: CityState = GameManager.state.cities[city_id_a]
			if ca.faction_id != treaty.faction_a:
				continue
			for city_id_b in GameManager.state.cities:
				var cb: CityState = GameManager.state.cities[city_id_b]
				if cb.faction_id != treaty.faction_b:
					continue
				var dist := HexHelper.hex_distance(ca.hex_pos, cb.hex_pos)
				if dist < best_dist:
					best_dist = dist
					best_a = ca.hex_pos
					best_b = cb.hex_pos
		if best_a != Vector2i(-1, -1) and best_b != Vector2i(-1, -1):
			routes.append({
				faction_a = treaty.faction_a,
				faction_b = treaty.faction_b,
				city_a_hex = best_a,
				city_b_hex = best_b,
				treaty_id = treaty.treaty_id,
			})
	return routes

static func get_trade_route_hex_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	## Hex line-drawing via cube coordinate lerp.
	var path: Array[Vector2i] = []
	var ac := HexHelper.offset_to_cube(from.x, from.y)
	var bc := HexHelper.offset_to_cube(to.x, to.y)
	var dist := HexHelper.hex_distance(from, to)
	if dist == 0:
		path.append(from)
		return path
	for i in dist + 1:
		var t := float(i) / float(dist)
		# Cube lerp with 1e-6 nudge to avoid ambiguous rounding at midpoints
		var cx := float(ac.x) + (float(bc.x) - float(ac.x)) * t + 1e-6
		var cy := float(ac.y) + (float(bc.y) - float(ac.y)) * t + 1e-6
		var cz := float(ac.z) + (float(bc.z) - float(ac.z)) * t - 2e-6
		# Cube round
		var rx := roundi(cx)
		var ry := roundi(cy)
		var rz := roundi(cz)
		var dx := absf(float(rx) - cx)
		var dy := absf(float(ry) - cy)
		var dz := absf(float(rz) - cz)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		path.append(HexHelper.cube_to_offset(Vector3i(rx, ry, rz)))
	return path

func get_intercepting_armies(route_path: Array[Vector2i], faction_a: StringName, faction_b: StringName) -> Array[Dictionary]:
	## Returns hostile armies standing on trade route tiles.
	var interceptors: Array[Dictionary] = []
	var route_set: Dictionary = {}
	for coord in route_path:
		route_set[coord] = true
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.is_garrison:
			continue
		if not route_set.has(army.hex_pos):
			continue
		# Must be at war with at least one trade partner
		var rel_a := GameManager.get_relation(army.faction_id, faction_a)
		var rel_b := GameManager.get_relation(army.faction_id, faction_b)
		if rel_a == Enums.FactionRelation.WAR or rel_b == Enums.FactionRelation.WAR:
			interceptors.append({army_id = army.army_id, faction_id = army.faction_id, hex_pos = army.hex_pos})
	return interceptors
