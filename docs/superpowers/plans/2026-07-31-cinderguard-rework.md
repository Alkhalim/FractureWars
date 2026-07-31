# Cinderguard Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (user-approved):** Fix the Cinderguard iron glut (~417 iron/turn vs ~35 sinks at turn 30) and the agency deficit (posture nudges fighting auto-centering into a dead zone, hidden combat thresholds, silent bonuses, interchangeable raid choices, invisible stakes) via the analyzed A→B→C packages, plus scrap transparency (scavenge_stockpile currently has zero UI presence).

**Architecture:** A is data-only cuts + one new dilemma option. B restructures vigilance into a player-set posture target (new FactionState field, auto-center removed, iron income and upkeep scale with chosen posture, battle thresholds aligned to UI values, feedback surfaced). C makes dragon raids name their target and differentiates the four choices with real costs. Scrap gets a top-bar element + explanatory tooltip. All numbers below come from the verified analysis (file:line references therein — `.superpowers/sdd` has the full audit; key sites: turn_manager.gd `_process_cinderguard_forge` ~:4529-4706, dilemma appliers :186-248, `city_system.gd:2416-2423`, `battle_simulator_v3.gd:580-602`, `campaign_hud.gd:1799-1802,1941-1956`).

**Tech Stack:** Godot 4.4 GDScript; headless tests; econ-sim balance verification.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; startup compile noise benign; tests pin map_seed; FOREGROUND only.
- BATTLE SIM: threshold changes must be inert at fresh new_game (vigilance starts 50 → no modifier under old OR new thresholds) — verify `test_battle_determinism.gd` stays FINGERPRINT MATCH.
- Save compat: new FactionState fields `@export` with defaults.
- Balance verification is part of the work: the econ sim must show Cinderguard iron income materially tamed (target: turn-30 recurring iron income under ~150/turn in balanced posture, under ~220 in war footing, vs ~417 today).
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1 (Package A): Halve the pumps, kill the hidden layer, add the smelt sink

**Files:**
- Modify: `data/buildings/ember_foundry.tres` (income iron 90→45; ALSO rename `display_name` "Frontier Armory II"→"Ember Foundry II" — an "armory" that produces iron reads wrong, per analysis)
- Modify: `data/buildings/volcanic_smelter.tres` (65→35), `cinder_mine.tres` (35→20), `magma_vent.tres` (28→16), `molten_core_forge.tres` (45→28)
- Modify: `scripts/systems/campaign/city_system.gd:2416-2423` — DELETE the hidden per-city vigilance iron layer (`+int(vigilance*0.06)` per city); KEEP the captive forge conversion (+18/city, it consumes captives — a real trade)
- Modify: `scripts/autoloads/turn_manager.gd` — Frontier Orders dilemma (~:4679-4706 choices + :186-193 applier): add choice `{"label": "Smelt Surplus", "description": "Convert 40 iron into 20 scrap for the fortress works.", "effect": "forge_smelt"}` shown when iron ≥ 40; applier: `-40 iron, +20 scavenge_stockpile`
- Test: `tests/test_cinderguard_rework.gd` (new)

**Interfaces:**
- Produces: the smelt applier effect id `"forge_smelt"`; test harness file used by later tasks.

- [ ] **Step 1: Failing test** — new `tests/test_cinderguard_rework.gd` (standard SceneTree harness, `new_game(&"cinderguard", false, 0)`):

```gdscript
	# Building data cuts
	var dm = root.get_node("/root/DataManager")
	_check(dm.get_building(&"ember_foundry").income_bonus.get(1, 0) == 45, "ember foundry iron 45")
	_check(dm.get_building(&"ember_foundry").display_name == "Ember Foundry II", "armory renamed")
	_check(dm.get_building(&"volcanic_smelter").income_bonus.get(1, 0) == 35, "smelter 35")
	_check(dm.get_building(&"cinder_mine").income_bonus.get(1, 0) == 20, "mine 20")
	_check(dm.get_building(&"magma_vent").income_bonus.get(1, 0) == 16, "vent 16")
	_check(dm.get_building(&"molten_core_forge").income_bonus.get(1, 0) == 28, "arsenal 28")
	# Smelt applier
	var cfs: FactionState = _gm.state.faction_states[&"cinderguard"]
	cfs.resources[1] = 100
	var scrap_before: float = cfs.scavenge_stockpile
	_tm._on_faction_dilemma_resolved(&"cinderguard", "forge_allocation", "forge_smelt")
	_check(cfs.resources[1] == 60, "smelt consumed 40 iron")
	_check(cfs.scavenge_stockpile == scrap_before + 20, "smelt produced 20 scrap")
```
(IMPLEMENTER: read `_on_faction_dilemma_resolved`'s real signature/dispatch (dilemma type string for frontier orders — the audit calls it forge/frontier orders; find the exact type key) and the applier's structure at :186-193; adapt the invocation. Also verify the hidden-layer deletion via an income delta assertion: craft a cinderguard city, vigilance 50 vs 80 → `calculate_city_income` iron identical after the fix.)

