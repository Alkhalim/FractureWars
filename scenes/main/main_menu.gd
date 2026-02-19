extends Control

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
var continue_button: Button
var load_button: Button
var options_button: Button

# Faction selection
var _faction_select_panel: PanelContainer

func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game)
	quit_button.pressed.connect(_on_quit)

	# Add Continue button (auto-save slot 0)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(0, 96)
	continue_button.add_theme_font_size_override("font_size", 18)
	continue_button.visible = GameManager.has_save(0)
	continue_button.pressed.connect(_on_continue)
	$VBoxContainer.add_child(continue_button)
	$VBoxContainer.move_child(continue_button, $VBoxContainer.get_children().find(new_game_button))

	# Add Load Game button
	load_button = Button.new()
	load_button.text = "Load Game"
	load_button.custom_minimum_size = Vector2(0, 96)
	load_button.add_theme_font_size_override("font_size", 18)
	load_button.visible = _has_any_save()
	load_button.pressed.connect(_on_load_game)
	$VBoxContainer.add_child(load_button)
	$VBoxContainer.move_child(load_button, $VBoxContainer.get_children().find(new_game_button) + 1)

	# Add Options button (before Quit)
	options_button = Button.new()
	options_button.text = "Options"
	options_button.custom_minimum_size = Vector2(0, 96)
	options_button.add_theme_font_size_override("font_size", 18)
	options_button.pressed.connect(_on_options)
	$VBoxContainer.add_child(options_button)
	$VBoxContainer.move_child(options_button, $VBoxContainer.get_children().find(quit_button))

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

func _on_options() -> void:
	AudioManager.play_sfx(&"ui_click")
	AudioManager.create_options_panel(self)

func _on_quit() -> void:
	get_tree().quit()

# ── Faction Selection ───────────────────────────────────────

var _selected_faction_id: StringName = &""
var _faction_info_label: Label
var _faction_desc_label: Label
var _faction_traits_label: Label
var _faction_region_label: Label
var _faction_color_rect: ColorRect
var _faction_start_btn: Button
var _faction_buttons: Dictionary = {} # faction_id -> Button

const FACTION_DETAILS := {
	&"empire": {
		"traits": "Balanced army, strong constructs, defensive formations, arcane regulation",
		"playstyle": "Build a stable economy, field disciplined legions, and conquer through superior logistics. Your Marching Bastions and Dracarii Riders form the backbone of a formidable war machine.",
		"unique": "Senate system with political dilemmas, Forsaken corruption mechanic",
	},
	&"skulloath": {
		"traits": "Aggressive raiders, fast cavalry, bone magic, corruption-fueled power",
		"playstyle": "Strike hard and fast with mounted raiders and undead horrors. Corruption makes your armies stronger but alienates potential allies. Raid enemy lands for captives and resources.",
		"unique": "Corruption mechanic - higher corruption = stronger armies but worse diplomacy",
	},
	&"gladehost": {
		"traits": "Defensive forest-dwellers, strong ranged units, nature magic, harmony",
		"playstyle": "Defend your sacred groves with thornbow scouts and stag riders. Build harmony with nature to unlock powerful bonuses. Use diplomacy to forge alliances against aggressors.",
		"unique": "Harmony mechanic - maintain balance with nature for combat and diplomacy bonuses",
	},
	&"tainted_jade": {
		"traits": "Serpent warriors, jungle ambushers, taint magic, thrall armies",
		"playstyle": "Spread the Taint across the land, converting captives into thralls for your armies. Use jungle stalkers and vine golems to ambush enemies. Serpent guardians protect your sacred temples.",
		"unique": "Taint Power mechanic - spread corruption to weaken enemies and empower your forces",
	},
	&"shardhorde": {
		"traits": "Crystal swarm, elderbeasts as mobile cities, shard-powered evolution",
		"playstyle": "A unique nomadic faction with no cities. Your elderbeasts serve as mobile bases that recruit units and evolve with buildings. Consume crystal shards to fuel your horde's growth.",
		"unique": "Elderbeasts replace cities - mobile bases that move, fight, recruit, and evolve",
	},
}

