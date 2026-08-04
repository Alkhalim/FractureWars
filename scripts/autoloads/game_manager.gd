extends Node

var state: GameState
var current_phase: Enums.GamePhase = Enums.GamePhase.MAIN_MENU
var movement_system: MovementSystem
var city_system: CitySystem = CitySystem.new()
var diplomacy_system: DiplomacySystem = DiplomacySystem.new()
var research_system: ResearchSystem = ResearchSystem.new()
var policy_system: PolicySystem = PolicySystem.new()

# Explored tiles (persists across campaign scene reloads, e.g., after battles)
var explored_tiles: Dictionary = {} # Vector2i -> true

# Faction-indexed army cache — rebuilt via rebuild_faction_army_cache()
var _faction_army_cache: Dictionary = {} # faction_id -> Array[ArmyState]
var _faction_army_cache_valid: bool = false

# Integer-keyed relation cache — avoids string allocation in get_relation()
var _relation_cache: Dictionary = {} # int -> Enums.FactionRelation

# Leader army override (set by main_menu before new_game, consumed in _init_armies)
var _leader_army_override: Array = []
var _leader_army_override_faction: StringName = &""

func rebuild_faction_army_cache() -> void:
	_faction_army_cache.clear()
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if not _faction_army_cache.has(army.faction_id):
			_faction_army_cache[army.faction_id] = []
		_faction_army_cache[army.faction_id].append(army)
	_faction_army_cache_valid = true

func invalidate_faction_army_cache() -> void:
	_faction_army_cache_valid = false

func _ready() -> void:
	_setup_global_theme()
	_setup_transition_overlay()

func _setup_transition_overlay() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 128
	_transition_rect = ColorRect.new()
	_transition_rect.color = Color(0, 0, 0, 0)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_transition_rect)
	add_child(_transition_layer)

var _is_transitioning := false

func transition_to_scene(path: String, duration := 0.5) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_transition_rect, "color:a", 1.0, duration)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
		call_deferred("_fade_in", duration)
	)

func _fade_in(duration: float) -> void:
	_transition_rect.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_transition_rect, "color:a", 0.0, duration)
	tween.tween_callback(func():
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
	)

# ── UI Theme — Parchment & Ink generated chrome (UI Overhaul #40) ──────
# Chrome is baked by tests/tools_generate_ui_chrome.gd to
# assets/sprites/ui/generated/<set_id>_{frame,btn_normal,btn_hover,
# btn_pressed,btn_disabled,notification}.png, one set per major faction plus
# `neutral`. game_manager.gd stays the single chrome chokepoint: every
# StyleBox factory below reads whichever set `chrome_set_id` currently names.
#
# Geometry CONTRACT — copied verbatim from tools_generate_ui_chrome.gd (keep
# in sync with that file). Whole-texture regions now (no sub-region
# slicing) — replaces the old hand-measured `_BTN_REGION`/`_FRAME_TEX_MARGIN`
# magic numbers that were scanned off the retired button1.png/frame1.png/
# notification1.png marble artwork.
const _FRAME_SIZE := Vector2i(192, 192)
const _FRAME_MARGIN := 32  # Task 5b round 2 (ART GATE seal-readability request): was 24, moves together with tools_generate_ui_chrome.gd's FRAME_MARGIN
const _BTN_SIZE := Vector2i(96, 48)
const _BTN_MARGIN := 12
const _NOTIF_SIZE := Vector2i(224, 224)
const _NOTIF_MARGIN := 32

# ── Bundled OFL fonts (Task 5, picked at the font ART GATE from 4 candidates
# baked by tests/tools_font_candidate_sheet.gd — sheet + tool kept committed
# for provenance). Body = Vollkorn, Display = Cinzel; both are variable-weight
# TTFs pinned to wght=400 via FontVariation (the exact weight shown at the
# gate) — see _load_ui_font. Licenses: assets/fonts/OFL-vollkorn.txt,
# assets/fonts/OFL-cinzel.txt.
const _BODY_FONT_PATH := "res://assets/fonts/Vollkorn-wght.ttf"
const _DISPLAY_FONT_PATH := "res://assets/fonts/Cinzel-wght.ttf"
const _FONT_WGHT_AXIS := 400.0

# Content-margin knobs — the layout-reflow tuning surface for the windowed
# panel-builder sweep (Task 3 step 6). Adjust HERE (or the geometry above),
# never with per-panel hacks in campaign_hud.gd/campaign.gd/etc.
#
# GOTCHA found during the sweep: almost every panel wraps its content in an
# opaque dark chip that fills the PanelContainer's content area (ScrollContainer
# panel override, or a full-rect backdrop Panel child — see _create_centered_dialog
# and _refresh_economy_panel). If content_margin < texture_margin, that opaque
# chip sits UNDER the border band and swallows it almost entirely — the frame
# reads as a plain dark box with no visible parchment. content_margin must stay
# >= texture_margin (a few px more, for a sliver of bare parchment) so the
# ink border + corner seals always show clear of whatever chip fills the interior.
const _FRAME_CONTENT := Vector4(40, 40, 40, 40)  # L T R B — 8px clear of _FRAME_MARGIN (32) — Task 5b round 2 grew both together
const _BTN_CONTENT := Vector4(18, 13, 18, 13)    # L T R B — buttons have no opaque backdrop child, just clear of _BTN_MARGIN (12)
const _NOTIF_CONTENT := Vector4(40, 58, 40, 40)  # L T R B — clear of _NOTIF_MARGIN (32); extra top clears the top-center seal

# Currently applied chrome/palette set (`neutral` at boot; a faction id once
# apply_faction_theme — Task 4 — runs). Every StyleBox factory below reflects
# whichever set was last loaded into _frame_texture/_btn_texture/_notif_texture.
var chrome_set_id: StringName = &"neutral"

var _btn_texture: Texture2D           # normal-state button texture
var _btn_hover_texture: Texture2D
var _btn_pressed_texture: Texture2D
var _btn_disabled_texture: Texture2D
var _frame_texture: Texture2D
var _notif_texture: Texture2D

var _transition_layer: CanvasLayer
var _transition_rect: ColorRect

func _setup_global_theme() -> void:
	UIPalette.rebuild(&"neutral")
	chrome_set_id = &"neutral"
	get_tree().root.theme = _build_theme_for_set(&"neutral")

## Live faction chrome switch (Task 4). Resolves minor factions to their
## parent via MINOR_FACTION_PARENTS (minors have no dedicated bake — they
## share their parent's generated PNGs, per _load_chrome_piece's fallback
## chain), then rebuilds the palette, the root theme, and drops the compact-
## theme memoization so get_compact_theme() lazily rebuilds from the new set
## next time something asks for it (same builder function as boot/neutral —
## no hand-constructed theme here, so the font-color/CheckBox-stylebox
## mirrors documented on get_compact_theme() stay intact).
## Call sites: new_game (right after state.player_faction_id is assigned)
## and load_game (right after the deserialized state is available).
func apply_faction_theme(faction_id: StringName) -> void:
	var set_id: StringName = MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	UIPalette.rebuild(set_id)
	chrome_set_id = set_id
	get_tree().root.theme = _build_theme_for_set(set_id)
	_compact_theme = null

## Loads one baked chrome piece for `set_id`, falling back to the neutral
## set's copy of the same piece if `set_id` has no bake (unknown/nonexistent
## faction id, or a set only partially baked). Returns null if even the
## neutral piece is missing (checkout with no generated PNGs at all) — every
## StyleBox factory below has its own flat StyleBoxFlat fallback for that case.
func _load_chrome_piece(set_id: StringName, piece: String) -> Texture2D:
	var path := "res://assets/sprites/ui/generated/%s_%s.png" % [String(set_id), piece]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if set_id != &"neutral":
		var neutral_path := "res://assets/sprites/ui/generated/neutral_%s.png" % piece
		if ResourceLoader.exists(neutral_path):
			return load(neutral_path) as Texture2D
	return null

## Loads a bundled UI font face (body or display) and pins its `wght`
## variable axis to _FONT_WGHT_AXIS via FontVariation. Both bundled faces are
## variable-weight TTFs — Godot 4 loads a variable .ttf as a plain FontFile at
## whatever the file's default named instance happens to be, which can render
## at an odd/inconsistent weight, so both are pinned explicitly here rather
## than trusting the file default. 400 is not a guess: it's the exact weight
## shown on both faces in the Task 5 ART GATE candidate sheet
## (assets/fonts/_contact_font_candidates.png), so the shipped look matches
## what was approved. Null-guarded (missing file/failed load) so every call
## site can skip straight to Godot's built-in default font instead of
## crashing on a null Font.
func _load_ui_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base := load(path) as FontFile
	if base == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": _FONT_WGHT_AXIS}
	return fv

## Builds a complete Theme from the baked chrome set `set_id` (fallback chain:
## `set_id` PNGs -> neutral PNGs -> flat StyleBoxFlat, per piece). Also
## refreshes _frame_texture/_btn_texture*/_notif_texture as a side effect, so
## the ad hoc factories below (make_panel_style, make_notification_style) and
## get_compact_theme() stay in lockstep with whichever set was last built
## here, without needing their own copy of the fallback logic. Caller is
## responsible for UIPalette.rebuild(set_id) — kept separate so callers that
## just want the palette (no theme rebuild) can do that alone.
func _build_theme_for_set(set_id: StringName) -> Theme:
	_frame_texture = _load_chrome_piece(set_id, "frame")
	_notif_texture = _load_chrome_piece(set_id, "notification")
	_btn_texture = _load_chrome_piece(set_id, "btn_normal")
	_btn_hover_texture = _load_chrome_piece(set_id, "btn_hover")
	_btn_pressed_texture = _load_chrome_piece(set_id, "btn_pressed")
	_btn_disabled_texture = _load_chrome_piece(set_id, "btn_disabled")

	var theme := Theme.new()

	# ── Bundled OFL font pair (Task 5) — body is the theme-wide default;
	# Theme.default_font/default_font_size are the fallback ANY type without
	# its own "font"/"font_size" override reads, so this one assignment
	# covers Label, Button (below, though it also gets an explicit size to
	# match the brief), and every other type that doesn't set its own font. ──
	var body_font := _load_ui_font(_BODY_FONT_PATH)
	if body_font:
		theme.default_font = body_font
	theme.default_font_size = 15

	# ── Button styles — each state has its own baked texture now (parchment/
	# hover-brighter/heraldry-pressed/desaturated-disabled), so no modulate
	# tinting is needed the way the old single-texture button1.png required. ──
	if _btn_texture:
		theme.set_stylebox("normal", "Button", _make_chrome_btn_style(_btn_texture))
		theme.set_stylebox("hover", "Button", _make_chrome_btn_style(_btn_hover_texture if _btn_hover_texture else _btn_texture))
		theme.set_stylebox("pressed", "Button", _make_chrome_btn_style(_btn_pressed_texture if _btn_pressed_texture else _btn_texture, true))
		theme.set_stylebox("disabled", "Button", _make_chrome_btn_style(_btn_disabled_texture if _btn_disabled_texture else _btn_texture))
		theme.set_stylebox("focus", "Button", _make_chrome_btn_style(_btn_hover_texture if _btn_hover_texture else _btn_texture))

	# Button font — dark ink on the (now light) parchment/heraldry fills;
	# pressed state's heraldry fill gets light parchment text per the
	# generator's "light text expected" note on btn_pressed.png.
	theme.set_color("font_color", "Button", UIPalette.INK_BODY)
	theme.set_color("font_hover_color", "Button", UIPalette.INK_TITLE)
	theme.set_color("font_pressed_color", "Button", UIPalette.PARCHMENT)
	theme.set_color("font_disabled_color", "Button", Color(UIPalette.INK_BODY.r, UIPalette.INK_BODY.g, UIPalette.INK_BODY.b, 0.55))
	theme.set_font_size("font_size", "Button", 15)

	# ── Label default — dark ink reads on the parchment fields panels now
	# sit on; text intended for dark chips (_make_text_chip et al) keeps
	# setting its own light font_color override, unaffected by this default. ──
	theme.set_color("font_color", "Label", UIPalette.INK_BODY)

	# ── Header type variations (display face, Task 5) — Task 6 applies
	# `theme_type_variation = "HeaderLarge"/"HeaderMedium"` to title Labels.
	# Both extend "Label" (set_type_variation) so anything they don't
	# override — font_color, notably — falls through to the "Label" entry
	# above rather than needing its own copy. Sizes match the style guide's
	# ladder (titles 20, section headers 17, UI Polish Wave Task P1 — raised
	# from 16/14 so headers don't read as barely-bigger-than-body next to the
	# now-15px default); font_color is set explicitly to INK_TITLE (distinct
	# semantic constant from body's INK_BODY, even though the two currently
	# hold equal values) since titles are exactly what that constant exists
	# for. ──
	theme.set_type_variation(&"HeaderLarge", &"Label")
	theme.set_type_variation(&"HeaderMedium", &"Label")
	var display_font := _load_ui_font(_DISPLAY_FONT_PATH)
	if display_font:
		theme.set_font(&"font", &"HeaderLarge", display_font)
		theme.set_font(&"font", &"HeaderMedium", display_font)
	theme.set_font_size(&"font_size", &"HeaderLarge", 20)
	theme.set_font_size(&"font_size", &"HeaderMedium", 17)
	theme.set_color(&"font_color", &"HeaderLarge", UIPalette.INK_TITLE)
	theme.set_color(&"font_color", &"HeaderMedium", UIPalette.INK_TITLE)

	# ── PanelContainer / notification (self-guarded flat fallback inside) ──
	theme.set_stylebox("panel", "PanelContainer", make_panel_style())
	theme.set_stylebox("panel", "TooltipPanel", _make_tooltip_style())
	theme.set_color("font_color", "TooltipLabel", UIPalette.PARCHMENT)

	# ── ProgressBar — parchment-dark trough + heraldry fill, ink border ──
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = UIPalette.BAR_TROUGH
	pb_bg.border_color = UIPalette.INK_BODY
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(3)
	pb_bg.set_content_margin_all(2)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = UIPalette.BAR_FILL
	pb_fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	# ── Separators — thin inked line ──
	var hsep := StyleBoxFlat.new()
	hsep.bg_color = UIPalette.INK_BODY
	hsep.content_margin_top = 1.0
	hsep.content_margin_bottom = 1.0
	theme.set_stylebox("separator", "HSeparator", hsep)
	var vsep := StyleBoxFlat.new()
	vsep.bg_color = UIPalette.INK_BODY
	vsep.content_margin_left = 1.0
	vsep.content_margin_right = 1.0
	theme.set_stylebox("separator", "VSeparator", vsep)

	# ── Sliders — parchment-dark trough, heraldry grabber-area fill, small
	# heraldry grabber disc (procedural — no bake tool needed for a circle) ──
	var slider_trough := StyleBoxFlat.new()
	slider_trough.bg_color = UIPalette.BAR_TROUGH
	slider_trough.set_corner_radius_all(3)
	slider_trough.content_margin_top = 3.0
	slider_trough.content_margin_bottom = 3.0
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = UIPalette.BAR_FILL
	slider_fill.set_corner_radius_all(3)
	slider_fill.content_margin_top = 3.0
	slider_fill.content_margin_bottom = 3.0
	var grabber_icon := _make_circle_icon(UIPalette.PARCHMENT_ACCENT, 14)
	for slider_type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", slider_type, slider_trough)
		theme.set_stylebox("grabber_area", slider_type, slider_fill)
		theme.set_stylebox("grabber_area_highlight", slider_type, slider_fill)
		theme.set_icon("grabber", slider_type, grabber_icon)
		theme.set_icon("grabber_highlight", slider_type, grabber_icon)
		theme.set_icon("grabber_disabled", slider_type, grabber_icon)

	# ── CheckBox — parchment box + ink check, procedural (same reasoning
	# as the slider grabber: too small to warrant a SubViewport bake).
	# GOTCHA: CheckBox extends Button in Godot's class hierarchy, so with no
	# CheckBox-specific stylebox it falls back to "Button"'s style for its own
	# background — the FULL parchment button texture stretched behind the
	# whole checkbox row, not just a small glyph. Every checkbox row in the
	# game (unit disband/split lists, settings toggles) hardcodes its own
	# light label color for the OLD dark button fallback, so a full parchment
	# CheckBox background is doubly wrong now (unwanted big fill + light text
	# on light fill). Empty styleboxes suppress that fallback; only the
	# checked/unchecked icon glyph draws. ──
	var cb_empty := StyleBoxEmpty.new()
	for cb_state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(cb_state, "CheckBox", cb_empty)
	var check_icon := _make_check_icon(UIPalette.INK_BODY, true)
	var uncheck_icon := _make_check_icon(UIPalette.INK_BODY, false)
	theme.set_icon("checked", "CheckBox", check_icon)
	theme.set_icon("unchecked", "CheckBox", uncheck_icon)
	theme.set_icon("checked_disabled", "CheckBox", check_icon)
	theme.set_icon("unchecked_disabled", "CheckBox", uncheck_icon)

	# ── LineEdit — parchment-dark field, ink border, parchment text ──
	var le_normal := StyleBoxFlat.new()
	le_normal.bg_color = UIPalette.PARCHMENT_DARK
	le_normal.border_color = UIPalette.INK_BODY
	le_normal.set_border_width_all(1)
	le_normal.set_corner_radius_all(3)
	le_normal.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_normal)
	theme.set_color("font_color", "LineEdit", UIPalette.PARCHMENT)
	theme.set_color("caret_color", "LineEdit", UIPalette.PARCHMENT)

	# ── Scrollbars — slim ink grabber on a parchment-dark track ──
	var scroll_track := StyleBoxFlat.new()
	scroll_track.bg_color = UIPalette.PARCHMENT_DARK
	scroll_track.set_corner_radius_all(3)
	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = UIPalette.INK_BODY
	scroll_grabber.set_corner_radius_all(3)
	for scroll_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, scroll_track)
		theme.set_stylebox("grabber", scroll_type, scroll_grabber)
		theme.set_stylebox("grabber_highlight", scroll_type, scroll_grabber)
		theme.set_stylebox("grabber_pressed", scroll_type, scroll_grabber)

	return theme

