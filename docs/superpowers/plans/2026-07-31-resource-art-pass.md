# Resource-Tier Art Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the programmatic resource markers (letter-dots, diamonds, stars) with generated gouache art: 22 bounty icons, 8 special-deposit overlays, 7 unique Landmark hex tiles — produced by a new procedural art tool in the established `tools_generate_terrain_tiles.gd` style, wired into the map with graceful fallbacks.

**Architecture:** One new SceneTree tool (`tests/tools_generate_resource_art.gd`) reuses the terrain generator's SubViewport capture loop with THREE canvas modes (64px chips, 128px transparent overlays, 512px hex-clipped tiles) and per-asset painter functions. `campaign.gd`'s marker creation tries `load()` on each generated texture and falls back to the existing polygon code when missing — the game never breaks regardless of generation state.

**Aesthetic gate:** every task ends with a map screenshot that the COORDINATOR (not the implementer) judges before the task is committed-final; painters are expected to need 1-2 tweak rounds.

**Tech Stack:** Godot 4.4 GDScript; windowed tool runs (SubViewport capture requires a window, run `--resolution 600x600`); `--headless --path . --import` after any regeneration.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`.
- Generator determinism: fixed `rng.seed = hash(asset_id)` per asset — same output every run; NO global randi/randf.
- Output dir: `res://assets/sprites/resources/` (`bounty_*.png` 64px, `deposit_*.png` 128px transparent, `landmark_*.png` 512px transparent-outside-hex).
- Wiring must FALL BACK to the current polygon markers when a texture is absent (`load()` null check) — commits are safe pre-import.
- Fog visibility mechanics unchanged (markers stay registered in `_bounty_markers`).
- Scene scripts verify via the windowed screenshot harness; FOREGROUND commands only; tests pin map_seed.
- Style: "boardgame gouache" — flat shapes, slight jitter (`_blob`), darker outline tones, muted palette, subtle speckle; match `tools_generate_terrain_tiles.gd`'s feel. Bounty chips keep the dark-chip + gold-rim identity (readable at 18px on-map).
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Generator tool + 22 bounty icons + wiring

**Files:**
- Create: `tests/tools_generate_resource_art.gd`
- Modify: `scenes/campaign/campaign.gd` `_create_bounty_markers` (bounty loop: Sprite2D + fallback)
- Create (generated): `assets/sprites/resources/bounty_<id>.png` × 22

**Interfaces:**
- Produces: the tool with `MODE` job tuples `[mode: String, asset_id: StringName]`; painter dispatch `_paint_bounty(rng, id)`; campaign.gd helper `_load_resource_art(path: String) -> Texture2D` (null when missing).

- [ ] **Step 1: Tool skeleton** — copy `tools_generate_terrain_tiles.gd`'s `_start`/`_process` capture machinery (SubViewport, UPDATE_ONCE, capture-next-frame, save_png, quit when jobs done) with these changes: viewport size set PER JOB (`64` for bounty mode, `128` deposit, `512` landmark); `_vp.transparent_bg = true` for ALL modes (bounty chips draw their own opaque chip circle); output name `"%s/%s_%s.png" % [OUT_DIR, mode, asset_id]`. Painter draws in native pixel space (no 2x transform for 64/128 modes; landmark mode uses the 256-space×2 transform like terrain).

- [ ] **Step 2: Shared painter helpers** (inside the painter class): copy `_blob`, `_wavy_line` verbatim from the terrain tool; add:

```gdscript
	func _chip(size: float) -> void:
		# Dark chip + gold rim, the on-map identity for bounty icons
		var c := Vector2(size / 2.0, size / 2.0)
		draw_circle(c, size * 0.48, Color(0.78, 0.62, 0.32))
		draw_circle(c, size * 0.42, Color(0.09, 0.075, 0.055))

	func _outline_poly(pts: PackedVector2Array, fill: Color, outline: Color, width := 1.5) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, width)
```

- [ ] **Step 3: The 22 bounty painters** — each `_paint_bounty` case draws `_chip(64.0)` then a 2-3 color emblem centered at (32,32), emblem radius ~14-17px, gouache-flat with a darker outline tone. Complete example painters (write these verbatim, then follow the table for the rest):

