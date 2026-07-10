# Plan C: Campaign UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate redundant per-frame / per-event recomputation in the campaign UI layer (resource-bar income projection, political overlay + map rebake, research tech-tree drawing, army/city panel rebuilds, minimap updates) without changing a single displayed number or pixel. Only *when* and *how often* work happens changes: caching, coalescing to one update per frame, guarding AI-turn events, and updating textures/images in place.

**Architecture:** Three UI scripts are touched — `scenes/campaign/campaign_hud.gd` (~13k lines, top-bar/panels), `scenes/campaign/campaign.gd` (~5k lines, map scene), `scenes/campaign/campaign_camera.gd` — plus one UI-driven hot path in `scripts/systems/campaign/city_system.gd` (`get_available_buildings`). The dominant costs are: (1) the income projection recomputing `calculate_city_income` 18–21× per city per refresh, (2) `_update_political_overlay` doing an O(tiles × chunk_entries) linear scan and then unconditionally redrawing every chunk, rebuilding the overview sprite, and re-baking the whole ~5650×4350 map texture. Both get single-pass/memo structures. All changes are self-contained per task and remain correct (just slower) if Plan A/B caches are absent — no task below calls any new Plan A/B API; only existing public functions.

**Tech Stack:** Godot 4.4, GDScript (typed, tab-indented)

## Global Constraints
- All changes behavior-preserving: displayed numbers and visuals identical; only update frequency/cost changes.
- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- Parse check after every task: `& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --quit 2>&1 | Select-String "SCRIPT ERROR|Parse Error"` → expect no output.
- Automated tests where feasible (tests/ SceneTree scripts, autoloads available); UI tasks otherwise get explicit manual smoke-check steps (launch game, do X, observe Y).
- Commit after each task on branch `city_management`; add ONLY files the task touched (repo has unrelated modified .import files — never `git add -A`).

Verified facts this plan relies on (all confirmed by reading the code):
- `CitySystem.calculate_city_income(city)` (scripts/systems/campaign/city_system.gd:199-263) returns a plain `Dictionary` mapping resource type (int) → int for **all** resource types at once. One call yields everything the per-resource breakdowns need.
- `_calculate_income_breakdown` is called from exactly two places: `_calculate_projected_income` (campaign_hud.gd:1302) and the tooltip hover `_on_resource_hover_entered` (campaign_hud.gd:1649). No other callers exist.
- `_update_resource_display()` (which calls `_calculate_projected_income`) has ~32 call sites in campaign_hud.gd, including `_on_turn_started` (line 965) which runs at the start of **every** faction's turn — so the projection is refreshed on every state-changing player action and at every turn boundary.
- The elderbeast contribution to the income breakdown (campaign_hud.gd:1490-1497) only counts beasts with `beast.faction_id == player_id`. AI-owned beast moves can never change the displayed projection.
- `campaign.gd` already declares `var _hex_tile_chunk_data: Dictionary = {}` (line 60) with the intended comment — it is declared but **never populated or read anywhere**. Task 2 populates and uses it.
- `_rebake_hex_map()` is called from exactly one place: `_update_political_overlay` line 1396. `_update_political_overlay` is called from lines 176 (`_ready`), 2902 (`_on_army_moved`, player-visible, non-animating only), 2920 (`_on_region_ownership_changed`, player turn only), 3775 (player turn start), 3902 (`_on_city_captured`, player turn only), 4856 (minimap view-mode toggle).
- `_update_minimap_viewport_only()` (campaign.gd:5136-5147) exists and redraws only the viewport rectangle from `_minimap_content_cache`, falling back to `_update_minimap()` when the cache is null. It fully covers what a minimap drag needs (camera indicator only; camera movement does not change map content).
- Player turn start (campaign.gd:3777) already calls `_create_army_markers()` unconditionally, and `_create_army_markers` (1400-1424) has a fast path that only updates positions when the army-id set is unchanged.
- The `_RadialTechTree` layout (`_calculate_positions`, campaign_hud.gd:5505-5600) depends only on `DataManager.research`, `DataManager.buildings`, and `faction_id` — all static during a campaign. It does **not** depend on completed/current research, so layout never needs recomputing on research change.
- The research panel tree control is clipped by a `tree_clip` Control with `clip_contents = true` (campaign_hud.gd:5383-5387), so screen-space culling in `_draw` cannot change any visible pixel.
- `GameManager.new_game(&"empire")` (scripts/autoloads/game_manager.gd:704-735) fully initializes `state` (map, factions, cities, elderbeasts, armies, diplomacy) synchronously; the trailing `transition_to_scene` only starts a 0.5 s tween, so a headless SceneTree test that runs synchronously and quits never loads the campaign scene. `tests/probe_autoloads.gd` confirms autoloads are available in `-s` scripts after one deferred call.
- Current branch is already `city_management`.

---

### Task 1: Income projection — single-pass memo, hover reuse, equivalence test (HIGH)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_calculate_projected_income` (1295-1305), `_calculate_income_breakdown` (1307-1604), `_on_resource_hover_entered` (1645-1649), new members near line 95.
- `tests/test_income_breakdown_equivalence.gd` — new automated equivalence test.

**Interfaces** (all signatures unchanged)
- `_calculate_projected_income() -> Dictionary` — unchanged signature/return; now rebuilds the memo first and fills `_income_breakdown_cache`.
- `_calculate_income_breakdown(res_type: int) -> Dictionary` — unchanged signature/return shape `{"cities": {...}, "upkeep": {...}, "modifiers": [...], "net": int}`; steps 1–3 and the upkeep step now read from the memo.
- New private members: `_income_city_memo`, `_income_upkeep_memo`, `_income_memo_valid`, `_income_breakdown_cache`.

Why displayed numbers are bit-identical: the memo stores the exact return values of `calculate_city_income` and `calculate_class_percentages` per city, keyed by the same siege/exists filter the old code applied inline; every arithmetic line in the breakdown is untouched. The old code computed `calculate_city_income(city)` 3× per city per resource type (lines 1322, 1333, 1366) and `calculate_class_percentages` 2× (1337, 1370) — both are pure functions of current state, so 1 call per city per update returns the identical dictionaries. The army upkeep single pass inserts `by_tag` keys in the same army → unit → commander iteration order as the old per-resource loop, so tooltip line order is preserved. Treaty loops (steps 6/6b), elderbeast, food/captive consumption, and GOLD plunder are left verbatim — they are O(treaties)/O(beasts) tiny and leaving them inline guarantees identical modifier ordering.

Why hover reuse is display-identical: the projection is refreshed by `_update_resource_display()` on every state-changing action and at every turn start (line 965, ~32 call sites), so `_income_breakdown_cache` always reflects the same state that produced the `+N` label the user is hovering. The tooltip now provably always matches the visible income label (previously a mid-AI-turn state change could make the freshly-computed tooltip disagree with the stale label). The only timing window is between an AI-turn state change and the next refresh — during which the old tooltip disagreed with the old label; the new tooltip agrees with the label. Net numbers at every refresh point are identical.

**Steps**

- [x] 1.1 In `scenes/campaign/campaign_hud.gd`, add new members directly after line 95 (`var _ai_offer_dialog: PanelContainer`):

```gdscript
# ── Income projection memo (rebuilt once per _calculate_projected_income) ──
# One calculate_city_income + calculate_class_percentages call per city and one
# army scan per update, instead of 3x/2x per city per resource type.
var _income_city_memo: Dictionary = {}       # city_id -> {income: Dictionary, pcts: Dictionary}
var _income_upkeep_memo: Dictionary = {}     # res_type -> {by_tag: Dictionary, total: int}
var _income_memo_valid := false
var _income_breakdown_cache: Dictionary = {} # res_type -> breakdown Dictionary (last projection update)
```

- [x] 1.2 Replace `_calculate_projected_income` (lines 1295-1305) — old:

```gdscript
func _calculate_projected_income() -> Dictionary:
	# Use the detailed breakdown for each resource to get true net income
	var income: Dictionary = {}
	var display_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var breakdown := _calculate_income_breakdown(res_type)
		if breakdown.net != 0:
			income[res_type] = breakdown.net
	return income
```

