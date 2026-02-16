class_name UnitInstance
extends Resource

@export var instance_id: StringName
@export var unit_data_id: StringName
@export var current_hp: int
@export var experience: int = 0
@export var veterancy_level: int = 0

func init_from_data(data: UnitData, id: StringName) -> void:
	instance_id = id
	unit_data_id = data.id
	current_hp = data.max_hp
