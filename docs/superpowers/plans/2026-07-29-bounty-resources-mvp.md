# Bounty Resources MVP (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tier-1 "bounty" resources from `docs/special_resources_design.md`: deterministic map-gen scatter onto hex tiles, radius-2 proximity claims by cities/settlements, income/loyalty/recruit bonuses, corner icons with hover tooltips, a resource-bar holdings list, and settlement-founding preview.

**Architecture:** One new all-static helper `BountySystem` (mirrors `LoyaltySystem` style) owns the bounty table, the scatter pass, claim resolution, and effect queries. Everything else is thin hooks: one new `TileState` field (+2 serializer lines), one call in the map generator, three one-liner hooks in economy code, and UI layers in `campaign.gd` / `campaign_hud.gd` following existing marker/tooltip/shard-label patterns.

**Tech Stack:** Godot 4.4 GDScript. Headless tests via `SceneTree` scripts (`-s res://tests/...`).

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`
- Test command shape: `& "<godot>" --headless --path . -s res://tests/<name>.gd` — autoloads must be fetched via `root.get_node("/root/GameManager")` inside tests; benign startup "Failed to compile depended scripts" noise is expected and NOT a failure (only the printed PASSED/FAILED line counts).
- Map generation must stay **deterministic with zero RNG** — use coordinate hashes like the rest of `map_generator.gd` (no `randi()`/`randf()` anywhere in scatter code).
- Save compatibility: new fields default via `Dictionary.get(key, default)` on deserialize; old saves must load.
- Battle determinism baselines (`tests/baselines/`) must NOT be regenerated; none of this plan touches battle code.
- Terrain enum ints: 0=PLAINS 1=FOREST 2=MOUNTAINS 3=DESERT 4=SWAMP 5=WETLANDS 6=TUNDRA 7=SHARD_WASTES 8=WATER 9=JUNGLE. Resource enum ints: 0=GOLD 1=IRON 2=TECHNOLOGY 3=FOOD 4=SHARD_ESSENCE 5=WOOD 6=CAPTIVES.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- UI text on leather panels must sit on dark chips (`docs/ui_style_guide.md`); tooltips follow the trade-route-tooltip pattern.

---

### Task 1: Bounty table, tile field, serialization, map-gen scatter

**Files:**
- Create: `scripts/systems/campaign/bounty_system.gd`
- Modify: `scripts/systems/campaign/hex_map_data.gd:19-25` (TileState field)
- Modify: `scripts/core/game_state.gd:46-53` (serialize) and `:65-70` (deserialize)
- Modify: `scripts/utils/map_generator.gd:124-160` (`generate_hex_map`) and `:79-122` (`generate_demo_hex_map`) — one call each
- Test: `tests/test_bounty_system.gd`

