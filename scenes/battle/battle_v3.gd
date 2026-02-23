extends Node2D

const ORDER_NAMES := {
	Enums.BattleOrder.ADVANCE: "Advance",
	Enums.BattleOrder.HOLD: "Hold",
	Enums.BattleOrder.FLANK_LEFT: "Flank Left",
	Enums.BattleOrder.FLANK_RIGHT: "Flank Right",
	Enums.BattleOrder.CHARGE: "Charge",
	Enums.BattleOrder.RETREAT: "Retreat",
}

enum Phase { SETUP, SIMULATION, RESULT }

var current_phase: Phase = Phase.SETUP
var simulator: BattleSimulatorV3
var attacker_army: ArmyState
var defender_army: ArmyState
var attacker_faction_id: StringName
var defender_faction_id: StringName
var battle_hex_pos: Vector2i

var selected_formation: BattleSimulatorV3.BattleFormationV3 = null
var player_side: int = 0
var is_player_attacker: bool = false
var _battle_loot: Dictionary = {}
var _magic_projs: Array[Dictionary] = []
var _impact_marks: Node2D
const MAX_IMPACT_MARKS := 200

# Simulation state
var sim_speed: float = 0.1
var sim_timer: float = 0.0
var is_simulating: bool = false
var skip_to_end: bool = false
var is_paused: bool = false

# Drag state for setup repositioning
var _dragging_formation: BattleSimulatorV3.BattleFormationV3 = null
var _drag_offset: Vector2 = Vector2.ZERO

# Screen shake
var _shake_intensity: float = 0.0
var _shake_decay: float = 8.0

# UI nodes
var renderer: Node2D
var effects_layer: Node2D
var order_panel: PanelContainer
var unit_info_panel: PanelContainer
var sim_panel: PanelContainer
var result_panel: PanelContainer
var unit_list_container: VBoxContainer
var speed_label: Label
var tick_label: Label
var pause_btn: Button

# Strength meter and roster UI
var strength_meter_panel: PanelContainer
var strength_bar_player: ColorRect
var strength_bar_enemy: ColorRect
var strength_label: Label
var roster_panel: PanelContainer
var player_roster_container: VBoxContainer
var enemy_roster_container: VBoxContainer
var _player_power_initial: float = 0.0
var _enemy_power_initial: float = 0.0

func _ready() -> void:
	var attacker_id: StringName = GameManager.get_meta("battle_attacker")
	var defender_id: StringName = GameManager.get_meta("battle_defender")
	battle_hex_pos = GameManager.get_meta("battle_hex_pos")

	attacker_army = GameManager.state.armies.get(attacker_id)
	defender_army = GameManager.state.armies.get(defender_id)

	if attacker_army == null or defender_army == null:
		push_error("BattleV3: Missing army data!")
		_return_to_campaign()
		return

	attacker_faction_id = attacker_army.faction_id
	defender_faction_id = defender_army.faction_id

	is_player_attacker = attacker_faction_id == GameManager.state.player_faction_id
	player_side = 0

	AudioManager.play_faction_music(GameManager.state.player_faction_id, &"battle")

	# Create simulator
	simulator = BattleSimulatorV3.new()

	# Generate terrain
	var campaign_terrain := Enums.TerrainType.PLAINS
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(battle_hex_pos)
		if tile:
			campaign_terrain = tile.terrain
	simulator.setup_terrain(campaign_terrain, battle_hex_pos)

	# Setup formations — player army always as side 0 (bottom)
	var atk_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(attacker_army.commander)
	var def_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(defender_army.commander)
	if is_player_attacker:
		simulator.setup_attacker_formations(attacker_army, atk_cmd_bonuses)
		simulator.setup_defender_formations(defender_army, def_cmd_bonuses)
	else:
		simulator.setup_attacker_formations(defender_army, def_cmd_bonuses)
		simulator.setup_defender_formations(attacker_army, atk_cmd_bonuses)

	# Set debt penalty flag on formations
	_apply_debt_flags()

	# Apply building bonuses to elderbeast formations (stats, ranged, aura, spawning)
	_apply_elderbeast_building_bonuses()

	# AI assigns orders for enemy side
	simulator.assign_ai_orders(1)

	# Build scene
	_build_scene()
	_build_ui()
	_populate_unit_list()

func _build_scene() -> void:
	# Renderer (custom _draw)
	renderer = $BattleRenderer
	renderer.set_script(preload("res://scenes/battle/battle_renderer_v3.gd"))
	renderer.set("battle_scene", self)

	# Impact marks layer (below effects, persists for battle duration)
	_impact_marks = Node2D.new()
	_impact_marks.name = "ImpactMarks"
	_impact_marks.z_index = 1
	add_child(_impact_marks)

	# Effects layer for floating damage numbers, projectiles
	effects_layer = Node2D.new()
	effects_layer.name = "EffectsLayer"
	add_child(effects_layer)

	# Camera centered on field
	$Camera2D.position = Vector2(BattleSimulatorV3.FIELD_WIDTH / 2.0, BattleSimulatorV3.FIELD_HEIGHT / 2.0)
	var viewport_size := get_viewport_rect().size
	var zoom_x := viewport_size.x / (BattleSimulatorV3.FIELD_WIDTH + 80)
	var zoom_y := viewport_size.y / (BattleSimulatorV3.FIELD_HEIGHT + 80)
	var zoom_val := minf(zoom_x, zoom_y)
	zoom_val = clampf(zoom_val, 0.2, 3.0)
	$Camera2D.zoom = Vector2(zoom_val, zoom_val)

