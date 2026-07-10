# Plan A: Core Indexes & Caches — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Execute this plan FIRST** (before Plans B, C, D). Plans B/C rely on these caches existing (they stay correct without them, just slower).

**Goal:** Replace the linear scans that dominate end-turn time with dictionary indexes and invalidation-correct caches, changing zero gameplay outcomes.

**Architecture:** Every change keeps the public function signature identical and adds a cache/index *inside* the provider, so no call site changes except explicit invalidation hooks. Invalidation is deliberately coarse (clear whole cache on relevant mutation) — mutations are rare, reads are hot.

**Tech Stack:** Godot 4.4, GDScript (typed, tab-indented)

## Global Constraints
- All changes behavior-preserving; public signatures unchanged; identical results for every input.
- The implementer of each task MUST read the cited function and all cited call/mutation sites in the live file before editing — line numbers are from the audit and may have drifted slightly; anchor on the quoted code.
- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- Parse check after every task: `& "<godot>" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"` → expect no output.
- Test scripts extend SceneTree in `tests/`, run via `& "<godot>" --headless --path . -s res://tests/<name>.gd`. Autoloads (GameManager, DataManager, etc.) ARE available in this mode (verified via tests/probe_autoloads.gd). `GameManager.new_game(&"empire")` synchronously builds a full real game state to test against.
- Equivalence-test pattern for every cache task: keep a private brute-force copy of the OLD implementation in the test file, run both old and new over (a) a fresh `new_game` state, (b) the state after a relevant mutation + invalidation, and assert equal results for all inputs. Print `PASS`/`FAIL <detail>` and `quit(0/1)`.
- Commit after each task on branch `city_management`; add ONLY files the task touched (repo has unrelated modified .import files — never `git add -A`).

---

### Task 1: Movement cache-key correctness fix (MUST BE FIRST)

**Files:** Modify `scripts/systems/campaign/movement_system.gd` (~line 97 path cache key, ~line 196 reachable cache key; read whole file — it is small).

**Why first:** the path key `"from:to:faction:max_cost"` and reachable key `"from:mp:faction"` omit inputs that change results: `excluded_army_id`, mountain-crossing ability, and the per-army terrain-stride modifier (used near lines 165/228). Today aggressive invalidation masks this; every later task that raises cache hit rates would surface it as a gameplay bug.

- [x] 1.1 Read `find_path` and `get_reachable_tiles` fully; list every parameter/army-derived value that affects cost or passability (`excluded_army_id`, `can_cross_mountains` or equivalent, stride modifier — confirm exact names in code).
- [x] 1.2 Extend both cache-key strings to include all of them (stringify stride as e.g. `"%.3f"` to avoid float-format drift).
- [x] 1.3 Write `tests/test_movement_cache_keys.gd`: after `new_game`, pick two armies of the same faction on the same hex-ish area with different abilities (or fabricate two army dicts with differing stride/mountain flags); call the function for army 1 then army 2 with identical from/to; assert army 2's result equals a fresh uncached computation (invalidate cache between to obtain reference). PASS expected.
- [x] 1.4 Parse check. Commit: `git add scripts/systems/campaign/movement_system.gd tests/test_movement_cache_keys.gd` / `perf(move): include all result-affecting params in path/reachable cache keys`

### Task 2: Hex→city index — `get_city_at_hex` O(1)

**Files:** Modify `scripts/systems/campaign/city_system.gd` (`get_city_at_hex` lines ~1628-1633; `refresh_caches()` if present), `scripts/autoloads/game_manager.gd` (Sunblessed camp move writes `city.hex_pos` near line 1830). Test: `tests/test_city_hex_index.gd`.

**Interfaces (contract used by Plans B/C):** `get_city_at_hex(hex_pos: Vector2i) -> CityState` unchanged; new `_city_hex_index: Dictionary` and `func rebuild_city_hex_index() -> void` on CitySystem.

Current code (to replace with a dict lookup):
```gdscript
func get_city_at_hex(hex_pos: Vector2i) -> CityState:
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.hex_pos == hex_pos:
			return city
	return null
```

- [x] 2.1 Grep for every mutation of the city set and of `hex_pos`: `state.cities[` assignments, `state.cities.erase`, `hex_pos =` (repo-wide). Known sites: new-game city creation, settlement founding, city destruction (if any), Sunblessed camp move (`game_manager.gd:~1830`), save-game load/deserialize. List them in the commit message.
- [x] 2.2 Implement `rebuild_city_hex_index()` (clear + one pass over `GameManager.state.cities`); call it from every site found in 2.1 (rebuild-on-mutation is fine — mutations are rare). Make `get_city_at_hex` a dict `.get(hex_pos)` with a lazy `if _city_hex_index.is_empty() and not GameManager.state.cities.is_empty(): rebuild_city_hex_index()` guard so load order can't break it.
- [x] 2.3 `tests/test_city_hex_index.gd`: new_game → for every city assert `get_city_at_hex(city.hex_pos) == city`; for 50 random empty hexes assert null (compare against embedded brute-force loop); then move one city's `hex_pos`, rebuild, re-assert; then erase a city from the dict, rebuild, assert null at its old pos. PASS expected.
- [x] 2.4 Parse check. Commit: `perf(city): O(1) hex->city index behind get_city_at_hex`

