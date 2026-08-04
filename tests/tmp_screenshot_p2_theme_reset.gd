extends SceneTree
## Temp tool (Task P2): reproduces the "returning to main menu keeps the last
## faction's chrome" bug repro end-to-end — starts a real Skulloath demo
## game (applies skulloath chrome), screenshots the live campaign HUD to
## prove skulloath chrome is genuinely active, then returns to the main menu
## the same way campaign_hud.gd's "Main Menu" button does
## (GameManager.transition_to_scene) and screenshots the menu — should now
## show NEUTRAL chrome despite skulloath having been active moments before.
## Run WITHOUT --headless:
##   & <godot> --resolution 1920x1080 --path . -s res://tests/tmp_screenshot_p2_theme_reset.gd
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _menu: Node = null
var _phase := 0 # 0 = campaign up, 1 = returned to menu

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", true) # demo map for speed
	gm._is_transitioning = false
	print("AFTER new_game(skulloath): chrome_set_id=", gm.chrome_set_id)
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0:
		if _frames == 40:
			var gm: Node = root.get_node("/root/GameManager")
			print("BEFORE return: chrome_set_id=", gm.chrome_set_id)
			_shot("p2_theme_before_skulloath_campaign.png")
		if _frames == 45:
			# Same path campaign_hud.gd's "Main Menu" button uses.
			var gm2: Node = root.get_node("/root/GameManager")
			var am: Node = root.get_node("/root/AudioManager")
			am.stop_music()
			gm2._is_transitioning = true # skip the tween/fade for a deterministic headless-ish shot
			_campaign.queue_free()
			_campaign = null
			var menu_scene: PackedScene = load("res://scenes/main/main_menu.tscn")
			_menu = menu_scene.instantiate()
			root.add_child(_menu)
			gm2._is_transitioning = false
			print("AFTER menu instantiate/_ready: chrome_set_id=", gm2.chrome_set_id)
			_phase = 1
	elif _phase == 1:
		if _frames == 60:
			_shot("p2_theme_after_menu_neutral.png")
			quit()
	return false
