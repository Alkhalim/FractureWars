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
const COLOR_BAR_OUTLINE := Color(0.6, 0.55, 0.4, 0.5)

var _flash_formations: Dictionary = {} # formation instance_id -> flash_timer (float)
var _hit_scale: Dictionary = {} # formation instance_id -> scale_timer (float)
var _bounds_cache: Dictionary = {} # formation instance_id -> Rect2
var _terrain_shader_material: ShaderMaterial
var _terrain_texture: ImageTexture
var _terrain_rect: ColorRect

func setup_terrain_shader(sim: BattleSimulatorV3) -> void:
	var shader := load("res://assets/shaders/battle_terrain.gdshader") as Shader
	if shader == null:
		return

	# Build terrain data texture (1 pixel per cell, R channel = terrain type enum value / 255)
	var img := Image.create(sim.terrain_grid_w, sim.terrain_grid_h, false, Image.FORMAT_R8)
	for y in sim.terrain_grid_h:
		for x in sim.terrain_grid_w:
			var pos := Vector2i(x, y)
			var terrain_type: int = sim.terrain_grid.get(pos, 0)
			img.set_pixel(x, y, Color(float(terrain_type) / 255.0, 0, 0))
	_terrain_texture = ImageTexture.create_from_image(img)

	_terrain_shader_material = ShaderMaterial.new()
	_terrain_shader_material.shader = shader
	_terrain_shader_material.set_shader_parameter("terrain_data", _terrain_texture)
	_terrain_shader_material.set_shader_parameter("grid_size", Vector2(sim.terrain_grid_w, sim.terrain_grid_h))
	_terrain_shader_material.set_shader_parameter("field_size", Vector2(BattleSimulatorV3.FIELD_WIDTH, BattleSimulatorV3.FIELD_HEIGHT))
	_terrain_shader_material.set_shader_parameter("time", 0.0)

	_terrain_rect = ColorRect.new()
	_terrain_rect.size = Vector2(BattleSimulatorV3.FIELD_WIDTH, BattleSimulatorV3.FIELD_HEIGHT)
	_terrain_rect.material = _terrain_shader_material
	_terrain_rect.z_index = -1
	add_child(_terrain_rect)

func trigger_flash(formation_id: StringName) -> void:
	_flash_formations[formation_id] = 0.15
	_hit_scale[formation_id] = 0.15

