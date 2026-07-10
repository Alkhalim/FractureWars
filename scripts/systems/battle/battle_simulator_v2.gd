class_name BattleSimulatorV2
extends RefCounted

signal tick_completed(actions: Array[Dictionary])
signal battle_ended(winner_side: int)

var grid_width: int = 30
var grid_height: int = 20
var grid: Dictionary = {}             # Vector2i -> BattleFormation
var terrain: Dictionary = {}          # Vector2i -> Enums.BattleTerrain
var attacker_formations: Array[BattleFormation] = []
var defender_formations: Array[BattleFormation] = []
var tick_count: int = 0
var max_ticks: int = 3000
var is_finished: bool = false
var winner_side: int = -1
var captives: Dictionary = {0: 0, 1: 0}  # side -> captive count
var recent_deaths: Array[Dictionary] = [] # {side, anchor_pos, tick}

var deploy_top_end: int = 5       # Defender zone: rows 0..deploy_top_end-1
var deploy_bottom_start: int = 15 # Attacker zone: rows deploy_bottom_start..grid_height-1

# --- BattleFormation Inner Class ---

class BattleFormation:
	var instance_id: StringName
	var unit_data_id: StringName
	var display_name: String
	var side: int
	var tags: Array[String] = []

	# Stats
	var attack: int
	var defense: int
	var speed: int
	var attack_range: int
	var tiles_per_entity: int = 1

	# Entity/HP tracking
	var total_entities: int
	var entities_alive: int
	var hp_per_entity: int
	var front_entity_hp: int
	var max_hp: int
	var current_hp: int

	# Formation geometry
	var anchor_pos: Vector2i
	var facing: Vector2i = Vector2i(0, -1)  # Default: facing up
	var occupied_tiles: Array[Vector2i] = []
	var max_anchor_span: int = 0 # max manhattan distance of any occupied tile from anchor (set in _build_formation)

	# Morale
	var base_morale: int = 50
	var current_morale: float = 50.0
	var is_routing: bool = false
	var rally_cooldown: int = 0

	# Orders
	var current_order: Enums.BattleOrder = Enums.BattleOrder.ADVANCE
	var target_priority: Enums.TargetPriority = Enums.TargetPriority.CLOSEST
	var stance: Enums.UnitStance = Enums.UnitStance.AGGRESSIVE

	# Aura
	var morale_aura: int = 0
	var fear_radius: int = 0
	var captive_chance: float = 0.3

	var is_dead: bool = false
	var is_fled: bool = false
	var damage_dealt: int = 0

	func take_damage(amount: int) -> int:
		# Returns entities killed this hit
		var entities_before := entities_alive
		if hp_per_entity > 0 and total_entities > 1:
			var remaining_damage := amount
			while remaining_damage > 0 and entities_alive > 0:
				if front_entity_hp <= remaining_damage:
					remaining_damage -= front_entity_hp
					entities_alive -= 1
					if entities_alive > 0:
						front_entity_hp = hp_per_entity
					else:
						front_entity_hp = 0
				else:
					front_entity_hp -= remaining_damage
					remaining_damage = 0
			current_hp = (entities_alive - 1) * hp_per_entity + front_entity_hp if entities_alive > 0 else 0
		else:
			current_hp = maxi(0, current_hp - amount)
			if current_hp <= 0:
				entities_alive = 0
		if current_hp <= 0:
			is_dead = true
			entities_alive = 0
			front_entity_hp = 0
		return entities_before - entities_alive

# --- Grid Sizing ---

func compute_grid_size(attacker_army: ArmyState, defender_army: ArmyState) -> void:
	var total_tiles := 0
	for unit in attacker_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			total_tiles += ud.squad_size * ud.tiles_per_entity
	for unit in defender_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			total_tiles += ud.squad_size * ud.tiles_per_entity

	var target_area := total_tiles * 12
	grid_width = ceili(sqrt(target_area * 1.5))
	grid_height = ceili(float(target_area) / float(grid_width))
	grid_width = clampi(grid_width, 60, 200)
	grid_height = clampi(grid_height, 40, 150)

	# Deploy zones: top 25% for defender, bottom 25% for attacker
	deploy_top_end = ceili(grid_height * 0.25)
	deploy_bottom_start = grid_height - ceili(grid_height * 0.25)

# --- Setup ---

func setup_terrain(terrain_data: Dictionary) -> void:
	terrain = terrain_data

