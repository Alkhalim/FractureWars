# Bounded Siege-Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fragile "rout the garrison then hold N uninterrupted turns" siege model with an accumulating siege-pressure meter so winning battles at a city actually captures it in a bounded number of turns, and make the AI commit to its sieges.

**Architecture:** Repurpose the existing `CityState.siege_turns` field (now a float) as accumulated siege pressure, measured against the unchanged `siege_threshold`. `_process_sieges` still captures at `siege_turns >= threshold` — no new capture path. Pressure fills from garrison overruns, relief-battle outcomes, and composition-scaled blockade presence; it decays when the besieger is absent. Besieged garrisons take heavier attrition than besiegers. The AI holds sieges in progress instead of re-targeting every turn.

**Tech Stack:** Godot 4.4, GDScript. Headless SceneTree test harness (`godot --headless --path . -s res://tests/<name>.gd`).

## Global Constraints

- Godot binary (this machine): `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- All pressure/attrition constants live in `city_system.gd` as `const` — no magic numbers elsewhere. Battle code and UI read them through `city_system`.
- Single capture path: capture happens **only** in `_process_sieges`. `add_siege_pressure` and battle awards never call `_capture_city` directly (preserves the Skulloath siege-choice dialog branch).
- `siege_turns` becomes a `float`. Every `= 0` / `+= x` / `>=` site already works; the only breakages are two `maxi(...)` UI calls, fixed in Task 1.
- Do NOT regenerate `tests/baselines/` unless Task 8 confirms a real battle-simulation change. Pressure awards happen after the sim finishes and don't touch RNG, so baselines should still match.
- Terrain/Realm/ResourceType enum ints per project memory; unit `tags` and `tiles_per_entity` are the composition inputs — no `.tres` edits.

## File Structure

- `scripts/core/city_state.gd` — `siege_turns` type change (int → float).
- `scripts/systems/campaign/city_system.gd` — all pressure logic: constants, `_unit_siege_factor`, `_army_siege_weight`, `get_siege_threshold`, `add_siege_pressure`, `award_siege_overrun`, `award_siege_battle`, `_besiegers_present`, `_apply_besieger_attrition`, rewritten `_process_sieges`, `break_siege` semantics.
- `scripts/systems/battle/battle_resolver.gd` — call `award_siege_overrun` / `award_siege_battle` after a battle at a besieged hex.
- `scripts/autoloads/game_manager.gd` — `_check_siege_departure` stops force-breaking sieges.
- `scripts/autoloads/turn_manager.gd` — `_execute_ai_turn` / `_execute_skulloath_ai` siege persistence + target weighting.
- `scripts/autoloads/event_bus.gd` — `siege_progress_changed` signal.
- `scenes/campaign/campaign_hud.gd` — city-panel meter, map badge, toasts; both `maxi` fixes.
- `tests/test_siege_pressure.gd` — unit tests for Tasks 1–3, 5.
- `tests/test_siege_ai.gd` — AI persistence test for Task 6.
- `tests/tmp_screenshot_siege.gd` — UI verification for Task 7.

## Test Harness Conventions (referenced by every test task)

Every `tests/test_*.gd` file uses this exact scaffold. Task test steps show only the
`_run()` body and helpers; wrap them in this boilerplate:

```gdscript
extends SceneTree
## <one-line purpose>
## Run: godot --headless --path . -s res://tests/<name>.gd

