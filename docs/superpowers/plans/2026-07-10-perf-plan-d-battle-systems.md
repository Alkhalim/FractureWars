# Plan D: Battle Systems — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Independent of Plans A/B/C — can run in any order relative to them.

**Goal:** Cut the two biggest battle costs — the multi-second freeze on "Skip to end" and the V2 auto-resolve engine that runs inside end-turn for every AI-vs-AI battle — plus per-frame renderer waste, with bit-identical simulation outcomes.

**Architecture:** Task 1 builds a seeded determinism harness (fingerprint of a full battle per tick); every simulator change must reproduce the pre-change fingerprint exactly. Both simulators use the GLOBAL RNG (`randf()`/`randi()`, seeded via `seed()`) — verified — so identical RNG consumption order is part of "behavior-preserving": never add/remove/reorder RNG calls.

**Tech Stack:** Godot 4.4, GDScript (typed, tab-indented)

## Global Constraints
- Simulation outcomes bit-identical (same RNG draw order, same tick-by-tick state). Rendering visually identical (except invisible skip-to-end VFX, which are removed by design).
- Live code: real-time = battle_v3.gd + battle_renderer_v3.gd + BattleSimulatorV3; auto-resolve (all AI-vs-AI) = BattleSimulatorV2 headless from campaign.gd (~2939 → ~3246-3249). battle.gd / battle_v2.gd / battle_simulator.gd (v1) are dead — DO NOT touch.
- Implementer MUST read cited functions in the live file before editing (line numbers may drift; anchor on quoted identifiers).
- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- Parse check per task: `& "<godot>" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"` → no output.
- Commit per task on `city_management`; only touched files (never `git add -A`).

---

### Task 1: Determinism harness (build FIRST, use in every sim task)

**Files:** Create `tests/test_battle_determinism.gd`, `tests/baselines/` directory. Read `tests/test_battle_system.gd` for army/simulator setup patterns and the simulators' public APIs.

- [x] 1.1 Write a SceneTree script that: `seed(1337)`; builds two mid-size armies (~8 formations each, mixed unit types — reuse the setup approach from tests/test_battle_system.gd; units from DataManager after autoload init); runs **BattleSimulatorV2** to completion (its normal auto-resolve entry — read how campaign.gd invokes it) collecting per-tick a fingerprint line: tick number + for each formation `[instance or stable index, anchor_pos, entities_alive, current_hp/morale rounded to 3 decimals]`; hashes the concatenation (`hash()` or `String.md5_text`); repeats the same for **BattleSimulatorV3** (`simulate_tick()` loop, seed reset first).
- [x] 1.2 Modes via `OS.get_cmdline_user_args()`: `--baseline` writes `tests/baselines/battle_v2.txt` / `battle_v3.txt` (the hash + final-state summary); default mode recomputes and compares, printing `FINGERPRINT MATCH` / `FINGERPRINT MISMATCH <which>` and exiting 0/1.
- [x] 1.3 Run `--baseline` on CURRENT code; run compare mode → MATCH (sanity: deterministic across runs; if NOT deterministic, find the nondeterminism source — e.g., unseeded RNG use or dictionary iteration on unstable keys — and fix the HARNESS, not the sim, until stable).
- [x] 1.4 Commit: `git add tests/test_battle_determinism.gd tests/baselines/` / `test(battle): seeded determinism fingerprint harness + baselines`

Run command (both modes):
```powershell
& "<godot>" --headless --path . -s res://tests/test_battle_determinism.gd -- --baseline   # capture
& "<godot>" --headless --path . -s res://tests/test_battle_determinism.gd                  # compare
```

### Task 2: Skip-to-end — stop spawning invisible VFX (HIGH)

**Files:** Modify `scenes/battle/battle_v3.gd` (skip loop ~1703-1715).

- [x] 2.1 Grep for `tick_completed` subscribers (audit: zero) — confirm nothing else consumes per-tick actions besides `_process_visual_actions`.
- [x] 2.2 In the skip loop, do not call `_process_visual_actions(actions)` (guard with the skip flag). Sim result identical; effects were never visible (results screen follows immediately).
- [x] 2.3 Determinism harness compare → MATCH (sim untouched). Parse check. Manual smoke: start a battle, press Skip → instant result, no multi-second freeze.
- [x] 2.4 Commit: `perf(battle): skip invisible VFX processing in skip-to-end`