func setup_attacker_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	var col_cursor := 2
	var row_offset := 0
	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var f := _create_formation(unit, ud, 0, cmd_bonuses)
		var tile_count := ud.squad_size * ud.tiles_per_entity
		var width := mini(tile_count, 10) + 2
		if col_cursor + width > grid_width - 2:
			col_cursor = 2
			row_offset += 3
		var col := clampi(col_cursor, 2, grid_width - width - 2)
		var row := deploy_bottom_start + 2 + row_offset
		f.anchor_pos = Vector2i(col, clampi(row, deploy_bottom_start, grid_height - 2))
		f.facing = Vector2i(0, -1)  # Face up toward enemy
		attacker_formations.append(f)
		_build_formation(f)
		col_cursor = col + width

func setup_defender_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	var col_cursor := 2
	var row_offset := 0
	for unit in army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var f := _create_formation(unit, ud, 1, cmd_bonuses)
		var tile_count := ud.squad_size * ud.tiles_per_entity
		var width := mini(tile_count, 10) + 2
		if col_cursor + width > grid_width - 2:
			col_cursor = 2
			row_offset += 3
		var col := clampi(col_cursor, 2, grid_width - width - 2)
		var row := deploy_top_end - 3 - row_offset
		f.anchor_pos = Vector2i(col, clampi(row, 1, deploy_top_end - 1))
		f.facing = Vector2i(0, 1)   # Face down toward enemy
		defender_formations.append(f)
		_build_formation(f)
		col_cursor = col + width

func _create_formation(unit: UnitInstance, ud: UnitData, side: int, cmd_bonuses: Dictionary) -> BattleFormation:
	var f := BattleFormation.new()
	f.instance_id = unit.instance_id
	f.unit_data_id = ud.id
	f.display_name = ud.display_name
	f.side = side
	f.tags = ud.tags.duplicate()
	var atk_bonus: int = cmd_bonuses.get("attack_bonus", 0)
	var def_bonus: int = cmd_bonuses.get("defense_bonus", 0)
	# Research combat bonuses
	var r_eff := GameManager.research_system.get_research_effects(ud.faction_id)
	f.attack = ud.attack + atk_bonus + r_eff.get("unit_attack_bonus", 0)
	f.defense = ud.melee_defense + def_bonus + r_eff.get("unit_defense_bonus", 0)

	# Faction mechanic combat bonuses
	var fs: FactionState = GameManager.state.faction_states.get(ud.faction_id)
	if fs:
		if ud.faction_id == &"skulloath":
			if fs.corruption >= 81:
				f.attack += int(f.attack * 0.25)
			elif fs.corruption >= 61:
				f.attack += int(f.attack * 0.15)
		elif ud.faction_id == &"tainted_jade":
			if fs.taint_power >= 50:
				f.defense += int(f.defense * 0.15)
			elif fs.taint_power >= 20:
				f.defense += int(f.defense * 0.10)
		elif ud.faction_id == &"shardhorde":
			for realm_key in fs.shard_resonance:
				if realm_key == Enums.Realm.VOID:
					f.attack += int(f.attack * 0.10)
				else:
					f.attack += int(f.attack * 0.05)
		elif ud.faction_id == &"moonspear":
			match fs.lunar_phase:
				0: f.attack += int(f.attack * 0.10)
				2: f.defense += int(f.defense * 0.10)
		elif ud.faction_id == &"thunderswarm":
			if fs.storm_fury >= 80:
				f.attack += int(f.attack * 0.20)
				f.defense -= int(f.defense * 0.05)
			elif fs.storm_fury >= 50:
				f.attack += int(f.attack * 0.10)
		elif ud.faction_id == &"cinderguard":
			if fs.border_vigilance <= 30:
				f.defense += int(f.defense * 0.15)
			elif fs.border_vigilance >= 85:
				f.attack += int(f.attack * 0.05)
		elif ud.faction_id == &"ivoryscar":
			if fs.relic_power >= 30:
				f.defense += int(f.defense * 0.10)
			elif fs.relic_power >= 15:
				f.defense += int(f.defense * 0.05)
		elif ud.faction_id == &"sunblessed":
			if fs.solar_faith >= 85:
				f.attack += int(f.attack * 0.10)
				f.defense += int(f.defense * 0.05)
			elif fs.solar_faith >= 70:
				f.attack += int(f.attack * 0.05)

	# Veterancy bonuses
	var vet_bonus := unit.get_veterancy_bonus()
	if vet_bonus > 0.0:
		f.attack += int(float(f.attack) * vet_bonus)
		f.defense += int(float(f.defense) * vet_bonus)
	f.speed = ud.speed
	if vet_bonus > 0.0:
		f.speed += int(float(f.speed) * vet_bonus)
	f.attack_range = ud.attack_range
	f.tiles_per_entity = ud.tiles_per_entity
	f.max_hp = unit.current_hp  # Use current HP from campaign
	f.current_hp = unit.current_hp

	# Entity tracking
	if ud.hp_per_soldier > 0 and ud.squad_size > 1:
		f.hp_per_entity = ud.hp_per_soldier
		f.total_entities = ud.squad_size
		# Calculate alive entities from current HP
		f.entities_alive = ceili(float(unit.current_hp) / float(ud.hp_per_soldier))
		f.entities_alive = clampi(f.entities_alive, 1, ud.squad_size)
		f.front_entity_hp = unit.current_hp - (f.entities_alive - 1) * ud.hp_per_soldier
		if f.front_entity_hp <= 0:
			f.front_entity_hp = ud.hp_per_soldier
	else:
		f.hp_per_entity = ud.max_hp
		f.total_entities = 1
		f.entities_alive = 1
		f.front_entity_hp = unit.current_hp

	# Morale
	f.base_morale = ud.base_morale + r_eff.get("unit_morale_bonus", 0)
	f.current_morale = float(f.base_morale)
	f.morale_aura = ud.morale_aura
	f.fear_radius = ud.fear_radius
	f.captive_chance = ud.captive_chance

	# Default stance from tags
	if ud.tags.has("ranged") or ud.tags.has("mage"):
		f.stance = Enums.UnitStance.DEFENSIVE
	elif ud.tags.has("cavalry") or ud.tags.has("fast"):
		f.stance = Enums.UnitStance.AGGRESSIVE

	return f