with:

```gdscript
func _calculate_projected_income() -> Dictionary:
	# Use the detailed breakdown for each resource to get true net income.
	# Build the per-update memo once, then derive all per-resource breakdowns
	# from it and cache them for the hover tooltip.
	_rebuild_income_memo()
	_income_breakdown_cache.clear()
	var income: Dictionary = {}
	var display_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var breakdown := _calculate_income_breakdown(res_type)
		_income_breakdown_cache[res_type] = breakdown
		if breakdown.net != 0:
			income[res_type] = breakdown.net
	return income

func _rebuild_income_memo() -> void:
	_income_city_memo.clear()
	_income_upkeep_memo.clear()
	_income_memo_valid = false
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return
	# One calculate_city_income + calculate_class_percentages per city.
	# Membership in the memo encodes the same "city exists and not under siege"
	# filter the breakdown steps 1-3 applied inline.
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			_income_city_memo[city_id] = {
				income = GameManager.city_system.calculate_city_income(city),
				pcts = LoyaltySystem.calculate_class_percentages(city, city.faction_id),
			}
	# One army/unit scan builds upkeep for ALL resource types at once.
	# Iteration order (army -> units -> commander) matches the old per-resource
	# loop, so by_tag key insertion order (tooltip line order) is preserved.
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != player_id:
			continue
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud == null:
				continue
			var tag := "Other"
			for t in ["infantry", "ranged", "cavalry", "mage", "construct"]:
				if ud.tags.has(t):
					tag = t.capitalize()
					break
			for res_type in ud.upkeep_cost:
				var entry: Dictionary = _income_upkeep_memo.get_or_add(res_type, {by_tag = {}, total = 0})
				entry.by_tag[tag] = entry.by_tag.get(tag, 0) + ud.upkeep_cost[res_type]
				entry.total += ud.upkeep_cost[res_type]
		# Commander upkeep
		if army.commander != null:
			var level_mult := 1.0 + (army.commander.level - 1) * 0.5
			for res_type in CommanderSystem.COMMANDER_UPKEEP:
				var cmd_cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				var entry: Dictionary = _income_upkeep_memo.get_or_add(res_type, {by_tag = {}, total = 0})
				entry.by_tag["Commanders"] = entry.by_tag.get("Commanders", 0) + cmd_cost
				entry.total += cmd_cost
	_income_memo_valid = true
```

- [x] 1.3 In `_calculate_income_breakdown` (1307-1604), replace **only** the header + steps 1–3 and the upkeep step; every other step stays byte-identical. New full function (steps 4, 5, 6, 6b, elderbeast, food consumption, captive consumption, plunder, and the final `breakdown.net` line are verbatim copies of the current code — copy them from the existing function, do not retype):

```gdscript
func _calculate_income_breakdown(res_type: int) -> Dictionary:
	# Returns {"cities": {city_name: amount}, "upkeep": {category: amount},
	#          "modifiers": [{label, amount}], "net": int}
	# Mirrors the actual _generate_income() logic in city_system.gd.
	# Per-city income / class percentages / army upkeep come from the memo
	# built once per update in _rebuild_income_memo() (see
	# _calculate_projected_income). The tooltip hover reuses the cached
	# breakdown so it always matches the income label on screen.
	var breakdown := {"cities": {}, "upkeep": {}, "modifiers": [], "net": 0}
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return breakdown
	if not _income_memo_valid:
		_rebuild_income_memo()

	# Step 1: Base city income (from buildings + region)
	var base_total := 0
	for city_id in fs.owned_cities:
		var memo: Dictionary = _income_city_memo.get(city_id, {})
		if memo.is_empty():
			continue
		var city: CityState = GameManager.state.cities.get(city_id)
		var amount: int = (memo.income as Dictionary).get(res_type, 0)
		if amount != 0:
			breakdown.cities[city.get_display_name()] = amount
			base_total += amount

	# Step 2: Class bonuses (applied per-city in _generate_income, aggregate here)
	var class_bonus_total := 0
	for city_id in fs.owned_cities:
		var memo: Dictionary = _income_city_memo.get(city_id, {})
		if memo.is_empty():
			continue
		var raw: int = (memo.income as Dictionary).get(res_type, 0)
		if raw == 0:
			continue
		var pcts: Dictionary = memo.pcts
		var bonus := 0
		match res_type:
			Enums.ResourceType.FOOD:
				bonus = int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
			Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
				bonus = int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
			Enums.ResourceType.TECHNOLOGY:
				bonus = int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
			Enums.ResourceType.GOLD:
				bonus = int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
		class_bonus_total += bonus
	if class_bonus_total != 0:
		var class_label := ""
		match res_type:
			Enums.ResourceType.FOOD: class_label = "Peasant Bonus"
			Enums.ResourceType.IRON, Enums.ResourceType.WOOD: class_label = "Artisan Bonus"
			Enums.ResourceType.TECHNOLOGY: class_label = "Scholar Bonus"
			Enums.ResourceType.GOLD: class_label = "Noble Bonus"
			_: class_label = "Class Bonus"
		breakdown.modifiers.append({label = class_label, amount = class_bonus_total})

	var income_subtotal := base_total + class_bonus_total

	# Step 3: Loyalty multiplier (applied per-city, aggregate the penalty)
	var loyalty_penalty := 0
	for city_id in fs.owned_cities:
		var memo: Dictionary = _income_city_memo.get(city_id, {})
		if memo.is_empty():
			continue
		var city: CityState = GameManager.state.cities.get(city_id)
		var raw: int = (memo.income as Dictionary).get(res_type, 0)
		if raw == 0:
			continue
		var pcts: Dictionary = memo.pcts
		var after_class := raw
		match res_type:
			Enums.ResourceType.FOOD:
				after_class += int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
			Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
				after_class += int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
			Enums.ResourceType.TECHNOLOGY:
				after_class += int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
			Enums.ResourceType.GOLD:
				after_class += int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
		var loyalty_mult := LoyaltySystem.get_loyalty_multiplier(city.loyalty)
		if loyalty_mult < 1.0:
			loyalty_penalty += int(float(after_class) * loyalty_mult) - after_class
	if loyalty_penalty != 0:
		breakdown.modifiers.append({label = "Low Loyalty", amount = loyalty_penalty})
		income_subtotal += loyalty_penalty

	# ── Steps 4 (Research), 5 (Senate), 6 (Trade), 6b (Trade Relations),
	#    Elderbeast income: KEEP VERBATIM from the current implementation
	#    (campaign_hud.gd lines 1388-1498) ──

	# Upkeep grouped by tag — from the single-pass memo
	var upkeep_total := 0
	var upkeep_by_tag: Dictionary = {}
	var upkeep_memo: Dictionary = _income_upkeep_memo.get(res_type, {})
	if not upkeep_memo.is_empty():
		upkeep_by_tag = (upkeep_memo.by_tag as Dictionary).duplicate()
		upkeep_total = upkeep_memo.total
	breakdown.upkeep = upkeep_by_tag

	# ── Population food consumption, captive consumption, trade plunder:
	#    KEEP VERBATIM from the current implementation (lines 1524-1601).
	#    NOTE: the captive-consumption loop intentionally does NOT use the memo
	#    because the old code does not exclude sieged cities there
	#    (`if city == null: continue` only, line 1541-1543) — do not change it. ──

	breakdown.net = income_subtotal - upkeep_total - food_consumption - captive_consumption
	return breakdown
```

(The old army-upkeep loop, lines 1500-1522, is deleted and replaced by the memo read above. `food_consumption` and `captive_consumption` are still declared/computed by the verbatim-kept blocks, so the final `net` line compiles unchanged.)

- [x] 1.4 In `_on_resource_hover_entered` (1645-1649), replace the recompute — old:

```gdscript
	var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
	var breakdown := _calculate_income_breakdown(res_type)
```

new:

```gdscript
	var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
	# Reuse the breakdown cached by the last projection update. The projection
	# is refreshed on every state-changing action and at every turn start
	# (_on_turn_started -> _update_resource_display, line ~965), so the cached
	# breakdown always matches the +N income label currently on screen.
	var breakdown: Dictionary = _income_breakdown_cache.get(res_type, {})
	if breakdown.is_empty():
		breakdown = _calculate_income_breakdown(res_type)
```

- [x] 1.5 Create `tests/test_income_breakdown_equivalence.gd` (complete file):

```gdscript
extends SceneTree
## Equivalence test: the memoized income breakdown must produce identical
## dictionaries to the original (pre-memo) reference implementation.
## Run: godot --headless --path . -s tests/test_income_breakdown_equivalence.gd

var _fail_count := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.new_game(&"empire")
	_compare_all("initial empire state")
	# Mutate state and re-check: loyalty drop (changes step 3)
	var fs: FactionState = GameManager.state.faction_states[GameManager.state.player_faction_id]
	if fs.owned_cities.size() > 0:
		var c0: CityState = GameManager.state.cities[fs.owned_cities[0]]
		c0.loyalty = 20
	_compare_all("after loyalty change")
	# Siege a city (changes memo membership / steps 1-3 + food consumption)
	if fs.owned_cities.size() > 1:
		var c1: CityState = GameManager.state.cities[fs.owned_cities[1]]
		c1.is_under_siege = true
	_compare_all("after siege change")
	if _fail_count == 0:
		print("EQUIVALENCE TEST PASSED")
		quit(0)
	else:
		print("EQUIVALENCE TEST FAILED (%d mismatches)" % _fail_count)
		quit(1)

func _compare_all(label: String) -> void:
	var hud: Control = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()
	# Populates _income_city_memo/_income_upkeep_memo and _income_breakdown_cache
	var projected: Dictionary = hud._calculate_projected_income()
	var display_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var expected := _reference_breakdown(res_type)
		var actual: Dictionary = hud._calculate_income_breakdown(res_type)
		var cached: Dictionary = hud._income_breakdown_cache.get(res_type, {})
		if expected != actual:
			_fail_count += 1
			print("MISMATCH (%s) res=%d direct call:\n  expected=%s\n  actual=%s" % [label, res_type, expected, actual])
		if expected != cached:
			_fail_count += 1
			print("MISMATCH (%s) res=%d cached breakdown:\n  expected=%s\n  cached=%s" % [label, res_type, expected, cached])
		var exp_net: int = expected.net
		if exp_net != 0 and int(projected.get(res_type, 0)) != exp_net:
			_fail_count += 1
			print("MISMATCH (%s) res=%d projected net: expected=%d got=%s" % [label, res_type, exp_net, str(projected.get(res_type))])
		if exp_net == 0 and projected.has(res_type):
			_fail_count += 1
			print("MISMATCH (%s) res=%d projected should omit zero net" % [label, res_type])
	hud.free()

func _reference_breakdown(res_type: int) -> Dictionary:
	# === VERBATIM copy of campaign_hud.gd _calculate_income_breakdown as it
	# === existed BEFORE Task 1 (lines 1307-1604). Copy the entire old function
	# === body here, unchanged, when implementing. It only references globals
	# === (GameManager, DataManager, Enums, LoyaltySystem, TurnManager,
	# === CommanderSystem, DiplomacySystem), so it runs unmodified here.
	var breakdown := {"cities": {}, "upkeep": {}, "modifiers": [], "net": 0}
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return breakdown
	# ... (paste old lines 1317-1604 here verbatim) ...
	return breakdown
```

The implementer MUST paste the pre-edit function body (copy it from `git show HEAD:scenes/campaign/campaign_hud.gd` before making the Task 1 edit, or from the diff) — that is the whole point of the reference. Dictionary `==` in Godot 4 compares keys/values recursively, and Array `==` is element-wise, so `expected != actual` is a deep comparison; modifier ordering differences will be caught.

- [x] 1.6 Run the test:

```powershell
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s tests/test_income_breakdown_equivalence.gd 2>&1 | Select-String "EQUIVALENCE|MISMATCH"
```

Expected output: exactly one line `EQUIVALENCE TEST PASSED`, no `MISMATCH` lines. (If autoload globals fail to resolve in `-s` mode — they resolved for `tests/probe_autoloads.gd` via `root.get_node`, and globals are expected to work — IMPLEMENTER MUST VERIFY and, if needed, fetch autoloads via `root.get_node("/root/GameManager")` into local variables at the top of `_run`.)

- [x] 1.7 Parse check (command in Global Constraints) → no output.
- [x] 1.8 Manual smoke: launch (`& "<godot>" --path .`), start a new Empire game, hover each resource in the top bar → tooltip shows city lines, class bonus, upkeep lines, `Net:` matching the `+N`/`-N` label below the amount. End turn once → labels update.
- [x] 1.9 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd tests/test_income_breakdown_equivalence.gd
git commit -m "perf(hud): single-pass income projection memo + cached hover breakdown"
```

---

### Task 2: Political overlay — coord→entry index, change tracking, in-place overview, debounced rebake (HIGH)

**Files**
- `scenes/campaign/campaign.gd` — chunk build (598-602 inside `_render_hex_map`), `_update_political_overlay` (1300-1396), `_create_overview_sprite` (358-393), `_update_overview_colors` (395-403), new `_request_rebake` near `_rebake_hex_map` (482-489), member near line 141.

**Interfaces**
- `_update_political_overlay() -> void` — unchanged signature; now O(tiles) with direct entry lookup, redraws only changed chunks, and skips overview/rebake entirely when no color changed.
- `_update_overview_colors() -> void` — unchanged signature; updates pixels in place via `ImageTexture.update()`.
- New: `_fill_overview_image(img: Image) -> void`, `_request_rebake() -> void`, `_run_queued_rebake() -> void`, member `_rebake_queued: bool`.
- `_hex_tile_chunk_data` (already declared at line 60, currently unused) is now populated.

**Steps**

- [x] 2.1 Populate the coord→entry map at chunk build time. In `_render_hex_map`, old (lines 598-602):

```gdscript
		# All tiles go into chunk batched _draw()
		var color: Color = Color.WHITE if tex else base_color
		if not chunk_entries.has(chunk_key):
			chunk_entries[chunk_key] = []
		chunk_entries[chunk_key].append([world_poly, color, tex, scaled_uv if tex else null])
```

new:

```gdscript
		# All tiles go into chunk batched _draw()
		var color: Color = Color.WHITE if tex else base_color
		if not chunk_entries.has(chunk_key):
			chunk_entries[chunk_key] = []
		# Direct coord -> chunk entry index (used by _update_political_overlay
		# instead of scanning ~100 entries per tile comparing polygon centers)
		_hex_tile_chunk_data[coord] = {chunk_key = chunk_key, entry_idx = chunk_entries[chunk_key].size()}
		chunk_entries[chunk_key].append([world_poly, color, tex, scaled_uv if tex else null])
