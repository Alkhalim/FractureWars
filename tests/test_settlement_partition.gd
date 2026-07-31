extends SceneTree
## Task 1 of the Settlement Building Partition plan: settlements build only
## settlement-grade buildings (waystation, resource_camp, frontier_watchpost,
## frontier_shrine) plus region-gated extractor/landmark buildings; cities
## keep the full roster minus that settlement-grade set. Closes the
## one-directional gate that used to live only in get_available_buildings
## (city_system.gd :1690) -- start_building's commit path never enforced it,
## so a settlement could be built into full city status straight through the
## API. Both call sites now share CitySystem.is_building_allowed_for().
## Run: godot --headless --path . -s res://tests/test_settlement_partition.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm = root.get_node("/root/GameManager")
	var tm = root.get_node("/root/TurnManager")
	gm.new_game(&"empire", false, 0)
	var cs = gm.city_system

	var capital: CityState = null
	var efs: FactionState = gm.state.faction_states.get(&"empire")
	if efs:
		for cid in efs.owned_cities:
			var c: CityState = gm.state.cities.get(cid)
			if c and c.is_capital:
				capital = c
				break
	if capital == null:
		_check(false, "found the empire capital for the partition test")
		_finish()
		return

	# ── Partition: a settlement's available list contains ONLY allowed classes ──
	# (waystation, resource_camp, frontier_watchpost, frontier_shrine,
	# region-gated extractor/landmark buildings, OR one of the faction's
	# Task 1b curated settlement_allowed chain buildings.)
	var saved_is_settlement := capital.is_settlement
	capital.is_settlement = true
	# Empire's tagged military tier-1 (cohort_barracks) is research-gated
	# (requires_research imperial_drill, checked earlier in
	# get_available_buildings than the partition) -- grant it so this test
	# actually exercises the curated-chain branch, not just the always-free
	# science tier-1 (village_gathering_place, which carries no gate).
	if not efs.completed_research.has(&"imperial_drill"):
		efs.completed_research.append(&"imperial_drill")
	# The starting capital already owns cohort_barracks (a new-game default
	# building, unrelated to this task) -- "already owned" buildings are
	# never re-offered regardless of settlement_allowed, so pull it
	# temporarily to prove the flag itself grants availability on a
	# settlement that doesn't have it yet, same as any real frontier
	# settlement would start out.
	var had_cohort_barracks := capital.buildings.has(&"cohort_barracks")
	if had_cohort_barracks:
		capital.buildings.erase(&"cohort_barracks")
	var settlement_avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	_check(not settlement_avail.is_empty(), "settlement offers at least one building")
	for bd in settlement_avail:
		_check(bd.settlement_only or bd.requires_region_resource != &"" or bd.requires_region_landmark != &"" or bd.settlement_allowed, "settlement offered only settlement-grade/extractor/landmark/curated-chain: %s" % bd.id)
	var settlement_avail_ids: Array = []
	for bd in settlement_avail:
		settlement_avail_ids.append(bd.id)
	_check(settlement_avail_ids.has(&"cohort_barracks"), "settlement offers empire's tagged military tier-1 (cohort_barracks), got %s" % [settlement_avail_ids])
	_check(settlement_avail_ids.has(&"village_gathering_place"), "settlement offers empire's tagged science/cultural tier-1 (village_gathering_place), got %s" % [settlement_avail_ids])
	if had_cohort_barracks:
		capital.buildings.append(&"cohort_barracks")

	# ── COMMIT PATH enforced (the latent hole): start_building a city
	# building (market_square) on the settlement must be REFUSED even though
	# resources suffice -- assert refusal AND that city.buildings/build_queue
	# did not gain it. ──
	var fs: FactionState = gm.state.faction_states[&"empire"]
	var saved_gold: int = fs.resources.get(Enums.ResourceType.GOLD, 0)
	var saved_wood: int = fs.resources.get(Enums.ResourceType.WOOD, 0)
	fs.resources[Enums.ResourceType.GOLD] = 100000
	fs.resources[Enums.ResourceType.WOOD] = 100000
	var had_market_before := capital.buildings.has(&"market_square")
	var queue_len_before := capital.build_queue.size()
	var started: bool = cs.start_building(capital.city_id, &"market_square")
	_check(not started, "start_building refuses a city building (market_square) on a settlement")
	_check(capital.buildings.has(&"market_square") == had_market_before, "settlement's buildings unchanged after refused start_building")
	_check(capital.build_queue.size() == queue_len_before, "settlement's build_queue unchanged after refused start_building")

	# A settlement-grade building, by contrast, must still be accepted on the
	# same settlement (the gate is a partition, not a blanket freeze).
	var settlement_started: bool = cs.start_building(capital.city_id, &"waystation")
	_check(settlement_started, "start_building accepts a settlement-grade building (waystation) on a settlement")
	if settlement_started:
		var found_in_queue := false
		var remove_idx := -1
		for i in capital.build_queue.size():
			if capital.build_queue[i].building_id == &"waystation":
				found_in_queue = true
				remove_idx = i
		_check(found_in_queue, "waystation actually entered the settlement's build_queue")
		if remove_idx >= 0:
			capital.build_queue.remove_at(remove_idx)

	# ── Old-save compat: a settlement with a pre-existing city building in
	# city.buildings keeps it and its income still counts (calculate_city_income
	# unchanged before/after adding the gate -- it iterates city.buildings
	# regardless of availability). ──
	var income_before: Dictionary = cs.calculate_city_income(capital)
	var added_market_for_compat := false
	if not capital.buildings.has(&"market_square"):
		capital.buildings.append(&"market_square")
		added_market_for_compat = true
	var income_after: Dictionary = cs.calculate_city_income(capital)
	_check(int(income_after.get(Enums.ResourceType.GOLD, 0)) > int(income_before.get(Enums.ResourceType.GOLD, 0)), "old-save city building already in a settlement's buildings list still contributes income (%s -> %s)" % [income_before, income_after])
	if added_market_for_compat:
		capital.buildings.erase(&"market_square")

	fs.resources[Enums.ResourceType.GOLD] = saved_gold
	fs.resources[Enums.ResourceType.WOOD] = saved_wood
	capital.is_settlement = saved_is_settlement

	# ── City never sees settlement buildings (pin the existing direction too) ──
	var city_avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	_check(not city_avail.is_empty(), "capital offers at least one building")
	for bd in city_avail:
		_check(not bd.settlement_only, "city not offered settlement building: %s" % bd.id)

	# ── Task 1b: universal tier-2 settlement buildings exist with exact
	# post-cost-sweep values, and are offered to a level-2+ settlement that
	# already owns the tier-1 -- never to a city. ──
	_run_settlement_tier2_tests(gm)

	# ── Task 1b: every major faction has 3-4 curated settlement_allowed
	# chains (both tiers tagged), and none of them is category defensive. ──
	_run_chain_tagging_invariant()

	# ── AI: a settlement with a free slot + resources builds one of the 4
	# settlement-grade buildings, not an arbitrary fallback. ──
	_run_ai_settlement_priority(gm, tm)

	# ── Fix round 1: Sunblessed mobile camps are a distinct city-class
	# mechanic, not a founded frontier settlement -- they keep full faction
	# building access despite is_settlement == true. ──
	_run_sunblessed_camp_tests(gm)

	# ── Fix round 1 (reviewer minor): a settlement holding a legacy city
	# building does NOT get offered that building's tier-2 upgrade --
	# upgrading IS building, and the partition applies to all NEW
	# construction, not just base buildings. ──
	_run_legacy_upgrade_not_offered_test(gm)

	_finish()

