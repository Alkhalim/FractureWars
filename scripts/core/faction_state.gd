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
@export var leader_bonuses: Dictionary = {} # e.g. {"army_attack": 5, "income_gold": 10}

# Research
@export var current_research_id: StringName = &""
@export var research_progress: int = 0
@export var completed_research: Array[StringName] = []
@export var research_invested_shards: Dictionary = {} # research_id -> Array of realm ints
@export var paused_research_progress: Dictionary = {} # research_id -> int (saved progress for paused techs)

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

# Moonspear unique: Lunar Phase (0-3, cycles every 4 turns)
# 0=New Moon (+atk), 1=Waxing (+move), 2=Full Moon (+def), 3=Waning (+heal)
@export var lunar_phase: int = 0

# Thunderswarm unique: Storm Fury (0-100, rises from battles)
# 50+: +10% atk. 80+: +20% atk, -5% def
@export var storm_fury: int = 0

# Cinderguard unique: Forge Heat (0-100, player-managed via buildings)
# High: cheaper iron builds + recruit speed. Low: +defense
@export var forge_heat: int = 50

# Forsaken unique: Espionage Network (grows from regions)
# Reveals enemy armies, enables sabotage
@export var espionage_network: int = 0

# Ivoryscar unique: Relic Power (grows from shard_wastes control)
# +commander item slots, stronger item effects
@export var relic_power: int = 0

# Sunblessed unique: Solar Faith (0-100)
# High: +morale/healing. Drops on losses, rises on wins
@export var solar_faith: int = 50
