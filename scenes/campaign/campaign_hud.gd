extends Control

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Coast", "Tundra", "Shard Wastes", "Water", "Jungle"]
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

const RESOURCE_NAMES := ["Gold", "Iron", "Technology", "Food", "Shard Essence", "Wood", "Captives"]
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
var commander_panel: PanelContainer
var economy_panel: PanelContainer
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
var _research_panel: PanelContainer
var _unit_detail_panel: PanelContainer
var _item_swap_panel: PanelContainer

func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn)

	EventBus.hex_tile_selected.connect(_on_hex_tile_selected)
	EventBus.hex_tile_deselected.connect(_on_hex_tile_deselected)
	EventBus.army_selected.connect(_on_army_selected)
	EventBus.army_deselected.connect(_on_army_deselected)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.army_moved.connect(_on_army_moved)

	EventBus.commander_level_up.connect(_on_commander_level_up)
	EventBus.commander_item_full.connect(_on_commander_item_full)
	EventBus.random_event_triggered.connect(_on_random_event_triggered)
	EventBus.shard_claimed.connect(_on_shard_claimed)
	EventBus.forsaken_offer.connect(_on_forsaken_offer_received)
	EventBus.senate_dilemma.connect(_on_senate_dilemma_received)
	EventBus.research_completed.connect(_on_research_completed)

	_create_resource_bar()
	_create_shard_display()
	_create_economy_panel()
	_create_city_panel()
	_create_commander_panel()
	_update_top_bar()

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

	army_panel.visible = true
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

	# Portrait placeholder (colored rectangle with unit icon)
	var portrait_container := PanelContainer.new()
	portrait_container.custom_minimum_size = Vector2(56, 64)
	var portrait_style := StyleBoxFlat.new()
	# Pick color based on primary tag
	var portrait_color := Color(0.3, 0.25, 0.2)
	for tag in unit_data.tags:
		if TAG_COLORS.has(tag):
			portrait_color = TAG_COLORS[tag]
			break
	portrait_style.bg_color = portrait_color
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

	# Unit type icon drawn as simple shapes
	var icon_container := CenterContainer.new()
	portrait_container.add_child(icon_container)
	var icon_label := Label.new()
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.8))
	# Choose icon based on tags
	if unit_data.tags.has("mage"):
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

	# Unit name
	var name_label := Label.new()
	name_label.text = unit_data.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.85, 0.55))
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

	# Stat row: DPS / DEF / SPD / RNG
	var stat_grid := HBoxContainer.new()
	stat_grid.add_theme_constant_override("separation", 6)

	var dps_val := estimate_unit_dps(unit_data)
	_add_stat_label(stat_grid, "DPS", str(int(dps_val)), Color(0.85, 0.4, 0.35))
	_add_stat_label(stat_grid, "DEF", str(unit_data.defense), Color(0.4, 0.6, 0.85))
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

	# Right-click to open detail panel
	card.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var title := Label.new()
	title.text = unit_data.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func():
		if _unit_detail_panel:
			_unit_detail_panel.queue_free()
			_unit_detail_panel = null
	)
	header.add_child(close_btn)
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
	var stat_lines: Array[String] = [
		"  DPS: %d  |  DEF: %d  |  SPD: %d" % [int(detail_dps), unit_data.defense, unit_data.speed],
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
## Ranged/mage: full salvo DPS (all entities fire). Melee: frontline contact DPS.
static func estimate_unit_dps(ud: UnitData) -> float:
	if ud.tags.has("mage"):
		# Mages: slow fire rate (18 tick cooldown), 0.6 dmg mult, ~70% hit
		return ud.squad_size * ud.attack * 0.6 * 0.7 * (10.0 / 18.0)
	if ud.tags.has("ranged"):
		# Archers: fast fire rate (5 tick cooldown), 0.6 dmg mult, ~80% hit
		return ud.squad_size * ud.attack * 0.6 * 0.8 * (10.0 / 5.0)
	# Melee: continuous damage at TICK_SCALE(0.2) * 10 ticks/sec = 2x attack per entity
	if ud.squad_size <= 1:
		return ud.attack * 2.0
	# Multi-entity melee: assume ~35% squad in frontline contact (proximity-weighted)
	var frontline := ceili(ud.squad_size * 0.35)
	return frontline * ud.attack * 2.0

func _on_army_deselected() -> void:
	army_panel.visible = false
	_hide_commander_panel()

func _on_turn_started(_turn: int, _faction_id: StringName) -> void:
	_update_top_bar()
	end_turn_button.disabled = not TurnManager.is_player_turn
	# Auto-refresh loyalty panel if open
	if _loyalty_panel_city_id != &"":
		_show_loyalty_panel(_loyalty_panel_city_id)
	# Auto-refresh research panel if open
	if _research_panel and _research_panel.visible:
		_refresh_research_panel()
	# Check for Forsaken offer on player turn
	if TurnManager.is_player_turn and _faction_id == GameManager.state.player_faction_id:
		var offer := GameManager.policy_system.check_forsaken_offer(_faction_id, GameManager.state.current_turn)
		if not offer.is_empty():
			EventBus.forsaken_offer.emit(_faction_id, offer)
		else:
			# Check for senate dilemma (deferred to avoid dialog overlap)
			var dilemma := GameManager.policy_system.check_senate_dilemma(_faction_id, GameManager.state.current_turn)
			if not dilemma.is_empty():
				call_deferred("_emit_senate_dilemma", _faction_id, dilemma)

func _on_army_moved(army_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	# Refresh army panel if the moved army is selected
	var campaign: Node2D = get_parent().get_parent()
	if campaign and "selected_army_id" in campaign:
		if campaign.selected_army_id == army_id:
			_on_army_selected(army_id)

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
				for j in 8:
					var angle := TAU * j / 8.0
					pts.append(Vector2(cos(angle) * 5.0 * s, sin(angle) * 3.5 * s))
				coin.polygon = pts
				coin.position = Vector2(float(i - 1) * 2.0 * s, float(1 - i) * 1.5 * s)
				coin.color = Color(0.95, 0.85, 0.3).darkened(i * 0.08)
				root.add_child(coin)
		1:  # Iron - ingot
			var ingot := Polygon2D.new()
			ingot.polygon = PackedVector2Array([
				Vector2(-6 * s, -2 * s), Vector2(6 * s, -2 * s),
				Vector2(5 * s, 4 * s), Vector2(-5 * s, 4 * s)
			])
			ingot.color = Color(0.55, 0.55, 0.6)
			root.add_child(ingot)
			var highlight := Polygon2D.new()
			highlight.polygon = PackedVector2Array([
				Vector2(-6 * s, -2 * s), Vector2(6 * s, -2 * s),
				Vector2(4 * s, 0), Vector2(-4 * s, 0)
			])
			highlight.color = Color(0.7, 0.7, 0.75, 0.6)
			root.add_child(highlight)
		2:  # Technology - gear
			var gear := Polygon2D.new()
			var pts := PackedVector2Array()
			for j in 12:
				var angle := TAU * j / 12.0
				var r := 5.0 * s if j % 2 == 0 else 3.5 * s
				pts.append(Vector2(cos(angle) * r, sin(angle) * r))
			gear.polygon = pts
			gear.color = Color(0.45, 0.55, 0.65)
			root.add_child(gear)
		3:  # Food - steak shape
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
		5:  # Wood - crossed logs
			for angle in [0.4, -0.4]:
				var log := Polygon2D.new()
				log.polygon = PackedVector2Array([
					Vector2(-6 * s, -1.5 * s), Vector2(6 * s, -1.5 * s),
					Vector2(6 * s, 1.5 * s), Vector2(-6 * s, 1.5 * s)
				])
				log.color = Color(0.55, 0.38, 0.22)
				log.rotation = angle
				root.add_child(log)
		6:  # Captives - person outlines
			for i in 3:
				var x_off := float(i - 1) * 4.5 * s
				# Head
				var head := Polygon2D.new()
				var pts := PackedVector2Array()
				for j in 6:
					var angle := TAU * j / 6.0
					pts.append(Vector2(cos(angle) * 2.0 * s + x_off, sin(angle) * 2.0 * s - 3.5 * s))
				head.polygon = pts
				head.color = Color(0.65, 0.45, 0.35)
				root.add_child(head)
				# Shoulders
				var body := Polygon2D.new()
				body.polygon = PackedVector2Array([
					Vector2(x_off - 3 * s, 0), Vector2(x_off + 3 * s, 0),
					Vector2(x_off + 2 * s, 5 * s), Vector2(x_off - 2 * s, 5 * s)
				])
				body.color = Color(0.65, 0.45, 0.35)
				root.add_child(body)
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

	# Build individual resource items
	for res_type in [0, 1, 2, 3, 5, 6]:
		var item_vbox := VBoxContainer.new()
		item_vbox.add_theme_constant_override("separation", 0)
		item_vbox.mouse_filter = Control.MOUSE_FILTER_STOP

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 3)

		# Polygon icon
		var icon := _create_resource_icon(res_type, 16.0)
		top_row.add_child(icon)

		# Amount label
		var amount_label := Label.new()
		amount_label.text = "0"
		amount_label.add_theme_font_size_override("font_size", 13)
		amount_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		top_row.add_child(amount_label)

		item_vbox.add_child(top_row)

		# Income preview label (smaller, below)
		var income_label := Label.new()
		income_label.text = ""
		income_label.add_theme_font_size_override("font_size", 10)
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

func _calculate_projected_income() -> Dictionary:
	var income: Dictionary = {}
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return income
	# Sum city incomes
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income := GameManager.city_system.calculate_city_income(city)
			for res in city_income:
				income[res] = income.get(res, 0) + city_income[res]
	# Subtract upkeep
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id:
			for unit in army.units:
				var ud := DataManager.get_unit(unit.unit_data_id)
				if ud:
					for res in ud.upkeep_cost:
						income[res] = income.get(res, 0) - ud.upkeep_cost[res]
			# Commander upkeep
			if army.commander != null:
				var level_mult := 1.0 + (army.commander.level - 1) * 0.5
				for res_type in CommanderSystem.COMMANDER_UPKEEP:
					var cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
					income[res_type] = income.get(res_type, 0) - cost
	return income

func _calculate_income_breakdown(res_type: int) -> Dictionary:
	# Returns {"cities": {city_name: amount}, "upkeep": {category: amount}, "net": int}
	var breakdown := {"cities": {}, "upkeep": {}, "net": 0}
	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return breakdown
	var total := 0
	for city_id in fs.owned_cities:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city and not city.is_under_siege:
			var city_income := GameManager.city_system.calculate_city_income(city)
			var amount: int = city_income.get(res_type, 0)
			if amount != 0:
				breakdown.cities[city.get_display_name()] = amount
				total += amount
	# Upkeep grouped by tag
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
					total -= ud.upkeep_cost[res_type]
			# Commander upkeep
			if army.commander != null and CommanderSystem.COMMANDER_UPKEEP.has(res_type):
				var level_mult := 1.0 + (army.commander.level - 1) * 0.5
				var cmd_cost := int(CommanderSystem.COMMANDER_UPKEEP[res_type] * level_mult)
				upkeep_by_tag["Commanders"] = upkeep_by_tag.get("Commanders", 0) + cmd_cost
				total -= cmd_cost
	breakdown.upkeep = upkeep_by_tag

	# Senate majority effects (percentage bonuses)
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
			breakdown["senate"] = pct

	breakdown.net = total
	return breakdown

func _update_resource_display() -> void:
	if GameManager.state == null or resource_bar == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs == null:
		return

	var projected := _calculate_projected_income()

	for res_type in [0, 1, 2, 3, 5, 6]:
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
	if breakdown.has("senate") and breakdown.senate != 0:
		text += "\n  Senate Majority: %+d%%" % breakdown.senate
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

	# Policies button
	_create_policies_panel()
	var policies_btn := Button.new()
	policies_btn.name = "PoliciesButton"
	policies_btn.text = "Senate"
	policies_btn.custom_minimum_size = Vector2(90, 0)
	policies_btn.pressed.connect(_toggle_policies_panel)
	hbox.add_child(policies_btn)
	hbox.move_child(policies_btn, end_btn_idx + 1)

	# Research button
	_create_research_panel()
	var research_btn := Button.new()
	research_btn.name = "ResearchButton"
	research_btn.text = "Research"
	research_btn.custom_minimum_size = Vector2(90, 0)
	research_btn.pressed.connect(_toggle_research_panel)
	hbox.add_child(research_btn)
	hbox.move_child(research_btn, end_btn_idx + 2)

	# Economy button
	var economy_btn := Button.new()
	economy_btn.name = "EconomyButton"
	economy_btn.text = "Economy"
	economy_btn.custom_minimum_size = Vector2(90, 0)
	economy_btn.pressed.connect(_toggle_economy_panel)
	hbox.add_child(economy_btn)
	hbox.move_child(economy_btn, end_btn_idx + 3)

	# Create the economy panel itself
	economy_panel = PanelContainer.new()
	economy_panel.name = "EconomyPanel"
	economy_panel.visible = false

	economy_panel.set_anchors_preset(Control.PRESET_CENTER)
	economy_panel.anchor_left = 0.5
	economy_panel.anchor_right = 0.5
	economy_panel.anchor_top = 0.1
	economy_panel.anchor_bottom = 0.9
	economy_panel.offset_left = -190.0
	economy_panel.offset_right = 190.0
	economy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	economy_panel.custom_minimum_size = Vector2(360, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	economy_panel.add_theme_stylebox_override("panel", style)

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
	else:
		_refresh_economy_panel()
		economy_panel.visible = true

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
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Economy Overview"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func(): economy_panel.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)
	_add_separator(vbox)

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
			siege_note.text = "    (BESIEGED - no income)"
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

func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	return style

func _create_panel_header(vbox: VBoxContainer, title_text: String, panel: PanelContainer) -> void:
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func(): panel.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)
	_add_separator(vbox)

# ── Diplomacy Panel ──────────────────────────────────────────

var _diplomacy_trade_panel: PanelContainer
var _diplomacy_trade_target: StringName = &""

func _create_diplomacy_panel() -> void:
	_diplomacy_panel = PanelContainer.new()
	_diplomacy_panel.name = "DiplomacyPanel"
	_diplomacy_panel.visible = false
	_diplomacy_panel.set_anchors_preset(Control.PRESET_CENTER)
	_diplomacy_panel.anchor_left = 0.5
	_diplomacy_panel.anchor_right = 0.5
	_diplomacy_panel.anchor_top = 0.08
	_diplomacy_panel.anchor_bottom = 0.92
	_diplomacy_panel.offset_left = -220.0
	_diplomacy_panel.offset_right = 220.0
	_diplomacy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_diplomacy_panel.custom_minimum_size = Vector2(420, 0)
	_diplomacy_panel.add_theme_stylebox_override("panel", _create_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_diplomacy_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "DiplomacyVBox"
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(_diplomacy_panel)

func _toggle_diplomacy_panel() -> void:
	if _diplomacy_panel.visible:
		_diplomacy_panel.visible = false
	else:
		_refresh_diplomacy_panel()
		_diplomacy_panel.visible = true

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

	_create_panel_header(vbox, "Diplomacy", _diplomacy_panel)

	var player_id := GameManager.state.player_faction_id
	for faction_id in GameManager.state.faction_states:
		if faction_id == player_id or faction_id == &"rebels":
			continue
		var fs: FactionState = GameManager.state.faction_states[faction_id]
		if fs.is_defeated:
			continue
		var fd: FactionData = DataManager.get_faction(faction_id)
		if fd == null:
			continue

		var relation := GameManager.get_relation(player_id, faction_id)
		var standing := GameManager.diplomacy_system.get_standing(player_id, faction_id)

		# Faction row container
		var faction_box := VBoxContainer.new()
		faction_box.add_theme_constant_override("separation", 4)

		# Name + relation + standing row
		var info_row := HBoxContainer.new()
		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(12, 12)
		color_rect.color = fd.color
		info_row.add_child(color_rect)
		var name_label := Label.new()
		name_label.text = " " + fd.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		info_row.add_child(name_label)
		var rel_label := Label.new()
		rel_label.text = RELATION_NAMES[relation]
		rel_label.add_theme_font_size_override("font_size", 12)
		rel_label.add_theme_color_override("font_color", RELATION_COLORS.get(relation, Color.WHITE))
		info_row.add_child(rel_label)
		var standing_label := Label.new()
		standing_label.text = "  [%d]" % standing
		standing_label.add_theme_font_size_override("font_size", 11)
		if standing > 0:
			standing_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
		elif standing < 0:
			standing_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
		else:
			standing_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
		info_row.add_child(standing_label)
		faction_box.add_child(info_row)

		# Action buttons row
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)

		if relation == Enums.FactionRelation.WAR:
			var peace_btn := Button.new()
			peace_btn.text = "Propose Peace"
			peace_btn.custom_minimum_size = Vector2(100, 28)
			var fid: StringName = faction_id
			peace_btn.pressed.connect(func(): _on_diplomacy_propose_peace(fid))
			btn_row.add_child(peace_btn)
		elif relation != Enums.FactionRelation.ALLIED:
			var war_btn := Button.new()
			war_btn.text = "Declare War"
			war_btn.custom_minimum_size = Vector2(90, 28)
			var fid: StringName = faction_id
			war_btn.pressed.connect(func(): _on_diplomacy_declare_war(fid))
			btn_row.add_child(war_btn)
			if relation == Enums.FactionRelation.FRIENDLY:
				var ally_btn := Button.new()
				ally_btn.text = "Propose Alliance"
				ally_btn.custom_minimum_size = Vector2(110, 28)
				var fid2: StringName = faction_id
				ally_btn.pressed.connect(func(): _on_diplomacy_propose_alliance(fid2))
				btn_row.add_child(ally_btn)

		if relation != Enums.FactionRelation.WAR:
			var trade_btn := Button.new()
			trade_btn.text = "Trade"
			trade_btn.custom_minimum_size = Vector2(60, 28)
			var fid: StringName = faction_id
			trade_btn.pressed.connect(func(): _on_diplomacy_open_trade(fid))
			btn_row.add_child(trade_btn)

		var gift_btn := Button.new()
		gift_btn.text = "Gift"
		gift_btn.custom_minimum_size = Vector2(50, 28)
		var fid_gift: StringName = faction_id
		gift_btn.pressed.connect(func(): _on_diplomacy_gift(fid_gift))
		btn_row.add_child(gift_btn)

		# Shard offer button (only if player owns shards)
		var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
		if player_fs and player_fs.owned_shards.size() > 0:
			var shard_btn := Button.new()
			shard_btn.text = "Offer Shard"
			shard_btn.custom_minimum_size = Vector2(80, 28)
			var fid_s: StringName = faction_id
			shard_btn.pressed.connect(func(): _on_diplomacy_offer_shard(fid_s))
			btn_row.add_child(shard_btn)

		faction_box.add_child(btn_row)

		# Active treaties
		var treaties := GameManager.diplomacy_system.get_treaties_between(player_id, faction_id)
		if treaties.size() > 0:
			for treaty in treaties:
				var treaty_label := Label.new()
				var type_name := ""
				match treaty.treaty_type:
					Enums.TreatyType.PEACE: type_name = "Peace Treaty"
					Enums.TreatyType.ALLIANCE: type_name = "Alliance"
					Enums.TreatyType.TRADE_DEAL: type_name = "Trade Deal"
				var duration_text := ""
				if treaty.turns_remaining > 0:
					duration_text = " (%d turns)" % treaty.turns_remaining
				elif treaty.turns_remaining == -1:
					duration_text = " (permanent)"
				treaty_label.text = "  > " + type_name + duration_text
				treaty_label.add_theme_font_size_override("font_size", 11)
				treaty_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8))
				faction_box.add_child(treaty_label)

		vbox.add_child(faction_box)
		_add_separator(vbox)

