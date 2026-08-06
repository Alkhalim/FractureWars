extends SceneTree
## Task R1 (Unit Stat Rescale): print-mode sweep tool.
##
## The designer ordered every combat-scale unit number ÷10 for readability
## (attack 70→7, max_hp 3750→375). This tool inventories every DIVIDE-
## classified field found by the R1 audit (see the report at
## docs/.../2026-08-06-unit-stat-rescale/task-R1-report.md) and prints what
## `round(old/10.0)`, floored to 1 for any genuinely-nonzero old value,
## would produce -- so a future apply pass has reviewed, provenance-tracked
## numbers to work from. PRINT MODE ONLY THIS TASK: writes nothing to disk.
## An `apply` mode is deliberately NOT implemented here -- R2 adds it once
## the DECIDE-list floor/formula questions in the R1 report are resolved
## (several of those floors live in battle_simulator_v2/v3.gd code, not
## data, and are out of a data-sweep tool's reach regardless).
##
## Modeled on tests/tools_cost_sweep.gd's provenance conventions: deterministic
## file walk, CSV to stdout, CRLF-safe regexes (no trailing `$` anchor -- see
## that file's header comment for the full reasoning, reused verbatim here).
##
## Scope (DIVIDE-classified fields; KEEP/DECIDE fields are catalogued in the
## report but intentionally not swept by this tool):
##   UnitData (data/units/**/*.tres):
##     max_hp, attack, melee_defense, projectile_defense, magic_defense,
##     hp_per_soldier, armor_aura (int, flat defense-aura), healing_aura
##     (float, flat HP/tick heal-aura), vs_attack_bonuses{tag:N},
##     vs_defense_bonuses{tag:N}
##   BuildingData (data/buildings/*.tres) special_effects:
##     flying_unit_attack_bonus, army_attack_bonus -- the only two combat-FLAT
##     (non-_pct) special_effects keys found anywhere in building data (see
##     report; special_effects.defense_bonus/`defense_bonus` field feed the
##     battle terrain-wall generator, a tile-count/geometry knob, NOT a unit
##     stat -- intentionally NOT swept).
##
## Usage (headless, print only):
##   godot --headless -s res://tests/tools_rescale_units.gd
##
## NOTE -- min-1 flooring collapses small multi-value ranges: vs_attack_bonuses
## values of 2, 3, 4, 5 all round to 0 under round(x/10.0) and get floored
## back up to 1, so e.g. {"cavalry": 2} and {"monster": 5} both become 1 --
## differentiation between a "minor" and a "major" hard-counter bonus is lost
## under the literal brief formula. Flagged as a DECIDE item in the R1
## report; this tool intentionally implements the literal formula as
## specified without editorializing the values.

const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"

const SCALAR_FIELDS := ["max_hp", "attack", "melee_defense", "projectile_defense", "magic_defense", "hp_per_soldier", "armor_aura"]
const DICT_FIELDS := ["vs_attack_bonuses", "vs_defense_bonuses"]
const BUILDING_FLAT_KEYS := ["flying_unit_attack_bonus", "army_attack_bonus"]

func _init() -> void:
	var unit_files := _collect_files(UNITS_DIR)
	var building_files := _collect_files(BUILDINGS_DIR)

	print("id,field,old,new")
	var n_rows := 0
	for path in unit_files:
		n_rows += _sweep_unit_file(path)
	for path in building_files:
		n_rows += _sweep_building_file(path)

	printerr("Swept %d value(s) across %d unit file(s) + %d building file(s) -- print mode, nothing written" % [
		n_rows, unit_files.size(), building_files.size(),
	])
	quit(0)

## Recursively collects every `.tres` path under `dir_path` (units live one
## sub-folder deep per faction; buildings are flat -- this handles both,
## verbatim from tools_cost_sweep.gd).
func _collect_files(dir_path: String) -> Array:
	var out: Array = []
	_collect_files_recursive(dir_path, out)
	out.sort()
	return out

func _collect_files_recursive(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("Could not open dir %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full := dir_path + "/" + fname
			if dir.current_is_dir():
				_collect_files_recursive(full, out)
			elif fname.ends_with(".tres"):
				out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()

func _extract_id(text: String) -> String:
	var re := RegEx.new()
	re.compile("(?m)^id = &\"([^\"]*)\"") # no trailing `$` -- see tools_cost_sweep.gd
	var m := re.search(text)
	return m.get_string(1) if m != null else "?"

## round(old/10.0), sign-preserving, floored to magnitude 1 if a genuinely
## nonzero old value would otherwise round to 0 (a silent 0 would delete the
## field's whole effect -- see the module doc's min-1 note).
func _rescale_int(old: int) -> int:
	if old == 0:
		return 0
	var mag := int(round(absf(float(old)) / 10.0))
	mag = maxi(1, mag)
	return mag if old > 0 else -mag

func _fmt_float(v: float) -> String:
	# Trim trailing zeros but keep at least one decimal place for CSV readability.
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s += "0"
	return s

func _sweep_unit_file(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return 0
	var text := f.get_as_text()
	f.close()
	var id := _extract_id(text)
	var count := 0

	for field in SCALAR_FIELDS:
		var re := RegEx.new()
		re.compile("(?m)^%s = (-?[0-9]+)" % field)
		var m := re.search(text)
		if m == null:
			continue # Field absent = at GDScript class default (never a combat value worth sweeping)
		var old_val := int(m.get_string(1))
		if old_val == 0:
			continue
		var new_val := _rescale_int(old_val)
		print("%s,%s,%d,%d" % [id, field, old_val, new_val])
		count += 1

	# healing_aura is a float field (HP/tick heal-aura) -- same ÷10 rescale,
	# no min-1 floor needed since it's continuous (0.1 is a valid nonzero heal).
	var hre := RegEx.new()
	hre.compile("(?m)^healing_aura = ([0-9.]+)")
	var hm := hre.search(text)
	if hm != null:
		var old_h := float(hm.get_string(1))
		if old_h != 0.0:
			var new_h := old_h / 10.0
			print("%s,healing_aura,%s,%s" % [id, _fmt_float(old_h), _fmt_float(new_h)])
			count += 1

	for field in DICT_FIELDS:
		var dre := RegEx.new()
		dre.compile("(?m)^%s = \\{([^}]*)\\}" % field) # closing `}` alone unambiguously ends the dict
		var dm := dre.search(text)
		if dm == null:
			continue
		var body := dm.get_string(1).strip_edges()
		if body == "":
			continue
		for entry in body.split(","):
			var parts := entry.split(":")
			if parts.size() != 2:
				printerr("Unparseable %s entry '%s' in %s" % [field, entry, path])
				continue
			var tag := parts[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var old_val := int(parts[1].strip_edges())
			if old_val == 0:
				continue
			var new_val := _rescale_int(old_val)
			print("%s,%s:%s,%d,%d" % [id, field, tag, old_val, new_val])
			count += 1

	return count

func _sweep_building_file(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return 0
	var text := f.get_as_text()
	f.close()
	var id := _extract_id(text)
	var count := 0
	for key in BUILDING_FLAT_KEYS:
		var re := RegEx.new()
		re.compile("\"%s\":\\s*(-?[0-9]+)" % key)
		var m := re.search(text)
		if m == null:
			continue
		var old_val := int(m.get_string(1))
		if old_val == 0:
			continue
		var new_val := _rescale_int(old_val)
		print("%s,special_effects:%s,%d,%d" % [id, key, old_val, new_val])
		count += 1
	return count
