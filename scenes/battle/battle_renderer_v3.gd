extends Node2D

var battle_scene = null  # Untyped — set by BattleV3

const TERRAIN_COLORS := {
	Enums.BattleTerrain.OPEN:    Color(0.15, 0.14, 0.12, 1),
	Enums.BattleTerrain.FOREST:  Color(0.12, 0.28, 0.10, 1),
	Enums.BattleTerrain.ROCK:    Color(0.30, 0.26, 0.22, 1),
	Enums.BattleTerrain.WATER:   Color(0.08, 0.15, 0.32, 1),
	Enums.BattleTerrain.SAND:    Color(0.32, 0.28, 0.16, 1),
	Enums.BattleTerrain.MUD:     Color(0.18, 0.14, 0.08, 1),
	Enums.BattleTerrain.ICE:     Color(0.24, 0.30, 0.38, 1),
	Enums.BattleTerrain.CRYSTAL: Color(0.26, 0.12, 0.32, 1),
	Enums.BattleTerrain.BRUSH:   Color(0.16, 0.22, 0.12, 1),
	Enums.BattleTerrain.CALTROPS: Color(0.35, 0.30, 0.20, 1),
	Enums.BattleTerrain.DITCH:   Color(0.20, 0.16, 0.10, 1),
	Enums.BattleTerrain.PALING:  Color(0.40, 0.32, 0.18, 1),
	Enums.BattleTerrain.MINE:    Color(0.15, 0.14, 0.12, 1),
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

# Entity shape resolved once per formation (tags/base radius are static per
# formation) — _draw_entity previously ran ~10 tags.has() string checks per
# entity per pass, ~50k/frame on large battles.
enum _Shape { FLYING, SWARM, MONSTER_LARGE, MONSTER, CONSTRUCT_LARGE, CONSTRUCT, BEAST, CAVALRY, MAGE, RANGED, SUPPORT, INFANTRY, CIRCLE }
var _shape_cache: Dictionary = {} # formation instance_id -> _Shape

# Dead marks (blood splatters) accumulate slowly but were re-submitted every
# frame (~8.8ms at 266 deaths). They live on a child canvas item that only
# redraws when the death count changes.
var _dead_marks_layer: _DeadMarksLayer
var _last_dead_count := -1

class _DeadMarksLayer extends Node2D:
	var renderer: Node2D = null
	func _draw() -> void:
		if renderer:
			renderer._draw_dead_marks_onto(self)

class _OverlayLayer extends Node2D:
	## Formation-level overlays (bars, names, rings, vignette) drawn above the
	## MultiMesh entity layers.
	var renderer: Node2D = null
	func _draw() -> void:
		if renderer:
			renderer._draw_overlay_onto(self)

# ── MultiMesh entity rendering ────────────────────────────────
# Entities are GPU-instanced per shape: one outline MultiMesh (black, slightly
# larger) plus one fill MultiMesh per shape, with per-instance transform
# (position/rotation/radius) and color. Replaces ~5000 immediate-mode canvas
# commands per frame with a handful of instanced draws.
var _mm_out_root: Node2D    # all outline MultiMeshInstance2Ds (drawn first)
var _mm_fill_root: Node2D   # all fill MultiMeshInstance2Ds
var _overlay_layer: _OverlayLayer
var _shape_mm: Dictionary = {}  # _Shape -> {out_mm, fill_mm, out_buf, fill_buf, cap}
const _MM_STRIDE := 12  # 8 transform floats + 4 color floats

# Previous-tick entity positions for interpolation (instance_id -> PackedVector2Array)
var _prev_positions: Dictionary = {}

func _ready() -> void:
	_ensure_layers()

## Creates the child render layers. Idempotent and called lazily from _process
## too: BattleV3 attaches this script via set_script() on an already-readied
## node, in which case _ready never fires.
func _ensure_layers() -> void:
	if _overlay_layer != null:
		return
	_dead_marks_layer = _DeadMarksLayer.new()
	_dead_marks_layer.renderer = self
	# Behind this node's own canvas (terrain/shadows), above the terrain rect (z -1)
	_dead_marks_layer.show_behind_parent = true
	add_child(_dead_marks_layer)
	_mm_out_root = Node2D.new()
	add_child(_mm_out_root)
	_mm_fill_root = Node2D.new()
	add_child(_mm_fill_root)
	_overlay_layer = _OverlayLayer.new()
	_overlay_layer.renderer = self
	add_child(_overlay_layer)

## Called by BattleV3 right before each simulate_tick(): captures the pre-tick
## entity positions so rendering can interpolate smoothly between ticks.
func snapshot_positions() -> void:
	if battle_scene == null or battle_scene.simulator == null:
		return
	var sim: BattleSimulatorV3 = battle_scene.simulator
	for f in sim.attacker_formations:
		_prev_positions[f.instance_id] = f.entity_positions.duplicate()
	for f in sim.defender_formations:
		_prev_positions[f.instance_id] = f.entity_positions.duplicate()

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

	if battle_scene and battle_scene.simulator:
		_ensure_layers()
		# Entities are GPU-instanced and interpolated between sim ticks, so a
		# full-rate update is cheap: buffer fill + a light overlay canvas.
		_update_entity_multimeshes()
		queue_redraw()
		if _overlay_layer:
			_overlay_layer.queue_redraw()
		# Redraw the dead-marks layer only when new entities died
		if _dead_marks_layer and battle_scene.is_simulating:
			var sim = battle_scene.simulator
			var dead_count := 0
			for f in sim.attacker_formations:
				dead_count += f.dead_entity_positions.size()
			for f in sim.defender_formations:
				dead_count += f.dead_entity_positions.size()
			if dead_count != _last_dead_count:
				_last_dead_count = dead_count
				_dead_marks_layer.queue_redraw()

	if _terrain_shader_material:
		_terrain_shader_material.set_shader_parameter("time", Time.get_ticks_msec() * 0.001)

func _draw() -> void:
	## Below-entity content only. Entities are instanced MultiMeshes (children
	## of this node); bars/names/rings/vignette draw on _overlay_layer above.
	if battle_scene == null:
		return

	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return

	# Lazy init terrain shader
	if _terrain_rect == null and sim.terrain_grid.size() > 0:
		setup_terrain_shader(sim)

	# 1. Draw terrain background
	_draw_terrain(sim)

	# 2. Draw deploy zone tints (only during setup)
	if battle_scene.current_phase == battle_scene.Phase.SETUP:
		_draw_deploy_zones(sim)

	# 3. Dead soldier marks are drawn by _dead_marks_layer (redraws only on deaths)

	# 4. Below-entity per-formation effects: shadows + charge trails
	_draw_below_entities(sim)

func _draw_overlay_onto(layer: CanvasItem) -> void:
	## Everything that renders above the instanced entities.
	if battle_scene == null:
		return
	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return

	_bounds_cache.clear()
	_draw_formation_overlays(layer, sim)

	# Drag-selection rectangle
	if battle_scene._drag_select_active:
		var dr: Rect2 = battle_scene._drag_select_rect
		layer.draw_rect(dr, Color(0.95, 0.85, 0.3, 0.08))
		layer.draw_rect(dr, Color(0.95, 0.85, 0.3, 0.6), false, 1.5)

	# Terrain hover tooltip during setup
	if battle_scene.current_phase == battle_scene.Phase.SETUP and battle_scene._terrain_hover_info.size() > 0:
		var info: Dictionary = battle_scene._terrain_hover_info
		var tip_pos: Vector2 = info.get("pos", Vector2.ZERO) + Vector2(15, -20)
		var tip_text: String = info.get("text", "")
		# Shadow then text
		layer.draw_string(ThemeDB.fallback_font, tip_pos + Vector2(1, 1), tip_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		layer.draw_string(ThemeDB.fallback_font, tip_pos, tip_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.85, 0.7, 0.9))

	# Battlefield vignette (darkened edges)
	_draw_vignette(layer)

	# Field border with corner markers
	var fw := BattleSimulatorV3.FIELD_WIDTH
	var fh := BattleSimulatorV3.FIELD_HEIGHT
	layer.draw_rect(Rect2(0, 0, fw, fh), Color(0.55, 0.42, 0.2, 0.7), false, 2.5)
	# Corner ornaments
	var corner_len := 30.0
	var cc := Color(0.7, 0.55, 0.3, 0.6)
	for corner in [Vector2(0, 0), Vector2(fw, 0), Vector2(0, fh), Vector2(fw, fh)]:
		var dx := 1.0 if corner.x < fw * 0.5 else -1.0
		var dy := 1.0 if corner.y < fh * 0.5 else -1.0
		layer.draw_line(corner, corner + Vector2(dx * corner_len, 0), cc, 2.0)
		layer.draw_line(corner, corner + Vector2(0, dy * corner_len), cc, 2.0)

## Interpolation factor between the previous and current sim tick.
func _interp_t() -> float:
	if battle_scene and battle_scene.is_simulating and battle_scene.sim_speed > 0.0:
		return clampf(battle_scene.sim_timer / battle_scene.sim_speed, 0.0, 1.0)
	return 1.0

func _interp_entity_pos(f: BattleSimulatorV3.BattleFormationV3, i: int, t: float) -> Vector2:
	var cur: Vector2 = f.entity_positions[i]
	if t >= 1.0:
		return cur
	var prev: PackedVector2Array = _prev_positions.get(f.instance_id, PackedVector2Array())
	if i >= prev.size():
		return cur
	return prev[i].lerp(cur, t)

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
	# Derive deploy zone tints from faction colors
	var atk_fd := DataManager.get_faction(battle_scene.attacker_faction_id)
	var def_fd := DataManager.get_faction(battle_scene.defender_faction_id)
	var atk_tint: Color = (atk_fd.color.darkened(0.7) if atk_fd else COLOR_DEPLOY_TINT)
	var def_tint: Color = (def_fd.color.darkened(0.7) if def_fd else COLOR_ENEMY_TINT)
	var fw := BattleSimulatorV3.FIELD_WIDTH
	# Attacker deploy zone (bottom)
	var atk_rect := Rect2(0, BattleSimulatorV3.DEPLOY_BOTTOM_Y, fw,
		BattleSimulatorV3.FIELD_HEIGHT - BattleSimulatorV3.DEPLOY_BOTTOM_Y)
	draw_rect(atk_rect, atk_tint * Color(1, 1, 1, 0.28))
	# Defender deploy zone (top)
	var def_rect := Rect2(0, 0, fw, BattleSimulatorV3.DEPLOY_TOP_Y)
	draw_rect(def_rect, def_tint * Color(1, 1, 1, 0.28))

	# Dashed edge lines for deploy zone boundaries
	var dash_len := 12.0
	var gap_len := 8.0
	var edge_color_atk := Color(atk_tint.r + 0.3, atk_tint.g + 0.3, atk_tint.b + 0.3, 0.45)
	var edge_color_def := Color(def_tint.r + 0.3, def_tint.g + 0.3, def_tint.b + 0.3, 0.45)
	# Attacker zone top edge (DEPLOY_BOTTOM_Y)
	_draw_dashed_line(Vector2(0, BattleSimulatorV3.DEPLOY_BOTTOM_Y),
		Vector2(fw, BattleSimulatorV3.DEPLOY_BOTTOM_Y), edge_color_atk, dash_len, gap_len, 1.5)
	# Defender zone bottom edge (DEPLOY_TOP_Y)
	_draw_dashed_line(Vector2(0, BattleSimulatorV3.DEPLOY_TOP_Y),
		Vector2(fw, BattleSimulatorV3.DEPLOY_TOP_Y), edge_color_def, dash_len, gap_len, 1.5)

	# Zone separator line
	var mid_y := (BattleSimulatorV3.DEPLOY_TOP_Y + BattleSimulatorV3.DEPLOY_BOTTOM_Y) / 2.0
	draw_line(Vector2(0, mid_y), Vector2(fw, mid_y),
		Color(0.9, 0.82, 0.55, 0.15), 1.0)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var dir := (to - from)
	var total := dir.length()
	dir = dir.normalized()
	var pos := 0.0
	while pos < total:
		var seg_end := minf(pos + dash, total)
		draw_line(from + dir * pos, from + dir * seg_end, color, width)
		pos = seg_end + gap

var _faction_color_cache: Dictionary = {} # faction_id -> resolved+contrast-adjusted Color

func _resolved_faction_color(faction_id: StringName, is_player: bool) -> Color:
	# DataManager lookup + luminance adjustment were repeated per formation
	# per frame; the result is constant per faction for the whole battle.
	if _faction_color_cache.has(faction_id):
		return _faction_color_cache[faction_id]
	var faction_data := DataManager.get_faction(faction_id)
	var base_color: Color = faction_data.color if faction_data else (COLOR_PLAYER if is_player else COLOR_ENEMY)
	# Ensure contrast: darken very light faction colors
	if base_color.get_luminance() > 0.7:
		base_color = base_color.darkened(0.2)
	if faction_data:
		_faction_color_cache[faction_id] = base_color
	return base_color

func _formation_base_color(f: BattleSimulatorV3.BattleFormationV3) -> Color:
	var is_player: bool = f.side == battle_scene.player_side
	var base_color := _resolved_faction_color(f.faction_id, is_player)
	if f.is_routing:
		base_color = base_color.lerp(Color(0.55, 0.25, 0.2), 0.55)
		base_color.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
	return base_color

## Fills the per-shape outline/fill MultiMesh buffers from current (interpolated)
## entity state. Runs every frame from _process.
func _update_entity_multimeshes() -> void:
	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return

	for shape in _shape_mm:
		_shape_mm[shape].count = 0

	var t := _interp_t()
	var time_ms := Time.get_ticks_msec()
	var selected_arr: Array = battle_scene.selected_formations
	var hovered: BattleSimulatorV3.BattleFormationV3 = battle_scene.hovered_formation

	for side_formations in [sim.attacker_formations, sim.defender_formations]:
		for f: BattleSimulatorV3.BattleFormationV3 in side_formations:
			if f.is_fled or f.is_dead:
				continue
			var limit := mini(f.entities_alive, f.entity_positions.size())
			if limit <= 0:
				continue

			var radius := BattleSimulatorV3.get_entity_radius(f)
			var shape := _get_shape(f, radius)
			var e: Dictionary = _get_mm_entry(shape)
			if e.count + limit > e.cap:
				e.cap = maxi(maxi(e.cap * 2, e.count + limit), 64)
				e.out_buf.resize(e.cap * _MM_STRIDE)
				e.fill_buf.resize(e.cap * _MM_STRIDE)

			var hit_scale := 1.0
			if _hit_scale.has(f.instance_id):
				hit_scale = 1.0 + 0.2 * (_hit_scale[f.instance_id] / 0.15)
			var s_fill := radius * hit_scale
			var s_out := s_fill + 1.5

			var rotating: bool = shape == _Shape.FLYING or shape == _Shape.BEAST \
				or shape == _Shape.CAVALRY or shape == _Shape.MONSTER_LARGE
			var cosr := 1.0
			var sinr := 0.0
			if rotating:
				cosr = cos(f.rotation)
				sinr = sin(f.rotation)

			var base_color := _formation_base_color(f)
			var is_selected: bool = f in selected_arr
			var is_hovered: bool = f == hovered and not is_selected
			var ent_col := base_color
			var leader_col := base_color.lightened(0.15)
			if is_selected:
				ent_col = ent_col.lerp(COLOR_SELECTED, 0.25)
				leader_col = leader_col.lerp(COLOR_SELECTED, 0.25)
			elif is_hovered:
				ent_col = ent_col.lightened(0.15)
				leader_col = leader_col.lightened(0.15)
			if _flash_formations.has(f.instance_id):
				ent_col = ent_col.lerp(Color.WHITE, 0.5)
				leader_col = leader_col.lerp(Color.WHITE, 0.5)

			var routing := f.is_routing
			var cur: PackedVector2Array = f.entity_positions
			var prev: PackedVector2Array = _prev_positions.get(f.instance_id, PackedVector2Array())
			var interp: bool = t < 1.0 and prev.size() >= limit
			var ob: PackedFloat32Array = e.out_buf
			var fb: PackedFloat32Array = e.fill_buf
			var cursor: int = e.count

			for i in limit:
				var px: float
				var py: float
				if interp:
					var pv := prev[i]
					var cv := cur[i]
					px = pv.x + (cv.x - pv.x) * t
					py = pv.y + (cv.y - pv.y) * t
				else:
					px = cur[i].x
					py = cur[i].y
				if routing:
					px += sin(i * 2.3 + time_ms * 0.004) * 2.5
					py += cos(i * 3.1 + time_ms * 0.003) * 2.0

				var o := (cursor + i) * _MM_STRIDE
				if rotating:
					ob[o] = cosr * s_out
					ob[o + 1] = -sinr * s_out
					ob[o + 4] = sinr * s_out
					ob[o + 5] = cosr * s_out
					fb[o] = cosr * s_fill
					fb[o + 1] = -sinr * s_fill
					fb[o + 4] = sinr * s_fill
					fb[o + 5] = cosr * s_fill
				else:
					ob[o] = s_out
					ob[o + 1] = 0.0
					ob[o + 4] = 0.0
					ob[o + 5] = s_out
					fb[o] = s_fill
					fb[o + 1] = 0.0
					fb[o + 4] = 0.0
					fb[o + 5] = s_fill
				ob[o + 2] = 0.0
				ob[o + 3] = px
				ob[o + 6] = 0.0
				ob[o + 7] = py
				ob[o + 8] = 0.0
				ob[o + 9] = 0.0
				ob[o + 10] = 0.0
				ob[o + 11] = 0.55
				fb[o + 2] = 0.0
				fb[o + 3] = px
				fb[o + 6] = 0.0
				fb[o + 7] = py
				var c := leader_col if i == 0 else ent_col
				fb[o + 8] = c.r
				fb[o + 9] = c.g
				fb[o + 10] = c.b
				fb[o + 11] = c.a
			e.count = cursor + limit

	# Push buffers to the GPU
	for shape in _shape_mm:
		var e: Dictionary = _shape_mm[shape]
		if e.cap == 0:
			continue
		if e.out.instance_count != e.cap:
			e.out.instance_count = e.cap
			e.fill.instance_count = e.cap
		e.out.buffer = e.out_buf
		e.fill.buffer = e.fill_buf
		e.out.visible_instance_count = e.count
		e.fill.visible_instance_count = e.count

func _draw_below_entities(sim: BattleSimulatorV3) -> void:
	var t := _interp_t()
	var time_ms := Time.get_ticks_msec()
	for side_formations in [sim.attacker_formations, sim.defender_formations]:
		for f: BattleSimulatorV3.BattleFormationV3 in side_formations:
			if f.is_fled or f.is_dead:
				continue
			var radius := BattleSimulatorV3.get_entity_radius(f)
			var hit_scale := 1.0
			if _hit_scale.has(f.instance_id):
				hit_scale = 1.0 + 0.2 * (_hit_scale[f.instance_id] / 0.15)
			var limit := mini(f.entities_alive, f.entity_positions.size())

			# Ground shadow beneath each entity — only for large entities where
			# it is actually visible (small dots' shadows cost a draw call each)
			if radius * hit_scale >= 4.5:
				for i in limit:
					var epos := _interp_entity_pos(f, i, t)
					if f.is_routing:
						epos += Vector2(sin(i * 2.3 + time_ms * 0.004) * 2.5, cos(i * 3.1 + time_ms * 0.003) * 2.0)
					draw_circle(epos + Vector2(1.5, 2.0), radius * hit_scale * 0.85, Color(0.0, 0.0, 0.0, 0.18))

			# Charge trail for fast-moving units
			if f.current_order == Enums.BattleOrder.CHARGE and not f.is_routing:
				var facing := f.get_facing_vector()
				var base_color := _formation_base_color(f)
				var trail_color := Color(base_color.r, base_color.g, base_color.b, 0.15)
				for i in limit:
					var epos := _interp_entity_pos(f, i, t)
					var trail_end := epos - facing * radius * 3.0
					draw_line(epos, trail_end, trail_color, 1.5)

func _draw_formation_overlays(layer: CanvasItem, sim: BattleSimulatorV3) -> void:
	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(sim.attacker_formations)
	all_formations.append_array(sim.defender_formations)

	var selected_arr: Array = battle_scene.selected_formations
	var hovered: BattleSimulatorV3.BattleFormationV3 = battle_scene.hovered_formation
	var t := _interp_t()
	var time_ms := Time.get_ticks_msec()

	for f in all_formations:
		if f.is_fled or f.is_dead:
			continue

		var is_player: bool = f.side == battle_scene.player_side
		var base_color := _formation_base_color(f)
		var is_selected: bool = f in selected_arr
		var is_hovered: bool = f == hovered and not is_selected
		var radius := BattleSimulatorV3.get_entity_radius(f)
		var limit := mini(f.entities_alive, f.entity_positions.size())

		# Selection highlight ring around entities
		if is_selected:
			for i in limit:
				var epos := _interp_entity_pos(f, i, t)
				layer.draw_arc(epos, radius + 2.0, 0, TAU, 16,
					COLOR_SELECTED * Color(1, 1, 1, 0.6), 1.0)
		elif is_hovered:
			# Hover highlight: softer ring
			for i in limit:
				var epos := _interp_entity_pos(f, i, t)
				layer.draw_arc(epos, radius + 2.0, 0, TAU, 16,
					Color(0.9, 0.85, 0.7, 0.35), 1.0)

		# Aura visual
		if f.damage_aura_radius > 0.0:
			var aura_alpha := 0.1 + 0.06 * sin(time_ms * 0.003)
			var aura_color := Color(base_color.r, base_color.g, base_color.b, aura_alpha)
			layer.draw_arc(f.position, f.damage_aura_radius, 0, TAU, 24, aura_color, 2.0)

		# Morale aura visual
		if f.morale_aura != 0 and f.fear_radius > 0 and not f.is_dead:
			var aura_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var pulse := 0.06 + 0.03 * sin(time_ms * 0.002 + f.position.x * 0.1)
			if f.morale_aura > 0:
				layer.draw_arc(f.position, aura_range, 0, TAU, 32, Color(0.8, 0.9, 0.4, pulse), 1.5)
			else:
				layer.draw_arc(f.position, aura_range, 0, TAU, 32, Color(0.7, 0.15, 0.1, pulse), 1.5)

		# Healing aura visual (soft green inner ring)
		if f.healing_aura > 0.0 and f.fear_radius > 0 and not f.is_dead:
			var heal_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var heal_pulse := 0.05 + 0.04 * sin(time_ms * 0.0015 + f.position.y * 0.1)
			layer.draw_arc(f.position, heal_range * 0.85, 0, TAU, 32, Color(0.3, 0.85, 0.4, heal_pulse), 1.5)

		# Armor aura visual (pale blue-white inner ring)
		if f.armor_aura > 0 and f.fear_radius > 0 and not f.is_dead:
			var armor_range := float(f.fear_radius) * BattleSimulatorV3.RANGED_PX_PER_RANGE * 0.5
			var armor_pulse := 0.05 + 0.03 * sin(time_ms * 0.0018 + f.position.y * 0.15)
			layer.draw_arc(f.position, armor_range * 0.9, 0, TAU, 32, Color(0.6, 0.7, 0.9, armor_pulse), 1.5)

		# Facing arrow at formation center
		_draw_facing_arrow(layer, f)

		# HP bar below formation, morale bar below that, resource bars below those
		_draw_hp_bar(layer, f)
		_draw_morale_bar(layer, f)
		_draw_resource_bars(layer, f)

		# Routing indicator — "!!" with rotating panic lines
		if f.is_routing:
			layer.draw_string(ThemeDB.fallback_font, f.position + Vector2(-6, -20),
				"!!", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 0.3, 0.2))
			var panic_center := f.position + Vector2(0, -24)
			var panic_rot := time_ms * 0.005
			var panic_color := Color(1, 0.3, 0.2, 0.6)
			for k in 3:
				var a := panic_rot + TAU * float(k) / 3.0
				var start := panic_center + Vector2(cos(a), sin(a)) * 5.0
				var end := panic_center + Vector2(cos(a), sin(a)) * 9.0
				layer.draw_line(start, end, panic_color, 1.5)

		# Name label with shadow for readability
		var name_text := f.display_name.left(10)
		var name_pos := f.position + Vector2(-35, -30)
		var name_color: Color = Color(0.95, 0.9, 0.75, 0.9) if is_player else Color(0.95, 0.72, 0.65, 0.9)
		# Shadow
		layer.draw_string(ThemeDB.fallback_font, name_pos + Vector2(1, 1),
			name_text, HORIZONTAL_ALIGNMENT_CENTER, 70, 10, Color(0, 0, 0, 0.6))
		layer.draw_string(ThemeDB.fallback_font, name_pos,
			name_text, HORIZONTAL_ALIGNMENT_CENTER, 70, 10, name_color)

