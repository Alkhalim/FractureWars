# UI Overhaul #40 — Parchment & Ink Generated Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stock PNG chrome with a generated Parchment & Ink style system themed per faction, migrate EVERY UI element (chips, bars, sliders, tooltips, separators, tabs, plaques) to the same style language, and introduce a bundled font — per `docs/superpowers/specs/2026-08-03-ui-overhaul-design.md` (all decisions locked; reference look = `assets/ui_style_candidates/style_parchment.png`).

**Architecture:** A CLI generator (`tests/tools_generate_ui_chrome.gd`, porting the parchment painters from the committed candidate tool `tests/tools_ui_style_candidates.gd`) bakes 12 chrome sets (11 majors + neutral) to `assets/sprites/ui/generated/`. Runtime consumption model unchanged (StyleBoxTexture in `game_manager.gd` factories); new `apply_faction_theme(faction_id)` rebuilds root+compact themes at campaign start/load. A `UIPalette` static helper (`scripts/ui/ui_palette.gd`) is the single source for every UI color; all ~59 inline StyleBoxFlat sites and UI color literals migrate through it file-by-file.

**Tech Stack:** Godot 4.4 GDScript; SubViewport bake tool (windowed); OFL fonts (Alegreya/Vollkorn body, Cinzel/IM Fell display — pair picked at the Task 5 font gate).

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`. Headless tests: `& "<godot>" --headless --path . -s res://tests/<name>.gd`. Startup "SCRIPT ERROR: Compile Error" noise is benign — only printed PASSED/FAILED verdicts count; noise then NOTHING = runtime crash.
- Generator/screenshot tools run WINDOWED (no `--headless`): `& "<godot>" --resolution 1200x800 --path . -s res://tests/<tool>.gd`. After baking PNGs run `& "<godot>" --headless --path . --import` once so the editor asset DB picks them up.
- Scene scripts (`campaign_hud.gd`, `campaign.gd`, `main_menu.gd`, `battle_v3.gd`) do NOT compile headless — verify them with a windowed harness run and check stdout has no SCRIPT ERROR naming the file.
- `tests/test_battle_determinism.gd` must stay FINGERPRINT MATCH after every task (this plan touches zero battle-sim files; if MATCH breaks, STOP and report).
- `docs/ui_style_guide.md` conventions stay binding: body text on dark chips only, compact theme below 48px controls, font ladder 16/14/13/11-12/10, edge-flush panels.
- ART GATES: the implementer bakes + screenshots, the COORDINATOR judges the images, and faction-set/font gates additionally go to the USER. An art gate is a STOP point: commit only after the gate passes.
- Every task leaves the game playable (fallback chain: faction set → neutral set → flat StyleBoxFlat).
- FOREGROUND commands only. Commits end with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- All line refs verified 2026-08-03 but drift — re-locate by searching the quoted identifier before editing.

---

### Task 1: Chrome generator tool + neutral set + geometry constants

**Files:**
- Create: `tests/tools_generate_ui_chrome.gd`
- Create: `assets/sprites/ui/generated/` (neutral set: `neutral_frame.png`, `neutral_btn_normal.png`, `neutral_btn_hover.png`, `neutral_btn_pressed.png`, `neutral_btn_disabled.png`, `neutral_notification.png`)
- Reference (read, port painters from): `tests/tools_ui_style_candidates.gd`, `tests/tools_generate_resource_art.gd`

**Interfaces:**
- Produces: the baked-asset naming contract `<set_id>_{frame,btn_normal,btn_hover,btn_pressed,btn_disabled,notification}.png` and the shared geometry constants (Task 3 copies them verbatim into `game_manager.gd`):

```gdscript
const FRAME_SIZE := Vector2i(192, 192)       # frame nine-patch canvas
const FRAME_MARGIN := 24                     # nine-patch texture margin, all 4 sides (corner seals live inside this band)
const BTN_SIZE := Vector2i(96, 48)           # button nine-patch canvas
const BTN_MARGIN := 12                       # button nine-patch margin
const NOTIF_SIZE := Vector2i(224, 224)
const NOTIF_MARGIN := 32
```

