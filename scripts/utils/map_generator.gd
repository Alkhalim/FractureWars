class_name MapGenerator

# Generates a hex map (HexMapData) with terrain, regions, and realm influence.
# Grid: 50 columns x 35 rows of hex tiles.
# Continental layout based on lore document:
#   Center: Eternal Plains (Imperial Core)
#   North: Frozen Lands (Northern Highlands)
#   South: Southern Reach (Jungle Belt)
#   West: Torgalun Desert (Divine Plateau)
#   East: Wasteland (Fracture Zone)
#   Water borders around the continent edges

# Region seed positions (in hex grid coordinates)
# Spread more evenly for balanced region sizes
const REGION_SEEDS := {
	# Eternal Plains (center) - rows ~10-22, cols ~17-30
	&"metropoleia":          Vector2i(24, 15),
	&"sainkhu_groves":       Vector2i(18, 18),
	&"sunburst_valley":      Vector2i(30, 13),
	&"verdant_glade":        Vector2i(24, 21),

	# Frozen Lands (north) - rows ~2-10, cols ~18-32
	&"nightfall_sanctum":    Vector2i(20, 5),
	&"moonspear_citadel":    Vector2i(30, 6),
	&"thundercrest_peaks":   Vector2i(25, 3),

	# Southern Reach (south) - rows ~24-32, cols ~16-28
	&"coatlanli_jungle":     Vector2i(18, 28),
	&"misthaven_refuge":     Vector2i(27, 30),
	&"xotchis_sanctuary":    Vector2i(22, 25),

	# Torgalun Desert (west) - rows ~8-26, cols ~4-16
	&"bataarbad_expanse":    Vector2i(8, 14),
	&"duststorm_valley":     Vector2i(14, 10),
	&"great_pyramid":        Vector2i(10, 21),
	&"whispering_dunes":     Vector2i(5, 20),

	# Wasteland (east) - rows ~8-24, cols ~34-46
	&"altaban_barrens":      Vector2i(39, 15),
	&"dragonspire_mountains": Vector2i(36, 8),
	&"tsagan_badlands":      Vector2i(40, 23),
}

# Continental zone definitions: which regions belong to each zone
const ZONE_ETERNAL_PLAINS := [&"metropoleia", &"sainkhu_groves", &"sunburst_valley", &"verdant_glade"]
const ZONE_FROZEN_LANDS := [&"nightfall_sanctum", &"moonspear_citadel", &"thundercrest_peaks"]
const ZONE_SOUTHERN_REACH := [&"coatlanli_jungle", &"misthaven_refuge", &"xotchis_sanctuary"]
const ZONE_TORGALUN_DESERT := [&"bataarbad_expanse", &"duststorm_valley", &"great_pyramid", &"whispering_dunes"]
const ZONE_WASTELAND := [&"altaban_barrens", &"dragonspire_mountains", &"tsagan_badlands"]

static func generate_hex_map(regions: Dictionary) -> HexMapData:
	var map := HexMapData.new()

	# 1. Create all tiles - water by default (land is carved out)
	_init_tiles(map)

	# 2. Carve landmass shape
	_carve_landmass(map)

	# 3. Assign regions via Voronoi from seeds
	_assign_regions(map, regions)

	# 4. Assign terrain based on continental zone
	_assign_terrain(map)

	# 5. Set realm influence from region data
	_assign_realm_influence(map, regions)

	# 6. Fix terrain pockets - ensure all land tiles are reachable
	_fix_terrain_pockets(map)

	return map

static func _init_tiles(map: HexMapData) -> void:
	for col in range(HexMapData.MAP_WIDTH):
		for row in range(HexMapData.MAP_HEIGHT):
			var tile := HexMapData.TileState.new()
			tile.terrain = Enums.TerrainType.WATER
			map.tiles[Vector2i(col, row)] = tile

static func _carve_landmass(map: HexMapData) -> void:
	# Create a continent shape: oval-ish landmass with irregular edges
	# Center of the continent
	var cx := 24.0
	var cy := 17.0

	for col in range(HexMapData.MAP_WIDTH):
		for row in range(HexMapData.MAP_HEIGHT):
			# Normalized distance from center (elliptical)
			var dx := (float(col) - cx) / 22.0 # horizontal radius ~22
			var dy := (float(row) - cy) / 15.0 # vertical radius ~15

			# Base ellipse distance
			var dist := dx * dx + dy * dy

			# Add noise for irregular coastline
			var noise_val := _hash_coord(col, row) % 100 / 100.0 * 0.25
			dist += noise_val

			# Extend the continent in certain directions for the lore layout
			# West extension for Torgalun Desert
			if col < 16 and row > 8 and row < 26:
				dist *= 0.75
			# East extension for Wasteland
			if col > 32 and row > 6 and row < 26:
				dist *= 0.7
			# South extension for Southern Reach
			if row > 22 and col > 14 and col < 30:
				dist *= 0.75
			# North extension for Frozen Lands
			if row < 12 and col > 16 and col < 34:
				dist *= 0.8

			# Land threshold
			if dist < 1.0:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.PLAINS # Placeholder, overwritten by zone terrain

			# Coast tiles: just outside the landmass
			if dist >= 1.0 and dist < 1.15:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.COAST

