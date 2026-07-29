# Special Regional Resources — Design Proposal

*Drafted 2026-07-29. Status: proposal, not implemented.*

## Goal

Give parts of the map a distinct economic identity beyond terrain art: rare
resources that exist only in certain regions, so that owning (or trading with
whoever owns) a region *matters*. Three payoffs:

1. **Regional identity** — "the Moonsilver mountains", "the Spice plains"
   become places with names players remember and fight over.
2. **Trade & diplomacy content** — asymmetric scarcity creates genuine reasons
   to trade, lease access, embargo, or declare war. Today trade is
   resource-for-resource arbitrage; special resources add *things only one
   neighbor has*.
3. **Faction goals** — each faction has an affinity resource that superpowers
   its mechanic, giving every AI (and player) a natural territorial ambition
   that reinforces its playstyle.

## What we already have to build on

- Regions with income dicts and completion bonuses (`data/regions/*.tres`,
  `game_manager.change_region_owner`).
- Terrain gating for buildings (`required_terrain`, e.g. Blessed Springs
  requires desert) — precedent for "this only exists here".
- Shard Wastes as terrain-bound value (essence trickle, Ivoryscar relic power)
  — the proof that location-bound economy works in this game.
- A deep trade/diplomacy layer: trade deals with duration, gifts with
  faction-specific gift-tag preferences, counter-offers, greed, "most needed
  resource" valuation (`diplomacy_system.gd`) — ready to price new goods.
- `special_effects` on buildings — the modifier plumbing already exists.

## Two-tier resource roster

Two tiers with different jobs. **Bounty resources** are common, multi-terrain
goods (orchards, marble, wild horses...) that make ordinary regions feel
individually useful and feed a commodity trade economy. **Special resources**
are rare, flavor-locked deposits with unique rules — they stand out precisely
*because* the map is already sprinkled with mundane bounties. Ratio ~1.5
bounty deposits for every special deposit on the map.

Design rules per tier:

- **Bounty**: 4-8 deposits each per map, 2+ valid terrains, exactly one small
  numeric bonus (no unique rules), any faction benefits equally. Tradeable as
  plain volume (they mostly boost existing resource incomes).
- **Special**: 1-3 deposits each, narrow terrain, a unique identity rule; the
  8 faction-affinity ones double for their faction. Tradeable only via
  exclusive Access leases → diplomacy content.
- **Not every type spawns every map**: roll ~60-70% of each tier's roster at
  map-gen, so campaigns differ ("this world has no Moonsilver at all").

### Tier 1 — Bounty resources (22 types, common, not flavor-locked)

| Resource | Terrains | Bonus (region owner) |
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

### Tier 2 — Special resources (15 types, rare, identity-defining)

The 8 **faction-affinity** specials (affinity faction gets the modifier
doubled, plus a flagship effect at 2+ deposits — see below):

| Resource | Terrain | Base yield/turn | Identity modifier (region owner) | Affinity |
|---|---|---|---|---|
| **Moonsilver** | Tundra / Mountains | +6 iron | -10% recruit cost for `heavy` units | Moonspear |
| **Sunstone** | Desert | +6 gold | +5% cultural building income | Sunblessed |
| **Deepiron** | Mountains | +10 iron | +5% army defense in owned territory | Cinderguard |
| **Heartwood** | Forest / Jungle | +8 wood | +5% food income | Gladehost |
| **Shardglass** | Shard Wastes | +2 shard essence | +10% research toward `arcane` techs | Ivoryscar / Shardhorde |
| **Saffron Reeds** | Plains / Wetlands | +8 gold | +15% gold from trade deals | Empire |
| **Bloodsalt** | Swamp / Wetlands | +4 food | +25% captive conversion rates | Skulloath / Tainted Jade |
| **Stormcrystal** | Mountains | +4 tech | +5% army speed | Thunderswarm |

Plus 7 **neutral specials** — powerful, unaligned, everyone wants them
(these are the "special specials" that headline a map):

| Resource | Terrain | Unique rule |
|---|---|---|
| **Dragonbone Fields** | Desert / Shard Wastes | -15% recruit cost for `monster`/`beast`; units recruited here gain +1 fear radius |
| **Everfrost Core** | Tundra | Region armies immune to winter penalties; +10% defense in own territory during winter |
| **Sungold Vein** | Mountains / Desert | +15 gold/turn, but -2 noble loyalty in region cities (greed) — a tradeoff deposit |
| **Worldroot Nexus** | Jungle / Forest | Armies in region heal double; +1 population growth in adjacent regions too |
| **Voidglass Rift** | Shard Wastes / Swamp | +3 shard essence, +10% arcane research; -1 loyalty region-wide (whispers) |
| **Titan Forge-Ruin** | Mountains | `construct` units here cost -25% and start at Trained veterancy |
| **Leyline Well** | any tile with realm influence | Socketed crystal bonuses of the owner count +50% stronger |

