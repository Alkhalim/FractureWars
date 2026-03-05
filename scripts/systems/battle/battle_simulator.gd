class_name BattleSimulator
extends RefCounted

signal tick_completed(actions: Array[Dictionary])
signal battle_ended(winner_side: int) # 0 = attacker, 1 = defender

const GRID_WIDTH := 28
const GRID_HEIGHT := 22
const ATTACKER_DEPLOY_START := 14  # Player deploys rows 14-21 (bottom)
const ATTACKER_DEPLOY_END := 22
const DEFENDER_DEPLOY_START := 0   # AI deploys rows 0-7 (top)
const DEFENDER_DEPLOY_END := 8

var grid: Dictionary = {} # Vector2i -> BattleUnit (all occupied tiles)
var battle_terrain: Dictionary = {} # Vector2i -> Enums.BattleTerrain
var attacker_units: Array[BattleUnit] = []
var defender_units: Array[BattleUnit] = []
var tick_count: int = 0
var is_finished: bool = false
var winner_side: int = -1

class BattleUnit:
	var instance_id: StringName
	var unit_data_id: StringName
	var display_name: String
	var side: int # 0 = attacker, 1 = defender
	var max_hp: int
	var current_hp: int
	var attack: int
	var defense: int
	var speed: int
	var attack_range: int
	var stance: Enums.UnitStance
	var target_priority: Enums.TargetPriority
	var is_dead: bool = false
	var tags: Array[String] = []

	# Soldier split fields
	var squad_size: int = 1
	var hp_per_soldier: int = 0 # 0 = single entity (uses max_hp)
	var soldiers_remaining: int = 1
	var front_soldier_hp: int = 0 # HP of the current front soldier

	# Formation fields
	var anchor_pos: Vector2i          # Primary tile (center/front)
	var occupied_tiles: Array[Vector2i] = []
	var formation_type: StringName    # "line", "wedge", "block", "cluster", "blob"
	var max_formation_tiles: int = 1

	func take_damage(amount: int) -> void:
		if hp_per_soldier > 0 and squad_size > 1:
			# Front-soldier-first damage model
			var remaining_damage := amount
			while remaining_damage > 0 and soldiers_remaining > 0:
				if front_soldier_hp <= remaining_damage:
					remaining_damage -= front_soldier_hp
					soldiers_remaining -= 1
					if soldiers_remaining > 0:
						front_soldier_hp = hp_per_soldier
					else:
						front_soldier_hp = 0
				else:
					front_soldier_hp -= remaining_damage
					remaining_damage = 0
			current_hp = (soldiers_remaining - 1) * hp_per_soldier + front_soldier_hp if soldiers_remaining > 0 else 0
		else:
			current_hp = maxi(0, current_hp - amount)
		if current_hp <= 0:
			is_dead = true
			soldiers_remaining = 0
			front_soldier_hp = 0

func setup_terrain(terrain_data: Dictionary) -> void:
	battle_terrain = terrain_data

func get_terrain_at(pos: Vector2i) -> Enums.BattleTerrain:
	return battle_terrain.get(pos, Enums.BattleTerrain.OPEN)

func setup_unit(unit_instance: UnitInstance, unit_data: UnitData, side: int, pos: Vector2i,
		stance: Enums.UnitStance, priority: Enums.TargetPriority) -> BattleUnit:
	var bu := BattleUnit.new()
	bu.instance_id = unit_instance.instance_id
	bu.unit_data_id = unit_data.id
	bu.display_name = unit_data.display_name
	bu.side = side
	bu.anchor_pos = pos
	bu.max_hp = unit_data.max_hp
	bu.current_hp = unit_instance.current_hp
	bu.attack = unit_data.attack
	bu.defense = unit_data.melee_defense
	bu.speed = unit_data.speed
	bu.attack_range = unit_data.attack_range
	bu.stance = stance
	bu.target_priority = priority
	bu.tags = unit_data.tags.duplicate()

	# Soldier split initialization
	bu.squad_size = unit_data.squad_size
	bu.hp_per_soldier = unit_data.hp_per_soldier
	if unit_data.hp_per_soldier > 0 and unit_data.squad_size > 1:
		bu.soldiers_remaining = unit_data.squad_size
		# Compute front soldier HP from current_hp
		var full_soldiers := int(bu.current_hp / unit_data.hp_per_soldier)
		var remainder := bu.current_hp - full_soldiers * unit_data.hp_per_soldier
		if remainder > 0:
			bu.soldiers_remaining = full_soldiers + 1
			bu.front_soldier_hp = remainder
		else:
			bu.soldiers_remaining = full_soldiers
			bu.front_soldier_hp = unit_data.hp_per_soldier if full_soldiers > 0 else 0
	else:
		bu.soldiers_remaining = 1
		bu.front_soldier_hp = bu.current_hp

	# Determine formation type and max tiles
	bu.formation_type = _determine_formation_type(unit_data)
	bu.max_formation_tiles = _determine_max_tiles(bu.formation_type, unit_data)

	# Place formation tiles
	_place_formation(bu)

	if side == 0:
		attacker_units.append(bu)
	else:
		defender_units.append(bu)

	return bu

