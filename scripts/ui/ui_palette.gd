class_name UIPalette
extends RefCounted
## Single source of truth for every runtime UI color in the Parchment & Ink
## system (UI Overhaul #40). UI code reads UIPalette.* instead of inlining
## Color(...) literals — see docs/ui_style_guide.md. `rebuild(set_id)` is
## called by GameManager whenever the active chrome set changes (boot ->
## neutral; later, apply_faction_theme -> the player's faction set), so
## every constant below already carries the active faction's ink/heraldry
## tuning. `heraldry(faction_id)` serves cross-faction contexts (diplomacy
## rows, anything naming ANOTHER faction) without needing a rebuild.
##
## Keep in sync with tests/tools_generate_ui_chrome.gd's SETS table (same
## Task 3 of the UI-overhaul plan): that table is tool-side and bakes
## pixels; this one drives runtime (non-chrome) UI colors. Same 12 rows,
## same parchment/parchment_dark/ink/heraldry/secondary/accent values (motif
## omitted — tool-only, irrelevant to runtime color).

# ── Style-guide constants — faction-independent, never touched by rebuild ──
const _CHIP_BG := Color(0.05, 0.04, 0.03, 0.72)
const _DANGER := Color(0.60, 0.17, 0.13)
const _SUCCESS := Color(0.28, 0.44, 0.20)
const _WARN := Color(0.58, 0.40, 0.11)
## Task 8 coherence pass: DANGER/SUCCESS/WARN are dark ink tones — correct
## (dark-on-light) for the majority of sites, which sit directly on light
## parchment panels, but read dull/low-contrast at the sites that sit on a
## near-black CHIP_BG chip (e.g. diplomacy standing tags), where the old
## pre-overhaul code used bright literals. These _BRIGHT variants are for
## that dark-background case specifically — apply at a call site only when
## the label's container is a CHIP_BG-backed chip/dialog backdrop, never as
## a blanket replacement (most SUCCESS/DANGER/WARN call sites are correct as
## written). Hand-picked to echo campaign_hud.gd's existing RELATION_COLORS
## bright red/green literals (same rows, proven readable on the same dark
## chips) rather than derived via .lightened() (which desaturates toward
## white and reads washed-out/pink instead of a clean bright hue).
const _DANGER_BRIGHT := Color(0.85, 0.25, 0.20)
const _SUCCESS_BRIGHT := Color(0.35, 0.78, 0.42)
const _WARN_BRIGHT := Color(0.88, 0.62, 0.18)

## Per-set palette table — duplicated from tests/tools_generate_ui_chrome.gd's
## SETS (keep in sync with that file). Same fields the tool table carries
## except `motif` (tool-only, irrelevant to runtime color).
##
## Task 5b round 1 (docs/faction_color_alignment.md) replaced 10 of these 11
## rows with values derived from the designer-approved SoB colour chart's
## per-faction Primary/Secondary/Tertiary colors. Task 5b round 2 (ART GATE
## feedback: palettes read monochrome) retired the old `seal` field — the
## wax-seal-disc role is now `secondary` — and made `accent` a required
## field on every row instead of an optional 2-faction extra. See
## tools_generate_ui_chrome.gd's SETS-level and per-row comments for the
## exact per-faction mapping reasoning (which chart color feeds which field,
## and which factions needed an invented secondary/accent because the
## chart's 3 colors were already claimed by ink/parchment/heraldry).
const _PALETTE := {
	&"neutral": {
		parchment = Color(0.85, 0.79, 0.66), parchment_dark = Color(0.24, 0.21, 0.17),
		ink = Color(0.16, 0.13, 0.10), heraldry = Color(0.62, 0.52, 0.30),
		secondary = Color(0.26, 0.29, 0.32), accent = Color(0.85, 0.77, 0.47),
	},
	&"empire": {
		parchment = Color(0.86, 0.82, 0.73), parchment_dark = Color(0.26, 0.24, 0.19),
		ink = Color(0.15, 0.13, 0.10), heraldry = Color(0.29, 0.36, 0.50),
		secondary = Color(0.45, 0.38, 0.20), accent = Color(0.88, 0.83, 0.69),
	},
	&"skulloath": {
		parchment = Color(0.78, 0.73, 0.68), parchment_dark = Color(0.23, 0.21, 0.18),
		ink = Color(0.06, 0.04, 0.04), heraldry = Color(0.50, 0.21, 0.21),
		secondary = Color(0.32, 0.24, 0.18), accent = Color(0.80, 0.70, 0.36),
	},
	&"gladehost": {
		parchment = Color(0.85, 0.81, 0.75), parchment_dark = Color(0.26, 0.23, 0.20),
		ink = Color(0.10, 0.13, 0.13), heraldry = Color(0.19, 0.42, 0.42),
		secondary = Color(0.30, 0.26, 0.20), accent = Color(0.92, 0.43, 0.37),
	},
	&"moonspear": {
		parchment = Color(0.75, 0.76, 0.81), parchment_dark = Color(0.20, 0.21, 0.24),
		ink = Color(0.11, 0.12, 0.15), heraldry = Color(0.26, 0.29, 0.58),
		secondary = Color(0.39, 0.40, 0.42), accent = Color(0.77, 0.77, 0.80),
	},
	&"sunblessed": {
		parchment = Color(0.87, 0.81, 0.66), parchment_dark = Color(0.26, 0.24, 0.17),
		ink = Color(0.16, 0.13, 0.10), heraldry = Color(0.46, 0.42, 0.18),
		secondary = Color(0.19, 0.42, 0.19), accent = Color(0.78, 0.80, 0.78),
	},
	&"shardhorde": {
		parchment = Color(0.82, 0.76, 0.71), parchment_dark = Color(0.25, 0.22, 0.19),
		ink = Color(0.13, 0.11, 0.08), heraldry = Color(0.50, 0.35, 0.20),
		secondary = Color(0.25, 0.30, 0.12), accent = Color(0.73, 0.57, 0.88),
	},
	&"thunderswarm": {
		parchment = Color(0.82, 0.82, 0.70), parchment_dark = Color(0.25, 0.24, 0.18),
		ink = Color(0.13, 0.10, 0.08), heraldry = Color(0.52, 0.34, 0.21),
		secondary = Color(0.30, 0.19, 0.13), accent = Color(0.90, 0.87, 0.59),
	},
	&"cinderguard": {
		parchment = Color(0.85, 0.77, 0.72), parchment_dark = Color(0.26, 0.21, 0.19),
		ink = Color(0.07, 0.06, 0.06), heraldry = Color(0.52, 0.21, 0.25),
		secondary = Color(0.28, 0.35, 0.40), accent = Color(0.85, 0.69, 0.38),
	},
	&"forsaken": {
		parchment = Color(0.72, 0.72, 0.79), parchment_dark = Color(0.20, 0.19, 0.24),
		ink = Color(0.07, 0.06, 0.07), heraldry = Color(0.42, 0.19, 0.36),
		secondary = Color(0.31, 0.36, 0.40), accent = Color(0.90, 0.78, 0.14),
	},
	&"ivoryscar": {
		parchment = Color(0.83, 0.80, 0.76), parchment_dark = Color(0.25, 0.23, 0.20),
		ink = Color(0.13, 0.11, 0.09), heraldry = Color(0.42, 0.39, 0.26),
		secondary = Color(0.35, 0.23, 0.17), accent = Color(0.82, 0.71, 0.33),
	},
	&"tainted_jade": {
		parchment = Color(0.73, 0.79, 0.70), parchment_dark = Color(0.20, 0.24, 0.18),
		ink = Color(0.10, 0.12, 0.09), heraldry = Color(0.28, 0.46, 0.19),
		secondary = Color(0.22, 0.11, 0.24), accent = Color(0.85, 0.83, 0.38),
	},
}

