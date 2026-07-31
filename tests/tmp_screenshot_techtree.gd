extends SceneTree
## Temp tool: loads a demo campaign (fast), opens the tech tree, screenshots at
## default and low zoom, then force-opens the research detail dialog on a
## tier-1 tech (Deliverable 1: "Research Cost: %d Tech | %d turns" line) and
## screenshots that too. Also presets _max_bake_tex to exercise the immediate
## frame-0 bake path (battle-return scenario). Run WITHOUT --headless. Delete after use.

var _frames := 0
var _campaign: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false, 0)
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
		var hud: Control = _campaign.get_node("UILayer/HUD")
		var tier1_data: ResearchData = _find_tier1_research()
		if tier1_data:
			hud.call("_show_research_detail", tier1_data)
		else:
			print("ERROR: no tier-1 research found for the detail-dialog screenshot")
	if _frames == 65:
		_shot("win_tech_cost.png")
		quit()
	return false

func hud_tree() -> Control:
	var hud: Control = _campaign.get_node("UILayer/HUD")
	return hud.get("_research_tree")

func _find_tier1_research() -> ResearchData:
	var dm: Node = root.get_node("/root/DataManager")
	for rid in dm.research:
		var data: ResearchData = dm.research[rid]
		if data.tier == 1:
			return data
	return null
