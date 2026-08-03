# Faction Color Alignment — SoB Colour Chart → UI Chrome Palettes

Status: PROPOSAL 2026-08-03 — awaiting designer approval before any implementation.
Source: `D:\Downloads\SoB_Faction_Colour_Chart.JPG` (designer-supplied 2026-08-03: primary/secondary/tertiary per faction + playstyle + cultural influences).
Applies to: the generator palette table (`tests/tools_generate_ui_chrome.gd` `SETS`) and its runtime twin (`scripts/ui/ui_palette.gd` `_PALETTE`), followed by a full chrome rebake and one art-gate re-check. Downstream, `UIPalette.heraldry()` (diplomacy plaques, faction accents) picks the new primaries up automatically.

## Chart transcription (source of truth)

| Faction | Playstyle | Cultural influences | Primary | Secondary | Tertiary |
|---|---|---|---|---|---|
| Cinderguard | Aggro | Roman/Polynesian | Crimson `#c4092e` | Charcoal `#42525d` | White `#f5f5f5` |
| Sunblessed | Midrange | Inca/Tibetan | Gold `#f7e689` | Mint Green `#98FF98` | Silver `#c0c0c0` |
| Tainted Jade | Control | Mayan/Chinese | Green `#30740f` | Dark Purple `#301934` | Pale Yellow `#d9d45c` |
| Moonspear | Aggro/Control | French/Babylonian | Blue `#3847cb` | Light Gray `#8c8c8c` | Silver `#c0c0c0` |
| Skulloath | Aggro/Midrange | Mongolian/Maori | Black `#000000` | Maroon `#950a0a` | Bone `#f2ebe3` |
| Forsaken | Control | Slavic/Persian | Purple `#9a0174` | Slate Gray `#708090` | Gold `#ffd700` |
| Thunderswarm | Midrange/Tempo | Norse/Ainu | Orange `#f28536` | Dark Brown `#6c4837` | Cream `#fffdd0` |
| Gladehost | Midrange/Control | Japanese/Celtic | Teal `#3bbcbc` | Beige `#EFE7db` | Autumn Red `#F17363` |
| Shardhorde | Midrange | Scythian/Scottish | Brown `#964b00` | Olive Green `#5a8000` | Dark Lavender `#734F96` |
| Ivoryscar | Control | Hindu/Egyptian | Bone `#f2ebe3` | Black `#212121` | Warm Gray `#c9be90` |

Empire is **not on the chart** — proposal keeps its current blue/gold palette until directed otherwise.

## Mapping rules (how chart colors land in the chrome system)

The chrome palette has 5 slots per faction: `parchment` (panel field), `parchment_dark` (dark chip variant), `ink` (borders/text), `heraldry` (pressed buttons, bar fills, accents), `seal` (wax-seal corners).

1. **Heraldry = chart Primary** (hand-tuned only if a raw value fights the ink borders).
2. **Ink = darkest chart color** of the three (else current ink kept).
3. **Parchment = lightest chart color**, pulled into the readability band (value 0.70–0.88, saturation ≤ 0.25 — binding rule from the approved spec). Saturated lights (e.g. Mint) do NOT become fields — they become accents.
4. **Seal = chart Secondary** (darkened if too light for emboss contrast).
5. **Tertiary → accent** uses: seal emboss highlight, progress-bar tips, hover-border emphasis — where it makes sense, faction by faction.
6. `parchment_dark` re-derived from the new parchment (same darkening as today).

## Per-faction change list (current → proposed)

Severity: **BIG** = palette identity changes, **MOD** = hue shift, **MIN** = value snapping.