func _make_chrome_btn_style(tex: Texture2D, pressed := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = _BTN_MARGIN
	s.texture_margin_top = _BTN_MARGIN
	s.texture_margin_right = _BTN_MARGIN
	s.texture_margin_bottom = _BTN_MARGIN
	s.content_margin_left = _BTN_CONTENT.x
	s.content_margin_right = _BTN_CONTENT.z
	s.content_margin_top = _BTN_CONTENT.y + (2.0 if pressed else 0.0)
	s.content_margin_bottom = _BTN_CONTENT.w - (2.0 if pressed else 0.0)
	return s

## Small procedural circle icon (slider grabber) — flat colors at 14px don't
## need a SubViewport bake; a hand-antialiased CPU fill runs fine headless
## (SubViewport capture would not).
func _make_circle_icon(color: Color, diameter: int) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter / 2.0
	var c := Vector2(r, r)
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r - 1.0:
				img.set_pixel(x, y, color)
			elif d <= r:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * (r - d)))
	return ImageTexture.create_from_image(img)

## Small procedural checkbox glyph — ink square outline, filled ink check
## mark on `checked`. Same rationale as _make_circle_icon.
func _make_check_icon(ink: Color, checked: bool, size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var m := 2
	for x in range(m, size - m):
		img.set_pixel(x, m, ink)
		img.set_pixel(x, size - m - 1, ink)
	for y in range(m, size - m):
		img.set_pixel(m, y, ink)
		img.set_pixel(size - m - 1, y, ink)
	if checked:
		for i in range(m + 2, size - m - 2):
			img.set_pixel(i, i, ink)
			if i + 1 < size - m:
				img.set_pixel(i + 1, i, ink)
	return ImageTexture.create_from_image(img)

func _make_tooltip_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UIPalette.CHIP_BG
	s.border_color = UIPalette.CHIP_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	return s

## Creates a panel style from the current chrome set's baked frame. Falls
## back to a flat style if no frame texture (neither `chrome_set_id` nor
## neutral) could be loaded — a checkout with no generated PNGs still runs.
func make_panel_style() -> StyleBox:
	if _frame_texture == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.08, 0.07, 0.1, 0.95)
		flat.border_color = Color(0.55, 0.42, 0.2, 0.8)
		flat.set_border_width_all(2)
		flat.set_corner_radius_all(6)
		flat.set_content_margin_all(12)
		return flat
	var s := StyleBoxTexture.new()
	s.texture = _frame_texture
	s.texture_margin_left = _FRAME_MARGIN
	s.texture_margin_top = _FRAME_MARGIN
	s.texture_margin_right = _FRAME_MARGIN
	s.texture_margin_bottom = _FRAME_MARGIN
	s.content_margin_left = _FRAME_CONTENT.x
	s.content_margin_top = _FRAME_CONTENT.y
	s.content_margin_right = _FRAME_CONTENT.z
	s.content_margin_bottom = _FRAME_CONTENT.w
	return s

## Creates the ornate notification style from the current chrome set's baked
## notification frame (doubled border + top-center seal). Falls back to
## make_panel_style() if missing.
func make_notification_style() -> StyleBox:
	if _notif_texture == null:
		return make_panel_style()
	var s := StyleBoxTexture.new()
	s.texture = _notif_texture
	s.texture_margin_left = _NOTIF_MARGIN
	s.texture_margin_top = _NOTIF_MARGIN
	s.texture_margin_right = _NOTIF_MARGIN
	s.texture_margin_bottom = _NOTIF_MARGIN
	s.content_margin_left = _NOTIF_CONTENT.x
	s.content_margin_top = _NOTIF_CONTENT.y
	s.content_margin_right = _NOTIF_CONTENT.z
	s.content_margin_bottom = _NOTIF_CONTENT.w
	return s

# ── Resource icons (generated by tests/tools_generate_resource_icons.gd) ──
# Shared everywhere a resource amount is shown: top bar, cost rows, tooltips.
const RESOURCE_ICON_NAMES := {0: "res_gold", 1: "res_iron", 2: "res_tech", 3: "res_food", 4: "res_shards", 5: "res_wood", 6: "res_captives"}
var _resource_icon_cache: Dictionary = {}

func get_resource_icon(res_type: int) -> Texture2D:
	if _resource_icon_cache.has(res_type):
		return _resource_icon_cache[res_type]
	var path := "res://assets/sprites/ui/icons/%s.png" % RESOURCE_ICON_NAMES.get(res_type, "res_gold")
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_resource_icon_cache[res_type] = tex
	return tex

func make_resource_icon(res_type: int, size := 16.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = get_resource_icon(res_type)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

const TIME_ICON_PATH := "res://assets/sprites/ui/icons/res_time.png"

func get_time_icon() -> Texture2D:
	if _resource_icon_cache.has(&"time"):
		return _resource_icon_cache[&"time"]
	var tex: Texture2D = load(TIME_ICON_PATH) if ResourceLoader.exists(TIME_ICON_PATH) else null
	_resource_icon_cache[&"time"] = tex
	return tex

## Icon + amount row for costs/incomes — replaces "200 Gold, 30 Iron" text.
## With `compare` (current resources) amounts color green/red by
## affordability; `signed` renders "+N" in income green; `turns` > 0 appends
## an hourglass + turn count. `on_light` picks the ink-dark text variant
## instead of the default light-parchment one — pass true when the row sits
## directly on a light chrome surface (e.g. inside make_cost_button, which
## draws straight on the button's parchment/heraldry fill, not a dark chip);
## default false preserves the light-on-dark-chip look every other call site
## (dialogs' chip-wrapped vboxes, per docs/ui_style_guide.md) already expects.
func make_cost_row(cost: Dictionary, compare: Dictionary = {}, font_size := 12, prefix := "", signed := false, turns := 0, on_light := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var base_col := UIPalette.INK_BODY if on_light else Color(UIPalette.PARCHMENT.r, UIPalette.PARCHMENT.g, UIPalette.PARCHMENT.b, 0.85)
	var dim_col := Color(base_col.r, base_col.g, base_col.b, 0.75)
	if prefix != "":
		var pl := Label.new()
		pl.text = prefix
		pl.add_theme_font_size_override("font_size", font_size)
		pl.add_theme_color_override("font_color", dim_col)
		row.add_child(pl)
	var icon_px := float(font_size) + 8.0
	for res_type in cost:
		var amount: int = cost[res_type]
		if amount == 0:
			continue
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 2)
		pair.add_child(make_resource_icon(res_type, icon_px))
		var lbl := Label.new()
		lbl.text = ("+%d" % amount) if signed and amount > 0 else str(amount)
		lbl.add_theme_font_size_override("font_size", font_size)
		var col := base_col
		if not compare.is_empty():
			col = UIPalette.SUCCESS if int(compare.get(res_type, 0)) >= amount else UIPalette.DANGER
		elif signed:
			col = UIPalette.SUCCESS if amount > 0 else UIPalette.DANGER
		lbl.add_theme_color_override("font_color", col)
		pair.add_child(lbl)
		row.add_child(pair)
	if turns > 0:
		var tpair := HBoxContainer.new()
		tpair.add_theme_constant_override("separation", 2)
		var ticon := TextureRect.new()
		ticon.texture = get_time_icon()
		ticon.custom_minimum_size = Vector2(icon_px, icon_px)
		ticon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ticon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ticon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tpair.add_child(ticon)
		var tlbl := Label.new()
		tlbl.text = str(turns)
		tlbl.add_theme_font_size_override("font_size", font_size)
		tlbl.add_theme_color_override("font_color", dim_col)
		tpair.add_child(tlbl)
		row.add_child(tpair)
	return row

## BBCode variant for RichTextLabels (building cards, tooltips).
func cost_bbcode(cost: Dictionary, compare: Dictionary = {}, icon_px := 16) -> String:
	var parts: Array[String] = []
	for res_type in cost:
		var amount: int = cost[res_type]
		if amount == 0:
			continue
		var color := "d9ccae"
		if not compare.is_empty():
			color = "66cc66" if int(compare.get(res_type, 0)) >= amount else "cc4444"
		var path := "res://assets/sprites/ui/icons/%s.png" % RESOURCE_ICON_NAMES.get(res_type, "res_gold")
		parts.append("[img=%d]%s[/img][color=#%s]%d[/color]" % [icon_px, path, color, amount])
	return "  ".join(parts)

## Hourglass + turn count for RichTextLabels ("3t" replacements).
func time_bbcode(turns: int, icon_px := 16) -> String:
	return "[img=%d]%s[/img][color=#bfb89e]%d[/color]" % [icon_px, TIME_ICON_PATH, turns]

## Button with an icon cost row inside — for actions whose label used to
## spell costs as text ("Found Settlement (80 Gold, 40 Wood)").
func make_cost_button(title: String, cost: Dictionary, turns := 0, compare: Dictionary = {}, font_size := 13, extra_text := "") -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, float(font_size) + 22.0)
	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", font_size)
	title_lbl.add_theme_color_override("font_color", UIPalette.INK_BODY)
	content.add_child(title_lbl)
	if not cost.is_empty() or turns > 0:
		var row := make_cost_row(cost, compare, font_size - 1, "", false, turns, true)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(row)
	var extra_lbl: Label = null
	if extra_text != "":
		extra_lbl = Label.new()
		extra_lbl.text = extra_text
		extra_lbl.add_theme_font_size_override("font_size", font_size - 2)
		extra_lbl.add_theme_color_override("font_color", UIPalette.INK_BODY)
		content.add_child(extra_lbl)
	btn.add_child(content)
	# This label sits directly on the button's own fill, not a themed Button's
	# internal text — it doesn't get the Button theme's automatic per-state
	# font color swap, so wire the pressed state by hand: pressed uses the
	# heraldry fill (dark for several factions), so the dark-ink title needs
	# to flip to light parchment text while held (mirrors font_pressed_color
	# on regular themed buttons).
	btn.button_down.connect(func():
		title_lbl.add_theme_color_override("font_color", UIPalette.PARCHMENT)
		if extra_lbl:
			extra_lbl.add_theme_color_override("font_color", UIPalette.PARCHMENT)
	)
	btn.button_up.connect(func():
		title_lbl.add_theme_color_override("font_color", UIPalette.INK_BODY)
		if extra_lbl:
			extra_lbl.add_theme_color_override("font_color", UIPalette.INK_BODY)
	)
	return btn

var _compact_theme: Theme

