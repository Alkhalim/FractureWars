extends SceneTree
## Task R1/R2 (Unit Stat Rescale): unit + building data sweep tool.
##
## R1 built this as PRINT-mode only (see the git history / task-R1-report.md
## for the original design rationale: deterministic file walk, CRLF-safe
## regexes, CSV to stdout). R2 adds an APPLY mode (`-- --apply`) that WRITES
## the computed new values back into the .tres files, and corrects the
## formula for `armor_aura`/`vs_attack_bonuses`/`vs_defense_bonuses`: R1's
## PRINT-mode used a literal `round(old/10.0)` min-1 divide for these three
## (same as the core stats); R2's design (task-R2-report.md, amendment B)
## found that divide-and-round fails the <25% relative-error bar for every
## value 1-8 these fields actually use, so they now convert to a PERSONALIZED
## PERCENTAGE instead: `pct = round(old_bonus / this_unit's_OWN_old_attack_or_
## melee_defense * 100)`, stored as a plain int (percentage points, consumed
## via `roundi(f.attack * pct / 100.0)` at the battle_simulator_v3.gd call
## sites -- see that file's doc comments above _create_formation).
## `healing_aura` (float, HP/tick heal-aura) stays a straight ÷10.0 divide,
## no pct conversion (see task-R2-report.md's healing_aura section -- the
## rescale-relevant fix for that field is a consumption-site floor, not a
## data-side change).
##
## Order of operations (apply mode): every OLD value (own attack, own
## melee_defense, per-tag bonus amounts) is read from the ORIGINAL file text
## BEFORE any field is mutated, so the vs_attack_bonuses/vs_defense_bonuses/
## armor_aura ratio bases are never computed against an already-divided
## number.
##
## Usage (headless):
##   Print (no writes, default):  godot --headless -s res://tests/tools_rescale_units.gd
##   Apply (writes .tres files):  godot --headless -s res://tests/tools_rescale_units.gd -- --apply

const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"

# Same empirical roster reference used by battle_simulator_v3.gd's
# _atk_pct/_def_pct helpers (see task-R2-report.md for the derivation: mean
# attack 67.76/median 60 -> 70; mean melee_defense 35.47/median 25 -> 30).
const RESCALE_REF_ATTACK := 70.0

const DIVIDE_SCALAR_FIELDS := ["max_hp", "attack", "melee_defense", "projectile_defense", "magic_defense", "hp_per_soldier"]
const BUILDING_FLAT_KEYS := ["flying_unit_attack_bonus", "army_attack_bonus"]

func _init() -> void:
	var apply_mode := "--apply" in OS.get_cmdline_user_args()
	var unit_files := _collect_files(UNITS_DIR)
	var building_files := _collect_files(BUILDINGS_DIR)

	if not apply_mode:
		print("id,field,old,new")
	var n_rows := 0
	var n_units_written := 0
	var n_buildings_written := 0
	for path in unit_files:
		var res := _process_unit_file(path, apply_mode)
		n_rows += res[0]
		if apply_mode and res[0] > 0:
			n_units_written += 1
	for path in building_files:
		var res := _process_building_file(path, apply_mode)
		n_rows += res[0]
		if apply_mode and res[0] > 0:
			n_buildings_written += 1

	if apply_mode:
		printerr("APPLY: swept %d value(s), wrote %d unit file(s) + %d building file(s)" % [
			n_rows, n_units_written, n_buildings_written,
		])
	else:
		printerr("Swept %d value(s) across %d unit file(s) + %d building file(s) -- print mode, nothing written" % [
			n_rows, unit_files.size(), building_files.size(),
		])
	quit(0)

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
## nonzero old value would otherwise round to 0.
func _rescale_int(old: int) -> int:
	if old == 0:
		return 0
	var mag := int(round(absf(float(old)) / 10.0))
	mag = maxi(1, mag)
	return mag if old > 0 else -mag

## Personalized percent: round(old_flat / ref_stat * 100), sign-preserving,
## floored to magnitude 1 if a genuinely nonzero old_flat would otherwise
## round to 0 (a silent 0% would delete the field's whole effect, same
## min-1 concern as _rescale_int).
func _personalized_pct(old_flat: int, ref_stat: int) -> int:
	if old_flat == 0:
		return 0
	if ref_stat <= 0:
		# Defensive fallback: no valid own-stat ratio base found (shouldn't
		# happen for real unit data -- every combat unit has positive attack
		# and melee_defense -- but never divide by zero).
		ref_stat = int(RESCALE_REF_ATTACK)
	var mag := int(round(absf(float(old_flat)) / float(ref_stat) * 100.0))
	mag = maxi(1, mag)
	return mag if old_flat > 0 else -mag

## Global-reference percent: round(old_flat / RESCALE_REF_ATTACK * 100),
## same min-1 floor convention (used for building special_effects, which
## apply broadly across many different units, so there's no single "own
## attack" to personalize against -- see battle_simulator_v3.gd's
## _atk_pct doc comment for the parallel code-side helper).
func _global_ref_pct(old_flat: int) -> int:
	if old_flat == 0:
		return 0
	var mag := int(round(absf(float(old_flat)) / RESCALE_REF_ATTACK * 100.0))
	mag = maxi(1, mag)
	return mag if old_flat > 0 else -mag

func _fmt_float(v: float) -> String:
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s += "0"
	return s

