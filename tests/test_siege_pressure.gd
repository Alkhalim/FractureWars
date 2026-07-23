extends SceneTree
## Unit tests for the siege pressure model (composition weights + threshold).
## Run: godot --headless --path . -s res://tests/test_siege_pressure.gd

var _fails := 0
var _gm: Node
var _dm: Node
var _cs   # city_system

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire")
	_cs = _gm.city_system

	# Composition ordering: siege engine > baseline infantry > light raider
	var w_engine: float = _cs._army_siege_weight(_make_army(&"empire", [&"marching_bastion"]))
	var w_base: float = _cs._army_siege_weight(_make_army(&"empire", [&"legionary"]))
	var w_light: float = _cs._army_siege_weight(_make_army(&"gladehost", [&"hawk_scout"]))
	_check(w_engine > w_base, "engine weight > baseline (%f > %f)" % [w_engine, w_base])
	_check(w_base > w_light, "baseline weight > light (%f > %f)" % [w_base, w_light])
	_check(abs(w_base - _cs.SIEGE_FACTOR_BASE) < 0.001, "infantry weight == base factor")
	_check(_cs._army_siege_weight(_make_army(&"empire", [])) == 0.0, "empty army weight is 0")

	# Threshold on a fresh empire city is the base 4 (no watchtower, no def research)
	var any_city: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			any_city = c
			break
	_check(any_city != null, "found an empire city")
	_check(_cs.get_siege_threshold(any_city) == 4, "base siege threshold is 4")

	# Pressure API on a besieged city
	any_city.is_under_siege = true
	any_city.siege_faction = &"skulloath"
	any_city.siege_turns = 0.0

	_cs.add_siege_pressure(any_city, 1.5)
	_check(abs(any_city.siege_turns - 1.5) < 0.001, "add_siege_pressure adds")
	_cs.add_siege_pressure(any_city, -10.0)
	_check(any_city.siege_turns == 0.0, "add_siege_pressure floors at 0")

	any_city.siege_turns = 0.0
	_cs.award_siege_overrun(any_city)
	_check(abs(any_city.siege_turns - _cs.SIEGE_OVERRUN_BONUS) < 0.001, "overrun awards +2.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, false, 0.8, 0.0)   # besieger wins outright
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_WIN)) < 0.001, "relief win +1.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, true, 0.9, 0.5)    # both survive, big gap -> point win
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_WIN)) < 0.001, "point win +1.0")

	any_city.siege_turns = 1.0
	_cs.award_siege_battle(any_city, true, true, 0.6, 0.55)   # both survive, small gap -> stalemate
	_check(abs(any_city.siege_turns - (1.0 + _cs.SIEGE_RELIEF_STALEMATE)) < 0.001, "stalemate +0.4")

	any_city.siege_turns = 5.0
	_cs.award_siege_battle(any_city, false, true, 0.0, 0.7)   # besieger routed
	_check(abs(any_city.siege_turns - (5.0 - _cs.SIEGE_RELIEF_LOSS)) < 0.001, "relief loss -2.0")

	# Cleanup so later steps see a clean city
	any_city.is_under_siege = false
	any_city.siege_faction = &""
	any_city.siege_turns = 0.0

	if _fails == 0:
		print("SIEGE TEST PASSED")
		quit(0)
	else:
		print("SIEGE TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

# Build a detached army of the given unit ids at a hex (not registered in state).
func _make_army(fid: StringName, unit_ids: Array, hex := Vector2i(0, 0)) -> ArmyState:
	var a := ArmyState.new()
	a.army_id = &"__test_army_%d" % randi()
	a.faction_id = fid
	a.hex_pos = hex
	for uid in unit_ids:
		var ud: UnitData = _dm.get_unit(uid)
		var ui := UnitInstance.new()
		ui.init_from_data(ud, uid)
		a.units.append(ui)
	return a
