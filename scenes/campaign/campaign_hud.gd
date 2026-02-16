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

const RESOURCE_NAMES := ["Gold", "Iron", "Technology", "Food", "Shard Essence", "Wood"]
const RESOURCE_COLORS := {
	0: Color(0.95, 0.85, 0.3), # Gold
	1: Color(0.6, 0.6, 0.65), # Iron
	2: Color(0.45, 0.55, 0.65), # Technology (steely blue-grey)
	3: Color(0.5, 0.8, 0.35), # Food
	4: Color(0.7, 0.3, 0.8), # Shard Essence
	5: Color(0.55, 0.40, 0.25), # Wood (warm brown)
}

@onready var turn_label: Label = $TopBar/HBoxContainer/TurnLabel
@onready var date_label: Label = $TopBar/HBoxContainer/DateLabel
@onready var faction_label: Label = $TopBar/HBoxContainer/FactionLabel
@onready var end_turn_button: Button = $TopBar/HBoxContainer/EndTurnButton
@onready var region_panel: PanelContainer = $RegionPanel
@onready var army_panel: PanelContainer = $SelectedArmyPanel
var city_panel: PanelContainer
var resource_label: Label
var shard_label: Label
var shard_tooltip: PanelContainer
var commander_panel: PanelContainer

func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn)

	EventBus.hex_tile_selected.connect(_on_hex_tile_selected)
	EventBus.hex_tile_deselected.connect(_on_hex_tile_deselected)
	EventBus.army_selected.connect(_on_army_selected)
	EventBus.army_deselected.connect(_on_army_deselected)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.army_moved.connect(_on_army_moved)

	_create_resource_label()
	_create_shard_display()
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

	# Stat row: ATK / DEF / SPD / RNG
	var stat_grid := HBoxContainer.new()
	stat_grid.add_theme_constant_override("separation", 6)

	_add_stat_label(stat_grid, "ATK", str(unit_data.attack), Color(0.85, 0.4, 0.35))
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
	return card

func _add_stat_label(parent: HBoxContainer, stat_name: String, value: String, color: Color) -> void:
	var label := Label.new()
	label.text = stat_name + ":" + value
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _on_army_deselected() -> void:
	army_panel.visible = false
	_hide_commander_panel()

func _on_turn_started(_turn: int, _faction_id: StringName) -> void:
	_update_top_bar()
	end_turn_button.disabled = not TurnManager.is_player_turn

func _on_army_moved(army_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	# Refresh army panel if the moved army is selected
	var campaign: Node2D = get_parent().get_parent()
	if campaign and "selected_army_id" in campaign:
		if campaign.selected_army_id == army_id:
			_on_army_selected(army_id)

# ── Resource display ─────────────────────────────────────────

func _create_resource_label() -> void:
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 12)
	resource_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	# Insert before the Spacer in the top bar
	var hbox: HBoxContainer = $TopBar/HBoxContainer
	var spacer := hbox.get_node("Spacer")
	hbox.add_child(resource_label)
	hbox.move_child(resource_label, spacer.get_index())

func _update_resource_display() -> void:
	if GameManager.state == null or resource_label == null:
		return
	var fs: FactionState = GameManager.state.faction_states.get(GameManager.state.player_faction_id)
	if fs == null:
		return
	var parts: Array[String] = []
	# Show Gold(0), Iron(1), Technology(2), Food(3), Wood(5) - skip Shard Essence(4)
	for i in [0, 1, 2, 3, 5]:
		var amount: int = fs.resources.get(i, 0)
		parts.append(RESOURCE_NAMES[i] + ": " + str(amount))
	resource_label.text = "  |  ".join(parts)

	# Update shard display
	_update_shard_display()

# ── City management panel ────────────────────────────────────

