# Polish Pass 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four quick wins from the roadmap: a faction-onboarding intro panel, a victory-progress panel with a reworked (reachable) Shard Ascension condition, an honest income-breakdown tooltip driven by the real income pipeline, and housekeeping (dead battle scenes deleted, shard_guardians AI turns skipped, typed-array load error fixed, battle baselines deliberately regenerated).

**Architecture:** Content-heavy pieces (faction intros) live in a new static data file; the two new panels reuse the auto-height centered-dialog factory and dark-chip conventions in `campaign_hud.gd`. Shard Ascension becomes a cumulative `shards_spent` counter incremented at every true shard-consumption sink. The breakdown refactor deletes the hand-copied income math and derives the tooltip from `calculate_city_income` plus labeled deltas.

**Tech Stack:** Godot 4.4 GDScript, headless SceneTree tests, windowed screenshot harness for scene-script verification.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; tests `& "<godot>" --headless --path . -s res://tests/<name>.gd`; startup "SCRIPT ERROR: Compile Error" noise benign — only printed PASSED/FAILED verdicts count; autoloads via `root.get_node`; every test `new_game` call pins `map_seed` (0 unless variance is the point).
- Scene scripts (`campaign_hud.gd`, `campaign.gd`) compile only when the scene loads — verify via windowed `tests/tmp_screenshot_windows.gd` run; stdout must not name them in SCRIPT ERRORs.
- UI: text never sits on raw leather (dark chips); new dialogs use `_create_centered_dialog(width[, min_height])` (auto-height); tooltips clamp below the TopBar.
- Save compat: new GameState/FactionState fields are `@export` with defaults; old saves must load.
- Task 5 DELIBERATELY regenerates `tests/baselines/` (user-authorized via roadmap item "make the deliberate re-baseline decision") — this is the ONLY task ever allowed to do so, and it must document the rationale in the commit message.
- FOREGROUND commands only in all dispatches — never Monitor/background waits.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Faction onboarding panel

**Files:**
- Create: `scripts/data/faction_intro_data.gd`
- Modify: `scenes/campaign/campaign_hud.gd` (show-once panel at campaign start)
- Modify: `scripts/core/game_state.gd` (`@export var faction_intro_shown: bool = false`)
- Test: `tests/test_polish_pass.gd` (new)

**Interfaces:**
- Produces: `FactionIntroData.INTROS: Dictionary` (faction_id → `{title: String, mechanic: String, dilemma: String, resource: String, opening: String}`); `campaign_hud._show_faction_intro()` (called from `_ready` when `not GameManager.state.faction_intro_shown`).

- [ ] **Step 1: Write the failing test** — create `tests/test_polish_pass.gd`:

```gdscript
extends SceneTree
## Tests for Polish Pass 1 (faction intros, shard ascension, breakdown honesty).
## Run: godot --headless --path . -s res://tests/test_polish_pass.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)

	# ── Faction intros: every playable faction has complete content ──
	for fid in _gm.state.faction_states:
		var fd: FactionData = root.get_node("/root/DataManager").get_faction(fid)
		if fd == null or not fd.is_playable:
			continue
		var intro: Dictionary = FactionIntroData.INTROS.get(fid, {})
		_check(not intro.is_empty(), "intro exists for %s" % fid)
		for key in ["title", "mechanic", "dilemma", "resource", "opening"]:
			_check(intro.get(key, "") != "", "intro.%s non-empty for %s" % [key, fid])
	_check(not _gm.state.faction_intro_shown, "intro flag starts false")

	if _fails == 0:
		print("POLISH TEST PASSED")
		quit(0)
	else:
		print("POLISH TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
```

- [ ] **Step 2: Run — parse failure (FactionIntroData missing).**

- [ ] **Step 3: Create `scripts/data/faction_intro_data.gd`** — full content, verified against the mechanics in `turn_manager.gd` (magnitudes may be paraphrased, not invented):

