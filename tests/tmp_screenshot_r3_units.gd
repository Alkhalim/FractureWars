extends SceneTree
## Task R3 (unit stat rescale) UI spot-check: unit cards + recruit buttons +
## hover info (small post-/10 numbers legibility), and the auto-resolved
## battle report panel. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_r3_units.gd
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _city_id: StringName = &""
var _recruit_unit_id: StringName = &""
var _attacker_id: StringName = &""
var _defender_id: StringName = &""

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true  # Block new_game's campaign scene transition
	gm.new_game(&"empire", false, 0)
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

	if _frames == 20:
		var gm: Node = root.get_node("/root/GameManager")
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.faction_id == &"empire" and not c.is_settlement:
				_city_id = cid
				break
		if _city_id == &"":
			print("NO EMPIRE CITY FOUND")
			quit()
			return false
		hud._show_city_panel(_city_id)

	if _frames == 30:
		var gm: Node = root.get_node("/root/GameManager")
		var city = gm.state.cities[_city_id]
		var recruitable: Array = hud._get_recruitable_units(city)
		if recruitable.size() > 0:
			_recruit_unit_id = recruitable[0]
			hud._show_unit_card(_recruit_unit_id)
			print("HOVER UNIT CARD: ", _recruit_unit_id)
		else:
			print("NO RECRUITABLE UNITS FOR ", _city_id)

	if _frames == 45:
		_shot("r3_recruit_hover.png")

	if _frames == 55:
		# Set up an auto-resolved battle so campaign.gd's battle-report panel
		# (small post-rescale casualty/HP numbers) can be spot-checked too.
		hud._hide_unit_card() if hud.has_method("_hide_unit_card") else null
		var gm: Node = root.get_node("/root/GameManager")
		var armies: Dictionary = gm.state.armies
		for aid in armies:
			var a = armies[aid]
			if a.faction_id == &"empire" and _attacker_id == &"":
				_attacker_id = aid
			elif a.faction_id != &"empire" and _defender_id == &"":
				_defender_id = aid
		if _attacker_id == &"" or _defender_id == &"":
			print("NO ARMIES FOUND attacker=%s defender=%s" % [_attacker_id, _defender_id])
			quit()
			return false
		var br: Node = root.get_node("/root/BattleResolver")
		var def_hex: Vector2i = armies[_defender_id].hex_pos
		print("AUTO-RESOLVE: %s vs %s @ %s" % [_attacker_id, _defender_id, def_hex])
		br.auto_resolve(_attacker_id, _defender_id, def_hex)

	if _frames == 70:
		_shot("r3_battle_report.png")
		quit()

	return false
