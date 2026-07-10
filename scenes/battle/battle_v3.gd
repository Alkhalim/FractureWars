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

# Multi-select system
var selected_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
var selected_formation: BattleSimulatorV3.BattleFormationV3:
	get:
		return selected_formations[0] if selected_formations.size() > 0 else null
	set(value):
		selected_formations.clear()
		if value != null:
			selected_formations.append(value)
var _drag_select_start: Vector2 = Vector2.ZERO
var _drag_select_active: bool = false
var _drag_select_rect: Rect2 = Rect2()
var _terrain_hover_info: Dictionary = {}  # {pos: Vector2, text: String} or empty

# Group drag state
var _group_drag_active: bool = false
var _group_drag_offsets: Dictionary = {}  # formation -> Vector2 offset from click point

var player_side: int = 0
var is_player_attacker: bool = false
var _battle_loot: Dictionary = {}
var _battle_plunder: Dictionary = {} # Extra city plunder for raider factions
var _magic_projs: Array[Dictionary] = []
var _impact_marks: Node2D
const MAX_IMPACT_MARKS := 200

# --- Dust Particles ---
const DUST_COLORS := {
	Enums.BattleTerrain.OPEN:    Color(0.45, 0.40, 0.30, 0.5),
	Enums.BattleTerrain.FOREST:  Color(0.30, 0.35, 0.20, 0.4),
	Enums.BattleTerrain.ROCK:    Color(0.50, 0.48, 0.45, 0.5),
	Enums.BattleTerrain.WATER:   Color(0.35, 0.45, 0.55, 0.4),
	Enums.BattleTerrain.SAND:    Color(0.65, 0.55, 0.35, 0.5),
	Enums.BattleTerrain.MUD:     Color(0.40, 0.30, 0.18, 0.5),
	Enums.BattleTerrain.ICE:     Color(0.60, 0.70, 0.80, 0.4),
	Enums.BattleTerrain.CRYSTAL: Color(0.55, 0.40, 0.60, 0.4),
	Enums.BattleTerrain.BRUSH:   Color(0.38, 0.42, 0.28, 0.4),
}
var _dust_throttle: Dictionary = {} # formation instance_id -> tick counter

# --- Object Pools ---
var _label_pool: Array[Label] = []
var _particle_pool: Array[Polygon2D] = []
var _proj_pool: Array[ColorRect] = []

# --- Portrait Cache ---
var _portrait_cache: Dictionary = {} # unit_id -> Texture2D

# --- Formation Lookup ---
var _formation_lookup: Dictionary = {} # instance_id -> BattleFormationV3

# Simulation state
var sim_speed: float = 0.1
var sim_timer: float = 0.0
var is_simulating: bool = false
var skip_to_end: bool = false
var is_paused: bool = false

# Drag state for setup repositioning
var _dragging_formation: BattleSimulatorV3.BattleFormationV3 = null
var _drag_offset: Vector2 = Vector2.ZERO

# Battle camera pan/zoom
var _battle_panning := false
var _battle_pan_start := Vector2.ZERO
const BATTLE_MIN_ZOOM := 0.6
const BATTLE_MAX_ZOOM := 2.5

# Screen shake
var _shake_intensity: float = 0.0
var _shake_decay: float = 8.0

# Hover highlight state
var hovered_formation: BattleSimulatorV3.BattleFormationV3 = null
var _roster_rows: Dictionary = {} # formation instance_id -> row Control
var _roster_hp_refs: Dictionary = {} # formation instance_id -> {bar_fill, bar_bg, hp_lbl}
var _roster_structure_key: String = "" # Fingerprint to detect when full rebuild is needed

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
var _bar_bg_cache: ColorRect = null # cached BarBG lookup (was a recursive find_child per tick)
var strength_label: Label
var roster_panel: PanelContainer
var player_roster_container: VBoxContainer
var enemy_roster_container: VBoxContainer
var queue_panel: PanelContainer
var _queue_slot_labels: Array[Label] = []
var _queue_slot_x_buttons: Array[Button] = []
var _queue_palette_buttons: Array[Button] = []
var _queue_drag_command: int = -1  # Currently dragged QueueCommand (-1 = none)
var _queue_drag_label: Label = null  # Floating label during drag
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
		var tile = GameManager.state.hex_map.get_tile(battle_hex_pos)
		if tile:
			campaign_terrain = tile.terrain
	simulator.setup_terrain(campaign_terrain, battle_hex_pos)

	# Setup formations — player army always as side 0 (bottom)
	var atk_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(attacker_army.commander)
	var def_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(defender_army.commander)
	# Apply camp building bonuses (Sunblessed Sunfire Forge etc.)
	_apply_camp_building_bonuses(attacker_army, atk_cmd_bonuses)
	_apply_camp_building_bonuses(defender_army, def_cmd_bonuses)
	if is_player_attacker:
		simulator.setup_attacker_formations(attacker_army, atk_cmd_bonuses)
		simulator.setup_defender_formations(defender_army, def_cmd_bonuses)
	else:
		simulator.setup_attacker_formations(defender_army, def_cmd_bonuses)
		simulator.setup_defender_formations(attacker_army, atk_cmd_bonuses)

	# Spawn tower/siege formations from defensive buildings
	simulator.setup_city_defense_formations()

	# Set debt penalty flag on formations
	_apply_debt_flags()

	# Apply building bonuses to elderbeast formations (stats, ranged, aura, spawning)
	_apply_elderbeast_building_bonuses()

	# Build formation lookup dictionary for O(1) access by instance_id
	_build_formation_lookup()

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

	# --- Command Queue Panel (Right Side, below strength meter) ---
	queue_panel = _create_panel()
	queue_panel.name = "QueuePanel"
	queue_panel.anchor_left = 0
	queue_panel.anchor_right = 0
	queue_panel.anchor_top = 0
	queue_panel.anchor_bottom = 0
	queue_panel.offset_left = 4
	queue_panel.offset_right = 320
	queue_panel.offset_top = 96
	queue_panel.offset_bottom = 360
	queue_panel.grow_horizontal = Control.GROW_DIRECTION_END

	var queue_vbox := VBoxContainer.new()
	queue_vbox.add_theme_constant_override("separation", 3)
	queue_panel.add_child(queue_vbox)

	var queue_title := Label.new()
	queue_title.text = "COMMAND QUEUE"
	queue_title.add_theme_font_size_override("font_size", 12)
	queue_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	queue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_vbox.add_child(queue_title)

	# 6 queue slots
	_queue_slot_labels.clear()
	_queue_slot_x_buttons.clear()
	for i in 6:
		var slot_hbox := HBoxContainer.new()
		slot_hbox.add_theme_constant_override("separation", 4)

		var num_lbl := Label.new()
		num_lbl.text = "%d." % (i + 1)
		num_lbl.add_theme_font_size_override("font_size", 11)
		num_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
		num_lbl.custom_minimum_size = Vector2(18, 0)
		slot_hbox.add_child(num_lbl)

		var cmd_lbl := Label.new()
		cmd_lbl.text = "---"
		cmd_lbl.add_theme_font_size_override("font_size", 11)
		cmd_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		cmd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cmd_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		var captured_slot_idx := i
		cmd_lbl.gui_input.connect(_on_queue_slot_input.bind(captured_slot_idx))
		slot_hbox.add_child(cmd_lbl)
		_queue_slot_labels.append(cmd_lbl)

		var x_btn := Button.new()
		x_btn.text = "X"
		x_btn.add_theme_font_size_override("font_size", 10)
		x_btn.custom_minimum_size = Vector2(22, 20)
		x_btn.pressed.connect(_on_queue_slot_remove.bind(captured_slot_idx))
		slot_hbox.add_child(x_btn)
		_queue_slot_x_buttons.append(x_btn)

		queue_vbox.add_child(slot_hbox)

	# Command palette
	var palette_sep := HSeparator.new()
	palette_sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	queue_vbox.add_child(palette_sep)

	var palette_label := Label.new()
	palette_label.text = "COMMANDS"
	palette_label.add_theme_font_size_override("font_size", 11)
	palette_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	palette_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_vbox.add_child(palette_label)

	var palette_grid := GridContainer.new()
	palette_grid.columns = 3
	palette_grid.add_theme_constant_override("h_separation", 3)
	palette_grid.add_theme_constant_override("v_separation", 3)
	queue_vbox.add_child(palette_grid)

	_queue_palette_buttons.clear()
	for cmd_val in Enums.QueueCommand.values():
		var cmd_name: String = Enums.QueueCommand.keys()[cmd_val].capitalize().replace("_", " ")
		var pbtn := Button.new()
		pbtn.text = cmd_name
		pbtn.add_theme_font_size_override("font_size", 10)
		pbtn.custom_minimum_size = Vector2(90, 24)
		var captured_cmd: Enums.QueueCommand = cmd_val
		pbtn.pressed.connect(_on_queue_palette_pressed.bind(captured_cmd))
		# Drag-and-drop: start drag on mouse button press
		pbtn.gui_input.connect(func(event: InputEvent) -> void:
			if current_phase == Phase.SIMULATION:
				return
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_queue_drag_command = captured_cmd
				if _queue_drag_label == null:
					_queue_drag_label = Label.new()
					_queue_drag_label.add_theme_font_size_override("font_size", 11)
					_queue_drag_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
					_queue_drag_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
					_queue_drag_label.add_theme_constant_override("outline_size", 2)
					_queue_drag_label.z_index = 100
					_queue_drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
					ui_layer.add_child(_queue_drag_label)
				_queue_drag_label.text = QUEUE_COMMAND_NAMES.get(captured_cmd, "?")
				_queue_drag_label.visible = true
				_queue_drag_label.position = event.global_position + Vector2(10, -10)
		)
		palette_grid.add_child(pbtn)
		_queue_palette_buttons.append(pbtn)

	ui_layer.add_child(queue_panel)

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
	player_title.add_theme_font_size_override("font_size", 14)
	player_title.add_theme_color_override("font_color", Color(0.25, 0.75, 0.4))
	player_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	player_title.add_theme_constant_override("outline_size", 2)
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
	enemy_title.add_theme_font_size_override("font_size", 14)
	enemy_title.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
	enemy_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	enemy_title.add_theme_constant_override("outline_size", 2)
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
	# Build a fingerprint to detect structural changes (deaths, routs)
	var key := ""
	for f in player_formations:
		key += str(f.instance_id) + ("d" if f.is_dead or f.is_fled else "a") + ","
	key += "|"
	for f in enemy_formations:
		key += str(f.instance_id) + ("d" if f.is_dead or f.is_fled else "a") + ","
	if key != _roster_structure_key:
		# Structure changed - full rebuild
		_roster_structure_key = key
		_roster_rows.clear()
		_roster_hp_refs.clear()
		_rebuild_roster_side(player_roster_container, player_formations, true)
		_rebuild_roster_side(enemy_roster_container, enemy_formations, false)
	else:
		# Structure same - just update HP bars in place
		_update_roster_bars(player_formations, true)
		_update_roster_bars(enemy_formations, false)

