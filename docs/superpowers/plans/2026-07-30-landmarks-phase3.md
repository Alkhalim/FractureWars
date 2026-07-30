# Landmarks (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 7 Landmarks from `docs/special_resources_design.md`: exactly 5 spawn per map (max 1 per type), each adjacent to an independent city (spawned if needed), exploited via a unique faction-shared building in the Landmark's region, granting 7 unique rules; AI builds them and covets them in war scoring.

**Architecture:** A new all-static `LandmarkSystem` (third sibling of `BountySystem`/`SpecialResourceSystem`) owns the 7-type table, the 5-of-7 deterministic roll + scatter (runs FIRST, before specials and bounties), and `has_landmark(faction_id, landmark_id)` state resolution (own the region + unique building built in a region city). Flat effects (Sungold gold/noble-loyalty, Voidglass essence/loyalty) ride the buildings' data fields with zero code; the remaining rules hook the same sites Phase 2 used plus healing/growth/veterancy/socket aggregation.

**Deliberate deviations from the design doc (announce in the doc in Task 7):**
1. *Building location*: the unique building is built in a city of the Landmark's REGION (extractor pattern), not literally on the tile — no tile-building system exists and the adjacency-spawned independent city makes the region the natural gate.
2. *Tile art*: unique hand-made tile art is deferred; Phase 3 ships large unique per-Landmark map markers (the tile keeps its terrain). Art follow-up can use the generated-tile pipeline.
3. *Everfrost "immune to winter penalties"*: NO universal winter penalties exist in the codebase (all season effects are Gladehost-only — verified) — the immunity clause is dormant-by-design until a universal winter system exists; Phase 3 implements the "+10% defense in own territory during winter" clause.
4. *Dragonbone "+1 fear radius for units recruited in this region"*: deferred (no unit-origin tracking); the -15% monster/beast recruit discount ships.
5. *Landmark leasing*: deferred (specials leases already carry the diplomacy content; generalizing the lease treaty to landmarks is a clean follow-up).

**Tech Stack:** Godot 4.4 GDScript, headless SceneTree tests.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; tests `& "<godot>" --headless --path . -s res://tests/<name>.gd`; startup "SCRIPT ERROR: Compile Error" noise benign — only printed PASSED/FAILED verdicts count; autoloads via `root.get_node("/root/...")` in tests; run `--headless --path . --import` once after creating a new class_name script.
- ZERO RNG in map gen — coordinate hashes only. Landmark scatter runs FIRST (before `SpecialResourceSystem.scatter_specials`) in BOTH generator paths; specials AND bounties must skip landmark tiles.
- Save compat: new tile field `landmark_id` via `Dictionary.get(key, "")`; new BuildingData field defaults `&""`.
- Battle-sim edits must be inert when no faction holds a Landmark (fresh new_game) — verify `test_battle_determinism.gd` divergence stays EXACTLY the documented pre-existing signature (v2 line 2 / v3 line 12); do NOT regenerate baselines.
- Scene scripts (campaign.gd/campaign_hud.gd) compile only when the scene loads — windowed harness verification.
- Terrain ints: 0=PLAINS 1=FOREST 2=MOUNTAINS 3=DESERT 4=SWAMP 5=WETLANDS 6=TUNDRA 7=SHARD_WASTES 8=WATER 9=JUNGLE. Resources: 0=GOLD 1=IRON 2=TECHNOLOGY 3=FOOD 4=SHARD_ESSENCE 5=WOOD 6=CAPTIVES.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Landmark table, tile field, 5-of-7 scatter

**Files:**
- Create: `scripts/systems/campaign/landmark_system.gd`
- Modify: `scripts/systems/campaign/hex_map_data.gd` (TileState: `landmark_id` after `special_id`)
- Modify: `scripts/core/game_state.gd` (serialize/deserialize: one line each)
- Modify: `scripts/utils/map_generator.gd` (insert `LandmarkSystem.scatter_landmarks(map)` BEFORE the `SpecialResourceSystem.scatter_specials(map)` line in BOTH generators)
- Modify: `scripts/systems/campaign/special_resource_system.gd` (`_try_place`: skip tiles with `landmark_id != &""`)
- Modify: `scripts/systems/campaign/bounty_system.gd` (scatter loop: skip `landmark_id != &""` next to the special skip)
- Test: `tests/test_landmarks.gd` (new)

**Interfaces:**
- Produces: `LandmarkSystem.LANDMARK_TYPES: Dictionary` (id → `{name: String, terrains: Array[int], building_id: StringName, rule_text: String}`); `LandmarkSystem.scatter_landmarks(map: HexMapData) -> void`; `TileState.landmark_id: StringName`; `LandmarkSystem.SPAWN_COUNT := 5`.

- [ ] **Step 1: Write the failing test** — create `tests/test_landmarks.gd`:

```gdscript
extends SceneTree
## Tests for tier-3 Landmarks (Phase 3, docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_landmarks.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var map = _gm.state.hex_map

	# ── Exactly SPAWN_COUNT landmarks, max 1 per type, terrain-fitting ──
	var placed := {}
	var coords_list: Array[Vector2i] = []
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.landmark_id == &"":
			continue
		coords_list.append(coord)
		_check(not placed.has(tile.landmark_id), "max 1 deposit of %s" % tile.landmark_id)
		placed[tile.landmark_id] = coord
		var def: Dictionary = LandmarkSystem.LANDMARK_TYPES.get(tile.landmark_id, {})
		_check(not def.is_empty(), "landmark %s in table" % tile.landmark_id)
		_check(int(tile.terrain) in def.get("terrains", []), "landmark %s on allowed terrain (%d)" % [tile.landmark_id, tile.terrain])
		_check(tile.special_id == &"" and tile.bounty_id == &"", "no other resource stacked on landmark tile")
		_check(tile.region_id != &"", "landmark tile belongs to a region")
	_check(placed.size() == LandmarkSystem.SPAWN_COUNT, "exactly %d landmarks spawn (got %d)" % [LandmarkSystem.SPAWN_COUNT, placed.size()])
	# Even spread: min pairwise distance
	for i in coords_list.size():
		for j in range(i + 1, coords_list.size()):
			if HexHelper.hex_distance(coords_list[i], coords_list[j]) < 12:
				_fails += 1
				print("FAIL: landmarks too close: %s %s" % [coords_list[i], coords_list[j]])

	# ── Determinism ──
	var fp := _fingerprint(map)
	_gm.new_game(&"empire")
	_check(_fingerprint(_gm.state.hex_map) == fp, "landmark scatter deterministic")

	# ── Serialization roundtrip + old-save compat ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fp, "landmark_id survives save/load")
	for key in saved:
		saved[key].erase("landmark_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].landmark_id != &"":
			any = true
	_check(not any, "old saves load with no landmarks")

	# ── Demo map: still exactly SPAWN_COUNT (or all placeable) ──
	_gm.new_game(&"empire", true)
	var demo_count := 0
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].landmark_id != &"":
			demo_count += 1
	_check(demo_count == LandmarkSystem.SPAWN_COUNT, "demo map places all %d landmarks (got %d)" % [LandmarkSystem.SPAWN_COUNT, demo_count])

	if _fails == 0:
		print("LANDMARKS TEST PASSED")
		quit(0)
	else:
		print("LANDMARKS TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].landmark_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].landmark_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
```

