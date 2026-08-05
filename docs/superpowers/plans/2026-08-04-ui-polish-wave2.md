# UI Polish Wave 2 — Second Acceptance-Review Round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the designer's 2026-08-04 second acceptance round (verbatim in the wave-2 ledger). Acceptance gate repeats after W6; whole-branch review + push after that.

**Architecture:** Continuation of the parchment/UIPalette system. One generator rework (texture-stretch root fix), one unit-button subsystem (class icons/colors), several targeted investigations (strength meter, income mismatch, vision misalignment) and data/design changes (capital L2, no-T3 starters, shard-beast iron).

**Tech Stack:** Godot 4.4 GDScript; established harness/battery conventions.

## Global Constraints

- Same as wave 1: Godot binary `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; windowed harnesses for scene scripts; headless battery; determinism FINGERPRINT MATCH after every task (STOP if broken); colors via UIPalette; screenshots + logs per task to the session scratchpad; FOREGROUND only; commits end `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Art-gated tasks STOP before commit for coordinator judgment (user check rides the acceptance gate).

---

### Task W1: Texture-stretch root fix + chrome treatment extensions (ART GATE)

Designer: boxes look "gestaucht und gestreckt", patterns unnatural when stretched, large panels pixelated ("scaled up too much"); city building menu background and elderbeast background are named examples; training/upgrade buttons need a SUBTLE texture; Upgrade + Found Settlement buttons deserve elaborate/beautified treatment; city-menu + top-bar buttons should get the squiggly border treatment; the faction accent line atop menus is hard to see on some colors — wider + shadow.

**Files:** `tests/tools_generate_ui_chrome.gd`, `scripts/autoloads/game_manager.gd`, `scenes/campaign/campaign_hud.gd` (button styling call sites), rebake.

- [ ] Root-fix stretching: bake the frame (and notification) at a LARGER canvas (e.g. 512² with margin 85 ≈ current 32px visual at typical panel sizes — compute the mapping so on-screen border thickness stays ≈ current; the geometry contract moves in BOTH files) so the center region is minified or ~1:1 on big panels instead of magnified; raise stain-field density/frequency to match the new resolution (no visible polygon edges at 1:1). Non-uniform aspect stretching: evaluate `axis_stretch_horizontal/vertical = TILE_FIT` for the CENTER region vs pure bake-bigger — pick what looks organic (no symmetric tiling artifacts — designer warning stands), judge on 900×700 AND wide-flat (1300×300) samples in the contact sheet.
- [ ] Subtle button texture: training/upgrade (all standard buttons) get a faint parchment-grain fill variation in the baked btn pieces (low-contrast noise, not stains).
- [ ] Ornate special buttons: a new baked piece `<id>_btn_ornate_*.png` (4 states) — squiggle border + corner flourishes + slightly richer fill; applied to "Upgrade to Level N" + "Found Settlement" (theme variation `OrnateButton` or per-button styleboxes).
- [ ] Squiggle treatment for compact contexts: the compact theme's buttons (top bar, city menu) currently derive from the same textures at 25% — verify the wobble survives the downscale readably; if it blurs out, bake dedicated compact btn pieces (48×24, margin 6) with scaled wobble instead of runtime rescale.
- [ ] Accent line: in the frame painter, widen the title underline (1px → 3px) + bake a 1px dark shadow line under it.
- [ ] Rebake all; contact sheet incl. stretched samples; ART GATE (coordinator). Windowed sweep spot-check; headless test_ui_palette + determinism MATCH. Commit `polish(ui): high-res chrome bake ends stretch artifacts; ornate and textured buttons`.

### Task W2: Unit training buttons — class icons, class colors, tag cleanup

