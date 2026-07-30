extends SceneTree
## Unit tests for the AI siege-hold/prioritize behavior (Task 6).
## Run: godot --headless --path . -s res://tests/test_siege_ai.gd

var _fails := 0
var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)

	var _tm = root.get_node("/root/TurnManager")

	# Put a Skulloath army on an enemy (empire) city with an active siege.
	var ecity: CityState = null
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if c.faction_id == &"empire":
			ecity = c
			break
	ecity.is_under_siege = true
	ecity.siege_faction = &"skulloath"
	ecity.siege_turns = 2.0

	var sieger := _make_army(&"skulloath", [&"legionary", &"legionary", &"legionary"], ecity.hex_pos)
	_gm.state.armies[sieger.army_id] = sieger
	_gm.movement_system.invalidate_positions()

	_check(_tm._army_is_holding_siege(sieger), "AI recognizes an army holding a siege")
	sieger.movement_remaining = 2.0
	# The AI army loop must leave a siege-holding army in place: the function
	# should report the hold (return true) and zero movement so the caller's
	# `continue` actually skips retargeting this turn.
	var held: bool = _tm._maybe_hold_siege_or_retarget(sieger, &"skulloath")
	_check(held, "hold returns true for an army besieging an enemy city")
	_check(sieger.movement_remaining == 0.0, "hold zeroes movement so the AI loop's continue skips retargeting")

	# _nearest_own_siege_hex should locate the besieged city for the besieging
	# faction, and report "none" ((-1,-1)) for a faction with no active siege.
	_check(_tm._nearest_own_siege_hex(ecity.hex_pos + Vector2i(4, 0), &"skulloath") == ecity.hex_pos, "nearest own siege hex finds the besieged city")
	_check(_tm._nearest_own_siege_hex(ecity.hex_pos, &"empire") == Vector2i(-1, -1), "no own siege -> (-1,-1)")

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
