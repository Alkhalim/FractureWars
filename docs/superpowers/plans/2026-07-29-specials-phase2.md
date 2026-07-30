# Specials (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 8 faction-affinity Special resources from `docs/special_resources_design.md`: rare map deposits owned via their region, exploited through universal Extractor buildings, granting percentage identity modifiers (doubled for the affinity faction), leasable to other factions through a new RESOURCE_LEASE treaty with AI valuation.

**Architecture:** A new all-static `SpecialResourceSystem` (sibling of `BountySystem`) owns the 8-type table, the deterministic scatter pass (runs BEFORE bounty scatter so rare deposits get first pick of tiles), region/extractor state queries, and modifier-strength resolution. Yields are carried by the Extractor buildings' ordinary `income_bonus` (zero new income code); only the percentage modifiers need hooks. Leases are ordinary `TreatyInstance`s with a new enum value, ticked in `process_treaties`.

**Design refinement vs the doc (deliberate, announce in the doc at the end):** ALL special effects (yield + modifier) require the Extractor built — the doc's "automatic yield, extractor doubles" is replaced by "extractor activates everything". Reasons: (1) battle-relevant modifiers (Deepiron) stay inert in a fresh `new_game`, so the battle-determinism baselines cannot be affected; (2) "build to exploit" matches the Landmark rule and gives leases a clear infrastructure prerequisite.

**Tech Stack:** Godot 4.4 GDScript, headless SceneTree test scripts.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; test shape `& "<godot>" --headless --path . -s res://tests/<name>.gd`; startup "SCRIPT ERROR: Compile Error" noise is benign — only printed PASSED/FAILED verdict lines count; autoloads in tests via `root.get_node("/root/...")`.
- Map generation stays deterministic with ZERO RNG — coordinate hashes only.
- `Enums.TreatyType` gets `RESOURCE_LEASE` APPENDED AT THE END — never reorder existing values (saved treaties store ints).
- Save compat: new tile field `special_id` defaults via `Dictionary.get(key, "")` on deserialize.
- `scatter_specials(map)` runs BEFORE `BountySystem.scatter_bounties(map)` in BOTH generator paths; bounty scatter must skip tiles that already carry a `special_id` (one resource per tile).
- Battle-sim edits must be inert when no faction has an extracted special (fresh `new_game` state) — do NOT regenerate `tests/baselines/`.
- Scene-attached scripts (`campaign.gd`, `campaign_hud.gd`) only compile when the scene loads — verify via the windowed screenshot harness and watch stdout for SCRIPT ERROR naming those files.
- Terrain ints: 0=PLAINS 1=FOREST 2=MOUNTAINS 3=DESERT 4=SWAMP 5=WETLANDS 6=TUNDRA 7=SHARD_WASTES 8=WATER 9=JUNGLE. Resource ints: 0=GOLD 1=IRON 2=TECHNOLOGY 3=FOOD 4=SHARD_ESSENCE 5=WOOD 6=CAPTIVES.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Special table, tile field, deterministic scatter

**Files:**
- Create: `scripts/systems/campaign/special_resource_system.gd`
- Modify: `scripts/systems/campaign/hex_map_data.gd` (TileState: add `special_id` after `bounty_id`)
- Modify: `scripts/core/game_state.gd` (`serialize_hex_map`/`deserialize_hex_map`: one line each)
- Modify: `scripts/utils/map_generator.gd:120` and `:161` (insert scatter call BEFORE the bounty call)
- Modify: `scripts/systems/campaign/bounty_system.gd` (`scatter_bounties`: skip tiles with `special_id != &""`)
- Test: `tests/test_special_resources.gd` (new)

**Interfaces:**
- Produces: `SpecialResourceSystem.SPECIAL_TYPES: Dictionary` (id → `{name: String, terrains: Array[int], strength: float, affinity: Array[StringName], extractor_id: StringName, modifier_text: String}`); `SpecialResourceSystem.scatter_specials(map: HexMapData) -> void`; `TileState.special_id: StringName`; `SpecialResourceSystem.MIN_PER_TYPE := 1`, `MAX_PER_TYPE := 3`.

- [ ] **Step 1: Write the failing test** — create `tests/test_special_resources.gd`:

```gdscript
extends SceneTree
## Tests for tier-2 Special resources (Phase 2, docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_special_resources.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var map = _gm.state.hex_map

	# ── Scatter: all 8 types present, 1-3 each, valid terrain, no tile overlap ──
	var counts := {}
	var placed: Array[Vector2i] = []
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.special_id == &"":
			continue
		placed.append(coord)
		counts[tile.special_id] = counts.get(tile.special_id, 0) + 1
		var def: Dictionary = SpecialResourceSystem.SPECIAL_TYPES.get(tile.special_id, {})
		_check(not def.is_empty(), "special %s exists in table" % tile.special_id)
		_check(int(tile.terrain) in def.get("terrains", []), "special %s on allowed terrain (%d)" % [tile.special_id, tile.terrain])
		_check(tile.bounty_id == &"", "no bounty stacked on special tile %s" % coord)
	for type_id in SpecialResourceSystem.SPECIAL_TYPES:
		var c: int = counts.get(type_id, 0)
		_check(c >= 1 and c <= 3, "type %s spawns 1-3 times (got %d)" % [type_id, c])

	# ── Determinism ──
	var fp := _fingerprint(map)
	_gm.new_game(&"empire")
	_check(_fingerprint(_gm.state.hex_map) == fp, "special scatter deterministic across new_game")

	# ── Serialization roundtrip + old-save compat ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fp, "special_id survives save/load roundtrip")
	for key in saved:
		saved[key].erase("special_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].special_id != &"":
			any = true
	_check(not any, "old saves without special_id load empty")

	if _fails == 0:
		print("SPECIALS TEST PASSED")
		quit(0)
	else:
		print("SPECIALS TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].special_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].special_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
```

- [ ] **Step 2: Run — expect parse failure / FAILED** (`SpecialResourceSystem` and `special_id` missing).

- [ ] **Step 3: Tile field + serializer lines**

`hex_map_data.gd` TileState, after `bounty_id`:
```gdscript
	var special_id: StringName = &"" # tier-2 Special resource deposit (special_resources_design)
```
`game_state.gd` `serialize_hex_map` per-tile dict: `"special_id": str(tile.special_id),` — `deserialize_hex_map`: `tile.special_id = StringName(tile_data.get("special_id", ""))`.