func _determine_formation_type(unit_data: UnitData) -> StringName:
	if unit_data.tags.has("monster"):
		return &"block"
	if unit_data.tags.has("cavalry"):
		return &"wedge"
	if unit_data.tags.has("infantry"):
		return &"line"
	if unit_data.tags.has("mage") or unit_data.tags.has("ranged"):
		return &"cluster"
	if unit_data.tags.has("fast") and not unit_data.tags.has("cavalry"):
		return &"blob"
	if unit_data.tags.has("construct") or (not unit_data.tags.has("infantry") and not unit_data.tags.has("cavalry") and unit_data.max_hp > 100):
		return &"block"
	# Default to line for anything else
	return &"line"

func _determine_max_tiles(formation_type: StringName, unit_data: UnitData = null) -> int:
	var base_tiles := 1
	match formation_type:
		&"line":   base_tiles = 4
		&"wedge":  base_tiles = 6
		&"block":  base_tiles = 4
		&"cluster": base_tiles = 4
		&"blob":   base_tiles = 5

	# Hybrid: squads get tiles from soldier count, monsters from formation type
	if unit_data and unit_data.hp_per_soldier > 0 and unit_data.squad_size > 1:
		return maxi(unit_data.squad_size, base_tiles)
	return base_tiles

func get_formation_size(unit: BattleUnit) -> int:
	if unit.hp_per_soldier > 0 and unit.squad_size > 1:
		# Squad: tile count = surviving soldiers, clamped to formation type base
		var base_tiles := 4 # fallback
		match unit.formation_type:
			&"line":   base_tiles = 4
			&"wedge":  base_tiles = 6
			&"block":  base_tiles = 4
			&"cluster": base_tiles = 4
			&"blob":   base_tiles = 5
		return maxi(1, mini(unit.soldiers_remaining, unit.max_formation_tiles))
	else:
		# Single entity: HP-ratio based
		var hp_ratio := float(unit.current_hp) / float(unit.max_hp)
		if hp_ratio > 0.75: return unit.max_formation_tiles
		if hp_ratio > 0.50: return ceili(unit.max_formation_tiles * 0.7)
		if hp_ratio > 0.25: return ceili(unit.max_formation_tiles * 0.4)
		return 1

func _place_formation(unit: BattleUnit) -> void:
	# Clear old tiles
	for tile in unit.occupied_tiles:
		if grid.get(tile) == unit:
			grid.erase(tile)
	unit.occupied_tiles.clear()

	var desired_size := get_formation_size(unit)
	var offsets := _get_formation_offsets(unit.formation_type, desired_size, unit.side)

	# Place anchor first
	unit.occupied_tiles.append(unit.anchor_pos)
	grid[unit.anchor_pos] = unit

	# Place additional tiles, skipping those that are occupied or impassable
	for offset in offsets:
		var tile_pos: Vector2i = unit.anchor_pos + offset
		if tile_pos.x < 0 or tile_pos.x >= GRID_WIDTH or tile_pos.y < 0 or tile_pos.y >= GRID_HEIGHT:
			continue
		if grid.has(tile_pos):
			continue
		if not BattleTerrainGen.is_passable(get_terrain_at(tile_pos)):
			continue
		unit.occupied_tiles.append(tile_pos)
		grid[tile_pos] = unit
		if unit.occupied_tiles.size() >= desired_size:
			break

func _get_formation_offsets(formation_type: StringName, size: int, side: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	# Side 0 (attacker) faces up, side 1 (defender) faces down
	var fwd := -1 if side == 0 else 1

	match formation_type:
		&"line":
			# Horizontal line: tiles to left and right of anchor
			offsets.append(Vector2i(-1, 0))
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(-2, 0))
			offsets.append(Vector2i(2, 0))
		&"wedge":
			# Wedge: point forward, expands backward
			offsets.append(Vector2i(-1, -fwd))
			offsets.append(Vector2i(1, -fwd))
			offsets.append(Vector2i(-2, -2 * fwd))
			offsets.append(Vector2i(0, -2 * fwd))
			offsets.append(Vector2i(2, -2 * fwd))
		&"block":
			# 2x2 block
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(0, 1))
			offsets.append(Vector2i(1, 1))
		&"cluster":
			# Compact 2x2
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(0, 1))
			offsets.append(Vector2i(1, 1))
		&"blob":
			# Irregular spread
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(-1, 0))
			offsets.append(Vector2i(0, fwd))
			offsets.append(Vector2i(1, -fwd))

	# Only return as many offsets as needed (size - 1 since anchor is already placed)
	var needed := mini(size - 1, offsets.size())
	var result: Array[Vector2i] = []
	for i in range(needed):
		result.append(offsets[i])
	return result

