extends SceneTree
## Performance benchmark — run via: godot --headless -s tests/perf_benchmark.gd
## Measures the cost of key campaign operations at map scale (117x78 = 9126 tiles).

const MAP_W := 117
const MAP_H := 78
const TILE_COUNT := MAP_W * MAP_H  # 9126
const PX_W := MAP_W * 4  # 468  (minimap pixel width)
const PX_H := MAP_H * 4  # 312

var results: Array[Dictionary] = []

func _init() -> void:
	print("=== FractureWars Performance Benchmark ===")
	print("Map size: %d x %d = %d tiles" % [MAP_W, MAP_H, TILE_COUNT])
	print("Minimap size: %d x %d pixels" % [PX_W, PX_H])
	print("")

	_bench_minimap_terrain_fill()
	_bench_minimap_fog_dimming()
	_bench_minimap_fog_dimming_optimized()
	_bench_image_duplicate_and_texture()
	_bench_dictionary_iteration_9k()
	_bench_bfs_visibility()
	_bench_hex_distance_voronoi()
	_bench_pixel_to_hex()

	print("")
	print("=== Summary ===")
	for r in results:
		var status := "OK" if r.ms < 5.0 else ("SLOW" if r.ms < 16.0 else "CRITICAL")
		print("  [%s] %s: %.2f ms" % [status, r.name, r.ms])

	print("")
	print("Target: each operation < 5ms (fits in 60fps frame budget of 16.6ms)")
	quit()

# ── Helpers ──────────────────────────────────────────────────

func _usec() -> int:
	return Time.get_ticks_usec()

func _record(name: String, start_usec: int, iterations: int = 1) -> void:
	var elapsed_us := Time.get_ticks_usec() - start_usec
	var ms := float(elapsed_us) / 1000.0 / float(iterations)
	results.append({name = name, ms = ms})
	print("  %-45s %8.2f ms" % [name, ms])

# ── Benchmarks ───────────────────────────────────────────────

func _bench_minimap_terrain_fill() -> void:
	print("-- Minimap Terrain Cache --")
	var img := Image.create(PX_W, PX_H, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = []
	for i in 10:
		colors.append(Color(randf(), randf(), randf()))

	# Old method: set_pixel loop (4x4 per tile)
	var t := _usec()
	for x in MAP_W:
		for y in MAP_H:
			var color: Color = colors[(x + y) % colors.size()]
			var px := x * 4
			var py := y * 4
			for dx in 4:
				for dy in 4:
					if px + dx < PX_W and py + dy < PX_H:
						img.set_pixel(px + dx, py + dy, color)
	_record("terrain fill (set_pixel 4x4 loop)", t)

	# New method: fill_rect
	t = _usec()
	for x in MAP_W:
		for y in MAP_H:
			var color: Color = colors[(x + y) % colors.size()]
			var px := x * 4
			var py := y * 4
			img.fill_rect(Rect2i(px, py, mini(4, PX_W - px), mini(4, PX_H - py)), color)
	_record("terrain fill (fill_rect)", t)

func _bench_minimap_fog_dimming() -> void:
	print("-- Minimap Fog Dimming (explored tiles) --")
	var img := Image.create(PX_W, PX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.2))
	var explored_dim := 0.6

	# Old method: per-pixel get+darken+set
	var t := _usec()
	for x in MAP_W:
		for y in MAP_H:
			var px := x * 4
			var py := y * 4
			for ddx in 4:
				for ddy in 4:
					if px + ddx < PX_W and py + ddy < PX_H:
						var c: Color = img.get_pixel(px + ddx, py + ddy)
						img.set_pixel(px + ddx, py + ddy, c.darkened(explored_dim))
	_record("fog dim (per-pixel get+darken+set)", t)

func _bench_minimap_fog_dimming_optimized() -> void:
	var img := Image.create(PX_W, PX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.2))
	var explored_dim := 0.6

	# Optimized: read one pixel per 4x4 block, fill_rect with darkened color
	var t := _usec()
	for x in MAP_W:
		for y in MAP_H:
			var px := x * 4
			var py := y * 4
			var c: Color = img.get_pixel(px, py).darkened(explored_dim)
			img.fill_rect(Rect2i(px, py, mini(4, PX_W - px), mini(4, PX_H - py)), c)
	_record("fog dim (1 get_pixel + fill_rect)", t)

func _bench_image_duplicate_and_texture() -> void:
	print("-- Image Duplicate + Texture Upload --")
	var img := Image.create(PX_W, PX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.15))

	var t := _usec()
	for i in 10:
		var dup := img.duplicate()
		ImageTexture.create_from_image(dup)
	_record("image dup + texture create (avg of 10)", t, 10)

