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
	_gm.new_game(&"empire", false, 0)
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

	# Full siege tick: besieger present fills by base*weight; garrison declines.
	var tcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			tcity = c
			break
	tcity.is_under_siege = true
	tcity.siege_faction = &"skulloath"
	tcity.siege_turns = 0.0
	tcity.garrison_hp_ratio = 1.0

	var besieger := _make_army(&"skulloath", [&"legionary"], tcity.hex_pos)
	_gm.state.armies[besieger.army_id] = besieger
	_gm.movement_system.invalidate_positions()

	_cs._process_sieges(&"skulloath")
	_check(abs(tcity.siege_turns - _cs.SIEGE_FILL_BASE) < 0.001, "present infantry fills by base (%f)" % tcity.siege_turns)
	_check(tcity.garrison_hp_ratio < 1.0, "besieged garrison declines while sieged")

	# One more present tick so accumulated pressure (1.5) can survive a single
	# absence decay (1.0) without hitting 0 -- SIEGE_FILL_BASE (0.75) times a
	# baseline weight of 1.0 is below SIEGE_DECAY_ABSENT (1.0), so a lone fill
	# tick can never outlast one decay tick; needed for the "stays active"
	# check below to be meaningful. See task-3-report.md for details.
	_cs._process_sieges(&"skulloath")

	# Besieger leaves -> next tick decays; still under siege until it hits 0.
	_gm.state.armies.erase(besieger.army_id)
	_gm.movement_system.invalidate_positions()
	var before := tcity.siege_turns
	_cs._process_sieges(&"skulloath")
	_check(tcity.siege_turns < before, "absent besieger decays pressure")
	_check(tcity.is_under_siege, "siege stays active while pressure > 0")

	# Decay all the way to 0 lifts the siege.
	tcity.siege_turns = 0.5
	_cs._process_sieges(&"skulloath")
	_check(not tcity.is_under_siege, "siege lifts when pressure reaches 0")

	# Reaching threshold captures the city for the besieger.
	tcity.is_under_siege = true
	tcity.siege_faction = &"skulloath"
	tcity.siege_turns = float(_cs.get_siege_threshold(tcity))
	var besieger2 := _make_army(&"skulloath", [&"legionary"], tcity.hex_pos)
	_gm.state.armies[besieger2.army_id] = besieger2
	_gm.movement_system.invalidate_positions()
	_cs._process_sieges(&"skulloath")
	_check(tcity.faction_id == &"skulloath", "city captured at threshold")
	_check(not tcity.is_under_siege, "siege cleared after capture")

	# Scripted garrison assault: overwhelming attacker overruns a garrison,
	# starting a siege with >= overrun pressure.
	var vcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"independent":
			vcity = c
			break
	if vcity != null:
		vcity.is_under_siege = false
		vcity.siege_turns = 0.0
		vcity.garrison_hp_ratio = 1.0
		var garrison: ArmyState = _cs.create_garrison_army(vcity)
		_gm.state.armies[garrison.army_id] = garrison
		# Overwhelming attacker: many elite units.
		var atk := _make_army(&"empire", [&"elite_legionaries", &"elite_legionaries", &"elite_legionaries", &"elite_legionaries", &"marching_bastion"], vcity.hex_pos)
		_gm.state.armies[atk.army_id] = atk
		_gm.movement_system.invalidate_positions()
		var _br: Node = root.get_node("/root/BattleResolver")
		_br.auto_resolve(atk.army_id, garrison.army_id, vcity.hex_pos)
		_check(vcity.is_under_siege, "scripted assault started a siege")
		_check(vcity.siege_faction == &"empire", "besieger is the attacker")
		_check(vcity.siege_turns >= _cs.SIEGE_OVERRUN_BONUS - 0.001, "overrun awarded pressure (%f)" % vcity.siege_turns)
	else:
		print("NOTE: no independent city to script an assault; skipping smoke check")

	# Leaving a besieged hex must NOT instantly end the siege.
	var dcity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			dcity = c
			break
	dcity.is_under_siege = true
	dcity.siege_faction = &"skulloath"
	dcity.siege_turns = 3.0
	var leaver := _make_army(&"skulloath", [&"legionary"], dcity.hex_pos)
	_gm.state.armies[leaver.army_id] = leaver
	_gm.movement_system.invalidate_positions()
	# Call the departure check while army is still at the besieged hex.
	# This simulates the call in move_army() before the position update.
	_gm._check_siege_departure(leaver)
	# Now move the army away
	leaver.hex_pos = dcity.hex_pos + Vector2i(1, 0)
	_gm.movement_system.invalidate_positions()
	_check(dcity.is_under_siege, "departure does not instantly break the siege")
	_check(abs(dcity.siege_turns - 3.0) < 0.001, "departure leaves pressure intact (decay handles it later)")
	dcity.is_under_siege = false
	dcity.siege_faction = &""
	dcity.siege_turns = 0.0

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
