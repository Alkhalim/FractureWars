extends SceneTree
## Tests for tier-2 Special resources (Phase 2, docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_special_resources.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
	var map = _gm.state.hex_map

	# ── Scatter: all 8 types present, 1-3 each, valid terrain, no tile overlap ──
	var counts := {}
	var placed: Array[Vector2i] = []
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.special_id == &"":
			continue
		placed.append(coord)
		counts[tile.special_id] = counts.get(tile.special_id, 0) + 1
		var def: Dictionary = SpecialResourceSystem.SPECIAL_TYPES.get(tile.special_id, {})
		_check(not def.is_empty(), "special %s exists in table" % tile.special_id)
		_check(int(tile.terrain) in def.get("terrains", []), "special %s on allowed terrain (%d)" % [tile.special_id, tile.terrain])
		_check(tile.bounty_id == &"", "no bounty stacked on special tile %s" % coord)
	for type_id in SpecialResourceSystem.SPECIAL_TYPES:
		var c: int = counts.get(type_id, 0)
		_check(c >= 1 and c <= 3, "type %s spawns 1-3 times (got %d)" % [type_id, c])

	# ── Demo map must also guarantee all 8 types ──
	_gm.new_game(&"empire", true)
	var demo_counts := {}
	for coord in _gm.state.hex_map.tiles:
		var t = _gm.state.hex_map.tiles[coord]
		if t.special_id != &"":
			demo_counts[t.special_id] = demo_counts.get(t.special_id, 0) + 1
	for type_id in SpecialResourceSystem.SPECIAL_TYPES:
		_check(demo_counts.get(type_id, 0) >= 1, "demo map spawns type %s" % type_id)
	_gm.new_game(&"empire")

	# ── Determinism ──
	var fp := _fingerprint(map)
	_gm.new_game(&"empire")
	_check(_fingerprint(_gm.state.hex_map) == fp, "special scatter deterministic across new_game")

	# ── Serialization roundtrip + old-save compat ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fp, "special_id survives save/load roundtrip")
	for key in saved:
		saved[key].erase("special_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].special_id != &"":
			any = true
	_check(not any, "old saves without special_id load empty")

	# ── Region/extractor plumbing ──
	_gm.new_game(&"empire")
	var map3 = _gm.state.hex_map
	# Find any special deposit and its region
	var dep_hex := Vector2i(-1, -1)
	for coord in map3.tiles:
		if map3.tiles[coord].special_id != &"":
			dep_hex = coord
			break
	var dep_tile = map3.get_tile(dep_hex)
	var dep_type: StringName = dep_tile.special_id
	var dep_region: StringName = dep_tile.region_id
	_check(SpecialResourceSystem.special_in_region(dep_region) == dep_type, "special_in_region finds the deposit")
	_check(not SpecialResourceSystem.region_has_extractor(dep_region), "no extractor at game start")

	# Craft: give the player a city in that region with the extractor built
	var pcity: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			pcity = _gm.state.cities[cid]
			break
	var old_region := pcity.region_id
	pcity.region_id = dep_region
	var extractor_id: StringName = SpecialResourceSystem.SPECIAL_TYPES[dep_type].extractor_id
	pcity.buildings.append(extractor_id)
	# Extractors require capital level 2; meet that gate too.
	pcity.level = maxi(pcity.level, 2)
	# Make empire the region owner: set all region tiles' owner
	for rc in map3.get_region_tiles(dep_region):
		map3.get_tile(rc).owner_faction = &"empire"
	map3._region_owner_cache.clear()
	# Raw tile-ownership writes bypass the normal conquest path, which is what
	# keeps FactionState.owned_regions in sync; mirror that bookkeeping here.
	var pfs: FactionState = _gm.state.faction_states[&"empire"]
	if dep_region not in pfs.owned_regions:
		pfs.owned_regions.append(dep_region)
	_check(SpecialResourceSystem.region_has_extractor(dep_region), "extractor detected in region city")
	_check(dep_type in SpecialResourceSystem.extracted_specials_of_faction(&"empire"), "faction extracts the special")
	_check(SpecialResourceSystem.has_modifier(&"empire", dep_type), "has_modifier true when extracted")
	var base_strength: float = SpecialResourceSystem.SPECIAL_TYPES[dep_type].strength
	var expect := base_strength * 2.0 if &"empire" in SpecialResourceSystem.SPECIAL_TYPES[dep_type].affinity else base_strength
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", dep_type), expect), "modifier_strength respects affinity doubling")
	_check(SpecialResourceSystem.modifier_strength(&"skulloath", dep_type) == 0.0, "no modifier without extraction")
	# Extractor gating: available only in the deposit's region
	var avail: Array[BuildingData] = _gm.city_system.get_available_buildings(pcity)
	var found_extractor := false
	for b in avail:
		if b.id == extractor_id:
			found_extractor = true
	# Already built -> not offered again; remove and re-check availability
	pcity.buildings.erase(extractor_id)
	avail = _gm.city_system.get_available_buildings(pcity)
	for b in avail:
		if b.id == extractor_id:
			found_extractor = true
	_check(found_extractor, "extractor offered in deposit region")
	pcity.region_id = old_region
	avail = _gm.city_system.get_available_buildings(pcity)
	var offered_outside := false
	for b in avail:
		if b.id == extractor_id:
			offered_outside = true
	_check(not offered_outside, "extractor NOT offered outside deposit region")
	pcity.region_id = dep_region
	pcity.buildings.append(extractor_id)

	# ── Economy hooks: craft a sunstone+heartwood extraction for empire ──
	# Reuse dep_region ownership; overwrite the deposit type per check.
	dep_tile.special_id = &"sunstone"
	pcity.buildings.erase(extractor_id)
	pcity.buildings.append(&"extractor_sunstone")
	var mod_sun := SpecialResourceSystem.modifier_strength(&"empire", &"sunstone")
	_check(is_equal_approx(mod_sun, 0.05), "sunstone modifier 5% for non-affinity empire")
	var inc_before: Dictionary = _gm.city_system.calculate_city_income(pcity)
	pcity.buildings.erase(&"extractor_sunstone")
	var inc_no: Dictionary = _gm.city_system.calculate_city_income(pcity)
	# With a cultural building present, income with modifier >= income without
	# (exact delta depends on the city's cultural buildings; assert monotonicity)
	_check(inc_before.get(0, 0) >= inc_no.get(0, 0), "sunstone never reduces gold income")
	pcity.buildings.append(&"extractor_sunstone")

	# Moonsilver heavy discount via recruit path
	dep_tile.special_id = &"moonsilver"
	pcity.buildings.erase(&"extractor_sunstone")
	pcity.buildings.append(&"extractor_moonsilver")
	var heavy_ud := UnitData.new()
	heavy_ud.tags = ["infantry", "heavy"]
	var light_ud := UnitData.new()
	light_ud.tags = ["infantry", "light"]
	_check(SpecialResourceSystem.recruit_discount_for(&"empire", heavy_ud) == 10, "moonsilver discounts heavy 10%")
	_check(SpecialResourceSystem.recruit_discount_for(&"empire", light_ud) == 0, "no discount for non-heavy")

	# Shardglass arcane research speed: bonus function query
	dep_tile.special_id = &"shardglass"
	pcity.buildings.erase(&"extractor_moonsilver")
	pcity.buildings.append(&"extractor_shardglass")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"shardglass"), 0.10), "shardglass 10% for empire")
	# restore
	dep_tile.special_id = dep_type
	pcity.buildings.erase(&"extractor_shardglass")

	# ── Stormcrystal movement + saffron trade hooks (query-level) ──
	dep_tile.special_id = &"stormcrystal"
	pcity.buildings.append(&"extractor_stormcrystal")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"stormcrystal"), 0.05), "stormcrystal 5%")
	dep_tile.special_id = &"saffron_reeds"
	pcity.buildings.erase(&"extractor_stormcrystal")
	pcity.buildings.append(&"extractor_saffron")
	_check(is_equal_approx(SpecialResourceSystem.modifier_strength(&"empire", &"saffron_reeds"), 0.30), "saffron 15% doubled for empire affinity")
	pcity.buildings.erase(&"extractor_saffron")
	dep_tile.special_id = dep_type
	# Deepiron inert at fresh state (battle-determinism guard)
	_gm.new_game(&"empire")
	for f_id in _gm.state.faction_states:
		_check(SpecialResourceSystem.extracted_specials_of_faction(f_id).is_empty(), "fresh game: no faction extracts anything (%s)" % f_id)

	# ── Saffron trade split: receiver banks inflated gold, giver pays base ──
	_gm.new_game(&"empire")
	var map5 = _gm.state.hex_map
	var sdep := Vector2i(-1, -1)
	for coord in map5.tiles:
		if map5.tiles[coord].special_id != &"":
			sdep = coord
			break
	var stile = map5.get_tile(sdep)
	stile.special_id = &"saffron_reeds"
	var scity: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			scity = _gm.state.cities[cid]
			break
	scity.region_id = stile.region_id
	scity.buildings.append(&"extractor_saffron")
	for rc in map5.get_region_tiles(stile.region_id):
		map5.get_tile(rc).owner_faction = &"empire"
	map5._region_owner_cache.clear()
	var sfs: FactionState = _gm.state.faction_states[&"empire"]
	if not (stile.region_id in sfs.owned_regions):
		sfs.owned_regions.append(stile.region_id)
	# empire (faction_a) gives food, receives 20 gold from gladehost
	var t := TreatyInstance.new()
	t.treaty_id = &"test_saffron_trade"
	t.treaty_type = Enums.TreatyType.TRADE_DEAL
	t.faction_a = &"empire"
	t.faction_b = &"gladehost"
	t.turns_remaining = 3
	t.terms = {give_resource = 3, give_amount = 10, receive_resource = 0, receive_amount = 20}
	_gm.state.diplomacy_state.treaties[t.treaty_id] = t
	var gfs2: FactionState = _gm.state.faction_states[&"gladehost"]
	var e_gold2: int = sfs.resources.get(0, 0)
	var g_gold2: int = gfs2.resources.get(0, 0)
	_gm.diplomacy_system._execute_trade(t)
	var e_gained: int = sfs.resources.get(0, 0) - e_gold2
	var g_paid: int = g_gold2 - gfs2.resources.get(0, 0)
	_check(g_paid == 20, "giver pays base 20 gold (paid %d)" % g_paid)
	_check(e_gained > 20, "saffron receiver banks inflated gold (got %d)" % e_gained)
	_gm.state.diplomacy_state.treaties.erase(t.treaty_id)

	# ── Resource lease lifecycle ──
	_gm.new_game(&"empire")
	var map4 = _gm.state.hex_map
	var dhex := Vector2i(-1, -1)
	for coord in map4.tiles:
		if map4.tiles[coord].special_id != &"":
			dhex = coord
			break
	var dtile = map4.get_tile(dhex)
	var dtype: StringName = dtile.special_id
	var dregion: StringName = dtile.region_id
	var owner_city: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == &"empire":
			owner_city = _gm.state.cities[cid]
			break
	owner_city.region_id = dregion
	owner_city.buildings.append(SpecialResourceSystem.SPECIAL_TYPES[dtype].extractor_id)
	for rc in map4.get_region_tiles(dregion):
		map4.get_tile(rc).owner_faction = &"empire"
	map4._region_owner_cache.clear()
	var efs: FactionState = _gm.state.faction_states[&"empire"]
	if not (dregion in efs.owned_regions):
		efs.owned_regions.append(dregion)

	var res: Dictionary = _gm.diplomacy_system.propose_resource_lease(&"empire", &"gladehost", dtype, 10, 8)
	_check(res.accepted, "AI lessee accepts a cheap lease of a useful special (reason: %s)" % res.get("reason", ""))
	_check(SpecialResourceSystem.has_modifier(&"gladehost", dtype), "lease grants the modifier to the lessee")
	_check(SpecialResourceSystem.lease_for_special(&"empire", dtype) != null, "lease registered for exclusivity")
	var res2: Dictionary = _gm.diplomacy_system.propose_resource_lease(&"empire", &"moonspear", dtype, 10, 8)
	_check(not res2.accepted, "second lease of same special rejected (exclusive)")

	# Tick: lessee pays owner gold_per_turn
	var gl_fs: FactionState = _gm.state.faction_states[&"gladehost"]
	var e_gold: int = efs.resources.get(0, 0)
	var g_gold: int = gl_fs.resources.get(0, 0)
	_gm.diplomacy_system.process_treaties(&"empire")
	_check(efs.resources.get(0, 0) == e_gold + 10, "owner received lease payment")
	_check(gl_fs.resources.get(0, 0) == g_gold - 10, "lessee paid lease payment")

	# War cancels the lease
	_gm.diplomacy_system.declare_war(&"empire", &"gladehost")
	_check(not SpecialResourceSystem.has_modifier(&"gladehost", dtype), "war cancels the lease")

	if _fails == 0:
		print("SPECIALS TEST PASSED")
		quit(0)
	else:
		print("SPECIALS TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].special_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].special_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