```gdscript
class_name FactionIntroData
extends RefCounted
## One-screen onboarding blurb per playable faction, shown once at campaign
## start. Content mirrors the actual mechanics in turn_manager.gd.

const INTROS := {
	&"empire": {
		title = "The Empire — Stable Hegemon",
		mechanic = "Imperial Authority (0-100) rises with territory, cultural buildings and a tech lead. At 75+ your treasury and diplomacy flourish; below 25 your cities slide toward crisis.",
		dilemma = "Every 5 turns the Senate offers an Edict: Military (+attack), Economic (+gold), Cultural (+loyalty) or Diplomatic (+standing). Senate policies and class politics are yours alone to manage.",
		resource = "Affinity resource: Saffron Reeds (+trade gold). Your legions favor heavy infantry and disciplined lines.",
		opening = "Expand steadily, keep Authority high, and pivot Edicts to match the moment. Watch your class loyalties in the Senate.",
	},
	&"skulloath": {
		title = "Skulloath — The Corruption Path",
		mechanic = "Corruption (0-100) is a slider between two identities: stay Pure (≤20) for loyalty, food and defense, or embrace the demonic (61+) for up to +30% attack and captive-fueled industry.",
		dilemma = "Every 4 turns the Dark Bargain lets you push either way: sacrifice captives to rise, spend gold on rites to fall, or walk the line for technology.",
		resource = "Affinity resource: Bloodsalt (+captive conversion). Your roster is fast raider cavalry — hit, take captives, vanish.",
		opening = "Pick your path early. Captives are fuel either way — raid often.",
	},
	&"gladehost": {
		title = "Gladehost — Harmony and the Seasons",
		mechanic = "Harmony (0-100) multiplies your seasonal income — but over-building drains it. Spring feeds, Summer arms, Autumn enriches, Winter tests you.",
		dilemma = "Each season change offers a Festival: feast for harmony, toil for resources, or rest quietly.",
		resource = "Affinity resource: Heartwood (+food). Wood-hungry defensive roster with healing and armor auras.",
		opening = "Build LESS than you think you should. Hold forests, ride the seasons, let attackers break on your groves.",
	},
	&"moonspear": {
		title = "Moonspear — The Lunar Cycle",
		mechanic = "The moon cycles every 4 turns: New Moon sharpens attack, Waxing hastens marches, Full Moon hardens defense, Waning mends wounds. Your ethereal soldiers dodge blows but carry less flesh.",
		dilemma = "At each phase change you may pay to extend a favorable moon or rush past a poor one.",
		resource = "Affinity resource: Moonsilver (-heavy recruit cost). Silver knights and lunar archers reward timing your wars to the sky.",
		opening = "Attack under the New Moon, defend under the Full. Extend the phase that matches your plan.",
	},
	&"sunblessed": {
		title = "Sunblessed — Faith and Wisdom",
		mechanic = "Solar Faith (0-100) grows as your armies walk among foreign cities and blesses your blades at 70+. Wisdom (0-200) accumulates near allies, feeding technology and speeding research.",
		dilemma = "At overflowing Faith (85+), proclaim a Golden Age for a burst of gold and knowledge — or convert zeal into Wisdom.",
		resource = "Affinity resource: Sunstone (+cultural income). A ranged-heavy zealot host with holy beasts.",
		opening = "March pilgrims beside friendly cities in peacetime — faith and wisdom flow from proximity, not conquest.",
	},
	&"shardhorde": {
		title = "Shardhorde — The Devouring Swarm",
		mechanic = "No settlements — your elderbeasts ARE your home. Consume claimed shards for 6-turn realm resonances: iron, gold, food, tech or healing depending on the shard's realm.",
		dilemma = "Manage your Shard Reserve: every crystal eaten is power now instead of research later.",
		resource = "Affinity resource: Shardglass (+arcane research). Giant monsters with double everyone's hit points.",
		opening = "Chase shardfalls relentlessly. Time your consumption windows to your offensives.",
	},
	&"thunderswarm": {
		title = "Thunderswarm — Ride the Fury",
		mechanic = "Storm Fury (0-100) builds from battle and mountain camps, decaying in idleness. High fury electrifies your attacks (+22% at 80).",
		dilemma = "Every 3 turns at 35+ fury, spend it: Storm March (+movement), Thunder Wall (city shield) or Tempest Harvest (resources).",
		resource = "Affinity resource: Stormcrystal (+army speed). Fast fliers and lightning callers built for momentum.",
		opening = "Never stop moving. Fury feeds on war and starves in peace.",
	},
	&"cinderguard": {
		title = "Cinderguard — The Border Forge",
		mechanic = "Border Vigilance swings between Fortress mode (low: +20% defense, thriving settlements) and War Forge (high: +15% attack, iron flowing). Dragon raids strike your settlements every few turns — survive them and grow harder.",
		dilemma = "Frontier Orders every 4 turns shift your posture or raise border fortresses from scavenged scrap.",
		resource = "Affinity resource: Deepiron (+home defense). Iron-clad desert wardens with anti-monster training.",
		opening = "Settle wide, fortify everything, and choose posture deliberately — you cannot be both anvil and hammer at once.",
	},
	&"forsaken": {
		title = "The Forsaken — Shadow Network",
		mechanic = "Your Espionage Network (0-50) grows with territory and spy dens. It reveals enemy capitals, steals gold and research, saboteurs their construction, and at its peak wounds enemy commanders.",
		dilemma = "When agents stand ready you choose the operation — and weigh the detection risk that turns all courts against you.",
		resource = "Undead swarms and fear: many cheap bodies, terrifying auras, ambush bonuses on the attack.",
		opening = "Grow the network before the war. Strike rich enemies from the shadows and let fear finish the rest.",
	},
	&"ivoryscar": {
		title = "Ivoryscar — The Black Pyramid",
		mechanic = "Relic Power flows from shard wastes and hoarded crystals, armoring your tomb legions. Feed gold, iron, essence and whole shards into the Black Pyramid — restore it fully for a permanent empire-wide ascension.",
		dilemma = "Every 5 turns choose: fund expeditions, study quietly, fortify, or invest in the Pyramid itself.",
		resource = "Affinity resource: Shardglass (+arcane research). Slow undead tanks that grind attackers to dust.",
		opening = "Turtle on the wastes, hoard shards, and build toward the Pyramid — your late game is the strongest in the world.",
	},
	&"tainted_jade": {
		title = "Tainted Jade — The Spreading Taint",
		mechanic = "Taint Power grows from processed captives and shattered shards, feeding technology and rotting enemy shards. High taint scars even your own lands.",
		dilemma = "Every 4 turns set your Focus: Verdant (growth), Venomous War (jungle combat), or Creeping Doom (decay and erosion).",
		resource = "Affinity resource: Bloodsalt (+captive conversion). Poison skirmishers strongest in jungle and swamp.",
		opening = "Fight where the jungle favors you, feed the taint with captives, and choose the Focus your era demands.",
	},
}
```