Designer: left-side class icon(s) (infantry, monster, cavalry, archer, supporter, mage, …; hybrids show two); color-code buttons by primary class(es) — split-frame for true hybrids; class colors must NOT 1:1 overlap building category colors; hide "Pop 0"; hover info drops superfluous tags (faction names like cinderguard; "melee" implied by absence of "ranged"; archers/mages don't need "range"); hover unit info should use more of its window / read larger.

**Files:** `tests/tools_generate_ui_chrome.gd` OR a small dedicated icon tool (12-16 class glyphs, generated — model on resource icons), `scripts/ui/ui_palette.gd` (class-color table), `scenes/campaign/campaign_hud.gd` (recruit buttons + unit hover info), possibly `scripts/core/` unit-class derivation helper.

- [ ] Class derivation: map UnitData.tags → primary/secondary class (infantry, cavalry, archer, mage, monster, beast, supporter, flying, siege — enumerate from the actual tag vocabulary; grep all tags in data/units). One helper, unit-tested headlessly.
- [ ] Generated class glyph set (~24px, ink-style, readable at button scale); baked once, committed.
- [ ] Recruit buttons: glyph(s) left of the name line; frame tint = class color (UIPalette.CLASS_COLORS — distinct hues from building category colors; verify no 1:1 collision); true hybrids: left half color A frame, right half color B.
- [ ] "Pop 0" hidden; hover info tag cleanup per the rules above; hover panel content scaled to use its window (larger text/fill).
- [ ] Windowed shots: recruit lists for 3 diverse factions (incl. a hybrid-heavy one), hover info. Headless: test_ui_palette + a new headless assert set for the class-derivation helper + determinism MATCH. Commit `feat(ui): unit class icons and colors on training buttons; hover info cleanup`.

### Task W3: Text-density + dark-backing fixes

Designer: building buttons have space for 5 lines but usually 4 — scale text up (down only for complex buildings); events' dark text-backing should extend further (text currently touches the boundary); loyalty menu still missing dark backing behind text; elderbeast panel needs dark chips behind text (white-on-light-grey remains) AND its building buttons must follow the normal building-card guidelines.

**Files:** `scenes/campaign/campaign_hud.gd`.

- [ ] Building cards: font sizes up so 4 lines fill the card; auto step-down when a card genuinely needs 5+ lines.
- [ ] Event dialog: dark backing padding grows (text never touches the chip edge).
- [ ] Loyalty panel: dark chips behind all text (contrast-checked).
- [ ] Elderbeast panel: dark chips behind text blocks; building entries rebuilt via the standard building-card factory.
- [ ] Windowed shots (city cards, event, loyalty, elderbeast ×2 factions incl. shardhorde); headless trio + MATCH. Commit `polish(ui): text density and dark backings - cards, events, loyalty, elderbeast`.

### Task W4: Strength meter accuracy + end-turn HP preview

Designer: meter showed enemy advantage despite player having better AND more units (enemy had higher-HP units) — likely BUG: current formula ignores max HP entirely. Also: selected armies should show a pale end-of-turn HP-bar preview (projected heal/attrition if the army stays put).

**Files:** `scenes/campaign/campaign.gd` (meter formula mirror), `scenes/battle/battle_v3.gd` (HUD formula — keep mirrored), army selection UI (campaign.gd/campaign_hud.gd).

- [ ] INVESTIGATE the meter: reproduce a better-and-more-units-vs-tanky matchup; compare meter vs auto-resolve outcomes across ≥10 varied matchups (scripted headless probe). Fix the shared formula to weigh effective HP (e.g. power = count × (offense_score) × f(hp_per_soldier) — tune until meter direction matches auto-resolve winner in ≥9/10 probes). Update BOTH mirrors + cross-ref comments. Display-only; determinism MATCH mandatory.
- [ ] HP preview: derive end-of-turn projection from the ACTUAL heal/attrition rules (find them: city garrison heal, field regen, siege/desertion attrition in turn_manager/city_system — read first, mirror read-only). Selected army's unit HP bars get a pale overlay segment showing projected next-turn fill/drain. No game-state mutation.
- [ ] Windowed shots (meter on the reproduced matchup pre/post fix, HP preview on a healing army + an attriting army). Headless probe committed as test (meter-direction assertions). Commit `fix(ui): strength meter weighs unit HP; end-turn HP preview on armies`.

### Task W5: Investigations — income mismatch, horde camera, vision misalignment

- [ ] ECO MISMATCH (designer: "net income per round in the eco overview does not line up with the numbers below the resource bar on top"): trace both pipelines (economy panel net row vs top-bar deltas); identify what one includes that the other doesn't (treaties? army upkeep? bounty/lease flows?); FIX so both read one source of truth (there is an income-equivalence precedent: test_income_breakdown_equivalence) or, if the difference is semantically intended (e.g. top bar = last-turn actual, panel = projection), make the labels SAY so. Report the root cause explicitly.
- [ ] HORDE CAMERA (designer: horde/nomadic campaign starts should open camera on the largest current horde): find campaign-start camera placement; for factions with no capital city at start (or camp-based), center on the largest army instead.
- [ ] VISION MISALIGNMENT (designer: 2 vision spots not aligned with horde positions at turn 1, self-cleared after end turn): reproduce with a nomadic start; likely fog seeded from stale anchor/spawn positions before armies took their actual spots; fix the init-order so initial vision derives from final spawn positions.
- [ ] MAP SKETCH UPGRADE (designer: "the map sketch should have the rough outlines of the land masses on it as well as an approximation of the terrain"): `_MapSketch` in main_menu.gd gains coastline outlines (ink stroke around the landmass silhouette) and rough terrain tinting (approximate biome patches from the terrain-assignment data/noise the map generator uses at seed 0 — read map_generator.gd's terrain pass; keep it painterly/rough, parchment style, not a precise minimap).
- [ ] Headless: test_save_roundtrip, test_ai_economy, test_income_breakdown_equivalence, determinism MATCH. Windowed: nomadic start shot (camera on horde, vision aligned). Commit `fix(campaign): income displays reconciled, horde start camera, turn-1 vision`.

### Task W6: Data/design batch (designer-decided)

- [ ] CAPITALS START AT LEVEL 2: find city init (new_game/city creation); capitals get level 2 at campaign start (all factions; verify founding/settlement logic unaffected; check level-up charge logic — founding charges trigger on level-up, ensure starting at 2 doesn't double-grant).
- [ ] NO TIER-3 STARTER BUILDINGS: audit every start-of-game building grant (faction starting buildings, leader "Starts with X" bonuses); list any tier-3 grants; downgrade each to its chain's T1/T2 (same chain where one exists); any case without an obvious downgrade → propose in report, apply the obvious ones.
- [ ] SHARD BEASTS BASE INCOME +2 IRON: locate the shardhorde elderbeast/shard-beast base income data; add iron 2 (resource key 1).
- [ ] Full battery (wave-1's 8 suites) + MATCH; econ sim smoke `tmp_econ_sim.gd -- 7 25` (capital-L2 shifts early economy — report deltas, no faction crater). Commit `balance(design): capitals start L2, no T3 starters, shard-beast iron`.

## Self-Review

Every designer item mapped: stretch artifacts + city-menu bg + elderbeast bg texture (W1); subtle button texture (W1); ornate upgrade/found (W1); squiggle on city/top-bar buttons (W1); accent line wider+shadow (W1); unit class icons/colors/pop-0/tag cleanup/hover density (W2); building-card text scale (W3); event backing extension (W3); loyalty backing (W3); elderbeast chips + standard cards (W3); strength meter accuracy (W4); HP preview (W4); eco mismatch (W5); horde camera (W5); vision misalignment (W5); map sketch outlines+terrain (W5, campaign-data-adjacent drawing alongside camera/vision work); capital L2 (W6); no T3 starters (W6); shard-beast iron (W6). No placeholders; art gate at W1; investigations report root causes explicitly; W6 ends with the full battery + econ smoke.