# --- Formation Geometry ---

func _build_formation(f: BattleFormation) -> void:
	# Clear old tiles
	for tile in f.occupied_tiles:
		if grid.get(tile) == f:
			grid.erase(tile)
	f.occupied_tiles.clear()

	var tile_count: int
	if f.total_entities == 1:
		# Single entity: tile count based on HP ratio
		var hp_ratio := float(f.current_hp) / float(f.max_hp)
		tile_count = maxi(1, ceili(f.tiles_per_entity * hp_ratio))
	else:
		tile_count = f.entities_alive * f.tiles_per_entity

	# Place anchor
	if _in_bounds(f.anchor_pos) and not grid.has(f.anchor_pos):
		f.occupied_tiles.append(f.anchor_pos)
		grid[f.anchor_pos] = f
	elif _in_bounds(f.anchor_pos):
		# Anchor occupied - find nearby free spot
		var free := _find_free_adjacent(f.anchor_pos)
		if free != Vector2i(-1, -1):
			f.anchor_pos = free
			f.occupied_tiles.append(f.anchor_pos)
			grid[f.anchor_pos] = f
		else:
			return

	if tile_count <= 1:
		return

	# Generate offsets perpendicular to facing
	var perp := Vector2i(-f.facing.y, f.facing.x)
	var offsets := _layout_rectangle(tile_count - 1, perp, f.facing)

	for offset in offsets:
		var pos := f.anchor_pos + offset
		if _in_bounds(pos) and not grid.has(pos) and _is_passable(pos):
			f.occupied_tiles.append(pos)
			grid[pos] = f
	# Track the formation's spatial extent for distance-scan pruning
	f.max_anchor_span = 0
	for tile in f.occupied_tiles:
		var span := _grid_distance(tile, f.anchor_pos)
		if span > f.max_anchor_span:
			f.max_anchor_span = span

func _layout_rectangle(tile_count: int, perp: Vector2i, depth_dir: Vector2i) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	# Determine row width: up to 10 wide, then wrap to deeper rows
	var row_width := mini(tile_count, 10)
	var rows := ceili(float(tile_count) / float(row_width))

	var placed := 0
	for row in rows:
		var tiles_this_row := mini(row_width, tile_count - placed)
		var start := -tiles_this_row / 2
		for i in tiles_this_row:
			var lateral := start + i
			# depth_dir points forward, so behind = -depth_dir
			var offset := perp * lateral + depth_dir * (-row)
			if offset != Vector2i.ZERO:  # Skip anchor position
				offsets.append(offset)
			placed += 1
			if placed >= tile_count:
				break
		if placed >= tile_count:
			break
	return offsets

# --- Tick Simulation ---

