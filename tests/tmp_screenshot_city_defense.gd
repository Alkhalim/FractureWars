extends SceneTree
## Temp tool (unit-stat-rescale final review, windowed spot-check): visual
## verification that the C1(a) arrow_tower/catapult hardcoded formations
## render with sane post-fix numbers (attack 4/40->4, defense 3/30->3,
## hp 80/800->80 for the tower; attack 8/80->8, hp 50/500->50 for the
## catapult) once actually visible in the manual-Fight battle UI, not just
## via the headless parity harness. Forces a high-defense_bonus building
## onto a real city (same treant_citadel trick as
## tests/test_rescale_parity_v3.gd's city_defense_formations coverage
## matchup) so setup_city_defense_formations() spawns both a tower and a
## siege/catapult formation, then drives the real battle_v3.tscn scene the
## same way tests/tmp_screenshot_battle.gd does. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_city_defense.gd
## Delete after use.

var _frames := 0
var _battle: Node = null

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true # Block new_game's campaign scene transition
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false

	var dm: Node = root.get_node("/root/DataManager")

	# Find a real city and force a high-defense_bonus building onto it so
	# BOTH a tower and a siege/catapult position spawn (tier >= 13, see
	# BattleTerrainGen.apply_defensive_buildings).
	var city_id: StringName = &""
	for cid in gm.state.cities:
		city_id = cid
		break
	if city_id == &"":
		print("NO CITY FOUND")
		quit()
		return
	var city = gm.state.cities[city_id]
	if not city.buildings.has(&"treant_citadel"):
		city.buildings.append(&"treant_citadel")
	print("CITY: %s defense buildings=%s" % [city_id, city.buildings])

	# Any two armies, attacker vs. a defender -- battle_hex_pos below is what
	# actually decides where (and thus whether defense formations spawn), not
	# the armies' own physical positions.
	var attacker_id: StringName = &""
	var defender_id: StringName = &""
	for aid in gm.state.armies:
		var a = gm.state.armies[aid]
		if a.faction_id == &"empire" and attacker_id == &"":
			attacker_id = aid
		elif a.faction_id != &"empire" and defender_id == &"":
			defender_id = aid
	if attacker_id == &"" or defender_id == &"":
		print("NO ARMIES FOUND attacker=%s defender=%s" % [attacker_id, defender_id])
		quit()
		return
	print("BATTLE: %s vs %s AT CITY %s" % [attacker_id, defender_id, city_id])

	gm.set_meta("battle_attacker", attacker_id)
	gm.set_meta("battle_defender", defender_id)
	gm.set_meta("battle_hex_pos", city.hex_pos)

	var scene: PackedScene = load("res://scenes/battle/battle_v3.tscn")
	_battle = scene.instantiate()
	root.add_child(_battle)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _init() -> void:
	call_deferred("_start")

func _process(_delta: float) -> bool:
	_frames += 1
	if _battle == null:
		return false
	if _frames == 30:
		_shot("ffw_city_defense_setup.png")
		_battle.call("_on_begin_battle")
	if _frames == 200:
		_shot("ffw_city_defense_sim.png")
		quit()
	return false
