class_name ElderbeastState
extends Resource

@export var beast_id: StringName
@export var faction_id: StringName = &"shardhorde"
@export var hex_pos: Vector2i
@export var name: String = "Elderbeast"
@export var level: int = 1 # 1-3
@export var hp: int = 500
@export var max_hp: int = 500
@export var buildings: Array[StringName] = []
@export var build_queue: Array[Dictionary] = [] # [{building_id, turns_remaining}]
@export var recruit_queue: Array[Dictionary] = []
@export var movement_remaining: float = 1.0
@export var escort_army_id: StringName = &""
@export var survival_turns: int = 0
@export var population: int = 50
@export var has_moved: bool = false
@export var tile_depletion: Dictionary = {} # Vector2i -> int (turns harvested)
@export var injured_turns: int = 0 # >0 = injured, stationary, vulnerable
@export var unit_instance_id: StringName = &"" # The UnitInstance ID in the escort army
@export var commander: CommanderState = null

# Stats by level
const LEVEL_STATS := {
	1: {max_hp = 500, building_slots = 1, movement = 1.0},
	2: {max_hp = 750, building_slots = 2, movement = 1.0},
	3: {max_hp = 1000, building_slots = 3, movement = 1.5},
}

# Unit data ID per level
const UNIT_DATA_IDS := {
	1: &"elderbeast_lv1",
	2: &"elderbeast_lv2",
	3: &"elderbeast_lv3",
}

func get_unit_data_id() -> StringName:
	return UNIT_DATA_IDS.get(level, &"elderbeast_lv1")

func get_max_building_slots() -> int:
	return LEVEL_STATS.get(level, LEVEL_STATS[1]).building_slots

func get_available_building_slots() -> int:
	return get_max_building_slots() - buildings.size()

func get_max_movement() -> float:
	if injured_turns > 0:
		return 0.0
	return LEVEL_STATS.get(level, LEVEL_STATS[1]).movement

func is_injured() -> bool:
	return injured_turns > 0

func get_depletion_multiplier(tile_pos: Vector2i) -> float:
	var dep: int = tile_depletion.get(tile_pos, 0)
	return maxf(0.1, 1.0 - dep * 0.25)

func apply_level_stats() -> void:
	var stats: Dictionary = LEVEL_STATS.get(level, LEVEL_STATS[1])
	max_hp = stats.max_hp
	hp = mini(hp, max_hp)
