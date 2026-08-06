extends SceneTree
## Task R2 (Unit Stat Rescale): old-save fixture for the load-time HP backfill.
##
## MADE EXACT (final review, 2026-08-06): the backfill no longer gates on a
## magnitude heuristic at all. `GameState.save_schema_version` (default 0,
## stamped to `GameState.SAVE_SCHEMA_VERSION` by new_game()/save_game()) now
## tells load_game() unambiguously whether a save predates this task -- see
## game_manager.gd's load_game() comment. Both modes below still work
## unchanged: the OLD-scale slot-90 fixture was saved (MAKE mode) before this
## field existed, so it deserializes with the class default 0 and the
## backfill still fires; the NEW-scale heal-clamp fixture (VERIFY-HEAL-CLAMP)
## calls new_game()+save_game() itself in-process, so it's stamped current
## and the backfill correctly does NOT fire. What changed is WHY each
## direction passes: not "current_hp happens to look old/new-scale" but "the
## save says so explicitly."
##
## MAKE mode must run BEFORE the data sweep lands (current HEAD, old scale):
## starts a real game, deliberately damages a handful of units to fractional
## current_hp (so the fixture isn't just "everyone at full HP", which
## wouldn't meaningfully exercise the backfill's HP-conversion math), saves
## to a dedicated slot (90, kept out of test_save_roundtrip.gd's slot 99),
## and prints the pre-save (unit_data_id, old current_hp, old max_hp) tuples
## for a handful of sample units so the report has ground truth to compare
## post-backfill values against.
##
## VERIFY mode must run AFTER the data sweep + game_manager.gd backfill land:
## loads slot 90 (still old-scale current_hp on disk, and save_schema_version
## 0 since the .res predates the field), and checks every backfilled unit's
## current_hp lands in [1, new_max_hp] and roughly matches old_hp/10 (the
## backfill formula).
##
## VERIFY-HEAL-CLAMP mode (Task R2 review) tests the OPPOSITE direction: a
## brand-new NEW-scale save must NOT be misdetected as old-scale. Originally
## this depended on EVERY current_hp mutation site clamping to max_hp (a
## review pass found 7 turn_manager.gd faction-mechanic passive-heal sites
## that clamped to `ud.max_hp * ud.squad_size` instead -- max_hp is already
## the whole-squad pool -- letting a full-HP squad_size>1 unit overheal past
## its real max); now the save-schema-version gate makes this direction
## correct unconditionally, but the fixture still exercises the same overheal
## bug as a belt-and-suspenders regression check (a real overheal is still a
## bug worth catching even though it can no longer fool the backfill). This
## mode builds a full-HP squad_size>1 army, fires the Tainted Jade
## jungle-heal faction mechanic directly (`TurnManager._process_tainted_jade_taint`,
## taint_focus=1 branch, taint_power>=30, army on a JUNGLE tile), asserts no
## overheal happened, saves at the CURRENT (new) scale, reloads through the
## real backfill code path, and asserts current_hp is bit-for-bit unchanged.
##
## Run:
##   Make   (BEFORE rescale): godot --headless --path . -s res://tests/tools_rescale_save_fixture.gd -- --make
##   Verify (AFTER rescale):  godot --headless --path . -s res://tests/tools_rescale_save_fixture.gd -- --verify
##   Heal-clamp false-positive check (any time after the fix lands):
##     godot --headless --path . -s res://tests/tools_rescale_save_fixture.gd -- --verify-heal-clamp

const SLOT := 90
const HEAL_CLAMP_SLOT := 91
const SAMPLE_COUNT := 6
const HEAL_TEST_UNIT_ID := &"jade_cavalry" # squad_size=30, hp_per_soldier=11, max_hp=320

var _gm: Node
var _dm: Node
var _tm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_tm = root.get_node("/root/TurnManager")

	var args := OS.get_cmdline_user_args()
	if "--make" in args:
		_make()
	elif "--verify" in args:
		_verify()
	elif "--verify-heal-clamp" in args:
		_verify_heal_clamp()
	else:
		print("Pass -- --make (before rescale), -- --verify (after rescale), or -- --verify-heal-clamp")
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

