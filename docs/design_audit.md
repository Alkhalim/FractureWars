# FractureWars — Design & UX Audit

*Audit date: July 2026. Method: five parallel deep-reads of the codebase and data
(faction mechanics, tech trees, unit rosters, buildings, UI surfaces), verified
with code evidence (file:line). This is a critical audit — it leads with problems;
the "what's genuinely good" sections are just as real.*

**Implementation status (July 2026):**
- **P0: DONE** — shard resonance revived (Shard Reserve dialog + AI), taint shard
  shattering wired, Tainted Jade/Moonspear AI branches, unit terrain/realm
  bonuses implemented in the simulator, 146 units tagged
  (heavy/light/stationary/demonic), supply_range stripped, inert Invest Shard
  hidden.
- **P1: DONE** — dilemmas for Skulloath/Gladehost/Forsaken/Sunblessed, 43 T3+
  buildings gated behind faction techs (unlock stars now live), research queue
  with auto-advance (shift-click), UX batch 1 (dialog chip backdrops,
  _format_cost eliminated, economy screen icon rows, dilemma cost-buttons).
- **P2: DONE** — weight-class counters (polearms +vs heavy, archers +vs light,
  raiders +vs stationary), terrain gates for Sunblessed/Forsaken/Shardhorde,
  doctrine forks for all 11 factions (exclusive_group, capital-only), price
  normalization (extractors ×1.6, prestige ×0.65), Shardhorde rescale + 8 new
  buildings, 59 upgrade tiers gained behavior effects, settlement-only
  building class (4 shared frontier buildings — first users of the shared
  path), research times compressed (full tree ~910 → ~560 serial turns), UX
  batch 2 (options skin, battle panels flush + button slots + chip results +
  icon spoils, trade picker icons + counter-offer cost rows, faction-select
  chip, ESC closes topmost overlay). Battle determinism baselines recaptured
  after the intentional balance changes.
- **Remaining (nice-to-have):** authored tech merging (times were compressed
  instead — safe for saves), signature units using the spawn/damage-aura
  systems, swarm cost-curve sanity pass, standing-tooltip chip styling,
  hotkey hints, load-menu anchoring.

---

## Executive verdict

**Do the factions actually play differently?** Partially — and the split is sharp.

- **6 of 11 factions play differently** (Cinderguard, Ivoryscar, Thunderswarm,
  Tainted Jade, Empire, Moonspear): recurring dilemmas, spendable resources, or
  timing decisions that change what you do on a turn.
- **4 factions are passive sliders** (Skulloath, Gladehost, Forsaken, Sunblessed):
  a number drifts on its own and applies modifiers. Interesting *concepts*, zero
  direct decisions.
- **1 faction's headline mechanic is dead code** (Shardhorde — see P0 bugs).

**Where the identity actually lives:** faction asymmetry is real, but it is carried
by (a) the per-turn faction mechanics, (b) ~350 lines of hardcoded per-faction
combat logic in `battle_simulator_v3.gd:405-757`, and (c) 100% bespoke building
menus. It is **not** carried by the tech trees (reskinned stat ladders) or by the
unit data (repeating role templates with stat biases).

**The single biggest design failure:** research. All 495 techs are pure numeric
modifiers — not one unlocks a unit, building, ability, or rule. Combined with
strictly serial research (~910 turns to finish one tree), players see <30 techs
per campaign and tiers 4–5 are effectively decorative.

**UX:** the four remediated HUD surfaces (city panel, unit/building cards, faction
detail) hold the standard, but the infrastructure built for them
(`_make_text_chip`, `make_cost_row`, `make_cost_button`, `make_panel_style`)
never reached the other ~20 surfaces. The economy screen, dilemma dialog, battle
results, options panel, and trade dialogs are the worst offenders.

---

## P0 — Broken / dead systems (fix before any redesign)

These are bugs, not design choices. Two factions' identities are partially or
fully non-functional:

