# FractureWars UI Style Guide

Baseline rules for ALL menus, panels, and HUD surfaces. These are binding —
new UI must follow them without being asked, and deviations are bugs.
The shared implementations live in `game_manager.gd` (theme + style factories)
and `campaign_hud.gd` (`_make_text_chip`). Never hand-roll a one-off style
when a shared factory exists.

## Themes — which skin where

| Context | Theme | Why |
|---|---|---|
| Main menu, dialogs, large screens | Global root theme (full-size gold skin) | Buttons ≥ 48 px tall render the 24 px nine-patch borders correctly |
| Campaign HUD (whole `UILayer/HUD`), battle HUD, minimap block, any dense panel | `GameManager.get_compact_theme()` | 6 px borders work at 22–40 px control heights |

**Rule: the full-size button skin needs ≥ 48 px control height. Anything
smaller MUST live under the compact theme** — a full-size button below 48 px
collapses into an unreadable flat sliver (this caused the "buttons don't look
like buttons" reports).

## Panels

- Major panels use `GameManager.make_panel_style()` (ornate leather + gold
  frame); dense HUD panels inherit the compact theme's panel.
- **Edge-anchored panels sit FLUSH against screen edges/corners** — offsets of
  0 on the anchored sides. Small 8–16 px gaps read as unfinished. The frame's
  outer glow overhanging off-screen is fine.
- Panel content honors the frame's content margins — never add negative
  margins or place children outside the frame.

## Text readability

- **Never place body text directly on the leather texture.** Wrap content in a
  dark chip: `_make_text_chip()` (campaign_hud) — dark translucent rounded
  panel, content margins built in. Scrollable content areas inside ornate
  panels get one chip wrapping the whole content VBox.
- Labels over the game world (map/battle) always use outlines
  (`draw_string_outline` or theme outline constants).
- Font sizes: titles 16, section headers 14, body 13, dense/secondary 11–12,
  never below 10.

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
  themed `HSeparator` (gold `separator_color`).
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
