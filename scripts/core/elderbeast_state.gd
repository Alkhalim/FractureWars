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
@export var recruit_queue: Array[Dictionary] = []
@export var movement_remaining: float = 1.0
@export var escort_army_id: StringName = &""
@export var survival_turns: int = 0

func get_max_building_slots() -> int:
	return level # 1 slot at L1, 2 at L2, 3 at L3

func get_available_building_slots() -> int:
	return get_max_building_slots() - buildings.size()