## Compact HUD theme: same generated parchment chrome as the global theme but
## pre-scaled to 25%, so the nine-patch border is ~6px instead of ~24px and
## content margins suit dense fixed-size panels (battle HUD, overlays). Reads
## _frame_texture/_btn_texture* set by the last _build_theme_for_set() call
## (boot -> neutral; Task 4's apply_faction_theme -> the active faction), so
## switching factions and calling get_compact_theme() again (after nulling
## _compact_theme) picks up the new set automatically.
##
## GOTCHA (found during the Task 3 windowed sweep, corrected/generalized in
## Task 8's coherence pass): once a Control's own `.theme` is set, Godot
## resolves EVERY theme property for that Control's whole subtree from THAT
## theme alone (with normal within-theme fallback: type variation -> class
## hierarchy, e.g. CheckBox -> Button) — it does NOT continue climbing to an
## ancestor Control's separate Theme resource for a type or property the
## nearer theme leaves unset, even one it doesn't mention AT ALL. Anything
## missing here falls straight to Godot's built-in engine default instead
## (~0.875 grey text; a flat neutral-grey ProgressBar/slider/separator/
## scrollbar). The whole campaign HUD subtree runs under this compact theme
## (docs/ui_style_guide.md) via `theme = get_compact_theme()` on the HUD
## Control itself, so EVERY type/property set on ANYTHING in
## _build_theme_for_set (Button colors, Label, ProgressBar, HSeparator/
## VSeparator, HSlider/VSlider, LineEdit, VScrollBar/HScrollBar, ...) must be
## mirrored here too, or compact-themed controls of that type silently lose
## their styling — confirmed empirically (a live theme-resolution probe on a
## Victory-panel ProgressBar) after screenshots showed one rendering as
## Godot's stock flat grey instead of BAR_TROUGH/BAR_FILL despite a code
## comment asserting it "cascades to root".
##
## Font mirroring (Task 5): default_font/default_font_size ARE Theme-level
## fallbacks (unlike colors, which have no such in-Theme fallback), so they
## apply to every type this theme claims — including Button — without needing
## a per-type override. Still set here explicitly (not just left to inherit)
## because Button is claimed the same way font_color is: if this theme were
## ever built before body_font/UIPalette are ready, silently falling to
## Godot's stock font would be a much quieter failure than an explicit call
## site.
##
## UI Polish Wave Task P1: mirrors _build_theme_for_set's 15px body/Button
## size verbatim rather than scaling it down further — this theme is already
## the "compact" (4x-shrunk chrome) skin, not a second size reduction, and the
## designer complaint driving this task ("small text and a large box looks
## bad") applies just as much to dense HUD panels as the root theme. Individual
## dense/secondary call sites in campaign_hud.gd/campaign.gd (tooltips, badge
## numerals, cost-row captions) keep their own smaller font_size overrides —
## style guide floor for those is 12px (was 10px), not enforced here since
## this function only sets the theme-wide default, not per-call overrides.
func get_compact_theme() -> Theme:
	if _compact_theme:
		return _compact_theme
	var theme := Theme.new()
	var body_font := _load_ui_font(_BODY_FONT_PATH)
	if body_font:
		theme.default_font = body_font
	theme.default_font_size = 15
	theme.set_font_size("font_size", "Button", 15)
	theme.set_color("font_color", "Button", UIPalette.INK_BODY)
	theme.set_color("font_hover_color", "Button", UIPalette.INK_TITLE)
	theme.set_color("font_pressed_color", "Button", UIPalette.PARCHMENT)
	theme.set_color("font_disabled_color", "Button", Color(UIPalette.INK_BODY.r, UIPalette.INK_BODY.g, UIPalette.INK_BODY.b, 0.55))
	# CheckBox falls back to this theme's Button styles too (see the
	# _build_theme_for_set gotcha note) — same empty-stylebox suppression,
	# mirrored here so compact-themed checkbox rows (unit disband/split
	# lists) don't inherit the full parchment button background either.
	var cb_empty := StyleBoxEmpty.new()
	for cb_state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(cb_state, "CheckBox", cb_empty)
	var check_icon := _make_check_icon(UIPalette.INK_BODY, true)
	var uncheck_icon := _make_check_icon(UIPalette.INK_BODY, false)
	theme.set_icon("checked", "CheckBox", check_icon)
	theme.set_icon("unchecked", "CheckBox", uncheck_icon)
	theme.set_icon("checked_disabled", "CheckBox", check_icon)
	theme.set_icon("unchecked_disabled", "CheckBox", uncheck_icon)
	theme.set_color("font_color", "Label", UIPalette.INK_BODY)
	# Task 8 coherence pass — root-caused a real bug found via the Victory
	# panel's progress bars rendering as Godot's built-in flat neutral-grey
	# default (bg (0.1,0.1,0.1,0.3) / fill (1.0,1.0,1.0,0.4), confirmed via a
	# live theme-resolution probe) instead of the themed BAR_TROUGH/BAR_FILL.
	# The "cascades to root for the unclaimed type" comments on the root-theme
	# ProgressBar/HSlider/audio_manager.gd's slider factory were WRONG: once
	# a Control's own `.theme` is set (HUD's is, to this function's result),
	# Godot resolves EVERY theme property from THAT theme alone — for a type
	# this theme never mentions at all, same as one it only partially defines
	# (the Button/CheckBox "claiming" gotcha already documented above) — and
	# falls straight to the engine default rather than continuing up to the
	# root theme. Mirroring every remaining root-theme type here (same
	# UIPalette-sourced recipe as _build_theme_for_set, unscaled — like
	# CheckBox's icon above, these are small procedural/flat styleboxes, not
	# baked textures, so no 4x compact-scale math applies) fixes ALL of them
	# at once: ProgressBar (Victory conditions, confirmed broken), separators
	# (76 `_add_separator()` call sites), sliders (the in-game Options panel
	# reached via the HUD's own Options button runs under THIS theme), and
	# scrollbars (22 ScrollContainers). LineEdit has zero call sites in
	# campaign_hud.gd today but is mirrored anyway for the same reason the
	# landmine comment above warns about: whichever type list drifts out of
	# sync between the two builders next silently regresses.
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = UIPalette.BAR_TROUGH
	pb_bg.border_color = UIPalette.INK_BODY
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(3)
	pb_bg.set_content_margin_all(2)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = UIPalette.BAR_FILL
	pb_fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)
	var hsep := StyleBoxFlat.new()
	hsep.bg_color = UIPalette.INK_BODY
	hsep.content_margin_top = 1.0
	hsep.content_margin_bottom = 1.0
	theme.set_stylebox("separator", "HSeparator", hsep)
	var vsep := StyleBoxFlat.new()
	vsep.bg_color = UIPalette.INK_BODY
	vsep.content_margin_left = 1.0
	vsep.content_margin_right = 1.0
	theme.set_stylebox("separator", "VSeparator", vsep)
	var slider_trough := StyleBoxFlat.new()
	slider_trough.bg_color = UIPalette.BAR_TROUGH
	slider_trough.set_corner_radius_all(3)
	slider_trough.content_margin_top = 3.0
	slider_trough.content_margin_bottom = 3.0
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = UIPalette.BAR_FILL
	slider_fill.set_corner_radius_all(3)
	slider_fill.content_margin_top = 3.0
	slider_fill.content_margin_bottom = 3.0
	var grabber_icon := _make_circle_icon(UIPalette.PARCHMENT_ACCENT, 14)
	for slider_type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", slider_type, slider_trough)
		theme.set_stylebox("grabber_area", slider_type, slider_fill)
		theme.set_stylebox("grabber_area_highlight", slider_type, slider_fill)
		theme.set_icon("grabber", slider_type, grabber_icon)
		theme.set_icon("grabber_highlight", slider_type, grabber_icon)
		theme.set_icon("grabber_disabled", slider_type, grabber_icon)
	var le_normal := StyleBoxFlat.new()
	le_normal.bg_color = UIPalette.PARCHMENT_DARK
	le_normal.border_color = UIPalette.INK_BODY
	le_normal.set_border_width_all(1)
	le_normal.set_corner_radius_all(3)
	le_normal.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_normal)
	theme.set_color("font_color", "LineEdit", UIPalette.PARCHMENT)
	theme.set_color("caret_color", "LineEdit", UIPalette.PARCHMENT)
	var scroll_track := StyleBoxFlat.new()
	scroll_track.bg_color = UIPalette.PARCHMENT_DARK
	scroll_track.set_corner_radius_all(3)
	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = UIPalette.INK_BODY
	scroll_grabber.set_corner_radius_all(3)
	for scroll_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, scroll_track)
		theme.set_stylebox("grabber", scroll_type, scroll_grabber)
		theme.set_stylebox("grabber_highlight", scroll_type, scroll_grabber)
		theme.set_stylebox("grabber_pressed", scroll_type, scroll_grabber)
	if _frame_texture:
		var frame_tex := _scaled_image_texture(_frame_texture, 4)
		var panel := StyleBoxTexture.new()
		panel.texture = frame_tex
		panel.texture_margin_left = _FRAME_MARGIN / 4.0
		panel.texture_margin_top = _FRAME_MARGIN / 4.0
		panel.texture_margin_right = _FRAME_MARGIN / 4.0
		panel.texture_margin_bottom = _FRAME_MARGIN / 4.0
		panel.content_margin_left = _FRAME_CONTENT.x / 4.0
		panel.content_margin_top = _FRAME_CONTENT.y / 4.0
		panel.content_margin_right = _FRAME_CONTENT.z / 4.0
		panel.content_margin_bottom = _FRAME_CONTENT.w / 4.0
		theme.set_stylebox("panel", "PanelContainer", panel)
	if _btn_texture:
		var btn_tex := _scaled_image_texture(_btn_texture, 4)
		var hover_tex := _scaled_image_texture(_btn_hover_texture if _btn_hover_texture else _btn_texture, 4)
		var pressed_tex := _scaled_image_texture(_btn_pressed_texture if _btn_pressed_texture else _btn_texture, 4)
		var disabled_tex := _scaled_image_texture(_btn_disabled_texture if _btn_disabled_texture else _btn_texture, 4)
		theme.set_stylebox("normal", "Button", _make_compact_btn_style(btn_tex))
		theme.set_stylebox("hover", "Button", _make_compact_btn_style(hover_tex))
		theme.set_stylebox("pressed", "Button", _make_compact_btn_style(pressed_tex, true))
		theme.set_stylebox("disabled", "Button", _make_compact_btn_style(disabled_tex))
		theme.set_stylebox("focus", "Button", _make_compact_btn_style(hover_tex))
	_compact_theme = theme
	return _compact_theme