```gdscript
	func _b_orchards(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var c := Vector2(32, 34)
		draw_line(c + Vector2(0, 10), c + Vector2(0, -2), Color(0.42, 0.3, 0.2), 3.0)
		_outline_poly(_blob(rng, c + Vector2(0, -6), 11.0, 9, 0.25), Color(0.35, 0.5, 0.28), Color(0.22, 0.34, 0.18))
		draw_circle(c + Vector2(-4, -8), 2.6, Color(0.78, 0.32, 0.28))
		draw_circle(c + Vector2(5, -4), 2.6, Color(0.78, 0.32, 0.28))
		draw_circle(c + Vector2(1, -12), 2.2, Color(0.82, 0.62, 0.3))

	func _b_wild_horses(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		# Horse head silhouette: neck wedge + muzzle + ears, warm bay tone
		var pts := PackedVector2Array([
			Vector2(24, 46), Vector2(27, 30), Vector2(31, 22), Vector2(30, 17),
			Vector2(34, 21), Vector2(38, 20), Vector2(36, 24), Vector2(43, 28),
			Vector2(44, 32), Vector2(38, 31), Vector2(34, 36), Vector2(33, 46),
		])
		_outline_poly(pts, Color(0.55, 0.38, 0.24), Color(0.35, 0.24, 0.15))
		draw_circle(Vector2(35.5, 25.5), 1.1, Color(0.12, 0.1, 0.08))
		# Mane strokes
		for k in 4:
			draw_line(Vector2(27 + k, 29 - k * 2), Vector2(24 + k, 33 - k * 2), Color(0.3, 0.2, 0.12), 1.6)

	func _b_fisheries(rng: RandomNumberGenerator) -> void:
		_chip(64.0)
		var pts := PackedVector2Array([
			Vector2(20, 32), Vector2(28, 25), Vector2(38, 26), Vector2(43, 32),
			Vector2(38, 38), Vector2(28, 39),
		])
		_outline_poly(pts, Color(0.45, 0.6, 0.68), Color(0.28, 0.42, 0.5))
		_outline_poly(PackedVector2Array([Vector2(43, 32), Vector2(49, 26), Vector2(49, 38)]), Color(0.45, 0.6, 0.68), Color(0.28, 0.42, 0.5))
		draw_circle(Vector2(26, 30.5), 1.2, Color(0.12, 0.12, 0.14))
		draw_arc(Vector2(33, 32), 4.5, -0.8, 0.8, 8, Color(0.28, 0.42, 0.5), 1.2)
```

Remaining 19, each following the same structure (chip → emblem with the listed palette/shapes; keep every emblem readable as a silhouette at 18px):

