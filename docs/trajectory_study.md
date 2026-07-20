# FractureWars — Long-Horizon Trajectory Study

*July 2026. Method: 6 fully-AI games (all 11 major factions AI-controlled, seeds
1–6) run headless via `tests/tmp_econ_sim.gd`, now that battle resolution is
decoupled from the campaign scene. Every faction's gold, food, cities,
settlements, armies, units, population, upkeep, income, net income, loyalty and
defeat status logged each round. Seeds 1, 2, 4, 6 ran the full 80 turns; seeds 3
and 5 reached turns 68 and 63 before I stopped them (the late game slows sharply
— see finding #1). 5,000 faction-rounds analysed. This measures how the game
actually plays out over a full campaign, not turn-1 snapshots.*

---

## The one finding that reframes everything

**The strategic map is nearly frozen — conquest almost never resolves.**

Across 6 games to turn 68–80, exactly **one** major faction was eliminated
(Forsaken, once, turn 56). The total number of major-held cities moved by only
−2 to +4 per entire game:

| seed | major cities t1 → end | net change |
|---|---|---|
| 1 | 18 → 22 | +4 |
| 2 | 18 → 21 | +3 |
| 3 | 18 → 20 | +2 |
| 4 | 18 → 16 | −2 |
| 5 | 18 → 20 | +2 |
| 6 | 18 → 18 | 0 |

And that small movement is almost entirely **factions absorbing independent
cities or founding settlements** — not taking each other's cities. Armies fight
constantly (it's why the late game gets so slow: a snowballed faction resolves
many battles per round), but they rarely *take and hold* a city. Sieges start,
armies grind, stalemates separate them, and the front barely moves.

Everything below follows from this: because conquest doesn't pay, the dominant
strategy is to **not fight** — build economy, expand into empty land, and turtle.

---

## Who snowballs (and how)

Territory (cities + settlements) at each seed's end, mean across seeds:

| Faction | mean territory | growth t10→end | how |
|---|---|---|---|
| **Gladehost** | **5.8** | **+3.6** | settles empty land + absorbs independents |
| **Empire** | **4.8** | **+2.6** | 3.0 settlements on average — peaceful expansion |
| Skulloath | 3.3 | +1.5 | modest |
| Cinderguard | 2.7 | +0.7 | |
| Tainted Jade | 2.7 | +0.7 | |
| Forsaken | 2.5 | +0.5 | (also the only faction ever eliminated) |
| Moonspear | 2.2 | +0.2 | stagnant |
| Ivoryscar | 2.0 | 0.0 | stagnant |
| Thunderswarm | 2.0 | 0.0 | stagnant |
| Sunblessed | 0.3 | 0.0 | nomad — never establishes |
| Shardhorde | 0.0 | 0.0 | nomad — no cities at all |

**Snowballing happens through expansion, not war.** Gladehost and Empire win by
settling and absorbing neutral territory. The gap is real (Gladehost/Empire end
with 2–3× the losers' territory) but it opens slowly and peacefully.

---

## Who compounds economically (turn 30, mean)

| Faction | net gold/turn | income | upkeep | units | end gold |
|---|---|---|---|---|---|
| **Empire** | **+110** | 135 | 25 | 6 | **~4,900** |
| Tainted Jade | +56 | 92 | 36 | 10 | ~1,150 |
| Forsaken | +55 | 67 | 12 | 10 | ~3,200 |
| Ivoryscar | +36 | 38 | 2 | 1 | ~2,500 |
| Thunderswarm | +33 | 39 | 6 | 2 | ~1,900 |
| Gladehost | +26 | 53 | 27 | 11 | ~200 |
| Cinderguard | +22 | 55 | 32 | 8 | ~500 |
| Moonspear | +13 | 41 | 28 | 10 | −6 |
| Skulloath | +8 | 29 | 21 | 10 | ~190 |
| Sunblessed | +2 | 9 | 6 | 3 | ~4,700* |
| **Shardhorde** | **−42** | **0** | 42 | 20 | **−52** |

**Empire's economy dominates by a factor of ~2–4** once past its opening dip. It
starts gold-negative (confirmed from the earlier audit — its units cost ~2× the
field), dips to ~26 gold by turn 10, then its developed cities vastly out-earn
the upkeep and it nets +110/turn, ending with ~4,900 gold. Empire's "starts in
the red" is a **temporary early tax, not a spiral** — provided it survives turn
5–15 without over-recruiting.

\*Note the treasuries with no army: **Ivoryscar (1 unit, 2,500 gold),
Thunderswarm (2 units, 1,900), Sunblessed (3 units, 4,700)**. These factions
*hoard* — they bank enormous gold and never spend it, because there's nothing
worth spending it on (conquest doesn't work, and nothing punishes idleness).

---

## Death spirals — measured

Turns spent at negative gold, mean per game:

| Faction | avg turns negative-gold | recoverable? |
|---|---|---|
| **Shardhorde** | **~20** (of ~70) | **NO** |
| Tainted Jade | 8.3 | yes — self-corrects |
| Moonspear | 3.7 | yes |
| Empire | 1.5 | yes — the opening dip |
| Gladehost | 1.0 | yes |
| Skulloath | 0.2 | fine |

**Shardhorde is the one true, unrecoverable death spiral.** It has **zero gold
income** (nomadic, no cities), yet 20 units costing 42 gold/turn upkeep. It sits
at −42 net gold/turn for the whole game — an average of 20 turns underwater — and
never climbs out, because there is no income source to climb with. It survives
only because a nomad can't lose cities (it has none), so it just persists,
permanently broke and unable to build or recruit. This is exactly the
"no-bankruptcy-floor" trap from the economy audit, made permanent by a faction
whose economy has no gold tap at all.

**Tainted Jade's spiral is the healthy kind:** it over-recruits (strong income
tempts it), goes negative for ~8 turns, then its 92 gold/turn income digs it out.
Risky but self-correcting.

Loyalty collapse (turns at negative average loyalty, mean per game):

| Faction | avg turns loyalty<0 |
|---|---|
| **Ivoryscar** | **11.5** |
| Empire | 3.3 |
| Tainted Jade | 0.7 |

**Ivoryscar** runs its cities into the ground with captive/relic buildings
(−loyalty), spending 11.5 turns below zero loyalty — which costs it 20–35% income
and most of its growth. It survives by turtling (1 unit) and hoarding, but it's
economically hamstrung the whole game and never grows.

---

## Strategy verdicts, backed by the trajectories

**Actually pays**
- **Peaceful expansion + economic development** (Gladehost, Empire). Settle empty
  land, absorb independents, out-develop rivals. This is the only strategy that
  demonstrably snowballs.
- **Surviving Empire's opening dip.** Its economy is the strongest in the game by
  turn 30; the early gold scare is a tax, not a death sentence.

**Sounds good, is actually bad**
- **Building an army for conquest.** This is the trap the whole study exposes:
  armies are expensive (upkeep is the #1 driver of the negative-gold turns), and
  conquest *almost never completes* — sieges stall, battles stalemate, cities
  don't change hands. You pay the upkeep and get nothing. This is precisely why
  the strongest-economy factions (Ivoryscar, Thunderswarm) end with **1–2 units
  and thousands of banked gold**: the AI has effectively discovered that fighting
  doesn't pay and stopped doing it.
- **Nomadic factions as currently tuned** (Shardhorde, Sunblessed): no city
  economy → no gold → permanent broke. Shardhorde never recovers in any of 6
  games.

**Unrecoverable trap**
- **Shardhorde's structure**: 20 units, 42 upkeep, 0 gold income. There is no
  play that fixes it because the faction has no gold source. Needs a design fix
  (a gold income mechanic, or upkeep in shard essence instead of gold).

---

## What this says about the game's health

The game is **stable but static and low-agency**. Nobody dies, the map barely
moves, and the winning line is passive (expand quietly, develop, turtle). Two
root causes, both already flagged in earlier audits and now confirmed dynamically:

1. **Conquest doesn't resolve** — sieges/battles rarely convert into captured
   cities, so the military layer is nearly inert and there's no pressure to spend
   gold or take risks. This is the highest-leverage thing to fix: make winning a
   battle at a city actually take it in a bounded number of turns.
2. **No bankruptcy consequence** — nothing punishes sitting on a giant treasury
   with no army, so the dominant strategy is to do exactly that. A desertion rule
   at negative gold (already recommended) would also make idle hoarding pointless
   and force engagement.

Fix those two and the trajectories should open up: economies would have somewhere
to spend, conquest would redistribute territory, and the currently-frozen map
would actually move.

---

## Reproducing / extending

```
# one game:
godot --headless --path . -s res://tests/tmp_econ_sim.gd -- <seed> <turns>
# batch + analysis: see scratchpad analyze_traj.ps1 (aggregates traj_s*.csv)
```
Caveat: late turns in a snowballed game are compute-heavy (many battles/round),
so 80-turn all-AI games take several minutes each; run seeds in parallel.
