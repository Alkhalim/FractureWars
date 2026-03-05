class_name PolicyData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var category: int # Enums.PolicyCategory
@export var class_loyalty_effects: Dictionary = {} # "peasants" -> +3 per turn
@export var resource_effects: Dictionary = {} # ResourceType int -> +/- per turn
@export var required_class_loyalty: Dictionary = {} # "nobles" -> min 30
@export var mutually_exclusive: Array[StringName] = []
@export var cooldown_turns: int = 3
@export var faction_id: StringName = &"empire"
