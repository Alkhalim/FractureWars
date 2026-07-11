extends SceneTree
## Temp tool: loads a demo campaign with fog disabled and screenshots a
## land-rich area at medium and close zoom — verifies tile rotation variety
## and the reworked terrain sets on the live map. Delete after use.

var _frames := 0
var _campaign: Node = null
var _focus := Vector2.ZERO

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
		var gm: Node = root.get_node("/root/GameManager")
		var hex_map = gm.state.hex_map
		# Find the coord with the most mountain/desert/swamp/shardwaste tiles
		# in its vicinity so the shot shows the reworked sets
		var best := Vector2i(20, 15)
		var best_score := -1
		for coord in hex_map.tiles:
			var t: int = hex_map.tiles[coord].terrain
			if t != 2 and t != 3:
				continue
			var score := 0
			for n in HexHelper.get_neighbors(coord):
				var nt = hex_map.tiles.get(n)
				if nt and (nt.terrain in [2, 3, 4, 7]):
					score += 1
			if score > best_score:
				best_score = score
				best = coord
		print("FOCUS TILE: %s score %d" % [str(best), best_score])
		_campaign.set("_fog_of_war_enabled", false)
		_campaign.set("_fog_dirty", true)
		_focus = _campaign.call("_hex_to_pixel", best)
	if _frames >= 40 and _focus != Vector2.ZERO:
		var cam: Camera2D = _campaign.get("camera")
		cam.position = _focus
		var z := 0.8 if _frames < 60 else 1.7
		cam.zoom = Vector2(z, z)
		cam.set("_target_zoom", z)
	if _frames == 58:
		_shot("terrain_rot_mid.png")
	if _frames == 80:
		_shot("terrain_rot_close.png")
		quit()
	return false
