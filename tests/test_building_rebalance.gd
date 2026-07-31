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

	# ── Task 4: pure-vs-hybrid split on twin food/iron chains ──
	_run_task4_pure_hybrid_split(dm)

	# ── Task 5: tail cleanup (wall chain, payback fix, unlock move, doctrine gate) ──
	_run_task5_tail_cleanup(dm)

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
	# untouched. Swept by income shape, not a fixed list.
	# Threshold lowered 10->9 by Task 4: underground_cistern, blessed_springs,
	# highland_ranches, and terraced_gardens (all food-primary, tier2+ HYBRID
	# upgrades) had region_population_growth_bonus stripped entirely as part
	# of "hybrid loses ALL growth" -- 4 fewer eligible buildings, floor
	# adjusted to match the new, intentional count (currently exactly 9) with
	# no slack, so any future straggler still trips this guard. ──
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
	_check(food_raised >= 9, "growth-variance sweep raised a plausible number of food-primary buildings (>=9, was >=10 pre-Task4), got %d" % food_raised)

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

## Task 4: pure-vs-hybrid differentiation on the twin tier-1 food/iron chains
## (plus their tier-2 upgrades). PURE keeps its full primary yield (and, for
## food, its growth); HYBRID loses all growth and gets its secondary income
## bumped -- and where its primary was reduced, drops to ~70% of its paired
## PURE's primary. The generic invariant checked for every pair: hybrid
## population_growth_bonus == 0, and pure.primary >= 1.25x hybrid.primary
## (checked as pure*4 >= hybrid*5 to stay in integer math).
func _run_task4_pure_hybrid_split(dm) -> void:
	const GOLD := 0
	const IRON := 1
	const FOOD := 3
	const WOOD := 5

	# ── Generic per-pair invariant, tier-1: [pure_id, hybrid_id, primary_key] ──
	var tier1_pairs := [
		[&"dust_fields", &"desert_well", FOOD],
		[&"pilgrim_gardens", &"sacred_oasis", FOOD],
		[&"highland_terrace", &"mountain_herds", FOOD],
		[&"hunting_ground", &"vine_shelter", FOOD],
		[&"bone_quarry", &"sandstone_pit", IRON],
		[&"silver_vein", &"ice_quarry", IRON],
		[&"sunfire_forge", &"clay_kiln", IRON],
		[&"thunderpeak_mine", &"stone_quarry", IRON],
		# cinder_mine/magma_vent excluded here: iron values are LOCKED by design
		# (20/16) and differentiated via secondary only -- pinned separately below.
	]
	# ── Same invariant, tier-2 upgrades of each hybrid above (pure tier-2 sibling
	# in column 0) -- primary scaled the same ~0.7 way, growth removed. ──
	var tier2_pairs := [
		[&"oasis_gardens", &"underground_cistern", FOOD],
		[&"blessed_harvest", &"blessed_springs", FOOD],
		[&"storm_harvest", &"highland_ranches", FOOD],
		[&"ancient_canopy", &"terraced_gardens", FOOD],
		[&"relic_smelter", &"petrified_quarry", IRON],
		[&"moonsilver_forge", &"moonstone_mine", IRON],
		[&"solar_foundry", &"adobe_works", IRON],
		[&"storm_forge", &"mountain_stoneworks", IRON],
	]
	var checked := 0
	for pair_list in [tier1_pairs, tier2_pairs]:
		for pair in pair_list:
			var pure_id: StringName = pair[0]
			var hybrid_id: StringName = pair[1]
			var key: int = pair[2]
			var pure_b: BuildingData = dm.get_building(pure_id)
			var hybrid_b: BuildingData = dm.get_building(hybrid_id)
			if pure_b == null or hybrid_b == null:
				_check(false, "%s/%s pair building data exists" % [pure_id, hybrid_id])
				continue
			checked += 1
			var pure_primary := int(pure_b.income_bonus.get(key, -1))
			var hybrid_primary := int(hybrid_b.income_bonus.get(key, -1))
			_check(hybrid_b.population_growth_bonus == 0, "%s (hybrid) population_growth_bonus == 0, got %s" % [hybrid_id, hybrid_b.population_growth_bonus])
			_check(pure_primary * 4 >= hybrid_primary * 5, "%s pure primary (%d) >= 1.25x %s hybrid primary (%d)" % [pure_id, pure_primary, hybrid_id, hybrid_primary])
	_check(checked == 16, "Task 4 invariant swept all 16 tier-1+tier-2 pairs, got %d" % checked)

	# ── Exact before->after pins, tier-1 ──

	# ivoryscar food: dust_fields PURE unchanged (12/growth5); desert_well HYBRID
	# cut 14->8, growth 5->0, gold secondary +2 (5->7).
	var dust_fields = dm.get_building(&"dust_fields")
	if dust_fields != null:
		_check(int(dust_fields.income_bonus.get(FOOD, -1)) == 12, "dust_fields (pure) food unchanged == 12, got %s" % [dust_fields.income_bonus.get(FOOD, -1)])
		_check(dust_fields.population_growth_bonus == 5, "dust_fields (pure) growth unchanged == 5, got %s" % [dust_fields.population_growth_bonus])
	var desert_well = dm.get_building(&"desert_well")
	if desert_well != null:
		_check(int(desert_well.income_bonus.get(FOOD, -1)) == 8, "desert_well (hybrid) food == 8 (was 14), got %s" % [desert_well.income_bonus.get(FOOD, -1)])
		_check(int(desert_well.income_bonus.get(GOLD, -1)) == 7, "desert_well (hybrid) gold == 7 (was 5, +2), got %s" % [desert_well.income_bonus.get(GOLD, -1)])
		_check(desert_well.population_growth_bonus == 0, "desert_well (hybrid) growth == 0 (was 5), got %s" % [desert_well.population_growth_bonus])

	# sunblessed food: pilgrim_gardens PURE unchanged (19/growth5); sacred_oasis
	# HYBRID cut 14->13, growth already 0, gold secondary +2 (12->14).
	var pilgrim_gardens = dm.get_building(&"pilgrim_gardens")
	if pilgrim_gardens != null:
		_check(int(pilgrim_gardens.income_bonus.get(FOOD, -1)) == 19, "pilgrim_gardens (pure) food unchanged == 19, got %s" % [pilgrim_gardens.income_bonus.get(FOOD, -1)])
		_check(pilgrim_gardens.population_growth_bonus == 5, "pilgrim_gardens (pure) growth unchanged == 5, got %s" % [pilgrim_gardens.population_growth_bonus])
	var sacred_oasis = dm.get_building(&"sacred_oasis")
	if sacred_oasis != null:
		_check(int(sacred_oasis.income_bonus.get(FOOD, -1)) == 13, "sacred_oasis (hybrid) food == 13 (was 14), got %s" % [sacred_oasis.income_bonus.get(FOOD, -1)])
		_check(int(sacred_oasis.income_bonus.get(GOLD, -1)) == 14, "sacred_oasis (hybrid) gold == 14 (was 12, +2), got %s" % [sacred_oasis.income_bonus.get(GOLD, -1)])
		_check(sacred_oasis.population_growth_bonus == 0, "sacred_oasis (hybrid) growth == 0 (already was), got %s" % [sacred_oasis.population_growth_bonus])

	# thunderswarm food: highland_terrace PURE unchanged (14/growth5);
	# mountain_herds HYBRID cut 16->10, growth 5->0, gold secondary +2 (5->7).
	var highland_terrace = dm.get_building(&"highland_terrace")
	if highland_terrace != null:
		_check(int(highland_terrace.income_bonus.get(FOOD, -1)) == 14, "highland_terrace (pure) food unchanged == 14, got %s" % [highland_terrace.income_bonus.get(FOOD, -1)])
		_check(highland_terrace.population_growth_bonus == 5, "highland_terrace (pure) growth unchanged == 5, got %s" % [highland_terrace.population_growth_bonus])
	var mountain_herds = dm.get_building(&"mountain_herds")
	if mountain_herds != null:
		_check(int(mountain_herds.income_bonus.get(FOOD, -1)) == 10, "mountain_herds (hybrid) food == 10 (was 16), got %s" % [mountain_herds.income_bonus.get(FOOD, -1)])
		_check(int(mountain_herds.income_bonus.get(GOLD, -1)) == 7, "mountain_herds (hybrid) gold == 7 (was 5, +2), got %s" % [mountain_herds.income_bonus.get(GOLD, -1)])
		_check(mountain_herds.population_growth_bonus == 0, "mountain_herds (hybrid) growth == 0 (was 5), got %s" % [mountain_herds.population_growth_bonus])

	# tainted_jade food: hunting_ground PURE unchanged (18/growth4, explicit);
	# vine_shelter HYBRID's primary (8) already satisfies the 1.25x invariant
	# against 18 (2.25x), so it is left unchanged -- only growth (5->0) and
	# wood secondary (+2, 12->14) move. jade_market (separate gold-identity
	# building, not part of this pair) growth 4->1.
	var hunting_ground = dm.get_building(&"hunting_ground")
	if hunting_ground != null:
		_check(int(hunting_ground.income_bonus.get(FOOD, -1)) == 18, "hunting_ground (pure) food unchanged == 18, got %s" % [hunting_ground.income_bonus.get(FOOD, -1)])
		_check(hunting_ground.population_growth_bonus == 4, "hunting_ground (pure) growth unchanged == 4, got %s" % [hunting_ground.population_growth_bonus])
	var vine_shelter = dm.get_building(&"vine_shelter")
	if vine_shelter != null:
		_check(int(vine_shelter.income_bonus.get(FOOD, -1)) == 8, "vine_shelter (hybrid) food unchanged == 8 (already satisfied invariant), got %s" % [vine_shelter.income_bonus.get(FOOD, -1)])
		_check(int(vine_shelter.income_bonus.get(WOOD, -1)) == 14, "vine_shelter (hybrid) wood == 14 (was 12, +2), got %s" % [vine_shelter.income_bonus.get(WOOD, -1)])
		_check(vine_shelter.population_growth_bonus == 0, "vine_shelter (hybrid) growth == 0 (was 5), got %s" % [vine_shelter.population_growth_bonus])
	var jade_market = dm.get_building(&"jade_market")
	if jade_market != null:
		_check(jade_market.population_growth_bonus == 1, "jade_market growth == 1 (was 4, A3 gold-identity trim), got %s" % [jade_market.population_growth_bonus])
		_check(int(jade_market.income_bonus.get(GOLD, -1)) == 25, "jade_market gold unchanged == 25 (its identity), got %s" % [jade_market.income_bonus.get(GOLD, -1)])

	# ivoryscar iron: bone_quarry PURE unchanged (25); sandstone_pit HYBRID
	# cut 22->18, wood secondary +2 (10->12). Growth was already 0 on both
	# (Task 3 iron-primary purge) -- verify Task 4 did not re-add it.
	var bone_quarry = dm.get_building(&"bone_quarry")
	if bone_quarry != null:
		_check(int(bone_quarry.income_bonus.get(IRON, -1)) == 25, "bone_quarry (pure) iron unchanged == 25, got %s" % [bone_quarry.income_bonus.get(IRON, -1)])
		_check(bone_quarry.population_growth_bonus == 0, "bone_quarry (pure) growth stays 0, got %s" % [bone_quarry.population_growth_bonus])
	var sandstone_pit = dm.get_building(&"sandstone_pit")
	if sandstone_pit != null:
		_check(int(sandstone_pit.income_bonus.get(IRON, -1)) == 18, "sandstone_pit (hybrid) iron == 18 (was 22), got %s" % [sandstone_pit.income_bonus.get(IRON, -1)])
		_check(int(sandstone_pit.income_bonus.get(WOOD, -1)) == 12, "sandstone_pit (hybrid) wood == 12 (was 10, +2), got %s" % [sandstone_pit.income_bonus.get(WOOD, -1)])
		_check(sandstone_pit.population_growth_bonus == 0, "sandstone_pit (hybrid) growth stays 0 (not re-added), got %s" % [sandstone_pit.population_growth_bonus])

	# moonspear iron: silver_vein PURE unchanged (30); ice_quarry HYBRID cut
	# 25->21, wood secondary +2 (8->10).
	var silver_vein = dm.get_building(&"silver_vein")
	if silver_vein != null:
		_check(int(silver_vein.income_bonus.get(IRON, -1)) == 30, "silver_vein (pure) iron unchanged == 30, got %s" % [silver_vein.income_bonus.get(IRON, -1)])
		_check(silver_vein.population_growth_bonus == 0, "silver_vein (pure) growth stays 0, got %s" % [silver_vein.population_growth_bonus])
	var ice_quarry = dm.get_building(&"ice_quarry")
	if ice_quarry != null:
		_check(int(ice_quarry.income_bonus.get(IRON, -1)) == 21, "ice_quarry (hybrid) iron == 21 (was 25), got %s" % [ice_quarry.income_bonus.get(IRON, -1)])
		_check(int(ice_quarry.income_bonus.get(WOOD, -1)) == 10, "ice_quarry (hybrid) wood == 10 (was 8, +2), got %s" % [ice_quarry.income_bonus.get(WOOD, -1)])
		_check(ice_quarry.population_growth_bonus == 0, "ice_quarry (hybrid) growth stays 0 (not re-added), got %s" % [ice_quarry.population_growth_bonus])

	# sunblessed iron: sunfire_forge PURE unchanged (25); clay_kiln HYBRID's
	# primary (10) already satisfies the 1.25x invariant against 25 (2.5x), so
	# it is left unchanged -- only wood secondary moves (+2, 18->20).
	var sunfire_forge = dm.get_building(&"sunfire_forge")
	if sunfire_forge != null:
		_check(int(sunfire_forge.income_bonus.get(IRON, -1)) == 25, "sunfire_forge (pure) iron unchanged == 25, got %s" % [sunfire_forge.income_bonus.get(IRON, -1)])
		_check(sunfire_forge.population_growth_bonus == 0, "sunfire_forge (pure) growth stays 0, got %s" % [sunfire_forge.population_growth_bonus])
	var clay_kiln = dm.get_building(&"clay_kiln")
	if clay_kiln != null:
		_check(int(clay_kiln.income_bonus.get(IRON, -1)) == 10, "clay_kiln (hybrid) iron unchanged == 10 (already satisfied invariant), got %s" % [clay_kiln.income_bonus.get(IRON, -1)])
		_check(int(clay_kiln.income_bonus.get(WOOD, -1)) == 20, "clay_kiln (hybrid) wood == 20 (was 18, +2), got %s" % [clay_kiln.income_bonus.get(WOOD, -1)])
		_check(clay_kiln.population_growth_bonus == 0, "clay_kiln (hybrid) growth stays 0 (not re-added), got %s" % [clay_kiln.population_growth_bonus])

	# thunderswarm iron: thunderpeak_mine PURE unchanged (35); stone_quarry
	# HYBRID cut 28->25, wood secondary +2 (10->12).
	var thunderpeak_mine = dm.get_building(&"thunderpeak_mine")
	if thunderpeak_mine != null:
		_check(int(thunderpeak_mine.income_bonus.get(IRON, -1)) == 35, "thunderpeak_mine (pure) iron unchanged == 35, got %s" % [thunderpeak_mine.income_bonus.get(IRON, -1)])
		_check(thunderpeak_mine.population_growth_bonus == 0, "thunderpeak_mine (pure) growth stays 0, got %s" % [thunderpeak_mine.population_growth_bonus])
	var stone_quarry = dm.get_building(&"stone_quarry")
	if stone_quarry != null:
		_check(int(stone_quarry.income_bonus.get(IRON, -1)) == 25, "stone_quarry (hybrid) iron == 25 (was 28), got %s" % [stone_quarry.income_bonus.get(IRON, -1)])
		_check(int(stone_quarry.income_bonus.get(WOOD, -1)) == 12, "stone_quarry (hybrid) wood == 12 (was 10, +2), got %s" % [stone_quarry.income_bonus.get(WOOD, -1)])
		_check(stone_quarry.population_growth_bonus == 0, "stone_quarry (hybrid) growth stays 0 (not re-added), got %s" % [stone_quarry.population_growth_bonus])

	# cinderguard iron EXCEPTION: cinder_mine/magma_vent iron VALUES are LOCKED
	# (20/16, already pinned by Task 3) -- Task 4 must not touch them. Only
	# magma_vent's wood secondary moves, and by +4 (not +2) per the plan's
	# explicit exception carve-out.
	var cinder_mine = dm.get_building(&"cinder_mine")
	if cinder_mine != null:
		_check(int(cinder_mine.income_bonus.get(IRON, -1)) == 20, "cinder_mine (pure, locked) iron unchanged == 20, got %s" % [cinder_mine.income_bonus.get(IRON, -1)])
		_check(not cinder_mine.income_bonus.has(WOOD), "cinder_mine (pure) has no wood income (stays pure, single-income), got %s" % [cinder_mine.income_bonus])
		_check(cinder_mine.population_growth_bonus == 0, "cinder_mine (pure) growth stays 0, got %s" % [cinder_mine.population_growth_bonus])
	var magma_vent = dm.get_building(&"magma_vent")
	if magma_vent != null:
		_check(int(magma_vent.income_bonus.get(IRON, -1)) == 16, "magma_vent (hybrid, locked) iron unchanged == 16, got %s" % [magma_vent.income_bonus.get(IRON, -1)])
		_check(int(magma_vent.income_bonus.get(WOOD, -1)) == 14, "magma_vent (hybrid) wood == 14 (was 10, +4 exception), got %s" % [magma_vent.income_bonus.get(WOOD, -1)])
		_check(magma_vent.population_growth_bonus == 0, "magma_vent (hybrid) growth stays 0 (not re-added), got %s" % [magma_vent.population_growth_bonus])

	# ── Exact before->after pins, tier-2 upgrades of each hybrid ──
	# (pure siblings' tier-2s -- oasis_gardens, blessed_harvest, storm_harvest,
	# ancient_canopy, relic_smelter, moonsilver_forge, solar_foundry,
	# storm_forge -- are unmodified by Task 4 and are not re-pinned here;
	# they're covered by the generic invariant sweep above.)

	var underground_cistern = dm.get_building(&"underground_cistern")
	if underground_cistern != null:
		_check(int(underground_cistern.income_bonus.get(FOOD, -1)) == 21, "underground_cistern (hybrid t2) food == 21 (was 32), got %s" % [underground_cistern.income_bonus.get(FOOD, -1)])
		_check(int(underground_cistern.income_bonus.get(GOLD, -1)) == 12, "underground_cistern (hybrid t2) gold unchanged == 12 (secondary kept, no t2 bump), got %s" % [underground_cistern.income_bonus.get(GOLD, -1)])
		_check(underground_cistern.population_growth_bonus == 0, "underground_cistern (hybrid t2) growth == 0 (was 8), got %s" % [underground_cistern.population_growth_bonus])
		_check(not underground_cistern.special_effects.has("region_population_growth_bonus"), "underground_cistern (hybrid t2) region_population_growth_bonus removed, got %s" % [underground_cistern.special_effects])

	var blessed_springs = dm.get_building(&"blessed_springs")
	if blessed_springs != null:
		_check(int(blessed_springs.income_bonus.get(FOOD, -1)) == 21, "blessed_springs (hybrid t2) food == 21 (was 34), got %s" % [blessed_springs.income_bonus.get(FOOD, -1)])
		_check(int(blessed_springs.income_bonus.get(GOLD, -1)) == 12, "blessed_springs (hybrid t2) gold unchanged == 12 (secondary kept, no t2 bump), got %s" % [blessed_springs.income_bonus.get(GOLD, -1)])
		_check(blessed_springs.population_growth_bonus == 0, "blessed_springs (hybrid t2) growth == 0 (was 8), got %s" % [blessed_springs.population_growth_bonus])
		_check(not blessed_springs.special_effects.has("region_population_growth_bonus"), "blessed_springs (hybrid t2) region_population_growth_bonus removed, got %s" % [blessed_springs.special_effects])

	var highland_ranches = dm.get_building(&"highland_ranches")
	if highland_ranches != null:
		_check(int(highland_ranches.income_bonus.get(FOOD, -1)) == 25, "highland_ranches (hybrid t2) food == 25 (was 38), got %s" % [highland_ranches.income_bonus.get(FOOD, -1)])
		_check(int(highland_ranches.income_bonus.get(GOLD, -1)) == 12, "highland_ranches (hybrid t2) gold unchanged == 12 (secondary kept, no t2 bump), got %s" % [highland_ranches.income_bonus.get(GOLD, -1)])
		_check(highland_ranches.population_growth_bonus == 0, "highland_ranches (hybrid t2) growth == 0 (was 8), got %s" % [highland_ranches.population_growth_bonus])
		_check(not highland_ranches.special_effects.has("region_population_growth_bonus"), "highland_ranches (hybrid t2) region_population_growth_bonus removed, got %s" % [highland_ranches.special_effects])

	var terraced_gardens = dm.get_building(&"terraced_gardens")
	if terraced_gardens != null:
		_check(int(terraced_gardens.income_bonus.get(FOOD, -1)) == 14, "terraced_gardens (hybrid t2) food == 14 (was 38), got %s" % [terraced_gardens.income_bonus.get(FOOD, -1)])
		_check(terraced_gardens.population_growth_bonus == 0, "terraced_gardens (hybrid t2) growth == 0 (was 9), got %s" % [terraced_gardens.population_growth_bonus])
		_check(not terraced_gardens.special_effects.has("region_population_growth_bonus"), "terraced_gardens (hybrid t2) region_population_growth_bonus removed, got %s" % [terraced_gardens.special_effects])

	var petrified_quarry = dm.get_building(&"petrified_quarry")
	if petrified_quarry != null:
		_check(int(petrified_quarry.income_bonus.get(IRON, -1)) == 46, "petrified_quarry (hybrid t2) iron == 46 (was 60), got %s" % [petrified_quarry.income_bonus.get(IRON, -1)])
		_check(int(petrified_quarry.income_bonus.get(WOOD, -1)) == 18, "petrified_quarry (hybrid t2) wood unchanged == 18 (secondary kept), got %s" % [petrified_quarry.income_bonus.get(WOOD, -1)])
		_check(petrified_quarry.population_growth_bonus == 0, "petrified_quarry (hybrid t2) growth stays 0, got %s" % [petrified_quarry.population_growth_bonus])

	var moonstone_mine = dm.get_building(&"moonstone_mine")
	if moonstone_mine != null:
		_check(int(moonstone_mine.income_bonus.get(IRON, -1)) == 53, "moonstone_mine (hybrid t2) iron == 53 (was 62), got %s" % [moonstone_mine.income_bonus.get(IRON, -1)])
		_check(int(moonstone_mine.income_bonus.get(WOOD, -1)) == 14, "moonstone_mine (hybrid t2) wood unchanged == 14 (secondary kept), got %s" % [moonstone_mine.income_bonus.get(WOOD, -1)])
		_check(moonstone_mine.population_growth_bonus == 0, "moonstone_mine (hybrid t2) growth stays 0, got %s" % [moonstone_mine.population_growth_bonus])

	var adobe_works = dm.get_building(&"adobe_works")
	if adobe_works != null:
		_check(int(adobe_works.income_bonus.get(IRON, -1)) == 22, "adobe_works (hybrid t2) iron == 22 (was 58), got %s" % [adobe_works.income_bonus.get(IRON, -1)])
		_check(int(adobe_works.income_bonus.get(WOOD, -1)) == 16, "adobe_works (hybrid t2) wood unchanged == 16 (secondary kept), got %s" % [adobe_works.income_bonus.get(WOOD, -1)])
		_check(adobe_works.population_growth_bonus == 0, "adobe_works (hybrid t2) growth stays 0, got %s" % [adobe_works.population_growth_bonus])

	var mountain_stoneworks = dm.get_building(&"mountain_stoneworks")
	if mountain_stoneworks != null:
		_check(int(mountain_stoneworks.income_bonus.get(IRON, -1)) == 60, "mountain_stoneworks (hybrid t2) iron == 60 (was 68), got %s" % [mountain_stoneworks.income_bonus.get(IRON, -1)])
		_check(int(mountain_stoneworks.income_bonus.get(WOOD, -1)) == 16, "mountain_stoneworks (hybrid t2) wood unchanged == 16 (secondary kept), got %s" % [mountain_stoneworks.income_bonus.get(WOOD, -1)])
		_check(mountain_stoneworks.population_growth_bonus == 0, "mountain_stoneworks (hybrid t2) growth stays 0, got %s" % [mountain_stoneworks.population_growth_bonus])

	# volcanic_smelter/ember_foundry (cinderguard iron t2): iron LOCKED at
	# 35/45 (Task 3 pin) and, per the tier-2 "secondary kept" rule plus the
	# cinderguard exception being scoped to the tier-1 pair only, untouched
	# here too -- confirm Task 4 did not touch them.
	var volcanic_smelter = dm.get_building(&"volcanic_smelter")
	if volcanic_smelter != null:
		_check(int(volcanic_smelter.income_bonus.get(IRON, -1)) == 35, "volcanic_smelter (hybrid t2, locked) iron unchanged == 35, got %s" % [volcanic_smelter.income_bonus.get(IRON, -1)])
		_check(int(volcanic_smelter.income_bonus.get(WOOD, -1)) == 16, "volcanic_smelter (hybrid t2, locked) wood unchanged == 16, got %s" % [volcanic_smelter.income_bonus.get(WOOD, -1)])

