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

# Stats by level
const LEVEL_STATS := {
	1: {max_hp = 500, building_slots = 1, movement = 1.0, gold = 2, food = 3},
	2: {max_hp = 750, building_slots = 2, movement = 1.0, gold = 4, food = 6},
	3: {max_hp = 1000, building_slots = 3, movement = 1.5, gold = 6, food = 9},
}

func get_max_building_slots() -> int:
	return LEVEL_STATS.get(level, LEVEL_STATS[1]).building_slots

func get_available_building_slots() -> int:
	return get_max_building_slots() - buildings.size()

func get_max_movement() -> float:
	return LEVEL_STATS.get(level, LEVEL_STATS[1]).movement

func get_base_income() -> Dictionary:
	var stats: Dictionary = LEVEL_STATS.get(level, LEVEL_STATS[1])
	return {
		Enums.ResourceType.GOLD: stats.gold,
		Enums.ResourceType.FOOD: stats.food,
	}

func apply_level_stats() -> void:
	var stats: Dictionary = LEVEL_STATS.get(level, LEVEL_STATS[1])
	max_hp = stats.max_hp
	hp = mini(hp, max_hp)
