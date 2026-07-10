# Plan B: Turn Processing, AI, Loyalty & Diplomacy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Execute AFTER Plan A** (this plan calls only public functions that Plan A made cheap; every task stays correct without Plan A, just slower).

**Goal:** Remove the per-turn O(armies × cities), O(armies × map) and repeated-recompute work from AI/turn processing without changing any AI decision or numeric outcome.

**Architecture:** Pure hoisting (loop-invariant values computed once per faction turn and passed down), per-turn memoization cleared at turn boundaries, and one threaded disk write. Private helper signatures may gain parameters; public APIs unchanged.

**Tech Stack:** Godot 4.4, GDScript (typed, tab-indented)

## Global Constraints
- Behavior-preserving: identical AI decisions, income, loyalty numbers. When in doubt whether a value can change mid-loop, DO NOT hoist — verify in code first.
- Implementer MUST read the cited function and call sites in the live file before editing; audit line numbers may have drifted — anchor on quoted code.
- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- Parse check after every task: `& "<godot>" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"` → no output.
- Tests: SceneTree scripts in `tests/` (autoloads available; `GameManager.new_game(&"empire")` builds real state). Equivalence pattern: embed the OLD computation in the test, assert new == old.
- Commit per task on `city_management`; add only touched files (never `git add -A`).

---

### Task 1: Hoist faction-wide census out of `_ai_recruit_with_composition`

**Files:** Modify `scripts/autoloads/turn_manager.gd` (`_ai_recruit_with_composition` ~720-751, caller `_execute_ai_city_management` ~line 718).

The helper recomputes per city: (a) tag census over all faction armies, (b) `total_units`, (c) `max_enemy_units` over all enemy factions. All three are loop-invariant across the caller's per-city loop (recruits only enter a build queue — IMPLEMENTER MUST VERIFY by reading the recruit path that no army/unit is created immediately).

- [x] 1.1 Compute census once in `_execute_ai_city_management` before its city loop; pass as parameters (e.g., `_ai_recruit_with_composition(faction_id, city, tag_counts, total_units, max_enemy_units)`).
- [x] 1.2 Test `tests/test_recruit_census.gd`: new_game → compute census via a copy of the old inline logic and via the new hoisted helper for 3 factions; assert equal dictionaries/ints. PASS.
- [x] 1.3 Parse check. Commit: `perf(ai): hoist faction census out of per-city recruit loop`

### Task 2: Hoist `_find_nearest_intruder` out of Tainted Jade per-army loop

**Files:** Modify `scripts/autoloads/turn_manager.gd` (`_execute_tainted_jade_ai`, loop ~1055-1090, call at ~1075; compare Gladehost pattern at ~979).

- [x] 2.1 Read the loop body: determine whether battles can occur inside the loop (they can — army moves may trigger battles). Hoist the intruder query before the loop; after any iteration in which a battle occurred (or the intruder army no longer exists / `is_instance_valid` fails / not in `state.armies`), recompute once. This preserves decisions: the only way the hoisted value could differ from per-iteration recomputation is if the intruder was destroyed or a new closer intruder appeared — new intruders cannot appear from our own moves; destruction only via battle, which triggers the recompute.
- [x] 2.2 Parse check. Manual verification note: run a few end turns with Tainted Jade in game (or trust the reasoning + parse). Commit: `perf(ai): hoist intruder scan out of tainted-jade army loop`

### Task 3: Set-based settlement sphere + region-scoped candidate scan

**Files:** Modify `scripts/systems/campaign/city_system.gd` (`is_in_settlement_sphere` ~1656-1661, `get_valid_settlement_tiles` ~1663-1685, `calculate_settlement_income_preview` ~1687-1724), `scripts/autoloads/turn_manager.gd` (`_execute_ai_settlement_building` sort ~839-840).

