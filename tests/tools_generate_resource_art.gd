extends SceneTree
## Resource-tier art generator — renders bounty / special-deposit / landmark
## map icons into res://assets/sprites/resources/, "boardgame gouache" style
## (matches tools_generate_terrain_tiles.gd). Deterministic per asset id
## (rng.seed = hash(asset_id) — no global RNG). Run WINDOWED (SubViewport
## capture needs a live window; a brief flash is expected):
##   & <godot> --resolution 600x600 -s res://tests/tools_generate_resource_art.gd -- bounty
## then: & <godot> --headless --path . --import
## Mode arg selects one tier to (re)generate; omit it to run all tiers (a
## tier with no ids yet implemented simply produces zero jobs — a no-op).

const OUT_DIR := "res://assets/sprites/resources"
const SIZE_BY_MODE := {"bounty": 64, "deposit": 128, "landmark": 512}

## The 22 Tier-1 bounty ids (must match BountySystem.BOUNTY_TYPES exactly).
const BOUNTY_IDS: Array[StringName] = [
	&"orchards", &"grain_basin", &"vineyards", &"honey_apiaries", &"herb_meadows",
	&"wild_horses", &"fisheries", &"pearl_beds", &"salt_flats", &"marble",
	&"granite", &"basalt_columns", &"copper_vein", &"obsidian_flows",
	&"titanstone_quarry", &"timber_giants", &"amber_groves", &"furs",
	&"crystal_springs", &"clay_pits", &"peat_bogs", &"dye_gardens",
]

## Future tasks: special-deposit (128px) and landmark (512px) ids. Empty for
## now — Task 1 only covers the bounty tier; painters land in a later task.
const DEPOSIT_IDS: Array[StringName] = []
const LANDMARK_IDS: Array[StringName] = []

var _vp: SubViewport
var _painter: _ResourcePainter
var _jobs: Array = []  # each entry: [mode: String, asset_id: StringName]
var _job_idx := -1
var _capture_pending := false

