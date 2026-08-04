extends SceneTree
## Temp tool: UI Polish Wave Task P5 verification -- diplomacy contrast +
## opaque relationship list, fitted event/dilemma dialog buttons, opaque
## commander skill-preview tooltip, margin sweep (victory/event/report
## dialogs), and the SHARDHORDE elderbeast readability audit (elderbeast
## panel under empire vs shardhorde chrome -- make_panel_style() bakes the
## active faction's palette into the frame texture, so this is genuinely
## chrome-dependent).
##
## Faction selectable via trailing cmdline arg (`-- empire` / `-- shardhorde`,
## default empire), matching the P1/P3/P4 tmp_screenshot_*.gd convention.
## Elderbeasts spawn unconditionally in every new_game() (GameManager.
## _init_elderbeasts reads DataManager's shardhorde FactionData, not the
## player's chosen faction), so both passes can open the same panel under
## their own chrome. The empire pass additionally exercises everything else
## in this task (diplomacy/event/dilemma/skill-tooltip/victory/turn-summary)
## since those aren't faction-chrome-sensitive in the same way the elderbeast
## panel is.
## Run WITHOUT --headless. Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction_id := &"empire"

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
	var fname := "p5_%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

## Crops the CURRENT frame (call right after a full-window _shot of the same
## frame) to `rect` (Control-logical/get_global_rect() coordinates) + `pad`
## logical px, scaled into the saved PNG's actual pixel space (DPI scaling
## can make these differ -- see tmp_screenshot_techtree.gd's note).
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
	var fname := "p5_%s_%s" % [String(_faction_id), name]
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r, " px_scale=", px_scale)

func _open_elderbeast() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	var beasts: Dictionary = gm.state.elderbeasts
	if beasts.is_empty():
		print("NO ELDERBEASTS FOUND (unexpected -- _init_elderbeasts should always spawn 2)")
		return
	var beast = beasts.values()[0]
	print("Opening elderbeast panel for: ", beast.name, " (faction chrome: ", _faction_id, ")")
	_hud.call("_show_elderbeast_panel", beast)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _hud == null and _campaign.has_node("UILayer/HUD"):
		_hud = _campaign.get_node("UILayer/HUD")
	if _hud == null:
		return false

	if _faction_id == &"empire":
		_full_pass()
	else:
		_elderbeast_only_pass()

	return false

func _elderbeast_only_pass() -> void:
	if _frames == 30:
		_open_elderbeast()
	if _frames == 50:
		_shot("elderbeast_panel.png")
		var panel: Control = _hud.get("_elderbeast_panel")
		if panel:
			_crop("elderbeast_closeup.png", panel.get_global_rect(), 4.0)
		quit()