func _process(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for fid in _flash_formations:
		_flash_formations[fid] -= delta
		if _flash_formations[fid] <= 0.0:
			to_remove.append(fid)
	for fid in to_remove:
		_flash_formations.erase(fid)

	var scale_remove: Array[StringName] = []
	for fid in _hit_scale:
		_hit_scale[fid] -= delta
		if _hit_scale[fid] <= 0.0:
			scale_remove.append(fid)
	for fid in scale_remove:
		_hit_scale.erase(fid)

	if _flash_formations.size() > 0 or _hit_scale.size() > 0:
		queue_redraw()
	elif battle_scene and battle_scene.is_simulating:
		# Keep redrawing during simulation for time-based animations (routing pulse, aura)
		queue_redraw()

	if _terrain_shader_material:
		_terrain_shader_material.set_shader_parameter("time", Time.get_ticks_msec() * 0.001)

func _draw() -> void:
	if battle_scene == null:
		return

	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return

	# Lazy init terrain shader
	if _terrain_rect == null and sim.terrain_grid.size() > 0:
		setup_terrain_shader(sim)

	_bounds_cache.clear()

	# 1. Draw terrain background
	_draw_terrain(sim)

	# 2. Draw deploy zone tints (only during setup)
	if battle_scene.current_phase == battle_scene.Phase.SETUP:
		_draw_deploy_zones(sim)

	# 3. Draw dead soldier marks (faint outlines where soldiers fell)
	_draw_dead_marks(sim)

	# 4. Draw entities for each formation
	_draw_formations(sim)

	# 5. Draw field border
	draw_rect(Rect2(0, 0, BattleSimulatorV3.FIELD_WIDTH, BattleSimulatorV3.FIELD_HEIGHT),
		Color(0.55, 0.42, 0.2, 0.8), false, 2.0)

func _draw_terrain(sim: BattleSimulatorV3) -> void:
	if _terrain_rect != null:
		return  # Shader handles terrain rendering
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
	var hovered: BattleSimulatorV3.BattleFormationV3 = battle_scene.hovered_formation

	for f in all_formations:
		if f.is_fled or f.is_dead:
			continue

		var is_player: bool = f.side == battle_scene.player_side
		var base_color: Color = COLOR_PLAYER if is_player else COLOR_ENEMY
		if f.is_routing:
			base_color = base_color.lerp(Color(0.55, 0.25, 0.2), 0.55)
			base_color.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)

		var is_selected: bool = f == selected
		var is_hovered: bool = f == hovered and not is_selected

		# Draw entities at variable radius based on unit type
		var radius := BattleSimulatorV3.get_entity_radius(f)
		var hit_scale: float = 1.0
		if _hit_scale.has(f.instance_id):
			hit_scale = 1.0 + 0.2 * (_hit_scale[f.instance_id] / 0.15)
		var facing_angle: float = f.rotation
		var limit := mini(f.entities_alive, f.entity_positions.size())
		var time_ms := Time.get_ticks_msec()
		for i in limit:
			var epos: Vector2 = f.entity_positions[i]
			# Routing scatter jitter — "breaking ranks" look
			if f.is_routing:
				var jx := sin(i * 2.3 + time_ms * 0.004) * 2.5
				var jy := cos(i * 3.1 + time_ms * 0.003) * 2.0
				epos += Vector2(jx, jy)
			var c := base_color
			if i == 0:
				c = c.lightened(0.15)
			if is_selected:
				c = c.lerp(COLOR_SELECTED, 0.25)
			elif is_hovered:
				c = c.lightened(0.15)
			_draw_entity(epos, radius * hit_scale, c, f.tags, facing_angle)
			# Attack flash overlay
			if _flash_formations.has(f.instance_id):
				_draw_entity(epos, radius * hit_scale, Color(1, 1, 1, 0.5), f.tags, facing_angle)

		# Charge trail for fast-moving units
		if f.current_order == Enums.BattleOrder.CHARGE and not f.is_routing:
			var facing := f.get_facing_vector()
			var trail_color := Color(base_color.r, base_color.g, base_color.b, 0.15)
			for i in mini(f.entities_alive, f.entity_positions.size()):
				var epos: Vector2 = f.entity_positions[i]
				var trail_end := epos - facing * radius * 3.0
				draw_line(epos, trail_end, trail_color, 1.5)

		# Selection highlight ring around entities
		if is_selected:
			for i in limit:
				var epos: Vector2 = f.entity_positions[i]
				draw_arc(epos, radius + 2.0, 0, TAU, 16,
					COLOR_SELECTED * Color(1, 1, 1, 0.6), 1.0)
		elif is_hovered:
			# Hover highlight: softer ring
			for i in limit:
				var epos: Vector2 = f.entity_positions[i]
				draw_arc(epos, radius + 2.0, 0, TAU, 16,
					Color(0.9, 0.85, 0.7, 0.35), 1.0)

		# Aura visual
		if f.damage_aura_radius > 0.0:
			var aura_alpha := 0.1 + 0.06 * sin(Time.get_ticks_msec() * 0.003)
			var aura_color := Color(base_color.r, base_color.g, base_color.b, aura_alpha)
			draw_arc(f.position, f.damage_aura_radius, 0, TAU, 24, aura_color, 2.0)

		# Morale aura visual
		if f.morale_aura != 0 and f.fear_radius > 0 and not f.is_dead:
			var aura_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var pulse := 0.06 + 0.03 * sin(Time.get_ticks_msec() * 0.002 + f.position.x * 0.1)
			if f.morale_aura > 0:
				var aura_col := Color(0.8, 0.9, 0.4, pulse)
				draw_arc(f.position, aura_range, 0, TAU, 32, aura_col, 1.5)
			else:
				var aura_col := Color(0.7, 0.15, 0.1, pulse)
				draw_arc(f.position, aura_range, 0, TAU, 32, aura_col, 1.5)

		# Healing aura visual (soft green inner ring)
		if f.healing_aura > 0.0 and f.fear_radius > 0 and not f.is_dead:
			var heal_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var heal_pulse := 0.05 + 0.04 * sin(Time.get_ticks_msec() * 0.0015 + f.position.y * 0.1)
			var heal_col := Color(0.3, 0.85, 0.4, heal_pulse)
			draw_arc(f.position, heal_range * 0.85, 0, TAU, 32, heal_col, 1.5)

		# Armor aura visual (pale blue-white inner ring)
		if f.armor_aura > 0 and f.fear_radius > 0 and not f.is_dead:
			var armor_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var armor_pulse := 0.05 + 0.03 * sin(Time.get_ticks_msec() * 0.0018 + f.position.y * 0.15)
			var armor_col := Color(0.6, 0.7, 0.9, armor_pulse)
			draw_arc(f.position, armor_range * 0.9, 0, TAU, 32, armor_col, 1.5)

		# Facing arrow at formation center
		_draw_facing_arrow(f, base_color)

		# HP bar below formation, morale bar below that, resource bars below those
		_draw_hp_bar(f)
		_draw_morale_bar(f)
		_draw_resource_bars(f)

		# Routing indicator — "!!" with rotating panic lines
		if f.is_routing:
			draw_string(ThemeDB.fallback_font, f.position + Vector2(-6, -20),
				"!!", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 0.3, 0.2))
			var panic_center := f.position + Vector2(0, -24)
			var panic_rot := time_ms * 0.005
			var panic_color := Color(1, 0.3, 0.2, 0.6)
			for k in 3:
				var a := panic_rot + TAU * float(k) / 3.0
				var start := panic_center + Vector2(cos(a), sin(a)) * 5.0
				var end := panic_center + Vector2(cos(a), sin(a)) * 9.0
				draw_line(start, end, panic_color, 1.5)

		# Name label
		draw_string(ThemeDB.fallback_font, f.position + Vector2(-30, -28),
			f.display_name.left(8), HORIZONTAL_ALIGNMENT_CENTER, 60, 9,
			Color(0.9, 0.85, 0.7, 0.8) if is_player else Color(0.9, 0.7, 0.65, 0.8))

