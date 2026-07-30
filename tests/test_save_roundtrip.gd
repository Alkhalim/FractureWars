extends SceneTree
## Plan B Task 7 (revised): binary .res autosave must roundtrip losslessly.
## Run: godot --headless --path . -s res://tests/test_save_roundtrip.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)

	var turn: int = _gm.state.current_turn
	var city_count: int = _gm.state.cities.size()
	var army_count: int = _gm.state.armies.size()
	var faction_count: int = _gm.state.faction_states.size()
	var sample_city_id: StringName = &""
	var sample_city_pos := Vector2i.ZERO
	for cid in _gm.state.cities:
		sample_city_id = cid
		sample_city_pos = _gm.state.cities[cid].hex_pos
		break

	var t0 := Time.get_ticks_usec()
	_gm.save_game(99)
	var save_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("save took %.1f ms" % save_ms)
	_check(_gm.has_save(99), "has_save finds .res save")

	_gm.load_game(99)
	_check(_gm.state != null, "state loaded")
	_check(_gm.state.current_turn == turn, "turn preserved")
	_check(_gm.state.cities.size() == city_count, "city count preserved")
	_check(_gm.state.armies.size() == army_count, "army count preserved")
	_check(_gm.state.faction_states.size() == faction_count, "faction count preserved")
	if _gm.state.cities.has(sample_city_id):
		_check(_gm.state.cities[sample_city_id].hex_pos == sample_city_pos, "city position preserved")
	else:
		_check(false, "sample city missing after load")
	# Post-load caches must serve correct data
	var c: CityState = _gm.state.cities[sample_city_id]
	_check(_gm.city_system.get_city_at_hex(sample_city_pos) == c, "city hex index rebuilt after load")

	# Cleanup test save
	DirAccess.remove_absolute("user://saves/save_99.res")
	DirAccess.remove_absolute("user://saves/save_99_meta.cfg")

	if _fails == 0:
		print("SAVE ROUNDTRIP TEST PASSED")
		quit(0)
	else:
		print("SAVE ROUNDTRIP TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