- [x] 3.1 Inside `get_valid_settlement_tiles`, precompute a blocked-set Dictionary once: for each city, add all hexes within the sphere radius (read the exact radius from `is_in_settlement_sphere`) using a hex-range iteration (check `HexHelper` for an existing range/ring helper; else iterate a bounding box and filter by the SAME hex_distance function the old code used). Then test candidate tiles against the set. Results must equal the old per-tile scan exactly.
- [x] 3.2 Same set-based treatment inside `calculate_settlement_income_preview` (build the set once per call).
- [x] 3.3 In `_execute_ai_settlement_building`, precompute `hex_distance` keys before the sort and sort on the keys with the same comparator direction (avoids recomputing distance in the comparator; ordering semantics identical).
- [x] 3.4 Test `tests/test_settlement_tiles.gd`: new_game → assert new `get_valid_settlement_tiles(faction)` equals embedded old implementation (exact array/set equality; sort both if old order was map-iteration order — verify and match order) for 3 factions. PASS.
- [x] 3.5 Parse check. Commit: `perf(city): set-based settlement sphere checks`

### Task 4: Invert Sunblessed proximity sweeps (armies×cities → armies×neighborhood)

**Files:** Modify `scripts/autoloads/turn_manager.gd` (faith proximity ~4678-4685; `_process_sunblessed_wisdom` ~4720-4745). Uses Plan A's O(1) `CitySystem.get_city_at_hex`.

- [x] 4.1 Read both loops; confirm the distance metric (hex_distance) and thresholds (3 and 2).
- [x] 4.2 Replace city-scans with neighborhood scans: for each army iterate all hexes with hex_distance ≤ threshold from the army (generate via the same hex-distance function — a dx/dy bounding box filtered by hex_distance is safe and obviously equivalent) and query `get_city_at_hex`. First-match semantics: the old loop returned/counted on the FIRST city found in dictionary order — IMPLEMENTER MUST VERIFY whether the result is a boolean/any-match (inversion trivially safe) or depends on WHICH city matches (then replicate: collect all matches and pick by the old iteration order, i.e., `state.cities` insertion order).
- [x] 4.3 Test `tests/test_sunblessed_sweeps.gd`: fabricate ~20 armies at random positions on a new_game map, assert old-logic vs new-logic identical outputs (faith deltas / wisdom counts) — extract both computations into testable local funcs in the test if the originals are inline.
- [x] 4.4 Parse check. Commit: `perf(ai): neighborhood-based sunblessed faith/wisdom sweeps`

### Task 5: Per-faction-turn accumulator for `_sum_building_special_effect`

**Files:** Modify `scripts/autoloads/turn_manager.gd` (`_sum_building_special_effect` ~3133-3144; cache clear in `_start_faction_turn` ~305).

- [x] 5.1 Add `_special_effect_sums_cache: Dictionary` (faction_id -> Dictionary[effect_key -> float/int sum]). On first call for a faction in a turn, do ONE pass over its cities × buildings accumulating ALL `special_effects` numeric keys; subsequent calls read the dict (`.get(key, 0)` matching old default). Clear the cache in `_start_faction_turn`.
- [x] 5.2 IMPLEMENTER MUST VERIFY: whether buildings can complete between two `_sum_building_special_effect` calls within one faction turn (building completion happens in city_system.process_turn — check its position relative to the faction-mechanic calls). If completion runs BEFORE all sum calls, cache is safe; if between, also clear the faction's cache entry on `building_completed` signal.
- [x] 5.3 Test `tests/test_special_effect_sums.gd`: new_game → for 3 factions × 3 effect keys assert cached sum == embedded old per-key loop. PASS.
- [x] 5.4 Parse check. Commit: `perf(turn): single-pass special-effect sums per faction turn`

### Task 6: Victory-check — verify Plan A cache suffices

**Files:** Read `scripts/autoloads/turn_manager.gd` `_check_victory_conditions` (~494-509) and `game_manager.get_completed_regions/cultures`.

- [x] 6.1 RESOLVED BY PLAN A TASK 5: _check_victory_conditions only calls the now-cached get_completed_regions/cultures; remaining work is O(factions) with trivial loops. No change needed.
- [x] 6.2 Skipped (no commit needed).

### Task 7: Threaded autosave disk write

**Files:** Modify `scripts/autoloads/turn_manager.gd` (`GameManager.save_game(0)` call ~421 in `_end_round`), `scripts/autoloads/game_manager.gd` (`save_game` ~652-668 and its serialize helpers).

