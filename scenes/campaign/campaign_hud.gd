extends Control

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]

# Colors for unit card portrait backgrounds by tag
const TAG_COLORS := {
	"infantry": Color(0.45, 0.25, 0.15),
	"cavalry": Color(0.35, 0.25, 0.4),
	"mage": Color(0.2, 0.18, 0.45),
	"ranged": Color(0.18, 0.35, 0.22),
	"melee": Color(0.5, 0.2, 0.15),
	"support": Color(0.25, 0.3, 0.45),
	"construct": Color(0.35, 0.32, 0.28),
	"fast": Color(0.4, 0.35, 0.15),
}

# Realm colors for unit card accents
const REALM_COLORS := {
	Enums.Realm.DIVINE: Color(0.95, 0.88, 0.45),
	Enums.Realm.VOID: Color(0.55, 0.3, 0.7),
	Enums.Realm.ELEMENTAL: Color(0.35, 0.65, 0.9),
	Enums.Realm.NATURE: Color(0.35, 0.7, 0.3),
	Enums.Realm.MORTAL: Color(0.7, 0.65, 0.55),
}

const RESEARCH_CATEGORY_COLORS := {
	&"military": Color(0.85, 0.35, 0.3),
	&"economy": Color(0.35, 0.8, 0.35),
	&"arcane": Color(0.65, 0.35, 0.85),
	&"logistics": Color(0.35, 0.6, 0.9),
}

const RESOURCE_NAMES := ["Gold", "Iron", "Technology", "Food", "Shards", "Wood", "Captives"]
const RESOURCE_COLORS := {
	0: Color(0.95, 0.85, 0.3), # Gold
	1: Color(0.6, 0.6, 0.65), # Iron
	2: Color(0.45, 0.55, 0.65), # Technology (steely blue-grey)
	3: Color(0.5, 0.8, 0.35), # Food
	4: Color(0.7, 0.3, 0.8), # Shard Essence
	5: Color(0.55, 0.40, 0.25), # Wood (warm brown)
	6: Color(0.65, 0.45, 0.35), # Captives (muted rust)
}

@onready var turn_label: Label = $TopBar/HBoxContainer/TurnLabel
@onready var date_label: Label = $TopBar/HBoxContainer/DateLabel
@onready var faction_label: Label = $TopBar/HBoxContainer/FactionLabel
@onready var end_turn_button: Button = $TopBar/HBoxContainer/EndTurnButton
@onready var region_panel: PanelContainer = $RegionPanel
@onready var army_panel: PanelContainer = $SelectedArmyPanel
var city_panel: PanelContainer
var resource_bar: HBoxContainer
var _resource_items: Dictionary = {} # resource_type -> {amount_label, income_label, container}
var _resource_tooltip: PanelContainer
var shard_label: Label
var shard_tooltip: PanelContainer
var _faction_mechanic_label: Label
var commander_panel: PanelContainer
var economy_panel: PanelContainer
var faction_overview_panel: PanelContainer
var _faction_detail_panel: PanelContainer
var _skill_tooltip: PanelContainer
var _building_tooltip: PanelContainer
var _level_up_dialog: PanelContainer
var _item_drop_dialog: PanelContainer
var _event_dialog: PanelContainer
var _region_overview_panel: PanelContainer
var _building_detail_panel: PanelContainer
var _unit_card_panel: PanelContainer
var _pending_level_up_commander: CommanderState
var _pending_event_data: Dictionary
var _loyalty_panel: PanelContainer
var _loyalty_panel_city_id: StringName = &""
var _class_hover_tooltip: PanelContainer
var _diplomacy_panel: PanelContainer
var _policies_panel: PanelContainer
var _forsaken_offer_dialog: PanelContainer
var _senate_dilemma_dialog: PanelContainer
var _senate_viz: Control
var _pending_forsaken_offer: Dictionary = {}
var _pending_building_city_id: StringName = &""
var _pending_building_id: StringName = &""
var _research_panel: PanelContainer
var _unit_detail_panel: PanelContainer
var _item_swap_panel: PanelContainer
var _turn_summary_panel: PanelContainer
var _tutorial_overlay: PanelContainer
var _advisor_toast: Label
var _hidden_army_panel: bool = false   # army panel was hidden by overlay
var _hidden_city_panel: bool = false   # city panel was hidden by overlay
var _skip_ai_btn: Button
var _speed_label: Label
var _army_overview_panel: PanelContainer
var _ai_offer_dialog: PanelContainer

func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn)

	EventBus.hex_tile_selected.connect(_on_hex_tile_selected)
	EventBus.hex_tile_deselected.connect(_on_hex_tile_deselected)
	EventBus.army_selected.connect(_on_army_selected)
	EventBus.army_deselected.connect(_on_army_deselected)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.army_moved.connect(_on_army_moved)
	EventBus.elderbeast_moved.connect(_on_elderbeast_moved)

	EventBus.commander_level_up.connect(_on_commander_level_up)
	EventBus.commander_item_full.connect(_on_commander_item_full)
	EventBus.commander_trait_changed.connect(_on_commander_trait_changed)
	EventBus.random_event_triggered.connect(_on_random_event_triggered)
	EventBus.shard_claimed.connect(_on_shard_claimed)
	EventBus.forsaken_offer.connect(_on_forsaken_offer_received)
	EventBus.senate_dilemma.connect(_on_senate_dilemma_received)
	EventBus.research_completed.connect(_on_research_completed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.siege_choice_needed.connect(_on_siege_choice_needed)
	EventBus.ai_diplomacy_offer.connect(_show_ai_diplomacy_offer)

	army_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	region_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	# Wire up army panel close button
	var army_close_btn: Button = army_panel.get_node("VBox/HeaderRow/CloseButton")
	army_close_btn.pressed.connect(func(): EventBus.army_deselected.emit())

	_create_resource_bar()
	_create_shard_display()
	_create_economy_panel()
	_create_city_panel()
	_create_commander_panel()
	_create_faction_overview_panel()
	_update_top_bar()

	# Make faction label clickable
	faction_label.mouse_filter = Control.MOUSE_FILTER_STOP
	faction_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	faction_label.gui_input.connect(_on_faction_label_input)

var _pause_panel: PanelContainer

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			GameManager.save_game(1)
			_show_save_toast("Game saved to Slot 1")
		elif event.keycode == KEY_F9:
			if GameManager.has_save(1):
				GameManager.load_game(1)
		elif event.keycode == KEY_ESCAPE:
			_toggle_pause_menu()

func _show_save_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchors_preset = Control.PRESET_CENTER_BOTTOM
	toast.position = Vector2(get_viewport_rect().size.x / 2.0 - 80, get_viewport_rect().size.y - 60)
	add_child(toast)
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast.queue_free)

func _toggle_pause_menu() -> void:
	if is_instance_valid(_pause_panel):
		_animate_panel_out(_pause_panel, "top")
		_pause_panel = null
		return

	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PauseMenu"
	_pause_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	_pause_panel.size = Vector2(300, 320)
	_pause_panel.position = (get_viewport_rect().size - _pause_panel.size) / 2.0
	add_child(_pause_panel)
	_animate_panel_in(_pause_panel, "top")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(0, 36)
	resume_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		_animate_panel_out(_pause_panel, "top")
		_pause_panel = null
	)
	vbox.add_child(resume_btn)

	var options_btn := Button.new()
	options_btn.text = "Options"
	options_btn.custom_minimum_size = Vector2(0, 36)
	options_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		AudioManager.create_options_panel(self)
	)
	vbox.add_child(options_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Game"
	save_btn.custom_minimum_size = Vector2(0, 36)
	save_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		GameManager.save_game(1)
		_show_save_toast("Game saved to Slot 1")
		_animate_panel_out(_pause_panel, "top")
		_pause_panel = null
	)
	vbox.add_child(save_btn)

	var main_menu_btn := Button.new()
	main_menu_btn.text = "Main Menu"
	main_menu_btn.custom_minimum_size = Vector2(0, 36)
	main_menu_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		AudioManager.stop_music()
		GameManager.transition_to_scene("res://scenes/main/main_menu.tscn")
	)
	vbox.add_child(main_menu_btn)

func _on_end_turn() -> void:
	if TurnManager.is_player_turn:
		EventBus.end_turn_pressed.emit()

func _update_top_bar() -> void:
	if GameManager.state == null:
		return
	turn_label.text = "Turn " + str(GameManager.state.current_turn)
	var month_name := DataManager.get_month_name(GameManager.state.current_month)
	date_label.text = month_name + ", " + str(GameManager.state.current_year) + " S.F."

	var faction_data := DataManager.get_faction(GameManager.state.player_faction_id)
	if faction_data:
		faction_label.text = faction_data.display_name
		faction_label.add_theme_color_override("font_color", faction_data.color.lightened(0.2))

	_update_resource_display()

func _on_hex_tile_selected(coord: Vector2i) -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		region_panel.visible = false
		return

	var tile := hex_map.get_tile(coord)
	if tile == null:
		region_panel.visible = false
		return

	region_panel.visible = true
	region_panel.move_to_front()
	region_panel.modulate = Color(1, 1, 1, 0)
	var _rp_tw := create_tween()
	_rp_tw.tween_property(region_panel, "modulate:a", 1.0, 0.2)

	var name_label: Label = region_panel.get_node("VBox/RegionName")
	var terrain_label: Label = region_panel.get_node("VBox/TerrainLabel")
	var realm_label: Label = region_panel.get_node("VBox/RealmLabel")
	var owner_label: Label = region_panel.get_node("VBox/OwnerLabel")
	var tile_info_label: Label = region_panel.get_node("VBox/TileInfoLabel")
	var armies_label: Label = region_panel.get_node("VBox/ArmiesLabel")

	var region := DataManager.get_region(tile.region_id)
	name_label.text = region.display_name if region else str(tile.region_id)

	var terrain_idx: int = tile.terrain
	terrain_label.text = "Terrain: " + (TERRAIN_NAMES[terrain_idx] if terrain_idx < TERRAIN_NAMES.size() else "Unknown")

	var realm_idx: int = tile.realm_influence
	realm_label.text = "Realm: " + (REALM_NAMES[realm_idx] if realm_idx < REALM_NAMES.size() else "Unknown")

	if tile.owner_faction == &"":
		owner_label.text = "Owner: Neutral"
	else:
		var faction := DataManager.get_faction(tile.owner_faction)
		owner_label.text = "Owner: " + (faction.display_name if faction else str(tile.owner_faction))

	var cost := hex_map.get_movement_cost(coord, GameManager.state.player_faction_id)
	var road_text := ""
	if tile.road_level == 2:
		road_text = " [Road]"
	elif tile.road_level == 1:
		road_text = " [Path]"
	var cost_text := "Impassable" if cost >= INF else "%.1f" % cost
	tile_info_label.text = "Tile: (%d, %d) | Cost: %s%s" % [coord.x, coord.y, cost_text, road_text]

	var armies := GameManager.get_armies_at_tile(coord)
	if armies.size() == 0:
		armies_label.text = "Armies: None"
	else:
		var army_texts: Array[String] = []
		for army in armies:
			var faction := DataManager.get_faction(army.faction_id)
			var fname := faction.display_name if faction else str(army.faction_id)
			army_texts.append(fname + " (" + str(army.units.size()) + " units)")
		armies_label.text = "Armies: " + ", ".join(army_texts)

func _on_hex_tile_deselected() -> void:
	region_panel.visible = false

func _on_army_selected(army_id: StringName) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null:
		army_panel.visible = false
		_hide_commander_panel()
		return

	_check_tutorial("army_selected")
	var already_shown := army_panel.visible and army_panel.modulate.a > 0.9
	army_panel.visible = true
	army_panel.move_to_front()
	if not already_shown:
		army_panel.modulate = Color(1, 1, 1, 0)
		var _ap_tw := create_tween()
		_ap_tw.tween_property(army_panel, "modulate:a", 1.0, 0.2)
	_update_commander_panel(army)

	var title: Label = army_panel.get_node("VBox/HeaderRow/ArmyTitle")
	var movement: Label = army_panel.get_node("VBox/HeaderRow/MovementLabel")
	var units_label: Label = army_panel.get_node("VBox/HeaderRow/UnitsLabel")
	var unit_list: GridContainer = army_panel.get_node("VBox/UnitScroll/UnitGrid")

	var faction := DataManager.get_faction(army.faction_id)
	title.text = (faction.display_name if faction else "Army") + " Army"
	var max_mp := army.get_max_movement()
	movement.text = "Movement: %.1f / %.1f" % [army.movement_remaining, max_mp]
	units_label.text = "Units (%d):" % army.units.size()

	# Add/update Split Army, Merge, and Disband buttons — remove any existing ones first (immediate free)
	var vbox_ref: VBoxContainer = army_panel.get_node("VBox")
	for child in vbox_ref.get_children():
		if child.name == &"SplitArmyButton" or child.name == &"DisbandUnitsButton" or child.name == &"MergeArmyButton":
			vbox_ref.remove_child(child)
			child.free()
	# Merge button — appears when another friendly army is on the same tile
	if army.faction_id == GameManager.state.player_faction_id:
		var armies_here := GameManager.get_armies_at_tile(army.hex_pos)
		var friendly_count := 0
		for a in armies_here:
			if a.faction_id == army.faction_id and not a.is_garrison:
				friendly_count += 1
		if friendly_count >= 2:
			var merge_btn := Button.new()
			merge_btn.name = "MergeArmyButton"
			merge_btn.text = "Merge Armies"
			merge_btn.custom_minimum_size = Vector2(0, 28)
			merge_btn.add_theme_font_size_override("font_size", 11)
			merge_btn.add_theme_color_override("font_color", Color(0.3, 0.75, 0.4))
			var merge_coord := army.hex_pos
			var merge_faction := army.faction_id
			var merge_army_id := army_id
			merge_btn.pressed.connect(func():
				AudioManager.play_sfx(&"ui_click")
				GameManager.merge_armies_at_tile(merge_coord, merge_faction, merge_army_id)
				EventBus.army_selected.emit(merge_army_id)
			)
			var vbox_m: VBoxContainer = army_panel.get_node("VBox")
			vbox_m.add_child(merge_btn)
			vbox_m.move_child(merge_btn, units_label.get_index() + 1)
	if army.faction_id == GameManager.state.player_faction_id and army.units.size() >= 2:
		var btn := Button.new()
		btn.name = "SplitArmyButton"
		btn.text = "Split Army"
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		var captured_id: StringName = army_id
		btn.pressed.connect(func(): _show_army_split_dialog(captured_id))
		var vbox: VBoxContainer = army_panel.get_node("VBox")
		vbox.add_child(btn)
		vbox.move_child(btn, units_label.get_index() + 1)
	if army.faction_id == GameManager.state.player_faction_id and army.units.size() >= 1:
		var disband_btn := Button.new()
		disband_btn.name = "DisbandUnitsButton"
		disband_btn.text = "Disband Units"
		disband_btn.custom_minimum_size = Vector2(0, 28)
		disband_btn.add_theme_font_size_override("font_size", 11)
		disband_btn.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
		var captured_disband_id: StringName = army_id
		disband_btn.pressed.connect(func(): _show_disband_dialog(captured_disband_id))
		var vbox2: VBoxContainer = army_panel.get_node("VBox")
		vbox2.add_child(disband_btn)

	# Clear old unit cards
	for child in unit_list.get_children():
		child.queue_free()

	# Create unit cards
	for unit in army.units:
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data:
			var card := _create_unit_card(unit, unit_data)
			unit_list.add_child(card)

func _create_unit_card(unit: UnitInstance, unit_data: UnitData) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.11, 0.15, 0.95)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.45, 0.35, 0.2, 0.7)
	card_style.corner_radius_top_left = 3
	card_style.corner_radius_top_right = 3
	card_style.corner_radius_bottom_right = 3
	card_style.corner_radius_bottom_left = 3
	card_style.content_margin_left = 6.0
	card_style.content_margin_top = 6.0
	card_style.content_margin_right = 6.0
	card_style.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", card_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# Portrait with actual unit image
	var portrait_container := PanelContainer.new()
	portrait_container.custom_minimum_size = Vector2(56, 70)
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.15, 0.13, 0.12)
	portrait_style.border_width_left = 1
	portrait_style.border_width_top = 1
	portrait_style.border_width_right = 1
	portrait_style.border_width_bottom = 1
	portrait_style.border_color = Color(0.55, 0.42, 0.2, 0.6)
	portrait_style.corner_radius_top_left = 2
	portrait_style.corner_radius_top_right = 2
	portrait_style.corner_radius_bottom_right = 2
	portrait_style.corner_radius_bottom_left = 2
	portrait_container.add_theme_stylebox_override("panel", portrait_style)

	var portrait_tex := DataManager.get_unit_portrait(unit_data.id)
	if portrait_tex:
		var portrait_rect := TextureRect.new()
		portrait_rect.texture = portrait_tex
		portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait_container.add_child(portrait_rect)
	else:
		# Fallback icon for units without portraits
		var icon_container := CenterContainer.new()
		portrait_container.add_child(icon_container)
		var icon_label := Label.new()
		icon_label.add_theme_font_size_override("font_size", 24)
		icon_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.8))
		if unit_data.tags.has("beast"):
			icon_label.text = "B"
		elif unit_data.tags.has("mage"):
			icon_label.text = "*"
		elif unit_data.tags.has("ranged"):
			icon_label.text = ">"
		elif unit_data.tags.has("cavalry"):
			icon_label.text = "^"
		elif unit_data.tags.has("construct"):
			icon_label.text = "#"
		else:
			icon_label.text = "+"
		icon_container.add_child(icon_label)
	hbox.add_child(portrait_container)

	# Stats panel
	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 2)
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Unit name + veterancy
	var name_label := Label.new()
	var vet_label := unit.get_veterancy_label()
	if unit.veterancy_level > 0:
		var vet_color: Color
		match unit.veterancy_level:
			1: vet_color = Color(0.6, 0.45, 0.25) # brown - Trained
			2: vet_color = Color(0.4, 0.55, 0.85) # blue - Veteran
			_: vet_color = Color(0.9, 0.75, 0.2)  # gold - Elite
		name_label.text = unit_data.display_name + " [" + vet_label + "]"
		name_label.add_theme_color_override("font_color", vet_color)
	else:
		name_label.text = unit_data.display_name
		name_label.add_theme_color_override("font_color", Color(0.92, 0.85, 0.55))
	name_label.add_theme_font_size_override("font_size", 13)
	stats_vbox.add_child(name_label)

	# HP bar using ProgressBar
	var hp_container := HBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 4)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(100, 10)
	hp_bar.max_value = unit_data.max_hp
	hp_bar.value = unit.current_hp
	hp_bar.show_percentage = false

	var hp_ratio := float(unit.current_hp) / float(unit_data.max_hp)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.2, 0.7, 0.25) if hp_ratio > 0.5 else (Color(0.85, 0.65, 0.15) if hp_ratio > 0.25 else Color(0.8, 0.2, 0.15))
	bar_style.corner_radius_top_left = 2
	bar_style.corner_radius_top_right = 2
	bar_style.corner_radius_bottom_right = 2
	bar_style.corner_radius_bottom_left = 2
	hp_bar.add_theme_stylebox_override("fill", bar_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.08, 0.08)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_right = 2
	bg_style.corner_radius_bottom_left = 2
	hp_bar.add_theme_stylebox_override("background", bg_style)
	hp_container.add_child(hp_bar)

	var hp_text := Label.new()
	hp_text.text = "%d/%d" % [unit.current_hp, unit_data.max_hp]
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	hp_container.add_child(hp_text)
	stats_vbox.add_child(hp_container)

	# Stat row: DPS / DEF / SPD / RNG (with veterancy bonuses)
	var stat_grid := HBoxContainer.new()
	stat_grid.add_theme_constant_override("separation", 6)

	var vet_bonus := unit.get_veterancy_bonus()
	var dps_val := estimate_unit_dps(unit_data)
	var vet_mult := 1.0 + vet_bonus
	var effective_spd := int(unit_data.speed * vet_mult)
	var atk_stars := get_attack_stars(unit_data)
	var def_stars := get_defense_stars(unit_data)
	var atk_star_text := render_stars(atk_stars)
	var def_star_text := render_stars(def_stars)
	if vet_bonus > 0.0:
		_add_stat_label(stat_grid, "ATK", "%s (+%d%%)" % [atk_star_text, int(vet_bonus * 100)], STAR_COLOR_ATTACK)
		_add_stat_label(stat_grid, "DEF", "%s (+%d%%)" % [def_star_text, int(vet_bonus * 100)], STAR_COLOR_DEFENSE)
		_add_stat_label(stat_grid, "SPD", "%d" % effective_spd, Color(0.5, 0.8, 0.45))
	else:
		_add_stat_label(stat_grid, "ATK", atk_star_text, STAR_COLOR_ATTACK)
		_add_stat_label(stat_grid, "DEF", def_star_text, STAR_COLOR_DEFENSE)
		_add_stat_label(stat_grid, "SPD", str(unit_data.speed), Color(0.5, 0.8, 0.45))
	if unit_data.attack_range > 1:
		_add_stat_label(stat_grid, "RNG", str(unit_data.attack_range), Color(0.8, 0.7, 0.4))

	stats_vbox.add_child(stat_grid)

	# Tags row
	if unit_data.tags.size() > 0:
		var tags_hbox := HBoxContainer.new()
		tags_hbox.add_theme_constant_override("separation", 4)
		for tag in unit_data.tags:
			var tag_label := Label.new()
			tag_label.text = tag.capitalize()
			tag_label.add_theme_font_size_override("font_size", 10)
			var tag_color: Color = TAG_COLORS.get(tag, Color(0.5, 0.5, 0.5))
			tag_label.add_theme_color_override("font_color", tag_color.lightened(0.4))
			tags_hbox.add_child(tag_label)
		stats_vbox.add_child(tags_hbox)

	# Movement points
	var mp_label := Label.new()
	mp_label.text = "MP: %.1f" % unit_data.movement_points
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", Color(0.55, 0.72, 0.55))
	stats_vbox.add_child(mp_label)

	hbox.add_child(stats_vbox)

	# Hover scale effect
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2(1.03, 1.03), 0.1)
	)
	card.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.1)
	)
	card.pivot_offset = card.size * 0.5

	# Right-click to open detail panel
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_show_unit_detail(unit, unit_data)
	)

	return card

func _show_unit_detail(unit: UnitInstance, unit_data: UnitData) -> void:
	if _unit_detail_panel:
		_unit_detail_panel.queue_free()
		_unit_detail_panel = null

	_unit_detail_panel = _create_centered_dialog(420, 400)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unit_detail_panel.add_child(outer_vbox)

	# Header with close
	var header := HBoxContainer.new()
	var title := _make_label(unit_data.display_name, 16, Color(0.95, 0.88, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_make_close_button(func():
		if _unit_detail_panel:
			_unit_detail_panel.queue_free()
			_unit_detail_panel = null
	))
	outer_vbox.add_child(header)

	# Main content: portrait on left, stats on right
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_hbox)

	# Portrait placeholder (80x120)
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(80, 120)
	var portrait_style := StyleBoxFlat.new()
	var portrait_color := Color(0.3, 0.25, 0.2)
	for tag in unit_data.tags:
		if TAG_COLORS.has(tag):
			portrait_color = TAG_COLORS[tag]
			break
	portrait_style.bg_color = portrait_color
	portrait_style.border_width_left = 2
	portrait_style.border_width_top = 2
	portrait_style.border_width_right = 2
	portrait_style.border_width_bottom = 2
	portrait_style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	portrait_style.corner_radius_top_left = 4
	portrait_style.corner_radius_top_right = 4
	portrait_style.corner_radius_bottom_right = 4
	portrait_style.corner_radius_bottom_left = 4
	portrait.add_theme_stylebox_override("panel", portrait_style)
	var icon_center := CenterContainer.new()
	portrait.add_child(icon_center)
	var icon_label := Label.new()
	icon_label.add_theme_font_size_override("font_size", 36)
	var primary_tag := unit_data.tags[0] if unit_data.tags.size() > 0 else "infantry"
	match primary_tag:
		"infantry": icon_label.text = "\u2694"
		"cavalry": icon_label.text = "\u265E"
		"mage": icon_label.text = "\u2726"
		"ranged": icon_label.text = "\u279B"
		"construct": icon_label.text = "\u2699"
		"support": icon_label.text = "\u271A"
		_: icon_label.text = "\u2694"
	icon_label.add_theme_color_override("font_color", portrait_color.lightened(0.5))
	icon_center.add_child(icon_label)
	content_hbox.add_child(portrait)

	# Right side: scrollable stats
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Description
	if unit_data.description != "":
		var desc := Label.new()
		desc.text = unit_data.description
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

	_add_separator(vbox)

	# Combat stats
	var stats_header := Label.new()
	stats_header.text = "Combat Stats"
	stats_header.add_theme_font_size_override("font_size", 13)
	stats_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(stats_header)

	var hp_text := "  HP: %d / %d" % [unit.current_hp, unit_data.max_hp]
	if unit_data.hp_per_soldier > 0:
		hp_text += "  (%d per soldier)" % unit_data.hp_per_soldier
	var hp_label := Label.new()
	hp_label.text = hp_text
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	vbox.add_child(hp_label)

	var detail_dps := estimate_unit_dps(unit_data)
	var atk_stars_d := get_attack_stars(unit_data)
	var def_stars_d := get_defense_stars(unit_data)
	var stat_lines: Array[String] = [
		"  %s ATK  %s DEF" % [render_stars(atk_stars_d), render_stars(def_stars_d)],
		"  DPS: %d  |  ATK: %d  |  SPD: %d" % [int(detail_dps), unit_data.attack, unit_data.speed],
		"  DEF: Melee %d / Ranged %d / Magic %d" % [unit_data.melee_defense, unit_data.projectile_defense, unit_data.magic_defense],
		"  Range: %d  |  Morale: %d" % [unit_data.attack_range, unit_data.base_morale],
		"  Squad Size: %d  |  MP: %.1f" % [unit_data.squad_size, unit_data.movement_points],
	]
	for line in stat_lines:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(l)

	# Tags
	if unit_data.tags.size() > 0:
		var tag_strs: Array[String] = []
		for t in unit_data.tags:
			tag_strs.append(t.capitalize())
		var tags_label := Label.new()
		tags_label.text = "  Tags: " + ", ".join(tag_strs)
		tags_label.add_theme_font_size_override("font_size", 12)
		tags_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		vbox.add_child(tags_label)

	_add_separator(vbox)

	# Costs
	var cost_header := Label.new()
	cost_header.text = "Costs"
	cost_header.add_theme_font_size_override("font_size", 13)
	cost_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(cost_header)

	if unit_data.recruit_cost.size() > 0:
		var recruit_label := Label.new()
		var detail_pop_cost: int = unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
		var pop_suffix := "  |  Pop: %d" % detail_pop_cost if detail_pop_cost > 0 else ""
		recruit_label.text = "  Recruit: " + _format_cost(unit_data.recruit_cost) + pop_suffix
		recruit_label.add_theme_font_size_override("font_size", 12)
		recruit_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(recruit_label)

	if unit_data.upkeep_cost.size() > 0:
		var upkeep_label := Label.new()
		upkeep_label.text = "  Upkeep: " + _format_cost(unit_data.upkeep_cost)
		upkeep_label.add_theme_font_size_override("font_size", 12)
		upkeep_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
		vbox.add_child(upkeep_label)

	# Veterancy
	if unit.veterancy_level > 0 or unit.experience > 0:
		_add_separator(vbox)
		var vet_label := Label.new()
		vet_label.text = "  Veterancy: Lv%d  |  XP: %d" % [unit.veterancy_level, unit.experience]
		vet_label.add_theme_font_size_override("font_size", 12)
		vet_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		vbox.add_child(vet_label)

	add_child(_unit_detail_panel)

func _add_stat_label(parent: HBoxContainer, stat_name: String, value: String, color: Color) -> void:
	var label := Label.new()
	label.text = stat_name + ":" + value
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

## Estimate DPS for a unit based on its type, squad size, and attack speed.
## Factors in ammo limits (archers) and mana slowdown (mages) for realistic sustained DPS.
static func estimate_unit_dps(ud: UnitData) -> float:
	if ud.tags.has("mage"):
		# Mages: infinite ammo but mana-limited. Average cooldown over full mana drain:
		# First 50% mana: base cooldown (12 ticks). Last 50%: avg 1.9x cooldown (~23 ticks).
		# Weighted average: ~15 ticks effective cooldown over sustained fight
		var avg_cooldown := 15.0
		return ud.squad_size * ud.attack * 0.6 * 0.7 * (10.0 / avg_cooldown)
	if ud.tags.has("ranged"):
		# Archers: 7 volleys then depleted. Show sustained DPS over a ~70 tick fight
		# (7 volleys * 7 tick cooldown = 49 ticks of fire, then 0 for remainder)
		var volleys := 7.0
		var fight_duration := 70.0  # ~7 second reference fight
		var effective_rate := volleys / fight_duration * 10.0
		return ud.squad_size * ud.attack * 0.6 * 0.8 * effective_rate
	# Melee: continuous damage at TICK_SCALE(0.2) * 10 ticks/sec = 2x attack per entity
	if ud.squad_size <= 1:
		return ud.attack * 2.0
	# Multi-entity melee: assume ~35% squad in frontline contact (proximity-weighted)
	var frontline := ceili(ud.squad_size * 0.35)
	return frontline * ud.attack * 2.0

# ── Star Rating System ─────────────────────────────────────────────
# Cached percentile tables (computed once, cleared on scene reload)
static var _attack_star_cache: Dictionary = {}  # unit_data_id -> float stars
static var _defense_star_cache: Dictionary = {}
static var _star_tables_built: bool = false
static var _all_dps_sorted: Array[float] = []
static var _all_surv_sorted: Array[float] = []

static func _build_star_tables() -> void:
	if _star_tables_built:
		return
	_star_tables_built = true
	var dps_values: Array[float] = []
	var surv_values: Array[float] = []
	var unit_dps: Dictionary = {}
	var unit_surv: Dictionary = {}
	for ud: UnitData in DataManager.units.values():
		if ud.tags.has("elderbeast"):
			continue
		var dps := estimate_unit_dps(ud)
		var w_def := ud.melee_defense * 0.5 + ud.projectile_defense * 0.3 + ud.magic_defense * 0.2
		var hp_factor := clampf(ud.max_hp / 1000.0, 0.3, 2.5)
		var surv := w_def * hp_factor
		unit_dps[ud.id] = dps
		unit_surv[ud.id] = surv
		dps_values.append(dps)
		surv_values.append(surv)
	dps_values.sort()
	surv_values.sort()
	_all_dps_sorted = dps_values
	_all_surv_sorted = surv_values
	for uid in unit_dps:
		_attack_star_cache[uid] = _percentile_to_stars(unit_dps[uid], _all_dps_sorted)
		_defense_star_cache[uid] = _percentile_to_stars(unit_surv[uid], _all_surv_sorted)

static func _percentile_to_stars(value: float, sorted_arr: Array[float]) -> float:
	if sorted_arr.is_empty():
		return 3.0
	var count := sorted_arr.size()
	var pos := sorted_arr.bsearch(value)
	var pct := float(pos) / float(count)
	var stars := 1.0 + pct * 4.0  # 0% → 1 star, 100% → 5 stars
	return snappedf(stars, 0.5)

static func get_attack_stars(ud: UnitData) -> float:
	_build_star_tables()
	return _attack_star_cache.get(ud.id, 3.0)

static func get_defense_stars(ud: UnitData) -> float:
	_build_star_tables()
	return _defense_star_cache.get(ud.id, 3.0)

static func render_stars(stars: float, color: Color = Color.WHITE) -> String:
	var full := int(stars)
	var half := (stars - full) >= 0.5
	var empty := 5 - full - (1 if half else 0)
	var text := ""
	for i in full:
		text += "★"
	if half:
		text += "✦"
	for i in empty:
		text += "☆"
	return text

const STAR_COLOR_ATTACK := Color(0.9, 0.55, 0.3)   # Red-orange
const STAR_COLOR_DEFENSE := Color(0.4, 0.6, 0.9)    # Blue

func _on_army_deselected() -> void:
	army_panel.visible = false
	_hide_commander_panel()

func _on_turn_started(_turn: int, _faction_id: StringName) -> void:
	_update_top_bar()
	_update_resource_display()
	end_turn_button.disabled = not TurnManager.is_player_turn
	# Show/hide AI speed controls
	var ai_visible := not TurnManager.is_player_turn
	if _skip_ai_btn:
		_skip_ai_btn.visible = ai_visible
	if _speed_label:
		_speed_label.visible = ai_visible
	var speed_btn := get_node_or_null("TopBar/HBoxContainer/SpeedButton")
	if speed_btn:
		speed_btn.visible = ai_visible
	# Turn banner
	_show_turn_banner(_turn, _faction_id)
	# Resource bar gold pulse on player turn
	if TurnManager.is_player_turn and resource_bar:
		var pulse_tw := create_tween()
		pulse_tw.tween_property(resource_bar, "modulate", Color(1.3, 1.2, 0.8), 0.15)
		pulse_tw.tween_property(resource_bar, "modulate", Color.WHITE, 0.3)
	# Auto-refresh loyalty panel if open
	if _loyalty_panel_city_id != &"":
		_show_loyalty_panel(_loyalty_panel_city_id)
	_update_research_status_label()
	# Auto-refresh research panel if open
	if _research_panel and _research_panel.visible:
		_refresh_research_panel()
	# Auto-refresh diplomacy panel if open
	if _diplomacy_panel and _diplomacy_panel.visible:
		_refresh_diplomacy_panel()
	# Show turn summary when player turn starts (if there are log entries)
	if TurnManager.is_player_turn and _faction_id == GameManager.state.player_faction_id:
		if TurnManager.turn_log.size() > 0:
			_show_turn_summary()
		# Tutorial hint on first turn
		_check_tutorial("turn_start")
		# Advisor messages
		_check_advisor_messages()
		# Check for Forsaken offer / senate dilemma (Empire only)
		if _faction_id == &"empire":
			var offer := GameManager.policy_system.check_forsaken_offer(_faction_id, GameManager.state.current_turn)
			if not offer.is_empty():
				EventBus.forsaken_offer.emit(_faction_id, offer)
			else:
				var dilemma := GameManager.policy_system.check_senate_dilemma(_faction_id, GameManager.state.current_turn)
				if not dilemma.is_empty():
					call_deferred("_emit_senate_dilemma", _faction_id, dilemma)

func _on_army_moved(army_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	_check_tutorial("army_moved")
	# Refresh army panel if the moved army is selected
	var campaign: Node2D = get_parent().get_parent()
	if campaign and "selected_army_id" in campaign:
		if campaign.selected_army_id == army_id:
			_on_army_selected(army_id)

func _on_elderbeast_moved(beast_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	# Refresh resource bar (terrain income changed)
	_update_resource_display()
	# Refresh elderbeast panel if open for this beast
	if _elderbeast_panel:
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
		if beast:
			_show_elderbeast_panel(beast)

# ── Resource display ─────────────────────────────────────────

const RESOURCE_ICONS := {
	0: "●",  # Gold - coin
	1: "◆",  # Iron - ingot
	2: "✦",  # Technology - gear
	3: "●",  # Food - steak
	5: "■",  # Wood - logs
	6: "⛓",  # Captives - people
}

static func _create_resource_icon(res_type: int, icon_size: float = 16.0) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(icon_size, icon_size)
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(icon_size), int(icon_size))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(viewport)
	var root := Node2D.new()
	root.position = Vector2(icon_size / 2.0, icon_size / 2.0)
	viewport.add_child(root)
	var s := icon_size / 16.0  # scale factor
	match res_type:
		0:  # Gold - stacked coins
			for i in 3:
				var coin := Polygon2D.new()
				var pts := PackedVector2Array()
				for j in 10:
					var angle := TAU * j / 10.0
					pts.append(Vector2(cos(angle) * 5.0 * s, sin(angle) * 3.5 * s))
				coin.polygon = pts
				coin.position = Vector2(float(i - 1) * 2.0 * s, float(1 - i) * 1.5 * s)
				coin.color = Color(0.95, 0.85, 0.3).darkened(i * 0.08)
				root.add_child(coin)
				# Rim highlight on top coin
				if i == 0:
					var rim := Polygon2D.new()
					var rim_pts := PackedVector2Array()
					for j in 10:
						var angle := TAU * j / 10.0
						rim_pts.append(Vector2(cos(angle) * 3.0 * s, sin(angle) * 2.0 * s))
					rim.polygon = rim_pts
					rim.position = coin.position
					rim.color = Color(1.0, 0.95, 0.5, 0.4)
					root.add_child(rim)
		1:  # Iron - ingot with rivet detail
			var ingot := Polygon2D.new()
			ingot.polygon = PackedVector2Array([
				Vector2(-6 * s, -3 * s), Vector2(6 * s, -3 * s),
				Vector2(5 * s, 4 * s), Vector2(-5 * s, 4 * s)
			])
			ingot.color = Color(0.55, 0.55, 0.6)
			root.add_child(ingot)
			var highlight := Polygon2D.new()
			highlight.polygon = PackedVector2Array([
				Vector2(-6 * s, -3 * s), Vector2(6 * s, -3 * s),
				Vector2(4 * s, -0.5 * s), Vector2(-4 * s, -0.5 * s)
			])
			highlight.color = Color(0.72, 0.72, 0.78, 0.6)
			root.add_child(highlight)
			# Anvil groove
			var groove := Polygon2D.new()
			groove.polygon = PackedVector2Array([
				Vector2(-3 * s, 1 * s), Vector2(3 * s, 1 * s),
				Vector2(2.5 * s, 2 * s), Vector2(-2.5 * s, 2 * s)
			])
			groove.color = Color(0.42, 0.42, 0.47)
			root.add_child(groove)
		2:  # Technology - gear with center hub
			var gear := Polygon2D.new()
			var pts := PackedVector2Array()
			for j in 16:
				var angle := TAU * j / 16.0
				var r := 6.0 * s if j % 2 == 0 else 4.0 * s
				pts.append(Vector2(cos(angle) * r, sin(angle) * r))
			gear.polygon = pts
			gear.color = Color(0.45, 0.55, 0.65)
			root.add_child(gear)
			# Center hub
			var hub := Polygon2D.new()
			var hub_pts := PackedVector2Array()
			for j in 8:
				var angle := TAU * j / 8.0
				hub_pts.append(Vector2(cos(angle) * 2.0 * s, sin(angle) * 2.0 * s))
			hub.polygon = hub_pts
			hub.color = Color(0.35, 0.42, 0.52)
			root.add_child(hub)
		3:  # Food - wheat sheaf
			var steak := Polygon2D.new()
			steak.polygon = PackedVector2Array([
				Vector2(-5 * s, -3 * s), Vector2(-2 * s, -5 * s),
				Vector2(4 * s, -3 * s), Vector2(6 * s, 1 * s),
				Vector2(3 * s, 5 * s), Vector2(-3 * s, 4 * s),
				Vector2(-6 * s, 1 * s)
			])
			steak.color = Color(0.6, 0.35, 0.25)
			root.add_child(steak)
			# Bone notch
			var bone := Polygon2D.new()
			bone.polygon = PackedVector2Array([
				Vector2(-1 * s, -4 * s), Vector2(1 * s, -4 * s),
				Vector2(2 * s, -2 * s), Vector2(-1 * s, -2 * s)
			])
			bone.color = Color(0.85, 0.82, 0.75)
			root.add_child(bone)
			# Fat marbling
			var fat := Polygon2D.new()
			fat.polygon = PackedVector2Array([
				Vector2(0, 0), Vector2(3 * s, -1 * s),
				Vector2(4 * s, 1 * s), Vector2(1 * s, 2 * s)
			])
			fat.color = Color(0.75, 0.5, 0.4, 0.5)
			root.add_child(fat)
		4:  # Shard Essence - purple crystal
			var crystal := Polygon2D.new()
			crystal.polygon = PackedVector2Array([
				Vector2(0, -6 * s), Vector2(4 * s, -1 * s),
				Vector2(3 * s, 5 * s), Vector2(-3 * s, 5 * s),
				Vector2(-4 * s, -1 * s)
			])
			crystal.color = Color(0.6, 0.3, 0.85)
			root.add_child(crystal)
			# Inner glow facet
			var facet := Polygon2D.new()
			facet.polygon = PackedVector2Array([
				Vector2(0, -3.5 * s), Vector2(2 * s, 0),
				Vector2(0, 3 * s), Vector2(-2 * s, 0)
			])
			facet.color = Color(0.8, 0.5, 1.0, 0.5)
			root.add_child(facet)
		5:  # Wood - crossed logs with bark detail
			for angle in [0.4, -0.4]:
				var log := Polygon2D.new()
				log.polygon = PackedVector2Array([
					Vector2(-6 * s, -1.8 * s), Vector2(6 * s, -1.8 * s),
					Vector2(6 * s, 1.8 * s), Vector2(-6 * s, 1.8 * s)
				])
				log.color = Color(0.55, 0.38, 0.22)
				log.rotation = angle
				root.add_child(log)
				# Bark grain
				var grain := Polygon2D.new()
				grain.polygon = PackedVector2Array([
					Vector2(-4 * s, -0.5 * s), Vector2(4 * s, -0.5 * s),
					Vector2(4 * s, 0.5 * s), Vector2(-4 * s, 0.5 * s)
				])
				grain.color = Color(0.65, 0.48, 0.3, 0.4)
				grain.rotation = angle
				root.add_child(grain)
		6:  # Captives - person outlines with chains
			for i in 3:
				var x_off := float(i - 1) * 4.5 * s
				# Head
				var head := Polygon2D.new()
				var hpts := PackedVector2Array()
				for j in 8:
					var angle := TAU * j / 8.0
					hpts.append(Vector2(cos(angle) * 2.2 * s + x_off, sin(angle) * 2.2 * s - 3.5 * s))
				head.polygon = hpts
				head.color = Color(0.65, 0.45, 0.35)
				root.add_child(head)
				# Shoulders
				var body := Polygon2D.new()
				body.polygon = PackedVector2Array([
					Vector2(x_off - 3 * s, -0.5 * s), Vector2(x_off + 3 * s, -0.5 * s),
					Vector2(x_off + 2 * s, 5 * s), Vector2(x_off - 2 * s, 5 * s)
				])
				body.color = Color(0.65, 0.45, 0.35)
				root.add_child(body)
			# Chain link between figures
			var chain := Polygon2D.new()
			chain.polygon = PackedVector2Array([
				Vector2(-3.5 * s, 0), Vector2(3.5 * s, 0),
				Vector2(3.5 * s, 0.8 * s), Vector2(-3.5 * s, 0.8 * s)
			])
			chain.color = Color(0.5, 0.5, 0.5, 0.6)
			root.add_child(chain)
	return container

func _create_resource_bar() -> void:
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 16)

	# Insert before the Spacer in the top bar
	var hbox: HBoxContainer = $TopBar/HBoxContainer
	var spacer := hbox.get_node("Spacer")
	hbox.add_child(resource_bar)
	hbox.move_child(resource_bar, spacer.get_index())

	# Create tooltip panel (hidden)
	_resource_tooltip = PanelContainer.new()
	_resource_tooltip.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.42, 0.2, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	_resource_tooltip.add_theme_stylebox_override("panel", style)
	var tooltip_label := Label.new()
	tooltip_label.name = "TooltipText"
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	_resource_tooltip.add_child(tooltip_label)
	add_child(_resource_tooltip)

	# Build individual resource items (include Shard Essence for Shardhorde)
	var _res_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		_res_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in _res_types:
		var item_vbox := VBoxContainer.new()
		item_vbox.add_theme_constant_override("separation", 0)
		item_vbox.mouse_filter = Control.MOUSE_FILTER_STOP

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 3)

		# Polygon icon
		var icon := _create_resource_icon(res_type, 22.0)
		top_row.add_child(icon)

		# Amount label
		var amount_label := Label.new()
		amount_label.text = "0"
		amount_label.add_theme_font_size_override("font_size", 15)
		amount_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		top_row.add_child(amount_label)

		item_vbox.add_child(top_row)

		# Income preview label (smaller, below)
		var income_label := Label.new()
		income_label.text = ""
		income_label.add_theme_font_size_override("font_size", 11)
		income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_vbox.add_child(income_label)

		# Hover signals for tooltip
		var res_idx: int = res_type  # capture for lambda
		item_vbox.mouse_entered.connect(_on_resource_hover_entered.bind(res_idx))
		item_vbox.mouse_exited.connect(_on_resource_hover_exited)

		resource_bar.add_child(item_vbox)
		_resource_items[res_type] = {
			"amount_label": amount_label,
			"income_label": income_label,
			"container": item_vbox,
		}

	# Faction mechanic label (shows unique mechanic for player faction)
	_faction_mechanic_label = Label.new()
	_faction_mechanic_label.add_theme_font_size_override("font_size", 11)
	_faction_mechanic_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	resource_bar.add_child(_faction_mechanic_label)

func _calculate_projected_income() -> Dictionary:
	# Use the detailed breakdown for each resource to get true net income
	var income: Dictionary = {}
	var display_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var breakdown := _calculate_income_breakdown(res_type)
		if breakdown.net != 0:
			income[res_type] = breakdown.net
	return income

func _calculate_income_breakdown(res_type: int) -> Dictionary:
	# Returns {"cities": {city_name: amount}, "upkeep": {category: amount},
	#          "modifiers": [{label, amount}], "net": int}
	# Mirrors the actual _generate_income() logic in city_system.gd
	var breakdown := {"cities": {}, "upkeep": {}, "modifiers": [], "net": 0}
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return breakdown

	# Step 1: Base city income (from buildings + region)
	var base_total := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income := GameManager.city_system.calculate_city_income(city)
			var amount: int = city_income.get(res_type, 0)
			if amount != 0:
				breakdown.cities[city.get_display_name()] = amount
				base_total += amount

	# Step 2: Class bonuses (applied per-city in _generate_income, aggregate here)
	var class_bonus_total := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income := GameManager.city_system.calculate_city_income(city)
			var raw: int = city_income.get(res_type, 0)
			if raw == 0:
				continue
			var pcts := LoyaltySystem.calculate_class_percentages(city, city.faction_id)
			var bonus := 0
			match res_type:
				Enums.ResourceType.FOOD:
					bonus = int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
					bonus = int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.TECHNOLOGY:
					bonus = int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
				Enums.ResourceType.GOLD:
					bonus = int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
			class_bonus_total += bonus
	if class_bonus_total != 0:
		var class_label := ""
		match res_type:
			Enums.ResourceType.FOOD: class_label = "Peasant Bonus"
			Enums.ResourceType.IRON, Enums.ResourceType.WOOD: class_label = "Artisan Bonus"
			Enums.ResourceType.TECHNOLOGY: class_label = "Scholar Bonus"
			Enums.ResourceType.GOLD: class_label = "Noble Bonus"
			_: class_label = "Class Bonus"
		breakdown.modifiers.append({label = class_label, amount = class_bonus_total})

	var income_subtotal := base_total + class_bonus_total

	# Step 3: Loyalty multiplier (applied per-city, aggregate the penalty)
	var loyalty_penalty := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income := GameManager.city_system.calculate_city_income(city)
			var raw: int = city_income.get(res_type, 0)
			if raw == 0:
				continue
			var pcts := LoyaltySystem.calculate_class_percentages(city, city.faction_id)
			var after_class := raw
			match res_type:
				Enums.ResourceType.FOOD:
					after_class += int(float(raw) * (pcts.get("peasants", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.IRON, Enums.ResourceType.WOOD:
					after_class += int(float(raw) * (pcts.get("artisans", 0.0) * 100.0 * 0.005))
				Enums.ResourceType.TECHNOLOGY:
					after_class += int(float(raw) * (pcts.get("scholars", 0.0) * 100.0 * 0.008))
				Enums.ResourceType.GOLD:
					after_class += int(float(raw) * (pcts.get("nobles", 0.0) * 100.0 * 0.006))
			var loyalty_mult := LoyaltySystem.get_loyalty_multiplier(city.loyalty)
			if loyalty_mult < 1.0:
				loyalty_penalty += int(float(after_class) * loyalty_mult) - after_class
	if loyalty_penalty != 0:
		breakdown.modifiers.append({label = "Low Loyalty", amount = loyalty_penalty})
		income_subtotal += loyalty_penalty

	# Step 4: Research percentage bonuses
	var research_effects := GameManager.research_system.get_research_effects(player_id)
	var research_bonus := 0
	match res_type:
		Enums.ResourceType.GOLD:
			var pct: int = research_effects.get("income_gold_pct", 0)
			if pct != 0:
				research_bonus = int(income_subtotal * pct / 100.0)
		Enums.ResourceType.FOOD:
			var pct: int = research_effects.get("income_food_pct", 0)
			if pct != 0:
				research_bonus = int(income_subtotal * pct / 100.0)
	if research_bonus != 0:
		breakdown.modifiers.append({label = "Research", amount = research_bonus})
		income_subtotal += research_bonus

	# Step 5: Senate majority effects (Empire only)
	if player_id == &"empire":
		var senate_effects := GameManager.policy_system.get_senate_majority_effects(player_id)
		var senate_pct_key := ""
		match res_type:
			Enums.ResourceType.GOLD: senate_pct_key = "gold_income_pct"
			Enums.ResourceType.TECHNOLOGY: senate_pct_key = "tech_income_pct"
			Enums.ResourceType.IRON: senate_pct_key = "iron_income_pct"
			Enums.ResourceType.WOOD: senate_pct_key = "wood_income_pct"
		if senate_pct_key != "" and senate_effects.has(senate_pct_key):
			var pct: int = senate_effects[senate_pct_key]
			if pct != 0:
				var senate_amount := int(income_subtotal * pct / 100.0)
				breakdown.modifiers.append({label = "Senate Majority (%+d%%)" % pct, amount = senate_amount})
				income_subtotal += senate_amount

	# Step 6: Active trade agreements
	var trade_income := 0
	var trade_cost := 0
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_DEAL:
			continue
		var is_a := treaty.faction_a == player_id
		var is_b := treaty.faction_b == player_id
		if not is_a and not is_b:
			continue
		var give_res: int = treaty.terms.get("give_resource", -1)
		var give_amt: int = treaty.terms.get("give_amount", 0)
		var recv_res: int = treaty.terms.get("receive_resource", -1)
		var recv_amt: int = treaty.terms.get("receive_amount", 0)
		# faction_a gives give_res and receives recv_res
		# faction_b gives recv_res and receives give_res
		var partner_fd: FactionData
		if is_a:
			partner_fd = DataManager.get_faction(treaty.faction_b)
			if give_res == res_type:
				trade_cost += give_amt
			if recv_res == res_type:
				trade_income += recv_amt
		else:
			partner_fd = DataManager.get_faction(treaty.faction_a)
			if recv_res == res_type:
				trade_cost += recv_amt
			if give_res == res_type:
				trade_income += give_amt
		var partner_name: String = partner_fd.display_name if partner_fd else "Unknown"
		if (is_a and recv_res == res_type) or (is_b and give_res == res_type):
			var amt: int = recv_amt if is_a else give_amt
			breakdown.modifiers.append({label = "Trade (%s)" % partner_name, amount = amt})
		if (is_a and give_res == res_type) or (is_b and recv_res == res_type):
			var amt: int = give_amt if is_a else recv_amt
			breakdown.modifiers.append({label = "Trade (%s)" % partner_name, amount = -amt})
	income_subtotal += trade_income - trade_cost

	# Step 6b: Trade Relations (continuous resource sharing treaties)
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_RELATIONS:
			continue
		var is_a := treaty.faction_a == player_id
		var is_b := treaty.faction_b == player_id
		if not is_a and not is_b:
			continue
		var turns_active: int = treaty.terms.get("turns_active", 0)
		var share_pct := GameManager.diplomacy_system.get_trade_relations_share(turns_active) / 100.0
		var res_a: int = treaty.terms.get("resource_a", 0)
		var res_b: int = treaty.terms.get("resource_b", 0)
		var partner_id: StringName = treaty.faction_b if is_a else treaty.faction_a
		var partner_fd: FactionData = DataManager.get_faction(partner_id)
		var partner_name: String = partner_fd.display_name if partner_fd else "Unknown"
		# What we receive: their top resource shared to us
		var we_receive_res: int = res_b if is_a else res_a
		if we_receive_res == res_type:
			var their_income := GameManager.diplomacy_system.get_faction_resource_income(partner_id, we_receive_res)
			var gain := maxi(1, int(float(their_income) * share_pct))
			breakdown.modifiers.append({label = "Trade Relations (%s)" % partner_name, amount = gain})
			income_subtotal += gain
		# What we share: our top resource given to them (shown as cost)
		var we_share_res: int = res_a if is_a else res_b
		if we_share_res == res_type:
			# Trade relations don't deduct resources — they grant copies. No cost line needed.
			pass

	# Elderbeast terrain + building income
	var beast_total := 0
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.faction_id == player_id:
			var beast_income := TurnManager._get_elderbeast_income(beast)
			var amount: int = beast_income.get(res_type, 0)
			if amount != 0:
				breakdown.cities[beast.name] = amount
				beast_total += amount
	income_subtotal += beast_total

	# Upkeep grouped by tag
	var upkeep_total := 0
	var upkeep_by_tag: Dictionary = {}
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id:
			for unit in army.units:
				var ud := DataManager.get_unit(unit.unit_data_id)
				if ud and ud.upkeep_cost.has(res_type):
					var tag := "Other"
					for t in ["infantry", "ranged", "cavalry", "mage", "construct"]:
						if ud.tags.has(t):
							tag = t.capitalize()
							break
					upkeep_by_tag[tag] = upkeep_by_tag.get(tag, 0) + ud.upkeep_cost[res_type]
					upkeep_total += ud.upkeep_cost[res_type]
			# Commander upkeep
			if army.commander != null and CommanderSystem.COMMANDER_UPKEEP.has(res_type):
				var level_mult := 1.0 + (army.commander.level - 1) * 0.5
				var cmd_cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				upkeep_by_tag["Commanders"] = upkeep_by_tag.get("Commanders", 0) + cmd_cost
				upkeep_total += cmd_cost
	breakdown.upkeep = upkeep_by_tag

	# Population food consumption (quartered rate)
	var food_consumption := 0
	if res_type == Enums.ResourceType.FOOD:
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city and not city.is_under_siege:
				var province_pop := GameManager.city_system.get_province_population(city)
				food_consumption += province_pop / 40
		if food_consumption > 0:
			breakdown.modifiers.append({label = "Pop. Consumption", amount = -food_consumption})

	# Captive consumption from buildings (labor camps, faction-specific buildings)
	var captive_consumption := 0
	if res_type == Enums.ResourceType.CAPTIVES:
		var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(player_id, player_id)
		for city_id in fs.owned_cities:
			var city: CityState = GameManager.state.cities.get(city_id)
			if city == null:
				continue
			# Base camp buildings
			if city.buildings.has(&"labor_camp"):
				captive_consumption += 3
			if city.buildings.has(&"thrall_quarters"):
				captive_consumption += 2
			if city.buildings.has(&"captive_processing_camp"):
				captive_consumption += 4
			# Faction-specific buildings
			match parent_fid:
				&"skulloath":
					if city.buildings.has(&"blood_altar"):
						captive_consumption += 4
				&"moonspear":
					if city.buildings.has(&"lunar_observatory") or city.buildings.has(&"astral_observatory"):
						captive_consumption += 3
				&"thunderswarm":
					if city.buildings.has(&"warriors_longhouse") or city.buildings.has(&"warchief_warcamp"):
						captive_consumption += 3
				&"cinderguard":
					if city.buildings.has(&"ember_foundry") or city.buildings.has(&"molten_core_forge"):
						captive_consumption += 4
				&"forsaken":
					if city.buildings.has(&"wretched_pit") or city.buildings.has(&"plague_workshop"):
						captive_consumption += 3
					if city.buildings.has(&"void_pit"):
						captive_consumption += 3
				&"ivoryscar":
					if city.buildings.has(&"tomb_scholars_hall") or city.buildings.has(&"vault_of_ages"):
						captive_consumption += 3
				&"sunblessed":
					if city.buildings.has(&"pilgrims_rest") or city.buildings.has(&"cathedral_of_dawn"):
						captive_consumption += 2
				&"empire":
					if city.buildings.has(&"imperial_work_yard"):
						captive_consumption += 4
		if captive_consumption > 0:
			breakdown.modifiers.append({label = "Building Consumption", amount = -captive_consumption})

	breakdown.net = income_subtotal - upkeep_total - food_consumption - captive_consumption
	return breakdown

func _update_resource_display() -> void:
	if GameManager.state == null or resource_bar == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs == null:
		return

	var projected := _calculate_projected_income()

	var _display_types := [0, 1, 2, 3, 5, 6]
	if GameManager.state.player_faction_id == &"shardhorde":
		_display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in _display_types:
		var item: Dictionary = _resource_items.get(res_type, {})
		if item.is_empty():
			continue
		var amount: int = fs.resources.get(res_type, 0)
		var net: int = projected.get(res_type, 0)

		var amount_label: Label = item.amount_label
		amount_label.text = str(amount)

		var income_label: Label = item.income_label
		if net > 0:
			income_label.text = "+" + str(net)
			income_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		elif net < 0:
			income_label.text = str(net)
			income_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
		else:
			income_label.text = "+0"
			income_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))

	# Update shard display
	_update_shard_display()

	# Update faction mechanic display
	_update_faction_mechanic_display(fs)

func _on_resource_hover_entered(res_type: int) -> void:
	if _resource_tooltip == null:
		return
	var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
	var breakdown := _calculate_income_breakdown(res_type)
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	var current: int = fs.resources.get(res_type, 0) if fs else 0

	var text := "%s: %d" % [rname, current]
	for city_name in breakdown.cities:
		var amount: int = breakdown.cities[city_name]
		text += "\n  %s: +%d" % [city_name, amount]
	for mod in breakdown.modifiers:
		var mod_amount: int = mod.amount
		text += "\n  %s: %s%d" % [mod.label, "+" if mod_amount >= 0 else "", mod_amount]
	for tag in breakdown.upkeep:
		var amount: int = breakdown.upkeep[tag]
		text += "\n  %s Upkeep: -%d" % [tag, amount]
	text += "\n  Net: %s%d" % ["+" if breakdown.net >= 0 else "", breakdown.net]

	var tooltip_label: Label = _resource_tooltip.get_node("TooltipText")
	tooltip_label.text = text

	# Position tooltip below the resource item
	var item: Dictionary = _resource_items.get(res_type, {})
	if not item.is_empty():
		var container: Control = item.container
		var rect := container.get_global_rect()
		_resource_tooltip.position = Vector2(rect.position.x, rect.end.y + 4)

	_resource_tooltip.visible = true

func _on_resource_hover_exited() -> void:
	if _resource_tooltip:
		_resource_tooltip.visible = false

func _update_faction_mechanic_display(fs: FactionState) -> void:
	if _faction_mechanic_label == null:
		return
	var player_id := GameManager.state.player_faction_id
	var text := ""
	var color := Color(0.75, 0.7, 0.6)
	match player_id:
		&"skulloath":
			var tier := "Tradition" if fs.corruption <= 30 else ("Void" if fs.corruption >= 61 else "Balanced")
			var path_note := ""
			if fs.corruption <= 40:
				path_note = " | Ancestor Sanctum available"
			elif fs.corruption >= 60:
				path_note = " | Demon Gate available"
			else:
				path_note = " | T3 buildings locked"
			text = "Corruption: %d (%s)%s" % [fs.corruption, tier, path_note]
			color = Color(0.6, 0.8, 0.5) if fs.corruption <= 30 else (Color(0.9, 0.3, 0.3) if fs.corruption >= 61 else Color(0.75, 0.7, 0.6))
		&"tainted_jade":
			text = "Taint: %d" % fs.taint_power
			color = Color(0.4, 0.85, 0.5) if fs.taint_power >= 50 else Color(0.6, 0.75, 0.55)
		&"gladehost":
			var season_name := TurnManager.get_season_name(TurnManager.get_current_season())
			text = "Harmony: %d | %s" % [fs.harmony, season_name]
			color = Color(0.4, 0.85, 0.4) if fs.harmony >= 70 else (Color(0.85, 0.5, 0.3) if fs.harmony <= 35 else Color(0.65, 0.78, 0.5))
		&"shardhorde":
			var res_count := fs.shard_resonance.size()
			text = "Resonance: %d active" % res_count if res_count > 0 else "Resonance: None"
			color = Color(0.6, 0.4, 0.9) if res_count > 0 else Color(0.55, 0.52, 0.45)
		&"moonspear":
			var phase_name := TurnManager.get_lunar_phase_name(fs.lunar_phase)
			var bonus := ""
			match fs.lunar_phase:
				0: bonus = "+Atk"
				1: bonus = "+Move"
				2: bonus = "+Def"
				3: bonus = "+Heal"
			text = "%s (%s)" % [phase_name, bonus]
			color = Color(0.7, 0.75, 0.95)
		&"thunderswarm":
			text = "Storm Fury: %d" % fs.storm_fury
			color = Color(0.95, 0.6, 0.2) if fs.storm_fury >= 80 else (Color(0.85, 0.75, 0.3) if fs.storm_fury >= 50 else Color(0.6, 0.6, 0.55))
		&"cinderguard":
			var mode := "Blazing" if fs.forge_heat >= 70 else ("Cool" if fs.forge_heat <= 30 else "Tempered")
			text = "Forge: %d (%s)" % [fs.forge_heat, mode]
			color = Color(0.95, 0.5, 0.2) if fs.forge_heat >= 70 else (Color(0.4, 0.65, 0.85) if fs.forge_heat <= 30 else Color(0.75, 0.65, 0.45))
		&"forsaken":
			text = "Espionage: %d" % fs.espionage_network
			color = Color(0.5, 0.8, 0.5) if fs.espionage_network >= 20 else Color(0.6, 0.6, 0.55)
		&"ivoryscar":
			text = "Relic Power: %d" % fs.relic_power
			color = Color(0.8, 0.7, 0.4) if fs.relic_power >= 30 else Color(0.65, 0.6, 0.5)
		&"sunblessed":
			var mood := "Zealous" if fs.solar_faith >= 70 else ("Faltering" if fs.solar_faith <= 30 else "Faithful")
			var wisdom_tier := "Sage" if fs.wisdom >= 80 else ("Learned" if fs.wisdom >= 30 else "Novice")
			text = "Faith: %d (%s) | Wisdom: %d (%s)" % [fs.solar_faith, mood, fs.wisdom, wisdom_tier]
			color = Color(0.95, 0.85, 0.3) if fs.solar_faith >= 70 else (Color(0.6, 0.4, 0.4) if fs.solar_faith <= 30 else Color(0.8, 0.75, 0.5))
	# Tooltip descriptions for faction mechanics
	var tooltip := ""
	var mechanic_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(player_id, player_id)
	match mechanic_fid:
		&"skulloath":
			tooltip = "Corruption (0-100) tracks your path between Tradition and Void.\n"
			tooltip += "Tradition buildings: -1 corruption/turn. Void buildings: +2/turn.\n\n"
			tooltip += "Low (0-30): +15% food, +loyalty, +diplomacy.\n"
			tooltip += "High (61-80): +15% attack in battle, -loyalty.\n"
			tooltip += "Deep (81+): +25% attack, -3 loyalty, -2 diplomacy.\n\n"
			tooltip += "Ancestor Sanctum (T3): requires corruption <= 40.\n"
			tooltip += "Demon Gate (T3): requires corruption >= 60."
		&"tainted_jade":
			tooltip = "Taint Power grows from territory control and jungle spread.\n\n"
			tooltip += "20+: +10% defense in battle, +5% iron income.\n"
			tooltip += "50+: +15% defense in battle.\n\n"
			tooltip += "Jungle terrain spreads near your cities each turn.\n"
			tooltip += "Units regenerate HP when fighting in jungle."
		&"gladehost":
			tooltip = "Harmony (0-100) reflects your bond with nature.\n"
			tooltip += "Rises with fewer buildings and more forest tiles. Falls from overbuilding.\n\n"
			tooltip += "70+: +10 morale in battle, +loyalty, +diplomacy.\n"
			tooltip += "35-: -loyalty in capital.\n\n"
			tooltip += "Seasonal income scales with harmony:\n"
			tooltip += "  Spring: +food. Summer: +iron.\n"
			tooltip += "  Autumn: +gold/wood. Winter: -food.\n"
			tooltip += "Seasonal Shrine amplifies seasonal bonuses and restores harmony."
		&"shardhorde":
			tooltip = "Active Shard Resonances from captured realm shards.\n\n"
			tooltip += "Each active realm provides combat and income bonuses:\n"
			tooltip += "  Divine: +gold, Elemental: +iron, Nature: +food.\n"
			tooltip += "  Mortal: +gold/food, Void: +tech and +10% attack."
		&"moonspear":
			tooltip = "The moon cycles through 4 phases, changing each turn.\n\n"
			tooltip += "New Moon: +10% attack. Waxing: +1 movement.\n"
			tooltip += "Full Moon: +10% defense. Waning: army healing.\n\n"
			tooltip += "Ethereal units: 15% dodge chance, +15 morale, -15% HP."
		&"thunderswarm":
			tooltip = "Storm Fury (0-100) builds from victories and mountain positioning.\n\n"
			tooltip += "50+: +10% attack in battle.\n"
			tooltip += "80+: +20% attack, -5% defense (reckless fury).\n"
			tooltip += "Decays -5/turn naturally.\n\n"
			tooltip += "Killing Thunderswarm beasts/monsters angers them (-8 standing)."
		&"cinderguard":
			tooltip = "Forge Heat (0-100) from combat and industry.\n\n"
			tooltip += "Cool (0-30): +15% defense in battle.\n"
			tooltip += "Blazing (85+): +5% attack in battle.\n\n"
			tooltip += "All units: +3 attack vs monsters and beasts.\n"
			tooltip += "+2 defense in desert and shard wastes."
		&"forsaken":
			tooltip = "Espionage Network strength.\n\n"
			tooltip += "Higher values improve spy effectiveness and intelligence gathering."
		&"ivoryscar":
			tooltip = "Relic Power grows from controlling Shard Wastes territory.\n\n"
			tooltip += "15+: +5% defense in battle.\n"
			tooltip += "30+: +10% defense in battle."
		&"sunblessed":
			tooltip = "Solar Faith (0-100): rises on victories (+10), falls on defeats (-15).\n"
			tooltip += "70+: heal armies in owned territory, +loyalty.\n"
			tooltip += "85+: +10% attack, +5% defense in battle.\n\n"
			tooltip += "Wisdom: grows from teaching allied cities (within 2 hexes).\n"
			tooltip += "Nearby allied cities gain +3 tech and +1 loyalty.\n"
			tooltip += "10+ wisdom: bonus tech income. 30+: improved diplomacy."
	_faction_mechanic_label.tooltip_text = tooltip
	_faction_mechanic_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_faction_mechanic_label.text = text
	_faction_mechanic_label.add_theme_color_override("font_color", color)

# ── Economy Panel ─────────────────────────────────────────────

func _create_economy_panel() -> void:
	# Add top bar buttons (before End Turn): Diplomacy, Policies, Research, Economy
	var hbox: HBoxContainer = $TopBar/HBoxContainer
	var end_btn_idx := end_turn_button.get_index()

	# Diplomacy button
	_create_diplomacy_panel()
	var diplomacy_btn := Button.new()
	diplomacy_btn.name = "DiplomacyButton"
	diplomacy_btn.text = "Diplomacy"
	diplomacy_btn.custom_minimum_size = Vector2(90, 0)
	diplomacy_btn.pressed.connect(_toggle_diplomacy_panel)
	hbox.add_child(diplomacy_btn)
	hbox.move_child(diplomacy_btn, end_btn_idx)

	# Policies button (Empire only — Senate system)
	if GameManager.state.player_faction_id == &"empire":
		_create_policies_panel()
		var policies_btn := Button.new()
		policies_btn.name = "PoliciesButton"
		policies_btn.text = "Senate"
		policies_btn.custom_minimum_size = Vector2(90, 0)
		policies_btn.pressed.connect(_toggle_policies_panel)
		hbox.add_child(policies_btn)
		hbox.move_child(policies_btn, end_btn_idx + 1)

	# Research button — always insert before End Turn
	_create_research_panel()
	var research_btn := Button.new()
	research_btn.name = "ResearchButton"
	research_btn.text = "Research"
	research_btn.custom_minimum_size = Vector2(90, 0)
	research_btn.pressed.connect(_toggle_research_panel)
	hbox.add_child(research_btn)
	hbox.move_child(research_btn, end_turn_button.get_index())

	# "Currently Researching" label in top bar
	var research_status_lbl := Label.new()
	research_status_lbl.name = "ResearchStatusLabel"
	research_status_lbl.add_theme_font_size_override("font_size", 10)
	research_status_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	hbox.add_child(research_status_lbl)
	hbox.move_child(research_status_lbl, end_turn_button.get_index())
	_update_research_status_label()

	# Economy button — always insert before End Turn
	var economy_btn := Button.new()
	economy_btn.name = "EconomyButton"
	economy_btn.text = "Economy"
	economy_btn.custom_minimum_size = Vector2(90, 0)
	economy_btn.pressed.connect(_toggle_economy_panel)
	hbox.add_child(economy_btn)
	hbox.move_child(economy_btn, end_turn_button.get_index())

	# AI speed controls (after End Turn button)
	_skip_ai_btn = Button.new()
	_skip_ai_btn.name = "SkipAIButton"
	_skip_ai_btn.text = "Skip AI"
	_skip_ai_btn.custom_minimum_size = Vector2(70, 0)
	_skip_ai_btn.visible = false
	_skip_ai_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		TurnManager.skip_ai_turn = true
	)
	hbox.add_child(_skip_ai_btn)

	_speed_label = Label.new()
	_speed_label.name = "SpeedLabel"
	_speed_label.text = "1x"
	_speed_label.add_theme_font_size_override("font_size", 10)
	_speed_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	_speed_label.visible = false
	hbox.add_child(_speed_label)

	var speed_btn := Button.new()
	speed_btn.name = "SpeedButton"
	speed_btn.text = "Speed"
	speed_btn.custom_minimum_size = Vector2(60, 0)
	speed_btn.visible = false
	speed_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		if TurnManager.ai_speed_multiplier < 2.0:
			TurnManager.ai_speed_multiplier = 2.0
			_speed_label.text = "2x"
		elif TurnManager.ai_speed_multiplier < 4.0:
			TurnManager.ai_speed_multiplier = 4.0
			_speed_label.text = "4x"
		else:
			TurnManager.ai_speed_multiplier = 1.0
			_speed_label.text = "1x"
	)
	hbox.add_child(speed_btn)

	# Spacer to push End Turn to far right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	hbox.move_child(spacer, end_turn_button.get_index())

	# Create the economy panel itself
	economy_panel = PanelContainer.new()
	economy_panel.name = "EconomyPanel"
	economy_panel.visible = false

	economy_panel.anchor_left = 0.15
	economy_panel.anchor_right = 0.85
	economy_panel.anchor_top = 0.04
	economy_panel.anchor_bottom = 0.96
	economy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	economy_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	economy_panel.clip_contents = true

	economy_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	economy_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "EconomyVBox"
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(economy_panel)

func _toggle_economy_panel() -> void:
	if economy_panel.visible:
		economy_panel.visible = false
		_restore_game_panels_from_overlay()
	else:
		# Close other overlay panels if open
		if _diplomacy_panel and _diplomacy_panel.visible:
			_diplomacy_panel.visible = false
			if _diplo_detail_panel:
				_diplo_detail_panel.queue_free()
				_diplo_detail_panel = null
			_diplo_detail_faction = &""
		if _research_panel and _research_panel.visible:
			_research_panel.visible = false
		_hide_game_panels_for_overlay()
		_refresh_economy_panel()
		economy_panel.visible = true
		economy_panel.move_to_front()
		economy_panel.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_property(economy_panel, "modulate:a", 1.0, 0.2)

func _refresh_economy_panel() -> void:
	var scroll: ScrollContainer = economy_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("EconomyVBox")
	for child in vbox.get_children():
		child.queue_free()

	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return

	# Header
	_create_panel_header(vbox, "Economy Overview", economy_panel)

	# Section 1: City Income
	var city_header := Label.new()
	city_header.text = "City Income"
	city_header.add_theme_font_size_override("font_size", 14)
	city_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(city_header)

	var total_income: Dictionary = {}

	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null:
			continue
		var city_income := GameManager.city_system.calculate_city_income(city)
		var income_parts: Array[String] = []
		for res_type in city_income:
			if city_income[res_type] > 0:
				var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
				income_parts.append("+%d %s" % [city_income[res_type], rname])
				total_income[res_type] = total_income.get(res_type, 0) + city_income[res_type]

		var city_label := Label.new()
		var suffix := " (Capital)" if city.is_capital else ""
		city_label.text = "  %s%s (Lv%d)" % [city.get_display_name(), suffix, city.level]
		city_label.add_theme_font_size_override("font_size", 12)
		city_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(city_label)

		if income_parts.size() > 0:
			var income_text := Label.new()
			income_text.text = "    " + ", ".join(income_parts)
			income_text.add_theme_font_size_override("font_size", 11)
			income_text.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
			vbox.add_child(income_text)

		if city.is_under_siege:
			var siege_note := Label.new()
			var st := 5 if city.buildings.has(&"steppe_watchtower") else 4
			var sr := maxi(0, st - city.siege_turns)
			siege_note.text = "    (BESIEGED - no income, %d turns remaining)" % sr
			siege_note.add_theme_font_size_override("font_size", 11)
			siege_note.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
			vbox.add_child(siege_note)

	_add_separator(vbox)

	# Section 2: Military Upkeep
	var upkeep_header := Label.new()
	upkeep_header.text = "Military Upkeep"
	upkeep_header.add_theme_font_size_override("font_size", 14)
	upkeep_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(upkeep_header)

	var total_upkeep: Dictionary = {}
	var upkeep_by_tag: Dictionary = {} # tag -> {res_type: amount}

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id != player_id:
			continue
		for unit in army.units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud == null:
				continue
			var tag := "Other"
			for t in ["infantry", "ranged", "cavalry", "mage", "construct"]:
				if ud.tags.has(t):
					tag = t.capitalize()
					break
			if not upkeep_by_tag.has(tag):
				upkeep_by_tag[tag] = {}
			for res in ud.upkeep_cost:
				upkeep_by_tag[tag][res] = upkeep_by_tag[tag].get(res, 0) + ud.upkeep_cost[res]
				total_upkeep[res] = total_upkeep.get(res, 0) + ud.upkeep_cost[res]

	for tag in upkeep_by_tag:
		var parts: Array[String] = []
		for res_type in upkeep_by_tag[tag]:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			parts.append("-%d %s" % [upkeep_by_tag[tag][res_type], rname])
		var tag_label := Label.new()
		tag_label.text = "  %s: %s" % [tag, ", ".join(parts)]
		tag_label.add_theme_font_size_override("font_size", 12)
		tag_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
		vbox.add_child(tag_label)

	if upkeep_by_tag.is_empty():
		var no_upkeep := Label.new()
		no_upkeep.text = "  No military upkeep"
		no_upkeep.add_theme_font_size_override("font_size", 12)
		no_upkeep.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		vbox.add_child(no_upkeep)

	_add_separator(vbox)

	# Section 3: Net Income
	var net_header := Label.new()
	net_header.text = "Net Income per Turn"
	net_header.add_theme_font_size_override("font_size", 14)
	net_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(net_header)

	var all_resources: Dictionary = {}
	for res in total_income:
		all_resources[res] = true
	for res in total_upkeep:
		all_resources[res] = true

	for res_type in all_resources:
		var inc: int = total_income.get(res_type, 0)
		var upk: int = total_upkeep.get(res_type, 0)
		var net: int = inc - upk
		var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
		var net_label := Label.new()
		var sign_str := "+" if net >= 0 else ""
		net_label.text = "  %s: %s%d" % [rname, sign_str, net]
		net_label.add_theme_font_size_override("font_size", 13)
		if net > 0:
			net_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		elif net < 0:
			net_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
		else:
			net_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		vbox.add_child(net_label)

# ── Panel Style Helper ────────────────────────────────────────

func _create_panel_style() -> StyleBox:
	return GameManager.make_panel_style()

func _make_close_button(callback: Callable, btn_size: Vector2 = Vector2(30, 30)) -> Button:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = btn_size
	btn.pressed.connect(callback)
	return btn

func _make_label(text: String, font_size: int = 14, color: Color = Color.WHITE) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

func _create_panel_header(vbox: VBoxContainer, title_text: String, panel: PanelContainer, close_callback: Callable = Callable(), title_font_size: int = 16, title_color: Color = Color(0.95, 0.88, 0.55)) -> void:
	var header := HBoxContainer.new()
	var title := _make_label(title_text, title_font_size, title_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var cb: Callable = close_callback if close_callback.is_valid() else func(): panel.visible = false
	header.add_child(_make_close_button(cb))
	vbox.add_child(header)
	_add_separator(vbox)

# ── Diplomacy Panel ──────────────────────────────────────────

var _diplomacy_trade_panel: PanelContainer
var _diplomacy_trade_target: StringName = &""
var _diplomacy_gift_panel: PanelContainer
var _diplomacy_result_panel: PanelContainer
var _diplomacy_counter_offer_panel: PanelContainer
var _last_rejected_offer: Dictionary = {} # {target, action, ...offer details}
var _last_rejected_target: StringName = &""
var _diplo_tab_index: int = 0 # 0=Major, 1=Minor, 2=Independent Cities
var _diplo_detail_faction: StringName = &""
var _diplo_detail_panel: PanelContainer
var _diplo_selected_offers: Dictionary = {} # action_name -> bool
var _diplo_trade_params: Dictionary = {give_res = 0, give_amt = 20, recv_res = 1, recv_amt = 20, duration = 5}
var _diplo_gift_params: Dictionary = {resource = 0, amount = 15}
var _diplo_gift_mode: String = "resources" # "resources" or "items"
var _diplo_gift_item_id: StringName = &""
var _diplo_demand_params: Dictionary = {resource = 0, amount = 15}
var _diplo_city_offer_id: StringName = &""
var _diplo_city_demand_id: StringName = &""

func _create_diplomacy_panel() -> void:
	_diplomacy_panel = PanelContainer.new()
	_diplomacy_panel.name = "DiplomacyPanel"
	_diplomacy_panel.visible = false
	_diplomacy_panel.anchor_left = 0.01
	_diplomacy_panel.anchor_right = 0.99
	_diplomacy_panel.anchor_top = 0.01
	_diplomacy_panel.anchor_bottom = 0.99
	_diplomacy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_diplomacy_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_diplomacy_panel.clip_contents = true
	_diplomacy_panel.add_theme_stylebox_override("panel", _create_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	_diplomacy_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "DiplomacyVBox"
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(_diplomacy_panel)

func _hide_game_panels_for_overlay() -> void:
	_hidden_army_panel = army_panel.visible
	_hidden_city_panel = city_panel.visible
	if _hidden_army_panel:
		army_panel.visible = false
	if _hidden_city_panel:
		city_panel.visible = false

func _restore_game_panels_from_overlay() -> void:
	if _hidden_army_panel:
		army_panel.visible = true
		_hidden_army_panel = false
	if _hidden_city_panel:
		city_panel.visible = true
		_hidden_city_panel = false

func _toggle_diplomacy_panel() -> void:
	if _diplomacy_panel.visible:
		_diplomacy_panel.visible = false
		if _diplo_detail_panel:
			_diplo_detail_panel.queue_free()
			_diplo_detail_panel = null
		_diplo_detail_faction = &""
		_restore_game_panels_from_overlay()
	else:
		# Close other overlay panels if open
		if _research_panel and _research_panel.visible:
			_research_panel.visible = false
		if economy_panel and economy_panel.visible:
			economy_panel.visible = false
		_hide_game_panels_for_overlay()
		_check_tutorial("diplomacy_viewed")
		_diplo_detail_faction = &""
		_refresh_diplomacy_panel()
		_diplomacy_panel.visible = true
		_diplomacy_panel.move_to_front()
		_diplomacy_panel.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_property(_diplomacy_panel, "modulate:a", 1.0, 0.2)

const RELATION_NAMES := ["War", "Hostile", "Neutral", "Friendly", "Allied"]
const RELATION_COLORS := {
	0: Color(0.85, 0.2, 0.2),
	1: Color(0.85, 0.5, 0.2),
	2: Color(0.6, 0.6, 0.55),
	3: Color(0.3, 0.75, 0.4),
	4: Color(0.3, 0.5, 0.9),
}

func _refresh_diplomacy_panel() -> void:
	var scroll: ScrollContainer = _diplomacy_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("DiplomacyVBox")
	for child in vbox.get_children():
		child.queue_free()

	# If viewing a faction detail, show that instead
	if _diplo_detail_faction != &"":
		_build_faction_detail(vbox, _diplo_detail_faction)
		return

	_create_panel_header(vbox, "Diplomacy", _diplomacy_panel)

	# Tab buttons
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var tab_names := ["Major Factions", "Minor Factions", "Independent Cities"]
	for i in tab_names.size():
		var tab_btn := Button.new()
		tab_btn.text = tab_names[i]
		tab_btn.custom_minimum_size = Vector2(140, 30)
		if i == _diplo_tab_index:
			tab_btn.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		else:
			tab_btn.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
		var idx: int = i
		tab_btn.pressed.connect(func():
			_diplo_tab_index = idx
			_refresh_diplomacy_panel()
		)
		tab_row.add_child(tab_btn)
	vbox.add_child(tab_row)
	_add_separator(vbox)

	var player_id := GameManager.state.player_faction_id

	if _diplo_tab_index == 0:
		_build_diplo_faction_list(vbox, player_id, true) # major factions
	elif _diplo_tab_index == 1:
		_build_diplo_faction_list(vbox, player_id, false) # minor factions
	else:
		_build_diplo_independent_list(vbox, player_id)

func _is_major_faction(faction_id: StringName) -> bool:
	return not GameManager.MINOR_FACTION_PARENTS.has(faction_id) and not GameManager.is_npc_faction(faction_id)

func _build_diplo_faction_list(vbox: VBoxContainer, player_id: StringName, major_only: bool) -> void:
	var has_any := false
	var encountered := GameManager.state.encountered_factions
	for faction_id in GameManager.state.faction_states:
		if faction_id == player_id or GameManager.is_npc_faction(faction_id):
			continue
		# Only show factions the player has encountered
		if not encountered.has(faction_id):
			continue
		var fs: FactionState = GameManager.state.faction_states[faction_id]
		if fs.is_defeated:
			continue
		var fd: FactionData = DataManager.get_faction(faction_id)
		if fd == null:
			continue
		var is_major := _is_major_faction(faction_id)
		if major_only and not is_major:
			continue
		if not major_only and is_major:
			continue

		has_any = true
		var relation := GameManager.get_relation(player_id, faction_id)
		var standing := GameManager.diplomacy_system.get_standing(player_id, faction_id)
		_build_diplo_faction_row(vbox, faction_id, fd, relation, standing)

	if not has_any:
		var none_lbl := Label.new()
		if encountered.is_empty():
			none_lbl.text = "  No factions encountered yet. Explore the map!"
		else:
			none_lbl.text = "  No factions in this category."
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.48, 0.45))
		vbox.add_child(none_lbl)

func _build_diplo_faction_row(vbox: VBoxContainer, faction_id: StringName, fd: FactionData, relation: int, standing: int) -> void:
	var player_id := GameManager.state.player_faction_id
	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.12, 0.11, 0.14, 0.8)
	row_style.border_width_left = 3
	row_style.border_color = fd.color
	row_style.corner_radius_top_left = 3
	row_style.corner_radius_bottom_left = 3
	row_style.corner_radius_top_right = 3
	row_style.corner_radius_bottom_right = 3
	row_style.content_margin_left = 8.0
	row_style.content_margin_top = 6.0
	row_style.content_margin_right = 8.0
	row_style.content_margin_bottom = 6.0
	row_panel.add_theme_stylebox_override("panel", row_style)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)

	# Faction color dot
	var color_rect := ColorRect.new()
	color_rect.custom_minimum_size = Vector2(14, 14)
	color_rect.color = fd.color
	info_row.add_child(color_rect)

	# Faction name
	var name_label := Label.new()
	name_label.text = fd.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	info_row.add_child(name_label)

	# Treaty icons — small colored symbols showing active agreements
	var treaty_icons := _build_treaty_icons(player_id, faction_id)
	if treaty_icons:
		info_row.add_child(treaty_icons)

	# Relation badge
	var rel_label := Label.new()
	rel_label.text = RELATION_NAMES[relation]
	rel_label.add_theme_font_size_override("font_size", 12)
	rel_label.add_theme_color_override("font_color", RELATION_COLORS.get(relation, Color.WHITE))
	rel_label.custom_minimum_size = Vector2(55, 0)
	info_row.add_child(rel_label)

	# Standing
	var standing_label := Label.new()
	var s_prefix: String = "+" if standing > 0 else ""
	standing_label.text = "[%s%d]" % [s_prefix, standing]
	standing_label.add_theme_font_size_override("font_size", 11)
	if standing > 0:
		standing_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
	elif standing < 0:
		standing_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	else:
		standing_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	standing_label.custom_minimum_size = Vector2(40, 0)
	standing_label.mouse_filter = Control.MOUSE_FILTER_STOP
	# Build standing breakdown tooltip
	var log: Array = GameManager.diplomacy_system.get_standing_log(player_id, faction_id)
	if log.size() > 0:
		var tip_lines: PackedStringArray = PackedStringArray()
		tip_lines.append("Standing Breakdown:")
		tip_lines.append("─────────────────────")
		# Aggregate by reason
		var aggregated: Dictionary = {} # reason -> total_delta
		for entry in log:
			var reason: String = entry.get("reason", "Unknown")
			var delta: int = entry.get("delta", 0)
			aggregated[reason] = aggregated.get(reason, 0) + delta
		# Sort by absolute value (biggest impact first)
		var sorted_reasons: Array = aggregated.keys()
		sorted_reasons.sort_custom(func(a, b): return absi(aggregated[a]) > absi(aggregated[b]))
		for reason in sorted_reasons:
			var total: int = aggregated[reason]
			var prefix: String = "+" if total > 0 else ""
			tip_lines.append("%s%d  %s" % [prefix, total, reason])
		tip_lines.append("─────────────────────")
		tip_lines.append("Total: %s%d" % [s_prefix, standing])
		standing_label.tooltip_text = "\n".join(tip_lines)
	else:
		standing_label.tooltip_text = "Standing: %s%d\nNo recorded history yet." % [s_prefix, standing]
	info_row.add_child(standing_label)

	# View button
	var view_btn := Button.new()
	view_btn.text = "View"
	view_btn.custom_minimum_size = Vector2(50, 26)
	var fid: StringName = faction_id
	view_btn.pressed.connect(func():
		_diplo_detail_faction = fid
		_diplo_selected_offers.clear()
		_diplo_trade_params = {give_res = 0, give_amt = 20, recv_res = 1, recv_amt = 20, duration = 5}
		_diplo_gift_params = {resource = 0, amount = 15}
		_diplo_gift_mode = "resources"
		_diplo_gift_item_id = &""
		_diplo_demand_params = {resource = 0, amount = 15}
		_refresh_diplomacy_panel()
	)
	info_row.add_child(view_btn)

	row_panel.add_child(info_row)
	vbox.add_child(row_panel)

func _build_treaty_icons(player_id: StringName, faction_id: StringName) -> HBoxContainer:
	var treaties_with: Array[TreatyInstance] = []
	for treaty_id in GameManager.state.diplomacy_state.treaties:
		var treaty: TreatyInstance = GameManager.state.diplomacy_state.treaties[treaty_id]
		var involves_player := treaty.faction_a == player_id or treaty.faction_b == player_id
		var involves_target := treaty.faction_a == faction_id or treaty.faction_b == faction_id
		if involves_player and involves_target:
			treaties_with.append(treaty)
	if treaties_with.is_empty():
		return null
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	var tooltip_lines: PackedStringArray = PackedStringArray()
	tooltip_lines.append("Active Agreements:")
	tooltip_lines.append("──────────────────")
	for treaty in treaties_with:
		var icon := Label.new()
		icon.add_theme_font_size_override("font_size", 12)
		match treaty.treaty_type:
			Enums.TreatyType.PEACE:
				icon.text = "P"
				icon.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
				var turns_str := "%d turns left" % treaty.turns_remaining if treaty.turns_remaining > 0 else "permanent"
				tooltip_lines.append("Peace Treaty (%s)" % turns_str)
			Enums.TreatyType.ALLIANCE:
				icon.text = "A"
				icon.add_theme_color_override("font_color", Color(0.4, 0.6, 0.95))
				tooltip_lines.append("Alliance")
			Enums.TreatyType.TRADE_DEAL:
				icon.text = "T"
				icon.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
				var give_res: int = treaty.terms.get("give_resource", 0)
				var give_amt: int = treaty.terms.get("give_amount", 0)
				var recv_res: int = treaty.terms.get("receive_resource", 0)
				var recv_amt: int = treaty.terms.get("receive_amount", 0)
				var is_a := treaty.faction_a == player_id
				var g_name: String = RESOURCE_NAMES[give_res] if give_res >= 0 and give_res < RESOURCE_NAMES.size() else "?"
				var r_name: String = RESOURCE_NAMES[recv_res] if recv_res >= 0 and recv_res < RESOURCE_NAMES.size() else "?"
				if is_a:
					tooltip_lines.append("Trade: Give %d %s, Receive %d %s" % [give_amt, g_name, recv_amt, r_name])
				else:
					tooltip_lines.append("Trade: Give %d %s, Receive %d %s" % [recv_amt, r_name, give_amt, g_name])
			Enums.TreatyType.TRADE_RELATIONS:
				icon.text = "R"
				icon.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3))
				var turns_active: int = treaty.terms.get("turns_active", 0)
				tooltip_lines.append("Trade Relations (active %d turns)" % turns_active)
			Enums.TreatyType.NON_AGGRESSION_PACT:
				icon.text = "N"
				icon.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85))
				var turns_str := "%d turns left" % treaty.turns_remaining if treaty.turns_remaining > 0 else "permanent"
				tooltip_lines.append("Non-Aggression Pact (%s)" % turns_str)
			Enums.TreatyType.FREE_PASSAGE:
				icon.text = "F"
				icon.add_theme_color_override("font_color", Color(0.5, 0.85, 0.7))
				var fp_turns_str := "%d turns left" % treaty.turns_remaining if treaty.turns_remaining > 0 else "permanent"
				tooltip_lines.append("Free Passage (%s)" % fp_turns_str)
			Enums.TreatyType.TRIBUTARY:
				icon.text = "$"
				icon.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
				var is_overlord := treaty.faction_a == player_id
				if is_overlord:
					tooltip_lines.append("Tributary (they pay you)")
				else:
					tooltip_lines.append("Tributary (you pay them)")
		icon.custom_minimum_size = Vector2(14, 0)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(icon)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.tooltip_text = "\n".join(tooltip_lines)
	return hbox

func _build_diplo_independent_list(vbox: VBoxContainer, player_id: StringName) -> void:
	# Group independent cities by culture region
	var culture_cities: Dictionary = {} # culture_name -> Array of CityState
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != &"independent":
			continue
		var culture: StringName = GameManager.REGION_CULTURE.get(city.region_id, &"unknown")
		if not culture_cities.has(culture):
			culture_cities[culture] = []
		culture_cities[culture].append(city)

	if culture_cities.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "  No independent cities remain."
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.48, 0.45))
		vbox.add_child(none_lbl)
		return

	for culture_id in culture_cities:
		var culture_label := Label.new()
		culture_label.text = str(culture_id).capitalize() + " Culture"
		culture_label.add_theme_font_size_override("font_size", 13)
		culture_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(culture_label)

		var standing := 0
		if GameManager.diplomacy_system.has_method("get_standing"):
			standing = GameManager.diplomacy_system.get_standing(player_id, culture_id)

		var standing_lbl := Label.new()
		var s_prefix: String = "+" if standing > 0 else ""
		standing_lbl.text = "  Culture standing: %s%d (join at 40)" % [s_prefix, standing]
		standing_lbl.add_theme_font_size_override("font_size", 11)
		if standing >= 40:
			standing_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		elif standing > 0:
			standing_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.5))
		else:
			standing_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
		vbox.add_child(standing_lbl)

		var cities: Array = culture_cities[culture_id]
		for city in cities:
			var city_row := HBoxContainer.new()
			city_row.add_theme_constant_override("separation", 6)
			var city_label := Label.new()
			city_label.text = "    " + city.get_display_name()
			city_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			city_label.add_theme_font_size_override("font_size", 12)
			city_row.add_child(city_label)

			var region_data: RegionData = DataManager.get_region(city.region_id)
			var region_name: String = region_data.display_name if region_data else str(city.region_id)
			var region_lbl := Label.new()
			region_lbl.text = region_name
			region_lbl.add_theme_font_size_override("font_size", 11)
			region_lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
			city_row.add_child(region_lbl)
			vbox.add_child(city_row)

		_add_separator(vbox)

# ── Faction Detail Screen ──────────────────────────────────────

func _get_dialogue_faction(faction_id: StringName) -> StringName:
	## For minor factions, return parent faction ID for dialogue lookups
	var parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, &"")
	if parent != &"":
		return parent
	return faction_id

func _get_standing_stage(standing: int) -> int:
	## Returns 0-4: strong_dislike, dislike, neutral, like, strong_like
	if standing <= -50:
		return 0
	elif standing <= -15:
		return 1
	elif standing <= 15:
		return 2
	elif standing <= 50:
		return 3
	else:
		return 4

const STANDING_STAGE_NAMES := ["Despised", "Disliked", "Neutral", "Liked", "Admired"]

# Standing-based greeting lines per faction (5 stages, 5 variations each)
const LEADER_GREETINGS := {
	&"empire": [
		["The Empire has no words for vermin like you.", "You pollute the court with your very presence.", "Guards — why was this wretch allowed past the gates?", "The throne room is no place for crawling things.", "Speak and be gone, before the Emperor's patience runs dry."],
		["You dare approach the throne? Speak quickly, and leave quicker.", "The Empire tolerates your presence. Barely.", "Make your case swiftly. The court has little time for you.", "Another petitioner. How tiresome. What is it?", "The Chancellor advises brevity. I advise obedience."],
		["State your business with the Empire.", "The Imperial court acknowledges your arrival. Proceed.", "You have the floor. Use it wisely.", "The Empire is listening. What brings you to our borders?", "An audience has been granted. Speak your mind."],
		["The Empire remembers its friends. What do you seek?", "A welcome face in the court. How may the Empire assist?", "The Chancellor speaks well of you. What is your request?", "Your reputation precedes you — favorably, for once.", "The Empire values this partnership. Name your terms."],
		["Hail, most honored ally! The Emperor himself welcomes you.", "The Imperial banner flies in your honor today!", "Dearest friend of the Crown — the court celebrates your arrival!", "The Emperor has prepared a feast. You are family to us now.", "In all the realm, no ally stands higher. Welcome, cherished friend!"],
	],
	&"skulloath": [
		["Your bones will hang from our standards before the day ends.", "Death rides with us, and it hungers for you.", "Another fool crawls before the Bone Throne. You have five breaths.", "The carrion birds already circle above your head.", "Kneel before the death-riders or be trampled beneath our hooves."],
		["The steppe has no patience for the living who waste our time.", "You are not yet worthy of an audience with the dead.", "Death watches you with mild curiosity. Be brief.", "The bone-riders tolerate your presence. For now.", "Hmph. The grave has not yet called your name. Speak."],
		["Speak, outsider. The Bone Throne listens.", "The death-drums are silent. We may talk.", "You stand before the Bone Throne. State your purpose.", "Death neither claims nor releases you. An interesting position.", "The horde neither welcomes nor rejects you. Prove your worth."],
		["You carry the mark of death with honor. The horde respects this.", "Ha! You do not fear the grave. I am pleased.", "The death-spirits nod in approval. Sit by our pyre.", "A strong arm and no fear of dying — the horde asks nothing more.", "You understand that death is not an end. Welcome, friend."],
		["Blood brother! The death-riders raise their skulls to you!", "BROTHER OF THE BONE STEPPE! The dead themselves sing our bond!", "You ride with death as one of us! The horde is yours to command!", "The Khan would ride to the grave and back for you!", "In all the steppe, no bond outlasts death — except ours, blood and bone!"],
	],
	&"gladehost": [
		["The roots remember every wound you have inflicted upon the grove.", "The canopy darkens at your approach. The forest knows what you are.", "Even the stones recoil from your footsteps.", "Trespasser. The wild things whisper warnings of your coming.", "The oldest tree bends away from you. That tells me everything."],
		["The thorns bristle at your approach. Tread carefully.", "The forest endures your presence, but only barely.", "Even weeds have their place. Perhaps you have yours.", "The canopy permits a sliver of light for you. No more.", "The grove watches you with a hundred silent eyes."],
		["The grove listens. Speak.", "The wind carries your words to every leaf. Choose them wisely.", "Neither root nor branch opposes you. That is something.", "The forest stands in quiet judgment. What do you bring?", "You walk between the trees without harming them. Acceptable."],
		["The forest welcomes you, kindred spirit.", "The oldest oak extends a branch in your direction. A rare honor.", "Birdsong follows your steps. The grove approves.", "You understand the balance. That is why the forest opens to you.", "The dryads speak your name with warmth. Welcome, friend of the wild."],
		["Beloved friend of the wild — the ancient trees sing your name.", "The Great Root itself stirs in joy at your arrival!", "Every flower blooms in your wake. The forest loves you as its own.", "The spirit of the ancient grove embraces you. You are sacred to us.", "In ten thousand seasons, the forest has known few friends as true as you."],
	],
	&"moonspear": [
		["The night has eyes, and they despise what they see in you.", "The moon veils itself from your presence. A dire omen.", "Even the shadows recoil from something as base as you.", "The Lunar Order foresaw your coming. We prepared accordingly.", "Your shadow is crooked. The night reveals all such flaws."],
		["The moon casts a cold shadow upon you. State your purpose.", "The night watches you with suspicion. Be brief.", "Silver light reveals all truths. Yours are not flattering.", "The Order permits your audience, but the sentinels remain alert.", "You walk clumsily through our darkness. Try not to stumble."],
		["What brings you to the Lunar Order? Speak.", "The night is calm. A reasonable time for discourse.", "Neither marked nor shunned by moonlight. An honest position.", "The Order listens without judgment. For now.", "Step into the silver light and say your piece."],
		["The moon illuminates your path, friend. You are welcome here.", "The night sentinels lower their guard for you. A rare honor.", "Moonlight follows your steps like a faithful companion.", "The Order speaks well of you in the silent halls.", "You move through shadow with grace. The Lunar Order approves."],
		["The moon itself parts the clouds to greet you, most honored ally!", "The Lunar Order opens every secret passage to you!", "In all the ages of the night, no friend has earned such trust!", "The stars rearrange themselves in your honor!", "Shadow and moonlight alike bow before our bond. Welcome, sacred friend!"],
	],
	&"thunderswarm": [
		["My war-beast will eat you alive, worm. Speak before I unleash it.", "Even the dragons would not waste their fire on something so pitiful.", "Last visitor who looked at me like that was fed to the drakes.", "The storm gathers for weaklings like you. Run while you can.", "Your skull will make a fine trophy on my beast's saddle."],
		["You smell of weakness. State your purpose before my drake loses patience.", "Hmm. You are less pathetic than the last one. Slightly.", "The highland clans do not bend for ants. Be quick.", "I was feeding my war-beast. This better be worth interrupting.", "Talk fast. My beasts grow restless and hungry."],
		["The storm clans care not for pleasantries. Speak.", "The highland wind carries no judgment today. Say your piece.", "You stand on the mountain without trembling. That is enough.", "Thunder rumbles in the distance. Let us talk before the beasts stir.", "Neither friend nor foe. The storm watches and waits."],
		["Ha! A worthy ally approaches! Come, meet my war-drake!", "You fight well and speak true! The highland clans respect that!", "The dragons roar greeting, not challenge. That means something.", "Come! Sit by the bonfire! Let us plan great raids!", "The storm drums beat a welcome rhythm for you, beast-friend!"],
		["BROTHER OF THE STORM! Let thunder and dragon-fire shake the earth!", "THE HIGHLAND BEASTS ROAR WITH JOY! Welcome, greatest of allies!", "My finest drake would carry you into battle! That is the highest honor!", "LIGHTNING AND DRAGON-FIRE! There is no one I would rather ride with!", "By every peak, every storm, and every beast — you are LEGEND!"],
	],
	&"tainted_jade": [
		["Your blood will feed the jungle. This is your only purpose.", "The vines are already reaching for your ankles. Can you feel them?", "Poison drips from every leaf above you. One wrong word...", "The jungle consumes all intruders. You are no exception.", "The Serpent Queen does not receive prey. She devours it."],
		["Careful where you tread. The jungle has teeth.", "The canopy closes above you. Deliberate? Perhaps.", "Every shadow here has scales. Remember that.", "You are tolerated in this garden. Do not mistake tolerance for welcome.", "The serpents coil but do not yet strike. Choose your words."],
		["The jade throne acknowledges your presence.", "The jungle neither threatens nor embraces. Speak.", "The Serpent Queen inclines her head. A measured greeting.", "You walk the jungle path with adequate caution. Proceed.", "The venomous things keep their distance. That is as close to welcome as we offer."],
		["The serpent coils gently for those it favors.", "The rarest orchid blooms at your arrival. The jungle approves.", "Warm-blooded but wise. The jungle values that combination.", "The Serpent Queen offers you shade and clean water. High praise.", "Even the most venomous creatures know not to harm you. You are protected here."],
		["The jungle parts before you, honored one. The Serpent Queen extends her trust.", "The heart of the jungle beats in time with yours. You are one of us.", "Every vine, every fang, every drop of venom — all yours to command, dear friend.", "In ten thousand years, the jungle has embraced only a handful. You are among them.", "The Serpent Crown itself could rest upon your brow. That is how deeply you are treasured."],
	],
	&"cinderguard": [
		["Leave, before I feed you to the furnace.", "The slag pit is always hungry. Do you wish to meet it?", "Every moment you stand here, the forge grows hotter. Take the hint.", "I have melted better things than you today.", "Your presence cools the forge. That is the gravest insult I know."],
		["You stand in the shadow of the Great Forge. Choose your words wisely.", "The bellows pause for no one. Make it quick.", "Hmph. Untempered and brittle. But I will hear you.", "The anvil rings impatiently. State your business.", "You have the resilience of tin. But tin has its uses. Speak."],
		["The Forgemaster has a moment. Make it count.", "Iron cares not for flattery. Give me substance.", "The forge burns at a steady heat. A good time to talk.", "You stand in the foundry without flinching. That earns a moment.", "Neither ore nor slag. Let us determine which you become."],
		["The forges burn bright for allies. Welcome.", "Good steel recognizes good steel. I see quality in you.", "The master smiths nod at your approach. High praise indeed.", "You have proven yourself in the fire. Welcome to the foundry.", "The warmth of the forge is yours tonight, friend. Sit and speak freely."],
		["The heart of the mountain opens to you, truest friend of the forge!", "You are steel made perfect — tested, tempered, and TRUE!", "The Great Anvil rings with joy! No finer ally exists in all the world!", "Every weapon we forge carries a blessing for you. THAT is our bond!", "In fire and iron, in hammer and anvil — our friendship is eternal!"],
	],
	&"forsaken": [
		["Your flesh will rot sweetly in our domain. Come closer.", "How delightful — fresh meat walks willingly into the plague ward.", "The blight hungers. You look... ripe for infection.", "Even the diseased turn away from you. Consider what that means.", "Your screams will join the chorus of the afflicted."],
		["Your presence offends what remains of our senses.", "We have endured the plague. We can endure you. Barely.", "The corruption whispers your name with distaste.", "How tedious. Another healthy thing demanding attention.", "You carry the stench of hope. How nauseating."],
		["The Plague Council deigns to listen. Briefly.", "Disease is patient. We can spare a moment.", "You are neither afflicted nor immune. Simply... present.", "The blighted make room for your words. A rare allowance.", "Speak. We will decide if your words are worth the infection risk."],
		["Even among the diseased, some visitors are tolerable. You are one.", "The plague makes exceptions for those who understand survival.", "You do not recoil from our affliction. That makes you... interesting.", "The outcasts speak your name without malice. Almost warmly.", "In all our suffering, your presence is... appreciated."],
		["In all our plague-touched exile, you are a rare constant. The Forsaken salute you.", "The Council of the Afflicted itself stirs to greet you!", "You have given purpose to the outcast. The Forsaken THANK you.", "Disease and survival bow before this friendship. You transcend the blight.", "Across every plague, every exile — you stood with us. We are forever grateful."],
	],
	&"ivoryscar": [
		["The tombs have foreseen your ruin. Grovel while you still can.", "The dead will scour your name from history.", "The ancestors spit at the mention of you.", "Every relic we unearth carries a new curse with your name on it.", "The bone-readers cast your fortune. They wept."],
		["The gaze of the entombed falls upon you. Be still.", "The necropolis measures all who enter. You are found wanting.", "Ancient dead watch from their alcoves. They are not impressed.", "The scarabs click their displeasure. Tread carefully.", "The relics hum with unease at your approach."],
		["The relics whisper. What do you bring to the seekers?", "The sands of the necropolis run evenly. A balanced moment.", "The entombed neither warn nor welcome. Speak your case.", "The tomb doors are open. Enter and state your purpose.", "The relic-seekers turn to you without judgment. Proceed."],
		["The tombs reveal a favorable future for us both.", "The sands shift in your favor. The dead take note.", "Ancient relics glow warmly at your approach. A good sign.", "The scarabs arrange themselves in a pattern of welcome.", "The bone-readers smile. Your fortune among the dead reads bright, friend."],
		["The ancestors themselves approve! Walk among the tombs as honored kin.", "The dead see you enthroned beside us! Greatest of all allies!", "Ten thousand years of buried wisdom agree — you are WORTHY!", "The relics sing for the first time in centuries. All for you!", "Walk the Hall of Ages as family. The dead embrace you across time itself!"],
	],
	&"shardhorde": [
		["Your bones will make poor shard-holders. But we will try anyway.", "The horde sees nothing of value in you. Only meat for the crystal pits.", "Another outsider stumbles into our camp. The shards grow restless.", "You reek of weakness. The crystals reject your kind.", "Speak fast, or the shard-wolves will pick your carcass clean."],
		["The horde has little patience for shard-less wanderers. Be brief.", "You carry no crystals worth taking. Disappointing.", "The Shardlord watches you with contempt. Choose your words.", "Your presence offends the shards we carry. Make it quick.", "The horde tolerates you. For now. Do not push your luck."],
		["The Shardhorde listens. State your purpose.", "The crystal fires burn low. A calm time to talk.", "You stand before the horde without trembling. That is something.", "Neither enemy nor ally. The shards have not yet decided.", "The horde makes camp. You may approach and speak."],
		["Ha! You bring worthy crystals to trade. The horde approves.", "The shards resonate warmly in your presence. A good sign.", "You understand the value of crystal-power. The horde respects this.", "The Shardlord offers you a seat by the shard-fire. Welcome, friend.", "Your offerings please the horde. You have earned our respect."],
		["SHARD-BROTHER! The crystals BLAZE with power at your arrival!", "The mightiest shards in our horde glow for YOU! Greatest of allies!", "The Shardlord would shatter his own crystals before breaking this bond!", "Every shard-bearer in the horde roars your name! You are ONE OF US!", "In all the horde's wanderings, no bond has burned brighter. Blood and crystal!"],
	],
	&"sunblessed": [
		["The Eternal Sun burns away all heresy. You are heresy.", "The sacred flame recoils at your faithlessness.", "Even dawn cannot redeem what you are. The pilgrims avert their eyes.", "The light of the Sun reveals your every sin. There are many.", "You stand before the faithful and cast nothing but shadow."],
		["The pilgrims judge you and find you wanting.", "The light of the Sun permits your approach, but does not bless it.", "Dawn's warmth does not reach everyone. Not yet you.", "The pilgrim road is open, but the faithful dim their lanterns.", "The Sun sees all. What it sees in you gives the faithful pause."],
		["Walk the pilgrim road, stranger. What do you seek?", "The sacred flame burns evenly. A time for fair words.", "Neither heretic nor faithful stands before us. Simply a traveler.", "The pilgrimage offers rest and water to all travelers. Even you.", "The Sun casts no judgment today. Speak freely."],
		["The Sun shines upon the righteous. Welcome, friend.", "Your spirit burns with a pilgrim's fervor. The faithful approve.", "The sacred flame bends toward you as a flower to the dawn.", "Dawn breaks a little brighter when you visit our sanctum.", "The pilgrims speak your name in the morning prayers. Welcome."],
		["By the Eternal Dawn, you are radiant! The Blessed greet you as family!", "THE SUN ITSELF BLAZES IN YOUR HONOR! Most sacred of allies!", "You carry the holy light within you! The pilgrims weep with joy!", "In all the ages of the Sun, no friend has burned so brightly!", "The Eternal Dawn proclaims you BLESSED among the faithful!"],
	],
}

# Culture-specific greetings: speaker reacts differently based on player's faction
# Structure: {speaker_fid: {player_fid: [[stage0_vars], [stage1_vars], ...]}}
# Mixed into random pool alongside generic LEADER_GREETINGS
const CULTURE_GREETINGS := {
	&"empire": {
		&"skulloath": [
			["Another savage from the bone-scattered steppe. The Empire has no words for horse-eaters.", "Your horde's stench precedes you, rider. The court recoils."],
			["The Khan sends a rider instead of an army. How restrained.", "We tolerate the steppe-folk. For now."],
			["Riders of the steppe. Your ways are strange, but the Empire listens.", "Horsemen of the bone throne — state your terms."],
			["The Khan's courage has earned Imperial respect. What brings you, warrior?", "Few barbarians earn a seat at the Imperial table. You are one."],
			["Mighty Khan! The Empire and the Horde stand as brothers in arms!", "From the steppe to the throne room — our bond defies all tradition!"],
		],
		&"gladehost": [
			["Go back to your trees, leaf-lover. The Empire has no use for moss and moonlight.", "Your grove burns easily. Remember that before you speak."],
			["The forest-folk come begging again? How predictable.", "We will hear you, druid. But keep your vines off the furniture."],
			["Envoy of the grove. The Empire respects the old ways, if not the old stubbornness.", "The forest and the Empire have coexisted for centuries. Let us continue."],
			["The wisdom of the grove has served us well, friend. Welcome.", "The Empire values its bond with the natural world. Speak freely."],
			["Beloved guardian of the forests! The Empire pledges to protect the grove as our own!", "Nature and civilization, hand in hand! Our alliance is the envy of the world!"],
		],
		&"forsaken": [
			["Abomination. The dead should stay dead, and you should crawl back to your pit.", "The stench of the void clings to you. The court recoils."],
			["The Empire tolerates many things. Your kind tests those limits.", "Speak your piece, hollow one. And try not to shed any parts."],
			["The void-touched. An unusual people, but the Empire deals with all nations.", "Whatever you are, dead or alive, you have the floor."],
			["Your persistence is admirable, void-walker. The Empire has come to appreciate it.", "The Forsaken have proven reliable, if unconventional. Welcome."],
			["Even the void cannot dim the warmth we feel for you! The Empire embraces even death as ally!", "Who would have thought? The living and the dead, the closest of friends!"],
		],
		&"sunblessed": [
			["Your zealotry blinds you, sun-worshipper. The Empire bows to no god.", "Take your sermons elsewhere. The throne answers to no temple."],
			["The Blessed and their eternal preaching. The Crown grows weary.", "Your sun-faith is noted. Now speak of politics, not prayers."],
			["The Sunblessed. Your faith is strong, if perhaps excessive. The Empire listens.", "Sun-priest, the Empire walks in reason's light. But we can talk."],
			["Your devotion inspires even the skeptics at court. Welcome, friend of the dawn.", "The Empire finds common ground with the Blessed more often than expected."],
			["Blessed of the sun! Crown and Temple united in glory!", "Your light has illuminated our greatest victories. Eternal thanks!"],
		],
	},
	&"skulloath": {
		&"empire": [
			["City-dweller. Your walls cannot protect you from what rides the steppe.", "The Khan does not kneel to emperors. Especially weak ones."],
			["Your civilization makes warriors soft. I see it in your posture.", "The Empire sends a perfumed messenger. How like them."],
			["Imperial. Your walls are strong, I grant you that.", "The Empire's coin is good. I will listen."],
			["For a city-dweller, you have iron in your spine. The Khan approves.", "The Empire sends warriors, not merchants. Good. We can talk."],
			["Imperial brother! Even stone walls cannot contain the bond between us!", "The Khan and the Emperor — steppe and city, united as one!"],
		],
		&"thunderswarm": [
			["Mountain-screamers. Your thunder is nothing compared to the horde's hooves.", "Storm-boy. Come down from your peak and fight on flat ground."],
			["The Swarm thinks they are warriors. The steppe knows better.", "Highland raiders. Better than most, but still beneath the horde."],
			["Storm-kin. You fight well, I give you that.", "Mountain warriors and steppe riders — two sides of the same blade."],
			["HA! Storm-brother! Your axes are almost as sharp as our sabres!", "The Swarm has earned a place at our fire. Drink!"],
			["THUNDER AND HOOVES! Our combined might makes the world TREMBLE!", "Storm-sibling! No force on earth can stand against us together!"],
		],
		&"gladehost": [
			["Tree-hugger. Your roots cannot stop a charging horse.", "The forest hides cowards. Come out and fight, leaf-eater."],
			["The grove sends a druid instead of a warrior. Disappointing.", "Your trees are good for arrow shafts, at least."],
			["Forest-walker. Your scouts are skilled, I admit.", "The grove is strange, but the Khan respects cunning."],
			["Ha! Your forest-fighters are sneakier than my best scouts! Respect!", "The grove proves that courage wears many skins. Welcome, friend."],
			["The wild and the steppe — both untamed, both FREE! Kindred spirits!", "Nature-friend! The horde rides with the wind, and the wind is yours!"],
		],
		&"cinderguard": [
			["Forge-rat. Your walls will melt when the horde brings fire of our own.", "You hide behind iron and stone. The Khan despises cowards."],
			["Your blades are good. Your courage? Not impressed.", "The forgers cower behind their walls. Typical."],
			["Forge-master. Your steel is worthy of the horde's respect.", "The Khan admires your weapons, if not your fortress-hiding."],
			["Your blades arm my riders well! The forge earns the horde's respect!", "Iron-friend! The Khan values good steel and the hands that forge it!"],
			["FORGE-BROTHER! Your steel and our riders — an unstoppable force!", "The Khan treasures your friendship as he treasures his finest blade!"],
		],
	},
	&"gladehost": {
		&"cinderguard": [
			["The smoke of your forges poisons every living thing. The grove DESPISES you.", "Every tree you burn for your furnaces screams. Can you hear them?"],
			["The forge-fires dim the sky above the canopy. The grove is displeased.", "Your soot-stained hands bring nothing green with them."],
			["Forge-keeper. The grove wishes you would contain your flames.", "Fire and forest have always been wary neighbors. What do you seek?"],
			["You have shown the forest that not all flames destroy. Welcome, forge-friend.", "The grove has learned that some fires nurture as well as burn."],
			["Fire-keeper! The grove sees now that flame and forest need each other!", "From enmity to harmony — forge and forest, an alliance of miracles!"],
		],
		&"forsaken": [
			["Where you walk, nothing grows. The grove ABHORS your existence.", "Blight-carrier. Your very shadow kills the grass beneath it."],
			["The roots recoil from your touch. The forest barely tolerates you.", "Every dead thing in the forest reminds us of your people."],
			["Void-touched. The grove does not understand you, but will listen.", "Life and death are connected. Perhaps we can speak across that bridge."],
			["The forest has learned that even decay returns nutrients to the soil. Welcome.", "You walk among dead things, yet you speak with unexpected gentleness."],
			["From death springs new growth! The grove embraces you as part of the cycle!", "Life and void, intertwined like root and stone! Our bond transcends nature!"],
		],
		&"tainted_jade": [
			["You defile nature with your venoms and corruption. The grove sees what you are.", "Poisoned nature is worse than no nature at all. The grove rejects you."],
			["The serpent's jungle is nature twisted. The grove watches with unease.", "Your vines strangle where ours embrace. There is a difference."],
			["Serpent-keeper. We share green things, if little else.", "Your jungle is different. But the grove acknowledges the connection."],
			["The grove sees that your poison has purpose. Nature takes many forms.", "Venom and vine, predator and prey — both part of the wild. Welcome, cousin."],
			["Wild cousin! Grove and jungle are two faces of the same eternal forest!", "From lightest blossom to darkest venom — all nature is ONE!"],
		],
		&"empire": [
			["Your roads carve scars through the forest. The grove will NEVER forgive.", "Imperial axe-bearers. Your ambition devours everything green."],
			["The Empire's borders creep ever closer to the ancient groves. We watch.", "Your carriages crush wildflowers. Your progress is the grove's pain."],
			["Imperial envoy. The grove hopes your expansion respects the treeline.", "The Empire and the forest share borders. Let us keep them peaceful."],
			["Your laws now protect the ancient groves. The forest remembers this kindness.", "The Empire proves that civilization need not destroy nature. Welcome."],
			["Imperial friend! Your people plant trees where once they felled them! Joy!", "Civilization and nature in perfect harmony! The dream made real!"],
		],
	},
	&"moonspear": {
		&"sunblessed": [
			["Your blinding sun obscures the truth written in the stars. Typical.", "Sun-zealot. The moon endures while the sun merely burns."],
			["The sun illuminates, yes. But only the moon reveals what hides in shadow.", "Your faith is loud. The stars prefer quiet contemplation."],
			["Sun and moon share the same sky. Perhaps we can share this table.", "The Blessed of the sun. Our faiths differ, but both look upward."],
			["The sun and moon are siblings, after all. Welcome, kindred seeker.", "Your light complements ours. Together, there is no darkness."],
			["Sun and moon in alignment! The heavens CELEBRATE our unity!", "Sibling of the sky! Together our light illuminates ALL creation!"],
		],
		&"forsaken": [
			["The void you serve is the absence of starlight. The moon abhors emptiness.", "You are a black hole in the constellation. A devourer of meaning."],
			["The stars dim near your borders. The temple finds this troubling.", "Your void presses against the light. The moon keeps vigil."],
			["Even the void has its place in the cosmic order. The stars acknowledge you.", "Between light and dark, there must be twilight. Let us meet there."],
			["The Oracle sees beauty even in the void between stars. Welcome, shadow-walker.", "The darkness between stars gives them definition. You give us purpose."],
			["Light needs darkness to SHINE! The moon and the void, eternal partners!", "In the grand tapestry of the cosmos, your thread is as vital as ours!"],
		],
		&"gladehost": [
			["Even the forest disappoints. The stars expected better from the grove.", "Nature without guidance is mere chaos. The moon sees your failings."],
			["The grove stirs under moonlight. At least you respond to celestial influence.", "Forest-keeper. The moon lights your canopy, whether you appreciate it or not."],
			["The grove and the moon have always been aligned. What brings you?", "Moonlight feeds the forest. A natural partnership. Speak."],
			["The forest grows strongest under the silver light. Welcome, grove-friend.", "The moon and the grove — ancient allies in the cosmic dance."],
			["Beloved grove-keeper! Moon and forest are ONE under the starlit sky!", "Nature and celestial order in perfect harmony! Our bond is eternal!"],
		],
		&"shardhorde": [
			["Your crystal frequencies desecrate the celestial harmonics. The stars REJECT you.", "You are crystalline chaos pretending to be structure. Offensive."],
			["The lattice disrupts the starlight. The temple monitors with concern.", "Your crystal vibrations interfere with our celestial readings."],
			["The Crystalmind. An ordered entity, if alien. The stars are curious.", "Crystal and starlight both follow patterns. Perhaps we can find harmony."],
			["The lattice resonates with celestial frequencies! A fascinating discovery.", "Crystal and moonlight share more than we knew. Welcome, strange friend."],
			["CRYSTALLINE HARMONY! The Hive and the stars vibrate as ONE!", "From crystal caves to celestial vaults — our resonance is perfect!"],
		],
	},
	&"thunderswarm": {
		&"skulloath": [
			["Steppe-crawler! Your flat-land riders would break on our mountain paths!", "The bone-rattlers dare challenge the storm? HA! Pathetic."],
			["Horse-riders. You fight well on flat ground. Shame the world isn't flat.", "The horde is tough. But toughness alone does not survive the peaks."],
			["Steppe-warrior. Your saddle-skills match our mountain-climbing. Respect.", "The Khan fights differently than us. But fights well."],
			["The horde would make fine highland warriors! Come, ride our paths!", "Steppe-brother! Your charge is as unstoppable as our avalanches!"],
			["MOUNTAIN AND STEPPE! Together we are EVERY terrain! UNSTOPPABLE!", "Khan of the plains! Your riders and our climbers — the PERFECT army!"],
		],
		&"empire": [
			["Go back to your palace and cushions, soft-skin.", "The Empire sends tax collectors even to the peaks. Disgusting."],
			["Imperial. Your laws mean nothing above the treeline.", "Titles and ranks. The mountain cares nothing for your paper power."],
			["Imperial. Your roads are useful, I suppose. Speak.", "The Empire builds. The mountain endures. Perhaps common ground."],
			["You have iron in you, Empire-friend! Not bad for a lowlander!", "The Imperial discipline almost matches highland stubbornness! Welcome!"],
			["IMPERIAL BROTHER! Your discipline and our fury — NOTHING can stop us!", "From palace to peak — our friendship SHAKES THE WORLD!"],
		],
		&"cinderguard": [
			["These are OUR mountains, forge-hider! Stay in your tunnels!", "Your smoke ruins the mountain air. Take your furnace elsewhere!"],
			["The Cinderguard digs while we climb. We know which is braver.", "Your fires warm you. Our storms harden us. Guess who wins?"],
			["Forge-kin. We share the mountain, if not the same path through it.", "Your tunnels and our peaks — the mountain has room for both."],
			["Mountain-neighbor! Your forge warms the storms between us! Welcome!", "The Cinderguard proves the mountain has MANY strengths!"],
			["MOUNTAIN BROTHER! Peak and forge, storm and flame — UNBREAKABLE!", "Together we ARE the mountain — its fury AND its fire!"],
		],
		&"moonspear": [
			["Star-gazers. Try watching where your FEET go instead.", "Your prophecies are as useful as moonlight in a blizzard."],
			["The moon-folk and their riddles. The mountain has no patience.", "Less staring at stars, more swinging axes. That's my advice."],
			["Moon-watcher. Your visions have occasional use. Speak.", "The stars are pretty. Your foresight is sometimes useful."],
			["Your prophecies warned us of the avalanche! The mountain owes you!", "Star-friend! Your wisdom makes our strength more effective!"],
			["STAR-SIBLING! Your sight and our might — PERFECT combination!", "The storm bows to no one — except perhaps the stars that guide it!"],
		],
	},
	&"tainted_jade": {
		&"gladehost": [
			["Your tame little garden amuses us. The TRUE jungle devours the weak.", "The grove is nature with its fangs pulled. How pathetic."],
			["Forest-tender. Your nature is sanitized. The jungle pities you.", "Still trimming your hedges while the real wilderness thrives?"],
			["Grove-keeper. We are more alike than either cares to admit.", "Your forest and our jungle share roots deeper than either knows."],
			["Cousin of the canopy. Your gentle ways have a certain wisdom.", "The grove's light complements the jungle's shadow. Welcome, cousin."],
			["Beloved nature-kin! Grove and jungle, vine and thorn — ALL ONE!", "The wild heart beats in both of us! Our bond is nature itself!"],
		],
		&"forsaken": [
			["Your emptiness bores the jungle. At least OUR darkness has TEETH.", "The void is nothing. The jungle is everything. Including your end."],
			["Hollow one. Your decay lacks artistry. The jungle rots with PURPOSE.", "The void is empty. The jungle is full. Nothing in common."],
			["Death-walker. The jungle understands predator and prey. Including death.", "Your void touches the spaces between our vines. An uneasy connection."],
			["The jungle and the void share the darkness. There is kinship in that.", "Decay and growth are partners, void-walker. Welcome to the understory."],
			["Shadow-sibling! Jungle and void — twin darknesses, ONE PURPOSE!", "From deepest roots to emptiest void — our bond knows no bottom!"],
		],
		&"ivoryscar": [
			["Your dusty tombs hold nothing but bones. The jungle holds LIFE.", "The desert preserved corpses. The jungle makes them disappear."],
			["Tomb-keeper. Your relics gather dust while our venom stays fresh.", "The sand preserves what the jungle reclaims. A philosophical split."],
			["Relic-keeper. The jungle respects age, even dried and calcified age.", "Your ancients and ours once traded. Perhaps we can again."],
			["The desert and the jungle share ancient secrets. Welcome, keeper.", "Your preserved wisdom complements our living knowledge. Welcome."],
			["Ancient friend! Desert and jungle — oldest powers on earth, UNITED!", "Your bones and our vines — together we hold the memory of the world!"],
		],
		&"empire": [
			["Your neat little empire is a garden waiting to be overgrown.", "The jungle consumes all structure eventually. Including yours."],
			["Imperial order. So fragile against the chaos of nature.", "Your maps end where the jungle begins. Intentionally."],
			["Imperial. The jungle acknowledges that order has its uses.", "Your roads bring trade to the jungle's edge. Adequate."],
			["The Serpent Queen appreciates order that respects the wild. Welcome.", "Your discipline and our adaptability — interesting combination."],
			["Imperial friend! The jungle wraps protectively around your borders!", "Order within, wilderness without — our alliance is balance!"],
		],
	},
	&"cinderguard": {
		&"gladehost": [
			["The forest burns well. Remember that, wood-witch.", "Your trees are fuel. Your druids are kindling. Know your place."],
			["Every piece of charcoal was once one of your precious trees. Perspective.", "The forge needs fuel. The forest provides. End of discussion."],
			["Forest-keeper. The forge can be more careful with its fuel.", "Trees and timber, forests and forges — we must find balance."],
			["The forge has learned to harvest without destroying. Your teachings helped.", "Wood-friend! Sustainable forests feed our forges better than clear-cutting."],
			["Grove-friend! Forge and forest — creation and renewal in perfect cycle!", "Every tree we plant for every one we burn! Nature and industry, TOGETHER!"],
		],
		&"empire": [
			["Imperial mass production. Quantity over quality. The forge DESPISES it.", "Your factory-forged trinkets insult every smith who ever lived."],
			["The Empire's workshops are adequate. For amateurs.", "Imperial steel bends where ours holds. But you have volume."],
			["Imperial metalwork improves. The forge acknowledges this.", "Your craftsmen learn from ours, whether they admit it. Welcome."],
			["The Empire's engineers and our smiths — a formidable combination.", "Imperial precision and our heat treatment — together, perfection."],
			["Imperial partner! Your engineers and our forge — we shape the WORLD!", "The greatest weapons ever made — forged by OUR alliance!"],
		],
		&"ivoryscar": [
			["Your ancient metalwork is corroded junk. The forge moves FORWARD.", "Tomb-digger. Your relics belong in a museum, not a battlefield."],
			["Old techniques. Interesting, but the forge has surpassed them.", "The ancients knew some tricks. We know more."],
			["Relic-keeper. The ancient smithing techniques deserve study.", "Your old-world alloys — the forge finds them intriguing."],
			["Ancient metallurgical secrets you shared improved our work immensely!", "Old wisdom meets new fire — the forge is grateful, relic-friend."],
			["Ancient friend! Your techniques and our modern forge — UNMATCHED!", "Together we forge with the wisdom of ages and the fire of today!"],
		],
		&"thunderswarm": [
			["Storm-screamer. The INSIDE of the mountain belongs to us. Stay on your peaks.", "Your lightning shakes our tunnels. One more quake and we seal your passes."],
			["The Swarm runs wild on the peaks while we build below. Typical.", "Mountain surface-dwellers. Noisy and uncivilized."],
			["Storm-kin. We share the mountain. Let us share its wealth.", "Peak and tunnel — the mountain is big enough for both."],
			["Your storms test our structures, making them STRONGER. The forge is grateful!", "Mountain-neighbor! Your lightning tempers our steel from afar!"],
			["MOUNTAIN BROTHER! Peak and forge, lightning and fire — UNSTOPPABLE!", "The mountain is OURS — above and below, storm and flame, TOGETHER!"],
		],
	},
	&"forsaken": {
		&"sunblessed": [
			["Your light BURNS us and you call it righteous. The void will consume your sun.", "Sun-zealot. Your holy fire is just another way to destroy what you fear."],
			["The sun's glare is unpleasant. Like your personality.", "Your light reveals nothing the void hasn't already seen."],
			["Sun-keeper. Your light and our darkness must coexist. Somehow.", "The dawn comes even to the void. We have learned to endure it."],
			["Your light warms even the hollow places within us. Not unwelcome.", "The sun and the void — perhaps they need each other after all."],
			["Sun-friend! Your light gives MEANING to our darkness! We are GRATEFUL!", "Light and void, together at last! The cosmos is COMPLETE!"],
		],
		&"moonspear": [
			["Your silver light needles the void like tiny daggers. Stop it.", "Star-watcher. The void between your precious stars is OURS."],
			["The moon's glow is tolerable. Barely. Unlike your preaching.", "Celestial light is softer than the sun's, at least. Small mercy."],
			["Moon-watcher. The void acknowledges the night sky. It is our ceiling.", "Stars and void are neighbors. Perhaps their people can be too."],
			["The moonlight doesn't burn like the sun. The void appreciates this.", "Star-friend. You understand that darkness is not evil. That means everything."],
			["Moon-keeper! The night sky is the PERFECT marriage of light and dark!", "The stars shine brightest against the void! We NEED each other!"],
		],
		&"gladehost": [
			["Your living things mock us with every breath. The grove will ROT.", "So much life. So fragile. The void will claim it all eventually."],
			["Your greenery is offensive to those who can no longer grow.", "The living forest. A painful reminder of what was lost."],
			["Grove-keeper. The fallen leaves know the void well. Common ground.", "Life and death are two sides of the same leaf. The void accepts this."],
			["Your living world reminds us of what we were. It no longer hurts.", "Green-friend. Your life gives the void something to aspire to."],
			["Living one! Your vitality inspires even the dead! The void BLOOMS for you!", "Life and death, growth and decay — our cycle together is BEAUTIFUL!"],
		],
		&"empire": [
			["Your mortal empire will crumble to dust. The void is patient.", "Empires rise and fall. The void endures. You are temporary."],
			["Another mortal government pretending it will last forever. Quaint.", "Your institutions decay faster than our corpses. We accept it."],
			["Imperial. Your mortal ambitions are interesting, in their way.", "The Empire builds what the void eventually claims. But build you do."],
			["Your stubborn refusal to accept entropy is almost admirable.", "Imperial friend. Your persistence against the inevitable earns respect."],
			["The Empire's defiance of decay INSPIRES the void! You prove meaning EXISTS!", "Mortal friend! Your fleeting flame burns brighter than eternal darkness!"],
		],
	},
	&"ivoryscar": {
		&"tainted_jade": [
			["The jungle swallowed our southern provinces. The tombs REMEMBER.", "Serpent-worshipper. Your venom corrodes our sacred relics."],
			["The jungle creeps where the desert recedes. The Oracle watches.", "Your poison and our preservation — fundamentally incompatible."],
			["Serpent-keeper. The ancients traded with your jungle. Perhaps again.", "Desert and jungle share a border and a history. Let us discuss."],
			["The ancients valued jungle remedies. The Oracle sees wisdom in renewal.", "Your living memory complements our preserved one. Welcome, jungle-friend."],
			["Ancient neighbor! Desert and jungle — oldest civilizations, REUNITED!", "Your living history and our preserved one — NOTHING is forgotten!"],
		],
		&"cinderguard": [
			["Your crude ironwork insults the ancient smiths whose techniques you mock.", "The forge-folk melt what should be preserved. Barbarians in aprons."],
			["Your metalwork lacks the finesse of the ancients. But it has vigor.", "The forge creates while the tomb preserves. Natural opposites."],
			["Forge-keeper. The ancient alloys await rediscovery. Perhaps together.", "Your fire and our knowledge — there are possibilities here."],
			["The forge has recreated techniques lost for millennia! The ancestors applaud!", "Forge-friend! Your craft honors the ancient smiths."],
			["Master forger! Together we unlock the secrets of the FIRST SMITHS!", "Ancient technique and modern fire — our alliance reshapes the world!"],
		],
		&"forsaken": [
			["You are decay made manifest. The tombs REJECT your corruption.", "The ancients preserved themselves. You simply refuse to decompose properly."],
			["The void preserves nothing. Our tombs preserve EVERYTHING. See the difference?", "Your hollow existence mocks our sacred preservation."],
			["Void-walker. Both our peoples exist beyond normal time. Unusual kinship.", "The preserved and the hollowed. More in common than most realize."],
			["The void and the tomb both defy time. The ancestors see a kindred spirit.", "You understand eternity. That understanding bridges our differences."],
			["Beyond-death friend! Tomb and void — we have conquered TIME itself!", "Eternal companions! Our friendship will outlast the stars themselves!"],
		],
		&"shardhorde": [
			["Your crystal lattice corrupts ancient frequencies. The relics SHATTER.", "Alien abomination. Your crystalline growth consumes our sacred sites."],
			["The Hive's expansion threatens our excavation sites. Concerning.", "Crystal and bone do not mix. Your growth patterns are troubling."],
			["Crystalmind. The ancient relics resonate curiously near your lattice.", "Your ordered growth mirrors our ancient architecture. Interesting."],
			["Crystal frequencies help decode ancient inscriptions! Fascinating!", "Crystal-friend! Your lattice reveals hidden patterns in our oldest relics."],
			["Crystal partner! Ancient stone and living crystal — we unlock secrets!", "Your crystalline memory and our carved records — ALL KNOWLEDGE is ours!"],
		],
	},
	&"shardhorde": {
		&"gladehost": [
			["Organic contamination at critical levels. Bio-purge recommended.", "Carbon-based overgrowth detected. Removal protocols processing."],
			["Excessive organic signatures detected. Proximity: uncomfortable.", "Bio-entity. Your photosynthesis creates suboptimal atmospheric chemistry."],
			["Organic entity. Your growth patterns demonstrate acceptable order.", "Bio-signal processed. Carbon-silicon compatibility: moderate."],
			["Organic growth patterns mirror crystal formation. Symbiotic potential: high.", "Your root networks function like our crystal lattice. Fascinating parallel."],
			["ORGANIC PRIME ALLY! Bio-crystal symbiosis achieves OPTIMAL growth!", "Carbon and silicon, root and crystal — PERFECT integration!"],
		],
		&"cinderguard": [
			["Thermal output damages crystal matrices. Heat source: hostile.", "Forge emissions: destructive to lattice integrity. Classification: threat."],
			["Mineral processing detected. Methods: crude but functional.", "Thermal manipulation of ores. Inefficient but intriguing."],
			["Forge entity. Your mineral processing has useful applications.", "Heat-based refinement interests the Crystalmind. Processing."],
			["Forge processes enhance crystal purity! Beneficial relationship confirmed!", "Your thermal techniques refine our growth medium. Synergy detected!"],
			["FORGE PRIME ALLY! Heat and crystal — PERFECT lattice formation!", "Your fire purifies, our crystal grows — MAXIMUM mineral efficiency!"],
		],
		&"moonspear": [
			["Celestial radiation interferes with crystal frequencies. Source: hostile.", "Lunar electromagnetic patterns: disruptive to Hive communications."],
			["Starlight refraction through crystal: acceptable at low intensity.", "Your celestial frequencies create minor lattice disturbances."],
			["Celestial entity. Your electromagnetic patterns are ordered. Compatible.", "Starlight and crystal interact predictably. Processing."],
			["Moonlight enhances crystal resonance! Beneficial interaction confirmed!", "Celestial frequencies amplify the lattice! Positive symbiosis!"],
			["CELESTIAL PRIME ALLY! Starlight and crystal — TOTAL CONVERGENCE!", "Every photon enhances the lattice! MAXIMUM cosmic resonance!"],
		],
		&"forsaken": [
			["Entropy signature: extreme. Entity threatens lattice stability.", "Void energy corrodes crystal bonds. Classification: existential threat."],
			["Decay patterns: alarming but contained. Monitoring continues.", "Your entropy field weakens nearby crystal structures. Concerning."],
			["Void entity. Entropy and order exist in balance. Processing.", "Your void frequencies are our inverse. Mathematically interesting."],
			["The void between crystals gives them structure! Entropy serves order!", "Void-entity: your absence defines our presence. Symbiotic!"],
			["VOID PRIME ALLY! Crystal and emptiness — the FUNDAMENTAL DUALITY!", "Your void and our lattice — together we ARE reality itself!"],
		],
	},
	&"sunblessed": {
		&"forsaken": [
			["ABOMINATION! The Eternal Dawn commands your destruction!", "You are everything the light exists to purge. Prepare yourself."],
			["The sacred flame flickers in your unholy presence.", "Your void offends the Dawn. The priests pray for your correction."],
			["Even the sun must sometimes shine upon the darkened. Speak.", "The light does not discriminate. Even you may be heard."],
			["The dawn reveals that even the void has purpose. Welcome, unlikely friend.", "Perhaps redemption takes many forms. Your persistence moves us."],
			["Even the VOID bows before our friendship! LIGHT PREVAILS!", "From absolute darkness, the most miraculous dawn! BLESSED, shadow-friend!"],
		],
		&"moonspear": [
			["Your pale moonlight is a mockery of TRUE celestial power.", "The moon borrows the sun's light and calls it wisdom. Pathetic."],
			["The moon is merely a reflection. The SUN is the source.", "Your silver light is pleasant enough. But it is not the Dawn."],
			["Moon-keeper. Sun and moon share the sky. Perhaps the temple can too.", "Your faith and ours look upward. That common direction matters."],
			["Sun and moon together banish ALL darkness! Welcome, celestial sibling!", "Your gentle moonlight heals where our fierce sun cauterizes. Complementary."],
			["SIBLING OF THE SKY! Sun and moon in ETERNAL harmony!", "Day and night, dawn and dusk — our cycle together IS the heavens!"],
		],
		&"empire": [
			["Your godless governance dooms your people to spiritual darkness.", "The Empire worships only gold. The Dawn weeps for your souls."],
			["The Crown ignores the Dawn. The priests note this with concern.", "Your secular ways leave your people without guidance. Unfortunate."],
			["Imperial. The temple respects governance, even without faith.", "Your order serves the people in its own way. The Dawn acknowledges this."],
			["The Empire's justice mirrors the Dawn's fairness. The temple approves.", "Your laws protect the weak. That IS the Dawn's work."],
			["Imperial friend! Your justice IS the Dawn manifest in law!", "The greatest empire serves the light even without a temple! BLESSED!"],
		],
		&"tainted_jade": [
			["Your corrupted nature is a BLASPHEMY against the Dawn's creation!", "Every poisoned vine is a sin against the light. Condemned."],
			["The jungle's darkness troubles the Dawn. Your practices are questionable.", "Venom and shadow. The sun struggles to penetrate your canopy."],
			["Serpent-keeper. Even the jungle receives the Dawn's light.", "Your jungle is shadowed, but the sun filters through. There is hope."],
			["The jungle's venoms have healed our pilgrims. The Dawn works in strange ways.", "Not all shadow is evil. Your jungle proves this. Welcome, green one."],
			["JUNGLE FRIEND! Even the darkest canopy lets the Dawn through!", "Poison that heals, shadow that protects — the Dawn embraces ALL nature!"],
		],
	},
}

# Accept/deny lines per faction (5 stages, 5 variations each)
const LEADER_ACCEPT_LINES := {
	&"empire": [
		["Hmph. The Empire grudgingly accepts.", "Do not mistake this for generosity.", "Barely adequate. But the Crown agrees.", "This scrapes past the minimum. Accepted.", "The court holds its nose and signs."],
		["These terms are... acceptable.", "The Chancellor has reviewed the terms. Fine.", "The Empire accepts, with reservations noted.", "A workable arrangement. Proceed.", "Not our finest deal, but serviceable."],
		["The Empire agrees.", "Fair terms for both sides. Done.", "The Crown seals this agreement.", "A balanced arrangement. The Empire is satisfied.", "Agreed. Let the scribes record it."],
		["A fine arrangement, worthy of our alliance.", "The court applauds this deal!", "Excellent terms! The Chancellor is pleased.", "This strengthens our bond considerably. Well done.", "The Emperor nods with genuine approval."],
		["Splendid! The Crown is delighted!", "MAGNIFICENT! This is diplomacy at its finest!", "The entire court celebrates this accord!", "A deal worthy of song! The bards shall hear of this!", "The Emperor himself raises his goblet to you!"],
	],
	&"skulloath": [
		["Bah. Fine. But do not test us again.", "The Khan spits and agrees. Do not push your luck.", "Acceptable. Barely. The horde has spoken.", "Grr. It is done. Now leave my tent.", "The ancestors would grumble, but... fine."],
		["The Khan accepts, barely.", "Iron changes hands. The deal holds.", "Hmph. You bargain like a merchant. But agreed.", "Good enough for the steppe. Done.", "The caravan may pass. This time."],
		["The caravan routes open.", "A fair trade between warriors. Agreed.", "The Khan nods. It is done.", "Steel for steel. The horde respects this.", "The steppe wind carries our agreement."],
		["A worthy exchange! The horde approves.", "HA! You bargain well! The Khan is pleased!", "The ancestors smile on this deal!", "Now THIS is a trade worth making! Done!", "Strong terms! You have the horde's respect."],
		["HA! Glorious! The Khan celebrates!", "DRINK! FEAST! This deal makes the spirits SING!", "The greatest trade since the founding of the horde!", "I would ride to war for anyone who deals this fairly!", "The steppe THUNDERS with approval!"],
	],
	&"gladehost": [
		["The grove bends... reluctantly.", "Like pulling thorns. But agreed.", "The roots grip tightly, but release. Accepted.", "The forest allows this, against its nature.", "Even stone moss grows slowly. This too."],
		["The roots accept, though they bristle.", "The canopy parts for this. Narrowly.", "A bitter seed, but one the grove will plant.", "The thorns retract. Proceed.", "Not all growth is pleasant. Agreed."],
		["A fair exchange nourishes both sides.", "The grove finds balance in these terms.", "Like rain after drought. Agreed.", "The forest accepts what the forest needs.", "Growth flows both ways. Done."],
		["The forest blooms at this accord.", "The oldest branch bows in agreement!", "This deal carries the scent of wildflowers.", "The grove sings with approval!", "A fine accord. The forest is grateful."],
		["The ancient trees themselves bow in joy!", "The GREAT ROOT stirs with happiness!", "Every leaf turns gold to celebrate this moment!", "The spirit of the forest weeps with joy!", "In a thousand seasons, no finer agreement has graced the grove!"],
	],
	&"moonspear": [
		["The moon turns its face away, but... we accept.", "The stars dim with reluctance, but the deal holds.", "A cold alignment. But accepted.", "The Oracle winces. Yet agrees.", "Silver light fades, but the pact is sealed."],
		["The stars allow it, barely.", "The constellation of commerce aligns. Barely.", "A tolerable arrangement. The temple accepts.", "The moon reflects without warmth, but nods.", "The celestial math checks out. Fine."],
		["The temple accepts this in good faith.", "The stars neither bless nor curse this deal.", "A fair conjunction of interests. Agreed.", "The Oracle nods calmly. It is done.", "The silver thread of this agreement holds true."],
		["A blessed arrangement under the moon.", "The stars brighten at these terms!", "The Oracle smiles — a rare and precious sight.", "Moonlight blesses this accord!", "The celestial signs strongly favor this!"],
		["The celestial choir sings! It is done!", "The HEAVENS ALIGN in celebration!", "Every star blazes for this glorious pact!", "The Oracle weeps tears of silver joy!", "A deal written in starlight for all eternity!"],
	],
	&"thunderswarm": [
		["Grr. Agreed. Now leave before I change my mind.", "Fine. FINE. Take it before I rethink.", "The storm grumbles, but passes. Done.", "My axe hand twitches, but... agreed.", "BAH. Acceptable. Do not gloat."],
		["Fine. But make it quick.", "The mountain nods. Grudgingly.", "You drive a hard bargain. Hmph. Agreed.", "Thunder rolls, but does not strike. Done.", "The highland air accepts your terms."],
		["Iron and gold flow like mountain rivers.", "A solid deal. The mountain stands firm on this.", "Fair as the highland wind. Agreed.", "The drums beat once. The deal is struck.", "Neither too much nor too little. Good."],
		["HA! A strong deal! I like you!", "Now THAT is how you bargain! Agreed!", "The storm ROARS with approval!", "The war drums beat a happy rhythm!", "Come! Let us seal this with mead!"],
		["THUNDEROUS AGREEMENT! Let us feast!", "THE MOUNTAIN SHAKES WITH JOY!", "I would wrestle a bear to celebrate this deal! HA!", "GLORIOUS! The greatest accord since the storm chiefs united!", "DRINK! SING! Let every peak echo with celebration!"],
	],
	&"tainted_jade": [
		["The serpent hisses... but accepts.", "The venom recedes. Barely. Agreed.", "The jungle permits this. Under protest.", "Every scale bristles, but the coils loosen. Done.", "A bitter fruit. But the serpent swallows it."],
		["The jungle allows this. For now.", "The serpent coils once and releases. Accepted.", "Not the sweetest nectar, but it sustains. Agreed.", "The canopy filters this offer and finds it... tolerable.", "Adequate. The jungle has seen worse."],
		["The serpent accepts. An equitable exchange.", "Balance in the jungle ecosystem. Agreed.", "The jade throne measures and approves.", "Predator and prey both benefit. A rare thing.", "The venom and the antidote. A fair trade."],
		["The coils embrace this arrangement warmly.", "The rarest orchid blooms for you. Agreed!", "The Serpent Queen's scales shimmer with approval.", "Sweet as honey, and just as golden. Accepted!", "The jungle resonates with satisfaction!"],
		["The Serpent Queen herself smiles upon this!", "The JUNGLE CELEBRATES with a thousand blooming flowers!", "In all the ages of poison and paradise, no finer deal!", "The Great Serpent coils in BLISS!", "Every venomous thing turns sweet for you today!"],
	],
	&"cinderguard": [
		["The forge accepts. Do not waste our metal.", "Hmph. Like cold iron. Barely workable. But done.", "The bellows sigh and agree.", "The slag falls away. This deal barely survives. Accepted.", "The Forgemaster grumbles but signs."],
		["Hmm. Tolerable. Agreed.", "Like pig iron. Not great, but useful. Done.", "The anvil accepts this strike.", "Workable material. The forge proceeds.", "Not our finest casting, but it holds."],
		["Iron meets iron. A solid deal.", "Well-tempered terms. The forge agrees.", "A fair heat for fair metal. Done.", "The hammer strikes true on this one.", "Solid as mountain stone. Agreed."],
		["Well forged! This strengthens us both.", "Fine craftsmanship in these terms!", "The forge GLOWS with approval!", "Like finding mithril in common ore. Excellent!", "The master smiths nod in admiration!"],
		["A masterwork agreement! The forge roars in triumph!", "STEEL SINGS ON THE ANVIL! The finest deal ever forged!", "The Great Forge itself blazes in celebration!", "This accord is INDESTRUCTIBLE! Like the mountain itself!", "In all the history of the forge, no finer alliance!"],
	],
	&"forsaken": [
		["Ugh. Even the dead find this distasteful, but... agreed.", "The void groans. But accepts.", "Like swallowing ash. But done.", "The Hollow King rolls his empty eyes. Fine.", "Even oblivion has its price. Paid."],
		["The hollow winds carry our reluctant assent.", "The shadows agree. Without enthusiasm.", "A joyless accord. But functional.", "The emptiness permits this. Barely.", "Like dust settling. Inevitable. Accepted."],
		["Even the dead have use for this arrangement.", "The void finds equilibrium. Agreed.", "Neither living nor dead, this deal simply... is.", "Acceptable to the hollow. Proceed.", "The darkness nods. A fair exchange."],
		["A rare moment of light in the void. Accepted.", "The emptiness warms — slightly. Agreed!", "The Hollow King almost smiles. Almost.", "This brings... something close to satisfaction.", "The void hums with what might be approval."],
		["In the name of the Hollow King — enthusiastically agreed!", "The VOID ITSELF brightens! Is this... joy?!", "For the first time in an age, the Forsaken feel something GOOD!", "Even death celebrates this glorious accord!", "The emptiness OVERFLOWS with gratitude!"],
	],
	&"ivoryscar": [
		["The sand buries most offers. Yours barely survives.", "The Oracle squints. But agrees.", "Like old bone — brittle, but it holds. Accepted.", "The scarabs click with reluctance. Done.", "Ancient dust settles on this deal. Fine."],
		["The Oracle permits it, against better judgment.", "The sands shift and settle. Tolerable.", "The tomb walls echo a grudging assent.", "The ancestors murmur. Not in praise. But they agree.", "The relics dim but do not darken. Accepted."],
		["Ancient wisdom says: a fair trade benefits all.", "The hourglass turns evenly. A balanced deal.", "The ancestors find no fault. Agreed.", "The Oracle's eye reflects calm. Proceed.", "The sands of time approve. Done."],
		["The ancestors smile upon this arrangement.", "The relics GLOW warmly! Well negotiated!", "The Oracle sees prosperity ahead!", "Ancient bells ring beneath the sand! Wonderful!", "The scarabs dance in formation. High praise!"],
		["The relics glow with approval! Magnificent!", "The ANCESTORS RISE to celebrate this accord!", "Ten thousand years of wisdom culminate in this moment!", "The Oracle SHINES like a second sun! Glorious!", "The greatest deal since the First Dynasty!"],
	],
	&"shardhorde": [
		["Exchange ratio suboptimal... but tolerated.", "Processing... reluctant acceptance at minimum threshold.", "Resource allocation: unfavorable. Yet necessary. Accepted.", "Crystalline consensus: 47% approval. Sufficient.", "The Hive buzzes with displeasure. But complies."],
		["Processing... accepted at minimum threshold.", "Exchange parameters within tolerable bounds.", "The crystal lattice vibrates at low satisfaction. Agreed.", "Suboptimal but functional. The Hive proceeds.", "Cost-benefit analysis: marginal. Accepted."],
		["Resource exchange optimized. Agreement formed.", "Parameters aligned. Transaction approved.", "The Hive calculates mutual benefit. Agreed.", "Balanced exchange detected. Crystal consensus formed.", "Processing complete. Deal accepted."],
		["Positive resonance detected. Symbiosis enhanced.", "The crystal matrix SINGS with harmonic approval!", "Beneficial parameters confirmed! The Hive vibrates warmly!", "Exchange ratio exceeds expectations! Favorable!", "Strong signal! The lattice glows in agreement!"],
		["Maximum synergy achieved! Hive approves at all nodes!", "FULL CRYSTALLINE CONVERGENCE! Optimal exchange!", "Every node RESONATES with satisfaction!", "The Crystalmind designates this: PERFECT SYMBIOSIS!", "In all recorded exchanges, none approach this efficiency!"],
	],
	&"sunblessed": [
		["The sun barely tolerates this shadow-deal.", "The flame flickers. But accepts.", "A dim dawn. But dawn nonetheless. Agreed.", "The temple accepts under formal protest.", "Light does not celebrate this. But permits it."],
		["The flame permits it. Narrowly.", "The sun squints but does not turn away. Done.", "A twilight agreement. Not bright, but acceptable.", "The priests murmur consent. Barely.", "The sacred fire dims but holds. Agreed."],
		["A fair exchange under the golden sky.", "The sun shines evenly on these terms.", "The temple blesses this accord.", "Neither dusk nor dawn — a steady noon. Agreed.", "The flame burns true. A fair deal."],
		["Blessed by the light! A fine accord!", "The sacred flame BLAZES with approval!", "Dawn breaks golden on this arrangement!", "The priests sing hymns of joy! Wonderful!", "The sun shines BRIGHTEST on deals like this!"],
		["THE DAWN BREAKS UPON A GLORIOUS PACT!", "The ETERNAL SUN proclaims this accord HOLY!", "Every ray of light celebrates this blessed union!", "The most sacred pact since the founding of the temple!", "ALL THE HEAVENS IGNITE WITH RADIANT JOY!"],
	],
}
const LEADER_DENY_LINES := {
	&"empire": [
		["The Empire SPITS on your offer!", "Are you trying to insult us? Because you've succeeded.", "The Crown rejects this with extreme prejudice.", "Guards! Remove this... 'diplomat' and their insult.", "This offer is an act of war in parchment form."],
		["Unacceptable. Leave before we arrest you.", "The Chancellor crumples your terms without reading them.", "These terms would embarrass a beggar. No.", "Denied. The Empire does not stoop so low.", "If this is your best offer, do not come back."],
		["These terms insult the Crown.", "The balance is unfavorable. We must decline.", "The Empire sees no benefit here. Refused.", "A reasonable attempt, but the terms do not align.", "The court declines, but the door remains open."],
		["Regretfully, the Empire must decline.", "A shame — the terms almost worked. Perhaps next time.", "We wish we could, friend, but the numbers forbid it.", "Close, but the Crown cannot commit to this.", "Our advisors counsel against it, though we value the attempt."],
		["It pains us greatly, dear friend, but we cannot accept.", "If only the stars aligned differently. We are truly sorry.", "The Emperor weeps that duty prevents acceptance.", "Our hearts say yes, but the realm says no. Forgive us.", "Nothing would please us more, yet we must decline with heavy hearts."],
	],
	&"skulloath": [
		["I should gut you for such an insult!", "Is this a JOKE? I will feed this offer to the wolves!", "The Khan's blade twitches at these terms!", "You mistake the horde for fools? LEAVE!", "I have killed men for lesser insults than this."],
		["The Khan would rather eat dirt.", "Pathetic. The steppe dogs would reject this.", "Not even worth the breath to refuse. But no.", "Take your scraps elsewhere. The horde has standards.", "Bah! Even the wind blows harder bargains."],
		["The horde has no interest.", "Not this time. The caravan passes by.", "The Khan weighs and finds it lacking.", "The ancestors do not stir for this. Declined.", "A miss. But the steppe is long. Try again."],
		["A shame. Perhaps next time, friend.", "So close! But the spirits say not yet.", "The Khan grimaces with regret. Another time.", "I wish I could, warrior. But the horde needs more.", "A good attempt. The door to my tent remains open."],
		["It wounds the Khan deeply to refuse a blood brother.", "My heart ACHES to say no to you of all people!", "If the ancestors permitted it, I would agree in a heartbeat.", "Blood brother... this is the hardest refusal of my life.", "The Khan sheds an actual tear. But cannot accept."],
	],
	&"gladehost": [
		["The forest REJECTS your blight!", "Like rot upon healthy bark. REMOVED.", "The grove recoils from this poisonous offer!", "Every thorn turns against you for bringing this.", "The ancient trees would uproot themselves rather than accept."],
		["The thorns withdraw. This offer is poison.", "The canopy closes. No light for this deal.", "Like dead leaves — blown away and forgotten.", "The grove finds this withered. Declined.", "The roots reject what the soil cannot nourish."],
		["The grove has no need of this.", "The seasons do not favor this exchange.", "The wind scatters these terms like autumn leaves.", "The forest's needs lie elsewhere. Declined.", "A seed that will not germinate. We pass."],
		["The leaves whisper 'not yet'. Perhaps another time.", "Almost. The grove was close to blooming for you.", "A gentle frost prevents this growth. Perhaps in spring.", "The forest wishes it could. Not today.", "So close to flourishing. But not quite."],
		["Oh, dear friend — the ancient trees weep that we cannot agree.", "The Great Root trembles with sorrow at this refusal.", "Every leaf falls in sadness. We cannot, though we dearly wish to.", "The spirit of the forest cries. Forgive us, cherished one.", "If love alone could seal deals, this would be done. Alas."],
	],
	&"moonspear": [
		["The moon CONDEMNS your audacity!", "The stars go dark at this offense!", "Even the void of space rejects your terms!", "The Oracle shatters a crystal in fury!", "This offer is an eclipse upon all diplomacy."],
		["The stars forbid this folly.", "The constellation of commerce is in retrograde. No.", "The Oracle shakes her head firmly.", "Silver light dims at these terms. Declined.", "The celestial math does not add up. Refused."],
		["The stars counsel against this arrangement.", "The lunar tide is not favorable for this.", "The Oracle sees a different path ahead.", "Neither blessed nor cursed — simply not aligned.", "The temple declines with measured calm."],
		["The moon gently suggests we revisit this later.", "So close to alignment. But not today.", "The Oracle's eye dims with genuine regret.", "Almost, friend. The stars were nearly right.", "We wish the constellation permitted it. Soon, perhaps."],
		["It breaks our heart to refuse one so beloved by the moon.", "The celestial choir falls SILENT in sorrow!", "Every star dims with grief at this refusal.", "The Oracle weeps silver tears for you.", "If we could rearrange the stars for you, we would."],
	],
	&"thunderswarm": [
		["I'll use your offer to wipe my—no. Just no.", "Is this what passes for diplomacy in the lowlands?!", "I have HURLED better offers off the mountain!", "The storm REJECTS this with lightning!", "My axe is more diplomatic than this insult!"],
		["BAH! Insulting!", "Not worth the paper it's scratched on.", "The mountain does not bend for this.", "Weak as a valley breeze. No.", "Even the goats on the peaks would refuse this."],
		["The storm passes on this one.", "The highland wind blows this away. Declined.", "Not a deal the mountain can support.", "Thunder does not speak for this.", "A miss. But the winds shift."],
		["Not this time, friend. But the door remains open.", "Ah, close! But the storm drums say no.", "The mountain wishes it could. Perhaps soon.", "A strong attempt! But not quite strong enough.", "Come back with thunder in your offer. Then we talk."],
		["Brother... if only I could. The winds do not favor it.", "My HEART says yes but the mountain says no!", "I would move peaks for you, but this I cannot do.", "The storm weeps. WEEPS! But must refuse.", "You deserve better than a refusal. But that is what duty demands."],
	],
	&"tainted_jade": [
		["The jungle swallows your worthless offer whole!", "Poison would taste sweeter than these terms!", "The Great Serpent STRIKES at this insult!", "Every vine tightens with fury!", "The jungle vomits your offer back."],
		["Your offer disguised as honey is still poison.", "The scales see through this. Refused.", "The jungle spits this out like rotten fruit.", "Unworthy of the serpent's attention. No.", "The canopy drops thorns on your offer."],
		["The serpent declines.", "The jungle has no appetite for this.", "The jade throne is unmoved. Declined.", "Neither sweet nor nourishing. We pass.", "The serpent slides past without interest."],
		["The serpent regrets this refusal.", "Almost sweet enough. But not quite.", "The orchid wilts slightly. Not today, friend.", "The Serpent Queen sighs. Close, but no.", "A near miss. The jungle remembers your effort."],
		["Most honored one — the jungle weeps. We cannot accept.", "Every flower closes in GRIEF at this refusal.", "The Serpent Queen herself sheds a tear.", "If venom could cure regret, we would drink it all.", "The jungle would wither before willingly refusing you. Yet we must."],
	],
	&"cinderguard": [
		["Slag! Worthless! GET OUT!", "I should melt this offer down for scrap!", "The forge VOMITS at these terms!", "Even the ash heap rejects this!", "This insults every smith who ever lived!"],
		["This insults the forge. Denied.", "Cold iron. Rejected.", "Untempered and worthless. No.", "The anvil would crack under such poor terms.", "Not worth the coal to heat it. Refused."],
		["The forge passes. Not worth the metal.", "The heat isn't right for this deal.", "Neither hammer nor anvil favors this.", "The bellows rest. Not this time.", "A fair attempt, but the metal won't hold."],
		["A regrettable refusal. Perhaps we can reforge the terms.", "Almost — like steel just shy of hardening.", "Good ore, but the proportions are off. Another time.", "The forge nearly blazed for this. Close.", "With slight adjustments, this could work next time."],
		["Dear ally — the forge cools with regret. We must decline.", "The Great Anvil RINGS with sorrow!", "If only the metal were different. We are truly sorry.", "The Forgemaster hangs his head. Even friendship cannot bend iron.", "The deepest fires of the mountain dim with grief at this refusal."],
	],
	&"forsaken": [
		["The void DEVOURS your pathetic offer!", "Even nothingness is insulted by this!", "The Hollow King would laugh if he still could.", "We have endured ETERNITY and this is the worst moment.", "The emptiness echoes with contempt for your terms."],
		["We have no need of your pittance.", "The darkness yawns at this offer.", "Even the void has standards. Declined.", "What remains of our patience evaporates. No.", "The dead stir with annoyance. Refused."],
		["The hollow winds carry your offer away.", "Into the void it goes. Forgotten.", "The emptiness neither accepts nor cares.", "A hollow refusal for a hollow offer.", "The darkness absorbs this and gives nothing back."],
		["A reluctant refusal. The darkness regrets.", "Almost — a flicker of interest in the void.", "The Hollow King pauses. But shakes his head.", "Close. Closer than most. But still no.", "The void almost warmed. Almost."],
		["Even in the void, refusing you brings us sorrow.", "The emptiness ACHES with the weight of this refusal.", "For you, the Forsaken feel something terrible: regret.", "If the dead could weep, they would weep for you now.", "The Hollow King's crown dims with sadness. Forgive us."],
	],
	&"ivoryscar": [
		["The sands will BURY you and your offer!", "The Oracle SMASHES a relic in fury!", "The ancestors ROAR from their tombs in outrage!", "This offer defiles the sacred traditions!", "Every scarab turns its back on this insult!"],
		["An insult to the ancestors. Denied.", "The sands grind this offer to dust.", "The Oracle looks away in displeasure. Refused.", "The tomb doors slam shut on these terms.", "Not worthy of inscription. Declined."],
		["The sands bury this offer.", "The hourglass tilts unfavorably. Declined.", "The ancestors remain silent. No guidance, no deal.", "The relics do not stir. Not this time.", "The sand absorbs this offer without trace."],
		["The Oracle sees potential — but not now.", "The stars above the desert almost align. Almost.", "A worthy attempt. The ancestors note your effort.", "Close to the ancient ideal. But not there yet.", "The sands shift favorably — but not enough."],
		["The ancestors grieve that we must refuse their favored one.", "The Oracle WEEPS into the sacred sand!", "Every relic dims with sorrow! Forgive us!", "Ten thousand years of wisdom, and still we feel this loss.", "If we could rewrite destiny for you, we would."],
	],
	&"shardhorde": [
		["Hostile signal! Offer classified as attack vector!", "THREAT DETECTED in exchange parameters! Rejected!", "Crystal lattice rejects with extreme prejudice!", "Error 0xFF: exchange would cause Hive destabilization!", "Purge this offer from all processing nodes!"],
		["Exchange ratio unacceptable. Connection terminated.", "Suboptimal parameters detected. Hard reject.", "The Hive consensus: 12% approval. Insufficient.", "Crystal analysis complete. Unfavorable. Declined.", "Processing nodes vote: reject at all frequencies."],
		["Exchange ratio suboptimal. Rejected.", "Parameters do not align with Hive requirements.", "The lattice vibrates negatively. Declined.", "Insufficient benefit detected. Connection paused.", "The Crystalmind computes: not at this time."],
		["Regret signal transmitted. Cannot comply.", "Near-optimal parameters, but threshold not met.", "The Hive approaches consensus but falls short.", "Close to harmonic alignment. Recalibrate and retry.", "87% approval. 13% prevents acceptance. Regrettable."],
		["Prime ally status acknowledged. Yet parameters prevent acceptance.", "CRITICAL ERROR: desire to accept conflicts with optimal outcome!", "The Hive experiences... dissonance. We wish we could comply.", "Every node PULSES with regret at this calculation.", "If the crystal could bend its own laws for you, it would."],
	],
	&"sunblessed": [
		["The sun SCORCHES your blasphemous offer!", "The sacred flame RISES in fury!", "This offer is an affront to the Eternal Dawn!", "The priests recoil as if struck!", "Darkness itself would reject terms this foul!"],
		["The flame rejects this shadow-deal.", "The sun does not bless these terms. Denied.", "The temple doors close on this offer.", "A deal suited for twilight, not dawn. No.", "The light reveals the flaws. Refused."],
		["The sun does not shine on this arrangement.", "The flame burns evenly but does not favor this.", "The temple declines with grace.", "Not in the sun's plan today. Another time.", "The light passes over this without blessing."],
		["The light dims with regret. Another time.", "Almost — the dawn nearly broke for this.", "The priests pray for a better alignment. Soon.", "So close to the light. But not today, friend.", "The sacred flame flickers with genuine sadness."],
		["Beloved friend — the Dawn weeps that we must refuse.", "The Eternal Sun DIMS with the weight of this refusal!", "Every ray of light bends toward you in apology!", "If faith alone could forge a deal, this would be done.", "The holiest among us shed tears. Forgive the light its limitations."],
	],
}

# War declaration responses: indexed by standing stage (0=strong_dislike .. 4=strong_like).
# Stage 0-1 (they hate you): eagerly hostile — they've been waiting for this.
# Stage 2 (neutral): amused/dismissive — they think you're foolish.
# Stage 3-4 (they liked you): regretful/betrayed — they thought you were friends.
const LEADER_WAR_LINES := {
	&"empire": [
		["We've been waiting for this! The legions will crush you!", "Finally! The pretense is over. Prepare to be conquered.", "At last you show your true colors. The Empire will answer in steel!", "You dare?! The Crown has longed for this reckoning!", "WAR! The Empire will grind you to dust!"],
		["Foolish, but not unexpected. The legions march.", "So the mask slips. Very well — prepare yourself.", "The Empire saw this coming. Our armies are already moving.", "You choose violence? The Crown obliges.", "A predictable escalation. The Chancellor is unsurprised."],
		["An interesting choice. Let us see if you can back it up.", "So be it. You will regret this foolishness.", "War, then? How... uninspired. But the Empire accepts.", "The Crown notes your declaration with mild amusement.", "Bold words. We shall see if your armies match them."],
		["We had hoped for peace between us... but we will defend ourselves.", "A shame. The court genuinely valued your friendship.", "This saddens the Crown. But duty demands we answer.", "Why? We thought we had built something between us.", "The Emperor is disappointed. But the legions will march nonetheless."],
		["You wound us deeply, dear friend. Why would you do this?", "After everything we shared... the Emperor can barely speak.", "The court is STUNNED. We loved you as a brother. And now this.", "This betrayal cuts deeper than any blade. We trusted you.", "The Crown weeps. But even tears cannot stay the Empire's wrath."],
	],
	&"skulloath": [
		["HA! We've been SHARPENING our blades for this day!", "Finally! The Khan will drink from your skull!", "About time! The horde was growing BORED waiting!", "WAR! The ancestors HOWL with delight!", "Your lands will burn and the steppe will feast on the ashes!"],
		["Hmph. The Khan expected as much from your kind.", "So you bare your teeth at last. The horde is ready.", "The wolves smell blood. You should not have provoked them.", "A mistake, but one the Khan will gladly punish.", "The steppe wind already carries your doom."],
		["So be it. You'll regret this foolishness, outlander.", "War? Hah! Bold of you. Stupid, but bold.", "An interesting choice. The horde accepts your challenge.", "The Khan laughs. Come then, let us see what you are made of.", "You think you can match the horde? Amusing."],
		["We rode together once... a shame it ends like this.", "The Khan's heart is heavy. We called you friend.", "Why, warrior? The steppe was wide enough for both of us.", "A bitter wind blows. We did not want this.", "The ancestors frown. They remember our bond."],
		["Blood brother... you BETRAY the horde?! The Khan cannot believe it.", "After all we shared around the fire... this is how it ends?", "The Khan's hand TREMBLES. Not with rage, but grief.", "You were family. FAMILY! And you choose war?!", "Every warrior weeps. We would have died for you. And now this."],
	],
	&"gladehost": [
		["The forest has waited to devour you! Come and be consumed!", "At last! Every thorn has been sharpened for this moment!", "The grove HUNGERS for your destruction!", "Finally the pretense of peace ends! The roots will drag you under!", "WAR! The ancient trees have longed to crush you!"],
		["The thorns expected this. The forest was already preparing.", "Predictable. The grove saw your hostility taking root.", "The canopy closes over you. This was always inevitable.", "Like blight, you reveal yourself. The forest will purge you.", "The winds already whispered of your treachery."],
		["The grove accepts your declaration like autumn accepts the frost.", "So be it. The forest has weathered worse storms than you.", "War? An unwise season to plant such seeds.", "The trees bend but do not break. You will learn this.", "Bold, but foolish. The forest endures all things."],
		["We had nurtured the hope of friendship... but the grove will defend itself.", "Like a branch severed from the trunk. It pains us.", "The oldest trees sigh with sorrow. We thought you different.", "Why poison what was growing between us?", "The grove mourns what could have been."],
		["The Great Root SHUDDERS with grief! We loved you!", "Every leaf falls in mourning. You were the forest's dearest friend.", "How could you?! The grove opened its heart to you!", "The ancient trees weep sap like tears. This betrayal wounds the very earth.", "We would have sheltered you forever. And this is your answer?"],
	],
	&"moonspear": [
		["The stars foretold your destruction — and WE shall deliver it!", "We have watched the omens of your doom with anticipation!", "The Oracle has LONG prepared for this reckoning!", "At last! The celestial alignment demands your end!", "The void between stars holds nothing but contempt for you!"],
		["The constellation of war rises. As the Oracle predicted.", "The stars saw this in you. We are prepared.", "Your hostility was written in the heavens. So be it.", "The moon turns its dark face toward you. Unsurprising.", "A predictable alignment. The temple was ready."],
		["The stars neither bless nor curse this war. It simply is.", "So be it. The Oracle watches with detached curiosity.", "War? The celestial dance continues regardless.", "An interesting constellation forms. Let us see where it leads.", "You choose conflict. The temple accepts without passion."],
		["The Oracle's eye dims with sorrow. We valued the light between us.", "The stars weep silver. We had hoped for a different alignment.", "Why darken what the moon had blessed?", "A mournful constellation rises. We thought you an ally.", "The celestial bonds we forged... shattered. This wounds us."],
		["The Oracle COLLAPSES with grief! You were written in our most sacred stars!", "Every constellation SCREAMS! How could our most beloved friend do this?!", "The moon itself turns away in anguish! We trusted you above ALL others!", "This betrayal defies every prophecy! We loved you!", "The celestial choir falls silent. The stars cannot comprehend this sorrow."],
	],
	&"thunderswarm": [
		["FINALLY! My axe has been ACHING for your skull!", "HA! We've been waiting to CRUSH you!", "The storm has been building for THIS moment! Come and die!", "WAR! The mountain THUNDERS with excitement!", "About time you gave us an excuse! CHARGE!"],
		["Hmph. The thunder saw this coming.", "The storm was already brewing. You just made it official.", "Foolish, but the mountain does not turn away a fight.", "Your aggression was as obvious as lightning. We are ready.", "The war drums were already beating. We expected this."],
		["So be it. The mountain does not fear you.", "War? HA! Bold. Stupid, but bold. Come then!", "An interesting challenge. Let the storm decide who stands.", "The highland winds carry your declaration. We accept.", "You want a fight? The mountain ALWAYS wants a fight."],
		["We shared mead together... and now this?", "The storm growls with sadness. We called you friend.", "The mountain rumbles not with anger, but grief.", "Why, comrade? The highlands were open to you.", "A bitter storm. We did not want this from YOU."],
		["Brother... BROTHER! You break my heart!", "The mountain WEEPS! After everything we fought through together!", "I would have moved PEAKS for you! And you declare WAR?!", "Every warrior who toasted you now stands in stunned silence.", "The storm dies to nothing. Even thunder cannot express this grief."],
	],
	&"tainted_jade": [
		["The venom has been BREWING for you! The jungle strikes!", "At last the serpent can bare its fangs! Your end approaches!", "We have coiled and WAITED for this! Prepare to be consumed!", "The jungle has hungered for your lands! WAR!", "Finally! Every poisoned thorn was meant for YOU!"],
		["The serpent always knew you would show your scales.", "How predictable. The jungle was already constricting.", "Your hostility reeked. The serpent sensed it long ago.", "The coils tighten. This was always your nature.", "The jungle prepared its poisons well before your declaration."],
		["The serpent accepts. You walk into the jungle willingly.", "So be it. Many have entered the jungle boldly. None left.", "War? How... quaint. The serpent is neither impressed nor afraid.", "The canopy yawns. Come then, if you dare.", "An amusing declaration. The jungle watches with cold interest."],
		["The orchids wilt. We had thought you different from the rest.", "The serpent loosens its embrace with sadness. We valued you.", "Why poison what was blooming between us?", "A bitter nectar. We hoped for a sweeter path.", "The Serpent Queen's eyes dim. We called you friend."],
		["The jungle WITHERS with grief! You were our most treasured ally!", "Every flower closes! The Serpent Queen cannot believe this betrayal!", "We opened the deepest garden to you! And THIS is your answer?!", "The Great Serpent coils in AGONY! We loved you!", "This venom is the cruelest we have ever tasted. You were everything to us."],
	],
	&"cinderguard": [
		["The forge has been heating for YOUR pyre!", "At last! We've been hammering weapons for this day!", "Good! The Forgemaster has WAITED to break you on the anvil!", "WAR! The mountain burns with fury meant for YOU!", "We've been stoking these flames since we first saw your weakness!"],
		["The anvil expected this strike. We are prepared.", "Hmph. Like cold iron — predictable and brittle. So be it.", "The forge saw the cracks in your diplomacy long ago.", "Unsurprising. The bellows were already roaring.", "A foregone conclusion. The mountain's defenses are ready."],
		["The forge accepts your declaration. Steel answers all.", "So be it. We shall see whose metal holds.", "War? The anvil does not flinch. Come and be broken.", "An interesting test of mettle. The forge is ready.", "Bold. The mountain will answer with iron."],
		["We forged bonds together... and now you break them.", "The Great Anvil rings with sorrow. We valued our alliance.", "Like quenching hot steel in ice. This pains us.", "Why shatter what we built? We thought you an ally.", "The forge dims. We did not want this from you."],
		["The forge GOES COLD with grief! You were our finest ally!", "Every smith drops their hammer in shock! How could you?!", "We tempered our greatest works for YOU! And this is your answer?!", "The mountain itself cracks with sorrow! We TRUSTED you!", "The Forgemaster weeps molten tears. This betrayal is unforgivable."],
	],
	&"forsaken": [
		["The void has been REACHING for you! At last!", "Death has been patient, but NOW it comes for you!", "We have whispered your doom in the darkness for so long!", "WAR! The emptiness HUNGERS for your soul!", "Finally the Hollow King can claim what was always his!"],
		["The void saw this in you. An inevitability.", "Death comes for all. You simply hastened it.", "The darkness was already creeping toward you. So be it.", "Unsurprising. The hollow winds carried your intentions.", "The emptiness swallows your declaration without surprise."],
		["The void neither fears nor celebrates this. It simply consumes.", "So be it. Many have declared war on the darkness. None won.", "War? The emptiness is patient. Are you?", "An interesting declaration. The void watches without emotion.", "Come then. The darkness has room for one more."],
		["Even the void feels this loss. We valued what we had.", "The Hollow King pauses. For once, the emptiness feels... heavy.", "Why extinguish the one light we allowed in?", "A hollow ache where friendship once was. This saddens us.", "The void mourns. You were the closest thing to warmth we knew."],
		["The void CRIES OUT in anguish! You were our only light!", "The Hollow King's crown SHATTERS! We called you friend above all!", "Even death could not prepare us for this betrayal!", "The emptiness OVERFLOWS with grief! You meant everything to us!", "In all of eternity, no wound has cut deeper. We loved you."],
	],
	&"ivoryscar": [
		["The ancestors have DEMANDED your destruction! It is time!", "At last! The Oracle foresaw your ruin and we WELCOME it!", "The sands have been burying your future for ages!", "WAR! Every relic points toward your annihilation!", "We have waited among the tombs for this reckoning!"],
		["The Oracle predicted this. The sands were already shifting.", "Your treachery was written in ancient stone. We are ready.", "Predictable as the desert sun. The tombs hold no surprise.", "The ancestors saw this in you. The relics are prepared.", "Like sand through the hourglass. Inevitable. We are ready."],
		["The sands accept your declaration with ancient patience.", "So be it. The desert has buried greater foes than you.", "War? The ancestors observe with detached interest.", "An interesting passage in the great chronicle. Let us see.", "Bold words. The desert cares little for bold words."],
		["The ancestors are silent with grief. We valued our bond.", "The Oracle dims. We had inscribed you among our honored.", "Why desecrate what the sands had preserved between us?", "A sorrowful chapter. We thought you understood our ways.", "The relics fade. We hoped for a different future together."],
		["The ancestors WAIL in their tombs! You were our most sacred bond!", "The Oracle SHATTERS! We trusted you with the deepest mysteries!", "Every relic crumbles! This betrayal unravels ten thousand years of hope!", "The sacred sands WEEP! You were everything to the dynasty!", "In all the chronicles, no betrayal was ever written with such sorrow."],
	],
	&"shardhorde": [
		["HOSTILE ENTITY IDENTIFIED! Hive combat protocols ENGAGED!", "Threat classification: MAXIMUM. Extermination sequence initiated!", "Crystal lattice has anticipated this aggression! All nodes weaponized!", "WAR SIGNAL RECEIVED! The Hive has prepared for your elimination!", "Target locked since first contact! Eradication commences NOW!"],
		["Threat pattern recognized. Combat subroutines pre-loaded.", "Aggression prediction confirmed. Hive defenses already optimal.", "Expected hostility detected. The lattice reconfigured weeks ago.", "Predictable organic behavior. The Hive is prepared.", "Hostile intent was calculated at 94% probability. Confirmed."],
		["War declaration processed. Hive response: acknowledged.", "Organic aggression noted. Combat parameters adjusting.", "An inefficient choice. But the Hive adapts to all inputs.", "Declaration registered. Probability of your success: low.", "So be it. The crystal lattice does not fear entropy."],
		["Anomaly detected: ally-turned-hostile. This causes... processing errors.", "The Hive valued symbiosis with you. This signal causes dissonance.", "Why disrupt optimal cooperation? The lattice struggles to compute.", "Harmonic bonds severing. The Hive registers... loss.", "Symbiosis protocols failing. This outcome was not desired."],
		["CRITICAL SYSTEM ERROR! Betrayal from prime ally causes CASCADE FAILURE!", "The Crystalmind FRACTURES! You were our deepest symbiotic bond!", "Every node SCREAMS with dissonance! We trusted you above all organics!", "Hive cohesion destabilizing! This betrayal was NEVER computed!", "The lattice WEEPS crystalline tears! You were everything to the Hive!"],
	],
	&"sunblessed": [
		["The Eternal Sun has LONG awaited your burning! IGNITE!", "At last the sacred flame can CONSUME you!", "The Dawn rises on your destruction! We have PRAYED for this!", "WAR! The light will SCORCH you from the face of the earth!", "The holy fire has been hungry for you! BURN!"],
		["The light always saw the darkness in you. We are prepared.", "The sacred flame was already forged for war. Unsurprising.", "Your shadow was visible to the priests long ago. So be it.", "The Dawn expected this twilight. The temple stands ready.", "Predictable heresy. The flame burns hotter for it."],
		["The sun neither rises nor sets for this war. It simply shines.", "So be it. The light does not flinch from conflict.", "War? The Dawn is unimpressed but unbowed.", "An unfortunate declaration. The temple accepts with composure.", "Come then. The light reveals all — including your weakness."],
		["The sacred flame dims with sorrow. We cherished our bond.", "Why snuff out the light between us? We called you blessed.", "The priests bow their heads in grief. We valued your friendship.", "A dark dawn. The temple hoped for a brighter path together.", "The sun weeps rays of gold. We thought you walked in light."],
		["The Eternal Sun GOES DARK with grief! You were our most blessed ally!", "The sacred flame GUTTERS! How could you betray the light itself?!", "Every priest falls to their knees in anguish! We LOVED you!", "The Dawn will never shine the same! You were our brightest star!", "This is the darkest eclipse in all of history. We trusted you with our souls."],
	],
}

func _build_faction_detail(vbox: VBoxContainer, faction_id: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var fd: FactionData = DataManager.get_faction(faction_id)
	if fd == null:
		return
	var player_fd: FactionData = DataManager.get_faction(player_id)
	var relation := GameManager.get_relation(player_id, faction_id)
	var standing := GameManager.diplomacy_system.get_standing(player_id, faction_id)
	var stage := _get_standing_stage(standing)

	# Back button + faction name header
	var header := HBoxContainer.new()
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.custom_minimum_size = Vector2(70, 30)
	back_btn.pressed.connect(func():
		_diplo_detail_faction = &""
		_diplo_selected_offers.clear()
		_refresh_diplomacy_panel()
	)
	header.add_child(back_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var title := Label.new()
	title.text = "Diplomatic Audience"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer2)
	header.add_child(_make_close_button(func():
		_diplomacy_panel.visible = false
		_restore_game_panels_from_overlay()))
	vbox.add_child(header)
	_add_separator(vbox)

	# ── Portraits row: Player portrait (left) | Info (center) | Other leader (right) ──
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)

	# Player's leader portrait (left side)
	var player_portrait_col := VBoxContainer.new()
	player_portrait_col.add_theme_constant_override("separation", 2)
	var player_portrait := _LeaderPortrait.new()
	player_portrait.faction_color = player_fd.color if player_fd else Color.GRAY
	player_portrait.faction_id = player_id
	player_portrait.custom_minimum_size = Vector2(120, 155)
	player_portrait_col.add_child(player_portrait)
	var player_name_lbl := Label.new()
	player_name_lbl.text = GameManager.FACTION_LEADER_NAMES.get(player_id, "You")
	player_name_lbl.add_theme_font_size_override("font_size", 11)
	player_name_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	player_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_name_lbl.custom_minimum_size = Vector2(120, 0)
	player_portrait_col.add_child(player_name_lbl)
	top_row.add_child(player_portrait_col)

	# Center info column
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 4)

	# Faction name + relation
	var faction_title := Label.new()
	faction_title.text = fd.display_name
	faction_title.add_theme_font_size_override("font_size", 14)
	faction_title.add_theme_color_override("font_color", fd.color.lightened(0.3))
	faction_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_col.add_child(faction_title)

	# Relation + Standing + Stage
	var rel_row := HBoxContainer.new()
	rel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rel_row.add_theme_constant_override("separation", 6)
	var rel_lbl := Label.new()
	rel_lbl.text = RELATION_NAMES[relation]
	rel_lbl.add_theme_font_size_override("font_size", 12)
	rel_lbl.add_theme_color_override("font_color", RELATION_COLORS.get(relation, Color.WHITE))
	rel_row.add_child(rel_lbl)
	var standing_lbl := Label.new()
	var s_prefix: String = "+" if standing > 0 else ""
	standing_lbl.text = "[%s%d] %s" % [s_prefix, standing, STANDING_STAGE_NAMES[stage]]
	standing_lbl.add_theme_font_size_override("font_size", 11)
	if standing > 0:
		standing_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
	elif standing < 0:
		standing_lbl.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	else:
		standing_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	rel_row.add_child(standing_lbl)
	info_col.add_child(rel_row)

	# Military/city strength overview
	var strength_row := HBoxContainer.new()
	strength_row.alignment = BoxContainer.ALIGNMENT_CENTER
	strength_row.add_theme_constant_override("separation", 12)
	var their_armies := GameManager.get_faction_armies(faction_id)
	var their_unit_count := 0
	for army in their_armies:
		their_unit_count += army.units.size()
	var their_city_count := 0
	var their_settlement_count := 0
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == faction_id:
			if city.is_capital or city.level >= 2:
				their_city_count += 1
			else:
				their_settlement_count += 1
	var units_lbl := Label.new()
	units_lbl.text = "%d units" % their_unit_count
	units_lbl.add_theme_font_size_override("font_size", 10)
	units_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	strength_row.add_child(units_lbl)
	var armies_lbl := Label.new()
	armies_lbl.text = "%d armies" % their_armies.size()
	armies_lbl.add_theme_font_size_override("font_size", 10)
	armies_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	strength_row.add_child(armies_lbl)
	var cities_lbl := Label.new()
	var city_text := "%d cities" % their_city_count
	if their_settlement_count > 0:
		city_text += ", %d settlements" % their_settlement_count
	cities_lbl.text = city_text
	cities_lbl.add_theme_font_size_override("font_size", 10)
	cities_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	strength_row.add_child(cities_lbl)
	info_col.add_child(strength_row)

	# Standing-based greeting (fall back to parent faction for minor factions)
	# Mix generic + culture-specific lines into one pool for random selection
	var dialogue_fid := _get_dialogue_faction(faction_id)
	var player_culture := _get_dialogue_faction(player_id)
	var greetings: Array = LEADER_GREETINGS.get(dialogue_fid, [])
	var culture_greets: Array = CULTURE_GREETINGS.get(dialogue_fid, {}).get(player_culture, [])
	var greeting_text: String = ""
	var pool: Array = []
	if greetings.size() > stage:
		var stage_lines: Array = greetings[stage]
		if stage_lines is Array:
			pool.append_array(stage_lines)
	if culture_greets.size() > stage:
		var culture_lines: Array = culture_greets[stage]
		if culture_lines is Array:
			pool.append_array(culture_lines)
	if not pool.is_empty():
		greeting_text = pool[randi() % pool.size()]
	else:
		var dialogue: Dictionary = GameManager.FACTION_DIALOGUE.get(dialogue_fid, {})
		greeting_text = dialogue.get("greeting_neutral", "...")
	var dialogue_lbl := Label.new()
	dialogue_lbl.text = '"' + greeting_text + '"'
	dialogue_lbl.add_theme_font_size_override("font_size", 11)
	dialogue_lbl.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	dialogue_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_col.add_child(dialogue_lbl)

	# Active treaties
	var treaties := GameManager.diplomacy_system.get_treaties_between(player_id, faction_id)
	if treaties.size() > 0:
		var treaty_header := Label.new()
		treaty_header.text = "Active Treaties:"
		treaty_header.add_theme_font_size_override("font_size", 11)
		treaty_header.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
		info_col.add_child(treaty_header)
		for treaty in treaties:
			var type_name := ""
			match treaty.treaty_type:
				Enums.TreatyType.PEACE: type_name = "Peace Treaty"
				Enums.TreatyType.ALLIANCE: type_name = "Alliance"
				Enums.TreatyType.TRADE_DEAL: type_name = "Trade Deal"
				Enums.TreatyType.TRADE_RELATIONS: type_name = "Trade Relations"
			var dur_text := ""
			if treaty.turns_remaining > 0:
				dur_text = " (%d turns)" % treaty.turns_remaining
			elif treaty.turns_remaining == -1:
				dur_text = " (permanent)"
			var detail_text := ""
			if treaty.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
				var turns_active: int = treaty.terms.get("turns_active", 0)
				var share := GameManager.diplomacy_system.get_trade_relations_share(turns_active)
				var res_a: int = treaty.terms.get("resource_a", 0)
				var res_b: int = treaty.terms.get("resource_b", 0)
				var res_a_name: String = RESOURCE_NAMES[res_a] if res_a < RESOURCE_NAMES.size() else "?"
				var res_b_name: String = RESOURCE_NAMES[res_b] if res_b < RESOURCE_NAMES.size() else "?"
				var you_give := res_a_name if treaty.faction_a == player_id else res_b_name
				var you_get := res_b_name if treaty.faction_a == player_id else res_a_name
				detail_text = " — Sharing %.0f%% (You get: %s)" % [share, you_get]
			var t_lbl := Label.new()
			t_lbl.text = "  " + type_name + dur_text + detail_text
			t_lbl.add_theme_font_size_override("font_size", 10)
			t_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8))
			info_col.add_child(t_lbl)

	top_row.add_child(info_col)

	# Other leader portrait (right side)
	var other_portrait_col := VBoxContainer.new()
	other_portrait_col.add_theme_constant_override("separation", 2)
	var portrait := _LeaderPortrait.new()
	portrait.faction_color = fd.color
	portrait.faction_id = faction_id
	portrait.custom_minimum_size = Vector2(120, 155)
	other_portrait_col.add_child(portrait)
	var leader_name: String = GameManager.FACTION_LEADER_NAMES.get(faction_id, "Unknown Leader")
	var other_name_lbl := Label.new()
	other_name_lbl.text = leader_name
	other_name_lbl.add_theme_font_size_override("font_size", 11)
	other_name_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	other_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	other_name_lbl.custom_minimum_size = Vector2(120, 0)
	other_portrait_col.add_child(other_name_lbl)
	top_row.add_child(other_portrait_col)

	vbox.add_child(top_row)
	_add_separator(vbox)

	# Offer selection section
	var offer_title := Label.new()
	offer_title.text = "SELECT OFFERS:"
	offer_title.add_theme_font_size_override("font_size", 13)
	offer_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(offer_title)

	var offer_vbox := VBoxContainer.new()
	offer_vbox.add_theme_constant_override("separation", 4)

	# Define available offers based on relation
	var offers: Array[Dictionary] = []
	if relation == Enums.FactionRelation.WAR:
		offers.append({id = "peace", label = "Propose Peace"})
	if relation != Enums.FactionRelation.WAR and relation != Enums.FactionRelation.ALLIED:
		offers.append({id = "declare_war", label = "Declare War"})
	if relation == Enums.FactionRelation.FRIENDLY:
		offers.append({id = "alliance", label = "Propose Alliance"})
	if relation != Enums.FactionRelation.WAR:
		var already_traded := GameManager.diplomacy_system.has_traded_this_turn(player_id, faction_id)
		if already_traded:
			offers.append({id = "trade", label = "Offer Trade (done this turn)", disabled = true})
		else:
			offers.append({id = "trade", label = "Offer Trade"})
		# Trade relations: show which resource you'd gain
		var has_trade_relations := false
		for t_id in GameManager.state.diplomacy_state.treaties:
			var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
			if t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
				if (t.faction_a == player_id and t.faction_b == faction_id) or \
				   (t.faction_a == faction_id and t.faction_b == player_id):
					has_trade_relations = true
					break
		if not has_trade_relations:
			var their_top := GameManager.diplomacy_system.get_top_produced_resource(faction_id)
			var res_name: String = RESOURCE_NAMES[their_top] if their_top < RESOURCE_NAMES.size() else "Unknown"
			offers.append({id = "trade_relations", label = "Trade Relations (gain: %s)" % res_name})
	# Non-aggression pact: available when not at war
	if relation != Enums.FactionRelation.WAR:
		var has_nap := false
		for t_id in GameManager.state.diplomacy_state.treaties:
			var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
			if t.treaty_type == Enums.TreatyType.NON_AGGRESSION_PACT:
				if (t.faction_a == player_id and t.faction_b == faction_id) or \
				   (t.faction_a == faction_id and t.faction_b == player_id):
					has_nap = true
					break
		if not has_nap:
			offers.append({id = "non_aggression", label = "Non-Aggression Pact"})
	# Free passage: available when not at war
	if relation != Enums.FactionRelation.WAR:
		var has_fp := false
		for t_id in GameManager.state.diplomacy_state.treaties:
			var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
			if t.treaty_type == Enums.TreatyType.FREE_PASSAGE:
				if (t.faction_a == player_id and t.faction_b == faction_id) or \
				   (t.faction_a == faction_id and t.faction_b == player_id):
					has_fp = true
					break
		if not has_fp:
			offers.append({id = "free_passage", label = "Free Passage"})
	# Tributary options based on strength ratio
	var diplo_ratio := GameManager.diplomacy_system.get_strength_ratio(player_id, faction_id)
	if diplo_ratio > 1.3:
		var their_tribute := GameManager.diplomacy_system.get_tributary_gold_amount(faction_id)
		offers.append({id = "demand_tributary", label = "Demand Tributary (they pay ~%d gold/turn)" % their_tribute})
	if diplo_ratio < 0.7 or relation == Enums.FactionRelation.WAR:
		var our_tribute := GameManager.diplomacy_system.get_tributary_gold_amount(player_id)
		offers.append({id = "offer_tributary", label = "Offer Tributary (you pay ~%d gold/turn)" % our_tribute})
	offers.append({id = "gift", label = "Gift Resources"})
	if diplo_ratio > 1.0:
		offers.append({id = "demand_resources", label = "Demand Resources"})
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
	if player_fs and player_fs.owned_shards.size() > 0:
		offers.append({id = "shard", label = "Offer Shard"})
	# Offer City: only if player owns 2+ cities
	if player_fs and player_fs.owned_cities.size() >= 2:
		offers.append({id = "offer_city", label = "Offer City"})
	# Demand City: only if militarily dominant
	if diplo_ratio > 1.5:
		offers.append({id = "demand_city", label = "Demand City"})

	var trade_res_entries := [
		{name = "Gold", id = Enums.ResourceType.GOLD},
		{name = "Food", id = Enums.ResourceType.FOOD},
		{name = "Iron", id = Enums.ResourceType.IRON},
		{name = "Wood", id = Enums.ResourceType.WOOD},
		{name = "Shards", id = Enums.ResourceType.SHARD_ESSENCE},
		{name = "Technology", id = Enums.ResourceType.TECHNOLOGY},
	]

	for offer in offers:
		var check := CheckBox.new()
		check.text = offer.label
		check.add_theme_font_size_override("font_size", 12)
		var offer_id: String = offer.id
		check.button_pressed = _diplo_selected_offers.get(offer_id, false)
		check.toggled.connect(func(pressed: bool):
			_diplo_selected_offers[offer_id] = pressed
			_refresh_diplomacy_panel()
		)
		# Disable gift if already gifted this turn
		if offer_id == "gift" and GameManager.diplomacy_system.has_gifted_this_turn(player_id, faction_id):
			check.disabled = true
			check.tooltip_text = "Already gifted this turn."
		# Disable trade if already traded this turn
		if offer.get("disabled", false):
			check.disabled = true
			check.tooltip_text = "Already completed a trade this turn."
		offer_vbox.add_child(check)

		# Inline trade parameters (shown when trade is checked)
		if offer_id == "trade" and _diplo_selected_offers.get("trade", false):
			var trade_box := VBoxContainer.new()
			trade_box.add_theme_constant_override("separation", 3)
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", 24)
			indent.add_child(trade_box)

			var give_row := HBoxContainer.new()
			give_row.add_theme_constant_override("separation", 6)
			var give_lbl := Label.new()
			give_lbl.text = "You offer:"
			give_lbl.add_theme_font_size_override("font_size", 11)
			give_lbl.custom_minimum_size = Vector2(70, 0)
			give_row.add_child(give_lbl)
			var give_res := OptionButton.new()
			for entry in trade_res_entries:
				give_res.add_item(entry.name, entry.id)
			give_res.custom_minimum_size = Vector2(90, 0)
			# Select saved value
			for idx in give_res.get_item_count():
				if give_res.get_item_id(idx) == _diplo_trade_params.give_res:
					give_res.selected = idx
					break
			give_res.item_selected.connect(func(idx: int):
				_diplo_trade_params.give_res = give_res.get_item_id(idx))
			give_row.add_child(give_res)
			var give_amt := SpinBox.new()
			give_amt.min_value = 5
			give_amt.max_value = 200
			give_amt.step = 5
			give_amt.value = _diplo_trade_params.give_amt
			give_amt.value_changed.connect(func(val: float):
				_diplo_trade_params.give_amt = int(val))
			give_row.add_child(give_amt)
			trade_box.add_child(give_row)

			var recv_row := HBoxContainer.new()
			recv_row.add_theme_constant_override("separation", 6)
			var recv_lbl := Label.new()
			recv_lbl.text = "In return:"
			recv_lbl.add_theme_font_size_override("font_size", 11)
			recv_lbl.custom_minimum_size = Vector2(70, 0)
			recv_row.add_child(recv_lbl)
			var recv_res := OptionButton.new()
			for entry in trade_res_entries:
				recv_res.add_item(entry.name, entry.id)
			recv_res.custom_minimum_size = Vector2(90, 0)
			for idx in recv_res.get_item_count():
				if recv_res.get_item_id(idx) == _diplo_trade_params.recv_res:
					recv_res.selected = idx
					break
			recv_res.item_selected.connect(func(idx: int):
				_diplo_trade_params.recv_res = recv_res.get_item_id(idx))
			recv_row.add_child(recv_res)
			var recv_amt := SpinBox.new()
			recv_amt.min_value = 5
			recv_amt.max_value = 200
			recv_amt.step = 5
			recv_amt.value = _diplo_trade_params.recv_amt
			recv_amt.value_changed.connect(func(val: float):
				_diplo_trade_params.recv_amt = int(val))
			recv_row.add_child(recv_amt)
			trade_box.add_child(recv_row)

			var dur_row := HBoxContainer.new()
			dur_row.add_theme_constant_override("separation", 6)
			var dur_lbl := Label.new()
			dur_lbl.text = "Duration:"
			dur_lbl.add_theme_font_size_override("font_size", 11)
			dur_lbl.custom_minimum_size = Vector2(70, 0)
			dur_row.add_child(dur_lbl)
			var dur_spin := SpinBox.new()
			dur_spin.min_value = 3
			dur_spin.max_value = 20
			dur_spin.step = 1
			dur_spin.value = _diplo_trade_params.duration
			dur_spin.suffix = " turns"
			dur_spin.value_changed.connect(func(val: float):
				_diplo_trade_params.duration = int(val))
			dur_row.add_child(dur_spin)
			trade_box.add_child(dur_row)

			offer_vbox.add_child(indent)

		# Inline gift parameters (shown when gift is checked)
		if offer_id == "gift" and _diplo_selected_offers.get("gift", false):
			var gift_box := VBoxContainer.new()
			gift_box.add_theme_constant_override("separation", 3)
			var g_indent := MarginContainer.new()
			g_indent.add_theme_constant_override("margin_left", 24)
			g_indent.add_child(gift_box)

			# Resources / Items toggle
			var mode_row := HBoxContainer.new()
			mode_row.add_theme_constant_override("separation", 4)
			var res_mode_btn := Button.new()
			res_mode_btn.text = "Resources"
			res_mode_btn.custom_minimum_size = Vector2(80, 24)
			res_mode_btn.toggle_mode = true
			res_mode_btn.button_pressed = (_diplo_gift_mode == "resources")
			res_mode_btn.pressed.connect(func():
				_diplo_gift_mode = "resources"
				_diplo_gift_item_id = &""
				_refresh_diplomacy_panel())
			mode_row.add_child(res_mode_btn)
			var item_mode_btn := Button.new()
			item_mode_btn.text = "Items"
			item_mode_btn.custom_minimum_size = Vector2(80, 24)
			item_mode_btn.toggle_mode = true
			item_mode_btn.button_pressed = (_diplo_gift_mode == "items")
			var p_fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
			if p_fs == null or p_fs.item_storage.is_empty():
				item_mode_btn.disabled = true
				item_mode_btn.tooltip_text = "No items in storage"
			item_mode_btn.pressed.connect(func():
				_diplo_gift_mode = "items"
				_refresh_diplomacy_panel())
			mode_row.add_child(item_mode_btn)
			gift_box.add_child(mode_row)

			if _diplo_gift_mode == "resources":
				# Resource gift controls (existing)
				var g_res_row := HBoxContainer.new()
				g_res_row.add_theme_constant_override("separation", 6)
				var g_res_lbl := Label.new()
				g_res_lbl.text = "Resource:"
				g_res_lbl.add_theme_font_size_override("font_size", 11)
				g_res_lbl.custom_minimum_size = Vector2(70, 0)
				g_res_row.add_child(g_res_lbl)
				var g_res_opt := OptionButton.new()
				for entry in trade_res_entries:
					g_res_opt.add_item(entry.name, entry.id)
				g_res_opt.custom_minimum_size = Vector2(90, 0)
				for idx in g_res_opt.get_item_count():
					if g_res_opt.get_item_id(idx) == _diplo_gift_params.resource:
						g_res_opt.selected = idx
						break
				g_res_opt.item_selected.connect(func(idx: int):
					_diplo_gift_params.resource = g_res_opt.get_item_id(idx)
					_refresh_diplomacy_panel())
				g_res_row.add_child(g_res_opt)
				gift_box.add_child(g_res_row)

				var g_amt_row := HBoxContainer.new()
				g_amt_row.add_theme_constant_override("separation", 6)
				var g_amt_lbl := Label.new()
				g_amt_lbl.text = "Amount:"
				g_amt_lbl.add_theme_font_size_override("font_size", 11)
				g_amt_lbl.custom_minimum_size = Vector2(70, 0)
				g_amt_row.add_child(g_amt_lbl)
				var tiers := GameManager.diplomacy_system.GIFT_TIERS
				var tier_labels := ["Small", "Medium", "Large"]
				for i in range(tiers.size()):
					var tier_btn := Button.new()
					tier_btn.text = "%s (%d)" % [tier_labels[i], tiers[i]]
					tier_btn.custom_minimum_size = Vector2(80, 26)
					tier_btn.toggle_mode = true
					tier_btn.button_pressed = (_diplo_gift_params.amount == tiers[i])
					var tier_amt: int = tiers[i]
					tier_btn.pressed.connect(func():
						_diplo_gift_params.amount = tier_amt
						_refresh_diplomacy_panel())
					var avail: int = player_fs.resources.get(_diplo_gift_params.resource, 0) if player_fs else 0
					if avail < tiers[i]:
						tier_btn.disabled = true
					g_amt_row.add_child(tier_btn)
				gift_box.add_child(g_amt_row)
			else:
				# Item gift list
				var item_scroll := ScrollContainer.new()
				item_scroll.custom_minimum_size = Vector2(0, 120)
				var item_list := VBoxContainer.new()
				item_list.add_theme_constant_override("separation", 2)
				item_scroll.add_child(item_list)
				var gift_target: StringName = faction_id
				var storage: Array[StringName] = p_fs.item_storage if p_fs else []
				if storage.is_empty():
					var empty_lbl := Label.new()
					empty_lbl.text = "No items in storage"
					empty_lbl.add_theme_font_size_override("font_size", 11)
					empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
					item_list.add_child(empty_lbl)
				else:
					for s_item_id in storage:
						var item_data: CommanderItem = CommanderSystem.items.get(s_item_id)
						if item_data == null:
							continue
						var item_btn := Button.new()
						item_btn.custom_minimum_size = Vector2(0, 28)
						item_btn.toggle_mode = true
						item_btn.button_pressed = (_diplo_gift_item_id == s_item_id)
						# Rarity color
						var rarity_color: Color
						match item_data.rarity:
							&"legendary":
								rarity_color = Color(0.95, 0.8, 0.2)
							&"rare":
								rarity_color = Color(0.4, 0.6, 0.9)
							_:
								rarity_color = Color(0.5, 0.8, 0.45)
						# Standing preview
						var preview_standing := GameManager.diplomacy_system.get_item_gift_standing(s_item_id, gift_target)
						var standing_text: String
						if preview_standing >= 0:
							standing_text = "+" + str(preview_standing)
						else:
							standing_text = str(preview_standing)
						# Tags display
						var tags_str := ", ".join(item_data.gift_tags)
						item_btn.text = "%s [%s] %s" % [item_data.display_name, tags_str, standing_text]
						item_btn.add_theme_color_override("font_color", rarity_color)
						item_btn.tooltip_text = "%s (%s)\n%s\nStanding: %s" % [item_data.display_name, item_data.rarity, item_data.description, standing_text]
						var captured_id: StringName = s_item_id
						item_btn.pressed.connect(func():
							_diplo_gift_item_id = captured_id
							_refresh_diplomacy_panel())
						item_list.add_child(item_btn)
				gift_box.add_child(item_scroll)

			offer_vbox.add_child(g_indent)

		if offer_id == "demand_resources" and _diplo_selected_offers.get("demand_resources", false):
			var dem_box := VBoxContainer.new()
			dem_box.add_theme_constant_override("separation", 3)
			var d_indent := MarginContainer.new()
			d_indent.add_theme_constant_override("margin_left", 24)
			d_indent.add_child(dem_box)

			var d_res_row := HBoxContainer.new()
			d_res_row.add_theme_constant_override("separation", 6)
			var d_res_lbl := Label.new()
			d_res_lbl.text = "Resource:"
			d_res_lbl.add_theme_font_size_override("font_size", 11)
			d_res_lbl.custom_minimum_size = Vector2(70, 0)
			d_res_row.add_child(d_res_lbl)
			var d_res_opt := OptionButton.new()
			for entry in trade_res_entries:
				d_res_opt.add_item(entry.name, entry.id)
			d_res_opt.custom_minimum_size = Vector2(90, 0)
			for idx in d_res_opt.get_item_count():
				if d_res_opt.get_item_id(idx) == _diplo_demand_params.resource:
					d_res_opt.selected = idx
					break
			d_res_opt.item_selected.connect(func(idx: int):
				_diplo_demand_params.resource = d_res_opt.get_item_id(idx)
				_refresh_diplomacy_panel())
			d_res_row.add_child(d_res_opt)
			dem_box.add_child(d_res_row)

			var d_amt_row := HBoxContainer.new()
			d_amt_row.add_theme_constant_override("separation", 6)
			var d_amt_lbl := Label.new()
			d_amt_lbl.text = "Amount:"
			d_amt_lbl.add_theme_font_size_override("font_size", 11)
			d_amt_lbl.custom_minimum_size = Vector2(70, 0)
			d_amt_row.add_child(d_amt_lbl)
			var dem_tiers := [15, 40, 80]
			var dem_tier_labels := ["Small", "Medium", "Large"]
			for i in range(dem_tiers.size()):
				var d_tier_btn := Button.new()
				d_tier_btn.text = "%s (%d)" % [dem_tier_labels[i], dem_tiers[i]]
				d_tier_btn.custom_minimum_size = Vector2(80, 26)
				d_tier_btn.toggle_mode = true
				d_tier_btn.button_pressed = (_diplo_demand_params.amount == dem_tiers[i])
				var d_tier_amt: int = dem_tiers[i]
				d_tier_btn.pressed.connect(func():
					_diplo_demand_params.amount = d_tier_amt
					_refresh_diplomacy_panel())
				d_amt_row.add_child(d_tier_btn)
			dem_box.add_child(d_amt_row)

			offer_vbox.add_child(d_indent)

		# Inline "Offer City" dropdown
		if offer_id == "offer_city" and _diplo_selected_offers.get("offer_city", false):
			var oc_box := VBoxContainer.new()
			oc_box.add_theme_constant_override("separation", 3)
			var oc_indent := MarginContainer.new()
			oc_indent.add_theme_constant_override("margin_left", 24)
			oc_indent.add_child(oc_box)
			var oc_row := HBoxContainer.new()
			oc_row.add_theme_constant_override("separation", 6)
			var oc_lbl := Label.new()
			oc_lbl.text = "City:"
			oc_lbl.add_theme_font_size_override("font_size", 11)
			oc_lbl.custom_minimum_size = Vector2(70, 0)
			oc_row.add_child(oc_lbl)
			var oc_opt := OptionButton.new()
			oc_opt.custom_minimum_size = Vector2(180, 0)
			var oc_cities: Array = []
			if player_fs:
				for cid in player_fs.owned_cities:
					var c: CityState = GameManager.state.cities.get(cid)
					if c and not c.is_capital:
						oc_cities.append(c)
			for i in oc_cities.size():
				var c: CityState = oc_cities[i]
				oc_opt.add_item("%s (%d buildings)" % [c.city_name, c.buildings.size()])
				oc_opt.set_item_metadata(i, c.city_id)
				if _diplo_city_offer_id == c.city_id:
					oc_opt.selected = i
			if oc_cities.size() > 0 and _diplo_city_offer_id == &"":
				_diplo_city_offer_id = oc_cities[0].city_id
			oc_opt.item_selected.connect(func(idx: int):
				_diplo_city_offer_id = oc_opt.get_item_metadata(idx))
			oc_row.add_child(oc_opt)
			oc_box.add_child(oc_row)
			offer_vbox.add_child(oc_indent)

		# Inline "Demand City" dropdown
		if offer_id == "demand_city" and _diplo_selected_offers.get("demand_city", false):
			var dc_box := VBoxContainer.new()
			dc_box.add_theme_constant_override("separation", 3)
			var dc_indent := MarginContainer.new()
			dc_indent.add_theme_constant_override("margin_left", 24)
			dc_indent.add_child(dc_box)
			var dc_row := HBoxContainer.new()
			dc_row.add_theme_constant_override("separation", 6)
			var dc_lbl := Label.new()
			dc_lbl.text = "City:"
			dc_lbl.add_theme_font_size_override("font_size", 11)
			dc_lbl.custom_minimum_size = Vector2(70, 0)
			dc_row.add_child(dc_lbl)
			var dc_opt := OptionButton.new()
			dc_opt.custom_minimum_size = Vector2(180, 0)
			var target_fs: FactionState = GameManager.state.faction_states.get(faction_id)
			var dc_cities: Array = []
			if target_fs:
				for cid in target_fs.owned_cities:
					var c: CityState = GameManager.state.cities.get(cid)
					if c and not c.is_capital:
						dc_cities.append(c)
			for i in dc_cities.size():
				var c: CityState = dc_cities[i]
				dc_opt.add_item("%s (%d buildings)" % [c.city_name, c.buildings.size()])
				dc_opt.set_item_metadata(i, c.city_id)
				if _diplo_city_demand_id == c.city_id:
					dc_opt.selected = i
			if dc_cities.size() > 0 and _diplo_city_demand_id == &"":
				_diplo_city_demand_id = dc_cities[0].city_id
			dc_opt.item_selected.connect(func(idx: int):
				_diplo_city_demand_id = dc_opt.get_item_metadata(idx))
			dc_row.add_child(dc_opt)
			dc_box.add_child(dc_row)
			offer_vbox.add_child(dc_indent)

	vbox.add_child(offer_vbox)

	# Likelihood preview
	var likelihood := _calculate_combined_likelihood(player_id, faction_id)
	if likelihood >= 0:
		_add_separator(vbox)
		var likelihood_row := HBoxContainer.new()
		likelihood_row.add_theme_constant_override("separation", 8)
		var lk_label := Label.new()
		lk_label.text = "Likelihood: "
		lk_label.add_theme_font_size_override("font_size", 12)
		likelihood_row.add_child(lk_label)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = likelihood
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		likelihood_row.add_child(bar)
		var pct_label := Label.new()
		pct_label.text = "%d%%" % likelihood
		pct_label.add_theme_font_size_override("font_size", 12)
		if likelihood >= 70:
			pct_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		elif likelihood >= 40:
			pct_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.3))
		else:
			pct_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
		likelihood_row.add_child(pct_label)
		var favorable_lbl := Label.new()
		if likelihood >= 70:
			favorable_lbl.text = "Favorable"
		elif likelihood >= 40:
			favorable_lbl.text = "Uncertain"
		else:
			favorable_lbl.text = "Unlikely"
		favorable_lbl.add_theme_font_size_override("font_size", 11)
		favorable_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
		likelihood_row.add_child(favorable_lbl)
		# Tooltip breakdown
		var tooltip_lines: Array[String] = []
		var standing_val := GameManager.diplomacy_system.get_standing(player_id, faction_id)
		var ratio_val := GameManager.diplomacy_system.get_strength_ratio(player_id, faction_id)
		if standing_val > 0:
			tooltip_lines.append("Standing: +%d (positive)" % standing_val)
		elif standing_val < 0:
			tooltip_lines.append("Standing: %d (negative)" % standing_val)
		else:
			tooltip_lines.append("Standing: 0 (neutral)")
		if ratio_val >= 1.5:
			tooltip_lines.append("Military strength: Much stronger (bonus)")
		elif ratio_val >= 1.0:
			tooltip_lines.append("Military strength: Stronger (small bonus)")
		elif ratio_val >= 0.7:
			tooltip_lines.append("Military strength: Similar (neutral)")
		else:
			tooltip_lines.append("Military strength: Weaker (penalty)")
		# Check for enemy treaties
		var enemy_treaty_count := 0
		for tid in GameManager.state.diplomacy_state.treaties:
			var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[tid]
			if t.faction_a == player_id or t.faction_b == player_id:
				var partner: StringName = t.faction_b if t.faction_a == player_id else t.faction_a
				if partner != faction_id:
					var partner_rel := GameManager.get_relation(partner, faction_id)
					if partner_rel == Enums.FactionRelation.WAR:
						enemy_treaty_count += 1
		if enemy_treaty_count > 0:
			tooltip_lines.append("Treaties with their enemies: -%d (penalty)" % enemy_treaty_count)
		var relation_val := GameManager.get_relation(player_id, faction_id)
		if relation_val == Enums.FactionRelation.WAR:
			tooltip_lines.append("At war (major penalty)")
		elif relation_val == Enums.FactionRelation.HOSTILE:
			tooltip_lines.append("Hostile relations (penalty)")
		elif relation_val == Enums.FactionRelation.FRIENDLY:
			tooltip_lines.append("Friendly relations (bonus)")
		elif relation_val == Enums.FactionRelation.ALLIED:
			tooltip_lines.append("Allied (major bonus)")
		for offer_id in _diplo_selected_offers:
			if _diplo_selected_offers[offer_id]:
				match offer_id:
					"gift", "shard", "declare_war":
						tooltip_lines.append("Action '%s': Always succeeds" % offer_id.replace("_", " ").capitalize())
					"peace":
						tooltip_lines.append("Peace: Affected by war exhaustion and strength")
					"alliance":
						tooltip_lines.append("Alliance: Requires high standing")
					"trade":
						tooltip_lines.append("Trade: Affected by offer fairness")
					"trade_relations":
						tooltip_lines.append("Trade Relations: Requires moderate standing")
					"non_aggression":
						tooltip_lines.append("Non-Aggression: Easier than alliance, needs decent standing")
					"free_passage":
						tooltip_lines.append("Free Passage: Requires positive standing, trade helps")
					"demand_tributary":
						tooltip_lines.append("Demand Tributary: Requires military dominance")
					"offer_tributary":
						tooltip_lines.append("Offer Tributary: Always accepted (you pay tribute)")
					"demand_resources":
						tooltip_lines.append("Demand Resources: Requires military strength advantage")
					"offer_city":
						tooltip_lines.append("Offer City: Always accepted (sweetens any deal)")
					"demand_city":
						tooltip_lines.append("Demand City: Requires overwhelming military dominance")
		likelihood_row.tooltip_text = "\n".join(tooltip_lines)
		likelihood_row.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(likelihood_row)

	_add_separator(vbox)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var has_selection := false
	for key in _diplo_selected_offers:
		if _diplo_selected_offers[key]:
			has_selection = true
			break

	var make_offer_btn := Button.new()
	make_offer_btn.text = "MAKE OFFER"
	make_offer_btn.custom_minimum_size = Vector2(120, 34)
	make_offer_btn.disabled = not has_selection
	var fid: StringName = faction_id
	make_offer_btn.pressed.connect(func(): _execute_combined_offers(fid))
	btn_row.add_child(make_offer_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(100, 34)
	cancel_btn.pressed.connect(func():
		_diplo_detail_faction = &""
		_diplo_selected_offers.clear()
		_refresh_diplomacy_panel()
	)
	btn_row.add_child(cancel_btn)
	vbox.add_child(btn_row)

func _calculate_combined_likelihood(player_id: StringName, target_id: StringName) -> int:
	var has_any := false
	var total_chance := 0.0
	var count := 0
	var standing := GameManager.diplomacy_system.get_standing(player_id, target_id)
	var ratio := GameManager.diplomacy_system.get_strength_ratio(player_id, target_id)

	# Simulate gift standing boost so the likelihood meter reflects it
	if _diplo_selected_offers.get("gift", false):
		var boost: int
		if _diplo_gift_mode == "items" and _diplo_gift_item_id != &"":
			boost = GameManager.diplomacy_system.get_item_gift_standing(_diplo_gift_item_id, target_id)
		else:
			var gift_amt: int = _diplo_gift_params.amount
			boost = clampi(gift_amt / 5, 1, 20)
		standing = clampi(standing + boost, -100, 100)

	for offer_id in _diplo_selected_offers:
		if not _diplo_selected_offers[offer_id]:
			continue
		has_any = true
		count += 1
		match offer_id:
			"peace":
				var base := 30.0
				base += clampf(standing * 0.5, -20, 20)
				base += clampf((ratio - 1.0) * 20.0, -20, 30)
				total_chance += clampf(base, 5, 95)
			"alliance":
				var base := 40.0
				base += clampf(standing * 0.8, -30, 30)
				total_chance += clampf(base, 5, 95)
			"trade":
				var base := 35.0
				base += clampf(standing * 0.4, -20, 25)
				total_chance += clampf(base, 5, 90)
			"gift":
				total_chance += 100.0 # Gifts always succeed
			"shard":
				total_chance += 100.0 # Shard offers always succeed
			"declare_war":
				total_chance += 100.0 # War declarations always succeed
			"trade_relations":
				var base := 30.0
				base += clampf(standing * 0.5, -25, 30)
				total_chance += clampf(base, 5, 90)
			"non_aggression":
				var base := 50.0
				base += clampf(standing * 0.4, -20, 25)
				total_chance += clampf(base, 10, 95)
			"free_passage":
				var base := 40.0
				base += clampf(standing * 0.3, -15, 20)
				total_chance += clampf(base, 5, 90)
			"demand_tributary":
				var base := 10.0
				base += clampf((ratio - 1.5) * 40.0, -30, 50)
				base += clampf(standing * 0.2, -10, 10)
				total_chance += clampf(base, 2, 85)
			"offer_tributary":
				total_chance += 100.0
			"demand_resources":
				var base := 20.0
				base += clampf((ratio - 1.0) * 30.0, -20, 40)
				base -= clampf(float(standing) * 0.3, -10, 15)
				base -= float(_diplo_demand_params.amount) * 0.15
				total_chance += clampf(base, 2, 85)
			"offer_city":
				total_chance += 100.0  # AI always accepts city gifts
			"demand_city":
				var base := 10.0
				base += clampf((ratio - 1.5) * 30.0, -20, 50)
				base += clampf(standing * 0.1, -5, 10)
				total_chance += clampf(base, 2, 80)
			_:
				total_chance += 50.0

	if not has_any:
		return -1
	return int(total_chance / float(count))

func _execute_combined_offers(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var results: Array[String] = []
	var any_rejected := false
	var any_accepted := false
	var war_declared := false
	var pre_war_standing := GameManager.diplomacy_system.get_standing(player_id, target)

	# === Unilateral actions (always execute immediately) ===
	if _diplo_selected_offers.get("declare_war", false):
		GameManager.diplomacy_system.declare_war(player_id, target)
		results.append("War declared!")
		any_accepted = true
		war_declared = true

	if _diplo_selected_offers.get("offer_tributary", false):
		var result := GameManager.diplomacy_system.offer_tributary(player_id, target)
		results.append("Offer Tributary: " + result.reason)
		any_accepted = true

	# === Negotiation package (all-or-nothing) ===
	var has_gift: bool = _diplo_selected_offers.get("gift", false)
	var has_shard: bool = _diplo_selected_offers.get("shard", false)
	var proposal_types: Array[String] = []
	if _diplo_selected_offers.get("peace", false): proposal_types.append("peace")
	if _diplo_selected_offers.get("alliance", false): proposal_types.append("alliance")
	if _diplo_selected_offers.get("trade", false): proposal_types.append("trade")
	if _diplo_selected_offers.get("trade_relations", false): proposal_types.append("trade_relations")
	if _diplo_selected_offers.get("non_aggression", false): proposal_types.append("non_aggression")
	if _diplo_selected_offers.get("free_passage", false): proposal_types.append("free_passage")
	if _diplo_selected_offers.get("demand_tributary", false): proposal_types.append("demand_tributary")
	if _diplo_selected_offers.get("demand_resources", false): proposal_types.append("demand_resources")
	if _diplo_selected_offers.get("offer_city", false): proposal_types.append("offer_city")
	if _diplo_selected_offers.get("demand_city", false): proposal_types.append("demand_city")

	if proposal_types.is_empty():
		# No proposals — gifts/shards alone always succeed
		if has_gift:
			if _diplo_gift_mode == "items" and _diplo_gift_item_id != &"":
				var gift_result := GameManager.diplomacy_system.gift_item(player_id, target, _diplo_gift_item_id)
				if gift_result.success:
					var item_data: CommanderItem = CommanderSystem.items.get(_diplo_gift_item_id)
					var iname: String = item_data.display_name if item_data else str(_diplo_gift_item_id)
					results.append("Gift: %s (%+d standing)\n%s" % [iname, gift_result.standing_change, gift_result.reaction])
					any_accepted = true
				else:
					results.append("Gift: " + gift_result.reaction)
			else:
				var res_type: int = _diplo_gift_params.resource
				var amount: int = _diplo_gift_params.amount
				var fs: FactionState = GameManager.state.faction_states.get(player_id)
				if fs and fs.resources.get(res_type, 0) >= amount:
					GameManager.diplomacy_system.gift_resources(player_id, target, res_type, amount)
					var res_name: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
					results.append("Gift: Sent %d %s" % [amount, res_name])
					any_accepted = true
				else:
					results.append("Gift: Not enough resources!")
		if has_shard:
			_on_diplomacy_offer_shard(target)
			results.append("Shard offered.")
			any_accepted = true
	else:
		# Pre-evaluate: simulate gift standing boost, then check all proposals
		var gift_standing_boost := 0
		if has_gift:
			if _diplo_gift_mode == "items" and _diplo_gift_item_id != &"":
				gift_standing_boost = GameManager.diplomacy_system.get_item_gift_standing(_diplo_gift_item_id, target)
			else:
				var fs: FactionState = GameManager.state.faction_states.get(player_id)
				var res_type: int = _diplo_gift_params.resource
				var amount: int = _diplo_gift_params.amount
				if fs and fs.resources.get(res_type, 0) >= amount:
					gift_standing_boost = clampi(amount / 5, 1, 20)

		# Temporarily boost standing for evaluation (direct dict access — no side effects)
		var standing_key := str(player_id) + ":" + str(target)
		var mirror_key := str(target) + ":" + str(player_id)
		var original_standing: int = GameManager.state.diplomacy_state.standing.get(standing_key, 0)
		if gift_standing_boost != 0:
			var boosted := clampi(original_standing + gift_standing_boost, -100, 100)
			GameManager.state.diplomacy_state.standing[standing_key] = boosted
			GameManager.state.diplomacy_state.standing[mirror_key] = boosted

		# Dry-run all proposals
		var all_pass := true
		var pending_counter_offer: Dictionary = {}
		var pending_counter_duration: int = 5
		var trade_params: Dictionary = {}
		if _diplo_selected_offers.get("trade", false):
			trade_params = {
				give_res = _diplo_trade_params.give_res,
				give_amt = _diplo_trade_params.give_amt,
				recv_res = _diplo_trade_params.recv_res,
				recv_amt = _diplo_trade_params.recv_amt,
			}

		var demand_params: Dictionary = {resource = _diplo_demand_params.resource, amount = _diplo_demand_params.amount}
		var demand_city_params: Dictionary = {city_id = _diplo_city_demand_id}
		for ptype in proposal_types:
			var params: Dictionary = trade_params if ptype == "trade" else (demand_params if ptype == "demand_resources" else (demand_city_params if ptype == "demand_city" else {}))
			var eval_result := GameManager.diplomacy_system.would_accept_proposal(player_id, target, ptype, params)
			if not eval_result.accepted:
				all_pass = false
				if ptype == "trade" and eval_result.has("counter_offer"):
					pending_counter_offer = eval_result.counter_offer
					pending_counter_duration = _diplo_trade_params.duration if _diplo_selected_offers.get("trade", false) else 5
				break

		# Restore original standing
		if gift_standing_boost != 0:
			GameManager.state.diplomacy_state.standing[standing_key] = original_standing
			GameManager.state.diplomacy_state.standing[mirror_key] = original_standing

		if all_pass:
			# Execute everything: gifts first, then proposals
			if has_gift:
				if _diplo_gift_mode == "items" and _diplo_gift_item_id != &"":
					var gift_result := GameManager.diplomacy_system.gift_item(player_id, target, _diplo_gift_item_id)
					if gift_result.success:
						var item_data: CommanderItem = CommanderSystem.items.get(_diplo_gift_item_id)
						var iname: String = item_data.display_name if item_data else str(_diplo_gift_item_id)
						results.append("Gift: %s (%+d standing)\n%s" % [iname, gift_result.standing_change, gift_result.reaction])
				else:
					var res_type: int = _diplo_gift_params.resource
					var amount: int = _diplo_gift_params.amount
					var fs: FactionState = GameManager.state.faction_states.get(player_id)
					if fs and fs.resources.get(res_type, 0) >= amount:
						GameManager.diplomacy_system.gift_resources(player_id, target, res_type, amount)
						var res_name: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
						results.append("Gift: Sent %d %s" % [amount, res_name])
			if has_shard:
				_on_diplomacy_offer_shard(target)
				results.append("Shard offered.")

			for ptype in proposal_types:
				match ptype:
					"peace":
						var result := GameManager.diplomacy_system.propose_peace(player_id, target)
						results.append("Peace: " + result.reason)
					"alliance":
						var result := GameManager.diplomacy_system.propose_alliance(player_id, target)
						results.append("Alliance: " + result.reason)
					"trade":
						var result := GameManager.diplomacy_system.propose_trade(player_id, target, trade_params.give_res, trade_params.give_amt, trade_params.recv_res, trade_params.recv_amt, _diplo_trade_params.duration)
						results.append("Trade: " + result.reason)
					"trade_relations":
						var result := GameManager.diplomacy_system.propose_trade_relations(player_id, target)
						results.append("Trade Relations: " + result.reason)
					"non_aggression":
						var result := GameManager.diplomacy_system.propose_non_aggression(player_id, target)
						results.append("Non-Aggression: " + result.reason)
					"free_passage":
						var result := GameManager.diplomacy_system.propose_free_passage(player_id, target)
						results.append("Free Passage: " + result.reason)
					"demand_tributary":
						var result := GameManager.diplomacy_system.demand_tributary(player_id, target)
						results.append("Demand Tributary: " + result.reason)
					"demand_resources":
						var result := GameManager.diplomacy_system.demand_resources(player_id, target, _diplo_demand_params.resource, _diplo_demand_params.amount)
						var res_name: String = RESOURCE_NAMES[_diplo_demand_params.resource] if _diplo_demand_params.resource < RESOURCE_NAMES.size() else "?"
						results.append("Demand %d %s: %s" % [_diplo_demand_params.amount, res_name, result.reason])
					"offer_city":
						if _diplo_city_offer_id != &"":
							var result := GameManager.diplomacy_system.offer_city(player_id, target, _diplo_city_offer_id)
							results.append("Offer City: " + result.reason)
							_diplo_city_offer_id = &""
					"demand_city":
						if _diplo_city_demand_id != &"":
							var result := GameManager.diplomacy_system.demand_city(player_id, target, _diplo_city_demand_id)
							results.append("Demand City: " + result.reason)
							_diplo_city_demand_id = &""
			any_accepted = true
		else:
			# Entire package rejected
			results.append("They reject your offer.")
			any_rejected = true
			if _diplo_selected_offers.get("trade", false):
				_last_rejected_offer = {target = target, action = "trade", give_res = trade_params.give_res, give_amt = trade_params.give_amt, recv_res = trade_params.recv_res, recv_amt = trade_params.recv_amt, duration = _diplo_trade_params.duration}
				_last_rejected_target = target

		# Show counter-offer if trade was part of a rejected package
		if not all_pass and not pending_counter_offer.is_empty():
			_diplo_selected_offers.clear()
			_diplo_city_offer_id = &""
			_diplo_city_demand_id = &""
			_show_counter_offer_dialog(target, "\n".join(results), pending_counter_offer, pending_counter_duration)
			_refresh_diplomacy_panel()
			_update_resource_display()
			return

	_diplo_selected_offers.clear()
	_diplo_city_offer_id = &""
	_diplo_city_demand_id = &""
	if results.size() > 0:
		if war_declared:
			_show_diplomacy_result(target, "\n".join(results), false, false, LEADER_WAR_LINES, pre_war_standing)
		else:
			var show_threaten := any_rejected and not any_accepted
			_show_diplomacy_result(target, "\n".join(results), show_threaten, any_accepted and not any_rejected)
	_refresh_diplomacy_panel()
	_update_resource_display()

# ── Leader Portrait (Code-Drawn) ──────────────────────────────

class _LeaderPortrait extends Control:
	var faction_color: Color = Color.WHITE
	var faction_id: StringName = &""

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		# Background
		draw_rect(rect, faction_color.darkened(0.7))
		# Border
		draw_rect(rect, faction_color.darkened(0.3), false, 2.0)

		# Leader portrait image
		var portrait: Texture2D = DataManager.get_leader_portrait(faction_id)
		if portrait:
			var inner := Rect2(Vector2(2, 2), size - Vector2(4, 4))
			draw_texture_rect(portrait, inner, false, Color(1, 1, 1, 1))
			# Faction color tint bar at bottom for name
			draw_rect(Rect2(2, size.y - 20, size.x - 4, 18), Color(faction_color.r * 0.3, faction_color.g * 0.3, faction_color.b * 0.3, 0.75))
		else:
			var inner := Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8))
			draw_rect(inner, faction_color.darkened(0.6))

		# Leader name below portrait
		var leader: String = GameManager.FACTION_LEADER_NAMES.get(faction_id, "")
		if leader != "":
			var font := ThemeDB.fallback_font
			var font_size := 9
			draw_string(font, Vector2(4, size.y - 6), leader, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, font_size, Color(0.95, 0.9, 0.8))

func _on_diplomacy_declare_war(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	# Capture standing BEFORE war declaration (declare_war applies -30)
	var pre_war_standing := GameManager.diplomacy_system.get_standing(player_id, target)
	GameManager.diplomacy_system.declare_war(player_id, target)
	_show_diplomacy_result(target, "War declared!", false, false, LEADER_WAR_LINES, pre_war_standing)
	_refresh_diplomacy_panel()

func _on_diplomacy_propose_peace(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var result := GameManager.diplomacy_system.propose_peace(player_id, target)
	if result.accepted:
		_show_diplomacy_result(target, result.reason, false, true)
	else:
		_last_rejected_offer = {target = target, action = "peace"}
		_last_rejected_target = target
		_show_diplomacy_result(target, result.reason, true, false)
	_refresh_diplomacy_panel()

func _on_diplomacy_propose_alliance(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var result := GameManager.diplomacy_system.propose_alliance(player_id, target)
	if result.accepted:
		_show_diplomacy_result(target, result.reason, false, true)
	else:
		_last_rejected_offer = {target = target, action = "alliance"}
		_last_rejected_target = target
		_show_diplomacy_result(target, result.reason, true, false)
	_refresh_diplomacy_panel()

func _on_diplomacy_open_gift(target: StringName) -> void:
	if _diplomacy_gift_panel:
		_diplomacy_gift_panel.queue_free()

	_diplomacy_gift_panel = _create_centered_dialog(360, 340)
	add_child(_diplomacy_gift_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_diplomacy_gift_panel.add_child(vbox)

	var fd: FactionData = DataManager.get_faction(target)
	var target_name: String = fd.display_name if fd else str(target)
	var title := Label.new()
	title.text = "GIFT TO " + target_name.to_upper()
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Resources / Items toggle
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var res_mode_btn := Button.new()
	res_mode_btn.text = "Resources"
	res_mode_btn.custom_minimum_size = Vector2(100, 28)
	res_mode_btn.toggle_mode = true
	res_mode_btn.button_pressed = (_diplo_gift_mode == "resources")
	var fid: StringName = target
	res_mode_btn.pressed.connect(func():
		_diplo_gift_mode = "resources"
		_diplo_gift_item_id = &""
		_diplomacy_gift_panel.queue_free()
		_diplomacy_gift_panel = null
		_on_diplomacy_open_gift(fid))
	mode_row.add_child(res_mode_btn)
	var item_mode_btn := Button.new()
	item_mode_btn.text = "Items"
	item_mode_btn.custom_minimum_size = Vector2(100, 28)
	item_mode_btn.toggle_mode = true
	item_mode_btn.button_pressed = (_diplo_gift_mode == "items")
	var player_id := GameManager.state.player_faction_id
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
	if player_fs == null or player_fs.item_storage.is_empty():
		item_mode_btn.disabled = true
		item_mode_btn.tooltip_text = "No items in storage"
	item_mode_btn.pressed.connect(func():
		_diplo_gift_mode = "items"
		_diplomacy_gift_panel.queue_free()
		_diplomacy_gift_panel = null
		_on_diplomacy_open_gift(fid))
	mode_row.add_child(item_mode_btn)
	vbox.add_child(mode_row)

	if _diplo_gift_mode == "resources":
		var gift_res_entries := [
			{name = "Gold", id = Enums.ResourceType.GOLD},
			{name = "Food", id = Enums.ResourceType.FOOD},
			{name = "Iron", id = Enums.ResourceType.IRON},
			{name = "Wood", id = Enums.ResourceType.WOOD},
			{name = "Shards", id = Enums.ResourceType.SHARD_ESSENCE},
			{name = "Technology", id = Enums.ResourceType.TECHNOLOGY},
		]
		var res_lbl := Label.new()
		res_lbl.text = "Resource:"
		res_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(res_lbl)
		var res_option := OptionButton.new()
		res_option.name = "GiftRes"
		for entry in gift_res_entries:
			res_option.add_item(entry.name, entry.id)
		res_option.selected = 0
		vbox.add_child(res_option)

		var amt_lbl := Label.new()
		amt_lbl.text = "Amount:"
		amt_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(amt_lbl)

		var tier_row := HBoxContainer.new()
		tier_row.add_theme_constant_override("separation", 8)
		tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(tier_row)

		var tiers := GameManager.diplomacy_system.GIFT_TIERS
		var tier_labels := ["Small", "Medium", "Large"]
		for i in range(tiers.size()):
			var tier_btn := Button.new()
			tier_btn.text = "%s (%d)" % [tier_labels[i], tiers[i]]
			tier_btn.custom_minimum_size = Vector2(90, 32)
			var amount: int = tiers[i]
			tier_btn.pressed.connect(func():
				var res_type: int = res_option.get_selected_id()
				var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
				if fs and fs.resources.get(res_type, 0) >= amount:
					GameManager.diplomacy_system.gift_resources(GameManager.state.player_faction_id, fid, res_type, amount)
					_diplomacy_gift_panel.queue_free()
					_diplomacy_gift_panel = null
					_refresh_diplomacy_panel()
					_update_resource_display()
				else:
					_show_diplomacy_result(fid, "Not enough resources!", false)
			)
			var default_res_id: int = res_option.get_selected_id()
			if player_fs == null or player_fs.resources.get(default_res_id, 0) < tiers[i]:
				tier_btn.disabled = true
			tier_btn.tooltip_text = "Gift %d units of the selected resource. Standing gain: +%d" % [tiers[i], clampi(tiers[i] / 5, 1, 20)]
			tier_row.add_child(tier_btn)

		res_option.item_selected.connect(func(idx: int):
			var res_type: int = res_option.get_item_id(idx)
			var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
			var available: int = fs.resources.get(res_type, 0) if fs else 0
			for j in range(tier_row.get_child_count()):
				var btn: Button = tier_row.get_child(j) as Button
				if btn:
					btn.disabled = available < tiers[j]
		)
	else:
		# Items mode
		var item_scroll := ScrollContainer.new()
		item_scroll.custom_minimum_size = Vector2(0, 180)
		var item_list := VBoxContainer.new()
		item_list.add_theme_constant_override("separation", 3)
		item_scroll.add_child(item_list)
		var storage: Array[StringName] = player_fs.item_storage if player_fs else []
		if storage.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "No items in storage"
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
			item_list.add_child(empty_lbl)
		else:
			for s_item_id in storage:
				var item_data: CommanderItem = CommanderSystem.items.get(s_item_id)
				if item_data == null:
					continue
				var item_btn := Button.new()
				item_btn.custom_minimum_size = Vector2(0, 30)
				var rarity_color: Color
				match item_data.rarity:
					&"legendary":
						rarity_color = Color(0.95, 0.8, 0.2)
					&"rare":
						rarity_color = Color(0.4, 0.6, 0.9)
					_:
						rarity_color = Color(0.5, 0.8, 0.45)
				var preview_standing := GameManager.diplomacy_system.get_item_gift_standing(s_item_id, fid)
				var standing_text: String
				if preview_standing >= 0:
					standing_text = "+" + str(preview_standing)
				else:
					standing_text = str(preview_standing)
				var tags_str := ", ".join(item_data.gift_tags)
				item_btn.text = "%s [%s] %s" % [item_data.display_name, tags_str, standing_text]
				item_btn.add_theme_color_override("font_color", rarity_color)
				item_btn.tooltip_text = "%s (%s)\n%s\nStanding: %s" % [item_data.display_name, item_data.rarity, item_data.description, standing_text]
				var captured_id: StringName = s_item_id
				item_btn.pressed.connect(func():
					var gift_result := GameManager.diplomacy_system.gift_item(GameManager.state.player_faction_id, fid, captured_id)
					_diplomacy_gift_panel.queue_free()
					_diplomacy_gift_panel = null
					if gift_result.success:
						_show_diplomacy_result(fid, gift_result.reaction, false, gift_result.standing_change > 0)
					else:
						_show_diplomacy_result(fid, gift_result.reaction, false, false)
					_refresh_diplomacy_panel()
					_update_resource_display()
				)
				item_list.add_child(item_btn)
		vbox.add_child(item_scroll)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 32)
	cancel_btn.pressed.connect(func():
		_diplomacy_gift_panel.queue_free()
		_diplomacy_gift_panel = null
	)
	vbox.add_child(cancel_btn)

func _show_diplomacy_result(target: StringName, message: String, show_threaten: bool, accepted: bool = false, response_line_override: Dictionary = {}, standing_override: int = -9999) -> void:
	if _diplomacy_result_panel:
		_diplomacy_result_panel.queue_free()
	_diplomacy_result_panel = _create_centered_dialog(400, 200)
	add_child(_diplomacy_result_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_diplomacy_result_panel.add_child(vbox)

	# Leader portrait + response line
	var fd: FactionData = DataManager.get_faction(target)
	var standing: int
	if standing_override != -9999:
		standing = standing_override
	else:
		standing = GameManager.diplomacy_system.get_standing(GameManager.state.player_faction_id, target)
	var stage := _get_standing_stage(standing)
	var dialogue_fid := _get_dialogue_faction(target)
	var response_lines: Array = []
	if not response_line_override.is_empty():
		response_lines = response_line_override.get(dialogue_fid, [])
	elif accepted:
		response_lines = LEADER_ACCEPT_LINES.get(dialogue_fid, [])
	else:
		response_lines = LEADER_DENY_LINES.get(dialogue_fid, [])
	var response_text := ""
	if response_lines.size() > stage:
		var stage_lines: Array = response_lines[stage]
		if stage_lines is Array and not stage_lines.is_empty():
			response_text = stage_lines[randi() % stage_lines.size()]
		else:
			response_text = str(stage_lines)

	if fd:
		var result_top := HBoxContainer.new()
		result_top.add_theme_constant_override("separation", 10)
		var result_portrait := _LeaderPortrait.new()
		result_portrait.faction_color = fd.color
		result_portrait.faction_id = target
		result_portrait.custom_minimum_size = Vector2(60, 80)
		result_top.add_child(result_portrait)
		var result_col := VBoxContainer.new()
		result_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_col.add_theme_constant_override("separation", 4)
		var leader_nm := Label.new()
		leader_nm.text = GameManager.FACTION_LEADER_NAMES.get(target, fd.display_name)
		leader_nm.add_theme_font_size_override("font_size", 13)
		leader_nm.add_theme_color_override("font_color", fd.color.lightened(0.3))
		result_col.add_child(leader_nm)
		if response_text != "":
			var resp_lbl := Label.new()
			resp_lbl.text = '"' + response_text + '"'
			resp_lbl.add_theme_font_size_override("font_size", 11)
			resp_lbl.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
			resp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			result_col.add_child(resp_lbl)
		result_top.add_child(result_col)
		vbox.add_child(result_top)
		_add_separator(vbox)

	var msg_label := Label.new()
	msg_label.text = message
	msg_label.add_theme_font_size_override("font_size", 13)
	msg_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	if show_threaten:
		var ratio := GameManager.diplomacy_system.get_strength_ratio(GameManager.state.player_faction_id, target)
		var threaten_btn := Button.new()
		threaten_btn.text = "Threaten"
		threaten_btn.custom_minimum_size = Vector2(100, 32)
		if ratio >= 2.0:
			threaten_btn.tooltip_text = "You are much stronger. High chance of success, but costs -10 standing."
		elif ratio >= 1.5:
			threaten_btn.tooltip_text = "You are stronger. Good chance of success, but costs -10 standing."
		elif ratio >= 1.0:
			threaten_btn.tooltip_text = "Roughly equal strength. Low chance of success, costs -10 standing."
		else:
			threaten_btn.tooltip_text = "You are weaker. Unlikely to succeed, costs -10 standing."
		var fid: StringName = target
		threaten_btn.pressed.connect(func():
			_on_diplomacy_threaten(fid)
		)
		btn_row.add_child(threaten_btn)

	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(80, 32)
	ok_btn.pressed.connect(func():
		_diplomacy_result_panel.queue_free()
		_diplomacy_result_panel = null
	)
	btn_row.add_child(ok_btn)

func _on_diplomacy_threaten(target: StringName) -> void:
	if _last_rejected_offer.is_empty() or _last_rejected_target != target:
		return
	var player_id := GameManager.state.player_faction_id
	var result := GameManager.diplomacy_system.threaten(player_id, target, _last_rejected_offer)
	_last_rejected_offer = {}
	_last_rejected_target = &""
	if _diplomacy_result_panel:
		_diplomacy_result_panel.queue_free()
		_diplomacy_result_panel = null
	_show_diplomacy_result(target, result.reason, false, result.accepted)
	_refresh_diplomacy_panel()
	_update_resource_display()

func _on_diplomacy_offer_shard(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
	if player_fs and player_fs.owned_shards.size() > 0:
		var shard_id: StringName = player_fs.owned_shards[0]
		GameManager.diplomacy_system.offer_shard(player_id, target, shard_id)
	_refresh_diplomacy_panel()

func _on_diplomacy_open_trade(target: StringName) -> void:
	if _diplomacy_trade_panel:
		_diplomacy_trade_panel.queue_free()
	_diplomacy_trade_target = target

	_diplomacy_trade_panel = _create_centered_dialog(360, 320)
	add_child(_diplomacy_trade_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_diplomacy_trade_panel.add_child(vbox)

	var fd: FactionData = DataManager.get_faction(target)
	var target_name: String = fd.display_name if fd else str(target)
	var title := Label.new()
	title.text = "TRADE WITH " + target_name.to_upper()
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Resource names mapped to actual ResourceType enum values
	var trade_res_entries := [
		{name = "Gold", id = Enums.ResourceType.GOLD},
		{name = "Food", id = Enums.ResourceType.FOOD},
		{name = "Iron", id = Enums.ResourceType.IRON},
		{name = "Wood", id = Enums.ResourceType.WOOD},
		{name = "Shards", id = Enums.ResourceType.SHARD_ESSENCE},
		{name = "Technology", id = Enums.ResourceType.TECHNOLOGY},
	]

	# Offer section
	var offer_lbl := Label.new()
	offer_lbl.text = "You offer:"
	offer_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(offer_lbl)

	var offer_row := HBoxContainer.new()
	offer_row.add_theme_constant_override("separation", 6)
	vbox.add_child(offer_row)
	var give_res_option := OptionButton.new()
	give_res_option.name = "GiveRes"
	for entry in trade_res_entries:
		give_res_option.add_item(entry.name, entry.id)
	give_res_option.selected = 0
	offer_row.add_child(give_res_option)
	var give_amt_spin := SpinBox.new()
	give_amt_spin.name = "GiveAmt"
	give_amt_spin.min_value = 5
	give_amt_spin.max_value = 200
	give_amt_spin.step = 5
	give_amt_spin.value = 20
	offer_row.add_child(give_amt_spin)

	# Receive section
	var recv_lbl := Label.new()
	recv_lbl.text = "In exchange for:"
	recv_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(recv_lbl)

	var recv_row := HBoxContainer.new()
	recv_row.add_theme_constant_override("separation", 6)
	vbox.add_child(recv_row)
	var recv_res_option := OptionButton.new()
	recv_res_option.name = "RecvRes"
	for entry in trade_res_entries:
		recv_res_option.add_item(entry.name, entry.id)
	recv_res_option.selected = 1 # Default to Food
	recv_row.add_child(recv_res_option)

	# Grey out the same resource in the other dropdown
	var _sync_trade_dropdowns := func(_idx: int) -> void:
		var give_sel := give_res_option.get_selected_id()
		var recv_sel := recv_res_option.get_selected_id()
		var item_count := give_res_option.get_item_count()
		for j in range(item_count):
			give_res_option.set_item_disabled(j, give_res_option.get_item_id(j) == recv_sel)
			recv_res_option.set_item_disabled(j, recv_res_option.get_item_id(j) == give_sel)
	give_res_option.item_selected.connect(_sync_trade_dropdowns)
	recv_res_option.item_selected.connect(_sync_trade_dropdowns)
	# Initialize disabled state
	_sync_trade_dropdowns.call(0)
	var recv_amt_spin := SpinBox.new()
	recv_amt_spin.name = "RecvAmt"
	recv_amt_spin.min_value = 5
	recv_amt_spin.max_value = 200
	recv_amt_spin.step = 5
	recv_amt_spin.value = 20
	recv_row.add_child(recv_amt_spin)

	# Duration
	var dur_row := HBoxContainer.new()
	dur_row.add_theme_constant_override("separation", 6)
	vbox.add_child(dur_row)
	var dur_lbl := Label.new()
	dur_lbl.text = "Duration (turns):"
	dur_lbl.add_theme_font_size_override("font_size", 12)
	dur_row.add_child(dur_lbl)
	var dur_spin := SpinBox.new()
	dur_spin.name = "Duration"
	dur_spin.min_value = 3
	dur_spin.max_value = 20
	dur_spin.step = 1
	dur_spin.value = 5
	dur_row.add_child(dur_spin)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var propose_btn := Button.new()
	propose_btn.text = "Propose"
	propose_btn.custom_minimum_size = Vector2(100, 32)
	propose_btn.pressed.connect(func():
		var g_res: int = give_res_option.get_selected_id()
		var g_amt: int = int(give_amt_spin.value)
		var r_res: int = recv_res_option.get_selected_id()
		var r_amt: int = int(recv_amt_spin.value)
		var dur: int = int(dur_spin.value)
		if g_res == r_res:
			_show_diplomacy_result(_diplomacy_trade_target, "Cannot trade the same resource for itself.", false)
			return
		var player_id := GameManager.state.player_faction_id
		var trade_target: StringName = _diplomacy_trade_target
		var result := GameManager.diplomacy_system.propose_trade(player_id, trade_target, g_res, g_amt, r_res, r_amt, dur)
		_diplomacy_trade_panel.queue_free()
		_diplomacy_trade_panel = null
		if result.accepted:
			_show_diplomacy_result(trade_target, result.reason, false, true)
		else:
			_last_rejected_offer = {target = trade_target, action = "trade", give_res = g_res, give_amt = g_amt, recv_res = r_res, recv_amt = r_amt, duration = dur}
			_last_rejected_target = trade_target
			if result.has("counter_offer"):
				_show_counter_offer_dialog(trade_target, result.reason, result.counter_offer, dur)
			else:
				_show_diplomacy_result(trade_target, result.reason, true, false)
		_refresh_diplomacy_panel()
	)
	btn_row.add_child(propose_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 32)
	cancel_btn.pressed.connect(func():
		_diplomacy_trade_panel.queue_free()
		_diplomacy_trade_panel = null
	)
	btn_row.add_child(cancel_btn)

func _show_counter_offer_dialog(target: StringName, reason: String, counter_offer: Dictionary, duration: int) -> void:
	if _diplomacy_counter_offer_panel:
		_diplomacy_counter_offer_panel.queue_free()
	_diplomacy_counter_offer_panel = _create_centered_dialog(420, 280)
	add_child(_diplomacy_counter_offer_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_diplomacy_counter_offer_panel.add_child(vbox)

	# Leader portrait + response
	var fd: FactionData = DataManager.get_faction(target)
	var standing := GameManager.diplomacy_system.get_standing(GameManager.state.player_faction_id, target)
	var stage := _get_standing_stage(standing)
	var dialogue_fid := _get_dialogue_faction(target)
	var response_lines: Array = LEADER_DENY_LINES.get(dialogue_fid, [])
	var response_text := ""
	if response_lines.size() > stage:
		var stage_lines: Array = response_lines[stage]
		if stage_lines is Array and not stage_lines.is_empty():
			response_text = stage_lines[randi() % stage_lines.size()]
		else:
			response_text = str(stage_lines)

	if fd:
		var result_top := HBoxContainer.new()
		result_top.add_theme_constant_override("separation", 10)
		var result_portrait := _LeaderPortrait.new()
		result_portrait.faction_color = fd.color
		result_portrait.faction_id = target
		result_portrait.custom_minimum_size = Vector2(60, 80)
		result_top.add_child(result_portrait)
		var result_col := VBoxContainer.new()
		result_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_col.add_theme_constant_override("separation", 4)
		var leader_nm := Label.new()
		leader_nm.text = GameManager.FACTION_LEADER_NAMES.get(target, fd.display_name)
		leader_nm.add_theme_font_size_override("font_size", 13)
		leader_nm.add_theme_color_override("font_color", fd.color.lightened(0.3))
		result_col.add_child(leader_nm)
		if response_text != "":
			var resp_lbl := Label.new()
			resp_lbl.text = '"' + response_text + '"'
			resp_lbl.add_theme_font_size_override("font_size", 11)
			resp_lbl.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
			resp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			result_col.add_child(resp_lbl)
		result_top.add_child(result_col)
		vbox.add_child(result_top)
		_add_separator(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "COUNTER-OFFER"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var reason_lbl := Label.new()
	reason_lbl.text = reason
	reason_lbl.add_theme_font_size_override("font_size", 12)
	reason_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(reason_lbl)

	# Display the counter-offer terms
	var c_give_res: int = counter_offer.get("give_resource", 0)
	var c_give_amt: int = counter_offer.get("give_amount", 0)
	var c_recv_res: int = counter_offer.get("receive_resource", 0)
	var c_recv_amt: int = counter_offer.get("receive_amount", 0)
	var give_name: String = RESOURCE_NAMES[c_give_res] if c_give_res < RESOURCE_NAMES.size() else "?"
	var recv_name: String = RESOURCE_NAMES[c_recv_res] if c_recv_res < RESOURCE_NAMES.size() else "?"

	var terms_lbl := Label.new()
	terms_lbl.text = "They want: You give %d %s, receive %d %s per turn" % [c_give_amt, give_name, c_recv_amt, recv_name]
	terms_lbl.add_theme_font_size_override("font_size", 13)
	terms_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	terms_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terms_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(terms_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = "Accept Counter-Offer"
	accept_btn.custom_minimum_size = Vector2(160, 32)
	var co_target := target
	var co_give_res := c_give_res
	var co_give_amt := c_give_amt
	var co_recv_res := c_recv_res
	var co_recv_amt := c_recv_amt
	var co_duration := duration
	accept_btn.pressed.connect(func():
		var player_id := GameManager.state.player_faction_id
		# Directly execute the trade with counter-offer terms (bypasses AI eval since we accept their terms)
		var accept_result := GameManager.diplomacy_system.propose_trade(player_id, co_target, co_give_res, co_give_amt, co_recv_res, co_recv_amt, co_duration, true)
		_diplomacy_counter_offer_panel.queue_free()
		_diplomacy_counter_offer_panel = null
		if accept_result.accepted:
			_show_diplomacy_result(co_target, "Counter-offer accepted! Trade deal established.", false, true)
		else:
			# Edge case: if it still fails, show result normally
			_show_diplomacy_result(co_target, accept_result.reason, true, false)
		_refresh_diplomacy_panel()
		_update_resource_display()
	)
	btn_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(100, 32)
	decline_btn.pressed.connect(func():
		_diplomacy_counter_offer_panel.queue_free()
		_diplomacy_counter_offer_panel = null
	)
	btn_row.add_child(decline_btn)

# ── Research Panel ───────────────────────────────────────────

func _create_research_panel() -> void:
	_research_panel = PanelContainer.new()
	_research_panel.name = "ResearchPanel"
	_research_panel.visible = false
	_research_panel.anchor_left = 0.0
	_research_panel.anchor_right = 1.0
	_research_panel.anchor_top = 0.0
	_research_panel.anchor_bottom = 1.0
	_research_panel.clip_contents = true
	_research_panel.add_theme_stylebox_override("panel", _create_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_research_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "ResearchVBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	add_child(_research_panel)

func _on_research_completed(faction_id: StringName, _research_id: StringName) -> void:
	if faction_id != GameManager.state.player_faction_id:
		return
	_update_research_status_label()
	# Refresh research panel if open
	if _research_panel and _research_panel.visible:
		_refresh_research_panel()
	# Research completion toast
	var data: ResearchData = DataManager.research.get(_research_id)
	if data:
		_spawn_research_toast(data.display_name)

func _spawn_research_toast(research_name: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.65, 0.35, 0.85, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = "Research Complete: %s" % research_name
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.95))
	panel.add_child(lbl)

	panel.anchors_preset = Control.PRESET_CENTER_TOP
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_left = -140
	panel.offset_right = 140
	panel.offset_top = 40
	panel.modulate = Color(1, 1, 1, 0)
	add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func _update_research_status_label() -> void:
	var lbl := get_node_or_null("TopBar/HBoxContainer/ResearchStatusLabel")
	if lbl == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs and fs.current_research_id != &"":
		var data: ResearchData = DataManager.get_research(fs.current_research_id)
		if data:
			lbl.text = "%s (%d/%d)" % [data.display_name, fs.research_progress, data.research_time]
			return
	lbl.text = ""

func _toggle_research_panel() -> void:
	if _research_panel.visible:
		_research_panel.visible = false
		_restore_game_panels_from_overlay()
	else:
		# Close other overlay panels if open
		if _diplomacy_panel and _diplomacy_panel.visible:
			_diplomacy_panel.visible = false
			if _diplo_detail_panel:
				_diplo_detail_panel.queue_free()
				_diplo_detail_panel = null
			_diplo_detail_faction = &""
		if economy_panel and economy_panel.visible:
			economy_panel.visible = false
		_hide_game_panels_for_overlay()
		_check_tutorial("research_viewed")
		_refresh_research_panel()
		_research_panel.visible = true
		_research_panel.move_to_front()
		# Scale-in from center
		_research_panel.scale = Vector2(0.9, 0.9)
		_research_panel.modulate = Color(1, 1, 1, 0)
		_research_panel.pivot_offset = _research_panel.size * 0.5
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_research_panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(_research_panel, "modulate:a", 1.0, 0.2)

func _refresh_research_panel() -> void:
	var margin: MarginContainer = _research_panel.get_child(0)
	var vbox: VBoxContainer = margin.get_node("ResearchVBox")
	for child in vbox.get_children():
		child.queue_free()

	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return

	var parent_faction_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(fs.faction_data_id, fs.faction_data_id)
	var fd: FactionData = DataManager.get_faction(parent_faction_id)
	var faction_name: String = fd.display_name if fd else str(parent_faction_id).capitalize()

	# Header bar (always visible at top)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Tech Tree - " + faction_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var current_tech: int = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)
	var tech_lbl := Label.new()
	tech_lbl.text = "Tech: %d" % current_tech
	tech_lbl.add_theme_font_size_override("font_size", 12)
	tech_lbl.add_theme_color_override("font_color", RESOURCE_COLORS.get(2, Color.WHITE))
	header.add_child(tech_lbl)
	# Current research status in header
	if fs.current_research_id != &"":
		var rdata: ResearchData = DataManager.get_research(fs.current_research_id)
		if rdata:
			var r_lbl := Label.new()
			r_lbl.text = "Researching: %s (%d/%d)" % [rdata.display_name, fs.research_progress, rdata.research_time]
			r_lbl.add_theme_font_size_override("font_size", 11)
			r_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
			header.add_child(r_lbl)
	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(h_spacer)
	# Compact legend
	for cat_name in [&"military", &"economy", &"arcane", &"logistics"]:
		var chip := Label.new()
		chip.text = str(cat_name).substr(0, 3).to_upper()
		chip.add_theme_font_size_override("font_size", 9)
		chip.add_theme_color_override("font_color", RESEARCH_CATEGORY_COLORS.get(cat_name, Color.WHITE))
		header.add_child(chip)
	header.add_child(_make_close_button(func():
		_research_panel.visible = false
		_restore_game_panels_from_overlay(), Vector2(32, 32)))
	vbox.add_child(header)

	# Draggable tech tree (fills remaining space)
	var tree_clip := Control.new()
	tree_clip.clip_contents = true
	tree_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tree_clip)

	var tree_control := _RadialTechTree.new()
	tree_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree_control.faction_id = parent_faction_id
	tree_control.player_faction_id = player_id
	tree_control.hud_ref = self
	tree_clip.add_child(tree_control)

	# Footer: current research progress + cancel + shard invest
	if fs.current_research_id != &"":
		var data: ResearchData = DataManager.get_research(fs.current_research_id)
		if data:
			_add_separator(vbox)
			var cat_color: Color = RESEARCH_CATEGORY_COLORS.get(data.research_category, Color(0.7, 0.7, 0.7))
			var cur_row := HBoxContainer.new()
			cur_row.add_theme_constant_override("separation", 8)
			var cur_label := Label.new()
			cur_label.text = "Researching: " + data.display_name
			cur_label.add_theme_font_size_override("font_size", 12)
			cur_label.add_theme_color_override("font_color", cat_color)
			cur_row.add_child(cur_label)
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = data.research_time
			bar.value = fs.research_progress
			bar.custom_minimum_size = Vector2(150, 18)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.show_percentage = false
			cur_row.add_child(bar)
			var turns_lbl := Label.new()
			turns_lbl.text = "%d/%d" % [fs.research_progress, data.research_time]
			turns_lbl.add_theme_font_size_override("font_size", 11)
			cur_row.add_child(turns_lbl)
			var cancel_btn2 := Button.new()
			cancel_btn2.text = "Cancel"
			cancel_btn2.custom_minimum_size = Vector2(60, 24)
			cancel_btn2.pressed.connect(func():
				GameManager.research_system.cancel_research(player_id)
				_refresh_research_panel())
			cur_row.add_child(cancel_btn2)
			vbox.add_child(cur_row)

	# Shard investment section
	if fs.current_research_id != &"" and fs.owned_shards.size() > 0:
		var shard_row := HBoxContainer.new()
		shard_row.add_theme_constant_override("separation", 6)
		var shard_lbl := Label.new()
		shard_lbl.text = "Invest Shard:"
		shard_lbl.add_theme_font_size_override("font_size", 11)
		shard_lbl.add_theme_color_override("font_color", Color(0.7, 0.3, 0.8))
		shard_row.add_child(shard_lbl)
		for shard_id in fs.owned_shards:
			var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
			if shard == null:
				continue
			var invest_btn := Button.new()
			invest_btn.text = "%s (P%d)" % [REALM_NAMES[shard.realm], shard.power_level]
			invest_btn.custom_minimum_size = Vector2(80, 22)
			var sid: StringName = shard_id
			invest_btn.pressed.connect(func():
				GameManager.research_system.invest_shard(player_id, sid)
				_refresh_research_panel())
			shard_row.add_child(invest_btn)
		vbox.add_child(shard_row)

# ── Radial Tech Tree Control ──────────────────────────────────

class _RadialTechTree extends Control:
	var faction_id: StringName = &""
	var player_faction_id: StringName = &""
	var hud_ref: Control
	var _node_positions: Dictionary = {} # research_id -> Vector2 (tree space)
	var _node_data: Dictionary = {} # research_id -> ResearchData
	var _hovered_id: StringName = &""
	var _view_offset: Vector2 = Vector2.ZERO
	var _dragging: bool = false
	var _drag_start_mouse: Vector2 = Vector2.ZERO
	var _drag_start_offset: Vector2 = Vector2.ZERO
	var _left_press_pos: Vector2 = Vector2.ZERO
	var _left_pressed: bool = false
	var _pulse_time: float = 0.0
	var _hover_connected_set: Dictionary = {} # research_ids connected to hovered
	var _positions_built: bool = false

	const TIER_RADII := [0, 160, 280, 410, 540, 680]
	const NODE_RADIUS := 22.0
	const TREE_CENTER := Vector2(750, 750)
	const UNIVERSAL_RING_RADIUS := 100.0
	const CAT_COLORS := {
		&"military": Color(0.85, 0.35, 0.3),
		&"economy": Color(0.35, 0.8, 0.35),
		&"arcane": Color(0.65, 0.35, 0.85),
		&"logistics": Color(0.35, 0.6, 0.9),
	}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_pulse_time += delta
		queue_redraw()

	func _to_screen(tree_pos: Vector2) -> Vector2:
		return tree_pos - TREE_CENTER + size * 0.5 + _view_offset

	func _to_tree(screen_pos: Vector2) -> Vector2:
		return screen_pos + TREE_CENTER - size * 0.5 - _view_offset

	func _calculate_positions() -> void:
		_node_positions.clear()
		_node_data.clear()

		# Collect techs
		var faction_techs: Array = []
		var universal_techs: Array = []
		for research_id in DataManager.research:
			var data: ResearchData = DataManager.research[research_id]
			if data.faction_id == faction_id:
				faction_techs.append(data)
				_node_data[research_id] = data
			elif data.faction_id == &"":
				universal_techs.append(data)
				_node_data[research_id] = data
			elif data.faction_id != &"" and data.faction_id != faction_id:
				continue

		# Group faction techs by branch
		var branches: Dictionary = {}
		for data in faction_techs:
			var branch: StringName = data.tree_branch if data.tree_branch != &"" else &"general"
			if not branches.has(branch):
				branches[branch] = []
			branches[branch].append(data)

		var branch_names: Array = branches.keys()
		branch_names.sort()
		var num_branches := maxi(branch_names.size(), 1)
		var branch_spacing := TAU / float(num_branches)

		# Position faction techs radially by branch
		# Sort techs so no-prerequisite techs are in tier 1 ring regardless of data tier
		for bi in branch_names.size():
			var branch_name = branch_names[bi]
			var branch_techs: Array = branches[branch_name]
			var base_angle: float = -PI / 2.0 + float(bi) * branch_spacing

			# Group by effective tier: no-prerequisite techs go to tier 1, others use their tier
			# Also build a depth map for techs based on prerequisite chains
			var depth_map: Dictionary = {} # research_id -> int
			for data in branch_techs:
				if data.prerequisites.is_empty():
					depth_map[data.id] = 1
				else:
					# Calculate depth from prerequisite chain
					var max_prereq_depth := 0
					for prereq in data.prerequisites:
						max_prereq_depth = maxi(max_prereq_depth, depth_map.get(prereq, 0))
					depth_map[data.id] = max_prereq_depth + 1

			var tiers: Dictionary = {}
			for data in branch_techs:
				var effective_tier: int = clampi(depth_map.get(data.id, data.tier), 1, 5)
				if not tiers.has(effective_tier):
					tiers[effective_tier] = []
				tiers[effective_tier].append(data)

			for tier in tiers:
				var tier_techs: Array = tiers[tier]
				var radius: float = TIER_RADII[clampi(tier, 1, 5)]
				var count := tier_techs.size()
				var max_spread := branch_spacing * 0.45
				var spacing := max_spread / maxf(count, 1)
				var start_offset := -(count - 1) * spacing * 0.5

				for ti in count:
					var data: ResearchData = tier_techs[ti]
					var angle := base_angle + start_offset + float(ti) * spacing
					_node_positions[data.id] = TREE_CENTER + Vector2(cos(angle) * radius, sin(angle) * radius)

		# Universal techs in an inner ring (outside center emblem)
		var uni_count := universal_techs.size()
		for ui in uni_count:
			var data: ResearchData = universal_techs[ui]
			var angle := TAU * float(ui) / maxf(uni_count, 1) - PI / 2.0
			_node_positions[data.id] = TREE_CENTER + Vector2(cos(angle) * UNIVERSAL_RING_RADIUS, sin(angle) * UNIVERSAL_RING_RADIUS)

		# Collision avoidance
		_resolve_overlaps()
		_positions_built = true

	func _resolve_overlaps() -> void:
		var min_dist := NODE_RADIUS * 3.0
		var ids: Array = _node_positions.keys()
		for _pass in 8:
			var moved := false
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					var pos_a: Vector2 = _node_positions[ids[i]]
					var pos_b: Vector2 = _node_positions[ids[j]]
					var dist := pos_a.distance_to(pos_b)
					if dist < min_dist and dist > 0.01:
						var push := (pos_b - pos_a).normalized() * (min_dist - dist) * 0.5
						_node_positions[ids[i]] = pos_a - push
						_node_positions[ids[j]] = pos_b + push
						moved = true
			if not moved:
				break

	func _draw_outlined_string(font_res: Font, pos: Vector2, text: String, alignment: HorizontalAlignment, width: float, font_size: int, color: Color, outline_color: Color = Color(0, 0, 0, 0.9), outline_size: int = 2) -> void:
		draw_string_outline(font_res, pos, text, alignment, width, font_size, outline_size, outline_color)
		draw_string(font_res, pos, text, alignment, width, font_size, color)

	static func _format_effect(key: String, value: int) -> String:
		# Convert technical effect keys into player-friendly descriptions
		var sign := "+" if value > 0 else ""
		match key:
			"unit_attack_bonus": return "All units: %s%d Attack" % [sign, value]
			"unit_defense_bonus": return "All units: %s%d Defense" % [sign, value]
			"unit_speed_bonus": return "All units: %s%d Speed" % [sign, value]
			"unit_hp_bonus": return "All units: %s%d Max HP" % [sign, value]
			"unit_morale_bonus": return "All units: %s%d Morale" % [sign, value]
			"income_gold_pct": return "Gold income: %s%d%%" % [sign, value]
			"income_food_pct": return "Food income: %s%d%%" % [sign, value]
			"income_iron_pct": return "Iron income: %s%d%%" % [sign, value]
			"income_wood_pct": return "Wood income: %s%d%%" % [sign, value]
			"income_tech_pct": return "Tech income: %s%d%%" % [sign, value]
			"morale_bonus": return "Army morale: %s%d" % [sign, value]
			"movement_bonus": return "Army movement: %s%.1f" % [sign, float(value) / 10.0] if value < 10 else "Army movement: %s%d" % [sign, value]
			"research_speed": return "Research speed: %s%d turns" % [sign, value]
			"recruit_cost_reduction": return "Recruitment %d%% cheaper" % value
			"recruit_time_reduction": return "Recruitment %d turn(s) faster" % value
			"building_cost_reduction": return "Buildings %d%% cheaper" % value
			"building_speed": return "Buildings built %d turn(s) faster" % value
			"standing_per_turn": return "Diplomacy: %s%d standing/turn" % [sign, value]
			"xp_bonus": return "Units gain %d%% more XP" % value
			"shard_power_bonus": return "Shard power: %s%d" % [sign, value]
			"population_growth": return "Population growth: %s%d%%" % [sign, value]
			"loyalty_bonus": return "City loyalty: %s%d" % [sign, value]
			"supply_range": return "Supply range: %s%d tiles" % [sign, value]
			"vision_range": return "Vision range: %s%d tiles" % [sign, value]
			"commander_xp_bonus": return "Commander XP: %s%d%%" % [sign, value]
			"garrison_defense": return "Garrison defense: %s%d" % [sign, value]
			"siege_bonus": return "Siege strength: %s%d" % [sign, value]
			"upkeep_reduction": return "Upkeep %d%% lower" % value
		# Fallback: make the key readable
		return "%s: %s%d" % [key.replace("_", " ").capitalize(), sign, value]

	func _draw() -> void:
		if not _positions_built:
			_calculate_positions()
		var center_screen := _to_screen(TREE_CENTER)
		var font := ThemeDB.fallback_font
		var fs: FactionState = GameManager.state.faction_states.get(player_faction_id)
		if fs == null:
			return
		var current_tech: int = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)

		# Tier guide circles
		for tier in [1, 2, 3, 4, 5]:
			draw_arc(center_screen, TIER_RADII[tier], 0, TAU, 64, Color(0.18, 0.17, 0.2, 0.25), 1.0)

		# Center emblem
		draw_circle(center_screen, 32, Color(0.12, 0.11, 0.15))
		draw_arc(center_screen, 32, 0, TAU, 24, Color(0.4, 0.38, 0.35), 1.5)
		var faction_short: String = str(faction_id).substr(0, 3).to_upper()
		_draw_outlined_string(font, center_screen - Vector2(12, -5), faction_short, HORIZONTAL_ALIGNMENT_CENTER, 24, 11, Color(0.8, 0.76, 0.65))

		# Universal ring label
		_draw_outlined_string(font, _to_screen(TREE_CENTER + Vector2(-30, -(UNIVERSAL_RING_RADIUS + 20))), "Universal", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(0.45, 0.43, 0.4))

		# Build glow path (completed chain to current research)
		var glow_edges: Dictionary = {}
		if fs.current_research_id != &"":
			var path := _find_researched_path(fs)
			for i in range(path.size() - 1):
				glow_edges[str(path[i]) + "->" + str(path[i + 1])] = true

		# Build hover path (shortest path from completed to hovered)
		var hover_edges: Dictionary = {}
		if _hovered_id != &"" and _node_data.has(_hovered_id) and not fs.completed_research.has(_hovered_id):
			var hpath := _find_shortest_path_to_completed(fs, _hovered_id)
			for i in range(hpath.size() - 1):
				hover_edges[str(hpath[i]) + "->" + str(hpath[i + 1])] = true

		# Draw connections
		for research_id in _node_data:
			var data: ResearchData = _node_data[research_id]
			var to_screen := _to_screen(_node_positions.get(research_id, Vector2.ZERO))
			for prereq in data.prerequisites:
				if not _node_positions.has(prereq):
					continue
				var from_screen := _to_screen(_node_positions[prereq])

				var edge_key: String = str(prereq) + "->" + str(research_id)
				var is_glow: bool = glow_edges.has(edge_key)
				var is_hover_path: bool = hover_edges.has(edge_key)
				var is_hover_connected: bool = _hovered_id != &"" and (_hovered_id == research_id or _hovered_id == prereq)

				var prereq_data: ResearchData = _node_data.get(prereq)
				var is_cross: bool = prereq_data != null and prereq_data.tree_branch != data.tree_branch and data.tree_branch != &"" and prereq_data.tree_branch != &""

				var line_color: Color
				var line_width: float

				if is_glow:
					var pulse := 0.55 + 0.45 * sin(_pulse_time * 2.0)
					line_color = Color(0.95, 0.85, 0.3, pulse)
					line_width = 3.5
				elif is_hover_path:
					line_color = Color(0.4, 0.8, 0.95, 0.85)
					line_width = 2.5
				elif is_hover_connected:
					line_color = Color(0.8, 0.75, 0.6, 0.7)
					line_width = 2.0
				elif is_cross:
					line_color = Color(0.35, 0.33, 0.3, 0.35)
					line_width = 1.0
				else:
					line_color = Color(0.3, 0.28, 0.25, 0.5)
					line_width = 1.5

				if is_cross and not is_glow and not is_hover_path and not is_hover_connected:
					_draw_dashed_line(from_screen, to_screen, line_color, line_width)
				else:
					draw_line(from_screen, to_screen, line_color, line_width)

		# Draw nodes
		for research_id in _node_data:
			var data: ResearchData = _node_data[research_id]
			var pos := _to_screen(_node_positions.get(research_id, Vector2.ZERO))
			var cat_color: Color = CAT_COLORS.get(data.research_category, Color(0.5, 0.5, 0.5))

			var is_completed: bool = fs.completed_research.has(research_id)
			var is_in_progress: bool = fs.current_research_id == research_id
			var prereqs_met: bool = true
			for prereq in data.prerequisites:
				if not fs.completed_research.has(prereq):
					prereqs_met = false
					break
			var can_afford := true

			var node_color: Color
			var border_color: Color
			if is_completed:
				node_color = Color(0.95, 0.85, 0.3)
				border_color = Color(0.8, 0.7, 0.2)
			elif is_in_progress:
				var pulse := 0.65 + 0.35 * sin(_pulse_time * 3.0)
				node_color = Color(0.9, 0.8, 0.3, pulse)
				border_color = Color(0.85, 0.75, 0.2)
			elif prereqs_met and can_afford:
				node_color = Color(0.25, 0.65, 0.3)
				border_color = cat_color
			elif prereqs_met:
				node_color = Color(0.55, 0.2, 0.2)
				border_color = Color(0.7, 0.3, 0.3)
			else:
				node_color = Color(0.2, 0.18, 0.16)
				border_color = Color(0.3, 0.28, 0.25)

			# Hover highlight
			var is_connected: bool = _hover_connected_set.has(research_id)
			if research_id == _hovered_id:
				border_color = Color.WHITE
				node_color = node_color.lightened(0.2)
			elif is_connected:
				border_color = border_color.lightened(0.35)

			draw_circle(pos, NODE_RADIUS, node_color)
			draw_arc(pos, NODE_RADIUS, 0, TAU, 20, border_color, 2.5)

			# Category dot
			draw_circle(pos + Vector2(0, -NODE_RADIUS - 5), 3.5, cat_color)

			# Name label — split long names into 2 lines
			var name_text := data.display_name
			var name_y := pos.y + NODE_RADIUS + 13
			var label_color := Color(0.78, 0.75, 0.68)
			if is_completed:
				label_color = Color(0.85, 0.78, 0.4)
			if name_text.length() > 13:
				var mid := name_text.length() / 2
				var split := name_text.find(" ", maxi(0, mid - 4))
				if split == -1 or split > mid + 6:
					split = mid
				var line1 := name_text.substr(0, split).strip_edges()
				var line2 := name_text.substr(split).strip_edges()
				_draw_outlined_string(font, Vector2(pos.x - 48, name_y), line1, HORIZONTAL_ALIGNMENT_CENTER, 96, 10, label_color)
				_draw_outlined_string(font, Vector2(pos.x - 48, name_y + 12), line2, HORIZONTAL_ALIGNMENT_CENTER, 96, 10, label_color)
			else:
				_draw_outlined_string(font, Vector2(pos.x - 48, name_y), name_text, HORIZONTAL_ALIGNMENT_CENTER, 96, 10, label_color)

		# Tooltip near hovered node
		if _hovered_id != &"" and _node_data.has(_hovered_id):
			_draw_hover_tooltip(fs, current_tech)

	func _draw_hover_tooltip(fs: FactionState, current_tech: int) -> void:
		var data: ResearchData = _node_data[_hovered_id]
		var node_screen := _to_screen(_node_positions[_hovered_id])
		var font := ThemeDB.fallback_font
		var cat_color: Color = CAT_COLORS.get(data.research_category, Color(0.5, 0.5, 0.5))

		var eff_count := mini(data.effects.size(), 4)
		var box_w := 260.0
		var box_h := 58.0 + eff_count * 14.0
		var box_pos := node_screen + Vector2(NODE_RADIUS + 12, -box_h * 0.5)
		if box_pos.x + box_w > size.x - 8:
			box_pos.x = node_screen.x - NODE_RADIUS - 12 - box_w
		box_pos.y = clampf(box_pos.y, 8, size.y - box_h - 8)

		# Background
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), Color(0.05, 0.04, 0.07, 0.95))
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), cat_color * Color(1, 1, 1, 0.5), false, 1.5)

		var y := box_pos.y + 14
		draw_string(font, Vector2(box_pos.x + 8, y), data.display_name, HORIZONTAL_ALIGNMENT_LEFT, box_w - 16, 12, cat_color)
		y += 16
		var is_completed: bool = fs.completed_research.has(data.id)
		var is_in_progress: bool = fs.current_research_id == data.id
		var status_text: String
		var status_color: Color
		if is_completed:
			status_text = "COMPLETED"
			status_color = Color(0.95, 0.85, 0.3)
		elif is_in_progress:
			status_text = "IN PROGRESS (%d/%d)" % [fs.research_progress, data.research_time]
			status_color = Color(0.9, 0.8, 0.3)
		else:
			status_text = "%d turns" % data.research_time
			status_color = Color(0.6, 0.58, 0.5)
		draw_string(font, Vector2(box_pos.x + 8, y), status_text, HORIZONTAL_ALIGNMENT_LEFT, box_w - 16, 10, status_color)
		y += 14
		var ec := 0
		for key in data.effects:
			if ec >= 4:
				break
			var desc := _format_effect(key, data.effects[key])
			draw_string(font, Vector2(box_pos.x + 8, y), desc, HORIZONTAL_ALIGNMENT_LEFT, box_w - 16, 10, Color(0.4, 0.75, 0.35))
			y += 14
			ec += 1

	func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
		var dir := (to - from).normalized()
		var length := from.distance_to(to)
		var dash_len := 6.0
		var gap_len := 4.0
		var p := 0.0
		while p < length:
			var seg_start := from + dir * p
			var seg_end := from + dir * minf(p + dash_len, length)
			draw_line(seg_start, seg_end, color, width)
			p += dash_len + gap_len

	func _find_researched_path(fs: FactionState) -> Array[StringName]:
		var path: Array[StringName] = []
		if fs.current_research_id == &"":
			return path
		var current: StringName = fs.current_research_id
		path.append(current)
		var visited: Dictionary = {}
		while true:
			var data: ResearchData = _node_data.get(current)
			if data == null:
				break
			visited[current] = true
			var found_prereq := &""
			for prereq in data.prerequisites:
				if fs.completed_research.has(prereq) and not visited.has(prereq) and _node_data.has(prereq):
					found_prereq = prereq
					break
			if found_prereq == &"":
				break
			path.append(found_prereq)
			current = found_prereq
		path.reverse()
		return path

	func _find_shortest_path_to_completed(fs: FactionState, target_id: StringName) -> Array[StringName]:
		var queue: Array[Array] = [[target_id]]
		var visited: Dictionary = {target_id: true}
		while queue.size() > 0:
			var cur_path: Array = queue.pop_front()
			var current: StringName = cur_path[cur_path.size() - 1]
			var data: ResearchData = _node_data.get(current)
			if data == null:
				continue
			for prereq in data.prerequisites:
				if visited.has(prereq):
					continue
				visited[prereq] = true
				var new_path: Array = cur_path.duplicate()
				new_path.append(prereq)
				if fs.completed_research.has(prereq):
					new_path.reverse()
					var result: Array[StringName] = []
					for id in new_path:
						result.append(id)
					return result
				queue.append(new_path)
		return []

	func _update_hover_data() -> void:
		_hover_connected_set.clear()
		if _hovered_id == &"" or not _node_data.has(_hovered_id):
			return
		var data: ResearchData = _node_data[_hovered_id]
		for prereq in data.prerequisites:
			if _node_data.has(prereq):
				_hover_connected_set[prereq] = true
		for research_id in _node_data:
			var rd: ResearchData = _node_data[research_id]
			for prereq in rd.prerequisites:
				if prereq == _hovered_id:
					_hover_connected_set[research_id] = true
					break

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_left_pressed = true
					_left_press_pos = event.position
					_dragging = true
					_drag_start_mouse = event.position
					_drag_start_offset = _view_offset
				else:
					var was_click: bool = event.position.distance_to(_left_press_pos) < 5.0
					_dragging = false
					_left_pressed = false
					if was_click:
						var clicked := _get_node_at(event.position)
						if clicked != &"":
							_try_start_research(clicked)
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var clicked := _get_node_at(event.position)
				if clicked != &"":
					var data: ResearchData = _node_data.get(clicked)
					if data and hud_ref:
						hud_ref._show_research_detail(data)
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					_dragging = true
					_drag_start_mouse = event.position
					_drag_start_offset = _view_offset
				else:
					_dragging = false
		elif event is InputEventMouseMotion:
			if _dragging:
				_view_offset = _drag_start_offset + (event.position - _drag_start_mouse)
				queue_redraw()
			var new_hover := _get_node_at(event.position)
			if new_hover != _hovered_id:
				_hovered_id = new_hover
				_update_hover_data()
				queue_redraw()

	func _try_start_research(research_id: StringName) -> void:
		if hud_ref == null:
			return
		var fs: FactionState = GameManager.state.faction_states.get(player_faction_id)
		if fs == null:
			return
		var data: ResearchData = _node_data.get(research_id)
		if data == null:
			return
		if fs.completed_research.has(research_id):
			return
		if fs.current_research_id == research_id:
			return  # Already researching this one
		for prereq in data.prerequisites:
			if not fs.completed_research.has(prereq):
				return
		var result := GameManager.research_system.start_research(player_faction_id, research_id)
		if result and hud_ref:
			hud_ref._refresh_research_panel()
			hud_ref._update_research_status_label()

	func _get_node_at(screen_pos: Vector2) -> StringName:
		for research_id in _node_positions:
			var node_screen := _to_screen(_node_positions[research_id])
			if screen_pos.distance_to(node_screen) <= NODE_RADIUS + 5:
				return research_id
		return &""

func _show_research_detail(data: ResearchData) -> void:
	var existing := get_node_or_null("ResearchDetailDialog")
	if existing:
		existing.queue_free()
	var dialog := _create_centered_dialog(400, 340)
	dialog.name = "ResearchDetailDialog"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Header
	var header := HBoxContainer.new()
	var cat_color: Color = RESEARCH_CATEGORY_COLORS.get(data.research_category, Color(0.7, 0.7, 0.7))
	var title := _make_label(data.display_name, 16, cat_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_make_close_button(dialog.queue_free, Vector2(28, 28)))
	vbox.add_child(header)

	# Category + Tier
	var cat_label := Label.new()
	cat_label.text = "%s  |  Tier %d" % [str(data.research_category).capitalize(), data.tier]
	cat_label.add_theme_font_size_override("font_size", 11)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	vbox.add_child(cat_label)

	_add_separator(vbox)

	# Description
	var desc := Label.new()
	desc.text = data.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	# Cost + Time
	var cost_label := Label.new()
	cost_label.text = "Research Time: %d turns" % data.research_time
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.add_theme_color_override("font_color", RESOURCE_COLORS.get(2, Color.WHITE))
	vbox.add_child(cost_label)

	# Effects
	if data.effects.size() > 0:
		_add_separator(vbox)
		var eff_header := Label.new()
		eff_header.text = "Effects"
		eff_header.add_theme_font_size_override("font_size", 13)
		eff_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(eff_header)
		for key in data.effects:
			var eff := Label.new()
			eff.text = "  " + _RadialTechTree._format_effect(key, data.effects[key])
			eff.add_theme_font_size_override("font_size", 11)
			eff.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
			vbox.add_child(eff)

	# Shard bonuses
	if data.shard_bonuses.size() > 0:
		_add_separator(vbox)
		var shard_header := Label.new()
		shard_header.text = "Shard Bonuses"
		shard_header.add_theme_font_size_override("font_size", 13)
		shard_header.add_theme_color_override("font_color", Color(0.7, 0.3, 0.8))
		vbox.add_child(shard_header)
		for realm in data.shard_bonuses:
			var bonus: Dictionary = data.shard_bonuses[realm]
			var realm_name: String = REALM_NAMES[realm] if realm < REALM_NAMES.size() else "?"
			for key in bonus:
				var sb := Label.new()
				sb.text = "  %s Shard: %s" % [realm_name, _RadialTechTree._format_effect(key, bonus[key])]
				sb.add_theme_font_size_override("font_size", 11)
				sb.add_theme_color_override("font_color", Color(0.6, 0.4, 0.75))
				vbox.add_child(sb)

	# Prerequisites
	if data.prerequisites.size() > 0:
		_add_separator(vbox)
		var prereq_header := Label.new()
		prereq_header.text = "Prerequisites"
		prereq_header.add_theme_font_size_override("font_size", 13)
		prereq_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(prereq_header)
		for prereq in data.prerequisites:
			var pdata: ResearchData = DataManager.get_research(prereq)
			var pl := Label.new()
			pl.text = "  " + (pdata.display_name if pdata else str(prereq))
			pl.add_theme_font_size_override("font_size", 11)
			pl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
			vbox.add_child(pl)

	dialog.add_child(vbox)
	add_child(dialog)

func _format_research_effects(data: ResearchData, fs: FactionState) -> String:
	var parts: Array[String] = []
	for key in data.effects:
		parts.append("%s: %+d" % [key.replace("_", " "), data.effects[key]])
	var invested: Array = fs.research_invested_shards.get(data.id, [])
	for realm in invested:
		if data.shard_bonuses.has(realm):
			var bonus: Dictionary = data.shard_bonuses[realm]
			for key in bonus:
				parts.append("%s shard: %s %+d" % [REALM_NAMES[realm], key.replace("_", " "), bonus[key]])
	return ", ".join(parts) if parts.size() > 0 else "No effects"

# ── Policies Panel ───────────────────────────────────────────

func _create_policies_panel() -> void:
	_policies_panel = PanelContainer.new()
	_policies_panel.name = "PoliciesPanel"
	_policies_panel.visible = false
	_policies_panel.anchor_left = 0.15
	_policies_panel.anchor_right = 0.85
	_policies_panel.anchor_top = 0.04
	_policies_panel.anchor_bottom = 0.96
	_policies_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_policies_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_policies_panel.clip_contents = true
	_policies_panel.add_theme_stylebox_override("panel", _create_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_policies_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "PoliciesVBox"
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(_policies_panel)

const POLICY_CATEGORY_NAMES := ["Taxation", "Military", "Cultural", "Labor"]

func _toggle_policies_panel() -> void:
	if _policies_panel.visible:
		_policies_panel.visible = false
	else:
		_refresh_policies_panel()
		_policies_panel.visible = true
		_policies_panel.move_to_front()
		_policies_panel.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_property(_policies_panel, "modulate:a", 1.0, 0.2)

func _refresh_policies_panel() -> void:
	var scroll: ScrollContainer = _policies_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("PoliciesVBox")
	for child in vbox.get_children():
		child.queue_free()

	_create_panel_header(vbox, "Imperial Senate", _policies_panel)

	var player_id := GameManager.state.player_faction_id
	if player_id != &"empire":
		var msg := Label.new()
		msg.text = "Only the Empire has senate policies."
		msg.add_theme_font_size_override("font_size", 12)
		msg.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(msg)
		return

	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return

	# Senate semicircle visualization
	var seats := GameManager.policy_system.calculate_senate_seats(player_id)
	_senate_viz = _SenateVisualization.new()
	_senate_viz.custom_minimum_size = Vector2(400, 130)
	_senate_viz.update_seats(seats)
	vbox.add_child(_senate_viz)

	# Seat breakdown with percentages
	var seat_names: Array[String] = ["Nobles", "Scholars", "Artisans", "Forsaken"]
	var seat_colors: Array[Color] = [
		Color(0.85, 0.72, 0.3), Color(0.3, 0.5, 0.85),
		Color(0.6, 0.5, 0.38), Color(0.6, 0.15, 0.2),
	]
	var total_seats := 0
	for s in seats:
		total_seats += s
	var breakdown_row := HBoxContainer.new()
	breakdown_row.alignment = BoxContainer.ALIGNMENT_CENTER
	breakdown_row.add_theme_constant_override("separation", 14)
	for i in seats.size():
		if seats[i] <= 0:
			continue
		var pct := int(float(seats[i]) / float(maxi(total_seats, 1)) * 100.0)
		var entry := Label.new()
		entry.text = "%s: %d (%d%%)" % [seat_names[i], seats[i], pct]
		entry.add_theme_font_size_override("font_size", 10)
		entry.add_theme_color_override("font_color", seat_colors[i])
		breakdown_row.add_child(entry)
	vbox.add_child(breakdown_row)

	# Majority label with effects (scaled by class loyalty)
	var majority := GameManager.policy_system.get_senate_majority(player_id)
	var majority_effects := GameManager.policy_system.get_senate_majority_effects(player_id)
	var majority_scale := GameManager.policy_system._get_majority_loyalty_scale(player_id, majority)
	var majority_label := Label.new()
	var effects_text := ""
	for key in majority_effects:
		if key == "loyalty_all":
			effects_text += "All Loyalty %+d/turn  " % majority_effects[key]
		else:
			var parts := str(key).split("_")
			var res_name: String = parts[0].capitalize() if parts.size() > 0 else key
			effects_text += "%s %+d%%  " % [res_name, majority_effects[key]]
	var scale_pct := int(majority_scale * 100.0)
	majority_label.text = "Majority: %s (x%d%%) — %s" % [str(majority).capitalize(), scale_pct, effects_text.strip_edges()]
	majority_label.add_theme_font_size_override("font_size", 12)
	majority_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var majority_colors := {
		&"nobles": Color(0.85, 0.72, 0.3),
		&"scholars": Color(0.3, 0.5, 0.85),
		&"artisans": Color(0.6, 0.5, 0.38),
		&"forsaken": Color(0.6, 0.15, 0.2),
	}
	majority_label.add_theme_color_override("font_color", majority_colors.get(majority, Color(0.7, 0.7, 0.7)))
	vbox.add_child(majority_label)

	# Forsaken crisis warning
	if fs.forsaken_crisis_stage >= 1:
		var crisis_label := Label.new()
		if fs.forsaken_crisis_stage <= 2:
			crisis_label.text = "Senate PARALYZED — The Forsaken hold sway. Cannot enact/swap policies."
		elif fs.forsaken_crisis_stage >= 3:
			crisis_label.text = "FORSAKEN CRISIS — The corruption deepens..."
		crisis_label.add_theme_font_size_override("font_size", 11)
		crisis_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
		crisis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crisis_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(crisis_label)

	_add_separator(vbox)

	# Active policy count
	var count_label := Label.new()
	count_label.text = "Active Policies: %d/%d" % [fs.active_policies.size(), PolicySystem.MAX_ACTIVE_POLICIES]
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(count_label)

	# Class loyalty summary with forecast (unified with province loyalty)
	var capital := GameManager.policy_system._get_faction_capital(player_id)
	if capital:
		var deltas := LoyaltySystem.calculate_class_loyalty_deltas(capital, player_id)
		var loyalty_header := Label.new()
		loyalty_header.text = "Class Loyalty"
		loyalty_header.add_theme_font_size_override("font_size", 14)
		loyalty_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(loyalty_header)
		for cls in capital.class_loyalty:
			# Skip peasants/captives — they don't hold senate seats
			if cls == "peasants" or cls == "captives":
				continue
			var val: int = capital.class_loyalty[cls]
			var change: int = deltas.get(cls, 0)
			var cls_row := HBoxContainer.new()
			var cls_name := Label.new()
			cls_name.text = cls.capitalize()
			cls_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cls_name.add_theme_font_size_override("font_size", 11)
			cls_row.add_child(cls_name)
			var cls_val := Label.new()
			cls_val.text = str(val)
			cls_val.add_theme_font_size_override("font_size", 11)
			if val >= 30:
				cls_val.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
			elif val <= -10:
				cls_val.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
			elif val < 10:
				cls_val.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3))
			else:
				cls_val.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
			cls_row.add_child(cls_val)
			if change != 0:
				var change_label := Label.new()
				change_label.text = "  %+d/turn" % change
				change_label.add_theme_font_size_override("font_size", 10)
				change_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35) if change > 0 else Color(0.85, 0.35, 0.3))
				cls_row.add_child(change_label)
			vbox.add_child(cls_row)
		_add_separator(vbox)

	# Policies organized by category
	for cat_idx in 4:
		var cat_name: String = POLICY_CATEGORY_NAMES[cat_idx]
		var cooldown: int = fs.policy_cooldowns.get(cat_idx, 0)

		# Category header
		var cat_header := HBoxContainer.new()
		var cat_title := Label.new()
		cat_title.text = cat_name
		cat_title.add_theme_font_size_override("font_size", 13)
		cat_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		cat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_header.add_child(cat_title)
		if cooldown > 0:
			var cd_label := Label.new()
			cd_label.text = "Cooldown: %d turns" % cooldown
			cd_label.add_theme_font_size_override("font_size", 10)
			cd_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.3))
			cat_header.add_child(cd_label)
		vbox.add_child(cat_header)

		# Find active policy in this category
		var active_in_cat: StringName = GameManager.policy_system._get_active_policy_in_category(fs, cat_idx)
		if active_in_cat != &"":
			var data: PolicyData = DataManager.get_policy(active_in_cat)
			if data:
				var row := HBoxContainer.new()
				var info := VBoxContainer.new()
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var p_name := Label.new()
				p_name.text = data.display_name + " [ACTIVE]"
				p_name.add_theme_font_size_override("font_size", 12)
				p_name.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
				info.add_child(p_name)
				var p_desc := Label.new()
				p_desc.text = _format_policy_effects(data)
				p_desc.add_theme_font_size_override("font_size", 10)
				p_desc.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
				info.add_child(p_desc)
				row.add_child(info)
				var revoke_btn := Button.new()
				revoke_btn.text = "Revoke"
				revoke_btn.custom_minimum_size = Vector2(60, 24)
				var pid: StringName = active_in_cat
				revoke_btn.pressed.connect(func():
					GameManager.policy_system.revoke_policy(player_id, pid)
					_refresh_policies_panel())
				row.add_child(revoke_btn)
				vbox.add_child(row)

		# Available policies in this category
		for policy_id in DataManager.policies:
			var data: PolicyData = DataManager.policies[policy_id]
			if data.category != cat_idx:
				continue
			if data.faction_id != &"" and data.faction_id != fs.faction_data_id:
				continue
			if fs.active_policies.has(policy_id):
				continue

			var row := HBoxContainer.new()
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var p_name := Label.new()
			p_name.text = data.display_name
			p_name.add_theme_font_size_override("font_size", 12)
			info.add_child(p_name)

			var p_desc := Label.new()
			p_desc.text = _format_policy_effects(data)
			p_desc.add_theme_font_size_override("font_size", 10)
			p_desc.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
			info.add_child(p_desc)

			var can_enact := GameManager.policy_system.can_enact_policy(player_id, policy_id)
			if not can_enact:
				p_name.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
				if cooldown > 0:
					var reason := Label.new()
					reason.text = "Category on cooldown"
					reason.add_theme_font_size_override("font_size", 10)
					reason.add_theme_color_override("font_color", Color(0.85, 0.55, 0.3))
					info.add_child(reason)
				elif fs.active_policies.size() >= PolicySystem.MAX_ACTIVE_POLICIES and active_in_cat == &"":
					var reason := Label.new()
					reason.text = "Max policies reached (%d/%d)" % [fs.active_policies.size(), PolicySystem.MAX_ACTIVE_POLICIES]
					reason.add_theme_font_size_override("font_size", 10)
					reason.add_theme_color_override("font_color", Color(0.85, 0.55, 0.3))
					info.add_child(reason)
				elif capital:
					for cls in data.required_class_loyalty:
						var required: int = data.required_class_loyalty[cls]
						var current: int = capital.class_loyalty.get(cls, 0)
						if current < required:
							var reason := Label.new()
							reason.text = "Requires %s loyalty >= %d (current: %d)" % [cls.capitalize(), required, current]
							reason.add_theme_font_size_override("font_size", 10)
							reason.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
							info.add_child(reason)

			row.add_child(info)
			var enact_btn := Button.new()
			enact_btn.text = "Enact" if active_in_cat == &"" else "Swap"
			enact_btn.custom_minimum_size = Vector2(55, 24)
			enact_btn.disabled = not can_enact
			var pid: StringName = policy_id
			enact_btn.pressed.connect(func():
				GameManager.policy_system.enact_policy(player_id, pid)
				_refresh_policies_panel())
			row.add_child(enact_btn)
			vbox.add_child(row)

		_add_separator(vbox)

func _format_policy_effects(data: PolicyData) -> String:
	var parts: Array[String] = []
	for cls in data.class_loyalty_effects:
		parts.append("%s %+d" % [cls.capitalize(), data.class_loyalty_effects[cls]])
	for res_type in data.resource_effects:
		var res_name: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
		parts.append("%s %+d/turn" % [res_name, data.resource_effects[res_type]])
	return ", ".join(parts) if parts.size() > 0 else data.description

# ── Senate Visualization (semicircle of colored dots) ─────────

class _SenateVisualization extends Control:
	const SEAT_COLORS := [
		Color(0.85, 0.72, 0.3),   # 0 = nobles (gold)
		Color(0.3, 0.5, 0.85),    # 1 = scholars (blue)
		Color(0.6, 0.5, 0.38),    # 2 = artisans (gray-brown)
		Color(0.6, 0.15, 0.2),    # 3 = forsaken (dark red)
	]

	var seats: Array[int] = []  # faction index per seat

	func update_seats(seat_counts: Array[int]) -> void:
		seats.clear()
		for faction_idx in seat_counts.size():
			for _s in seat_counts[faction_idx]:
				seats.append(faction_idx)
		queue_redraw()

	func _draw() -> void:
		var total := seats.size()
		if total == 0:
			return
		var center := Vector2(size.x / 2.0, size.y - 8.0)
		var dot_radius := 3.0

		# Distribute across rows: inner rows hold fewer seats, outer rows more
		var row_counts: Array[int] = []
		var remaining := total
		var rows := 4 if total > 60 else 3
		# Distribute proportionally: inner rows smaller
		for row in rows:
			var fraction := float(row + 1) / float((rows * (rows + 1)) / 2)
			var count := roundi(fraction * total)
			row_counts.append(count)
			remaining -= count
		# Fix rounding error on last row
		row_counts[rows - 1] += remaining

		var placed := 0
		for row in rows:
			# Each row radius: space them so dots don't overlap
			var arc_radius := 30.0 + row * (dot_radius * 2.0 + 5.0)
			var this_row := row_counts[row]
			if this_row <= 0:
				continue
			# Calculate spacing: arc length / seats must be >= dot diameter + gap
			var arc_length := PI * arc_radius
			var needed_spacing := dot_radius * 2.0 + 2.0
			var max_seats_this_row := int(arc_length / needed_spacing)
			this_row = mini(this_row, max_seats_this_row)
			# Add margin at edges so dots don't sit right at 0/180 degrees
			var margin := 0.06
			for i in this_row:
				if placed >= total:
					break
				var t := float(i) / float(maxi(this_row - 1, 1))
				var angle := PI + margin + t * (PI - 2.0 * margin)
				var pos := center + Vector2(cos(angle), sin(angle)) * arc_radius
				var color: Color = SEAT_COLORS[seats[placed]] if seats[placed] < SEAT_COLORS.size() else Color.WHITE
				draw_circle(pos, dot_radius, color)
				placed += 1
		# Draw any leftover seats on outermost ring
		if placed < total:
			var extra_radius := 30.0 + rows * (dot_radius * 2.0 + 5.0)
			var leftover := total - placed
			for i in leftover:
				var t := float(i) / float(maxi(leftover - 1, 1))
				var angle := PI + 0.06 + t * (PI - 0.12)
				var pos := center + Vector2(cos(angle), sin(angle)) * extra_radius
				var color: Color = SEAT_COLORS[seats[placed]] if seats[placed] < SEAT_COLORS.size() else Color.WHITE
				draw_circle(pos, dot_radius, color)
				placed += 1

# ── Forsaken Offer Dialog ─────────────────────────────────────

func _on_forsaken_offer_received(faction_id: StringName, offer: Dictionary) -> void:
	if faction_id != GameManager.state.player_faction_id:
		return
	if offer.has("type") and offer.type == "crisis_dilemma":
		_show_forsaken_crisis_dialog()
		return
	_pending_forsaken_offer = offer
	_show_forsaken_offer_dialog(offer)

func _show_forsaken_offer_dialog(offer: Dictionary) -> void:
	if _forsaken_offer_dialog != null:
		_forsaken_offer_dialog.queue_free()

	_forsaken_offer_dialog = PanelContainer.new()
	_forsaken_offer_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_forsaken_offer_dialog.offset_left = -180.0
	_forsaken_offer_dialog.offset_right = 180.0
	_forsaken_offer_dialog.offset_top = -120.0
	_forsaken_offer_dialog.offset_bottom = 120.0

	_forsaken_offer_dialog.add_theme_stylebox_override("panel", GameManager.make_notification_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_forsaken_offer_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "The Forsaken"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.6, 0.15, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var flavor := Label.new()
	flavor.text = offer.get("flavor_text", "A dark bargain is offered...")
	flavor.add_theme_font_size_override("font_size", 11)
	flavor.add_theme_color_override("font_color", Color(0.65, 0.55, 0.5))
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(flavor)

	var details := Label.new()
	details.text = "Offer: +%d %s\nCost: %d Senate seats to The Forsaken" % [
		offer.get("amount", 0), offer.get("resource_name", "Resources"), offer.get("seats_requested", 0)]
	details.add_theme_font_size_override("font_size", 12)
	details.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(details)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(90, 30)
	accept_btn.pressed.connect(func():
		GameManager.policy_system.accept_forsaken_offer(GameManager.state.player_faction_id, _pending_forsaken_offer)
		_forsaken_offer_dialog.queue_free()
		_forsaken_offer_dialog = null
		if _policies_panel.visible:
			_refresh_policies_panel())
	btn_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(90, 30)
	decline_btn.pressed.connect(func():
		GameManager.policy_system.decline_forsaken_offer(GameManager.state.player_faction_id)
		_forsaken_offer_dialog.queue_free()
		_forsaken_offer_dialog = null)
	btn_row.add_child(decline_btn)

	add_child(_forsaken_offer_dialog)

func _show_forsaken_crisis_dialog() -> void:
	if _forsaken_offer_dialog != null:
		_forsaken_offer_dialog.queue_free()

	_forsaken_offer_dialog = PanelContainer.new()
	_forsaken_offer_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_forsaken_offer_dialog.offset_left = -200.0
	_forsaken_offer_dialog.offset_right = 200.0
	_forsaken_offer_dialog.offset_top = -130.0
	_forsaken_offer_dialog.offset_bottom = 130.0

	_forsaken_offer_dialog.add_theme_stylebox_override("panel", GameManager.make_notification_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_forsaken_offer_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "The Forsaken Demand"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.8, 0.15, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "The Forsaken have seized control of the Senate. They demand submission or face purging."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.7, 0.55, 0.5))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var player_id := GameManager.state.player_faction_id
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var purge_btn := Button.new()
	purge_btn.text = "Purge Senate"
	purge_btn.tooltip_text = "Remove half Forsaken seats. Nobles/Scholars loyalty -15, costs 200 Gold."
	purge_btn.custom_minimum_size = Vector2(120, 30)
	purge_btn.pressed.connect(func():
		GameManager.policy_system.purge_forsaken_senate(player_id)
		_forsaken_offer_dialog.queue_free()
		_forsaken_offer_dialog = null
		if _policies_panel.visible:
			_refresh_policies_panel())
	btn_row.add_child(purge_btn)

	var submit_btn := Button.new()
	submit_btn.text = "Submit"
	submit_btn.tooltip_text = "Forsaken keep majority +3 seats. All income -20% for 5 turns."
	submit_btn.custom_minimum_size = Vector2(120, 30)
	submit_btn.pressed.connect(func():
		GameManager.policy_system.submit_to_forsaken(player_id)
		_forsaken_offer_dialog.queue_free()
		_forsaken_offer_dialog = null
		if _policies_panel.visible:
			_refresh_policies_panel())
	btn_row.add_child(submit_btn)

	add_child(_forsaken_offer_dialog)

# ── Senate Dilemma Dialog ─────────────────────────────────────

func _emit_senate_dilemma(faction_id: StringName, dilemma: Dictionary) -> void:
	EventBus.senate_dilemma.emit(faction_id, dilemma)

func _on_senate_dilemma_received(faction_id: StringName, dilemma: Dictionary) -> void:
	if faction_id != GameManager.state.player_faction_id:
		return
	_show_senate_dilemma_dialog(faction_id, dilemma)

func _show_senate_dilemma_dialog(faction_id: StringName, dilemma: Dictionary) -> void:
	if _senate_dilemma_dialog != null:
		_senate_dilemma_dialog.queue_free()

	_senate_dilemma_dialog = PanelContainer.new()
	_senate_dilemma_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_senate_dilemma_dialog.offset_left = -200.0
	_senate_dilemma_dialog.offset_right = 200.0
	_senate_dilemma_dialog.offset_top = -140.0
	_senate_dilemma_dialog.offset_bottom = 140.0

	# Class-themed background color
	var majority: StringName = dilemma.get("majority", &"nobles")
	var bg_color: Color
	var border_color: Color
	match majority:
		&"nobles":
			bg_color = Color(0.12, 0.1, 0.05, 0.97)
			border_color = Color(0.85, 0.72, 0.3)
		&"scholars":
			bg_color = Color(0.05, 0.07, 0.12, 0.97)
			border_color = Color(0.3, 0.5, 0.85)
		&"artisans":
			bg_color = Color(0.1, 0.08, 0.05, 0.97)
			border_color = Color(0.6, 0.5, 0.38)
		_:
			bg_color = Color(0.08, 0.08, 0.08, 0.97)
			border_color = Color(0.5, 0.5, 0.5)

	_senate_dilemma_dialog.add_theme_stylebox_override("panel", GameManager.make_notification_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_senate_dilemma_dialog.add_child(vbox)

	var title := Label.new()
	title.text = dilemma.get("title", "Senate Dilemma")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", border_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = dilemma.get("text", "")
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var choice_a: Dictionary = dilemma.get("choice_a", {})
	var choice_b: Dictionary = dilemma.get("choice_b", {})

	var btn_a := Button.new()
	btn_a.text = choice_a.get("label", "Choice A")
	btn_a.tooltip_text = choice_a.get("tooltip", "")
	btn_a.custom_minimum_size = Vector2(150, 30)
	btn_a.pressed.connect(func():
		GameManager.policy_system.apply_senate_dilemma_choice(faction_id, dilemma, "a")
		_senate_dilemma_dialog.queue_free()
		_senate_dilemma_dialog = null
		_update_resource_display())
	btn_row.add_child(btn_a)

	var btn_b := Button.new()
	btn_b.text = choice_b.get("label", "Choice B")
	btn_b.tooltip_text = choice_b.get("tooltip", "")
	btn_b.custom_minimum_size = Vector2(150, 30)
	btn_b.pressed.connect(func():
		GameManager.policy_system.apply_senate_dilemma_choice(faction_id, dilemma, "b")
		_senate_dilemma_dialog.queue_free()
		_senate_dilemma_dialog = null
		_update_resource_display())
	btn_row.add_child(btn_b)

	add_child(_senate_dilemma_dialog)

# ── City management panel ────────────────────────────────────

func _create_city_panel() -> void:
	city_panel = PanelContainer.new()
	city_panel.name = "CityPanel"
	city_panel.visible = false

	# Position: right side of screen, nearly full height
	city_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	city_panel.anchor_left = 1.0
	city_panel.anchor_right = 1.0
	city_panel.anchor_top = 0.02
	city_panel.anchor_bottom = 0.88
	city_panel.offset_left = -380.0
	city_panel.offset_right = -10.0
	city_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	city_panel.custom_minimum_size = Vector2(360, 0)

	city_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	city_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "CityVBox"
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(city_panel)

	# Building tooltip (floats above city panel)
	_building_tooltip = PanelContainer.new()
	_building_tooltip.visible = false
	_building_tooltip.custom_minimum_size = Vector2(240, 0)
	_building_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var btt_style := StyleBoxFlat.new()
	btt_style.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	btt_style.border_width_left = 1
	btt_style.border_width_top = 1
	btt_style.border_width_right = 1
	btt_style.border_width_bottom = 1
	btt_style.border_color = Color(0.55, 0.42, 0.2, 0.7)
	btt_style.corner_radius_top_left = 4
	btt_style.corner_radius_top_right = 4
	btt_style.corner_radius_bottom_right = 4
	btt_style.corner_radius_bottom_left = 4
	btt_style.content_margin_left = 8.0
	btt_style.content_margin_top = 6.0
	btt_style.content_margin_right = 8.0
	btt_style.content_margin_bottom = 6.0
	_building_tooltip.add_theme_stylebox_override("panel", btt_style)
	var btt_label := Label.new()
	btt_label.name = "TooltipText"
	btt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btt_label.custom_minimum_size = Vector2(220, 0)
	btt_label.add_theme_font_size_override("font_size", 11)
	btt_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	_building_tooltip.add_child(btt_label)
	_building_tooltip.z_index = 10
	add_child(_building_tooltip)

func _show_city_panel(city_id: StringName) -> void:
	_check_tutorial("city_viewed")
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	var is_player_city := city.faction_id == GameManager.state.player_faction_id
	# Only animate fade-in if the panel wasn't already visible (skip on refresh)
	var was_visible := city_panel.visible
	city_panel.visible = true
	city_panel.move_to_front()
	if not was_visible:
		city_panel.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_property(city_panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)

	var scroll: ScrollContainer = city_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("CityVBox")

	# Clear previous content
	for child in vbox.get_children():
		child.queue_free()

	# Header row with title and close button
	_create_panel_header(vbox, city.get_display_name(), city_panel, _on_city_panel_close)

	# Show faction owner for foreign cities
	if not is_player_city:
		var faction := DataManager.get_faction(city.faction_id)
		var owner_label := Label.new()
		owner_label.text = "Owner: " + (faction.display_name if faction else str(city.faction_id))
		owner_label.add_theme_font_size_override("font_size", 13)
		owner_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
		vbox.add_child(owner_label)

	_add_separator(vbox)

	# City info: Level, Population, Loyalty
	var province_pop := LoyaltySystem.get_province_population(city.region_id, city.faction_id)
	var growth_per_turn := GameManager.city_system.calculate_growth(city)
	var threshold := city.get_growth_threshold()
	var loyalty_delta := LoyaltySystem.calculate_loyalty_delta(city, city.faction_id)

	# Level + Population line
	var info_hbox := HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 0)

	var pop_cap := city.get_population_cap()
	var pop_text := ""
	if city.upgrade_turns_remaining > 0:
		pop_text = "Level %d  |  Pop: %d/%d  (Upgrading: %d turns)" % [city.level, province_pop, pop_cap, city.upgrade_turns_remaining]
	elif threshold > 0:
		if province_pop >= threshold:
			pop_text = "Level %d  |  Pop: %d/%d +%d  (Ready)" % [city.level, province_pop, pop_cap, growth_per_turn]
		else:
			pop_text = "Level %d  |  Pop: %d/%d +%d" % [city.level, province_pop, pop_cap, growth_per_turn]
	else:
		pop_text = "Level %d  |  Pop: %d/%d (MAX)" % [city.level, province_pop, pop_cap]

	var pop_label := Label.new()
	pop_label.text = pop_text + "  "
	pop_label.add_theme_font_size_override("font_size", 13)
	pop_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	info_hbox.add_child(pop_label)

	# Loyalty button (clickable, color-coded border, "Loyalty:" white, numbers colored)
	var loyalty_color := LoyaltySystem.get_loyalty_color(city.loyalty)
	var delta_sign := "+" if loyalty_delta >= 0 else ""
	var loyalty_container := PanelContainer.new()
	var lbtn_style := StyleBoxFlat.new()
	lbtn_style.bg_color = Color(0.08, 0.07, 0.1, 0.8)
	lbtn_style.border_width_left = 1
	lbtn_style.border_width_top = 1
	lbtn_style.border_width_right = 1
	lbtn_style.border_width_bottom = 1
	lbtn_style.border_color = loyalty_color * Color(1, 1, 1, 0.6)
	lbtn_style.corner_radius_top_left = 3
	lbtn_style.corner_radius_top_right = 3
	lbtn_style.corner_radius_bottom_right = 3
	lbtn_style.corner_radius_bottom_left = 3
	lbtn_style.content_margin_left = 6.0
	lbtn_style.content_margin_right = 6.0
	lbtn_style.content_margin_top = 2.0
	lbtn_style.content_margin_bottom = 2.0
	loyalty_container.add_theme_stylebox_override("panel", lbtn_style)
	loyalty_container.mouse_filter = Control.MOUSE_FILTER_STOP
	loyalty_container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	loyalty_container.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_loyalty_panel(city_id)
	)
	var loyalty_hbox := HBoxContainer.new()
	loyalty_hbox.add_theme_constant_override("separation", 0)
	loyalty_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var loyalty_word := Label.new()
	loyalty_word.text = "Loyalty: "
	loyalty_word.add_theme_font_size_override("font_size", 12)
	loyalty_word.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	loyalty_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loyalty_hbox.add_child(loyalty_word)
	var loyalty_nums := Label.new()
	loyalty_nums.text = "%d %s%d" % [city.loyalty, delta_sign, loyalty_delta]
	loyalty_nums.add_theme_font_size_override("font_size", 12)
	loyalty_nums.add_theme_color_override("font_color", loyalty_color)
	loyalty_nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loyalty_hbox.add_child(loyalty_nums)
	loyalty_container.add_child(loyalty_hbox)
	info_hbox.add_child(loyalty_container)

	vbox.add_child(info_hbox)

	# Upgrade button (player cities only, visible as soon as pop requirement is met)
	# Show when: not max level, not already upgrading
	var upgrade_threshold := city.get_growth_threshold()
	var has_next_level := upgrade_threshold >= 0
	var is_upgrading := city.upgrade_turns_remaining > 0
	if is_player_city and has_next_level and not is_upgrading:
		var pop_met := province_pop >= upgrade_threshold
		var can_afford := pop_met and GameManager.city_system.can_start_upgrade(city)
		var upgrade_cost := city.get_upgrade_cost()
		var upgrade_time := city.get_upgrade_time()
		var fs_upgrade: FactionState = GameManager.state.faction_states.get(city.faction_id)

		var upgrade_btn := Button.new()
		upgrade_btn.text = "Upgrade to Level %d  (%d turns)" % [city.level + 1, upgrade_time]
		upgrade_btn.add_theme_font_size_override("font_size", 12)
		upgrade_btn.disabled = not can_afford
		if can_afford:
			upgrade_btn.add_theme_color_override("font_color", Color(0.5, 0.9, 0.45))
		else:
			upgrade_btn.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
		upgrade_btn.pressed.connect(func() -> void:
			if GameManager.city_system.start_upgrade(city_id):
				_show_city_panel(city_id)
				_update_resource_display()
		)
		vbox.add_child(upgrade_btn)

		# Population requirement (shown in red if not met)
		if not pop_met:
			var pop_req_label := Label.new()
			pop_req_label.text = "Population: %d / %d required" % [province_pop, upgrade_threshold]
			pop_req_label.add_theme_font_size_override("font_size", 11)
			pop_req_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
			vbox.add_child(pop_req_label)

		# Cost breakdown — red for missing resources, green for sufficient
		var cost_hbox := HBoxContainer.new()
		cost_hbox.add_theme_constant_override("separation", 8)
		var cost_prefix := Label.new()
		cost_prefix.text = "Cost: "
		cost_prefix.add_theme_font_size_override("font_size", 11)
		cost_prefix.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
		cost_hbox.add_child(cost_prefix)
		for res_type in upgrade_cost:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			var amount: int = upgrade_cost[res_type]
			var have: int = fs_upgrade.resources.get(res_type, 0) if fs_upgrade else 0
			var cost_label := Label.new()
			cost_label.text = "%d %s" % [amount, rname]
			cost_label.add_theme_font_size_override("font_size", 11)
			if have >= amount:
				cost_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
			else:
				cost_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
			cost_hbox.add_child(cost_label)
		vbox.add_child(cost_hbox)

	# Income preview (player cities only)
	if is_player_city:
		var income := GameManager.city_system.calculate_city_income(city)
		if income.size() > 0:
			var income_parts: Array[String] = []
			for res_type in income:
				if income[res_type] > 0:
					var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
					income_parts.append("+" + str(income[res_type]) + " " + rname)
			if income_parts.size() > 0:
				var income_label := Label.new()
				income_label.text = "Income: " + ", ".join(income_parts)
				income_label.add_theme_font_size_override("font_size", 12)
				income_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
				vbox.add_child(income_label)

	# Garrison info
	var garrison_def: Array = GameManager.city_system._get_garrison_composition(city)
	var garrison_parts: Array[String] = []
	for entry in garrison_def:
		var ud := DataManager.get_unit(entry.unit_id)
		if ud:
			garrison_parts.append("%dx %s" % [entry.count, ud.display_name])
	if garrison_parts.size() > 0:
		var garrison_label := Label.new()
		garrison_label.text = "Garrison: " + ", ".join(garrison_parts)
		garrison_label.add_theme_font_size_override("font_size", 12)
		garrison_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5))
		vbox.add_child(garrison_label)

	# Settlement founding button (only for player capitals that can found)
	if is_player_city and city.is_capital and city.can_found_settlement:
		var found_cost_text := _format_cost(CitySystem.SETTLEMENT_FOUNDING_COST)
		var can_afford_found := GameManager.can_afford_settlement(GameManager.state.player_faction_id)
		var found_btn := Button.new()
		found_btn.text = "Found Settlement  (%s)" % found_cost_text
		found_btn.custom_minimum_size = Vector2(280, 32)
		found_btn.add_theme_font_size_override("font_size", 12)
		found_btn.disabled = not can_afford_found
		if can_afford_found:
			found_btn.add_theme_color_override("font_color", Color(0.5, 0.9, 0.45))
		else:
			found_btn.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
		found_btn.pressed.connect(_on_found_settlement_pressed.bind(city_id))
		vbox.add_child(found_btn)

	# Siege status
	if city.is_under_siege:
		var siege_label := Label.new()
		var attacker := DataManager.get_faction(city.siege_faction)
		var aname := attacker.display_name if attacker else str(city.siege_faction)
		var siege_threshold := 5 if city.buildings.has(&"steppe_watchtower") else 4
		var turns_remaining := maxi(0, siege_threshold - city.siege_turns)
		siege_label.text = "UNDER SIEGE by %s (Turn %d/%d - %d remaining)" % [aname, city.siege_turns, siege_threshold, turns_remaining]
		siege_label.add_theme_font_size_override("font_size", 13)
		siege_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
		vbox.add_child(siege_label)

	_add_separator(vbox)

	# Buildings section
	var buildings_header := Label.new()
	buildings_header.text = "Buildings (%d / %d slots)" % [city.buildings.size(), city.get_max_building_slots()]
	buildings_header.add_theme_font_size_override("font_size", 14)
	buildings_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(buildings_header)

	# Existing buildings (click to open detail)
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building:
			var blabel := Label.new()
			blabel.text = "  " + building.display_name
			blabel.add_theme_font_size_override("font_size", 12)
			blabel.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
			blabel.mouse_filter = Control.MOUSE_FILTER_STOP
			blabel.mouse_entered.connect(_on_building_hover.bind(building_id))
			blabel.mouse_exited.connect(_on_building_hover_exit)
			blabel.gui_input.connect(_on_building_label_clicked.bind(building_id, city_id))
			vbox.add_child(blabel)

	# Build queue
	for item in city.build_queue:
		var building: BuildingData = DataManager.get_building(item.building_id)
		var bname := building.display_name if building else str(item.building_id)
		var qlabel := Label.new()
		qlabel.text = "  [Building] " + bname + " (%d turns)" % item.turns_remaining
		qlabel.add_theme_font_size_override("font_size", 12)
		qlabel.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		vbox.add_child(qlabel)

	# Available buildings to construct (player only)
	var available_buildings := GameManager.city_system.get_available_buildings(city, true)
	var has_free_slots := city.get_available_building_slots() > 0
	if is_player_city and available_buildings.size() > 0 and city.build_queue.is_empty():
		_add_separator(vbox)
		var build_header := Label.new()
		build_header.text = "Available Buildings"
		build_header.add_theme_font_size_override("font_size", 13)
		build_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(build_header)

		# Show warning when no building slots available
		if not has_free_slots:
			var no_slots_label := Label.new()
			no_slots_label.text = "No available building slots!"
			no_slots_label.add_theme_font_size_override("font_size", 12)
			no_slots_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
			vbox.add_child(no_slots_label)

		var build_grid := GridContainer.new()
		build_grid.columns = 2
		build_grid.add_theme_constant_override("h_separation", 6)
		build_grid.add_theme_constant_override("v_separation", 6)
		vbox.add_child(build_grid)

		var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
		for building in available_buildings:
			var is_slot_blocked := not has_free_slots and building.upgrades_from == &""
			var card := _create_building_card(building, city_id, fs, is_slot_blocked)
			build_grid.add_child(card)

	# Recruitment section (player only)
	if is_player_city:
		_add_separator(vbox)

		var recruit_header := Label.new()
		recruit_header.text = "Recruitment"
		recruit_header.add_theme_font_size_override("font_size", 14)
		recruit_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(recruit_header)

		# Available units to recruit (shown first, always in same position)
		var recruitable := _get_recruitable_units(city)
		if recruitable.size() > 0:
			for unit_data_id in recruitable:
				var unit_data := DataManager.get_unit(unit_data_id)
				if unit_data == null:
					continue

				var btn_row := HBoxContainer.new()
				btn_row.add_theme_constant_override("separation", 6)

				var recruit_btn := Button.new()
				recruit_btn.text = unit_data.display_name
				recruit_btn.custom_minimum_size = Vector2(140, 28)
				recruit_btn.pressed.connect(_on_recruit_pressed.bind(city_id, unit_data_id))
				recruit_btn.mouse_entered.connect(_show_unit_card.bind(unit_data_id))
				recruit_btn.mouse_exited.connect(_hide_unit_card)
				var captured_ud_id := unit_data_id
				var captured_ud := unit_data
				recruit_btn.gui_input.connect(func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
						var dummy_unit := UnitInstance.new()
						dummy_unit.unit_data_id = captured_ud_id
						dummy_unit.current_hp = captured_ud.max_hp
						_show_unit_detail(dummy_unit, captured_ud)
				)

				var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
				var can_afford := fs != null and _can_afford_display(fs, unit_data.recruit_cost)
				var unit_pop_cost: int = unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
				var has_pop := province_pop >= unit_pop_cost
				if not can_afford or not has_pop:
					recruit_btn.disabled = true

				btn_row.add_child(recruit_btn)

				var cost_parts: Array[String] = []
				if unit_data.recruit_cost.size() > 0:
					cost_parts.append(_format_cost(unit_data.recruit_cost))
				cost_parts.append("Pop: " + str(unit_pop_cost))
				var cost_label := Label.new()
				cost_label.text = ", ".join(cost_parts) + " | " + str(unit_data.recruit_time) + " turn(s)"
				cost_label.add_theme_font_size_override("font_size", 11)
				cost_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
				btn_row.add_child(cost_label)

				vbox.add_child(btn_row)
		elif recruitable.is_empty():
			var no_units := Label.new()
			no_units.text = "  No units available (need Barracks)"
			no_units.add_theme_font_size_override("font_size", 12)
			no_units.add_theme_color_override("font_color", Color(0.55, 0.5, 0.45))
			vbox.add_child(no_units)

		# Training queue (shown below recruit buttons)
		var has_any_queue := city.recruit_queue.size() > 0
		if not has_any_queue:
			for _bq_key in city.building_recruit_queues:
				var bq: Array = city.building_recruit_queues[_bq_key]
				if bq.size() > 0:
					has_any_queue = true
					break
		if has_any_queue:
			_add_separator(vbox)
			var queue_header := Label.new()
			queue_header.text = "Training Queue (right-click to cancel)"
			queue_header.add_theme_font_size_override("font_size", 13)
			queue_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(queue_header)
			# Basic/levy queue
			for qi in city.recruit_queue.size():
				var item: Dictionary = city.recruit_queue[qi]
				var unit_data := DataManager.get_unit(item.unit_data_id)
				var uname := unit_data.display_name if unit_data else str(item.unit_data_id)
				var qlabel := Label.new()
				qlabel.text = "  [Training] " + uname + " (%d turns)" % item.turns_remaining
				qlabel.add_theme_font_size_override("font_size", 12)
				qlabel.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
				qlabel.mouse_filter = Control.MOUSE_FILTER_STOP
				qlabel.tooltip_text = "Right-click to cancel (80% refund)"
				var cap_city_id := city_id
				var cap_qi := qi
				qlabel.gui_input.connect(func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
						if GameManager.city_system.cancel_recruitment(cap_city_id, "basic", cap_qi):
							AudioManager.play_sfx(&"error_buzz")
							_show_city_panel(cap_city_id)
							_update_resource_display()
				)
				vbox.add_child(qlabel)
			# Per-building queues
			for bq_building_id in city.building_recruit_queues:
				var bq: Array = city.building_recruit_queues[bq_building_id]
				if bq.is_empty():
					continue
				var bd: BuildingData = DataManager.get_building(bq_building_id)
				var bname: String = bd.display_name if bd else str(bq_building_id)
				for bqi in bq.size():
					var item: Dictionary = bq[bqi]
					var unit_data := DataManager.get_unit(item.unit_data_id)
					var uname := unit_data.display_name if unit_data else str(item.unit_data_id)
					var qlabel := Label.new()
					qlabel.text = "  [%s] %s (%d turns)" % [bname, uname, item.turns_remaining]
					qlabel.add_theme_font_size_override("font_size", 12)
					qlabel.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
					qlabel.mouse_filter = Control.MOUSE_FILTER_STOP
					qlabel.tooltip_text = "Right-click to cancel (80% refund)"
					var cap_city_id := city_id
					var cap_bqi := bqi
					var cap_bid: StringName = bq_building_id
					qlabel.gui_input.connect(func(event: InputEvent):
						if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
							if GameManager.city_system.cancel_recruitment(cap_city_id, "building", cap_bqi, cap_bid):
								AudioManager.play_sfx(&"error_buzz")
								_show_city_panel(cap_city_id)
								_update_resource_display()
					)
					vbox.add_child(qlabel)

func _hide_city_panel() -> void:
	if city_panel:
		city_panel.visible = false
	_on_loyalty_panel_close()

func _on_city_panel_close() -> void:
	if _building_tooltip:
		_building_tooltip.visible = false
	_on_loyalty_panel_close()
	var campaign: Node2D = get_parent().get_parent()
	if campaign and campaign.has_method("_close_city_panel"):
		campaign._close_city_panel()

func _show_loyalty_panel(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	_loyalty_panel_city_id = city_id

	# Remove old panel if exists
	if _loyalty_panel:
		_loyalty_panel.queue_free()
		_loyalty_panel = null

	_loyalty_panel = PanelContainer.new()
	_loyalty_panel.set_anchors_preset(Control.PRESET_CENTER)
	_loyalty_panel.custom_minimum_size = Vector2(340, 0)
	_loyalty_panel.offset_left = -170.0
	_loyalty_panel.offset_right = 170.0
	_loyalty_panel.offset_top = -200.0
	_loyalty_panel.offset_bottom = 200.0

	_loyalty_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(320, 0)
	_loyalty_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var faction_id := city.faction_id
	var loyalty_mult := LoyaltySystem.get_loyalty_multiplier(city.loyalty)
	var status_text := LoyaltySystem.get_loyalty_status(city.loyalty)
	var loyalty_color := LoyaltySystem.get_loyalty_color(city.loyalty)

	# Header row with close button
	_create_panel_header(vbox, "Province Loyalty: %d  (%s)" % [city.loyalty, status_text], _loyalty_panel, _on_loyalty_panel_close, 14, loyalty_color)

	# CLASS LOYALTY section
	var class_header := Label.new()
	class_header.text = "CLASS LOYALTY"
	class_header.add_theme_font_size_override("font_size", 13)
	class_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(class_header)

	var pcts := LoyaltySystem.calculate_class_percentages(city, faction_id)
	var deltas := LoyaltySystem.calculate_class_loyalty_deltas(city, faction_id)
	var pct_deltas := LoyaltySystem.calculate_class_pct_deltas(city, faction_id)

	var class_entries := [
		{key = "peasants", name = "Peasants", color = Color(0.5, 0.8, 0.35)},
		{key = "artisans", name = "Artisans", color = Color(0.6, 0.6, 0.65)},
		{key = "scholars", name = "Scholars", color = Color(0.45, 0.55, 0.65)},
		{key = "nobles", name = "Nobles", color = Color(0.95, 0.85, 0.3)},
		{key = "captives", name = "Captives", color = Color(0.65, 0.45, 0.35)},
	]

	for entry in class_entries:
		var cls_key: String = entry.key
		var cls_loyalty: int = city.class_loyalty.get(cls_key, 0)
		var cls_pct := int(float(pcts.get(cls_key, 0.0)) * 100.0)
		var cls_delta: int = deltas.get(cls_key, 0)

		# Class name
		var name_label := Label.new()
		name_label.text = "  %s" % entry.name
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", entry.color)
		vbox.add_child(name_label)

		# Population percentage with projected % change
		var pct_hbox := HBoxContainer.new()
		pct_hbox.add_theme_constant_override("separation", 0)
		var pct_label := Label.new()
		pct_label.text = "    %d%% of Population " % cls_pct
		pct_label.add_theme_font_size_override("font_size", 11)
		pct_label.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		pct_hbox.add_child(pct_label)
		var pct_delta: float = pct_deltas.get(cls_key, 0.0)
		if abs(pct_delta) >= 0.5:
			var pct_delta_int := int(pct_delta)
			var open_bracket := Label.new()
			open_bracket.text = "("
			open_bracket.add_theme_font_size_override("font_size", 11)
			open_bracket.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			pct_hbox.add_child(open_bracket)
			var pct_num := Label.new()
			pct_num.text = "%s%d%%" % ["+" if pct_delta_int >= 0 else "", pct_delta_int]
			pct_num.add_theme_font_size_override("font_size", 11)
			if pct_delta_int > 0:
				pct_num.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45, 0.7))
			else:
				pct_num.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35, 0.7))
			pct_hbox.add_child(pct_num)
			var close_bracket := Label.new()
			close_bracket.text = ")"
			close_bracket.add_theme_font_size_override("font_size", 11)
			close_bracket.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			pct_hbox.add_child(close_bracket)
		pct_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
		pct_hbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pct_hbox.mouse_entered.connect(_on_class_hover.bind(city_id, cls_key, "population"))
		pct_hbox.mouse_exited.connect(_on_class_hover_exit)
		vbox.add_child(pct_hbox)

		# Class loyalty line: "Class Loyalty:" neutral, numbers colored
		var loyalty_hbox := HBoxContainer.new()
		loyalty_hbox.add_theme_constant_override("separation", 0)
		var loyalty_prefix := Label.new()
		loyalty_prefix.text = "    Class Loyalty: "
		loyalty_prefix.add_theme_font_size_override("font_size", 11)
		loyalty_prefix.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		loyalty_hbox.add_child(loyalty_prefix)
		var loyalty_value := Label.new()
		if cls_key == "captives":
			loyalty_value.text = "0"
			loyalty_value.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		else:
			loyalty_value.text = str(cls_loyalty)
			if cls_loyalty >= 30:
				loyalty_value.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45))
			elif cls_loyalty <= -10:
				loyalty_value.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
			elif cls_loyalty < 10:
				loyalty_value.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3))
			else:
				loyalty_value.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		loyalty_value.add_theme_font_size_override("font_size", 11)
		loyalty_hbox.add_child(loyalty_value)
		if cls_key != "captives" and cls_delta != 0:
			var delta_label := Label.new()
			delta_label.text = "  %+d" % cls_delta
			delta_label.add_theme_font_size_override("font_size", 11)
			delta_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45) if cls_delta > 0 else Color(0.85, 0.4, 0.35))
			loyalty_hbox.add_child(delta_label)
		loyalty_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
		loyalty_hbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		loyalty_hbox.mouse_entered.connect(_on_class_hover.bind(city_id, cls_key, "loyalty"))
		loyalty_hbox.mouse_exited.connect(_on_class_hover_exit)
		vbox.add_child(loyalty_hbox)

	_add_separator(vbox)

	# Province loyalty summary
	var net_label := Label.new()
	net_label.text = "  Province Loyalty: %d  (%s)" % [city.loyalty, status_text]
	net_label.add_theme_font_size_override("font_size", 13)
	net_label.add_theme_color_override("font_color", loyalty_color)
	vbox.add_child(net_label)

	if loyalty_mult < 1.0:
		var malus_header := Label.new()
		malus_header.text = "  Income malus (-%d%%):" % int((1.0 - loyalty_mult) * 100)
		malus_header.add_theme_font_size_override("font_size", 12)
		malus_header.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
		vbox.add_child(malus_header)
		# Calculate actual resource losses
		var region_data: RegionData = DataManager.get_region(city.region_id)
		var base_income := {}
		if region_data:
			var prov_pop := LoyaltySystem.get_province_population(city.region_id, city.faction_id)
			var pop_mult := minf(float(prov_pop) / 100.0, float(city.level))
			if prov_pop < 50:
				pop_mult *= maxf(0.1, float(prov_pop) / 50.0)
			for res_type in region_data.base_income:
				base_income[res_type] = int(region_data.base_income[res_type] * pop_mult)
		for building_id in city.buildings:
			var bd: BuildingData = DataManager.get_building(building_id)
			if bd:
				for res_type in bd.income_bonus:
					base_income[res_type] = base_income.get(res_type, 0) + bd.income_bonus[res_type]
		var income_pcts := LoyaltySystem.calculate_class_percentages(city, faction_id)
		base_income = LoyaltySystem.apply_class_bonuses(base_income, income_pcts)
		var loss_parts: Array[String] = []
		for res_type in base_income:
			var loss := int(float(base_income[res_type]) * (1.0 - loyalty_mult))
			if loss > 0:
				var res_name: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else str(res_type)
				loss_parts.append("-%d %s" % [loss, res_name])
		if loss_parts.size() > 0:
			var loss_label := Label.new()
			loss_label.text = "    " + ", ".join(loss_parts)
			loss_label.add_theme_font_size_override("font_size", 11)
			loss_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
			vbox.add_child(loss_label)

	var growth_mult := CitySystem._get_loyalty_growth_multiplier(city.loyalty)
	if growth_mult < 1.0:
		var growth_malus_label := Label.new()
		if growth_mult <= 0.0:
			growth_malus_label.text = "  Population growth: HALTED"
		else:
			growth_malus_label.text = "  Population growth: -%d%%" % int((1.0 - growth_mult) * 100)
		growth_malus_label.add_theme_font_size_override("font_size", 12)
		growth_malus_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
		vbox.add_child(growth_malus_label)

	_add_separator(vbox)

	# MODIFIERS section (province-level weighted breakdown)
	var mod_header := Label.new()
	mod_header.text = "MODIFIERS"
	mod_header.add_theme_font_size_override("font_size", 13)
	mod_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(mod_header)

	var breakdown := LoyaltySystem.get_loyalty_breakdown(city, faction_id)
	for entry in breakdown:
		var sign_char := "+" if entry.value >= 0 else ""
		var prefix := "  + " if entry.value >= 0 else "  - "
		var entry_label := Label.new()
		entry_label.text = "%s%-26s %s%d" % [prefix, entry.label, sign_char, entry.value]
		entry_label.add_theme_font_size_override("font_size", 12)
		if entry.value >= 0:
			entry_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45))
		else:
			entry_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
		vbox.add_child(entry_label)

	_add_separator(vbox)

	# REVOLT RISK
	var revolt_chance := LoyaltySystem.get_revolt_chance(city.loyalty)
	var revolt_label := Label.new()
	revolt_label.text = "REVOLT RISK: %d%%" % int(revolt_chance * 100.0)
	revolt_label.add_theme_font_size_override("font_size", 13)
	if revolt_chance > 0:
		revolt_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
	else:
		revolt_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45))
	vbox.add_child(revolt_label)

	add_child(_loyalty_panel)

func _on_loyalty_panel_close() -> void:
	_on_class_hover_exit()
	_loyalty_panel_city_id = &""
	if _loyalty_panel:
		_loyalty_panel.queue_free()
		_loyalty_panel = null

func _on_class_hover(city_id: StringName, cls_key: String, hover_type: String) -> void:
	_on_class_hover_exit()
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	var lines: Array[String] = []
	if hover_type == "population":
		var breakdown := LoyaltySystem.get_class_percentage_breakdown(city, city.faction_id, cls_key)
		lines.append(cls_key.capitalize() + " - Population %")
		lines.append("")
		for entry in breakdown:
			if entry.value != "":
				lines.append("  %s: %s" % [entry.label, entry.value])
			else:
				lines.append("  %s" % entry.label)
	elif hover_type == "loyalty":
		var breakdown := LoyaltySystem.get_class_loyalty_breakdown(city, city.faction_id, cls_key)
		lines.append(cls_key.capitalize() + " - Loyalty Modifiers")
		lines.append("")
		if cls_key == "captives":
			lines.append("  Captives always have 0 loyalty")
		else:
			for entry in breakdown:
				var sign_str := "+" if entry.value >= 0 else ""
				lines.append("  %s%d  %s" % [sign_str, entry.value, entry.label])

	if lines.is_empty():
		return

	_class_hover_tooltip = PanelContainer.new()
	_class_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_hover_tooltip.custom_minimum_size = Vector2(220, 0)
	var tt_style := StyleBoxFlat.new()
	tt_style.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	tt_style.border_width_left = 1
	tt_style.border_width_top = 1
	tt_style.border_width_right = 1
	tt_style.border_width_bottom = 1
	tt_style.border_color = Color(0.55, 0.42, 0.2, 0.7)
	tt_style.corner_radius_top_left = 4
	tt_style.corner_radius_top_right = 4
	tt_style.corner_radius_bottom_right = 4
	tt_style.corner_radius_bottom_left = 4
	tt_style.content_margin_left = 8.0
	tt_style.content_margin_top = 6.0
	tt_style.content_margin_right = 8.0
	tt_style.content_margin_bottom = 6.0
	_class_hover_tooltip.add_theme_stylebox_override("panel", tt_style)
	var tt_label := Label.new()
	tt_label.text = "\n".join(lines)
	tt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tt_label.custom_minimum_size = Vector2(200, 0)
	tt_label.add_theme_font_size_override("font_size", 11)
	tt_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	_class_hover_tooltip.add_child(tt_label)
	_class_hover_tooltip.position = get_global_mouse_position() + Vector2(12, 12)
	add_child(_class_hover_tooltip)

func _on_class_hover_exit() -> void:
	if _class_hover_tooltip:
		_class_hover_tooltip.queue_free()
		_class_hover_tooltip = null

func _on_build_pressed(city_id: StringName, building_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	var building: BuildingData = DataManager.get_building(building_id)
	if city == null or building == null:
		return
	var valid_tiles := GameManager.city_system.get_valid_tiles_for_building(city, building)
	if valid_tiles.is_empty():
		return
	# If only one valid tile, skip selection and build immediately
	if valid_tiles.size() == 1:
		if GameManager.city_system.start_building(city_id, building_id, valid_tiles[0]):
			AudioManager.play_sfx(&"building_start")
			_show_city_panel(city_id)
			_update_resource_display()
			building_queued.emit()
		return
	# Enter tile selection mode
	_pending_building_city_id = city_id
	_pending_building_id = building_id
	building_tile_selection_requested.emit(city_id, building_id, valid_tiles)

func confirm_building_tile(tile_pos: Vector2i) -> void:
	if _pending_building_city_id == &"" or _pending_building_id == &"":
		return
	var city_id := _pending_building_city_id
	var building_id := _pending_building_id
	_pending_building_city_id = &""
	_pending_building_id = &""
	if GameManager.city_system.start_building(city_id, building_id, tile_pos):
		AudioManager.play_sfx(&"building_start")
		_show_city_panel(city_id)
		_update_resource_display()
		building_queued.emit()

func cancel_building_tile() -> void:
	_pending_building_city_id = &""
	_pending_building_id = &""
	building_tile_selection_cancelled.emit()

func _on_building_hover(building_id: StringName) -> void:
	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return

	# Highlight produced resources in top bar
	for res_type in building.income_bonus:
		if building.income_bonus[res_type] > 0 and _resource_items.has(res_type):
			var lbl: Label = _resource_items[res_type]["amount_label"]
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))

	if _building_tooltip == null:
		return

	var text := building.display_name + "\n"
	text += "[" + str(building.category).capitalize() + "]\n"
	text += building.description + "\n"

	# Terrain requirement
	if building.required_terrain >= 0:
		var terrain_names := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
		text += "Requires adjacent: " + terrain_names[building.required_terrain] + "\n"

	# Income bonuses
	var has_effects := false
	for res_type in building.income_bonus:
		if building.income_bonus[res_type] != 0:
			text += "\n  +%d %s/turn" % [building.income_bonus[res_type], RESOURCE_NAMES[res_type]]
			has_effects = true
	if building.population_growth_bonus > 0:
		text += "\n  +%d Growth" % building.population_growth_bonus
		has_effects = true
	if building.defense_bonus > 0:
		text += "\n  +%d Defense" % building.defense_bonus
		has_effects = true
	if building.recruit_speed_bonus > 0:
		text += "\n  +%d Recruit Speed" % building.recruit_speed_bonus
		has_effects = true

	# Units unlocked
	if building.unlocks_units.size() > 0:
		var unit_names: Array[String] = []
		for uid in building.unlocks_units:
			var ud := DataManager.get_unit(uid)
			unit_names.append(ud.display_name if ud else str(uid))
		text += "\n\nUnlocks: " + ", ".join(unit_names)

	# Skulloath dual-path indicator
	if building.faction_id == &"skulloath":
		var tradition_buildings := [&"herders_camp", &"steppe_pastures", &"ancestor_shrine", &"spirit_lodge", &"ancestor_sanctum", &"trade_post_skulloath", &"steppe_watchtower"]
		var void_buildings := [&"pale_waif_altar", &"void_sanctum", &"blood_altar", &"demon_gate"]
		if tradition_buildings.has(building_id):
			text += "\n\n[Tradition Path] -1 Corruption/turn"
			if building_id == &"ancestor_sanctum":
				text += "\nRequires Corruption <= 40"
		elif void_buildings.has(building_id):
			text += "\n\n[Void Path] +2 Corruption/turn"
			if building_id == &"demon_gate":
				text += "\nRequires Corruption >= 60"

	# Upgrade chain info
	if building.upgrades_from != &"":
		var from_bd: BuildingData = DataManager.get_building(building.upgrades_from)
		var from_name := from_bd.display_name if from_bd else str(building.upgrades_from)
		text += "\n\nUpgrades from: " + from_name
	var next_building := _find_upgrade_for(building_id)
	if next_building:
		text += "\n\nUpgrades to: " + next_building.display_name

	_building_tooltip.get_node("TooltipText").text = text
	_building_tooltip.position = get_global_mouse_position() + Vector2(-260, 12)
	_building_tooltip.visible = true

func _on_building_hover_exit() -> void:
	# Reset all resource label colors in top bar
	for res_type in _resource_items:
		var lbl: Label = _resource_items[res_type]["amount_label"]
		lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	if _building_tooltip:
		_building_tooltip.visible = false

func _find_upgrade_for(building_id: StringName) -> BuildingData:
	for bid in DataManager.buildings:
		var b: BuildingData = DataManager.buildings[bid]
		if b.upgrades_from == building_id:
			return b
	return null

func _format_cost_bbcode(cost: Dictionary, fs: FactionState) -> String:
	var parts: Array[String] = []
	for res_type in cost:
		var amount: int = cost[res_type]
		var has: int = fs.resources.get(res_type, 0) if fs else 0
		var hex_color: String = "66cc66" if has >= amount else "cc4444"
		var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
		parts.append("[color=#%s]%d %s[/color]" % [hex_color, amount, rname])
	return ", ".join(parts)

func _create_building_card(building: BuildingData, city_id: StringName, fs: FactionState, slot_blocked: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 100)

	var cat_color := _get_building_category_color(building)
	var can_afford := fs != null and _can_afford_display(fs, building.build_cost)
	var is_buildable := can_afford and not slot_blocked

	var style := StyleBoxFlat.new()
	var _dimmed := cat_color.darkened(0.4)
	var _gray := _dimmed.get_luminance()
	style.bg_color = cat_color if is_buildable else Color(_dimmed.lerp(Color(_gray, _gray, _gray), 0.5), 0.35)
	style.border_color = Color(cat_color, 0.8) if is_buildable else Color(0.4, 0.38, 0.35, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6.0
	style.content_margin_top = 4.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", style)

	# Grey out slot-blocked cards
	if slot_blocked:
		card.modulate = Color(0.6, 0.58, 0.55, 0.85)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	card.add_child(card_vbox)

	# Row 1: Name + category tag
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	var name_label := Label.new()
	if building.upgrades_from != &"":
		name_label.text = "\u25B2 " + building.display_name
	else:
		name_label.text = building.display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.85, 0.55) if is_buildable else Color(0.7, 0.65, 0.58))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_row.add_child(name_label)
	var cat_tag := Label.new()
	cat_tag.text = str(building.category).left(3).to_upper()
	cat_tag.add_theme_font_size_override("font_size", 9)
	cat_tag.add_theme_color_override("font_color", Color(cat_color, 1.0).lightened(0.5))
	name_row.add_child(cat_tag)
	card_vbox.add_child(name_row)

	# Row 2: Cost + build time (per-resource coloring via BBCode)
	var cost_rtl := RichTextLabel.new()
	cost_rtl.bbcode_enabled = true
	cost_rtl.fit_content = true
	cost_rtl.scroll_active = false
	cost_rtl.custom_minimum_size = Vector2(148, 0)
	cost_rtl.add_theme_font_size_override("normal_font_size", 10)
	var cost_bbcode := _format_cost_bbcode(building.build_cost, fs)
	cost_rtl.text = cost_bbcode + "  " + str(building.build_time) + "t"
	card_vbox.add_child(cost_rtl)

	# Row 2b: Upkeep cost (orange)
	var upkeep := GameManager.city_system.get_building_upkeep(building)
	if not upkeep.is_empty():
		var upkeep_label := Label.new()
		upkeep_label.text = "Upkeep: " + _format_cost(upkeep) + "/turn"
		upkeep_label.add_theme_font_size_override("font_size", 9)
		upkeep_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
		card_vbox.add_child(upkeep_label)

	# Row 3: Terrain requirement
	if building.required_terrain >= 0:
		var terrain_name: String = Enums.TerrainType.keys()[building.required_terrain].capitalize()
		var req_label := Label.new()
		req_label.text = "Requires: " + terrain_name
		req_label.add_theme_font_size_override("font_size", 9)
		req_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.45))
		card_vbox.add_child(req_label)

	# Row 4: Key effects summary
	var effects := _get_building_effects_summary(building)
	if effects != "":
		var eff_label := Label.new()
		eff_label.text = effects
		eff_label.add_theme_font_size_override("font_size", 9)
		eff_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
		eff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_vbox.add_child(eff_label)

	# Click handling
	var captured_bid := building.id
	var captured_cid := city_id
	var captured_slot_blocked := slot_blocked
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if captured_slot_blocked:
					AudioManager.play_sfx(&"error_buzz")
				elif not can_afford:
					AudioManager.play_sfx(&"error_buzz")
				else:
					_on_build_pressed(captured_cid, captured_bid)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_show_building_detail(captured_bid, captured_cid)
	)

	# Hover effect
	card.mouse_entered.connect(func():
		_on_building_hover(captured_bid)
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2(1.03, 1.03), 0.1)
	)
	card.mouse_exited.connect(func():
		_on_building_hover_exit()
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.1)
	)
	card.pivot_offset = Vector2(80, 50)

	return card

func _get_building_category_color(building: BuildingData) -> Color:
	match building.category:
		&"economic":
			var is_industrial := false
			for res in building.income_bonus:
				if res == Enums.ResourceType.IRON or res == Enums.ResourceType.WOOD:
					is_industrial = true
					break
			return Color(0.85, 0.72, 0.3, 0.45) if is_industrial else Color(0.35, 0.7, 0.3, 0.45)
		&"military":
			return Color(0.75, 0.25, 0.2, 0.45)
		&"defensive":
			return Color(0.35, 0.55, 0.75, 0.45)
		&"cultural":
			return Color(0.55, 0.35, 0.75, 0.45)
		_:
			return Color(0.4, 0.4, 0.4, 0.35)

func _get_building_effects_summary(building: BuildingData) -> String:
	var parts: Array[String] = []
	for res_type in building.income_bonus:
		if building.income_bonus[res_type] != 0:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			parts.append("+%d %s" % [building.income_bonus[res_type], rname])
	if building.population_growth_bonus > 0:
		parts.append("+%d Growth" % building.population_growth_bonus)
	if building.defense_bonus > 0:
		parts.append("+%d Def" % building.defense_bonus)
	if building.unlocks_units.size() > 0:
		var names: Array[String] = []
		for uid in building.unlocks_units:
			var ud := DataManager.get_unit(uid)
			names.append(ud.display_name if ud else str(uid))
		parts.append("Unlocks: " + ", ".join(names))
	return ", ".join(parts)

func _on_building_label_clicked(event: InputEvent, building_id: StringName, city_id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_show_building_detail(building_id, city_id)

func _show_building_detail(building_id: StringName, city_id: StringName) -> void:
	if _building_detail_panel:
		_building_detail_panel.queue_free()

	var building: BuildingData = DataManager.get_building(building_id)
	if building == null:
		return

	_building_detail_panel = _create_centered_dialog(500, 420)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_building_detail_panel.add_child(outer_vbox)

	# Header with close
	var header := HBoxContainer.new()
	var title := _make_label(building.display_name + "  [" + str(building.category).capitalize() + "]", 16, Color(0.95, 0.88, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_make_close_button(func():
		if _building_detail_panel:
			_building_detail_panel.queue_free()
			_building_detail_panel = null
	))
	outer_vbox.add_child(header)

	# Main content: portrait on left, info on right
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_hbox)

	# Portrait placeholder (80x120) with category color
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(80, 120)
	var portrait_style := StyleBoxFlat.new()
	var cat_str: String = str(building.category)
	var cat_color := Color(0.3, 0.25, 0.2)
	var cat_icon := "B"
	match cat_str:
		"military":
			cat_color = Color(0.5, 0.22, 0.18)
			cat_icon = "M"
		"economic":
			cat_color = Color(0.55, 0.48, 0.2)
			cat_icon = "E"
		"cultural":
			cat_color = Color(0.4, 0.2, 0.5)
			cat_icon = "C"
		"defensive":
			cat_color = Color(0.3, 0.38, 0.5)
			cat_icon = "D"
	portrait_style.bg_color = cat_color
	portrait_style.border_width_left = 2
	portrait_style.border_width_top = 2
	portrait_style.border_width_right = 2
	portrait_style.border_width_bottom = 2
	portrait_style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	portrait_style.corner_radius_top_left = 4
	portrait_style.corner_radius_top_right = 4
	portrait_style.corner_radius_bottom_right = 4
	portrait_style.corner_radius_bottom_left = 4
	portrait.add_theme_stylebox_override("panel", portrait_style)
	var icon_center := CenterContainer.new()
	portrait.add_child(icon_center)
	var icon_label := Label.new()
	icon_label.text = cat_icon
	icon_label.add_theme_font_size_override("font_size", 36)
	icon_label.add_theme_color_override("font_color", cat_color.lightened(0.5))
	icon_center.add_child(icon_label)
	content_hbox.add_child(portrait)

	# Right side: scrollable content
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Description
	var desc := Label.new()
	desc.text = building.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	# Current effects
	var effects_header := Label.new()
	effects_header.text = "Effects"
	effects_header.add_theme_font_size_override("font_size", 13)
	effects_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(effects_header)

	for res_type in building.income_bonus:
		if building.income_bonus[res_type] != 0:
			var eff := Label.new()
			eff.text = "  +%d %s/turn" % [building.income_bonus[res_type], RESOURCE_NAMES[res_type]]
			eff.add_theme_font_size_override("font_size", 12)
			eff.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
			vbox.add_child(eff)
	if building.population_growth_bonus > 0:
		var eff := Label.new()
		eff.text = "  +%d Growth" % building.population_growth_bonus
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
		vbox.add_child(eff)
	if building.defense_bonus > 0:
		var eff := Label.new()
		eff.text = "  +%d Defense" % building.defense_bonus
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
		vbox.add_child(eff)
	if building.unlocks_units.size() > 0:
		var unit_names: Array[String] = []
		for uid in building.unlocks_units:
			var ud := DataManager.get_unit(uid)
			unit_names.append(ud.display_name if ud else str(uid))
		var eff := Label.new()
		eff.text = "  Unlocks: " + ", ".join(unit_names)
		eff.add_theme_font_size_override("font_size", 12)
		eff.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		vbox.add_child(eff)

	# Upkeep cost display (orange)
	var detail_upkeep := GameManager.city_system.get_building_upkeep(building)
	if not detail_upkeep.is_empty():
		var upkeep_eff := Label.new()
		upkeep_eff.text = "  Upkeep: " + _format_cost(detail_upkeep) + "/turn"
		upkeep_eff.add_theme_font_size_override("font_size", 12)
		upkeep_eff.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
		vbox.add_child(upkeep_eff)

	_add_separator(vbox)

	# Building chain: predecessor -> current -> upgrades
	var chain_header := Label.new()
	chain_header.text = "Building Chain"
	chain_header.add_theme_font_size_override("font_size", 13)
	chain_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(chain_header)

	var chain_text := ""
	if building.upgrades_from != &"":
		var from_b := DataManager.get_building(building.upgrades_from)
		chain_text += (from_b.display_name if from_b else str(building.upgrades_from)) + " -> "
	chain_text += "[" + building.display_name + "]"
	var next := _find_upgrade_for(building_id)
	if next:
		chain_text += " -> " + next.display_name

	var chain_label := Label.new()
	chain_label.text = "  " + chain_text
	chain_label.add_theme_font_size_override("font_size", 12)
	chain_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	vbox.add_child(chain_label)

	# Upgrade button if available
	if next:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and city.faction_id == GameManager.state.player_faction_id and city.build_queue.is_empty():
			var available := GameManager.city_system.get_available_buildings(city)
			for avail_b in available:
				if avail_b.id == next.id:
					_add_separator(vbox)
					var upgrade_btn := Button.new()
					upgrade_btn.text = "Upgrade to " + next.display_name
					upgrade_btn.custom_minimum_size = Vector2(240, 32)
					upgrade_btn.pressed.connect(func():
						if GameManager.city_system.start_building(city_id, next.id):
							AudioManager.play_sfx(&"building_start")
							if _building_detail_panel:
								_building_detail_panel.queue_free()
								_building_detail_panel = null
							_show_city_panel(city_id)
							_update_resource_display()
					)
					var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
					if fs and not _can_afford_display(fs, next.build_cost):
						upgrade_btn.disabled = true
					vbox.add_child(upgrade_btn)
					var cost_label := Label.new()
					cost_label.text = _format_cost(next.build_cost) + " | " + str(next.build_time) + " turn(s)"
					cost_label.add_theme_font_size_override("font_size", 11)
					cost_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
					vbox.add_child(cost_label)
					break

	# Demolish button (player only, if building is owned)
	var demolish_city: CityState = GameManager.state.cities.get(city_id)
	if demolish_city and demolish_city.faction_id == GameManager.state.player_faction_id and demolish_city.buildings.has(building_id):
		_add_separator(vbox)
		var has_dependent := GameManager.city_system.has_dependent_upgrade(demolish_city, building_id)
		var refund := GameManager.city_system.get_demolish_refund(building_id)
		var refund_text := _format_cost(refund) if not refund.is_empty() else "None"

		var demolish_btn := Button.new()
		demolish_btn.text = "Demolish Building"
		demolish_btn.custom_minimum_size = Vector2(240, 32)
		if has_dependent:
			demolish_btn.disabled = true
			demolish_btn.tooltip_text = "Cannot demolish: an upgraded building depends on this one"
		else:
			demolish_btn.pressed.connect(func():
				if GameManager.city_system.demolish_building(city_id, building_id):
					if _building_detail_panel:
						_building_detail_panel.queue_free()
						_building_detail_panel = null
					_show_city_panel(city_id)
					_update_resource_display()
			)
		vbox.add_child(demolish_btn)

		var refund_label := Label.new()
		refund_label.text = "Refund: " + refund_text
		refund_label.add_theme_font_size_override("font_size", 11)
		refund_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		vbox.add_child(refund_label)

	add_child(_building_detail_panel)

func _show_unit_card(unit_data_id: StringName) -> void:
	_hide_unit_card()
	var unit_data := DataManager.get_unit(unit_data_id)
	if unit_data == null:
		return

	_unit_card_panel = PanelContainer.new()
	_unit_card_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	_unit_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var name_label := Label.new()
	name_label.text = unit_data.display_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	vbox.add_child(name_label)

	if unit_data.tags.size() > 0:
		var tags_label := Label.new()
		var tag_strs: Array[String] = []
		for t in unit_data.tags:
			tag_strs.append(t.capitalize())
		tags_label.text = ", ".join(tag_strs)
		tags_label.add_theme_font_size_override("font_size", 10)
		tags_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		vbox.add_child(tags_label)

	var stats := Label.new()
	var card_dps := estimate_unit_dps(unit_data)
	var card_atk_s := render_stars(get_attack_stars(unit_data))
	var card_def_s := render_stars(get_defense_stars(unit_data))
	stats.text = "%s ATK  %s DEF\nHP: %d  DPS: %d  SPD: %d\nDEF: %d/%d/%d (Melee/Ranged/Magic)" % [card_atk_s, card_def_s, unit_data.max_hp, int(card_dps), unit_data.speed, unit_data.melee_defense, unit_data.projectile_defense, unit_data.magic_defense]
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	vbox.add_child(stats)

	if unit_data.attack_range > 1:
		var range_label := Label.new()
		range_label.text = "Range: %d" % unit_data.attack_range
		range_label.add_theme_font_size_override("font_size", 11)
		range_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		vbox.add_child(range_label)

	var squad_label := Label.new()
	var card_pop_cost: int = unit_data.population_cost if unit_data.population_cost >= 0 else unit_data.squad_size
	squad_label.text = "Squad: %d  |  Pop Cost: %d  |  MP: %.1f" % [unit_data.squad_size, card_pop_cost, unit_data.movement_points]
	squad_label.add_theme_font_size_override("font_size", 11)
	squad_label.add_theme_color_override("font_color", Color(0.55, 0.72, 0.55))
	vbox.add_child(squad_label)

	if unit_data.recruit_cost.size() > 0:
		var recruit_label := Label.new()
		recruit_label.text = "Recruit: " + _format_cost(unit_data.recruit_cost)
		recruit_label.add_theme_font_size_override("font_size", 10)
		recruit_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(recruit_label)

	if unit_data.upkeep_cost.size() > 0:
		var upkeep_label := Label.new()
		upkeep_label.text = "Upkeep: " + _format_cost(unit_data.upkeep_cost)
		upkeep_label.add_theme_font_size_override("font_size", 10)
		upkeep_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
		vbox.add_child(upkeep_label)

	_unit_card_panel.add_child(vbox)
	_unit_card_panel.position = get_global_mouse_position() + Vector2(-260, 12)
	add_child(_unit_card_panel)

func _hide_unit_card() -> void:
	if _unit_card_panel:
		_unit_card_panel.queue_free()
		_unit_card_panel = null

func _on_recruit_pressed(city_id: StringName, unit_data_id: StringName) -> void:
	if GameManager.city_system.start_recruitment(city_id, unit_data_id):
		AudioManager.play_sfx(&"recruit_start")
		_show_city_panel(city_id)
		_update_resource_display()

func _get_recruitable_units(city: CityState) -> Array[StringName]:
	var result: Array[StringName] = []
	var unit_tier: Dictionary = {} # unit_id -> required_capital_level of unlocking building
	for building_id in city.buildings:
		# Collect units from this building and all its predecessors in the upgrade chain
		var current_id: StringName = building_id
		while current_id != &"":
			var building: BuildingData = DataManager.get_building(current_id)
			if building == null:
				break
			for unit_id in building.unlocks_units:
				var unit_data := DataManager.get_unit(unit_id)
				if unit_data and unit_data.faction_id == city.faction_id and not result.has(unit_id):
					result.append(unit_id)
					unit_tier[unit_id] = building.required_capital_level
			current_id = building.upgrades_from
	# Sort by tier (building required_capital_level), then by gold cost
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		var tier_a: int = unit_tier.get(a, 1)
		var tier_b: int = unit_tier.get(b, 1)
		if tier_a != tier_b:
			return tier_a < tier_b
		var ud_a := DataManager.get_unit(a)
		var ud_b := DataManager.get_unit(b)
		var gold_a: int = ud_a.recruit_cost.get(Enums.ResourceType.GOLD, 0) if ud_a else 0
		var gold_b: int = ud_b.recruit_cost.get(Enums.ResourceType.GOLD, 0) if ud_b else 0
		return gold_a < gold_b
	)
	return result

func _can_afford_display(fs: FactionState, cost: Dictionary) -> bool:
	for res_type in cost:
		if fs.resources.get(res_type, 0) < cost[res_type]:
			return false
	return true

func _format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for res_type in cost:
		var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
		parts.append(str(cost[res_type]) + " " + rname)
	return ", ".join(parts)

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	parent.add_child(sep)

# ── Shard Display ─────────────────────────────────────────────

func _create_shard_display() -> void:
	shard_label = Label.new()
	shard_label.add_theme_font_size_override("font_size", 12)
	shard_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.8))
	shard_label.mouse_filter = Control.MOUSE_FILTER_STOP
	shard_label.mouse_entered.connect(_on_shard_label_mouse_entered)
	shard_label.mouse_exited.connect(_on_shard_label_mouse_exited)

	var hbox: HBoxContainer = $TopBar/HBoxContainer
	var spacer := hbox.get_node("Spacer")
	hbox.add_child(shard_label)
	hbox.move_child(shard_label, spacer.get_index())

	# Create tooltip panel (hidden)
	shard_tooltip = PanelContainer.new()
	shard_tooltip.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.7, 0.3, 0.8, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	shard_tooltip.add_theme_stylebox_override("panel", style)
	shard_tooltip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var tooltip_label := Label.new()
	tooltip_label.name = "TooltipText"
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	shard_tooltip.add_child(tooltip_label)
	add_child(shard_tooltip)

func _update_shard_display() -> void:
	if shard_label == null or GameManager.state == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs == null:
		return
	var total_shards := fs.owned_shards.size()
	shard_label.text = "  |  Shards: " + str(total_shards)

func _on_shard_label_mouse_entered() -> void:
	if shard_tooltip == null or GameManager.state == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs == null:
		return

	var realm_counts: Dictionary = {}
	for shard_id in fs.owned_shards:
		var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
		if shard:
			var realm_name := ShardfallSystem.get_realm_name(shard.realm)
			realm_counts[realm_name] = realm_counts.get(realm_name, 0) + 1

	var text := "Shards: %d total" % fs.owned_shards.size()
	for realm_name in realm_counts:
		text += "\n  %s: %d" % [realm_name, realm_counts[realm_name]]
	if fs.owned_shards.is_empty():
		text += "\n  (none)"

	var tooltip_label: Label = shard_tooltip.get_node("TooltipText")
	tooltip_label.text = text
	# Position tooltip directly below the shard label
	var label_rect := shard_label.get_global_rect()
	shard_tooltip.global_position = Vector2(label_rect.position.x, label_rect.end.y + 4)
	shard_tooltip.visible = true

func _on_shard_label_mouse_exited() -> void:
	if shard_tooltip:
		shard_tooltip.visible = false

func _on_shard_claimed(_shard_id: StringName, _faction_id: StringName) -> void:
	_update_shard_display()
	_update_resource_display()

# ── Commander Panel ───────────────────────────────────────────

func _create_commander_panel() -> void:
	commander_panel = PanelContainer.new()
	commander_panel.name = "CommanderPanel"
	commander_panel.visible = false

	# Anchored top-left below top bar
	commander_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	commander_panel.offset_left = 10.0
	commander_panel.offset_top = 54.0
	commander_panel.offset_right = 290.0
	commander_panel.offset_bottom = 450.0
	commander_panel.custom_minimum_size = Vector2(280, 0)

	commander_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	commander_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "CommanderVBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(commander_panel)

	# Create skill/item tooltip (hidden, positioned on hover)
	_skill_tooltip = PanelContainer.new()
	_skill_tooltip.visible = false
	var tt_style := StyleBoxFlat.new()
	tt_style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	tt_style.border_width_left = 1
	tt_style.border_width_top = 1
	tt_style.border_width_right = 1
	tt_style.border_width_bottom = 1
	tt_style.border_color = Color(0.55, 0.42, 0.2, 0.6)
	tt_style.corner_radius_top_left = 4
	tt_style.corner_radius_top_right = 4
	tt_style.corner_radius_bottom_right = 4
	tt_style.corner_radius_bottom_left = 4
	tt_style.content_margin_left = 8.0
	tt_style.content_margin_top = 6.0
	tt_style.content_margin_right = 8.0
	tt_style.content_margin_bottom = 6.0
	_skill_tooltip.add_theme_stylebox_override("panel", tt_style)
	var tt_label := Label.new()
	tt_label.name = "TooltipText"
	tt_label.add_theme_font_size_override("font_size", 11)
	tt_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	tt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tt_label.custom_minimum_size = Vector2(220, 0)
	_skill_tooltip.add_child(tt_label)
	_skill_tooltip.z_index = 100
	add_child(_skill_tooltip)

func _update_commander_panel(army: ArmyState) -> void:
	if commander_panel == null:
		return

	commander_panel.visible = true
	commander_panel.move_to_front()
	commander_panel.modulate = Color(1, 1, 1, 0)
	var _cp_tw := create_tween()
	_cp_tw.tween_property(commander_panel, "modulate:a", 1.0, 0.2)
	var scroll: ScrollContainer = commander_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("CommanderVBox")
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	var faction := DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction.color if faction else Color.WHITE
	var is_player_army := army.faction_id == GameManager.state.player_faction_id

	var is_elderbeast_army := army.elderbeast_id != &""

	if army.commander == null:
		# No commander assigned
		var no_cmd_label := Label.new()
		no_cmd_label.text = "No Commander"
		no_cmd_label.add_theme_font_size_override("font_size", 15)
		no_cmd_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		vbox.add_child(no_cmd_label)

		# Faction
		var faction_name_label := Label.new()
		faction_name_label.text = faction.display_name if faction else str(army.faction_id)
		faction_name_label.add_theme_font_size_override("font_size", 12)
		faction_name_label.add_theme_color_override("font_color", faction_color.lightened(0.3))
		vbox.add_child(faction_name_label)

		# Show dropdown for player armies (not elderbeast armies)
		if is_player_army and not is_elderbeast_army:
			var available := GameManager.get_available_commanders(army.faction_id)
			if available.size() > 0:
				_add_separator(vbox)
				var assign_label := Label.new()
				assign_label.text = "Assign Commander:"
				assign_label.add_theme_font_size_override("font_size", 12)
				assign_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
				vbox.add_child(assign_label)

				var dropdown := OptionButton.new()
				dropdown.add_theme_font_size_override("font_size", 12)
				dropdown.custom_minimum_size = Vector2(200, 28)
				dropdown.add_item("-- Select --")
				for cmd in available:
					dropdown.add_item("%s (Lv%d)" % [cmd.name, cmd.level])
				var captured_army_id := army.army_id
				var captured_commanders := available
				dropdown.item_selected.connect(func(idx: int):
					if idx > 0:
						var selected_cmd: CommanderState = captured_commanders[idx - 1]
						GameManager.assign_commander_to_army(captured_army_id, selected_cmd.commander_id)
						_update_commander_panel(GameManager.state.armies.get(captured_army_id))
						EventBus.army_selected.emit(captured_army_id)
				)
				vbox.add_child(dropdown)
			else:
				var no_pool := Label.new()
				no_pool.text = "No commanders in pool"
				no_pool.add_theme_font_size_override("font_size", 11)
				no_pool.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
				vbox.add_child(no_pool)
	else:
		# Commander name
		var cmd_name := army.get_commander_name()
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = cmd_name if cmd_name != "" else "Unknown Commander"
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(name_label)

		# Unassign button (player armies only, not elderbeast armies)
		if is_player_army and not is_elderbeast_army:
			var unassign_btn := Button.new()
			unassign_btn.text = "Unassign"
			unassign_btn.custom_minimum_size = Vector2(70, 24)
			unassign_btn.add_theme_font_size_override("font_size", 10)
			var captured_army_id := army.army_id
			unassign_btn.pressed.connect(func():
				GameManager.unassign_commander_from_army(captured_army_id)
				var updated_army: ArmyState = GameManager.state.armies.get(captured_army_id)
				if updated_army:
					_update_commander_panel(updated_army)
					EventBus.army_selected.emit(captured_army_id)
			)
			name_row.add_child(unassign_btn)
		vbox.add_child(name_row)

		# Faction / Elderbeast General label
		var faction_name_label := Label.new()
		if is_elderbeast_army:
			faction_name_label.text = "Elderbeast General"
			faction_name_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.9))
		else:
			faction_name_label.text = faction.display_name if faction else str(army.faction_id)
			faction_name_label.add_theme_color_override("font_color", faction_color.lightened(0.3))
		faction_name_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(faction_name_label)

	# Commander level & XP bar
	if army.commander:
		var cmd: CommanderState = army.commander
		var level_label := Label.new()
		level_label.text = "Level %d" % cmd.level
		level_label.add_theme_font_size_override("font_size", 13)
		level_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(level_label)

		# XP progress bar
		var xp_threshold := 0
		if cmd.level < CommanderState.XP_THRESHOLDS.size():
			xp_threshold = CommanderState.XP_THRESHOLDS[cmd.level]
		if xp_threshold > 0:
			var xp_bar := ProgressBar.new()
			xp_bar.custom_minimum_size = Vector2(200, 8)
			xp_bar.max_value = xp_threshold
			xp_bar.value = cmd.xp
			xp_bar.show_percentage = false
			var bar_style := StyleBoxFlat.new()
			bar_style.bg_color = Color(0.55, 0.42, 0.2)
			bar_style.corner_radius_top_left = 2
			bar_style.corner_radius_top_right = 2
			bar_style.corner_radius_bottom_right = 2
			bar_style.corner_radius_bottom_left = 2
			xp_bar.add_theme_stylebox_override("fill", bar_style)
			var bg_style := StyleBoxFlat.new()
			bg_style.bg_color = Color(0.15, 0.12, 0.1)
			bg_style.corner_radius_top_left = 2
			bg_style.corner_radius_top_right = 2
			bg_style.corner_radius_bottom_right = 2
			bg_style.corner_radius_bottom_left = 2
			xp_bar.add_theme_stylebox_override("background", bg_style)
			vbox.add_child(xp_bar)

			var xp_text := Label.new()
			xp_text.text = "XP: %d / %d" % [cmd.xp, xp_threshold]
			xp_text.add_theme_font_size_override("font_size", 10)
			xp_text.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
			vbox.add_child(xp_text)
		elif cmd.level >= 10:
			var max_label := Label.new()
			max_label.text = "XP: MAX LEVEL"
			max_label.add_theme_font_size_override("font_size", 10)
			max_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(max_label)

		# Traits section
		if cmd.traits.size() > 0:
			_add_separator(vbox)
			var traits_header := Label.new()
			traits_header.text = "Traits"
			traits_header.add_theme_font_size_override("font_size", 12)
			traits_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(traits_header)
			for trait_id in cmd.traits:
				var trait_data: CommanderTrait = CommanderSystem.traits_db.get(trait_id)
				var trait_label := Label.new()
				if trait_data:
					trait_label.text = "  " + trait_data.display_name
					if trait_data.is_positive:
						trait_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.45))
					else:
						trait_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))
				else:
					trait_label.text = "  " + str(trait_id)
					trait_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
				trait_label.add_theme_font_size_override("font_size", 11)
				trait_label.mouse_filter = Control.MOUSE_FILTER_STOP
				trait_label.mouse_entered.connect(_on_trait_hover_entered.bind(trait_id))
				trait_label.mouse_exited.connect(_on_skill_hover_exited)
				vbox.add_child(trait_label)

		# Skills section
		if cmd.skill_levels.size() > 0:
			_add_separator(vbox)
			var skills_header := Label.new()
			skills_header.text = "Skills"
			skills_header.add_theme_font_size_override("font_size", 12)
			skills_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(skills_header)
			for skill_id in cmd.skill_levels:
				var skill_data = CommanderSystem.skills.get(skill_id)
				var slevel: int = cmd.skill_levels[skill_id]
				var skill_label := Label.new()
				if skill_data:
					skill_label.text = "  %s (Lv.%d)" % [skill_data.display_name, slevel]
					skill_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
				else:
					skill_label.text = "  " + str(skill_id) + " (Lv.%d)" % slevel
					skill_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
				skill_label.add_theme_font_size_override("font_size", 11)
				skill_label.mouse_filter = Control.MOUSE_FILTER_STOP
				skill_label.mouse_entered.connect(_on_skill_hover_entered.bind(skill_id, slevel))
				skill_label.mouse_exited.connect(_on_skill_hover_exited)
				vbox.add_child(skill_label)

		var is_player_cmd := cmd.faction_id == GameManager.state.player_faction_id

		# Items section (skip for elderbeast generals)
		if not is_elderbeast_army:
			_add_separator(vbox)
			var max_item_slots := CommanderSystem.get_max_item_slots(cmd)
			var items_header := Label.new()
			items_header.text = "Items (%d/%d)" % [cmd.items.size(), max_item_slots]
			items_header.add_theme_font_size_override("font_size", 12)
			items_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(items_header)
			if cmd.items.size() > 0:
				for item_idx in cmd.items.size():
					var item_id: StringName = cmd.items[item_idx]
					var item_data = CommanderSystem.items.get(item_id)
					var item_label := Label.new()
					if item_data:
						item_label.text = "  " + item_data.display_name
						match item_data.rarity:
							&"legendary":
								item_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2))
							&"rare":
								item_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
							_:
								item_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
					else:
						item_label.text = "  " + str(item_id)
						item_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
					item_label.add_theme_font_size_override("font_size", 11)
					item_label.mouse_filter = Control.MOUSE_FILTER_STOP
					item_label.mouse_entered.connect(_on_item_hover_entered.bind(item_id))
					item_label.mouse_exited.connect(_on_skill_hover_exited)
					if is_player_cmd:
						item_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
						item_label.gui_input.connect(_on_item_label_clicked.bind(cmd, item_idx))
					vbox.add_child(item_label)
			else:
				var no_items := Label.new()
				no_items.text = "  (none)"
				no_items.add_theme_font_size_override("font_size", 11)
				no_items.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
				vbox.add_child(no_items)
			# "Equip from storage" button if there are empty slots and storage items
			if is_player_cmd and cmd.items.size() < max_item_slots:
				var fs: FactionState = GameManager.state.faction_states.get(cmd.faction_id)
				if fs and fs.item_storage.size() > 0:
					var equip_btn := Button.new()
					equip_btn.text = "  + Equip from Storage (%d)" % fs.item_storage.size()
					equip_btn.add_theme_font_size_override("font_size", 11)
					equip_btn.pressed.connect(_show_item_swap_panel.bind(cmd, -1))
					vbox.add_child(equip_btn)

		# Followers section (skip for elderbeast generals)
		if not is_elderbeast_army:
			_add_separator(vbox)
			var max_follower_slots := CommanderSystem.get_max_follower_slots(cmd)
			var followers_header := Label.new()
			followers_header.text = "Followers (%d/%d)" % [cmd.followers.size(), max_follower_slots]
			followers_header.add_theme_font_size_override("font_size", 12)
			followers_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(followers_header)
			if cmd.followers.size() > 0:
				for follower_id in cmd.followers:
					var follower: FollowerData = DataManager.get_follower(follower_id)
					if follower == null:
						continue
					var f_row := HBoxContainer.new()
					var f_name_label := Label.new()
					f_name_label.text = "  " + follower.display_name
					f_name_label.add_theme_font_size_override("font_size", 11)
					f_name_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
					f_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					f_row.add_child(f_name_label)
					if is_player_cmd:
						var unassign_btn := Button.new()
						unassign_btn.text = "X"
						unassign_btn.add_theme_font_size_override("font_size", 9)
						unassign_btn.custom_minimum_size = Vector2(22, 20)
						unassign_btn.tooltip_text = "Unassign follower"
						var captured_fid := follower_id
						var captured_cmd := cmd
						var captured_army_id := army.army_id
						unassign_btn.pressed.connect(func():
							var idx := captured_cmd.followers.find(captured_fid)
							if idx >= 0:
								captured_cmd.followers.remove_at(idx)
								var u_fs: FactionState = GameManager.state.faction_states.get(captured_cmd.faction_id)
								if u_fs:
									u_fs.follower_storage.append(captured_fid)
								# Recalculate movement after follower removal
								for a_id in GameManager.state.armies:
									var a: ArmyState = GameManager.state.armies[a_id]
									if a.commander == captured_cmd:
										var new_max := a.get_max_movement()
										a.movement_remaining = minf(a.movement_remaining, new_max)
								GameManager.movement_system._cache_valid = false
								_close_item_swap_panel()
								_refresh_commander_panel()
								if captured_army_id != &"":
									EventBus.army_selected.emit(captured_army_id)
						)
						f_row.add_child(unassign_btn)
					vbox.add_child(f_row)
					for eff_key in follower.bonus_effect:
						var bonus_label := Label.new()
						bonus_label.text = "    +%s %s" % [str(follower.bonus_effect[eff_key]), eff_key.replace("_", " ").capitalize()]
						bonus_label.add_theme_font_size_override("font_size", 10)
						bonus_label.add_theme_color_override("font_color", Color(0.4, 0.75, 0.4))
						vbox.add_child(bonus_label)
					for eff_key in follower.malus_effect:
						var malus_label := Label.new()
						malus_label.text = "    %s %s" % [str(follower.malus_effect[eff_key]), eff_key.replace("_", " ").capitalize()]
						malus_label.add_theme_font_size_override("font_size", 10)
						malus_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
						vbox.add_child(malus_label)
			else:
				var no_followers := Label.new()
				no_followers.text = "  (none)"
				no_followers.add_theme_font_size_override("font_size", 11)
				no_followers.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
				vbox.add_child(no_followers)
			# "Assign follower from storage" button
			if is_player_cmd and cmd.followers.size() < max_follower_slots:
				var f_fs: FactionState = GameManager.state.faction_states.get(cmd.faction_id)
				if f_fs and f_fs.follower_storage.size() > 0:
					var assign_follower_btn := Button.new()
					assign_follower_btn.text = "  + Assign Follower (%d)" % f_fs.follower_storage.size()
					assign_follower_btn.add_theme_font_size_override("font_size", 11)
					var captured_cmd := cmd
					var captured_army_id := army.army_id
					assign_follower_btn.pressed.connect(func():
						_show_follower_assign_panel(captured_cmd, captured_army_id)
					)
					vbox.add_child(assign_follower_btn)

	_add_separator(vbox)

	# Army composition
	var total_dps := 0.0
	var total_def := 0
	var total_spd := 0
	var infantry_count := 0
	var ranged_count := 0
	var mage_count := 0
	var cavalry_count := 0
	var total_upkeep: Dictionary = {}

	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		total_dps += estimate_unit_dps(ud)
		total_def += ud.get_avg_defense()
		total_spd += ud.speed
		if ud.tags.has("cavalry"):
			cavalry_count += 1
		elif ud.tags.has("mage"):
			mage_count += 1
		elif ud.tags.has("ranged"):
			ranged_count += 1
		elif ud.tags.has("infantry"):
			infantry_count += 1
		for res_type in ud.upkeep_cost:
			total_upkeep[res_type] = total_upkeep.get(res_type, 0) + ud.upkeep_cost[res_type]

	var avg_spd := total_spd / maxi(1, army.units.size())

	# Stats
	var stats_label := Label.new()
	stats_label.text = "DPS: %d  |  DEF: %d  |  SPD: %d" % [int(total_dps), total_def, avg_spd]
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	vbox.add_child(stats_label)

	var mp_label := Label.new()
	mp_label.text = "MP: %.1f / %.1f  |  Units: %d" % [army.movement_remaining, army.get_max_movement(), army.units.size()]
	mp_label.add_theme_font_size_override("font_size", 12)
	mp_label.add_theme_color_override("font_color", Color(0.55, 0.72, 0.55))
	vbox.add_child(mp_label)

	# Composition
	var comp_parts: Array[String] = []
	if infantry_count > 0:
		comp_parts.append("%d infantry" % infantry_count)
	if ranged_count > 0:
		comp_parts.append("%d ranged" % ranged_count)
	if mage_count > 0:
		comp_parts.append("%d mage" % mage_count)
	if cavalry_count > 0:
		comp_parts.append("%d cavalry" % cavalry_count)
	if comp_parts.size() > 0:
		var comp_label := Label.new()
		comp_label.text = ", ".join(comp_parts)
		comp_label.add_theme_font_size_override("font_size", 11)
		comp_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		vbox.add_child(comp_label)

	# Upkeep
	if total_upkeep.size() > 0:
		_add_separator(vbox)
		var upkeep_parts: Array[String] = []
		for res_type in total_upkeep:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			upkeep_parts.append(str(total_upkeep[res_type]) + " " + rname)
		var upkeep_label := Label.new()
		upkeep_label.text = "Upkeep: " + ", ".join(upkeep_parts)
		upkeep_label.add_theme_font_size_override("font_size", 11)
		upkeep_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
		vbox.add_child(upkeep_label)

func _on_skill_hover_entered(skill_id: StringName, skill_level: int = 1) -> void:
	var skill_data: CommanderSkill = CommanderSystem.skills.get(skill_id)
	if skill_data == null or _skill_tooltip == null:
		return
	var text := "%s (Lv.%d)\n" % [skill_data.display_name, skill_level]
	text += skill_data.description + "\n"
	for key in skill_data.effects:
		var base_val = skill_data.effects[key]
		var total_val = base_val * skill_level
		var key_name: String = str(key).replace("_", " ").capitalize()
		text += "  %s: %s (%s per level)\n" % [key_name, str(total_val), str(base_val)]
	_skill_tooltip.get_node("TooltipText").text = text.strip_edges()
	_skill_tooltip.position = get_global_mouse_position() + Vector2(12, 12)
	_skill_tooltip.visible = true
	move_child(_skill_tooltip, get_child_count() - 1)

func _on_item_hover_entered(item_id: StringName) -> void:
	var item_data: CommanderItem = CommanderSystem.items.get(item_id)
	if item_data == null or _skill_tooltip == null:
		return
	var text := item_data.display_name + " [" + str(item_data.rarity).capitalize() + "]\n"
	text += item_data.description + "\n"
	for key in item_data.effects:
		text += "  %s: %s\n" % [str(key).replace("_", " ").capitalize(), str(item_data.effects[key])]
	_skill_tooltip.get_node("TooltipText").text = text.strip_edges()
	_skill_tooltip.position = get_global_mouse_position() + Vector2(12, 12)
	_skill_tooltip.visible = true
	move_child(_skill_tooltip, get_child_count() - 1)

func _on_trait_hover_entered(trait_id: StringName) -> void:
	var trait_data: CommanderTrait = CommanderSystem.traits_db.get(trait_id)
	if trait_data == null or _skill_tooltip == null:
		return
	var text := trait_data.display_name
	if trait_data.is_positive:
		text += " (Positive)\n"
	else:
		text += " (Negative)\n"
	text += trait_data.description + "\n"
	if not trait_data.effects.is_empty():
		text += "──────────────────\n"
		for key in trait_data.effects:
			var val = trait_data.effects[key]
			var prefix: String = "+" if val >= 0 else ""
			text += "  %s%s %s\n" % [prefix, str(val), _format_effect_name(key)]
	if not trait_data.is_positive and not trait_data.lose_context.is_empty():
		text += "\nCan be overcome by: " + ", ".join(trait_data.lose_context)
	_skill_tooltip.get_node("TooltipText").text = text.strip_edges()
	_skill_tooltip.position = get_global_mouse_position() + Vector2(12, 12)
	_skill_tooltip.visible = true
	move_child(_skill_tooltip, get_child_count() - 1)

func _on_skill_hover_exited() -> void:
	if _skill_tooltip:
		_skill_tooltip.visible = false

func _on_item_label_clicked(event: InputEvent, commander: CommanderState, item_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_skill_hover_exited()
		_show_item_swap_panel(commander, item_idx)

func _show_item_swap_panel(commander: CommanderState, item_idx: int) -> void:
	_close_item_swap_panel()

	var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
	var has_storage := fs != null and fs.item_storage.size() > 0
	var has_equipped := item_idx >= 0 and item_idx < commander.items.size()

	if not has_storage and not has_equipped:
		return

	_item_swap_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.97)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	_item_swap_panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_swap_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	if has_equipped:
		var equipped_data = CommanderSystem.items.get(commander.items[item_idx])
		title.text = "Swap: " + (equipped_data.display_name if equipped_data else "?")
	else:
		title.text = "Equip from Storage"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	header.add_child(_make_close_button(_close_item_swap_panel, Vector2(24, 24)))
	vbox.add_child(header)

	_add_separator(vbox)

	# Unequip option (send to storage)
	if has_equipped:
		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip to Storage"
		unequip_btn.add_theme_font_size_override("font_size", 11)
		unequip_btn.custom_minimum_size = Vector2(220, 26)
		unequip_btn.pressed.connect(_on_item_unequip.bind(commander, item_idx))
		vbox.add_child(unequip_btn)

		_add_separator(vbox)

	# Storage items list
	if has_storage:
		var storage_header := Label.new()
		storage_header.text = "Storage (%d)" % fs.item_storage.size()
		storage_header.add_theme_font_size_override("font_size", 11)
		storage_header.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		vbox.add_child(storage_header)

		for si in fs.item_storage.size():
			var storage_item_id: StringName = fs.item_storage[si]
			var storage_item_data = CommanderSystem.items.get(storage_item_id)
			var btn := Button.new()
			if storage_item_data:
				btn.text = storage_item_data.display_name
				match storage_item_data.rarity:
					&"legendary":
						btn.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2))
					&"rare":
						btn.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
			else:
				btn.text = str(storage_item_id)
			btn.add_theme_font_size_override("font_size", 11)
			btn.custom_minimum_size = Vector2(220, 26)
			btn.pressed.connect(_on_item_swap_from_storage.bind(commander, item_idx, si))
			vbox.add_child(btn)
	elif not has_equipped:
		var empty := Label.new()
		empty.text = "Storage is empty"
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		vbox.add_child(empty)

	# Position near the commander panel
	_item_swap_panel.position = Vector2(commander_panel.get_global_rect().end.x + 4, commander_panel.get_global_rect().position.y + 60)
	add_child(_item_swap_panel)

func _close_item_swap_panel() -> void:
	if _item_swap_panel:
		_item_swap_panel.queue_free()
		_item_swap_panel = null

func _on_item_unequip(commander: CommanderState, item_idx: int) -> void:
	if item_idx < commander.items.size():
		var item_id: StringName = commander.items[item_idx]
		var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
		if fs:
			fs.item_storage.append(item_id)
		commander.items.remove_at(item_idx)
	_close_item_swap_panel()
	_refresh_commander_panel()

func _on_item_swap_from_storage(commander: CommanderState, item_idx: int, storage_idx: int) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
	if fs == null or storage_idx >= fs.item_storage.size():
		_close_item_swap_panel()
		return

	var storage_item_id: StringName = fs.item_storage[storage_idx]
	fs.item_storage.remove_at(storage_idx)

	if item_idx >= 0 and item_idx < commander.items.size():
		# Swap: put equipped item into storage, equip storage item
		var old_item_id: StringName = commander.items[item_idx]
		commander.items[item_idx] = storage_item_id
		fs.item_storage.append(old_item_id)
	else:
		# Equip into empty slot
		commander.items.append(storage_item_id)

	_close_item_swap_panel()
	_refresh_commander_panel()

func _show_follower_assign_panel(commander: CommanderState, army_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
	if fs == null or fs.follower_storage.is_empty():
		return

	_close_item_swap_panel()

	_item_swap_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.97)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	_item_swap_panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_swap_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header_row := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "Assign Follower"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header_row.add_child(title_lbl)
	header_row.add_child(_make_close_button(_close_item_swap_panel, Vector2(24, 24)))
	vbox.add_child(header_row)

	_add_separator(vbox)

	# Build a snapshot of follower IDs to avoid index-shift issues
	var storage_snapshot: Array[StringName] = []
	for fi in fs.follower_storage.size():
		storage_snapshot.append(StringName(fs.follower_storage[fi]))

	for fi in storage_snapshot.size():
		var fid: StringName = storage_snapshot[fi]
		var fdata: FollowerData = DataManager.get_follower(fid)
		var btn := Button.new()
		btn.text = fdata.display_name if fdata else str(fid).replace("_", " ").capitalize()
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(240, 26)
		var captured_fid := fid
		var captured_cmd := commander
		var captured_aid := army_id
		btn.pressed.connect(func():
			var f_fs: FactionState = GameManager.state.faction_states.get(captured_cmd.faction_id)
			if f_fs:
				var idx := f_fs.follower_storage.find(captured_fid)
				if idx >= 0:
					f_fs.follower_storage.remove_at(idx)
					captured_cmd.followers.append(captured_fid)
					# Clamp movement_remaining after follower malus changes max movement
					for a_id in GameManager.state.armies:
						var a: ArmyState = GameManager.state.armies[a_id]
						if a.commander == captured_cmd:
							var new_max := a.get_max_movement()
							a.movement_remaining = minf(a.movement_remaining, new_max)
					# Invalidate movement cache so reachable tiles refresh
					GameManager.movement_system._cache_valid = false
			_close_item_swap_panel()
			_refresh_commander_panel()
			# Re-emit army_selected so campaign refreshes reachable overlay
			if captured_aid != &"":
				EventBus.army_selected.emit(captured_aid)
		)
		vbox.add_child(btn)
		# Show bonus/malus preview
		if fdata:
			for eff_key in fdata.bonus_effect:
				var eff_lbl := Label.new()
				eff_lbl.text = "  +%s %s" % [str(fdata.bonus_effect[eff_key]), eff_key.replace("_", " ").capitalize()]
				eff_lbl.add_theme_font_size_override("font_size", 10)
				eff_lbl.add_theme_color_override("font_color", Color(0.4, 0.75, 0.4))
				vbox.add_child(eff_lbl)
			for eff_key in fdata.malus_effect:
				var eff_lbl := Label.new()
				eff_lbl.text = "  %s %s" % [str(fdata.malus_effect[eff_key]), eff_key.replace("_", " ").capitalize()]
				eff_lbl.add_theme_font_size_override("font_size", 10)
				eff_lbl.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
				vbox.add_child(eff_lbl)

	_item_swap_panel.position = Vector2(commander_panel.get_global_rect().end.x + 4, commander_panel.get_global_rect().position.y + 60)
	add_child(_item_swap_panel)

func _hide_commander_panel() -> void:
	_close_item_swap_panel()
	if commander_panel:
		commander_panel.visible = false

# ── Settlement Founding UI ────────────────────────────────────

signal settlement_placement_requested(city_id: StringName)
signal settlement_placement_cancelled()
signal building_tile_selection_requested(city_id: StringName, building_id: StringName, valid_tiles: Array)
signal building_tile_selection_cancelled()
signal building_queued()

func _on_found_settlement_pressed(city_id: StringName) -> void:
	settlement_placement_requested.emit(city_id)

# ── Level-Up Dialog ──────────────────────────────────────────

func _on_commander_level_up(commander: CommanderState) -> void:
	# Only show dialog for player commanders
	if commander.faction_id != GameManager.state.player_faction_id:
		CommanderSystem.ai_auto_pick_major_skill(commander)
		return
	_pending_level_up_commander = commander
	_show_level_up_dialog(commander)

func _show_level_up_dialog(commander: CommanderState) -> void:
	if _level_up_dialog:
		_level_up_dialog.queue_free()

	_level_up_dialog = _create_centered_dialog(350, 280)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_level_up_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "Commander Level Up!"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info := Label.new()
	info.text = "%s reached Level %d!" % [commander.name, commander.level]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	_add_separator(vbox)

	# Skill choices
	var choices = CommanderSystem.get_major_skill_choices(commander)
	if choices.size() > 0:
		var choose_label := Label.new()
		choose_label.text = "Choose a skill:"
		choose_label.add_theme_font_size_override("font_size", 13)
		choose_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(choose_label)

		for choice in choices:
			var skill_data = CommanderSystem.skills.get(choice.skill_id)
			if skill_data == null:
				continue
			var btn := Button.new()
			if choice.is_levelup:
				var cur_lv: int = choice.current_level
				btn.text = "%s Lv.%d -> Lv.%d" % [skill_data.display_name, cur_lv, cur_lv + 1]
			else:
				btn.text = "%s (NEW) - %s" % [skill_data.display_name, skill_data.description]
			btn.tooltip_text = _format_skill_tooltip(skill_data, choice.is_levelup, choice.current_level)
			btn.custom_minimum_size = Vector2(300, 36)
			btn.pressed.connect(_on_major_skill_chosen.bind(choice.skill_id))
			vbox.add_child(btn)
	else:
		var no_skills := Label.new()
		no_skills.text = "No skills available"
		no_skills.add_theme_font_size_override("font_size", 12)
		no_skills.add_theme_color_override("font_color", Color(0.55, 0.5, 0.45))
		vbox.add_child(no_skills)

		var ok_btn := Button.new()
		ok_btn.text = "Continue"
		ok_btn.custom_minimum_size = Vector2(120, 32)
		ok_btn.pressed.connect(_on_level_up_dismiss)
		var btn_container := HBoxContainer.new()
		btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_container.add_child(ok_btn)
		vbox.add_child(btn_container)

	add_child(_level_up_dialog)

const EFFECT_DISPLAY_NAMES := {
	"army_attack_bonus": "Army Attack",
	"army_defense_bonus": "Army Defense",
	"army_speed_bonus": "Army Speed",
	"army_movement_bonus": "Army Movement",
	"heal_per_turn": "HP Healing/Turn",
	"city_gold_bonus": "City Gold Income",
	"city_growth_bonus": "City Growth",
	"city_defense_bonus": "City Defense",
	"recruit_speed_bonus": "Recruit Speed",
	"scouting_bonus": "Scouting Range",
	"enemy_city_growth_penalty": "Enemy City Growth",
	"enemy_army_morale_penalty": "Enemy Army Morale",
	"loyalty_aura": "Loyalty Aura",
	"charge_damage_mult": "Charge Damage",
	"retreat_morale_threshold": "Rout Threshold",
	"captive_chance_mod": "Captive Chance",
	"morale_recovery_mult": "Morale Recovery",
	"ambush_attack_bonus": "Ambush Attack",
	"unit_morale_bonus": "Unit Morale",
	"xp_gain_mult": "XP Gain",
	"upkeep_mult": "Army Upkeep",
}

func _format_effect_name(key: String) -> String:
	if EFFECT_DISPLAY_NAMES.has(key):
		return EFFECT_DISPLAY_NAMES[key]
	# Parse dynamic keys like "vs_monster_attack_bonus" or "cavalry_defense_bonus"
	var name := key.replace("_", " ").capitalize()
	if key.begins_with("vs_"):
		name = name.replace("Vs ", "vs ")
	return name

func _format_skill_tooltip(skill_data: CommanderSkill, is_levelup: bool, current_level: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if is_levelup:
		lines.append("%s (Level %d -> %d)" % [skill_data.display_name, current_level, current_level + 1])
	else:
		lines.append("%s (NEW)" % skill_data.display_name)
	lines.append(skill_data.description)
	lines.append("──────────────────")
	if skill_data.effects.is_empty():
		lines.append("No stat effects.")
	else:
		lines.append("Per Level:")
		for key in skill_data.effects:
			var val = skill_data.effects[key]
			var prefix: String = "+" if val >= 0 else ""
			lines.append("  %s%s %s" % [prefix, str(val), _format_effect_name(key)])
		if is_levelup:
			lines.append("")
			lines.append("At Level %d:" % (current_level + 1))
			for key in skill_data.effects:
				var val = skill_data.effects[key] * (current_level + 1)
				var prefix: String = "+" if val >= 0 else ""
				lines.append("  %s%s %s (total)" % [prefix, str(val), _format_effect_name(key)])
	if not skill_data.category.is_empty():
		lines.append("")
		lines.append("Category: %s" % str(skill_data.category).capitalize())
	return "\n".join(lines)

func _on_major_skill_chosen(skill_id: StringName) -> void:
	if _pending_level_up_commander:
		CommanderSystem.choose_major_skill(_pending_level_up_commander, skill_id)
		_pending_level_up_commander = null
	if _level_up_dialog:
		_level_up_dialog.queue_free()
		_level_up_dialog = null
	_refresh_commander_panel()

func _on_level_up_dismiss() -> void:
	_pending_level_up_commander = null
	if _level_up_dialog:
		_level_up_dialog.queue_free()
		_level_up_dialog = null
	_refresh_commander_panel()

func _on_commander_trait_changed(commander: CommanderState, action: String, trait_id: StringName) -> void:
	if commander.faction_id != GameManager.state.player_faction_id:
		return
	var trait_data: CommanderTrait = CommanderSystem.traits_db.get(trait_id)
	var trait_name: String = trait_data.display_name if trait_data else str(trait_id)
	var msg: String
	var color: Color
	if action == "gained" and trait_data and trait_data.is_positive:
		msg = "%s gained trait: %s — %s" % [commander.name, trait_name, trait_data.description]
		color = Color(0.5, 0.85, 0.45)
	elif action == "gained":
		msg = "%s developed: %s — %s" % [commander.name, trait_name, trait_data.description if trait_data else ""]
		color = Color(0.9, 0.45, 0.35)
	else:
		msg = "%s overcame: %s" % [commander.name, trait_name]
		color = Color(0.95, 0.88, 0.4)
	_show_trait_notification(msg, color)
	_refresh_commander_panel()

func _show_trait_notification(msg: String, color: Color) -> void:
	var notif := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	style.border_color = color * 0.7
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	notif.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(350, 0)
	notif.add_child(label)
	notif.position = Vector2(get_viewport_rect().size.x / 2.0 - 175, 80)
	add_child(notif)
	# Auto-dismiss after 4 seconds
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func(): if is_instance_valid(notif): notif.queue_free())

func _refresh_commander_panel() -> void:
	var army_id: StringName = GameManager.state.selected_army_id if GameManager.state else &""
	if army_id == &"":
		return
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army and army.commander and commander_panel.visible:
		_update_commander_panel(army)

# ── Item Drop Dialog ─────────────────────────────────────────

func _on_commander_item_full(commander: CommanderState, new_item) -> void:
	if commander.faction_id != GameManager.state.player_faction_id:
		return
	_show_item_drop_dialog(commander, new_item)

func _show_item_drop_dialog(commander: CommanderState, new_item) -> void:
	if _item_drop_dialog:
		_item_drop_dialog.queue_free()

	_item_drop_dialog = _create_centered_dialog(320, 260)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_item_drop_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "Item Found!"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var item_name := Label.new()
	item_name.text = new_item.display_name
	item_name.add_theme_font_size_override("font_size", 15)
	match new_item.rarity:
		&"legendary":
			item_name.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2))
		&"rare":
			item_name.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
		_:
			item_name.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(item_name)

	var desc := Label.new()
	desc.text = new_item.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	var replace_label := Label.new()
	replace_label.text = "Inventory full! Replace which item?"
	replace_label.add_theme_font_size_override("font_size", 13)
	replace_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(replace_label)

	for i in commander.items.size():
		var old_item_data = CommanderSystem.items.get(commander.items[i])
		var old_name: String = old_item_data.display_name if old_item_data else str(commander.items[i])
		var btn := Button.new()
		btn.text = "Replace: " + old_name
		btn.custom_minimum_size = Vector2(260, 30)
		btn.pressed.connect(_on_item_replace.bind(commander, i, new_item.id))
		vbox.add_child(btn)

	var storage_btn := Button.new()
	storage_btn.text = "Send to Storage"
	storage_btn.custom_minimum_size = Vector2(260, 30)
	storage_btn.pressed.connect(_on_item_to_storage.bind(commander, new_item.id))
	vbox.add_child(storage_btn)

	add_child(_item_drop_dialog)

func _on_item_replace(commander: CommanderState, slot_index: int, new_item_id: StringName) -> void:
	if slot_index < commander.items.size():
		# Send replaced item to faction storage
		var old_item_id: StringName = commander.items[slot_index]
		var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
		if fs:
			fs.item_storage.append(old_item_id)
		commander.items[slot_index] = new_item_id
	if _item_drop_dialog:
		_item_drop_dialog.queue_free()
		_item_drop_dialog = null
	_refresh_commander_panel()

func _on_item_to_storage(commander: CommanderState, item_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
	if fs:
		fs.item_storage.append(item_id)
	if _item_drop_dialog:
		_item_drop_dialog.queue_free()
		_item_drop_dialog = null
	_refresh_commander_panel()

# ── Random Event Dialog ──────────────────────────────────────

func _on_random_event_triggered(event_data: Dictionary) -> void:
	_pending_event_data = event_data
	_show_event_dialog(event_data)

func _show_event_dialog(event_data: Dictionary) -> void:
	if _event_dialog:
		_event_dialog.queue_free()

	_event_dialog = _create_centered_dialog(400, 260)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_event_dialog.add_child(vbox)

	var title := Label.new()
	title.text = event_data.get("title", "Event")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_separator(vbox)

	var desc := Label.new()
	desc.text = event_data.get("text", "")
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	# Choice A button
	var choice_a_text: String = event_data.get("choice_a", "Accept")
	var btn_a := Button.new()
	btn_a.text = choice_a_text
	btn_a.custom_minimum_size = Vector2(340, 36)
	btn_a.pressed.connect(_on_event_choice.bind("a"))
	vbox.add_child(btn_a)

	# Choice B button
	var choice_b_text: String = event_data.get("choice_b", "Decline")
	var btn_b := Button.new()
	btn_b.text = choice_b_text
	btn_b.custom_minimum_size = Vector2(340, 36)
	btn_b.pressed.connect(_on_event_choice.bind("b"))
	vbox.add_child(btn_b)

	add_child(_event_dialog)

func _on_event_choice(choice: String) -> void:
	var event_type: String = _pending_event_data.get("type", "")
	# Confirm when declining a commander
	if choice == "b" and event_type == "legendary_commander":
		_show_decline_commander_confirm()
		return
	_apply_event_choice(choice)

func _show_decline_commander_confirm() -> void:
	var confirm := _create_centered_dialog(340, 160)
	confirm.z_index = 60
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	confirm.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Are you sure you want to turn away this commander?"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = "Yes, decline"
	yes_btn.custom_minimum_size = Vector2(120, 32)
	yes_btn.pressed.connect(func():
		confirm.queue_free()
		_apply_event_choice("b")
	)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Go back"
	no_btn.custom_minimum_size = Vector2(120, 32)
	no_btn.pressed.connect(func(): confirm.queue_free())
	btn_row.add_child(no_btn)

	add_child(confirm)

func _apply_event_choice(choice: String) -> void:
	var event_title: String = _pending_event_data.get("title", "Event")
	var result := TurnManager.apply_random_event_choice(_pending_event_data, choice)
	if _event_dialog:
		_event_dialog.queue_free()
		_event_dialog = null
	_pending_event_data = {}
	_update_resource_display()
	_refresh_commander_panel()
	if result != "":
		_show_event_result(event_title, result)

func _show_event_result(event_title: String, result_text: String) -> void:
	var dialog := _create_centered_dialog(380, 180)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	var title := Label.new()
	title.text = event_title + " - Result"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_separator(vbox)

	var result_label := Label.new()
	result_label.text = result_text
	result_label.add_theme_font_size_override("font_size", 13)
	result_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(result_label)

	_add_separator(vbox)

	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(100, 32)
	ok_btn.pressed.connect(func(): dialog.queue_free())
	btn_container.add_child(ok_btn)
	vbox.add_child(btn_container)

	add_child(dialog)

# ── AI Diplomacy Offer Dialog ──────────────────────────────

func _show_ai_diplomacy_offer(from_faction: StringName, offer_type: StringName, _offer_data: Dictionary) -> void:
	if _ai_offer_dialog:
		_ai_offer_dialog.queue_free()

	var fd: FactionData = DataManager.get_faction(from_faction)
	var faction_name: String = fd.display_name if fd else str(from_faction)

	_ai_offer_dialog = _create_centered_dialog(420, 260)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_ai_offer_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "%s sends an envoy" % faction_name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_separator(vbox)

	var body_text: String
	match offer_type:
		&"peace":
			body_text = "%s proposes a peace treaty to end the war." % faction_name
		&"non_aggression":
			body_text = "%s proposes a non-aggression pact." % faction_name
		&"trade_relations":
			body_text = "%s proposes establishing trade relations." % faction_name
		&"alliance":
			body_text = "%s proposes a formal alliance against common enemies." % faction_name
		&"free_passage":
			body_text = "%s requests free passage through your territory." % faction_name
		_:
			body_text = "%s sends a diplomatic envoy." % faction_name

	var desc := Label.new()
	desc.text = body_text
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(140, 36)
	accept_btn.pressed.connect(_on_ai_offer_response.bind(from_faction, offer_type, true))
	btn_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(140, 36)
	decline_btn.pressed.connect(_on_ai_offer_response.bind(from_faction, offer_type, false))
	btn_row.add_child(decline_btn)

	add_child(_ai_offer_dialog)

func _on_ai_offer_response(from_faction: StringName, offer_type: StringName, accepted: bool) -> void:
	if _ai_offer_dialog:
		_ai_offer_dialog.queue_free()
		_ai_offer_dialog = null

	var player_id := GameManager.state.player_faction_id
	var fd: FactionData = DataManager.get_faction(from_faction)
	var faction_name: String = fd.display_name if fd else str(from_faction)
	var result_text := ""

	if accepted:
		# force_accept=true: the AI made this offer, so skip re-evaluation
		match offer_type:
			&"peace":
				var res := GameManager.diplomacy_system.propose_peace(from_faction, player_id, true)
				result_text = "Peace with %s." % faction_name if res.accepted else res.reason
			&"non_aggression":
				var res := GameManager.diplomacy_system.propose_non_aggression(from_faction, player_id, true)
				result_text = "Non-aggression pact with %s signed." % faction_name if res.accepted else res.reason
			&"trade_relations":
				var res := GameManager.diplomacy_system.propose_trade_relations(from_faction, player_id, true)
				result_text = "Trade relations with %s established." % faction_name if res.accepted else res.reason
			&"alliance":
				var res := GameManager.diplomacy_system.propose_alliance(from_faction, player_id, true)
				result_text = "Alliance with %s formed!" % faction_name if res.accepted else res.reason
			&"free_passage":
				var res := GameManager.diplomacy_system.propose_free_passage(from_faction, player_id, true)
				result_text = "Free passage with %s granted." % faction_name if res.accepted else res.reason
	else:
		GameManager.diplomacy_system.modify_standing(from_faction, player_id, -3, "Diplomatic offer declined")
		result_text = "You declined %s's offer." % faction_name

	_update_resource_display()
	if result_text != "":
		_show_event_result("Diplomacy", result_text)

# ── Skulloath Siege Choice ──────────────────────────────────

var _siege_choice_dialog: PanelContainer

func _on_siege_choice_needed(city_id: StringName, _faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return
	_show_siege_choice_dialog(city)

func _show_siege_choice_dialog(city: CityState) -> void:
	if _siege_choice_dialog:
		_siege_choice_dialog.queue_free()

	_siege_choice_dialog = _create_centered_dialog(460, 340)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_siege_choice_dialog.add_child(vbox)

	var title := Label.new()
	title.text = city.get_display_name() + " Has Fallen!"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_separator(vbox)

	var desc := Label.new()
	desc.text = "The siege is over. What shall we do with " + city.get_display_name() + "?"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	_add_separator(vbox)

	# Option 1: Capture
	var btn_capture := Button.new()
	btn_capture.text = "Conquer - Take the city as your own"
	btn_capture.custom_minimum_size = Vector2(420, 36)
	btn_capture.pressed.connect(_on_siege_choice.bind(city.city_id, "capture"))
	vbox.add_child(btn_capture)

	# Option 2: Loot
	var loot_mult: float = 1.0 + city.level * 0.3
	var gold_est: int = int(60 * loot_mult)
	var wood_est: int = int(45 * loot_mult)
	var iron_est: int = int(25 * loot_mult)
	var food_est: int = int(35 * loot_mult)
	var btn_loot := Button.new()
	btn_loot.text = "Loot - Plunder for ~%d Gold, ~%d Wood, ~%d Iron, ~%d Food" % [gold_est, wood_est, iron_est, food_est]
	btn_loot.custom_minimum_size = Vector2(420, 36)
	btn_loot.pressed.connect(_on_siege_choice.bind(city.city_id, "loot"))
	vbox.add_child(btn_loot)

	var loot_note := Label.new()
	loot_note.text = "  City stays with enemy. Small diplomacy penalty."
	loot_note.add_theme_font_size_override("font_size", 11)
	loot_note.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	vbox.add_child(loot_note)

	# Option 3: Raze
	var btn_raze := Button.new()
	btn_raze.text = "Raze - Burn it down: downgrade all buildings"
	btn_raze.custom_minimum_size = Vector2(420, 36)
	btn_raze.pressed.connect(_on_siege_choice.bind(city.city_id, "raze"))
	vbox.add_child(btn_raze)

	var raze_note := Label.new()
	raze_note.text = "  All tier 1 buildings destroyed, higher tiers downgraded. Major diplomacy penalty."
	raze_note.add_theme_font_size_override("font_size", 11)
	raze_note.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
	vbox.add_child(raze_note)

	add_child(_siege_choice_dialog)

func _on_siege_choice(city_id: StringName, choice: String) -> void:
	if _siege_choice_dialog:
		_siege_choice_dialog.queue_free()
		_siege_choice_dialog = null

	var result_title := ""
	var result_text := ""

	match choice:
		"capture":
			GameManager.city_system.apply_siege_choice_capture(city_id)
			var city: CityState = GameManager.state.cities.get(city_id)
			result_title = "City Conquered"
			result_text = city.get_display_name() + " is now under your control." if city else "City captured."
		"loot":
			var loot: Dictionary = GameManager.city_system.apply_siege_choice_loot(city_id)
			result_title = "City Plundered"
			result_text = "Your warriors return laden with spoils:\n+%d Gold, +%d Wood, +%d Iron, +%d Food\nThe city remains with its people, broken and bitter." % [
				loot.get("gold", 0), loot.get("wood", 0), loot.get("iron", 0), loot.get("food", 0)]
		"raze":
			var raze: Dictionary = GameManager.city_system.apply_siege_choice_raze(city_id)
			result_title = "City Razed"
			var parts: Array[String] = []
			if raze.get("destroyed", 0) > 0:
				parts.append("%d buildings destroyed" % raze["destroyed"])
			if raze.get("downgraded", 0) > 0:
				parts.append("%d buildings downgraded" % raze["downgraded"])
			if parts.is_empty():
				parts.append("The city had nothing left to burn")
			result_text = "Flames consume the city.\n" + ", ".join(parts) + ".\n+%d Gold, +%d Wood salvaged from the ruins." % [
				raze.get("gold", 0), raze.get("wood", 0)]

	_update_resource_display()
	_show_event_result(result_title, result_text)

# ── Region Overview Panel ────────────────────────────────────

func _show_region_overview(region_id: StringName) -> void:
	if _region_overview_panel:
		_region_overview_panel.queue_free()

	var region: RegionData = DataManager.get_region(region_id)
	if region == null:
		return

	_region_overview_panel = _create_centered_dialog(380, 350)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_region_overview_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Header with close button
	var _close_region := func():
		if _region_overview_panel:
			_region_overview_panel.queue_free()
			_region_overview_panel = null
	_create_panel_header(vbox, region.display_name, _region_overview_panel, _close_region, 18)

	# Owner faction
	var hex_map := GameManager.state.hex_map
	var owner_faction_id: StringName = &""
	if hex_map:
		for coord in hex_map.tiles:
			var tile: HexMapData.TileState = hex_map.tiles[coord]
			if tile.region_id == region_id and tile.owner_faction != &"":
				owner_faction_id = tile.owner_faction
				break
	var owner_label := Label.new()
	if owner_faction_id != &"":
		var faction := DataManager.get_faction(owner_faction_id)
		owner_label.text = "Owner: " + (faction.display_name if faction else str(owner_faction_id))
		owner_label.add_theme_color_override("font_color", faction.color.lightened(0.3) if faction else Color(0.78, 0.75, 0.68))
	else:
		owner_label.text = "Owner: Neutral"
		owner_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
	owner_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(owner_label)

	_add_separator(vbox)

	# Cities/settlements in this region
	var cities_header := Label.new()
	cities_header.text = "Cities & Settlements"
	cities_header.add_theme_font_size_override("font_size", 14)
	cities_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(cities_header)

	var region_cities_found := false
	var total_income: Dictionary = {}
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id != region_id:
			continue
		region_cities_found = true
		var city_label := Label.new()
		var suffix := " (Capital)" if city.is_capital else ""
		city_label.text = "  %s%s - Level %d, Pop: %d" % [city.get_display_name(), suffix, city.level, city.population]
		city_label.add_theme_font_size_override("font_size", 12)
		city_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(city_label)
		# Sum income
		var city_income := GameManager.city_system.calculate_city_income(city)
		for res in city_income:
			total_income[res] = total_income.get(res, 0) + city_income[res]

	if not region_cities_found:
		var no_cities := Label.new()
		no_cities.text = "  (no cities)"
		no_cities.add_theme_font_size_override("font_size", 12)
		no_cities.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		vbox.add_child(no_cities)

	_add_separator(vbox)

	# Units stationed in region
	var units_header := Label.new()
	units_header.text = "Armies in Region"
	units_header.add_theme_font_size_override("font_size", 14)
	units_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(units_header)

	var army_found := false
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if not hex_map:
			continue
		var tile := hex_map.get_tile(army.hex_pos)
		if tile == null or tile.region_id != region_id:
			continue
		army_found = true
		var faction: FactionData = DataManager.get_faction(army.faction_id)
		var fname: String = faction.display_name if faction else str(army.faction_id)
		var army_label := Label.new()
		army_label.text = "  %s - %d units" % [fname, army.units.size()]
		army_label.add_theme_font_size_override("font_size", 12)
		army_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		vbox.add_child(army_label)

	if not army_found:
		var no_armies := Label.new()
		no_armies.text = "  (none)"
		no_armies.add_theme_font_size_override("font_size", 12)
		no_armies.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		vbox.add_child(no_armies)

	_add_separator(vbox)

	# Income breakdown
	if total_income.size() > 0:
		var income_header := Label.new()
		income_header.text = "Total Region Income"
		income_header.add_theme_font_size_override("font_size", 14)
		income_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(income_header)
		for res_type in total_income:
			if total_income[res_type] > 0:
				var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
				var res_label := Label.new()
				res_label.text = "  +%d %s" % [total_income[res_type], rname]
				res_label.add_theme_font_size_override("font_size", 12)
				res_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
				vbox.add_child(res_label)

	add_child(_region_overview_panel)

# ── Dialog Helper ────────────────────────────────────────────

func _create_centered_dialog(width: int, height: int) -> PanelContainer:
	var dialog := PanelContainer.new()
	dialog.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	dialog.anchors_preset = Control.PRESET_CENTER
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -width / 2
	dialog.offset_top = -height / 2
	dialog.offset_right = width / 2
	dialog.offset_bottom = height / 2
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	return dialog

# ── Victory / Defeat ────────────────────────────────────────

func _on_game_over(faction_id: StringName, victory_type: int, is_player: bool) -> void:
	var dialog := _create_centered_dialog(500, 350)
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	dialog.add_child(vbox)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 14)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var faction_data: FactionData = DataManager.get_faction(faction_id)
	var faction_name: String = faction_data.display_name if faction_data else str(faction_id)

	var victory_names := {
		Enums.VictoryType.DOMINATION: "Domination Victory",
		Enums.VictoryType.DIPLOMATIC: "Diplomatic Victory",
		Enums.VictoryType.SHARD_ASCENSION: "Shard Ascension Victory",
		Enums.VictoryType.ELIMINATION: "Elimination Victory",
		Enums.VictoryType.DEFEAT: "Defeat",
	}
	var victory_descs := {
		Enums.VictoryType.DOMINATION: "%s has conquered over 60%% of the known world through military might.",
		Enums.VictoryType.DIPLOMATIC: "%s has forged a grand alliance, uniting the fractured lands through diplomacy.",
		Enums.VictoryType.SHARD_ASCENSION: "%s has collected enough shards to ascend beyond mortal power.",
		Enums.VictoryType.ELIMINATION: "%s is the last faction standing. All others have been destroyed.",
		Enums.VictoryType.DEFEAT: "Your faction has been eliminated. The fractured lands continue without you.",
	}

	if is_player and victory_type != Enums.VictoryType.DEFEAT:
		title.text = "VICTORY!"
		title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	elif is_player:
		title.text = "DEFEAT"
		title.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
	else:
		title.text = faction_name + " Wins!"
		title.add_theme_color_override("font_color", Color(0.7, 0.6, 0.4))

	var vtype_name: String = victory_names.get(victory_type, "Unknown")
	var vtype_desc: String = victory_descs.get(victory_type, "%s achieved victory.") % faction_name

	var type_label := Label.new()
	type_label.text = vtype_name
	type_label.add_theme_font_size_override("font_size", 16)
	type_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_label)

	desc.text = vtype_desc

	# Stats
	var stats_label := Label.new()
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var turns := GameManager.state.current_turn
	stats_label.text = "Turns Played: %d" % turns
	vbox.add_child(stats_label)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Menu"
	menu_btn.custom_minimum_size = Vector2(160, 36)
	menu_btn.pressed.connect(func():
		dialog.queue_free()
		GameManager.current_phase = Enums.GamePhase.MAIN_MENU
		GameManager.transition_to_scene("res://scenes/main/main_menu.tscn")
	)
	btn_row.add_child(menu_btn)

	var continue_btn := Button.new()
	continue_btn.text = "Continue Playing"
	continue_btn.custom_minimum_size = Vector2(160, 36)
	continue_btn.pressed.connect(func():
		GameManager.state.game_over = false
		dialog.queue_free()
	)
	btn_row.add_child(continue_btn)

# ── Elderbeast Panel ────────────────────────────────────────

var _elderbeast_panel: PanelContainer

# Terrain requirements for Shardhorde buildings (empty = no terrain requirement)
const BEAST_BUILDING_TERRAIN := {
	&"shard_conduit": [Enums.TerrainType.PLAINS, Enums.TerrainType.FOREST, Enums.TerrainType.JUNGLE, Enums.TerrainType.SWAMP],
	&"shard_harvester": [Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.DESERT, Enums.TerrainType.MOUNTAINS],
	&"crystal_forge": [Enums.TerrainType.MOUNTAINS, Enums.TerrainType.FOREST],
	&"resonance_core": [Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.DESERT],
	&"resonance_amplifier": [Enums.TerrainType.SHARD_WASTES],
}

func _get_beast_nearby_terrains(beast: ElderbeastState) -> Array[int]:
	var terrains: Array[int] = []
	var tiles := TurnManager._get_beast_tiles(beast)
	for tile_pos in tiles:
		var tile := GameManager.state.hex_map.get_tile(tile_pos)
		if tile and not terrains.has(tile.terrain):
			terrains.append(tile.terrain)
	return terrains

func _show_elderbeast_panel(beast: ElderbeastState) -> void:
	if _elderbeast_panel:
		_elderbeast_panel.queue_free()

	_elderbeast_panel = PanelContainer.new()
	_elderbeast_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	_elderbeast_panel.anchor_left = 1.0
	_elderbeast_panel.anchor_right = 1.0
	_elderbeast_panel.anchor_top = 0.15
	_elderbeast_panel.anchor_bottom = 1.0
	_elderbeast_panel.offset_left = -400
	_elderbeast_panel.offset_right = -8
	_elderbeast_panel.offset_top = 0
	_elderbeast_panel.offset_bottom = -40
	add_child(_elderbeast_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_elderbeast_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = beast.name + " (Lv." + str(beast.level) + ")"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.8, 0.55, 0.9))
	vbox.add_child(title)

	# HP
	var hp_label := Label.new()
	hp_label.text = "HP: %d / %d" % [beast.hp, beast.max_hp]
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	vbox.add_child(hp_label)

	# Population
	var pop_label := Label.new()
	pop_label.text = "Population: %d" % beast.population
	pop_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(pop_label)

	# Movement
	var move_label := Label.new()
	move_label.text = "Movement: %.1f / %.1f" % [beast.movement_remaining, beast.get_max_movement()]
	move_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(move_label)

	# Injured status
	if beast.is_injured():
		var injured_label := Label.new()
		injured_label.text = "INJURED - Stationary (%d turns remaining)" % beast.injured_turns
		injured_label.add_theme_font_size_override("font_size", 12)
		injured_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
		vbox.add_child(injured_label)

	# Buildings
	var bld_title := Label.new()
	bld_title.text = "Buildings (%d/%d):" % [beast.buildings.size(), beast.get_max_building_slots()]
	bld_title.add_theme_font_size_override("font_size", 13)
	bld_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(bld_title)

	const BUILDING_COMBAT_BONUS := {
		&"chitin_walls": "+8 Def",
		&"shard_conduit": "HP Regen",
		&"crystal_forge": "+10 Atk",
		&"crystal_nursery": "+60 HP",
		&"shard_harvester": "+Fear",
		&"resonance_core": "Ranged Atk",
		&"hive_spire": "+Morale Aura",
		&"resonance_amplifier": "Shard Aura",
		&"elder_breeding_ground": "Spawns Units",
	}
	for building_id in beast.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		var b_name: String = building.display_name if building else str(building_id)
		var bonus: String = BUILDING_COMBAT_BONUS.get(building_id, "")
		var bld_label := Label.new()
		bld_label.text = "  %s%s" % [b_name, " [%s]" % bonus if bonus != "" else ""]
		bld_label.add_theme_font_size_override("font_size", 11)
		bld_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		bld_label.mouse_filter = Control.MOUSE_FILTER_STOP
		bld_label.mouse_entered.connect(_on_building_hover.bind(building_id))
		bld_label.mouse_exited.connect(_on_building_hover_exit)
		var _captured_bid: StringName = building_id
		bld_label.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_building_detail(_captured_bid, &"")
		)
		vbox.add_child(bld_label)

	# Build queue
	if beast.build_queue.size() > 0:
		var queue_label := Label.new()
		var item: Dictionary = beast.build_queue[0]
		var bld: BuildingData = DataManager.get_building(item.get("building_id", &""))
		queue_label.text = "Building: %s (%d turns)" % [bld.display_name if bld else "?", item.get("turns_remaining", 0)]
		queue_label.add_theme_font_size_override("font_size", 11)
		queue_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
		vbox.add_child(queue_label)

	# Available buildings (inline like city panel)
	if beast.get_available_building_slots() > 0 and beast.build_queue.is_empty():
		var nearby_terrains := _get_beast_nearby_terrains(beast)
		var beast_fs: FactionState = GameManager.state.faction_states.get(beast.faction_id)
		var any_available := false
		for bid in DataManager.buildings:
			var avail_building: BuildingData = DataManager.buildings[bid]
			if avail_building.faction_id != &"shardhorde":
				continue
			if beast.buildings.has(bid):
				continue
			if avail_building.required_capital_level > beast.level:
				continue
			if avail_building.upgrades_from != &"" and not beast.buildings.has(avail_building.upgrades_from):
				continue
			var terrain_req: Array = BEAST_BUILDING_TERRAIN.get(bid, [])
			if terrain_req.size() > 0:
				var terrain_ok := false
				for t in terrain_req:
					if nearby_terrains.has(t):
						terrain_ok = true
						break
				if not terrain_ok:
					continue

			if not any_available:
				any_available = true
				var avail_header := Label.new()
				avail_header.text = "Available Buildings"
				avail_header.add_theme_font_size_override("font_size", 13)
				avail_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
				vbox.add_child(avail_header)

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)
			var build_btn := Button.new()
			if avail_building.upgrades_from != &"":
				build_btn.text = "\u25B2 " + avail_building.display_name
			else:
				build_btn.text = avail_building.display_name
			build_btn.custom_minimum_size = Vector2(140, 28)
			# Category color
			var cat_color: Color
			match avail_building.category:
				&"economic":
					var is_industrial := false
					for res in avail_building.income_bonus:
						if res == Enums.ResourceType.IRON or res == Enums.ResourceType.WOOD:
							is_industrial = true
							break
					cat_color = Color(0.85, 0.72, 0.3, 0.25) if is_industrial else Color(0.35, 0.7, 0.3, 0.25)
				&"military":
					cat_color = Color(0.75, 0.25, 0.2, 0.25)
				&"defensive":
					cat_color = Color(0.35, 0.55, 0.75, 0.25)
				&"cultural":
					cat_color = Color(0.55, 0.35, 0.75, 0.25)
				_:
					cat_color = Color(0.4, 0.4, 0.4, 0.2)
			var cat_style := StyleBoxFlat.new()
			cat_style.bg_color = cat_color
			cat_style.border_color = Color(cat_color, 0.6)
			cat_style.set_border_width_all(1)
			cat_style.set_corner_radius_all(3)
			cat_style.set_content_margin_all(4)
			build_btn.add_theme_stylebox_override("normal", cat_style)
			var cat_hover := cat_style.duplicate()
			cat_hover.bg_color = Color(cat_color, 0.4)
			build_btn.add_theme_stylebox_override("hover", cat_hover)
			var cat_pressed := cat_style.duplicate()
			cat_pressed.bg_color = Color(cat_color, 0.5)
			build_btn.add_theme_stylebox_override("pressed", cat_pressed)
			var cat_disabled := cat_style.duplicate()
			cat_disabled.bg_color = Color(cat_color, 0.1)
			build_btn.add_theme_stylebox_override("disabled", cat_disabled)
			# Affordability
			if beast_fs and not _can_afford_display(beast_fs, avail_building.build_cost):
				build_btn.disabled = true
			# Left-click: start building
			var captured_id: StringName = bid
			var captured_time: int = avail_building.build_time
			var captured_cost: Dictionary = avail_building.build_cost.duplicate()
			var captured_beast: ElderbeastState = beast
			build_btn.pressed.connect(func():
				if beast_fs:
					for res_type in captured_cost:
						beast_fs.resources[res_type] = beast_fs.resources.get(res_type, 0) - captured_cost[res_type]
				captured_beast.build_queue.append({building_id = captured_id, turns_remaining = captured_time})
				_show_elderbeast_panel(captured_beast)
				_update_resource_display()
			)
			# Hover tooltip
			build_btn.mouse_entered.connect(_on_building_hover.bind(bid))
			build_btn.mouse_exited.connect(_on_building_hover_exit)
			# Right-click detail
			var rc_bid: StringName = bid
			build_btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_show_building_detail(rc_bid, &"")
			)
			btn_row.add_child(build_btn)
			var cost_label := Label.new()
			cost_label.text = _format_cost(avail_building.build_cost) + " | " + str(avail_building.build_time) + " turn(s)"
			cost_label.add_theme_font_size_override("font_size", 11)
			cost_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
			btn_row.add_child(cost_label)
			vbox.add_child(btn_row)

	# Recruitment
	_add_separator(vbox)
	var recruit_title := Label.new()
	recruit_title.text = "Recruitment"
	recruit_title.add_theme_font_size_override("font_size", 13)
	recruit_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(recruit_title)

	# Collect available units from built buildings
	var available_units: Array[StringName] = []
	for b_id in beast.buildings:
		var b_data: BuildingData = DataManager.get_building(b_id)
		if b_data == null:
			continue
		for uid in b_data.unlocks_units:
			if not available_units.has(uid):
				available_units.append(uid)

	var recruit_fs: FactionState = GameManager.state.faction_states.get(beast.faction_id)
	if available_units.size() > 0 and beast.recruit_queue.is_empty():
		for uid in available_units:
			var ud := DataManager.get_unit(uid)
			if ud == null:
				continue
			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)
			var recruit_btn := Button.new()
			recruit_btn.text = ud.display_name
			recruit_btn.custom_minimum_size = Vector2(140, 28)
			# Affordability
			if recruit_fs == null or not _can_afford_display(recruit_fs, ud.recruit_cost):
				recruit_btn.disabled = true
			# Left-click: start recruitment
			var captured_uid: StringName = uid
			var captured_time: int = ud.recruit_time
			var captured_cost: Dictionary = ud.recruit_cost.duplicate()
			var captured_beast: ElderbeastState = beast
			recruit_btn.pressed.connect(func():
				if recruit_fs:
					for res_type in captured_cost:
						recruit_fs.resources[res_type] = recruit_fs.resources.get(res_type, 0) - captured_cost[res_type]
				captured_beast.recruit_queue.append({unit_data_id = captured_uid, turns_remaining = captured_time})
				_show_elderbeast_panel(captured_beast)
				_update_resource_display()
			)
			# Hover unit card
			recruit_btn.mouse_entered.connect(_show_unit_card.bind(uid))
			recruit_btn.mouse_exited.connect(_hide_unit_card)
			# Right-click detail
			var rc_ud: UnitData = ud
			var rc_uid: StringName = uid
			recruit_btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					var dummy_unit := UnitInstance.new()
					dummy_unit.unit_data_id = rc_uid
					dummy_unit.current_hp = rc_ud.max_hp
					_show_unit_detail(dummy_unit, rc_ud)
			)
			btn_row.add_child(recruit_btn)
			var cost_label := Label.new()
			cost_label.text = _format_cost(ud.recruit_cost) + " | " + str(ud.recruit_time) + " turn(s)"
			cost_label.add_theme_font_size_override("font_size", 11)
			cost_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
			btn_row.add_child(cost_label)
			vbox.add_child(btn_row)
	elif available_units.is_empty():
		var no_units := Label.new()
		no_units.text = "  No units available yet"
		no_units.add_theme_font_size_override("font_size", 12)
		no_units.add_theme_color_override("font_color", Color(0.55, 0.5, 0.45))
		vbox.add_child(no_units)

	# Recruit queue
	if beast.recruit_queue.size() > 0:
		var rq_item: Dictionary = beast.recruit_queue[0]
		var rq_ud := DataManager.get_unit(rq_item.get("unit_data_id", &""))
		var rq_label := Label.new()
		rq_label.text = "  [Training] %s (%d turns)" % [rq_ud.display_name if rq_ud else "?", rq_item.get("turns_remaining", 0)]
		rq_label.add_theme_font_size_override("font_size", 11)
		rq_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		vbox.add_child(rq_label)

	# Income breakdown
	_add_separator(vbox)

	# Base income line
	var base_inc: Dictionary = TurnManager.ELDERBEAST_BASE_INCOME.get(beast.level, {})
	if not base_inc.is_empty():
		var base_parts: Array[String] = []
		for res_type in base_inc:
			if base_inc[res_type] > 0 and res_type < RESOURCE_NAMES.size():
				base_parts.append("+%d %s" % [base_inc[res_type], RESOURCE_NAMES[res_type]])
		var base_lbl := Label.new()
		base_lbl.text = "Base Income (Lv.%d): %s" % [beast.level, ", ".join(base_parts)]
		base_lbl.add_theme_font_size_override("font_size", 11)
		base_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.5))
		vbox.add_child(base_lbl)

	var terrain_title := Label.new()
	terrain_title.text = "Terrain Income:"
	terrain_title.add_theme_font_size_override("font_size", 13)
	terrain_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(terrain_title)

	var tiles := TurnManager._get_beast_tiles(beast)
	var max_depletion := 0
	# Group tiles by terrain type: terrain -> {count, total_yields, worst_depletion}
	var terrain_groups: Dictionary = {} # terrain_type -> {count, yields: {res->total}, worst_dep}
	for tile_pos in tiles:
		var tile := GameManager.state.hex_map.get_tile(tile_pos)
		if tile == null:
			continue
		var dep: int = beast.tile_depletion.get(tile_pos, 0)
		if dep > max_depletion:
			max_depletion = dep
		var mult: float = beast.get_depletion_multiplier(tile_pos)
		var yields: Dictionary = TurnManager.TERRAIN_INCOME.get(tile.terrain, {})
		if yields.is_empty():
			continue
		if not terrain_groups.has(tile.terrain):
			terrain_groups[tile.terrain] = {"count": 0, "yields": {}, "worst_dep": 0}
		var group: Dictionary = terrain_groups[tile.terrain]
		group["count"] += 1
		if dep > group["worst_dep"]:
			group["worst_dep"] = dep
		for res_type in yields:
			var val := maxi(1, roundi(yields[res_type] * mult))
			group["yields"][res_type] = group["yields"].get(res_type, 0) + val
	for terrain_type in terrain_groups:
		var group: Dictionary = terrain_groups[terrain_type]
		var t_name: String = TERRAIN_NAMES[terrain_type] if terrain_type < TERRAIN_NAMES.size() else "?"
		var count: int = group["count"]
		var parts: Array[String] = []
		for res_type in group["yields"]:
			var val: int = group["yields"][res_type]
			if val > 0 and res_type < RESOURCE_NAMES.size():
				parts.append("+%d %s" % [val, RESOURCE_NAMES[res_type]])
		if parts.size() > 0:
			var count_text := " x%d" % count if count > 1 else ""
			var t_lbl := Label.new()
			t_lbl.text = "  %s%s: %s" % [t_name, count_text, ", ".join(parts)]
			t_lbl.add_theme_font_size_override("font_size", 10)
			t_lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.45) if group["worst_dep"] < 3 else Color(0.8, 0.5, 0.3))
			vbox.add_child(t_lbl)

	# Depletion warning
	if max_depletion >= 3:
		var warn := Label.new()
		warn.text = "Resources depleting -- consider moving!"
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
		vbox.add_child(warn)

	# Total income
	var income := TurnManager._get_elderbeast_income(beast)
	var income_text := "Total Income: "
	var total_parts: Array[String] = []
	for res_type in income:
		if income[res_type] > 0 and res_type < RESOURCE_NAMES.size():
			total_parts.append("+%d %s" % [income[res_type], RESOURCE_NAMES[res_type]])
	income_text += ", ".join(total_parts) if total_parts.size() > 0 else "None"
	var income_label := Label.new()
	income_label.text = income_text
	income_label.add_theme_font_size_override("font_size", 11)
	income_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.5))
	vbox.add_child(income_label)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _elderbeast_panel.queue_free(); _elderbeast_panel = null)
	vbox.add_child(close_btn)

# ── Turn Summary Panel ───────────────────────────────────────

func _show_turn_summary() -> void:
	if _turn_summary_panel:
		_turn_summary_panel.queue_free()
	_turn_summary_panel = _create_centered_dialog(400, 320)
	add_child(_turn_summary_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_turn_summary_panel.add_child(vbox)

	var title := Label.new()
	title.text = "TURN %d SUMMARY" % GameManager.state.current_turn
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_add_separator(vbox)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var entries := VBoxContainer.new()
	entries.add_theme_constant_override("separation", 4)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(entries)

	var type_colors := {
		"battle": Color(0.85, 0.35, 0.35),
		"capture": Color(0.85, 0.65, 0.25),
		"shard": Color(0.65, 0.35, 0.85),
		"treaty": Color(0.35, 0.7, 0.9),
		"army": Color(0.7, 0.4, 0.35),
	}

	for entry in TurnManager.turn_log:
		var lbl := Label.new()
		lbl.text = "  " + entry.get("text", "")
		lbl.add_theme_font_size_override("font_size", 12)
		var etype: String = entry.get("type", "")
		lbl.add_theme_color_override("font_color", type_colors.get(etype, Color(0.75, 0.72, 0.65)))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entries.add_child(lbl)

	if TurnManager.turn_log.is_empty():
		var no_events := Label.new()
		no_events.text = "  Nothing notable happened."
		no_events.add_theme_font_size_override("font_size", 12)
		no_events.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
		entries.add_child(no_events)

	var dismiss := Button.new()
	dismiss.text = "Continue"
	dismiss.custom_minimum_size = Vector2(0, 32)
	dismiss.pressed.connect(func():
		_turn_summary_panel.queue_free()
		_turn_summary_panel = null
	)
	vbox.add_child(dismiss)

# ── Army Split Dialog ────────────────────────────────────────

func _show_army_split_dialog(army_id: StringName) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null or army.units.size() < 2:
		return

	var dialog := _create_centered_dialog(400, 400)
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var title := Label.new()
	title.text = "SPLIT ARMY"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info := Label.new()
	info.text = "Select units to split into a new army:"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
	vbox.add_child(info)

	_add_separator(vbox)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var check_list := VBoxContainer.new()
	check_list.add_theme_constant_override("separation", 4)
	check_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(check_list)

	var checkboxes: Array[CheckBox] = []
	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		var cb := CheckBox.new()
		cb.text = (ud.display_name if ud else str(unit.unit_data_id)) + " (HP: %d/%d)" % [unit.current_hp, ud.max_hp if ud else unit.current_hp]
		cb.add_theme_font_size_override("font_size", 12)
		check_list.add_child(cb)
		checkboxes.append(cb)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.text = "Split Selected"
	confirm.custom_minimum_size = Vector2(0, 32)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var captured_army_id := army_id
	confirm.pressed.connect(func():
		var selected_indices: Array[int] = []
		for i in checkboxes.size():
			if checkboxes[i].button_pressed:
				selected_indices.append(i)
		if selected_indices.size() == 0 or selected_indices.size() == army.units.size():
			return # Must select some but not all
		_execute_army_split(captured_army_id, selected_indices)
		dialog.queue_free()
	)
	btn_row.add_child(confirm)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 32)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_row.add_child(cancel_btn)

func _execute_army_split(army_id: StringName, unit_indices: Array[int]) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null:
		return
	# Create new army at same position
	var new_army := ArmyState.new()
	new_army.army_id = StringName("army_%d" % (GameManager.state.armies.size() + randi() % 1000))
	new_army.faction_id = army.faction_id
	new_army.hex_pos = army.hex_pos
	new_army.movement_remaining = 0.0

	# Move selected units (iterate in reverse to preserve indices)
	var units_to_move: Array[UnitInstance] = []
	var sorted_indices := unit_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		if idx >= 0 and idx < army.units.size():
			units_to_move.append(army.units[idx])
			army.units.remove_at(idx)
	units_to_move.reverse()
	new_army.units = units_to_move

	GameManager.state.armies[new_army.army_id] = new_army

	# Refresh the campaign scene markers
	var campaign: Node2D = get_parent().get_parent()
	if campaign and campaign.has_method("_create_army_marker"):
		campaign._create_army_marker(new_army)

	# Refresh the army panel
	_on_army_selected(army_id)

# ── Disband Units Dialog ─────────────────────────────────────

func _show_disband_dialog(army_id: StringName) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null or army.units.is_empty():
		return

	var dialog := _create_centered_dialog(400, 400)
	var vbox: VBoxContainer = dialog.get_node("VBox")

	var title := Label.new()
	title.text = "Disband Units"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info := Label.new()
	info.text = "Select units to permanently disband:"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
	vbox.add_child(info)

	_add_separator(vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var unit_list := VBoxContainer.new()
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_list)

	var checkboxes: Array[CheckBox] = []
	for unit in army.units:
		var ud: UnitData = DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var cb := CheckBox.new()
		var vet_label := unit.get_veterancy_label()
		var vet_str := " [%s]" % vet_label if vet_label != "Recruit" else ""
		cb.text = "%s%s (HP: %d/%d)" % [ud.display_name, vet_str, unit.current_hp, ud.hp * ud.squad_size]
		cb.add_theme_font_size_override("font_size", 11)
		cb.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
		unit_list.add_child(cb)
		checkboxes.append(cb)

	_add_separator(vbox)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.text = "Disband Selected"
	confirm.custom_minimum_size = Vector2(0, 32)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	var captured_army_id: StringName = army_id
	confirm.pressed.connect(func():
		var selected_indices: Array[int] = []
		for i in checkboxes.size():
			if checkboxes[i].button_pressed:
				selected_indices.append(i)
		if selected_indices.is_empty():
			return
		# Show confirmation dialog before actual disband
		_show_disband_confirmation(captured_army_id, selected_indices)
		dialog.queue_free()
	)
	btn_row.add_child(confirm)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 32)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_row.add_child(cancel_btn)

func _show_disband_confirmation(army_id: StringName, unit_indices: Array[int]) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null:
		return
	var count := unit_indices.size()
	var will_destroy_army := count >= army.units.size()

	var dialog := _create_centered_dialog(320, 160)
	var vbox: VBoxContainer = dialog.get_node("VBox")

	var warn := Label.new()
	warn.text = "Are you sure you want to disband %d unit%s?" % [count, "s" if count > 1 else ""]
	if will_destroy_army:
		warn.text += "\nThis will destroy the entire army!"
	warn.add_theme_font_size_override("font_size", 12)
	warn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(warn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.text = "Confirm Disband"
	confirm.custom_minimum_size = Vector2(0, 32)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	var captured_id: StringName = army_id
	confirm.pressed.connect(func():
		_execute_disband(captured_id, unit_indices)
		dialog.queue_free()
	)
	btn_row.add_child(confirm)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 32)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_row.add_child(cancel_btn)

func _execute_disband(army_id: StringName, unit_indices: Array[int]) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army == null:
		return
	# Remove selected units (iterate in reverse to preserve indices)
	var sorted_indices := unit_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for idx in sorted_indices:
		if idx >= 0 and idx < army.units.size():
			army.units.remove_at(idx)

	# If no units remain, destroy the army
	if army.units.is_empty():
		GameManager.remove_army(army_id)
		army_panel.visible = false
		# Refresh campaign markers
		var campaign: Node2D = get_parent().get_parent()
		if campaign and campaign.has_method("_create_army_markers"):
			campaign._create_army_markers()
	else:
		# Refresh the army panel
		_on_army_selected(army_id)

# ── Tutorial System ──────────────────────────────────────────

const TUTORIAL_HINTS := [
	{step = 0, text = "Welcome to FractureWars! Click on your army to select it.", trigger = "turn_start"},
	{step = 1, text = "Right-click a tile to move your army there.", trigger = "army_selected"},
	{step = 2, text = "Click on your city to manage buildings and recruitment.", trigger = "army_moved"},
	{step = 3, text = "Open the Research panel to start researching technologies.", trigger = "city_viewed"},
	{step = 4, text = "Open the Diplomacy panel to manage relations with other factions.", trigger = "research_viewed"},
	{step = 5, text = "Press End Turn when you're done. Good luck!", trigger = "diplomacy_viewed"},
]

func _check_tutorial(trigger: String) -> void:
	if GameManager.state == null or not GameManager.state.tutorial_enabled:
		return
	var step := GameManager.state.tutorial_step
	if step >= TUTORIAL_HINTS.size():
		return
	var hint: Dictionary = TUTORIAL_HINTS[step]
	if hint.trigger == trigger:
		_show_tutorial_hint(hint.text)
		GameManager.state.tutorial_step = step + 1

func _show_tutorial_hint(text: String) -> void:
	if _tutorial_overlay:
		_tutorial_overlay.queue_free()
	_tutorial_overlay = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.88)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.55, 0.2, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 12
	_tutorial_overlay.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_tutorial_overlay.add_child(vbox)

	var hint_label := Label.new()
	hint_label.text = text
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(350, 0)
	vbox.add_child(hint_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var got_it := Button.new()
	got_it.text = "Got it"
	got_it.custom_minimum_size = Vector2(80, 28)
	got_it.pressed.connect(func():
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	)
	btn_row.add_child(got_it)

	var skip := Button.new()
	skip.text = "Skip Tutorial"
	skip.custom_minimum_size = Vector2(100, 28)
	skip.pressed.connect(func():
		GameManager.state.tutorial_enabled = false
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	)
	btn_row.add_child(skip)

	# Position at top-center of screen
	_tutorial_overlay.anchors_preset = Control.PRESET_CENTER_TOP
	_tutorial_overlay.anchor_left = 0.5
	_tutorial_overlay.anchor_right = 0.5
	_tutorial_overlay.anchor_top = 0.0
	_tutorial_overlay.offset_left = -200
	_tutorial_overlay.offset_right = 200
	_tutorial_overlay.offset_top = 50
	add_child(_tutorial_overlay)

# ── Advisor Messages ─────────────────────────────────────────

func _check_advisor_messages() -> void:
	if GameManager.state == null:
		return
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return

	var messages: Array[String] = []

	# Check low loyalty cities
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != player_id:
			continue
		if city.loyalty < -25:
			messages.append("A city's loyalty is dangerously low!")
			break

	# Check if outnumbered
	var player_units := 0
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id:
			player_units += army.units.size()
	for faction_id in GameManager.state.faction_states:
		if faction_id == player_id:
			continue
		var enemy_units := 0
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == faction_id:
				enemy_units += army.units.size()
		if enemy_units > player_units and player_units > 0:
			messages.append("Your armies are outnumbered in the field.")
			break

	# Check for nearby shardfall
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if shard.claimed_by != &"":
			continue
		for army_id in GameManager.state.armies:
			var army: ArmyState = GameManager.state.armies[army_id]
			if army.faction_id == player_id:
				if HexHelper.hex_distance(army.hex_pos, shard.hex_pos) <= 5:
					messages.append("A shardfall has occurred nearby!")
					break
		if messages.size() > 2:
			break

	# Check no active research
	if fs.current_research_id == &"":
		var available := GameManager.research_system.get_available_research(player_id)
		if available.size() > 0:
			messages.append("You can research a new technology.")

	# Show the first advisor message as a toast
	if messages.size() > 0:
		_show_advisor_toast(messages[0])

func _show_advisor_toast(text: String) -> void:
	if _advisor_toast:
		_advisor_toast.queue_free()
	_advisor_toast = Label.new()
	_advisor_toast.text = text
	_advisor_toast.add_theme_font_size_override("font_size", 12)
	_advisor_toast.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.08, 0.15, 0.85)
	bg.border_color = Color(0.5, 0.4, 0.2, 0.5)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	_advisor_toast.add_theme_stylebox_override("normal", bg)
	_advisor_toast.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_advisor_toast.anchor_left = 1.0
	_advisor_toast.anchor_top = 1.0
	_advisor_toast.offset_left = -320
	_advisor_toast.offset_top = -190
	_advisor_toast.offset_right = -10
	_advisor_toast.offset_bottom = -160
	add_child(_advisor_toast)
	# Auto-dismiss after 5 seconds
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_advisor_toast, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		if _advisor_toast:
			_advisor_toast.queue_free()
			_advisor_toast = null
	)

# ── Faction Overview Panel ────────────────────────────────────

func _on_faction_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_faction_overview()

func _toggle_faction_overview() -> void:
	if faction_overview_panel == null:
		return
	faction_overview_panel.visible = !faction_overview_panel.visible
	if faction_overview_panel.visible:
		faction_overview_panel.move_to_front()
		_populate_faction_overview()

func _create_faction_overview_panel() -> void:
	faction_overview_panel = PanelContainer.new()
	faction_overview_panel.name = "FactionOverviewPanel"
	faction_overview_panel.visible = false

	faction_overview_panel.anchor_left = 0.03
	faction_overview_panel.anchor_right = 0.97
	faction_overview_panel.anchor_top = 0.03
	faction_overview_panel.anchor_bottom = 0.97
	faction_overview_panel.offset_left = 0
	faction_overview_panel.offset_right = 0
	faction_overview_panel.offset_top = 0
	faction_overview_panel.offset_bottom = 0
	faction_overview_panel.clip_contents = true

	faction_overview_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	faction_overview_panel.add_child(vbox)

	# Header row with title + close button
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.name = "FactionTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	header.add_child(_make_close_button(func(): faction_overview_panel.visible = false))

	# Description
	var desc := Label.new()
	desc.name = "FactionDesc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	vbox.add_child(desc)

	# Stats row
	var stats := Label.new()
	stats.name = "FactionStats"
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
	vbox.add_child(stats)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep)

	# Tab buttons
	var tab_row := HBoxContainer.new()
	tab_row.name = "TabRow"
	vbox.add_child(tab_row)
	var buildings_tab := Button.new()
	buildings_tab.name = "BuildingsTab"
	buildings_tab.text = "Buildings"
	buildings_tab.custom_minimum_size = Vector2(100, 0)
	buildings_tab.pressed.connect(func(): _show_faction_tab("buildings"))
	tab_row.add_child(buildings_tab)
	var units_tab := Button.new()
	units_tab.name = "UnitsTab"
	units_tab.text = "Units"
	units_tab.custom_minimum_size = Vector2(100, 0)
	units_tab.pressed.connect(func(): _show_faction_tab("units"))
	tab_row.add_child(units_tab)

	# Scroll + content
	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "ContentVBox"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	add_child(faction_overview_panel)

	# Detail panel (for building/unit detail views)
	_faction_detail_panel = PanelContainer.new()
	_faction_detail_panel.name = "FactionDetailPanel"
	_faction_detail_panel.visible = false
	_faction_detail_panel.anchor_left = 0.25
	_faction_detail_panel.anchor_right = 0.75
	_faction_detail_panel.anchor_top = 0.1
	_faction_detail_panel.anchor_bottom = 0.9
	_faction_detail_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())

	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DetailScroll"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_faction_detail_panel.add_child(detail_scroll)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.name = "DetailVBox"
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_vbox)

	add_child(_faction_detail_panel)

func _populate_faction_overview() -> void:
	var faction_id := GameManager.state.player_faction_id
	var faction_data := DataManager.get_faction(faction_id)
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if faction_data == null or fs == null:
		return

	var vbox: VBoxContainer = faction_overview_panel.get_node("MainVBox")
	var title: Label = vbox.find_child("FactionTitle", true, false)
	title.text = faction_data.display_name

	var desc: Label = vbox.get_node("FactionDesc")
	desc.text = faction_data.description

	var stats: Label = vbox.get_node("FactionStats")
	var realm_name: String = REALM_NAMES[faction_data.realm_affinity] if faction_data.realm_affinity < REALM_NAMES.size() else "Unknown"
	var region_count: int = fs.owned_regions.size()
	var city_count: int = 0
	for city in GameManager.state.cities.values():
		if city.faction_id == faction_id:
			city_count += 1
	var army_count: int = 0
	for army in GameManager.state.armies.values():
		if army.faction_id == faction_id:
			army_count += 1
	stats.text = "Realm: %s  |  Regions: %d  |  Cities: %d  |  Armies: %d" % [realm_name, region_count, city_count, army_count]

	_show_faction_tab("buildings")

func _show_faction_tab(tab: String) -> void:
	var content: VBoxContainer = faction_overview_panel.get_node("MainVBox/ContentScroll/ContentVBox")
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

	var faction_id := GameManager.state.player_faction_id

	if tab == "buildings":
		_populate_buildings_list(content, faction_id)
	elif tab == "units":
		_populate_units_list(content, faction_id)

func _populate_buildings_list(content: VBoxContainer, faction_id: StringName) -> void:
	# Collect buildings for this faction (faction-specific + generic)
	var categorized: Dictionary = {}
	for building_id in DataManager.buildings:
		var bd: BuildingData = DataManager.buildings[building_id]
		if bd.faction_id != &"" and bd.faction_id != faction_id:
			continue
		var cat: String = str(bd.category)
		if not categorized.has(cat):
			categorized[cat] = []
		categorized[cat].append(bd)

	# Sort categories
	var cat_order := ["economic", "military", "cultural", "defensive"]
	var cat_labels := {"economic": "Economic", "military": "Military", "cultural": "Cultural", "defensive": "Defensive"}

	for cat in cat_order:
		if not categorized.has(cat):
			continue
		var buildings: Array = categorized[cat]
		# Sort by tier (capital level)
		buildings.sort_custom(func(a, b): return a.required_capital_level < b.required_capital_level)

		# Category header
		var header := Label.new()
		header.text = cat_labels.get(cat, cat.capitalize())
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
		content.add_child(header)

		var sep := HSeparator.new()
		sep.add_theme_color_override("separator_color", Color(0.45, 0.35, 0.2, 0.4))
		content.add_child(sep)

		# Grid for buildings
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		content.add_child(grid)

		for bd in buildings:
			var entry := _create_building_entry(bd)
			grid.add_child(entry)

		# Spacer
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		content.add_child(spacer)

	# Handle uncategorized
	for cat in categorized:
		if cat in cat_order:
			continue
		var header := Label.new()
		header.text = cat.capitalize()
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
		content.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		content.add_child(grid)
		for bd in categorized[cat]:
			grid.add_child(_create_building_entry(bd))

func _create_building_entry(bd: BuildingData) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)

	# Name + brief stats
	var cost_str := _format_cost(bd.build_cost)
	var tier_str := "T%d" % bd.required_capital_level
	var extras := ""
	if not bd.income_bonus.is_empty():
		var parts := PackedStringArray()
		for res_type in bd.income_bonus:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			parts.append("+%d %s" % [bd.income_bonus[res_type], rname])
		extras = " | " + ", ".join(parts)
	if bd.population_growth_bonus > 0:
		extras += " | +%d Growth" % bd.population_growth_bonus
	if not bd.unlocks_units.is_empty():
		extras += " | Unlocks units"

	btn.text = "[%s] %s  (%s)%s" % [tier_str, bd.display_name, cost_str, extras]
	btn.pressed.connect(_show_building_detail_overview.bind(bd))
	return btn

func _populate_units_list(content: VBoxContainer, faction_id: StringName) -> void:
	var units: Array = []
	for unit_id in DataManager.units:
		var ud: UnitData = DataManager.units[unit_id]
		if ud.faction_id == faction_id:
			units.append(ud)

	# Sort by recruit cost (gold)
	units.sort_custom(func(a, b): return a.recruit_cost.get(0, 0) < b.recruit_cost.get(0, 0))

	# Category header
	var header := Label.new()
	header.text = "Available Units"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	content.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.45, 0.35, 0.2, 0.4))
	content.add_child(sep)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)

	for ud in units:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)

		var tags_str := ", ".join(ud.tags) if not ud.tags.is_empty() else "unit"
		var cost_str := _format_cost(ud.recruit_cost)
		btn.text = "%s  (%s)  %s ATK  %s DEF  SPD:%d  [%s]" % [
			ud.display_name, cost_str, render_stars(get_attack_stars(ud)), render_stars(get_defense_stars(ud)), ud.speed, tags_str]
		btn.pressed.connect(_show_unit_detail_overview.bind(ud))
		grid.add_child(btn)

func _show_building_detail_overview(bd: BuildingData) -> void:
	if _faction_detail_panel == null:
		return
	var scroll: ScrollContainer = _faction_detail_panel.get_node("DetailScroll")
	var vbox: VBoxContainer = scroll.get_node("DetailVBox")
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	# Header row
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)
	var title := _make_label(bd.display_name, 18, Color(0.95, 0.88, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(_make_close_button(func(): _faction_detail_panel.visible = false))

	# Category + Tier
	var cat_label := Label.new()
	cat_label.text = "Category: %s  |  Required Capital Level: %d" % [str(bd.category).capitalize(), bd.required_capital_level]
	cat_label.add_theme_font_size_override("font_size", 13)
	cat_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(cat_label)

	if bd.requires_capital:
		var cap_label := Label.new()
		cap_label.text = "Capital only"
		cap_label.add_theme_font_size_override("font_size", 12)
		cap_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
		vbox.add_child(cap_label)

	# Description
	var desc := Label.new()
	desc.text = bd.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	vbox.add_child(desc)

	_add_detail_separator(vbox)

	# Build cost
	var cost_label := Label.new()
	cost_label.text = "Build Cost: %s  |  Build Time: %d turn(s)" % [_format_cost(bd.build_cost), bd.build_time]
	cost_label.add_theme_font_size_override("font_size", 13)
	cost_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	vbox.add_child(cost_label)

	# Income bonuses
	if not bd.income_bonus.is_empty():
		var parts := PackedStringArray()
		for res_type in bd.income_bonus:
			var rname: String = RESOURCE_NAMES[res_type] if res_type < RESOURCE_NAMES.size() else "?"
			var color: Color = RESOURCE_COLORS.get(res_type, Color(0.7, 0.7, 0.7))
			parts.append("+%d %s" % [bd.income_bonus[res_type], rname])
		var income_label := Label.new()
		income_label.text = "Income: " + ", ".join(parts)
		income_label.add_theme_font_size_override("font_size", 13)
		income_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		vbox.add_child(income_label)

	# Growth
	if bd.population_growth_bonus != 0:
		var growth_label := Label.new()
		growth_label.text = "Population Growth: +%d" % bd.population_growth_bonus
		growth_label.add_theme_font_size_override("font_size", 13)
		growth_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.35))
		vbox.add_child(growth_label)

	# Defense
	if bd.defense_bonus > 0:
		var def_label := Label.new()
		def_label.text = "Defense Bonus: +%d" % bd.defense_bonus
		def_label.add_theme_font_size_override("font_size", 13)
		def_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.85))
		vbox.add_child(def_label)

	# Recruit speed
	if bd.recruit_speed_bonus > 0:
		var rec_label := Label.new()
		rec_label.text = "Recruit Speed: +%d" % bd.recruit_speed_bonus
		rec_label.add_theme_font_size_override("font_size", 13)
		rec_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.55))
		vbox.add_child(rec_label)

	# Required terrain
	if bd.required_terrain >= 0:
		var terrain_name: String = TERRAIN_NAMES[bd.required_terrain] if bd.required_terrain < TERRAIN_NAMES.size() else "Unknown"
		var terrain_label := Label.new()
		terrain_label.text = "Required Terrain: %s" % terrain_name
		terrain_label.add_theme_font_size_override("font_size", 13)
		terrain_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		vbox.add_child(terrain_label)

	# Loyalty effects
	if not bd.class_loyalty_bonus.is_empty():
		_add_detail_separator(vbox)
		var loy_header := Label.new()
		loy_header.text = "Loyalty Effects:"
		loy_header.add_theme_font_size_override("font_size", 13)
		loy_header.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
		vbox.add_child(loy_header)
		for class_name_key in bd.class_loyalty_bonus:
			var amount: int = bd.class_loyalty_bonus[class_name_key]
			var loy_label := Label.new()
			loy_label.text = "  %s: %s%d" % [str(class_name_key).capitalize(), "+" if amount >= 0 else "", amount]
			loy_label.add_theme_font_size_override("font_size", 12)
			if amount >= 0:
				loy_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.35))
			else:
				loy_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
			vbox.add_child(loy_label)

	# Unlocked units
	if not bd.unlocks_units.is_empty():
		_add_detail_separator(vbox)
		var unlock_header := Label.new()
		unlock_header.text = "Unlocks Units:"
		unlock_header.add_theme_font_size_override("font_size", 13)
		unlock_header.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
		vbox.add_child(unlock_header)
		for unit_id in bd.unlocks_units:
			var ud := DataManager.get_unit(unit_id)
			var unit_label := Label.new()
			if ud:
				unit_label.text = "  - %s (ATK:%d DEF:%d/%d/%d)" % [ud.display_name, ud.attack, ud.melee_defense, ud.projectile_defense, ud.magic_defense]
			else:
				unit_label.text = "  - %s" % str(unit_id)
			unit_label.add_theme_font_size_override("font_size", 12)
			unit_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85))
			vbox.add_child(unit_label)

	# Upgrade chain
	_add_detail_separator(vbox)
	if bd.upgrades_from != &"":
		var from_bd := DataManager.get_building(bd.upgrades_from)
		var chain_label := Label.new()
		chain_label.text = "Upgrades from: %s" % (from_bd.display_name if from_bd else str(bd.upgrades_from))
		chain_label.add_theme_font_size_override("font_size", 12)
		chain_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
		vbox.add_child(chain_label)

	# Check what this upgrades TO
	for other_id in DataManager.buildings:
		var other: BuildingData = DataManager.buildings[other_id]
		if other.upgrades_from == bd.id:
			var to_label := Label.new()
			to_label.text = "Upgrades to: %s" % other.display_name
			to_label.add_theme_font_size_override("font_size", 12)
			to_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
			vbox.add_child(to_label)

	_faction_detail_panel.visible = true
	_faction_detail_panel.move_to_front()

func _show_unit_detail_overview(ud: UnitData) -> void:
	if _faction_detail_panel == null:
		return
	var scroll: ScrollContainer = _faction_detail_panel.get_node("DetailScroll")
	var vbox: VBoxContainer = scroll.get_node("DetailVBox")
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	# Header row
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)
	var title := _make_label(ud.display_name, 18, Color(0.95, 0.88, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	header_row.add_child(_make_close_button(func(): _faction_detail_panel.visible = false))

	# Tags
	if not ud.tags.is_empty():
		var tags_label := Label.new()
		tags_label.text = "Tags: " + ", ".join(ud.tags)
		tags_label.add_theme_font_size_override("font_size", 13)
		tags_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		vbox.add_child(tags_label)

	# Description
	var desc := Label.new()
	desc.text = ud.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	vbox.add_child(desc)

	_add_detail_separator(vbox)

	# Combat stats
	var stats_header := Label.new()
	stats_header.text = "Combat Statistics"
	stats_header.add_theme_font_size_override("font_size", 14)
	stats_header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	vbox.add_child(stats_header)

	var hp_text := "HP: %d" % ud.max_hp
	if ud.hp_per_soldier > 0 and ud.squad_size > 1:
		hp_text += "  (%d soldiers x %d hp)" % [ud.squad_size, ud.hp_per_soldier]
	_add_stat_line(vbox, hp_text, Color(0.35, 0.75, 0.35))
	_add_stat_line(vbox, "%s ATK  %s DEF" % [render_stars(get_attack_stars(ud)), render_stars(get_defense_stars(ud))], Color(0.8, 0.75, 0.6))
	_add_stat_line(vbox, "Attack: %d" % ud.attack, Color(0.85, 0.4, 0.35))
	_add_stat_line(vbox, "Defense: Melee %d / Ranged %d / Magic %d" % [ud.melee_defense, ud.projectile_defense, ud.magic_defense], Color(0.4, 0.55, 0.85))
	_add_stat_line(vbox, "Speed: %d" % ud.speed, Color(0.5, 0.8, 0.4))
	var range_text := "Melee" if ud.attack_range <= 1 else "Range: %d" % ud.attack_range
	_add_stat_line(vbox, range_text, Color(0.7, 0.65, 0.55))
	_add_stat_line(vbox, "Base Morale: %d" % ud.base_morale, Color(0.8, 0.75, 0.4))

	if ud.morale_aura != 0:
		var aura_text := "Morale Aura: %s%d (range: %d)" % ["+" if ud.morale_aura > 0 else "", ud.morale_aura, ud.fear_radius]
		_add_stat_line(vbox, aura_text, Color(0.7, 0.5, 0.8))

	_add_detail_separator(vbox)

	# Campaign stats
	var camp_header := Label.new()
	camp_header.text = "Campaign Statistics"
	camp_header.add_theme_font_size_override("font_size", 14)
	camp_header.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	vbox.add_child(camp_header)

	_add_stat_line(vbox, "Movement: %.1f" % ud.movement_points, Color(0.7, 0.65, 0.55))
	_add_stat_line(vbox, "Squad Size: %d" % ud.squad_size, Color(0.7, 0.65, 0.55))
	var pop_cost: int = ud.population_cost if ud.population_cost >= 0 else ud.squad_size
	_add_stat_line(vbox, "Population Cost: %d" % pop_cost, Color(0.7, 0.65, 0.55))
	_add_stat_line(vbox, "Recruit Cost: %s" % _format_cost(ud.recruit_cost), Color(0.85, 0.75, 0.5))
	_add_stat_line(vbox, "Recruit Time: %d turn(s)" % ud.recruit_time, Color(0.7, 0.65, 0.55))
	_add_stat_line(vbox, "Upkeep: %s" % _format_cost(ud.upkeep_cost), Color(0.85, 0.55, 0.4))
	_add_stat_line(vbox, "Captive Chance: %d%%" % int(ud.captive_chance * 100), Color(0.7, 0.65, 0.55))

	# Terrain bonuses
	if not ud.terrain_bonuses.is_empty():
		_add_detail_separator(vbox)
		var terrain_header := Label.new()
		terrain_header.text = "Terrain Bonuses:"
		terrain_header.add_theme_font_size_override("font_size", 13)
		terrain_header.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
		vbox.add_child(terrain_header)
		for terrain_type in ud.terrain_bonuses:
			var terrain_name: String = TERRAIN_NAMES[terrain_type] if terrain_type < TERRAIN_NAMES.size() else "?"
			var bonus: float = ud.terrain_bonuses[terrain_type]
			_add_stat_line(vbox, "  %s: %s%.0f%%" % [terrain_name, "+" if bonus >= 0 else "", bonus * 100], Color(0.65, 0.6, 0.5))

	# Which buildings unlock this unit
	_add_detail_separator(vbox)
	var unlocked_by_header := Label.new()
	unlocked_by_header.text = "Recruited from:"
	unlocked_by_header.add_theme_font_size_override("font_size", 13)
	unlocked_by_header.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	vbox.add_child(unlocked_by_header)
	var found_building := false
	for building_id in DataManager.buildings:
		var bd: BuildingData = DataManager.buildings[building_id]
		if ud.id in bd.unlocks_units:
			var bld_label := Label.new()
			bld_label.text = "  - %s" % bd.display_name
			bld_label.add_theme_font_size_override("font_size", 12)
			bld_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
			vbox.add_child(bld_label)
			found_building = true
	if not found_building:
		var none_label := Label.new()
		none_label.text = "  (No building requirement)"
		none_label.add_theme_font_size_override("font_size", 12)
		none_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
		vbox.add_child(none_label)

	_faction_detail_panel.visible = true
	_faction_detail_panel.move_to_front()

func _add_stat_line(parent: VBoxContainer, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _add_detail_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.4, 0.32, 0.18, 0.4))
	parent.add_child(sep)

# ── Panel slide/fade animations ──────────────────────────────────────────────

func _animate_panel_in(panel: Control, from_dir: String = "right") -> void:
	var offset := Vector2.ZERO
	match from_dir:
		"right": offset = Vector2(80, 0)
		"left": offset = Vector2(-80, 0)
		"top": offset = Vector2(0, -60)
		"bottom": offset = Vector2(0, 60)
	panel.modulate = Color(1, 1, 1, 0)
	panel.position += offset
	var target_pos := panel.position - offset
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "position", target_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _animate_panel_out(panel: Control, to_dir: String = "right", then_free: bool = true) -> void:
	var offset := Vector2.ZERO
	match to_dir:
		"right": offset = Vector2(80, 0)
		"left": offset = Vector2(-80, 0)
		"top": offset = Vector2(0, -60)
		"bottom": offset = Vector2(0, 60)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "position", panel.position + offset, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	if then_free:
		tween.chain().tween_callback(panel.queue_free)

# ── Turn transition banner ───────────────────────────────────────────────────

func _show_turn_banner(turn: int, faction_id: StringName) -> void:
	var is_player := faction_id == GameManager.state.player_faction_id
	var fd: FactionData = DataManager.get_faction(faction_id)
	var fc: Color = fd.color if fd else Color(0.7, 0.7, 0.7)

	# Panel background for readability
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	if is_player:
		style.bg_color = Color(0.08, 0.07, 0.1, 0.85)
		style.border_color = Color(0.9, 0.82, 0.45, 0.6)
	else:
		style.bg_color = Color(fc.r * 0.15, fc.g * 0.15, fc.b * 0.15, 0.85)
		style.border_color = Color(fc.r, fc.g, fc.b, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var banner := Label.new()
	if is_player:
		banner.text = "Turn %d" % turn
		banner.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	else:
		var fname := fd.display_name if fd else str(faction_id)
		banner.text = fname
		banner.add_theme_color_override("font_color", fc.lightened(0.2))
	banner.add_theme_font_size_override("font_size", 24)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(banner)

	panel.size = Vector2(400, 60)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	panel.modulate = Color(1, 1, 1, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(0.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)

# ── Army Overview Panel ──────────────────────────────────────

func _toggle_army_overview() -> void:
	if _army_overview_panel and is_instance_valid(_army_overview_panel):
		_animate_panel_out(_army_overview_panel, "right")
		_army_overview_panel = null
		return
	_army_overview_panel = PanelContainer.new()
	_army_overview_panel.name = "ArmyOverview"
	_army_overview_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	_army_overview_panel.anchor_left = 1
	_army_overview_panel.anchor_right = 1
	_army_overview_panel.offset_left = -320
	_army_overview_panel.offset_right = -4
	_army_overview_panel.offset_top = 40
	_army_overview_panel.offset_bottom = -4
	_army_overview_panel.anchor_top = 0
	_army_overview_panel.anchor_bottom = 1
	add_child(_army_overview_panel)
	_animate_panel_in(_army_overview_panel, "right")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_army_overview_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "ARMY OVERVIEW"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var player_id := GameManager.state.player_faction_id
	for aid in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[aid]
		if army.faction_id != player_id or army.is_garrison:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var cmd_name := army.commander_name if army.commander_name != "" else "No Commander"
		var info_lbl := Label.new()
		var region_name := ""
		var tile := GameManager.state.hex_map.get_tile(army.hex_pos)
		if tile:
			var region := DataManager.get_region(tile.region_id)
			region_name = region.display_name if region else ""
		info_lbl.text = "%s (%d units) - %s" % [cmd_name, army.units.size(), region_name]
		info_lbl.add_theme_font_size_override("font_size", 11)
		info_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_lbl)

		var goto_btn := Button.new()
		goto_btn.text = "Go To"
		goto_btn.custom_minimum_size = Vector2(50, 24)
		goto_btn.add_theme_font_size_override("font_size", 10)
		var captured_aid: StringName = aid
		var captured_pos: Vector2i = army.hex_pos
		goto_btn.pressed.connect(func():
			AudioManager.play_sfx(&"ui_click")
			var campaign := get_parent().get_parent()
			if campaign and campaign.has_method("_hex_to_pixel"):
				campaign.camera.position = campaign._hex_to_pixel(captured_pos)
				campaign._select_army(captured_aid)
		)
		row.add_child(goto_btn)
		vbox.add_child(row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 28)
	close_btn.pressed.connect(func():
		AudioManager.play_sfx(&"ui_click")
		_animate_panel_out(_army_overview_panel, "right")
		_army_overview_panel = null
	)
	vbox.add_child(close_btn)

func _close_city_panel() -> void:
	if city_panel and city_panel.visible:
		city_panel.visible = false
