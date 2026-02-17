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
