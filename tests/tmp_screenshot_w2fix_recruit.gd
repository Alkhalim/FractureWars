extends SceneTree
## UI Polish Wave 2 Task W2 fix-round — windowed re-shoot verifying the
## elderbeast recruit-row icon-sizing fix (recruit_btn.add_theme_constant_
## override("icon_max_width", 20) at campaign_hud.gd ~line 12686). Modeled on
## tests/tmp_screenshot_w2_recruit.gd's new_game/elderbeast-panel-open
## pattern, trimmed to shardhorde only, plus a crop derived from the live
## _elderbeast_panel Control's real global rect (not a hand-guessed pixel
## offset) so it stays correct regardless of resolution/layout. Delete after
## use.
## Run:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w2fix_recruit.gd

const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

var _frames := 0
var _campaign: Node = null
var _hud: Control = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"shardhorde", false, 0)
	gm._is_transitioning = false
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

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	if _frames == 40:
		_hud = _campaign.get_node("UILayer/HUD")
		var gm: Node = root.get_node("/root/GameManager")
		for bid in gm.state.elderbeasts:
			var beast = gm.state.elderbeasts[bid]
			if beast.faction_id == &"shardhorde":
				# Same display-harness-only building grant as the original W2
				# shoot (tmp_screenshot_w2_recruit.gd) — a turn-1 elderbeast has
				# no unit-unlocking building yet, so the recruit list would
				# otherwise be empty ("No units available").
				if not beast.buildings.has(&"crystal_nursery"):
					beast.buildings.append(&"crystal_nursery")
				_hud.call("_show_elderbeast_panel", beast)
				break

	if _frames == 50:
		_shot("w2fix_shardhorde_recruit.png")
		var full_img := root.get_viewport().get_texture().get_image()
		# get_global_rect() returns LOGICAL viewport coordinates, which on
		# this machine don't map 1:1 to the saved image's pixel size (e.g. a
		# 1920x1080 request saves as ~1808x1017 — some OS/window content-
		# scale factor). Scale rects into image-pixel space before cropping,
		# or the crop silently shifts right/down and clips the left column
		# (caught by comparing a first attempt's output against this math).
		var vp_size: Vector2 = root.get_viewport().get_visible_rect().size
		var scale := Vector2(full_img.get_width() / vp_size.x, full_img.get_height() / vp_size.y)
		var panel: Control = _hud.get("_elderbeast_panel")
		if panel:
			var gr := panel.get_global_rect()
			var rect := Rect2i(Vector2i(gr.position * scale), Vector2i(gr.size * scale))
			rect = rect.intersection(Rect2i(Vector2i.ZERO, full_img.get_size()))
			var cropped := full_img.get_region(rect)
			_shot("w2fix_shardhorde_recruit_zoom.png", cropped)

			# Tighter, 3x-upscaled close-up of JUST the recruit rows (the
			# icon-sizing bug's actual location) — bounding box of every icon-
			# bearing Button found under the panel (recruit_btn is the only
			# Button in this panel that sets .icon; build_btn does not),
			# matching the closeup-crop convention the original task used
			# (w2_swatch_crop_3x.png) rather than a hand-guessed pixel offset.
			var icon_btns := _find_icon_buttons(panel)
			if icon_btns.size() > 0:
				var union_rect: Rect2 = icon_btns[0].get_global_rect()
				for b in icon_btns:
					union_rect = union_rect.merge(b.get_global_rect())
				union_rect = union_rect.grow(10)
				var rows_rect := Rect2i(Vector2i(union_rect.position * scale), Vector2i(union_rect.size * scale))
				rows_rect = rows_rect.intersection(Rect2i(Vector2i.ZERO, full_img.get_size()))
				var rows_img := full_img.get_region(rows_rect)
				rows_img.resize(rows_img.get_width() * 3, rows_img.get_height() * 3, Image.INTERPOLATE_NEAREST)
				_shot("w2fix_shardhorde_recruit_rows_3x.png", rows_img)
			else:
				print("WARNING: no icon-bearing recruit Buttons found under _elderbeast_panel")
		else:
			print("WARNING: _elderbeast_panel not found for zoom crop")
		quit()
	return false

func _find_icon_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button and (node as Button).icon != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_icon_buttons(child))
	return out
