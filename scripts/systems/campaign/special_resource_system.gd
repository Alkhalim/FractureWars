class_name SpecialResourceSystem
extends RefCounted
## Tier-2 "Special" resources (Phase 2 of docs/special_resources_design.md).
## All static. 8 rare faction-affinity deposits owned via their REGION and
## activated by a universal Extractor building. Yields ride the extractor's
## normal income_bonus; this class owns the table, the scatter pass, and the
## modifier/lease state queries used by the percentage hooks.

const MIN_PER_TYPE := 1
const MAX_PER_TYPE := 3
const MIN_SPACING := 8   # hexes between any two special deposits

## strength = the identity modifier's base magnitude (doubled for affinity).
## Interpretation is per-type at the hook site (pct fraction or flat pct).
const SPECIAL_TYPES := {
	&"moonsilver": {name = "Moonsilver", terrains = [6, 2], strength = 10.0, affinity = [&"moonspear"], extractor_id = &"extractor_moonsilver", modifier_text = "-10% recruit cost for heavy units"},
	&"sunstone": {name = "Sunstone", terrains = [3], strength = 0.05, affinity = [&"sunblessed"], extractor_id = &"extractor_sunstone", modifier_text = "+5% cultural building income"},
	&"deepiron": {name = "Deepiron", terrains = [2], strength = 0.05, affinity = [&"cinderguard"], extractor_id = &"extractor_deepiron", modifier_text = "+5% army defense in owned territory"},
	&"heartwood": {name = "Heartwood", terrains = [1, 9], strength = 0.05, affinity = [&"gladehost"], extractor_id = &"extractor_heartwood", modifier_text = "+5% food income"},
	&"shardglass": {name = "Shardglass", terrains = [7], strength = 0.10, affinity = [&"ivoryscar", &"shardhorde"], extractor_id = &"extractor_shardglass", modifier_text = "+10% arcane research speed"},
	&"saffron_reeds": {name = "Saffron Reeds", terrains = [0, 5], strength = 0.15, affinity = [&"empire"], extractor_id = &"extractor_saffron", modifier_text = "+15% gold from trade deals"},
	&"bloodsalt": {name = "Bloodsalt", terrains = [4, 5], strength = 0.25, affinity = [&"skulloath", &"tainted_jade"], extractor_id = &"extractor_bloodsalt", modifier_text = "+25% captive conversion"},
	&"stormcrystal": {name = "Stormcrystal", terrains = [2], strength = 0.05, affinity = [&"thunderswarm"], extractor_id = &"extractor_stormcrystal", modifier_text = "+5% army movement"},
}

static func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

## Map-gen pass. Runs BEFORE BountySystem.scatter_bounties (rare deposits get
## first pick; bounties skip occupied tiles). All 8 types spawn 1-3 deposits.
## salt: per-campaign map seed (Task 1B). 0 == identity fold, reproducing the
## legacy roster/placement exactly.
static func scatter_specials(map: HexMapData, salt: int = 0) -> void:
	var coords: Array = map.tiles.keys()
	coords.sort()
	var placed: Array[Vector2i] = []
	var type_ids: Array = SPECIAL_TYPES.keys()
	# Pass 1: one guaranteed deposit per type — walk tiles with a per-type
	# hash offset so types land in different map areas.
	for t_idx in type_ids.size():
		var type_id: StringName = type_ids[t_idx]
		var def: Dictionary = SPECIAL_TYPES[type_id]
		var start := _hash(t_idx * 101 + 13 + salt * 7919, 4242) % coords.size()
		var placed_one := false
		for spacing in [MIN_SPACING, 6, 4, 2]:
			for k in coords.size():
				var coord: Vector2i = coords[(start + k) % coords.size()]
				if _try_place(map, coord, type_id, def, placed, spacing):
					placed_one = true
					break
			if placed_one:
				break
	# Pass 2: hash-gated extra deposits up to MAX_PER_TYPE.
	var counts := {}
	for p in placed:
		var tid: StringName = map.tiles[p].special_id
		counts[tid] = counts.get(tid, 0) + 1
	for coord in coords:
		var h := _hash(coord.x + 7 + salt * 7919, coord.y - 7)
		if h % 37 != 0:
			continue
		var type_id: StringName = type_ids[(h / 37) % type_ids.size()]
		if counts.get(type_id, 0) >= MAX_PER_TYPE:
			continue
		if _try_place(map, coord, type_id, SPECIAL_TYPES[type_id], placed):
			counts[type_id] = counts.get(type_id, 0) + 1

