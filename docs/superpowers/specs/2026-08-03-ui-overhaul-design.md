# UI Overhaul #40 — Generated Parchment & Ink Chrome with Faction Theming

Status: IMPLEMENTED 2026-08-04 (Tasks 1-8 of `docs/superpowers/plans/2026-08-03-ui-overhaul-parchment.md` complete; style direction D picked from `assets/ui_style_candidates/`; all sections user-approved in brainstorming; final coherence sweep + full battery green — see task-8-report.md).

## As-built deviations from this spec

Decisions made or corrected during implementation that this document didn't
originally call, in rollout order:

- **Candidate-tool port, not a from-scratch generator**: §1's tool
  (`tests/tools_generate_ui_chrome.gd`) ports its painters directly from the
  already-committed style-direction mockup `tests/tools_ui_style_candidates.gd`
  (Task 1), rather than being written independently against the spec text.
  Kept as the visual source of truth per the plan's own instruction.
- **Faction palette table replaced mid-plan by a user-supplied colour chart**
  (interposed as Task 5b, between Tasks 5 and 6): the original §2 palette
  table (heraldry seeded from `FactionData.color`, hand-tuned tone shifts)
  was superseded by a designer-approved "SoB Faction Colour Chart" — see
  `docs/faction_color_alignment.md`. This changed the palette record from
  2 chart-independent fields (`heraldry`, `seal`) to a **3-color round**
  matching the chart's Primary/Secondary/Tertiary per faction
  (`heraldry`/`secondary`/`accent`), retiring the original `seal` field
  (the wax-seal-disc role moved to `secondary`). §2/§5's `UIPalette` field
  list should be read as `heraldry, secondary, accent` in place of the
  original `heraldry_color, seal_color`.
- **`FRAME_MARGIN` grew from the spec's implied ~24px to 32px** (Task 5b
  round 2 ART GATE feedback: seals read too small at 24px) — moved together
  in both `tests/tools_generate_ui_chrome.gd` and `game_manager.gd`, per
  §1's own "declared once... shared by tool and runtime" contract.
- **Standalone `<id>_seal.png` (64px) pieces added**, beyond §1's original
  6-piece-per-set list — a dialog-header-scale emblem separate from the
  frame's baked-in corner seals, added at the Task 5b gate for later reuse
  (faction intro dialog, faction overview panel — Task 6).
- **§5's "roughly 150-250 of the 583" literal-migration estimate for
  `campaign_hud.gd`** landed at 206 (Task 6) — within-band but the low end;
  the remainder is the documented "body/dim text, map-marker, faction-data,
  categorical-color" carve-out, not a shortfall.
- **Folded fixes found via the "screenshot first, judge, fix" loop each
  task's own brief mandated**, beyond what §5/§6 named explicitly: a Button/
  CheckBox font-color cascade gap between the root and compact themes
  (Task 3); `INK_TITLE == INK_BODY` silently erasing 3 "selected/active"
  highlight states (Task 7, fixed via `SECONDARY`/`heraldry()`); a main-menu
  title readability regression from the font commit (Task 7 fix round); a
  `CheckBox.font_pressed_color` cascade gap specific to a checked-by-default
  box on light parchment (Task 8); and the same root/compact-theme cascade
  gap recurring for `ProgressBar`/`HSeparator`/`VSeparator`/`HSlider`/
  `VSlider`/`LineEdit`/scrollbars — undetected until Task 8's coherence pass
  because the affected controls (Victory panel bars, in-game Options
  sliders) hadn't been screenshotted under the compact theme specifically
  until then. See `docs/ui_style_guide.md`'s "Generated chrome pipeline"
  section for the general mechanism (now documented so it isn't
  rediscovered a third time).
- **Two `.tscn`-defined panels invisible to the `.gd`-file literal sweeps**:
  `campaign.tscn`'s `RegionPanel` and `SelectedArmyPanel` labels carried
  static `theme_override_colors` baked for the pre-overhaul dark HUD skin —
  never touched by any task's `Color(0....)` grep because those greps target
  `.gd` source, not `.tscn` resource properties. Found and fixed in Task 8's
  coherence pass; see `docs/ui_style_guide.md` for the pattern going forward.

## Goal

