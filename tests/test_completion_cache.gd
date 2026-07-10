extends SceneTree
## Plan A Task 5: cached completed regions/cultures must equal the brute-force
## reference for every faction, including after a simulated capture.
## Run: godot --headless --path . -s res://tests/test_completion_cache.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")

	_compare_all("initial")
	_compare_all("cached second read")

	# Simulate a capture: flip one city's faction and invalidate
	var target: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id != &"empire" and c.faction_id != &"" and c.faction_id != &"independent":
			target = c
			break
	if target:
		target.faction_id = &"empire"
		_gm.invalidate_completion_cache()
		_compare_all("after simulated capture")
	else:
		print("WARN: no capturable city found; capture case skipped")

	if _fails == 0:
		print("COMPLETION CACHE TEST PASSED")
		quit(0)
	else:
		print("COMPLETION CACHE TEST FAILED (%d)" % _fails)
		quit(1)

func _compare_all(label: String) -> void:
	for fid in _gm.state.faction_states:
		var new_r: Array = _gm.get_completed_regions(fid)
		var old_r: Array = _ref_regions(fid)
		if new_r != old_r:
			_fails += 1
			print("FAIL regions (%s) %s:\n  new=%s\n  old=%s" % [label, fid, new_r, old_r])
		var new_c: Array = _gm.get_completed_cultures(fid)
		var old_c: Array = _ref_cultures(fid)
		if new_c != old_c:
			_fails += 1
			print("FAIL cultures (%s) %s:\n  new=%s\n  old=%s" % [label, fid, new_c, old_c])

func _ref_regions(faction_id: StringName) -> Array[StringName]:
	# Verbatim old get_completed_regions
	var result: Array[StringName] = []
	for region_id in _gm.REGION_CITIES:
		var all_owned := true
		for city_id in _gm.state.cities:
			var city: CityState = _gm.state.cities[city_id]
			if city.region_id == region_id and city.faction_id != faction_id:
				all_owned = false
				break
		if all_owned:
			result.append(region_id)
	return result

func _ref_cultures(faction_id: StringName) -> Array[StringName]:
	# Verbatim old get_completed_cultures (on the reference regions)
	var completed_regions := _ref_regions(faction_id)
	var result: Array[StringName] = []
	for culture_id in _gm.CULTURE_REGIONS:
		var regions: Array = _gm.CULTURE_REGIONS[culture_id]
		var all_complete := true
		for r in regions:
			if r not in completed_regions:
				all_complete = false
				break
		if all_complete:
			result.append(culture_id)
	return result