- [ ] **Step 2: Run — expect parse failure/FAILED.**

- [ ] **Step 3: Tile field + serializer** — `hex_map_data.gd` TileState after `special_id`:
```gdscript
	var landmark_id: StringName = &"" # tier-3 Landmark on this tile (special_resources_design)
```
`game_state.gd`: `"landmark_id": str(tile.landmark_id),` in serialize; `tile.landmark_id = StringName(tile_data.get("landmark_id", ""))` in deserialize.

- [ ] **Step 4: Create `scripts/systems/campaign/landmark_system.gd`**

```gdscript
class_name LandmarkSystem
extends RefCounted
## Tier-3 Landmarks (Phase 3 of docs/special_resources_design.md).
## All static. Exactly SPAWN_COUNT of the 7 types spawn per map (max 1 each),
## terrain-fitting and widely spread. A Landmark is exploited by owning its
## REGION and building its unique faction-shared building in a region city.

const SPAWN_COUNT := 5
const MIN_SPACING := 12  # relaxed progressively on small maps

const LANDMARK_TYPES := {
	&"dragonbone_fields": {name = "Dragonbone Fields", terrains = [3, 7], building_id = &"dragonbone_digsite", rule_text = "-15% recruit cost for monster/beast units"},
	&"everfrost_core": {name = "Everfrost Core", terrains = [6], building_id = &"rimeheart_bore", rule_text = "+10% army defense in owned territory during winter"},
	&"sungold_vein": {name = "Sungold Vein", terrains = [2, 3], building_id = &"sungold_mine", rule_text = "+15 gold/turn, but -2 noble loyalty in its province (greed)"},
	&"worldroot_nexus": {name = "Worldroot Nexus", terrains = [9, 1], building_id = &"rootwarden_enclave", rule_text = "Armies in the region heal double; +1 population growth in adjacent regions"},
	&"voidglass_rift": {name = "Voidglass Rift", terrains = [7, 4], building_id = &"rift_stabilizer", rule_text = "+3 shard essence/turn, +10% arcane research; -1 loyalty in its province (whispers)"},
	&"titan_forge_ruin": {name = "Titan Forge-Ruin", terrains = [2], building_id = &"reforged_foundry", rule_text = "Construct units cost -25% and start at Trained veterancy"},
	&"leyline_well": {name = "Leyline Well", terrains = [0, 1, 2, 3, 6, 9], building_id = &"attunement_circle", rule_text = "Socketed crystal bonuses count +50% stronger"},
}

static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass. Runs FIRST (before specials/bounties). Rolls 5 of the 7
## types deterministically, then places each with wide spacing, relaxing
## spacing progressively so small maps still fit all SPAWN_COUNT.
static func scatter_landmarks(map: HexMapData) -> void:
	# Deterministic 5-of-7 roll: sort type ids by hash, take the first SPAWN_COUNT
	var type_ids: Array = LANDMARK_TYPES.keys()
	var scored: Array = []
	for i in type_ids.size():
		scored.append([_hash(i * 271 + 5, 991), type_ids[i]])
	scored.sort()
	var selected: Array[StringName] = []
	for k in mini(SPAWN_COUNT, scored.size()):
		selected.append(scored[k][1])
	# Placement: rotating-start full scan per type, spacing relaxation chain
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	for t_idx in selected.size():
		var type_id: StringName = selected[t_idx]
		var def: Dictionary = LANDMARK_TYPES[type_id]
		var start := _hash(t_idx * 137 + 29, 771) % coords.size()
		var done := false
		for spacing in [MIN_SPACING, 9, 6, 4]:
			for k in coords.size():
				var coord: Vector2i = coords[(start + k) % coords.size()]
				if _try_place(map, coord, type_id, def, placed, spacing):
					done = true
					break
			if done:
				break

static func _try_place(map: HexMapData, coord: Vector2i, type_id: StringName, def: Dictionary, placed: Array[Vector2i], spacing: int) -> bool:
	var tile: HexMapData.TileState = map.tiles[coord]
	if tile.terrain == Enums.TerrainType.WATER or tile.landmark_id != &"":
		return false
	if tile.region_id == &"":
		return false
	if not (int(tile.terrain) in def.terrains):
		return false
	for p in placed:
		if HexHelper.hex_distance(coord, p) < spacing:
			return false
	tile.landmark_id = type_id
	placed.append(coord)
	return true
```

- [ ] **Step 5: Wire generators + skips** — `map_generator.gd`: insert `LandmarkSystem.scatter_landmarks(map)` immediately BEFORE `SpecialResourceSystem.scatter_specials(map)` in both generators. `special_resource_system.gd` `_try_place`: add `if tile.landmark_id != &"": return false` next to the special_id check. `bounty_system.gd` scatter loop: extend the skip to `if tile.special_id != &"" or tile.landmark_id != &"": continue`.

