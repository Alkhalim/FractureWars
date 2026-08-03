extends SceneTree
## UI chrome style-candidate mockup generator — DESIGN EXPLORATION ONLY, not a
## production art tool. Renders one dialog mockup per (direction x faction)
## = 8 images, then composites them into 4 contact sheets (Empire left /
## Skulloath right, direction name banner at top) so the team can pick a
## direction for the real UI overhaul before any production art is built.
## Everything is painted with canvas primitives (draw_circle/draw_colored_
## polygon/draw_polyline/draw_rect/draw_arc) — no external textures — so the
## approved look is provably achievable by a later real generator tool.
##
## Deterministic: rng.seed = hash(direction + "_" + faction), no global RNG,
## no Date/randomize calls. Run WINDOWED (SubViewport capture needs a live
## window; a brief flash is expected):
##   & "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --resolution 1200x800 --path . -s res://tests/tools_ui_style_candidates.gd
##
## Output: assets/ui_style_candidates/style_<direction>.png (committed design
## record) + a copy of each in the scratchpad dir for the coordinator to view.

const OUT_DIR := "res://assets/ui_style_candidates"
const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

const MOCKUP_VP_SIZE := Vector2i(560, 720)
const SHEET_VP_SIZE := Vector2i(1120, 720)

## The 4 style directions under consideration (id must match the _frame_*/
## _button_* dispatch below).
const DIRECTIONS := [
	{id = "gouache", label = "A — PAINTED GOUACHE"},
	{id = "gilded", label = "B — ORNATE GILDED FANTASY"},
	{id = "grimdark", label = "C — DARK ENGRAVED GRIMDARK"},
	{id = "parchment", label = "D — PARCHMENT & INK STRATEGY"},
]

## Contrast pair: Empire (ordered/imperial, color from data/factions/empire.tres)
## vs Skulloath (savage/dark, color from data/factions/skulloath.tres).
const FACTION_IDS := ["empire", "skulloath"]

var _vp: SubViewport
var _painter: _StylePainter
var _jobs: Array = []  # ["mockup", dir_id, faction_id] or ["sheet", dir_id, dir_label]
var _job_idx := -1
var _capture_pending := false
var _mockup_images: Dictionary = {}  # "<dir>_<faction>" -> Image