1. **Shardhorde Shard Resonance is fully dead.** `consume_shard_for_resonance()`
   (`turn_manager.gd:3841`) is the only writer of `fs.shard_resonance` and is
   **never called anywhere** — no UI button, no AI path. All per-realm income
   (`turn_manager.gd:3793-3817`) and combat buffs
   (`battle_simulator_v3.gd:493-510`) never fire, for player or AI. The faction
   runs on a small essence trickle. *Fix: add a "Consume Shard" action on claimed
   shards (city/shard panel) + an AI heuristic.*
2. **Tainted Jade shard destruction is dead.** `destroy_shard_for_taint()`
   (`turn_manager.gd:3866`) is never called; the faction's biggest intended
   taint source (power_level × 12) doesn't exist in play.
3. **Tainted Jade AI never picks a Taint Focus.** The focus dilemma has no AI
   `else` branch (`turn_manager.gd:3591`), so every AI Tainted Jade is stuck at
   focus 0 forever and loses all three signature playstyles.
4. **Gladehost's "Seasonal Festival dilemma" doesn't exist.** The header comment
   (`turn_manager.gd:3605`) promises it; no dilemma is ever emitted.
5. **Dead unit data fields:** `terrain_bonuses` (set on **79 units**) and
   `realm_bonuses` (21 units) are never read by the battle simulator. Players
   reading unit cards are being lied to. Either implement or remove from data+UI.
6. **Dead combat tags:** `heavy`, `light`, `stationary`, `demonic` are checked in
   the simulator (`battle_simulator_v3.gd:659,704,2162,2426`) but appear on zero
   units. Four counter-conditionals never fire.
7. **Dead research effects:** `supply_range`/`supply_range_bonus` on ~31 techs
   exist only in the tooltip formatter (`campaign_hud.gd:5663,5699`) — no system
   reads them.
