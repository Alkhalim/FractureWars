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
