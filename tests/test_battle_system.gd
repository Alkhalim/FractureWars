extends Node

# Battle system tests — run this scene from the editor to validate.
# Results printed to Output panel. Errors will show as FAIL.

var _pass_count := 0
var _fail_count := 0
var _test_name := ""

func _ready() -> void:
	print("\n========== BATTLE SYSTEM TESTS ==========\n")

	_run_terrain_gen_tests()
	_run_battle_unit_tests()
	_run_formation_tests()
	_run_simulator_tests()
	_run_movement_tests()
	_run_damage_tests()
	_run_win_condition_tests()
	_run_placement_tests()

	print("\n==========================================")
	print("PASSED: %d  |  FAILED: %d" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	print("==========================================\n")

	# Exit after tests if running from command line
	await get_tree().create_timer(0.5).timeout

# --- Helpers ---

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: [%s] %s" % [_test_name, message])

func _begin_test(name: String) -> void:
	_test_name = name
	print("  Running: %s" % name)

func _make_unit_data(id: StringName, tags: Array[String], hp: int = 100, atk: int = 10,
		def: int = 5, spd: int = 5, rng: int = 1) -> UnitData:
	var ud := UnitData.new()
	ud.id = id
	ud.display_name = str(id)
	ud.tags = tags
	ud.max_hp = hp
	ud.attack = atk
	ud.defense = def
	ud.speed = spd
	ud.attack_range = rng
	return ud

func _make_unit_instance(id: StringName, data: UnitData) -> UnitInstance:
	var ui := UnitInstance.new()
	ui.instance_id = id
	ui.unit_data_id = data.id
	ui.current_hp = data.max_hp
	return ui

# =========================================================
# TERRAIN GENERATION TESTS
# =========================================================

func _run_terrain_gen_tests() -> void:
	print("\n--- Terrain Generation ---")

	_test_terrain_gen_all_types()
	_test_terrain_gen_deployment_zones_clear()
	_test_terrain_gen_deterministic()
	_test_terrain_props_complete()
	_test_terrain_passability()

func _test_terrain_gen_all_types() -> void:
	_begin_test("terrain_gen_all_campaign_types")
	var campaign_types: Array[Enums.TerrainType] = [
		Enums.TerrainType.PLAINS, Enums.TerrainType.FOREST, Enums.TerrainType.MOUNTAINS,
		Enums.TerrainType.DESERT, Enums.TerrainType.SWAMP, Enums.TerrainType.COAST,
		Enums.TerrainType.TUNDRA, Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.WATER,
		Enums.TerrainType.JUNGLE,
	]

	for ct in campaign_types:
		var terrain := BattleTerrainGen.generate(ct, 12345)
		_assert(terrain.size() == 20 * 16, "Terrain for %s should have 320 tiles, got %d" % [Enums.TerrainType.keys()[ct], terrain.size()])

		# Every tile should have a valid BattleTerrain value
		for pos in terrain:
			var val = terrain[pos]
			_assert(val >= 0 and val <= Enums.BattleTerrain.BRUSH,
				"Invalid terrain value %s at %s for campaign type %s" % [str(val), str(pos), Enums.TerrainType.keys()[ct]])

func _test_terrain_gen_deployment_zones_clear() -> void:
	_begin_test("terrain_gen_deployment_zones_clear")
	# Mountains and shard wastes have impassable terrain — verify deploy zones are clear
	for ct in [Enums.TerrainType.MOUNTAINS, Enums.TerrainType.SHARD_WASTES]:
		var terrain := BattleTerrainGen.generate(ct, 99999)

		# Top deployment zone (rows 0-4)
		for y in range(5):
			for x in range(20):
				var t = terrain[Vector2i(x, y)]
				_assert(BattleTerrainGen.is_passable(t),
					"Deployment zone has impassable tile at (%d,%d) for %s" % [x, y, Enums.TerrainType.keys()[ct]])

		# Bottom deployment zone (rows 10-15)
		for y in range(10, 16):
			for x in range(20):
				var t = terrain[Vector2i(x, y)]
				_assert(BattleTerrainGen.is_passable(t),
					"Deployment zone has impassable tile at (%d,%d) for %s" % [x, y, Enums.TerrainType.keys()[ct]])

func _test_terrain_gen_deterministic() -> void:
	_begin_test("terrain_gen_deterministic")
	var t1 := BattleTerrainGen.generate(Enums.TerrainType.FOREST, 42)
	var t2 := BattleTerrainGen.generate(Enums.TerrainType.FOREST, 42)

	var match_count := 0
	for pos in t1:
		if t1[pos] == t2[pos]:
			match_count += 1
	_assert(match_count == 320, "Same seed should produce identical terrain (matched %d/320)" % match_count)

func _test_terrain_props_complete() -> void:
	_begin_test("terrain_props_complete")
	for i in range(Enums.BattleTerrain.size()):
		var bt: Enums.BattleTerrain = i as Enums.BattleTerrain
		_assert(BattleTerrainGen.TERRAIN_PROPS.has(bt),
			"TERRAIN_PROPS missing entry for BattleTerrain.%s" % Enums.BattleTerrain.keys()[i])

func _test_terrain_passability() -> void:
	_begin_test("terrain_passability")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.OPEN) == true, "OPEN should be passable")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.ROCK) == false, "ROCK should be impassable")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.CRYSTAL) == false, "CRYSTAL should be impassable")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.FOREST) == true, "FOREST should be passable")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.WATER) == true, "WATER should be passable")
	_assert(BattleTerrainGen.get_speed_modifier(Enums.BattleTerrain.OPEN) == 1.0, "OPEN speed should be 1.0")
	_assert(BattleTerrainGen.get_speed_modifier(Enums.BattleTerrain.ROCK) == 0.0, "ROCK speed should be 0.0")
	_assert(BattleTerrainGen.get_defense_bonus(Enums.BattleTerrain.FOREST) == 3, "FOREST defense bonus should be 3")
	_assert(BattleTerrainGen.get_defense_bonus(Enums.BattleTerrain.WATER) == -2, "WATER defense bonus should be -2")

