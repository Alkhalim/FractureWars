extends SceneTree
## Temp tool: UI Polish Wave Task P3 — city panel readability screenshots.
## Verifies 2-line recruit/upgrade/found buttons, calm (neutral-bg,
## colored-rim) building cards, and the fit-content income row. Faction
## selectable via trailing cmdline arg (`-- empire` / `-- skulloath`,
## default skulloath), matching the P1 tmp_screenshot_windows.gd convention.
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction_id := &"skulloath"
var _city_id := StringName()
var _shown := false

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_faction_id = StringName(args[0])
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(_faction_id, false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fname := "p3_%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

## Crops the CURRENT frame (call right after a full-window _shot of the same
## frame — don't let a frame pass in between, or content may have moved/faded)
## to `rect` (given in Control-logical/get_global_rect() coordinates) + `pad`
## logical px of margin, clamped to the viewport. `rect` is scaled from
## logical space into actual saved-image pixel space before cropping — on
## this machine the saved PNG comes out 1808x1017 for a "--resolution
## 1920x1080" window (Windows DPI scaling, ~0.94x), which does NOT match the
## Control-logical coordinates get_global_rect() reports; cropping with raw
## logical numbers silently drifted onto the wrong row/card for small crop
## windows (confirmed by diffing against a PIL crop of the raw PNG).
func _crop(name: String, rect: Rect2, pad: float = 10.0) -> void:
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
	var fname := "p3_%s_%s" % [String(_faction_id), name]
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r, " px_scale=", px_scale)

## Depth-first search for the first Button whose subtree contains a Label
## whose text begins with `needle` — make_cost_button never sets Button.text
## directly (the label is a child), so this is the only way to locate e.g.
## the "Upgrade to Level 2" / "Found Settlement" buttons from outside.
func _find_button_by_label_prefix(node: Node, needle: String) -> Button:
	if node is Button and _contains_label_prefix(node, needle):
		return node
	for child in node.get_children():
		var found := _find_button_by_label_prefix(child, needle)
		if found:
			return found
	return null

func _contains_label_prefix(node: Node, needle: String) -> bool:
	if node is Label and String(node.text).begins_with(needle):
		return true
	for child in node.get_children():
		if _contains_label_prefix(child, needle):
			return true
	return false

func _find_label_exact(node: Node, needle: String) -> Label:
	if node is Label and String(node.text) == needle:
		return node
	for child in node.get_children():
		var found := _find_label_exact(child, needle)
		if found:
			return found
	return null

func _find_first_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found := _find_first_grid(child)
		if found:
			return found
	return null

## Union of a GridContainer's children's own global rects — more reliable
## than the container's own get_global_rect() here (observed short by ~1
## row's worth of height on the first pass, likely a stale/pre-sort read on
## the container itself even several frames after content was built; the
## children's individually-reported rects were accurate).
func _grid_children_bounds(grid: GridContainer) -> Rect2:
	var result := Rect2()
	var first := true
	for child in grid.get_children():
		if child is Control:
			var r: Rect2 = (child as Control).get_global_rect()
			if first:
				result = r
				first = false
			else:
				result = result.merge(r)
	return result

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _hud == null and _campaign.has_node("UILayer/HUD"):
		_hud = _campaign.get_node("UILayer/HUD")
	if _hud == null:
		return false

	if _frames == 20:
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		for cid in gm.state.cities:
			if gm.state.cities[cid].faction_id == pid:
				_city_id = cid
				break
		if _city_id == StringName():
			print("NO PLAYER CITY FOUND")
			quit()
			return false
		# can_found_settlement is only granted by a completed city level-up
		# (city_system.gd _process_upgrade) — never true this early in a fresh
		# game — force it so the "Found Settlement" 2-line button is present
		# to screenshot. Resources are left at their natural starting values
		# (not boosted) so the shots show real affordable/unaffordable
		# contrast on both buttons and building cards, same as a real early
		# game would.
		var city = gm.state.cities[_city_id]
		city.can_found_settlement = true
		print("CITY: ", _city_id, "  FACTION: ", _faction_id)
		_hud.call("_show_city_panel", _city_id)
		_shown = true

	if _shown and _frames == 45:
		_shot("city_panel_full.png")
		var panel: Control = _hud.get("city_panel")
		var recruit_vbox: Control = _hud.get("_city_recruit_vbox")
		if panel:
			if recruit_vbox:
				_crop("crop_recruit_list.png", recruit_vbox.get_global_rect())
			else:
				print("recruit vbox not found")
			var upgrade_btn := _find_button_by_label_prefix(panel, "Upgrade to Level")
			if upgrade_btn:
				_crop("crop_upgrade_btn.png", upgrade_btn.get_global_rect())
			else:
				print("upgrade button not found (city may be max level)")
			var found_btn := _find_button_by_label_prefix(panel, "Found Settlement")
			if found_btn:
				_crop("crop_found_btn.png", found_btn.get_global_rect())
			else:
				print("found-settlement button not found")
			var grid := _find_first_grid(panel)
			if grid:
				_crop("crop_building_cards.png", _grid_children_bounds(grid))
				if grid.get_child_count() > 0:
					_crop("crop_building_card_single.png", (grid.get_child(0) as Control).get_global_rect())
			else:
				print("building grid not found (no available buildings?)")
			var income_lbl := _find_label_exact(panel, "Income:")
			if income_lbl:
				var income_row: Control = income_lbl.get_parent()
				_crop("crop_income_row.png", income_row.get_global_rect())
			else:
				print("income row not found (no positive income this turn?)")
		else:
			print("city_panel not found on hud")

	if _frames == 55:
		print("ALL DONE")
		quit()
	return false
