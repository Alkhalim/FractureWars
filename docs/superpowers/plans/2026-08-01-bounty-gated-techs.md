# Bounty-Gated Technologies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ~30 tier-2+ techs each require holding (claim or lease) a map bounty of a given type to START researching — making claiming, conquering, and trading for bounties matter to the tech game — per `docs/bounty_gated_techs_design.md` with all designer decisions locked.

**Architecture:** New `ResearchData.requires_bounty_types` (any-of array) checked at research start only (start-only gate — LOCKED decision; no pause/continuous plumbing). Three new bounty types (`coal_seams`, `bone_fields`, `bronze_ore` — LOCKED) widen the gate vocabulary. Bounty access is tradeable via the existing `RESOURCE_LEASE` treaty with a new terms shape (REQUIRED scope — LOCKED). The AI values gate bounties in settlement placement via a flat scoring bonus (LOCKED). Map-absence fallback: if none of a tech's required types exist anywhere on the map, the tech is researchable at 2× tech cost instead of being dead (design doc §7 default, Option 1+3).

**Tech Stack:** Godot 4.4 GDScript; headless SceneTree tests; windowed screenshot harness for scene scripts.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; run tests `& "<godot>" --headless --path . -s res://tests/<name>.gd`. Startup "SCRIPT ERROR: Compile Error" noise is benign — only printed PASSED/FAILED verdicts count. A test that prints the noise then NOTHING is a runtime crash (look for "Invalid access"), not a compile failure.
- Autoloads in tests via `root.get_node("/root/GameManager")` etc. Every `new_game` call pins the seed: `gm.new_game(&"empire", false, 0)` (0 unless seed variance is the point).
- `tests/test_battle_determinism.gd` must stay FINGERPRINT MATCH after every task. If MATCH breaks, STOP and report — do not regenerate baselines.
- Scene scripts (`campaign_hud.gd`, `campaign.gd`) don't compile headless; verify them with a WINDOWED harness run (no `--headless`) and check stdout has no SCRIPT ERROR naming them.
- All line numbers below were verified 2026-08-01 but drift — re-locate by searching the quoted code before editing.
- `ResearchSystem` is an instance member: call as `GameManager.research_system.foo(...)` (tests: `gm.research_system`). `BountySystem` is all-static: `BountySystem.foo(...)`.
- Save compat: no new state fields are added anywhere in this plan (leases ride the existing `@export` treaty `terms`; the research gate is data-side). Old saves must keep loading — `test_save_roundtrip` runs in the final battery.
- NEVER gate a tier-1 tech (design rule). The sweep verification test enforces this.
- FOREGROUND commands only. Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Three new bounty types

**Files:**
- Modify: `scripts/systems/campaign/bounty_system.gd` (BOUNTY_TYPES dict, lines 20-43)
- Test: `tests/test_bounty_gated_techs.gd` (new file)

**Interfaces:**
- Produces: bounty type ids `&"coal_seams"`, `&"bone_fields"`, `&"bronze_ore"` in `BountySystem.BOUNTY_TYPES` — Task 3's sweep references them; all existing helpers (describe/income_bonus_for_city/recruit_discount_for/scatter) pick them up automatically because they iterate the dict.

- [ ] **Step 1: Write the failing test** — create `tests/test_bounty_gated_techs.gd` modeled on `tests/test_bounty_system.gd` (SceneTree, `_init -> call_deferred("_run")`, `_check(cond, label)` helper, quit(0/1) on PASSED/FAILED print):

```gdscript
extends SceneTree
## Bounty-gated technologies test suite. Task 1 section: the three new
## bounty types added for gate variety (designer directive 2026-08-01).
var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm = root.get_node("/root/GameManager")
	gm.new_game(&"empire", false, 0)
	_run_new_bounty_types_test(gm)
	if _fails == 0:
		print("BOUNTY GATED TECHS TEST PASSED")
		quit(0)
	else:
		print("BOUNTY GATED TECHS TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

func _run_new_bounty_types_test(gm) -> void:
	for tid in [&"coal_seams", &"bone_fields", &"bronze_ore"]:
		_check(BountySystem.BOUNTY_TYPES.has(tid), "%s exists in BOUNTY_TYPES" % tid)
		_check(BountySystem.describe(tid) != "", "%s has a describe() line" % tid)
	# Plant each new type on a tile within CLAIM_RADIUS of a player city and
	# verify the generic pickup paths (income / recruit discount) see it.
	var player_id: StringName = gm.state.player_faction_id
	var fs = gm.state.faction_states[player_id]
	var city: CityState = gm.state.cities.get(fs.owned_cities[0])
	var map = gm.state.hex_map
	# Three distinct neighbor tiles of the city (all within CLAIM_RADIUS=2)
	var spots: Array[Vector2i] = []
	for coord in map.tiles:
		if spots.size() >= 3:
			break
		var d: int = maxi(absi(coord.x - city.hex_pos.x), absi(coord.y - city.hex_pos.y))
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"" and t.special_id == &"" and t.landmark_id == &"":
			spots.append(coord)
	_check(spots.size() == 3, "found 3 clean tiles near the capital (got %d)" % spots.size())
	if spots.size() < 3:
		return
	map.get_tile(spots[0]).bounty_id = &"coal_seams"
	map.get_tile(spots[1]).bounty_id = &"bronze_ore"
	map.get_tile(spots[2]).bounty_id = &"bone_fields"
	var income: Dictionary = BountySystem.income_bonus_for_city(city)
	_check(income.get(1, 0) >= 6 + 4, "coal_seams+bronze_ore iron income sums (got %s)" % [income])
	_check(income.get(0, 0) >= 3, "bronze_ore gold income counted (got %s)" % [income])
	# bone_fields: undead recruit discount — find any undead-tagged unit
	var undead_unit: UnitData = null
	var dm = root.get_node("/root/DataManager")
	for uid in dm.units:
		if dm.units[uid].tags.has("undead"):
			undead_unit = dm.units[uid]
			break
	_check(undead_unit != null, "an undead-tagged unit exists")
	if undead_unit:
		_check(BountySystem.recruit_discount_for(city, undead_unit) >= 10,
			"bone_fields grants 10%% undead recruit discount")
	# Cleanup so later test sections see an unmodified map
	for s in spots:
		map.get_tile(s).bounty_id = &""
```

