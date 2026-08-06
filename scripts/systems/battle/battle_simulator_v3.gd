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
const TICK_SCALE := 0.17      # Damage/morale scale factor for high tick rate (15% slower than 0.2)
const FORCE_ADVANCE_TICK := 600  # After this tick, attacker forced to advance
const BATTLE_TIMER_TICKS := 1500  # ~2.5 minutes at 10 ticks/sec — all units forced to advance

# Endurance system
const ENDURANCE_MAX := 100.0
const ENDURANCE_DRAIN_SPRINT := 2.0     # Per tick while sprinting
const ENDURANCE_DRAIN_ADVANCE := 0.3    # Per tick while advancing
const ENDURANCE_DRAIN_MELEE := 1.0      # Per tick in melee combat
const ENDURANCE_DRAIN_CHARGE := 1.5     # Per tick while charging
const ENDURANCE_DRAIN_SHOOT := 0.5      # Per volley fired
const ENDURANCE_REGEN_IDLE := 0.6       # Per tick when idle (no combat/sprint/shooting)
const ENDURANCE_REGEN_MARCHING := 0.3   # Per tick when advancing but not in melee/sprinting

# Mana system
const MANA_MAX := 100.0
const MANA_COST_SPELL := 18.0           # Per spell cast
const MANA_REGEN := 0.4                 # Per tick (permanent)

# Ammo system
const AMMO_PER_ENTITY := 5             # Volleys per archer (nerfed 7->5: archers were
									   # best-value in 10/11 factions with near-zero losses)

# Deploy zones
const DEPLOY_BOTTOM_Y := 900.0  # Attacker zone: y 900-1200
const DEPLOY_TOP_Y := 300.0     # Defender zone: y 0-300

# Disciplined factions that fire synchronized volleys (others fire staggered skirmish shots)
const VOLLEY_FACTIONS: Array[StringName] = [
	&"empire", &"moonspear", &"sunblessed", &"cinderguard", &"ivoryscar",
	&"aurentis_guard", &"crimson_legion", &"luminarch", &"valkarn_garrison",
	&"skalvar_watch", &"venerated", &"obsidian_order",
]

static func get_entity_radius(f: BattleFormationV3) -> float:
	if f.tags.has("swarm") and not f.tags.has("infantry"):
		return 1.0         # Critter swarms (bats, rats, insects) — tiny individuals
	if f.tags.has("monster") or f.tags.has("beast"):
		if f.total_entities == 1:
			return 24.0    # Large single monsters (dragons, ceratops)
		if f.tags.has("flying") and f.total_entities <= 40:
			return 3.5     # Small flying beast flock (deathshriek bats)
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
var _side_cmd_bonuses: Dictionary = {0: {}, 1: {}} # Per-side commander bonuses for behavioral effects

# Terrain stored as grid cells mapped to continuous space
var terrain_grid: Dictionary = {}  # Vector2i -> Enums.BattleTerrain
var terrain_cell_size: float = 20.0
var terrain_grid_w: int = 80
var terrain_grid_h: int = 60

# Spatial hash grid for proximity queries
var _battle_hex_pos: Vector2i = Vector2i.ZERO
var _campaign_terrain: Enums.TerrainType = Enums.TerrainType.PLAINS
var _battle_realm: int = -1  # Enums.Realm of the battle tile's region (-1 = unknown)
var _is_city_battle: bool = false
var _battle_city_id: StringName = &""  # city on the battle hex (for city-shield mechanics)
var _defense_meta: Dictionary = {} # tower_positions, siege_positions from defensive buildings
var spatial_grid: Dictionary = {}  # Vector2i -> Array[BattleFormationV3]

# Track which pairs made first contact this tick (for charge bonus)
var _first_contact_pairs: Dictionary = {}  # int pair key -> true

# Cached sorted formation list (invalidated when routing changes)
var _sorted_formations_dirty := true
var _sorted_formations_cache: Array[BattleFormationV3] = []

# Per-tick target cache (instance_id -> target formation)
var _target_cache: Dictionary = {}

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
	var melee_defense: int
	var projectile_defense: int
	var magic_defense: int
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
	var rout_panic_ticks: int = 0  # Ticks of panic where rally is impossible

	# Orders
	var current_order: Enums.BattleOrder = Enums.BattleOrder.ADVANCE
	var target_priority: Enums.TargetPriority = Enums.TargetPriority.CLOSEST
	var stance: Enums.UnitStance = Enums.UnitStance.AGGRESSIVE

	# Command queue
	var command_queue: Array[Dictionary] = []  # [{command: QueueCommand, duration: int}]
	var queue_index: int = 0
	var queue_tick_start: int = 0
	var queue_locked: bool = false
	var focus_tag_filter: String = ""          # "", "mage", "cavalry", etc.
	var fall_back_origin: Vector2 = Vector2.ZERO
	var fall_back_retreating: bool = false

	# Aura
	var morale_aura: int = 0
	var fear_radius: int = 0
	var healing_aura: float = 0.0
	var armor_aura: int = 0
	var armor_aura_bonus: int = 0  # Received from nearby armor aura allies
	var captive_chance: float = 0.3
	var vs_attack_bonuses: Dictionary = {}   # tag -> int bonus (e.g. {"cavalry": 3})
	var vs_defense_bonuses: Dictionary = {}  # tag -> int bonus (e.g. {"ranged": 2})
	var fear_vs_tags: Array[String] = []     # Extra fear effect against specific tags
	var fear_vs_bonus: int = 0               # Additional morale_aura when targeting matching units
	var ethereal_dodge_chance: float = 0.0   # Moonspear: chance to phase through attacks

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
	var fires_volleys: bool = true     # true = synchronized volley, false = staggered skirmish
	var entity_fire_offsets: PackedInt32Array = PackedInt32Array()  # Per-entity cooldown offset (skirmish mode)

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
	var regen_requires_combat: bool = false  # If true, only regen while actively fighting
	var damage_aura_radius: float = 0.0   # Pixel radius for damage aura
	var damage_aura_damage: float = 0.0   # Damage per tick to enemies in aura
	var cached_radius: float = 2.5         # Cached result of get_entity_radius()
	var spawn_unit_data_id: StringName = &""  # Unit to spawn mid-battle
	var spawn_interval: int = 0           # Ticks between spawns
	var spawn_counter: int = 0            # Current spawn countdown

	# Chariot trample
	var chariot_trample_cooldown: int = 0  # Ticks until next trample tick

	# Mage spell type
	var spell_type: StringName = &""  # fireball, lightning, frost_bolt, death_curse, heal_bolt, sunfire, hex_curse, shard_pulse, sand_blast

	# Debuffs applied by spells (each: {type: StringName, value: float, ticks: int})
	var debuffs: Array[Dictionary] = []

	# Research-driven combat bonuses
	var flanking_damage_bonus: float = 0.0   # Extra multiplier on flanking damage
	var charge_damage_bonus: float = 0.0     # Extra multiplier on charge damage
	var fire_damage_bonus: float = 0.0       # Multiplier on fire/magic damage
	var poison_damage_pct: float = 0.0       # Poison DoT as % of damage dealt
	var stun_chance_pct: float = 0.0         # % chance to stun target per hit
	var siege_bonus: int = 0                 # Flat bonus to siege damage
	var ranged_attack_bonus: int = 0         # Flat bonus to ranged attack stat
	var adjacent_unit_damage_pct: float = 0.0 # Bonus damage when friendly unit adjacent

	# Debt penalty: faction has negative gold
	var faction_in_debt: bool = false

	func take_damage(amount: int) -> int:
		# Ethereal dodge: chance to phase through attacks entirely
		if ethereal_dodge_chance > 0.0 and randf() < ethereal_dodge_chance:
			return 0  # Attack phased through
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
	_campaign_terrain = campaign_terrain
	_battle_realm = -1
	if GameManager.state and GameManager.state.hex_map:
		var btile = GameManager.state.hex_map.get_tile(hex_pos)
		if btile:
			_battle_realm = btile.realm_influence
	var hex_city: CityState = GameManager.city_system.get_city_at_hex(hex_pos)
	_is_city_battle = hex_city != null
	_battle_city_id = hex_city.city_id if hex_city else &""
	terrain_grid_w = ceili(FIELD_WIDTH / terrain_cell_size)
	terrain_grid_h = ceili(FIELD_HEIGHT / terrain_cell_size)
	var seed_val := hex_pos.x * 1000 + hex_pos.y
	terrain_grid = BattleTerrainGen.generate(campaign_terrain, seed_val, terrain_grid_w, terrain_grid_h)
	# Apply defensive building terrain if city battle
	if _is_city_battle:
		var city: CityState = GameManager.city_system.get_city_at_hex(hex_pos)
		if city:
			var total_defense := 0
			for bid in city.buildings:
				var bdata: BuildingData = DataManager.get_building(bid)
				if bdata:
					total_defense += bdata.defense_bonus
			if total_defense > 0:
				_defense_meta = BattleTerrainGen.apply_defensive_buildings(
					terrain_grid, total_defense, terrain_grid_w, terrain_grid_h, seed_val)

func get_terrain_at(pos: Vector2) -> Enums.BattleTerrain:
	var cell := Vector2i(int(pos.x / terrain_cell_size), int(pos.y / terrain_cell_size))
	return terrain_grid.get(cell, Enums.BattleTerrain.OPEN)

func is_passable_at(pos: Vector2) -> bool:
	return BattleTerrainGen.is_passable(get_terrain_at(pos))

func setup_attacker_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	setup_formations(army, 0, cmd_bonuses)

func setup_defender_formations(army: ArmyState, cmd_bonuses: Dictionary = {}) -> void:
	setup_formations(army, 1, cmd_bonuses)

func setup_formations(army: ArmyState, side: int, cmd_bonuses: Dictionary = {}) -> void:
	_side_cmd_bonuses[side] = cmd_bonuses.duplicate()
	var units := army.units
	var count := units.size()
	if count == 0:
		return
	var spacing := minf(300.0, (FIELD_WIDTH - 200.0) / float(count))
	var start_x := (FIELD_WIDTH - spacing * (count - 1)) / 2.0

	var deploy_y := DEPLOY_BOTTOM_Y + 100.0 if side == 0 else DEPLOY_TOP_Y - 100.0
	var deploy_rot := 0.0 if side == 0 else PI

	for i in count:
		var unit := units[i]
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		var f := _create_formation(unit, ud, side, cmd_bonuses)
		f.position = Vector2(start_x + i * spacing, deploy_y)
		f.rotation = deploy_rot
		_assign_formation_shape(f)
		_generate_formation_offsets(f)
		_update_entity_world_positions(f)
		if side == 0:
			attacker_formations.append(f)
		else:
			defender_formations.append(f)

# rescale (Task R2): global-reference pct-conversion helpers for hardcoded
# flat combat-bonus constants that apply broadly across many different units
# (sub-faction identity modifiers, terrain home-turf bonuses baked into the
# faction-mechanic blocks below, Empire/Cinderguard vs_attack_bonuses, Thunder
# Wall, Relic Defense, Ivoryscar pyramid) -- there's no single "this unit's
# own attack" to personalize against for a code constant applied to many
# units, so these use the empirical roster reference (mean attack ~68,
# median 60 -> 70; mean defense ~35, median 25 -> 30; see task-R2-report.md).
# The call sites below intentionally keep the ORIGINAL pre-rescale literal
# (e.g. `_atk_pct(f, 3)` for what used to be `f.attack += 3`) so the diff
# stays traceable to the R1 inventory instead of hiding the old magnitude
# behind a pre-computed percentage.
const RESCALE_REF_ATTACK := 70.0
const RESCALE_REF_DEFENSE := 30.0

func _atk_pct(f: BattleFormationV3, old_flat: float) -> int:
	return roundi(f.attack * old_flat / RESCALE_REF_ATTACK)

func _def_pct(f: BattleFormationV3, old_flat: float) -> int:
	return roundi(f.defense * old_flat / RESCALE_REF_DEFENSE)

