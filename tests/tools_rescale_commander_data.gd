extends SceneTree
## Task R2 (Unit Stat Rescale): commander/research data sweep tool.
##
## Companion to tools_rescale_units.gd (units + buildings). Covers the other
## DIVIDE-classified flat combat sources R1 inventoried (task-R1-report.md
## §1.3-1.4): data/skills, data/items, data/traits, data/followers (all flat
## `army_attack_bonus`/`army_defense_bonus`/tag-conditional/`vs_X`-conditional
## keys inside an `effects` or `bonus_effect`/`malus_effect` dict), and
## data/research (`unit_ranged_bonus`, `siege_bonus`, `enemy_defense_penalty`
## inside an `effects` dict -- every other research effect key is already a
## percentage or an unrelated scale, left untouched).
##
## Conversion: GLOBAL-REFERENCE PERCENT (not personalized) -- these bonuses
## apply broadly across many different units with different own stats (a
## commander skill isn't tied to one specific unit's .tres file the way
## UnitData.vs_attack_bonuses is), so there's no single "this unit's own
## attack" to ratio against at data-sweep time. Same empirical roster
## reference as battle_simulator_v3.gd's _atk_pct/_def_pct helpers and
## tools_rescale_units.gd's building sweep: RESCALE_REF_ATTACK=70 for every
## `*_attack_bonus` key (+ siege_bonus/unit_ranged_bonus, both consumed
## against each unit's own f.attack at the battle_simulator_v3.gd call
## sites -- see that file's doc comments), RESCALE_REF_DEFENSE=30 for every
## `*_defense_bonus` key (+ enemy_defense_penalty, consumed PERSONALIZED per
## enemy formation at _apply_research_enemy_penalties -- see that function's
## doc comment).
##
## `heal_per_turn` is the one deliberate EXCEPTION (task-R2-report.md):
## treated as an HP-scale absolute number like max_hp, not a bonus ratio --
## straight `roundi(old / 10.0)`, WITHOUT a min-1 floor (legitimate 0 for old
## values 1-4 is acceptable; it rides on top of a nonzero
## `int(max_hp*0.15*mult)` baseline at the turn_manager.gd consumption site,
## so the mechanic doesn't fully die, and it's a per-TURN not per-tick cost
## so the loss is far less frequent than the healing_aura case).
##
## Excluded as DEAD DATA (found this task, not previously flagged by R1):
## `city_defense_bonus` (R1-confirmed dead -- city_system.gd's
## _get_commander_defense_bonus() has no callers) and
## `magic_defense_bonus`/`projectile_defense_bonus` (accumulated into
## commander_system.gd's bonuses dict via the generic "*_defense_bonus"
## catch-all, but never read downstream -- no unit tag is literally "magic"
## or "projectile", so the tag-conditional consumption loop in
## battle_simulator_v3.gd never matches these key names). Left as literal
## small ints, unread either way -- converting them would be needless
## surface area for zero behavior change.
##
## Usage (headless):
##   Print (no writes, default):  godot --headless -s res://tests/tools_rescale_commander_data.gd
##   Apply (writes .tres files):  godot --headless -s res://tests/tools_rescale_commander_data.gd -- --apply

const SKILLS_DIR := "res://data/skills"
const ITEMS_DIR := "res://data/items"
const TRAITS_DIR := "res://data/traits"
const FOLLOWERS_DIR := "res://data/followers"
const RESEARCH_DIR := "res://data/research"

const RESCALE_REF_ATTACK := 70.0
const RESCALE_REF_DEFENSE := 30.0

# key -> "atk" | "def" | "heal" (heal_per_turn: linear /10, no floor, no pct)
const COMMANDER_KEYS := {
	"army_attack_bonus": "atk",
	"army_defense_bonus": "def",
	"ambush_attack_bonus": "atk",
	"beast_attack_bonus": "atk",
	"cavalry_attack_bonus": "atk",
	"infantry_defense_bonus": "def",
	"mage_attack_bonus": "atk",
	"terrain_desert_attack_bonus": "atk",
	"terrain_desert_defense_bonus": "def",
	"terrain_forest_attack_bonus": "atk",
	"terrain_forest_defense_bonus": "def",
	"terrain_jungle_attack_bonus": "atk",
	"vs_beast_attack_bonus": "atk",
	"vs_beast_defense_bonus": "def",
	"vs_cavalry_defense_bonus": "def",
	"vs_monster_attack_bonus": "atk",
	"vs_monster_defense_bonus": "def",
	"heal_per_turn": "heal",
	# Deliberately excluded (dead data, see module doc): city_defense_bonus,
	# magic_defense_bonus, projectile_defense_bonus.
}

const RESEARCH_KEYS := {
	"unit_ranged_bonus": "atk",
	"siege_bonus": "atk",
	"enemy_defense_penalty": "def",
}

var _n_rows := 0
var _n_files_written := 0