Numbers are placeholders scaled to early income (~25-40 gold/turn): a bounty
should read as "nice region", a special as "strong region worth a war"
(~15-25% swing in its niche), never a game-winner.

## Mechanics

### Placement (map generation)
- New pass in `map_generator.gd` after terrain: roll the map's roster
  (~60-70% of each tier's types), then place deposits biased by terrain.
  Bounties: 4-8 deposits each, loose spacing. Specials: 1-3 each, wide
  minimum distance. Overall mix ≈ 1.5 bounty deposits per special deposit.
- Fairness rule: **each major faction's starting area is within ~2 regions of
  at least one bounty, and every affinity special that spawned is reachable
  by its faction (not across the entire map).**
- Data: `region.region_resource: StringName` (empty = none) + a `tier` flag +
  one marked hex tile inside the region for the map icon. Save-compatible
  (defaults empty). One resource per region max — a region IS its resource.

### Ownership & extraction
- Owning the region grants the yield/bonus automatically — bounties need
  nothing else (zero-friction: common goods should not add micromanagement).
- **Specials only**: a T2 **Extractor** building (one flavored variant per
  special: Moonsilver Mine, Spice Terraces, Dragonbone Digsite...), buildable
  only in a city of that region, doubles the base yield and unlocks the
  *Access lease* (below). Uses existing `required_terrain`-style gating plus
  a new `requires_region_resource` field on BuildingData.

### Trade & diplomacy hooks
1. **Bounty regions feed normal trade**: their yields raise plain resource
   incomes, so the existing trade-deal system automatically gets more volume
   and more asymmetry (the orchard-rich neighbor really does have spare food).
   No new mechanics needed for tier 1.
2. **Resource Access deal** (specials only; new treaty type alongside trade
   deals): the owner leases the *identity modifier* (not the yield) to a
   partner for gold/turn, duration-limited like current trade deals. Requires
   an Extractor. One lessee per deposit — exclusivity makes deals competitive.
3. **AI valuation**: extend `_get_faction_most_needed_resource` /greed logic —
   an AI missing its affinity resource values access deals at 1.5-2x and
   weights gift/counter-offer math accordingly.
4. **Embargo lever**: cancelling an access deal mid-war already falls out of
   existing treaty-breaking rules; add a standing penalty when cancelled
   without war ("trade betrayal").
5. **War goals**: in the AI war score (`diplomacy_system.gd:1251`), add
   `+10 if target owns a deposit of my affinity resource` — wars start over
   resources, visibly.
6. **Region tooltips/diplomacy UI**: deposit icon + "Access: leased to X"
   line; the diplomacy world map (right panel) can tint deposit regions.

### Faction affinity payoffs (the flavor layer)
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
| Data | `scripts/core/region_data` / hex tile | `special_resource` field + marked tile |
| Placement | `scripts/utils/map_generator.gd` | deposit pass + fairness rule |
| Income | `scripts/systems/campaign/city_system.gd` | region yield + modifier hooks |
| Buildings | `scripts/resources/building_data.gd` + `data/buildings/` | `requires_region_resource`, 15 extractor variants (specials only) |
| Diplomacy | `scripts/systems/campaign/diplomacy_system.gd` | access-deal treaty, AI valuation, war-score term |
| AI | `scripts/autoloads/turn_manager.gd` | expansion targeting weight toward affinity deposits |
| UI | `campaign_hud.gd` (region overview, diplomacy panel), map icons | icons, tooltips, deal UI |
| Save | serialize new fields (defaults keep old saves loading) |

## Phasing

1. **MVP** — placement + map icons + base yields + region tooltip. (Pure
   economy; no new UI flows.) Immediately creates "rich regions".
2. **Phase 2** — extractor buildings + Resource Access deals + AI valuation.
   This is where trade/diplomacy depth lands.
3. **Phase 3** — faction affinities, flagship effects, war-goal weighting,
   diplomacy-map tinting.

## Risks / open questions

- **Balance**: identity modifiers stack with faction mechanics — cap total
  swing per niche (~25%) and keep yields linear.
- **Map fairness**: the fairness rule needs testing across map sizes; a
  faction spawning far from its affinity resource should be a *goal*, not a
  death sentence (hence base yields are generic resources anyone can use).
- **UI surface**: the access-deal flow adds one more diplomacy verb — reuse
  the existing trade-dialog skeleton to keep cost down.
- **Do independents own deposits?** Yes — independent cities on deposits
  become prized diplomatic targets (defection at standing ≥40 already exists,
  which becomes a peaceful route to a deposit).
