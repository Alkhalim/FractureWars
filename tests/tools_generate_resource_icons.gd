extends SceneTree
## Resource icon generator — renders the 7 resource glyphs (64px, marker
## visual language: dark outline, gold trim) into assets/sprites/ui/icons/.
##   & <godot> --path . --resolution 128x128 -s res://tests/tools_generate_resource_icons.gd
## then: & <godot> --headless --path . --import

const SIZE := 64
const OUT_DIR := "res://assets/sprites/ui/icons"
const ICONS := ["res_gold", "res_iron", "res_tech", "res_food", "res_shards", "res_wood", "res_captives"]

var _vp: SubViewport
var _painter: _IconPainter
var _idx := -1
var _capture_pending := false

class _IconPainter extends Node2D:
	var icon := "res_gold"

	const C := Vector2(32, 32)
	const OUTLINE := Color(0.07, 0.055, 0.045, 0.95)
	const GOLD := Color(0.93, 0.8, 0.32)

	func _ellipse(center: Vector2, rx: float, ry: float, segs := 16) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in segs:
			var a := TAU * float(i) / float(segs)
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	func _scaled(pts: PackedVector2Array, s: float, origin: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(origin + (p - origin) * s)
		return out

	func _outlined(pts: PackedVector2Array, color: Color, origin: Vector2, outline_scale := 1.14) -> void:
		draw_colored_polygon(_scaled(pts, outline_scale, origin), OUTLINE)
		draw_colored_polygon(pts, color)

	func _draw() -> void:
		match icon:
			"res_gold": _i_gold()
			"res_iron": _i_iron()
			"res_tech": _i_tech()
			"res_food": _i_food()
			"res_shards": _i_shards()
			"res_wood": _i_wood()
			"res_captives": _i_captives()

	func _i_gold() -> void:
		# Coin stack: two base coins, one on top
		for coin in [[Vector2(-9, 8), 0.95], [Vector2(10, 9), 0.9], [Vector2(1, -5), 1.0]]:
			var cc: Vector2 = C + coin[0]
			var cs: float = coin[1]
			_outlined(_ellipse(cc, 15 * cs, 10 * cs), GOLD.darkened(0.12 if cc.y > C.y else 0.0), cc)
			draw_polyline(_ellipse(cc, 11 * cs, 6.6 * cs, 14), Color(0.75, 0.6, 0.2), 2.0, true)
		# Shine on top coin
		draw_polyline(_ellipse(C + Vector2(-2, -8), 6, 3, 8), Color(1.0, 0.95, 0.6, 0.8), 2.0, true)

	func _i_iron() -> void:
		# Ingot pair: back + front trapezoid bricks with lit top face
		for ing: Vector2 in [Vector2(6, -7), Vector2(-4, 5)]:
			var o := C + ing
			var body := PackedVector2Array([
				o + Vector2(-16, -2), o + Vector2(16, -2), o + Vector2(12, 10), o + Vector2(-12, 10)
			])
			_outlined(body, Color(0.55, 0.56, 0.62), o)
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-16, -2), o + Vector2(16, -2), o + Vector2(13, -8), o + Vector2(-13, -8)
			]), Color(0.72, 0.73, 0.8))
			draw_polyline(PackedVector2Array([o + Vector2(-13, -8), o + Vector2(13, -8)]),
				Color(0.85, 0.86, 0.92, 0.8), 1.5, true)

	func _i_tech() -> void:
		# Unrolled scroll with rolled ends and a gold seal
		var body := PackedVector2Array([
			C + Vector2(-13, -14), C + Vector2(13, -14), C + Vector2(13, 14), C + Vector2(-13, 14)
		])
		_outlined(body, Color(0.85, 0.78, 0.6), C)
		for ry in [-14.0, 14.0]:
			var ro := C + Vector2(0, ry)
			draw_colored_polygon(_ellipse(ro + Vector2(-14, 0), 4.5, 5.5, 10), Color(0.72, 0.64, 0.47))
			draw_colored_polygon(PackedVector2Array([
				ro + Vector2(-14, -5.5), ro + Vector2(14, -5.5), ro + Vector2(14, 5.5), ro + Vector2(-14, 5.5)
			]), Color(0.78, 0.7, 0.52))
			draw_colored_polygon(_ellipse(ro + Vector2(14, 0), 4.5, 5.5, 10), Color(0.66, 0.58, 0.42))
			draw_colored_polygon(_ellipse(ro + Vector2(14, 0), 2.2, 3.0, 8), Color(0.5, 0.44, 0.32))
		for i in 3:
			var ly := -6.0 + float(i) * 6.0
			draw_line(C + Vector2(-8, ly), C + Vector2(8, ly), Color(0.45, 0.4, 0.3, 0.8), 1.6)
		draw_colored_polygon(_ellipse(C + Vector2(8, 10), 4.5, 4.5, 10), GOLD)
		draw_polyline(_ellipse(C + Vector2(8, 10), 2.4, 2.4, 8), Color(0.7, 0.55, 0.2), 1.2, true)

	func _i_food() -> void:
		# Wheat sheaf: three bound stalks with grain heads
		var tie := C + Vector2(0, 10)
		for k in 3:
			var a := -PI / 2.0 + float(k - 1) * 0.42
			var dirv := Vector2(cos(a), sin(a))
			var top := tie + dirv * 30.0
			draw_line(tie, top, OUTLINE, 5.0)
			draw_line(tie, top, Color(0.78, 0.62, 0.26), 3.0)
			for g in 4:
				var gp := tie + dirv * (16.0 + float(g) * 4.4)
				var perp := Vector2(-dirv.y, dirv.x)
				draw_colored_polygon(PackedVector2Array([
					gp + perp * 3.6, gp + dirv * 5.0, gp - perp * 3.6, gp - dirv * 1.5
				]), Color(0.88, 0.74, 0.34))
		# Tie band
		draw_line(tie + Vector2(-6, 0), tie + Vector2(6, 0), OUTLINE, 7.0)
		draw_line(tie + Vector2(-5, 0), tie + Vector2(5, 0), Color(0.6, 0.44, 0.2), 4.0)

	func _i_shards() -> void:
		# Faceted violet crystal with glow + companion shard
		draw_colored_polygon(_ellipse(C + Vector2(0, 2), 22, 20, 14), Color(0.62, 0.4, 0.85, 0.16))
		var shard := PackedVector2Array([
			C + Vector2(0, -22), C + Vector2(9, -6), C + Vector2(6, 16), C + Vector2(-6, 16), C + Vector2(-9, -6)
		])
		_outlined(shard, Color(0.6, 0.38, 0.82), C)
		draw_colored_polygon(PackedVector2Array([
			C + Vector2(0, -22), C + Vector2(9, -6), C + Vector2(0, 12)
		]), Color(0.74, 0.52, 0.95, 0.7))
		draw_line(C + Vector2(0, -22), C + Vector2(0, 12), Color(0.85, 0.68, 1.0, 0.7), 1.6)
		var mini := PackedVector2Array([
			C + Vector2(14, 2), C + Vector2(19, 8), C + Vector2(16, 17), C + Vector2(11, 12)
		])
		_outlined(mini, Color(0.55, 0.35, 0.75), C + Vector2(15, 9))

	func _i_wood() -> void:
		# Two stacked logs with visible ring ends
		for lg in [[Vector2(0, 7), 0.0], [Vector2(-2, -7), -0.12]]:
			var o: Vector2 = C + lg[0]
			var rot: float = lg[1]
			var dirv := Vector2(cos(rot), sin(rot))
			var perp := Vector2(-dirv.y, dirv.x) * 7.0
			var a0 := o - dirv * 17.0
			var a1 := o + dirv * 17.0
			_outlined(PackedVector2Array([a0 + perp, a1 + perp, a1 - perp, a0 - perp]),
				Color(0.5, 0.35, 0.2), o)
			draw_line(a0 + perp * 0.4, a1 + perp * 0.4, Color(0.4, 0.27, 0.15, 0.7), 2.0)
			# Ring end
			draw_colored_polygon(_ellipse(a1, 4.4, 7.0, 12), Color(0.78, 0.64, 0.44))
			draw_polyline(_ellipse(a1, 2.6, 4.2, 10), Color(0.58, 0.45, 0.28), 1.4, true)
			draw_colored_polygon(_ellipse(a1, 1.0, 1.6, 6), Color(0.58, 0.45, 0.28))

	func _i_captives() -> void:
		# Shackle ring with chain links
		var ring_c := C + Vector2(0, -8)
		draw_polyline(_ellipse(ring_c, 13, 12, 18), OUTLINE, 9.0, true)
		draw_polyline(_ellipse(ring_c, 13, 12, 18), Color(0.58, 0.58, 0.64), 5.5, true)
		draw_polyline(_ellipse(ring_c, 13, 12, 18), Color(0.74, 0.74, 0.8, 0.5), 1.8, true)
		# Hinge bolt
		draw_colored_polygon(_ellipse(ring_c + Vector2(13, 0), 3.2, 3.2, 8), Color(0.45, 0.45, 0.5))
		# Chain links below
		for k in 2:
			var lc := C + Vector2(3 + float(k) * 7.0, 12 + float(k) * 7.0)
			draw_polyline(_ellipse(lc, 6.0, 4.2, 12), OUTLINE, 5.5, true)
			draw_polyline(_ellipse(lc, 6.0, 4.2, 12), Color(0.58, 0.58, 0.64), 3.0, true)

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	_painter = _IconPainter.new()
	_vp.add_child(_painter)

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		img.save_png("%s/%s.png" % [OUT_DIR, ICONS[_idx]])
		_capture_pending = false
	if _idx + 1 < ICONS.size():
		_idx += 1
		_painter.icon = ICONS[_idx]
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d icons into %s" % [ICONS.size(), OUT_DIR])
		quit()
	return false
