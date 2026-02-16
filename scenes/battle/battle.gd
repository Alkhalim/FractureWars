extends Node2D

const CELL_SIZE := 40
const GRID_WIDTH := 20
const GRID_HEIGHT := 16

# Terrain colors
const TERRAIN_COLORS := {
	Enums.BattleTerrain.OPEN:    Color(0.12, 0.11, 0.16, 1),
	Enums.BattleTerrain.FOREST:  Color(0.1, 0.2, 0.1, 1),
	Enums.BattleTerrain.ROCK:    Color(0.22, 0.2, 0.2, 1),
	Enums.BattleTerrain.WATER:   Color(0.08, 0.12, 0.25, 1),
	Enums.BattleTerrain.SAND:    Color(0.22, 0.2, 0.13, 1),
	Enums.BattleTerrain.MUD:     Color(0.14, 0.12, 0.08, 1),
	Enums.BattleTerrain.ICE:     Color(0.18, 0.22, 0.28, 1),
	Enums.BattleTerrain.CRYSTAL: Color(0.2, 0.1, 0.25, 1),
	Enums.BattleTerrain.BRUSH:   Color(0.13, 0.15, 0.11, 1),
}

const COLOR_DEPLOY_ZONE := Color(0.14, 0.18, 0.12, 1)
const COLOR_DEPLOY_HIGHLIGHT := Color(0.22, 0.32, 0.18, 1)
const COLOR_ENEMY_ZONE := Color(0.18, 0.12, 0.12, 1)
const COLOR_GRID_LINE := Color(0.25, 0.22, 0.18, 0.6)
const COLOR_ATTACKER := Color(0.7, 0.2, 0.15, 1)
const COLOR_DEFENDER := Color(0.35, 0.18, 0.5, 1)

enum Phase { SETUP, SIMULATION, RESULT }

var current_phase: Phase = Phase.SETUP
var simulator: BattleSimulator
var attacker_army: ArmyState
var defender_army: ArmyState
var attacker_faction_id: StringName
var defender_faction_id: StringName
var battle_hex_pos: Vector2i
var battle_terrain: Dictionary = {} # Vector2i -> Enums.BattleTerrain

# Setup state
var available_units: Array[UnitInstance] = []
var placed_units: Dictionary = {} # Vector2i -> {unit_instance, stance, priority}
var current_stance: Enums.UnitStance = Enums.UnitStance.AGGRESSIVE
var current_priority: Enums.TargetPriority = Enums.TargetPriority.CLOSEST

# Simulation state
var sim_speed: float = 0.5
var sim_timer: float = 0.0
var is_simulating: bool = false
var skip_to_end: bool = false

# Visual nodes
var _grid_cells: Dictionary = {} # Vector2i -> ColorRect
var _unit_visuals: Dictionary = {} # instance_id -> Dictionary of tile visuals
var _hovered_unit: BattleSimulator.BattleUnit = null
var _highlighted_tiles: Array[Vector2i] = []

# Rearrange state — click unit to pick up, click empty tile to move
var _picked_up_bu: BattleSimulator.BattleUnit = null  # The unit being moved
var _picked_up_origin: Vector2i = Vector2i(-1, -1)  # Where it was before pickup
var _place_ghost: ColorRect = null
var _grid_click_area: Control = null  # Transparent overlay that catches grid clicks

@onready var grid_cells_node: Node2D = $GridContainer/GridCells
@onready var battle_units_node: Node2D = $GridContainer/BattleUnits
@onready var effects_node: Node2D = $GridContainer/Effects
@onready var setup_panel: PanelContainer = $UILayer/BattleUI/SetupPanel
@onready var sim_panel: PanelContainer = $UILayer/BattleUI/SimPanel
@onready var result_panel: PanelContainer = $UILayer/BattleUI/ResultPanel
@onready var unit_info_panel: PanelContainer = $UILayer/BattleUI/UnitInfoPanel

func _ready() -> void:
	var attacker_id: StringName = GameManager.get_meta("battle_attacker")
	var defender_id: StringName = GameManager.get_meta("battle_defender")
	battle_hex_pos = GameManager.get_meta("battle_hex_pos")

	attacker_army = GameManager.state.armies.get(attacker_id)
	defender_army = GameManager.state.armies.get(defender_id)

	if attacker_army == null or defender_army == null:
		push_error("Battle: Missing army data!")
		_return_to_campaign()
		return

	attacker_faction_id = attacker_army.faction_id
	defender_faction_id = defender_army.faction_id

	var player_is_attacker := attacker_faction_id == GameManager.state.player_faction_id

	if player_is_attacker:
		available_units = attacker_army.units.duplicate()
	else:
		available_units = defender_army.units.duplicate()

	# Generate terrain from campaign hex
	_generate_terrain()

	_build_grid()
	_setup_ui()
	_place_ai_units(player_is_attacker)
	_auto_deploy_player_units(player_is_attacker)
	_populate_unit_list()

	unit_info_panel.visible = false

func _generate_terrain() -> void:
	var campaign_terrain := Enums.TerrainType.PLAINS
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(battle_hex_pos)
		if tile:
			campaign_terrain = tile.terrain

	var seed_val := battle_hex_pos.x * 1000 + battle_hex_pos.y
	battle_terrain = BattleTerrainGen.generate(campaign_terrain, seed_val)

