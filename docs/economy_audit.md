# FractureWars — Economy & Strategy Audit

*July 2026. Method: (a) full AI-vs-AI games run headlessly with every faction
under AI control, logging each faction's gold/food/pop/loyalty/army/income every
round (`tests/tmp_econ_sim.gd`); (b) static extraction of all 260 buildings'
cost/income/upkeep/loyalty; (c) reading the actual feedback loops out of
`city_system.gd` / `loyalty_system.gd` / `turn_manager.gd`.*

---

## The feedback loops that actually exist

These are the levers everything else hangs off (verbatim from code):

| Loop | Effect |
|---|---|
| **Loyalty → income** | ≥50: ×1.0 · 25–49: ×0.9 · 0–24: **×0.8** · −25..−1: ×0.65 · −50..−26: ×0.4 · <−50: **×0.2** |
| **Loyalty → pop growth** | ≥50: ×1.0 · 25: ×0.85 · 0: ×0.6 · −25: ×0.3 · −50: ×0.1 · <−50: **×0.0** |
| **Loyalty → revolt** | below −25, revolt chance = (−loyalty−25)/150 per turn (≈50%/turn at −100) |
| **Population → food** | income scales with `min(pop/100, city_level)`; consumption = `pop/60` |
| **Food < 0** | starvation: every city loses `|food|/(cities×5)` pop, floored at 30 |
| **Gold < 0** | **nothing happens.** No bankruptcy, no auto-disband, no interest. |

That last row is the single most important line in this document.

---

## 1. The death spiral: gold bankruptcy (no floor, no exit)

`_deduct_upkeep()` (`city_system.gd:791`) subtracts army + building upkeep with
**no floor**. Gold simply goes negative and stays there. There is no bankruptcy
rule, no forced disband, no morale/loyalty penalty — nothing tells the player
anything is wrong.

What that means in play:

- Every build and recruit action is gated by an affordability check, so at
  negative gold **you can do nothing at all** — you're not punished, you're
  *paralysed*.
- The only way out is to wait: at −400 gold with +20/turn net income you spend
  **20 turns doing nothing** while the AI develops. Disbanding the army that
  caused it is the correct play, but nothing in the UI suggests it.
- Because there's no feedback, players walk into this by doing the most natural
  thing in a strategy game: recruiting a big army.

**The trap is very easy to hit.** Measured upkeep vs. measured income:

| | gold/turn |
|---|---|
| Two starting cities produce | **19–33** |
| Empire unit upkeep (average) | **10.7 each** |
| Cinderguard unit upkeep | 8.1 each |
| All other factions | 4–6 each |
| Commander upkeep | ×(1 + 0.5·(level−1)) on top |

**Empire starts the game at −3 gold/turn** with only its five starting units —
measured on turn 1 of the simulation. Every other faction starts between +8 and
+16. A 10-unit Empire army costs **107 gold/turn**, i.e. *three to five cities'
entire gold output*. Empire's units cost roughly **double** everyone else's
upkeep and this is almost certainly unintentional.

**Recommendations**
1. Add a bankruptcy rule: at negative gold, units desert (highest-upkeep first)
   until income balances, with a clear warning at ≤0. This converts a silent
   softlock into a legible consequence.
2. Show net income prominently and colour it red when negative (the top bar
   already has the data).
3. Halve Empire's unit gold upkeep, or double its early city gold income.

---

## 2. The second spiral: loyalty

Loyalty is a genuine reinforcing loop, and unlike gold it *is* well designed —
but it's steep and it's invisible until it bites:

- A city at loyalty 0–24 already loses **20% of all income** and **40% of pop
  growth**.
- Below −25 it starts rolling for revolt every turn.
- Below −50 it produces **20% income and zero growth** — mathematically it can
  never recover on its own.

The buildings that push you there are the *good economic ones*:

| Building | Loyalty | Net income |
|---|---|---|
| demon_gate | **−8** | −8 |
| crimson_altar | −7 | +40 |
| captive_processing_camp | −6 | +32 |
| pale_waif_altar | −6 | −5 |
| blood_altar | −5 | +25 |
| thrall_quarters | −5 | +12 |
| iron_pit | −3 | +35 |

Stacking two or three of these in one city (exactly what the AI's build priority
lists do for Skulloath / Tainted Jade) drops a fresh city below zero loyalty,
which costs 20–35% income *and* 40–70% growth *and* opens revolt rolls. The
income you bought is smaller than the income you lost.

**Recommendation:** these buildings are fine as a *choice*, but the city panel
must show the loyalty consequence and the resulting income multiplier before you
build. Right now the loyalty malus is buried in the effects line and the income
multiplier is invisible.

---

## 3. Buildings: which are good, which are traps

Measured across all 260 buildings (`build_cost` vs `income − upkeep`):

- **Median payback: 5.2 turns.** The economic core of the game is healthy.
- **104 of 260 buildings never pay back** (net income ≤ 0). Most are legitimately
  military/defensive/cultural (they buy units, walls or loyalty), but…
- **13 buildings are pure drains**: negative net income, no unit unlock, no
  defence. These are strictly bad:

  `demon_gate` (−8/turn, −8 loyalty!), `sanctified_temple_knowledge` (−8/turn),
  `pilgrims_haven`, `sanctified_temple_harvest`, `survivors_stronghold`,
  `temple_of_the_pantheon`, `wayfarers_lodge`, `lightning_shrine`,
  `pilgrims_rest`, `relic_shrine`, `survivors_gathering`,
  `village_gathering_place`, `wanderers_rest`.

  Most of these *do* give loyalty (+4 to +12), which is worth real money via the
  income multiplier — but `demon_gate` gives **−8 loyalty AND −8 gold/turn** for
  84 gold. It is strictly harmful in every dimension, and it's one of
  Skulloath's two doctrine capstones.