var _fails := 0
var _gm: Node
var _dm: Node
var _cs   # city_system

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire")
	_cs = _gm.city_system

	# <task-specific assertions call _check(...)>

	if _fails == 0:
		print("SIEGE TEST PASSED")
		quit(0)
	else:
		print("SIEGE TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

# Build a detached army of the given unit ids at a hex (not registered in state).
func _make_army(fid: StringName, unit_ids: Array, hex := Vector2i(0, 0)) -> ArmyState:
	var a := ArmyState.new()
	a.army_id = &"__test_army_%d" % randi()
	a.faction_id = fid
	a.hex_pos = hex
	for uid in unit_ids:
		var ud: UnitData = _dm.get_unit(uid)
		var ui := UnitInstance.new()
		ui.init_from_data(ud, uid)
		a.units.append(ui)
	return a
```

Test unit ids used below are real data: `marching_bastion` (empire, `construct`+`heavy`+`stationary`, `tiles_per_entity`=16 → siege engine), `legionary` (empire, `infantry`+`melee` → baseline), `hawk_scout` (gladehost, `ranged`+`fast`+`light` → light).

---

### Task 1: Pressure field, constants, and pure composition/threshold helpers

**Files:**
- Modify: `scripts/core/city_state.gd:18`
- Modify: `scripts/systems/campaign/city_system.gd` (add constants + 3 helpers near the siege section, ~line 594)
- Modify: `scripts/autoloads/event_bus.gd` (add signal)
- Modify: `scenes/campaign/campaign_hud.gd:2206` and `:7736-7737` (float-safe the two `maxi` sites)
- Test: `tests/test_siege_pressure.gd`

**Interfaces:**
- Produces:
  - `CityState.siege_turns: float`
  - `CitySystem.get_siege_threshold(city: CityState) -> int`
  - `CitySystem._unit_siege_factor(ud: UnitData) -> float`
  - `CitySystem._army_siege_weight(army: ArmyState) -> float` (returns average per-unit factor; 0.0 for empty)
  - constants: `SIEGE_FILL_BASE`, `SIEGE_FACTOR_ENGINE/HEAVY/BASE/LIGHT`, `SIEGE_OVERRUN_BONUS`, `SIEGE_RELIEF_WIN`, `SIEGE_RELIEF_STALEMATE`, `SIEGE_POINTWIN_GAP`, `SIEGE_DECAY_ABSENT`, `SIEGE_RELIEF_LOSS`, `SIEGE_BESIEGER_ATTRITION`, `SIEGE_GARRISON_ATTRITION`
  - `EventBus.siege_progress_changed(city_id: StringName, pressure: float, threshold: int)`

- [ ] **Step 1: Change the field type**

In `scripts/core/city_state.gd`, line 18:

```gdscript
@export var siege_turns: float = 0.0 # Accumulated siege pressure (was an int turn counter)
```

- [ ] **Step 2: Add the EventBus signal**

In `scripts/autoloads/event_bus.gd`, alongside the other siege signals (`siege_started`, `siege_broken`):

```gdscript
signal siege_progress_changed(city_id: StringName, pressure: float, threshold: int)
```

- [ ] **Step 3: Add constants + helpers in city_system.gd**

Insert immediately **above** `func _process_sieges(faction_id: StringName) -> void:` (currently ~line 594):

```gdscript
# ── Siege pressure model ─────────────────────────────────────
# siege_turns is accumulated pressure (float) vs get_siege_threshold(city).
const SIEGE_FILL_BASE := 0.75          # infantry-army blockade fill per turn
const SIEGE_FACTOR_ENGINE := 1.8       # construct / tiles>=4 (batters walls)
const SIEGE_FACTOR_HEAVY := 1.3        # heavy / monster / beast
const SIEGE_FACTOR_BASE := 1.0         # infantry / ranged baseline
const SIEGE_FACTOR_LIGHT := 0.5        # light / fast raiders
const SIEGE_OVERRUN_BONUS := 2.0       # garrison overrun (decisive)
const SIEGE_RELIEF_WIN := 1.0          # besieger wins a relief battle on the hex
const SIEGE_RELIEF_STALEMATE := 0.4    # both survive, roughly even
const SIEGE_POINTWIN_GAP := 0.25       # strength-fraction gap that counts as a point win
const SIEGE_DECAY_ABSENT := 1.0        # drain per turn when no besieger present
const SIEGE_RELIEF_LOSS := 2.0         # drain when a relief army beats the besieger
const SIEGE_BESIEGER_ATTRITION := 0.025 # 2.5% max_hp/turn to besieging units
const SIEGE_GARRISON_ATTRITION := 0.09  # 9%/turn garrison_hp_ratio decline (besieged suffer more)

func get_siege_threshold(city: CityState) -> int:
	var t := 4
	if city.buildings.has(&"steppe_watchtower"):
		t = 5
	var parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(city.faction_id, city.faction_id)
	var eff := GameManager.research_system.get_research_effects(parent)
	var rdef: int = eff.get("defense_bonus", 0)
	var cpct: int = eff.get("city_defense_pct", 0)
	if rdef >= 5 or cpct >= 15:
		t += 1
	if rdef >= 10 or cpct >= 30:
		t += 1
	return t

func _unit_siege_factor(ud: UnitData) -> float:
	if ud == null:
		return SIEGE_FACTOR_BASE
	if ud.tags.has("construct") or ud.tiles_per_entity >= 4:
		return SIEGE_FACTOR_ENGINE
	if ud.tags.has("heavy") or ud.tags.has("monster") or ud.tags.has("beast"):
		return SIEGE_FACTOR_HEAVY
	if ud.tags.has("light") or ud.tags.has("fast"):
		return SIEGE_FACTOR_LIGHT
	return SIEGE_FACTOR_BASE

func _army_siege_weight(army: ArmyState) -> float:
	if army == null or army.units.is_empty():
		return 0.0
	var total := 0.0
	for unit in army.units:
		total += _unit_siege_factor(DataManager.get_unit(unit.unit_data_id))
	return total / float(army.units.size())
```

- [ ] **Step 4: Float-safe the two campaign_hud siege readouts**

These currently use `maxi` (int-only) on `siege_turns`. Replace to keep the project compiling; Task 7 rewrites them into the real meter.

`scenes/campaign/campaign_hud.gd:2206` — replace:

```gdscript
			var sr := maxi(0, st - city.siege_turns)
```
with:
```gdscript
			var sr := int(ceil(maxf(0.0, float(st) - city.siege_turns)))
```

`scenes/campaign/campaign_hud.gd:7736-7737` — replace:

```gdscript
		var turns_remaining := maxi(0, siege_threshold - city.siege_turns)
		siege_label.text = "UNDER SIEGE by %s (Turn %d/%d - %d remaining)" % [aname, city.siege_turns, siege_threshold, turns_remaining]
```
with:
```gdscript
		var turns_remaining := int(ceil(maxf(0.0, float(siege_threshold) - city.siege_turns)))
		siege_label.text = "UNDER SIEGE by %s (%d/%d - %d remaining)" % [aname, int(city.siege_turns), siege_threshold, turns_remaining]
```

- [ ] **Step 5: Write the failing test**

Create `tests/test_siege_pressure.gd` using the standard scaffold. `_run()` body:

```gdscript
	# Composition ordering: siege engine > baseline infantry > light raider
	var w_engine := _cs._army_siege_weight(_make_army(&"empire", [&"marching_bastion"]))
	var w_base := _cs._army_siege_weight(_make_army(&"empire", [&"legionary"]))
	var w_light := _cs._army_siege_weight(_make_army(&"gladehost", [&"hawk_scout"]))
	_check(w_engine > w_base, "engine weight > baseline (%f > %f)" % [w_engine, w_base])
	_check(w_base > w_light, "baseline weight > light (%f > %f)" % [w_base, w_light])
	_check(abs(w_base - _cs.SIEGE_FACTOR_BASE) < 0.001, "infantry weight == base factor")
	_check(_cs._army_siege_weight(_make_army(&"empire", [])) == 0.0, "empty army weight is 0")

	# Threshold on a fresh empire city is the base 4 (no watchtower, no def research)
	var any_city: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			any_city = c
			break
	_check(any_city != null, "found an empire city")
	_check(_cs.get_siege_threshold(any_city) == 4, "base siege threshold is 4")
```

- [ ] **Step 6: Run the test — expect failure first, then pass**

Run:
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_siege_pressure.gd
```
Before Steps 1–3 this fails to compile / errors on unknown members. After them: `SIEGE TEST PASSED`.

- [ ] **Step 7: Parse-check the whole project**

Run:
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"
```
Expected: no matches.

- [ ] **Step 8: Commit**

```bash
git add scripts/core/city_state.gd scripts/systems/campaign/city_system.gd scripts/autoloads/event_bus.gd scenes/campaign/campaign_hud.gd tests/test_siege_pressure.gd
git commit -m "feat(siege): pressure field + composition/threshold helpers"
```

---

### Task 2: Pressure mutation API (add / overrun / relief classification)

**Files:**
- Modify: `scripts/systems/campaign/city_system.gd` (add 3 methods below the Task 1 helpers)
- Test: `tests/test_siege_pressure.gd` (extend)

**Interfaces:**
- Consumes: constants + `get_siege_threshold` from Task 1.
- Produces:
  - `CitySystem.add_siege_pressure(city: CityState, amount: float) -> void` — clamps to ≥0, emits `siege_progress_changed`. Never captures.
  - `CitySystem.award_siege_overrun(city: CityState) -> void` — `+SIEGE_OVERRUN_BONUS`.
  - `CitySystem.award_siege_battle(city: CityState, besieger_alive: bool, enemy_alive: bool, besieger_frac: float, enemy_frac: float) -> void` — relief-battle result.

- [ ] **Step 1: Write the failing test (extend `_run()`)**

Append to the `_run()` body in `tests/test_siege_pressure.gd`, before the pass/fail print:

```gdscript
	# Pressure API on a besieged city
	any_city.is_under_siege = true
	any_city.siege_faction = &"skulloath"
	any_city.siege_turns = 0.0

	_cs.add_siege_pressure(any_city, 1.5)
	_check(abs(any_city.siege_turns - 1.5) < 0.001, "add_siege_pressure adds")
	_cs.add_siege_pressure(any_city, -10.0)
	_check(any_city.siege_turns == 0.0, "add_siege_pressure floors at 0")

	any_city.siege_turns = 0.0
	_cs.award_siege_overrun(any_city)
	_check(abs(any_city.siege_turns - _cs.SIEGE_OVERRUN_BONUS) < 0.001, "overrun awards +2.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, false, 0.8, 0.0)   # besieger wins outright
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_WIN)) < 0.001, "relief win +1.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, true, 0.9, 0.5)    # both survive, big gap -> point win
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_WIN)) < 0.001, "point win +1.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, true, 0.6, 0.55)   # both survive, small gap -> stalemate
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_STALEMATE)) < 0.001, "stalemate +0.4")

	any_city.siege_turns = 5.0
	_cs.award_siege_battle(any_city, false, true, 0.0, 0.7)   # besieger routed
	_check(abs(any_city.siege_turns - (5.0 - _cs.SIEGE_RELIEF_LOSS)) < 0.001, "relief loss -2.0")

	# Cleanup so later steps see a clean city
	any_city.is_under_siege = false
	any_city.siege_faction = &""
	any_city.siege_turns = 0.0
