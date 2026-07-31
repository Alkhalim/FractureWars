extends SceneTree
## Balance Batch 2, Item 2: AI settlement founding was firing ~0-1 TOTAL
## across an entire 40-turn AI-vs-AI game (see tmp_econ_sim.gd), against a
## target of ~2-4 per faction. Diagnosis (via temporary instrumentation in
## _execute_ai_settlement_building, since removed): the dominant bottleneck
## was city.can_found_settlement being granted at game start to the PLAYER'S
## capital only -- every AI faction had to wait for its first capital
## level-up (observed ~15-20 turns in) before even ONE window opened, and
## that window is single-use until the next level-up. A secondary bug: once
## a target hex was picked, the march toward it re-checked can_afford_
## settlement() every turn and stalled indefinitely the instant gold dipped
## below the founding cost mid-route -- even though found_settlement()
## itself deducts unconditionally and never re-checks affordability.
## Run: godot --headless --path . -s res://tests/test_settlement_founding.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm = root.get_node("/root/GameManager")
	var tm = root.get_node("/root/TurnManager")

	gm.new_game(&"empire", false, 0)

	# ── Fix 1 (game_manager.gd _init_cities): every major faction's capital,
	# not just the player's, starts with the settlement-founding ability --
	# previously only true for owning_faction == player_faction_id. ──
	var majors: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"moonspear", &"thunderswarm", &"cinderguard", &"forsaken", &"ivoryscar"]
	var granted := 0
	for fid in majors:
		var fs = gm.state.faction_states.get(fid)
		if fs == null or fs.owned_cities.is_empty():
			continue
		for cid in fs.owned_cities:
			var c = gm.state.cities.get(cid)
			if c and c.is_capital:
				_check(c.can_found_settlement, "%s's capital starts with can_found_settlement == true (turn 1, not just the player's), got false" % fid)
				granted += 1
	_check(granted >= 8, "sanity: found capitals to check for a plausible number of major factions (>=8), got %d" % granted)

	# ── Fix 2 (turn_manager.gd _execute_ai_settlement_building): a PENDING
	# target keeps marching even when the faction can no longer currently
	# afford to found a NEW one -- found_settlement() deducts unconditionally
	# once the army arrives, so the walk must not stall on a live
	# affordability re-check it was never gated on to begin with. ──
	var fid2: StringName = &"skulloath"
	var fs2 = gm.state.faction_states.get(fid2)
	if fs2 == null or fs2.owned_cities.is_empty():
		_check(false, "skulloath faction state with owned cities exists (march-stall test)")
	else:
		var capital = null
		for cid in fs2.owned_cities:
			var c = gm.state.cities.get(cid)
			if c and c.is_capital:
				capital = c
				break
		var armies: Array = gm.get_faction_armies(fid2)
		if capital == null or armies.is_empty():
			_check(false, "skulloath has a capital and at least one field army (march-stall test precondition)")
		else:
			var army = armies[0]
			# Pick a target hex a few tiles away from the army so there's an
			# actual march to make (not already adjacent/there).
			var target_hex: Vector2i = Vector2i(capital.hex_pos.x + 4, capital.hex_pos.y)
			tm._ai_settlement_targets[fid2] = target_hex

			# Drain gold WELL below the founding cost -- can_afford_settlement()
			# must now be false, same as a faction whose build/recruit spending
			# ate the turn's income.
			fs2.resources[Enums.ResourceType.GOLD] = 0
			_check(not gm.can_afford_settlement(fid2), "sanity: skulloath cannot currently afford a new settlement (gold pinned to 0)")

			var pos_before: Vector2i = army.hex_pos
			var movement_before: float = army.movement_remaining
			if movement_before <= 0.0:
				army.movement_remaining = army.movement_points if "movement_points" in army else 2.0
				movement_before = army.movement_remaining

			tm._execute_ai_settlement_building(fid2)

			var moved: bool = army.hex_pos != pos_before or army.movement_remaining < movement_before
			_check(moved, "a pending settlement target still marches when gold is insufficient for a NEW one (army stayed at %s with %f movement left, unchanged)" % [pos_before, movement_before])
			_check(tm._ai_settlement_targets.has(fid2), "the pending target survives a turn where the army hasn't arrived yet")

			# Cleanup: clear the synthetic target so it doesn't leak into any
			# later state this process might inspect.
			tm._ai_settlement_targets.erase(fid2)

	# ── Quick-fix Item F: founding charges now recharge on ANY owned city's
	# level-up, not just the capital's -- previously city_system._process_upgrade
	# only set can_found_settlement=true `if city.is_capital`, so a faction's
	# non-capital cities/settlements leveling up (which happens far more often
	# across a growing empire) granted nothing, throttling foundings to ~1
	# window per faction per ~40 turns. ──
	_run_noncapital_levelup_grants_charge_test(gm)

	if _fails == 0:
		print("SETTLEMENT FOUNDING TEST PASSED")
		quit(0)
	else:
		print("SETTLEMENT FOUNDING TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)

## A non-capital city (regular city OR settlement) that completes a level-up
## must grant can_found_settlement, exactly like a capital does -- the
## generalized parity rule from city_system._process_upgrade.
func _run_noncapital_levelup_grants_charge_test(gm) -> void:
	gm.new_game(&"empire", false, 7)
	var fs: FactionState = gm.state.faction_states.get(&"empire")
	if fs == null:
		_check(false, "empire faction state exists (non-capital level-up test)")
		return
	var non_capital: CityState = null
	for cid in fs.owned_cities:
		var c: CityState = gm.state.cities.get(cid)
		if c and not c.is_capital:
			non_capital = c
			break
	if non_capital == null:
		_check(false, "empire owns at least one non-capital city at game start (non-capital level-up test precondition)")
		return

	non_capital.can_found_settlement = false
	non_capital.upgrade_turns_remaining = 1
	var level_before := non_capital.level

	gm.city_system._process_upgrade(non_capital)

	_check(non_capital.level == level_before + 1, "non-capital city leveled up (before=%d, after=%d)" % [level_before, non_capital.level])
	_check(non_capital.can_found_settlement, "non-capital city's level-up granted can_found_settlement (is_capital=%s)" % non_capital.is_capital)
