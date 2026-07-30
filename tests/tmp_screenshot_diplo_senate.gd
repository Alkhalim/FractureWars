extends SceneTree
## Temp tool: screenshots the reworked diplomacy panel (list + world map) and
## the Imperial Senate. Delete after use.

var _frames := 0
var _campaign: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
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
	var hud: Control = _campaign.get_node_or_null("UILayer/HUD")
	if hud == null:
		return false
	if _frames == 40:
		# Explore a chunk of the map so the diplo world map has content
		var gm: Node = root.get_node("/root/GameManager")
		for coord in gm.state.hex_map.tiles:
			if (coord.x + coord.y) % 2 == 0 or coord.x < 60:
				gm.explored_tiles[coord] = true
		hud._diplomacy_panel.visible = true
		hud._refresh_diplomacy_panel()
	if _frames == 55:
		_shot("ux_diplomacy.png")
		hud._diplomacy_panel.visible = false
		hud._refresh_policies_panel()
		hud._policies_panel.visible = true
	if _frames == 70:
		_shot("ux_senate.png")
		quit()
	return false