func _build_ui() -> void:
	var ui_layer: CanvasLayer = $UILayer

	# --- Order Panel (Left Side) ---
	order_panel = _create_panel()
	order_panel.name = "OrderPanel"
	order_panel.anchors_preset = Control.PRESET_LEFT_WIDE
	order_panel.anchor_left = 0
	order_panel.anchor_right = 0
	order_panel.offset_left = 4
	order_panel.offset_top = 4
	order_panel.offset_right = 220
	order_panel.offset_bottom = -4
	order_panel.grow_horizontal = Control.GROW_DIRECTION_END

	var order_vbox := VBoxContainer.new()
	order_vbox.add_theme_constant_override("separation", 4)
	order_panel.add_child(order_vbox)

	var order_title := Label.new()
	order_title.text = "FORMATIONS"
	order_title.add_theme_font_size_override("font_size", 14)
	order_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	order_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_vbox.add_child(order_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(200, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	order_vbox.add_child(scroll)

	unit_list_container = VBoxContainer.new()
	unit_list_container.add_theme_constant_override("separation", 3)
	scroll.add_child(unit_list_container)

	# Order buttons
	var order_sep := HSeparator.new()
	order_sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	order_vbox.add_child(order_sep)

	var order_label := Label.new()
	order_label.text = "SET ORDER"
	order_label.add_theme_font_size_override("font_size", 12)
	order_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_vbox.add_child(order_label)

	var order_grid := GridContainer.new()
	order_grid.columns = 2
	order_grid.add_theme_constant_override("h_separation", 4)
	order_grid.add_theme_constant_override("v_separation", 4)
	order_vbox.add_child(order_grid)

	var order_tooltips := {
		Enums.BattleOrder.ADVANCE: "Move toward the nearest enemy",
		Enums.BattleOrder.HOLD: "Stay in position, rotate to face enemy",
		Enums.BattleOrder.FLANK_LEFT: "Move diagonally left to flank the enemy",
		Enums.BattleOrder.FLANK_RIGHT: "Move diagonally right to flank the enemy",
		Enums.BattleOrder.CHARGE: "Rush at double speed. Bonus damage on first contact",
	}

	for order_val in ORDER_NAMES:
		if order_val == Enums.BattleOrder.RETREAT:
			continue
		var btn := Button.new()
		btn.text = ORDER_NAMES[order_val]
		btn.tooltip_text = order_tooltips.get(order_val, "")
		btn.custom_minimum_size = Vector2(95, 28)
		btn.add_theme_font_size_override("font_size", 11)
		var captured_order: Enums.BattleOrder = order_val
		btn.pressed.connect(_on_order_button_pressed.bind(captured_order))
		order_grid.add_child(btn)

	# Retreat All button — hidden during setup, visible during simulation
	var retreat_btn := Button.new()
	retreat_btn.name = "RetreatAllBtn"
	retreat_btn.text = "RETREAT ALL"
	retreat_btn.tooltip_text = "Order all your formations to retreat from battle"
	retreat_btn.custom_minimum_size = Vector2(200, 32)
	retreat_btn.add_theme_font_size_override("font_size", 12)
	retreat_btn.visible = false
	var retreat_style := StyleBoxFlat.new()
	retreat_style.bg_color = Color(0.4, 0.12, 0.1, 0.9)
	retreat_style.border_width_left = 1
	retreat_style.border_width_top = 1
	retreat_style.border_width_right = 1
	retreat_style.border_width_bottom = 1
	retreat_style.border_color = Color(0.7, 0.25, 0.2, 0.8)
	retreat_style.corner_radius_top_left = 3
	retreat_style.corner_radius_top_right = 3
	retreat_style.corner_radius_bottom_right = 3
	retreat_style.corner_radius_bottom_left = 3
	retreat_btn.add_theme_stylebox_override("normal", retreat_style)
	retreat_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	retreat_btn.pressed.connect(_on_retreat_all)
	order_vbox.add_child(retreat_btn)

	ui_layer.add_child(order_panel)

	# --- Strength Meter (Top Right) ---
	strength_meter_panel = _create_panel()
	strength_meter_panel.name = "StrengthMeterPanel"
	strength_meter_panel.anchor_left = 1
	strength_meter_panel.anchor_right = 1
	strength_meter_panel.anchor_top = 0
	strength_meter_panel.anchor_bottom = 0
	strength_meter_panel.offset_left = -320
	strength_meter_panel.offset_right = -4
	strength_meter_panel.offset_top = 4
	strength_meter_panel.offset_bottom = 90
	strength_meter_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var meter_vbox := VBoxContainer.new()
	meter_vbox.add_theme_constant_override("separation", 3)
	strength_meter_panel.add_child(meter_vbox)

	strength_label = Label.new()
	strength_label.text = "BATTLE STRENGTH"
	strength_label.add_theme_font_size_override("font_size", 11)
	strength_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	strength_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meter_vbox.add_child(strength_label)

	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(280, 16)
	bar_bg.color = Color(0.15, 0.12, 0.1, 0.9)
	bar_bg.name = "BarBG"
	meter_vbox.add_child(bar_bg)

	strength_bar_player = ColorRect.new()
	strength_bar_player.color = Color(0.25, 0.65, 0.35, 0.9)
	strength_bar_player.position = Vector2.ZERO
	strength_bar_player.size = Vector2(140, 16)
	bar_bg.add_child(strength_bar_player)

	strength_bar_enemy = ColorRect.new()
	strength_bar_enemy.color = Color(0.75, 0.25, 0.2, 0.9)
	strength_bar_enemy.position = Vector2(140, 0)
	strength_bar_enemy.size = Vector2(140, 16)
	bar_bg.add_child(strength_bar_enemy)

	# Commander bonuses info under strength meter
	var player_army := attacker_army if is_player_attacker else defender_army
	var enemy_army_ref := defender_army if is_player_attacker else attacker_army
	var player_bonuses := CommanderSystem.get_commander_army_bonuses(player_army.commander)
	var enemy_bonuses := CommanderSystem.get_commander_army_bonuses(enemy_army_ref.commander)

	var cmd_vbox := VBoxContainer.new()
	cmd_vbox.add_theme_constant_override("separation", 1)
	meter_vbox.add_child(cmd_vbox)

	_add_commander_bonus_line(cmd_vbox, player_army.commander, player_bonuses, Color(0.6, 0.8, 0.65))
	_add_commander_bonus_line(cmd_vbox, enemy_army_ref.commander, enemy_bonuses, Color(0.8, 0.6, 0.55))

	ui_layer.add_child(strength_meter_panel)

	# --- Army Roster (Right Side) ---
	roster_panel = _create_panel()
	roster_panel.name = "RosterPanel"
	roster_panel.anchor_left = 1
	roster_panel.anchor_right = 1
	roster_panel.anchor_top = 0
	roster_panel.anchor_bottom = 1
	roster_panel.offset_left = -320
	roster_panel.offset_right = -4
	roster_panel.offset_top = 96
	roster_panel.offset_bottom = -4
	roster_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_panel.add_child(roster_scroll)

	var roster_vbox := VBoxContainer.new()
	roster_vbox.add_theme_constant_override("separation", 2)
	roster_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_vbox)

	var player_title := Label.new()
	player_title.text = "YOUR FORCES"
	player_title.add_theme_font_size_override("font_size", 12)
	player_title.add_theme_color_override("font_color", Color(0.25, 0.75, 0.4))
	player_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster_vbox.add_child(player_title)

	player_roster_container = VBoxContainer.new()
	player_roster_container.add_theme_constant_override("separation", 1)
	roster_vbox.add_child(player_roster_container)

	var roster_sep := HSeparator.new()
	roster_sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	roster_vbox.add_child(roster_sep)

	var enemy_title := Label.new()
	enemy_title.text = "ENEMY FORCES"
	enemy_title.add_theme_font_size_override("font_size", 12)
	enemy_title.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
	enemy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster_vbox.add_child(enemy_title)

	enemy_roster_container = VBoxContainer.new()
	enemy_roster_container.add_theme_constant_override("separation", 1)
	roster_vbox.add_child(enemy_roster_container)

	ui_layer.add_child(roster_panel)

	# --- Unit Info Panel (Bottom Left) ---
	unit_info_panel = _create_panel()
	unit_info_panel.name = "UnitInfoPanel"
	unit_info_panel.visible = false
	unit_info_panel.anchors_preset = Control.PRESET_BOTTOM_LEFT
	unit_info_panel.anchor_left = 0
	unit_info_panel.anchor_top = 1
	unit_info_panel.anchor_right = 0
	unit_info_panel.anchor_bottom = 1
	unit_info_panel.offset_left = 4
	unit_info_panel.offset_top = -120
	unit_info_panel.offset_right = 220
	unit_info_panel.offset_bottom = -4
	ui_layer.add_child(unit_info_panel)

	# --- Sim Panel (Bottom Center) ---
	sim_panel = _create_panel()
	sim_panel.name = "SimPanel"
	sim_panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	sim_panel.anchor_left = 0.5
	sim_panel.anchor_top = 1
	sim_panel.anchor_right = 0.5
	sim_panel.anchor_bottom = 1
	sim_panel.offset_left = -180
	sim_panel.offset_top = -50
	sim_panel.offset_right = 180
	sim_panel.offset_bottom = -4
	sim_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var sim_hbox := HBoxContainer.new()
	sim_hbox.add_theme_constant_override("separation", 8)
	sim_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sim_panel.add_child(sim_hbox)

	tick_label = Label.new()
	tick_label.text = "Tick: 0"
	tick_label.add_theme_font_size_override("font_size", 13)
	tick_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	sim_hbox.add_child(tick_label)

	var begin_btn := Button.new()
	begin_btn.text = "BEGIN BATTLE"
	begin_btn.name = "BeginBtn"
	begin_btn.custom_minimum_size = Vector2(120, 32)
	begin_btn.pressed.connect(_on_begin_battle)
	sim_hbox.add_child(begin_btn)

	pause_btn = Button.new()
	pause_btn.text = "PAUSE"
	pause_btn.name = "PauseBtn"
	pause_btn.custom_minimum_size = Vector2(70, 32)
	pause_btn.visible = false
	pause_btn.pressed.connect(_on_pause_toggle)
	sim_hbox.add_child(pause_btn)

	speed_label = Label.new()
	speed_label.text = "1x"
	speed_label.add_theme_font_size_override("font_size", 13)
	speed_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	sim_hbox.add_child(speed_label)

	var speed_up_btn := Button.new()
	speed_up_btn.text = ">>"
	speed_up_btn.custom_minimum_size = Vector2(40, 32)
	speed_up_btn.pressed.connect(_on_speed_up)
	sim_hbox.add_child(speed_up_btn)

	var skip_btn := Button.new()
	skip_btn.text = "SKIP"
	skip_btn.custom_minimum_size = Vector2(60, 32)
	skip_btn.pressed.connect(_on_skip)
	sim_hbox.add_child(skip_btn)

	ui_layer.add_child(sim_panel)

	# --- Result Panel (Center, hidden initially) ---
	result_panel = _create_panel()
	result_panel.name = "ResultPanel"
	result_panel.visible = false
	result_panel.anchors_preset = Control.PRESET_CENTER
	result_panel.anchor_left = 0.5
	result_panel.anchor_top = 0.5
	result_panel.anchor_right = 0.5
	result_panel.anchor_bottom = 0.5
	result_panel.offset_left = -200
	result_panel.offset_top = -180
	result_panel.offset_right = 200
	result_panel.offset_bottom = 180
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui_layer.add_child(result_panel)

func _populate_unit_list() -> void:
	for child in unit_list_container.get_children():
		child.queue_free()

	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	for f in player_formations:
		var btn := Button.new()
		btn.text = "%s [%s]" % [f.display_name, ORDER_NAMES.get(f.current_order, "?")]
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(190, 24)
		if f == selected_formation:
			btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
		var captured_f := f
		btn.pressed.connect(_on_formation_selected.bind(captured_f))
		unit_list_container.add_child(btn)

	_update_roster()
	_update_strength_meter()

func _update_roster() -> void:
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	var enemy_formations := simulator.defender_formations if player_side == 0 else simulator.attacker_formations
	_rebuild_roster_side(player_roster_container, player_formations, true)
	_rebuild_roster_side(enemy_roster_container, enemy_formations, false)

func _rebuild_roster_side(container: VBoxContainer, formations: Array[BattleSimulatorV3.BattleFormationV3], is_player: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	for f in formations:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		var is_dead := f.is_dead or f.is_fled

		# Name + HP text
		var name_hbox := HBoxContainer.new()
		name_hbox.add_theme_constant_override("separation", 4)
		var name_lbl := Label.new()
		name_lbl.text = f.display_name
		name_lbl.add_theme_font_size_override("font_size", 11)
		if is_dead:
			name_lbl.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35))
		elif is_player:
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.7))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_hbox.add_child(name_lbl)

		# HP numbers + entity count
		var hp_text := "%d/%d HP  %d/%d" % [maxi(0, f.current_hp), f.max_hp, f.entities_alive, f.total_entities]
		var hp_lbl := Label.new()
		hp_lbl.text = hp_text
		hp_lbl.add_theme_font_size_override("font_size", 9)
		hp_lbl.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35) if is_dead else Color(0.65, 0.6, 0.55))
		name_hbox.add_child(hp_lbl)
		row.add_child(name_hbox)

		# HP bar
		var bar_bg := ColorRect.new()
		bar_bg.custom_minimum_size = Vector2(280, 6)
		bar_bg.color = Color(0.2, 0.18, 0.15, 0.8) if not is_dead else Color(0.15, 0.13, 0.12, 0.5)
		row.add_child(bar_bg)

		if not is_dead and f.max_hp > 0:
			var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
			var bar_fill := ColorRect.new()
			bar_fill.size = Vector2(280.0 * hp_ratio, 6)
			bar_fill.position = Vector2.ZERO
			if hp_ratio > 0.6:
				bar_fill.color = Color(0.25, 0.65, 0.35) if is_player else Color(0.7, 0.25, 0.2)
			elif hp_ratio > 0.3:
				bar_fill.color = Color(0.75, 0.65, 0.2)
			else:
				bar_fill.color = Color(0.8, 0.3, 0.2)
			bar_bg.add_child(bar_fill)

		if is_dead:
			row.modulate = Color(0.6, 0.55, 0.5, 0.6)

		# Right-click opens unit card, left-click selects (player only)
		# Ensure child controls pass mouse events through to the row
		name_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		hp_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		bar_bg.mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var captured_f := f
		row.gui_input.connect(_on_roster_row_input.bind(captured_f, is_player))

		container.add_child(row)

