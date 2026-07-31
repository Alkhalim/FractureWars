extends SceneTree
## Temp tool (Balance Batch 2, Item 4): lists every unit whose unlocking
## building is a TIER-1 building (required_capital_level <= 1, no
## upgrades_from) alongside its current recruit_time, so the 1-turn-training
## rule can be applied by hand to the .tres files. Delete after use.
##   godot --headless --path . -s res://tests/tmp_unit_training_sweep.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")

	# A unit qualifies if ANY building that unlocks it is tier-1 (required_
	# capital_level <= 1 AND upgrades_from == &"") -- even if the same unit
	# is also unlocked elsewhere by a tier-2+ building.
	var qualifying_unit_ids: Dictionary = {} # unit_id -> true
	var tier1_building_count := 0
	for bid in dm.buildings.keys():
		var b: BuildingData = dm.buildings[bid]
		var is_tier1 := b.required_capital_level <= 1 and b.upgrades_from == &""
		if not is_tier1:
			continue
		tier1_building_count += 1
		for uid in b.unlocks_units:
			qualifying_unit_ids[uid] = true

	print("tier-1 buildings scanned: %d" % tier1_building_count)
	print("qualifying unit ids (tier-1-unlocked): %d" % qualifying_unit_ids.size())
	print("id,faction,old_recruit_time,needs_change")

	var rows: Array = []
	for uid in qualifying_unit_ids.keys():
		var ud: UnitData = dm.get_unit(uid)
		if ud == null:
			print("WARNING: unit id %s referenced by a tier-1 building but not found in DataManager.units" % uid)
			continue
		rows.append(ud)
	rows.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		if a.faction_id != b.faction_id:
			return String(a.faction_id) < String(b.faction_id)
		return String(a.id) < String(b.id)
	)
	var needs_change := 0
	for ud in rows:
		var needs: bool = ud.recruit_time > 1
		if needs:
			needs_change += 1
		print("%s,%s,%d,%s" % [ud.id, ud.faction_id, ud.recruit_time, str(needs)])

	print("TOTAL needing change (recruit_time > 1 -> 1): %d" % needs_change)
	quit(0)