func _draw_dead_marks(sim: BattleSimulatorV3) -> void:
	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(sim.attacker_formations)
	all_formations.append_array(sim.defender_formations)

	for f in all_formations:
		if f.dead_entity_positions.size() == 0:
			continue
		var r := BattleSimulatorV3.get_entity_radius(f) * 0.5
		for pos in f.dead_entity_positions:
			_draw_blood_splatter(pos, r, int(pos.x * 73 + pos.y * 137))

func _draw_blood_splatter(pos: Vector2, radius: float, seed_val: int) -> void:
	# 2-3 irregular droplet polygons per death position
	var rng := seed_val
	var droplet_count := 2 + (absi(rng) % 2) # 2 or 3
	for d in droplet_count:
		rng = absi(rng * 1103515245 + 12345) # LCG for determinism
		var vert_count := 4 + (rng % 3) # 4-6 vertices
		rng = absi(rng * 1103515245 + 12345)
		var offset_angle := float(rng % 628) / 100.0
		rng = absi(rng * 1103515245 + 12345)
		var offset_dist := float(rng % 100) / 100.0 * radius * 0.8
		var center := pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist
		var pts := PackedVector2Array()
		for v in vert_count:
			rng = absi(rng * 1103515245 + 12345)
			var a := TAU * float(v) / float(vert_count) + float(rng % 100) / 200.0
			rng = absi(rng * 1103515245 + 12345)
			var r := radius * (0.3 + float(rng % 100) / 150.0)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		# Dark red/brown, subtle alpha matching old X marks
		rng = absi(rng * 1103515245 + 12345)
		var red := 0.25 + float(rng % 100) / 667.0 # 0.25 - 0.40
		rng = absi(rng * 1103515245 + 12345)
		var green := 0.08 + float(rng % 100) / 1250.0 # 0.08 - 0.16
		var blue := 0.05 + float(rng % 100) / 2000.0 # 0.05 - 0.10
		draw_colored_polygon(pts, Color(red, green, blue, 0.2))

