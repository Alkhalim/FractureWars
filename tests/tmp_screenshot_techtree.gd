extends SceneTree
## Temp tool: loads a demo campaign (fast), opens the tech tree, screenshots at
## default and low zoom. Also presets _max_bake_tex to exercise the immediate
## frame-0 bake path (battle-return scenario). Run WITHOUT --headless. Delete after use.

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
	if _frames == 25:
		_shot("campaign_frame0_bake.png")
		var hud: Control = _campaign.get_node("UILayer/HUD")
		hud.call("_toggle_research_panel")
	if _frames == 45:
		_shot("techtree_default.png")
		# Zoom out two steps via simulated wheel events on the tree control
		var tree: Control = hud_tree()
		if tree:
			tree._zoom = 0.5
			tree.queue_redraw()
	if _frames == 55:
		_shot("techtree_zoomout.png")
		quit()
	return false

func hud_tree() -> Control:
	var hud: Control = _campaign.get_node("UILayer/HUD")
	return hud.get("_research_tree")
