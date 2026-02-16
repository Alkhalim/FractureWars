extends Node

# Battle System V2 tests — run this scene from the editor to validate.
# Tests cover: formations, contact combat, morale, captives, orders, terrain gen params.

var _pass_count := 0
var _fail_count := 0
var _test_name := ""

func _ready() -> void:
	print("\n========== BATTLE V2 SYSTEM TESTS ==========\n")

	_run_formation_class_tests()
	_run_grid_sizing_tests()
	_run_formation_geometry_tests()
	_run_contact_combat_tests()
	_run_morale_tests()
	_run_captive_tests()
	_run_order_tests()
	_run_ranged_tests()
	_run_victory_tests()
	_run_terrain_gen_param_tests()

	print("\n==============================================")
	print("PASSED: %d  |  FAILED: %d" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	print("==============================================\n")

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

func _make_formation(id: StringName, side: int, tags: Array[String] = [],
		atk: int = 10, def: int = 5, spd: int = 5, rng: int = 1,
		hp: int = 100, squad: int = 10, hp_per_entity: int = 10,
		tiles_per_entity: int = 1, base_morale: int = 50,
		captive_chance: float = 0.3) -> BattleSimulatorV2.BattleFormation:
	var f := BattleSimulatorV2.BattleFormation.new()
	f.instance_id = id
	f.unit_data_id = id
	f.display_name = str(id)
	f.side = side
	f.tags = tags
	f.attack = atk
	f.defense = def
	f.speed = spd
	f.attack_range = rng
	f.tiles_per_entity = tiles_per_entity
	f.max_hp = hp
	f.current_hp = hp
	if squad > 1:
		f.total_entities = squad
		f.entities_alive = squad
		f.hp_per_entity = hp_per_entity
		f.front_entity_hp = hp_per_entity
	else:
		f.total_entities = 1
		f.entities_alive = 1
		f.hp_per_entity = hp
		f.front_entity_hp = hp
	f.base_morale = base_morale
	f.current_morale = float(base_morale)
	f.captive_chance = captive_chance
	return f

func _make_sim(width: int = 40, height: int = 30) -> BattleSimulatorV2:
	var sim := BattleSimulatorV2.new()
	sim.grid_width = width
	sim.grid_height = height
	sim.deploy_top_end = ceili(height * 0.25)
	sim.deploy_bottom_start = height - ceili(height * 0.25)
	# Fill with open terrain
	var terrain_data: Dictionary = {}
	for y in height:
		for x in width:
			terrain_data[Vector2i(x, y)] = Enums.BattleTerrain.OPEN
	sim.setup_terrain(terrain_data)
	return sim

func _place_formation(sim: BattleSimulatorV2, f: BattleSimulatorV2.BattleFormation, pos: Vector2i) -> void:
	f.anchor_pos = pos
	if f.side == 0:
		f.facing = Vector2i(0, -1)
		sim.attacker_formations.append(f)
	else:
		f.facing = Vector2i(0, 1)
		sim.defender_formations.append(f)
	sim._build_formation(f)

# =========================================================
# BATTLE FORMATION CLASS TESTS
# =========================================================

func _run_formation_class_tests() -> void:
	print("\n--- BattleFormation ---")

	_test_formation_take_damage_squad()
	_test_formation_take_damage_single()
	_test_formation_take_damage_overkill()
	_test_formation_entity_kill_tracking()

func _test_formation_take_damage_squad() -> void:
	_begin_test("formation_take_damage_squad")
	var f := _make_formation(&"sq1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	_assert(f.entities_alive == 10, "Should start with 10 entities")
	_assert(f.current_hp == 100, "Should start with 100 HP")

	# Deal 25 damage — should kill 2 entities (25 / 10hp = 2.5 -> 2 killed, front at 5hp)
	var killed := f.take_damage(25)
	_assert(killed == 2, "Should kill 2 entities, got %d" % killed)
	_assert(f.entities_alive == 8, "Should have 8 entities alive, got %d" % f.entities_alive)
	_assert(f.current_hp == 75, "Should have 75 HP, got %d" % f.current_hp)
	_assert(f.front_entity_hp == 5, "Front entity should have 5 HP, got %d" % f.front_entity_hp)
	_assert(f.is_dead == false, "Should not be dead")

func _test_formation_take_damage_single() -> void:
	_begin_test("formation_take_damage_single_entity")
	var f := _make_formation(&"s1", 0, [], 10, 5, 5, 1, 200, 1, 200)
	var killed := f.take_damage(50)
	_assert(killed == 0, "Single entity should not die at 150 HP, killed=%d" % killed)
	_assert(f.current_hp == 150, "Should have 150 HP, got %d" % f.current_hp)
	_assert(f.is_dead == false, "Should not be dead")

func _test_formation_take_damage_overkill() -> void:
	_begin_test("formation_take_damage_overkill")
	var f := _make_formation(&"ok1", 0, [], 10, 5, 5, 1, 50, 5, 10)
	var killed := f.take_damage(999)
	_assert(killed == 5, "Should kill all 5 entities, got %d" % killed)
	_assert(f.current_hp == 0, "HP should be 0, got %d" % f.current_hp)
	_assert(f.is_dead == true, "Should be dead")
	_assert(f.entities_alive == 0, "No entities alive, got %d" % f.entities_alive)

func _test_formation_entity_kill_tracking() -> void:
	_begin_test("formation_entity_kill_returns_accurate_count")
	var f := _make_formation(&"ek1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	# Kill exactly 1 entity (10 damage to front entity at 10 hp)
	var killed := f.take_damage(10)
	_assert(killed == 1, "Should kill exactly 1 entity, got %d" % killed)
	_assert(f.entities_alive == 9, "Should have 9 alive, got %d" % f.entities_alive)

	# Deal 1 damage — wounds front entity but doesn't kill
	killed = f.take_damage(1)
	_assert(killed == 0, "Should not kill any entity with 1 dmg, got %d" % killed)

# =========================================================
# GRID SIZING TESTS
# =========================================================

func _run_grid_sizing_tests() -> void:
	print("\n--- Grid Sizing ---")

	_test_grid_minimum_size()
	_test_deploy_zone_proportions()

func _test_grid_minimum_size() -> void:
	_begin_test("grid_minimum_size")
	var sim := BattleSimulatorV2.new()
	# Manually set grid size to minimum
	sim.grid_width = 30
	sim.grid_height = 20
	_assert(sim.grid_width >= 30, "Grid width should be >= 30")
	_assert(sim.grid_height >= 20, "Grid height should be >= 20")

func _test_deploy_zone_proportions() -> void:
	_begin_test("deploy_zone_proportions")
	var sim := _make_sim(60, 40)
	# Top 25% for defender
	_assert(sim.deploy_top_end == ceili(40 * 0.25), "Deploy top end should be ceil(40*0.25)=%d, got %d" % [ceili(40 * 0.25), sim.deploy_top_end])
	# Bottom 25% for attacker
	_assert(sim.deploy_bottom_start == 40 - ceili(40 * 0.25), "Deploy bottom start should be %d, got %d" % [40 - ceili(40 * 0.25), sim.deploy_bottom_start])
	# No-man's land in the middle
	_assert(sim.deploy_bottom_start > sim.deploy_top_end, "There should be no-man's land between zones")

# =========================================================
# FORMATION GEOMETRY TESTS
# =========================================================

func _run_formation_geometry_tests() -> void:
	print("\n--- Formation Geometry ---")

	_test_build_single_tile_formation()
	_test_build_multi_tile_formation()
	_test_build_multi_entity_formation()
	_test_formation_avoids_occupied()
	_test_formation_avoids_impassable()
	_test_formation_shrinks_on_entity_loss()

func _test_build_single_tile_formation() -> void:
	_begin_test("build_single_tile_formation")
	var sim := _make_sim()
	var f := _make_formation(&"st1", 0, [], 10, 5, 5, 1, 50, 1, 50, 1)
	_place_formation(sim, f, Vector2i(20, 25))
	_assert(f.occupied_tiles.size() == 1, "Single entity with 1 tile should have 1 tile, got %d" % f.occupied_tiles.size())
	_assert(f.occupied_tiles.has(Vector2i(20, 25)), "Should occupy anchor position")
	_assert(sim.grid.get(Vector2i(20, 25)) == f, "Grid should reference formation at anchor")

func _test_build_multi_tile_formation() -> void:
	_begin_test("build_multi_tile_formation_monster")
	var sim := _make_sim()
	# Monster: 1 entity, 6 tiles_per_entity
	var f := _make_formation(&"mt1", 0, ["monster"] as Array[String], 20, 10, 3, 1, 200, 1, 200, 6)
	_place_formation(sim, f, Vector2i(20, 25))
	# Should occupy up to 6 tiles (may be less if geometry wraps)
	_assert(f.occupied_tiles.size() >= 2, "Monster should occupy multiple tiles, got %d" % f.occupied_tiles.size())
	_assert(f.occupied_tiles.size() <= 6, "Monster should not exceed 6 tiles, got %d" % f.occupied_tiles.size())
	_assert(f.occupied_tiles.has(f.anchor_pos), "Anchor should be in occupied tiles")

func _test_build_multi_entity_formation() -> void:
	_begin_test("build_multi_entity_formation")
	var sim := _make_sim()
	# 10 entities, 1 tile each = 10 tiles
	var f := _make_formation(&"me1", 0, ["infantry"] as Array[String], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, f, Vector2i(20, 25))
	_assert(f.occupied_tiles.size() >= 5, "10-entity formation should occupy multiple tiles, got %d" % f.occupied_tiles.size())
	_assert(f.occupied_tiles.size() <= 10, "Should not exceed 10 tiles, got %d" % f.occupied_tiles.size())

func _test_formation_avoids_occupied() -> void:
	_begin_test("v2_formation_avoids_occupied_tiles")
	var sim := _make_sim()
	var f1 := _make_formation(&"fo1", 0, [], 10, 5, 5, 1, 50, 5, 10, 1)
	_place_formation(sim, f1, Vector2i(20, 25))

	var f2 := _make_formation(&"fo2", 0, [], 10, 5, 5, 1, 50, 5, 10, 1)
	_place_formation(sim, f2, Vector2i(22, 25))

	# No shared tiles
	for tile in f1.occupied_tiles:
		_assert(not f2.occupied_tiles.has(tile),
			"Formations should not share tile %s" % str(tile))

func _test_formation_avoids_impassable() -> void:
	_begin_test("v2_formation_avoids_impassable")
	var sim := _make_sim()
	# Place rock next to anchor
	sim.terrain[Vector2i(19, 25)] = Enums.BattleTerrain.ROCK
	sim.terrain[Vector2i(21, 25)] = Enums.BattleTerrain.ROCK

	var f := _make_formation(&"fi1", 0, [], 10, 5, 5, 1, 50, 5, 10, 1)
	_place_formation(sim, f, Vector2i(20, 25))

	_assert(not f.occupied_tiles.has(Vector2i(19, 25)), "Should not occupy ROCK at (19,25)")
	_assert(not f.occupied_tiles.has(Vector2i(21, 25)), "Should not occupy ROCK at (21,25)")
	_assert(f.occupied_tiles.has(Vector2i(20, 25)), "Should occupy anchor")

func _test_formation_shrinks_on_entity_loss() -> void:
	_begin_test("formation_shrinks_on_entity_loss")
	var sim := _make_sim()
	var f := _make_formation(&"fs1", 0, [], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, f, Vector2i(20, 25))
	var initial_tiles := f.occupied_tiles.size()

	# Kill 5 entities
	f.take_damage(50)
	sim._build_formation(f)

	_assert(f.occupied_tiles.size() < initial_tiles,
		"Formation should shrink after entity loss (was %d, now %d)" % [initial_tiles, f.occupied_tiles.size()])

# =========================================================
# CONTACT COMBAT TESTS
# =========================================================

func _run_contact_combat_tests() -> void:
	print("\n--- Contact Combat ---")

	_test_melee_no_contact_no_damage()
	_test_melee_front_contact()
	_test_melee_flank_contact()
	_test_melee_rear_contact()
	_test_melee_damage_scales_with_contact()
	_test_stance_modifies_damage()

func _test_melee_no_contact_no_damage() -> void:
	_begin_test("melee_no_contact_no_damage")
	var sim := _make_sim()
	var atk := _make_formation(&"nc_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	var def := _make_formation(&"nc_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	_place_formation(sim, atk, Vector2i(5, 25))
	_place_formation(sim, def, Vector2i(30, 5))

	var result := sim._resolve_melee_combat(atk, def)
	var dmg: int = result.damage
	_assert(dmg == 0, "No contact = no damage, got %d" % dmg)

func _test_melee_front_contact() -> void:
	_begin_test("melee_front_contact_deals_damage")
	var sim := _make_sim()
	# Place attacker directly below defender so attacker faces up into defender's front
	var atk := _make_formation(&"fc_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	var def := _make_formation(&"fc_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	# Defender at (20,14) facing down, Attacker at (20,15) facing up
	_place_formation(sim, def, Vector2i(20, 14))
	_place_formation(sim, atk, Vector2i(20, 15))

	var result := sim._resolve_melee_combat(atk, def)
	var dmg: int = result.damage
	var front: int = result.front
	_assert(dmg > 0, "Adjacent formations should deal damage, got %d" % dmg)
	_assert(front > 0, "Should register front contact, got %d" % front)

func _test_melee_flank_contact() -> void:
	_begin_test("melee_flank_contact_causes_morale_damage")
	var sim := _make_sim()
	# Defender facing down (0,1), attacker from the side
	var def := _make_formation(&"flk_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def.facing = Vector2i(0, 1)
	var atk := _make_formation(&"flk_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)

	# Place defender, then attacker to its right
	def.anchor_pos = Vector2i(20, 14)
	def.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim.grid[Vector2i(20, 14)] = def
	sim.defender_formations.append(def)

	atk.anchor_pos = Vector2i(21, 14)
	atk.occupied_tiles = [Vector2i(21, 14)] as Array[Vector2i]
	sim.grid[Vector2i(21, 14)] = atk
	sim.attacker_formations.append(atk)

	var result := sim._resolve_melee_combat(atk, def)
	var flank: int = result.flank
	var morale_dmg: float = result.morale_damage
	_assert(flank > 0, "Should register flank contact, got %d" % flank)
	_assert(morale_dmg > 0.0, "Flank should cause morale damage, got %f" % morale_dmg)

func _test_melee_rear_contact() -> void:
	_begin_test("melee_rear_contact_causes_high_morale_damage")
	var sim := _make_sim()
	# Defender facing up (0,-1), attacker behind (below)
	var def := _make_formation(&"rr_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def.facing = Vector2i(0, -1)

	def.anchor_pos = Vector2i(20, 14)
	def.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim.grid[Vector2i(20, 14)] = def
	sim.defender_formations.append(def)

	var atk := _make_formation(&"rr_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	atk.anchor_pos = Vector2i(20, 15)
	atk.occupied_tiles = [Vector2i(20, 15)] as Array[Vector2i]
	sim.grid[Vector2i(20, 15)] = atk
	sim.attacker_formations.append(atk)

	var result := sim._resolve_melee_combat(atk, def)
	var rear: int = result.rear
	var morale_dmg: float = result.morale_damage
	_assert(rear > 0, "Should register rear contact, got %d" % rear)
	_assert(morale_dmg >= 3.0, "Rear should cause high morale damage (>=3.0), got %f" % morale_dmg)

func _test_melee_damage_scales_with_contact() -> void:
	_begin_test("melee_damage_scales_with_contact_surface")
	var sim := _make_sim()

	# Setup: 1 tile attacker vs 1 tile defender (1 contact point)
	var atk1 := _make_formation(&"sc1_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	var def1 := _make_formation(&"sc1_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def1.facing = Vector2i(0, 1)
	atk1.anchor_pos = Vector2i(20, 15)
	atk1.occupied_tiles = [Vector2i(20, 15)] as Array[Vector2i]
	sim.grid[Vector2i(20, 15)] = atk1
	sim.attacker_formations.append(atk1)
	def1.anchor_pos = Vector2i(20, 14)
	def1.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim.grid[Vector2i(20, 14)] = def1
	sim.defender_formations.append(def1)

	# Measure damage over many iterations for 1 contact point
	var total_1_contact := 0
	for i in 50:
		var r := sim._resolve_melee_combat(atk1, def1)
		var d: int = r.damage
		total_1_contact += d

	# Now create wider formations with more contact (3 tiles wide, adjacent)
	var sim2 := _make_sim()
	var atk2 := _make_formation(&"sc2_a", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	var def2 := _make_formation(&"sc2_d", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def2.facing = Vector2i(0, 1)

	# 3-tile wide attacker
	atk2.anchor_pos = Vector2i(20, 15)
	atk2.occupied_tiles = [Vector2i(19, 15), Vector2i(20, 15), Vector2i(21, 15)] as Array[Vector2i]
	for t in atk2.occupied_tiles:
		sim2.grid[t] = atk2
	sim2.attacker_formations.append(atk2)
	# 3-tile wide defender
	def2.anchor_pos = Vector2i(20, 14)
	def2.occupied_tiles = [Vector2i(19, 14), Vector2i(20, 14), Vector2i(21, 14)] as Array[Vector2i]
	for t in def2.occupied_tiles:
		sim2.grid[t] = def2
	sim2.defender_formations.append(def2)

	var total_3_contact := 0
	for i in 50:
		var r := sim2._resolve_melee_combat(atk2, def2)
		var d: int = r.damage
		total_3_contact += d

	_assert(total_3_contact > total_1_contact,
		"3 contact tiles should deal more damage than 1 (3c avg=%d, 1c avg=%d)" % [total_3_contact / 50, total_1_contact / 50])

func _test_stance_modifies_damage() -> void:
	_begin_test("stance_modifies_melee_damage")
	var sim := _make_sim()

	# Aggressive attacker
	var atk_agg := _make_formation(&"st_aa", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	atk_agg.stance = Enums.UnitStance.AGGRESSIVE
	atk_agg.anchor_pos = Vector2i(20, 15)
	atk_agg.occupied_tiles = [Vector2i(20, 15)] as Array[Vector2i]
	sim.grid[Vector2i(20, 15)] = atk_agg
	sim.attacker_formations.append(atk_agg)

	var def_agg := _make_formation(&"st_da", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def_agg.stance = Enums.UnitStance.AGGRESSIVE
	def_agg.facing = Vector2i(0, 1)
	def_agg.anchor_pos = Vector2i(20, 14)
	def_agg.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim.grid[Vector2i(20, 14)] = def_agg
	sim.defender_formations.append(def_agg)

	var total_agg := 0
	for i in 100:
		var r := sim._resolve_melee_combat(atk_agg, def_agg)
		var d: int = r.damage
		total_agg += d

	# Defensive defender should take less damage
	var sim2 := _make_sim()
	var atk_agg2 := _make_formation(&"st_aa2", 0, [], 20, 5, 5, 1, 100, 1, 100, 1)
	atk_agg2.stance = Enums.UnitStance.AGGRESSIVE
	atk_agg2.anchor_pos = Vector2i(20, 15)
	atk_agg2.occupied_tiles = [Vector2i(20, 15)] as Array[Vector2i]
	sim2.grid[Vector2i(20, 15)] = atk_agg2
	sim2.attacker_formations.append(atk_agg2)

	var def_def := _make_formation(&"st_dd", 1, [], 10, 10, 5, 1, 100, 1, 100, 1)
	def_def.stance = Enums.UnitStance.DEFENSIVE
	def_def.facing = Vector2i(0, 1)
	def_def.anchor_pos = Vector2i(20, 14)
	def_def.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim2.grid[Vector2i(20, 14)] = def_def
	sim2.defender_formations.append(def_def)

	var total_def := 0
	for i in 100:
		var r := sim2._resolve_melee_combat(atk_agg2, def_def)
		var d: int = r.damage
		total_def += d

	_assert(total_def < total_agg,
		"Defensive stance should reduce damage (vs_agg=%d, vs_def=%d)" % [total_agg / 100, total_def / 100])

# =========================================================
# MORALE TESTS
# =========================================================

func _run_morale_tests() -> void:
	print("\n--- Morale ---")

	_test_morale_passive_recovery()
	_test_morale_routing_at_zero()
	_test_morale_rally_above_threshold()
	_test_morale_death_shock()
	_test_morale_fear_aura()
	_test_morale_routing_flees()

func _test_morale_passive_recovery() -> void:
	_begin_test("morale_passive_recovery")
	var sim := _make_sim()
	var f := _make_formation(&"mr1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	f.current_morale = 30.0
	_place_formation(sim, f, Vector2i(20, 25))

	# No enemies, so not in combat — should get +2 passive recovery
	sim._update_morale(f)
	_assert(f.current_morale > 30.0, "Morale should recover when not in combat, got %f" % f.current_morale)

func _test_morale_routing_at_zero() -> void:
	_begin_test("morale_routing_at_zero")
	var sim := _make_sim()
	var f := _make_formation(&"mr2", 0, [], 10, 5, 5, 1, 100, 10, 10)
	f.current_morale = 0.5  # Just above 0
	f.rally_cooldown = 0
	_place_formation(sim, f, Vector2i(20, 25))

	# Force morale to 0
	f.current_morale = -1.0
	sim._update_morale(f)
	# After update, current_morale will get passive recovery, but routing flag should be set
	# Let's set morale to very low before update
	f.current_morale = -29.0
	f.is_routing = false
	sim._update_morale(f)
	# Even with +2 recovery, -29 + 2 = -27, still below 0
	_assert(f.is_routing == true, "Should be routing when morale <= 0")

func _test_morale_rally_above_threshold() -> void:
	_begin_test("morale_rally_above_20pct")
	var sim := _make_sim()
	var f := _make_formation(&"mr3", 0, [], 10, 5, 5, 1, 100, 10, 10, 1, 50)
	f.is_routing = true
	f.current_morale = 12.0  # > 50 * 0.2 = 10.0
	_place_formation(sim, f, Vector2i(20, 25))

	sim._update_morale(f)
	_assert(f.is_routing == false, "Should rally when morale > 20%% base")
	_assert(f.rally_cooldown > 0, "Should have rally cooldown")

func _test_morale_death_shock() -> void:
	_begin_test("morale_nearby_death_reduces_morale")
	var sim := _make_sim()
	var f := _make_formation(&"md1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	f.current_morale = 40.0
	_place_formation(sim, f, Vector2i(20, 25))

	# Simulate a nearby ally death
	sim.tick_count = 5
	sim.recent_deaths.append({"side": 0, "anchor_pos": Vector2i(22, 25), "tick": 4})

	var before := f.current_morale
	sim._update_morale(f)
	# Should get passive recovery (+2) but death shock (-4), net -2
	_assert(f.current_morale < before, "Death shock should reduce morale, was %f now %f" % [before, f.current_morale])

func _test_morale_fear_aura() -> void:
	_begin_test("morale_enemy_fear_aura_reduces_morale")
	var sim := _make_sim()
	var f := _make_formation(&"mf1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	f.current_morale = 40.0
	_place_formation(sim, f, Vector2i(20, 20))

	# Place enemy monster with fear aura nearby
	var monster := _make_formation(&"mf_m", 1, ["monster"] as Array[String], 30, 15, 3, 1, 300, 1, 300, 6, 80)
	monster.morale_aura = -5
	monster.fear_radius = 5
	_place_formation(sim, monster, Vector2i(20, 17))

	var before := f.current_morale
	sim._update_morale(f)
	# Fear aura: -5 * 0.5 = -2.5 morale per tick, plus passive +2, net -0.5
	_assert(f.current_morale < before + 2.0, "Fear aura should counteract some recovery, was %f now %f" % [before, f.current_morale])

func _test_morale_routing_flees() -> void:
	_begin_test("morale_routing_unit_moves_toward_edge")
	var sim := _make_sim()
	# Attacker (side 0) routes toward bottom (y increases)
	var f := _make_formation(&"mfl1", 0, [], 10, 5, 5, 1, 100, 10, 10)
	f.is_routing = true
	f.current_morale = -10.0
	_place_formation(sim, f, Vector2i(20, 28))  # Near bottom edge (grid_height=30)

	# Place a dummy enemy to prevent instant victory
	var dummy := _make_formation(&"mfl_d", 1, [], 5, 5, 5, 1, 100, 10, 10)
	_place_formation(sim, dummy, Vector2i(10, 5))

	var start_y := f.anchor_pos.y
	var actions := sim._execute_rout_movement(f)
	_assert(f.anchor_pos.y >= start_y, "Routing attacker should move toward bottom (y >= %d), got %d" % [start_y, f.anchor_pos.y])

# =========================================================
# CAPTIVE TESTS
# =========================================================

func _run_captive_tests() -> void:
	print("\n--- Captives ---")

	_test_captive_melee_generation()
	_test_captive_ranged_low_chance()
	_test_captive_monster_very_low()
	_test_captive_count_tracks_per_side()

func _test_captive_melee_generation() -> void:
	_begin_test("captive_melee_infantry_generates_captives")
	var sim := _make_sim()
	var killer := _make_formation(&"ck1", 0, ["infantry", "melee"] as Array[String])
	var victim := _make_formation(&"cv1", 1, [], 10, 5, 5, 1, 100, 10, 10, 1, 50, 1.0)  # 100% captive chance for testing
	sim.attacker_formations.append(killer)
	sim.defender_formations.append(victim)

	var total_captives := 0
	for i in 100:
		sim.captives = {0: 0, 1: 0}
		total_captives += sim._generate_captives(killer, victim, 5)

	_assert(total_captives > 0, "Infantry melee should generate captives with high chance")
	# With 100% base chance and melee infantry multiplier of 1.0, should get close to 500
	_assert(total_captives > 400, "Should generate many captives with 100%% chance, got %d" % total_captives)

func _test_captive_ranged_low_chance() -> void:
	_begin_test("captive_ranged_very_low_chance")
	var sim := _make_sim()
	var killer := _make_formation(&"ck2", 0, ["ranged"] as Array[String])
	var victim := _make_formation(&"cv2", 1, [], 10, 5, 5, 1, 100, 10, 10, 1, 50, 0.3)
	sim.attacker_formations.append(killer)
	sim.defender_formations.append(victim)

	var total_captives := 0
	for i in 100:
		sim.captives = {0: 0, 1: 0}
		total_captives += sim._generate_captives(killer, victim, 5)

	# 0.3 * 0.1 = 0.03 chance per entity, 500 rolls → ~15 captives
	_assert(total_captives < 100, "Ranged should generate very few captives, got %d" % total_captives)

func _test_captive_monster_very_low() -> void:
	_begin_test("captive_monster_extremely_low")
	var sim := _make_sim()
	var killer := _make_formation(&"ck3", 0, ["monster"] as Array[String])
	var victim := _make_formation(&"cv3", 1, [], 10, 5, 5, 1, 100, 10, 10, 1, 50, 0.3)
	sim.attacker_formations.append(killer)
	sim.defender_formations.append(victim)

	var total_captives := 0
	for i in 100:
		sim.captives = {0: 0, 1: 0}
		total_captives += sim._generate_captives(killer, victim, 5)

	# 0.3 * 0.05 = 0.015 chance per entity
	_assert(total_captives < 50, "Monster should generate very few captives, got %d" % total_captives)

func _test_captive_count_tracks_per_side() -> void:
	_begin_test("captive_count_accumulates_per_side")
	var sim := _make_sim()
	sim.captives = {0: 0, 1: 0}
	var killer := _make_formation(&"ck4", 0, ["infantry", "melee"] as Array[String])
	var victim := _make_formation(&"cv4", 1, [], 10, 5, 5, 1, 100, 10, 10, 1, 50, 1.0)
	sim.attacker_formations.append(killer)
	sim.defender_formations.append(victim)

	sim._generate_captives(killer, victim, 10)
	var side_0_caps: int = sim.captives.get(0, 0)
	_assert(side_0_caps > 0, "Side 0 should have captives, got %d" % side_0_caps)
	var side_1_caps: int = sim.captives.get(1, 0)
	_assert(side_1_caps == 0, "Side 1 should have 0 captives, got %d" % side_1_caps)

# =========================================================
# ORDER TESTS
# =========================================================

func _run_order_tests() -> void:
	print("\n--- Orders ---")

	_test_ai_assigns_cavalry_charge()
	_test_ai_assigns_ranged_hold()
	_test_ai_assigns_infantry_advance()
	_test_hold_does_not_move()
	_test_charge_double_speed()

func _test_ai_assigns_cavalry_charge() -> void:
	_begin_test("ai_assigns_cavalry_charge_or_flank")
	var sim := _make_sim()
	var cav := _make_formation(&"ai_c1", 1, ["cavalry"] as Array[String])
	_place_formation(sim, cav, Vector2i(20, 5))

	var inf := _make_formation(&"ai_e1", 0, ["infantry"] as Array[String])
	_place_formation(sim, inf, Vector2i(20, 25))

	sim.assign_ai_orders(1)
	_assert(cav.current_order == Enums.BattleOrder.CHARGE or cav.current_order == Enums.BattleOrder.FLANK_LEFT,
		"Cavalry should be assigned CHARGE or FLANK, got %d" % cav.current_order)

func _test_ai_assigns_ranged_hold() -> void:
	_begin_test("ai_assigns_ranged_hold")
	var sim := _make_sim()
	var rng := _make_formation(&"ai_r1", 1, ["ranged"] as Array[String], 10, 5, 5, 5)
	_place_formation(sim, rng, Vector2i(20, 5))

	var inf := _make_formation(&"ai_e2", 0, ["infantry"] as Array[String])
	_place_formation(sim, inf, Vector2i(20, 25))

	sim.assign_ai_orders(1)
	_assert(rng.current_order == Enums.BattleOrder.HOLD, "Ranged should HOLD, got %d" % rng.current_order)

func _test_ai_assigns_infantry_advance() -> void:
	_begin_test("ai_assigns_infantry_advance")
	var sim := _make_sim()
	var inf := _make_formation(&"ai_i1", 1, ["infantry", "melee"] as Array[String])
	_place_formation(sim, inf, Vector2i(20, 5))

	var enemy := _make_formation(&"ai_e3", 0, ["infantry"] as Array[String])
	_place_formation(sim, enemy, Vector2i(20, 25))

	sim.assign_ai_orders(1)
	_assert(inf.current_order == Enums.BattleOrder.ADVANCE, "Infantry should ADVANCE, got %d" % inf.current_order)

func _test_hold_does_not_move() -> void:
	_begin_test("hold_order_does_not_move")
	var sim := _make_sim()
	var f := _make_formation(&"hm1", 0, [], 10, 5, 5, 1, 100, 1, 100, 1)
	f.current_order = Enums.BattleOrder.HOLD
	_place_formation(sim, f, Vector2i(20, 25))

	var enemy := _make_formation(&"hm_e", 1, [], 10, 5, 5, 1, 100, 1, 100, 1)
	_place_formation(sim, enemy, Vector2i(20, 5))

	var start_pos := f.anchor_pos
	sim._execute_order_movement(f)
	_assert(f.anchor_pos == start_pos, "HOLD order should not move, was %s now %s" % [str(start_pos), str(f.anchor_pos)])

func _test_charge_double_speed() -> void:
	_begin_test("charge_order_moves_at_double_speed")
	var sim := _make_sim()
	# Speed 6 -> move_tiles = max(1, 6/3) = 2, charge doubles to 4
	var f := _make_formation(&"ch1", 0, [], 10, 5, 6, 1, 100, 1, 100, 1)
	f.current_order = Enums.BattleOrder.CHARGE
	_place_formation(sim, f, Vector2i(20, 25))

	var adv := _make_formation(&"ch_a", 0, [], 10, 5, 6, 1, 100, 1, 100, 1)
	adv.current_order = Enums.BattleOrder.ADVANCE
	_place_formation(sim, adv, Vector2i(15, 25))

	var enemy := _make_formation(&"ch_e", 1, [], 10, 5, 5, 1, 100, 1, 100, 1)
	_place_formation(sim, enemy, Vector2i(20, 5))

	var charge_start := f.anchor_pos.y
	var advance_start := adv.anchor_pos.y
	sim._execute_order_movement(f)
	sim._execute_order_movement(adv)

	var charge_moved := charge_start - f.anchor_pos.y
	var advance_moved := advance_start - adv.anchor_pos.y
	_assert(charge_moved > advance_moved,
		"CHARGE should move further than ADVANCE (charge=%d, advance=%d)" % [charge_moved, advance_moved])

# =========================================================
# RANGED TESTS
# =========================================================

func _run_ranged_tests() -> void:
	print("\n--- Ranged ---")

	_test_ranged_deals_damage_at_range()
	_test_ranged_no_fire_in_melee()
	_test_ranged_out_of_range()

func _test_ranged_deals_damage_at_range() -> void:
	_begin_test("ranged_deals_damage_at_range")
	var sim := _make_sim()
	# Ranged unit with range 5 (effective range = 5*3 = 15 tiles)
	var rng := _make_formation(&"rd1", 0, ["ranged"] as Array[String], 15, 5, 5, 5, 100, 10, 10, 1)
	_place_formation(sim, rng, Vector2i(20, 25))

	var target := _make_formation(&"rd_t", 1, [], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, target, Vector2i(20, 15))

	var hp_before := target.current_hp
	var actions := sim._execute_ranged_attack(rng)
	_assert(actions.size() > 0, "Should have ranged attack action")
	_assert(target.current_hp < hp_before, "Target should take damage, was %d now %d" % [hp_before, target.current_hp])

func _test_ranged_no_fire_in_melee() -> void:
	_begin_test("ranged_cannot_fire_in_melee")
	var sim := _make_sim()
	var rng := _make_formation(&"rm1", 0, ["ranged"] as Array[String], 15, 5, 5, 5, 100, 1, 100, 1)
	rng.anchor_pos = Vector2i(20, 15)
	rng.occupied_tiles = [Vector2i(20, 15)] as Array[Vector2i]
	sim.grid[Vector2i(20, 15)] = rng
	sim.attacker_formations.append(rng)

	var enemy := _make_formation(&"rm_e", 1, [], 10, 5, 5, 1, 100, 1, 100, 1)
	enemy.anchor_pos = Vector2i(20, 14)
	enemy.occupied_tiles = [Vector2i(20, 14)] as Array[Vector2i]
	sim.grid[Vector2i(20, 14)] = enemy
	sim.defender_formations.append(enemy)

	# Ranged unit is in melee contact — should not fire
	_assert(sim._is_in_melee_contact(rng) == true, "Should detect melee contact")
	# The simulate_tick skips ranged fire for melee-engaged units
	# We test the check directly
	var would_skip := sim._is_in_melee_contact(rng)
	_assert(would_skip, "Ranged in melee contact should be skipped for ranged fire")

func _test_ranged_out_of_range() -> void:
	_begin_test("ranged_out_of_range_no_attack")
	var sim := _make_sim(80, 60)
	# Range 2 -> effective 6 tiles
	var rng := _make_formation(&"ro1", 0, ["ranged"] as Array[String], 15, 5, 5, 2, 100, 10, 10, 1)
	_place_formation(sim, rng, Vector2i(20, 55))

	var target := _make_formation(&"ro_t", 1, [], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, target, Vector2i(20, 5))

	var hp_before := target.current_hp
	sim._execute_ranged_attack(rng)
	_assert(target.current_hp == hp_before, "Out-of-range target should not take damage")

# =========================================================
# VICTORY TESTS
# =========================================================

func _run_victory_tests() -> void:
	print("\n--- Victory Conditions ---")

	_test_attacker_wins_when_defenders_die()
	_test_defender_wins_on_timeout()
	_test_surviving_formations_correct()
	_test_fled_units_survive()

func _test_attacker_wins_when_defenders_die() -> void:
	_begin_test("v2_attacker_wins_when_all_defenders_die")
	var sim := _make_sim()
	var strong := _make_formation(&"vw_a", 0, ["infantry", "melee"] as Array[String], 50, 5, 5, 1, 500, 1, 500, 1, 80)
	_place_formation(sim, strong, Vector2i(20, 16))

	var weak := _make_formation(&"vw_d", 1, [], 1, 0, 1, 1, 10, 1, 10, 1, 99)
	_place_formation(sim, weak, Vector2i(20, 14))

	for tick in 200:
		sim.simulate_tick()
		if sim.is_finished:
			break

	_assert(sim.is_finished, "Battle should be finished")
	_assert(sim.winner_side == 0, "Attacker should win, got side %d" % sim.winner_side)

func _test_defender_wins_on_timeout() -> void:
	_begin_test("v2_defender_wins_on_timeout")
	var sim := _make_sim(80, 60)
	sim.max_ticks = 50

	# Two units far apart that won't reach each other
	var f1 := _make_formation(&"to_a", 0, [], 1, 999, 1, 1, 9999, 1, 9999, 1, 99)
	f1.current_order = Enums.BattleOrder.HOLD
	_place_formation(sim, f1, Vector2i(5, 55))

	var f2 := _make_formation(&"to_d", 1, [], 1, 999, 1, 1, 9999, 1, 9999, 1, 99)
	f2.current_order = Enums.BattleOrder.HOLD
	_place_formation(sim, f2, Vector2i(70, 5))

	for tick in 60:
		sim.simulate_tick()
		if sim.is_finished:
			break

	_assert(sim.is_finished, "Battle should end at max ticks")
	_assert(sim.winner_side == 1, "Defender should win on timeout, got side %d" % sim.winner_side)
	_assert(sim.tick_count <= 50, "Should not exceed max_ticks=%d, got %d" % [50, sim.tick_count])

func _test_surviving_formations_correct() -> void:
	_begin_test("v2_surviving_formations_correct")
	var sim := _make_sim()
	var f1 := _make_formation(&"sf1", 0, [], 10, 5, 5, 1, 100, 10, 10, 1)
	var f2 := _make_formation(&"sf2", 0, [], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, f1, Vector2i(10, 25))
	_place_formation(sim, f2, Vector2i(30, 25))

	_assert(sim.get_surviving_formations(0).size() == 2, "Should have 2 alive")

	# Kill one
	f1.take_damage(9999)
	_assert(sim.get_surviving_formations(0).size() == 1, "Should have 1 alive after kill")

func _test_fled_units_survive() -> void:
	_begin_test("fled_units_counted_as_surviving")
	var sim := _make_sim()
	var f := _make_formation(&"fl1", 0, [], 10, 5, 5, 1, 100, 10, 10, 1)
	_place_formation(sim, f, Vector2i(20, 25))

	f.is_fled = true  # Simulated flee
	# Fled but not dead — should still be in surviving formations
	var survivors := sim.get_surviving_formations(0)
	_assert(survivors.size() == 1, "Fled unit should be in survivors, got %d" % survivors.size())

# =========================================================
# TERRAIN GEN PARAMETERIZATION TESTS
# =========================================================

func _run_terrain_gen_param_tests() -> void:
	print("\n--- Terrain Gen Params ---")

	_test_terrain_gen_default_size()
	_test_terrain_gen_custom_size()
	_test_terrain_gen_scales_features()

func _test_terrain_gen_default_size() -> void:
	_begin_test("terrain_gen_default_28x22")
	var terrain := BattleTerrainGen.generate(Enums.TerrainType.PLAINS, 12345)
	# Default: 28*22 = 616 tiles (old was 20*16=320, new default 28*22)
	_assert(terrain.size() > 0, "Should generate terrain tiles")
	# Check bounds
	var max_x := -1
	var max_y := -1
	for pos in terrain:
		var p: Vector2i = pos
		if p.x > max_x: max_x = p.x
		if p.y > max_y: max_y = p.y
	_assert(max_x <= 27, "Max x should be <= 27 for default width, got %d" % max_x)
	_assert(max_y <= 21, "Max y should be <= 21 for default height, got %d" % max_y)

func _test_terrain_gen_custom_size() -> void:
	_begin_test("terrain_gen_custom_60x40")
	var terrain := BattleTerrainGen.generate(Enums.TerrainType.FOREST, 42, 60, 40)
	_assert(terrain.size() == 60 * 40, "Custom 60x40 should have %d tiles, got %d" % [60 * 40, terrain.size()])

	# Verify all tiles are valid
	for pos in terrain:
		var val = terrain[pos]
		_assert(val >= 0 and val <= Enums.BattleTerrain.BRUSH,
			"Invalid terrain value %s at %s" % [str(val), str(pos)])

func _test_terrain_gen_scales_features() -> void:
	_begin_test("terrain_gen_larger_grid_has_more_features")
	# Small grid
	var small := BattleTerrainGen.generate(Enums.TerrainType.MOUNTAINS, 42, 30, 20)
	var small_non_open := 0
	for pos in small:
		if small[pos] != Enums.BattleTerrain.OPEN:
			small_non_open += 1

	# Large grid (same seed)
	var large := BattleTerrainGen.generate(Enums.TerrainType.MOUNTAINS, 42, 90, 60)
	var large_non_open := 0
	for pos in large:
		if large[pos] != Enums.BattleTerrain.OPEN:
			large_non_open += 1

	_assert(large_non_open > small_non_open,
		"Larger grid should have more features (small=%d, large=%d)" % [small_non_open, large_non_open])