func _build_grid() -> void:
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var cell := ColorRect.new()
			cell.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)
			cell.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var pos := Vector2i(x, y)
			var terrain_type: Enums.BattleTerrain = battle_terrain.get(pos, Enums.BattleTerrain.OPEN)
			cell.color = TERRAIN_COLORS.get(terrain_type, TERRAIN_COLORS[Enums.BattleTerrain.OPEN])

			# Tint deployment zones
			if y >= BattleSimulator.ATTACKER_DEPLOY_START:
				cell.color = cell.color.lerp(COLOR_DEPLOY_ZONE, 0.3)
			elif y < BattleSimulator.DEFENDER_DEPLOY_END:
				cell.color = cell.color.lerp(COLOR_ENEMY_ZONE, 0.3)

			# Mark impassable terrain
			if not BattleTerrainGen.is_passable(terrain_type):
				cell.color = cell.color.lightened(0.1)

			grid_cells_node.add_child(cell)
			_grid_cells[pos] = cell

	# Add terrain detail markers
	_add_terrain_details()

	# Zone separator line
	var sep_line := Line2D.new()
	sep_line.points = PackedVector2Array([
		Vector2(0, 8 * CELL_SIZE),
		Vector2(GRID_WIDTH * CELL_SIZE, 8 * CELL_SIZE)
	])
	sep_line.width = 1.5
	sep_line.default_color = Color(0.9, 0.82, 0.55, 0.3)
	grid_cells_node.add_child(sep_line)

	# Transparent click area over the entire grid — catches mouse events reliably
	_grid_click_area = Control.new()
	_grid_click_area.position = Vector2.ZERO
	_grid_click_area.size = Vector2(GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)
	_grid_click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_click_area.gui_input.connect(_on_grid_gui_input)
	# Add to GridContainer (above cells and units) so it reliably captures clicks
	$GridContainer.add_child(_grid_click_area)

	# Grid border
	var border := Line2D.new()
	border.points = PackedVector2Array([
		Vector2(0, 0),
		Vector2(GRID_WIDTH * CELL_SIZE, 0),
		Vector2(GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE),
		Vector2(0, GRID_HEIGHT * CELL_SIZE),
		Vector2(0, 0),
	])
	border.width = 2.0
	border.default_color = Color(0.55, 0.42, 0.2, 0.8)
	grid_cells_node.add_child(border)

func _add_terrain_details() -> void:
	for pos in battle_terrain:
		var terrain_type: Enums.BattleTerrain = battle_terrain[pos]
		var px: float = pos.x * CELL_SIZE
		var py: float = pos.y * CELL_SIZE
		var center := Vector2(px + CELL_SIZE * 0.5, py + CELL_SIZE * 0.5)

		match terrain_type:
			Enums.BattleTerrain.FOREST:
				var dot := _make_dot(center + Vector2(-5, -3), 3.0, Color(0.15, 0.3, 0.12, 0.7))
				grid_cells_node.add_child(dot)
				var dot2 := _make_dot(center + Vector2(4, 2), 2.5, Color(0.12, 0.25, 0.1, 0.6))
				grid_cells_node.add_child(dot2)
			Enums.BattleTerrain.ROCK:
				# X pattern for impassable
				var x_line := Line2D.new()
				x_line.points = PackedVector2Array([
					Vector2(px + 6, py + 6), Vector2(px + CELL_SIZE - 6, py + CELL_SIZE - 6)
				])
				x_line.width = 1.5
				x_line.default_color = Color(0.4, 0.35, 0.3, 0.5)
				grid_cells_node.add_child(x_line)
				var x_line2 := Line2D.new()
				x_line2.points = PackedVector2Array([
					Vector2(px + CELL_SIZE - 6, py + 6), Vector2(px + 6, py + CELL_SIZE - 6)
				])
				x_line2.width = 1.5
				x_line2.default_color = Color(0.4, 0.35, 0.3, 0.5)
				grid_cells_node.add_child(x_line2)
			Enums.BattleTerrain.WATER:
				var wave := Line2D.new()
				wave.points = PackedVector2Array([
					Vector2(px + 5, py + CELL_SIZE * 0.5),
					Vector2(px + CELL_SIZE * 0.33, py + CELL_SIZE * 0.35),
					Vector2(px + CELL_SIZE * 0.66, py + CELL_SIZE * 0.65),
					Vector2(px + CELL_SIZE - 5, py + CELL_SIZE * 0.5),
				])
				wave.width = 1.0
				wave.default_color = Color(0.2, 0.35, 0.55, 0.5)
				grid_cells_node.add_child(wave)
			Enums.BattleTerrain.CRYSTAL:
				var x_line := Line2D.new()
				x_line.points = PackedVector2Array([
					Vector2(px + 5, py + 5), Vector2(px + CELL_SIZE - 5, py + CELL_SIZE - 5)
				])
				x_line.width = 2.0
				x_line.default_color = Color(0.5, 0.2, 0.6, 0.6)
				grid_cells_node.add_child(x_line)
				var x_line2 := Line2D.new()
				x_line2.points = PackedVector2Array([
					Vector2(px + CELL_SIZE - 5, py + 5), Vector2(px + 5, py + CELL_SIZE - 5)
				])
				x_line2.width = 2.0
				x_line2.default_color = Color(0.5, 0.2, 0.6, 0.6)
				grid_cells_node.add_child(x_line2)
			Enums.BattleTerrain.BRUSH:
				var dot := _make_dot(center, 2.0, Color(0.2, 0.28, 0.15, 0.5))
				grid_cells_node.add_child(dot)

func _make_dot(pos: Vector2, radius: float, color: Color) -> Polygon2D:
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(6):
		var angle := i * TAU / 6.0
		pts.append(pos + Vector2(cos(angle), sin(angle)) * radius)
	dot.polygon = pts
	dot.color = color
	return dot

