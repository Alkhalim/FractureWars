extends SceneTree
## UI Polish Wave 2 Task W3 — windowed verification (Empire chrome):
##  1. City panel building-card grid at the new "roomy" font tier (+ ornate
##     Upgrade/Found Settlement buttons, now taller to clear the squiggle).
##  2. Two standalone demo building cards (simple vs. a hand-picked complex
##     building) added directly to the HUD, proving the auto-step-down font
##     tier logic independent of whatever the player's real tech/city-level
##     state happens to have unlocked.
##  3. Loyalty panel (now dark-chip-backed).
##  4. Event dialog (dark-chip padding fix).
##  5. Elderbeast panel under EMPIRE chrome (an AI shardhorde beast; demo=false
##     spawns all factions incl. shardhorde's elderbeasts regardless of the
##     player's own faction, per game_manager.gd's new_game()).
## Modeled on tests/tmp_screenshot_w2fix_recruit.gd's frame-counted _process
## + logical-to-image-pixel scale-corrected crop pattern. Delete after use.
## Run:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w3_empire.gd

const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _capital_id: StringName = &""
var _demo_cards_holder: Control = null
var _demo_card1: Control = null
var _demo_card2: Control = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	gm.state.faction_intro_shown = true
	gm.state.tutorial_enabled = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String, img: Image = null) -> void:
	var use_img := img
	if use_img == null:
		use_img = root.get_viewport().get_texture().get_image()
	var user_path := "user://" + name
	use_img.save_png(user_path)
	var dst := SCRATCH_DIR + "/" + name
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(user_path), dst)
	print("SCREENSHOT SAVED: %s (copy to scratchpad: %s)" % [ProjectSettings.globalize_path(user_path), "ok" if err == OK else "FAILED %d" % err])

func _scale() -> Vector2:
	var full_img := root.get_viewport().get_texture().get_image()
	var vp_size: Vector2 = root.get_viewport().get_visible_rect().size
	return Vector2(full_img.get_width() / vp_size.x, full_img.get_height() / vp_size.y)

func _crop(full_img: Image, gr: Rect2, scale: Vector2, pad: float = 10.0) -> Image:
	var grown := gr.grow(pad)
	var rect := Rect2i(Vector2i(grown.position * scale), Vector2i(grown.size * scale))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, full_img.get_size()))
	return full_img.get_region(rect)

func _find_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found := _find_grid(child)
		if found:
			return found
	return null

