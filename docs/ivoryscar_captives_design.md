# Ivoryscar Captives Kit — Design Proposal

*Drafted 2026-08-01. Status: proposal, not implemented. Read-only research
against the `city_management` branch.*

> **DESIGNER DECISION (2026-08-01):** Pyramid Labor is VISIBLE and player-managed — via a dedicated **Black Pyramid management window** modeled on the Empire's Senate (top-bar button for Ivoryscar, centered management panel). The window hosts: restoration progress, captive labor allocation (the player sets how many captives/turn feed the pyramid — replacing the proposed automatic drain), relic power status, and is the natural future home for expedition management. ALSO: the pre-existing hidden tomb_scholars_hall drain (3 captives/turn, city_system.gd:2621-2626) must become visible in this window too — no invisible captive drains for this faction once the window ships. Bound Levy/Mummy recruitment competes for the same captive pool by design; the window is where that tension is managed.

## The ask

> "Ivoryscar does not seem to have easily accessible ways to get rid of
> prisoners, which is odd as I thought they are one of the factions to
> consume them the most. Like using slaves to build big pyramids, maybe
> consuming them for their main faction mechanic for expeditions or
> archeological digs searching for lost relics, or recruiting them as slave
> warrior types or turning them into skeleton legions or mummies."

Plus a follow-up while drafting: give them a **Slave Market** to actively
*produce* captives, not just capture them in battle.

## 1. How CAPTIVES actually works today

**Resource:** `Enums.ResourceType.CAPTIVES = 6` (`scripts/enums/enums.gd:18`).

**Acquisition — battle captures.** Every kill has a chance to yield a
captive, rolled per unit in `battle_simulator_v3.gd:3073` (`_generate_captives`):
chance = victim's `UnitData.captive_chance` (default `0.3`,
`scripts/resources/unit_data.gd:36`) + the killer side's `captive_chance_mod`
commander-trait bonus. Captives are credited to the winning faction after
combat in `battle_resolver.gd:139-143`. There is no other acquisition path
in the game today — every faction currently depends entirely on winning
fights to get captives.

Ivoryscar's own roster averages **captive_chance ≈ 0.133** across its 15
units (7 constructs/beasts explicitly zeroed — `bone_colossus`,
`tomb_jackal`, `scarab_swarm`, `relic_golem`, `great_scarab`, `bone_priest`,
`sand_wyrm`; 2 units at `0.1` — `ancient_champion`, `sand_mage`; 6 units at
the unset default `0.3` — `tomb_guard`, `bone_archer`, `ivoryscar_seeker`,
`bone_cavalry`, `relic_skirmisher`, `relic_scholar`). For comparison:
tainted_jade (the deliberate captive-economy faction) averages `0.125`,
skulloath `0.139`, empire/forsaken/cinderguard `0.17`. **Ivoryscar's capture
rate is not unusually weak** — it's in line with the other captive-consuming
factions. The gap the designer is feeling is entirely on the *sink* side.

**Decay.** `city_system.gd:1219` (`_process_captive_decay`) drains captives
via `calculate_captive_camp_decay` (`labor_camp` -3/turn, `thrall_quarters`
-2/turn, `captive_processing_camp` -4/turn — none of which ivoryscar owns)
plus flat natural attrition of 1 captive per 5 turns regardless of buildings.
So today an ivoryscar player who captures prisoners just watches them trickle
away at 1-per-5-turns with almost nothing to spend them on.

**Existing sinks catalogue** (all in `city_system.gd`,
`compute_faction_income_modifier_effects`, called once per owned city per
turn from `calculate_city_income` → `_apply_faction_income_modifier`,
`city_system.gd:131`):

| Faction | Building(s) | Cost | Payoff |
|---|---|---|---|
| skulloath | `blood_altar` | 4 captives/turn | +20 iron, +15 gold |
| skulloath | dilemma "Feed the Hunger" (`turn_manager.gd:3835`) | 10 captives | +12 corruption, +10 iron |
| skulloath | corruption ≥61/81 auto-conversion (`turn_manager.gd:3784-3791`) | 4-6 captives/turn | iron or food, automatic |
| tainted_jade | `thrall_quarters` / `captive_processing_camp` | 5 captives per 5 → wood+iron | scales, camp doubles it |
| tainted_jade | unit `thrall_swarm` recruit cost | **10 captives** (`recruit_cost = {0:15, 6:10}`) | cheap swarm infantry |
| moonspear | `lunar_observatory` / `astral_observatory` | 3 captives/turn | +10 tech |
| thunderswarm | `warriors_longhouse` / `warchief_warcamp` | 3 captives/turn | +10 gold, +3 storm fury |
| cinderguard | `ember_foundry` / `molten_core_forge` | 4 captives/turn | +18 iron |
| forsaken | `wretched_pit` / `necromancer_sanctum` | 3 captives/turn | +15 food |
| forsaken | `void_pit` | 3 captives/turn | +12 gold |
| sunblessed | `pilgrims_rest` / `cathedral_of_dawn` | 2 captives/turn | +5 population, +3 faith |
| empire | `labor_camp` / `imperial_work_yard` | 3-4 captives/turn | gold+iron |
| **ivoryscar** | `tomb_scholars_hall` / `vault_of_ages` (`city_system.gd:2621-2626`) | **3 captives/turn** | +8 tech, +4 relic power |

