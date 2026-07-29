# Systems Maturity Audit

*2026-07-29. Full-codebase sweep (systems + faction mechanics + AI). Verdicts:
**WELL-DEVELOPED** (deep + interactive), **FLAVOR-ONLY** (works but thin),
**UNDERDEVELOPED** (missing depth or player agency).*

## Well-developed & interactive

| System | Where | Why it qualifies |
|---|---|---|
| City & buildings | `city_system.gd` (2.2k lines) | Tile placement, parallel recruit queues, city levels 1-5 gated by province pop, doctrine forks, demolish tradeoffs; deep income pipeline (pop x buildings x loyalty x research x senate x culture x debt) |
| Loyalty & rebellion | `loyalty_system.gd` | Per-class loyalty, ~30 modifiers; real consequences: income x0.2-1.0, growth mult, revolts spawn actual rebel armies that besiege and then act via AI |
| Recruitment & veterancy | `city_system.gd`, `unit_instance.gd` | Population-costed, building-gated, 3 veterancy tiers, bankruptcy desertion |
| Battle (manual V3 + auto V2) | `battle_simulator_v3.gd` (3.5k), `battle_resolver.gd` | Formations, morale/rout/rally, flanking/charge, fear, procedural terrain, per-faction combat hooks; fight/auto/retreat choice |
| Siege & conquest | `city_system.gd:594-880` | Pressure meter, composition-scaled fill, attrition, relief battles, occupation choices (capture/loot/raze) |
| Diplomacy | `diplomacy_system.gd` (1.8k) | Standing w/ reasons, 6 treaty types, gifts w/ faction preferences, threats, counter-offers w/ greed + needed-resource logic, war exhaustion |
| Research | `research_system.gd` | Prereq tree, queue, pause/resume, shard investment, removable crystal sockets, faction-weighted AI |
| Shards & essence | `shardfall_system.gd`, guardians | Timed shardfalls, guardian armies, decay, many real essence sinks |
| Commanders | `commander_system.gd` | Levels/skills/traits/items/followers, contextual trait gain/loss, pity-timer drops, city influence radius |
| Movement/fog | `movement_system.gd` | A* + caching, terrain stride tags, trespass costs, vision ranges |
| Senate & policies | `policy_system.gd` | Seats by class, policy loyalty gates + auto-revoke, senate dilemmas, Forsaken infiltration crisis (Empire-centric though) |
| Events/dilemmas | `turn_manager.gd:1860+` | ~21 weighted generic events + per-faction dilemma families, all with branching outcomes |
| Economy & captives | distributed | Debt spiral w/ desertion, starvation, captive sinks + decay — no one-way resources |
| Settlements | `city_system.gd:1866+` | Founding rules, terrain income preview, Cinderguard fortress tiers, Sunblessed mobile camps |
| Save/load | autosave each round | Roundtrip-tested |
| Faction mechanics (11 majors) | `turn_manager.gd` `_process_*` | Every playable faction has a real accumulate-and-spend loop; richest: Cinderguard, Skulloath, Sunblessed, Ivoryscar, Gladehost, Empire |

## More flavor than content

| System | Issue |
|---|---|
| Audio/music | Works (18 SFX, faction playlists) but no gameplay role — fine as-is |
| Tutorial/onboarding | Contextual hint popups only; no guided flow for the 11 asymmetric factions — steep for new players |
| Turn log/summary | Functional feed; no filtering, no jump-to-location links (partially: goto exists), no per-category history |
| Moonspear lunar mechanic | Solid numbers but semi-passive — phases cycle on their own; only agency is extend/skip (candidate for an active spender) |
| Minor-faction identity | Combat tweaks + parent inheritance work, but minors have no mechanics of their own — acceptable by design |

## Underdeveloped / lacking depth

| System | Gap | Suggested direction |
|---|---|---|
| Victory conditions | Logic exists and is reachable, but SHARD_ASCENSION (hold 10 shards) fights the whole design — every mechanic *consumes* shards | Rework to cumulative-shards-spent or realm-attunement track |
| Independent cities | Garrisons grow and can defect at standing ≥40, but they have no wants: no quests, no trade, no personality | Small request/quest table + trade willingness would make the map feel inhabited |
| Espionage counterplay | Forsaken ops now have 5 tiers (10/15/20/25/30/35/40+) but victims have no counter-espionage lever | A cheap "counter-intelligence" building or policy |
| AI army operations | Postures added (2026-07-29) but still no multi-army coordination, no naval/transport concept, no defensive garrison sizing | Group-attack planner would be the next big AI win |
| Trade depth | Resource-for-resource only; no location-bound goods, no routes | See `docs/special_resources_design.md` |
| Dead legacy code | Battle V1 scene+sim and interactive V2 scene are unreachable; shard_guardians consume full AI turns | Delete V1/V2 scenes; skip NPC guardian faction in the AI loop |

## Known debt flagged during this audit

- `tests/baselines/` battle fingerprints were **already stale before 2026-07-29**
  (v2+v3 diverge on clean HEAD by a few HP/morale points) — some earlier
  battle-relevant commit shipped without regenerating; needs a deliberate
  re-baseline decision.
- `FactionData.shard_preferences` and `ai_personality.style` are declared but
  never read (dead data fields).
- Sunblessed wisdom research-speed bonus and Forsaken 35+/40+ espionage tiers
  were implemented 2026-07-29; header comments now match code.
