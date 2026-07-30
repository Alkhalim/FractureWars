extends SceneTree
## Plan A Task 7: cached has_free_passage must equal the brute-force treaty
## scan for all faction pairs, including after adding/removing a treaty.
## Run: godot --headless --path . -s res://tests/test_free_passage_cache.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var ds = _gm.diplomacy_system

	_compare_all(ds, "initial")

	# Force a free-passage treaty between two factions and re-check
	var fids: Array = _gm.state.faction_states.keys()
	var a: StringName = fids[0]
	var b: StringName = fids[1] if fids.size() > 1 else fids[0]
	ds.propose_free_passage(a, b, true)
	_compare_all(ds, "after treaty added")

	# Remove all FREE_PASSAGE treaties and re-check
	var to_erase: Array = []
	for tid in _gm.state.diplomacy_state.treaties:
		var t = _gm.state.diplomacy_state.treaties[tid]
		if t.treaty_type == Enums.TreatyType.FREE_PASSAGE:
			to_erase.append(tid)
	for tid in to_erase:
		_gm.state.diplomacy_state.treaties.erase(tid)
	ds.invalidate_free_passage_cache()
	_compare_all(ds, "after treaties removed")

	if _fails == 0:
		print("FREE PASSAGE TEST PASSED")
		quit(0)
	else:
		print("FREE PASSAGE TEST FAILED (%d)" % _fails)
		quit(1)

func _compare_all(ds, label: String) -> void:
	var fids: Array = _gm.state.faction_states.keys()
	for i in range(fids.size()):
		for j in range(fids.size()):
			var a: StringName = fids[i]
			var b: StringName = fids[j]
			if ds.has_free_passage(a, b) != _ref(ds, a, b):
				_fails += 1
				print("FAIL (%s): %s vs %s" % [label, a, b])

func _ref(ds, faction_a: StringName, faction_b: StringName) -> bool:
	# Verbatim old has_free_passage
	if faction_a == faction_b:
		return true
	var relation: int = _gm.get_relation(faction_a, faction_b)
	if relation == Enums.FactionRelation.ALLIED:
		return true
	for treaty_id in _gm.state.diplomacy_state.treaties:
		var t = _gm.state.diplomacy_state.treaties[treaty_id]
		if t.treaty_type == Enums.TreatyType.FREE_PASSAGE:
			if (t.faction_a == faction_a and t.faction_b == faction_b) or \
			   (t.faction_a == faction_b and t.faction_b == faction_a):
				return true
	return false