func _draw_facing_arrow(f: BattleSimulatorV3.BattleFormationV3, base_color: Color) -> void:
	var facing := f.get_facing_vector()
	var tip := f.position + facing * 14.0
	var perp := Vector2(-facing.y, facing.x) * 5.0
	var base_pt := f.position - facing * 4.0

	var points := PackedVector2Array([tip, base_pt + perp, base_pt - perp])
	draw_colored_polygon(points, Color(1, 1, 1, 0.5))

func _draw_entity(pos: Vector2, radius: float, color: Color, tags: Array, facing_angle: float) -> void:
	if tags.has("flying"):
		_draw_flying_entity(pos, radius, color, facing_angle)
	elif tags.has("swarm") and not tags.has("cavalry"):
		_draw_swarm_entity(pos, radius, color)
	elif tags.has("monster"):
		# Hexagon + inner ring
		var pts := PackedVector2Array()
		for k in 6:
			var a := TAU * float(k) / 6.0
			pts.append(pos + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, color)
		draw_arc(pos, radius * 0.65, 0, TAU, 6, color.darkened(0.3), 1.5)
	elif tags.has("construct") and not tags.has("infantry"):
		_draw_construct_entity(pos, radius, color)
	elif tags.has("beast") and not tags.has("cavalry"):
		_draw_beast_entity(pos, radius, color, facing_angle)
	elif tags.has("cavalry"):
		# Triangle pointing in facing direction
		var pts := PackedVector2Array()
		for k in 3:
			var a := facing_angle + TAU * float(k) / 3.0 - PI / 2.0
			pts.append(pos + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, color)
	elif tags.has("mage"):
		_draw_mage_entity(pos, radius, color)
	elif tags.has("ranged"):
		_draw_ranged_entity(pos, radius, color)
	elif tags.has("support"):
		# Circle with plus sign
		draw_circle(pos, radius, color)
		var cr := radius * 0.55
		draw_line(pos + Vector2(-cr, 0), pos + Vector2(cr, 0), color.lightened(0.35), 1.5)
		draw_line(pos + Vector2(0, -cr), pos + Vector2(0, cr), color.lightened(0.35), 1.5)
	elif tags.has("infantry"):
		# Diamond (rotated square)
		var pts := PackedVector2Array()
		for k in 4:
			var a := PI / 4.0 + TAU * float(k) / 4.0
			pts.append(pos + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, color)
	else:
		# Default: circle
		draw_circle(pos, radius, color)

func _draw_flying_entity(pos: Vector2, radius: float, color: Color, facing_angle: float) -> void:
	# Winged triangle: body triangle + two wing extensions
	var r := radius
	var fa := facing_angle - PI / 2.0
	# Body triangle
	var tip := pos + Vector2(cos(fa), sin(fa)) * r
	var bl := pos + Vector2(cos(fa + 2.3), sin(fa + 2.3)) * r * 0.8
	var br := pos + Vector2(cos(fa - 2.3), sin(fa - 2.3)) * r * 0.8
	draw_colored_polygon(PackedVector2Array([tip, bl, br]), color)
	# Left wing
	var wl := pos + Vector2(cos(fa + 1.8), sin(fa + 1.8)) * r * 1.4
	draw_colored_polygon(PackedVector2Array([bl, wl, pos]), color.lightened(0.15))
	# Right wing
	var wr := pos + Vector2(cos(fa - 1.8), sin(fa - 1.8)) * r * 1.4
	draw_colored_polygon(PackedVector2Array([br, wr, pos]), color.lightened(0.15))

func _draw_swarm_entity(pos: Vector2, radius: float, color: Color) -> void:
	# 3 tiny circles in triangle arrangement
	var r := radius * 0.4
	var spread := radius * 0.5
	draw_circle(pos + Vector2(0, -spread), r, color)
	draw_circle(pos + Vector2(-spread * 0.87, spread * 0.5), r, color)
	draw_circle(pos + Vector2(spread * 0.87, spread * 0.5), r, color)

func _draw_construct_entity(pos: Vector2, radius: float, color: Color) -> void:
	# Outer square + inner darker square
	var r := radius * 0.85
	draw_rect(Rect2(pos.x - r, pos.y - r, r * 2, r * 2), color)
	var ir := r * 0.55
	draw_rect(Rect2(pos.x - ir, pos.y - ir, ir * 2, ir * 2), color.darkened(0.3))