func _on_diplomacy_declare_war(target: StringName) -> void:
	GameManager.diplomacy_system.declare_war(GameManager.state.player_faction_id, target)
	_refresh_diplomacy_panel()

func _on_diplomacy_propose_peace(target: StringName) -> void:
	var result := GameManager.diplomacy_system.propose_peace(GameManager.state.player_faction_id, target)
	_refresh_diplomacy_panel()

func _on_diplomacy_propose_alliance(target: StringName) -> void:
	var result := GameManager.diplomacy_system.propose_alliance(GameManager.state.player_faction_id, target)
	_refresh_diplomacy_panel()

func _on_diplomacy_gift(target: StringName) -> void:
	# Gift 20 gold as default action
	var player_id := GameManager.state.player_faction_id
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
	if player_fs and player_fs.resources.get(Enums.ResourceType.GOLD, 0) >= 20:
		GameManager.diplomacy_system.gift_resources(player_id, target, Enums.ResourceType.GOLD, 20)
	_refresh_diplomacy_panel()

func _on_diplomacy_offer_shard(target: StringName) -> void:
	var player_id := GameManager.state.player_faction_id
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)
	if player_fs and player_fs.owned_shards.size() > 0:
		var shard_id: StringName = player_fs.owned_shards[0]
		GameManager.diplomacy_system.offer_shard(player_id, target, shard_id)
	_refresh_diplomacy_panel()

