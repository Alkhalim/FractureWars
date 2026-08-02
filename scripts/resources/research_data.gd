class_name ResearchData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var tech_cost: int = 50 # TECHNOLOGY lump sum
@export var research_time: int = 3 # turns
@export var prerequisites: Array[StringName] = []
@export var effects: Dictionary = {} # "unit_attack_bonus" -> 1, "income_gold_pct" -> 10, etc.
@export var shard_bonuses: Dictionary = {} # Realm int -> bonus effects Dictionary
@export var tier: int = 1
@export var research_category: StringName = &"military" # military, economy, arcane, logistics
@export var faction_id: StringName = &"" # empty = universal
@export var tree_angle: float = 0.0       # Angle in degrees for radial placement (0-360)
@export var tree_branch: StringName = &""  # Branch name for grouping
@export var unlocks_units: Array[StringName] = [] # Unit IDs unlocked globally when researched
@export var socket_realm: int = -1 # Realm of crystal that fits this socket (-1 = no socket)
@export var socket_bonus: Dictionary = {} # Bonus effects when a crystal is socketed
@export var requires_bounty_types: Array[StringName] = [] # Any-of bounty-type gate, checked when research STARTS only (never pauses running research). Empty = no gate.