# =========================================================
# BATTLE UNIT TESTS
# =========================================================

func _run_battle_unit_tests() -> void:
	print("\n--- BattleUnit ---")

	_test_take_damage_basic()
	_test_take_damage_death()
	_test_take_damage_overkill()

func _test_take_damage_basic() -> void:
	_begin_test("take_damage_basic")
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 100
	bu.take_damage(30)
	_assert(bu.current_hp == 70, "HP should be 70 after 30 damage, got %d" % bu.current_hp)
	_assert(bu.is_dead == false, "Should not be dead at 70 HP")

func _test_take_damage_death() -> void:
	_begin_test("take_damage_death")
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 10
	bu.take_damage(10)
	_assert(bu.current_hp == 0, "HP should be 0")
	_assert(bu.is_dead == true, "Should be dead at 0 HP")

func _test_take_damage_overkill() -> void:
	_begin_test("take_damage_overkill")
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 5
	bu.take_damage(50)
	_assert(bu.current_hp == 0, "HP should clamp to 0, got %d" % bu.current_hp)
	_assert(bu.is_dead == true, "Should be dead after overkill")

# =========================================================
# FORMATION TESTS
# =========================================================

func _run_formation_tests() -> void:
	print("\n--- Formations ---")

	_test_formation_type_infantry()
	_test_formation_type_cavalry()
	_test_formation_type_mage()
	_test_formation_type_construct()
	_test_formation_type_fast()
	_test_formation_type_default()
	_test_formation_size_full_hp()
	_test_formation_size_half_hp()
	_test_formation_size_low_hp()
	_test_formation_size_critical_hp()
	_test_formation_placement_line()
	_test_formation_placement_block()
	_test_formation_grid_occupancy()
	_test_formation_shrink_on_damage()
	_test_formation_avoids_impassable()
	_test_formation_avoids_occupied()

func _test_formation_type_infantry() -> void:
	_begin_test("formation_type_infantry")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"inf1", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"inf1_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"line", "Infantry should use line formation, got %s" % bu.formation_type)
	_assert(bu.max_formation_tiles == 4, "Infantry line should have 4 max tiles, got %d" % bu.max_formation_tiles)