**Correction to the prior audit:** ivoryscar is *not* at zero — there is one
hook, riding on the existing cultural tech buildings. But it's the smallest
sink in the game, it's invisible (no dedicated building, no player choice,
no line in any dilemma or tooltip calling it out as "feed captives here"),
and it's gated behind a tier-2/3 building most players build for the tech
income, not the captive drain. That's the real gap: every *other*
captive-consuming faction has a dedicated, visible, thematic building or
choice; ivoryscar has a byproduct nobody notices.

**Recruit-cost-with-captives is a proven, fully generic pattern.** The only
existing precedent is `thrall_swarm` (`recruit_cost = {0: 15, 6: 10}`).
Affordability (`city_system.gd:1904`, `_can_afford`) and the dilemma-choice
cost check (`campaign_hud.gd:7896-7906`) both loop over the cost dict
generically — no resource-type special-casing anywhere, and `res_captives`
already has an icon (`game_manager.gd:225`). **Nothing in the UI/affordability
layer needs to change** to add captive-costed units or dilemma choices; this
is purely a data + one small `turn_manager.gd`/`city_system.gd` code problem.

## 2. Ivoryscar's current kit (what any proposal must slot into)

**Relic Power (0-50)** and **Black Pyramid Restoration (0-100)**, both in
`turn_manager.gd:_process_ivoryscar_relics` (`turn_manager.gd:5107-5265`):
- Relic power drifts toward a target set by shard-wastes tiles + owned
  shards + research/building bonuses; unlocks tech/gold/essence/diplomacy
  breakpoints at 10/20/25/30/40.
- Pyramid restoration (while `not fs.pyramid_restored`): `relic_power / 10`
  per turn, but **gated on 1 shard essence/turn** (stalls without it); every
  3rd turn also consumes a claimed shard crystal for +5. Milestones at
  25/50/75/100% grant escalating permanent bonuses; `pyramid_restored` is a
  one-time flag flip at 100.
- **Relic Expedition dilemma** fires every 5 turns once `relic_power >= 15`
  (player gets a dialog; AI auto-resolves). Current choices: `relic_fund`
  (30 gold + 5 tech → 65% relic/20% tech/15% danger), `relic_study` (free,
  +5 tech +2 power), `relic_fortify` (free, +3 defense/3 turns), and
  `pyramid_invest` (40 gold+15 iron+5 essence+1 shard crystal → +15
  restoration) once not yet restored.

**Roster is already thematically undead** — no new "skeleton legion" concept
is needed, it exists: `bone_colossus`, `tomb_guard`, `bone_archer`,
`bone_priest`, `ancient_champion` all carry the `undead` tag. There is
**no mummy unit** and no unit with a captive-paid recruit cost. AI recruiting
already favors this identity: `FACTION_RECRUIT_TAG_WEIGHTS[&"ivoryscar"] =
{"undead": 12, "heavy": 10}` (`turn_manager.gd:932`) — any new undead/heavy
unit is automatically AI-attractive once affordable.

**Building chains relevant here:** `ancestor_crypt` (T1, cultural,
`unlocks_units = []`, +1 relic_power_bonus) → `tomb_scholars_hall` (T2,
unlocks `relic_scholar`/`bone_priest`/`sand_mage`) → `vault_of_ages` (T3,
`exclusive_group = "ivory_legacy"` shared with the `bone_arsenal` military
line); `seekers_lodge` (T1, military, unlocks `ivoryscar_seeker` +
`relic_skirmisher`); `bone_stables` → `bone_arsenal` (T3, unlocks the heavy
constructs). The AI's per-turn build order is a hardcoded priority list,
`FACTION_BUILD_PRIORITIES[&"ivoryscar"]` (`turn_manager.gd:792`):
`[seekers_lodge, sandstone_pit, petrified_quarry, dust_fields, bone_quarry,
relic_shrine, caravan_depot, relic_workshop, ancestor_crypt, bone_palisade]`
— walked in order, first affordable-and-available entry wins, one build per
city per turn. **A new building needs an explicit slot in this list or the
AI will never build it.** Note the comment at `turn_manager.gd:767-780`:
ivoryscar has zero native wood income, so anything inserted before
`dust_fields`/`bone_quarry` that costs wood can silently wedge the whole
list. New entries should avoid wood cost or sit after those two.

