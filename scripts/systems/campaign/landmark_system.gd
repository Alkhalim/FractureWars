class_name LandmarkSystem
extends RefCounted
## Tier-3 Landmarks (Phase 3 of docs/special_resources_design.md).
## All static. Exactly SPAWN_COUNT of the 7 types spawn per map (max 1 each),
## terrain-fitting and widely spread. A Landmark is exploited by owning its
## REGION and building its unique faction-shared building in a region city.

const SPAWN_COUNT := 5
const MIN_SPACING := 12  # relaxed progressively on small maps

const LANDMARK_TYPES := {
	&"dragonbone_fields": {name = "Dragonbone Fields", terrains = [3, 7], building_id = &"dragonbone_digsite", rule_text = "-15% recruit cost for monster/beast units"},
	&"everfrost_core": {name = "Everfrost Core", terrains = [6], building_id = &"rimeheart_bore", rule_text = "+10% army defense in owned territory during winter"},
	&"sungold_vein": {name = "Sungold Vein", terrains = [2, 3], building_id = &"sungold_mine", rule_text = "+15 gold/turn, but -2 noble loyalty in its province (greed)"},
	&"worldroot_nexus": {name = "Worldroot Nexus", terrains = [9, 1], building_id = &"rootwarden_enclave", rule_text = "Armies in the region heal double; +1 population growth in adjacent regions"},
	&"voidglass_rift": {name = "Voidglass Rift", terrains = [7, 4], building_id = &"rift_stabilizer", rule_text = "+3 shard essence/turn, +10% arcane research; -1 loyalty in its province (whispers)"},
	&"titan_forge_ruin": {name = "Titan Forge-Ruin", terrains = [2], building_id = &"reforged_foundry", rule_text = "Construct units cost -25% and start at Trained veterancy"},
	&"leyline_well": {name = "Leyline Well", terrains = [0, 1, 2, 3, 6, 9], building_id = &"attunement_circle", rule_text = "Socketed crystal bonuses count +50% stronger"},
}

static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass. Runs FIRST (before specials/bounties). Rolls 5 of the 7
## types deterministically, then places each with wide spacing, relaxing
## spacing progressively so small maps still fit all SPAWN_COUNT.
## salt: per-campaign map seed (Task 1B). 0 == identity fold, reproducing the
## legacy roll/placement exactly.
static func scatter_landmarks(map: HexMapData, salt: int = 0) -> void:
	# Deterministic 5-of-7 roll: sort type ids by hash, take the first SPAWN_COUNT
	var type_ids: Array = LANDMARK_TYPES.keys()
	var scored: Array = []
	for i in type_ids.size():
		scored.append([_hash(i * 271 + 5 + salt * 7919, 991), type_ids[i]])
	scored.sort()
	var selected: Array[StringName] = []
	for k in mini(SPAWN_COUNT, scored.size()):
		selected.append(scored[k][1])
	# Placement: rotating-start full scan per type, spacing relaxation chain
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	for t_idx in selected.size():
		var type_id: StringName = selected[t_idx]
		var def: Dictionary = LANDMARK_TYPES[type_id]
		var start := _hash(t_idx * 137 + 29 + salt * 7919, 771) % coords.size()
		var done := false
		for spacing in [MIN_SPACING, 9, 6, 4, 2]:
			for k in coords.size():
				var coord: Vector2i = coords[(start + k) % coords.size()]
				if _try_place(map, coord, type_id, def, placed, spacing):
					done = true
					break
			if done:
				break

static func _try_place(map: HexMapData, coord: Vector2i, type_id: StringName, def: Dictionary, placed: Array[Vector2i], spacing: int) -> bool:
	var tile: HexMapData.TileState = map.tiles[coord]
	if tile.terrain == Enums.TerrainType.WATER or tile.landmark_id != &"":
		return false
	if tile.region_id == &"":
		return false
	if not (int(tile.terrain) in def.terrains):
		return false
	for p in placed:
		if HexHelper.hex_distance(coord, p) < spacing:
			return false
	tile.landmark_id = type_id
	placed.append(coord)
	return true

## Query API (Task 3). A Landmark is exploited by owning its region and
## building the landmark's unique faction-shared building in a region city.
static func landmark_hex_in_region(region_id: StringName) -> Vector2i:
	var map = GameManager.state.hex_map
	if map == null or region_id == &"":
		return Vector2i(-1, -1)
	for coord in map.get_region_tiles(region_id):
		var tile = map.get_tile(coord)
		if tile and tile.landmark_id != &"":
			return coord
	return Vector2i(-1, -1)

static func landmark_in_region(region_id: StringName) -> StringName:
	var hex := landmark_hex_in_region(region_id)
	if hex == Vector2i(-1, -1):
		return &""
	return GameManager.state.hex_map.get_tile(hex).landmark_id

static func region_has_landmark_building(region_id: StringName) -> bool:
	var lm: StringName = landmark_in_region(region_id)
	if lm == &"":
		return false
	var building_id: StringName = LANDMARK_TYPES[lm].building_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id == region_id and city.buildings.has(building_id):
			return true
	return false

static func landmarks_of_faction(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	for region_id in fs.owned_regions:
		var lm: StringName = landmark_in_region(region_id)
		if lm != &"" and region_has_landmark_building(region_id):
			result.append(lm)
	return result

static func has_landmark(faction_id: StringName, landmark_id: StringName) -> bool:
	return landmark_id in landmarks_of_faction(faction_id)

## Returns the region_id holding faction_id's active (owned + built) Worldroot
## Nexus, or &"" if none. Used by heal-doubling and adjacent-growth hooks.
static func worldroot_region_of_faction(faction_id: StringName) -> StringName:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return &""
	for region_id in fs.owned_regions:
		if landmark_in_region(region_id) == &"worldroot_nexus" and region_has_landmark_building(region_id):
			return region_id
	return &""

static func describe(landmark_id: StringName) -> String:
	var def: Dictionary = LANDMARK_TYPES.get(landmark_id, {})
	return def.get("rule_text", "") if not def.is_empty() else ""

## Dragonbone: -15% for monster/beast. Titan Forge: -25% for constructs.
static func recruit_discount_for(faction_id: StringName, ud: UnitData) -> int:
	var total := 0
	if (ud.tags.has("monster") or ud.tags.has("beast")) and has_landmark(faction_id, &"dragonbone_fields"):
		total += 15
	if ud.tags.has("construct") and has_landmark(faction_id, &"titan_forge_ruin"):
		total += 25
	return total