func _create_formation(unit: UnitInstance, ud: UnitData, side: int, cmd_bonuses: Dictionary) -> BattleFormationV3:
	var f := BattleFormationV3.new()
	f.instance_id = unit.instance_id
	f.unit_data_id = ud.id
	f.display_name = ud.display_name
	f.faction_id = ud.faction_id
	f.side = side
	f.tags = ud.tags.duplicate()
	f.spell_type = ud.spell_type if ud.spell_type != &"" else &"bolt"
	var atk_bonus: int = cmd_bonuses.get("attack_bonus", 0)
	var def_bonus: int = cmd_bonuses.get("defense_bonus", 0)
	var spd_bonus: int = cmd_bonuses.get("speed_bonus", 0)

	# Tag-specific commander bonuses (e.g. cavalry_attack_bonus only applies to cavalry)
	for tag in ud.tags:
		atk_bonus += cmd_bonuses.get(tag + "_attack_bonus", 0)
		def_bonus += cmd_bonuses.get(tag + "_defense_bonus", 0)
		spd_bonus += cmd_bonuses.get(tag + "_speed_bonus", 0)
	# "vs_X" bonuses applied to opposing units happen during combat (not here)

	# Terrain-specific commander bonuses
	var terrain_key: String = Enums.TerrainType.keys()[_campaign_terrain].to_lower()
	atk_bonus += cmd_bonuses.get("terrain_" + terrain_key + "_attack_bonus", 0)
	def_bonus += cmd_bonuses.get("terrain_" + terrain_key + "_defense_bonus", 0)
	spd_bonus += cmd_bonuses.get("terrain_" + terrain_key + "_speed_bonus", 0)
	# City battle bonuses
	if _is_city_battle:
		atk_bonus += cmd_bonuses.get("terrain_city_attack_bonus", 0)
		def_bonus += cmd_bonuses.get("terrain_city_defense_bonus", 0)
	# Ambush bonus: defenders with this trait get extra attack
	if side == 1:
		atk_bonus += cmd_bonuses.get("ambush_attack_bonus", 0)

	# Research combat bonuses
	var r_eff := GameManager.research_system.get_research_effects(ud.faction_id)
	# Research bonuses are PERCENTAGES of each unit's own base (readable and
	# fair across a 15-150 attack range; flat +N was invisible on big units)
	# rescale (Task R2): atk_bonus/def_bonus now arrive pre-converted to
	# percent-points from every skill/item/trait/follower/building source
	# (see tools_rescale_data.gd) -- percent-points still sum linearly across
	# stacked sources, so this remains the single resolution point.
	f.attack = ud.attack + roundi(float(ud.attack) * float(atk_bonus) / 100.0)
	f.attack += roundi(f.attack * float(r_eff.get("unit_attack_pct", 0)) / 100.0)
	f.defense = ud.melee_defense + roundi(float(ud.melee_defense) * float(def_bonus) / 100.0)
	f.defense += roundi(f.defense * float(r_eff.get("unit_defense_pct", 0)) / 100.0)
	# Additional research effect keys
	# rescale (Task R2): unit_ranged_bonus/siege_bonus were flat, same-scale
	# adds (values 2-30) -- now stored as global-reference percent (see
	# task-R2-report.md) and resolved here against this unit's own already-
	# computed f.attack, so the downstream combat-time read sites (lines
	# ~2200-2620) that treat these as flat need no further changes.
	f.ranged_attack_bonus = roundi(f.attack * float(r_eff.get("unit_ranged_bonus", 0)) / 100.0)
	f.flanking_damage_bonus = r_eff.get("flanking_damage_bonus", 0) / 100.0
	f.charge_damage_bonus = r_eff.get("charge_damage_pct", 0) / 100.0
	f.fire_damage_bonus = r_eff.get("fire_damage_pct", 0) / 100.0
	f.poison_damage_pct = r_eff.get("poison_damage_pct", 0) / 100.0
	f.stun_chance_pct = r_eff.get("stun_chance_pct", 0) / 100.0
	f.siege_bonus = roundi(f.attack * float(r_eff.get("siege_bonus", 0)) / 100.0)
	f.adjacent_unit_damage_pct = r_eff.get("adjacent_unit_damage_pct", 0) / 100.0

	# Per-unit terrain & realm home-turf bonuses from UnitData (data-driven):
	# fraction applied to both attack and defense on matching ground
	var home_bonus: float = ud.terrain_bonuses.get(int(_campaign_terrain), 0.0)
	if _battle_realm >= 0:
		home_bonus += ud.realm_bonuses.get(_battle_realm, 0.0)
	if home_bonus != 0.0:
		f.attack += roundi(f.attack * home_bonus)
		f.defense += roundi(f.defense * home_bonus)

	# Building special_effects: flying_unit_attack_bonus
	# rescale (Task R2): was a flat same-scale add (values 1-3), now stored
	# as global-reference percent (tools_rescale_data.gd) and resolved here
	# against this unit's own already-computed f.attack.
	if f.tags.has("flying"):
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			if city.faction_id == ud.faction_id:
				for bid in city.buildings:
					var bld: BuildingData = DataManager.get_building(bid)
					if bld and bld.special_effects.has("flying_unit_attack_bonus"):
						f.attack += roundi(f.attack * float(bld.special_effects["flying_unit_attack_bonus"]) / 100.0)

	# Faction mechanic combat bonuses — resolve parent faction for sub-factions
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(ud.faction_id, ud.faction_id)
	var fs: FactionState = GameManager.state.faction_states.get(ud.faction_id)
	# Sub-factions use parent's faction state for mechanic bonuses if they don't have their own
	if fs == null and parent_fid != ud.faction_id:
		fs = GameManager.state.faction_states.get(parent_fid)
	if fs:
		# ── Empire: Imperial Authority + Edicts ──
		if parent_fid == &"empire":
			# Authority affects morale
			if fs.imperial_authority >= 75:
				f.base_morale += 10
			elif fs.imperial_authority < 25:
				f.base_morale -= 10
			# Military Edict: +12% attack
			if fs.imperial_edict == 1 and fs.imperial_edict_turns > 0:
				f.attack += roundi(f.attack * 0.12)

		# ── Skulloath: Corruption — stronger scaling ──
		elif parent_fid == &"skulloath":
			if fs.corruption >= 81:
				f.attack += roundi(f.attack * 0.30)
				f.base_morale -= 5 # Demonic units are feared but unstable
			elif fs.corruption >= 61:
				f.attack += roundi(f.attack * 0.18)
			elif fs.corruption <= 20:
				# Traditional Pure: less attack but more defense and morale
				f.attack -= roundi(f.attack * 0.08)
			# Research: corruption_attack_scaling (+X% attack per 10 corruption)
			var sk_scaling: int = r_eff.get("corruption_attack_scaling", 0)
			if sk_scaling > 0 and fs.corruption > 0:
				f.attack += roundi(f.attack * float(sk_scaling) * float(fs.corruption) / 1000.0)
				f.defense += roundi(f.defense * 0.10)
				f.base_morale += 10

		# ── Tainted Jade: Taint Power + Focus ──
		elif parent_fid == &"tainted_jade":
			# Base taint defense (always active, scales more)
			if fs.taint_power >= 60:
				f.defense += roundi(f.defense * 0.20)
			elif fs.taint_power >= 40:
				f.defense += roundi(f.defense * 0.15)
			elif fs.taint_power >= 20:
				f.defense += roundi(f.defense * 0.10)
			# Jungle regen: stronger home terrain advantage
			# rescale (Task R2): flat +3/+2 def -> global-reference percent (see
			# _def_pct doc comment); original pre-rescale magnitude kept inline.
			if _campaign_terrain == Enums.TerrainType.JUNGLE:
				# scale-note (Task R2 review): flat HP/tick regen floor, same
				# 10x-scale pattern as the melee/ranged DPS floors elsewhere
				# in this file -- f.current_hp/f.max_hp are both DIVIDE-
				# rescaled (/10), so an unscaled flat regen rate is now ~10x
				# relatively STRONGER (bigger fraction of the smaller pool
				# healed per tick) than pre-rescale. Scaled 0.5 -> 0.05.
				f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, 0.05)
				f.defense += _def_pct(f, 3)
			elif _campaign_terrain == Enums.TerrainType.SWAMP:
				# scale-note (Task R2 review): same as the jungle regen floor
				# above, 0.3 -> 0.03.
				f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, 0.03)
				f.defense += _def_pct(f, 2)
			# Taint Focus: Venomous War = attack bonus in jungle/swamp
			if fs.taint_focus == 2 and fs.taint_power >= 20:
				if _campaign_terrain == Enums.TerrainType.JUNGLE or _campaign_terrain == Enums.TerrainType.SWAMP:
					f.attack += roundi(f.attack * 0.15)
				# Anti-magic: enemy mages deal less damage (applied as defense vs magic)
				if fs.taint_power >= 40:
					f.vs_defense_bonuses["mage"] = f.vs_defense_bonuses.get("mage", 0) + _def_pct(f, 5)
			# Research: taint_attack_scaling (+X% attack per 10 taint)
			var tj_scaling: int = r_eff.get("taint_attack_scaling", 0)
			if tj_scaling > 0 and fs.taint_power > 0:
				f.attack += roundi(f.attack * float(tj_scaling) * float(fs.taint_power) / 1000.0)

		# ── Gladehost: Harmony + Season ──
		elif parent_fid == &"gladehost":
			if fs.harmony >= 70:
				f.base_morale += 12
				f.defense += roundi(f.defense * 0.05)
			elif fs.harmony >= 50:
				f.base_morale += 6
			elif fs.harmony <= 30:
				f.base_morale -= 8
			# Forest terrain: Gladehost always gets home advantage
			# rescale (Task R2): flat +3 def/+2 atk -> global-reference percent.
			if _campaign_terrain == Enums.TerrainType.FOREST:
				f.defense += _def_pct(f, 3)
				f.attack += _atk_pct(f, 2)
			# Summer season: attack bonus
			var season := TurnManager.get_current_season() if TurnManager else -1
			if season == 1: # Summer
				f.attack += roundi(f.attack * 0.08)
			elif season == 3: # Winter: defense bonus (hardened)
				f.defense += roundi(f.defense * 0.10)
			# Research: harmony_income_scaling handled in turn_manager (not combat)

		# ── Shardhorde: Resonance — much stronger per-realm ──
		elif parent_fid == &"shardhorde":
			# Research: shard_resonance_bonus amplifies all realm effects
			var sh_res_amp: float = 1.0 + float(r_eff.get("shard_resonance_bonus", 0)) / 100.0
			for realm_key in fs.shard_resonance:
				match realm_key:
					Enums.Realm.VOID:
						f.attack += roundi(f.attack * 0.15 * sh_res_amp)
					Enums.Realm.ELEMENTAL:
						f.attack += roundi(f.attack * 0.10 * sh_res_amp)
					Enums.Realm.DIVINE:
						f.defense += roundi(f.defense * 0.10 * sh_res_amp)
						# scale-note (Task R2 review): flat HP/tick regen
						# floor, same pattern as the jungle/swamp regen
						# floors above -- 0.2 -> 0.02.
						f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, 0.02 * sh_res_amp)
					Enums.Realm.NATURE:
						f.base_morale += int(8 * sh_res_amp) # morale scale, out of rescale scope
					Enums.Realm.MORTAL:
						f.attack += roundi(f.attack * 0.05 * sh_res_amp)
						f.defense += roundi(f.defense * 0.05 * sh_res_amp)
			# Multi-resonance bonus: 3+ realms = massive power spike
			if fs.shard_resonance.size() >= 3:
				f.attack += roundi(f.attack * 0.10)
				f.base_morale += 10

		# ── Moonspear: Lunar Phase — much stronger effects ──
		elif parent_fid == &"moonspear":
			# Research: lunar_phase_bonus_pct amplifies all phase effects
			var lunar_amp: float = 1.0 + float(r_eff.get("lunar_phase_bonus_pct", 0)) / 100.0
			match fs.lunar_phase:
				0: # New Moon: aggression, stealth
					f.attack += roundi(f.attack * 0.15 * lunar_amp)
					f.defense -= roundi(f.defense * 0.05)
				1: # Waxing: speed bonus
					f.speed += 1
					f.move_speed = f.speed * BASE_MOVE_SPEED
				2: # Full Moon: defense, morale
					f.defense += roundi(f.defense * 0.15 * lunar_amp)
					f.base_morale += int(10 * lunar_amp) # morale scale, out of rescale scope
				3: # Waning: healing during battle
					# scale-note (Task R2 review): flat HP/tick regen floor,
					# same pattern as the jungle/swamp regen floors above --
					# 0.4 -> 0.04.
					f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, 0.04 * lunar_amp)
			# Ethereal soldiers (always)
			f.ethereal_dodge_chance = 0.15
			f.base_morale += 15
			f.max_hp = roundi(float(f.max_hp) * 0.85)
			f.current_hp = mini(f.current_hp, f.max_hp)

		# ── Thunderswarm: Storm Fury — bigger bonuses ──
		elif parent_fid == &"thunderswarm":
			if fs.storm_fury >= 80:
				f.attack += roundi(f.attack * 0.22)
				f.defense -= roundi(f.defense * 0.08)
				f.base_morale += 5 # Fury-fueled courage
			elif fs.storm_fury >= 60:
				f.attack += roundi(f.attack * 0.15)
				f.defense -= roundi(f.defense * 0.03)
			elif fs.storm_fury >= 40:
				f.attack += roundi(f.attack * 0.08)
			# Mountain terrain: storm warriors get bonus
			# rescale (Task R2): flat +3 atk/+2 def -> global-reference percent.
			if _campaign_terrain == Enums.TerrainType.MOUNTAINS:
				f.attack += _atk_pct(f, 3)
				f.defense += _def_pct(f, 2)
			# Thunder Wall ability: +8 defense while defending the warded city
			# rescale (Task R2): flat +8 def -> global-reference percent.
			if side == 1 and fs.storm_wall_turns > 0 and _battle_city_id != &"" and _battle_city_id == fs.storm_wall_city:
				f.defense += _def_pct(f, 8)
			# Research: storm_fury_attack_scaling (+X% attack per 10 fury)
			var ts_scaling: int = r_eff.get("storm_fury_attack_scaling", 0)
			if ts_scaling > 0 and fs.storm_fury > 0:
				f.attack += roundi(f.attack * float(ts_scaling) * float(fs.storm_fury) / 1000.0)

		# ── Cinderguard: Forge Mode — clear attack/defense trade-off ──
		elif parent_fid == &"cinderguard":
			if fs.border_vigilance <= 30:
				# Fortress mode: significant defense
				f.defense += roundi(f.defense * 0.20)
				f.base_morale += 8
			elif fs.border_vigilance >= 75:
				# War forge: attack power
				f.attack += roundi(f.attack * 0.15)
			# Research: vigilance_defense_scaling (+X% defense per 10 vigilance)
			var cg_scaling: int = r_eff.get("vigilance_defense_scaling", 0)
			if cg_scaling > 0 and fs.border_vigilance > 0:
				f.defense += roundi(f.defense * float(cg_scaling) * float(fs.border_vigilance) / 1000.0)
			# Border fortress network bonus: +2% def per total fortress level across settlements
			var cg_total_forts := 0
			for cg_cid in fs.border_fortresses:
				cg_total_forts += int(fs.border_fortresses[cg_cid])
			if cg_total_forts > 0:
				f.defense += roundi(f.defense * float(cg_total_forts) * 0.02)
			# Dragon raid veterans: +morale per raids survived
			if fs.dragon_raids_survived >= 5:
				f.base_morale += 5
			elif fs.dragon_raids_survived >= 3:
				f.base_morale += 2

		# ── Ivoryscar: Relic Power — stronger defense scaling ──
		elif parent_fid == &"ivoryscar":
			if fs.relic_power >= 40:
				f.defense += roundi(f.defense * 0.18)
				f.base_morale += 5
			elif fs.relic_power >= 30:
				f.defense += roundi(f.defense * 0.13)
			elif fs.relic_power >= 20:
				f.defense += roundi(f.defense * 0.08)
			elif fs.relic_power >= 10:
				f.defense += roundi(f.defense * 0.05)
			# Black Pyramid milestones: combat bonuses
			if fs.pyramid_restored:
				f.attack += roundi(f.attack * 0.15)
				f.defense += roundi(f.defense * 0.15)
				f.base_morale += 8
			elif fs.pyramid_restoration >= 75:
				f.attack += roundi(f.attack * 0.08)
				f.base_morale += 3
			elif fs.pyramid_restoration >= 50:
				f.attack += roundi(f.attack * 0.04)
			# Pyramid >= 25: +2 defense to all (applied in city system too)
			# rescale (Task R2): flat +2 def -> global-reference percent.
			if fs.pyramid_restoration >= 25:
				f.defense += _def_pct(f, 2)
			# Relic Defense expedition choice: +3 defense in city battles for 3 turns
			# rescale (Task R2): flat +3 def -> global-reference percent.
			if side == 1 and _is_city_battle and int(fs.leader_bonuses.get("relic_defense_turns", 0)) > 0:
				f.defense += _def_pct(f, 3)
			# Desert/Wastes terrain: home advantage
			# rescale (Task R2): flat +2 def -> global-reference percent.
			if _campaign_terrain == Enums.TerrainType.DESERT or _campaign_terrain == Enums.TerrainType.SHARD_WASTES:
				f.defense += _def_pct(f, 2)
				f.speed += 1
				f.move_speed = f.speed * BASE_MOVE_SPEED

		# ── Sunblessed: Solar Faith — strong faith scaling ──
		elif parent_fid == &"sunblessed":
			if fs.solar_faith >= 85:
				f.attack += roundi(f.attack * 0.12)
				f.defense += roundi(f.defense * 0.08)
				f.base_morale += 12
			elif fs.solar_faith >= 70:
				f.attack += roundi(f.attack * 0.08)
				f.defense += roundi(f.defense * 0.05)
				f.base_morale += 6
			elif fs.solar_faith <= 24:
				f.attack -= roundi(f.attack * 0.10)
				f.base_morale -= 10
			elif fs.solar_faith <= 39:
				f.base_morale -= 5
			# Research: solar_faith_attack_scaling (+X% attack per 10 faith)
			var sb_scaling: int = r_eff.get("solar_faith_attack_scaling", 0)
			if sb_scaling > 0 and fs.solar_faith > 0:
				f.attack += roundi(f.attack * float(sb_scaling) * float(fs.solar_faith) / 1000.0)

		# ── Forsaken: Espionage ambush bonus ──
		elif parent_fid == &"forsaken":
			if fs.espionage_network >= 15:
				# Intelligence advantage: bonus when attacking (side == 0 = attacker)
				if side == 0:
					f.attack += roundi(f.attack * 0.08)
					f.speed += 1
					f.move_speed = f.speed * BASE_MOVE_SPEED
			if fs.espionage_network >= 30:
				f.base_morale += 5 # Confidence from knowing enemy positions

		# ── Deepiron (tier-2 Special): +% defense when fighting in own territory ──
		var deep_mod := SpecialResourceSystem.modifier_strength(ud.faction_id, &"deepiron")
		if deep_mod > 0.0:
			var own_tile = GameManager.state.hex_map.get_tile(_battle_hex_pos) if GameManager.state.hex_map else null
			if own_tile and own_tile.owner_faction == ud.faction_id:
				f.defense += roundi(f.defense * deep_mod)

		# ── Everfrost Core (Landmark): winter defense in own territory ──
		if TurnManager and TurnManager.get_current_season() == 3:
			if LandmarkSystem.has_landmark(ud.faction_id, &"everfrost_core"):
				var ef_tile = GameManager.state.hex_map.get_tile(_battle_hex_pos) if GameManager.state.hex_map else null
				if ef_tile and ef_tile.owner_faction == ud.faction_id:
					f.defense += roundi(f.defense * 0.10)

	# Empire anti-mage war mages: Empire mage units deal extra damage to enemy mages
	# rescale (Task R2): flat +5 vs_attack -> global-reference percent.
	if parent_fid == &"empire" and ud.tags.has("mage"):
		f.vs_attack_bonuses["mage"] = f.vs_attack_bonuses.get("mage", 0) + _atk_pct(f, 5)

	# Cinderguard frontier guards: former dragon hunters — bonus damage vs large units
	# rescale (Task R2): flat +3/+3 vs_attack, +2 def -> global-reference percent.
	if parent_fid == &"cinderguard":
		f.vs_attack_bonuses["monster"] = f.vs_attack_bonuses.get("monster", 0) + _atk_pct(f, 3)
		f.vs_attack_bonuses["beast"] = f.vs_attack_bonuses.get("beast", 0) + _atk_pct(f, 3)
		if _campaign_terrain == Enums.TerrainType.SHARD_WASTES or _campaign_terrain == Enums.TerrainType.DESERT:
			f.defense += _def_pct(f, 2)

	# ── Sub-faction unique modifiers ──────────────────────────
	# rescale (Task R2): every flat atk/def/vs_attack/vs_defense constant in
	# this block was 1-5 same-scale points -> global-reference percent (see
	# _atk_pct/_def_pct doc comment above _create_formation); the numeric
	# literal passed to the helper is the ORIGINAL pre-rescale magnitude.
	# f.speed/f.base_morale stay untouched (unrelated scale, out of rescale
	# scope).
	match ud.faction_id:
		# Empire sub-factions
		&"crimson_legion":  # Elite infantry, no mages — raw melee power
			if ud.tags.has("infantry") or ud.tags.has("heavy"):
				f.attack += _atk_pct(f, 3)
				f.base_morale += 5
		&"aurentis_guard":  # Defensive specialists, construction focus
			f.defense += _def_pct(f, 2)
		# Skulloath sub-factions
		&"salt_reavers":  # Pirate raiders — fast and aggressive
			f.speed += 1
			f.move_speed = f.speed * BASE_MOVE_SPEED
			if _campaign_terrain == Enums.TerrainType.WETLANDS or _campaign_terrain == Enums.TerrainType.SWAMP:
				f.attack += _atk_pct(f, 3)
		&"ashbound":  # Demon summoners and mages
			if ud.tags.has("mage"):
				f.attack += _atk_pct(f, 3)
			else:
				f.defense -= _def_pct(f, 1)
		# Gladehost sub-factions
		&"thornwardens":  # Aggressive plant warriors
			f.attack += _atk_pct(f, 2)
			if _campaign_terrain == Enums.TerrainType.FOREST or _campaign_terrain == Enums.TerrainType.JUNGLE:
				f.attack += _atk_pct(f, 2)
		&"miststriders":  # Fog stealth + trade — faster, elusive
			f.speed += 1
			f.move_speed = f.speed * BASE_MOVE_SPEED
			f.ethereal_dodge_chance = maxf(f.ethereal_dodge_chance, 0.08)
		# Moonspear sub-factions
		&"obsidian_order":  # Heavy infantry + siege — tanky but slow
			f.defense += _def_pct(f, 3)
			f.speed = maxi(f.speed - 1, 1)
			f.move_speed = f.speed * BASE_MOVE_SPEED
		&"luminarch":  # Prophecy/magic focus — mage specialists
			if ud.tags.has("mage"):
				f.attack += _atk_pct(f, 3)
			f.base_morale += 5
		# Thunderswarm sub-factions
		&"stormbound":  # Ranged + speed + Valkyries
			if ud.tags.has("ranged") or ud.tags.has("mage"):
				f.attack += _atk_pct(f, 2)
			f.speed += 1
			f.move_speed = f.speed * BASE_MOVE_SPEED
		&"skalvar_watch":  # Protectors — defensive stalwarts
			f.defense += _def_pct(f, 2)
			f.base_morale += 5
		# Tainted Jade sub-factions
		&"twilight_veil":  # Shadow assassins — glass cannon melee
			if ud.tags.has("infantry") or ud.tags.has("light"):
				f.attack += _atk_pct(f, 4)
			f.defense -= _def_pct(f, 2)
		&"jade_conclave":  # Seal magic — anti-mage specialists
			f.vs_defense_bonuses["mage"] = f.vs_defense_bonuses.get("mage", 0) + _def_pct(f, 4)
			f.defense += _def_pct(f, 1)
		# Ivoryscar sub-factions
		&"gorgonic_cult":  # Monster tamers — beast bonus
			f.vs_attack_bonuses["monster"] = f.vs_attack_bonuses.get("monster", 0) + _atk_pct(f, 2)
			f.vs_attack_bonuses["beast"] = f.vs_attack_bonuses.get("beast", 0) + _atk_pct(f, 2)
			if ud.tags.has("monster") or ud.tags.has("beast"):
				f.attack += _atk_pct(f, 2)
		&"servants_of_reliquary":  # Relic guardians — defensive
			f.defense += _def_pct(f, 2)
			if _is_city_battle:
				f.defense += _def_pct(f, 2)
		# Cinderguard sub-factions
		&"crownfire":  # Fire specialists (dragon heritage)
			f.attack += _atk_pct(f, 2)
			if ud.tags.has("mage"):
				f.attack += _atk_pct(f, 2)
		&"valkarn_garrison":  # Heavy garrison defense
			f.defense += _def_pct(f, 3)
			if _is_city_battle:
				f.defense += _def_pct(f, 2)
				f.base_morale += 5
		# Forsaken sub-factions
		&"bloodthrone":  # Vampire nobles — strong but arrogant
			f.attack += _atk_pct(f, 2)
			f.base_morale += 5
		&"blightcoven":  # Witchcraft sorcery — glass cannon mages
			if ud.tags.has("mage"):
				f.attack += _atk_pct(f, 4)
			f.defense -= _def_pct(f, 1)
		# Shardhorde sub-factions
		&"icebound":  # Ice and frost — tundra specialists
			if _campaign_terrain == Enums.TerrainType.TUNDRA:
				f.defense += _def_pct(f, 3)
				f.attack += _atk_pct(f, 2)
			elif _campaign_terrain == Enums.TerrainType.DESERT:
				f.speed = maxi(f.speed - 1, 1)
				f.move_speed = f.speed * BASE_MOVE_SPEED
		&"splinterbrood":  # Crystal swarm — regen and numbers
			# scale-note (Task R2 review): flat HP/tick regen floor, same
			# pattern as the jungle/swamp regen floors above -- 0.2 -> 0.02.
			f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, 0.02)
			f.attack += _atk_pct(f, 1)
		# Sunblessed sub-factions
		&"oaseans":  # Desert educators — knowledge seekers
			if _campaign_terrain == Enums.TerrainType.DESERT:
				f.defense += _def_pct(f, 2)
				f.base_morale += 5
		&"venerated":  # Dogmatic holy order — zealous
			f.base_morale += 8
			f.attack += _atk_pct(f, 1)

	# Veterancy bonuses
	var vet_bonus := unit.get_veterancy_bonus()
	if vet_bonus > 0.0:
		f.attack += roundi(float(f.attack) * vet_bonus)
		f.defense += roundi(float(f.defense) * vet_bonus)

	# Propagate accumulated defense modifiers to all three defense types
	var net_def_delta: int = f.defense - ud.melee_defense
	f.melee_defense = maxi(0, ud.melee_defense + net_def_delta)
	f.projectile_defense = maxi(0, ud.projectile_defense + net_def_delta)
	f.magic_defense = maxi(0, ud.magic_defense + net_def_delta)

	f.speed = ud.speed + spd_bonus + r_eff.get("unit_speed_bonus", 0)
	if vet_bonus > 0.0:
		f.speed += roundi(float(f.speed) * vet_bonus)
	f.attack_range = ud.attack_range
	# HP bonus as % of the squad pool (flat +15 on a 6000 HP squad was nothing)
	var hp_extra: int = roundi(unit.current_hp * float(r_eff.get("unit_hp_pct", 0)) / 100.0)
	f.max_hp = unit.current_hp + hp_extra
	f.current_hp = unit.current_hp + hp_extra
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

	f.base_morale = ud.base_morale + r_eff.get("unit_morale_bonus", 0) + cmd_bonuses.get("unit_morale_bonus", 0)
	# Gladehost harmony: +10 base morale when harmony >= 70
	if fs and parent_fid == &"gladehost" and fs.harmony >= 70:
		f.base_morale += 10
	f.current_morale = float(f.base_morale)
	# Research: HP regen as % of max HP per battle round
	var regen_pct: float = r_eff.get("unit_regen_pct", 0) / 100.0
	if regen_pct > 0.0:
		f.hp_regen_per_tick = maxf(f.hp_regen_per_tick, float(f.max_hp) * regen_pct / 60.0)  # Spread over ~60 ticks per round
	f.morale_aura = ud.morale_aura
	f.fear_radius = ud.fear_radius
	f.fear_vs_tags = ud.fear_vs_tags.duplicate()
	f.fear_vs_bonus = ud.fear_vs_bonus
	f.healing_aura = ud.healing_aura
	# rescale (Task R2): armor_aura was a flat defense-scale int (1-3); data
	# now stores a percent-of-this-unit's-own-defense (computed at sweep time
	# from the SAME unit's old melee_defense, see task-R2-report.md category
	# A), resolved back to a flat NEW-scale delta against f.defense here.
	f.armor_aura = roundi(f.defense * float(ud.armor_aura) / 100.0)
	f.captive_chance = ud.captive_chance

	# Load base vs_bonuses from unit data
	# rescale (Task R2): vs_attack_bonuses/vs_defense_bonuses were flat
	# same-scale ints (2-5); data now stores a percent-of-this-unit's-own-
	# attack/defense (personalized ratio computed at sweep time from the SAME
	# unit's old attack/melee_defense), resolved back to a flat NEW-scale
	# delta here against f.attack/f.defense (already fully computed above).
	for tag_key in ud.vs_attack_bonuses:
		f.vs_attack_bonuses[tag_key] = f.vs_attack_bonuses.get(tag_key, 0) + roundi(f.attack * float(ud.vs_attack_bonuses[tag_key]) / 100.0)
	for tag_key in ud.vs_defense_bonuses:
		f.vs_defense_bonuses[tag_key] = f.vs_defense_bonuses.get(tag_key, 0) + roundi(f.defense * float(ud.vs_defense_bonuses[tag_key]) / 100.0)

	# Tag-conditional "vs_X" bonuses from commander (e.g. vs_cavalry_attack_bonus → +atk vs cavalry)
	# rescale (Task R2): these were flat same-scale ints from skill/item/
	# trait/follower data; now stored as global-reference percent (see
	# tools_rescale_data.gd), resolved back to a flat NEW-scale delta here
	# against f.attack/f.defense (already fully computed by this point).
	for key in cmd_bonuses:
		if key.begins_with("vs_") and key.ends_with("_attack_bonus"):
			var tag: String = key.substr(3, key.length() - 17)  # strip "vs_" and "_attack_bonus"
			f.vs_attack_bonuses[tag] = f.vs_attack_bonuses.get(tag, 0) + roundi(f.attack * float(cmd_bonuses[key]) / 100.0)
		elif key.begins_with("vs_") and key.ends_with("_defense_bonus"):
			var tag: String = key.substr(3, key.length() - 18)  # strip "vs_" and "_defense_bonus"
			f.vs_defense_bonuses[tag] = f.vs_defense_bonuses.get(tag, 0) + roundi(f.defense * float(cmd_bonuses[key]) / 100.0)

	# Ranged attack cooldown: mages fire slower than archers (high burst, lower frequency)
	if ud.tags.has("mage"):
		f.ranged_cooldown_max = 14
	elif ud.tags.has("ranged"):
		# Fast ranged units (speed 6+) fire slightly faster — 10% reduction instead of 15%
		if ud.tags.has("fast") or ud.speed >= 6:
			f.ranged_cooldown_max = 7
		else:
			f.ranged_cooldown_max = 8

	if ud.tags.has("ranged") or ud.tags.has("mage"):
		f.stance = Enums.UnitStance.DEFENSIVE
		f.fire_deploy_timer = 5  # Short initial deploy delay
		f.is_deployed = false
	elif ud.tags.has("cavalry") or ud.tags.has("fast"):
		f.stance = Enums.UnitStance.AGGRESSIVE

	# Volley vs skirmish fire mode
	f.fires_volleys = ud.faction_id in VOLLEY_FACTIONS or ud.base_morale >= 60
	if ud.tags.has("mage"):
		f.fires_volleys = false  # Mages always fire independently (spellcasting isn't synchronized)
	if ud.tags.has("beast") or ud.tags.has("swarm"):
		f.fires_volleys = false  # Beasts don't coordinate
	# Initialize staggered offsets for skirmish fire
	if not f.fires_volleys and f.attack_range > 1:
		f.entity_fire_offsets.resize(f.total_entities)
		for i in f.total_entities:
			f.entity_fire_offsets[i] = i % f.ranged_cooldown_max

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
			f.attack = roundi(float(f.attack) * realm_mods.get("atk_mult", 1.0))
			var def_mult: float = realm_mods.get("def_mult", 1.0)
			f.defense = roundi(float(f.defense) * def_mult)
			f.melee_defense = roundi(float(f.melee_defense) * def_mult)
			f.projectile_defense = roundi(float(f.projectile_defense) * def_mult)
			f.magic_defense = roundi(float(f.magic_defense) * def_mult)
			f.speed = roundi(float(f.speed) * realm_mods.get("spd_mult", 1.0))
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

	f.cached_radius = get_entity_radius(f)
	return f

