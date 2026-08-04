extends SceneTree
## Temp tool (Task P2): loads the main menu and screenshots it — verifies the
## impressive title treatment + lighter vignette background. Run WITHOUT
## --headless:
##   & <godot> --resolution 1920x1080 --path . -s res://tests/tmp_screenshot_p2_menu.gd
## Delete after use.

var _frames := 0
var _menu: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var scene: PackedScene = load("res://scenes/main/main_menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://p2_main_menu.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://p2_main_menu.png"))
		quit()
	return false
