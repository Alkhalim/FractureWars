class_name BuildingData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var faction_id: StringName = &"" # empty = available to all factions
@export var category: StringName # "economic", "military", "defensive", "cultural"
@export var build_cost: Dictionary = {} # ResourceType -> amount
@export var build_time: int = 1 # turns
@export var income_bonus: Dictionary = {} # ResourceType -> amount per turn
@export var population_growth_bonus: int = 0
@export var defense_bonus: int = 0
@export var recruit_speed_bonus: int = 0 # reduces recruit time
@export var unlocks_units: Array[StringName] = [] # unit_data_ids this building allows recruiting
@export var required_capital_level: int = 1
@export var required_terrain: int = -1 # Enums.TerrainType value, -1 = no terrain requirement
@export var class_loyalty_bonus: Dictionary = {} # class_name -> int bonus per turn
@export var upkeep_cost: Dictionary = {} # ResourceType -> amount per turn
@export var upgrades_from: StringName = &"" # Building ID this upgrades from (empty = base building)
@export var requires_capital: bool = false # If true, can only be built in the faction's capital city
@export var special_effects: Dictionary = {} # Special gameplay effects (e.g. region_population_growth_bonus, army_movement_bonus, recruit_cost_discount_pct, etc.)
