extends SceneTree
## Tests for tier-3 Landmarks (Phase 3, docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_landmarks.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var map = _gm.state.hex_map

	# ── Exactly SPAWN_COUNT landmarks, max 1 per type, terrain-fitting ──
	var placed := {}
	var coords_list: Array[Vector2i] = []
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.landmark_id == &"":
			continue
		coords_list.append(coord)
		_check(not placed.has(tile.landmark_id), "max 1 deposit of %s" % tile.landmark_id)
		placed[tile.landmark_id] = coord
		var def: Dictionary = LandmarkSystem.LANDMARK_TYPES.get(tile.landmark_id, {})
		_check(not def.is_empty(), "landmark %s in table" % tile.landmark_id)
		_check(int(tile.terrain) in def.get("terrains", []), "landmark %s on allowed terrain (%d)" % [tile.landmark_id, tile.terrain])
		_check(tile.special_id == &"" and tile.bounty_id == &"", "no other resource stacked on landmark tile")
		_check(tile.region_id != &"", "landmark tile belongs to a region")
	_check(placed.size() == LandmarkSystem.SPAWN_COUNT, "exactly %d landmarks spawn (got %d)" % [LandmarkSystem.SPAWN_COUNT, placed.size()])
	# Even spread: min pairwise distance
	for i in coords_list.size():
		for j in range(i + 1, coords_list.size()):
			if HexHelper.hex_distance(coords_list[i], coords_list[j]) < 12:
				_fails += 1
				print("FAIL: landmarks too close: %s %s" % [coords_list[i], coords_list[j]])

	# ── Determinism ──
	var fp := _fingerprint(map)
	_gm.new_game(&"empire", false, 0)
	_check(_fingerprint(_gm.state.hex_map) == fp, "landmark scatter deterministic")

	# ── Serialization roundtrip + old-save compat ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fp, "landmark_id survives save/load")
	for key in saved:
		saved[key].erase("landmark_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].landmark_id != &"":
			any = true
	_check(not any, "old saves load with no landmarks")

	# ── Demo map: still exactly SPAWN_COUNT (or all placeable) ──
	_gm.new_game(&"empire", true, 0)
	var demo_count := 0
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].landmark_id != &"":
			demo_count += 1
	_check(demo_count == LandmarkSystem.SPAWN_COUNT, "demo map places all %d landmarks (got %d)" % [LandmarkSystem.SPAWN_COUNT, demo_count])

	# ── Every landmark has a city within distance 2 (guardian rule), across seeds ──
	for s in [0, 1, 2]:
		_gm.new_game(&"empire", false, s)
		var map6 = _gm.state.hex_map
		for coord in map6.tiles:
			if map6.tiles[coord].landmark_id == &"":
				continue
			var found_city := false
			for cid in _gm.state.cities:
				if HexHelper.hex_distance(_gm.state.cities[cid].hex_pos, coord) <= 2:
					found_city = true
					break
			_check(found_city, "seed %d: landmark at %s has a neighboring city" % [s, coord])

	if _fails == 0:
		print("LANDMARKS TEST PASSED")
		quit(0)
	else:
		print("LANDMARKS TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].landmark_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].landmark_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
