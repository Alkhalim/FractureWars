extends SceneTree
## Terrain tile generator — renders the "boardgame gouache" tile set into
## res://assets/sprites/campaign_map_v2/ (10 terrains + river, 5 variants each,
## 256px). Deterministic per (set, variant). Re-run any time to regenerate:
##   & <godot> --path . --resolution 320x320 -s res://tests/tools_generate_terrain_tiles.gd
## then: & <godot> --headless --path . --import

const SIZE := 512  # painters draw in 256-space, scaled 2x for crisp close zoom
const OUT_DIR := "res://assets/sprites/campaign_map_v2"
const SETS := ["plains", "forest", "mountain", "desert", "swamp", "wetlands", "tundra", "shardwaste", "water", "jungle", "river"]

var _vp: SubViewport
var _painter: _TilePainter
var _jobs: Array = []
var _job_idx := -1
var _capture_pending := false

class _TilePainter extends Node2D:
	var terrain := "plains"
	var seed_val := 0

	const C := Vector2(128, 128)

	func _blob(rng: RandomNumberGenerator, center: Vector2, base_r: float, verts := 10, jitter := 0.35) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in verts:
			var a := TAU * float(i) / float(verts)
			var rr := base_r * (1.0 - jitter * 0.5 + rng.randf() * jitter)
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
		return pts

	func _rand_in(rng: RandomNumberGenerator, max_r: float) -> Vector2:
		var a := rng.randf() * TAU
		return C + Vector2(cos(a), sin(a)) * rng.randf() * max_r

	func _fill(color: Color) -> void:
		draw_rect(Rect2(0, 0, 256, 256), color)

	func _wavy_line(rng: RandomNumberGenerator, from: Vector2, to: Vector2, amp: float, segs: int) -> PackedVector2Array:
		var dirv := (to - from).normalized()
		var perp := Vector2(-dirv.y, dirv.x)
		var pts := PackedVector2Array()
		for k in segs + 1:
			var t := float(k) / float(segs)
			pts.append(from.lerp(to, t) + perp * sin(t * PI * 2.0 + rng.randf() * 2.0) * amp)
		return pts

	## Organic paint grain: sparse dark/light specks over the whole tile
	func _speckle(rng: RandomNumberGenerator) -> void:
		for i in 26:
			var p := Vector2(rng.randf() * 256.0, rng.randf() * 256.0)
			draw_circle(p, 1.0 + rng.randf() * 0.8, Color(0, 0, 0, 0.05))
		for i in 18:
			var p := Vector2(rng.randf() * 256.0, rng.randf() * 256.0)
			draw_circle(p, 0.9 + rng.randf() * 0.7, Color(1, 1, 1, 0.04))

	func _draw() -> void:
		# Painters use 256-space coordinates; render at 2x for a 512px tile
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(terrain) * 31 + seed_val
		match terrain:
			"plains": _p_plains(rng)
			"forest": _p_forest(rng)
			"mountain": _p_mountain(rng)
			"desert": _p_desert(rng)
			"swamp": _p_swamp(rng)
			"wetlands": _p_wetlands(rng)
			"tundra": _p_tundra(rng)
			"shardwaste": _p_shardwaste(rng)
			"water": _p_water(rng)
			"jungle": _p_jungle(rng)
			"river": _p_river(rng)
		_speckle(rng)

	func _p_plains(rng: RandomNumberGenerator) -> void:
		var t := rng.randf() * 0.05 - 0.025
		_fill(Color(0.55 + t, 0.55 + t, 0.32))
		# Many smaller, varied meadow patches — several crossing the tile edge
		# so adjacent plains blend instead of reading as copies
		for i in 4 + rng.randi() % 4:
			var p := _rand_in(rng, 105)
			var pr := 16.0 + rng.randf() * 22.0
			var shade_pick := rng.randi() % 3
			var shade := Color(0.63, 0.62, 0.38, 0.7)
			if shade_pick == 1:
				shade = Color(0.47, 0.48, 0.27, 0.65)
			elif shade_pick == 2:
				shade = Color(0.58, 0.56, 0.3, 0.6)
			draw_colored_polygon(_blob(rng, p, pr, 9, 0.5), shade)
		# Occasional dirt patch / tiny bush per variant for extra variety
		if rng.randf() < 0.45:
			draw_colored_polygon(_blob(rng, _rand_in(rng, 70), 13.0 + rng.randf() * 9.0, 8, 0.4), Color(0.52, 0.45, 0.3, 0.75))
		if rng.randf() < 0.5:
			var bp := _rand_in(rng, 75)
			draw_colored_polygon(_blob(rng, bp, 7.5, 8, 0.3), Color(0.3, 0.38, 0.2))
			draw_circle(bp + Vector2(-1.5, -1.5), 2.4, Color(0.4, 0.48, 0.26))
		# Top-down grass dot clusters
		for i in 7 + rng.randi() % 5:
			var p := _rand_in(rng, 95)
			for k in 4 + rng.randi() % 4:
				var dp := p + Vector2(rng.randf_range(-7, 7), rng.randf_range(-5.5, 5.5))
				draw_circle(dp, 1.4 + rng.randf() * 1.1, Color(0.38, 0.45, 0.22, 0.9))
			draw_circle(p + Vector2(1.5, 1.0), 1.6, Color(0.62, 0.63, 0.4, 0.8))
		# Scattered wildflowers
		for i in 3 + rng.randi() % 4:
			var fp := _rand_in(rng, 90)
			var fcol := Color(0.85, 0.8, 0.5) if rng.randf() < 0.6 else Color(0.8, 0.65, 0.75)
			draw_circle(fp, 1.8, fcol)

	func _p_forest(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.24, 0.35, 0.21))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 50), 64), Color(0.2, 0.31, 0.18, 0.9))
		for i in 8 + rng.randi() % 4:
			var p := _rand_in(rng, 84)
			var cr := 20.0 + rng.randf() * 13.0
			# Ground shadow under the crown, then trunk, crown, lit top
			draw_colored_polygon(_blob(rng, p + Vector2(3, cr * 0.55), cr * 0.8, 8, 0.3), Color(0.12, 0.2, 0.11, 0.5))
			draw_line(p, p + Vector2(0, cr * 0.9), Color(0.25, 0.18, 0.12), 4.0)
			draw_colored_polygon(_blob(rng, p, cr, 9, 0.25), Color(0.15, 0.27, 0.14))
			draw_colored_polygon(_blob(rng, p + Vector2(-cr * 0.2, -cr * 0.3), cr * 0.55, 8, 0.3), Color(0.33, 0.45, 0.24, 0.9))
		# Undergrowth dots
		for i in 6:
			draw_circle(_rand_in(rng, 90), 2.2, Color(0.28, 0.4, 0.22, 0.8))

	func _mount_peak(rng: RandomNumberGenerator, base_c: Vector2, s: float, snow_cap: bool) -> void:
		# One peak: body, hard-shadowed east face, ridge line, optional snow.
		# All extents scale with s and are safe inside the hex crop.
		var apex := base_c + Vector2(rng.randf_range(-8, 8) * s, -74.0 * s)
		var bl := base_c + Vector2(-52.0 * s + rng.randf_range(-6, 6), 0)
		var br := base_c + Vector2(54.0 * s + rng.randf_range(-6, 6), rng.randf_range(0, 5))
		var ridge_l := apex.lerp(bl, 0.42) + Vector2(-6.0 * s, rng.randf_range(-10, 2) * s)
		var ridge_r := apex.lerp(br, 0.38) + Vector2(7.0 * s, rng.randf_range(-8, 4) * s)
		draw_colored_polygon(PackedVector2Array([bl, ridge_l, apex, ridge_r, br]), Color(0.56, 0.52, 0.45))
		draw_colored_polygon(PackedVector2Array([apex, ridge_r, br, apex + Vector2(3.0 * s, 12.0 * s)]), Color(0.3, 0.27, 0.25))
		draw_polyline(PackedVector2Array([bl, ridge_l, apex]), Color(0.24, 0.21, 0.19), maxf(1.6, 2.6 * s), true)
		if snow_cap:
			var snow := PackedVector2Array([apex])
			var sl := apex.lerp(ridge_l, 0.6)
			var sr := apex.lerp(ridge_r, 0.56)
			snow.append(sl)
			for k in 4:
				var t := float(k + 1) / 5.0
				snow.append(sl.lerp(sr, t) + Vector2(0, (-6.0 if k % 2 == 0 else 4.0) * s))
			snow.append(sr)
			draw_colored_polygon(snow, Color(0.92, 0.93, 0.94))
		for i in 4:
			var sp := bl.lerp(br, rng.randf()) + Vector2(rng.randf_range(-5, 5), rng.randf_range(2, 9))
			draw_circle(sp, 1.4 + rng.randf() * 1.4, Color(0.36, 0.33, 0.3, 0.85))

	func _p_mountain(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.45, 0.42, 0.37))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 55), 62), Color(0.41, 0.38, 0.34, 0.6))
		# Structural variant modes so tiles don't read as one copy-pasted peak
		match seed_val % 3:
			0:
				# One large peak + small companion, varied placement
				var main_c := C + Vector2(rng.randf_range(-24, 10), rng.randf_range(26, 44))
				_mount_peak(rng, main_c + Vector2(rng.randf_range(30, 48), rng.randf_range(2, 10)), 0.55 + rng.randf() * 0.15, false)
				_mount_peak(rng, main_c, 0.95 + rng.randf() * 0.15, true)
			1:
				# Overlapping ridge of two medium peaks
				var rc := C + Vector2(rng.randf_range(-16, 16), rng.randf_range(26, 40))
				_mount_peak(rng, rc + Vector2(-30 + rng.randf_range(-8, 8), 4), 0.72 + rng.randf() * 0.12, rng.randf() < 0.5)
				_mount_peak(rng, rc + Vector2(30 + rng.randf_range(-8, 8), 0), 0.8 + rng.randf() * 0.15, true)
			_:
				# Diagonal chain of three small peaks
				var start := C + Vector2(rng.randf_range(-46, -30), rng.randf_range(-18, -2))
				var step := Vector2(38 + rng.randf_range(-6, 6), 26 + rng.randf_range(-6, 6))
				for i in 3:
					var pc := start + step * float(i) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4))
					_mount_peak(rng, pc + Vector2(0, 30), 0.5 + rng.randf() * 0.2, i == 1)

	func _p_desert(rng: RandomNumberGenerator) -> void:
		var t := rng.randf() * 0.04 - 0.02
		_fill(Color(0.71 + t, 0.62 + t, 0.42))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 65), 55), Color(0.76, 0.67, 0.46, 0.75))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 70), 40), Color(0.66, 0.57, 0.38, 0.6))
		# Barchan dunes from above: crescent slip-face shadows with a lit
		# windward rim, varied position/rotation/size
		for i in 2 + rng.randi() % 3:
			var p := _rand_in(rng, 85)
			var dr := 18.0 + rng.randf() * 20.0
			var rot := rng.randf() * TAU
			var a0 := rot - PI * 0.42
			var a1 := rot + PI * 0.42
			var shadow := PackedVector2Array()
			for k in 8:
				var a := lerpf(a0, a1, float(k) / 7.0)
				shadow.append(p + Vector2(cos(a), sin(a)) * dr)
			for k in 8:
				var a := lerpf(a1, a0, float(k) / 7.0)
				shadow.append(p + Vector2(cos(a), sin(a)) * (dr - 5.0 - rng.randf() * 3.0))
			draw_colored_polygon(shadow, Color(0.55, 0.46, 0.3, 0.85))
			var rim := PackedVector2Array()
			for k in 9:
				var a := lerpf(a0, a1, float(k) / 8.0)
				rim.append(p + Vector2(cos(a), sin(a)) * (dr + 1.5))
			draw_polyline(rim, Color(0.82, 0.73, 0.5, 0.9), 2.2, true)
		# Faint sand ripples + pebbles
		var rip_dir := rng.randf() * TAU
		for i in 4:
			var rp := _rand_in(rng, 80)
			var rv := Vector2(cos(rip_dir), sin(rip_dir)) * (10.0 + rng.randf() * 8.0)
			draw_line(rp - rv, rp + rv, Color(0.62, 0.53, 0.35, 0.5), 1.4)
		for i in 3:
			draw_circle(_rand_in(rng, 85), 2.0, Color(0.6, 0.52, 0.36))

	func _swamp_pool(rng: RandomNumberGenerator, p: Vector2, pr: float) -> void:
		draw_colored_polygon(_blob(rng, p, pr, 11, 0.35), Color(0.1, 0.14, 0.12, 0.97))
		draw_polyline(_blob(rng, p, pr * 0.72, 9, 0.25), Color(0.24, 0.3, 0.24, 0.55), 1.8, true)
		# Lily pads floating on the pool
		for i in 1 + rng.randi() % 3:
			var lp := p + Vector2(rng.randf_range(-pr, pr) * 0.55, rng.randf_range(-pr, pr) * 0.5)
			draw_circle(lp, 3.6 + rng.randf() * 1.8, Color(0.3, 0.4, 0.22, 0.95))
			draw_circle(lp + Vector2(-1.0, -1.0), 1.1, Color(0.4, 0.5, 0.28))

	func _p_swamp(rng: RandomNumberGenerator) -> void:
		# Darker, murkier base
		_fill(Color(0.24, 0.26, 0.16))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 50), 62), Color(0.19, 0.21, 0.13, 0.9))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 60), 40), Color(0.28, 0.3, 0.18, 0.7))
		# Variants 3 and 6: two clearly separated ponds; otherwise 1-2 pools
		if seed_val == 3 or seed_val == 6:
			_swamp_pool(rng, C + Vector2(-42 + rng.randf_range(-8, 8), -30 + rng.randf_range(-8, 8)), 22.0 + rng.randf() * 6.0)
			_swamp_pool(rng, C + Vector2(38 + rng.randf_range(-8, 8), 34 + rng.randf_range(-8, 8)), 19.0 + rng.randf() * 6.0)
		else:
			for i in 1 + rng.randi() % 2:
				_swamp_pool(rng, _rand_in(rng, 55), 26.0 + rng.randf() * 16.0)
		# Dead snag (bare tree) on some tiles
		if rng.randf() < 0.5:
			var sp := _rand_in(rng, 70)
			draw_line(sp + Vector2(0, 12), sp + Vector2(2, -14), Color(0.16, 0.13, 0.1), 3.0)
			draw_line(sp + Vector2(1, -4), sp + Vector2(-8, -12), Color(0.16, 0.13, 0.1), 2.0)
			draw_line(sp + Vector2(1.5, -8), sp + Vector2(9, -15), Color(0.16, 0.13, 0.1), 2.0)
		# Rush clumps
		for i in 3:
			var cp2 := _rand_in(rng, 88)
			for k in 4:
				var dp := cp2 + Vector2(rng.randf_range(-5, 5), rng.randf_range(-4, 4))
				draw_circle(dp, 1.5, Color(0.34, 0.38, 0.2, 0.9))
		# Low mist streak
		draw_colored_polygon(_blob(rng, _rand_in(rng, 55), 34, 9, 0.5), Color(0.7, 0.75, 0.7, 0.06))

	func _p_wetlands(rng: RandomNumberGenerator) -> void:
		# Green-dominant marsh: grass base with small irregular PUDDLES — no
		# horizontal wave bands (those read as impassable water/river)
		_fill(Color(0.34, 0.44, 0.3))
		for i in 2 + rng.randi() % 3:
			draw_colored_polygon(_blob(rng, _rand_in(rng, 95), 22.0 + rng.randf() * 26.0, 9, 0.5), Color(0.3, 0.4, 0.27, 0.7))
		# Scattered small puddles with grassy rims
		for i in 2 + rng.randi() % 3:
			var pp := _rand_in(rng, 80)
			var pr := 9.0 + rng.randf() * 11.0
			draw_colored_polygon(_blob(rng, pp, pr * 1.25, 9, 0.4), Color(0.26, 0.36, 0.22, 0.9))
			draw_colored_polygon(_blob(rng, pp, pr, 9, 0.35), Color(0.3, 0.42, 0.44, 0.95))
			draw_circle(pp + Vector2(-pr * 0.25, -pr * 0.25), 1.6, Color(0.55, 0.66, 0.66, 0.7))
		# Dense tuft clusters + reeds
		for i in 8 + rng.randi() % 5:
			var p := _rand_in(rng, 95)
			for k in 4 + rng.randi() % 3:
				var dp := p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-5, 5))
				draw_circle(dp, 1.4 + rng.randf() * 1.0, Color(0.42, 0.52, 0.3, 0.9))
		for i in 3:
			var rp := _rand_in(rng, 85)
			for k in 3:
				var rx := float(k - 1) * 3.4
				draw_circle(rp + Vector2(rx, rng.randf_range(-2, 2)), 1.7, Color(0.5, 0.56, 0.3))

	func _tundra_tree(rng: RandomNumberGenerator, tp: Vector2) -> void:
		# Top-down conifer with snow-side shadow
		draw_colored_polygon(_blob(rng, tp + Vector2(2.5, 2.5), 11.0, 9, 0.25), Color(0.5, 0.54, 0.55, 0.6))
		draw_colored_polygon(_blob(rng, tp, 10.5, 9, 0.3), Color(0.2, 0.28, 0.22))
		draw_colored_polygon(_blob(rng, tp + Vector2(-1.5, -1.5), 5.0, 8, 0.3), Color(0.26, 0.35, 0.28))
		draw_circle(tp, 1.4, Color(0.32, 0.4, 0.32))

	func _p_tundra(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.66, 0.68, 0.66))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 60), 58), Color(0.58, 0.61, 0.62, 0.7))
		# Sprawling multi-blob snow fields, several crossing the tile edge so
		# neighboring tundra tiles blend into one snowy landscape instead of
		# each reading as "one speck in the middle"
		for i in 2 + rng.randi() % 3:
			var sp := _rand_in(rng, 98)
			var sr := 24.0 + rng.randf() * 22.0
			draw_colored_polygon(_blob(rng, sp, sr, 10, 0.5), Color(0.84, 0.86, 0.87))
			draw_colored_polygon(_blob(rng, sp + Vector2(rng.randf_range(-16, 16), rng.randf_range(-12, 12)), sr * 0.65, 9, 0.55), Color(0.88, 0.9, 0.91))
		# Trees per variant: offset single tree, a pair, or a rock
		var tree_mode := seed_val % 3
		if tree_mode == 0:
			_tundra_tree(rng, C + Vector2(rng.randf_range(18, 44) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-40, 34)))
		elif tree_mode == 1:
			_tundra_tree(rng, C + Vector2(-34 + rng.randf_range(-8, 8), -22 + rng.randf_range(-8, 8)))
			_tundra_tree(rng, C + Vector2(28 + rng.randf_range(-8, 8), 26 + rng.randf_range(-8, 8)))
		else:
			var rp := _rand_in(rng, 65)
			draw_colored_polygon(_blob(rng, rp, 14, 8, 0.3), Color(0.52, 0.53, 0.52))
			draw_colored_polygon(_blob(rng, rp + Vector2(-3, -4), 7, 7, 0.3), Color(0.72, 0.73, 0.72))
		for i in 5:
			draw_circle(_rand_in(rng, 90), 1.6, Color(0.78, 0.8, 0.8, 0.8))

	func _shard_cluster(rng: RandomNumberGenerator, cp: Vector2, scale: float) -> void:
		draw_circle(cp, (24.0 + rng.randf() * 22.0) * scale, Color(0.62, 0.45, 0.75, 0.1 + rng.randf() * 0.1))
		for i in 1 + rng.randi() % 4:
			var sp := cp + Vector2(rng.randf_range(-22, 22) * scale, rng.randf_range(-12, 16) * scale)
			var h := (16.0 + rng.randf() * 42.0) * scale
			var tilt := rng.randf_range(-0.6, 0.6)
			var tip := sp + Vector2(sin(tilt) * h, -cos(tilt) * h)
			var half_w := (4.0 + rng.randf() * 6.0) * scale * clampf(h / 34.0, 0.6, 1.3)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(-half_w, 0), tip, sp + Vector2(half_w, 0)]), Color(0.6, 0.42, 0.72))
			draw_line(sp + Vector2(-half_w * 0.4, -2), tip, Color(0.78, 0.62, 0.88), maxf(1.2, 2.2 * scale))

	func _p_shardwaste(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.42, 0.36, 0.44))
		# Varied ground mottling, some crossing tile edges
		for i in 2 + rng.randi() % 2:
			draw_colored_polygon(_blob(rng, _rand_in(rng, 95), 26.0 + rng.randf() * 30.0, 9, 0.45), Color(0.34, 0.29, 0.37, 0.7))
		# 1-3 crystal clusters at varied positions/sizes (may sit near edges),
		# instead of one centered circle-with-crystals
		for i in 1 + rng.randi() % 3:
			_shard_cluster(rng, _rand_in(rng, 82), 0.6 + rng.randf() * 0.6)
		# Lone stray shards
		for i in 1 + rng.randi() % 3:
			var sp2 := _rand_in(rng, 95)
			var lh := 8.0 + rng.randf() * 12.0
			draw_colored_polygon(PackedVector2Array([
				sp2 + Vector2(-3.5, 0), sp2 + Vector2(rng.randf_range(-6, 6), -lh), sp2 + Vector2(3.5, 0)
			]), Color(0.55, 0.4, 0.66, 0.9))
		# Ground crack
		if rng.randf() < 0.6:
			var ck0 := _rand_in(rng, 70)
			var ck := PackedVector2Array([ck0])
			for k in 4:
				ck.append(ck[k] + Vector2(rng.randf_range(-4, 18), rng.randf_range(6, 16)))
			draw_polyline(ck, Color(0.26, 0.22, 0.3, 0.8), 1.8, true)

	func _p_water(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.13, 0.2, 0.34))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 50), 62), Color(0.11, 0.18, 0.31, 0.9))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 55), 34), Color(0.15, 0.23, 0.37, 0.8))
		for i in 3:
			draw_circle(_rand_in(rng, 80), 1.4, Color(0.4, 0.5, 0.62, 0.5))
		for i in 3 + rng.randi() % 2:
			var p := _rand_in(rng, 70)
			var w := 36.0 + rng.randf() * 30.0
			var arc := PackedVector2Array()
			for k in 7:
				var tt := float(k) / 6.0
				arc.append(p + Vector2((tt - 0.5) * w * 2.0, -sin(tt * PI) * w * 0.22))
			draw_polyline(arc, Color(0.22, 0.32, 0.46, 0.8), 3.2, true)

	func _p_river(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.18, 0.3, 0.4))
		draw_colored_polygon(_blob(rng, C, 90, 10, 0.25), Color(0.2, 0.33, 0.43, 0.7))
		for i in 3:
			var y := float(i - 1) * 46.0 + rng.randf_range(-6, 6)
			var line := PackedVector2Array()
			for k in 11:
				var tt := float(k) / 10.0
				line.append(C + Vector2((tt - 0.5) * 250.0, y + sin(tt * TAU + float(i)) * 5.0))
			draw_polyline(line, Color(0.33, 0.47, 0.56, 0.85), 3.2, true)
		for i in 5:
			draw_circle(_rand_in(rng, 75), 2.2, Color(0.6, 0.72, 0.78, 0.7))

	func _spiky_crown(rng: RandomNumberGenerator, p: Vector2, cr: float, color: Color) -> void:
		# Star-shaped canopy crown seen from above — keeps the sharp, aggressive
		# language but reads as a treetop rather than fallen grass blades
		var pts := PackedVector2Array()
		var spikes := 7 + rng.randi() % 3
		var a0 := rng.randf() * TAU
		for k in spikes * 2:
			var a := a0 + TAU * float(k) / float(spikes * 2)
			var r := cr if k % 2 == 0 else cr * (0.5 + rng.randf() * 0.12)
			pts.append(p + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, color)

	func _p_jungle(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.16, 0.3, 0.17))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 50), 60), Color(0.13, 0.26, 0.15, 0.9))
		for i in 5 + rng.randi() % 3:
			var p := _rand_in(rng, 82)
			var cr := 16.0 + rng.randf() * 9.0
			# Ground shadow, dark spiky crown, lighter spiky top, dark center
			draw_colored_polygon(_blob(rng, p + Vector2(3, 3.5), cr * 0.9, 8, 0.3), Color(0.09, 0.19, 0.11, 0.6))
			_spiky_crown(rng, p, cr, Color(0.18, 0.34, 0.16))
			_spiky_crown(rng, p + Vector2(-cr * 0.14, -cr * 0.16), cr * 0.62, Color(0.28, 0.48, 0.22))
			draw_circle(p, 1.6, Color(0.1, 0.22, 0.12))
		var vp0 := _rand_in(rng, 60)
		var vine := PackedVector2Array()
		for k in 9:
			var tt := float(k) / 8.0
			vine.append(vp0 + Vector2(tt * 46.0, sin(tt * 7.0) * 9.0))
		draw_polyline(vine, Color(0.35, 0.45, 0.2), 2.8, true)

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	_painter = _TilePainter.new()
	_vp.add_child(_painter)
	for set_name in SETS:
		for v in range(1, 8):
			_jobs.append([set_name, v])

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	# Capture the tile configured last frame
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		img.save_png("%s/%s%d.png" % [OUT_DIR, job[0], job[1]])
		_capture_pending = false
	# Configure next tile
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		_painter.terrain = job[0]
		_painter.seed_val = job[1]
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d tiles into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
