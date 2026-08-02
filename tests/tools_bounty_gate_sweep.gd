extends SceneTree
## Task 3 (bounty-gated techs): one-off data sweep applying the approved
## 30-tech gate list (design brief `.superpowers/sdd/2026-08-01-bounty-gated-
## techs/task-3-brief.md`) to their `.tres` files.
##
## Model: `tests/tools_cost_sweep.gd` -- same "text surgery on the .tres
## content" approach. Unlike that tool this one INSERTS a brand-new line
## (there is no existing `requires_bounty_types = ...` line in any of these
## files yet) rather than only rewriting an existing one, so it locates the
## `prerequisites = Array[StringName]([...])` line via regex and splices a
## `requires_bounty_types = Array[StringName]([...])` line in immediately
## after it. If a `requires_bounty_types` line already exists (e.g. a re-run,
## or manual editing since) it replaces that line's content instead of
## inserting a duplicate -- so `apply` is idempotent for this fixed table.
##
## Usage (headless, run from repo root):
##   godot --headless --path . -s res://tests/tools_bounty_gate_sweep.gd -- print
##   godot --headless --path . -s res://tests/tools_bounty_gate_sweep.gd -- apply
## print (default if no arg given): dumps CSV `id,faction,tier,types` to
## stdout for review, writes NOTHING to disk. apply: rewrites the .tres files.
##
## Design-rule guard (non-negotiable, never bypassed even in `apply` mode):
## refuses (prints + skips, no write) any entry whose tier is 1, or whose
## gate type id is missing from `BountySystem.BOUNTY_TYPES`.
##
## Committed for provenance. This is a one-off tied to the exact table below
## -- do not repurpose for a future gate table without review.

const GATES := {
	&"sk_horse_lords": [&"wild_horses"],
	&"sk_leather_works": [&"furs"],
	&"great_yurt": [&"bone_fields"],
	&"sb_dawn_cavalry": [&"wild_horses"],
	&"oasis_blessing": [&"salt_flats"],
	&"sb_sun_forging": [&"bronze_ore"],
	&"ms_lunar_knights": [&"wild_horses"],
	&"ms_silver_mines": [&"copper_vein"],
	&"adamantine_forge": [&"titanstone_quarry"],
	&"cg_master_alloys": [&"bronze_ore", &"copper_vein"],
	&"volcanic_glass": [&"obsidian_flows"],
	&"cg_war_forges": [&"coal_seams"],
	&"emp_war_machines": [&"titanstone_quarry"],
	&"emp_aqueducts": [&"orchards"],
	&"road_network": [&"granite"],
	&"emp_harbor_cities": [&"fisheries"],
	&"gh_herb_gardens": [&"herb_meadows"],
	&"gh_root_bridges": [&"timber_giants"],
	&"gh_forest_trade": [&"amber_groves"],
	&"mining_expertise": [&"copper_vein"],
	&"ts_deep_mines": [&"granite"],
	&"storm_forge": [&"coal_seams"],
	&"iv_stone_masons": [&"marble"],
	&"ossuary_guards": [&"bone_fields"],
	&"fk_corpse_labor": [&"bone_fields"],
	&"fk_bone_walls": [&"basalt_columns"],
	&"jungle_pharmacy": [&"herb_meadows"],
	&"tj_mushroom_farms": [&"peat_bogs"],
	&"venomcraft": [&"dye_gardens"],
	&"sh_shard_miners": [&"crystal_springs"],
}

var _dm: Node

func _init() -> void:
	# Autoloads aren't attached under /root yet during _init() of a -s main
	# script (same reason tests/probe_autoloads.gd and every other tool/test
	# in this suite defer their real work) -- so fetch them, deferred, via
	# root.get_node the same way the rest of the suite does (a bare
	# `DataManager` identifier does NOT resolve in a SceneTree main script,
	# confirmed empirically: it's an autoload singleton, unlike BountySystem
	# which is a plain `class_name` static class and needs no lookup at all).
	call_deferred("_run")