- [ ] **Step 6: Run** — `test_landmarks.gd` → LANDMARKS TEST PASSED; regressions `test_special_resources.gd` + `test_bounty_system.gd` → PASSED (their determinism checks compare same-order runs; still fine). If the demo map cannot fit 5 with the relaxation chain, extend the chain to `[MIN_SPACING, 9, 6, 4, 2]` — do not drop the count.

- [ ] **Step 7: Commit** — `feat(landmarks): table, tile field and 5-of-7 deterministic scatter` + footer.

---

### Task 1B: Per-campaign map seed (terrain shuffle + resource re-rolls)

*Interposed by user decision 2026-07-30: "the map itself should be regenerated each time. the rough shape should stay the same as do the starting positions and regions/characters but the terrains can be shuffled around a bit so not every time each city will have the same resource income etc. stay true to the rules about mountains and rivers and not creating blocked off areas etc."*

**Files:**
- Modify: `scripts/utils/map_generator.gd` — salt parameter threaded into the coordinate hash for TERRAIN-affecting passes only
- Modify: `scripts/core/game_state.gd` — `@export var map_seed: int = 0`
- Modify: `scripts/autoloads/game_manager.gd` — `new_game(faction_id, demo := false, map_seed := -1)`: `-1` → randomize (`randi() % 1000000` is fine here, this is setup not gameplay), store in `state.map_seed`, pass to the generator
- Modify: `scripts/systems/campaign/{bounty_system,special_resource_system,landmark_system}.gd` — scatter functions gain `salt: int = 0`; fold salt into their `_hash` calls AND their roster/roll hashes
- Modify: `tests/test_bounty_system.gd`, `tests/test_special_resources.gd`, `tests/test_landmarks.gd`, `tests/test_battle_determinism.gd`, `tests/test_faction_ai_flavor.gd`, `tests/test_save_roundtrip.gd`, `tests/tmp_econ_sim.gd`, `tests/tmp_screenshot_*.gd` — pin `map_seed = 0` in every existing `new_game` call (0 = EXACT legacy map)
- Test: `tests/test_map_seed.gd` (new)

**Interfaces:**
- Produces: `GameManager.new_game(faction_id: StringName, demo := false, map_seed := -1)`; `MapGenerator.generate_hex_map(regions, salt: int = 0)` and `generate_demo_hex_map(salt: int = 0)`; scatter signatures `scatter_bounties(map, salt := 0)` etc.
- INVARIANT: **salt 0 must reproduce the previous map byte-for-byte** (additive/xor salt folded so that 0 is the identity). This keeps battle-determinism baselines and all existing fingerprints valid.

**Scope rules (which passes get the salt):**
- SALTED: `_assign_terrain` (the per-tile terrain bucket hash), `_place_border_mountains`, `_thin_mountains`, `_carve_rivers`, `_create_wetland_bridges`, and the three resource scatters + their roster rolls (bounty ROSTER_ROLL gate + type rotation, specials pass-1 rotating starts + pass-2 gate, landmark 5-of-7 roll + placement starts).
- NOT salted: `_init_tiles`, `_carve_landmass` (rough shape stays), `_assign_regions` (regions stay), `_assign_realm_influence`, `_fix_region_pockets`/`_fix_terrain_pockets` (connectivity fixups run identically as algorithms — they may READ salted terrain but their own hash gates, if any, should use the salt too; connectivity guarantees come from the algorithm, not the hash).
- Implementation shape: add `salt: int = 0` parameter to `MapGenerator._hash_coord` (`_hash_coord(col, row, salt := 0)` folding e.g. `col_input = col + salt * 7919`) OR a module-static `_salt` set at generate entry and read inside `_hash_coord`, with the NOT-salted passes calling a raw variant. Read `_hash_coord`'s call sites first and choose the mechanically safest option; document the choice. The three scatter systems take `salt` as a parameter and fold it the same way (`_hash(x + salt * 7919, y)` — with salt 0 unchanged).