static func _assign_regions(map: HexMapData, regions: Dictionary) -> void:
	# Assign each land tile to nearest region seed (Voronoi)
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue # Water tiles don't belong to regions

		var min_dist := 9999
		var closest_region: StringName = &""

		for region_id in REGION_SEEDS:
			if not regions.has(region_id):
				continue
			var seed_pos: Vector2i = REGION_SEEDS[region_id]
			var dist := HexHelper.hex_distance(coord, seed_pos)
			if dist < min_dist:
				min_dist = dist
				closest_region = region_id

		tile.region_id = closest_region

static func _assign_terrain(map: HexMapData) -> void:
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.COAST:
			continue
		if tile.region_id == &"":
			continue

		var hash_val := _hash_coord(coord.x, coord.y)
		tile.terrain = _terrain_for_region(tile.region_id, hash_val)

static func _terrain_for_region(region_id: StringName, hash_val: int) -> Enums.TerrainType:
	var h10 := hash_val % 10 # 0-9 for fine-grained distribution

	# ── Eternal Plains (center) — fertile heartland with rivers and groves ──
	if region_id in ZONE_ETERNAL_PLAINS:
		if region_id == &"sainkhu_groves":
			# Dense ancient forest with clearings and streams
			if h10 <= 1: return Enums.TerrainType.PLAINS # clearings
			if h10 == 2: return Enums.TerrainType.SWAMP # river banks
			return Enums.TerrainType.FOREST
		if region_id == &"verdant_glade":
			# Mixed forest-plains with gentle hills
			if h10 <= 3: return Enums.TerrainType.FOREST
			if h10 == 4: return Enums.TerrainType.MOUNTAINS # foothills
			return Enums.TerrainType.PLAINS
		if region_id == &"metropoleia":
			# Imperial heartland — mostly open, scattered groves
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.COAST # river delta
			return Enums.TerrainType.PLAINS
		# Sunburst Valley — warm plains with desert edge transition
		if h10 <= 1: return Enums.TerrainType.FOREST
		if h10 == 2: return Enums.TerrainType.DESERT # dry eastern edge
		return Enums.TerrainType.PLAINS

	# ── Frozen Lands (north) — harsh mountains, frozen forests, tundra ──
	if region_id in ZONE_FROZEN_LANDS:
		if region_id == &"thundercrest_peaks":
			# Towering mountain range with ice fields
			if h10 <= 1: return Enums.TerrainType.TUNDRA # frozen valleys
			if h10 == 2: return Enums.TerrainType.SHARD_WASTES # exposed crystal veins
			return Enums.TerrainType.MOUNTAINS
		if region_id == &"moonspear_citadel":
			# Tundra plateau with scattered peaks and frozen forest
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS
			if h10 == 2: return Enums.TerrainType.FOREST # frozen pine groves
			if h10 == 3: return Enums.TerrainType.PLAINS # sheltered valleys
			return Enums.TerrainType.TUNDRA
		# Nightfall Sanctum — dark forests and mountain passes
		if h10 <= 2: return Enums.TerrainType.MOUNTAINS
		if h10 <= 4: return Enums.TerrainType.FOREST # dark pine forest
		if h10 == 5: return Enums.TerrainType.SWAMP # frozen bogs
		return Enums.TerrainType.TUNDRA

	# ── Southern Reach (south) — dense jungle, misty swamps, hidden temples ──
	if region_id in ZONE_SOUTHERN_REACH:
		if region_id == &"misthaven_refuge":
			# Vast wetlands with deep pools and mangroves
			if h10 <= 1: return Enums.TerrainType.JUNGLE # mangrove edges
			if h10 == 2: return Enums.TerrainType.FOREST # raised land
			if h10 == 3: return Enums.TerrainType.COAST # coastal marshes
			return Enums.TerrainType.SWAMP
		if region_id == &"xotchis_sanctuary":
			# Heart of the jungle — towering canopy with ancient ruins
			if h10 <= 1: return Enums.TerrainType.SWAMP # jungle pools
			if h10 == 2: return Enums.TerrainType.MOUNTAINS # temple ruins on hillsides
			if h10 == 3: return Enums.TerrainType.FOREST # transitional forest
			return Enums.TerrainType.JUNGLE
		# Coatlanli Jungle — deep jungle with volcanic mountains
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.MOUNTAINS # volcanic ridge
		if h10 == 3: return Enums.TerrainType.FOREST
		return Enums.TerrainType.JUNGLE

	# ── Torgalun Desert (west) — vast dunes, oases, mountain passes ──
	if region_id in ZONE_TORGALUN_DESERT:
		if region_id == &"duststorm_valley":
			# Desert basin ringed by mountains
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS # basin walls
			if h10 == 2: return Enums.TerrainType.PLAINS # oasis
			if h10 == 3: return Enums.TerrainType.SHARD_WASTES # wind-exposed crystals
			return Enums.TerrainType.DESERT
		if region_id == &"great_pyramid":
			# Ancient monument in endless sand
			if h10 == 0: return Enums.TerrainType.PLAINS # irrigated fields
			if h10 == 1: return Enums.TerrainType.MOUNTAINS # buried ruins
			return Enums.TerrainType.DESERT
		if region_id == &"bataarbad_expanse":
			# Steppe transition: desert meeting plains
			if h10 <= 1: return Enums.TerrainType.PLAINS # nomad camps
			if h10 == 2: return Enums.TerrainType.TUNDRA # cold desert nights
			if h10 == 3: return Enums.TerrainType.MOUNTAINS # buttes
			return Enums.TerrainType.DESERT
		# Whispering Dunes — deep sand sea
		if h10 == 0: return Enums.TerrainType.COAST # coastal dunes
		if h10 == 1: return Enums.TerrainType.PLAINS # dried riverbed
		return Enums.TerrainType.DESERT

	# ── Wasteland (east) — shard-scarred landscape, crystalline wastes ──
	if region_id in ZONE_WASTELAND:
		if region_id == &"dragonspire_mountains":
			# Crystallized mountain range with shard veins
			if h10 <= 1: return Enums.TerrainType.SHARD_WASTES # exposed crystal
			if h10 == 2: return Enums.TerrainType.TUNDRA # high altitude
			if h10 == 3: return Enums.TerrainType.DESERT # rain shadow
			return Enums.TerrainType.MOUNTAINS
		if region_id == &"altaban_barrens":
			# Broken landscape: shattered plains, scattered peaks, sand
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS # jagged remnants
			if h10 <= 3: return Enums.TerrainType.DESERT # dry flats
			if h10 == 4: return Enums.TerrainType.PLAINS # rare fertile patch
			return Enums.TerrainType.SHARD_WASTES
		# Tsagan Badlands — deep wasteland, most corrupted
		if h10 <= 1: return Enums.TerrainType.MOUNTAINS # crystallized pillars
		if h10 == 2: return Enums.TerrainType.DESERT # ash flats
		if h10 == 3: return Enums.TerrainType.SWAMP # toxic pools
		return Enums.TerrainType.SHARD_WASTES

	return Enums.TerrainType.PLAINS

