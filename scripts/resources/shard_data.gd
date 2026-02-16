class_name ShardData
extends Resource

@export var id: StringName
@export var display_name: String
@export var realm: Enums.Realm
@export var power_level: int = 1 # 1-5
@export var effects: Dictionary = {} # bonus type -> value
@export var decay_turns: int = -1 # -1 = permanent, >0 = disappears after N turns
@export var corruption_radius: int = 0
@export var description: String