func _update_roster_bars(formations: Array[BattleSimulatorV3.BattleFormationV3], is_player: bool) -> void:
	for f in formations:
		if not _roster_hp_refs.has(f.instance_id):
			continue
		var refs: Dictionary = _roster_hp_refs[f.instance_id]
		var hp_lbl: Label = refs.get("hp_lbl")
		var bar_fill: ColorRect = refs.get("bar_fill")
		var bar_bg: ColorRect = refs.get("bar_bg")
		var routing_lbl: Label = refs.get("routing_lbl")
		if hp_lbl:
			hp_lbl.text = "%d/%d  %d/%d ent" % [maxi(0, f.current_hp), f.max_hp, f.entities_alive, f.total_entities]
		if routing_lbl:
			routing_lbl.visible = f.is_routing and not f.is_dead and not f.is_fled
		if bar_fill and bar_bg and f.max_hp > 0:
			var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
			bar_fill.size = Vector2(bar_bg.size.x * hp_ratio, bar_bg.size.y)
			if f.is_routing:
				bar_fill.color = Color(0.85, 0.85, 0.85)  # White for routing/fleeing
			elif hp_ratio > 0.6:
				bar_fill.color = Color(0.25, 0.65, 0.35) if is_player else Color(0.7, 0.25, 0.2)
			elif hp_ratio > 0.3:
				bar_fill.color = Color(0.75, 0.65, 0.2)
			else:
				bar_fill.color = Color(0.8, 0.3, 0.2)

func _rebuild_roster_side(container: VBoxContainer, formations: Array[BattleSimulatorV3.BattleFormationV3], is_player: bool) -> void:
	for child in container.get_children():
		child.queue_free()

	# Group formations by unit type
	var groups: Array[Array] = []  # Array of [unit_data_id, Array[formation]]
	var group_map: Dictionary = {} # unit_data_id -> index in groups
	for f in formations:
		if group_map.has(f.unit_data_id):
			groups[group_map[f.unit_data_id]][1].append(f)
		else:
			group_map[f.unit_data_id] = groups.size()
			groups.append([f.unit_data_id, [f]])

	for group in groups:
		var unit_id: StringName = group[0]
		var group_formations: Array = group[1]
		var first_f: BattleSimulatorV3.BattleFormationV3 = group_formations[0]
		var all_dead := true
		for gf_idx in group_formations.size():
			var gf: BattleSimulatorV3.BattleFormationV3 = group_formations[gf_idx]
			if not gf.is_dead and not gf.is_fled:
				all_dead = false
				break

		var group_box := VBoxContainer.new()
		group_box.add_theme_constant_override("separation", 2)

		# Portrait + Name header row
		var header_hbox := HBoxContainer.new()
		header_hbox.add_theme_constant_override("separation", 6)

		# Full portrait (not cropped)
		var portrait_tex := _get_cached_portrait(unit_id)
		if portrait_tex:
			var portrait := TextureRect.new()
			portrait.texture = portrait_tex
			portrait.custom_minimum_size = Vector2(48, 60)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			portrait.mouse_filter = Control.MOUSE_FILTER_PASS
			if all_dead:
				portrait.modulate = Color(0.5, 0.45, 0.4, 0.6)
			header_hbox.add_child(portrait)

		# Name + count
		var name_col := VBoxContainer.new()
		name_col.add_theme_constant_override("separation", 0)
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_lbl := Label.new()
		var count_str := " (x%d)" % group_formations.size() if group_formations.size() > 1 else ""
		name_lbl.text = first_f.display_name + count_str
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		name_lbl.add_theme_constant_override("outline_size", 2)
		if all_dead:
			name_lbl.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35))
		elif is_player:
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.7))
		name_col.add_child(name_lbl)

		# Tags line
		var tags_lbl := Label.new()
		tags_lbl.text = ", ".join(first_f.tags)
		tags_lbl.add_theme_font_size_override("font_size", 10)
		tags_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		tags_lbl.add_theme_constant_override("outline_size", 2)
		tags_lbl.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		name_col.add_child(tags_lbl)

		header_hbox.add_child(name_col)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		tags_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		name_col.mouse_filter = Control.MOUSE_FILTER_PASS
		header_hbox.mouse_filter = Control.MOUSE_FILTER_STOP
		# Click on portrait/header selects ALL formations of this unit type
		var captured_group := group_formations.duplicate()
		var captured_is_player := is_player
		header_hbox.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and captured_is_player:
				selected_formations.clear()
				for gf in captured_group:
					if not gf.is_dead and not gf.is_fled:
						selected_formations.append(gf)
				if selected_formations.size() > 0:
					_update_unit_info(selected_formations[0])
				_populate_unit_list()
				_update_queue_display()
				renderer.queue_redraw()
		)
		group_box.add_child(header_hbox)

		# Individual HP bars for each formation of this type
		for f_idx in group_formations.size():
			var f: BattleSimulatorV3.BattleFormationV3 = group_formations[f_idx]
			var is_dead: bool = f.is_dead or f.is_fled
			var bar_row := HBoxContainer.new()
			bar_row.add_theme_constant_override("separation", 4)

			# Routing indicator
			var routing_lbl := Label.new()
			routing_lbl.text = "ROUTING"
			routing_lbl.add_theme_font_size_override("font_size", 9)
			routing_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
			routing_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			routing_lbl.add_theme_constant_override("outline_size", 2)
			routing_lbl.visible = f.is_routing and not is_dead
			bar_row.add_child(routing_lbl)

			# HP text
			var hp_lbl := Label.new()
			hp_lbl.text = "%d/%d  %d/%d ent" % [maxi(0, f.current_hp), f.max_hp, f.entities_alive, f.total_entities]
			hp_lbl.add_theme_font_size_override("font_size", 10)
			hp_lbl.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35) if is_dead else Color(0.6, 0.58, 0.5))
			hp_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			hp_lbl.add_theme_constant_override("outline_size", 2)
			hp_lbl.custom_minimum_size = Vector2(100, 0)
			bar_row.add_child(hp_lbl)

			# HP bar
			var bar_bg := ColorRect.new()
			bar_bg.custom_minimum_size = Vector2(170, 7)
			bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar_bg.color = Color(0.2, 0.18, 0.15, 0.8) if not is_dead else Color(0.15, 0.13, 0.12, 0.5)
			bar_row.add_child(bar_bg)

			var bar_fill := ColorRect.new()
			bar_fill.position = Vector2.ZERO
			if not is_dead and f.max_hp > 0:
				var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
				bar_fill.size = Vector2(170.0 * hp_ratio, 7)
				if f.is_routing:
					bar_fill.color = Color(0.85, 0.85, 0.85)  # White for routing/fleeing
				elif hp_ratio > 0.6:
					bar_fill.color = Color(0.25, 0.65, 0.35) if is_player else Color(0.7, 0.25, 0.2)
				elif hp_ratio > 0.3:
					bar_fill.color = Color(0.75, 0.65, 0.2)
				else:
					bar_fill.color = Color(0.8, 0.3, 0.2)
			else:
				bar_fill.size = Vector2.ZERO
			bar_bg.add_child(bar_fill)

			# Store refs for in-place updates
			_roster_hp_refs[f.instance_id] = {"hp_lbl": hp_lbl, "bar_fill": bar_fill, "bar_bg": bar_bg, "routing_lbl": routing_lbl}

			if is_dead:
				bar_row.modulate = Color(0.6, 0.55, 0.5, 0.6)

			# Mouse events per formation bar
			hp_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			bar_bg.mouse_filter = Control.MOUSE_FILTER_PASS
			bar_row.mouse_filter = Control.MOUSE_FILTER_STOP
			var captured_f := f
			bar_row.gui_input.connect(_on_roster_row_input.bind(captured_f, is_player))
			bar_row.mouse_entered.connect(_on_roster_row_hover.bind(captured_f))
			bar_row.mouse_exited.connect(_on_roster_row_hover.bind(null))

			if not is_dead:
				_roster_rows[f.instance_id] = bar_row

			group_box.add_child(bar_row)

		if all_dead:
			group_box.modulate = Color(0.6, 0.55, 0.5, 0.6)

		container.add_child(group_box)

