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
		# Focus the biggest city on the map so the new top-down town markers
		# are front and center
		var best := Vector2i(20, 15)
		var best_lvl := -1
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.is_settlement:
				continue
			var lvl: int = c.level + (3 if c.is_capital else 0)
			if lvl > best_lvl:
				best_lvl = lvl
				best = c.hex_pos
		print("FOCUS CITY TILE: %s" % str(best))
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