func update_formation(unit: BattleUnit) -> Array[Vector2i]:
	# Returns tiles that were removed (for visual fade-out)
	var old_tiles := unit.occupied_tiles.duplicate()
	_place_formation(unit)

	var removed: Array[Vector2i] = []
	for tile in old_tiles:
		if not unit.occupied_tiles.has(tile):
			removed.append(tile)
	return removed

func simulate_tick() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	tick_count += 1

	var all_units: Array[BattleUnit] = []
	for u in attacker_units:
		if not u.is_dead:
			all_units.append(u)
	for u in defender_units:
		if not u.is_dead:
			all_units.append(u)

	all_units.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.speed > b.speed)

	for unit in all_units:
		if unit.is_dead:
			continue

		var target := _find_target(unit)
		if target == null:
			continue

		var dist := _formation_distance(unit, target)

		if dist <= unit.attack_range:
			# Attack with terrain defense bonus
			var terrain_def := BattleTerrainGen.get_defense_bonus(get_terrain_at(target.anchor_pos))
			var damage := _calculate_damage(unit, target, terrain_def)
			var old_formation_size := target.occupied_tiles.size()
			target.take_damage(damage)

			actions.append({
				"type": "attack",
				"attacker_id": unit.instance_id,
				"attacker_pos": unit.anchor_pos,
				"defender_id": target.instance_id,
				"defender_pos": target.anchor_pos,
				"damage": damage,
				"target_hp": target.current_hp,
				"target_dead": target.is_dead,
				"attacker_range": unit.attack_range,
				"attacker_tags": unit.tags,
				"soldiers_remaining": target.soldiers_remaining,
			})

			if target.is_dead:
				# Remove all occupied tiles
				for tile in target.occupied_tiles:
					if grid.get(tile) == target:
						grid.erase(tile)
				actions.append({
					"type": "death",
					"unit_id": target.instance_id,
					"tiles": target.occupied_tiles.duplicate(),
				})
			else:
				# Check if formation should shrink
				var new_formation_size := get_formation_size(target)
				if new_formation_size < old_formation_size:
					var removed := update_formation(target)
					if not removed.is_empty():
						actions.append({
							"type": "formation_shrink",
							"unit_id": target.instance_id,
							"anchor_pos": target.anchor_pos,
							"new_tiles": target.occupied_tiles.duplicate(),
							"removed_tiles": removed,
						})
		else:
			# Move toward target
			if unit.stance == Enums.UnitStance.DEFENSIVE:
				if unit.attack_range <= 1:
					continue  # Melee defensive: hold position
				# Ranged defensive: advance cautiously (every other tick)
				if tick_count % 2 == 0:
					continue

			# Check terrain speed modifier at current position
			var terrain_speed := BattleTerrainGen.get_speed_modifier(get_terrain_at(unit.anchor_pos))
			if terrain_speed <= 0.0:
				continue # Shouldn't happen (unit on impassable) but safety check

			# Units in slow terrain might skip a tick
			if terrain_speed < 1.0:
				var skip_chance := 1.0 - terrain_speed
				var h := (tick_count * 31 + unit.anchor_pos.x * 17 + unit.anchor_pos.y * 13) & 0xFF
				if float(h) / 255.0 < skip_chance:
					continue

			var move_to := _get_move_toward(unit.anchor_pos, target.anchor_pos)
			if move_to != unit.anchor_pos and _can_place_at(unit, move_to):
				var old_pos := unit.anchor_pos
				# Remove old tiles from grid
				for tile in unit.occupied_tiles:
					if grid.get(tile) == unit:
						grid.erase(tile)
				unit.anchor_pos = move_to
				_place_formation(unit)

				actions.append({
					"type": "move",
					"unit_id": unit.instance_id,
					"from": old_pos,
					"to": move_to,
					"tiles": unit.occupied_tiles.duplicate(),
				})

	# Check win condition
	var attackers_alive := _count_alive(attacker_units)
	var defenders_alive := _count_alive(defender_units)

	if attackers_alive == 0 or defenders_alive == 0:
		is_finished = true
		if attackers_alive > 0:
			winner_side = 0
		elif defenders_alive > 0:
			winner_side = 1
		else:
			winner_side = 1

	if tick_count >= 100 and not is_finished:
		is_finished = true
		winner_side = 1

	return actions

