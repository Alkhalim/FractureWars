extends SceneTree
## UI Polish Wave 2 Task W2 — bakes the unit-class glyph set shown left of
## the name on recruit buttons (see scripts/core/unit_class_helper.gd for
## the class enum + the tag->class derivation rules these glyphs represent).
##
## Modeled on tests/tools_generate_ui_chrome.gd's deterministic SubViewport
## bake pattern, deliberately simplified:
##  - no per-faction sets — a unit's CLASS doesn't depend on the player's
##    chrome set, only its tags. Per-class COLOR is a separate concern
##    (UIPalette.CLASS_COLORS), applied at runtime as a frame tint around the
##    button, not baked into the glyph pixels — so one glyph set serves every
##    faction.
##  - no hand-wobble. The chrome generator's ~1-1.5px wobble amplitude is
##    tuned for 96-512px canvases; at this glyph's ~24px DISPLAY size (baked
##    at 64px for crisp downscale) that amplitude would be pure noise, not a
##    visible "hand-inked" character. Bold flat-ink silhouettes instead, per
##    the brief's own "simple bold silhouettes" direction.
##  - deterministic with NO RandomNumberGenerator at all (not just a fixed
##    seed) — every glyph is a fixed set of draw calls, nothing to seed.
##
## Run WINDOWED (SubViewport capture needs a live window; a brief flash is
## expected):
##   & "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --resolution 900x400 --path . -s res://tests/tools_generate_class_icons.gd
## Then a headless --import pass so the editor asset DB picks up the PNGs:
##   & <godot> --headless --path . --import
##
## Output: assets/sprites/ui/generated/class_<id>.png (10, ICON_SIZE each,
## transparent bg) + assets/sprites/ui/generated/_contact_class_icons.png
## (also copied to the session scratchpad) — a labeled row of all 10 at both
## native 64px and a 24px downscale (the real recruit-button display size)
## for legibility judging.

const OUT_DIR := "res://assets/sprites/ui/generated"

## Final review fix: was a hardcoded, session-specific AppData temp path (only
## meaningful inside one particular Claude Code session) — de-hardcoded to an
## optional CLI arg. `res://` OUT_DIR is always the real, permanent output;
## this is purely an extra copy for a chat session's review, so it defaults to
## "" (skip copy) instead of assuming any particular machine/user.
## Pass `--scratch-dir=<path>` after `--` to opt in, e.g.:
##   -s res://tests/tools_generate_class_icons.gd -- --scratch-dir=C:/path/to/scratch
var SCRATCH_DIR := ""

static func _parse_scratch_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scratch-dir="):
			return arg.substr("--scratch-dir=".length())
	return ""

const ICON_SIZE := Vector2i(64, 64)     # baked ~2.5x the "~24px" brief target for a crisp downscale
const CONTACT_VP_SIZE := Vector2i(760, 210)

## Fixed ink silhouette color — glyphs bake once and are never re-tinted per
## faction (the button's colored FRAME carries class color, see
## campaign_hud.gd's recruit-button decoration + UIPalette.CLASS_COLORS).
## Matches the neutral chrome set's `ink` tone (tools_generate_ui_chrome.gd
## SETS.neutral) so the glyph reads coherently even on chrome sets far from
## neutral, without importing a UIPalette dependency into a bake tool that
## (like tools_generate_ui_chrome.gd) must run before any autoload state
## matters.
const INK := Color(0.16, 0.13, 0.10, 1.0)
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.16)   # subtle ink-illustration accent stroke, a few glyphs only

const CLASSES: Array[StringName] = [
	&"infantry", &"cavalry", &"archer", &"mage", &"monster",
	&"beast", &"supporter", &"flying", &"siege", &"construct",
]

