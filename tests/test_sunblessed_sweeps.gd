extends SceneTree
## Plan B Task 4: neighborhood-inverted Sunblessed sweeps must produce the
## same faith contributions and near-army city sets as the old full scans.
## Run: godot --headless --path . -s res://tests/test_sunblessed_sweeps.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	seed(777)

	# Fabricate 25 armies at random positions for a hypothetical faction
	var fid: StringName = &"sunblessed"
	var armies: Array = []
	for i in 25:
		var a := ArmyState.new()
		a.army_id = StringName("__sun_test_%d" % i)
		a.faction_id = fid
		a.hex_pos = Vector2i(randi() % 117, randi() % 78)
		armies.append(a)

	# --- faith proximity: per-army contribution old vs new --------------------
	for army in armies:
		var old_contrib := _old_faith_contrib(army, fid)
		var new_contrib := _new_faith_contrib(army, fid)
		if old_contrib != new_contrib:
			_fails += 1
			print("FAIL faith at %s: old=%d new=%d" % [army.hex_pos, old_contrib, new_contrib])

	# --- wisdom near-army set: old vs new --------------------------------------
	var near_army_hexes: Dictionary = {}
	for army in armies:
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var h := Vector2i(army.hex_pos.x + dx, army.hex_pos.y + dy)
				if HexHelper.hex_distance(army.hex_pos, h) <= 2:
					near_army_hexes[h] = true
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		var old_near := false
		for army in armies:
			if HexHelper.hex_distance(army.hex_pos, city.hex_pos) <= 2:
				old_near = true
				break
		var new_near: bool = near_army_hexes.has(city.hex_pos)
		if old_near != new_near:
			_fails += 1
			print("FAIL wisdom near-army at city %s" % city_id)

	if _fails == 0:
		print("SUNBLESSED SWEEPS TEST PASSED")
		quit(0)
	else:
		print("SUNBLESSED SWEEPS TEST FAILED (%d)" % _fails)
		quit(1)

func _old_faith_contrib(army, fid: StringName) -> int:
	# Verbatim old inner loop
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if city.faction_id == fid or city.faction_id == &"independent":
			continue
		if HexHelper.hex_distance(army.hex_pos, city.hex_pos) <= 3:
			return mini(city.level, 3)
	return 0

func _new_faith_contrib(army, fid: StringName) -> int:
	# Mirrors the new neighborhood inversion in turn_manager
	var candidates: Array = []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var h := Vector2i(army.hex_pos.x + dx, army.hex_pos.y + dy)
			if HexHelper.hex_distance(army.hex_pos, h) > 3:
				continue
			var c: CityState = _gm.city_system.get_city_at_hex(h)
			if c == null or c.faction_id == fid or c.faction_id == &"independent":
				continue
			candidates.append(c)
	var best_city: CityState = null
	if candidates.size() == 1:
		best_city = candidates[0]
	elif candidates.size() > 1:
		for city_id in _gm.state.cities:
			var c2: CityState = _gm.state.cities[city_id]
			if candidates.has(c2):
				best_city = c2
				break
	return mini(best_city.level, 3) if best_city else 0