class _ResourcePainter extends Node2D:
	var mode := "bounty"
	var asset_id: StringName = &""

	# ── Shared helpers, copied verbatim from tools_generate_terrain_tiles.gd ──

	func _blob(rng: RandomNumberGenerator, center: Vector2, base_r: float, verts := 10, jitter := 0.35) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in verts:
			var a := TAU * float(i) / float(verts)
			var rr := base_r * (1.0 - jitter * 0.5 + rng.randf() * jitter)
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
		return pts

	func _wavy_line(rng: RandomNumberGenerator, from: Vector2, to: Vector2, amp: float, segs: int) -> PackedVector2Array:
		var dirv := (to - from).normalized()
		var perp := Vector2(-dirv.y, dirv.x)
		var pts := PackedVector2Array()
		for k in segs + 1:
			var t := float(k) / float(segs)
			pts.append(from.lerp(to, t) + perp * sin(t * PI * 2.0 + rng.randf() * 2.0) * amp)
		return pts

	func _chip(size: float) -> void:
		# Dark chip + gold rim, the on-map identity for bounty icons
		var c := Vector2(size / 2.0, size / 2.0)
		draw_circle(c, size * 0.48, Color(0.78, 0.62, 0.32))
		draw_circle(c, size * 0.42, Color(0.09, 0.075, 0.055))

	func _outline_poly(pts: PackedVector2Array, fill: Color, outline: Color, width := 1.5) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, width)

	## Small extra helpers (not in the terrain tool, used by a few emblems below).
	func _hexagon(center: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a := TAU * float(i) / 6.0 - PI / 6.0  # flat-top orientation
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		return pts

	func _diamond(center: Vector2, r: float) -> PackedVector2Array:
		return PackedVector2Array([
			center + Vector2(0, -r), center + Vector2(r * 0.75, 0),
			center + Vector2(0, r), center + Vector2(-r * 0.75, 0),
		])

	# ── Dispatch ─────────────────────────────────────────────────────────────

	func _draw() -> void:
		match mode:
			"bounty":
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(asset_id)
				_paint_bounty(rng, asset_id)
			"deposit":
				pass  # Task 2: deposit-tier painters land later
			"landmark":
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
				pass  # Task 3: landmark-tier painters land later
			_:
				pass

	func _paint_bounty(rng: RandomNumberGenerator, id: StringName) -> void:
		match id:
			&"orchards": _b_orchards(rng)
			&"grain_basin": _b_grain_basin(rng)
			&"vineyards": _b_vineyards(rng)
			&"honey_apiaries": _b_honey_apiaries(rng)
			&"herb_meadows": _b_herb_meadows(rng)
			&"wild_horses": _b_wild_horses(rng)
			&"fisheries": _b_fisheries(rng)
			&"pearl_beds": _b_pearl_beds(rng)
			&"salt_flats": _b_salt_flats(rng)
			&"marble": _b_marble(rng)
			&"granite": _b_granite(rng)
			&"basalt_columns": _b_basalt_columns(rng)
			&"copper_vein": _b_copper_vein(rng)
			&"obsidian_flows": _b_obsidian_flows(rng)
			&"titanstone_quarry": _b_titanstone_quarry(rng)
			&"timber_giants": _b_timber_giants(rng)
			&"amber_groves": _b_amber_groves(rng)
			&"furs": _b_furs(rng)
			&"crystal_springs": _b_crystal_springs(rng)
			&"clay_pits": _b_clay_pits(rng)
			&"peat_bogs": _b_peat_bogs(rng)
			&"dye_gardens": _b_dye_gardens(rng)
			_:
				# id == "" happens once, harmlessly: newly-added CanvasItems get
				# an engine-triggered redraw with default field values before the
				# first real job is configured. Only warn on a genuine unknown id.
				if id != &"":
					push_warning("No bounty painter for id: %s" % id)

	# ── The 22 bounty painters ───────────────────────────────────────────────
	# Each draws _chip(64.0) then a 2-3 color emblem centered near (32,32),
	# radius ~14-17px, gouache-flat with a darker outline tone.

	func _b_orchards(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var c := Vector2(32, 34)
		draw_line(c + Vector2(0, 10), c + Vector2(0, -2), Color(0.42, 0.3, 0.2), 3.0)
		_outline_poly(_blob(rng, c + Vector2(0, -6), 11.0, 9, 0.25), Color(0.35, 0.5, 0.28), Color(0.22, 0.34, 0.18))
		draw_circle(c + Vector2(-4, -8), 2.6, Color(0.78, 0.32, 0.28))
		draw_circle(c + Vector2(5, -4), 2.6, Color(0.78, 0.32, 0.28))
		draw_circle(c + Vector2(1, -12), 2.2, Color(0.82, 0.62, 0.3))

	func _b_wild_horses(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		# Horse head silhouette: neck wedge + muzzle + ears, warm bay tone
		var pts := PackedVector2Array([
			Vector2(24, 46), Vector2(27, 30), Vector2(31, 22), Vector2(30, 17),
			Vector2(34, 21), Vector2(38, 20), Vector2(36, 24), Vector2(43, 28),
			Vector2(44, 32), Vector2(38, 31), Vector2(34, 36), Vector2(33, 46),
		])
		_outline_poly(pts, Color(0.55, 0.38, 0.24), Color(0.35, 0.24, 0.15))
		draw_circle(Vector2(35.5, 25.5), 1.1, Color(0.12, 0.1, 0.08))
		# Mane strokes
		for k in 4:
			draw_line(Vector2(27 + k, 29 - k * 2), Vector2(24 + k, 33 - k * 2), Color(0.3, 0.2, 0.12), 1.6)

	func _b_fisheries(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var pts := PackedVector2Array([
			Vector2(20, 32), Vector2(28, 25), Vector2(38, 26), Vector2(43, 32),
			Vector2(38, 38), Vector2(28, 39),
		])
		_outline_poly(pts, Color(0.45, 0.6, 0.68), Color(0.28, 0.42, 0.5))
		_outline_poly(PackedVector2Array([Vector2(43, 32), Vector2(49, 26), Vector2(49, 38)]), Color(0.45, 0.6, 0.68), Color(0.28, 0.42, 0.5))
		draw_circle(Vector2(26, 30.5), 1.2, Color(0.12, 0.12, 0.14))
		draw_arc(Vector2(33, 32), 4.5, -0.8, 0.8, 8, Color(0.28, 0.42, 0.5), 1.2)

	func _b_grain_basin(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.8, 0.68, 0.35)
		var outline := Color(0.55, 0.45, 0.22)
		for i in 3:
			var ang := deg_to_rad(-26 + i * 26)
			var dirv := Vector2(sin(ang), -cos(ang))
			var perp := Vector2(-dirv.y, dirv.x)
			var base := Vector2(30 + i * 2, 47)
			var tip := base + dirv * 20.0
			draw_line(base, tip, outline, 2.0)
			# Drooping head: 5 grain dots zigzagging down from the tip
			for k in 5:
				var t := float(k) / 4.0
				var side := 2.2 if k % 2 == 0 else -2.2
				var gp := base.lerp(tip, 0.4 + t * 0.55) + perp * side
				draw_circle(gp, 1.7, fill)

	func _b_vineyards(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.5, 0.3, 0.5)
		var outline := Color(0.32, 0.18, 0.34)
		var top := Vector2(32, 23)
		var rows := [
			[Vector2(-6, 0), Vector2(0, 0), Vector2(6, 0)],
			[Vector2(-3.5, 4.5), Vector2(3.5, 4.5)],
			[Vector2(0, 9)],
			[Vector2(0, 13.5)],
		]
		for row in rows:
			for p in row:
				var gp: Vector2 = top + p
				draw_circle(gp, 2.6, fill)
				draw_arc(gp, 2.6, 0, TAU, 10, outline, 0.8)
		draw_line(Vector2(32, 20), Vector2(32, 15), Color(0.32, 0.4, 0.22), 1.6)
		_outline_poly(_blob(rng, Vector2(32, 13), 5.5, 6, 0.25), Color(0.4, 0.52, 0.3), Color(0.26, 0.34, 0.18))

	func _b_honey_apiaries(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.85, 0.65, 0.25)
		var outline := Color(0.6, 0.44, 0.15)
		var positions := [Vector2(-7, 6), Vector2(7, 6), Vector2(0, -6)]
		for p in positions:
			_outline_poly(_hexagon(Vector2(32, 32) + p, 8.0), fill, outline)

	func _b_herb_meadows(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.42, 0.58, 0.35)
		var outline := Color(0.28, 0.4, 0.22)
		var top := Vector2(32, 18)
		var bottom := Vector2(32, 47)
		draw_line(bottom, top, outline, 2.0)
		for k in 5:
			var t := float(k) / 4.0
			var p := bottom.lerp(top, 0.15 + t * 0.8)
			for side in [-1.0, 1.0]:
				var leaf_tip := p + Vector2(side * (6.0 + t * 2.0), -2.0)
				_outline_poly(PackedVector2Array([
					p, p + Vector2(side * 2.0, -3.0), leaf_tip, p + Vector2(side * 1.5, 1.5),
				]), fill, outline, 1.0)

	func _b_pearl_beds(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var shell := Color(0.7, 0.62, 0.55)
		var outline := Color(0.48, 0.42, 0.36)
		var c := Vector2(32, 38)
		var left_pts := PackedVector2Array([c, c + Vector2(-16, -14), c + Vector2(-9, -18), c + Vector2(-2, -6)])
		var right_pts := PackedVector2Array([c, c + Vector2(2, -6), c + Vector2(9, -18), c + Vector2(16, -14)])
		_outline_poly(left_pts, shell, outline)
		_outline_poly(right_pts, shell, outline)
		for i in 3:
			var t := float(i + 1) / 4.0
			draw_line(c.lerp(c + Vector2(-16, -14), t), c.lerp(c + Vector2(-2, -6), t), outline, 0.8)
			draw_line(c.lerp(c + Vector2(16, -14), t), c.lerp(c + Vector2(2, -6), t), outline, 0.8)
		draw_circle(c + Vector2(0, -9), 4.2, Color(0.9, 0.88, 0.85))
		draw_circle(c + Vector2(-1.2, -10.2), 1.2, Color(1, 1, 1, 0.6))

	func _b_salt_flats(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.88, 0.88, 0.85)
		var outline := Color(0.62, 0.62, 0.6)
		_outline_poly(_diamond(Vector2(25, 37), 8.5), fill, outline)
		_outline_poly(_diamond(Vector2(39, 35), 7.5), fill, outline)
		_outline_poly(_diamond(Vector2(32, 24), 7.0), fill, outline)

	func _b_marble(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.85, 0.84, 0.8)
		var outline := Color(0.6, 0.58, 0.55)
		var pts := PackedVector2Array([Vector2(18, 24), Vector2(46, 20), Vector2(48, 42), Vector2(20, 46)])
		_outline_poly(pts, fill, outline)
		draw_polyline(PackedVector2Array([Vector2(22, 26), Vector2(30, 33), Vector2(27, 40)]), Color(0.65, 0.63, 0.6), 1.3)
		draw_polyline(PackedVector2Array([Vector2(36, 23), Vector2(40, 31), Vector2(38, 40)]), Color(0.65, 0.63, 0.6), 1.3)

	func _b_granite(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.55, 0.55, 0.55)
		var outline := Color(0.38, 0.38, 0.38)
		_outline_poly(PackedVector2Array([Vector2(20, 34), Vector2(42, 32), Vector2(43, 44), Vector2(21, 46)]), fill, outline)
		_outline_poly(PackedVector2Array([Vector2(23, 20), Vector2(41, 19), Vector2(42, 31), Vector2(22, 33)]), fill.lightened(0.08), outline)

	func _b_basalt_columns(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.32, 0.32, 0.36)
		var outline := Color(0.2, 0.2, 0.24)
		var heights := [16.0, 22.0, 12.0]
		for i in 3:
			var x := 21.0 + i * 11.0
			var h: float = heights[i]
			var top_y := 32.0 - h
			var w := 4.5
			var pts := PackedVector2Array([
				Vector2(x, top_y), Vector2(x + w, top_y + 3), Vector2(x + w, 46),
				Vector2(x - w, 46), Vector2(x - w, top_y + 3),
			])
			_outline_poly(pts, fill, outline)

	func _b_copper_vein(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.72, 0.45, 0.3)
		var outline := Color(0.5, 0.3, 0.2)
		var pts := PackedVector2Array([Vector2(20, 42), Vector2(24, 26), Vector2(40, 26), Vector2(44, 42)])
		_outline_poly(pts, fill, outline)
		draw_line(Vector2(25, 34), Vector2(35, 30), Color(0.85, 0.6, 0.42), 2.0)

	func _b_obsidian_flows(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var pts := PackedVector2Array([
			Vector2(24, 46), Vector2(21, 32), Vector2(29, 18), Vector2(35, 24),
			Vector2(44, 20), Vector2(40, 36), Vector2(46, 44), Vector2(30, 40),
		])
		# Lighter violet-grey fill + rim than a literal near-black shard would
		# give — obsidian must still separate from the dark chip at 19px.
		_outline_poly(pts, Color(0.24, 0.2, 0.3), Color(0.45, 0.4, 0.52), 1.8)
		draw_line(Vector2(29, 25), Vector2(34, 35), Color(0.78, 0.78, 0.85), 2.0)

	func _b_titanstone_quarry(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.6, 0.58, 0.52)
		var outline := Color(0.4, 0.38, 0.34)
		_outline_poly(PackedVector2Array([Vector2(18, 30), Vector2(44, 28), Vector2(46, 45), Vector2(19, 47)]), fill, outline)
		_outline_poly(PackedVector2Array([Vector2(30, 22), Vector2(36, 20), Vector2(34, 29), Vector2(28, 29)]), fill.darkened(0.18), outline)

	func _b_timber_giants(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.24, 0.38, 0.24)
		var outline := Color(0.15, 0.26, 0.16)
		draw_line(Vector2(32, 47), Vector2(32, 40), Color(0.4, 0.28, 0.18), 3.0)
		var widths := [12.0, 9.5, 7.0]
		var ys := [40.0, 32.0, 25.0]
		for i in 3:
			var y: float = ys[i]
			var w: float = widths[i]
			_outline_poly(PackedVector2Array([Vector2(32, y - 9), Vector2(32 + w, y), Vector2(32 - w, y)]), fill, outline)

	func _b_amber_groves(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var pts := PackedVector2Array([Vector2(32, 20), Vector2(40, 32), Vector2(37, 44), Vector2(27, 44), Vector2(24, 32)])
		_outline_poly(pts, Color(0.85, 0.6, 0.2), Color(0.6, 0.4, 0.12))
		draw_circle(Vector2(31, 32), 1.6, Color(0.5, 0.32, 0.1))

	func _b_furs(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.55, 0.42, 0.3)
		var outline := Color(0.36, 0.27, 0.18)
		_outline_poly(_blob(rng, Vector2(32, 32), 13.0, 10, 0.2), fill, outline)
		for off in [Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9)]:
			_outline_poly(_blob(rng, Vector2(32, 32) + off, 3.5, 6, 0.2), fill, outline)

	func _b_crystal_springs(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		draw_arc(Vector2(32, 40), 12.0, PI * 0.15, PI * 0.85, 10, Color(0.35, 0.5, 0.62), 3.0)
		var fill := Color(0.6, 0.78, 0.88)
		var outline := Color(0.4, 0.58, 0.7)
		var xs := [24.0, 32.0, 40.0]
		var hs := [12.0, 17.0, 10.0]
		for i in 3:
			var x: float = xs[i]
			var h: float = hs[i]
			_outline_poly(PackedVector2Array([Vector2(x, 39 - h), Vector2(x + 3.2, 39), Vector2(x - 3.2, 39)]), fill, outline)

	func _b_clay_pits(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.62, 0.42, 0.3)
		var outline := Color(0.42, 0.28, 0.2)
		_outline_poly(_blob(rng, Vector2(32, 36), 12.0, 10, 0.15), fill, outline)
		draw_line(Vector2(21, 27), Vector2(43, 27), Color(0.72, 0.52, 0.38), 3.0)
		draw_arc(Vector2(32, 27), 11.0, PI, TAU, 10, outline, 1.2)

	func _b_peat_bogs(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var fill := Color(0.3, 0.24, 0.18)
		var outline := Color(0.18, 0.14, 0.1)
		var rows_y := [42.0, 34.0, 26.0]
		var offsets := [0.0, 6.0, 0.0]
		for i in 3:
			var y: float = rows_y[i]
			var ox: float = offsets[i]
			_outline_poly(PackedVector2Array([
				Vector2(18 + ox, y), Vector2(34 + ox, y), Vector2(34 + ox, y - 7), Vector2(18 + ox, y - 7),
			]), fill, outline)

	func _b_dye_gardens(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var c1 := Color(0.6, 0.3, 0.55)
		var c2 := Color(0.75, 0.35, 0.3)
		_outline_poly(_blob(rng, Vector2(27, 25), 9.5, 8, 0.2), c1, c1.darkened(0.35))
		_outline_poly(_blob(rng, Vector2(37, 39), 9.5, 8, 0.2), c2, c2.darkened(0.35))
		draw_line(Vector2(30, 30), Vector2(34, 34), Color(0.2, 0.1, 0.15, 0.5), 1.2)

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var args := OS.get_cmdline_user_args()
	var mode_arg := args[0] if args.size() > 0 else ""

	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = true  # all modes: painters draw their own opaque chip/base
	root.add_child(_vp)
	_painter = _ResourcePainter.new()
	_vp.add_child(_painter)

	var modes_to_run: Array = ["bounty", "deposit", "landmark"] if mode_arg == "" else [mode_arg]
	for m in modes_to_run:
		var ids: Array = []
		match m:
			"bounty": ids = BOUNTY_IDS
			"deposit": ids = DEPOSIT_IDS
			"landmark": ids = LANDMARK_IDS
		for id in ids:
			_jobs.append([m, id])

	if _jobs.is_empty():
		print("No jobs to run for mode(s): %s (nothing implemented yet for that tier)" % [modes_to_run])
		quit()

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		img.save_png("%s/%s_%s.png" % [OUT_DIR, job[0], String(job[1])])
		_capture_pending = false
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		var m: String = job[0]
		var id: StringName = job[1]
		var sz: int = SIZE_BY_MODE[m]
		_vp.size = Vector2i(sz, sz)
		_painter.mode = m
		_painter.asset_id = id
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d resource-art assets into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