| id | Emblem | Palette (fill / outline / accent) |
|---|---|---|
| grain_basin | 3 wheat stalks fanning up, drooping heads of 5 grain dots each | 0.8,0.68,0.35 / 0.55,0.45,0.22 / — |
| vineyards | grape cluster (7 circles in triangle) + leaf | 0.5,0.3,0.5 / 0.32,0.18,0.34 / leaf 0.4,0.52,0.3 |
| honey_apiaries | 3 stacked honeycomb hexes | 0.85,0.65,0.25 / 0.6,0.44,0.15 / — |
| herb_meadows | sprig: stem + 5 paired leaves | 0.42,0.58,0.35 / 0.28,0.4,0.22 / — |
| pearl_beds | open shell arc + pearl circle | shell 0.7,0.62,0.55 / 0.48,0.42,0.36 / pearl 0.9,0.88,0.85 |
| salt_flats | 3 white crystal cubes clustered | 0.88,0.88,0.85 / 0.62,0.62,0.6 / — |
| marble | white block with two grey veins | 0.85,0.84,0.8 / 0.6,0.58,0.55 / veins 0.65,0.63,0.6 |
| granite | 2 stacked grey blocks | 0.55,0.55,0.55 / 0.38,0.38,0.38 / — |
| basalt_columns | 3 vertical hexagonal columns, staggered heights | 0.32,0.32,0.36 / 0.2,0.2,0.24 / — |
| copper_vein | ingot trapezoid + glint line | 0.72,0.45,0.3 / 0.5,0.3,0.2 / glint 0.85,0.6,0.42 |
| obsidian_flows | jagged black shard, single white glint | 0.15,0.13,0.18 / 0.05,0.05,0.08 / glint 0.7,0.7,0.75 |
| titanstone_quarry | large block + small chisel wedge | 0.6,0.58,0.52 / 0.4,0.38,0.34 / — |
| timber_giants | tall conifer (3 stacked triangles) + trunk | 0.24,0.38,0.24 / 0.15,0.26,0.16 / trunk 0.4,0.28,0.18 |
| amber_groves | teardrop amber with tiny inclusion dot | 0.85,0.6,0.2 / 0.6,0.4,0.12 / dot 0.5,0.32,0.1 |
| furs | pelt outline (rounded rect + 4 leg stubs) | 0.55,0.42,0.3 / 0.36,0.27,0.18 / — |
| crystal_springs | 3 ice-blue crystal spikes from a pool arc | 0.6,0.78,0.88 / 0.4,0.58,0.7 / pool 0.35,0.5,0.62 |
| clay_pits | round pot with rim | 0.62,0.42,0.3 / 0.42,0.28,0.2 / rim highlight 0.72,0.52,0.38 |
| peat_bogs | 3 stacked dark sods, brick pattern | 0.3,0.24,0.18 / 0.18,0.14,0.1 / — |
| dye_gardens | S-swirl of two colors | 0.6,0.3,0.55 & 0.75,0.35,0.3 / outlines darker / — |

- [ ] **Step 4: Wire with fallback** — in `_create_bounty_markers`'s bounty loop, before the polygon code:

```gdscript
		var b_tex := _load_resource_art("res://assets/sprites/resources/bounty_%s.png" % tile.bounty_id)
		if b_tex:
			var spr := Sprite2D.new()
			spr.texture = b_tex
			spr.scale = Vector2(0.30, 0.30)  # 64px -> ~19px on map
			marker.add_child(spr)
		else:
			# fallback: existing chip polygons (keep verbatim)
			...
```

with helper `func _load_resource_art(path: String) -> Texture2D: return load(path) if ResourceLoader.exists(path) else null`.

- [ ] **Step 5: Generate + import + screenshot** — run the tool windowed (`--resolution 600x600 -s res://tests/tools_generate_resource_art.gd -- bounty` — support a mode arg so tasks can regenerate one tier), then `--headless --path . --import`, then the bounty screenshot phase of `tests/tmp_screenshot_bounties.gd`. Report the screenshot path; the COORDINATOR judges the art before final commit. Iterate painter tweaks if directed.
- [ ] **Step 6: Commit** — tool + campaign.gd + the 22 PNGs (+ .import files) — `feat(art): generated bounty icons replace letter chips` + footer.

---

### Task 2: 8 special-deposit overlays

Same structure: 128px transparent canvas, deposit motifs drawn as a small ground patch + crystal/material cluster (center ~(64,78), cluster radius ~34), Sprite2D at scale 0.36 replacing the purple diamond (fallback kept). Palette table:

| id | Motif | Palette |
|---|---|---|
| moonsilver | 4 slender crystal spires, silver-blue | 0.75,0.8,0.9 / outline 0.5,0.55,0.7 / glow dots 0.9,0.93,1.0 |
| sunstone | 3 rounded glow-stones, amber | 0.9,0.7,0.3 / 0.65,0.48,0.18 / glow 0.98,0.85,0.5 |
| deepiron | 5 dark angular nodes part-buried | 0.3,0.3,0.35 / 0.18,0.18,0.22 / rust flecks 0.5,0.32,0.2 |
| heartwood | glowing root knot: 3 crossing roots + green light | roots 0.35,0.26,0.18 / glow 0.5,0.8,0.4 |
| shardglass | 5 teal glass shards, one catching light | 0.35,0.7,0.68 / 0.2,0.48,0.46 / glint 0.8,0.95,0.92 |
| saffron_reeds | tuft of 7 red-gold reeds bending one way | 0.8,0.45,0.25 / 0.55,0.3,0.15 / heads 0.9,0.6,0.3 |
| bloodsalt | crimson salt crust: jagged low crystals on dark ground | 0.7,0.25,0.25 / 0.45,0.15,0.15 / white edges 0.85,0.7,0.7 |
| stormcrystal | single tall jagged crystal + 2 small, electric blue, tiny spark lines | 0.45,0.65,0.9 / 0.28,0.42,0.65 / sparks 0.8,0.9,1.0 |