func _draw_dead_marks_onto(layer: CanvasItem) -> void:
	if battle_scene == null:
		return
	var sim: BattleSimulatorV3 = battle_scene.simulator
	if sim == null:
		return
	var all_formations: Array[BattleSimulatorV3.BattleFormationV3] = []
	all_formations.append_array(sim.attacker_formations)
	all_formations.append_array(sim.defender_formations)

	for f in all_formations:
		if f.dead_entity_positions.size() == 0:
			continue
		var r := BattleSimulatorV3.get_entity_radius(f) * 0.5
		for pos in f.dead_entity_positions:
			_draw_blood_splatter(layer, pos, r, int(pos.x * 73 + pos.y * 137))

# Splatter polygons are deterministic per (pos, radius, seed) — generated once
# and cached, since _draw regenerated them every frame for every dead entity.
var _splatter_cache: Dictionary = {} # [pos, radius, seed] -> Array of [pts, color]

func _draw_blood_splatter(layer: CanvasItem, pos: Vector2, radius: float, seed_val: int) -> void:
	var cache_key := [pos, radius, seed_val]
	var cached: Variant = _splatter_cache.get(cache_key)
	if cached == null:
		cached = _generate_blood_splatter(pos, radius, seed_val)
		_splatter_cache[cache_key] = cached
	for droplet in cached:
		layer.draw_colored_polygon(droplet[0], droplet[1])

