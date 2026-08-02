class_name BountySystem
extends RefCounted
## Tier-1 "bounty" resources (docs/special_resources_design.md).
## All static. Owns the bounty table, the deterministic map-gen scatter pass,
## radius-2 claim resolution, and effect queries used by economy hooks + UI.

const CLAIM_RADIUS := 2
const MIN_SPACING := 3      # no two bounties closer than this
const MAX_PER_TYPE := 14
const ROSTER_ROLL_PCT := 66 # ~2/3 of types spawn per map
const DENSITY_DIVISOR := 40 # target ~1 bounty per 40 land tiles (post-rebalance)
const CAPITAL_RING_MIN := 3
const CAPITAL_RING_NEAR := 4
const CAPITAL_RING_FAR := 10

## Effects implemented in Phase 1: income {ResourceType->int},
## loyalty {class->int}, recruit_discount {unit_tag->pct}.
## `deferred` documents the design-doc rule awaiting a Phase 1.5 hook —
## such entries carry a provisional income stand-in so the bounty still matters.
const BOUNTY_TYPES := {
	&"orchards": {name = "Orchards", terrains = [0, 1], income = {3: 6}},
	&"grain_basin": {name = "Grain Basin", terrains = [0, 5], income = {3: 10}},
	&"vineyards": {name = "Vineyards", terrains = [0], income = {0: 5}, loyalty = {peasants = 1, artisans = 1, scholars = 1, nobles = 1}},
	&"honey_apiaries": {name = "Honey Apiaries", terrains = [0, 1], income = {3: 4}, loyalty = {peasants = 1}},
	&"herb_meadows": {name = "Herb Meadows", terrains = [0, 4], income = {3: 4}, deferred = "+25% army healing in this region"},
	&"wild_horses": {name = "Wild Horses", terrains = [0, 6], recruit_discount = {cavalry = 10}},
	&"fisheries": {name = "Fisheries", terrains = [0, 5], coastal = true, income = {3: 8}},
	&"pearl_beds": {name = "Pearl Beds", terrains = [0, 5], coastal = true, income = {0: 6}, deferred = "+20% gift value of gold gifts"},
	&"salt_flats": {name = "Salt Flats", terrains = [3, 5], income = {3: 4, 0: 4}},
	&"marble": {name = "Marble", terrains = [2, 3], income = {0: 6}, deferred = "-15% build cost for cultural buildings"},
	&"granite": {name = "Granite", terrains = [2], income = {1: 4}, deferred = "+20% build speed in region cities"},
	&"basalt_columns": {name = "Basalt Columns", terrains = [2], income = {1: 4}, deferred = "-20% cost for defensive buildings"},
	&"copper_vein": {name = "Copper Vein", terrains = [2, 3], income = {1: 5, 0: 3}},
	&"obsidian_flows": {name = "Obsidian Flows", terrains = [2, 7], income = {1: 4}, deferred = "+1 attack for units recruited here"},
	&"titanstone_quarry": {name = "Titanstone Quarry", terrains = [2], recruit_discount = {construct = 10}},
	&"timber_giants": {name = "Timber Giants", terrains = [1, 9], income = {5: 10}},
	&"amber_groves": {name = "Amber Groves", terrains = [1, 6], income = {0: 7}},
	&"furs": {name = "Furs", terrains = [6, 1], income = {0: 5}, deferred = "-10% army upkeep in tundra"},
	&"crystal_springs": {name = "Crystal Springs", terrains = [6], income = {0: 3}, deferred = "+2 population growth in region cities"},
	&"clay_pits": {name = "Clay Pits", terrains = [5, 0], income = {5: 5}, deferred = "-15% wood component of build costs"},
	&"peat_bogs": {name = "Peat Bogs", terrains = [4, 5], income = {5: 6}, deferred = "-10% building upkeep in region"},
	&"dye_gardens": {name = "Dye Gardens", terrains = [9, 5], coastal = true, income = {0: 8}, deferred = "gold counts toward trade deals only"},
	&"coal_seams": {name = "Coal Seams", terrains = [2, 6], income = {1: 6}},
	&"bone_fields": {name = "Bone Fields", terrains = [3, 7], recruit_discount = {undead = 10}},
	&"bronze_ore": {name = "Bronze Ore", terrains = [2, 3], income = {0: 3, 1: 4}},
}

