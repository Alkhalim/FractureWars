extends SceneTree
## Font candidate sheet bake tool (UI Overhaul #40, Task 5 ART GATE). Renders
## the 4 downloaded OFL candidates directly on the neutral parchment frame
## texture (via a real StyleBoxTexture nine-patch draw — same path
## `_build_theme_for_set` uses at runtime) so the coordinator/user judge
## legibility in situ, not on a flat swatch. One-shot bake, no RNG (pure text
## layout) — fully deterministic. Run WINDOWED (SubViewport capture needs a
## live window; a brief flash is expected):
##   & "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --resolution 1200x800 --path . -s res://tests/tools_font_candidate_sheet.gd
##
## Candidates (Task 5 brief; file names as actually downloaded — the brief's
## IM Fell English URL 404'd, the real Google Fonts file is IMFeENrm28P.ttf,
## saved locally as IMFellEnglish-Regular.ttf):
##   Body A    = Alegreya       (variable wght axis) assets/fonts/Alegreya-wght.ttf
##   Body B    = Vollkorn       (variable wght axis) assets/fonts/Vollkorn-wght.ttf
##   Display A = Cinzel         (variable wght axis) assets/fonts/Cinzel-wght.ttf
##   Display B = IM Fell English (static regular, no axis) assets/fonts/IMFellEnglish-Regular.ttf
## The 3 variable faces are pinned to wght=400 via FontVariation for a fair
## baseline comparison here — global constraint note: if the FINAL wired pair
## (post-gate) renders at an odd default weight, the axis gets tuned again at
## that point and the choice is documented in the Task 5 report.
##
## Output: assets/fonts/_contact_font_candidates.png, also copied to the
## session scratchpad for the ART GATE.

const OUT_DIR := "res://assets/fonts"
const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"
const OUT_NAME := "_contact_font_candidates.png"

const FRAME_TEX_PATH := "res://assets/sprites/ui/generated/neutral_frame.png"
const FRAME_MARGIN := 32  # matches tools_generate_ui_chrome.gd's FRAME_MARGIN contract (Task 5b round 2: was 24, moved to 32 with the rebaked neutral_frame.png)

const BODY_SIZES := [13, 12, 11, 10]
const DISPLAY_SIZES := [20, 16, 14]
const DISPLAY_TEXT := {20: "PROVINCIAL OVERVIEW", 16: "Declare War", 14: "Research: Iron Working"}
const PARAGRAPH := "The garrison reports a shortfall of grain as autumn rains flood the eastern roads; reinforcements from the capital will not arrive before the frost breaks the passes."
const DIGITS_LINE := "0123456789 +15% \u22123"  # \u2212 = minus sign, per brief's literal "−3"

const INK := Color(0.16, 0.13, 0.10)          # neutral set's ink, hardcoded (tool-side, no UIPalette/autoload dependency — matches tools_generate_ui_chrome.gd convention)
const CAPTION_COL := Color(0.16, 0.13, 0.10, 0.62)

const MARGIN_X := 40.0
const COL_GAP := 40.0
const PAGE_W := 1200.0
const COL_W := (PAGE_W - MARGIN_X * 2.0 - COL_GAP) / 2.0

## One draw instruction, precomputed by _start() so measurement (which
## determines the canvas height, hence SubViewport size) and drawing share a
## single source of truth instead of two independently-guessed layouts.
class _Cmd:
	var kind: String  # "single" or "multi"
	var font: Font
	var size: int
	var pos: Vector2
	var text: String
	var color: Color
	var width: float

var _vp: SubViewport
var _painter: _Painter
var _capture_pending := false
var _job_started := false

class _Painter extends Node2D:
	var frame_tex: Texture2D
	var canvas_size: Vector2
	var cmds: Array = []

	func _draw() -> void:
		var sb := StyleBoxTexture.new()
		sb.texture = frame_tex
		sb.texture_margin_left = FRAME_MARGIN
		sb.texture_margin_top = FRAME_MARGIN
		sb.texture_margin_right = FRAME_MARGIN
		sb.texture_margin_bottom = FRAME_MARGIN
		draw_style_box(sb, Rect2(Vector2.ZERO, canvas_size))
		for c in cmds:
			var cmd: _Cmd = c
			if cmd.kind == "single":
				draw_string(cmd.font, cmd.pos, cmd.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cmd.size, cmd.color)
			else:
				draw_multiline_string(cmd.font, cmd.pos, cmd.text, HORIZONTAL_ALIGNMENT_LEFT, cmd.width, cmd.size, -1, cmd.color)

func _init() -> void:
	call_deferred("_start")