```

- [ ] **Step 2: Run — expect failure**

Run the Task 1 command. Expected: FAIL on `add_siege_pressure` (method not found).

- [ ] **Step 3: Implement the three methods**

Add below `_army_siege_weight` in `city_system.gd`:

```gdscript
func add_siege_pressure(city: CityState, amount: float) -> void:
	if city == null or not city.is_under_siege:
		return
	city.siege_turns = maxf(0.0, city.siege_turns + amount)
	EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))

func award_siege_overrun(city: CityState) -> void:
	add_siege_pressure(city, SIEGE_OVERRUN_BONUS)

func award_siege_battle(city: CityState, besieger_alive: bool, enemy_alive: bool, besieger_frac: float, enemy_frac: float) -> void:
	if besieger_alive and not enemy_alive:
		add_siege_pressure(city, SIEGE_RELIEF_WIN)
	elif besieger_alive and enemy_alive:
		if besieger_frac - enemy_frac >= SIEGE_POINTWIN_GAP:
			add_siege_pressure(city, SIEGE_RELIEF_WIN)
		else:
			add_siege_pressure(city, SIEGE_RELIEF_STALEMATE)
	elif not besieger_alive:
		add_siege_pressure(city, -SIEGE_RELIEF_LOSS)
```

- [ ] **Step 4: Run — expect pass**

Expected: `SIEGE TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/campaign/city_system.gd tests/test_siege_pressure.gd
git commit -m "feat(siege): pressure mutation API (overrun + relief classification)"
```

---

### Task 3: Rewrite `_process_sieges` (presence fill, decay, attrition, capture)

**Files:**
- Modify: `scripts/systems/campaign/city_system.gd:594-633` (`_process_sieges`) + add `_besiegers_present`, `_apply_besieger_attrition`
- Test: `tests/test_siege_pressure.gd` (extend)

**Interfaces:**
- Consumes: everything from Tasks 1–2, `GameManager.get_armies_at_tile`, `GameManager.movement_system.invalidate_positions`.
- Produces:
  - `CitySystem._besiegers_present(city: CityState) -> Array` (non-garrison armies of `siege_faction` on the hex)
  - `CitySystem._apply_besieger_attrition(besiegers: Array) -> void`
  - `_process_sieges(faction_id)` behavior: fill when present, decay + auto-lift when absent, attrition each turn, capture at threshold (Skulloath dialog branch preserved).

- [ ] **Step 1: Write the failing test (extend `_run()`)**

Append to `_run()` (before pass/fail print):

```gdscript
	# Full siege tick: besieger present fills by base*weight; garrison declines.
	var tcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			tcity = c
			break
	tcity.is_under_siege = true
	tcity.siege_faction = &"skulloath"
	tcity.siege_turns = 0.0
	tcity.garrison_hp_ratio = 1.0

	var besieger := _make_army(&"skulloath", [&"legionary"], tcity.hex_pos)
	_gm.state.armies[besieger.army_id] = besieger
	_gm.movement_system.invalidate_positions()

	_cs._process_sieges(&"skulloath")
	_check(abs(tcity.siege_turns - _cs.SIEGE_FILL_BASE) < 0.001, "present infantry fills by base (%f)" % tcity.siege_turns)
	_check(tcity.garrison_hp_ratio < 1.0, "besieged garrison declines while sieged")

	# Besieger leaves -> next tick decays; still under siege until it hits 0.
	_gm.state.armies.erase(besieger.army_id)
	_gm.movement_system.invalidate_positions()
	var before := tcity.siege_turns
	_cs._process_sieges(&"skulloath")
	_check(tcity.siege_turns < before, "absent besieger decays pressure")
	_check(tcity.is_under_siege, "siege stays active while pressure > 0")

	# Decay all the way to 0 lifts the siege.
	tcity.siege_turns = 0.5
	_cs._process_sieges(&"skulloath")
	_check(not tcity.is_under_siege, "siege lifts when pressure reaches 0")

	# Reaching threshold captures the city for the besieger.
	tcity.is_under_siege = true
	tcity.siege_faction = &"skulloath"
	tcity.siege_turns = float(_cs.get_siege_threshold(tcity))
	var besieger2 := _make_army(&"skulloath", [&"legionary"], tcity.hex_pos)
	_gm.state.armies[besieger2.army_id] = besieger2
	_gm.movement_system.invalidate_positions()
	_cs._process_sieges(&"skulloath")
	_check(tcity.faction_id == &"skulloath", "city captured at threshold")
	_check(not tcity.is_under_siege, "siege cleared after capture")
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL (`_process_sieges` still increments by 1, no decay/lift, `_besiegers_present` missing).

