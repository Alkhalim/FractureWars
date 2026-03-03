class_name MapGenerator

# Generates a hex map (HexMapData) with terrain, regions, and realm influence.
# Grid: 117 columns x 78 rows of hex tiles.
# Continental layout — six geographic zones with scattered factions:
#   North:      Iskar, Asdrol, Nightfall Sanctum, Dragonspire Mtns, Thundercrest Peaks
#   West:       Verdant Glade, Aurentis, Sainkhu Groves, Orisyl
#   Center:     Sunburst Valley, Eternal Plains, Valkarn, Duststorm Valley, Bataarbad
#   East:       Skalvar, Ashenmark, Morvane, Whispering Dunes
#   South-West: Coatlantli, Altaban, Xotchi, Southern Reach, Orenthal
#   South-East: Tsagan, Torgalun Desert, Weeping Barrows, Qareth

# Region seed positions (in hex grid coordinates) — scaled for 117x78 grid
# Factions are scattered across zones for diverse cross-faction interactions.
const REGION_SEEDS := {
	# ── North Zone ──
	&"iskar":                Vector2i(30, 7),    # Moonspear
	&"asdrol":               Vector2i(36, 15),   # Luminarch
	&"nightfall_sanctum":    Vector2i(56, 8),    # Obsidian Order
	&"dragonspire_mountains": Vector2i(78, 8),   # Thunderswarm
	&"thundercrest_peaks":   Vector2i(92, 13),   # Stormbound

	# ── West Zone ──
	&"verdant_glade":        Vector2i(10, 26),   # Salt Reavers
	&"aurentis":             Vector2i(24, 21),   # Aurentis Guard
	&"sainkhu_groves":       Vector2i(18, 34),   # Gladehost
	&"orisyl":               Vector2i(14, 46),   # Miststriders

	# ── Center Zone ──
	&"sunburst_valley":      Vector2i(46, 24),   # Crimson Legion
	&"eternal_plains":       Vector2i(34, 32),   # Empire
	&"valkarn":              Vector2i(55, 34),   # Valkarn Garrison
	&"duststorm_valley":     Vector2i(62, 23),   # Cinderguard
	&"bataarbad":            Vector2i(62, 42),   # Skulloath

	# ── East Zone ──
	&"skalvar":              Vector2i(80, 21),   # Skalvar Watch
	&"ashenmark":            Vector2i(96, 20),   # Crownfire
	&"morvane":              Vector2i(100, 36),  # Bloodthrone
	&"whispering_dunes":     Vector2i(86, 48),   # Servants of Reliquary

	# ── South-West Zone ──
	&"coatlantli":           Vector2i(28, 48),   # Tainted Jade
	&"altaban":              Vector2i(46, 50),   # Thornwardens
	&"xotchi":               Vector2i(38, 56),   # Twilight Veil
	&"southern_reach":       Vector2i(16, 64),   # Jade Conclave
	&"orenthal":             Vector2i(36, 64),   # Forsaken

	# ── South-East Zone ──
	&"tsagan":               Vector2i(70, 54),   # Ashbound
	&"torgalun_desert":      Vector2i(56, 66),   # Gorgonic Cult
	&"weeping_barrows":      Vector2i(96, 56),   # Blightcoven
	&"qareth":               Vector2i(104, 62),  # Ivoryscar
}

