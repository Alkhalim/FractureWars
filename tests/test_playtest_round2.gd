extends SceneTree
## Playtest Round 2.
##
## Task A: ocean tiles get REAL coastal income + an honest settlement-founding
## preview.
##
## Two independent fixes, tested separately:
## 1) calculate_city_income() (city_system.gd) now folds in a coastal-waters
##    component (apply_coastal_income_bonus): +2 food / +1 gold per 2 WATER(8)
##    hex neighbors (HexHelper, 6 max), added AFTER region-effects/mobile-camp
##    scaling so the formula always lands exactly. A landlocked city (0 water
##    neighbors) gains exactly 0.
## 2) calculate_settlement_income_preview() (the settlement-founding UI/AI
##    scoring preview) no longer skips WATER tiles in its adjacency loop, and
##    TILE_INCOME/_get_primary_resource now know about WATER -- so the
##    preview stops promising coastal income a founded city never actually
##    got.
##
## Task B: the settlement preview numbers/gradient and the AI's site score
## must count claimable bounty income too. New static helper
## BountySystem.claimable_income_at(map, hex_pos, ignore_fog := false) sums
## BOUNTY_TYPES[id].income over the bounties a settlement at hex_pos would
## claim (same claim rule as bounties_claimable_at). Fog-gated by default
## (matches bounties_claimable_at's existing player-fog anti-spoiler gate for
## the UI preview/gradient); `ignore_fog=true` is for the AI site-scorer only
## -- GameManager.explored_tiles is documented elsewhere (turn_manager.gd) as
## "player fog only", so gating the AI's own settlement decisions on the human
## player's scouting would make the AI blind to most of the map, not smarter.
##
## Run: godot --headless --path . -s res://tests/test_playtest_round2.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)

	_run_real_income_tests()
	_run_preview_tests()
	_run_preview_real_parity_tests()
	_run_coastal_breakdown_label_test()
	_run_bounty_income_tests()
	_run_bounty_claim_exclusion_tests()

	if _fails == 0:
		print("PLAYTEST ROUND 2 TEST PASSED")
		quit(0)
	else:
		print("PLAYTEST ROUND 2 TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

# ── Map scanning helpers ────────────────────────────────────────

func _count_water_neighbors(coord: Vector2i) -> int:
	var hex_map = _gm.state.hex_map
	var n := 0
	for nb in HexHelper.get_neighbors(coord):
		var ntile = hex_map.get_tile(nb)
		if ntile != null and ntile.terrain == Enums.TerrainType.WATER:
			n += 1
	return n

## First land tile (scan order = hex_map.tiles insertion order, deterministic
## for a fixed seed) whose HexHelper water-neighbor count matches `at_least`
## (>=) or exact (==) `target`.
func _find_tile_by_water_neighbors(target: int, at_least: bool) -> Vector2i:
	var hex_map = _gm.state.hex_map
	for coord in hex_map.tiles:
		var tile = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		var wc := _count_water_neighbors(coord)
		if at_least and wc >= target:
			return coord
		if not at_least and wc == target:
			return coord
	return Vector2i(-1, -1)

## Finds a coastal (>=2 water neighbors) + landlocked (0 water neighbors)
## land-tile pair sharing the SAME region_id, so every region-scoped stage of
## calculate_city_income() (province population, region completion, region
## effects) treats both test cities identically -- isolating the coastal
## component as the only possible source of a delta. Returns {} if no region
## on the (deterministic, seed-0) map has both.
func _find_coastal_and_landlocked_pair() -> Dictionary:
	var hex_map = _gm.state.hex_map
	var by_region: Dictionary = {} # region_id -> {coastal, coastal_n, landlocked}
	for coord in hex_map.tiles:
		var tile = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if tile.region_id == &"":
			continue
		var entry: Dictionary = by_region.get_or_add(tile.region_id, {})
		var wc := _count_water_neighbors(coord)
		if wc >= 2 and not entry.has("coastal"):
			entry["coastal"] = coord
			entry["coastal_n"] = wc
		if wc == 0 and not entry.has("landlocked"):
			entry["landlocked"] = coord
		if entry.has("coastal") and entry.has("landlocked"):
			return {
				region_id = tile.region_id,
				coastal = entry.coastal,
				coastal_n = entry.coastal_n,
				landlocked = entry.landlocked,
			}
	return {}

# ── (a)+(c) REAL income: calculate_city_income() coastal delta ─────────────

func _run_real_income_tests() -> void:
	var cs = _gm.city_system

	var pair := _find_coastal_and_landlocked_pair()
	if pair.is_empty():
		_check(false, "found a same-region coastal(>=2 water nbrs)/landlocked(0 water nbrs) tile pair on the seed-0 map")
		return

	var region_id: StringName = pair.region_id
	var coastal_hex: Vector2i = pair.coastal
	var landlocked_hex: Vector2i = pair.landlocked
	var n: int = pair.coastal_n

	var coastal_city := CityState.new()
	coastal_city.city_id = &"__test_coastal_city__"
	coastal_city.faction_id = &"empire"
	coastal_city.region_id = region_id
	coastal_city.hex_pos = coastal_hex
	coastal_city.level = 2
	coastal_city.population = 150
	_gm.state.cities[coastal_city.city_id] = coastal_city

	var landlocked_city := CityState.new()
	landlocked_city.city_id = &"__test_landlocked_city__"
	landlocked_city.faction_id = &"empire"
	landlocked_city.region_id = region_id
	landlocked_city.hex_pos = landlocked_hex
	landlocked_city.level = 2
	landlocked_city.population = 150
	_gm.state.cities[landlocked_city.city_id] = landlocked_city

	# Confound guard: commander gold bonus is the only OTHER hex_pos-dependent
	# stage in calculate_city_income(). A fresh new_game has no commanders
	# assigned yet, so this should always be 0 -- guard it explicitly so a
	# future change that seeds starting commanders fails loudly here instead
	# of silently corrupting the exact-formula assertions below.
	var cmd_coastal: int = cs._get_commander_gold_bonus(coastal_city)
	var cmd_landlocked: int = cs._get_commander_gold_bonus(landlocked_city)
	_check(cmd_coastal == 0 and cmd_landlocked == 0, "no stray commander gold bonus at either test tile (coastal=%d, landlocked=%d) -- confound guard for the exact-formula check" % [cmd_coastal, cmd_landlocked])

	var income_coastal: Dictionary = cs.calculate_city_income(coastal_city)
	var income_landlocked: Dictionary = cs.calculate_city_income(landlocked_city)

	var food_delta: int = income_coastal.get(Enums.ResourceType.FOOD, 0) - income_landlocked.get(Enums.ResourceType.FOOD, 0)
	var gold_delta: int = income_coastal.get(Enums.ResourceType.GOLD, 0) - income_landlocked.get(Enums.ResourceType.GOLD, 0)

	_check(food_delta == n * 2, "(a) coastal city (N=%d water neighbors) gains exactly +2N=%d food over an identical landlocked control via calculate_city_income(), got delta=%d" % [n, n * 2, food_delta])
	_check(gold_delta == n / 2, "(a) coastal city (N=%d water neighbors) gains exactly +N/2=%d gold over an identical landlocked control via calculate_city_income(), got delta=%d" % [n, n / 2, gold_delta])

	# (c) The landlocked control gains exactly 0 from the new component itself.
	var landlocked_component: Dictionary = cs.apply_coastal_income_bonus(landlocked_city)
	_check(landlocked_component.is_empty(), "(c) landlocked city (0 water neighbors) gains nothing from apply_coastal_income_bonus, got %s" % [landlocked_component])

	_gm.state.cities.erase(coastal_city.city_id)
	_gm.state.cities.erase(landlocked_city.city_id)

# ── (b) PREVIEW honesty: calculate_settlement_income_preview() ─────────────

# Frozen copy of TILE_INCOME/_get_primary_resource as they were BEFORE this
# task (no WATER entries) -- used only to build the legacy-behavior oracle
# below, never touched by the production fix.
const _LEGACY_TILE_INCOME := {
	Enums.TerrainType.PLAINS:    {0: 2, 3: 3, 5: 0},
	Enums.TerrainType.FOREST:    {0: 1, 3: 1, 5: 3},
	Enums.TerrainType.MOUNTAINS: {0: 1, 1: 3, 5: 0},
	Enums.TerrainType.DESERT:    {0: 3, 3: 0, 5: 0},
	Enums.TerrainType.SWAMP:     {0: 1, 3: 2, 5: 1},
	Enums.TerrainType.WETLANDS:  {0: 2, 3: 2, 5: 0},
	Enums.TerrainType.TUNDRA:    {0: 1, 3: 1, 1: 1},
	Enums.TerrainType.JUNGLE:    {0: 1, 3: 2, 5: 2},
}

func _legacy_primary_resource(terrain: int) -> int:
	match terrain:
		Enums.TerrainType.PLAINS: return 3
		Enums.TerrainType.FOREST: return 5
		Enums.TerrainType.MOUNTAINS: return 1
		Enums.TerrainType.DESERT: return 0
		Enums.TerrainType.JUNGLE: return 5
		Enums.TerrainType.SWAMP: return 3
		Enums.TerrainType.WETLANDS: return 0
		Enums.TerrainType.TUNDRA: return 1
	return -1

## Frozen re-implementation of calculate_settlement_income_preview() AS IT
## BEHAVED BEFORE this task (water tiles skipped entirely in the adjacency
## loop, no WATER entry anywhere). Used as an oracle for "what the preview
## used to promise" so the test can prove the fixed version promises MORE,
## without needing to check out the pre-fix commit. Reuses the production
## ring/sphere helpers (_get_hex_ring, is_in_settlement_sphere), which this
## task does not change.
func _legacy_settlement_income_preview(hex_pos: Vector2i) -> Dictionary:
	var cs = _gm.city_system
	var hex_map = _gm.state.hex_map
	var tile = hex_map.get_tile(hex_pos)
	if tile == null:
		return {}
	var income: Dictionary = {}
	var base: Dictionary = _LEGACY_TILE_INCOME.get(tile.terrain, {})
	for res_type in base:
		income[res_type] = base[res_type]
	var center_terrain: int = tile.terrain
	for r in range(1, 4): # SETTLEMENT_SPHERE_RADIUS(3) + 1
		var ring: Array = cs._get_hex_ring(hex_pos, r)
		for ring_coord in ring:
			if not HexHelper.is_valid(ring_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var rtile = hex_map.get_tile(ring_coord)
			if rtile == null or rtile.terrain == Enums.TerrainType.WATER:
				continue
			if cs.is_in_settlement_sphere(ring_coord):
				continue
			var adj_income: Dictionary = _LEGACY_TILE_INCOME.get(rtile.terrain, {})
			if rtile.terrain == center_terrain:
				var primary_res := _legacy_primary_resource(rtile.terrain)
				if primary_res >= 0:
					income[primary_res] = income.get(primary_res, 0) + 1
			else:
				for res_type in adj_income:
					if adj_income[res_type] > 0:
						income[res_type] = income.get(res_type, 0) + max(1, adj_income[res_type] / 3)
	return income

## Counts ONLY the immediate ring-1 neighbors of hex_pos that are WATER --
## via HexHelper.get_neighbors() + a direct hex_map.get_tile() lookup (the
## exact same independent math _count_water_neighbors() above already uses),
## NOT the production ring/sphere helpers (_get_hex_ring, is_in_settlement_
## sphere). This is deliberately narrower than the preview's full 3-ring
## adjacency loop: apply_coastal_income_bonus() -- the real formula this
## mirrors -- only ever looks at ring-1 (HexHelper.get_neighbors), so ring-2/3
## water tiles are NOT part of the count a correct preview should honor.
func _count_preview_water_neighbors(hex_pos: Vector2i) -> int:
	return _count_water_neighbors(hex_pos)

func _run_preview_tests() -> void:
	var cs = _gm.city_system
	var hex_map = _gm.state.hex_map

	var coastal_hex := _find_tile_by_water_neighbors(2, true)
	if coastal_hex == Vector2i(-1, -1):
		_check(false, "found a land tile with >= 2 water neighbors for the preview test")
		return

	var new_income: Dictionary = cs.calculate_settlement_income_preview(coastal_hex)
	var legacy_income: Dictionary = _legacy_settlement_income_preview(coastal_hex)

	var new_food: int = new_income.get(Enums.ResourceType.FOOD, 0)
	var legacy_food: int = legacy_income.get(Enums.ResourceType.FOOD, 0)
	_check(new_food > legacy_food, "(b) coastal tile's settlement preview FOOD (%d) exceeds its pre-fix value (%d) -- water neighbors now contribute via the new TILE_INCOME entry + un-skipped adjacency" % [new_food, legacy_food])

	var new_total := 0
	for r in new_income:
		new_total += new_income[r]
	var legacy_total := 0
	for r in legacy_income:
		legacy_total += legacy_income[r]
	_check(new_total > legacy_total, "(b) coastal tile's total settlement preview income (%d) exceeds its pre-fix total (%d)" % [new_total, legacy_total])

	# (d) Water composition honesty: the legacy oracle skips water entirely
	# (contributes exactly 0) at every ring, and current production also
	# skips ring-2/3 water entirely -- so new-vs-legacy isolates precisely
	# the RING-1-ONLY water special-case's contribution. It must equal the
	# REAL apply_coastal_income_bonus formula (+2 food per ring-1 water
	# neighbor, +1 gold per 2 ring-1 water neighbors) for N = ring-1 water
	# neighbors ONLY, not the old generic max(1, adj_income[res]/3)
	# approximation (~+1 food/+1 gold per neighbor) and not a count that
	# includes ring-2/3 water (which contributes nothing, on either side).
	var water_n := _count_preview_water_neighbors(coastal_hex)
	_check(water_n > 0, "(d) test fixture has at least one ring-1 water neighbor counted independently of the preview's adjacency loop")
	var water_food_delta: int = new_food - legacy_food
	var new_gold: int = new_income.get(Enums.ResourceType.GOLD, 0)
	var legacy_gold: int = legacy_income.get(Enums.ResourceType.GOLD, 0)
	var water_gold_delta: int = new_gold - legacy_gold
	_check(water_food_delta == water_n * 2, "(d) water's FOOD contribution to the preview (%d) equals the real formula's +2/neighbor for N=%d ring-1 water neighbors (expected %d)" % [water_food_delta, water_n, water_n * 2])
	_check(water_gold_delta == water_n / 2, "(d) water's GOLD contribution to the preview (%d) equals the real formula's +1-per-2-neighbors for N=%d ring-1 water neighbors (expected %d)" % [water_gold_delta, water_n, water_n / 2])

	# Regression guard (unrelated to the honesty fix): WATER must still never
	# be a foundable tile itself.
	var region_id: StringName = hex_map.get_tile(coastal_hex).region_id
	if region_id != &"":
		var valid_tiles: Array = cs.get_valid_settlement_tiles(&"empire", region_id)
		var water_found := false
		for t in valid_tiles:
			var t_tile = hex_map.get_tile(t)
			if t_tile != null and t_tile.terrain == Enums.TerrainType.WATER:
				water_found = true
				break
		_check(not water_found, "get_valid_settlement_tiles never returns a WATER tile as foundable")

# ── Fix round 1: exact preview/real coastal parity ──────────────────────────

## THE cross-check the whole deliverable is about: the settlement preview's
## water contribution (isolated via the same new-vs-legacy delta as (d) above)
## must equal calculate_city_income()'s REAL water contribution for a city
## standing on that exact hex -- apply_coastal_income_bonus()'s own returned
## dict, used here as ground truth (not a re-derived formula), across
## several distinct coastal candidates so this isn't a single-tile fluke.
func _run_preview_real_parity_tests() -> void:
	var cs = _gm.city_system
	var hex_map = _gm.state.hex_map
	var checked := 0
	for coord in hex_map.tiles:
		if checked >= 3:
			break
		var tile = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if _count_water_neighbors(coord) <= 0:
			continue
		checked += 1

		# Ground truth: a real city standing on this exact hex.
		var synth := CityState.new()
		synth.city_id = &"__test_parity_city__"
		synth.hex_pos = coord
		var real_bonus: Dictionary = cs.apply_coastal_income_bonus(synth)
		var real_food: int = real_bonus.get(Enums.ResourceType.FOOD, 0)
		var real_gold: int = real_bonus.get(Enums.ResourceType.GOLD, 0)

		var new_income: Dictionary = cs.calculate_settlement_income_preview(coord)
		var legacy_income: Dictionary = _legacy_settlement_income_preview(coord)
		var preview_food_delta: int = new_income.get(Enums.ResourceType.FOOD, 0) - legacy_income.get(Enums.ResourceType.FOOD, 0)
		var preview_gold_delta: int = new_income.get(Enums.ResourceType.GOLD, 0) - legacy_income.get(Enums.ResourceType.GOLD, 0)

		_check(preview_food_delta == real_food, "(f) preview water FOOD contribution at %s (%d) matches apply_coastal_income_bonus's real ground truth (%d)" % [coord, preview_food_delta, real_food])
		_check(preview_gold_delta == real_gold, "(f) preview water GOLD contribution at %s (%d) matches apply_coastal_income_bonus's real ground truth (%d)" % [coord, preview_gold_delta, real_gold])

	_check(checked >= 3, "(f) found at least 3 coastal candidate tiles on the seed-0 map for the preview/real parity cross-check (found %d)" % checked)

# ── Deliverable 2 (deferred from Task A): "Coastal waters" breakdown row ───

## The income-breakdown tooltip (campaign_hud._calculate_income_breakdown)
## folds calculate_city_income()'s coastal contribution back out of the
## per-city "cities" bucket into its own named "Coastal waters" modifier row
## (see test_income_breakdown_equivalence.gd for the parity guarantee that
## row doesn't change the net total). This proves the row actually shows up
## for a coastal city, using the same direct hud._calculate_income_breakdown()
## access pattern test_income_breakdown_equivalence.gd relies on.
func _run_coastal_breakdown_label_test() -> void:
	_gm.new_game(&"empire", false, 0)
	var fs: FactionState = _gm.state.faction_states[_gm.state.player_faction_id]
	if fs.owned_cities.is_empty():
		_check(false, "(e) player has at least one owned city for the coastal-waters breakdown-label test")
		return

	var coastal_hex := _find_tile_by_water_neighbors(1, true)
	if coastal_hex == Vector2i(-1, -1):
		_check(false, "(e) found a land tile with >= 1 water neighbor for the coastal-waters breakdown-label test")
		return

	# Relocate the player's first owned city onto the coastal tile just long
	# enough to read the breakdown -- apply_coastal_income_bonus() reads
	# city.hex_pos directly (see city_system.gd), so this is enough to give
	# the city a non-zero coastal contribution without disturbing anything
	# else new_game set up (region_id, buildings, population, ...).
	var city_id: StringName = fs.owned_cities[0]
	var city: CityState = _gm.state.cities[city_id]
	var original_hex: Vector2i = city.hex_pos
	city.hex_pos = coastal_hex

	var hud = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()
	var breakdown: Dictionary = hud._calculate_income_breakdown(Enums.ResourceType.FOOD)
	hud.free()

	city.hex_pos = original_hex

	var found_label := false
	for mod in breakdown.modifiers:
		if mod.label == "Coastal waters":
			found_label = true
			break
	_check(found_label, "(e) FOOD income breakdown includes a 'Coastal waters' row for a coastal city (modifiers=%s)" % [breakdown.modifiers])

	_gm.new_game(&"empire", false, 0) # leave shared GameManager state clean

# ── Task B: BountySystem.claimable_income_at() ──────────────────────────────

## Scans the seed-0 map for a bounty type WITH an `income` entry that would
## actually be self-claimed by a settlement standing exactly on its hex --
## same "distance 0 beats any existing claimant" trick test_bounty_system.gd
## already relies on for bounties_claimable_at (a claimant, if any, is at
## distance 1-2 since bounty placement forbids being ON a major city's own
## tile). Returns {} (Vector2i(-9999,-9999), &"") if no such tile exists.
func _find_self_claiming_income_bounty() -> Dictionary:
	var hex_map = _gm.state.hex_map
	for coord in hex_map.tiles:
		var tile = hex_map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		var def: Dictionary = BountySystem.BOUNTY_TYPES.get(tile.bounty_id, {})
		if def.get("income", {}).is_empty():
			continue # need an income-bearing type for a meaningful assertion
		# Probe with the fog gate open just long enough to check claim
		# eligibility via the EXISTING production query (not the function
		# under test) -- this is only locating a valid fixture, not asserting.
		_gm.explored_tiles[coord] = true
		var claimable: Array = BountySystem.bounties_claimable_at(coord)
		_gm.explored_tiles.erase(coord)
		for entry in claimable:
			if entry.hex == coord:
				return {hex = coord, type_id = tile.bounty_id}
	return {}

## Finds a land hex with no bounty anywhere within CLAIM_RADIUS+1 (the full
## scan window claimable_income_at/bounties_claimable_at use) -- a "bare"
## site with zero claimable income.
func _find_bare_hex() -> Vector2i:
	var hex_map = _gm.state.hex_map
	for coord in hex_map.tiles:
		var tile = hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		var any_nearby := false
		for dx in range(-BountySystem.CLAIM_RADIUS - 1, BountySystem.CLAIM_RADIUS + 2):
			for dy in range(-BountySystem.CLAIM_RADIUS - 1, BountySystem.CLAIM_RADIUS + 2):
				var h := Vector2i(coord.x + dx, coord.y + dy)
				if HexHelper.hex_distance(coord, h) > BountySystem.CLAIM_RADIUS:
					continue
				var t = hex_map.get_tile(h)
				if t and t.bounty_id != &"":
					any_nearby = true
					break
			if any_nearby:
				break
		if not any_nearby:
			return coord
	return Vector2i(-1, -1)

func _run_bounty_income_tests() -> void:
	_gm.new_game(&"empire", false, 0)
	var hex_map = _gm.state.hex_map

	var fixture := _find_self_claiming_income_bounty()
	_check(not fixture.is_empty(), "found a real seed-0 income-bearing bounty that self-claims standing on its own hex")
	if fixture.is_empty():
		return
	var bounty_hex: Vector2i = fixture.hex
	var bounty_type: StringName = fixture.type_id

	# Expected income derived directly from BOUNTY_TYPES -- NOT via the
	# function under test, so this isn't a tautology.
	var expected: Dictionary = {}
	var def: Dictionary = BountySystem.BOUNTY_TYPES.get(bounty_type, {})
	for res_type in def.get("income", {}):
		expected[res_type] = def.income[res_type]

	# RED/GREEN case 1: default call is fog-gated, same as bounties_claimable_at.
	# The tile starts unexplored (a fresh new_game only marks capital surroundings).
	_check(not _gm.explored_tiles.has(bounty_hex), "test setup: %s's hex starts unexplored" % bounty_type)
	var fogged: Dictionary = BountySystem.claimable_income_at(hex_map, bounty_hex)
	_check(fogged.is_empty(), "claimable_income_at is fog-gated by default on an unexplored bounty (got %s)" % [fogged])

	# ignore_fog=true is the AI site-scorer's path -- must see the bounty
	# regardless of the human player's exploration.
	var unfogged: Dictionary = BountySystem.claimable_income_at(hex_map, bounty_hex, true)
	_check(unfogged == expected, "claimable_income_at(ignore_fog=true) returns %s's income %s regardless of player fog (got %s)" % [bounty_type, expected, unfogged])

	# Once explored, the default (fog-gated) call matches too.
	_gm.explored_tiles[bounty_hex] = true
	var got: Dictionary = BountySystem.claimable_income_at(hex_map, bounty_hex)
	_check(got == expected, "claimable_income_at returns %s's income %s once its hex is explored (got %s)" % [bounty_type, expected, got])
	_gm.explored_tiles.erase(bounty_hex)

	# Bare hex (no bounty within CLAIM_RADIUS) -> {} either way.
	var bare := _find_bare_hex()
	_check(bare != Vector2i(-1, -1), "found a bare hex with no bounty within CLAIM_RADIUS")
	if bare != Vector2i(-1, -1):
		var bare_fogged: Dictionary = BountySystem.claimable_income_at(hex_map, bare)
		_check(bare_fogged.is_empty(), "claimable_income_at returns {} on a bare hex (got %s)" % [bare_fogged])
		var bare_unfogged: Dictionary = BountySystem.claimable_income_at(hex_map, bare, true)
		_check(bare_unfogged.is_empty(), "claimable_income_at(ignore_fog=true) also returns {} on a bare hex (got %s)" % [bare_unfogged])

	_gm.new_game(&"empire", false, 0) # leave shared GameManager state clean

# ── Task B review follow-up: claimable_income_at's EXCLUSION branch ────────
# (a bounty already claimed by a closer-or-equal-distance existing city must
# NOT also feed a farther candidate's income -- the double-count guard).

## Finds a real seed-0 income-bearing bounty with NO current claimant (no
## city, major or independent, sits within CLAIM_RADIUS of it yet) -- so
## adding exactly one synthetic city near it deterministically becomes its
## sole/closest claimant, independent of any tie-break rule.
func _find_unclaimed_income_bounty() -> Dictionary:
	var hex_map = _gm.state.hex_map
	for coord in hex_map.tiles:
		var tile = hex_map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		var def: Dictionary = BountySystem.BOUNTY_TYPES.get(tile.bounty_id, {})
		if def.get("income", {}).is_empty():
			continue
		if BountySystem.claimant_for(coord) != &"":
			continue # already claimed -- not the "starts unclaimed" fixture we need
		return {hex = coord, type_id = tile.bounty_id}
	return {}

func _run_bounty_claim_exclusion_tests() -> void:
	_gm.new_game(&"empire", false, 0)
	var hex_map = _gm.state.hex_map

	var fixture := _find_unclaimed_income_bounty()
	_check(not fixture.is_empty(), "found a real seed-0 income-bearing bounty with no current claimant")
	if fixture.is_empty():
		return
	var b_hex: Vector2i = fixture.hex
	var b_type: StringName = fixture.type_id
	var b_def: Dictionary = BountySystem.BOUNTY_TYPES[b_type]
	var b_res: int = b_def.income.keys()[0]
	var b_amount: int = b_def.income[b_res]

	# A distance-1 neighbor of B to host the synthetic claimant city (1) --
	# CLAIM_RADIUS is 2, so this leaves room for a distance-2 candidate (2)
	# still inside radius, and the bounty's own distance-0 hex (3) as the
	# closer-candidate site.
	var c1_hex := Vector2i(-9999, -9999)
	for n in HexHelper.get_neighbors(b_hex):
		if HexHelper.hex_distance(b_hex, n) == 1:
			c1_hex = n
			break
	_check(c1_hex != Vector2i(-9999, -9999), "found a distance-1 neighbor hex for the synthetic claimant city")
	if c1_hex == Vector2i(-9999, -9999):
		return

	# A distance-2 hex from B (any tile qualifies -- claimable_income_at
	# doesn't care about terrain/foundability, only distance).
	var far_candidate := Vector2i(-9999, -9999)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var h := Vector2i(b_hex.x + dx, b_hex.y + dy)
			if HexHelper.hex_distance(b_hex, h) == 2:
				far_candidate = h
				break
		if far_candidate != Vector2i(-9999, -9999):
			break
	_check(far_candidate != Vector2i(-9999, -9999), "found a distance-2 candidate hex from B")
	if far_candidate == Vector2i(-9999, -9999):
		return
	var near_candidate := b_hex # distance 0 from itself

	# BEFORE any claimant exists: B is unclaimed, so an unclaimed bounty is
	# includable from ANY hex within CLAIM_RADIUS -- both sites see it.
	# (ignore_fog=true throughout: this test is about the claim-distance
	# exclusion branch, not the fog gate, which is covered above.)
	var far_before: Dictionary = BountySystem.claimable_income_at(hex_map, far_candidate, true)
	var near_before: Dictionary = BountySystem.claimable_income_at(hex_map, near_candidate, true)
	_check(far_before.get(b_res, 0) >= b_amount, "setup: unclaimed B contributes to the distance-2 site before any claimant exists (got %d)" % far_before.get(b_res, 0))
	_check(near_before.get(b_res, 0) >= b_amount, "setup: unclaimed B contributes to the distance-0 site before any claimant exists (got %d)" % near_before.get(b_res, 0))

	# 1) Place synthetic city C1 at distance 1 -- the sole city within
	# CLAIM_RADIUS (B started unclaimed), so it deterministically claims B.
	var c1 := CityState.new()
	c1.city_id = &"__test_claimant_city__"
	c1.faction_id = &"empire"
	c1.hex_pos = c1_hex
	_gm.state.cities[c1.city_id] = c1
	_check(BountySystem.claimant_for(b_hex) == c1.city_id, "test setup: synthetic city becomes B's claimant at distance 1")

	var far_after: Dictionary = BountySystem.claimable_income_at(hex_map, far_candidate, true)
	var near_after: Dictionary = BountySystem.claimable_income_at(hex_map, near_candidate, true)

	# 2) THE GAP: a farther candidate (d=2 > claimant's d=1) must LOSE B's
	# income once a closer claimant exists -- no double-counting a bounty
	# that's already spoken for by someone nearer. Exact delta (not just
	# "empty"), so this is immune to any OTHER real bounty also in range of
	# far_candidate.
	_check(far_before.get(b_res, 0) - far_after.get(b_res, 0) == b_amount, "farther candidate (d=2) loses exactly B's +%d once a closer (d=1) claimant exists (before=%d, after=%d)" % [b_amount, far_before.get(b_res, 0), far_after.get(b_res, 0)])

	# 3) A closer candidate (d=0 < claimant's d=1) still outbids the existing
	# claimant -- matches bounties_claimable_at's "strictly closer wins" rule.
	_check(near_after.get(b_res, 0) == near_before.get(b_res, 0), "closer candidate (d=0) keeps B's income even after a farther (d=1) claimant exists (before=%d, after=%d)" % [near_before.get(b_res, 0), near_after.get(b_res, 0)])

	_gm.state.cities.erase(c1.city_id)
	_gm.new_game(&"empire", false, 0) # leave shared GameManager state clean
