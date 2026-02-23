class_name MovementSystem
extends RefCounted

var hex_map: HexMapData

# Position caches — rebuilt once per refresh_caches() call
var _beast_positions: Dictionary = {} # Vector2i -> true
var _army_positions: Dictionary = {} # Vector2i -> Array[ArmyState]
var _cache_valid: bool = false

func _init(map: HexMapData) -> void:
	hex_map = map

func refresh_caches() -> void:
	_beast_positions.clear()
	_army_positions.clear()
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		_beast_positions[beast.hex_pos] = true
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if not _army_positions.has(army.hex_pos):
			_army_positions[army.hex_pos] = [army]
		else:
			_army_positions[army.hex_pos].append(army)
	_cache_valid = true

func _ensure_cache() -> void:
	if not _cache_valid:
		refresh_caches()

func _is_tile_blocked(coord: Vector2i, _faction_id: StringName, _excluded_army_id: StringName) -> bool:
	return _beast_positions.has(coord)

func _has_enemy_at(coord: Vector2i, faction_id: StringName, excluded_army_id: StringName) -> bool:
	if not _army_positions.has(coord):
		return false
	var armies: Array = _army_positions[coord]
	for army: ArmyState in armies:
		if army.army_id == excluded_army_id:
			continue
		if army.faction_id == faction_id:
			continue
		var relation := GameManager.get_relation(faction_id, army.faction_id)
		if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
			return true
	return false

func find_path(from: Vector2i, to: Vector2i, faction_id: StringName, max_cost: float, excluded_army_id: StringName = &"", can_cross_mountains: bool = false) -> Array[Vector2i]:
	# A* pathfinding on hex grid with sorted open set (descending f — pop_back = best)
	_ensure_cache()
	if from == to:
		return []

	var came_from: Dictionary = {} # Vector2i -> Vector2i
	var g_score: Dictionary = {} # Vector2i -> float
	var in_open: Dictionary = {} # Vector2i -> true (tracks membership)
	var closed: Dictionary = {} # Vector2i -> true

	# open_heap: Array of [f_score: float, coord: Vector2i], sorted descending by f
	var open_heap: Array[Array] = []

	g_score[from] = 0.0
	var start_f := float(HexHelper.hex_distance(from, to))
	open_heap.append([start_f, from])
	in_open[from] = true

	while open_heap.size() > 0:
		var best: Array = open_heap.pop_back() # lowest f (sorted descending)
		var current: Vector2i = best[1]

		if closed.has(current):
			continue
		closed[current] = true
		in_open.erase(current)

		if current == to:
			var path: Array[Vector2i] = []
			var node := to
			while node != from:
				path.push_front(node)
				node = came_from[node]
			return path

		var current_g: float = g_score.get(current, INF)

		for neighbor in HexHelper.get_neighbors(current):
			if closed.has(neighbor):
				continue
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			if hex_map.get_tile(neighbor) == null:
				continue
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue
			if _has_enemy_at(neighbor, faction_id, excluded_army_id):
				if neighbor != to:
					continue

			var move_cost := hex_map.get_movement_cost(neighbor, faction_id)
			if move_cost >= INF:
				continue
			if not can_cross_mountains:
				var check_tile := hex_map.get_tile(neighbor)
				if check_tile and check_tile.terrain == Enums.TerrainType.MOUNTAINS:
					continue

			var tentative_g := current_g + move_cost
			if tentative_g > max_cost:
				continue

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f := tentative_g + float(HexHelper.hex_distance(neighbor, to))
				# Binary insert: keep sorted descending by f (largest first)
				var idx := open_heap.size()
				while idx > 0 and open_heap[idx - 1][0] < f:
					idx -= 1
				open_heap.insert(idx, [f, neighbor])
				in_open[neighbor] = true

	return [] # No path found

func get_reachable_tiles(from: Vector2i, movement_points: float, faction_id: StringName, excluded_army_id: StringName = &"", can_cross_mountains: bool = false) -> Dictionary:
	# Returns Dictionary of Vector2i -> remaining_mp
	# Dijkstra with sorted open set (ascending remaining — pop_back = best)
	_ensure_cache()
	var result: Dictionary = {}
	result[from] = movement_points

	# open_heap: [remaining_mp, coord], sorted ascending (pop_back = highest remaining)
	var open_heap: Array[Array] = [[movement_points, from]]

	while open_heap.size() > 0:
		var entry: Array = open_heap.pop_back() # highest remaining MP
		var remaining: float = entry[0]
		var current: Vector2i = entry[1]

		if remaining < result.get(current, -1.0):
			continue # Already found a better path

		for neighbor in HexHelper.get_neighbors(current):
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			if hex_map.get_tile(neighbor) == null:
				continue
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue

			var cost := hex_map.get_movement_cost(neighbor, faction_id)
			if not can_cross_mountains:
				var check_tile := hex_map.get_tile(neighbor)
				if check_tile and check_tile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
			var new_remaining := remaining - cost

			if new_remaining < 0.0:
				continue

			if new_remaining > result.get(neighbor, -1.0):
				result[neighbor] = new_remaining
				# Enemy tiles are reachable (for battle) but don't expand through them
				if not _has_enemy_at(neighbor, faction_id, excluded_army_id):
					# Binary insert: sorted ascending by remaining MP
					var idx := open_heap.size()
					while idx > 0 and open_heap[idx - 1][0] > new_remaining:
						idx -= 1
					open_heap.insert(idx, [new_remaining, neighbor])

	result.erase(from) # Don't include starting tile
	return result