- [ ] **Step 2: Run it — expect FAIL** at "coal_seams exists in BOUNTY_TYPES".
- [ ] **Step 3: Implement** — add three entries at the end of `BOUNTY_TYPES` (before the closing `}`), matching the existing entry style exactly (terrains: 2=MOUNTAINS, 3=DESERT, 6=TUNDRA, 7=SHARD_WASTES; income keys: 0=GOLD, 1=IRON):

```gdscript
	&"coal_seams": {name = "Coal Seams", terrains = [2, 6], income = {1: 6}},
	&"bone_fields": {name = "Bone Fields", terrains = [3, 7], recruit_discount = {undead = 10}},
	&"bronze_ore": {name = "Bronze Ore", terrains = [2, 3], income = {0: 3, 1: 4}},
```

- [ ] **Step 4: Run the new test — expect PASSED.**
- [ ] **Step 5: Regressions** (scatter now rolls 25 types instead of 22, which shifts which types each seed selects — these suites assert invariants, not pinned rosters, and must stay green): `test_bounty_system`, `test_map_seed`, `test_landmarks`, `test_playtest_round2`, `test_battle_determinism` (MATCH).
- [ ] **Step 6: Commit** `feat(bounties): coal_seams, bone_fields, bronze_ore deposit types`.

---

### Task 2: Research gate core (start-only check + map-absence fallback)

**Files:**
- Modify: `scripts/resources/research_data.gd` (append after line 19)
- Modify: `scripts/systems/campaign/bounty_system.gd` (new static helpers)
- Modify: `scripts/systems/campaign/research_system.gd` (`get_available_research` :24-31, `start_research` :34-49, `_advance_queue` :127-130)
- Test: `tests/test_bounty_gated_techs.gd` (append)

**Interfaces:**
- Consumes: bounty type ids from Task 1.
- Produces (later tasks rely on these exact signatures):
  - `ResearchData.requires_bounty_types: Array[StringName]` (any-of; empty = ungated)
  - `static BountySystem.faction_has_bounty_type(faction_id: StringName, type_id: StringName) -> bool` (claim-based; Task 4 ORs lease access into `is_bounty_locked`, NOT here)
  - `static BountySystem.types_on_map(map: HexMapData) -> Dictionary` (type_id -> true)
  - `ResearchSystem.is_bounty_locked(faction_id: StringName, data: ResearchData) -> bool`
  - `ResearchSystem.effective_tech_cost(data: ResearchData) -> int` (2× when gate exists but no required type is on the map)
  - `ResearchSystem.get_bounty_locked_research(faction_id: StringName) -> Array[Dictionary]` — `[{data: ResearchData, missing_types: Array[StringName]}]`

- [ ] **Step 1: Write the failing test** — append to `tests/test_bounty_gated_techs.gd` and call from `_run` after the Task-1 section. Gate a real tech in-memory (the .tres sweep is Task 3; mutating `DataManager.research` is safe — the headless process exits after the run):

```gdscript
func _run_gate_core_test(gm) -> void:
	gm.new_game(&"empire", false, 0)
	var rs = gm.research_system
	var player_id: StringName = gm.state.player_faction_id
	var fs = gm.state.faction_states[player_id]
	var dm = root.get_node("/root/DataManager")
	var map = gm.state.hex_map
	# Pick a tier-2+ empire tech with no prereqs beyond what we control:
	# gate emp_aqueducts (tier 3) on wild_horses for the test.
	var data: ResearchData = dm.research.get(&"emp_aqueducts")
	_check(data != null, "emp_aqueducts exists")
	data.requires_bounty_types = [&"wild_horses"] as Array[StringName]
	# Complete its prereqs so the bounty is the only gate.
	for prereq in data.prerequisites:
		if not fs.completed_research.has(prereq):
			fs.completed_research.append(prereq)
	fs.resources[Enums.ResourceType.TECHNOLOGY] = 10000

	# Case 1: type exists on map (plant one far away), faction holds none -> LOCKED
	var far_tile = null
	for coord in map.tiles:
		var t = map.get_tile(coord)
		if t and t.bounty_id == &"" and BountySystem.claimant_for(coord) == &"":
			far_tile = t
			break
	_check(far_tile != null, "found an unclaimed clean tile")
	far_tile.bounty_id = &"wild_horses"
	_check(rs.is_bounty_locked(player_id, data), "locked while type on map but unheld")
	_check(not rs.start_research(player_id, &"emp_aqueducts"), "start_research refuses while locked")
	var avail: Array[ResearchData] = rs.get_available_research(player_id)
	var listed := false
	for a in avail:
		if a.id == &"emp_aqueducts":
			listed = true
	_check(not listed, "locked tech excluded from get_available_research")
	var locked_list: Array[Dictionary] = rs.get_bounty_locked_research(player_id)
	var found_entry := false
	for e in locked_list:
		if e.data.id == &"emp_aqueducts" and e.missing_types.has(&"wild_horses"):
			found_entry = true
	_check(found_entry, "get_bounty_locked_research reports the tech + missing type")

	# Case 2: faction claims the type -> UNLOCKED, normal cost
	var city: CityState = gm.state.cities.get(fs.owned_cities[0])
	var near_tile = null
	var near_coord := Vector2i.ZERO
	for coord in map.tiles:
		var d: int = maxi(absi(coord.x - city.hex_pos.x), absi(coord.y - city.hex_pos.y))
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"":
			near_tile = t
			near_coord = coord
			break
	near_tile.bounty_id = &"wild_horses"
	_check(BountySystem.faction_has_bounty_type(player_id, &"wild_horses"), "claim within radius detected")
	_check(not rs.is_bounty_locked(player_id, data), "unlocked once claimed")
	_check(rs.effective_tech_cost(data) == data.tech_cost, "normal cost while type on map")
	var tech_before: int = fs.resources[Enums.ResourceType.TECHNOLOGY]
	_check(rs.start_research(player_id, &"emp_aqueducts"), "start_research succeeds once claimed")
	_check(fs.resources[Enums.ResourceType.TECHNOLOGY] == tech_before - data.tech_cost, "normal cost deducted")
	rs.cancel_research(player_id)

	# Case 3: type absent from the whole map -> researchable at 2x cost
	near_tile.bounty_id = &""
	far_tile.bounty_id = &""
	for coord in map.tiles:  # strip any scatter-placed wild_horses
		var t = map.get_tile(coord)
		if t and t.bounty_id == &"wild_horses":
			t.bounty_id = &""
	_check(not rs.is_bounty_locked(player_id, data), "not locked when type absent map-wide")
	_check(rs.effective_tech_cost(data) == data.tech_cost * 2, "cost doubles when type absent map-wide")
	tech_before = fs.resources[Enums.ResourceType.TECHNOLOGY]
	_check(rs.start_research(player_id, &"emp_aqueducts"), "start succeeds via fallback")
	_check(fs.resources[Enums.ResourceType.TECHNOLOGY] == tech_before - data.tech_cost * 2, "doubled cost deducted")
	rs.cancel_research(player_id)
	data.requires_bounty_types = [] as Array[StringName]  # undo for later sections
```

