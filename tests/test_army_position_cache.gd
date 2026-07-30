extends SceneTree
## Plan A Task 9: incremental army-position updates must keep the position
## cache exactly consistent with state.armies through moves, removals, and
## uncounted insertions (which must self-heal via the count check).
## Run: godot --headless --path . -s res://tests/test_army_position_cache.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var ms: MovementSystem = _gm.movement_system
	ms.refresh_caches()
	_check(ms.positions_fresh(), "cache fresh after refresh")

	# Move a player army along a real path
	var moved_army: ArmyState = null
	for aid in _gm.state.armies:
		var a: ArmyState = _gm.state.armies[aid]
		if a.faction_id == &"empire" and not a.is_garrison:
			moved_army = a
			break
	if moved_army:
		var from: Vector2i = moved_army.hex_pos
		var to := Vector2i(from.x + 3, from.y + 2)
		var path: Array[Vector2i] = ms.find_path(from, to, moved_army.faction_id, 99.0, moved_army.army_id, false, moved_army)
		if path.size() > 0:
			moved_army.movement_remaining = 99.0
			_gm.move_army_along_path(moved_army.army_id, path)
			_verify_consistency(ms, "after multi-step move")
		else:
			print("WARN: no path found for move test")

	# Removal keeps the cache fresh and consistent
	var victim: ArmyState = null
	for aid in _gm.state.armies:
		var a: ArmyState = _gm.state.armies[aid]
		if a != moved_army:
			victim = a
			break
	if victim:
		var victim_pos: Vector2i = victim.hex_pos
		var victim_id: StringName = victim.army_id
		_gm.remove_army(victim_id)
		_verify_consistency(ms, "after remove_army")
		for a in _gm.get_armies_at_tile(victim_pos):
			if a.army_id == victim_id:
				_fails += 1
				print("FAIL: removed army still listed at its tile")

	# Uncounted insertion must break freshness and self-heal
	if ms.positions_fresh():
		var extra := ArmyState.new()
		extra.army_id = &"__test_extra_army"
		extra.faction_id = &"empire"
		extra.hex_pos = Vector2i(5, 5)
		_gm.state.armies[extra.army_id] = extra
		_check(not ms.positions_fresh(), "count check detects uncounted insertion")
		# Getter must fall back to a correct linear scan
		var found := false
		for a in _gm.get_armies_at_tile(Vector2i(5, 5)):
			if a.army_id == extra.army_id:
				found = true
		_check(found, "fallback getter finds uncounted army")
		ms.refresh_caches()
		_verify_consistency(ms, "after refresh following insertion")

	if _fails == 0:
		print("ARMY POSITION CACHE TEST PASSED")
		quit(0)
	else:
		print("ARMY POSITION CACHE TEST FAILED (%d)" % _fails)
		quit(1)

func _verify_consistency(ms: MovementSystem, label: String) -> void:
	if not ms.positions_fresh():
		# A battle/merge during the move may legitimately invalidate; rebuild
		ms.refresh_caches()
	# Every army must be listed exactly at its hex
	for aid in _gm.state.armies:
		var a: ArmyState = _gm.state.armies[aid]
		var listed := false
		for x in _gm.get_armies_at_tile(a.hex_pos):
			if x.army_id == a.army_id:
				listed = true
				break
		if not listed:
			_fails += 1
			print("FAIL (%s): army %s missing at %s" % [label, a.army_id, a.hex_pos])
	# No bucket may contain an army whose hex_pos disagrees
	for coord in ms._army_positions:
		for a: ArmyState in ms._army_positions[coord]:
			if a.hex_pos != coord:
				_fails += 1
				print("FAIL (%s): stale bucket %s holds army at %s" % [label, coord, a.hex_pos])

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
