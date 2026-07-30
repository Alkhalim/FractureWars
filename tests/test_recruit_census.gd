extends SceneTree
## Plan B Task 1: the hoisted recruit census must equal the old inline
## computation for several factions.
## Run: godot --headless --path . -s res://tests/test_recruit_census.gd

var _fails := 0
var _gm: Node
var _dm: Node
var _tm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_tm = root.get_node("/root/TurnManager")
	_gm.new_game(&"empire", false, 0)

	var count := 0
	for fid in _gm.state.faction_states:
		if _gm.is_npc_faction(fid):
			continue
		var new_census: Dictionary = _tm._compute_ai_recruit_census(fid)
		var old_census: Dictionary = _ref_census(fid)
		if new_census != old_census:
			_fails += 1
			print("FAIL %s:\n  new=%s\n  old=%s" % [fid, new_census, old_census])
		count += 1
		if count >= 5:
			break

	if _fails == 0:
		print("RECRUIT CENSUS TEST PASSED (%d factions)" % count)
		quit(0)
	else:
		print("RECRUIT CENSUS TEST FAILED (%d)" % _fails)
		quit(1)

func _ref_census(faction_id: StringName) -> Dictionary:
	# Verbatim old inline computation from _ai_recruit_with_composition
	var tag_counts := {"infantry": 0, "ranged": 0, "cavalry": 0, "mage": 0}
	var total_units := 0
	var _unit_cache: Dictionary = {}
	for army: ArmyState in _gm.get_all_faction_armies(faction_id):
		for unit in army.units:
			var ud: UnitData = _unit_cache.get(unit.unit_data_id)
			if ud == null:
				ud = _dm.get_unit(unit.unit_data_id)
				if ud == null:
					continue
				_unit_cache[unit.unit_data_id] = ud
			total_units += 1
			for tag in tag_counts:
				if ud.tags.has(tag):
					tag_counts[tag] += 1
	var max_enemy_units := 0
	for other_id in _gm.state.faction_states:
		if other_id == faction_id or _gm.is_npc_faction(other_id):
			continue
		if _gm.get_relation(faction_id, other_id) != Enums.FactionRelation.WAR:
			continue
		var enemy_units := 0
		for enemy_army: ArmyState in _gm.get_faction_armies(other_id):
			enemy_units += enemy_army.units.size()
		max_enemy_units = maxi(max_enemy_units, enemy_units)
	return {tag_counts = tag_counts, total_units = total_units, max_enemy_units = max_enemy_units}