- [ ] **Step 1: Read the two source tools.** `tests/tools_ui_style_candidates.gd` (the parchment painters to port: parchment field with stain blotches, inked double-line wobble border, wax-seal corner, button fills per state — keep their drawing code as the visual source of truth) and `tests/tools_generate_resource_art.gd` (the bake mechanics to copy: SubViewport UPDATE_ONCE, `_process` capture, `save_png`, `rng.seed = hash(id)`, windowed-run comment).
- [ ] **Step 2: Write the tool skeleton** — SceneTree script with: the geometry constants above; a `SETS` dict (this task: only `&"neutral"`); a palette record per set `{parchment: Color, parchment_dark: Color, ink: Color, heraldry: Color, seal: Color, motif: StringName}` (neutral: warm paper `Color(0.85, 0.79, 0.66)`, dark field `Color(0.24, 0.21, 0.17)`, ink `Color(0.16, 0.13, 0.10)`, heraldry muted brass `Color(0.62, 0.52, 0.30)`, seal dark brass, motif `&"quill"` — a simple crossed-quills emblem); a job queue baking the 6 pieces per set; CLI arg `--` `<set_id>` to bake one set, no arg = all. Output `res://assets/sprites/ui/generated/`.
- [ ] **Step 3: Port the painters.** Frame: parchment field (stains seeded by set id) + double-line wobble ink border sitting inside the outer 6px + wax-seal motif in each 24px corner square (seals must live entirely inside the FRAME_MARGIN corner cells so nine-patch stretching never distorts them). Buttons: per-state fills exactly as the candidate sheet (normal parchment + ink border; hover pale + heraldry-emphasis border; pressed heraldry fill; disabled desaturated parchment, faded ink) — with borders inside BTN_MARGIN. Notification: frame painter variant with a doubled outer border + seal at top-center instead of corners.
- [ ] **Step 4: Bake the neutral set** (windowed run, then `--import`). Compose a contact sheet `assets/sprites/ui/generated/_contact_neutral.png` (all 6 pieces + one piece stretched to 400×260 to prove the nine-patch corners survive stretching) and copy it to the session scratchpad for the coordinator.
- [ ] **Step 5: ART GATE (coordinator):** seals undistorted on the stretched sample, border weight reads at 100%, states distinguishable. Iterate until passed.
- [ ] **Step 6: Commit** `feat(ui): parchment chrome generator + neutral set` (tool + 6 PNGs + contact sheet).

---

### Task 2: Eleven faction sets — palettes + motif painters