func _generate_blood_splatter(pos: Vector2, radius: float, seed_val: int) -> Array:
	# 2-3 irregular droplet polygons per death position (verbatim generation)
	var result: Array = []
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
		result.append([pts, Color(red, green, blue, 0.2)])
	return result

func _draw_facing_arrow(layer: CanvasItem, f: BattleSimulatorV3.BattleFormationV3) -> void:
	var facing := f.get_facing_vector()
	var tip := f.position + facing * 14.0
	var perp := Vector2(-facing.y, facing.x) * 5.0
	var base_pt := f.position - facing * 4.0

	var points := PackedVector2Array([tip, base_pt + perp, base_pt - perp])
	layer.draw_colored_polygon(points, Color(1, 1, 1, 0.5))

## Resolves the entity draw shape for a formation once (tags and base radius
## never change mid-battle). Branch priority mirrors the old per-entity checks.
func _get_shape(f: BattleSimulatorV3.BattleFormationV3, base_radius: float) -> _Shape:
	if _shape_cache.has(f.instance_id):
		return _shape_cache[f.instance_id]
	var tags: Array = f.tags
	var shape: _Shape
	if tags.has("flying"):
		shape = _Shape.FLYING
	elif tags.has("swarm") and not tags.has("cavalry") and not tags.has("infantry"):
		shape = _Shape.SWARM
	elif tags.has("monster"):
		# Outline pass adds +1.5, matching the old radius >= 20.0 check there
		shape = _Shape.MONSTER_LARGE if base_radius >= 18.5 else _Shape.MONSTER
	elif tags.has("construct") and not tags.has("infantry"):
		shape = _Shape.CONSTRUCT_LARGE if base_radius >= 23.5 else _Shape.CONSTRUCT
	elif tags.has("beast") and not tags.has("cavalry"):
		shape = _Shape.BEAST
	elif tags.has("cavalry"):
		shape = _Shape.CAVALRY
	elif tags.has("mage"):
		shape = _Shape.MAGE
	elif tags.has("ranged"):
		shape = _Shape.RANGED
	elif tags.has("support"):
		shape = _Shape.SUPPORT
	elif tags.has("infantry"):
		shape = _Shape.INFANTRY
	else:
		shape = _Shape.CIRCLE
	_shape_cache[f.instance_id] = shape
	return shape

