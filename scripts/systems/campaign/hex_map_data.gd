class_name HexMapData
extends RefCounted

static var MAP_WIDTH := 117
static var MAP_HEIGHT := 78

# Render metrics — single source of truth for hex pixel geometry (flat-top).
# campaign.gd (rendering) and campaign_camera.gd (pan clamp) must both read
# these; a stale duplicate once made the camera clamp wall off ~16% of the map.
const HEX_RADIUS := 38.0
const HEX_H_SPACING := HEX_RADIUS * 1.5
const HEX_V_SPACING := HEX_RADIUS * 1.732

var tiles: Dictionary = {} # Vector2i -> TileState
var _region_tiles_cache: Dictionary = {} # region_id (StringName) -> Array[Vector2i]
var _faction_affinity_cache: Dictionary = {} # faction_id (StringName) -> Enums.Realm (or -1 if no FactionData)
var _region_owner_cache: Dictionary = {} # region_id -> StringName; invalidated on ownership writes
var _region_adjacency_cache: Dictionary = {} # "a|b" (sorted) -> bool; static after map gen

func invalidate_region_owner_cache() -> void:
	_region_owner_cache.clear()

func invalidate_region_owner(region_id: StringName) -> void:
	_region_owner_cache.erase(region_id)

class TileState:
	var terrain: Enums.TerrainType = Enums.TerrainType.PLAINS
	var region_id: StringName = &""
	var road_level: int = 0 # 0=none, 1=path, 2=road
	var realm_influence: Enums.Realm = Enums.Realm.MORTAL
	var development_level: int = 0 # 0-3
	var owner_faction: StringName = &""
	var bounty_id: StringName = &"" # tier-1 bounty resource on this tile (special_resources_design)
	var special_id: StringName = &"" # tier-2 Special resource deposit (special_resources_design)
	var landmark_id: StringName = &"" # tier-3 Landmark on this tile (special_resources_design)

const TERRAIN_COSTS := {
	Enums.TerrainType.PLAINS: 1.2,
	Enums.TerrainType.FOREST: 2.0,
	Enums.TerrainType.MOUNTAINS: 4.2,
	Enums.TerrainType.DESERT: 1.5,
	Enums.TerrainType.SWAMP: 3.0,
	Enums.TerrainType.WETLANDS: 1.0,
	Enums.TerrainType.TUNDRA: 2.0,
	Enums.TerrainType.SHARD_WASTES: 3.0,
	Enums.TerrainType.WATER: INF,
	Enums.TerrainType.JUNGLE: 2.0,
}

func build_region_cache() -> void:
	_region_tiles_cache.clear()
	_faction_affinity_cache.clear()
	_region_owner_cache.clear()
	_region_adjacency_cache.clear()
	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.region_id == &"":
			continue
		if not _region_tiles_cache.has(tile.region_id):
			_region_tiles_cache[tile.region_id] = [] as Array[Vector2i]
		_region_tiles_cache[tile.region_id].append(coord)

func get_tile(coord: Vector2i) -> TileState:
	return tiles.get(coord)

func get_movement_cost(coord: Vector2i, faction_id: StringName) -> float:
	var tile := get_tile(coord)
	if tile == null:
		return INF

	var base_cost: float = TERRAIN_COSTS.get(tile.terrain, 1.0)

	# Faction terrain affinity — factions move faster in aligned terrain
	var affinity: int
	if _faction_affinity_cache.has(faction_id):
		affinity = _faction_affinity_cache[faction_id]
	else:
		var fd: FactionData = DataManager.get_faction(faction_id)
		affinity = fd.realm_affinity if fd else -1
		_faction_affinity_cache[faction_id] = affinity
	if affinity >= 0:
		if affinity == Enums.Realm.VOID:
			# Void factions: -0.5 in Shard Wastes and Desert
			if tile.terrain == Enums.TerrainType.SHARD_WASTES:
				base_cost -= 0.5
			elif tile.terrain == Enums.TerrainType.DESERT:
				base_cost -= 0.3
		elif affinity == Enums.Realm.NATURE:
			# Nature factions: -0.5 in Jungle and Forest
			if tile.terrain == Enums.TerrainType.JUNGLE:
				base_cost -= 0.5
			elif tile.terrain == Enums.TerrainType.FOREST:
				base_cost -= 0.4
		elif affinity == Enums.Realm.MORTAL:
			# Mortal factions: -0.3 on Plains and Wetlands (civilized lands)
			if tile.terrain == Enums.TerrainType.PLAINS:
				base_cost -= 0.2
		elif affinity == Enums.Realm.ELEMENTAL:
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

	# Friendly territory development reduces movement cost
	if tile.owner_faction == faction_id and tile.development_level >= 1:
		if tile.development_level >= 3:
			base_cost *= 0.65
		elif tile.development_level >= 2:
			base_cost *= 0.75
		else:
			base_cost *= 0.85

	return maxf(base_cost, 0.5)