- [ ] **Step 4: Create `scripts/systems/campaign/special_resource_system.gd`**

```gdscript
class_name SpecialResourceSystem
extends RefCounted
## Tier-2 "Special" resources (Phase 2 of docs/special_resources_design.md).
## All static. 8 rare faction-affinity deposits owned via their REGION and
## activated by a universal Extractor building. Yields ride the extractor's
## normal income_bonus; this class owns the table, the scatter pass, and the
## modifier/lease state queries used by the percentage hooks.

const MIN_PER_TYPE := 1
const MAX_PER_TYPE := 3
const MIN_SPACING := 8   # hexes between any two special deposits

## strength = the identity modifier's base magnitude (doubled for affinity).
## Interpretation is per-type at the hook site (pct fraction or flat pct).
const SPECIAL_TYPES := {
	&"moonsilver": {name = "Moonsilver", terrains = [6, 2], strength = 10.0, affinity = [&"moonspear"], extractor_id = &"extractor_moonsilver", modifier_text = "-10% recruit cost for heavy units"},
	&"sunstone": {name = "Sunstone", terrains = [3], strength = 0.05, affinity = [&"sunblessed"], extractor_id = &"extractor_sunstone", modifier_text = "+5% cultural building income"},
	&"deepiron": {name = "Deepiron", terrains = [2], strength = 0.05, affinity = [&"cinderguard"], extractor_id = &"extractor_deepiron", modifier_text = "+5% army defense in owned territory"},
	&"heartwood": {name = "Heartwood", terrains = [1, 9], strength = 0.05, affinity = [&"gladehost"], extractor_id = &"extractor_heartwood", modifier_text = "+5% food income"},
	&"shardglass": {name = "Shardglass", terrains = [7], strength = 0.10, affinity = [&"ivoryscar", &"shardhorde"], extractor_id = &"extractor_shardglass", modifier_text = "+10% arcane research speed"},
	&"saffron_reeds": {name = "Saffron Reeds", terrains = [0, 5], strength = 0.15, affinity = [&"empire"], extractor_id = &"extractor_saffron", modifier_text = "+15% gold from trade deals"},
	&"bloodsalt": {name = "Bloodsalt", terrains = [4, 5], strength = 0.25, affinity = [&"skulloath", &"tainted_jade"], extractor_id = &"extractor_bloodsalt", modifier_text = "+25% captive conversion"},
	&"stormcrystal": {name = "Stormcrystal", terrains = [2], strength = 0.05, affinity = [&"thunderswarm"], extractor_id = &"extractor_stormcrystal", modifier_text = "+5% army movement"},
}

static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass. Runs BEFORE BountySystem.scatter_bounties (rare deposits get
## first pick; bounties skip occupied tiles). All 8 types spawn 1-3 deposits.
static func scatter_specials(map: HexMapData) -> void:
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	var type_ids: Array = SPECIAL_TYPES.keys()
	# Pass 1: one guaranteed deposit per type — walk tiles with a per-type
	# hash offset so types land in different map areas.
	for t_idx in type_ids.size():
		var type_id: StringName = type_ids[t_idx]
		var def: Dictionary = SPECIAL_TYPES[type_id]
		var start := _hash(t_idx * 101 + 13, 4242) % coords.size()
		for k in coords.size():
			var coord: Vector2i = coords[(start + k) % coords.size()]
			if _try_place(map, coord, type_id, def, placed):
				break
	# Pass 2: hash-gated extra deposits up to MAX_PER_TYPE.
	var counts := {}
	for p in placed:
		var tid: StringName = map.tiles[p].special_id
		counts[tid] = counts.get(tid, 0) + 1
	for coord in coords:
		var h := _hash(coord.x + 7, coord.y - 7)
		if h % 37 != 0:
			continue
		var type_id: StringName = type_ids[(h / 37) % type_ids.size()]
		if counts.get(type_id, 0) >= MAX_PER_TYPE:
			continue
		if _try_place(map, coord, type_id, SPECIAL_TYPES[type_id], placed):
			counts[type_id] = counts.get(type_id, 0) + 1

static func _try_place(map: HexMapData, coord: Vector2i, type_id: StringName, def: Dictionary, placed: Array[Vector2i]) -> bool:
	var tile: HexMapData.TileState = map.tiles[coord]
	if tile.terrain == Enums.TerrainType.WATER or tile.special_id != &"":
		return false
	if tile.region_id == &"":
		return false # deposits must belong to a region (ownership model)
	if not (int(tile.terrain) in def.terrains):
		return false
	for p in placed:
		if HexHelper.hex_distance(coord, p) < MIN_SPACING:
			return false
	tile.special_id = type_id
	placed.append(coord)
	return true
```

- [ ] **Step 5: Wire the generator + bounty skip**

`map_generator.gd`: insert `SpecialResourceSystem.scatter_specials(map)` IMMEDIATELY BEFORE the existing `BountySystem.scatter_bounties(map)` line in BOTH `generate_demo_hex_map` (~:120) and `generate_hex_map` (~:161).

`bounty_system.gd` `scatter_bounties`, in the tile loop next to the WATER skip:
```gdscript
		if tile.special_id != &"":
			continue # specials scattered first; one resource per tile
```

- [ ] **Step 6: Run tests** — `test_special_resources.gd` → `SPECIALS TEST PASSED`; also `test_bounty_system.gd` → `BOUNTY TEST PASSED` (bounty determinism check compares two runs under the new order — still passes). If a type can't reach MIN_PER_TYPE on the demo map (small), relax `MIN_SPACING` to 6 rather than dropping the guarantee.

- [ ] **Step 7: Commit** — `feat(resources): special deposits table, tile field and scatter` + footer.

---

### Task 2: Extractors — BuildingData gate, 8 building files, state queries

**Files:**
- Modify: `scripts/resources/building_data.gd` (add field after `settlement_only`)
- Modify: `scripts/systems/campaign/city_system.gd` `get_available_buildings` (~:1401-1411, new gate after `requires_research` check) and `start_building` (~:1480, same guard)
- Create: `data/buildings/extractor_{moonsilver,sunstone,deepiron,heartwood,shardglass,saffron,bloodsalt,stormcrystal}.tres` (8 files)
- Modify: `scripts/systems/campaign/special_resource_system.gd` (append queries)
- Test: `tests/test_special_resources.gd` (append)

