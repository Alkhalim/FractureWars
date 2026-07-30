extends SceneTree
## Plan A Task 1: movement cache keys must include every result-affecting input.
## Two calls that differ only in excluded_army_id / can_cross_mountains / army
## must NOT serve each other's cached results.
## Run: godot --headless --path . -s res://tests/test_movement_cache_keys.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Autoload globals are not compile-time resolvable in -s scripts; fetch nodes.
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)
	var ms: MovementSystem = _gm.movement_system
	ms.refresh_caches()

	# Pick a start hex with open surroundings: use the player's capital position.
	var fs: FactionState = _gm.state.faction_states[_gm.state.player_faction_id]
	var capital: CityState = _gm.state.cities[fs.owned_cities[0]]
	var from: Vector2i = capital.hex_pos
	var faction: StringName = capital.faction_id

	# --- can_cross_mountains must not collide ---------------------------------
	ms._path_cache.clear()
	ms._reachable_cache.clear()
	var reach_no_mtn: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, &"", false, null)
	var reach_mtn: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, &"", true, null)
	# Reference: fresh computation with cleared cache must equal the second call.
	ms._reachable_cache.clear()
	var reach_mtn_ref: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, &"", true, null)
	_check(reach_mtn == reach_mtn_ref, "reachable: can_cross_mountains ignored by cache key")
	ms._reachable_cache.clear()
	var reach_no_mtn_ref: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, &"", false, null)
	_check(reach_no_mtn == reach_no_mtn_ref, "reachable: baseline mismatch (no-mountain)")

	# --- army stride modifiers must not collide -------------------------------
	# Two armies of the same faction at the same hex, different composition.
	var army_a := _make_army(&"__test_a", faction, from, &"") # first unit id from data
	var army_b := _make_army(&"__test_b", faction, from, &"flying_preferred")
	if army_a and army_b:
		ms._reachable_cache.clear()
		var ra: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, army_a.army_id, false, army_a)
		var rb: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, army_b.army_id, false, army_b)
		ms._reachable_cache.clear()
		var rb_ref: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, army_b.army_id, false, army_b)
		_check(rb == rb_ref, "reachable: army identity ignored by cache key")
		ms._reachable_cache.clear()
		var ra_ref: Dictionary = ms.get_reachable_tiles(from, 6.0, faction, army_a.army_id, false, army_a)
		_check(ra == ra_ref, "reachable: baseline mismatch (army a)")

		# Path variant: same from/to, different army/excluded id.
		var to := Vector2i(from.x + 4, from.y + 2)
		ms._path_cache.clear()
		var pa: Array[Vector2i] = ms.find_path(from, to, faction, 99.0, army_a.army_id, false, army_a)
		var pb: Array[Vector2i] = ms.find_path(from, to, faction, 99.0, army_b.army_id, false, army_b)
		ms._path_cache.clear()
		var pb_ref: Array[Vector2i] = ms.find_path(from, to, faction, 99.0, army_b.army_id, false, army_b)
		_check(pb == pb_ref, "path: army/excluded identity ignored by cache key")
		ms._path_cache.clear()
		var pa_ref: Array[Vector2i] = ms.find_path(from, to, faction, 99.0, army_a.army_id, false, army_a)
		_check(pa == pa_ref, "path: baseline mismatch (army a)")

	if _fails == 0:
		print("CACHE KEY TEST PASSED")
		quit(0)
	else:
		print("CACHE KEY TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

func _make_army(id: StringName, faction: StringName, pos: Vector2i, prefer_tag: StringName) -> ArmyState:
	# Build a minimal in-memory army (not registered in state) with a real unit.
	var unit_id: StringName = &""
	for uid in _dm.units:
		var ud: UnitData = _dm.units[uid]
		if prefer_tag != &"" and "flying" in ud.tags:
			unit_id = uid
			break
		elif prefer_tag == &"" and "flying" not in ud.tags:
			unit_id = uid
			break
	if unit_id == &"":
		# Fall back to any unit
		for uid in _dm.units:
			unit_id = uid
			break
	if unit_id == &"":
		return null
	var army := ArmyState.new()
	army.army_id = id
	army.faction_id = faction
	army.hex_pos = pos
	var unit := UnitInstance.new()
	unit.unit_data_id = unit_id
	army.units.append(unit)
	return army