## Deterministic coordinate hash — same idiom as map_generator.gd (no RNG).
static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass: run AFTER terrain is final (map_generator calls this last).
## salt: per-campaign map seed (Task 1B). 0 == identity fold, reproducing the
## legacy roster/placement exactly.
static func scatter_bounties(map: HexMapData, salt: int = 0) -> void:
	# 1. Roll the roster: ~2/3 of types spawn on any given map
	var selected: Array[StringName] = []
	var idx := 0
	for type_id in BOUNTY_TYPES:
		if _hash(idx * 31 + 7 + salt * 7919, 7777) % 100 < ROSTER_ROLL_PCT:
			selected.append(type_id)
		idx += 1
	if selected.is_empty():
		return
	# 2. Walk tiles in sorted order (deterministic), gate candidates by hash
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	var counts := {}
	for coord in coords:
		var tile: HexMapData.TileState = map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if tile.special_id != &"" or tile.landmark_id != &"":
			continue # specials/landmarks scattered first; one resource per tile
		var h := _hash(coord.x + salt * 7919, coord.y)
		if h % 9 != 0:
			continue # ~11% of land tiles are candidates
		# Spacing vs already-placed bounties
		var too_close := false
		for p in placed:
			if HexHelper.hex_distance(coord, p) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		# Pick the first fitting type, rotating start point by hash
		var start := (h / 9) % selected.size()
		for k in selected.size():
			var type_id: StringName = selected[(start + k) % selected.size()]
			var def: Dictionary = BOUNTY_TYPES[type_id]
			if counts.get(type_id, 0) >= MAX_PER_TYPE:
				continue
			if not (int(tile.terrain) in def.terrains):
				continue
			if def.get("coastal", false) and not _has_water_neighbor(map, coord):
				continue
			tile.bounty_id = type_id
			placed.append(coord)
			counts[type_id] = counts.get(type_id, 0) + 1
			break

static func _has_water_neighbor(map: HexMapData, coord: Vector2i) -> bool:
	for n in HexHelper.get_neighbors(coord):
		var t = map.get_tile(n)
		if t and t.terrain == Enums.TerrainType.WATER:
			return true
	return false

## Radius-limited hex range around `center` (every coord with hex_distance <=
## radius), via the standard cube-coordinate range walk. Used to stamp OUTWARD
## from each city instead of scanning every land tile against every city.
static func _hex_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var c := HexHelper.offset_to_cube(center.x, center.y)
	for dx in range(-radius, radius + 1):
		var lo := maxi(-radius, -dx - radius)
		var hi := mini(radius, -dx + radius)
		for dy in range(lo, hi + 1):
			var dz := -dx - dy
			result.append(HexHelper.cube_to_offset(c + Vector3i(dx, dy, dz)))
	return result

## Precomputes the three tile-keyed validity lookups ONCE per rebalance pass by
## stamping outward FROM EACH CITY (~90 cities x ~19-37 cells each) instead of
## the O(cities) scan per tile that is_valid_bounty_spot does without this.
## Feed the result into is_valid_bounty_spot's `stamps` param for bulk queries
## (see rebalance_for_cities); omit it entirely for one-off single-coord calls.
static func _build_validity_stamps() -> Dictionary:
	var major_blocked := {}
	var near_independent := {}
	var settle_too_close := {}
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == &"independent":
			for h in _hex_range(city.hex_pos, CLAIM_RADIUS):
				near_independent[h] = true
		else:
			for h in _hex_range(city.hex_pos, CLAIM_RADIUS):
				major_blocked[h] = true
		for h in _hex_range(city.hex_pos, 3): # "distance < 4" == radius 3
			settle_too_close[h] = true
	return {major_blocked = major_blocked, near_independent = near_independent, settle_too_close = settle_too_close}

