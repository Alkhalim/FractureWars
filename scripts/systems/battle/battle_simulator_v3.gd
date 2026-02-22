class_name BattleSimulatorV3
extends RefCounted

signal tick_completed(actions: Array[Dictionary])
signal battle_ended(winner_side: int)

const FIELD_WIDTH := 1600.0
const FIELD_HEIGHT := 1200.0
const ENTITY_RADIUS := 4.0
const ENTITY_SPACING := 12.0
const ROW_DEPTH := 10.0
const LOOSE_SPACING := 18.0
const ENGAGE_RADIUS := 20.0
const SPATIAL_CELL_SIZE := 40.0
const CHARGE_DAMAGE_MULT := 1.5
const SPRINT_SPEED_MULT := 1.4       # Speed boost during infantry sprint
const HEAVY_IMPACT_MULT := 1.3       # Impact damage bonus for heavy infantry
const MEDIUM_IMPACT_MULT := 1.15     # Impact damage bonus for medium infantry
const RANGED_PX_PER_RANGE := 48.0
const DEATH_PROXIMITY := 120.0
const ROUT_SPEED_MULT := 1.5
const BASE_MOVE_SPEED := 0.3  # Pixels per tick per speed point (scaled for 10 ticks/sec)
const TICK_SCALE := 0.2       # Damage/morale scale factor for high tick rate
const FORCE_ADVANCE_TICK := 600  # After this tick, attacker forced to advance

# Endurance system
const ENDURANCE_MAX := 100.0
const ENDURANCE_DRAIN_SPRINT := 2.0     # Per tick while sprinting
const ENDURANCE_DRAIN_ADVANCE := 0.3    # Per tick while advancing
const ENDURANCE_DRAIN_MELEE := 1.0      # Per tick in melee combat
const ENDURANCE_DRAIN_CHARGE := 1.5     # Per tick while charging
const ENDURANCE_DRAIN_SHOOT := 0.5      # Per volley fired
const ENDURANCE_REGEN_IDLE := 0.6       # Per tick when idle (no combat/sprint/shooting)

# Mana system
const MANA_MAX := 100.0
const MANA_COST_SPELL := 18.0           # Per spell cast
const MANA_REGEN := 0.4                 # Per tick (permanent)

# Ammo system
const AMMO_PER_ENTITY := 5             # Volleys per archer

# Deploy zones
const DEPLOY_BOTTOM_Y := 900.0  # Attacker zone: y 900-1200
const DEPLOY_TOP_Y := 300.0     # Defender zone: y 0-300

static func get_entity_radius(f: BattleFormationV3) -> float:
	if f.tags.has("monster") or f.tags.has("beast"):
		if f.total_entities == 1:
			return 24.0    # Large single monsters (dragons, ceratops)
		return 15.0        # Multi-entity monsters
	if f.tags.has("construct"):
		if f.total_entities == 1:
			return 27.0    # Marching Bastion etc
		return 15.0
	if f.tags.has("cavalry"):
		if f.tags.has("beast"):
			return 4.5     # Beast cavalry (raptors) — 10% smaller
		return 5.0         # Mounted units
	return 2.5             # Infantry / ranged / mage

var attacker_formations: Array[BattleFormationV3] = []
var defender_formations: Array[BattleFormationV3] = []
var tick_count: int = 0
var max_ticks: int = 5000  # Safety cap for skip-to-end only
var is_finished: bool = false
var winner_side: int = -1
var captives: Dictionary = {0: 0, 1: 0}
var recent_deaths: Array[Dictionary] = []

# Terrain stored as grid cells mapped to continuous space
var terrain_grid: Dictionary = {}  # Vector2i -> Enums.BattleTerrain
var terrain_cell_size: float = 40.0
var terrain_grid_w: int = 40
var terrain_grid_h: int = 30

# Spatial hash grid for proximity queries
var _battle_hex_pos: Vector2i = Vector2i.ZERO
var spatial_grid: Dictionary = {}  # Vector2i -> Array[BattleFormationV3]

# Track which pairs made first contact this tick (for charge bonus)
var _first_contact_pairs: Dictionary = {}  # "id1:id2" -> true

# --- BattleFormationV3 Inner Class ---

class BattleFormationV3:
	var instance_id: StringName
	var unit_data_id: StringName
	var display_name: String
	var faction_id: StringName
	var side: int
	var tags: Array[String] = []

	# Stats
	var attack: int
	var defense: int
	var speed: int
	var attack_range: int

	# Entity/HP tracking
	var total_entities: int
	var entities_alive: int
	var hp_per_entity: int
	var front_entity_hp: int
	var max_hp: int
	var current_hp: int

	# Continuous position and rotation
	var position: Vector2 = Vector2.ZERO
	var rotation: float = 0.0  # Radians, 0 = facing up (-Y)
	var entity_positions: PackedVector2Array = PackedVector2Array()
	var entity_target_positions: PackedVector2Array = PackedVector2Array()
	var entity_local_offsets: PackedVector2Array = PackedVector2Array()
	var formation_shape: Enums.FormationShape = Enums.FormationShape.LINE
	var move_speed: float = 3.0  # Pixels per tick

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
	var in_melee_contact: bool = false
	var was_in_melee_contact: bool = false
	var first_contact_tick: int = -1  # Tick when first melee contact happened
	var momentum: float = 0.0        # Cavalry acceleration (0.0 to 1.0)
	var is_sprinting: bool = false    # Infantry sprint before contact
	var impact_applied: bool = false  # Whether first-contact impact was already applied

	# Dead entity tracking — positions where soldiers fell
	var dead_entity_positions: PackedVector2Array = PackedVector2Array()

	# Ranged attack cooldown
	var ranged_cooldown_max: int = 5   # Ticks between ranged attacks
	var ranged_cooldown_timer: int = 0 # Current cooldown counter
	var fire_deploy_timer: int = 0     # Ticks remaining before unit can fire after stopping
	var is_deployed: bool = false      # True when stationary and ready to fire

	# Resource bars
	var max_endurance: float = 100.0
	var current_endurance: float = 100.0
	var is_idle_this_tick: bool = true  # Track if unit did nothing combat-related this tick

	var max_mana: float = 0.0          # 0 = not a mage
	var current_mana: float = 0.0

	var max_ammo: int = 0              # 0 = not a ranged unit (or is mage)
	var current_ammo: int = 0
	var fired_this_tick: bool = false   # Track if ranged attack happened this tick

	# Beast special abilities (set by building bonuses)
	var hp_regen_per_tick: float = 0.0    # HP restored per tick
	var damage_aura_radius: float = 0.0   # Pixel radius for damage aura
	var damage_aura_damage: float = 0.0   # Damage per tick to enemies in aura
	var spawn_unit_data_id: StringName = &""  # Unit to spawn mid-battle
	var spawn_interval: int = 0           # Ticks between spawns
	var spawn_counter: int = 0            # Current spawn countdown

	# Debt penalty: faction has negative gold
	var faction_in_debt: bool = false

	func take_damage(amount: int) -> int:
		var entities_before := entities_alive
		if hp_per_entity > 0 and total_entities > 1:
			var remaining_damage := amount
			while remaining_damage > 0 and entities_alive > 0:
				if front_entity_hp <= remaining_damage:
					remaining_damage -= front_entity_hp
					# Record position of dying entity before decrementing
					var dying_idx := entities_alive - 1
					if dying_idx >= 0 and dying_idx < entity_positions.size():
						dead_entity_positions.append(entity_positions[dying_idx])
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
				# Single-entity death — record position
				if entity_positions.size() > 0:
					dead_entity_positions.append(entity_positions[0])
				elif position != Vector2.ZERO:
					dead_entity_positions.append(position)
				entities_alive = 0
		if current_hp <= 0:
			is_dead = true
			entities_alive = 0
			front_entity_hp = 0
		return entities_before - entities_alive

	func get_facing_vector() -> Vector2:
		return Vector2(sin(rotation), -cos(rotation))

# --- Setup ---

func setup_terrain(campaign_terrain: Enums.TerrainType, hex_pos: Vector2i) -> void:
	_battle_hex_pos = hex_pos
	terrain_grid_w = ceili(FIELD_WIDTH / terrain_cell_size)
	terrain_grid_h = ceili(FIELD_HEIGHT / terrain_cell_size)
	var seed_val := hex_pos.x * 1000 + hex_pos.y
	terrain_grid = BattleTerrainGen.generate(campaign_terrain, seed_val, terrain_grid_w, terrain_grid_h)

func get_terrain_at(pos: Vector2) -> Enums.BattleTerrain:
	var cell := Vector2i(int(pos.x / terrain_cell_size), int(pos.y / terrain_cell_size))
	return terrain_grid.get(cell, Enums.BattleTerrain.OPEN)

