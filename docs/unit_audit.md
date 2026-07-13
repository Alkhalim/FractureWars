# FractureWars — Unit Roster Audit

*July 2026. Method: every one of the 275 units was fought against a fixed
reference opponent (Empire Legionary) inside the **real battle simulator**
(`tests/tmp_unit_audit.gd`, 900 ticks, normal deployment so archers get their
volleys off before contact). "Power" = damage dealt + surviving HP/8.
"Value" (VPC) = power ÷ total recruit cost. This measures what units actually
do in battle, not what the unit card claims.*

---

## Executive summary

Three structural faults, in order of severity:

1. **Ranged units are the best buy in 10 of 11 factions.** Archers average
   **VPC 76** vs infantry 41, cavalry 32, monsters 19. They win because they
   destroy the enemy *while it walks toward them* and then survive: 33 of 44
   archer types finish the fight alive, most at ~100% HP. There is no real
   reason to build anything else.
2. **Cost is not derived from power.** Within a single faction the value
   spread is **14× to 58×** (Empire: Imperial Chariot 0.9 vs Imperial Crossbow
   52.3). 64 of ~165 major-faction units are **strictly dominated** — a
   cheaper stablemate is better at damage, toughness *and* speed. Those units
   are dead content.
3. **The unit card lies.** The HUD's DPS estimate (`estimate_unit_dps`) does
   not model the simulator: it ignores armor mitigation, the volley/ammo model,
   and *cleave for single large entities*. This is exactly what you noticed —
   the card says Steppe Rider 900 vs Warband Raider 3900 (4.3× gap). In the
   actual engine the gap is **1.7×** (2211 vs 3822 damage). The mammoth's card
   says 200 DPS; in the engine it deals 7200.

---

## Your two examples, measured

| Unit | Cost | Damage dealt | HP left | Value |
|---|---|---|---|---|
| Warband Raider (infantry) | 71 | 3822 | 0% | **53.8** |
| Steppe Rider (cavalry) | 71 | 2211 | 0% | **31.1** |

Same price. The rider deals 42% less damage **and dies just as fast** — its
speed 9 buys nothing in a stand-up fight because it charges in and gets stuck.
The card's "900 vs 3900" is a display bug on top of a real 1.7× imbalance.

| Unit | Cost | Range | Damage | HP left | Value |
|---|---|---|---|---|---|
| Steppe Archers | 81 | 3 | 6946 | **100%** | **90.4** |
| Steppe Skirmishers | 96 | 2 | 6203 | 99% | **69.1** |

These are the same unit. The skirmishers cost 19% more, shoot less far, and
deal less damage — **strictly worse**, no compensating trait. And both are far
and away the best units Skulloath has: they out-value the entire melee roster
while taking ~zero casualties.

### Full Skulloath roster (measured)

| Unit | Role | Cost | Damage | HP left | Value |
|---|---|---|---|---|---|
| Steppe Archers | ranged | 81 | 6946 | 100% | **90.4** |
| Steppe Skirmishers | ranged | 96 | 6203 | 99% | 69.1 |
| Warband Raider | infantry | 71 | 3822 | 0% | 53.8 |
| Pale Touched | infantry | 147 | 7203 | 47% | 51.4 |
| Runebound Wyvern | monster | 173 | 7201 | 64% | 45.3 |
| Dread Riders | cavalry | 173 | 7219 | 70% | 44.3 |
| Skulloath Raider | cavalry | 102 | 3320 | 0% | 32.5 |
| Steppe Rider | cavalry | 71 | 2211 | 0% | 31.1 |
| Skull Reavers | infantry | 268 | 6764 | 0% | 25.2 |
| Bonecaller | mage | 110 | 2669 | 0% | 24.3 |
| Boneguard | infantry | 323 | 7206 | 55% | 24.1 |
| Steppe Mammoth | monster | 605 | 7200 | 81% | 13.6 |
| Grave Shaman | mage | 120 | 559 | 0% | **4.7** |
| Ancestor Spirit | infantry | 120 | 302 | 0% | **2.5** |

Note the ordering: your *cheapest tier-1 archers are the best unit in the
faction*, and your 605-gold prestige mammoth is 6× worse per gold than them.
Ancestor Spirit and Grave Shaman are functionally unbuildable.

---

## Roles, measured across all 275 units

| Role | n | avg value | avg damage | survived |
|---|---|---|---|---|
| **ranged** | 44 | **75.7** | 5805 | 33/44 |
| infantry | 102 | 41.1 | 5125 | 53/102 |
| mage | 32 | 35.2 | 4597 | 19/32 |
| cavalry | 28 | 32.1 | 5295 | 19/28 |
| **monster** | 48 | **19.1** | 5040 | 30/48 |

- **Ranged**: ~2× the value of anything else and the best survivability. Broken.
- **Monsters**: the *worst* value despite being the most expensive units in the
  game. Every faction's prestige monster (colossi, mammoths, wyrms, behemoths)
  is a trap purchase.
- **Cavalry**: deals reasonable damage but dies at the same rate as infantry —
  its speed/charge premium is not being paid back.
- **Mage/support**: fine on average, but the *support* subset (healers,
  priests, oracles, drummers) sits at value 2–5, i.e. 10× below their faction
  median.