## Placement validity (post-city): never free for majors; claimable by an
## independent town or grabbable by a future settlement.
## `stamps`, if given, must be a Dictionary from _build_validity_stamps() —
## swaps the O(cities) scans below for O(1) lookups. Both paths implement the
## exact same rule (only the lookup mechanism differs), so results are
## identical either way; omit `stamps` for one-off queries (tests, UI).
static func is_valid_bounty_spot(map: HexMapData, coord: Vector2i, stamps: Dictionary = {}) -> bool:
	var tile = map.get_tile(coord)
	if tile == null or tile.terrain == Enums.TerrainType.WATER:
		return false
	if tile.special_id != &"" or tile.landmark_id != &"":
		return false
	var near_independent := false
	if stamps.is_empty():
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			var d := HexHelper.hex_distance(city.hex_pos, coord)
			if d <= CLAIM_RADIUS:
				if city.faction_id == &"independent":
					near_independent = true
				else:
					return false # major (or other) city would auto-claim: forbidden
	else:
		if stamps.major_blocked.has(coord):
			return false # major (or other) city would auto-claim: forbidden
		near_independent = stamps.near_independent.has(coord)
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
			if stamps.is_empty():
				var far_enough := true
				for city_id2 in GameManager.state.cities:
					if HexHelper.hex_distance(GameManager.state.cities[city_id2].hex_pos, t_coord) < 4:
						far_enough = false
						break
				if far_enough:
					return true
			else:
				if not stamps.settle_too_close.has(t_coord):
					return true
	return false

## Post-city rebalance: relocate invalid map-gen bounties, then top up the
## capital rings and the global density target. Deterministic via salt.
## Runs once per new_game, after cities (and landmark-guardian towns) exist.
static func rebalance_for_cities(map: HexMapData, salt: int) -> void:
	var coords: Array = map.tiles.keys()
	coords.sort()
	# Precompute the city-stamped validity lookups ONCE for this whole pass
	# (see _build_validity_stamps) instead of re-scanning every city for every
	# tile below — the two candidate-building loops touch every land tile.
	var stamps := _build_validity_stamps()
	# 1. Strip invalid bounties (map-gen ran before cities existed, so any
	#    deposit that now falls within CLAIM_RADIUS of a major city, or off
	#    the settlement-adjacency rule, gets cleared here). Their type is not
	#    tracked for re-placement — see the topup-loop note below.
	var placed: Array[Vector2i] = []
	for coord in coords:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		if is_valid_bounty_spot(map, coord, stamps):
			placed.append(coord)
		else:
			tile.bounty_id = &""
	# 2. Build the valid-candidate list once (terrain-agnostic; per-type
	#    terrain checked at placement)
	var candidates: Array[Vector2i] = []
	for coord in coords:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"" and is_valid_bounty_spot(map, coord, stamps):
			candidates.append(coord)
	# 3. Top up ring targets + global density via a shared placement helper:
	var counts := {}
	for p in placed:
		var b: StringName = map.tiles[p].bounty_id
		counts[b] = counts.get(b, 0) + 1
	var type_ids: Array = BOUNTY_TYPES.keys()
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
	# `dead` remembers candidates _place_rebalanced already rejected (every
	# terrain-fitting type at that tile is at MAX_PER_TYPE, or no type fits
	# its terrain at all) — counts only grow, so a dead candidate stays dead
	# for the rest of this pass. Without this, the ring search below would
	# keep re-selecting the same nearest-but-unplaceable tile on every one of
	# a capital's remaining ring slots instead of moving on to the next one.
	var dead: Dictionary = {}
	for cap_pos in ring_targets:
		var best := Vector2i(-9999, -9999)
		var best_d := 9999
		for cand in candidates:
			if dead.has(cand):
				continue
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
			# The capital-ring guarantee is a hard settlement-decision invariant;
			# MAX_PER_TYPE is a soft variety cap. A handful of terrains (desert:
			# 3 fitting types; shard wastes: 1) can exhaust their type(s) map-wide
			# before every capital's ring is served, so retry ignoring the cap
			# rather than leave a capital permanently short.
			if not _place_rebalanced(map, best, type_ids, counts, salt, placed):
				_place_rebalanced(map, best, type_ids, counts, salt, placed, true)
			dead[best] = true # never revisit — filled or truly unplaceable either way
	# NOTE: re-placement deliberately ignores the map-gen roster roll — top-up
	# may introduce types the initial roll skipped. That's acceptable (more
	# variety across a rebalanced map) rather than a bug.
	while placed.size() < target:
		var progressed := false
		for cand in candidates:
			if placed.size() >= target:
				break
			if dead.has(cand) or map.tiles[cand].bounty_id != &"":
				continue
			var h := _hash(cand.x + salt * 7919, cand.y + 13)
			if h % 3 != 0:
				continue
			if not _spacing_ok(map, cand, placed):
				continue
			if _place_rebalanced(map, cand, type_ids, counts, salt, placed):
				progressed = true
			else:
				dead[cand] = true
		if not progressed:
			break # candidates exhausted; accept what fits