func _make_compact_btn_style(tex: Texture2D, pressed := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = _BTN_MARGIN / 4.0
	s.texture_margin_top = _BTN_MARGIN / 4.0
	s.texture_margin_right = _BTN_MARGIN / 4.0
	s.texture_margin_bottom = _BTN_MARGIN / 4.0
	s.content_margin_left = _BTN_CONTENT.x / 4.0
	s.content_margin_right = _BTN_CONTENT.z / 4.0
	s.content_margin_top = _BTN_CONTENT.y / 4.0 + (1.0 if pressed else 0.0)
	s.content_margin_bottom = _BTN_CONTENT.w / 4.0 - (1.0 if pressed else 0.0)
	return s

func _scaled_image_texture(tex: Texture2D, div: int) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() / div, img.get_height() / div, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

# Minor faction → parent faction mapping
const MINOR_FACTION_PARENTS := {
	&"crimson_legion": &"empire", &"aurentis_guard": &"empire",
	&"thornwardens": &"gladehost", &"miststriders": &"gladehost",
	&"obsidian_order": &"moonspear", &"luminarch": &"moonspear",
	&"stormbound": &"thunderswarm", &"skalvar_watch": &"thunderswarm",
	&"twilight_veil": &"tainted_jade", &"jade_conclave": &"tainted_jade",
	&"gorgonic_cult": &"ivoryscar", &"servants_of_reliquary": &"ivoryscar",
	&"salt_reavers": &"skulloath", &"ashbound": &"skulloath",
	&"crownfire": &"cinderguard", &"valkarn_garrison": &"cinderguard",
	&"bloodthrone": &"forsaken", &"blightcoven": &"forsaken",
	&"icebound": &"shardhorde", &"splinterbrood": &"shardhorde",
	&"oaseans": &"sunblessed", &"venerated": &"sunblessed",
}

# Nomadic factions don't get cities — they roam or use elderbeasts
const NOMADIC_FACTIONS := [&"shardhorde", &"icebound", &"splinterbrood", &"sunblessed", &"oaseans", &"venerated"]

# ── Region → 3 cities each (81 cities total) ──────────────────
const REGION_CITIES := {
	# ── Empire Culture ──
	&"eternal_plains": [
		{name = "Aurelion", offset = Vector2i(-4, -4)},
		{name = "Marcellum", offset = Vector2i(4, 0)},
		{name = "Goldsward", offset = Vector2i(-1, 5)},
	],
	&"sunburst_valley": [
		{name = "Dawnhold", offset = Vector2i(-4, -3)},
		{name = "Solarius", offset = Vector2i(4, 3)},
		{name = "Cinderfall Keep", offset = Vector2i(0, 7)},
	],
	&"aurentis": [
		{name = "Aurentis Prime", offset = Vector2i(0, -4)},
		{name = "Goldwatch", offset = Vector2i(4, 3)},
		{name = "Whitegate", offset = Vector2i(-4, 4)},
	],
	# ── Gladehost Culture ──
	&"sainkhu_groves": [
		{name = "Heartwood", offset = Vector2i(-4, -3)},
		{name = "Willowmere", offset = Vector2i(4, 0)},
		{name = "Roothollow", offset = Vector2i(0, 5)},
	],
	&"verdant_glade": [
		{name = "Tidewrack", offset = Vector2i(-3, -4)},
		{name = "Mangrove Haven", offset = Vector2i(4, 3)},
		{name = "Corsair's Reach", offset = Vector2i(-4, 4)},
	],
	&"orisyl": [
		{name = "Orisyl Canopy", offset = Vector2i(0, -4)},
		{name = "Dewspring", offset = Vector2i(4, 3)},
		{name = "Thornveil", offset = Vector2i(-4, 4)},
	],
	# ── Moonspear Culture ──
	&"iskar": [
		{name = "Iskar Citadel", offset = Vector2i(0, -4)},
		{name = "Moonwell", offset = Vector2i(4, 3)},
		{name = "Silver Archive", offset = Vector2i(-4, 4)},
	],
	&"nightfall_sanctum": [
		{name = "Obsidian Gate", offset = Vector2i(-4, -3)},
		{name = "Twilight Spire", offset = Vector2i(4, 0)},
		{name = "Sanctum Depths", offset = Vector2i(0, 5)},
	],
	&"asdrol": [
		{name = "Asdrol Haven", offset = Vector2i(0, -4)},
		{name = "Luminar Watch", offset = Vector2i(4, 3)},
		{name = "Pilgrim's Rest", offset = Vector2i(-4, 4)},
	],
	# ── Thunderswarm Culture ──
	&"dragonspire_mountains": [
		{name = "Stormforge", offset = Vector2i(-4, -3)},
		{name = "Thunder Keep", offset = Vector2i(4, 0)},
		{name = "Wyrmhold", offset = Vector2i(0, 5)},
	],
	&"thundercrest_peaks": [
		{name = "Thundercrest", offset = Vector2i(0, -4)},
		{name = "Galewatch", offset = Vector2i(4, 3)},
		{name = "Stonehorn", offset = Vector2i(-4, 4)},
	],
	&"skalvar": [
		{name = "Skalvar Hall", offset = Vector2i(-3, -4)},
		{name = "Ironpeak", offset = Vector2i(4, 3)},
		{name = "Windbreak", offset = Vector2i(-4, 4)},
	],
	# ── Tainted Jade Culture ──
	&"coatlantli": [
		{name = "Coatlantli", offset = Vector2i(0, -4)},
		{name = "Jade Fang Temple", offset = Vector2i(4, 3)},
		{name = "Serpent Pool", offset = Vector2i(-4, 5)},
	],
	&"southern_reach": [
		{name = "Xalapa", offset = Vector2i(-4, -3)},
		{name = "Emerald Port", offset = Vector2i(4, 0)},
		{name = "Thornmarsh", offset = Vector2i(0, 5)},
	],
	&"xotchi": [
		{name = "Xotchi Sanctuary", offset = Vector2i(0, -4)},
		{name = "Bloomheart", offset = Vector2i(4, 3)},
		{name = "Fungal Hollow", offset = Vector2i(-4, 4)},
	],
	# ── Skulloath Culture ──
	&"bataarbad": [
		{name = "Bataarbad", offset = Vector2i(-4, -3)},
		{name = "Bonecairn", offset = Vector2i(4, 0)},
		{name = "Dreadcamp", offset = Vector2i(0, 5)},
	],
	&"altaban": [
		{name = "Thornwatch", offset = Vector2i(0, -4)},
		{name = "Rootspire", offset = Vector2i(4, 3)},
		{name = "Verdant Hall", offset = Vector2i(-4, 4)},
	],
	&"tsagan": [
		{name = "Tsagan Camp", offset = Vector2i(-3, -4)},
		{name = "Ashbone", offset = Vector2i(4, 3)},
		{name = "Wailing Flats", offset = Vector2i(-4, 4)},
	],
	# ── Cinderguard Culture ──
	&"duststorm_valley": [
		{name = "Emberhold", offset = Vector2i(-4, -3)},
		{name = "Cinderwatch", offset = Vector2i(4, 0)},
		{name = "Furnace Gate", offset = Vector2i(0, 5)},
	],
	&"ashenmark": [
		{name = "Ashenmark Forge", offset = Vector2i(0, -4)},
		{name = "Crownfire Bastion", offset = Vector2i(4, 3)},
		{name = "Slagtown", offset = Vector2i(-4, 4)},
	],
	&"valkarn": [
		{name = "Valkarn Garrison", offset = Vector2i(-3, -4)},
		{name = "Molten Gate", offset = Vector2i(4, 3)},
		{name = "Sparkhaven", offset = Vector2i(-4, 4)},
	],
	# ── Forsaken Culture ──
	&"orenthal": [
		{name = "Orenthal Ruins", offset = Vector2i(-4, -3)},
		{name = "Blightspire", offset = Vector2i(4, 0)},
		{name = "Carrion Hold", offset = Vector2i(0, 5)},
	],
	&"morvane": [
		{name = "Morvane Citadel", offset = Vector2i(0, -4)},
		{name = "Bloodthrone Keep", offset = Vector2i(4, 3)},
		{name = "Rotmere", offset = Vector2i(-4, 4)},
	],
	&"weeping_barrows": [
		{name = "Barrow Gate", offset = Vector2i(-3, -4)},
		{name = "Blighthollow", offset = Vector2i(4, 3)},
		{name = "Gravemist", offset = Vector2i(-4, 4)},
	],
	# ── Ivoryscar Culture ──
	&"qareth": [
		{name = "Qareth Spire", offset = Vector2i(-4, -3)},
		{name = "Gorgon's Eye", offset = Vector2i(4, 0)},
		{name = "Petrified Gate", offset = Vector2i(0, 5)},
	],
	&"torgalun_desert": [
		{name = "Torgalun", offset = Vector2i(0, -4)},
		{name = "Sand Shrine", offset = Vector2i(4, 3)},
		{name = "Dustwalker Camp", offset = Vector2i(-4, 4)},
	],
	&"whispering_dunes": [
		{name = "Relic Court", offset = Vector2i(-3, -4)},
		{name = "Whisper Gate", offset = Vector2i(4, 3)},
		{name = "Ossuary", offset = Vector2i(-4, 4)},
	],
}

# ── Region → Culture mapping (geographic cultures) ───────────
const REGION_CULTURE := {
	&"iskar": &"frostlands", &"asdrol": &"frostlands", &"nightfall_sanctum": &"frostlands",
	&"dragonspire_mountains": &"storm_peaks", &"thundercrest_peaks": &"storm_peaks", &"skalvar": &"storm_peaks",
	&"verdant_glade": &"western_marches", &"aurentis": &"western_marches", &"sainkhu_groves": &"western_marches",
	&"eternal_plains": &"imperial_heartland", &"sunburst_valley": &"imperial_heartland", &"valkarn": &"imperial_heartland",
	&"duststorm_valley": &"ashlands", &"ashenmark": &"ashlands", &"morvane": &"ashlands",
	&"bataarbad": &"central_steppe", &"altaban": &"central_steppe", &"tsagan": &"central_steppe",
	&"coatlantli": &"emerald_south", &"orisyl": &"emerald_south", &"xotchi": &"emerald_south",
	&"southern_reach": &"southern_reaches", &"orenthal": &"southern_reaches", &"torgalun_desert": &"southern_reaches",
	&"whispering_dunes": &"eastern_wastes", &"weeping_barrows": &"eastern_wastes", &"qareth": &"eastern_wastes",
}

# ── Culture → Regions mapping ─────────────────────────────────
const CULTURE_REGIONS := {
	&"frostlands": [&"iskar", &"asdrol", &"nightfall_sanctum"],
	&"storm_peaks": [&"dragonspire_mountains", &"thundercrest_peaks", &"skalvar"],
	&"western_marches": [&"verdant_glade", &"aurentis", &"sainkhu_groves"],
	&"imperial_heartland": [&"eternal_plains", &"sunburst_valley", &"valkarn"],
	&"ashlands": [&"duststorm_valley", &"ashenmark", &"morvane"],
	&"central_steppe": [&"bataarbad", &"altaban", &"tsagan"],
	&"emerald_south": [&"coatlantli", &"orisyl", &"xotchi"],
	&"southern_reaches": [&"southern_reach", &"orenthal", &"torgalun_desert"],
	&"eastern_wastes": [&"whispering_dunes", &"weeping_barrows", &"qareth"],
}

# ── Culture completion bonuses ────────────────────────────────
const CULTURE_BONUSES := {
	&"frostlands":        {type = "tech_bonus", value = 0.25, desc = "Frozen Wisdom: +25% technology"},
	&"storm_peaks":       {type = "movement_bonus", value = 1.0, desc = "Storm March: +1 army movement"},
	&"western_marches":   {type = "food_bonus", value = 0.30, desc = "Verdant Bounty: +30% food production"},
	&"imperial_heartland": {type = "upkeep_reduction", value = 0.20, desc = "Imperial Dominion: -20% unit upkeep"},
	&"ashlands":          {type = "iron_bonus", value = 0.30, desc = "Ashen Veins: +30% iron production"},
	&"central_steppe":    {type = "combat_damage", value = 0.15, desc = "Steppe Fury: +15% combat damage"},
	&"emerald_south":     {type = "population_growth", value = 0.30, desc = "Jungle Vitality: +30% population growth"},
	&"southern_reaches":  {type = "building_cost_reduction", value = 0.25, desc = "Ruinlore: -25% building costs"},
	&"eastern_wastes":    {type = "shard_bonus", value = 0.25, desc = "Petrified Wisdom: +25% shard essence"},
}

# ── Faction leader names ──────────────────────────────────────
var FACTION_LEADER_NAMES := {
	&"empire": "Emperor Aurelian III",
	&"gladehost": "Archdruid Thalwen",
	&"moonspear": "High Priestess Selara",
	&"thunderswarm": "Warchief Groth",
	&"tainted_jade": "Serpent Queen Ixchala",
	&"skulloath": "Khan Borlag",
	&"cinderguard": "Warden-Commander Valdris",
	&"forsaken": "Countess Neshara",
	&"ivoryscar": "Oracle Medusa",
	&"shardhorde": "The Crystalmind",
	&"sunblessed": "Solar Archon Kael",
}

# ── Faction dialogue ──────────────────────────────────────────
const FACTION_DIALOGUE := {
	&"empire": {
		"greeting_friendly": "The Empire remembers its friends. What do you seek?",
		"greeting_hostile": "You dare approach the throne? Speak quickly.",
		"greeting_neutral": "State your business with the Empire.",
		"greeting_war": "Your audacity knows no bounds. Speak before we silence you.",
		"accept_trade": "The Empire's coffers benefit from fair trade.",
		"reject_trade": "These terms insult the Crown. Leave.",
		"accept_alliance": "Together we shall bring order to this fractured world.",
		"reject_alliance": "The Empire does not ally with the weak.",
		"accept_peace": "Very well. The Empire grants you respite... for now.",
		"reject_peace": "Your armies burn. There will be no peace.",
		"war_declared": "So be it. The legions march.",
		"threatened": "You would threaten the Empire? Bold... and foolish.",
	},
	&"gladehost": {
		"greeting_friendly": "The forest welcomes you, kindred spirit.",
		"greeting_hostile": "The roots remember your transgressions.",
		"greeting_neutral": "The grove listens. Speak.",
		"greeting_war": "You have disturbed the balance. Nature will correct this.",
		"accept_trade": "A fair exchange nourishes both sides.",
		"reject_trade": "The forest has no need of your trinkets.",
		"accept_alliance": "Our roots intertwine. We grow stronger together.",
		"reject_alliance": "The grove stands alone for now.",
		"accept_peace": "Let the land heal. We accept your peace.",
		"reject_peace": "The thorns will not be withdrawn.",
		"war_declared": "You have awoken the wrath of the wild.",
		"threatened": "Storms break upon ancient oaks. We do not bend.",
	},
	&"moonspear": {
		"greeting_friendly": "The moon smiles upon your visit, friend.",
		"greeting_hostile": "The stars foretold your coming... and your failure.",
		"greeting_neutral": "What guidance do you seek from the moon?",
		"greeting_war": "The divine light shall burn away your darkness.",
		"accept_trade": "The temple accepts this exchange in good faith.",
		"reject_trade": "The stars counsel against this arrangement.",
		"accept_alliance": "By moonlight we are bound. Our fates intertwine.",
		"reject_alliance": "The moon has not yet aligned for such a pact.",
		"accept_peace": "Let there be peace under the moon's gaze.",
		"reject_peace": "The divine mandate demands your submission.",
		"war_declared": "The moonspear shall pierce your heart.",
		"threatened": "We serve a higher power. Your threats are empty.",
	},
	&"thunderswarm": {
		"greeting_friendly": "Ha! A worthy ally approaches! Come, drink with us!",
		"greeting_hostile": "You smell of weakness. State your purpose.",
		"greeting_neutral": "The storms care not for pleasantries. Speak.",
		"greeting_war": "Your skull will join our collection.",
		"accept_trade": "Iron and gold flow like mountain rivers. Agreed.",
		"reject_trade": "Bah! Insulting terms. Begone.",
		"accept_alliance": "Together we are the storm! None shall stand before us!",
		"reject_alliance": "We fight our own battles. Ask again when you prove yourself.",
		"accept_peace": "The storm passes. For now.",
		"reject_peace": "THUNDER DOES NOT NEGOTIATE!",
		"war_declared": "STOOOOORM! The warhorns sound!",
		"threatened": "You threaten the storm? HAH! Amusing.",
	},
	&"tainted_jade": {
		"greeting_friendly": "The serpent coils gently for those it favors.",
		"greeting_hostile": "Careful where you tread. The jungle has teeth.",
		"greeting_neutral": "The jade throne acknowledges your presence.",
		"greeting_war": "Your blood will feed the jungle.",
		"accept_trade": "The serpent accepts. An equitable exchange.",
		"reject_trade": "You offer poison disguised as honey. Denied.",
		"accept_alliance": "Our venom and your strength... a potent combination.",
		"reject_alliance": "The jungle does not share its secrets lightly.",
		"accept_peace": "The serpent releases its prey... this time.",
		"reject_peace": "The jungle remembers every wound.",
		"war_declared": "The serpent strikes without warning.",
		"threatened": "Threaten us? The jungle laughs.",
	},
	&"skulloath": {
		"greeting_friendly": "You ride with honor. The horde respects this.",
		"greeting_hostile": "Your bones will decorate our standards.",
		"greeting_neutral": "Speak, outsider. The Khan listens.",
		"greeting_war": "The steppe will swallow your armies whole.",
		"accept_trade": "The caravan routes open. A fair exchange.",
		"reject_trade": "The Khan spits on your offer.",
		"accept_alliance": "Blood brothers! Together, the world trembles!",
		"reject_alliance": "The horde rides alone.",
		"accept_peace": "The raids cease. Your tribute is noted.",
		"reject_peace": "Peace is for the dead!",
		"war_declared": "The skull banner rises! War!",
		"threatened": "Threaten the horde? Your courage exceeds your wisdom.",
	},
	&"cinderguard": {
		"greeting_friendly": "The forges burn bright for allies. Welcome.",
		"greeting_hostile": "You stand in the shadow of the furnace. Choose wisely.",
		"greeting_neutral": "The Forgemaster has a moment. Make it count.",
		"greeting_war": "The furnace consumes all. You will be no different.",
		"accept_trade": "Iron meets iron. A solid deal.",
		"reject_trade": "Slag. Worthless. Leave my forge.",
		"accept_alliance": "Forged together, we are unbreakable.",
		"reject_alliance": "The forge needs no additional fuel.",
		"accept_peace": "The coals cool. Peace is granted.",
		"reject_peace": "The furnace does not forgive.",
		"war_declared": "The forge-fires of war are stoked.",
		"threatened": "Threaten the forge? You'll melt before us.",
	},
	&"forsaken": {
		"greeting_friendly": "Even in darkness, some lights are... tolerable.",
		"greeting_hostile": "Your presence offends what remains of our senses.",
		"greeting_neutral": "The Countess deigns to listen. Briefly.",
		"greeting_war": "All things end. Your time has come.",
		"accept_trade": "Even the dead have use for the living's trinkets.",
		"reject_trade": "We have no need of your pittance.",
		"accept_alliance": "In shadow, we are bound. A useful arrangement.",
		"reject_alliance": "Trust? We barely trust ourselves.",
		"accept_peace": "Death pauses... but never truly stops.",
		"reject_peace": "There is no peace in the grave.",
		"war_declared": "The hollow winds carry our armies forth.",
		"threatened": "What can you threaten the already-dead?",
	},
	&"ivoryscar": {
		"greeting_friendly": "The Oracle's eye sees a favorable future for us both.",
		"greeting_hostile": "The petrified gaze falls upon you. Be still.",
		"greeting_neutral": "The relics whisper. What do you bring?",
		"greeting_war": "Your fate was sealed the moment you opposed us.",
		"accept_trade": "Ancient wisdom says: a fair trade benefits all.",
		"reject_trade": "The sands bury worthless offers.",
		"accept_alliance": "Our visions align. Together we unearth greatness.",
		"reject_alliance": "The future does not yet show us as allies.",
		"accept_peace": "The Oracle decrees peace. So it shall be.",
		"reject_peace": "Your destruction has already been foretold.",
		"war_declared": "The desert's wrath is patient, but absolute.",
		"threatened": "We have seen civilizations rise and fall. You do not frighten us.",
	},
	&"shardhorde": {
		"greeting_friendly": "Crystal resonance... positive. Communication proceeds.",
		"greeting_hostile": "Foreign vibrations detected. Hostile intent registered.",
		"greeting_neutral": "The Crystalmind processes your signal. Transmit.",
		"greeting_war": "Elimination protocol engaged.",
		"accept_trade": "Resource exchange optimized. Agreement formed.",
		"reject_trade": "Exchange ratio suboptimal. Rejected.",
		"accept_alliance": "Symbiosis detected. Cooperation protocol initiated.",
		"reject_alliance": "Insufficient compatibility for merger.",
		"accept_peace": "Hostility termination accepted. Resources redirected.",
		"reject_peace": "Threat not neutralized. Conflict continues.",
		"war_declared": "Swarm vector locked. All units: converge.",
		"threatened": "Threat assessment: negligible.",
	},
	&"sunblessed": {
		"greeting_friendly": "The sun shines upon the righteous. Welcome, friend.",
		"greeting_hostile": "The sacred flame judges you... and finds you wanting.",
		"greeting_neutral": "Walk in the light, stranger. What do you seek?",
		"greeting_war": "The sun's justice is absolute. Prepare yourself.",
		"accept_trade": "A blessed exchange under the golden sky.",
		"reject_trade": "The sun does not bargain with shadows.",
		"accept_alliance": "Under the same sun, we march as one.",
		"reject_alliance": "The pilgrimage continues alone.",
		"accept_peace": "Let the dawn bring peace between us.",
		"reject_peace": "The sun sets on your pleas for mercy.",
		"war_declared": "By solar decree, you are judged!",
		"threatened": "The sun fears no darkness.",
	},
}

# Commander name lists per faction
const COMMANDER_NAMES := {
	&"empire": [
		"Legate Aurelius", "Prefect Cassius", "Tribune Marcellus", "Centurion Varro",
		"Commander Gaius", "Marshal Tiberius", "Captain Lucius", "General Septimus",
		"Prefect Helena", "Legate Octavia", "Tribune Valeria", "Commander Flavia",
	],
	&"skulloath": [
		"Warchief Grak", "Bonelord Thresh", "Ravager Krul", "Dread Maw Vex",
		"Skull Warden Zhag", "Gore Fist Brul", "Howler Nix", "Bonecaller Dren",
		"War Mistress Skaela", "Dread Mother Vhul", "Ravager Ghast", "Blood Seer Morg",
	],
	&"gladehost": [
		"Grove Keeper Aelind", "Thorn Warden Sylara", "Root Guard Faelen", "Leaf Marshal Thandril",
		"Bark Shield Eryn", "Vine Watcher Olwen", "Shade Walker Miriel", "Canopy Lord Thaelen",
		"Branch Warden Ysviel", "Moss Sentinel Caedris", "Dew Guard Lirael", "Grove Marshal Alathir",
	],
	&"tainted_jade": [
		"Serpent Lord Ixcatl", "Jade Fang Quetzal", "Venom Priest Tlacael", "Shadow Coatl Xipe",
		"Scale Warden Cipac", "Mist Serpent Yaotl", "Jade Eye Necuame", "Fang Master Itzli",
		"Serpent Queen Malinal", "Venom Seer Xochitl", "Jade Priestess Atzi", "Coatl Keeper Izel",
	],
	&"shardhorde": [
		"Crystal Matriarch Zyx", "Shard Caller Prysm", "Hive Mind Kryl", "Crystal Warden Thex",
		"Swarm Lord Vyss", "Beast Keeper Nyx", "Void Herder Qal", "Crystal Seer Oryth",
		"Shard Mother Kael", "Hive Queen Zhyl", "Crystal Fang Drex", "Beast Lord Gryx",
	],
	&"moonspear": [
		"Sentinel Arathor", "Moon Warden Yselle", "Starlight Keeper Doran", "High Guard Caelen",
		"Dawn Shield Mirael", "Silver Lance Theron", "Crescent Blade Lirael", "Vigilant Aldric",
	],
	&"thunderswarm": [
		"Stormcaller Draken", "Thunder Lord Bjorn", "Lightning Warden Askari", "Storm Rider Volga",
		"Tempest Fang Ragnar", "Sky Breaker Haldis", "Gale Marshal Tormund", "Wind Rider Svara",
	],
	&"ivoryscar": [
		"Relic Seeker Asharan", "Bone Scholar Nephris", "Dust Warden Kaleth", "Tomb Walker Seris",
		"Ivory Sage Mithren", "Sand Oracle Zephra", "Ruin Guard Vashti", "Crypt Keeper Oshar",
	],
	&"cinderguard": [
		"Forge Master Vulkan", "Ember Warden Kael", "Ash Captain Brennan", "Fire Marshal Ignis",
		"Slag Knight Thorin", "Cinder Shield Pyra", "Furnace Lord Steren", "Coal Warden Ashlyn",
	],
	&"forsaken": [
		"Dusk Lord Morven", "Blood Warden Thessal", "Crypt Knight Cadeus", "Wraith Captain Vael",
		"Shadow Keeper Nyx", "Ruin Marshal Gharan", "Pale Sentinel Draven", "Void Walker Serath",
	],
	&"sunblessed": [
		"Radiant Seraph Aurel", "Sun Warden Solara", "Dawn Walker Helios", "Light Bearer Amara",
		"Golden Shield Darius", "Sacred Flame Pyriel", "Sun Pilgrim Eshara", "Bright Lance Oriel",
	],
}
var _commander_name_counters: Dictionary = {} # faction_id -> int

# ── Save / Load ─────────────────────────────────────────────

static func _save_path(slot: int) -> String:
	# Binary .res serializes/parses far faster than text .tres and is the
	# preferred format; _resolve_save_path falls back to legacy .tres saves.
	return "user://saves/save_%d.res" % slot

static func _resolve_save_path(slot: int) -> String:
	var res_path := _save_path(slot)
	if ResourceLoader.exists(res_path):
		return res_path
	var tres_path := "user://saves/save_%d.tres" % slot
	if ResourceLoader.exists(tres_path):
		return tres_path
	return ""

func save_game(slot: int) -> void:
	state.serialize_hex_map()
	state.turn_manager_state = TurnManager.serialize_state()
	DirAccess.make_dir_recursive_absolute("user://saves")
	ResourceSaver.save(state, _save_path(slot))
	# Store metadata alongside save for load menu display
	var meta := ConfigFile.new()
	var faction_data := DataManager.get_faction(state.player_faction_id)
	meta.set_value("save", "turn", state.current_turn)
	meta.set_value("save", "faction_id", str(state.player_faction_id))
	meta.set_value("save", "faction_name", faction_data.display_name if faction_data else str(state.player_faction_id))
	meta.set_value("save", "timestamp", Time.get_datetime_string_from_system())
	var month_name := DataManager.get_month_name(state.current_month)
	meta.set_value("save", "date", "%s, %d S.F." % [month_name, state.current_year])
	meta.save("user://saves/save_%d_meta.cfg" % slot)
	state.hex_map_data = {} # Clear after save to save memory
	state.turn_manager_state = {}

static func get_save_metadata(slot: int) -> Dictionary:
	var cfg := ConfigFile.new()
	var path := "user://saves/save_%d_meta.cfg" % slot
	if cfg.load(path) != OK:
		return {}
	return {
		turn = cfg.get_value("save", "turn", 0),
		faction_id = cfg.get_value("save", "faction_id", ""),
		faction_name = cfg.get_value("save", "faction_name", "Unknown"),
		timestamp = cfg.get_value("save", "timestamp", ""),
		date = cfg.get_value("save", "date", ""),
	}

func load_game(slot: int) -> void:
	var path := _resolve_save_path(slot)
	if path == "":
		return
	state = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameState
	if state == null:
		return
	apply_faction_theme(state.player_faction_id)
	# Old-save backfill (Task 1b, camp-fix follow-up): saves from before
	# ba9c8bc may have a settled Sunblessed camp with is_mobile_camp == false
	# (that fix's old semantics cleared the flag on settle instead of keeping
	# it as a permanent identity marker). army.camp_city_id is set ONLY by
	# setup_sunblessed_camp and never repurposed by any other mechanic, so
	# it's a reliable discriminator regardless of save age -- backfill
	# unconditionally rather than leaving pre-fix camps misclassified until
	# the player happens to break camp.
	for aid in state.armies:
		var backfill_army: ArmyState = state.armies[aid]
		if backfill_army.camp_city_id != &"" and state.cities.has(backfill_army.camp_city_id):
			state.cities[backfill_army.camp_city_id].is_mobile_camp = true
	state.deserialize_hex_map()
	state.hex_map.build_region_cache()
	TurnManager.deserialize_state(state.turn_manager_state)
	state.turn_manager_state = {}
	movement_system = MovementSystem.new(state.hex_map)
	city_system.invalidate_city_hex_index()
	invalidate_completion_cache()
	city_system.invalidate_region_effects_cache()
	diplomacy_system.invalidate_free_passage_cache()
	current_phase = Enums.GamePhase.CAMPAIGN
	_commander_name_counters.clear()
	transition_to_scene("res://scenes/campaign/campaign.tscn")

static func has_save(slot: int) -> bool:
	return _resolve_save_path(slot) != ""

var is_demo_map := false

func new_game(faction_id: StringName = &"empire", demo: bool = false, map_seed: int = -1) -> void:
	is_demo_map = demo
	explored_tiles.clear()
	state = GameState.new()
	state.player_faction_id = faction_id
	apply_faction_theme(faction_id)

	# Per-campaign map seed (Task 1B): -1 means "unset", so roll one now.
	# This is the ONLY place map-gen randomness is allowed to originate —
	# the generator itself and its scatter passes stay pure hash functions.
	if map_seed < 0:
		map_seed = randi() % 1000000
	state.map_seed = map_seed

	# Generate hex map
	if demo:
		HexMapData.MAP_WIDTH = MapGenerator.DEMO_WIDTH
		HexMapData.MAP_HEIGHT = MapGenerator.DEMO_HEIGHT
		state.hex_map = MapGenerator.generate_demo_hex_map(DataManager.regions, map_seed, REGION_CITIES)
	else:
		HexMapData.MAP_WIDTH = 117
		HexMapData.MAP_HEIGHT = 78
		state.hex_map = MapGenerator.generate_hex_map(DataManager.regions, map_seed, REGION_CITIES)
	state.hex_map.build_region_cache()
	movement_system = MovementSystem.new(state.hex_map)
	city_system.invalidate_city_hex_index()
	invalidate_completion_cache()
	city_system.invalidate_region_effects_cache()
	diplomacy_system.invalidate_free_passage_cache()

	_init_factions()
	_init_rebels_faction()
	_init_shard_guardians_faction()
	_init_independent_faction()
	_init_regions()
	_init_cities()
	_ensure_landmark_neighbors()
	BountySystem.rebalance_for_cities(state.hex_map, state.map_seed)
	_recompute_all_territory()
	if not demo:
		_init_elderbeasts()
	_init_armies()
	_init_commander_pools()
	_init_diplomacy()
	current_phase = Enums.GamePhase.CAMPAIGN
	transition_to_scene("res://scenes/campaign/campaign.tscn")

func _init_factions() -> void:
	_commander_name_counters.clear()
	# In demo mode, only init factions that have starting regions on the demo map
	var demo_region_set: Dictionary = {}
	if is_demo_map:
		for rid in MapGenerator.DEMO_REGIONS:
			demo_region_set[rid] = true
	for faction_id in DataManager.factions:
		if is_demo_map:
			var fd: FactionData = DataManager.factions[faction_id]
			var has_demo_region := false
			for sr in fd.starting_regions:
				if demo_region_set.has(sr):
					has_demo_region = true
					break
			if not has_demo_region:
				continue
		var fs := FactionState.new()
		fs.faction_data_id = faction_id
		var is_minor := MINOR_FACTION_PARENTS.has(faction_id)
		if faction_id in NOMADIC_FACTIONS and _is_shardhorde_type(faction_id):
			# Shardhorde-type nomads: crystal/shard economy
			fs.resources = {
				Enums.ResourceType.GOLD: 160 if is_minor else 200,
				Enums.ResourceType.IRON: 30 if is_minor else 50,
				Enums.ResourceType.FOOD: 100 if is_minor else 150,
				Enums.ResourceType.TECHNOLOGY: 12 if is_minor else 17,
				Enums.ResourceType.SHARD_ESSENCE: 10 if is_minor else 20,
				Enums.ResourceType.WOOD: 20 if is_minor else 40,
				Enums.ResourceType.CAPTIVES: 0,
			}
		elif is_minor:
			# Minor factions: reduced starting resources
			fs.resources = {
				Enums.ResourceType.GOLD: 200,
				Enums.ResourceType.IRON: 50,
				Enums.ResourceType.FOOD: 80,
				Enums.ResourceType.TECHNOLOGY: 17,
				Enums.ResourceType.SHARD_ESSENCE: 0,
				Enums.ResourceType.WOOD: 40,
				Enums.ResourceType.CAPTIVES: 0,
			}
		else:
			# Major factions: full starting resources
			fs.resources = {
				Enums.ResourceType.GOLD: 250,
				Enums.ResourceType.IRON: 80,
				Enums.ResourceType.FOOD: 120,
				Enums.ResourceType.TECHNOLOGY: 34,
				Enums.ResourceType.SHARD_ESSENCE: 0,
				Enums.ResourceType.WOOD: 60,
				Enums.ResourceType.CAPTIVES: 0,
			}
		state.faction_states[faction_id] = fs

static func _is_shardhorde_type(faction_id: StringName) -> bool:
	return faction_id == &"shardhorde" or faction_id == &"icebound" or faction_id == &"splinterbrood"

static func is_npc_faction(faction_id: StringName) -> bool:
	return faction_id == &"rebels" or faction_id == &"shard_guardians" or faction_id == &"independent"

func _init_rebels_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"rebels"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"rebels"] = fs

