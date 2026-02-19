class_name ShardGuardianSystem
extends RefCounted

# Terrain -> base guardian unit mapping
const TERRAIN_GUARDIAN_UNIT := {
	Enums.TerrainType.PLAINS: &"guardian_wolf",
	Enums.TerrainType.FOREST: &"guardian_bear",
	Enums.TerrainType.MOUNTAINS: &"guardian_eagle",
	Enums.TerrainType.DESERT: &"guardian_scorpion",
	Enums.TerrainType.SWAMP: &"guardian_serpent",
	Enums.TerrainType.TUNDRA: &"guardian_mammoth",
	Enums.TerrainType.SHARD_WASTES: &"guardian_crawler",
	Enums.TerrainType.JUNGLE: &"guardian_jaguar",
}

# Realm modifier sets: {hp_mult, atk_mult, def_mult, spd_mult, extras}
const REALM_MODIFIERS := {
	Enums.Realm.DIVINE: {
		"hp_mult": 1.0, "atk_mult": 1.0, "def_mult": 1.3, "spd_mult": 1.0,
		"morale_bonus": 15,
	},
	Enums.Realm.VOID: {
		"hp_mult": 1.0, "atk_mult": 1.4, "def_mult": 0.9, "spd_mult": 1.1,
		"fear_radius": 2,
	},
	Enums.Realm.ELEMENTAL: {
		"hp_mult": 1.2, "atk_mult": 1.2, "def_mult": 1.0, "spd_mult": 1.0,
		"attack_range": 1,
	},
	Enums.Realm.NATURE: {
		"hp_mult": 1.4, "atk_mult": 1.0, "def_mult": 1.1, "spd_mult": 0.9,
		"hp_regen": 0.5,
	},
	Enums.Realm.MORTAL: {
		"hp_mult": 1.1, "atk_mult": 1.1, "def_mult": 1.1, "spd_mult": 1.1,
	},
}

# Power level -> number of units (power 3 adds an alpha with 2x HP)
const POWER_COMPOSITION := {
	1: 2,
	2: 3,
	3: 4, # + 1 alpha at index 0
}

func spawn_guardian_army(shard: ShardInstance) -> ArmyState:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return null

	var tile := hex_map.get_tile(shard.hex_pos)
	if tile == null:
		return null

	# Pick base unit from terrain
	var terrain: Enums.TerrainType = tile.terrain
	var unit_id: StringName = TERRAIN_GUARDIAN_UNIT.get(terrain, &"guardian_wolf")

	var unit_data := DataManager.get_unit(unit_id)
	if unit_data == null:
		return null

	# Get realm modifiers
	var realm_mods: Dictionary = REALM_MODIFIERS.get(shard.realm, REALM_MODIFIERS[Enums.Realm.MORTAL])
	var hp_mult: float = realm_mods.get("hp_mult", 1.0)

	# Get unit count from power level
	var unit_count: int = POWER_COMPOSITION.get(shard.power_level, 2)
	var has_alpha: bool = shard.power_level >= 3

	# Create army
	var army := ArmyState.new()
	army.army_id = GameManager.state.generate_id()
	army.faction_id = &"shard_guardians"
	army.hex_pos = shard.hex_pos
	army.movement_remaining = 0.0
	army.has_moved = true

	# Create units
	for i in unit_count:
		var instance := UnitInstance.new()
		instance.init_from_data(unit_data, GameManager.state.generate_id())
		instance.current_hp = int(float(unit_data.max_hp) * hp_mult)
		army.units.append(instance)

	# Power 3: insert alpha at index 0 with 2x HP
	if has_alpha:
		var alpha := UnitInstance.new()
		alpha.init_from_data(unit_data, GameManager.state.generate_id())
		alpha.current_hp = int(float(unit_data.max_hp) * hp_mult * 2.0)
		army.units.insert(0, alpha)

	return army

# Get the realm modifiers for use in battle (called by battle simulator)
static func get_realm_mods_for_shard_at(hex_pos: Vector2i) -> Dictionary:
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if shard.hex_pos == hex_pos and shard.guardian_army_id != &"":
			return REALM_MODIFIERS.get(shard.realm, {})
	return {}