**Interfaces:**
- Produces: `BuildingData.requires_region_resource: StringName`; `SpecialResourceSystem.special_in_region(region_id: StringName) -> StringName` (deposit type or `&""`); `deposits_in_region(region_id) -> Array[Vector2i]`; `region_has_extractor(region_id: StringName) -> bool`; `extracted_specials_of_faction(faction_id: StringName) -> Array[StringName]` (one entry PER extracted deposit region — duplicates count for flagship later); `has_modifier(faction_id: StringName, special_id: StringName) -> bool` (extracted OR leased-in; lease part returns false until Task 5 wires `_lease_grants`); `modifier_strength(faction_id, special_id) -> float` (0.0 / base / ×2 affinity via `GameManager.MINOR_FACTION_PARENTS` parent resolution); `describe(special_id) -> String`.

- [ ] **Step 1: Append failing test cases** (before the PASSED block; `_gm.new_game(&"empire")` first to reset):

```gdscript
	# ── Region/extractor plumbing ──
	_gm.new_game(&"empire")
	var map3 = _gm.state.hex_map
	# Find any special deposit and its region
	var dep_hex := Vector2i(-1, -1)
	for coord in map3.tiles:
		if map3.tiles[coord].special_id != &"":
			dep_hex = coord
			break
	var dep_tile = map3.get_tile(dep_hex)
	var dep_type: StringName = dep_tile.special_id
	var dep_region: StringName = dep_tile.region_id
	_check(SpecialResourceSystem.special_in_region(dep_region) == dep_type, "special_in_region finds the deposit")
	_check(not SpecialResourceSystem.region_has_extractor(dep_region), "no extractor at game start")

	# Craft: give the player a city in that region with the extractor built
	var pcity: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			pcity = _gm.state.cities[cid]
			break
	var old_region := pcity.region_id
	pcity.region_id = dep_region
	var extractor_id: StringName = SpecialResourceSystem.SPECIAL_TYPES[dep_type].extractor_id
	pcity.buildings.append(extractor_id)
	# Make empire the region owner: set all region tiles' owner
	for rc in map3.get_region_tiles(dep_region):
		map3.get_tile(rc).owner_faction = &"empire"
	map3._region_owner_cache.clear()
	_check(SpecialResourceSystem.region_has_extractor(dep_region), "extractor detected in region city")
	_check(dep_type in SpecialResourceSystem.extracted_specials_of_faction(&"empire"), "faction extracts the special")
	_check(SpecialResourceSystem.has_modifier(&"empire", dep_type), "has_modifier true when extracted")
	var base_strength: float = SpecialResourceSystem.SPECIAL_TYPES[dep_type].strength
	var expect := base_strength * 2.0 if &"empire" in SpecialResourceSystem.SPECIAL_TYPES[dep_type].affinity else base_strength
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", dep_type), expect), "modifier_strength respects affinity doubling")
	_check(SpecialResourceSystem.modifier_strength(&"skulloath", dep_type) == 0.0, "no modifier without extraction")
	# Extractor gating: available only in the deposit's region
	var avail := _gm.city_system.get_available_buildings(pcity)
	var found_extractor := false
	for b in avail:
		if b.id == extractor_id:
			found_extractor = true
	# Already built -> not offered again; remove and re-check availability
	pcity.buildings.erase(extractor_id)
	avail = _gm.city_system.get_available_buildings(pcity)
	for b in avail:
		if b.id == extractor_id:
			found_extractor = true
	_check(found_extractor, "extractor offered in deposit region")
	pcity.region_id = old_region
	avail = _gm.city_system.get_available_buildings(pcity)
	var offered_outside := false
	for b in avail:
		if b.id == extractor_id:
			offered_outside = true
	_check(not offered_outside, "extractor NOT offered outside deposit region")
	pcity.region_id = dep_region
	pcity.buildings.append(extractor_id)
```

- [ ] **Step 2: Run — expect FAILs.**

- [ ] **Step 3: BuildingData field + gate**

`building_data.gd`: `@export var requires_region_resource: StringName = &"" # tier-2 Special deposit required in the city's region`.

`city_system.gd` `get_available_buildings`, immediately after the `requires_research` check:
```gdscript
		# Extractors: only buildable where the city's region holds the deposit
		if building.requires_region_resource != &"":
			if SpecialResourceSystem.special_in_region(city.region_id) != building.requires_region_resource:
				continue
```
`start_building` (~:1480), same guard with `return false`.

- [ ] **Step 4: The 8 extractor .tres files** — identical shape, universal (`faction_id = &""`), category economic, capital level 2. Full example (`data/buildings/extractor_moonsilver.tres`); repeat for all 8 with the listed name/income/requires values:

```
[gd_resource type="Resource" script_class="BuildingData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/building_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"extractor_moonsilver"
display_name = "Moonsilver Mine"
description = "Deep shafts chasing veins of lunar silver. Whoever works this region's deposit arms their soldiers with it."
faction_id = &""
category = &"economic"
build_cost = {0: 120, 1: 40}
build_time = 3
income_bonus = {1: 12}
required_capital_level = 2
requires_region_resource = &"moonsilver"
upkeep_cost = {0: 3}
```
Per-type values: sunstone → "Sunstone Quarry", `income_bonus = {0: 12}`; deepiron → "Deepiron Bore", `{1: 20}`; heartwood → "Heartwood Lodge", `{5: 16}`; shardglass → "Shardglass Refinery", `{4: 4}`; saffron (`id extractor_saffron`, `requires_region_resource = &"saffron_reeds"`) → "Saffron Terraces", `{0: 16}`; bloodsalt → "Bloodsalt Works", `{3: 8}`; stormcrystal → "Stormcrystal Spire", `{2: 8}`. Descriptions: one flavorful sentence each, written fresh.

- [ ] **Step 5: Append queries to `special_resource_system.gd`**

