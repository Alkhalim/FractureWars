class_name MovementSystem
extends RefCounted

var hex_map: HexMapData

# Position caches — rebuilt once per refresh_caches() call
var _beast_positions: Dictionary = {} # Vector2i -> StringName (faction_id of elderbeast)
var _army_positions: Dictionary = {} # Vector2i -> Array[ArmyState]
var _cache_valid: bool = false
var _path_cache: Dictionary = {} # "from:to:faction:max_cost" -> Array[Vector2i]
var _reachable_cache: Dictionary = {} # "from:mp:faction" -> Dictionary
var _region_city_level_cache: Dictionary = {} # "region_id:faction_id" -> int (max city level)

func _init(map: HexMapData) -> void:
	hex_map = map

func refresh_caches() -> void:
	_beast_positions.clear()
	_army_positions.clear()
	_path_cache.clear()
	_reachable_cache.clear()
	_region_city_level_cache.clear()
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		_beast_positions[beast.hex_pos] = beast.faction_id
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if not _army_positions.has(army.hex_pos):
			_army_positions[army.hex_pos] = [army]
		else:
			_army_positions[army.hex_pos].append(army)
	# Build region city level cache: highest city level per region+faction
	if GameManager.city_system:
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			if city.faction_id == &"" or city.faction_id == &"independent":
				continue
			var key := "%s:%s" % [city.region_id, city.faction_id]
			var current_max: int = _region_city_level_cache.get(key, 0)
			if city.level > current_max:
				_region_city_level_cache[key] = city.level
	_cache_valid = true

func _ensure_cache() -> void:
	if not _cache_valid:
		refresh_caches()

func _is_tile_blocked(coord: Vector2i, faction_id: StringName, _excluded_army_id: StringName) -> bool:
	if not _beast_positions.has(coord):
		return false
	# Elderbeast on this tile — block unless we are at war with its faction
	var beast_faction: StringName = _beast_positions[coord]
	if beast_faction == &"" or beast_faction == faction_id:
		return true # Neutral or friendly beast — can't enter
	var relation := GameManager.get_relation(faction_id, beast_faction)
	if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
		return false # Enemy beast — can attack, not blocked
	return true # Non-hostile foreign beast — blocked

func _get_city_tier_cost_modifier(region_id: StringName, faction_id: StringName) -> float:
	# Each city level reduces movement cost in the region by 3% (up to 15% at L5)
	var key := "%s:%s" % [region_id, faction_id]
	var city_level: int = _region_city_level_cache.get(key, 0)
	if city_level <= 0:
		return 1.0
	return 1.0 - city_level * 0.03

func _has_enemy_beast_at(coord: Vector2i, faction_id: StringName) -> bool:
	if not _beast_positions.has(coord):
		return false
	var beast_faction: StringName = _beast_positions[coord]
	if beast_faction == &"" or beast_faction == faction_id:
		return false
	var relation := GameManager.get_relation(faction_id, beast_faction)
	return relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE

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

