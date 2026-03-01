class_name UnitData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var faction_id: StringName

# Combat stats
@export var max_hp: int = 100
@export var attack: int = 10
@export var melee_defense: int = 5
@export var projectile_defense: int = 3
@export var magic_defense: int = 2
@export var speed: int = 5
@export var attack_range: int = 1 # 1 = melee, 2+ = ranged
@export var squad_size: int = 1
@export var hp_per_soldier: int = 0 # 0 = use max_hp directly (legacy/single entity)

# Campaign stats
@export var movement_points: float = 2.0
@export var upkeep_cost: Dictionary = {} # ResourceType -> amount
@export var recruit_cost: Dictionary = {} # ResourceType -> amount
@export var recruit_time: int = 1
@export var population_cost: int = -1 # -1 = use squad_size

# Battle modifiers
@export var terrain_bonuses: Dictionary = {} # TerrainType -> modifier
@export var realm_bonuses: Dictionary = {} # Realm -> modifier
@export var tags: Array[String] = [] # "infantry", "cavalry", "construct", "mage"

# Battle V2 fields
@export var base_morale: int = 50
@export var tiles_per_entity: int = 1   # 1=infantry, 2=cavalry, 4-6=siege, 6-16=monster
@export var captive_chance: float = 0.3
@export var morale_aura: int = 0         # +N boosts friendly morale; -N scares enemies
@export var fear_radius: int = 0         # Range of morale_aura in tiles (0=no aura)
@export var healing_aura: float = 0.0    # HP per tick healed to nearby allies (uses fear_radius)
@export var armor_aura: int = 0          # Defense bonus to nearby allies (uses fear_radius)

# VS bonuses — extra attack/defense against specific tags
@export var vs_attack_bonuses: Dictionary = {}  # tag -> int bonus (e.g. {"cavalry": 3})
@export var vs_defense_bonuses: Dictionary = {} # tag -> int bonus (e.g. {"ranged": 2})

# Targeted fear — extra morale aura against specific unit tags
@export var fear_vs_tags: Array[String] = []  # Extra fear effect against specific tags
@export var fear_vs_bonus: int = 0             # Additional morale_aura when targeting matching units

func get_avg_defense() -> int:
	return int((melee_defense + projectile_defense + magic_defense) / 3.0)
