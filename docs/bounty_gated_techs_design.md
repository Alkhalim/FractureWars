# Bounty-Gated Technologies Design Proposal

Status: PROPOSAL — not implemented. Every id/line ref below was verified against the current repo.

> **DESIGNER DECISION (2026-08-01):** the bounty is required only to **initiate** the research (checked at research start). Losing the bounty mid-research does **not** pause or cancel it. This resolves the start-vs-continuous Open Question — the simpler start-only model is chosen; the continuous-check/pause plumbing proposed below is NOT needed.

> **DESIGNER DIRECTIVES (2026-08-01, round 2):**
> 1. **DO add new bounty types** for gate variety — e.g. `coal_seams` (mountains/tundra; fuels forge/construct gates), `bone_fields` (desert/wastes; skulloath/ivoryscar necro-flavored gates), and the doc's proposed `bronze_ore` if useful. More variety is a plus; new types also spread gate-relevant bounties across more map regions, creating more reasons to trade.
> 2. **Trading access is REQUIRED scope, not optional** — the §4 lease-extension (bounty access via treaty) ships with the feature, so a faction without map access to a gate bounty can negotiate for it.
> 3. **AI settlement placement must actively prioritize bounties.** The AI already founds settlements (turn_manager.gd:963-982) and scores sites with `calculate_settlement_income_preview` — the playtest-round-2 plan already makes that function bounty-aware (income folded in), which upgrades AI placement automatically. ON TOP of that, when this feature lands: add a scoring bonus for claimable bounty TYPES the faction needs for techs in its research path (gate-aware weighting), so the AI reaches for wild_horses/coal_seams sites deliberately.

## 1. Grounding findings (read this before the mapping table)

**The real bounty roster (22 ids, `BountySystem.BOUNTY_TYPES`, `scripts/systems/campaign/bounty_system.gd:20-43`):**
`orchards, grain_basin, vineyards, honey_apiaries, herb_meadows, wild_horses, fisheries, pearl_beds, salt_flats, marble, granite, basalt_columns, copper_vein, obsidian_flows, titanstone_quarry, timber_giants, amber_groves, furs, crystal_springs, clay_pits, peat_bogs, dye_gardens`

**Flagged deviations from the user's assumed ids:**
- `wild_horses` and `orchards` **do exist exactly as named** — good, those two map directly.
- **`bronze` and `coal` do NOT exist as bounty ids.** `cg_coal_mines.tres` is a *research tech* (Cinderguard, tier 1, flavor "coal fuels the forges"), not a bounty — there is no coal deposit to claim/conquer/trade for. Closest real analogues for a "constructs need X" gate: **`titanstone_quarry`** (already has `recruit_discount = {construct: 10}}` — it is *already construct-flavored* in the data) or **`copper_vein`** (income iron+gold, mountain/desert terrain — the closest thing to a "bronze" precursor material). Recommendation below uses both; a literal `coal_seams`/`bronze_ore` bounty could be added later if you want the flavor word "bronze"/"coal" to appear verbatim (see Open Questions).

**Research does not currently unlock units — buildings do.** `ResearchData.unlocks_units` (`scripts/resources/research_data.gd:17`) is declared but **never read anywhere in scripts** (verified via full-repo grep). Unit recruitment eligibility is 100% `BuildingData.unlocks_units`, checked in `CityState.can_recruit()` (`scripts/core/city_state.gd:139-159`) and explicitly documented in `turn_manager.gd:1618`: *"Unit unlocks come entirely from buildings — no level-based overrides."* So "the heavy cavalry unit requires wild horses" cannot be built as a literal research-unlocks-unit gate today. This proposal instead gates the army-wide **stat-bonus techs** that are thematically tied to a unit line (which is how all 495 techs actually work — `effects = {"unit_attack_pct": X, ...}`), and flags a fallback for the literal case in Open Questions.

**No research effect is currently unit-tag-scoped** (no tech uses a key like `cavalry_attack_bonus`; grepped all 495 `.tres` files) — every military tech is army-wide. The "cavalry tech" / "construct tech" framing in the tree is carried by **flavor text + `tree_branch` grouping** (e.g. Moonspear branch `silver_arms`, Skulloath branch `raiding`), not a mechanical filter. The mapping table below rides that same existing convention.