func _init_shard_guardians_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"shard_guardians"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"shard_guardians"] = fs

func _init_independent_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"independent"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"independent"] = fs

func _init_regions() -> void:
	# Track starting region ownership (tile ownership set after cities via Voronoi)
	for faction_id in DataManager.factions:
		if not state.faction_states.has(faction_id):
			continue
		var faction_data: FactionData = DataManager.factions[faction_id]
		var fs: FactionState = state.faction_states[faction_id]
		for region_id in faction_data.starting_regions:
			if not state.hex_map.get_region_tiles(region_id).is_empty():
				fs.owned_regions.append(region_id)

func _get_all_cities_array() -> Array:
	var result: Array = []
	for city_id in state.cities:
		result.append(state.cities[city_id])
	return result

func _recompute_all_territory() -> void:
	state.hex_map.set_city_territory_owner(_get_all_cities_array())

func _recompute_region_territory(region_id: StringName) -> void:
	var cities: Array = []
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		if city.region_id == region_id:
			cities.append(city)
	state.hex_map.set_region_city_territory(region_id, cities)

func _get_region_majority_faction(region_id: StringName) -> StringName:
	var counts: Dictionary = {}
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		if city.region_id == region_id and city.faction_id != &"" and city.faction_id != &"independent":
			counts[city.faction_id] = counts.get(city.faction_id, 0) + 1
	var best_fid: StringName = &""
	var best_count := 0
	for fid in counts:
		if counts[fid] > best_count:
			best_count = counts[fid]
			best_fid = fid
	return best_fid

# Hardcoded starting armies for factions with custom unit rosters
# Mostly tier 1 units with at most 2 tier 2 units per army
const MAJOR_STARTING_ARMIES := {
	&"empire": [&"levy_conscripts", &"legionary", &"legionary", &"emberlight_auxilia", &"border_mercenaries"],
	&"gladehost": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"stag_rider", &"hawk_scout"],
	&"tainted_jade": [&"jade_fang", &"jade_fang", &"jungle_stalker", &"coatl_shaman", &"thrall_swarm"],
	&"skulloath": [&"warband_raider", &"warband_raider", &"steppe_rider", &"steppe_archers", &"bonecaller"],
	&"moonspear": [&"moonspear_sentinel", &"moonspear_sentinel", &"moonspear_sentinel", &"lunar_archer", &"lunar_archer"],
	&"thunderswarm": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"stormbow_raider", &"stormbow_raider"],
	&"cinderguard": [&"cinderguard_warden", &"cinderguard_warden", &"cinderguard_warden", &"ember_crossbow", &"ember_crossbow"],
	&"forsaken": [&"shadow_thrall", &"shadow_thrall", &"bat_swarm", &"bat_swarm", &"death_mage"],
	&"ivoryscar": [&"ivoryscar_seeker", &"ivoryscar_seeker", &"scarab_swarm", &"scarab_swarm", &"bone_cavalry"],
}

func _init_armies() -> void:
	var occupied_tiles: Dictionary = {} # Vector2i -> true — tracks tiles with armies
	# Pre-populate with elderbeast positions (they were already initialized)
	for beast_id in state.elderbeasts:
		var beast: ElderbeastState = state.elderbeasts[beast_id]
		occupied_tiles[beast.hex_pos] = true
	for faction_id in DataManager.factions:
		if not state.faction_states.has(faction_id):
			continue
		if _is_shardhorde_type(faction_id):
			continue # Shardhorde-type armies handled in _init_shardhorde_armies
		if faction_id in NOMADIC_FACTIONS:
			_init_nomadic_army(faction_id, occupied_tiles)
			continue
		var faction_data: FactionData = DataManager.factions[faction_id]
		if faction_data.starting_regions.is_empty():
			continue

		var center := MapGenerator.get_region_center(faction_data.starting_regions[0])
		center = _find_unoccupied_spawn(center, occupied_tiles)

		# Use leader army override for the player faction, else hardcoded, else generic
		var unit_ids: Array = []
		if faction_id == _leader_army_override_faction and not _leader_army_override.is_empty():
			unit_ids = _leader_army_override.duplicate()
		else:
			unit_ids = MAJOR_STARTING_ARMIES.get(faction_id, [])
		if unit_ids.is_empty():
			unit_ids = _get_generic_starting_units(faction_id)
		if unit_ids.is_empty():
			continue

		var army := _create_army(faction_id, center, unit_ids)
		state.armies[army.army_id] = army
		occupied_tiles[center] = true

	# Shardhorde elderbeasts + escort armies (pass occupied tiles to avoid overlap)
	_init_shardhorde_armies(occupied_tiles)

func _get_generic_starting_units(faction_id: StringName) -> Array:
	# Build a starting army from whatever units exist for this faction
	# Ensures at least 2 different unit types for variety (never mono-composition)
	var faction_units: Array[UnitData] = []
	for unit_id in DataManager.units:
		var ud: UnitData = DataManager.units[unit_id]
		if ud.faction_id == faction_id:
			faction_units.append(ud)
	if faction_units.is_empty():
		# Try parent faction units for minor factions
		var parent_id: StringName = MINOR_FACTION_PARENTS.get(faction_id, &"")
		if parent_id != &"":
			for unit_id in DataManager.units:
				var ud: UnitData = DataManager.units[unit_id]
				if ud.faction_id == parent_id:
					faction_units.append(ud)
	if faction_units.is_empty():
		return []

	# Sort by recruit cost (cheapest first) as proxy for tier
	faction_units.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		var cost_a: int = a.recruit_cost.get(0, 100)
		var cost_b: int = b.recruit_cost.get(0, 100)
		return cost_a < cost_b
	)

	# Split into tier 1 (cheaper half) and tier 2 (more expensive half)
	var mid := maxi(1, faction_units.size() / 2)
	var tier1_units: Array[UnitData] = []
	var tier2_units: Array[UnitData] = []
	for i in faction_units.size():
		if i < mid:
			tier1_units.append(faction_units[i])
		else:
			tier2_units.append(faction_units[i])

	# Major factions get 5 units, minor factions get 4
	var is_minor := MINOR_FACTION_PARENTS.has(faction_id)
	var total_count := 4 if is_minor else 5
	var max_tier2 := 1 if is_minor else 2

	var result: Array = []
	# Add tier 2 units (up to max_tier2), cycling through available tier 2 types
	var t2_count := mini(max_tier2, tier2_units.size())
	for i in t2_count:
		result.append(tier2_units[i % tier2_units.size()].id)
	# Fill rest with tier 1 units, cycling through available types for variety
	var t1_needed := total_count - t2_count
	for i in t1_needed:
		result.append(tier1_units[i % tier1_units.size()].id)

	# Ensure at least 2 different unit types — if only 1 type so far, swap one for a tier 2
	if result.size() >= 2:
		var unique_types: Dictionary = {}
		for uid in result:
			unique_types[uid] = true
		if unique_types.size() <= 1 and tier2_units.size() > 0:
			# Replace last slot with a different unit type
			result[result.size() - 1] = tier2_units[0].id
		elif unique_types.size() <= 1 and faction_units.size() > 1:
			# Use the next available faction unit even if same tier
			result[result.size() - 1] = faction_units[1].id
	return result

func _init_nomadic_army(faction_id: StringName, occupied_tiles: Dictionary) -> void:
	# Nomadic non-shardhorde factions (e.g. sunblessed) get an army at a random neutral tile
	var unit_ids := _get_generic_starting_units(faction_id)
	if unit_ids.is_empty():
		return
	# Faction-specific spawn positions (south-east of Marcellum for Oaseans, etc.)
	var search_center := Vector2i(42, 29)
	if faction_id == &"oaseans":
		search_center = Vector2i(44, 37)  # South-east of Marcellum, desert terrain
	elif faction_id == &"venerated":
		search_center = Vector2i(64, 30)  # South of Cinderwatch
	var spawn_pos := search_center
	for coord in state.hex_map.tiles:
		var tile: HexMapData.TileState = state.hex_map.tiles[coord]
		if tile.terrain != Enums.TerrainType.WATER and tile.owner_faction == &"":
			if not occupied_tiles.has(coord) and HexHelper.hex_distance(coord, search_center) < 12:
				spawn_pos = coord
				break
	var army := _create_army(faction_id, spawn_pos, unit_ids)
	state.armies[army.army_id] = army
	occupied_tiles[spawn_pos] = true

