extends SceneTree
## Task D (Playtest Round 2): global cost rebalance sweep.
## Buildings/settlements are the expensive, protected thing; units are the
## cheap, replaceable thing (design rationale: losing your one army shouldn't
## end the run the way losing your capital should). This one-off, deterministic
## tool applies that ratio uniformly:
##   - every data/buildings/*.tres `build_cost` value  x1.5, ceil
##   - every data/units/**/*.tres `recruit_cost` value x0.5, ceil, min 1
## `upkeep_cost` (both) and all non-cost dilemma/mechanic numbers are untouched
## -- this tool only ever rewrites the single `build_cost = {...}` /
## `recruit_cost = {...}` line already present in each .tres file's text.
## Settlement-founding cost (CitySystem.SETTLEMENT_FOUNDING_COST, a GDScript
## constant, not a .tres) is handled separately by hand -- out of scope here.
##
## Usage (headless, run from the project root):
##   godot --headless -s res://tests/tools_cost_sweep.gd -- print
##   godot --headless -s res://tests/tools_cost_sweep.gd -- apply
## print (default if no arg given): dumps a CSV `id,field,resource,old,new` to
## stdout for review, writes NOTHING to disk. apply: rewrites the .tres files.
## Committed for provenance.
##
## WARNING -- NOT IDEMPOTENT (review-verified 2026-08-01): the tool has no
## memory of having run; every `apply` multiplies the CURRENT values again.
## Running apply a second time on an already-swept tree double-sweeps
## (x2.25 buildings / x0.25 units). The x1.5/x0.5 sweep for the 2026-08-01
## rebalance has ALREADY BEEN APPLIED (commit 5778993) -- do not re-run
## `apply` unless you intend a fresh multiplication on top of current data.

const BUILDING_MULT := 1.5
const UNIT_MULT := 0.5
const BUILDINGS_DIR := "res://data/buildings"
const UNITS_DIR := "res://data/units"

## ResourceType enum (scripts/core/enums.gd) mirrored here only for CSV
## readability -- the sweep itself works on raw int keys, so a future new
## resource type needs no change here.
const RESOURCE_NAMES := {
	0: "GOLD", 1: "IRON", 2: "TECH", 3: "FOOD", 4: "SHARD", 5: "WOOD", 6: "CAPTIVES",
}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "print"
	if mode != "print" and mode != "apply":
		printerr("Unknown mode '%s' -- use 'print' or 'apply'" % mode)
		quit(1)
		return

	var building_files := _collect_files(BUILDINGS_DIR)
	var unit_files := _collect_files(UNITS_DIR)

	print("id,field,resource,old,new")
	var n_building_vals := 0
	var n_unit_vals := 0
	for path in building_files:
		n_building_vals += _sweep_file(path, "build_cost", BUILDING_MULT, mode)
	for path in unit_files:
		n_unit_vals += _sweep_file(path, "recruit_cost", UNIT_MULT, mode)

	printerr("Swept %d build_cost value(s) across %d building file(s), %d recruit_cost value(s) across %d unit file(s) (mode=%s)" % [
		n_building_vals, building_files.size(), n_unit_vals, unit_files.size(), mode,
	])
	quit(0)

## Recursively collects every `.tres` path under `dir_path` (units live one
## sub-folder deep per faction; buildings are flat -- this handles both).
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

## Inspects (print mode) or rewrites (apply mode) the single `<field> = {...}`
## line in `path`. Returns the number of resource-value entries swept (0 for
## a file with an empty/absent dict -- e.g. non-recruitable "independent"
## units -- which is never treated as an error).
func _sweep_file(path: String, field: String, mult: float, mode: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return 0
	var text := f.get_as_text()
	f.close()

	var id := _extract_id(text)
	var re := RegEx.new()
	# No trailing `$` anchor: most original data files are CRLF-terminated, and
	# PCRE's (?m) `$` matches only immediately before a bare `\n`, so a `\r`
	# between `}` and the newline would silently fail every match. The closing
	# `}` alone unambiguously ends the dict (cost values never nest), so this
	# is unambiguous without anchoring the far end -- and it leaves whatever
	# line terminator follows (`\n` or `\r\n`) completely untouched.
	re.compile("(?m)^%s = \\{([^}]*)\\}" % field)
	var m := re.search(text)
	if m == null:
		printerr("No `%s = {...}` line found in %s" % [field, path])
		return 0

	var dict := _parse_dict(m.get_string(1))
	if dict.is_empty():
		return 0

	var new_dict := {}
	var count := 0
	# Deterministic key order (ascending ResourceType) regardless of the
	# dict's original insertion order, so print/apply output is stable.
	var keys: Array = dict.keys()
	keys.sort()
	for key in keys:
		var old_val: int = dict[key]
		var new_val: int = maxi(1, int(ceil(old_val * mult)))
		new_dict[key] = new_val
		var res_name: String = RESOURCE_NAMES.get(key, str(key))
		print("%s,%s,%s,%d,%d" % [id, field, res_name, old_val, new_val])
		count += 1

	if mode == "apply":
		var new_line := "%s = {%s}" % [field, _format_dict(new_dict)]
		var start := m.get_start()
		var end := m.get_end()
		var new_text := text.substr(0, start) + new_line + text.substr(end)
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			printerr("Could not open %s for writing" % path)
			return count
		wf.store_string(new_text)
		wf.close()

	return count

func _extract_id(text: String) -> String:
	var re := RegEx.new()
	re.compile("(?m)^id = &\"([^\"]*)\"") # same no-trailing-`$` reasoning as above
	var m := re.search(text)
	return m.get_string(1) if m != null else "?"

## Parses a flat `0: 20, 5: 46` dict body (no nested structures ever appear
## in build_cost/recruit_cost data) into {int: int}.
func _parse_dict(body: String) -> Dictionary:
	var out := {}
	var trimmed := body.strip_edges()
	if trimmed == "":
		return out
	for entry in trimmed.split(","):
		var parts := entry.split(":")
		if parts.size() != 2:
			printerr("Unparseable cost entry '%s' in body '%s'" % [entry, body])
			continue
		out[int(parts[0].strip_edges())] = int(parts[1].strip_edges())
	return out

func _format_dict(d: Dictionary) -> String:
	var parts: Array = []
	for key in d:
		parts.append("%d: %d" % [key, d[key]])
	return ", ".join(parts)
