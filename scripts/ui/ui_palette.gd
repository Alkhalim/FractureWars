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
## same parchment/parchment_dark/ink/heraldry/seal values (motif omitted —
## tool-only, irrelevant to runtime color).

# ── Style-guide constants — faction-independent, never touched by rebuild ──
const _CHIP_BG := Color(0.05, 0.04, 0.03, 0.72)
const _DANGER := Color(0.60, 0.17, 0.13)
const _SUCCESS := Color(0.28, 0.44, 0.20)
const _WARN := Color(0.58, 0.40, 0.11)

## Per-set palette table — duplicated from tests/tools_generate_ui_chrome.gd's
## SETS (keep in sync with that file). Only the color fields the runtime
## needs; the tool additionally carries `motif` for pixel-baking, omitted
## here.
const _PALETTE := {
	&"neutral": {
		parchment = Color(0.85, 0.79, 0.66), parchment_dark = Color(0.24, 0.21, 0.17),
		ink = Color(0.16, 0.13, 0.10), heraldry = Color(0.62, 0.52, 0.30), seal = Color(0.40, 0.32, 0.16),
	},
	&"empire": {
		parchment = Color(0.86, 0.82, 0.73), parchment_dark = Color(0.26, 0.24, 0.19),
		ink = Color(0.15, 0.13, 0.10), heraldry = Color(0.29, 0.36, 0.50), seal = Color(0.17, 0.22, 0.33),
	},
	&"skulloath": {
		parchment = Color(0.72, 0.64, 0.62), parchment_dark = Color(0.22, 0.17, 0.16),
		ink = Color(0.13, 0.08, 0.08), heraldry = Color(0.42, 0.19, 0.20), seal = Color(0.27, 0.11, 0.12),
	},
	&"gladehost": {
		parchment = Color(0.76, 0.83, 0.70), parchment_dark = Color(0.22, 0.25, 0.18),
		ink = Color(0.12, 0.14, 0.10), heraldry = Color(0.33, 0.44, 0.26), seal = Color(0.20, 0.29, 0.15),
	},
	&"moonspear": {
		parchment = Color(0.74, 0.76, 0.82), parchment_dark = Color(0.20, 0.21, 0.25),
		ink = Color(0.11, 0.12, 0.15), heraldry = Color(0.36, 0.39, 0.55), seal = Color(0.21, 0.23, 0.36),
	},
	&"sunblessed": {
		parchment = Color(0.87, 0.81, 0.66), parchment_dark = Color(0.26, 0.24, 0.17),
		ink = Color(0.16, 0.13, 0.10), heraldry = Color(0.62, 0.52, 0.25), seal = Color(0.40, 0.33, 0.14),
	},
	&"shardhorde": {
		parchment = Color(0.83, 0.77, 0.85), parchment_dark = Color(0.25, 0.21, 0.26),
		ink = Color(0.15, 0.10, 0.15), heraldry = Color(0.55, 0.28, 0.49), seal = Color(0.36, 0.16, 0.31),
	},
	&"thunderswarm": {
		parchment = Color(0.73, 0.75, 0.78), parchment_dark = Color(0.19, 0.21, 0.23),
		ink = Color(0.11, 0.12, 0.14), heraldry = Color(0.50, 0.44, 0.22), seal = Color(0.33, 0.28, 0.13),
	},
	&"cinderguard": {
		parchment = Color(0.85, 0.74, 0.68), parchment_dark = Color(0.26, 0.21, 0.18),
		ink = Color(0.15, 0.11, 0.09), heraldry = Color(0.52, 0.32, 0.21), seal = Color(0.34, 0.20, 0.11),
	},
	&"forsaken": {
		parchment = Color(0.76, 0.74, 0.79), parchment_dark = Color(0.22, 0.20, 0.24),
		ink = Color(0.12, 0.10, 0.13), heraldry = Color(0.36, 0.26, 0.40), seal = Color(0.23, 0.15, 0.26),
	},
	&"ivoryscar": {
		parchment = Color(0.88, 0.86, 0.81), parchment_dark = Color(0.26, 0.25, 0.22),
		ink = Color(0.16, 0.14, 0.12), heraldry = Color(0.52, 0.47, 0.34), seal = Color(0.34, 0.30, 0.20),
	},
	&"tainted_jade": {
		parchment = Color(0.72, 0.80, 0.71), parchment_dark = Color(0.19, 0.24, 0.19),
		ink = Color(0.10, 0.12, 0.09), heraldry = Color(0.29, 0.22, 0.36), seal = Color(0.18, 0.13, 0.23),
	},
}

# ── Semantic constants (set once, faction-independent) ──
static var CHIP_BG: Color = _CHIP_BG
static var DANGER: Color = _DANGER
static var SUCCESS: Color = _SUCCESS
static var WARN: Color = _WARN

# ── Faction-dependent constants — initialized to the neutral palette,
# overwritten by rebuild(). ──
static var INK_TITLE: Color = Color(0.16, 0.13, 0.10)
static var INK_BODY: Color = Color(0.16, 0.13, 0.10)
static var PARCHMENT: Color = Color(0.85, 0.79, 0.66)
static var PARCHMENT_DARK: Color = Color(0.24, 0.21, 0.17)
static var PARCHMENT_ACCENT: Color = Color(0.62, 0.52, 0.30)
static var CHIP_BORDER: Color = Color(0.62, 0.52, 0.30)
static var SEAL: Color = Color(0.40, 0.32, 0.16)
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
	SEAL = pal.seal
	BAR_FILL = Color(pal.heraldry).darkened(0.1)
	BAR_TROUGH = pal.parchment_dark
	CHIP_BG = _CHIP_BG
	DANGER = _DANGER
	SUCCESS = _SUCCESS
	WARN = _WARN

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
