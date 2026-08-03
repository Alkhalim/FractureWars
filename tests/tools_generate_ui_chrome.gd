extends SceneTree
## Parchment & Ink UI chrome generator — bakes the production nine-patch
## chrome (frame/buttons/notification) for each faction "set", replacing the
## stock PNG chrome (button1.png, frame1.png, notification1.png). Style
## direction D — parchment & ink — approved in assets/ui_style_candidates/
## (see tests/tools_ui_style_candidates.gd for the mockup that established
## the look; this tool ports those painters into a real nine-patch-safe bake).
##
## Deterministic: rng.seed = hash(set_id + "_" + piece), no global RNG, no
## Date/randomize calls. Run WINDOWED (SubViewport capture needs a live
## window; a brief flash is expected):
##   & "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --resolution 1200x800 --path . -s res://tests/tools_generate_ui_chrome.gd
## Optional trailing arg selects one set to (re)bake; omit for all sets:
##   & <godot> --resolution 1200x800 --path . -s res://tests/tools_generate_ui_chrome.gd -- neutral
## Then run a headless import pass so the editor asset DB picks up the PNGs:
##   & <godot> --headless --path . --import
##
## Output: assets/sprites/ui/generated/<set_id>_{frame,btn_normal,btn_hover,
## btn_pressed,btn_disabled,notification}.png plus a per-set contact sheet
## assets/sprites/ui/generated/_contact_<set_id>.png (also copied to the
## session scratchpad) proving all 6 pieces plus a 400x260 nine-patch-
## stretched sample of the frame piece via a real StyleBoxTexture draw.

const OUT_DIR := "res://assets/sprites/ui/generated"
const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

## ─────────────────────────────────────────────────────────────────────────
## Geometry CONTRACT — Task 3 of the UI-overhaul plan copies these verbatim
## into game_manager.gd's StyleBoxTexture factories. Corner/top-center seals
## must live entirely inside the margin bands below so nine-patch stretching
## never distorts them.
## ─────────────────────────────────────────────────────────────────────────
const FRAME_SIZE := Vector2i(192, 192)       # frame nine-patch canvas
const FRAME_MARGIN := 24                     # nine-patch texture margin, all 4 sides (corner seals live inside this band)
const BTN_SIZE := Vector2i(96, 48)           # button nine-patch canvas
const BTN_MARGIN := 12                       # button nine-patch margin
const NOTIF_SIZE := Vector2i(224, 224)
const NOTIF_MARGIN := 32

const PIECES := ["frame", "btn_normal", "btn_hover", "btn_pressed", "btn_disabled", "notification"]

const CONTACT_VP_SIZE := Vector2i(940, 380)
const STRETCH_SAMPLE_SIZE := Vector2(400.0, 260.0)

## Per-set palette table — data, not code branches (Task 2 appends the 11
## faction rows here; painters below stay unchanged and read only these
## fields). Keep in sync with scripts/ui/ui_palette.gd (Task 3): that file
## duplicates these values for runtime color decisions; this table is
## tool-side and bakes pixels.
const SETS := {
	&"neutral": {
		parchment = Color(0.85, 0.79, 0.66),
		parchment_dark = Color(0.24, 0.21, 0.17),
		ink = Color(0.16, 0.13, 0.10),
		heraldry = Color(0.62, 0.52, 0.30),
		seal = Color(0.40, 0.32, 0.16),
		motif = &"quill",
	},
}

var _vp: SubViewport
var _painter: _ChromePainter
var _jobs: Array = []  # ["bake", set_id, piece] or ["contact", set_id, ""]
var _job_idx := -1
var _capture_pending := false
var _images: Dictionary = {}  # "<set_id>_<piece>" -> Image