func _on_roster_row_input(event: InputEvent, f: BattleSimulatorV3.BattleFormationV3, is_player: bool) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and is_player and not f.is_dead and not f.is_fled:
			_on_formation_selected(f)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_update_unit_info(f)

func _add_commander_bonus_line(container: VBoxContainer, commander: CommanderState, bonuses: Dictionary, color: Color) -> void:
	if commander == null:
		return
	var parts: Array[String] = []
	var atk: int = bonuses.get("attack_bonus", 0)
	var def: int = bonuses.get("defense_bonus", 0)
	var spd: int = bonuses.get("speed_bonus", 0)
	var heal: int = bonuses.get("heal_per_turn", 0)
	if atk != 0:
		parts.append("ATK %+d" % atk)
	if def != 0:
		parts.append("DEF %+d" % def)
	if spd != 0:
		parts.append("SPD %+d" % spd)
	if heal != 0:
		parts.append("HEAL %+d" % heal)
	var bonus_text := ", ".join(parts) if parts.size() > 0 else "no bonuses"
	var lbl := Label.new()
	lbl.text = "%s (Lv%d): %s" % [commander.name, commander.level, bonus_text]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color)
	container.add_child(lbl)

func _calc_formation_power(f: BattleSimulatorV3.BattleFormationV3) -> float:
	# Power = HP_ratio * (attack + defense * 0.5 + speed * 0.3) * entities_alive
	# This weights offensive capability, survivability, and remaining manpower
	if f.is_dead or f.is_fled or f.max_hp <= 0:
		return 0.0
	var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
	var stat_value := float(f.attack) + float(f.defense) * 0.5 + float(f.speed) * 0.3
	if f.attack_range > 1:
		stat_value += float(f.attack_range) * 0.4  # Ranged units are more valuable
	return hp_ratio * stat_value * float(f.entities_alive)