func _setup_ui() -> void:
	var stance_opt: OptionButton = setup_panel.get_node("VBox/StanceOption")
	stance_opt.clear()
	stance_opt.add_item("Aggressive", Enums.UnitStance.AGGRESSIVE)
	stance_opt.add_item("Defensive", Enums.UnitStance.DEFENSIVE)
	stance_opt.item_selected.connect(_on_stance_changed)

	var prio_opt: OptionButton = setup_panel.get_node("VBox/PriorityOption")
	prio_opt.clear()
	prio_opt.add_item("Closest", Enums.TargetPriority.CLOSEST)
	prio_opt.add_item("Weakest", Enums.TargetPriority.WEAKEST)
	prio_opt.add_item("Strongest", Enums.TargetPriority.STRONGEST)
	prio_opt.add_item("Ranged First", Enums.TargetPriority.RANGED_FIRST)
	prio_opt.item_selected.connect(_on_priority_changed)

	var begin_btn: Button = setup_panel.get_node("VBox/BeginBattleButton")
	begin_btn.disabled = false  # All units auto-deployed, ready to start
	begin_btn.pressed.connect(_on_begin_battle)

	var s1: Button = sim_panel.get_node("HBox/Speed1x")
	var s2: Button = sim_panel.get_node("HBox/Speed2x")
	var s4: Button = sim_panel.get_node("HBox/Speed4x")
	var skip: Button = sim_panel.get_node("HBox/SkipButton")
	s1.pressed.connect(func(): sim_speed = 0.6)
	s2.pressed.connect(func(): sim_speed = 0.3)
	s4.pressed.connect(func(): sim_speed = 0.15)
	skip.pressed.connect(func(): skip_to_end = true)

	var cont_btn: Button = result_panel.get_node("VBox/ContinueButton")
	cont_btn.pressed.connect(_on_continue)

func _on_stance_changed(idx: int) -> void:
	current_stance = idx as Enums.UnitStance
	if _picked_up_bu:
		_picked_up_bu.stance = current_stance
		if placed_units.has(_picked_up_origin):
			placed_units[_picked_up_origin]["stance"] = current_stance

func _on_priority_changed(idx: int) -> void:
	current_priority = idx as Enums.TargetPriority
	if _picked_up_bu:
		_picked_up_bu.target_priority = current_priority
		if placed_units.has(_picked_up_origin):
			placed_units[_picked_up_origin]["priority"] = current_priority

func _auto_deploy_player_units(player_is_attacker: bool) -> void:
	## Auto-deploy all player units in a spread formation in the deploy zone.
	var player_side := 0 if player_is_attacker else 1
	var unit_count := available_units.size()
	if unit_count == 0:
		return

	# Spread units with enough room for formations (~5 tiles wide each)
	var spacing := maxi(5, GRID_WIDTH / maxi(unit_count, 1))
	# Center the group: start so that (unit_count * spacing) is centered in the grid
	var total_width: int = unit_count * spacing
	var start_col: int = maxi(2, (GRID_WIDTH - total_width) / 2 + spacing / 2)

	for i in unit_count:
		var unit: UnitInstance = available_units[i]
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data == null:
			continue

		var col: int = clampi(start_col + i * spacing, 2, GRID_WIDTH - 3)
		var row: int = 12
		var pos := Vector2i(col, row)

		# Find a free, passable tile near the target position
		var attempts := 0
		while (simulator.grid.has(pos) or not BattleTerrainGen.is_passable(battle_terrain.get(pos, Enums.BattleTerrain.OPEN))) and attempts < 60:
			pos.x += 1
			if pos.x >= GRID_WIDTH - 2:
				pos.x = 2
				pos.y += 1
			if pos.y >= GRID_HEIGHT:
				pos.y = BattleSimulator.ATTACKER_DEPLOY_START
			attempts += 1

		var bu := simulator.setup_unit(unit, unit_data, player_side, pos, current_stance, current_priority)
		placed_units[pos] = {
			"unit": unit,
			"stance": current_stance,
			"priority": current_priority,
		}
		_create_unit_visual(bu)

func _populate_unit_list() -> void:
	## Populate the tray with a read-only list of deployed units.
	var tray: VBoxContainer = setup_panel.get_node("VBox/UnitTrayScroll/UnitTray")
	for child in tray.get_children():
		tray.remove_child(child)
		child.queue_free()

	for i in available_units.size():
		var unit: UnitInstance = available_units[i]
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data == null:
			continue
		var label := Label.new()
		label.text = "%s  HP:%d  ATK:%d" % [unit_data.display_name, unit.current_hp, unit_data.attack]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65, 1))
		tray.add_child(label)

func _highlight_deploy_zone() -> void:
	for pos in _grid_cells:
		var cell: ColorRect = _grid_cells[pos]
		var in_deploy: bool = pos.y >= BattleSimulator.ATTACKER_DEPLOY_START and pos.y < GRID_HEIGHT
		var is_free: bool = not simulator.grid.has(pos)
		var is_passable: bool = BattleTerrainGen.is_passable(battle_terrain.get(pos, Enums.BattleTerrain.OPEN))
		if in_deploy and is_free and is_passable:
			cell.color = COLOR_DEPLOY_HIGHLIGHT
		else:
			_reset_cell_color(pos)

func _create_place_ghost() -> void:
	_remove_place_ghost()
	_place_ghost = ColorRect.new()
	_place_ghost.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
	_place_ghost.color = Color(0.9, 0.85, 0.5, 0.4)
	_place_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_ghost.z_index = 100
	_place_ghost.visible = false
	$GridContainer.add_child(_place_ghost)

func _remove_place_ghost() -> void:
	if _place_ghost and is_instance_valid(_place_ghost):
		_place_ghost.queue_free()
		_place_ghost = null

func _pickup_unit(bu: BattleSimulator.BattleUnit) -> void:
	## Pick up a placed unit for repositioning.
	_picked_up_bu = bu
	_picked_up_origin = bu.anchor_pos

	# Load this unit's stance/priority into the dropdowns
	var stance_opt: OptionButton = setup_panel.get_node("VBox/StanceOption")
	var prio_opt: OptionButton = setup_panel.get_node("VBox/PriorityOption")
	stance_opt.selected = bu.stance
	prio_opt.selected = bu.target_priority
	current_stance = bu.stance
	current_priority = bu.target_priority

	# Dim the unit visual to show it's being moved
	var visual_data = _unit_visuals.get(bu.instance_id)
	if visual_data:
		visual_data.container.modulate.a = 0.3

	_create_place_ghost()
	_highlight_deploy_zone()