8. **"Invest Shard" UI trap:** the research footer buttons record a realm but
   grant nothing on ~479 of 495 techs (`shard_bonuses` populated on only 16,
   11 of them Shardhorde's) (`research_system.gd:60-76`).
9. **Dead unlock UI:** the tech tree's unlock-star glow and "Unlocks:" tooltip
   lines (`campaign_hud.gd:5599-5610,5950-5959`) can never fire because no tech
   unlocks anything.

---

## Part 1 — Faction mechanics

### Ranking (most → least engaging)

| # | Faction | Verdict | Player decision cadence |
|---|---------|---------|------------------------|
| 1 | **Cinderguard** | Deepest, genuinely play-different | 2 dilemma streams (Frontier Orders /4t, Dragon Raids /4-6t) + scrap economy + fortress building |
| 2 | **Ivoryscar** | Goal-oriented long game | Expedition gamble /5t + Black Pyramid build project with milestones |
| 3 | **Thunderswarm** | Clean spendable-resource loop | Spend Fury /3t (Storm March, Thunder Wall, Tempest Harvest) |
| 4 | **Tainted Jade** | Richest systemic web (player only; AI broken) | Focus rewire /4t; touches defense, captives, enemy shards, loyalty |
| 5 | **Empire** | Solid cadence, light feedback loop | Edict /5t (attack vs gold vs loyalty vs diplomacy, each nudges Authority) |
| 6 | **Moonspear** | Auto-cycle elevated by timing | Ritual on phase change (extend/accept/rush) — hold Full Moon for a siege |
| 7 | **Sunblessed** | Passive but positional | None direct; faith/wisdom respond to army placement, buffs allies |
| 8 | **Skulloath** | Great tension, zero agency | None — corruption drifts from buildings/captives only |
| 9 | **Gladehost** | Passive + missing promised dilemma | None; harmony punishes building (perverse incentive) |
| 10 | **Forsaken** | Autopilot espionage | None — thresholds auto-fire sabotage/steal; can't pick targets or lie low |
| 11 | **Shardhorde** | **Broken (dead code)** | Intended "when to consume a shard" — currently impossible |

### What separates the top from the bottom

Every engaging mechanic has at least two of: **recurring dilemmas**, **a spendable
resource**, and **combat-relevant percentages (12–30%)**. Every passive mechanic
has none of the three — they're flat per-turn dribbles (+3..+8 gold/tech) plus a
threshold modifier. The dribbles read as *modifiers*, not *engines*.

### Suggested changes

- **Skulloath:** add a "Dark Bargain" dilemma every 4 turns — spend captives to
  push corruption up, or purge (lose iron income) to push it down. Turns the
  existing well-tuned slider into a steered one. The dual-path T3 building fork
  already exists (`city_system.gd:1223-1229`) — the dilemma should reference it.
- **Gladehost:** implement the promised Seasonal Festival dilemma at each season
  change (spend food/wood for a harmony surge, a season extension, or a
  one-season economic boost). Also fix the perverse incentive: over-building
  should be offsettable (e.g. groves/shrines counteract per-building harmony
  loss), so the answer is "build *in harmony*", not "don't build".
- **Forsaken:** convert auto-sabotage into an operations dilemma when network ≥
  threshold: pick target + operation (steal gold / steal tech / erode loyalty /
  lie low to clear detection risk). The effects all exist
  (`turn_manager.gd:4410-4436`); only the choice layer is missing.
- **Sunblessed:** surface the positioning mechanic (it's invisible!). A small HUD
  indicator "Faith +2/turn: 3 armies near foreign cities" would turn a hidden
  drift into a deliberate playstyle. Optionally a Golden Age dilemma at Faith 85+.
- **Moonspear AI:** give it the ritual `else` branch (extend Full Moon when at
  war and defending; rush when behind).
- **All factions:** the mechanic panels should show *what the current value does*
  ("Corruption 63: +18% attack, captives → iron, -1 loyalty/turn") — thresholds
  are currently only discoverable by reading effects tables.

---

## Part 2 — Tech trees

### Findings

- 495 techs = 11 near-disjoint ~43-tech faction trees + 15 common. A player sees
  ~58 per campaign and **completes ~15–30** (serial research, avg 16 turns/tech,
  ~910 serial turns per tree). Tiers 4–5 (147 techs) are effectively unreachable.
- **Zero gameplay unlocks anywhere**: `unlocks_units` empty in all 495 files;
  `requires_research` set on 0 of 248 buildings. Research only scales numbers.
- Effect distribution is dominated by generic stats: `unit_attack_bonus` ×182,
  `unit_defense_bonus` ×101, `income_gold_pct` ×64 … `unit_attack_bonus` is the
  #1/#2 effect in *every* faction. Roughly 40–45 of each faction's ~58 accessible
  techs are decision-free stat ticks; ~13 hook real faction mechanics
  (corruption/lunar/harmony/vigilance/faith/fury scaling — those are wired and
  good).
- Structure: every faction has the identical skeleton (6 branches, one 3-tech
  throne capstone). Max 2 prereqs, no mutually exclusive choices, chains within
  a branch are near-linear.
- Sockets: 282 tier-3+ techs have realm sockets with small bonuses (+4/+5 range);
  crystals are scarce and contested → realm-matching busywork, not strategy.
- UI: good pan/zoom/tooltips/path-glow, but no search, no queue, no auto-advance
  (player must re-open and re-pick after every completion), labels vanish below
  0.55 zoom (anonymous dots at overview).

### Suggested changes (ordered by impact)

1. **Make research unlock things.** The wiring already exists on both ends
   (`research_data.gd:17` `unlocks_units`, `building_data.gd:23`
   `requires_research`). Move each faction's tier-3+ military buildings and
   elite units behind ~8–10 techs per faction. This single data change makes the
   tree a progression system instead of a modifier shop, and it makes the dead
   unlock-star UI light up for free.
2. **Fix pacing.** Either add a research queue with auto-advance (minimum), or
   cut each faction tree to ~25–30 meaningful techs, or halve research_time at
   tiers 1–3. Target: a full campaign should complete ~60–80% of a tree, so
   tier 4–5 capstones are reachable ambitions rather than fiction.
3. **Merge stat-tick chains.** Collapse "+5% attack → +5% attack II → +5% attack
   III" ladders into single bigger techs; spend the freed nodes on faction
   mechanics (the ~13 good techs per faction show the pattern).
4. **Add 2–3 mutually exclusive forks per faction** (the Skulloath corruption
   building fork proves the concept works). E.g. Moonspear: "Perpetual Waxing"
   vs "Deep Full Moon" — pick a lunar doctrine.
5. **Sockets:** either make socket bonuses scale into build-arounds (double the
   tier-5 rule is a start) or reduce socket count to ~5 big sockets per faction
   so each crystal placement is a real decision.
6. **Remove or implement** `supply_range`; remove the invest-shard buttons for
   techs without `shard_bonuses`.
7. **Tree UI:** add a search box and a "recommended next" pin; keep branch
   labels visible at overview zoom.

---

## Part 3 — Units

### Findings

- Actual count: **275 units** (majors 15–17 each; ~23 minor factions with 4 each).
- The stat framework is strong: 3-way armor split (melee/projectile/magic — all
  genuinely used by the simulator), morale, auras, 10 implemented spell types,
  vs-tag counters, charge/flank/rear/pursuit mechanics.
- **Faction stat identities are real**: Skulloath atk/def ratio 2.40 (glass
  cannon) vs Cinderguard 1.54 (anvil); Sunblessed has 9 ranged units, Tainted
  Jade zero cavalry. It is *not* "same army, different sprites" numerically.
- But **role templates repeat** (every major: infantry+ranged+mage+monster+beast)
  and **145 of 275 units are plain statlines** (no special mechanic at all).
  Most tactical identity is injected by hardcoded faction code
  (`battle_simulator_v3.gd:405-757`), not by unit data.
- The counter *engine* is richer than the counter *content*: only 45 units carry
  `vs_attack_bonuses`, 5 carry `vs_defense_bonuses`, and the heavy/light
  weight-class system exists only in code.
- **Balance flags:** Shardhorde means are ~40–60% above every other faction on
  attack AND defense (power creep, not identity). Cheap high-HP swarms top the
  cost-efficiency chart (0.18→8.75 power-per-gold spread, 48×).
- 110 of 275 units (all minor factions) are not unlocked by any building — flat
  rosters with no progression (mostly by design for minors, but worth knowing).

### Suggested changes

1. Implement or strip `terrain_bonuses`/`realm_bonuses` (P0 above). If
   implemented, they become the cheapest way to differentiate the 145 plain
   statlines — a forest-bonus unit plays differently from an open-field one.
2. **Adopt the weight-class system**: tag ~30% of units `heavy`/`light` per the
   existing dead code paths, then give spears +vs heavy, skirmishers +vs light.
   Composition instantly matters more, using code that already exists.
3. **Rein in Shardhorde numerically** and re-express its identity as "fewer,
   bigger, resonance-buffed" once the resonance mechanic actually works (P0 #1).
4. Give each faction 2–3 signature units a unique mechanic instead of a statline
   (the spell system shows the payoff — mages are the most differentiated units
   in the game). Candidates: the spawn system (`spawn_unit_data_id` — fully
   implemented, used by zero units) and damage auras (same).
5. Sanity-pass the swarm cost curve (thrall_swarm 8.75 power/gold vs median 2.92).

---

## Part 4 — Buildings

### Findings

- 248 buildings, **100% faction-specific** (the shared-building code path is
  dead), zero name-stem overlap across factions — real bespoke menus, not
  reskins. All 24 `special_effects` keys are implemented end-to-end (verified);
  each faction's buildings feed its unique mechanic.
- **Decision quality is the system's strength**: hard slot caps (capital 2+level
  → ~7; settlement = level), physical hex-tile adjacency, terrain gates, and
  loyalty tradeoffs mean you genuinely cannot build everything. Skulloath's
  corruption-forked T3 (sanctum XOR demon gate) is the best single decision in
  the content.
- Weaknesses: **41% of upgrade tiers are pure number bumps** (chains are
  uniformly 2-tier shallow); terrain gates touch only 7% of buildings and
  **Sunblessed/Forsaken/Shardhorde have zero** terrain interaction; early
  extractors pay back in <2 turns (auto-includes) while several effect buildings
  have 50–125-turn income paybacks (un-normalized pricing); settlements are just
  smaller cities for 10/11 factions (only Empire has capital-exclusive
  buildings); content depth is uneven (Shardhorde 12 vs Empire 35).

### Suggested changes

1. **Give every faction a Skulloath-style exclusive fork** at T3 — one either/or
   building pair keyed to its mechanic (Gladehost: deep grove XOR industry;
   Thunderswarm: storm temple XOR forge; etc.). This is cheap content with high
   decision value.
2. **Make upgrades change behavior**: each upgrade tier should add or amplify a
   `special_effect`, not just income. Target: <15% pure-number upgrades.
3. **Spread terrain gates**: give Sunblessed (desert), Forsaken (swamp/tundra),
   and Shardhorde (shard wastes) 2–3 terrain-gated buildings each so the map
   shapes their expansion too.
4. **Differentiate settlements**: a settlement-only building class (watchposts,
   waystations, resource camps) and 1–2 more capital-only buildings per faction.
5. **Price normalization pass**: extractors to ~4–6 turn payback; give the
   125-turn prestige buildings either meaningful income or explicitly zero (pure
   effect buildings), not a token 5/turn.
6. **Fill out Shardhorde's menu** to ~20 buildings once resonance works.
7. Either use `requires_research` (see tech suggestions — preferred) or remove
   the field; same for the shared-building path (`faction_id == ""`).

---

## Part 5 — UX audit (menus, popups, dialogs)

### Systemic issues

1. **~15 dialogs put raw Labels straight on the leather panel** — every
   `_create_centered_dialog` caller skips `_make_text_chip` (dilemma, trade,
   counter-offer, AI offer, siege, event result, level-up, victory/defeat,
   faction-defeated, region overview, research detail…). One shared fix: make
   the dialog factory wrap its content VBox in a chip by default.
2. **Raw resource text instead of icon rows** everywhere outside the four fixed
   panels — the legacy `_format_cost()` helper (campaign_hud.gd:8533) still
   returns "200 Gold, 30 Iron" text and is even called inside otherwise-fixed
   cards (unit detail :850, detail-overview :8283, unit card :8475, commander
   :9109).
3. **Non-anchored magic-size layout** (`.size`/`.position` computed once) in
   pause menu, options, load menu, turn banner — breaks on window resize.
4. **ESC inconsistency**: ESC always opens the pause menu, even over open
   dialogs (stacks instead of dismissing). No per-dialog cancel. F5/F9 exist but
   are hinted nowhere.

### Top offenders (priority order)

| # | Surface | Problems | Evidence |
|---|---------|----------|----------|
| 1 | **Economy screen** | Entire readout is raw text on bare leather; zero icon rows; hand-rolled +/- coloring | campaign_hud.gd:2036-2173 (2068, 2129, 2165) |
| 2 | **Dilemma dialog** | Choice costs invisible (only "[Can't Afford]" suffix); consequences only in hover tooltips; text on leather; hardcoded height | :6927-6988 |
| 3 | **Battle results** | One giant multiline label on leather; raw spoils text; fixed 400×360 with no scroll (long rosters overflow) | battle_v3.gd:2231-2318 |
| 4 | **Options panel** | Off-skin purple StyleBoxFlat; vanilla HSlider/CheckButton; non-anchored; no ESC-close; shown from BOTH main menu and pause | audio_manager.gd:615-730 |
| 5 | **Trade + counter-offer** | Vanilla SpinBox/OptionButton; resource pickers and terms as plain text, no icons | campaign_hud.gd:4843-4941, 5079-5094 |
| 6 | **Centered-dialog family** | No chips anywhere (see systemic #1) | :10248 + ~15 callers |
| 7 | **Battle side panels** | 4px gaps instead of flush; clickable queue Labels that aren't buttons; hardcoded 388/376 offsets; retreat button replaces whole stylebox | battle_v3.gd:231-391 |
| 8 | **Research panel + detail dialog** | Tech amounts and research time as plain text; legend labels not chip-styled; detail dialog text on leather | :5307-5390, 6161-6219 |
| 9 | **Faction select info column** | Description/traits/unique text directly on leather (chip helper never ported to main_menu.gd) | main_menu.gd:566-592 |
| 10 | **Notifications / siege loot** | "+30 Gold" raw text toasts; siege results spell out four resources in a sentence | campaign.gd:4709-5017, campaign_hud.gd:10092-10104 |

### What already meets the standard (don't redo)

No vanilla Godot dialog classes anywhere; battle HUD uses the compact theme
correctly; diplomacy faction rows (chip + faction-color border + treaty icons);
diplomacy result dialog; city panel columns/chips; building & unit detail cards'
cost/time icon rows; recruit/upgrade/found cost-buttons; gold separators.

### Suggested UX fixes (cheapest first)

1. Wrap `_create_centered_dialog` content in a chip **inside the factory** — one
   edit fixes ~15 dialogs.
2. Kill `_format_cost`: redirect all remaining call sites to
   `make_cost_row`/`cost_bbcode`.
3. Rebuild economy screen rows on `make_cost_row` (it's a table of exactly the
   thing that helper renders).
4. Dilemma dialog: render each choice as `make_cost_button` (title + cost row +
   consequence line visible, not tooltip-hidden).
5. Options panel: `make_panel_style` + themed slider/toggle skins; anchor it.
6. Battle: zero the 4px edge offsets; convert queue labels to flat-styled
   Buttons; results into chip + scroll container with icon rows for spoils.
7. ESC: route to "close topmost dialog, else pause"; add hotkey hints (F5/F9,
   ESC) to the pause menu.
8. Anchor-center pause/options/load panels instead of one-shot `.size/.position`.

---

## Part 6 — Prioritized roadmap

**P0 — Fix broken promises (days):** resonance consume action + AI (unblocks a
faction), taint shard destruction, Tainted Jade AI focus pick, remove/implement
dead unit fields + dead tags + supply_range, hide invest-shard where inert,
Gladehost festival dilemma (or delete the comment).

**P1 — Highest design leverage (weeks):**
1. Research unlocks (units + buildings behind techs) + research queue/auto-advance.
2. Dilemmas for the four passive factions (Skulloath bargain, Gladehost festival,
   Forsaken operations, Sunblessed golden age) — the Cinderguard/Thunderswarm
   pattern is proven and the effect hooks all exist.
3. UX batch 1: dialog-factory chip, `_format_cost` removal, economy screen icon
   rows, dilemma cost-buttons.

**P2 — Content quality (ongoing):** upgrade tiers that change behavior, per-
faction exclusive building forks, weight-class tags + counters, terrain gates
for the three untouched factions, Shardhorde rebalance + menu fill, tech-tree
pruning/merging, settlement differentiation, price normalization, UX batch 2
(options, trade, battle panels, faction select).

---

## Bottom line

The skeleton is genuinely good: real slot scarcity in cities, a combat engine
with more counterplay than the content uses, fully-wired special effects, and
five or six faction mechanics that would be at home in a commercial 4X. The gap
is consistency: for every implemented system there's a parallel one that's data
without code (terrain bonuses on units) or code without data (research gates,
shared buildings, weight classes, unit spawning) — and the tech tree, the system
that should tie progression together, currently changes nothing but numbers.
Close the dead-code gaps first, then spend the design budget where the pattern
already works: dilemmas, exclusive forks, and unlocks.