```gdscript
static func deposits_in_region(region_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map = GameManager.state.hex_map
	if map == null or region_id == &"":
		return result
	for coord in map.get_region_tiles(region_id):
		var tile = map.get_tile(coord)
		if tile and tile.special_id != &"":
			result.append(coord)
	return result

static func special_in_region(region_id: StringName) -> StringName:
	var deps := deposits_in_region(region_id)
	if deps.is_empty():
		return &""
	return GameManager.state.hex_map.get_tile(deps[0]).special_id

static func region_has_extractor(region_id: StringName) -> bool:
	var special: StringName = special_in_region(region_id)
	if special == &"":
		return false
	var extractor_id: StringName = SPECIAL_TYPES[special].extractor_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id == region_id and city.buildings.has(extractor_id):
			return true
	return false

## One entry per extracted deposit-region; duplicates count (flagship effects).
static func extracted_specials_of_faction(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	for region_id in fs.owned_regions:
		var special: StringName = special_in_region(region_id)
		if special != &"" and region_has_extractor(region_id):
			result.append(special)
	return result

## Task 5 replaces the lease stub with real treaty lookups.
static func _lease_grants(_faction_id: StringName, _special_id: StringName) -> bool:
	return false

static func has_modifier(faction_id: StringName, special_id: StringName) -> bool:
	if special_id in extracted_specials_of_faction(faction_id):
		return true
	return _lease_grants(faction_id, special_id)

static func modifier_strength(faction_id: StringName, special_id: StringName) -> float:
	if not has_modifier(faction_id, special_id):
		return 0.0
	var def: Dictionary = SPECIAL_TYPES[special_id]
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	return def.strength * 2.0 if parent_fid in def.affinity else def.strength

static func describe(special_id: StringName) -> String:
	var def: Dictionary = SPECIAL_TYPES.get(special_id, {})
	return def.get("modifier_text", "") if not def.is_empty() else ""
```

- [ ] **Step 6: Run — `SPECIALS TEST PASSED`. Step 7: Commit** — `feat(resources): extractor buildings and special-resource state queries` + footer.

---

### Task 3: Economy modifier hooks (sunstone, heartwood, moonsilver, bloodsalt, shardglass)

**Files:**
- Modify: `scripts/systems/campaign/city_system.gd` — `calculate_city_income` building-loop (~:235-244, cultural %) ; `_generate_income` food_pct block (~:105) ; `start_recruitment` discount block (~:1562)
- Modify: `scripts/autoloads/turn_manager.gd` — captive conversion (~:3739 `conv_rate` block)
- Modify: `scripts/systems/campaign/research_system.gd` — `process_research` (~:86-93)
- Test: `tests/test_special_resources.gd` (append)

**Interfaces:**
- Consumes: `modifier_strength(faction_id, special_id) -> float` from Task 2.

- [ ] **Step 1: Append failing test cases** (test state from Task 2 still has empire extracting `dep_type` — craft SPECIFIC types instead for precision; before the PASSED block):

```gdscript
	# ── Economy hooks: craft a sunstone+heartwood extraction for empire ──
	# Reuse dep_region ownership; overwrite the deposit type per check.
	dep_tile.special_id = &"sunstone"
	pcity.buildings.erase(extractor_id)
	pcity.buildings.append(&"extractor_sunstone")
	var mod_sun := SpecialResourceSystem.modifier_strength(&"empire", &"sunstone")
	_check(is_equal_approx(mod_sun, 0.05), "sunstone modifier 5% for non-affinity empire")
	var inc_before: Dictionary = _gm.city_system.calculate_city_income(pcity)
	pcity.buildings.erase(&"extractor_sunstone")
	var inc_no: Dictionary = _gm.city_system.calculate_city_income(pcity)
	# With a cultural building present, income with modifier >= income without
	# (exact delta depends on the city's cultural buildings; assert monotonicity)
	_check(inc_before.get(0, 0) >= inc_no.get(0, 0), "sunstone never reduces gold income")
	pcity.buildings.append(&"extractor_sunstone")

	# Moonsilver heavy discount via recruit path
	dep_tile.special_id = &"moonsilver"
	pcity.buildings.erase(&"extractor_sunstone")
	pcity.buildings.append(&"extractor_moonsilver")
	var heavy_ud := UnitData.new()
	heavy_ud.tags = ["infantry", "heavy"]
	var light_ud := UnitData.new()
	light_ud.tags = ["infantry", "light"]
	_check(SpecialResourceSystem.recruit_discount_for(&"empire", heavy_ud) == 10, "moonsilver discounts heavy 10%")
	_check(SpecialResourceSystem.recruit_discount_for(&"empire", light_ud) == 0, "no discount for non-heavy")

	# Shardglass arcane research speed: bonus function query
	dep_tile.special_id = &"shardglass"
	pcity.buildings.erase(&"extractor_moonsilver")
	pcity.buildings.append(&"extractor_shardglass")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"shardglass"), 0.10), "shardglass 10% for empire")
	# restore
	dep_tile.special_id = dep_type
	pcity.buildings.erase(&"extractor_shardglass")
```

- [ ] **Step 2: Run — expect FAILs** (`recruit_discount_for` missing).

- [ ] **Step 3: Implement**

Append to `special_resource_system.gd`:
```gdscript
## Moonsilver: percentage discount for heavy-tagged units (int pct).
static func recruit_discount_for(faction_id: StringName, ud: UnitData) -> int:
	if not ud.tags.has("heavy"):
		return 0
	return int(modifier_strength(faction_id, &"moonsilver"))
```

`city_system.gd` `calculate_city_income` building loop, before `income[res_type] += bonus`:
```gdscript
			# Sunstone: +% income from cultural buildings (special_resources_design)
			if building.category == &"cultural":
				var sun_mod := SpecialResourceSystem.modifier_strength(city.faction_id, &"sunstone")
				if sun_mod > 0.0:
					bonus = int(bonus * (1.0 + sun_mod))
```