static func deposits_in_region(region_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map = GameManager.state.hex_map
	if map == null or region_id == &"":
		return result
	for coord in map.get_region_tiles(region_id):
		var tile = map.get_tile(coord)
		if tile and tile.special_id != &"":
			result.append(coord)
	return result

static func special_in_region(region_id: StringName) -> StringName:
	var deps := deposits_in_region(region_id)
	if deps.is_empty():
		return &""
	return GameManager.state.hex_map.get_tile(deps[0]).special_id

static func region_has_extractor(region_id: StringName) -> bool:
	var special: StringName = special_in_region(region_id)
	if special == &"":
		return false
	var extractor_id: StringName = SPECIAL_TYPES[special].extractor_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.region_id == region_id and city.buildings.has(extractor_id):
			return true
	return false

## One entry per extracted deposit-region; duplicates count (flagship effects).
static func extracted_specials_of_faction(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	for region_id in fs.owned_regions:
		var special: StringName = special_in_region(region_id)
		if special != &"" and region_has_extractor(region_id):
			result.append(special)
	return result

static func _lease_grants(faction_id: StringName, special_id: StringName) -> bool:
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_b == faction_id \
				and t.terms.get("special_id", &"") == special_id:
			return true
	return false

## The active lease treaty for a special the owner extracts (or null). Used to
## enforce exclusivity — a deposit can only be leased to one faction at a time.
static func lease_for_special(owner: StringName, special_id: StringName) -> TreatyInstance:
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_a == owner \
				and t.terms.get("special_id", &"") == special_id:
			return t
	return null

## Specials leased INTO faction_id from other factions, for UI display.
## Bounty leases ride the same RESOURCE_LEASE treaty_type with a different
## terms shape ({bounty_hex, bounty_id, gold_per_turn} instead of
## {special_id, gold_per_turn}) -- the terms.has("special_id") check keeps
## those out of this specials-only listing (see leased_in_bounties for the
## bounty-lease equivalent).
static func leased_in_specials(faction_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t_id in GameManager.state.diplomacy_state.treaties:
		var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE and t.faction_b == faction_id \
				and t.terms.has("special_id"):
			result.append({special_id = t.terms.get("special_id", &""), from = t.faction_a, turns_remaining = t.turns_remaining})
	return result

static func has_modifier(faction_id: StringName, special_id: StringName) -> bool:
	if special_id in extracted_specials_of_faction(faction_id):
		return true
	return _lease_grants(faction_id, special_id)

static func modifier_strength(faction_id: StringName, special_id: StringName) -> float:
	if not has_modifier(faction_id, special_id):
		return 0.0
	var def: Dictionary = SPECIAL_TYPES[special_id]
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	return def.strength * 2.0 if parent_fid in def.affinity else def.strength

## Moonsilver: percentage discount for heavy-tagged units (int pct).
static func recruit_discount_for(faction_id: StringName, ud: UnitData) -> int:
	if not ud.tags.has("heavy"):
		return 0
	return int(modifier_strength(faction_id, &"moonsilver"))

static func describe(special_id: StringName) -> String:
	var def: Dictionary = SPECIAL_TYPES.get(special_id, {})
	return def.get("modifier_text", "") if not def.is_empty() else ""

static func _try_place(map: HexMapData, coord: Vector2i, type_id: StringName, def: Dictionary, placed: Array[Vector2i], spacing: int = MIN_SPACING) -> bool:
	var tile: HexMapData.TileState = map.tiles[coord]
	if tile.terrain == Enums.TerrainType.WATER or tile.special_id != &"":
		return false
	if tile.landmark_id != &"":
		return false # landmarks scattered first; one resource per tile
	if tile.region_id == &"":
		return false # deposits must belong to a region (ownership model)
	if not (int(tile.terrain) in def.terrains):
		return false
	for p in placed:
		if HexHelper.hex_distance(coord, p) < spacing:
			return false
	tile.special_id = type_id
	placed.append(coord)
	return true
