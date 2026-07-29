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
		var placed_one := false
		for spacing in [MIN_SPACING, 6, 4, 2]:
			for k in coords.size():
				var coord: Vector2i = coords[(start + k) % coords.size()]
				if _try_place(map, coord, type_id, def, placed, spacing):
					placed_one = true
					break
			if placed_one:
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

static func _try_place(map: HexMapData, coord: Vector2i, type_id: StringName, def: Dictionary, placed: Array[Vector2i], spacing: int = MIN_SPACING) -> bool:
	var tile: HexMapData.TileState = map.tiles[coord]
	if tile.terrain == Enums.TerrainType.WATER or tile.special_id != &"":
		return false
	if tile.region_id == &"":
		return false # deposits must belong to a region (ownership model)
	if not (int(tile.terrain) in def.terrains):
		return false
	for p in placed:
		if HexHelper.hex_distance(coord, p) < spacing:
			return false
	tile.special_id = type_id
	placed.append(coord)
	return true
