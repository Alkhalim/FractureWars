# Settlement Building Partition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (user decision 2026-08-01):** settlements may only build the small settlement-grade buildings, never the larger city versions of the same roles — "settlements only having the smaller settlement versions and not the larger ones of the same type." Cities keep the full faction roster (and already can't build the settlement versions).

> **USER REVISION (2026-08-01, after Task 1):** "settlements still should be able to get city buildings, but only a few. like one military tree, one science tree, something like that that still gives them choices. add extra tiers to settlement buildings as well." → Task 1b below: per-faction curated access (one military chain + one science/cultural chain) via a new `settlement_allowed: bool` data field, PLUS tier-2 upgrades for all four settlement buildings. Mobile camps stay exempt (city-class) per the Task 1 fix round.

---

### Task 1b: Curated city-tree access + settlement building tiers

**Files:** Modify `scripts/resources/building_data.gd` (+`settlement_allowed: bool = false` @export), `scripts/systems/campaign/city_system.gd` (`is_building_allowed_for` settlement branch gains `or building.settlement_allowed`), ~22-30 `data/buildings/*.tres` (tag two chains per faction), CREATE 4 new `data/buildings/*.tres` (tier-2 settlement buildings), `scripts/autoloads/turn_manager.gd` (AI settlement priorities gain the faction's tagged chain heads), tests append to `tests/test_settlement_partition.gd`.

Chain selection rule (USER-REVISED 2026-08-01: 3-4 city trees per faction, NEVER defensive/wall trees; tag the WHOLE chain tier-1→tier-2, not just tier 1):
1. MILITARY tree: the faction's basic unit-unlocking barracks line (the tier-1 building whose `unlocks_units` carries the faction's basic units, plus its `upgrades_from` successor). Settlements can then recruit and defend.
2. SCIENCE/CULTURAL tree: the faction's basic shrine/temple line (tech and/or loyalty income). Where a faction has several, prefer the one with `research_speed_bonus`/tech income; fall back to the loyalty shrine.
3. CAPTIVE/PRISONER tree, IF the faction has one (user-directed): any chain whose income/cost/effects involve CAPTIVES(6) — e.g. skulloath blood altars, cinderguard captive forges, tainted_jade/ivoryscar captive lines. Identify by scanning for resource key 6 in income_bonus/build_cost/special_effects and captive-themed effects. Factions without a captive economy simply skip this slot.
4. FOURTH slot (to reach 3-4 total): for factions WITHOUT a captive tree, add ONE faction-flavor chain tied to the faction's signature mechanic (e.g. a harmony/lunar/storm line) — implementer's judgment, but NEVER a defensive/wall chain (`defense_bonus`-primary or category defensive buildings are EXCLUDED from tagging across the board; frontier_watchpost covers settlement defense). Factions WITH a captive tree already sit at 3 — a fourth is optional there, use judgment on roster size.
- Implementer lists every tagged id per faction in the report — the coordinator will show the table to the user for override.

Tier-2 settlement buildings (universal, `settlement_only = true`, `upgrades_from` the tier-1, `required_capital_level = 2`, build_time 3, no upkeep — matching the tier-1 conventions; costs stated post-cost-sweep, i.e. these ARE the final values):
| id | display_name | cost | effect |
|---|---|---|---|
| `waystation_2` | "Waystation II" | Gold 175 | Gold +14, Food +8 |
| `resource_camp_2` | "Resource Camp II" | Gold 68, Food 149 | Wood +16, Iron +8 |
| `frontier_watchpost_2` | "Frontier Watchpost II" | Wood 155 | Defense +8, garrison_strength_bonus 0.2 |
| `frontier_shrine_2` | "Frontier Shrine II" | Gold 155, Wood 52 | region_loyalty_bonus 2 |