## Task 5: tail cleanup -- six audited oddities (wall chain, resonant forge
## payback fix, blessed_springs unit-unlock move, echo_chamber/resonant_pylon
## chain, codex_sanctum authority->research swap, tempest_spire doctrine gate).
## chitin_hatchery: NO data change (see progress.md ledger note) -- not pinned here.
func _run_task5_tail_cleanup(dm) -> void:
	const GOLD := 0
	const IRON := 1
	const FOOD := 3

	# ── hive_bulwark chained as hardened_chitin_wall's upgrade (3rd wall tier) ──
	var hive_bulwark = dm.get_building(&"hive_bulwark")
	if hive_bulwark == null:
		_check(false, "hive_bulwark building data exists")
	else:
		_check(hive_bulwark.upgrades_from == &"hardened_chitin_wall", "hive_bulwark upgrades_from == hardened_chitin_wall, got %s" % [hive_bulwark.upgrades_from])
		_check(hive_bulwark.defense_bonus == 12, "hive_bulwark defense_bonus == 12 (was 8), got %s" % [hive_bulwark.defense_bonus])
		_check(absf(float(hive_bulwark.special_effects.get("garrison_strength_bonus", -1.0)) - 0.2) < 0.001, "hive_bulwark garrison_strength_bonus == 0.2 (was 0.15), got %s" % [hive_bulwark.special_effects.get("garrison_strength_bonus")])
		_check(int(hive_bulwark.build_cost.get(IRON, -1)) == 149, "hive_bulwark build_cost kept unchanged pre-sweep, now x1.5 (iron 99 -> 149), got %s" % [hive_bulwark.build_cost])
		_check(hive_bulwark.display_name == "Hive Bulwark III", "hive_bulwark display_name carries tier-3 numeral suffix like chain siblings, got %s" % [hive_bulwark.display_name])

	var hardened_chitin_wall = dm.get_building(&"hardened_chitin_wall")
	if hardened_chitin_wall != null:
		_check(hardened_chitin_wall.upgrades_from == &"chitin_walls", "hardened_chitin_wall still upgrades_from chitin_walls (chain root unchanged), got %s" % [hardened_chitin_wall.upgrades_from])

	# ── resonant_crystal_forge: payback-fix cost {gold 35, food 101} -> {gold 40, food 30} ──
	var resonant_crystal_forge = dm.get_building(&"resonant_crystal_forge")
	if resonant_crystal_forge == null:
		_check(false, "resonant_crystal_forge building data exists")
	else:
		_check(int(resonant_crystal_forge.build_cost.get(GOLD, -1)) == 60, "resonant_crystal_forge build_cost gold == 60 (payback-fix 40, then Task D x1.5), got %s" % [resonant_crystal_forge.build_cost.get(GOLD, -1)])
		_check(int(resonant_crystal_forge.build_cost.get(FOOD, -1)) == 45, "resonant_crystal_forge build_cost food == 45 (payback-fix 30, then Task D x1.5), got %s" % [resonant_crystal_forge.build_cost.get(FOOD, -1)])

	# ── blessed_springs no longer unlocks dawnscale_thunderlizard; the unlock ──
	# moves to solar_chapter_house (sunblessed tier-2 barracks-line military
	# building, already unlocking mid-tier units dawn_crusader/sunfire_lancer).
	var blessed_springs = dm.get_building(&"blessed_springs")
	if blessed_springs == null:
		_check(false, "blessed_springs building data exists")
	else:
		_check(not (blessed_springs.unlocks_units as Array).has(&"dawnscale_thunderlizard"), "blessed_springs no longer unlocks_units dawnscale_thunderlizard, got %s" % [blessed_springs.unlocks_units])

	var solar_chapter_house = dm.get_building(&"solar_chapter_house")
	if solar_chapter_house == null:
		_check(false, "solar_chapter_house building data exists")
	else:
		_check((solar_chapter_house.unlocks_units as Array).has(&"dawnscale_thunderlizard"), "solar_chapter_house unlocks_units contains dawnscale_thunderlizard, got %s" % [solar_chapter_house.unlocks_units])
		_check((solar_chapter_house.unlocks_units as Array).has(&"dawn_crusader"), "solar_chapter_house still unlocks pre-existing dawn_crusader, got %s" % [solar_chapter_house.unlocks_units])

	# Sweep ALL buildings: dawnscale_thunderlizard must be unlocked by exactly
	# one building, and that building must be a military-category building.
	var dawnscale_unlockers: Array = []
	for id in dm.buildings.keys():
		var b: BuildingData = dm.buildings[id]
		if b.unlocks_units != null and (b.unlocks_units as Array).has(&"dawnscale_thunderlizard"):
			dawnscale_unlockers.append(id)
	_check(dawnscale_unlockers.size() == 1, "dawnscale_thunderlizard is unlocked by exactly one building, got %s" % [dawnscale_unlockers])
	if dawnscale_unlockers.size() == 1:
		var unlocker: BuildingData = dm.buildings[dawnscale_unlockers[0]]
		_check(unlocker.category == &"military", "dawnscale_thunderlizard's sole unlocker (%s) is category military, got %s" % [dawnscale_unlockers[0], unlocker.category])

	# ── echo_chamber chained as resonant_pylon's upgrade (shardhorde parallel- ──
	# tech pair). No cost-subtraction convention exists elsewhere in the data
	# (every other chained pair costs strictly MORE at the upgrade tier, full
	# standalone price -- e.g. crystal_forge 72 total -> resonant_crystal_forge
	# 136 total pre-fix, cinder_mine 97 total -> ember_foundry 273 total), so
	# echo_chamber's cost is left unchanged here.
	var echo_chamber = dm.get_building(&"echo_chamber")
	if echo_chamber == null:
		_check(false, "echo_chamber building data exists")
	else:
		_check(echo_chamber.upgrades_from == &"resonant_pylon", "echo_chamber upgrades_from == resonant_pylon, got %s" % [echo_chamber.upgrades_from])
		_check(int(echo_chamber.build_cost.get(GOLD, -1)) == 158, "echo_chamber build_cost gold == 158 (no discount convention found in data: 105, then Task D x1.5), got %s" % [echo_chamber.build_cost.get(GOLD, -1)])

	var resonant_pylon = dm.get_building(&"resonant_pylon")
	if resonant_pylon != null:
		_check(resonant_pylon.upgrades_from == &"", "resonant_pylon remains the chain root (no upgrades_from), got %s" % [resonant_pylon.upgrades_from])

	# ── codex_sanctum: imperial_authority_bonus swapped for research_speed_bonus 0.25 ──
	var codex_sanctum = dm.get_building(&"codex_sanctum")
	if codex_sanctum == null:
		_check(false, "codex_sanctum building data exists")
	else:
		_check(not codex_sanctum.special_effects.has("imperial_authority_bonus"), "codex_sanctum special_effects no longer has imperial_authority_bonus, got %s" % [codex_sanctum.special_effects])
		_check(absf(float(codex_sanctum.special_effects.get("research_speed_bonus", -1.0)) - 0.25) < 0.001, "codex_sanctum research_speed_bonus == 0.25, got %s" % [codex_sanctum.special_effects.get("research_speed_bonus")])

	# ── tempest_roost / tempest_spire: consistent storm_doctrine capstone fork ──
	var tempest_roost = dm.get_building(&"tempest_roost")
	var tempest_spire = dm.get_building(&"tempest_spire")
	if tempest_roost == null or tempest_spire == null:
		_check(false, "tempest_roost and tempest_spire building data exist")
	else:
		_check(tempest_roost.exclusive_group == &"storm_doctrine", "tempest_roost still in storm_doctrine group, got %s" % [tempest_roost.exclusive_group])
		_check(tempest_spire.exclusive_group == &"storm_doctrine", "tempest_spire now in storm_doctrine group (was empty), got %s" % [tempest_spire.exclusive_group])
