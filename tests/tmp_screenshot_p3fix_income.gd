extends SceneTree
## Temp tool: UI Polish Wave Task P3 review-fix verification — confirms the
## city panel's "Income:" row (make_cost_row(..., wrap=true), an
## HFlowContainer) wraps instead of silently clipping when a developed
## capital posts 6+ income resource types (region base income + wood/shard
## buildings can combine to more than the 3-4 types the original P3 shots
## happened to exercise). Two shots:
##   1. the real natural income row (short — proves the fit-content/no-clip
##      look from the original P3 task is unaffected).
##   2. the SAME row rebuilt in-place with a harness-only synthetic 6-type
##      income dict (stubbed here, never in production code) to force the
##      overflow case and prove it wraps to a second line within the city
##      panel's fixed-width column instead of running off the edge.
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction_id := &"skulloath"
var _city_id := StringName()

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
	var fname := "p3fix_%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

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
	var fname := "p3fix_%s_%s" % [String(_faction_id), name]
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r)

func _find_label_exact(node: Node, needle: String) -> Label:
	if node is Label and String(node.text) == needle:
		return node
	for child in node.get_children():
		var found := _find_label_exact(child, needle)
		if found:
			return found
	return null

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
		print("CITY: ", _city_id, "  FACTION: ", _faction_id)
		_hud.call("_show_city_panel", _city_id)

	# Phase 1: natural income row (whatever the real city produces this turn
	# — proves the fit-content/short-row look from the original P3 task is
	# unaffected by the HFlowContainer swap).
	if _frames == 45:
		_shot("income_natural_full.png")
		var panel: Control = _hud.get("city_panel")
		var lbl := _find_label_exact(panel, "Income:")
		if lbl:
			var row: Control = lbl.get_parent()
			print("NATURAL INCOME ROW rect=", row.get_global_rect(), " children=", row.get_child_count())
			_crop("crop_income_natural.png", row.get_global_rect())
		else:
			print("natural income row not found")

	# Phase 2: harness-only synthetic 6-type income — rebuilds ONLY the
	# income row in place (same real column/ScrollContainer context) using
	# the actual production factory (GameManager.make_cost_row with
	# wrap=true), so this exercises the real wrap code path, just with a
	# stubbed cost dict standing in for a developed capital's real income.
	# This stub lives ONLY in this throwaway harness — nothing in
	# game_manager.gd or campaign_hud.gd is touched.
	if _frames == 70:
		var panel: Control = _hud.get("city_panel")
		var lbl := _find_label_exact(panel, "Income:")
		if lbl == null:
			print("income row not found for synthetic phase")
			quit()
			return false
		var old_row: Control = lbl.get_parent()
		var vbox: Node = old_row.get_parent()
		var idx := old_row.get_index()
		vbox.remove_child(old_row)
		old_row.queue_free()
		var gm: Node = root.get_node("/root/GameManager")
		# 6 resource types, matching the finding's "developed capital" example
		# (region base income + wood/shard-essence buildings): GOLD, IRON,
		# TECHNOLOGY, FOOD, SHARD_ESSENCE, WOOD (Enums.ResourceType 0,1,2,3,4,5).
		# 2-3 digit amounts on purpose — the first pass here used single/
		# low-double-digit values that happened to fit 346px on one line
		# without wrapping at all (a too-easy test that didn't actually
		# exercise the wrap path); wider digit counts reproduce the finding's
		# measured 358-371px overflow.
		var synthetic_income := {0: 142, 1: 87, 2: 39, 3: 123, 4: 26, 5: 94}
		var new_row: Control = gm.call("make_cost_row", synthetic_income, {}, 13, "Income:", true, 0, false, true)
		vbox.add_child(new_row)
		vbox.move_child(new_row, idx)
		print("SYNTHETIC 6-TYPE INCOME ROW INJECTED")

	if _frames == 95:
		_shot("income_synthetic6_full.png")
		var panel: Control = _hud.get("city_panel")
		var lbl := _find_label_exact(panel, "Income:")
		if lbl:
			var row: Control = lbl.get_parent()
			print("SYNTHETIC INCOME ROW rect=", row.get_global_rect(), " children=", row.get_child_count())
			_crop("crop_income_synthetic6.png", row.get_global_rect())
		else:
			print("synthetic income row not found")

	if _frames == 105:
		print("ALL DONE")
		quit()
	return false