func _bench_dictionary_iteration_9k() -> void:
	print("-- Dictionary Iteration (fog update pattern) --")
	# Simulate fog alpha update: iterate 9126 entries, check visibility, update alpha
	var tile_alphas: Dictionary = {}
	var visible_cache: Dictionary = {}
	var explored: Dictionary = {}
	for x in MAP_W:
		for y in MAP_H:
			var coord := Vector2i(x, y)
			tile_alphas[coord] = 0.75
			if randf() < 0.3:
				visible_cache[coord] = true
			if randf() < 0.5:
				explored[coord] = true

	# Old: using .get() with bool() cast
	var t := _usec()
	var changed := 0
	for coord in tile_alphas:
		var is_visible: bool = bool(visible_cache.get(coord, false))
		var new_alpha: float
		if is_visible:
			new_alpha = 0.0
		elif explored.has(coord):
			new_alpha = 0.45
		else:
			new_alpha = 0.75
		if tile_alphas[coord] != new_alpha:
			tile_alphas[coord] = new_alpha
			changed += 1
	_record("fog alpha OLD (bool + .get())", t)

	# Reset
	for coord in tile_alphas:
		tile_alphas[coord] = 0.75

	# New: using .has() instead of .get() + bool()
	t = _usec()
	changed = 0
	for coord in tile_alphas:
		var new_alpha: float
		if visible_cache.has(coord):
			new_alpha = 0.0
		elif explored.has(coord):
			new_alpha = 0.45
		else:
			new_alpha = 0.75
		if tile_alphas[coord] != new_alpha:
			tile_alphas[coord] = new_alpha
			changed += 1
	_record("fog alpha NEW (.has() check)", t)

	# Optimized: only iterate non-visible tiles (using a filtered list)
	var fogged_list: Array = []
	for coord in tile_alphas:
		if tile_alphas[coord] > 0.0:
			fogged_list.append(coord)
	t = _usec()
	changed = 0
	for coord in fogged_list:
		var alpha: float = tile_alphas[coord]
		if alpha <= 0.0:
			continue
		# Simulate draw call cost (just color construction)
		var _c := Color(0.03, 0.02, 0.05, alpha)
	_record("fog draw (filtered list, %d tiles)" % fogged_list.size(), t)

func _bench_bfs_visibility() -> void:
	print("-- BFS Visibility (fog cache rebuild) --")
	# Simulate: mark owned tiles visible, then BFS from 8 cities + 5 armies
	var visible_cache: Dictionary = {}

	# Phase 1: iterate all tiles to mark owned
	var t := _usec()
	for x in MAP_W:
		for y in MAP_H:
			if (x + y) % 5 == 0:  # ~20% player-owned
				visible_cache[Vector2i(x, y)] = true
	_record("  phase 1: ownership scan (9126 tiles)", t)

	# Phase 2: BFS from 13 positions (8 cities + 5 armies), radius 3
	t = _usec()
	var sources: Array[Vector2i] = []
	for i in 13:
		sources.append(Vector2i(randi() % MAP_W, randi() % MAP_H))
	for src in sources:
		var visited: Dictionary = {src: true}
		visible_cache[src] = true
		var frontier: Array[Vector2i] = [src]
		for _r in 3:
			var next_frontier: Array[Vector2i] = []
			for coord in frontier:
				for n in _get_neighbors(coord):
					if visited.has(n):
						continue
					if n.x < 0 or n.x >= MAP_W or n.y < 0 or n.y >= MAP_H:
						continue
					visited[n] = true
					visible_cache[n] = true
					next_frontier.append(n)
			frontier = next_frontier
	_record("  phase 2: BFS x13, radius 3", t)

	# Combined
	print("  %-45s %8.2f ms (combined)" % ["fog visibility rebuild total",
		results[-1].ms + results[-2].ms])