- [ ] **Step 1: failing tests** — settlement availability now ALSO includes the faction's tagged military tier-1 and science tier-1 (assert via `settlement_allowed` flag AND by known id for empire at seed 0); tier-2 settlement buildings exist with the exact table values and are offered to a level-2+ settlement that owns the tier-1; cities are NOT offered the 4+4 settlement buildings (unchanged direction); mobile camps unaffected. RED.
- [ ] **Step 2: implement** (field + predicate + tags + 4 new .tres + AI priorities: settlements walk [tagged military t1, resource_camp, waystation, tagged science t1, watchpost, shrine, then tier-2s via the existing upgrade-fallback]). GREEN.
- [ ] **Step 3: regressions** — test_settlement_partition, test_building_rebalance (its invariant sweeps iterate all buildings — new .tres must not violate), test_faction_ai_flavor, test_battle_determinism (MATCH), test_save_roundtrip (new @export field).
- [ ] **Step 4: commit** `feat(settlements): curated city trees + settlement building tiers`.

---

**Architecture:** No per-building data tagging of ~270 city buildings. Instead a mechanic-level branch keyed on `CityState.is_settlement` in BOTH `get_available_buildings` AND `start_building` (the commit path currently enforces no settlement gate at all — latent exploit). Settlement whitelist: `settlement_only` buildings ∪ region-gated extractors (`requires_region_resource`) ∪ landmark buildings (`requires_region_landmark`) — the latter two protected because AI lease/landmark claiming happens in settlements (turn_manager.gd:761-786). AI gets a settlement-specific priority list so it stops falling through to arbitrary-order fallback.

**Tech Stack:** Godot 4.4 GDScript.

**Grounding (2026-08-01 investigation, verify lines):** availability filter `city_system.gd:1588` (`get_available_buildings`), the one existing gate `settlement_only and not is_settlement` at :1690; commit path `start_building` :1737 checks slots/level/capital/resources but NOT settlement class; `BuildingData.settlement_only` :25; the 4 settlement buildings: `waystation`, `resource_camp`, `frontier_watchpost`, `frontier_shrine` (universal, no upkeep); NO graduation exists (`is_settlement` never unset); Cinderguard settlements have extra slots (`city_state.gd:54-77`) and border-fortress ties; AI: `_execute_ai_city_management` turn_manager.gd:723, priorities :730-742 list only city buildings, fallback chain :790-807; UI: same `_show_city_panel` for both (campaign_hud.gd:8024), buildings pulled at :8265.

## Global Constraints

- Binary `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; headless `-s res://tests/<name>.gd`; compile noise benign; HANG = runtime crash; null-guard data lookups; pin `new_game(..., 0)`; FOREGROUND only.
- `test_battle_determinism.gd` must stay FINGERPRINT MATCH after every task.
- Existing settlements in old SAVES may already contain city buildings — the gate applies to NEW construction only; never delete/invalidate already-built buildings (their income keeps working; `calculate_city_income` iterates `city.buildings` regardless of availability).
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: The partition gate (both paths) + AI settlement priorities + tests

**Files:**
- Modify: `scripts/systems/campaign/city_system.gd` — `get_available_buildings` (~:1588-1691) and `start_building` (~:1737).
- Modify: `scripts/autoloads/turn_manager.gd` — `_execute_ai_city_management` (~:723-807).
- Test: `tests/test_settlement_partition.gd` (new; harness modeled on tests/test_building_rebalance.gd).

**Interfaces:** Produces `CitySystem.is_building_allowed_for(city, building) -> bool` — ONE shared predicate both call sites use (no logic duplication):

