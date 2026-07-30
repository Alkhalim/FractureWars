# Special Regional Resources — Design Proposal

*Drafted 2026-07-29, revised same day after design review. Status: proposal,
not implemented.*

## Goal

Give parts of the map a distinct economic identity beyond terrain art: rare
resources that exist only in certain places, so that owning (or trading with
whoever owns) a location *matters*. Three payoffs:

1. **Regional identity** — "the Moonsilver mountains", "the Dragonbone
   flats" become places with names players remember and fight over.
2. **Trade & diplomacy content** — asymmetric scarcity creates genuine
   reasons to trade, lease access, embargo, or declare war.
3. **Faction goals** — affinity resources superpower faction mechanics,
   giving every AI (and player) a natural territorial ambition.

## What we already have to build on

- Terrain gating for buildings (`required_terrain`) — precedent for "this
  only exists here".
- Shard Wastes as terrain-bound value — proof that location-bound economy
  works in this game.
- A deep trade/diplomacy layer (deals with duration, gift preferences,
  counter-offers, greed, "most needed resource" valuation) ready to price
  new goods.
- `special_effects` on buildings — the modifier plumbing already exists.
- Settlement founding with income preview — the natural place to surface
  "this spot claims these resources".

## Three categories

| | **Bounties** | **Specials** (faction-affinity) | **Landmarks** (name confirmed 2026-07-29) |
|---|---|---|---|
| Types in roster | 22 | 8 | 7 |
| Per map | 4-8 deposits each (~60-70% of types spawn) | 1-3 deposits each (affinity ones guaranteed reachable) | **exactly 5 spawn, max 1 per type** |
| Visual | small icon in the **top-right corner of the terrain tile**, tooltip on hover | deposit art overlay per resource (shared style) | **replaces the terrain tile entirely; unique hand-made art per Landmark** |
| Placement | terrain-appropriate, spread widely | narrow terrain bands | terrain-fitting, **roughly evenly distributed across the map**, each **adjacent to a neutral/independent city** at spawn |
| How you get it | **proximity claim**: a city or settlement within radius 2 claims it automatically | own the region + build its Extractor in a region city | conquer/befriend your way to it + build its **unique dedicated building on the tile itself** |
| Building | none (zero micromanagement) | Extractor variant (T2, faction-agnostic) | one **unique building per Landmark, shared across all factions**; it is the *only* thing buildable on that tile |
| Effect budget | one small numeric bonus | yield + identity modifier; doubled for affinity faction | one strong unique rule each |
| Trade | boosts normal resource income → feeds existing trade deals | exclusive Access lease (new treaty) | Access lease, high AI valuation |

### Claim rule for bounties (single-owner guarantee)

A bounty belongs to the **nearest owned city or settlement within radius 2**
(ties: lower city id wins, deterministic). Since settlements can only be
founded outside radius-3 of existing cities (`city_system.gd` founding rule),
two cities can rarely contest the same tile; the nearest-city rule resolves
the border cases so **one bounty is always claimed by exactly one city**.
Losing the city (conquest, razing) releases the claim to the new owner /
nobody.

The **settlement placement UI** lists every bounty/special/Landmark the new
site would claim (extends the existing settlement income preview), making
"settle toward resources" a visible decision.

### The Landmarks in detail

Spawning next to neutral cities does two things: the early map has visible
prizes guarded by someone, and independent-city diplomacy (defection at
standing ≥40) becomes a peaceful route to a Landmark. Their unique building
is the only structure allowed on the tile, is identical for all factions, and
starts the resource's effect once built (build cost ~T3-equivalent).

| Landmark | Terrain it replaces | Unique building | Unique rule |
|---|---|---|---|
| **Dragonbone Fields** | Desert / Shard Wastes | Dragonbone Digsite | -15% recruit cost for `monster`/`beast` faction-wide; units recruited in this region gain +1 fear radius |
| **Everfrost Core** | Tundra | Rimeheart Bore | Owner's armies immune to winter penalties; +10% defense in own territory during winter |
| **Sungold Vein** | Mountains / Desert | Sungold Mine | +15 gold/turn, but -2 noble loyalty in the claiming city (greed) — a tradeoff prize |
| **Worldroot Nexus** | Jungle / Forest | Rootwarden Enclave | Armies in the region heal double; +1 population growth in adjacent regions |
| **Voidglass Rift** | Shard Wastes / Swamp | Rift Stabilizer | +3 shard essence/turn, +10% arcane research; -1 loyalty region-wide (whispers) |
| **Titan Forge-Ruin** | Mountains | Reforged Foundry | `construct` units cost -25% faction-wide and start at Trained veterancy |
| **Leyline Well** | any realm-influenced tile | Attunement Circle | Socketed crystal bonuses count +50% stronger for the owner |

