class_name HexMapData
extends RefCounted

const MAP_WIDTH := 65
const MAP_HEIGHT := 45

var tiles: Dictionary = {} # Vector2i -> TileState

class TileState:
	var terrain: Enums.TerrainType = Enums.TerrainType.PLAINS
	var region_id: StringName = &""
	var road_level: int = 0 # 0=none, 1=path, 2=road
	var realm_influence: Enums.Realm = Enums.Realm.MORTAL
	var development_level: int = 0 # 0-3
	var owner_faction: StringName = &""

const TERRAIN_COSTS := {
	Enums.TerrainType.PLAINS: 1.0,
	Enums.TerrainType.FOREST: 2.0,
	Enums.TerrainType.MOUNTAINS: 4.2,
	Enums.TerrainType.DESERT: 1.5,
	Enums.TerrainType.SWAMP: 3.0,
	Enums.TerrainType.WETLANDS: 1.0,
	Enums.TerrainType.TUNDRA: 2.0,
	Enums.TerrainType.SHARD_WASTES: 3.0,
	Enums.TerrainType.WATER: INF,
	Enums.TerrainType.JUNGLE: 2.7,
}

func get_tile(coord: Vector2i) -> TileState:
	return tiles.get(coord)

func get_movement_cost(coord: Vector2i, faction_id: StringName) -> float:
	var tile := get_tile(coord)
	if tile == null:
		return INF

	var base_cost: float = TERRAIN_COSTS.get(tile.terrain, 1.0)

	# Faction terrain affinity — factions move faster in aligned terrain
	var fd: FactionData = DataManager.get_faction(faction_id)
	if fd:
		if fd.realm_affinity == Enums.Realm.VOID:
			# Void factions: -0.5 in Shard Wastes and Desert
			if tile.terrain == Enums.TerrainType.SHARD_WASTES:
				base_cost -= 0.5
			elif tile.terrain == Enums.TerrainType.DESERT:
				base_cost -= 0.3
		elif fd.realm_affinity == Enums.Realm.NATURE:
			# Nature factions: -0.5 in Jungle and Forest
			if tile.terrain == Enums.TerrainType.JUNGLE:
				base_cost -= 0.5
			elif tile.terrain == Enums.TerrainType.FOREST:
				base_cost -= 0.4
		elif fd.realm_affinity == Enums.Realm.MORTAL:
			# Mortal factions: -0.3 on Plains and Wetlands (civilized lands)
			if tile.terrain == Enums.TerrainType.PLAINS:
				base_cost -= 0.2
		elif fd.realm_affinity == Enums.Realm.ELEMENTAL:
			# Elemental factions: -0.4 in Mountains and Tundra
			if tile.terrain == Enums.TerrainType.MOUNTAINS:
				base_cost -= 0.6
			elif tile.terrain == Enums.TerrainType.TUNDRA:
				base_cost -= 0.3

	# Road modifier
	if tile.road_level == 1:
		base_cost *= 0.75
	elif tile.road_level >= 2:
		base_cost *= 0.5

	# Friendly territory with development 2+
	if tile.owner_faction == faction_id and tile.development_level >= 2:
		base_cost *= 0.75

	return maxf(base_cost, 0.5)

func get_region_tiles(region_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.region_id == region_id:
			result.append(coord)
	return result

func get_region_owner(region_id: StringName) -> StringName:
	# Ownership = faction controlling the most tiles in the region
	var counts: Dictionary = {} # faction_id -> count
	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.region_id == region_id and tile.owner_faction != &"":
			counts[tile.owner_faction] = counts.get(tile.owner_faction, 0) + 1

	if counts.is_empty():
		return &""

	var best_faction: StringName = &""
	var best_count := 0
	for faction_id in counts:
		if counts[faction_id] > best_count:
			best_count = counts[faction_id]
			best_faction = faction_id
	return best_faction

func set_region_owner(region_id: StringName, faction_id: StringName) -> void:
	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.region_id == region_id:
			tile.owner_faction = faction_id
