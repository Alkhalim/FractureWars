# UI Overhaul #40 — Generated Parchment & Ink Chrome with Faction Theming

Status: APPROVED DESIGN 2026-08-03 (style direction D picked from `assets/ui_style_candidates/`; all sections user-approved in brainstorming).

## Goal

Replace the two stock PNG chrome textures (`button1.png`, `frame1.png`, `notification1.png`) with a **generated Parchment & Ink style system** that is themed per faction — playing Skulloath must look and feel different from playing Empire — while consolidating the inline styling drift that makes panels inconsistent. Scope: **everything** (campaign HUD + all dialogs, main menu, faction select, battle HUD) plus a **real bundled font**. Reference look: `assets/ui_style_candidates/style_parchment.png` (Empire/Skulloath contrast pair is the quality bar).

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

## 5. Inline-style consolidation

A small `UIPalette` helper at the theme layer with semantic constants (`INK_TITLE`, `CHIP_BG`, `PARCHMENT_ACCENT`, `DANGER`, …) plus `heraldry(faction_id)`. The shared factories (`_make_text_chip`, `make_panel_style`, `_create_centered_dialog`, progress-bar and separator styling) are rewired through it.

Scattered one-off literals migrate **only where they visibly clash** with the new chrome — the known categories: title golds, chip backdrops, separator/border tones. Found by grep, judged by screenshot. Everything else stays.

## 6. Verification & rollout

- Chrome regenerable with one command; tool + PNGs committed (resource-art provenance convention).
- Art gates: contact sheet of all 12 sets (coordinator judges, then user), plus a windowed `tmp_screenshot_windows.gd` sweep of every major window in ≥2 contrasting factions — the layout-reflow check for the new nine-patch margins (top risk).
- Headless suites stay green: `test_save_roundtrip`, `test_battle_determinism` FINGERPRINT MATCH (UI-only change; battle-path files untouched).
- Rollout order (each step leaves the game playable): generator + neutral theme → faction sets + apply-hook → font → consolidation pass → menu/battle sweep.

## Grounding facts (from 2026-08-03 survey)

- All chrome flows through ~10 factory functions in `game_manager.gd`; **zero** NinePatchRect/TextureButton anywhere; no `.tscn` chrome beyond one background TextureRect — the swap is concentrated, not scattered.
- `assets/ui_theme.tres` is only a tooltip override, not the theme system.
- No font resources exist anywhere — nothing to migrate.
- `_LeaderPortrait` (campaign_hud.gd) is the precedent for faction-color-parameterized drawn chrome.
- Risks: 583 inline color literals in campaign_hud.gd (mitigated by §5's category approach), pixel-measured nine-patch magic numbers (§1 replaces them), compact theme derives from full textures at runtime (kept), no theme-reapply hook (§3 adds it).
