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
	# 5. UI Polish Wave 2 Task W2 (fix-round) — CLASS_COLORS must hold no
	# exact-value collision with the LIVE _get_building_category_color() in
	# campaign_hud.gd (brief: "those colors should not have 1:1 overlap with
	# the building button frames"). The original check compared against a
	# hand-copied literal Color list here, which stops protecting anything
	# the moment campaign_hud.gd's colors drift — this drives the real
	# function instead. campaign_hud.gd only compiles headless AFTER a
	# new_game() has warmed its autoload-dependent scripts (done above by
	# _run_faction_theme_test's gm.new_game() call) — same load-late +
	# instantiate pattern as test_building_percent_display.gd:26 (which
	# cites test_income_breakdown_equivalence.gd:111). Synthetic BuildingData
	# probes (not real DataManager buildings) so every category branch —
	# including the industrial/non-industrial economic split and the
	# unmatched-category default fallback, neither of which any real
	# buildings.tres reliably exercises — is hit deterministically.
	var hud = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()
	var probe_economic_industrial := BuildingData.new()
	probe_economic_industrial.category = &"economic"
	probe_economic_industrial.income_bonus = {Enums.ResourceType.IRON: 1}
	var probe_economic_plain := BuildingData.new()
	probe_economic_plain.category = &"economic"
	probe_economic_plain.income_bonus = {Enums.ResourceType.GOLD: 1}
	var probe_military := BuildingData.new()
	probe_military.category = &"military"
	var probe_defensive := BuildingData.new()
	probe_defensive.category = &"defensive"
	var probe_cultural := BuildingData.new()
	probe_cultural.category = &"cultural"
	var probe_default := BuildingData.new()
	probe_default.category = &"unrecognized_category"
	var building_category_colors: Array[Color] = []
	for probe in [probe_economic_industrial, probe_economic_plain, probe_military, probe_defensive, probe_cultural, probe_default]:
		building_category_colors.append(hud._get_building_category_color(probe))
	hud.free()
	_check(building_category_colors.size() == 6, "6 live building category colors collected, got %d" % building_category_colors.size())
	for cls in UIPalette.CLASS_COLORS:
		var cc: Color = UIPalette.CLASS_COLORS[cls]
		for bc in building_category_colors:
			var collides: bool = is_equal_approx(cc.r, bc.r) and is_equal_approx(cc.g, bc.g) and is_equal_approx(cc.b, bc.b)
			_check(not collides, "CLASS_COLORS[%s] (%s) doesn't 1:1-collide with a live building category color (%s)" % [cls, cc, bc])
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
