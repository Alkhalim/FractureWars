class_name UnitInstance
extends Resource

@export var instance_id: StringName
@export var unit_data_id: StringName
@export var current_hp: int
@export var experience: int = 0
@export var veterancy_level: int = 0

const VETERANCY_XP_THRESHOLDS := [30, 80, 160]
const VETERANCY_STAT_BONUS := [0.05, 0.10, 0.15]
const MAX_VETERANCY := 3

func init_from_data(data: UnitData, id: StringName) -> void:
	instance_id = id
	unit_data_id = data.id
	current_hp = data.max_hp

func grant_xp(amount: int) -> bool:
	experience += amount
	var leveled := false
	while veterancy_level < MAX_VETERANCY:
		if experience >= VETERANCY_XP_THRESHOLDS[veterancy_level]:
			veterancy_level += 1
			leveled = true
		else:
			break
	return leveled

func get_veterancy_bonus() -> float:
	if veterancy_level <= 0:
		return 0.0
	return VETERANCY_STAT_BONUS[mini(veterancy_level, MAX_VETERANCY) - 1]

func get_veterancy_label() -> String:
	match veterancy_level:
		1: return "Trained"
		2: return "Veteran"
		3: return "Elite"
		_: return "Recruit"
