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
		_shade(rng, Color(0.2, 0.31, 0.18, 0.7))
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

	## 2-3 spread-out shading blobs — replaces the old single centered dark
	## circle that made tiles read as "one dark spot in the middle"
	func _shade(rng: RandomNumberGenerator, color: Color) -> void:
		for i in 2 + rng.randi() % 2:
			draw_colored_polygon(_blob(rng, _rand_in(rng, 95), 22.0 + rng.randf() * 24.0, 9, 0.45), color)

	func _mount_massif(rng: RandomNumberGenerator, p: Vector2, s: float, snow: bool) -> void:
		# Rocky mass seen from ABOVE (rotation-safe): angular body, subtle
		# shadow lobe, lit facet, sharp ridge cracks, optional summit snowfield
		var body := _blob(rng, p, 34.0 * s, 8, 0.55)
		draw_colored_polygon(_blob(rng, p + Vector2(4.0 * s, 5.0 * s), 34.0 * s, 8, 0.5), Color(0.26, 0.23, 0.21, 0.8))
		draw_colored_polygon(body, Color(0.58, 0.55, 0.48))
		draw_colored_polygon(_blob(rng, p + Vector2(-4.0 * s, -5.0 * s), 20.0 * s, 8, 0.5), Color(0.68, 0.64, 0.56))
		# Ridge cracks across the mass
		for i in 2 + rng.randi() % 2:
			var a := rng.randf() * TAU
			var dirv := Vector2(cos(a), sin(a))
			var mid := p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)) * s
			var crack := PackedVector2Array([mid - dirv * 22.0 * s])
			crack.append(mid + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)) * s)
			crack.append(mid + dirv * 20.0 * s)
			draw_polyline(crack, Color(0.26, 0.23, 0.2, 0.9), maxf(1.4, 2.2 * s), true)
		if snow:
			draw_colored_polygon(_blob(rng, p + Vector2(-2.0 * s, -2.0 * s), 13.0 * s, 9, 0.6), Color(0.92, 0.93, 0.94))
		for i in 4:
			var a2 := rng.randf() * TAU
			var sp := p + Vector2(cos(a2), sin(a2)) * (34.0 * s + rng.randf() * 8.0)
			draw_circle(sp, 1.4 + rng.randf() * 1.4, Color(0.36, 0.33, 0.3, 0.85))

	func _p_mountain(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.45, 0.42, 0.37))
		_shade(rng, Color(0.41, 0.38, 0.34, 0.55))
		# Structural variant modes, all top-down and rotation-safe
		match seed_val % 3:
			0:
				# One large massif + small companion
				var main_c := _rand_in(rng, 30)
				_mount_massif(rng, main_c + Vector2((1.0 if rng.randf() < 0.5 else -1.0) * (52.0 + rng.randf() * 12.0), rng.randf_range(-34, 34)), 0.58 + rng.randf() * 0.15, false)
				_mount_massif(rng, main_c, 1.15 + rng.randf() * 0.15, true)
			1:
				# Two overlapping medium masses
				var rc := _rand_in(rng, 25)
				var axis := rng.randf() * TAU
				var off := Vector2(cos(axis), sin(axis)) * (38.0 + rng.randf() * 8.0)
				_mount_massif(rng, rc - off, 0.85 + rng.randf() * 0.12, rng.randf() < 0.5)
				_mount_massif(rng, rc + off, 0.95 + rng.randf() * 0.15, true)
			_:
				# Chain of three small masses along a random axis
				var axis2 := rng.randf() * TAU
				var step := Vector2(cos(axis2), sin(axis2)) * (40.0 + rng.randf() * 8.0)
				var start := C - step + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
				for i in 3:
					var pc := start + step * float(i) + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
					_mount_massif(rng, pc, 0.6 + rng.randf() * 0.18, i == 1)

	func _palm(rng: RandomNumberGenerator, pp: Vector2) -> void:
		# Small lone palm seen from ABOVE: soft shadow, radial fronds, trunk dot
		draw_colored_polygon(_blob(rng, pp + Vector2(3, 3), 15.0, 8, 0.3), Color(0.5, 0.42, 0.28, 0.5))
		var fronds := 6 + rng.randi() % 3
		for i in fronds:
			var fa := TAU * float(i) / float(fronds) + rng.randf_range(-0.15, 0.15)
			var fl := 15.0 + rng.randf() * 5.0
			var dirv := Vector2(cos(fa), sin(fa))
			var perp := Vector2(-dirv.y, dirv.x)
			draw_colored_polygon(PackedVector2Array([
				pp, pp + dirv * fl * 0.55 + perp * 2.6, pp + dirv * fl, pp + dirv * fl * 0.55 - perp * 2.6
			]), Color(0.25, 0.42, 0.2))
		draw_circle(pp, 2.4, Color(0.45, 0.35, 0.2))

	func _p_desert(rng: RandomNumberGenerator) -> void:
		# Wider per-tile tint range: warm/pale/reddish sand mixes
		var t := rng.randf() * 0.08 - 0.04
		var h := rng.randf() * 0.05
		_fill(Color(0.71 + t, 0.62 + t - h * 0.4, 0.42 + h))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 65), 55), Color(0.76 + t, 0.67 + t, 0.46 + h, 0.75))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 70), 40), Color(0.66 + t, 0.57 + t - h * 0.5, 0.38, 0.6))
		# Barchan dunes from above: one shared wind direction per tile, no
		# overlapping placement, elongated irregular crescents (not round arcs)
		var wind := rng.randf() * TAU
		var placed: Array = []
		for i in 2 + rng.randi() % 3:
			var dr := 16.0 + rng.randf() * 16.0
			var p := _rand_in(rng, 85)
			var ok := false
			for attempt in 8:
				ok = true
				for pr in placed:
					if p.distance_to(pr[0]) < (dr + pr[1]) * 1.05:
						ok = false
						break
				if ok:
					break
				p = _rand_in(rng, 95)
			if not ok:
				continue
			placed.append([p, dr])
			var rot := wind + rng.randf_range(-0.3, 0.3)
			var dirv := Vector2(cos(rot), sin(rot))
			var perp := Vector2(-dirv.y, dirv.x)
			var elong := 1.3 + rng.randf() * 0.35
			var span := PI * (0.36 + rng.randf() * 0.14)
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			var mound := PackedVector2Array()
			for k in 9:
				var la := lerpf(-span, span, float(k) / 8.0)
				var rr := dr * (0.92 + rng.randf() * 0.16)
				var band := 9.0 + rng.randf() * 5.0  # slip face must read as a dune body, not a crack
				outer.append(p + dirv * cos(la) * rr + perp * sin(la) * rr * elong)
				inner.append(p + dirv * cos(la) * (rr - band) + perp * sin(la) * (rr - band) * elong)
				mound.append(p + dirv * cos(la) * (rr - band * 0.4) * 0.72 + perp * sin(la) * (rr - band * 0.4) * 0.72 * elong)
			# Soft lighter mound filling the dune's windward interior
			draw_colored_polygon(mound, Color(0.78 + t, 0.69 + t, 0.48 + h, 0.7))
			var shadow := outer.duplicate()
			inner.reverse()
			shadow.append_array(inner)
			draw_colored_polygon(shadow, Color(0.55 + t, 0.46 + t, 0.3, 0.85))
			draw_polyline(outer, Color(0.82 + t, 0.73 + t, 0.5, 0.9), 2.2, true)
		# One desert variant carries a small lone palm
		if seed_val == 4:
			_palm(rng, C + Vector2(rng.randf_range(24, 48) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-42, 38)))
		# Faint sand ripples (following the wind) + pebbles
		for i in 4:
			var rp := _rand_in(rng, 80)
			var rv := Vector2(cos(wind), sin(wind)) * (10.0 + rng.randf() * 8.0)
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
		# Very dark, murky base — swamps are hard to traverse and must read so
		_fill(Color(0.19, 0.21, 0.12))
		_shade(rng, Color(0.15, 0.17, 0.1, 0.75))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 60), 40), Color(0.24, 0.26, 0.15, 0.6))
		# Every tile gets 2-3 pools, most of them large, so standing water
		# dominates the terrain
		match seed_val % 3:
			0:
				# Two big clearly separated ponds
				_swamp_pool(rng, C + Vector2(-40 + rng.randf_range(-8, 8), -28 + rng.randf_range(-8, 8)), 26.0 + rng.randf() * 8.0)
				_swamp_pool(rng, C + Vector2(36 + rng.randf_range(-8, 8), 32 + rng.randf_range(-8, 8)), 22.0 + rng.randf() * 8.0)
			1:
				# One dominant pool + a smaller satellite near the edge
				_swamp_pool(rng, _rand_in(rng, 35), 34.0 + rng.randf() * 10.0)
				var sat_a := rng.randf() * TAU
				_swamp_pool(rng, C + Vector2(cos(sat_a), sin(sat_a)) * (72.0 + rng.randf() * 14.0), 14.0 + rng.randf() * 6.0)
			_:
				# Three medium pools spread across the tile
				for i in 3:
					var pa := TAU * float(i) / 3.0 + rng.randf() * 1.2
					_swamp_pool(rng, C + Vector2(cos(pa), sin(pa)) * (44.0 + rng.randf() * 18.0), 17.0 + rng.randf() * 9.0)
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

	func _tundra_rock(rng: RandomNumberGenerator, rp: Vector2, s := 1.0) -> void:
		draw_colored_polygon(_blob(rng, rp, 14.0 * s, 8, 0.3), Color(0.52, 0.53, 0.52))
		draw_colored_polygon(_blob(rng, rp + Vector2(-3, -4) * s, 7.0 * s, 7, 0.3), Color(0.72, 0.73, 0.72))

	func _p_tundra(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.66, 0.68, 0.66))
		_shade(rng, Color(0.58, 0.61, 0.62, 0.6))
		# Sprawling multi-blob snow fields, several crossing the tile edge so
		# neighboring tundra tiles blend into one snowy landscape instead of
		# each reading as "one speck in the middle"
		for i in 2 + rng.randi() % 3:
			var sp := _rand_in(rng, 98)
			var sr := 24.0 + rng.randf() * 22.0
			draw_colored_polygon(_blob(rng, sp, sr, 10, 0.5), Color(0.84, 0.86, 0.87))
			draw_colored_polygon(_blob(rng, sp + Vector2(rng.randf_range(-16, 16), rng.randf_range(-12, 12)), sr * 0.65, 9, 0.55), Color(0.88, 0.9, 0.91))
		# Features per variant: single offset tree, tree pair, one rock, or two rocks
		match seed_val % 4:
			0:
				_tundra_tree(rng, C + Vector2(rng.randf_range(18, 44) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-40, 34)))
			1:
				_tundra_tree(rng, C + Vector2(-34 + rng.randf_range(-8, 8), -22 + rng.randf_range(-8, 8)))
				_tundra_tree(rng, C + Vector2(28 + rng.randf_range(-8, 8), 26 + rng.randf_range(-8, 8)))
			2:
				_tundra_rock(rng, _rand_in(rng, 65))
			_:
				_tundra_rock(rng, C + Vector2(-30 + rng.randf_range(-10, 10), 20 + rng.randf_range(-10, 10)), 0.9 + rng.randf() * 0.2)
				_tundra_rock(rng, C + Vector2(32 + rng.randf_range(-10, 10), -24 + rng.randf_range(-10, 10)), 0.7 + rng.randf() * 0.2)
		for i in 5:
			draw_circle(_rand_in(rng, 90), 1.6, Color(0.78, 0.8, 0.8, 0.8))

	## One crystal kite seen from ABOVE: radiates outward from its base in a
	## random direction (no side-view "pointing up" spikes)
	func _shard_kite(rng: RandomNumberGenerator, base: Vector2, a: float, length: float, scale: float) -> void:
		var dirv := Vector2(cos(a), sin(a))
		var perp := Vector2(-dirv.y, dirv.x)
		var hw := (4.5 + rng.randf() * 4.0) * scale * clampf(length / 28.0, 0.65, 1.3)
		var tip := base + dirv * length
		var waist := base + dirv * length * 0.35
		draw_colored_polygon(PackedVector2Array([base, waist + perp * hw, tip, waist - perp * hw]), Color(0.6, 0.42, 0.72))
		draw_line(base + dirv * length * 0.1, tip, Color(0.78, 0.62, 0.88), maxf(1.2, 2.0 * scale))
		draw_line(waist + perp * hw * 0.7, tip, Color(0.48, 0.32, 0.6), 1.2)

	func _shard_cluster(rng: RandomNumberGenerator, cp: Vector2, scale: float) -> void:
		# Glow patch + shards spraying outward in varied directions (top-down)
		draw_circle(cp, (24.0 + rng.randf() * 22.0) * scale, Color(0.62, 0.45, 0.75, 0.1 + rng.randf() * 0.1))
		var n := 2 + rng.randi() % 4
		var base_a := rng.randf() * TAU
		for i in n:
			var a := base_a + TAU * float(i) / float(n) + rng.randf_range(-0.5, 0.5)
			var base := cp + Vector2(cos(a), sin(a)) * rng.randf_range(2, 9) * scale
			_shard_kite(rng, base, a, (16.0 + rng.randf() * 26.0) * scale, scale)

	func _p_shardwaste(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.42, 0.36, 0.44))
		# Varied ground mottling, some crossing tile edges
		for i in 2 + rng.randi() % 2:
			draw_colored_polygon(_blob(rng, _rand_in(rng, 95), 26.0 + rng.randf() * 30.0, 9, 0.45), Color(0.34, 0.29, 0.37, 0.7))
		# Jagged ground cracks: 2-3 per tile, each with its own random overall
		# direction, hard zigzags and occasional forks — drawn under crystals
		for i in 2 + rng.randi() % 2:
			var ca := rng.randf() * TAU
			var cd := Vector2(cos(ca), sin(ca))
			var pts := PackedVector2Array([_rand_in(rng, 80)])
			for k in 5 + rng.randi() % 3:
				if rng.randf() < 0.35:
					ca += rng.randf_range(-1.0, 1.0)
					cd = Vector2(cos(ca), sin(ca))
				var cperp := Vector2(-cd.y, cd.x)
				pts.append(pts[k] + cd * (7.0 + rng.randf() * 9.0) + cperp * rng.randf_range(-7.0, 7.0))
			draw_polyline(pts, Color(0.26, 0.22, 0.3, 0.85), 1.4 + rng.randf() * 1.2, true)
			if rng.randf() < 0.7 and pts.size() > 3:
				var bi := 1 + rng.randi() % (pts.size() - 2)
				var ba := ca + rng.randf_range(0.6, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0)
				var bd := Vector2(cos(ba), sin(ba))
				var bpts := PackedVector2Array([pts[bi]])
				for k in 2 + rng.randi() % 2:
					bpts.append(bpts[k] + bd * (6.0 + rng.randf() * 7.0) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)))
				draw_polyline(bpts, Color(0.26, 0.22, 0.3, 0.7), 1.2, true)
		# 1-3 crystal clusters at varied positions/sizes (may sit near edges),
		# instead of one centered circle-with-crystals
		for i in 1 + rng.randi() % 3:
			_shard_cluster(rng, _rand_in(rng, 82), 0.6 + rng.randf() * 0.6)
		# Lone stray shards, also radiating in random directions
		for i in 1 + rng.randi() % 3:
			_shard_kite(rng, _rand_in(rng, 95), rng.randf() * TAU, 8.0 + rng.randf() * 12.0, 0.8)

	func _p_water(rng: RandomNumberGenerator) -> void:
		_fill(Color(0.13, 0.2, 0.34))
		_shade(rng, Color(0.11, 0.18, 0.31, 0.7))
		draw_colored_polygon(_blob(rng, _rand_in(rng, 75), 34), Color(0.15, 0.23, 0.37, 0.8))
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
		_shade(rng, Color(0.2, 0.33, 0.43, 0.6))
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
		_shade(rng, Color(0.13, 0.26, 0.15, 0.7))
		for i in 8 + rng.randi() % 3:
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