func simulate_tick() -> Array[Dictionary]:
	tick_count += 1
	var actions: Array[Dictionary] = []

	var all := _get_all_alive()
	all.sort_custom(func(a: BattleFormation, b: BattleFormation) -> bool: return a.speed > b.speed)

	# Phase 1: Movement
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		if f.is_routing:
			actions.append_array(_execute_rout_movement(f))
			continue
		if _is_in_melee_contact(f):
			continue  # Locked in combat
		actions.append_array(_execute_order_movement(f))

	# Phase 2: Melee combat (all pairs in contact)
	var combat_pairs := _find_all_contact_pairs()
	for pair in combat_pairs:
		var fa: BattleFormation = pair[0]
		var fb: BattleFormation = pair[1]
		actions.append_array(_resolve_combat_pair(fa, fb))

	# Phase 3: Ranged attacks
	for f in all:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		if f.attack_range <= 1:
			continue
		if _is_in_melee_contact(f):
			continue
		actions.append_array(_execute_ranged_attack(f))

	# Phase 4: Morale updates
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		_update_morale(f)

	# Phase 5: Rebuild formations for units that lost entities
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		_build_formation(f)

	# Phase 6: Check win condition
	_check_victory()

	# Clean stale deaths (older than 5 ticks) — in place, preserving order
	for i in range(recent_deaths.size() - 1, -1, -1):
		if recent_deaths[i].tick < tick_count - 5:
			recent_deaths.remove_at(i)

	tick_completed.emit(actions)
	return actions

# --- Movement ---

func _execute_order_movement(f: BattleFormation) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var move_tiles := maxi(1, f.speed / 3)
	var target := _find_target(f)
	if target == null:
		return actions

	match f.current_order:
		Enums.BattleOrder.ADVANCE:
			var dir := _direction_toward(f.anchor_pos, target.anchor_pos)
			_move_formation(f, dir, move_tiles)
			# Auto-rotate to face target when close
			if _formation_distance(f, target) <= 10:
				_rotate_toward(f, target.anchor_pos)
			actions.append({"type": "move", "id": f.instance_id, "to": f.anchor_pos})

		Enums.BattleOrder.HOLD:
			# Don't move, just rotate
			_rotate_toward(f, target.anchor_pos)

		Enums.BattleOrder.FLANK_LEFT:
			var fwd := _direction_toward(f.anchor_pos, target.anchor_pos)
			var left := Vector2i(fwd.y, -fwd.x)  # 90 degrees left
			var diag := _normalize_dir(fwd + left)
			_move_formation(f, diag, move_tiles)
			_rotate_toward(f, target.anchor_pos)
			actions.append({"type": "move", "id": f.instance_id, "to": f.anchor_pos})

		Enums.BattleOrder.FLANK_RIGHT:
			var fwd := _direction_toward(f.anchor_pos, target.anchor_pos)
			var right := Vector2i(-fwd.y, fwd.x)  # 90 degrees right
			var diag := _normalize_dir(fwd + right)
			_move_formation(f, diag, move_tiles)
			_rotate_toward(f, target.anchor_pos)
			actions.append({"type": "move", "id": f.instance_id, "to": f.anchor_pos})

		Enums.BattleOrder.CHARGE:
			var dir := _direction_toward(f.anchor_pos, target.anchor_pos)
			_move_formation(f, dir, move_tiles * 2)  # Double speed
			_rotate_toward(f, target.anchor_pos)
			actions.append({"type": "charge", "id": f.instance_id, "to": f.anchor_pos})

		Enums.BattleOrder.RETREAT:
			var retreat_dir := Vector2i(0, 1) if f.side == 0 else Vector2i(0, -1)
			_move_formation(f, retreat_dir, move_tiles)
			actions.append({"type": "retreat", "id": f.instance_id, "to": f.anchor_pos})

	return actions

func _execute_rout_movement(f: BattleFormation) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	# Route toward retreat edge at 2x speed
	var retreat_dir := Vector2i(0, 1) if f.side == 0 else Vector2i(0, -1)
	var move_tiles := maxi(2, ceili(f.speed * 0.75))
	_move_formation(f, retreat_dir, move_tiles)
	actions.append({"type": "rout", "id": f.instance_id, "to": f.anchor_pos})

	# Check if reached retreat edge
	if f.side == 0 and f.anchor_pos.y >= grid_height - 1:
		_remove_formation(f)
		f.is_fled = true
	elif f.side == 1 and f.anchor_pos.y <= 0:
		_remove_formation(f)
		f.is_fled = true

	return actions