### Task 3: Region-owner cache in HexMapData

**Files:** Modify `scripts/systems/campaign/hex_map_data.gd` (`get_region_owner` lines ~112-127). Test: `tests/test_region_owner_cache.gd`.

**Contract:** signature unchanged; new `_region_owner_cache: Dictionary` + `func invalidate_region_owner_cache() -> void` (clears all).

- [x] 3.1 Grep repo-wide for `owner_faction =` (tile ownership writes). Expected choke points: hex_map_data territory functions (`update_development_levels`, `set_region_city_territory`, cleanup functions), game_manager tile claims during army movement (`~2001-2005`), map generation. Add `invalidate_region_owner_cache()` after each mutation block (once per block, not per tile — e.g., at the end of a loop that claims tiles).
- [x] 3.2 Cache `get_region_owner(region_id)` results in the dict; return cached when present.
- [x] 3.3 `tests/test_region_owner_cache.gd`: new_game → for every region assert cached result == embedded brute-force copy of old implementation; flip one tile's `owner_faction` manually + call `invalidate_region_owner_cache()` → re-assert all regions. PASS expected.
- [x] 3.4 Parse check. Commit: `perf(map): cache get_region_owner with ownership-write invalidation`

### Task 4: Permanent memo for `regions_adjacent`

**Files:** Modify `scripts/systems/campaign/hex_map_data.gd` (`regions_adjacent` lines ~129-139, `build_region_cache()` line ~32). Test: `tests/test_region_adjacency.gd`.

- [x] 4.1 Memoize pair results in `_region_adjacency_cache: Dictionary` keyed by a canonical pair key (sort the two region ids, join). Region layout is static after map generation: clear the memo only in `build_region_cache()`.
- [x] 4.2 Test: new_game → assert memoized result equals embedded brute-force for all region pairs (or a 200-pair random sample if the full cross product is slow) — both true and false cases. PASS expected.
- [x] 4.3 Parse check. Commit: `perf(map): memoize static region adjacency`

### Task 5: Completed regions/cultures cache in GameManager

**Files:** Modify `scripts/autoloads/game_manager.gd` (`get_completed_regions` ~1605-1616, `get_completed_cultures` ~1619+). Test: `tests/test_completion_cache.gd`.

**Contract (Plan B relies on this):** signatures unchanged; new `_completion_cache: Dictionary` + `func invalidate_completion_cache() -> void`.

