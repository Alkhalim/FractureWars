class_name RegionData
extends Resource

@export var id: StringName
@export var display_name: String
@export var terrain: Enums.TerrainType
@export var realm_influence: Enums.Realm
@export var realm_influence_strength: float = 1.0
@export var base_income: Dictionary = {} # ResourceType -> amount per turn
@export var has_city_slot: bool = true
@export var max_armies: int = 3
@export var strategic_value: int = 1