func _find_ornate_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button and (node as Button).theme_type_variation == &"OrnateButton":
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_ornate_buttons(child))
	return out

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 10:
		_hud = _campaign.get_node("UILayer/HUD")
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		for cid in gm.state.cities:
			var c = gm.state.cities[cid]
			if c.faction_id == pid and c.is_capital:
				_capital_id = cid
				c.can_found_settlement = true  # display-only grant so found_btn renders
				break
		if _capital_id != &"":
			_hud.call("_show_city_panel", _capital_id)

		# Standalone demo cards: scan every building for the tier
		# _pick_building_card_font_tier resolves it to (name font size 16/13/11
		# identifies tier 0/1/2), independent of the player's real tech state.
		var dm: Node = root.get_node("/root/DataManager")
		var simple_building = null
		var complex_building = null
		var complex_tier_name := 16
		for bid in dm.buildings:
			var b = dm.buildings[bid]
			var upkeep = gm.city_system.get_building_upkeep(b)
			var effects = _hud.call("_get_building_effects_summary", b, true)
			var cost_bb = _hud.call("_format_cost_bbcode", b.build_cost, null)
			var tier = _hud.call("_pick_building_card_font_tier", b, upkeep, effects, cost_bb)
			if int(tier.name) == 16 and simple_building == null:
				simple_building = b
			if int(tier.name) < complex_tier_name or (int(tier.name) <= complex_tier_name and complex_building == null):
				if int(tier.name) < 16:
					complex_tier_name = int(tier.name)
					complex_building = b
		print("W3 CARD TIER SCAN: simple=%s complex=%s (tier name-size=%d)" % [
			(simple_building.id if simple_building else "NONE"),
			(complex_building.id if complex_building else "NONE"), complex_tier_name])

		_demo_cards_holder = Control.new()
		_demo_cards_holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_demo_cards_holder.position = Vector2(20, 700)
		_hud.add_child(_demo_cards_holder)
		var fs = gm.state.faction_states.get(pid)
		if simple_building:
			_demo_card1 = _hud.call("_create_building_card", simple_building, &"", fs, false)
			_demo_card1.position = Vector2(0, 0)
			_demo_cards_holder.add_child(_demo_card1)
		if complex_building:
			_demo_card2 = _hud.call("_create_building_card", complex_building, &"", fs, false)
			_demo_card2.position = Vector2(190, 0)
			_demo_cards_holder.add_child(_demo_card2)

	if _frames == 30:
		var full_img := root.get_viewport().get_texture().get_image()
		var scale := _scale()
		_shot("w3_empire_city_full.png")
		var grid := _find_grid(_hud.get("city_panel"))
		if grid:
			_shot("w3_empire_city_cards.png", _crop(full_img, grid.get_global_rect(), scale, 12.0))
		else:
			print("WARNING: no GridContainer (building cards) found under city_panel")
		var ornate := _find_ornate_buttons(_hud.get("city_panel"))
		if ornate.size() > 0:
			var u: Rect2 = ornate[0].get_global_rect()
			for b in ornate:
				u = u.merge(b.get_global_rect())
			_shot("w3_empire_ornate_buttons.png", _crop(full_img, u, scale, 14.0))
		else:
			print("WARNING: no OrnateButton found under city_panel")
		if _demo_card1 or _demo_card2:
			# Union of the individual card rects, not the holder Control's own
			# rect — a plain Control (not a Container) doesn't grow its own
			# `size` to fit children just because they're positioned inside
			# it, so get_global_rect() on the holder itself stayed (0,0)-sized.
			var u: Rect2
			if _demo_card1:
				u = _demo_card1.get_global_rect()
			else:
				u = _demo_card2.get_global_rect()
			if _demo_card1 and _demo_card2:
				u = u.merge(_demo_card2.get_global_rect())
			_shot("w3_empire_card_tiers_demo.png", _crop(full_img, u, scale, 10.0))

	if _frames == 40:
		var city_panel: Control = _hud.get("city_panel")
		if city_panel:
			city_panel.visible = false
		if _demo_cards_holder:
			_demo_cards_holder.visible = false
		if _capital_id != &"":
			_hud.call("_show_loyalty_panel", _capital_id)

	if _frames == 55:
		var full_img := root.get_viewport().get_texture().get_image()
		var scale := _scale()
		var lp: Control = _hud.get("_loyalty_panel")
		if lp:
			_shot("w3_empire_loyalty.png", _crop(full_img, lp.get_global_rect(), scale, 10.0))
		else:
			print("WARNING: _loyalty_panel not found")
		_hud.call("_on_loyalty_panel_close")
		_hud.call("_show_event_dialog", {
			"title": "The Merchant's Gambit",
			"text": "A traveling merchant offers a suspiciously good trade deal, claiming the goods are surplus from a disbanded caravan. Your advisors are divided on whether to trust the offer or investigate further before committing any coin.",
			"choice_a": "Accept the trade",
			"choice_b": "Decline and investigate",
		})

	if _frames == 70:
		var full_img := root.get_viewport().get_texture().get_image()
		var scale := _scale()
		var ed: Control = _hud.get("_event_dialog")
		if ed:
			_shot("w3_empire_event_dialog.png", _crop(full_img, ed.get_global_rect(), scale, 10.0))
		else:
			print("WARNING: _event_dialog not found")
		var edv = _hud.get("_event_dialog")
		if edv:
			edv.queue_free()

		var gm: Node = root.get_node("/root/GameManager")
		var beast_found = null
		for bid in gm.state.elderbeasts:
			var beast = gm.state.elderbeasts[bid]
			if beast.faction_id == &"shardhorde":
				beast_found = beast
				break
		if beast_found:
			if not beast_found.buildings.has(&"crystal_nursery"):
				beast_found.buildings.append(&"crystal_nursery")
			_hud.call("_show_elderbeast_panel", beast_found)
		else:
			print("WARNING: no shardhorde elderbeast found under empire game")

	if _frames == 85:
		var full_img := root.get_viewport().get_texture().get_image()
		var scale := _scale()
		var eb: Control = _hud.get("_elderbeast_panel")
		if eb:
			_shot("w3_empire_elderbeast.png", _crop(full_img, eb.get_global_rect(), scale, 10.0))
		else:
			print("WARNING: _elderbeast_panel not found (empire chrome)")
		quit()
	return false
