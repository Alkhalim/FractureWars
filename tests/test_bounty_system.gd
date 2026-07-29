extends SceneTree
## Tests for tier-1 bounty resources (docs/special_resources_design.md).
## Run: godot --headless --path . -s res://tests/test_bounty_system.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire")
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
	for t in counts:
		_check(counts[t] <= 8, "type %s capped at 8 (got %d)" % [t, counts[t]])
	# Spacing: no two bounties within 3 hexes
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if HexHelper.hex_distance(placed[i], placed[j]) < 3:
				_fails += 1
				print("FAIL: bounties too close: %s %s" % [placed[i], placed[j]])

	# ── Determinism: regenerating the same map yields identical bounties ──
	var fingerprint := _fingerprint(map)
	_gm.new_game(&"empire")
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
	_gm.new_game(&"empire")
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
