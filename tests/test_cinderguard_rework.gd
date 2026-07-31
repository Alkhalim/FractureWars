extends SceneTree
## Task 1 (Package A) of the Cinderguard rework: halve the iron pumps, kill
## the hidden per-city vigilance-iron layer, add the Smelt Surplus sink.
## Run: godot --headless --path . -s res://tests/test_cinderguard_rework.gd

var _fails := 0
var _gm: Node
var _tm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_tm = root.get_node("/root/TurnManager")
	var dm = root.get_node("/root/DataManager")
	_gm.new_game(&"cinderguard", false, 0)

	# ── Building data cuts (halved iron pumps) ──
	_check(dm.get_building(&"ember_foundry").income_bonus.get(1, 0) == 45, "ember foundry iron 45")
	_check(dm.get_building(&"ember_foundry").display_name == "Ember Foundry II", "armory renamed")
	_check(dm.get_building(&"volcanic_smelter").income_bonus.get(1, 0) == 35, "smelter 35")
	_check(dm.get_building(&"cinder_mine").income_bonus.get(1, 0) == 20, "mine 20")
	_check(dm.get_building(&"magma_vent").income_bonus.get(1, 0) == 16, "vent 16")
	_check(dm.get_building(&"molten_core_forge").income_bonus.get(1, 0) == 28, "arsenal 28")

	# ── deepiron extractor untouched (not part of this cut) ──
	_check(dm.get_building(&"extractor_deepiron").income_bonus.get(1, 0) == 20, "deepiron extractor untouched at 20")

	# ── Hidden vigilance-iron layer deleted (income delta parity) ──
	# Isolate the mechanic-income-modifier stage directly: no captives and no
	# forge building present, so the ONLY thing that could move iron here
	# (pre-fix) is the vigilance*0.06 term. Post-fix it must be zero and must
	# not vary with vigilance at all.
	var cg_fs: FactionState = _gm.state.faction_states[&"cinderguard"]
	var vig_city := CityState.new()
	vig_city.faction_id = &"cinderguard"
	cg_fs.resources[Enums.ResourceType.CAPTIVES] = 0
	cg_fs.border_vigilance = 50
	var result_50: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	cg_fs.border_vigilance = 80
	var result_80: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	_check(int(result_50.income_delta.get(Enums.ResourceType.IRON, 0)) == 0, "no vigilance iron bonus at vigilance 50")
	_check(int(result_80.income_delta.get(Enums.ResourceType.IRON, 0)) == 0, "no vigilance iron bonus at vigilance 80")
	_check(int(result_50.income_delta.get(Enums.ResourceType.IRON, 0)) == int(result_80.income_delta.get(Enums.ResourceType.IRON, 0)), "vigilance 50 vs 80 iron income identical")

	# ── Captive forge conversion KEPT (a real trade, not the hidden layer) ──
	cg_fs.resources[Enums.ResourceType.CAPTIVES] = 10
	vig_city.buildings.append(&"ember_foundry")
	var result_forge: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	_check(int(result_forge.income_delta.get(Enums.ResourceType.IRON, 0)) == 18, "captive forge conversion kept (+18 iron)")
	_check(int(result_forge.captive_consumption) == 4, "captive forge conversion still consumes 4 captives")

	# ── Smelt Surplus applier: -40 iron, +20 scrap ──
	var cfs: FactionState = _gm.state.faction_states[&"cinderguard"]
	cfs.resources[Enums.ResourceType.IRON] = 100
	var scrap_before: float = cfs.scavenge_stockpile
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"forge_allocation", "forge_smelt")
	_check(int(cfs.resources[Enums.ResourceType.IRON]) == 60, "smelt consumed 40 iron")
	_check(cfs.scavenge_stockpile == scrap_before + 20, "smelt produced 20 scrap")

	# ── Task 2: vigilance is a chosen posture, not a coinflip ──────────
	# Isolate _process_cinderguard_forge from real settlements/buildings so
	# the drift and economics math can be checked exactly.
	var real_owned_cities: Array[StringName] = cg_fs.owned_cities.duplicate()
	cg_fs.owned_cities = []

	# Target-seeking drift: rises ~4/turn toward the target, no auto-centering to 50.
	cg_fs.vigilance_target = 85
	cg_fs.border_vigilance = 50
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 54, "drift +4 toward target 85 (tick 1)")
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 58, "drift +4 toward target 85 (tick 2)")
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 62, "drift +4 toward target 85 (tick 3), not centered back to 50")

	# Posture economics: war footing (>=60) pays iron for gold+food.
	cg_fs.vigilance_target = 80
	cg_fs.border_vigilance = 80
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 80, "vigilance holds when already at target (no auto-center)")
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 132, "war footing (80) nets +int(80*0.4)=32 iron")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 92, "war footing (80) costs -int(80*0.1)=8 gold")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 92, "war footing (80) costs -int(80*0.1)=8 food")

	# Mid-band (41-59): flat +2 iron, no gold/food cost.
	cg_fs.vigilance_target = 50
	cg_fs.border_vigilance = 50
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 102, "mid-band nets flat +2 iron")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 100, "mid-band gold untouched")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 100, "mid-band food untouched")

	# Fortress mode (<=40): old flat iron tiers gone (iron +0), loyalty/pop/food perk kept.
	cg_fs.vigilance_target = 15
	cg_fs.border_vigilance = 15
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 100, "fortress mode grants no iron (old flat tiers removed)")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 106, "fortress mode still grants +6 food")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 104, "fortress mode still grants +4 gold")

	# Threshold-crossing turn_log entries at 30/75 (matches the battle-sim tiers).
	_tm.turn_log.clear()
	cg_fs.vigilance_target = 90
	cg_fs.border_vigilance = 72
	_tm._process_cinderguard_forge(cg_fs) # 72 -> 76, crosses 75 upward
	var crossed_war := false
	for entry in _tm.turn_log:
		if "War Footing" in str(entry.text):
			crossed_war = true
	_check(crossed_war, "crossing 75 upward logs a War Footing turn_log entry")

	_tm.turn_log.clear()
	cg_fs.vigilance_target = 10
	cg_fs.border_vigilance = 33
	_tm._process_cinderguard_forge(cg_fs) # 33 -> 29, crosses 30 downward
	var crossed_fortress := false
	for entry in _tm.turn_log:
		if "Fortress doctrine" in str(entry.text):
			crossed_fortress = true
	_check(crossed_fortress, "crossing 30 downward logs a Fortress doctrine turn_log entry")

	# Exit logging: leaving a combat band (dropping out of War Footing, or
	# rising out of Fortress doctrine) must ALSO log a turn_log entry — a
	# player silently losing +15% attack or +20% defense is a transparency
	# bug just as much as silently gaining it.
	_tm.turn_log.clear()
	cg_fs.vigilance_target = 10
	cg_fs.border_vigilance = 76
	_tm._process_cinderguard_forge(cg_fs) # 76 -> 72, drops below 75 (exits War Footing)
	var left_war := false
	for entry in _tm.turn_log:
		if "War Footing" in str(entry.text) and "cool" in str(entry.text):
			left_war = true
	_check(left_war, "dropping below 75 logs a War Footing EXIT turn_log entry")

	_tm.turn_log.clear()
	cg_fs.vigilance_target = 90
	cg_fs.border_vigilance = 28
	_tm._process_cinderguard_forge(cg_fs) # 28 -> 32, rises above 30 (exits Fortress doctrine)
	var left_fortress := false
	for entry in _tm.turn_log:
		if "Fortress doctrine" in str(entry.text) and "stirs" in str(entry.text):
			left_fortress = true
	_check(left_fortress, "rising above 30 logs a Fortress doctrine EXIT turn_log entry")

	cg_fs.owned_cities = real_owned_cities

	# ── AI posture selection: War Footing at war, Fortress Doctrine at peace ──
	var no_settlements: Array[StringName] = []
	cg_fs.border_fortresses.clear()
	cg_fs.scavenge_stockpile = 0
	cg_fs.resources[Enums.ResourceType.IRON] = 50
	_gm._set_relation(&"cinderguard", &"empire", Enums.FactionRelation.WAR)
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(cg_fs.vigilance_target == 85, "AI sets War Footing target (85) while at war")

	_gm._set_relation(&"cinderguard", &"empire", Enums.FactionRelation.HOSTILE)
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(cg_fs.vigilance_target == 15, "AI sets Fortress Doctrine target (15) when not at war")

	# AI smelts surplus iron instead of touching posture when iron is very high.
	cg_fs.vigilance_target = 50
	cg_fs.resources[Enums.ResourceType.IRON] = 350
	var scrap_before2: float = cg_fs.scavenge_stockpile
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 310, "AI smelts 40 iron when surplus > 300")
	_check(cg_fs.scavenge_stockpile == scrap_before2 + 20, "AI smelt produces 20 scrap")
	_check(cg_fs.vigilance_target == 50, "AI smelt tick leaves posture target untouched")

	# ── Task 3: Dragon raids threaten a NAMED building with real choices ──

	# Ground truth: independently compute the max-build_cost building among a
	# known set of real building ids (never re-derive from the code under
	# test, or a bug in the implementation could match a bug in the check).
	var bld_ids: Array[StringName] = [&"volcanic_smelter", &"cinder_mine", &"ember_foundry"]
	var expected_top_bld: StringName = &""
	var expected_top_value := -1
	for bid in bld_ids:
		var bd: BuildingData = dm.get_building(bid)
		if bd == null:
			_check(false, "test building id exists in data: %s" % bid)
			continue
		var total := 0
		for rt in bd.build_cost:
			total += int(bd.build_cost[rt])
		if total > expected_top_value:
			expected_top_value = total
			expected_top_bld = bid

	# _get_highest_value_building() picks the priciest building by summed build_cost.
	var priced_city := CityState.new()
	priced_city.buildings = bld_ids.duplicate()
	_check(_tm._get_highest_value_building(priced_city) == expected_top_bld, "highest-value building matches ground-truth build_cost sum")

	# No-buildings settlement degrades gracefully: names no building.
	var bare_city := CityState.new()
	_check(_tm._get_highest_value_building(bare_city) == &"", "no-buildings settlement names no building")

	# Save/restore raid state so this test block doesn't leak into anything else.
	var saved_owned2: Array[StringName] = cg_fs.owned_cities.duplicate()
	var saved_fortresses2: Dictionary = cg_fs.border_fortresses.duplicate()
	var saved_cooldown2: int = cg_fs.dragon_raid_cooldown
	var saved_target2: StringName = cg_fs.dragon_raid_target
	var saved_building2: StringName = cg_fs.dragon_raid_building

	# End-to-end: the raid trigger names the highest-value building of the
	# settlement it actually picks.
	var raid_city_id: StringName = &"__test_raid_settlement__"
	var raid_city := CityState.new()
	raid_city.city_id = raid_city_id
	raid_city.faction_id = &"cinderguard"
	raid_city.is_settlement = true
	raid_city.population = 100
	raid_city.buildings = bld_ids.duplicate()
	_gm.state.cities[raid_city_id] = raid_city

	cg_fs.owned_cities = [raid_city_id]
	cg_fs.border_fortresses.clear()
	cg_fs.dragon_raid_cooldown = 0
	cg_fs.dragon_raid_target = &""
	cg_fs.dragon_raid_building = &""
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.dragon_raid_target == raid_city_id, "raid trigger targets the only settlement")
	_check(cg_fs.dragon_raid_building == expected_top_bld, "raid trigger names the settlement's highest-value building")

	_gm.state.cities.erase(raid_city_id)
	cg_fs.owned_cities = saved_owned2
	cg_fs.border_fortresses = saved_fortresses2
	cg_fs.dragon_raid_cooldown = saved_cooldown2

	# Forced-fail "Man the Walls" destroys THE NAMED building, not a random
	# one. fort_lv=0 and vigilance=0 caps defense_score at 29 (< 45), so the
	# defense fails on every possible RNG roll — deterministic without seeding.
	var fail_city_id: StringName = &"__test_fail_settlement__"
	var fail_city := CityState.new()
	fail_city.city_id = fail_city_id
	fail_city.faction_id = &"cinderguard"
	fail_city.is_settlement = true
	fail_city.population = 100
	fail_city.buildings = [&"volcanic_smelter", &"cinder_mine", &"ember_foundry"]
	_gm.state.cities[fail_city_id] = fail_city

	cg_fs.dragon_raid_target = fail_city_id
	cg_fs.dragon_raid_building = &"ember_foundry"
	cg_fs.border_fortresses[fail_city_id] = 0
	cg_fs.border_vigilance = 0
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"dragon_raid", "dragon_defend")
	_check(not fail_city.buildings.has(&"ember_foundry"), "forced-fail destroys the named building")
	_check(fail_city.buildings.has(&"volcanic_smelter") and fail_city.buildings.has(&"cinder_mine"), "forced-fail leaves the other buildings untouched")

	# Edge safety: named building no longer present (e.g. stale state) falls
	# back to destroying from what remains, instead of crashing or no-op.
	var remaining_before := fail_city.buildings.duplicate()
	cg_fs.dragon_raid_target = fail_city_id
	cg_fs.dragon_raid_building = &"not_a_real_building"
	cg_fs.border_fortresses[fail_city_id] = 0
	cg_fs.border_vigilance = 0
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"dragon_raid", "dragon_defend")
	_check(fail_city.buildings.size() == remaining_before.size() - 1, "missing named building falls back to destroying a remaining building")

	_gm.state.cities.erase(fail_city_id)

	# No-buildings settlement: forced-fail degrades gracefully — no building
	# to name, no building to destroy, but the existing pop/loyalty damage
	# still lands (Man-the-Walls failure falls back to existing behavior).
	var bare_fail_id: StringName = &"__test_bare_fail_settlement__"
	var bare_fail_city := CityState.new()
	bare_fail_city.city_id = bare_fail_id
	bare_fail_city.faction_id = &"cinderguard"
	bare_fail_city.is_settlement = true
	bare_fail_city.population = 100
	_gm.state.cities[bare_fail_id] = bare_fail_city

	cg_fs.dragon_raid_target = bare_fail_id
	cg_fs.dragon_raid_building = &""
	cg_fs.border_fortresses[bare_fail_id] = 0
	cg_fs.border_vigilance = 0
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"dragon_raid", "dragon_defend")
	_check(bare_fail_city.buildings.is_empty(), "no-buildings settlement stays buildingless after forced fail")
	_check(bare_fail_city.population == 80, "no-buildings settlement still takes the population hit (existing behavior)")

	_gm.state.cities.erase(bare_fail_id)

	# Set Dragon Traps: still costs 20 iron; success rewards unchanged.
	var trap_city_id: StringName = &"__test_trap_settlement__"
	var trap_city := CityState.new()
	trap_city.city_id = trap_city_id
	trap_city.faction_id = &"cinderguard"
	trap_city.is_settlement = true
	_gm.state.cities[trap_city_id] = trap_city

	cg_fs.dragon_raid_target = trap_city_id
	cg_fs.border_fortresses[trap_city_id] = 3 # 3*20 + 40 + [0..29] = 100..129 -> guaranteed success
	cg_fs.resources[Enums.ResourceType.IRON] = 50
	cg_fs.resources[Enums.ResourceType.TECHNOLOGY] = 0
	var scrap_before_trap: float = cg_fs.scavenge_stockpile
	var survived_before_trap := cg_fs.dragon_raids_survived
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"dragon_raid", "dragon_trap")
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 30, "dragon trap still costs 20 iron")
	_check(cg_fs.scavenge_stockpile == scrap_before_trap + 25, "dragon trap success still grants +25 scrap (unchanged)")
	_check(int(cg_fs.resources[Enums.ResourceType.TECHNOLOGY]) == 8, "dragon trap success still grants +8 tech (unchanged)")
	_check(cg_fs.dragon_raids_survived == survived_before_trap + 1, "dragon trap success still increments raids survived (unchanged)")

	_gm.state.cities.erase(trap_city_id)

	# ── Evacuate: no damage roll; the settlement goes offline (empty income)
	# for exactly 3 turns, then resumes. Exercised end-to-end: the dilemma
	# applier sets the field, city_system's per-turn processing ticks it down.
	_check(cg_fs.owned_cities.size() > 0, "sanity: cinderguard owns at least one real city for the evacuate test")
	var evac_id: StringName = cg_fs.owned_cities[0]
	var evac_city: CityState = _gm.state.cities[evac_id]
	evac_city.production_disabled_turns = 0
	_check(_gm.city_system.calculate_city_income(evac_city).size() > 0, "sanity: city produces income normally before evacuation")

	cg_fs.dragon_raid_target = evac_id
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"dragon_raid", "dragon_evacuate")
	_check(evac_city.production_disabled_turns == 3, "evacuate applier sets production_disabled_turns to 3")
	_check(_gm.city_system.calculate_city_income(evac_city) == {}, "evacuated settlement's income is empty right after evacuating")

	_gm.city_system.process_turn(&"cinderguard")
	_check(evac_city.production_disabled_turns == 2, "production_disabled_turns ticks down 3 -> 2 after one turn")
	_check(_gm.city_system.calculate_city_income(evac_city) == {}, "income still empty with 2 turns remaining")

	_gm.city_system.process_turn(&"cinderguard")
	_check(evac_city.production_disabled_turns == 1, "production_disabled_turns ticks down 2 -> 1")

	_gm.city_system.process_turn(&"cinderguard")
	_check(evac_city.production_disabled_turns == 0, "production_disabled_turns ticks down 1 -> 0 (3 full turns blocked)")
	_check(_gm.city_system.calculate_city_income(evac_city).size() > 0, "income resumes once production_disabled_turns hits 0")

	_gm.city_system.process_turn(&"cinderguard")
	_check(evac_city.production_disabled_turns == 0, "production_disabled_turns does not go negative")

	# Restore raid state.
	cg_fs.dragon_raid_target = saved_target2
	cg_fs.dragon_raid_building = saved_building2

	if _fails == 0:
		print("CINDERGUARD REWORK TEST PASSED")
		quit(0)
	else:
		print("CINDERGUARD REWORK TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
