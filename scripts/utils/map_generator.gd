class_name MapGenerator

# Generates a hex map (HexMapData) with terrain, regions, and realm influence.
# Grid: 117 columns x 78 rows of hex tiles.
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

# Region seed positions (in hex grid coordinates) — scaled for 117x78 grid
const REGION_SEEDS := {
	# ── Western Civilized Basin ──
	&"eternal_plains":       Vector2i(31, 31),
	&"sunburst_valley":      Vector2i(39, 22),
	&"aurentis":             Vector2i(22, 25),
	&"sainkhu_groves":       Vector2i(22, 42),
	&"verdant_glade":        Vector2i(33, 48),
	&"orisyl":               Vector2i(14, 33),

	# ── Northern Divine & Storm Belt ──
	&"iskar":                Vector2i(39, 9),
	&"nightfall_sanctum":    Vector2i(52, 10),
	&"asdrol":               Vector2i(29, 16),
	&"dragonspire_mountains": Vector2i(72, 9),
	&"thundercrest_peaks":   Vector2i(85, 14),
	&"skalvar":              Vector2i(62, 17),

	# ── Southern Emerald Reach ──
	&"coatlantli":           Vector2i(42, 62),
	&"southern_reach":       Vector2i(56, 68),
	&"xotchi":               Vector2i(29, 57),

	# ── Central Steppe & Ash March ──
	&"bataarbad":            Vector2i(52, 36),
	&"altaban":              Vector2i(61, 46),
	&"tsagan":               Vector2i(47, 47),
	&"duststorm_valley":     Vector2i(70, 31),
	&"ashenmark":            Vector2i(79, 40),
	&"valkarn":              Vector2i(75, 22),

	# ── Eastern Ruin & Shard Frontier ──
	&"orenthal":             Vector2i(92, 31),
	&"morvane":              Vector2i(95, 46),
	&"weeping_barrows":      Vector2i(86, 56),
	&"qareth":               Vector2i(103, 25),
	&"torgalun_desert":      Vector2i(107, 40),
	&"whispering_dunes":     Vector2i(100, 56),
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

	# 4b. Place mountain ranges along faction borders
	_place_border_mountains(map)

	# 4c. Thin mountains to prevent thick blobs
	_thin_mountains(map)

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
		# Southern jungle (Tainted Jade) — teardrop hanging south
		{cx = 42.9, cy = 61.1, rx = 23.4, ry = 15.6, w = 0.7},
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
	# Mountains are placed separately by _place_border_mountains() along faction borders.
	# Base terrain here should NOT include mountains (or only very sparingly).
	var h10 := hash_val % 10

	# ── Western Civilized Basin — Empire ──
	if region_id in ZONE_WEST_EMPIRE:
		if region_id == &"eternal_plains":
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.PLAINS
		if region_id == &"sunburst_valley":
			if h10 <= 1: return Enums.TerrainType.FOREST
			if h10 == 2: return Enums.TerrainType.DESERT
			return Enums.TerrainType.PLAINS
		# Aurentis — rolling hills and forests
		if h10 <= 2: return Enums.TerrainType.FOREST
		return Enums.TerrainType.PLAINS

	# ── Western Civilized Basin — Gladehost ──
	if region_id in ZONE_WEST_GLADEHOST:
		if region_id == &"sainkhu_groves":
			if h10 <= 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.FOREST
		if region_id == &"verdant_glade":
			if h10 <= 3: return Enums.TerrainType.FOREST
			return Enums.TerrainType.PLAINS
		# Orisyl — misty coastal forest
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.WETLANDS
		return Enums.TerrainType.FOREST

	# ── Northern Divine — Moonspear ──
	if region_id in ZONE_NORTH_MOONSPEAR:
		if region_id == &"iskar":
			if h10 == 0: return Enums.TerrainType.FOREST
			if h10 == 1: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		if region_id == &"nightfall_sanctum":
			if h10 <= 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.TUNDRA
		# Asdrol — frozen tundra
		if h10 == 0: return Enums.TerrainType.FOREST
		return Enums.TerrainType.TUNDRA

	# ── Northern Storm Belt — Thunderswarm ──
	if region_id in ZONE_NORTH_THUNDERSWARM:
		if region_id == &"dragonspire_mountains":
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			if h10 <= 4: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		if region_id == &"thundercrest_peaks":
			if h10 == 0: return Enums.TerrainType.DESERT
			if h10 <= 4: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.TUNDRA
		# Skalvar — steppe transition
		if h10 <= 2: return Enums.TerrainType.TUNDRA
		if h10 <= 4: return Enums.TerrainType.DESERT
		return Enums.TerrainType.PLAINS

	# ── Southern Emerald Reach — Tainted Jade ──
	if region_id in ZONE_SOUTH_JADE:
		if region_id == &"coatlantli":
			if h10 <= 1: return Enums.TerrainType.SWAMP
			if h10 == 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.JUNGLE
		if region_id == &"southern_reach":
			if h10 <= 1: return Enums.TerrainType.JUNGLE
			if h10 == 2: return Enums.TerrainType.FOREST
			if h10 == 3: return Enums.TerrainType.WETLANDS
			return Enums.TerrainType.SWAMP
		# Xotchi — ancient jungle sanctuary
		if h10 <= 1: return Enums.TerrainType.SWAMP
		if h10 == 2: return Enums.TerrainType.FOREST
		return Enums.TerrainType.JUNGLE

	# ── Central Steppe — Skulloath ──
	if region_id in ZONE_CENTER_SKULLOATH:
		if region_id == &"bataarbad":
			if h10 <= 1: return Enums.TerrainType.PLAINS
			if h10 == 2: return Enums.TerrainType.TUNDRA
			return Enums.TerrainType.DESERT
		if region_id == &"altaban":
			if h10 <= 2: return Enums.TerrainType.DESERT
			if h10 == 3: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.SHARD_WASTES
		# Tsagan — deep corruption
		if h10 == 0: return Enums.TerrainType.DESERT
		if h10 == 1: return Enums.TerrainType.SWAMP
		return Enums.TerrainType.SHARD_WASTES

	# ── Ash March — Cinderguard ──
	if region_id in ZONE_CENTER_CINDERGUARD:
		if region_id == &"duststorm_valley":
			if h10 == 0: return Enums.TerrainType.PLAINS
			if h10 == 1: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		if region_id == &"ashenmark":
			if h10 == 0: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		# Valkarn — fortress region
		if h10 == 0: return Enums.TerrainType.TUNDRA
		return Enums.TerrainType.DESERT

	# ── Eastern Ruin — Forsaken ──
	if region_id in ZONE_EAST_FORSAKEN:
		if region_id == &"orenthal":
			if h10 <= 1: return Enums.TerrainType.DESERT
			if h10 <= 3: return Enums.TerrainType.SWAMP
			return Enums.TerrainType.SHARD_WASTES
		if region_id == &"morvane":
			if h10 <= 1: return Enums.TerrainType.SHARD_WASTES
			if h10 == 2: return Enums.TerrainType.FOREST
			return Enums.TerrainType.SWAMP
		# Weeping Barrows — toxic swamps
		if h10 <= 1: return Enums.TerrainType.SHARD_WASTES
		return Enums.TerrainType.SWAMP

	# ── Shard Frontier — Ivoryscar ──
	if region_id in ZONE_EAST_IVORYSCAR:
		if region_id == &"qareth":
			if h10 == 0: return Enums.TerrainType.PLAINS
			if h10 == 1: return Enums.TerrainType.SHARD_WASTES
			return Enums.TerrainType.DESERT
		if region_id == &"torgalun_desert":
			if h10 == 0: return Enums.TerrainType.WETLANDS
			if h10 == 1: return Enums.TerrainType.PLAINS
			return Enums.TerrainType.DESERT
		# Whispering Dunes — deep sand with buried ruins
		if h10 == 0: return Enums.TerrainType.SHARD_WASTES
		return Enums.TerrainType.DESERT

	return Enums.TerrainType.PLAINS

# ── Faction zone helpers ──────────────────────────────────────────────────────
# Maps region_id to the major faction zone it belongs to.

static func _get_faction_zone(region_id: StringName) -> StringName:
	if region_id in ZONE_WEST_EMPIRE: return &"empire"
	if region_id in ZONE_WEST_GLADEHOST: return &"gladehost"
	if region_id in ZONE_NORTH_MOONSPEAR: return &"moonspear"
	if region_id in ZONE_NORTH_THUNDERSWARM: return &"thunderswarm"
	if region_id in ZONE_SOUTH_JADE: return &"tainted_jade"
	if region_id in ZONE_CENTER_SKULLOATH: return &"skulloath"
	if region_id in ZONE_CENTER_CINDERGUARD: return &"cinderguard"
	if region_id in ZONE_EAST_FORSAKEN: return &"forsaken"
	if region_id in ZONE_EAST_IVORYSCAR: return &"ivoryscar"
	return &""

static func _zone_pair_key(a: StringName, b: StringName) -> String:
	if String(a) < String(b):
		return str(a) + "|" + str(b)
	return str(b) + "|" + str(a)

# Mountain range density along borders between major faction zones.
# Higher = denser mountains along that border.
const MOUNTAIN_BORDER_PROB := {
	"cinderguard|thunderswarm": 0.50,
	"moonspear|thunderswarm": 0.45,
	"cinderguard|forsaken": 0.42,
	"empire|moonspear": 0.40,
	"cinderguard|ivoryscar": 0.38,
	"empire|skulloath": 0.38,
	"moonspear|skulloath": 0.38,
	"cinderguard|skulloath": 0.35,
	"gladehost|tainted_jade": 0.35,
	"skulloath|tainted_jade": 0.32,
	"forsaken|ivoryscar": 0.30,
	"gladehost|skulloath": 0.25,
	"empire|gladehost": 0.18,
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
		# River 1: Western Divide (Empire ↔ Gladehost border, N-S) — with west branch
		{
			waypoints = [Vector2i(26, 18), Vector2i(23, 26), Vector2i(25, 34), Vector2i(29, 42)],
			crossings = [Vector2i(24, 22), Vector2i(24, 30), Vector2i(27, 38)],
			branches = [
				{
					from = Vector2i(23, 26),
					waypoints = [Vector2i(18, 30), Vector2i(14, 36)],
					crossings = [Vector2i(16, 33)],
				},
			],
		},
		# River 2: Northern Barrier (Moonspear/Thunderswarm border, W-E) — with north branch
		{
			waypoints = [Vector2i(30, 20), Vector2i(45, 18), Vector2i(60, 20), Vector2i(72, 22)],
			crossings = [Vector2i(37, 19), Vector2i(52, 19), Vector2i(66, 21)],
			branches = [
				{
					from = Vector2i(45, 18),
					waypoints = [Vector2i(48, 12), Vector2i(52, 6)],
					crossings = [Vector2i(50, 9)],
				},
			],
		},
		# River 3: Central-East Divide (Cinderguard/Skulloath ↔ Forsaken)
		{
			waypoints = [Vector2i(82, 16), Vector2i(84, 28), Vector2i(82, 40), Vector2i(80, 50)],
			crossings = [Vector2i(83, 22), Vector2i(83, 34), Vector2i(81, 45)],
			branches = [],
		},
		# River 4: Southern Divide (Tainted Jade ↔ central zones) — with south branch
		{
			waypoints = [Vector2i(26, 50), Vector2i(40, 52), Vector2i(55, 54), Vector2i(65, 52)],
			crossings = [Vector2i(33, 51), Vector2i(48, 53)],
			branches = [
				{
					from = Vector2i(40, 52),
					waypoints = [Vector2i(38, 58), Vector2i(34, 64)],
					crossings = [Vector2i(36, 61)],
				},
			],
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
		# Western isle → Orisyl coast
		[Vector2i(8, 29), Vector2i(9, 29), Vector2i(10, 30)],
		# Southern isle → Tainted Jade peninsula
		[Vector2i(31, 72), Vector2i(32, 71), Vector2i(33, 71), Vector2i(34, 70)],
		# SE island → Ivoryscar hook
		[Vector2i(108, 49), Vector2i(109, 49), Vector2i(110, 50)],
		# NE island → Thunderswarm finger
		[Vector2i(97, 7), Vector2i(96, 7), Vector2i(95, 7)],
		# NW archipelago → mainland
		[Vector2i(12, 12), Vector2i(13, 13), Vector2i(14, 14)],
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
