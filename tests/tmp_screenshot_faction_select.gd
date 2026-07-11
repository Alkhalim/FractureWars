extends SceneTree
## Temp tool: opens the main menu, shows faction select, selects a faction,
## and saves a screenshot for layout verification. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_faction_select.gd
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
	if _frames == 10 and _menu:
		_menu.call("_show_faction_select")
	if _frames == 20 and _menu:
		_menu.call("_on_faction_list_clicked", &"tainted_jade")
	if _frames == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://faction_select_check.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://faction_select_check.png"))
		quit()
	return false
