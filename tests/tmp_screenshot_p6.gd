extends SceneTree
## Temp tool: UI Polish Wave Task P6 verification -- campaign-side surfaces:
## (1) the pre-battle attack-confirmation dialog's new relative strength
##     meter (_show_battle_dialog in campaign.gd), forced into a LOPSIDED
##     matchup (player stripped to 1 unit, enemy stacked to 7) so the meter
##     visibly leans toward ENEMY;
## (2) the auto-resolve battle report (_show_battle_report), driven through
##     the real BattleResolver.auto_resolve() path with a moderate (5v5)
##     roster, checking the enlarged 2-column window needs no scrolling and
##     spoils render as icons.
##
## The THIRD P6 surface (battle_v3.gd's own manual-battle result screen) is
## covered separately by the existing tests/tmp_screenshot_battle.gd harness
## (extended this task with a skip-to-end result shot), matching the
## established precedent of driving that scene standalone.
## Run WITHOUT --headless. Delete after use.

var _frames := 0
var _campaign: Node = null
var _atk_id: StringName = &""
var _def_id: StringName = &""
var _hex := Vector2i.ZERO

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", true, 0)
	gm._is_transitioning = false

	var armies: Dictionary = gm.state.armies
	for aid in armies:
		var a = armies[aid]
		if a.faction_id == &"empire" and _atk_id == &"":
			_atk_id = aid
		elif a.faction_id != &"empire" and _def_id == &"":
			_def_id = aid
	if _atk_id == &"" or _def_id == &"":
		print("NO ARMIES FOUND atk=%s def=%s" % [_atk_id, _def_id])
		quit()
		return
	print("BATTLE: %s vs %s" % [_atk_id, _def_id])

	var atk_army = armies[_atk_id]
	var def_army = armies[_def_id]
	_hex = def_army.hex_pos

	# LOPSIDED matchup for the strength meter shot: strip the player
	# (attacker, empire) down to a single unit; stack the enemy defender
	# with several extra copies of its own unit -- meter should visibly
	# lean toward ENEMY.
	if atk_army.units.size() > 1:
		atk_army.units = atk_army.units.slice(0, 1)
	var dm: Node = root.get_node("/root/DataManager")
	if def_army.units.size() > 0:
		var template = def_army.units[0]
		var ud = dm.get_unit(template.unit_data_id)
		if ud:
			while def_army.units.size() < 7:
				var inst := UnitInstance.new()
				inst.init_from_data(ud, gm.state.generate_id())
				def_army.units.append(inst)

	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fname := "p6_%s" % name
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

func _crop(name: String, rect: Rect2, pad: float = 8.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		print("CROP SKIPPED (empty rect): ", name, " rect=", rect)
		return
	var img := root.get_viewport().get_texture().get_image()
	var logical_size: Vector2 = root.get_visible_rect().size
	var px_scale: Vector2 = Vector2(img.get_size()) / logical_size
	var grown := rect.grow(pad)
	var scaled := Rect2(grown.position * px_scale, grown.size * px_scale)
	var r := Rect2i(scaled).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		print("CROP SKIPPED (out of bounds): ", name, " rect=", rect)
		return
	var cropped := img.get_region(r)
	var fname := "p6_%s" % name
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r, " px_scale=", px_scale)

