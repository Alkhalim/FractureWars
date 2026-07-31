extends SceneTree
## Temp tool: windowed repro of the Ivoryscar camera-clamp bug. Starts an
## Ivoryscar campaign, pushes the camera far west, then tries to return to the
## capital and clamps — PASS if the clamped camera lands on the capital.

var _frames := 0
var _campaign: Node = null
var _capital_pos := Vector2.ZERO

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"ivoryscar", false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 30:
		var gm: Node = root.get_node("/root/GameManager")
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.faction_id == &"ivoryscar" and c.is_capital:
				print("CAPITAL HEX: %s" % str(c.hex_pos))
				_capital_pos = _campaign.call("_hex_to_pixel", c.hex_pos)
				break
		var cam: Camera2D = _campaign.get("camera")
		# 1) Simulate the player panning far away, with clamping active
		cam.position = Vector2(200.0, 200.0)
		cam.call("_clamp_position")
		# 2) Try to come back to the capital (what minimap click does)
		cam.position = _capital_pos
		cam.call("_clamp_position")
		var dist: float = cam.position.distance_to(_capital_pos)
		print("CAPITAL PIXEL: %s  CLAMPED CAM: %s  DIST: %.0f" % [str(_capital_pos), str(cam.position), dist])
		# The capital may legitimately sit closer to the map edge than half a
		# viewport — allow that much, nothing more.
		var vp_half: Vector2 = cam.get_viewport_rect().size / cam.zoom / 2.0
		if dist <= vp_half.x:
			print("CAMERA CLAMP: PASSED (capital reachable)")
		else:
			print("CAMERA CLAMP: FAILED (capital cut off by %.0f px)" % dist)
	if _frames == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://camera_ivoryscar.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://camera_ivoryscar.png"))
		quit()
	return false