**Interfaces:**
- Produces: `BountySystem.BOUNTY_TYPES: Dictionary` (id → def with `name: String`, `terrains: Array[int]`, optional `coastal: bool`, optional `income: Dictionary[int,int]`, optional `loyalty: Dictionary[String,int]`, optional `recruit_discount: Dictionary[String,int]`, optional `deferred: String`); `BountySystem.scatter_bounties(map: HexMapData) -> void`; `HexMapData.TileState.bounty_id: StringName`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_bounty_system.gd`:

```gdscript
extends SceneTree
## Tests for tier-1 bounty resources (docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_bounty_system.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var map = _gm.state.hex_map

	# ── Scatter happened and is sane ──
	var placed: Array[Vector2i] = []
	var counts := {}
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		placed.append(coord)
		counts[tile.bounty_id] = counts.get(tile.bounty_id, 0) + 1
		var def: Dictionary = BountySystem.BOUNTY_TYPES.get(tile.bounty_id, {})
		_check(not def.is_empty(), "placed bounty %s exists in table" % tile.bounty_id)
		_check(int(tile.terrain) in def.get("terrains", []), "bounty %s on allowed terrain (%d)" % [tile.bounty_id, tile.terrain])
	_check(placed.size() >= 10, "at least 10 bounty deposits placed (got %d)" % placed.size())
	for t in counts:
		_check(counts[t] <= 8, "type %s capped at 8 (got %d)" % [t, counts[t]])
	# Spacing: no two bounties within 3 hexes
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if HexHelper.hex_distance(placed[i], placed[j]) < 3:
				_fails += 1
				print("FAIL: bounties too close: %s %s" % [placed[i], placed[j]])

	# ── Determinism: regenerating the same map yields identical bounties ──
	var fingerprint := _fingerprint(map)
	_gm.new_game(&"empire")
	_check(_fingerprint(_gm.state.hex_map) == fingerprint, "scatter is deterministic across new_game")

	# ── Serialization roundtrip preserves bounty_id ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fingerprint, "bounty_id survives save/load roundtrip")

	# ── Old-save compat: entries without the key default to empty ──
	for key in saved:
		saved[key].erase("bounty_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any_bounty := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].bounty_id != &"":
			any_bounty = true
	_check(not any_bounty, "old saves without bounty_id load with empty bounties")

	if _fails == 0:
		print("BOUNTY TEST PASSED")
		quit(0)
	else:
		print("BOUNTY TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].bounty_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].bounty_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . -s res://tests/test_bounty_system.gd 2>&1 | Select-String "PASSED|FAILED|FAIL:"`
Expected: load/parse failure or `BOUNTY TEST FAILED` (BountySystem and `bounty_id` don't exist yet).

- [ ] **Step 3: Add the tile field + serializer lines**

In `scripts/systems/campaign/hex_map_data.gd`, extend `TileState` (after `var owner_faction`):

```gdscript
	var bounty_id: StringName = &"" # tier-1 bounty resource on this tile (special_resources_design)
```

In `scripts/core/game_state.gd` `serialize_hex_map()`, add to the per-tile dict:

```gdscript
			"bounty_id": str(tile.bounty_id),
```

In `deserialize_hex_map()`, next to the other `tile_data.get` lines:

```gdscript
		tile.bounty_id = StringName(tile_data.get("bounty_id", ""))
```

- [ ] **Step 4: Create `scripts/systems/campaign/bounty_system.gd`**

```gdscript
class_name BountySystem
extends RefCounted
## Tier-1 "bounty" resources (docs/special_resources_design.md).
## All static. Owns the bounty table, the deterministic map-gen scatter pass,
## radius-2 claim resolution, and effect queries used by economy hooks + UI.

const CLAIM_RADIUS := 2
const MIN_SPACING := 3      # no two bounties closer than this
const MAX_PER_TYPE := 8
const ROSTER_ROLL_PCT := 66 # ~2/3 of types spawn per map

## Effects implemented in Phase 1: income {ResourceType->int},
## loyalty {class->int}, recruit_discount {unit_tag->pct}.
## `deferred` documents the design-doc rule awaiting a Phase 1.5 hook —
## such entries carry a provisional income stand-in so the bounty still matters.
const BOUNTY_TYPES := {
	&"orchards": {name = "Orchards", terrains = [0, 1], income = {3: 6}},
	&"grain_basin": {name = "Grain Basin", terrains = [0, 5], income = {3: 10}},
	&"vineyards": {name = "Vineyards", terrains = [0], income = {0: 5}, loyalty = {peasants = 1, artisans = 1, scholars = 1, nobles = 1}},
	&"honey_apiaries": {name = "Honey Apiaries", terrains = [0, 1], income = {3: 4}, loyalty = {peasants = 1}},
	&"herb_meadows": {name = "Herb Meadows", terrains = [0, 4], income = {3: 4}, deferred = "+25% army healing in this region"},
	&"wild_horses": {name = "Wild Horses", terrains = [0, 6], recruit_discount = {cavalry = 10}},
	&"fisheries": {name = "Fisheries", terrains = [0, 5], coastal = true, income = {3: 8}},
	&"pearl_beds": {name = "Pearl Beds", terrains = [0, 5], coastal = true, income = {0: 6}, deferred = "+20% gift value of gold gifts"},
	&"salt_flats": {name = "Salt Flats", terrains = [3, 5], income = {3: 4, 0: 4}},
	&"marble": {name = "Marble", terrains = [2, 3], income = {0: 6}, deferred = "-15% build cost for cultural buildings"},
	&"granite": {name = "Granite", terrains = [2], income = {1: 4}, deferred = "+20% build speed in region cities"},
	&"basalt_columns": {name = "Basalt Columns", terrains = [2], income = {1: 4}, deferred = "-20% cost for defensive buildings"},
	&"copper_vein": {name = "Copper Vein", terrains = [2, 3], income = {1: 5, 0: 3}},
	&"obsidian_flows": {name = "Obsidian Flows", terrains = [2, 7], income = {1: 4}, deferred = "+1 attack for units recruited here"},
	&"titanstone_quarry": {name = "Titanstone Quarry", terrains = [2], recruit_discount = {construct = 10}},
	&"timber_giants": {name = "Timber Giants", terrains = [1, 9], income = {5: 10}},
	&"amber_groves": {name = "Amber Groves", terrains = [1, 6], income = {0: 7}},
	&"furs": {name = "Furs", terrains = [6, 1], income = {0: 5}, deferred = "-10% army upkeep in tundra"},
	&"crystal_springs": {name = "Crystal Springs", terrains = [6], income = {0: 3}, deferred = "+2 population growth in region cities"},
	&"clay_pits": {name = "Clay Pits", terrains = [5, 0], income = {5: 5}, deferred = "-15% wood component of build costs"},
	&"peat_bogs": {name = "Peat Bogs", terrains = [4, 5], income = {5: 6}, deferred = "-10% building upkeep in region"},
	&"dye_gardens": {name = "Dye Gardens", terrains = [9, 0], coastal = true, income = {0: 8}, deferred = "gold counts toward trade deals only"},
}

## Deterministic coordinate hash — same idiom as map_generator.gd (no RNG).
static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass: run AFTER terrain is final (map_generator calls this last).
static func scatter_bounties(map: HexMapData) -> void:
	# 1. Roll the roster: ~2/3 of types spawn on any given map
	var selected: Array[StringName] = []
	var idx := 0
	for type_id in BOUNTY_TYPES:
		if _hash(idx * 31 + 7, 7777) % 100 < ROSTER_ROLL_PCT:
			selected.append(type_id)
		idx += 1
	if selected.is_empty():
		return
	# 2. Walk tiles in sorted order (deterministic), gate candidates by hash
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	var counts := {}
	for coord in coords:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		var h := _hash(coord.x, coord.y)
		if h % 9 != 0:
			continue # ~11% of land tiles are candidates
		# Spacing vs already-placed bounties
		var too_close := false
		for p in placed:
			if HexHelper.hex_distance(coord, p) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		# Pick the first fitting type, rotating start point by hash
		var start := (h / 9) % selected.size()
		for k in selected.size():
			var type_id: StringName = selected[(start + k) % selected.size()]
			var def: Dictionary = BOUNTY_TYPES[type_id]
			if counts.get(type_id, 0) >= MAX_PER_TYPE:
				continue
			if not (int(tile.terrain) in def.terrains):
				continue
			if def.get("coastal", false) and not _has_water_neighbor(map, coord):
				continue
			tile.bounty_id = type_id
			placed.append(coord)
			counts[type_id] = counts.get(type_id, 0) + 1
			break

static func _has_water_neighbor(map: HexMapData, coord: Vector2i) -> bool:
	for n in HexHelper.get_neighbors(coord):
		var t = map.get_tile(n)
		if t and t.terrain == Enums.TerrainType.WATER:
			return true
	return false
```

- [ ] **Step 5: Call the scatter pass from the generator**

In `scripts/utils/map_generator.gd`, in BOTH `generate_hex_map` (before its `return map`, after `_fix_terrain_pockets`) and `generate_demo_hex_map` (same position):

```gdscript
	BountySystem.scatter_bounties(map)  # tier-1 resources; terrain is final here
```

- [ ] **Step 6: Run test to verify it passes**

Run: same command as Step 2. Expected: `BOUNTY TEST PASSED`. If "at least 10 deposits" fails, loosen the candidate gate (`h % 9` → `h % 7`) rather than the spacing.

- [ ] **Step 7: Commit**

```bash
git add scripts/systems/campaign/bounty_system.gd scripts/systems/campaign/hex_map_data.gd scripts/core/game_state.gd scripts/utils/map_generator.gd tests/test_bounty_system.gd
git commit -m "feat(resources): bounty table, tile field and deterministic map scatter

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Claim resolution (radius 2, single claimant)

**Files:**
- Modify: `scripts/systems/campaign/bounty_system.gd` (append functions)
- Test: `tests/test_bounty_system.gd` (append cases)

**Interfaces:**
- Consumes: `BOUNTY_TYPES`, `TileState.bounty_id` from Task 1.
- Produces: `BountySystem.claimant_for(bounty_hex: Vector2i) -> StringName` (city_id or `&""`); `BountySystem.claimed_bounties_for_city(city: CityState) -> Array[Vector2i]`; `BountySystem.bounties_of_faction(faction_id: StringName) -> Array[Dictionary]` (each `{id, name, hex, city_id}`); `BountySystem.describe(type_id: StringName) -> String`.

- [ ] **Step 1: Append failing test cases**

Insert into `tests/test_bounty_system.gd` before the final PASSED check (state still loaded from Task 1 roundtrips — call `_gm.new_game(&"empire")` again first to reset):

```gdscript
	# ── Claim resolution ──
	_gm.new_game(&"empire")
	var map2 = _gm.state.hex_map
	var pid: StringName = &"empire"
	var home: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == pid:
			home = _gm.state.cities[cid]
			break
	# Craft a bounty 2 tiles from home on a land tile
	var spot := Vector2i(-1, -1)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var h2 := Vector2i(home.hex_pos.x + dx, home.hex_pos.y + dy)
			if HexHelper.hex_distance(home.hex_pos, h2) == 2:
				var t2 = map2.get_tile(h2)
				if t2 and t2.terrain != Enums.TerrainType.WATER and t2.bounty_id == &"":
					spot = h2
					break
		if spot != Vector2i(-1, -1):
			break
	map2.get_tile(spot).bounty_id = &"orchards"
	_check(BountySystem.claimant_for(spot) == home.city_id, "city claims bounty at distance 2")
	_check(spot in BountySystem.claimed_bounties_for_city(home), "claimed_bounties_for_city finds it")
	var listing: Array = BountySystem.bounties_of_faction(pid)
	var found_listing := false
	for entry in listing:
		if entry.hex == spot and entry.id == &"orchards":
			found_listing = true
	_check(found_listing, "bounties_of_faction lists the claim")
	_check(BountySystem.describe(&"orchards").contains("Food"), "describe() names the bonus")
	# Distance 3 → unclaimed
	map2.get_tile(spot).bounty_id = &""
	var far := Vector2i(-1, -1)
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var h3 := Vector2i(home.hex_pos.x + dx, home.hex_pos.y + dy)
			if HexHelper.hex_distance(home.hex_pos, h3) == 3:
				var t3 = map2.get_tile(h3)
				if t3 and t3.terrain != Enums.TerrainType.WATER and t3.bounty_id == &"":
					var other_claim := false
					for cid2 in _gm.state.cities:
						if HexHelper.hex_distance(_gm.state.cities[cid2].hex_pos, h3) <= 2:
							other_claim = true
					if not other_claim:
						far = h3
						break
		if far != Vector2i(-1, -1):
			break
	if far != Vector2i(-1, -1):
		map2.get_tile(far).bounty_id = &"orchards"
		_check(BountySystem.claimant_for(far) == &"", "distance 3 is out of claim range")
		map2.get_tile(far).bounty_id = &""
```

- [ ] **Step 2: Run to verify the new cases fail** (same command; expect `FAIL:` lines / parse error on missing functions)

- [ ] **Step 3: Append implementations to `bounty_system.gd`**

```gdscript
## Nearest city within CLAIM_RADIUS claims a bounty; ties break by city_id.
static func claimant_for(bounty_hex: Vector2i) -> StringName:
	var best_id: StringName = &""
	var best_d := 99
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var d := HexHelper.hex_distance(city.hex_pos, bounty_hex)
		if d > CLAIM_RADIUS:
			continue
		if d < best_d or (d == best_d and String(city_id) < String(best_id)):
			best_d = d
			best_id = city_id
	return best_id

static func claimed_bounties_for_city(city: CityState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for dx in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
		for dy in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
			var h := Vector2i(city.hex_pos.x + dx, city.hex_pos.y + dy)
			if HexHelper.hex_distance(city.hex_pos, h) > CLAIM_RADIUS:
				continue
			var tile = map.get_tile(h)
			if tile and tile.bounty_id != &"" and claimant_for(h) == city.city_id:
				result.append(h)
	return result

## For the HUD holdings list: every bounty claimed by any of the faction's cities.
static func bounties_of_faction(faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		for hex in claimed_bounties_for_city(city):
			var tile = map.get_tile(hex)
			result.append({
				id = tile.bounty_id,
				name = BOUNTY_TYPES[tile.bounty_id].name,
				hex = hex,
				city_id = city_id,
			})
	return result

const _RES_NAMES := {0: "Gold", 1: "Iron", 2: "Technology", 3: "Food", 4: "Shard Essence", 5: "Wood", 6: "Captives"}

## Human-readable one-line bonus text for tooltips.
static func describe(type_id: StringName) -> String:
	var def: Dictionary = BOUNTY_TYPES.get(type_id, {})
	if def.is_empty():
		return ""
	var parts: PackedStringArray = []
	for res_type in def.get("income", {}):
		parts.append("+%d %s" % [def.income[res_type], _RES_NAMES.get(res_type, "?")])
	for cls in def.get("loyalty", {}):
		parts.append("+%d %s loyalty" % [def.loyalty[cls], String(cls)])
	for tag in def.get("recruit_discount", {}):
		parts.append("-%d%% %s recruit cost" % [def.recruit_discount[tag], String(tag)])
	return ", ".join(parts)
```

- [ ] **Step 4: Run test — expect `BOUNTY TEST PASSED`**

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/campaign/bounty_system.gd tests/test_bounty_system.gd
git commit -m "feat(resources): radius-2 single-claimant bounty resolution

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Economy hooks — income, loyalty, recruit discount

**Files:**
- Modify: `scripts/systems/campaign/bounty_system.gd` (3 query functions)
- Modify: `scripts/systems/campaign/city_system.gd` — `calculate_city_income` (flat add before `apply_region_effects` at ~line 258) and `start_recruitment` discount block (~1547-1559)
- Modify: `scripts/systems/campaign/loyalty_system.gd` — `_get_active_modifiers` (append one modifier entry near the per-building block ~290-300)
- Test: `tests/test_bounty_system.gd` (append cases)

**Interfaces:**
- Consumes: `claimed_bounties_for_city` from Task 2.
- Produces: `BountySystem.income_bonus_for_city(city: CityState) -> Dictionary` (ResourceType→int); `BountySystem.loyalty_bonus_for_city(city: CityState) -> Dictionary` (class String→int); `BountySystem.recruit_discount_for(city: CityState, ud: UnitData) -> int` (percent).

- [ ] **Step 1: Append failing test cases** (before the PASSED check; reuses `home`/`spot` from Task 2 — re-set `map2.get_tile(spot).bounty_id = &"orchards"` first):

```gdscript
	# ── Economy hooks ──
	map2.get_tile(spot).bounty_id = &"orchards"
	var inc_with: Dictionary = _gm.city_system.calculate_city_income(home)
	map2.get_tile(spot).bounty_id = &""
	var inc_without: Dictionary = _gm.city_system.calculate_city_income(home)
	_check(inc_with.get(3, 0) - inc_without.get(3, 0) == 6, "orchards adds +6 food to city income")

	map2.get_tile(spot).bounty_id = &"wild_horses"
	var cav_ud := UnitData.new()
	cav_ud.tags = ["cavalry", "melee"]
	var inf_ud := UnitData.new()
	inf_ud.tags = ["infantry", "melee"]
	_check(BountySystem.recruit_discount_for(home, cav_ud) == 10, "wild horses discount cavalry 10%")
	_check(BountySystem.recruit_discount_for(home, inf_ud) == 0, "no discount for infantry")

	map2.get_tile(spot).bounty_id = &"vineyards"
	var loy: Dictionary = BountySystem.loyalty_bonus_for_city(home)
	_check(int(loy.get("peasants", 0)) == 1, "vineyards grant +1 peasant loyalty")
	map2.get_tile(spot).bounty_id = &""
```

- [ ] **Step 2: Run — expect FAILs on missing functions**

- [ ] **Step 3: Append queries to `bounty_system.gd`**

```gdscript
static func income_bonus_for_city(city: CityState) -> Dictionary:
	var total := {}
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for res_type in def.get("income", {}):
			total[res_type] = total.get(res_type, 0) + def.income[res_type]
	return total

static func loyalty_bonus_for_city(city: CityState) -> Dictionary:
	var total := {}
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for cls in def.get("loyalty", {}):
			total[String(cls)] = total.get(String(cls), 0) + def.loyalty[cls]
	return total

static func recruit_discount_for(city: CityState, ud: UnitData) -> int:
	var total := 0
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for tag in def.get("recruit_discount", {}):
			if ud.tags.has(String(tag)):
				total += def.recruit_discount[tag]
	return total
```

- [ ] **Step 4: Wire the three hooks**

`city_system.gd`, in `calculate_city_income` immediately BEFORE the `apply_region_effects(income, city)` call:

```gdscript
	# Claimed tier-1 bounty resources (special_resources_design)
	var bounty_income := BountySystem.income_bonus_for_city(city)
	for b_res in bounty_income:
		income[b_res] = income.get(b_res, 0) + bounty_income[b_res]
```

`city_system.gd`, in `start_recruitment` inside the discount block (after the research `recruitment_cost_reduction` line, before `if total_discount_pct > 0`):

```gdscript
	total_discount_pct += BountySystem.recruit_discount_for(city, unit_data)
```

(Use the local `UnitData` variable already in scope at that point — check its actual name in the function and match it.)

`loyalty_system.gd`, in `_get_active_modifiers`, after the per-building `class_loyalty_bonus` aggregation block — match the exact modifier dict shape used by surrounding entries (`{label, weights, multiplier}` with all five class keys):

```gdscript
	# Claimed bounty resources (e.g. Vineyards, Honey Apiaries)
	var bounty_loyalty := BountySystem.loyalty_bonus_for_city(city)
	if not bounty_loyalty.is_empty():
		modifiers.append({
			"label": "Bounty resources",
			"weights": {
				"peasants": bounty_loyalty.get("peasants", 0),
				"artisans": bounty_loyalty.get("artisans", 0),
				"scholars": bounty_loyalty.get("scholars", 0),
				"nobles": bounty_loyalty.get("nobles", 0),
				"captives": 0,
			},
			"multiplier": 1.0,
		})
```

(Verify the surrounding entries' key style — bare identifiers vs strings — and match it exactly; verify the local variable holding the modifiers array is called `modifiers`, adjust if not.)

- [ ] **Step 5: Run test — expect `BOUNTY TEST PASSED`. Also run `tests/test_siege_pressure.gd` (income path regression) — expect `SIEGE TEST PASSED`.**

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/campaign/bounty_system.gd scripts/systems/campaign/city_system.gd scripts/systems/campaign/loyalty_system.gd tests/test_bounty_system.gd
git commit -m "feat(resources): bounty income, loyalty and recruit-discount hooks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Map corner icons + hover tooltip

**Files:**
- Modify: `scenes/campaign/campaign.gd` — marker layer + hover branch
- Verify: extend `tests/tmp_screenshot_windows.gd`-style harness (new `tests/tmp_screenshot_bounties.gd`)

**Interfaces:**
- Consumes: `TileState.bounty_id`, `BountySystem.BOUNTY_TYPES`, `claimant_for`, `describe`.
- Produces: `_create_bounty_markers()` (called once at campaign setup), `_update_bounty_hover(world_pos: Vector2)` (called from the existing hover gate).

- [ ] **Step 1: Add the marker layer** — in `campaign.gd`, new member vars near `_city_markers` (~line 58):

```gdscript
var _bounty_markers: Dictionary = {} # Vector2i -> Node2D
var bounty_markers_node: Node2D = null
var _bounty_tooltip: PanelContainer = null
var _last_bounty_hover := Vector2i(-9999, -9999)
```

New function (place near `_create_city_markers`, ~line 2521):

```gdscript
func _create_bounty_markers() -> void:
	if bounty_markers_node == null:
		bounty_markers_node = Node2D.new()
		bounty_markers_node.name = "BountyMarkers"
		bounty_markers_node.z_index = 1 # above terrain, below cities (2)
		$EntityLayer.add_child(bounty_markers_node)
	for child in bounty_markers_node.get_children():
		child.queue_free()
	_bounty_markers.clear()
	var map = GameManager.state.hex_map
	if map == null:
		return
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		var marker := Node2D.new()
		# Top-right corner of the hex tile
		marker.position = _hex_to_pixel(coord) + Vector2(HEX_RADIUS * 0.45, -HEX_RADIUS * 0.55)
		var bg := Polygon2D.new()
		bg.polygon = _make_circle(Vector2.ZERO, 7.0, 10)
		bg.color = Color(0.08, 0.07, 0.05, 0.9)
		marker.add_child(bg)
		var rim := Polygon2D.new()
		rim.polygon = _make_circle(Vector2.ZERO, 7.0, 10)
		rim.color = Color(0.78, 0.62, 0.32, 0.9)
		rim.scale = Vector2(1.15, 1.15)
		rim.z_index = -1
		marker.add_child(rim)
		var glyph := Label.new()
		glyph.text = String(BountySystem.BOUNTY_TYPES[tile.bounty_id].name).left(1)
		glyph.add_theme_font_size_override("font_size", 9)
		glyph.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		glyph.position = Vector2(-4, -8)
		marker.add_child(glyph)
		bounty_markers_node.add_child(marker)
		_bounty_markers[coord] = marker
```

Call it right after `_create_city_markers()` is called during campaign setup (find the call site of `_create_city_markers()` and add `_create_bounty_markers()` on the next line). NOTE: `_make_circle` already exists in campaign.gd (used by city markers) — reuse it; if its signature differs (`_make_circle(radius, points)` without center), adapt the two calls to match the real signature.

- [ ] **Step 2: Hover tooltip** — in `_unhandled_input`, inside the existing `if hex_coord != _last_hover_hex:` gate (~line 3409-3417), add `_update_bounty_hover(hex_coord)` alongside `_update_trade_route_hover`. New function (modeled on `_update_trade_route_hover`, ~line 4983):

```gdscript
func _update_bounty_hover(hex_coord: Vector2i) -> void:
	var map = GameManager.state.hex_map
	var tile = map.get_tile(hex_coord) if map else null
	if tile == null or tile.bounty_id == &"" or not GameManager.explored_tiles.has(hex_coord):
		if _bounty_tooltip:
			_bounty_tooltip.visible = false
		return
	if _bounty_tooltip == null:
		_bounty_tooltip = PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
		style.border_color = Color(0.55, 0.42, 0.2, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(8)
		_bounty_tooltip.add_theme_stylebox_override("panel", style)
		var lbl := Label.new()
		lbl.name = "Text"
		lbl.add_theme_font_size_override("font_size", 12)
		_bounty_tooltip.add_child(lbl)
		$UILayer.add_child(_bounty_tooltip)
	var def: Dictionary = BountySystem.BOUNTY_TYPES[tile.bounty_id]
	var claimant := BountySystem.claimant_for(hex_coord)
	var claim_text := "Unclaimed — settle within %d tiles" % BountySystem.CLAIM_RADIUS
	if claimant != &"":
		var c: CityState = GameManager.state.cities.get(claimant)
		claim_text = "Claimed by " + (c.get_display_name() if c else String(claimant))
	_bounty_tooltip.get_node("Text").text = "%s\n%s\n%s" % [def.name, BountySystem.describe(tile.bounty_id), claim_text]
	_bounty_tooltip.position = get_viewport().get_mouse_position() + Vector2(15, -30)
	_bounty_tooltip.visible = true
```

- [ ] **Step 3: Screenshot verification** — create `tests/tmp_screenshot_bounties.gd` (copy the header of `tests/tmp_screenshot_windows.gd`: new_game empire with `_is_transitioning` guard, instantiate `res://scenes/campaign/campaign.tscn`). At frame 40: disable fog (`_campaign.set("_fog_of_war_enabled", false); _campaign.set("_fog_dirty", true)`), find any bounty tile, pin the camera on it at zoom 2, screenshot at frame 55 (`win_bounty_icons.png`). Run WITHOUT `--headless`:

`& "<godot>" --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_bounties.gd`

Then Read the PNG and confirm: corner icons visible on tiles, not overlapping city badges. Also watch stdout for `SCRIPT ERROR` mentioning campaign.gd (this is the only compile check that covers scene scripts).

- [ ] **Step 4: Commit**

```bash
git add scenes/campaign/campaign.gd tests/tmp_screenshot_bounties.gd
git commit -m "feat(resources): bounty corner icons on map tiles + hover tooltip

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Resource-bar "Special Resources" entry

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` — new label + tooltip next to the shard label (created ~line 9040-9078, updated by `_update_shard_display` ~9080)

**Interfaces:**
- Consumes: `BountySystem.bounties_of_faction`, `describe`.
- Produces: `_create_bounty_bar_label()`, `_update_bounty_bar_display()` (called from `_update_resource_display`).

- [ ] **Step 1: Create the label** — copy the shard-label pattern exactly (standalone `Label` inserted into `$TopBar/HBoxContainer` before the `"Spacer"` node, plus a lazily-built tooltip `PanelContainer`). New member vars near `shard_label`'s declaration; new function `_create_bounty_bar_label()` called immediately after the shard label is created:

```gdscript
func _create_bounty_bar_label() -> void:
	bounty_bar_label = Label.new()
	bounty_bar_label.name = "BountyBarLabel"
	bounty_bar_label.add_theme_font_size_override("font_size", 13)
	bounty_bar_label.add_theme_color_override("font_color", Color(0.72, 0.85, 0.55))
	bounty_bar_label.mouse_filter = Control.MOUSE_FILTER_STOP
	bounty_bar_label.mouse_entered.connect(_on_bounty_bar_hover)
	bounty_bar_label.mouse_exited.connect(func():
		if _bounty_bar_tooltip:
			_bounty_bar_tooltip.visible = false)
	var hbox: HBoxContainer = $TopBar/HBoxContainer
	hbox.add_child(bounty_bar_label)
	hbox.move_child(bounty_bar_label, hbox.get_node("Spacer").get_index())

func _update_bounty_bar_display() -> void:
	if bounty_bar_label == null:
		return
	var n := BountySystem.bounties_of_faction(GameManager.state.player_faction_id).size()
	bounty_bar_label.text = "  |  Bounties: %d" % n
	bounty_bar_label.visible = n > 0
```

Hover handler builds the tooltip listing each entry as `"%s — %s (%s)" % [entry.name, city display name, BountySystem.describe(entry.id)]`, on a dark chip panel (copy `_on_shard_label_mouse_entered`'s panel construction wholesale, swap content). Call `_update_bounty_bar_display()` at the end of `_update_resource_display()` (next to `_update_shard_display()`).

- [ ] **Step 2: Verify via screenshot** — re-run `tests/tmp_screenshot_bounties.gd`; the top bar should show `| Bounties: N` when the starting cities claim any (if starting cities claim none, temporarily craft one in the harness: set a tile 2 away from the player capital to `&"orchards"` before the screenshot frame). Read the PNG; confirm placement and no overlap with Shards.

- [ ] **Step 3: Commit**

```bash
git add scenes/campaign/campaign_hud.gd tests/tmp_screenshot_bounties.gd
git commit -m "feat(resources): resource-bar bounty holdings entry with tooltip

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Settlement founding preview lists claimable bounties

**Files:**
- Modify: `scripts/systems/campaign/bounty_system.gd` (`bounties_claimable_at`)
- Modify: `scenes/campaign/campaign.gd` — `_show_settlement_preview` (~5408-5476)
- Test: `tests/test_bounty_system.gd` (append case)

**Interfaces:**
- Consumes: `claimant_for`.
- Produces: `BountySystem.bounties_claimable_at(hex_pos: Vector2i) -> Array[Dictionary]` (each `{id, name, hex}`) — bounties within CLAIM_RADIUS of `hex_pos` that are currently unclaimed or farther from their current claimant than from `hex_pos`.

- [ ] **Step 1: Append failing test case**

```gdscript
	# ── Founding preview query ──
	map2.get_tile(spot).bounty_id = &"orchards"
	var near_settle := Vector2i(home.hex_pos.x, home.hex_pos.y)  # settling AT the city is impossible, but the query is position-based
	var claimable: Array = BountySystem.bounties_claimable_at(spot)  # standing on the bounty
	var self_found := false
	for entry in claimable:
		if entry.hex == spot:
			self_found = true
	_check(self_found, "bounties_claimable_at sees an adjacent bounty (distance 0 beats the existing claimant at 2)")
	map2.get_tile(spot).bounty_id = &""
```

- [ ] **Step 2: Run — expect FAIL, then implement**

```gdscript
## Bounties a NEW city founded at hex_pos would claim: within CLAIM_RADIUS and
## either unclaimed or strictly closer to hex_pos than to the current claimant.
static func bounties_claimable_at(hex_pos: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for dx in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
		for dy in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
			var h := Vector2i(hex_pos.x + dx, hex_pos.y + dy)
			var d := HexHelper.hex_distance(hex_pos, h)
			if d > CLAIM_RADIUS:
				continue
			var tile = map.get_tile(h)
			if tile == null or tile.bounty_id == &"":
				continue
			var current := claimant_for(h)
			if current == &"":
				result.append({id = tile.bounty_id, name = BOUNTY_TYPES[tile.bounty_id].name, hex = h})
			else:
				var cur_city: CityState = GameManager.state.cities.get(current)
				if cur_city and d < HexHelper.hex_distance(cur_city.hex_pos, h):
					result.append({id = tile.bounty_id, name = BOUNTY_TYPES[tile.bounty_id].name, hex = h})
	return result
```

- [ ] **Step 3: Wire into `_show_settlement_preview`** — in `campaign.gd` between the income rows loop (~5462) and the total label (~5464):

```gdscript
	# Bounty resources this settlement would claim (special_resources_design)
	var claimable := BountySystem.bounties_claimable_at(hex_coord)
	if not claimable.is_empty():
		var b_header := Label.new()
		b_header.text = "Claims resources:"
		b_header.add_theme_font_size_override("font_size", 11)
		b_header.add_theme_color_override("font_color", Color(0.72, 0.85, 0.55))
		vbox.add_child(b_header)
		for entry in claimable:
			var b_lbl := Label.new()
			b_lbl.text = "  %s (%s)" % [entry.name, BountySystem.describe(entry.id)]
			b_lbl.add_theme_font_size_override("font_size", 11)
			b_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
			vbox.add_child(b_lbl)
```

(Match the actual local variable names in `_show_settlement_preview` — the vbox may be named differently; adapt.)

- [ ] **Step 4: Run test (`BOUNTY TEST PASSED`) + screenshot the placement mode** — extend `tests/tmp_screenshot_bounties.gd`: call `hud._on_found_settlement_pressed(capital_id)` equivalent or directly `_campaign._on_settlement_placement_requested(capital_id)`, hover a valid tile near a crafted bounty via `_campaign._show_settlement_preview(hex)`, screenshot. Confirm the "Claims resources:" rows render.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/campaign/bounty_system.gd scenes/campaign/campaign.gd tests/test_bounty_system.gd tests/tmp_screenshot_bounties.gd
git commit -m "feat(resources): settlement founding preview lists claimable bounties

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Regression sweep + doc status update

**Files:**
- Modify: `docs/special_resources_design.md` (mark Phase 1 implemented)

- [ ] **Step 1: Full test sweep** — run and confirm each prints its PASSED line:
  - `tests/test_bounty_system.gd`
  - `tests/test_faction_ai_flavor.gd`
  - `tests/test_siege_pressure.gd`
  - `tests/test_save_roundtrip.gd`
  - 15-turn AI smoke: `-s res://tests/tmp_econ_sim.gd -- 7 15` filtered for `SCRIPT ERROR` (expect none)
- [ ] **Step 2: Screenshot sweep** — re-run `tests/tmp_screenshot_windows.gd` (no regressions in existing windows) and `tests/tmp_screenshot_bounties.gd`; visually inspect both PNGs.
- [ ] **Step 3: Update doc** — in `docs/special_resources_design.md`, change the Phasing section's MVP line to `1. **MVP — IMPLEMENTED (see tests/test_bounty_system.gd)** — ...` and note the deferred effect kinds (heal/build-cost/build-speed/upkeep/gift-value/trade-only/pop-growth/unit-attack) with their provisional income stand-ins.
- [ ] **Step 4: Commit**

```bash
git add docs/special_resources_design.md
git commit -m "docs(resources): mark bounty MVP implemented, note deferred effect kinds

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** scatter (T1), claims + single-claimant (T2), bonuses (T3), corner icons + hover (T4), resource-bar list (T5), settlement preview (T6) — matches the MVP phase of the design doc. Deferred: 8 effect kinds without existing hooks (documented in T7); AI settle-toward-bounties weighting (doc places it in later phases); trade display of leased resources (Phase 2 — no leases exist yet).
- **Placeholder scan:** the "adapt to the real signature/local variable name" notes in T3/T4/T6 are deliberate — those exact identifiers must be read from the live file at execution time; every behavioral requirement has concrete code.
- **Type consistency:** `bounty_id: StringName` everywhere; `claimant_for -> StringName`; listing entries `{id, name, hex[, city_id]}` consistent between T2 (bounties_of_faction) and T6 (bounties_claimable_at, no city_id).