# ── Entity shape meshes (unit radius, vertex-colored) ────────
# Each shape is built once at radius 1 centered on the origin; per-instance
# transform supplies position/rotation/scale and per-instance color the
# formation color. Vertex colors are multipliers: white parts take the
# formation color, gray parts render darkened detail. ("Lightened" details
# from the old immediate-mode draws are approximated by darkening the base
# geometry slightly instead — instance colors can only darken vertex colors.)

func _get_mm_entry(shape: _Shape) -> Dictionary:
	if _shape_mm.has(shape):
		return _shape_mm[shape]
	var mesh := _build_shape_mesh(shape)
	var out_mm := MultiMesh.new()
	out_mm.transform_format = MultiMesh.TRANSFORM_2D
	out_mm.use_colors = true
	out_mm.mesh = mesh
	var fill_mm := MultiMesh.new()
	fill_mm.transform_format = MultiMesh.TRANSFORM_2D
	fill_mm.use_colors = true
	fill_mm.mesh = mesh
	var out_node := MultiMeshInstance2D.new()
	out_node.multimesh = out_mm
	_mm_out_root.add_child(out_node)
	var fill_node := MultiMeshInstance2D.new()
	fill_node.multimesh = fill_mm
	_mm_fill_root.add_child(fill_node)
	var entry := {out = out_mm, fill = fill_mm, out_buf = PackedFloat32Array(), fill_buf = PackedFloat32Array(), cap = 0, count = 0}
	_shape_mm[shape] = entry
	return entry