- [ ] **Step 2-4: Run failing → implement → run passing.** Also regressions: `test_special_resources.gd` (deepiron extractor untouched at 20 — confirm), `test_income_breakdown_equivalence.gd` (the deleted layer flows through `compute_faction_income_modifier_effects` — the breakdown must stay in parity; if the layer lives there, delete it from the SHARED helper so both sides update together).
- [ ] **Step 5: Commit** — `balance(cinderguard): halve iron pumps, remove hidden vigilance layer, smelt sink` + footer.

---

### Task 2 (Package B): Vigilance is the economy — posture target, aligned thresholds, feedback

**Files:**
- Modify: `scripts/core/faction_state.gd` — `@export var vigilance_target: int = 50`
- Modify: `scripts/autoloads/turn_manager.gd` `_process_cinderguard_forge`:
  - DELETE the auto-center nudge (~:4551-4555)
  - Drift: `border_vigilance` moves toward `vigilance_target` by 4/turn (building `vigilance_drift` special_effects still add ±, clamped 0-100)
  - REPLACE the flat vigilance iron bonuses (~:4575-4588) with posture economics: `if border_vigilance >= 60: iron += int(border_vigilance * 0.4); gold -= int(border_vigilance * 0.1); food -= int(border_vigilance * 0.1)` (war footing pays for its iron); `elif border_vigilance <= 40:` keep the existing fortress-mode loyalty/pop/food benefits, iron +0. Mid-band: +2 iron flat (unchanged).
  - Frontier Orders choices become POSTURE ORDERS: "War Footing (target 85)" / "Balanced Watch (target 50)" / "Fortress Doctrine (target 15)" (each sets `vigilance_target`), plus the existing fortress-build options and Task 1's Smelt Surplus. Remove the ±10 nudge choices and Emergency Mobilization (obsolete under targets). Applier updates accordingly.
- Modify: `scripts/systems/battle/battle_simulator_v3.gd:580-602` — align thresholds to the UI's numbers: fortress `<= 30` → +20% def +8 morale (single tier; delete the ≤40 half-tier), war `>= 75` → +15% atk (delete the ≥70/≥85 split). INERT-AT-FRESH: vigilance starts 50 → no branch fires; verify determinism.
- Modify: `scenes/campaign/campaign_hud.gd:1941-1956` — vigilance tooltip gains the combat lines ("Fortress (≤30): +20% defense, +8 morale in battle" / "War Footing (≥75): +15% attack in battle") and the posture economics (+iron/-gold/-food at war footing); AND `turn_manager` appends a turn_log entry when `border_vigilance` crosses 30 or 75 in either direction ("The forges shift to War Footing — armies strike +15% harder" / "The border settles into Fortress doctrine — +20% defense").
- Test: `tests/test_cinderguard_rework.gd` (append)

**Interfaces:**
- Consumes: Task 1's dilemma structure. Produces: `FactionState.vigilance_target`.

- [ ] **Steps: failing tests** (target-seeking drift: set target 85, run `_process_cinderguard_forge` 3 times → vigilance rises by ~4/turn toward 85 and does NOT center back to 50; posture economics: at vigilance 80, one process tick nets `+int(80*0.4)=+32` iron, `-8` gold, `-8` food vs the mid-band's +2; threshold crossing appends a turn_log entry) → implement → pass. Then `test_battle_determinism.gd` → FINGERPRINT MATCH (byte-check). `test_faction_ai_flavor.gd` — the AI posture gate reads `border_vigilance < 60` for defensive stance; verify it still functions (AI cinderguard now also needs to SET vigilance_target: update the AI branch in `_process_cinderguard_forge`'s auto-resolve (~:4511 per old audit) to pick War Footing when at war, Fortress when not — read the existing `_ai_handle_frontier_orders` and adapt).
- [ ] **Commit** — `feat(cinderguard): vigilance as chosen posture with real economics and visible combat stakes` + footer.

---

### Task 3 (Package C): Raids with named stakes