## Loads a font file, optionally wrapping it in a FontVariation pinned to
## wght=400 (variable faces only — the static IM Fell English face is used
## as-is, it has no wght axis to pin).
func _load_face(path: String, pin_wght: bool) -> Font:
	var base := load(path)
	if base == null:
		push_error("Font candidate missing: %s" % path)
		return ThemeDB.fallback_font
	if not pin_wght:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 400.0}
	return fv

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

	var body_a := _load_face("res://assets/fonts/Alegreya-wght.ttf", true)
	var body_b := _load_face("res://assets/fonts/Vollkorn-wght.ttf", true)
	var display_a := _load_face("res://assets/fonts/Cinzel-wght.ttf", true)
	var display_b := _load_face("res://assets/fonts/IMFellEnglish-Regular.ttf", false)

	var frame_tex: Texture2D = load(FRAME_TEX_PATH) if ResourceLoader.exists(FRAME_TEX_PATH) else null
	if frame_tex == null:
		push_error("Neutral frame texture missing at %s — run tools_generate_ui_chrome.gd first" % FRAME_TEX_PATH)
		quit(1)
		return

	var cmds: Array = []
	var y := 34.0
	cmds.append(_txt(ThemeDB.fallback_font, 16, Vector2(MARGIN_X, y), "FONT CANDIDATE SHEET \u2014 UI Overhaul #40, Task 5 ART GATE", INK))
	y += 20
	cmds.append(_txt(ThemeDB.fallback_font, 11, Vector2(MARGIN_X, y), "Body @ 13/12/11/10px paragraphs; Display @ 20/16/14px titles; digits row per face @ 11px. On the neutral parchment frame.", CAPTION_COL))
	y += 34

	# ── Body candidates: two columns, paragraph at each ladder size + a digits row ──
	var col_x := [MARGIN_X, MARGIN_X + COL_W + COL_GAP]
	var body_fonts := [body_a, body_b]
	var body_labels := ["BODY A \u2014 Alegreya (variable, wght=400)", "BODY B \u2014 Vollkorn (variable, wght=400)"]
	var body_bottom := y
	for c in 2:
		var cy := y
		cmds.append(_txt(ThemeDB.fallback_font, 13, Vector2(col_x[c], cy), body_labels[c], INK))
		cy += 22
		var f: Font = body_fonts[c]
		for sz in BODY_SIZES:
			cmds.append(_txt(ThemeDB.fallback_font, 10, Vector2(col_x[c], cy), "%dpx" % sz, CAPTION_COL))
			cy += 13
			var block_h: float = f.get_multiline_string_size(PARAGRAPH, HORIZONTAL_ALIGNMENT_LEFT, COL_W, sz).y
			cmds.append(_multi(f, sz, Vector2(col_x[c], cy), PARAGRAPH, COL_W, INK))
			cy += block_h + 16
		cmds.append(_txt(ThemeDB.fallback_font, 10, Vector2(col_x[c], cy), "digits @11px", CAPTION_COL))
		cy += 13
		cmds.append(_txt(f, 11, Vector2(col_x[c], cy), DIGITS_LINE, INK))
		cy += 22
		body_bottom = max(body_bottom, cy)

	# ── Display candidates: two columns, one title line per ladder size + a digits row ──
	y = body_bottom + 16
	cmds.append(_txt(ThemeDB.fallback_font, 11, Vector2(MARGIN_X, y), "\u2014\u2014\u2014", CAPTION_COL))
	y += 22
	var disp_fonts := [display_a, display_b]
	var disp_labels := ["DISPLAY A \u2014 Cinzel (variable, wght=400)", "DISPLAY B \u2014 IM Fell English (static regular)"]
	var disp_bottom := y
	for c in 2:
		var cy := y
		cmds.append(_txt(ThemeDB.fallback_font, 13, Vector2(col_x[c], cy), disp_labels[c], INK))
		cy += 22
		var f: Font = disp_fonts[c]
		for sz in DISPLAY_SIZES:
			cmds.append(_txt(ThemeDB.fallback_font, 10, Vector2(col_x[c], cy), "%dpx" % sz, CAPTION_COL))
			cy += 13
			cmds.append(_txt(f, sz, Vector2(col_x[c], cy), DISPLAY_TEXT[sz], INK))
			cy += sz * 1.35 + 10
		cmds.append(_txt(ThemeDB.fallback_font, 10, Vector2(col_x[c], cy), "digits @11px", CAPTION_COL))
		cy += 13
		cmds.append(_txt(f, 11, Vector2(col_x[c], cy), DIGITS_LINE, INK))
		cy += 22
		disp_bottom = max(disp_bottom, cy)

	var page_h: float = disp_bottom + 24.0

	_vp = SubViewport.new()
	_vp.size = Vector2i(int(PAGE_W), int(page_h))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = false
	root.add_child(_vp)

	_painter = _Painter.new()
	_painter.frame_tex = frame_tex
	_painter.canvas_size = Vector2(PAGE_W, page_h)
	_painter.cmds = cmds
	_vp.add_child(_painter)
	# Capture is driven from _process (job-setup frame, then a capture-readback
	# frame) — same proven-safe 2-tick gap as tools_generate_ui_chrome.gd's
	# driver, not started here, so the SubViewport has a full tick before the
	# UPDATE_ONCE render is requested.

func _txt(font: Font, size: int, pos: Vector2, text: String, color: Color) -> _Cmd:
	var c := _Cmd.new()
	c.kind = "single"
	c.font = font
	c.size = size
	c.pos = pos
	c.text = text
	c.color = color
	return c

func _multi(font: Font, size: int, pos: Vector2, text: String, width: float, color: Color) -> _Cmd:
	var c := _Cmd.new()
	c.kind = "multi"
	c.font = font
	c.size = size
	c.pos = pos
	c.text = text
	c.color = color
	c.width = width
	return c

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		img.save_png("%s/%s" % [OUT_DIR, OUT_NAME])
		img.save_png("%s/%s" % [SCRATCH_DIR, OUT_NAME])
		print("Saved font candidate sheet: %s" % OUT_NAME)
		quit()
		return false
	if not _job_started:
		_job_started = true
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	return false