func _init() -> void:
	var apply_mode := "--apply" in OS.get_cmdline_user_args()
	if not apply_mode:
		print("source,id,field,key,old,new")

	for pair in [["skill", SKILLS_DIR, ["effects"]], ["item", ITEMS_DIR, ["effects"]],
			["trait", TRAITS_DIR, ["effects"]], ["follower", FOLLOWERS_DIR, ["bonus_effect", "malus_effect"]]]:
		var label: String = pair[0]
		var dir_path: String = pair[1]
		var fields: Array = pair[2]
		for path in _collect_files(dir_path):
			_process_file(path, label, fields, COMMANDER_KEYS, apply_mode)

	for path in _collect_files(RESEARCH_DIR):
		_process_file(path, "research", ["effects"], RESEARCH_KEYS, apply_mode)

	if apply_mode:
		printerr("APPLY: swept %d value(s), wrote %d file(s)" % [_n_rows, _n_files_written])
	else:
		printerr("Swept %d value(s) -- print mode, nothing written" % [_n_rows])
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
	re.compile("(?m)^id = &\"([^\"]*)\"")
	var m := re.search(text)
	return m.get_string(1) if m != null else "?"

## round(old_flat / ref * 100), sign-preserving, floored to magnitude 1 if a
## genuinely nonzero old_flat would otherwise round to 0.
func _global_ref_pct(old_flat: int, ref: float) -> int:
	if old_flat == 0:
		return 0
	var mag := int(round(absf(float(old_flat)) / ref * 100.0))
	mag = maxi(1, mag)
	return mag if old_flat > 0 else -mag

## heal_per_turn: straight /10 divide, NO min-1 floor (deliberate exception,
## see module doc comment -- legitimate 0 for old values 1-4 is acceptable).
func _heal_divide(old_flat: int) -> int:
	return roundi(float(old_flat) / 10.0)

func _process_file(path: String, source: String, fields: Array, key_map: Dictionary, apply_mode: bool) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open %s" % path)
		return
	var text := f.get_as_text()
	f.close()
	var id := _extract_id(text)
	var file_rows := 0

	for field: String in fields:
		var dre := RegEx.new()
		# Tolerates both `field = {"k": v}` (skills/items/traits/followers)
		# and `field = { "k": v }` (research's extra inner spacing).
		dre.compile("(?m)^%s = \\{([^}]*)\\}" % field)
		var dm := dre.search(text)
		if dm == null:
			continue
		var body := dm.get_string(1).strip_edges()
		if body == "":
			continue
		var entries := _parse_dict_body(body, id, field, path)
		if entries.is_empty():
			continue
		var changed := false
		var new_parts: Array[String] = []
		for entry: Dictionary in entries:
			var key: String = entry["key"]
			var raw_val: String = entry["raw"]
			if not key_map.has(key):
				new_parts.append("\"%s\": %s" % [key, raw_val])
				continue
			var kind: String = key_map[key]
			var old_val := int(raw_val) if _is_int_literal(raw_val) else 0
			var new_val: int
			match kind:
				"atk":
					new_val = _global_ref_pct(old_val, RESCALE_REF_ATTACK)
				"def":
					new_val = _global_ref_pct(old_val, RESCALE_REF_DEFENSE)
				"heal":
					new_val = _heal_divide(old_val)
				_:
					new_val = old_val
			if new_val != old_val:
				changed = true
				file_rows += 1
				var suffix := "%" if kind != "heal" else ""
				if not apply_mode:
					print("%s,%s,%s,%s,%d,%d%s" % [source, id, field, key, old_val, new_val, suffix])
			new_parts.append("\"%s\": %d" % [key, new_val])
		if apply_mode and changed:
			var old_full := dm.get_string(0)
			var new_full := "%s = {%s}" % [field, ", ".join(new_parts)]
			text = text.replace(old_full, new_full)

	_n_rows += file_rows
	if apply_mode and file_rows > 0:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf == null:
			printerr("Could not open %s for writing" % path)
			return
		wf.store_string(text)
		wf.close()
		_n_files_written += 1

func _is_int_literal(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^-?[0-9]+$")
	return re.search(s) != null

## Parses a Godot dict-literal body ("k1": v1, "k2": v2, ...) into
## [{"key": String, "raw": String}, ...]. Values may be ints, floats, or
## other literals (bools, strings) -- non-int values pass through unchanged
## (key_map only ever names int-valued combat keys, so a mismatch here would
## indicate a key-name collision worth flagging, not silent data loss).
func _parse_dict_body(body: String, id: String, field: String, path: String) -> Array:
	var out: Array = []
	for entry in body.split(","):
		var colon_idx := entry.find(":")
		if colon_idx < 0:
			printerr("Unparseable %s entry '%s' in %s (id=%s)" % [field, entry, path, id])
			continue
		var key := entry.substr(0, colon_idx).strip_edges().trim_prefix("\"").trim_suffix("\"")
		var raw := entry.substr(colon_idx + 1).strip_edges()
		out.append({"key": key, "raw": raw})
	return out