**Tier/category distribution** (495 techs total, counted directly from `data/research/**/*.tres`):

| Tier | Count | | Category | Count |
|---|---|---|---|---|
| 1 | 46 | | military | 175 |
| 2 | 161 | | arcane | 148 |
| 3 | 141 | | economy | 113 |
| 4 | 98 | | logistics | 59 |
| 5 | 49 | | | |

Gating ~25-40 techs (5-8%) at tier ≥2 is easy headroom. **Never tier 1** — note that the single most obviously "agriculture" tech, `advanced_agriculture.tres`, is tier 1 and universal; it is deliberately **excluded** below as the clearest illustration of that rule.

**Diplomacy precedent exists, but only for Tier-2, not Tier-1 bounties.** `BuildingData.requires_region_resource` (`scripts/resources/building_data.gd:26`) already gates *buildings* on a Tier-2 Special deposit, and `Enums.TreatyType.RESOURCE_LEASE` (`diplomacy_system.gd:350-377, 723-733`) already lets one faction lease a Tier-2 Special's yield to another via `SpecialResourceSystem.extracted_specials_of_faction`. **Tier-1 Bounties have no equivalent building-gate field and no lease path** — `RESOURCE_LEASE`'s `terms` dict only ever carries `special_id`, never a bounty id. This gap is exactly what §4 needs to close.

## 2. Requirement model: check at start, or continuously?

**Recommendation: continuous check, using the pause/resume plumbing that already exists.**

`start_research()` already pauses progress on a tech switch (`fs.paused_research_progress[research_id] = fs.research_progress`, `research_system.gd:51-52`) and resumes it later. Reuse this exact mechanism for the bounty gate: `process_research()` (`research_system.gd:79-105`) re-checks the gate every turn *before* incrementing `research_progress`; if the bounty is no longer held, progress is **paused** (not lost) until the bounty is reclaimed. This is deliberately more consequential than "check once at start":

- **Pro**: makes losing a bounty tile to conquest/raiding matter mid-research, not just at the moment of clicking "start" — directly serves the user's "claiming, conquering, or trading for them important" goal, and mirrors how siege progress already pauses/reflows on battlefield events elsewhere in the codebase (bounded siege-capture design).
- **Con**: can feel punishing if a rival snipes a border bounty while you're deep into a 15-turn tech. Mitigated by the pause-not-reset behavior (no wasted `tech_cost`, just delay) and by the fallback options in §6.
- **Option A (simpler)**: check only at `start_research()` time; once started, the tech completes regardless of later bounty loss. Less interesting but zero risk of frustrating a long research investment. Flag as designer's call — see Open Questions.

**New field** (mirrors `BuildingData.requires_region_resource` naming exactly):
```gdscript
# ResearchData addition
@export var requires_bounty_types: Array[StringName] = []  # any-of; empty = no gate
```
**New helper** (`BountySystem`):
```gdscript
static func faction_has_bounty_type(faction_id: StringName, type_id: StringName) -> bool:
    for entry in bounties_of_faction(faction_id):
        if entry.id == type_id:
            return true
    return false
```
**Hook points**: `get_available_research()` prereq loop (`research_system.gd:24-29`, add the bounty check alongside the existing prereq check) and `process_research()` (`research_system.gd:87`, guard the progress increment).

## 3. Mapping table (12 real gates, sampling the eventual ~25-40)

