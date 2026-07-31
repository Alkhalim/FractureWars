# Playtest Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four user-reported items (2026-08-01): ocean tiles worthless → coastal value made real; resource preview + placement color gradient are bounty-blind; tech detail dialog omits research cost; global cost rebalance (buildings/settlements ×1.5, units ×0.5) because armies are too precious relative to infrastructure.

**Architecture:** Ocean value gets BOTH a real income component (new coastal-harbor term in `calculate_city_income` — real income is region-based and never read tiles; the preview-only `TILE_INCOME` table must not silently diverge from reality) AND matching preview/AI updates. Bounty-awareness lands as one `BountySystem` helper consumed by every preview path. Cost sweep is a scripted data pass that runs LAST (after the building-rebalance plan, so it multiplies final values) with test-pin updates.

**Tech Stack:** Godot 4.4 GDScript. All scoping evidence (file:line) from the 2026-08-01 Explore report; re-verify lines before editing.

## Global Constraints

- Binary `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; headless `-s res://tests/<name>.gd`; compile noise benign; HANG = runtime crash (check "Invalid access"); pin seeds `new_game(..., 0)`; FOREGROUND only.
- ResourceType: 0=GOLD 1=IRON 2=TECH 3=FOOD 4=SHARD 5=WOOD 6=CAPTIVES. Terrain WATER=8.
- `test_battle_determinism.gd` must stay FINGERPRINT MATCH after every task (cost changes must not leak into battle fingerprints; if MATCH breaks, STOP and report).
- `test_income_breakdown_equivalence.gd` guards panel-vs-pipeline parity — any income change must go through the shared helpers.
- Task D (cost sweep) runs ONLY after the building-rebalance plan is fully committed.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task A: Ocean tiles — real coastal income + honest preview

**Files:** `scripts/systems/campaign/city_system.gd` (~:2067 TILE_INCOME, ~:2142/:2154/:2158 preview loops, ~:2171 `_get_primary_resource`, `calculate_city_income` ~:286-330); test append `tests/test_playtest_round2.gd` (new).

1. REAL income: new coastal-harbor component in `calculate_city_income`, via the extracted-pure-helper pattern (one source of truth — the breakdown UI derives from the same helpers): for the city's hex, count adjacent WATER tiles (6 neighbors, HexHelper): `coastal_food = water_neighbors * 2`, `coastal_gold = water_neighbors / 2` (int div). Add to income; expose in the breakdown as its own labeled line ("Coastal waters"). A landlocked city gains exactly 0.
2. PREVIEW: `TILE_INCOME` gains `WATER: {3: 4, 0: 1}`; `_get_primary_resource` WATER → 3 (FOOD); DELETE the water-skip in the adjacency loop (~:2154) so coastal adjacency counts.
3. AI settlement scoring (turn_manager.gd:982 caller) consumes the same preview — no separate change, but VERIFY the AI doesn't now try to settle ON water (`get_valid_settlement_tiles` still excludes WATER at :2119 — leave that).

- [ ] Failing tests: (a) city with N adjacent water tiles gains +2N food +N/2 gold over an identical landlocked control (build two synthetic cities on real map tiles, seed 0 — find a coastal vs inland spot by scanning hex_map); (b) `calculate_settlement_income_preview` on a tile with 2+ water neighbors > same tile's old bounty-free value (assert water contributes); (c) income breakdown still passes equivalence. RED → implement → GREEN.
- [ ] Regressions: test_income_breakdown_equivalence, test_save_roundtrip, test_battle_determinism (MATCH), econ sim `-- 3 25` (report: do AI factions settle coasts more?).
- [ ] Commit `feat(economy): coastal waters feed cities - real income + honest preview`.

---

### Task B: Bounty-aware preview numbers and placement colors

**Files:** `scripts/systems/campaign/bounty_system.gd` (new helper), `scenes/campaign/campaign.gd` (:5516-5545 gradient, :5633-5716 panel); test append.

1. New static helper `BountySystem.claimable_income_at(map, hex) -> Dictionary` (ResourceType→int): sum `BOUNTY_TYPES[id].income` over `bounties_claimable_at(hex)` — mirror `income_bonus_for_city`'s aggregation.
2. Gradient (campaign.gd:5521-5525): add the helper's summed value into `resource_values[coord]` so claimable-bounty tiles color green.
3. Panel (:5680-5705): add each claimable bounty's income numbers next to its name (e.g. "Fisheries (+8 Food)") and fold them into the "Total: %d resources/turn" headline.
4. Non-income bounty effects (loyalty, recruit discounts — `deferred` fields): show the describe() text as today; only numeric income joins the total. Do not invent numbers for deferred effects.