## ─────────────────────────────────────────────────────────────────────────
## Painter — everything below draws in LOCAL canvas-item space; the outer
## SceneTree script only drives the SubViewport capture loop (mechanics
## copied from tests/tools_generate_resource_art.gd).
## ─────────────────────────────────────────────────────────────────────────
class _ChromePainter extends Node2D:
	var set_id: StringName = &""
	var piece := ""
	var contact_mode := false
	var contact_set_id: StringName = &""
	var contact_textures: Dictionary = {}  # piece -> Texture2D, pre-built by the driver (see note on _paint_contact_sheet)

	# ── Shared paint helpers, copied from tools_ui_style_candidates.gd ──────

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

	## Traces a rect's 4 edges through _wavy_line so straight borders read as
	## hand-inked instead of ruler-straight. Open polygon (no duplicated
	## closing point) — callers close it themselves if needed.
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

	## Chamfered/rounded rect via corner arcs — used for button fills.
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

	func _rotate_poly(pts: PackedVector2Array, angle: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(p.rotated(angle))
		return out

	## Seeded stain blotches for the parchment field — scatters translucent
	## blobs of `tint` inside `rect`, kept clear of the very edge.
	func _paint_stains(rng: RandomNumberGenerator, rect: Rect2, count: int, tint: Color) -> void:
		var max_r: float = min(rect.size.x, rect.size.y) * 0.16
		for i in count:
			var cx := rng.randf_range(rect.position.x + max_r, rect.end.x - max_r)
			var cy := rng.randf_range(rect.position.y + max_r, rect.end.y - max_r)
			var r := rng.randf_range(max_r * 0.4, max_r)
			draw_colored_polygon(_blob(rng, Vector2(cx, cy), r, 8, 0.35), tint)

	## One or more nested hand-inked wobble lines, each `insets[i]` px inside
	## `rect` at stroke width `widths[i]` — the frame's signature double-line
	## border (and, doubled up, the notification's ornate variant).
	func _paint_wobble_border(rng: RandomNumberGenerator, rect: Rect2, insets: Array, widths: Array, color: Color) -> void:
		for i in insets.size():
			var r2: Rect2 = rect.grow(-float(insets[i]))
			var poly := _jittered_rect_poly(rng, r2, 6, 1.0)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, color, float(widths[i]), true)

	# ── Motifs — drawn at an explicit absolute center + radius budget so the
	# same function serves tiny corner seals and the larger notification
	# seal. `mirror` (±1,±1) reflects the motif for the 3 non-origin corners
	# WITHOUT touching draw_set_transform (which is a single absolute state,
	# not a stack — nesting it with the caller's own transform would clobber
	# it), so every coordinate below is computed in absolute space. ──

	func _motif_quill(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var quill_col: Color = Color(pal.heraldry).lightened(0.12)
		var l := r * 0.95
		var w := r * 0.32
		var base := PackedVector2Array([
			Vector2(l, 0.0), Vector2(l * 0.45, w), Vector2(-l * 0.35, w * 0.55),
			Vector2(-l * 0.55, 0.0), Vector2(-l * 0.35, -w * 0.55), Vector2(l * 0.45, -w),
		])
		for ang in [deg_to_rad(40.0), deg_to_rad(-40.0)]:
			var rotated := _rotate_poly(base, ang)
			var placed := PackedVector2Array()
			for p in rotated:
				placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
			draw_colored_polygon(placed, quill_col)
			var closed := placed.duplicate()
			closed.append(placed[0])
			draw_polyline(closed, ink, max(1.0, r * 0.12), true)
			draw_circle(placed[0], r * 0.10, ink)
		draw_circle(center, r * 0.14, ink)

	func _paint_motif(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		match String(pal.motif):
			"quill":
				_motif_quill(pal, center, r, mirror)
			_:
				_motif_quill(pal, center, r, mirror)

	## Wax-seal disc (flat base + ink rim) with the set's motif embossed
	## inside it, sized to `r` so it always fits its caller's margin cell.
	func _paint_seal(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		draw_circle(center, r, pal.seal)
		draw_arc(center, r, 0.0, TAU, 24, Color(Color(pal.ink).r, Color(pal.ink).g, Color(pal.ink).b, 0.85), max(1.0, r * 0.12))
		_paint_motif(pal, center, r * 0.72, mirror)

	# ── Pieces ───────────────────────────────────────────────────────────

	func _paint_frame(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(FRAME_SIZE))
		draw_rect(rect, pal.parchment)
		_paint_stains(rng, rect, 8, Color(Color(pal.parchment_dark).r, Color(pal.parchment_dark).g, Color(pal.parchment_dark).b, 0.07))
		_paint_wobble_border(rng, rect, [2.0, 5.5], [2.0, 1.6], pal.ink)
		var m := float(FRAME_MARGIN)
		var r := 9.0
		var corners := [
			{c = Vector2(m * 0.5, m * 0.5), mir = Vector2(1, 1)},
			{c = Vector2(FRAME_SIZE.x - m * 0.5, m * 0.5), mir = Vector2(-1, 1)},
			{c = Vector2(m * 0.5, FRAME_SIZE.y - m * 0.5), mir = Vector2(1, -1)},
			{c = Vector2(FRAME_SIZE.x - m * 0.5, FRAME_SIZE.y - m * 0.5), mir = Vector2(-1, -1)},
		]
		for cd in corners:
			_paint_seal(pal, cd.c, r, cd.mir)

	## Per-state fills exactly per the candidate sheet's parchment button:
	## normal parchment + ink border; hover pale fill + heraldry-emphasis
	## border overlay; pressed heraldry fill; disabled desaturated fill +
	## faded ink. Every color is derived from `pal` so faction sets (Task 2)
	## reskin automatically without touching this function.
	func _paint_button(rng: RandomNumberGenerator, pal: Dictionary, state: String) -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(BTN_SIZE))
		var fill: Color
		var border: Color = pal.ink
		match state:
			"normal":
				fill = pal.parchment
			"hover":
				fill = Color(pal.parchment).lightened(0.10)
			"pressed":
				fill = pal.heraldry
			_:  # "disabled"
				# Fully opaque, desaturated toward mid-grey — deliberately NOT
				# using alpha<1 here: a SubViewport capture stores premultiplied
				# RGB, so a baked sub-1.0 alpha reads correctly in an isolated
				# preview but gets alpha-blended a SECOND time by any normal
				# consumer (StyleBoxTexture draw, PNG viewer), silently darkening
				# the result. Runtime dimming, if ever wanted, belongs in
				# game_manager.gd's existing modulate parameter, not the bake.
				var p: Color = pal.parchment
				var g := (p.r + p.g + p.b) / 3.0
				fill = p.lerp(Color(g, g, g), 0.55)
				border = Color(pal.ink).lerp(fill, 0.5)
		draw_colored_polygon(_rounded_rect_poly(rect, 4.0), fill)
		var border_rect := rect.grow(-2.0)  # inside BTN_MARGIN (12px)
		var wobble := _jittered_rect_poly(rng, border_rect, 4, 1.0)
		var closed := wobble.duplicate()
		closed.append(wobble[0])
		draw_polyline(closed, border, 1.6, true)
		if state == "hover":
			draw_polyline(closed, Color(Color(pal.heraldry).r, Color(pal.heraldry).g, Color(pal.heraldry).b, 0.85), 1.0, true)

	## Frame variant: doubled outer border (two nested wobble-line pairs)
	## and a single larger seal at top-center instead of the 4 corners.
	func _paint_notification(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(NOTIF_SIZE))
		draw_rect(rect, pal.parchment)
		_paint_stains(rng, rect, 14, Color(Color(pal.parchment_dark).r, Color(pal.parchment_dark).g, Color(pal.parchment_dark).b, 0.07))
		_paint_wobble_border(rng, rect, [3.0, 6.5], [2.2, 1.8], pal.ink)
		_paint_wobble_border(rng, rect, [12.0, 15.5], [1.8, 1.4], pal.ink)
		var r := 13.0
		var cy := float(NOTIF_MARGIN) * 0.5
		_paint_seal(pal, Vector2(NOTIF_SIZE.x * 0.5, cy), r, Vector2.ONE)

	# ── Contact sheet — lays out all 6 baked pieces plus a 400x260 sample of
	# the frame piece drawn through a real StyleBoxTexture (draw_style_box),
	# the same nine-patch draw path game_manager.gd uses at runtime, so
	# corner-seal integrity under stretch is provably checked, not asserted. ──

	## NOTE: `textures` must already be real Texture2D objects built by the
	## driver's _process() BEFORE this draw runs — creating a fresh
	## ImageTexture from inside _draw() (this function) races the GPU
	## upload against the same frame's draw batch and silently rasterizes
	## as blank white. Pre-building in _process() (see the SceneTree driver
	## below) is the pattern tools_ui_style_candidates.gd's sheet mode uses
	## and is the proven-safe order.
	func _paint_contact_sheet(sid: StringName, textures: Dictionary) -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(CONTACT_VP_SIZE)), Color(0.10, 0.09, 0.08))
		draw_string(ThemeDB.fallback_font, Vector2(20, 24), "UI CHROME CONTACT SHEET — %s" % String(sid).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.92, 0.88, 0.78))

		var frame_tex: Texture2D = textures["frame"]
		var notif_tex: Texture2D = textures["notification"]

		var frame_pos := Vector2(20, 40)
		draw_string(ThemeDB.fallback_font, frame_pos + Vector2(0, -6), "frame", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.76, 0.68))
		draw_texture(frame_tex, frame_pos)

		var notif_pos := Vector2(240, 40)
		draw_string(ThemeDB.fallback_font, notif_pos + Vector2(0, -6), "notification", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.76, 0.68))
		draw_texture(notif_tex, notif_pos)

		var btn_keys := ["btn_normal", "btn_hover", "btn_pressed", "btn_disabled"]
		var bx := 20.0
		var by := 280.0
		for key in btn_keys:
			var tex: Texture2D = textures[key]
			draw_string(ThemeDB.fallback_font, Vector2(bx, by - 6), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.76, 0.68))
			draw_texture(tex, Vector2(bx, by))
			bx += 110.0

		var sb := StyleBoxTexture.new()
		sb.texture = frame_tex
		sb.texture_margin_left = FRAME_MARGIN
		sb.texture_margin_top = FRAME_MARGIN
		sb.texture_margin_right = FRAME_MARGIN
		sb.texture_margin_bottom = FRAME_MARGIN
		var stretch_pos := Vector2(500, 40)
		draw_string(ThemeDB.fallback_font, stretch_pos + Vector2(0, -6), "frame stretched to 400x260 (StyleBoxTexture nine-patch)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.76, 0.68))
		draw_style_box(sb, Rect2(stretch_pos, STRETCH_SAMPLE_SIZE))

	# ── Dispatch ─────────────────────────────────────────────────────────

	func _draw() -> void:
		if contact_mode:
			if contact_textures.is_empty():
				return
			_paint_contact_sheet(contact_set_id, contact_textures)
			return
		if set_id == &"" or piece == "":
			return
		var pal: Dictionary = SETS.get(set_id, SETS[&"neutral"])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(set_id) + "_" + piece)
		match piece:
			"frame":
				_paint_frame(rng, pal)
			"btn_normal":
				_paint_button(rng, pal, "normal")
			"btn_hover":
				_paint_button(rng, pal, "hover")
			"btn_pressed":
				_paint_button(rng, pal, "pressed")
			"btn_disabled":
				_paint_button(rng, pal, "disabled")
			"notification":
				_paint_notification(rng, pal)
			_:
				push_warning("No painter for piece: %s" % piece)

