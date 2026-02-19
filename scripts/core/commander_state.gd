class_name CommanderState
extends Resource

@export var commander_id: StringName
@export var name: String
@export var faction_id: StringName
@export var level: int = 1
@export var xp: int = 0
@export var skill_levels: Dictionary = {} # skill_id -> int level (1-10)
@export var items: Array[StringName] = []
@export var followers: Array[StringName] = []  # follower_data_ids
@export var influence_radius: int = 3
@export var is_elderbeast: bool = false

var level_up_context: Array[StringName] = []

const XP_THRESHOLDS := [0, 50, 120, 220, 350, 520, 730, 1000, 1350, 1800]

# Backward-compat computed property
var skills: Array[StringName]:
	get:
		var result: Array[StringName] = []
		for sid in skill_levels:
			result.append(sid)
		return result