func is_passable_at(pos: Vector2) -> bool:
	return BattleTerrainGen.is_passable(get_terrain_at(pos))

func setup_attacker_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	var units := army.units
	var count := units.size()
	if count == 0:
		return
	var spacing := minf(300.0, (FIELD_WIDTH - 200.0) / float(count))
	var start_x := (FIELD_WIDTH - spacing * (count - 1)) / 2.0

	for i in count:
		var unit := units[i]
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var f := _create_formation(unit, ud, 0, cmd_bonuses)
		f.position = Vector2(start_x + i * spacing, DEPLOY_BOTTOM_Y + 100.0)
		f.rotation = 0.0  # Facing up
		_assign_formation_shape(f)
		_generate_formation_offsets(f)
		_update_entity_world_positions(f)
		attacker_formations.append(f)

func setup_defender_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	var units := army.units
	var count := units.size()
	if count == 0:
		return
	var spacing := minf(300.0, (FIELD_WIDTH - 200.0) / float(count))
	var start_x := (FIELD_WIDTH - spacing * (count - 1)) / 2.0

	for i in count:
		var unit := units[i]
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var f := _create_formation(unit, ud, 1, cmd_bonuses)
		f.position = Vector2(start_x + i * spacing, DEPLOY_TOP_Y - 100.0)
		f.rotation = PI  # Facing down
		_assign_formation_shape(f)
		_generate_formation_offsets(f)
		_update_entity_world_positions(f)
		defender_formations.append(f)

func _create_formation(unit: UnitInstance, ud: UnitData, side: int, cmd_bonuses: Dictionary) -> BattleFormationV3:
	var f := BattleFormationV3.new()
	f.instance_id = unit.instance_id
	f.unit_data_id = ud.id
	f.display_name = ud.display_name
	f.faction_id = ud.faction_id
	f.side = side
	f.tags = ud.tags.duplicate()
	var atk_bonus: int = cmd_bonuses.get("attack_bonus", 0)
	var def_bonus: int = cmd_bonuses.get("defense_bonus", 0)
	f.attack = ud.attack + atk_bonus
	f.defense = ud.defense + def_bonus

	# Faction mechanic combat bonuses
	var fs: FactionState = GameManager.state.faction_states.get(ud.faction_id)
	if fs:
		# Skulloath: high corruption = attack bonus
		if ud.faction_id == &"skulloath":
			if fs.corruption >= 81:
				f.attack += int(f.attack * 0.25)
			elif fs.corruption >= 61:
				f.attack += int(f.attack * 0.15)
		# Tainted Jade: taint power = defense bonus
		elif ud.faction_id == &"tainted_jade":
			if fs.taint_power >= 50:
				f.defense += int(f.defense * 0.15)
			elif fs.taint_power >= 20:
				f.defense += int(f.defense * 0.10)
		# Gladehost: high harmony = morale bonus (applied below in morale section)
		elif ud.faction_id == &"gladehost":
			pass
		# Shardhorde: active resonance buffs boost attack per matching realm
		elif ud.faction_id == &"shardhorde":
			for realm_key in fs.shard_resonance:
				# Void resonance: +10% attack to all. Others: +5% attack
				if realm_key == Enums.Realm.VOID:
					f.attack += int(f.attack * 0.10)
				else:
					f.attack += int(f.attack * 0.05)
	f.speed = ud.speed
	f.attack_range = ud.attack_range
	f.max_hp = unit.current_hp
	f.current_hp = unit.current_hp
	f.move_speed = f.speed * BASE_MOVE_SPEED

	if ud.hp_per_soldier > 0 and ud.squad_size > 1:
		f.hp_per_entity = ud.hp_per_soldier
		f.total_entities = ud.squad_size
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

	f.base_morale = ud.base_morale
	# Gladehost harmony: +10 base morale when harmony >= 70
	if fs and ud.faction_id == &"gladehost" and fs.harmony >= 70:
		f.base_morale += 10
	f.current_morale = float(f.base_morale)
	f.morale_aura = ud.morale_aura
	f.fear_radius = ud.fear_radius
	f.captive_chance = ud.captive_chance

	# Ranged attack cooldown: mages fire slower than archers (high burst, lower frequency)
	if ud.tags.has("mage"):
		f.ranged_cooldown_max = 12
	elif ud.tags.has("ranged"):
		f.ranged_cooldown_max = 7

	if ud.tags.has("ranged") or ud.tags.has("mage"):
		f.stance = Enums.UnitStance.DEFENSIVE
		f.fire_deploy_timer = 5  # Short initial deploy delay
		f.is_deployed = false
	elif ud.tags.has("cavalry") or ud.tags.has("fast"):
		f.stance = Enums.UnitStance.AGGRESSIVE

	# Resource bars
	f.max_endurance = ENDURANCE_MAX
	f.current_endurance = ENDURANCE_MAX
	if ud.tags.has("mage"):
		f.max_mana = MANA_MAX
		f.current_mana = MANA_MAX
	if ud.tags.has("ranged") and not ud.tags.has("mage"):
		f.max_ammo = AMMO_PER_ENTITY
		f.current_ammo = AMMO_PER_ENTITY

	# Shard guardian realm combat modifiers
	if ud.faction_id == &"shard_guardians":
		var realm_mods := ShardGuardianSystem.get_realm_mods_for_shard_at(_battle_hex_pos)
		if not realm_mods.is_empty():
			f.attack = int(float(f.attack) * realm_mods.get("atk_mult", 1.0))
			f.defense = int(float(f.defense) * realm_mods.get("def_mult", 1.0))
			f.speed = int(float(f.speed) * realm_mods.get("spd_mult", 1.0))
			f.move_speed = f.speed * BASE_MOVE_SPEED
			# Realm specials
			if realm_mods.has("morale_bonus"):
				f.base_morale += realm_mods["morale_bonus"]
				f.current_morale = float(f.base_morale)
			if realm_mods.has("fear_radius"):
				f.fear_radius += realm_mods["fear_radius"]
			if realm_mods.has("attack_range"):
				f.attack_range += realm_mods["attack_range"]
				if f.attack_range > 1 and not f.tags.has("ranged"):
					f.tags.append("ranged")
					f.ranged_cooldown_max = 8
					f.max_ammo = AMMO_PER_ENTITY
					f.current_ammo = AMMO_PER_ENTITY
					f.fire_deploy_timer = 5
					f.is_deployed = false
			if realm_mods.has("hp_regen"):
				f.hp_regen_per_tick = realm_mods["hp_regen"]

	return f

func _assign_formation_shape(f: BattleFormationV3) -> void:
	if f.tags.has("beast") or f.tags.has("monster"):
		if f.total_entities <= 3:
			f.formation_shape = Enums.FormationShape.SINGLE
		else:
			f.formation_shape = Enums.FormationShape.BLOCK
	elif f.tags.has("cavalry") and f.tags.has("fast"):
		f.formation_shape = Enums.FormationShape.WEDGE
	elif f.tags.has("cavalry"):
		f.formation_shape = Enums.FormationShape.WEDGE
	elif f.tags.has("ranged") or f.tags.has("mage"):
		f.formation_shape = Enums.FormationShape.LOOSE_LINE
	elif f.tags.has("construct"):
		f.formation_shape = Enums.FormationShape.BLOCK
	elif f.tags.has("infantry"):
		f.formation_shape = Enums.FormationShape.LINE
	else:
		f.formation_shape = Enums.FormationShape.LINE

# --- Formation Shape Generation ---

func _generate_formation_offsets(f: BattleFormationV3) -> void:
	f.entity_local_offsets = PackedVector2Array()
	var count := f.entities_alive
	if count <= 0:
		return

	# Scale spacing for larger entities
	var radius_scale := get_entity_radius(f) / 4.0
	var scaled_spacing := ENTITY_SPACING * radius_scale
	var scaled_loose := LOOSE_SPACING * radius_scale
	var scaled_row := ROW_DEPTH * radius_scale

	match f.formation_shape:
		Enums.FormationShape.LINE:
			_generate_line_offsets(f, count, scaled_spacing, scaled_row)
		Enums.FormationShape.LOOSE_LINE:
			_generate_line_offsets(f, count, scaled_loose, scaled_row)
		Enums.FormationShape.WEDGE:
			_generate_wedge_offsets(f, count, scaled_spacing, scaled_row)
		Enums.FormationShape.BLOCK:
			_generate_block_offsets(f, count, scaled_spacing, scaled_row)
		Enums.FormationShape.SINGLE:
			_generate_single_offsets(f, count, scaled_spacing)

	# Add initial scatter for natural look (skip single entities)
	if count > 1:
		var scatter := get_entity_radius(f) * 0.4
		for i in f.entity_local_offsets.size():
			f.entity_local_offsets[i] += Vector2(randf_range(-scatter, scatter), randf_range(-scatter, scatter))