## ─────────────────────────────────────────────────────────────────────────
## Painter — draws exactly one glyph (icon_id) or the contact sheet,
## captured via SubViewport (mirrors _ChromePainter's role in the chrome
## generator, trimmed to what this tool needs).
## ─────────────────────────────────────────────────────────────────────────
class _IconPainter extends Node2D:
	var icon_id: StringName = &""
	var contact_mode := false
	var contact_textures: Dictionary = {}   # class_id -> ImageTexture, built by the driver

	func _draw() -> void:
		if contact_mode:
			_paint_contact_sheet()
		else:
			_paint_icon(icon_id, Vector2(ICON_SIZE) * 0.5, float(min(ICON_SIZE.x, ICON_SIZE.y)) * 0.5 * 0.78)

	func _ellipse_poly(center: Vector2, rx: float, ry: float, segs: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in segs:
			var a := TAU * float(i) / float(segs)
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	## Same base->tip teardrop technique as tools_generate_ui_chrome.gd's
	## _leaf_poly (feather/wing petals here) — kept local since this tool
	## has no shared-code dependency on the chrome generator by design (a
	## small standalone tool, per the brief's "OR a small dedicated icon
	## tool" option).
	func _leaf_poly(base: Vector2, tip: Vector2, width: float) -> PackedVector2Array:
		var dirv := tip - base
		var perp: Vector2
		if dirv.length() > 0.0001:
			perp = Vector2(-dirv.y, dirv.x).normalized()
		else:
			perp = Vector2(0.0, 1.0)
		var mid := base.lerp(tip, 0.5)
		return PackedVector2Array([base, mid + perp * width * 0.5, tip, mid - perp * width * 0.5])

	## Tapered claw/slash stroke: full `width` at `a`, a point at `b`.
	func _claw_poly(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
		var d := (b - a).normalized()
		var perp := Vector2(-d.y, d.x)
		return PackedVector2Array([a - perp * width * 0.5, a + perp * width * 0.5, b])

	func _paint_icon(cls: StringName, center: Vector2, r: float) -> void:
		if cls == &"":
			return   # benign: Node2D's default _draw() fires once when added to the tree, before _process assigns the first real job
		match cls:
			&"infantry": _glyph_infantry(center, r)
			&"cavalry": _glyph_cavalry(center, r)
			&"archer": _glyph_archer(center, r)
			&"mage": _glyph_mage(center, r)
			&"monster": _glyph_monster(center, r)
			&"beast": _glyph_beast(center, r)
			&"supporter": _glyph_supporter(center, r)
			&"flying": _glyph_flying(center, r)
			&"siege": _glyph_siege(center, r)
			&"construct": _glyph_construct(center, r)
			_:
				push_warning("No glyph painter for class: %s" % cls)

	## Helmet-shield: infantry's defining silhouette — a pointed-bottom
	## heater shield (simplest, most legible "ground trooper" read at 24px;
	## a literal helmet dome reads ambiguous against a round-topped button at
	## small scale, a shield outline doesn't).
	func _glyph_infantry(center: Vector2, r: float) -> void:
		var w := r * 0.62
		var top := center.y - r * 0.78
		var pts := PackedVector2Array([
			Vector2(center.x - w, top), Vector2(center.x + w, top),
			Vector2(center.x + w, center.y + r * 0.02),
			Vector2(center.x, center.y + r * 0.85),
			Vector2(center.x - w, center.y + r * 0.02),
		])
		draw_colored_polygon(pts, INK)
		draw_line(Vector2(center.x, top + r * 0.08), Vector2(center.x, center.y + r * 0.6), HIGHLIGHT, r * 0.10)

	## Horseshoe: a thick U-shaped band — cavalry.
	## Self-critique round 1 (24px downscale column of the first bake):
	## the original horsehead silhouette (poll/nose-wedge/jaw/ear, same
	## multi-point-polygon technique as the shield/gear/paw glyphs that DID
	## read clearly) collapsed into an unreadable dark blob at 24px — its
	## defining feature (the pricked ear notch) is a thin concave detail
	## that anti-aliases away at this scale, unlike shield/gear/paw whose
	## silhouettes stay bold and convex-ish even shrunk. A horseshoe has no
	## such fragile detail: it's one thick, unbroken, symmetric band with an
	## immediately legible universal "horse" association, and reads
	## correctly at both 64px and the 24px display size.
	func _glyph_cavalry(center: Vector2, r: float) -> void:
		draw_arc(center + Vector2(0.0, -r * 0.05), r * 0.78, deg_to_rad(20.0), deg_to_rad(160.0), 28, INK, r * 0.34, true)

	## Bow (arc + string) with a nocked arrow drawn through center —
	## archer's class icon (see unit_class_helper.gd: "archer" covers both
	## ranged-infantry AND the ~23 bare-"ranged" skirmishers, so the icon
	## needs to read as "ranged skirmisher" generically, not e.g. an
	## infantry-specific shield-and-bow composite).
	## Self-critique round 1: strokes (arc/string/shaft) were too thin
	## (0.06-0.13r) — fine at the 64px bake, but a stroke under ~4px at that
	## canvas anti-aliases to a faint hairline once downscaled to the real
	## 24px display size. Widened every stroke here 60-70%; dropped the
	## small fletching cross-lines (they were sub-pixel clutter at 24px,
	## not adding legibility) so the composite stays bold instead of busy.
	func _glyph_archer(center: Vector2, r: float) -> void:
		var rad := r * 0.82
		draw_arc(center, rad, deg_to_rad(-65.0), deg_to_rad(65.0), 20, INK, r * 0.22, true)
		var top := center + Vector2(cos(deg_to_rad(-65.0)), sin(deg_to_rad(-65.0))) * rad
		var bot := center + Vector2(cos(deg_to_rad(65.0)), sin(deg_to_rad(65.0))) * rad
		draw_line(top, bot, INK, r * 0.10)
		var nock := top.lerp(bot, 0.5)
		var tip := nock + Vector2(-r * 1.05, 0.0)
		draw_line(nock, tip, INK, r * 0.12)
		var head := PackedVector2Array([tip, tip + Vector2(r * 0.30, -r * 0.17), tip + Vector2(r * 0.30, r * 0.17)])
		draw_colored_polygon(head, INK)

	## Staff with a 4-point spark at the tip — mage.
	## Self-critique round 1: staff line (0.11r) and spark (0.5r half-width)
	## were both too thin/small to survive the 24px downscale (same
	## "stroke/detail under ~4px at the 64px bake fades to a hairline"
	## pattern as archer). Widened the staff, enlarged the spark — moved the
	## staff top down from 0.80r to 0.62r to make room so the now-bigger
	## spark doesn't clip the canvas edge (verified against ICON_SIZE: with
	## r~25 the old 0.80r+0.5s combination would have put the star's tip at
	## y<0, off-canvas).
	func _glyph_mage(center: Vector2, r: float) -> void:
		var top := Vector2(center.x, center.y - r * 0.62)
		var bot := Vector2(center.x, center.y + r * 0.88)
		draw_line(top, bot, INK, r * 0.16)
		var spark_c := top + Vector2(0.0, r * 0.04)
		var s := r * 0.55
		var star := PackedVector2Array([
			spark_c + Vector2(0, -s), spark_c + Vector2(s * 0.32, -s * 0.32),
			spark_c + Vector2(s, 0), spark_c + Vector2(s * 0.32, s * 0.32),
			spark_c + Vector2(0, s), spark_c + Vector2(-s * 0.32, s * 0.32),
			spark_c + Vector2(-s, 0), spark_c + Vector2(-s * 0.32, -s * 0.32),
		])
		draw_colored_polygon(star, INK)

	## 3 tapered claw-slash strokes, parallel, diagonal — monster.
	func _glyph_monster(center: Vector2, r: float) -> void:
		var dir := Vector2(1, -1).normalized()
		var perp := Vector2(dir.y, -dir.x)
		for i in range(3):
			var off := perp * (r * 0.5) * float(i - 1)
			var a := center - dir * r * 0.75 + off
			var b := center + dir * r * 0.75 + off
			draw_colored_polygon(_claw_poly(a, b, r * 0.15), INK)

	## Paw print: one broad pad + 4 arced toes — beast.
	func _glyph_beast(center: Vector2, r: float) -> void:
		draw_colored_polygon(_ellipse_poly(center + Vector2(0, r * 0.32), r * 0.52, r * 0.40, 20), INK)
		var toe_offsets := [Vector2(-0.50, -0.30), Vector2(-0.18, -0.55), Vector2(0.18, -0.55), Vector2(0.50, -0.30)]
		for t in toe_offsets:
			draw_colored_polygon(_ellipse_poly(center + t * r, r * 0.20, r * 0.24, 14), INK)

	## Chalice/goblet — supporter (healer/buffer read, distinct from mage's
	## staff-and-spark).
	## Self-critique round 1: the 3-piece build (separate bowl/stem/base draw
	## calls, plus a small cross-sparkle accent) read as a weak, ambiguous
	## triangle at 24px — none of its 3 pieces was individually bold enough,
	## and the sparkle was pure sub-pixel noise at that size. Rebuilt as ONE
	## connected 8-point polygon tracing the whole goblet outline (bowl rim
	## -> neck -> base -> neck -> bowl rim) so it fills as a single solid
	## silhouette with no seams between pieces, and dropped the sparkle
	## entirely (the goblet shape alone is what needs to read at small
	## scale; a shape that already reads doesn't need a second cue that
	## can't read at all).
	func _glyph_supporter(center: Vector2, r: float) -> void:
		var bowl_w := r * 0.62
		var neck_w := r * 0.14
		var base_w := r * 0.40
		var top_y := center.y - r * 0.80
		var bowl_bottom_y := center.y - r * 0.10
		var stem_bottom_y := center.y + r * 0.55
		var base_y := center.y + r * 0.78
		var pts := PackedVector2Array([
			Vector2(center.x - bowl_w, top_y), Vector2(center.x + bowl_w, top_y),
			Vector2(center.x + neck_w, bowl_bottom_y), Vector2(center.x + neck_w, stem_bottom_y),
			Vector2(center.x + base_w, base_y), Vector2(center.x - base_w, base_y),
			Vector2(center.x - neck_w, stem_bottom_y), Vector2(center.x - neck_w, bowl_bottom_y),
		])
		draw_colored_polygon(pts, INK)

	## Swept wing — flying.
	## Self-critique round 1: a fan of 4 thin feather leaves (each
	## individually narrow, overlapping only near their shared base) merged
	## into a small indistinct dark smudge at 24px — no single feather was
	## wide enough to read on its own, and the fan's negative space (the
	## whole point of showing separate feathers) disappears at that scale
	## anyway. Replaced with 2 large overlapping leaf shapes — one big
	## primary sweep (0.62r wide) plus a smaller secondary tucked near its
	## base for a touch of layered-feather character — using the SAME
	## _leaf_poly helper (still a guaranteed-simple polygon, just sized to
	## actually read as a single bold wing silhouette instead of 4 slivers).
	func _glyph_flying(center: Vector2, r: float) -> void:
		var base1 := center + Vector2(-r * 0.55, r * 0.60)
		var tip1 := center + Vector2(r * 0.70, -r * 0.70)
		draw_colored_polygon(_leaf_poly(base1, tip1, r * 0.62), INK)
		var base2 := center + Vector2(-r * 0.15, r * 0.55)
		var tip2 := center + Vector2(r * 0.35, -r * 0.20)
		draw_colored_polygon(_leaf_poly(base2, tip2, r * 0.30), INK)

	## Battering ram: tapered beam + a bold round ram-head — siege.
	## Self-critique round 1: the original beam+head+2 wheels+struts
	## composite crowded a lot of small detail (wheel circles ~0.17r,
	## strut lines) into one glyph — none of it individually bold, and it
	## read as an indistinct smudge at 24px. Dropped the wheels/struts
	## entirely (they weren't adding legibility, just clutter) and widened
	## the ram-head; a tapered beam (wide at the back, narrow at the
	## striking end) ending in one large circle is simpler AND bolder.
	func _glyph_siege(center: Vector2, r: float) -> void:
		var beam := PackedVector2Array([
			Vector2(center.x - r * 0.85, center.y - r * 0.12),
			Vector2(center.x + r * 0.55, center.y - r * 0.30),
			Vector2(center.x + r * 0.55, center.y + r * 0.30),
			Vector2(center.x - r * 0.85, center.y + r * 0.12),
		])
		draw_colored_polygon(beam, INK)
		draw_circle(Vector2(center.x - r * 0.85, center.y), r * 0.32, INK)

	## 8-tooth gear silhouette with a hub — construct.
	func _glyph_construct(center: Vector2, r: float) -> void:
		var teeth := 8
		var outer := r * 0.92
		var inner := r * 0.60
		var pts := PackedVector2Array()
		for i in range(teeth):
			var base_ang := TAU * float(i) / float(teeth)
			var step := TAU / float(teeth)
			pts.append(center + Vector2(cos(base_ang), sin(base_ang)) * inner)
			pts.append(center + Vector2(cos(base_ang + step * 0.22), sin(base_ang + step * 0.22)) * outer)
			pts.append(center + Vector2(cos(base_ang + step * 0.55), sin(base_ang + step * 0.55)) * outer)
			pts.append(center + Vector2(cos(base_ang + step * 0.78), sin(base_ang + step * 0.78)) * inner)
		draw_colored_polygon(pts, INK)
		draw_circle(center, r * 0.24, INK)
		draw_circle(center, r * 0.24, HIGHLIGHT)

	## Contact sheet: one column per class, native 64px + a 24px downscale
	## (the real button display size) + label, so legibility at both scales
	## is checkable straight from the bake without opening the game.
	func _paint_contact_sheet() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(CONTACT_VP_SIZE)), Color(0.82, 0.78, 0.68, 1.0))
		var col_w := float(CONTACT_VP_SIZE.x) / float(CLASSES.size())
		for i in CLASSES.size():
			var cls: StringName = CLASSES[i]
			var tex: ImageTexture = contact_textures.get(cls)
			if tex == null:
				continue
			var cx := col_w * (float(i) + 0.5)
			draw_texture_rect(tex, Rect2(cx - 32.0, 20.0, 64.0, 64.0), false)
			draw_texture_rect(tex, Rect2(cx - 12.0, 100.0, 24.0, 24.0), false)
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(cx - col_w * 0.45, 148.0), String(cls), HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.9, 14, Color(0.1, 0.08, 0.06))