Research: `tomb_lords` branch (`iv_tomb_builders → iv_death_masks/
iv_tomb_guardians → iv_pharaoh_guard/iv_tomb_wealth → iv_ancient_pharaoh/
iv_eternal_dynasty`) is the necromancy/pharaoh-flavored line; `relics`
branch (`tomb_raiding → reliquary_vault → iv_relic_army → iv_eternal_tomb`)
is the expedition-flavored line. Neither currently touches captives.
Caution: two existing tier-5 techs (`fk_death_eternal`, `tj_blood_god`) have
*description text* promising captive-related effects ("catacomb metropolis
converts food to captives", "captives generate 3x resources") that **are not
backed by any code** — confirmed by grep, zero references to either tech id
outside the `.tres` files. Don't repeat that pattern: any captive mechanic
promised in flavor text needs a real hook, not just a description.

## 3. Proposal — a five-piece kit

Ordered acquisition → sinks, all keyed to `&"ivoryscar"` in the same places
the other 10 factions already hook captives, so this is consistent with
existing patterns rather than a bespoke new system.

### 3.0 ACQUISITION — Slave Market (the anchor; addresses "produce captives")

New economic building chain. This is the piece that makes the whole kit
self-sustaining instead of war-dependent.

**Slave Market I** (`slave_market`, new building)
- `build_cost = {0: 40, 1: 10}` (gold+iron — **no wood**, avoids the
  wood-choke problem noted above)
- `build_time = 2`, `required_capital_level = 1`, **no `requires_research`**
  (immediately buildable, like `tomb_kennels`/`seekers_lodge`)
- `income_bonus = {0: 5}` (secondary gold trickle from the trade itself,
  ~4 effective after the standard 0.85× building-income multiplier)
- `population_growth_bonus = -1` (slave pens are not a pleasant neighbor)
- `class_loyalty_bonus = {"peasants": -3, "nobles": 3, "artisans": 1,
  "captives": -6}` — nobles profit, commoners are uneasy, captives (obviously)
  hate it. Matches the polarity of `blood_altar`'s `{"peasants": -4,
  "nobles": 2}` and `captive_processing_camp`'s `{"captives": -8}`.
- `upkeep_cost = {0: 3}`
- **New code hook**, `city_system.gd`, `compute_faction_income_modifier_effects`,
  `&"ivoryscar"` arm (right next to the existing `tomb_scholars_hall` check
  at `city_system.gd:2621-2626`): `if city.buildings.has(&"slave_market") or
  city.buildings.has(&"slave_bazaar"): local_captives +=
  (4 if city.buildings.has(&"slave_bazaar") else 2)`. The existing
  `captive_consumption = start_captives - local_captives` math already
  supports *negative* consumption (i.e. a gain) with zero changes to the
  wrapper in `_apply_faction_income_modifier` — confirmed by reading that
  function; it's a plain delta.

**Slave Bazaar II** (`slave_bazaar`, upgrade)
- `upgrades_from = &"slave_market"`, `required_capital_level = 2`,
  `requires_research = &"tomb_raiding"` (existing tier-2 econ tech, "every
  ruin holds treasures for those brave enough to seek" — reads naturally as
  raiding parties bringing back captives, not just relics)
- `build_cost = {0: 95, 1: 25}`, `income_bonus = {0: 12}`
- `class_loyalty_bonus = {"peasants": -4, "nobles": 5, "artisans": 2,
  "captives": -8}`
- Captive gain +4/turn (via the shared hook above)

**AI build order:** insert `&"slave_market"` into
`FACTION_BUILD_PRIORITIES[&"ivoryscar"]` right after `&"bone_quarry"` and
before `&"relic_shrine"` — after the two wood-economy fixes, early enough to
matter. The Bazaar upgrade needs no separate list entry; the existing
"build any available upgrade" fallback branch in `_execute_ai_city_management`
(`turn_manager.gd:873-878`) already picks it up automatically, the same way
`relic_shrine → relic_sanctum` upgrades happen today.

**The arithmetic** (why this is sized right): steady per-turn captive drain
if a player runs every sink below full-tilt: 1-2× `tomb_scholars_hall`/
`vault_of_ages` (-3 to -6) + Pyramid Labor while unrestored (-5, §3.1) ≈
**-8 to -11/turn** at peak. One Slave Market alone (+2) roughly offsets a
single tomb-hall's drain; two Markets or one upgraded Bazaar (+4 to +6)
covers the passive tech/relic-power sink outright and leaves a couple
captives/turn spare toward the Pyramid Labor sink. Fully funding *all* sinks
simultaneously (including bursty recruit-cost spends, §3.3-3.4) still needs
battle captures on top — exactly the "steady base, battle captures are the
variable topper" framing requested, and it puts ivoryscar in the same
position as skulloath/tainted_jade, whose dedicated sinks (`blood_altar`
4/turn, thrall economy) also assume active war footing to run at full tilt.

### 3.1 PYRAMID LABOR (MVP)

Location: `turn_manager.gd:5167-5192`, the Black Pyramid Restoration block.
Add an automatic "Slave Crews" drain alongside the existing shard-essence
gate, unconditional like `blood_altar` (no dilemma needed):

```gdscript
if not fs.pyramid_restored:
    var restoration_gain := fs.relic_power / 10
    ... # existing essence/shard-crystal logic unchanged
    # NEW: captives worked to death hauling stone
    var pl_captives := fs.resources.get(Enums.ResourceType.CAPTIVES, 0)
    if pl_captives >= 5:
        fs.resources[Enums.ResourceType.CAPTIVES] = pl_captives - 5
        fs.pyramid_restoration = mini(fs.pyramid_restoration + 3, 100)