```

- [x] 2.2 Replace the whole of `_update_political_overlay` (1300-1396) with:

```gdscript
func _update_political_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# Recolor chunk tile entries via the coord -> entry index map built at
	# chunk creation. Track which chunks actually changed color so unchanged
	# chunks are not redrawn and a no-op update skips the overview rebuild
	# and the full map rebake entirely.
	var dirty_chunks: Dictionary = {}
	for coord in hex_map.tiles:
		var lookup: Dictionary = _hex_tile_chunk_data.get(coord, {})
		if lookup.is_empty():
			continue
		var chunk: _HexChunkNode = _hex_chunks.get(lookup.chunk_key)
		if chunk == null:
			continue
		var entry: Array = chunk.tile_entries[lookup.entry_idx]
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var has_tex: bool = entry[2] != null
		var new_color: Color = entry[1]
		if _minimap_view_mode == 1:
			if tile.owner_faction != &"" and tile.owner_faction != &"independent":
				var fd: FactionData = DataManager.get_faction(tile.owner_faction)
				if fd:
					var pc: Color = fd.color
					pc.s = minf(pc.s * 1.4, 1.0)
					new_color = pc.lightened(0.15)
				else:
					new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
			else:
				new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
		elif _minimap_view_mode == 2:
			var cul_id: StringName = GameManager.REGION_CULTURE.get(tile.region_id, &"")
			if cul_id != &"":
				var cc: Color = CULTURE_COLORS.get(cul_id, Color(0.5, 0.5, 0.5))
				cc.s = minf(cc.s * 1.3, 1.0)
				new_color = cc.lightened(0.1)
			else:
				new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
		else:
			# Terrain view: restore original colors (with faction tint)
			var base_color: Color = Color.WHITE if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
			if tile.owner_faction != &"" and tile.owner_faction != &"independent":
				var fd2: FactionData = DataManager.get_faction(tile.owner_faction)
				if fd2:
					base_color = base_color.lerp(fd2.color, 0.12)
			new_color = base_color
		if new_color != entry[1]:
			entry[1] = new_color
			dirty_chunks[lookup.chunk_key] = true

	if dirty_chunks.is_empty():
		return  # Nothing changed — skip chunk redraws, overview rebuild, and rebake

	for chunk_key: Vector2i in dirty_chunks:
		_hex_chunks[chunk_key].queue_redraw()
	_update_overview_colors()
	_request_rebake()
```

Color-formula equivalence with the old code: mode 1 / mode 2 branches are copied verbatim from old lines 1345-1363; mode 0 reproduces old lines 1384-1390 (the old first loop's `entry[1] = Color.WHITE if has_tex` at 1316 was always overwritten by the second mode-0 loop for every tile, since every entry corresponds to exactly one tile). The old proximity match (`absf(cx - target_x) < 2.0`) mapped each tile to its own entry — the index map is the exact same mapping without the scan.

- [x] 2.3 Extract the overview pixel fill and update in place. Replace `_create_overview_sprite` (358-393) and `_update_overview_colors` (395-403) with:

```gdscript
func _create_overview_sprite() -> void:
	## Creates a low-res overview image of the map (flat terrain colors + political tint).
	## Rendered once at startup; toggled on when zoomed out for massive perf gain.
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	# Each tile gets a small block of pixels in the overview (3x3 for hex shape approx)
	var px_per_tile := 3
	var img_w: int = HexMapData.MAP_WIDTH * px_per_tile + px_per_tile
	var img_h: int = HexMapData.MAP_HEIGHT * px_per_tile + px_per_tile
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGB8)
	_fill_overview_image(img)

	_overview_sprite = Sprite2D.new()
	_overview_sprite.centered = false
	_overview_sprite.texture = ImageTexture.create_from_image(img)
	# Scale sprite so it aligns with the hex map world coordinates
	_overview_sprite.scale = Vector2(HEX_H_SPACING / float(px_per_tile), HEX_V_SPACING / float(px_per_tile))
	_overview_sprite.visible = false
	hex_map_layer.add_child(_overview_sprite)

func _fill_overview_image(img: Image) -> void:
	## Shared pixel fill for the overview sprite (create + in-place refresh).
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var px_per_tile := 3
	var img_w := img.get_width()
	var img_h := img.get_height()
	img.fill(Color(0.06, 0.05, 0.04))  # Dark background
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		# Apply slight faction tint
		if tile.owner_faction != &"" and tile.owner_faction != &"independent":
			var fd: FactionData = DataManager.get_faction(tile.owner_faction)
			if fd:
				color = color.lerp(fd.color, 0.12)
		# Map hex coords to pixel position (odd columns offset by half)
		var px: int = coord.x * px_per_tile
		var py: int = coord.y * px_per_tile + (px_per_tile / 2 if coord.x & 1 else 0)
		for dx in px_per_tile:
			for dy in px_per_tile:
				if px + dx < img_w and py + dy < img_h:
					img.set_pixel(px + dx, py + dy, color)

func _update_overview_colors() -> void:
	## Refreshes overview sprite pixels in place when political overlay changes
	## (previously freed and recreated the sprite + a new ImageTexture).
	if _overview_sprite == null:
		return
	var tex := _overview_sprite.texture as ImageTexture
	if tex == null:
		# Fallback: recreate from scratch (previous behavior)
		_overview_sprite.queue_free()
		_overview_sprite = null
		_create_overview_sprite()
		if _overview_visible:
			_overview_sprite.visible = true
		return
	var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGB8)
	_fill_overview_image(img)
	tex.update(img)
	_overview_sprite.visible = _overview_visible
```

(`ImageTexture.update()` requires same size/format — guaranteed: same map, same `FORMAT_RGB8`. End-state visibility equals `_overview_visible`, exactly as the old recreate path produced.)

- [x] 2.4 Add the rebake debounce. After `_rebake_hex_map` (482-489), add:

```gdscript
var _rebake_queued := false

func _request_rebake() -> void:
	## Coalesces multiple rebake requests in one frame into a single rebake.
	## _rebake_hex_map re-renders the whole ~5650x4350 SubViewport and does a
	## GPU readback in _finish_bake — never do that more than once per frame.
	if _rebake_queued:
		return
	_rebake_queued = true
	call_deferred("_run_queued_rebake")

func _run_queued_rebake() -> void:
	_rebake_queued = false
	_rebake_hex_map()
```

`_rebake_hex_map` keeps its existing guards (`_hex_map_viewport == null or not _hex_map_baked` → no-op, which also covers the `_ready` call at line 176 that happens before the first bake, same as today). `_update_political_overlay` is `_rebake_hex_map`'s only caller (verified), so all rebakes now flow through the debounce plus the no-change early-out.

- [x] 2.5 Parse check → no output.
- [x] 2.6 Manual smoke: launch, new game. (a) Map renders with faction tint on owned tiles as before. (b) Open minimap (M), click "Political" → map recolors to bright faction colors; click "Culture" → culture colors; click "Terrain" → original look. (c) Move a player army several hexes inside your own territory → no visible change or hitch (previously each confirmed move re-baked the map even when nothing changed). (d) Capture a neutral tile/region → tint updates as before.
- [x] 2.7 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): O(1) tile->chunk-entry lookup, change-tracked political overlay, in-place overview, debounced rebake"
```

---

### Task 3: Guard + coalesce resource-bar refresh on elderbeast moves (HIGH)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_on_elderbeast_moved` (1019-1026), new members/helpers next to it.

**Interfaces** — `_on_elderbeast_moved` signature unchanged (EventBus signal handler). New private `_queue_resource_display_update()`, `_run_queued_resource_display_update()`, member `_resource_display_refresh_queued: bool`.

Correctness argument (verified by reading): the income breakdown counts elderbeast income only for `beast.faction_id == player_id` (campaign_hud.gd:1490-1497), and a beast move changes nothing else the resource bar displays. Therefore AI-beast moves can never change any displayed number, and skipping the refresh for them is display-identical. Player-beast moves are coalesced to one deferred update per frame — the deferred call runs in the same frame before rendering, so rendered output is identical. This mirrors the AI-turn guard pattern of campaign.gd:2862-2868.

**Steps**

- [x] 3.1 Replace `_on_elderbeast_moved` (1019-1026) — old:

```gdscript
func _on_elderbeast_moved(beast_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	# Refresh resource bar (terrain income changed)
	_update_resource_display()
	# Refresh elderbeast panel if open for this beast
	if _elderbeast_panel:
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
		if beast:
			_show_elderbeast_panel(beast)
```

new:

```gdscript
var _resource_display_refresh_queued := false

func _on_elderbeast_moved(beast_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id) if GameManager.state else null
	# Refresh resource bar only for player-owned beasts: the income breakdown
	# counts elderbeast income only when beast.faction_id == player_id
	# (see _calculate_income_breakdown), so AI beast moves cannot change any
	# displayed number. Coalesce multi-hex moves to one update per frame.
	if beast and beast.faction_id == GameManager.state.player_faction_id:
		_queue_resource_display_update()
	# Refresh elderbeast panel if open for this beast
	if _elderbeast_panel and beast:
		_show_elderbeast_panel(beast)

func _queue_resource_display_update() -> void:
	if _resource_display_refresh_queued:
		return
	_resource_display_refresh_queued = true
	call_deferred("_run_queued_resource_display_update")

func _run_queued_resource_display_update() -> void:
	_resource_display_refresh_queued = false
	_update_resource_display()
```