Each map rolls 5 of the 7 — every campaign is missing two Landmarks, so no
fixed "always rush X" meta.

### Tier 1 — Bounty resources (22 types, common, not flavor-locked)

| Resource | Terrains | Bonus (claiming city's owner) |
|---|---|---|
| Orchards | Plains, Forest | +6 food |
| Grain Basin | Plains, Wetlands | +10 food |
| Vineyards | Plains | +5 gold, +1 loyalty (all classes) |
| Honey Apiaries | Plains, Forest | +4 food, +1 peasant loyalty |
| Herb Meadows | Plains, Swamp | +25% army healing in this region |
| Wild Horses | Plains, Tundra | -10% recruit cost for `cavalry` |
| Fisheries | Coastal (water-adjacent) | +8 food |
| Pearl Beds | Coastal | +6 gold, +20% gift value of gold gifts |
| Salt Flats | Desert, Wetlands | +4 food, +4 gold |
| Marble | Mountains, Desert | -15% build cost for `cultural` buildings |
| Granite | Mountains | +20% build speed in region cities |
| Basalt Columns | Mountains | -20% cost for `defensive` buildings |
| Copper Vein | Mountains, Desert | +5 iron, +3 gold |
| Obsidian Flows | Mountains, Shard Wastes | +1 attack for units recruited here |
| Titanstone Quarry | Mountains | -10% recruit cost for `construct` |
| Timber Giants | Forest, Jungle | +10 wood |
| Amber Groves | Forest, Tundra | +7 gold |
| Furs | Tundra, Forest | +5 gold, -10% upkeep in tundra |
| Crystal Springs | Tundra | +2 population growth in region cities |
| Clay Pits | Wetlands, Plains | -15% wood component of build costs |
| Peat Bogs | Swamp, Wetlands | -10% building upkeep in region |
| Dye Gardens | Jungle, Coastal | +8 gold from trade deals only |

### Tier 2 — Specials (8 faction-affinity types)

Affinity faction gets the modifier doubled, plus a flagship effect at 2+
deposits (see below).

| Resource | Terrain | Base yield/turn | Identity modifier (owner) | Affinity |
|---|---|---|---|---|
| **Moonsilver** | Tundra / Mountains | +6 iron | -10% recruit cost for `heavy` units | Moonspear |
| **Sunstone** | Desert | +6 gold | +5% cultural building income | Sunblessed |
| **Deepiron** | Mountains | +10 iron | +5% army defense in owned territory | Cinderguard |
| **Heartwood** | Forest / Jungle | +8 wood | +5% food income | Gladehost |
| **Shardglass** | Shard Wastes | +2 shard essence | +10% research toward `arcane` techs | Ivoryscar / Shardhorde |
| **Saffron Reeds** | Plains / Wetlands | +8 gold | +15% gold from trade deals | Empire |
| **Bloodsalt** | Swamp / Wetlands | +4 food | +25% captive conversion rates | Skulloath / Tainted Jade |
| **Stormcrystal** | Mountains | +4 tech | +5% army speed | Thunderswarm |

Numbers are placeholders scaled to early income (~25-40 gold/turn): a bounty
should read as "nice city spot", a special as "strong region", a Landmark as
"worth a war" — never a game-winner (~15-25% swing in its niche).

## UI

- **Bounty tiles**: small icon in the tile's top-right corner; hovering shows
  name, bonus, and claiming city (or "Unclaimed — settle within 2 tiles").
- **Landmark tiles**: full-tile unique art replaces the terrain; hover shows
  the rule + build state of its unique building.
- **Resource bar**: a new **"Special Resources" icon** next to the seven core
  resources. Clicking/hovering lists everything the player currently holds —
  claimed bounties, extracted specials, built Landmarks — plus anything
  gained via Access leases (marked "via trade with X" and lease turns
  remaining).
- **Settlement founding**: the placement preview lists all resources the new
  settlement would claim.
- **Diplomacy panel**: deposit icons on the world map; Access-lease line in
  faction detail ("Leased: Moonsilver access, 12 turns").

## Trade & diplomacy hooks

1. **Bounties feed normal trade**: their yields raise plain resource incomes,
   so the existing trade-deal system automatically gets more volume and more
   asymmetry. No new mechanics for tier 1.
2. **Resource Access deal** (specials + Landmarks; new treaty type): the
   owner leases the *identity modifier / rule* (not the yield) for gold/turn,
   duration-limited like current trade deals. One lessee per deposit —
   exclusivity makes deals competitive.
3. **AI valuation**: extend `_get_faction_most_needed_resource`/greed logic —
   an AI missing its affinity resource values access at 1.5-2x; every AI
   values Landmark access highly.
4. **Embargo lever**: cancelling an access deal without war costs standing
   ("trade betrayal"); at war it falls out of existing treaty-breaking rules.
5. **War goals**: in the AI war score (`diplomacy_system.gd:1251`), add
   `+10 if target owns a deposit of my affinity resource; +8 per Landmark` —
   wars visibly start over resources.

## Faction affinity payoffs (the flavor layer)

Affinity doubles the identity modifier and, at 2+ affinity deposits owned,
unlocks one flagship effect per faction (examples):
- Moonspear: Silverguard/Lunar Crusader upkeep -25%.
- Sunblessed: Golden Age dilemma threshold 85 → 75 faith.
- Cinderguard: fortress build costs -30% scrap.
- Skulloath/Jade: +1 captive per battle won.
These reuse existing mechanic hooks — no new systems.

## Integration map (files)

| Area | File | Change |
|---|---|---|
| Data | hex tile / region data | `region_resource` + `resource_tier` fields; Landmark tile type overrides terrain |
| Placement | `scripts/utils/map_generator.gd` | roster roll, bounty scatter, special bands, Landmark pass (5 of 7, max 1 each, even spread, adjacent to independent cities) |
| Claiming | `scripts/systems/campaign/city_system.gd` | nearest-city-within-2 claim resolution on found/conquer/raze; settlement preview additions |
| Income | `city_system.gd` | claimed-bounty bonuses, special yields, Landmark rules |
| Buildings | `building_data.gd` + `data/buildings/` | `requires_region_resource`; 8 extractor variants; 7 unique Landmark buildings (faction_id empty = shared) |
| Diplomacy | `diplomacy_system.gd` | Access-lease treaty, AI valuation, war-score terms |
| AI | `turn_manager.gd` | expansion/settling weight toward unclaimed bounties and affinity deposits |
| UI | `campaign_hud.gd`, tile renderer | corner icons + tooltips, Landmark tile art, resource-bar "Special Resources" list, founding preview |
| Art | `assets/sprites/campaign_map_v2/` | 7 unique Landmark tiles, 22 bounty corner icons, 8 deposit overlays |
| Save | serialize new fields (defaults keep old saves loading) |

## Phasing

1. **MVP — IMPLEMENTED 2026-07-29** (see tests/test_bounty_system.gd) —
   bounty scatter + corner icons + proximity claims + resource-bar
   list. (No new buildings; immediate "settle toward resources" gameplay.)
2. **Phase 2 — IMPLEMENTED 2026-07-30** (see tests/test_special_resources.gd) —
   specials with extractors + Access leases + AI valuation.
3. **Phase 3** — Landmarks: unique tiles/art, unique shared buildings,
   neutral-city adjacency, war-goal weighting, affinity flagship effects.

### Phase 1 implementation notes

`BountySystem.BOUNTY_TYPES` (`scripts/systems/campaign/bounty_system.gd`)
ships all 22 bounty types with real terrain/spacing scatter, radius-2 claim
resolution, corner icons + tooltips, and the resource-bar list — but 11 of
the 22 have design-doc effects that don't have a hook to plug into yet.
Those entries carry a `deferred` string (the intended rule) plus a
provisional `income` stand-in so the bounty still matters economically
until Phase 1.5 wires up the real mechanic:

| Bounty | Deferred effect kind | Provisional stand-in |
|---|---|---|
| `herb_meadows` | army healing (+25% in region) | +4 Food |
| `pearl_beds` | gift value (+20% on gold gifts) | +6 Gold |
| `marble` | build cost (-15% cultural buildings) | +6 Gold |
| `granite` | build speed (+20% in region cities) | +4 Iron |
| `basalt_columns` | defensive-building cost (-20%) | +4 Iron |
| `obsidian_flows` | unit attack (+1 for units recruited here) | +4 Iron |
| `crystal_springs` | population growth (+2 in region cities) | +3 Gold |
| `clay_pits` | build cost, wood component (-15%) | +5 Wood |
| `peat_bogs` | building upkeep (-10% in region) | +6 Wood |
| `furs` | army upkeep, tundra (-10%) | +5 Gold |
| `dye_gardens` | trade-only gold (counts toward trade deals only) | +8 Gold |

None of these are blocking for MVP — every bounty already produces a real,
claimable income/loyalty/recruit-discount effect. Phase 1.5 should replace
each stand-in with its documented rule once the relevant hook exists
(healing modifier, gift-value modifier, per-category build cost/speed
modifiers, upkeep modifiers, population-growth modifier, unit-attack
modifier, trade-only income flag).

### Phase 2 implementation notes

`SpecialResourceSystem` (`scripts/systems/campaign/special_resource_system.gd`)
ships all 8 specials with region-bound scatter, the universal Extractor
building per type, Access-lease treaties, AI valuation, and AI-side
initiation — but one point departs from this doc's original text, and a
few pieces named in the original proposal are deliberately out of scope
this phase:

- **DESIGN REFINEMENT: the Extractor activates BOTH the yield and the
  identity modifier**, replacing this doc's earlier "automatic yield,
  extractor doubles [the modifier]" split (§ Tier 2 table above, and the
  category table's "How you get it" row). Un-extracted deposits now
  produce nothing at all — no yield, no modifier — until the owner's
  region builds the Extractor. Rationale: (1) battle-determinism safety —
  an "automatic" yield that starts the moment a region is owned, with no
  build step, is a passive per-turn income source with no fingerprint-safe
  place to gate it against the AI building queue; gating both effects
  behind one building keeps the whole feature inside the existing
  build-queue/income-recalculation hooks instead of adding a second,
  build-less income path. (2) Build-to-exploit clarity — a single
  "build this to get anything at all" trigger is a simpler, more legible
  incentive than "yield is free, modifier needs a building," and matches
  how bounties (free) and Landmarks (building-gated) are already
  differentiated by tier. (3) Lease prerequisite — Access leases lease the
  *extractor's* effect (`extracted_specials_of_faction` requires
  `region_has_extractor`), so a deposit has to be extracted before it can
  be leased at all; splitting yield from modifier would leave leases
  either transferring an un-buildable yield or requiring a second
  eligibility check.
