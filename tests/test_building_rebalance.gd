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