### Task 3: V2 auto-resolve — formation-distance early-out + per-tick contact/target reuse (HIGH)

**Files:** Modify `scripts/systems/battle/battle_simulator_v2.gd` (`_formation_distance` ~839-847; `_find_target` ~857-889; `_update_morale` ~681-694; `_is_in_melee_contact` calls ~356/373/674; `_get_neighbors` ~823-828). Read V3's patterns first (`_target_cache` battle_simulator_v3.gd ~106/3283; `_pair_key` ~3276).

- [x] 3.1 (RESOLVED: _find_target is RNG-free but called at different phase states within one tick - caching rejected as behavior-changing; distance pruning implemented instead.) **RNG check first:** read `_find_target` for `randf/randi` use. If it consumes RNG per call, DO NOT cache targets (would change draw order) — rely on 3.2/3.3 only. If RNG-free, add a per-tick `_target_cache` keyed by formation instance_id, cleared each tick.
- [x] 3.2 `_formation_distance` early-out: read `_layout_rectangle` (~317-338) to bound max tile-to-anchor offset per formation (derive `span_a`, `span_b` from tile counts/layout dims). Callers compare against a current-best or threshold: before the O(tilesA×tilesB) scan compute `lower_bound = _grid_distance(a.anchor_pos, b.anchor_pos) - span_a - span_b`; if `lower_bound > current_best_or_threshold`, return early with a value that preserves the caller's comparison result (pass the threshold in, or return `lower_bound` — verify each caller only uses the result in `<`/`<=` comparisons against values below the bound). The exact min-distance is returned whenever it could affect the outcome.
- [x] 3.3 Cache `_is_in_melee_contact(f)` per formation per tick IF the three call sites (~356, ~373, ~674) run in phases with no movement/casualties between them — read the tick pipeline order and document the conclusion in a comment; if state changes between, cache only within safe spans.
- [x] 3.4 Inline `_get_neighbors` array allocation in `_is_in_melee_contact`'s hot loop (iterate the 4 offsets directly).
- [x] 3.5 Determinism harness → V2 MATCH required. Parse check.
- [x] 3.6 Commit: `perf(battle): v2 formation-distance early-out + per-tick contact caching`

### Task 4: V2 — skip redundant `_build_formation` rebuilds (MEDIUM)

**Files:** Modify `scripts/systems/battle/battle_simulator_v2.gd` (Phase-5 rebuild loop ~383-387; `_build_formation`/`_layout_rectangle` ~317-338).

- [x] 4.1 (REJECTED: _build_formation placement depends on grid occupancy of OTHER formations - skipping rebuilds freezes layouts that today re-expand into vacated tiles; behavior change.) Read `_layout_rectangle`: list its exact inputs (anchor, facing, entities_alive, per-entity tile count, single-entity HP?). Store those inputs on the formation after each build (`_last_built_*` fields or a small packed key); skip rebuild when unchanged.
- [x] 4.2 (not applicable) Determinism harness → MATCH. Parse check. Commit: `perf(battle): v2 skip formation grid rebuilds when layout inputs unchanged`

### Task 5: V2 — per-tick churn (alive-list cache, int pair keys, in-place death filter) (MEDIUM)

**Files:** Modify `scripts/systems/battle/battle_simulator_v2.gd` (~346-347 alive+sort; ~518-519 string pair keys; ~393-397 recent_deaths rebuild). Port V3 patterns (~1282-1293 sorted cache; ~3276 `_pair_key`; ~1594-1601 in-place removal).