func _calc_formation_power_max(f: BattleSimulatorV3.BattleFormationV3) -> float:
	var stat_value := float(f.attack) + float(f.defense) * 0.5 + float(f.speed) * 0.3
	if f.attack_range > 1:
		stat_value += float(f.attack_range) * 0.4
	return stat_value * float(f.total_entities)

func _update_strength_meter() -> void:
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	var enemy_formations := simulator.defender_formations if player_side == 0 else simulator.attacker_formations

	var player_power := 0.0
	var enemy_power := 0.0

	for f in player_formations:
		player_power += _calc_formation_power(f)
	for f in enemy_formations:
		enemy_power += _calc_formation_power(f)

	if _player_power_initial <= 0.0:
		for f in player_formations:
			_player_power_initial += _calc_formation_power_max(f)
	if _enemy_power_initial <= 0.0:
		for f in enemy_formations:
			_enemy_power_initial += _calc_formation_power_max(f)

	if _player_power_initial + _enemy_power_initial <= 0.0:
		return

	var bar_bg_node := strength_meter_panel.find_child("BarBG", true, false) as ColorRect
	if bar_bg_node == null:
		return
	var bar_width: float = bar_bg_node.custom_minimum_size.x

	# Proportional power: how much combat power each side has
	var total_current := player_power + enemy_power
	var player_ratio := 0.5
	if total_current > 0.0:
		player_ratio = player_power / total_current
	var enemy_ratio := 1.0 - player_ratio

	strength_bar_player.size = Vector2(bar_width * player_ratio, 16)
	strength_bar_player.position = Vector2.ZERO
	strength_bar_enemy.size = Vector2(bar_width * enemy_ratio, 16)
	strength_bar_enemy.position = Vector2(bar_width * player_ratio, 0)

	# Color intensity based on remaining power
	var p_pct := player_power / maxf(1.0, _player_power_initial)
	var e_pct := enemy_power / maxf(1.0, _enemy_power_initial)
	strength_bar_player.color = Color(0.25, 0.65, 0.35, 0.9) if p_pct > 0.4 else Color(0.75, 0.55, 0.2, 0.9)
	strength_bar_enemy.color = Color(0.75, 0.25, 0.2, 0.9) if e_pct > 0.4 else Color(0.6, 0.2, 0.15, 0.7)

	# Update label with percentage
	var player_pct_text := "%d%%" % int(p_pct * 100)
	var enemy_pct_text := "%d%%" % int(e_pct * 100)
	strength_label.text = "YOU %s  |  ENEMY %s" % [player_pct_text, enemy_pct_text]

func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.92)
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
	panel.add_theme_stylebox_override("panel", style)
	return panel

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var world_pos := _screen_to_world(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(world_pos)
			else:
				_on_left_release(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_right_click(world_pos)
	elif event is InputEventMouseMotion and _dragging_formation != null:
		var world_pos := _screen_to_world(event.position)
		_on_drag(world_pos)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := $Camera2D as Camera2D
	var viewport_size := get_viewport_rect().size
	var cam_pos := cam.position
	var zoom := cam.zoom
	return cam_pos + (screen_pos - viewport_size / 2.0) / zoom

func _on_left_press(world_pos: Vector2) -> void:
	if current_phase == Phase.SETUP:
		# Try to pick up a formation for dragging
		var f := _find_formation_at(world_pos)
		if f and f.side == player_side:
			selected_formation = f
			_dragging_formation = f
			_drag_offset = f.position - world_pos
			_update_unit_info(f)
			_populate_unit_list()
			renderer.queue_redraw()
		elif f:
			selected_formation = f
			_update_unit_info(f)
			_populate_unit_list()
			renderer.queue_redraw()

	elif current_phase == Phase.SIMULATION and is_paused:
		var f := _find_formation_at(world_pos)
		if f and not f.is_dead and not f.is_fled:
			selected_formation = f
			_update_unit_info(f)
			_populate_unit_list()
			renderer.queue_redraw()

func _on_left_release(_world_pos: Vector2) -> void:
	if _dragging_formation != null:
		_dragging_formation = null
		renderer.queue_redraw()

func _on_drag(world_pos: Vector2) -> void:
	if _dragging_formation == null:
		return
	var new_pos := world_pos + _drag_offset
	# Clamp to deploy zone
	if _dragging_formation.side == 0:  # Attacker: bottom
		new_pos.y = clampf(new_pos.y, BattleSimulatorV3.DEPLOY_BOTTOM_Y, BattleSimulatorV3.FIELD_HEIGHT - 20.0)
	else:  # Defender: top
		new_pos.y = clampf(new_pos.y, 20.0, BattleSimulatorV3.DEPLOY_TOP_Y)
	new_pos.x = clampf(new_pos.x, 20.0, BattleSimulatorV3.FIELD_WIDTH - 20.0)

	_dragging_formation.position = new_pos
	simulator._update_entity_world_positions(_dragging_formation)
	renderer.queue_redraw()

func _on_right_click(world_pos: Vector2) -> void:
	if current_phase == Phase.SETUP and selected_formation and selected_formation.side == player_side:
		# Rotate formation to face the clicked point
		var diff := world_pos - selected_formation.position
		if diff.length_squared() > 1.0:
			selected_formation.rotation = atan2(diff.x, -diff.y)
			simulator._update_entity_world_positions(selected_formation)
			renderer.queue_redraw()

func _find_formation_at(world_pos: Vector2) -> BattleSimulatorV3.BattleFormationV3:
	var best: BattleSimulatorV3.BattleFormationV3 = null
	var best_dist := 40.0  # Click radius

	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(simulator.attacker_formations)
	all_formations.append_array(simulator.defender_formations)

	for f in all_formations:
		if f.is_dead or f.is_fled:
			continue
		var dist := f.position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = f
	return best

func _on_formation_selected(f: BattleSimulatorV3.BattleFormationV3) -> void:
	selected_formation = f
	_update_unit_info(f)
	_populate_unit_list()
	renderer.queue_redraw()

func _on_order_button_pressed(order: Enums.BattleOrder) -> void:
	if selected_formation and selected_formation.side == player_side:
		selected_formation.current_order = order
		_update_unit_info(selected_formation)
		_populate_unit_list()
		renderer.queue_redraw()

func _on_retreat_all() -> void:
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	for f in player_formations:
		if not f.is_dead and not f.is_fled:
			f.current_order = Enums.BattleOrder.RETREAT
	if selected_formation:
		_update_unit_info(selected_formation)
	_populate_unit_list()
	renderer.queue_redraw()

func _update_unit_info(f: BattleSimulatorV3.BattleFormationV3) -> void:
	for child in unit_info_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = f.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(name_label)

	# Calculate live DPS from formation data
	var live_dps := 0.0
	if f.tags.has("mage"):
		live_dps = f.entities_alive * f.attack * 0.6 * 0.7 * (10.0 / f.ranged_cooldown_max)
	elif f.tags.has("ranged"):
		live_dps = f.entities_alive * f.attack * 0.6 * 0.8 * (10.0 / f.ranged_cooldown_max)
	elif f.total_entities <= 1:
		live_dps = f.attack * 2.0
	else:
		var frontline := ceili(f.entities_alive * 0.35)
		live_dps = frontline * f.attack * 2.0
	var dps_text := "DPS:%d" % int(live_dps)

	var ud := DataManager.get_unit(f.unit_data_id)
	var base_def: int = ud.defense if ud else f.defense
	var bonus_def: int = f.defense - base_def
	var def_text := "DEF:%d" % f.defense
	if bonus_def != 0:
		def_text += " (%+d)" % bonus_def

	var terrain_def := BattleTerrainGen.get_defense_bonus(simulator.get_terrain_at(f.position))
	if terrain_def != 0:
		def_text += " [terrain %+d]" % terrain_def

	var stats_label := Label.new()
	stats_label.text = "%s %s SPD:%d RNG:%d" % [dps_text, def_text, f.speed, f.attack_range]
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	vbox.add_child(stats_label)

	var hp_label := Label.new()
	hp_label.text = "HP: %d/%d  Entities: %d/%d" % [f.current_hp, f.max_hp, f.entities_alive, f.total_entities]
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.65))
	vbox.add_child(hp_label)

	var morale_label := Label.new()
	var morale_color := Color(0.4, 0.8, 0.35)
	if f.current_morale < f.base_morale * 0.3:
		morale_color = Color(0.85, 0.35, 0.3)
	elif f.current_morale < f.base_morale * 0.6:
		morale_color = Color(0.85, 0.75, 0.3)
	morale_label.text = "Morale: %d/%d%s" % [int(f.current_morale), f.base_morale, " ROUTING!" if f.is_routing else ""]
	morale_label.add_theme_font_size_override("font_size", 11)
	morale_label.add_theme_color_override("font_color", morale_color)
	vbox.add_child(morale_label)

	var order_label := Label.new()
	order_label.text = "Order: %s" % ORDER_NAMES.get(f.current_order, "?")
	order_label.add_theme_font_size_override("font_size", 11)
	order_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	vbox.add_child(order_label)

	# Resource bars info
	var res_parts: Array[String] = []
	if f.max_endurance > 0.0:
		res_parts.append("END:%d%%" % int(f.current_endurance / f.max_endurance * 100.0))
	if f.max_ammo > 0:
		res_parts.append("AMMO:%d/%d" % [f.current_ammo, f.max_ammo])
	if f.max_mana > 0.0:
		res_parts.append("MANA:%d%%" % int(f.current_mana / f.max_mana * 100.0))
	if res_parts.size() > 0:
		var res_label := Label.new()
		res_label.text = " ".join(res_parts)
		res_label.add_theme_font_size_override("font_size", 11)
		res_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
		vbox.add_child(res_label)

	unit_info_panel.add_child(vbox)
	unit_info_panel.visible = true