Replace the stock PNG chrome textures (`button1.png`, `frame1.png`, `notification1.png`) with a **generated Parchment & Ink style system** that is themed per faction — playing Skulloath must look and feel different from playing Empire. **Every UI element carries the same coherent style language with faction styling** (user directive 2026-08-03): not just frames and buttons, but chips, progress bars, tooltips, separators, sliders, tabs, scrollbars, plaques — all of it reads as one parchment-and-ink system with the player faction's ink/heraldry accents. Scope: **everything** (campaign HUD + all dialogs, main menu, faction select, battle HUD) plus a **real bundled font**. Reference look: `assets/ui_style_candidates/style_parchment.png` (Empire/Skulloath contrast pair is the quality bar).

## Non-goals

- Map-marker drawing, terrain art, unit/battle sprite colors — untouched.
- Background images (`MainMenuBackground.png`, `factionselectionbackground.png`) — stay.
- A hunt for all 1,357 inline `Color(...)` literals — only categories that visibly clash migrate (see §5).
- Per-faction layout differences — geometry is shared; only palette + motifs vary.

## 1. Generator & baked assets

One committed CLI tool `tests/tools_generate_ui_chrome.gd`, following the `tools_generate_resource_art.gd` pattern exactly: windowed run, SubViewport `UPDATE_ONCE` capture, deterministic RNG (`rng.seed = hash(asset_id)`), `save_png` output, followed by a headless `--import` pass.

Output to `assets/sprites/ui/generated/`, per set:

| Piece | Content |
|---|---|
| `<id>_frame.png` | Parchment field, inked double-line wobble border, 4 wax-seal corner motifs baked into nine-patch corners |
| `<id>_btn_normal.png` | Parchment fill + ink border |
| `<id>_btn_hover.png` | Brighter parchment + heraldry-color border emphasis |
| `<id>_btn_pressed.png` | Heraldry-color fill, light text expected |
| `<id>_btn_disabled.png` | Desaturated parchment, faded ink |
| `<id>_notification.png` | Ornate frame variant (replaces `notification1.png` role) |

Sets: 11 major factions + 1 **neutral** set (main menu, faction select, independents, any missing id). Compact-scale variants are NOT baked — derived at runtime via the existing `_scaled_image_texture()` re-scale, unchanged.

**Nine-patch geometry becomes designed constants** (round numbers, e.g. frame texture margin 24px full scale) declared once and shared by tool and `game_manager.gd` — replacing the hand-measured magic regions (`_BTN_REGION` etc.). Chosen close to current effective margins so the ~31 procedural panel builders in `campaign_hud.gd` don't reflow badly; the screenshot sweep (§6) is the check.

## 2. Faction palettes & motifs

A hand-tunable palette table lives in the tool (data, not code branches): per faction `{parchment_tone, ink_color, heraldry_color (seeded from FactionData.color), seal_color, motif_id}`.

Eleven motif painter functions, each drawn procedurally and reused as the wax-seal emblem:

| Faction | Motif |
|---|---|
| empire | laurel shield |
| skulloath | horned skull |
| gladehost | leaf |
| moonspear | crescent |
| sunblessed | sun |
| cinderguard | anvil/flame |
| thunderswarm | bolt |
| forsaken | broken mask |
| ivoryscar | pyramid |
| tainted_jade | fanged blossom |
| shardhorde | crystal shard |

Parchment tone may shift subtly per faction (Skulloath aged darker, Gladehost greenish) but **text-bearing fields stay within a readability band**; body text keeps living on the dark text-chips per `docs/ui_style_guide.md`.

## 3. Runtime application & fallbacks

`game_manager.gd` stays the single chrome chokepoint:

- Boot: `_setup_global_theme()` builds the **neutral** parchment theme (main menu, faction select see this).
- New: `apply_faction_theme(faction_id)` rebuilds root theme + compact theme from that faction's baked set. Called from `new_game` and `load_game` once the player faction is known. This closes the existing "theme applied once at `_ready`, no reapply path" gap.
- Battle HUD and all dialogs inherit automatically (everything reads the root/compact theme).
- Minor factions resolve to parent (`MINOR_FACTION_PARENTS`).
- Fallback chain: faction set → neutral set → flat `StyleBoxFlat` (existing idiom) — a checkout without generated PNGs still runs.

