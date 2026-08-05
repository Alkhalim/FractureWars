extends SceneTree
## UI Polish Wave 2 Task W3 — second-faction contrast check (Skulloath chrome,
## dark/desaturated palette vs. Empire's lighter one): city panel building
## cards at the new roomy font tier + ornate Upgrade/Found Settlement buttons
## closeup (verifying the +32px height bump clears the squiggle border here
## too, not just under Empire's palette). Modeled on
## tests/tmp_screenshot_w3_empire.gd. Delete after use.
## Run:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w3_skulloath.gd

const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

var _frames := 0
var _campaign: Node = null
var _hud: Control = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false, 0)
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
				c.can_found_settlement = true  # display-only grant so found_btn renders
				_hud.call("_show_city_panel", cid)
				break

	if _frames == 30:
		var full_img := root.get_viewport().get_texture().get_image()
		var scale := _scale()
		_shot("w3_skulloath_city_full.png")
		var grid := _find_grid(_hud.get("city_panel"))
		if grid:
			_shot("w3_skulloath_city_cards.png", _crop(full_img, grid.get_global_rect(), scale, 12.0))
		var ornate := _find_ornate_buttons(_hud.get("city_panel"))
		if ornate.size() > 0:
			var u: Rect2 = ornate[0].get_global_rect()
			for b in ornate:
				u = u.merge(b.get_global_rect())
			_shot("w3_skulloath_ornate_buttons.png", _crop(full_img, u, scale, 14.0))
		else:
			print("WARNING: no OrnateButton found under skulloath city_panel")
		quit()
	return false
