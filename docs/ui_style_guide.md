# FractureWars UI Style Guide

Baseline rules for ALL menus, panels, and HUD surfaces. These are binding —
new UI must follow them without being asked, and deviations are bugs.
The shared implementations live in `game_manager.gd` (theme + style factories)
and `campaign_hud.gd` (`_make_text_chip`). Never hand-roll a one-off style
when a shared factory exists.

As of the UI Overhaul (#40, "Parchment & Ink", implemented 2026-08-04) every
chrome texture, palette color, and font is generated/sourced, not hand-picked
per call site — see the two new sections below before adding any UI.

## Generated chrome pipeline

All button/frame/notification textures are procedurally baked, per faction,
by `tests/tools_generate_ui_chrome.gd` (ported from the style-direction
mockup `tests/tools_ui_style_candidates.gd`) — replacing the old stock
`button1.png`/`frame1.png`/`notification1.png` (retired, deleted). 12 sets
(11 majors + `neutral`) live in `assets/sprites/ui/generated/` as
`<set_id>_{frame,btn_normal,btn_hover,btn_pressed,btn_disabled,notification,
seal}.png`, plus a per-set contact sheet.

**Regenerate** (windowed — SubViewport capture needs a live window; a brief
flash is expected):
```
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --resolution 1200x800 --path . -s res://tests/tools_generate_ui_chrome.gd
& "G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe" --headless --path . --import
```
Optional trailing `-- <set_id>` rebakes one set only. Nine-patch geometry is
declared once in the tool (`FRAME_SIZE`/`FRAME_MARGIN`/`BTN_SIZE`/
`BTN_MARGIN`/`NOTIF_SIZE`/`NOTIF_MARGIN`) and copied verbatim into
`game_manager.gd`'s `_FRAME_SIZE`/`_FRAME_MARGIN`/etc. — the two files must
stay in sync (each carries a comment cross-referencing the other). Palette
rows (parchment/ink/heraldry/secondary/accent per faction) are similarly
duplicated between the tool's `SETS` table and `scripts/ui/ui_palette.gd`'s
`_PALETTE` table — same rule.

`GameManager._build_theme_for_set(set_id)` consumes the baked PNGs into
`StyleBoxTexture`s for the root theme; `GameManager.get_compact_theme()`
re-derives a 25%-scaled copy for dense HUD panels (battle HUD, campaign HUD).
Missing PNGs fall back to the `neutral` set, then to a flat `StyleBoxFlat` —
a checkout with no generated assets still runs.

**Godot theme-cascade gotcha (read before adding a new themed control type):**
once a Control's own `.theme` is set (this is true of the HUD root — see
`campaign_hud.gd`'s `theme = GameManager.get_compact_theme()` — and of every
Window/root Control with an assigned theme), Godot resolves **every** theme
property for that Control's whole subtree from that one Theme resource alone
(with the normal *within-theme* fallback: type variation → class hierarchy,
e.g. CheckBox → Button). It does **not** climb further up the scene tree to
a different ancestor's Theme for a type or property the nearer theme leaves
unset — even a type it doesn't mention at all. Anything missing falls
straight to Godot's built-in engine default (flat grey ProgressBar/slider,
~0.875-grey text), not to the root theme. Concretely: **any control type
themed in `_build_theme_for_set` (root theme) must be mirrored into
`get_compact_theme()` too**, or compact-themed instances of that type
silently lose their styling. This was found and fixed for real during the
Task 8 coherence pass — a Victory-panel `ProgressBar` was rendering as
Godot's stock flat grey bar despite a (wrong) code comment claiming it
"cascades to root". `get_compact_theme()`'s doc comment in `game_manager.gd`
has the full mechanism and the up-to-date list of mirrored types.

## UIPalette — color sourcing

**Every runtime UI color goes through `UIPalette` (`scripts/ui/ui_palette.gd`).
An inline `Color(0.x, 0.y, 0.z, ...)` literal in UI code is a review defect**
— it can't react to `apply_faction_theme()`, and it's exactly how the old
pre-overhaul chrome accumulated ~1,357 stray literals that this overhaul
spent seven tasks migrating. If a new call site needs a color, it's one of:

