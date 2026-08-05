extends SceneTree
## Temp tool (UI Polish Wave 2, Task W4): captures the fixed pre-battle
## strength meter on a tanky-vs-many matchup, plus the new pale end-of-turn
## HP preview overlay on a healing army (in a city) and an attriting army
## (besieging an enemy city). Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w4.gd
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null

func _init() -> void:
	call_deferred("_start")

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _build_army(gm: Node, dm: Node, id: StringName, faction: StringName, hex: Vector2i, specs: Array) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = id
	army.faction_id = faction
	army.hex_pos = hex
	var n := 0
	for spec in specs:
		var ud: UnitData = dm.get_unit(spec["id"])
		if ud == null:
			continue
		for i in int(spec["n"]):
			var inst := UnitInstance.new()
			inst.init_from_data(ud, StringName("%s_u%d" % [id, n]))
			army.units.append(inst)
			n += 1
	return army

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true  # Block new_game's campaign scene transition
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)
	_hud = _campaign.get_node("UILayer/HUD")

func _setup_meter_shot() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	var dm: Node = root.get_node("/root/DataManager")
	# Tanky-few (player, empire) vs many-cheap (rebels) -- the exact shape of
	# the designer's bug report. Post-fix, the meter should now lean toward
	# the tanky player side instead of the swarm.
	var atk := _build_army(gm, dm, &"w4_meter_atk", &"empire", Vector2i(10, 10),
		[{"id": &"marching_bastion", "n": 1}])
	var def := _build_army(gm, dm, &"w4_meter_def", &"rebels", Vector2i(10, 10),
		[{"id": &"rebel_militia", "n": 2}])
	_campaign.call("_show_battle_dialog", atk, def)

func _find_player_city(gm: Node) -> CityState:
	var player_fid: StringName = gm.state.player_faction_id
	for cid in gm.state.cities:
		var c: CityState = gm.state.cities[cid]
		if c.faction_id == player_fid:
			return c
	return null

func _find_enemy_city(gm: Node) -> CityState:
	var player_fid: StringName = gm.state.player_faction_id
	for cid in gm.state.cities:
		var c: CityState = gm.state.cities[cid]
		if c.faction_id != player_fid and c.faction_id != &"" and c.faction_id != &"independent":
			return c
	return null

func _setup_healing_shot() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	var dm: Node = root.get_node("/root/DataManager")
	var city := _find_player_city(gm)
	if city == null:
		print("W4 SHOT: no player city found, skipping healing shot")
		return
	var army := _build_army(gm, dm, &"w4_heal_army", gm.state.player_faction_id, city.hex_pos,
		[{"id": &"legionary", "n": 1}, {"id": &"imperial_crossbow", "n": 1}])
	# Damage the units so the projected heal has a visible delta.
	for unit in army.units:
		var ud: UnitData = dm.get_unit(unit.unit_data_id)
		unit.current_hp = int(ud.max_hp * 0.5)
	gm.state.armies[&"w4_heal_army"] = army
	gm.movement_system.invalidate_positions()
	root.get_node("/root/EventBus").army_selected.emit(&"w4_heal_army")

func _setup_attrition_shot() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	var dm: Node = root.get_node("/root/DataManager")
	var city := _find_enemy_city(gm)
	if city == null:
		print("W4 SHOT: no enemy city found, skipping attrition shot")
		return
	city.is_under_siege = true
	city.siege_faction = gm.state.player_faction_id
	var army := _build_army(gm, dm, &"w4_siege_army", gm.state.player_faction_id, city.hex_pos,
		[{"id": &"legionary", "n": 1}, {"id": &"imperial_crossbow", "n": 1}])
	# Pre-damage so the trough (and the pale dimming sliver against it) is
	# visible -- a fresh full-HP bar makes a single-turn 2.5% attrition tick
	# nearly invisible at screenshot scale even though it's computed/drawn
	# correctly (see the numeric (-N) readout either way).
	for unit in army.units:
		var ud: UnitData = dm.get_unit(unit.unit_data_id)
		unit.current_hp = int(ud.max_hp * 0.6)
	gm.state.armies[&"w4_siege_army"] = army
	gm.movement_system.invalidate_positions()
	root.get_node("/root/EventBus").army_selected.emit(&"w4_siege_army")

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 20:
		_setup_meter_shot()
	if _frames == 30:
		_shot("w4_meter_tanky_vs_many.png")
		var hud_node: Control = _campaign.get_node("UILayer/HUD")
		if hud_node.has_method("_close_army_panel"):
			hud_node.call("_close_army_panel")
		if _campaign.get("_battle_dialog"):
			_campaign.get("_battle_dialog").queue_free()
			_campaign.set("_battle_dialog", null)
		_setup_healing_shot()
	if _frames == 40:
		_shot("w4_hp_preview_healing.png")
		_setup_attrition_shot()
	if _frames == 50:
		_shot("w4_hp_preview_attrition.png")
		quit()
	return false