func _drop_unit_cancel() -> void:
	## Cancel pickup — restore unit to original position.
	if _picked_up_bu:
		var visual_data = _unit_visuals.get(_picked_up_bu.instance_id)
		if visual_data:
			visual_data.container.modulate.a = 1.0
	_picked_up_bu = null
	_picked_up_origin = Vector2i(-1, -1)
	_remove_place_ghost()
	_reset_grid_colors()

func _drop_unit_at(new_pos: Vector2i) -> void:
	## Move the picked-up unit to a new grid position.
	var bu := _picked_up_bu
	if bu == null:
		return

	# Get the old placed_units entry before erasing
	var old_entry: Dictionary = placed_units.get(_picked_up_origin, {})
	placed_units.erase(_picked_up_origin)

	# Reposition unit in simulator (clears old grid entries, places new formation)
	simulator.reposition_unit(bu, new_pos)

	# Update placed_units with same unit/stance/priority
	placed_units[new_pos] = old_entry

	# Rebuild visual at new position
	_rebuild_unit_visual(bu)

	_picked_up_bu = null
	_picked_up_origin = Vector2i(-1, -1)
	_remove_place_ghost()
	_reset_grid_colors()

func _place_ai_units(player_is_attacker: bool) -> void:
	var ai_army: ArmyState = defender_army if player_is_attacker else attacker_army
	var ai_side: int = 1 if player_is_attacker else 0

	simulator = BattleSimulator.new()
	simulator.setup_terrain(battle_terrain)

	for i in ai_army.units.size():
		var unit: UnitInstance = ai_army.units[i]
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data == null:
			continue

		# AI deploys in rows 1-4, spread across the grid
		var col: int = (GRID_WIDTH / 2 - ai_army.units.size() / 2 + i * 3) % GRID_WIDTH
		if col < 0:
			col = 0
		var row: int = 2
		var pos := Vector2i(col, row)

		while simulator.grid.has(pos):
			pos.x = (pos.x + 1) % GRID_WIDTH
			if pos.x == col:
				row += 1
				pos.y = row

		var stance := Enums.UnitStance.AGGRESSIVE
		var priority := Enums.TargetPriority.CLOSEST

		var bu := simulator.setup_unit(unit, unit_data, ai_side, pos, stance, priority)
		_create_unit_visual(bu)

func _grid_pos_from_local(local_pos: Vector2) -> Vector2i:
	var gx: int = int(floor(local_pos.x / CELL_SIZE))
	var gy: int = int(floor(local_pos.y / CELL_SIZE))
	if gx >= 0 and gx < GRID_WIDTH and gy >= 0 and gy < GRID_HEIGHT:
		return Vector2i(gx, gy)
	return Vector2i(-1, -1)

func _is_valid_deploy_pos(grid_pos: Vector2i) -> bool:
	if grid_pos.x < 0 or grid_pos.y < BattleSimulator.ATTACKER_DEPLOY_START:
		return false
	if grid_pos.x >= GRID_WIDTH or grid_pos.y >= GRID_HEIGHT:
		return false
	if simulator.grid.has(grid_pos):
		return false
	if not BattleTerrainGen.is_passable(battle_terrain.get(grid_pos, Enums.BattleTerrain.OPEN)):
		return false
	return true

func _on_grid_gui_input(event: InputEvent) -> void:
	if current_phase != Phase.SETUP:
		return

	var player_side := 0
	if attacker_faction_id != GameManager.state.player_faction_id:
		player_side = 1

	# Mouse motion — update ghost if carrying a unit
	if event is InputEventMouseMotion and _picked_up_bu and _place_ghost:
		var grid_pos := _grid_pos_from_local(event.position)
		if grid_pos.x >= 0:
			_place_ghost.position = Vector2(grid_pos.x * CELL_SIZE + 1, grid_pos.y * CELL_SIZE + 1)
			if _is_valid_deploy_pos(grid_pos):
				_place_ghost.color = Color(0.3, 0.85, 0.4, 0.4)
			else:
				_place_ghost.color = Color(0.85, 0.3, 0.2, 0.3)
			_place_ghost.visible = true
		else:
			_place_ghost.visible = false

	# Left click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var grid_pos := _grid_pos_from_local(event.position)
		if grid_pos.x < 0:
			return

		if _picked_up_bu:
			# We're carrying a unit — try to place it at the clicked tile
			if _is_valid_deploy_pos(grid_pos):
				_drop_unit_at(grid_pos)
				_grid_click_area.accept_event()
			# If clicked on an invalid tile, do nothing (keep carrying)
		else:
			# Nothing picked up — check if clicking on own unit in deploy zone
			var clicked_bu := simulator.get_unit_at(grid_pos)
			if clicked_bu and clicked_bu.side == player_side:
				if grid_pos.y >= BattleSimulator.ATTACKER_DEPLOY_START:
					_pickup_unit(clicked_bu)
					_grid_click_area.accept_event()

	# Right click — cancel pickup
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _picked_up_bu:
			_drop_unit_cancel()
			_grid_click_area.accept_event()

func _reset_grid_colors() -> void:
	for pos in _grid_cells:
		_reset_cell_color(pos)

func _reset_cell_color(pos: Vector2i) -> void:
	var cell: ColorRect = _grid_cells[pos]
	var terrain_type: Enums.BattleTerrain = battle_terrain.get(pos, Enums.BattleTerrain.OPEN)
	cell.color = TERRAIN_COLORS.get(terrain_type, TERRAIN_COLORS[Enums.BattleTerrain.OPEN])

	if pos.y >= BattleSimulator.ATTACKER_DEPLOY_START:
		cell.color = cell.color.lerp(COLOR_DEPLOY_ZONE, 0.3)
	elif pos.y < BattleSimulator.DEFENDER_DEPLOY_END:
		cell.color = cell.color.lerp(COLOR_ENEMY_ZONE, 0.3)

	if not BattleTerrainGen.is_passable(terrain_type):
		cell.color = cell.color.lightened(0.1)

# --- Formation visuals ---

