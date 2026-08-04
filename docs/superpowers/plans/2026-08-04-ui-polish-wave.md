# UI Polish Wave — Acceptance-Review Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement every item of the designer's 2026-08-04 acceptance review of UI Overhaul #40 (verbatim list preserved in the plan ledger); the overhaul's user acceptance gate repeats after this wave.

**Architecture:** Continuation of the parchment system — all changes route through UIPalette/theme/generator conventions established by the overhaul. No new systems; one small feature (pre-battle strength meter) reuses the existing battle-HUD strength-meter component.

**Tech Stack:** Godot 4.4 GDScript; established windowed screenshot verification; headless battery.

## Global Constraints

- Godot binary `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; headless `-s res://tests/<name>.gd`; compile noise benign, noise-then-nothing = crash; windowed runs for scene scripts; screenshot evidence per task copied to the session scratchpad.
- `test_battle_determinism.gd` stays FINGERPRINT MATCH after every task; STOP if broken.
- New/changed UI colors go through UIPalette (style-guide rule); inline `Color()` literals in UI code are a review defect.
- Layout changes ARE in scope this wave (2-line buttons, width fixes) — but keep them minimal and localized; every changed window gets a screenshot.
- FOREGROUND only; commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task P1: Type scale, crisp fonts, button/panel contrast separation

**Files:** `scripts/autoloads/game_manager.gd` (font sizes in `_build_theme_for_set` + `get_compact_theme`), `assets/fonts/*.ttf.import` (MSDF), `docs/ui_style_guide.md` (ladder update), `scenes/campaign/campaign.gd` (map label rendering if label-specific).

- [ ] Raise the type ladder: theme `default_font_size` 13→15; Button 13→15; HeaderLarge 16→20; HeaderMedium 14→17; compact theme proportionally (was mirroring 13 → mirror 15, floor 12). Update the style-guide ladder table (titles 20 / headers 17 / body 15 / dense 12-13 / floor 12).
- [ ] Crisp text at any zoom (map labels pixelated when zoomed in): enable MSDF on both font imports (`multichannel_signed_distance_field=true` in the .ttf import options, re-import headless). Verify a fully-zoomed-in map label screenshot is sharp. If map labels use a bitmap-scaled path instead of Font scaling, fix that path to font-size-based scaling.
- [ ] Button-vs-background separation ("button color and background color often too close"): strengthen the baked button ink border (generator: +1px weight or darker ink on btn pieces — regenerate) OR theme-side content separation (pick the cheaper that reads; screenshot judged). Also give `_make_text_chip` panels slightly more contrast against parchment if needed after the size bump.
- [ ] Windowed sweep both factions + zoomed map shot; battery: `test_ui_palette`, `test_save_roundtrip`, `test_battle_determinism` (MATCH). Panels that clip from larger fonts: fix at the builder (fit rule), list each in the report.
- [ ] Commit `polish(ui): larger type ladder, MSDF crisp fonts, button contrast`.

### Task P2: Main menu & faction select

**Files:** `scenes/main/main_menu.gd`, `scenes/main/main_menu.tscn` (title/subtitle nodes), background import settings.

- [ ] Title "FRACTURE WARS": impressive treatment — Cinzel HeaderLarge base but ~56px, parchment-gold fill, strong dark outline (6-8px), subtle drop shadow; subtitle ~24px matching style. Judge on screenshot; iterate once.
- [ ] Faction-select list: each faction row/button styled in THAT faction's chrome — btn_normal/hover/pressed textures from `assets/sprites/ui/generated/<id>_btn_*.png` via per-button StyleBoxTexture overrides, faction seal (`<id>_seal.png`) as row icon, heraldry-tinted name. Neutral chrome only for the surrounding frame.
- [ ] Text sizes up throughout menu + faction select (title of faction info, blurb, leader bonuses — leader bonuses get a readable chip with body-15).
- [ ] "Start as X" button: black text outline (outline_size ~3, black), width = measured longest faction name + padding (compute across DataManager factions at build time), centered horizontally.
- [ ] Backgrounds ("too pixelated / mono-colored blobs"): inspect `MainMenuBackground.png` + `factionselectionbackground.png` import settings & source resolution. Enable filtering/mipmaps if off; if the source art is genuinely low-res, add a subtle dark vignette overlay to mask blockiness and report the finding (art regeneration is out of scope this wave — note as follow-up if sources are the problem).
- [ ] Screenshots: menu, faction select unpicked + 2 factions picked. Commit `polish(ui): impressive menu titles, faction-styled selection, readable start flow`.

### Task P3: City panel — 2-line action buttons, readable building cards, fitted income row

**Files:** `scenes/campaign/campaign_hud.gd` (city panel builders).

