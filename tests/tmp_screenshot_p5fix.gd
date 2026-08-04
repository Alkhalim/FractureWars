extends SceneTree
## Temp tool: UI Polish Wave Task P5 FIX-ROUND verification -- re-shoots just
## the event dialog and faction dilemma dialog (the two _add_dialog_choice_button
## call sites) after moving each dialog's add_child() into the HUD tree BEFORE
## the button-width measurement pass, so get_combined_minimum_size() resolves
## the game's real theme (Vollkorn @ Button size 15, get_tree().root.theme)
## instead of Godot's built-in default theme. Prints exact button widths
## (custom_minimum_size.x + final rect size.x) to console for numeric
## before/after comparison against the original p5_empire_event_dialog*.png /
## p5_empire_dilemma_dialog*.png screenshots (same frame timings as
## tmp_screenshot_p5.gd's event/dilemma section, reused verbatim so the shots
## are apples-to-apples). Run WITHOUT --headless. Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction_id := &"empire"

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(_faction_id, false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fname := "p5fix_%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

func _crop(name: String, rect: Rect2, pad: float = 8.0) -> void:
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
	var fname := "p5fix_%s_%s" % [String(_faction_id), name]
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r, " px_scale=", px_scale)

func _report_button_widths(dlg: Control, label: String) -> void:
	print("--- ", label, " button widths ---")
	print("  dialog.size = ", dlg.size)
	for child in dlg.get_children():
		_report_widths_recursive(child, 1)

func _report_widths_recursive(node: Node, depth: int) -> void:
	if node is Button:
		var b: Button = node
		print("  ", "  ".repeat(depth), "Button text='", b.text, "' custom_minimum_size.x=",
			b.custom_minimum_size.x, " actual size.x=", b.size.x,
			" theme_font=", b.get_theme_font("font"), " theme_font_size=", b.get_theme_font_size("font_size"))
	if node is Node:
		for child in node.get_children():
			_report_widths_recursive(child, depth + 1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _hud == null and _campaign.has_node("UILayer/HUD"):
		_hud = _campaign.get_node("UILayer/HUD")
	if _hud == null:
		return false

	# ── Event dialog: fitted, centered choice buttons ──
	if _frames == 40:
		_hud.call("_show_event_dialog", {
			title = "Border Raiders",
			text = "Scouts report a raiding party crossing the frontier. How do you respond?",
			choice_a = "Reinforce",
			choice_b = "Withdraw",
		})
	if _frames == 55:
		_shot("event_dialog.png")
		var dlg: Control = _hud.get("_event_dialog")
		if dlg:
			_crop("event_dialog_closeup.png", dlg.get_global_rect(), 6.0)
			_report_button_widths(dlg, "EVENT DIALOG")
			dlg.queue_free()
			_hud.set("_event_dialog", null)

	# ── Faction dilemma dialog: same fitted-button factory ──
	if _frames == 60:
		var gm2: Node = root.get_node("/root/GameManager")
		var player_id: StringName = gm2.state.player_faction_id
		_hud.call("_show_faction_dilemma_dialog", player_id, &"p5fix_test_dilemma", {
			title = "A Difficult Choice",
			description = "Advisors are split on how to allocate this season's surplus.",
			choices = [
				{label = "Invest", cost = {0: 20}, effect = "invest", description = "Spend gold now for a long-term yield."},
				{label = "Hoard", cost = {}, effect = "hoard", description = "Keep the surplus in reserve."},
			],
		})
	if _frames == 75:
		_shot("dilemma_dialog.png")
		var dlg: Control = _hud.get("_faction_dilemma_dialog")
		if dlg:
			_crop("dilemma_dialog_closeup.png", dlg.get_global_rect(), 6.0)
			_report_button_widths(dlg, "DILEMMA DIALOG")
			dlg.queue_free()
			_hud.set("_faction_dilemma_dialog", null)
		quit()

	return false
