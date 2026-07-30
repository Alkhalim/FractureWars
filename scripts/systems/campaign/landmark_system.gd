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
