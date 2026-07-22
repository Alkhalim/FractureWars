# Bounded Siege-Capture — Design

**Date:** 2026-07-22
**Branch:** city_management
**Status:** Approved design, pre-implementation

## Problem

The July 2026 trajectory study (`docs/trajectory_study.md`) diagnosed the game as
"stable but static and low-agency": the map barely moves and conquest almost never
completes. Its highest-leverage recommendation:

> Make winning a battle at a city actually take it in a bounded number of turns.

### Why conquest doesn't complete today

The siege flow is: army moves onto an enemy city hex → fights the garrison
(`battle_resolver.gd`) → on a win, `city_system.start_siege` fires → the siege
must be held **uninterrupted for `siege_threshold` (4–6) turns** →
`_process_sieges` calls `_capture_city`. The failure modes:

1. **The hold is fragile.** The last friendly army leaving resets `siege_turns`
   to 0 (`break_siege`); a relief army breaks it. 4–6 uninterrupted turns is a lot.
2. **Garrisons heal back.** A weakened/broken garrison respawns at 10% and regens
   +15%/turn (`city_system.gd:49-54`), so chip damage never sticks.
3. **The AI abandons its own sieges.** `_execute_ai_turn` re-picks "nearest enemy
   army, then nearest enemy region" every turn, so a besieging army wanders off the
   city under its feet before the siege matures.
4. **Composition is irrelevant.** Any army sieges as well as any other; there is no
   payoff to bringing siege-capable troops, and no attrition pressure to force
   resolution.

## Approach (chosen: "C — meter on existing plumbing")

Reinterpret the existing `CityState.siege_turns` as **accumulated siege pressure**
(a float, in siege-turn units) rather than a raw turn counter, measured against the
**unchanged** `siege_threshold`. `_process_sieges` already captures at
`siege_turns >= siege_threshold`, and the Skulloath siege-choice dialog keys off the
same comparison — both keep working with no new capture path. Pressure **fills** from
fighting and blockading and **decays** when the besieger neglects the city, so a
committed attacker captures in a bounded window while a half-hearted one never does.

Rejected alternatives: **A** (net-new `siege_progress` state + parallel UI) pays for
a second system the threshold plumbing already provides; **B** (patch the binary
model) is cheap but leaves conquest a fragile step-function that won't move the
AI-vs-AI map.

## Mechanic

### Fill (Balanced model)

| Event | Δ pressure |
|---|---|
| Garrison **overrun** (attacker wins the assault, `battle_resolver.gd:158`) — also starts the siege if not active | **+2.0** |
| Relief-army battle on the siege hex, besieger wins on **points** (defender survives but lost proportionally more) | **+1.0** |
| Relief-army battle on the siege hex, **stalemate** (both survive, roughly even) | **+0.4** |
| **Passive presence** — besieger parked, no battle that turn (existing `_process_sieges` tick) | **+ siege-weight** (see below) |

**Win classification** uses `ArmyState.get_total_strength()` (sum of unit
`current_hp`). `battle_resolver.gd:80` already snapshots `atk_strength_pre` /
`def_strength_pre`; compare against post-battle strength. Point win = besieger
retained a materially higher fraction of strength than the defender (threshold a
tuning output, starting ~0.25 fractional gap); otherwise stalemate.

### Passive presence scales with army composition (siege weight)

The passive tick is **not** flat. A helper `_army_siege_weight(army) -> float`
(in `city_system`) reads fields that already exist — no `.tres` edits, no data
migration:

- **Siege engines / constructs** (`construct` tag **or** `tiles_per_entity >= 4`):
  heavy contribution — what actually breaks walls.
- **Heavy / monster / beast** tags: above baseline.
- **Infantry / ranged** (default line unit): baseline.
- **Light / fast** tags (raiders, skirmishers): reduced.

Normalize the summed factor by stack size so a plain infantry army earns the
**+0.75/turn baseline**; a siege-equipped stack trends toward **~+1.3/turn**
(falls in ~3 turns), a pure light-raider stack crawls at **~+0.35** (barely
progresses). *Bringing the right army* becomes the decision — the study's point
that conquest armies should pay off, if equipped for it.

### Drain (Decay model)