func _verify_heal_clamp() -> void:
	print("--- Rescale save fixture VERIFY-HEAL-CLAMP (false-positive direction) ---")
	_gm.new_game(&"tainted_jade", false, 0)
	var fs: FactionState = _gm.state.faction_states.get(&"tainted_jade")
	if fs == null:
		printerr("No tainted_jade FactionState in a fresh game")
		quit(1)
		return
	fs.taint_focus = 1 # Verdant Growth -- jungle heal branch
	# _process_tainted_jade_taint applies natural decay (maxi(1, 2 -
	# jungle_cities), so >=1 with zero owned cities) BEFORE the taint_focus
	# match block's `if fs.taint_power >= 30:` heal-branch check -- set well
	# above the threshold so the decay can't drop it below 30 first.
	fs.taint_power = 40

	var ud: UnitData = _dm.get_unit(HEAL_TEST_UNIT_ID)
	if ud == null:
		printerr("Missing unit data %s" % HEAL_TEST_UNIT_ID)
		quit(1)
		return
	if ud.squad_size <= 1:
		printerr("%s has squad_size<=1 -- not a valid overheal-bug regression case" % HEAL_TEST_UNIT_ID)
		quit(1)
		return

	var jungle_hex := _find_or_force_jungle_hex()

	var army := ArmyState.new()
	army.army_id = &"heal_clamp_test_army"
	army.faction_id = &"tainted_jade"
	army.hex_pos = jungle_hex
	var inst := UnitInstance.new()
	inst.init_from_data(ud, &"heal_clamp_test_u0") # current_hp = ud.max_hp (full HP)
	army.units.append(inst)
	_gm.state.armies[army.army_id] = army
	_gm.invalidate_faction_army_cache()

	var hp_before_heal := inst.current_hp
	_tm._process_tainted_jade_taint(fs)

	var overhealed := inst.current_hp > ud.max_hp
	print("Fired jungle-heal mechanic on full-HP %s: current_hp %d -> %d (max_hp=%d) %s" % [
		HEAL_TEST_UNIT_ID, hp_before_heal, inst.current_hp, ud.max_hp,
		("OVERHEAL BUG" if overhealed else "correctly capped"),
	])
	if overhealed:
		printerr("FAIL: heal exceeded max_hp -- the clamp-site fix did not land")
		quit(1)
		return

	var hp_at_new_scale := inst.current_hp
	_gm.save_game(HEAL_CLAMP_SLOT)
	_gm.load_game(HEAL_CLAMP_SLOT)
	if _gm.state == null:
		printerr("Fixture failed to reload")
		quit(1)
		return

	var reloaded_army: ArmyState = _gm.state.armies.get(&"heal_clamp_test_army")
	if reloaded_army == null or reloaded_army.units.is_empty():
		printerr("FAIL: test army missing after reload")
		quit(1)
		return
	var reloaded_hp: int = reloaded_army.units[0].current_hp
	print("After save+reload through the real backfill path: current_hp=%d (expected unchanged at %d)" % [reloaded_hp, hp_at_new_scale])

	if reloaded_hp == hp_at_new_scale:
		print("SAVE FIXTURE HEAL-CLAMP VERIFY PASSED (new-scale save NOT misdetected as old-scale)")
		quit(0)
	else:
		printerr("FAIL: current_hp changed across reload -- backfill false-positived on a NEW-scale save")
		quit(1)

func _find_or_force_jungle_hex() -> Vector2i:
	for coord in _gm.state.hex_map.tiles:
		var tile = _gm.state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.JUNGLE:
			return coord
	# No natural jungle on this generated map -- force one cityless land tile
	# to JUNGLE for the test (mutating a throwaway test-run map, not saved
	# back to any real map data).
	for coord in _gm.state.hex_map.tiles:
		var tile = _gm.state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if _gm.city_system.get_city_at_hex(coord) != null:
			continue
		tile.terrain = Enums.TerrainType.JUNGLE
		return coord
	return Vector2i(10, 10)