# Geographic zone definitions (factions scattered across zones)
const ZONE_NORTH := [&"iskar", &"asdrol", &"nightfall_sanctum", &"dragonspire_mountains", &"thundercrest_peaks"]
const ZONE_WEST := [&"verdant_glade", &"aurentis", &"sainkhu_groves", &"orisyl"]
const ZONE_CENTER := [&"sunburst_valley", &"eternal_plains", &"valkarn", &"duststorm_valley", &"bataarbad"]
const ZONE_EAST := [&"skalvar", &"ashenmark", &"morvane", &"whispering_dunes"]
const ZONE_SOUTH_WEST := [&"coatlantli", &"altaban", &"xotchi", &"southern_reach", &"orenthal"]
const ZONE_SOUTH_EAST := [&"tsagan", &"torgalun_desert", &"weeping_barrows", &"qareth"]

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

	# 4b. Place mountain ranges along faction borders
	_place_border_mountains(map)

	# 4c. Thin mountains to prevent thick blobs
	_thin_mountains(map)

	# 4d. Fix small region pockets and mountain-isolated tiles
	_fix_region_pockets(map)

	# 5. Carve rivers through land
	_carve_rivers(map)

	# 6. Create wetland bridges to islands
	_create_wetland_bridges(map)

	# 7. Set realm influence from region data
	_assign_realm_influence(map, regions)

	# 8. Fix terrain pockets
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
		{cx = 54.6, cy = 35.1, rx = 39.0, ry = 24.7, w = 1.0},
		# Western heartland (Empire/Gladehost) — bulges south-west
		{cx = 24.7, cy = 35.1, rx = 22.1, ry = 22.1, w = 0.8},
		# Northern ridge (Moonspear/Thunderswarm) — wide but narrow
		{cx = 57.2, cy = 14.3, rx = 36.4, ry = 11.7, w = 0.7},
		# Eastern arm (Forsaken/Ivoryscar) — long peninsula reaching east
		{cx = 93.6, cy = 37.7, rx = 22.1, ry = 24.7, w = 0.75},
		# Southern jungle — teardrop hanging south (widened for scattered factions)
		{cx = 42.9, cy = 62.0, rx = 28.0, ry = 16.0, w = 0.7},
		# SW extension (Jade Conclave area)
		{cx = 16.0, cy = 64.0, rx = 12.0, ry = 10.0, w = 0.55},
		# SE extension (Ivoryscar area)
		{cx = 102.0, cy = 60.0, rx = 14.0, ry = 12.0, w = 0.55},
		# Central steppe bridge connecting west to east
		{cx = 68.9, cy = 31.2, rx = 24.7, ry = 14.3, w = 0.6},
		# NE highlands (Thunderswarm/Cinderguard connection)
		{cx = 79.3, cy = 20.8, rx = 18.2, ry = 14.3, w = 0.65},
		# SE barren hook (Weeping Barrows / Whispering Dunes)
		{cx = 89.7, cy = 52.0, rx = 18.2, ry = 14.3, w = 0.6},
	]

	# Peninsulas — thin rotated ellipses that extend from the coast
	# Each: {cx, cy, rx, ry, angle (radians), w}
	var peninsulas := [
		# Western coastal finger (Gladehost coast)
		{cx = 9.1, cy = 36.4, rx = 7.8, ry = 16.9, angle = 0.15, w = 0.55},
		# Northern Moonspear spur
		{cx = 36.4, cy = 3.9, rx = 15.6, ry = 5.2, angle = 0.0, w = 0.5},
		# Southern Tainted Jade peninsula
		{cx = 36.4, cy = 71.5, rx = 13.0, ry = 6.5, angle = 0.0, w = 0.5},
		# Eastern Ivoryscar hook
		{cx = 110.5, cy = 49.4, rx = 7.8, ry = 13.0, angle = 0.0, w = 0.5},
		# NE Thunderswarm finger
		{cx = 93.6, cy = 6.5, rx = 11.7, ry = 5.2, angle = 0.0, w = 0.5},
	]

	# Island chains — small detached blobs near coast (existing scaled + new larger islands)
	var islands := [
		# ── Existing islands (scaled ×1.3) ──
		# Western cluster off Orisyl
		{cx = 3.9, cy = 28.6, rx = 3.9, ry = 3.9, w = 0.6},
		{cx = 6.5, cy = 23.4, rx = 3.25, ry = 3.25, w = 0.55},
		# Southern reef off Tainted Jade
		{cx = 28.6, cy = 75.4, rx = 3.9, ry = 3.25, w = 0.55},
		{cx = 36.4, cy = 76.0, rx = 3.25, ry = 3.9, w = 0.5},
		# Eastern atoll off Ivoryscar
		{cx = 114.0, cy = 54.6, rx = 4.55, ry = 3.9, w = 0.55},
		# Northern peaks off Thunderswarm
		{cx = 84.5, cy = 1.3, rx = 3.9, ry = 3.25, w = 0.5},
		# ── New larger islands ──
		# Large Western Isle — off Gladehost coast
		{cx = 4.0, cy = 29.0, rx = 5.0, ry = 5.0, w = 0.65},
		# NW Archipelago chain
		{cx = 6.0, cy = 14.0, rx = 4.0, ry = 3.0, w = 0.6},
		{cx = 10.0, cy = 10.0, rx = 3.0, ry = 3.0, w = 0.55},
		# Large Southern Isle — off Tainted Jade
		{cx = 30.0, cy = 74.0, rx = 5.0, ry = 4.0, w = 0.65},
		# SE Island — off Ivoryscar
		{cx = 110.0, cy = 48.0, rx = 4.0, ry = 4.0, w = 0.6},
		# NE Island — off Thunderswarm
		{cx = 100.0, cy = 6.0, rx = 4.0, ry = 3.0, w = 0.6},
	]

	# Bays / indentations — these subtract from the land (negative weight)
	var bays := [
		# Western bay between Empire and Gladehost
		{cx = 14.3, cy = 29.9, rx = 9.1, ry = 6.5, w = 0.4},
		# Southern bay splitting jungle from steppe
		{cx = 54.6, cy = 55.9, rx = 10.4, ry = 6.5, w = 0.35},
		# Northern inlet between Moonspear and Thunderswarm
		{cx = 61.1, cy = 6.5, rx = 13.0, ry = 5.2, w = 0.3},
		# Eastern strait separating Forsaken from Ivoryscar
		{cx = 98.8, cy = 32.5, rx = 5.2, ry = 10.4, w = 0.25},
		# NW coastal indent
		{cx = 18.2, cy = 16.9, rx = 9.1, ry = 9.1, w = 0.35},
		# Central-south coastal indent
		{cx = 32.5, cy = 52.0, rx = 6.5, ry = 5.2, w = 0.3},
		# NE coastal bite
		{cx = 88.4, cy = 13.0, rx = 5.2, ry = 6.5, w = 0.25},
		# SW coastal notch
		{cx = 10.4, cy = 45.5, rx = 6.5, ry = 5.2, w = 0.3},
		# SE coastal bite
		{cx = 101.4, cy = 57.2, rx = 6.5, ry = 5.2, w = 0.25},
		# Mid-north fjord
		{cx = 45.5, cy = 7.8, rx = 3.9, ry = 6.5, w = 0.25},
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

			# Add peninsulas (rotated ellipses)
			for pen in peninsulas:
				var lx: float = float(col) - pen.cx
				var ly: float = float(row) - pen.cy
				var cos_a: float = cos(pen.angle)
				var sin_a: float = sin(pen.angle)
				var rx_f: float = (lx * cos_a + ly * sin_a) / pen.rx
				var ry_f: float = (-lx * sin_a + ly * cos_a) / pen.ry
				var d: float = rx_f * rx_f + ry_f * ry_f
				if d < 1.0:
					land_val += pen.w * (1.0 - d)

			# Add islands
			for isle in islands:
				var dx: float = (float(col) - isle.cx) / isle.rx
				var dy: float = (float(row) - isle.cy) / isle.ry
				var d: float = dx * dx + dy * dy
				if d < 1.0:
					land_val += isle.w * (1.0 - d)

			# Subtract bays
			for bay in bays:
				var dx: float = (float(col) - bay.cx) / bay.rx
				var dy: float = (float(row) - bay.cy) / bay.ry
				var d: float = dx * dx + dy * dy
				if d < 1.0:
					land_val -= bay.w * (1.0 - d)

			# Multi-octave noise for irregular, natural-looking coastline (4 octaves)
			var noise1 := _hash_coord(col, row) % 100 / 100.0 * 0.15
			var noise2 := _hash_coord(col * 3 + 7, row * 3 + 13) % 100 / 100.0 * 0.08
			var noise3 := _hash_coord(col * 7 + 31, row * 5 + 17) % 100 / 100.0 * 0.05
			var noise4 := _hash_coord(col * 13 + 53, row * 11 + 37) % 100 / 100.0 * 0.03
			land_val -= (noise1 + noise2 + noise3 + noise4)

			# Directional edge erosion — more erosion near map edges
			var edge_x := minf(float(col), float(HexMapData.MAP_WIDTH - 1 - col)) / 10.0
			var edge_y := minf(float(row), float(HexMapData.MAP_HEIGHT - 1 - row)) / 10.0
			var edge_factor := clampf(minf(edge_x, edge_y), 0.0, 1.0)
			land_val *= lerpf(0.5, 1.0, edge_factor)

			# Land threshold
			if land_val > 0.12:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.PLAINS

			# Wetlands: wider coastal fringe (connects islands to mainland)
			elif land_val > 0.01:
				var tile := map.get_tile(Vector2i(col, row))
				if tile:
					tile.terrain = Enums.TerrainType.WETLANDS

static func _assign_regions(map: HexMapData, regions: Dictionary) -> void:
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue

		var min_dist := 9999.0
		var closest_region: StringName = &""

		for region_id in REGION_SEEDS:
			if not regions.has(region_id):
				continue
			var seed_pos: Vector2i = REGION_SEEDS[region_id]
			var base_dist := float(HexHelper.hex_distance(coord, seed_pos))
			# Noise perturbation for organic, irregular borders
			var noise := float(_hash_coord(coord.x * 3 + seed_pos.x * 7, coord.y * 5 + seed_pos.y * 11) % 100) / 100.0 * 5.0 - 2.5
			var dist := base_dist + noise
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
	# Mountains are placed separately by _place_border_mountains() along zone borders.
	# Base terrain here should NOT include mountains (or only very sparingly).
	var h10 := hash_val % 10

	# ── North Zone — tundra-heavy ──
	if region_id in ZONE_NORTH:
		if region_id == &"iskar":
			# Moonspear — deep tundra
			if h10 == 0: return Enums.TerrainType.FOREST
			if h10 == 1: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		if region_id == &"asdrol":
			# Luminarch — frozen tundra
			if h10 == 0: return Enums.TerrainType.FOREST
			return Enums.TerrainType.TUNDRA
		if region_id == &"nightfall_sanctum":
			# Obsidian Order — tundra with dark forests
			if h10 <= 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.TUNDRA
		if region_id == &"dragonspire_mountains":
			# Thunderswarm — tundra/plains mix
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			if h10 <= 4: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		# thundercrest_peaks — Stormbound — tundra/plains
		if h10 == 0: return Enums.TerrainType.DESERT
		if h10 <= 4: return Enums.TerrainType.PLAINS
		return Enums.TerrainType.TUNDRA

	# ── West Zone — forest/swamp coastal ──
	if region_id in ZONE_WEST:
		if region_id == &"verdant_glade":
			# Salt Reavers — pirate-infested mangrove forests
			if h10 <= 2: return Enums.TerrainType.WETLANDS
			if h10 <= 4: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.FOREST
		if region_id == &"aurentis":
			# Aurentis Guard — plains/forest
			if h10 <= 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.PLAINS
		if region_id == &"sainkhu_groves":
			# Gladehost — deep forest
			if h10 <= 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.FOREST
		# orisyl — Miststriders — forest/swamp
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.WETLANDS
		return Enums.TerrainType.FOREST

	# ── Center Zone — plains/desert ──
	if region_id in ZONE_CENTER:
		if region_id == &"eternal_plains":
			# Empire — open plains
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.PLAINS
		if region_id == &"sunburst_valley":
			# Crimson Legion — plains
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.DESERT
			return Enums.TerrainType.PLAINS
		if region_id == &"valkarn":
			# Valkarn Garrison — plains/desert transition
			if h10 == 0: return Enums.TerrainType.TUNDRA
			if h10 <= 3: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.DESERT
		if region_id == &"duststorm_valley":
			# Cinderguard — plains/desert
			if h10 == 0: return Enums.TerrainType.PLAINS
			if h10 == 1: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		# bataarbad — Skulloath — desert/shard
		if h10 <= 1: return Enums.TerrainType.PLAINS
		if h10 == 2: return Enums.TerrainType.SHARD_WASTES
		return Enums.TerrainType.DESERT

	# ── East Zone — desert/shard ──
	if region_id in ZONE_EAST:
		if region_id == &"skalvar":
			# Skalvar Watch — desert/plains
			if h10 <= 2: return Enums.TerrainType.TUNDRA
			if h10 <= 4: return Enums.TerrainType.DESERT
			return Enums.TerrainType.PLAINS
		if region_id == &"ashenmark":
			# Crownfire — desert
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		if region_id == &"morvane":
			# Bloodthrone — desert/shard
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			if h10 == 1: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.DESERT
		# whispering_dunes — Servants of Reliquary — deep desert
		if h10 == 0: return Enums.TerrainType.SHARD_WASTES
		return Enums.TerrainType.DESERT

	# ── South-West Zone — jungle/swamp ──
	if region_id in ZONE_SOUTH_WEST:
		if region_id == &"coatlantli":
			# Tainted Jade — jungle
			if h10 <= 1: return Enums.TerrainType.SWAMP
			if h10 == 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.JUNGLE
		if region_id == &"altaban":
			# Thornwardens — dense forest/jungle
			if h10 <= 3: return Enums.TerrainType.FOREST
			if h10 <= 5: return Enums.TerrainType.JUNGLE
			return Enums.TerrainType.PLAINS
		if region_id == &"xotchi":
			# Twilight Veil — jungle
			if h10 <= 1: return Enums.TerrainType.SWAMP
			if h10 == 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.JUNGLE
		if region_id == &"southern_reach":
			# Jade Conclave — jungle/swamp
			if h10 <= 1: return Enums.TerrainType.JUNGLE
			if h10 == 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.SWAMP
		# orenthal — Forsaken — dark swamp/shard wastes (gothic, no jungle)
		if h10 <= 1: return Enums.TerrainType.FOREST
		if h10 <= 5: return Enums.TerrainType.SWAMP
		return Enums.TerrainType.SHARD_WASTES

	# ── South-East Zone — shard wastes/desert ──
	if region_id in ZONE_SOUTH_EAST:
		if region_id == &"tsagan":
			# Ashbound — shard wastes/desert
			if h10 == 0: return Enums.TerrainType.DESERT
			if h10 == 1: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.SHARD_WASTES
		if region_id == &"torgalun_desert":
			# Gorgonic Cult — shard wastes/desert
			if h10 == 0: return Enums.TerrainType.WETLANDS
			if h10 == 1: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.DESERT
		if region_id == &"weeping_barrows":
			# Blightcoven — shard wastes
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			if h10 <= 3: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.DESERT
		# qareth — Ivoryscar — desert
		if h10 == 0: return Enums.TerrainType.PLAINS
		if h10 == 1: return Enums.TerrainType.SHARD_WASTES
		return Enums.TerrainType.DESERT

	return Enums.TerrainType.PLAINS

# ── Geographic zone helpers ───────────────────────────────────────────────────
# Maps region_id to its geographic zone.

static func _get_faction_zone(region_id: StringName) -> StringName:
	if region_id in ZONE_NORTH: return &"north"
	if region_id in ZONE_WEST: return &"west"
	if region_id in ZONE_CENTER: return &"center"
	if region_id in ZONE_EAST: return &"east"
	if region_id in ZONE_SOUTH_WEST: return &"south_west"
	if region_id in ZONE_SOUTH_EAST: return &"south_east"
	return &""

static func _zone_pair_key(a: StringName, b: StringName) -> String:
	if String(a) < String(b):
		return str(a) + "|" + str(b)
	return str(b) + "|" + str(a)

# Mountain range density along borders between geographic zones.
# Higher = denser mountains along that border.
const MOUNTAIN_BORDER_PROB := {
	"north|east": 0.48,
	"center|north": 0.45,
	"north|west": 0.40,
	"center|east": 0.38,
	"center|south_west": 0.35,
	"center|south_east": 0.32,
	"east|south_east": 0.30,
	"south_east|south_west": 0.25,
	"south_west|west": 0.22,
	"center|west": 0.20,
}

# ── Border Mountain Placement ─────────────────────────────────────────────────
# Places narrow mountain ranges along borders between different faction zones.

static func _place_border_mountains(map: HexMapData) -> void:
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.WETLANDS:
			continue
		if tile.region_id == &"":
			continue

		var my_zone := _get_faction_zone(tile.region_id)
		if my_zone == &"":
			continue

		# Check if this tile borders a different faction zone
		var best_prob := 0.0
		for n in HexHelper.get_neighbors(coord):
			var ntile := map.get_tile(n)
			if ntile == null or ntile.terrain == Enums.TerrainType.WATER:
				continue
			if ntile.region_id == &"" or ntile.region_id == tile.region_id:
				continue
			var neighbor_zone := _get_faction_zone(ntile.region_id)
			if neighbor_zone == &"" or neighbor_zone == my_zone:
				continue
			var key := _zone_pair_key(my_zone, neighbor_zone)
			var prob: float = MOUNTAIN_BORDER_PROB.get(key, 0.0)
			if prob > best_prob:
				best_prob = prob

		if best_prob > 0.0:
			var h := _hash_coord(coord.x * 7 + 11, coord.y * 13 + 23)
			if float(h % 100) / 100.0 < best_prob:
				tile.terrain = Enums.TerrainType.MOUNTAINS

# ── Mountain Thinning ─────────────────────────────────────────────────────────
# Prevents thick mountain blobs by removing tiles with too many mountain
# neighbors and cleaning up isolated single peaks.

static func _thin_mountains(map: HexMapData) -> void:
	# Pass 1: Remove tiles in thick blobs (>= 4 mountain neighbors)
	var to_remove: Array[Vector2i] = []
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain != Enums.TerrainType.MOUNTAINS:
			continue
		var mountain_neighbors := 0
		for n in HexHelper.get_neighbors(coord):
			var ntile := map.get_tile(n)
			if ntile and ntile.terrain == Enums.TerrainType.MOUNTAINS:
				mountain_neighbors += 1
		if mountain_neighbors >= 4:
			to_remove.append(coord)

	for coord in to_remove:
		var tile := map.get_tile(coord)
		if tile:
			tile.terrain = _terrain_for_region(tile.region_id, _hash_coord(coord.x + 7, coord.y + 13))

	# Pass 2: Remove isolated mountains (0 mountain neighbors)
	to_remove.clear()
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain != Enums.TerrainType.MOUNTAINS:
			continue
		var mountain_neighbors := 0
		for n in HexHelper.get_neighbors(coord):
			var ntile := map.get_tile(n)
			if ntile and ntile.terrain == Enums.TerrainType.MOUNTAINS:
				mountain_neighbors += 1
		if mountain_neighbors == 0:
			to_remove.append(coord)

	for coord in to_remove:
		var tile := map.get_tile(coord)
		if tile:
			tile.terrain = _terrain_for_region(tile.region_id, _hash_coord(coord.x + 7, coord.y + 13))

# ── Region Pocket Cleanup ────────────────────────────────────────────────────
# Removes small isolated pockets where Voronoi noise placed 1-2 tiles of one
# region inside another. Also reassigns tiles connected to their region only
# through mountain tiles (impassable connectivity).

static func _fix_region_pockets(map: HexMapData) -> void:
	# Pass 1: Find connected components per region using passable tiles (no water, no mountains)
	var visited: Dictionary = {}
	var components: Array = []

	for coord in map.tiles:
		if visited.has(coord):
			continue
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.MOUNTAINS:
			continue
		if tile.region_id == &"":
			continue

		var region_id := tile.region_id
		var seed_pos: Vector2i = REGION_SEEDS.get(region_id, Vector2i(-1, -1))
		var comp_tiles: Array[Vector2i] = [coord]
		var has_seed := (coord == seed_pos)
		visited[coord] = true
		var queue: Array[Vector2i] = [coord]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for n in HexHelper.get_neighbors(c):
				if visited.has(n):
					continue
				if not map.tiles.has(n):
					continue
				var ntile: HexMapData.TileState = map.tiles[n]
				if ntile.terrain == Enums.TerrainType.WATER or ntile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
				if ntile.region_id != region_id:
					continue
				visited[n] = true
				comp_tiles.append(n)
				queue.append(n)
				if n == seed_pos:
					has_seed = true
		components.append({region_id = region_id, tiles = comp_tiles, has_seed = has_seed})

	# Find largest component per region
	var largest: Dictionary = {}
	for comp in components:
		var rid: StringName = comp.region_id
		var sz: int = comp.tiles.size()
		if sz > largest.get(rid, 0):
			largest[rid] = sz

	# Reassign small components (< 5 tiles, not having seed, not the largest)
	for comp in components:
		if comp.has_seed:
			continue
		var rid: StringName = comp.region_id
		var sz: int = comp.tiles.size()
		if sz >= 5 and sz == largest.get(rid, 0):
			continue
		# Find majority neighboring region (non-mountain, non-water neighbors)
		var neighbor_counts: Dictionary = {}
		for coord in comp.tiles:
			for n in HexHelper.get_neighbors(coord):
				if not map.tiles.has(n):
					continue
				var ntile: HexMapData.TileState = map.tiles[n]
				if ntile.terrain == Enums.TerrainType.WATER:
					continue
				if ntile.region_id == rid or ntile.region_id == &"":
					continue
				neighbor_counts[ntile.region_id] = neighbor_counts.get(ntile.region_id, 0) + 1
		var best_rid: StringName = &""
		var best_count := 0
		for nrid in neighbor_counts:
			if neighbor_counts[nrid] > best_count:
				best_count = neighbor_counts[nrid]
				best_rid = nrid
		if best_rid != &"":
			for coord in comp.tiles:
				map.tiles[coord].region_id = best_rid

	# Pass 2: Reassign mountain tiles that have no same-region non-mountain neighbors
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain != Enums.TerrainType.MOUNTAINS:
			continue
		if tile.region_id == &"":
			continue
		var has_same_region_passable := false
		for n in HexHelper.get_neighbors(coord):
			if not map.tiles.has(n):
				continue
			var ntile: HexMapData.TileState = map.tiles[n]
			if ntile.region_id == tile.region_id and ntile.terrain != Enums.TerrainType.WATER and ntile.terrain != Enums.TerrainType.MOUNTAINS:
				has_same_region_passable = true
				break
		if has_same_region_passable:
			continue
		# Reassign to majority neighboring region
		var neighbor_counts: Dictionary = {}
		for n in HexHelper.get_neighbors(coord):
			if not map.tiles.has(n):
				continue
			var ntile: HexMapData.TileState = map.tiles[n]
			if ntile.region_id != &"" and ntile.region_id != tile.region_id:
				neighbor_counts[ntile.region_id] = neighbor_counts.get(ntile.region_id, 0) + 1
		var best_rid: StringName = &""
		var best_count := 0
		for nrid in neighbor_counts:
			if neighbor_counts[nrid] > best_count:
				best_count = neighbor_counts[nrid]
				best_rid = nrid
		if best_rid != &"":
			tile.region_id = best_rid

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

# ── Rivers ──────────────────────────────────────────────────────────────────────
# Carves rivers as lines of WATER tiles with WETLANDS crossing points (fords).

static func _carve_rivers(map: HexMapData) -> void:
	var rivers := [
		# River 1: Northern Barrier (W-E) — separates tundra from temperate belt
		{
			waypoints = [Vector2i(20, 18), Vector2i(38, 19), Vector2i(58, 17), Vector2i(75, 18), Vector2i(90, 18)],
			crossings = [Vector2i(30, 19), Vector2i(48, 18), Vector2i(66, 17), Vector2i(82, 18)],
			branches = [],
		},
		# River 2: Western Divide (N-S) — between forest coast and central plains
		{
			waypoints = [Vector2i(22, 18), Vector2i(24, 28), Vector2i(26, 38), Vector2i(24, 48)],
			crossings = [Vector2i(23, 23), Vector2i(25, 33), Vector2i(25, 43)],
			branches = [],
		},
		# River 3: Central Divide (N-S) — between center and eastern desert
		{
			waypoints = [Vector2i(76, 18), Vector2i(74, 28), Vector2i(76, 38), Vector2i(78, 50)],
			crossings = [Vector2i(75, 23), Vector2i(75, 33), Vector2i(77, 44)],
			branches = [],
		},
		# River 4: Southern Divide (W-E) — between mid-regions and southern jungles/wastes
		{
			waypoints = [Vector2i(14, 52), Vector2i(32, 46), Vector2i(50, 46), Vector2i(66, 48), Vector2i(84, 52)],
			crossings = [Vector2i(23, 49), Vector2i(42, 46), Vector2i(58, 47), Vector2i(76, 50)],
			branches = [],
		},
	]

	for river in rivers:
		_carve_river_segment(map, river.waypoints, river.crossings)
		for branch in river.branches:
			var branch_wps: Array = [branch.from]
			branch_wps.append_array(branch.waypoints)
			_carve_river_segment(map, branch_wps, branch.crossings)

static func _carve_river_segment(map: HexMapData, waypoints: Array, crossings: Array) -> void:
	var tiles_since_crossing := 0
	for i in range(waypoints.size() - 1):
		var from: Vector2i = waypoints[i]
		var to: Vector2i = waypoints[i + 1]
		var path := _hex_line(from, to)

		for j in range(path.size()):
			var pos: Vector2i = path[j]
			var tile := map.get_tile(pos)
			if tile == null:
				continue
			if tile.terrain == Enums.TerrainType.WATER:
				continue

			var near_crossing := false
			for cp in crossings:
				if HexHelper.hex_distance(pos, cp) <= 1:
					near_crossing = true
					break

			# Force a crossing if 9+ consecutive water tiles without one
			if tiles_since_crossing >= 9:
				near_crossing = true

			if near_crossing:
				tile.terrain = Enums.TerrainType.WETLANDS
				tiles_since_crossing = 0
			else:
				tile.terrain = Enums.TerrainType.WATER
				tile.region_id = &""
				tiles_since_crossing += 1

static func _hex_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	# Interpolate a line between two hex positions using cube coordinates
	var result: Array[Vector2i] = []
	var n := HexHelper.hex_distance(from, to)
	if n == 0:
		result.append(from)
		return result

	var from_cube := HexHelper.offset_to_cube(from.x, from.y)
	var to_cube := HexHelper.offset_to_cube(to.x, to.y)

	for i in range(n + 1):
		var t := float(i) / float(n)
		var fx := lerpf(float(from_cube.x), float(to_cube.x), t)
		var fy := lerpf(float(from_cube.y), float(to_cube.y), t)
		var fz := lerpf(float(from_cube.z), float(to_cube.z), t)
		# Cube round
		var q := roundi(fx)
		var r := roundi(fy)
		var s := roundi(fz)
		var q_diff := absf(float(q) - fx)
		var r_diff := absf(float(r) - fy)
		var s_diff := absf(float(s) - fz)
		if q_diff > r_diff and q_diff > s_diff:
			q = -r - s
		elif r_diff > s_diff:
			r = -q - s
		else:
			s = -q - r
		result.append(HexHelper.cube_to_offset(Vector3i(q, r, s)))

	return result

# ── Wetland Bridges ─────────────────────────────────────────────────────────────
# Connect outer islands to the mainland via chains of WETLANDS tiles.

static func _create_wetland_bridges(map: HexMapData) -> void:
	# Each bridge is a list of tile positions to set as WETLANDS
	var bridges := [
		# Western isle → Verdant Glade/West coast
		[Vector2i(8, 29), Vector2i(9, 29), Vector2i(10, 28)],
		# Southern isle → SW jungle
		[Vector2i(31, 72), Vector2i(32, 71), Vector2i(33, 70), Vector2i(34, 69)],
		# SE island → Qareth/SE zone
		[Vector2i(108, 58), Vector2i(109, 58), Vector2i(110, 59)],
		# NE island → Thundercrest coast
		[Vector2i(97, 7), Vector2i(96, 8), Vector2i(95, 9)],
		# NW archipelago → mainland
		[Vector2i(12, 12), Vector2i(13, 13), Vector2i(14, 14)],
		# SW extension bridge → Southern Reach
		[Vector2i(14, 60), Vector2i(15, 61), Vector2i(16, 62)],
	]

	for bridge in bridges:
		for pos in bridge:
			var tile := map.get_tile(pos)
			if tile:
				tile.terrain = Enums.TerrainType.WETLANDS

static func _fix_terrain_pockets(map: HexMapData) -> void:
	# Phase 1: Ensure ground connectivity (mountains treated as barriers).
	# Armies without flying units cannot cross mountains, so every land area
	# must be reachable without crossing mountain tiles.
	_create_mountain_passes(map)
	# Phase 2: Remove any remaining water-isolated land pockets.
	_remove_isolated_land(map)

static func _create_mountain_passes(map: HexMapData) -> void:
	for _attempt in 10:
		# Build passable set (non-water, non-mountain)
		var passable: Dictionary = {}
		for coord in map.tiles:
			var tile: HexMapData.TileState = map.tiles[coord]
			if tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.MOUNTAINS:
				passable[coord] = true
		if passable.is_empty():
			return

		# BFS from map center
		var start := Vector2i(59, 39)
		if not passable.has(start):
			for coord in passable:
				start = coord
				break
		var visited: Dictionary = {}
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		while queue.size() > 0:
			var current: Vector2i = queue.pop_front()
			for n in HexHelper.get_neighbors(current):
				if visited.has(n) or not passable.has(n):
					continue
				visited[n] = true
				queue.append(n)

		# Find first disconnected tile
		var disconnected := Vector2i(-1, -1)
		for coord in passable:
			if not visited.has(coord):
				disconnected = coord
				break
		if disconnected == Vector2i(-1, -1):
			return # All connected

		# BFS from disconnected tile through ALL non-water tiles (including mountains)
		# to find a path to the connected set, then punch through mountains
		var parent: Dictionary = {}
		parent[disconnected] = disconnected # root sentinel
		var q: Array[Vector2i] = [disconnected]
		var pass_made := false
		while q.size() > 0 and not pass_made:
			var current: Vector2i = q.pop_front()
			for n in HexHelper.get_neighbors(current):
				if parent.has(n):
					continue
				if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
					continue
				var ntile := map.get_tile(n)
				if ntile == null or ntile.terrain == Enums.TerrainType.WATER:
					continue
				parent[n] = current
				if visited.has(n):
					# Trace back from current to root, converting mountains to plains
					var trace: Vector2i = current
					while trace != disconnected:
						var ttile := map.get_tile(trace)
						if ttile and ttile.terrain == Enums.TerrainType.MOUNTAINS:
							ttile.terrain = Enums.TerrainType.PLAINS
						trace = parent[trace]
					pass_made = true
					break
				q.append(n)
		if not pass_made:
			return # Remaining isolation is water-based, handled by Phase 2

static func _remove_isolated_land(map: HexMapData) -> void:
	var land: Dictionary = {}
	for coord in map.tiles:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain != Enums.TerrainType.WATER:
			land[coord] = true
	if land.is_empty():
		return
	var start := Vector2i(59, 39)
	if not land.has(start):
		for coord in land:
			start = coord
			break
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for n in HexHelper.get_neighbors(current):
			if visited.has(n) or not land.has(n):
				continue
			visited[n] = true
			queue.append(n)
	for coord in land:
		if not visited.has(coord):
			var tile: HexMapData.TileState = map.tiles[coord]
			tile.terrain = Enums.TerrainType.WATER
			tile.region_id = &""

static func get_region_center(region_id: StringName) -> Vector2i:
	return REGION_SEEDS.get(region_id, Vector2i(59, 39))