func _generate_line_offsets(f: BattleFormationV3, count: int, spacing: float, row_depth: float) -> void:
	var per_row := mini(count, 15)
	var rows := ceili(float(count) / float(per_row))
	var placed := 0
	for row in rows:
		var this_row := mini(per_row, count - placed)
		var row_width := (this_row - 1) * spacing
		var start_x := -row_width / 2.0
		for i in this_row:
			var x := start_x + i * spacing
			var y := row * row_depth
			f.entity_local_offsets.append(Vector2(x, y))
			placed += 1

func _generate_wedge_offsets(f: BattleFormationV3, count: int, spacing: float, row_depth: float) -> void:
	# Filled triangle wedge: row 0 = 1 (tip), row 1 = 2, row 2 = 3, etc.
	f.entity_local_offsets.append(Vector2.ZERO)
	var placed := 1
	var row := 1
	while placed < count:
		var depth := row * row_depth
		var entities_in_row := row + 1
		var row_width := row * spacing * 0.8
		for j in entities_in_row:
			if placed >= count:
				break
			var t := float(j) / float(maxi(entities_in_row - 1, 1))
			var x := lerpf(-row_width, row_width, t)
			f.entity_local_offsets.append(Vector2(x, depth))
			placed += 1
		row += 1

func _generate_block_offsets(f: BattleFormationV3, count: int, spacing: float, row_depth: float) -> void:
	var cols := mini(count, 4)
	var rows := ceili(float(count) / float(cols))
	var placed := 0
	for row in rows:
		var this_row := mini(cols, count - placed)
		var row_width := (this_row - 1) * spacing
		var start_x := -row_width / 2.0
		for i in this_row:
			var x := start_x + i * spacing
			var y := row * row_depth
			f.entity_local_offsets.append(Vector2(x, y))
			placed += 1

func _generate_single_offsets(f: BattleFormationV3, count: int, spacing: float) -> void:
	if count == 1:
		f.entity_local_offsets.append(Vector2.ZERO)
	else:
		for i in count:
			var angle := TAU * float(i) / float(count)
			f.entity_local_offsets.append(Vector2(cos(angle), sin(angle)) * spacing)

func _update_entity_world_positions(f: BattleFormationV3, use_lerp: bool = false) -> void:
	# Compute target positions from center + rotated offsets
	f.entity_target_positions = PackedVector2Array()
	var cos_r := cos(f.rotation)
	var sin_r := sin(f.rotation)
	var limit := mini(f.entities_alive, f.entity_local_offsets.size())
	for i in limit:
		var local := f.entity_local_offsets[i]
		var world_offset := Vector2(
			local.x * cos_r - local.y * sin_r,
			local.x * sin_r + local.y * cos_r
		)
		f.entity_target_positions.append(f.position + world_offset)

	if use_lerp and f.entity_positions.size() == limit:
		# Row-based lerp: front entities react faster, creating a ripple effect
		var max_i := float(maxi(limit - 1, 1))
		var is_cavalry := f.tags.has("cavalry")
		for i in limit:
			# Front entities (low index) have higher lerp = move first
			var row_factor := 1.0 - float(i) / max_i * 0.5
			var base_lerp: float
			if f.in_melee_contact:
				# Cavalry breaks formation fast; infantry advances steadily toward enemies
				base_lerp = 0.18 if is_cavalry else 0.14
			elif f.was_in_melee_contact:
				base_lerp = 0.12
			elif f.is_sprinting:
				# Sprinting: entities stay tight but move fast
				base_lerp = 0.20
			else:
				base_lerp = 0.25
			var entity_lerp := base_lerp * row_factor
			# No jitter during melee or sprint — clean purposeful movement
			var jitter := Vector2.ZERO
			if not f.in_melee_contact and not f.is_sprinting:
				jitter = Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))
			var target_pos := f.entity_target_positions[i] + jitter
			var new_pos := f.entity_positions[i].lerp(target_pos, entity_lerp)
			# Cap per-tick movement to move_speed so entities don't teleport
			var move_delta := new_pos - f.entity_positions[i]
			var max_step := f.move_speed * 1.5
			if move_delta.length() > max_step:
				new_pos = f.entity_positions[i] + move_delta.normalized() * max_step
			f.entity_positions[i] = new_pos

		# Anti-overlap: push apart entities that are too close to friendly entities
		if limit > 1:
			var min_dist := get_entity_radius(f) * 2.0
			var push_strength := 0.5 if f.in_melee_contact else 0.3
			for i in limit:
				for j in range(i + 1, limit):
					var diff := f.entity_positions[i] - f.entity_positions[j]
					var d := diff.length()
					if d > 0.1 and d < min_dist:
						var push := diff.normalized() * (min_dist - d) * push_strength
						f.entity_positions[i] += push
						f.entity_positions[j] -= push
	else:
		# Snap directly (initial placement or size change)
		f.entity_positions = f.entity_target_positions.duplicate()

# --- Spatial Grid ---

func _rebuild_spatial_grid() -> void:
	spatial_grid.clear()
	var all := _get_all_alive()
	for f in all:
		var cell := _pos_to_cell(f.position)
		if not spatial_grid.has(cell):
			spatial_grid[cell] = []
		spatial_grid[cell].append(f)

func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / SPATIAL_CELL_SIZE), int(pos.y / SPATIAL_CELL_SIZE))

