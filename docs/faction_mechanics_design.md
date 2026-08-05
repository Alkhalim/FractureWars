# Faction Mechanics Design Doc
Fantasy antiquity/medieval 4X (Total War style). Living document, accepted designs only.

> **Implementation decisions (designer, 2026-08-05):** implementation starts AFTER UI polish wave 2 completes. **Flagship set (full bespoke suites first): Skulloath, Thunderswarm, Ivoryscar, The Forsaken** — the rest initially receive lighter substrate-driven variants (answers Part 14's tiering question). **Migration: keep-until-replaced** — each faction's current live mechanic stays playable until its new suite ships; the game stays complete at every commit. Build order: substrate first (Land State → Sites & Ruins incl. Part-13 density pass → Calendar → Settlement Resolution verbs; Obligation Webs / Named Entities / Building Favor land with their first consumer), then flagships one at a time (Skulloath → Thunderswarm → Ivoryscar → Forsaken), each as its own spec → plan → reviewed execution.

**Status legend:** ACCEPTED = signed off. Sections are only added after sign-off.

**Scope cuts (current):**
- Named warlord loyalty/splinter systems (Skulloath) — deferred
- Black Pyramid seal counter / endgame crisis (Ivoryscar) — deferred

---

## Part 1: The Substrate — ACCEPTED

Design rule: faction mechanics are not bespoke systems bolted on top of the game. They are reads and writes on **seven shared world systems**. Factions are data (thresholds, verb tables, event chains); the substrate is engine code. Mechanics must reference neighbours, not only their owner.

### 1. Land State
Every province carries a persistent value vector:

- **Corruption** (demonic taint, decay, blight)
- **Sanctity** (consecration, lunar/solar blessing)
- **Harmony** (wildness and ecological vitality) — **the counterpoint to Development.** Development actively suppresses Harmony: farms, roads, quarries and cities push it down; wilderness, time, and deliberate rewilding raise it.
- **Development** (urbanisation, infrastructure)

**Harmony and Development are opposed but not strict inverses.** A blighted, razed, or corrupted province is low on *both* — neither wild nor built. This is what distinguishes a wasteland from a forest, and why Corruption is its own axis rather than merely "low Sanctity."

All "state of the land" mechanics are operations on this vector.

**Design rule: every faction must read or write at least one axis.** Land State is the shared connective tissue; a faction that ignores it is a faction that does not touch the world. Full coverage matrix in Part 14.

One map overlay per axis. This system is the highest-leverage build item: it makes factions feel each other passively without scripted interactions.

### 2. Landmarks and Sites
Typed persistent map entities. **Sites are non-settleable point features** — they are interacted with by armies and remain permanently available, so faction mechanics keyed to them never disappear from the map.

| Type | Settleable? | Notes |
|---|---|---|
| **Large Ruins** | **Yes** — rebuildable into cities | Former city sites. Accept **both** settlement and shrine verbs. Finite; once settled, they leave the ruin economy |
| **Small Ruins** | **Never** | Accept **shrine verbs only**. Cheap to claim (an army action, not a construction project). **Permanent interaction layer** |
| **Tombs** | No | Ivoryscar's parallel network (Part 3) |
| **Crystal veins, dragon lairs, nesting grounds, sacred sites** | No | Faction-specific resource and objective sites |

**Why the split matters:** if every ruin could become a city, a late-game map would be paved over and five factions' core mechanics would quietly stop existing. Small ruins guarantee a permanent, contestable, cheap-to-flip layer beneath the settlement game.

**Razing a city produces a Large Ruin.** The razer factions therefore feed the city-rebuilding economy; the small-ruin layer is permanent by construction and cannot be manufactured or destroyed.

**Shrines block settlement.** A Large Ruin carrying any shrine-type structure — grove, estate, moon temple, sanctified shrine, necropolis, Watchfort — **cannot be rebuilt into a city until that structure is destroyed.** This gives the site factions a strategic veto over settlement, not merely an economy of their own.

- Sites have **states**: dormant, claimed, consecrated, defiled, quarried, awakened.
- Each faction has a **verb table** per site type. **Every faction must have at least one ruin verb** (Part 14).
- Verb conflicts are rivalry drivers by construction (Tainted Jade *consecrate* where Sunblessed *sanctify*; mutually exclusive).
- **Sites are claimable and repurposable by any faction**, including sites already repurposed by someone else.

### 3. The Calendar
One global clock, visible to all players. Produces:

- **Moon phase**: fixed cycle (working value: 8 turns).
- **Seasons**.
- **Scheduled ritual dates** (faction-specific deadlines pinned to the global calendar).

Consumers: Moonspear power curve and crusade windows (full moon only), Tainted Jade quota deadlines, Shardhorde seasonal migration bonuses. Predictability is intentional: enemies plan around it (e.g. strike Moonspear at new moon).

### 4. Named Entities
Framework for persistent characters that are not lords: legions with traditions, crystal dinosaurs, aristocrats, tomb guardians.

- Persist between battles, accrue traits, have state, can be permanently lost.
- Factions differ in what their entities are and what entity states mean.
- **Scope note:** warlord loyalty/splintering is deferred. The framework should still be built entity-first (persistence + traits), with loyalty behaviors as a later layer.

### 5. Obligation Webs
Soft control distinct from ownership: a directed link between a faction and a settlement/faction, carrying obligations, benefits, and a breach condition.

Instances: Cinderguard oath-bonds, Empire claims and senate mandates, Forsaken puppet courts, Sunblessed enlightened free cities.

Overlapping webs generate emergent drama (e.g. a Cinderguard oath settlement inside an Empire claim zone is a war waiting to happen) without scripting.

### 6. Settlement Resolution
Shared post-capture verb set. Every faction conquers; **faction identity is defined by which verbs it may use afterward.** One system, per-faction access table.

| Verb | Effect | Access |
|---|---|---|
| **Occupy** | Take intact, low immediate yield | Default, nearly all factions |
| **Sack** | High immediate resources, damaged settlement, repeatable | Most factions |
| **Enslave** | Reduced resources, large **captive** yield, population loss | Ivoryscar, The Forsaken, Tainted Jade, Skulloath |
| **Raze** | Settlement destroyed → becomes **Ruins** | Shardhorde, Thunderswarm (to *empty* land); Tainted Jade (variant: **Raze & Consecrate**, auto-consecrates to a shrine); Skulloath at demonic endpoint |
| **Liberate** | Settlement becomes independent tributary bound to captor | Sunblessed, Cinderguard (strong); Ivoryscar (weak — value is dig rights, not tribute); others (weak) |

**Ruins (persistent world state):**
- Razed settlements leave a **Large Ruin** on the map permanently until restored or repurposed.
- Any faction may rebuild a Large Ruin into a city, but restoration starts at **level 1 at a large cost**, comparatively expensive versus founding a smaller settlement elsewhere.
- Consequence: razing regions makes them unattractive to *everyone* for a long time. Borders bend around scar tissue; the map accumulates history.
- **Land State interlock:** ruins set Development to zero and allow Harmony to recover over subsequent turns. Razing is therefore mechanically identical to rewilding — the same act reads as destruction or restoration depending on the actor (Thunderswarm nest viability, Gladehost balance, Shardhorde grazing).
- **Small Ruins are never created by razing and can never be settled** (Substrate §2). They are the permanent, non-pavable interaction layer.

**Sites are claimable and repurposable by any faction.** An army may seize a ruin — *including one already repurposed by another faction* — and convert it to its own use. A Tainted Jade shrine can be taken and planted as a Gladehost grove; a grove on a Large Ruin can be taken and rebuilt as an Empire city.

- Repurposed sites feel permanent but remain flippable, which keeps the map churning.
- **Effects already produced by a repurposed site persist after capture.** Terrain a grove has already spread stays — you cannot un-flood a marsh. Only ongoing production and projection stop.
- **Small Ruins flip cheaply and often** (army action, no construction). Large Ruins are slower and heavier because a city may be sitting on them.

**Every faction has at least one ruin verb.** Full table in Part 14.

**Ruins are the central point of contention on the map**, and the small-ruin layer guarantees that contention survives into the late game rather than being paved over.

**Liberate design warning:** in the genre, liberation is usually the trap option (weak, disloyal tributaries). Since it is the *identity* of two factions here, it must be tiered:
- **Cinderguard / Sunblessed:** liberated cities enter their Obligation Web as full entries — recruits and Oath integrity (Cinderguard), enlightenment influence and trade (Sunblessed). They can sustain a far larger effective empire this way than they could administer directly.
- **Everyone else:** standard mediocre tributary.
- For Cinderguard this **collapses liberation and oath-bonding into a single act**: take cities, hand them back, keep protecting them, never own anything.

**Characterization by restriction:** the Empire cannot raze at all — a civilizing empire that erases cities is a contradiction. Restrictions are characterization, not balance patches.

### 7. Building-Driven Favor
Shared pattern: **faction favor generated spatially by construction, not by an abstract slider.**

- The player's build order determines their factional politics or religious standing without a single explicit choice.
- Favor is faction-wide but produced by *what is built where* — visible on the map, expensive to reverse.
- Implementation is a per-building contribution table; cheap to build once and reuse.

**Current consumers:** Tainted Jade (temples → god favor), Empire (buildings → Senate bloc influence).

---

## Part 2: Skulloath — ACCEPTED (revised for scope)

**Fantasy:** demonically corrupted steppe horde torn between the Old Ways and new demonic strength. The faction's internal war made playable.

### Core value: Path
- Faction-wide value from **-100 (Old Ways)** to **+100 (Demon Ascendant)**. Starts at 0.
- **The middle is punished, not neutral.** From roughly -25 to +25: "A Horde Divided" — penalties to replenishment, control, and upkeep efficiency.
- Campaign opens inside the bad zone; the first ~10 turns are about choosing an identity under pressure.

### What moves the needle
- **Tech choices:** two visually distinct tree branches; picking any node shifts Path 3–5 points toward its side.
- **Event dilemmas:** larger swings, 8–15 points.
- **Rituals:** spend resources for deliberate shifts.
- **Behavioral drift:** recruiting daemonic units drifts positive; winning battles with 70%+ cavalry share drifts negative; sacking vs. tribute-taking each pull their own way. Drift means how you actually play keeps tugging at the value; it cannot be set and forgotten.

### Endpoint identities (both top-tier, neither "the good one")
**Old Ways (-100 side):**
- Elite steppe cavalry capstones, doubled horde movement.
- Tribute extortion: raid stance forces a "pay or burn" ultimatum without formal war (Empire border friction by design).
- Bloodline traditions on armies.

**Demon Ascendant (+100 side):**
- Daemonic monster roster, widespread fear/terror.
- Armies emit **Corruption** into Land State (automatic Gladehost conflict driver).
- Battle rites fueled by own-unit casualties.

### Cost of hard swings (replaces warlord splintering — scope revision)
Units of the alignment being abandoned suffer escalating upkeep and attrition as Path commits toward the opposite endpoint. Swinging hard is powerful but bleeds your existing army; transitioning identity mid-campaign is a real logistical project, not a free respec.

### Ruin verb: Defile
Skulloath may **defile** Small Ruins: cheap, fast, destructive. It denies the site to every other faction and pumps **Corruption** into the surrounding province. They build nothing and hold nothing — they spoil. Available on both Path endpoints; substantially stronger at the demonic end.

### Event chain spine
Recurring rival NPC: the **Khan of the old blood**, embodying whichever side the player abandons.
- Trigger thresholds at ±50: challenge duel (quest battle), then a schism/confrontation chain.
- At ±90: final confrontation. Victory unlocks the capstone title: *Great Khagan of the Endless Sky* (Old Ways) or vessel of the demon patron (Ascendant).
- Purpose: give the slider a face and a narrative payoff.

### Diplomacy consequences
- Old Ways Skulloath can reach non-aggression with Shardhorde and Sunblessed.
- Demon Ascendant cannot; Corruption emission also poisons relations with Gladehost passively.

### UI surface
- One prominent Path slider on the faction banner.
- Forecast tooltip: "current drift: +2/turn from daemonic upkeep."
- Readable in five seconds from the campaign HUD.

### Interlocks summary
| Touches | Via |
|---|---|
| Gladehost | Corruption emission into Land State |
| Empire | Tribute extortion, border friction |
| Shardhorde / Sunblessed | Alignment-gated diplomacy |
| Ivoryscar | (deferred with seal system) |

---

## Part 3: Ivoryscar — ACCEPTED

**Fantasy:** a buried kingdom dragged back into the light one chamber at a time, on the backs of the living. Not conquerors, not defenders — **diggers**. Angels, demons, constructs, sphinxes and undead bound under one covenant that predates the moral categories everyone else fights over.

### Core loop: The Work

The Black Pyramid (Akhet-Neru) has **five tiers**, gated by a tracked **sand level**. Excavation lowers it.
- Tier I sits above the sand line at start. Tier II is at the line and workable. Tiers III–V are buried: visible as named silhouettes only, contents unknown.
- Each tier unlocked reveals its chambers and their choices.
- Gives Ivoryscar a **victory-adjacent progress bar that is not territorial** — they can be losing the map and winning the campaign. Full Tier V excavation is a victory condition or the gate on one.

### Labor: the captive economy
Excavation consumes **materials** (gold, iron, natron, soulshards) and **labor** (captives).

- **Captives are consumed by the work.** Assigned to a chamber, a percentage is burned per turn of restoration. The work kills them. State this flatly in UI; do not soften it.
- **Sources:** battle prisoners (post-battle: execute / ransom / enslave), raiding, tribute clauses, and **purchase from factions that trade in people** (Forsaken, Skulloath) — their best trade partners are the worst factions on the map.
- **Central tension:** a faction sworn to protect the dead must consume the living to do it. Do not resolve this mechanically. Let it sit.
- **Throughput vs. attrition:** more captives per chamber = faster work, higher losses/turn. Recurring decision, not a set-once slider.
- **Hasten the Work:** spend soulshards to buy turns. Keep soulshards scarce enough that this is agonizing rather than default.

### Chambers as identity
Each chamber offers **two mutually exclusive consecrations** (e.g. Sanctum of Oaths: *Seal of Silence* [−40% grave-robber incursions, +gold] vs. *The Unbound Sanctum* [unlocks Rite of the Second Dawn, −25% ritual casting cost]).

Across five tiers × ~2–4 chambers, the pyramid is simultaneously **tech tree, building tree, and faction identity**.

Rules:
- Pairs are genuine forks, not power tiers (defensive vs. ritual-enablement, not better vs. worse).
- **No respec, ever.** Restoration is permanent.
- Deeper tiers offer *weirder* choices, not bigger numbers. Tier II gives +8% tax; Tier V should change what the faction is.
- Some consecrations are **externally visible/scoutable** so enemies can react.

### Tombs as settlements
**Ivoryscar cannot found settlements.** Instead the map is seeded with tomb sites — some known at start, most hidden until surveyed — which they excavate into functioning settlements. Expansion is discovery-driven and pre-placed: the map decides where their empire *can* be.

- **Anti-turtle by construction:** outlying tombs are the only source of **natron and soulshards**. The pyramid is fed by the frontier. Retreating to the pyramid stalls the Work.
- **Site revelation:** exploration, chamber consecrations (e.g. Tier III unlocks the old kingdom's own maps), and capturing enemy settlements built atop tombs.
- Many tombs sit **under other factions' cities** → conquest with a specific motive ("there is something beneath your capital that belongs to me"). Natural casus belli generator.
- **Depth instead of settlement tier.** Advance depth by excavating, not constructing. Shallow: basic yield, small sleeper garrison. Deep: soulshards, elite sleeper stock, Deep Roads connectivity. Building slots are replaced by chamber consecrations — same forked-choice grammar as the pyramid, smaller scale. **The pyramid is the largest instance of the tomb class, not a bespoke entity.**
- **Defensive strength scales with depth.** A barely-excavated tomb is a hole in the ground; the old core is a fortress. Frontier acquisitions are fragile by design.

### Recruitment: Awakening
Units are **awakened** from tombs, not recruited. Each tomb holds a finite, defined sleeper stock (this one: two sphinx broods and a construct cohort; that one: a choir of angels). Awakening costs Vigil and draws from that specific tomb.

- Army composition reads off the map — **order of battle is geography**.
- Tiered regeneration: chaff regrows; mid-tier regrows very slowly and only while consecrated and undisturbed; **elites never**. Mistakes cost your ceiling, not your floor.

### Deep Roads
Underground redeployment network rooted at the pyramid. **Each tier restored extends range outward** — digging down expands reach across the map. Answer to being a defensive faction with a vast frontier: they can't hold everything, but they can *be* anywhere the network reaches.

### Silence of the Sands
Desert provinces generate Vigil scaled by how **undisturbed** they are: no recent battles, no foreign armies passing, low Development. War on their own soil is expensive even in victory → pushes them toward intercepting at the edge and punishing transgressors abroad. Aggressive neighbors can wage economic war just by marching through (intended counterplay).

### How other factions fight Ivoryscar
Other factions **cannot use tombs themselves.** Three-state verb system on captured tombs:

| Verb | Cost | Effect | Ivoryscar restoration cost |
|---|---|---|---|
| **Plunder** | Cheap, fast | Resources + commander equipment items | Moderate |
| **Seal** | Expensive: resources + army parked several turns | Large **local population happiness boost** | **Dramatically higher** |

- Neither destroys the tomb. Both are reversible by recapture.
- **Plunder is farmable:** leave it open, let Ivoryscar re-excavate, return and plunder again. This is intended emergent behavior — do not patch out.
- **Sealing is the real weapon.** It denies rather than taxes.
- **Sealing is domestically attractive** (happiness) so factions with no grudge seal tombs as public works. Ivoryscar's obstacles are not all malice.
- **Faction flavor via shared verb:** Moonspear/Sunblessed seal cheaply with bonus Sanctity; Gladehost sealing restores land; Forsaken/Tainted Jade seal poorly and plunder excellently; Skulloath cannot seal (they wreck and leave).
- **Anti-strangle guards:** sealing requires the tomb to be unoccupied by Ivoryscar armies (contested, not done at range), and retaking a sealed tomb refunds part of the original excavation. Recapture is a bitter, expensive win — never a hopeless one.

### Grave-robbery consequence (minimal)
No ledger system here (Wrath belongs to Thunderswarm). Just a standard diplomatic penalty plus a defensive bonus on recently-defiled tombs. Cheap, no new mechanic.

### Ruin verb: Necropolis
A ruined city is full of dead who were never properly interred. Ivoryscar **consecrate them into a necropolis**: the ruin becomes a minor node on the **Deep Roads** network, with a small sleeper stock and a modest natron yield.

Non-destructive and non-consuming, consistent with a faction that negotiates before it fights. It also gives them legitimate reason to want ruins deep in other people's territory — there are unburied dead there, and that is intolerable.

### The Approach: diplomatic escalation ladder
**Their motive is never the city — it is what lies beneath.** War is usually an inefficient way to get it. Ivoryscar opens with negotiation and escalates:

1. **Excavation Rights (default opener).** They approach the owner of a province containing a tomb and offer payment for permission to dig: gold, relics, awakened guardians seconded to the settlement's garrison, trade terms. The city stays owned, populated, and taxed by its holder; they simply tolerate crews working underneath. A neighboring player can coexist with Ivoryscar for an entire campaign without a shot fired. Creates an ongoing relationship — the tomb keeps producing, they keep paying.
2. **The Petition.** Cede the province outright, with compensation scaled to its value. They prefer ownership because rights can be revoked and an owned province can be excavated to full depth. Refusal is not automatically war; it advances them one rung.
3. **War**, resolved by **Liberate**: the city becomes an independent tributary, the population survives, Ivoryscar gains unrestricted access to what is beneath.

**Convergence (key property):** liberation and granted excavation rights reach the *same end state*. The peaceful path and the war path converge — a player who refuses the deal ends up in exactly the position they were offered, minus a war. Bitter and legible.

**Verb access for Ivoryscar:**
- **Liberate** — their diplomatic/target outcome. Deliberately *weaker* than Cinderguard's or Sunblessed's version: tribute and little else. Its value to them is dig rights, not empire. (Preserves verb tiering.)
- **Sack / Enslave** — for cities with nothing beneath them, or when labor is urgently needed.
- They still **cannot administer ordinary settlements**, so Occupy is unavailable.

**Moral texture (intended, do not sand down):** they negotiate honestly, honor deals, and leave you alone if you do not build on their dead — *and* they will march a captured population into a pit to die moving stone. Both true simultaneously, no contradiction from their side. This makes the diplomatic option **more** disturbing, not less: accepting their gold means knowing where the labor came from.

**Balance guard:** revoking granted excavation rights must be a serious act — heavy reputation loss with Ivoryscar and immediate casus belli — or players will grant rights, let them invest, then cancel. The deal must be safe for both sides or the entire ladder collapses back into war-first.

### Interlocks
| Touches | Via |
|---|---|
| Tainted Jade, The Forsaken | Natural tomb-robbers (rituals, necromancy on pharaonic dead) — default antagonists through play, not script |
| The Forsaken, Skulloath | Captive trade — supplier who is also a thief |
| Empire | Senate demands for archaeological plunder (event chains) |
| Shardhorde | Crystal veins beneath desert provinces — innocent-transgressor friction |
| Sunblessed, Gladehost | Hardcoded revulsion at the captive economy |
| Sunblessed | Uniquely able to broker restitution in the desert |

### Balance flags
- Excavation must be gated by **supply, not gold**, or a rich player straight-lines to Tier V. Natron/soulshards only from tombs; captives only from war and trade.
- **Decide first:** target turn count for a full five-tier excavation in a normal campaign. Every cost number falls out of that figure.
- Sleeper scarcity: too finite → death spiral from one bad war; too regenerative → tomb defense stops mattering.

---

## Part 4: Thunderswarm — ACCEPTED

**Fantasy:** angels who revere dragons as divine. Humans encroached on the nesting grounds; the response was fiery devastation that made the Empire retreat from its outer settlements — the event that created the Cinderguard. From the outside it looked like unprovoked apocalypse.

### Core value: Wrath (per-faction grudge ledger)
**Trespass, not theft.** They are not angry that you took something. They are angry that you are *there*.

- Wrath accrues per faction from acts within **nesting territory**: settling, raising **Development**, logging, mining, road-building through the passes, and killing dragons.
- **Most generation is passive and unintentional.** A faction expanding normally into good land builds a case against itself without ever fighting them.
- **Nesting grounds anchor it geographically.** Certain provinces are nesting territory (some obvious, some not), weighted by sanctity. They do not care what you do a thousand miles away. Other players get real counterplay through *knowledge* — learn where the nests are, expand around them.
- Like Cinderguard, Thunderswarm is invested in land it does not hold.

### The Reckoning ladder
Wrath thresholds unlock escalating responses:

1. **Warning.** A herald arrives; the sky darkens over the offending province; explicit demands are issued (abandon the settlement, cease development, pay tribute in dragon-gold). A real diplomatic event with a real choice. *The Empire's historical retreat was this.* Compliance being possible is what makes the mechanic tragic rather than arbitrary.
2. **Casus belli + combat bonuses** against the transgressor.
3. **Devastation (capstone).** A declared campaign of fire against a specific faction: free storm front over their territory, bonus replenishment while operating in it, and the ability to **raze settlements for Wrath discharge instead of gold.** Razing a city *reduces* their Wrath toward you — their goal is a world returned to silence, not a world conquered.

### The storm front
The physical form of the grudge. It sits over whoever is being punished: their replenishment and vigor, enemy missile penalties, continuous attrition on the target's settlements. **Other factions see the weather turn against them turns before the armies arrive.** They are the most legible threat on the map — right for a faction whose whole nature is that it announces itself.

### Proactive loop (they do not sit and wait)
"Leave the nesting grounds alone" is a state that must be *actively maintained*. Their forward agenda:

- **The nesting grounds are unfinished.** Only a fraction of historical nests are active at start; the rest are dormant, ruined, or buried under other people's cities. The faction goal is restoring the full range. Their most sacred ground is frequently *underneath somebody else's province* — so they take land proactively and call it returning it.
- **Dragons as the growth economy.** Currency is brood, not gold. Nests produce eggs over time, scaled by how undisturbed and wild the province is. Expand nesting range → raise Harmony → hatch more → field more. A quiet world means a busy rewilding-and-breeding campaign. Killing a dragon is permanently expensive for them, which makes Cinderguard dragon-hunters existential rather than flavor.
- **Interdiction (active diplomatic verb).** They can unprompted declare a province forbidden to any faction, with demands attached. This is the mechanic that made the Empire retreat, now player-initiated rather than Wrath-gated. From turn ~10 everyone's expansion planning must account for the sky claiming a province they wanted. Compliance buys a buffer; refusal gives Thunderswarm a war of its own timing. They can effectively **manufacture Wrath** by claiming ground someone already uses — aggressive play that still feels righteous.
- **Rewilding as a targeted build action.** Razing settlements returns provinces to wilderness (Development → 0, Harmony recovers), eventually making land nest-viable again. This is aimed specifically at **nesting grounds and their immediate surroundings**, not at civilization in general.

**Territorial model — important:** Thunderswarm **hold normal cities and settlements** and play the standard settlement game elsewhere on the map. They are not an anti-civilization faction (that is Gladehost). They are a conventional power with one non-negotiable red line: the nesting grounds must be cleared and kept clear.

- Consequence for Wrath: they punish Development **in and near nesting territory only**, not Development as such. Their rage is proportionate and legible rather than ideological.
- **Intended texture:** other factions can fairly point out that the sky-lords maintain fine cities of their own while burning yours. Keep this hypocrisy; it is good characterization.

**Resulting loop:** hold and grow a normal empire, reclaim and rewild the nesting grounds, hatch brood, declare interdictions, burn whoever refuses. **Wrath is a targeting system, not an engine** — it decides who burns first, how hard, and at what discount.

### Ruin verb: Eyries
Thunderswarm raise **eyries** on Small Ruins inside nesting territory, adding brood capacity. Ruined ground is ideal — already emptied of people, already returning to Harmony. Their razing therefore feeds their own nesting economy on a delay.

### Discharge and the peace condition
Wrath is reducible: abandoning or razing the offending settlement, letting a province return to wilderness (Harmony recovery), tribute, and Sunblessed brokerage. **A world that leaves the nesting grounds alone gets a quiet Thunderswarm.** Other players control the temperature — whether Thunderswarm is a background power or a burning apocalypse is decided by everyone else's expansion patterns.

### Interlocks
| Touches | Via |
|---|---|
| **Cinderguard** | *Structural nemesis.* Cinderguard exist because the Empire complied with the Reckoning and abandoned the outer settlements. Their oath-bonds sit on settlements Thunderswarm demanded be emptied — **every oath generates Wrath.** They are the one faction that cannot lower Wrath without abandoning its identity. No script required. |
| **Empire** | The one enemy that once showed proper deference. Empire and Cinderguard blame each other for the same event. |
| Gladehost | Shared rewilding goals via Harmony; natural alignment |
| Anyone expanding into nesting territory | Passive Wrath from Development in nesting provinces (and only those) |
| Sunblessed | Brokerage can discharge Wrath |

---

## Part 5: Cinderguard — ACCEPTED

**Fantasy:** legionaries ordered to fall back to the coreland and leave the outer settlements to burn, who refused. They are not a nation. They are a promise that outlived the state that made it.

### They own nothing
Cinderguard **cannot found or hold cities**. Every settlement they take is **Liberated**, and liberated settlements enter their Obligation Web as **oath-bonds**. No taxes, no city management, no building queues on settlements.

- **They can oath-bond settlements they never conquered.** Any settlement — Empire cities, Sunblessed free cities, anyone's — can be brought under protection by agreement. Expansion is not taking land, it is accumulating responsibility across other people's borders.
- Their obligation web therefore overlaps everyone else's by construction, generating friction without scripting.
- Liberation and oath-bonding are **a single act** (see Substrate §6).

### Watchforts (their only holding)
They build **forts**: a settlement variant with building slots and real choices. Their construction outlet and their claim on ground nobody else wanted. The legion that stayed builds its own castles at the edge of the abandoned frontier.

- **Forts are nearly worthless alone.** Fort income scales with the oath-bound settlements inside its **protection radius**, weighted by those settlements' prosperity. A fort in empty wilderness is dead weight; a fort near a cluster of wealthy cities is a fortune.
- Build decisions are **spatial, not provincial**: not "is this good land" but "what can I reach from here, and can I hold it."
- **Failure is immediately material.** A protected city gets sacked → income drops that turn. No abstract penalty needed. Oath integrity remains as a lighter morale/unlock layer on top, but poverty is the primary punishment for a broken promise.

### Oath-bonding is proximity-based, not event-based
Settlements within a fort's radius can be bonded by agreement. Willingness scales with **actual threat in the region** and **fort strength**.

Loop: build a fort where danger is → prove you can hold it → neighbors sign on.

- **No petition events.** (Rejected: would require the AI to reliably telegraph attacks several turns ahead — fragile and would misfire constantly.)
- **Proactive by construction:** the player chooses which frontier to plant on. Cinderguard reads the map asking where the fires will start, then gets there first.
- **Second-order effect:** they are incentivized toward genuinely dangerous ground, because safe cities do not need protection and will not pay for it. Optimal play is standing between other factions and disaster — precisely the fantasy.

### Fort building choices (forks, not stacking queues)
Same grammar as Ivoryscar's chambers: mutually exclusive pairs.

| Fork | Option A | Option B |
|---|---|---|
| Reach | **Signal Tower** — extends protection radius, grants forced-march beacon network | **Deep Garrison** — holds far more troops in place |
| Purpose | **Hunting Lodge** — dragon quest access, trophy gear forging | **Refuge** — evacuation capacity |

**Refuge matters structurally:** a settlement that cannot be saved can at least be emptied, converting a defeat into a partial save and preserving integrity. This is the **honest way to fail** — the player chooses *how* to lose ground rather than only eating penalties.

### Ruin verb: Watchforts on ruins
Watchforts may be built on **Large or Small Ruins** as well as on open ground. Thematically exact: they fortify the wreckage of the frontier they refused to abandon, and ruins are disproportionately common on exactly the abandoned outer ground their oaths cover.

### Beacons
Bonded settlements and Signal Towers form a network granting large movement and forced-march bonuses between them, plus early warning of attacks on the web. They cannot garrison everything; they cover an impossible frontier by being fast.

**Web shape is strategy:** a contiguous chain is defensible; a scattered set of far-flung oaths is a death sentence. The pull to say yes fights the geometry that punishes it.

### Dragon hunting
Their power curve. Small elite armies, few in number, commanders equipped with trophy gear harvested from dragon kills.

### Vulnerability (the balancing cost)
Forts are the pressure point: cheap enough to plant aggressively, weak enough that an overextended web gets picked apart.

**Losing a fort severs every oath in its radius at once** — a single fort falling can cost a quarter of the economy. Collapse comes from a cascade of broken oaths, not from an enemy reaching a capital.

### Interlocks
| Touches | Via |
|---|---|
| **Thunderswarm** | *Structural nemesis, doubled.* Their oaths sit on settlements the sky demanded be emptied; Watchforts raise **Development** on ground meant to stay empty; and killing dragons is the highest Wrath-generating act in the game. Permanently the most hated faction on the map, by the faction least willing to negotiate. The one faction that cannot lower Wrath without abandoning its identity. |
| **Empire** | Kept as a *wound, not a mechanic* (scope): permanent diplomatic penalty, mutual claims, and a small number of high-impact event chains — demands for dissolution, or a pardon conditioned on abandoning the outer oaths. No legitimacy slider. |
| Sunblessed | Overlapping Obligation Webs; both run liberation-based empires and may compete for or share the same free cities |
| Skulloath, Tainted Jade | Primary threat sources that drive settlement willingness to bond |

---

## Part 6: Tainted Jade — ACCEPTED

**Fantasy:** they stayed. When the empire fell, half the people walked out into the world to bring counsel (the Sunblessed). The other half stayed in the ruins with the gods who ate it, and concluded the collapse was not proof the bargain was wrong — only that the payments had fallen behind.

### The two gods
| God | Domain | Wants | Pays in |
|---|---|---|---|
| **God of Death and Endings** | death, endings | **Sacrifices** — quotas of bodies on ritual dates | Faction-wide boons; the aggressive war economy |
| **Goddess of Life** | life; created undeath by accident, grieving as her children died to mortal perils | **Consecrations** — shrines raised over the dead | **Undeath**: cheap undead levies raised from consecrated ruins, requiring no captives |

**The key property: the gods want different wars.** Death wants prisoners taken alive. Life wants cities destroyed. Two incompatible targeting preferences inside one faction; the player decides which their campaign is actually about.

### Temples (favor system — spatial, not a slider)
Basic temple → branch to one god → several building-stage upgrades.

- Favor is **faction-wide but generated spatially** by what is built where. Visible on the map, expensive to reverse. Preferred over an abstract slider for exactly this reason.
- **Both gods must stay above a minimum or they sour.** The player may lean hard but never abandon one.

### The Debt (core engine)
Fixed ritual dates on the global **Calendar**, visible to every player, each carrying a **quota**.

- Meet it → substantial faction-wide boon until the next date.
- Miss it → the gods take payment themselves, **god-specific**:
  - **Death** takes population from your own settlements; units dissolve mid-campaign; prosperity is stripped.
  - **Life** withdraws her gift — **undead crumble where they stand.**
- Punishment should genuinely hurt and read as a small collapse, not a soft penalty.

**Quotas escalate.** Each cycle demands more than the last; the player cannot stabilize. Whatever satisfied the gods forty turns ago is now insufficient. This forces continuous aggression even when strategically stupid — **which is exactly why the empire fell the first time.** The player repeats the mistake with full knowledge.

**You can always pay from your own people.** Captives are the efficient currency, but your own population is always available. Tainted Jade can never be truly cornered: a losing Tainted Jade eats itself and keeps going, hollowing out its own cities to make quota. Their failure state is a slow spiral, not a sudden loss.

**Balance:** tie quota scaling to the player's own size rather than turn count, so a wide empire owes more than a small one and pressure stays proportional. Too steep → every campaign self-consumes by ~turn 120; too shallow → the Debt stops mattering.

### The Ruins (homeland and the central variability lever)
Their starting region is a dense field of **pre-seeded Ruins** from the collapse — reusing the Ruins state from Substrate §6, not a new system. Restoration is **cheap for Tainted Jade, full price for everyone else** (it is their heritage).

Early game: rebuilding a dead empire's cities inside its own corpse. Homeland is rich in potential but starts near nothing. Outward expansion comes once the ruins run out.

**Every ruin is a permanent, mutually exclusive choice:**

| Option | Gives | Costs |
|---|---|---|
| **Rebuild** into a city | Economy, settlement slots, armies to feed the Death god's raiding | No Life favor from this site |
| **Consecrate** as a shrine | Life favor + **undead levies** requiring no captives | No tax base |

Because ruins are finite and pre-seeded, **every campaign allocates them differently.** A fully rebuilt homeland is rich and godless; a fully consecrated one is a necropolis with no economy. The player cannot have both.

### Manufacturing ruins
Tainted Jade have **Raze** access, with the motive inverted from other razers: Shardhorde and Thunderswarm raze to *empty* land; Tainted Jade raze to *sanctify* it.

**Their Raze is "Raze & Consecrate" — a single verb.** Razed cities are consecrated automatically; there is no intermediate plain-ruin state and no cooldown. They would never want a plain ruin (strictly worse for them), so no meaningful choice is lost, and a timer here would only tax the player for using their own identity mechanic.

**Where the fork lives:**
- **Pre-seeded homeland ruins:** genuine permanent rebuild-vs-consecrate choice (no conquest moment at which to decide).
- **Conquered enemy cities:** the fork moves up into the Settlement Resolution menu — *Occupy* for a city, *Raze* for a shrine. Same decision, made once, where the player is already thinking about it.

**Limiter is opportunity cost, and it is sufficient on its own:**
- Consecrated ruins yield meaningfully less than a functioning city. Every shrine is a city you do not have.
- Undead levy capacity per shrine is **fixed and modest**. Twenty shrines = twenty small levy pools and twenty missing economies. A raze-everything player fields a large, cheap, un-replenishable army with no money to use it — a legitimate strategy with an obvious ceiling, not an exploit.
- Razing is diplomatically catastrophic with most of the roster.

**Counterplay — Desecration:** other factions can **desecrate** consecrated ruins, reverting them to plain ruins and stripping the Life favor. Fits Moonspear and Sunblessed exactly. Tainted Jade's shrine network is contestable ground, not permanent progress. No new system — another entry in the Landmark verb table.

### Captives and the calendar
They are on the **Enslave** list. Quota pressure drives raids against whoever is nearest and softest, regardless of whether it is a good war.

- **Neighbors learn to read the calendar** and know exactly when raids come — same predictability-as-gameplay principle as Moonspear's lunar cycle.
- Direct competition with **Ivoryscar** for the same captive supply: each other's most natural trade partner *and* most natural rival, since both need bodies and neither has enough.

### Interlocks
| Touches | Via |
|---|---|
| **Sunblessed** | *The mirror.* Same ruins, incompatible verbs — Tainted Jade reconsecrate to the old gods, Sunblessed sanctify. Every ruin is a contested claim on what the empire *was*, and both believe the other betrayed it. **Hardcode mutual permanent hostility**; it is the roster's one genuine family argument. |
| **Ivoryscar** | Captive market; prolific tomb-plunderers with no interest in sealing |
| **Cinderguard** | Their raids are a primary reason settlements seek oath-bonds |
| **Moonspear** | Sanctity inversion makes them a standing crusade target |
| Land State | Reconsecration pushes Sanctity into a corrupted variant that neighbors can watch spreading |

---

## Part 7: Sunblessed — ACCEPTED

**Fantasy:** the other half of the empire. Rather than stay and pay the gods, they walked out. They renounced the corrupting magical power that tore down their empire in its hubris and turned to the earthly deities of sunlight, life, and nature. They travel with sacred beasts, offering research, healing, and counsel — **a horde that gives instead of taking.**

### The subversion
They are a **migratory faction** that does not plunder. Processions arrive and *improve* the settlements they visit: research aid, happiness, healing, counsel. **Generosity is the conquest.**

### Income from goodwill (the unique posture)
Their economy is hospitality, gifts, and tribute paid by host settlements in exchange for what they provide.

**They are the only faction whose economy requires everyone else to be prosperous and at peace.** A continent at war starves them. Every war on the map is read as a personal loss.

### Welcome wears out
A Procession parked too long at one city hits **diminishing returns** — counsel given, research done, goodwill spent. This forces circulation.

Their loop is **routing, not parking**: a constant tour with real decisions about where to be. (Distinguishes them from Shardhorde, a *migration* faction; Sunblessed are a *circuit* faction.)

### Conversion: Gratitude + Crisis
**Presence does not convert anyone.** Two-part system:

**1. Gratitude is a decaying deposit, not a stay.** Each visit accumulates Gratitude in the settlement while a Procession is nearby. It **decays slowly once they leave**, and **nearby shrines slow that decay further**. Conversion is the product of *a relationship maintained over decades of returning*, not of a long occupation. Circulation is therefore the **delivery mechanism** for conversion, not an obstacle to it.

**This gives shrines a concrete mechanical job:** they are the persistence layer, keeping relationships alive in provinces the Processions cannot currently visit. Shrine placement becomes a real strategic question and destroying a shrine becomes meaningful — which is what "territory without provinces" needs in order to mean anything.

**2. Conversion fires at the rebellion threshold, branching on Gratitude.**

**Sunblessed do not affect happiness at all — in either direction.** Their visits raise **income and, above all, research**. This is deliberate: they must have *no lever* on the thing they are waiting for, or the faction becomes self-defeating (presence → happiness → no unrest → no conversion).

The trigger is therefore a **single existing value**. Raids, overtaxation, poor food supply and the rest already push happiness down; no separate catastrophe list is needed. One check at the normal rebellion threshold:

| Gratitude when unrest hits the rebellion threshold | Outcome |
|---|---|
| Low / none | **Ordinary rebellion** — rebel armies spawn, the province burns, a bandit or independent state emerges |
| High | **Orderly secession** — the city becomes an independent city-state generating income for the Sunblessed, entering their Obligation Web with tithes, trade, and levies |

**They are not buying rebellion. They are buying the *alternative* to rebellion.** Their presence enriches the owner the entire time and only cashes out once the owner has already failed the city.

**They cannot cheat.** With no lever on happiness in either direction, they cannot manufacture the crisis. They can only be present, be useful, and wait for someone else's failure. *This is the line separating them from the Forsaken.*

**Gratitude should be visible to the owner.** A ruler seeing accumulated Gratitude in a border province can read the bargain plainly: enjoy the research income, but understand this province now carries a penalty for misgovernment that others do not. Far better than an invisible timer, and it lets an owner expel the Processions before it is too late.

**The honest devil's bargain:** any host gets years of income and research for free and pays nothing — *unless* they misgovern or fail to defend the city, in which case they lose it to the Sunblessed rather than to fire. Competent rulers take the deal, which is exactly how the Sunblessed end up embedded across half the map.

**Knock-on pressure (good for the 4X layer):** overtaxing to fund a war, or stripping a garrison and letting a province be raided, becomes far riskier if that province is full of grateful priests. **The Sunblessed threat is downstream of overextension and misrule.**

- **They cannot take a contented, well-defended city at any price.**
- **Clean counterplay: govern well, tax fairly, defend your provinces — and your cities are yours.**

### The central tension
**Their income wants peace; their growth needs crises.** A Sunblessed player watching a distant war start feels both at once — revenue drying up, opportunity opening.

Their strategic layer is therefore **prediction**: betting on which cities will fail, years before they do, and already being loved there when it happens. Reading the map for coming disaster is the core skill.

**Structural squeeze:** conversion strips provinces from the great powers, so the better they do, the more the map's real powers want them dead — and war is precisely what ruins their income. *Their success mechanism undermines their sustenance mechanism.* The tension is structural, not bolted on.

### Helplessness (the emotional core)
They invest decades in a city's prosperity; when Skulloath burns it they lose the income and the investment and **can do nothing** — no garrison, no claim. Their only answers:
- strengthen the host's own defenses, or
- convert it into a free city they can support through the Obligation Web — which is exactly what makes the great powers hate them.

Every road leads back to the same squeeze.

### Shrines (their build, their only footprint)
They **cannot found cities**. They raise shrines at ruins and sacred sites: permanent, point-based, generating **Sanctity**, anchoring Procession routes, holding Gratitude, and amplifying nearby effects.

Shrines are **nearly undefendable** — enemies have something to hit that genuinely hurts. Territory without provinces.

**Sanctified ruins:** the same finite ruins Tainted Jade contest, *sanctified* rather than reconsecrated — memorial and teaching sites. **The Maya split is fully symmetrical:** one faction rebuilds or consecrates, the other sanctifies; neither can share; **desecration works both ways.**

### Holy animals (their Named Entities)
Each Procession is led by a sacred beast; species determines function:

| Beast role | Effect |
|---|---|
| Amplifier | Boosts Gratitude deposited per visit |
| Healer | Grants Sanctity and healing to hosts |
| Arbiter | Permits brokerage actions |
| Guardian | Protects the Procession |

Few in number, slow to replace, **losing one is a serious setback.** Processions are lightly defended, so hunting one is worth an enemy's time.

### The renounced magic (deliberately small — scope)
**Not a track or a slider.** A handful of forbidden old-empire rituals available in desperate moments: powerful, with permanent costs to Enlightenment and shrine sanctity.

**Their failure state is becoming Tainted Jade.** This reads best as a few irreversible choices, not a system. A Sunblessed player reaching for the old power to save a city should be a story they remember, not a build path.

### Brokerage (payoff, not engine)
They may intervene in others' wars, propose terms, and be paid in reputation and gold. They can **discharge Thunderswarm Wrath** and **broker Ivoryscar restitution**. Real value and flavor — not what they do all day.

### The moral stance is mechanical
Settlements threatened by slavers and sacrificers accumulate Gratitude **dramatically faster**, and raids from those factions are what push happiness toward the secession threshold. Ivoryscar and Tainted Jade activity actively feeds Sunblessed growth — the worst factions on the map are their best recruiters, and a self-balancing pressure on those two.

### Interlocks
| Touches | Via |
|---|---|
| **Tainted Jade** | *The mirror.* Hardcoded mutual permanent hostility; contested finite ruins with incompatible verbs; mutual desecration |
| **Cinderguard** | *Direct competition on the same failing frontier* — one offers protection, the other offers succession. Overlapping Obligation Webs |
| **Ivoryscar** | Hardcoded revulsion at the captive economy; uniquely able to broker desert restitution; cheap tomb-sealing with bonus Sanctity |
| **Thunderswarm** | Brokerage discharges Wrath |
| **Skulloath / Tainted Jade** | *Raiders are mechanically their recruiters.* Raids tank a city's happiness; if Gratitude is high, the raid hands the province to the Sunblessed. Those factions perform Sunblessed conquest on their behalf |
| Every great power | Conversion strips provinces without war; **all wars reduce Sunblessed income** |

### Risk flag
Their web output overlaps Cinderguard's — both field armies from obligated settlements. Acquisition differs sharply (crisis-succession vs. protection-oath), but if playtesting shows they feel similar, the lever is: **Sunblessed levies numerous and mediocre; Cinderguard's few and elite.**

---

## Part 8: The Empire — ACCEPTED

**Fantasy:** the one power that learned its limits the hard way. Every other faction wants more. The Empire is the only one that knows what happens when you take more than you can hold — because it already did, it pulled back, and the men it abandoned became the Cinderguard.

### Integration (core mechanic)
Conquered provinces do not simply become yours. Each carries an **Integration** value rising slowly with connection, garrison presence, proximity to the capital, and time held.

- Low-Integration provinces yield a fraction of their potential and generate unrest.
- **The Empire cannot snowball by conquest.** They must *digest*, and digestion takes decades.

Three payoffs:
1. A genuinely different expansion rhythm — slow, deliberate, infrastructure-first.
2. It explains the historical retreat **mechanically** rather than as backstory: the outer settlements were exactly the provinces that could never be integrated.
3. It hands the **Sunblessed** their natural prey. A sprawling half-digested frontier is precisely where Gratitude converts. **Overextension is punished by other factions eating you, not by an abstract penalty.**

**Balance flag:** Integration must not be pure friction. A *fully* integrated province should be meaningfully better than any other faction's equivalent holding. The Empire's promise is that what they hold, they hold **well**.

### Two routes to Integration (both viable)
Military and infrastructure are **two solutions to the same problem**, not two unrelated activities. Players may mix freely.

| Route | Method |
|---|---|
| **Military** | Garrisoned troops speed Integration — hold conquests down by occupation |
| **Infrastructure** | Roads and aqueducts bind provinces into the network |

### Roads and aqueducts (the visible network)
Together these should visibly stitch the map into something that reads as an empire from a distance — the core aesthetic fantasy.

- **Roads:** movement, connectivity, Integration reach. **Usable by invaders** — the Empire's greatest asset is also how enemies reach its heart. Good history, real strategic cost, and it makes road placement non-trivial.
- **Aqueducts:** growth and prosperity, and **severable**. Cutting one during a siege or raid is historically real and mechanically excellent: enemies can attack the infrastructure Empire without taking a single city. The infrastructure path's payoff and its exposed flank in one building.

### Culture spread (preparation, not conquest)
Cultural pressure bleeds from integrated provinces into neighbours:
- lowers the future Integration cost of anything conquered there,
- lets **minor or independent settlements** join peacefully.
- **Major powers' cities never flip to it.**

The Empire softens ground for expansion decades before the armies arrive. Deliberately kept distinct from Sunblessed secession.

### The Senate (three blocs, no legitimacy slider)
Per scope cuts: no civil-war meter. Instead, three competing blocs whose influence is **driven by the player's buildings** (see Substrate §7).

| Bloc | Empowered by | Unlocks |
|---|---|---|
| **Expansionists** | barracks, training grounds, frontier forts, military ports | Aggressive unit lines, claim-pressing diplomacy |
| **Traditionalists** | temples, aqueducts, civic and administrative buildings | Integration and army bonuses |
| **Mercantile** | markets, roads, harbours, workshops | Roads, trade, buying your way out of problems |

- Each bloc issues periodic **mandates**: take that city, restore that province's Integration, secure that trade route, fund that temple. Completing one rewards the player and raises that bloc's influence; ignoring one lowers it.
- **The player's build order writes their politics without a single explicit choice.** A road-heavy Empire drifts Mercantile; an aqueduct-and-temple Empire drifts Traditionalist. Both are "infrastructure" and produce different Senates.
- Almost entirely data-driven — cheap to build, cheap to iterate.

**The central squeeze:** Expansionist mandates demand conquests that Integration cannot absorb. A player who builds barracks to fight their wars gets a Senate that demands more wars. Obeying the Senate reliably overextends you; defying it costs the tools you need. *This is the same failure that created the Cinderguard, offered to the player as a live decision every twenty turns.*

### Settlement Resolution (characterization by restriction)
- **Cannot Raze.** A civilizing empire that erases cities is a contradiction.
- **Cannot Enslave.** Places them in clean opposition to Ivoryscar and Tainted Jade without needing an alignment tag.
- **Best at Occupy** — they integrate conquered cities better than anyone. That is the whole Roman proposition.

### Scope cuts
- **No persistent named legions.** (Cut.) The military path's identity comes from Integration-by-garrison instead.
- No legitimacy slider or civil-war meter.

### Interlocks
| Touches | Via |
|---|---|
| **Cinderguard** | *A wound, not a mechanic.* Mutual claims, permanent diplomatic penalty, and a handful of high-impact events: Senate demands for dissolution, or a pardon conditioned on abandoning the outer oaths. **The Traditionalist bloc is sympathetic to them; the Expansionists contemptuous** — the player's own Senate is split on the question |
| **Thunderswarm** | The one power that showed proper deference: lower baseline Wrath and access to interdiction compliance terms nobody else gets. **It should be tempting** — accepting an interdiction is cheap, and it is how the whole tragedy started |
| **Sunblessed** | Half-digested frontier provinces are their natural prey |
| **Ivoryscar** | Petitions and excavation-rights offers; Senate event chains demanding archaeological plunder |
| **Skulloath** | Old Ways tribute extortion creates border friction |

---

## Part 9: Shardhorde — ACCEPTED

**Fantasy:** stone-age tribes travelling with crystal-infused megafauna. Their cities are alive, and they walk.

### Elder beasts are mobile settlements
Giant dinosaurs with crystalline growths that **hold the faction's buildings and fight in battles as large powerful entities.**

- **Your city is your army.** Every battle risks the buildings, the economy, and decades of accumulated investment simultaneously. No other faction weighs "do I commit my capital to this fight."
- Building slots scale with the beast's **growth stage** — beasts age into larger cities over decades.
- Few in number, slow to replace. This single fact governs the faction's entire feel: Shardhorde players are cautious with their heaviest assets in a way nobody else is.

### Beast defeat: the two-strike rule
A defeated elder beast **does not die.** It becomes **immobile for 1–3 turns while it recovers.**

- **A beast defeated again while wounded dies** — and everything built on it is lost.
- This is **the only time Shardhorde use fortifications**: earthworks and stake lines thrown up around a downed beast. Implement as a **rapid deploy action, not a build queue** — they fortify only in emergencies.
- Other beasts and armies can converge to defend it. Every beast defeat becomes a converging emergency rather than a coin flip.
- **The most readable objective in the game:** everyone within reach knows there is a wounded city sitting in the open for three turns.
- **The grazing clock keeps running while it is down.** A beast wounded on already-stripped ground starves while helpless and cannot be moved out. Nasty compounding pressure that punishes fighting in exhausted territory — exactly the strategic lesson the faction should teach.

### Grazing depletion (and why they make enemies by existing)
A beast sitting in a province **drains its yield over time**, and **nearby settled cities lose income while it is there.** Make it **symmetric**: settled cities likewise suppress beast yields in their vicinity.

- **The Shardhorde are materially incompatible with settled civilization** — not ideologically (Gladehost) and not by territorial red line (Thunderswarm), but because they and cities are competing uses of the same land.
- A neighbour has a real economic grievance without the Shardhorde having done anything aggressive.
- **This produces their Raze motive with no "barbarians smash" framing.** They raze cities because cities eat the grass: a cold, legible, entirely non-evil reason to destroy a settlement.

### Migration is forced and one-way
Unlike the Sunblessed *circuit*, this is **grazing**: strip a province, move on, let it recover over a long period.

Their campaign is a slow rotation across the map, always seeking unspoiled ground — and the map slowly runs out of it. **Late-game Shardhorde are squeezed by their own history.**

### Crystal veins (growth economy)
Attuning at a vein advances a beast to its next **growth stage**, adding building slots and battlefield power.

- Veins are **fixed, finite, and frequently inside someone else's territory** — including beneath Ivoryscar desert provinces (innocent-transgressor friction, already flagged in Part 3).
- Migration therefore has **destinations, not just directions**, and the important ones are contested.

### Ruin verb: Calving grounds
Herds may claim Small Ruins as **calving grounds** — a **temporary, non-permanent claim** that accelerates beast growth while the herd remains and lapses when it moves on. Nomads use sites; they do not hold them. This is the only ruin verb on the map that expires by itself, and it means Shardhorde contest ruins without ever removing them from circulation.

### Land State interaction
**Grazing suppresses Development and slowly raises Harmony.** Herds trample infrastructure and the land goes wild behind them, so Shardhorde are **passive rewilders** — aligning them with Thunderswarm and Gladehost without duplicating either faction's method.

### Expansion means herd size, not territory
More beasts is more empire. Their strategic layer is **husbandry**: when to risk a beast, and whether to spend growth on a new calf or on advancing an existing one.

### Building forks on beasts
Same grammar as Ivoryscar chambers and Cinderguard forts — mutually exclusive pairs (war howdah vs. nursery, and similar). Slots are scarce and permanent, so **each beast becomes a specialised thing** rather than a generic settlement.

### Balance flags
- **Death spiral risk is severe.** The two-strike rule mitigates it; add **juvenile beasts travelling with the horde as a buffer**, so an early loss is survivable.
- **Map recovery-time headroom must be decided early.** Set the province recovery rate so a long campaign does not leave them grazing a continent of dead ground. This single number defines their entire late game.

### Interlocks
| Touches | Via |
|---|---|
| **Every settled faction** | Symmetric grazing/suppression — mutual economic grievance without aggression |
| **Ivoryscar** | Crystal veins beneath desert provinces; innocent transgressors |
| **Thunderswarm** | Both hold Raze access; compatible interests in unsettled land |
| **Skulloath (Old Ways)** | Alignment-gated non-aggression available |
| **Gladehost** | Adjacent but distinct: Gladehost oppose settlement ideologically, Shardhorde materially |

---

## Part 10: Gladehost — ACCEPTED

**Fantasy:** Japanese-Celtic hybrid forest humans and dryads, in negotiated relationship with a landscape that has opinions. Their concern is balance — and for them balance is **internal**, not a grievance against other people's buildings.

### Design constraints observed
- **No balance bar.** A two-pole meter would read as Skulloath with trees.
- **No mushroom/rot-empire theming.** That belongs to Tainted Jade.
- **No global council or mask rotation.** *(Cut — superseded by per-grove dedication, which creates the same tension spatially. One less faction screen to build.)*
- **No forest-maturation route to groves.** *(Cut — would interfere with settlement density and add complexity.)*

### The Four Aspects
The faction's supernatural identity is distributed **spatially, per grove**, not toggled globally.

| Aspect | Terrain it spreads | Projects onto surrounding land |
|---|---|---|
| **Green Man** | Deep woodland | Aggressive overgrowth, healing, accelerated settlement absorption |
| **Drowned Woman** | Wetland and marsh | Rivers rise, roads break, sieges fail; everything in it slowly rots |
| **Stag** | Open heath and meadow | Fast movement, ambush bonuses, replenishment — mustering ground |
| **Crone** | Moor, mist, barrow-country | Enemy armies lose their way, take attrition, arrive at the wrong province |

**Two of the four are not forest.** A faction of balance that produced only one terrain would not be balancing anything.

### Balance without a meter (two layers, both spatial)

**Layer 1 — Development vs. Harmony, inside their own borders.** Holts generate Development; groves generate Harmony; the faction needs both. Development suppresses Harmony, so a Holt-heavy Gladehost strangles its own groves and a grove-heavy one has no economy. **This is their inward balance, and it requires no additional system** — it is just Land State applied to themselves. They are the only faction that must manage both ends of that axis deliberately.

**Layer 2 — terrain diversity, as an economic constraint.** Each aspect terrain yields **different resources and supports different units**, so **no single terrain can sustain the faction.** A Gladehost empire must be a patchwork.

Both layers make balance a **spatial engineering problem** rather than a meter creeping toward a penalty. The player composes a landscape; they are not avoiding punishment.

### Groves
**Groves are planted at ruins** — Small Ruins by preference, Large Ruins where available (Substrate §2). This is their only grove-seeding route.

- Aspect is chosen **at the moment of planting** and permanently reshapes the land around it.
- Groves have **no economy and no building slots.** They do two jobs: **project their aspect's effect** on surrounding land, and **spread their aspect's terrain** outward into adjacent provinces within a radius.
- **Destroying a grove costs the player twice** — the terrain advantage *and* the growth in that direction. This is what makes groves worth attacking, and it is the faction's counterplay.
- **Overlap rule: nearest grove wins** per province. Simple to implement, and it makes placement a real puzzle — a badly placed Green Man grove overwrites the Crone defences you wanted on that approach.
- **Re-dedication is possible but slow:** a ritual lasting several turns during which the grove projects nothing. Adaptability without becoming a toggle.
- **On capture:** terrain already spread **stays** (you cannot un-flood a marsh); growth and projection stop. Taking a grove **freezes** Gladehost territory rather than reversing it, and the landscape keeps the scar.

**Ruins are finite and contested, so Gladehost must go and take them.** This solves the proactivity problem outright — no sitting in the woods. It also puts them in direct competition with Tainted Jade and Sunblessed for the same sites.

**Economics still work at low grove counts:** ruins are the **seed** count, terrain spread is the **growth**. Five groves still expand outward indefinitely. Scarcity limits how many aspects and how many directions can be projected, not how large the faction can become.

### Settlements: Holts
Conventional settlements with building slots, economy, growth, and garrisons. Forest humans farm clearings, log sustainably, and trade.

- Gives Gladehost a **normal economic loop** to fall back on — after Ivoryscar, Cinderguard, Sunblessed and Shardhorde, the roster does not need a fifth exotic territorial model. The aspects carry their distinctiveness.
- **Absorbed enemy settlements become Holts.** A settlement fully swallowed by spreading terrain is **absorbed rather than razed** — lore-clean, since their people are forest humans as well as dryads. The town does not die; it changes what it is.
- Holts yield less than comparable cities; the spread wild terrain itself generates income scaled by extent and age.

### Recruitment
| Source | Roster |
|---|---|
| **Holts** | Human roster — hunters, spearmen, wardens, riders. Always available, reliable, aspect-independent |
| **Groves** | Supernatural roster, **specific to that grove's aspect**. Stag: fast cavalry, beasts, ambushers. Crone: hexes, crows, unmaking. Green Man: treemen, regenerating growth. Drowned Woman: rot, plagues, drowned things |

Army composition is layered by **where the player has planted**, not by a global mode — so the roster is read off the map like everything else in this faction.

### Distinctness from neighbouring designs
| Faction | Relationship to land |
|---|---|
| **Thunderswarm** | Burn land **empty** for nests |
| **Shardhorde** | **Temporarily strip** land and move on |
| **Gladehost** | **Permanently convert** land and keep what lives on it |

### Interlocks
| Touches | Via |
|---|---|
| **Tainted Jade / Sunblessed** | Three-way contest over the same finite ruins, for three incompatible purposes |
| **Skulloath (demonic)** | Corruption emission degrades their terrain and Harmony |
| **Empire** | Spreading terrain consumes farmland — direct economic pressure; roads cut through projected terrain |
| **Thunderswarm** | Shared interest in unsettled land; compatible rewilding goals |
| **Everyone** | Absorbed settlements are lost without being razed |

---

## Part 11: Moonspear — ACCEPTED

**Fantasy:** the moon goddess gathers the souls of her loyal followers and sets them into suits of armour to serve again. Crusader-themed, but the crusade is armed by the patient dead rather than by levies.

### Dual constraint (the faction's spine)
Two resources, produced by **opposite playstyles**, and neither alone fields an army:

| Resource | Source | Playstyle |
|---|---|---|
| **Souls** | Moon temples, passively over time | Patience, holding ground, long tenure |
| **Moonsilver** | Conquest of oracle-marked cities (plus a trickle from economic buildings) | Aggression, directed war |

**Balance is enforced by the economy, not by a meter** — the same structural trick used for Gladehost. A Moonspear player can neither turtle piously nor pure-rush; they must alternate.

### Temples (souls)
**Moon temples are raised on ruins** (see Substrate §6).

- **Soul output scales with how long the temple has stood.** Temples are long-term holdings, not seeds to plant and forget.
- **Famine and war *near* a temple sharply increase soul yield.**
- **Resulting tension: you want catastrophe near your temples, never on them.** Moonspear are incentivised to plant at the edge of other people's disasters and then defend that ground hard. The player reads the map for where the next war will be and builds just outside it.

### Moonsilver (arming the souls)
Souls are inert without armour; **moonsilver is what arms them.**

- **Small amounts** from economic buildings — a slow floor that lets a peaceful player arm gradually.
- **Large amounts** from capturing **cities marked by the oracle**.

### The Oracle's Mark
The goddess names a city. This is the faction's proactivity engine, and it names targets **the player would not otherwise pick** — some inconvenient, some belonging to current friends.

- **The mark is public.** Everyone sees which city has been named — same predictability-as-gameplay principle as the lunar calendar and Tainted Jade's quota dates. The marked faction knows it has a fixed window and may garrison, ally, or evacuate.
- **The mark can be bought off in moonsilver tribute.** Moonspear become a shakedown power with a real diplomatic dimension: take the city, or take the payment. Their conquest mechanic has a peaceful resolution that is still profitable.
- **Refusing the oracle entirely** costs faith and delays the next mark. Possible, but expensive.
- Capturing a marked city yields a one-time large moonsilver payout; the city is thereafter ordinary.

### Crusades
Declared **only at full moon** against a named target (Calendar consumer, Substrate §3). Grant faction-wide zeal.

**Crusades bind:** no peace with the target until the objective is met. They are commitments, not buffs — the aggressive lever, not the default state.

### Territorial model
**Conventional settlement faction.** The roster needs settled baselines after Ivoryscar, Cinderguard, Sunblessed, Shardhorde and Thunderswarm.

### Faction screen: the Reliquary
Souls held, moonsilver stock, revenants awaiting forging, temple ages and yields, and the oracle's current mark with its countdown — with the moon phase running across the top.

Build-order question: **few elite revenants or many common ones.**

### Interlocks
| Touches | Via |
|---|---|
| **Tainted Jade** | Sanctity inversion makes them a standing crusade target; Moonspear hold the **desecration** verb against Tainted Jade shrines |
| **Tainted Jade / Sunblessed / Gladehost** | Four-way contest for the same finite ruins |
| **Skulloath (demonic), The Forsaken** | Natural crusade targets; the roster's designated hammer against the evil bloc |
| **Ivoryscar** | Cheap tomb-sealing with bonus Sanctity |
| **Everyone** | Wars and famines anywhere near a moon temple feed its harvest |

### Open flag: ruin density is now first-order
**Four factions seed core mechanics from ruins** — Tainted Jade, Sunblessed, Gladehost, Moonspear — plus universal city-rebuilding on top. This makes the ruins map effectively **the strategic map**.

This is either the best thing in the design or a bottleneck, depending entirely on **how many ruins the map carries and how they are distributed.** Ruin density and placement has moved from a tuning detail to a design decision needing its own dedicated pass.

---

## Part 12: The Forsaken — ACCEPTED

**Fantasy:** exiled vampire and necromancer aristocrats — Roman decadence crossed with Persian court life. They lost their country and kept their manners. They live in other people's provinces as invited guests, and the province rots around them.

### The Corruption faction (fills a substrate gap)
Prior to this design, **Corruption had one emitter (demonic Skulloath) and one reader (Gladehost).** The Forsaken are built to make that axis load-bearing.

### Estates: the baroque necropolis
Their core mechanic and their only real footprint. **Estates are planted on ruins only** (Substrate §6) — no invitation or consent mechanic.

An estate is a **decaying palace above and catacombs below**: courtly rot on the surface, a charnel warren underneath. It **projects happiness and Corruption into the surrounding provinces**, whether the neighbour likes it or not.

### Reach (not troop movement)
**Forsaken armies do not travel underground.** Instead an estate's catacombs **connect to whatever underground already exists nearby** — city sewers, old crypts, burial vaults, and **Ivoryscar necropolises**. This grants the estate **reach** into nearby settlements.

Reach enables:
- **Sabotage and manipulation** of the settlements within it
- **Accelerated Corruption** spread into those provinces

**Clean split from Ivoryscar:** *Ivoryscar dig, build, and travel their own tunnels. The Forsaken infest tunnels other people dug and use them to reach in, not to move through.* Construction versus infestation — the guardians of the orderly dead against the things living in the walls. (Deliberately avoids duplicating Ivoryscar's Deep Roads or Cinderguard's beacon mobility.)

### The Undead Incursion
**The payoff that makes Corruption worth spreading.** Once a settlement's Corruption is high enough, the Forsaken may trigger an incursion: **the city's own necropolises open and its own dead rise inside the walls**, spawning a hostile undead army *within* the settlement.

- **No siege and no approach march.** The war starts in the middle of the target.
- The estate is therefore **a siege engine with a forty-turn fuse**.
- The player's real decision is **timing**: every turn of delay raises Corruption and makes the incursion larger, and brings them one turn closer to being discovered.

**The incursion army is uncontrolled and purely destructive.** The Forsaken do not command it.

- It **guts the settlement's defences**, which then take multiple turns to repair even if the assault is beaten off.
- If it **captures the city**, that city is thereafter **easier for the Forsaken to take** than it would have been under its original owner.

### The Risen (emergent crisis faction)
**Once feral undead hold a city, they become an actual faction.**

- **No diplomacy of any kind.** They do not treat, tribute, or ally. They spread and consume.
- **Aggression priority:** the city's original owner first, then nearby non-Forsaken powers.
- **They ignore the Forsaken only while easier prey exists.** If the Forsaken become the last living power of consequence, the wave turns on them.

**This restores an endgame crisis to the design** — the role vacated when the Black Pyramid seal system was cut — except **emergent and player-caused rather than scripted.** The apocalypse has an author sitting at the table.

**Corruption is their metabolism.** Risen armies replenish freely in corrupted provinces and **attrit steadily in clean ones.**

- The wave surges through rotten land and **stalls at the edge of healthy territory.**
- **Containment becomes a real strategy** rather than a body count: cleanse the ground behind them and the wave starves.
- Gives Moonspear, Sunblessed and Gladehost a concrete role in the crisis beyond fighting harder.
- Lets the Forsaken **feed the plague** by seeding Corruption ahead of its advance.

**Growth scales with cities taken but must decelerate.** The first city falling should be genuinely alarming; the curve has to flatten or a mid-game incursion eats the map before anyone can respond. Corruption-gating handles most of this naturally — they expand only as fast as the rot spreads.

**Why factions must take incursions seriously:** a peasant rebellion costs one city. The Risen try to become a wave that sweeps the land.

**Self-limiter for the Forsaken (important):** their estates harvest **living** populations, and a dead province yields nothing. A runaway wave destroys their own economy — the parasite kills its host. A Forsaken player must therefore trigger incursions **surgically**: enough to cripple rivals, never enough to turn the continent into a corpse. This removes the degenerate "spam incursions everywhere" line without needing a cooldown.

**Implementation note:** this is a rebel-spawn system upgraded to a persistent faction, not a new subsystem. Reuse whatever handles rebellion armies; add faction identity, settlement ownership, and Corruption-driven replenishment.

**Two harvest modes, cleanly split:**
| Mode | Trigger | Yield |
|---|---|---|
| **Passive drip** | Province rotting under high Corruption | Steady undead levies from the dying |
| **Burst** | Player triggers an incursion | An army inside an enemy city, and the city gutted |

### Stealth and detection
Stealth is load-bearing for the whole design — reach and incursions only work if the source is not obvious.

- **Estates and Forsaken armies are invisible at range.**
- **Revealed by:** an army in or adjacent to the province, or proximity to a settlement the observer owns with sufficient control.
- **Naturally better at seeing them:** Moonspear and Sunblessed (sanctity powers), and Ivoryscar (they know their own tunnels).

**The counterplay is built in: the estate is hidden, but the Corruption is not.** A player watching a border province rot on the overlay knows something is wrong and must go and find it. The tell is real, visible, and **ambiguous** — Corruption could equally be Skulloath. **Investigation is the counter**, which is exactly right against a faction of hidden parasites.

### The trap: happiness now, Corruption later
- **Happiness arrives immediately and stays flat.** Neighbouring provinces see a clear, instant benefit and **tolerate** the estate rather than consenting to it.
- **Corruption accumulates slowly and its penalties compound:** control loss, yield decay, and eventually population dying off.
- **The estate is net-positive for a long stretch and then quietly is not.** By the time it turns, the damage is structural.

**Eviction means taking the ruin by force.** There is no polite way to ask them to leave. A province that has quietly enjoyed the happiness bonus for forty turns must go to war to stop the rot — and by then the Corruption is already in the ground.

**Corruption persists after the estate is destroyed.** The trap is not a reversible experiment. **The Forsaken always come out ahead; the only question is by how much.**

### The Court
**The undead twist is the engine:** a human court resolves itself — people die, grudges lapse, factions age out. Theirs never does. Nobody leaves, nobody forgets, and every slight is permanent.

**Structure:** many named aristocrats, **few high seats**. Each aristocrat holds an estate.

- **Ambition** accumulates per aristocrat over time — faster if their estate is old and rich, faster still if they have been passed over for a seat.
- **Seats grant real faction-wide bonuses**, so the player wants them filled by their strongest aristocrats — who are also the ones who become dangerous fastest.
- **High-Ambition aristocrats scheme:** siphoning estate income, sabotaging rivals' estates, feeding intelligence to enemies, and at the top end attempting to displace the player outright.

**Every tool costs something:**

| Tool | Effect | Cost |
|---|---|---|
| **Promote** | Buys peace now | A stronger rival later |
| **Indulge** | Suppresses Ambition with luxuries | Ongoing drain |
| **Set two against each other** | Suppresses both; eventually one dies | The survivor **absorbs the loser's estate** and becomes considerably more dangerous |
| **Destroy** | Removes the aristocrat | **Closes their estate permanently**, and — since everyone remembers forever — **raises Ambition across the entire court.** Purges compound rather than clear the air |

**Steady state:** the court grows stronger and more dangerous in lockstep with the empire. The only way to relieve pressure is to give ambitious immortals more to do — new estates, new seats — which is the same as growing the problem. Perfectly in character for a decadent aristocracy in exile.

**Distinct from the cut Skulloath system:** that was alignment divergence causing army splits. This is court politics causing resource drain and sabotage, with **no army-loyalty layer**.

**Counterplay:** killing an aristocrat closes their estate. Enemies **hunt courtiers** rather than sieging cities.

### Harvest: population into army
Their army comes from other factions' populations — extracted over decades from neighbours who were glad of the arrangement, and then all at once when an incursion is triggered. No captives, no ritual quotas, no corpse-following. (Both modes tabulated above.)

### Contrast with Sunblessed (deliberate mirror)
| | Sunblessed | Forsaken |
|---|---|---|
| Lever on happiness | **None** — they cannot touch it | **Raise it actively**, masking the decline |
| What they give | Income and research | Contentment |
| What they take | The city, when its owner fails it | The land itself, and its dead |
| Removal | Expel the Processions | **Take the ruin by force** |
| Posture | Patient beneficiary | A debt you are paid to accept |

### Cut
- **Separate blood upkeep.** The estates *are* the feeding mechanism.
- **Generational character-hook / heir-inheritance intrigue.** Too slow, too little map interaction.
- **Invited estates inside living provinces.** Ruins only.

### Territorial model
A small decadent core they actually hold, plus a scatter of estates across other factions' provinces. Their economy is **extraction and luxury rather than production** — they do not build much, they take.

### Interlocks
| Touches | Via |
|---|---|
| **Gladehost** | Corruption degrades terrain and Harmony — their estates are a slow attack on Gladehost's entire premise |
| **Skulloath** | The other Corruption emitter; compatible methods, opposed temperaments (one corrupts by existing, one by seducing) |
| **Ivoryscar** | Necromancy on pharaonic dead; captive trade; **Ivoryscar necropolises extend Forsaken reach** wherever the two overlap — guardians of the orderly dead against the things living in the walls. Ivoryscar also see through their stealth |
| **Moonspear** | Natural crusade target |
| **Empire, and any settled power** | Estates on nearby ruins; the happiness bonus is most tempting exactly where control is weakest, and removing one requires war |
| **Sunblessed** | Direct competitors for the same struggling provinces, offering opposite bargains |

---

## Part 13: Ruin Density and Distribution — DIRECTIONAL

### The central point: ruins are produced, not fixed
Razing creates ruins. **Shardhorde, Thunderswarm, Tainted Jade, and demonic-endpoint Skulloath continuously manufacture the resource that six other factions depend on.**

- Starting density can therefore be **lower than the sum of everyone's needs**, because supply grows across the campaign.
- **A peaceful map starves the ruin factions; a violent one enriches them.** Useful global pressure, and an unplanned dependency web worth preserving.
- **No hard cap and no permanent starvation** — a faction denied ruins early can still be fed by someone else's war later.

### Two tiers
| Tier | Character |
|---|---|
| **Great Ruins** | Few. Named, individually designed, high yield, concentrated in the fallen empire's heartland. **Permanent contention points.** |
| **Lesser Ruins** | Many. Generic, scattered, lower yield. The working supply. |

Tiering lets **overall density stay high enough to sustain six factions while contention concentrates on a small number of named sites.** Without it, either the map is starved or nothing is worth fighting over.

**Ruins created by razing are Lesser Ruins.** Great Ruins cannot be manufactured.

### Distribution principles
- **The old empire's heartland is the ruins belt** — dense, Great Ruin-heavy, and the contested middle of the map.
- **Tainted Jade start ruin-rich**, inside that belt. It is their homeland and their early game.
- **Gladehost, Moonspear, Sunblessed, and The Forsaken start ruin-poor** and must go and take more. Deliberate: it produces **outward pressure from turn one for four factions**, which is what makes each of them proactive rather than passive.
- **Those four must be geographically separated at start** so they do not all collide in the opening act. They should converge on the belt in the mid-game.
- **Scattered Lesser Ruins in wilderness and frontier regions** give the ruin factions viable early targets outside the belt.
- **Some ruins sit beneath or beside existing cities**, mirroring the Ivoryscar tomb precedent — taking them means war with a settled power.

### Expected campaign arc
| Phase | Ruin supply |
|---|---|
| Early | Scarce outside the belt; four factions expanding hard toward it |
| Mid | The belt contested by everyone at once; razing begins adding supply |
| Late | Supply dominated by **manufactured** ruins from ongoing wars; Great Ruins have changed hands repeatedly |

### Open sub-questions
- Should Great Ruins carry **unique named effects** per faction verb (a Great Ruin grove vs. a Great Ruin estate), or only scaled-up generic ones? Unique is far better and is also a large bespoke-content commitment.
- Does a **rebuilt city** on a ruin site destroy the site permanently, or can it be razed back into a usable ruin? Leaning: razed back — keeps sites permanently contested and reinforces the produced-resource model.
- Do the four ruin-hungry factions need a **fallback income** for campaigns where they are boxed out early? Probably yes for Moonspear and Gladehost, whose economies key off ruin-seeded structures.

---

## Part 14: Coverage Matrix — ACCEPTED

Two hard requirements, enforced across the roster: **every faction reads or writes Land State, and every faction has a ruin verb.** A faction failing either is a faction that does not touch the world.

### Land State

| Faction | Writes | Reads |
|---|---|---|
| **Skulloath** | **Corruption** (demonic endpoint, emitted by armies) | — |
| **Ivoryscar** | Suppresses Development (Silence of the Sands) | **Development** — Vigil scales inversely with disturbance and Development |
| **Thunderswarm** | **Harmony** up / **Development** down, via razing in nesting territory | **Development** in nesting grounds → Wrath |
| **Cinderguard** | **Development** (Watchforts and protected settlements) | — |
| **Tainted Jade** | **Sanctity** → corrupted variant, via consecration | Sanctity |
| **Empire** | **Development** (the roster's primary generator) | Development (Integration) |
| **The Forsaken** | **Corruption** (estates) | Corruption — high Corruption converts population into undead levies |
| **Sunblessed** | **Sanctity** (shrines and Processions) | — |
| **Shardhorde** | **Development** down, **Harmony** slowly up (grazing tramples infrastructure; land goes wild behind them) | Harmony — beast yields and growth scale with it |
| **Gladehost** | **Harmony** (groves and spread terrain) *and* **Development** (Holts) | Both — their internal balance |
| **Moonspear** | **Sanctity** (moon temples) | Sanctity |

**Gladehost's inward balance falls out of this for free:** Holts generate Development, groves generate Harmony, and the faction needs both. The balancing act happens inside their own borders with no additional system.

**Corruption is now properly load-bearing** with two emitters (Skulloath, Forsaken) using opposite methods, and multiple sufferers.

### Ruin verbs

| Faction | Verb | Site type | Effect |
|---|---|---|---|
| **Empire** | **Rebuild** (best in game) | Large | City, integrated faster than anyone can manage |
| **Tainted Jade** | **Rebuild** *or* **Consecrate** | Large / Small | City, or Life-goddess shrine yielding undead levies |
| **Sunblessed** | **Sanctify** | Small (Large possible) | Shrine: Sanctity, Procession waypoint, holds Gratitude |
| **Gladehost** | **Plant grove** | Small (Large possible) | Aspect grove: projects effect, spreads terrain |
| **Moonspear** | **Raise moon temple** | Small (Large possible) | Souls, scaling with temple age and nearby suffering |
| **The Forsaken** | **Found estate** (baroque necropolis) | Small (Large possible) | Happiness out, Corruption in; harvests the dying; **projects reach into nearby settlements and enables undead incursions** |
| **Cinderguard** | **Build Watchfort** | Large / Small | Fortifying the wreckage of the frontier they refused to abandon |
| **Ivoryscar** | **Consecrate necropolis** | Small (Large possible) | Deep Roads node, small sleeper stock, natron. The unburied dead of a ruined city, put in order |
| **Skulloath** | **Defile** | Small | Cheap, destructive; denies the site to everyone and pumps Corruption |
| **Thunderswarm** | **Raise eyrie** | Small, in nesting territory | Additional brood capacity |
| **Shardhorde** | **Calving ground** | Small — **temporary, non-permanent claim** | Accelerated beast growth while the herd remains. Nomads use sites; they do not hold them |
| **Most factions** | **Desecrate** | Any repurposed site | Reverts to plain ruin, strips the holder's benefit |

**Note the verb *shapes* differ, not just their outputs.** Skulloath **deny** sites, Shardhorde **borrow** them temporarily, Ivoryscar and the Forsaken **network** them, Cinderguard **fortify** them, the rest **hold** them. That variety is what stops the ruin layer becoming eleven flavours of the same claim action.

**Shrines block settlement.** A Large Ruin carrying any shrine-type structure **cannot be rebuilt into a city until that structure is destroyed.** Consequence: the shrine factions can deliberately deny city sites to settlers, which is a strategic weapon well beyond their own economies — planting on a Large Ruin is both a claim and a veto.
All eleven factions specified, on seven shared substrate systems.

**Open design question (not tuning):**
- **Tiering.** Eleven fully bespoke mechanic suites is trilogy-scale. Confirm which factions ship as flagships and which get lighter variations of the shared substrate.

**Deliberately out of scope for this document:** balance figures, pacing targets, yields, thresholds, and counts. This is a directional paper — those belong in tuning passes once systems exist and can be played.