**Files:**
- Modify: `tests/tools_generate_ui_chrome.gd` (SETS grows to 12; 11 motif painters)
- Create: 66 PNGs (`<faction>_*.png` × 11) + `assets/sprites/ui/generated/_contact_factions.png`
- Reference: `data/factions/*.tres` (read each faction's `color` as heraldry seed)

**Interfaces:**
- Consumes: Task 1's painters, geometry, naming contract.
- Produces: set ids exactly matching major faction ids: `empire, skulloath, gladehost, moonspear, sunblessed, shardhorde, thunderswarm, cinderguard, forsaken, ivoryscar, tainted_jade` (Task 4 loads by these ids).

- [ ] **Step 1: Palette table.** Per faction: heraldry = `FactionData.color` hand-tuned toward ink-compatible saturation; parchment tone shifted subtly per faction (skulloath aged/darker, gladehost greenish, ivoryscar sun-bleached, forsaken grey-cold, tainted_jade faint green, cinderguard ember-warm, moonspear cool blue-grey, sunblessed golden, thunderswarm storm-grey, shardhorde crystal-cold, empire clean warm) — every parchment tone stays within the readability band: value 0.70-0.88, saturation ≤ 0.25.
- [ ] **Step 2: Motif painters** (each ~15-30 lines of draw primitives, used in frame corners AND as the wax-seal emboss): empire = laurel shield (shield pentagon + two arced leaf rows); skulloath = horned skull (circle skull + two curved horn triangles + eye notches); gladehost = leaf (teardrop + center vein polyline); moonspear = crescent (two offset circles, lit arc + spear tip); sunblessed = sun (circle + 8 triangle rays); cinderguard = anvil over flame (anvil silhouette + 3 flame teardrops); thunderswarm = bolt (5-point zigzag polygon); forsaken = broken mask (face oval + jagged crack polyline, one empty eye); ivoryscar = pyramid (triangle + step lines + eye slit); tainted_jade = fanged blossom (4 petals + 2 fang triangles); shardhorde = crystal shard (elongated hexagon + inner facet lines).
- [ ] **Step 3: Bake all 12 sets; compose `_contact_factions.png`** — grid 12 rows × (frame thumb, 4 buttons, seal close-up), faction name labels. Copy to scratchpad.
- [ ] **Step 4: ART GATE (coordinator, then USER):** every motif readable at seal size, palettes differentiated but coherent, no faction below the readability band. STOP for the user's verdict before committing.
- [ ] **Step 5: Commit** `feat(ui): 11 faction chrome sets - palettes and seal motifs`.

---

### Task 3: UIPalette + neutral theme swap (the layout-risk task)

**Files:**
- Create: `scripts/ui/ui_palette.gd`
- Modify: `scripts/autoloads/game_manager.gd` (`_setup_global_theme` :102-141, `make_panel_style` :175, `make_notification_style` :203, `get_compact_theme` :358, delete `_BTN_REGION`-era measured constants :84-93)
- Test: `tests/test_ui_palette.gd` (new, headless — UIPalette + theme-build logic compile headlessly; only scene scripts don't)

**Interfaces:**
- Produces (Tasks 4-8 rely on these exact names):
  - `class_name UIPalette` with static `rebuild(set_id: StringName)` and static color vars: `INK_TITLE, INK_BODY, PARCHMENT, PARCHMENT_DARK, PARCHMENT_ACCENT, CHIP_BG, CHIP_BORDER, SEAL, DANGER, SUCCESS, WARN, BAR_FILL, BAR_TROUGH` plus `static func heraldry(faction_id: StringName) -> Color`
  - `GameManager.chrome_set_id: StringName` (currently applied set, `&"neutral"` at boot)
  - `GameManager._build_theme_for_set(set_id: StringName) -> Theme` (used by Task 4's `apply_faction_theme`)

- [ ] **Step 1: Write the failing test** `tests/test_ui_palette.gd` (SceneTree pattern from `tests/test_bounty_gated_techs.gd`: `_init -> call_deferred("_run")`, `_check`, PASSED/FAILED prints, quit codes):

```gdscript
extends SceneTree
var _fails := 0
func _init() -> void: call_deferred("_run")
func _check(c: bool, l: String) -> void:
	if not c: _fails += 1; print("FAIL: " + l)
func _run() -> void:
	# 1. Palette rebuild swaps heraldry-derived colors
	UIPalette.rebuild(&"neutral")
	var neutral_fill: Color = UIPalette.BAR_FILL
	UIPalette.rebuild(&"skulloath")
	_check(UIPalette.BAR_FILL != neutral_fill, "BAR_FILL faction-dependent")
	_check(UIPalette.INK_BODY.v < 0.4, "ink stays dark (readability)")
	_check(UIPalette.CHIP_BG.a < 1.0 and UIPalette.CHIP_BG.v < 0.2, "chip bg dark translucent per style guide")
	# 2. heraldry() works cross-faction without rebuild
	_check(UIPalette.heraldry(&"empire") != UIPalette.heraldry(&"skulloath"), "heraldry per faction")
	# 3. Theme builder produces textured styleboxes when PNGs exist, flat fallback otherwise
	var gm = root.get_node("/root/GameManager")
	var t: Theme = gm._build_theme_for_set(&"neutral")
	_check(t.get_stylebox("normal", "Button") is StyleBoxTexture, "neutral button textured")
	_check(t.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "neutral frame textured")
	var t2: Theme = gm._build_theme_for_set(&"nonexistent_faction")
	_check(t2.get_stylebox("normal", "Button") != null, "fallback still yields a stylebox")
	_check(t.get_stylebox("fill", "ProgressBar") != null, "ProgressBar themed")
	_check(t.get_stylebox("separator", "HSeparator") != null, "HSeparator themed")
	_check(t.get_stylebox("slider", "HSlider") != null, "HSlider themed")
	_check(t.get_stylebox("panel", "TooltipPanel") != null, "tooltip themed")
	print("UI PALETTE TEST %s" % ("PASSED" if _fails == 0 else "FAILED (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
```

- [ ] **Step 2: Run — expect FAIL** (UIPalette nonexistent).
- [ ] **Step 3: Implement `scripts/ui/ui_palette.gd`.** Static vars initialized to the neutral palette; `rebuild(set_id)` looks up the same palette table values as the generator (duplicate the 12-row table as a `const` here — the generator's table is tool-side and bakes pixels, this one drives runtime colors; a comment in BOTH files cross-references them: "keep in sync with <other file>"). Derivations: `BAR_FILL = heraldry.darkened(0.1)`, `BAR_TROUGH = PARCHMENT_DARK`, `CHIP_BG = Color(0.05, 0.04, 0.03, 0.72)` (style-guide constant, faction-independent), `DANGER/SUCCESS/WARN` = fixed semantic reds/greens/ambers harmonized to ink saturation. `heraldry(faction_id)` resolves minors via `GameManager.MINOR_FACTION_PARENTS` and reads the table (fallback: `FactionData.color`).
- [ ] **Step 4: Rework `game_manager.gd`.** Extract theme construction into `_build_theme_for_set(set_id)`: loads `res://assets/sprites/ui/generated/<set_id>_*.png` (missing file → try `neutral_*` → still missing → the existing `StyleBoxFlat` fallback branch, preserved); StyleBoxTexture with the Task-1 geometry constants (copied verbatim, replacing `_BTN_REGION`/`_FRAME_TEX_MARGIN`/measured numbers — whole-texture regions now, no sub-region slicing); adds themed entries for `ProgressBar` (background=`BAR_TROUGH` flat + ink border, fill=`BAR_FILL`), `HSeparator` (2px ink line stylebox), `HSlider` (slider trough flat + grabber circle in heraldry), `CheckBox` (parchment box + ink check), `LineEdit` (parchment-dark field + ink border), `VScrollBar`/`HScrollBar` (slim ink grabber), `TooltipPanel`/`TooltipLabel` (dark chip + parchment text — retiring `assets/ui_theme.tres`'s role; leave the .tres file but stop assigning it anywhere). `_setup_global_theme()` becomes: `UIPalette.rebuild(&"neutral"); chrome_set_id = &"neutral"; get_tree().root.theme = _build_theme_for_set(&"neutral")`. `get_compact_theme()` keeps the `_scaled_image_texture` 25% mechanic but reads the generated PNGs.
- [ ] **Step 5: Run the test — expect PASSED.** Headless regressions: `test_save_roundtrip`, `test_battle_determinism` (MATCH).
- [ ] **Step 6: Windowed layout sweep** — run `tests/tmp_screenshot_windows.gd` (opens+screenshots all major windows); check stdout for SCRIPT ERROR; coordinator judges shots for layout breakage (clipped buttons, collapsed panels, text on parchment without chips). The 31 panel builders were tuned against old margins — THIS is where reflow shows up. Fix reflow by adjusting the geometry constants (both files) or content margins in `_build_theme_for_set`, never per-panel hacks.
- [ ] **Step 7: Commit** `feat(ui): UIPalette + generated neutral theme replaces PNG chrome`.

---

### Task 4: apply_faction_theme — faction switching live

**Files:**
- Modify: `scripts/autoloads/game_manager.gd` (`new_game`, `load_game` — search for where `player_faction_id` becomes known in each; add the call immediately after)
- Test: `tests/test_ui_palette.gd` (append)

**Interfaces:**
- Consumes: `_build_theme_for_set`, `UIPalette.rebuild`, `chrome_set_id` (Task 3).
- Produces: `GameManager.apply_faction_theme(faction_id: StringName)` — resolves minors to parents via `MINOR_FACTION_PARENTS`, rebuilds UIPalette + root theme + invalidates the cached compact theme so it lazily rebuilds from the new set.

- [ ] **Step 1: Append failing test:**

```gdscript
func _run_faction_theme_test(gm) -> void:
	gm.new_game(&"skulloath", false, 0)
	_check(gm.chrome_set_id == &"skulloath", "new_game applies faction chrome (got %s)" % gm.chrome_set_id)
	var btn_style = root.theme.get_stylebox("normal", "Button") if root.theme else null
	_check(btn_style is StyleBoxTexture and (btn_style.texture.resource_path.contains("skulloath")), "root theme uses skulloath textures")
	gm.apply_faction_theme(&"nonexistent")
	_check(gm.chrome_set_id == &"nonexistent", "set id tracked even on fallback")
	_check(root.theme.get_stylebox("normal", "Button") != null, "fallback theme still valid")
	gm.apply_faction_theme(&"neutral")
```

(If `root.theme` isn't readable headless, assert via `gm._build_theme_for_set` + `chrome_set_id` only — note it in the report.)
- [ ] **Step 2: Run — expect FAIL.** **Step 3: Implement** `apply_faction_theme` + the two call sites (`new_game` after faction assignment; `load_game` after state deserialize). Compact-theme cache: search `get_compact_theme` for its memoization var and null it in `apply_faction_theme`.
- [ ] **Step 4: Test PASSED + regressions** (`test_save_roundtrip` — loading an old save must apply the loaded faction's theme; `test_battle_determinism` MATCH).
- [ ] **Step 5: Windowed spot-check:** `tmp_screenshot_windows.gd` variant run as skulloath (edit the harness's `new_game` faction arg if hardcoded) — shots show red-skull chrome. Coordinator judges.
- [ ] **Step 6: Commit** `feat(ui): faction chrome applied at campaign start and load`.

---

### Task 5: Bundled font pair (art-gated pick)

**Files:**
- Create: `assets/fonts/` (candidates then final pair + `OFL.txt` licenses)
- Create: `tests/tools_font_candidate_sheet.gd` (bake tool, committed)
- Modify: `scripts/autoloads/game_manager.gd` (`_build_theme_for_set`: default_font + per-type font sizes)

**Interfaces:**
- Consumes: `_build_theme_for_set` (Task 3).
- Produces: theme default font = body face; `"HeaderLarge"`/`"HeaderMedium"` Label theme_type_variations (display face 16/14) that Task 6 applies to titles.

- [ ] **Step 1: Download 4 OFL candidates** (WebFetch or curl; each repo dir also carries `OFL.txt` — download alongside):
  - Body A: `https://github.com/google/fonts/raw/main/ofl/alegreya/Alegreya%5Bwght%5D.ttf`
  - Body B: `https://github.com/google/fonts/raw/main/ofl/vollkorn/Vollkorn%5Bwght%5D.ttf`
  - Display A: `https://github.com/google/fonts/raw/main/ofl/cinzel/Cinzel%5Bwght%5D.ttf`
  - Display B: `https://github.com/google/fonts/raw/main/ofl/imfellenglish/IMFellEnglish-Regular.ttf`
  If download fails (no network), STOP and report NEEDS_CONTEXT — the coordinator supplies files.
- [ ] **Step 2: Bake the candidate sheet** — tool renders each body candidate at 13/12/11/10px paragraph + each display candidate at 20/16/14px titles, ON the neutral parchment frame texture, plus a digits row (`0123456789 +15% −3`) per face at 11px (HUD numerals are the stress case). Copy to scratchpad.
- [ ] **Step 3: ART GATE (coordinator, then USER):** pick body + display. STOP for user verdict. Delete the two unchosen files.
- [ ] **Step 4: Wire in:** `_build_theme_for_set` sets `theme.default_font` (body, load via `load("res://assets/fonts/<chosen>.ttf")`, null-guard → skip = Godot default), `default_font_size = 13`, Button font_size 13, and registers `HeaderLarge`(display 16)/`HeaderMedium`(display 14) type variations.
- [ ] **Step 5: Windowed sweep** (`tmp_screenshot_windows.gd`): text overflow check — procedural panels sized for the default font may clip with the new metrics; fix via the style guide's rule (containers must fit largest font), reporting any panel that needed a size bump. Headless: `test_save_roundtrip`, determinism MATCH.
- [ ] **Step 6: Commit** `feat(ui): bundled OFL font pair - <body> body, <display> display`.

---

### Task 6: Element migration — campaign_hud.gd

**Files:**
- Modify: `scenes/campaign/campaign_hud.gd` (35 StyleBoxFlat sites + UI color literals; shared factories first: `_make_text_chip`, `_create_centered_dialog` :11739, progress bars, separators, category tabs, portrait borders, tooltip backgrounds)

**Interfaces:**
- Consumes: `UIPalette.*`, `heraldry()`, `HeaderLarge`/`HeaderMedium` variations (Tasks 3-5).

- [ ] **Step 1: Factories.** `_make_text_chip` → `UIPalette.CHIP_BG`/`CHIP_BORDER`; `_create_centered_dialog` → themed PanelContainer (drop any inline stylebox; title Label gets `theme_type_variation = "HeaderLarge"`); dialog backdrop dimmer → `UIPalette` constant.
- [ ] **Step 2: Sweep the 35 sites** (grep `StyleBoxFlat.new()` in the file, handle each): delete where the themed control now covers it (progress bars, separators, sliders); rewire the rest (chips, plaques, portrait borders, tab styling, tooltip boxes) through `UIPalette` constants or `heraldry(fid)` for faction-colored accents (e.g. `_LeaderPortrait` :5286 keeps its draw code but sources colors from `heraldry`).
- [ ] **Step 3: Color-literal sweep, semantic categories only** (grep `Color(0.`): title golds → `INK_TITLE`; body/dim text colors → `INK_BODY`/derivatives; green/red deltas → `SUCCESS`/`DANGER`; amber warnings → `WARN`; bar fills → `BAR_FILL`. Leave: map-marker colors, faction-data-driven colors, one-off effect tints. Expect to migrate roughly 150-250 of the 583; every migrated literal must map to a semantically-correct constant, not just the nearest color.
- [ ] **Step 4: Windowed verification** — `tmp_screenshot_windows.gd` full sweep ×2 factions (empire + skulloath): zero SCRIPT ERROR naming campaign_hud.gd; coordinator judges for element-level coherence (spec §6: no element reads as pre-overhaul — no flat grey bars, no unthemed sliders, no stray gold titles).
- [ ] **Step 5: Headless regressions** — `test_ui_palette`, `test_save_roundtrip`, `test_polish_pass`, `test_battle_determinism` (MATCH).
- [ ] **Step 6: Commit** `refactor(ui): campaign HUD elements migrate to UIPalette parchment system`.

---

### Task 7: Element migration — campaign.gd, battle_v3.gd, main_menu.gd, audio_manager.gd

**Files:**
- Modify: `scenes/campaign/campaign.gd` (9 sites: diplomacy row plaques, misc panels — NOT the map-marker `_draw` code)
- Modify: `scenes/battle/battle_v3.gd` (3 sites + battle HUD color literals in UI panels only)
- Modify: `scenes/main/main_menu.gd` (2 sites; faction-select list; title Labels get `HeaderLarge`)
- Modify: `scripts/autoloads/audio_manager.gd` (3 sites: settings volume slider track/fill :635,753,759 — themed HSlider should cover; delete or rewire)

**Interfaces:**
- Consumes: same as Task 6.

- [ ] **Step 1: Per file, same recipe as Task 6** (factories/themed-control deletions first, then UIPalette rewires, then semantic literal sweep). Diplomacy plaques use `heraldry(other_faction_id)` for the border tint (cross-faction — NOT the active theme's own heraldry).
- [ ] **Step 2: Windowed verification ×3 surfaces:** main menu + faction select (fresh boot shot), campaign diplomacy panel, one auto-resolve battle opened via an existing battle screenshot harness if present (else drive a battle from the campaign harness; if impractical, state so and shot the battle HUD via a quick scripted battle start). Zero SCRIPT ERROR for each edited scene script; coordinator judges coherence.
- [ ] **Step 3: Headless:** `test_ui_palette`, `test_save_roundtrip`, `test_battle_determinism` (MATCH), `test_ai_economy` (audio_manager is an autoload — verify no headless breakage from its edit).
- [ ] **Step 4: Commit** `refactor(ui): campaign map, battle, menu, settings elements on UIPalette`.

---

### Task 8: Coherence sweep, docs, full battery

**Files:**
- Modify: `docs/ui_style_guide.md` (chrome + palette + font sections), `docs/superpowers/specs/2026-08-03-ui-overhaul-design.md` (Status → IMPLEMENTED + as-built deviations)
- Delete: `assets/sprites/ui/button1.png`, `frame1.png`, `notification1.png` (grep first — zero references must remain), `assets/ui_theme.tres` if fully retired (grep)

**Interfaces:** none — closure task.

- [ ] **Step 1: Final coherence sweep** — windowed `tmp_screenshot_windows.gd` ×2 contrast factions + main menu + battle; coordinator judges every shot against spec §6's bar ("no element reads as pre-overhaul"); USER gets the final shot set as the overhaul's acceptance gate. STOP for user verdict.
- [ ] **Step 2: Delete dead assets** (post-grep) and stale measured-region constants if any survived Task 3.
- [ ] **Step 3: Docs:** style guide gains — generated chrome pipeline (regen command), UIPalette usage rules ("new UI colors go through UIPalette; inline Color() literals in UI code are a review defect"), font ladder with the new faces, faction theming notes. Spec status line + as-built deviations list.
- [ ] **Step 4: Full battery** (all PASSED + MATCH): `test_ui_palette`, `test_save_roundtrip`, `test_polish_pass`, `test_ai_economy`, `test_bounty_gated_techs`, `test_settlement_founding`, `test_income_breakdown_equivalence`, `test_battle_determinism`.
- [ ] **Step 5: Commit** `docs(ui): style guide + spec as-built for parchment overhaul; retire stock chrome`.

## Self-Review

- Spec coverage: §1 generator/naming/geometry → Task 1-2; §2 palettes/motifs (11 named) → Task 2; §3 runtime/apply hook/fallback chain → Tasks 3-4; §4 font pair + gate + fallback → Task 5; §5 FULL element migration (all 59 sites: 35+9+3+3+2 across five files + game_manager's 7 handled in Task 3) + semantic literals + themed control types → Tasks 3 (theme entries) and 6-7 (call sites); §6 art gates/coherence bar/rollout order/battery → Tasks 1,2,5 gates + 8; user directive "ALL elements, coherent + faction-styled" → Tasks 3 theme types, 6-7 sweeps, 8 acceptance gate.
- Placeholders: none — every step names files, code or the committed source to port, run commands, and gates.
- Type consistency: `UIPalette.rebuild(set_id)`, `heraldry(faction_id)`, `_build_theme_for_set(set_id) -> Theme`, `apply_faction_theme(faction_id)`, `chrome_set_id` used identically across Tasks 3-7; asset naming `<set_id>_<piece>.png` identical in Tasks 1,2,3; geometry constants declared Task 1, copied Task 3.
- Known risks written into tasks: layout reflow (Task 3 Step 6 + fix rule), font metric overflow (Task 5 Step 5), palette-table duplication tool↔runtime (cross-reference comments mandated), battle screenshot practicality (Task 7 Step 2 fallback wording).