- [ ] **Step 3: Rewrite `_process_sieges` and add helpers**

Replace the entire body of `_process_sieges` (lines 594–633) with:

```gdscript
func _process_sieges(faction_id: StringName) -> void:
	# Pressure model: fill while the besieger holds the hex, decay when absent.
	# Runs on the besieging faction's turn (siege_faction == faction_id).
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not city.is_under_siege:
			continue
		if city.siege_faction != faction_id:
			continue

		var besiegers := _besiegers_present(city)

		if besiegers.is_empty():
			# No one holding the siege — drain, and lift at zero.
			city.siege_turns = maxf(0.0, city.siege_turns - SIEGE_DECAY_ABSENT)
			if city.siege_turns <= 0.0:
				break_siege(city.city_id)
			else:
				EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))
			continue

		# Fill scaled by the best besieging army's composition.
		var weight := 0.0
		for a: ArmyState in besiegers:
			weight = maxf(weight, _army_siege_weight(a))
		city.siege_turns += SIEGE_FILL_BASE * weight

		# Attrition: besieged garrison suffers more than the besieger.
		_apply_besieger_attrition(besiegers)
		city.garrison_hp_ratio = maxf(0.0, city.garrison_hp_ratio - SIEGE_GARRISON_ATTRITION)

		# Jungle Traps: extra besieger attrition (existing building behavior).
		if city.buildings.has(&"jungle_traps"):
			for army: ArmyState in besiegers:
				for unit in army.units:
					var ud := DataManager.get_unit(unit.unit_data_id)
					if ud:
						unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * 0.05))

		EventBus.siege_progress_changed.emit(city.city_id, city.siege_turns, get_siege_threshold(city))

		if city.siege_turns >= get_siege_threshold(city):
			# Skulloath player gets a choice: capture, loot, or raze.
			if faction_id == &"skulloath" and faction_id == GameManager.state.player_faction_id:
				EventBus.siege_choice_needed.emit(city.city_id, faction_id)
			else:
				_capture_city(city)

func _besiegers_present(city: CityState) -> Array:
	var out: Array = []
	for a: ArmyState in GameManager.get_armies_at_tile(city.hex_pos):
		if a.faction_id == city.siege_faction and not a.is_garrison:
			out.append(a)
	return out

func _apply_besieger_attrition(besiegers: Array) -> void:
	for army: ArmyState in besiegers:
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud:
				unit.current_hp = maxi(1, unit.current_hp - int(ud.max_hp * SIEGE_BESIEGER_ATTRITION))
```

- [ ] **Step 4: Run — expect pass**