## Per-faction value spread (max ÷ min)

| Faction | Spread | Worst pick | Best pick |
|---|---|---|---|
| Empire | 58× | Imperial Chariot (0.9) | Imperial Crossbow (52.3) |
| Moonspear | 57× | Celestial Oracle (2.7) | Lunar Archer (152.9) |
| Sunblessed | 54× | Sun Oracle (2.0) | Sun Archer (107.4) |
| Cinderguard | 47× | Forge Priest (2.5) | Ember Crossbow (116.2) |
| Ivoryscar | 40× | Bone Priest (2.4) | Relic Skirmisher (96.4) |
| Shardhorde | 40× | Crystal Menders (1.7) | Crystal Archer (68.5) |
| Forsaken | 39× | Void Prophet (3.3) | Death Mage (128.2) |
| Thunderswarm | 39× | Storm Drummer (3.0) | Highland Skirmisher (115.7) |
| Skulloath | 36× | Ancestor Spirit (2.5) | Steppe Archers (90.4) |
| Gladehost | 33× | Wildwood Shaman (3.2) | Grove Warden (104.0) |
| Tainted Jade | 14× | Plague Shaman (5.6) | Jungle Stalker (80.2) |

A healthy roster sits within roughly 2–3×. Every faction is 10–20× beyond that.

## Dead content

- **64 strictly dominated units** (a cheaper stablemate matches or beats them on
  damage, toughness *and* speed). Worst offenders: Sunblessed (8), Thunderswarm
  (7), Shardhorde (7), Moonspear (6), Skulloath (5).
- **8 near-duplicate pairs** — same role, near-identical cost and stats:
  Steppe Archers/Skirmishers, Empire Legionary/Levy Conscripts,
  Centurion Guard/Praetorian Champion, Bone Archer/Relic Skirmisher,
  Jade Cavalry/Venom Assassin, Forge Colossus/Magma Crawler,
  Elder Ceratops/Shard Crawler, Shard Colossus/Shardback Behemoth.
- **~30 support units** (priests, oracles, healers, drummers) at value 2–5 that
  no rational player or AI will ever recruit.

---

## Recommendations, in priority order

### 1. Fix the unit card (do this first — it's a lie, not a balance issue)
`estimate_unit_dps` in `campaign_hud.gd:975` should be replaced with the
simulator's own model, or (better) with a measured power table generated by the
same harness used for this audit. Right now the numbers players compare units
with are wrong by up to 30× (single monsters) and mis-rank cavalry vs infantry.
Star ratings are computed from the same bad estimate and inherit the error.

### 2. Nerf ranged sustain (the actual balance bug)
Archers currently annihilate a melee squad **without taking losses**. Options,
cheapest first:
- Cut ammo from 7 volleys to 4–5, so they must be screened and can't solo a
  battle. (`battle_simulator_v3.gd`, volley/ammo constants.)
- Increase melee vulnerability: ranged units already fight at ×0.4 in melee;
  also drop their `melee_defense` by ~30% across the board so a line unit that
  *does* reach them wins decisively.
- Make advance speed vs volley rate the tuning knob: if infantry crosses the
  field in ~4 volleys instead of 7, everything falls into place.

### 3. Re-price every unit from measured power
Set `recruit_cost ≈ power ÷ target_value`, with per-role targets that price in
what the sim doesn't measure in a 1v1 (charge/flank, tile control, auras):

| Role | target value | rationale |
|---|---|---|
| ranged | 28 | safest role — should cost a premium |
| infantry | 38 | baseline |
| cavalry | 35 | pays for flanking/charge utility |
| monster | 32 | pays for tile control + anti-swarm |
| mage/support | 30 | pays for spells/auras |

**198 of 254 recruitable units would move more than 30% in price.** This is a
big data change, but it's mechanical, scriptable, and it's the only way to kill
all 64 dominated units at once.

### 4. Give the redundant pairs distinct jobs
The engine already supports the distinction — the data just doesn't use it:
- **Archers**: long range (3), slow, *fragile in melee* (low melee_defense).
- **Skirmishers**: range 2, `fast` tag, +vs `light`, better projectile_defense,
  cheap — a harasser that screens the archers rather than a worse copy of them.
- Apply the same split to the other 7 duplicate pairs (see list above).

### 5. Make monsters worth their price
They deal fine damage (5040 avg) but cost 300–800. Either cut their cost ~40%,
or lean into what the engine gives them: single large entities cleave
(`contact_cap = radius/2.5`, ~9.6 contacts) and get ×1.3 vs swarms. Raising
their `attack` and giving them fear auras would make them the anti-swarm answer
that the ranged meta currently lacks.

### 6. Rescue the support units
Healers/priests/oracles at value 2–5 need either a 50–60% price cut *or*
meaningfully stronger auras (`healing_aura`, `armor_aura`, `morale_aura` are
all implemented and read by the sim). As they stand they are strictly worse
than buying one more line unit.

---

## Appendix — reproducing this

`tests/tmp_unit_audit.gd` prints a CSV of every unit's measured damage, damage
taken, surviving HP and cost. Re-run it after any balance change:

```
godot --headless --path . -s res://tests/tmp_unit_audit.gd
```
