extends SceneTree
## Plan B Task 12: cached trade routes and per-turn faction income totals must
## equal the old implementations.
## Run: godot --headless --path . -s res://tests/test_trade_routes.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)
	var ds = _gm.diplomacy_system

	# Create trade treaties between a few faction pairs
	var fids: Array = []
	for fid in _gm.state.faction_states:
		if not _gm.is_npc_faction(fid):
			fids.append(fid)
		if fids.size() >= 4:
			break
	ds.propose_trade_relations(fids[0], fids[1], true)
	ds.propose_trade_relations(fids[2], fids[3], true)

	# Routes: new vs verbatim-old
	var new_routes: Array[Dictionary] = ds.get_active_trade_routes()
	var old_routes: Array[Dictionary] = _ref_routes()
	if new_routes != old_routes:
		_fails += 1
		print("FAIL routes:\n  new=%s\n  old=%s" % [new_routes, old_routes])
	# Cached second read
	if ds.get_active_trade_routes() != old_routes:
		_fails += 1
		print("FAIL routes (cached)")

	# Income totals: new vs verbatim-old for several factions and types
	for fid in fids:
		var top_new: int = ds.get_top_produced_resource(fid)
		var top_old: int = _ref_top(fid)
		if top_new != top_old:
			_fails += 1
			print("FAIL top resource %s: new=%d old=%d" % [fid, top_new, top_old])
		for res_type in [0, 1, 2, 3, 4, 5, 6]:
			var inc_new: int = ds.get_faction_resource_income(fid, res_type)
			var inc_old: int = _ref_income(fid, res_type)
			if inc_new != inc_old:
				_fails += 1
				print("FAIL income %s/%d: new=%d old=%d" % [fid, res_type, inc_new, inc_old])

	if _fails == 0:
		print("TRADE ROUTES TEST PASSED")
		quit(0)
	else:
		print("TRADE ROUTES TEST FAILED (%d)" % _fails)
		quit(1)

func _ref_routes() -> Array[Dictionary]:
	# Verbatim old get_active_trade_routes
	var routes: Array[Dictionary] = []
	for treaty_id in _gm.state.diplomacy_state.treaties:
		var treaty = _gm.state.diplomacy_state.treaties[treaty_id]
		if treaty.treaty_type != Enums.TreatyType.TRADE_DEAL and treaty.treaty_type != Enums.TreatyType.TRADE_RELATIONS:
			continue
		var best_dist := 999999
		var best_a := Vector2i(-1, -1)
		var best_b := Vector2i(-1, -1)
		for city_id_a in _gm.state.cities:
			var ca: CityState = _gm.state.cities[city_id_a]
			if ca.faction_id != treaty.faction_a:
				continue
			for city_id_b in _gm.state.cities:
				var cb: CityState = _gm.state.cities[city_id_b]
				if cb.faction_id != treaty.faction_b:
					continue
				var dist := HexHelper.hex_distance(ca.hex_pos, cb.hex_pos)
				if dist < best_dist:
					best_dist = dist
					best_a = ca.hex_pos
					best_b = cb.hex_pos
		if best_a != Vector2i(-1, -1) and best_b != Vector2i(-1, -1):
			routes.append({
				faction_a = treaty.faction_a,
				faction_b = treaty.faction_b,
				city_a_hex = best_a,
				city_b_hex = best_b,
				treaty_id = treaty.treaty_id,
			})
	return routes

func _ref_top(faction_id: StringName) -> int:
	# Verbatim old get_top_produced_resource
	var totals: Dictionary = {}
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		if city.is_under_siege:
			continue
		var income: Dictionary = _gm.city_system.calculate_city_income(city)
		for res_type in income:
			if res_type == Enums.ResourceType.CAPTIVES or res_type == Enums.ResourceType.SHARD_ESSENCE:
				continue
			totals[res_type] = totals.get(res_type, 0) + income[res_type]
	var best_type: int = Enums.ResourceType.GOLD
	var best_amount: int = 0
	for res_type in totals:
		if totals[res_type] > best_amount:
			best_amount = totals[res_type]
			best_type = res_type
	return best_type

func _ref_income(faction_id: StringName, res_type: int) -> int:
	# Verbatim old get_faction_resource_income
	var total := 0
	for city_id in _gm.state.cities:
		var city: CityState = _gm.state.cities[city_id]
		if city.faction_id != faction_id or city.is_under_siege:
			continue
		var income: Dictionary = _gm.city_system.calculate_city_income(city)
		total += income.get(res_type, 0)
	return total