Runs in `_process_sieges`, iterating **all** besieged cities (not only the current
besieger's), floored at 0 (never negative):

| Condition | Δ pressure |
|---|---|
| No besieger present on the hex | **−1.0/turn** |
| Relief army beats the besieger | **−2.0** |

**Departure no longer ends the siege.** Today `game_manager._check_siege_departure`
calls `break_siege` (setting `is_under_siege = false`, pressure to 0) the moment the
last besieger leaves the hex. Under the decay model, a besieger-absent siege instead
stays active with `is_under_siege = true` and drains at −1.0/turn; it only lifts when
pressure reaches 0 (or via an explicit break). So `_check_siege_departure` should
**stop force-breaking on departure** — decay in `_process_sieges` handles lapses, and
a returning attacker resumes where they left off.

`break_siege` is retained for **explicit** ends only — peace/alliance
(`start_siege` already refuses ALLIED/FRIENDLY targets), a friendly army retaking its
own city (`game_manager.gd:2272`), or pressure decaying to 0.

### Attrition each siege turn — besieged suffers more

In `_process_sieges`:

- **Besieger**: light attrition, ~2–3% `max_hp`/turn across units (supply/disease).
  The existing `jungle_traps` besieger attrition stacks on top for that building.
- **Besieged garrison**: heavier — `garrison_hp_ratio` **actively declines**
  (~8–10%/turn) rather than merely being regen-suppressed. Models starvation and
  makes a drawn-out siege progressively easier to storm, so even a stalled siege
  trends toward resolution.

Garrison regen (`city_system.gd:49-54`) stays gated on `not is_under_siege`, so it
only recovers once the siege actually lifts.

## AI (commit + persist)

In `_execute_ai_turn` (and the Skulloath `_execute_skulloath_ai` loop), **before**
re-targeting:

1. **Hold sieges in progress.** If the army sits on an enemy city with a live siege
   by its faction and pressure is rising (not stalled/hopeless), **stay** — skip
   re-targeting for that army this turn.
2. **Prefer near-complete sieges.** When choosing a target, weight enemy cities with
   an in-progress siege above fresh targets, so the AI finishes what it starts.

This is the change that actually makes the AI-vs-AI map move; the mechanic alone
only makes conquest *possible*.

## UI (meter + map badge)

- **City detail panel** (campaign_hud): a progress bar for a besieged city plus a
  "falls in ~N turns" readout (`ceil((threshold − pressure) / recent_fill_rate)`).
- **Map**: a small ring / number over any besieged city.
- **Toasts**: on siege start and capture-imminent ("next turn"). Reuses
  `EventBus.siege_started` / `siege_broken` / `city_captured`; add a lightweight
  `siege_progress_changed` signal (or read state on redraw) for the bar.

## Tuning loop

After the mechanic + AI work, run the AI-vs-AI sim
(`godot --headless --path . -s res://tests/tmp_econ_sim.gd -- <seed> <turns>`),
measure **cities changing hands per game** and **max single-faction city share**,
and iterate the tuning outputs until conquest resolves at a healthy rate **without**
a single-faction runaway. Targets:

- Cities **do** change hands across a game (vs. ~0 today).
- No faction runaway-snowballs the map by the endgame.

**Tuning outputs (not fixed now):** siege-weight multipliers, point-win strength
threshold, besieged-attrition rate.

If any battle-resolution math shifts, recapture determinism baselines:
`-s res://tests/test_battle_determinism.gd -- --baseline`.

## Scope guard (YAGNI)

In scope: pressure meter (fill/decay), composition weight, attrition, AI persistence,
UI, tuning. **Out of scope:** new resources, siege-weapon items, diplomacy changes,
new unit data fields. Pressure comes from armies and battles that already exist.

## Touched surfaces

- `scripts/systems/campaign/city_system.gd` — `_process_sieges` (fill/decay/attrition),
  `_army_siege_weight`, `break_siege` (no hard reset), garrison regen/decline.
- `scripts/systems/battle/battle_resolver.gd` — award pressure on garrison overrun and
  classify relief-army outcomes.
- `scripts/autoloads/game_manager.gd` — `_check_siege_departure` stops force-breaking on
  besieger departure (decay lifts the siege at 0 instead).
- `scripts/autoloads/turn_manager.gd` — `_execute_ai_turn` / `_execute_skulloath_ai`
  siege persistence + target weighting.
- `scripts/autoloads/event_bus.gd` — optional `siege_progress_changed` signal.
- `scenes/campaign/campaign_hud.gd` — city-panel meter, map badge, toasts.
- `tests/` — sim-driven tuning; determinism baselines if battle math changes.