## ─────────────────────────────────────────────────────────────────────────
## SceneTree driver — capture loop modeled on tools_generate_ui_chrome.gd.
## ─────────────────────────────────────────────────────────────────────────
var _vp: SubViewport
var _painter: _IconPainter
var _images: Dictionary = {}   # class_id (String) -> Image
var _jobs: Array = []          # ["icon", class_id] | ["contact"]
var _job_idx := -1
var _capture_pending := false

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	SCRATCH_DIR = _parse_scratch_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if SCRATCH_DIR != "":
		DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = true
	root.add_child(_vp)
	_painter = _IconPainter.new()
	_vp.add_child(_painter)

	for cls in CLASSES:
		_jobs.append(["icon", cls])
	_jobs.append(["contact", &""])

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		if job[0] == "icon":
			var cls: StringName = job[1]
			var fname := "class_%s.png" % String(cls)
			img.save_png("%s/%s" % [OUT_DIR, fname])
			_images[String(cls)] = img
			print("Saved %s" % fname)
		else:
			img.save_png("%s/_contact_class_icons.png" % OUT_DIR)
			if SCRATCH_DIR != "":
				img.save_png("%s/_contact_class_icons.png" % SCRATCH_DIR)
			print("Saved contact sheet: _contact_class_icons.png")
		_capture_pending = false
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		if job[0] == "icon":
			var cls: StringName = job[1]
			_vp.size = ICON_SIZE
			_painter.contact_mode = false
			_painter.icon_id = cls
		else:
			_vp.size = CONTACT_VP_SIZE
			_painter.contact_mode = true
			# Built HERE (not inside _draw()) so the GPU upload has a full
			# tick to land before the draw batch referencing these textures
			# is submitted — same gotcha as tools_generate_ui_chrome.gd's
			# _paint_contact_sheet (creating them inside _draw() rasterizes
			# as blank).
			var textures := {}
			for cls2 in CLASSES:
				textures[cls2] = ImageTexture.create_from_image(_images[String(cls2)])
			_painter.contact_textures = textures
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d class-icon jobs into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
