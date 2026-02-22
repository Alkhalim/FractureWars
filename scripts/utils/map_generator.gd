class_name MapGenerator

# Generates a hex map (HexMapData) with terrain, regions, and realm influence.
# Grid: 65 columns x 45 rows of hex tiles.
# Continental layout — five geographic arcs:
#   West:   Empire (Eternal Plains, Sunburst Valley, Aurentis)
#           + Gladehost (Sainkhu Groves, Verdant Glade, Orisyl)
#   North:  Moonspear (Iskar, Nightfall Sanctum, Asdrol)
#           + Thunderswarm (Dragonspire Mountains, Thundercrest Peaks, Skalvar)
#   South:  Tainted Jade (Coatlantli, Southern Reach, Xotchi)
#   Center: Skulloath (Bataarbad, Altaban, Tsagan)
#           + Cinderguard (Duststorm Valley, Ashenmark, Valkarn)
#   East:   Forsaken (Orenthal, Morvane, Weeping Barrows)
#           + Ivoryscar (Qareth, Torgalun Desert, Whispering Dunes)

# Region seed positions (in hex grid coordinates) — scaled for 65x45 grid
const REGION_SEEDS := {
	# ── Western Civilized Basin ──
	&"eternal_plains":       Vector2i(17, 18),
	&"sunburst_valley":      Vector2i(22, 13),
	&"aurentis":             Vector2i(12, 14),
	&"sainkhu_groves":       Vector2i(12, 24),
	&"verdant_glade":        Vector2i(18, 28),
	&"orisyl":               Vector2i(8, 19),

	# ── Northern Divine & Storm Belt ──
	&"iskar":                Vector2i(22, 5),
	&"nightfall_sanctum":    Vector2i(29, 6),
	&"asdrol":               Vector2i(16, 9),
	&"dragonspire_mountains": Vector2i(40, 5),
	&"thundercrest_peaks":   Vector2i(47, 8),
	&"skalvar":              Vector2i(35, 10),

	# ── Southern Emerald Reach ──
	&"coatlantli":           Vector2i(23, 36),
	&"southern_reach":       Vector2i(31, 39),
	&"xotchi":               Vector2i(16, 33),

	# ── Central Steppe & Ash March ──
	&"bataarbad":            Vector2i(29, 21),
	&"altaban":              Vector2i(34, 26),
	&"tsagan":               Vector2i(26, 27),
	&"duststorm_valley":     Vector2i(39, 18),
	&"ashenmark":            Vector2i(44, 23),
	&"valkarn":              Vector2i(42, 13),

	# ── Eastern Ruin & Shard Frontier ──
	&"orenthal":             Vector2i(51, 18),
	&"morvane":              Vector2i(53, 26),
	&"weeping_barrows":      Vector2i(48, 32),
	&"qareth":               Vector2i(57, 14),
	&"torgalun_desert":      Vector2i(59, 23),
	&"whispering_dunes":     Vector2i(56, 32),
}

# Continental zone definitions
const ZONE_WEST_EMPIRE := [&"eternal_plains", &"sunburst_valley", &"aurentis"]
const ZONE_WEST_GLADEHOST := [&"sainkhu_groves", &"verdant_glade", &"orisyl"]
const ZONE_NORTH_MOONSPEAR := [&"iskar", &"nightfall_sanctum", &"asdrol"]
const ZONE_NORTH_THUNDERSWARM := [&"dragonspire_mountains", &"thundercrest_peaks", &"skalvar"]
const ZONE_SOUTH_JADE := [&"coatlantli", &"southern_reach", &"xotchi"]
const ZONE_CENTER_SKULLOATH := [&"bataarbad", &"altaban", &"tsagan"]
const ZONE_CENTER_CINDERGUARD := [&"duststorm_valley", &"ashenmark", &"valkarn"]
const ZONE_EAST_FORSAKEN := [&"orenthal", &"morvane", &"weeping_barrows"]
const ZONE_EAST_IVORYSCAR := [&"qareth", &"torgalun_desert", &"whispering_dunes"]

