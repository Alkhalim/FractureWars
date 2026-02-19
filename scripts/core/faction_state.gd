class_name FactionState
extends Resource

@export var faction_data_id: StringName
@export var resources: Dictionary = {} # ResourceType -> int
@export var owned_regions: Array[StringName] = []
@export var owned_cities: Array[StringName] = []
@export var owned_shards: Array[StringName] = []
@export var commander_pool: Array[CommanderState] = []
@export var item_storage: Array[StringName] = []
@export var follower_storage: Array[StringName] = []
@export var is_defeated: bool = false

# Research
@export var current_research_id: StringName = &""
@export var research_progress: int = 0
@export var completed_research: Array[StringName] = []
@export var research_invested_shards: Dictionary = {} # research_id -> Array of realm ints

# Policies (max 3 active, 1 per category)
@export var active_policies: Array[StringName] = []
@export var policy_cooldowns: Dictionary = {} # category (int) -> turns remaining

# Senate / Forsaken (Empire unique)
@export var forsaken_seats: int = 3
@export var forsaken_next_offer_turn: int = 5
@export var forsaken_crisis_stage: int = 0
@export var senate_dilemma_next_turn: int = 8

# Skulloath unique: Corruption duality (0-100)
# Low = traditional (food/loyalty bonus), High = demonic (military bonus, loyalty penalty)
@export var corruption: int = 20

# Tainted Jade unique: Taint Power (accumulated from destroying shards)
@export var taint_power: int = 0

# Gladehost unique: Harmony level (0-100)
# High harmony = strong seasonal bonuses, drops when over-building
@export var harmony: int = 75

# Shardhorde unique: Shard Resonance buffs (shard realm -> turns remaining)
@export var shard_resonance: Dictionary = {}