- [ ] **Step 2: Run — expect FAIL** ("requires_bounty_types" nonexistent / is_bounty_locked nonexistent).
- [ ] **Step 3: Implement.**

`research_data.gd` (append after line 19, same style as existing exports):
```gdscript
@export var requires_bounty_types: Array[StringName] = [] # Any-of bounty-type gate, checked when research STARTS only (never pauses running research). Empty = no gate.
```

`bounty_system.gd` (new statics, place after `bounties_claimable_at`):
```gdscript
## True if any of this faction's cities currently claims a bounty of this
## type. Claim-based only -- leased-in access is a diplomacy concern and is
## ORed in by ResearchSystem.is_bounty_locked, not here.
static func faction_has_bounty_type(faction_id: StringName, type_id: StringName) -> bool:
	for entry in bounties_of_faction(faction_id):
		if entry.id == type_id:
			return true
	return false

## Set (Dictionary keys -> true) of bounty type ids present anywhere on the
## map. ~66% of types roll onto a given map (ROSTER_ROLL_PCT) -- gate
## fallbacks key off absence.
static func types_on_map(map: HexMapData) -> Dictionary:
	var found := {}
	if map == null:
		return found
	for coord in map.tiles:
		var tid: StringName = map.tiles[coord].bounty_id
		if tid != &"":
			found[tid] = true
	return found
```

`research_system.gd` — three new instance funcs (place before `execute_ai_research`):
```gdscript
## Bounty gate (start-only, designer decision 2026-08-01): a tech listing
## requires_bounty_types can be STARTED only while the faction holds a
## bounty of any listed type (city claim; Task 4 adds leased-in access).
## If NONE of the listed types exist anywhere on this map, the gate is not
## a lock -- effective_tech_cost doubles instead (design doc §7 fallback).
func is_bounty_locked(faction_id: StringName, data: ResearchData) -> bool:
	if data.requires_bounty_types.is_empty():
		return false
	var on_map := BountySystem.types_on_map(GameManager.state.hex_map)
	var any_on_map := false
	for type_id in data.requires_bounty_types:
		if on_map.has(type_id):
			any_on_map = true
		if BountySystem.faction_has_bounty_type(faction_id, type_id):
			return false
	return any_on_map

## tech_cost, or double it when the tech is gated but none of its required
## bounty types exist on this map ("improvised without the real material").
func effective_tech_cost(data: ResearchData) -> int:
	if data.requires_bounty_types.is_empty():
		return data.tech_cost
	var on_map := BountySystem.types_on_map(GameManager.state.hex_map)
	for type_id in data.requires_bounty_types:
		if on_map.has(type_id):
			return data.tech_cost
	return data.tech_cost * 2

## Techs whose ONLY unmet gate is the bounty (prereqs met, not completed,
## faction-eligible). Feeds the tech-tree locked display and the AI's
## gate-aware settlement scoring.
func get_bounty_locked_research(faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	var parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	for research_id in DataManager.research:
		var data: ResearchData = DataManager.research[research_id]
		if data.requires_bounty_types.is_empty():
			continue
		if fs.completed_research.has(research_id) or fs.current_research_id == research_id:
			continue
		if data.faction_id != &"" and data.faction_id != parent:
			continue
		var prereqs_met := true
		for prereq in data.prerequisites:
			if not fs.completed_research.has(prereq):
				prereqs_met = false
				break
		if not prereqs_met:
			continue
		if not is_bounty_locked(faction_id, data):
			continue
		var missing: Array[StringName] = []
		for type_id in data.requires_bounty_types:
			if not BountySystem.faction_has_bounty_type(faction_id, type_id):
				missing.append(type_id)
		result.append({data = data, missing_types = missing})
	return result
```
NOTE: match `get_available_research`'s actual faction-eligibility line (:21-23) when writing the `parent` check — copy its exact condition.

Hook the gate in (three places):
1. `get_available_research` (:24-31): change `if prereqs_met:` to `if prereqs_met and not is_bounty_locked(faction_id, data):`.
2. `start_research` (:34-49): after the `data == null` check add:
```gdscript
	# Bounty gate -- start-only check (designer decision 2026-08-01)
	if is_bounty_locked(faction_id, data):
		return false
```
   and replace the two `data.tech_cost` reads in the cost check/deduct with `var cost := effective_tech_cost(data)` used in both lines.
3. `_advance_queue` (:127-130): its duplicated prereq loop skips queue entries with unmet prereqs — add `or is_bounty_locked(faction_id, data)` to the same skip condition so a locked queued tech is passed over, not silently started.

- [ ] **Step 4: Run the suite — expect PASSED.**
- [ ] **Step 5: Regressions:** `test_polish_pass` (uses start_research), `test_ai_economy`, `test_save_roundtrip`, `test_battle_determinism` (MATCH). All 495 existing .tres files omit the new field → default `[]` → zero behavior change for ungated techs.
- [ ] **Step 6: Commit** `feat(research): start-only bounty gate + map-absence cost fallback`.

---

### Task 3: Gate data sweep — 30 techs

**Files:**
- Create: `tests/tools_bounty_gate_sweep.gd` (one-off tool, committed for provenance — model on `tests/tools_cost_sweep.gd`)
- Modify: 30 files under `data/research/<faction>/*.tres`
- Test: `tests/test_bounty_gated_techs.gd` (append verification section)

**Interfaces:**
- Consumes: `requires_bounty_types` field (Task 2), the three new type ids (Task 1).
- Produces: the live gate list below — Tasks 5/6 test against `sk_horse_lords`→`wild_horses` and `emp_war_machines`→`titanstone_quarry` specifically.

**THE GATE LIST (30 gates — this exact table is the spec; all ids verified to exist 2026-08-01):**