func _get_nearby_formations(pos: Vector2) -> Array:
	var result := []
	var center_cell := _pos_to_cell(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := center_cell + Vector2i(dx, dy)
			if spatial_grid.has(cell):
				result.append_array(spatial_grid[cell])
	return result

func _resolve_cross_formation_overlap() -> void:
	var all_formations: Array[BattleFormationV3] = []
	all_formations.append_array(attacker_formations)
	all_formations.append_array(defender_formations)
	for i in all_formations.size():
		var f1 := all_formations[i]
		if f1.is_dead or f1.is_fled:
			continue
		var r1 := get_entity_radius(f1)
		for j in range(i + 1, all_formations.size()):
			var f2 := all_formations[j]
			if f2.is_dead or f2.is_fled:
				continue
			# Skip pairs both in melee contact (fighting is expected close contact)
			if f1.in_melee_contact and f2.in_melee_contact:
				if f1.side != f2.side:
					continue
			var r2 := get_entity_radius(f2)
			var min_dist := r1 + r2
			# Quick bounding check between formation centers
			if f1.position.distance_to(f2.position) > min_dist * float(maxi(f1.entities_alive, f2.entities_alive)) + 50.0:
				continue
			var lim1 := mini(f1.entities_alive, f1.entity_positions.size())
			var lim2 := mini(f2.entities_alive, f2.entity_positions.size())
			# Stronger push for same-side formations piling into melee
			var push_str := 0.7 if f1.side == f2.side else 0.5
			for a in lim1:
				for b in lim2:
					var diff := f1.entity_positions[a] - f2.entity_positions[b]
					var d := diff.length()
					if d < min_dist and d > 0.01:
						var push := diff.normalized() * (min_dist - d) * push_str
						f1.entity_positions[a] += push
						f2.entity_positions[b] -= push

# --- Tick Simulation ---

func simulate_tick() -> Array[Dictionary]:
	tick_count += 1
	var actions: Array[Dictionary] = []
	_first_contact_pairs.clear()

	var all := _get_all_alive()
	all.sort_custom(func(a: BattleFormationV3, b: BattleFormationV3) -> bool: return a.speed > b.speed)

	# Track previous melee state, then reset
	for f in all:
		# Reset impact when leaving melee so next charge/sprint gets a fresh impact
		if f.was_in_melee_contact and not f.in_melee_contact:
			f.impact_applied = false
			f.first_contact_tick = -1
		f.was_in_melee_contact = f.in_melee_contact
		f.in_melee_contact = false
		f.is_idle_this_tick = true
		f.fired_this_tick = false

	# Force attacker advance after prolonged battle
	if tick_count >= FORCE_ADVANCE_TICK:
		for f in attacker_formations:
			if not f.is_dead and not f.is_fled and not f.is_routing:
				f.current_order = Enums.BattleOrder.ADVANCE

	# Auto-advance ranged units that can no longer fire (out of ammo/mana)
	for f in all:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		if f.attack_range <= 1:
			continue
		var depleted := false
		if f.max_ammo > 0 and f.current_ammo <= 0:
			depleted = true
		if f.max_mana > 0.0 and f.current_mana < MANA_COST_SPELL * 0.3:
			depleted = true
		if depleted and f.current_order in [Enums.BattleOrder.HOLD, Enums.BattleOrder.ADVANCE]:
			f.current_order = Enums.BattleOrder.ADVANCE

	# Phase 1: Movement
	_rebuild_spatial_grid()
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		if f.is_routing:
			actions.append_array(_execute_rout_movement(f))
			continue
		if _check_melee_contact(f):
			if f.first_contact_tick < 0:
				f.first_contact_tick = tick_count
			f.in_melee_contact = true
			f.is_sprinting = false
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_MELEE)
			_apply_melee_spread(f)
			if f.tags.has("cavalry") or f.tags.has("infantry"):
				_loosen_melee_formation(f)
			# Advance formation center toward nearest enemy to close gaps
			var melee_target := _find_target(f)
			if melee_target != null:
				var close_dir := f.position.direction_to(melee_target.position)
				var close_speed := f.move_speed * 0.6
				if f.tags.has("cavalry"):
					close_speed = f.move_speed * 0.8
				if f.current_order == Enums.BattleOrder.CHARGE:
					close_speed = f.move_speed * 1.2
				f.position += close_dir * close_speed
				f.position.x = clampf(f.position.x, 20.0, FIELD_WIDTH - 20.0)
				f.position.y = clampf(f.position.y, 20.0, FIELD_HEIGHT - 20.0)
			continue
		# If was in melee but lost contact, aggressively close the gap
		if f.was_in_melee_contact:
			# Gradually reform formation when disengaging (lerp offsets toward ideal)
			if f.tags.has("cavalry") or f.tags.has("infantry"):
				_reform_formation_gradual(f)
			var target := _find_target(f)
			if target != null:
				var dir := f.position.direction_to(target.position)
				f.position += dir * f.move_speed * 1.5
				_rotate_toward_smooth(f, target.position)
				f.position.x = clampf(f.position.x, 20.0, FIELD_WIDTH - 20.0)
				f.position.y = clampf(f.position.y, 20.0, FIELD_HEIGHT - 20.0)
				actions.append({"type": "move", "id": f.instance_id, "to": f.position})
				continue
		actions.append_array(_execute_order_movement(f))

	# Update cavalry momentum
	for f in all:
		if f.is_dead or f.is_fled or not f.tags.has("cavalry"):
			continue
		if f.in_melee_contact or f.is_routing:
			f.momentum = maxf(0.0, f.momentum - 0.15)
		elif f.current_order in [Enums.BattleOrder.ADVANCE, Enums.BattleOrder.CHARGE, Enums.BattleOrder.FLANK_LEFT, Enums.BattleOrder.FLANK_RIGHT]:
			f.momentum = minf(1.0, f.momentum + 0.05)
		else:
			f.momentum = maxf(0.0, f.momentum - 0.05)

	# Update all entity world positions with smooth lerp
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		_update_entity_world_positions(f, true)

	# Cross-formation entity anti-overlap
	_resolve_cross_formation_overlap()

	# Rebuild spatial grid after movement
	_rebuild_spatial_grid()

	# Phase 2: Melee Combat
	var combat_pairs := _find_all_contact_pairs()
	for pair in combat_pairs:
		var fa: BattleFormationV3 = pair[0]
		var fb: BattleFormationV3 = pair[1]
		actions.append_array(_resolve_combat_pair(fa, fb))

	# Phase 3: Ranged Attacks
	for f in all:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		if f.attack_range <= 1:
			continue
		if f.in_melee_contact:
			continue
		actions.append_array(_execute_ranged_attack(f))

	# Phase 4: Morale updates
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		_update_morale(f)

	# Phase 5: Update entity positions (remove dead from front, survivors advance)
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		# Front soldiers die first: trim from front of arrays
		var had_casualties := f.entities_alive < f.entity_local_offsets.size()
		if had_casualties:
			var excess := f.entity_local_offsets.size() - f.entities_alive
			f.entity_local_offsets = f.entity_local_offsets.slice(excess)
		if f.entity_positions.size() > f.entities_alive:
			var excess := f.entity_positions.size() - f.entities_alive
			f.entity_positions = f.entity_positions.slice(excess)
		# Only regenerate formation offsets when entities actually died (trimmed above),
		# not every tick — prevents resetting the drift from _loosen_melee_formation
		if f.in_melee_contact and f.total_entities > 1:
			if had_casualties:
				_generate_formation_offsets(f)
		_update_entity_world_positions(f, true)

	# Phase 5b: Resource regeneration (endurance, mana)
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		# Endurance regen: only when idle (not fighting, sprinting, or shooting)
		if f.is_idle_this_tick:
			f.current_endurance = minf(f.max_endurance, f.current_endurance + ENDURANCE_REGEN_IDLE)
		# Mana regen: permanent but slow
		if f.max_mana > 0.0:
			f.current_mana = minf(f.max_mana, f.current_mana + MANA_REGEN)

	# Phase 5c: Beast special abilities (regen, damage aura, spawning)
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		# HP regeneration
		if f.hp_regen_per_tick > 0.0 and f.current_hp < f.max_hp:
			f.current_hp = mini(f.max_hp, f.current_hp + roundi(f.hp_regen_per_tick))
			f.front_entity_hp = f.current_hp if f.total_entities == 1 else f.front_entity_hp
		# Damage aura
		if f.damage_aura_radius > 0.0 and f.damage_aura_damage > 0.0:
			var enemies := defender_formations if f.side == 0 else attacker_formations
			for e in enemies:
				if e.is_dead or e.is_fled:
					continue
				if f.position.distance_to(e.position) <= f.damage_aura_radius:
					var aura_dmg := roundi(f.damage_aura_damage * TICK_SCALE)
					if aura_dmg > 0:
						e.take_damage(aura_dmg)
						actions.append({"type": "aura_damage", "source": f.instance_id, "target": e.instance_id, "damage": aura_dmg})
		# Unit spawning
		if f.spawn_interval > 0 and f.spawn_unit_data_id != &"":
			f.spawn_counter -= 1
			if f.spawn_counter <= 0:
				f.spawn_counter = f.spawn_interval
				var spawned := _spawn_unit_from_beast(f)
				if spawned:
					actions.append({"type": "spawn", "source": f.instance_id, "spawned": spawned.instance_id})

	# Phase 6: Victory check
	_check_victory()

	# Clean stale deaths
	var filtered: Array[Dictionary] = []
	for d in recent_deaths:
		if d.tick >= tick_count - 25:
			filtered.append(d)
	recent_deaths = filtered

	tick_completed.emit(actions)
	return actions

# --- Movement ---

