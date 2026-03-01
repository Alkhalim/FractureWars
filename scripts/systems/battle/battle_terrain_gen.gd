class_name BattleTerrainGen
extends RefCounted

const GRID_WIDTH := 20
const GRID_HEIGHT := 16

# Deployment zones should stay mostly open
const DEPLOY_TOP_END := 5
const DEPLOY_BOTTOM_START := 10

# Default reference area for scaling cluster counts
const _REF_AREA := 28.0 * 22.0

# Terrain properties: [speed_modifier, defense_bonus, passable]
const TERRAIN_PROPS := {
	Enums.BattleTerrain.OPEN:    [1.0,  0, true],
	Enums.BattleTerrain.FOREST:  [0.6,  3, true],
	Enums.BattleTerrain.ROCK:    [0.0,  0, false],
	Enums.BattleTerrain.WATER:   [0.3, -2, true],
	Enums.BattleTerrain.SAND:    [0.7,  0, true],
	Enums.BattleTerrain.MUD:     [0.4, -1, true],
	Enums.BattleTerrain.ICE:     [0.8,  0, true],
	Enums.BattleTerrain.CRYSTAL: [0.0,  0, false],
	Enums.BattleTerrain.BRUSH:   [0.8,  1, true],
}

static func get_speed_modifier(terrain: Enums.BattleTerrain) -> float:
	return TERRAIN_PROPS[terrain][0]

static func get_defense_bonus(terrain: Enums.BattleTerrain) -> int:
	return TERRAIN_PROPS[terrain][1]

static func is_passable(terrain: Enums.BattleTerrain) -> bool:
	return TERRAIN_PROPS[terrain][2]