func _report_scrollbars(panel: Control, label: String) -> void:
	var scrolls := panel.find_children("*", "ScrollContainer", true, false)
	for s in scrolls:
		var sc := s as ScrollContainer
		var vbar: VScrollBar = sc.get_v_scroll_bar()
		print("%s SCROLLBAR visible=%s max=%s page=%s" % [label, vbar.visible, vbar.max_value, vbar.page])

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	# ── Pre-battle dialog with strength meter (lopsided) ──
	if _frames == 30:
		var gm: Node = root.get_node("/root/GameManager")
		var atk_army = gm.state.armies.get(_atk_id)
		var def_army = gm.state.armies.get(_def_id)
		_campaign.set("_pending_battle_attacker_id", _atk_id)
		_campaign.set("_pending_battle_defender_id", _def_id)
		_campaign.set("_pending_battle_hex", _hex)
		_campaign.call("_show_battle_dialog", atk_army, def_army)

	if _frames == 45:
		_shot("prebattle_meter.png")
		var dlg: Control = _campaign.get("_battle_dialog")
		if dlg:
			_crop("prebattle_meter_closeup.png", dlg.get_global_rect(), 6.0)
			dlg.queue_free()
			_campaign.set("_battle_dialog", null)

	# ── Auto-resolve battle report (moderate 5v5 roster) ──
	if _frames == 60:
		var gm2: Node = root.get_node("/root/GameManager")
		var dm2: Node = root.get_node("/root/DataManager")
		var atk_army2 = gm2.state.armies.get(_atk_id)
		var def_army2 = gm2.state.armies.get(_def_id)
		if atk_army2 and def_army2:
			# Swap templates (attacker gets the DEFENDER's stronger unit type,
			# defender gets the weak Levy Conscripts) so the ATTACKER (player)
			# wins convincingly this pass -- exercises the icon-based spoils
			# row (only the winner gets loot in the report dict).
			var strong_ud = dm2.get_unit(def_army2.units[0].unit_data_id) if def_army2.units.size() > 0 else null
			var weak_ud = dm2.get_unit(atk_army2.units[0].unit_data_id) if atk_army2.units.size() > 0 else null
			if strong_ud:
				atk_army2.units = atk_army2.units.slice(0, 1)
				while atk_army2.units.size() < 6:
					var ai := UnitInstance.new()
					ai.init_from_data(strong_ud, gm2.state.generate_id())
					atk_army2.units.append(ai)
			if weak_ud:
				def_army2.units = def_army2.units.slice(0, 1)
			var br: Node = root.get_node("/root/BattleResolver")
			br.auto_resolve(_atk_id, _def_id, _hex)
		else:
			print("ARMIES MISSING FOR AUTO-RESOLVE PASS")

	if _frames == 80:
		_shot("battle_report_auto.png")
		var rep: Control = _campaign.get("_battle_report_panel")
		if rep:
			_crop("battle_report_auto_closeup.png", rep.get_global_rect(), 6.0)
			_report_scrollbars(rep, "AUTO-REPORT")
			rep.queue_free()
			_campaign.set("_battle_report_panel", null)
		else:
			print("NO BATTLE REPORT PANEL (report may have been empty -- player not involved?)")

	# ── Synthetic winner report (deterministic, bypasses sim RNG) --
	# the real auto_resolve() pass above kept landing on STALEMATE, which
	# never populates spoils -- construct a report dict matching
	# BattleResolver.auto_resolve()'s exact shape with loot/captives > 0 to
	# directly verify the icon-based spoils row renders.
	if _frames == 95:
		var synthetic := {
			"atk_faction": &"empire",
			"def_faction": &"skulloath",
			"atk_snapshot": [
				{"name": "Merchant Crossbow", "hp_before": 4400, "max_hp": 4400},
				{"name": "Levy Conscripts", "hp_before": 7920, "max_hp": 7920},
			],
			"def_snapshot": [
				{"name": "Bone Legion", "hp_before": 5000, "max_hp": 5000},
			],
			"atk_hp_after": {0: 3800, 1: 6200},
			"def_hp_after": {},
			"atk_alive": true,
			"def_alive": false,
			"captives": 3,
			"loot_gold": 240,
			"loot_iron": 60,
		}
		_campaign.call("_show_battle_report", synthetic)

	if _frames == 110:
		_shot("battle_report_spoils.png")
		var rep2: Control = _campaign.get("_battle_report_panel")
		if rep2:
			_crop("battle_report_spoils_closeup.png", rep2.get_global_rect(), 6.0)
			_report_scrollbars(rep2, "SPOILS-REPORT")
		quit()

	return false
