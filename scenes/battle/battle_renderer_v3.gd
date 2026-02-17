extends Node2D

var battle_scene = null  # Untyped — set by BattleV3

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

const COLOR_DEPLOY_TINT := Color(0.12, 0.15, 0.25, 1)
const COLOR_ENEMY_TINT := Color(0.25, 0.12, 0.12, 1)
const COLOR_PLAYER := Color(0.25, 0.5, 0.9, 1)
const COLOR_ENEMY := Color(0.8, 0.25, 0.2, 1)
const COLOR_SELECTED := Color(0.95, 0.85, 0.3, 1)
const COLOR_ROUTING_TINT := Color(0.4, 0.4, 0.4, 1)

func _draw() -> void:
	if battle_scene == null:
		return

	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return

	# 1. Draw terrain background
	_draw_terrain(sim)

	# 2. Draw deploy zone tints (only during setup)
	if battle_scene.current_phase == battle_scene.Phase.SETUP:
		_draw_deploy_zones(sim)

	# 3. Draw entities for each formation
	_draw_formations(sim)

	# 4. Draw field border
	draw_rect(Rect2(0, 0, BattleSimulatorV3.FIELD_WIDTH, BattleSimulatorV3.FIELD_HEIGHT),
		Color(0.55, 0.42, 0.2, 0.8), false, 2.0)

func _draw_terrain(sim: BattleSimulatorV3) -> void:
	var cs := sim.terrain_cell_size
	for y in sim.terrain_grid_h:
		for x in sim.terrain_grid_w:
			var pos := Vector2i(x, y)
			var terrain_type: Enums.BattleTerrain = sim.terrain_grid.get(pos, Enums.BattleTerrain.OPEN)
			var color: Color = TERRAIN_COLORS.get(terrain_type, TERRAIN_COLORS[Enums.BattleTerrain.OPEN])

			if not BattleTerrainGen.is_passable(terrain_type):
				color = color.lightened(0.1)

			draw_rect(Rect2(x * cs, y * cs, cs, cs), color)

func _draw_deploy_zones(sim: BattleSimulatorV3) -> void:
	# Attacker deploy zone (bottom)
	draw_rect(Rect2(0, BattleSimulatorV3.DEPLOY_BOTTOM_Y, BattleSimulatorV3.FIELD_WIDTH,
		BattleSimulatorV3.FIELD_HEIGHT - BattleSimulatorV3.DEPLOY_BOTTOM_Y),
		COLOR_DEPLOY_TINT * Color(1, 1, 1, 0.15))
	# Defender deploy zone (top)
	draw_rect(Rect2(0, 0, BattleSimulatorV3.FIELD_WIDTH, BattleSimulatorV3.DEPLOY_TOP_Y),
		COLOR_ENEMY_TINT * Color(1, 1, 1, 0.15))

	# Zone separator line
	var mid_y := (BattleSimulatorV3.DEPLOY_TOP_Y + BattleSimulatorV3.DEPLOY_BOTTOM_Y) / 2.0
	draw_line(Vector2(0, mid_y), Vector2(BattleSimulatorV3.FIELD_WIDTH, mid_y),
		Color(0.9, 0.82, 0.55, 0.15), 1.0)

func _draw_formations(sim: BattleSimulatorV3) -> void:
	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(sim.attacker_formations)
	all_formations.append_array(sim.defender_formations)

	var selected: BattleSimulatorV3.BattleFormationV3 = battle_scene.selected_formation

	for f in all_formations:
		if f.is_fled or f.is_dead:
			continue

		var is_player: bool = f.side == battle_scene.player_side
		var base_color: Color = COLOR_PLAYER if is_player else COLOR_ENEMY
		if f.is_routing:
			base_color = base_color.lerp(COLOR_ROUTING_TINT, 0.5)

		var is_selected: bool = f == selected

		# Draw entities at variable radius based on unit type
		var radius := BattleSimulatorV3.get_entity_radius(f)
		var limit := mini(f.entities_alive, f.entity_positions.size())
		for i in limit:
			var epos: Vector2 = f.entity_positions[i]
			var c := base_color
			if i == 0:
				c = c.lightened(0.15)
			if is_selected:
				c = c.lerp(COLOR_SELECTED, 0.25)
			draw_circle(epos, radius, c)

		# Selection highlight ring around entities
		if is_selected:
			for i in limit:
				var epos: Vector2 = f.entity_positions[i]
				draw_arc(epos, radius + 2.0, 0, TAU, 16,
					COLOR_SELECTED * Color(1, 1, 1, 0.6), 1.0)

		# Facing arrow at formation center
		_draw_facing_arrow(f, base_color)

		# HP bar below formation, morale bar below that
		_draw_hp_bar(f)
		_draw_morale_bar(f)

		# Routing indicator
		if f.is_routing:
			draw_string(ThemeDB.fallback_font, f.position + Vector2(-4, -20),
				"!", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 0.3, 0.2))

		# Name label
		draw_string(ThemeDB.fallback_font, f.position + Vector2(-30, -28),
			f.display_name.left(8), HORIZONTAL_ALIGNMENT_CENTER, 60, 9,
			Color(0.9, 0.85, 0.7, 0.8) if is_player else Color(0.9, 0.7, 0.65, 0.8))

func _draw_facing_arrow(f: BattleSimulatorV3.BattleFormationV3, base_color: Color) -> void:
	var facing := f.get_facing_vector()
	var tip := f.position + facing * 14.0
	var perp := Vector2(-facing.y, facing.x) * 5.0
	var base_pt := f.position - facing * 4.0

	var points := PackedVector2Array([tip, base_pt + perp, base_pt - perp])
	draw_colored_polygon(points, Color(1, 1, 1, 0.5))

func _draw_morale_bar(f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_formation_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 2.5
	var bar_x := bounds.position.x
	# Position below the HP bar (HP bar is at bounds.bottom + 2, height 2.5)
	var bar_y := bounds.position.y + bounds.size.y + 2 + 2.5 + 1.5

	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	var morale_ratio := clampf(f.current_morale / float(f.base_morale), 0.0, 1.5)
	var fill_width := bar_width * minf(morale_ratio, 1.0)
	var morale_color := Color(1, 1, 1, 0.9)
	if morale_ratio < 0.3:
		morale_color = Color(1, 1, 1, 0.4)
	elif morale_ratio < 0.6:
		morale_color = Color(1, 1, 1, 0.65)
	draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), morale_color)

func _draw_hp_bar(f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_formation_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 2.5
	var bar_x := bounds.position.x
	var bar_y := bounds.position.y + bounds.size.y + 2

	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
	var fill_width := bar_width * hp_ratio
	var hp_color := Color(0.3, 0.75, 0.3)
	if hp_ratio < 0.3:
		hp_color = Color(0.85, 0.25, 0.2)
	elif hp_ratio < 0.6:
		hp_color = Color(0.85, 0.65, 0.2)
	draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), hp_color)

func _get_formation_bounds(f: BattleSimulatorV3.BattleFormationV3) -> Rect2:
	if f.entity_positions.size() == 0:
		return Rect2(f.position.x - 15, f.position.y - 15, 30, 30)

	var min_x := f.entity_positions[0].x
	var max_x := min_x
	var min_y := f.entity_positions[0].y
	var max_y := min_y

	for i in range(1, mini(f.entities_alive, f.entity_positions.size())):
		var p := f.entity_positions[i]
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)

	return Rect2(min_x - 5, min_y - 5, max_x - min_x + 10, max_y - min_y + 10)