func _on_diplomacy_open_trade(target: StringName) -> void:
	# Simple trade proposal: offer 10 gold for 10 food, 5 turns
	var player_id := GameManager.state.player_faction_id
	var result := GameManager.diplomacy_system.propose_trade(
		player_id, target,
		Enums.ResourceType.GOLD, 10,
		Enums.ResourceType.FOOD, 10,
		5)
	_refresh_diplomacy_panel()

# ── Research Panel ───────────────────────────────────────────

func _create_research_panel() -> void:
	_research_panel = PanelContainer.new()
	_research_panel.name = "ResearchPanel"
	_research_panel.visible = false
	_research_panel.set_anchors_preset(Control.PRESET_CENTER)
	_research_panel.anchor_left = 0.5
	_research_panel.anchor_right = 0.5
	_research_panel.anchor_top = 0.08
	_research_panel.anchor_bottom = 0.92
	_research_panel.offset_left = -220.0
	_research_panel.offset_right = 220.0
	_research_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_research_panel.custom_minimum_size = Vector2(420, 0)
	_research_panel.add_theme_stylebox_override("panel", _create_panel_style())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_research_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "ResearchVBox"
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	add_child(_research_panel)

func _on_research_completed(faction_id: StringName, _research_id: StringName) -> void:
	if faction_id != GameManager.state.player_faction_id:
		return
	# Refresh research panel if open
	if _research_panel and _research_panel.visible:
		_refresh_research_panel()

