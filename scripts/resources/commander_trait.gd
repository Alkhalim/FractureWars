class_name CommanderTrait
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String                    # Flavor text
@export var is_positive: bool = true               # true = beneficial, false = detrimental
@export var effects: Dictionary = {}               # Effect keys (army_attack_bonus, charge_damage_mult, etc.)
@export var excludes: Array[StringName] = []        # Mutually exclusive trait IDs
@export var acquire_context: Array[StringName] = [] # Context tags that can trigger acquisition
@export var acquire_threshold: int = 5             # How many matching contexts needed to gain this trait
@export var lose_context: Array[StringName] = []    # Context tags that work toward removing this trait
@export var lose_threshold: int = 10               # How many countering contexts needed to lose it