func _can_place_at(unit: BattleUnit, anchor: Vector2i) -> bool:
	if anchor.x < 0 or anchor.x >= GRID_WIDTH or anchor.y < 0 or anchor.y >= GRID_HEIGHT:
		return false
	if not BattleTerrainGen.is_passable(get_terrain_at(anchor)):
		return false
	# Check if anchor is free (or occupied by this unit)
	var occupant = grid.get(anchor)
	if occupant != null and occupant != unit:
		return false
	return true

func _find_target(unit: BattleUnit) -> BattleUnit:
	var enemies: Array[BattleUnit] = []
	if unit.side == 0:
		for u in defender_units:
			if not u.is_dead:
				enemies.append(u)
	else:
		for u in attacker_units:
			if not u.is_dead:
				enemies.append(u)

	if enemies.is_empty():
		return null

	match unit.target_priority:
		Enums.TargetPriority.CLOSEST:
			enemies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				return _formation_distance(unit, a) < _formation_distance(unit, b))
		Enums.TargetPriority.WEAKEST:
			enemies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				return a.current_hp < b.current_hp)
		Enums.TargetPriority.STRONGEST:
			enemies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				return a.attack > b.attack)
		Enums.TargetPriority.RANGED_FIRST:
			enemies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				return a.attack_range > b.attack_range)
		Enums.TargetPriority.SUPPORT_FIRST:
			enemies.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				var a_support: int = 1 if a.stance == Enums.UnitStance.SUPPORT else 0
				var b_support: int = 1 if b.stance == Enums.UnitStance.SUPPORT else 0
				return a_support > b_support)

	return enemies[0]

func _formation_distance(a: BattleUnit, b: BattleUnit) -> int:
	# Minimum manhattan distance between any tile of a and any tile of b
	var min_dist := 999
	for i in a.occupied_tiles.size():
		var ta: Vector2i = a.occupied_tiles[i]
		for j in b.occupied_tiles.size():
			var tb: Vector2i = b.occupied_tiles[j]
			var d: int = abs(ta.x - tb.x) + abs(ta.y - tb.y)
			if d < min_dist:
				min_dist = d
	return min_dist

func _calculate_damage(attacker: BattleUnit, defender: BattleUnit, terrain_defense_bonus: int = 0) -> int:
	var effective_defense := defender.defense + terrain_defense_bonus
	var base_damage: int = maxi(1, attacker.attack - effective_defense)

	if attacker.stance == Enums.UnitStance.AGGRESSIVE:
		base_damage = int(base_damage * 1.25)
	if defender.stance == Enums.UnitStance.DEFENSIVE:
		base_damage = int(base_damage * 0.75)

	var variance := randf_range(0.85, 1.15)
	base_damage = int(base_damage * variance)

	return maxi(1, base_damage)

func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _get_move_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	var move := Vector2i.ZERO

	if abs(diff.x) >= abs(diff.y):
		move.x = signi(diff.x)
	else:
		move.y = signi(diff.y)

	var target_pos := from + move
	target_pos.x = clampi(target_pos.x, 0, GRID_WIDTH - 1)
	target_pos.y = clampi(target_pos.y, 0, GRID_HEIGHT - 1)

	# If target is impassable, try the other axis
	if not BattleTerrainGen.is_passable(get_terrain_at(target_pos)):
		move = Vector2i.ZERO
		if abs(diff.x) < abs(diff.y):
			move.x = signi(diff.x) if diff.x != 0 else 1
		else:
			move.y = signi(diff.y) if diff.y != 0 else 1
		target_pos = from + move
		target_pos.x = clampi(target_pos.x, 0, GRID_WIDTH - 1)
		target_pos.y = clampi(target_pos.y, 0, GRID_HEIGHT - 1)
		if not BattleTerrainGen.is_passable(get_terrain_at(target_pos)):
			return from

	return target_pos

func _count_alive(units: Array[BattleUnit]) -> int:
	var count := 0
	for u in units:
		if not u.is_dead:
			count += 1
	return count

func get_surviving_units(side: int) -> Array[BattleUnit]:
	var units: Array[BattleUnit] = attacker_units if side == 0 else defender_units
	var result: Array[BattleUnit] = []
	for u in units:
		if not u.is_dead:
			result.append(u)
	return result

func get_unit_at(pos: Vector2i) -> BattleUnit:
	return grid.get(pos)

func reposition_unit(unit: BattleUnit, new_anchor: Vector2i) -> void:
	## Move a unit to a new anchor position and rebuild its formation.
	# Clear old grid entries
	for tile in unit.occupied_tiles:
		if grid.get(tile) == unit:
			grid.erase(tile)
	unit.occupied_tiles.clear()
	unit.anchor_pos = new_anchor
	_place_formation(unit)