Expected: `SIEGE TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/campaign/city_system.gd tests/test_siege_pressure.gd
git commit -m "feat(siege): pressure fill/decay/attrition in _process_sieges"
```

---

### Task 4: Wire battle outcomes into siege pressure

**Files:**
- Modify: `scripts/systems/battle/battle_resolver.gd` (garrison-overrun award at ~line 220; relief-battle award after the siege-consequence branches, ~line 232)
- Test: `tests/test_siege_pressure.gd` (extend with a scripted garrison assault)

**Interfaces:**
- Consumes: `CitySystem.award_siege_overrun`, `CitySystem.award_siege_battle`; `atk_strength_pre` / `def_strength_pre` (already computed at `battle_resolver.gd:80-81`); `atk_alive` / `def_alive`.
- Produces: pressure awarded on garrison overrun (+2.0) and on any non-garrison battle fought on a besieged hex.

- [ ] **Step 1: Award overrun where the siege starts**

In `battle_resolver.gd`, the `atk_alive and not def_alive and not garrison_retreat` branch (~line 218-222). Replace:

```gdscript
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id != attacker_army.faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_army.faction_id)
		elif city_at and city_at.faction_id == attacker_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
```
with:
```gdscript
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id != attacker_army.faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_army.faction_id)
			# Overrunning the garrison is a decisive assault win.
			if defender_army.is_garrison and city_at.is_under_siege:
				GameManager.city_system.award_siege_overrun(city_at)
		elif city_at and city_at.faction_id == attacker_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
```

- [ ] **Step 2: Award relief-battle results (role-agnostic)**

Immediately **before** the `# Build battle context for context-aware skill selection` line (~line 233), insert:

```gdscript
	# Siege pressure from a field battle fought on a besieged city hex.
	# Excludes garrison assaults (handled above); handles both "besieger attacks
	# relief on the hex" and "relief attacks besieger on the hex".
	var siege_city := GameManager.city_system.get_city_at_hex(hex_pos)
	if siege_city and siege_city.is_under_siege and not attacker_army.is_garrison and not defender_army.is_garrison:
		var besieger_fid := siege_city.siege_faction
		var besieger_is_atk := attacker_army.faction_id == besieger_fid
		var besieger_is_def := defender_army.faction_id == besieger_fid
		if besieger_is_atk or besieger_is_def:
			var besieger_alive := atk_alive if besieger_is_atk else def_alive
			var enemy_alive := def_alive if besieger_is_atk else atk_alive
			var atk_frac := float(attacker_army.get_total_strength()) / maxf(1.0, float(atk_strength_pre))
			var def_frac := float(defender_army.get_total_strength()) / maxf(1.0, float(def_strength_pre))
			var besieger_frac := atk_frac if besieger_is_atk else def_frac
			var enemy_frac := def_frac if besieger_is_atk else atk_frac
			GameManager.city_system.award_siege_battle(siege_city, besieger_alive, enemy_alive, besieger_frac, enemy_frac)
```

- [ ] **Step 3: Write a scripted-assault smoke test (extend `_run()`)**

This drives a real garrison assault through `auto_resolve`. Stack the attacker so the win is reliable, then assert the siege started with pressure. Append to `_run()`:

```gdscript
	# Scripted garrison assault: overwhelming attacker overruns a garrison,
	# starting a siege with >= overrun pressure.
	var vcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"independent":
			vcity = c
			break
	if vcity != null:
		vcity.is_under_siege = false
		vcity.siege_turns = 0.0
		vcity.garrison_hp_ratio = 1.0
		var garrison: ArmyState = _cs.create_garrison_army(vcity)
		_gm.state.armies[garrison.army_id] = garrison
		# Overwhelming attacker: many elite units.
		var atk := _make_army(&"empire", [&"elite_legionaries", &"elite_legionaries", &"elite_legionaries", &"elite_legionaries", &"marching_bastion"], vcity.hex_pos)
		_gm.state.armies[atk.army_id] = atk
		_gm.movement_system.invalidate_positions()
		_gm.battle_resolver.auto_resolve(atk.army_id, garrison.army_id, vcity.hex_pos)
		_check(vcity.is_under_siege, "scripted assault started a siege")
		_check(vcity.siege_faction == &"empire", "besieger is the attacker")
		_check(vcity.siege_turns >= _cs.SIEGE_OVERRUN_BONUS - 0.001, "overrun awarded pressure (%f)" % vcity.siege_turns)
	else:
		print("NOTE: no independent city to script an assault; skipping smoke check")
```

- [ ] **Step 4: Run — expect pass**

Run the Task 1 command. Expected: `SIEGE TEST PASSED`. If the scripted attacker ever loses (unlucky seed / weak stack), add more `elite_legionaries` — the assertion requires a win. The `auto_resolve` path is deterministic per state, so a sufficiently large stack wins consistently.

- [ ] **Step 5: Parse-check + commit**

```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"
git add scripts/systems/battle/battle_resolver.gd tests/test_siege_pressure.gd
git commit -m "feat(siege): battle wins feed the siege meter (overrun + relief)"
```

---

### Task 5: Departure no longer ends a siege

**Files:**
- Modify: `scripts/autoloads/game_manager.gd:2292-2307` (`_check_siege_departure`)
- Test: `tests/test_siege_pressure.gd` (extend)

**Interfaces:**
- Consumes: existing `_check_siege_departure` call site (`game_manager.gd:2233`).
- Produces: `_check_siege_departure` becomes a no-op for pressure — decay in `_process_sieges` lifts the siege instead of an instant break. Explicit breaks (friendly retake at `game_manager.gd:2272`, peace) still call `break_siege`.