func _create_unit_visual(bu: BattleSimulator.BattleUnit) -> void:
	var base_color := COLOR_ATTACKER if bu.side == 0 else COLOR_DEFENDER
	var unit_data := DataManager.get_unit(bu.unit_data_id)

	var visual_data := {
		"container": Node2D.new(),
		"tile_nodes": {},  # Vector2i -> ColorRect
		"anchor_node": null,  # The anchor tile with icon/name/hp
		"side": bu.side,
		"base_color": base_color,
	}

	battle_units_node.add_child(visual_data.container)

	# Create tile visuals for each occupied tile
	for tile_pos in bu.occupied_tiles:
		var is_anchor := (tile_pos == bu.anchor_pos)
		var tile_visual := _create_tile_visual(tile_pos, base_color, is_anchor)
		visual_data.container.add_child(tile_visual)
		visual_data.tile_nodes[tile_pos] = tile_visual

	# Add icon and HP on anchor
	var anchor_visual := _create_anchor_overlay(bu, base_color, unit_data)
	visual_data.container.add_child(anchor_visual)
	visual_data.anchor_node = anchor_visual

	_unit_visuals[bu.instance_id] = visual_data

func _create_tile_visual(tile_pos: Vector2i, color: Color, is_anchor: bool) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
	rect.position = Vector2(tile_pos.x * CELL_SIZE + 1, tile_pos.y * CELL_SIZE + 1)
	rect.color = color if is_anchor else color.darkened(0.2)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _create_anchor_overlay(bu: BattleSimulator.BattleUnit, base_color: Color, unit_data: UnitData) -> Node2D:
	var overlay := Node2D.new()
	var px: float = bu.anchor_pos.x * CELL_SIZE
	var py: float = bu.anchor_pos.y * CELL_SIZE

	# Unit type icon
	var icon_label := Label.new()
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.9))
	icon_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	icon_label.add_theme_constant_override("shadow_offset_x", 1)
	icon_label.add_theme_constant_override("shadow_offset_y", 1)
	if unit_data and unit_data.tags.has("mage"):
		icon_label.text = "*"
	elif unit_data and unit_data.tags.has("ranged"):
		icon_label.text = ">"
	elif unit_data and unit_data.tags.has("cavalry"):
		icon_label.text = "^"
	elif unit_data and unit_data.tags.has("construct"):
		icon_label.text = "#"
	else:
		icon_label.text = "+"
	icon_label.position = Vector2(px + CELL_SIZE * 0.5 - 5, py + 2)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(icon_label)

	# Name (abbreviated)
	var name_label := Label.new()
	name_label.text = bu.display_name.substr(0, 4)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.85))
	name_label.position = Vector2(px + 2, py + 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(name_label)

	# HP bar spanning formation width
	var min_x := bu.anchor_pos.x
	var max_x := bu.anchor_pos.x
	for tile in bu.occupied_tiles:
		if tile.x < min_x: min_x = tile.x
		if tile.x > max_x: max_x = tile.x
	var bar_start_x: float = min_x * CELL_SIZE + 3
	var bar_width: float = (max_x - min_x + 1) * CELL_SIZE - 6
	bar_width = maxf(bar_width, CELL_SIZE - 6)

	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(bar_width, 3)
	bar_bg.position = Vector2(bar_start_x, py + CELL_SIZE - 6)
	bar_bg.color = Color(0.15, 0.08, 0.08)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bar_bg)

	var hp_ratio := float(bu.current_hp) / float(bu.max_hp)
	var bar_fill := ColorRect.new()
	bar_fill.name = "HPBar"
	bar_fill.size = Vector2(bar_width * hp_ratio, 3)
	bar_fill.position = Vector2(bar_start_x, py + CELL_SIZE - 6)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hp_ratio > 0.5:
		bar_fill.color = Color(0.2, 0.7, 0.25)
	elif hp_ratio > 0.25:
		bar_fill.color = Color(0.85, 0.65, 0.15)
	else:
		bar_fill.color = Color(0.8, 0.2, 0.15)
	overlay.add_child(bar_fill)

	# HP text (show soldier count for squads)
	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	if bu.hp_per_soldier > 0 and bu.squad_size > 1:
		hp_label.text = "%d(%d)" % [bu.current_hp, bu.soldiers_remaining]
	else:
		hp_label.text = str(bu.current_hp)
	hp_label.add_theme_font_size_override("font_size", 8)
	hp_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	hp_label.position = Vector2(px + CELL_SIZE * 0.5 - 8, py + CELL_SIZE * 0.5)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hp_label)

	return overlay

func _rebuild_unit_visual(bu: BattleSimulator.BattleUnit, ripple: bool = false) -> void:
	# Remove old visual and recreate
	var old_data = _unit_visuals.get(bu.instance_id)
	if old_data:
		old_data.container.queue_free()
	_create_unit_visual(bu)

	# Formation tile ripple: stagger tile visibility with delay
	if ripple:
		var visual_data = _unit_visuals.get(bu.instance_id)
		if visual_data:
			var delay := 0.0
			for tile_pos in visual_data.tile_nodes:
				var tile_rect: ColorRect = visual_data.tile_nodes[tile_pos]
				tile_rect.modulate.a = 0.0
				var tween := create_tween()
				tween.tween_interval(delay)
				tween.tween_property(tile_rect, "modulate:a", 1.0, 0.1)
				delay += 0.05

# --- Hover / Info Panel ---

func _process(delta: float) -> void:
	_update_hover()

	if current_phase != Phase.SIMULATION or not is_simulating:
		return

	if skip_to_end:
		while not simulator.is_finished:
			var actions := simulator.simulate_tick()
			_apply_actions_instant(actions)
		_on_simulation_complete()
		return

	sim_timer += delta
	if sim_timer >= sim_speed:
		sim_timer = 0.0
		_run_one_tick()