func _mesh_convex(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, pts: PackedVector2Array, color: Color) -> void:
	# Triangle-fan a convex polygon from its first vertex
	var base := verts.size()
	verts.append_array(pts)
	for i in pts.size():
		cols.append(color)
	for i in range(1, pts.size() - 1):
		idx.append(base)
		idx.append(base + i)
		idx.append(base + i + 1)

func _mesh_star(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, pts: PackedVector2Array, color: Color) -> void:
	# Fan a star-shaped (about the origin) polygon around a center vertex
	var center := verts.size()
	verts.append(Vector2.ZERO)
	cols.append(color)
	var base := verts.size()
	verts.append_array(pts)
	for i in pts.size():
		cols.append(color)
	for i in pts.size():
		idx.append(center)
		idx.append(base + i)
		idx.append(base + (i + 1) % pts.size())

func _mesh_circle(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, center: Vector2, r: float, segs: int, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in segs:
		var a := TAU * float(k) / float(segs)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_mesh_convex(verts, cols, idx, pts, color)

func _mesh_ring(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, r_in: float, r_out: float, segs: int, color: Color) -> void:
	var base := verts.size()
	for k in segs:
		var a := TAU * float(k) / float(segs)
		var dir := Vector2(cos(a), sin(a))
		verts.append(dir * r_in)
		verts.append(dir * r_out)
		cols.append(color)
		cols.append(color)
	for k in segs:
		var i0 := base + k * 2
		var i1 := base + k * 2 + 1
		var j0 := base + ((k + 1) % segs) * 2
		var j1 := base + ((k + 1) % segs) * 2 + 1
		idx.append(i0)
		idx.append(i1)
		idx.append(j1)
		idx.append(i0)
		idx.append(j1)
		idx.append(j0)

func _regular_poly(r: float, segs: int, angle_offset := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in segs:
		var a := TAU * float(k) / float(segs) + angle_offset
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _build_shape_mesh(shape: _Shape) -> ArrayMesh:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var white := Color.WHITE
	var detail := Color(0.7, 0.7, 0.7)

	match shape:
		_Shape.FLYING:
			# Winged triangle pointing "up" (instances rotate by facing)
			var fa := -PI / 2.0
			var tip := Vector2(cos(fa), sin(fa))
			var bl := Vector2(cos(fa + 2.3), sin(fa + 2.3)) * 0.8
			var br := Vector2(cos(fa - 2.3), sin(fa - 2.3)) * 0.8
			var wl := Vector2(cos(fa + 1.8), sin(fa + 1.8)) * 1.4
			var wr := Vector2(cos(fa - 1.8), sin(fa - 1.8)) * 1.4
			_mesh_convex(verts, cols, idx, PackedVector2Array([tip, bl, br]), Color(0.88, 0.88, 0.88))
			_mesh_convex(verts, cols, idx, PackedVector2Array([bl, wl, Vector2.ZERO]), white)
			_mesh_convex(verts, cols, idx, PackedVector2Array([br, wr, Vector2.ZERO]), white)
		_Shape.SWARM:
			# 3 tiny circles in triangle arrangement
			_mesh_circle(verts, cols, idx, Vector2(0, -0.5), 0.4, 8, white)
			_mesh_circle(verts, cols, idx, Vector2(-0.435, 0.25), 0.4, 8, white)
			_mesh_circle(verts, cols, idx, Vector2(0.435, 0.25), 0.4, 8, white)
		_Shape.MONSTER_LARGE:
			# Spiky 7-point star + inner ring (instances rotate by facing)
			var pts := PackedVector2Array()
			for k in 14:
				var a := TAU * float(k) / 14.0
				var r := 1.0 if k % 2 == 0 else 0.55
				pts.append(Vector2(cos(a), sin(a)) * r)
			_mesh_star(verts, cols, idx, pts, white)
			_mesh_ring(verts, cols, idx, 0.36, 0.44, 10, Color(0.65, 0.65, 0.65))
		_Shape.MONSTER:
			# Hexagon + inner ring
			_mesh_convex(verts, cols, idx, _regular_poly(1.0, 6), white)
			_mesh_ring(verts, cols, idx, 0.6, 0.7, 6, detail)
		_Shape.CONSTRUCT_LARGE:
			# Octagon + inner octagon + crosshatch
			_mesh_convex(verts, cols, idx, _regular_poly(0.92, 8, PI / 8.0), white)
			_mesh_convex(verts, cols, idx, _regular_poly(0.55, 8, PI / 8.0), detail)
			_mesh_convex(verts, cols, idx, PackedVector2Array([Vector2(-0.35, -0.03), Vector2(0.35, -0.03), Vector2(0.35, 0.03), Vector2(-0.35, 0.03)]), white)
			_mesh_convex(verts, cols, idx, PackedVector2Array([Vector2(-0.03, -0.35), Vector2(0.03, -0.35), Vector2(0.03, 0.35), Vector2(-0.03, 0.35)]), white)
		_Shape.CONSTRUCT:
			# Hexagon + inner hexagon detail
			_mesh_convex(verts, cols, idx, _regular_poly(0.9, 6, PI / 6.0), white)
			_mesh_convex(verts, cols, idx, _regular_poly(0.5, 6, PI / 6.0), detail)
		_Shape.BEAST:
			# Irregular 5-point claw (instances rotate by facing)
			var radii := [1.0, 0.6, 0.9, 0.55, 0.95]
			var pts := PackedVector2Array()
			for k in 5:
				var a := -PI / 2.0 + TAU * float(k) / 5.0
				pts.append(Vector2(cos(a), sin(a)) * radii[k])
			_mesh_star(verts, cols, idx, pts, white)
		_Shape.CAVALRY:
			# Triangle pointing "up" (instances rotate by facing)
			_mesh_convex(verts, cols, idx, _regular_poly(1.0, 3, -PI / 2.0), white)
		_Shape.MAGE:
			# 4-point star + center dot
			var pts := PackedVector2Array()
			for k in 8:
				var a := TAU * float(k) / 8.0 - PI / 8.0
				var r := 1.0 if k % 2 == 0 else 0.4
				pts.append(Vector2(cos(a), sin(a)) * r)
			_mesh_star(verts, cols, idx, pts, Color(0.9, 0.9, 0.9))
			_mesh_circle(verts, cols, idx, Vector2.ZERO, 0.2, 8, white)
		_Shape.RANGED:
			# Filled square + thin ring
			_mesh_convex(verts, cols, idx, PackedVector2Array([Vector2(-0.65, -0.65), Vector2(0.65, -0.65), Vector2(0.65, 0.65), Vector2(-0.65, 0.65)]), Color(0.9, 0.9, 0.9))
			_mesh_ring(verts, cols, idx, 0.88, 1.12, 12, white)
		_Shape.SUPPORT:
			# Circle with plus sign
			_mesh_circle(verts, cols, idx, Vector2.ZERO, 1.0, 12, Color(0.85, 0.85, 0.85))
			_mesh_convex(verts, cols, idx, PackedVector2Array([Vector2(-0.55, -0.08), Vector2(0.55, -0.08), Vector2(0.55, 0.08), Vector2(-0.55, 0.08)]), white)
			_mesh_convex(verts, cols, idx, PackedVector2Array([Vector2(-0.08, -0.55), Vector2(0.08, -0.55), Vector2(0.08, 0.55), Vector2(-0.08, 0.55)]), white)
		_Shape.INFANTRY:
			# Diamond (rotated square)
			_mesh_convex(verts, cols, idx, _regular_poly(1.0, 4, PI / 4.0), white)
		_:
			# Default: circle
			_mesh_circle(verts, cols, idx, Vector2.ZERO, 1.0, 12, white)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _draw_morale_bar(layer: CanvasItem, f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_cached_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 5.0
	var bar_x := bounds.position.x
	# Position below the HP bar (HP bar is at bounds.bottom + 2, height 5.0)
	var bar_y := bounds.position.y + bounds.size.y + 2 + 5.0 + 1.5

	layer.draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	var morale_ratio := clampf(f.current_morale / float(f.base_morale), 0.0, 1.5)
	var fill_width := bar_width * minf(morale_ratio, 1.0)
	var morale_color := Color(1, 1, 1, 0.9)
	if morale_ratio < 0.3:
		morale_color = Color(1, 1, 1, 0.4)
	elif morale_ratio < 0.6:
		morale_color = Color(1, 1, 1, 0.65)
	layer.draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), morale_color)
	layer.draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)