func _run_ai_settlement_priority(gm, tm) -> void:
	var dm = root.get_node("/root/DataManager")
	var faction_id: StringName = &"skulloath"
	var fs: FactionState = gm.state.faction_states.get(faction_id)
	if fs == null or fs.owned_cities.is_empty():
		_check(false, "found an AI faction with an owned city to anchor the settlement AI test")
		return
	var parent_city: CityState = gm.state.cities.get(fs.owned_cities[0])
	if parent_city == null:
		_check(false, "found a valid parent city for the settlement AI test")
		return

	# Synthetic settlement anchored on the parent capital's own hex (a real,
	# already-valid map tile) but in a region_id with no Special deposit and
	# no Landmark, so the AI's extractor/landmark claim steps (which must
	# stay first and unchanged) have nothing to claim here -- isolating the
	# settlement-priority-list behavior this task actually adds.
	var settlement := CityState.new()
	settlement.city_id = &"__test_ai_settlement__"
	settlement.faction_id = faction_id
	settlement.hex_pos = parent_city.hex_pos
	settlement.region_id = &"__test_settlement_region_no_deposit__"
	settlement.level = 1
	settlement.population = 100
	settlement.is_settlement = true
	settlement.is_capital = false
	gm.state.cities[settlement.city_id] = settlement
	fs.owned_cities.append(settlement.city_id)

	var saved_resources: Dictionary = fs.resources.duplicate()
	fs.resources[Enums.ResourceType.GOLD] = 100000
	fs.resources[Enums.ResourceType.WOOD] = 100000
	fs.resources[Enums.ResourceType.FOOD] = 100000
	fs.resources[Enums.ResourceType.IRON] = 100000

	# Task 1b: raiders_den (skulloath's tagged military tier-1) is
	# research-gated (bone_rituals) -- grant it so the settlement actually has
	# it available, exercising the NEW curated-chain-first priority order
	# instead of silently falling back to the pre-existing universal 4.
	var had_research := fs.completed_research.has(&"bone_rituals")
	if not had_research:
		fs.completed_research.append(&"bone_rituals")

	tm._execute_ai_city_management(faction_id)

	var built_id: StringName = &""
	for item in settlement.build_queue:
		var bd: BuildingData = dm.get_building(item.building_id)
		if bd and (bd.settlement_only or bd.settlement_allowed):
			built_id = item.building_id
			break
	if built_id == &"":
		for bid in settlement.buildings:
			var bd2: BuildingData = dm.get_building(bid)
			if bd2 and (bd2.settlement_only or bd2.settlement_allowed):
				built_id = bid
				break
	_check(built_id != &"", "AI-managed settlement builds a settlement-grade or curated-chain building (buildings=%s queue=%s)" % [settlement.buildings, settlement.build_queue])
	# Task 1b: with its tagged tier-1 available and unlimited resources, the
	# new settlement priority walk puts raiders_den FIRST -- pin the actual
	# pick, not just its validity, so a priority-order regression trips this.
	_check(built_id == &"raiders_den", "settlement AI prioritizes skulloath's tagged military tier-1 (raiders_den) over the universal 4, got %s" % built_id)
	if built_id != &"":
		print("NOTE: settlement AI picked %s" % built_id)

	if not had_research:
		fs.completed_research.erase(&"bone_rituals")
	gm.state.cities.erase(settlement.city_id)
	fs.owned_cities.erase(settlement.city_id)
	fs.resources = saved_resources