- [x] 7.1 Read `save_game` end-to-end. Split into: `_serialize_save() -> <SaveResource/Dictionary>` (synchronous, main thread — MUST produce a snapshot with no shared mutable references to live state; verify `serialize_hex_map`/`serialize_state` produce fresh Dictionaries/Arrays — the audit found `duplicate(true)` already used for waypoints/temp effects; duplicate anything that isn't fresh) and `_write_save_to_disk(data, slot)` (ResourceSaver.save + metadata).
- [x] 7.2 (REVISED: threading rejected as unsafe — ResourceSaver serializes live state; switched autosave to binary .res with .tres load fallback instead.) Autosave path (slot 0) runs `_write_save_to_disk` on a background thread (`Thread.new()` stored as a member). Before starting a new save thread: if previous `is_alive()`/started, `wait_to_finish()` first (never drop a save). Manual saves stay fully synchronous. On quit: if a save thread is running, `wait_to_finish()` (hook `_exit_tree`/`NOTIFICATION_WM_CLOSE_REQUEST` — check what quit handling exists).
- [x] 7.3 Verification: `tests/test_threaded_save.gd`: new_game → call the autosave path → wait for thread completion → load the save file (existing load function) → assert key fields (turn number, faction count, a few city ids/positions, army count) match live state. PASS. Also manual: end a few turns, quit, relaunch, load autosave.
- [x] 7.4 Parse check. Commit: `perf(save): move autosave disk write off the main thread`

### Task 8: Loyalty province index + per-turn class-percentage memo

**Files:** Modify `scripts/systems/campaign/loyalty_system.gd` (`get_province_cities` ~6-12; `calculate_class_percentages` ~59-108; `_get_active_modifiers` ~258+; `calculate_province_loyalty` ~457).

- [x] 8.1 Add `_province_index: Dictionary` (key `"%s|%s" % [region_id, faction_id]` or packed key -> Array[CityState]) + `_province_index_turn: int` stamp. `get_province_cities` rebuilds the whole index in one pass over cities when the stamp != current turn counter (find the counter: TurnManager round/turn variable), else reads. All existing callers benefit with zero call-site changes.
- [x] 8.2 Memoize `calculate_class_percentages(city, faction)` per (city_id, turn-stamp). IMPLEMENTER MUST VERIFY its inputs (population, buildings, capital presence) cannot change between its calls within one faction turn — building completion order matters, same check as Plan B Task 5.2; if buildings complete mid-turn before later calls, clear memo on `building_completed`. Also clear on `city_captured`.
- [x] 8.3 Test `tests/test_loyalty_memo.gd`: new_game → for every player city assert memoized `calculate_class_percentages` == embedded old computation; simulate building completion + invalidate → re-assert. PASS.
- [x] 8.4 Parse check. Commit: `perf(loyalty): per-turn province index and class-percentage memo`

### Task 9: Border-tile-based `_get_neighbor_region_factions` + hoist triple call

**Files:** Modify `scripts/systems/campaign/loyalty_system.gd` (`_get_neighbor_region_factions` ~532-549; callers ~315, ~338, ~340).

- [x] 9.1 Precompute per region the static border-tile adjacency: `region_id -> Array[Vector2i]` of FOREIGN tiles adjacent to the region (tiles in other regions touching it). Build lazily once (static after map gen; clear if `build_region_cache` reruns). Per call, read only `owner_faction` of those tiles — same result set as scanning all region tiles × 6 neighbors.
- [x] 9.2 Hoist: the three call sites run within one `_get_active_modifiers` invocation for the same capital — compute once into a local and reuse (verify the three calls use identical arguments).
- [x] 9.3 Test: extend `tests/test_loyalty_memo.gd` — assert new result == embedded old implementation for every region with an owned capital. PASS.
- [x] 9.4 Parse check. Commit: `perf(loyalty): static border-tile adjacency for neighbor-faction checks`

### Task 10: Commander-presence check via cached faction armies

**Files:** Modify `scripts/systems/campaign/loyalty_system.gd` (~403-417).

- [x] 10.1 Read the check: WHICH factions' armies matter (owner only, or any)? If owner-only: replace all-army scan with `GameManager.get_all_faction_armies(faction_id)` (cached). If any-faction: keep but use per-hex position cache (`get_armies_at_tile`) over the province's city hexes instead of scanning all armies. Preserve the distance semantics exactly.
- [x] 10.2 Test: extend `tests/test_loyalty_memo.gd` with old-vs-new assertion for all capitals. Parse check. Commit: `perf(loyalty): use cached army lookups for commander presence`

### Task 11: Diplomacy strength memo

**Files:** Modify `scripts/systems/campaign/diplomacy_system.gd` (`_calculate_faction_strength` ~110-126, `get_strength_ratio` ~128-133, `execute_ai_diplomacy` ~1160-1251, `_evaluate_peace`/`_evaluate_alliance` ~839-849).

- [x] 11.1 Add `_strength_cache: Dictionary` cleared at the top of `execute_ai_diplomacy`. IMPLEMENTER MUST VERIFY: can execute_ai_diplomacy trigger battles or recruiting mid-tick (war declaration effects)? If yes, also clear the cache after any war declaration inside the tick. Memoize `_calculate_faction_strength` reads.
- [x] 11.2 Test `tests/test_diplo_strength.gd`: new_game → assert memoized == embedded old for all factions; mutate an army (add units) + clear → re-assert. PASS.
- [x] 11.3 Parse check. Commit: `perf(diplo): memoize faction strength per diplomacy tick`

### Task 12: Trade-route single-treaty helper + endpoint cache + per-turn income totals

**Files:** Modify `scripts/systems/campaign/diplomacy_system.gd` (`_execute_trade_relations` ~584-613, `get_top_produced_resource` ~510+, `get_faction_resource_income` ~529+, `_check_trade_interception` ~1496-1518, `get_active_trade_routes` ~1522-1554).

- [x] 12.1 Extract `_compute_trade_route(treaty) -> Dictionary` (closest city pair + A* path) from `get_active_trade_routes`; the latter maps it over treaties (unchanged output/order); `_check_trade_interception` computes only its own treaty's route.
- [x] 12.2 Cache route endpoints per treaty id in `_trade_route_cache` + `invalidate_trade_route_cache()`, called on: treaty add/remove/expire, any city ownership change / founding / destruction (same event sites as Plan A Task 5.2 — add calls next to `invalidate_completion_cache()`).
- [x] 12.3 Per-turn faction income totals: `_faction_income_cache: Dictionary` (faction -> per-resource totals via one pass over its cities' `calculate_city_income`), cleared at turn boundaries (same place Plan B Task 5 clears). Rewrite `get_top_produced_resource` and `get_faction_resource_income` to read it — first VERIFY both currently aggregate `calculate_city_income` identically (same filters); if one skips sieged cities and the other doesn't, cache both variants or keep the differing one uncached.
- [x] 12.4 Test `tests/test_trade_routes.gd`: new_game + manually add a trade treaty between two factions → assert `get_active_trade_routes()` new == embedded old (endpoints + path), `get_top_produced_resource`/`get_faction_resource_income` new == old for all factions. PASS.
- [x] 12.5 Parse check. Commit: `perf(diplo): per-treaty route computation, endpoint cache, per-turn income totals`

### Task 13: Standing/cooldown int keys (conditional)

**Files:** `scripts/systems/campaign/diplomacy_system.gd` (`_standing_key` ~59-70).

- [x] 13.1 SKIPPED: standing/cooldowns are @export string-keyed dicts persisted in save files (diplomacy_state.gd:4-7); key migration not worth it per plan condition. Grep save/load serialization for standings/cooldowns dictionaries. If the string keys are persisted in save files: SKIP this task (migration not worth it) and note why here. If not persisted: switch to int pair keys copying `game_manager.gd:~1713`.
- [x] 13.2 (not applicable) If done: parse check + quick save/load manual test. Commit: `perf(diplo): int pair keys for standings/cooldowns`

---

## Final verification
- [x] All `tests/test_*.gd` from Plans A+B PASS; full parse check clean.
- [ ] Manual (USER): new game, end 5 rounds; watch end-turn latency; play Tainted Jade or Sunblessed briefly if feasible.
