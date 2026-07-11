extends SceneTree
## Temp tool: renders a preview sheet of the proposed "boardgame gouache"
## terrain tile style — plains/forest/mountains, deep water vs river water,
## plus a shoreline-bleed demo. Run WITHOUT --headless. Delete after use.

const R := 56.0
var _frames := 0

class _Sheet extends Node2D:
	const R := 56.0

	func _hex(center: Vector2, r := R) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * float(i))
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		return pts

	func _blob(rng: RandomNumberGenerator, center: Vector2, base_r: float, verts := 9, jitter := 0.35) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in verts:
			var a := TAU * float(i) / float(verts)
			var rr := base_r * (1.0 - jitter * 0.5 + rng.randf() * jitter)
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
		return pts

	func _rand_in(rng: RandomNumberGenerator, center: Vector2, max_r: float) -> Vector2:
		var a := rng.randf() * TAU
		return center + Vector2(cos(a), sin(a)) * rng.randf() * max_r

	# ── Tile painters ────────────────────────────────────────
	func _tile_plains(center: Vector2, rng: RandomNumberGenerator) -> void:
		var t := rng.randf() * 0.04 - 0.02
		draw_colored_polygon(_hex(center), Color(0.55 + t, 0.55 + t, 0.32))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.32), R * 0.34), Color(0.63, 0.62, 0.38, 0.85))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.36), R * 0.26), Color(0.47, 0.48, 0.27, 0.8))
		for i in 4 + rng.randi() % 2:
			var p := _rand_in(rng, center, R * 0.5)
			for k in 3:
				var dx := float(k - 1) * 2.4
				draw_line(p + Vector2(dx, 2.5), p + Vector2(dx * 1.7, -4.5), Color(0.35, 0.42, 0.2), 1.6)

	func _tile_forest(center: Vector2, rng: RandomNumberGenerator) -> void:
		draw_colored_polygon(_hex(center), Color(0.24, 0.35, 0.21))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.3), R * 0.36), Color(0.2, 0.31, 0.18, 0.9))
		for i in 4 + rng.randi() % 3:
			var p := _rand_in(rng, center, R * 0.48)
			var cr := R * (0.13 + rng.randf() * 0.08)
			draw_line(p, p + Vector2(0, cr * 0.9), Color(0.25, 0.18, 0.12), 2.2)
			draw_colored_polygon(_blob(rng, p, cr, 8, 0.25), Color(0.15, 0.27, 0.14))
			draw_colored_polygon(_blob(rng, p + Vector2(-cr * 0.2, -cr * 0.3), cr * 0.55, 7, 0.3), Color(0.33, 0.45, 0.24, 0.9))

	func _tile_mountains(center: Vector2, rng: RandomNumberGenerator) -> void:
		draw_colored_polygon(_hex(center), Color(0.45, 0.42, 0.37))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.3), R * 0.4), Color(0.4, 0.37, 0.33, 0.8))
		var off := Vector2(rng.randf_range(-8, 8), rng.randf_range(-2, 6))
		var apex := center + off + Vector2(0, -R * 0.52)
		var bl := center + off + Vector2(-R * 0.5, R * 0.34)
		var br := center + off + Vector2(R * 0.52, R * 0.36)
		var ridge_l := apex.lerp(bl, 0.45) + Vector2(-4, rng.randf_range(-6, 2))
		var ridge_r := apex.lerp(br, 0.4) + Vector2(5, rng.randf_range(-5, 3))
		draw_colored_polygon(PackedVector2Array([bl, ridge_l, apex, ridge_r, br]), Color(0.54, 0.5, 0.44))
		draw_colored_polygon(PackedVector2Array([apex, ridge_r, br, apex + Vector2(1, 6)]), Color(0.34, 0.31, 0.28, 0.9))
		draw_colored_polygon(PackedVector2Array([
			apex, apex.lerp(ridge_l, 0.55) + Vector2(1, 0), apex + Vector2(2, 9), apex.lerp(ridge_r, 0.45)
		]), Color(0.88, 0.89, 0.9))
		var p2 := center + off + Vector2(R * 0.34, R * 0.1)
		draw_colored_polygon(PackedVector2Array([
			p2 + Vector2(-R * 0.22, R * 0.26), p2 + Vector2(0, -R * 0.16), p2 + Vector2(R * 0.24, R * 0.26)
		]), Color(0.48, 0.44, 0.39))

	func _tile_water_deep(center: Vector2, rng: RandomNumberGenerator) -> void:
		draw_colored_polygon(_hex(center), Color(0.13, 0.2, 0.34))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.3), R * 0.38), Color(0.11, 0.18, 0.31, 0.9))
		for i in 2 + rng.randi() % 2:
			var p := _rand_in(rng, center, R * 0.42)
			var w := R * (0.2 + rng.randf() * 0.16)
			var arc := PackedVector2Array()
			for k in 7:
				var tt := float(k) / 6.0
				arc.append(p + Vector2((tt - 0.5) * w * 2.0, -sin(tt * PI) * w * 0.22))
			draw_polyline(arc, Color(0.22, 0.32, 0.46, 0.8), 1.8, true)

	func _tile_water_river(center: Vector2, rng: RandomNumberGenerator, flow_dir := 0.0) -> void:
		draw_colored_polygon(_hex(center), Color(0.18, 0.3, 0.4))
		draw_colored_polygon(_blob(rng, center, R * 0.5, 9, 0.25), Color(0.2, 0.33, 0.43, 0.7))
		var dirv := Vector2(cos(flow_dir), sin(flow_dir))
		var perp := Vector2(-dirv.y, dirv.x)
		for i in 3:
			var lane := perp * (float(i - 1) * R * 0.26 + rng.randf_range(-3, 3))
			var line := PackedVector2Array()
			for k in 9:
				var tt := float(k) / 8.0
				var along := dirv * (tt - 0.5) * R * 1.4
				line.append(center + lane + along + perp * sin(tt * TAU + float(i)) * 2.6)
			draw_polyline(line, Color(0.33, 0.47, 0.56, 0.85), 1.7, true)
		for i in 3:
			var p := _rand_in(rng, center, R * 0.4)
			draw_circle(p, 1.1, Color(0.6, 0.72, 0.78, 0.7))

	func _tile_desert(center: Vector2, rng: RandomNumberGenerator) -> void:
		draw_colored_polygon(_hex(center), Color(0.71, 0.62, 0.42))
		draw_colored_polygon(_blob(rng, _rand_in(rng, center, R * 0.3), R * 0.36), Color(0.76, 0.67, 0.46, 0.85))
		for i in 2 + rng.randi() % 2:
			var p := _rand_in(rng, center, R * 0.4)
			var w := R * (0.24 + rng.randf() * 0.18)
			var arc := PackedVector2Array()
			for k in 8:
				var tt := float(k) / 7.0
				arc.append(p + Vector2((tt - 0.5) * w * 2.0, -sin(tt * PI) * w * 0.3))
			draw_polyline(arc, Color(0.58, 0.49, 0.32, 0.8), 1.8, true)

	## Shoreline bleed: land color scallops into the water tile along edge k
	## (edge between hex verts k and k+1), plus a foam line. Water tile keeps
	## its hex; only the rim changes.
	func _shore(center: Vector2, edge: int, land_color: Color, rng: RandomNumberGenerator) -> void:
		var hexp := _hex(center)
		var v0 := hexp[edge]
		var v1 := hexp[(edge + 1) % 6]
		var inward := (center - (v0 + v1) * 0.5).normalized()
		# Scalloped land-bleed band
		var band := PackedVector2Array([v0, v1])
		var foam := PackedVector2Array()
		for k in 5:
			var tt := 1.0 - float(k) / 4.0
			var base_pt := v0.lerp(v1, tt)
			var depth := R * (0.2 + 0.1 * sin(tt * PI)) + rng.randf_range(-3.5, 3.5)
			band.append(base_pt + inward * depth)
		draw_colored_polygon(band, Color(land_color.r, land_color.g, land_color.b, 0.85))
		# Wet sand rim + foam line just inside the bleed
		for k in 9:
			var tt := float(k) / 8.0
			var base_pt := v0.lerp(v1, tt)
			var depth := R * (0.2 + 0.1 * sin(tt * PI)) + sin(tt * 14.0) * 1.5
			foam.append(base_pt + inward * (depth + 2.0))
		draw_polyline(foam, Color(0.85, 0.9, 0.92, 0.55), 2.0, true)

	func _label(pos: Vector2, text: String, size := 15) -> void:
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.85, 0.7))

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.12, 0.1, 0.08))
		_label(Vector2(40, 40), "Terrain style preview — 5 variants each", 20)

		var rows := [
			["Plains", Callable(self, "_tile_plains")],
			["Forest", Callable(self, "_tile_forest")],
			["Mountains", Callable(self, "_tile_mountains")],
			["Water (open/deep)", Callable(self, "_tile_water_deep")],
		]
		for ri in rows.size():
			var y := 140.0 + float(ri) * 130.0
			_label(Vector2(40, y + 6), rows[ri][0])
			for vi in 5:
				var rng := RandomNumberGenerator.new()
				rng.seed = ri * 100 + vi
				var c := Vector2(320.0 + float(vi) * 130.0, y)
				(rows[ri][1] as Callable).call(c, rng)
				draw_polyline(_hex(c), Color(0.05, 0.04, 0.03, 0.85), 2.5, true)

		# River variants row (flow left→right)
		var ry := 140.0 + 4.0 * 130.0
		_label(Vector2(40, ry + 6), "Water (river)")
		for vi in 5:
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + vi
			var c := Vector2(320.0 + float(vi) * 130.0, ry)
			_tile_water_river(c, rng, 0.0)
			draw_polyline(_hex(c), Color(0.05, 0.04, 0.03, 0.85), 2.5, true)

		# ── Shoreline demo ──
		_label(Vector2(1150, 120), "Shoreline bleed demo", 18)
		var wc := Vector2(1400, 330)
		var hspace := R * 1.5
		var vspace := R * 0.8660254 * 2.0
		# Neighbor centers for flat-top hexes (edge-adjacent)
		var n_offsets := [
			Vector2(hspace, -vspace * 0.5), Vector2(hspace, vspace * 0.5), Vector2(0, vspace),
			Vector2(-hspace, vspace * 0.5), Vector2(-hspace, -vspace * 0.5), Vector2(0, -vspace)
		]
		var land_types := {2: "plains", 3: "desert", 4: "forest"}
		var land_colors := {2: Color(0.55, 0.55, 0.32), 3: Color(0.71, 0.62, 0.42), 4: Color(0.24, 0.35, 0.21)}
		for k in 6:
			var nc: Vector2 = wc + n_offsets[k]
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 40 + k
			if land_types.has(k):
				match land_types[k]:
					"plains": _tile_plains(nc, rng2)
					"desert": _tile_desert(nc, rng2)
					"forest": _tile_forest(nc, rng2)
			else:
				_tile_water_deep(nc, rng2)
		var rngw := RandomNumberGenerator.new()
		rngw.seed = 77
		_tile_water_deep(wc, rngw)
		# Bleed the three land neighbors into the water tile.
		# Neighbor at offset k faces the water hex across water-hex edge (k+2)%6...
		# determined geometrically: pick the edge whose midpoint is closest to the neighbor.
		var hexp := _hex(wc)
		for k in land_types.keys():
			var nc: Vector2 = wc + n_offsets[k]
			var best_edge := 0
			var best_d := 1e9
			for e in 6:
				var mid := (hexp[e] + hexp[(e + 1) % 6]) * 0.5
				var d := mid.distance_to(nc)
				if d < best_d:
					best_d = d
					best_edge = e
			var rng3 := RandomNumberGenerator.new()
			rng3.seed = 60 + k
			_shore(wc, best_edge, land_colors[k], rng3)
		for k in 7:
			var cc: Vector2 = wc + (n_offsets[k % 6] if k < 6 else Vector2.ZERO)
			draw_polyline(_hex(cc), Color(0.05, 0.04, 0.03, 0.85), 2.5, true)

		# ── River-through-land demo ──
		_label(Vector2(1150, 620), "River through plains (with shorelines)", 18)
		for i in 3:
			var rc := Vector2(1280.0 + float(i) * hspace, 800.0 + (vspace * 0.5 if i % 2 == 1 else 0.0))
			var rngp := RandomNumberGenerator.new()
			rngp.seed = 200 + i
			_tile_plains(rc + Vector2(0, -vspace), rngp)
			var rngp2 := RandomNumberGenerator.new()
			rngp2.seed = 300 + i
			_tile_plains(rc + Vector2(0, vspace), rngp2)
			var rngr := RandomNumberGenerator.new()
			rngr.seed = 400 + i
			_tile_water_river(rc, rngr, 0.35 if i % 2 == 1 else -0.1)
			var rngs := RandomNumberGenerator.new()
			rngs.seed = 500 + i
			_shore(rc, 4, Color(0.55, 0.55, 0.32), rngs)
			var rngs2 := RandomNumberGenerator.new()
			rngs2.seed = 600 + i
			_shore(rc, 1, Color(0.55, 0.55, 0.32), rngs2)
			for dy in [-1.0, 0.0, 1.0]:
				draw_polyline(_hex(rc + Vector2(0, vspace * dy)), Color(0.05, 0.04, 0.03, 0.85), 2.5, true)

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var sheet := _Sheet.new()
	root.add_child(sheet)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://terrain_preview.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://terrain_preview.png"))
		quit()
	return false
