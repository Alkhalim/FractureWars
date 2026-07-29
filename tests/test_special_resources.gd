extends SceneTree
## Tests for tier-2 Special resources (Phase 2, docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_special_resources.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var map = _gm.state.hex_map

	# ── Scatter: all 8 types present, 1-3 each, valid terrain, no tile overlap ──
	var counts := {}
	var placed: Array[Vector2i] = []
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.special_id == &"":
			continue
		placed.append(coord)
		counts[tile.special_id] = counts.get(tile.special_id, 0) + 1
		var def: Dictionary = SpecialResourceSystem.SPECIAL_TYPES.get(tile.special_id, {})
		_check(not def.is_empty(), "special %s exists in table" % tile.special_id)
		_check(int(tile.terrain) in def.get("terrains", []), "special %s on allowed terrain (%d)" % [tile.special_id, tile.terrain])
		_check(tile.bounty_id == &"", "no bounty stacked on special tile %s" % coord)
	for type_id in SpecialResourceSystem.SPECIAL_TYPES:
		var c: int = counts.get(type_id, 0)
		_check(c >= 1 and c <= 3, "type %s spawns 1-3 times (got %d)" % [type_id, c])

	# ── Demo map must also guarantee all 8 types ──
	_gm.new_game(&"empire", true)
	var demo_counts := {}
	for coord in _gm.state.hex_map.tiles:
		var t = _gm.state.hex_map.tiles[coord]
		if t.special_id != &"":
			demo_counts[t.special_id] = demo_counts.get(t.special_id, 0) + 1
	for type_id in SpecialResourceSystem.SPECIAL_TYPES:
		_check(demo_counts.get(type_id, 0) >= 1, "demo map spawns type %s" % type_id)
	_gm.new_game(&"empire")

	# ── Determinism ──
	var fp := _fingerprint(map)
	_gm.new_game(&"empire")
	_check(_fingerprint(_gm.state.hex_map) == fp, "special scatter deterministic across new_game")

	# ── Serialization roundtrip + old-save compat ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fp, "special_id survives save/load roundtrip")
	for key in saved:
		saved[key].erase("special_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].special_id != &"":
			any = true
	_check(not any, "old saves without special_id load empty")

	if _fails == 0:
		print("SPECIALS TEST PASSED")
		quit(0)
	else:
		print("SPECIALS TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].special_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].special_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