func get_region_tiles(region_id: StringName) -> Array[Vector2i]:
	if _region_tiles_cache.has(region_id):
		return _region_tiles_cache[region_id]
	var result: Array[Vector2i] = []
	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.region_id == region_id:
			result.append(coord)
	return result

func get_region_owner(region_id: StringName) -> StringName:
	if _region_owner_cache.has(region_id):
		return _region_owner_cache[region_id]
	var region_coords: Array[Vector2i] = get_region_tiles(region_id)
	var counts: Dictionary = {}
	for coord in region_coords:
		var tile: TileState = tiles[coord]
		if tile.owner_faction != &"":
			counts[tile.owner_faction] = counts.get(tile.owner_faction, 0) + 1
	if counts.is_empty():
		_region_owner_cache[region_id] = &""
		return &""
	var best_faction: StringName = &""
	var best_count := 0
	for faction_id in counts:
		if counts[faction_id] > best_count:
			best_count = counts[faction_id]
			best_faction = faction_id
	_region_owner_cache[region_id] = best_faction
	return best_faction

func regions_adjacent(region_a: StringName, region_b: StringName) -> bool:
	# Check if two regions share a border (any tile in A neighbors a tile in B).
	# Region layout is static after map generation — memoized permanently,
	# cleared only in build_region_cache().
	var pair_key := "%s|%s" % [region_a, region_b] if region_a < region_b else "%s|%s" % [region_b, region_a]
	if _region_adjacency_cache.has(pair_key):
		return _region_adjacency_cache[pair_key]
	var tiles_a := get_region_tiles(region_a)
	var tiles_b_set: Dictionary = {}
	for coord in get_region_tiles(region_b):
		tiles_b_set[coord] = true
	var adjacent := false
	for coord in tiles_a:
		for n in HexHelper.get_neighbors(coord):
			if tiles_b_set.has(n):
				adjacent = true
				break
		if adjacent:
			break
	_region_adjacency_cache[pair_key] = adjacent
	return adjacent

## Updates development_level (0-3) for all owned tiles based on nearby cities.
## City score = population + building_count. Full bonus within 2 tiles,
## linear falloff from tiles 3-4, no effect beyond 4. Overlapping cities
## use the highest value (not additive). Settlements (villages) count too.
## Thresholds: 0 = undeveloped, 1 = score 8+, 2 = score 15+, 3 = score 25+.
func update_development_levels(cities: Array) -> void:
	# Build lookup: faction_id -> [{hex_pos, score}]
	var faction_cities: Dictionary = {}
	for city in cities:
		var fid: StringName = city.faction_id
		if fid == &"" or fid == &"independent":
			continue
		if not faction_cities.has(fid):
			faction_cities[fid] = []
		var score: int = city.population + city.buildings.size()
		faction_cities[fid].append({hex_pos = city.hex_pos, score = score})

	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.owner_faction == &"":
			tile.development_level = 0
			continue
		var fcities: Array = faction_cities.get(tile.owner_faction, [])
		if fcities.is_empty():
			tile.development_level = 0
			continue
		# Use highest effective score from any nearby city (not additive)
		var best_effective := 0.0
		for cdata in fcities:
			var dist := HexHelper.hex_distance(coord, cdata.hex_pos)
			if dist > 5:
				continue
			var effective: float
			if dist <= 2:
				# Full bonus within 2 tiles
				effective = float(cdata.score)
			elif dist <= 4:
				# Linear falloff from tile 3 to 4 (at dist 3: 66%, at dist 4: 33%)
				effective = float(cdata.score) * (1.0 - float(dist - 2) / 3.0)
			else:
				# 15% at tile 5
				effective = float(cdata.score) * 0.15
			if effective > best_effective:
				best_effective = effective
		if best_effective >= 25.0:
			tile.development_level = 3
		elif best_effective >= 15.0:
			tile.development_level = 2
		elif best_effective >= 8.0:
			tile.development_level = 1
		else:
			tile.development_level = 0

func set_region_owner(region_id: StringName, faction_id: StringName) -> void:
	var region_coords: Array[Vector2i] = get_region_tiles(region_id)
	for coord in region_coords:
		var tile: TileState = tiles[coord]
		if tile.terrain == Enums.TerrainType.MOUNTAINS or tile.terrain == Enums.TerrainType.WATER:
			tile.owner_faction = &""
		else:
			tile.owner_faction = faction_id
	invalidate_region_owner(region_id)