- [x] 3.2 Parse check → no output.
- [x] 3.3 Manual smoke: launch a faction with elderbeasts (e.g., default map, non-demo). Move your own elderbeast → income labels update. End turn and watch AI turns → no per-hex stutter from AI beast movement; resource labels at the start of your next turn are correct (turn start always refreshes, line 965).
- [x] 3.4 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd
git commit -m "perf(hud): guard resource-bar refresh to player elderbeasts, coalesce per frame"
```

---

### Task 4: Coalesce army-panel rebuild during multi-hex moves (MEDIUM)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_on_army_moved` (1011-1017), read `_on_army_selected` (319-486) for context.

**Interfaces** — `_on_army_moved` signature unchanged. New `_run_queued_army_panel_refresh()`, member `_army_panel_refresh_queued: bool`.

Decision (from reading `_on_army_selected` 319-486): updating only the movement label in place is NOT provably identical — the panel's Merge button existence depends on `GameManager.get_armies_at_tile(army.hex_pos)` (line 364), which changes as the army moves. Therefore coalesce the full rebuild to once per frame via `call_deferred`; the deferred rebuild reads the selected army's final state for that frame, so the rendered panel each frame is identical to today's last-rebuild-of-the-frame.

**Steps**

- [x] 4.1 Replace `_on_army_moved` (1011-1017) — old:

```gdscript
func _on_army_moved(army_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	_check_tutorial("army_moved")
	# Refresh army panel if the moved army is selected
	var campaign: Node2D = get_parent().get_parent()
	if campaign and "selected_army_id" in campaign:
		if campaign.selected_army_id == army_id:
			_on_army_selected(army_id)
```

new:

```gdscript
var _army_panel_refresh_queued := false

func _on_army_moved(army_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	_check_tutorial("army_moved")
	# Refresh army panel if the moved army is selected — coalesced to one full
	# rebuild per frame (army_moved fires once per hex stepped; each rebuild
	# frees/recreates action rows, the unit-card grid, and the commander panel).
	var campaign: Node2D = get_parent().get_parent()
	if campaign and "selected_army_id" in campaign:
		if campaign.selected_army_id == army_id:
			if not _army_panel_refresh_queued:
				_army_panel_refresh_queued = true
				call_deferred("_run_queued_army_panel_refresh")

func _run_queued_army_panel_refresh() -> void:
	_army_panel_refresh_queued = false
	var campaign: Node2D = get_parent().get_parent()
	if campaign == null or not "selected_army_id" in campaign:
		return
	var selected: StringName = campaign.selected_army_id
	if selected != &"":
		_on_army_selected(selected)
```

(If the army is deselected before the deferred call runs, `_on_army_deselected` has already hidden the panel and the refresh is skipped — same end state as before.)

- [x] 4.2 Parse check → no output.
- [x] 4.3 Manual smoke: select a player army, right-click a destination 5+ hexes away → panel shows correct Movement `x.x / y.y` after the move, unit cards intact, Merge/Split/Disband buttons present exactly as before; no flicker during movement.
- [x] 4.4 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd
git commit -m "perf(hud): coalesce selected-army panel rebuild to once per frame during moves"
```

---

### Task 5: Radial tech tree — cached glow path + screen-space culling in `_draw` (MEDIUM)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_RadialTechTree._draw` (5712-5876), new members near line 5472, new helper.

**Interfaces** — `_draw()` unchanged externally. New inner-class members `_glow_edges_cache`, `_glow_cache_research_id`, `_glow_cache_completed_count`; new `static func _segment_fully_outside(a, b, r) -> bool`. Per-frame `queue_redraw()` in `_process` (5493-5497) is kept — the pulse animation requires it (visual requirement); culling + the cached path make each redraw cheap.

Pixel-identity argument: the parent `tree_clip` has `clip_contents = true` (line 5384), so anything drawn outside `Rect2(Vector2.ZERO, size)` is clipped and contributes no pixels. The cull rect is grown by `NODE_RADIUS + 60` (node circle 26 + unlock glow 30 + labels extend ≤48 px horizontally / ≤51 px vertically, all inside 86 px), so nothing partially visible is ever skipped. Edges are skipped only when both endpoints are beyond the same side of the grown rect — such a segment cannot intersect it. The glow-path cache is invalidated whenever `current_research_id` or `completed_research.size()` changes, which covers every way `_find_researched_path`'s result can change (it depends only on those plus static prerequisites).

**Steps**

- [x] 5.1 Add members after line 5472 (`var _positions_built: bool = false`):

```gdscript
	# Cached researched-glow path — _find_researched_path only changes when
	# current research or the completed set changes, not per frame.
	var _glow_edges_cache: Dictionary = {}
	var _glow_cache_research_id: StringName = &"__unset__"
	var _glow_cache_completed_count: int = -1
```

- [x] 5.2 Add the segment-cull helper after `_to_tree` (line 5503):

```gdscript
	static func _segment_fully_outside(a: Vector2, b: Vector2, r: Rect2) -> bool:
		# True only when the segment provably cannot intersect r
		# (both endpoints beyond the same side).
		if a.x < r.position.x and b.x < r.position.x:
			return true
		if a.x > r.end.x and b.x > r.end.x:
			return true
		if a.y < r.position.y and b.y < r.position.y:
			return true
		if a.y > r.end.y and b.y > r.end.y:
			return true
		return false
```

- [x] 5.3 In `_draw` (5712-5876), make three surgical edits:

(a) Replace the glow-path build (old lines 5744-5749):

```gdscript
		# Build glow path (completed chain to current research)
		var glow_edges: Dictionary = {}
		if fs.current_research_id != &"":
			var path := _find_researched_path(fs)
			for i in range(path.size() - 1):
				glow_edges[str(path[i]) + "->" + str(path[i + 1])] = true
```

with:

```gdscript
		# Build glow path (completed chain to current research) — cached across
		# frames, invalidated when research state changes
		if fs.current_research_id != _glow_cache_research_id \
				or fs.completed_research.size() != _glow_cache_completed_count:
			_glow_cache_research_id = fs.current_research_id
			_glow_cache_completed_count = fs.completed_research.size()
			_glow_edges_cache.clear()
			if fs.current_research_id != &"":
				var path := _find_researched_path(fs)
				for i in range(path.size() - 1):
					_glow_edges_cache[str(path[i]) + "->" + str(path[i + 1])] = true
		var glow_edges: Dictionary = _glow_edges_cache
```

(b) Add the cull rect right after `var current_tech: int = ...` (line 5720):

```gdscript
		# Off-screen culling: parent tree_clip has clip_contents = true, so
		# skipping fully-clipped nodes/edges changes no pixels. Grown to cover
		# node circle + unlock glow + name labels (all within 86 px of center).
		var cull_rect := Rect2(Vector2.ZERO, size).grow(NODE_RADIUS + 60.0)
```

(c) In the connections loop, after `var from_screen := _to_screen(_node_positions[prereq])` (line 5765), insert:

```gdscript
				if _segment_fully_outside(from_screen, to_screen, cull_rect):
					continue
```

(d) In the nodes loop, after `var pos := _to_screen(_node_positions.get(research_id, Vector2.ZERO))` (line 5803), insert:

```gdscript
			if not cull_rect.has_point(pos):
				continue
```

(The hover tooltip block at 5874-5876 stays untouched; a hovered node is under the cursor and therefore inside the rect.)