- **Yields ride the Extractor's normal `income_bonus`** — there's no
  separate "special resource income" pipeline; the Extractor is an
  ordinary T2 building whose `income_bonus` field carries the deposit's
  per-turn yield, so it flows through the same city-income calculation as
  every other building.
- **Lease exclusivity is scoped per (owner, special)** — `TreatyInstance`
  lookups key on `faction_a == owner AND terms.special_id == special_id`,
  so a deposit can only be leased out by its owner to one lessee at a
  time, but if the same special type exists as separate deposits owned by
  different factions, each owner runs its own independent exclusivity
  (there is no single global "one lessee per special type" lock).
- **AI builds Extractors when a city's region holds a deposit**: before
  falling back to its faction's generic build-priority list, the AI build
  loop (`turn_manager.gd`) checks whether the city's region has an
  unclaimed special and, if the matching Extractor is buildable, queues it
  first — so AI factions reliably feed the lease market instead of sitting
  on unclaimed deposits.
- **AI initiates affinity-seeking leases (AI → AI only)**: an AI missing
  its own affinity special looks for another AI faction (never the player)
  that already extracts it and, if not at war and not already leased
  elsewhere, proposes a lease for itself as lessee
  (`diplomacy_system.gd`, `_affinity_specials_of` + the per-turn AI
  diplomacy pass). The reverse direction — an AI *owner* offering a lease
  to another party unprompted — is not implemented; leases only originate
  from the would-be lessee's side.

