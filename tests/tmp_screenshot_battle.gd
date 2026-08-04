extends SceneTree
## Temp tool: sets up a demo-map battle and captures screenshots during setup
## and mid-simulation for renderer verification. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_battle.gd
## Delete after use.
##
## UI Polish Wave Task P6 extension: armies are inflated to 6 units per side
## (typical mid-game skirmish, well under the base 8-unit army-size cap) so
## the result screen's new 2-column roster gets a real multi-line test, and
## the run now drives the battle through to completion (_on_skip -> skip_to_end
## fast-forward) to capture the RESULT screen itself (battle_result.png),
## verifying the enlarged result_panel + 2-column layout needs no scrolling.
## Prior behavior (setup/sim shots) is unchanged.

var _frames := 0
var _battle: Node = null

func _init() -> void:
	call_deferred("_start")

func _inflate_army(gm: Node, dm: Node, army, target_size: int) -> void:
	if army.units.is_empty():
		return
	var template = army.units[0]
	var ud = dm.get_unit(template.unit_data_id)
	if ud == null:
		return
	while army.units.size() < target_size:
		var inst := UnitInstance.new()
		inst.init_from_data(ud, gm.state.generate_id())
		army.units.append(inst)

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

	# P6: fill both rosters to 6 units (typical-but-hefty) so the result
	# screen's 2-column roster is exercised with a realistic line count.
	var dm: Node = root.get_node("/root/DataManager")
	_inflate_army(gm, dm, armies[attacker_id], 6)
	_inflate_army(gm, dm, armies[defender_id], 6)

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
		_battle.call("_on_skip")  # fast-forward to completion (skip_to_end)
	if _frames == 300:
		# Diagnostic: confirm the roster ScrollContainer's v-scrollbar is NOT
		# needed for this typical (6v6) content -- programmatic check beyond
		# the visual screenshot judgment.
		var scrolls := _battle.find_children("*", "ScrollContainer", true, false)
		for s in scrolls:
			var sc := s as ScrollContainer
			var vbar: VScrollBar = sc.get_v_scroll_bar()
			print("RESULT SCROLLBAR visible=%s max=%s page=%s" % [vbar.visible, vbar.max_value, vbar.page])
		_shot("battle_result.png")
		quit()
	return false