func _create_city_panel() -> void:
	city_panel = PanelContainer.new()
	city_panel.name = "CityPanel"
	city_panel.visible = false

	# Position: right side of screen
	city_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	city_panel.anchor_left = 1.0
	city_panel.anchor_right = 1.0
	city_panel.anchor_top = 0.15
	city_panel.anchor_bottom = 0.85
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

func _show_city_panel(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

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

	_add_separator(vbox)

	# City info: Level, Population, Growth
	var info_label := Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	var threshold := city.get_growth_threshold()
	var growth_text := ""
	if threshold > 0:
		growth_text = "Growth: %d / %d" % [city.growth_points, threshold]
	else:
		growth_text = "Growth: MAX"
	info_label.text = "Level %d  |  Pop: %d  |  %s" % [city.level, city.population, growth_text]
	vbox.add_child(info_label)

	# Income preview
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

	# Settlement founding button (only for player capitals that can found)
	if city.is_capital and city.can_found_settlement and city.faction_id == GameManager.state.player_faction_id:
		var found_btn := Button.new()
		found_btn.text = "Found Settlement"
		found_btn.custom_minimum_size = Vector2(180, 32)
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

	# Existing buildings
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building:
			var blabel := Label.new()
			blabel.text = "  " + building.display_name
			blabel.add_theme_font_size_override("font_size", 12)
			blabel.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
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

	# Available buildings to construct
	if city.get_available_building_slots() > 0 and city.build_queue.is_empty():
		_add_separator(vbox)
		var build_header := Label.new()
		build_header.text = "Available Buildings"
		build_header.add_theme_font_size_override("font_size", 13)
		build_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
		vbox.add_child(build_header)

		for building_id in DataManager.buildings:
			var building: BuildingData = DataManager.buildings[building_id]
			if city.buildings.has(building_id):
				continue
			if city.level < building.required_capital_level:
				continue
			# Check if already in queue
			var in_queue := false
			for item in city.build_queue:
				if item.building_id == building_id:
					in_queue = true
					break
			if in_queue:
				continue

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)

			var build_btn := Button.new()
			build_btn.text = building.display_name
			build_btn.custom_minimum_size = Vector2(140, 28)
			build_btn.pressed.connect(_on_build_pressed.bind(city_id, building_id))

			# Check if can afford
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

	_add_separator(vbox)

	# Recruitment section
	var recruit_header := Label.new()
	recruit_header.text = "Recruitment"
	recruit_header.add_theme_font_size_override("font_size", 14)
	recruit_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(recruit_header)

	# Recruit queue
	for item in city.recruit_queue:
		var unit_data := DataManager.get_unit(item.unit_data_id)
		var uname := unit_data.display_name if unit_data else str(item.unit_data_id)
		var qlabel := Label.new()
		qlabel.text = "  [Training] " + uname + " (%d turns)" % item.turns_remaining
		qlabel.add_theme_font_size_override("font_size", 12)
		qlabel.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		vbox.add_child(qlabel)

	# Available units to recruit
	var recruitable := _get_recruitable_units(city)
	if recruitable.size() > 0 and city.recruit_queue.is_empty():
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

			var fs: FactionState = GameManager.state.faction_states.get(city.faction_id)
			var can_afford := fs != null and _can_afford_display(fs, unit_data.recruit_cost)
			var has_pop := city.population >= unit_data.squad_size
			if not can_afford or not has_pop:
				recruit_btn.disabled = true

			btn_row.add_child(recruit_btn)

			var cost_parts: Array[String] = []
			if unit_data.recruit_cost.size() > 0:
				cost_parts.append(_format_cost(unit_data.recruit_cost))
			cost_parts.append("Pop: " + str(unit_data.squad_size))
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

func _hide_city_panel() -> void:
	if city_panel:
		city_panel.visible = false

func _on_city_panel_close() -> void:
	var campaign: Node2D = get_parent().get_parent()
	if campaign and campaign.has_method("_close_city_panel"):
		campaign._close_city_panel()

