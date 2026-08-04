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
## btn_pressed,btn_disabled,notification,seal}.png plus a per-set contact
## sheet assets/sprites/ui/generated/_contact_<set_id>.png (also copied to
## the session scratchpad) proving all 7 pieces plus a 400x260 nine-patch-
## stretched sample of the frame piece via a real StyleBoxTexture draw. On a
## full default run (all 12 sets: neutral + the 11 major factions) also
## produces assets/sprites/ui/generated/_contact_factions.png (also copied
## to the scratchpad) — one row per set with a frame thumb, all 4 button
## states, a magnified seal close-up cropped from the real baked frame
## corner, and (Task 5b round 2) the real 64x64 `<id>_seal.png` at native
## size, for the ART GATE.

const OUT_DIR := "res://assets/sprites/ui/generated"
const SCRATCH_DIR := "C:/Users/LUTZGR~1/AppData/Local/Temp/claude/D--Dokumente-Gamedesign-Beyond-FractureWars-FractureWars/60f5a753-2e0c-4d4a-bf21-4fb3197d9a6c/scratchpad"

## ─────────────────────────────────────────────────────────────────────────
## Geometry CONTRACT — Task 3 of the UI-overhaul plan copies these verbatim
## into game_manager.gd's StyleBoxTexture factories. Corner/top-center seals
## must live entirely inside the margin bands below so nine-patch stretching
## never distorts them. Task 5b round 2 (ART GATE seal-readability request):
## FRAME_MARGIN 24 -> 32 (moves together with game_manager.gd's _FRAME_MARGIN
## and _FRAME_CONTENT — content margin must stay >= texture margin, see that
## file's GOTCHA comment) so the corner seals have more room; frame/
## notification seal draw radii scaled up to match (see _paint_frame /
## _paint_notification below); SEAL_SIZE is the new standalone wax-seal piece
## (transparent background, no nine-patch margin of its own — it's placed by
## whoever consumes it, not stretched).
## ─────────────────────────────────────────────────────────────────────────
const FRAME_SIZE := Vector2i(192, 192)       # frame nine-patch canvas
const FRAME_MARGIN := 32                     # nine-patch texture margin, all 4 sides (corner seals live inside this band)
const BTN_SIZE := Vector2i(96, 48)           # button nine-patch canvas
const BTN_MARGIN := 12                       # button nine-patch margin
const NOTIF_SIZE := Vector2i(224, 224)
const NOTIF_MARGIN := 32
const SEAL_SIZE := Vector2i(64, 64)          # standalone wax-seal piece, transparent bg, no nine-patch

const PIECES := ["frame", "btn_normal", "btn_hover", "btn_pressed", "btn_disabled", "notification", "seal"]

const CONTACT_VP_SIZE := Vector2i(940, 410)  # +30 (Task 5b round 2) for the new standalone-seal row
const STRETCH_SAMPLE_SIZE := Vector2(400.0, 260.0)

## Task 2's multi-set contact sheet — one row per SETS entry (12 with neutral
## + the 11 factions), each row showing a frame thumb, all 4 button states,
## a magnified seal close-up cropped from the corner cell of the same baked
## frame texture (so it proves motif legibility straight off the real bake,
## not a re-rendered approximation), and (Task 5b round 2) the standalone
## `<id>_seal.png` at its REAL 64x64 size, unscaled — the magnified crop can
## flatter small-scale legibility, so the real-size column is the honest
## check.
const FACTIONS_CONTACT_ROW_H := 100.0
const FACTIONS_CONTACT_HEADER_H := 50.0
const FACTIONS_CONTACT_VP_SIZE := Vector2i(820, 1270)

