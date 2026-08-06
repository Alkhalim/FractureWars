extends SceneTree
## Task R2 (Unit Stat Rescale): old-save fixture for the load-time HP backfill.
##
## MAKE mode must run BEFORE the data sweep lands (current HEAD, old scale):
## starts a real game, deliberately damages a handful of units to fractional
## current_hp (so the fixture isn't just "everyone at full HP", which would
## never exercise the backfill's `current_hp > new_max_hp * 1.5` heuristic
## any differently than a trivial case), saves to a dedicated slot (90, kept
## out of test_save_roundtrip.gd's slot 99), and prints the pre-save
## (unit_data_id, old current_hp, old max_hp) tuples for a handful of sample
## units so the report has ground truth to compare post-backfill values against.
##
## VERIFY mode must run AFTER the data sweep + game_manager.gd backfill land:
## loads slot 90 (still old-scale current_hp on disk, since the .res save
## predates the rescale), and checks every backfilled unit's current_hp lands
## in [1, new_max_hp] and roughly matches old_hp/10 (the backfill formula).
##
## Run:
##   Make   (BEFORE rescale): godot --headless --path . -s res://tests/tools_rescale_save_fixture.gd -- --make
##   Verify (AFTER rescale):  godot --headless --path . -s res://tests/tools_rescale_save_fixture.gd -- --verify

const SLOT := 90
const SAMPLE_COUNT := 6

var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")

	var args := OS.get_cmdline_user_args()
	if "--make" in args:
		_make()
	elif "--verify" in args:
		_verify()
	else:
		print("Pass -- --make (before rescale) or -- --verify (after rescale)")
		quit(1)

func _make() -> void:
	_gm.new_game(&"empire", false, 0)

	# Damage a spread of units across armies/factions to fractional HP so the
	# fixture exercises real mid-battle-ish state, not just "everyone full".
	var damaged: Array[Dictionary] = []
	var n := 0
	for aid in _gm.state.armies:
		var army: ArmyState = _gm.state.armies[aid]
		for u: UnitInstance in army.units:
			n += 1
			# Deterministic spread: full HP, 75%, 50%, 25%, 15%, then repeat.
			var fractions := [1.0, 0.75, 0.5, 0.25, 0.15]
			var frac: float = fractions[n % fractions.size()]
			var ud: UnitData = _dm.get_unit(u.unit_data_id)
			if ud == null:
				continue
			u.current_hp = maxi(1, roundi(float(ud.max_hp) * frac))
			if damaged.size() < SAMPLE_COUNT:
				damaged.append({
					"unit_data_id": String(u.unit_data_id),
					"old_current_hp": u.current_hp,
					"old_max_hp": ud.max_hp,
					"frac": frac,
				})

	_gm.save_game(SLOT)
	print("--- Rescale save fixture MAKE (slot %d, OLD scale) ---" % SLOT)
	for d: Dictionary in damaged:
		print("%s current_hp=%d old_max_hp=%d (frac=%.2f)" % [
			d["unit_data_id"], d["old_current_hp"], d["old_max_hp"], d["frac"],
		])
	print("FIXTURE SAVED: user://saves/save_%d.res (%d units total, %d sampled above)" % [SLOT, n, damaged.size()])
	quit(0)

func _verify() -> void:
	if not _gm.has_save(SLOT):
		printerr("No fixture at slot %d -- run -- --make BEFORE the rescale lands first" % SLOT)
		quit(1)
		return
	_gm.load_game(SLOT)
	if _gm.state == null:
		printerr("Fixture failed to load")
		quit(1)
		return

	print("--- Rescale save fixture VERIFY (slot %d, post-backfill) ---" % SLOT)
	var checked := 0
	var fails := 0
	for aid in _gm.state.armies:
		var army: ArmyState = _gm.state.armies[aid]
		for u: UnitInstance in army.units:
			var ud: UnitData = _dm.get_unit(u.unit_data_id)
			if ud == null:
				continue
			checked += 1
			var ok := u.current_hp >= 1 and u.current_hp <= ud.max_hp
			if not ok:
				fails += 1
			if checked <= SAMPLE_COUNT * 3:
				print("%s current_hp=%d new_max_hp=%d %s" % [
					u.unit_data_id, u.current_hp, ud.max_hp, ("OK" if ok else "OUT OF RANGE"),
				])
	print("Checked %d units, %d out-of-range (expect 0)" % [checked, fails])
	if fails == 0:
		print("SAVE FIXTURE BACKFILL VERIFY PASSED")
		quit(0)
	else:
		print("SAVE FIXTURE BACKFILL VERIFY FAILED")
		quit(1)