# --- Simulation Control ---

func _on_begin_battle() -> void:
	if current_phase != Phase.SETUP:
		return
	current_phase = Phase.SIMULATION
	is_simulating = true
	sim_timer = 0.0

	var begin_btn := sim_panel.find_child("BeginBtn", true, false)
	if begin_btn:
		begin_btn.visible = false
	pause_btn.visible = true

	# Show retreat button during simulation
	var retreat_btn := order_panel.find_child("RetreatAllBtn", true, false)
	if retreat_btn:
		retreat_btn.visible = true

func _on_pause_toggle() -> void:
	is_paused = not is_paused
	pause_btn.text = "RESUME" if is_paused else "PAUSE"

func _on_speed_up() -> void:
	if sim_speed <= 0.0125:
		sim_speed = 0.1
	else:
		sim_speed /= 2.0
	var speed_val := roundi(0.1 / sim_speed)
	speed_label.text = "%dx" % speed_val

func _on_skip() -> void:
	skip_to_end = true

func _process(delta: float) -> void:
	_update_magic_projectiles(delta)

	# Update screen shake
	if _shake_intensity > 0.01:
		_shake_intensity *= exp(-_shake_decay * delta)
		$Camera2D.offset = Vector2(randf_range(-_shake_intensity, _shake_intensity), randf_range(-_shake_intensity, _shake_intensity))
	else:
		_shake_intensity = 0.0
		$Camera2D.offset = Vector2.ZERO

	if current_phase != Phase.SIMULATION or not is_simulating:
		return

	if skip_to_end:
		for _i in simulator.max_ticks:
			var actions := simulator.simulate_tick()
			_process_visual_actions(actions)
			if simulator.is_finished:
				break
		_clear_magic_projectiles()
		_update_roster()
		_update_strength_meter()
		skip_to_end = false
		is_simulating = false
		_show_result()
		return

	if is_paused:
		return

	sim_timer += delta
	if sim_timer >= sim_speed:
		sim_timer -= sim_speed
		var actions := simulator.simulate_tick()
		_process_visual_actions(actions)
		tick_label.text = "Tick: %d" % simulator.tick_count
		_update_roster()
		_update_strength_meter()
		renderer.queue_redraw()

		if simulator.is_finished:
			is_simulating = false
			_show_result()

func _process_visual_actions(actions: Array[Dictionary]) -> void:
	for action in actions:
		match action.get("type", ""):
			"melee_hit":
				var def_id: StringName = action.defender
				var dmg: int = action.damage
				_spawn_damage_number(def_id, dmg)
				if dmg > 15:
					_shake_intensity = clampf(float(dmg) * 0.15, 2.0, 8.0)
				renderer.trigger_flash(action.attacker)
			"ranged_hit":
				var r_dmg: int = action.damage
				var r_def_id: StringName = action.defender
				var projectiles: Array = action.get("projectiles", [])
				if projectiles.size() > 0:
					for proj in projectiles:
						if proj.get("is_mage", false):
							var magic_color := _get_magic_color(proj.get("faction_id", &""))
							_spawn_magic_projectile(proj["from"], proj["to"], proj["hit"], magic_color, proj.get("speed_var", 1.0))
						else:
							_spawn_projectile_from_pos(proj["from"], proj["to"], proj["hit"])
				else:
					_spawn_projectile(action.attacker, r_def_id)
				if r_dmg > 0:
					_spawn_damage_number(r_def_id, r_dmg)
					renderer.trigger_flash(action.attacker)
			"aura_damage":
				_spawn_aura_damage_number(action.target, action.damage)
			"spawn":
				pass # Spawned unit will be rendered on next redraw

func _spawn_damage_number(formation_id: StringName, damage: int) -> void:
	var pos := Vector2.ZERO
	for f in simulator.attacker_formations + simulator.defender_formations:
		if f.instance_id == formation_id:
			pos = f.position
			break

	var label := Label.new()
	label.text = str(damage)
	label.position = pos + Vector2(randf_range(-12, 12), -10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	label.z_index = 10
	effects_layer.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 25, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)