**Files:**
- Modify: `scripts/autoloads/turn_manager.gd` — raid trigger (~:4639-4677): pick the raided settlement's HIGHEST-VALUE building (max summed `build_cost`) as `dragon_raid_building: StringName` stored alongside the existing raid target; the dilemma description NAMES it ("The dragon circles Ashfall Outpost — its Ember Foundry II lies in the fire's path"). Appliers (~:194-248):
  - Man the Walls: unchanged mechanics; on FAIL `_apply_dragon_damage` destroys THE NAMED building (not random) — modify :4762-4766.
  - Set Dragon Traps: cost 20 iron (now meaningful post-A/B); success unchanged; on success additionally +1 `dragon_raids_survived` bonus counts? NO — keep simple: unchanged rewards.
  - Evacuate: no damage roll BUT the settlement goes offline: new `CityState @export var production_disabled_turns: int = 0` — set 3; `calculate_city_income` returns `{}` for cities with it > 0; tick it down in city_system's per-turn processing; UI: city panel shows "Evacuated (N turns)" if feasible cheaply (city name suffix in the info panel).
  - Rush Fortifications: unchanged.
- Test: `tests/test_cinderguard_rework.gd` (append)

- [ ] **Steps: failing tests** (raid stores the named building id and it's the settlement's most expensive; forced-fail damage destroys exactly that building; evacuate sets production_disabled_turns=3 and income is empty while active, ticking down) → implement (read the real raid state fields — the audit shows `dragon_raid_target`; add the building field beside it, @export for save compat) → pass; regressions test_save_roundtrip (new fields), tmp_econ_sim -- 7 30 (zero SCRIPT ERRORs; report cinderguard iron/turn observed).
- [ ] **Commit** — `feat(cinderguard): dragon raids threaten named buildings with real choices` + footer.

---

### Task 4: Scrap transparency

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` — for a Cinderguard player: a top-bar element after the shard label (the established standalone-label pattern): `"  |  Scrap: N"` reading `fs.scavenge_stockpile` (int display), updated in `_update_resource_display`; hover tooltip (dark chip, clamped below TopBar) explaining: "Scrap — salvage for the border works.\nSources: settlements each turn, surviving dragon raids, razed rubble, Smelt Surplus orders.\nSpent on: border fortresses (Watchtower 10 / Palisade 20 / Fort 35) via Frontier Orders.\nFortresses: +2% army defense each (network), raise vigilance, harden raid defense." plus a live list of current fortress levels per settlement (`fs.border_fortresses`) and the current vigilance/target line.
- Also add scrap to the vigilance tooltip's economics block (Task 2's tooltip) with one cross-reference line.
- Test: harness screenshot (cinderguard game phase — extend tests/tmp_screenshot_windows.gd or a small dedicated phase with `new_game(&"cinderguard", false, 0)` — NOTE the harness currently news empire; a second faction phase requires a fresh new_game inside the harness which rebuilds the scene — read how tmp_screenshot_bounties handles multi-phase new_game or add a minimal dedicated `tests/tmp_screenshot_cinderguard.gd` modeled on it: intro suppressed, screenshot the top bar + vigilance tooltip forced visible, `user://win_scrap_ui.png`).

- [ ] **Steps:** implement → windowed screenshot (coordinator judges) → headless `test_cinderguard_rework.gd` still PASSED → commit `feat(ui): scrap visibility for cinderguard` + footer.

---

### Task 5: Balance verification + docs

- [ ] **Step 1:** Econ sim balance check: run `tmp_econ_sim.gd -- 7 40` and `-- 3 40`; extract Cinderguard's iron column trajectory; ASSERT the goal informally: recurring iron/turn at t30 ≈ under 150 balanced / under 220 war-footing (report actual numbers; if wildly off, tune the Task 2 multiplier `0.4` and building values ±20% and re-run — you own the final numbers, document them).
- [ ] **Step 2:** Full battery: test_cinderguard_rework, test_faction_ai_flavor, test_battle_determinism (MATCH), test_save_roundtrip, test_income_breakdown_equivalence, test_special_resources, windowed harness sweeps.
- [ ] **Step 3:** Update `docs/design_audit.md` (or the faction section of `docs/special_resources_design.md` is wrong home — use design_audit.md's Cinderguard section if present, else append a dated note): the rework summary + final numbers.
- [ ] **Step 4:** Commit — `docs(cinderguard): rework notes and final balance numbers` + footer.

---

## Self-Review

- **Coverage:** A (T1: cuts+rename+hidden-layer+smelt), B (T2: target posture, aligned thresholds, feedback, AI adaptation), C (T3: named stakes, evacuate cost, trap cost), scrap UX (T4), balance proof (T5). User's scrap-transparency complaint answered by T4's bar+tooltip; "how it relates to vigilance" covered in both tooltips.
- **Placeholders:** none — numbers fixed; implementer-notes are live-code lookups.
- **Type consistency:** `vigilance_target`/`production_disabled_turns` `@export`; `"forge_smelt"` effect id consistent T1/T2 choice lists.
