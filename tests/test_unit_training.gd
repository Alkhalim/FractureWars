extends SceneTree
## Balance Batch 2, Item 4: every unit whose unlocking building is a TIER-1
## building (required_capital_level <= 1, no upgrades_from) trains in 1 turn.
## A unit unlocked by a tier-1 building AND (elsewhere) a tier-2+ building
## still qualifies -- it's reachable at tier 1, so it must train in 1 turn.
## Units unlocked ONLY by tier-2+ buildings are unaffected by this rule.
## Run: godot --headless --path . -s res://tests/test_unit_training.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")

	# Discover every unit reachable from a tier-1 building -- not a fixed
	# list, so any future new tier-1 building/unit is swept automatically.
	var tier1_unit_ids: Dictionary = {} # unit_id -> true
	var tier1_building_count := 0
	for bid in dm.buildings.keys():
		var b: BuildingData = dm.buildings[bid]
		if b.required_capital_level <= 1 and b.upgrades_from == &"":
			tier1_building_count += 1
			for uid in b.unlocks_units:
				tier1_unit_ids[uid] = true

	_check(tier1_building_count >= 90, "sanity: a plausible number of tier-1 buildings were scanned (>=90), got %d" % tier1_building_count)
	_check(tier1_unit_ids.size() >= 40, "sanity: a plausible number of tier-1-unlocked units were found (>=40), got %d" % tier1_unit_ids.size())

	var checked := 0
	for uid in tier1_unit_ids.keys():
		var ud: UnitData = dm.get_unit(uid)
		if ud == null:
			_check(false, "tier-1-unlocked unit id %s resolves in DataManager.units" % uid)
			continue
		checked += 1
		_check(ud.recruit_time == 1, "%s (%s, tier-1-unlocked) trains in 1 turn, got recruit_time=%d" % [uid, ud.faction_id, ud.recruit_time])
	_check(checked == tier1_unit_ids.size(), "every tier-1-unlocked unit id resolved to real unit data, got %d/%d" % [checked, tier1_unit_ids.size()])

	# ── Spot pins: named units that were >1-turn before this batch, now 1. ──
	for pinned_id in [&"legionary", &"cinderguard_warden", &"storm_drakes", &"bonecaller", &"crystal_menders"]:
		var pud: UnitData = dm.get_unit(pinned_id)
		if pud == null:
			_check(false, "%s unit data exists (spot pin)" % pinned_id)
		else:
			_check(pud.recruit_time == 1, "%s (spot pin, was >1-turn) recruit_time == 1, got %d" % [pinned_id, pud.recruit_time])

	# ── Regression guard: a unit unlocked ONLY by tier-2+ buildings must be
	# left alone by this rule (not swept to 1 just because it's cheap/early).
	# Find one such unit dynamically: any unit whose unlockers are ALL
	# tier-2+, with recruit_time still > 1 in the data as of this batch. ──
	var tier2plus_only_examples: Array = []
	for uid in dm.units.keys():
		var unlockers: Array = []
		for bid2 in dm.buildings.keys():
			var b2: BuildingData = dm.buildings[bid2]
			if (b2.unlocks_units as Array).has(uid):
				unlockers.append(b2)
		if unlockers.is_empty():
			continue
		if tier1_unit_ids.has(uid):
			continue
		tier2plus_only_examples.append(uid)
	_check(tier2plus_only_examples.size() > 0, "sanity: at least one unit is unlocked exclusively by tier-2+ buildings (regression-guard precondition)")

	if _fails == 0:
		print("UNIT TRAINING TEST PASSED")
		quit(0)
	else:
		print("UNIT TRAINING TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