func _spawn_aura_damage_number(formation_id: StringName, damage: int) -> void:
	var pos := Vector2.ZERO
	for f in simulator.attacker_formations + simulator.defender_formations:
		if f.instance_id == formation_id:
			pos = f.position
			break
	var label := Label.new()
	label.text = str(damage)
	label.position = pos + Vector2(randf_range(-8, 8), -6)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.9))
	label.z_index = 10
	effects_layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 18, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _spawn_projectile_from_pos(from_pos: Vector2, to_pos: Vector2, is_hit: bool) -> void:
	var proj := ColorRect.new()
	proj.size = Vector2(3, 3)
	proj.color = Color(0.9, 0.8, 0.3) if is_hit else Color(0.5, 0.45, 0.3, 0.5)
	proj.position = from_pos
	proj.z_index = 10
	effects_layer.add_child(proj)

	var dir := (to_pos - from_pos).normalized()
	var mark_alpha := 0.4 if is_hit else 0.2
	var tween := create_tween()
	tween.tween_property(proj, "position", to_pos, 0.3)
	tween.tween_callback(func():
		proj.queue_free()
		_spawn_arrow_mark(to_pos, dir, mark_alpha)
	)

func _spawn_projectile(attacker_id: StringName, defender_id: StringName) -> void:
	var from_pos := Vector2.ZERO
	var to_pos := Vector2.ZERO
	for f in simulator.attacker_formations + simulator.defender_formations:
		if f.instance_id == attacker_id:
			from_pos = f.position
		if f.instance_id == defender_id:
			to_pos = f.position

	var proj := ColorRect.new()
	proj.size = Vector2(4, 4)
	proj.color = Color(0.9, 0.8, 0.3)
	proj.position = from_pos
	proj.z_index = 10
	effects_layer.add_child(proj)

	var tween := create_tween()
	tween.tween_property(proj, "position", to_pos, 0.3)
	tween.tween_callback(proj.queue_free)

func _get_magic_color(faction_id: StringName) -> Color:
	match faction_id:
		&"empire":
			return Color(1.0, 0.5, 0.1)      # Fire/amber
		&"skulloath":
			return Color(0.7, 0.2, 0.9)      # Necrotic/purple
		&"tainted_jade":
			return Color(0.2, 0.9, 0.4)      # Nature/poison green
		&"gladehost":
			return Color(0.3, 0.8, 0.9)      # Frost/ice blue
		&"shardhorde":
			return Color(0.9, 0.1, 0.3)      # Shard/crimson
		_:
			return Color(0.4, 0.6, 1.0)      # Default arcane blue

func _spawn_magic_projectile(from_pos: Vector2, to_pos: Vector2, _is_hit: bool, magic_color: Color, speed_var: float) -> void:
	var container := Node2D.new()
	container.z_index = 10
	effects_layer.add_child(container)

	# Glow (semi-transparent circle)
	var glow := Polygon2D.new()
	var glow_pts := PackedVector2Array()
	for k in 12:
		var a := TAU * float(k) / 12.0
		glow_pts.append(Vector2(cos(a), sin(a)) * 4.5)
	glow.polygon = glow_pts
	glow.color = Color(magic_color.r, magic_color.g, magic_color.b, 0.2)
	container.add_child(glow)

	# Teardrop body (pointing right along +X, rotation orients it)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-4, 0), Vector2(-2, -2.2), Vector2(1.5, -1.6),
		Vector2(3.5, 0), Vector2(1.5, 1.6), Vector2(-2, 2.2),
	])
	body.color = magic_color
	container.add_child(body)

	_magic_projs.append({
		"node": container,
		"from": from_pos,
		"to": to_pos,
		"elapsed": 0.0,
		"duration": (0.5 + randf_range(0.0, 0.15)) * speed_var,
		"phase": randf() * TAU,
		"amplitude": randf_range(4.0, 10.0),
		"freq": randf_range(1.2, 2.2),
	})
	container.position = from_pos

func _update_magic_projectiles(delta: float) -> void:
	var i := _magic_projs.size() - 1
	while i >= 0:
		var p: Dictionary = _magic_projs[i]
		p.elapsed += delta
		var t: float = p.elapsed / p.duration
		if t >= 1.0:
			# Spawn crater mark at impact position
			var impact_pos: Vector2 = p.to
			if is_instance_valid(p.node):
				var magic_col: Color = Color(0.4, 0.6, 1.0, 0.25)
				# Extract color from the teardrop body child (index 1)
				if p.node.get_child_count() > 1:
					var body_node = p.node.get_child(1)
					if body_node is Polygon2D:
						magic_col = Color(body_node.color.r, body_node.color.g, body_node.color.b, 0.25)
				p.node.queue_free()
				_spawn_crater_mark(impact_pos, magic_col)
			_magic_projs.remove_at(i)
			i -= 1
			continue

		var from_p: Vector2 = p.from
		var to_p: Vector2 = p.to
		var base_pos := from_p.lerp(to_p, t)

		# Perpendicular oscillation for erratic movement
		var path_dir := (to_p - from_p).normalized()
		var perp := Vector2(-path_dir.y, path_dir.x)
		var osc: float = sin(t * TAU * p.freq + p.phase) * p.amplitude * (1.0 - t * 0.7)

		var final_pos := base_pos + perp * osc
		p.node.position = final_pos

		# Rotate teardrop to face movement direction
		var look_t := minf(t + 0.02, 1.0)
		var look_base := from_p.lerp(to_p, look_t)
		var look_osc: float = sin(look_t * TAU * p.freq + p.phase) * p.amplitude * (1.0 - look_t * 0.7)
		var look_pos := look_base + perp * look_osc
		var move_dir := look_pos - final_pos
		if move_dir.length_squared() > 0.01:
			p.node.rotation = move_dir.angle()

		i -= 1

func _clear_magic_projectiles() -> void:
	for p in _magic_projs:
		if is_instance_valid(p.node):
			p.node.queue_free()
	_magic_projs.clear()

# --- Impact Marks ---

func _spawn_arrow_mark(pos: Vector2, dir: Vector2, alpha: float) -> void:
	var mark := Polygon2D.new()
	var half_len := 2.0
	mark.polygon = PackedVector2Array([
		Vector2(-half_len, 0), Vector2(half_len, 0)
	])
	mark.color = Color(0.35, 0.25, 0.15, alpha)
	mark.position = pos
	mark.rotation = dir.angle()
	mark.z_index = 1
	_impact_marks.add_child(mark)
	_enforce_mark_limit()

func _spawn_crater_mark(pos: Vector2, color: Color) -> void:
	var mark := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 6:
		var a := TAU * float(k) / 6.0
		pts.append(Vector2(cos(a), sin(a)) * 3.0)
	mark.polygon = pts
	mark.color = color
	mark.position = pos
	mark.z_index = 1
	_impact_marks.add_child(mark)
	_enforce_mark_limit()

func _enforce_mark_limit() -> void:
	while _impact_marks.get_child_count() > MAX_IMPACT_MARKS:
		var oldest := _impact_marks.get_child(0)
		oldest.queue_free()
		_impact_marks.remove_child(oldest)

# --- Result ---