- [ ] **Step 4: Wire the panel** in `campaign_hud.gd`: `@export`/field additions none; in `_ready`, after existing setup (find where the tutorial hint check `_check_tutorial` runs and place adjacent):

```gdscript
	if not GameManager.state.faction_intro_shown:
		call_deferred("_show_faction_intro")
```

New function (place near the other dialogs):

```gdscript
func _show_faction_intro() -> void:
	var fid := GameManager.state.player_faction_id
	var intro: Dictionary = FactionIntroData.INTROS.get(fid, {})
	if intro.is_empty():
		GameManager.state.faction_intro_shown = true
		return
	var dialog := _create_centered_dialog(560)
	add_child(dialog)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	dialog.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = intro.title
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_add_separator(vbox)
	for pair in [["Your Power", intro.mechanic], ["Your Choices", intro.dilemma], ["Your Strengths", intro.resource], ["Opening Moves", intro.opening]]:
		var h := Label.new()
		h.text = pair[0]
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", Color(0.72, 0.85, 0.55))
		vbox.add_child(h)
		var b := Label.new()
		b.text = pair[1]
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(500, 0)
		vbox.add_child(b)
	var begin := Button.new()
	begin.text = "Begin Your Reign"
	begin.custom_minimum_size = Vector2(0, 36)
	begin.pressed.connect(func():
		GameManager.state.faction_intro_shown = true
		dialog.queue_free())
	vbox.add_child(begin)
```