## Fix round 1: Sunblessed mobile camps set is_settlement = true (see
## setup_sunblessed_camp) but are NOT founded frontier settlements -- they're
## a distinct city-class mechanic and must keep full faction-roster access
## (city.is_mobile_camp is the permanent camp-identity marker that carves
## them out of the settlement branch in is_building_allowed_for). Exercises
## the REAL setup_sunblessed_camp path end-to-end, not a synthetic stand-in,
## since that's exactly the function the reviewer flagged.
func _run_sunblessed_camp_tests(gm) -> void:
	var cs = gm.city_system
	var sfs: FactionState = gm.state.faction_states.get(&"sunblessed")
	if sfs == null:
		_check(false, "found the sunblessed faction state for the camp test")
		return
	# Reuse a real, already-known-valid map tile (any existing city's hex_pos
	# guarantees a non-water tile with buildable neighbors).
	var anchor_hex := Vector2i(0, 0)
	for cid in gm.state.cities:
		var c: CityState = gm.state.cities[cid]
		anchor_hex = c.hex_pos
		break

	var army := ArmyState.new()
	army.army_id = &"__test_camp_army__"
	army.faction_id = &"sunblessed"
	army.hex_pos = anchor_hex
	army.movement_remaining = 2.0 # units.is_empty() -> get_max_movement() == 2.0; > half of that
	var cmd := CommanderState.new()
	cmd.commander_id = &"__test_camp_commander__"
	cmd.name = "Test Commander"
	cmd.faction_id = &"sunblessed"
	army.commander = cmd
	gm.state.armies[army.army_id] = army

	var camp_city_id: StringName = gm.setup_sunblessed_camp(army.army_id)
	_check(camp_city_id != &"", "setup_sunblessed_camp creates a camp city")
	if camp_city_id == &"":
		gm.state.armies.erase(army.army_id)
		return
	var camp: CityState = gm.state.cities.get(camp_city_id)
	if camp == null:
		_check(false, "camp city registered in GameManager.state.cities")
		gm.state.armies.erase(army.army_id)
		return

	_check(camp.is_settlement, "camp city has is_settlement == true (why the partition would apply at all)")
	_check(camp.is_mobile_camp, "camp city has is_mobile_camp == true (permanent camp identity, set by setup_sunblessed_camp)")

	var saved_resources: Dictionary = sfs.resources.duplicate()
	sfs.resources[Enums.ResourceType.GOLD] = 100000
	sfs.resources[Enums.ResourceType.WOOD] = 100000

	# 1. Camp's available list includes a real faction city building, and
	# start_building of it succeeds -- RED before the fix round (the camp
	# was wrongly confined to the 4 settlement-grade buildings), GREEN after.
	var camp_avail: Array[BuildingData] = cs.get_available_buildings(camp, true)
	var found_city_building := false
	for bd in camp_avail:
		if bd.id == &"pilgrim_gardens":
			found_city_building = true
			break
	_check(found_city_building, "sunblessed camp's available list includes a faction city building (pilgrim_gardens)")
	var camp_started: bool = cs.start_building(camp_city_id, &"pilgrim_gardens")
	_check(camp_started, "start_building accepts a faction city building (pilgrim_gardens) on a sunblessed camp")
	if camp_started:
		var found_in_queue := false
		for item in camp.build_queue:
			if item.building_id == &"pilgrim_gardens":
				found_in_queue = true
		_check(found_in_queue, "pilgrim_gardens actually entered the camp's build_queue")

	# 2. Design call: camps are city-class, so settlement_only stays blocked
	# for them exactly like any other non-settlement city.
	for bd in camp_avail:
		_check(not bd.settlement_only, "camp not offered a settlement_only building: %s" % bd.id)
	for settlement_only_id in [&"waystation", &"resource_camp", &"frontier_watchpost", &"frontier_shrine"]:
		var blocked: bool = not cs.start_building(camp_city_id, settlement_only_id)
		_check(blocked, "start_building refuses settlement_only building %s on a sunblessed camp" % settlement_only_id)

	sfs.resources = saved_resources
	gm.state.cities.erase(camp_city_id)
	sfs.owned_cities.erase(camp_city_id)
	gm.state.armies.erase(army.army_id)