func _bench_hex_distance_voronoi() -> void:
	print("-- Voronoi Border Assignment --")
	# Simulate: for each of 9126 tiles, find closest of ~30 cities
	var cities: Array[Vector2i] = []
	for i in 30:
		cities.append(Vector2i(randi() % MAP_W, randi() % MAP_H))

	# Old method: brute force hex_distance per tile per city
	var t := _usec()
	var owner_map: Dictionary = {}
	for x in MAP_W:
		for y in MAP_H:
			var coord := Vector2i(x, y)
			var best_dist := 999
			var best_idx := 0
			for i in cities.size():
				var d := _hex_distance(coord, cities[i])
				if d < best_dist:
					best_dist = d
					best_idx = i
			owner_map[coord] = best_idx
	_record("voronoi OLD (9126 x 30, hex_distance)", t)

	# New method: BFS flood from all cities simultaneously
	t = _usec()
	var bfs_owner: Dictionary = {}
	var bfs_dist: Dictionary = {}
	var bfs_queue: Array = []  # [coord, city_idx, distance]
	for i in cities.size():
		var c := cities[i]
		bfs_owner[c] = i
		bfs_dist[c] = 0
		bfs_queue.append([c, i, 0])
	var bfs_idx := 0
	while bfs_idx < bfs_queue.size():
		var entry: Array = bfs_queue[bfs_idx]
		bfs_idx += 1
		var coord: Vector2i = entry[0]
		var city_idx: int = entry[1]
		var dist: int = entry[2]
		for n in _get_neighbors(coord):
			if n.x < 0 or n.x >= MAP_W or n.y < 0 or n.y >= MAP_H:
				continue
			if bfs_dist.has(n):
				continue
			bfs_dist[n] = dist + 1
			bfs_owner[n] = city_idx
			bfs_queue.append([n, city_idx, dist + 1])
	_record("voronoi NEW (BFS flood, 30 cities, global)", t)

	# Realistic: BFS flood constrained to regions (~300 tiles each, ~3 cities per region)
	# Simulate 30 regions of ~300 tiles, 3 cities per region
	t = _usec()
	var region_owner: Dictionary = {}
	var region_dist: Dictionary = {}
	var region_queue: Array = []
	# Assign tiles to ~30 regions
	var tile_regions: Dictionary = {}
	for x in MAP_W:
		for y in MAP_H:
			tile_regions[Vector2i(x, y)] = (x / 6 + (y / 6) * 20) % 30
	# Place 3 cities per region
	for r in 30:
		for ci in 3:
			var cx := (r % 20) * 6 + ci * 2
			var cy := (r / 20) * 6 + ci
			if cx < MAP_W and cy < MAP_H:
				var c := Vector2i(cx, cy)
				region_owner[c] = ci
				region_dist[c] = 0
				region_queue.append([c, ci, r, 0])
	var ridx := 0
	while ridx < region_queue.size():
		var entry: Array = region_queue[ridx]
		ridx += 1
		var coord: Vector2i = entry[0]
		var cid: int = entry[1]
		var rid: int = entry[2]
		var dist: int = entry[3]
		for n in _get_neighbors(coord):
			if n.x < 0 or n.x >= MAP_W or n.y < 0 or n.y >= MAP_H:
				continue
			if region_dist.has(n):
				continue
			if tile_regions.get(n, -1) != rid:
				continue
			region_dist[n] = dist + 1
			region_owner[n] = cid
			region_queue.append([n, cid, rid, dist + 1])
	_record("voronoi NEW (BFS, region-constrained)", t)

func _bench_pixel_to_hex() -> void:
	print("-- Pixel to Hex (mouse hover) --")
	var HEX_H := 52.0
	var HEX_V := 45.0

	# Simulate 120 calls (2 seconds of mouse motion at 60Hz)
	var t := _usec()
	for i in 120:
		var px := randf() * float(MAP_W) * HEX_H
		var py := randf() * float(MAP_H) * HEX_V
		var approx_col := int(round(px / HEX_H))
		var approx_row := int(round(py / HEX_V))
		var best := Vector2i(approx_col, approx_row)
		var best_dist := INF
		for col in range(maxi(0, approx_col - 2), mini(MAP_W, approx_col + 3)):
			for row in range(maxi(0, approx_row - 2), mini(MAP_H, approx_row + 3)):
				var cx := float(col) * HEX_H
				var cy := float(row) * HEX_V + (0.5 * HEX_V if col % 2 == 1 else 0.0)
				var dist := (px - cx) * (px - cx) + (py - cy) * (py - cy)
				if dist < best_dist:
					best_dist = dist
					best = Vector2i(col, row)
	_record("pixel_to_hex x120 (2s of mouse motion)", t)

# ── Utility ──────────────────────────────────────────────────

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	# Offset coord hex distance (even-q)
	var ac := _offset_to_cube(a)
	var bc := _offset_to_cube(b)
	return (absi(ac.x - bc.x) + absi(ac.y - bc.y) + absi(ac.z - bc.z)) / 2

func _offset_to_cube(hex: Vector2i) -> Vector3i:
	var q := hex.x
	var r := hex.y - (hex.x - (hex.x & 1)) / 2
	return Vector3i(q, r, -q - r)

func _get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var x := coord.x
	var y := coord.y
	if x & 1 == 0:
		return [Vector2i(x+1,y-1), Vector2i(x+1,y), Vector2i(x,y+1),
				Vector2i(x-1,y), Vector2i(x-1,y-1), Vector2i(x,y-1)]
	else:
		return [Vector2i(x+1,y), Vector2i(x+1,y+1), Vector2i(x,y+1),
				Vector2i(x-1,y+1), Vector2i(x-1,y), Vector2i(x,y-1)]