`game_state.gd`: `@export var faction_intro_shown: bool = false` (saves keep it — loads don't re-show).

- [ ] **Step 5: Run test (POLISH TEST PASSED) + windowed harness screenshot** — extend `tests/tmp_screenshot_windows.gd` (it force-hides the intro? NO — the harness loads campaign fresh, so the intro WILL appear and could occlude other window shots; set `gm.state.faction_intro_shown = true` right after `new_game` in the EXISTING harness phases, and add ONE new phase at the start that leaves it false, screenshots `win_faction_intro.png`, then dismisses via `hud._show_faction_intro` internals — simplest: screenshot first with the intro up, then set the flag and free the dialog child before the other phases).
- [ ] **Step 6: Commit** — `feat(ui): faction onboarding panel shown once at campaign start` + footer.

---

### Task 2: Shard Ascension rework (cumulative shards spent)

**Files:**
- Modify: `scripts/core/faction_state.gd` (`@export var shards_spent: int = 0`)
- Modify: every true shard-consumption sink (grep `owned_shards.erase` across scripts/ — known sites: research_system.gd `invest_shard`, turn_manager.gd `pyramid_invest` dilemma branch + shardhorde `consume_shard_for_resonance` + tainted_jade `destroy_shard_for_taint`; cover ALL hits, incrementing the CONSUMING faction's `shards_spent`)
- Modify: `scripts/autoloads/turn_manager.gd` victory check (~:479-581): SHARD_ASCENSION fires at `fs.shards_spent >= 15` instead of holding 10 simultaneous shards
- Test: `tests/test_polish_pass.gd` (append)

**Interfaces:**
- Produces: `FactionState.shards_spent: int`; victory constant `SHARD_ASCENSION_TARGET := 15` (const in turn_manager near the victory code).

- [ ] **Step 1: Append failing test:**

```gdscript
	# ── Shard ascension counts consumption ──
	var efs: FactionState = _gm.state.faction_states[&"empire"]
	_check(efs.shards_spent == 0, "shards_spent starts 0")
	# Craft a shard and invest it in research
	var shard := ShardInstance.new()
	shard.shard_id = &"test_shard_polish"
	shard.claimed_by = &"empire"
	shard.realm = 1
	_gm.state.active_shards[shard.shard_id] = shard
	efs.owned_shards.append(shard.shard_id)
	# Start any affordable research so invest_shard has a target
	for rid in root.get_node("/root/DataManager").research:
		if _gm.research_system.start_research(&"empire", rid):
			break
	if efs.current_research_id != &"":
		var before := efs.shards_spent
		if _gm.research_system.invest_shard(&"empire", shard.shard_id):
			_check(efs.shards_spent == before + 1, "invest_shard increments shards_spent")
	_check(_gm.turn_manager_const_check() if false else true, "placeholder-free")  # remove this line; see note
```

(IMPLEMENTER NOTE: drop the last `_check` placeholder line entirely — assert instead that `TurnManager.SHARD_ASCENSION_TARGET == 15`. Read `ShardInstance`'s real field names first — `shard_id`/`claimed_by`/`realm` must match `scripts/core/shard_instance.gd`; `start_research` signature from research_system.gd.)

- [ ] **Step 2: Run — FAILs.**
- [ ] **Step 3: Implement** — field, `const SHARD_ASCENSION_TARGET := 15`, `fs.shards_spent += 1` at every `owned_shards.erase` consumption site (verify each grep hit is genuine consumption, not transfer — diplomacy `offer_shard` TRANSFERS a shard to another faction: that is NOT consumption, do not increment there; document which sites you classified as transfer vs consumption), victory check replacement:

```gdscript
	# Shard Ascension: cumulative mastery — every shard consumed by your
	# works (research, rituals, the Pyramid) counts toward transcendence
	if fs.shards_spent >= SHARD_ASCENSION_TARGET:
		_trigger_victory(faction_id, Enums.VictoryType.SHARD_ASCENSION)
```

(Anchor on the real victory-check function and its existing SHARD_ASCENSION branch — replace the held-count condition, keep the trigger idiom identical to neighbors.)

- [ ] **Step 4: Run** — POLISH TEST PASSED + `test_save_roundtrip.gd` (new field roundtrips) + `test_special_resources.gd` (pyramid/lease paths untouched).
- [ ] **Step 5: Commit** — `feat(victory): shard ascension counts cumulative shards spent` + footer.

---

### Task 3: Victory progress panel

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` — "Victory" button in the top bar (next to Economy, same `_create_economy_panel` insertion pattern) + centered panel
- Test: windowed harness phase

**Interfaces:**
- Consumes: `TurnManager.SHARD_ASCENSION_TARGET`, `fs.shards_spent`, `fs.owned_regions`, `GameManager.state.hex_map` region counts, victory-mode flags (READ the victory check in turn_manager to mirror EXACTLY which conditions are active in the current game mode — quickmatch vs sandbox — and reuse its thresholds rather than re-deriving).

- [ ] **Step 1: Panel** — button "Victory" inserted beside the Research/Economy buttons (mirror `_create_economy_panel`'s button-insertion pattern); toggling opens `_create_centered_dialog(520)` rebuilt on open:
  - One row per ACTIVE victory condition (read active-mode gating from the victory check): name, one-line description, and a `ProgressBar` (custom_minimum_size `Vector2(300, 16)`, `show_percentage = false`) with a caption "you: X / N — leader: <faction> Y".
  - Progress sources: Domination/Conquest = owned_regions vs threshold regions; Shard Ascension = `shards_spent / SHARD_ASCENSION_TARGET`; Elimination = factions defeated / total majors; Diplomatic = mirror whatever the check reads. For "leader", scan all non-NPC factions for the max of the same metric.
  - Dark chip behind content; close button via `_create_panel_header` if it fits, else the standard X pattern.
- [ ] **Step 2: Windowed harness phase** — extend `tests/tmp_screenshot_windows.gd`: open the victory panel (call its toggle), screenshot `win_victory.png`; verify no SCRIPT ERROR naming campaign_hud.gd; visually confirm bars render.
- [ ] **Step 3: Headless regression** — `test_polish_pass.gd` still PASSED (no new headless assertions needed — panel is UI-only; the metrics it reads are tested in Task 2).
- [ ] **Step 4: Commit** — `feat(ui): victory progress panel` + footer.

---

### Task 4: Honest income breakdown

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` — `_calculate_income_breakdown` (find it; it's a hand-copied snapshot of an older `_generate_income`)
- Modify: `tests/test_income_breakdown_equivalence.gd` — reference copy replaced by parity-with-reality assertions

**Interfaces:**
- Consumes: `GameManager.city_system.calculate_city_income(city)` (authoritative per-city income) and the faction-level percentage effects applied in `_generate_income` (read it: food_pct, iron_pct, culture bonuses, region completion, shard_pct, debt penalty, faction modifiers, wood reduction, heartwood...).

- [ ] **Step 1: Rework the breakdown** so every line is DERIVED, not re-implemented: per-city rows come from `calculate_city_income` directly; faction-level modifiers become labeled delta rows computed by applying the REAL helper functions where they exist, or by difference (compute the faction total with and without the modifier where the pipeline exposes no helper — e.g. run the percentage math on the summed base exactly as `_generate_income` does by CALLING shared code, not copying it). Where sharing requires extraction, extract small pure helpers from `_generate_income` into city_system (e.g. `apply_faction_income_percentages(faction_id, income: Dictionary) -> Dictionary` used by BOTH `_generate_income` and the breakdown) — the point of this task is ONE source of truth.
- [ ] **Step 2: Rework the equivalence test**: instead of a frozen reference copy, assert that the breakdown's TOTAL for each resource equals the amount `_generate_income` actually credits (capture `fs.resources` before/after one `_generate_income` call on a crafted state, compare to the breakdown's totals). This makes the test future-proof: any new income modifier automatically breaks parity until the breakdown learns it.
- [ ] **Step 3: Run** — `test_income_breakdown_equivalence.gd` PASSED (reworked), `test_bounty_system.gd`, `test_special_resources.gd`, `test_siege_pressure.gd` PASSED; windowed harness: economy panel screenshot unchanged in structure, no SCRIPT ERRORs.
- [ ] **Step 4: Commit** — `fix(ui): income breakdown derives from the real income pipeline` + footer.

---

### Task 5: Housekeeping — dead scenes, guardian skip, typed-array fix, re-baseline

**Files:**
- Delete: `scenes/battle/battle.gd`, `scenes/battle/battle.tscn`, `scripts/systems/battle/battle_simulator.gd` (V1), `scenes/battle/battle_v2.gd`, `scenes/battle/grid_renderer_v2.gd`, `scenes/battle/battle_v2.tscn` (+ their `.uid` files). KEEP `scripts/systems/battle/battle_simulator_v2.gd` (live headless auto-resolver).
- Modify: `scripts/autoloads/turn_manager.gd` — `start_game` faction_order build (~:299-303): exclude `&"shard_guardians"`; and `deserialize_state` (~:79): typed-array fix
- Regenerate: `tests/baselines/` via the determinism harness
- Test: existing suites

- [ ] **Step 1: Verify the dead files are truly dead** — grep for `battle.tscn`, `battle_v2.tscn`, `grid_renderer_v2`, and V1 `BattleSimulator` class usage (excluding the dead files themselves); expected: zero live references (prior audit found none — re-verify at HEAD). `git rm` the six files + uids.
- [ ] **Step 2: Guardian skip** — in `start_game`'s faction_order append loop, skip `&"shard_guardians"` with a comment (stationary guardian armies are map entities; a full AI turn for the pseudo-faction is wasted processing). Verify rebels/independent stay IN (they act meaningfully). Run `tmp_econ_sim.gd -- 7 15` — zero SCRIPT ERRORs, and shard guardians still exist on the map (assert via a quick check in the polish test: some army with faction_id == &"shard_guardians" exists after new_game... READ how guardians spawn first — if they spawn with shardfalls over time, assert instead that the shardfall system still functions, or skip the assertion with a note).
- [ ] **Step 3: Typed-array fix** — turn_manager.gd:79 assigns an untyped loaded Array to `Array[Dictionary]`. Fix by rebuilding typed:

```gdscript
	var loaded: Array = data.get("turn_log", [])
	turn_log.clear()
	for entry in loaded:
		if entry is Dictionary:
			turn_log.append(entry)
```

(Anchor on the real line 79 variable — read `deserialize_state` first; apply the same rebuild pattern to whichever typed array it is.)
- [ ] **Step 4: Run `test_save_roundtrip.gd`** — PASSED with ZERO runtime SCRIPT ERRORs now (the :79 error line must be gone).
- [ ] **Step 5: RE-BASELINE (deliberate)** — run `& "<godot>" --headless --path . -s res://tests/test_battle_determinism.gd -- --baseline` then the compare run → `FINGERPRINT MATCH` expected. Commit baselines separately with message documenting: baselines stale since 6bd9103 (intentional balance change AMMO_PER_ENTITY 7→5, melee_defense -30%) — this re-baseline accepts current battle behavior as the new reference; verified against pinned map_seed 0.
- [ ] **Step 6: Full battery** — test_polish_pass, test_landmarks, test_map_seed, test_special_resources, test_bounty_system, test_faction_ai_flavor, test_siege_pressure, test_save_roundtrip, test_income_breakdown_equivalence, test_battle_determinism (now MATCH), windowed tmp_screenshot_windows.
- [ ] **Step 7: Two commits** — `chore(battle): remove dead V1/V2 scenes, skip guardian pseudo-faction turns, fix typed-array load` and `test(battle): re-baseline determinism fingerprints (accepts 6bd9103 balance change)` + footers.

---

## Self-Review

- **Spec coverage:** roadmap items 1 (T1), 2 (T2+T3), 3 (T4), 4 (T5 — all four sub-items). 
- **Placeholder scan:** T2's Step-1 snippet flags its own placeholder line with explicit removal instructions and the real replacement assertion; T3 is UI-only with the windowed-harness verification pattern used in all prior phases; no TBDs remain.
- **Type consistency:** `FactionIntroData.INTROS` keys match `FactionState` faction ids; `SHARD_ASCENSION_TARGET` defined T2, consumed T3; `shards_spent` defined T2 before T3's read.
