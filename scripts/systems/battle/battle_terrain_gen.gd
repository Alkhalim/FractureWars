class_name BattleTerrainGen
extends RefCounted

const GRID_WIDTH := 20
const GRID_HEIGHT := 16

# Deployment zones should stay mostly open
const DEPLOY_TOP_END := 5
const DEPLOY_BOTTOM_START := 10

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

static func generate(campaign_terrain: Enums.TerrainType, seed_value: int) -> Dictionary:
	var terrain: Dictionary = {} # Vector2i -> Enums.BattleTerrain

	# Fill with OPEN
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.OPEN

	# Scatter features based on campaign terrain
	match campaign_terrain:
		Enums.TerrainType.PLAINS:
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, 2, 3, 5, seed_value)
		Enums.TerrainType.FOREST:
			_scatter_clusters(terrain, Enums.BattleTerrain.FOREST, 4, 4, 8, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, 2, 2, 4, seed_value + 100)
		Enums.TerrainType.MOUNTAINS:
			_scatter_clusters(terrain, Enums.BattleTerrain.ROCK, 3, 3, 6, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, 2, 2, 4, seed_value + 100)
		Enums.TerrainType.DESERT:
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, 4, 5, 10, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, 1, 2, 4, seed_value + 100)
		Enums.TerrainType.SWAMP:
			_scatter_clusters(terrain, Enums.BattleTerrain.MUD, 4, 4, 8, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, 3, 3, 6, seed_value + 100)
		Enums.TerrainType.TUNDRA:
			_scatter_clusters(terrain, Enums.BattleTerrain.ICE, 3, 4, 7, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.ROCK, 2, 2, 4, seed_value + 100)
		Enums.TerrainType.JUNGLE:
			_scatter_clusters(terrain, Enums.BattleTerrain.FOREST, 5, 5, 10, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.MUD, 2, 3, 5, seed_value + 100)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, 3, 2, 4, seed_value + 200)
		Enums.TerrainType.SHARD_WASTES:
			_scatter_clusters(terrain, Enums.BattleTerrain.CRYSTAL, 3, 3, 6, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.BRUSH, 2, 2, 4, seed_value + 100)
		Enums.TerrainType.COAST:
			_place_water_edge(terrain, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, 3, 4, 7, seed_value + 100)
		Enums.TerrainType.WATER:
			_scatter_clusters(terrain, Enums.BattleTerrain.WATER, 5, 5, 10, seed_value)
			_scatter_clusters(terrain, Enums.BattleTerrain.SAND, 2, 3, 5, seed_value + 100)

	# Ensure deployment zones are mostly open
	_clear_deployment_zones(terrain)

	return terrain

static func _hash_pos(x: int, y: int, seed_val: int) -> int:
	var h := (x * 374761393 + y * 668265263 + seed_val * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245 + 12345) & 0x7FFFFFFF
	return h

static func _scatter_clusters(terrain: Dictionary, type: Enums.BattleTerrain,
		cluster_count: int, min_size: int, max_size: int, seed_val: int) -> void:
	for i in range(cluster_count):
		var h := _hash_pos(i, seed_val, 0)
		# Place clusters in the middle area (rows 3-12) to avoid deployment zones
		var cx: int = 2 + (h % (GRID_WIDTH - 4))
		var cy: int = 3 + ((h >> 8) % (GRID_HEIGHT - 6))
		var size: int = min_size + ((h >> 16) % (max_size - min_size + 1))

		# Grow cluster from center
		var placed: Array[Vector2i] = [Vector2i(cx, cy)]
		terrain[Vector2i(cx, cy)] = type

		for j in range(size - 1):
			if placed.is_empty():
				break
			var base_idx := _hash_pos(i, j, seed_val + 50) % placed.size()
			var base: Vector2i = placed[base_idx]
			var dir := _hash_pos(i, j, seed_val + 77) % 4
			var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var new_pos: Vector2i = base + offsets[dir]

			if new_pos.x >= 0 and new_pos.x < GRID_WIDTH and new_pos.y >= 0 and new_pos.y < GRID_HEIGHT:
				if terrain[new_pos] == Enums.BattleTerrain.OPEN:
					terrain[new_pos] = type
					placed.append(new_pos)

static func _place_water_edge(terrain: Dictionary, seed_val: int) -> void:
	# Place water along one edge (left side)
	for y in range(GRID_HEIGHT):
		var width := 2 + (_hash_pos(y, seed_val, 33) % 3)
		for x in range(width):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.WATER
		if width < GRID_WIDTH:
			terrain[Vector2i(width, y)] = Enums.BattleTerrain.SAND

static func _clear_deployment_zones(terrain: Dictionary) -> void:
	# Top deployment zone (rows 0 to DEPLOY_TOP_END-1): clear impassable
	for y in range(DEPLOY_TOP_END):
		for x in range(GRID_WIDTH):
			var pos := Vector2i(x, y)
			var t: Enums.BattleTerrain = terrain[pos]
			if not is_passable(t):
				terrain[pos] = Enums.BattleTerrain.OPEN

	# Bottom deployment zone (rows DEPLOY_BOTTOM_START to GRID_HEIGHT-1): clear impassable
	for y in range(DEPLOY_BOTTOM_START, GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var pos := Vector2i(x, y)
			var t: Enums.BattleTerrain = terrain[pos]
			if not is_passable(t):
				terrain[pos] = Enums.BattleTerrain.OPEN