func _assign_formation_shape(f: BattleFormationV3) -> void:
	if f.tags.has("swarm"):
		f.formation_shape = Enums.FormationShape.SWARM
	elif f.tags.has("beast") or f.tags.has("monster"):
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
	var radius_scale := f.cached_radius / 4.0
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
		Enums.FormationShape.SWARM:
			# Swarm formations need a minimum spread so they don't cluster into a tiny blob
			var swarm_spacing := maxf(scaled_spacing, 6.0)
			_generate_swarm_offsets(f, count, swarm_spacing)

	# Add initial scatter for natural look (skip single entities)
	if count > 1:
		var scatter := f.cached_radius * (1.0 if f.formation_shape == Enums.FormationShape.SWARM else 0.4)
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

func _generate_swarm_offsets(f: BattleFormationV3, count: int, spacing: float) -> void:
	# Organic blob: concentric rings with angular jitter and radial noise
	if count <= 0:
		return
	# Ring 0: center entity
	f.entity_local_offsets.append(Vector2.ZERO)
	var placed := 1
	var ring := 1
	while placed < count:
		var entities_in_ring := mini(6 * ring, count - placed)
		for i in entities_in_ring:
			if placed >= count:
				break
			var base_angle := TAU * float(i) / float(entities_in_ring)
			var angle_jitter := randf_range(-TAU / float(entities_in_ring) * 0.45, TAU / float(entities_in_ring) * 0.45)
			var angle := base_angle + angle_jitter
			var base_radius := ring * spacing * 1.1
			var radial_jitter := randf_range(-spacing * 0.45, spacing * 0.45)
			var radius := base_radius + radial_jitter
			f.entity_local_offsets.append(Vector2(cos(angle) * radius, sin(angle) * radius))
			placed += 1
		ring += 1

