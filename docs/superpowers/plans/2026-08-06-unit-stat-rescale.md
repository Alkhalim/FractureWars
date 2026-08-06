# Unit Stat Rescale ÷10 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Divide all combat-scale unit numbers by 10 ("easier designs in future, not half baked" — designer Option B, 2026-08-05) with function preserved: same battle outcomes within tolerance, no truncation-starved modifiers, honest re-baseline.

**Architecture:** One atomic change set: scripted data sweep (÷10 across ALL same-scale fields in units + flat combat bonuses in data) + formula audit (int-truncation → round-at-end) landed together, validated by an A/B outcome-parity harness captured BEFORE the change, then a deliberate determinism re-baseline. Costs/economy are NOT combat-scale and stay untouched.

**Tech Stack:** Godot 4.4 GDScript; headless battery; sweep-tool provenance convention.

## Global Constraints

- Godot binary `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; headless `-s res://tests/<name>.gd`; compile noise benign; FOREGROUND only; commits end `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- The determinism baseline WILL change — that is the point of Task R3's deliberate re-baseline. Until R3, do NOT regenerate baselines; R1 runs with MATCH intact, R2's commit is the only one allowed to break MATCH (its battery defers determinism to R3).
- Old saves: unit `current_hp` is state — R2 must add a load-time backfill (detect old-scale saves via a save-version bump or magnitude heuristic; divide current_hp by 10 on load) so old saves stay playable. NO other new state fields.
- Balance-parity bar: A/B winner agreement ≥ 18/20 probe matchups AND aggregate casualty-fraction deltas within ±10% mean; econ sim army counts within ±15% at t25. Misses → tune the formula conversions (not the data) until met, or STOP and report.

---

### Task R1: Baseline capture + inventory + sweep tool (no production changes)

**Files:** Create `tests/tools_rescale_units.gd` (sweep tool, print-mode only this task), `tests/test_rescale_parity.gd` (A/B harness: 20 deterministic matchups spanning tanky-few/many-cheap/ranged/monster/mixed/garrison-defense, records winner + per-side casualty fractions to `tests/baselines/rescale_ab_baseline.json` in CAPTURE mode), report inventory.

- [ ] Inventory ALL same-scale numbers, with file:field lists in the report: UnitData (attack, max_hp, hp_per_soldier, melee_defense, vs_attack_bonuses values, any flat aura/heal fields), BuildingData special_effects flat combat bonuses (flying_unit_attack_bonus etc. — enumerate by grepping the sim's flat reads), research effects flat combat values (most are _pct — list the exceptions), commander flat bonuses, hardcoded flat combat constants in battle_simulator_v3/battle systems (e.g. thunder wall +8, relic defense +3) — each classified: DIVIDE / KEEP (percentage or non-combat) / DECIDE (min-1 floors — list them, recommend keep-with-comment).
- [ ] Sweep tool print-mode CSV (id, field, old, new=round(old/10) with min 1 where zero would break).
- [ ] A/B harness CAPTURE run at current scale → baseline JSON committed. Battery: test_battle_determinism (MATCH — still intact this task), test_strength_meter_probe (9/10).
- [ ] Commit `feat(rescale): A/B baseline capture + inventory + sweep tool (print mode)`.

### Task R2: The atomic rescale (sweep + formula audit + backfill, one commit)

**Files:** Modify ~279 unit .tres + flagged building/research/commander data; battle_simulator_v3.gd + related (truncation sites); game_manager.gd (save-version/backfill); sweep tool gains apply mode.

- [ ] Formula audit: every `int(x * pct)` combat-modifier site → `roundi()` or float-accumulate-round-once (enumerate all sites in the report; the sim's ~15-150 attack range comment updates to ~2-15); flat constants from R1's DIVIDE list divided in code; min-1 floors kept with a `# scale-note` comment each (per R1 recommendation unless R1 found a breaker).
- [ ] Apply sweep (units + data bonuses). Save backfill: bump save version const (or magnitude heuristic if no version field exists — prefer adding a version int TO THE SAVE ROOT only if one already exists; else heuristic: any unit current_hp > its new max_hp × 1.5 ⇒ old save ⇒ ÷10 clamp) — verify with an old save fixture.
- [ ] A/B COMPARE run: new outcomes vs baseline JSON — meet the parity bar or tune (formula side only). Report the full 20-row table.
- [ ] Battery (determinism EXCLUDED, deferred to R3): test_unit_classes (data invariant holds post-sweep: hp_per_soldier==max_hp for squad_size==1), test_strength_meter_probe (re-run; if the meter's grid-searched constants need rescale-tuning, retune and report), test_save_roundtrip + old-save fixture, test_ai_economy, econ sim `-- 7 25` army-count deltas.
- [ ] Commit `balance(rescale): unit combat numbers /10 - data sweep, truncation audit, save backfill`.

### Task R3: Re-baseline + closure

- [ ] Deliberate determinism re-baseline (document rationale in the baseline file header + ledger: rescale epoch, designer-ordered); MATCH guard re-armed and verified green twice.
- [ ] Pinned-value test sweep (grep tests/ for hardcoded attack/hp magnitudes; update pins); UI spot-check windowed (unit cards, strength meter, battle HUD showing small numbers; hover info).
- [ ] Docs: unit_audit.md / design docs' stat references note the epoch; style-guide N/A. Full battery (all suites + re-armed MATCH). Commit `test(rescale): re-baseline + pin updates + docs`.

## Self-Review
- Option B's full promise covered: data sweep (R2), truncation audit (R2), A/B parity with pre-captured baseline (R1→R2), deliberate re-baseline (R3), pinned tests (R3). Save compat via backfill (R2). Costs/economy untouched (constraint). Min-1 floors get explicit DECIDE treatment (R1) instead of silent retention.