func _on_roster_row_hover(f) -> void:
	if hovered_formation != f:
		hovered_formation = f
		_update_roster_highlight()
		renderer.queue_redraw()

func _on_roster_row_input(event: InputEvent, f: BattleSimulatorV3.BattleFormationV3, is_player: bool) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and is_player and not f.is_dead and not f.is_fled:
			if event.ctrl_pressed:
				# Ctrl+click: toggle in multi-select
				if f in selected_formations:
					selected_formations.erase(f)
				else:
					selected_formations.append(f)
				if selected_formations.size() > 0:
					_update_unit_info(selected_formations[-1])
				else:
					unit_info_panel.visible = false
				_populate_unit_list()
				_update_queue_display()
				renderer.queue_redraw()
			else:
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

	# Cached: recursive find_child ran every tick
	if _bar_bg_cache == null or not is_instance_valid(_bar_bg_cache):
		_bar_bg_cache = strength_meter_panel.find_child("BarBG", true, false) as ColorRect
	var bar_bg_node := _bar_bg_cache
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

func _input(event: InputEvent) -> void:
	# Handle command queue drag-and-drop
	if _queue_drag_command >= 0:
		if event is InputEventMouseMotion:
			if _queue_drag_label:
				_queue_drag_label.position = event.global_position + Vector2(10, -10)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Drop: check if over a queue slot
			var dropped := false
			for i in _queue_slot_labels.size():
				var slot_rect := _queue_slot_labels[i].get_global_rect()
				if slot_rect.has_point(event.global_position):
					# Insert command at this slot position
					var cmd: Enums.QueueCommand = _queue_drag_command as Enums.QueueCommand
					for sf in selected_formations:
						if sf.side != player_side or sf.is_dead or sf.is_fled:
							continue
						if i <= sf.command_queue.size() and sf.command_queue.size() < 6:
							sf.command_queue.insert(i, {"command": cmd, "duration": 100})
						elif i < sf.command_queue.size():
							sf.command_queue[i] = {"command": cmd, "duration": 100}
					_update_queue_display()
					dropped = true
					break
			# If not dropped on a slot, append to end (same as click behavior)
			if not dropped:
				_on_queue_palette_pressed(_queue_drag_command as Enums.QueueCommand)
			_queue_drag_command = -1
			if _queue_drag_label:
				_queue_drag_label.visible = false
			get_viewport().set_input_as_handled()
			return

	# Handle all setup phase mouse input in _input to prevent UI panels from consuming clicks
	if current_phase == Phase.SETUP:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			# Let Button controls (Begin Battle, orders, etc.) handle their own clicks
			var gui_hovered := get_viewport().gui_get_hovered_control()
			if gui_hovered is Button:
				return
			if event.pressed and _dragging_formation == null and not _drag_select_active and not _group_drag_active:
				var world_pos := _screen_to_world(event.position)
				_on_left_press(world_pos, event)
				if _dragging_formation != null or _drag_select_active or _group_drag_active:
					get_viewport().set_input_as_handled()
			elif not event.pressed:
				var world_pos := _screen_to_world(event.position)
				_on_left_release(world_pos)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and (_dragging_formation != null or _drag_select_active or _group_drag_active):
			var world_pos := _screen_to_world(event.position)
			_on_drag(world_pos)
			get_viewport().set_input_as_handled()
		return
	# Handle drag motion in _input so UI panels can't interrupt active drags
	if _dragging_formation != null:
		if event is InputEventMouseMotion:
			var world_pos := _screen_to_world(event.position)
			_on_drag(world_pos)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var world_pos := _screen_to_world(event.position)
			_on_left_release(world_pos)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Battle camera zoom with mouse wheel
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_battle_camera(0.1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_battle_camera(-0.1)
			get_viewport().set_input_as_handled()
			return
		# Middle-mouse pan
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_battle_panning = event.pressed
			_battle_pan_start = event.position
			get_viewport().set_input_as_handled()
			return

		var world_pos := _screen_to_world(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(world_pos, event)
			else:
				_on_left_release(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_right_click(world_pos)
	elif event is InputEventMouseMotion:
		if _battle_panning:
			var cam := $Camera2D
			var delta_pos: Vector2 = (_battle_pan_start - event.position) / cam.zoom
			cam.position += delta_pos
			_battle_pan_start = event.position
			# Clamp to field bounds with margin
			cam.position.x = clampf(cam.position.x, -50, BattleSimulatorV3.FIELD_WIDTH + 50)
			cam.position.y = clampf(cam.position.y, -50, BattleSimulatorV3.FIELD_HEIGHT + 50)
			get_viewport().set_input_as_handled()
			return
		if _drag_select_active or _group_drag_active:
			var world_pos := _screen_to_world(event.position)
			_on_drag(world_pos)
			get_viewport().set_input_as_handled()
			return
		var world_pos := _screen_to_world(event.position)
		_update_battlefield_hover(world_pos)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key_input(event)

func _zoom_battle_camera(amount: float) -> void:
	var cam := $Camera2D
	var new_zoom := clampf(cam.zoom.x + amount, BATTLE_MIN_ZOOM, BATTLE_MAX_ZOOM)
	cam.zoom = Vector2(new_zoom, new_zoom)

func _handle_key_input(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE:
			if current_phase == Phase.SIMULATION:
				_on_pause_toggle()
				get_viewport().set_input_as_handled()
			elif current_phase == Phase.SETUP:
				_on_begin_battle()
				get_viewport().set_input_as_handled()
		KEY_1:
			if current_phase == Phase.SIMULATION:
				_set_speed(1)
				get_viewport().set_input_as_handled()
		KEY_2:
			if current_phase == Phase.SIMULATION:
				_set_speed(2)
				get_viewport().set_input_as_handled()
		KEY_3:
			if current_phase == Phase.SIMULATION:
				_set_speed(4)
				get_viewport().set_input_as_handled()
		KEY_4:
			if current_phase == Phase.SIMULATION:
				_set_speed(8)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if selected_formations.size() > 0:
				_deselect_formation()
				get_viewport().set_input_as_handled()
		KEY_TAB:
			_cycle_player_formation(1 if not event.shift_pressed else -1)
			get_viewport().set_input_as_handled()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := $Camera2D as Camera2D
	var viewport_size := get_viewport_rect().size
	var cam_pos := cam.position
	var zoom := cam.zoom
	return cam_pos + (screen_pos - viewport_size / 2.0) / zoom

func _on_left_press(world_pos: Vector2, event: InputEvent = null) -> void:
	var ctrl_held: bool = event != null and event is InputEventMouseButton and event.ctrl_pressed
	if current_phase == Phase.SETUP:
		var f := _find_formation_at(world_pos)
		if f and f.side == player_side:
			if ctrl_held:
				# Ctrl+click: toggle formation in/out of multi-select
				if f in selected_formations:
					selected_formations.erase(f)
				else:
					selected_formations.append(f)
				if selected_formations.size() > 0:
					_update_unit_info(selected_formations[-1])
				else:
					unit_info_panel.visible = false
				_populate_unit_list()
				_update_queue_display()
				renderer.queue_redraw()
			elif f in selected_formations and selected_formations.size() > 1:
				# Clicked a formation already in multi-select — start group drag
				_group_drag_active = true
				_group_drag_offsets.clear()
				for sf in selected_formations:
					_group_drag_offsets[sf] = sf.position - world_pos
			else:
				# Single-select + start drag
				selected_formations.clear()
				selected_formations.append(f)
				_dragging_formation = f
				_drag_offset = f.position - world_pos
				_update_unit_info(f)
				_populate_unit_list()
				_update_queue_display()
				renderer.queue_redraw()
		elif f:
			# Clicked enemy formation — just select to view info
			if not ctrl_held:
				selected_formations.clear()
			selected_formations.append(f)
			_update_unit_info(f)
			_populate_unit_list()
			_update_queue_display()
			renderer.queue_redraw()
		else:
			if ctrl_held:
				return  # Ctrl+click on empty: do nothing
			# Start drag-select box
			_drag_select_start = world_pos
			_drag_select_active = true
			_drag_select_rect = Rect2(world_pos, Vector2.ZERO)

	elif current_phase == Phase.SIMULATION:
		var f := _find_formation_at(world_pos)
		if f and not f.is_dead and not f.is_fled:
			if ctrl_held:
				if f in selected_formations:
					selected_formations.erase(f)
				else:
					selected_formations.append(f)
				if selected_formations.size() > 0:
					_update_unit_info(selected_formations[-1])
				else:
					unit_info_panel.visible = false
			else:
				selected_formations.clear()
				selected_formations.append(f)
				_update_unit_info(f)
			_populate_unit_list()
			_update_queue_display()
			renderer.queue_redraw()
		elif not f:
			_deselect_formation()

func _on_left_release(world_pos: Vector2) -> void:
	if _drag_select_active:
		# Complete drag-box selection
		_drag_select_active = false
		var rect := _drag_select_rect.abs()
		if rect.size.length() > 5.0:
			selected_formations.clear()
			var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
			for f in player_formations:
				if f.is_dead or f.is_fled:
					continue
				if rect.has_point(f.position):
					selected_formations.append(f)
			if selected_formations.size() > 0:
				_update_unit_info(selected_formations[0])
			else:
				unit_info_panel.visible = false
			_populate_unit_list()
			_update_queue_display()
		else:
			# Tiny drag = click on empty space — deselect
			_deselect_formation()
		renderer.queue_redraw()
		return
	if _group_drag_active:
		_group_drag_active = false
		_group_drag_offsets.clear()
		renderer.queue_redraw()
		return
	if _dragging_formation != null:
		_dragging_formation = null
		renderer.queue_redraw()

func _on_drag(world_pos: Vector2) -> void:
	if _drag_select_active:
		# Update drag-box rectangle
		var tl := Vector2(minf(_drag_select_start.x, world_pos.x), minf(_drag_select_start.y, world_pos.y))
		var br := Vector2(maxf(_drag_select_start.x, world_pos.x), maxf(_drag_select_start.y, world_pos.y))
		_drag_select_rect = Rect2(tl, br - tl)
		renderer.queue_redraw()
		return
	if _group_drag_active:
		# Move all selected formations maintaining relative positions
		# Compute group bounding box to clamp
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for sf in selected_formations:
			if not _group_drag_offsets.has(sf):
				continue
			var target: Vector2 = world_pos + _group_drag_offsets[sf]
			min_x = minf(min_x, target.x)
			max_x = maxf(max_x, target.x)
			min_y = minf(min_y, target.y)
			max_y = maxf(max_y, target.y)
		# Clamp bounding box to deploy zone
		var side: int = selected_formations[0].side if selected_formations.size() > 0 else 0
		var zone_top := BattleSimulatorV3.DEPLOY_BOTTOM_Y if side == 0 else 20.0
		var zone_bot := BattleSimulatorV3.FIELD_HEIGHT - 20.0 if side == 0 else BattleSimulatorV3.DEPLOY_TOP_Y
		var shift := Vector2.ZERO
		if min_x < 20.0:
			shift.x = 20.0 - min_x
		elif max_x > BattleSimulatorV3.FIELD_WIDTH - 20.0:
			shift.x = BattleSimulatorV3.FIELD_WIDTH - 20.0 - max_x
		if min_y < zone_top:
			shift.y = zone_top - min_y
		elif max_y > zone_bot:
			shift.y = zone_bot - max_y
		for sf in selected_formations:
			if not _group_drag_offsets.has(sf):
				continue
			sf.position = world_pos + _group_drag_offsets[sf] + shift
			simulator._update_entity_world_positions(sf)
		renderer.queue_redraw()
		return
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
	if current_phase == Phase.SETUP and selected_formations.size() > 0:
		# Rotate all selected player formations to face the clicked point
		for sf in selected_formations:
			if sf.side != player_side:
				continue
			var diff := world_pos - sf.position
			if diff.length_squared() > 1.0:
				sf.rotation = atan2(diff.x, -diff.y)
				simulator._update_entity_world_positions(sf)
		renderer.queue_redraw()

const BATTLE_TERRAIN_NAMES := ["Open", "Forest", "Rock", "Water", "Sand", "Mud", "Ice", "Crystal", "Brush"]

func _update_battlefield_hover(world_pos: Vector2) -> void:
	var f := _find_formation_at(world_pos)
	var changed := f != hovered_formation
	if changed:
		hovered_formation = f
		_update_roster_highlight()

	# Terrain hover tooltip during setup
	if current_phase == Phase.SETUP:
		var terrain := simulator.get_terrain_at(world_pos)
		var terrain_idx := int(terrain)
		var t_name: String = BATTLE_TERRAIN_NAMES[terrain_idx] if terrain_idx < BATTLE_TERRAIN_NAMES.size() else "?"
		var spd_mod := BattleTerrainGen.get_speed_modifier(terrain)
		var def_bonus := BattleTerrainGen.get_defense_bonus(terrain)
		var passable := BattleTerrainGen.is_passable(terrain)
		var tip := t_name
		if not passable:
			tip += " (impassable)"
		else:
			if spd_mod != 1.0:
				tip += "  SPD:x%.1f" % spd_mod
			if def_bonus != 0:
				tip += "  DEF:%+d" % def_bonus
		_terrain_hover_info = {"pos": world_pos, "text": tip}
		changed = true
	elif _terrain_hover_info.size() > 0:
		_terrain_hover_info = {}
		changed = true

	if changed:
		renderer.queue_redraw()

func _update_roster_highlight() -> void:
	for fid in _roster_rows:
		var row = _roster_rows[fid]
		if not is_instance_valid(row):
			continue
		if hovered_formation and fid == hovered_formation.instance_id:
			row.modulate = Color(1.3, 1.2, 0.9, 1.0)
		else:
			row.modulate = Color(1, 1, 1, 1)

func _find_formation_at(world_pos: Vector2) -> BattleSimulatorV3.BattleFormationV3:
	var best: BattleSimulatorV3.BattleFormationV3 = null
	var best_dist := 999999.0

	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(simulator.attacker_formations)
	all_formations.append_array(simulator.defender_formations)

	for f in all_formations:
		if f.is_dead or f.is_fled:
			continue
		var dist := f.position.distance_to(world_pos)
		# Use entity radius + padding as click threshold (larger units = larger click area)
		var search_radius := BattleSimulatorV3.get_entity_radius(f) + 20.0
		if dist < search_radius and dist < best_dist:
			best_dist = dist
			best = f
	return best

func _deselect_formation() -> void:
	if selected_formations.is_empty():
		return
	selected_formations.clear()
	unit_info_panel.visible = false
	_populate_unit_list()
	_update_queue_display()
	renderer.queue_redraw()

func _on_formation_selected(f: BattleSimulatorV3.BattleFormationV3) -> void:
	selected_formation = f
	selected_formations.clear()
	selected_formations.append(f)
	_update_unit_info(f)
	_populate_unit_list()
	_update_queue_display()
	renderer.queue_redraw()

func _on_order_button_pressed(order: Enums.BattleOrder) -> void:
	var changed := false
	for sf in selected_formations:
		if sf.side == player_side and not sf.is_dead and not sf.is_fled:
			sf.current_order = order
			# If battle is running, immediate order overrides queue (mark exhausted)
			if current_phase == Phase.SIMULATION and sf.queue_locked:
				sf.queue_index = sf.command_queue.size()
				sf.focus_tag_filter = ""
			changed = true
	if changed:
		if selected_formations.size() > 0:
			_update_unit_info(selected_formations[-1])
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

# --- Command Queue UI ---

const QUEUE_COMMAND_NAMES := {
	Enums.QueueCommand.ADVANCE: "Advance",
	Enums.QueueCommand.HOLD: "Hold",
	Enums.QueueCommand.CHARGE: "Charge",
	Enums.QueueCommand.FLANK_LEFT: "Flank L",
	Enums.QueueCommand.FLANK_RIGHT: "Flank R",
	Enums.QueueCommand.RETREAT: "Retreat",
	Enums.QueueCommand.FALL_BACK: "Fall Back",
	Enums.QueueCommand.FOCUS_MAGE: "Focus Mage",
	Enums.QueueCommand.FOCUS_RANGED: "Focus Rng",
	Enums.QueueCommand.FOCUS_MONSTER: "Focus Mon",
	Enums.QueueCommand.FOCUS_CAVALRY: "Focus Cav",
	Enums.QueueCommand.FOCUS_INFANTRY: "Focus Inf",
}

const QUEUE_DURATION_CYCLE := [50, 100, 150, 200, 300, 0]  # 0 = until end

func _on_queue_palette_pressed(cmd: Enums.QueueCommand) -> void:
	if current_phase == Phase.SIMULATION:
		return  # Locked during battle
	for sf in selected_formations:
		if sf.side != player_side or sf.is_dead or sf.is_fled:
			continue
		if sf.command_queue.size() >= 6:
			continue
		sf.command_queue.append({"command": cmd, "duration": 100})
	_update_queue_display()

func _on_queue_slot_remove(slot_idx: int) -> void:
	if current_phase == Phase.SIMULATION:
		return
	for sf in selected_formations:
		if sf.side != player_side:
			continue
		if slot_idx < sf.command_queue.size():
			sf.command_queue.remove_at(slot_idx)
	_update_queue_display()

func _on_queue_slot_input(event: InputEvent, slot_idx: int) -> void:
	if current_phase == Phase.SIMULATION:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: cycle duration
		for sf in selected_formations:
			if sf.side != player_side:
				continue
			if slot_idx >= sf.command_queue.size():
				continue
			var current_dur: int = sf.command_queue[slot_idx].get("duration", 100)
			var next_idx := 0
			for di in QUEUE_DURATION_CYCLE.size():
				if QUEUE_DURATION_CYCLE[di] == current_dur:
					next_idx = (di + 1) % QUEUE_DURATION_CYCLE.size()
					break
			sf.command_queue[slot_idx]["duration"] = QUEUE_DURATION_CYCLE[next_idx]
		_update_queue_display()

func _update_queue_display() -> void:
	# Show queue of first selected player formation
	var ref_f: BattleSimulatorV3.BattleFormationV3 = null
	for sf in selected_formations:
		if sf.side == player_side and not sf.is_dead and not sf.is_fled:
			ref_f = sf
			break

	for i in 6:
		if ref_f and i < ref_f.command_queue.size():
			var slot: Dictionary = ref_f.command_queue[i]
			var cmd: Enums.QueueCommand = slot.get("command", Enums.QueueCommand.ADVANCE)
			var dur: int = slot.get("duration", 100)
			var dur_text := "%ds" % (dur / 10) if dur > 0 else "END"
			var cmd_name: String = QUEUE_COMMAND_NAMES.get(cmd, "?")
			_queue_slot_labels[i].text = "%s (%s)" % [cmd_name, dur_text]
			# Highlight active slot during simulation
			if current_phase == Phase.SIMULATION and ref_f.queue_locked and i == ref_f.queue_index and ref_f.queue_index < ref_f.command_queue.size():
				_queue_slot_labels[i].add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
			else:
				_queue_slot_labels[i].add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		else:
			_queue_slot_labels[i].text = "---"
			_queue_slot_labels[i].add_theme_color_override("font_color", Color(0.45, 0.4, 0.35))
		# Disable X buttons during simulation
		_queue_slot_x_buttons[i].disabled = current_phase == Phase.SIMULATION

	# Disable palette buttons during simulation
	for pbtn in _queue_palette_buttons:
		pbtn.disabled = current_phase == Phase.SIMULATION

func _update_unit_info(f: BattleSimulatorV3.BattleFormationV3) -> void:
	for child in unit_info_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Portrait + Name header
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	var portrait_tex := _get_cached_portrait(f.unit_data_id)
	if portrait_tex:
		var portrait := TextureRect.new()
		portrait.texture = portrait_tex
		portrait.custom_minimum_size = Vector2(48, 60)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		header_hbox.add_child(portrait)
	var name_label := Label.new()
	name_label.text = f.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(name_label)
	vbox.add_child(header_hbox)

	# Calculate live DPS from formation data (accounts for mana/ammo)
	var live_dps := 0.0
	if f.tags.has("mage"):
		var mana_ratio := f.current_mana / f.max_mana if f.max_mana > 0.0 else 1.0
		var eff_cd := f.ranged_cooldown_max
		if mana_ratio < 0.5:
			eff_cd = int(float(eff_cd) * lerpf(2.5, 1.3, mana_ratio * 2.0))
		live_dps = f.entities_alive * f.attack * 0.6 * 0.7 * (10.0 / eff_cd)
	elif f.tags.has("ranged"):
		# Show remaining-ammo-weighted DPS
		if f.current_ammo > 0:
			live_dps = f.entities_alive * f.attack * 0.6 * 0.8 * (10.0 / f.ranged_cooldown_max)
		else:
			live_dps = 0.0  # Out of ammo
	elif f.total_entities <= 1:
		live_dps = f.attack * 2.0
	else:
		var frontline := ceili(f.entities_alive * 0.35)
		live_dps = frontline * f.attack * 2.0
	var dps_text := "DPS:%d" % int(live_dps)

	var ud := DataManager.get_unit(f.unit_data_id)
	var base_def: int = ud.melee_defense if ud else f.defense
	var bonus_def: int = f.defense - base_def
	var def_text := "DEF:%d/%d/%d" % [f.melee_defense, f.projectile_defense, f.magic_defense]
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

	# Lock command queues on all player formations
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	for f in player_formations:
		if f.command_queue.size() > 0:
			f.queue_locked = true
			f.queue_index = 0
			f.queue_tick_start = 0

	var begin_btn := sim_panel.find_child("BeginBtn", true, false)
	if begin_btn:
		begin_btn.visible = false
	pause_btn.visible = true

	# Show retreat button during simulation
	var retreat_btn := order_panel.find_child("RetreatAllBtn", true, false)
	if retreat_btn:
		retreat_btn.visible = true

	_update_queue_display()

func _on_pause_toggle() -> void:
	is_paused = not is_paused
	pause_btn.text = "RESUME" if is_paused else "PAUSE"

func _on_speed_up() -> void:
	var current_multiplier := roundi(0.1 / sim_speed)
	# Cycle: 1x -> 2x -> 4x -> 8x -> 1x
	match current_multiplier:
		1:
			_set_speed(2)
		2:
			_set_speed(4)
		4:
			_set_speed(8)
		_:
			_set_speed(1)

func _on_skip() -> void:
	skip_to_end = true

func _set_speed(multiplier: int) -> void:
	sim_speed = 0.1 / float(multiplier)
	speed_label.text = "%dx" % multiplier
	# Flash the speed label to indicate the change
	speed_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	var tw := create_tween()
	tw.tween_property(speed_label, "theme_override_colors/font_color", Color(0.7, 0.65, 0.55), 0.4)

func _cycle_player_formation(direction: int) -> void:
	var player_formations := simulator.attacker_formations if player_side == 0 else simulator.defender_formations
	# Filter to alive formations only
	var alive: Array[BattleSimulatorV3.BattleFormationV3] = []
	for f in player_formations:
		if not f.is_dead and not f.is_fled:
			alive.append(f)
	if alive.is_empty():
		return
	if selected_formation == null or selected_formation.side != player_side:
		_on_formation_selected(alive[0])
		return
	var idx := -1
	for i in alive.size():
		if alive[i] == selected_formation:
			idx = i
			break
	if idx == -1:
		_on_formation_selected(alive[0])
		return
	var next_idx := (idx + direction) % alive.size()
	if next_idx < 0:
		next_idx += alive.size()
	_on_formation_selected(alive[next_idx])

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
			# Skip _process_visual_actions: the results screen follows
			# immediately, so spawning labels/projectiles/particles for up to
			# 5000 ticks in one frame was pure invisible cost (multi-second
			# freeze on large battles). Nothing else consumes the actions.
			simulator.simulate_tick()
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
		var remaining := maxi(0, BattleSimulatorV3.BATTLE_TIMER_TICKS - simulator.tick_count)
		var rem_sec := remaining / 10
		tick_label.text = "Tick: %d  Timer: %d:%02d" % [simulator.tick_count, rem_sec / 60, rem_sec % 60]
		_update_roster()
		_update_strength_meter()
		_update_queue_display()
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
				# Melee sparks
				_spawn_melee_sparks(def_id)
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
				_build_formation_lookup() # Rebuild lookup to include new formation
			"charge":
				# 3 dust particles per charge tick
				_spawn_dust_particles(action.id, 3)
			"rout":
				# 2 dust particles, throttled to every 3 ticks
				var rout_id: StringName = action.id
				var rout_tick: int = _dust_throttle.get(rout_id, 0)
				if rout_tick <= 0:
					_spawn_dust_particles(rout_id, 2)
					_dust_throttle[rout_id] = 3
				else:
					_dust_throttle[rout_id] = rout_tick - 1
			"move":
				# Dust only for sprinting infantry or cavalry with momentum
				var move_id: StringName = action.id
				var mf = _formation_lookup.get(move_id)
				if mf and (mf.is_sprinting or (mf.tags.has("cavalry") and mf.momentum > 0.5)):
					var move_tick: int = _dust_throttle.get(move_id, 0)
					if move_tick <= 0:
						_spawn_dust_particles(move_id, 2)
						_dust_throttle[move_id] = 2
					else:
						_dust_throttle[move_id] = move_tick - 1

# --- Object Pool Helpers ---

func _pool_get_label() -> Label:
	if _label_pool.size() > 0:
		var l: Label = _label_pool.pop_back()
		l.visible = true
		return l
	return Label.new()

func _pool_return_label(l: Label) -> void:
	l.visible = false
	if _label_pool.size() < 30:
		_label_pool.append(l)
	else:
		l.queue_free()

func _pool_get_proj() -> ColorRect:
	if _proj_pool.size() > 0:
		var p: ColorRect = _proj_pool.pop_back()
		p.visible = true
		return p
	return ColorRect.new()

func _pool_return_proj(p: ColorRect) -> void:
	p.visible = false
	if _proj_pool.size() < 50:
		_proj_pool.append(p)
	else:
		p.queue_free()

func _pool_get_particle() -> Polygon2D:
	if _particle_pool.size() > 0:
		var p: Polygon2D = _particle_pool.pop_back()
		p.visible = true
		p.modulate = Color(1, 1, 1, 1)
		p.scale = Vector2(1, 1)
		return p
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in 5:
		var a := TAU * float(k) / 5.0
		pts.append(Vector2(cos(a), sin(a)) * 2.0)
	poly.polygon = pts
	return poly

func _pool_return_particle(p: Polygon2D) -> void:
	p.visible = false
	if _particle_pool.size() < 150:
		_particle_pool.append(p)
	else:
		p.queue_free()

# --- Portrait Cache Helper ---

func _get_cached_portrait(unit_id: StringName) -> Texture2D:
	if _portrait_cache.has(unit_id):
		return _portrait_cache[unit_id]
	var tex := DataManager.get_unit_portrait(unit_id)
	_portrait_cache[unit_id] = tex
	return tex

# --- Damage / Projectile Spawning ---

func _spawn_damage_number(formation_id: StringName, damage: int) -> void:
	var pos := _get_formation_pos(formation_id)

	var label := _pool_get_label()
	label.text = str(damage)
	label.position = pos + Vector2(randf_range(-14, 14), -12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.2))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 10
	label.modulate = Color(1, 1, 1, 1)
	label.scale = Vector2(1.15, 1.15)
	if not label.is_inside_tree():
		effects_layer.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.parallel().tween_property(label, "scale", Vector2(0.8, 0.8), 0.9)
	tween.tween_callback(func(): label.scale = Vector2.ONE; _pool_return_label(label))

func _spawn_aura_damage_number(formation_id: StringName, damage: int) -> void:
	var pos := _get_formation_pos(formation_id)
	var label := _pool_get_label()
	label.text = str(damage)
	label.position = pos + Vector2(randf_range(-10, 10), -8)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.35, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 2)
	label.z_index = 10
	label.modulate = Color(1, 1, 1, 1)
	if not label.is_inside_tree():
		effects_layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 22, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(_pool_return_label.bind(label))

func _spawn_projectile_from_pos(from_pos: Vector2, to_pos: Vector2, is_hit: bool) -> void:
	var dir := (to_pos - from_pos).normalized()
	var arrow := _pool_get_particle()
	# Thin 4-point arrow polygon
	arrow.polygon = PackedVector2Array([
		Vector2(4, 0), Vector2(-2, -1.2), Vector2(-1, 0), Vector2(-2, 1.2)
	])
	arrow.color = Color(0.9, 0.8, 0.3) if is_hit else Color(0.5, 0.45, 0.3, 0.5)
	arrow.position = from_pos
	arrow.rotation = dir.angle()
	arrow.scale = Vector2(1, 1)
	arrow.z_index = 10
	arrow.modulate = Color(1, 1, 1, 1)
	if not arrow.is_inside_tree():
		effects_layer.add_child(arrow)

	var mark_alpha := 0.4 if is_hit else 0.2
	var tween := create_tween()
	tween.tween_property(arrow, "position", to_pos, 0.25)
	tween.tween_callback(func():
		_pool_return_particle(arrow)
		_spawn_arrow_ground_mark(to_pos, dir, mark_alpha, is_hit)
	)

func _spawn_projectile(attacker_id: StringName, defender_id: StringName) -> void:
	var from_pos := _get_formation_pos(attacker_id)
	var to_pos := _get_formation_pos(defender_id)
	_spawn_projectile_from_pos(from_pos, to_pos, true)

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
				# Impact burst particles
				_spawn_impact_burst(impact_pos, magic_col)
				# Bright flash
				_spawn_magic_flash(impact_pos, magic_col)
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

		# Spawn trail particle every 3rd frame
		if Engine.get_process_frames() % 3 == 0 and t < 0.85:
			var trail := _pool_get_particle()
			var body_node = p.node.get_child(1) if p.node.get_child_count() > 1 else null
			var trail_color := Color(0.4, 0.6, 1.0, 0.4)
			if body_node is Polygon2D:
				trail_color = Color(body_node.color.r, body_node.color.g, body_node.color.b, 0.4)
			trail.color = trail_color
			trail.position = final_pos
			trail.scale = Vector2(0.8, 0.8)
			trail.z_index = 9
			if not trail.is_inside_tree():
				effects_layer.add_child(trail)
			var tw := create_tween()
			tw.tween_property(trail, "modulate:a", 0.0, 0.3)
			tw.parallel().tween_property(trail, "scale", Vector2(0.2, 0.2), 0.3)
			tw.tween_callback(_pool_return_particle.bind(trail))

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

# --- Spell / Melee Effects ---

func _spawn_impact_burst(pos: Vector2, color: Color) -> void:
	for k in 5:
		var particle := _pool_get_particle()
		particle.color = Color(color.r, color.g, color.b, 0.7)
		particle.position = pos
		particle.scale = Vector2(1.0, 1.0)
		particle.z_index = 10
		if not particle.is_inside_tree():
			effects_layer.add_child(particle)
		var angle := TAU * float(k) / 5.0 + randf_range(-0.3, 0.3)
		var dist := randf_range(8.0, 18.0)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		var tw := create_tween()
		tw.tween_property(particle, "position", target, 0.3).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, 0.3)
		tw.parallel().tween_property(particle, "scale", Vector2(0.3, 0.3), 0.3)
		tw.tween_callback(_pool_return_particle.bind(particle))

func _spawn_magic_flash(pos: Vector2, color: Color) -> void:
	var flash := _pool_get_particle()
	# Circle shape for flash
	var pts := PackedVector2Array()
	for k in 12:
		var a := TAU * float(k) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * 2.0)
	flash.polygon = pts
	flash.color = Color(1.0, 1.0, 1.0, 0.9)
	flash.position = pos
	flash.scale = Vector2(1.0, 1.0)
	flash.z_index = 11
	flash.modulate = Color(1, 1, 1, 1)
	if not flash.is_inside_tree():
		effects_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector2(5.0, 5.0), 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.2)
	tw.tween_callback(_pool_return_particle.bind(flash))