Deposit tiles keep their hover tooltips; commit `feat(art): special deposit overlays` + footer, after the coordinator screenshot gate.

---

### Task 3: 7 Landmark hex tiles

512px canvas, 256-space×2 transform like terrain tiles. FIRST draw the hex clip base: compute the flat-top hex polygon inscribed in 256-space (radius 122 centered 128,128 — match the map renderer's hex orientation: READ how campaign.gd draws hex tiles / what orientation the terrain textures assume, and match it), fill with a terrain-appropriate base color, draw the scene INSIDE, leave outside transparent. Scenes (each also gets `_speckle`):

| id | Base | Scene |
|---|---|---|
| dragonbone_fields | desert sand 0.76,0.64,0.44 | giant ribcage: 5 arcing bone ribs (white 0.88,0.85,0.78, outlines 0.6,0.58,0.5) over a spine line; half-buried skull blob |
| everfrost_core | tundra snow 0.82,0.85,0.88 | central ice spire (pale blue 0.7,0.85,0.95) with 2 concentric frost rings on the ground + small shards |
| sungold_vein | mountain grey 0.5,0.48,0.46 | rocky peaks with 3 branching gold cracks (0.9,0.75,0.3) radiating from a gold pool |
| worldroot_nexus | forest floor 0.28,0.38,0.24 | massive trunk (0.4,0.3,0.2) with 6 radiating roots to the hex edges + glowing green canopy blob |
| voidglass_rift | wastes purple-grey 0.35,0.3,0.4 | dark fissure (0.1,0.08,0.14) diagonal across, purple glow edge (0.6,0.4,0.8) + floating glass shards |
| titan_forge_ruin | mountain grey 0.48,0.46,0.44 | broken ring of 5 stone anvil-blocks around a central ember glow (0.85,0.45,0.2) |
| leyline_well | plains green 0.5,0.52,0.32 | stone circle of 6 monoliths + glowing cyan lines (0.4,0.85,0.85) connecting them to a bright center |

Wiring: landmark loop replaces the star with `Sprite2D` scale ~0.105 (512 → ~54px, slightly larger than a hex so it reads as dominating the tile; verify against `HEX_RADIUS` = 24 → hex width 48; tune 0.10-0.115 by screenshot), z below city markers, keep glyph label REMOVED when art present (name comes from hover), fallback star kept. Commit after coordinator gate: `feat(art): unique landmark hex tiles` + footer.

---

### Task 4: Sweep + gallery

- Re-run: `test_landmarks`, `test_special_resources`, `test_bounty_system`, windowed `tmp_screenshot_bounties.gd` + `tmp_screenshot_windows.gd` (no scene-script errors; all shots).
- Produce a GALLERY screenshot: a harness phase that pans across one landmark, one deposit, and a bounty cluster at zoom 2 for the user's final art verdict — `user://win_art_gallery.png`.
- Doc: append to `docs/special_resources_design.md` Phase 3 notes — "art pass: generated placeholders replaced ALL programmatic markers (tool: tests/tools_generate_resource_art.gd); hand-made art can later replace individual PNGs file-by-file, no code changes".
- Commit docs + any tuned painters: `docs(resources): note generated art pass` + footer.

---

## Self-Review

- **Spec coverage:** 22 bounty icons (T1), 8 deposits (T2), 7 landmarks (T3), fallback wiring per tier, import + screenshot gates, gallery for the user (T4).
- **Placeholder scan:** three full example painters with real coordinates/colors; the remaining entries carry complete palettes + shape lists (executable against the pattern); no TBDs.
- **Type consistency:** `_load_resource_art` helper name used in T1 wiring and implied by T2/T3 (same helper); file naming `bounty_/deposit_/landmark_<id>.png` consistent across tool output and load paths.
