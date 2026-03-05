class_name FactionData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var color: Color
@export var is_playable: bool = false
@export var starting_regions: Array[StringName] = []
@export var realm_affinity: Enums.Realm
@export var shard_preferences: Dictionary = {} # Realm -> weight float
@export var ai_personality: Dictionary = {} # aggression, expansion, shard_hunger
@export var gift_likes: Array[StringName] = []
@export var gift_dislikes: Array[StringName] = []