func find_path(from: Vector2i, to: Vector2i, faction_id: StringName, max_cost: float, excluded_army_id: StringName = &"", can_cross_mountains: bool = false, army: ArmyState = null) -> Array[Vector2i]:
	# A* pathfinding on hex grid with sorted open set (descending f — pop_back = best)
	_ensure_cache()
	if from == to:
		return []

	var cache_key := "%d,%d:%d,%d:%s:%.1f" % [from.x, from.y, to.x, to.y, faction_id, max_cost]
	if _path_cache.has(cache_key):
		var cached: Array = _path_cache[cache_key]
		var typed: Array[Vector2i] = []
		typed.assign(cached)
		return typed

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
			_path_cache[cache_key] = path
			return path

		var current_g: float = g_score.get(current, INF)

		for neighbor in HexHelper.get_neighbors(current):
			if closed.has(neighbor):
				continue
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue
			if _has_enemy_at(neighbor, faction_id, excluded_army_id):
				if neighbor != to:
					continue
			# Block pathing through foreign cities unless allied or has free passage
			var city_at := GameManager.city_system.get_city_at_hex(neighbor)
			if city_at and city_at.faction_id != faction_id and city_at.faction_id != &"" and city_at.faction_id != &"independent":
				if not GameManager.diplomacy_system.has_free_passage(faction_id, city_at.faction_id):
					if neighbor != to:
						continue

			var move_cost := hex_map.get_movement_cost(neighbor, faction_id)
			if move_cost >= INF:
				continue
			if not can_cross_mountains:
				if ntile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
			# Apply army-specific terrain stride modifiers
			if army:
				move_cost *= army.get_terrain_stride_modifier(ntile.terrain)
			# City tier reduces movement cost in friendly regions
			if ntile.owner_faction == faction_id:
				move_cost *= _get_city_tier_cost_modifier(ntile.region_id, faction_id)
			# Trespass penalty: 1.5x cost for crossing foreign territory without free passage
			elif ntile.owner_faction != &"" and ntile.owner_faction != &"independent":
				if not GameManager.diplomacy_system.has_free_passage(faction_id, ntile.owner_faction):
					move_cost *= 1.5

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

	_path_cache[cache_key] = []
	return [] # No path found

func get_reachable_tiles(from: Vector2i, movement_points: float, faction_id: StringName, excluded_army_id: StringName = &"", can_cross_mountains: bool = false, army: ArmyState = null) -> Dictionary:
	# Returns Dictionary of Vector2i -> remaining_mp
	# Dijkstra with sorted open set (ascending remaining — pop_back = best)
	_ensure_cache()
	var cache_key := "%d,%d:%.1f:%s" % [from.x, from.y, movement_points, faction_id]
	if _reachable_cache.has(cache_key):
		return _reachable_cache[cache_key]
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
			var ntile := hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			if _is_tile_blocked(neighbor, faction_id, excluded_army_id):
				continue

			var cost := hex_map.get_movement_cost(neighbor, faction_id)
			if not can_cross_mountains:
				if ntile.terrain == Enums.TerrainType.MOUNTAINS:
					continue
			# Apply army-specific terrain stride modifiers
			if army:
				cost *= army.get_terrain_stride_modifier(ntile.terrain)
			# City tier reduces movement cost in friendly regions
			if ntile.owner_faction == faction_id:
				cost *= _get_city_tier_cost_modifier(ntile.region_id, faction_id)
			# Trespass penalty: 1.5x cost for crossing foreign territory without free passage
			elif ntile.owner_faction != &"" and ntile.owner_faction != &"independent":
				if not GameManager.diplomacy_system.has_free_passage(faction_id, ntile.owner_faction):
					cost *= 1.5
			var new_remaining := remaining - cost

			if new_remaining < 0.0:
				continue

			if new_remaining > result.get(neighbor, -1.0):
				result[neighbor] = new_remaining
				# Foreign cities are reachable (for attack/diplomacy) but don't expand through them unless allied/free passage
				var blocked_by_city := false
				var city_at := GameManager.city_system.get_city_at_hex(neighbor)
				if city_at and city_at.faction_id != faction_id and city_at.faction_id != &"" and city_at.faction_id != &"independent":
					if not GameManager.diplomacy_system.has_free_passage(faction_id, city_at.faction_id):
						blocked_by_city = true
				# Enemy tiles are reachable (for battle) but don't expand through them
				if not blocked_by_city and not _has_enemy_at(neighbor, faction_id, excluded_army_id) and not _has_enemy_beast_at(neighbor, faction_id):
					# Binary insert: sorted ascending by remaining MP
					var idx := open_heap.size()
					while idx > 0 and open_heap[idx - 1][0] > new_remaining:
						idx -= 1
					open_heap.insert(idx, [new_remaining, neighbor])

	result.erase(from) # Don't include starting tile
	_reachable_cache[cache_key] = result
	return result