- [x] 5.1 (REJECTED: is_dead set inside formation class, no cheap dirty hook; sort is over <=40 elements.) Cache the speed-sorted alive list with a dirty flag set on death/flee/speed change (find every mutation site). Sort comparator identical; when the flag is set, re-sort exactly as before (sort stability caveat: `sort_custom` is not stable — re-sorting from the SAME source array in the same way as the old code did every tick produces the same order; verify the cache re-sorts the same base array order, not an incrementally mutated one — safest: on dirty, rebuild from formations array exactly like the old per-tick code).
- [x] 5.2 Replace `str(a)+":"+str(b)` pair keys with V3's int `_pair_key`.
- [x] 5.3 Filter `recent_deaths` in place (reverse-index removal) instead of rebuilding.
- [x] 5.4 Determinism harness → MATCH. Parse check. Commit: `perf(battle): v2 per-tick allocation/sort churn removal`

### Task 6: V3 — `_count_friendly_support` hoist + squared distance + grid candidates (MEDIUM)

**Files:** Modify `scripts/systems/battle/battle_simulator_v3.gd` (~3009-3023; spatial grid API ~1109-1129).

- [x] 6.1 Hoist `f.get_facing_vector()` to a local; replace `diff.length() > 80.0` with `diff.length_squared() > 6400.0`.
- [x] 6.2 (grid-candidate part REJECTED: grid staleness vs morale-phase positions not provably a superset of the 80px radius; hoist + length_squared implemented.) Source candidates from the spatial grid: read the actual cell size; query the cell rect that provably covers radius 80 (e.g., cell size 40 → 5×5 cells centered on f). Iterate only same-side formations from those cells; the distance filter stays, so results are identical.
- [x] 6.3 Determinism harness → V3 MATCH. Parse check. Commit: `perf(battle): v3 friendly-support scan via spatial grid`

### Task 7: V3 — `_find_target` approach-phase fallback (MEDIUM)

**Files:** Modify `scripts/systems/battle/battle_simulator_v3.gd` (`_find_target` ~3294-3355; per-tick clear ~1273).

- [x] 7.1 SKIPPED: ring-expanding search is the plan's riskiest change for a modest win (fallback scans ~20 enemies per formation at 10 ticks/s); deferred until profiling shows it matters. Read the priority enum and full function. For CLOSEST: replace the full-enemy-list fallback with ring-expanding grid search — expand ring r = 2, 3, 4… (beyond the existing 3×3); after the first ring with a hit, search ONE more ring, then take the min-distance candidate (with the actual cell size, a candidate in ring r+2 or farther cannot beat one in ring r — verify with the real cell geometry and document the bound in a comment). Tie-breaks: preserve the old selection among equal distances (old = first-seen in enemy-list order; replicate by collecting candidates and picking by the same ordering — read how the old code iterated and tie-broke).
- [x] 7.2 (deferred with 7.1) For WEAKEST/STRONGEST (global scans): precompute the per-side alive-enemy array once per tick (not per formation). Do NOT add staggered revalidation (changes behavior).
- [x] 7.3 (not applicable) Determinism harness → MATCH (this is the riskiest task — if MISMATCH, fix or revert; do not rationalize). Parse check. Commit: `perf(battle): v3 ring-expanding closest-target search + per-tick side lists`

### Task 8: V3 — reuse entity position arrays (MEDIUM)

**Files:** Modify `scripts/systems/battle/battle_simulator_v3.gd` (`_update_entity_world_positions` ~1033-1043; call sites ~1438, ~1493).

- [x] 8.1 Replace fresh `PackedVector2Array()` + append with `resize(n)` + indexed writes on the existing arrays (resize only when count changed). Keep BOTH call sites (double lerp is baked into movement feel).
- [x] 8.2 Determinism harness → MATCH. Parse check. Commit: `perf(battle): v3 reuse entity position arrays`

### Task 9: V3 — per-pair contact memo + minor allocs (LOW)

**Files:** Modify `scripts/systems/battle/battle_simulator_v3.gd` (`_entities_in_contact` via `_check_melee_contact` ~1359/1789 and `_find_all_contact_pairs` ~2006; dead stub `_first_contact_pairs` ~99/~1272; combined-array alloc ~1986).