static func _assign_realm_influence(map: HexMapData, regions: Dictionary) -> void:
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		var region: RegionData = regions.get(tile.region_id)
		if region:
			tile.realm_influence = region.realm_influence

static func _hash_coord(col: int, row: int) -> int:
	var h := col * 374761393 + row * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)

static func _fix_terrain_pockets(map: HexMapData) -> void:
	# Find all passable land tiles (cost < INF) and flood-fill from the largest
	# connected component. Any disconnected tiles get their terrain changed to
	# something passable (Plains) so armies can't get trapped.
	var passable: Dictionary = {} # coord -> true
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		# Check if this tile is passable (mountains are passable but expensive)
		passable[coord] = true

	if passable.is_empty():
		return

	# BFS from the center of the map to find the main connected component
	var start := Vector2i(24, 15)
	if not passable.has(start):
		# Find any passable tile as start
		for coord in passable:
			start = coord
			break

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		var neighbors := HexHelper.get_neighbors(current)
		for n in neighbors:
			if visited.has(n):
				continue
			if not passable.has(n):
				continue
			visited[n] = true
			queue.append(n)

	# Any passable tile NOT in visited is in an isolated pocket
	# Check if it's surrounded by impassable terrain and fix it
	for coord in passable:
		if visited.has(coord):
			continue
		# This tile is isolated - check neighbors
		var neighbors := HexHelper.get_neighbors(coord)
		for n in neighbors:
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := map.get_tile(n)
			if ntile == null:
				continue
			# If neighbor is impassable mountain, make it passable
			if ntile.terrain == Enums.TerrainType.MOUNTAINS:
				# Convert to a passable terrain matching the region's zone
				ntile.terrain = Enums.TerrainType.PLAINS

	# Re-run BFS to verify - convert remaining isolated tiles to plains
	visited.clear()
	queue = [start]
	visited[start] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		var neighbors := HexHelper.get_neighbors(current)
		for n in neighbors:
			if visited.has(n):
				continue
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := map.get_tile(n)
			if ntile == null or ntile.terrain == Enums.TerrainType.WATER:
				continue
			visited[n] = true
			queue.append(n)

	# Force-connect any still-isolated land tiles
	for coord in passable:
		if not visited.has(coord):
			var tile: HexMapData.TileState = map.tiles[coord]
			# Convert to water if truly unreachable (small isolated islands)
			tile.terrain = Enums.TerrainType.WATER
			tile.region_id = &""

static func get_region_center(region_id: StringName) -> Vector2i:
	return REGION_SEEDS.get(region_id, Vector2i(24, 15))