func _move_formation(f: BattleFormation, dir: Vector2i, tiles: int) -> void:
	# Clear current tiles
	for tile in f.occupied_tiles:
		if grid.get(tile) == f:
			grid.erase(tile)
	f.occupied_tiles.clear()

	for _i in tiles:
		var new_pos := f.anchor_pos + dir
		if not _in_bounds(new_pos):
			break
		if grid.has(new_pos) and grid[new_pos] != f:
			# Try to step around
			var alt1 := f.anchor_pos + Vector2i(dir.y, dir.x)
			var alt2 := f.anchor_pos + Vector2i(-dir.y, -dir.x)
			if _in_bounds(alt1) and not grid.has(alt1) and _is_passable(alt1):
				new_pos = alt1
			elif _in_bounds(alt2) and not grid.has(alt2) and _is_passable(alt2):
				new_pos = alt2
			else:
				break
		if not _is_passable(new_pos):
			break
		f.anchor_pos = new_pos

	# Rebuild will happen in phase 5
	# But place anchor now to prevent overlap
	if _in_bounds(f.anchor_pos):
		f.occupied_tiles.append(f.anchor_pos)
		grid[f.anchor_pos] = f

# --- Contact Combat ---

func _find_all_contact_pairs() -> Array[Array]:
	var pairs: Array[Array] = []
	var checked: Dictionary = {} # formation -> Dictionary of partner formations (no string keys)

	for f in attacker_formations:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		for tile in f.occupied_tiles:
			for off in _CONTACT_OFFSETS:
				var other: BattleFormation = grid.get(tile + off)
				if other == null or other == f or other.side == f.side:
					continue
				if other.is_dead or other.is_fled:
					continue
				var f_checked: Dictionary = checked.get_or_add(f, {})
				if not f_checked.has(other) and not (checked.get(other, {}) as Dictionary).has(f):
					f_checked[other] = true
					pairs.append([f, other])
	return pairs

func _resolve_combat_pair(a: BattleFormation, b: BattleFormation) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# A attacks B
	var result_ab := _resolve_melee_combat(a, b)
	var ab_dmg: int = result_ab.damage
	if ab_dmg > 0:
		a.damage_dealt += ab_dmg
		var killed := b.take_damage(ab_dmg)
		var ab_morale_dmg: float = result_ab.morale_damage
		b.current_morale -= ab_morale_dmg
		# Morale hit from entity losses
		if b.total_entities > 1 and killed > 0:
			b.current_morale -= killed * 3.0
		var ab_contact: int = result_ab.contact
		var ab_flank: int = result_ab.flank
		var ab_rear: int = result_ab.rear
		actions.append({
			"type": "melee_hit", "attacker": a.instance_id, "defender": b.instance_id,
			"damage": ab_dmg, "killed": killed,
			"contact": ab_contact, "flank": ab_flank, "rear": ab_rear
		})
		if killed > 0:
			var caps := _generate_captives(a, b, killed)
			if caps > 0:
				actions.append({"type": "captive", "side": a.side, "count": caps})
		if b.is_dead:
			recent_deaths.append({"side": b.side, "anchor_pos": b.anchor_pos, "tick": tick_count})
			_remove_formation(b)

	# B attacks A (if still alive)
	if not b.is_dead and not b.is_fled:
		var result_ba := _resolve_melee_combat(b, a)
		var ba_dmg: int = result_ba.damage
		if ba_dmg > 0:
			b.damage_dealt += ba_dmg
			var killed := a.take_damage(ba_dmg)
			var ba_morale_dmg: float = result_ba.morale_damage
			a.current_morale -= ba_morale_dmg
			if a.total_entities > 1 and killed > 0:
				a.current_morale -= killed * 3.0
			var ba_contact: int = result_ba.contact
			var ba_flank: int = result_ba.flank
			var ba_rear: int = result_ba.rear
			actions.append({
				"type": "melee_hit", "attacker": b.instance_id, "defender": a.instance_id,
				"damage": ba_dmg, "killed": killed,
				"contact": ba_contact, "flank": ba_flank, "rear": ba_rear
			})
			if killed > 0:
				var caps := _generate_captives(b, a, killed)
				if caps > 0:
					actions.append({"type": "captive", "side": b.side, "count": caps})
			if a.is_dead:
				recent_deaths.append({"side": a.side, "anchor_pos": a.anchor_pos, "tick": tick_count})
				_remove_formation(a)

	# Charge bonus: +25% attack, -25% defense for this tick
	if a.current_order == Enums.BattleOrder.CHARGE and not a.is_dead:
		a.current_order = Enums.BattleOrder.ADVANCE  # Reset after contact

	return actions