func _show_result() -> void:
	current_phase = Phase.RESULT
	pause_btn.visible = false

	for child in result_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	var player_won := simulator.winner_side == player_side
	var is_stalemate := simulator.winner_side == -1
	if is_stalemate:
		title.text = "STALEMATE!"
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.45))
	elif player_won:
		title.text = "VICTORY!"
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	else:
		title.text = "DEFEAT!"
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(0.85, 0.3, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep)

	var casualty_label := Label.new()
	casualty_label.add_theme_font_size_override("font_size", 12)
	casualty_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))

	var text := "YOUR FORCES:\n"
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	for f in player_formations:
		var status := "ALIVE"
		if f.is_dead:
			status = "KILLED"
		elif f.is_fled:
			status = "FLED"
		text += "  %s - %s (%d/%d HP, %d dmg dealt)\n" % [f.display_name, status, maxi(0, f.current_hp), f.max_hp, f.damage_dealt]

	text += "\nENEMY FORCES:\n"
	var enemy_formations := simulator.defender_formations if player_side == 0 else simulator.attacker_formations
	for f in enemy_formations:
		var status := "ALIVE"
		if f.is_dead:
			status = "KILLED"
		elif f.is_fled:
			status = "FLED"
		text += "  %s - %s (%d/%d HP, %d dmg dealt)\n" % [f.display_name, status, maxi(0, f.current_hp), f.max_hp, f.damage_dealt]

	var player_captives: int = simulator.captives.get(player_side, 0)
	if player_captives > 0:
		text += "\nCaptives gained: %d" % player_captives

	if player_won:
		var enemy_strength: int
		if is_player_attacker:
			enemy_strength = defender_army.get_total_strength()
		else:
			enemy_strength = attacker_army.get_total_strength()
		var loot_gold := int(enemy_strength * 0.1)
		var loot_iron := int(enemy_strength * 0.03)
		var loot_parts: Array[String] = []
		if loot_gold > 0:
			loot_parts.append("+%d Gold" % loot_gold)
		if loot_iron > 0:
			loot_parts.append("+%d Iron" % loot_iron)
		if loot_parts.size() > 0:
			text += "\nResources gained: %s" % ", ".join(loot_parts)

	casualty_label.text = text
	vbox.add_child(casualty_label)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(120, 36)
	continue_btn.pressed.connect(_on_continue)
	vbox.add_child(continue_btn)

	result_panel.add_child(vbox)
	result_panel.visible = true
	result_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(result_panel, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT)

func _on_continue() -> void:
	# Fade music out
	AudioManager.stop_music()

	# Create fullscreen black overlay and fade in
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.anchor_left = 0
	fade_rect.anchor_top = 0
	fade_rect.anchor_right = 1
	fade_rect.anchor_bottom = 1
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UILayer.add_child(fade_rect)
	# Ensure it renders on top of everything
	fade_rect.z_index = 100

	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, 2.0)
	tween.tween_callback(func():
		_apply_battle_results()
		_return_to_campaign()
	)

func _apply_battle_results() -> void:
	var atk_strength := attacker_army.get_total_strength()
	var def_strength := defender_army.get_total_strength()

	if is_player_attacker:
		_update_army_survivors(attacker_army, simulator.get_surviving_formations(0))
		_update_army_survivors(defender_army, simulator.get_surviving_formations(1))
	else:
		_update_army_survivors(defender_army, simulator.get_surviving_formations(0))
		_update_army_survivors(attacker_army, simulator.get_surviving_formations(1))

	# Handle elderbeast survival BEFORE removing dead armies
	# This may re-add the beast unit to an army if it "flees" with 1 HP
	_apply_elderbeast_battle_results()

	var attacker_alive := attacker_army.units.size() > 0
	var defender_alive := defender_army.units.size() > 0

	# Award captives to winner
	var winner_faction_id: StringName
	if is_player_attacker:
		winner_faction_id = attacker_faction_id if simulator.winner_side == 0 else defender_faction_id
	else:
		winner_faction_id = defender_faction_id if simulator.winner_side == 0 else attacker_faction_id
	var winner_captives: int = simulator.captives.get(simulator.winner_side, 0)
	if winner_captives > 0:
		var fs: FactionState = GameManager.state.faction_states.get(winner_faction_id)
		if fs:
			fs.resources[Enums.ResourceType.CAPTIVES] = fs.resources.get(Enums.ResourceType.CAPTIVES, 0) + winner_captives

	# Cache commanders before remove_army nulls them
	var atk_commander: CommanderState = attacker_army.commander
	var def_commander: CommanderState = defender_army.commander

	if not attacker_alive:
		GameManager.remove_army(attacker_army.army_id)
	if not defender_alive:
		GameManager.remove_army(defender_army.army_id)

	# Remove surviving garrison armies
	if defender_alive and defender_army.is_garrison:
		GameManager.remove_army(defender_army.army_id)
		defender_alive = false

	# Stalemate: both armies survive — separate and exhaust
	if attacker_alive and defender_alive:
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		defender_army.battle_exhausted = true
		defender_army.movement_remaining = 0.0
		_separate_armies_after_stalemate()

	if attacker_alive and not defender_alive:
		EventBus.battle_resolved.emit(attacker_faction_id, battle_hex_pos)
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id != attacker_faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_faction_id)
		elif city_at and city_at.faction_id == attacker_faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
		# Auto-claim shard after defeating guardians
		GameManager._try_claim_shard(battle_hex_pos, attacker_faction_id)
	elif defender_alive and not attacker_alive:
		EventBus.battle_resolved.emit(defender_faction_id, battle_hex_pos)
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id == defender_faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
		# Auto-claim shard after defeating guardians
		GameManager._try_claim_shard(battle_hex_pos, defender_faction_id)

	# Battle loot
	_battle_loot.clear()
	if attacker_alive and not defender_alive:
		var loot_gold := int(def_strength * 0.1)
		var loot_iron := int(def_strength * 0.03)
		if loot_gold > 0 or loot_iron > 0:
			var fs: FactionState = GameManager.state.faction_states.get(attacker_faction_id)
			if fs:
				if loot_gold > 0:
					fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + loot_gold
					_battle_loot[Enums.ResourceType.GOLD] = loot_gold
				if loot_iron > 0:
					fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + loot_iron
					_battle_loot[Enums.ResourceType.IRON] = loot_iron
	elif defender_alive and not attacker_alive:
		var loot_gold := int(atk_strength * 0.1)
		var loot_iron := int(atk_strength * 0.03)
		if loot_gold > 0 or loot_iron > 0:
			var fs: FactionState = GameManager.state.faction_states.get(defender_faction_id)
			if fs:
				if loot_gold > 0:
					fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + loot_gold
					_battle_loot[Enums.ResourceType.GOLD] = loot_gold
				if loot_iron > 0:
					fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + loot_iron
					_battle_loot[Enums.ResourceType.IRON] = loot_iron

	# Build battle context for context-aware skill selection
	var base_context: Array[StringName] = []
	var tile := GameManager.state.hex_map.get_tile(battle_hex_pos)
	if tile:
		base_context.append(StringName("terrain_" + Enums.TerrainType.keys()[tile.terrain].to_lower()))
	if GameManager.city_system.get_city_at_hex(battle_hex_pos):
		base_context.append(&"in_city")

	# Collect faced unit tags from both sides
	var def_faced_tags: Dictionary = {}
	for f in simulator.defender_formations:
		for tag in f.tags:
			if tag in ["cavalry", "ranged", "mage", "infantry", "beast"]:
				def_faced_tags[tag] = true
	var atk_faced_tags: Dictionary = {}
	for f in simulator.attacker_formations:
		for tag in f.tags:
			if tag in ["cavalry", "ranged", "mage", "infantry", "beast"]:
				atk_faced_tags[tag] = true

	var atk_context: Array[StringName] = base_context.duplicate()
	atk_context.append(&"was_attacker")
	atk_context.append(&"battle_won" if attacker_alive else &"battle_lost")
	atk_context.append(StringName("enemy_" + defender_faction_id))
	for tag in def_faced_tags:
		atk_context.append(StringName("faced_" + tag))

	var def_context: Array[StringName] = base_context.duplicate()
	def_context.append(&"was_defender")
	def_context.append(&"battle_won" if defender_alive else &"battle_lost")
	def_context.append(StringName("enemy_" + attacker_faction_id))
	for tag in atk_faced_tags:
		def_context.append(StringName("faced_" + tag))

	# Commander XP and item drops (use cached refs since remove_army nulls them)
	if atk_commander:
		CommanderSystem.grant_battle_xp(atk_commander, def_strength, attacker_alive, atk_context)
		if attacker_alive and not defender_alive:
			CommanderSystem.apply_item_drop(atk_commander, defender_faction_id)
	if def_commander:
		CommanderSystem.grant_battle_xp(def_commander, atk_strength, defender_alive, def_context)
		if defender_alive and not attacker_alive:
			CommanderSystem.apply_item_drop(def_commander, attacker_faction_id)