func _init_shardhorde_armies(_occupied_tiles: Dictionary = {}) -> void:
	var beast_ids := state.elderbeasts.keys()
	if beast_ids.size() >= 1:
		var beast1: ElderbeastState = state.elderbeasts[beast_ids[0]]
		var escort := _create_army(&"shardhorde", beast1.hex_pos,
			[&"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling", &"crystalback_raptor"])
		escort.elderbeast_id = beast1.beast_id
		state.armies[escort.army_id] = escort
		beast1.escort_army_id = escort.army_id
		_add_elderbeast_to_army(beast1, escort)
		beast1.commander = _create_commander(&"shardhorde")
		beast1.commander.name = beast1.name
		beast1.commander.is_elderbeast = true
		escort.commander = beast1.commander
		escort.commander_name = beast1.commander.name
	if beast_ids.size() >= 2:
		var beast2: ElderbeastState = state.elderbeasts[beast_ids[1]]
		var raider := _create_army(&"shardhorde", beast2.hex_pos,
			[&"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling"])
		raider.elderbeast_id = beast2.beast_id
		state.armies[raider.army_id] = raider
		beast2.escort_army_id = raider.army_id
		_add_elderbeast_to_army(beast2, raider)
		beast2.commander = _create_commander(&"shardhorde")
		beast2.commander.name = beast2.name
		beast2.commander.is_elderbeast = true
		raider.commander = beast2.commander
		raider.commander_name = beast2.commander.name

	# Shardhorde MINOR hordes: nomadic with no cities, so without a starting
	# warband they were "defeated" on turn 1 before ever acting
	var minor_hordes := {
		&"icebound": [&"frost_swarmling", &"frost_swarmling", &"ice_hunter", &"war_yak"],
		&"splinterbrood": [&"splinter_drone", &"splinter_drone", &"shard_swarm", &"splinter_spitter"],
	}
	for horde_id in minor_hordes:
		if not state.faction_states.has(horde_id):
			continue
		var spawn := _find_minor_horde_spawn(horde_id)
		var warband := _create_army(horde_id, spawn, minor_hordes[horde_id])
		warband.commander = _create_commander(horde_id)
		warband.commander_name = warband.commander.name
		state.armies[warband.army_id] = warband

## Spawn point for a nomadic minor horde: a shard-wastes tile far from player
## start if possible, otherwise a map-quadrant fallback
func _find_minor_horde_spawn(horde_id: StringName) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for coord in state.hex_map.tiles:
		var tile = state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.SHARD_WASTES:
			candidates.append(coord)
	if candidates.is_empty():
		for coord in state.hex_map.tiles:
			var tile = state.hex_map.tiles[coord]
			if tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.MOUNTAINS:
				candidates.append(coord)
	if candidates.is_empty():
		return Vector2i(HexMapData.MAP_WIDTH / 2, HexMapData.MAP_HEIGHT / 2)
	# Deterministic per horde: hash the id into the candidate list
	return candidates[absi(hash(horde_id)) % candidates.size()]

func _find_unoccupied_spawn(center: Vector2i, occupied_tiles: Dictionary) -> Vector2i:
	# Build set of city hexes to avoid spawning armies inside cities
	var city_hexes: Dictionary = {}
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		city_hexes[city.hex_pos] = true
	if not occupied_tiles.has(center) and not city_hexes.has(center):
		var tile := state.hex_map.get_tile(center)
		if tile and tile.terrain != Enums.TerrainType.WATER:
			return center
	# BFS outward to find nearest unoccupied, passable tile (not on a city)
	var visited: Dictionary = {center: true}
	var queue: Array[Vector2i] = [center]
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for n in HexHelper.get_neighbors(current):
			if visited.has(n):
				continue
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			visited[n] = true
			var ntile := state.hex_map.get_tile(n)
			if ntile and ntile.terrain != Enums.TerrainType.WATER and not occupied_tiles.has(n) and not city_hexes.has(n):
				return n
			queue.append(n)
	return center

func _create_army(faction_id: StringName, hex_pos: Vector2i, unit_ids: Array) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = state.generate_id()
	army.faction_id = faction_id
	army.hex_pos = hex_pos
	army.movement_remaining = 2.0

	for uid in unit_ids:
		var unit_data := DataManager.get_unit(uid)
		if unit_data:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, state.generate_id())
			army.units.append(instance)

	# Set max movement from unit composition
	army.movement_remaining = army.get_max_movement()
	return army

func _add_elderbeast_to_army(beast: ElderbeastState, army: ArmyState) -> void:
	var unit_data := DataManager.get_unit(beast.get_unit_data_id())
	if unit_data == null:
		return
	var instance := UnitInstance.new()
	instance.instance_id = beast.beast_id # Use beast_id as instance_id for easy lookup
	instance.unit_data_id = unit_data.id
	instance.current_hp = beast.hp
	beast.unit_instance_id = instance.instance_id
	army.units.insert(0, instance)
	# Set elderbeast commander as army general
	if beast.commander:
		army.commander = beast.commander
		army.commander_name = beast.commander.name

func _generate_commander_name(faction_id: StringName) -> String:
	var names: Array = COMMANDER_NAMES.get(faction_id, [])
	if names.is_empty():
		return "Commander"
	var idx: int = _commander_name_counters.get(faction_id, 0)
	var name: String = names[idx % names.size()]
	_commander_name_counters[faction_id] = idx + 1
	return name

func _get_faction_starting_city_count(faction_id: StringName) -> int:
	if faction_id == &"" or faction_id in NOMADIC_FACTIONS:
		return 0
	if MINOR_FACTION_PARENTS.has(faction_id):
		return 1  # Minor factions: 1 city
	return 2  # Major factions: 2 cities

func _get_region_starting_faction(region_id: StringName) -> StringName:
	for faction_id in DataManager.factions:
		var fd: FactionData = DataManager.factions[faction_id]
		if region_id in fd.starting_regions:
			return faction_id
	return &""

const MIN_CITY_DISTANCE := 4

func _find_valid_city_pos(region_center: Vector2i, offset: Vector2i, required_region: StringName = &"") -> Vector2i:
	var target := region_center + offset
	# Clamp to map bounds
	target.x = clampi(target.x, 0, HexMapData.MAP_WIDTH - 1)
	target.y = clampi(target.y, 0, HexMapData.MAP_HEIGHT - 1)
	# Determine the region constraint from the target tile if not provided
	if required_region == &"":
		var center_tile := state.hex_map.get_tile(region_center)
		if center_tile:
			required_region = center_tile.region_id
	# Check if the target tile is valid land, in the correct region, and far enough from other cities
	var tile := state.hex_map.get_tile(target)
	if tile and tile.region_id == required_region and tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.MOUNTAINS and _is_far_from_cities(target) and not _is_adjacent_to_water(target):
		return target
	# BFS spiral search for a valid placement that respects minimum distance and stays in region
	var visited: Dictionary = {target: true}
	var frontier: Array[Vector2i] = [target]
	var steps := 0
	while frontier.size() > 0 and steps < 200:
		var current: Vector2i = frontier.pop_front()
		steps += 1
		for neighbor in HexHelper.get_neighbors(current):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := state.hex_map.get_tile(neighbor)
			if ntile == null:
				continue
			# Only consider tiles within the same region
			if required_region != &"" and ntile.region_id != required_region:
				continue
			if ntile.terrain != Enums.TerrainType.WATER and ntile.terrain != Enums.TerrainType.MOUNTAINS and _is_far_from_cities(neighbor) and not _is_adjacent_to_water(neighbor):
				return neighbor
			frontier.append(neighbor)
	# Last resort: accept original target even if close, but still prefer same region (relax water adjacency)
	if tile and tile.region_id == required_region and tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.MOUNTAINS:
		return target
	return region_center

func _is_far_from_cities(pos: Vector2i) -> bool:
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		if HexHelper.hex_distance(pos, city.hex_pos) < MIN_CITY_DISTANCE:
			return false
	return true