func _update_hover() -> void:
	var local_pos: Vector2 = $GridContainer.get_local_mouse_position()
	var gx: int = int(floor(local_pos.x / CELL_SIZE))
	var gy: int = int(floor(local_pos.y / CELL_SIZE))

	if gx < 0 or gx >= GRID_WIDTH or gy < 0 or gy >= GRID_HEIGHT:
		_clear_formation_highlight()
		unit_info_panel.visible = false
		_hovered_unit = null
		return

	var grid_pos := Vector2i(gx, gy)
	var unit := simulator.get_unit_at(grid_pos)

	if unit != null and unit != _hovered_unit:
		_clear_formation_highlight()
		_hovered_unit = unit
		_apply_formation_highlight(unit)
		_populate_info_panel(unit, grid_pos)
		unit_info_panel.visible = true
	elif unit == null and _hovered_unit != null:
		_clear_formation_highlight()
		_hovered_unit = null
		unit_info_panel.visible = false

func _apply_formation_highlight(unit: BattleSimulator.BattleUnit) -> void:
	for tile_pos in unit.occupied_tiles:
		if _grid_cells.has(tile_pos):
			var cell: ColorRect = _grid_cells[tile_pos]
			cell.color = cell.color.lerp(Color.WHITE, 0.2)
			_highlighted_tiles.append(tile_pos)

func _clear_formation_highlight() -> void:
	for tile_pos in _highlighted_tiles:
		_reset_cell_color(tile_pos)
	_highlighted_tiles.clear()

func _populate_info_panel(unit: BattleSimulator.BattleUnit, pos: Vector2i) -> void:
	var vbox: VBoxContainer = unit_info_panel.get_node("VBox")

	var name_label: Label = vbox.get_node("NameLabel")
	name_label.text = unit.display_name

	var faction_label: Label = vbox.get_node("FactionLabel")
	var side_text := "Attacker" if unit.side == 0 else "Defender"
	faction_label.text = side_text

	# Portrait placeholder
	var portrait: ColorRect = vbox.get_node("Portrait")
	portrait.color = COLOR_ATTACKER if unit.side == 0 else COLOR_DEFENDER

	var hp_label: Label = vbox.get_node("HPLabel")
	if unit.hp_per_soldier > 0 and unit.squad_size > 1:
		hp_label.text = "HP: %d / %d  |  Soldiers: %d / %d" % [unit.current_hp, unit.max_hp, unit.soldiers_remaining, unit.squad_size]
	else:
		hp_label.text = "HP: %d / %d" % [unit.current_hp, unit.max_hp]

	var stats_label: Label = vbox.get_node("StatsLabel")
	stats_label.text = "ATK: %d  DEF: %d  SPD: %d  RNG: %d" % [unit.attack, unit.defense, unit.speed, unit.attack_range]

	var tags_label: Label = vbox.get_node("TagsLabel")
	tags_label.text = "Tags: " + ", ".join(unit.tags) if not unit.tags.is_empty() else "Tags: none"

	var stance_label: Label = vbox.get_node("StanceInfoLabel")
	var stance_name: String = Enums.UnitStance.keys()[unit.stance]
	var priority_name: String = Enums.TargetPriority.keys()[unit.target_priority]
	stance_label.text = "Stance: %s | Target: %s" % [stance_name, priority_name]

	var formation_label: Label = vbox.get_node("FormationLabel")
	formation_label.text = "Formation: %s (%d tiles)" % [unit.formation_type, unit.occupied_tiles.size()]

	var terrain_label: Label = vbox.get_node("TerrainLabel")
	var terrain_type := simulator.get_terrain_at(pos)
	var terrain_name: String = Enums.BattleTerrain.keys()[terrain_type]
	var def_bonus := BattleTerrainGen.get_defense_bonus(terrain_type)
	var spd_mod := BattleTerrainGen.get_speed_modifier(terrain_type)
	terrain_label.text = "Terrain: %s (DEF %+d, SPD x%.1f)" % [terrain_name, def_bonus, spd_mod]

# --- Battle flow ---

func _on_begin_battle() -> void:
	# Cancel any in-progress pickup
	if _picked_up_bu:
		_drop_unit_cancel()
	current_phase = Phase.SIMULATION
	setup_panel.visible = false
	sim_panel.visible = true
	is_simulating = true

func _run_one_tick() -> void:
	if simulator.is_finished:
		_on_simulation_complete()
		return

	var actions := simulator.simulate_tick()

	var tick_label: Label = sim_panel.get_node("HBox/TickLabel")
	tick_label.text = "Tick: " + str(simulator.tick_count)

	for action in actions:
		match action.type:
			"move":
				_animate_move(action.unit_id, action.from, action.to, action.get("tiles", []))
			"attack":
				_animate_attack(action.attacker_id, action.defender_id, action.damage, action.target_hp, action.target_dead, action.get("attacker_range", 1), action.get("attacker_tags", []))
			"death":
				_animate_death(action.unit_id)
			"formation_shrink":
				_animate_formation_shrink(action.unit_id, action.removed_tiles)

	if simulator.is_finished:
		await get_tree().create_timer(1.0).timeout
		_on_simulation_complete()

func _apply_actions_instant(actions: Array[Dictionary]) -> void:
	for action in actions:
		match action.type:
			"move":
				_instant_move(action.unit_id)
			"attack":
				_instant_attack(action.defender_id, action.target_hp)
			"death":
				_instant_death(action.unit_id)
			"formation_shrink":
				_instant_formation_shrink(action.unit_id)

func _instant_move(unit_id: StringName) -> void:
	# Find the BattleUnit and rebuild its visual
	var bu := _find_battle_unit(unit_id)
	if bu:
		_rebuild_unit_visual(bu)

func _instant_attack(defender_id: StringName, target_hp: int) -> void:
	var bu := _find_battle_unit(defender_id)
	var visual_data = _unit_visuals.get(defender_id)
	if visual_data and visual_data.anchor_node:
		var hp_label: Label = visual_data.anchor_node.get_node_or_null("HPLabel")
		if hp_label:
			if bu and bu.hp_per_soldier > 0 and bu.squad_size > 1:
				hp_label.text = "%d(%d)" % [target_hp, bu.soldiers_remaining]
			else:
				hp_label.text = str(target_hp)