static func generate(campaign_terrain: Enums.TerrainType, seed_value: int,
		grid_w: int = 28, grid_h: int = 22) -> Dictionary:
	var terrain: Dictionary = {} # Vector2i -> Enums.BattleTerrain

	# Scale factor for cluster counts relative to default grid size
	var scale := float(grid_w * grid_h) / _REF_AREA

	# Fill with OPEN
	for y in range(grid_h):
		for x in range(grid_w):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.OPEN

	# Scatter features based on campaign terrain
	match campaign_terrain:
		Enums.TerrainType.PLAINS:
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, _scaled(2, scale), 3, 5, seed_value, grid_w, grid_h)
		Enums.TerrainType.FOREST:
			_scatter_clusters(terrain, Enums.BattleTerrain.FOREST, _scaled(4, scale), 4, 8, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, _scaled(2, scale), 2, 4, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.MOUNTAINS:
			_scatter_clusters(terrain, Enums.BattleTerrain.ROCK, _scaled(3, scale), 3, 6, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, _scaled(2, scale), 2, 4, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.DESERT:
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, _scaled(4, scale), 5, 10, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, _scaled(1, scale), 2, 4, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.SWAMP:
			_scatter_clusters(terrain, Enums.BattleTerrain.MUD, _scaled(4, scale), 4, 8, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, _scaled(3, scale), 3, 6, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.TUNDRA:
			_scatter_clusters(terrain, Enums.BattleTerrain.ICE, _scaled(3, scale), 4, 7, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.ROCK, _scaled(2, scale), 2, 4, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.JUNGLE:
			_scatter_clusters(terrain, Enums.BattleTerrain.FOREST, _scaled(5, scale), 5, 10, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.MUD, _scaled(2, scale), 3, 5, seed_value + 100, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, _scaled(3, scale), 2, 4, seed_value + 200, grid_w, grid_h)
		Enums.TerrainType.SHARD_WASTES:
			_scatter_clusters(terrain, Enums.BattleTerrain.CRYSTAL, _scaled(3, scale), 3, 6, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, _scaled(2, scale), 2, 4, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.WETLANDS:
			_place_water_edge(terrain, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, _scaled(3, scale), 4, 7, seed_value + 100, grid_w, grid_h)
		Enums.TerrainType.WATER:
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, _scaled(5, scale), 5, 10, seed_value, grid_w, grid_h)
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, _scaled(2, scale), 3, 5, seed_value + 100, grid_w, grid_h)

	# Ensure deployment zones are mostly open
	_clear_deployment_zones(terrain, grid_w, grid_h)

	return terrain

static func _scaled(base_count: int, scale: float) -> int:
	return maxi(1, roundi(base_count * scale))

static func _hash_pos(x: int, y: int, seed_val: int) -> int:
	var h := (x * 374761393 + y * 668265263 + seed_val * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245 + 12345) & 0x7FFFFFFF
	return h

static func _noise_hash(x: float, y: float, seed_val: int) -> float:
	# Simple value-noise-like hash returning 0.0 to 1.0
	var ix: int = int(floorf(x))
	var iy: int = int(floorf(y))
	var fx: float = x - floorf(x)
	var fy: float = y - floorf(y)
	# Smooth interpolation
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := float(_hash_pos(ix, iy, seed_val) & 0xFFFF) / 65535.0
	var b := float(_hash_pos(ix + 1, iy, seed_val) & 0xFFFF) / 65535.0
	var c := float(_hash_pos(ix, iy + 1, seed_val) & 0xFFFF) / 65535.0
	var d := float(_hash_pos(ix + 1, iy + 1, seed_val) & 0xFFFF) / 65535.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

static func _scatter_clusters(terrain: Dictionary, type: Enums.BattleTerrain,
		cluster_count: int, min_size: int, max_size: int, seed_val: int,
		grid_w: int = GRID_WIDTH, grid_h: int = GRID_HEIGHT) -> void:
	for i in range(cluster_count):
		var h := _hash_pos(i, seed_val, 0)
		# Place clusters in the middle area to avoid deployment zones
		var cx: int = 2 + (h % maxi(1, grid_w - 4))
		var cy: int = 3 + ((h >> 8) % maxi(1, grid_h - 6))
		var size: int = min_size + ((h >> 16) % (max_size - min_size + 1))

		# Blob radius derived from desired cell count: area = pi*r^2, so r = sqrt(size/pi)
		var blob_radius: float = sqrt(float(size) / PI) + 0.5
		# Noise seed unique per cluster
		var noise_seed := seed_val * 31 + i * 137

		# Scan a bounding box around the center and use distance + noise falloff
		var scan_r := ceili(blob_radius) + 2
		var placed_count := 0
		for dy in range(-scan_r, scan_r + 1):
			for dx in range(-scan_r, scan_r + 1):
				var px := cx + dx
				var py := cy + dy
				if px < 0 or px >= grid_w or py < 0 or py >= grid_h:
					continue
				if terrain[Vector2i(px, py)] != Enums.BattleTerrain.OPEN:
					continue
				# Distance from cluster center
				var dist := sqrt(float(dx * dx + dy * dy))
				# Noise-based distortion for organic shape
				var noise_val := _noise_hash(float(px) * 0.7, float(py) * 0.7, noise_seed)
				var threshold := blob_radius * (0.6 + noise_val * 0.8)
				if dist <= threshold:
					terrain[Vector2i(px, py)] = type
					placed_count += 1
					if placed_count >= size * 2:
						break
			if placed_count >= size * 2:
				break

static func _place_water_edge(terrain: Dictionary, seed_val: int,
		grid_w: int = GRID_WIDTH, grid_h: int = GRID_HEIGHT) -> void:
	# Place water along one edge (left side)
	for y in range(grid_h):
		var width := 2 + (_hash_pos(y, seed_val, 33) % 3)
		for x in range(width):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.WATER
		if width < grid_w:
			terrain[Vector2i(width, y)] = Enums.BattleTerrain.SAND

static func _clear_deployment_zones(terrain: Dictionary,
		grid_w: int = GRID_WIDTH, grid_h: int = GRID_HEIGHT) -> void:
	var deploy_top := ceili(grid_h * 0.25)
	var deploy_bottom := grid_h - ceili(grid_h * 0.25)

	# Top deployment zone: clear impassable
	for y in range(deploy_top):
		for x in range(grid_w):
			var pos := Vector2i(x, y)
			if terrain.has(pos) and not is_passable(terrain[pos]):
				terrain[pos] = Enums.BattleTerrain.OPEN

	# Bottom deployment zone: clear impassable
	for y in range(deploy_bottom, grid_h):
		for x in range(grid_w):
			var pos := Vector2i(x, y)
			if terrain.has(pos) and not is_passable(terrain[pos]):
				terrain[pos] = Enums.BattleTerrain.OPEN