- [ ] Recruit buttons: 2 lines — line 1 unit name (body-15), line 2 cost icons + turns + pop (dense-13). Height accordingly (~52-56px compact-theme buttons; keep themed chrome).
- [ ] "Upgrade to Level N" and "Found Settlement" buttons: same 2-line treatment (label / costs).
- [ ] Building cards: background → neutral chip/parchment (readable), category color ONLY on the border rim + the small ECO/DEF/CUL tag; text colors from UIPalette (this supersedes the Task-6 "deliberate leave" of `_create_building_card`'s cat_color backgrounds).
- [ ] City income listing ("Income: ..." row): width fits entry count (size flags/fit-content), not fixed length.
- [ ] Screenshots city panel both factions; battery trio; commit `polish(ui): city panel readability - 2-line actions, calm building cards`.

### Task P4: Tech tree readability

**Files:** `scenes/campaign/campaign_hud.gd` (`_RadialTechTree` label drawing, hover tooltip, category labels).

- [ ] Node name labels: draw with dark outline (draw_string outline variant or shadow pass) so they read over any parchment/disc background; category ring labels (ARCANE etc.) same treatment + size up to dense-13.
- [ ] Hover tooltip + detail dialog: verify contrast at the new type scale; tooltip panel opaque (no transparency).
- [ ] Screenshots (tree overview + hover + detail); determinism MATCH; commit `polish(ui): tech tree text readability`.

### Task P5: Diplomacy, dialogs, previews — readability & fitted widths

**Files:** `scenes/campaign/campaign_hud.gd`, `scenes/campaign/campaign.gd`.

- [ ] Diplomacy: faction names high-contrast (parchment-light on dark chip rows, or ink on light — pick per actual row background); relationship/standing list panel fully OPAQUE; general pass over the diplomacy window at the new scale.
- [ ] Event dialog buttons: width fits text (+padding), centered — not full textbox width. Apply to the shared dialog factory so all event/dilemma dialogs inherit.
- [ ] Skill/ability info previews (commander skill tooltips + any hover previews): fully opaque backgrounds.
- [ ] Dialog text areas: content takes more of the panel (reduce oversized margins where a small text block floats in a large box — combined with the larger type this closes the "small text, large box" complaint). Sweep the _create_centered_dialog callers with visibly bad ratios (victory, event, report dialogs) and tighten.
- [ ] Screenshots (diplomacy, one event dialog, one skill preview); commit `polish(ui): diplomacy contrast, opaque previews, fitted dialog buttons`.

### Task P6: Battle screens

**Files:** `scenes/battle/battle_v3.gd`, battle setup/report builders (locate: battle setup screen + `_show_battle_report`/result dialog; also campaign-side pre-battle dialog in campaign_hud.gd if the selection screen lives there).

- [ ] Pre-battle/selection screen: add a relative strength meter — reuse the existing strength-meter component/logic (army power sums both sides, same estimate the HUD meter uses), themed BAR_FILL vs DANGER.
- [ ] Battle report: window sized so NO scrolling at typical content (raise min size, 2-column if needed); resource quantities shown with icons (`GameManager.make_resource_icon`/`cost_bbcode`) instead of text names.
- [ ] Screenshots (setup w/ meter, report); determinism MATCH mandatory; commit `polish(ui): pre-battle strength meter, icon-based no-scroll battle report`.

### Task P7: Misc fixes + investigations

**Files:** `scenes/campaign/campaign_hud.gd` (top bar, placement mode), `data/buildings/*.tres` + `data/research/*` (kennels), report.

- [ ] Remove the season/year flavor text from the top bar ("Moonwatch, 174 S.F." style strings — locate the top-bar date label; remove label + its updates; keep turn number).
- [ ] Placement click-through BUG: during building tile placement the city panel fades (quickfix #41) but still blocks clicks — set `mouse_filter = MOUSE_FILTER_IGNORE` on the faded panel AND its children (recursively or via top-level), restore on exit paths (confirm/cancel/close). Verify by scripted placement click through the faded panel region.
- [ ] INVESTIGATE Frost Kennels (T1) vs Frost Wolf Den: both unlocked by tier-1 techs per the designer. Read the .tres data: are they an upgrade chain (`upgrades_to`/`upgrade_of`)? If interdependent buildings shouldn't unlock in the same tier, propose + apply the minimal data fix (e.g. move the dependent unlock to the T2 tech) and REPORT the before/after clearly for the designer; if they're actually independent by design, report that with evidence and change nothing.
- [ ] Battery: full 8-suite battery + MATCH (this task ends the wave). Commit `polish(ui): top-bar cleanup, placement click-through fix, kennels data check`.

## Self-Review

- Every acceptance-review item mapped: larger text (P1, P3, P5), main-menu titles (P2), faction-styled selection + start button (P2), 2-line recruit/upgrade/settle buttons (P3), building-card readability (P3), tech-tree text (P4), button/background contrast (P1), event button widths (P5), income listing fit (P3), season/year removal (P7), diplomacy names + opaque relationship list (P5), pixelated backgrounds (P2 investigate), pre-battle strength meter (P6), battle report size + icons (P6), opaque skill previews (P5), zoomed map text crispness (P1 MSDF), textbox space (P5), placement click-through (P7), frost kennels question (P7).
- No placeholders; files and mechanisms named; screenshot gates per task; final battery in P7.