func _is_adjacent_to_water(pos: Vector2i) -> bool:
	for neighbor in HexHelper.get_neighbors(pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var ntile := state.hex_map.get_tile(neighbor)
		if ntile and ntile.terrain == Enums.TerrainType.WATER:
			return true
	return false

func _init_cities() -> void:
	# Faction-specific starting buildings
	var faction_starting_buildings := {
		&"empire": &"cohort_barracks",
		&"skulloath": &"raiders_den",
		&"gladehost": &"ranger_outpost",
		&"tainted_jade": &"serpent_pit",
		&"moonspear": &"moon_shrine",
		&"thunderswarm": &"storm_altar",
		&"cinderguard": &"cinder_watchtower",
		&"forsaken": &"crypt_court",
		&"ivoryscar": &"relic_shrine",
	}

	for region_id in REGION_CITIES:
		# Skip regions not present on the current map
		if state.hex_map.get_region_tiles(region_id).is_empty():
			continue
		var slots: Array = REGION_CITIES[region_id]
		var region_center := MapGenerator.get_region_center(region_id)

		# Determine which faction owns this region
		var owning_faction := _get_region_starting_faction(region_id)
		var faction_cities_placed := 0
		var max_faction_cities := _get_faction_starting_city_count(owning_faction)

		for i in slots.size():
			var slot: Dictionary = slots[i]
			var city_pos := _find_valid_city_pos(region_center, slot.offset, region_id)
			var city := CityState.new()
			city.city_id = state.generate_id()
			city.city_name = slot.name
			city.region_id = region_id
			city.hex_pos = city_pos
			city.level = 1
			city.population = 80
			city.loyalty = 40
			city.class_loyalty = {
				"peasants": 40, "artisans": 40, "scholars": 40, "nobles": 40, "captives": 0
			}
			city.original_faction_id = owning_faction if owning_faction != &"" else &"independent"
			city.turns_since_capture = -1

			# First N cities go to the owning faction, rest are independent
			if owning_faction != &"" and owning_faction not in NOMADIC_FACTIONS and faction_cities_placed < max_faction_cities:
				city.faction_id = owning_faction
				city.loyalty = 50
				city.population = 100
				city.class_loyalty = {
					"peasants": 50, "artisans": 50, "scholars": 50, "nobles": 50, "captives": 0
				}
				if faction_cities_placed == 0:
					city.is_capital = true
					# Faction-specific starting building
					var building: StringName = faction_starting_buildings.get(owning_faction, &"")
					if building != &"":
						city.buildings.append(building)
						# Assign starting building to a tile — pick the neighbor most bordered by other city neighbors
						var best_tile := Vector2i(-1, -1)
						var best_score := -1
						var city_neighbors := HexHelper.get_neighbors(city_pos)
						var neighbor_set: Dictionary = {}
						for cn in city_neighbors:
							neighbor_set[cn] = true
						for cn in city_neighbors:
							if not HexHelper.is_valid(cn, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
								continue
							var tile := state.hex_map.get_tile(cn)
							if tile == null or tile.terrain == Enums.TerrainType.WATER:
								continue
							# Check building terrain requirement
							var bdata: BuildingData = DataManager.get_building(building)
							if bdata and bdata.required_terrain >= 0 and tile.terrain != bdata.required_terrain:
								continue
							# Score = how many of this tile's own neighbors are also neighbors of the city
							var score := 0
							for nn in HexHelper.get_neighbors(cn):
								if neighbor_set.has(nn):
									score += 1
							if score > best_score:
								best_score = score
								best_tile = cn
						if best_tile != Vector2i(-1, -1):
							city.building_tiles[building] = best_tile
					# Grant every major faction (player and AI alike) a free
					# settlement founding on turn 1. Previously player-only:
					# AI capitals only ever regained the ability on a capital
					# level-up (see _process_upgrade), and with capitals
					# typically taking ~15-20 turns to first level up, most AI
					# factions got at most one narrow window in a 40-turn game
					# to align "flag true" with "can currently afford 120g/
					# 60w/45f" -- measured result: ~0-1 settlements founded
					# TOTAL across an entire game, not per faction. Starting
					# every faction with the ability from turn 1 (like the
					# player always had) is the dominant fix for that;
					# subsequent foundings still gate on the same level-up
					# recharge for everyone.
					city.can_found_settlement = true
				faction_cities_placed += 1
				var fs: FactionState = state.faction_states.get(owning_faction)
				if fs:
					fs.owned_cities.append(city.city_id)
			else:
				city.faction_id = &"independent"
				city.loyalty = 60  # Independent cities are self-content
				city.class_loyalty = {
					"peasants": 60, "artisans": 60, "scholars": 60, "nobles": 60, "captives": 0
				}
				# Persistent garrison: 3 phalanx + 1 toxotes
				city.garrison_units = [
					{unit_id = &"citizen_phalanx", count = 3},
					{unit_id = &"toxotes", count = 1},
				]

			state.cities[city.city_id] = city

const LANDMARK_GUARD_NAMES := {
	&"dragonbone_fields": "Bonewatch",
	&"everfrost_core": "Rimehold",
	&"sungold_vein": "Gilder's Rest",
	&"worldroot_nexus": "Rootshade",
	&"voidglass_rift": "Whisperfall",
	&"titan_forge_ruin": "Cindervault",
	&"leyline_well": "Wellwarden",
}

## Every Landmark spawns guarded: ensure a city (any owner) exists within 2
## hexes, founding a small independent town beside it when none does.
func _ensure_landmark_neighbors() -> void:
	if state.hex_map == null:
		return
	for coord in state.hex_map.tiles:
		var tile: HexMapData.TileState = state.hex_map.tiles[coord]
		if tile.landmark_id == &"":
			continue
		var has_neighbor := false
		for cid in state.cities:
			if HexHelper.hex_distance(state.cities[cid].hex_pos, coord) <= 2:
				has_neighbor = true
				break
		if has_neighbor:
			continue
		# Pick a deterministic adjacent land tile (not the landmark itself)
		var spot := Vector2i(-1, -1)
		for n in HexHelper.get_neighbors(coord):
			var nt := state.hex_map.get_tile(n)
			if nt and nt.terrain != Enums.TerrainType.WATER and nt.terrain != Enums.TerrainType.MOUNTAINS \
					and nt.landmark_id == &"" and nt.special_id == &"" and nt.bounty_id == &"":
				spot = n
				break
		if spot == Vector2i(-1, -1):
			for n in HexHelper.get_neighbors(coord): # fallback: allow mountains
				var nt2 := state.hex_map.get_tile(n)
				if nt2 and nt2.terrain != Enums.TerrainType.WATER and nt2.landmark_id == &"" and nt2.special_id == &"" and nt2.bounty_id == &"":
					spot = n
					break
		if spot == Vector2i(-1, -1):
			continue # fully water-locked landmark: leave unguarded
		var spot_tile := state.hex_map.get_tile(spot)
		var city := CityState.new()
		city.city_id = state.generate_id()
		city.city_name = LANDMARK_GUARD_NAMES.get(tile.landmark_id, "Landmark Watch")
		city.region_id = spot_tile.region_id if spot_tile else tile.region_id
		city.hex_pos = spot
		city.level = 1
		city.population = 80
		city.faction_id = &"independent"
		city.original_faction_id = &"independent"
		city.loyalty = 60
		city.class_loyalty = {
			"peasants": 60, "artisans": 60, "scholars": 60, "nobles": 60, "captives": 0
		}
		city.turns_since_capture = -1
		city.garrison_units = [
			{unit_id = &"citizen_phalanx", count = 3},
			{unit_id = &"toxotes", count = 1},
		]
		state.cities[city.city_id] = city
		invalidate_completion_cache()
		city_system.invalidate_region_effects_cache()
	city_system.invalidate_city_hex_index()

func _init_elderbeasts() -> void:
	var shard_data: FactionData = DataManager.get_faction(&"shardhorde")
	if shard_data == null:
		return

	# Shardhorde is nomadic — spawn elderbeasts scattered, away from major faction cities
	var region_id: StringName = &"bataarbad"
	var center := MapGenerator.get_region_center(region_id)

	# Collect already-occupied tiles and major faction city positions
	var occupied: Dictionary = {}
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		occupied[army.hex_pos] = true

	var major_city_positions: Array[Vector2i] = []
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		if not MINOR_FACTION_PARENTS.has(city.faction_id) and not is_npc_faction(city.faction_id) and city.faction_id != &"independent":
			major_city_positions.append(city.hex_pos)

	# Find suitable hex positions — wider search radius, prefer distance from major cities
	var hex_map := state.hex_map
	var valid_hexes: Array[Vector2i] = []
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.WETLANDS:
			continue
		if occupied.has(coord):
			continue
		if HexHelper.hex_distance(coord, center) > 14:
			continue
		# Check distance from major faction cities — prefer at least 5 hexes away
		var min_city_dist := 999
		for city_pos in major_city_positions:
			min_city_dist = mini(min_city_dist, HexHelper.hex_distance(coord, city_pos))
		# Only consider tiles at least 4 hexes from major cities (closest should be independent)
		if min_city_dist >= 4:
			valid_hexes.append(coord)

	# Sort by distance from major cities (prefer furthest away)
	valid_hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a := 999
		var dist_b := 999
		for cp in major_city_positions:
			dist_a = mini(dist_a, HexHelper.hex_distance(a, cp))
			dist_b = mini(dist_b, HexHelper.hex_distance(b, cp))
		return dist_a > dist_b
	)

	var beast1_pos: Vector2i
	if valid_hexes.size() > 0:
		beast1_pos = valid_hexes[0]
	else:
		beast1_pos = _find_unoccupied_spawn(center, occupied)
	occupied[beast1_pos] = true

	# Second beast should be well-scattered from first (at least 6 hexes away)
	var beast2_pos := beast1_pos
	for coord in valid_hexes:
		var dist_from_first := HexHelper.hex_distance(coord, beast1_pos)
		if dist_from_first >= 6 and dist_from_first <= 12 and not occupied.has(coord):
			beast2_pos = coord
			break
	# Fallback: accept closer distance
	if beast2_pos == beast1_pos:
		for coord in valid_hexes:
			if HexHelper.hex_distance(coord, beast1_pos) >= 3 and not occupied.has(coord):
				beast2_pos = coord
				break
	occupied[beast2_pos] = true

	# Create first elderbeast with barracks
	var beast1 := ElderbeastState.new()
	beast1.beast_id = state.generate_id()
	beast1.faction_id = &"shardhorde"
	beast1.hex_pos = beast1_pos
	beast1.name = "Elder Crystalhorn"
	beast1.level = 1
	beast1.apply_level_stats()
	beast1.hp = beast1.max_hp
	# Elderbeasts recruit all faction units directly — no barracks needed
	state.elderbeasts[beast1.beast_id] = beast1

	# Create second elderbeast empty
	var beast2 := ElderbeastState.new()
	beast2.beast_id = state.generate_id()
	beast2.faction_id = &"shardhorde"
	beast2.hex_pos = beast2_pos
	beast2.name = "Ancient Shardback"
	beast2.level = 1
	beast2.apply_level_stats()
	beast2.hp = beast2.max_hp
	state.elderbeasts[beast2.beast_id] = beast2

func _create_commander(faction_id: StringName) -> CommanderState:
	var cmd := CommanderState.new()
	cmd.commander_id = state.generate_id()
	cmd.name = _generate_commander_name(faction_id)
	cmd.faction_id = faction_id
	cmd.level = 1
	cmd.xp = 0
	cmd.portrait_path = _pick_random_leader_portrait(faction_id)
	if CommanderSystem:
		CommanderSystem.assign_starting_traits(cmd)
	return cmd

func _pick_random_leader_portrait(faction_id: StringName) -> String:
	var leader_dir := "res://assets/sprites/factions/" + str(faction_id) + "/leaders/"
	var dir := DirAccess.open(leader_dir)
	if dir == null:
		return ""
	var portraits: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".webp"):
			portraits.append(leader_dir + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	if portraits.is_empty():
		return ""
	return portraits[randi() % portraits.size()]

func _init_commander_pools() -> void:
	for faction_id in state.faction_states:
		var fs: FactionState = state.faction_states[faction_id]
		var cmd := _create_commander(faction_id)
		# Auto-assign the first commander to the first army without one
		var armies := get_faction_armies(faction_id)
		var assigned := false
		for army in armies:
			if army.commander == null:
				army.commander = cmd
				army.commander_name = cmd.name
				assigned = true
				break
		if not assigned:
			fs.commander_pool.append(cmd)

func assign_commander_to_army(army_id: StringName, commander_id: StringName) -> bool:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or army.commander != null:
		return false
	if army.elderbeast_id != &"":
		return false
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs == null:
		return false
	for i in fs.commander_pool.size():
		if fs.commander_pool[i].commander_id == commander_id:
			army.commander = fs.commander_pool[i]
			army.commander_name = army.commander.name
			fs.commander_pool.remove_at(i)
			return true
	return false

func unassign_commander_from_army(army_id: StringName) -> bool:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or army.commander == null:
		return false
	if army.elderbeast_id != &"":
		return false
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs == null:
		return false
	fs.commander_pool.append(army.commander)
	army.commander = null
	army.commander_name = ""
	return true

func get_available_commanders(faction_id: StringName) -> Array[CommanderState]:
	var fs: FactionState = state.faction_states.get(faction_id)
	if fs == null:
		return []
	return fs.commander_pool

func _init_diplomacy() -> void:
	# ── Minor factions are ALLIED with their parent, FRIENDLY with siblings ──
	for minor_id in MINOR_FACTION_PARENTS:
		if not state.faction_states.has(minor_id):
			continue
		var parent_id: StringName = MINOR_FACTION_PARENTS[minor_id]
		if state.faction_states.has(parent_id):
			_set_relation(minor_id, parent_id, Enums.FactionRelation.ALLIED)
		# Friendly with other minors of same parent
		for other_minor in MINOR_FACTION_PARENTS:
			if other_minor == minor_id:
				continue
			if MINOR_FACTION_PARENTS[other_minor] == parent_id:
				if state.faction_states.has(other_minor):
					_set_relation(minor_id, other_minor, Enums.FactionRelation.FRIENDLY)

	# ── Major faction relationships ──
	# Western Basin: Empire + Gladehost (allies)
	_set_relation(&"empire", &"gladehost", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"empire", &"moonspear", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"empire", &"sunblessed", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"gladehost", &"moonspear", Enums.FactionRelation.FRIENDLY)

	# Empire conflicts
	_set_relation(&"empire", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"empire", &"tainted_jade", Enums.FactionRelation.WAR)
	_set_relation(&"empire", &"forsaken", Enums.FactionRelation.HOSTILE)
	_set_relation(&"empire", &"cinderguard", Enums.FactionRelation.HOSTILE) # Cinderguard are Empire deserters
	_set_relation(&"empire", &"shardhorde", Enums.FactionRelation.HOSTILE)

	# Northern belt: Moonspear + Thunderswarm (uneasy neighbors)
	_set_relation(&"moonspear", &"thunderswarm", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"moonspear", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"moonspear", &"ivoryscar", Enums.FactionRelation.HOSTILE)
	_set_relation(&"moonspear", &"forsaken", Enums.FactionRelation.HOSTILE)

	_set_relation(&"thunderswarm", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"thunderswarm", &"cinderguard", Enums.FactionRelation.HOSTILE)

	# Southern: Tainted Jade vs their neighbors
	_set_relation(&"gladehost", &"tainted_jade", Enums.FactionRelation.WAR)
	_set_relation(&"tainted_jade", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"tainted_jade", &"shardhorde", Enums.FactionRelation.NEUTRAL)

	# Central: Skulloath + Cinderguard (rivals)
	_set_relation(&"skulloath", &"cinderguard", Enums.FactionRelation.HOSTILE)
	_set_relation(&"skulloath", &"forsaken", Enums.FactionRelation.HOSTILE)
	_set_relation(&"skulloath", &"shardhorde", Enums.FactionRelation.HOSTILE)

	# Eastern: Forsaken + Ivoryscar (uneasy neighbors)
	_set_relation(&"forsaken", &"ivoryscar", Enums.FactionRelation.HOSTILE)
	_set_relation(&"cinderguard", &"forsaken", Enums.FactionRelation.HOSTILE)

	# Shardhorde vs most
	_set_relation(&"shardhorde", &"gladehost", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"moonspear", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"thunderswarm", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"forsaken", Enums.FactionRelation.HOSTILE)

	# ── Minor factions inherit their parent's wars ──
	for minor_id in MINOR_FACTION_PARENTS:
		if not state.faction_states.has(minor_id):
			continue
		var parent_id: StringName = MINOR_FACTION_PARENTS[minor_id]
		for other_faction in state.faction_states:
			if other_faction == minor_id or other_faction == parent_id:
				continue
			if MINOR_FACTION_PARENTS.get(other_faction, &"") == parent_id:
				continue # Same-parent minor, already set above
			# Check if parent has a relation with this faction
			var parent_rel := _get_set_relation(parent_id, other_faction)
			if parent_rel != -1:
				var current := _get_set_relation(minor_id, other_faction)
				if current == -1: # Only set if not already defined
					_set_relation(minor_id, other_faction, parent_rel as Enums.FactionRelation)

	# ── Rebels at WAR with all ──
	for faction_id in state.faction_states:
		if faction_id != &"rebels":
			_set_relation(&"rebels", faction_id, Enums.FactionRelation.WAR)
	# ── Shard Guardians at WAR with all ──
	for faction_id in state.faction_states:
		if faction_id != &"shard_guardians":
			_set_relation(&"shard_guardians", faction_id, Enums.FactionRelation.WAR)

	# ── Initialize diplomacy standing from relations ──
	# Each contributing component is logged separately via
	# DiplomacySystem.init_standing (not modify_standing — see its doc
	# comment) so the standing breakdown tooltip fully explains turn-1
	# standing instead of showing only whichever ripple effects happened
	# to log something later.
	for key in state.diplomacy:
		var parts := str(key).split(":")
		if parts.size() != 2:
			continue
		var a := StringName(parts[0])
		var b := StringName(parts[1])
		if str(a) > str(b):
			continue
		var relation: int = state.diplomacy[key]
		var base_standing := 0
		match relation:
			Enums.FactionRelation.WAR: base_standing = -30
			Enums.FactionRelation.HOSTILE: base_standing = -15
			Enums.FactionRelation.NEUTRAL: base_standing = 0
			Enums.FactionRelation.FRIENDLY: base_standing = 20
			Enums.FactionRelation.ALLIED: base_standing = 50
		if base_standing != 0:
			diplomacy_system.init_standing(a, b, base_standing, "Historical relations")
		# Historical grudges: Empire vs Cinderguard (deserters) and Forsaken (exiled necromancers)
		var is_empire_pair := (a == &"empire" or b == &"empire")
		if is_empire_pair:
			var other: StringName = b if a == &"empire" else a
			if other == &"forsaken":
				diplomacy_system.init_standing(a, b, -20, "Ancient enmity — exiled necromancers")
			elif other == &"cinderguard":
				diplomacy_system.init_standing(a, b, -10, "Deserter resentment")
		# Cinderguard vs Forsaken: fellow ex-Imperials but opposed philosophies
		if (a == &"cinderguard" and b == &"forsaken") or (a == &"forsaken" and b == &"cinderguard"):
			diplomacy_system.init_standing(a, b, -15, "Rival realm distrust")

func _set_relation(a: StringName, b: StringName, relation: Enums.FactionRelation) -> void:
	state.diplomacy[StringName(str(a) + ":" + str(b))] = relation
	state.diplomacy[StringName(str(b) + ":" + str(a))] = relation
	_relation_cache[_relation_key(a, b)] = relation
	_relation_cache[_relation_key(b, a)] = relation

func _get_set_relation(a: StringName, b: StringName) -> int:
	var key := StringName(str(a) + ":" + str(b))
	if state.diplomacy.has(key):
		return state.diplomacy[key]
	return -1

# ── Region & Culture Completion ──────────────────────────────
# Cached per faction; recomputed from a single pass over cities. Invalidated at
# every city-ownership mutation: capture, diplomatic transfer, independent
# join, settlement/camp founding, and new_game/load_game.
var _completion_cache: Dictionary = {} # faction_id -> {regions: Array, cultures: Array}

# Bumped whenever city ownership/region membership can change — consumers
# (e.g., LoyaltySystem's province index) compare against it for staleness.
var city_topology_epoch: int = 0

func invalidate_completion_cache() -> void:
	_completion_cache.clear()
	city_topology_epoch += 1

func get_completed_regions(faction_id: StringName) -> Array[StringName]:
	var entry: Dictionary = _completion_cache.get_or_add(faction_id, {})
	if entry.has("regions"):
		return entry["regions"]
	# One pass over cities: which factions hold cities in each region
	var region_factions: Dictionary = {} # region_id -> {faction_id: true}
	for city_id in state.cities:
		var city: CityState = state.cities[city_id]
		region_factions.get_or_add(city.region_id, {})[city.faction_id] = true
	var result: Array[StringName] = []
	for region_id in REGION_CITIES:
		var facs: Dictionary = region_factions.get(region_id, {})
		var all_owned := true
		for f in facs:
			if f != faction_id:
				all_owned = false
				break
		if all_owned:
			result.append(region_id)
	entry["regions"] = result
	return result

func get_completed_cultures(faction_id: StringName) -> Array[StringName]:
	var entry: Dictionary = _completion_cache.get_or_add(faction_id, {})
	if entry.has("cultures"):
		return entry["cultures"]
	var completed_regions := get_completed_regions(faction_id)
	var result: Array[StringName] = []
	for culture_id in CULTURE_REGIONS:
		var regions: Array = CULTURE_REGIONS[culture_id]
		var all_complete := true
		for r in regions:
			if r not in completed_regions:
				all_complete = false
				break
		if all_complete:
			result.append(culture_id)
	entry["cultures"] = result
	return result

func has_culture_bonus(faction_id: StringName, bonus_type: String) -> bool:
	var completed := get_completed_cultures(faction_id)
	for culture_id in completed:
		var bonus: Dictionary = CULTURE_BONUSES.get(culture_id, {})
		if bonus.get("type", "") == bonus_type:
			return true
	return false

func get_culture_bonus_value(faction_id: StringName, bonus_type: String) -> float:
	var total := 0.0
	var completed := get_completed_cultures(faction_id)
	for culture_id in completed:
		var bonus: Dictionary = CULTURE_BONUSES.get(culture_id, {})
		if bonus.get("type", "") == bonus_type:
			total += bonus.get("value", 0.0)
	return total

func get_elderbeast_at_tile(coord: Vector2i) -> ElderbeastState:
	for beast_id in state.elderbeasts:
		var beast: ElderbeastState = state.elderbeasts[beast_id]
		if beast.hex_pos == coord:
			return beast
	return null

func get_faction_elderbeasts(faction_id: StringName) -> Array[ElderbeastState]:
	var result: Array[ElderbeastState] = []
	for beast_id in state.elderbeasts:
		var beast: ElderbeastState = state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			result.append(beast)
	return result

func get_army_at_tile(coord: Vector2i) -> ArmyState:
	# Use movement system position cache when valid
	if movement_system and movement_system.positions_fresh():
		var armies: Array = movement_system._army_positions.get(coord, [])
		if armies.size() > 0:
			return armies[0]
		return null
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			return army
	return null

func get_armies_at_tile(coord: Vector2i) -> Array[ArmyState]:
	# Use movement system position cache when valid
	if movement_system and movement_system.positions_fresh():
		var cached: Array = movement_system._army_positions.get(coord, [])
		var result: Array[ArmyState] = []
		for a: ArmyState in cached:
			result.append(a)
		return result
	var result: Array[ArmyState] = []
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			result.append(army)
	return result

func get_enemies_at_tile(coord: Vector2i, my_faction: StringName) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army in get_armies_at_tile(coord):
		if army.faction_id == my_faction:
			continue
		var relation := get_relation(my_faction, army.faction_id)
		if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
			result.append(army)
	return result

func get_relation(faction_a: StringName, faction_b: StringName) -> Enums.FactionRelation:
	if faction_a == faction_b:
		return Enums.FactionRelation.ALLIED
	var ikey := _relation_key(faction_a, faction_b)
	if _relation_cache.has(ikey):
		return _relation_cache[ikey]
	var skey := StringName(str(faction_a) + ":" + str(faction_b))
	var rel: Enums.FactionRelation = state.diplomacy.get(skey, Enums.FactionRelation.NEUTRAL)
	_relation_cache[ikey] = rel
	return rel

static func _relation_key(a: StringName, b: StringName) -> int:
	return a.hash() * 31 + b.hash()

func clear_relation_cache() -> void:
	_relation_cache.clear()

func merge_armies_at_tile(coord: Vector2i, faction_id: StringName, prefer_army_id: StringName = &"") -> void:
	var armies_here: Array[ArmyState] = []
	for aid in state.armies:
		var army: ArmyState = state.armies[aid]
		if army.hex_pos == coord and army.faction_id == faction_id and not army.is_garrison:
			armies_here.append(army)
	if armies_here.size() <= 1:
		return
	# Prefer the specified army as merge target
	var target: ArmyState = armies_here[0]
	if prefer_army_id != &"":
		for a in armies_here:
			if a.army_id == prefer_army_id:
				target = a
				break
	for a in armies_here:
		if a.army_id == target.army_id:
			continue
		for unit in a.units:
			target.units.append(unit)
		# Keep the higher-level commander, return the other to pool
		if a.commander and target.commander:
			if a.commander.level > target.commander.level:
				# Return target's weaker commander to pool
				var fs: FactionState = state.faction_states.get(faction_id)
				if fs:
					fs.commander_pool.append(target.commander)
				target.commander = a.commander
				target.commander_name = a.commander.name
			# The merged army's commander will be returned by remove_army
		elif a.commander and target.commander == null:
			target.commander = a.commander
			target.commander_name = a.commander.name
		# Clear commander before remove_army so it doesn't double-return
		a.commander = null
		remove_army(a.army_id)

func can_afford_settlement(faction_id: StringName) -> bool:
	var fs: FactionState = state.faction_states.get(faction_id)
	if fs == null:
		return false
	for res_type in CitySystem.SETTLEMENT_FOUNDING_COST:
		if fs.resources.get(res_type, 0) < CitySystem.SETTLEMENT_FOUNDING_COST[res_type]:
			return false
	return true

func found_settlement(faction_id: StringName, hex_pos: Vector2i, parent_city_id: StringName) -> StringName:
	var parent_city: CityState = state.cities.get(parent_city_id)
	if parent_city == null:
		return &""

	var tile := state.hex_map.get_tile(hex_pos)
	if tile == null:
		return &""

	# Deduct founding cost (Cinderguard pays half — scrappy frontier builders)
	var fs: FactionState = state.faction_states.get(faction_id)
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var is_cg := parent_fid == &"cinderguard"
	if fs:
		for res_type in CitySystem.SETTLEMENT_FOUNDING_COST:
			var cost: int = CitySystem.SETTLEMENT_FOUNDING_COST[res_type]
			if is_cg:
				cost = cost / 2
			fs.resources[res_type] = fs.resources.get(res_type, 0) - cost

	var city := CityState.new()
	city.city_id = state.generate_id()
	city.region_id = tile.region_id
	city.faction_id = faction_id
	city.hex_pos = hex_pos
	city.level = 1
	city.population = 50 if not is_cg else 80
	city.is_capital = false
	city.is_settlement = true
	city.original_faction_id = faction_id
	city.loyalty = 50
	city.class_loyalty = {
		"peasants": 50, "artisans": 50, "scholars": 50, "nobles": 50, "captives": 0
	}
	city.turns_since_capture = -1
	state.cities[city.city_id] = city
	invalidate_completion_cache()
	city_system.invalidate_region_effects_cache()

	if fs:
		fs.owned_cities.append(city.city_id)

	# Mark parent capital as having used its founding ability
	parent_city.can_found_settlement = false

	return city.city_id

# ── Sunblessed Camp ────────────────────────────────────────

func setup_sunblessed_camp(army_id: StringName) -> StringName:
	## Sunblessed army with a commander sets up camp: creates a temporary city.
	## Returns the camp city_id or &"" on failure.
	var army: ArmyState = state.armies.get(army_id)
	if army == null or army.is_camp:
		return &""
	if army.commander == null:
		return &""
	# Require > half movement remaining to set up camp
	if army.movement_remaining <= army.get_max_movement() * 0.5:
		return &""
	var tile: HexMapData.TileState = state.hex_map.get_tile(army.hex_pos)
	if tile == null:
		return &""
	# Check if army has a mobile camp city — re-use it instead of creating new
	if army.camp_city_id != &"" and state.cities.has(army.camp_city_id):
		var city: CityState = state.cities[army.camp_city_id]
		# is_mobile_camp now doubles as the camp's PERMANENT identity marker
		# (see is_building_allowed_for) as well as the pre-existing "currently
		# on the move" signal consumed by calculate_city_income — settling
		# back down must NOT clear it, or the settlement-building partition
		# would wrongly re-apply to a re-settled camp. calculate_city_income
		# derives the actual "is it moving right now" 80%-income check from
		# the army's own is_camp flag instead, so this stays true here.
		city.is_mobile_camp = true
		city.hex_pos = army.hex_pos
		city_system.invalidate_city_hex_index()
		city.region_id = tile.region_id if tile else &""
		army.is_camp = true
		army.movement_remaining = 0.0
		return city.city_id
	# Create camp city at army position
	var city := CityState.new()
	city.city_id = state.generate_id()
	city.city_name = army.get_commander_name() + "'s Camp"
	city.region_id = tile.region_id if tile else &""
	city.faction_id = army.faction_id
	city.hex_pos = army.hex_pos
	city.level = 1
	city.population = 30
	city.is_capital = false
	city.is_settlement = true
	# Permanent camp identity (see is_building_allowed_for): Sunblessed camps
	# keep full faction building access, unlike founded frontier settlements.
	city.is_mobile_camp = true
	city.original_faction_id = army.faction_id
	city.loyalty = 60
	city.class_loyalty = {
		"peasants": 60, "artisans": 50, "scholars": 40, "nobles": 40, "captives": 0
	}
	city.turns_since_capture = -1
	state.cities[city.city_id] = city
	invalidate_completion_cache()
	city_system.invalidate_region_effects_cache()
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs:
		fs.owned_cities.append(city.city_id)
	army.is_camp = true
	army.camp_city_id = city.city_id
	army.movement_remaining = 0.0
	# Restore saved buildings/queue from previous camp
	if army.camp_saved_buildings.size() > 0:
		city.buildings = army.camp_saved_buildings.duplicate()
		army.camp_saved_buildings.clear()
	if army.camp_saved_build_queue.size() > 0:
		city.build_queue = army.camp_saved_build_queue.duplicate()
		army.camp_saved_build_queue.clear()
	return city.city_id

func break_sunblessed_camp(army_id: StringName) -> bool:
	## Break camp: converts camp city to mobile (80% income) instead of removing it.
	var army: ArmyState = state.armies.get(army_id)
	if army == null or not army.is_camp:
		return false
	var city_id := army.camp_city_id
	if city_id != &"" and state.cities.has(city_id):
		var city: CityState = state.cities[city_id]
		# Save buildings and build queue to army for persistence
		army.camp_saved_buildings = city.buildings.duplicate()
		army.camp_saved_build_queue = city.build_queue.duplicate()
		# Already true (permanent camp identity, set at setup_sunblessed_camp)
		# for any camp created/settled post-fix; kept as an explicit backfill
		# so a pre-fix save's still-settled camp gets correctly marked the
		# moment it's broken, instead of staying misclassified indefinitely.
		city.is_mobile_camp = true
	army.is_camp = false
	return true

func recruit_to_army(army_id: StringName, unit_data_id: StringName) -> bool:
	## Sunblessed: recruit a unit directly into an army (basic units only, no camp needed).
	var army: ArmyState = state.armies.get(army_id)
	if army == null:
		return false
	var ud := DataManager.get_unit(unit_data_id)
	if ud == null:
		return false
	# Only faction basic unit can be recruited without a camp
	var basic_unit: StringName = CityState.FACTION_BASIC_UNITS.get(army.faction_id, &"")
	if unit_data_id != basic_unit:
		return false
	# Check cost
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs == null:
		return false
	for res_type in ud.recruit_cost:
		if fs.resources.get(res_type, 0) < ud.recruit_cost[res_type]:
			return false
	# Deduct cost
	for res_type in ud.recruit_cost:
		fs.resources[res_type] = fs.resources.get(res_type, 0) - ud.recruit_cost[res_type]
	# Spawn unit
	var instance := UnitInstance.new()
	instance.init_from_data(ud, state.generate_id())
	army.units.append(instance)
	EventBus.unit_recruited.emit(&"", unit_data_id, army_id)
	return true

func get_faction_armies(faction_id: StringName) -> Array[ArmyState]:
	if not _faction_army_cache_valid:
		rebuild_faction_army_cache()
	var all: Array = _faction_army_cache.get(faction_id, [])
	var result: Array[ArmyState] = []
	for army: ArmyState in all:
		if not army.is_garrison:
			result.append(army)
	return result

func get_all_faction_armies(faction_id: StringName) -> Array:
	## Returns ALL armies for faction (including garrisons). Uses cache.
	if not _faction_army_cache_valid:
		rebuild_faction_army_cache()
	return _faction_army_cache.get(faction_id, [])

func move_army_along_path(army_id: StringName, path: Array[Vector2i]) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or path.is_empty():
		return
	# Keep the position cache fresh and update it incrementally per step
	# (previously invalidated wholesale, forcing O(all armies) fallbacks for
	# every per-step lookup below).
	movement_system._ensure_cache()
	# Injured elderbeast prevents army movement
	if army.elderbeast_id != &"":
		var beast: ElderbeastState = state.elderbeasts.get(army.elderbeast_id)
		if beast and beast.is_injured():
			return

	for tile_coord in path:
		var cost := state.hex_map.get_movement_cost(tile_coord, army.faction_id)
		# Apply army terrain stride modifier (junglestrider, desertstrider, etc.)
		var tile := state.hex_map.get_tile(tile_coord)
		if tile:
			cost *= army.get_terrain_stride_modifier(tile.terrain)
		if army.movement_remaining < cost:
			break

		# Check if army is leaving a besieged city hex
		_check_siege_departure(army)

		var from_pos := army.hex_pos
		army.hex_pos = tile_coord
		movement_system.update_army_position(army, from_pos, tile_coord)
		army.movement_remaining -= cost
		army.has_moved = true
		# Sync elderbeast position with army
		if army.elderbeast_id != &"":
			var beast: ElderbeastState = state.elderbeasts.get(army.elderbeast_id)
			if beast:
				var old_beast_pos := beast.hex_pos
				beast.hex_pos = tile_coord
				movement_system.update_beast_position(old_beast_pos, tile_coord, beast.faction_id)
				EventBus.elderbeast_moved.emit(beast.beast_id, old_beast_pos, tile_coord)
		EventBus.army_moved.emit(army_id, from_pos, tile_coord)

		# Check for battle
		var enemies := get_enemies_at_tile(tile_coord, army.faction_id)
		if enemies.size() > 0:
			EventBus.battle_initiated.emit(army_id, enemies[0].army_id, tile_coord)
			return

		# Check for enemy city at this hex → garrison battle or siege
		var city_at := city_system.get_city_at_hex(tile_coord)
		if city_at and city_at.faction_id != army.faction_id:
			if not city_at.is_under_siege or city_at.siege_faction != army.faction_id:
				# Skip garrison if already defeated this turn or garrison completely destroyed
				if city_at.garrison_defeated_turn >= state.current_turn or city_at.garrison_hp_ratio <= 0.0:
					pass # Garrison destroyed — proceed to siege
				else:
					# Spawn garrison army and fight before siege can begin
					var garrison := city_system.create_garrison_army(city_at)
					state.armies[garrison.army_id] = garrison
					_faction_army_cache_valid = false
					EventBus.battle_initiated.emit(army_id, garrison.army_id, tile_coord)
					return

		# Break siege on own cities if army arrives
		if city_at and city_at.faction_id == army.faction_id and city_at.is_under_siege:
			city_system.break_siege(city_at.city_id)

		# Claim unclaimed shards
		_try_claim_shard(tile_coord, army.faction_id)

		# Merge with friendly army at this tile
		var friendly_armies := get_armies_at_tile(tile_coord)
		if friendly_armies.size() > 1:
			merge_armies_at_tile(tile_coord, army.faction_id, army_id)
			if not state.armies.has(army_id):
				return # This army was absorbed into another

		# Take ownership of neutral tiles in the region (skip mountains/water)
		var region_tile := state.hex_map.get_tile(tile_coord)
		if region_tile and region_tile.owner_faction == &"":
			if region_tile.terrain != Enums.TerrainType.MOUNTAINS and region_tile.terrain != Enums.TerrainType.WATER:
				region_tile.owner_faction = army.faction_id
				state.hex_map.invalidate_region_owner(region_tile.region_id)

func _check_siege_departure(army: ArmyState) -> void:
	# Pressure model: leaving does NOT end the siege. If no besieger remains,
	# _process_sieges decays the pressure and lifts the siege at zero. This keeps
	# a determined attacker able to step out and back without restarting.
	pass

func _try_claim_shard(hex_pos: Vector2i, faction_id: StringName) -> void:
	# Block claiming if shard guardian army still alive at this hex
	for army: ArmyState in get_armies_at_tile(hex_pos):
		if army.faction_id == &"shard_guardians":
			return
	for shard_id in state.active_shards:
		var shard: ShardInstance = state.active_shards[shard_id]
		if shard.hex_pos == hex_pos and shard.claimed_by == &"":
			shard.claimed_by = faction_id
			var fs: FactionState = state.faction_states.get(faction_id)
			if fs:
				fs.owned_shards.append(shard_id)
				# Award Shard Essence based on power_level (15 base + 5 per extra power)
				var shard_value: int = 15 + (shard.power_level - 1) * 5
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + shard_value
			EventBus.shard_claimed.emit(shard_id, faction_id)
			break

func remove_army(army_id: StringName) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army:
		# Return commander to pool if army had one
		if army.commander:
			var fs: FactionState = state.faction_states.get(army.faction_id)
			if fs:
				fs.commander_pool.append(army.commander)
			army.commander = null
		EventBus.army_destroyed.emit(army_id, army.faction_id)
		movement_system.remove_army_position(army)
		state.armies.erase(army_id)
		_faction_army_cache_valid = false

func change_region_owner(region_id: StringName, _new_owner_hint: StringName) -> void:
	# Find current region owner from owned_regions tracking
	var old_owner: StringName = &""
	for fid in state.faction_states:
		var fs: FactionState = state.faction_states[fid]
		if region_id in fs.owned_regions:
			old_owner = fid
			break

	# Recompute per-city Voronoi territory for this region
	_recompute_region_territory(region_id)

	# Determine new region owner from city majority
	var new_owner := _get_region_majority_faction(region_id)

	# Update owned_regions if changed
	if old_owner != new_owner:
		if old_owner != &"":
			var old_fs: FactionState = state.faction_states.get(old_owner)
			if old_fs:
				old_fs.owned_regions.erase(region_id)
		if new_owner != &"":
			var new_fs: FactionState = state.faction_states.get(new_owner)
			if new_fs and not new_fs.owned_regions.has(region_id):
				new_fs.owned_regions.append(region_id)
		# Landmark/lease-relevant caches: region transfer can change research effects
		# (e.g. Leyline Well ownership changing the socket-bonus multiplier).
		if old_owner != &"":
			research_system._invalidate_cache(old_owner)
		if new_owner != &"":
			research_system._invalidate_cache(new_owner)

	# Grant a new general when a player fully captures a region from another faction
	if new_owner != &"" and old_owner != &"" and new_owner != old_owner:
		var all_cities_owned := true
		for city_id in state.cities:
			var city: CityState = state.cities[city_id]
			if city.region_id == region_id and city.faction_id != new_owner:
				all_cities_owned = false
				break
		if all_cities_owned:
			var cap_fs: FactionState = state.faction_states.get(new_owner)
			if cap_fs:
				var cmd := _create_commander(new_owner)
				cap_fs.commander_pool.append(cmd)
				TurnManager.turn_log.append({
					"type": "general",
					"text": "A new general, %s, has rallied to your banner!" % cmd.name,
				})

	EventBus.region_ownership_changed.emit(region_id, old_owner, new_owner)