## ─────────────────────────────────────────────────────────────────────────
## Painter — everything below draws in LOCAL canvas-item space; the outer
## SceneTree script only drives the SubViewport capture loop.
## ─────────────────────────────────────────────────────────────────────────
class _StylePainter extends Node2D:
	var mode := "mockup"
	var direction := ""
	var faction := ""
	var sheet_label := ""
	var sheet_left_tex: ImageTexture
	var sheet_right_tex: ImageTexture

	const CANVAS_SIZE := Vector2(560, 720)
	const SHEET_SIZE := Vector2(1120, 720)
	const FRAME_POS := Vector2(20, 20)
	const FRAME_SIZE := Vector2(520, 680)

	# ── Shared paint helpers (gouache jitter/blob techniques copied verbatim
	# from tools_generate_resource_art.gd / tools_generate_terrain_tiles.gd) ──

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

	func _outline_poly(pts: PackedVector2Array, fill: Color, outline: Color, width := 1.5) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, width)

	## Traces a rect's 4 edges through _wavy_line so straight borders read as
	## hand-painted / hand-inked instead of ruler-straight. Open polygon (no
	## duplicated closing point) — callers close it themselves if needed.
	func _jittered_rect_poly(rng: RandomNumberGenerator, rect: Rect2, segs: int, jitter: float) -> PackedVector2Array:
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		var pts := PackedVector2Array()
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			var seg := _wavy_line(rng, a, b, jitter, segs)
			for j in range(seg.size() - 1):
				pts.append(seg[j])
		return pts

	## Chamfered/rounded rect via corner arcs — used for buttons/chips/bars.
	func _rounded_rect_poly(rect: Rect2, radius: float, segs_per_corner := 6) -> PackedVector2Array:
		var r: float = min(radius, min(rect.size.x * 0.5, rect.size.y * 0.5))
		var corners := [
			{c = rect.position + Vector2(r, r), a0 = PI, a1 = PI * 1.5},
			{c = Vector2(rect.end.x - r, rect.position.y + r), a0 = PI * 1.5, a1 = TAU},
			{c = rect.end - Vector2(r, r), a0 = 0.0, a1 = PI * 0.5},
			{c = Vector2(rect.position.x + r, rect.end.y - r), a0 = PI * 0.5, a1 = PI},
		]
		var pts := PackedVector2Array()
		for cd in corners:
			for i in segs_per_corner + 1:
				var t := float(i) / float(segs_per_corner)
				var ang: float = lerp(float(cd.a0), float(cd.a1), t)
				pts.append(cd.c + Vector2(cos(ang), sin(ang)) * r)
		return pts

	## Seeded noise mottling for leather/stone/parchment fills — scatters
	## small blobs of `dark`/`light` (pass pre-alpha'd colors) inside `rect`.
	func _mottle_fill(rng: RandomNumberGenerator, rect: Rect2, count: int, r_min: float, r_max: float, dark: Color, light: Color) -> void:
		for i in count:
			var cx := rng.randf_range(rect.position.x + r_max, rect.end.x - r_max)
			var cy := rng.randf_range(rect.position.y + r_max, rect.end.y - r_max)
			var r := rng.randf_range(r_min, r_max)
			var col := dark if rng.randf() < 0.55 else light
			draw_colored_polygon(_blob(rng, Vector2(cx, cy), r, 7, 0.4), col)

	func _center_text(text: String, pos: Vector2, width: float, size: int, color: Color) -> void:
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)

	## Faction theming seed — colors read from data/factions/{empire,skulloath}.tres.
	func _faction_palette(fid: String) -> Dictionary:
		match fid:
			"empire":
				return {
					label = "The Empire",
					base = Color(0.25, 0.35, 0.58, 1.0),      # data/factions/empire.tres color
					light = Color(0.42, 0.52, 0.74, 1.0),
					dark = Color(0.10, 0.13, 0.24, 1.0),
					metal = Color(0.80, 0.64, 0.32, 1.0),      # gold/brass
					metal_dark = Color(0.48, 0.36, 0.15, 1.0),
					metal_light = Color(0.95, 0.86, 0.55, 1.0),
					accent = Color(0.55, 0.78, 0.95, 1.0),     # cold blue glow / seal wax
				}
			_:
				return {
					label = "Skulloath Clans",
					base = Color(0.35, 0.10, 0.10, 1.0),       # data/factions/skulloath.tres color
					light = Color(0.55, 0.20, 0.18, 1.0),
					dark = Color(0.14, 0.03, 0.03, 1.0),
					metal = Color(0.62, 0.58, 0.50, 1.0),      # bone
					metal_dark = Color(0.30, 0.28, 0.24, 1.0), # iron
					metal_light = Color(0.85, 0.82, 0.72, 1.0),
					accent = Color(0.85, 0.35, 0.20, 1.0),     # ember glow
				}

	# ── Corner motifs: Empire = laurel/shield, Skulloath = skull/crossbones.
	# Local space: origin (0,0) = the frame's outer corner tip, +x/+y point
	# INWARD; placement mirrors via draw_set_transform for the other 3 corners. ──

	func _motif_gouache_empire(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var metal: Color = pal.metal
		var metal_d: Color = pal.metal_dark
		var shield := PackedVector2Array()
		for p in [Vector2(8, 6), Vector2(28, 4), Vector2(32, 16), Vector2(18, 34), Vector2(4, 16)]:
			shield.append(p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)))
		_outline_poly(shield, Color(pal.base).lightened(0.1), metal_d, 2.5)
		_outline_poly(_blob(rng, Vector2(18, 18), 6.0, 8, 0.3), metal, metal_d, 1.6)
		for side_f in [-1.0, 1.0]:
			var side: float = side_f
			var stem_end := Vector2(18 + side * 22.0, 56.0)
			draw_polyline(_wavy_line(rng, Vector2(18, 30), stem_end, 3.0, 5), metal_d, 2.2)
			for k in 4:
				var t := float(k) / 3.0
				var p2: Vector2 = Vector2(18, 30).lerp(stem_end, 0.3 + t * 0.62)
				_outline_poly(_blob(rng, p2, 4.2, 6, 0.35), metal, metal_d, 1.2)

	func _motif_gouache_skulloath(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var bone: Color = pal.metal
		var bone_d: Color = pal.metal_dark
		for ang_deg in [35.0, -35.0]:
			var ang := deg_to_rad(ang_deg)
			var dirv := Vector2(cos(ang), sin(ang))
			var a := Vector2(20, 26) - dirv * 20.0
			var b := Vector2(20, 26) + dirv * 20.0
			draw_polyline(_wavy_line(rng, a, b, 1.5, 4), bone_d, 6.5)
			draw_polyline(_wavy_line(rng, a, b, 1.5, 4), bone, 4.5)
			draw_circle(a, 4.2, bone)
			draw_circle(b, 4.2, bone)
		_outline_poly(_blob(rng, Vector2(20, 14), 9.0, 9, 0.25), bone, bone_d, 1.6)
		_outline_poly(PackedVector2Array([Vector2(13, 18), Vector2(27, 18), Vector2(23, 28), Vector2(17, 28)]), bone, bone_d, 1.4)
		draw_circle(Vector2(16, 13), 2.0, Color(0.08, 0.06, 0.05))
		draw_circle(Vector2(24, 13), 2.0, Color(0.08, 0.06, 0.05))

	func _motif_gilded_empire(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var metal: Color = pal.metal
		var hi: Color = pal.metal_light
		var sh: Color = pal.metal_dark
		var shield := PackedVector2Array([Vector2(10, 8), Vector2(30, 6), Vector2(34, 18), Vector2(20, 36), Vector2(6, 18)])
		draw_colored_polygon(shield, pal.dark)
		var shc := shield.duplicate()
		shc.append(shield[0])
		draw_polyline(shc, sh, 2.5, true)
		draw_polyline(PackedVector2Array([Vector2(10, 8), Vector2(30, 6), Vector2(34, 18)]), hi, 1.4)
		draw_line(Vector2(20, 10), Vector2(20, 30), metal, 2.0)
		draw_line(Vector2(10, 18), Vector2(30, 18), metal, 2.0)
		for side_f in [-1.0, 1.0]:
			var side: float = side_f
			var pts := PackedVector2Array()
			for i in 18:
				var t := float(i) / 17.0
				var a := t * TAU * 1.5 * side
				var r: float = lerp(4.0, 26.0, t)
				pts.append(Vector2(18, 30) + Vector2(cos(a), sin(a)) * r + Vector2(side * 8.0, 10.0))
			draw_polyline(pts, sh, 3.0, true)
			draw_polyline(pts, metal, 1.6, true)

	func _motif_gilded_skulloath(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var bone: Color = pal.metal
		var hi: Color = pal.metal_light
		var sh: Color = pal.metal_dark
		draw_circle(Vector2(20, 16), 10.0, pal.dark)
		draw_arc(Vector2(20, 16), 10.0, 0.0, TAU, 20, sh, 2.2)
		draw_arc(Vector2(20, 16), 10.0, PI * 1.1, PI * 1.6, 10, hi, 1.4)
		draw_circle(Vector2(16, 15), 1.8, Color(0.05, 0.04, 0.03))
		draw_circle(Vector2(24, 15), 1.8, Color(0.05, 0.04, 0.03))
		for side_f in [-1.0, 1.0]:
			var side: float = side_f
			var pts := PackedVector2Array()
			for i in 16:
				var t := float(i) / 15.0
				var a := t * TAU * 1.3 * side
				var r: float = lerp(3.0, 22.0, t)
				pts.append(Vector2(20, 16) + Vector2(side * 8.0 + cos(a) * r * 0.6, 10.0 + sin(a) * r))
			draw_polyline(pts, sh, 3.2, true)
			draw_polyline(pts, bone, 1.6, true)

	func _motif_grimdark_empire(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var stone_l := Color(0.5, 0.5, 0.55)
		var stone_d := Color(0.16, 0.16, 0.19)
		var rim := Color(0.62, 0.63, 0.68, 0.9)
		var shield := PackedVector2Array([Vector2(9, 4), Vector2(33, 4), Vector2(33, 21), Vector2(21, 38), Vector2(9, 21)])
		draw_colored_polygon(shield, stone_d)
		draw_colored_polygon(PackedVector2Array([Vector2(9, 4), Vector2(33, 4), Vector2(26, 17), Vector2(15, 17)]), stone_l)
		var shc := shield.duplicate()
		shc.append(shield[0])
		draw_polyline(shc, rim, 2.0, true)
		draw_polyline(shc, Color(0, 0, 0, 0.9), 1.0, true)
		var glow: Color = pal.accent
		var rune := PackedVector2Array([Vector2(2, 48), Vector2(16, 56), Vector2(10, 62), Vector2(24, 72), Vector2(18, 62), Vector2(32, 54)])
		draw_polyline(rune, Color(glow.r, glow.g, glow.b, 0.45), 9.0)
		draw_polyline(rune, Color(glow.r, glow.g, glow.b, 0.7), 4.5)
		draw_polyline(rune, Color(1, 1, 1, 0.8).lerp(glow, 0.4), 1.6)
		draw_circle(Vector2(2, 48), 2.4, glow)
		draw_circle(Vector2(24, 72), 2.4, glow)

	func _motif_grimdark_skulloath(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var stone_l := Color(0.5, 0.47, 0.44)
		var stone_d := Color(0.16, 0.14, 0.13)
		var rim := Color(0.6, 0.56, 0.5, 0.9)
		var skull := _blob(rng, Vector2(19, 17), 12.0, 8, 0.2)
		draw_colored_polygon(skull, stone_d)
		var skull_c := skull.duplicate()
		skull_c.append(skull[0])
		draw_polyline(skull_c, rim, 1.8, true)
		draw_colored_polygon(_blob(rng, Vector2(15, 13), 6.5, 6, 0.2), stone_l)
		draw_colored_polygon(PackedVector2Array([Vector2(10, 22), Vector2(28, 22), Vector2(23, 34), Vector2(15, 34)]), stone_d)
		var glow: Color = pal.accent
		draw_circle(Vector2(14, 16), 2.2, glow)
		draw_circle(Vector2(23, 16), 2.2, glow)
		var rune := PackedVector2Array([Vector2(2, 50), Vector2(18, 58), Vector2(10, 66), Vector2(28, 74)])
		draw_polyline(rune, Color(glow.r, glow.g, glow.b, 0.45), 9.0)
		draw_polyline(rune, Color(glow.r, glow.g, glow.b, 0.7), 4.5)
		draw_polyline(rune, Color(1, 1, 1, 0.8).lerp(glow, 0.4), 1.6)
		draw_circle(Vector2(2, 50), 2.4, glow)
		draw_circle(Vector2(28, 74), 2.4, glow)

	func _offset_poly(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(p + off)
		return out

	func _motif_parchment_empire(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var wax: Color = pal.base
		var wax_d: Color = pal.dark
		var c := Vector2(22, 24)
		draw_circle(c, 18.0, wax)
		draw_arc(c, 18.0, 0.0, TAU, 24, wax_d, 1.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 16), c + Vector2(4, 16), c + Vector2(1, 25), c + Vector2(-1, 25)]), wax)
		var emblem := PackedVector2Array([c + Vector2(-8, -10), c + Vector2(8, -10), c + Vector2(8, 2), c + Vector2(0, 12), c + Vector2(-8, 2)])
		var emblem_closed := emblem.duplicate()
		emblem_closed.append(emblem[0])
		draw_polyline(_offset_poly(emblem_closed, Vector2(-0.8, -0.8)), Color(wax).lightened(0.3), 1.3, true)
		draw_polyline(_offset_poly(emblem_closed, Vector2(0.8, 0.8)), wax_d, 1.3, true)
		draw_line(c + Vector2(0, -8), c + Vector2(0, 6), wax_d, 1.2)
		draw_line(c + Vector2(-6, -2), c + Vector2(6, -2), wax_d, 1.2)

	func _motif_parchment_skulloath(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var wax: Color = pal.base
		var wax_d: Color = pal.dark
		var c := Vector2(22, 24)
		draw_circle(c, 18.0, wax)
		draw_arc(c, 18.0, 0.0, TAU, 24, wax_d, 1.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 16), c + Vector2(4, 16), c + Vector2(1, 25), c + Vector2(-1, 25)]), wax)
		draw_arc(c + Vector2(-0.8, -2.8), 7.0, PI, TAU, 10, Color(wax).lightened(0.3), 1.3)
		draw_arc(c + Vector2(0.8, -2.2), 7.0, PI, TAU, 10, wax_d, 1.3)
		draw_line(c + Vector2(-5, 3), c + Vector2(5, 3), wax_d, 1.2)
		draw_circle(c + Vector2(-3, -3), 1.3, wax_d)
		draw_circle(c + Vector2(3, -3), 1.3, wax_d)

	func _paint_corner_motif(direction: String, faction: String, rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var is_empire := faction == "empire"
		match direction:
			"gouache":
				if is_empire: _motif_gouache_empire(rng, pal)
				else: _motif_gouache_skulloath(rng, pal)
			"gilded":
				if is_empire: _motif_gilded_empire(rng, pal)
				else: _motif_gilded_skulloath(rng, pal)
			"grimdark":
				if is_empire: _motif_grimdark_empire(rng, pal)
				else: _motif_grimdark_skulloath(rng, pal)
			"parchment":
				if is_empire: _motif_parchment_empire(rng, pal)
				else: _motif_parchment_skulloath(rng, pal)

	## Places the motif at all 4 corners, pushed below the title bar on top
	## (inset_top) so it never collides with the title text or the button
	## stack below it.
	func _draw_corner_motifs(direction: String, faction: String, rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		var inset_x := 8.0
		var inset_top := 78.0
		var inset_bottom := 8.0
		var positions := [
			[frame.position + Vector2(inset_x, inset_top), 1.0, 1.0],
			[Vector2(frame.end.x - inset_x, frame.position.y + inset_top), -1.0, 1.0],
			[Vector2(frame.position.x + inset_x, frame.end.y - inset_bottom), 1.0, -1.0],
			[frame.end - Vector2(inset_x, inset_bottom), -1.0, -1.0],
		]
		for p in positions:
			var pos: Vector2 = p[0]
			var sx: float = p[1]
			var sy: float = p[2]
			draw_set_transform(pos, 0.0, Vector2(sx, sy))
			_paint_corner_motif(direction, faction, rng, pal)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ── Direction A: Painted gouache — boardgame-gouache identity ──────────

	func _frame_gouache(rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.16, 0.15, 0.13))
		var canvas_tone: Color = Color(0.86, 0.79, 0.65).lerp(pal.base, 0.16)
		draw_colored_polygon(_jittered_rect_poly(rng, frame, 5, 2.5), canvas_tone)
		_mottle_fill(rng, frame, 70, 6.0, 22.0, Color(0, 0, 0, 0.035), Color(1, 1, 1, 0.035))
		# Layered painted border: strokes drawn INSET (not outset) so each
		# translucent ring sits on top of the light canvas_tone fill and is
		# actually visible, instead of vanishing over the near-black backdrop.
		for i in range(4):
			var shrink := 2.0 + float(i) * 3.0
			var r2 := frame.grow(-shrink)
			var a := 0.16 + float(i) * 0.07
			var poly := _jittered_rect_poly(rng, r2, 5, 3.0)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, Color(Color(pal.dark).r, Color(pal.dark).g, Color(pal.dark).b, a), 2.4, true)
		var inner := frame.grow(-8.0)
		var inner_poly := _jittered_rect_poly(rng, inner, 5, 1.5)
		var inner_closed := inner_poly.duplicate()
		inner_closed.append(inner_poly[0])
		draw_polyline(inner_closed, pal.metal_dark, 1.8, true)
		var title_rect := Rect2(frame.position + Vector2(14, 12), Vector2(frame.size.x - 28.0, 56.0))
		var title_poly := _jittered_rect_poly(rng, title_rect, 5, 2.0)
		draw_colored_polygon(title_poly, Color(pal.base).darkened(0.12))
		var title_closed := title_poly.duplicate()
		title_closed.append(title_poly[0])
		draw_polyline(title_closed, pal.metal_dark, 2.0, true)
		_center_text(pal.label, Vector2(title_rect.position.x, title_rect.position.y + title_rect.size.y * 0.5 + 7.0), title_rect.size.x, 20, pal.metal_light)

	func _button_gouache(rect: Rect2, state: String, pal: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
		var r := rect
		var fill: Color = Color(pal.base).lightened(0.05)
		var outline: Color = pal.dark
		var text_col: Color = pal.metal_light
		match state:
			"hover":
				fill = Color(pal.base).lightened(0.22)
				text_col = Color(1, 1, 0.9)
			"pressed":
				fill = Color(pal.base).darkened(0.18)
				r.position.y += 2.0
				text_col = Color(pal.metal).darkened(0.1)
			"disabled":
				fill = Color(pal.base).darkened(0.1)
				fill.a = 0.55
				outline.a = 0.5
				text_col = Color(0.6, 0.58, 0.55, 0.7)
		if state == "hover":
			draw_colored_polygon(_rounded_rect_poly(r.grow(3.0), 11.0), Color(Color(pal.metal).r, Color(pal.metal).g, Color(pal.metal).b, 0.25))
		_outline_poly(_rounded_rect_poly(r, 9.0), fill, outline, 2.2)
		for i in 5:
			var p := Vector2(rng.randf_range(r.position.x + 10.0, r.end.x - 10.0), rng.randf_range(r.position.y + 6.0, r.end.y - 6.0))
			draw_circle(p, 1.2, Color(1, 1, 1, 0.05))
		_center_text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), r.size.x, 15, text_col)

	func _chip_common(rect: Rect2, direction: String, pal: Dictionary, rng: RandomNumberGenerator) -> void:
		var bg := Color(0.05, 0.04, 0.03, 0.78)
		draw_colored_polygon(_rounded_rect_poly(rect, 6.0), bg)
		match direction:
			"gouache":
				var p := _jittered_rect_poly(rng, rect, 5, 1.6)
				var pc := p.duplicate()
				pc.append(p[0])
				draw_polyline(pc, Color(Color(pal.metal).r, Color(pal.metal).g, Color(pal.metal).b, 0.5), 1.4, true)
			"gilded":
				draw_rect(rect, pal.metal, false, 1.2)
			"grimdark":
				draw_rect(rect, Color(Color(pal.accent).r, Color(pal.accent).g, Color(pal.accent).b, 0.5), false, 1.2)
			"parchment":
				var p2 := _jittered_rect_poly(rng, rect, 5, 1.2)
				var pc2 := p2.duplicate()
				pc2.append(p2[0])
				draw_polyline(pc2, Color(0.7, 0.6, 0.4, 0.6), 1.0, true)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 32), "This chip shows two lines of sample body", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 13, Color(0.92, 0.9, 0.85))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, 54), "text over a dark, readable background.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 13, Color(0.92, 0.9, 0.85))

	func _progress_common(rect: Rect2, direction: String, pal: Dictionary, rng: RandomNumberGenerator) -> void:
		var pct := 0.62
		draw_colored_polygon(_rounded_rect_poly(rect, 6.0), Color(0.08, 0.07, 0.07, 0.85))
		var fill_rect := Rect2(rect.position, Vector2(rect.size.x * pct, rect.size.y))
		match direction:
			"gouache":
				draw_colored_polygon(_rounded_rect_poly(fill_rect, 6.0), Color(pal.base).lightened(0.15))
				draw_rect(rect, pal.metal_dark, false, 1.6)
			"gilded":
				draw_colored_polygon(_rounded_rect_poly(fill_rect, 4.0), pal.metal)
				draw_rect(Rect2(rect.position, Vector2(fill_rect.size.x, fill_rect.size.y * 0.4)), pal.metal_light)
				draw_rect(rect, pal.metal_dark, false, 1.6)
			"grimdark":
				var accent: Color = pal.accent
				draw_colored_polygon(_rounded_rect_poly(fill_rect, 2.0), accent.darkened(0.1))
				draw_rect(fill_rect, Color(accent.r, accent.g, accent.b, 0.5), false, 3.0)
				draw_rect(rect, Color(0.02, 0.02, 0.03), false, 2.0)
			"parchment":
				draw_colored_polygon(_rounded_rect_poly(fill_rect, 2.0), Color(pal.base).lerp(Color(0.85, 0.78, 0.6), 0.25))
				var steps := int(fill_rect.size.x / 6.0)
				for i in steps:
					var x := fill_rect.position.x + float(i) * 6.0
					draw_line(Vector2(x, rect.position.y + 2.0), Vector2(x - 5.0, rect.end.y - 2.0), Color(0.18, 0.12, 0.06, 0.35), 1.0)
				draw_rect(rect, Color(0.18, 0.12, 0.06), false, 1.2)

	func _divider_common(y: float, x0: float, x1: float, direction: String, pal: Dictionary, rng: RandomNumberGenerator) -> void:
		var mid := (x0 + x1) * 0.5
		match direction:
			"gouache":
				draw_polyline(_wavy_line(rng, Vector2(x0, y), Vector2(x1, y), 1.6, 8), pal.metal_dark, 2.0)
			"gilded":
				draw_line(Vector2(x0, y), Vector2(x1, y), pal.metal, 1.6)
				draw_circle(Vector2(mid, y), 3.0, pal.metal_light)
				draw_arc(Vector2(mid, y), 3.0, 0.0, TAU, 10, pal.metal_dark, 1.0)
			"grimdark":
				draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.03, 0.03, 0.04), 3.0)
				draw_line(Vector2(mid - 14.0, y), Vector2(mid + 14.0, y), pal.accent, 1.4)
			"parchment":
				draw_polyline(_wavy_line(rng, Vector2(x0, y), Vector2(x1, y), 1.0, 10), Color(0.18, 0.12, 0.06), 1.2)
				draw_circle(Vector2(mid, y), 2.2, pal.base)

	# ── Direction B: Ornate gilded fantasy ──────────────────────────────────

	func _frame_gilded(rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.05, 0.045, 0.06))
		var border_w := 16.0
		var block := Rect2(frame.position - Vector2(border_w, border_w), frame.size + Vector2(border_w * 2.0, border_w * 2.0))
		draw_rect(block, pal.metal_dark)
		draw_rect(block.grow(-2.0), pal.metal, false, 2.0)
		draw_rect(block.grow(-5.0), pal.metal_light, false, 1.6)
		draw_rect(frame.grow(2.0), pal.dark, false, 2.2)
		draw_rect(frame.grow(5.0), Color(pal.metal_dark).darkened(0.3), false, 1.4)
		var leather: Color = Color(0.14, 0.09, 0.07).lerp(pal.dark, 0.35)
		draw_rect(frame, leather)
		_mottle_fill(rng, frame, 100, 4.0, 15.0, Color(0, 0, 0, 0.12), Color(min(leather.r + 0.1, 1.0), min(leather.g + 0.08, 1.0), min(leather.b + 0.06, 1.0), 0.10))
		draw_rect(frame, pal.metal, false, 1.6)
		var title_rect := Rect2(frame.position + Vector2(10, 10), Vector2(frame.size.x - 20.0, 54.0))
		draw_rect(title_rect, Color(pal.dark).lerp(Color.BLACK, 0.3))
		draw_rect(title_rect, pal.metal, false, 1.6)
		draw_rect(title_rect.grow(-3.0), pal.metal_dark, false, 1.0)
		_center_text(pal.label, Vector2(title_rect.position.x, title_rect.position.y + title_rect.size.y * 0.5 + 7.0), title_rect.size.x, 20, pal.metal_light)

	func _button_gilded(rect: Rect2, state: String, pal: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
		var r := rect
		var top_col: Color = pal.metal_light
		var bot_col: Color = pal.metal_dark
		var text_col: Color = pal.metal_light
		match state:
			"hover":
				top_col = Color(pal.metal_light).lightened(0.15)
				text_col = Color(1, 0.98, 0.85)
			"pressed":
				top_col = pal.metal_dark
				bot_col = pal.metal_light
				r.position.y += 2.0
				text_col = Color(0.16, 0.1, 0.03)
			"disabled":
				top_col = Color(pal.metal_dark).darkened(0.2)
				top_col.a = 0.55
				bot_col = Color(pal.metal_dark).darkened(0.3)
				bot_col.a = 0.55
				text_col = Color(0.55, 0.52, 0.45, 0.6)
		draw_rect(r, pal.metal)
		var band_h := r.size.y / 3.0
		draw_rect(Rect2(r.position, Vector2(r.size.x, band_h)), top_col)
		draw_rect(Rect2(r.position + Vector2(0, band_h * 2.0), Vector2(r.size.x, band_h)), bot_col)
		draw_rect(r, pal.dark, false, 1.6)
		draw_rect(r.grow(-2.0), (pal.metal_light if state != "pressed" else pal.metal_dark), false, 1.0)
		if state == "hover":
			draw_rect(r.grow(2.0), Color(Color(pal.metal_light).r, Color(pal.metal_light).g, Color(pal.metal_light).b, 0.5), false, 1.4)
		_center_text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), r.size.x, 15, text_col)

	# ── Direction C: Dark engraved grimdark ─────────────────────────────────

	func _frame_grimdark(rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.02, 0.02, 0.025))
		var border_w := 20.0
		var block := Rect2(frame.position - Vector2(border_w, border_w), frame.size + Vector2(border_w * 2.0, border_w * 2.0))
		draw_rect(block, Color(0.05, 0.05, 0.06))
		draw_rect(block.grow(-3.0), Color(0.16, 0.16, 0.19), false, 2.5)
		draw_rect(frame.grow(3.0), Color(0.0, 0.0, 0.0, 0.9), false, 3.0)
		var accent: Color = pal.accent
		draw_rect(frame.grow(9.0), Color(accent.r, accent.g, accent.b, 0.4), false, 1.2)
		var stone: Color = Color(0.13, 0.12, 0.13)
		draw_rect(frame, stone)
		_mottle_fill(rng, frame, 110, 3.0, 14.0, Color(0, 0, 0, 0.18), Color(0.3, 0.3, 0.32, 0.12))
		# Chisel crack lines — confined to the empty lower-middle stretch of
		# the panel (below the disabled button, between the corner runes) so
		# they read as stone texture instead of a stray line through the UI.
		for i in 2:
			var x0 := frame.position.x + rng.randf_range(150.0, 230.0)
			var y0 := frame.position.y + rng.randf_range(600.0, 650.0)
			var pts := PackedVector2Array([
				Vector2(x0, y0), Vector2(x0 + rng.randf_range(60.0, 100.0), y0 + rng.randf_range(-10.0, 10.0)),
				Vector2(x0 + rng.randf_range(120.0, 170.0), y0 + rng.randf_range(-8.0, 8.0)),
			])
			draw_polyline(pts, Color(0, 0, 0, 0.4), 1.2)
		draw_rect(frame, Color(0.03, 0.03, 0.03), false, 1.5)
		var title_rect := Rect2(frame.position + Vector2(10, 10), Vector2(frame.size.x - 20.0, 54.0))
		draw_rect(title_rect, Color(0.04, 0.04, 0.05))
		draw_rect(title_rect, Color(0.14, 0.14, 0.16), false, 1.6)
		draw_rect(title_rect.grow(2.0), Color(accent.r, accent.g, accent.b, 0.5), false, 3.5)
		draw_rect(title_rect, accent, false, 1.0)
		_center_text(pal.label, Vector2(title_rect.position.x, title_rect.position.y + title_rect.size.y * 0.5 + 7.0), title_rect.size.x, 20, Color(0.9, 0.92, 0.95))

	func _button_grimdark(rect: Rect2, state: String, pal: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
		var r := rect
		var accent: Color = pal.accent
		var glow_a := 0.9
		var text_col := Color(0.85, 0.86, 0.88)
		match state:
			"hover":
				glow_a = 1.0
				text_col = Color(0.95, 0.96, 1.0)
			"pressed":
				r.position.y += 2.0
				glow_a = 0.5
				text_col = Color(0.7, 0.71, 0.74)
			"disabled":
				glow_a = 0.0
				text_col = Color(0.45, 0.45, 0.47, 0.6)
		draw_rect(r, Color(0.07, 0.07, 0.08))
		draw_rect(r, Color(0.02, 0.02, 0.03), false, 2.5)
		draw_rect(r.grow(-3.0), Color(0.18, 0.18, 0.2), false, 1.0)
		if glow_a > 0.0:
			var from_p := Vector2(r.position.x + 10.0, r.end.y - 6.0)
			var to_p := Vector2(r.end.x - 10.0, r.end.y - 6.0)
			draw_line(from_p, to_p, Color(accent.r, accent.g, accent.b, 0.35 * glow_a), 4.0)
			draw_line(from_p, to_p, Color(accent.r, accent.g, accent.b, glow_a), 1.4)
		_center_text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), r.size.x, 15, text_col)

	# ── Direction D: Parchment & ink strategy ───────────────────────────────

	func _frame_parchment(rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.24, 0.20, 0.15))
		var paper: Color = Color(0.87, 0.79, 0.6)
		draw_rect(frame, paper)
		for i in 10:
			var cx := rng.randf_range(frame.position.x + 20.0, frame.end.x - 20.0)
			var cy := rng.randf_range(frame.position.y + 20.0, frame.end.y - 20.0)
			var r := rng.randf_range(14.0, 46.0)
			draw_colored_polygon(_blob(rng, Vector2(cx, cy), r, 8, 0.35), Color(0.55, 0.42, 0.24, 0.06))
		var outer_poly := _jittered_rect_poly(rng, frame, 6, 1.6)
		var outer_closed := outer_poly.duplicate()
		outer_closed.append(outer_poly[0])
		draw_polyline(outer_closed, Color(0.18, 0.12, 0.06), 1.6, true)
		var inner_rect := frame.grow(-7.0)
		var inner_poly := _jittered_rect_poly(rng, inner_rect, 6, 1.4)
		var inner_closed := inner_poly.duplicate()
		inner_closed.append(inner_poly[0])
		draw_polyline(inner_closed, Color(0.18, 0.12, 0.06), 1.0, true)
		var mid_rect := frame.grow(-3.5)
		var mid_poly := _jittered_rect_poly(rng, mid_rect, 6, 1.2)
		var mid_closed := mid_poly.duplicate()
		mid_closed.append(mid_poly[0])
		draw_polyline(mid_closed, Color(Color(pal.base).r, Color(pal.base).g, Color(pal.base).b, 0.55), 1.2, true)
		var title_rect := Rect2(frame.position + Vector2(14, 14), Vector2(frame.size.x - 28.0, 50.0))
		_center_text(String(pal.label).to_upper(), Vector2(title_rect.position.x, title_rect.position.y + 30.0), title_rect.size.x, 20, Color(0.16, 0.11, 0.06))
		var uy := title_rect.position.y + 40.0
		draw_polyline(_wavy_line(rng, Vector2(title_rect.position.x + 40.0, uy), Vector2(title_rect.end.x - 40.0, uy), 1.2, 8), Color(0.16, 0.11, 0.06), 1.4)

	func _button_parchment(rect: Rect2, state: String, pal: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
		var r := rect
		var ink: Color = Color(0.18, 0.12, 0.06)
		var fill: Color = Color(0.91, 0.85, 0.7)
		var text_col: Color = ink
		match state:
			"hover":
				fill = Color(0.95, 0.9, 0.76)
			"pressed":
				fill = Color(pal.base).lerp(Color(0.2, 0.15, 0.08), 0.3)
				text_col = Color(0.95, 0.9, 0.8)
				r.position.y += 1.0
			"disabled":
				fill = Color(0.82, 0.78, 0.68, 0.55)
				ink.a = 0.45
				text_col = ink
		draw_colored_polygon(_rounded_rect_poly(r, 4.0), fill)
		var wobble := _jittered_rect_poly(rng, r, 4, 1.0)
		var wobble_closed := wobble.duplicate()
		wobble_closed.append(wobble[0])
		draw_polyline(wobble_closed, ink, 1.4, true)
		if state == "hover" or state == "pressed":
			draw_polyline(wobble_closed, Color(Color(pal.base).r, Color(pal.base).g, Color(pal.base).b, 0.7), 1.0, true)
		_center_text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), r.size.x, 15, text_col)

	# ── Dispatch + layout ────────────────────────────────────────────────────

	func _draw_frame(direction: String, rng: RandomNumberGenerator, frame: Rect2, pal: Dictionary) -> void:
		match direction:
			"gouache": _frame_gouache(rng, frame, pal)
			"gilded": _frame_gilded(rng, frame, pal)
			"grimdark": _frame_grimdark(rng, frame, pal)
			"parchment": _frame_parchment(rng, frame, pal)

	func _draw_button(direction: String, rect: Rect2, state: String, pal: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
		match direction:
			"gouache": _button_gouache(rect, state, pal, rng, label)
			"gilded": _button_gilded(rect, state, pal, rng, label)
			"grimdark": _button_grimdark(rect, state, pal, rng, label)
			"parchment": _button_parchment(rect, state, pal, rng, label)

	## Full 560x720 dialog mockup: frame + corner motifs, title, 3-state
	## button stack, text chip, progress bar, divider, disabled button.
	func _paint_mockup(rng: RandomNumberGenerator, direction: String, faction: String) -> void:
		var pal := _faction_palette(faction)
		var frame := Rect2(FRAME_POS, FRAME_SIZE)
		_draw_frame(direction, rng, frame, pal)
		_draw_corner_motifs(direction, faction, rng, frame, pal)

		var content_x0 := frame.position.x + 30.0
		var content_w := frame.size.x - 60.0
		var by := frame.position.y + 96.0
		var btn_h := 44.0
		var states := ["normal", "hover", "pressed"]
		var btn_labels := ["Normal", "Hover", "Pressed"]
		for i in 3:
			var rect := Rect2(content_x0 + (content_w - 200.0) * 0.5, by, 200.0, btn_h)
			_draw_button(direction, rect, states[i], pal, rng, btn_labels[i])
			by += btn_h + 14.0

		by += 20.0
		var chip_rect := Rect2(content_x0, by, content_w, 88.0)
		_chip_common(chip_rect, direction, pal, rng)
		by += 88.0 + 24.0

		var prog_rect := Rect2(content_x0, by, content_w, 20.0)
		_progress_common(prog_rect, direction, pal, rng)
		by += 20.0 + 22.0

		_divider_common(by, content_x0, content_x0 + content_w, direction, pal, rng)
		by += 26.0

		var disabled_rect := Rect2(content_x0 + (content_w - 200.0) * 0.5, by, 200.0, 36.0)
		_draw_button(direction, disabled_rect, "disabled", pal, rng, "Disabled")

	## Composites the two per-faction mockups into one labeled contact sheet.
	func _paint_sheet(direction_label: String, left_tex: ImageTexture, right_tex: ImageTexture) -> void:
		draw_texture(left_tex, Vector2(0, 0))
		draw_texture(right_tex, Vector2(560, 0))
		draw_line(Vector2(560, 0), Vector2(560, SHEET_SIZE.y), Color(0, 0, 0, 0.6), 2.0)
		draw_rect(Rect2(0, 0, SHEET_SIZE.x, 30.0), Color(0.03, 0.03, 0.03, 0.85))
		_center_text(direction_label, Vector2(0, 21), SHEET_SIZE.x, 18, Color(0.95, 0.9, 0.75))

	func _draw() -> void:
		match mode:
			"mockup":
				if direction == "" or faction == "":
					return
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(direction + "_" + faction)
				_paint_mockup(rng, direction, faction)
			"sheet":
				if sheet_left_tex == null or sheet_right_tex == null:
					return
				_paint_sheet(sheet_label, sheet_left_tex, sheet_right_tex)
			_:
				pass

## ─────────────────────────────────────────────────────────────────────────
## SceneTree driver — capture loop modeled on tools_generate_resource_art.gd.
## ─────────────────────────────────────────────────────────────────────────

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = false
	root.add_child(_vp)
	_painter = _StylePainter.new()
	_vp.add_child(_painter)

	for d in DIRECTIONS:
		for f in FACTION_IDS:
			_jobs.append(["mockup", d.id, f])
	for d in DIRECTIONS:
		_jobs.append(["sheet", d.id, d.label])

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		if job[0] == "mockup":
			_mockup_images["%s_%s" % [job[1], job[2]]] = img
		else:
			var out_name := "style_%s.png" % job[1]
			img.save_png("%s/%s" % [OUT_DIR, out_name])
			img.save_png("%s/%s" % [SCRATCH_DIR, out_name])
			print("Saved contact sheet: %s" % out_name)
		_capture_pending = false
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		if job[0] == "mockup":
			_vp.size = MOCKUP_VP_SIZE
			_painter.mode = "mockup"
			_painter.direction = job[1]
			_painter.faction = job[2]
		else:
			_vp.size = SHEET_VP_SIZE
			_painter.mode = "sheet"
			_painter.sheet_label = job[2]
			var left_img: Image = _mockup_images["%s_empire" % job[1]]
			var right_img: Image = _mockup_images["%s_skulloath" % job[1]]
			_painter.sheet_left_tex = ImageTexture.create_from_image(left_img)
			_painter.sheet_right_tex = ImageTexture.create_from_image(right_img)
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d UI style-candidate images into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
