extends SceneTree
## UIPalette + generated-theme test (UI Overhaul #40, Task 3). Headless:
## UIPalette and GameManager._build_theme_for_set are pure GDScript/Theme
## logic with no scene-tree dependency, so they compile and run headless
## even though the scene scripts that CONSUME the theme (campaign_hud.gd
## etc.) don't.
var _fails := 0
func _init() -> void: call_deferred("_run")
func _check(c: bool, l: String) -> void:
	if not c: _fails += 1; print("FAIL: " + l)
func _run() -> void:
	# 1. Palette rebuild swaps heraldry-derived colors
	UIPalette.rebuild(&"neutral")
	var neutral_fill: Color = UIPalette.BAR_FILL
	UIPalette.rebuild(&"skulloath")
	_check(UIPalette.BAR_FILL != neutral_fill, "BAR_FILL faction-dependent")
	_check(UIPalette.INK_BODY.v < 0.4, "ink stays dark (readability)")
	_check(UIPalette.CHIP_BG.a < 1.0 and UIPalette.CHIP_BG.v < 0.2, "chip bg dark translucent per style guide")
	# Task 5b round 2: SECONDARY/ACCENT are new 3-color-presence fields —
	# assert they're genuinely distinct from heraldry (PARCHMENT_ACCENT),
	# not just present, for the faction still active (skulloath).
	_check(UIPalette.SECONDARY != UIPalette.PARCHMENT_ACCENT, "SECONDARY differs from heraldry")
	_check(UIPalette.ACCENT != UIPalette.PARCHMENT_ACCENT, "ACCENT differs from heraldry")
	_check(UIPalette.SECONDARY != UIPalette.ACCENT, "SECONDARY differs from ACCENT")
	# 2. heraldry() works cross-faction without rebuild
	_check(UIPalette.heraldry(&"empire") != UIPalette.heraldry(&"skulloath"), "heraldry per faction")
	# 3. Theme builder produces textured styleboxes when PNGs exist, flat fallback otherwise
	var gm = root.get_node("/root/GameManager")
	var t: Theme = gm._build_theme_for_set(&"neutral")
	_check(t.get_stylebox("normal", "Button") is StyleBoxTexture, "neutral button textured")
	_check(t.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "neutral frame textured")
	var t2: Theme = gm._build_theme_for_set(&"nonexistent_faction")
	_check(t2.get_stylebox("normal", "Button") != null, "fallback still yields a stylebox")
	_check(t.get_stylebox("fill", "ProgressBar") != null, "ProgressBar themed")
	_check(t.get_stylebox("separator", "HSeparator") != null, "HSeparator themed")
	_check(t.get_stylebox("slider", "HSlider") != null, "HSlider themed")
	_check(t.get_stylebox("panel", "TooltipPanel") != null, "tooltip themed")
	# 4. apply_faction_theme — live faction chrome switching (Task 4)
	_run_faction_theme_test(gm)
	# 5. UI Polish Wave 2 Task W2 — CLASS_COLORS must hold no exact-value
	# collision with campaign_hud.gd's _get_building_category_color rows
	# (brief: "those colors should not have 1:1 overlap with the building
	# button frames"). Building colors duplicated here (not loaded live —
	# campaign_hud.gd is a scene script, loading it cold in a -s test needs
	# the gm.new_game() warm-up dance documented in the harness gotchas;
	# not worth it for 6 literal Color values) — mirrors the RGB literals at
	# campaign_hud.gd's _get_building_category_color, alpha dropped since
	# CLASS_COLORS' frame strokes and the building cards' fill washes are
	# never compared at matching alpha anyway. Keep in sync with that
	# function if its colors ever change.
	var building_category_colors := [
		Color(0.85, 0.72, 0.3), Color(0.35, 0.7, 0.3), Color(0.75, 0.25, 0.2),
		Color(0.35, 0.55, 0.75), Color(0.55, 0.35, 0.75), Color(0.4, 0.4, 0.4),
	]
	for cls in UIPalette.CLASS_COLORS:
		var cc: Color = UIPalette.CLASS_COLORS[cls]
		for bc in building_category_colors:
			var collides: bool = is_equal_approx(cc.r, bc.r) and is_equal_approx(cc.g, bc.g) and is_equal_approx(cc.b, bc.b)
			_check(not collides, "CLASS_COLORS[%s] (%s) doesn't 1:1-collide with a building category color (%s)" % [cls, cc, bc])
	print("UI PALETTE TEST %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _run_faction_theme_test(gm) -> void:
	gm.new_game(&"skulloath", false, 0)
	_check(gm.chrome_set_id == &"skulloath", "new_game applies faction chrome (got %s)" % gm.chrome_set_id)
	var btn_style = root.theme.get_stylebox("normal", "Button") if root.theme else null
	_check(btn_style is StyleBoxTexture and (btn_style.texture.resource_path.contains("skulloath")), "root theme uses skulloath textures")
	gm.apply_faction_theme(&"nonexistent")
	_check(gm.chrome_set_id == &"nonexistent", "set id tracked even on fallback")
	_check(root.theme.get_stylebox("normal", "Button") != null, "fallback theme still valid")
	gm.apply_faction_theme(&"neutral")