- [ ] **Step 1: Write the failing test (extend `_run()`)**

Append to `_run()`:

```gdscript
	# Leaving a besieged hex must NOT instantly end the siege.
	var dcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			dcity = c
			break
	dcity.is_under_siege = true
	dcity.siege_faction = &"skulloath"
	dcity.siege_turns = 3.0
	var leaver := _make_army(&"skulloath", [&"legionary"], dcity.hex_pos)
	_gm.state.armies[leaver.army_id] = leaver
	_gm.movement_system.invalidate_positions()
	# Simulate the departure check directly with the army already moved away.
	leaver.hex_pos = dcity.hex_pos + Vector2i(1, 0)
	_gm.movement_system.invalidate_positions()
	_gm._check_siege_departure(leaver)
	_check(dcity.is_under_siege, "departure does not instantly break the siege")
	_check(abs(dcity.siege_turns - 3.0) < 0.001, "departure leaves pressure intact (decay handles it later)")
	dcity.is_under_siege = false
	dcity.siege_faction = &""
	dcity.siege_turns = 0.0
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — current `_check_siege_departure` calls `break_siege`, so `is_under_siege` is false.

- [ ] **Step 3: Make departure a no-op for the siege**

Replace the body of `_check_siege_departure` (`game_manager.gd:2292-2307`) with:

```gdscript
func _check_siege_departure(army: ArmyState) -> void:
	# Pressure model: leaving does NOT end the siege. If no besieger remains,
	# _process_sieges decays the pressure and lifts the siege at zero. This keeps
	# a determined attacker able to step out and back without restarting.
	pass
```

- [ ] **Step 4: Run — expect pass**

Expected: `SIEGE TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/autoloads/game_manager.gd tests/test_siege_pressure.gd
git commit -m "feat(siege): besieger departure decays instead of instantly breaking"
```

---

### Task 6: AI holds and prioritizes its sieges

**Files:**
- Modify: `scripts/autoloads/turn_manager.gd` (`_execute_ai_turn` ~906-947, `_execute_skulloath_ai` ~961-992) + a small helper
- Test: `tests/test_siege_ai.gd`

**Interfaces:**
- Consumes: `GameManager.get_armies_at_tile`, `CitySystem.get_city_at_hex`, `_army_siege_weight`.
- Produces:
  - `TurnManager._army_is_holding_siege(army: ArmyState) -> bool` — true if the army sits on an enemy city under active siege by its own faction with a besieging weight > 0.
  - Both AI army loops skip re-targeting for an army that is holding a siege.

- [ ] **Step 1: Write the failing test**

Create `tests/test_siege_ai.gd` with the standard scaffold, plus a `_tm` autoload lookup. `_run()` body (after `new_game`):

```gdscript
	var _tm = root.get_node("/root/TurnManager")

	# Put a Skulloath army on an enemy (empire) city with an active siege.
	var ecity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			ecity = c
			break
	ecity.is_under_siege = true
	ecity.siege_faction = &"skulloath"
	ecity.siege_turns = 2.0

	var sieger := _make_army(&"skulloath", [&"legionary", &"legionary", &"legionary"], ecity.hex_pos)
	_gm.state.armies[sieger.army_id] = sieger
	_gm.movement_system.invalidate_positions()

	_check(_tm._army_is_holding_siege(sieger), "AI recognizes an army holding a siege")
	var pos_before: Vector2i = sieger.hex_pos
	sieger.movement_remaining = 2.0
	# The AI army loop must leave a siege-holding army in place.
	_tm._maybe_hold_siege_or_retarget(sieger, &"skulloath")
	_check(sieger.hex_pos == pos_before, "AI keeps a besieging army on the city")
```

- [ ] **Step 2: Run — expect failure**

Run:
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_siege_ai.gd
```
Expected: FAIL — helpers not defined.

- [ ] **Step 3: Add the siege-hold helpers**

Add near `_execute_ai_turn` in `turn_manager.gd`:

```gdscript
func _army_is_holding_siege(army: ArmyState) -> bool:
	var city := GameManager.city_system.get_city_at_hex(army.hex_pos)
	if city == null or not city.is_under_siege:
		return false
	if city.siege_faction != army.faction_id or city.faction_id == army.faction_id:
		return false
	return GameManager.city_system._army_siege_weight(army) > 0.0

# Returns true if the army was left in place holding a siege (caller should skip
# re-targeting it this turn); false if it is free to act.
func _maybe_hold_siege_or_retarget(army: ArmyState, faction_id: StringName) -> bool:
	if _army_is_holding_siege(army):
		army.movement_remaining = 0.0
		return true
	return false
```

- [ ] **Step 4: Call it in both AI loops**

In `_execute_ai_turn`, immediately after the `if army.movement_remaining <= 0: continue` guard (~line 914) and before the "Don't attack with tiny armies" block:

```gdscript
		if _maybe_hold_siege_or_retarget(army, faction_id):
			continue
```

Add the identical two lines in `_execute_skulloath_ai` after its `if army.movement_remaining <= 0: continue` guard (~line 969).

- [ ] **Step 5: Prefer near-complete sieges when targeting**

In `_find_nearest_enemy_region_hex` consumers, bias toward besieged enemy cities. Minimal, self-contained approach: in `_execute_ai_turn`, when `target_hex` resolves to an enemy region, first check for an in-progress siege by this faction and prefer it. Insert right before `_ai_move_army_safe(army, target_hex, faction_id)` (~line 941):