func _instant_death(unit_id: StringName) -> void:
	var visual_data = _unit_visuals.get(unit_id)
	if visual_data:
		visual_data.container.visible = false

func _instant_formation_shrink(unit_id: StringName) -> void:
	var bu := _find_battle_unit(unit_id)
	if bu:
		_rebuild_unit_visual(bu)

func _animate_move(unit_id: StringName, from: Vector2i, to: Vector2i, tiles: Array) -> void:
	var bu := _find_battle_unit(unit_id)
	if bu == null:
		return

	# Rebuild at new position with ripple effect
	_rebuild_unit_visual(bu, true)
	var visual_data = _unit_visuals.get(unit_id)
	if visual_data == null:
		return

	# Smooth slide: offset container by (from - to) in pixels, tween to zero
	var pixel_offset := Vector2((from.x - to.x) * CELL_SIZE, (from.y - to.y) * CELL_SIZE)
	visual_data.container.position = pixel_offset
	var tween := create_tween()
	tween.tween_property(visual_data.container, "position", Vector2.ZERO, 0.2)

func _animate_attack(attacker_id: StringName, defender_id: StringName, damage: int, target_hp: int, _target_dead: bool, attack_range: int = 1, attacker_tags: Array = []) -> void:
	var attacker_visual = _unit_visuals.get(attacker_id)
	var defender_visual = _unit_visuals.get(defender_id)
	var attacker_bu := _find_battle_unit(attacker_id)
	var defender_bu := _find_battle_unit(defender_id)

	# Melee lunge animation
	if attack_range <= 1 and attacker_visual and attacker_bu and defender_bu:
		var dir := Vector2(defender_bu.anchor_pos.x - attacker_bu.anchor_pos.x, defender_bu.anchor_pos.y - attacker_bu.anchor_pos.y).normalized()
		var lunge_offset := dir * 8.0
		var lunge_tween := create_tween()
		lunge_tween.tween_property(attacker_visual.container, "position", lunge_offset, 0.1)
		lunge_tween.tween_property(attacker_visual.container, "position", Vector2.ZERO, 0.1)

	# Ranged projectile animation
	if attack_range > 1 and attacker_bu and defender_bu:
		var from_pixel := Vector2(attacker_bu.anchor_pos.x * CELL_SIZE + CELL_SIZE * 0.5, attacker_bu.anchor_pos.y * CELL_SIZE + CELL_SIZE * 0.5)
		var to_pixel := Vector2(defender_bu.anchor_pos.x * CELL_SIZE + CELL_SIZE * 0.5, defender_bu.anchor_pos.y * CELL_SIZE + CELL_SIZE * 0.5)

		var projectile := ColorRect.new()
		projectile.size = Vector2(4, 4)
		projectile.position = from_pixel - Vector2(2, 2)
		projectile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Color by type: purple for mage, white for ranged
		if attacker_tags.has("mage"):
			projectile.color = Color(0.7, 0.3, 0.9)
		else:
			projectile.color = Color(0.95, 0.9, 0.8)
		effects_node.add_child(projectile)

		var proj_tween := create_tween()
		proj_tween.tween_property(projectile, "position", to_pixel - Vector2(2, 2), 0.3)
		proj_tween.tween_callback(projectile.queue_free)

	if defender_visual:
		# Wiggle/shake on hit: oscillate position offset
		var shake_tween := create_tween()
		shake_tween.tween_property(defender_visual.container, "position", Vector2(3, 0), 0.033)
		shake_tween.tween_property(defender_visual.container, "position", Vector2(-3, 0), 0.066)
		shake_tween.tween_property(defender_visual.container, "position", Vector2(2, 0), 0.033)
		shake_tween.tween_property(defender_visual.container, "position", Vector2(-2, 0), 0.033)
		shake_tween.tween_property(defender_visual.container, "position", Vector2(1, 0), 0.033)
		shake_tween.tween_property(defender_visual.container, "position", Vector2.ZERO, 0.033)

		# Flash tiles red
		for tile_pos in defender_visual.tile_nodes:
			var tile_rect: ColorRect = defender_visual.tile_nodes[tile_pos]
			var original_color := tile_rect.color
			tile_rect.color = Color(1, 0.4, 0.3, 1)
			var tween := create_tween()
			tween.tween_property(tile_rect, "color", original_color, 0.3)

		var hp_label: Label = defender_visual.anchor_node.get_node_or_null("HPLabel")
		if hp_label:
			hp_label.text = str(target_hp)

		# Damage number at anchor
		if defender_bu:
			_spawn_damage_number(Vector2(defender_bu.anchor_pos.x * CELL_SIZE + CELL_SIZE * 0.5, defender_bu.anchor_pos.y * CELL_SIZE), damage)

func _animate_death(unit_id: StringName) -> void:
	var visual_data = _unit_visuals.get(unit_id)
	if visual_data:
		var tween := create_tween()
		# Death collapse: scale Y to 0 + fade simultaneously
		tween.set_parallel(true)
		tween.tween_property(visual_data.container, "scale:y", 0.0, 0.3)
		tween.tween_property(visual_data.container, "modulate:a", 0.0, 0.3)
		tween.set_parallel(false)
		tween.tween_callback(visual_data.container.queue_free)
		_unit_visuals.erase(unit_id)

