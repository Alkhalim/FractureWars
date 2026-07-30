extends SceneTree
## Tests for tier-1 bounty resources (docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_bounty_system.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var map = _gm.state.hex_map

	# ── Scatter happened and is sane ──
	var placed: Array[Vector2i] = []
	var counts := {}
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		placed.append(coord)
		counts[tile.bounty_id] = counts.get(tile.bounty_id, 0) + 1
		var def: Dictionary = BountySystem.BOUNTY_TYPES.get(tile.bounty_id, {})
		_check(not def.is_empty(), "placed bounty %s exists in table" % tile.bounty_id)
		_check(int(tile.terrain) in def.get("terrains", []), "bounty %s on allowed terrain (%d)" % [tile.bounty_id, tile.terrain])
	_check(placed.size() >= 10, "at least 10 bounty deposits placed (got %d)" % placed.size())
	# MAX_PER_TYPE is a soft variety cap; the capital-ring guarantee (below)
	# is a hard settlement-decision invariant and wins when they conflict —
	# a few terrains have very few fitting types (desert: 3; shard wastes:
	# only obsidian_flows) and can exhaust those types map-wide before every
	# capital's ring is satisfied. Empirically (20-seed sweep) the resulting
	# overflow tops out around MAX_PER_TYPE+5; double the cap as a generous
	# ceiling that still catches a real runaway-placement regression.
	for t in counts:
		_check(counts[t] <= BountySystem.MAX_PER_TYPE * 2, "type %s stays near MAX_PER_TYPE, allowing bounded capital-ring overflow (got %d)" % [t, counts[t]])
	# Spacing: no two bounties within 3 hexes
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if HexHelper.hex_distance(placed[i], placed[j]) < 3:
				_fails += 1
				print("FAIL: bounties too close: %s %s" % [placed[i], placed[j]])

	# ── Determinism: regenerating the same map yields identical bounties ──
	var fingerprint := _fingerprint(map)
	_gm.new_game(&"empire", false, 0)
	_check(_fingerprint(_gm.state.hex_map) == fingerprint, "scatter is deterministic across new_game")

	# ── Serialization roundtrip preserves bounty_id ──
	_gm.state.serialize_hex_map()
	var saved: Dictionary = _gm.state.hex_map_data.duplicate(true)
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	_check(_fingerprint(_gm.state.hex_map) == fingerprint, "bounty_id survives save/load roundtrip")

	# ── Old-save compat: entries without the key default to empty ──
	for key in saved:
		saved[key].erase("bounty_id")
	_gm.state.hex_map_data = saved
	_gm.state.deserialize_hex_map()
	var any_bounty := false
	for coord in _gm.state.hex_map.tiles:
		if _gm.state.hex_map.tiles[coord].bounty_id != &"":
			any_bounty = true
	_check(not any_bounty, "old saves without bounty_id load with empty bounties")

	# ── Claim resolution ──
	_gm.new_game(&"empire", false, 0)
	var map2 = _gm.state.hex_map
	var pid: StringName = &"empire"
	var home: CityState = null
	for cid in _gm.state.cities:
		if _gm.state.cities[cid].faction_id == pid:
			home = _gm.state.cities[cid]
			break
	# Craft a bounty 2 tiles from home on a land tile
	var spot := Vector2i(-1, -1)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var h2 := Vector2i(home.hex_pos.x + dx, home.hex_pos.y + dy)
			if HexHelper.hex_distance(home.hex_pos, h2) == 2:
				var t2 = map2.get_tile(h2)
				if t2 and t2.terrain != Enums.TerrainType.WATER and t2.bounty_id == &"":
					spot = h2
					break
		if spot != Vector2i(-1, -1):
			break
	map2.get_tile(spot).bounty_id = &"orchards"
	_check(BountySystem.claimant_for(spot) == home.city_id, "city claims bounty at distance 2")
	_check(spot in BountySystem.claimed_bounties_for_city(home), "claimed_bounties_for_city finds it")
	var listing: Array = BountySystem.bounties_of_faction(pid)
	var found_listing := false
	for entry in listing:
		if entry.hex == spot and entry.id == &"orchards":
			found_listing = true
	_check(found_listing, "bounties_of_faction lists the claim")
	_check(BountySystem.describe(&"orchards").contains("Food"), "describe() names the bonus")
	# Distance 3 → unclaimed
	map2.get_tile(spot).bounty_id = &""
	var far := Vector2i(-1, -1)
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var h3 := Vector2i(home.hex_pos.x + dx, home.hex_pos.y + dy)
			if HexHelper.hex_distance(home.hex_pos, h3) == 3:
				var t3 = map2.get_tile(h3)
				if t3 and t3.terrain != Enums.TerrainType.WATER and t3.bounty_id == &"":
					var other_claim := false
					for cid2 in _gm.state.cities:
						if HexHelper.hex_distance(_gm.state.cities[cid2].hex_pos, h3) <= 2:
							other_claim = true
					if not other_claim:
						far = h3
						break
		if far != Vector2i(-1, -1):
			break
	if far != Vector2i(-1, -1):
		map2.get_tile(far).bounty_id = &"orchards"
		_check(BountySystem.claimant_for(far) == &"", "distance 3 is out of claim range")
		map2.get_tile(far).bounty_id = &""

	# ── Economy hooks ──
	map2.get_tile(spot).bounty_id = &"orchards"
	var inc_with: Dictionary = _gm.city_system.calculate_city_income(home)
	map2.get_tile(spot).bounty_id = &""
	var inc_without: Dictionary = _gm.city_system.calculate_city_income(home)
	_check(inc_with.get(3, 0) - inc_without.get(3, 0) == 6, "orchards adds +6 food to city income")

	# Note: home's claim radius may already contain naturally-scattered bounties
	# (e.g. another wild_horses or honey_apiaries deposit), so these checks use
	# before/after deltas at `spot` rather than raw totals — same trick as the
	# income check above.
	map2.get_tile(spot).bounty_id = &"wild_horses"
	var cav_ud := UnitData.new()
	cav_ud.tags = ["cavalry", "melee"]
	var inf_ud := UnitData.new()
	inf_ud.tags = ["infantry", "melee"]
	var disc_cav_with := BountySystem.recruit_discount_for(home, cav_ud)
	var disc_inf_with := BountySystem.recruit_discount_for(home, inf_ud)
	map2.get_tile(spot).bounty_id = &""
	var disc_cav_without := BountySystem.recruit_discount_for(home, cav_ud)
	var disc_inf_without := BountySystem.recruit_discount_for(home, inf_ud)
	_check(disc_cav_with - disc_cav_without == 10, "wild horses discount cavalry 10%")
	_check(disc_inf_with - disc_inf_without == 0, "no discount for infantry")

	map2.get_tile(spot).bounty_id = &"vineyards"
	var loy_with: Dictionary = BountySystem.loyalty_bonus_for_city(home)
	map2.get_tile(spot).bounty_id = &""
	var loy_without: Dictionary = BountySystem.loyalty_bonus_for_city(home)
	_check(int(loy_with.get("peasants", 0)) - int(loy_without.get("peasants", 0)) == 1, "vineyards grant +1 peasant loyalty")

	# ── Founding preview query ──
	map2.get_tile(spot).bounty_id = &"orchards"
	var near_settle := Vector2i(home.hex_pos.x, home.hex_pos.y)  # settling AT the city is impossible, but the query is position-based
	# Populate explored_tiles with the bounty location so the fog-of-war check passes
	_gm.explored_tiles[spot] = true
	var claimable: Array = BountySystem.bounties_claimable_at(spot)  # standing on the bounty
	var self_found := false
	for entry in claimable:
		if entry.hex == spot:
			self_found = true
	_check(self_found, "bounties_claimable_at sees an adjacent bounty (distance 0 beats the existing claimant at 2)")
	map2.get_tile(spot).bounty_id = &""

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

	if _fails == 0:
		print("BOUNTY TEST PASSED")
		quit(0)
	else:
		print("BOUNTY TEST FAILED (%d)" % _fails)
		quit(1)

func _fingerprint(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].bounty_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].bounty_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