```gdscript
		# Prefer finishing an in-progress siege over opening a new front.
		var ongoing := _nearest_own_siege_hex(army.hex_pos, faction_id)
		if ongoing != Vector2i(-1, -1):
			target_hex = ongoing
```

And add the helper near `_army_is_holding_siege`:

```gdscript
func _nearest_own_siege_hex(from: Vector2i, faction_id: StringName) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not city.is_under_siege or city.siege_faction != faction_id:
			continue
		var d := HexHelper.hex_distance(from, city.hex_pos)
		if d < best_d:
			best_d = d
			best = city.hex_pos
	return best
```

- [ ] **Step 6: Run — expect pass**

Run the Task 6 command. Expected: `SIEGE TEST PASSED`.

- [ ] **Step 7: Parse-check + commit**

```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"
git add scripts/autoloads/turn_manager.gd tests/test_siege_ai.gd
git commit -m "feat(siege): AI holds and prioritizes sieges in progress"
```

---

### Task 7: UI — city-panel meter, map badge, toasts

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` (city-panel siege block ~7729-7740; add `_shown_city_id` tracking in `_show_city_panel`/`_hide_city_panel`; connect siege signals; toasts via `_show_advisor_toast`)
- Modify: `scenes/campaign/campaign.gd` (siege-badge label on city markers)
- Test: `tests/tmp_screenshot_siege.gd` (visual verification)

**Interfaces:**
- Consumes: `CitySystem.get_siege_threshold`, `EventBus.siege_progress_changed`, `EventBus.siege_started`, `EventBus.city_captured`, `EventBus.siege_broken`, `CityState.siege_turns`, `CityState.get_display_name()`, `campaign._hex_to_pixel`, `campaign._city_markers`, `campaign_hud._show_advisor_toast`.
- Produces: a progress bar + "falls in ~N turns" in the city panel; a turns-to-fall number badge over besieged city markers; player-relevant siege toasts.

- [ ] **Step 1: Replace the city-panel siege label with a meter**

In `campaign_hud.gd`, the `if city.is_under_siege:` block (~7729-7740), replace the single label with a bar + readout:

```gdscript
	# Siege status — pressure meter
	if city.is_under_siege:
		var attacker := DataManager.get_faction(city.siege_faction)
		var aname := attacker.display_name if attacker else str(city.siege_faction)
		var threshold := CitySystem.get_siege_threshold(city)
		var frac := clampf(city.siege_turns / float(maxi(1, threshold)), 0.0, 1.0)
		var falls_in := int(ceil(maxf(0.0, float(threshold) - city.siege_turns)))

		var siege_label := Label.new()
		siege_label.text = "UNDER SIEGE by %s — falls in ~%d turn%s" % [aname, falls_in, "" if falls_in == 1 else "s"]
		siege_label.add_theme_font_size_override("font_size", 13)
		siege_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
		vbox.add_child(siege_label)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = frac
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(280, 14)
		vbox.add_child(bar)
```

- [ ] **Step 2: Track the shown city + refresh the panel live**

`campaign_hud` has no open-city field today (it keys off `city_panel.visible`). Add one. Near the other panel members (~line 74, beside `_loyalty_panel_city_id`):

```gdscript
var _shown_city_id: StringName = &""
var _siege_warned: Dictionary = {}   # city_id -> true (capture-imminent toast fired once)
```

In `_show_city_panel(city_id)`, right after the `if city == null: return` guard (~line 7553):

```gdscript
	_shown_city_id = city_id
```

In `_hide_city_panel()` (line 7922), inside the function:

```gdscript
	_shown_city_id = &""
```

In `_ready` (where `EventBus.siege_choice_needed.connect(...)` already is, ~line 119), add:

```gdscript
	EventBus.siege_progress_changed.connect(_on_siege_progress_changed)
	EventBus.siege_started.connect(_on_siege_started_toast)
```

Add the handler (anywhere among the `_on_*` methods):

```gdscript
func _on_siege_progress_changed(city_id: StringName, pressure: float, threshold: int) -> void:
	# Rebuild the panel if it's showing this city.
	if _shown_city_id == city_id and city_panel and city_panel.visible:
		_show_city_panel(city_id)
	# Capture-imminent toast (once per siege), for player-relevant cities.
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return
	var pf := GameManager.state.player_faction_id
	var relevant := city.faction_id == pf or city.siege_faction == pf
	if relevant and pressure >= float(threshold) - 1.0 and not _siege_warned.has(city_id):
		_siege_warned[city_id] = true
		_show_advisor_toast("%s will fall next turn!" % city.get_display_name())
	elif pressure < float(threshold) - 1.0:
		_siege_warned.erase(city_id)