func _toggle_research_panel() -> void:
	if _research_panel.visible:
		_research_panel.visible = false
	else:
		_refresh_research_panel()
		_research_panel.visible = true

func _refresh_research_panel() -> void:
	var scroll: ScrollContainer = _research_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("ResearchVBox")
	for child in vbox.get_children():
		child.queue_free()

	_create_panel_header(vbox, "Research", _research_panel)

	var player_id := GameManager.state.player_faction_id
	var fs: FactionState = GameManager.state.faction_states.get(player_id)
	if fs == null:
		return

	var current_tech: int = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)

	# Technology resource display
	var tech_row := HBoxContainer.new()
	var tech_icon := Label.new()
	tech_icon.text = "Technology: "
	tech_icon.add_theme_font_size_override("font_size", 13)
	tech_icon.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	tech_row.add_child(tech_icon)
	var tech_val := Label.new()
	tech_val.text = str(current_tech)
	tech_val.add_theme_font_size_override("font_size", 13)
	tech_val.add_theme_color_override("font_color", RESOURCE_COLORS.get(2, Color.WHITE))
	tech_row.add_child(tech_val)
	vbox.add_child(tech_row)

	# Current research section
	if fs.current_research_id != &"":
		var data: ResearchData = DataManager.get_research(fs.current_research_id)
		if data:
			_add_separator(vbox)
			var section_label := Label.new()
			section_label.text = "Current Research"
			section_label.add_theme_font_size_override("font_size", 14)
			section_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(section_label)

			var cat_color: Color = RESEARCH_CATEGORY_COLORS.get(data.research_category, Color(0.7, 0.7, 0.7))
			var cur_box := VBoxContainer.new()
			cur_box.add_theme_constant_override("separation", 2)
			var name_label := Label.new()
			name_label.text = data.display_name
			name_label.add_theme_font_size_override("font_size", 13)
			name_label.add_theme_color_override("font_color", cat_color)
			cur_box.add_child(name_label)

			var progress_row := HBoxContainer.new()
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = data.research_time
			bar.value = fs.research_progress
			bar.custom_minimum_size = Vector2(200, 20)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.show_percentage = false
			progress_row.add_child(bar)
			var turns_label := Label.new()
			turns_label.text = " %d/%d turns" % [fs.research_progress, data.research_time]
			turns_label.add_theme_font_size_override("font_size", 11)
			progress_row.add_child(turns_label)
			cur_box.add_child(progress_row)

			var invested: Array = fs.research_invested_shards.get(fs.current_research_id, [])
			if invested.size() > 0:
				var shard_text := Label.new()
				var realm_names: Array[String] = []
				for realm in invested:
					realm_names.append(REALM_NAMES[realm])
				shard_text.text = "Invested shards: " + ", ".join(realm_names)
				shard_text.add_theme_font_size_override("font_size", 11)
				shard_text.add_theme_color_override("font_color", Color(0.7, 0.3, 0.8))
				cur_box.add_child(shard_text)

			var cancel_btn := Button.new()
			cancel_btn.text = "Cancel Research"
			cancel_btn.custom_minimum_size = Vector2(120, 26)
			cancel_btn.pressed.connect(func():
				GameManager.research_system.cancel_research(player_id)
				_refresh_research_panel())
			cur_box.add_child(cancel_btn)
			vbox.add_child(cur_box)

	# Available shards to invest
	if fs.current_research_id != &"" and fs.owned_shards.size() > 0:
		_add_separator(vbox)
		var shard_section := Label.new()
		shard_section.text = "Invest Shard"
		shard_section.add_theme_font_size_override("font_size", 14)
		shard_section.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(shard_section)
		for shard_id in fs.owned_shards:
			var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
			if shard == null:
				continue
			var shard_row := HBoxContainer.new()
			var shard_label_item := Label.new()
			shard_label_item.text = "%s Shard (Power %d)" % [REALM_NAMES[shard.realm], shard.power_level]
			shard_label_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			shard_label_item.add_theme_font_size_override("font_size", 12)
			shard_row.add_child(shard_label_item)
			var invest_btn := Button.new()
			invest_btn.text = "Invest"
			invest_btn.custom_minimum_size = Vector2(60, 24)
			var sid: StringName = shard_id
			invest_btn.pressed.connect(func():
				GameManager.research_system.invest_shard(player_id, sid)
				_refresh_research_panel())
			shard_row.add_child(invest_btn)
			vbox.add_child(shard_row)

	# Category legend
	_add_separator(vbox)
	var legend_row := HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 12)
	for cat_name in [&"military", &"economy", &"arcane", &"logistics"]:
		var chip := Label.new()
		chip.text = str(cat_name).capitalize()
		chip.add_theme_font_size_override("font_size", 10)
		chip.add_theme_color_override("font_color", RESEARCH_CATEGORY_COLORS.get(cat_name, Color.WHITE))
		legend_row.add_child(chip)
	vbox.add_child(legend_row)

	# Research tree grouped by tier
	for tier in [1, 2, 3]:
		_add_separator(vbox)
		var tier_label := Label.new()
		tier_label.text = "Tier %d" % tier
		tier_label.add_theme_font_size_override("font_size", 14)
		tier_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(tier_label)

		var has_any := false
		for research_id in DataManager.research:
			var data: ResearchData = DataManager.research[research_id]
			if data.tier != tier:
				continue
			if data.faction_id != &"" and data.faction_id != fs.faction_data_id:
				continue
			has_any = true
			var cat_color: Color = RESEARCH_CATEGORY_COLORS.get(data.research_category, Color(0.7, 0.7, 0.7))

			# Research card
			var card := PanelContainer.new()
			var card_style := StyleBoxFlat.new()
			card_style.bg_color = Color(0.1, 0.09, 0.13, 0.9)
			card_style.border_width_left = 3
			card_style.border_width_top = 1
			card_style.border_width_right = 1
			card_style.border_width_bottom = 1
			card_style.border_color = cat_color.darkened(0.3)
			card_style.corner_radius_top_left = 4
			card_style.corner_radius_top_right = 4
			card_style.corner_radius_bottom_right = 4
			card_style.corner_radius_bottom_left = 4
			card_style.content_margin_left = 8.0
			card_style.content_margin_top = 4.0
			card_style.content_margin_right = 6.0
			card_style.content_margin_bottom = 4.0
			card.add_theme_stylebox_override("panel", card_style)

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var info_box := VBoxContainer.new()
			info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_box.add_theme_constant_override("separation", 1)
			var r_name := Label.new()
			r_name.add_theme_font_size_override("font_size", 12)
			var desc := Label.new()
			desc.add_theme_font_size_override("font_size", 10)
			desc.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))

			if fs.completed_research.has(research_id):
				r_name.text = data.display_name
				r_name.add_theme_color_override("font_color", cat_color)
				card_style.bg_color = Color(cat_color.r * 0.15, cat_color.g * 0.15, cat_color.b * 0.15, 0.9)
				desc.text = _format_research_effects(data, fs)
				var done_badge := Label.new()
				done_badge.text = "DONE"
				done_badge.add_theme_font_size_override("font_size", 10)
				done_badge.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
				row.add_child(info_box)
				info_box.add_child(r_name)
				info_box.add_child(desc)
				row.add_child(done_badge)
			elif fs.current_research_id == research_id:
				r_name.text = data.display_name
				r_name.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
				desc.text = "%d/%d turns" % [fs.research_progress, data.research_time]
				row.add_child(info_box)
				info_box.add_child(r_name)
				info_box.add_child(desc)
			else:
				var prereqs_met := true
				for prereq in data.prerequisites:
					if not fs.completed_research.has(prereq):
						prereqs_met = false
						break
				var can_afford := current_tech >= data.tech_cost
				var not_busy := fs.current_research_id == &""

				if not prereqs_met:
					r_name.text = data.display_name
					r_name.add_theme_color_override("font_color", Color(0.4, 0.38, 0.35))
					card_style.border_color = Color(0.3, 0.28, 0.25)
					var prereq_names: Array[String] = []
					for prereq in data.prerequisites:
						var pdata: ResearchData = DataManager.get_research(prereq)
						if pdata:
							prereq_names.append(pdata.display_name)
					desc.text = "Requires: " + ", ".join(prereq_names)
					var lock_badge := Label.new()
					lock_badge.text = "LOCKED"
					lock_badge.add_theme_font_size_override("font_size", 10)
					lock_badge.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
					row.add_child(info_box)
					info_box.add_child(r_name)
					info_box.add_child(desc)
					row.add_child(lock_badge)
				else:
					r_name.text = data.display_name
					r_name.add_theme_color_override("font_color", cat_color if can_afford else cat_color.darkened(0.4))
					var cost_color := Color(0.6, 0.58, 0.5) if can_afford else Color(0.85, 0.35, 0.3)
					desc.text = "Cost: %dT, %d turns" % [data.tech_cost, data.research_time]
					desc.add_theme_color_override("font_color", cost_color)
					row.add_child(info_box)
					info_box.add_child(r_name)
					info_box.add_child(desc)
					if not_busy:
						var start_btn := Button.new()
						start_btn.text = "Start"
						start_btn.custom_minimum_size = Vector2(55, 24)
						start_btn.disabled = not can_afford
						var rid: StringName = research_id
						start_btn.pressed.connect(func():
							GameManager.research_system.start_research(player_id, rid)
							_refresh_research_panel())
						row.add_child(start_btn)
					else:
						var busy_label := Label.new()
						busy_label.text = "BUSY"
						busy_label.add_theme_font_size_override("font_size", 10)
						busy_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
						row.add_child(busy_label)

			card.add_child(row)

			# Right-click for detail popup
			var captured_data: ResearchData = data
			card.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_show_research_detail(captured_data))

			vbox.add_child(card)

		if not has_any:
			var none_label := Label.new()
			none_label.text = "  No research available"
			none_label.add_theme_font_size_override("font_size", 11)
			none_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
			vbox.add_child(none_label)

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
	var title := Label.new()
	title.text = data.display_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", cat_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(dialog.queue_free)
	header.add_child(close_btn)
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
	cost_label.text = "Cost: %d Technology  |  Research Time: %d turns" % [data.tech_cost, data.research_time]
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
			eff.text = "  %s: %+d" % [key.replace("_", " ").capitalize(), data.effects[key]]
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
				sb.text = "  %s Shard: %s %+d" % [realm_name, key.replace("_", " ").capitalize(), bonus[key]]
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
	_policies_panel.set_anchors_preset(Control.PRESET_CENTER)
	_policies_panel.anchor_left = 0.5
	_policies_panel.anchor_right = 0.5
	_policies_panel.anchor_top = 0.08
	_policies_panel.anchor_bottom = 0.92
	_policies_panel.offset_left = -220.0
	_policies_panel.offset_right = 220.0
	_policies_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_policies_panel.custom_minimum_size = Vector2(420, 0)
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
			var val_text := str(val)
			if change != 0:
				val_text += "  (%+d)" % change
			cls_val.text = val_text
			cls_val.add_theme_font_size_override("font_size", 11)
			if val >= 30:
				cls_val.add_theme_color_override("font_color", Color(0.4, 0.8, 0.35))
			elif val <= -10:
				cls_val.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
			else:
				cls_val.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
			cls_row.add_child(cls_val)
			# Change indicator color
			if change != 0:
				var change_label := Label.new()
				change_label.text = "/turn"
				change_label.add_theme_font_size_override("font_size", 9)
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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.06, 0.08, 0.97)
	style.border_color = Color(0.6, 0.15, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_forsaken_offer_dialog.add_theme_stylebox_override("panel", style)

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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.05, 0.07, 0.97)
	style.border_color = Color(0.7, 0.1, 0.15)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_forsaken_offer_dialog.add_theme_stylebox_override("panel", style)

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

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_senate_dilemma_dialog.add_theme_stylebox_override("panel", style)

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

	# Position: right side of screen, pushed toward top
	city_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	city_panel.anchor_left = 1.0
	city_panel.anchor_right = 1.0
	city_panel.anchor_top = 0.04
	city_panel.anchor_bottom = 0.72
	city_panel.offset_left = -380.0
	city_panel.offset_right = -10.0
	city_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	city_panel.custom_minimum_size = Vector2(360, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	city_panel.add_theme_stylebox_override("panel", style)

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
	add_child(_building_tooltip)

func _show_city_panel(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	var is_player_city := city.faction_id == GameManager.state.player_faction_id
	city_panel.visible = true

	var scroll: ScrollContainer = city_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("CityVBox")

	# Clear previous content
	for child in vbox.get_children():
		child.queue_free()

	# Header row with title and close button
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = city.get_display_name()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_city_panel_close)
	header.add_child(close_btn)
	vbox.add_child(header)

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

	var pop_text := ""
	if city.upgrade_turns_remaining > 0:
		pop_text = "Level %d  |  Pop: %d  (Upgrading: %d turns)" % [city.level, province_pop, city.upgrade_turns_remaining]
	elif threshold > 0:
		if province_pop >= threshold:
			pop_text = "Level %d  |  Pop: %d/%d +%d  (Ready)" % [city.level, province_pop, threshold, growth_per_turn]
		else:
			pop_text = "Level %d  |  Pop: %d/%d +%d" % [city.level, province_pop, threshold, growth_per_turn]
	else:
		pop_text = "Level %d  |  Pop: %d (MAX)" % [city.level, province_pop]

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

	# Upgrade button (player cities only, when population threshold met)
	if is_player_city and city.is_upgrade_available():
		var can_afford := GameManager.city_system.can_start_upgrade(city)
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

		# Cost breakdown with red for unaffordable resources
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

		# Show what's missing when can't afford
		if not can_afford and fs_upgrade:
			var missing_text := ""
			for res_type2 in upgrade_cost:
				var have2: int = fs_upgrade.resources.get(res_type2, 0)
				var need2: int = upgrade_cost[res_type2]
				if have2 < need2:
					var rname2: String = RESOURCE_NAMES[res_type2] if res_type2 < RESOURCE_NAMES.size() else "?"
					missing_text += " Need %d more %s." % [need2 - have2, rname2]
			if missing_text != "":
				var missing_label := Label.new()
				missing_label.text = missing_text.strip_edges()
				missing_label.add_theme_font_size_override("font_size", 10)
				missing_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.3))
				vbox.add_child(missing_label)

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
	var garrison_def: Array = CitySystem.GARRISON_BY_LEVEL.get(city.level, CitySystem.GARRISON_BY_LEVEL[1])
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
		siege_label.text = "UNDER SIEGE by %s (Turn %d/2)" % [aname, city.siege_turns]
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
	var available_buildings := GameManager.city_system.get_available_buildings(city)
	if is_player_city and available_buildings.size() > 0 and city.build_queue.is_empty():
		_add_separator(vbox)
		var build_header := Label.new()
		build_header.text = "Available Buildings"
		build_header.add_theme_font_size_override("font_size", 13)
		build_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(build_header)

		for building in available_buildings:
			var building_id: StringName = building.id

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)

			var build_btn := Button.new()
			if building.upgrades_from != &"":
				var from_building: BuildingData = DataManager.get_building(building.upgrades_from)
				var from_name := from_building.display_name if from_building else str(building.upgrades_from)
				build_btn.text = "\u25B2 " + building.display_name + " (from " + from_name + ")"
			else:
				build_btn.text = building.display_name
			build_btn.custom_minimum_size = Vector2(140, 28)
			# Color by building category
			var cat_color: Color
			match building.category:
				&"economic":
					# Check if industrial (iron/wood production) or pastoral (food/gold)
					var is_industrial := false
					for res in building.income_bonus:
						if res == Enums.ResourceType.IRON or res == Enums.ResourceType.WOOD:
							is_industrial = true
							break
					if is_industrial:
						cat_color = Color(0.85, 0.72, 0.3, 0.25)  # Gold/amber for industrial
					else:
						cat_color = Color(0.35, 0.7, 0.3, 0.25)   # Green for pastoral/village
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
			build_btn.pressed.connect(_on_build_pressed.bind(city_id, building_id))
			build_btn.mouse_entered.connect(_on_building_hover.bind(building_id))
			build_btn.mouse_exited.connect(_on_building_hover_exit)
			var captured_bid := building_id
			var captured_cid := city_id
			build_btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_show_building_detail(captured_bid, captured_cid)
			)

			var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
			if fs and not _can_afford_display(fs, building.build_cost):
				build_btn.disabled = true

			btn_row.add_child(build_btn)

			var cost_label := Label.new()
			cost_label.text = _format_cost(building.build_cost) + " | " + str(building.build_time) + " turn(s)"
			cost_label.add_theme_font_size_override("font_size", 11)
			cost_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
			btn_row.add_child(cost_label)

			vbox.add_child(btn_row)

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
				var has_pop := city.population >= unit_pop_cost
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
		if city.recruit_queue.size() > 0:
			_add_separator(vbox)
			var queue_header := Label.new()
			queue_header.text = "Training Queue"
			queue_header.add_theme_font_size_override("font_size", 13)
			queue_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
			vbox.add_child(queue_header)
			for item in city.recruit_queue:
				var unit_data := DataManager.get_unit(item.unit_data_id)
				var uname := unit_data.display_name if unit_data else str(item.unit_data_id)
				var qlabel := Label.new()
				qlabel.text = "  [Training] " + uname + " (%d turns)" % item.turns_remaining
				qlabel.add_theme_font_size_override("font_size", 12)
				qlabel.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	_loyalty_panel.add_theme_stylebox_override("panel", style)

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
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Province Loyalty: %d  (%s)" % [city.loyalty, status_text]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", loyalty_color)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(_on_loyalty_panel_close)
	header.add_child(close_btn)
	vbox.add_child(header)

	_add_separator(vbox)

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
			var delta_sign := "+" if cls_delta >= 0 else ""
			loyalty_value.text = "%d  %s%d" % [cls_loyalty, delta_sign, cls_delta]
			if cls_delta > 0:
				loyalty_value.add_theme_color_override("font_color", Color(0.5, 0.8, 0.45))
			elif cls_delta < 0:
				loyalty_value.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
			else:
				loyalty_value.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		loyalty_value.add_theme_font_size_override("font_size", 11)
		loyalty_hbox.add_child(loyalty_value)
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
			var pop_mult := minf(float(city.population) / 100.0, float(city.level))
			if city.population < 50:
				pop_mult *= maxf(0.1, float(city.population) / 50.0)
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
	if GameManager.city_system.start_building(city_id, building_id):
		_show_city_panel(city_id)
		_update_resource_display()

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
	text += building.description + "\n"

	# Terrain requirement
	if building.required_terrain >= 0:
		var terrain_names := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Coast", "Tundra", "Shard Wastes", "Water", "Jungle"]
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

	# Next upgrade in chain
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

	_building_detail_panel = _create_centered_dialog(400, 320)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_building_detail_panel.add_child(outer_vbox)

	# Header with close
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = building.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func():
		if _building_detail_panel:
			_building_detail_panel.queue_free()
			_building_detail_panel = null
	)
	header.add_child(close_btn)
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

	add_child(_building_detail_panel)

