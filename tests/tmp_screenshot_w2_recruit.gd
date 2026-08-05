extends SceneTree
## UI Polish Wave 2 Task W2 — windowed verification: city recruit-list class
## icons/colors for one faction (arg 1, default skulloath) + the recruit-
## hover tooltip + a synthetic swatch of hand-picked units (guarantees a
## true-hybrid split-frame shot regardless of what a fresh turn-0 city has
## actually unlocked, since the hybrids in the real data — e.g. the
## shardhorde elderbeast — aren't always reachable that early). Delete after
## use. Modeled on tests/tmp_screenshot_campaign.gd's load/pan pattern.
## Run per faction:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w2_recruit.gd -- skulloath
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w2_recruit.gd -- forsaken
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w2_recruit.gd -- shardhorde

const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction: StringName = &"skulloath"

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_faction = StringName(args[0])
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(_faction, false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var user_path := "user://" + name
	img.save_png(user_path)
	var dst := SCRATCH_DIR + "/" + name
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(user_path), dst)
	print("SCREENSHOT SAVED: %s (copy to scratchpad: %s)" % [ProjectSettings.globalize_path(user_path), "ok" if err == OK else "FAILED %d" % err])

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	if _frames == 40:
		_hud = _campaign.get_node("UILayer/HUD")
		var gm: Node = root.get_node("/root/GameManager")
		var opened := false
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.faction_id == _faction:
				_hud.call("_show_city_panel", cid)
				opened = true
				break
		if not opened:
			# Nomadic/settlement-less faction (shardhorde: "no settlements —
			# your elderbeasts ARE your home") — recruit list lives in the
			# elderbeast panel instead of a city panel. A turn-1 elderbeast
			# has no buildings yet (nothing to recruit) — grant the tier-1
			# unit-unlocking building directly on the state object (display-
			# harness-only; not a saved/committed game action) so the
			# screenshot actually shows a populated, diverse recruit list
			# instead of "No units available".
			for bid in gm.state.elderbeasts:
				var beast = gm.state.elderbeasts[bid]
				if beast.faction_id == _faction:
					if not beast.buildings.has(&"crystal_nursery"):
						beast.buildings.append(&"crystal_nursery")
					_hud.call("_show_elderbeast_panel", beast)
					break

	if _frames == 50:
		_shot("w2_%s_recruit.png" % _faction)
		# Force-open the recruit hover tooltip (real usage is mouse_entered,
		# not reliably synthesizable headless-but-windowed without a real
		# cursor move — call the handler directly instead) for the first
		# recruitable unit, then pin it on-screen (it normally positions off
		# get_global_mouse_position(), which is untouched/near-origin here).
		var gm2: Node = root.get_node("/root/GameManager")
		var hover_done := false
		for cid in gm2.state.cities:
			var c = gm2.state.cities[cid]
			if c.faction_id == _faction:
				var recruitable: Array = _hud.call("_get_recruitable_units", c)
				if recruitable.size() > 0:
					_hud.call("_show_unit_card", recruitable[0])
					var panel = _hud.get("_unit_card_panel")
					if panel:
						panel.position = Vector2(460, 160)
					hover_done = true
				break
		if not hover_done:
			for bid in gm2.state.elderbeasts:
				var beast = gm2.state.elderbeasts[bid]
				if beast.faction_id == _faction:
					var dm: Node = root.get_node("/root/DataManager")
					var available_units: Array = []
					for b_id in beast.buildings:
						var b_data = dm.call("get_building", b_id)
						if b_data == null:
							continue
						for uid in b_data.unlocks_units:
							if not available_units.has(uid):
								available_units.append(uid)
					if available_units.size() > 0:
						_hud.call("_show_unit_card", available_units[0])
						var panel2 = _hud.get("_unit_card_panel")
						if panel2:
							panel2.position = Vector2(460, 160)
					break

	if _frames == 55:
		_shot("w2_%s_hover.png" % _faction)

	if _frames == 58:
		_build_swatch()

	if _frames == 65:
		_shot("w2_closeup_swatch.png")
		quit()
	return false

## Hand-picked units covering every single-class case AND both true-hybrid
## combos present in the real roster (beast+construct: the shardhorde
## elderbeast; mage+monster: forsaken's shadow_mage) — a controlled
## side-by-side for judging icon/frame legibility that doesn't depend on
## what a turn-0 city happens to have unlocked.
func _build_swatch() -> void:
	var dm: Node = root.get_node("/root/DataManager")
	var gm: Node = root.get_node("/root/GameManager")
	# crimson_shieldwall (pop 3) and cinder_drake (pop 0) are back-to-back
	# on purpose — same "Pop N" logic path, side by side, to visually
	# confirm the 0-pop suppression against a non-zero control case.
	var sample_ids: Array[StringName] = [
		&"crimson_shieldwall", &"cinder_drake", &"nightrider", &"sun_archer",
		&"war_ballista", &"elderbeast_lv1", &"shadow_mage",
	]
	var swatch := PanelContainer.new()
	swatch.position = Vector2(40, 420)
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	swatch_style.set_border_width_all(2)
	swatch_style.border_color = Color(0.6, 0.5, 0.3)
	swatch_style.set_content_margin_all(10)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	var svbox := VBoxContainer.new()
	svbox.add_theme_constant_override("separation", 6)
	swatch.add_child(svbox)
	var caption := Label.new()
	caption.text = "W2 verification swatch (not a real recruit list)"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	svbox.add_child(caption)
	for uid in sample_ids:
		var ud = dm.call("get_unit", uid)
		if ud == null:
			var missing := Label.new()
			missing.text = "MISSING: %s" % uid
			missing.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			svbox.add_child(missing)
			continue
		# Mirror the real recruit-button pop-text logic exactly (campaign_hud.gd
		# ~line 8701-8706) instead of always passing "" — this is the one
		# swatch row set (crimson_shieldwall/cinder_drake) that needs the
		# REAL branch to prove the 0-pop suppression, not just the icon/frame.
		var pop_cost: int = ud.population_cost if ud.population_cost >= 0 else ud.squad_size
		var pop_text := "" if pop_cost <= 0 else "Pop %d" % pop_cost
		var b = gm.call("make_cost_button", ud.display_name, ud.recruit_cost, ud.recruit_time, {}, 15, pop_text, true)
		b.custom_minimum_size.x = 280.0
		_hud.call("_apply_unit_class_decoration", b, ud)
		svbox.add_child(b)
	_hud.add_child(swatch)