```

- [ ] **Step 3: Siege-start toast**

Add the handler:

```gdscript
func _on_siege_started_toast(city_id: StringName, faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return
	var pf := GameManager.state.player_faction_id
	if city.faction_id == pf or faction_id == pf:
		_show_advisor_toast("Siege begun at %s" % city.get_display_name())
```

- [ ] **Step 4: Number badge on the map city markers**

The main-map markers live in `campaign.gd` (`_city_markers[city_id]` Node2D at `_hex_to_pixel(city.hex_pos)`). Add a turns-to-fall label per besieged city. In `campaign.gd`, in `_ready` after `_create_city_markers()` (~line 185), connect:

```gdscript
	EventBus.siege_progress_changed.connect(_on_siege_badge_update)
	EventBus.siege_started.connect(func(cid, _f): _refresh_siege_badge(cid))
	EventBus.siege_broken.connect(func(cid): _refresh_siege_badge(cid))
	EventBus.city_captured.connect(func(cid, _o, _n): _refresh_siege_badge(cid))
```

Add:

```gdscript
func _on_siege_badge_update(city_id: StringName, _pressure: float, _threshold: int) -> void:
	_refresh_siege_badge(city_id)

func _refresh_siege_badge(city_id: StringName) -> void:
	var marker: Node2D = _city_markers.get(city_id)
	if marker == null:
		return
	var badge: Label = marker.get_node_or_null("SiegeBadge")
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or not city.is_under_siege:
		if badge:
			badge.queue_free()
		return
	if badge == null:
		badge = Label.new()
		badge.name = "SiegeBadge"
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		badge.add_theme_color_override("font_outline_color", Color(0.4, 0.03, 0.02))
		badge.add_theme_constant_override("outline_size", 6)
		badge.z_index = 5
		badge.position = Vector2(-10, -34)
		marker.add_child(badge)
	var threshold := GameManager.city_system.get_siege_threshold(city)
	var falls_in := int(ceil(maxf(0.0, float(threshold) - city.siege_turns)))
	badge.text = "⚔%d" % falls_in
```

- [ ] **Step 5: Visual verification via screenshot harness**

Create `tests/tmp_screenshot_siege.gd` following the screenshot-harness pattern (run WITHOUT `--headless`): set `GameManager._is_transitioning = true` around `new_game`, instantiate the campaign scene, put an enemy city under siege with `siege_turns` at ~60% of threshold (call `city_system.start_siege(city_id, &"skulloath")` then set `siege_turns`, then emit `siege_progress_changed`), open its panel via the HUD's `_show_city_panel`, render a frame, and save a PNG to `user://siege_meter.png`. Run:

```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_siege.gd
```
Open `C:/Users/Lutz Görs/AppData/Roaming/Godot/app_userdata/Fracture Wars/siege_meter.png` and confirm the panel bar, "falls in ~N turns" text, and the map `⚔N` badge render. Iterate on placement (badge `position`, bar size) until it reads clearly.

- [ ] **Step 6: Parse-check + commit**

```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"
git add scenes/campaign/campaign_hud.gd scenes/campaign/campaign.gd tests/tmp_screenshot_siege.gd
git commit -m "feat(siege): pressure meter UI - panel bar, map badge, toasts"
```

---

### Task 8: Tuning loop + determinism check

**Files:**
- Modify (numbers only, if needed): `scripts/systems/campaign/city_system.gd` siege constants
- Reference: `tests/tmp_econ_sim.gd`, `tests/test_battle_determinism.gd`

**Interfaces:**
- Consumes: the whole mechanic from Tasks 1–7.
- Produces: tuned `SIEGE_*` constants and a short results note appended to `docs/trajectory_study.md`.

- [ ] **Step 1: Confirm battle determinism is unaffected**

Run:
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_battle_determinism.gd
```
Expected: `FINGERPRINT MATCH`. Pressure awards run after the sim and don't touch RNG. If it MISMATCHES, a real sim change slipped in — investigate before touching baselines (do NOT regenerate them to "fix" a mismatch).

- [ ] **Step 2: Baseline the current conquest rate**

Run several AI-vs-AI games and count captures. Example (single game, 60 turns):
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/tmp_econ_sim.gd -- 12345 60
```
Run seeds 12345, 23456, 34567 (parallel). Record, per game: total `city_captured` events (cities changing hands) and the max single-faction city count at the end.

- [ ] **Step 3: Tune toward the targets**

Targets: cities DO change hands (vs ~0 before) AND no single faction runs away with the map by turn 60. Adjust in `city_system.gd`:
- Too few captures → raise `SIEGE_FILL_BASE` / `SIEGE_OVERRUN_BONUS`, or lower `SIEGE_DECAY_ABSENT`.
- Runaway snowball → lower fill, raise `SIEGE_DECAY_ABSENT` / `SIEGE_GARRISON_ATTRITION` (defenders recover), or raise the point-win gap.
Re-run Step 2 after each change. Keep changes to constants only.

- [ ] **Step 4: Record the outcome**

Append a short section to `docs/trajectory_study.md` with the before/after capture counts and the final constant values. Re-run the full unit suite:
```bash
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_siege_pressure.gd
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_siege_ai.gd
```
Expected: both `SIEGE TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/campaign/city_system.gd docs/trajectory_study.md
git commit -m "balance(siege): tune pressure constants so conquest resolves without runaway"
```

---

## Notes for the implementer

- **Autoloads in `-s` tests:** fetch via `root.get_node("/root/GameManager")` etc.; class-level autoload references don't resolve. `DataManager`, `EventBus`, `CitySystem`, `GameManager` are all reachable as autoloads and as `GameManager.city_system` / `GameManager.battle_resolver` / `GameManager.movement_system`.
- **Finding armies at a hex in tests:** after mutating `GameManager.state.armies`, always call `GameManager.movement_system.invalidate_positions()` so `get_armies_at_tile` re-scans.
- **`CitySystem` vs `GameManager.city_system`:** `CitySystem` is the autoload singleton (usable for `const`/`static`-style access like `CitySystem.get_siege_threshold`); `GameManager.city_system` is the same instance. Match whichever form the surrounding code already uses in each file.
- **Existing saves:** old binary saves store `siege_turns` as an int; it loads into the float field and is overwritten on the next siege tick. Acceptable in dev; no migration.