func _draw_hp_bar(layer: CanvasItem, f: BattleSimulatorV3.BattleFormationV3) -> void:
	var bounds := _get_cached_bounds(f)
	var bar_width := maxf(30.0, bounds.size.x)
	var bar_height := 5.0
	var bar_x := bounds.position.x
	var bar_y := bounds.position.y + bounds.size.y + 2

	layer.draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.15, 0.12, 0.1, 0.8))

	var hp_ratio := clampf(float(f.current_hp) / float(f.max_hp), 0.0, 1.0)
	var fill_width := bar_width * hp_ratio
	var hp_color := Color(0.3, 0.75, 0.3)
	if hp_ratio < 0.3:
		hp_color = Color(0.85, 0.25, 0.2)
	elif hp_ratio < 0.6:
		hp_color = Color(0.85, 0.65, 0.2)
	layer.draw_rect(Rect2(bar_x, bar_y, fill_width, bar_height), hp_color)
	layer.draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)

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

func _draw_resource_bars(layer: CanvasItem, f: BattleSimulatorV3.BattleFormationV3) -> void:
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
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(f.current_endurance / f.max_endurance, 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.9, 0.82, 0.25, 0.85)
		if ratio < 0.3:
			color = Color(0.7, 0.55, 0.15, 0.6)
		layer.draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)
		bar_idx += 1

	# Ammo bar (beige) — ranged non-mage units only
	if f.max_ammo > 0:
		var y := base_y + bar_idx * (bar_height + 1.0)
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(float(f.current_ammo) / float(f.max_ammo), 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.82, 0.75, 0.55, 0.85)
		if ratio < 0.3:
			color = Color(0.65, 0.55, 0.35, 0.6)
		layer.draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)
		bar_idx += 1

	# Mana bar (blue) — mage units only
	if f.max_mana > 0.0:
		var y := base_y + bar_idx * (bar_height + 1.0)
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), bg_color)
		var ratio := clampf(f.current_mana / f.max_mana, 0.0, 1.0)
		var fill := bar_width * ratio
		var color := Color(0.3, 0.45, 0.9, 0.85)
		if ratio < 0.3:
			color = Color(0.2, 0.3, 0.65, 0.6)
		layer.draw_rect(Rect2(bar_x, y, fill, bar_height), color)
		layer.draw_rect(Rect2(bar_x, y, bar_width, bar_height), COLOR_BAR_OUTLINE, false, 1.0)