# ── Semantic constants (set once, faction-independent) ──
static var CHIP_BG: Color = _CHIP_BG
static var DANGER: Color = _DANGER
static var SUCCESS: Color = _SUCCESS
static var WARN: Color = _WARN
static var DANGER_BRIGHT: Color = _DANGER_BRIGHT
static var SUCCESS_BRIGHT: Color = _SUCCESS_BRIGHT
static var WARN_BRIGHT: Color = _WARN_BRIGHT

# ── Faction-dependent constants — initialized to the neutral palette,
# overwritten by rebuild(). ──
static var INK_TITLE: Color = Color(0.16, 0.13, 0.10)
static var INK_BODY: Color = Color(0.16, 0.13, 0.10)
static var PARCHMENT: Color = Color(0.85, 0.79, 0.66)
static var PARCHMENT_DARK: Color = Color(0.24, 0.21, 0.17)
static var PARCHMENT_ACCENT: Color = Color(0.62, 0.52, 0.30)
static var CHIP_BORDER: Color = Color(0.62, 0.52, 0.30)
## Task 5b round 2: the old `SEAL` var (wax-seal disc color) is renamed
## SECONDARY to match the palette record's field rename — nothing outside
## this file read `UIPalette.SEAL` (verified before renaming), so this is a
## clean rename, not an added alias. ACCENT is new (chart Tertiary role —
## seal emboss/motif color at bake time; Tasks 6/7 can now also pull it for
## runtime UI, e.g. a highlight chip or notification accent).
static var SECONDARY: Color = Color(0.40, 0.32, 0.16)
static var ACCENT: Color = Color(0.85, 0.77, 0.47)
static var BAR_FILL: Color = Color(0.62, 0.52, 0.30).darkened(0.1)
static var BAR_TROUGH: Color = Color(0.24, 0.21, 0.17)

## Rebuilds every faction-dependent constant above from the palette table
## row for `set_id` (falls back to neutral if unknown). Faction-independent
## constants (CHIP_BG, DANGER, SUCCESS, WARN) are reasserted too — harmless,
## keeps this the single place that ever writes them.
static func rebuild(set_id: StringName) -> void:
	var pal: Dictionary = _PALETTE.get(set_id, _PALETTE[&"neutral"])
	INK_TITLE = pal.ink
	INK_BODY = pal.ink
	PARCHMENT = pal.parchment
	PARCHMENT_DARK = pal.parchment_dark
	PARCHMENT_ACCENT = pal.heraldry
	CHIP_BORDER = pal.heraldry
	SECONDARY = pal.secondary
	ACCENT = pal.accent
	BAR_FILL = Color(pal.heraldry).darkened(0.1)
	BAR_TROUGH = pal.parchment_dark
	CHIP_BG = _CHIP_BG
	DANGER = _DANGER
	SUCCESS = _SUCCESS
	WARN = _WARN
	DANGER_BRIGHT = _DANGER_BRIGHT
	SUCCESS_BRIGHT = _SUCCESS_BRIGHT
	WARN_BRIGHT = _WARN_BRIGHT

## Cross-faction heraldry lookup — does NOT depend on / mutate the current
## rebuild() state, so callers can ask "what's Skulloath's color" while the
## player's own theme (e.g. Empire) stays active. Minors resolve to their
## parent major faction first; unknown ids fall back to FactionData.color,
## then to the neutral heraldry tone.
static func heraldry(faction_id: StringName) -> Color:
	var fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	if _PALETTE.has(fid):
		return _PALETTE[fid].heraldry
	var fd: FactionData = DataManager.factions.get(fid) if DataManager.factions.has(fid) else null
	if fd:
		return fd.color
	return _PALETTE[&"neutral"].heraldry