- [x] 5.4 Parse check → no output.
- [x] 5.5 Manual smoke: open Research. (a) Pulsing gold path from completed chain to current research still animates. (b) Start a research → glow path updates immediately. (c) Pan the tree far to one side and zoom in — off-screen branches disappear/reappear at the edges with no popping inside the visible area; labels at the very edge are not cut off early. (d) Hover a node → cyan hover path + tooltip unchanged.
- [x] 5.6 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd
git commit -m "perf(hud): cache tech-tree glow path, cull off-screen nodes/edges in _draw"
```

---

### Task 6: Minimap drag — viewport-only update per mouse motion (MEDIUM)

**Files**
- `scenes/campaign/campaign.gd` — `_minimap_move_camera` (5181-5192).

**Interfaces** — signature unchanged.

Verified: camera movement changes only the viewport indicator rectangle. `_update_minimap_viewport_only()` (5136-5147) duplicates `_minimap_content_cache` (written by every full `_update_minimap` at 5130) and redraws only the rectangle — exactly what the drag needs — and already falls back to `_update_minimap()` when the cache is null. Content changes (armies, fog) are still picked up by the 0.5 s dirty-flag timer in `_process` (263-275), same as today.

**Steps**

- [x] 6.1 In `_minimap_move_camera`, replace the last line (5192) — old:

```gdscript
	camera.position = Vector2(ratio_x * map_pixel_w, ratio_y * map_pixel_h)
	camera._clamp_position()
	_update_minimap()
```

new:

```gdscript
	camera.position = Vector2(ratio_x * map_pixel_w, ratio_y * map_pixel_h)
	camera._clamp_position()
	# Camera move changes only the viewport rectangle — army/shard/fog content
	# is unchanged, so skip duplicating the fogged cache and rescanning armies.
	_update_minimap_viewport_only()
```

- [x] 6.2 Parse check → no output.
- [x] 6.3 Manual smoke: open minimap (M), click-drag across it → camera follows smoothly, white viewport rectangle tracks the drag, army dots/fog unchanged during the drag and still refresh within ~0.5 s after content changes (e.g., end turn).
- [x] 6.4 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): minimap drag uses viewport-only update instead of full rebuild"
```

---

### Task 7: Skip army-marker rebuild for recruits during AI turns (MEDIUM)

**Files**
- `scenes/campaign/campaign.gd` — `_on_unit_recruited` (3959-3966).

**Interfaces** — signature unchanged.

Verified: player turn start already calls `_create_army_markers()` unconditionally (line 3777), which fully rebuilds when the army-id set changed — so any army created during AI turns gets its marker at the start of the player turn. This mirrors the existing AI-turn deferral pattern (`_on_army_moved` 2862-2868, `_on_region_ownership_changed` 2915-2919, `_on_turn_started` else-branch 3795-3798). Player recruiting only happens on the player's turn, so the player-facing path is unchanged.

**Steps**

- [x] 7.1 Replace `_on_unit_recruited` (3959-3966) — old:

```gdscript
func _on_unit_recruited(city_id: StringName, unit_data_id: StringName, _army_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"recruit_start")
		var unit_data: UnitData = DataManager.get_unit(unit_data_id)
		var uname: String = unit_data.display_name if unit_data else str(unit_data_id)
		_show_notification(uname + " recruited in " + city.get_display_name())
	_create_army_markers()
```

new:

```gdscript
func _on_unit_recruited(city_id: StringName, unit_data_id: StringName, _army_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"recruit_start")
		var unit_data: UnitData = DataManager.get_unit(unit_data_id)
		var uname: String = unit_data.display_name if unit_data else str(unit_data_id)
		_show_notification(uname + " recruited in " + city.get_display_name())
	# During AI turns, skip the marker rebuild — player turn start calls
	# _create_army_markers() (line ~3777), matching the deferral pattern of the
	# neighboring handlers (_on_army_moved / _on_region_ownership_changed).
	if not TurnManager.is_player_turn:
		return
	_create_army_markers()
```

- [x] 7.2 Parse check → no output.
- [x] 7.3 Manual smoke: recruit a unit in a player city → marker/garrison state updates immediately as before. End turn, let several AI turns pass → no per-recruit hitching; at your next turn start all AI armies (incl. newly recruited garrisons, mostly fog-hidden anyway) have markers.
- [x] 7.4 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): defer army-marker rebuild for AI-turn recruits to player turn start"
```

---

### Task 8: Settlement placement preview — gate on hovered hex change (MEDIUM)

**Files**
- `scenes/campaign/campaign.gd` — `_unhandled_input` settlement branch (2295-2301), `_on_settlement_placement_requested` (4556+), `_cancel_settlement_placement` (4603-4612), new member near line 103.

**Interfaces** — unchanged signatures; new member `_last_settlement_preview_hex: Vector2i`.

Verified: `_show_settlement_preview` positions the panel from the **hex** center (`_hex_to_pixel(hex_coord)`, line 4751), not the raw mouse position, so two motion events over the same hex produce an identical panel — skipping the second is display-identical. This mirrors the existing `_last_hover_hex` gating at 2393-2400.

**Steps**

- [x] 8.1 Add member after line 103 (`var _settlement_preview_panel: PanelContainer = null`):

```gdscript
var _last_settlement_preview_hex := Vector2i(-9999, -9999)  # Gate preview rebuilds to hex changes
```

- [x] 8.2 In `_unhandled_input`, replace the settlement mouse-motion block (2295-2301) — old:

```gdscript
		if event is InputEventMouseMotion:
			var world_pos := get_global_mouse_position()
			var hex_coord := _pixel_to_hex(world_pos)
			_update_region_hover(world_pos)
			if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				_show_settlement_preview(hex_coord)
		return
```

new:

```gdscript
		if event is InputEventMouseMotion:
			var world_pos := get_global_mouse_position()
			var hex_coord := _pixel_to_hex(world_pos)
			_update_region_hover(world_pos)
			if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				# Preview panel content and position depend only on the hex —
				# rebuild it (free + recreate + income preview calc) only when
				# the hovered hex actually changes (mirrors _last_hover_hex).
				if hex_coord != _last_settlement_preview_hex:
					_last_settlement_preview_hex = hex_coord
					_show_settlement_preview(hex_coord)
		return
```

- [x] 8.3 In `_on_settlement_placement_requested`, after line 4561 (`_settlement_placement_mode = true`), add:

```gdscript
	_last_settlement_preview_hex = Vector2i(-9999, -9999)
```

- [x] 8.4 In `_cancel_settlement_placement`, after line 4604 (`_settlement_placement_mode = false`), add:

```gdscript
	_last_settlement_preview_hex = Vector2i(-9999, -9999)
```

- [x] 8.5 Parse check → no output.
- [x] 8.6 Manual smoke: open your capital's city panel, start "Found Settlement". Sweep the mouse over green tiles → preview panel appears/updates per hex exactly as before (terrain name, +income lines, total), disappears over invalid tiles; wiggling the mouse inside one hex causes no flicker. Right-click cancels; re-entering placement mode shows previews again.
- [x] 8.7 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): rebuild settlement preview only when hovered hex changes"
```

---

### Task 9: Hoist loop invariants out of `get_available_buildings` (MEDIUM)

**Files**
- `scripts/systems/campaign/city_system.gd` — `get_available_buildings` (1150-1241).

**Interfaces** — `get_available_buildings(city: CityState, include_slot_blocked: bool = false) -> Array[BuildingData]` unchanged.

Verified: the 246-iteration loop mutates nothing (it only reads `city`/`DataManager`/faction state and appends to `result`), so `city.get_available_building_slots()` and per-terrain `get_valid_tiles_for_building_terrain` results are loop-invariant. `get_valid_tiles_for_building` (1085-1089) returns `[city.building_tiles[building.upgrades_from]]` (always non-empty) for placed upgrades, else the terrain result — the replacement below reproduces exactly that emptiness semantics. `get_valid_tiles_for_building_terrain` (1063-1083) internally calls `city.get_occupied_tiles()`; memoizing per distinct `required_terrain` reduces that from 246 calls to ≤ number of distinct terrains.

**Steps**

- [x] 9.1 In `get_available_buildings`, insert immediately before the loop (before line 1187 `var result: Array[BuildingData] = []`):

