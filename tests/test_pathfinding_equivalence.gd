extends SceneTree
## Plan A Task 8: binary-insert + allocation-free neighbors must produce
## byte-identical paths and reachable sets to the old implementation.
## The old find_path/get_reachable_tiles are embedded verbatim below (calling
## the live helpers on the MovementSystem instance).
## Run: godot --headless --path . -s res://tests/test_pathfinding_equivalence.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var ms: MovementSystem = _gm.movement_system
	ms.refresh_caches()

	var fids: Array = []
	for fid in _gm.state.faction_states:
		fids.append(fid)
		if fids.size() >= 3:
			break

	seed(4242)
	var checked := 0
	for i in 40:
		var from := Vector2i(randi() % 117, randi() % 78)
		var to := Vector2i(randi() % 117, randi() % 78)
		var faction: StringName = fids[i % fids.size()]
		ms._path_cache.clear()
		var new_path: Array[Vector2i] = ms.find_path(from, to, faction, 60.0)
		var old_path: Array[Vector2i] = _old_find_path(ms, from, to, faction, 60.0, &"", false, null)
		if new_path != old_path:
			_fails += 1
			print("FAIL path %s->%s (%s):\n  new=%s\n  old=%s" % [from, to, faction, new_path, old_path])
		ms._reachable_cache.clear()
		var new_reach: Dictionary = ms.get_reachable_tiles(from, 8.0, faction)
		var old_reach: Dictionary = _old_get_reachable_tiles(ms, from, 8.0, faction, &"", false, null)
		if new_reach != old_reach:
			_fails += 1
			print("FAIL reachable %s (%s): new=%d tiles old=%d tiles" % [from, faction, new_reach.size(), old_reach.size()])
		checked += 1

	if _fails == 0:
		print("PATHFINDING EQUIVALENCE PASSED (%d queries)" % checked)
		quit(0)
	else:
		print("PATHFINDING EQUIVALENCE FAILED (%d)" % _fails)
		quit(1)

func _old_find_path(ms: MovementSystem, from: Vector2i, to: Vector2i, faction_id: StringName, max_cost: float, excluded_army_id: StringName, can_cross_mountains: bool, army: ArmyState) -> Array[Vector2i]:
	# Verbatim pre-Task-8 implementation (no cache), calling live helpers on ms
	if from == to:
		return []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var in_open: Dictionary = {}
	var closed: Dictionary = {}
	var open_heap: Array[Array] = []
	g_score[from] = 0.0
	var start_f := float(HexHelper.hex_distance(from, to))
	open_heap.append([start_f, from])
	in_open[from] = true
	while open_heap.size() > 0:
		var best: Array = open_heap.pop_back()
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
			var ntile = ms.hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			if ms._is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue
			if ms._has_enemy_at(neighbor, faction_id, excluded_army_id):
				if neighbor != to:
					continue
			var city_at = _gm.city_system.get_city_at_hex(neighbor)
			if city_at and city_at.faction_id != faction_id and city_at.faction_id != &"" and city_at.faction_id != &"independent":
				if not _gm.diplomacy_system.has_free_passage(faction_id, city_at.faction_id):
					if neighbor != to:
						continue
			var move_cost: float = ms.hex_map.get_movement_cost(neighbor, faction_id)
			if move_cost >= INF:
				continue
			if not can_cross_mountains:
				if ntile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
			if army:
				move_cost *= army.get_terrain_stride_modifier(ntile.terrain)
			if ntile.owner_faction == faction_id:
				move_cost *= ms._get_city_tier_cost_modifier(ntile.region_id, faction_id)
			elif ntile.owner_faction != &"" and ntile.owner_faction != &"independent":
				if not _gm.diplomacy_system.has_free_passage(faction_id, ntile.owner_faction):
					move_cost *= 1.5
			var tentative_g := current_g + move_cost
			if tentative_g > max_cost:
				continue
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f := tentative_g + float(HexHelper.hex_distance(neighbor, to))
				var idx := open_heap.size()
				while idx > 0 and open_heap[idx - 1][0] < f:
					idx -= 1
				open_heap.insert(idx, [f, neighbor])
				in_open[neighbor] = true
	return []

func _old_get_reachable_tiles(ms: MovementSystem, from: Vector2i, movement_points: float, faction_id: StringName, excluded_army_id: StringName, can_cross_mountains: bool, army: ArmyState) -> Dictionary:
	# Verbatim pre-Task-8 implementation (no cache), calling live helpers on ms
	var result: Dictionary = {}
	result[from] = movement_points
	var open_heap: Array[Array] = [[movement_points, from]]
	while open_heap.size() > 0:
		var entry: Array = open_heap.pop_back()
		var remaining: float = entry[0]
		var current: Vector2i = entry[1]
		if remaining < result.get(current, -1.0):
			continue
		for neighbor in HexHelper.get_neighbors(current):
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile = ms.hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			if ms._is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue
			var cost: float = ms.hex_map.get_movement_cost(neighbor, faction_id)
			if not can_cross_mountains:
				if ntile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
			if army:
				cost *= army.get_terrain_stride_modifier(ntile.terrain)
			if ntile.owner_faction == faction_id:
				cost *= ms._get_city_tier_cost_modifier(ntile.region_id, faction_id)
			elif ntile.owner_faction != &"" and ntile.owner_faction != &"independent":
				if not _gm.diplomacy_system.has_free_passage(faction_id, ntile.owner_faction):
					cost *= 1.5
			var new_remaining := remaining - cost
			if new_remaining < 0.0:
				continue
			if new_remaining > result.get(neighbor, -1.0):
				result[neighbor] = new_remaining
				var blocked_by_city := false
				var city_at = _gm.city_system.get_city_at_hex(neighbor)
				if city_at and city_at.faction_id != faction_id and city_at.faction_id != &"" and city_at.faction_id != &"independent":
					if not _gm.diplomacy_system.has_free_passage(faction_id, city_at.faction_id):
						blocked_by_city = true
				if not blocked_by_city and not ms._has_enemy_at(neighbor, faction_id, excluded_army_id) and not ms._has_enemy_beast_at(neighbor, faction_id):
					var idx := open_heap.size()
					while idx > 0 and open_heap[idx - 1][0] > new_remaining:
						idx -= 1
					open_heap.insert(idx, [new_remaining, neighbor])
	result.erase(from)
	return result