func _resolve_melee_combat(attacker: BattleFormation, defender: BattleFormation) -> Dictionary:
	var front_contact := 0
	var flank_contact := 0
	var rear_contact := 0

	for a_tile in attacker.occupied_tiles:
		for d_tile in defender.occupied_tiles:
			if absi(a_tile.x - d_tile.x) + absi(a_tile.y - d_tile.y) == 1:
				var dir := a_tile - d_tile  # direction from defender toward attacker
				var dot := dir.x * defender.facing.x + dir.y * defender.facing.y
				if dot > 0:
					front_contact += 1
				elif dot < 0:
					rear_contact += 1
				else:
					flank_contact += 1

	var total_contact := front_contact + flank_contact + rear_contact
	if total_contact == 0:
		return {"damage": 0, "morale_damage": 0.0, "contact": 0, "flank": 0, "rear": 0}

	var per_tile_dps := maxf(1.0, float(attacker.attack) - float(defender.defense) * 0.5)
	var total_damage := int(per_tile_dps * total_contact * randf_range(0.85, 1.15))

	# Stance modifiers
	if attacker.stance == Enums.UnitStance.AGGRESSIVE:
		total_damage = int(total_damage * 1.2)
	if defender.stance == Enums.UnitStance.DEFENSIVE:
		total_damage = int(total_damage * 0.8)

	# Charge bonus
	if attacker.current_order == Enums.BattleOrder.CHARGE:
		total_damage = int(total_damage * 1.25)

	# Morale damage from flanks/rear
	var morale_dmg := flank_contact * 1.5 + rear_contact * 3.0

	return {"damage": maxi(1, total_damage), "morale_damage": morale_dmg, "contact": total_contact, "flank": flank_contact, "rear": rear_contact}

# --- Ranged Combat ---

func _execute_ranged_attack(f: BattleFormation) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var target := _find_target(f)
	if target == null:
		return actions

	var dist := _formation_distance(f, target)
	if dist > f.attack_range * 3:  # Range in grid tiles (range stat * 3)
		return actions

	var dmg_per_entity := maxf(0.5, float(f.attack) * 0.6 - float(target.defense) * 0.3)
	var total_damage := int(dmg_per_entity * f.entities_alive * randf_range(0.8, 1.2))
	total_damage = maxi(1, total_damage)

	f.damage_dealt += total_damage
	var killed := target.take_damage(total_damage)
	target.current_morale -= 1.5  # Bombardment fear

	actions.append({
		"type": "ranged_hit", "attacker": f.instance_id, "defender": target.instance_id,
		"damage": total_damage, "killed": killed
	})

	if killed > 0:
		# Very low captive chance for ranged
		var caps := _generate_captives(f, target, killed)
		if caps > 0:
			actions.append({"type": "captive", "side": f.side, "count": caps})

	if target.is_dead:
		recent_deaths.append({"side": target.side, "anchor_pos": target.anchor_pos, "tick": tick_count})
		_remove_formation(target)

	return actions

# --- Morale System ---

func _update_morale(f: BattleFormation) -> void:
	var delta := 0.0

	# Routing units get no passive recovery — they keep fleeing until off the map
	# (only friendly auras can save them)
	if not f.is_routing:
		# Passive recovery
		delta += 1.0
		if not _is_in_melee_contact(f):
			delta += 1.0

		# Friendly flank support
		delta += _count_friendly_flank_support(f) * 1.5

	# Friendly morale auras (can still affect routing units — inspiring leaders)
	for ally in _get_side_formations(f.side):
		if ally == f or ally.is_dead:
			continue
		if ally.morale_aura > 0 and ally.fear_radius > 0:
			if _formation_distance(f, ally) <= ally.fear_radius:
				delta += ally.morale_aura * 0.5

	# Enemy monster fear
	for enemy in _get_side_formations(1 - f.side):
		if enemy.is_dead:
			continue
		if enemy.morale_aura < 0 and enemy.fear_radius > 0:
			if _formation_distance(f, enemy) <= enemy.fear_radius:
				delta += enemy.morale_aura * 0.5  # Negative value

	# Nearby ally deaths
	for death in recent_deaths:
		var death_side: int = death.get("side", -1)
		var death_tick: int = death.get("tick", 0)
		var death_pos: Vector2i = death.get("anchor_pos", Vector2i.ZERO)
		if death_side == f.side and death_tick >= tick_count - 3:
			if _grid_distance(f.anchor_pos, death_pos) <= 8:
				delta -= 4.0

	f.current_morale = clampf(f.current_morale + delta, -30.0, f.base_morale * 1.5)

	# Routing check
	if f.current_morale <= 0.0 and not f.is_routing and f.rally_cooldown <= 0:
		f.is_routing = true

	# Rally check (harder to rally — need more morale since recovery is limited)
	if f.is_routing and f.current_morale > float(f.base_morale) * 0.3:
		f.is_routing = false
		f.rally_cooldown = 8

	if f.rally_cooldown > 0:
		f.rally_cooldown -= 1