```

5 captives → +3 restoration/turn, independent of and stacking with the
existing relic-power/essence path. Self-disables the moment
`pyramid_restored` flips true, so it's a finite, midgame-relevant sink, not
a permanent lategame tax. **MVP: yes** — three lines in an existing
function, no new UI (the pyramid progress is already surfaced in the
`relic_expedition` dilemma title and, per the bounded-siege-capture work,
likely a HUD meter already). **Later option:** make it a toggle (dilemma
choice or a settable flag) instead of automatic, for players who'd rather
bank captives for population conversion elsewhere — flagged as an open
question below.

### 3.2 EXPEDITION LABOR

Location: the `relic_expedition` dilemma choice list (`turn_manager.gd:5216-5234`)
and its resolution (`turn_manager.gd:253-292`). Add a captive-funded variant,
shown only when affordable (`fs.resources.get(CAPTIVES,0) >= 15`), sitting
next to `relic_fund`:

```gdscript
{"label": "Send the Slaves", "description": "Send 15 Captives into the deep tombs. 55%: rich find (+12 power, +item). 25%: knowledge (+10 tech). 20%: the tombs claim them (captives lost, nothing gained).", "effect": "relic_slaves", "cost": {6: 15}}
```

Slightly better odds and payout than the gold-funded `relic_fund` (which is
65/20/15 for +8 power) since the stake is captives, not treasury gold+tech —
"expendable labor, not real risk." AI: extend the existing non-player branch
(`turn_manager.gd:5236-5265`) to try `relic_slaves` when captives ≥15 **and**
gold <30 (i.e. as the fallback before the current weakest branch that just
grants +2 power/+5 tech for free) — this plugs an existing AI gap where a
gold-poor ivoryscar AI currently sits on unused captives while taking the
worst outcome every 5 turns. **MVP: yes**, small and reuses the exact
existing dilemma/AI pattern — no new UI (cost-dict rendering is generic,
confirmed in §1).

### 3.3 SLAVE WARRIORS (MVP)

New unit **Bound Levy**, unlocked from the existing `seekers_lodge` (T1,
already unlocks `ivoryscar_seeker` + `relic_skirmisher` — add
`&"bound_levy"` to its `unlocks_units` array; **zero new buildings**).

- `max_hp = 3000`, `attack = 40`, `melee_defense = 8`,
  `projectile_defense = 5`, `magic_defense = 0`, `speed = 4`,
  `squad_size = 80`, `hp_per_soldier = 38`
- `recruit_cost = {6: 12}` — **captives only**, no gold/iron. This is the
  distinguishing hook: once the Slave Market is running, Bound Levy is
  effectively a free (but weak) unit that converts a captive glut directly
  into army bodies.
- `upkeep_cost = {3: 2}` (food, they still need feeding)
- `recruit_time = 1` (herded to the front, no training)
- `tags = ["infantry", "melee", "light"]`, `base_morale = 25`
  (unwilling conscripts — weak and prone to breaking)
- `captive_chance` left at default (`0.3`): a defeated Bound Levy squad can
  itself yield captives back to whoever kills it — thematically consistent.

**AI usage, honestly assessed:** Bound Levy's raw score (attack + avg
defense ≈ 44) is well below `ivoryscar_seeker`'s (≈76) in the AI's unit-pick
formula (`turn_manager.gd:980-989`), and it carries no tag from
`FACTION_RECRUIT_TAG_WEIGHTS`. The AI will rarely choose it over the seeker
under current scoring, so in practice **this is primarily a player-facing
captive-dump valve**, not a core AI army-comp driver. That's fine for MVP —
call it what it is rather than oversell it. **Later option:** add a small
score bonus when `fs.resources[CAPTIVES]` is above some threshold, so AI
factions also use it as a release valve instead of just player armies.

### 3.4 UNDEAD CONVERSION

New unit **Grave-Bound Mummy**, unlocked from `ancestor_crypt` (T1,
cultural, currently `unlocks_units = []` — add `&"grave_bound_mummy"`;
zero new buildings for MVP, see open question below on whether it deserves
its own).

- `max_hp = 6000`, `attack = 70`, `melee_defense = 45`,
  `projectile_defense = 25`, `magic_defense = 15`, `speed = 3`,
  `squad_size = 60`, `hp_per_soldier = 100`
- `recruit_cost = {1: 20, 6: 14}` — iron (wrappings/preservatives) +
  14 captives ("worked to death, then raised" — heavier than Bound Levy
  since this is a permanent mid-tier unit, not a one-shot filler)
- `recruit_time = 3` (embalming takes time), `upkeep_cost = {0: 4}`
- `tags = ["infantry", "melee", "undead", "heavy"]` — **both tags are
  already in `FACTION_RECRUIT_TAG_WEIGHTS[&"ivoryscar"]`** (+12 undead, +10
  heavy = +22 combined score bonus), so unlike Bound Levy, **the AI will
  actively want this unit** once it can afford the captive cost — real
  synergy with existing code, no new AI work needed.
- `base_morale = 90` (undead, fearless), `captive_chance = 0.0` (raised
  dead don't take prisoners of their own will)

**MVP: yes** for the same reason as Bound Levy — one data file + a
one-line `unlocks_units` edit, no new code paths beyond the recruit-cost
plumbing already proven generic.

## 4. MVP cut

**Ship together (closes the "no accessible sink" gap with minimal surface):**
1. Slave Market I + Slave Bazaar II (§3.0) — the acquisition anchor
2. Pyramid Labor auto-drain (§3.1) — guaranteed passive sink, 3 lines of code
3. Bound Levy unit (§3.3) — direct, visible "recruit away your prisoners" outlet

**Phase 2 (equally cheap, but not required to solve the core complaint):**
4. Expedition Labor dilemma variant (§3.2) — periodic, nice-to-have
5. Grave-Bound Mummy (§3.4) — roster depth, the "mummy" ask specifically
6. AI captive-dump weighting for Bound Levy; toggle option for Pyramid Labor

Everything above reuses existing plumbing (`compute_faction_income_modifier_effects`,
the generic dilemma-cost renderer, the generic recruit-cost affordability
check, `FACTION_RECRUIT_TAG_WEIGHTS`) — no new systems, no new UI code.

## 5. Open questions for the designer

1. **Pyramid Labor: automatic drain or player toggle?** Automatic (like
   `blood_altar`) is simplest and matches precedent, but forces captives
   into the pyramid even if a player wanted to bank them for Bound
   Levy/Mummy recruitment instead.
2. **Is a pure-captive-cost (`{6: 12}`, no gold/iron) Bound Levy too
   strong** once the Slave Market is running — effectively a free unit — or
   is that exactly the "meat-grinder slave army" fantasy intended?
3. **Should Grave-Bound Mummy get its own building** (e.g. a new
   "Embalming House") instead of piggybacking on `ancestor_crypt`, to give
   the necromancy theme a visible dedicated slot/upgrade line of its own?
4. **Slave Bazaar's research gate** — reuse `tomb_raiding` (as proposed) or
   spin up a dedicated tech (e.g. "Slave Caravans") in the `tomb_lords`
   branch for thematic ownership and a socket-bonus opportunity?
5. Given ivoryscar's capture rate is already average (not weak, §1), is
   the Slave Market meant to make ivoryscar **better** at captives than
   peers (a faction identity claim), or just **self-sufficient** so a
   builder-style non-warmonger ivoryscar isn't captive-starved?
