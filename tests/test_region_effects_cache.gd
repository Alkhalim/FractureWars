extends SceneTree
## Plan A Task 6: cached apply_region_effects must produce numerically identical
## income to the old all-cities scan, including compounding order and after
## building/ownership mutations.
## Run: godot --headless --path . -s res://tests/test_region_effects_cache.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)
	var cs = _gm.city_system

	# Give one city special buildings so effects actually fire (two depots to
	# exercise sequential compounding, plus a faction-wide one if defined).
	var region_keys: Array = cs.REGION_WIDE_BUILDING_EFFECTS.keys()
	var faction_keys: Array = cs.FACTION_WIDE_BUILDING_EFFECTS.keys()
	var some_city: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			some_city = c
			break
	if some_city and region_keys.size() > 0:
		some_city.buildings.append(region_keys[0])
		some_city.buildings.append(region_keys[0])
	if some_city and faction_keys.size() > 0:
		some_city.buildings.append(faction_keys[0])
	cs.invalidate_region_effects_cache()

	_compare_all(cs, "with injected special buildings")
	_compare_all(cs, "cached second pass")

	# Mutation: remove one special building + invalidate
	if some_city and region_keys.size() > 0:
		some_city.buildings.erase(region_keys[0])
		cs.invalidate_region_effects_cache()
		_compare_all(cs, "after building removal")

	if _fails == 0:
		print("REGION EFFECTS TEST PASSED")
		quit(0)
	else:
		print("REGION EFFECTS TEST FAILED (%d)" % _fails)
		quit(1)

func _compare_all(cs, label: String) -> void:
	for cid in _gm.state.cities:
		var city: CityState = _gm.state.cities[cid]
		# Seed both with identical synthetic income so pct effects have a base.
		var income_new := {Enums.ResourceType.GOLD: 100, Enums.ResourceType.TECHNOLOGY: 20}
		var income_old := {Enums.ResourceType.GOLD: 100, Enums.ResourceType.TECHNOLOGY: 20}
		cs.apply_region_effects(income_new, city)
		_ref_apply(cs, income_old, city)
		if income_new != income_old:
			_fails += 1
			print("FAIL (%s) city %s: new=%s old=%s" % [label, city.city_id, income_new, income_old])

func _ref_apply(cs, income: Dictionary, city: CityState) -> void:
	# Verbatim old apply_region_effects
	var faction_id: StringName = city.faction_id
	var region_id: StringName = city.region_id
	var parent_fid: StringName = _gm.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	for scan_city_id in _gm.state.cities:
		var scan_city: CityState = _gm.state.cities[scan_city_id]
		if scan_city.faction_id != faction_id:
			var scan_parent: StringName = _gm.MINOR_FACTION_PARENTS.get(scan_city.faction_id, scan_city.faction_id)
			if scan_parent != parent_fid:
				continue
		for building_id in scan_city.buildings:
			if cs.REGION_WIDE_BUILDING_EFFECTS.has(building_id) and scan_city.region_id == region_id:
				var eff: Dictionary = cs.REGION_WIDE_BUILDING_EFFECTS[building_id]
				match eff.effect:
					"gold_income_pct":
						var gold_bonus := int(income.get(Enums.ResourceType.GOLD, 0) * eff.value / 100.0)
						income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + gold_bonus
					"tech_flat":
						income[Enums.ResourceType.TECHNOLOGY] = income.get(Enums.ResourceType.TECHNOLOGY, 0) + eff.value
					"defense_flat":
						pass
			if cs.FACTION_WIDE_BUILDING_EFFECTS.has(building_id):
				var eff: Dictionary = cs.FACTION_WIDE_BUILDING_EFFECTS[building_id]
				if eff.has("faction_filter"):
					if parent_fid != eff.faction_filter:
						continue
				match eff.effect:
					"loyalty_flat":
						pass
					"trade_income_pct":
						var gold_bonus := int(income.get(Enums.ResourceType.GOLD, 0) * eff.value / 100.0)
						income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + gold_bonus
					"gold_per_relic_building":
						var relic_count := 0
						for bid in city.buildings:
							var bld = _dm.get_building(bid)
							if bld and bld.category == &"cultural":
								relic_count += 1
						income[Enums.ResourceType.GOLD] = income.get(Enums.ResourceType.GOLD, 0) + relic_count * eff.value