# --- Captive Generation ---

func _generate_captives(killer: BattleFormation, victim: BattleFormation, entities_killed: int) -> int:
	var chance := victim.captive_chance
	if killer.tags.has("ranged") or killer.tags.has("mage"):
		chance *= 0.1
	elif killer.tags.has("monster"):
		chance *= 0.05
	elif killer.tags.has("infantry") and killer.tags.has("melee"):
		chance *= 1.0  # Full

	var count := 0
	for i in entities_killed:
		if randf() < chance:
			count += 1
	var prev_captives: int = captives.get(killer.side, 0)
	captives[killer.side] = prev_captives + count
	return count

# --- AI Order Assignment ---

func assign_ai_orders(side: int) -> void:
	for f in _get_side_formations(side):
		if f.is_dead or f.is_fled:
			continue
		if f.tags.has("cavalry") or f.tags.has("fast"):
			if _enemy_has_exposed_flank(f):
				f.current_order = Enums.BattleOrder.FLANK_LEFT
			else:
				f.current_order = Enums.BattleOrder.CHARGE
		elif f.tags.has("ranged") or f.tags.has("mage"):
			f.current_order = Enums.BattleOrder.HOLD
		elif f.tags.has("monster"):
			f.current_order = Enums.BattleOrder.ADVANCE
		else:
			f.current_order = Enums.BattleOrder.ADVANCE

func assign_ai_orders_both_sides() -> void:
	assign_ai_orders(0)
	assign_ai_orders(1)

# --- Victory Check ---

func _check_victory() -> void:
	var atk_alive := false
	var def_alive := false
	for f in attacker_formations:
		if not f.is_dead and not f.is_fled:
			atk_alive = true
			break
	for f in defender_formations:
		if not f.is_dead and not f.is_fled:
			def_alive = true
			break

	if not atk_alive and not def_alive:
		is_finished = true
		winner_side = -1  # Draw
	elif not atk_alive:
		is_finished = true
		winner_side = 1
		battle_ended.emit(1)
	elif not def_alive:
		is_finished = true
		winner_side = 0
		battle_ended.emit(0)
	elif tick_count >= max_ticks:
		is_finished = true
		# Defender wins on timeout (held the field)
		winner_side = 1
		battle_ended.emit(1)

# --- Surviving Units Query ---

func get_surviving_formations(side: int) -> Array[BattleFormation]:
	var result: Array[BattleFormation] = []
	var formations := attacker_formations if side == 0 else defender_formations
	for f in formations:
		if not f.is_dead:
			result.append(f)
	return result

# --- Helper Functions ---

func _get_all_alive() -> Array[BattleFormation]:
	var result: Array[BattleFormation] = []
	for f in attacker_formations:
		if not f.is_dead and not f.is_fled:
			result.append(f)
	for f in defender_formations:
		if not f.is_dead and not f.is_fled:
			result.append(f)
	return result

func _get_side_formations(side: int) -> Array[BattleFormation]:
	return attacker_formations if side == 0 else defender_formations

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height

func _is_passable(pos: Vector2i) -> bool:
	var t: Enums.BattleTerrain = terrain.get(pos, Enums.BattleTerrain.OPEN)
	return BattleTerrainGen.is_passable(t)

func _get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [
		pos + Vector2i(1, 0), pos + Vector2i(-1, 0),
		pos + Vector2i(0, 1), pos + Vector2i(0, -1)
	]
	return result

func _find_free_adjacent(pos: Vector2i) -> Vector2i:
	for n in _get_neighbors(pos):
		if _in_bounds(n) and not grid.has(n) and _is_passable(n):
			return n
	return Vector2i(-1, -1)

func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

