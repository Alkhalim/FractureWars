extends SceneTree
## Plan D Task 1: seeded battle fingerprint harness.
## Captures a per-tick fingerprint of full V2 and V3 battles under a fixed
## seed. Any refactor of the simulators must reproduce the baseline exactly
## (same RNG consumption order, same tick-by-tick state).
##
## Capture baseline:  godot --headless --path . -s res://tests/test_battle_determinism.gd -- --baseline
## Compare:           godot --headless --path . -s res://tests/test_battle_determinism.gd

const BASELINE_DIR := "res://tests/baselines"
const SEED := 133742

var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire")

	var baseline_mode := "--baseline" in OS.get_cmdline_user_args()

	var v2_fp := _run_v2()
	var v3_fp := _run_v3()

	if baseline_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE_DIR))
		_write(BASELINE_DIR + "/battle_v2.txt", v2_fp)
		_write(BASELINE_DIR + "/battle_v3.txt", v3_fp)
		print("BASELINES WRITTEN (v2 %d chars, v3 %d chars)" % [v2_fp.length(), v3_fp.length()])
		quit(0)
		return

	var v2_ok := _compare("v2", BASELINE_DIR + "/battle_v2.txt", v2_fp)
	var v3_ok := _compare("v3", BASELINE_DIR + "/battle_v3.txt", v3_fp)
	if v2_ok and v3_ok:
		print("FINGERPRINT MATCH")
		quit(0)
	else:
		print("FINGERPRINT MISMATCH")
		quit(1)

func _compare(label: String, path: String, current: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("MISSING BASELINE %s — run with -- --baseline first" % label)
		return false
	var expected := f.get_as_text()
	if expected == current:
		return true
	# Locate first differing line for diagnostics
	var exp_lines := expected.split("\n")
	var cur_lines := current.split("\n")
	for i in mini(exp_lines.size(), cur_lines.size()):
		if exp_lines[i] != cur_lines[i]:
			print("%s DIVERGES at line %d:\n  exp: %s\n  cur: %s" % [label, i, exp_lines[i], cur_lines[i]])
			return false
	print("%s DIVERGES in length: exp=%d cur=%d lines" % [label, exp_lines.size(), cur_lines.size()])
	return false

func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()

func _build_army(id: StringName, faction: StringName, unit_ids: Array) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = id
	army.faction_id = faction
	army.hex_pos = Vector2i(10, 10)
	var n := 0
	for uid in unit_ids:
		var ud: UnitData = _dm.get_unit(uid)
		if ud == null:
			continue
		var inst := UnitInstance.new()
		inst.init_from_data(ud, StringName("%s_u%d" % [id, n]))
		army.units.append(inst)
		n += 1
	return army

func _pick_units(faction: StringName, count: int) -> Array:
	var result: Array = []
	for uid in _dm.units:
		var ud: UnitData = _dm.units[uid]
		if ud.faction_id == faction:
			result.append(uid)
			if result.size() >= count:
				break
	return result

func _run_v2() -> String:
	seed(SEED)
	var atk := _build_army(&"fp_atk", &"empire", _pick_units(&"empire", 8))
	var def := _build_army(&"fp_def", &"skulloath", _pick_units(&"skulloath", 8))
	var sim = load("res://scripts/systems/battle/battle_simulator_v2.gd").new()
	sim.compute_grid_size(atk, def)
	var terrain = load("res://scripts/systems/battle/battle_terrain_gen.gd").generate(Enums.TerrainType.PLAINS, 4242, sim.grid_width, sim.grid_height)
	sim.setup_terrain(terrain)
	sim.setup_attacker_formations(atk)
	sim.setup_defender_formations(def)
	sim.assign_ai_orders_both_sides()
	var lines: PackedStringArray = []
	for tick in range(sim.max_ticks):
		sim.simulate_tick()
		if tick % 5 == 0 or sim.is_finished:
			lines.append(_fingerprint_v2(sim, tick))
		if sim.is_finished:
			break
	lines.append("survivors atk=%d def=%d" % [sim.get_surviving_formations(0).size(), sim.get_surviving_formations(1).size()])
	return "\n".join(lines)

func _fingerprint_v2(sim, tick: int) -> String:
	var parts: PackedStringArray = ["t%d" % tick]
	for arr in [sim.attacker_formations, sim.defender_formations]:
		for f in arr:
			parts.append("%s|%s|%d|%d|%.3f" % [f.instance_id, f.anchor_pos, f.entities_alive, f.current_hp, f.current_morale])
	return ";".join(parts)

func _run_v3() -> String:
	seed(SEED)
	var atk := _build_army(&"fp3_atk", &"empire", _pick_units(&"empire", 8))
	var def := _build_army(&"fp3_def", &"gladehost", _pick_units(&"gladehost", 8))
	var sim = load("res://scripts/systems/battle/battle_simulator_v3.gd").new()
	sim.setup_terrain(Enums.TerrainType.PLAINS, Vector2i(10, 10))
	sim.setup_attacker_formations(atk)
	sim.setup_defender_formations(def)
	var lines: PackedStringArray = []
	var cap := mini(sim.max_ticks, 1500)
	for tick in range(cap):
		sim.simulate_tick()
		if tick % 10 == 0 or sim.is_finished:
			lines.append(_fingerprint_v3(sim, tick))
		if sim.is_finished:
			break
	return "\n".join(lines)

func _fingerprint_v3(sim, tick: int) -> String:
	var parts: PackedStringArray = ["t%d" % tick]
	for arr in [sim.attacker_formations, sim.defender_formations]:
		for f in arr:
			parts.append("%s|%.1f,%.1f|%d|%d|%.3f" % [f.instance_id, f.position.x, f.position.y, f.entities_alive, f.current_hp, f.current_morale])
	return ";".join(parts)
