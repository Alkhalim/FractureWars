extends SceneTree
## Task 1 of the Building Rebalance plan: user-directed data retunes
## (grotto, ironworks, shrine, jade forge) + the chitin garrison bug.
## Run: godot --headless --path . -s res://tests/test_building_rebalance.gd
##
## Data-only assertions: no new_game() needed, DataManager loads buildings
## in its own _ready().

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")

	# ── mushroom_grotto: cash-crop pick vs harvest_clearing's food14/growth6 ──
	var grotto = dm.get_building(&"mushroom_grotto")
	if grotto == null:
		_check(false, "mushroom_grotto building data exists")
	else:
		_check(int(grotto.income_bonus.get(3, -1)) == 10, "mushroom_grotto food (income_bonus[3]) == 10, got %s" % [grotto.income_bonus.get(3, -1)])
		_check(int(grotto.income_bonus.get(0, -1)) == 5, "mushroom_grotto gold (income_bonus[0]) unchanged == 5, got %s" % [grotto.income_bonus.get(0, -1)])
		_check(grotto.population_growth_bonus == 0, "mushroom_grotto population_growth_bonus == 0, got %s" % [grotto.population_growth_bonus])

	# ── sporevault: food cut, gold kept, hidden region-growth layer removed ──
	var sporevault = dm.get_building(&"sporevault")
	if sporevault == null:
		_check(false, "sporevault building data exists")
	else:
		_check(int(sporevault.income_bonus.get(3, -1)) == 28, "sporevault food (income_bonus[3]) == 28, got %s" % [sporevault.income_bonus.get(3, -1)])
		_check(int(sporevault.income_bonus.get(0, -1)) == 12, "sporevault gold (income_bonus[0]) unchanged == 12, got %s" % [sporevault.income_bonus.get(0, -1)])
		_check(not sporevault.special_effects.has("region_population_growth_bonus"), "sporevault special_effects no longer has region_population_growth_bonus, got %s" % [sporevault.special_effects])

	# ── grove_ironworks: iron cut, growth twin-effect removed ──
	var ironworks = dm.get_building(&"grove_ironworks")
	if ironworks == null:
		_check(false, "grove_ironworks building data exists")
	else:
		_check(int(ironworks.income_bonus.get(1, -1)) == 20, "grove_ironworks iron (income_bonus[1]) == 20, got %s" % [ironworks.income_bonus.get(1, -1)])
		_check(ironworks.population_growth_bonus == 0, "grove_ironworks population_growth_bonus == 0, got %s" % [ironworks.population_growth_bonus])

	# ── grove_smithy: hidden region-growth layer removed, iron kept ──
	var smithy = dm.get_building(&"grove_smithy")
	if smithy == null:
		_check(false, "grove_smithy building data exists")
	else:
		_check(not smithy.special_effects.has("region_population_growth_bonus"), "grove_smithy special_effects no longer has region_population_growth_bonus, got %s" % [smithy.special_effects])
		_check(int(smithy.income_bonus.get(1, -1)) == 32, "grove_smithy iron (income_bonus[1]) unchanged == 32, got %s" % [smithy.income_bonus.get(1, -1)])

	# ── seasonal_shrine: income rebalanced (tech up, food down), growth cut ──
	var shrine = dm.get_building(&"seasonal_shrine")
	if shrine == null:
		_check(false, "seasonal_shrine building data exists")
	else:
		_check(int(shrine.income_bonus.get(2, -1)) == 8, "seasonal_shrine income_bonus[2] (tech) == 8, got %s" % [shrine.income_bonus.get(2, -1)])
		_check(int(shrine.income_bonus.get(3, -1)) == 4, "seasonal_shrine income_bonus[3] (food) == 4, got %s" % [shrine.income_bonus.get(3, -1)])
		_check(shrine.population_growth_bonus == 3, "seasonal_shrine population_growth_bonus == 3, got %s" % [shrine.population_growth_bonus])

	# ── jade_forge: growth cut, iron + loyalty kept ──
	var jade_forge = dm.get_building(&"jade_forge")
	if jade_forge == null:
		_check(false, "jade_forge building data exists")
	else:
		_check(jade_forge.population_growth_bonus == 0, "jade_forge population_growth_bonus == 0, got %s" % [jade_forge.population_growth_bonus])
		_check(int(jade_forge.income_bonus.get(1, -1)) == 18, "jade_forge iron (income_bonus[1]) unchanged == 18, got %s" % [jade_forge.income_bonus.get(1, -1)])
		_check(int(jade_forge.class_loyalty_bonus.get("artisans", -999)) == 1, "jade_forge artisans loyalty unchanged == +1, got %s" % [jade_forge.class_loyalty_bonus.get("artisans", -999)])
		_check(int(jade_forge.class_loyalty_bonus.get("captives", -999)) == -3, "jade_forge captives loyalty unchanged == -3, got %s" % [jade_forge.class_loyalty_bonus.get("captives", -999)])

	# ── hardened_chitin_wall: garrison bug fix (2 -> 0.2, was spawning +20 militia) ──
	var chitin_wall = dm.get_building(&"hardened_chitin_wall")
	if chitin_wall == null:
		_check(false, "hardened_chitin_wall building data exists")
	else:
		var garrison_bonus: float = float(chitin_wall.special_effects.get("garrison_strength_bonus", -1.0))
		_check(absf(garrison_bonus - 0.2) < 0.01, "hardened_chitin_wall garrison_strength_bonus ~= 0.2 (within 0.01), got %s" % [garrison_bonus])
		# Guard the actual militia-count math too: int(value*10) must equal +2, not +20.
		_check(int(garrison_bonus * 10) == 2, "hardened_chitin_wall militia math int(value*10) == 2 (bug was +20), got %s" % [int(garrison_bonus * 10)])

	# ── Task 2: Tainted Jade wall split — attrition traps vs endurance walls ──
	# jungle_traps/serpents_maze (traps line): besieger_attrition, no terrain lock.
	var jungle_traps = dm.get_building(&"jungle_traps")
	if jungle_traps == null:
		_check(false, "jungle_traps building data exists")
	else:
		_check(absf(float(jungle_traps.special_effects.get("besieger_attrition", -1.0)) - 2.0) < 0.001, "jungle_traps besieger_attrition == 2.0, got %s" % [jungle_traps.special_effects.get("besieger_attrition", -1.0)])
		_check(jungle_traps.required_terrain == -1, "jungle_traps has no required_terrain (available everywhere), got %s" % [jungle_traps.required_terrain])
		_check(jungle_traps.defense_bonus == 6, "jungle_traps defense_bonus unchanged == 6, got %s" % [jungle_traps.defense_bonus])

	var serpents_maze = dm.get_building(&"serpents_maze")
	if serpents_maze == null:
		_check(false, "serpents_maze building data exists")
	else:
		_check(absf(float(serpents_maze.special_effects.get("besieger_attrition", -1.0)) - 4.0) < 0.001, "serpents_maze besieger_attrition == 4.0, got %s" % [serpents_maze.special_effects.get("besieger_attrition", -1.0)])
		_check(not serpents_maze.special_effects.has("garrison_strength_bonus"), "serpents_maze special_effects no longer has garrison_strength_bonus (endurance identity moved to living walls), got %s" % [serpents_maze.special_effects])
		_check(serpents_maze.defense_bonus == 10, "serpents_maze defense_bonus unchanged == 10, got %s" % [serpents_maze.defense_bonus])

	# living_walls/thornwall (endurance line): unchanged — no besieger_attrition,
	# thornwall keeps its garrison_strength_bonus.
	var living_walls = dm.get_building(&"living_walls")
	if living_walls == null:
		_check(false, "living_walls building data exists")
	else:
		_check(living_walls.defense_bonus == 8, "living_walls defense_bonus unchanged == 8, got %s" % [living_walls.defense_bonus])
		_check(not living_walls.special_effects.has("besieger_attrition"), "living_walls has no besieger_attrition (endurance line, not traps), got %s" % [living_walls.special_effects])

	var thornwall = dm.get_building(&"thornwall")
	if thornwall == null:
		_check(false, "thornwall building data exists")
	else:
		_check(thornwall.defense_bonus == 13, "thornwall defense_bonus unchanged == 13, got %s" % [thornwall.defense_bonus])
		_check(absf(float(thornwall.special_effects.get("garrison_strength_bonus", -1.0)) - 0.1) < 0.001, "thornwall garrison_strength_bonus unchanged ~= 0.1, got %s" % [thornwall.special_effects.get("garrison_strength_bonus", -1.0)])
		_check(not thornwall.special_effects.has("besieger_attrition"), "thornwall has no besieger_attrition (endurance line, not traps), got %s" % [thornwall.special_effects])

	# ── Functional: jungle_traps bleeds besiegers 2% max_hp per UNIT per siege
	# tick (attrition 2.0 -> 2%), not a flat pool split across the army --
	# a flat pool rounds to 0 per unit once the army is large enough to
	# dilute it, which would make the wall inert for exactly the large siege
	# stacks it's meant to punish. ──
	var gm = root.get_node("/root/GameManager")
	gm.new_game(&"tainted_jade", false, 0)
	var cs = gm.city_system

	var tj_city: CityState = null
	for cid in gm.state.cities:
		var c: CityState = gm.state.cities[cid]
		if c.faction_id == &"tainted_jade":
			tj_city = c
			break

	var legionary_ud: UnitData = dm.get_unit(&"legionary")

	if tj_city == null:
		_check(false, "found a tainted_jade city for the wall-attrition test")
	elif legionary_ud == null:
		_check(false, "found legionary unit data for the wall-attrition test")
	else:
		var expected_per_unit := maxi(1, int(legionary_ud.max_hp * 2.0 * 0.01))

		# Runs one siege tick against a fresh besieging army of unit_count
		# legionaries and returns the total HP that army lost. with_wall
		# toggles jungle_traps on the besieged city so paired runs are
		# otherwise identical.
		var run_tick := func(with_wall: bool, unit_count: int) -> float:
			tj_city.is_under_siege = true
			tj_city.siege_faction = &"empire"
			tj_city.siege_turns = 0.0
			tj_city.garrison_hp_ratio = 1.0
			tj_city.buildings.clear()
			if with_wall:
				tj_city.buildings.append(&"jungle_traps")

			var army := ArmyState.new()
			army.army_id = &"__test_wall_army_%d" % randi()
			army.faction_id = &"empire"
			army.hex_pos = tj_city.hex_pos
			for i in unit_count:
				var ui := UnitInstance.new()
				ui.init_from_data(legionary_ud, &"legionary")
				army.units.append(ui)
			gm.state.armies[army.army_id] = army
			gm.movement_system.invalidate_positions()

			var hp_before := 0
			for u in army.units:
				hp_before += u.current_hp

			cs._process_sieges(&"empire")

			var hp_after := 0
			if gm.state.armies.has(army.army_id):
				for u in gm.state.armies[army.army_id].units:
					hp_after += u.current_hp
			# else: army was wiped out entirely -- 0 HP remaining.

			gm.state.armies.erase(army.army_id)
			gm.movement_system.invalidate_positions()
			tj_city.is_under_siege = false
			tj_city.siege_faction = &""
			tj_city.siege_turns = 0.0
			return float(hp_before - hp_after)

		# 1-unit differential: delta == 2% of that unit's max_hp (min 1 HP).
		var loss_control_1: float = run_tick.call(false, 1)
		var loss_with_wall_1: float = run_tick.call(true, 1)
		var delta_1 := loss_with_wall_1 - loss_control_1
		_check(absf(delta_1 - float(expected_per_unit)) < 1.0, "jungle_traps adds 2%% max_hp (%d HP) besieger loss per siege tick for a 1-unit army (delta=%f, control=%f, with_wall=%f)" % [expected_per_unit, delta_1, loss_control_1, loss_with_wall_1])
		# Double-apply guard: if a leftover old 5%-flat-per-unit path fired
		# alongside the new hook, delta would show ~7% (5%+2%) instead of 2% --
		# assert it stays near 2% only, well below what a stacked ~7% would be.
		_check(delta_1 < float(expected_per_unit) * 2.0, "jungle_traps delta stays within tolerance of 2%% max_hp only, not a double-applied ~7%% (old 5%% path + new 2%%) (delta=%f, expected~%d)" % [delta_1, expected_per_unit])

		# Large-army regression guard: a flat pool split across N units
		# rounds to 0 per unit once N is large enough to dilute it (the flaw
		# this per-unit-percentage design replaces) -- assert every unit in a
		# 10-unit army still takes real, nonzero, size-scaling damage.
		var loss_control_10: float = run_tick.call(false, 10)
		var loss_with_wall_10: float = run_tick.call(true, 10)
		var delta_10 := loss_with_wall_10 - loss_control_10
		_check(delta_10 > 0.0, "jungle_traps damage is nonzero for a 10-unit besieging army -- regression guard for the round-to-zero cliff (delta=%f)" % [delta_10])
		_check(absf(delta_10 - float(expected_per_unit * 10)) < 10.0, "jungle_traps damage scales with army size: 10-unit delta ~= 10x the per-unit share (delta=%f, expected~%d)" % [delta_10, expected_per_unit * 10])

	if _fails == 0:
		print("BUILDING REBALANCE TEST PASSED")
		quit(0)
	else:
		print("BUILDING REBALANCE TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
