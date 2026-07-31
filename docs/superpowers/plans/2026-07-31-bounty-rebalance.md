# Bounty Density + Placement Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (user directive, verbatim intent):** Bounties should be much more common (~3-5 visible near a starting position, not 1); settling should be a "which bounty helps me more" decision, not "do I get one at all"; every spawned bounty must be either within claim range of an existing NON-major city (independent/guardian) or far enough from all cities that a new settlement can grab it — never auto-claimed for free by a major faction's starting city, never stranded in a dead zone.

**Architecture:** The map-gen scatter stays (roster roll, terrain fit) but gets denser caps; a NEW deterministic post-pass in `new_game` — running AFTER all cities exist (init_cities + guardians) — enforces the placement rule by relocating/removing invalid bounties and topping up: (a) ≥3 settlement-grabbable bounties in the ring around each major capital, (b) a global density target. Claims logic, effects, and UI are untouched.

**Tech Stack:** Godot 4.4 GDScript, headless SceneTree tests.

## Global Constraints

- Godot binary: `G:\Programme\Godot\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64_console.exe`; startup "SCRIPT ERROR: Compile Error" noise benign — only printed PASSED/FAILED verdicts count; every test `new_game` pins map_seed.
- ALL placement math deterministic — coordinate hashes salted by `GameManager.state.map_seed` (0 = a stable layout, though bounty fingerprints WILL change vs the previous algorithm — that is expected and fine; only run-to-run determinism matters).
- Validity rule (exact): a bounty at hex B is VALID iff
  1. `dist(B, any major-faction city) > CLAIM_RADIUS` (no free spawns for majors — majors can still claim later via conquest/new settlements), AND
  2. `dist(B, some independent-faction city) <= CLAIM_RADIUS` OR B is GRABBABLE: there exists a land tile T (terrain not WATER and not MOUNTAINS) with `dist(T, B) <= CLAIM_RADIUS` and `dist(T, every existing city) >= 4` (the settlement-founding exclusion is radius-3, so distance ≥4 is foundable).
