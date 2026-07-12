extends SceneTree
## Temp tool: screenshots panel edge alignment — city panel + region panel +
## commander panel all visible. Delete after use.

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
	var hud: Control = _campaign.get_node_or_null("UILayer/HUD")
	if hud == null:
		return false
	if _frames == 40:
		var gm: Node = root.get_node("/root/GameManager")
		for cid in gm.state.cities:
			if gm.state.cities[cid].faction_id == &"skulloath":
				hud._show_city_panel(cid)
				break
		hud.region_panel.visible = true
		hud.commander_panel.visible = true
		# Select first player army so commander panel has content
		for aid in gm.state.armies:
			var a = gm.state.armies[aid]
			if a.faction_id == &"skulloath":
				hud._update_commander_panel(a)
				break
	if _frames == 55:
		_shot("panels_flush.png")
		quit()
	return false
