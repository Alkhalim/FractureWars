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
	# (waystation, resource_camp, frontier_watchpost, frontier_shrine, or
	# region-gated extractor/landmark buildings)
	var saved_is_settlement := capital.is_settlement
	capital.is_settlement = true
	var settlement_avail: Array[BuildingData] = cs.get_available_buildings(capital, true)
	_check(not settlement_avail.is_empty(), "settlement offers at least one building")
	for bd in settlement_avail:
		_check(bd.settlement_only or bd.requires_region_resource != &"" or bd.requires_region_landmark != &"", "settlement offered only settlement-grade/extractor/landmark: %s" % bd.id)

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

	# ── AI: a settlement with a free slot + resources builds one of the 4
	# settlement-grade buildings, not an arbitrary fallback. ──
	_run_ai_settlement_priority(gm, tm)

	_finish()

func _run_ai_settlement_priority(gm, tm) -> void:
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

	tm._execute_ai_city_management(faction_id)

	var built_id: StringName = &""
	for item in settlement.build_queue:
		if (tm.SETTLEMENT_BUILD_PRIORITY as Array).has(item.building_id):
			built_id = item.building_id
			break
	if built_id == &"":
		for bid in settlement.buildings:
			if (tm.SETTLEMENT_BUILD_PRIORITY as Array).has(bid):
				built_id = bid
				break
	_check(built_id != &"", "AI-managed settlement builds one of the 4 settlement-grade buildings (buildings=%s queue=%s)" % [settlement.buildings, settlement.build_queue])
	if built_id != &"":
		print("NOTE: settlement AI picked %s" % built_id)

	gm.state.cities.erase(settlement.city_id)
	fs.owned_cities.erase(settlement.city_id)
	fs.resources = saved_resources

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