- [ ] Failing tests: helper returns fisheries' {3:8} on a hex adjacent to a fisheries bounty and {} on a bare hex (craft via BountySystem scatter on seed 0 — find a real bounty with `bounties_claimable_at`); RED → implement → GREEN. Screenshot: extend a placement-mode screenshot (model on tmp_screenshot_bounties.gd) showing the gradient + panel on a bounty-adjacent tile → coordinator judges.
- [ ] Regressions: test_bounty_system, test_battle_determinism (MATCH). Windowed run: no SCRIPT ERROR mentioning campaign.gd.
- [ ] Commit `fix(ui): settlement preview and placement colors count claimable bounties`.

---

### Task C: Tech detail dialog shows research cost

**Files:** `scenes/campaign/campaign_hud.gd` (~:7054-7055 in `_show_research_detail`); no new test file needed (windowed compile + screenshot gate).

- Amend the cost line to `"Research Cost: %d Tech  |  %d turns" % [data.tech_cost, data.research_time]` (hover-box format at :6824 is the model). Keep completed/in-progress status behavior as-is.
- [ ] Implement → windowed harness (tmp_screenshot_techtree.gd — force the detail dialog open on a tier-1 tech, screenshot) → no campaign_hud SCRIPT ERROR → coordinator judges screenshot → commit `fix(ui): research detail dialog shows tech-point cost`.

---

### Task D: Global cost sweep — buildings ×1.5, units ×0.5 (RUNS LAST, after building-rebalance plan)

**Files:** all `data/buildings/*.tres` (build_cost dicts), all `data/units/**/*.tres` (cost dicts), settlement/town founding costs (find where settlement founding cost is defined — game_manager or city_system constant), plus every test that PINS a cost value; script the sweep in `tests/tools_cost_sweep.gd` (one-off, deterministic, committed for provenance).

Rules:
- Building `build_cost`: each value ×1.5, `ceil` to int. UPGRADE costs too (they are build_costs of tier-2+ buildings). Upkeep UNCHANGED. Bounty/extractor/landmark buildings included (they're buildings).
- Unit recruit costs: each value ×0.5, `ceil` (min 1 if original ≥ 1). Upkeep UNCHANGED.
- Settlement/town founding cost ×1.5 (locate the constant; likely game_manager or turn_manager settlement founding).
- The recently-tuned specific values from the building-rebalance plan (e.g. resonant_crystal_forge upgrade {gold 40, food 30}) get swept like everything else — the ×1.5 applies on top by design; do NOT re-tune individual buildings here.
- Update EVERY test pin that asserts an exact cost (grep test files for the old values FIRST, list them in the report): test_building_rebalance pins, test_cinderguard_rework's "dragon trap still costs 20 iron" is a DILEMMA cost not a unit cost — unchanged; Frontier Orders fortress scrap costs unchanged (scrap, not build_cost).

- [ ] Step 1: write + run the sweep script printing a CSV of id,resource,old,new for review; commit the script alone first.
- [ ] Step 2: apply (script writes .tres values), run FULL battery: test_building_rebalance, test_cinderguard_rework, test_bounty_system, test_special_resources, test_landmarks, test_save_roundtrip, test_income_breakdown_equivalence, test_faction_ai_flavor, test_battle_determinism (MATCH — unit costs must not touch battle sim inputs; if they do, STOP).
- [ ] Step 3: econ sim `-- 7 40` + `-- 3 40`: verify AI factions still build (buildings constructed per faction > 0 by t40) and recruit MORE units than before; report army counts + any faction that stalls economically.
- [ ] Step 4: commit `balance(economy): buildings x1.5, units x0.5 - armies over infrastructure`.

## Self-Review
- Item #36 → Task A (real income + preview + AI parity); #35 → Task B (single helper, both UI paths); #38 → Task C; #37 → Task D with ordering constraint and pin-update discipline. No placeholders; exact values and formats given. Type consistency: `claimable_income_at` name used in B's steps; coastal term goes through shared income helpers (A) to keep the equivalence test green.
