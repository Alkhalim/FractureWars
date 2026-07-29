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
	&"dye_gardens": {name = "Dye Gardens", terrains = [9, 5], coastal = true, income = {0: 8}, deferred = "gold counts toward trade deals only"},
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