func _update_entity_world_positions(f: BattleFormationV3, use_lerp: bool = false) -> void:
	# Compute target positions from center + rotated offsets. Reuses the
	# existing array via resize + indexed writes (called twice per formation
	# per tick; fresh PackedVector2Array allocations added up).
	var cos_r := cos(f.rotation)
	var sin_r := sin(f.rotation)
	var limit := mini(f.entities_alive, f.entity_local_offsets.size())
	if f.entity_target_positions.size() != limit:
		f.entity_target_positions.resize(limit)
	for i in limit:
		var local := f.entity_local_offsets[i]
		var world_offset := Vector2(
			local.x * cos_r - local.y * sin_r,
			local.x * sin_r + local.y * cos_r
		)
		f.entity_target_positions[i] = f.position + world_offset

	if use_lerp and f.entity_positions.size() == limit:
		# Row-based lerp: front entities react faster, creating a ripple effect
		var max_i := float(maxi(limit - 1, 1))
		var is_cavalry := f.tags.has("cavalry")
		var is_swarm := f.formation_shape == Enums.FormationShape.SWARM
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
			# Swarm units have more inertia — sluggish individual movement
			if is_swarm:
				base_lerp *= 0.55
			var entity_lerp := base_lerp * row_factor
			# No jitter during melee or sprint — clean purposeful movement
			var jitter := Vector2.ZERO
			if not f.in_melee_contact and not f.is_sprinting:
				var jitter_strength := 1.5 if is_swarm else 0.8
				jitter = Vector2(randf_range(-jitter_strength, jitter_strength), randf_range(-jitter_strength, jitter_strength))
			var target_pos := f.entity_target_positions[i] + jitter
			var new_pos := f.entity_positions[i].lerp(target_pos, entity_lerp)
			# Cap per-tick movement to move_speed so entities don't teleport
			var move_delta := new_pos - f.entity_positions[i]
			var max_step := f.move_speed * 1.5
			if move_delta.length() > max_step:
				new_pos = f.entity_positions[i] + move_delta.normalized() * max_step
			f.entity_positions[i] = new_pos

		# Anti-overlap: push apart entities that are too close to friendly entities
		# Cap comparisons to avoid O(n^2) explosion on large formations
		# Only run when entities are bunched up (in melee or recently reformed)
		if limit > 1 and (f.in_melee_contact or f.was_in_melee_contact):
			var min_dist := f.cached_radius * 2.0
			var min_dist_sq := min_dist * min_dist
			var push_strength := 0.5 if f.in_melee_contact else 0.3
			var overlap_cap := 40 if f.formation_shape == Enums.FormationShape.SWARM else 25
			var check_limit := mini(limit, overlap_cap)
			var positions := f.entity_positions
			for i in check_limit:
				var pi := positions[i]
				for j in range(i + 1, check_limit):
					var diff := pi - positions[j]
					var d_sq := diff.length_squared()
					if d_sq > 0.01 and d_sq < min_dist_sq:
						var d := sqrt(d_sq)
						var push := diff * ((min_dist - d) * push_strength / d)
						f.entity_positions[i] = pi + push
						f.entity_positions[j] -= push
						pi += push
	else:
		# Snap directly (initial placement or size change)
		f.entity_positions = f.entity_target_positions.duplicate()

# --- Spatial Grid ---

func _rebuild_spatial_grid() -> void:
	spatial_grid.clear()
	var all := _sorted_formations_cache if _sorted_formations_cache.size() > 0 else _get_all_alive()
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
	# Only run every other tick to save CPU
	if tick_count % 2 != 0:
		return
	var processed_pairs: Dictionary = {} # int pair key -> true
	var all_formations: Array[BattleFormationV3] = []
	all_formations.append_array(attacker_formations)
	all_formations.append_array(defender_formations)
	for f1 in all_formations:
		if f1.is_dead or f1.is_fled:
			continue
		var r1: float = f1.cached_radius
		var nearby := _get_nearby_formations(f1.position)
		for f2: BattleFormationV3 in nearby:
			if f2 == f1 or f2.is_dead or f2.is_fled:
				continue
			# Deduplicate pairs using integer pair key
			var pk := _pair_key(f1.instance_id, f2.instance_id)
			if processed_pairs.has(pk):
				continue
			processed_pairs[pk] = true
			# Skip opposing pairs both in melee (fighting is expected close contact)
			if f1.in_melee_contact and f2.in_melee_contact:
				if f1.side != f2.side:
					continue
			var r2: float = f2.cached_radius
			var min_dist := r1 + r2
			# Quick bounding check between formation centers
			var bound := min_dist * 8.0 + 50.0
			if f1.position.distance_squared_to(f2.position) > bound * bound:
				continue
			# Cap entity iterations to avoid O(n^2) explosion
			var lim1 := mini(f1.entities_alive, mini(f1.entity_positions.size(), 16))
			var lim2: int = mini(f2.entities_alive, mini(f2.entity_positions.size(), 16))
			var push_str: float = 0.7 if f1.side == f2.side else 0.5
			var min_dist_sq := min_dist * min_dist
			var pos1 := f1.entity_positions
			var pos2 := f2.entity_positions
			for a in lim1:
				var pa := pos1[a]
				for b in lim2:
					var diff: Vector2 = pa - pos2[b]
					var d_sq: float = diff.length_squared()
					if d_sq < min_dist_sq and d_sq > 0.0001:
						var d := sqrt(d_sq)
						var push := diff * ((min_dist - d) * push_str / d)
						f1.entity_positions[a] = pa + push
						f2.entity_positions[b] -= push
						pa += push

# --- Command Queue Processing ---

const QUEUE_COMMAND_MAP := {
	Enums.QueueCommand.ADVANCE: [Enums.BattleOrder.ADVANCE, ""],
	Enums.QueueCommand.HOLD: [Enums.BattleOrder.HOLD, ""],
	Enums.QueueCommand.CHARGE: [Enums.BattleOrder.CHARGE, ""],
	Enums.QueueCommand.FLANK_LEFT: [Enums.BattleOrder.FLANK_LEFT, ""],
	Enums.QueueCommand.FLANK_RIGHT: [Enums.BattleOrder.FLANK_RIGHT, ""],
	Enums.QueueCommand.RETREAT: [Enums.BattleOrder.RETREAT, ""],
	Enums.QueueCommand.FALL_BACK: [Enums.BattleOrder.RETREAT, ""],  # Special handling below
	Enums.QueueCommand.FOCUS_MAGE: [Enums.BattleOrder.ADVANCE, "mage"],
	Enums.QueueCommand.FOCUS_RANGED: [Enums.BattleOrder.ADVANCE, "ranged"],
	Enums.QueueCommand.FOCUS_MONSTER: [Enums.BattleOrder.ADVANCE, "monster"],
	Enums.QueueCommand.FOCUS_CAVALRY: [Enums.BattleOrder.ADVANCE, "cavalry"],
	Enums.QueueCommand.FOCUS_INFANTRY: [Enums.BattleOrder.ADVANCE, "infantry"],
}

func _advance_command_queues() -> void:
	var all := _get_all_alive()
	for f in all:
		if not f.queue_locked or f.command_queue.is_empty():
			continue
		if f.queue_index >= f.command_queue.size():
			# Queue exhausted — revert to advance/closest
			f.current_order = Enums.BattleOrder.ADVANCE
			f.target_priority = Enums.TargetPriority.CLOSEST
			f.focus_tag_filter = ""
			f.fall_back_retreating = false
			continue

		var slot: Dictionary = f.command_queue[f.queue_index]
		var cmd: Enums.QueueCommand = slot.get("command", Enums.QueueCommand.ADVANCE)
		var duration: int = slot.get("duration", 100)  # 0 = until end

		# Check if current command duration expired (0 = infinite)
		if duration > 0 and tick_count - f.queue_tick_start >= duration:
			f.queue_index += 1
			f.queue_tick_start = tick_count
			f.fall_back_retreating = false
			if f.queue_index >= f.command_queue.size():
				f.current_order = Enums.BattleOrder.ADVANCE
				f.target_priority = Enums.TargetPriority.CLOSEST
				f.focus_tag_filter = ""
				continue
			slot = f.command_queue[f.queue_index]
			cmd = slot.get("command", Enums.QueueCommand.ADVANCE)
			duration = slot.get("duration", 100)

		# Map command to order + focus filter
		var mapping: Array = QUEUE_COMMAND_MAP.get(cmd, [Enums.BattleOrder.ADVANCE, ""])
		f.current_order = mapping[0]
		f.focus_tag_filter = mapping[1]

		# FALL_BACK special: retreat until 80px from origin, then hold
		if cmd == Enums.QueueCommand.FALL_BACK:
			if not f.fall_back_retreating:
				f.fall_back_origin = f.position
				f.fall_back_retreating = true
				f.current_order = Enums.BattleOrder.RETREAT
			elif f.position.distance_to(f.fall_back_origin) >= 80.0:
				f.current_order = Enums.BattleOrder.HOLD
				f.fall_back_retreating = false

# Apply research-driven enemy morale/defense penalties at battle start
func _apply_research_enemy_penalties() -> void:
	# Collect research effects for each side (use first formation's faction)
	for side in [0, 1]:
		var own_formations := attacker_formations if side == 0 else defender_formations
		var enemy_formations := defender_formations if side == 0 else attacker_formations
		if own_formations.is_empty():
			continue
		var faction_id: StringName = own_formations[0].faction_id
		var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
		var r_eff := GameManager.research_system.get_research_effects(parent_fid)
		var morale_pen: int = r_eff.get("enemy_morale_penalty", 0)
		# rescale (Task R2): enemy_defense_penalty was a flat same-scale int
		# (-2 to -5); now stored as global-reference percent (see
		# tools_rescale_data.gd) and resolved PERSONALIZED per enemy formation
		# below (against each ef's own current .defense) rather than through a
		# second global-reference lookup -- strictly more correct since this
		# already loops per-formation and enemies have varying defense stats.
		var defense_pen_pct: int = r_eff.get("enemy_defense_penalty", 0)
		if morale_pen != 0 or defense_pen_pct != 0:
			for ef in enemy_formations:
				ef.base_morale += morale_pen  # Expected to be negative
				ef.current_morale = float(ef.base_morale)
				if defense_pen_pct != 0:
					var defense_pen := roundi(ef.defense * float(defense_pen_pct) / 100.0)
					ef.defense += defense_pen
					ef.melee_defense += defense_pen
					ef.projectile_defense += defense_pen
					ef.magic_defense += defense_pen

# --- Tick Simulation ---

func simulate_tick() -> Array[Dictionary]:
	tick_count += 1
	var actions: Array[Dictionary] = []
	_first_contact_pairs.clear()
	_target_cache.clear()

	# First tick: apply research-based enemy penalties (morale/defense debuffs to opposing side)
	if tick_count == 1:
		_apply_research_enemy_penalties()

	# Advance command queues before any movement/combat
	_advance_command_queues()

	if _sorted_formations_dirty:
		_sorted_formations_cache = _get_all_alive()
		_sorted_formations_cache.sort_custom(func(a: BattleFormationV3, b: BattleFormationV3) -> bool: return a.speed > b.speed)
		_sorted_formations_dirty = false
	else:
		# Remove dead/fled from cache (in-place to avoid allocation)
		var i := 0
		while i < _sorted_formations_cache.size():
			if _sorted_formations_cache[i].is_dead or _sorted_formations_cache[i].is_fled:
				_sorted_formations_cache.remove_at(i)
			else:
				i += 1
	var all := _sorted_formations_cache

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

	# Battle timer: force ALL non-routing formations to advance
	if tick_count >= BATTLE_TIMER_TICKS:
		for f in all:
			if not f.is_dead and not f.is_fled and not f.is_routing:
				f.current_order = Enums.BattleOrder.ADVANCE
				f.target_priority = Enums.TargetPriority.CLOSEST
				f.focus_tag_filter = ""

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

	# Armor aura recalculation (reset and apply each tick)
	for f in all:
		f.armor_aura_bonus = 0
	for f in all:
		if f.is_dead or f.is_fled or f.armor_aura <= 0 or f.fear_radius <= 0:
			continue
		var aura_range := float(f.fear_radius) * RANGED_PX_PER_RANGE * 0.5
		var allies := attacker_formations if f.side == 0 else defender_formations
		for ally in allies:
			if ally == f or ally.is_dead or ally.is_fled:
				continue
			if f.position.distance_to(ally.position) <= aura_range:
				ally.armor_aura_bonus = maxi(ally.armor_aura_bonus, f.armor_aura)

	# Phase 1: Movement
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		if f.is_routing:
			actions.append_array(_execute_rout_movement(f))
			continue
		# Chariot trample cooldown tick-down
		if f.chariot_trample_cooldown > 0:
			f.chariot_trample_cooldown -= 1
		if _check_melee_contact(f):
			# Chariots don't stop at melee contact — they plow through dealing trample damage
			if f.tags.has("chariot"):
				f.in_melee_contact = true
				f.is_idle_this_tick = false
				f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_CHARGE)
				# Deal trample damage while passing through
				actions.append_array(_execute_chariot_trample(f))
				# Keep moving — don't stop at contact
				actions.append_array(_execute_order_movement(f))
				continue
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
				# In melee: face the enemy directly
				_rotate_toward_smooth(f, melee_target.position)
				var dist_to_target := f.position.distance_to(melee_target.position)
				var engage_dist := f.cached_radius + melee_target.cached_radius + 12.0
				# Depleted ranged units advance aggressively into melee (no tapering)
				var is_depleted_ranged := f.attack_range > 1 and ((f.max_ammo > 0 and f.current_ammo <= 0) or (f.max_mana > 0.0 and f.current_mana < MANA_COST_SPELL * 0.3))
				if is_depleted_ranged:
					# Commit fully to melee — close gap at full speed
					if dist_to_target > engage_dist * 0.5:
						var close_dir := f.position.direction_to(melee_target.position)
						f.position += close_dir * f.move_speed * 0.8
				elif dist_to_target > engage_dist * 0.8:
					var close_dir := f.position.direction_to(melee_target.position)
					var close_speed := f.move_speed * 0.6
					if f.tags.has("cavalry"):
						close_speed = f.move_speed * 0.8
					if f.current_order == Enums.BattleOrder.CHARGE:
						close_speed = f.move_speed * 1.2
					# Taper off speed as we get close to prevent overshoot
					var approach_factor := clampf((dist_to_target - engage_dist * 0.8) / engage_dist, 0.0, 1.0)
					close_speed *= approach_factor
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

	# Defensive terrain damage effects (caltrops, mines, palings)
	_apply_defensive_terrain_damage(all, actions)

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

	# Phase 4b: Army-wide rout check — if side is overwhelmed, all units break
	_check_army_rout(attacker_formations, defender_formations, actions)
	_check_army_rout(defender_formations, attacker_formations, actions)

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
		# Endurance regen: full when idle, slow when marching (not in melee/sprinting)
		if f.is_idle_this_tick:
			f.current_endurance = minf(f.max_endurance, f.current_endurance + ENDURANCE_REGEN_IDLE)
		elif not f.in_melee_contact and not f.is_sprinting:
			# Slow regen while marching (advancing/flanking but not fighting or sprinting)
			f.current_endurance = minf(f.max_endurance, f.current_endurance + ENDURANCE_REGEN_MARCHING)
		# Mana regen: permanent but slow
		if f.max_mana > 0.0:
			f.current_mana = minf(f.max_mana, f.current_mana + MANA_REGEN)

	# Phase 5c: Beast special abilities (regen, damage aura, spawning)
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		# HP regeneration
		if f.hp_regen_per_tick > 0.0 and f.current_hp < f.max_hp:
			var should_regen := true
			if f.regen_requires_combat:
				should_regen = f.in_melee_contact  # Only regen while in melee combat
			if should_regen:
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
		# Healing aura
		if f.healing_aura > 0.0 and f.fear_radius > 0:
			var heal_range := float(f.fear_radius) * RANGED_PX_PER_RANGE * 0.5
			var allies := attacker_formations if f.side == 0 else defender_formations
			for ally in allies:
				if ally == f or ally.is_dead or ally.is_fled:
					continue
				if ally.current_hp >= ally.max_hp:
					continue
				if f.position.distance_to(ally.position) <= heal_range:
					# bugfix (Task R2): plain roundi() silently zeroed every
					# rescaled healing_aura (old values 0.3-2.0 -> /10.0 ->
					# 0.03-0.2 -> roundi() -> 0, EVERY time), disabling the
					# whole heal-aura mechanic. Data stays a straight float
					# divide (healing_aura is a rate, not a bonus ratio); the
					# floor belongs here at the per-tick consumption site.
					# maxi(1, ...) makes `heal` unconditionally >= 1 here
					# (the enclosing `f.healing_aura > 0.0` guard at the top
					# of this block is the only gate needed) -- removed the
					# now-dead `if heal > 0:` check (Task R2 review).
					var heal := maxi(1, roundi(f.healing_aura))
					ally.current_hp = mini(ally.max_hp, ally.current_hp + heal)
					if ally.total_entities == 1:
						ally.front_entity_hp = ally.current_hp
		# Unit spawning
		if f.spawn_interval > 0 and f.spawn_unit_data_id != &"":
			f.spawn_counter -= 1
			if f.spawn_counter <= 0:
				f.spawn_counter = f.spawn_interval
				var spawned := _spawn_unit_from_beast(f)
				if spawned:
					actions.append({"type": "spawn", "source": f.instance_id, "spawned": spawned.instance_id})

	# Phase 5d: Process debuffs (DoT, slow, defense reduction)
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		if f.debuffs.is_empty():
			continue
		var i_db := 0
		while i_db < f.debuffs.size():
			var db: Dictionary = f.debuffs[i_db]
			db.ticks -= 1
			if db.type == &"dot" or db.type == &"poison":
				# scale-note (Task R2): literal 1 HP floor; db.value is
				# already derived from already-rescaled hit damage x pct, so
				# only this floor is disproportionate -- DoT is a minor
				# damage source, kept as-is per R1/R2 DECIDE-list disposition.
				var dot_tick_dmg := maxi(1, int(db.value))
				f.damage_dealt -= 0  # DoT doesn't count as attacker DPS
				var killed := f.take_damage(dot_tick_dmg)
				if killed > 0:
					actions.append({"type": "dot_damage", "target": f.instance_id, "damage": dot_tick_dmg, "killed": killed})
				if f.is_dead:
					recent_deaths.append({"side": f.side, "position": f.position, "tick": tick_count})
					break
			elif db.type == &"stun":
				# Stunned units cannot act this tick — skip movement and attacks
				f.is_idle_this_tick = true
			if db.ticks <= 0:
				# Remove expired debuff and restore effects
				if db.type == &"slow":
					f.move_speed /= maxf(0.01, 1.0 - db.value)
				elif db.type == &"defense_down":
					f.defense += int(db.value)
					f.melee_defense += int(db.value)
					f.magic_defense += int(db.value)
				f.debuffs.remove_at(i_db)
			else:
				i_db += 1

	# Phase 6: Victory check
	_check_victory()

	# Clean stale deaths (in-place, every 10 ticks)
	if tick_count % 10 == 0:
		var cutoff := tick_count - 25
		var i := 0
		while i < recent_deaths.size():
			if recent_deaths[i].tick < cutoff:
				recent_deaths.remove_at(i)
			else:
				i += 1

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

	# Rotation inertia: moving units turn toward movement direction, not enemy
	# 0.15 = slower turn with inertia feel; 0.3 = default snappy turn for stationary
	match f.current_order:
		Enums.BattleOrder.ADVANCE:
			var dir := f.position.direction_to(target.position)
			var move_target := f.position + dir * effective_speed
			f.position = move_target
			# Face movement direction with inertia
			_rotate_toward_smooth(f, move_target + dir * 100.0, 0.15)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			if not f.is_sprinting: # Sprint drain already applied above
				f.is_idle_this_tick = false
				f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.HOLD:
			# Stationary: face the enemy directly
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
			var move_target := f.position + diag * effective_speed
			f.position = move_target
			# Face flanking direction with inertia
			_rotate_toward_smooth(f, move_target + diag * 100.0, 0.15)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.FLANK_RIGHT:
			var fwd := f.position.direction_to(target.position)
			var right := Vector2(-fwd.y, fwd.x)
			var diag := (fwd + right).normalized()
			var move_target := f.position + diag * effective_speed
			f.position = move_target
			# Face flanking direction with inertia
			_rotate_toward_smooth(f, move_target + diag * 100.0, 0.15)
			actions.append({"type": "move", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_ADVANCE)

		Enums.BattleOrder.CHARGE:
			var dir := f.position.direction_to(target.position)
			var move_target := f.position + dir * effective_speed * 2.0
			f.position = move_target
			# Charge: face movement direction but turn faster (aggressive)
			_rotate_toward_smooth(f, move_target + dir * 100.0, 0.2)
			actions.append({"type": "charge", "id": f.instance_id, "to": f.position})
			f.is_idle_this_tick = false
			f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_CHARGE)

		Enums.BattleOrder.RETREAT:
			var retreat_y := FIELD_HEIGHT if f.side == 0 else 0.0
			var retreat_target := Vector2(f.position.x, retreat_y)
			var dir := f.position.direction_to(retreat_target)
			f.position += dir * effective_speed
			# Face retreat direction
			_rotate_toward_smooth(f, f.position + dir * 100.0, 0.15)
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
	# Routing units face their flee direction
	_rotate_toward_smooth(f, f.position + dir * 100.0, 0.2)
	_update_entity_world_positions(f)
	actions.append({"type": "rout", "id": f.instance_id, "to": f.position})

	# Check if fled off map
	if f.side == 0 and f.position.y >= FIELD_HEIGHT - 5.0:
		f.is_fled = true
	elif f.side == 1 and f.position.y <= 5.0:
		f.is_fled = true

	return actions

