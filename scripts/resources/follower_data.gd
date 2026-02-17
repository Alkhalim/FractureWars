class_name FollowerData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var bonus_effect: Dictionary = {}  # effect_key -> value (positive)
@export var malus_effect: Dictionary = {}  # effect_key -> value (negative)