func _draw_beast_entity(pos: Vector2, radius: float, color: Color, facing_angle: float) -> void:
	# Irregular 5-point claw shape
	var pts := PackedVector2Array()
	var fa := facing_angle - PI / 2.0
	var radii := [1.0, 0.6, 0.9, 0.55, 0.95]
	for k in 5:
		var a := fa + TAU * float(k) / 5.0
		pts.append(pos + Vector2(cos(a), sin(a)) * radius * radii[k])
	draw_colored_polygon(pts, color)

func _draw_mage_entity(pos: Vector2, radius: float, color: Color) -> void:
	# 4-point star (alternating long/short radius) + center dot
	var pts := PackedVector2Array()
	for k in 8:
		var a := TAU * float(k) / 8.0 - PI / 8.0
		var r := radius if k % 2 == 0 else radius * 0.4
		pts.append(pos + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)
	draw_circle(pos, radius * 0.2, color.lightened(0.4))

func _draw_ranged_entity(pos: Vector2, radius: float, color: Color) -> void:
	# Small filled square with circle outline
	var r := radius * 0.65
	draw_rect(Rect2(pos.x - r, pos.y - r, r * 2, r * 2), color)
	draw_arc(pos, radius, 0, TAU, 12, color.lightened(0.25), 1.5)

func _draw_morale_bar(f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_cached_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 5.0
	var bar_x := bounds.position.x
	# Position below the HP bar (HP bar is at bounds.bottom + 2, height 5.0)
	var bar_y := bounds.position.y + bounds.size.y + 2 + 5.0 + 1.5

	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	var morale_ratio := clampf(f.current_morale / float(f.base_morale), 0.0, 1.5)
	var fill_width := bar_width * minf(morale_ratio, 1.0)
	var morale_color := Color(1, 1, 1, 0.9)
	if morale_ratio < 0.3:
		morale_color = Color(1, 1, 1, 0.4)
	elif morale_ratio < 0.6:
		morale_color = Color(1, 1, 1, 0.65)
	draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), morale_color)
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)

func _draw_hp_bar(f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_cached_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 5.0
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
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)

func _get_cached_bounds(f: BattleSimulatorV3.BattleFormationV3) -> Rect2:
	if _bounds_cache.has(f.instance_id):
		return _bounds_cache[f.instance_id]
	var bounds := _get_formation_bounds(f)
	_bounds_cache[f.instance_id] = bounds
	return bounds

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

func _draw_resource_bars(f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_cached_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 4.0
	var bar_x := bounds.position.x
	# Start below HP bar (5.0) + gap (1.5) + morale bar (5.0) + gap (1.5)
	var base_y := bounds.position.y + bounds.size.y + 2 + 5.0 + 1.5 + 5.0 + 1.5
	var bar_idx := 0
	var bg_color := Color(0.15, 0.12, 0.1, 0.6)

	# Endurance bar (yellow) — all units
	if f.max_endurance > 0.0:
		var y := base_y + bar_idx * (bar_height + 1.0)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(f.current_endurance / f.max_endurance, 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.9, 0.82, 0.25, 0.85)
		if ratio < 0.3:
			color = Color(0.7, 0.55, 0.15, 0.6)
		draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)
		bar_idx += 1

	# Ammo bar (beige) — ranged non-mage units only
	if f.max_ammo > 0:
		var y := base_y + bar_idx * (bar_height + 1.0)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(float(f.current_ammo) / float(f.max_ammo), 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.82, 0.75, 0.55, 0.85)
		if ratio < 0.3:
			color = Color(0.65, 0.55, 0.35, 0.6)
		draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)
		bar_idx += 1

	# Mana bar (blue) — mage units only
	if f.max_mana > 0.0:
		var y := base_y + bar_idx * (bar_height + 1.0)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(f.current_mana / f.max_mana, 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.3, 0.45, 0.9, 0.85)
		if ratio < 0.3:
			color = Color(0.2, 0.3, 0.65, 0.6)
		draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)
