extends SceneTree
## Temp tool: sets up a demo-map battle and captures screenshots during setup
## and mid-simulation for renderer verification. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_battle.gd
## Delete after use.

var _frames := 0
var _battle: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true  # Block new_game's campaign scene transition
	gm.new_game(&"empire", true, 0)
	gm._is_transitioning = false

	var attacker_id: StringName = &""
	var defender_id: StringName = &""
	var armies: Dictionary = gm.state.armies
	for aid in armies:
		var a = armies[aid]
		if a.faction_id == &"empire" and attacker_id == &"":
			attacker_id = aid
		elif a.faction_id != &"empire" and defender_id == &"":
			defender_id = aid
	if attacker_id == &"" or defender_id == &"":
		print("NO ARMIES FOUND attacker=%s defender=%s" % [attacker_id, defender_id])
		quit()
		return
	print("BATTLE: %s vs %s" % [attacker_id, defender_id])
	gm.set_meta("battle_attacker", attacker_id)
	gm.set_meta("battle_defender", defender_id)
	gm.set_meta("battle_hex_pos", armies[defender_id].hex_pos)

	var scene: PackedScene = load("res://scenes/battle/battle_v3.tscn")
	_battle = scene.instantiate()
	root.add_child(_battle)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _battle == null:
		return false
	if _frames == 30:
		_shot("battle_setup.png")
		_battle.call("_on_begin_battle")
	if _frames == 240:
		_shot("battle_sim.png")
		quit()
	return false
