extends SceneTree
## Plan A Tasks 3+4: cached get_region_owner and memoized regions_adjacent
## must equal the brute-force reference, including after ownership mutation.
## Run: godot --headless --path . -s res://tests/test_region_caches.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire")
	var map: HexMapData = _gm.state.hex_map

	# --- region owner: all regions vs brute force -----------------------------
	var region_ids: Array = _dm.regions.keys()
	for rid in region_ids:
		if map.get_region_owner(rid) != _ref_owner(map, rid):
			_fails += 1
			print("FAIL owner (initial): %s" % rid)
	# Cached second read
	for rid in region_ids:
		if map.get_region_owner(rid) != _ref_owner(map, rid):
			_fails += 1
			print("FAIL owner (cached): %s" % rid)

	# --- mutate ownership of one region, targeted invalidation ----------------
	var target_rid: StringName = region_ids[0]
	var rtiles: Array = map.get_region_tiles(target_rid)
	if rtiles.size() > 0:
		var flipped := 0
		for coord in rtiles:
			var t: HexMapData.TileState = map.tiles[coord]
			if t.terrain != Enums.TerrainType.MOUNTAINS and t.terrain != Enums.TerrainType.WATER:
				t.owner_faction = &"skulloath"
				flipped += 1
				if flipped >= rtiles.size() / 2 + 1:
					break
		map.invalidate_region_owner(target_rid)
		for rid in region_ids:
			if map.get_region_owner(rid) != _ref_owner(map, rid):
				_fails += 1
				print("FAIL owner (after mutation): %s" % rid)

	# --- adjacency memo vs brute force over a sample ---------------------------
	var checked := 0
	for i in range(region_ids.size()):
		for j in range(i + 1, region_ids.size()):
			if (i + j) % 7 != 0 and checked > 40:
				continue
			var a: StringName = region_ids[i]
			var b: StringName = region_ids[j]
			var memo: bool = map.regions_adjacent(a, b)
			var ref: bool = _ref_adjacent(map, a, b)
			if memo != ref:
				_fails += 1
				print("FAIL adjacency: %s vs %s memo=%s ref=%s" % [a, b, memo, ref])
			# Cached read must agree too
			if map.regions_adjacent(b, a) != ref:
				_fails += 1
				print("FAIL adjacency (cached/swapped): %s vs %s" % [a, b])
			checked += 1

	if _fails == 0:
		print("REGION CACHES TEST PASSED (%d adjacency pairs)" % checked)
		quit(0)
	else:
		print("REGION CACHES TEST FAILED (%d)" % _fails)
		quit(1)

func _ref_owner(map: HexMapData, region_id: StringName) -> StringName:
	# Verbatim old get_region_owner
	var counts: Dictionary = {}
	for coord in map.get_region_tiles(region_id):
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.owner_faction != &"":
			counts[tile.owner_faction] = counts.get(tile.owner_faction, 0) + 1
	if counts.is_empty():
		return &""
	var best_faction: StringName = &""
	var best_count := 0
	for faction_id in counts:
		if counts[faction_id] > best_count:
			best_count = counts[faction_id]
			best_faction = faction_id
	return best_faction

func _ref_adjacent(map: HexMapData, region_a: StringName, region_b: StringName) -> bool:
	# Verbatim old regions_adjacent
	var tiles_a: Array = map.get_region_tiles(region_a)
	var tiles_b_set: Dictionary = {}
	for coord in map.get_region_tiles(region_b):
		tiles_b_set[coord] = true
	for coord in tiles_a:
		for n in HexHelper.get_neighbors(coord):
			if tiles_b_set.has(n):
				return true
	return false
