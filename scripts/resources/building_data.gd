class_name BuildingData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var category: StringName # "economic", "military", "defensive", "cultural"
@export var build_cost: Dictionary = {} # ResourceType -> amount
@export var build_time: int = 1 # turns
@export var income_bonus: Dictionary = {} # ResourceType -> amount per turn
@export var population_growth_bonus: int = 0
@export var defense_bonus: int = 0
@export var recruit_speed_bonus: int = 0 # reduces recruit time
@export var unlocks_units: Array[StringName] = [] # unit_data_ids this building allows recruiting
@export var required_capital_level: int = 1
@export var upgrades_from: StringName = &"" # Building ID this upgrades from (empty = base building)
