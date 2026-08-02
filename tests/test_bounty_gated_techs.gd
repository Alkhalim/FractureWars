extends SceneTree
## Bounty-gated technologies test suite. Task 1 section: the three new
## bounty types added for gate variety (designer directive 2026-08-01).
var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm = root.get_node("/root/GameManager")
	gm.new_game(&"empire", false, 0)
	_run_new_bounty_types_test(gm)
	if _fails == 0:
		print("BOUNTY GATED TECHS TEST PASSED")
		quit(0)
	else:
		print("BOUNTY GATED TECHS TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

func _run_new_bounty_types_test(gm) -> void:
	for tid in [&"coal_seams", &"bone_fields", &"bronze_ore"]:
		_check(BountySystem.BOUNTY_TYPES.has(tid), "%s exists in BOUNTY_TYPES" % tid)
		_check(BountySystem.describe(tid) != "", "%s has a describe() line" % tid)
	# Plant each new type on a tile within CLAIM_RADIUS of a player city and
	# verify the generic pickup paths (income / recruit discount) see it.
	var player_id: StringName = gm.state.player_faction_id
	var fs = gm.state.faction_states[player_id]
	var city: CityState = gm.state.cities.get(fs.owned_cities[0])
	var map = gm.state.hex_map
	# Three distinct neighbor tiles of the city (all within CLAIM_RADIUS=2)
	var spots: Array[Vector2i] = []
	for coord in map.tiles:
		if spots.size() >= 3:
			break
		var d: int = HexHelper.hex_distance(city.hex_pos, coord)
		var t = map.get_tile(coord)
		if d >= 1 and d <= 2 and t and t.bounty_id == &"" and t.special_id == &"" and t.landmark_id == &"":
			spots.append(coord)
	_check(spots.size() == 3, "found 3 clean tiles near the capital (got %d)" % spots.size())
	if spots.size() < 3:
		return
	map.get_tile(spots[0]).bounty_id = &"coal_seams"
	map.get_tile(spots[1]).bounty_id = &"bronze_ore"
	map.get_tile(spots[2]).bounty_id = &"bone_fields"
	var income: Dictionary = BountySystem.income_bonus_for_city(city)
	_check(income.get(1, 0) >= 6 + 4, "coal_seams+bronze_ore iron income sums (got %s)" % [income])
	_check(income.get(0, 0) >= 3, "bronze_ore gold income counted (got %s)" % [income])
	# bone_fields: undead recruit discount — find any undead-tagged unit
	var undead_unit: UnitData = null
	var dm = root.get_node("/root/DataManager")
	for uid in dm.units:
		if dm.units[uid].tags.has("undead"):
			undead_unit = dm.units[uid]
			break
	_check(undead_unit != null, "an undead-tagged unit exists")
	if undead_unit:
		_check(BountySystem.recruit_discount_for(city, undead_unit) >= 10,
			"bone_fields grants 10%% undead recruit discount")
	# Cleanup so later test sections see an unmodified map
	for s in spots:
		map.get_tile(s).bounty_id = &""
