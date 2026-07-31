# Building Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (user-approved "do all those changes"):** Kill same-roster building redundancy found by the 2026-07-31 audit: parallel twin chains where one dominates, thematically-wrong effects (forges granting growth), identical gains that collapse choices, plus the user's five named directives and one live bug.

**Architecture:** Almost entirely data edits to `data/buildings/*.tres`, guarded by a new invariant test (no industrial building grants growth) and per-change value pins. One new code hook: `besieger_attrition` (attrition walls damage besieging armies during sieges, in turn_manager's siege tick). Audit source of truth: the five user directives + audit report (Parts A/B/C/D/E) summarized per task below — every target value is in this plan.

**Tech Stack:** Godot 4.4 GDScript; DataManager building resources; headless tests.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; headless `-s res://tests/<name>.gd`; startup compile noise benign; pin `new_game(..., 0)` seeds; FOREGROUND only.
- Resource keys in income/cost dicts: 0=GOLD 1=IRON 2=TECH 3=FOOD 4=SHARD 5=WOOD 6=CAPTIVES.
- DO NOT touch the five Cinderguard iron VALUES (ember_foundry 45, volcanic_smelter 35, cinder_mine 20, magma_vent 16, molten_core_forge 28) — set by the parallel Cinderguard plan. Stripping their growth fields is in-scope (Task 3).
- `tests/test_battle_determinism.gd` must print FINGERPRINT MATCH after every task. If any task breaks it (candidate: sunfire_forge army_attack removal), STOP and report — the coordinator decides re-baselining; never re-baseline yourself.
- After each task also run `tests/test_faction_ai_flavor.gd` and the new `tests/test_building_rebalance.gd`.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: User directives (data) + garrison bug

**Files:** Modify `data/buildings/`: `mushroom_grotto.tres`, `sporevault.tres`, `grove_ironworks.tres`, `grove_smithy.tres`, `seasonal_shrine.tres`, `jade_forge.tres`, `hardened_chitin_wall.tres`. Create `tests/test_building_rebalance.gd`.

Exact changes:
- `mushroom_grotto`: food 14→**10**, population_growth_bonus 5→**0** (keep gold 5). The cash-crop pick vs harvest_clearing's food 14/growth 6.
- `sporevault`: food 36→**28** (keep gold 12); remove `region_population_growth_bonus` from special_effects if present.
- `grove_ironworks`: iron 25→**20**, population_growth_bonus 2→**0**.
- `grove_smithy`: remove `region_population_growth_bonus:1` (keep iron 32).
- `seasonal_shrine`: income {2:4, 3:12} → **{2:8, 3:4}**, population_growth_bonus 6→**3**.
- `jade_forge`: population_growth_bonus 2→**0** (keep iron 18, keep loyalty artisans+1/captives-3).
- `hardened_chitin_wall`: special_effects garrison_strength_bonus **2 → 0.2** (live bug: code does `int(value*10)` militia — was spawning +20 defenders instead of +2, city_system.gd:1929-1934).

- [ ] **Step 1:** New `tests/test_building_rebalance.gd` (SceneTree harness modeled on tests/test_cinderguard_rework.gd; DataManager via `root.get_node("/root/DataManager")`): one `_check` per value above (income key, growth field, garrison 0.2 within 0.01). Run → RED.
- [ ] **Step 2:** Apply the seven .tres edits. Run → GREEN. Regressions: test_battle_determinism (MATCH), test_faction_ai_flavor.
- [ ] **Step 3:** Commit `balance(buildings): user-directed retunes (grotto, ironworks, shrine, jade forge) + chitin garrison bug`.

---

### Task 2: Tainted Jade wall split — attrition vs endurance

**Files:** Modify `data/buildings/jungle_traps.tres`, `serpents_maze.tres`, `living_walls.tres`, `thornwall.tres`; `scripts/autoloads/turn_manager.gd` (siege tick); `scripts/systems/campaign/city_system.gd` only if the siege tick lives there — find `siege_turns` incrementing code first. Test: append to `tests/test_building_rebalance.gd`.

**Interfaces:** Produces special_effects key `"besieger_attrition"` (float; per-siege-turn damage multiplier).

Data:
- `jungle_traps` (tier 1): keep def 6, ADD special_effects `{"besieger_attrition": 2.0}`, REMOVE `required_terrain` (audit: available everywhere so the choice is attrition-vs-endurance, not terrain-forced).
- `serpents_maze` (tier 2): keep def 10, special_effects → `{"besieger_attrition": 4.0}` (REMOVE its garrison_strength_bonus 0.1 — garrison identity belongs to the endurance line).
- `living_walls`/`thornwall`: unchanged data (def 8/13 + thornwall garrison 0.1) — they're the endurance line by contrast.

Code hook: in the siege tick (where `siege_turns` increments each turn a city is besieged), sum the besieged city's buildings' `besieger_attrition`; if > 0, each besieging army takes `attrition * 8` HP damage spread across its units (mirror `_apply_dragon_damage`'s damage-spreading pattern in turn_manager.gd:4753-4778 — reuse/extract if clean, else parallel implementation). Kill units at 0 HP the same way that pattern does. Append a turn_log/toast line for both sides ("Jungle traps bleed the besiegers: X damage") — use the existing siege-toast conventions.

- [ ] **Step 1:** Failing tests: (a) jungle_traps has besieger_attrition 2.0, no required_terrain; serpents_maze 4.0 and no garrison key; (b) functional: craft a besieged tainted_jade city (set a hostile army adjacent + siege state the way existing siege tests do it — READ tests/test_siege_pressure.gd first and reuse its siege-setup helper pattern), give the city jungle_traps, tick one turn, assert the besieging army's total HP dropped by ~16 (2.0*8) more than an identical control without the wall.
- [ ] **Step 2:** Implement data + hook → GREEN. Regressions: test_siege_pressure, test_siege_ai, test_battle_determinism (MATCH), test_save_roundtrip.
- [ ] **Step 3:** Commit `feat(buildings): tainted jade wall split — attrition traps vs endurance walls`.

---

### Task 3: Growth purge on industry + growth variance

**Files:** Modify ~30 `data/buildings/*.tres` (enumerated below); `data/buildings/sunfire_forge.tres`. Test: append invariant to `tests/test_building_rebalance.gd`.

- Strip `population_growth_bonus` (set 0 / remove) from ALL tier-1 industrial buildings (audit list): `iron_pit`, `sandstone_pit`, `silver_vein`, `thunderpeak_mine`, `bone_quarry`, `sunfire_forge`, `scrap_pit`, `stone_quarry`, `ice_quarry`, `bone_workshop`, `crystal_forge`, `clay_kiln` (+ cinderguard `cinder_mine`, `magma_vent` growth fields only — values untouchable per Global Constraints; jade_forge/grove_ironworks already done in Task 1).
- Remove `region_population_growth_bonus` from ALL tier-2+ industrial buildings: `deeproot_foundry`, `imperial_foundry`, `solar_foundry`, `war_forge`, `storm_forge`, `moonsilver_forge`, `moonstone_mine`, `salvage_foundry`, `relic_smelter`, `petrified_quarry`, `mountain_stoneworks`, `adobe_works`, `volcanic_smelter`, `ember_foundry`, `molten_core_forge`, `resonant_crystal_forge`, `shard_breaker_forge` (grove_smithy done in Task 1). Sweep with a script/grep for any further mine/forge/quarry/foundry/smelter/pit/kiln-named building carrying either growth field — the audit list may be incomplete; the invariant test is the authority.
- Growth variance on food buildings: every tier-2+ building whose LARGEST income key is 3 (FOOD) and which carries `region_population_growth_bonus:1` → raise to **2** (granaries/orchards become the real growth engines; Forsaken's 3/5 stay). Markets/temples keep 1.
- `sunfire_forge`: also REMOVE special_effects `army_attack_bonus:2` (a tier-1 economy building carrying a capstone-grade combat buff; `solar_citadel` keeps its +2).

- [ ] **Step 1:** Failing INVARIANT test: iterate all DataManager buildings; for every building whose id or name matches `(mine|forge|quarry|foundry|smelter|pit|kiln|works)` AND whose largest income key is 1 (IRON): assert population_growth_bonus == 0 and no region_population_growth_bonus. Plus spot pins: sunfire_forge has no army_attack_bonus; one named granary-class building per the variance rule reports 2.
- [ ] **Step 2:** Apply sweep → GREEN. Regressions: test_battle_determinism (MATCH — if sunfire_forge's attack removal breaks it, STOP per Global Constraints), test_faction_ai_flavor, test_income_breakdown_equivalence, econ sim `tests/tmp_econ_sim.gd -- 7 25` (report any faction whose food/growth trajectory collapses).
- [ ] **Step 3:** Commit `balance(buildings): industry no longer grows population; growth belongs to farms`.

---

### Task 4: Pure-vs-hybrid differentiation on the 8 remaining twin chains

**Files:** Modify `data/buildings/`: food pairs — `dust_fields.tres`/`desert_well.tres` (ivoryscar), `pilgrim_gardens.tres`/`sacred_oasis.tres` (sunblessed), `highland_terrace.tres`/`mountain_herds.tres` (thunderswarm), `hunting_ground.tres`/`vine_shelter.tres` + `jade_market.tres` (tainted_jade); iron pairs — `bone_quarry.tres`/`sandstone_pit.tres` (ivoryscar), `silver_vein.tres`/`ice_quarry.tres` (moonspear), `sunfire_forge.tres`/`clay_kiln.tres` (sunblessed), `thunderpeak_mine.tres`/`stone_quarry.tres` (thunderswarm), `cinder_mine.tres`/`magma_vent.tres` (cinderguard — see constraint below). Their tier-2 upgrades where noted. Test: append pins.

Template (audit-approved): in each same-tier pair, the PURE building keeps full primary yield and (for food) keeps growth; the HYBRID drops primary to ~70% (round to nearest int), loses ALL growth, and gets its secondary income bumped +2 so it's clearly the flexibility pick. Implementer reads each pair's current values first and records before→after in the report; the invariant is **pure.primary > hybrid.primary by ≥25%** and **hybrid growth = 0**. For tainted_jade food: `hunting_ground` is the pure (keep food 18, keep growth 4), `vine_shelter` hybrid; ALSO `jade_market` growth 4→**1** (A3: markets attract people modestly; its identity is gold 25).
- CINDERGUARD EXCEPTION: iron VALUES are locked (20/16). Differentiate on secondaries only: `magma_vent` (hybrid) gets wood +4 and loses any growth remnant; `cinder_mine` stays pure. The 20-vs-16 gap plus wood satisfies the template's spirit; do not touch the iron numbers.
- Tier-2 upgrades of each hybrid: primary scaled by the same ~0.7 ratio, growth effects removed, secondary kept — record exact before→after per file.

- [ ] **Step 1:** Failing tests: per pair, pin hybrid growth == 0 and assert pure primary ≥ 1.25 × hybrid primary (read both from DataManager, so exact hybrid values are free to be ~70% rounded).
- [ ] **Step 2:** Apply → GREEN. Regressions: test_faction_ai_flavor, test_battle_determinism (MATCH), econ sim `-- 3 25` sanity (no faction starves: food income stays positive for all majors).
- [ ] **Step 3:** Commit `balance(buildings): pure-vs-hybrid split on twin food/iron chains`.

---

### Task 5: Tail cleanup

**Files:** `data/buildings/hive_bulwark.tres`, `chitin_walls.tres`/`hardened_chitin_wall.tres` (chain refs only if schema needs), `crystal_forge.tres`/`resonant_crystal_forge.tres`, `blessed_springs.tres` + one sunblessed military building, `echo_chamber.tres`/`resonant_pylon.tres`, `codex_sanctum.tres`, `tempest_spire.tres`. Test: append pins.

- `hive_bulwark` (shardhorde 3rd wall): CHAIN it — becomes the upgrade of `hardened_chitin_wall` (read how chains are encoded — `upgrades_to`/`upgrade_of` field on the .tres — and wire hardened_chitin_wall→hive_bulwark): def 8→**12**, garrison 0.15→**0.2**, keep cost. If the schema only supports one upgrade slot and hardened_chitin_wall's is free, this is clean; if not, report BLOCKED with what you found.
- `resonant_crystal_forge` upgrade cost: {gold 35, food 101} → **{gold 40, food 30}** (audit: dozens-of-turns payback).
- `blessed_springs`: REMOVE `unlocks_units=[dawnscale_thunderlizard]`; ADD that unlock to the sunblessed tier-2 MILITARY building (find the barracks-line tier 2 — likely the building already unlocking mid-tier sunblessed units; append to its unlocks_units).
- `echo_chamber`/`resonant_pylon` (shardhorde parallel tech): CHAIN pylon→chamber (chamber becomes pylon's upgrade; adjust chamber cost down by pylon's cost if chains discount that way elsewhere — match an existing chained pair's convention).
- `codex_sanctum` (empire, 4th tier-3 authority source): swap its `imperial_authority` special_effect for `research_speed_bonus: 0.25` (matches the tier-3 cultural convention; the codex is a knowledge building — empire keeps 3 authority sources).
- `tempest_roost` vs `tempest_spire` (thunderswarm capstone fork off stormrider_eyrie): roost is in EXCL group storm_doctrine, spire is not. Make the fork consistent: ADD `tempest_spire` to `storm_doctrine` so picking one locks the other (they're alternatives off the same base).
- `chitin_hatchery`: NO data change; add one line to the Task 6 doc note flagging it as a possible stub for a future look.

- [ ] **Step 1:** Failing pins for each change (chain wiring, costs, unlock moved — assert dawnscale_thunderlizard absent from blessed_springs and present in exactly one military building, codex research 0.25 and no authority, spire in storm_doctrine group). → RED.
- [ ] **Step 2:** Apply → GREEN. Regressions: test_faction_ai_flavor (empire/thunderswarm/shardhorde build priorities may reference these ids — fix priorities if a moved/chained building broke a table), test_save_roundtrip, test_battle_determinism (MATCH).
- [ ] **Step 3:** Commit `balance(buildings): tail cleanup — wall chain, payback fix, unlock move, doctrine gate`.

---

### Task 6: Sweep, sim sanity, docs

- [ ] **Step 1:** Full battery: test_building_rebalance, test_cinderguard_rework, test_bounty_system, test_special_resources, test_landmarks, test_income_breakdown_equivalence, test_save_roundtrip, test_battle_determinism (MATCH), test_faction_ai_flavor. Windowed: `tests/tmp_screenshot_windows.gd` (no SCRIPT ERROR mentioning campaign files).
- [ ] **Step 2:** Econ sim `tests/tmp_econ_sim.gd -- 7 40`: report per-faction food/iron/growth health (no negative food spirals; tainted_jade/gladehost growth still functional post-purge). Numbers into the report file.
- [ ] **Step 3:** Append a dated "Building Rebalance 2026-07-31" section to `docs/design_audit.md` (create the section, not the file — it exists): what changed and why, the invariant now enforced (industry never grows population), chitin_hatchery flag.
- [ ] **Step 4:** Commit `docs(buildings): rebalance notes + invariants`.

## Self-Review
- Coverage: P1 = Tasks 1-2 (all five directives + bug + wall split); P2 = Tasks 3-4 (growth purge/variance, 10 twin chains incl. the 2 already fixed); P3 = Task 5 (all audit tail items; spy_guild/thieves_den explicitly excluded as already-differentiated; chitin_hatchery deferred by doc flag). Verification = Task 6.
- Placeholders: none; every change has explicit target values or an explicit measurable invariant.
- Consistency: `besieger_attrition` key named identically in Task 2 data and hook; growth fields named per existing schema (`population_growth_bonus`, `region_population_growth_bonus`).