static func _spacing_ok(map: HexMapData, coord: Vector2i, placed: Array[Vector2i]) -> bool:
	for p in placed:
		if HexHelper.hex_distance(coord, p) < MIN_SPACING:
			return false
	return true

## Places the hash-preferred terrain-fitting type at coord; false if none fits.
## `ignore_cap`: capital-ring fallback only (see call site) — a handful of
## terrains have very few fitting types (desert: 3, shard wastes: 1) and can
## exhaust MAX_PER_TYPE map-wide before every capital's ring guarantee is
## met. When true, and every fitting type is at cap, spreads the unavoidable
## overflow onto whichever fitting type is currently least-over rather than
## dumping it all on the first hash match, so no single type runs away.
static func _place_rebalanced(map: HexMapData, coord: Vector2i, type_ids: Array, counts: Dictionary, salt: int, placed: Array[Vector2i], ignore_cap: bool = false) -> bool:
	var tile = map.get_tile(coord)
	var start := _hash(coord.x + salt * 7919, coord.y) % type_ids.size()
	var fallback_type: StringName = &""
	var fallback_count := 999999
	for k in type_ids.size():
		var type_id: StringName = type_ids[(start + k) % type_ids.size()]
		var def: Dictionary = BOUNTY_TYPES[type_id]
		if not (int(tile.terrain) in def.terrains):
			continue
		if def.get("coastal", false) and not _has_water_neighbor(map, coord):
			continue
		var c: int = counts.get(type_id, 0)
		if c < MAX_PER_TYPE:
			tile.bounty_id = type_id
			counts[type_id] = c + 1
			placed.append(coord)
			return true
		if ignore_cap and c < fallback_count:
			fallback_count = c
			fallback_type = type_id
	if ignore_cap and fallback_type != &"":
		tile.bounty_id = fallback_type
		counts[fallback_type] = fallback_count + 1
		placed.append(coord)
		return true
	return false

## Nearest city within CLAIM_RADIUS claims a bounty; ties break by city_id.
static func claimant_for(bounty_hex: Vector2i) -> StringName:
	var best_id: StringName = &""
	var best_d := 99
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var d := HexHelper.hex_distance(city.hex_pos, bounty_hex)
		if d > CLAIM_RADIUS:
			continue
		if d < best_d or (d == best_d and String(city_id) < String(best_id)):
			best_d = d
			best_id = city_id
	return best_id