- **24 buildings have >20-turn paybacks.** Given a campaign is ~60–100 turns,
  these are only correct if bought before turn ~40.

**Recommendation:** fix `demon_gate` (it should be a power spike, not a
self-inflicted wound). Audit the other 12 drains — if their loyalty is the
payoff, say so in the card ("+7 loyalty ≈ +9 gold/turn at this city's income").

---

## 4. Strategies: what pays, what's risky, what's a trap

**Pays reliably**
- **Tall, loyalty-first, small army.** Loyalty ≥50 is worth +25% income and +67%
  growth versus a neglected city. Growth gates city level-ups, which gate
  settlement founding (80 gold + 40 wood + 30 food). The compounding here beats
  everything else in the game.
- **Extractor-first build order.** Median payback 5.2 turns; the best extractors
  pay back in 3–4. Nothing else compounds that fast.
- **Archers.** (See `unit_audit.md`.) They're the best value in 10 of 11
  factions and take almost no losses — currently the strongest military play by
  a wide margin.

**Risky but correct**
- **Early conquest.** A captured city is worth 20–40 gold/turn *forever* plus
  loot. But the army that takes it costs 40–107 gold/turn *forever too*. Conquest
  only pays if the captured city out-earns the army — or **if you disband the
  army afterwards**, which the game never suggests and which no AI does.
- **Captive economies (Skulloath / Tainted Jade).** The conversion rates are
  good, but the buildings that enable them carry −5 to −6 loyalty each. Viable
  only if paired with cultural buildings to offset.

**Sounds good, is actually bad**
- **"Build a big standing army early."** The single most intuitive strategy in
  the genre is the one that bankrupts you here, silently and unrecoverably. A
  10-unit army costs 2–5× your entire early income.
- **Prestige monsters** (mammoths, colossi, wyrms). Highest gold cost, *worst*
  measured combat value per gold (see unit audit), plus the highest upkeep.
- **Empire's default opening.** It starts gold-negative before doing anything.
- **`demon_gate`** as a Skulloath doctrine: −8 gold/turn and −8 loyalty.
- **Rushing city upgrades for their own sake.** Upgrades raise the population
  threshold and the noble class %, which raises gold slightly but does nothing
  for the loyalty multiplier — the loyalty band is worth far more than a level.

---

## 5. Faction-by-faction opening economics (measured, turn 1)

| Faction | Net gold/turn | Note |
|---|---|---|
| Ivoryscar, Moonspear | **+16** | best openings |
| Tainted Jade | +15 | |
| Thunderswarm | +14 | |
| Forsaken | +11 | |
| Cinderguard | +9 | high unit upkeep (8.1) offsets this later |
| Skulloath, Gladehost | +8/+9 | |
| **Empire** | **−3** | starts in the red with its default army |
| **Shardhorde** | **−15** | nomadic: no cities, so zero gold income |
| **Sunblessed** | **−16** | nomadic start, same problem |

The two nomadic factions have **no gold income at all** on turn 1 and burn ~15
gold/turn on upkeep. They are entirely dependent on their unique mechanics
(shard essence, faith) to not spiral — and both of those mechanics were the ones
found broken in the earlier design audit. This is worth a dedicated look.

---

## 6. Priority fixes

1. **Bankruptcy rule + visible net income.** The gold-negative softlock is the
   worst thing in the economy: it's easy to hit, invisible, and unrecoverable.
2. **Empire upkeep.** Halve it (10.7 → ~5.5) or lift Empire's early gold income.
3. **Nomad openings** (Shardhorde, Sunblessed): give them a gold trickle or cut
   their starting army's upkeep; right now they open at −15/turn.
4. **`demon_gate`** and the 12 other pure drains: make the loyalty payoff
   explicit, and fix demon_gate outright.
5. **Surface the loyalty multiplier in the city panel.** Players cannot see the
   single biggest economic lever in the game.
6. **Teach the disband-after-conquest play** (or make garrisons cheaper than
   field armies, so holding land isn't punished like campaigning is).

---

## Long-horizon simulation — now unblocked

The original version of this audit could only measure turn-1 snapshots, because
headless AI-vs-AI games stalled the moment two armies met: **`battle_initiated`
had exactly one listener, `campaign.gd` (the scene)**, so with no scene present a
battle was never resolved, both armies survived on the same tile, and the AI
re-attacked it forever.

**That coupling has since been fixed.** Battle resolution now lives in a
`BattleResolver` autoload (`scripts/systems/battle/battle_resolver.gd`); the
campaign scene merely opts in to showing the player dialog/report while it is
on-screen. Headless AI-vs-AI games now run to completion — a 40-turn all-AI
game resolves cleanly with armies lost, cities changing hands, and factions
eliminated. This means the trajectory questions (who snowballs, who collapses,
when) *can* now be answered empirically; a follow-up pass with 60–100-turn runs
across seeds is the natural next step.

## Reproducing this

```
godot --headless --path . -s res://tests/tmp_econ_sim.gd -- <seed> <turns>
```
Prints a CSV of every faction's gold/food/iron/wood/tech, cities, settlements,
armies, units, population, upkeep, income, net income, average loyalty and
defeat status for every round of a fully AI-driven game. Usable up to first
army contact (see limitations above).