| Need | Constant |
|---|---|
| Title text on a light parchment panel | `UIPalette.INK_TITLE` |
| Body/secondary text on a light parchment panel | `UIPalette.INK_BODY` (dim/de-emphasized: `Color(UIPalette.INK_BODY, 0.7-0.75)`, not a separate literal) |
| Title/body text on a dark chip (`_make_text_chip`, `_create_centered_dialog`) | `UIPalette.PARCHMENT` |
| A chip/dialog backdrop fill | `UIPalette.CHIP_BG` (+ `UIPalette.CHIP_BORDER` for the hairline) |
| Bar/slider fill vs. trough | `UIPalette.BAR_FILL` / `UIPalette.BAR_TROUGH` |
| Semantic delta on a **light** background (dark-on-light reads correctly) | `UIPalette.SUCCESS` / `UIPalette.DANGER` / `UIPalette.WARN` |
| The same semantic on a **dark chip** (needs a light tone, not dark ink) | `UIPalette.SUCCESS_BRIGHT` / `UIPalette.DANGER_BRIGHT` / `UIPalette.WARN_BRIGHT` |
| Naming/accenting ANOTHER faction (diplomacy rows, cross-faction plaques) | `UIPalette.heraldry(faction_id)` — does not depend on / mutate the active theme |
| Naming/accenting the ACTIVE faction | `UIPalette.PARCHMENT_ACCENT` / `UIPalette.SECONDARY` / `UIPalette.ACCENT` |

`SUCCESS`/`DANGER`/`WARN` are deliberately dark ink tones (correct contrast
on the majority-case light parchment panel); the `_BRIGHT` variants exist
specifically for the dark-chip case (e.g. diplomacy standing tags) — judge
the background at the call site, don't default to one or the other.
`UIPalette.rebuild(set_id)` is called by `GameManager` on boot (`neutral`)
and by `apply_faction_theme()`, so every faction-dependent constant above
already carries the active faction's tuning — read it fresh at build time,
don't cache a `UIPalette.X` value across a faction switch.

**Scene-file (`.tscn`) `theme_override_colors` are the same rule and the
same trap** — they're invisible to a `grep "Color(0\."` sweep of `.gd`
files, which is exactly how `campaign.tscn`'s `RegionPanel` and
`SelectedArmyPanel` labels carried pre-overhaul literals (baked for the old
dark HUD panel skin) all the way through Tasks 1-7 undetected, reading as
washed-out near-invisible text once those panels' background flipped to the
new light parchment chrome. Fixed in Task 8 by removing the static
`theme_override_colors` from the `.tscn` and setting the equivalent
`UIPalette` color via `add_theme_color_override()` at the same point in
`campaign_hud.gd` where the label's `.text` is already set — new `.tscn`
labels should follow the same pattern (leave color to code) rather than
baking a static override.

## Fonts