- [x] 5.1 Restructure internally: one pass over all cities building `region_id -> Dictionary[faction -> count/ownership]`, from which per-faction completed regions/cultures are derived and cached per faction. Old semantics must be replicated exactly — read the current functions first (note how partial ownership / REGION_CITIES is treated).
- [x] 5.2 Grep for city-ownership-change events: `city_captured` emission, settlement founding, any `transfer` function, city destruction, load-game. Call `invalidate_completion_cache()` at each.
- [x] 5.3 Test: new_game → assert equal to embedded brute-force old implementation for ALL faction ids (playable + minors); capture-simulate (reassign one city's `faction_id` + owned_cities arrays) + invalidate → re-assert. PASS expected.
- [x] 5.4 Parse check. Commit: `perf(gm): cache completed regions/cultures per faction with ownership invalidation`

### Task 6: Region/faction special-building effects cache (`apply_region_effects`)

**Files:** Modify `scripts/systems/campaign/city_system.gd` (`apply_region_effects` lines ~265-312, called from `calculate_city_income` ~line 256). Test: `tests/test_region_effects_cache.gd`.

- [x] 6.1 Read `apply_region_effects`. It scans all cities × buildings per call for ~6 special buildings (caravan_depot, astral_bazaar, relic guild, etc.). Precompute on first use per "state version": `_region_effects_cache` = `{region_id: {...}, faction_id: {...}}` aggregates, plus `func invalidate_region_effects_cache() -> void`.
- [x] 6.2 Invalidation sites (grep): building construction completion, demolition, city capture, settlement founding, load-game. Wire the calls.
- [x] 6.3 Rewrite `apply_region_effects` to read the aggregates; results must be numerically identical (same order of operations on the income dict — keep the same +/- and pct application sequence).
- [x] 6.4 Test: new_game → for every city assert `calculate_city_income(city)` equals embedded brute-force old `apply_region_effects` result; add a special building to one city's `buildings` + invalidate → re-assert all cities. PASS expected.
- [x] 6.5 Parse check. Commit: `perf(city): cache region/faction special-building effects`

### Task 7: Free-passage cache in DiplomacySystem

**Files:** Modify `scripts/systems/campaign/diplomacy_system.gd` (`has_free_passage` lines ~1342-1356). Test: `tests/test_free_passage_cache.gd`.

- [x] 7.1 Cache per canonical faction pair (int pair key or sorted string key — copy the relation-cache keying at `game_manager.gd:~1713`). New `invalidate_free_passage_cache()`.
- [x] 7.2 Grep every mutation of `diplomacy_state.treaties` (create, expire in `process_treaties`, break/cancel, war declarations that void treaties, load-game). Wire invalidation at each.
- [x] 7.3 Test: new_game → assert cached == brute-force for all faction pairs; add a FREE_PASSAGE treaty instance manually + invalidate → re-assert. PASS expected.
- [x] 7.4 Parse check. Commit: `perf(diplo): cache has_free_passage with treaty invalidation`

### Task 8: A*/Dijkstra micro-fixes — real binary insert + allocation-free neighbors

**Files:** Modify `scripts/systems/campaign/movement_system.gd` (insert loops ~182-186 and ~251-255; neighbor iteration ~137/~213), read `scripts/systems/campaign/hex_helper.gd` (get_neighbors ~30-39, DIRECTIONS_EVEN/ODD).

- [x] 8.1 Replace the linear "binary insert" scans with a true binary search producing the SAME insertion index the linear scan finds (sorted descending by f; preserve tie placement: the linear scan stops at the first element with `>= f` from the back — replicate exactly).
- [x] 8.2 Inline neighbor iteration in both hot loops: select `HexHelper.DIRECTIONS_EVEN/ODD` by row/col parity (match `get_neighbors` exactly, including order — expansion order affects tie-breaks) and iterate `coord + d` without building an array. Keep bounds checks identical.
- [x] 8.3 Test `tests/test_pathfinding_equivalence.gd`: new_game → for 30 random (from,to) pairs and 3 factions, assert `find_path` results (exact array equality) and `get_reachable_tiles` results (dict equality) match a reference obtained by running the OLD implementations (embed old versions of both functions in the test, adapted to call the same helpers). PASS expected.
- [x] 8.4 Parse check. Commit: `perf(move): true binary insert + allocation-free neighbor iteration`

### Task 9: Incremental army positions during multi-step movement

**Files:** Modify `scripts/autoloads/game_manager.gd` (`move_army_along_path` ~1929-2042, `_try_claim_shard` ~2027-2034, `_check_siege_departure` ~2017), `scripts/systems/campaign/movement_system.gd` (new `update_army_position`).

- [x] 9.1 Add `MovementSystem.update_army_position(army_id: StringName, from: Vector2i, to: Vector2i) -> void`: erase army from `_army_positions[from]` entry (remove key if empty), append to `_army_positions[to]`. Only act when `_cache_valid` is true.
- [x] 9.2 In `move_army_along_path`, replace the up-front `_cache_valid = false` with per-step `update_army_position` calls (after each hex step, matching where `army.hex_pos` is written). IMPLEMENTER MUST VERIFY: any code inside the step loop that creates/destroys armies (merges, battles) — after such events fall back to full invalidation for safety (`_cache_valid = false`) and stop incremental updates for the rest of that move.
- [x] 9.3 Index `active_shards` by hex: build a local dict `hex -> shard` once at the start of `move_army_along_path` (shards don't move) and use it in `_try_claim_shard`'s per-step check; keep the claim logic itself untouched.
- [x] 9.4 Verification: run `tests/test_pathfinding_equivalence.gd` again (positions cache feeds `get_armies_at_tile`) plus a new `tests/test_army_position_cache.gd`: new_game → move an army along a 5+ hex path via `move_army_along_path`, then assert for every army in the game `get_armies_at_tile(army.hex_pos)` contains it and stale positions return empty (compare against brute-force scan of all armies). PASS expected.
- [x] 9.5 Parse check. Commit: `perf(gm): incremental army-position cache updates + shard hex index during movement`

---

## Final verification (after all tasks)
- [x] Run all tests in `tests/test_*.gd` added by this plan → all PASS.
- [x] Full parse check → clean.
- [ ] Manual smoke: launch, new game, end 3 turns — end-turn time visibly reduced or unchanged, no errors in console; move armies, found a settlement, capture something if quick.