func _full_pass() -> void:
	# ── Diplomacy: relationship list opacity + faction-name contrast ──
	if _frames == 20:
		var gm: Node = root.get_node("/root/GameManager")
		gm.state.encountered_factions[&"skulloath"] = true
		gm.state.encountered_factions[&"gladehost"] = true
		gm.state.encountered_factions[&"moonspear"] = true
		_hud.set("_diplo_detail_faction", &"")
		_hud.call("_refresh_diplomacy_panel")
		var panel: Control = _hud.get("_diplomacy_panel")
		panel.visible = true
	if _frames == 35:
		_shot("diplomacy_list.png")
		var vbox: Control = _hud.get_node_or_null("DiplomacyPanel/Columns/Scroll/DiplomacyVBox")
		if vbox:
			for child in vbox.get_children():
				if child is PanelContainer:
					_crop("diplomacy_row_closeup.png", child.get_global_rect(), 6.0)
					break
		var panel: Control = _hud.get("_diplomacy_panel")
		panel.visible = false

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
			dlg.queue_free()
			_hud.set("_event_dialog", null)

	# ── Faction dilemma dialog: same fitted-button factory ──
	if _frames == 60:
		var gm2: Node = root.get_node("/root/GameManager")
		var player_id: StringName = gm2.state.player_faction_id
		_hud.call("_show_faction_dilemma_dialog", player_id, &"p5_test_dilemma", {
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
			dlg.queue_free()
			_hud.set("_faction_dilemma_dialog", null)

	# ── Victory dialog: oversized-margin sweep target #1 ──
	if _frames == 80:
		_hud.call("_show_victory_panel")
	if _frames == 95:
		_shot("victory_dialog.png")
		var dlg: Control = _hud.get("_victory_dialog")
		if dlg:
			_crop("victory_dialog_closeup.png", dlg.get_global_rect(), 6.0)
			dlg.queue_free()
			_hud.set("_victory_dialog", null)

	# ── Turn summary ("report") dialog: oversized-margin sweep target #2 --
	# populate a few synthetic log entries first so the box isn't judged
	# empty (a real end-of-turn report usually has 2-5 lines) ──
	if _frames == 100:
		var tm: Node = root.get_node("/root/TurnManager")
		tm.turn_log.append({type = "battle", text = "Your army won a battle at (12, 7)"})
		tm.turn_log.append({type = "capture", text = "Your forces captured Ashford"})
		tm.turn_log.append({type = "treaty", text = "Empire and Gladehost formed a Peace Treaty"})
		_hud.call("_show_turn_summary")
	if _frames == 115:
		_shot("turn_summary_dialog.png")
		var dlg: Control = _hud.get("_turn_summary_panel")
		if dlg:
			_crop("turn_summary_dialog_closeup.png", dlg.get_global_rect(), 6.0)
			dlg.queue_free()
			_hud.set("_turn_summary_panel", null)

	# ── Commander skill-preview tooltip: opaque background ──
	if _frames == 120:
		var cs: Node = root.get_node("/root/CommanderSystem")
		var skill_ids: Array = cs.skills.keys()
		if skill_ids.size() > 0:
			Input.warp_mouse(Vector2(700, 450))
			_hud.call("_on_skill_hover_entered", skill_ids[0], 3)
		else:
			print("NO COMMANDER SKILLS FOUND")
	if _frames == 135:
		_shot("skill_tooltip.png")
		var tip: Control = _hud.get("_skill_tooltip")
		if tip and tip.visible:
			_crop("skill_tooltip_closeup.png", tip.get_global_rect(), 6.0)

	# ── Elderbeast panel under empire chrome (second faction run repeats
	# this alone under shardhorde chrome via _elderbeast_only_pass) ──
	if _frames == 140:
		_hud.call("_on_skill_hover_exited")
		_open_elderbeast()
	if _frames == 155:
		_shot("elderbeast_panel.png")
		var panel: Control = _hud.get("_elderbeast_panel")
		if panel:
			_crop("elderbeast_closeup.png", panel.get_global_rect(), 4.0)
		var eb: Control = _hud.get("_elderbeast_panel")
		if eb:
			eb.queue_free()

	# ── Supplementary check: diplomacy trade-offer CheckBox contrast fix
	# (same dark-CHIP_BG-on-Button-INK_BODY bug already fixed twice elsewhere
	# in this file per its own comments -- not one of the required P5 shots
	# but worth a self-critique look since it's touched in this task). The
	# offers checklist lives INLINE in the faction detail page (_diplo_tab
	# offers/demands columns), not the separate _on_diplomacy_open_trade
	# resource-dropdown dialog -- open the detail page itself. ──
	if _frames == 160:
		_hud.set("_diplo_detail_faction", &"gladehost")
		_hud.call("_refresh_diplomacy_panel")
		var panel: Control = _hud.get("_diplomacy_panel")
		panel.visible = true
	if _frames == 175:
		_shot("trade_offers.png")
		var panel2: Control = _hud.get("_diplomacy_panel")
		if panel2:
			_crop("trade_offers_closeup.png", panel2.get_global_rect(), 4.0)
		quit()