```gdscript
	# Loop invariants hoisted out of the 246-building scan: the loop mutates
	# nothing, so slots and per-terrain valid-tile results cannot change inside it.
	var available_slots := city.get_available_building_slots()
	var valid_tiles_by_terrain: Dictionary = {}  # required_terrain (int) -> Array[Vector2i]
```

- [x] 9.2 Replace the valid-tile check (old lines 1229-1231):

```gdscript
		# Skip if no valid adjacent tile available
		if get_valid_tiles_for_building(city, building).is_empty():
			continue
```

with:

```gdscript
		# Skip if no valid adjacent tile available (identical result to
		# get_valid_tiles_for_building, with the terrain query memoized)
		var has_valid_tile: bool
		if building.upgrades_from != &"" and city.building_tiles.has(building.upgrades_from):
			has_valid_tile = true  # upgrade reuses the existing building's tile
		else:
			var terrain_key: int = building.required_terrain
			if not valid_tiles_by_terrain.has(terrain_key):
				valid_tiles_by_terrain[terrain_key] = get_valid_tiles_for_building_terrain(city, terrain_key)
			has_valid_tile = not (valid_tiles_by_terrain[terrain_key] as Array).is_empty()
		if not has_valid_tile:
			continue
```

- [x] 9.3 Replace the slot check (old line 1234):

```gdscript
			if city.get_available_building_slots() <= 0 and not include_slot_blocked:
```

with:

```gdscript
			if available_slots <= 0 and not include_slot_blocked:
```

- [x] 9.4 Parse check → no output.
- [x] 9.5 Manual smoke: open a player city panel → the buildable-buildings list is unchanged (compare a few entries before/after this task, including at least one upgrade and one terrain-restricted building); queue a building → it disappears from the list; a full-slot city offers only upgrades.
- [x] 9.6 Commit:

```powershell
git add scripts/systems/campaign/city_system.gd
git commit -m "perf(city): hoist slot/terrain-tile invariants out of get_available_buildings loop"
```

---

### Task 10: Research panel refresh keeps the tech-tree instance (LOW)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_refresh_research_panel` (5329-5451), new members near line 84 (`var _research_panel: PanelContainer`), new `refresh_state()` on `_RadialTechTree`.

**Interfaces** — `_refresh_research_panel()` unchanged signature. New members `_research_tree_clip: Control`, `_research_tree: _RadialTechTree`; new inner-class method `refresh_state()`.

Verified: the radial layout (`_calculate_positions` + `_resolve_overlaps`) depends only on `DataManager.research`, `DataManager.buildings`, and `faction_id` — all static during a campaign — so it never needs recomputing. All research *state* (completed/in-progress/affordable colors, glow path) is read live from `FactionState` inside `_draw`, which already runs every frame; Task 5's glow cache self-invalidates on state change. So `refresh_state()` only needs a redraw. Accepted, intended behavior change (sanctioned by this task's purpose): the user's pan/zoom is no longer reset by per-turn refreshes while the panel is open, nor on reopen — layout/colors/labels are pixel-identical otherwise.

**Steps**

- [x] 10.1 Add members after line 84 (`var _research_panel: PanelContainer`):

```gdscript
var _research_tree_clip: Control = null       # Persistent tech-tree clip container
var _research_tree: _RadialTechTree = null    # Persistent tree control (keeps pan/zoom + layout)
```

- [x] 10.2 Add to `_RadialTechTree` (after `_ready`, line 5491):

```gdscript
		func refresh_state() -> void:
			# Re-read research state without recomputing layout or touching
			# pan/zoom. Node/edge state is read live from FactionState in
			# _draw(); the cached glow path invalidates itself on change.
			queue_redraw()
```

- [x] 10.3 In `_refresh_research_panel`, make three edits:

(a) Replace the child-clearing loop (old 5330-5333):

```gdscript
	var margin: MarginContainer = _research_panel.get_child(0)
	var vbox: VBoxContainer = margin.get_node("ResearchVBox")
	for child in vbox.get_children():
		child.queue_free()
```

with:

```gdscript
	var margin: MarginContainer = _research_panel.get_child(0)
	var vbox: VBoxContainer = margin.get_node("ResearchVBox")
	# Rebuild header/footer rows but keep the tech-tree control: its layout
	# depends only on static data and recreating it reset the user's pan/zoom
	# and re-ran the 16-pass O(n^2) overlap resolver on every refresh.
	for child in vbox.get_children():
		if child == _research_tree_clip:
			continue
		vbox.remove_child(child)
		child.queue_free()
```

(b) After `vbox.add_child(header)` (old line 5380), add:

```gdscript
	vbox.move_child(header, 0)
```

(c) Replace the tree construction (old 5382-5394):

```gdscript
	# Draggable tech tree (fills remaining space)
	var tree_clip := Control.new()
	tree_clip.clip_contents = true
	tree_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tree_clip)

	var tree_control := _RadialTechTree.new()
	tree_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree_control.faction_id = parent_faction_id
	tree_control.player_faction_id = player_id
	tree_control.hud_ref = self
	tree_clip.add_child(tree_control)
```

with:

```gdscript
	# Draggable tech tree (fills remaining space) — created once, reused on
	# every subsequent refresh (preserves pan/zoom and the computed layout)
	if _research_tree_clip == null or not is_instance_valid(_research_tree_clip):
		_research_tree_clip = Control.new()
		_research_tree_clip.clip_contents = true
		_research_tree_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_research_tree_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(_research_tree_clip)
		_research_tree = _RadialTechTree.new()
		_research_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
		_research_tree.faction_id = parent_faction_id
		_research_tree.player_faction_id = player_id
		_research_tree.hud_ref = self
		_research_tree_clip.add_child(_research_tree)
	else:
		_research_tree.refresh_state()
	vbox.move_child(_research_tree_clip, 1)
```

(The footer rows built after this point are appended after the tree, i.e., indices 2+, matching the original header → tree → footer order.)

- [x] 10.4 Parse check → no output.
- [x] 10.5 Manual smoke: open Research, pan/zoom somewhere, click a researchable node to start research → panel refreshes (header/footer update, node turns pulsing) and the view does NOT recenter. Close and reopen, end a turn with the panel open → progress numbers update, view preserved, footer Cancel/Invest rows correct.
- [x] 10.6 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd
git commit -m "perf(hud): reuse tech-tree control across research panel refreshes"
```

---

### Task 11: Cache city "has available action" per city with event invalidation (LOW)

**Files**
- `scenes/campaign/campaign.gd` — `_city_has_available_action` (2188-2192), `_refresh_city_markers` (2143-2150), `_on_building_completed` (3927-3941), `_on_building_demolished` (3943-3953), `_on_city_captured` (3888-3903), `building_queued` lambda (line 219), new member near line 66.

**Interfaces** — `_city_has_available_action(city: CityState) -> bool` unchanged. New `_invalidate_city_action_cache()`, member `_city_action_cache: Dictionary`.

Invalidation set = exactly the events that can change the boolean *and* currently trigger a glow recompute: turn start (covers research completion, city growth, corruption drift — via `_city_markers_dirty` → `_refresh_city_markers`), `building_completed`, `building_demolished`, `city_captured`, and the HUD `building_queued` signal. The live `build_queue` check stays outside the cache. Clearing inside `_refresh_city_markers` (which only runs when `_city_markers_dirty`) guarantees any dirty-marker path recomputes fresh, exactly like today; the cache only ever serves the redundant second call at player turn start (line 3770 rebuild + line 3772 direct call) and same-frame duplicates with no intervening event.

**Steps**

- [x] 11.1 Add member after line 66 (`var _city_markers_dirty := true ...`):

```gdscript
var _city_action_cache: Dictionary = {}  # city_id -> bool (get_available_buildings > 0); cleared on building/turn events
```

- [x] 11.2 Replace `_city_has_available_action` (2188-2192) — old:

```gdscript
func _city_has_available_action(city: CityState) -> bool:
	if not city.build_queue.is_empty():
		return false
	var available := GameManager.city_system.get_available_buildings(city)
	return available.size() > 0
