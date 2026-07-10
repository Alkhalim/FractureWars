extends SceneTree
## Plan A Task 2: hex->city index must return exactly what the old linear scan did,
## including after city creation, hex_pos moves, and collisions.
## Run: godot --headless --path . -s res://tests/test_city_hex_index.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var cs = _gm.city_system

	_compare_all(cs, "initial state")

	# Simulate a city move (mobile camp pattern) + invalidation
	var first_city: CityState = null
	for cid in _gm.state.cities:
		first_city = _gm.state.cities[cid]
		break
	var old_pos: Vector2i = first_city.hex_pos
	first_city.hex_pos = Vector2i(old_pos.x + 1, old_pos.y)
	cs.invalidate_city_hex_index()
	_compare_all(cs, "after hex_pos move")
	_check(cs.get_city_at_hex(old_pos) == _reference(old_pos), "old position after move")

	# Simulate a new city insertion WITHOUT explicit invalidation (size check must catch it)
	var extra := CityState.new()
	extra.city_id = &"__test_extra"
	extra.hex_pos = Vector2i(1, 1)
	# Ensure the test hex is free; if occupied pick another
	var tries := 0
	while _reference(extra.hex_pos) != null and tries < 20:
		extra.hex_pos += Vector2i(1, 0)
		tries += 1
	_gm.state.cities[extra.city_id] = extra
	_compare_all(cs, "after uninvalidated insertion (size check)")
	_check(cs.get_city_at_hex(extra.hex_pos) == extra, "new city found via size check")

	if _fails == 0:
		print("CITY HEX INDEX TEST PASSED")
		quit(0)
	else:
		print("CITY HEX INDEX TEST FAILED (%d)" % _fails)
		quit(1)

func _reference(hex_pos: Vector2i) -> CityState:
	# Verbatim old implementation (first match in insertion order)
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if city.hex_pos == hex_pos:
			return city
	return null

func _compare_all(cs, label: String) -> void:
	# Every city position + a grid sample of empty hexes must match the reference.
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if cs.get_city_at_hex(city.hex_pos) != _reference(city.hex_pos):
			_fails += 1
			print("FAIL (%s): mismatch at city hex %s" % [label, city.hex_pos])
	for x in range(0, 117, 9):
		for y in range(0, 78, 7):
			var pos := Vector2i(x, y)
			if cs.get_city_at_hex(pos) != _reference(pos):
				_fails += 1
				print("FAIL (%s): mismatch at %s" % [label, pos])

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