func _rotate_toward_smooth(f: BattleFormationV3, target_pos: Vector2, smooth_factor: float = 0.3) -> void:
	var diff := target_pos - f.position
	if diff.length_squared() < 1.0:
		return
	var target_rot := atan2(diff.x, -diff.y)
	# Smooth rotation (lerp toward target with inertia)
	var angle_diff := fmod(target_rot - f.rotation + 3.0 * PI, TAU) - PI
	f.rotation += angle_diff * smooth_factor
	f.rotation = fmod(f.rotation + TAU, TAU)

# --- Contact Detection ---

func _check_melee_contact(f: BattleFormationV3) -> bool:
	var nearby := _get_nearby_formations(f.position)
	for other: BattleFormationV3 in nearby:
		if other == f or other.side == f.side:
			continue
		if other.is_dead or other.is_fled:
			continue
		var quick_dist: float = (f.cached_radius + other.cached_radius + 12.0) * 3.0
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

	# Pre-filter to only nearby alive enemies (skip distant formations entirely)
	var all_enemies := _get_side_formations(1 - f.side)
	var enemies: Array[BattleFormationV3] = []
	for enemy in all_enemies:
		if enemy.is_dead or enemy.is_fled:
			continue
		if f.position.distance_to(enemy.position) < 200.0:
			enemies.append(enemy)
	if enemies.is_empty():
		return

	var max_drift := ENTITY_SPACING * 5.0
	if f.tags.has("cavalry"):
		max_drift = ENTITY_SPACING * 8.0

	# Cap per-entity checks to avoid O(n*m) explosion
	var entity_limit := mini(limit, 20)
	for i in entity_limit:
		var epos: Vector2 = f.entity_target_positions[i]
		# Check if this entity is already engaging an enemy entity (check center first)
		var is_engaged := false
		var nearest_pos := Vector2.ZERO
		var nearest_dist := 999999.0
		for enemy in enemies:
			var engage_dist := f.cached_radius + enemy.cached_radius + 12.0
			# Use formation center as proxy first
			var center_d := epos.distance_to(enemy.position)
			if center_d > engage_dist * 5.0:
				continue
			var elimit := mini(enemy.entities_alive, mini(enemy.entity_positions.size(), 15))
			for j in elimit:
				var d := epos.distance_to(enemy.entity_positions[j])
				if d < engage_dist:
					is_engaged = true
					break
				if d < nearest_dist:
					nearest_dist = d
					nearest_pos = enemy.entity_positions[j]
			if is_engaged:
				break

		if is_engaged:
			continue

		if nearest_dist < 999999.0:
			var drift_dir := (nearest_pos - epos).normalized()
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

	var engage_dist := attacker.cached_radius + defender.cached_radius + 12.0
	var dlimit := mini(defender.entities_alive, mini(defender.entity_target_positions.size(), 20))
	var alimit := mini(attacker.entities_alive, mini(attacker.entity_positions.size(), 20))

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
	if f.entities_alive <= 1:
		return
	var limit := mini(f.entities_alive, f.entity_local_offsets.size())
	# Pre-filter to only nearby alive enemies
	var all_enemies := _get_side_formations(1 - f.side)
	var enemies: Array[BattleFormationV3] = []
	for enemy in all_enemies:
		if enemy.is_dead or enemy.is_fled:
			continue
		if f.position.distance_to(enemy.position) < 200.0:
			enemies.append(enemy)
	if enemies.is_empty():
		return

	var engage_dist := f.cached_radius * 2.0 + 15.0
	var max_spread := ENTITY_SPACING * f.cached_radius * 2.5
	var drift_amount := 0.6 * f.move_speed
	if f.tags.has("cavalry"):
		max_spread = ENTITY_SPACING * f.cached_radius * 3.0
		drift_amount = 1.2 * f.move_speed
	var cos_r := cos(-f.rotation)
	var sin_r := sin(-f.rotation)

	# Cap entity iterations
	var check_limit := mini(limit, 20)
	for i in check_limit:
		var world_pos: Vector2 = f.entity_positions[i] if i < f.entity_positions.size() else f.position
		var nearest_enemy := Vector2.ZERO
		var nearest_dist := 999999.0
		for enemy in enemies:
			# Use formation center as first approximation
			var center_d := world_pos.distance_to(enemy.position)
			if center_d > engage_dist * 6.0:
				continue
			var elimit := mini(enemy.entities_alive, mini(enemy.entity_positions.size(), 15))
			for j in elimit:
				var d := world_pos.distance_to(enemy.entity_positions[j])
				if d < nearest_dist:
					nearest_dist = d
					nearest_enemy = enemy.entity_positions[j]

		if nearest_dist > engage_dist * 5.0:
			continue

		var drift_dir := (nearest_enemy - world_pos).normalized()
		var local_drift := Vector2(
			drift_dir.x * cos_r - drift_dir.y * sin_r,
			drift_dir.x * sin_r + drift_dir.y * cos_r
		) * drift_amount

		var new_offset := f.entity_local_offsets[i] + local_drift
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
	var engage_dist := f1.cached_radius + f2.cached_radius + 12.0
	var engage_dist_sq := engage_dist * engage_dist
	# Cap iterations to avoid O(n^2) on large formations
	# Swarm units need higher limits so their spread-out entities can make contact
	var cap1 := 40 if f1.formation_shape == Enums.FormationShape.SWARM else 20
	var cap2 := 40 if f2.formation_shape == Enums.FormationShape.SWARM else 20
	var limit1 := mini(f1.entities_alive, mini(f1.entity_positions.size(), cap1))
	var limit2 := mini(f2.entities_alive, mini(f2.entity_positions.size(), cap2))
	var positions1 := f1.entity_positions
	var positions2 := f2.entity_positions
	for i in limit1:
		var p1 := positions1[i]
		for j in limit2:
			if p1.distance_squared_to(positions2[j]) < engage_dist_sq:
				count += 1
				break  # One contact per entity is enough
	return mini(count, mini(f1.entities_alive, f2.entities_alive))

func _find_all_contact_pairs() -> Array[Array]:
	var pairs: Array[Array] = []
	var checked: Dictionary = {}

	# Iterate BOTH sides so defender formations can also initiate contact
	# (e.g., monsters pursuing routing attacker cavalry)
	for f in attacker_formations + defender_formations:
		if f.is_dead or f.is_fled or f.is_routing:
			continue
		var nearby := _get_nearby_formations(f.position)
		for other: BattleFormationV3 in nearby:
			if other == f or other.side == f.side:
				continue
			if other.is_dead or other.is_fled:
				continue
			# Routing enemies: only cavalry/fast/monster can pursue them
			if other.is_routing:
				if not (f.tags.has("cavalry") or f.tags.has("fast") or f.tags.has("monster")):
					continue
			var pk := _pair_key(f.instance_id, other.instance_id)
			if checked.has(pk):
				continue
			# Quick distance check before expensive entity check
			var quick_dist: float = (f.cached_radius + other.cached_radius + 12.0) * 5.0
			if f.position.distance_squared_to(other.position) > quick_dist * quick_dist:
				continue
			var contact := _entities_in_contact(f, other)
			if contact > 0:
				checked[pk] = true
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

	# A attacks B (chariots deal damage via trample instead — skip their melee attack)
	if not a.tags.has("chariot"):
		var result_ab := _resolve_melee_combat(a, b)
		var ab_dmg: int = result_ab.damage
		if ab_dmg > 0:
			a.damage_dealt += ab_dmg
			var killed := b.take_damage(ab_dmg)
			b.current_morale -= result_ab.morale_damage
			if b.total_entities > 1 and killed > 0:
				b.current_morale -= killed * 3.0 * TICK_SCALE
			# Research: poison DoT from melee hits
			if a.poison_damage_pct > 0.0:
				# scale-note (Task R2): literal 1.0 floor; ab_dmg is already a
				# rescaled hit-damage value and poison_damage_pct is an
				# unrelated-scale rate (KEEP), so the unfloored product
				# auto-scales -- same minor-damage-source disposition as the
				# DoT tick floor below, kept as-is.
				var poison_dmg := maxf(1.0, float(ab_dmg) * a.poison_damage_pct)
				b.debuffs.append({"type": &"poison", "value": poison_dmg / 5.0, "ticks": 5})
			# Research: stun chance from melee hits
			if a.stun_chance_pct > 0.0 and randf() < a.stun_chance_pct:
				b.debuffs.append({"type": &"stun", "value": 0.0, "ticks": 3})
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

	# B attacks A (routing units don't fight back; chariots skip their attack here too)
	if not b.is_dead and not b.is_fled and not b.is_routing and not b.tags.has("chariot"):
		var result_ba := _resolve_melee_combat(b, a)
		var ba_dmg: int = result_ba.damage
		if ba_dmg > 0:
			b.damage_dealt += ba_dmg
			var killed := a.take_damage(ba_dmg)
			a.current_morale -= result_ba.morale_damage
			if a.total_entities > 1 and killed > 0:
				a.current_morale -= killed * 3.0 * TICK_SCALE
			# Research: poison DoT from melee hits
			if b.poison_damage_pct > 0.0:
				# scale-note (Task R2): same disposition as the a->b poison
				# floor above (auto-scales via ba_dmg, minor damage source).
				var poison_dmg := maxf(1.0, float(ba_dmg) * b.poison_damage_pct)
				a.debuffs.append({"type": &"poison", "value": poison_dmg / 5.0, "ticks": 5})
			# Research: stun chance from melee hits
			if b.stun_chance_pct > 0.0 and randf() < b.stun_chance_pct:
				a.debuffs.append({"type": &"stun", "value": 0.0, "ticks": 3})
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

	var engage_dist := attacker.cached_radius + defender.cached_radius + 12.0
	var engage_dist_sq := engage_dist * engage_dist
	var inv_engage_dist := 1.0 / engage_dist
	var def_facing := defender.get_facing_vector()
	# Cap entity iterations to avoid O(n^2) on large formations
	# Swarms need higher caps so their spread-out entities register contacts properly
	var cap_a := 40 if attacker.formation_shape == Enums.FormationShape.SWARM else 20
	var cap_d := 40 if defender.formation_shape == Enums.FormationShape.SWARM else 20
	var limit_a := mini(attacker.entities_alive, mini(attacker.entity_positions.size(), cap_a))
	var limit_d := mini(defender.entities_alive, mini(defender.entity_positions.size(), cap_d))
	# Scale results up if we sampled a subset
	var scale_a := float(mini(attacker.entities_alive, attacker.entity_positions.size())) / float(maxi(limit_a, 1))
	var scale_d := float(mini(defender.entities_alive, defender.entity_positions.size())) / float(maxi(limit_d, 1))
	var contact_scale := maxf(scale_a, scale_d)

	var atk_positions := attacker.entity_positions
	var def_positions := defender.entity_positions
	for i in limit_a:
		var apos := atk_positions[i]
		for j in limit_d:
			var dpos := def_positions[j]
			var diff := apos - dpos
			var dist_sq := diff.length_squared()
			if dist_sq < engage_dist_sq:
				var dist := sqrt(dist_sq)
				var proximity := maxf(0.35, 1.0 - dist * inv_engage_dist)
				var dir := diff / maxf(dist, 0.001)
				var dot := dir.dot(def_facing)
				if dot > 0.5:
					front_contact += proximity
				elif dot < -0.5:
					rear_contact += proximity
				else:
					flank_contact += proximity

	# Scale up contact values if we only sampled a subset of entities
	if contact_scale > 1.01:
		front_contact *= contact_scale
		flank_contact *= contact_scale
		rear_contact *= contact_scale

	var total_contact := front_contact + flank_contact + rear_contact
	if total_contact < 0.01:
		return {"damage": 0, "morale_damage": 0.0, "contact": 0.0, "flank": 0.0, "rear": 0.0}

	# Cap contact: limited by how many attacker entities are in range (not defender count)
	# This allows many small units to swarm a single large target
	var contact_cap := float(attacker.entities_alive)
	# Large single entities (elderbeasts, dragons) cleave — their massive size hits many at once
	if attacker.total_entities == 1:
		contact_cap = maxf(1.0, attacker.cached_radius / 2.5)
	total_contact = minf(total_contact, contact_cap)

	# Percentage-based defense: armor reduces damage proportionally, never to zero
	# Formula: attack^2 / (attack + defense * 0.5)
	# Uses melee_defense for melee combat
	var atk_f := float(attacker.attack)
	# Research: siege bonus adds attack vs constructs and in city battles
	if attacker.siege_bonus > 0 and (defender.tags.has("construct") or defender.tags.has("stationary") or _is_city_battle):
		atk_f += float(attacker.siege_bonus)
	var def_f := float(defender.melee_defense + defender.armor_aura_bonus) * 0.5
	# Apply "vs_X" bonuses — attacker gets bonus attack vs specific defender tags
	for tag in defender.tags:
		atk_f += float(attacker.vs_attack_bonuses.get(tag, 0))
	# Defender gets bonus defense vs specific attacker tags
	for tag in attacker.tags:
		def_f += float(defender.vs_defense_bonuses.get(tag, 0)) * 0.5
	# rescale (Task R2): floor scaled 0.5 -> 0.05 alongside attack/defense
	# /10 (quadratic formula is scale-consistent -- see task-R2-report.md --
	# so this re-engages at the same relative frequency as before the rescale).
	var per_tile_dps := maxf(0.05, atk_f * atk_f / (atk_f + def_f))

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
		per_tile_dps *= lerpf(0.6, 1.0, hp_ratio)
		# Large single entities cleave many targets — reduce per-hit DPS to compensate
		per_tile_dps *= 0.8

	# Anti-swarm bonus: monsters/beasts deal extra damage vs swarm-tagged units
	if (attacker.tags.has("monster") or attacker.tags.has("beast")) and defender.tags.has("swarm"):
		per_tile_dps *= 1.3

	# Pursuit bonus: attacking a routing enemy deals +50% damage
	if defender.is_routing:
		per_tile_dps *= 1.5

	# Terrain defense bonus (percentage reduction on top)
	var terrain_def := BattleTerrainGen.get_defense_bonus(get_terrain_at(defender.position))
	if terrain_def > 0:
		per_tile_dps *= maxf(0.5, 1.0 - terrain_def * 0.05)

	# Infantry vs infantry: reduce damage to make clashes longer and less explosive
	if attacker.tags.has("infantry") and defender.tags.has("infantry"):
		per_tile_dps *= 0.55

	# Fast attackers (speed 6+) get less of a speed reduction (10% total instead of 15%)
	if attacker.tags.has("fast") or attacker.speed >= 6:
		per_tile_dps *= 1.06

	# scale-note (Task R2): literal 1 HP floor, aggregated across total_contact
	# already-scaled hits -- kept as-is per R1/R2 DECIDE-list disposition.
	var total_damage := maxi(1, int(per_tile_dps * total_contact * randf_range(0.85, 1.15) * TICK_SCALE))

	# Stance modifiers
	if attacker.stance == Enums.UnitStance.AGGRESSIVE:
		total_damage = int(total_damage * 1.2)
	if defender.stance == Enums.UnitStance.DEFENSIVE:
		total_damage = int(total_damage * 0.8)

	# Charge bonus on first contact (cavalry order)
	if attacker.current_order == Enums.BattleOrder.CHARGE:
		var charge_mult: float = CHARGE_DAMAGE_MULT + _side_cmd_bonuses[attacker.side].get("charge_damage_mult", 0.0) + attacker.charge_damage_bonus
		total_damage = int(total_damage * charge_mult)

	# Research: flanking damage bonus (applies to flank + rear contact portion)
	if attacker.flanking_damage_bonus > 0.0 and (flank_contact + rear_contact) > 0.01:
		var flank_ratio := (flank_contact + rear_contact) / total_contact
		total_damage += int(float(total_damage) * flank_ratio * attacker.flanking_damage_bonus)

	# Research: adjacent unit bonus (bonus when friendly unit within support range)
	if attacker.adjacent_unit_damage_pct > 0.0:
		var allies := attacker_formations if attacker.side == 0 else defender_formations
		for ally in allies:
			if ally == attacker or ally.is_dead or ally.is_fled:
				continue
			if attacker.position.distance_to(ally.position) < 120.0:
				total_damage += int(float(total_damage) * attacker.adjacent_unit_damage_pct)
				break  # Only one adjacent bonus

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