func _execute_order_movement(f: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var target := _find_target(f)
	if target == null:
		return actions

	# Ranged/mage units stop moving when a target is in range — but only if they can still fire
	var can_fire := true
	if f.max_ammo > 0 and f.current_ammo <= 0:
		can_fire = false # Out of ammo
	if f.max_mana > 0.0 and f.current_mana < MANA_COST_SPELL * 0.3:
		can_fire = false # Out of mana
	if f.attack_range > 1 and not f.in_melee_contact and can_fire:
		var dist := f.position.distance_to(target.position)
		var range_px := f.attack_range * RANGED_PX_PER_RANGE
		if dist <= range_px:
			# Stop and deploy — face target but don't move
			_rotate_toward_smooth(f, target.position)
			if not f.is_deployed:
				f.fire_deploy_timer = maxi(0, f.fire_deploy_timer - 1)
				if f.fire_deploy_timer <= 0:
					f.is_deployed = true
			return actions
		else:
			# Moving again — reset deploy state
			f.is_deployed = false
			f.fire_deploy_timer = 8  # ~0.8 second deploy delay at 10 ticks/sec

	# Apply terrain speed modifier
	var terrain_mod := BattleTerrainGen.get_speed_modifier(get_terrain_at(f.position))
	var effective_speed := f.move_speed * maxf(0.2, terrain_mod)

	# Endurance-based speed penalty: below 50% endurance, speed drops linearly
	var endurance_ratio := f.current_endurance / f.max_endurance if f.max_endurance > 0.0 else 1.0
	if endurance_ratio < 0.5:
		effective_speed *= lerpf(0.5, 1.0, endurance_ratio * 2.0)

	# Single-entity units (dragons, constructs) slow down when damaged
	if f.total_entities == 1 and f.max_hp > 0:
		var hp_ratio := float(f.current_hp) / float(f.max_hp)
		effective_speed *= lerpf(0.3, 1.0, hp_ratio)

	# Infantry sprint: accelerate for the last stretch before contact
	var target_dist := f.position.distance_to(target.position)
	f.is_sprinting = false
	if f.tags.has("infantry") and not f.in_melee_contact and f.current_endurance > 15.0:
		# Light infantry (fast or speed >= 5): longer sprint distance
		# Heavy infantry (defense >= 8 or construct): shorter but harder hitting
		var sprint_dist := 80.0
		if f.tags.has("fast") or f.speed >= 5:
			sprint_dist = 130.0
		elif f.defense >= 8:
			sprint_dist = 55.0
		if target_dist < sprint_dist and target_dist > ENGAGE_RADIUS:
			f.is_sprinting = true
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_SPRINT)
			effective_speed *= SPRINT_SPEED_MULT

	# Cavalry momentum bonus (up to 80% faster at full momentum)
	if f.tags.has("cavalry") and f.momentum > 0.0:
		effective_speed *= 1.0 + f.momentum * 0.8

	match f.current_order:
		Enums.BattleOrder.ADVANCE:
			var dir := f.position.direction_to(target.position)
			f.position += dir * effective_speed
			_rotate_toward_smooth(f, target.position)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			if not f.is_sprinting: # Sprint drain already applied above
				f.is_idle_this_tick = false
				f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.HOLD:
			_rotate_toward_smooth(f, target.position)
			# Holding units deploy quickly for ranged fire
			if f.attack_range > 1 and not f.is_deployed:
				f.fire_deploy_timer = maxi(0, f.fire_deploy_timer - 1)
				if f.fire_deploy_timer <= 0:
					f.is_deployed = true

		Enums.BattleOrder.FLANK_LEFT:
			var fwd := f.position.direction_to(target.position)
			var left := Vector2(fwd.y, -fwd.x)
			var diag := (fwd + left).normalized()
			f.position += diag * effective_speed
			_rotate_toward_smooth(f, target.position)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.FLANK_RIGHT:
			var fwd := f.position.direction_to(target.position)
			var right := Vector2(-fwd.y, fwd.x)
			var diag := (fwd + right).normalized()
			f.position += diag * effective_speed
			_rotate_toward_smooth(f, target.position)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.CHARGE:
			var dir := f.position.direction_to(target.position)
			f.position += dir * effective_speed * 2.0
			_rotate_toward_smooth(f, target.position)
			actions.append({"type": "charge", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_CHARGE)

		Enums.BattleOrder.RETREAT:
			var retreat_y := FIELD_HEIGHT if f.side == 0 else 0.0
			var retreat_target := Vector2(f.position.x, retreat_y)
			var dir := f.position.direction_to(retreat_target)
			f.position += dir * effective_speed
			actions.append({"type": "retreat", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

	# Clamp to field bounds
	f.position.x = clampf(f.position.x, 20.0, FIELD_WIDTH - 20.0)
	f.position.y = clampf(f.position.y, 20.0, FIELD_HEIGHT - 20.0)

	return actions

func _execute_rout_movement(f: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var retreat_y := FIELD_HEIGHT if f.side == 0 else 0.0
	var retreat_target := Vector2(f.position.x, retreat_y)
	var dir := f.position.direction_to(retreat_target)
	var rout_speed := f.move_speed * ROUT_SPEED_MULT
	if f.total_entities == 1 and f.max_hp > 0:
		var hp_ratio := float(f.current_hp) / float(f.max_hp)
		rout_speed *= lerpf(0.3, 1.0, hp_ratio)
	f.position += dir * rout_speed
	_update_entity_world_positions(f)
	actions.append({"type": "rout", "id": f.instance_id, "to": f.position})

	# Check if fled off map
	if f.side == 0 and f.position.y >= FIELD_HEIGHT - 5.0:
		f.is_fled = true
	elif f.side == 1 and f.position.y <= 5.0:
		f.is_fled = true

	return actions

func _rotate_toward_smooth(f: BattleFormationV3, target_pos: Vector2) -> void:
	var diff := target_pos - f.position
	if diff.length_squared() < 1.0:
		return
	var target_rot := atan2(diff.x, -diff.y)
	# Smooth rotation (lerp toward target)
	var angle_diff := fmod(target_rot - f.rotation + 3.0 * PI, TAU) - PI
	f.rotation += angle_diff * 0.3  # Smooth factor
	f.rotation = fmod(f.rotation + TAU, TAU)

# --- Contact Detection ---

func _check_melee_contact(f: BattleFormationV3) -> bool:
	var nearby := _get_nearby_formations(f.position)
	for other in nearby:
		if other == f or other.side == f.side:
			continue
		if other.is_dead or other.is_fled:
			continue
		var quick_dist := (get_entity_radius(f) + get_entity_radius(other) + 12.0) * 3.0
		if f.position.distance_to(other.position) < quick_dist:
			var contact := _entities_in_contact(f, other)
			if contact <= 0:
				continue
			# Require meaningful contact: at least 2 entity pairs or single-entity units
			if f.total_entities <= 1 or other.total_entities <= 1:
				return true
			if contact >= 2:
				return true
	return false

func _apply_melee_spread(f: BattleFormationV3) -> void:
	# Non-engaged entities drift toward nearby enemies to envelop
	var limit := mini(f.entities_alive, f.entity_target_positions.size())
	if limit == 0 or f.entity_target_positions.size() == 0:
		return

	var enemies := _get_side_formations(1 - f.side)
	var max_drift := ENTITY_SPACING * 5.0
	if f.tags.has("cavalry"):
		max_drift = ENTITY_SPACING * 8.0

	for i in limit:
		var epos: Vector2 = f.entity_target_positions[i]
		# Check if this entity is already engaging an enemy entity
		var is_engaged := false
		for enemy in enemies:
			if enemy.is_dead or enemy.is_fled:
				continue
			var elimit := mini(enemy.entities_alive, enemy.entity_positions.size())
			var engage_dist := get_entity_radius(f) + get_entity_radius(enemy) + 12.0
			for j in elimit:
				if epos.distance_to(enemy.entity_positions[j]) < engage_dist:
					is_engaged = true
					break
			if is_engaged:
				break

		if is_engaged:
			continue

		# Find nearest enemy entity and drift toward it
		var nearest_pos := Vector2.ZERO
		var nearest_dist := 999999.0
		for enemy in enemies:
			if enemy.is_dead or enemy.is_fled:
				continue
			var elimit := mini(enemy.entities_alive, enemy.entity_positions.size())
			for j in elimit:
				var d := epos.distance_to(enemy.entity_positions[j])
				if d < nearest_dist:
					nearest_dist = d
					nearest_pos = enemy.entity_positions[j]

		if nearest_dist < 999999.0:
			var drift_dir := (nearest_pos - epos).normalized()
			# Infantry closes purposefully; cavalry sweeps around
			var drift_amount := 0.7 * f.move_speed
			if f.tags.has("cavalry"):
				drift_amount = 1.0 * f.move_speed
			var new_target := epos + drift_dir * drift_amount
			if new_target.distance_to(f.position) <= max_drift:
				f.entity_target_positions[i] = new_target

func _apply_charge_pushback(attacker: BattleFormationV3, defender: BattleFormationV3) -> void:
	if not (attacker.tags.has("cavalry") or attacker.tags.has("monster") or attacker.tags.has("construct")):
		return

	var base_push := 6.0
	if attacker.tags.has("cavalry"):
		base_push = 8.0
	elif attacker.tags.has("monster"):
		base_push = 12.0

	# Scale by momentum for cavalry
	var momentum_mult := 1.0
	if attacker.tags.has("cavalry"):
		momentum_mult = 0.3 + attacker.momentum * 1.2

	# Armor resistance: higher defense = less push (up to 70% reduction)
	var armor_resist := clampf(float(defender.defense) / 20.0, 0.0, 0.7)
	var push_strength := base_push * momentum_mult * (1.0 - armor_resist)

	var engage_dist := get_entity_radius(attacker) + get_entity_radius(defender) + 12.0
	var dlimit := mini(defender.entities_alive, defender.entity_target_positions.size())
	var alimit := mini(attacker.entities_alive, attacker.entity_positions.size())

	for i in dlimit:
		var dpos: Vector2 = defender.entity_target_positions[i]
		for j in alimit:
			if dpos.distance_to(attacker.entity_positions[j]) < engage_dist:
				# Push direction from attacker entity toward defender entity (individual)
				var push_dir := (dpos - attacker.entity_positions[j]).normalized()
				defender.entity_target_positions[i] += push_dir * push_strength
				break

func _loosen_melee_formation(f: BattleFormationV3) -> void:
	# Entities in melee spread out toward nearby enemies (wrapping around them)
	# while maintaining some cohesion with the formation center
	if f.entities_alive <= 1:
		return
	var limit := mini(f.entities_alive, f.entity_local_offsets.size())
	var enemies := _get_side_formations(1 - f.side)
	var engage_dist := get_entity_radius(f) * 2.0 + 15.0
	# Infantry loosens to reach enemies; cavalry breaks wider to surround
	var max_spread := ENTITY_SPACING * get_entity_radius(f) * 2.5
	var drift_amount := 0.6 * f.move_speed
	if f.tags.has("cavalry"):
		max_spread = ENTITY_SPACING * get_entity_radius(f) * 3.0
		drift_amount = 1.2 * f.move_speed
	var cos_r := cos(-f.rotation)
	var sin_r := sin(-f.rotation)

	for i in limit:
		# Convert current world position to find nearest enemy
		var world_pos: Vector2 = f.entity_positions[i] if i < f.entity_positions.size() else f.position
		var nearest_enemy := Vector2.ZERO
		var nearest_dist := 999999.0
		for enemy in enemies:
			if enemy.is_dead or enemy.is_fled:
				continue
			var elimit := mini(enemy.entities_alive, enemy.entity_positions.size())
			for j in elimit:
				var d := world_pos.distance_to(enemy.entity_positions[j])
				if d < nearest_dist:
					nearest_dist = d
					nearest_enemy = enemy.entity_positions[j]

		if nearest_dist > engage_dist * 5.0:
			continue

		# Calculate desired drift in world space toward the nearest enemy
		var drift_dir := (nearest_enemy - world_pos).normalized()

		# Convert drift to local space
		var local_drift := Vector2(
			drift_dir.x * cos_r - drift_dir.y * sin_r,
			drift_dir.x * sin_r + drift_dir.y * cos_r
		) * drift_amount

		var new_offset := f.entity_local_offsets[i] + local_drift
		# Limit distance from formation center to prevent entities drifting too far
		if new_offset.length() <= max_spread:
			f.entity_local_offsets[i] = new_offset

func _reform_formation_gradual(f: BattleFormationV3) -> void:
	# Gradually lerp offsets back toward ideal formation shape instead of snapping
	var ideal_offsets := PackedVector2Array()
	# Generate ideal offsets into a temp array
	var old_offsets := f.entity_local_offsets.duplicate()
	_generate_formation_offsets(f)
	ideal_offsets = f.entity_local_offsets.duplicate()
	# Restore current offsets and lerp toward ideal
	f.entity_local_offsets = old_offsets
	var limit := mini(f.entities_alive, mini(old_offsets.size(), ideal_offsets.size()))
	var reform_speed := 0.08 if f.tags.has("cavalry") else 0.05
	for i in limit:
		f.entity_local_offsets[i] = f.entity_local_offsets[i].lerp(ideal_offsets[i], reform_speed)

func _entities_in_contact(f1: BattleFormationV3, f2: BattleFormationV3) -> int:
	var count := 0
	var engage_dist := get_entity_radius(f1) + get_entity_radius(f2) + 12.0
	var limit1 := mini(f1.entities_alive, f1.entity_positions.size())
	var limit2 := mini(f2.entities_alive, f2.entity_positions.size())
	for i in limit1:
		for j in limit2:
			if f1.entity_positions[i].distance_to(f2.entity_positions[j]) < engage_dist:
				count += 1
	return mini(count, mini(f1.entities_alive, f2.entities_alive))

func _find_all_contact_pairs() -> Array[Array]:
	var pairs: Array[Array] = []
	var checked: Dictionary = {}

	for f in attacker_formations:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		var nearby := _get_nearby_formations(f.position)
		for other in nearby:
			if other == f or other.side == f.side:
				continue
			if other.is_dead or other.is_fled or other.is_routing:
				continue
			var key := str(f.instance_id) + ":" + str(other.instance_id)
			var key_rev := str(other.instance_id) + ":" + str(f.instance_id)
			if checked.has(key) or checked.has(key_rev):
				continue
			# Quick distance check before expensive entity check
			var quick_dist := (get_entity_radius(f) + get_entity_radius(other) + 12.0) * 5.0
			if f.position.distance_to(other.position) > quick_dist:
				continue
			var contact := _entities_in_contact(f, other)
			if contact > 0:
				checked[key] = true
				if f.first_contact_tick < 0:
					f.first_contact_tick = tick_count
				if other.first_contact_tick < 0:
					other.first_contact_tick = tick_count
				f.in_melee_contact = true
				other.in_melee_contact = true
				pairs.append([f, other, contact])
	return pairs

# --- Melee Combat ---

func _resolve_combat_pair(a: BattleFormationV3, b: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# A attacks B
	var result_ab := _resolve_melee_combat(a, b)
	var ab_dmg: int = result_ab.damage
	if ab_dmg > 0:
		a.damage_dealt += ab_dmg
		var killed := b.take_damage(ab_dmg)
		b.current_morale -= result_ab.morale_damage
		if b.total_entities > 1 and killed > 0:
			b.current_morale -= killed * 3.0 * TICK_SCALE
		actions.append({
			"type": "melee_hit", "attacker": a.instance_id, "defender": b.instance_id,
			"damage": ab_dmg, "killed": killed,
			"contact": result_ab.contact, "flank": result_ab.flank, "rear": result_ab.rear
		})
		if killed > 0:
			var caps := _generate_captives(a, b, killed)
			if caps > 0:
				actions.append({"type": "captive", "side": a.side, "count": caps})
		if b.is_dead:
			recent_deaths.append({"side": b.side, "position": b.position, "tick": tick_count})

	# B attacks A
	if not b.is_dead and not b.is_fled:
		var result_ba := _resolve_melee_combat(b, a)
		var ba_dmg: int = result_ba.damage
		if ba_dmg > 0:
			b.damage_dealt += ba_dmg
			var killed := a.take_damage(ba_dmg)
			a.current_morale -= result_ba.morale_damage
			if a.total_entities > 1 and killed > 0:
				a.current_morale -= killed * 3.0 * TICK_SCALE
			actions.append({
				"type": "melee_hit", "attacker": b.instance_id, "defender": a.instance_id,
				"damage": ba_dmg, "killed": killed,
				"contact": result_ba.contact, "flank": result_ba.flank, "rear": result_ba.rear
			})
			if killed > 0:
				var caps := _generate_captives(b, a, killed)
				if caps > 0:
					actions.append({"type": "captive", "side": b.side, "count": caps})
			if a.is_dead:
				recent_deaths.append({"side": a.side, "position": a.position, "tick": tick_count})

	# Charge/momentum push-back on contact
	if not a.is_dead and not b.is_dead:
		if a.current_order == Enums.BattleOrder.CHARGE or (a.tags.has("cavalry") and a.momentum > 0.5):
			_apply_charge_pushback(a, b)
		if b.current_order == Enums.BattleOrder.CHARGE or (b.tags.has("cavalry") and b.momentum > 0.5):
			_apply_charge_pushback(b, a)

	# Reset charge after contact
	if a.current_order == Enums.BattleOrder.CHARGE and not a.is_dead:
		a.current_order = Enums.BattleOrder.ADVANCE
	if b.current_order == Enums.BattleOrder.CHARGE and not b.is_dead:
		b.current_order = Enums.BattleOrder.ADVANCE

	return actions

func _resolve_melee_combat(attacker: BattleFormationV3, defender: BattleFormationV3) -> Dictionary:
	var front_contact := 0.0
	var flank_contact := 0.0
	var rear_contact := 0.0

	var engage_dist := get_entity_radius(attacker) + get_entity_radius(defender) + 12.0
	var def_facing := defender.get_facing_vector()
	var limit_a := mini(attacker.entities_alive, attacker.entity_positions.size())
	var limit_d := mini(defender.entities_alive, defender.entity_positions.size())

	for i in limit_a:
		for j in limit_d:
			var dist := attacker.entity_positions[i].distance_to(defender.entity_positions[j])
			if dist < engage_dist:
				# Proximity-weighted: full contribution at point-blank, minimum 0.35 at edge
				var proximity := maxf(0.35, 1.0 - dist / engage_dist)
				# Direction from defender entity toward attacker entity
				var dir := (attacker.entity_positions[i] - defender.entity_positions[j]).normalized()
				var dot := dir.dot(def_facing)
				if dot > 0.5:
					front_contact += proximity
				elif dot < -0.5:
					rear_contact += proximity
				else:
					flank_contact += proximity

	var total_contact := front_contact + flank_contact + rear_contact
	if total_contact < 0.01:
		return {"damage": 0, "morale_damage": 0.0, "contact": 0.0, "flank": 0.0, "rear": 0.0}

	# Cap contact: limited by how many attacker entities are in range (not defender count)
	# This allows many small units to swarm a single large target
	var contact_cap := float(attacker.entities_alive)
	# Large single entities (elderbeasts, dragons) cleave — their massive size hits many at once
	if attacker.total_entities == 1:
		contact_cap = maxf(1.0, get_entity_radius(attacker) / 2.5)
	total_contact = minf(total_contact, contact_cap)

	# Percentage-based defense: armor reduces damage proportionally, never to zero
	# Formula: attack^2 / (attack + defense * 0.5)
	# Examples: atk 8 vs def 30 → 2.78 dps; atk 40 vs def 8 → 36.4 dps
	var atk_f := float(attacker.attack)
	var def_f := float(defender.defense) * 0.5
	var per_tile_dps := maxf(0.5, atk_f * atk_f / (atk_f + def_f))

	# Endurance-based damage reduction: below 50% endurance, damage drops
	var atk_endurance_ratio := attacker.current_endurance / attacker.max_endurance if attacker.max_endurance > 0.0 else 1.0
	if atk_endurance_ratio < 0.5:
		per_tile_dps *= lerpf(0.5, 1.0, atk_endurance_ratio * 2.0)

	# Ranged/mage units fight weakly in melee
	if attacker.tags.has("mage"):
		per_tile_dps *= 0.3
	elif attacker.tags.has("ranged"):
		per_tile_dps *= 0.4

	# Multi-soldier units lose combat effectiveness as soldiers fall
	if attacker.total_entities > 1:
		var strength_ratio := float(attacker.entities_alive) / float(attacker.total_entities)
		per_tile_dps *= lerpf(0.5, 1.0, strength_ratio)

	# Single-entity units (dragons etc) attack slower when damaged
	if attacker.total_entities == 1:
		var hp_ratio := float(attacker.current_hp) / float(attacker.max_hp)
		per_tile_dps *= lerpf(0.4, 1.0, hp_ratio)
		# Large single entities cleave many targets — reduce per-hit DPS to compensate
		per_tile_dps *= 0.7

	# Terrain defense bonus (percentage reduction on top)
	var terrain_def := BattleTerrainGen.get_defense_bonus(get_terrain_at(defender.position))
	if terrain_def > 0:
		per_tile_dps *= maxf(0.5, 1.0 - terrain_def * 0.05)

	# Infantry vs infantry: reduce damage to make clashes longer and less explosive
	if attacker.tags.has("infantry") and defender.tags.has("infantry"):
		per_tile_dps *= 0.55

	var total_damage := maxi(1, int(per_tile_dps * total_contact * randf_range(0.85, 1.15) * TICK_SCALE))

	# Stance modifiers
	if attacker.stance == Enums.UnitStance.AGGRESSIVE:
		total_damage = int(total_damage * 1.2)
	if defender.stance == Enums.UnitStance.DEFENSIVE:
		total_damage = int(total_damage * 0.8)

	# Charge bonus on first contact (cavalry order)
	if attacker.current_order == Enums.BattleOrder.CHARGE:
		total_damage = int(total_damage * CHARGE_DAMAGE_MULT)

	# Impact bonus — first few ticks of each melee engagement (resets on disengage)
	if not attacker.impact_applied and attacker.first_contact_tick >= 0:
		var ticks_in := tick_count - attacker.first_contact_tick
		if ticks_in <= 3:
			var impact_mult := 1.0
			if attacker.tags.has("monster") or attacker.tags.has("beast"):
				impact_mult = HEAVY_IMPACT_MULT  # Heavy creatures hit hard
			elif attacker.tags.has("cavalry"):
				impact_mult = HEAVY_IMPACT_MULT if attacker.momentum > 0.5 else MEDIUM_IMPACT_MULT
			elif attacker.tags.has("construct"):
				impact_mult = HEAVY_IMPACT_MULT
			elif attacker.tags.has("infantry"):
				# Infantry impact is lighter — prolonged grinding, not explosive bursts
				if attacker.defense >= 8:
					impact_mult = MEDIUM_IMPACT_MULT
				else:
					impact_mult = 1.0
			if impact_mult > 1.0:
				total_damage = int(total_damage * impact_mult)
		else:
			attacker.impact_applied = true

	# Debt penalty: 15% less damage when faction is in debt
	if attacker.faction_in_debt:
		total_damage = int(total_damage * 0.85)

	# Morale damage from flanks/rear (scaled for tick rate)
	var morale_dmg := (flank_contact * 1.5 + rear_contact * 3.0) * TICK_SCALE

	return {
		"damage": maxi(0, total_damage),
		"morale_damage": morale_dmg,
		"contact": total_contact,
		"flank": flank_contact,
		"rear": rear_contact
	}

# --- Ranged Combat ---

func _execute_ranged_attack(f: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# Must be deployed (stationary) before firing
	if not f.is_deployed:
		return actions

	# Ammo check for archers (non-mage ranged)
	if f.max_ammo > 0 and f.current_ammo <= 0:
		return actions

	# Mana check for mages
	if f.max_mana > 0.0 and f.current_mana < MANA_COST_SPELL * 0.3:
		return actions # Too low to cast

	# Cooldown check: skip if not ready to fire
	if f.ranged_cooldown_timer > 0:
		f.ranged_cooldown_timer -= 1
		return actions

	var target := _find_target(f)
	if target == null:
		return actions

	var dist := f.position.distance_to(target.position)
	var range_px := f.attack_range * RANGED_PX_PER_RANGE
	if dist > range_px:
		return actions

	# Consume ammo or mana
	if f.max_ammo > 0:
		f.current_ammo -= 1
	if f.max_mana > 0.0:
		f.current_mana = maxf(0.0, f.current_mana - MANA_COST_SPELL)

	# Reset cooldown after firing — mana affects mage cooldown
	var cooldown := f.ranged_cooldown_max
	if f.max_mana > 0.0:
		var mana_ratio := f.current_mana / f.max_mana
		if mana_ratio < 0.5:
			# At 50% mana: 1.3x cooldown, at 0%: 2.5x cooldown
			cooldown = int(float(cooldown) * lerpf(2.5, 1.3, mana_ratio * 2.0))
	f.ranged_cooldown_timer = cooldown

	# Mark as not idle (shooting uses endurance)
	f.is_idle_this_tick = false
	f.fired_this_tick = true
	f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_SHOOT)

	# Per-entity firing with miss chance
	# Mages are less accurate than archers; Empire units are generally inaccurate
	var miss_chance := 0.20
	if f.tags.has("mage"):
		miss_chance = 0.30
	if f.faction_id == &"empire":
		miss_chance += 0.20

	# Percentage-based ranged defense: attack * 0.6 scaled by armor
	var ranged_atk := float(f.attack) * 0.6
	var ranged_def := float(target.defense) * 0.3
	var dmg_per_entity := maxf(0.5, ranged_atk * ranged_atk / (ranged_atk + ranged_def))
	# Endurance-based ranged damage reduction
	var ranged_end_ratio := f.current_endurance / f.max_endurance if f.max_endurance > 0.0 else 1.0
	if ranged_end_ratio < 0.5:
		dmg_per_entity *= lerpf(0.6, 1.0, ranged_end_ratio * 2.0)
	var total_damage := 0
	var hit_count := 0
	var miss_count := 0
	var entity_limit := mini(f.entities_alive, f.entity_positions.size())
	var target_limit := mini(target.entities_alive, target.entity_positions.size())

	# Build visual projectile data (sample up to 20 for performance)
	var visual_projs: Array[Dictionary] = []
	var sample_step := maxi(1, ceili(float(entity_limit) / 20.0))
	var is_mage := f.tags.has("mage")

	for i in entity_limit:
		var is_hit := randf() >= miss_chance
		if is_hit:
			hit_count += 1
			var dmg := maxi(1, int(dmg_per_entity * randf_range(0.8, 1.2)))
			total_damage += dmg
		else:
			miss_count += 1

		# Sample projectiles for visual display
		if i % sample_step == 0 and target_limit > 0:
			var from_pos: Vector2 = f.entity_positions[i]
			var target_idx := randi() % target_limit
			var to_pos: Vector2 = target.entity_positions[target_idx]
			if not is_hit:
				to_pos += Vector2(randf_range(-50, 50), randf_range(-50, 50))
			var proj_data: Dictionary = {"from": from_pos, "to": to_pos, "hit": is_hit}
			if is_mage:
				proj_data["is_mage"] = true
				proj_data["faction_id"] = f.faction_id
				proj_data["speed_var"] = randf_range(0.8, 1.3)
			visual_projs.append(proj_data)

	# Debt penalty: 15% less damage when faction is in debt
	if f.faction_in_debt:
		total_damage = int(total_damage * 0.85)

	if total_damage > 0:
		f.damage_dealt += total_damage
		var killed := target.take_damage(total_damage)
		target.current_morale -= 1.5 * (float(hit_count) / maxf(1.0, float(entity_limit)))

		actions.append({
			"type": "ranged_hit", "attacker": f.instance_id, "defender": target.instance_id,
			"damage": total_damage, "killed": killed,
			"projectiles": visual_projs
		})

		if killed > 0:
			var caps := _generate_captives(f, target, killed)
			if caps > 0:
				actions.append({"type": "captive", "side": f.side, "count": caps})

		if target.is_dead:
			recent_deaths.append({"side": target.side, "position": target.position, "tick": tick_count})
	elif visual_projs.size() > 0:
		# All missed but still show the projectiles
		actions.append({
			"type": "ranged_hit", "attacker": f.instance_id, "defender": target.instance_id,
			"damage": 0, "killed": 0,
			"projectiles": visual_projs
		})

	return actions

# --- Morale System ---

func _update_morale(f: BattleFormationV3) -> void:
	var delta := 0.0

	# Passive recovery (scaled for tick rate)
	delta += 1.0 * TICK_SCALE
	if not f.in_melee_contact:
		delta += 1.0 * TICK_SCALE

	# Friendly flank support (formations within 60px on flanks)
	delta += _count_friendly_support(f) * 1.5 * TICK_SCALE

	# Friendly morale auras
	for ally in _get_side_formations(f.side):
		if ally == f or ally.is_dead:
			continue
		if ally.morale_aura > 0 and ally.fear_radius > 0:
			var aura_range := float(ally.fear_radius) * RANGED_PX_PER_RANGE * 0.5
			if f.position.distance_to(ally.position) <= aura_range:
				delta += ally.morale_aura * 0.5 * TICK_SCALE

	# Enemy fear auras
	for enemy in _get_side_formations(1 - f.side):
		if enemy.is_dead:
			continue
		if enemy.morale_aura < 0 and enemy.fear_radius > 0:
			var aura_range := float(enemy.fear_radius) * RANGED_PX_PER_RANGE * 0.5
			if f.position.distance_to(enemy.position) <= aura_range:
				delta += enemy.morale_aura * 0.5 * TICK_SCALE

	# Nearby ally deaths
	for death in recent_deaths:
		var death_side: int = death.get("side", -1)
		var death_tick: int = death.get("tick", 0)
		var death_pos: Vector2 = death.get("position", Vector2.ZERO)
		if death_side == f.side and death_tick >= tick_count - 15:
			if f.position.distance_to(death_pos) <= DEATH_PROXIMITY:
				delta -= 4.0 * TICK_SCALE

	f.current_morale = clampf(f.current_morale + delta, -30.0, f.base_morale * 1.5)

	# Routing check
	if f.current_morale <= 0.0 and not f.is_routing and f.rally_cooldown <= 0:
		f.is_routing = true

	# Rally check
	if f.is_routing and f.current_morale > float(f.base_morale) * 0.2:
		f.is_routing = false
		f.rally_cooldown = 25

	if f.rally_cooldown > 0:
		f.rally_cooldown -= 1

func _count_friendly_support(f: BattleFormationV3) -> int:
	var count := 0
	var perp := Vector2(-f.get_facing_vector().y, f.get_facing_vector().x)
	for ally in _get_side_formations(f.side):
		if ally == f or ally.is_dead or ally.is_fled:
			continue
		var diff := ally.position - f.position
		if diff.length() > 80.0:
			continue
		# Check if ally is roughly on our flanks
		var lateral := absf(diff.dot(perp))
		var forward := absf(diff.dot(f.get_facing_vector()))
		if lateral > forward:
			count += 1
	return mini(count, 2)

# --- Captive Generation ---

func _generate_captives(killer: BattleFormationV3, victim: BattleFormationV3, entities_killed: int) -> int:
	var chance := victim.captive_chance
	if killer.tags.has("ranged") or killer.tags.has("mage"):
		chance *= 0.1
	elif killer.tags.has("monster"):
		chance *= 0.05

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
			f.current_order = Enums.BattleOrder.CHARGE
		elif f.tags.has("ranged") or f.tags.has("mage"):
			# Advance until in range, then auto-stop and deploy (handled in movement code)
			f.current_order = Enums.BattleOrder.ADVANCE
		elif f.tags.has("monster"):
			f.current_order = Enums.BattleOrder.ADVANCE
		else:
			f.current_order = Enums.BattleOrder.ADVANCE

# --- Beast Spawning ---

func _spawn_unit_from_beast(beast_f: BattleFormationV3) -> BattleFormationV3:
	var ud: UnitData = DataManager.get_unit(beast_f.spawn_unit_data_id)
	if ud == null:
		return null
	var f := BattleFormationV3.new()
	f.instance_id = StringName("spawn_%d_%d" % [tick_count, beast_f.side])
	f.unit_data_id = ud.id
	f.display_name = ud.display_name + " (spawned)"
	f.faction_id = beast_f.faction_id
	f.side = beast_f.side
	f.tags = ud.tags.duplicate()
	f.attack = ud.attack
	f.defense = ud.defense
	f.speed = ud.speed
	f.attack_range = ud.attack_range
	f.max_hp = ud.max_hp
	f.current_hp = ud.max_hp
	f.move_speed = f.speed * BASE_MOVE_SPEED
	if ud.hp_per_soldier > 0 and ud.squad_size > 1:
		f.hp_per_entity = ud.hp_per_soldier
		f.total_entities = ud.squad_size
		f.entities_alive = ud.squad_size
		f.front_entity_hp = ud.hp_per_soldier
	else:
		f.hp_per_entity = ud.max_hp
		f.total_entities = 1
		f.entities_alive = 1
		f.front_entity_hp = ud.max_hp
	f.base_morale = ud.base_morale
	f.current_morale = float(f.base_morale)
	f.morale_aura = ud.morale_aura
	f.fear_radius = ud.fear_radius
	f.captive_chance = ud.captive_chance
	f.max_endurance = ENDURANCE_MAX
	f.current_endurance = ENDURANCE_MAX
	if ud.tags.has("ranged") and not ud.tags.has("mage"):
		f.max_ammo = AMMO_PER_ENTITY
		f.current_ammo = AMMO_PER_ENTITY
	# Spawn behind the beast
	var offset_y := -60.0 if beast_f.side == 0 else 60.0
	f.position = beast_f.position + Vector2(randf_range(-40, 40), offset_y)
	f.position.x = clampf(f.position.x, 40.0, FIELD_WIDTH - 40.0)
	f.position.y = clampf(f.position.y, 40.0, FIELD_HEIGHT - 40.0)
	f.rotation = beast_f.rotation
	_assign_formation_shape(f)
	_generate_formation_offsets(f)
	_update_entity_world_positions(f)
	var formations := attacker_formations if beast_f.side == 0 else defender_formations
	formations.append(f)
	return f

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
		winner_side = -1
		battle_ended.emit(-1)
	elif not atk_alive:
		is_finished = true
		winner_side = 1
		battle_ended.emit(1)
	elif not def_alive:
		is_finished = true
		winner_side = 0
		battle_ended.emit(0)

# --- Surviving Units Query ---

func get_surviving_formations(side: int) -> Array[BattleFormationV3]:
	var result: Array[BattleFormationV3] = []
	var formations := attacker_formations if side == 0 else defender_formations
	for f in formations:
		if not f.is_dead:
			result.append(f)
	return result

# --- Helper Functions ---

func _get_all_alive() -> Array[BattleFormationV3]:
	var result: Array[BattleFormationV3] = []
	for f in attacker_formations:
		if not f.is_dead and not f.is_fled:
			result.append(f)
	for f in defender_formations:
		if not f.is_dead and not f.is_fled:
			result.append(f)
	return result

func _get_side_formations(side: int) -> Array[BattleFormationV3]:
	return attacker_formations if side == 0 else defender_formations

func _find_target(f: BattleFormationV3) -> BattleFormationV3:
	var enemies := _get_side_formations(1 - f.side)
	var best: BattleFormationV3 = null
	var best_score := 999999.0

	for e in enemies:
		if e.is_dead or e.is_fled:
			continue
		var dist := f.position.distance_to(e.position)
		var score: float

		match f.target_priority:
			Enums.TargetPriority.CLOSEST:
				score = dist
			Enums.TargetPriority.WEAKEST:
				score = float(e.current_hp) + dist * 0.01
			Enums.TargetPriority.STRONGEST:
				score = -float(e.current_hp) + dist * 0.01
			Enums.TargetPriority.RANGED_FIRST:
				score = dist
				if e.tags.has("ranged") or e.tags.has("mage"):
					score -= 10000.0
			Enums.TargetPriority.SUPPORT_FIRST:
				score = dist
				if e.tags.has("support"):
					score -= 10000.0
			_:
				score = dist

		if score < best_score:
			best_score = score
			best = e
	return best