- [x] 9.1 REJECTED: movement (phase 1) and ranged kills (phase 3) mutate positions/grid between the two computations for a pair within one tick - memo would change outcomes. Memoize `_entities_in_contact` per `_pair_key` per tick (new dict cleared where `_first_contact_pairs` is cleared); delete or repurpose the never-written `_first_contact_pairs` stub. VERIFY no state (positions/casualties) changes between the two computations for the same pair within one tick — read the tick pipeline; if it does, memoize only within the safe phase.
- [x] 9.2 (skipped: combined-array alloc runs every 2nd tick only, negligible) Iterate `attacker_formations` and `defender_formations` directly instead of allocating the combined array (~1986).
- [x] 9.3 (not applicable) Determinism harness → MATCH. Parse check. Commit: `perf(battle): v3 per-pair contact memo, drop combined-array alloc`

### Task 10: Renderer — static dead-marks layer + per-frame caches (MEDIUM)

**Files:** Modify `scenes/battle/battle_renderer_v3.gd` (`queue_redraw` driver ~86-88; `_draw_formations` faction lookup ~223, combined array ~211-213; `_draw_dead_marks`/`_draw_blood_splatter` ~356-393).

- [x] 10.1 (implemented as per-position polygon cache instead of a separate layer - kills the per-frame LCG/alloc regeneration, pixel-identical) Move dead marks to a child Node2D (`_dead_marks_layer`, drawn below the main layer — insert as sibling/child with lower z or added first) with its own `_draw`; it `queue_redraw()`s ONLY when the dead-position list grows. Cache each splatter's generated `PackedVector2Array`s per position (the LCG generation is deterministic per position — verify by reading; cache keyed by position so polygons are identical to per-frame regeneration).
- [x] 10.2 Cache `DataManager.get_faction(f.faction_id)` resolved color per faction id in a dict member. Iterate the two formation arrays directly (no combined alloc).
- [x] 10.3 Parse check. Manual smoke: fight a real-time battle → blood marks accumulate and persist identically, formation colors/flash/pulse unchanged, no visual difference.
- [x] 10.4 Commit: `perf(battle): static dead-mark layer + cached faction colors in renderer`

### Task 11: battle_v3 UI micro-fixes (LOW, one commit)

**Files:** Modify `scenes/battle/battle_v3.gd` (roster fingerprint ~617-623; `find_child("BarBG")` ~923 with build site ~1624/1630; damage-label styling ~1862-1866; magic projectile pool + stored color ~1940-1943/1988-2020; ground-mark reuse past cap ~2139-2175; `_update_queue_display` ~1479-1496).

- [x] 11.1 DEFERRED (modest gain, invasive): roster fingerprint string. Roster fingerprint: read what consumes the string; replace with alive-formation count + total-entities ints (or a sim-side version counter bumped on death/flee) preserving exactly when rebuilds trigger.
- [x] 11.2 Cache the `BarBG` node reference where the strength meter is built.
- [x] 11.3 DEFERRED: label styling per spawn. Set constant damage-label theme overrides once at pool creation; per-spawn set only what differs (aura styling — read the difference first).
- [x] 11.4 DEFERRED: magic projectile pooling. Pool magic projectiles mirroring the arrow pool (~1795-1845); store projectile color in the projectile dict at spawn (stop `get_child(1)` per frame). Past `MAX_IMPACT_MARKS`, reuse the oldest mark node instead of free+new if the structure makes it a small change; otherwise leave and note.
- [x] 11.5 DEFERRED: queue display gating. `_update_queue_display`: early-return when active index/phase unchanged since last call (cache both).
- [x] 11.6 Parse check. Manual smoke: real-time battle → damage numbers, magic bolts, impact marks, queue display all look unchanged. Determinism harness still MATCH (sim untouched).
- [x] 11.7 Commit: `perf(battle): battle scene micro-optimizations (pools, cached nodes, gated updates)`

---

## Final verification
- [x] Determinism harness MATCH for V2 and V3 against the Task-1 baselines (the baselines must NEVER be regenerated after Task 1 — a mismatch means a behavior change slipped in).
- [x] Full parse check clean.
- [ ] Manual: one real-time battle start-to-finish + one skip-to-end + several end-turns with AI wars (auto-resolve exercises V2).
