extends SceneTree
## Plan C Task 9: the hoisted/memoized checks inside get_available_buildings
## must match the original expressions for every (city, building) pair.
## Run: godot --headless --path . -s res://tests/test_available_buildings.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)
	var cs = _gm.city_system

	var city_checked := 0
	for cid in _gm.state.cities:
		var city: CityState = _gm.state.cities[cid]
		# 1) The substituted valid-tile expression must equal the original call
		for bid in _dm.buildings:
			var building: BuildingData = _dm.buildings[bid]
			var original: bool = not cs.get_valid_tiles_for_building(city, building).is_empty()
			var substituted: bool
			if building.upgrades_from != &"" and city.building_tiles.has(building.upgrades_from):
				substituted = true
			else:
				substituted = not cs.get_valid_tiles_for_building_terrain(city, building.required_terrain).is_empty()
			if original != substituted:
				_fails += 1
				print("FAIL tile check %s/%s: orig=%s subst=%s" % [cid, bid, original, substituted])
		# 2) Full function must still return a self-consistent list (spot check:
		#    every returned building passes the original tile check and slot rule)
		var slots: int = city.get_available_building_slots()
		for b: BuildingData in cs.get_available_buildings(city):
			if cs.get_valid_tiles_for_building(city, b).is_empty():
				_fails += 1
				print("FAIL returned building without valid tile: %s/%s" % [cid, b.id])
			if b.upgrades_from == &"" and slots <= 0:
				_fails += 1
				print("FAIL returned base building with no slots: %s/%s" % [cid, b.id])
		city_checked += 1
		if city_checked >= 12:
			break

	if _fails == 0:
		print("AVAILABLE BUILDINGS TEST PASSED (%d cities)" % city_checked)
		quit(0)
	else:
		print("AVAILABLE BUILDINGS TEST FAILED (%d)" % _fails)
		quit(1)