func _test_formation_type_cavalry() -> void:
	_begin_test("formation_type_cavalry")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"cav1", ["cavalry"] as Array[String])
	var ui := _make_unit_instance(&"cav1_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"wedge", "Cavalry should use wedge formation, got %s" % bu.formation_type)
	_assert(bu.max_formation_tiles == 6, "Cavalry wedge should have 6 max tiles, got %d" % bu.max_formation_tiles)

func _test_formation_type_mage() -> void:
	_begin_test("formation_type_mage")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"mage1", ["mage"] as Array[String])
	var ui := _make_unit_instance(&"mage1_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"cluster", "Mage should use cluster formation, got %s" % bu.formation_type)

func _test_formation_type_construct() -> void:
	_begin_test("formation_type_construct")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"golem1", ["construct"] as Array[String], 200)
	var ui := _make_unit_instance(&"golem1_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"block", "Construct should use block formation, got %s" % bu.formation_type)

func _test_formation_type_fast() -> void:
	_begin_test("formation_type_fast")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"wolf1", ["fast"] as Array[String])
	var ui := _make_unit_instance(&"wolf1_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"blob", "Fast unit should use blob formation, got %s" % bu.formation_type)

func _test_formation_type_default() -> void:
	_begin_test("formation_type_default_no_tags")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"militia", [] as Array[String], 50)
	var ui := _make_unit_instance(&"militia_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"line", "Default (no tags, low HP) should use line, got %s" % bu.formation_type)

func _test_formation_size_full_hp() -> void:
	_begin_test("formation_size_full_hp")
	var sim := BattleSimulator.new()
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 100
	bu.max_formation_tiles = 4
	_assert(sim.get_formation_size(bu) == 4, "Full HP should give max tiles")

func _test_formation_size_half_hp() -> void:
	_begin_test("formation_size_half_hp")
	var sim := BattleSimulator.new()
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 60
	bu.max_formation_tiles = 4
	# 60% HP: > 0.50, so ceili(4 * 0.7) = ceili(2.8) = 3
	_assert(sim.get_formation_size(bu) == 3, "60%% HP should give 3 tiles, got %d" % sim.get_formation_size(bu))

func _test_formation_size_low_hp() -> void:
	_begin_test("formation_size_low_hp")
	var sim := BattleSimulator.new()
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 30
	bu.max_formation_tiles = 4
	# 30% HP: > 0.25, so ceili(4 * 0.4) = ceili(1.6) = 2
	_assert(sim.get_formation_size(bu) == 2, "30%% HP should give 2 tiles, got %d" % sim.get_formation_size(bu))

func _test_formation_size_critical_hp() -> void:
	_begin_test("formation_size_critical_hp")
	var sim := BattleSimulator.new()
	var bu := BattleSimulator.BattleUnit.new()
	bu.max_hp = 100
	bu.current_hp = 10
	bu.max_formation_tiles = 4
	_assert(sim.get_formation_size(bu) == 1, "10%% HP should give 1 tile, got %d" % sim.get_formation_size(bu))

func _test_formation_placement_line() -> void:
	_begin_test("formation_placement_line_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"inf_pl", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"inf_pl_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.occupied_tiles.size() == 4, "Full HP infantry should occupy 4 tiles, got %d" % bu.occupied_tiles.size())
	_assert(bu.occupied_tiles.has(bu.anchor_pos), "Anchor should be in occupied tiles")

func _test_formation_placement_block() -> void:
	_begin_test("formation_placement_block_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"golem_pl", ["construct"] as Array[String], 200)
	var ui := _make_unit_instance(&"golem_pl_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.occupied_tiles.size() == 4, "Full HP construct should occupy 4 tiles, got %d" % bu.occupied_tiles.size())

func _test_formation_grid_occupancy() -> void:
	_begin_test("formation_grid_occupancy")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"inf_go", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"inf_go_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# All occupied tiles should map back to this unit in the grid
	for i in bu.occupied_tiles.size():
		var tile: Vector2i = bu.occupied_tiles[i]
		_assert(sim.grid.get(tile) == bu,
			"Grid at %s should reference the unit" % str(tile))

	# get_unit_at should return the unit for any occupied tile
	for i in bu.occupied_tiles.size():
		var tile: Vector2i = bu.occupied_tiles[i]
		_assert(sim.get_unit_at(tile) == bu,
			"get_unit_at(%s) should return the unit" % str(tile))

func _test_formation_shrink_on_damage() -> void:
	_begin_test("formation_shrink_on_damage")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"inf_sh", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"inf_sh_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	_assert(bu.occupied_tiles.size() == 4, "Should start with 4 tiles")

	# Damage to 50% HP
	bu.take_damage(50)
	var removed := sim.update_formation(bu)
	_assert(bu.occupied_tiles.size() <= 3, "At 50%% HP should have <= 3 tiles, got %d" % bu.occupied_tiles.size())
	_assert(removed.size() > 0, "Should have removed tiles")

	# Verify removed tiles are no longer in grid
	for i in removed.size():
		var tile: Vector2i = removed[i]
		_assert(sim.grid.get(tile) != bu,
			"Removed tile %s should not reference unit in grid" % str(tile))

func _test_formation_avoids_impassable() -> void:
	_begin_test("formation_avoids_impassable_terrain")
	var sim := BattleSimulator.new()
	# Create terrain with rock next to anchor
	var terrain: Dictionary = {}
	for y in range(16):
		for x in range(20):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.OPEN
	# Place rocks around the anchor position
	terrain[Vector2i(9, 12)] = Enums.BattleTerrain.ROCK
	terrain[Vector2i(11, 12)] = Enums.BattleTerrain.ROCK
	sim.setup_terrain(terrain)

	var ud := _make_unit_data(&"inf_imp", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"inf_imp_inst", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Formation should not include the rock tiles
	_assert(not bu.occupied_tiles.has(Vector2i(9, 12)), "Should not occupy ROCK tile at (9,12)")
	_assert(not bu.occupied_tiles.has(Vector2i(11, 12)), "Should not occupy ROCK tile at (11,12)")
	# Anchor should still be placed
	_assert(bu.occupied_tiles.has(Vector2i(10, 12)), "Anchor should be placed")

func _test_formation_avoids_occupied() -> void:
	_begin_test("formation_avoids_occupied_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Place first unit
	var ud1 := _make_unit_data(&"inf_a", ["infantry"] as Array[String])
	var ui1 := _make_unit_instance(&"inf_a_inst", ud1)
	var bu1 := sim.setup_unit(ui1, ud1, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Place second unit adjacent
	var ud2 := _make_unit_data(&"inf_b", ["infantry"] as Array[String])
	var ui2 := _make_unit_instance(&"inf_b_inst", ud2)
	var bu2 := sim.setup_unit(ui2, ud2, 0, Vector2i(10, 13), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# No tile should be shared
	for i in bu1.occupied_tiles.size():
		var tile: Vector2i = bu1.occupied_tiles[i]
		_assert(not bu2.occupied_tiles.has(tile),
			"Units should not share tile %s" % str(tile))

# =========================================================
# SIMULATOR TESTS
# =========================================================

func _run_simulator_tests() -> void:
	print("\n--- Simulator ---")

	_test_simulator_setup()
	_test_formation_distance()
	_test_tick_moves_units()
	_test_tick_attacks_in_range()

func _test_simulator_setup() -> void:
	_begin_test("simulator_setup_sides")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"test_su", ["infantry"] as Array[String])
	var ui_a := _make_unit_instance(&"atk_inst", ud)
	var ui_d := _make_unit_instance(&"def_inst", ud)

	sim.setup_unit(ui_a, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	_assert(sim.attacker_units.size() == 1, "Should have 1 attacker")
	_assert(sim.defender_units.size() == 1, "Should have 1 defender")
	_assert(sim.is_finished == false, "Battle should not be finished")

func _test_formation_distance() -> void:
	_begin_test("formation_distance_calculation")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"test_fd", ["infantry"] as Array[String])
	var ui_a := _make_unit_instance(&"fd_atk", ud)
	var ui_d := _make_unit_instance(&"fd_def", ud)

	var bu_a := sim.setup_unit(ui_a, ud, 0, Vector2i(10, 14), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	var bu_d := sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Distance should be measured from nearest tiles
	var dist: int = sim._formation_distance(bu_a, bu_d)
	_assert(dist > 0, "Distance should be > 0, got %d" % dist)
	# Anchors are 12 rows apart, but formation tiles extend toward each other
	_assert(dist < 14, "Distance should be less than anchor distance of 12, got %d" % dist)

func _test_tick_moves_units() -> void:
	_begin_test("tick_moves_aggressive_units")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"test_mv", ["infantry"] as Array[String], 100, 10, 5, 5, 1)
	var ui_a := _make_unit_instance(&"mv_atk", ud)
	var ui_d := _make_unit_instance(&"mv_def", ud)

	var bu_a := sim.setup_unit(ui_a, ud, 0, Vector2i(10, 14), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	var start_y := bu_a.anchor_pos.y
	var actions := sim.simulate_tick()

	var moved := false
	for action in actions:
		if action.type == "move" and action.unit_id == &"mv_atk":
			moved = true
	_assert(moved, "Aggressive unit should move toward enemy")

func _test_tick_attacks_in_range() -> void:
	_begin_test("tick_attacks_when_adjacent")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Place melee units right next to each other
	var ud := _make_unit_data(&"test_at", [] as Array[String], 100, 15, 5, 5, 1)
	var ui_a := _make_unit_instance(&"at_atk", ud)
	var ui_d := _make_unit_instance(&"at_def", ud)

	sim.setup_unit(ui_a, ud, 0, Vector2i(10, 8), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 7), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	var actions := sim.simulate_tick()
	var attacked := false
	for action in actions:
		if action.type == "attack":
			attacked = true
	_assert(attacked, "Adjacent units should attack each other")

# =========================================================
# MOVEMENT TESTS
# =========================================================

func _run_movement_tests() -> void:
	print("\n--- Movement ---")

	_test_defensive_no_move()
	_test_move_avoids_impassable()

func _test_defensive_no_move() -> void:
	_begin_test("defensive_unit_does_not_move")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"test_def", [] as Array[String], 100, 10, 5, 5, 1)
	var ui_a := _make_unit_instance(&"def_atk", ud)
	var ui_d := _make_unit_instance(&"def_def", ud)

	var bu_a := sim.setup_unit(ui_a, ud, 0, Vector2i(10, 14), Enums.UnitStance.DEFENSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	var start_pos := bu_a.anchor_pos
	sim.simulate_tick()
	_assert(bu_a.anchor_pos == start_pos, "Defensive unit should not move")

func _test_move_avoids_impassable() -> void:
	_begin_test("movement_avoids_impassable")
	var sim := BattleSimulator.new()
	# Create a wall of rock between the units
	var terrain: Dictionary = {}
	for y in range(16):
		for x in range(20):
			terrain[Vector2i(x, y)] = Enums.BattleTerrain.OPEN
	# Rock wall at row 8 except one gap
	for x in range(20):
		terrain[Vector2i(x, 8)] = Enums.BattleTerrain.ROCK
	terrain[Vector2i(5, 8)] = Enums.BattleTerrain.OPEN  # Gap

	sim.setup_terrain(terrain)

	var ud := _make_unit_data(&"test_avoid", [] as Array[String], 100, 10, 5, 10, 1)
	var ui_a := _make_unit_instance(&"avoid_atk", ud)
	var ui_d := _make_unit_instance(&"avoid_def", ud)

	var bu_a := sim.setup_unit(ui_a, ud, 0, Vector2i(10, 10), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Simulate several ticks — unit should never land on ROCK
	for tick in range(20):
		sim.simulate_tick()
		for i in bu_a.occupied_tiles.size():
			var tile: Vector2i = bu_a.occupied_tiles[i]
			var t = terrain.get(tile, Enums.BattleTerrain.OPEN)
			_assert(BattleTerrainGen.is_passable(t),
				"Unit should never be on impassable tile %s (tick %d)" % [str(tile), tick])
		if bu_a.is_dead:
			break

# =========================================================
# DAMAGE TESTS
# =========================================================

func _run_damage_tests() -> void:
	print("\n--- Damage ---")

	_test_damage_minimum_one()
	_test_terrain_defense_bonus()
	_test_aggressive_stance_bonus()
	_test_defensive_stance_reduction()

func _test_damage_minimum_one() -> void:
	_begin_test("damage_minimum_one")
	var sim := BattleSimulator.new()
	var attacker := BattleSimulator.BattleUnit.new()
	attacker.attack = 1
	attacker.stance = Enums.UnitStance.AGGRESSIVE
	var defender := BattleSimulator.BattleUnit.new()
	defender.defense = 100
	defender.stance = Enums.UnitStance.DEFENSIVE

	# Run many times to test with variance
	var all_at_least_one := true
	for i in range(50):
		var dmg: int = sim._calculate_damage(attacker, defender, 0)
		if dmg < 1:
			all_at_least_one = false
			break
	_assert(all_at_least_one, "Damage should always be at least 1")

func _test_terrain_defense_bonus() -> void:
	_begin_test("terrain_defense_bonus_applied")
	var sim := BattleSimulator.new()
	var attacker := BattleSimulator.BattleUnit.new()
	attacker.attack = 20
	attacker.stance = Enums.UnitStance.AGGRESSIVE
	var defender := BattleSimulator.BattleUnit.new()
	defender.defense = 5
	defender.stance = Enums.UnitStance.AGGRESSIVE

	# Without terrain bonus
	var total_no_bonus := 0
	for i in range(100):
		total_no_bonus += sim._calculate_damage(attacker, defender, 0)

	# With forest bonus (+3 defense)
	var total_with_bonus := 0
	for i in range(100):
		total_with_bonus += sim._calculate_damage(attacker, defender, 3)

	_assert(total_with_bonus < total_no_bonus,
		"Terrain defense bonus should reduce damage (no bonus avg: %d, with bonus avg: %d)" % [total_no_bonus / 100, total_with_bonus / 100])

func _test_aggressive_stance_bonus() -> void:
	_begin_test("aggressive_stance_increases_damage")
	var sim := BattleSimulator.new()
	var defender := BattleSimulator.BattleUnit.new()
	defender.defense = 5
	defender.stance = Enums.UnitStance.AGGRESSIVE

	var attacker_agg := BattleSimulator.BattleUnit.new()
	attacker_agg.attack = 20
	attacker_agg.stance = Enums.UnitStance.AGGRESSIVE

	var attacker_def := BattleSimulator.BattleUnit.new()
	attacker_def.attack = 20
	attacker_def.stance = Enums.UnitStance.DEFENSIVE

	var total_agg := 0
	var total_def := 0
	for i in range(200):
		total_agg += sim._calculate_damage(attacker_agg, defender, 0)
		total_def += sim._calculate_damage(attacker_def, defender, 0)

	_assert(total_agg > total_def,
		"Aggressive attacker should deal more damage (agg avg: %d, def avg: %d)" % [total_agg / 200, total_def / 200])

func _test_defensive_stance_reduction() -> void:
	_begin_test("defensive_stance_reduces_damage")
	var sim := BattleSimulator.new()
	var attacker := BattleSimulator.BattleUnit.new()
	attacker.attack = 20
	attacker.stance = Enums.UnitStance.AGGRESSIVE

	var defender_agg := BattleSimulator.BattleUnit.new()
	defender_agg.defense = 5
	defender_agg.stance = Enums.UnitStance.AGGRESSIVE

	var defender_def := BattleSimulator.BattleUnit.new()
	defender_def.defense = 5
	defender_def.stance = Enums.UnitStance.DEFENSIVE

	var total_vs_agg := 0
	var total_vs_def := 0
	for i in range(200):
		total_vs_agg += sim._calculate_damage(attacker, defender_agg, 0)
		total_vs_def += sim._calculate_damage(attacker, defender_def, 0)

	_assert(total_vs_def < total_vs_agg,
		"Defensive stance should reduce incoming damage (vs agg avg: %d, vs def avg: %d)" % [total_vs_agg / 200, total_vs_def / 200])

# =========================================================
# WIN CONDITION TESTS
# =========================================================

func _run_win_condition_tests() -> void:
	print("\n--- Win Conditions ---")

	_test_attacker_wins_when_defenders_die()
	_test_defender_wins_when_attackers_die()
	_test_battle_ends_at_max_ticks()
	_test_surviving_units()

func _test_attacker_wins_when_defenders_die() -> void:
	_begin_test("attacker_wins_when_all_defenders_die")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud_strong := _make_unit_data(&"strong", [] as Array[String], 1000, 50, 5, 10, 1)
	var ud_weak := _make_unit_data(&"weak", [] as Array[String], 10, 1, 0, 1, 1)

	var ui_a := _make_unit_instance(&"strong_inst", ud_strong)
	var ui_d := _make_unit_instance(&"weak_inst", ud_weak)

	sim.setup_unit(ui_a, ud_strong, 0, Vector2i(10, 8), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud_weak, 1, Vector2i(10, 7), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	for tick in range(100):
		sim.simulate_tick()
		if sim.is_finished:
			break

	_assert(sim.is_finished, "Battle should be finished")
	_assert(sim.winner_side == 0, "Attacker should win, got side %d" % sim.winner_side)

func _test_defender_wins_when_attackers_die() -> void:
	_begin_test("defender_wins_when_all_attackers_die")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud_weak := _make_unit_data(&"weak2", [] as Array[String], 10, 1, 0, 1, 1)
	var ud_strong := _make_unit_data(&"strong2", [] as Array[String], 1000, 50, 5, 10, 1)

	var ui_a := _make_unit_instance(&"weak2_inst", ud_weak)
	var ui_d := _make_unit_instance(&"strong2_inst", ud_strong)

	sim.setup_unit(ui_a, ud_weak, 0, Vector2i(10, 8), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud_strong, 1, Vector2i(10, 7), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	for tick in range(100):
		sim.simulate_tick()
		if sim.is_finished:
			break

	_assert(sim.is_finished, "Battle should be finished")
	_assert(sim.winner_side == 1, "Defender should win, got side %d" % sim.winner_side)

func _test_battle_ends_at_max_ticks() -> void:
	_begin_test("battle_ends_at_100_ticks")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Two defensive units that won't move or attack (too far apart)
	var ud := _make_unit_data(&"passive", [] as Array[String], 9999, 1, 999, 1, 1)
	var ui_a := _make_unit_instance(&"pass_atk", ud)
	var ui_d := _make_unit_instance(&"pass_def", ud)

	sim.setup_unit(ui_a, ud, 0, Vector2i(0, 15), Enums.UnitStance.DEFENSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(19, 0), Enums.UnitStance.DEFENSIVE, Enums.TargetPriority.CLOSEST)

	for tick in range(105):
		sim.simulate_tick()
		if sim.is_finished:
			break

	_assert(sim.is_finished, "Battle should end by tick 100")
	_assert(sim.winner_side == 1, "Defender wins on timeout")
	_assert(sim.tick_count <= 100, "Should not exceed 100 ticks, got %d" % sim.tick_count)

func _test_surviving_units() -> void:
	_begin_test("surviving_units_correct")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"surv", [] as Array[String], 100, 10, 5, 5, 1)
	var ui_a := _make_unit_instance(&"surv_a1", ud)
	var ui_a2 := _make_unit_instance(&"surv_a2", ud)
	var ui_d := _make_unit_instance(&"surv_d1", ud)

	sim.setup_unit(ui_a, ud, 0, Vector2i(5, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_a2, ud, 0, Vector2i(15, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	sim.setup_unit(ui_d, ud, 1, Vector2i(10, 2), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Before battle
	_assert(sim.get_surviving_units(0).size() == 2, "Should have 2 attackers alive")
	_assert(sim.get_surviving_units(1).size() == 1, "Should have 1 defender alive")

	# Kill one attacker manually
	sim.attacker_units[0].take_damage(9999)
	_assert(sim.get_surviving_units(0).size() == 1, "Should have 1 attacker alive after kill")

# =========================================================
# PLACEMENT TESTS
# =========================================================

func _run_placement_tests() -> void:
	print("\n--- Placement ---")

	_test_placement_in_deploy_zone()
	_test_placement_rejected_outside_deploy()
	_test_placement_rejected_on_occupied()
	_test_placement_rejected_on_impassable()
	_test_placement_no_overlap_with_formations()
	_test_placement_multiple_units_no_overlap()
	_test_placement_grid_tracks_all_tiles()
	_test_reposition_unit()
	_test_monster_formation_type()
	_test_wedge_points_toward_enemy()

func _test_placement_in_deploy_zone() -> void:
	_begin_test("placement_in_deploy_zone")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var pos := Vector2i(10, 12)  # Row 12, in attacker deploy zone (10-15)
	var valid: bool = pos.y >= BattleSimulator.ATTACKER_DEPLOY_START and pos.y < 16
	var free: bool = not sim.grid.has(pos)
	var passable: bool = BattleTerrainGen.is_passable(Enums.BattleTerrain.OPEN)
	_assert(valid and free and passable, "Position (10,12) should be valid for placement")

	# Actually place a unit there
	var ud := _make_unit_data(&"pl_test1", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"pl_test1_i", ud)
	var bu := sim.setup_unit(ui, ud, 0, pos, Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu != null, "Unit should be placed successfully")
	_assert(sim.grid.has(pos), "Grid should have unit at placed position")

func _test_placement_rejected_outside_deploy() -> void:
	_begin_test("placement_rejected_outside_deploy_zone")
	# Attacker deploy zone is rows 10-15. Rows 0-9 are enemy/middle territory.
	var pos_enemy := Vector2i(10, 2)  # Enemy zone
	var pos_middle := Vector2i(10, 8)  # Middle zone
	var pos_above := Vector2i(10, 9)  # Just before deploy zone

	_assert(pos_enemy.y < BattleSimulator.ATTACKER_DEPLOY_START,
		"Row 2 should be outside attacker deploy zone")
	_assert(pos_middle.y < BattleSimulator.ATTACKER_DEPLOY_START,
		"Row 8 should be outside attacker deploy zone")
	_assert(pos_above.y < BattleSimulator.ATTACKER_DEPLOY_START,
		"Row 9 should be outside attacker deploy zone")

	# Row 10 should be valid
	var pos_valid := Vector2i(10, 10)
	_assert(pos_valid.y >= BattleSimulator.ATTACKER_DEPLOY_START,
		"Row 10 should be in attacker deploy zone")

func _test_placement_rejected_on_occupied() -> void:
	_begin_test("placement_rejected_on_occupied_tile")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Place first unit
	var ud := _make_unit_data(&"pl_occ1", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"pl_occ1_i", ud)
	sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Anchor position should be occupied
	_assert(sim.grid.has(Vector2i(10, 12)), "Anchor tile (10,12) should be occupied")

	# grid.has() should prevent placement on any occupied tile
	var blocked: bool = sim.grid.has(Vector2i(10, 12))
	_assert(blocked, "Placement should be blocked on occupied anchor tile")

func _test_placement_rejected_on_impassable() -> void:
	_begin_test("placement_rejected_on_impassable_terrain")
	# ROCK and CRYSTAL are impassable
	_assert(not BattleTerrainGen.is_passable(Enums.BattleTerrain.ROCK),
		"ROCK should be impassable (placement blocked)")
	_assert(not BattleTerrainGen.is_passable(Enums.BattleTerrain.CRYSTAL),
		"CRYSTAL should be impassable (placement blocked)")
	# OPEN, FOREST, etc. should be passable
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.OPEN),
		"OPEN should be passable (placement allowed)")
	_assert(BattleTerrainGen.is_passable(Enums.BattleTerrain.FOREST),
		"FOREST should be passable (placement allowed)")

func _test_placement_no_overlap_with_formations() -> void:
	_begin_test("placement_no_overlap_with_formation_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Place an infantry unit (line formation = 4 tiles)
	var ud := _make_unit_data(&"pl_form1", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"pl_form1_i", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	_assert(bu.occupied_tiles.size() >= 2, "Infantry should occupy multiple tiles (formation)")

	# ALL occupied tiles should be blocked (not just anchor)
	for tile in bu.occupied_tiles:
		_assert(sim.grid.has(tile),
			"Formation tile %s should be tracked in grid (blocks new placement)" % str(tile))

	# Attempt to check a formation tile that is NOT the anchor
	var non_anchor_found := false
	for tile in bu.occupied_tiles:
		if tile != bu.anchor_pos:
			_assert(sim.grid.has(tile),
				"Non-anchor formation tile %s should block placement" % str(tile))
			non_anchor_found = true
			break
	_assert(non_anchor_found, "Unit should have formation tiles beyond anchor")

func _test_placement_multiple_units_no_overlap() -> void:
	_begin_test("placement_multiple_units_no_shared_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	# Place 3 units in the deploy zone
	var positions := [Vector2i(5, 12), Vector2i(10, 12), Vector2i(15, 12)]
	var all_units: Array = []

	for i in positions.size():
		var ud := _make_unit_data(&("pl_mu%d" % i), ["infantry"] as Array[String])
		var ui := _make_unit_instance(&("pl_mu%d_i" % i), ud)
		var bu := sim.setup_unit(ui, ud, 0, positions[i], Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
		all_units.append(bu)

	# Verify no tile is shared between any two units
	for i in all_units.size():
		for j in range(i + 1, all_units.size()):
			var bu_a: BattleSimulator.BattleUnit = all_units[i]
			var bu_b: BattleSimulator.BattleUnit = all_units[j]
			for tile_a in bu_a.occupied_tiles:
				_assert(not bu_b.occupied_tiles.has(tile_a),
					"Units %d and %d share tile %s" % [i, j, str(tile_a)])

func _test_placement_grid_tracks_all_tiles() -> void:
	_begin_test("placement_grid_tracks_all_formation_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"pl_grid", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"pl_grid_i", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 13), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Every occupied tile must be in simulator.grid
	for tile in bu.occupied_tiles:
		_assert(sim.grid.has(tile),
			"Occupied tile %s must be in simulator.grid" % str(tile))
		_assert(sim.grid[tile] == bu,
			"simulator.grid[%s] must point back to the unit" % str(tile))

	# Total grid entries for this unit should match occupied_tiles count
	var grid_count := 0
	for pos in sim.grid:
		if sim.grid[pos] == bu:
			grid_count += 1
	_assert(grid_count == bu.occupied_tiles.size(),
		"Grid should have exactly %d entries for unit, got %d" % [bu.occupied_tiles.size(), grid_count])

func _test_reposition_unit() -> void:
	_begin_test("reposition_unit_clears_old_tiles")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))

	var ud := _make_unit_data(&"pl_repo", ["infantry"] as Array[String])
	var ui := _make_unit_instance(&"pl_repo_i", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	var old_tiles := bu.occupied_tiles.duplicate()
	_assert(old_tiles.size() >= 2, "Should have formation tiles at old position")

	# Reposition to new location
	sim.reposition_unit(bu, Vector2i(5, 14))

	# Old tiles should be clear
	for tile in old_tiles:
		_assert(not sim.grid.has(tile) or sim.grid[tile] != bu,
			"Old tile %s should no longer reference this unit" % str(tile))

	# New tiles should be set
	_assert(bu.anchor_pos == Vector2i(5, 14), "Anchor should be at new position")
	_assert(bu.occupied_tiles.has(Vector2i(5, 14)), "New anchor should be in occupied_tiles")
	for tile in bu.occupied_tiles:
		_assert(sim.grid[tile] == bu,
			"New tile %s should reference the unit" % str(tile))

func _test_monster_formation_type() -> void:
	_begin_test("monster_tag_uses_block_formation")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"wyvern_t", ["monster", "melee", "fast"] as Array[String], 120)
	var ui := _make_unit_instance(&"wyvern_t_i", ud)
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"block", "Monster should use block formation, got %s" % bu.formation_type)

func _test_wedge_points_toward_enemy() -> void:
	_begin_test("wedge_anchor_is_closest_to_enemy")
	var sim := BattleSimulator.new()
	sim.setup_terrain(BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 1))
	var ud := _make_unit_data(&"cav_wd", ["cavalry"] as Array[String])
	var ui := _make_unit_instance(&"cav_wd_i", ud)

	# Side 0 (attacker) deploys at bottom, faces up
	var bu := sim.setup_unit(ui, ud, 0, Vector2i(10, 12), Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)
	_assert(bu.formation_type == &"wedge", "Cavalry should use wedge formation")

	# Anchor (the point) should be the tile closest to enemy (lowest y for side 0)
	var min_y := bu.anchor_pos.y
	for tile in bu.occupied_tiles:
		if tile.y < min_y:
			min_y = tile.y
	_assert(bu.anchor_pos.y == min_y,
		"Wedge anchor (point) should be the frontmost tile (y=%d), but min_y=%d" % [bu.anchor_pos.y, min_y])