Deferred to a follow-up phase (not implemented, out of scope for this
phase's tests):
- **Flagship effects at 2+ affinity deposits** — the per-faction bonus
  effects listed under "Faction affinity payoffs" above (Silverguard
  upkeep -25%, etc.) do not exist yet; only the doubled identity modifier
  from Extractor + affinity is live.
- **AI → player lease offers** — the AI never proposes a lease *to* the
  player as lessee; `propose_resource_lease` still supports an AI owner
  deciding whether to accept a player-initiated request, but nothing
  triggers the AI to reach out first.
- **Owner-side veto for AI-to-AI leases** — when both parties are AI,
  `propose_resource_lease` only evaluates the lessee's side
  (`_evaluate_lease_as_lessee`); the owning AI has no independent
  accept/reject check of its own, unlike the AI-owner-vs-player-lessee
  path, which does check standing and minimum pay.
- **Offer-likelihood UI for leases** — there's no player-facing indicator
  of how likely an AI is to accept a proposed Access lease before the
  player commits to the offer.
- **Placement reachability fairness** — special deposits scatter by
  terrain band and spacing only; there's no check that every faction (or
  every affinity faction) has a reasonably reachable deposit of its own
  affinity type on a given map.

## Risks / open questions

- ~~**Category name** for the Landmarks tier~~ — DECIDED 2026-07-29:
  **Landmarks**.
- **Balance**: modifiers stack with faction mechanics — cap total swing per
  niche (~25%) and keep yields linear.
- **Art cost**: 7 unique tiles + 22 icons + 8 overlays is the largest asset
  ask in the proposal; tile art can reuse the generated-tile pipeline
  (`tests/tools_generate_terrain_tiles.gd`) for consistency.
- **Landmark adjacency**: "next to a neutral city" needs a fallback when map
  gen places few independents (spawn the independent city *with* the
  Landmark in that case).
- **Claim radius**: spec says 2-3; radius 2 is the safe default given the
  radius-3 founding exclusion guarantees single claimants in almost all
  layouts — needs playtesting on small maps.