```

new:

```gdscript
func _city_has_available_action(city: CityState) -> bool:
	if not city.build_queue.is_empty():
		return false
	if _city_action_cache.has(city.city_id):
		return _city_action_cache[city.city_id]
	var available := GameManager.city_system.get_available_buildings(city)
	var result := available.size() > 0
	_city_action_cache[city.city_id] = result
	return result

func _invalidate_city_action_cache() -> void:
	_city_action_cache.clear()
```

- [x] 11.3 In `_refresh_city_markers` (2143-2150), after `_city_markers_dirty = false` (line 2146), add:

```gdscript
	_invalidate_city_action_cache()
```

- [x] 11.4 Add `_invalidate_city_action_cache()` as the **first line** of `_on_building_completed` (3927), `_on_building_demolished` (3943), and `_on_city_captured` (3888) bodies.
- [x] 11.5 In the `building_queued` lambda (line 219) — old:

```gdscript
		hud.building_queued.connect(func(): _create_building_tile_markers(); _fog_dirty = true)
```

new:

```gdscript
		hud.building_queued.connect(func():
			_invalidate_city_action_cache()
			_create_building_tile_markers()
			_fog_dirty = true)
```

- [x] 11.6 Parse check → no output.
- [x] 11.7 Manual smoke: player cities with buildable options show the green build glow at turn start; queue a building → glow disappears (queue non-empty); when it completes → glow returns/updates; capture a city → its glow state appears next refresh, same as before.
- [x] 11.8 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): cache city available-action flag with event-based invalidation"
```

---

### Task 12: Cache the research status label node (LOW)

**Files**
- `scenes/campaign/campaign_hud.gd` — `_update_research_status_label` (5289-5299), member near line 84.

**Interfaces** — signature unchanged; new member `_research_status_label: Label`.

**Steps**

- [x] 12.1 Add member next to the Task 10 members:

```gdscript
var _research_status_label: Label = null  # Cached "TopBar/.../ResearchStatusLabel" lookup
```

- [x] 12.2 Replace `_update_research_status_label` (5289-5299) — old:

```gdscript
func _update_research_status_label() -> void:
	var lbl := get_node_or_null("TopBar/HBoxContainer/ResearchStatusLabel")
	if lbl == null:
		return
```

new (rest of body unchanged):

```gdscript
func _update_research_status_label() -> void:
	if _research_status_label == null or not is_instance_valid(_research_status_label):
		_research_status_label = get_node_or_null("TopBar/HBoxContainer/ResearchStatusLabel") as Label
	var lbl := _research_status_label
	if lbl == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs and fs.current_research_id != &"":
		var data: ResearchData = DataManager.get_research(fs.current_research_id)
		if data:
			lbl.text = "%s (%d/%d)" % [data.display_name, fs.research_progress, data.research_time]
			return
	lbl.text = ""
```

- [x] 12.3 Parse check → no output. Manual smoke: start a research → top-bar label shows `Name (x/y)`; completes → clears.
- [x] 12.4 Commit:

```powershell
git add scenes/campaign/campaign_hud.gd
git commit -m "perf(hud): cache research status label node lookup"
```

---

### Task 13: Minimap texture — update in place (LOW)

**Files**
- `scenes/campaign/campaign.gd` — `_update_minimap` (5073-5134, texture set at 5134), `_update_minimap_viewport_only` (5136-5147, texture set at 5147), new helper.

**Interfaces** — new private `_set_minimap_texture(img: Image) -> void`; callers unchanged.

**Steps**

- [x] 13.1 Add helper after `_update_minimap_viewport_only` (5147):

```gdscript
func _set_minimap_texture(img: Image) -> void:
	## Reuses the existing ImageTexture via update() when dimensions/format
	## match (every frame after the first); creates it otherwise.
	var tex := _minimap_image.texture as ImageTexture
	if tex and tex.get_width() == img.get_width() and tex.get_height() == img.get_height() \
			and tex.get_format() == img.get_format():
		tex.update(img)
	else:
		_minimap_image.texture = ImageTexture.create_from_image(img)
```

- [x] 13.2 Replace line 5134 and line 5147 — both currently:

```gdscript
	_minimap_image.texture = ImageTexture.create_from_image(img)
```

with:

```gdscript
	_set_minimap_texture(img)
```

- [x] 13.3 Parse check → no output. Manual smoke: open minimap → renders; end turns / drag → dots, fog and viewport rect all keep updating.
- [x] 13.4 Commit:

```powershell
git add scenes/campaign/campaign.gd
git commit -m "perf(map): update minimap ImageTexture in place instead of recreating"
```

---

### Task 14: Cache HUD reference in camera `_is_mouse_over_ui` (LOW)

**Files**
- `scenes/campaign/campaign_camera.gd` — `_is_mouse_over_ui` (115-126), member near line 16.

**Interfaces** — signature unchanged; new member `_hud_cache: Control`.

**Steps**

- [x] 14.1 Add member after line 16 (`var _zoom_focus_screen := Vector2.ZERO`):

```gdscript
var _hud_cache: Control = null  # Cached ../UILayer/HUD lookup (resolved lazily, revalidated if freed)
```

- [x] 14.2 Replace `_is_mouse_over_ui` (115-126) — old:

```gdscript
func _is_mouse_over_ui() -> bool:
	# Check if the mouse is hovering over any visible UI panel
	var hud := get_node_or_null("../UILayer/HUD")
	if hud == null:
		return false
```

new (loop body unchanged):

```gdscript
func _is_mouse_over_ui() -> bool:
	# Check if the mouse is hovering over any visible UI panel
	if _hud_cache == null or not is_instance_valid(_hud_cache):
		_hud_cache = get_node_or_null("../UILayer/HUD") as Control
	var hud := _hud_cache
	if hud == null:
		return false
	var mouse_pos: Vector2 = hud.get_global_mouse_position()
	# Only check top-level visible panels (not deep-iterating)
	for child in hud.get_children():
		if child is Control and child.visible and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if child.get_global_rect().has_point(mouse_pos):
				return true
	return false
```

- [x] 14.3 Parse check → no output. Manual smoke: mouse-wheel over the map zooms; wheel over an open panel (city panel/minimap) does not zoom the camera; middle/right-drag panning works; return from a battle scene (campaign reloads) still works (lazy revalidation handles the new HUD instance).
- [x] 14.4 Commit:

```powershell
git add scenes/campaign/campaign_camera.gd
git commit -m "perf(camera): cache HUD node lookup in _is_mouse_over_ui"
```

---

## Self-review notes
- Every "verify by reading" item from the findings was resolved by reading the cited code before writing the task (return shape of `calculate_city_income`; hover-staleness argument + the 32 `_update_resource_display` call sites incl. per-turn refresh; elderbeast income player-only; `_hex_tile_chunk_data` declared-but-unused; `_rebake_hex_map` single caller + existing `_bake_frames_remaining` countdown with no same-frame guard; `_update_minimap_viewport_only` coverage; player-turn-start marker rebuild at 3777; tech-tree layout static-data-only + `clip_contents`; `get_available_buildings` loop purity; `new_game` synchronous init for the headless test). The single remaining uncertainty is flagged inline in Task 1.6 (autoload global resolution in `-s` scripts, with a concrete fallback).
- Tasks are independent except: Task 1 must precede its test file usage (same task); Task 5 and Task 10 both touch `_RadialTechTree` but different regions (implement in order to avoid merge friction); Task 3/4/12 touch campaign_hud.gd in disjoint regions.

### Critical Files for Implementation
- D:\Dokumente\Gamedesign\Beyond\FractureWars\FractureWars\scenes\campaign\campaign_hud.gd
- D:\Dokumente\Gamedesign\Beyond\FractureWars\FractureWars\scenes\campaign\campaign.gd
- D:\Dokumente\Gamedesign\Beyond\FractureWars\FractureWars\scripts\systems\campaign\city_system.gd
- D:\Dokumente\Gamedesign\Beyond\FractureWars\FractureWars\scenes\campaign\campaign_camera.gd
- D:\Dokumente\Gamedesign\Beyond\FractureWars\FractureWars\tests\test_income_breakdown_equivalence.gd (new)