func _spawn_melee_sparks(formation_id: StringName) -> void:
	var pos := _get_formation_pos(formation_id)
	if pos == Vector2.ZERO:
		return
	for k in 3:
		var spark := _pool_get_particle()
		spark.color = Color(1.0, 0.9, 0.5, 0.8)
		spark.position = pos + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		spark.scale = Vector2(0.5, 0.5)
		spark.z_index = 10
		if not spark.is_inside_tree():
			effects_layer.add_child(spark)
		var angle := randf() * TAU
		var target := spark.position + Vector2(cos(angle), sin(angle)) * randf_range(6.0, 12.0)
		var tw := create_tween()
		tw.tween_property(spark, "position", target, 0.15).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(spark, "modulate:a", 0.0, 0.15)
		tw.tween_callback(_pool_return_particle.bind(spark))

# --- Dust Particles ---

func _spawn_dust_particles(formation_id: StringName, count: int) -> void:
	var f: BattleSimulatorV3.BattleFormationV3 = _formation_lookup.get(formation_id)
	if f == null:
		return
	var terrain: Enums.BattleTerrain = simulator.get_terrain_at(f.position)
	var dust_color: Color = DUST_COLORS.get(terrain, DUST_COLORS[Enums.BattleTerrain.OPEN])
	var facing: Vector2 = f.get_facing_vector()
	# Spawn behind formation (opposite facing direction)
	var behind: Vector2 = -facing
	for k in count:
		var particle := _pool_get_particle()
		particle.color = dust_color
		var offset: Vector2 = behind * randf_range(3.0, 8.0) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		particle.position = f.position + offset
		particle.scale = Vector2(randf_range(0.6, 1.2), randf_range(0.6, 1.2))
		particle.z_index = 2
		particle.modulate = Color(1, 1, 1, 1)
		if not particle.is_inside_tree():
			effects_layer.add_child(particle)
		var drift: Vector2 = behind * randf_range(6.0, 14.0) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		var duration := randf_range(0.4, 0.7)
		var tw := create_tween()
		tw.tween_property(particle, "position", particle.position + drift, duration).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, duration)
		tw.parallel().tween_property(particle, "scale", Vector2(0.2, 0.2), duration)
		tw.tween_callback(_pool_return_particle.bind(particle))