func _draw_vignette(layer: CanvasItem) -> void:
	# Darken edges of the battlefield for atmospheric depth
	var fw := BattleSimulatorV3.FIELD_WIDTH
	var fh := BattleSimulatorV3.FIELD_HEIGHT
	var edge := 80.0
	var step := edge / 5.0
	var vc := Color(0.0, 0.0, 0.0)
	# Top edge gradient
	for i in 6:
		var t := float(i) / 5.0
		var alpha := lerpf(0.25, 0.0, t)
		var y := t * edge
		layer.draw_line(Vector2(0, y), Vector2(fw, y), Color(vc.r, vc.g, vc.b, alpha), step)
	# Bottom edge gradient
	for i in 6:
		var t := float(i) / 5.0
		var alpha := lerpf(0.25, 0.0, t)
		var y := fh - t * edge
		layer.draw_line(Vector2(0, y), Vector2(fw, y), Color(vc.r, vc.g, vc.b, alpha), step)
	# Left edge gradient
	for i in 6:
		var t := float(i) / 5.0
		var alpha := lerpf(0.2, 0.0, t)
		var x := t * edge
		layer.draw_line(Vector2(x, 0), Vector2(x, fh), Color(vc.r, vc.g, vc.b, alpha), step)
	# Right edge gradient
	for i in 6:
		var t := float(i) / 5.0
		var alpha := lerpf(0.2, 0.0, t)
		var x := fw - t * edge
		layer.draw_line(Vector2(x, 0), Vector2(x, fh), Color(vc.r, vc.g, vc.b, alpha), step)