**`tests/test_map_seed.gd` must assert:**
1. Same seed twice → identical terrain fingerprint AND identical bounty/special/landmark fingerprints.
2. Seed 1 vs seed 2 → terrain fingerprints differ AND landmark placements differ (positions or roll).
3. Land/water mask identical across seeds 0, 1, 2 ("rough shape stays": every tile's `terrain == WATER` boolean matches seed 0).
4. For seeds 1, 2, 3: exactly `LandmarkSystem.SPAWN_COUNT` landmarks; every one of the 8 special types has ≥1 deposit; every landmark/special/bounty on legal terrain (reuse the per-type terrain assertions).
5. Region structure unchanged across seeds: every tile's `region_id` matches seed 0's; the set of city ids/names and each city's `region_id`+`faction_id` match seed 0 (positions may drift a tile if `_find_valid_city_pos` dodges shuffled terrain — assert `hex_distance(pos, seed0_pos) <= 2`).
6. Seed variance actually re-rolls the landmark SET eventually: across seeds 1..8, at least two different 5-of-7 selections occur (catches a roll that ignores the salt).
7. `new_game` default (no seed argument... call with -1) produces a map whose terrain fingerprint differs from seed 0 at least for one of three tries — SKIP this probabilistic check; instead assert `state.map_seed != 0` is possible: call `new_game(&"empire")` (default) and just assert `state.map_seed >= 0` and the game constructs without errors.

**Steps:** failing test → run → implement generator salt → implement scatter salts → new_game plumbing → pin seeds in ALL existing tests/harnesses (grep `new_game(` across tests/) → run the FULL battery (all suites incl. battle determinism byte-check at seed 0) → commit `feat(map): per-campaign seed shuffles terrain and resource rolls` + footer.

---

### Task 2: Independent-city adjacency guarantee

**Files:**
- Modify: `scripts/autoloads/game_manager.gd` — new `_ensure_landmark_neighbors()` called from `new_game` right after `_init_cities()` (line ~943, both demo and full paths — it's outside the `if not demo` block)
- Test: `tests/test_landmarks.gd` (append)

**Interfaces:**
- Consumes: `TileState.landmark_id`, the `_init_cities` construction pattern (game_manager.gd:1470-1544).
- Produces: after `new_game`, every landmark tile has a city (any owner) within hex-distance 2; if none existed, a new `&"independent"` city stands adjacent.

- [ ] **Step 1: Append failing test** (before the PASSED block; note the demo-map section already ran — add after it, then `new_game(&"empire")` to reset):

```gdscript
	# ── Every landmark has a city within distance 2 (guardian rule) ──
	_gm.new_game(&"empire")
	var map6 = _gm.state.hex_map
	for coord in map6.tiles:
		if map6.tiles[coord].landmark_id == &"":
			continue
		var found_city := false
		for cid in _gm.state.cities:
			if HexHelper.hex_distance(_gm.state.cities[cid].hex_pos, coord) <= 2:
				found_city = true
				break
		_check(found_city, "landmark at %s has a neighboring city" % coord)
```

- [ ] **Step 2: Run — expect FAILs for isolated landmarks.**

- [ ] **Step 3: Implement `_ensure_landmark_neighbors()`** in game_manager.gd (place near `_init_cities`; read `_init_cities` lines 1470-1544 first and mirror its CityState construction exactly — id via `state.generate_id()`, level 1, pop 80, class_loyalty init, `original_faction_id`, independent loyalty 60, garrison `[{unit_id = &"citizen_phalanx", count = 3}, {unit_id = &"toxotes", count = 1}]`, register in `state.cities`):

```gdscript
const LANDMARK_GUARD_NAMES := {
	&"dragonbone_fields": "Bonewatch",
	&"everfrost_core": "Rimehold",
	&"sungold_vein": "Gilder's Rest",
	&"worldroot_nexus": "Rootshade",
	&"voidglass_rift": "Whisperfall",
	&"titan_forge_ruin": "Cindervault",
	&"leyline_well": "Wellwarden",
}

## Every Landmark spawns guarded: ensure a city exists within 2 hexes,
## founding a small independent town beside it when none does.
func _ensure_landmark_neighbors() -> void:
	if state.hex_map == null:
		return
	for coord in state.hex_map.tiles:
		var tile: HexMapData.TileState = state.hex_map.tiles[coord]
		if tile.landmark_id == &"":
			continue
		var has_neighbor := false
		for cid in state.cities:
			if HexHelper.hex_distance(state.cities[cid].hex_pos, coord) <= 2:
				has_neighbor = true
				break
		if has_neighbor:
			continue
		# Pick a deterministic adjacent land tile (not the landmark itself)
		var spot := Vector2i(-1, -1)
		for n in HexHelper.get_neighbors(coord):
			var nt = state.hex_map.get_tile(n)
			if nt and nt.terrain != Enums.TerrainType.WATER and nt.terrain != Enums.TerrainType.MOUNTAINS \
					and nt.landmark_id == &"" and nt.special_id == &"" and nt.bounty_id == &"":
				spot = n
				break
		if spot == Vector2i(-1, -1):
			for n in HexHelper.get_neighbors(coord): # fallback: allow mountains
				var nt2 = state.hex_map.get_tile(n)
				if nt2 and nt2.terrain != Enums.TerrainType.WATER and nt2.landmark_id == &"":
					spot = n
					break
		if spot == Vector2i(-1, -1):
			continue # fully water-locked landmark: leave unguarded
		var city := CityState.new()
		city.city_id = state.generate_id()
		city.display_name = LANDMARK_GUARD_NAMES.get(tile.landmark_id, "Landmark Watch")
		city.region_id = tile.region_id
		city.hex_pos = spot
		city.level = 1
		city.population = 80
		city.faction_id = &"independent"
		city.original_faction_id = &"independent"
		city.loyalty = 60
		city.garrison_units = [
			{unit_id = &"citizen_phalanx", count = 3},
			{unit_id = &"toxotes", count = 1},
		]
		state.cities[city.city_id] = city
```
(ADAPT to the real CityState field names — read `_init_cities`; if it sets `class_loyalty` explicitly or uses a name field other than `display_name`, mirror it. Call `_ensure_landmark_neighbors()` in `new_game` immediately after `_init_cities()` and BEFORE `_recompute_all_territory()`.)

- [ ] **Step 4: Run** — LANDMARKS TEST PASSED + `tmp_econ_sim.gd -- 7 15` (no SCRIPT ERRORs; new cities don't break AI loops).
- [ ] **Step 5: Commit** — `feat(landmarks): guardian independent city beside every landmark` + footer.

---

### Task 3: Unique buildings, state queries, AI construction

**Files:**
- Modify: `scripts/resources/building_data.gd` (add `requires_region_landmark: StringName` after `requires_region_resource`)
- Modify: `scripts/systems/campaign/city_system.gd` — `get_available_buildings` + `start_building` (extend the existing `requires_region_resource` gates with the landmark equivalent)
- Create: `data/buildings/{dragonbone_digsite,rimeheart_bore,sungold_mine,rootwarden_enclave,rift_stabilizer,reforged_foundry,attunement_circle}.tres` (7 files)
- Modify: `scripts/systems/campaign/landmark_system.gd` (append queries)
- Modify: `scripts/autoloads/turn_manager.gd` `_execute_ai_city_management` (extend the extractor AI check to landmarks)
- Test: `tests/test_landmarks.gd` (append)

**Interfaces:**
- Produces: `LandmarkSystem.landmark_in_region(region_id: StringName) -> StringName`; `landmark_hex_in_region(region_id) -> Vector2i`; `region_has_landmark_building(region_id: StringName) -> bool`; `landmarks_of_faction(faction_id: StringName) -> Array[StringName]`; `has_landmark(faction_id: StringName, landmark_id: StringName) -> bool`; `describe(landmark_id) -> String`; `BuildingData.requires_region_landmark`.

- [ ] **Step 1: Append failing tests** (craft pattern mirrors the Phase 2 Task 2 test — find a landmark tile, give the player a city in that region + the building, set region tile owners, clear `_region_owner_cache`, sync `owned_regions`, city level 2):

```gdscript
	# ── Landmark buildings + state queries ──
	_gm.new_game(&"empire")
	var map7 = _gm.state.hex_map
	var lhex := Vector2i(-1, -1)
	for coord in map7.tiles:
		if map7.tiles[coord].landmark_id != &"":
			lhex = coord
			break
	var ltile = map7.get_tile(lhex)
	var ltype: StringName = ltile.landmark_id
	var lregion: StringName = ltile.region_id
	_check(LandmarkSystem.landmark_in_region(lregion) == ltype, "landmark_in_region finds it")
	_check(not LandmarkSystem.region_has_landmark_building(lregion), "no landmark building at start")
	var lcity: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			lcity = _gm.state.cities[cid]
			break
	lcity.region_id = lregion
	lcity.level = maxi(lcity.level, 2)
	var lbuilding: StringName = LandmarkSystem.LANDMARK_TYPES[ltype].building_id
	# Gate: offered only in the landmark's region
	var avail_l: Array[BuildingData] = _gm.city_system.get_available_buildings(lcity)
	var offered := false
	for b in avail_l:
		if b.id == lbuilding:
			offered = true
	_check(offered, "landmark building offered in its region")
	lcity.buildings.append(lbuilding)
	for rc in map7.get_region_tiles(lregion):
		map7.get_tile(rc).owner_faction = &"empire"
	map7._region_owner_cache.clear()
	var lfs: FactionState = _gm.state.faction_states[&"empire"]
	if not (lregion in lfs.owned_regions):
		lfs.owned_regions.append(lregion)
	_check(LandmarkSystem.region_has_landmark_building(lregion), "landmark building detected")
	_check(LandmarkSystem.has_landmark(&"empire", ltype), "has_landmark true when region owned + built")
	_check(ltype in LandmarkSystem.landmarks_of_faction(&"empire"), "landmarks_of_faction lists it")
	_check(not LandmarkSystem.has_landmark(&"skulloath", ltype), "other factions do not hold it")
	_check(LandmarkSystem.describe(ltype) != "", "describe returns rule text")
```

- [ ] **Step 2: Run — FAILs.**

- [ ] **Step 3: Field + gates** — `building_data.gd`: `@export var requires_region_landmark: StringName = &"" # tier-3 Landmark required in the city's region`. `city_system.gd` `get_available_buildings`, directly under the existing `requires_region_resource` gate:
```gdscript
		if building.requires_region_landmark != &"":
			if LandmarkSystem.landmark_in_region(city.region_id) != building.requires_region_landmark:
				continue
```
Same guard (`return false`) in `start_building` beside its `requires_region_resource` twin.

- [ ] **Step 4: The 7 .tres files** — universal (`faction_id = &""`), `category = &"economic"`, `required_capital_level = 2`, `build_time = 4`, `build_cost = {0: 220, 1: 60, 5: 40}` (T3-equivalent), `upkeep_cost = {0: 4}`, `requires_region_landmark` per type. Data-driven effects where possible:
  - `sungold_mine`: `income_bonus = {0: 15}`, `class_loyalty_bonus = {"nobles": -2}`
  - `rift_stabilizer`: `income_bonus = {4: 3}`, `class_loyalty_bonus = {"peasants": -1, "artisans": -1, "scholars": -1, "nobles": -1}`
  - the other five: `income_bonus = {}` (their rules are code hooks in Tasks 4-5); give each a one-sentence flavorful description. Full example (`data/buildings/dragonbone_digsite.tres`):
```
[gd_resource type="Resource" script_class="BuildingData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/building_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"dragonbone_digsite"
display_name = "Dragonbone Digsite"
description = "Scaffolds and pulleys strip the great skeletons. Whoever works these bones learns what killed their owners."
faction_id = &""
category = &"economic"
build_cost = {0: 220, 1: 60, 5: 40}
build_time = 4
income_bonus = {}
required_capital_level = 2
requires_region_landmark = &"dragonbone_fields"
upkeep_cost = {0: 4}
```
(Names: Rimeheart Bore, Sungold Mine, Rootwarden Enclave, Rift Stabilizer, Reforged Foundry, Attunement Circle.) Run `--import` after creating.

- [ ] **Step 5: LandmarkSystem queries** (append):
```gdscript
static func landmark_hex_in_region(region_id: StringName) -> Vector2i:
	var map = GameManager.state.hex_map
	if map == null or region_id == &"":
		return Vector2i(-1, -1)
	for coord in map.get_region_tiles(region_id):
		var tile = map.get_tile(coord)
		if tile and tile.landmark_id != &"":
			return coord
	return Vector2i(-1, -1)

static func landmark_in_region(region_id: StringName) -> StringName:
	var hex := landmark_hex_in_region(region_id)
	if hex == Vector2i(-1, -1):
		return &""
	return GameManager.state.hex_map.get_tile(hex).landmark_id

static func region_has_landmark_building(region_id: StringName) -> bool:
	var lm: StringName = landmark_in_region(region_id)
	if lm == &"":
		return false
	var building_id: StringName = LANDMARK_TYPES[lm].building_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id == region_id and city.buildings.has(building_id):
			return true
	return false

static func landmarks_of_faction(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	for region_id in fs.owned_regions:
		var lm: StringName = landmark_in_region(region_id)
		if lm != &"" and region_has_landmark_building(region_id):
			result.append(lm)
	return result

static func has_landmark(faction_id: StringName, landmark_id: StringName) -> bool:
	return landmark_id in landmarks_of_faction(faction_id)

static func describe(landmark_id: StringName) -> String:
	var def: Dictionary = LANDMARK_TYPES.get(landmark_id, {})
	return def.get("rule_text", "") if not def.is_empty() else ""
```

- [ ] **Step 6: AI construction** — `turn_manager.gd` `_execute_ai_city_management`: extend the existing extractor block (read it): after the extractor attempt, add the same pattern for landmarks — `var lm := LandmarkSystem.landmark_in_region(city.region_id); if lm != &"" and not LandmarkSystem.region_has_landmark_building(city.region_id):` look up `LANDMARK_TYPES[lm].building_id`, check it's in `get_available_buildings(city)`, `start_building`, `continue` on success.

- [ ] **Step 7: Run** — LANDMARKS TEST PASSED + `test_special_resources.gd` PASSED + `tmp_econ_sim.gd -- 7 40` (report whether any AI builds a landmark building — capitals start level 1 so it may take ~20+ turns).
- [ ] **Step 8: Commit** — `feat(landmarks): unique shared buildings, state queries and AI construction` + footer.

---

### Task 4: Effect hooks A — Dragonbone, Titan Forge, Voidglass arcane

**Files:**
- Modify: `scripts/systems/campaign/landmark_system.gd` (`recruit_discount_for`)
- Modify: `scripts/systems/campaign/city_system.gd` — `start_recruitment` discount block (~:1570-1584) + `_spawn_recruited_unit` (~:591-592)
- Modify: `scripts/systems/campaign/research_system.gd` — `process_research` (extend the shardglass arcane block)
- Test: `tests/test_landmarks.gd` (append)

**Interfaces:**
- Consumes: `has_landmark(faction_id, landmark_id)`.
- Produces: `LandmarkSystem.recruit_discount_for(faction_id: StringName, ud: UnitData) -> int` (dragonbone 15 for monster/beast tags + titan 25 for construct, cumulative).

- [ ] **Step 1: Append failing tests** (reuses `lcity`/`ltype` state from Task 3 — re-craft with SPECIFIC landmark types by overwriting `ltile.landmark_id` and swapping the building, exactly like the Phase 2 Task 3 test did with deposits):

```gdscript
	# ── Effect hooks A ──
	lcity.buildings.erase(lbuilding)
	ltile.landmark_id = &"dragonbone_fields"
	lcity.buildings.append(&"dragonbone_digsite")
	var beast_ud := UnitData.new()
	beast_ud.tags = ["monster", "beast", "melee"]
	var inf_ud2 := UnitData.new()
	inf_ud2.tags = ["infantry", "melee"]
	_check(LandmarkSystem.recruit_discount_for(&"empire", beast_ud) == 15, "dragonbone discounts monsters 15%")
	_check(LandmarkSystem.recruit_discount_for(&"empire", inf_ud2) == 0, "no dragonbone discount for infantry")
	lcity.buildings.erase(&"dragonbone_digsite")

	ltile.landmark_id = &"titan_forge_ruin"
	lcity.buildings.append(&"reforged_foundry")
	var con_ud := UnitData.new()
	con_ud.tags = ["construct", "melee"]
	_check(LandmarkSystem.recruit_discount_for(&"empire", con_ud) == 25, "titan forge discounts constructs 25%")
	# Trained veterancy on spawn
	var spawned := _gm.city_system._spawn_recruited_unit(lcity, &"legionary", &"empire")
	# _spawn_recruited_unit may return void — instead find the army/garrison it went to;
	# simpler: construct the veterancy check via a direct helper call if available.
	# Assert via the army at the city hex:
	var vet_ok := false
	var at_army = _gm.get_army_at_tile(lcity.hex_pos)
	if at_army and at_army.units.size() > 0:
		var last_unit = at_army.units[at_army.units.size() - 1]
		var last_ud = root.get_node("/root/DataManager").get_unit(last_unit.unit_data_id)
		if last_ud and last_ud.tags.has("construct"):
			vet_ok = last_unit.veterancy_level >= 1
		else:
			vet_ok = last_unit.veterancy_level == 0  # non-construct unaffected
	else:
		vet_ok = true  # spawn path differs; hook verified by reading (note in report)
	_check(vet_ok, "titan forge veterancy consistent")
	lcity.buildings.erase(&"reforged_foundry")

	ltile.landmark_id = &"voidglass_rift"
	lcity.buildings.append(&"rift_stabilizer")
	_check(LandmarkSystem.has_landmark(&"empire", &"voidglass_rift"), "voidglass held")
	lcity.buildings.erase(&"rift_stabilizer")
	ltile.landmark_id = ltype
```
(IMPORTANT for the implementer: `_spawn_recruited_unit`'s actual signature/return and where the unit lands must be read from city_system.gd — adapt the veterancy assertion to reality; a construct unit id from any faction roster may be needed instead of `legionary`. If a clean assertion isn't possible without heavy scaffolding, assert the DISCOUNT paths strictly and verify the veterancy line by code-reading, documenting that in the report.)

- [ ] **Step 2: Run — FAILs on missing recruit_discount_for.**

- [ ] **Step 3: Implement**

`landmark_system.gd`:
```gdscript
## Dragonbone: -15% for monster/beast. Titan Forge: -25% for constructs.
static func recruit_discount_for(faction_id: StringName, ud: UnitData) -> int:
	var total := 0
	if (ud.tags.has("monster") or ud.tags.has("beast")) and has_landmark(faction_id, &"dragonbone_fields"):
		total += 15
	if ud.tags.has("construct") and has_landmark(faction_id, &"titan_forge_ruin"):
		total += 25
	return total
```

`city_system.gd` `start_recruitment`, after the SpecialResourceSystem discount line:
```gdscript
	total_discount_pct += LandmarkSystem.recruit_discount_for(city.faction_id, unit_data)
```

`city_system.gd` `_spawn_recruited_unit`, after `instance.init_from_data(...)`:
```gdscript
	# Titan Forge-Ruin: constructs muster already Trained
	if unit_data.tags.has("construct") and LandmarkSystem.has_landmark(faction_id, &"titan_forge_ruin"):
		instance.veterancy_level = 1
		instance.experience = UnitInstance.VETERANCY_XP_THRESHOLDS[0]
```

`research_system.gd` `process_research`, extend the existing arcane block (shardglass) to include voidglass:
```gdscript
	if data.research_category == &"arcane":
		var arcane_bonus := SpecialResourceSystem.modifier_strength(faction_id, &"shardglass")
		if LandmarkSystem.has_landmark(faction_id, &"voidglass_rift"):
			arcane_bonus += 0.10
		if arcane_bonus > 0.0:
			...existing accumulation...
```
(Read the current shardglass code from P2T3 — it folded into the culture-bonus local; extend that same local coherently.)

- [ ] **Step 4: Run** — LANDMARKS TEST PASSED + regressions (`test_special_resources.gd`, `test_bounty_system.gd`).
- [ ] **Step 5: Commit** — `feat(landmarks): dragonbone, titan forge and voidglass effect hooks` + footer.

---

### Task 5: Effect hooks B — Everfrost, Worldroot, Leyline

**Files:**
- Modify: `scripts/systems/battle/battle_simulator_v3.gd` — after the deepiron block (Everfrost winter defense)
- Modify: `scripts/autoloads/turn_manager.gd` — `_heal_armies_in_settlements` (~:1781-1845, Worldroot double heal)
- Modify: `scripts/systems/campaign/city_system.gd` — `calculate_province_growth` (~:383-420, Worldroot adjacent growth)
- Modify: `scripts/systems/campaign/research_system.gd` — `get_research_effects` socket aggregation (~:184-187, Leyline ×1.5) + cache invalidation
- Modify: `scripts/autoloads/game_manager.gd` — `change_region_owner` (invalidate research caches on region transfer)
- Test: `tests/test_landmarks.gd` (append)

**Interfaces:**
- Consumes: `has_landmark`, `landmarks_of_faction`, `regions_adjacent` (hex_map_data.gd:145), `TurnManager.get_current_season()`.
- Produces: `LandmarkSystem.worldroot_region_of_faction(faction_id) -> StringName` (the region holding the faction's active Worldroot, or `&""`).

- [ ] **Step 1: Append failing tests**

```gdscript
	# ── Effect hooks B ──
	# Leyline: socket bonuses x1.5
	ltile.landmark_id = &"leyline_well"
	lcity.buildings.append(&"attunement_circle")
	_check(LandmarkSystem.has_landmark(&"empire", &"leyline_well"), "leyline held")
	# Craft: socket a research with a known socket_bonus and compare effects
	var rs = _gm.research_system
	var socketed_id: StringName = &""
	for rid in root.get_node("/root/DataManager").research:
		var rd = root.get_node("/root/DataManager").research[rid]
		if not rd.socket_bonus.is_empty():
			socketed_id = rid
			break
	if socketed_id != &"":
		var rd2 = root.get_node("/root/DataManager").research[socketed_id]
		lfs.completed_research.append(socketed_id)
		lfs.research_sockets[socketed_id] = rd2.socket_realm
		rs._invalidate_cache(&"empire")
		var eff_with: Dictionary = rs.get_research_effects(&"empire")
		lcity.buildings.erase(&"attunement_circle")
		rs._invalidate_cache(&"empire")
		var eff_without: Dictionary = rs.get_research_effects(&"empire")
		var key0 = rd2.socket_bonus.keys()[0]
		var base_v: float = float(rd2.socket_bonus[key0])
		_check(float(eff_with.get(key0, 0)) - float(eff_without.get(key0, 0)) >= base_v * 0.4,
			"leyline amplifies socket bonus (%s: %s vs %s)" % [key0, eff_with.get(key0, 0), eff_without.get(key0, 0)])
		lfs.completed_research.erase(socketed_id)
		lfs.research_sockets.erase(socketed_id)
		rs._invalidate_cache(&"empire")
	else:
		print("NOTE: no socketable research found; leyline assert skipped")
	ltile.landmark_id = ltype

	# Worldroot: adjacent-region growth qualifies (query-level)
	_check(LandmarkSystem.worldroot_region_of_faction(&"empire") == &"", "no worldroot held -> empty")
```

- [ ] **Step 2: Run — FAILs.**

- [ ] **Step 3: Implement**

`landmark_system.gd`:
```gdscript
static func worldroot_region_of_faction(faction_id: StringName) -> StringName:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return &""
	for region_id in fs.owned_regions:
		if landmark_in_region(region_id) == &"worldroot_nexus" and region_has_landmark_building(region_id):
			return region_id
	return &""
```

`battle_simulator_v3.gd`, directly after the deepiron block (same `if fs:` scope):
```gdscript
		# ── Everfrost Core (Landmark): winter defense in own territory ──
		if TurnManager and TurnManager.get_current_season() == 3:
			if LandmarkSystem.has_landmark(ud.faction_id, &"everfrost_core"):
				var ef_tile = GameManager.state.hex_map.get_tile(_battle_hex_pos) if GameManager.state.hex_map else null
				if ef_tile and ef_tile.owner_faction == ud.faction_id:
					f.defense += int(f.defense * 0.10)
```
NOTE the guard ORDER: season first (cheap), then has_landmark (region scans) — and has_landmark is false in any fresh new_game, keeping the hook inert for determinism (the determinism test runs at whatever season turn 1 is — month 0 → Spring → the branch shortcuts anyway; verify byte-identical output regardless).

`turn_manager.gd` `_heal_armies_in_settlements`: at the top of the per-army loop body compute once per faction (hoist BEFORE the loop): `var worldroot_region: StringName = LandmarkSystem.worldroot_region_of_faction(faction_id)`. In the city-heal branch and the field-heal branch, after `heal_amount` is computed:
```gdscript
			if worldroot_region != &"" and tile and tile.region_id == worldroot_region:
				heal_amount *= 2
```
(The city branch may use `city_at`'s tile — read the code; the army's own tile is what matters, it's already fetched at the loop top.)

`city_system.gd` `calculate_province_growth`, after the per-building flat bonuses:
```gdscript
	# Worldroot Nexus: +1 growth in its own and adjacent regions (any faction's
	# province benefits only from ITS OWN faction's worldroot)
	var wr_region: StringName = LandmarkSystem.worldroot_region_of_faction(faction_id)
	if wr_region != &"":
		if region_id == wr_region or GameManager.state.hex_map.regions_adjacent(region_id, wr_region):
			base_growth += 1
```

`research_system.gd` socket aggregation (~:184-187):
```gdscript
		if fs.research_sockets.has(research_id) and not data.socket_bonus.is_empty():
			var socket_mult := 1.5 if LandmarkSystem.has_landmark(faction_id, &"leyline_well") else 1.0
			for key in data.socket_bonus:
				combined[key] = combined.get(key, 0) + int(round(data.socket_bonus[key] * socket_mult))
```
Cache invalidation: in `game_manager.gd` `change_region_owner`, after ownership actually changes (inside the `if old_owner != new_owner:` block), add:
```gdscript
		# Landmark/lease-relevant caches: region transfer can change research effects
		research_system._invalidate_cache(old_owner)
		research_system._invalidate_cache(new_owner)
```
(Adapt to how game_manager references research_system — likely `research_system` member or `GameManager.research_system`; guard `old_owner != &""` per the function's own style.) ALSO: building completion already needs invalidation — find where a completed building lands in `city.buildings` in city_system's build-queue processing and add `if building.requires_region_landmark != &"": GameManager.research_system._invalidate_cache(city.faction_id)`.

- [ ] **Step 4: Run** — LANDMARKS TEST PASSED; regressions `test_special_resources.gd`, `test_bounty_system.gd`, `test_siege_pressure.gd`, `test_income_breakdown_equivalence.gd`; `test_battle_determinism.gd` divergence signature byte-identical to the documented pre-existing one (capture before/after and diff, like Phase 2 Task 4 did).
- [ ] **Step 5: Commit** — `feat(landmarks): everfrost, worldroot and leyline effect hooks` + footer.

---

### Task 6: UI — unique markers, tooltips, resource bar, war-score covet

**Files:**
- Modify: `scenes/campaign/campaign.gd` — `_create_bounty_markers` (third loop: landmark markers) + `_update_bounty_hover` (landmark branch takes precedence over special and bounty)
- Modify: `scenes/campaign/campaign_hud.gd` — `_update_bounty_bar_display` + `_on_bounty_bar_hover` (Landmarks section)
- Modify: `scripts/systems/campaign/diplomacy_system.gd` — war-score `+8` per Landmark the target holds
- Modify: `tests/tmp_screenshot_bounties.gd` (landmark phase)

**Interfaces:**
- Consumes: `LANDMARK_TYPES` (name/rule_text/building_id), `landmark_in_region`, `region_has_landmark_building`, `landmarks_of_faction`, `describe`, `GameManager.state.get_region_owner`.

- [ ] **Step 1: Markers** — in `_create_bounty_markers`, after the specials loop, iterate tiles with `landmark_id != &""` and build a UNIQUE marker per type: a large 6-point star (12px outer radius) with a per-Landmark color from:
```gdscript
const LANDMARK_COLORS := {
	&"dragonbone_fields": Color(0.85, 0.80, 0.65),
	&"everfrost_core": Color(0.55, 0.80, 0.95),
	&"sungold_vein": Color(0.95, 0.78, 0.25),
	&"worldroot_nexus": Color(0.35, 0.75, 0.35),
	&"voidglass_rift": Color(0.60, 0.35, 0.85),
	&"titan_forge_ruin": Color(0.80, 0.45, 0.25),
	&"leyline_well": Color(0.40, 0.85, 0.85),
}
```
Star polygon (alternating outer 12 / inner 6 radius, 12 points via a small loop), dark bg circle behind it, 3-letter glyph (`name.left(3)`), tile-center position, registered in `_bounty_markers` for fog refresh.

- [ ] **Step 2: Hover** — in `_update_bounty_hover`, the landmark branch FIRST (before special/bounty): name + "(Landmark)", `describe()`, region owner line, building status ("Built" / "Requires <building display_name> (build in a city of this region)"), fog-gated like the others.

- [ ] **Step 3: Resource bar** — extend the count with `LandmarkSystem.landmarks_of_faction(pid).size()` and the tooltip with a "Landmarks:" section (`"<name> — <rule_text>"`).

- [ ] **Step 4: War-score covet** — `diplomacy_system.gd` `_execute_ai_diplomacy_inner`, next to the affinity-special covet term:
```gdscript
	war_score += 8.0 * LandmarkSystem.landmarks_of_faction(other_id).size()
```

- [ ] **Step 5: Screenshot verification** — extend `tests/tmp_screenshot_bounties.gd`: pan to a landmark tile, fog off, force hover, screenshot `user://win_landmark_marker.png`. Run windowed; no SCRIPT ERROR naming the scene scripts. Headless `test_landmarks.gd` still PASSED.
- [ ] **Step 6: Commit** — `feat(landmarks): unique map markers, tooltips, resource bar and war-score covet` + footer.

---

### Task 7: Regression sweep + doc status

**Files:** `docs/special_resources_design.md`

- [ ] **Step 1:** Full battery with verdicts recorded: test_landmarks, test_special_resources, test_bounty_system, test_faction_ai_flavor, test_siege_pressure, test_save_roundtrip, test_income_breakdown_equivalence, test_battle_determinism (pre-existing signature ONLY), `tmp_econ_sim.gd -- 7 40` (zero SCRIPT ERRORs; note AI landmark-building activity), windowed tmp_screenshot_windows + tmp_screenshot_bounties.
- [ ] **Step 2:** Doc update: mark `3. **Phase 3 — IMPLEMENTED 2026-07-30** ...`; add "Phase 3 implementation notes" documenting the five deviations from the plan header (building-in-region-city, marker art placeholder pending hand-made tiles, Everfrost immunity dormant (no universal winter penalties exist), Dragonbone fear rider deferred, Landmark leasing deferred) + follow-ups.
- [ ] **Step 3:** Commit — `docs(resources): mark landmarks phase 3 implemented` + footer.

---

## Self-Review

- **Spec coverage:** 5-of-7 max-1 spawn (T1), even spread (T1 spacing test), neutral-city adjacency + fallback spawn (T2), unique shared buildings only-in-region (T3), all 7 rules (T3 data-driven Sungold/Voidglass flat parts; T4 Dragonbone/Titan/Voidglass-arcane; T5 Everfrost/Worldroot/Leyline), AI builds (T3) + war-score covet (T6), map/UI presentation (T6). Deviations declared in the header and documented in T7.
- **Placeholder scan:** the "adapt to real signature/field names" notes in T2/T4/T5 are live-code lookups with behavior fully specified; no TBDs.
- **Type consistency:** `has_landmark(faction_id, landmark_id) -> bool` used in T4/T5/T6 as defined in T3; `LANDMARK_TYPES[id].building_id` (T1) matches the 7 .tres ids (T3); `worldroot_region_of_faction` defined T5 before both its uses (same task); `recruit_discount_for` name mirrors the Bounty/Special siblings deliberately (different class namespace).
