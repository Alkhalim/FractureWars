extends SceneTree
## Temp tool: loads a demo campaign, screenshots the initial view, then pans
## the camera far away and screenshots again — verifies fog of war redraws
## with the camera (regression check for the stale-culling fix). Delete after use.

var _frames := 0
var _campaign: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 40:
		_shot("campaign_fog_before_pan.png")
		var gm: Node = root.get_node("/root/GameManager")
		var player_cities: Array = []
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.faction_id == &"skulloath":
				player_cities.append(c)
		print("PLAYER CITIES: %d" % player_cities.size())
		# Find a coastal water tile (water with several land neighbors) so the
		# screenshot shows shoreline bleed and river rendering
		var hex_map = gm.state.hex_map
		var coast := Vector2i(-1, -1)
		for coord in hex_map.tiles:
			if hex_map.tiles[coord].terrain != 8:  # WATER
				continue
			var land := 0
			for n in HexHelper.get_neighbors(coord):
				if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
					continue
				var nt = hex_map.tiles.get(n)
				if nt and nt.terrain != 8:
					land += 1
			if land >= 3:
				coast = coord
				break
		print("COAST TILE: %s" % str(coast))
		# Reveal the map so the shoreline/river rendering is visible
		_campaign.set("_fog_of_war_enabled", false)
		_campaign.set("_fog_dirty", true)
		if coast.x >= 0:
			_city_pos = _campaign.call("_hex_to_pixel", coast)
		elif not player_cities.is_empty():
			_city_pos = _campaign.call("_hex_to_pixel", player_cities[0].hex_pos)
	if _frames >= 40 and _city_pos != Vector2.ZERO:
		# Pin camera every frame — the camera controller edge-pans/zoom-lerps
		var cam: Camera2D = _campaign.get("camera")
		cam.position = _city_pos
		cam.zoom = Vector2(2.0, 2.0)
		cam.set("_target_zoom", 2.0)
	if _frames == 60:
		_shot("campaign_zoomed_in.png")
		quit()
	return false

var _city_pos := Vector2.ZERO
