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
@export var requires_research: StringName = &"" # Research ID required to unlock this building
@export var exclusive_group: StringName = &"" # Doctrine fork: only ONE building per group can exist faction-wide
@export var settlement_only: bool = false # If true, can only be built in settlements (frontier structures)
@export var settlement_allowed: bool = false # Task 1b: this building's WHOLE chain (tier-1+tier-2) is one of a faction's 3-4 curated settlement trees -- also offered to settlements despite not being settlement_only. Never set on defensive/wall buildings or requires_capital chains.
@export var requires_region_resource: StringName = &"" # tier-2 Special deposit required in the city's region
@export var requires_region_landmark: StringName = &"" # tier-3 Landmark required in the city's region