## Per-set palette table — data, not code branches (Task 2 appends the 11
## faction rows here; painters below stay unchanged and read only these
## fields). Keep in sync with scripts/ui/ui_palette.gd (Task 3): that file
## duplicates these values for runtime color decisions; this table is
## tool-side and bakes pixels.
## Record shape (Task 5b round 2, ART GATE 3-color-presence request):
## {parchment, parchment_dark, ink, heraldry, secondary, accent, motif}.
## `seal` (round 1's field name) is RETIRED — its role (the wax-seal disc
## color) is now `secondary`, so every SETS row needed a rename, not just a
## value tweak. Color ROLES, all now visibly distinct per set instead of
## round 1's "everything reads as heraldry" monochrome:
##   heraldry  (primary)   -> pressed-button fill, bar fills (unchanged role)
##   secondary             -> frame's INNER wobble-border line (outer line
##                             stays `ink`), button HOVER border emphasis
##                             (replaces heraldry there), seal wax disc
##   accent    (tertiary)  -> seal emboss-highlight ring AND the seal's
##                             motif fill (both were heraldry-derived in
##                             round 1, reading as "dark-on-dark"; _paint_seal
##                             now feeds the motif painter a `pal` copy with
##                             `heraldry` swapped for `accent` instead of
##                             touching any `_motif_*` function — geometry
##                             stays untouched, only which color the existing
##                             heraldry-reads resolve to), plus the frame's
##                             thin title-bar underline
## `accent` is now REQUIRED on every row (round 1 made it optional, wired
## only for forsaken/tainted_jade) since _paint_seal's emboss ring and motif
## recolor are unconditional now — every set needs a real value.
const SETS := {
	&"neutral": {  # no chart (base/unthemed style) — secondary invented as a
		# cool ink-well grey-blue (hue ~174 deg from the warm gold heraldry,
		# strong separation); accent a pale warm gold-cream emboss highlight.
		parchment = Color(0.85, 0.79, 0.66),
		parchment_dark = Color(0.24, 0.21, 0.17),
		ink = Color(0.16, 0.13, 0.10),
		heraldry = Color(0.62, 0.52, 0.30),
		secondary = Color(0.26, 0.29, 0.32),
		accent = Color(0.85, 0.77, 0.47),
		motif = &"quill",
	},
	# ── 11 major faction sets. Task 5b round 1 (docs/faction_color_alignment.md,
	# the designer-approved SoB colour chart) replaced 10 of these 11 rows'
	# heraldry/ink/parchment with values derived from each faction's chart
	# Primary/Secondary/Tertiary colors (heraldry=chart Primary, ink=darkest
	# chart color, parchment=lightest chart color pulled into the readability
	# band — hand-tuned per-row where a raw chart value fought contrast; see
	# the doc's per-faction table for exact reasoning). Task 5b round 2 (ART
	# GATE feedback: palettes read monochrome — primary dominated, secondary
	# looked like darker-primary, tertiary was nearly absent) reworked
	# `secondary`/`accent` so all three chart colors are genuinely visible:
	# wherever the chart's Secondary/Tertiary color was still "free" (not
	# already spent on ink/parchment in round 1), it was pulled in here
	# directly — see each row's comment for exactly which chart color feeds
	# which field. Two factions (cinderguard, forsaken) had their chart
	# Secondary REASSIGNED here from `ink` to `secondary` so it reads as its
	# own hue instead of matching the border color — `ink` for those two
	# became a small generic near-neutral-dark tone instead (ink was never
	# required to be literally chart-sourced; several rows already synthesize
	# it). Three factions (skulloath, ivoryscar, and — for `accent` only —
	# thunderswarm/cinderguard/neutral/empire) have all 3 chart hues already
	# claimed by ink/parchment/heraldry with nothing left over, so their
	# `secondary`/`accent` are INVENTED complementary tones, documented as
	# such per-row — not a chart-fidelity gap, a mathematical one (3 chart
	# colors, more than 3 chrome roles once secondary+accent are real roles).
	# Empire is not on the chart; its heraldry/ink/parchment stay untouched,
	# only secondary/accent are new (also invented, see its row).
	# All heraldry stays hand-tuned toward ink-compatible saturation
	# (s ~0.35-0.60, v ~0.36-0.62, matching neutral's heraldry weight) —
	# UNCHANGED from round 1 (this request only touches secondary/accent/the
	# 2 reassigned inks).
	# `parchment` is the BINDING readability band: v 0.70-0.88, s <= 0.25 for
	# all 11 (verified via a scratch HSV script per Task 5b's report) —
	# UNCHANGED from round 1.
	# `parchment_dark` (stain tone) is re-derived from `parchment` via the
	# same relative darkening every row already used (same hue, s+~0.10,
	# v*~0.30) — UNCHANGED from round 1.
	&"empire": {  # clean warm heraldry/ink/parchment stay close to neutral's
		# warm cream (unchanged from round 1 — not on the chart). secondary/
		# accent invented for round 2: a Roman gold/bronze secondary (~177
		# deg from the blue heraldry) fits the laurel_shield motif; accent a
		# pale ivory/banner-white emboss highlight.
		parchment = Color(0.86, 0.82, 0.73),
		parchment_dark = Color(0.26, 0.24, 0.19),
		ink = Color(0.15, 0.13, 0.10),
		heraldry = Color(0.29, 0.36, 0.50),
		secondary = Color(0.45, 0.38, 0.20),
		accent = Color(0.88, 0.83, 0.69),
		motif = &"laurel_shield",
	},
	&"skulloath": {  # SoB chart: primary Black #000000, secondary Maroon
		# #950a0a, tertiary Bone #f2ebe3. Ink = primary (near-black, kept
		# just off literal 0/0/0 for warmth); heraldry = secondary maroon
		# (raw hex is too saturated/bright for a pressed-button fill,
		# hand-tuned per mapping rule 1); parchment = tertiary bone pulled
		# into the readability band — replaces the old dusty-rose tone.
		# Round 2: all 3 chart hues are already claimed above, so secondary/
		# accent are INVENTED — a deep aged-horn brown secondary (wax-seal
		# disc/inner-border/hover, ~27 deg off the maroon heraldry) and a
		# pale trophy-gold accent (emboss/motif), fitting a skull-and-bone
		# trophy aesthetic.
		parchment = Color(0.78, 0.73, 0.68),
		parchment_dark = Color(0.23, 0.21, 0.18),
		ink = Color(0.06, 0.04, 0.04),
		heraldry = Color(0.50, 0.21, 0.21),
		secondary = Color(0.32, 0.24, 0.18),
		accent = Color(0.80, 0.70, 0.36),
		motif = &"horned_skull",
	},
	&"gladehost": {  # SoB chart: primary Teal #3bbcbc, secondary Beige
		# #EFE7db, tertiary Autumn Red #F17363. heraldry = primary teal
		# (tuned darker than raw hex for pressed-button contrast); parchment
		# = secondary beige, pulled a touch below the raw hex's v=0.937 to
		# stay inside the 0.70-0.88 band; ink synthesized as a deep
		# teal-grey (not chart-literal).
		# Round 2: secondary = beige's OWN hue, darkened into wax-seal
		# weight (v~0.30) — beige itself stays parchment at a much lighter
		# value, so reusing the hue at a different value isn't a conflict,
		# and it reads as clearly different from the teal heraldry (~144
		# deg apart). accent = tertiary autumn red, brightened for emboss
		# pop (now WIRED — round 1 only recorded it as unused data).
		parchment = Color(0.85, 0.81, 0.75),
		parchment_dark = Color(0.26, 0.23, 0.20),
		ink = Color(0.10, 0.13, 0.13),
		heraldry = Color(0.19, 0.42, 0.42),
		secondary = Color(0.30, 0.26, 0.20),
		accent = Color(0.92, 0.43, 0.37),
		motif = &"leaf",
	},
	&"moonspear": {  # SoB chart: primary Blue #3847cb, secondary Light Gray
		# #8c8c8c, tertiary Silver #c0c0c0. heraldry = primary, tuned to a
		# vivid-but-button-safe blue; parchment is a light cool tint (not
		# literally chart-sourced any more — round 2 frees the chart's
		# secondary/tertiary greys for their own roles below instead of
		# blending both into parchment); ink stays the existing navy-black.
		# Round 2: secondary = chart Secondary Light Gray's hue, tuned;
		# accent = chart Tertiary Silver, brighter still — both are
		# essentially achromatic (the chart itself gives moonspear a
		# saturated-blue-primary + neutral-greys identity), so secondary and
		# accent read apart from heraldry mainly by saturation/value, not
		# hue — a chart-faithful "steel and silver" look, not an execution
		# gap.
		parchment = Color(0.75, 0.76, 0.81),
		parchment_dark = Color(0.20, 0.21, 0.24),
		ink = Color(0.11, 0.12, 0.15),
		heraldry = Color(0.26, 0.29, 0.58),
		secondary = Color(0.39, 0.40, 0.42),
		accent = Color(0.77, 0.77, 0.80),
		motif = &"crescent",
	},
	&"sunblessed": {  # SoB chart: primary Gold #f7e689, secondary Mint
		# Green #98FF98, tertiary Silver #c0c0c0. heraldry = primary gold,
		# darkened well below the raw hex's v=0.969 — its pressed-state text
		# is UIPalette.PARCHMENT (light), so heraldry needs real separation
		# from that value to stay readable. Parchment/ink unchanged (never
		# chart-sourced for this faction).
		# GATE round-1 self-critique: a first pass at heraldry v=0.55 only
		# reached ~2.6:1 WCAG contrast against the PARCHMENT-colored
		# pressed-state text — pushed down to v=0.46 for ~3.47:1.
		# Round 2: secondary = chart Secondary Mint Green, tamed from its
		# raw v=1.0 into wax-seal weight (v~0.42) — genuinely GREEN against
		# the gold heraldry (~69 deg apart), unlike round 1's unused mint
		# note. accent = chart Tertiary Silver (now WIRED).
		parchment = Color(0.87, 0.81, 0.66),
		parchment_dark = Color(0.26, 0.24, 0.17),
		ink = Color(0.16, 0.13, 0.10),
		heraldry = Color(0.46, 0.42, 0.18),
		secondary = Color(0.19, 0.42, 0.19),
		accent = Color(0.78, 0.80, 0.78),
		motif = &"sun",
	},
	&"shardhorde": {  # SoB chart: primary Brown #964b00, secondary Olive
		# Green #5a8000, tertiary Dark Lavender #734F96. heraldry = primary
		# brown; parchment = a warm neutral tint from the brown family,
		# banded; ink deepened to match.
		# Round 2: secondary = chart Secondary Olive Green (same hue round 1
		# already used for the old `seal` field, kept — just renamed/
		# re-darkened slightly). accent = chart Tertiary Dark Lavender,
		# brightened for emboss pop (now WIRED — round 1 only recorded it as
		# unused data after the old magenta heraldry was retired).
		parchment = Color(0.82, 0.76, 0.71),
		parchment_dark = Color(0.25, 0.22, 0.19),
		ink = Color(0.13, 0.11, 0.08),
		heraldry = Color(0.50, 0.35, 0.20),
		secondary = Color(0.25, 0.30, 0.12),
		accent = Color(0.73, 0.57, 0.88),
		motif = &"crystal_shard",
	},
	&"thunderswarm": {  # SoB chart: primary Orange #f28536, secondary Dark
		# Brown #6c4837, tertiary Cream #fffdd0. heraldry = primary orange,
		# darkened for pressed-state text contrast; parchment = tertiary
		# cream pulled into the readability band; ink deepened to match the
		# secondary's dark brown.
		# Round 2: secondary = chart Secondary Dark Brown (same hue round 1
		# already used for `ink`/old `seal`, kept — the chart's own orange
		# primary + dark-brown secondary sit only ~6 deg apart in hue, so
		# this pairing is close by chart design, not by under-tuning; value
		# keeps them apart instead). accent is INVENTED (tertiary cream is
		# already spent on parchment) — a pale spark-gold "lightning flash"
		# highlight, distinctly brighter than both.
		parchment = Color(0.82, 0.82, 0.70),
		parchment_dark = Color(0.25, 0.24, 0.18),
		ink = Color(0.13, 0.10, 0.08),
		heraldry = Color(0.52, 0.34, 0.21),
		secondary = Color(0.30, 0.19, 0.13),
		accent = Color(0.90, 0.87, 0.59),
		motif = &"bolt",
	},
	&"cinderguard": {  # SoB chart: primary Crimson #c4092e, secondary
		# Charcoal #42525d, tertiary White #f5f5f5. heraldry = primary,
		# retuned from ember-orange to a true crimson; parchment kept warm
		# but desaturated a touch toward the tertiary white.
		# Round 2 REASSIGNMENT: round 1 put chart-secondary charcoal on
		# `ink`, which meant the wax-seal disc (old `seal`, a darkened-
		# heraldry derivative) never showed charcoal's own hue anywhere.
		# Charcoal now IS `secondary` (~148 deg from the crimson heraldry);
		# `ink` becomes a small generic near-neutral-dark tone instead (not
		# chart-literal — several other rows already do this). accent is
		# INVENTED (tertiary white was nudged into parchment, not free) — a
		# warm ember-gold emboss highlight.
		parchment = Color(0.85, 0.77, 0.72),
		parchment_dark = Color(0.26, 0.21, 0.19),
		ink = Color(0.07, 0.06, 0.06),
		heraldry = Color(0.52, 0.21, 0.25),
		secondary = Color(0.28, 0.35, 0.40),
		accent = Color(0.85, 0.69, 0.38),
		motif = &"anvil_flame",
	},
	&"forsaken": {  # SoB chart: primary Purple #9a0174, secondary Slate
		# Gray #708090, tertiary Gold #ffd700. heraldry = primary purple;
		# parchment stays grey-violet (slate-tinted, not chart-literal).
		# Round 2 REASSIGNMENT (same reasoning as cinderguard): round 1 put
		# chart-secondary slate on `ink`. Slate now IS `secondary` (~106 deg
		# from the purple heraldry); `ink` becomes a small generic
		# near-neutral-dark tone instead. accent = chart Tertiary Gold —
		# UNCHANGED from round 1, already wired (the doc's named concrete
		# use: "seal emboss highlight -> gold accent").
		parchment = Color(0.72, 0.72, 0.79),
		parchment_dark = Color(0.20, 0.19, 0.24),
		ink = Color(0.07, 0.06, 0.07),
		heraldry = Color(0.42, 0.19, 0.36),
		secondary = Color(0.31, 0.36, 0.40),
		accent = Color(0.90, 0.78, 0.14),
		motif = &"broken_mask",
	},
	&"ivoryscar": {  # SoB chart: primary Bone #f2ebe3, secondary Black
		# #212121, tertiary Warm Gray #c9be90. parchment = primary bone,
		# pinned safely inside the band; ink = secondary black, warmed with
		# a touch of hue; heraldry = tertiary warm gray, darkened.
		# GATE round-1 self-critique: pulling parchment off the v=0.880
		# band-edge quietly ate into pressed-button contrast (3.17:1 ->
		# 2.80:1 at first pass) — darkened heraldry to v=0.42 to recover
		# ~3.76:1.
		# Round 2: all 3 chart hues are already claimed above (same
		# situation as skulloath), so secondary/accent are INVENTED — a
		# terracotta/sandstone secondary and a gold-inlay accent, fitting
		# the Egyptian/pyramid motif (sandstone-and-gold-inlay tombware).
		parchment = Color(0.83, 0.80, 0.76),
		parchment_dark = Color(0.25, 0.23, 0.20),
		ink = Color(0.13, 0.11, 0.09),
		heraldry = Color(0.42, 0.39, 0.26),
		secondary = Color(0.35, 0.23, 0.17),
		accent = Color(0.82, 0.71, 0.33),
		motif = &"pyramid",
	},
	&"tainted_jade": {  # SoB chart: primary Green #30740f, secondary Dark
		# Purple #301934, tertiary Pale Yellow #d9d45c. heraldry SWAPS to
		# the chart's green primary (was purple pre-Task-5b — the doc calls
		# this out explicitly: chart makes green primary, purple secondary);
		# ink stays put (already green-hued); parchment snapped toward the
		# chart's green tint.
		# Round 2: secondary = chart Secondary Dark Purple (same value round
		# 1 already used for the old `seal` field, kept unchanged — this is
		# the doc's own "keep the dark secondary dark, lighten the emboss
		# instead" case). accent = chart Tertiary Pale Yellow — UNCHANGED
		# from round 1, already wired (fixes the doc's
		# weakest-seal-contrast ledger note).
		parchment = Color(0.73, 0.79, 0.70),
		parchment_dark = Color(0.20, 0.24, 0.18),
		ink = Color(0.10, 0.12, 0.09),
		heraldry = Color(0.28, 0.46, 0.19),
		secondary = Color(0.22, 0.11, 0.24),
		accent = Color(0.85, 0.83, 0.38),
		motif = &"fanged_blossom",
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
	var factions_mode := false
	var factions_set_ids: Array = []
	var factions_textures: Dictionary = {}  # set_id -> {piece -> Texture2D}, pre-built by the driver

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

	## Shared leaf/petal/flame/spearhead shape — a 4-point teardrop from
	## `base` to `tip`, `width` px across its midpoint. Reused by several
	## faction motifs (laurel leaves, the gladehost leaf, the moonspear
	## spear tip, cinderguard flame teeth, tainted_jade petals) instead of
	## each motif re-deriving the same perpendicular-offset math.
	func _leaf_poly(base: Vector2, tip: Vector2, width: float) -> PackedVector2Array:
		var dirv := tip - base
		var perp: Vector2
		if dirv.length() > 0.0001:
			perp = Vector2(-dirv.y, dirv.x).normalized()
		else:
			perp = Vector2(0.0, 1.0)
		var mid := base.lerp(tip, 0.5)
		return PackedVector2Array([base, mid + perp * width * 0.5, tip, mid - perp * width * 0.5])

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
	## `rect` at stroke width `widths[i]`, all in one `color` — the frame's
	## signature double-line border (called twice, once per color, since
	## Task 5b round 2 split it into an `ink` outer line + `secondary` inner
	## line) and, doubled up again, the notification's ornate variant.
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

	## Empire — laurel shield: a pointed pentagon shield with two small
	## flanking rows of laurel leaves (via _leaf_poly) arced up its sides.
	func _motif_empire(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var shield_col: Color = Color(pal.heraldry).lightened(0.10)
		var w := r * 0.42
		var top := -r * 0.55
		var shield_local := PackedVector2Array([
			Vector2(-w, top), Vector2(w, top),
			Vector2(w * 0.9, top + r * 0.55), Vector2(0.0, r * 0.85),
			Vector2(-w * 0.9, top + r * 0.55),
		])
		var placed := PackedVector2Array()
		for p in shield_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, shield_col)
		var closed := placed.duplicate()
		closed.append(placed[0])
		draw_polyline(closed, ink, max(1.0, r * 0.09), true)
		var leaf_col: Color = Color(pal.heraldry).darkened(0.05)
		for side in [-1.0, 1.0]:
			for i in range(3):
				var t := float(i) / 2.0
				var base_local := Vector2(side * w * 1.05, r * 0.75 - t * r * 0.5)
				var tip_local := Vector2(side * (w * 1.55 + t * r * 0.15), r * 0.55 - t * r * 0.75)
				var base_p := center + Vector2(base_local.x * mirror.x, base_local.y * mirror.y)
				var tip_p := center + Vector2(tip_local.x * mirror.x, tip_local.y * mirror.y)
				var leaf := _leaf_poly(base_p, tip_p, r * 0.22)
				draw_colored_polygon(leaf, leaf_col)
				var lc := leaf.duplicate()
				lc.append(leaf[0])
				draw_polyline(lc, ink, max(1.0, r * 0.06), true)

	## Skulloath — horned skull: bone-colored skull disc + jaw block, two
	## dark eye notches, and a pair of curved horn triangles above.
	## GATE FIX (self-critique round 2): at true seal scale (motif r~6.5px)
	## every outline stroke clamps to the same 1.0px minimum regardless of
	## its `r * 0.0X` multiplier, so a needle-thin sub-shape's own outline
	## covers most or all of its fill — the jaw's separate outline and the
	## original narrow-base horns were rendering as solid ink blobs with the
	## bone/horn fill barely surviving (verified via direct pixel sampling
	## of the baked PNG, not just the visual crop). Fix: drop the jaw's own
	## outline (it now reads as part of the skull disc's silhouette instead
	## of losing its fill to a second thin ring) and widen the horns' base
	## so their fill area meaningfully exceeds their outline's footprint.
	func _motif_skulloath(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var bone_col: Color = Color(pal.heraldry).lightened(0.35)
		draw_circle(center, r * 0.55, bone_col)
		draw_arc(center, r * 0.55, 0.0, TAU, 20, ink, max(1.0, r * 0.08))
		var jaw_local := PackedVector2Array([
			Vector2(-r * 0.30, r * 0.35), Vector2(r * 0.30, r * 0.35),
			Vector2(r * 0.20, r * 0.65), Vector2(-r * 0.20, r * 0.65),
		])
		var jaw_placed := PackedVector2Array()
		for p in jaw_local:
			jaw_placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(jaw_placed, bone_col)
		for side in [-1.0, 1.0]:
			var eye_local := Vector2(side * r * 0.22, -r * 0.05)
			var eye_p := center + Vector2(eye_local.x * mirror.x, eye_local.y * mirror.y)
			draw_circle(eye_p, r * 0.16, ink)
		var horn_col: Color = Color(pal.heraldry).lightened(0.20)
		for side in [-1.0, 1.0]:
			var horn_local := PackedVector2Array([
				Vector2(side * r * 0.18, -r * 0.30),
				Vector2(side * r * 0.68, -r * 0.80),
				Vector2(side * r * 0.58, -r * 0.18),
			])
			var horn_placed := PackedVector2Array()
			for p in horn_local:
				horn_placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
			draw_colored_polygon(horn_placed, horn_col)
			var hc := horn_placed.duplicate()
			hc.append(horn_placed[0])
			draw_polyline(hc, ink, max(1.0, r * 0.05), true)

	## Gladehost — leaf: single teardrop leaf (via _leaf_poly) with a center
	## vein spine and two pairs of angled side veins.
	func _motif_gladehost(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var leaf_col: Color = Color(pal.heraldry).lightened(0.12)
		var base_local := Vector2(0.0, r * 0.85)
		var tip_local := Vector2(0.0, -r * 0.85)
		var base_p := center + Vector2(base_local.x * mirror.x, base_local.y * mirror.y)
		var tip_p := center + Vector2(tip_local.x * mirror.x, tip_local.y * mirror.y)
		var leaf := _leaf_poly(base_p, tip_p, r * 0.85)
		draw_colored_polygon(leaf, leaf_col)
		var lc := leaf.duplicate()
		lc.append(leaf[0])
		draw_polyline(lc, ink, max(1.0, r * 0.09), true)
		draw_polyline(PackedVector2Array([base_p, center, tip_p]), ink, max(1.0, r * 0.06), true)
		for t in [0.3, 0.6]:
			var mid: Vector2 = base_p.lerp(tip_p, t)
			for side in [-1.0, 1.0]:
				var vein_end := mid + Vector2(side * r * 0.28 * mirror.x, -r * 0.12 * mirror.y)
				draw_line(mid, vein_end, ink, max(1.0, r * 0.05))

	## Moonspear — crescent: a lit-arc moon carved from two offset circles
	## (the second drawn in `pal.secondary` so it blends into the seal
	## backing — Task 5b round 2 renamed the old `pal.seal` field but the
	## blend-into-the-disc intent is unchanged), plus a small spearhead
	## hanging off the lower horn.
	func _motif_moonspear(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var moon_col: Color = Color(pal.heraldry).lightened(0.28)
		draw_circle(center, r * 0.6, moon_col)
		var cut_local := Vector2(r * 0.32, 0.0)
		var cut_p := center + Vector2(cut_local.x * mirror.x, cut_local.y * mirror.y)
		draw_circle(cut_p, r * 0.55, pal.secondary)
		draw_arc(center, r * 0.6, 0.0, TAU, 20, ink, max(1.0, r * 0.06))
		var tip_local := Vector2(-r * 0.05, r * 0.95)
		var spear_base_local := Vector2(-r * 0.15, r * 0.35)
		var tip_p := center + Vector2(tip_local.x * mirror.x, tip_local.y * mirror.y)
		var spear_base_p := center + Vector2(spear_base_local.x * mirror.x, spear_base_local.y * mirror.y)
		var spear := _leaf_poly(spear_base_p, tip_p, r * 0.16)
		draw_colored_polygon(spear, Color(pal.heraldry).darkened(0.10))
		var sc := spear.duplicate()
		sc.append(spear[0])
		draw_polyline(sc, ink, max(1.0, r * 0.05), true)

	## Sunblessed — sun: circle core + 8 triangular rays. Radially symmetric
	## so `mirror` needs no special handling (any reflection of a full ray
	## ring is itself).
	func _motif_sunblessed(pal: Dictionary, center: Vector2, r: float, _mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var sun_col: Color = Color(pal.heraldry).lightened(0.22)
		var core_r := r * 0.4
		for i in range(8):
			var ang := TAU * float(i) / 8.0
			var dirv := Vector2(cos(ang), sin(ang))
			var perp := Vector2(-dirv.y, dirv.x)
			var base_a := center + dirv * core_r * 0.9 + perp * r * 0.09
			var base_b := center + dirv * core_r * 0.9 - perp * r * 0.09
			var tip := center + dirv * r * 0.95
			draw_colored_polygon(PackedVector2Array([base_a, tip, base_b]), sun_col)
		draw_circle(center, core_r, sun_col)
		draw_arc(center, core_r, 0.0, TAU, 20, ink, max(1.0, r * 0.07))

	## Cinderguard — anvil over flame: a blocky anvil silhouette above three
	## teardrop flame tongues (via _leaf_poly) rising toward its underside.
	## GATE FIX (self-critique round 2): the original 8-point anvil traced a
	## notched "I-beam" waist whose thinnest segments (~0.1r) were narrower
	## than the outline's 1.0px-minimum stroke width, so the outline alone
	## covered the fill almost entirely (confirmed via direct pixel sampling
	## — anvil_col essentially never appeared in the baked PNG). Replaced
	## with a bold 6-point hexagon (flat top face, tapered body, still-wide
	## foot) where every cross-section stays well above that 1px floor.
	func _motif_cinderguard(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var anvil_col: Color = Color(pal.heraldry).lightened(0.15)  # lightened, not darkened: too close to pal.secondary's dark tone to survive render-time AA blending at seal scale (note: at seal scale this function receives motif_pal, whose `heraldry` is really the faction's `accent` — see _paint_seal)
		var anvil_local := PackedVector2Array([
			Vector2(-r * 0.55, -r * 0.25), Vector2(r * 0.55, -r * 0.25),
			Vector2(r * 0.38, r * 0.10), Vector2(r * 0.30, r * 0.55),
			Vector2(-r * 0.30, r * 0.55), Vector2(-r * 0.38, r * 0.10),
		])
		var placed := PackedVector2Array()
		for p in anvil_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, anvil_col)
		var ac := placed.duplicate()
		ac.append(placed[0])
		draw_polyline(ac, ink, max(1.0, r * 0.07), true)
		var flame_col: Color = Color(pal.heraldry).lightened(0.22)
		for i in range(3):
			var fx := (float(i) - 1.0) * r * 0.28
			var base_local := Vector2(fx, r * 0.95)
			var tip_local := Vector2(fx * 0.4, r * 0.65)  # below the taller anvil foot (now reaches r*0.55), was r*0.40
			var base_p := center + Vector2(base_local.x * mirror.x, base_local.y * mirror.y)
			var tip_p := center + Vector2(tip_local.x * mirror.x, tip_local.y * mirror.y)
			var flame := _leaf_poly(base_p, tip_p, r * 0.18)
			draw_colored_polygon(flame, flame_col)

	## Thunderswarm — bolt: classic 5-vertex lightning zigzag polygon.
	func _motif_thunderswarm(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var bolt_col: Color = Color(pal.heraldry).lightened(0.22)
		var bolt_local := PackedVector2Array([
			Vector2(r * 0.15, -r * 0.95),
			Vector2(-r * 0.35, r * 0.05),
			Vector2(r * 0.05, r * 0.05),
			Vector2(-r * 0.15, r * 0.95),
			Vector2(r * 0.35, -r * 0.05),
		])
		var placed := PackedVector2Array()
		for p in bolt_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, bolt_col)
		var bc := placed.duplicate()
		bc.append(placed[0])
		draw_polyline(bc, ink, max(1.0, r * 0.08), true)

	## Forsaken — broken mask: face oval, one filled eye + one empty (ring-
	## only) eye socket, split by a jagged hand-authored crack polyline.
	## GATE FIX (self-critique round 2): the oval's own outline plus the
	## crack plus both eye marks are 4 separate ink strokes inside a ~13px
	## motif — at that density even a lightened(0.28) fill was nearly
	## invisible in the baked PNG (direct pixel sampling found almost no
	## fill-colored pixels). Pushed the fill most of the way to the
	## parchment end of the scale so it still reads as a distinct pale
	## silhouette once the render's AA blends the surrounding ink strokes
	## into it.
	func _motif_forsaken(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var mask_col: Color = Color(pal.heraldry).lightened(0.65)
		var oval_local := PackedVector2Array([
			Vector2(0.0, -r * 0.85), Vector2(r * 0.5, -r * 0.5), Vector2(r * 0.55, r * 0.1),
			Vector2(r * 0.3, r * 0.75), Vector2(0.0, r * 0.9), Vector2(-r * 0.3, r * 0.75),
			Vector2(-r * 0.55, r * 0.1), Vector2(-r * 0.5, -r * 0.5),
		])
		var placed := PackedVector2Array()
		for p in oval_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, mask_col)
		var oc := placed.duplicate()
		oc.append(placed[0])
		draw_polyline(oc, ink, max(1.0, r * 0.08), true)
		var eye_local := Vector2(r * 0.22, -r * 0.15)
		var eye_p := center + Vector2(eye_local.x * mirror.x, eye_local.y * mirror.y)
		draw_circle(eye_p, r * 0.12, ink)
		var empty_local := Vector2(-r * 0.22, -r * 0.15)
		var empty_p := center + Vector2(empty_local.x * mirror.x, empty_local.y * mirror.y)
		draw_arc(empty_p, r * 0.12, 0.0, TAU, 12, ink, max(1.0, r * 0.05))
		# Shortened to 2 segments confined to the lower half (below the eye
		# line) — the original 4-segment crack ran top-to-bottom and, being
		# a 4th ink stroke inside the same ~13px motif, left almost no clean
		# fill area anywhere in the oval (confirmed via direct pixel
		# sampling of the baked PNG).
		var crack_local := [
			Vector2(-r * 0.05, -r * 0.10), Vector2(r * 0.12, r * 0.25), Vector2(-r * 0.05, r * 0.65),
		]
		var crack := PackedVector2Array()
		for p in crack_local:
			crack.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_polyline(crack, ink, max(1.0, r * 0.07), true)

	## Ivoryscar — pyramid: triangle silhouette with 3 horizontal terrace
	## step lines and a small diamond eye slit near the apex.
	func _motif_ivoryscar(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var stone_col: Color = Color(pal.heraldry).lightened(0.15)
		var tri_local := PackedVector2Array([
			Vector2(0.0, -r * 0.9), Vector2(r * 0.85, r * 0.75), Vector2(-r * 0.85, r * 0.75),
		])
		var placed := PackedVector2Array()
		for p in tri_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, stone_col)
		var tc := placed.duplicate()
		tc.append(placed[0])
		draw_polyline(tc, ink, max(1.0, r * 0.08), true)
		for t in [0.25, 0.5, 0.75]:
			var y: float = lerp(-r * 0.9, r * 0.75, t)
			var half_w: float = lerp(0.0, r * 0.85, t)
			var a := center + Vector2(-half_w * mirror.x, y * mirror.y)
			var b := center + Vector2(half_w * mirror.x, y * mirror.y)
			draw_line(a, b, ink, max(1.0, r * 0.04))
		var eye_local := Vector2(0.0, -r * 0.25)
		var eye_p := center + Vector2(eye_local.x * mirror.x, eye_local.y * mirror.y)
		draw_colored_polygon(PackedVector2Array([
			eye_p + Vector2(-r * 0.18, 0.0), eye_p + Vector2(0.0, -r * 0.09),
			eye_p + Vector2(r * 0.18, 0.0), eye_p + Vector2(0.0, r * 0.09),
		]), ink)

	## Tainted Jade — fanged blossom: 4 petals (via _leaf_poly, radiating
	## from the seal center) plus 2 pale fang triangles hanging below.
	func _motif_tainted_jade(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var petal_col: Color = Color(pal.heraldry).lightened(0.22)
		for i in range(4):
			var ang := TAU * float(i) / 4.0 + PI * 0.25
			var tip_local := Vector2(cos(ang), sin(ang)) * r * 0.85
			var tip_p := center + Vector2(tip_local.x * mirror.x, tip_local.y * mirror.y)
			var petal := _leaf_poly(center, tip_p, r * 0.45)
			draw_colored_polygon(petal, petal_col)
			var pc := petal.duplicate()
			pc.append(petal[0])
			draw_polyline(pc, ink, max(1.0, r * 0.05), true)
		var fang_col: Color = Color(pal.heraldry).lightened(0.40)
		for side in [-1.0, 1.0]:
			var fang_local := PackedVector2Array([
				Vector2(side * r * 0.12, r * 0.15),
				Vector2(side * r * 0.22, r * 0.15),
				Vector2(side * r * 0.06, r * 0.6),
			])
			var fp := PackedVector2Array()
			for p in fang_local:
				fp.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
			draw_colored_polygon(fp, fang_col)
			var fc := fp.duplicate()
			fc.append(fp[0])
			draw_polyline(fc, ink, max(1.0, r * 0.04), true)
		draw_circle(center, r * 0.12, ink)

	## Shardhorde — crystal shard: elongated hexagon with 3 inner facet
	## lines from alternating tips toward an off-center core.
	func _motif_shardhorde(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		var ink: Color = pal.ink
		var crystal_col: Color = Color(pal.heraldry).lightened(0.22)
		var hex_local := PackedVector2Array([
			Vector2(0.0, -r * 0.95), Vector2(r * 0.4, -r * 0.35), Vector2(r * 0.32, r * 0.55),
			Vector2(0.0, r * 0.9), Vector2(-r * 0.32, r * 0.55), Vector2(-r * 0.4, -r * 0.35),
		])
		var placed := PackedVector2Array()
		for p in hex_local:
			placed.append(center + Vector2(p.x * mirror.x, p.y * mirror.y))
		draw_colored_polygon(placed, crystal_col)
		var hc := placed.duplicate()
		hc.append(placed[0])
		draw_polyline(hc, ink, max(1.0, r * 0.07), true)
		var facet_col: Color = Color(pal.ink).lerp(crystal_col, 0.4)
		var core_local := Vector2(0.0, r * 0.15)
		var core_p := center + Vector2(core_local.x * mirror.x, core_local.y * mirror.y)
		draw_line(placed[0], core_p, facet_col, max(1.0, r * 0.04))
		draw_line(placed[1], core_p, facet_col, max(1.0, r * 0.04))
		draw_line(placed[5], core_p, facet_col, max(1.0, r * 0.04))

	func _paint_motif(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		match String(pal.motif):
			"quill":
				_motif_quill(pal, center, r, mirror)
			"laurel_shield":
				_motif_empire(pal, center, r, mirror)
			"horned_skull":
				_motif_skulloath(pal, center, r, mirror)
			"leaf":
				_motif_gladehost(pal, center, r, mirror)
			"crescent":
				_motif_moonspear(pal, center, r, mirror)
			"sun":
				_motif_sunblessed(pal, center, r, mirror)
			"crystal_shard":
				_motif_shardhorde(pal, center, r, mirror)
			"bolt":
				_motif_thunderswarm(pal, center, r, mirror)
			"anvil_flame":
				_motif_cinderguard(pal, center, r, mirror)
			"broken_mask":
				_motif_forsaken(pal, center, r, mirror)
			"pyramid":
				_motif_ivoryscar(pal, center, r, mirror)
			"fanged_blossom":
				_motif_tainted_jade(pal, center, r, mirror)
			_:
				_motif_quill(pal, center, r, mirror)

	## Wax-seal disc (flat base + ink rim) with the set's motif embossed
	## inside it, sized to `r` so it always fits its caller's margin cell.
	## Task 5b round 2 (ART GATE 3-color-presence request): the wax-seal
	## disc is now `secondary` (was `heraldry`-derived `seal` — reading as
	## "dark-on-dark" against the heraldry-derived motif). `accent` is
	## unconditional now (every SETS row carries one) and does TWO jobs: an
	## emboss-highlight ring just inside the ink rim, AND the motif fill —
	## achieved by handing `_paint_motif` a shallow copy of `pal` with
	## `heraldry` swapped for `accent`. Every `_motif_*` function already
	## reads `pal.heraldry` for its base fill color, so this recolors all 11
	## motifs to the tertiary accent WITHOUT touching a single motif's
	## geometry — `motif_pal.secondary` still equals the real seal disc
	## color unchanged, so e.g. moonspear's crescent cut-circle (drawn in
	## `pal.secondary` to blend into the disc) still blends correctly.
	func _paint_seal(pal: Dictionary, center: Vector2, r: float, mirror: Vector2) -> void:
		draw_circle(center, r, pal.secondary)
		draw_arc(center, r, 0.0, TAU, 24, Color(Color(pal.ink).r, Color(pal.ink).g, Color(pal.ink).b, 0.85), max(1.0, r * 0.12))
		var acc: Color = pal.accent
		draw_arc(center, r * 0.82, 0.0, TAU, 20, Color(acc.r, acc.g, acc.b, 0.55), max(1.0, r * 0.08))
		var motif_pal: Dictionary = pal.duplicate()
		motif_pal.heraldry = pal.accent
		_paint_motif(motif_pal, center, r * 0.72, mirror)

	# ── Pieces ───────────────────────────────────────────────────────────

	func _paint_frame(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(FRAME_SIZE))
		draw_rect(rect, pal.parchment)
		_paint_stains(rng, rect, 8, Color(Color(pal.parchment_dark).r, Color(pal.parchment_dark).g, Color(pal.parchment_dark).b, 0.07))
		# Task 5b round 2: outer line stays `ink` (border definition), inner
		# line becomes `secondary` (previously both were `ink` — this is the
		# "frame's inner border line" the ART GATE asked for).
		_paint_wobble_border(rng, rect, [2.0], [2.0], pal.ink)
		_paint_wobble_border(rng, rect, [5.5], [1.6], pal.secondary)
		var m := float(FRAME_MARGIN)
		var r := 12.0  # scaled with FRAME_MARGIN 24->32 (was 9.0 at margin 24, same ratio)
		var corners := [
			{c = Vector2(m * 0.5, m * 0.5), mir = Vector2(1, 1)},
			{c = Vector2(FRAME_SIZE.x - m * 0.5, m * 0.5), mir = Vector2(-1, 1)},
			{c = Vector2(m * 0.5, FRAME_SIZE.y - m * 0.5), mir = Vector2(1, -1)},
			{c = Vector2(FRAME_SIZE.x - m * 0.5, FRAME_SIZE.y - m * 0.5), mir = Vector2(-1, -1)},
		]
		for cd in corners:
			_paint_seal(pal, cd.c, r, cd.mir)
		# Task 5b round 2 (optional per the ART GATE brief, "if it reads
		# well"): a thin accent underline evoking a title-bar rule, sitting
		# inside the margin band (clear of the corner seals) so it never
		# overlaps them, spanning the frame's inner width.
		# Fix-round finding (code review): this MUST stay < FRAME_MARGIN —
		# the margin band is the nine-patch texture margin, everything at
		# y >= FRAME_MARGIN is the stretchable center region, so a line
		# placed there (was m + 3 = 35, past the 32px margin) gets thicker
		# on tall dialogs as the center stretches. m - 4 keeps it fixed at
		# 28, safely inside the unstretched band.
		var underline_y := m - 4.0
		var acc: Color = pal.accent
		draw_line(Vector2(m, underline_y), Vector2(FRAME_SIZE.x - m, underline_y), Color(acc.r, acc.g, acc.b, 0.55), 1.5)

	## Per-state fills exactly per the candidate sheet's parchment button:
	## normal parchment + ink border; hover pale fill + secondary-emphasis
	## border overlay (Task 5b round 2 — was heraldry, which made hover read
	## as a duller pressed-state instead of its own thing); pressed heraldry
	## fill; disabled desaturated fill + faded ink. Every color is derived
	## from `pal` so faction sets (Task 2) reskin automatically without
	## touching this function.
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
		# UI Polish Wave Task P1 ("button color and background color often too
		# close to each other"): border weight 1.6 -> 2.6 (+1px). The button's
		# `fill` (parchment/lightened-parchment) sits close in tone to the
		# panel parchment it's placed on — the ink outline is what actually
		# separates a button's silhouette from its backdrop, so it's the
		# cheaper/more effective lever here than darkening `pal.ink` further:
		# every set's ink is already a near-black tone (luminance well under
		# 0.2), so there's little headroom left to darken before it just reads
		# as pure black regardless of faction. A thicker line reads as a
		# stronger separator at every zoom without touching per-faction color
		# tuning.
		draw_polyline(closed, border, 2.6, true)
		if state == "hover":
			# Task 5b round 2: hover emphasis border is now `secondary`
			# (was `heraldry`, which made hover and pressed states share a
			# color family — secondary gives hover its own distinct hue).
			draw_polyline(closed, Color(Color(pal.secondary).r, Color(pal.secondary).g, Color(pal.secondary).b, 0.85), 1.0, true)

	## Frame variant: doubled outer border (two nested wobble-line pairs)
	## and a single larger seal at top-center instead of the 4 corners.
	func _paint_notification(rng: RandomNumberGenerator, pal: Dictionary) -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(NOTIF_SIZE))
		draw_rect(rect, pal.parchment)
		_paint_stains(rng, rect, 14, Color(Color(pal.parchment_dark).r, Color(pal.parchment_dark).g, Color(pal.parchment_dark).b, 0.07))
		# Task 5b round 2: only the innermost of the 4 nested lines becomes
		# `secondary` (matching _paint_frame's outermost=ink/innermost=
		# secondary rule applied to the whole nested stack) — keeps the
		# structural double-border look intact while still showing the
		# secondary hue.
		_paint_wobble_border(rng, rect, [3.0, 6.5, 12.0], [2.2, 1.8, 1.8], pal.ink)
		_paint_wobble_border(rng, rect, [15.5], [1.4], pal.secondary)
		var r := 15.0  # grown from 13.0 (ART GATE seal-readability request), stays inside NOTIF_MARGIN (32)
		var cy := float(NOTIF_MARGIN) * 0.5
		_paint_seal(pal, Vector2(NOTIF_SIZE.x * 0.5, cy), r, Vector2.ONE)

	## Task 5b round 2 — standalone wax-seal asset (`<id>_seal.png`,
	## transparent background, no nine-patch margin): Tasks 6/7 will place
	## these directly in dialog headers/faction panels. Same `_paint_seal`
	## painter as the frame corners/notification top-center, just larger and
	## with no parchment backdrop drawn first (the SubViewport is already
	## transparent_bg — see the driver below — so skipping the backdrop
	## `draw_rect` is what makes this piece transparent).
	func _paint_seal_standalone(pal: Dictionary) -> void:
		var r := 28.0
		_paint_seal(pal, Vector2(SEAL_SIZE) * 0.5, r, Vector2.ONE)

	# ── Contact sheet — lays out all 7 baked pieces plus a 400x260 sample of
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

		# Task 5b round 2 — standalone seal.png at its real 64x64 size.
		var seal_tex: Texture2D = textures["seal"]
		var seal_pos := Vector2(500, 315)
		draw_string(ThemeDB.fallback_font, seal_pos + Vector2(0, -6), "seal (64px, real size)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.76, 0.68))
		draw_texture(seal_tex, seal_pos)

	## Task 2 — one composite sheet across all 12 sets (`_contact_factions.png`):
	## a row per set with a frame thumbnail, all 4 button states, and a
	## magnified crop of the frame's top-left FRAME_MARGIN×FRAME_MARGIN corner
	## cell (the actual baked seal, not a re-render) so the ART GATE can judge
	## every motif's legibility at a glance, set against set for palette
	## differentiation. `textures` is keyed by set_id -> {piece -> Texture2D},
	## pre-built in _process() for the same GPU-upload-race reason documented
	## on _paint_contact_sheet above.
	func _paint_factions_contact_sheet(set_ids: Array, textures: Dictionary) -> void:
		var vp_size := Vector2(FACTIONS_CONTACT_VP_SIZE)
		draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.10, 0.09, 0.08))
		draw_string(ThemeDB.fallback_font, Vector2(16, 26), "UI CHROME — 12 SETS (neutral + 11 factions)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.92, 0.88, 0.78))

		var label_x := 16.0
		var frame_x := 140.0
		var frame_thumb := 80.0
		var btn_x0 := 240.0
		var btn_w := 70.0
		var btn_h := 34.0
		var btn_gap := 8.0
		var seal_x := btn_x0 + 4.0 * (btn_w + btn_gap) + 12.0
		var seal_thumb := 80.0
		# Task 5b round 2 — real 64x64 standalone seal.png, unscaled, next to
		# the existing magnified corner-crop column (the crop can flatter
		# small-scale legibility; this column is the honest check).
		var seal64_x := seal_x + seal_thumb + 16.0
		var row_h := FACTIONS_CONTACT_ROW_H
		var top := FACTIONS_CONTACT_HEADER_H
		var btn_keys := ["btn_normal", "btn_hover", "btn_pressed", "btn_disabled"]

		var col_caption_y := 44.0
		draw_string(ThemeDB.fallback_font, Vector2(frame_x, col_caption_y), "frame", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.61, 0.54))
		draw_string(ThemeDB.fallback_font, Vector2(btn_x0, col_caption_y), "normal / hover / pressed / disabled", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.61, 0.54))
		draw_string(ThemeDB.fallback_font, Vector2(seal_x, col_caption_y), "seal (corner, ~3.3x)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.61, 0.54))
		draw_string(ThemeDB.fallback_font, Vector2(seal64_x, col_caption_y), "seal (64px real)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.61, 0.54))

		for i in set_ids.size():
			var sid: StringName = set_ids[i]
			var row_y := top + float(i) * row_h
			var tset: Dictionary = textures[sid]

			draw_string(ThemeDB.fallback_font, Vector2(label_x, row_y + row_h * 0.5 + 5.0), String(sid), HORIZONTAL_ALIGNMENT_LEFT, 118, 14, Color(0.88, 0.84, 0.74))

			var frame_tex: Texture2D = tset["frame"]
			var frame_rect := Rect2(Vector2(frame_x, row_y + (row_h - frame_thumb) * 0.5), Vector2(frame_thumb, frame_thumb))
			draw_texture_rect(frame_tex, frame_rect, false)

			var bx := btn_x0
			for key in btn_keys:
				var btex: Texture2D = tset[key]
				var brect := Rect2(Vector2(bx, row_y + (row_h - btn_h) * 0.5), Vector2(btn_w, btn_h))
				draw_texture_rect(btex, brect, false)
				bx += btn_w + btn_gap

			# Seal close-up: crop the top-left corner cell straight off the
			# native-resolution frame texture and magnify it (80px from a
			# FRAME_MARGIN-px source cell, ~2.5x at the new 32px margin) —
			# proves motif legibility off the real bake instead of a
			# synthetic re-render at higher radius.
			var src := Rect2(Vector2.ZERO, Vector2(FRAME_MARGIN, FRAME_MARGIN))
			var seal_rect := Rect2(Vector2(seal_x, row_y + (row_h - seal_thumb) * 0.5), Vector2(seal_thumb, seal_thumb))
			draw_texture_rect_region(frame_tex, seal_rect, src)

			# Task 5b round 2 — the real 64x64 standalone seal.png, drawn at
			# native size (no scaling) so it shows exactly what Tasks 6/7
			# will actually place in dialog headers/faction panels.
			var seal64_tex: Texture2D = tset["seal"]
			var seal64_pos := Vector2(seal64_x, row_y + (row_h - 64.0) * 0.5)
			draw_texture(seal64_tex, seal64_pos)

			if i < set_ids.size() - 1:
				draw_line(Vector2(8, row_y + row_h), Vector2(vp_size.x - 8.0, row_y + row_h), Color(0.3, 0.28, 0.24), 1.0)

	# ── Dispatch ─────────────────────────────────────────────────────────

	func _draw() -> void:
		if factions_mode:
			if factions_textures.is_empty():
				return
			_paint_factions_contact_sheet(factions_set_ids, factions_textures)
			return
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
			"seal":
				_paint_seal_standalone(pal)
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

	# The 12-row cross-faction sheet needs every set's textures in _images,
	# so it's only meaningful (and only enqueued) on a full default run —
	# a single-set re-bake (`-- <set_id>`) skips it.
	if set_arg == "":
		_jobs.append(["factions_contact", &"", ""])

	if _jobs.is_empty():
		print("No jobs to run — no valid set id(s) in %s" % [set_ids])
		quit()

func _process(_delta: float) -> bool:
	if _vp == null:
		return false
	if _capture_pending:
		var img := _vp.get_texture().get_image()
		var job: Array = _jobs[_job_idx]
		match job[0]:
			"bake":
				var sid: StringName = job[1]
				var piece: String = job[2]
				var fname := "%s_%s.png" % [String(sid), piece]
				img.save_png("%s/%s" % [OUT_DIR, fname])
				_images["%s_%s" % [String(sid), piece]] = img
				print("Saved %s" % fname)
			"contact":
				var sid2: StringName = job[1]
				var fname2 := "_contact_%s.png" % String(sid2)
				img.save_png("%s/%s" % [OUT_DIR, fname2])
				img.save_png("%s/%s" % [SCRATCH_DIR, fname2])
				print("Saved contact sheet: %s" % fname2)
			_:  # "factions_contact"
				var fname3 := "_contact_factions.png"
				img.save_png("%s/%s" % [OUT_DIR, fname3])
				img.save_png("%s/%s" % [SCRATCH_DIR, fname3])
				print("Saved factions contact sheet: %s" % fname3)
		_capture_pending = false
	if _job_idx + 1 < _jobs.size():
		_job_idx += 1
		var job: Array = _jobs[_job_idx]
		match job[0]:
			"bake":
				var sid: StringName = job[1]
				var piece: String = job[2]
				var sz: Vector2i
				match piece:
					"frame":
						sz = FRAME_SIZE
					"notification":
						sz = NOTIF_SIZE
					"seal":
						sz = SEAL_SIZE
					_:
						sz = BTN_SIZE
				_vp.size = sz
				_painter.contact_mode = false
				_painter.factions_mode = false
				_painter.set_id = sid
				_painter.piece = piece
			"contact":
				var sid2: StringName = job[1]
				_vp.size = CONTACT_VP_SIZE
				_painter.contact_mode = true
				_painter.factions_mode = false
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
					"seal": ImageTexture.create_from_image(_images["%s_seal" % String(sid2)]),
				}
			_:  # "factions_contact" — 12-row cross-set sheet, all sets already baked
				_vp.size = FACTIONS_CONTACT_VP_SIZE
				_painter.contact_mode = false
				_painter.factions_mode = true
				_painter.factions_set_ids = SETS.keys()
				var ftextures := {}
				for sid3 in SETS.keys():
					ftextures[sid3] = {
						"frame": ImageTexture.create_from_image(_images["%s_frame" % String(sid3)]),
						"btn_normal": ImageTexture.create_from_image(_images["%s_btn_normal" % String(sid3)]),
						"btn_hover": ImageTexture.create_from_image(_images["%s_btn_hover" % String(sid3)]),
						"btn_pressed": ImageTexture.create_from_image(_images["%s_btn_pressed" % String(sid3)]),
						"btn_disabled": ImageTexture.create_from_image(_images["%s_btn_disabled" % String(sid3)]),
						"seal": ImageTexture.create_from_image(_images["%s_seal" % String(sid3)]),
					}
				_painter.factions_textures = ftextures
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_capture_pending = true
	else:
		print("GENERATED %d UI chrome jobs into %s" % [_jobs.size(), OUT_DIR])
		quit()
	return false
