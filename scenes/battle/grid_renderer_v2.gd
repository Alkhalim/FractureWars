extends Node2D

var battle_scene = null  # Untyped to allow access to BattleV2 properties

func _draw() -> void:
	if battle_scene == null:
		return

	var sim: BattleSimulatorV2 = battle_scene.simulator
	if sim == null:
		return

	var cs: int = battle_scene.cell_size
	var gw: int = battle_scene.grid_width
	var gh: int = battle_scene.grid_height

	# 1. Draw terrain cells
	for y in gh:
		for x in gw:
			var pos := Vector2i(x, y)
			var terrain_type: Enums.BattleTerrain = sim.terrain.get(pos, Enums.BattleTerrain.OPEN)
			var color: Color = battle_scene.TERRAIN_COLORS.get(terrain_type, battle_scene.TERRAIN_COLORS[Enums.BattleTerrain.OPEN])

			# Tint deploy zones
			if y >= sim.deploy_bottom_start:
				color = color.lerp(battle_scene.COLOR_DEPLOY_TINT, 0.3)
			elif y < sim.deploy_top_end:
				color = color.lerp(battle_scene.COLOR_ENEMY_TINT, 0.3)

			# Mark impassable
			if not BattleTerrainGen.is_passable(terrain_type):
				color = color.lightened(0.1)

			draw_rect(Rect2(x * cs, y * cs, cs - 1, cs - 1), color)

	# 2. Draw formation tiles
	var all_formations: Array[BattleSimulatorV2.BattleFormation] = []
	all_formations.append_array(sim.attacker_formations)
	all_formations.append_array(sim.defender_formations)

	for formation in all_formations:
		if formation.is_fled or formation.is_dead:
			continue

		var base_color: Color = battle_scene.COLOR_ATTACKER if formation.side == 0 else battle_scene.COLOR_DEFENDER
		if formation.is_routing:
			base_color = base_color.lerp(Color.DARK_GRAY, 0.5)

		var is_selected: bool = formation == battle_scene.selected_formation

		for tile in formation.occupied_tiles:
			var c: Color = base_color if tile == formation.anchor_pos else base_color.darkened(0.15)
			if is_selected:
				c = c.lerp(battle_scene.COLOR_SELECTED, 0.3)
			draw_rect(Rect2(tile.x * cs, tile.y * cs, cs - 1, cs - 1), c)

		# Selection border
		if is_selected:
			for tile in formation.occupied_tiles:
				draw_rect(Rect2(tile.x * cs, tile.y * cs, cs - 1, cs - 1), battle_scene.COLOR_SELECTED, false, 1.5)

		# 3. Facing arrow on anchor
		_draw_facing_indicator(formation, cs)

		# 4. Morale bar above formation
		if formation.occupied_tiles.size() > 0:
			_draw_morale_bar(formation, cs)

		# 5. HP bar below formation
		if formation.occupied_tiles.size() > 0:
			_draw_hp_bar(formation, cs)

		# 6. Routing indicator
		if formation.is_routing:
			var anchor_px := Vector2(formation.anchor_pos.x * cs + cs / 2.0, formation.anchor_pos.y * cs - 2)
			draw_string(ThemeDB.fallback_font, anchor_px, "!", HORIZONTAL_ALIGNMENT_CENTER, -1, clampi(cs, 8, 16), Color(1, 0.3, 0.2))

	# 7. Grid border
	draw_rect(Rect2(0, 0, gw * cs, gh * cs), Color(0.55, 0.42, 0.2, 0.8), false, 2.0)

	# 8. Zone separator line
	var mid_y := float(sim.deploy_top_end + sim.deploy_bottom_start) / 2.0 * cs
	draw_line(Vector2(0, mid_y), Vector2(gw * cs, mid_y), Color(0.9, 0.82, 0.55, 0.2), 1.0)

func _draw_facing_indicator(formation: BattleSimulatorV2.BattleFormation, cs: int) -> void:
	var anchor := formation.anchor_pos
	var center := Vector2(anchor.x * cs + cs / 2.0, anchor.y * cs + cs / 2.0)
	var facing := Vector2(formation.facing.x, formation.facing.y)
	var tip := center + facing * (cs * 0.4)
	var perp := Vector2(-facing.y, facing.x) * (cs * 0.2)

	# Draw small triangle pointing in facing direction
	var points := PackedVector2Array([
		tip,
		center - facing * (cs * 0.15) + perp,
		center - facing * (cs * 0.15) - perp,
	])
	draw_colored_polygon(points, Color(1, 1, 1, 0.7))

func _draw_morale_bar(formation: BattleSimulatorV2.BattleFormation, cs: int) -> void:
	# Find top-left of formation bounding box
	var min_x := 9999
	var min_y := 9999
	var max_x := -9999
	for tile in formation.occupied_tiles:
		min_x = mini(min_x, tile.x)
		min_y = mini(min_y, tile.y)
		max_x = maxi(max_x, tile.x)

	var bar_width := float((max_x - min_x + 1) * cs)
	var bar_height := maxf(2.0, cs * 0.15)
	var bar_x := float(min_x * cs)
	var bar_y := float(min_y * cs) - bar_height - 2

	# Background
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	# Morale fill
	var morale_ratio := clampf(formation.current_morale / float(formation.base_morale), 0.0, 1.5)
	var fill_width := bar_width * minf(morale_ratio, 1.0)
	var morale_color := Color(0.4, 0.8, 0.35)
	if morale_ratio < 0.3:
		morale_color = Color(0.85, 0.25, 0.2)
	elif morale_ratio < 0.6:
		morale_color = Color(0.85, 0.75, 0.2)
	draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), morale_color)

func _draw_hp_bar(formation: BattleSimulatorV2.BattleFormation, cs: int) -> void:
	var min_x := 9999
	var max_x := -9999
	var max_y := -9999
	for tile in formation.occupied_tiles:
		min_x = mini(min_x, tile.x)
		max_x = maxi(max_x, tile.x)
		max_y = maxi(max_y, tile.y)

	var bar_width := float((max_x - min_x + 1) * cs)
	var bar_height := maxf(2.0, cs * 0.15)
	var bar_x := float(min_x * cs)
	var bar_y := float((max_y + 1) * cs) + 1

	# Background
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	# HP fill
	var hp_ratio := clampf(float(formation.current_hp) / float(formation.max_hp), 0.0, 1.0)
	var fill_width := bar_width * hp_ratio
	var hp_color := Color(0.3, 0.75, 0.3)
	if hp_ratio < 0.3:
		hp_color = Color(0.85, 0.25, 0.2)
	elif hp_ratio < 0.6:
		hp_color = Color(0.85, 0.65, 0.2)
	draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), hp_color)