| # | Faction | Sev | Current (parchment / ink / heraldry / seal) | Proposed |
|---|---|---|---|---|
| 1 | Skulloath | BIG | dusty-rose `(0.72,0.64,0.62)` / dark red-brown / red `(0.42,0.19,0.20)` / dark red | parchment → **bone tint** (from `#f2ebe3`, banded) — fixes the "dusty-rose vs aged tan" gate note; ink → **near-black** (from `#000000`, kept ≥0.05 for warmth); heraldry → **maroon `#950a0a`**; seal → maroon darkened |
| 2 | Thunderswarm | BIG | storm-grey parchment / blue-grey ink / olive-gold `(0.50,0.44,0.22)` / olive | parchment → **cream tint** (from `#fffdd0`, banded); ink → **dark brown `#6c4837`** deepened; heraldry → **orange `#f28536`**; seal → dark brown |
| 3 | Shardhorde | BIG | lilac parchment `(0.83,0.77,0.85)` / plum ink / magenta `(0.55,0.28,0.49)` / plum | parchment → warm neutral tint (brown-family light, banded); ink → dark brown; heraldry → **brown `#964b00`**; seal → **olive `#5a8000`**; **dark lavender `#734F96`** demoted to accent only |
| 4 | Gladehost | MOD | leaf-green parchment / green ink / green `(0.33,0.44,0.26)` / dark green | parchment → **beige `#EFE7db`** (already in band); ink → deep teal-grey; heraldry → **teal `#3bbcbc`** (tuned darker for button-fill contrast); seal → teal dark; **autumn red `#F17363`** as accent |
| 5 | Moonspear | MOD | blue-grey parchment / navy ink / muted blue `(0.36,0.39,0.55)` / navy | parchment → silver-grey tint (from `#c0c0c0`/`#8c8c8c`, banded); heraldry → **vivid blue `#3847cb`**; seal → blue darkened; ink stays navy-black |
| 6 | Cinderguard | MOD | ember parchment / brown ink / ember `(0.52,0.32,0.21)` / brown | heraldry → **crimson `#c4092e`**; ink → **charcoal `#42525d`** deepened; parchment stays warm but nudged toward white-warm (tertiary `#f5f5f5`); seal → crimson darkened |
| 7 | Forsaken | MOD | grey-violet parchment / violet ink / dull violet `(0.36,0.26,0.40)` / dark violet | heraldry → **purple `#9a0174`**; ink → **slate `#708090`** deepened; parchment stays grey-violet (slate-tinted); seal emboss highlight → **gold `#ffd700`** accent (should make the seal pop) |
| 8 | Sunblessed | MIN | golden parchment / warm ink / gold-brown `(0.62,0.52,0.25)` / dark gold | heraldry → chart **gold `#f7e689`** darkened enough for pressed-state contrast; **mint `#98FF98`** only as sparse accent (out of band for fields); silver for hover emphasis; parchment unchanged |
| 9 | Ivoryscar | MIN | bleached parchment `(0.88,0.86,0.81)` / warm ink / tan / tan dark | parchment pinned to **bone `#f2ebe3`**-derived value inside band (also clears the v=0.880 band-edge ledger note); ink → **`#212121`**-warm; heraldry → **warm gray `#c9be90`** darkened; seal near-black |
| 10 | Tainted Jade | MIN | pale-green parchment / dark green ink / corrupt purple `(0.29,0.22,0.36)` / dark purple | heraldry → **green `#30740f`**; seal → **dark purple `#301934`** with **pale-yellow `#d9d45c`** emboss highlight (fixes the weakest-seal-contrast ledger note); parchment snapped toward chart-green tint |
| 11 | Empire | — | unchanged | not on chart; awaiting designer colors if any |

Note the **primary/heraldry swap for Tainted Jade**: chart makes GREEN the primary and purple secondary — current chrome has purple as heraldry. Proposal follows the chart (green pressed-buttons/bars, purple seals).

## Cultural influences → motifs

The 11 seal motifs were user-approved at the Task 2 art gate and already fit most influences (Inca sun, Norse bolt, Egyptian pyramid, Babylonian crescent, Mongolian skull). **Proposal: keep all motifs unchanged**; treat the influences as guidance for future ornament detailing (border patterns, notification flourishes), not a rework now.

## Open decisions (designer)

1. **Approve the per-faction list above?** (or mark rows for adjustment)
2. **`FactionData.color` alignment** — should map territory / army marker / political-map colors ALSO move to chart primaries? Affects map identity strongly for Shardhorde (magenta→brown), Thunderswarm (grey→orange), Gladehost (green→teal). Recommendation: decide separately from the chrome change; chrome-only first is reversible.
3. **Empire chart colors** — supply if Empire should join the alignment.

## Execution shape once approved

One palette-swap task inside the running UI-overhaul plan (before Task 6's element migration, so migrated colors derive from final palettes): update both palette tables (generator + UIPalette, kept in sync) → rebake all 12 sets → regenerate `_contact_factions.png` → art-gate re-check (coordinator + user) → commit. Motifs, geometry, and theme code untouched.
