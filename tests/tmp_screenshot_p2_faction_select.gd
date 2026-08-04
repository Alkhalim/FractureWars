extends SceneTree
## Temp tool (Task P2): opens the main menu, shows faction select unpicked,
## then picks two different factions in turn — verifies the faction-styled
## row chrome, the 2/3-1/3 layout split, the map sketch, and the readable
## leader-bonus chips. Run WITHOUT --headless:
##   & <godot> --resolution 1920x1080 --path . -s res://tests/tmp_screenshot_p2_faction_select.gd
## Delete after use.

var _frames := 0
var _menu: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var scene: PackedScene = load("res://scenes/main/main_menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10 and _menu:
		_menu.call("_show_faction_select")
	if _frames == 20:
		_shot("p2_faction_select_unpicked.png")
	if _frames == 25 and _menu:
		_menu.call("_on_faction_list_clicked", &"skulloath")
	if _frames == 35:
		_shot("p2_faction_select_skulloath.png")
	if _frames == 40 and _menu:
		_menu.call("_on_faction_list_clicked", &"gladehost")
	if _frames == 50:
		_shot("p2_faction_select_gladehost.png")
		quit()
	return false
