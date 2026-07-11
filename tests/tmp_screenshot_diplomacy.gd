extends SceneTree
## Temp tool: opens the diplomatic audience screen and screenshots it.
## Run WITHOUT --headless. Delete after use.

var _frames := 0
var _campaign: Node = null

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

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 25:
		var hud: Control = _campaign.get_node("UILayer/HUD")
		hud.set("_diplo_detail_faction", &"gladehost")
		hud.call("_refresh_diplomacy_panel")
		var panel: Control = hud.get("_diplomacy_panel")
		panel.visible = true
	if _frames == 45:
		_shot("diplomacy_audience.png")
		quit()
	return false