func _run() -> void:
	_dm = root.get_node("/root/DataManager")

	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "print"
	if mode != "print" and mode != "apply":
		printerr("Unknown mode '%s' -- use 'print' or 'apply'" % mode)
		quit(1)
		return

	print("id,faction,tier,types")
	var n_applied := 0
	var n_skipped := 0
	# Deterministic order regardless of dict insertion/hash order.
	var ids: Array = GATES.keys()
	ids.sort()
	for id in ids:
		if _sweep_one(id, GATES[id], mode):
			n_applied += 1
		else:
			n_skipped += 1

	printerr("Swept %d gate(s), skipped %d (mode=%s)" % [n_applied, n_skipped, mode])
	quit(0 if n_skipped == 0 else 1)

## Returns true if the entry was valid and (in apply mode) written; false if
## refused/skipped for any reason. Always prints exactly one line: either a
## CSV data row (valid) or a "REFUSED"/error line to stderr (invalid).
func _sweep_one(id: StringName, types: Array, mode: String) -> bool:
	var data: ResearchData = _dm.research.get(id)
	if data == null:
		printerr("REFUSED %s: not found in DataManager.research" % id)
		return false

	# Hard design rule: never gate a tier-1 tech.
	if data.tier <= 1:
		printerr("REFUSED %s: tier %d (tier-1 techs may never be bounty-gated)" % [id, data.tier])
		return false

	# Every gate type must be a real bounty type.
	for type_id in types:
		if not BountySystem.BOUNTY_TYPES.has(type_id):
			printerr("REFUSED %s: gate type %s is not in BountySystem.BOUNTY_TYPES" % [id, type_id])
			return false

	var path: String = data.resource_path
	if path == "":
		printerr("REFUSED %s: no resource_path on loaded ResearchData" % id)
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("REFUSED %s: could not open %s for reading" % [id, path])
		return false
	var text := f.get_as_text()
	f.close()

	# Preserve whatever line terminator this file already uses.
	var eol := "\r\n" if text.find("\r\n") != -1 else "\n"

	var type_strs: Array = []
	for type_id in types:
		type_strs.append("&\"%s\"" % type_id)
	var new_line := "requires_bounty_types = Array[StringName]([%s])" % ", ".join(type_strs)

	var new_text: String
	var existing_re := RegEx.new()
	existing_re.compile("(?m)^requires_bounty_types = Array\\[StringName\\]\\(\\[[^\\]]*\\]\\)")
	var existing_match := existing_re.search(text)
	if existing_match != null:
		# Replace-in-place: line already present (e.g. a prior sweep run).
		new_text = text.substr(0, existing_match.get_start()) + new_line + text.substr(existing_match.get_end())
	else:
		# Insert immediately after the `prerequisites` line. No trailing `$`
		# anchor: the closing `])` unambiguously ends the line without
		# needing to anchor past a possible `\r` (same reasoning as
		# tools_cost_sweep.gd's build_cost/recruit_cost regex).
		var prereq_re := RegEx.new()
		prereq_re.compile("(?m)^prerequisites = Array\\[StringName\\]\\(\\[[^\\]]*\\]\\)")
		var prereq_match := prereq_re.search(text)
		if prereq_match == null:
			printerr("REFUSED %s: no `prerequisites` line found in %s" % [id, path])
			return false
		var insert_at := prereq_match.get_end()
		new_text = text.substr(0, insert_at) + eol + new_line + text.substr(insert_at)

	var type_names: Array = []
	for type_id in types:
		type_names.append(String(type_id))
	print("%s,%s,%d,%s" % [id, data.faction_id, data.tier, "|".join(type_names)])

	if mode == "apply":
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			printerr("REFUSED %s: could not open %s for writing" % [id, path])
			return false
		wf.store_string(new_text)
		wf.close()

	return true