static func generate_hex_map(regions: Dictionary) -> HexMapData:
	var map := HexMapData.new()

	# 1. Create all tiles - water by default
	_init_tiles(map)

	# 2. Carve landmass shape
	_carve_landmass(map)

	# 3. Assign regions via Voronoi from seeds
	_assign_regions(map, regions)

	# 4. Assign terrain based on zone
	_assign_terrain(map)

	# 5. Set realm influence from region data
	_assign_realm_influence(map, regions)

	# 6. Fix terrain pockets
	_fix_terrain_pockets(map)

	return map

static func _init_tiles(map: HexMapData) -> void:
	for col in range(HexMapData.MAP_WIDTH):
		for row in range(HexMapData.MAP_HEIGHT):
			var tile := HexMapData.TileState.new()
			tile.terrain = Enums.TerrainType.WATER
			map.tiles[Vector2i(col, row)] = tile

static func _carve_landmass(map: HexMapData) -> void:
	# Asymmetric continent built from multiple overlapping landmass blobs,
	# peninsulas, bays, and irregular coastline noise.
	# Each blob is an ellipse: {cx, cy, rx, ry, weight}
	# Higher weight = stronger contribution to land formation
	var blobs := [
		# Main continent body — off-center, slightly NW-biased
		{cx = 30.0, cy = 20.0, rx = 22.0, ry = 14.0, w = 1.0},
		# Western heartland (Empire/Gladehost) — bulges south-west
		{cx = 14.0, cy = 20.0, rx = 12.0, ry = 13.0, w = 0.8},
		# Northern ridge (Moonspear/Thunderswarm) — wide but narrow
		{cx = 32.0, cy = 8.0, rx = 20.0, ry = 7.0, w = 0.7},
		# Eastern arm (Forsaken/Ivoryscar) — long peninsula reaching east
		{cx = 52.0, cy = 22.0, rx = 12.0, ry = 14.0, w = 0.75},
		# Southern jungle (Tainted Jade) — teardrop hanging south
		{cx = 24.0, cy = 35.0, rx = 13.0, ry = 9.0, w = 0.7},
		# Central steppe bridge connecting west to east
		{cx = 38.0, cy = 18.0, rx = 14.0, ry = 8.0, w = 0.6},
		# NE highlands (Thunderswarm/Cinderguard connection)
		{cx = 44.0, cy = 12.0, rx = 10.0, ry = 8.0, w = 0.65},
		# SE barren hook (Weeping Barrows / Whispering Dunes)
		{cx = 50.0, cy = 30.0, rx = 10.0, ry = 8.0, w = 0.6},
	]

	# Bays / indentations — these subtract from the land (negative weight)
	var bays := [
		# Western bay between Empire and Gladehost
		{cx = 8.0, cy = 17.0, rx = 5.0, ry = 4.0, w = 0.4},
		# Southern bay splitting jungle from steppe
		{cx = 30.0, cy = 32.0, rx = 6.0, ry = 4.0, w = 0.35},
		# Northern inlet between Moonspear and Thunderswarm
		{cx = 34.0, cy = 4.0, rx = 7.0, ry = 3.0, w = 0.3},
		# Eastern strait separating Forsaken from Ivoryscar
		{cx = 55.0, cy = 19.0, rx = 3.0, ry = 6.0, w = 0.25},
		# NW coastal indent
		{cx = 10.0, cy = 10.0, rx = 5.0, ry = 5.0, w = 0.35},
	]

	for col in range(HexMapData.MAP_WIDTH):
		for row in range(HexMapData.MAP_HEIGHT):
			# Calculate land strength from all blobs
			var land_val := 0.0
			for blob in blobs:
				var dx: float = (float(col) - blob.cx) / blob.rx
				var dy: float = (float(row) - blob.cy) / blob.ry
				var d: float = dx * dx + dy * dy
				if d < 1.0:
					land_val += blob.w * (1.0 - d)

			# Subtract bays
			for bay in bays:
				var dx: float = (float(col) - bay.cx) / bay.rx
				var dy: float = (float(row) - bay.cy) / bay.ry
				var d: float = dx * dx + dy * dy
				if d < 1.0:
					land_val -= bay.w * (1.0 - d)

			# Multi-octave noise for irregular, natural-looking coastline
			var noise1 := _hash_coord(col, row) % 100 / 100.0 * 0.15
			var noise2 := _hash_coord(col * 3 + 7, row * 3 + 13) % 100 / 100.0 * 0.08
			var noise3 := _hash_coord(col * 7 + 31, row * 5 + 17) % 100 / 100.0 * 0.05
			land_val -= (noise1 + noise2 + noise3)

			# Land threshold
			if land_val > 0.12:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.PLAINS

			# Wetlands: coastal fringe
			elif land_val > 0.04:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.WETLANDS

