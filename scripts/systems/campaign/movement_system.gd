class_name MovementSystem
extends RefCounted

var hex_map: HexMapData

func _init(map: HexMapData) -> void:
	hex_map = map

func _is_tile_blocked(coord: Vector2i, faction_id: StringName, excluded_army_id: StringName) -> bool:
	# Friendly armies no longer block — they merge on arrival
	# Check elderbeasts
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.hex_pos == coord:
			return true # Elderbeasts always block movement onto their tile
	return false

func _has_enemy_at(coord: Vector2i, faction_id: StringName, excluded_army_id: StringName) -> bool:
	var armies := GameManager.get_armies_at_tile(coord)
	for army in armies:
		if army.army_id == excluded_army_id:
			continue
		if army.faction_id == faction_id:
			continue
		var relation := GameManager.get_relation(faction_id, army.faction_id)
		if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
			return true
	return false

func find_path(from: Vector2i, to: Vector2i, faction_id: StringName, max_cost: float, excluded_army_id: StringName = &"") -> Array[Vector2i]:
	# A* pathfinding on hex grid
	if from == to:
		return []

	var open_set: Array[Vector2i] = [from]
	var came_from: Dictionary = {} # Vector2i -> Vector2i
	var g_score: Dictionary = {} # Vector2i -> float (cost from start)
	var f_score: Dictionary = {} # Vector2i -> float (g + heuristic)

	g_score[from] = 0.0
	f_score[from] = float(HexHelper.hex_distance(from, to))

	while open_set.size() > 0:
		# Find node with lowest f_score
		var current := open_set[0]
		var current_f: float = f_score.get(current, INF)
		for node in open_set:
			var nf: float = f_score.get(node, INF)
			if nf < current_f:
				current = node
				current_f = nf

		if current == to:
			# Reconstruct path
			var path: Array[Vector2i] = []
			var node := to
			while node != from:
				path.push_front(node)
				node = came_from[node]
			return path

		open_set.erase(current)
		var current_g: float = g_score.get(current, INF)

		for neighbor in HexHelper.get_neighbors(current):
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			if hex_map.get_tile(neighbor) == null:
				continue

			# Check tile occupancy
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue
			# Enemy tile: passable as destination (battle), but don't path through
			if _has_enemy_at(neighbor, faction_id, excluded_army_id):
				if neighbor != to:
					continue

			var move_cost := hex_map.get_movement_cost(neighbor, faction_id)
			if move_cost >= INF:
				continue

			var tentative_g := current_g + move_cost
			if tentative_g > max_cost:
				continue

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + float(HexHelper.hex_distance(neighbor, to))
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return [] # No path found

func get_reachable_tiles(from: Vector2i, movement_points: float, faction_id: StringName, excluded_army_id: StringName = &"") -> Dictionary:
	# Returns Dictionary of Vector2i -> remaining_mp
	var result: Dictionary = {}
	result[from] = movement_points

	# Dijkstra flood fill
	var open_set: Array[Array] = [[from, movement_points]] # [coord, remaining_mp]

	while open_set.size() > 0:
		# Find node with most remaining MP (least cost spent)
		var best_idx := 0
		var best_mp: float = open_set[0][1]
		for i in range(1, open_set.size()):
			if open_set[i][1] > best_mp:
				best_mp = open_set[i][1]
				best_idx = i

		var entry: Array = open_set[best_idx]
		open_set.remove_at(best_idx)
		var current: Vector2i = entry[0]
		var remaining: float = entry[1]

		if remaining < result.get(current, -1.0):
			continue # Already found a better path

		for neighbor in HexHelper.get_neighbors(current):
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			if hex_map.get_tile(neighbor) == null:
				continue

			# Check tile occupancy
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue

			var cost := hex_map.get_movement_cost(neighbor, faction_id)
			var new_remaining := remaining - cost

			if new_remaining < 0.0:
				continue

			if new_remaining > result.get(neighbor, -1.0):
				result[neighbor] = new_remaining
				# Enemy tiles are reachable (for battle) but don't expand through them
				if not _has_enemy_at(neighbor, faction_id, excluded_army_id):
					open_set.append([neighbor, new_remaining])

	result.erase(from) # Don't include starting tile
	return result