| Tech id | Display name | Faction | Tier | Category | Gate bounty | Gate rationale |
|---|---|---|---|---|---|---|
| `sk_horse_lords` | Horse Lords | skulloath | 3 | military | `wild_horses` | Home terrain (steppe/raiding branch) — organic |
| `sb_dawn_cavalry` | Dawn Cavalry | sunblessed | 2 | military | `wild_horses` | **Reach gate** — desert faction must expand into plains/tundra (`wild_horses` terrains) or trade for it |
| `ms_lunar_knights` | Lunar Knights | moonspear | 3 | military | `wild_horses` | Home terrain (tundra) — organic |
| `adamantine_forge` | Wasteland Foundry | cinderguard | 3 | economy | `titanstone_quarry` | Already construct-flavored bounty (`recruit_discount.construct`) — direct fit |
| `cg_master_alloys` | Elite Armaments | cinderguard | 4 | economy | `copper_vein` | Bronze-analogue (no literal bronze bounty exists — see §1) |
| `emp_war_machines` | War Machines | empire | 4 | logistics | `titanstone_quarry` | **Reach gate** — plains faction must push into mountains or trade; siege engines = constructs |
| `gh_herb_gardens` | Herb Gardens | gladehost | 2 | economy | `herb_meadows` | Literal name match; bounty's deferred effect ("+25% army healing") mirrors the tech's own healing flavor |
| `emp_aqueducts` | Imperial Aqueducts | empire | 3 | logistics | `orchards` | Home terrain (plains/forest) — organic |
| `oasis_blessing` | Oasis Blessing | sunblessed | 3 | economy | `salt_flats` | Home terrain (desert) — `salt_flats` is the only food/gold bounty with desert terrain |
| `mining_expertise` | Mining Expertise | thunderswarm | 2 | economy | `copper_vein` | Home terrain (mountains) — organic |
| `ts_deep_mines` | Deep Mines | thunderswarm | 4 | economy | `granite` | Deeper tier in same branch requires a *different, rarer* mountain bounty than its tier-2 prerequisite — shows escalating demand within one tech line |
| `iv_stone_masons` | Stone Masons | ivoryscar | 2 | economy | `marble` | Literal fit ("master builders of stone monuments") + home terrain (desert/mountains) |

Notes:
- `advanced_agriculture` (tier 1, universal) is deliberately **not** gated — see the tier-1 exclusion rule in §1.
- Bounty types repeat across factions on purpose (`wild_horses` x3, `copper_vein` x2, `titanstone_quarry` x2) — the same deposit type can gate different factions' trees since each campaign map places bounties independently per-game.
- Forsaken, Tainted Jade, and Shardhorde have no gate in this sample: their tech flavors (espionage, decay/corruption, shard-crystal economy) don't map cleanly onto secular resource bounties (a mine, a farm, a herd). Extending the full ~25-40 list to these factions may need either a looser flavor match (e.g. Forsaken "Bone Trade" → `furs` as a trade-goods stand-in) or accepting they simply get fewer gates than resource-flavored factions — designer's call.

## 4. Diplomacy integration

**Recommendation: extend `RESOURCE_LEASE`'s `terms` dict rather than add a new `TreatyType`.** Today `terms = {special_id, gold_per_turn}` (`diplomacy_system.gd:372`); add an alternative shape `terms = {bounty_hex: Vector2i, bounty_id: StringName, gold_per_turn}`. The per-turn processor (`process_treaties`, `diplomacy_system.gd:723-733`) already branches on `treaty.treaty_type == RESOURCE_LEASE`; add a second branch keyed on whether `terms.has("bounty_hex")` instead of `special_id`. `faction_has_bounty_type()` (§2) then checks claimed-by-city **OR** currently-leased-in bounties of that type.

This reuses the existing propose/accept/expire lifecycle (`propose_resource_lease`, `diplomacy_system.gd:350-377`) and the UI label switch (`diplomacy_system.gd:933, 956`) almost verbatim — only the eligibility check (`extracted_specials_of_faction` → `bounties_of_faction`) and the payment condition change.