- Density targets: global total ≈ `land_tiles / 40` (≈150 on the 117×78 map, roughly double today's); per-type cap `MAX_PER_TYPE = 14`; `MIN_SPACING = 3` unchanged; ROSTER_ROLL unchanged. Capital ring guarantee: for every MAJOR faction's capital, ≥3 valid GRABBABLE bounties within hex-distance 4..10.
- FOREGROUND commands only in dispatches. Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Rebalance pass + density constants + tests

**Files:**
- Modify: `scripts/systems/campaign/bounty_system.gd` — constants + new `rebalance_for_cities()` static
- Modify: `scripts/autoloads/game_manager.gd` — `new_game`: call `BountySystem.rebalance_for_cities(state.hex_map, state.map_seed)` AFTER `_ensure_landmark_neighbors()` and BEFORE `_recompute_all_territory()`
- Test: `tests/test_bounty_system.gd` (extend)

**Interfaces:**
- Produces: `BountySystem.rebalance_for_cities(map: HexMapData, salt: int) -> void`; `BountySystem.DENSITY_DIVISOR := 40`; `MAX_PER_TYPE := 14`; `CAPITAL_RING_MIN := 3`; `CAPITAL_RING_NEAR := 4`; `CAPITAL_RING_FAR := 10`; helper `BountySystem.is_valid_bounty_spot(map, coord) -> bool` (the validity rule, city-aware, usable by tests).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_bounty_system.gd` before the final PASSED block (and UPDATE any existing assertion that now conflicts — notably the per-type `<= 8` cap check must become `<= BountySystem.MAX_PER_TYPE`):

```gdscript
	# ── Density + placement rebalance (user directive 2026-07-31) ──
	for seed_v in [0, 1, 2]:
		_gm.new_game(&"empire", false, seed_v)
		var mapd = _gm.state.hex_map
		var land := 0
		var total_b := 0
		for coord in mapd.tiles:
			var t = mapd.tiles[coord]
			if t.terrain != Enums.TerrainType.WATER:
				land += 1
			if t.bounty_id != &"":
				total_b += 1
		_check(total_b >= land / 60, "seed %d: density at least land/60 (got %d of %d land)" % [seed_v, total_b, land])
		# Validity rule holds for EVERY bounty
		for coord in mapd.tiles:
			if mapd.tiles[coord].bounty_id == &"":
				continue
			_check(BountySystem.is_valid_bounty_spot(mapd, coord), "seed %d: bounty at %s satisfies placement rule" % [seed_v, coord])
		# No major-faction city auto-claims at spawn
		for cid in _gm.state.cities:
			var c: CityState = _gm.state.cities[cid]
			if c.faction_id == &"independent" or _gm.is_npc_faction(c.faction_id):
				continue
			_check(BountySystem.claimed_bounties_for_city(c).is_empty(), "seed %d: major city %s starts with zero free bounties" % [seed_v, c.get_display_name()])
		# Capital ring guarantee: every major capital has >=3 grabbable bounties at dist 4..10
		for fid in _gm.state.faction_states:
			var fd: FactionData = root.get_node("/root/DataManager").get_faction(fid)
			if fd == null or not fd.is_playable:
				continue
			var cap: CityState = null
			for cid2 in _gm.state.cities:
				var c2: CityState = _gm.state.cities[cid2]
				if c2.faction_id == fid and c2.is_capital:
					cap = c2
					break
			if cap == null:
				continue
			var ring := 0
			for coord in mapd.tiles:
				if mapd.tiles[coord].bounty_id == &"":
					continue
				var d := HexHelper.hex_distance(cap.hex_pos, coord)
				if d >= BountySystem.CAPITAL_RING_NEAR and d <= BountySystem.CAPITAL_RING_FAR:
					ring += 1
			_check(ring >= BountySystem.CAPITAL_RING_MIN, "seed %d: capital of %s has >=3 ring bounties (got %d)" % [seed_v, fid, ring])
	_gm.new_game(&"empire", false, 0)
```

(IMPLEMENTER NOTES: `is_capital` field — verify against CityState; the earlier sections of this test file may assert per-type counts `<= 8` and a specific fingerprint flow — update the cap to `MAX_PER_TYPE` and confirm the determinism section still passes since it compares run-to-run, not against a frozen value. The earlier "Aurelion claims 2 bounties naturally" behavior no longer exists — scan the file for any assertion that RELIED on natural major-city claims and convert it to crafted claims like the delta tests already use.)

- [ ] **Step 2: Run — FAILs** (rebalance/validity functions missing; density too low; majors auto-claim).

- [ ] **Step 3: Implement in `bounty_system.gd`:**

```gdscript
const DENSITY_DIVISOR := 40   # target ~1 bounty per 40 land tiles
const CAPITAL_RING_MIN := 3
const CAPITAL_RING_NEAR := 4
const CAPITAL_RING_FAR := 10

## Placement validity (post-city): never free for majors; claimable by an
## independent town or grabbable by a future settlement.
static func is_valid_bounty_spot(map: HexMapData, coord: Vector2i) -> bool:
	var tile = map.get_tile(coord)
	if tile == null or tile.terrain == Enums.TerrainType.WATER:
		return false
	if tile.special_id != &"" or tile.landmark_id != &"":
		return false
	var near_independent := false
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var d := HexHelper.hex_distance(city.hex_pos, coord)
		if d <= CLAIM_RADIUS:
			if city.faction_id == &"independent":
				near_independent = true
			else:
				return false # major (or other) city would auto-claim: forbidden
	if near_independent:
		return true
	# Grabbable: a foundable land tile within CLAIM_RADIUS
	for dx in range(-CLAIM_RADIUS, CLAIM_RADIUS + 1):
		for dy in range(-CLAIM_RADIUS, CLAIM_RADIUS + 1):
			var t_coord := Vector2i(coord.x + dx, coord.y + dy)
			if HexHelper.hex_distance(coord, t_coord) > CLAIM_RADIUS:
				continue
			var tt = map.get_tile(t_coord)
			if tt == null or tt.terrain == Enums.TerrainType.WATER or tt.terrain == Enums.TerrainType.MOUNTAINS:
				continue
			var far_enough := true
			for city_id2 in GameManager.state.cities:
				if HexHelper.hex_distance(GameManager.state.cities[city_id2].hex_pos, t_coord) < 4:
					far_enough = false
					break
			if far_enough:
				return true
	return false

## Post-city rebalance: relocate invalid map-gen bounties, then top up the
## capital rings and the global density target. Deterministic via salt.
static func rebalance_for_cities(map: HexMapData, salt: int) -> void:
	var coords: Array = map.tiles.keys()
	coords.sort()
	# 1. Collect + strip invalid bounties (keep their type for re-placement)
	var displaced: Array[StringName] = []
	var placed: Array[Vector2i] = []
	for coord in coords:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		if is_valid_bounty_spot(map, coord):
			placed.append(coord)
		else:
			displaced.append(tile.bounty_id)
			tile.bounty_id = &""
	# 2. Build the valid-candidate list once (terrain-agnostic; per-type
	#    terrain checked at placement)
	var candidates: Array[Vector2i] = []
	for coord in coords:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"" and is_valid_bounty_spot(map, coord):
			candidates.append(coord)
	# 3. Re-place displaced types, then top up. Shared placement helper:
	var counts := {}
	for p in placed:
		var b: StringName = map.tiles[p].bounty_id
		counts[b] = counts.get(b, 0) + 1
	var type_ids: Array = BOUNTY_TYPES.keys()
	var queue: Array[StringName] = displaced.duplicate()
	# Capital rings: for each major capital lacking ring coverage, queue extra
	var ring_targets: Array[Vector2i] = []
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == &"independent" or GameManager.is_npc_faction(city.faction_id):
			continue
		if not city.is_capital:
			continue
		var have := 0
		for p in placed:
			var d := HexHelper.hex_distance(city.hex_pos, p)
			if d >= CAPITAL_RING_NEAR and d <= CAPITAL_RING_FAR:
				have += 1
		for k in maxi(0, CAPITAL_RING_MIN + 1 - have): # +1 headroom over the min
			ring_targets.append(city.hex_pos)
	# Global density
	var land := 0
	for coord in coords:
		if map.tiles[coord].terrain != Enums.TerrainType.WATER:
			land += 1
	var target := land / DENSITY_DIVISOR
	# 4. Placement loop: ring targets first (nearest valid candidate to each
	#    capital within the ring band), then displaced+topup on hash-rotated
	#    candidates. All spacing-checked and per-type capped.
	for cap_pos in ring_targets:
		var best := Vector2i(-9999, -9999)
		var best_d := 9999
		for cand in candidates:
			var d := HexHelper.hex_distance(cap_pos, cand)
			if d < CAPITAL_RING_NEAR or d > CAPITAL_RING_FAR:
				continue
			if map.tiles[cand].bounty_id != &"":
				continue
			if not _spacing_ok(map, cand, placed):
				continue
			if d < best_d:
				best_d = d
				best = cand
		if best.x != -9999:
			_place_rebalanced(map, best, type_ids, counts, salt, placed)
	while placed.size() < target:
		var progressed := false
		for cand in candidates:
			if placed.size() >= target:
				break
			if map.tiles[cand].bounty_id != &"":
				continue
			var h := _hash(cand.x + salt * 7919, cand.y + 13)
			if h % 3 != 0:
				continue
			if not _spacing_ok(map, cand, placed):
				continue
			if _place_rebalanced(map, cand, type_ids, counts, salt, placed):
				progressed = true
		if not progressed:
			break # candidates exhausted; accept what fits

static func _spacing_ok(map: HexMapData, coord: Vector2i, placed: Array[Vector2i]) -> bool:
	for p in placed:
		if HexHelper.hex_distance(coord, p) < MIN_SPACING:
			return false
	return true

## Places the hash-preferred terrain-fitting type at coord; false if none fits.
static func _place_rebalanced(map: HexMapData, coord: Vector2i, type_ids: Array, counts: Dictionary, salt: int, placed: Array[Vector2i]) -> bool:
	var tile = map.get_tile(coord)
	var start := _hash(coord.x + salt * 7919, coord.y) % type_ids.size()
	for k in type_ids.size():
		var type_id: StringName = type_ids[(start + k) % type_ids.size()]
		var def: Dictionary = BOUNTY_TYPES[type_id]
		if counts.get(type_id, 0) >= MAX_PER_TYPE:
			continue
		if not (int(tile.terrain) in def.terrains):
			continue
		if def.get("coastal", false) and not _has_water_neighbor(map, coord):
			continue
		tile.bounty_id = type_id
		counts[type_id] = counts.get(type_id, 0) + 1
		placed.append(coord)
		return true
	return false
```

Update `MAX_PER_TYPE` from 8 to 14. NOTE the re-placement ignores the roster roll deliberately: top-up may introduce types the initial roll skipped — acceptable (more variety); document in a comment. `game_manager.gd new_game`: insert `BountySystem.rebalance_for_cities(state.hex_map, state.map_seed)` after `_ensure_landmark_neighbors()`.

- [ ] **Step 4: Run** — full bounty suite + `test_special_resources.gd` + `test_landmarks.gd` + `test_map_seed.gd` (its bounty-agnostic assertions must hold; if it fingerprints bounties anywhere, update per run-to-run semantics) + `test_polish_pass.gd`. All PASSED.
- [ ] **Step 5: Commit** — `feat(resources): denser bounties with settlement-first placement rule` + footer.

---

### Task 2: Verification sweep + doc + visual check

- [ ] **Step 1:** `tmp_econ_sim.gd -- 7 25` (zero SCRIPT ERRORs; AI settlement founding still works), windowed `tmp_screenshot_bounties.gd` + `tmp_screenshot_windows.gd` (all phases; the start-view screenshot should now show multiple bounty chips — count them in the shot and report).
- [ ] **Step 2:** Update `docs/special_resources_design.md`: bounty row "Per map" → "~1 per 40 land tiles (≈150 full map), max 14/type; every deposit either sits beside an independent town or in settleable open land (never auto-claimed by major starting cities); every major capital ring (4-10 hexes) holds ≥3 grabbable bounties"; claim-rule section gains the placement-validity paragraph.
- [ ] **Step 3:** Commit — `docs(resources): bounty density and placement rules` + footer.

---

## Self-Review

- **Spec coverage:** density (~2x + visible-at-start via capital rings), settlement-decision goal (ring guarantee = multiple candidate spots), the user's exact placement disjunction incl. the major-city exclusion (T1); doc + visual verification (T2).
- **Placeholder scan:** complete code for the pass; implementer notes are live-code lookups.
- **Type consistency:** `is_valid_bounty_spot(map, coord)`/`rebalance_for_cities(map, salt)` used consistently; constants named once.