## Fix round 1 (reviewer minor): a settlement holding a legacy city building
## (as if from an old save, injected directly into city.buildings bypassing
## the gate) must NOT be offered that building's tier-2 upgrade -- upgrading
## IS building, and the partition governs all NEW construction, upgrades
## included, not just fresh base buildings.
func _run_legacy_upgrade_not_offered_test(gm) -> void:
	var cs = gm.city_system
	var efs: FactionState = gm.state.faction_states.get(&"empire")
	if efs == null or efs.owned_cities.is_empty():
		_check(false, "found the empire capital for the legacy-upgrade test")
		return
	var capital: CityState = null
	for cid in efs.owned_cities:
		var c: CityState = gm.state.cities.get(cid)
		if c and c.is_capital:
			capital = c
			break
	if capital == null:
		_check(false, "found the empire capital for the legacy-upgrade test")
		return

	var saved_is_settlement := capital.is_settlement
	var saved_level := capital.level
	var had_grain_fields := capital.buildings.has(&"grain_fields")
	capital.is_settlement = true
	# imperial_granary requires_capital_level 2 -- bump so the partition is
	# the ONLY reason it's excluded, isolating it from the unrelated level gate.
	capital.level = maxi(capital.level, 2)
	if not had_grain_fields:
		capital.buildings.append(&"grain_fields")

	var avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	var offered_upgrade := false
	for bd in avail:
		if bd.id == &"imperial_granary":
			offered_upgrade = true
	_check(not offered_upgrade, "settlement holding a legacy grain_fields is NOT offered its tier-2 upgrade (imperial_granary) -- upgrading is building")

	if not had_grain_fields:
		capital.buildings.erase(&"grain_fields")
	capital.level = saved_level
	capital.is_settlement = saved_is_settlement

