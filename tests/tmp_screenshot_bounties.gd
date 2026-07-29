extends SceneTree
## Temp tool: verifies bounty corner icons render on the campaign map + hover
## tooltip wiring compiles. Delete after use.

var _frames := 0
var _campaign: Node = null
var _bounty_coord := Vector2i(-9999, -9999)
var _pinned := false

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	if _frames == 40:
		var gm: Node = root.get_node("/root/GameManager")
		var map = gm.state.hex_map
		for coord in map.tiles:
			var tile = map.tiles[coord]
			if tile.bounty_id != &"":
				_bounty_coord = coord
				break
		print("BOUNTY TILE: ", _bounty_coord)
		# Disable fog so the icon + tooltip fog-gate can't hide the result, then
		# force every bounty marker visible (mirrors what a real fog update would do).
		_campaign.set("_fog_of_war_enabled", false)
		_campaign.set("_fog_dirty", true)
		_campaign.call("_refresh_bounty_marker_visibility")

	if _frames >= 40 and _bounty_coord != Vector2i(-9999, -9999):
		var cam: Camera2D = _campaign.get("camera")
		if cam:
			cam.position = _campaign.call("_hex_to_pixel", _bounty_coord)
			cam.zoom = Vector2(2, 2)
			_pinned = true

	if _frames == 54 and _bounty_coord != Vector2i(-9999, -9999):
		# Exercise the hover tooltip directly (no real mouse-motion event fires
		# in a headed -s run without simulated input) and center the mouse so the
		# tooltip lands on-screen for the frame-55 screenshot.
		var center := root.get_viewport().get_visible_rect().size / 2
		root.get_viewport().warp_mouse(center)
		_campaign.call("_update_bounty_hover", _bounty_coord)
		var tip: Node = _campaign.get("_bounty_tooltip")
		if tip:
			print("TOOLTIP visible=", tip.visible, " text=[", tip.get_node("Text").text, "]")
		else:
			print("WARNING: _bounty_tooltip is null after _update_bounty_hover")

	if _frames == 55:
		if not _pinned:
			print("WARNING: no bounty tile found / camera not pinned")
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://win_bounty_icons.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_bounty_icons.png"))
		quit()
	return false