func _on_build_pressed(city_id: StringName, building_id: StringName) -> void:
	if GameManager.city_system.start_building(city_id, building_id):
		_show_city_panel(city_id)
		_update_resource_display()

func _on_recruit_pressed(city_id: StringName, unit_data_id: StringName) -> void:
	if GameManager.city_system.start_recruitment(city_id, unit_data_id):
		_show_city_panel(city_id)
		_update_resource_display()

func _get_recruitable_units(city: CityState) -> Array[StringName]:
	var result: Array[StringName] = []
	for building_id in city.buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building == null:
			continue
		for unit_id in building.unlocks_units:
			# Only show units matching this faction
			var unit_data := DataManager.get_unit(unit_id)
			if unit_data and unit_data.faction_id == city.faction_id and not result.has(unit_id):
				result.append(unit_id)
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
	shard_tooltip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shard_tooltip.offset_left = -200.0
	shard_tooltip.offset_top = 50.0
	shard_tooltip.offset_right = -10.0
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
	shard_tooltip.visible = true

func _on_shard_label_mouse_exited() -> void:
	if shard_tooltip:
		shard_tooltip.visible = false

# ── Commander Panel ───────────────────────────────────────────

func _create_commander_panel() -> void:
	commander_panel = PanelContainer.new()
	commander_panel.name = "CommanderPanel"
	commander_panel.visible = false

	# Anchored top-left below top bar
	commander_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	commander_panel.offset_left = 10.0
	commander_panel.offset_top = 54.0
	commander_panel.offset_right = 270.0
	commander_panel.offset_bottom = 300.0
	commander_panel.custom_minimum_size = Vector2(260, 0)

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

	var vbox := VBoxContainer.new()
	vbox.name = "CommanderVBox"
	vbox.add_theme_constant_override("separation", 4)
	commander_panel.add_child(vbox)

	add_child(commander_panel)

func _update_commander_panel(army: ArmyState) -> void:
	if commander_panel == null:
		return

	commander_panel.visible = true
	var vbox: VBoxContainer = commander_panel.get_node("CommanderVBox")
	for child in vbox.get_children():
		child.queue_free()

	var faction := DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction.color if faction else Color.WHITE

	# Commander name
	var name_label := Label.new()
	name_label.text = army.commander_name if army.commander_name != "" else "Unknown Commander"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	vbox.add_child(name_label)

	# Faction
	var faction_name_label := Label.new()
	faction_name_label.text = faction.display_name if faction else str(army.faction_id)
	faction_name_label.add_theme_font_size_override("font_size", 12)
	faction_name_label.add_theme_color_override("font_color", faction_color.lightened(0.3))
	vbox.add_child(faction_name_label)

	_add_separator(vbox)

	# Army composition
	var total_atk := 0
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
		total_atk += ud.attack
		total_def += ud.defense
		total_spd += ud.speed
		if ud.tags.has("infantry"):
			infantry_count += 1
		if ud.tags.has("ranged"):
			ranged_count += 1
		if ud.tags.has("mage"):
			mage_count += 1
		if ud.tags.has("cavalry"):
			cavalry_count += 1
		for res_type in ud.upkeep_cost:
			total_upkeep[res_type] = total_upkeep.get(res_type, 0) + ud.upkeep_cost[res_type]

	var avg_spd := total_spd / maxi(1, army.units.size())

	# Stats
	var stats_label := Label.new()
	stats_label.text = "STR: %d  |  DEF: %d  |  SPD: %d" % [total_atk, total_def, avg_spd]
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

func _hide_commander_panel() -> void:
	if commander_panel:
		commander_panel.visible = false

# ── Settlement Founding UI ────────────────────────────────────

signal settlement_placement_requested(city_id: StringName)
signal settlement_placement_cancelled()

func _on_found_settlement_pressed(city_id: StringName) -> void:
	settlement_placement_requested.emit(city_id)
