extends SceneTree
## Plan B Task 9: border-tile-cached _get_neighbor_region_factions must equal
## the old full region scan (content AND order) for all regions.
## Run: godot --headless --path . -s res://tests/test_neighbor_factions.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)

	var fids: Array = [&"empire", &"skulloath", &"gladehost", &""]
	var checked := 0
	for rid in _dm.regions:
		for fid in fids:
			var new_arr: Array[StringName] = LoyaltySystem._get_neighbor_region_factions(rid, fid)
			var old_arr: Array[StringName] = _ref(rid, fid)
			if new_arr != old_arr:
				_fails += 1
				print("FAIL %s/%s: new=%s old=%s" % [rid, fid, new_arr, old_arr])
			checked += 1

	if _fails == 0:
		print("NEIGHBOR FACTIONS TEST PASSED (%d queries)" % checked)
		quit(0)
	else:
		print("NEIGHBOR FACTIONS TEST FAILED (%d)" % _fails)
		quit(1)

func _ref(region_id: StringName, faction_id: StringName) -> Array[StringName]:
	# Verbatim old _get_neighbor_region_factions
	var hex_map: HexMapData = _gm.state.hex_map
	if hex_map == null:
		return []
	var region_tiles := hex_map.get_region_tiles(region_id)
	var neighbor_factions: Array[StringName] = []
	for coord in region_tiles:
		for neighbor_coord in HexHelper.get_neighbors(coord):
			if not HexHelper.is_valid(neighbor_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var tile := hex_map.get_tile(neighbor_coord)
			if tile == null or tile.region_id == region_id:
				continue
			if tile.owner_faction != &"" and tile.owner_faction != faction_id:
				if not neighbor_factions.has(tile.owner_faction):
					neighbor_factions.append(tile.owner_faction)
	return neighbor_factions