## Task 1b: the 4 universal settlement buildings each get a tier-2 upgrade
## (waystation_2/resource_camp_2/frontier_watchpost_2/frontier_shrine_2),
## exact post-cost-sweep values per the plan table, offered to a level-2+
## settlement that already owns the tier-1 (upgrades_from) -- never to a city.
func _run_settlement_tier2_tests(gm) -> void:
	var dm = root.get_node("/root/DataManager")
	var cs = gm.city_system

	var expected := {
		&"waystation_2": {"upg": &"waystation", "cost": {0: 175}, "income": {0: 14, 3: 8}},
		&"resource_camp_2": {"upg": &"resource_camp", "cost": {0: 68, 3: 149}, "income": {5: 16, 1: 8}},
		&"frontier_watchpost_2": {"upg": &"frontier_watchpost", "cost": {5: 155}, "defense": 8, "garrison": 0.2},
		&"frontier_shrine_2": {"upg": &"frontier_shrine", "cost": {0: 155, 5: 52}, "loyalty": 2},
	}
	for id in expected.keys():
		var b: BuildingData = dm.get_building(id)
		if b == null:
			_check(false, "%s building data exists" % id)
			continue
		var exp: Dictionary = expected[id]
		_check(b.settlement_only, "%s settlement_only == true" % id)
		_check(b.upgrades_from == exp.upg, "%s upgrades_from == %s, got %s" % [id, exp.upg, b.upgrades_from])
		_check(b.required_capital_level == 2, "%s required_capital_level == 2, got %s" % [id, b.required_capital_level])
		_check(b.build_time == 3, "%s build_time == 3, got %s" % [id, b.build_time])
		_check(b.upkeep_cost.is_empty(), "%s has no upkeep, got %s" % [id, b.upkeep_cost])
		for k in (exp.cost as Dictionary).keys():
			_check(int(b.build_cost.get(k, -1)) == int((exp.cost as Dictionary)[k]), "%s build_cost[%s] == %s, got %s" % [id, k, (exp.cost as Dictionary)[k], b.build_cost.get(k, -1)])
		if exp.has("income"):
			for k in (exp.income as Dictionary).keys():
				_check(int(b.income_bonus.get(k, -1)) == int((exp.income as Dictionary)[k]), "%s income_bonus[%s] == %s, got %s" % [id, k, (exp.income as Dictionary)[k], b.income_bonus.get(k, -1)])
		if exp.has("defense"):
			_check(b.defense_bonus == int(exp.defense), "%s defense_bonus == %s, got %s" % [id, exp.defense, b.defense_bonus])
		if exp.has("garrison"):
			_check(absf(float(b.special_effects.get("garrison_strength_bonus", -1.0)) - float(exp.garrison)) < 0.001, "%s garrison_strength_bonus == %s, got %s" % [id, exp.garrison, b.special_effects.get("garrison_strength_bonus")])
		if exp.has("loyalty"):
			_check(int(b.special_effects.get("region_loyalty_bonus", -1)) == int(exp.loyalty), "%s region_loyalty_bonus == %s, got %s" % [id, exp.loyalty, b.special_effects.get("region_loyalty_bonus")])

	# ── Offering: a level-2 settlement owning waystation is offered waystation_2 ──
	var efs: FactionState = gm.state.faction_states.get(&"empire")
	if efs == null or efs.owned_cities.is_empty():
		_check(false, "found the empire capital for the tier-2 offering test")
		return
	var capital: CityState = null
	for cid in efs.owned_cities:
		var c: CityState = gm.state.cities.get(cid)
		if c and c.is_capital:
			capital = c
			break
	if capital == null:
		_check(false, "found the empire capital for the tier-2 offering test")
		return

	var saved_is_settlement := capital.is_settlement
	var saved_level := capital.level
	var had_waystation := capital.buildings.has(&"waystation")
	var had_tile := capital.building_tiles.has(&"waystation")
	var saved_tile: Vector2i = capital.building_tiles.get(&"waystation", Vector2i.ZERO)

	capital.is_settlement = true
	capital.level = maxi(capital.level, 2)
	if not had_waystation:
		capital.buildings.append(&"waystation")
	capital.building_tiles[&"waystation"] = capital.hex_pos

	var avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	var offered_tier2 := false
	for bd in avail:
		if bd.id == &"waystation_2":
			offered_tier2 = true
	_check(offered_tier2, "level-2 settlement owning waystation is offered waystation_2, got %s" % [avail.map(func(b): return b.id)])

	# Cities never offered the new tier-2s either (settlement_only, same
	# direction pin as the base 4).
	capital.is_settlement = false
	var city_avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	for bd in city_avail:
		_check(bd.id != &"waystation_2" and bd.id != &"resource_camp_2" and bd.id != &"frontier_watchpost_2" and bd.id != &"frontier_shrine_2", "city not offered tier-2 settlement building: %s" % bd.id)

	if not had_waystation:
		capital.buildings.erase(&"waystation")
	if had_tile:
		capital.building_tiles[&"waystation"] = saved_tile
	else:
		capital.building_tiles.erase(&"waystation")
	capital.level = saved_level
	capital.is_settlement = saved_is_settlement

