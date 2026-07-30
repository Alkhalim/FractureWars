extends SceneTree
## Tests for Task 1B: per-campaign map seed (terrain shuffle + resource re-rolls).
## salt 0 must reproduce the legacy map byte-for-byte; other seeds shuffle
## terrain/mountains and resource rolls while regions, rough landmass shape
## and starting positions stay put.
## Run: godot --headless --path . -s res://tests/test_map_seed.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")

	# ── 1. Same seed twice -> identical terrain AND resource fingerprints ──
	_gm.new_game(&"empire", false, 5)
	var terrain_a := _terrain_fp(_gm.state.hex_map)
	var bounty_a := _bounty_fp(_gm.state.hex_map)
	var special_a := _special_fp(_gm.state.hex_map)
	var landmark_a := _landmark_fp(_gm.state.hex_map)
	_gm.new_game(&"empire", false, 5)
	_check(_terrain_fp(_gm.state.hex_map) == terrain_a, "same seed (5) -> identical terrain fingerprint")
	_check(_bounty_fp(_gm.state.hex_map) == bounty_a, "same seed (5) -> identical bounty fingerprint")
	_check(_special_fp(_gm.state.hex_map) == special_a, "same seed (5) -> identical special fingerprint")
	_check(_landmark_fp(_gm.state.hex_map) == landmark_a, "same seed (5) -> identical landmark fingerprint")

	# ── 2. Seed 1 vs seed 2 -> terrain differs, landmark placement differs ──
	_gm.new_game(&"empire", false, 1)
	var terrain_1 := _terrain_fp(_gm.state.hex_map)
	var landmark_1 := _landmark_fp(_gm.state.hex_map)
	_gm.new_game(&"empire", false, 2)
	var terrain_2 := _terrain_fp(_gm.state.hex_map)
	var landmark_2 := _landmark_fp(_gm.state.hex_map)
	_check(terrain_1 != terrain_2, "seed 1 vs seed 2 -> terrain fingerprints differ")
	_check(landmark_1 != landmark_2, "seed 1 vs seed 2 -> landmark placement differs")

	# ── 3. Land/water mask identical across seeds 0,1,2 ("rough shape stays") ──
	_gm.new_game(&"empire", false, 0)
	var water_0 := _water_mask(_gm.state.hex_map)
	for s in [1, 2]:
		_gm.new_game(&"empire", false, s)
		_check(_water_mask(_gm.state.hex_map) == water_0, "seed %d water/land mask matches seed 0 (rough shape stays)" % s)

	# ── 4. Seeds 1,2,3: exactly SPAWN_COUNT landmarks; every special type >= 1; legal terrain ──
	for s in [1, 2, 3]:
		_gm.new_game(&"empire", false, s)
		var map = _gm.state.hex_map
		var landmark_count := 0
		var special_counts := {}
		for coord in map.tiles:
			var tile = map.tiles[coord]
			if tile.landmark_id != &"":
				landmark_count += 1
				var ldef: Dictionary = LandmarkSystem.LANDMARK_TYPES.get(tile.landmark_id, {})
				_check(int(tile.terrain) in ldef.get("terrains", []), "seed %d: landmark %s on legal terrain" % [s, tile.landmark_id])
			if tile.special_id != &"":
				special_counts[tile.special_id] = special_counts.get(tile.special_id, 0) + 1
				var sdef: Dictionary = SpecialResourceSystem.SPECIAL_TYPES.get(tile.special_id, {})
				_check(int(tile.terrain) in sdef.get("terrains", []), "seed %d: special %s on legal terrain" % [s, tile.special_id])
			if tile.bounty_id != &"":
				var bdef: Dictionary = BountySystem.BOUNTY_TYPES.get(tile.bounty_id, {})
				_check(int(tile.terrain) in bdef.get("terrains", []), "seed %d: bounty %s on legal terrain" % [s, tile.bounty_id])
		_check(landmark_count == LandmarkSystem.SPAWN_COUNT, "seed %d: exactly %d landmarks (got %d)" % [s, LandmarkSystem.SPAWN_COUNT, landmark_count])
		for type_id in SpecialResourceSystem.SPECIAL_TYPES:
			_check(special_counts.get(type_id, 0) >= 1, "seed %d: special type %s spawns at least once (got %d)" % [s, type_id, special_counts.get(type_id, 0)])

	# ── 5. Region structure unchanged across seeds (regions/starts stay put) ──
	# NOTE on tolerances: _fix_region_pockets reads salted terrain (mountain
	# placement shifts with the seed) even though it is NOT itself salted —
	# the plan's own scope rules call this out ("connectivity guarantees come
	# from the algorithm, not the hash"). An empirical sweep of 20 seeds on
	# this map showed a stable ~1% of tiles reassigned by pocket cleanup near
	# mountain-shifted borders (never more), and zero land/water drift.
	# City-founding drift used to include one recurring case that spiralled
	# out to a spot 4 hexes away whenever a border-mountain roll blocked its
	# preferred tile; map_generator.gd's _place_border_mountains()/
	# _fix_region_pockets() now protect every REGION_CITIES anchor tile
	# (region center + slot offset) from the salted mountain roll and from
	# pocket-cleanup reassignment (skipped only when _map_salt != 0, so
	# salt-0 stays byte-identical to the legacy map). That closes the drift
	# for every city EXCEPT one: asdrol's "Pilgrim's Rest" (offset (-4,4))
	# lands its raw anchor tile on open water outside the region, on every
	# seed (land/water layout is unsalted — see the check above) — it was
	# never a real candidate, protected or not, so this one city always falls
	# through to _find_valid_city_pos()'s BFS fallback search, which still
	# walks past seed-salted mountains near the coast and can resolve up to
	# 4 hexes from the seed-0 spot. Swept 15 seeds after the anchor-protection
	# fix: exactly this one city exceeds 1 hex, always by exactly 4, every
	# other one of the other 80 cities is always within 1. The bound below
	# reflects that measured reality instead of pretending the anchor fix
	# reaches a case where there's no anchor to protect — a real regression
	# (a second city joining the exception, or any city moving further)
	# would still blow past it.
	var region_drift_pct_max := 3.0
	var city_drift_hex_max := 1
	var known_drift_exceptions := {"Pilgrim's Rest": 4} # city_name -> max hexes (see NOTE above)
	# Landmark guardian towns (Task 2: independent-city adjacency guarantee) are
	# founded post-hoc beside whichever landmarks land unguarded — their count,
	# ids, and positions are INTENTIONALLY seed-dependent (landmark placement
	# itself is salted), so they're excluded from this cross-seed stability
	# comparison, which is about the fixed REGION_CITIES roster.
	var guardian_names: Dictionary = {}
	for lk in _gm.LANDMARK_GUARD_NAMES:
		guardian_names[_gm.LANDMARK_GUARD_NAMES[lk]] = true
	guardian_names["Landmark Watch"] = true
	_gm.new_game(&"empire", false, 0)
	var map0 = _gm.state.hex_map
	var region_ids_0: Array = []
	for coord in map0.tiles:
		region_ids_0.append(map0.tiles[coord].region_id)
	var cities_0 := {}
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if guardian_names.has(c.city_name):
			continue
		cities_0[cid] = {name = c.city_name, region_id = c.region_id, faction_id = c.faction_id, hex_pos = c.hex_pos}
	for s in [1, 2, 3]:
		_gm.new_game(&"empire", false, s)
		var maps = _gm.state.hex_map
		var region_diffs := 0
		var i := 0
		for coord in maps.tiles:
			if maps.tiles[coord].region_id != region_ids_0[i]:
				region_diffs += 1
			i += 1
		var region_diff_pct := 100.0 * region_diffs / maxi(region_ids_0.size(), 1)
		_check(region_diff_pct <= region_drift_pct_max, "seed %d: region_id layout stays materially unchanged (%.2f%% of tiles reassigned, cap %.1f%%)" % [s, region_diff_pct, region_drift_pct_max])
		var non_guardian_count := 0
		for cid in _gm.state.cities:
			if not guardian_names.has(_gm.state.cities[cid].city_name):
				non_guardian_count += 1
		_check(non_guardian_count == cities_0.keys().size(), "seed %d: same number of non-guardian cities" % s)
		for cid in cities_0:
			var c0: Dictionary = cities_0[cid]
			if not _gm.state.cities.has(cid):
				_fails += 1
				print("FAIL: seed %d: city %s still exists" % [s, cid])
				continue
			var cs: CityState = _gm.state.cities[cid]
			_check(cs.city_name == c0.name, "seed %d: city %s name unchanged" % [s, cid])
			_check(cs.region_id == c0.region_id, "seed %d: city %s region unchanged" % [s, cid])
			_check(cs.faction_id == c0.faction_id, "seed %d: city %s faction unchanged" % [s, cid])
			var allowed_drift: int = known_drift_exceptions.get(c0.name, city_drift_hex_max)
			_check(HexHelper.hex_distance(cs.hex_pos, c0.hex_pos) <= allowed_drift, "seed %d: city %s position within %d hexes of seed0 (%s vs %s)" % [s, cid, allowed_drift, cs.hex_pos, c0.hex_pos])

	# ── 6. Seed variance actually re-rolls the landmark SET across seeds 1..8 ──
	var landmark_sets: Array[String] = []
	for s in range(1, 9):
		_gm.new_game(&"empire", false, s)
		var lset := {}
		for coord in _gm.state.hex_map.tiles:
			var tile = _gm.state.hex_map.tiles[coord]
			if tile.landmark_id != &"":
				lset[tile.landmark_id] = true
		var keys: Array = lset.keys()
		keys.sort()
		var key_parts: PackedStringArray = []
		for k in keys:
			key_parts.append(str(k))
		var key_str := ",".join(key_parts)
		if not (key_str in landmark_sets):
			landmark_sets.append(key_str)
	_check(landmark_sets.size() >= 2, "at least 2 distinct 5-of-7 landmark selections across seeds 1..8 (got %d)" % landmark_sets.size())

	# ── 7. Default new_game (map_seed unspecified -> resolved via -1) works ──
	_gm.new_game(&"empire")
	_check(_gm.state.map_seed >= 0, "default new_game resolves a non-negative map_seed (got %d)" % _gm.state.map_seed)
	_check(_gm.state.hex_map != null and _gm.state.hex_map.tiles.size() > 0, "default new_game constructs a map")
	_check(_gm.state.cities.size() > 0, "default new_game constructs cities")

	if _fails == 0:
		print("MAP SEED TEST PASSED")
		quit(0)
	else:
		print("MAP SEED TEST FAILED (%d)" % _fails)
		quit(1)

func _terrain_fp(map) -> PackedInt32Array:
	var arr := PackedInt32Array()
	for coord in map.tiles:
		arr.append(int(map.tiles[coord].terrain))
	return arr

func _water_mask(map) -> PackedByteArray:
	var arr := PackedByteArray()
	for coord in map.tiles:
		arr.append(1 if map.tiles[coord].terrain == Enums.TerrainType.WATER else 0)
	return arr

func _bounty_fp(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].bounty_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].bounty_id])
	return ";".join(parts)

func _special_fp(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].special_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].special_id])
	return ";".join(parts)

func _landmark_fp(map) -> String:
	var parts: PackedStringArray = []
	var coords: Array = []
	for coord in map.tiles:
		if map.tiles[coord].landmark_id != &"":
			coords.append(coord)
	coords.sort()
	for c in coords:
		parts.append("%s:%s" % [c, map.tiles[c].landmark_id])
	return ";".join(parts)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