**Option**: a dedicated new `BOUNTY_ACCESS` treaty type instead, if you want bounty leases to read differently in the diplomacy UI (Tier-1 bounties have no building/extraction step, so "leasing" a bounty is conceptually simpler than leasing a Special — arguably deserves its own label rather than overloading `RESOURCE_LEASE`'s existing "Resource Lease" text). Flagged as designer's call in Open Questions.

## 5. UI

- **Tech tree node**: small badge icon (reuse the bounty's own icon/color if one exists in the UI atlas, else a generic lock glyph) in the corner of any tech card where `requires_bounty_types` is non-empty. Green outline if satisfied, red/grey if not — same visual language the tree likely already uses for unmet prerequisites.
- **Tooltip**: `"Requires: Wild Horses (claimed or leased)"` plus, if unmet, the nearest source using existing helpers: `BountySystem.bounties_claimable_at(hex_pos)` for unclaimed tiles in reach, or a simple nearest-claimed-by-anyone scan, formatted like the existing one-liner builder `BountySystem.describe(type_id)` (`bounty_system.gd:428-439`) already used for bounty tooltips elsewhere.
- **Research list**: gated-and-unmet techs stay visible but visually locked (not hidden) so the player knows to go claim/conquer/trade rather than wondering why a tech never appears.

## 6. AI behavior

**Problem**: `get_available_research()` (`research_system.gd:7-32`) already filters out techs whose prerequisites aren't met — adding the bounty check to the same loop means a bounty-locked tech **never appears** in `available`/`affordable` inside `execute_ai_research()` (`research_system.gd:324-368`). The AI's category-weight scoring (`research_system.gd:342-368`) therefore never "sees" the locked tech and has no natural reason to value the bounty tile.

**Proposed fix**: add a small new helper `get_bounty_locked_research(faction_id) -> Array[Dictionary]` that returns techs whose *only* unmet gate is the bounty (prereqs otherwise satisfied), each paired with its required bounty type(s). Feed the resulting bounty-type set into the **existing AI settlement-tile scorer** (`turn_manager.gd:963-990`), which already sums per-tile income into `total_score` (`turn_manager.gd:984-987`) — add a flat bonus (e.g. `+15`) when `tile.bounty_id` is in the AI's desired set, on top of the income it already counts. The same desired-set can weight **conquest targeting** (whatever scores enemy-army/city attack priority) so the AI is more likely to march on a border settlement that happens to sit on a bounty it needs, not just tiles with the highest raw income.

Exact bonus magnitude is a tuning knob — default `+15` roughly matches the existing `dist_penalty: int = keyed[i][0] * 2` scale (worth ~7 hexes of distance), enough to occasionally redirect a settlement choice without dominating pure income.

## 7. Failure modes

**Map has no reachable `wild_horses` (or any gated type) at all** — since `BountySystem.scatter_bounties()` rolls only ~66% of the 22 types per map (`ROSTER_ROLL_PCT := 66`, `bounty_system.gd:10, 58-61`), roughly 1-in-3 types can be entirely absent from a given campaign. A tech permanently locked for an entire game is a real risk.

Options (pick one, or layer them):
1. **Steep alternative cost** (recommended default): if the bounty type does not exist anywhere on the map (checkable once at game-start via `GameManager.state.hex_map` scan, cached), the tech becomes researchable anyway at e.g. **2x `tech_cost`** and no bounty requirement — a "we improvised without the real material" escape valve. Cheap to implement, never leaves a tech dead.
2. **Conquest/trade incentive only, no fallback** — leave it hard-locked. Maximizes the "go get it" pressure the user wants, but risks a frustrating dead branch on unlucky maps; only reasonable if the roster-roll is changed to guarantee gated types always spawn (would mean special-casing `scatter_bounties` for any type referenced by `requires_bounty_types`, adding coupling between the tech data and the map-gen roll it currently doesn't have).
3. **Reveal at game start** whether a gated type exists on the map at all (a one-time tech-tree annotation, "this material does not exist this game — alternate cost applies") so the player isn't left guessing.

Default recommendation: **Option 1 + Option 3** together — never a truly dead tech, but the player is told early whether they're on the "easy" or "expensive" path for that branch.

## Open questions for the designer

1. Continuous bounty-check-with-pause (§2, default) vs check-once-at-start (Option A) — how punishing should losing a border bounty mid-research feel?
2. Should a literal `coal_seams`/`bronze_ore`/`tin_ore` bounty be added to `BOUNTY_TYPES` so "constructs need bronze/coal" can be gated verbatim, instead of reusing `titanstone_quarry`/`copper_vein` as flavor-adjacent stand-ins (§1, §3)?
3. Extend `RESOURCE_LEASE` (§4, default) or add a dedicated `BOUNTY_ACCESS` treaty type — does "leasing" a Tier-1 bounty deserve different diplomacy UI text than the existing Tier-2 Special lease?
4. For the ~13 gates not covered in the sample table (to reach the 5-8%/~25-40 target), should Forsaken/Tainted Jade/Shardhorde get looser flavor matches (e.g. `furs` as a Forsaken "bone trade" stand-in) or fewer gates than resource-themed factions?
5. Map failure-mode default (§6): steep alternative cost (never dead, but a "pay-to-skip" that undercuts the conquest-for-access pressure) vs true hard lock (maximal pressure, risk of a dead branch on unlucky maps) — which matters more for this design's goals?