## Returns [rows_changed]. In apply mode, also writes the file.
func _process_unit_file(path: String, apply_mode: bool) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return [0]
	var text := f.get_as_text()
	f.close()
	var id := _extract_id(text)
	var count := 0

	# Read every OLD scalar value BEFORE any mutation -- armor_aura/
	# vs_attack_bonuses/vs_defense_bonuses need the OWN old attack/
	# melee_defense as their ratio base.
	var old_scalars := {}
	for field in DIVIDE_SCALAR_FIELDS:
		var re := RegEx.new()
		re.compile("(?m)^%s = (-?[0-9]+)" % field)
		var m := re.search(text)
		if m != null:
			old_scalars[field] = int(m.get_string(1))
	var old_attack: int = old_scalars.get("attack", 0)
	var old_melee_defense: int = old_scalars.get("melee_defense", 0)

	# ── Core scalar stats: straight divide ──
	for field in DIVIDE_SCALAR_FIELDS:
		if not old_scalars.has(field):
			continue # Field absent = at GDScript class default, never swept
		var old_val: int = old_scalars[field]
		if old_val == 0:
			continue
		var new_val := _rescale_int(old_val)
		count += 1
		if apply_mode:
			text = _replace_scalar_field(text, field, old_val, new_val)
		else:
			print("%s,%s,%d,%d" % [id, field, old_val, new_val])

	# ── armor_aura: personalized percent of this unit's OWN old melee_defense ──
	var are := RegEx.new()
	are.compile("(?m)^armor_aura = (-?[0-9]+)")
	var am := are.search(text)
	if am != null:
		var old_aa := int(am.get_string(1))
		if old_aa != 0:
			var new_aa := _personalized_pct(old_aa, old_melee_defense)
			count += 1
			if apply_mode:
				text = _replace_scalar_field(text, "armor_aura", old_aa, new_aa)
			else:
				print("%s,armor_aura,%d,%d%%" % [id, old_aa, new_aa])

	# ── healing_aura: float, straight ÷10.0 divide, no min-1 floor (continuous rate) ──
	var hre := RegEx.new()
	hre.compile("(?m)^healing_aura = ([0-9.]+)")
	var hm := hre.search(text)
	if hm != null:
		var old_h := float(hm.get_string(1))
		if old_h != 0.0:
			var new_h := old_h / 10.0
			count += 1
			if apply_mode:
				var old_full := hm.get_string(0)
				var new_full := "healing_aura = %s" % _fmt_float(new_h)
				text = text.replace(old_full, new_full)
			else:
				print("%s,healing_aura,%s,%s" % [id, _fmt_float(old_h), _fmt_float(new_h)])

	# ── vs_attack_bonuses / vs_defense_bonuses: personalized percent ──
	# (GDScript lambdas capture locals by value, not by reference, so
	# _process_dict_field_text returns the mutated text explicitly instead
	# of writing through a closure.)
	var vab := _process_dict_field_text(text, id, "vs_attack_bonuses", old_attack, apply_mode)
	text = vab[0]
	count += vab[1]
	var vdb := _process_dict_field_text(text, id, "vs_defense_bonuses", old_melee_defense, apply_mode)
	text = vdb[0]
	count += vdb[1]

	if apply_mode and count > 0:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			printerr("Could not open %s for writing" % path)
			return [0]
		wf.store_string(text)
		wf.close()

	return [count]

## Returns [new_text, rows_changed].
func _process_dict_field_text(text: String, id: String, field: String, ref_stat: int, apply_mode: bool) -> Array:
	var dre := RegEx.new()
	dre.compile("(?m)^%s = \\{([^}]*)\\}" % field) # closing `}` alone unambiguously ends the dict
	var dm := dre.search(text)
	if dm == null:
		return [text, 0]
	var body := dm.get_string(1).strip_edges()
	if body == "":
		return [text, 0]
	var count := 0
	var new_entries: Array[String] = []
	for entry in body.split(","):
		var parts := entry.split(":")
		if parts.size() != 2:
			printerr("Unparseable %s entry '%s' in id=%s" % [field, entry, id])
			continue
		var tag := parts[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
		var old_val := int(parts[1].strip_edges())
		if old_val == 0:
			new_entries.append("\"%s\": %d" % [tag, old_val])
			continue
		var new_val := _personalized_pct(old_val, ref_stat)
		count += 1
		new_entries.append("\"%s\": %d" % [tag, new_val])
		if not apply_mode:
			print("%s,%s:%s,%d,%d%%" % [id, field, tag, old_val, new_val])
	if apply_mode and count > 0:
		var old_full := dm.get_string(0)
		var new_full := "%s = {%s}" % [field, ", ".join(new_entries)]
		text = text.replace(old_full, new_full)
	return [text, count]

func _replace_scalar_field(text: String, field: String, old_val: int, new_val: int) -> String:
	var re := RegEx.new()
	re.compile("(?m)^%s = %d$" % [field, old_val])
	var m := re.search(text)
	if m == null:
		# Fallback: value may not be alone on its logical line end in some
		# edge case (shouldn't happen for these fields, but never silently
		# skip a write) -- try without the end anchor.
		re.compile("(?m)^%s = %d" % [field, old_val])
		m = re.search(text)
	if m == null:
		printerr("Could not locate '%s = %d' to replace" % [field, old_val])
		return text
	var old_full := m.get_string(0)
	var new_full := "%s = %d" % [field, new_val]
	return text.replace(old_full, new_full)

func _process_building_file(path: String, apply_mode: bool) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return [0]
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
		var new_val := _global_ref_pct(old_val)
		count += 1
		if apply_mode:
			var old_full := m.get_string(0)
			var new_full := "\"%s\": %d" % [key, new_val]
			text = text.replace(old_full, new_full)
		else:
			print("%s,special_effects:%s,%d,%d%%" % [id, key, old_val, new_val])
	if apply_mode and count > 0:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			printerr("Could not open %s for writing" % path)
			return [0]
		wf.store_string(text)
		wf.close()
	return [count]