## Assigns tile ownership based on Voronoi partition around cities.
## Each tile gets the faction of the closest city in its region.
## Mountains/water stay unowned. Independent cities don't claim tiles.
func set_city_territory_owner(cities: Array) -> void:
	# Group cities by region for efficient lookup
	var region_cities: Dictionary = {}
	for city in cities:
		var rid: StringName = city.region_id
		if not region_cities.has(rid):
			region_cities[rid] = []
		region_cities[rid].append(city)

	for coord in tiles:
		var tile: TileState = tiles[coord]
		if tile.terrain == Enums.TerrainType.MOUNTAINS or tile.terrain == Enums.TerrainType.WATER:
			tile.owner_faction = &""
			continue
		if tile.region_id == &"":
			continue
		var rcities: Array = region_cities.get(tile.region_id, [])
		if rcities.is_empty():
			tile.owner_faction = &""
			continue
		var closest_fid: StringName = &""
		var closest_dist := 999
		for city in rcities:
			var dist := HexHelper.hex_distance(coord, city.hex_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_fid = city.faction_id
		if closest_fid != &"" and closest_fid != &"independent":
			tile.owner_faction = closest_fid
		else:
			tile.owner_faction = &""
	invalidate_region_owner_cache()
	cleanup_ownership_pockets()
	update_development_levels(cities)

## Same as set_city_territory_owner but only for a single region.
func set_region_city_territory(region_id: StringName, cities: Array) -> void:
	var region_coords: Array[Vector2i] = get_region_tiles(region_id)
	for coord in region_coords:
		var tile: TileState = tiles[coord]
		if tile.terrain == Enums.TerrainType.MOUNTAINS or tile.terrain == Enums.TerrainType.WATER:
			tile.owner_faction = &""
			continue
		var closest_fid: StringName = &""
		var closest_dist := 999
		for city in cities:
			var dist := HexHelper.hex_distance(coord, city.hex_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_fid = city.faction_id
		if closest_fid != &"" and closest_fid != &"independent":
			tile.owner_faction = closest_fid
		else:
			tile.owner_faction = &""
	invalidate_region_owner(region_id)
	cleanup_ownership_pockets(region_id)
	update_development_levels(cities)

## Removes small isolated pockets of faction ownership.
## Finds connected components per faction; any component smaller than
## the threshold gets reassigned to the majority surrounding faction.
## Never reassigns components that contain a city.
## Runs multiple passes to catch cascading pockets.
func cleanup_ownership_pockets(only_region: StringName = &"") -> void:
	# Build set of city positions — these tiles must never be reassigned
	var city_positions: Dictionary = {}  # Vector2i -> true
	if GameManager.state:
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			city_positions[city.hex_pos] = true

	for _pass in 3:  # Multiple passes to handle cascading reassignment
		var changed := false
		# Build connected components of owned tiles (skipping mountains/water)
		var visited: Dictionary = {}
		var components: Array = []
		var iter_coords: Array = []
		if only_region != &"":
			iter_coords = get_region_tiles(only_region)
		else:
			iter_coords = tiles.keys()
		for coord in iter_coords:
			if visited.has(coord):
				continue
			var tile: TileState = tiles[coord]
			if only_region != &"" and tile.region_id != only_region:
				continue
			if tile.owner_faction == &"":
				continue
			# BFS to find connected component of same faction
			var faction: StringName = tile.owner_faction
			var comp_tiles: Array[Vector2i] = [coord]
			var has_city := city_positions.has(coord)
			visited[coord] = true
			var queue: Array[Vector2i] = [coord]
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				for n in HexHelper.get_neighbors(c):
					if visited.has(n):
						continue
					if not tiles.has(n):
						continue
					var ntile: TileState = tiles[n]
					if only_region != &"" and ntile.region_id != only_region:
						continue
					if ntile.owner_faction == faction:
						visited[n] = true
						comp_tiles.append(n)
						queue.append(n)
						if city_positions.has(n):
							has_city = true
			components.append({faction_id = faction, comp_tiles = comp_tiles, has_city = has_city})

		# Find the largest component per faction (main territory)
		var largest_per_faction: Dictionary = {}  # faction_id -> size
		for comp in components:
			var fid: StringName = comp.faction_id
			var sz: int = comp.comp_tiles.size()
			if sz > largest_per_faction.get(fid, 0):
				largest_per_faction[fid] = sz

		# Reassign small components (< 15% of largest, or < 8 tiles absolute)
		# NEVER reassign components that contain a city
		for comp in components:
			if comp.has_city:
				continue  # Protect city territory
			var fid: StringName = comp.faction_id
			var sz: int = comp.comp_tiles.size()
			var largest: int = largest_per_faction.get(fid, sz)
			# Skip if this IS the largest component or is big enough
			if sz == largest:
				continue
			if sz >= 8 and float(sz) / float(largest) >= 0.15:
				continue
			# Find majority surrounding faction
			var surround_counts: Dictionary = {}
			for coord in comp.comp_tiles:
				for n in HexHelper.get_neighbors(coord):
					if not tiles.has(n):
						continue
					var nf: StringName = tiles[n].owner_faction
					if nf != &"" and nf != fid:
						surround_counts[nf] = surround_counts.get(nf, 0) + 1
			var best_faction: StringName = &""
			var best_count := 0
			for f in surround_counts:
				if surround_counts[f] > best_count:
					best_count = surround_counts[f]
					best_faction = f
			if best_faction != &"":
				for coord in comp.comp_tiles:
					tiles[coord].owner_faction = best_faction
				changed = true
				invalidate_region_owner_cache()
		if not changed:
			break