## ─────────────────────────────────────────────────────────────────────────
## SceneTree driver — capture loop modeled on tools_generate_resource_art.gd.
## ─────────────────────────────────────────────────────────────────────────

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

	var args := OS.get_cmdline_user_args()
	var set_arg := args[0] if args.size() > 0 else ""
	var set_ids: Array = SETS.keys() if set_arg == "" else [StringName(set_arg)]

	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = true
	root.add_child(_vp)
	_painter = _ChromePainter.new()
	_vp.add_child(_painter)

	for sid in set_ids:
		if not SETS.has(sid):
			push_warning("Unknown chrome set id: %s (skipping)" % [sid])
			continue
		for piece in PIECES:
			_jobs.append(["bake", sid, piece])
		_jobs.append(["contact", sid, ""])

	if _jobs.is_empty():
		print("No jobs to run — no valid set id(s) in %s" % [set_ids])
		quit()

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		if job[0] == "bake":
			var sid: StringName = job[1]
			var piece: String = job[2]
			var fname := "%s_%s.png" % [String(sid), piece]
			img.save_png("%s/%s" % [OUT_DIR, fname])
			_images["%s_%s" % [String(sid), piece]] = img
			print("Saved %s" % fname)
		else:
			var sid2: StringName = job[1]
			var fname2 := "_contact_%s.png" % String(sid2)
			img.save_png("%s/%s" % [OUT_DIR, fname2])
			img.save_png("%s/%s" % [SCRATCH_DIR, fname2])
			print("Saved contact sheet: %s" % fname2)
		_capture_pending = false
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		if job[0] == "bake":
			var sid: StringName = job[1]
			var piece: String = job[2]
			var sz: Vector2i
			match piece:
				"frame":
					sz = FRAME_SIZE
				"notification":
					sz = NOTIF_SIZE
				_:
					sz = BTN_SIZE
			_vp.size = sz
			_painter.contact_mode = false
			_painter.set_id = sid
			_painter.piece = piece
		else:
			var sid2: StringName = job[1]
			_vp.size = CONTACT_VP_SIZE
			_painter.contact_mode = true
			_painter.contact_set_id = sid2
			# Built HERE in _process (not inside _draw/_paint_contact_sheet) so the
			# GPU upload has a full tick to land before the draw batch that
			# references these textures is submitted — see the note on
			# _paint_contact_sheet for why creating them inside _draw() instead
			# rasterizes as blank white.
			_painter.contact_textures = {
				"frame": ImageTexture.create_from_image(_images["%s_frame" % String(sid2)]),
				"btn_normal": ImageTexture.create_from_image(_images["%s_btn_normal" % String(sid2)]),
				"btn_hover": ImageTexture.create_from_image(_images["%s_btn_hover" % String(sid2)]),
				"btn_pressed": ImageTexture.create_from_image(_images["%s_btn_pressed" % String(sid2)]),
				"btn_disabled": ImageTexture.create_from_image(_images["%s_btn_disabled" % String(sid2)]),
				"notification": ImageTexture.create_from_image(_images["%s_notification" % String(sid2)]),
			}
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d UI chrome jobs into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
