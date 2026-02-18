extends Control

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
var continue_button: Button
var load_button: Button

# Faction selection
var _faction_select_panel: PanelContainer

func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game)
	quit_button.pressed.connect(_on_quit)

	# Add Continue button (auto-save slot 0)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.visible = GameManager.has_save(0)
	continue_button.pressed.connect(_on_continue)
	$VBoxContainer.add_child(continue_button)
	$VBoxContainer.move_child(continue_button, $VBoxContainer.get_children().find(new_game_button))

	# Add Load Game button
	load_button = Button.new()
	load_button.text = "Load Game"
	load_button.visible = _has_any_save()
	load_button.pressed.connect(_on_load_game)
	$VBoxContainer.add_child(load_button)
	$VBoxContainer.move_child(load_button, $VBoxContainer.get_children().find(new_game_button) + 1)

	AudioManager.play_music(&"music_menu")

func _has_any_save() -> bool:
	for i in range(0, 4):
		if GameManager.has_save(i):
			return true
	return false

func _on_new_game() -> void:
	AudioManager.play_sfx(&"ui_click")
	_show_faction_select()

func _on_continue() -> void:
	AudioManager.play_sfx(&"ui_click")
	GameManager.load_game(0)

func _on_load_game() -> void:
	_show_load_menu()

func _on_quit() -> void:
	get_tree().quit()

# ── Faction Selection ───────────────────────────────────────

func _show_faction_select() -> void:
	if _faction_select_panel:
		_faction_select_panel.queue_free()

	_faction_select_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.95)
	style.border_color = Color(0.55, 0.42, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	_faction_select_panel.add_theme_stylebox_override("panel", style)
	_faction_select_panel.anchors_preset = Control.PRESET_CENTER
	_faction_select_panel.size = Vector2(500, 450)
	_faction_select_panel.position = (get_viewport_rect().size - _faction_select_panel.size) / 2.0
	add_child(_faction_select_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_faction_select_panel.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE YOUR FACTION"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var factions: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"shardhorde"]
	var descriptions := {
		&"empire": "Balanced with strong constructs and defensive capabilities.",
		&"skulloath": "Aggressive raiders with high attack and fast units.",
		&"gladehost": "Defensive forest-dwellers with strong ranged units.",
		&"tainted_jade": "Quick serpent warriors focused on poison and magic.",
		&"shardhorde": "Nomadic crystal swarm using elderbeasts as mobile cities.",
	}

	for faction_id in factions:
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data == null:
			continue
		var btn := Button.new()
		btn.text = faction_data.display_name
		btn.tooltip_text = descriptions.get(faction_id, "")
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_faction_selected.bind(faction_id))
		vbox.add_child(btn)

	# Tutorial toggle
	var tutorial_cb := CheckBox.new()
	tutorial_cb.name = "TutorialCheck"
	tutorial_cb.text = "Enable Tutorial"
	tutorial_cb.button_pressed = true
	tutorial_cb.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tutorial_cb)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _faction_select_panel.queue_free())
	vbox.add_child(cancel_btn)

func _on_faction_selected(faction_id: StringName) -> void:
	var tutorial_on := true
	if _faction_select_panel:
		var cb := _faction_select_panel.get_node_or_null("VBoxContainer/TutorialCheck")
		if cb == null:
			# Try finding it in the direct vbox child
			for child in _faction_select_panel.get_children():
				if child is VBoxContainer:
					cb = child.get_node_or_null("TutorialCheck")
					break
		if cb and cb is CheckBox:
			tutorial_on = cb.button_pressed
		_faction_select_panel.queue_free()
	GameManager.new_game(faction_id)
	if GameManager.state:
		GameManager.state.tutorial_enabled = tutorial_on

# ── Load Menu ───────────────────────────────────────────────

func _show_load_menu() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.95)
	style.border_color = Color(0.55, 0.42, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.size = Vector2(400, 350)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "LOAD GAME"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var slot_names := ["Auto-Save", "Save Slot 1", "Save Slot 2", "Save Slot 3"]
	for i in range(0, 4):
		var btn := Button.new()
		btn.text = slot_names[i]
		btn.disabled = not GameManager.has_save(i)
		btn.custom_minimum_size = Vector2(0, 36)
		var slot := i
		btn.pressed.connect(func():
			panel.queue_free()
			GameManager.load_game(slot)
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): panel.queue_free())
	vbox.add_child(cancel)
