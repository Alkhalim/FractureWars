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

	# ── Task 3: growth purge on industry + growth variance on farms ──
	_run_task3_growth_purge(dm)

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

## Returns the income_bonus key with the highest value for a building, or -1
## if income_bonus is empty. Ties keep whichever key Dictionary iteration
## visits first (insertion order, i.e. .tres declaration order).
func _largest_income_key(b: BuildingData) -> int:
	var largest_key := -1
	var largest_val := -2147483648
	for k in b.income_bonus.keys():
		var v := int(b.income_bonus[k])
		if v > largest_val:
			largest_val = v
			largest_key = int(k)
	return largest_key

func _run_task3_growth_purge(dm) -> void:
	const IRON := 1
	const FOOD := 3

	var industrial_re := RegEx.new()
	industrial_re.compile("(?i)(mine|forge|quarry|foundry|smelter|pit|kiln|works)")

	# ── INVARIANT: every building whose id/name matches the industrial regex
	# AND whose largest income key is IRON must grant zero population growth,
	# directly or via the hidden region_population_growth_bonus layer. This is
	# the authority for the sweep -- it iterates every loaded building, not a
	# fixed list, so it also catches any straggler the audit missed. ──
	var swept := 0
	for id in dm.buildings.keys():
		var b: BuildingData = dm.buildings[id]
		var name_hit: bool = industrial_re.search(String(id)) != null or industrial_re.search(b.display_name) != null
		if not name_hit:
			continue
		if _largest_income_key(b) != IRON:
			continue
		swept += 1
		_check(b.population_growth_bonus == 0, "%s (industrial, iron-primary) population_growth_bonus == 0, got %s" % [id, b.population_growth_bonus])
		_check(not b.special_effects.has("region_population_growth_bonus"), "%s (industrial, iron-primary) special_effects has no region_population_growth_bonus, got %s" % [id, b.special_effects])
	_check(swept >= 25, "invariant sweep matched a plausible number of iron-primary industrial buildings (>=25), got %d" % swept)

	# ── Stragglers that dodge the naming regex (id has no mine/forge/quarry/
	# foundry/smelter/pit/kiln/works substring) but are iron-primary industrial
	# buildings all the same -- caught by an exhaustive by-income scan, not by
	# name, during the sweep for this task. Pinned explicitly since the
	# automated regex above cannot see them. ──
	for straggler_id in [&"silver_vein", &"magma_vent", &"imperial_work_yard", &"grove_smithy"]:
		var b: BuildingData = dm.get_building(straggler_id)
		if b == null:
			_check(false, "%s building data exists (straggler check)" % straggler_id)
			continue
		_check(_largest_income_key(b) == IRON, "%s is iron-primary (sanity check for straggler pin), largest key got %s" % [straggler_id, _largest_income_key(b)])
		_check(b.population_growth_bonus == 0, "%s (straggler) population_growth_bonus == 0, got %s" % [straggler_id, b.population_growth_bonus])
		_check(not b.special_effects.has("region_population_growth_bonus"), "%s (straggler) special_effects has no region_population_growth_bonus, got %s" % [straggler_id, b.special_effects])

	# ── sunfire_forge: also strip the capstone-grade army_attack_bonus a
	# tier-1 economy building had no business carrying. solar_citadel (its
	# unrelated late-game counterpart) keeps its own +2 untouched. ──
	var sunfire_forge = dm.get_building(&"sunfire_forge")
	if sunfire_forge == null:
		_check(false, "sunfire_forge building data exists")
	else:
		_check(not sunfire_forge.special_effects.has("army_attack_bonus"), "sunfire_forge special_effects has no army_attack_bonus, got %s" % [sunfire_forge.special_effects])
	var solar_citadel = dm.get_building(&"solar_citadel")
	if solar_citadel != null:
		_check(int(solar_citadel.special_effects.get("army_attack_bonus", -1)) == 2, "solar_citadel keeps its own army_attack_bonus == 2 (unrelated capstone), got %s" % [solar_citadel.special_effects.get("army_attack_bonus", -1)])

	# ── Cinderguard iron VALUES are locked -- Task 3 strips only growth
	# fields, never touches income_bonus, on these five buildings. ──
	var locked_iron_values := {
		&"ember_foundry": 45,
		&"volcanic_smelter": 35,
		&"cinder_mine": 20,
		&"magma_vent": 16,
		&"molten_core_forge": 28,
	}
	for cg_id in locked_iron_values.keys():
		var b: BuildingData = dm.get_building(cg_id)
		if b == null:
			_check(false, "%s building data exists (cinderguard locked-value check)" % cg_id)
		else:
			_check(int(b.income_bonus.get(IRON, -1)) == locked_iron_values[cg_id], "%s iron income_bonus[1] unchanged == %d, got %s" % [cg_id, locked_iron_values[cg_id], b.income_bonus.get(IRON, -1)])

	# ── Negative-growth "sacrifice" buildings are a deliberate design (captives
	# consumed for materials cost population), not the "industry grants growth"
	# nonsense this task purges. They must NOT be zeroed out by an overzealous
	# future sweep. ──
	var blood_altar = dm.get_building(&"blood_altar")
	if blood_altar != null:
		_check(blood_altar.population_growth_bonus == -2, "blood_altar keeps its deliberate population_growth_bonus == -2 (sacrifice mechanic, not a growth grant), got %s" % [blood_altar.population_growth_bonus])
	var crimson_altar = dm.get_building(&"crimson_altar")
	if crimson_altar != null:
		_check(crimson_altar.population_growth_bonus == -3, "crimson_altar keeps its deliberate population_growth_bonus == -3 (sacrifice mechanic, not a growth grant), got %s" % [crimson_altar.population_growth_bonus])

	# ── Growth variance: every tier-2+ building whose largest income key is
	# FOOD and which carried region_population_growth_bonus:1 is raised to 2,
	# making granaries/orchards the real growth engines. Markets/temples
	# (gold-primary) and Forsaken's bespoke 3/5 survivors_* buildings are
	# untouched. Swept by income shape, not a fixed list. ──
	var food_raised := 0
	for id in dm.buildings.keys():
		var b: BuildingData = dm.buildings[id]
		if b.required_capital_level < 2:
			continue
		if not b.special_effects.has("region_population_growth_bonus"):
			continue
		if _largest_income_key(b) != FOOD:
			continue
		food_raised += 1
		_check(int(b.special_effects.get("region_population_growth_bonus")) == 2, "%s (food-primary, tier2+) region_population_growth_bonus == 2, got %s" % [id, b.special_effects.get("region_population_growth_bonus")])
	_check(food_raised >= 10, "growth-variance sweep raised a plausible number of food-primary buildings (>=10), got %d" % food_raised)

	# ── Spot pin: a named granary-class building explicitly at 2. ──
	var imperial_granary = dm.get_building(&"imperial_granary")
	if imperial_granary == null:
		_check(false, "imperial_granary building data exists")
	else:
		_check(int(imperial_granary.special_effects.get("region_population_growth_bonus", -1)) == 2, "imperial_granary (granary-class) region_population_growth_bonus == 2, got %s" % [imperial_granary.special_effects.get("region_population_growth_bonus", -1)])

	# ── Forsaken's survivors_gathering/survivors_stronghold keep their bespoke
	# 3/5 (not part of the generic food-variance raise, not zeroed either). ──
	var survivors_gathering = dm.get_building(&"survivors_gathering")
	if survivors_gathering != null:
		_check(int(survivors_gathering.special_effects.get("region_population_growth_bonus", -1)) == 3, "survivors_gathering keeps region_population_growth_bonus == 3, got %s" % [survivors_gathering.special_effects.get("region_population_growth_bonus", -1)])
	var survivors_stronghold = dm.get_building(&"survivors_stronghold")
	if survivors_stronghold != null:
		_check(int(survivors_stronghold.special_effects.get("region_population_growth_bonus", -1)) == 5, "survivors_stronghold keeps region_population_growth_bonus == 5, got %s" % [survivors_stronghold.special_effects.get("region_population_growth_bonus", -1)])

	# ── Markets/temples (gold-primary) keep their flat +1 -- the variance rule
	# only touches food-primary buildings. ──
	var merchant_guild = dm.get_building(&"merchant_guild")
	if merchant_guild != null:
		_check(int(merchant_guild.special_effects.get("region_population_growth_bonus", -1)) == 1, "merchant_guild (gold-primary market) keeps region_population_growth_bonus == 1, got %s" % [merchant_guild.special_effects.get("region_population_growth_bonus", -1)])

	# ── Wood-primary "works" buildings are out of this task's scope (only iron
	# and food are addressed) -- guard that they were left alone. ──
	var imperial_timberworks = dm.get_building(&"imperial_timberworks")
	if imperial_timberworks != null:
		_check(int(imperial_timberworks.special_effects.get("region_population_growth_bonus", -1)) == 1, "imperial_timberworks (wood-primary, out of scope) unchanged region_population_growth_bonus == 1, got %s" % [imperial_timberworks.special_effects.get("region_population_growth_bonus", -1)])
