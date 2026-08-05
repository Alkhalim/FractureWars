extends SceneTree
## UI Polish Wave 2 Task W3 — elderbeast panel under SHARDHORDE chrome (the
## palette explicitly called out by the designer as "worst" before this
## task's fix: warm/darker parchment made the old un-chipped light text read
## as "white on light grey"). Grants crystal_nursery for a populated recruit
## list, same display-only harness grant tmp_screenshot_w2_recruit.gd /
## tmp_screenshot_w2fix_recruit.gd used. Also confirms the "Available
## Buildings" section (now routed through _create_building_card) renders
## correctly if the beast's start terrain offers any matching building.
## Delete after use.
## Run:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w3_shardhorde.gd

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
				# Level 2 -> 2 building slots (LEVEL_STATS in elderbeast_state.gd)
				# so 1 filled + 1 free still exercises the "Available Buildings"
				# section (now routed through _create_building_card) — a level-1
				# beast's single slot would fill with crystal_nursery alone and
				# never reach that code path in this screenshot.
				beast.level = 2
				if not beast.buildings.has(&"crystal_nursery"):
					beast.buildings.append(&"crystal_nursery")
				_hud.call("_show_elderbeast_panel", beast)
				break

	if _frames == 55:
		_shot("w3_shardhorde_elderbeast_full.png")
		var full_img := root.get_viewport().get_texture().get_image()
		var vp_size: Vector2 = root.get_viewport().get_visible_rect().size
		var scale := Vector2(full_img.get_width() / vp_size.x, full_img.get_height() / vp_size.y)
		var panel: Control = _hud.get("_elderbeast_panel")
		if panel:
			var gr := panel.get_global_rect()
			var rect := Rect2i(Vector2i(gr.position * scale), Vector2i(gr.size * scale))
			rect = rect.intersection(Rect2i(Vector2i.ZERO, full_img.get_size()))
			_shot("w3_shardhorde_elderbeast_zoom.png", full_img.get_region(rect))
		else:
			print("WARNING: _elderbeast_panel not found (shardhorde chrome)")
		quit()
	return false