func _update_army_survivors(army: ArmyState, survivors: Array[BattleSimulatorV3.BattleFormationV3]) -> void:
	var surviving_ids: Dictionary = {}
	for f in survivors:
		surviving_ids[f.instance_id] = f.current_hp

	var updated_units: Array[UnitInstance] = []
	for unit in army.units:
		if surviving_ids.has(unit.instance_id):
			unit.current_hp = surviving_ids[unit.instance_id]
			updated_units.append(unit)
	army.units = updated_units

func _separate_armies_after_stalemate() -> void:
	# Move each army 1 tile away from the other
	var atk_pos := attacker_army.hex_pos
	var def_pos := defender_army.hex_pos
	var hex_map := GameManager.state.hex_map

	# Find a valid neighbor tile for the attacker that's farther from the defender
	var best_atk := atk_pos
	var best_atk_dist := 0
	for neighbor in HexHelper.get_neighbors(atk_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(neighbor) if hex_map else null
		if tile and tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(neighbor, def_pos)
		if dist > best_atk_dist:
			best_atk_dist = dist
			best_atk = neighbor

	# Find a valid neighbor tile for the defender that's farther from the attacker
	var best_def := def_pos
	var best_def_dist := 0
	for neighbor in HexHelper.get_neighbors(def_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(neighbor) if hex_map else null
		if tile and tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(neighbor, atk_pos)
		if dist > best_def_dist:
			best_def_dist = dist
			best_def = neighbor

	attacker_army.hex_pos = best_atk
	defender_army.hex_pos = best_def

func _apply_elderbeast_battle_results() -> void:
	# Sync elderbeast HP from battle formations and handle survival mechanic
	for army in [attacker_army, defender_army]:
		if army.elderbeast_id == &"":
			continue
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(army.elderbeast_id)
		if beast == null:
			continue

		# Find the elderbeast's UnitInstance in the army
		var beast_unit: UnitInstance = null
		for unit in army.units:
			if unit.instance_id == beast.unit_instance_id:
				beast_unit = unit
				break

		if beast_unit == null:
			# Beast was killed in battle (removed from units by _update_army_survivors)
			# Check if other units survived or fled
			var other_units_alive: bool = army.units.size() > 0
			if other_units_alive and not beast.is_injured():
				# Beast flees with 1 HP and becomes injured for 3 turns
				beast.hp = 1
				beast.injured_turns = 3
				beast.movement_remaining = 0.0
				# Re-add the beast UnitInstance to the army
				var unit_data := DataManager.get_unit(beast.get_unit_data_id())
				if unit_data:
					var instance := UnitInstance.new()
					instance.instance_id = beast.unit_instance_id
					instance.unit_data_id = unit_data.id
					instance.current_hp = 1
					army.units.insert(0, instance)
			else:
				# Beast dies outright (injured and attacked, or entire army wiped)
				beast.hp = 0
				GameManager.state.elderbeasts.erase(beast.beast_id)
				EventBus.elderbeast_destroyed.emit(beast.beast_id, beast.faction_id)
				army.elderbeast_id = &""
		else:
			# Beast survived — sync HP back
			beast.hp = beast_unit.current_hp

func _apply_debt_flags() -> void:
	# Check if each side's faction is in gold debt and flag their formations
	for faction_id in [attacker_faction_id, defender_faction_id]:
		var fs: FactionState = GameManager.state.faction_states.get(faction_id)
		var in_debt: bool = fs != null and fs.resources.get(Enums.ResourceType.GOLD, 0) < 0
		if not in_debt:
			continue
		var formations: Array = simulator.attacker_formations if faction_id == attacker_faction_id else simulator.defender_formations
		for f in formations:
			f.faction_in_debt = true

func _apply_elderbeast_building_bonuses() -> void:
	# Apply building bonuses to elderbeast formations in battle
	var all_formations: Array = []
	all_formations.append_array(simulator.attacker_formations)
	all_formations.append_array(simulator.defender_formations)
	for f in all_formations:
		if not f.tags.has("beast"):
			continue
		# Find the corresponding elderbeast
		for beast_id in GameManager.state.elderbeasts:
			var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
			if beast.unit_instance_id != f.instance_id:
				continue

			# T1: Chitin Walls — +8 defense
			if beast.buildings.has(&"chitin_walls"):
				f.defense += 8

			# T1: Feeding Tendrils — HP regen while fighting (1 HP/tick, only during combat)
			if beast.buildings.has(&"shard_conduit"):
				f.hp_regen_per_tick = 1.0
				f.regen_requires_combat = true

			# T1: Chitin Forge — +10 attack
			if beast.buildings.has(&"crystal_forge"):
				f.attack += 10

			# T1: Brood Chamber — +60 max HP
			if beast.buildings.has(&"crystal_nursery"):
				f.max_hp += 60
				f.current_hp += 60
				f.front_entity_hp += 60

			# T1: Crystal Tap — +25 fear radius
			if beast.buildings.has(&"shard_harvester"):
				f.fear_radius += 25

			# T2: Resonance Spire — adds ranged attack (range 3, mana-based)
			if beast.buildings.has(&"resonance_core"):
				if f.attack_range < 3:
					f.attack_range = 3
					if not f.tags.has("ranged"):
						f.tags.append("ranged")
					f.ranged_cooldown_max = 10
					f.max_ammo = 0 # Unlimited crystal shots (uses mana instead)
					f.max_mana = BattleSimulatorV3.MANA_MAX
					f.current_mana = BattleSimulatorV3.MANA_MAX
					f.fire_deploy_timer = 8
					f.is_deployed = false

			# T2: War Crest — +12 morale aura
			if beast.buildings.has(&"hive_spire"):
				f.morale_aura += 12

			# T3: Shard Heart — damage aura + stronger ranged
			if beast.buildings.has(&"resonance_amplifier"):
				f.damage_aura_radius = 120.0
				f.damage_aura_damage = 3.0
				if f.attack_range >= 3:
					f.attack_range = 5
					f.attack += 8

			# T3: Apex Den — spawns crystal swarmlings every 120 ticks
			if beast.buildings.has(&"elder_breeding_ground"):
				f.spawn_unit_data_id = &"crystal_swarmling"
				f.spawn_interval = 120
				f.spawn_counter = 120

			break

func _return_to_campaign() -> void:
	GameManager.current_phase = Enums.GamePhase.CAMPAIGN
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")