static func _assign_regions(map: HexMapData, regions: Dictionary) -> void:
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue

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
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.WETLANDS:
			continue
		if tile.region_id == &"":
			continue

		var hash_val := _hash_coord(coord.x, coord.y)
		tile.terrain = _terrain_for_region(tile.region_id, hash_val)

static func _terrain_for_region(region_id: StringName, hash_val: int) -> Enums.TerrainType:
	var h10 := hash_val % 10

	# ── Western Civilized Basin — Empire ──
	if region_id in ZONE_WEST_EMPIRE:
		if region_id == &"eternal_plains":
			# Imperial heartland — open fields, scattered groves, rivers
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.PLAINS
		if region_id == &"sunburst_valley":
			# Warm valley with forest edges
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.DESERT
			return Enums.TerrainType.PLAINS
		# Aurentis — western province, rolling hills
		if h10 <= 2: return Enums.TerrainType.FOREST
		if h10 == 3: return Enums.TerrainType.MOUNTAINS
		return Enums.TerrainType.PLAINS

	# ── Western Civilized Basin — Gladehost ──
	if region_id in ZONE_WEST_GLADEHOST:
		if region_id == &"sainkhu_groves":
			# Dense ancient forest
			if h10 <= 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.FOREST
		if region_id == &"verdant_glade":
			# Mixed forest-plains
			if h10 <= 3: return Enums.TerrainType.FOREST
			if h10 == 4: return Enums.TerrainType.MOUNTAINS
			return Enums.TerrainType.PLAINS
		# Orisyl — misty coastal forest
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.WETLANDS
		return Enums.TerrainType.FOREST

	# ── Northern Divine — Moonspear ──
	if region_id in ZONE_NORTH_MOONSPEAR:
		if region_id == &"iskar":
			# Sacred citadel plateau
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS
			if h10 == 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		if region_id == &"nightfall_sanctum":
			# Dark forests and mountain passes
			if h10 <= 2: return Enums.TerrainType.MOUNTAINS
			if h10 <= 4: return Enums.TerrainType.FOREST
			if h10 == 5: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.TUNDRA
		# Asdrol — frozen tundra with peaks
		if h10 <= 1: return Enums.TerrainType.MOUNTAINS
		if h10 == 2: return Enums.TerrainType.FOREST
		return Enums.TerrainType.TUNDRA

	# ── Northern Storm Belt — Thunderswarm ──
	if region_id in ZONE_NORTH_THUNDERSWARM:
		if region_id == &"dragonspire_mountains":
			# Towering crystallized peaks
			if h10 <= 1: return Enums.TerrainType.TUNDRA
			if h10 == 2: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.MOUNTAINS
		if region_id == &"thundercrest_peaks":
			# Storm-battered ridges
			if h10 <= 1: return Enums.TerrainType.TUNDRA
			if h10 == 2: return Enums.TerrainType.DESERT
			return Enums.TerrainType.MOUNTAINS
		# Skalvar — mountain-steppe transition
		if h10 <= 1: return Enums.TerrainType.PLAINS
		if h10 <= 3: return Enums.TerrainType.TUNDRA
		return Enums.TerrainType.MOUNTAINS

	# ── Southern Emerald Reach — Tainted Jade ──
	if region_id in ZONE_SOUTH_JADE:
		if region_id == &"coatlantli":
			# Deep jungle with volcanic ridges
			if h10 <= 1: return Enums.TerrainType.SWAMP
			if h10 == 2: return Enums.TerrainType.MOUNTAINS
			if h10 == 3: return Enums.TerrainType.FOREST
			return Enums.TerrainType.JUNGLE
		if region_id == &"southern_reach":
			# Vast wetlands and mangroves
			if h10 <= 1: return Enums.TerrainType.JUNGLE
			if h10 == 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.SWAMP
		# Xotchi — ancient jungle sanctuary
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.MOUNTAINS
		if h10 == 3: return Enums.TerrainType.FOREST
		return Enums.TerrainType.JUNGLE

	# ── Central Steppe — Skulloath ──
	if region_id in ZONE_CENTER_SKULLOATH:
		if region_id == &"bataarbad":
			# Steppe heartland — nomad camps
			if h10 <= 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.TUNDRA
			if h10 == 3: return Enums.TerrainType.MOUNTAINS
			return Enums.TerrainType.DESERT
		if region_id == &"altaban":
			# Broken shard-scarred wasteland
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS
			if h10 <= 3: return Enums.TerrainType.DESERT
			if h10 == 4: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.SHARD_WASTES
		# Tsagan — deep corruption
		if h10 <= 1: return Enums.TerrainType.MOUNTAINS
		if h10 == 2: return Enums.TerrainType.DESERT
		if h10 == 3: return Enums.TerrainType.SWAMP
		return Enums.TerrainType.SHARD_WASTES

	# ── Ash March — Cinderguard ──
	if region_id in ZONE_CENTER_CINDERGUARD:
		if region_id == &"duststorm_valley":
			# Desert basin ringed by mountains
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS
			if h10 == 2: return Enums.TerrainType.PLAINS
			if h10 == 3: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		if region_id == &"ashenmark":
			# Volcanic ash plains
			if h10 <= 1: return Enums.TerrainType.MOUNTAINS
			if h10 == 2: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		# Valkarn — mountain fortress region
		if h10 <= 1: return Enums.TerrainType.DESERT
		if h10 == 2: return Enums.TerrainType.TUNDRA
		return Enums.TerrainType.MOUNTAINS

	# ── Eastern Ruin — Forsaken ──
	if region_id in ZONE_EAST_FORSAKEN:
		if region_id == &"orenthal":
			# Shard frontier capital
			if h10 <= 1: return Enums.TerrainType.DESERT
			if h10 <= 3: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.SHARD_WASTES
		if region_id == &"morvane":
			# Blighted marshlands
			if h10 <= 1: return Enums.TerrainType.SHARD_WASTES
			if h10 == 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.SWAMP
		# Weeping Barrows — toxic swamps
		if h10 <= 1: return Enums.TerrainType.SHARD_WASTES
		if h10 == 2: return Enums.TerrainType.MOUNTAINS
		return Enums.TerrainType.SWAMP

	# ── Shard Frontier — Ivoryscar ──
	if region_id in ZONE_EAST_IVORYSCAR:
		if region_id == &"qareth":
			# Desert citadel with ruins
			if h10 == 0: return Enums.TerrainType.PLAINS
			if h10 == 1: return Enums.TerrainType.MOUNTAINS
			if h10 == 2: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		if region_id == &"torgalun_desert":
			# Endless sand sea
			if h10 == 0: return Enums.TerrainType.WETLANDS
			if h10 == 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.MOUNTAINS
			return Enums.TerrainType.DESERT
		# Whispering Dunes — deep sand with buried ruins
		if h10 == 0: return Enums.TerrainType.SHARD_WASTES
		if h10 == 1: return Enums.TerrainType.MOUNTAINS
		return Enums.TerrainType.DESERT

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
	var passable: Dictionary = {}
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		passable[coord] = true

	if passable.is_empty():
		return

	# BFS from center
	var start := Vector2i(32, 22)
	if not passable.has(start):
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

	# Fix isolated pockets
	for coord in passable:
		if visited.has(coord):
			continue
		var neighbors := HexHelper.get_neighbors(coord)
		for n in neighbors:
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := map.get_tile(n)
			if ntile == null:
				continue
			if ntile.terrain == Enums.TerrainType.MOUNTAINS:
				ntile.terrain = Enums.TerrainType.PLAINS

	# Re-verify
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

	for coord in passable:
		if not visited.has(coord):
			var tile: HexMapData.TileState = map.tiles[coord]
			tile.terrain = Enums.TerrainType.WATER
			tile.region_id = &""

static func get_region_center(region_id: StringName) -> Vector2i:
	return REGION_SEEDS.get(region_id, Vector2i(32, 22))