static func claimed_bounties_for_city(city: CityState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for dx in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
		for dy in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
			var h := Vector2i(city.hex_pos.x + dx, city.hex_pos.y + dy)
			if HexHelper.hex_distance(city.hex_pos, h) > CLAIM_RADIUS:
				continue
			var tile = map.get_tile(h)
			if tile and tile.bounty_id != &"" and claimant_for(h) == city.city_id:
				result.append(h)
	return result

## For the HUD holdings list: every bounty claimed by any of the faction's cities.
static func bounties_of_faction(faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		for hex in claimed_bounties_for_city(city):
			var tile = map.get_tile(hex)
			result.append({
				id = tile.bounty_id,
				name = BOUNTY_TYPES[tile.bounty_id].name,
				hex = hex,
				city_id = city_id,
			})
	return result

## Bounties a NEW city founded at hex_pos would claim: within CLAIM_RADIUS and
## either unclaimed or strictly closer to hex_pos than to the current claimant.
static func bounties_claimable_at(hex_pos: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map = GameManager.state.hex_map
	if map == null:
		return result
	for dx in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
		for dy in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
			var h := Vector2i(hex_pos.x + dx, hex_pos.y + dy)
			var d := HexHelper.hex_distance(hex_pos, h)
			if d > CLAIM_RADIUS:
				continue
			var tile = map.get_tile(h)
			if tile == null or tile.bounty_id == &"":
				continue
			if not GameManager.explored_tiles.has(h):
				continue
			var current := claimant_for(h)
			if current == &"":
				result.append({id = tile.bounty_id, name = BOUNTY_TYPES[tile.bounty_id].name, hex = h})
			else:
				var cur_city: CityState = GameManager.state.cities.get(current)
				if cur_city and d < HexHelper.hex_distance(cur_city.hex_pos, h):
					result.append({id = tile.bounty_id, name = BOUNTY_TYPES[tile.bounty_id].name, hex = h})
	return result

## Flat resource income the bounties claimable at hex_pos would grant if a
## settlement stood there right now -- an income-only projection of
## bounties_claimable_at, aggregated the same way income_bonus_for_city sums
## an EXISTING city's claims. Used by the settlement preview gradient/panel
## (campaign.gd) and the AI's site-scorer (turn_manager.gd) so an unclaimed
## deposit within CLAIM_RADIUS isn't invisible to either.
##
## `ignore_fog`: bounties_claimable_at gates on GameManager.explored_tiles as
## a player-facing anti-spoiler measure (don't preview a bounty the player
## hasn't scouted yet); this helper mirrors that gate by default for the same
## UI reason. GameManager.explored_tiles is documented elsewhere as
## "player fog only" (turn_manager.gd), so the AI site-scorer passes
## ignore_fog=true -- the AI's own settlement decisions must not be blinded
## by the human player's exploration.
static func claimable_income_at(map: HexMapData, hex_pos: Vector2i, ignore_fog: bool = false) -> Dictionary:
	var total := {}
	for dx in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
		for dy in range(-CLAIM_RADIUS - 1, CLAIM_RADIUS + 2):
			var h := Vector2i(hex_pos.x + dx, hex_pos.y + dy)
			var d := HexHelper.hex_distance(hex_pos, h)
			if d > CLAIM_RADIUS:
				continue
			var tile = map.get_tile(h)
			if tile == null or tile.bounty_id == &"":
				continue
			if not ignore_fog and not GameManager.explored_tiles.has(h):
				continue
			var current := claimant_for(h)
			if current != &"":
				var cur_city: CityState = GameManager.state.cities.get(current)
				if cur_city == null or d >= HexHelper.hex_distance(cur_city.hex_pos, h):
					continue # already claimed by someone at least as close
			var def: Dictionary = BOUNTY_TYPES.get(tile.bounty_id, {})
			for res_type in def.get("income", {}):
				total[res_type] = total.get(res_type, 0) + def.income[res_type]
	return total

const _RES_NAMES := {0: "Gold", 1: "Iron", 2: "Technology", 3: "Food", 4: "Shard Essence", 5: "Wood", 6: "Captives"}

## Human-readable one-line bonus text for tooltips.
static func describe(type_id: StringName) -> String:
	var def: Dictionary = BOUNTY_TYPES.get(type_id, {})
	if def.is_empty():
		return ""
	var parts: PackedStringArray = []
	for res_type in def.get("income", {}):
		parts.append("+%d %s" % [def.income[res_type], _RES_NAMES.get(res_type, "?")])
	for cls in def.get("loyalty", {}):
		parts.append("+%d %s loyalty" % [def.loyalty[cls], String(cls)])
	for tag in def.get("recruit_discount", {}):
		parts.append("-%d%% %s recruit cost" % [def.recruit_discount[tag], String(tag)])
	return ", ".join(parts)

## Flat resource income granted by this city's claimed bounties (ResourceType int -> int).
static func income_bonus_for_city(city: CityState) -> Dictionary:
	var total := {}
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for res_type in def.get("income", {}):
			total[res_type] = total.get(res_type, 0) + def.income[res_type]
	return total

## Per-class loyalty bonus granted by this city's claimed bounties (class String -> int).
static func loyalty_bonus_for_city(city: CityState) -> Dictionary:
	var total := {}
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for cls in def.get("loyalty", {}):
			total[String(cls)] = total.get(String(cls), 0) + def.loyalty[cls]
	return total

## Recruit-cost discount percent for a unit, from this city's claimed bounties whose
## recruit_discount tags match one of the unit's tags.
static func recruit_discount_for(city: CityState, ud: UnitData) -> int:
	var total := 0
	for hex in claimed_bounties_for_city(city):
		var def: Dictionary = BOUNTY_TYPES.get(GameManager.state.hex_map.get_tile(hex).bounty_id, {})
		for tag in def.get("recruit_discount", {}):
			if ud.tags.has(String(tag)):
				total += def.recruit_discount[tag]
	return total
