class_name CommanderSkill
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var category: StringName # "combat", "economy", "logistics", "magic"
@export var is_minor: bool = false # true = auto-assigned on level up
@export var effects: Dictionary = {} # effect_type -> value