## 4. Font

Bundle an OFL-licensed pair under `assets/fonts/`, applied via the theme only (no per-label changes):

- Body: readable serif — candidate **Alegreya** or **Vollkorn**.
- Display (titles/headers): ink-flavored — candidate **IM Fell English** or **Cinzel**.

A small font-candidate sheet rendered on the parchment chrome at the style guide's size ladder (10–16px) gates the final pick — 11px readability is the real test. Fallback: font file fails to load → Godot default font (today's state). License files ship next to the fonts.

## 5. Full element migration (all UI elements, one style language)

Per the 2026-08-03 user directive, this is a **complete migration of every UI element** to the parchment & ink system, not a clash-only touch-up:

- A `UIPalette` helper at the theme layer holds the semantic palette (`INK_TITLE`, `INK_BODY`, `CHIP_BG`, `PARCHMENT_ACCENT`, `SEAL`, `DANGER`, …) and is **rebuilt by `apply_faction_theme`** so every constant already carries the active faction's ink/heraldry tuning. `heraldry(faction_id)` serves cross-faction contexts (diplomacy rows, map-adjacent UI naming other factions).
- The root/compact **Theme gains styled entries for every control type in use** — `ProgressBar`, `HSlider` (settings volume), `HSeparator`, `CheckBox`, `LineEdit`, scrollbars, `TabContainer`/tab-style category buttons, tooltip panel (replacing `ui_theme.tres`'s override) — all drawn in the inked style (e.g. progress bars: parchment trough + heraldry fill + ink border; separators: inked wobble line).
- **All ~59 inline `StyleBoxFlat` call sites** (35 campaign_hud, 9 campaign, 3 battle_v3, 3 audio_manager, 2 main_menu, plus game_manager factories) are migrated: each either deleted (the themed control now looks right by default) or rewired through `UIPalette`/shared factories. The shared factories (`_make_text_chip`, `make_panel_style`, `make_notification_style`, `_create_centered_dialog`) are the first movers.
- Hardcoded UI color literals (title golds, chip backdrops, borders, bar fills, plaque tints) migrate to `UIPalette` constants file-by-file across `campaign_hud.gd`, `campaign.gd`, `battle_v3.gd`, `main_menu.gd`, `audio_manager.gd`. Literals that encode **game semantics** (relation colors, resource-delta green/red, rarity tiers, loyalty bands) become semantic `UIPalette` entries too, so they harmonize with the parchment palette instead of floating free.
- Out of scope stays: map-marker geometry/terrain/battle-sprite colors (`campaign.gd` marker drawing, renderer files) — only their UI-panel surroundings migrate.

## 6. Verification & rollout

- Chrome regenerable with one command; tool + PNGs committed (resource-art provenance convention).
- Art gates: contact sheet of all 12 sets (coordinator judges, then user), plus a windowed `tmp_screenshot_windows.gd` sweep of every major window in ≥2 contrasting factions — the layout-reflow check for the new nine-patch margins (top risk).
- Headless suites stay green: `test_save_roundtrip`, `test_battle_determinism` FINGERPRINT MATCH (UI-only change; battle-path files untouched).
- The windowed sweep also gates **element-level coherence**: every window shot is judged for stray old-style elements (flat grey bars, unthemed sliders, orphan color literals) — the migration is done when no element reads as pre-overhaul.
- Rollout order (each step leaves the game playable): generator + neutral theme → faction sets + apply-hook → font → full element migration (factories first, then file-by-file) → menu/battle sweep.

## Grounding facts (from 2026-08-03 survey)

- All chrome flows through ~10 factory functions in `game_manager.gd`; **zero** NinePatchRect/TextureButton anywhere; no `.tscn` chrome beyond one background TextureRect — the swap is concentrated, not scattered.
- `assets/ui_theme.tres` is only a tooltip override, not the theme system.
- No font resources exist anywhere — nothing to migrate.
- `_LeaderPortrait` (campaign_hud.gd) is the precedent for faction-color-parameterized drawn chrome.
- Risks: 583 inline color literals in campaign_hud.gd (mitigated by §5's category approach), pixel-measured nine-patch magic numbers (§1 replaces them), compact theme derives from full textures at runtime (kept), no theme-reapply hook (§3 adds it).