# --- Chariot Trample ---

func _execute_chariot_trample(chariot: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	# Trample cooldown: deal trample damage every 3 ticks (not every tick)
	if chariot.chariot_trample_cooldown > 0:
		return actions
	chariot.chariot_trample_cooldown = 3

	var enemies := defender_formations if chariot.side == 0 else attacker_formations
	var trample_range := chariot.cached_radius * 3.0 + 20.0
	var speed_factor := clampf(chariot.move_speed / 4.0, 0.5, 2.5)
	if chariot.momentum > 0.3:
		speed_factor *= 1.0 + chariot.momentum * 0.6

	for enemy in enemies:
		if enemy.is_dead or enemy.is_fled:
			continue
		var dist := chariot.position.distance_to(enemy.position)
		if dist > trample_range:
			continue

		# Trample damage: attack-based, scaled by speed and momentum
		var atk_f := float(chariot.attack)
		var def_f := float(enemy.melee_defense) * 0.3  # Armor helps less against trampling
		# rescale (Task R2): floor scaled 1.0 -> 0.1 alongside attack/defense /10.
		var trample_dps := maxf(0.1, atk_f * atk_f / (atk_f + def_f))
		trample_dps *= speed_factor * TICK_SCALE * 1.5  # 50% bonus over regular melee

		# Contact estimate: how many chariot entities are near the enemy
		var contact := 0.0
		var c_limit := mini(chariot.entities_alive, chariot.entity_positions.size())
		var e_limit := mini(enemy.entities_alive, enemy.entity_positions.size())
		var engage_sq := trample_range * trample_range
		for ci in mini(c_limit, 10):
			for ei in mini(e_limit, 15):
				if chariot.entity_positions[ci].distance_squared_to(enemy.entity_positions[ei]) < engage_sq:
					contact += 1.0
					break  # One match per chariot entity is enough
		contact = minf(contact, float(chariot.entities_alive))
		if contact < 0.5:
			continue

		# scale-note (Task R2): literal 1 HP floor, aggregated across contact
		# already-scaled hits -- kept as-is per R1/R2 DECIDE-list disposition.
		var total_damage := maxi(1, int(trample_dps * contact))

		if chariot.faction_in_debt:
			total_damage = int(total_damage * 0.85)

		chariot.damage_dealt += total_damage
		var killed := enemy.take_damage(total_damage)

		# Trample causes heavy morale damage — being run over is terrifying
		enemy.current_morale -= contact * 2.5 * TICK_SCALE

		# Push enemy entities aside (scatter effect)
		if not enemy.is_dead:
			var push_dir := chariot.get_facing_vector()
			var push_strength := chariot.move_speed * 0.4
			var scatter_limit := mini(e_limit, 10)
			for ei in scatter_limit:
				if chariot.position.distance_squared_to(enemy.entity_positions[ei]) < engage_sq:
					var scatter := push_dir * push_strength + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
					enemy.entity_positions[ei] += scatter
					if enemy.entity_target_positions.size() > ei:
						enemy.entity_target_positions[ei] += scatter * 0.5

		actions.append({
			"type": "melee_hit", "attacker": chariot.instance_id, "defender": enemy.instance_id,
			"damage": total_damage, "killed": killed,
			"contact": contact, "flank": 0.0, "rear": 0.0
		})

		if killed > 0:
			var caps := _generate_captives(chariot, enemy, killed)
			if caps > 0:
				actions.append({"type": "captive", "side": chariot.side, "count": caps})
		if enemy.is_dead:
			recent_deaths.append({"side": enemy.side, "position": enemy.position, "tick": tick_count})

	return actions

# --- Spell Effect Helpers ---

func _apply_debuff(target: BattleFormationV3, type: StringName, value: float, ticks: int) -> void:
	# Check if debuff already exists — refresh duration, don't stack
	for db in target.debuffs:
		if db.type == type:
			db.ticks = maxi(db.ticks, ticks)
			return
	# Apply new debuff
	target.debuffs.append({type = type, value = value, ticks = ticks})
	if type == &"slow":
		target.move_speed *= (1.0 - value)
	elif type == &"defense_down":
		target.defense = maxi(0, target.defense - int(value))
		target.melee_defense = maxi(0, target.melee_defense - int(value))
		target.magic_defense = maxi(0, target.magic_defense - int(value))

func _find_splash_target(caster: BattleFormationV3, primary_target: BattleFormationV3) -> BattleFormationV3:
	var enemies := defender_formations if caster.side == 0 else attacker_formations
	var best: BattleFormationV3 = null
	var best_dist := 999999.0
	for e in enemies:
		if e == primary_target or e.is_dead or e.is_fled:
			continue
		var d := primary_target.position.distance_to(e.position)
		if d < best_dist and d < RANGED_PX_PER_RANGE * 3.0:
			best_dist = d
			best = e
	return best

func _heal_nearest_ally(caster: BattleFormationV3, amount: int) -> void:
	if amount <= 0:
		return
	var allies := attacker_formations if caster.side == 0 else defender_formations
	var best: BattleFormationV3 = null
	var best_dist := 999999.0
	for ally in allies:
		if ally == caster or ally.is_dead or ally.is_fled:
			continue
		if ally.current_hp >= ally.max_hp:
			continue
		var d := caster.position.distance_to(ally.position)
		if d < best_dist:
			best_dist = d
			best = ally
	if best:
		best.current_hp = mini(best.max_hp, best.current_hp + amount)
		if best.total_entities == 1:
			best.front_entity_hp = best.current_hp

func _apply_spell_pre_damage(f: BattleFormationV3, target: BattleFormationV3, dmg_per_entity: float, miss_chance: float, cooldown: int) -> Array:
	# Returns [dmg_per_entity, miss_chance, cooldown] modified by spell type
	match f.spell_type:
		&"fireball":
			cooldown = int(float(cooldown) * 1.2)
		&"lightning":
			miss_chance = 0.15
		&"frost_bolt":
			miss_chance = 0.25
		&"death_curse":
			dmg_per_entity *= 0.8
		&"sunfire":
			dmg_per_entity *= 1.15
			for tag in target.tags:
				if tag == "undead" or tag == "demonic":
					dmg_per_entity *= 1.2
					break
		&"hex_curse":
			dmg_per_entity *= 0.75
		&"shard_pulse":
			cooldown = int(float(cooldown) * 0.85)
		&"lunar_beam":
			dmg_per_entity *= 0.8  # Lower per-entity but pierces to splash
	return [dmg_per_entity, miss_chance, cooldown]

func _apply_spell_post_damage(f: BattleFormationV3, target: BattleFormationV3, total_damage: int, hit_count: int, actions: Array[Dictionary]) -> void:
	match f.spell_type:
		&"fireball":
			var splash_dmg := int(total_damage * 0.25)
			if splash_dmg > 0:
				var splash_target := _find_splash_target(f, target)
				if splash_target:
					f.damage_dealt += splash_dmg
					var killed := splash_target.take_damage(splash_dmg)
					splash_target.current_morale -= 0.5
					if killed > 0:
						actions.append({"type": "spell_splash", "source": f.instance_id, "target": splash_target.instance_id, "damage": splash_dmg, "killed": killed})
					if splash_target.is_dead:
						recent_deaths.append({"side": splash_target.side, "position": splash_target.position, "tick": tick_count})
		&"lightning":
			# 20% chance to chain to another nearby enemy for 40% damage
			if hit_count > 0 and randf() < 0.20:
				var chain_dmg := int(total_damage * 0.4)
				if chain_dmg > 0:
					var chain_target := _find_splash_target(f, target)
					if chain_target:
						f.damage_dealt += chain_dmg
						var killed := chain_target.take_damage(chain_dmg)
						chain_target.current_morale -= 0.5
						if killed > 0:
							actions.append({"type": "spell_chain", "source": f.instance_id, "target": chain_target.instance_id, "damage": chain_dmg, "killed": killed})
						if chain_target.is_dead:
							recent_deaths.append({"side": chain_target.side, "position": chain_target.position, "tick": tick_count})
		&"frost_bolt":
			if hit_count > 0:
				_apply_debuff(target, &"slow", 0.15, 30)
		&"death_curse":
			if total_damage > 0:
				# DoT: 50% of damage dealt over 30 ticks
				var dot_per_tick := float(total_damage) * 0.5 / 30.0
				_apply_debuff(target, &"dot", dot_per_tick, 30)
		&"heal_bolt":
			if total_damage > 0:
				_heal_nearest_ally(f, int(total_damage * 0.15))
		&"hex_curse":
			if hit_count > 0:
				_apply_debuff(target, &"defense_down", 2.0, 40)
		&"shard_pulse":
			var splash_dmg := int(total_damage * 0.4)
			if splash_dmg > 0:
				var splash_target := _find_splash_target(f, target)
				if splash_target:
					f.damage_dealt += splash_dmg
					var killed := splash_target.take_damage(splash_dmg)
					if killed > 0:
						actions.append({"type": "spell_splash", "source": f.instance_id, "target": splash_target.instance_id, "damage": splash_dmg, "killed": killed})
					if splash_target.is_dead:
						recent_deaths.append({"side": splash_target.side, "position": splash_target.position, "tick": tick_count})
		&"sand_blast":
			if hit_count > 0:
				_apply_debuff(target, &"defense_down", 3.0, 30)
		&"lunar_beam":
			# Beam pierces — splash 35% damage to 1 nearby enemy
			var beam_splash := int(total_damage * 0.35)
			if beam_splash > 0:
				var beam_target := _find_splash_target(f, target)
				if beam_target:
					f.damage_dealt += beam_splash
					var killed := beam_target.take_damage(beam_splash)
					beam_target.current_morale -= 0.5
					if killed > 0:
						actions.append({"type": "spell_splash", "source": f.instance_id, "target": beam_target.instance_id, "damage": beam_splash, "killed": killed})
					if beam_target.is_dead:
						recent_deaths.append({"side": beam_target.side, "position": beam_target.position, "tick": tick_count})

func _get_spell_morale_mult(spell_type: StringName) -> float:
	if spell_type == &"hex_curse":
		return 3.0  # 3x morale damage
	return 1.0

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

	# --- Skirmish fire mode: staggered per-entity firing ---
	if not f.fires_volleys and f.entity_fire_offsets.size() > 0:
		return _execute_skirmish_fire(f)

	# --- Volley fire mode: all entities fire together ---
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

	# Percentage-based ranged defense: attack * 0.6 scaled by armor type
	# Mages bypass physical armor (use magic_defense); archers use projectile_defense
	var ranged_atk := float(f.attack + f.ranged_attack_bonus) * 0.6
	var target_def_stat: int = target.projectile_defense
	if f.tags.has("mage"):
		target_def_stat = target.magic_defense
	var ranged_def := float(target_def_stat + target.armor_aura_bonus) * 0.3
	# Apply "vs_X" bonuses for ranged combat
	for tag in target.tags:
		ranged_atk += float(f.vs_attack_bonuses.get(tag, 0)) * 0.6
	for tag in f.tags:
		ranged_def += float(target.vs_defense_bonuses.get(tag, 0)) * 0.3
	# rescale (Task R2): floor scaled 0.5 -> 0.05 alongside attack/defense /10.
	var dmg_per_entity := maxf(0.05, ranged_atk * ranged_atk / (ranged_atk + ranged_def))
	# Endurance-based ranged damage reduction
	var ranged_end_ratio := f.current_endurance / f.max_endurance if f.max_endurance > 0.0 else 1.0
	if ranged_end_ratio < 0.5:
		dmg_per_entity *= lerpf(0.6, 1.0, ranged_end_ratio * 2.0)
	# Spell type pre-damage modifiers (accuracy, damage mult, cooldown)
	if f.spell_type != &"bolt" and f.tags.has("mage"):
		var spell_mods := _apply_spell_pre_damage(f, target, dmg_per_entity, miss_chance, cooldown)
		dmg_per_entity = spell_mods[0]
		miss_chance = spell_mods[1]
		cooldown = spell_mods[2]
		f.ranged_cooldown_timer = cooldown  # Update cooldown with spell modifier
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
			# scale-note (Task R2): highest-leverage floor in the codebase --
			# fires once per living entity per tick. HP itself also divides by
			# 10, so "1 damage" stays the same proportional fraction of a
			# target's max_hp as before; the real lever is dmg_per_entity's
			# own floor (0.5 -> 0.05) just above. Kept literal per R1/R2
			# DECIDE-list disposition; watch the ranged_heavy parity category
			# specifically if casualty deltas ever blow the bar.
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
				proj_data["spell_type"] = f.spell_type
				proj_data["speed_var"] = randf_range(0.8, 1.3)
			visual_projs.append(proj_data)

	# Research: fire/magic damage bonus (applies to mage ranged attacks)
	if f.fire_damage_bonus > 0.0 and f.tags.has("mage"):
		total_damage += int(float(total_damage) * f.fire_damage_bonus)

	# Debt penalty: 15% less damage when faction is in debt
	if f.faction_in_debt:
		total_damage = int(total_damage * 0.85)

	if total_damage > 0:
		f.damage_dealt += total_damage
		var killed := target.take_damage(total_damage)
		var morale_mult := _get_spell_morale_mult(f.spell_type) if f.tags.has("mage") else 1.0
		target.current_morale -= 1.5 * morale_mult * (float(hit_count) / maxf(1.0, float(entity_limit)))

		# Research: poison DoT — apply lingering damage as debuff
		if f.poison_damage_pct > 0.0 and hit_count > 0:
			# scale-note (Task R2): same disposition as the melee poison
			# floors (auto-scales via total_damage, minor damage source).
			var poison_dmg := maxf(1.0, float(total_damage) * f.poison_damage_pct)
			target.debuffs.append({"type": &"poison", "value": poison_dmg / 5.0, "ticks": 5})
		# Research: stun chance — chance to briefly pause target actions
		if f.stun_chance_pct > 0.0 and randf() < f.stun_chance_pct:
			target.debuffs.append({"type": &"stun", "value": 0.0, "ticks": 3})

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

		# Spell post-damage effects (splash, chain, debuffs, DoT, heal)
		if f.tags.has("mage") and f.spell_type != &"bolt":
			_apply_spell_post_damage(f, target, total_damage, hit_count, actions)
	elif visual_projs.size() > 0:
		# All missed but still show the projectiles
		actions.append({
			"type": "ranged_hit", "attacker": f.instance_id, "defender": target.instance_id,
			"damage": 0, "killed": 0,
			"projectiles": visual_projs
		})

	return actions

# --- Skirmish Fire (staggered per-entity firing) ---

func _execute_skirmish_fire(f: BattleFormationV3) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# Determine which entities fire this tick based on their offset
	var tick_phase := tick_count % f.ranged_cooldown_max
	var firing_entities: Array[int] = []
	for i in mini(f.entities_alive, f.entity_fire_offsets.size()):
		if f.entity_fire_offsets[i] == tick_phase:
			firing_entities.append(i)
	if firing_entities.is_empty():
		return actions

	var target := _find_target(f)
	if target == null:
		return actions

	var dist := f.position.distance_to(target.position)
	var range_px := f.attack_range * RANGED_PX_PER_RANGE
	if dist > range_px:
		return actions

	# Consume ammo once per full rotation (when tick_phase == 0)
	if f.max_ammo > 0 and tick_phase == 0:
		f.current_ammo -= 1
	# Mana: consume proportionally per sub-volley
	if f.max_mana > 0.0:
		var mana_per_sub := MANA_COST_SPELL / float(f.ranged_cooldown_max)
		f.current_mana = maxf(0.0, f.current_mana - mana_per_sub)

	# Mark as not idle
	f.is_idle_this_tick = false
	f.fired_this_tick = true
	f.current_endurance = maxf(0.0, f.current_endurance - ENDURANCE_DRAIN_SHOOT * 0.3)

	# Miss chance
	var miss_chance := 0.20
	if f.tags.has("mage"):
		miss_chance = 0.30
	if f.faction_id == &"empire":
		miss_chance += 0.20

	# Damage calculation (same as volley)
	var ranged_atk := float(f.attack) * 0.6
	var target_def_stat: int = target.projectile_defense
	if f.tags.has("mage"):
		target_def_stat = target.magic_defense
	var ranged_def := float(target_def_stat + target.armor_aura_bonus) * 0.3
	for tag in target.tags:
		ranged_atk += float(f.vs_attack_bonuses.get(tag, 0)) * 0.6
	for tag in f.tags:
		ranged_def += float(target.vs_defense_bonuses.get(tag, 0)) * 0.3
	# rescale (Task R2): floor scaled 0.5 -> 0.05 alongside attack/defense /10.
	var dmg_per_entity := maxf(0.05, ranged_atk * ranged_atk / (ranged_atk + ranged_def))
	dmg_per_entity *= 0.86 # Skirmish fire DPS reduction vs volley mode
	var ranged_end_ratio := f.current_endurance / f.max_endurance if f.max_endurance > 0.0 else 1.0
	if ranged_end_ratio < 0.5:
		dmg_per_entity *= lerpf(0.6, 1.0, ranged_end_ratio * 2.0)
	# Spell type pre-damage modifiers for skirmish fire (same as volley)
	var skirmish_cooldown_unused := f.ranged_cooldown_max
	if f.spell_type != &"bolt" and f.tags.has("mage"):
		var spell_mods := _apply_spell_pre_damage(f, target, dmg_per_entity, miss_chance, skirmish_cooldown_unused)
		dmg_per_entity = spell_mods[0]
		miss_chance = spell_mods[1]

	var total_damage := 0
	var hit_count := 0
	var entity_limit := mini(f.entities_alive, f.entity_positions.size())
	var target_limit := mini(target.entities_alive, target.entity_positions.size())
	var visual_projs: Array[Dictionary] = []
	var is_mage := f.tags.has("mage")

	for idx in firing_entities:
		if idx >= entity_limit:
			continue
		var is_hit := randf() >= miss_chance
		if is_hit:
			hit_count += 1
			# scale-note (Task R2): highest-leverage floor in the codebase --
			# fires once per living entity per tick. HP itself also divides by
			# 10, so "1 damage" stays the same proportional fraction of a
			# target's max_hp as before; the real lever is dmg_per_entity's
			# own floor (0.5 -> 0.05) just above. Kept literal per R1/R2
			# DECIDE-list disposition; watch the ranged_heavy parity category
			# specifically if casualty deltas ever blow the bar.
			var dmg := maxi(1, int(dmg_per_entity * randf_range(0.8, 1.2)))
			total_damage += dmg
		# Visual projectiles for each firing entity
		if target_limit > 0:
			var from_pos: Vector2 = f.entity_positions[idx]
			var target_idx := randi() % target_limit
			var to_pos: Vector2 = target.entity_positions[target_idx]
			if not is_hit:
				to_pos += Vector2(randf_range(-50, 50), randf_range(-50, 50))
			var proj_data: Dictionary = {"from": from_pos, "to": to_pos, "hit": is_hit}
			if is_mage:
				proj_data["is_mage"] = true
				proj_data["faction_id"] = f.faction_id
				proj_data["spell_type"] = f.spell_type
				proj_data["speed_var"] = randf_range(0.8, 1.3)
			visual_projs.append(proj_data)

	if f.faction_in_debt:
		total_damage = int(total_damage * 0.85)

	if total_damage > 0:
		f.damage_dealt += total_damage
		var killed := target.take_damage(total_damage)
		var skirmish_morale_mult := _get_spell_morale_mult(f.spell_type) if f.tags.has("mage") else 1.0
		target.current_morale -= 1.5 * skirmish_morale_mult * (float(hit_count) / maxf(1.0, float(firing_entities.size())))

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

		# Spell post-damage effects for skirmish fire
		if f.tags.has("mage") and f.spell_type != &"bolt":
			_apply_spell_post_damage(f, target, total_damage, hit_count, actions)
	elif visual_projs.size() > 0:
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

	# Morale auras (friendly and enemy) — use spatial grid to limit checks
	var nearby_for_morale := _get_nearby_formations(f.position)
	for other: BattleFormationV3 in nearby_for_morale:
		if other == f or other.is_dead or other.is_fled:
			continue
		if other.morale_aura == 0 or other.fear_radius <= 0:
			continue
		# Friendly auras: positive morale_aura on same side
		# Enemy fear auras: negative morale_aura on opposite side
		if (other.side == f.side and other.morale_aura > 0) or (other.side != f.side and other.morale_aura < 0):
			var aura_range := float(other.fear_radius) * RANGED_PX_PER_RANGE * 0.5
			if f.position.distance_squared_to(other.position) <= aura_range * aura_range:
				var aura_val: int = other.morale_aura
				# Tag-specific fear bonus (e.g. moonhounds terrify infantry)
				if other.fear_vs_bonus != 0 and other.fear_vs_tags.size() > 0:
					for tag in other.fear_vs_tags:
						if f.tags.has(tag):
							aura_val += other.fear_vs_bonus
							break
				delta += aura_val * 0.5 * TICK_SCALE

	# Nearby ally deaths
	var death_proximity_sq := DEATH_PROXIMITY * DEATH_PROXIMITY
	var death_cutoff := tick_count - 15
	for death in recent_deaths:
		var death_tick: int = death.get("tick", 0)
		if death_tick < death_cutoff:
			continue
		var death_side: int = death.get("side", -1)
		if death_side != f.side:
			continue
		var death_pos: Vector2 = death.get("position", Vector2.ZERO)
		if f.position.distance_squared_to(death_pos) <= death_proximity_sq:
			delta -= 4.0 * TICK_SCALE

	# Apply morale recovery mult from commander traits (only boosts positive recovery)
	if delta > 0.0:
		var morale_mult: float = _side_cmd_bonuses[f.side].get("morale_recovery_mult", 0.0)
		if morale_mult != 0.0:
			delta *= (1.0 + morale_mult)
	f.current_morale = clampf(f.current_morale + delta, -30.0, f.base_morale * 1.5)

	# Undead units never rout — instead they take HP bleed when morale is negative
	if f.tags.has("undead"):
		if f.current_morale < 0.0:
			# Bleed scales with how far below zero morale is (1-3% max HP per tick)
			var bleed_ratio := clampf(absf(f.current_morale) / 30.0, 0.0, 1.0)
			# scale-note (Task R2): literal 1 HP floor on a max_hp-relative
			# (0.3%-1%) tick -- same family as R1 §2.3's city_system.gd/
			# turn_manager.gd attrition floors; stays <=1% of a unit's HP
			# pool even at 10x relative harshness, kept as-is.
			var bleed_dmg := maxi(1, int(float(f.max_hp) * lerpf(0.003, 0.01, bleed_ratio)))
			f.current_hp = maxi(0, f.current_hp - bleed_dmg)
			if f.total_entities == 1:
				f.front_entity_hp = f.current_hp
			elif f.entities_alive > 0:
				f.front_entity_hp = maxi(0, f.front_entity_hp - bleed_dmg)
				if f.front_entity_hp <= 0:
					f.entities_alive -= 1
					if f.entities_alive > 0:
						var hp_per_entity := f.max_hp / f.total_entities
						f.front_entity_hp = hp_per_entity
			if f.current_hp <= 0:
				f.is_dead = true
				_sorted_formations_dirty = true
		return # Skip normal routing logic entirely for undead

	# Cinderguard units never rout — instead they shed armor for speed when morale is low
	if f.tags.has("cinderguard"):
		if f.current_morale <= 0.0 and not f.is_routing:
			# "Molten Retreat": lose defense, gain move speed. Stacks up to 3 times.
			# Each time morale would cause a rout, strip one layer of armor.
			if not f.has_method("get") or true:
				# Track shed count via rally_cooldown (repurposed — cinderguard don't rally)
				var shed_count := f.rout_panic_ticks # Repurpose as shed counter for cinderguard
				if shed_count < 3:
					# bugfix (Task R2): integer `/4` truncated to 0 for any
					# defense < 4, which becomes the COMMON case post-rescale
					# (typical defense ~3-6) -- the maxi(1,...) floor was then
					# firing on nearly every shed instead of occasionally,
					# collapsing graduated 25%/25%/25% shedding into "lose
					# 100% of a 3-point defense stat in one shed". roundi()
					# restores graduated shedding (defense=3 -> roundi(0.75)=1,
					# i.e. ~25%, matching the original design intent).
					var armor_loss := maxi(1, roundi(f.defense * 0.25)) # Lose ~25% of current defense
					f.defense = maxi(0, f.defense - armor_loss)
					f.melee_defense = maxi(0, f.melee_defense - armor_loss)
					f.projectile_defense = maxi(0, f.projectile_defense - armor_loss)
					f.magic_defense = maxi(0, f.magic_defense - armor_loss)
					f.move_speed = f.move_speed * 1.15 # +15% speed per shed
					f.rout_panic_ticks = shed_count + 1
					f.current_morale = float(f.base_morale) * 0.15 # Reset morale slightly above zero
					f.rally_cooldown = 20 # Brief cooldown before next shed can trigger
		# Cinderguard slowly recover morale when not in combat (but never re-gain armor)
		if f.rally_cooldown > 0:
			f.rally_cooldown -= 1
		return # Skip normal routing logic for cinderguard

	# Routing check — enter panic phase when morale drops to threshold
	var rout_threshold: float = 0.0 + _side_cmd_bonuses[f.side].get("retreat_morale_threshold", 0.0)
	if f.current_morale <= rout_threshold and not f.is_routing and f.rally_cooldown <= 0:
		f.is_routing = true
		_sorted_formations_dirty = true
		f.rout_panic_ticks = 40  # ~4 seconds of pure panic (no rally possible)

	# Panic phase countdown
	if f.rout_panic_ticks > 0:
		f.rout_panic_ticks -= 1

	# Rally check — only after panic phase, with gradual probability
	if f.is_routing and f.rout_panic_ticks <= 0 and f.current_morale > float(f.base_morale) * 0.2:
		# Rally chance increases as morale recovers further above threshold
		var morale_ratio := (f.current_morale - float(f.base_morale) * 0.2) / (float(f.base_morale) * 0.8)
		var rally_chance := clampf(morale_ratio * 0.15, 0.01, 0.15)  # 1% to 15% per tick
		if randf() < rally_chance:
			f.is_routing = false
			_sorted_formations_dirty = true
			f.rally_cooldown = 30

	if f.rally_cooldown > 0:
		f.rally_cooldown -= 1

## Army-wide rout: if a side has lost most of its combat power and the enemy
## is clearly superior, all remaining units break and flee.
func _check_army_rout(side_formations: Array[BattleFormationV3], enemy_formations: Array[BattleFormationV3], actions: Array[Dictionary]) -> void:
	# Count side status
	var total := side_formations.size()
	if total <= 1:
		return # Solo units rout individually
	var alive_fighting := 0 # alive and not routing/fled
	var alive_routing := 0
	var dead_or_fled := 0
	var side_hp := 0
	var side_max_hp := 0
	for f in side_formations:
		if f.is_dead or f.is_fled:
			dead_or_fled += 1
		elif f.is_routing:
			alive_routing += 1
			side_hp += f.current_hp
			side_max_hp += f.max_hp
		else:
			alive_fighting += 1
			side_hp += f.current_hp
			side_max_hp += f.max_hp

	if alive_fighting == 0:
		return # Already all routing or dead

	# Count enemy strength
	var enemy_hp := 0
	var enemy_alive := 0
	for f in enemy_formations:
		if not f.is_dead and not f.is_fled:
			enemy_hp += f.current_hp
			enemy_alive += 1

	if enemy_alive == 0:
		return

	# Trigger conditions: side must be overwhelmed
	# 0) No army rout before tick 100 (~10 seconds) to prevent instant snowballs
	if tick_count < 100:
		return
	# 1) More than 70% of original formations are dead/fled/routing
	var broken_ratio: float = float(dead_or_fled + alive_routing) / float(total)
	if broken_ratio < 0.7:
		return
	# 2) Enemy has at least 4x the remaining HP
	var hp_ratio: float = float(enemy_hp) / maxf(float(side_hp), 1.0)
	if hp_ratio < 4.0:
		return

	# Army breaks! All remaining fighting units rout (special factions get alternative effects)
	for f in side_formations:
		if not f.is_dead and not f.is_fled and not f.is_routing:
			if f.tags.has("undead"):
				# Undead don't rout — slam morale to trigger heavy bleed via _update_morale
				f.current_morale = -25.0
				actions.append({"type": "army_rout", "id": f.instance_id})
			elif f.tags.has("cinderguard"):
				# Cinderguard shed all remaining armor instantly, big speed boost
				f.current_morale = -5.0
				f.defense = 0
				f.melee_defense = 0
				f.projectile_defense = 0
				f.magic_defense = 0
				f.move_speed = f.move_speed * 1.4
				f.rout_panic_ticks = 3 # Max shed count
				actions.append({"type": "army_rout", "id": f.instance_id})
			else:
				f.is_routing = true
				f.current_morale = -20.0
				f.rout_panic_ticks = 60 # Long panic — army-wide rout is harder to rally from
				actions.append({"type": "army_rout", "id": f.instance_id})
	_sorted_formations_dirty = true

func _count_friendly_support(f: BattleFormationV3) -> int:
	var count := 0
	# Hoist the facing vector (was computed twice per ally) and compare
	# squared distances (identical comparison, no sqrt per ally).
	var facing := f.get_facing_vector()
	var perp := Vector2(-facing.y, facing.x)
	for ally in _get_side_formations(f.side):
		if ally == f or ally.is_dead or ally.is_fled:
			continue
		var diff := ally.position - f.position
		if diff.length_squared() > 6400.0:
			continue
		# Check if ally is roughly on our flanks
		var lateral := absf(diff.dot(perp))
		var forward := absf(diff.dot(facing))
		if lateral > forward:
			count += 1
	return mini(count, 2)

# --- Captive Generation ---

func _generate_captives(killer: BattleFormationV3, victim: BattleFormationV3, entities_killed: int) -> int:
	var chance := victim.captive_chance
	# Apply captive_chance_mod from commander traits
	chance += _side_cmd_bonuses[killer.side].get("captive_chance_mod", 0.0)
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
	f.spell_type = ud.spell_type if ud.spell_type != &"" else &"bolt"
	f.attack = ud.attack
	f.defense = ud.melee_defense
	f.melee_defense = ud.melee_defense
	f.projectile_defense = ud.projectile_defense
	f.magic_defense = ud.magic_defense
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
	f.fear_vs_tags = ud.fear_vs_tags.duplicate()
	f.fear_vs_bonus = ud.fear_vs_bonus
	f.healing_aura = ud.healing_aura
	f.armor_aura = ud.armor_aura
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
	f.cached_radius = get_entity_radius(f)
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
	var atk_all_routing := true
	var def_all_routing := true
	var atk_has_units := false
	var def_has_units := false
	for f in attacker_formations:
		if not f.is_dead and not f.is_fled:
			atk_alive = true
			atk_has_units = true
			if not f.is_routing:
				atk_all_routing = false
	for f in defender_formations:
		if not f.is_dead and not f.is_fled:
			def_alive = true
			def_has_units = true
			if not f.is_routing:
				def_all_routing = false

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
	# Both sides all routing → auto-end, side with more remaining HP wins
	elif atk_has_units and atk_all_routing and def_has_units and def_all_routing:
		var atk_hp := _sum_alive_hp(attacker_formations)
		var def_hp := _sum_alive_hp(defender_formations)
		_apply_rout_retreat_losses(attacker_formations, defender_formations)
		_apply_rout_retreat_losses(defender_formations, attacker_formations)
		is_finished = true
		if atk_hp > def_hp:
			winner_side = 0
		elif def_hp > atk_hp:
			winner_side = 1
		else:
			winner_side = -1
		battle_ended.emit(winner_side)
	# All enemy formations routing → declare victory and apply retreat losses
	elif atk_has_units and atk_all_routing:
		# If no attacker formation can potentially rally, auto-end immediately
		if not _can_any_rally(attacker_formations):
			_apply_rout_retreat_losses(attacker_formations, defender_formations)
			is_finished = true
			winner_side = 1
			battle_ended.emit(1)
	elif def_has_units and def_all_routing:
		if not _can_any_rally(defender_formations):
			_apply_rout_retreat_losses(defender_formations, attacker_formations)
			is_finished = true
			winner_side = 0
			battle_ended.emit(0)

func _can_any_rally(formations: Array[BattleFormationV3]) -> bool:
	## Returns true if any routing formation on this side has a realistic chance to rally.
	## A formation can rally if its panic phase will expire and morale could recover
	## above the rally threshold (base_morale * 0.2). Formations from army-wide rout
	## (very negative morale + long panic) are considered unrecoverable.
	for f in formations:
		if f.is_dead or f.is_fled:
			continue
		if not f.is_routing:
			return true # Non-routing unit still fighting
		# Routing unit: check if rally is feasible
		# Rally requires: rout_panic_ticks <= 0 AND current_morale > base_morale * 0.2
		# Morale recovers at ~1-2 per tick passively. If morale is deeply negative
		# and panic ticks are high, rally is extremely unlikely.
		var rally_threshold := float(f.base_morale) * 0.2
		# Estimate max morale recovery during remaining panic ticks + some buffer
		# Passive regen is ~2.0 per tick (in combat ~1.0). Be generous with the estimate.
		var estimated_recovery := float(f.rout_panic_ticks + 30) * 2.0
		if f.current_morale + estimated_recovery > rally_threshold:
			return true
	return false

func _sum_alive_hp(formations: Array[BattleFormationV3]) -> int:
	var total := 0
	for f in formations:
		if not f.is_dead and not f.is_fled:
			total += f.current_hp
	return total

func _apply_rout_retreat_losses(routing_side: Array[BattleFormationV3], winning_side: Array[BattleFormationV3]) -> void:
	# Calculate average speed of both sides
	var rout_speed := 0.0
	var rout_count := 0
	for f in routing_side:
		if not f.is_dead and not f.is_fled:
			rout_speed += f.speed
			rout_count += 1
	if rout_count > 0:
		rout_speed /= float(rout_count)

	var win_speed := 0.0
	var win_count := 0
	for f in winning_side:
		if not f.is_dead and not f.is_fled:
			win_speed += f.speed
			win_count += 1
	if win_count > 0:
		win_speed /= float(win_count)

	# Speed ratio: if winner is faster, routing side takes more losses
	# Base loss: 10-30% HP. Faster winner = up to 50% HP loss
	var speed_ratio := win_speed / maxf(rout_speed, 1.0)
	var hp_loss_pct := clampf(0.10 + (speed_ratio - 1.0) * 0.15, 0.10, 0.50)

	for f in routing_side:
		if f.is_dead or f.is_fled:
			continue
		var hp_loss := int(float(f.current_hp) * hp_loss_pct)
		if hp_loss > 0:
			f.take_damage(hp_loss)
		# Mark as fled (retreated off the field)
		if not f.is_dead:
			f.is_fled = true

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
	if not _sorted_formations_dirty and _sorted_formations_cache.size() > 0:
		return _sorted_formations_cache
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

func _pair_key(a: StringName, b: StringName) -> int:
	var ha := a.hash()
	var hb := b.hash()
	if ha > hb:
		return ha * 31 + hb
	return hb * 31 + ha

func _find_target(f: BattleFormationV3) -> BattleFormationV3:
	if _target_cache.has(f.instance_id):
		return _target_cache[f.instance_id]

	# Try spatial grid first for CLOSEST priority (most common case)
	var best: BattleFormationV3 = null
	var best_score := 999999.0

	var focus_filter: String = f.focus_tag_filter

	# Use spatial grid nearby + expand if nothing found
	var nearby := _get_nearby_formations(f.position)
	var found_enemy := false
	for e: BattleFormationV3 in nearby:
		if e.side == f.side or e.is_dead or e.is_fled:
			continue
		found_enemy = true
		var dist := f.position.distance_squared_to(e.position)
		var score: float
		match f.target_priority:
			Enums.TargetPriority.CLOSEST:
				score = dist
			Enums.TargetPriority.WEAKEST:
				score = float(e.current_hp) + dist * 0.000001
			Enums.TargetPriority.STRONGEST:
				score = -float(e.current_hp) + dist * 0.000001
			Enums.TargetPriority.RANGED_FIRST:
				score = dist
				if e.tags.has("ranged") or e.tags.has("mage"):
					score -= 1e12
			Enums.TargetPriority.SUPPORT_FIRST:
				score = dist
				if e.tags.has("support"):
					score -= 1e12
			_:
				score = dist
		# Focus tag filter: heavily prefer enemies matching the filter
		if focus_filter != "" and _matches_focus_filter(e, focus_filter):
			score -= 1e12
		if score < best_score:
			best_score = score
			best = e

	# Fallback to full list only if spatial grid found no enemies nearby
	if not found_enemy:
		var enemies := _get_side_formations(1 - f.side)
		for e in enemies:
			if e.is_dead or e.is_fled:
				continue
			var dist := f.position.distance_squared_to(e.position)
			var score: float
			match f.target_priority:
				Enums.TargetPriority.CLOSEST:
					score = dist
				Enums.TargetPriority.WEAKEST:
					score = float(e.current_hp) + dist * 0.000001
				Enums.TargetPriority.STRONGEST:
					score = -float(e.current_hp) + dist * 0.000001
				Enums.TargetPriority.RANGED_FIRST:
					score = dist
					if e.tags.has("ranged") or e.tags.has("mage"):
						score -= 1e12
				Enums.TargetPriority.SUPPORT_FIRST:
					score = dist
					if e.tags.has("support"):
						score -= 1e12
				_:
					score = dist
			if focus_filter != "" and _matches_focus_filter(e, focus_filter):
				score -= 1e12
			if score < best_score:
				best_score = score
				best = e

	_target_cache[f.instance_id] = best
	return best

func _matches_focus_filter(e: BattleFormationV3, filter: String) -> bool:
	if e.tags.has(filter):
		return true
	# "monster" filter also matches "beast"
	if filter == "monster" and e.tags.has("beast"):
		return true
	return false

# ── Defensive Buildings: Terrain Damage Effects ──────────────────────────

var _mine_triggered: Dictionary = {} # Vector2i -> true (mines that already exploded)

func _apply_defensive_terrain_damage(all: Array[BattleFormationV3], actions: Array[Dictionary]) -> void:
	if _defense_meta.is_empty():
		return
	for f in all:
		if f.is_dead or f.is_fled:
			continue
		var cell := Vector2i(int(f.position.x / terrain_cell_size), int(f.position.y / terrain_cell_size))
		var terrain_type: Enums.BattleTerrain = terrain_grid.get(cell, Enums.BattleTerrain.OPEN)
		# Skip flying units for ground-based traps
		if f.tags.has("flying"):
			continue
		match terrain_type:
			Enums.BattleTerrain.CALTROPS:
				# Tick damage to moving attackers (side 0 = attacker)
				if f.side == 0 and not f.in_melee_contact:
					var dmg := f.take_damage(1)
					if dmg > 0:
						actions.append({"type": "hit", "id": f.instance_id, "damage": dmg, "source": "caltrops"})
			Enums.BattleTerrain.MINE:
				# One-time explosion on first attacker contact
				if f.side == 0 and not _mine_triggered.has(cell):
					_mine_triggered[cell] = true
					var mine_dmg := int(float(f.max_hp) * 0.2)
					var actual := f.take_damage(mine_dmg)
					if actual > 0:
						actions.append({"type": "hit", "id": f.instance_id, "damage": actual, "source": "mine"})
					# Destroy mine after detonation
					terrain_grid[cell] = Enums.BattleTerrain.OPEN
			Enums.BattleTerrain.PALING:
				# Extra impact damage on charging attackers
				if f.side == 0 and f.momentum > 0.5:
					var paling_dmg := int(float(f.max_hp) * 0.05)
					var actual := f.take_damage(paling_dmg)
					if actual > 0:
						actions.append({"type": "hit", "id": f.instance_id, "damage": actual, "source": "paling"})

# ── Defensive Buildings: Tower/Siege Formation Spawning ──────────────────

func setup_city_defense_formations() -> void:
	## Spawn tower and siege formations at positions from _defense_meta.
	## Called after defender setup. Towers/siege are side 1 (defender).
	if _defense_meta.is_empty():
		return

	var _next_id := 9000
	# Arrow Towers
	for tower_pos in _defense_meta.get("tower_positions", []):
		var f := BattleFormationV3.new()
		f.instance_id = StringName("tower_%d" % _next_id)
		_next_id += 1
		f.unit_data_id = &"arrow_tower"
		f.display_name = "Arrow Tower"
		f.faction_id = &"defense"
		f.side = 1
		f.tags = ["construct", "ranged", "stationary"]
		f.attack = 40
		f.defense = 30
		f.melee_defense = 30
		f.projectile_defense = 30
		f.magic_defense = 15
		f.speed = 0
		f.attack_range = 4
		f.total_entities = 1
		f.entities_alive = 1
		f.hp_per_entity = 800
		f.front_entity_hp = 800
		f.max_hp = 800
		f.current_hp = 800
		f.position = Vector2(tower_pos.x * terrain_cell_size, tower_pos.y * terrain_cell_size)
		f.move_speed = 0.0
		f.base_morale = 999
		f.current_morale = 999.0
		f.current_order = Enums.BattleOrder.HOLD
		f.max_ammo = 200
		f.current_ammo = 200
		f.ranged_cooldown_max = 8
		f.fires_volleys = true
		f.cached_radius = 10.0
		f.entity_positions = PackedVector2Array([f.position])
		f.entity_target_positions = PackedVector2Array([f.position])
		f.entity_local_offsets = PackedVector2Array([Vector2.ZERO])
		f.max_endurance = 999.0
		f.current_endurance = 999.0
		defender_formations.append(f)

	# Siege Weapons (Catapults)
	for siege_pos in _defense_meta.get("siege_positions", []):
		var f := BattleFormationV3.new()
		f.instance_id = StringName("siege_%d" % _next_id)
		_next_id += 1
		f.unit_data_id = &"catapult"
		f.display_name = "Catapult"
		f.faction_id = &"defense"
		f.side = 1
		f.tags = ["construct", "ranged", "stationary"]
		f.attack = 80
		f.defense = 10
		f.melee_defense = 10
		f.projectile_defense = 10
		f.magic_defense = 5
		f.speed = 0
		f.attack_range = 6
		f.total_entities = 1
		f.entities_alive = 1
		f.hp_per_entity = 500
		f.front_entity_hp = 500
		f.max_hp = 500
		f.current_hp = 500
		f.position = Vector2(siege_pos.x * terrain_cell_size, siege_pos.y * terrain_cell_size)
		f.move_speed = 0.0
		f.base_morale = 999
		f.current_morale = 999.0
		f.current_order = Enums.BattleOrder.HOLD
		f.max_ammo = 50
		f.current_ammo = 50
		f.ranged_cooldown_max = 20  # Slow fire rate
		f.fires_volleys = true
		f.cached_radius = 10.0
		f.entity_positions = PackedVector2Array([f.position])
		f.entity_target_positions = PackedVector2Array([f.position])
		f.entity_local_offsets = PackedVector2Array([Vector2.ZERO])
		f.max_endurance = 999.0
		f.current_endurance = 999.0
		defender_formations.append(f)
