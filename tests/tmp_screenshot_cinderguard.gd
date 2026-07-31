extends SceneTree
## Temp tool (Task 4 art-gate verification): loads a Cinderguard campaign and
## screenshots (a) the top bar with the new "Scrap: N" label, (b) the scrap
## label's hover tooltip forced visible, (c) the widened army panel open
## simultaneously with a city panel. Modeled on tmp_screenshot_campaign.gd
## (new_game + instantiate pattern) and tmp_screenshot_bounties.gd (multi-phase
## frame counter + faction_intro_shown suppression). Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Node = null
var _army_id: StringName = &""
var _city_id: StringName = &""

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"cinderguard", false, 0)
	gm._is_transitioning = false
	# Suppress the once-per-game faction onboarding dialog (would cover the
	# whole map on HUD _ready()) and the step-by-step tutorial hint overlay
	# (would pop up on army-select/city-view triggers exercised below) —
	# neither is under test here. Same suppression tmp_screenshot_bounties.gd
	# uses for the intro dialog; tutorial_enabled=false additionally silences
	# _check_tutorial()'s hint popups for this harness.
	gm.state.faction_intro_shown = true
	gm.state.tutorial_enabled = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)
	_hud = _campaign.get_node("UILayer/HUD")

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	# ── Phase 1: top bar with "Scrap: N" label ──────────────────────────
	if _frames == 40:
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		print("PLAYER FACTION: ", pid)
		var fs: FactionState = gm.state.faction_states.get(pid)
		print("SCRAP STOCKPILE: ", fs.scavenge_stockpile if fs else "null fs")
		_hud.call("_update_resource_display")
		var lbl: Label = _hud.get("scrap_label")
		print("SCRAP LABEL: visible=", lbl.visible if lbl else "null", " text=[", lbl.text if lbl else "", "]")

	if _frames == 42:
		_shot("win_scrap_bar.png")

	# ── Phase 2: scrap tooltip forced visible ───────────────────────────
	if _frames == 44:
		_hud.call("_on_scrap_label_hover")
		var tip: Node = _hud.get("_scrap_tooltip")
		if tip:
			print("SCRAP TOOLTIP: visible=", tip.visible, " text=[", tip.get_node("TooltipText").text, "]")
		else:
			print("WARNING: _scrap_tooltip is null after _on_scrap_label_hover")

	if _frames == 46:
		_shot("win_scrap_tooltip.png")

	# ── Phase 3: widened army panel open together with a city panel ────
	if _frames == 48:
		# Hide the phase-2 tooltip (no real mouse_exited fired) so it doesn't
		# linger over the phase-3 shot.
		var tip2: Node = _hud.get("_scrap_tooltip")
		if tip2:
			tip2.visible = false
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		for aid in gm.state.armies:
			var army: ArmyState = gm.state.armies[aid]
			if army.faction_id == pid and not army.units.is_empty():
				_army_id = aid
				break
		for cid in gm.state.cities:
			var city: CityState = gm.state.cities[cid]
			if city.faction_id == pid:
				_city_id = cid
				if city.is_capital:
					break
		print("ARMY FOR PANEL: ", _army_id, " CITY FOR PANEL: ", _city_id)
		if _city_id != &"":
			_hud.call("_show_city_panel", _city_id)
		if _army_id != &"":
			_hud.call("_on_army_selected", _army_id)
		var army_panel: Control = _hud.get("army_panel")
		var city_panel: Control = _hud.get("city_panel")
		if army_panel and city_panel:
			print("ARMY PANEL rect: ", army_panel.get_global_rect(), " visible=", army_panel.visible)
			print("CITY PANEL rect: ", city_panel.get_global_rect(), " visible=", city_panel.visible)

	# Art-gate follow-up: the first pass shot this at frame 50 (2 frames after
	# triggering both panels), which caught the 0.2s fade-in tween mid-flight —
	# both panels use `modulate:a` tweens on first-open. Give it ~1s (60
	# frames) more before re-shooting so the tween is long finished, and print
	# each panel's modulate.a right before capture as hard evidence either way.
	if _frames == 108:
		var army_panel2: Control = _hud.get("army_panel")
		var city_panel2: Control = _hud.get("city_panel")
		if army_panel2:
			print("ARMY PANEL modulate.a (frame 108): ", army_panel2.modulate.a)
		if city_panel2:
			print("CITY PANEL modulate.a (frame 108): ", city_panel2.modulate.a)
		_shot("win_army_panel_late.png")

	# ── Phase 4 (review-fix follow-up): small army — the army-panel width
	# fix (Finding 2) is specifically about 1-4 unit armies leaving a dead
	# band in the ~620px floor width, which the phase-3 army (5 units) does
	# not exercise. No 1-2 unit cinderguard army necessarily exists in a
	# fresh new_game, so build one directly the same way the test suite
	# builds detached armies (see tests/test_battle_determinism.gd,
	# tests/test_movement_cache_keys.gd: construct ArmyState/UnitInstance by
	# hand and register it in GameManager.state.armies — there is no
	# higher-level "create_army" API), reusing the phase-3 army's own
	# hex_pos so ArmyState.hex_pos stays a valid key for
	# GameManager.get_armies_at_tile() (used by the panel's Merge-button
	# check). Uses cinderguard_warden — CityState.FACTION_BASIC_UNITS[&"cinderguard"].
	if _frames == 110:
		var gm: Node = root.get_node("/root/GameManager")
		var base_army: ArmyState = gm.state.armies.get(_army_id)
		var small_army := ArmyState.new()
		small_army.army_id = &"__test_small_army__"
		small_army.faction_id = gm.state.player_faction_id
		small_army.hex_pos = base_army.hex_pos if base_army else Vector2i.ZERO
		var u1 := UnitInstance.new()
		u1.unit_data_id = &"cinderguard_warden"
		small_army.units.append(u1)
		gm.state.armies[small_army.army_id] = small_army
		_hud.call("_on_army_selected", small_army.army_id)
		var small_panel: Control = _hud.get("army_panel")
		if small_panel:
			print("SMALL ARMY PANEL rect (frame 110): ", small_panel.get_global_rect())

	if _frames == 114:
		var small_panel2: Control = _hud.get("army_panel")
		if small_panel2:
			print("SMALL ARMY PANEL rect (frame 114): ", small_panel2.get_global_rect())
		_shot("win_army_panel_small.png")
		quit()
	return false
