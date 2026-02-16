class_name UnitData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var faction_id: StringName

# Combat stats
@export var max_hp: int = 100
@export var attack: int = 10
@export var defense: int = 5
@export var speed: int = 5
@export var attack_range: int = 1 # 1 = melee, 2+ = ranged
@export var squad_size: int = 1
@export var hp_per_soldier: int = 0 # 0 = use max_hp directly (legacy/single entity)

# Campaign stats
@export var movement_points: float = 2.0
@export var upkeep_cost: Dictionary = {} # ResourceType -> amount
@export var recruit_cost: Dictionary = {} # ResourceType -> amount
@export var recruit_time: int = 1

# Battle modifiers
@export var terrain_bonuses: Dictionary = {} # TerrainType -> modifier
@export var realm_bonuses: Dictionary = {} # Realm -> modifier
@export var tags: Array[String] = [] # "infantry", "cavalry", "construct", "mage"