```gdscript
## The settlement/city building partition (user decision 2026-08-01):
## settlements build only settlement-grade buildings plus region-gated
## extractor/landmark buildings; cities build everything except the
## settlement-grade set. Settlements never graduate, so this is a permanent
## class identity, not an early-game state.
func is_building_allowed_for(city: CityState, building: BuildingData) -> bool:
	if city.is_settlement:
		return building.settlement_only \
			or building.requires_region_resource != &"" \
			or building.requires_region_landmark != &""
	return not building.settlement_only
```
(IMPLEMENTER: read the real field types first — `requires_region_resource`/`requires_region_landmark` may be StringName or bool; adapt the emptiness checks. Replace the existing :1690 settlement_only gate with a call to this predicate; ADD the same call to `start_building`'s validation chain with a clear error/refusal consistent with its other rejections.)

AI: add `const SETTLEMENT_BUILD_PRIORITY: Array[StringName] = [&"resource_camp", &"waystation", &"frontier_watchpost", &"frontier_shrine"]` and, in `_execute_ai_city_management`, when `city.is_settlement`, walk this list instead of the faction table (extractor/landmark steps :764-786 stay FIRST, unchanged — they are the settlement's most valuable builds). Fallback (e) stays as safety net.

- [ ] **Step 1: failing tests** — `tests/test_settlement_partition.gd`, `new_game(&"empire", false, 0)`:
```gdscript
	# Partition: a settlement's available list contains ONLY allowed classes
	var settlement = <find or found a settlement via game_manager.found_settlement — read its signature; else craft synthetic CityState with is_settlement=true on a real tile>
	for b in cs.get_available_buildings(settlement, true):
		var bd = dm.get_building(b)  # (adapt: list may hold ids or data)
		_check(bd.settlement_only or bd.requires_region_resource != &"" or bd.requires_region_landmark != &"", "settlement offered only settlement-grade/extractor/landmark: %s" % b)
	# City never sees settlement buildings (pin the existing direction too)
	var capital = <player capital>
	for b in cs.get_available_buildings(capital, true):
		_check(not dm.get_building(b).settlement_only, "city not offered settlement building: %s" % b)
	# COMMIT PATH enforced (the latent hole): start_building a city building
	# (e.g. &"market_square") on the settlement must be REFUSED even though
	# resources suffice — assert refusal AND that city.buildings did not gain it.
	# Old-save compat: a settlement with a pre-existing city building in
	# city.buildings keeps it and its income still counts (calculate_city_income
	# unchanged before/after adding the gate).
	# AI: run _execute_ai_city_management for a faction owning a settlement with
	# a free slot + resources; assert the settlement built one of the 4 (not
	# arbitrary fallback) — check city.buildings/build queue afterward.
```
RED → **Step 2: implement** → **Step 3: GREEN.** Regressions: test_building_rebalance, test_special_resources (extractors in settlements MUST still work — this is the trap), test_landmarks, test_faction_ai_flavor, test_battle_determinism (MATCH), test_save_roundtrip.
- [ ] **Step 4: commit** `feat(settlements): settlements build only settlement-grade buildings (+ extractors/landmarks)`.

---

### Task 2: Sim verification + docs

- [ ] **Step 1:** Econ sim A/B: capture `tmp_econ_sim.gd -- 7 40` BEFORE the gate is merged? (Task 1 already committed — instead compare against the Task-D-era baseline numbers in .superpowers/sdd/task-D-report.md.) Run `-- 7 40` and `-- 3 40`: report settlements' build patterns (do AI settlements now hold the 4 + extractors?), overall faction economy deltas vs the task-D-report baselines (settlement income WILL drop — that is intended; flag only if a faction's total economy collapses >25% vs baseline), and confirm extractor/lease behavior unchanged (gladehost→moonspear lease still forms, if present in baseline).
- [ ] **Step 2:** Battery re-run + windowed `tmp_screenshot_windows.gd` (a settlement's city panel should now show the short list — screenshot it: open _show_city_panel on an AI-founded or test-founded settlement → user://win_settlement_menu.png for the coordinator).
- [ ] **Step 3:** Docs: append to `docs/design_audit.md` a dated "## Settlement Building Partition (2026-08-01)" note: the rule, the permanent-identity implication (no graduation), the extractor/landmark whitelist rationale, old-save behavior, and one flagged designer option: the 4 settlement buildings have no upgrade tiers, so a level-5 settlement (5 slots) can build everything — if settlements should stay interesting at high level, tier-2 versions of the 4 are the natural extension (NOT implemented; designer's call).
- [ ] **Step 4:** Commit `docs(settlements): partition notes + sim verification`.

## Self-Review
- User's rule implemented both directions with one shared predicate; commit-path hole closed; extractor/landmark trap explicitly whitelisted; AI priorities added so settlement builds are role-aware; old saves safe (no retroactive deletion); Cinderguard slot special-case unaffected (slots orthogonal to availability); no graduation dependency.
- Placeholders: implementer must adapt field-type checks and the settlement-acquisition helper in tests to real signatures — flagged inline, values otherwise concrete.