## Task 1b: every one of the 11 major factions has 3-4 curated
## settlement_allowed chains (a military tier-1+tier-2 and a science/cultural
## tier-1+tier-2 at minimum, plus a captive and/or flavor chain), and NONE of
## those chains is a defensive/wall chain -- the live invariant the plan
## calls for, computed from the actual tagged data (not a fixed list) so any
## future drift trips it. A "chain" = one connected group of tagged buildings
## for that faction, grouped by their ultimate (possibly-untagged)
## upgrades_from root ancestor.
func _run_chain_tagging_invariant() -> void:
	var dm = root.get_node("/root/DataManager")
	var majors: Array[StringName] = [
		&"empire", &"skulloath", &"gladehost", &"moonspear", &"sunblessed",
		&"shardhorde", &"thunderswarm", &"cinderguard", &"forsaken",
		&"ivoryscar", &"tainted_jade",
	]
	for faction_id in majors:
		var roots: Dictionary = {} # ultimate root id -> true
		var tagged_count := 0
		for id in dm.buildings.keys():
			var b: BuildingData = dm.buildings[id]
			if b.faction_id != faction_id or not b.settlement_allowed:
				continue
			tagged_count += 1
			var cur: BuildingData = b
			var cur_id: StringName = id
			var guard := 0
			while cur.upgrades_from != &"" and guard < 10:
				cur_id = cur.upgrades_from
				var anc: BuildingData = dm.get_building(cur_id)
				if anc == null:
					break
				cur = anc
				guard += 1
			roots[cur_id] = true
		var n := roots.size()
		_check(n >= 3 and n <= 4, "%s has 3-4 curated settlement chains, got %d (%s)" % [faction_id, n, roots.keys()])
		_check(tagged_count >= n * 2, "%s tagged both tiers of each chain (>= 2 buildings per chain), got %d tagged across %d chains" % [faction_id, tagged_count, n])
		for root_id in roots.keys():
			var root_b: BuildingData = dm.get_building(root_id)
			if root_b:
				_check(root_b.category != &"defensive", "%s curated chain root %s is not category defensive, got %s" % [faction_id, root_id, root_b.category])

func _finish() -> void:
	if _fails == 0:
		print("SETTLEMENT PARTITION TEST PASSED")
		quit(0)
	else:
		print("SETTLEMENT PARTITION TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