const _CONTACT_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func _formation_distance(a: BattleFormation, b: BattleFormation) -> int:
	# Minimum distance between any tiles of the two formations. The inner scan
	# is pruned via the triangle inequality: every tile of b lies within
	# b.max_anchor_span of b's anchor, so |ta - b.anchor| - span is a lower
	# bound for ta's best possible distance — skipped when it cannot beat the
	# current minimum. Result is exact.
	var min_dist := 99999
	var b_anchor := b.anchor_pos
	var b_span := b.max_anchor_span
	for ta in a.occupied_tiles:
		if _grid_distance(ta, b_anchor) - b_span >= min_dist:
			continue
		for tb in b.occupied_tiles:
			var d := _grid_distance(ta, tb)
			if d < min_dist:
				min_dist = d
	return min_dist

func _is_in_melee_contact(f: BattleFormation) -> bool:
	# Inline neighbor offsets (no per-tile Array allocation). NOTE: caching
	# this per tick is NOT safe — movement (phase 1) and ranged kills
	# (phase 3) change the grid between calls within a single tick.
	for tile in f.occupied_tiles:
		for off in _CONTACT_OFFSETS:
			var other: BattleFormation = grid.get(tile + off)
			if other != null and other.side != f.side and not other.is_dead and not other.is_fled:
				return true
	return false

func _find_target(f: BattleFormation) -> BattleFormation:
	var enemies := _get_side_formations(1 - f.side)
	var best: BattleFormation = null
	var best_score := 99999.0

	for e in enemies:
		if e.is_dead or e.is_fled:
			continue
		var dist := _formation_distance(f, e)
		var score: float

		match f.target_priority:
			Enums.TargetPriority.CLOSEST:
				score = float(dist)
			Enums.TargetPriority.WEAKEST:
				score = float(e.current_hp) + float(dist) * 0.1
			Enums.TargetPriority.STRONGEST:
				score = -float(e.current_hp) + float(dist) * 0.1
			Enums.TargetPriority.RANGED_FIRST:
				score = float(dist)
				if e.tags.has("ranged") or e.tags.has("mage"):
					score -= 100.0
			Enums.TargetPriority.SUPPORT_FIRST:
				score = float(dist)
				if e.tags.has("support"):
					score -= 100.0
			_:
				score = float(dist)

		if score < best_score:
			best_score = score
			best = e
	return best

func _direction_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if diff == Vector2i.ZERO:
		return Vector2i(0, -1)
	# Return cardinal direction
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	else:
		return Vector2i(0, signi(diff.y))

func _normalize_dir(dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i(0, -1)
	# Clamp to cardinal or diagonal
	return Vector2i(clampi(dir.x, -1, 1), clampi(dir.y, -1, 1))

func _rotate_toward(f: BattleFormation, target_pos: Vector2i) -> void:
	var diff := target_pos - f.anchor_pos
	if diff == Vector2i.ZERO:
		return
	f.facing = Vector2i(clampi(diff.x, -1, 1), clampi(diff.y, -1, 1))

func _count_friendly_flank_support(f: BattleFormation) -> int:
	var count := 0
	var perp := Vector2i(-f.facing.y, f.facing.x)
	# Check tiles to the left and right of the formation
	var side_dirs: Array[Vector2i] = [perp, -perp]
	for tile in f.occupied_tiles:
		for side_dir in side_dirs:
			var adj: Vector2i = tile + side_dir
			var other: BattleFormation = grid.get(adj)
			if other != null and other != f and other.side == f.side and not other.is_dead:
				count += 1
				break  # Count each direction once
	return mini(count, 2)

func _enemy_has_exposed_flank(f: BattleFormation) -> bool:
	var enemies := _get_side_formations(1 - f.side)
	for e in enemies:
		if e.is_dead or e.is_fled:
			continue
		# Check if enemy's flanks are unprotected
		var perp := Vector2i(-e.facing.y, e.facing.x)
		var left_protected := false
		var right_protected := false
		for tile in e.occupied_tiles:
			var left_adj: BattleFormation = grid.get(tile + perp)
			if left_adj != null and left_adj.side == e.side:
				left_protected = true
			var right_adj: BattleFormation = grid.get(tile - perp)
			if right_adj != null and right_adj.side == e.side:
				right_protected = true
		if not left_protected or not right_protected:
			return true
	return false

func _remove_formation(f: BattleFormation) -> void:
	for tile in f.occupied_tiles:
		if grid.get(tile) == f:
			grid.erase(tile)
	f.occupied_tiles.clear()

func _is_in_contact(f: BattleFormation) -> bool:
	return _is_in_melee_contact(f)
