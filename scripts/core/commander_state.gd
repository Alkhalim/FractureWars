class_name CommanderState
extends Resource

@export var commander_id: StringName
@export var name: String
@export var faction_id: StringName
@export var level: int = 1
@export var xp: int = 0
@export var skill_levels: Dictionary = {} # skill_id -> int level (1-10)
@export var traits: Array[StringName] = [] # Active trait IDs
@export var trait_progress: Dictionary = {} # "gain_X" / "lose_X" -> int tally
@export var items: Array[StringName] = []
@export var followers: Array[StringName] = []  # follower_data_ids
@export var battles_won_no_drop: int = 0
@export var influence_radius: int = 3
@export var is_elderbeast: bool = false
@export var portrait_path: String = ""

var level_up_context: Array[StringName] = []

const XP_THRESHOLDS := [0, 50, 120, 220, 350, 520, 730, 1000, 1350, 1800]

# Backward-compat computed property
var skills: Array[StringName]:
	get:
		var result: Array[StringName] = []
		for sid in skill_levels:
			result.append(sid)
		return result
