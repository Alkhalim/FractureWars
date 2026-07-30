extends SceneTree
## Plan B Task 3: set-based settlement sphere + region-scoped candidate scan
## must equal the old implementations exactly (content AND order).
## Run: godot --headless --path . -s res://tests/test_settlement_tiles.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var cs = _gm.city_system
	var hex_map: HexMapData = _gm.state.hex_map

	# Sphere membership: every map tile must agree with the brute force
	var mismatches := 0
	for coord in hex_map.tiles:
		if cs.is_in_settlement_sphere(coord) != _ref_sphere(coord, cs.SETTLEMENT_SPHERE_RADIUS):
			mismatches += 1
			if mismatches <= 5:
				print("FAIL sphere at %s" % coord)
	if mismatches > 0:
		_fails += mismatches
	print("sphere check: %d tiles" % hex_map.tiles.size())

	# Valid settlement tiles: content and order for a few faction/region pairs
	var checked := 0
	for fid in _gm.state.faction_states:
		var fs: FactionState = _gm.state.faction_states[fid]
		if fs.owned_cities.is_empty():
			continue
		var city: CityState = _gm.state.cities[fs.owned_cities[0]]
		var new_tiles: Array[Vector2i] = cs.get_valid_settlement_tiles(fid, city.region_id)
		var old_tiles: Array[Vector2i] = _ref_valid_tiles(cs, fid, city.region_id, &"")
		if new_tiles != old_tiles:
			_fails += 1
			print("FAIL valid tiles %s/%s: new=%d old=%d" % [fid, city.region_id, new_tiles.size(), old_tiles.size()])
		checked += 1
		if checked >= 4:
			break

	# After founding a settlement-like city, sphere must update (size check)
	var extra := CityState.new()
	extra.city_id = &"__test_sphere_city"
	extra.hex_pos = Vector2i(50, 40)
	_gm.state.cities[extra.city_id] = extra
	if not cs.is_in_settlement_sphere(Vector2i(50, 40)):
		_fails += 1
		print("FAIL: sphere not updated after city insertion")

	if _fails == 0:
		print("SETTLEMENT TILES TEST PASSED (%d faction/region pairs)" % checked)
		quit(0)
	else:
		print("SETTLEMENT TILES TEST FAILED (%d)" % _fails)
		quit(1)

func _ref_sphere(hex_pos: Vector2i, radius: int) -> bool:
	# Verbatim old is_in_settlement_sphere
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if HexHelper.hex_distance(hex_pos, city.hex_pos) <= radius:
			return true
	return false

func _ref_valid_tiles(cs, faction_id: StringName, region_id: StringName, city_id: StringName) -> Array[Vector2i]:
	# Verbatim old get_valid_settlement_tiles (full-map scan + brute sphere)
	var result: Array[Vector2i] = []
	var hex_map: HexMapData = _gm.state.hex_map
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id != region_id:
			continue
		if tile.owner_faction != faction_id:
			continue
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if tile.terrain == Enums.TerrainType.MOUNTAINS:
			continue
		if _ref_sphere(coord, cs.SETTLEMENT_SPHERE_RADIUS):
			continue
		if city_id != &"":
			var territory_owner = cs.get_city_territory_owner(coord, region_id)
			if territory_owner != city_id:
				continue
		result.append(coord)
	return result
