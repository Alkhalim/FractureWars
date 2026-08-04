extends SceneTree
## Fix-round verification (Task P2 review): confirms the desc-chip no longer
## fills all remaining vertical space (SIZE_EXPAND_FILL bug) and instead
## shrinks to its content while the map sketch grows to absorb the freed
## space — checked at both content-length extremes:
##   - forsaken: longest combined description+playstyle+traits+unique text
##     among PLAYABLE_FACTIONS (measured via a scratch char-count pass).
##   - shardhorde: shortest (also nomadic — exercises the "no fixed capital"
##     caption path in the sketch at the same time).
##   - skulloath: same faction as the original bug screenshot
##     (p2_faction_select_skulloath.png), for a direct before/after diff.
## Run WITHOUT --headless:
##   & <godot> --resolution 1920x1080 --path . -s res://tests/tmp_screenshot_p2fix_faction_select.gd
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
	if _frames == 20 and _menu:
		_menu.call("_on_faction_list_clicked", &"forsaken")
	if _frames == 30:
		_shot("p2fix_faction_select_forsaken_longest.png")
	if _frames == 35 and _menu:
		_menu.call("_on_faction_list_clicked", &"shardhorde")
	if _frames == 45:
		_shot("p2fix_faction_select_shardhorde_shortest.png")
	if _frames == 50 and _menu:
		_menu.call("_on_faction_list_clicked", &"skulloath")
	if _frames == 60:
		_shot("p2fix_faction_select_skulloath.png")
		quit()
	return false