func _animate_formation_shrink(unit_id: StringName, removed_tiles: Array) -> void:
	var visual_data = _unit_visuals.get(unit_id)
	if visual_data == null:
		return

	# Fade out removed tiles
	for tile_pos in removed_tiles:
		if visual_data.tile_nodes.has(tile_pos):
			var tile_rect: ColorRect = visual_data.tile_nodes[tile_pos]
			var tween := create_tween()
			tween.tween_property(tile_rect, "modulate:a", 0.0, 0.3)
			tween.tween_callback(tile_rect.queue_free)
			visual_data.tile_nodes.erase(tile_pos)

	# Update HP display on anchor
	var bu := _find_battle_unit(unit_id)
	if bu:
		# Rebuild anchor overlay to update HP bar width
		if visual_data.anchor_node:
			visual_data.anchor_node.queue_free()
		var unit_data := DataManager.get_unit(bu.unit_data_id)
		var base_color := COLOR_ATTACKER if bu.side == 0 else COLOR_DEFENDER
		visual_data.anchor_node = _create_anchor_overlay(bu, base_color, unit_data)
		visual_data.container.add_child(visual_data.anchor_node)

func _spawn_damage_number(pos: Vector2, damage: int) -> void:
	var label := Label.new()
	label.text = "-" + str(damage)
	label.position = pos + Vector2(-10, -20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	effects_node.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 25, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _find_battle_unit(instance_id: StringName) -> BattleSimulator.BattleUnit:
	for u in simulator.attacker_units:
		if u.instance_id == instance_id:
			return u
	for u in simulator.defender_units:
		if u.instance_id == instance_id:
			return u
	return null

# --- Result ---

func _on_simulation_complete() -> void:
	is_simulating = false
	current_phase = Phase.RESULT
	sim_panel.visible = false
	result_panel.visible = true

	var player_is_attacker := attacker_faction_id == GameManager.state.player_faction_id
	var player_side := 0 if player_is_attacker else 1
	var enemy_side := 1 if player_is_attacker else 0
	var player_won := simulator.winner_side == player_side

	var winner_label: Label = result_panel.get_node("VBox/WinnerLabel")
	winner_label.text = "VICTORY!" if player_won else "DEFEAT!"
	winner_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.35) if player_won else Color(0.9, 0.3, 0.25))

	# Build two-column losses display
	var losses_container: HBoxContainer = result_panel.get_node("VBox/LossesContainer")
	for child in losses_container.get_children():
		losses_container.remove_child(child)
		child.queue_free()

	var player_army := attacker_army if player_is_attacker else defender_army
	var enemy_army := defender_army if player_is_attacker else attacker_army
	var player_survivors := simulator.get_surviving_units(player_side)
	var enemy_survivors := simulator.get_surviving_units(enemy_side)

	var player_col := _build_losses_column("YOUR FORCES", player_army, player_survivors, COLOR_ATTACKER if player_is_attacker else COLOR_DEFENDER)
	var enemy_col := _build_losses_column("ENEMY FORCES", enemy_army, enemy_survivors, COLOR_DEFENDER if player_is_attacker else COLOR_ATTACKER)

	losses_container.add_child(player_col)

	# Vertical separator
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	losses_container.add_child(sep)

	losses_container.add_child(enemy_col)

func _build_losses_column(title: String, army: ArmyState, survivors: Array[BattleSimulator.BattleUnit], color: Color) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 220
	col.add_theme_constant_override("separation", 4)

	# Title
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", color.lightened(0.3))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)

	# Summary
	var survivor_ids: Dictionary = {}
	for bu in survivors:
		survivor_ids[bu.instance_id] = bu.current_hp

	var total := army.units.size()
	var alive := survivor_ids.size()
	var lost := total - alive

	var summary := Label.new()
	summary.text = "Survived: %d / %d  |  Lost: %d" % [alive, total, lost]
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(summary)

	# Individual unit list
	for unit in army.units:
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		var name_str: String = unit_data.display_name if unit_data else str(unit.unit_data_id)
		var entry := Label.new()
		entry.add_theme_font_size_override("font_size", 10)

		if survivor_ids.has(unit.instance_id):
			var hp: int = survivor_ids[unit.instance_id]
			entry.text = "  %s  HP: %d/%d" % [name_str, hp, unit_data.max_hp if unit_data else hp]
			entry.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
		else:
			entry.text = "  %s  KILLED" % name_str
			entry.add_theme_color_override("font_color", Color(0.8, 0.35, 0.3))

		col.add_child(entry)

	return col

func _on_continue() -> void:
	_apply_battle_results()
	_return_to_campaign()

func _apply_battle_results() -> void:
	_update_army_survivors(attacker_army, simulator.get_surviving_units(0))
	_update_army_survivors(defender_army, simulator.get_surviving_units(1))

	var attacker_alive := simulator.get_surviving_units(0).size() > 0
	var defender_alive := simulator.get_surviving_units(1).size() > 0

	if not attacker_alive:
		GameManager.remove_army(attacker_army.army_id)
	if not defender_alive:
		GameManager.remove_army(defender_army.army_id)

	if attacker_alive and not defender_alive:
		EventBus.battle_resolved.emit(attacker_faction_id, battle_hex_pos)
		# Check if there's an enemy city at this hex → start/continue siege
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id != attacker_faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_faction_id)
		elif city_at and city_at.faction_id == attacker_faction_id and city_at.is_under_siege:
			# Defender won the field but attacker was defending their own city
			GameManager.city_system.break_siege(city_at.city_id)
	elif defender_alive and not attacker_alive:
		EventBus.battle_resolved.emit(defender_faction_id, battle_hex_pos)
		# If defender's city was besieged, break the siege
		var city_at := GameManager.city_system.get_city_at_hex(battle_hex_pos)
		if city_at and city_at.faction_id == defender_faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)

func _update_army_survivors(army: ArmyState, survivors: Array[BattleSimulator.BattleUnit]) -> void:
	var surviving_ids: Dictionary = {}
	for bu in survivors:
		surviving_ids[bu.instance_id] = bu.current_hp

	var updated_units: Array[UnitInstance] = []
	for unit in army.units:
		if surviving_ids.has(unit.instance_id):
			unit.current_hp = surviving_ids[unit.instance_id]
			updated_units.append(unit)

	army.units = updated_units

func _return_to_campaign() -> void:
	GameManager.current_phase = Enums.GamePhase.CAMPAIGN
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")