func _show_faction_select() -> void:
	if _faction_select_panel:
		_faction_select_panel.queue_free()

	# Full-screen overlay
	_faction_select_panel = PanelContainer.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.12, 1.0)
	_faction_select_panel.add_theme_stylebox_override("panel", bg_style)
	_faction_select_panel.anchor_left = 0
	_faction_select_panel.anchor_top = 0
	_faction_select_panel.anchor_right = 1
	_faction_select_panel.anchor_bottom = 1
	add_child(_faction_select_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	_faction_select_panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(outer_vbox)

	# Title
	var title := Label.new()
	title.text = "CHOOSE YOUR FACTION"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	# Main content: faction list (left) + info panel (right)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(hbox)

	# Left side: faction list
	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	left_panel.custom_minimum_size = Vector2(320, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 16)
	left_margin.add_theme_constant_override("margin_right", 16)
	left_margin.add_theme_constant_override("margin_top", 16)
	left_margin.add_theme_constant_override("margin_bottom", 16)
	left_panel.add_child(left_margin)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_vbox)

	var list_title := Label.new()
	list_title.text = "FACTIONS"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_vbox.add_child(list_title)

	var factions: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"shardhorde"]
	_faction_buttons.clear()
	for faction_id in factions:
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data == null:
			continue
		var btn := Button.new()
		btn.text = faction_data.display_name
		btn.custom_minimum_size = Vector2(0, 96)
		btn.add_theme_font_size_override("font_size", 18)
		var captured_id := faction_id
		btn.pressed.connect(_on_faction_list_clicked.bind(captured_id))
		left_vbox.add_child(btn)
		_faction_buttons[faction_id] = btn

	# Spacer to push bottom controls down
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(spacer)

	# Tutorial toggle
	var tutorial_cb := CheckBox.new()
	tutorial_cb.name = "TutorialCheck"
	tutorial_cb.text = "Enable Tutorial"
	tutorial_cb.button_pressed = true
	tutorial_cb.add_theme_font_size_override("font_size", 13)
	tutorial_cb.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	left_vbox.add_child(tutorial_cb)

	# Right side: faction info panel
	var right_panel := PanelContainer.new()
	right_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 16)
	right_margin.add_theme_constant_override("margin_right", 16)
	right_margin.add_theme_constant_override("margin_top", 16)
	right_margin.add_theme_constant_override("margin_bottom", 16)
	right_panel.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	right_margin.add_child(right_vbox)

	# Faction color bar + name
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	right_vbox.add_child(header_hbox)

	_faction_color_rect = ColorRect.new()
	_faction_color_rect.custom_minimum_size = Vector2(8, 0)
	_faction_color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_faction_color_rect.color = Color(0.5, 0.5, 0.5, 0.5)
	header_hbox.add_child(_faction_color_rect)

	_faction_info_label = Label.new()
	_faction_info_label.text = "Select a faction"
	_faction_info_label.add_theme_font_size_override("font_size", 20)
	_faction_info_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	header_hbox.add_child(_faction_info_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	right_vbox.add_child(sep)

	# Description
	_faction_desc_label = Label.new()
	_faction_desc_label.text = "Choose a faction from the list to see details about their playstyle, unique mechanics, and starting position."
	_faction_desc_label.add_theme_font_size_override("font_size", 14)
	_faction_desc_label.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	_faction_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_faction_desc_label)

	# Traits
	_faction_traits_label = Label.new()
	_faction_traits_label.text = ""
	_faction_traits_label.add_theme_font_size_override("font_size", 13)
	_faction_traits_label.add_theme_color_override("font_color", Color(0.7, 0.82, 0.65))
	_faction_traits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_faction_traits_label)

	# Starting region
	_faction_region_label = Label.new()
	_faction_region_label.text = ""
	_faction_region_label.add_theme_font_size_override("font_size", 13)
	_faction_region_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.85))
	_faction_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_faction_region_label)

	# Spacer
	var info_spacer := Control.new()
	info_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(info_spacer)

	# Start button (disabled until faction selected)
	_faction_start_btn = Button.new()
	_faction_start_btn.text = "START GAME"
	_faction_start_btn.custom_minimum_size = Vector2(0, 96)
	_faction_start_btn.add_theme_font_size_override("font_size", 20)
	_faction_start_btn.disabled = true
	_faction_start_btn.pressed.connect(_on_faction_confirmed)
	right_vbox.add_child(_faction_start_btn)

	# Bottom bar: cancel button
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(bottom_hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Back to Main Menu"
	cancel_btn.custom_minimum_size = Vector2(240, 96)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(func(): _faction_select_panel.queue_free())
	bottom_hbox.add_child(cancel_btn)

func _on_faction_list_clicked(faction_id: StringName) -> void:
	_selected_faction_id = faction_id
	var faction_data: FactionData = DataManager.get_faction(faction_id)
	if faction_data == null:
		return

	AudioManager.play_sfx(&"ui_click")

	# Highlight selected button
	for fid in _faction_buttons:
		var btn: Button = _faction_buttons[fid]
		if fid == faction_id:
			btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
		else:
			btn.remove_theme_color_override("font_color")

	# Update info panel
	_faction_color_rect.color = faction_data.color
	_faction_info_label.text = faction_data.display_name

	var details: Dictionary = FACTION_DETAILS.get(faction_id, {})
	var desc_text := faction_data.description
	if details.has("playstyle"):
		desc_text += "\n\n" + details["playstyle"]
	_faction_desc_label.text = desc_text

	if details.has("traits"):
		_faction_traits_label.text = "Traits: " + details["traits"]
	if details.has("unique"):
		_faction_traits_label.text += "\n\nUnique: " + details["unique"]

	# Starting regions
	var region_names: Array[String] = []
	for region_id in faction_data.starting_regions:
		var region := DataManager.get_region(region_id)
		if region:
			region_names.append(region.display_name)
		else:
			region_names.append(str(region_id).capitalize())
	_faction_region_label.text = "Starting Region: " + ", ".join(region_names)

	_faction_start_btn.disabled = false
	_faction_start_btn.text = "START AS " + faction_data.display_name.to_upper()

func _on_faction_confirmed() -> void:
	if _selected_faction_id == &"":
		return
	var tutorial_on := true
	if _faction_select_panel:
		var cb: CheckBox = null
		# Find the tutorial checkbox
		var stack: Array[Node] = [_faction_select_panel]
		while stack.size() > 0:
			var node: Node = stack.pop_back()
			if node.name == "TutorialCheck" and node is CheckBox:
				cb = node
				break
			for child in node.get_children():
				stack.append(child)
		if cb:
			tutorial_on = cb.button_pressed
		_faction_select_panel.queue_free()
	GameManager.new_game(_selected_faction_id)
	if GameManager.state:
		GameManager.state.tutorial_enabled = tutorial_on

# ── Load Menu ───────────────────────────────────────────────

func _show_load_menu() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	panel.anchors_preset = Control.PRESET_CENTER
	panel.size = Vector2(450, 620)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "LOAD GAME"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var slot_names := ["Auto-Save", "Save Slot 1", "Save Slot 2", "Save Slot 3"]
	for i in range(0, 4):
		var btn := Button.new()
		btn.text = slot_names[i]
		btn.disabled = not GameManager.has_save(i)
		btn.custom_minimum_size = Vector2(0, 96)
		btn.add_theme_font_size_override("font_size", 18)
		var slot := i
		btn.pressed.connect(func():
			panel.queue_free()
			GameManager.load_game(slot)
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 96)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(func(): panel.queue_free())
	vbox.add_child(cancel)