Bundled OFL pair (`assets/fonts/`, licenses alongside): **Vollkorn**
(`Vollkorn-wght.ttf`) is the body/default face, set as `Theme.default_font`
in both theme builders; **Cinzel** (`Cinzel-wght.ttf`) is the display face,
wired only via the `HeaderLarge` (20px)/`HeaderMedium` (17px) Label
`theme_type_variation`s — never set a font directly on a Label. Apply
`theme_type_variation = &"HeaderLarge"` to real titles (dialog/panel/screen
titles — Task 6/7 precedent) and `HeaderMedium` to secondary headers; body
copy needs no variation, it already gets Vollkorn from the theme default.
Font size ladder (UI Polish Wave Task P1 — raised across the board, "small
text and a large box looks bad"): titles 20, section headers 17, body 15,
dense/secondary 12-13, floor 12 (never below). Missing font files fail closed to
Godot's stock font (`_load_ui_font` null-guards every caller) — the game
still runs, just unstyled, so this is safe to leave unset in a stripped
checkout.

## Faction theming

`GameManager.apply_faction_theme(faction_id)` is the single entry point that
switches the whole game's skin: resolves minor factions to their parent via
`MINOR_FACTION_PARENTS`, calls `UIPalette.rebuild(set_id)`, rebuilds
`get_tree().root.theme` from that faction's baked chrome set, and
invalidates the cached compact theme so it lazily rebuilds on next use.
Called from `new_game()` and `load_game()` once the player faction is known
— never rebuild the theme any other way. `GameManager.chrome_set_id` tracks
the currently-applied set (`&"neutral"` at boot, before any faction is
chosen). The per-faction parchment/ink/heraldry/secondary/accent palette
values were hand-tuned against the SoB (Shards of Beyond) design doc's
faction colour chart — see `docs/faction_color_alignment.md` for the
per-faction chart-color → palette-field mapping and rationale (which chart
color feeds heraldry vs. secondary vs. accent, and which factions needed an
invented value because the chart's 3 colors were already claimed).

## Themes — which skin where

| Context | Theme | Why |
|---|---|---|
| Main menu, dialogs, large screens | Global root theme (generated parchment & ink skin, per active faction) | Buttons ≥ 48 px tall render the 32 px nine-patch borders correctly |
| Campaign HUD (whole `UILayer/HUD`), battle HUD, minimap block, any dense panel | `GameManager.get_compact_theme()` | ~8 px borders (32px margin ÷ 4x scale) work at 22–40 px control heights |

**Rule: the full-size button skin needs ≥ 48 px control height. Anything
smaller MUST live under the compact theme** — a full-size button below 48 px
collapses into an unreadable flat sliver (this caused the "buttons don't look
like buttons" reports).

## Panels

- Major panels use `GameManager.make_panel_style()` (generated parchment
  field + inked wobble border, faction seal in the corners); dense HUD
  panels inherit the compact theme's panel.
- **Edge-anchored panels sit FLUSH against screen edges/corners** — offsets of
  0 on the anchored sides. Small 8–16 px gaps read as unfinished. The frame's
  outer glow overhanging off-screen is fine.
- Panel content honors the frame's content margins — never add negative
  margins or place children outside the frame.

## Text readability

- **Never place body text directly on the parchment texture in `PARCHMENT`
  gold/light tones — and never place ink-dark text on a dark chip.** Match
  the constant to the background per the UIPalette table above. Wrap
  dark-chip content in `_make_text_chip()` (campaign_hud) — `UIPalette.
  CHIP_BG`/`CHIP_BORDER`, translucent rounded panel, content margins built
  in. Scrollable content areas inside ornate panels get one chip wrapping
  the whole content VBox. A panel with NO chip wrapper (most of
  `GameManager.make_panel_style()`'s direct children) is light parchment —
  use `INK_TITLE`/`INK_BODY`, not `PARCHMENT`.
- Labels over the game world (map/battle) always use outlines
  (`draw_string_outline` or theme outline constants) — they cross both light
  and dark map terrain, so a fixed ink or parchment color alone isn't enough.
- Font sizes: titles 20, section headers 17, body 15, dense/secondary 12–13,
  never below 12 — see Fonts above for which face carries which size.

## Buttons & interactions

- Anything clickable is a `Button` styled by the active theme. No Labels with
  `gui_input`, no flat `StyleBoxFlat` overrides for standard actions.
- Semantic variants are allowed as *color* overrides only (e.g. danger actions
  keep the themed stylebox but use red font color — see Disband/Retreat).
- Standard heights: primary actions 40 px (compact theme) / 50 px (full-size),
  row actions 24–28 px, icon buttons 24×24 min.
- Destructive actions get a confirm dialog.

## Layout

- Standard spacing scale: 4 / 8 / 16 px separations; sections separated by
  themed `HSeparator`/`VSeparator` (thin inked line, `UIPalette.INK_BODY` —
  set via the theme's `separator` StyleBox in both `_build_theme_for_set`
  and `get_compact_theme`; `separator_color` is not a real Godot 4 Separator
  property, don't set it expecting an effect).
- Fixed-size containers must fit their content at the largest font — when in
  doubt use size flags and minimum sizes, not hard offsets.
- Columns of option rows are fixed-width (~430 px) and centered, never
  expand-fill across wide panels.

## Resource display

- Resource amounts are shown as **icon + number**, never "200 Gold" text.
  Factories: `GameManager.make_resource_icon(type, px)`,
  `GameManager.make_cost_row(cost, compare, font_size, prefix, signed)` for
  Control layouts, `GameManager.cost_bbcode(cost, compare)` for
  RichTextLabels. Affordability coloring (green/red) comes from passing the
  player's resources as `compare`; incomes use `signed = true`.
- Icons are generated assets (`tests/tools_generate_resource_icons.gd` →
  `assets/sprites/ui/icons/res_*.png`): gold coin stack, iron ingots, tech
  scroll, wheat sheaf, shard crystal, log pair, captive shackle.
- Exception: plain Button labels may spell the resource name (buttons cannot
  embed icons).

## Map & markers

- Marker visual language: dark silhouette outline, bronze/gold trim
  (`_MARKER_*` constants in campaign.gd), faction color on cloth/roofs, soft
  ground shadow, relation ring = front arc only.
- City markers are the visual anchor of a settlement: largest, crowned when
  capital, and the ONLY building with a relation ring. Tile buildings are
  smaller, category-colored roofs, faction pennant.

## Terrain

- Tile art comes from `tests/tools_generate_terrain_tiles.gd` (regenerate +
  `--headless --import`). Motifs are drawn TOP-DOWN (no side-view blades or
  trees; mountains keep the traditional map-icon profile).
- Terrain transitions use the bleed-band system in `_render_hex_map` — smooth
  world-noise curves, never per-edge pinched wedges.
