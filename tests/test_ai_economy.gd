extends SceneTree
## Balance batch (2026-07): 3 small AI-economy fixes.
## 1. Ivoryscar's home region (qareth) now matches its realm_affinity (VOID)
##    like every other playable faction's home region matches its own --
##    it was the only DIVINE/VOID mismatch, flipping the loyalty Same-Realm
##    bonus into a Cultural-Mismatch penalty for every Ivoryscar city.
## 2. Ivoryscar's AI build-priority table now includes a wood producer
##    (sandstone_pit + its tier-2 petrified_quarry) -- the desert biome has
##    zero native wood income, yet several Ivoryscar buildings carry wood
##    upkeep.
## 3. The AI recruit function now bails when the faction's recurring gold
##    income is already non-positive, instead of recruiting purely on unit
##    count regardless of affordability.
## Run: godot --headless --path . -s res://tests/test_ai_economy.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")
	var gm = root.get_node("/root/GameManager")
	var tm = root.get_node("/root/TurnManager")

	# ── Item 1: qareth realm now matches Ivoryscar's realm_affinity (VOID=1) ──
	var qareth = dm.get_region(&"qareth")
	if qareth == null:
		_check(false, "qareth region data exists")
	else:
		_check(qareth.realm_influence == Enums.Realm.VOID, "qareth realm_influence == VOID (1), got %s" % [qareth.realm_influence])

	var ivoryscar_faction = dm.get_faction(&"ivoryscar")
	if ivoryscar_faction:
		_check(qareth != null and ivoryscar_faction.realm_affinity == qareth.realm_influence, "qareth realm now matches ivoryscar.realm_affinity")

	# ── Item 2: ivoryscar build priorities carry a wood producer ──
	var ivoryscar_priorities: Array = tm.FACTION_BUILD_PRIORITIES.get(&"ivoryscar", [])
	_check(ivoryscar_priorities.has(&"sandstone_pit"), "ivoryscar build priorities contain sandstone_pit, got %s" % [ivoryscar_priorities])
	_check(ivoryscar_priorities.has(&"petrified_quarry"), "ivoryscar build priorities contain petrified_quarry (sandstone_pit's tier-2), got %s" % [ivoryscar_priorities])
	var sp_idx: int = ivoryscar_priorities.find(&"sandstone_pit")
	var pq_idx: int = ivoryscar_priorities.find(&"petrified_quarry")
	var df_idx: int = ivoryscar_priorities.find(&"dust_fields")
	if sp_idx != -1 and pq_idx != -1:
		_check(sp_idx <= 3, "sandstone_pit sits early in the priority list (index <=3), got index %d" % sp_idx)
		_check(pq_idx == sp_idx + 1, "petrified_quarry immediately follows sandstone_pit, got indices %d/%d" % [sp_idx, pq_idx])
	# Regression guard for a discovered priority-walk quirk: the AI's build
	# walk (_execute_ai_city_management) stops at the first priority entry
	# that is currently buildable, whether or not start_building() actually
	# succeeds -- so a wood-costing entry ivoryscar can never afford
	# (dust_fields) must not sit ahead of the gold-only wood producer, or it
	# would permanently block the walk from ever reaching sandstone_pit.
	if sp_idx != -1 and df_idx != -1:
		_check(sp_idx < df_idx, "sandstone_pit (gold-only) sits ahead of dust_fields (needs wood ivoryscar doesn't have) in the priority walk, got indices %d/%d" % [sp_idx, df_idx])

	var sandstone_pit_bd = dm.get_building(&"sandstone_pit")
	_check(sandstone_pit_bd != null and sandstone_pit_bd.faction_id == &"ivoryscar", "sandstone_pit is an ivoryscar building")
	if sandstone_pit_bd:
		_check(int(sandstone_pit_bd.income_bonus.get(Enums.ResourceType.WOOD, -1)) > 0, "sandstone_pit produces wood, got %s" % [sandstone_pit_bd.income_bonus])

	# ── Item 3: AI recruit gate -- gold income <= 0 blocks recruitment ──
	gm.new_game(&"empire", false, 0)
	var fs: FactionState = gm.state.faction_states.get(&"ivoryscar")
	if fs == null or fs.owned_cities.is_empty():
		_check(false, "ivoryscar faction state with owned cities exists after new_game")
	else:
		var city: CityState = gm.state.cities.get(fs.owned_cities[0])
		_check(city != null, "ivoryscar's first owned city resolves")
		if city:
			# Healthy baseline: a freshly-started game should have positive gold income.
			var healthy_income: int = gm.diplomacy_system.get_faction_resource_income(&"ivoryscar", Enums.ResourceType.GOLD)
			_check(healthy_income > 0, "sanity: fresh ivoryscar gold income is positive before we siege it, got %d" % healthy_income)

			# Craft a collapsed-income faction state: siege every owned city so
			# the faction's recurring gold income totals to <= 0 (sieged cities
			# are excluded from the income scan entirely).
			var sieged_ids: Array = []
			for cid in fs.owned_cities:
				var c: CityState = gm.state.cities.get(cid)
				if c and not c.is_under_siege:
					c.is_under_siege = true
					sieged_ids.append(cid)
			# The income-totals cache is keyed by (turn, faction-turn-index,
			# topology-epoch) and does not know about is_under_siege flips on
			# its own -- force a recompute the same way real siege/capture
			# code paths do (they change city ownership/buildings, which also
			# bumps the epoch).
			gm.city_system.invalidate_region_effects_cache()

			var collapsed_income: int = gm.diplomacy_system.get_faction_resource_income(&"ivoryscar", Enums.ResourceType.GOLD)
			_check(collapsed_income <= 0, "sanity: sieging every owned city collapses gold income to <=0, got %d" % collapsed_income)

			var census: Dictionary = tm._compute_ai_recruit_census(&"ivoryscar")
			var queue_before := city.recruit_queue.size()
			tm._ai_recruit_with_composition(city, &"ivoryscar", census)
			_check(city.recruit_queue.size() == queue_before, "AI recruit gate: no recruitment queued while gold income <= 0 (before=%d, after=%d)" % [queue_before, city.recruit_queue.size()])

			# Restore state for any later checks / cleanliness.
			for cid in sieged_ids:
				var c2: CityState = gm.state.cities.get(cid)
				if c2:
					c2.is_under_siege = false
			gm.city_system.invalidate_region_effects_cache()

	# ── Balance Batch 2, Item 1: desertion brake sheds gradually (1-2 units),
	# not the whole army, and triggers on recurring income going negative --
	# not just the gold stock already being negative. ──
	_run_batch2_desertion_brake_test(dm, gm, tm)

	# ── Balance Batch 2, Item 3: AI build-priority walk no longer stops dead
	# at the first priority entry that's merely eligible but unaffordable --
	# it keeps walking to a later, affordable entry the same turn. ──
	_run_batch2_priority_walk_test(dm, gm, tm)

	# ── Quick-fix Item A: a faction pair with an active trade deal must not
	# keep getting re-proposed via the AI-offer-to-player dialog. ──
	_run_trade_rerequest_test(gm)

	if _fails == 0:
		print("AI ECONOMY TEST PASSED")
		quit(0)
	else:
		print("AI ECONOMY TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

## Quick-fix Item A: diplomacy_system.generate_ai_offer_to_player() drives the
## "X sends an envoy" popup (campaign_hud._show_ai_diplomacy_offer). Its NEUTRAL
## candidate branch offered "trade_relations" purely off standing, never
## checking whether the pair already has an active TRADE_DEAL/TRADE_RELATIONS
## treaty -- so a faction the player already trades with kept re-proposing
## trade every cooldown cycle. Neutralizes every other major to ALLIED (a
## relation no candidate branch matches) so the target faction is the only
## possible candidate, proving the assertion isn't a coincidence of priority
## ties with unrelated factions.
func _run_trade_rerequest_test(gm) -> void:
	var eb = root.get_node("/root/EventBus")
	gm.new_game(&"empire", false, 42)
	var player_id: StringName = gm.state.player_faction_id
	var ds = gm.diplomacy_system
	var target: StringName = &"skulloath"
	# Neutralize EVERY other non-NPC faction (mirrors generate_ai_offer_to_player's
	# own iteration exactly, so no faction in the roster -- major or minor -- can
	# sneak in a higher-priority candidate and mask the assertion).
	for fid in gm.state.faction_states:
		if fid == player_id or fid == target or gm.is_npc_faction(fid):
			continue
		gm._set_relation(fid, player_id, Enums.FactionRelation.ALLIED)
	gm._set_relation(target, player_id, Enums.FactionRelation.NEUTRAL)
	# Delta, not an absolute -- some pairs start with historical-grudge standing
	# (e.g. WAR's -30 baseline) baked in by new_game, so push it comfortably
	# past the >=5 trade_relations threshold regardless of that baseline.
	ds.init_standing(target, player_id, 60, "test setup")
	gm.state.current_turn = 10
	ds._ai_offer_cooldown = 0

	var offers: Array = []
	var cb := func(fid, otype, _data): offers.append([fid, otype])
	eb.ai_diplomacy_offer.connect(cb)
	ds.generate_ai_offer_to_player()
	eb.ai_diplomacy_offer.disconnect(cb)
	# Sanity: without an active deal yet, the target IS offered -- proves this
	# test setup would actually catch a regression, not just vacuously pass.
	_check(offers.has([target, &"trade_relations"]), "sanity: with no active deal, target is offered trade_relations, got %s" % [offers])

	var result: Dictionary = ds.propose_trade_relations(target, player_id, true)
	_check(result.get("accepted", false), "sanity: trade_relations treaty was established, got %s" % [result])
	_check(ds._has_active_trade(target, player_id), "sanity: _has_active_trade reports true right after establishing the treaty")

	ds._ai_offer_cooldown = 0
	offers.clear()
	eb.ai_diplomacy_offer.connect(cb)
	ds.generate_ai_offer_to_player()
	eb.ai_diplomacy_offer.disconnect(cb)
	_check(offers.is_empty(), "item A: no new trade proposal to a faction pair with an active deal, got %s" % [offers])

## Crafts an insolvent faction (all cities sieged -> zero gold production,
## but the gold STOCK left comfortably positive) so only the new "recurring
## income < 0" trigger fires, never the old "stock < 0" one, then calls the
## real _deduct_upkeep() pipeline directly and checks the brake sheds at most
## 2 units, never empties the army, and takes the cheapest (lowest summed
## recruit-cost) units first.
func _run_batch2_desertion_brake_test(dm, gm, tm) -> void:
	gm.new_game(&"empire", false, 0)
	var fs: FactionState = gm.state.faction_states.get(&"ivoryscar")
	if fs == null:
		_check(false, "ivoryscar faction state exists (desertion brake test)")
		return

	var field_army: ArmyState = null
	for a: ArmyState in gm.get_faction_armies(&"ivoryscar"):
		if not a.is_garrison and a.elderbeast_id == &"" and a.units.size() >= 4:
			field_army = a
			break
	if field_army == null:
		_check(false, "ivoryscar has a starting field army with >=4 units (desertion brake test precondition)")
		return

	var starting_count: int = field_army.units.size()
	var original_units: Array = field_army.units.duplicate()
	# Per-instance recruit-cost "value" (summed across resource types), the
	# same metric _desert_unpaid_units uses to pick who goes first. Also
	# replicate the real desertion-candidate filter (can_desert && effective
	# gold upkeep > 0 after terrain/research/global-discount) -- a unit whose
	# gold upkeep rounds to 0 (e.g. scarab_swarm: 1 gold * 0.8 discount -> 0)
	# is structurally exempt from the brake entirely regardless of its
	# recruit value, same as garrisons/elderbeasts, so it must not be counted
	# against the "lowest-value-first" ordering below.
	var terrain_mult: float = tm.get_terrain_upkeep_modifier(field_army)
	var r_eff: Dictionary = gm.research_system.get_research_effects(&"ivoryscar")
	var upkeep_red_pct: float = float(r_eff.get("upkeep_reduction_pct", 0)) / 100.0
	var values: Dictionary = {}
	var is_candidate: Dictionary = {}
	for u in original_units:
		var ud: UnitData = dm.get_unit(u.unit_data_id)
		var v := 0
		var gold_cost := 0
		if ud:
			for rt in ud.recruit_cost:
				v += int(ud.recruit_cost[rt])
			gold_cost = int(ud.upkeep_cost.get(Enums.ResourceType.GOLD, 0) * terrain_mult)
			if upkeep_red_pct > 0:
				gold_cost = int(gold_cost * (1.0 - upkeep_red_pct))
			gold_cost = int(gold_cost * 0.80)
		values[u] = v
		is_candidate[u] = gold_cost > 0

	# Siege every owned city: income totals collapse to 0 (sieged cities are
	# excluded from the income scan) while upkeep still gets deducted, so
	# recurring net income goes negative on its own -- independent of the
	# gold stock, which we pin comfortably positive below.
	var sieged_ids: Array = []
	for cid in fs.owned_cities:
		var c: CityState = gm.state.cities.get(cid)
		if c and not c.is_under_siege:
			c.is_under_siege = true
			sieged_ids.append(cid)
	gm.city_system.invalidate_region_effects_cache()
	fs.resources[Enums.ResourceType.GOLD] = 500

	gm.city_system._deduct_upkeep(&"ivoryscar")

	var remaining: int = field_army.units.size()
	var shed_count: int = starting_count - remaining
	_check(shed_count >= 1, "desertion brake triggers on recurring income going negative alone (stock was pinned to 500 beforehand), got shed_count=%d" % shed_count)
	_check(shed_count <= 2, "desertion brake sheds at most 2 units in one tick, got %d (before=%d after=%d)" % [shed_count, starting_count, remaining])
	_check(remaining > 0, "desertion brake never empties the army, got %d remaining of %d" % [remaining, starting_count])

	if shed_count > 0 and remaining > 0:
		# Every shed unit must actually have been a real desertion candidate
		# (never true of e.g. scarab_swarm, whose gold upkeep rounds to 0 --
		# it's structurally exempt, not "spared for being valuable").
		var max_shed_value := -1
		for u in original_units:
			if not field_army.units.has(u):
				_check(is_candidate.get(u, false), "every shed unit was a real desertion candidate (nonzero effective gold upkeep), got a shed unit with is_candidate=false")
				max_shed_value = maxi(max_shed_value, int(values.get(u, 0)))
		# Lowest-value-first is only meaningful among the candidate pool --
		# non-candidates (like scarab_swarm here) are exempt regardless of
		# their recruit value, same as garrisons/elderbeasts.
		var min_kept_candidate_value := 2147483647
		for u in field_army.units:
			if is_candidate.get(u, false):
				min_kept_candidate_value = mini(min_kept_candidate_value, int(values.get(u, 0)))
		if min_kept_candidate_value < 2147483647:
			_check(max_shed_value <= min_kept_candidate_value, "desertion brake sheds the lowest-value CANDIDATE units first, got max shed value %d > min kept candidate value %d" % [max_shed_value, min_kept_candidate_value])

	# Restore state for any later checks / cleanliness.
	for cid in sieged_ids:
		var c2: CityState = gm.state.cities.get(cid)
		if c2:
			c2.is_under_siege = false
	gm.city_system.invalidate_region_effects_cache()

## Finds a real (faction, city, first_priority, second_priority) combo where
## first_priority is a strictly MORE expensive build (on some resource type)
## than second_priority, both currently eligible ("available") in the same
## city and both present in the faction's priority list in that order. Drains
## the faction down to exactly what second_priority needs (after the engine's
## flat -10 wood discount) so first_priority is guaranteed unaffordable while
## second_priority is guaranteed affordable, then runs the real AI build walk
## and checks it queued second_priority instead of getting stuck on
## first_priority.
func _run_batch2_priority_walk_test(dm, gm, tm) -> void:
	var candidate_factions: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"cinderguard", &"moonspear", &"forsaken", &"thunderswarm", &"ivoryscar"]
	var walk_faction: StringName = &""
	var walk_city: CityState = null
	var walk_first: StringName = &""
	var walk_second: StringName = &""

	for map_seed in [0, 1, 2]:
		if walk_city != null:
			break
		for cand_fid in candidate_factions:
			if walk_city != null:
				break
			gm.new_game(cand_fid, false, map_seed)
			var fs: FactionState = gm.state.faction_states.get(cand_fid)
			if fs == null:
				continue
			var priorities: Array = tm.FACTION_BUILD_PRIORITIES.get(cand_fid, [])
			for cid in fs.owned_cities:
				if walk_city != null:
					break
				var c: CityState = gm.state.cities.get(cid)
				if c == null or not c.build_queue.is_empty():
					continue
				# Skip cities whose region has an unclaimed extractor/landmark --
				# those precede the priority walk and would consume the city's
				# one build this turn before we ever reach it (see
				# _execute_ai_city_management).
				if SpecialResourceSystem.special_in_region(c.region_id) != &"":
					continue
				if LandmarkSystem.landmark_in_region(c.region_id) != &"":
					continue
				var avail: Array = gm.city_system.get_available_buildings(c)
				var avail_by_id: Dictionary = {}
				for b in avail:
					avail_by_id[b.id] = b
				var ordered: Array = []
				for pid in priorities:
					if avail_by_id.has(pid):
						ordered.append(pid)
				for i in range(ordered.size() - 1):
					var fid: StringName = ordered[i]
					var sid: StringName = ordered[i + 1]
					var fbd: BuildingData = avail_by_id[fid]
					var sbd: BuildingData = avail_by_id[sid]
					var differentiator := false
					for rt in fbd.build_cost:
						if int(fbd.build_cost[rt]) > int(sbd.build_cost.get(rt, 0)):
							differentiator = true
							break
					if differentiator:
						walk_faction = cand_fid
						walk_city = c
						walk_first = fid
						walk_second = sid
						break

	if walk_city == null:
		_check(false, "found a faction/city/priority-pair combo suitable for the build-walk test")
		return

	var first_bd: BuildingData = dm.get_building(walk_first)
	var second_bd: BuildingData = dm.get_building(walk_second)
	var fs2: FactionState = gm.state.faction_states.get(walk_faction)
	# Fund exactly what `second` needs (after the flat -10 wood discount
	# start_building applies) for every resource type either building cares
	# about -- nothing more. `first` needs strictly more of at least one
	# shared type by construction of the search above, so it fails the
	# afford check while `second` exactly clears it.
	var types: Dictionary = {}
	for rt in first_bd.build_cost:
		types[rt] = true
	for rt in second_bd.build_cost:
		types[rt] = true
	for rt in types:
		var need: int = int(second_bd.build_cost.get(rt, 0))
		if rt == Enums.ResourceType.WOOD:
			need = maxi(0, need - 10)
		fs2.resources[rt] = need

	tm._execute_ai_city_management(walk_faction)

	var queued_ids: Array = []
	for item in walk_city.build_queue:
		queued_ids.append(item.building_id)
	_check(not queued_ids.has(walk_first), "unaffordable first-priority entry (%s) did not get queued, got queue %s" % [walk_first, queued_ids])
	_check(queued_ids.has(walk_second), "walk continued past the unaffordable %s and queued the later affordable %s, got queue %s" % [walk_first, walk_second, queued_ids])
	_check(walk_city.build_queue.size() <= 1, "one-build-per-city-per-turn semantics preserved, got queue size %d" % walk_city.build_queue.size())
