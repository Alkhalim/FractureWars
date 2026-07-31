extends SceneTree
## THROWAWAY scan script for Task 3 (growth purge). Enumerates every building
## whose id or display_name matches the industrial-name regex, prints its
## income_bonus, largest income key, population_growth_bonus, and
## special_effects.region_population_growth_bonus so we can spot stragglers
## the audit list missed. Also separately lists every tier-2+ building whose
## largest income key is FOOD(3) and carries region_population_growth_bonus,
## for the growth-variance rule.
##
## Run: godot --headless --path . -s res://tests/tmp_growth_sweep.gd

var _name_re := RegEx.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_name_re.compile("(?i)(mine|forge|quarry|foundry|smelter|pit|kiln|works)")
	var dm = root.get_node("/root/DataManager")

	print("=== INDUSTRIAL-NAMED BUILDINGS (mine|forge|quarry|foundry|smelter|pit|kiln|works) ===")
	var ids: Array = dm.buildings.keys()
	ids.sort()
	for id in ids:
		var b: BuildingData = dm.buildings[id]
		var name_hit := _name_re.search(String(id)) != null or _name_re.search(b.display_name) != null
		if not name_hit:
			continue
		var largest_key := -1
		var largest_val := -999999
		for k in b.income_bonus.keys():
			var v := int(b.income_bonus[k])
			if v > largest_val:
				largest_val = v
				largest_key = int(k)
		var region_growth = b.special_effects.get("region_population_growth_bonus", null)
		print("%s | display=%s | income=%s | largest_key=%s(val=%s) | pop_growth=%s | region_growth=%s | tier(cap_lvl)=%s" % [
			id, b.display_name, b.income_bonus, largest_key, largest_val,
			b.population_growth_bonus, region_growth, b.required_capital_level
		])

	print("")
	print("=== FOOD-PRIMARY BUILDINGS WITH region_population_growth_bonus (growth-variance candidates) ===")
	for id in ids:
		var b: BuildingData = dm.buildings[id]
		if not b.special_effects.has("region_population_growth_bonus"):
			continue
		var largest_key := -1
		var largest_val := -999999
		for k in b.income_bonus.keys():
			var v := int(b.income_bonus[k])
			if v > largest_val:
				largest_val = v
				largest_key = int(k)
		if largest_key == 3:
			print("%s | display=%s | income=%s | region_growth=%s | cap_lvl=%s" % [
				id, b.display_name, b.income_bonus, b.special_effects.get("region_population_growth_bonus"), b.required_capital_level
			])

	print("")
	print("=== ALL region_population_growth_bonus holders (for reference, any largest key) ===")
	for id in ids:
		var b: BuildingData = dm.buildings[id]
		if not b.special_effects.has("region_population_growth_bonus"):
			continue
		var largest_key := -1
		var largest_val := -999999
		for k in b.income_bonus.keys():
			var v := int(b.income_bonus[k])
			if v > largest_val:
				largest_val = v
				largest_key = int(k)
		print("%s | display=%s | largest_key=%s | region_growth=%s" % [
			id, b.display_name, largest_key, b.special_effects.get("region_population_growth_bonus")
		])

	print("")
	print("=== ALL population_growth_bonus != 0 on industrial-named buildings (redundant with first section but explicit) ===")
	for id in ids:
		var b: BuildingData = dm.buildings[id]
		var name_hit := _name_re.search(String(id)) != null or _name_re.search(b.display_name) != null
		if name_hit and b.population_growth_bonus != 0:
			print("%s | display=%s | population_growth_bonus=%s" % [id, b.display_name, b.population_growth_bonus])

	print("")
	print("=== EXHAUSTIVE: ALL buildings (any name) whose largest income key is IRON(1) AND carry a growth field ===")
	for id in ids:
		var b: BuildingData = dm.buildings[id]
		var largest_key := -1
		var largest_val := -999999
		for k in b.income_bonus.keys():
			var v := int(b.income_bonus[k])
			if v > largest_val:
				largest_val = v
				largest_key = int(k)
		if largest_key != 1:
			continue
		var has_region := b.special_effects.has("region_population_growth_bonus")
		if b.population_growth_bonus != 0 or has_region:
			print("%s | display=%s | income=%s | pop_growth=%s | region_growth=%s | name_regex_hit=%s" % [
				id, b.display_name, b.income_bonus, b.population_growth_bonus, b.special_effects.get("region_population_growth_bonus"),
				(_name_re.search(String(id)) != null or _name_re.search(b.display_name) != null)
			])

	print("DONE")
	quit(0)