| tech id | faction | tier | gate type(s) — any-of |
|---|---|---|---|
| sk_horse_lords | skulloath | 3 | wild_horses |
| sk_leather_works | skulloath | 3 | furs |
| great_yurt | skulloath | 3 | bone_fields |
| sb_dawn_cavalry | sunblessed | 2 | wild_horses |
| oasis_blessing | sunblessed | 3 | salt_flats |
| sb_sun_forging | sunblessed | 3 | bronze_ore |
| ms_lunar_knights | moonspear | 3 | wild_horses |
| ms_silver_mines | moonspear | 3 | copper_vein |
| adamantine_forge | cinderguard | 3 | titanstone_quarry |
| cg_master_alloys | cinderguard | 4 | bronze_ore, copper_vein |
| volcanic_glass | cinderguard | 2 | obsidian_flows |
| cg_war_forges | cinderguard | 4 | coal_seams |
| emp_war_machines | empire | 4 | titanstone_quarry |
| emp_aqueducts | empire | 3 | orchards |
| road_network | empire | 2 | granite |
| emp_harbor_cities | empire | 3 | fisheries |
| gh_herb_gardens | gladehost | 2 | herb_meadows |
| gh_root_bridges | gladehost | 2 | timber_giants |
| gh_forest_trade | gladehost | 3 | amber_groves |
| mining_expertise | thunderswarm | 2 | copper_vein |
| ts_deep_mines | thunderswarm | 4 | granite |
| storm_forge | thunderswarm | 3 | coal_seams |
| iv_stone_masons | ivoryscar | 2 | marble |
| ossuary_guards | ivoryscar | 2 | bone_fields |
| fk_corpse_labor | forsaken | 2 | bone_fields |
| fk_bone_walls | forsaken | 2 | basalt_columns |
| jungle_pharmacy | tainted_jade | 2 | herb_meadows |
| tj_mushroom_farms | tainted_jade | 2 | peat_bogs |
| venomcraft | tainted_jade | 2 | dye_gardens |
| sh_shard_miners | shardhorde | 2 | crystal_springs |

- [ ] **Step 1: Write the sweep tool** `tests/tools_bounty_gate_sweep.gd` (SceneTree script): holds the table above as a `const GATES := {&"sk_horse_lords": [&"wild_horses"], ...}` dict; for each entry, load `data/research/<faction_id>/<id>.tres` path via DataManager lookup (`DataManager.research[id].resource_path`), read the file text, insert/replace a `requires_bounty_types = Array[StringName]([&"..."])` line after the `prerequisites` line, write it back, print CSV `id,faction,tier,types`. Refuse (print + skip) any entry whose tier is 1 or whose type id is missing from `BountySystem.BOUNTY_TYPES`.
- [ ] **Step 2: Write the failing verification test** — append to `tests/test_bounty_gated_techs.gd`:

```gdscript
const EXPECTED_GATES := {
	&"sk_horse_lords": [&"wild_horses"], &"sk_leather_works": [&"furs"],
	&"great_yurt": [&"bone_fields"], &"sb_dawn_cavalry": [&"wild_horses"],
	&"oasis_blessing": [&"salt_flats"], &"sb_sun_forging": [&"bronze_ore"],
	&"ms_lunar_knights": [&"wild_horses"], &"ms_silver_mines": [&"copper_vein"],
	&"adamantine_forge": [&"titanstone_quarry"], &"cg_master_alloys": [&"bronze_ore", &"copper_vein"],
	&"volcanic_glass": [&"obsidian_flows"], &"cg_war_forges": [&"coal_seams"],
	&"emp_war_machines": [&"titanstone_quarry"], &"emp_aqueducts": [&"orchards"],
	&"road_network": [&"granite"], &"emp_harbor_cities": [&"fisheries"],
	&"gh_herb_gardens": [&"herb_meadows"], &"gh_root_bridges": [&"timber_giants"],
	&"gh_forest_trade": [&"amber_groves"], &"mining_expertise": [&"copper_vein"],
	&"ts_deep_mines": [&"granite"], &"storm_forge": [&"coal_seams"],
	&"iv_stone_masons": [&"marble"], &"ossuary_guards": [&"bone_fields"],
	&"fk_corpse_labor": [&"bone_fields"], &"fk_bone_walls": [&"basalt_columns"],
	&"jungle_pharmacy": [&"herb_meadows"], &"tj_mushroom_farms": [&"peat_bogs"],
	&"venomcraft": [&"dye_gardens"], &"sh_shard_miners": [&"crystal_springs"],
}

func _run_gate_sweep_verification(dm) -> void:
	for tech_id in EXPECTED_GATES:
		var data: ResearchData = dm.research.get(tech_id)
		_check(data != null, "%s exists" % tech_id)
		if data == null:
			continue
		_check(data.requires_bounty_types == (EXPECTED_GATES[tech_id] as Array[StringName]),
			"%s gated on %s (got %s)" % [tech_id, EXPECTED_GATES[tech_id], data.requires_bounty_types])
	# Global invariants over ALL research data:
	var gated_count := 0
	for research_id in dm.research:
		var d: ResearchData = dm.research[research_id]
		if d.requires_bounty_types.is_empty():
			continue
		gated_count += 1
		_check(d.tier >= 2, "%s: gated tech is tier 2+ (tier %d)" % [research_id, d.tier])
		_check(EXPECTED_GATES.has(research_id), "%s: gated tech is in the approved list" % research_id)
		for type_id in d.requires_bounty_types:
			_check(BountySystem.BOUNTY_TYPES.has(type_id), "%s: gate type %s exists" % [research_id, type_id])
	_check(gated_count == 30, "exactly 30 gated techs (got %d)" % gated_count)
```
   NOTE: this section must run BEFORE `_run_gate_core_test` in `_run` (that test temporarily mutates `emp_aqueducts`; order the calls sweep-verification → gate-core, or re-set `emp_aqueducts.requires_bounty_types = [&"orchards"]` at the end of the gate-core section once Task 3 lands — pick the first, it's simpler).
- [ ] **Step 3: Run verification — expect FAIL** (all gates missing). Run the sweep tool; eyeball its CSV (30 rows, no skips). Re-run verification — **expect PASSED** (adjust `_run_gate_core_test` per the NOTE — it must restore `emp_aqueducts` to `[&"orchards"]`, not `[]`).
- [ ] **Step 4: Regressions:** full `test_bounty_gated_techs`, `test_ai_economy` (AI research now skips locked techs — must still pick SOMETHING), `test_polish_pass`, `test_battle_determinism` (MATCH). Run econ sim smoke `tests/tmp_econ_sim.gd -- 7 25` if present: no faction may end with zero research completions.
- [ ] **Step 5: Commit** `feat(research): 30 bounty-gated techs across 11 factions` (include the tool + tres changes + test).

---

### Task 4: Bounty leases — trade for gate access (REQUIRED scope)

**Files:**
- Modify: `scripts/systems/campaign/diplomacy_system.gd` (near `propose_resource_lease` :350-377, `process_treaties` RESOURCE_LEASE branch :723-733, tooltip strings)
- Modify: `scripts/systems/campaign/research_system.gd` (`is_bounty_locked` gains the lease OR)
- Modify: `scenes/campaign/campaign_hud.gd` (offer list :4323-4331 area, `_execute_combined_offers` :5006-5031 area, treaty-icon tooltips :3248-3250)
- Test: `tests/test_bounty_gated_techs.gd` (append)

**Interfaces:**
- Consumes: `faction_has_bounty_type`, `is_bounty_locked`, `get_bounty_locked_research` (Task 2).
- Produces:
  - `DiplomacySystem.propose_bounty_lease(owner: StringName, lessee: StringName, bounty_hex: Vector2i, gold_per_turn: int, duration: int) -> Dictionary` (`{accepted: bool, reason: String}`)
  - `DiplomacySystem.lease_for_bounty(bounty_hex: Vector2i) -> TreatyInstance` (null if none)
  - `DiplomacySystem.faction_leases_bounty_type(faction_id: StringName, type_id: StringName) -> bool`
  - Treaty terms shape: `{bounty_hex: Vector2i, bounty_id: StringName, gold_per_turn: int}` on `TreatyType.RESOURCE_LEASE` (all `@export` plumbing already survives save/load).

- [ ] **Step 1: Write the failing test** — append:

```gdscript
func _run_bounty_lease_test(gm) -> void:
	gm.new_game(&"empire", false, 0)
	var ds = gm.diplomacy_system
	var rs = gm.research_system
	var player_id: StringName = gm.state.player_faction_id
	var other: StringName = &"skulloath"
	var other_fs = gm.state.faction_states[other]
	var map = gm.state.hex_map
	# Plant wild_horses next to a skulloath city so skulloath is claimant.
	var other_city: CityState = gm.state.cities.get(other_fs.owned_cities[0])
	var spot := Vector2i.ZERO
	for coord in map.tiles:
		var d: int = maxi(absi(coord.x - other_city.hex_pos.x), absi(coord.y - other_city.hex_pos.y))
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"" and BountySystem.claimant_for(coord) == other_city.city_id:
			spot = coord
			t.bounty_id = &"wild_horses"
			break
	_check(BountySystem.faction_has_bounty_type(other, &"wild_horses"), "skulloath claims the planted wild_horses")
	ds.init_standing(other, player_id, 40, "test setup")
	var res: Dictionary = ds.propose_bounty_lease(other, player_id, spot, 14, 10)
	_check(res.get("accepted", false), "AI owner leases bounty to player (got %s)" % [res])
	_check(ds.lease_for_bounty(spot) != null, "lease_for_bounty finds the treaty")
	_check(ds.faction_leases_bounty_type(player_id, &"wild_horses"), "player has leased-in wild_horses")
	_check(ds.propose_bounty_lease(other, player_id, spot, 14, 10).get("accepted", true) == false, "double-lease refused")
	# Lease satisfies the research gate:
	var data: ResearchData = root.get_node("/root/DataManager").research[&"sk_horse_lords"]
	# (player is empire; use a player-eligible gated tech instead)
	data = root.get_node("/root/DataManager").research[&"sb_dawn_cavalry"]
	# sb_dawn_cavalry is sunblessed -- also wrong faction. Use an in-memory gate:
	data = root.get_node("/root/DataManager").research[&"emp_war_machines"]
	data.requires_bounty_types = [&"wild_horses"] as Array[StringName]  # temporary override
	var fs = gm.state.faction_states[player_id]
	for prereq in data.prerequisites:
		if not fs.completed_research.has(prereq):
			fs.completed_research.append(prereq)
	_check(not rs.is_bounty_locked(player_id, data), "leased-in type unlocks the gate")
	data.requires_bounty_types = [&"titanstone_quarry"] as Array[StringName]  # restore Task-3 value
	# Per-turn processing: player pays, owner earns; losing the claim expires it.
	var gold_p: int = fs.resources[Enums.ResourceType.GOLD]
	var gold_o: int = other_fs.resources.get(Enums.ResourceType.GOLD, 0)
	ds.process_treaties(other)  # leases process on faction_a's turn
	_check(fs.resources[Enums.ResourceType.GOLD] == gold_p - 14, "lessee paid 14 gold")
	_check(other_fs.resources[Enums.ResourceType.GOLD] == gold_o + 14, "owner earned 14 gold")
	map.get_tile(spot).bounty_id = &""  # bounty gone -> lease must expire
	ds.process_treaties(other)
	_check(ds.lease_for_bounty(spot) == null, "lease expired when the bounty vanished")
	_check(not ds.faction_leases_bounty_type(player_id, &"wild_horses"), "leased access gone after expiry")
```

- [ ] **Step 2: Run — expect FAIL** (propose_bounty_lease nonexistent).
- [ ] **Step 3: Implement.**

`diplomacy_system.gd` — place the three funcs directly after `propose_resource_lease`:
```gdscript
## ── Bounty leases ─────────────────────────────────────────
## Ride TreatyType.RESOURCE_LEASE with a different terms shape:
## {bounty_hex, bounty_id, gold_per_turn} instead of {special_id, gold_per_turn}.
## Required scope for bounty-gated techs (designer directive 2026-08-01):
## a faction without map access to a gate bounty negotiates for it here.

func lease_for_bounty(bounty_hex: Vector2i) -> TreatyInstance:
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.terms.get("bounty_hex", Vector2i(-9999, -9999)) == bounty_hex:
			return t
	return null

func faction_leases_bounty_type(faction_id: StringName, type_id: StringName) -> bool:
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_b == faction_id and t.terms.get("bounty_id", &"") == type_id:
			return true
	return false

func propose_bounty_lease(owner: StringName, lessee: StringName, bounty_hex: Vector2i, gold_per_turn: int, duration: int) -> Dictionary:
	if GameManager.get_relation(owner, lessee) == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "At war."}
	var tile = GameManager.state.hex_map.get_tile(bounty_hex)
	if tile == null or tile.bounty_id == &"":
		return {accepted = false, reason = "No bounty there."}
	var claimant_city: CityState = GameManager.state.cities.get(BountySystem.claimant_for(bounty_hex))
	if claimant_city == null or claimant_city.faction_id != owner:
		return {accepted = false, reason = "Owner does not hold this bounty."}
	if lease_for_bounty(bounty_hex) != null:
		return {accepted = false, reason = "Already leased to another faction."}
	if lessee != GameManager.state.player_faction_id:
		# AI lessee wants it only if it unlocks a bounty-locked tech.
		var wants := false
		for entry in GameManager.research_system.get_bounty_locked_research(lessee):
			if entry.missing_types.has(tile.bounty_id):
				wants = true
				break
		if not wants:
			return {accepted = false, reason = "Not interested in this lease."}
	elif owner != GameManager.state.player_faction_id:
		# AI owner deciding whether to lease out to the player (mirrors specials).
		var standing := get_standing(owner, lessee)
		var min_pay := 8 + int(_get_faction_greed(owner) * 4.0)
		if gold_per_turn < min_pay or standing < 0:
			return {accepted = false, reason = "They want more for this lease."}
	var treaty := TreatyInstance.new()
	treaty.treaty_id = GameManager.state.generate_id()
	treaty.treaty_type = Enums.TreatyType.RESOURCE_LEASE
	treaty.faction_a = owner
	treaty.faction_b = lessee
	treaty.turns_remaining = duration
	treaty.terms = {bounty_hex = bounty_hex, bounty_id = tile.bounty_id, gold_per_turn = gold_per_turn}
	GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
	modify_standing(owner, lessee, 3, "Bounty lease")
	EventBus.treaty_created.emit(treaty.treaty_id, Enums.TreatyType.RESOURCE_LEASE, owner, lessee)
	return {accepted = true, reason = "Lease agreed."}
```

`process_treaties` RESOURCE_LEASE branch: guard the existing `still_extracted` logic behind `if treaty.terms.has("special_id"):` and add the bounty variant:
```gdscript
			var still_valid: bool
			if treaty.terms.has("bounty_hex"):
				var bhex: Vector2i = treaty.terms["bounty_hex"]
				var btile = GameManager.state.hex_map.get_tile(bhex)
				var bcity: CityState = GameManager.state.cities.get(BountySystem.claimant_for(bhex))
				still_valid = btile != null and btile.bounty_id == treaty.terms.get("bounty_id", &"") \
					and bcity != null and bcity.faction_id == treaty.faction_a
			else:
				still_valid = treaty.terms.get("special_id", &"") in SpecialResourceSystem.extracted_specials_of_faction(treaty.faction_a)
```
(then the existing pay/expire logic uses `still_valid` where it used `still_extracted`).

`research_system.gd` `is_bounty_locked`: inside the type loop, after the `faction_has_bounty_type` early-return, add:
```gdscript
		if GameManager.diplomacy_system.faction_leases_bounty_type(faction_id, type_id):
			return false
```

`campaign_hud.gd`:
- Offer list (next to the specials lease block at :4323-4331): for up to 4 of the OTHER faction's claimed bounties (`BountySystem.bounties_of_faction(other_id)`) whose type the player does not already hold (`not BountySystem.faction_has_bounty_type(player_id, entry.id)`) and that is unleased (`lease_for_bounty(entry.hex) == null`), append `{id = "blease_in_%d_%d" % [entry.hex.x, entry.hex.y], label = "Request bounty lease: %s (pay 14g/turn, 10 turns)" % entry.name}`. Symmetric `blease_out_%d_%d` rows ("Lease out bounty: %s (10g/turn, 10 turns)") for the player's own claimed bounties, capped at 4.
- `_execute_combined_offers` (:5006-5031 area): add `blease_in_` / `blease_out_` prefix branches that parse the two ints back into a `Vector2i` and call `GameManager.diplomacy_system.propose_bounty_lease(other, player, hex, 14, 10)` / `(player, other, hex, 10, 10)` — mirror the existing `lease_in_`/`lease_out_` result handling verbatim.
- Treaty-icon tooltips (:3248-3250): when the treaty's terms have `bounty_id`, name it: `"Bounty Lease: %s (earning %d gold/turn)"` using `BountySystem.BOUNTY_TYPES[terms.bounty_id].name` — same paying/earning polarity as the existing strings.

- [ ] **Step 4: Run the suite — expect PASSED.**
- [ ] **Step 5: Windowed compile check** (campaign_hud.gd changed): run `tests/tmp_screenshot_diplomacy.gd` windowed; stdout must not SCRIPT ERROR on campaign_hud.gd.
- [ ] **Step 6: Regressions:** `test_save_roundtrip` (terms dict with Vector2i must survive — it's all @export native serialization), `test_ai_economy`, `test_battle_determinism` (MATCH).
- [ ] **Step 7: Commit** `feat(diplomacy): bounty leases - trade access to gate bounties`.

---

### Task 5: Tech tree UI — locked badge, tooltip, detail dialog, honest costs

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` — `_RadialTechTree._calculate_positions` :6305, `_draw` :6725-6829, `_draw_hover_tooltip` :6834-6892, `_try_start_research` :7028-7047, `_show_research_detail` :7070-7166
- Test: windowed screenshot gate (no headless test can compile campaign_hud cold — see Global Constraints)

**Interfaces:**
- Consumes: `is_bounty_locked`, `effective_tech_cost`, `get_bounty_locked_research` (Task 2), `BountySystem.BOUNTY_TYPES[t].name`, `BountySystem.types_on_map`.

Design (from the design doc §5): gated-and-unmet techs stay VISIBLE but visually locked; tooltip names the requirement; map-absent types are labeled with the doubled cost.

- [ ] **Step 1: Cache lock states** — `is_bounty_locked` scans the map dict; NEVER call it per-node inside `_draw` (runs per frame). In `_RadialTechTree` add members and populate at the END of `_calculate_positions()`:
```gdscript
var _bounty_gate_state: Dictionary = {}  # research_id -> 0 met/ungated, 1 locked, 2 map-absent (cost doubled)
```
```gdscript
	# Bounty-gate display cache -- recomputed on every panel rebuild, cheap
	# and can't go stale mid-frame (claims/leases only change on turn/treaty).
	_bounty_gate_state.clear()
	var rs = GameManager.research_system
	for research_id in _positions:
		var rdata: ResearchData = DataManager.research[research_id]
		if rdata.requires_bounty_types.is_empty():
			continue
		if rs.is_bounty_locked(faction_id, rdata):
			_bounty_gate_state[research_id] = 1
		elif rs.effective_tech_cost(rdata) > rdata.tech_cost:
			_bounty_gate_state[research_id] = 2
		else:
			_bounty_gate_state[research_id] = 0
```
(Use the tree's actual node-position dict name — `_positions` per :6305's structure — and its actual faction id member; re-read the class header first.)
- [ ] **Step 2: Node coloring** — in `_draw` (:6733-6768): the `can_afford` local is hardcoded `true` (line ~6740) making the red branch dead. Repurpose it: `var can_afford: bool = _bounty_gate_state.get(research_id, 0) != 1`. The existing `elif prereqs_met:` red branch (0.55, 0.2, 0.2) now renders bounty-locked techs — exactly the "visible but locked" convention. Add a small marker so red reads as "resource-locked" not "error": after the node circle draw, if state == 1 draw the category-colored ring plus a `"⚿"`-substitute — draw a 3px white-bordered dot at the node's top-right using `draw_circle(pos + Vector2(radius * 0.7, -radius * 0.7), 3.0, Color(0.9, 0.75, 0.3))`.
- [ ] **Step 3: Hover tooltip** — in `_draw_hover_tooltip`: the status line uses `"%d turns | %d Tech"`; swap the cost operand to `GameManager.research_system.effective_tech_cost(data)`. Then append one extra line when `data.requires_bounty_types` is non-empty, before the effects lines (grow `total_lines` accordingly):
```gdscript
	if not data.requires_bounty_types.is_empty():
		var names: Array[String] = []
		for t in data.requires_bounty_types:
			names.append(BountySystem.BOUNTY_TYPES[t].name)
		match _bounty_gate_state.get(research_id, 0):
			1: lines.append("Requires: %s (claim or lease one)" % " / ".join(names))
			2: lines.append("%s not on this map - cost doubled" % " / ".join(names))
			_: lines.append("Requires: %s (met)" % " / ".join(names))
```
(Adapt to the tooltip's actual line-building structure — it may draw strings directly rather than build a `lines` array; keep the three texts verbatim.)
- [ ] **Step 4: Start guard** — `_try_start_research` (:7028-7047) currently returns silently on unmet prereqs. Add after the prereq loop:
```gdscript
	if GameManager.research_system.is_bounty_locked(GameManager.state.player_faction_id, data):
		AudioManager.play_sfx(&"error_buzz")
		return
```
- [ ] **Step 5: Detail dialog** — `_show_research_detail` (:7070-7166): after the Prerequisites section (:7148-7160), add a "Required Resources" block using the same label style: one row per type in `requires_bounty_types` — text `BOUNTY_TYPES[t].name`, color green `Color(0.4, 0.8, 0.4)` if `BountySystem.faction_has_bounty_type(player, t)` or `faction_leases_bounty_type(player, t)`, grey `Color(0.6, 0.58, 0.52)` with suffix `" — not on this map (cost doubled)"` if absent from `types_on_map`, else red `Color(0.85, 0.4, 0.35)` with suffix `" — claim or lease to unlock"`. Also swap the dialog's cost display (added in playtest R2, "Research Cost: %d Tech") to `effective_tech_cost`.
- [ ] **Step 6: Windowed verification + screenshot** — extend `tests/tmp_screenshot_techtree.gd`: open the tech tree as empire (empire has 4 gates: road_network T2, emp_aqueducts T3, emp_harbor_cities T3, emp_war_machines T4), screenshot the tree, then force-open `_show_research_detail` on `road_network` and screenshot the dialog. Run windowed; require: zero SCRIPT ERROR naming campaign_hud.gd, and visually confirm (coordinator judges the PNGs): a red-locked node with the gold dot, the requires-line in the hover box if capturable, the Required Resources row in the dialog.
- [ ] **Step 7: Commit** `feat(ui): tech tree shows bounty gates - locked nodes, requirements, honest costs`.

---

### Task 6: Gate-aware AI settlement scoring

**Files:**
- Modify: `scripts/autoloads/turn_manager.gd` (`_execute_ai_settlement_building` :1012-1108, scoring loop :1086-1104)
- Modify: `scripts/systems/campaign/bounty_system.gd` (`bounties_claimable_at` :400 gains `ignore_fog` param)
- Test: `tests/test_bounty_gated_techs.gd` (append)

**Interfaces:**
- Consumes: `get_bounty_locked_research` (Task 2).
- Produces: `static BountySystem.bounties_claimable_at(hex_pos: Vector2i, ignore_fog: bool = false) -> Array[Dictionary]` (default preserves all existing call sites); `TurnManager._settlement_gate_bonus(tile_pos: Vector2i, wanted_types: Dictionary) -> int`.

- [ ] **Step 1: Write the failing test** — append:
```gdscript
func _run_ai_gate_scoring_test(gm, tm) -> void:
	gm.new_game(&"empire", false, 0)
	var map = gm.state.hex_map
	# skulloath has 3 gates incl. sk_horse_lords -> wild_horses. Ensure the
	# type is on the map but unheld by skulloath -> it lands in the wanted set.
	var wanted := {}
	for entry in gm.research_system.get_bounty_locked_research(&"skulloath"):
		for t in entry.missing_types:
			wanted[t] = true
	# Force determinism: plant an unclaimed wild_horses far from all cities
	# if scatter didn't roll it this seed, then rebuild the wanted set.
	if not wanted.has(&"wild_horses"):
		for coord in map.tiles:
			var t = map.get_tile(coord)
			if t and t.bounty_id == &"" and BountySystem.claimant_for(coord) == &"":
				t.bounty_id = &"wild_horses"
				break
		wanted = {}
		for entry in gm.research_system.get_bounty_locked_research(&"skulloath"):
			for t2 in entry.missing_types:
				wanted[t2] = true
	# NOTE: sk_horse_lords is tier 3 -- if its prereqs aren't met at turn 1 it
	# won't appear in get_bounty_locked_research. Complete them first:
	var fs = gm.state.faction_states[&"skulloath"]
	var data: ResearchData = root.get_node("/root/DataManager").research[&"sk_horse_lords"]
	for prereq in data.prerequisites:
		if not fs.completed_research.has(prereq):
			fs.completed_research.append(prereq)
	wanted = {}
	for entry in gm.research_system.get_bounty_locked_research(&"skulloath"):
		for t3 in entry.missing_types:
			wanted[t3] = true
	_check(wanted.has(&"wild_horses"), "wild_horses is in skulloath's wanted set (got %s)" % [wanted])
	# The bonus helper: a tile adjacent to an unclaimed wanted bounty scores +15.
	var bounty_coord := Vector2i(-9999, -9999)
	for coord in map.tiles:
		var t = map.get_tile(coord)
		if t and t.bounty_id == &"wild_horses" and BountySystem.claimant_for(coord) == &"":
			bounty_coord = coord
			break
	_check(bounty_coord != Vector2i(-9999, -9999), "an unclaimed wild_horses exists")
	var near := bounty_coord + Vector2i(1, 0)
	_check(tm._settlement_gate_bonus(near, wanted) == 15, "wanted-bounty-adjacent tile gets +15")
	_check(tm._settlement_gate_bonus(near, {}) == 0, "empty wanted set -> 0")
	var far := bounty_coord + Vector2i(30, 30)
	_check(tm._settlement_gate_bonus(far, wanted) == 0, "far tile gets 0")
```
(`tm` = `root.get_node("/root/TurnManager")`.)
- [ ] **Step 2: Run — expect FAIL** (_settlement_gate_bonus nonexistent).
- [ ] **Step 3: Implement.** `bounty_system.gd:400` — add `ignore_fog: bool = false` parameter; the fog check at :414 becomes `if not ignore_fog and not GameManager.explored_tiles.has(...)`. `turn_manager.gd` — new helper next to `_execute_ai_settlement_building`:
```gdscript
## Flat settlement-scoring bonus when a candidate tile can claim a bounty
## type the faction needs for a bounty-locked tech (designer directive:
## the AI reaches for gate bounties deliberately). +15 ~ 7 hexes of
## dist_penalty -- redirects close calls without dominating raw income.
func _settlement_gate_bonus(tile_pos: Vector2i, wanted_types: Dictionary) -> int:
	if wanted_types.is_empty():
		return 0
	for b in BountySystem.bounties_claimable_at(tile_pos, true):
		if wanted_types.has(b.id):
			return 15
	return 0
```
In `_execute_ai_settlement_building`, before the scoring loop (:1086) build the set once:
```gdscript
		var wanted_gate_types := {}
		for entry in GameManager.research_system.get_bounty_locked_research(faction_id):
			for t in entry.missing_types:
				wanted_gate_types[t] = true
```
and inside the loop, after the `bounty_income` sum: `income_score += _settlement_gate_bonus(tile_pos, wanted_gate_types)`.
- [ ] **Step 4: Run the suite — expect PASSED.**
- [ ] **Step 5: Regressions + sim:** `test_settlement_founding`, `test_ai_economy`, `test_battle_determinism` (MATCH). Econ sim if present (`tests/tmp_econ_sim.gd -- 7 40`): report how many gated techs AI factions completed and whether any faction stalls research (0 completions by t40 = investigate before committing).
- [ ] **Step 6: Commit** `feat(ai): settlement scoring reaches for research-gate bounties`.

---

### Task 7: Docs sync + full battery

**Files:**
- Modify: `docs/bounty_gated_techs_design.md` (status header)
- Modify: `docs/special_resources_design.md` (bounty roster section — the leftover #26 doc-sync)

- [ ] **Step 1:** `bounty_gated_techs_design.md`: change the Status line to `Status: IMPLEMENTED 2026-08-01 — see docs/superpowers/plans/2026-08-01-bounty-gated-techs.md.` and add a short "As-built deviations" list (start-only gate per decision; 3 new types shipped; 30 gates; 2× map-absence fallback; leases via RESOURCE_LEASE terms shape; AI +15 settlement bonus; conquest-targeting weighting NOT implemented — deliberately deferred).
- [ ] **Step 2:** `special_resources_design.md`: update every mention of the tier-1 bounty roster/count (22 → 25 types) and add the three new entries to whatever roster table it carries; note `ROSTER_ROLL_PCT` still 66.
- [ ] **Step 3: Full battery** (all must print PASSED; determinism must print MATCH): `test_bounty_gated_techs`, `test_bounty_system`, `test_map_seed`, `test_landmarks`, `test_playtest_round2`, `test_ai_economy`, `test_settlement_founding`, `test_polish_pass`, `test_save_roundtrip`, `test_income_breakdown_equivalence`, `test_battle_determinism`.
- [ ] **Step 4: Commit** `docs(design): bounty-gated techs as-built + roster sync`.

## Self-Review

- Spec coverage: locked decision 1 (start-only) → Task 2 start_research choke point, no pause plumbing anywhere. Decision 2 (new types) → Task 1 + spread across 7 gates in Task 3. Decision 3 (lease trading REQUIRED) → Task 4 full propose/process/UI loop. Decision 4 (AI settlement priority) → Task 6. Design §5 UI → Task 5. §7 failure mode Option 1+3 → Task 2 effective_tech_cost + Task 5 map-absent labeling. §6 AI research blindness → get_available_research exclusion (Task 2) + get_bounty_locked_research feeding Task 6. #26 doc-sync → Task 7.
- Open design questions resolved by this plan (defaults, flag to designer in the final report): Q4 → Forsaken/TJ/Shardhorde got looser flavor matches (bone_fields/herbs/crystal_springs), shardhorde only 1 gate; Q5 → fallback cost (never a dead tech). Conquest-target weighting from §6 is OUT of scope (settlement weighting only — matches the locked directive's wording).
- Type consistency: `requires_bounty_types: Array[StringName]` everywhere; `faction_has_bounty_type(faction_id, type_id)`; `types_on_map(map)`; `is_bounty_locked(faction_id, data)`; `effective_tech_cost(data)` (no faction param — the fallback is map-scoped, not faction-scoped); `get_bounty_locked_research(faction_id)` returns `{data, missing_types}`; lease terms `{bounty_hex, bounty_id, gold_per_turn}`; `_settlement_gate_bonus(tile_pos, wanted_types)`.
- Known ordering hazards written into the tasks: Task 3's verification runs before the Task-2 in-memory mutation section (and that section restores `emp_aqueducts` to `[&"orchards"]`); Task 6's test completes sk_horse_lords prereqs before reading the wanted set; Task 1's test cleans planted bounties.
