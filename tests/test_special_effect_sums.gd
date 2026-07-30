extends SceneTree
## Plan B Task 5: cached special-effect sums must equal the old per-key loops.
## Run: godot --headless --path . -s res://tests/test_special_effect_sums.gd

var _fails := 0
var _gm: Node
var _dm: Node
var _tm: Node

const KEYS := ["imperial_authority_bonus", "harmony_bonus", "seasonal_multiplier",
	"taint_generation", "faith_stabilization", "solar_faith_income",
	"relic_power_bonus", "lunar_phase_tech_bonus", "captive_conversion_rate"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_tm = root.get_node("/root/TurnManager")
	_gm.new_game(&"empire", false, 0)

	# Give a few cities buildings that actually carry special effects
	var special_bids: Array = []
	for bid in _dm.buildings:
		var bd: BuildingData = _dm.buildings[bid]
		if bd.special_effects.size() > 0:
			special_bids.append(bid)
		if special_bids.size() >= 6:
			break
	var injected := 0
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id != &"" and c.faction_id != &"independent" and injected < special_bids.size():
			c.buildings.append(special_bids[injected])
			injected += 1

	_tm._special_effect_sums_cache.clear()
	var count := 0
	for fid in _gm.state.faction_states:
		var fs: FactionState = _gm.state.faction_states[fid]
		for key in KEYS:
			var new_val: float = _tm._sum_building_special_effect(fs, key)
			var old_val: float = _ref_sum(fs, key)
			if absf(new_val - old_val) > 0.0001:
				_fails += 1
				print("FAIL %s/%s: new=%f old=%f" % [fid, key, new_val, old_val])
		count += 1

	if _fails == 0:
		print("SPECIAL EFFECT SUMS TEST PASSED (%d factions x %d keys)" % [count, KEYS.size()])
		quit(0)
	else:
		print("SPECIAL EFFECT SUMS TEST FAILED (%d)" % _fails)
		quit(1)

func _ref_sum(fs: FactionState, key: String) -> float:
	# Verbatim old _sum_building_special_effect
	var total := 0.0
	for city_id in fs.owned_cities:
		var city: CityState = _gm.state.cities.get(city_id)
		if city == null:
			continue
		for building_id in city.buildings:
			var bd: BuildingData = _dm.get_building(building_id)
			if bd and bd.special_effects.has(key):
				total += float(bd.special_effects[key])
	return total
