extends SceneTree
## Bounty-gated technologies test suite. Task 1 section: the three new
## bounty types added for gate variety (designer directive 2026-08-01).
var _fails := 0

## Task 3: the approved 30-tech gate list (`.superpowers/sdd/2026-08-01-
## bounty-gated-techs/task-3-brief.md`), applied to data by
## `tests/tools_bounty_gate_sweep.gd`. This is the spec this section verifies
## against.
const EXPECTED_GATES := {
	&"sk_horse_lords": [&"wild_horses"], &"sk_leather_works": [&"furs"],
	&"great_yurt": [&"bone_fields"], &"sb_dawn_cavalry": [&"wild_horses"],
	&"oasis_blessing": [&"salt_flats"], &"sb_sun_forging": [&"bronze_ore"],
	&"ms_lunar_knights": [&"wild_horses"], &"ms_silver_mines": [&"copper_vein"],
	&"adamantine_forge": [&"titanstone_quarry"], &"cg_master_alloys": [&"bronze_ore", &"copper_vein"],
	&"volcanic_glass": [&"obsidian_flows"], &"cg_war_forges": [&"coal_seams"],
	&"emp_war_machines": [&"titanstone_quarry"], &"emp_aqueducts": [&"orchards"],
	&"road_network": [&"granite"], &"emp_harbor_cities": [&"fisheries"],
	&"gh_herb_gardens": [&"herb_meadows"], &"gh_root_bridges": [&"timber_giants"],
	&"gh_forest_trade": [&"amber_groves"], &"mining_expertise": [&"copper_vein"],
	&"ts_deep_mines": [&"granite"], &"storm_forge": [&"coal_seams"],
	&"iv_stone_masons": [&"marble"], &"ossuary_guards": [&"bone_fields"],
	&"fk_corpse_labor": [&"bone_fields"], &"fk_bone_walls": [&"basalt_columns"],
	&"jungle_pharmacy": [&"herb_meadows"], &"tj_mushroom_farms": [&"peat_bogs"],
	&"venomcraft": [&"dye_gardens"], &"sh_shard_miners": [&"crystal_springs"],
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm = root.get_node("/root/GameManager")
	gm.new_game(&"empire", false, 0)
	_run_new_bounty_types_test(gm)
	# Must run BEFORE _run_gate_core_test: that section temporarily mutates
	# emp_aqueducts.requires_bounty_types and restores it to [&"orchards"]
	# (the Task 3 sweep value) at the end, which this section's EXPECTED_GATES
	# check for emp_aqueducts depends on running first, before the mutation.
	var dm = root.get_node("/root/DataManager")
	_run_gate_sweep_verification(dm)
	_run_gate_core_test(gm)
	if _fails == 0:
		print("BOUNTY GATED TECHS TEST PASSED")
		quit(0)
	else:
		print("BOUNTY GATED TECHS TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

func _run_new_bounty_types_test(gm) -> void:
	for tid in [&"coal_seams", &"bone_fields", &"bronze_ore"]:
		_check(BountySystem.BOUNTY_TYPES.has(tid), "%s exists in BOUNTY_TYPES" % tid)
		_check(BountySystem.describe(tid) != "", "%s has a describe() line" % tid)
	# Plant each new type on a tile within CLAIM_RADIUS of a player city and
	# verify the generic pickup paths (income / recruit discount) see it.
	var player_id: StringName = gm.state.player_faction_id
	var fs = gm.state.faction_states[player_id]
	var city: CityState = gm.state.cities.get(fs.owned_cities[0])
	var map = gm.state.hex_map
	# Three distinct neighbor tiles of the city (all within CLAIM_RADIUS=2)
	var spots: Array[Vector2i] = []
	for coord in map.tiles:
		if spots.size() >= 3:
			break
		var d: int = HexHelper.hex_distance(city.hex_pos, coord)
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"" and t.special_id == &"" and t.landmark_id == &"":
			spots.append(coord)
	_check(spots.size() == 3, "found 3 clean tiles near the capital (got %d)" % spots.size())
	if spots.size() < 3:
		return
	map.get_tile(spots[0]).bounty_id = &"coal_seams"
	map.get_tile(spots[1]).bounty_id = &"bronze_ore"
	map.get_tile(spots[2]).bounty_id = &"bone_fields"
	var income: Dictionary = BountySystem.income_bonus_for_city(city)
	_check(income.get(1, 0) >= 6 + 4, "coal_seams+bronze_ore iron income sums (got %s)" % [income])
	_check(income.get(0, 0) >= 3, "bronze_ore gold income counted (got %s)" % [income])
	# bone_fields: undead recruit discount — find any undead-tagged unit
	var undead_unit: UnitData = null
	var dm = root.get_node("/root/DataManager")
	for uid in dm.units:
		if dm.units[uid].tags.has("undead"):
			undead_unit = dm.units[uid]
			break
	_check(undead_unit != null, "an undead-tagged unit exists")
	if undead_unit:
		_check(BountySystem.recruit_discount_for(city, undead_unit) >= 10,
			"bone_fields grants 10%% undead recruit discount")
	# Cleanup so later test sections see an unmodified map
	for s in spots:
		map.get_tile(s).bounty_id = &""

func _run_gate_sweep_verification(dm) -> void:
	for tech_id in EXPECTED_GATES:
		var data: ResearchData = dm.research.get(tech_id)
		_check(data != null, "%s exists" % tech_id)
		if data == null:
			continue
		_check(data.requires_bounty_types == (EXPECTED_GATES[tech_id] as Array[StringName]),
			"%s gated on %s (got %s)" % [tech_id, EXPECTED_GATES[tech_id], data.requires_bounty_types])
	# Global invariants over ALL research data:
	var gated_count := 0
	for research_id in dm.research:
		var d: ResearchData = dm.research[research_id]
		if d.requires_bounty_types.is_empty():
			continue
		gated_count += 1
		_check(d.tier >= 2, "%s: gated tech is tier 2+ (tier %d)" % [research_id, d.tier])
		_check(EXPECTED_GATES.has(research_id), "%s: gated tech is in the approved list" % research_id)
		for type_id in d.requires_bounty_types:
			_check(BountySystem.BOUNTY_TYPES.has(type_id), "%s: gate type %s exists" % [research_id, type_id])
	_check(gated_count == 30, "exactly 30 gated techs (got %d)" % gated_count)

func _run_gate_core_test(gm) -> void:
	gm.new_game(&"empire", false, 0)
	var rs = gm.research_system
	var player_id: StringName = gm.state.player_faction_id
	var fs = gm.state.faction_states[player_id]
	var dm = root.get_node("/root/DataManager")
	var map = gm.state.hex_map
	# Pick a tier-2+ empire tech with no prereqs beyond what we control:
	# gate emp_aqueducts (tier 3) on wild_horses for the test.
	var data: ResearchData = dm.research.get(&"emp_aqueducts")
	_check(data != null, "emp_aqueducts exists")
	data.requires_bounty_types = [&"wild_horses"] as Array[StringName]
	# Complete its prereqs so the bounty is the only gate.
	for prereq in data.prerequisites:
		if not fs.completed_research.has(prereq):
			fs.completed_research.append(prereq)
	fs.resources[Enums.ResourceType.TECHNOLOGY] = 10000

	# Case 1: type exists on map (plant one far away), faction holds none -> LOCKED
	var far_tile = null
	for coord in map.tiles:
		var t = map.get_tile(coord)
		if t and t.bounty_id == &"" and BountySystem.claimant_for(coord) == &"":
			far_tile = t
			break
	_check(far_tile != null, "found an unclaimed clean tile")
	far_tile.bounty_id = &"wild_horses"
	_check(rs.is_bounty_locked(player_id, data), "locked while type on map but unheld")
	_check(not rs.start_research(player_id, &"emp_aqueducts"), "start_research refuses while locked")
	var avail: Array[ResearchData] = rs.get_available_research(player_id)
	var listed := false
	for a in avail:
		if a.id == &"emp_aqueducts":
			listed = true
	_check(not listed, "locked tech excluded from get_available_research")
	var locked_list: Array[Dictionary] = rs.get_bounty_locked_research(player_id)
	var found_entry := false
	for e in locked_list:
		if e.data.id == &"emp_aqueducts" and e.missing_types.has(&"wild_horses"):
			found_entry = true
	_check(found_entry, "get_bounty_locked_research reports the tech + missing type")

	# Case 2: faction claims the type -> UNLOCKED, normal cost
	var city: CityState = gm.state.cities.get(fs.owned_cities[0])
	var near_tile = null
	var near_coord := Vector2i.ZERO
	for coord in map.tiles:
		# NOTE (Task 1 correction applied here too): BountySystem claim radius
		# is measured in hex distance, not Chebyshev grid distance.
		var d: int = HexHelper.hex_distance(city.hex_pos, coord)
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"":
			near_tile = t
			near_coord = coord
			break
	near_tile.bounty_id = &"wild_horses"
	_check(BountySystem.faction_has_bounty_type(player_id, &"wild_horses"), "claim within radius detected")
	_check(not rs.is_bounty_locked(player_id, data), "unlocked once claimed")
	_check(rs.effective_tech_cost(data) == data.tech_cost, "normal cost while type on map")
	var tech_before: int = fs.resources[Enums.ResourceType.TECHNOLOGY]
	_check(rs.start_research(player_id, &"emp_aqueducts"), "start_research succeeds once claimed")
	_check(fs.resources[Enums.ResourceType.TECHNOLOGY] == tech_before - data.tech_cost, "normal cost deducted")
	rs.cancel_research(player_id)

	# Case 3: type absent from the whole map -> researchable at 2x cost
	near_tile.bounty_id = &""
	far_tile.bounty_id = &""
	for coord in map.tiles:  # strip any scatter-placed wild_horses
		var t = map.get_tile(coord)
		if t and t.bounty_id == &"wild_horses":
			t.bounty_id = &""
	_check(not rs.is_bounty_locked(player_id, data), "not locked when type absent map-wide")
	_check(rs.effective_tech_cost(data) == data.tech_cost * 2, "cost doubles when type absent map-wide")
	tech_before = fs.resources[Enums.ResourceType.TECHNOLOGY]
	_check(rs.start_research(player_id, &"emp_aqueducts"), "start succeeds via fallback")
	_check(fs.resources[Enums.ResourceType.TECHNOLOGY] == tech_before - data.tech_cost * 2, "doubled cost deducted")
	rs.cancel_research(player_id)
	# Restore to the Task 3 sweep value (NOT empty): emp_aqueducts is
	# permanently gated on orchards by tests/tools_bounty_gate_sweep.gd, and
	# leaving it empty here would corrupt that invariant for any test run
	# after this one within the same process.
	data.requires_bounty_types = [&"orchards"] as Array[StringName]