func _show_unit_card(unit_data_id: StringName) -> void:
	_hide_unit_card()
	var unit_data := DataManager.get_unit(unit_data_id)
	if unit_data == null:
		return

	_unit_card_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.42, 0.2, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	_unit_card_panel.add_theme_stylebox_override("panel", style)
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
	stats.text = "HP: %d  DPS: %d  DEF: %d  SPD: %d" % [unit_data.max_hp, int(card_dps), unit_data.defense, unit_data.speed]
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
		_show_city_panel(city_id)
		_update_resource_display()

func _get_recruitable_units(city: CityState) -> Array[StringName]:
	var result: Array[StringName] = []
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
			current_id = building.upgrades_from
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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	commander_panel.add_theme_stylebox_override("panel", style)

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
	add_child(_skill_tooltip)

func _update_commander_panel(army: ArmyState) -> void:
	if commander_panel == null:
		return

	commander_panel.visible = true
	var scroll: ScrollContainer = commander_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_node("CommanderVBox")
	for child in vbox.get_children():
		child.queue_free()

	var faction := DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction.color if faction else Color.WHITE
	var is_player_army := army.faction_id == GameManager.state.player_faction_id

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

		# Show dropdown for player armies
		if is_player_army:
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

		# Unassign button (player armies only)
		if is_player_army:
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

		# Faction
		var faction_name_label := Label.new()
		faction_name_label.text = faction.display_name if faction else str(army.faction_id)
		faction_name_label.add_theme_font_size_override("font_size", 12)
		faction_name_label.add_theme_color_override("font_color", faction_color.lightened(0.3))
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
					if skill_data.is_minor:
						skill_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
					else:
						skill_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
				else:
					skill_label.text = "  " + str(skill_id) + " (Lv.%d)" % slevel
					skill_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
				skill_label.add_theme_font_size_override("font_size", 11)
				skill_label.mouse_filter = Control.MOUSE_FILTER_STOP
				skill_label.mouse_entered.connect(_on_skill_hover_entered.bind(skill_id, slevel))
				skill_label.mouse_exited.connect(_on_skill_hover_exited)
				vbox.add_child(skill_label)

		# Items section
		_add_separator(vbox)
		var max_item_slots := CommanderSystem.get_max_item_slots(cmd)
		var items_header := Label.new()
		items_header.text = "Items (%d/%d)" % [cmd.items.size(), max_item_slots]
		items_header.add_theme_font_size_override("font_size", 12)
		items_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(items_header)
		var is_player_cmd := cmd.faction_id == GameManager.state.player_faction_id
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

		# Followers section
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
				var f_name_label := Label.new()
				f_name_label.text = "  " + follower.display_name
				f_name_label.add_theme_font_size_override("font_size", 11)
				f_name_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
				vbox.add_child(f_name_label)
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
		total_def += ud.defense
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
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(_close_item_swap_panel)
	header.add_child(close_btn)
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
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(_close_item_swap_panel)
	header_row.add_child(close_btn)
	vbox.add_child(header_row)

	_add_separator(vbox)

	for fi in fs.follower_storage.size():
		var fid: StringName = fs.follower_storage[fi]
		var fdata: FollowerData = DataManager.get_follower(fid)
		if fdata == null:
			continue
		var btn := Button.new()
		btn.text = fdata.display_name
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(240, 26)
		var captured_fi := fi
		var captured_cmd := commander
		var captured_aid := army_id
		btn.pressed.connect(func():
			var f_fs: FactionState = GameManager.state.faction_states.get(captured_cmd.faction_id)
			if f_fs and captured_fi < f_fs.follower_storage.size():
				var f_id: StringName = f_fs.follower_storage[captured_fi]
				f_fs.follower_storage.remove_at(captured_fi)
				captured_cmd.followers.append(f_id)
			_close_item_swap_panel()
			_refresh_commander_panel()
		)
		vbox.add_child(btn)
		# Show bonus/malus preview
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

	# Show auto-assigned minor skill info
	# Find the most recently changed minor skill
	for sid in commander.skill_levels:
		var skill_data = CommanderSystem.skills.get(sid)
		if skill_data and skill_data.is_minor:
			var slevel: int = commander.skill_levels[sid]
			var minor_label := Label.new()
			if slevel > 1:
				minor_label.text = "%s leveled up to Lv.%d" % [skill_data.display_name, slevel]
			else:
				minor_label.text = "Gained: %s" % skill_data.display_name
			minor_label.add_theme_font_size_override("font_size", 13)
			minor_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
			minor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(minor_label)
			break

	_add_separator(vbox)

	# Major skill choices (now can include level-ups)
	var choices = CommanderSystem.get_major_skill_choices(commander)
	if choices.size() > 0:
		var choose_label := Label.new()
		choose_label.text = "Choose a major skill:"
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
			btn.custom_minimum_size = Vector2(300, 36)
			btn.pressed.connect(_on_major_skill_chosen.bind(choice.skill_id))
			vbox.add_child(btn)
	else:
		var no_skills := Label.new()
		no_skills.text = "No major skills available"
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
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = region.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func():
		if _region_overview_panel:
			_region_overview_panel.queue_free()
			_region_overview_panel = null
	)
	header.add_child(close_btn)
	vbox.add_child(header)
	_add_separator(vbox)

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
		var faction := DataManager.get_faction(army.faction_id)
		var fname := faction.display_name if faction else str(army.faction_id)
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	dialog.add_theme_stylebox_override("panel", style)

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