`city_system.gd` `_generate_income`, next to the existing `food_pct` block:
```gdscript
	# Heartwood: +% food income
	var heart_mod := SpecialResourceSystem.modifier_strength(faction_id, &"heartwood")
	if heart_mod > 0.0 and total_income.has(Enums.ResourceType.FOOD):
		total_income[Enums.ResourceType.FOOD] = int(total_income[Enums.ResourceType.FOOD] * (1.0 + heart_mod))
```
(Anchor on the real local variable holding aggregated income in `_generate_income` — read the function; if income is credited per-city rather than via a total dict, apply the multiplier to the city's food component at the equivalent point.)

`city_system.gd` `start_recruitment` discount block:
```gdscript
	total_discount_pct += SpecialResourceSystem.recruit_discount_for(city.faction_id, unit_data)
```

`turn_manager.gd` captive conversion (~:3739), after `conv_rate` is computed:
```gdscript
	# Bloodsalt: +% captive conversion (affinity: skulloath/tainted_jade doubled)
	conv_rate += SpecialResourceSystem.modifier_strength(fs.faction_data_id, &"bloodsalt")
```
(Read the block: if `conv_rate` feeds `camp_mult` only when `> 0.0`, ensure the bloodsalt add happens before that branch.)

`research_system.gd` `process_research`, after `fs.research_progress += 1`:
```gdscript
	# Shardglass: +% progress on arcane techs (fractional accumulation)
	if data.research_category == &"arcane":
		var glass_mod := SpecialResourceSystem.modifier_strength(faction_id, &"shardglass")
		if glass_mod > 0.0:
			fs.research_speed_accumulator += glass_mod
```

- [ ] **Step 4: Run** — `SPECIALS TEST PASSED` + regression `test_bounty_system.gd`, `test_siege_pressure.gd`, `test_income_breakdown_equivalence.gd` all PASSED. NOTE: if the income-equivalence test embeds a reference copy of the income math, the sunstone hook may need mirroring there — read that test if it fails and mirror the hook in its reference implementation (that is the test's documented pattern).

- [ ] **Step 5: Commit** — `feat(resources): economy modifier hooks for extracted specials` + footer.

---

### Task 4: Military/movement/trade hooks (deepiron, stormcrystal, saffron_reeds)

**Files:**
- Modify: `scripts/systems/battle/battle_simulator_v3.gd` `_create_formation` — after the per-faction elif chain (~:663, after the forsaken block, before the empire anti-mage block)
- Modify: `scripts/autoloads/turn_manager.gd` movement reset (~:352-372)
- Modify: `scripts/systems/campaign/diplomacy_system.gd` `_execute_trade` (~:727)
- Test: `tests/test_special_resources.gd` (append)

**Interfaces:**
- Consumes: `modifier_strength`. NOTE battle-sim constraint: the deepiron branch must be a no-op when `modifier_strength` returns 0.0 (fresh new_game) — do not touch anything else in the sim.

- [ ] **Step 1: Append failing tests**

```gdscript
	# ── Stormcrystal movement + saffron trade hooks (query-level) ──
	dep_tile.special_id = &"stormcrystal"
	pcity.buildings.append(&"extractor_stormcrystal")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"stormcrystal"), 0.05), "stormcrystal 5%")
	dep_tile.special_id = &"saffron_reeds"
	pcity.buildings.erase(&"extractor_stormcrystal")
	pcity.buildings.append(&"extractor_saffron")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"saffron_reeds"), 0.30), "saffron 15% doubled for empire affinity")
	pcity.buildings.erase(&"extractor_saffron")
	dep_tile.special_id = dep_type
	# Deepiron inert at fresh state (battle-determinism guard)
	_gm.new_game(&"empire")
	for f_id in _gm.state.faction_states:
		_check(SpecialResourceSystem.extracted_specials_of_faction(f_id).is_empty(), "fresh game: no faction extracts anything (%s)" % f_id)
```

- [ ] **Step 2: Run — the saffron affinity check fails until hooks exist? No — modifier_strength exists already; these mostly pass. The REAL new behavior is the three hook sites; they're integration code verified by inertness + regression. Run and confirm which cases fail; proceed.**

- [ ] **Step 3: Implement the three hooks**

`battle_simulator_v3.gd`, after the faction-mechanic elif chain (immediately after the forsaken block, still inside `if fs:`):
```gdscript
		# ── Deepiron (tier-2 Special): +% defense when fighting in own territory ──
		var deep_mod := SpecialResourceSystem.modifier_strength(ud.faction_id, &"deepiron")
		if deep_mod > 0.0:
			var own_tile = GameManager.state.hex_map.get_tile(_battle_hex_pos) if GameManager.state.hex_map else null
			if own_tile and own_tile.owner_faction == ud.faction_id:
				f.defense += int(f.defense * deep_mod)
```

`turn_manager.gd` movement reset — after the base `army.movement_remaining` is set from `get_max_movement()` (read the block; multiply before road/building additions):
```gdscript
		# Stormcrystal: +% army movement
		var storm_mod := SpecialResourceSystem.modifier_strength(faction_id, &"stormcrystal")
		if storm_mod > 0.0:
			army.movement_remaining *= (1.0 + storm_mod)
```

`diplomacy_system.gd` `_execute_trade`, before the resource writes: for each leg that is GOLD (`give_res == 0` from `fs_a`, `recv_res == 0` toward `fs_a`), the RECEIVER of gold with the saffron modifier gains extra:
```gdscript
	# Saffron Reeds: +% gold received from trade deals
	if give_res == Enums.ResourceType.GOLD:
		var saff_b := SpecialResourceSystem.modifier_strength(treaty.faction_b, &"saffron_reeds")
		if saff_b > 0.0:
			give_amt = int(give_amt * (1.0 + saff_b))
	if recv_res == Enums.ResourceType.GOLD:
		var saff_a := SpecialResourceSystem.modifier_strength(treaty.faction_a, &"saffron_reeds")
		if saff_a > 0.0:
			recv_amt = int(recv_amt * (1.0 + saff_a))
```
(The bonus inflates what the receiver gets; the giver still pays the base amount — implement by splitting the transfer amounts: giver pays `give_amt_base`, receiver receives inflated. Read the four write lines and split the variables accordingly: `fs_a.resources[give_res] -= give_amt_base` but `fs_b.resources[give_res] += give_amt`.)

- [ ] **Step 4: Run full battery** — `test_special_resources.gd`, `test_bounty_system.gd`, `test_siege_pressure.gd`, `test_battle_determinism.gd` (EXPECTED: the same PRE-EXISTING divergence documented in `.superpowers/sdd/progress.md` — v2 line 2 / v3 line 12 with identical values as before this branch; verify the diverging line numbers/values did NOT change, which proves the deepiron hook is inert), `tmp_econ_sim.gd -- 7 15` (no new SCRIPT ERRORs).

- [ ] **Step 5: Commit** — `feat(resources): deepiron, stormcrystal and saffron modifier hooks` + footer.

---

### Task 5: RESOURCE_LEASE treaty — propose, evaluate, tick, break, AI

**Files:**
- Modify: `scripts/enums/enums.gd:94` TreatyType — append `RESOURCE_LEASE` at the END
- Modify: `scripts/systems/campaign/diplomacy_system.gd` — `process_treaties` (~:645), `break_treaty` match (~:829), `would_accept_proposal` (~:1075), `_execute_ai_diplomacy_inner` (~:1251 war-score + lease initiation)
- Modify: `scripts/systems/campaign/special_resource_system.gd` — replace `_lease_grants` stub; add lease helpers
- Test: `tests/test_special_resources.gd` (append)

**Interfaces:**
- Produces: `DiplomacySystem.propose_resource_lease(owner: StringName, lessee: StringName, special_id: StringName, gold_per_turn: int, duration: int) -> Dictionary` (`{accepted: bool, reason: String}`; creates the treaty when accepted or when both parties are scripted/test callers — evaluation only applies when the DECIDING party is AI); treaty shape: `treaty_type = Enums.TreatyType.RESOURCE_LEASE`, `faction_a = owner`, `faction_b = lessee`, `turns_remaining = duration`, `terms = {special_id, gold_per_turn}`; `SpecialResourceSystem.lease_for_special(owner: StringName, special_id: StringName) -> TreatyInstance` (or null — exclusivity check); `leased_in_specials(faction_id) -> Array[Dictionary]` (`{special_id, from, turns_remaining}` for UI).

- [ ] **Step 1: Append failing tests**

```gdscript
	# ── Resource lease lifecycle ──
	_gm.new_game(&"empire")
	var map4 = _gm.state.hex_map
	var dhex := Vector2i(-1, -1)
	for coord in map4.tiles:
		if map4.tiles[coord].special_id != &"":
			dhex = coord
			break
	var dtile = map4.get_tile(dhex)
	var dtype: StringName = dtile.special_id
	var dregion: StringName = dtile.region_id
	var owner_city: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			owner_city = _gm.state.cities[cid]
			break
	owner_city.region_id = dregion
	owner_city.buildings.append(SpecialResourceSystem.SPECIAL_TYPES[dtype].extractor_id)
	for rc in map4.get_region_tiles(dregion):
		map4.get_tile(rc).owner_faction = &"empire"
	map4._region_owner_cache.clear()
	var efs: FactionState = _gm.state.faction_states[&"empire"]
	if not (dregion in efs.owned_regions):
		efs.owned_regions.append(dregion)

	var res: Dictionary = _gm.diplomacy_system.propose_resource_lease(&"empire", &"gladehost", dtype, 10, 8)
	_check(res.accepted, "AI lessee accepts a cheap lease of a useful special (reason: %s)" % res.get("reason", ""))
	_check(SpecialResourceSystem.has_modifier(&"gladehost", dtype), "lease grants the modifier to the lessee")
	_check(SpecialResourceSystem.lease_for_special(&"empire", dtype) != null, "lease registered for exclusivity")
	var res2: Dictionary = _gm.diplomacy_system.propose_resource_lease(&"empire", &"moonspear", dtype, 10, 8)
	_check(not res2.accepted, "second lease of same special rejected (exclusive)")

	# Tick: lessee pays owner gold_per_turn
	var gl_fs: FactionState = _gm.state.faction_states[&"gladehost"]
	var e_gold: int = efs.resources.get(0, 0)
	var g_gold: int = gl_fs.resources.get(0, 0)
	_gm.diplomacy_system.process_treaties(&"empire")
	_check(efs.resources.get(0, 0) == e_gold + 10, "owner received lease payment")
	_check(gl_fs.resources.get(0, 0) == g_gold - 10, "lessee paid lease payment")

	# War cancels the lease
	_gm.diplomacy_system.declare_war(&"empire", &"gladehost")
	_check(not SpecialResourceSystem.has_modifier(&"gladehost", dtype), "war cancels the lease")
```

- [ ] **Step 2: Run — FAILs on missing functions.**

- [ ] **Step 3: Implement**

`enums.gd`: append `RESOURCE_LEASE` as the LAST TreatyType value.

`special_resource_system.gd` — replace the stub + add helpers:
```gdscript
static func _lease_grants(faction_id: StringName, special_id: StringName) -> bool:
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_b == faction_id \
				and t.terms.get("special_id", &"") == special_id:
			return true
	return false

static func lease_for_special(owner: StringName, special_id: StringName) -> TreatyInstance:
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_a == owner \
				and t.terms.get("special_id", &"") == special_id:
			return t
	return null

static func leased_in_specials(faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_b == faction_id:
			result.append({special_id = t.terms.get("special_id", &""), from = t.faction_a, turns_remaining = t.turns_remaining})
	return result
```

`diplomacy_system.gd` — new function (place near `propose_trade`; follow the file's treaty-creation idiom — read how `propose_trade` builds and registers a `TreatyInstance` and mirror id generation):
```gdscript
## Owner leases a Special's modifier to lessee for gold_per_turn, exclusive.
func propose_resource_lease(owner: StringName, lessee: StringName, special_id: StringName, gold_per_turn: int, duration: int) -> Dictionary:
	if GameManager.get_relation(owner, lessee) == Enums.FactionRelation.WAR:
		return {accepted = false, reason = "At war."}
	if not (special_id in SpecialResourceSystem.extracted_specials_of_faction(owner)):
		return {accepted = false, reason = "Owner does not extract this resource."}
	if SpecialResourceSystem.lease_for_special(owner, special_id) != null:
		return {accepted = false, reason = "Already leased to another faction."}
	# AI decision when the lessee is AI (player lessee decides via UI)
	if lessee != GameManager.state.player_faction_id:
		var affinity: bool = GameManager.MINOR_FACTION_PARENTS.get(lessee, lessee) in SpecialResourceSystem.SPECIAL_TYPES[special_id].affinity
		var max_pay := 20 if affinity else 12
		var lessee_fs: FactionState = GameManager.state.faction_states.get(lessee)
		if gold_per_turn > max_pay:
			return {accepted = false, reason = "Too expensive."}
		if lessee_fs == null or lessee_fs.resources.get(Enums.ResourceType.GOLD, 0) < gold_per_turn * 3:
			return {accepted = false, reason = "Cannot afford it."}
	var treaty := TreatyInstance.new()
	treaty.treaty_id = StringName("lease_%s_%s_%d" % [owner, special_id, GameManager.state.current_turn])
	treaty.treaty_type = Enums.TreatyType.RESOURCE_LEASE
	treaty.faction_a = owner
	treaty.faction_b = lessee
	treaty.turns_remaining = duration
	treaty.terms = {special_id = special_id, gold_per_turn = gold_per_turn}
	GameManager.state.diplomacy_state.treaties[treaty.treaty_id] = treaty
	modify_standing(owner, lessee, 3, "Resource lease")
	return {accepted = true, reason = "Lease agreed."}
```

`process_treaties` — add a branch beside `TRADE_DEAL`:
```gdscript
	elif treaty.treaty_type == Enums.TreatyType.RESOURCE_LEASE:
		var pay: int = treaty.terms.get("gold_per_turn", 0)
		var lessee_fs: FactionState = GameManager.state.faction_states.get(treaty.faction_b)
		var owner_fs: FactionState = GameManager.state.faction_states.get(treaty.faction_a)
		var still_extracted: bool = treaty.terms.get("special_id", &"") in SpecialResourceSystem.extracted_specials_of_faction(treaty.faction_a)
		if lessee_fs == null or owner_fs == null or lessee_fs.resources.get(Enums.ResourceType.GOLD, 0) < pay or not still_extracted:
			to_expire.append(treaty_id) # defaulted or supply lost -> lease ends
		else:
			lessee_fs.resources[Enums.ResourceType.GOLD] -= pay
			owner_fs.resources[Enums.ResourceType.GOLD] = owner_fs.resources.get(Enums.ResourceType.GOLD, 0) + pay
```
(Anchor on the function's real local names — `to_expire` etc.)

`break_treaty` match: add `Enums.TreatyType.RESOURCE_LEASE: penalty = -10`.
(War already cancels via `_cancel_treaties_between` — no change needed; the test verifies.)

`would_accept_proposal`: add case `"resource_lease"` delegating to the same affinity/price logic as `propose_resource_lease`'s AI branch (extract that logic into a small private `_evaluate_lease_as_lessee(lessee, special_id, gold_per_turn) -> bool` used by both).

`_execute_ai_diplomacy_inner` — two additions:
```gdscript
	# War-score: covet extracted deposits of our affinity resource
	# (inside the war_score computation, add:)
	for aff_special in _affinity_specials_of(faction_id):
		if aff_special in SpecialResourceSystem.extracted_specials_of_faction(other_id):
			war_score += 10.0
```
with helper `_affinity_specials_of(faction_id) -> Array[StringName]` (scan SPECIAL_TYPES affinity lists for the parent faction). And lease initiation (AI→AI only; frequency-gated like other actions in this function — read the surrounding cadence pattern):
```gdscript
	# Seek a lease of our affinity special if someone else extracts it
	for aff_special in _affinity_specials_of(faction_id):
		if SpecialResourceSystem.has_modifier(faction_id, aff_special):
			continue
		for other_fid in GameManager.state.faction_states:
			if other_fid == faction_id or other_fid == GameManager.state.player_faction_id:
				continue
			if aff_special in SpecialResourceSystem.extracted_specials_of_faction(other_fid) \
					and SpecialResourceSystem.lease_for_special(other_fid, aff_special) == null \
					and GameManager.get_relation(faction_id, other_fid) != Enums.FactionRelation.WAR:
				propose_resource_lease(other_fid, faction_id, aff_special, 14, 10)
				break
```

- [ ] **Step 4: Run** — `SPECIALS TEST PASSED` + `test_save_roundtrip.gd` (treaty with new enum value roundtrips) + `tmp_econ_sim.gd -- 7 20` (AI lease initiation exercised, no SCRIPT ERRORs).

- [ ] **Step 5: Commit** — `feat(diplomacy): RESOURCE_LEASE treaty with AI valuation and war-score coveting` + footer.

---

### Task 6: UI — deposit markers, resource-bar merge, diplomacy lease actions

**Files:**
- Modify: `scenes/campaign/campaign.gd` — special-deposit markers (parallel to `_create_bounty_markers` at :2534) + `_update_bounty_hover` extension (:5032)
- Modify: `scenes/campaign/campaign_hud.gd` — `_update_bounty_bar_display`/`_on_bounty_bar_hover` (:9181/:9188) + `_build_faction_detail` offers (:3853-3925) + confirm handler (~:4700)
- Modify: `tests/tmp_screenshot_bounties.gd` (extend with a specials phase)

**Interfaces:**
- Consumes: `SPECIAL_TYPES`, `deposits_in_region`, `special_in_region`, `region_has_extractor`, `extracted_specials_of_faction`, `leased_in_specials`, `lease_for_special`, `describe`, `propose_resource_lease`.

- [ ] **Step 1: Map markers** — in `_create_bounty_markers` (rename NOT allowed — add a sibling loop inside the same function so one call renders both): after the bounty loop, iterate tiles with `special_id != &""` and build a DISTINCT marker: larger (radius 9) diamond (`Polygon2D` with 4 points `[Vector2(0,-9), Vector2(9,0), Vector2(0,9), Vector2(-9,0)]`), purple-tinted rim `Color(0.65, 0.45, 0.85, 0.95)`, dark bg, 2-letter glyph (`name.left(2)`), positioned at the TILE CENTER (`_hex_to_pixel(coord)`) not the corner (specials dominate their tile per the design). Same fog visibility handling (`marker.visible = GameManager.explored_tiles.has(coord)`) and registration in `_bounty_markers` so `_refresh_bounty_marker_visibility` covers them.

- [ ] **Step 2: Hover** — extend `_update_bounty_hover`: if the tile has `special_id`, show (instead of bounty text):
```gdscript
		var sdef: Dictionary = SpecialResourceSystem.SPECIAL_TYPES[tile.special_id]
		var owner_id: StringName = GameManager.state.get_region_owner(tile.region_id)
		var owner_txt := "Unowned region"
		if owner_id != &"":
			var ofd: FactionData = DataManager.get_faction(owner_id)
			owner_txt = "Region: " + (ofd.display_name if ofd else String(owner_id))
		var extract_txt := "Extractor built" if SpecialResourceSystem.region_has_extractor(tile.region_id) else "Requires %s (build in a city of this region)" % DataManager.get_building(sdef.extractor_id).display_name
		var lease_txt := ""
		if owner_id != &"":
			var lease := SpecialResourceSystem.lease_for_special(owner_id, tile.special_id)
			if lease:
				var lfd: FactionData = DataManager.get_faction(lease.faction_b)
				lease_txt = "\nLeased to %s (%d turns)" % [lfd.display_name if lfd else String(lease.faction_b), lease.turns_remaining]
		_bounty_tooltip.get_node("Text").text = "%s (Special)\n%s\n%s\n%s%s" % [sdef.name, SpecialResourceSystem.describe(tile.special_id), owner_txt, extract_txt, lease_txt]
```
(gated on explored, same as bounties; keep the existing bounty path untouched otherwise).

- [ ] **Step 3: Resource bar** — `_update_bounty_bar_display` becomes a combined readout:
```gdscript
	var pid := GameManager.state.player_faction_id
	var n_b := BountySystem.bounties_of_faction(pid).size()
	var n_s := SpecialResourceSystem.extracted_specials_of_faction(pid).size()
	var n_l := SpecialResourceSystem.leased_in_specials(pid).size()
	bounty_bar_label.text = "  |  Resources: %d" % (n_b + n_s + n_l)
	bounty_bar_label.visible = (n_b + n_s + n_l) > 0
```
`_on_bounty_bar_hover` gains two sections after the bounty lines: "Specials:" (each extracted special as `"<name> (<describe>)"`, plus `" — leased to X"` when `lease_for_special` hits) and "Leased in:" (each from `leased_in_specials` as `"<name> — via <faction> (%d turns)"`). Keep the dark-chip style; reuse `SpecialResourceSystem.SPECIAL_TYPES[id].name`.

- [ ] **Step 4: Diplomacy actions** — in `_build_faction_detail`'s offers assembly: append after the gift entry:
```gdscript
	# Resource leases (tier-2 Specials)
	var my_specials := SpecialResourceSystem.extracted_specials_of_faction(GameManager.state.player_faction_id)
	for sp in my_specials:
		if SpecialResourceSystem.lease_for_special(GameManager.state.player_faction_id, sp) == null:
			offers.append({id = "lease_out_%s" % sp, label = "Lease out %s (10g/turn, 10 turns)" % SpecialResourceSystem.SPECIAL_TYPES[sp].name})
	var their_specials := SpecialResourceSystem.extracted_specials_of_faction(faction_id)
	for sp in their_specials:
		if SpecialResourceSystem.lease_for_special(faction_id, sp) == null:
			offers.append({id = "lease_in_%s" % sp, label = "Request lease of %s (pay 14g/turn, 10 turns)" % SpecialResourceSystem.SPECIAL_TYPES[sp].name})
```
Confirm handler: for selected ids starting `lease_out_` → `propose_resource_lease(player, faction_id, sp, 10, 10)`; `lease_in_` → `propose_resource_lease(faction_id, player, sp, 14, 10)` BUT the owner is AI — add the owner-side AI decision: accept when `gold_per_turn >= 8 + int(_get_faction_greed(faction_id) * 4.0)` and standing >= 0 (implement inside `propose_resource_lease`: when the OWNER is AI and the lessee is the player, run that check before creating the treaty). Append the result line to the existing `results` feedback array (match the trade result pattern).

- [ ] **Step 5: Screenshot verification** — extend `tests/tmp_screenshot_bounties.gd`: pan the camera to a special deposit (search `special_id != &""`), disable fog, screenshot `user://win_special_marker.png` with the hover tooltip forced (`_campaign._update_bounty_hover(dep_coord)`); run windowed; controller inspects. Also re-run `-s res://tests/test_special_resources.gd` headless (still PASSED).

- [ ] **Step 6: Commit** — `feat(resources): special deposit markers, resource-bar merge and lease diplomacy UI` + footer.

---

### Task 7: Regression sweep + doc status

**Files:** `docs/special_resources_design.md`

- [ ] **Step 1:** Run and record verdicts: `test_special_resources.gd`, `test_bounty_system.gd`, `test_faction_ai_flavor.gd`, `test_siege_pressure.gd`, `test_save_roundtrip.gd`, `test_income_breakdown_equivalence.gd`, `test_battle_determinism.gd` (expect ONLY the documented pre-existing divergence — same lines/values as recorded in `.superpowers/sdd/progress.md`), `tmp_econ_sim.gd -- 7 20` (no new SCRIPT ERRORs; look for AI lease lines), windowed `tmp_screenshot_windows.gd` + `tmp_screenshot_bounties.gd`.
- [ ] **Step 2:** Update `docs/special_resources_design.md`: mark Phase 2 implemented (same style as Phase 1); document the design refinement (extractor activates yield AND modifier — replaces "automatic yield, extractor doubles"); note deferred items: AI→player lease offers, flagship effects at 2+ affinity deposits (NOT implemented this phase — moved to follow-up), affinity-reachability placement fairness.
- [ ] **Step 3:** Commit — `docs(resources): mark specials phase 2 implemented` + footer.

---

## Self-Review

- **Spec coverage:** placement (T1), extractors + region gating (T2), all 8 identity modifiers (T3+T4), affinity doubling (T2 `modifier_strength`), Access lease + exclusivity + war cancel + AI valuation + war-score coveting + AI initiation (T5), UI markers/tooltip/bar/diplomacy actions (T6). NOT in scope (documented in T7): flagship effects at 2+ deposits, AI→player lease offers, per-faction reachability fairness in placement — deliberate cuts to keep the phase shippable; flagged for the user.
- **Placeholder scan:** the "anchor on real local names" notes in T3/T4/T5/T6 are execution-time lookups of live identifiers, with the behavioral code fully specified; no TBDs.
- **Type consistency:** `modifier_strength(faction_id, special_id) -> float` used identically in T3/T4; lease helpers of T5 match the `_lease_grants` stub contract from T2; `extractor_id` values in SPECIAL_TYPES (T1) match the 8 .tres ids (T2), including the shortened `extractor_saffron` for `saffron_reeds`.
