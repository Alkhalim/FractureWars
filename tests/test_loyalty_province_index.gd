extends SceneTree
## Plan B Task 8: the province index must return exactly what the old per-call
## scan returned, including after ownership changes.
## Run: godot --headless --path . -s res://tests/test_loyalty_province_index.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")

	_compare_all("initial")
	_compare_all("cached second read")

	# Simulate a capture through the real path (bumps the topology epoch)
	var target: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id != &"empire" and c.faction_id != &"" and c.faction_id != &"independent":
			target = c
			break
	if target:
		target.faction_id = &"empire"
		_gm.invalidate_completion_cache() # real capture path calls this
		_compare_all("after simulated capture")

	if _fails == 0:
		print("PROVINCE INDEX TEST PASSED")
		quit(0)
	else:
		print("PROVINCE INDEX TEST FAILED (%d)" % _fails)
		quit(1)

func _compare_all(label: String) -> void:
	# Every (region, faction) combination that exists, plus some misses
	var pairs: Dictionary = {}
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		pairs["%s|%s" % [c.region_id, c.faction_id]] = [c.region_id, c.faction_id]
	pairs["missing|missing"] = [&"__no_region", &"__no_faction"]
	for key in pairs:
		var rid: StringName = pairs[key][0]
		var fid: StringName = pairs[key][1]
		var new_arr: Array[CityState] = LoyaltySystem.get_province_cities(rid, fid)
		var old_arr: Array[CityState] = _ref(rid, fid)
		if new_arr != old_arr:
			_fails += 1
			print("FAIL (%s) %s: new=%d old=%d" % [label, key, new_arr.size(), old_arr.size()])

func _ref(region_id: StringName, faction_id: StringName) -> Array[CityState]:
	# Verbatim old get_province_cities
	var result: Array[CityState] = []
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if city.region_id == region_id and city.faction_id == faction_id:
			result.append(city)
	return result