# --- Impact Marks ---

func _spawn_arrow_ground_mark(pos: Vector2, dir: Vector2, alpha: float, is_hit: bool) -> void:
	var mark := Polygon2D.new()
	if is_hit:
		# Small fletching shape sticking up from impact point
		mark.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(-1.5, -3.5), Vector2(0, -2.5), Vector2(1.5, -3.5)
		])
	else:
		# Small flat arrow lying on ground
		mark.polygon = PackedVector2Array([
			Vector2(3, 0), Vector2(-1.5, -0.8), Vector2(-0.5, 0), Vector2(-1.5, 0.8)
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

	var res_names := {
		Enums.ResourceType.GOLD: "Gold",
		Enums.ResourceType.IRON: "Iron",
		Enums.ResourceType.WOOD: "Wood",
		Enums.ResourceType.FOOD: "Food",
		Enums.ResourceType.TECHNOLOGY: "Tech",
	}
	if player_won and _battle_loot.size() > 0:
		var loot_parts: Array[String] = []
		for res_type in _battle_loot:
			var amount: int = _battle_loot[res_type]
			if amount > 0:
				var rname: String = res_names.get(res_type, "???")
				loot_parts.append("+%d %s" % [amount, rname])
		if loot_parts.size() > 0:
			text += "\nSpoils of war: %s" % ", ".join(loot_parts)

	if player_won and _battle_plunder.size() > 0:
		var plunder_parts: Array[String] = []
		for res_type in _battle_plunder:
			var amount: int = _battle_plunder[res_type]
			if amount > 0:
				var rname: String = res_names.get(res_type, "???")
				plunder_parts.append("+%d %s" % [amount, rname])
		if plunder_parts.size() > 0:
			text += "\nPlundered from city: %s" % ", ".join(plunder_parts)

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

func _calculate_army_value(army: ArmyState) -> Dictionary:
	# Returns {gold: int, iron: int} based on total recruit cost of all units
	var total_gold := 0
	var total_iron := 0
	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			total_gold += ud.recruit_cost.get(Enums.ResourceType.GOLD, 0)
			total_iron += ud.recruit_cost.get(Enums.ResourceType.IRON, 0)
	return {gold = total_gold, iron = total_iron}

func _apply_battle_results() -> void:
	# Calculate army values BEFORE removing survivors (for loot scaling)
	var atk_value := _calculate_army_value(attacker_army)
	var def_value := _calculate_army_value(defender_army)
	var atk_strength: int = atk_value.gold + atk_value.iron
	var def_strength: int = def_value.gold + def_value.iron

	if is_player_attacker:
		_update_army_survivors(attacker_army, simulator.get_surviving_formations(0))
		_update_army_survivors(defender_army, simulator.get_surviving_formations(1))
	else:
		_update_army_survivors(defender_army, simulator.get_surviving_formations(0))
		_update_army_survivors(attacker_army, simulator.get_surviving_formations(1))

	# Strip garrison reinforcements from armies (they were temp-merged before battle)
	_strip_garrison_reinforcements(attacker_army)
	_strip_garrison_reinforcements(defender_army)

	# Grant veterancy XP to surviving units
	_grant_unit_veterancy_xp(attacker_army, simulator, 0 if is_player_attacker else 1, def_strength)
	_grant_unit_veterancy_xp(defender_army, simulator, 1 if is_player_attacker else 0, atk_strength)

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

	if not defender_alive:
		GameManager.remove_army(defender_army.army_id)
		# Mark garrison as defeated so a second army doesn't have to re-fight it this turn
		if defender_army.is_garrison:
			var garrison_city := GameManager.city_system.get_city_at_hex(battle_hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0

	# Garrison battle resolution — garrison can't retreat from city defenses
	var garrison_retreat := false
	if defender_army.is_garrison and defender_alive:
		GameManager.remove_army(defender_army.army_id)
		defender_alive = false
		var attacker_side := 0 if is_player_attacker else 1
		var attacker_won := simulator.winner_side == attacker_side
		if attacker_won and attacker_alive:
			# Attacker won — garrison eradicated, move attacker to city hex and start siege
			var garrison_city := GameManager.city_system.get_city_at_hex(battle_hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0
			attacker_army.hex_pos = battle_hex_pos
			GameManager.movement_system.invalidate_positions()
			attacker_army.movement_remaining = 0.0
			attacker_army.battle_exhausted = true
		elif attacker_alive:
			# Garrison won — retreat attacker away from city
			var retreat_hex := _find_garrison_retreat_hex(attacker_army, battle_hex_pos)
			if retreat_hex != Vector2i(-1, -1):
				attacker_army.hex_pos = retreat_hex
				GameManager.movement_system.invalidate_positions()
			attacker_army.movement_remaining = 0.0
			attacker_army.battle_exhausted = true
			garrison_retreat = true
			# Persist garrison damage — surviving garrison spawns with reduced HP
			var garrison_city := GameManager.city_system.get_city_at_hex(battle_hex_pos)
			if garrison_city:
				var total_max := 0
				var total_current := 0
				for unit in defender_army.units:
					var data := DataManager.get_unit(unit.unit_data_id)
					if data:
						total_max += data.max_hp
					total_current += unit.current_hp
				if total_max > 0:
					garrison_city.garrison_hp_ratio = clampf(float(total_current) / float(total_max), 0.01, 1.0)
		else:
			GameManager.remove_army(attacker_army.army_id)
	elif not attacker_alive:
		GameManager.remove_army(attacker_army.army_id)

	# Remove surviving garrison armies (non-garrison-retreat case)
	if defender_alive and defender_army.is_garrison:
		GameManager.remove_army(defender_army.army_id)
		defender_alive = false

	# Stalemate: both armies survive — separate and exhaust
	if attacker_alive and defender_alive:
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		# Defender was forced into battle — only penalize the aggressor
		# Defender keeps movement so they can act on their own turn
		_separate_armies_after_stalemate()

	# Faction mechanic: Thunderswarm storm fury rises from battles
	for fid in [attacker_faction_id, defender_faction_id]:
		if fid == &"thunderswarm":
			var tfs: FactionState = GameManager.state.faction_states.get(fid)
			if tfs:
				tfs.storm_fury = mini(tfs.storm_fury + 15, 100)

	# Thunderswarm dragon-kill grudge: killing their beast/dragon units angers them
	var thunderswarm_fid := &"thunderswarm"
	var all_formations: Array = []
	all_formations.append_array(simulator.attacker_formations)
	all_formations.append_array(simulator.defender_formations)
	for f_form in all_formations:
		var bf: BattleSimulatorV3.BattleFormationV3 = f_form
		var bf_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(bf.faction_id, bf.faction_id)
		if bf.faction_id != thunderswarm_fid and bf_parent != thunderswarm_fid:
			continue
		if not bf.is_dead:
			continue
		if bf.tags.has("beast") or bf.tags.has("monster"):
			# Determine who killed them (the opposing faction)
			var killer_fid: StringName = attacker_faction_id if bf.side == 1 else defender_faction_id
			if killer_fid != thunderswarm_fid and killer_fid != &"" and killer_fid != &"independent":
				GameManager.diplomacy_system.modify_standing(thunderswarm_fid, killer_fid, -8)

	# Faction mechanic: Sunblessed solar faith changes from battle results
	for battle_pair in [[attacker_faction_id, attacker_alive], [defender_faction_id, defender_alive]]:
		var bp_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(battle_pair[0], battle_pair[0])
		if battle_pair[0] == &"sunblessed" or bp_parent == &"sunblessed":
			var sfs: FactionState = GameManager.state.faction_states.get(battle_pair[0])
			if sfs:
				if battle_pair[1]:
					sfs.solar_faith = mini(sfs.solar_faith + 10, 100)
				else:
					sfs.solar_faith = maxi(sfs.solar_faith - 15, 0)

	if attacker_alive and not defender_alive and not garrison_retreat:
		EventBus.battle_resolved.emit(attacker_faction_id, battle_hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(attacker_faction_id, defender_faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id != attacker_faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_faction_id)
		elif city_at and city_at.faction_id == attacker_faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
		# Auto-claim shard after defeating guardians
		GameManager._try_claim_shard(battle_hex_pos, attacker_faction_id)
	elif garrison_retreat:
		EventBus.battle_resolved.emit(defender_faction_id, battle_hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(defender_faction_id, attacker_faction_id, 5)
	elif defender_alive and not attacker_alive:
		# Winning defender keeps full movement — they were attacked, not the aggressor
		defender_army.battle_exhausted = false
		defender_army.movement_remaining = defender_army.get_max_movement()
		EventBus.battle_resolved.emit(defender_faction_id, battle_hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(defender_faction_id, attacker_faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id == defender_faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
		# Auto-claim shard after defeating guardians
		GameManager._try_claim_shard(battle_hex_pos, defender_faction_id)

	# Battle loot — based on types of enemy units killed/routed
	_battle_loot.clear()
	_battle_plunder.clear()
	var winner_fid: StringName = &""
	var enemy_formations_ref: Array = []
	if attacker_alive and not defender_alive:
		winner_fid = attacker_faction_id
		enemy_formations_ref = simulator.defender_formations if is_player_attacker else simulator.attacker_formations
	elif defender_alive and not attacker_alive:
		winner_fid = defender_faction_id
		enemy_formations_ref = simulator.attacker_formations if is_player_attacker else simulator.defender_formations

	if winner_fid != &"":
		var loot_gold := 0
		var loot_iron := 0
		var loot_wood := 0
		var loot_food := 0
		var loot_tech := 0
		for ef in enemy_formations_ref:
			var form: BattleSimulatorV3.BattleFormationV3 = ef
			if not form.is_dead and not form.is_fled:
				continue # Only loot from killed/routed units
			var ud := DataManager.get_unit(form.unit_data_id)
			if not ud:
				continue
			var unit_value: int = ud.recruit_cost.get(Enums.ResourceType.GOLD, 0) + ud.recruit_cost.get(Enums.ResourceType.IRON, 0)
			# Base gold from every kill (spoils of war)
			loot_gold += int(unit_value * 0.08)
			# Tag-specific bonus loot
			for tag in form.tags:
				match tag:
					"infantry":
						loot_iron += int(unit_value * 0.06) # Armor and weapons salvage
					"cavalry":
						loot_food += int(unit_value * 0.08) # Mounts and provisions
						loot_gold += int(unit_value * 0.04) # Valuable tack
					"ranged":
						loot_wood += int(unit_value * 0.07) # Bows, bolts, shafts
					"construct":
						loot_iron += int(unit_value * 0.10) # Scrap metal
					"mage":
						loot_tech += int(unit_value * 0.08) # Arcane scrolls and knowledge
					"beast", "monster":
						loot_food += int(unit_value * 0.10) # Meat, hide, bone
						loot_wood += int(unit_value * 0.03) # Bone as building material

		var fs: FactionState = GameManager.state.faction_states.get(winner_fid)
		if fs:
			if loot_gold > 0:
				fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + loot_gold
				_battle_loot[Enums.ResourceType.GOLD] = loot_gold
			if loot_iron > 0:
				fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + loot_iron
				_battle_loot[Enums.ResourceType.IRON] = loot_iron
			if loot_wood > 0:
				fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + loot_wood
				_battle_loot[Enums.ResourceType.WOOD] = loot_wood
			if loot_food > 0:
				fs.resources[Enums.ResourceType.FOOD] = fs.resources.get(Enums.ResourceType.FOOD, 0) + loot_food
				_battle_loot[Enums.ResourceType.FOOD] = loot_food
			if loot_tech > 0:
				fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + loot_tech
				_battle_loot[Enums.ResourceType.TECHNOLOGY] = loot_tech

		# Skulloath / Shardhorde city plunder: extra loot when defeating a garrison
		var winner_parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(winner_fid, winner_fid)
		var is_raider := winner_fid in [&"skulloath", &"shardhorde"] or winner_parent in [&"skulloath", &"shardhorde"]
		var enemy_was_garrison: bool = (attacker_alive and not defender_alive and defender_army.is_garrison) or (defender_alive and not attacker_alive and attacker_army.is_garrison)
		if is_raider and enemy_was_garrison and fs:
			var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
			var city_level: int = city_at.level if city_at else 1
			var plunder_mult := 3
			var plunder_iron := (15 + city_level * 10) * plunder_mult
			var plunder_wood := (10 + city_level * 8) * plunder_mult
			var plunder_tech := (5 + city_level * 5) * plunder_mult
			var plunder_gold := (20 + city_level * 12) * plunder_mult
			fs.resources[Enums.ResourceType.IRON] = fs.resources.get(Enums.ResourceType.IRON, 0) + plunder_iron
			fs.resources[Enums.ResourceType.WOOD] = fs.resources.get(Enums.ResourceType.WOOD, 0) + plunder_wood
			fs.resources[Enums.ResourceType.TECHNOLOGY] = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0) + plunder_tech
			fs.resources[Enums.ResourceType.GOLD] = fs.resources.get(Enums.ResourceType.GOLD, 0) + plunder_gold
			_battle_plunder[Enums.ResourceType.IRON] = plunder_iron
			_battle_plunder[Enums.ResourceType.WOOD] = plunder_wood
			_battle_plunder[Enums.ResourceType.TECHNOLOGY] = plunder_tech
			_battle_plunder[Enums.ResourceType.GOLD] = plunder_gold

	# Build battle context for context-aware skill selection
	var base_context: Array[StringName] = []
	var tile = GameManager.state.hex_map.get_tile(battle_hex_pos)
	if tile:
		base_context.append(StringName("terrain_" + Enums.TerrainType.keys()[tile.terrain].to_lower()))
	if GameManager.city_system.get_city_at_hex(battle_hex_pos):
		base_context.append(&"in_city")

	# Collect used and faced unit tags from both sides
	var unit_tag_types := ["cavalry", "ranged", "mage", "infantry", "beast", "monster", "construct"]
	var atk_used_tags: Dictionary = {}
	var def_faced_tags: Dictionary = {}
	for f in simulator.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_used_tags[tag] = true
	for f in simulator.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_faced_tags[tag] = true
	var def_used_tags: Dictionary = {}
	var atk_faced_tags: Dictionary = {}
	for f in simulator.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_used_tags[tag] = true
	for f in simulator.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_faced_tags[tag] = true

	var atk_context: Array[StringName] = base_context.duplicate()
	atk_context.append(&"was_attacker")
	atk_context.append(&"battle_won" if attacker_alive else &"battle_lost")
	atk_context.append(StringName("enemy_" + defender_faction_id))
	for tag in def_faced_tags:
		atk_context.append(StringName("faced_" + tag))
	for tag in atk_used_tags:
		atk_context.append(StringName("used_" + tag))

	var def_context: Array[StringName] = base_context.duplicate()
	def_context.append(&"was_defender")
	def_context.append(&"battle_won" if defender_alive else &"battle_lost")
	def_context.append(StringName("enemy_" + attacker_faction_id))
	for tag in atk_faced_tags:
		def_context.append(StringName("faced_" + tag))
	for tag in def_used_tags:
		def_context.append(StringName("used_" + tag))

	# Commander XP and item drops (use cached refs since remove_army nulls them)
	if atk_commander:
		CommanderSystem.grant_battle_xp(atk_commander, def_strength, attacker_alive, atk_context)
		var atk_trait_changes := CommanderSystem.evaluate_traits(atk_commander, atk_context)
		for change in atk_trait_changes:
			EventBus.commander_trait_changed.emit(atk_commander, change.action, change.trait_id)
		if attacker_alive and not defender_alive:
			CommanderSystem.apply_item_drop(atk_commander, defender_faction_id)
	if def_commander:
		CommanderSystem.grant_battle_xp(def_commander, atk_strength, defender_alive, def_context)
		var def_trait_changes := CommanderSystem.evaluate_traits(def_commander, def_context)
		for change in def_trait_changes:
			EventBus.commander_trait_changed.emit(def_commander, change.action, change.trait_id)
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

func _grant_unit_veterancy_xp(army: ArmyState, sim: BattleSimulatorV3, side: int, enemy_strength: int) -> void:
	var formations := sim.get_surviving_formations(side)
	var formation_damage: Dictionary = {} # instance_id -> damage_dealt
	for f in formations:
		formation_damage[f.instance_id] = f.damage_dealt
	var base_xp := 8 + mini(enemy_strength / 50, 20)
	for unit in army.units:
		var dmg: int = formation_damage.get(unit.instance_id, 0)
		var damage_bonus := mini(dmg / 40, 10)
		unit.grant_xp(base_xp + damage_bonus)

func _find_garrison_retreat_hex(army: ArmyState, city_hex: Vector2i) -> Vector2i:
	# Find adjacent hex farthest from the city and passable (no water or mountains)
	var neighbors := HexHelper.get_neighbors(army.hex_pos)
	var best_hex := Vector2i(-1, -1)
	var best_dist := -1
	for n in neighbors:
		if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile = GameManager.state.hex_map.get_tile(n) if GameManager.state and GameManager.state.hex_map else null
		if tile and tile.terrain == Enums.TerrainType.WATER:
			continue
		if tile and tile.terrain == Enums.TerrainType.MOUNTAINS:
			continue
		var dist := HexHelper.hex_distance(n, city_hex)
		if dist > best_dist:
			best_dist = dist
			best_hex = n
	return best_hex

func _separate_armies_after_stalemate() -> void:
	# Defender stays at battle hex, attacker retreats to adjacent tile
	var retreat_hex := _find_garrison_retreat_hex(attacker_army, defender_army.hex_pos)
	if retreat_hex != Vector2i(-1, -1):
		attacker_army.hex_pos = retreat_hex
		GameManager.movement_system.invalidate_positions()
	else:
		# No valid retreat for attacker — push defender instead as fallback
		var def_retreat := _find_garrison_retreat_hex(defender_army, attacker_army.hex_pos)
		if def_retreat != Vector2i(-1, -1):
			defender_army.hex_pos = def_retreat
			GameManager.movement_system.invalidate_positions()

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

func _apply_camp_building_bonuses(army: ArmyState, cmd_bonuses: Dictionary) -> void:
	if army.camp_city_id == &"":
		return
	var camp_city: CityState = GameManager.state.cities.get(army.camp_city_id)
	if camp_city == null:
		return
	for bid in camp_city.buildings:
		var bdata: BuildingData = DataManager.get_building(bid)
		if bdata and bdata.special_effects.has("army_attack_bonus"):
			cmd_bonuses["attack_bonus"] = cmd_bonuses.get("attack_bonus", 0) + int(bdata.special_effects["army_attack_bonus"])

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
				f.melee_defense += 8
				f.projectile_defense += 8
				f.magic_defense += 8

			# T1: Feeding Tendrils — HP regen during melee combat (0.33 HP/tick)
			if beast.buildings.has(&"shard_conduit"):
				f.hp_regen_per_tick = 0.33
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

func _build_formation_lookup() -> void:
	_formation_lookup.clear()
	for f in simulator.attacker_formations:
		_formation_lookup[f.instance_id] = f
	for f in simulator.defender_formations:
		_formation_lookup[f.instance_id] = f

func _get_formation_pos(formation_id: StringName) -> Vector2:
	var f = _formation_lookup.get(formation_id)
	if f:
		return f.position
	return Vector2.ZERO

func _strip_garrison_reinforcements(army: ArmyState) -> void:
	if army == null:
		return
	var count: int = army.get_meta("garrison_reinforcement_count", 0)
	if count <= 0:
		return
	# Remove the last N units (garrison units were appended at the end)
	# But some may have died — only remove surviving garrison units from the tail
	var to_remove := mini(count, army.units.size())
	if to_remove > 0:
		army.units = army.units.slice(0, army.units.size() - to_remove)
	army.remove_meta("garrison_reinforcement_count")

func _return_to_campaign() -> void:
	GameManager.current_phase = Enums.GamePhase.CAMPAIGN
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")
	GameManager.call_deferred("_fade_in", 0.5)
