class_name FactionState
extends Resource

@export var faction_data_id: StringName
@export var resources: Dictionary = {} # ResourceType -> int
@export var owned_regions: Array[StringName] = []
@export var owned_cities: Array[StringName] = []
@export var owned_shards: Array[StringName] = []
@export var shards_spent: int = 0 # Cumulative shards consumed (research, rituals, Pyramid) — Shard Ascension victory metric
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
@export var research_speed_accumulator: float = 0.0 # Fractional bonus progress from culture buildings

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

# Cinderguard unique: Border Vigilance (0-100, player-managed via events)
# High: aggressive patrol (+iron, +attack). Low: defensive posture (+defense, +pop)
@export var border_vigilance: int = 50

# Cinderguard unique: Scavenge stockpile (accumulated from dragon raids + scavenging)
# Spent to erect border fortresses at settlements
@export var scavenge_stockpile: int = 0
# Fortress level per settlement city_id (0=none, 1=watchtower, 2=palisade, 3=border fort)
@export var border_fortresses: Dictionary = {} # city_id -> int (0-3)
# Dragon raid tracking
@export var dragon_raid_cooldown: int = 0 # turns until next raid
@export var dragon_raids_survived: int = 0 # total survived, unlocks bonuses

# Forsaken unique: Espionage Network (grows from regions)
# Reveals enemy armies, enables sabotage
@export var espionage_network: int = 0

# Ivoryscar unique: Relic Power (grows from shard_wastes control)
# +commander item slots, stronger item effects
@export var relic_power: int = 0
# Ivoryscar unique: Black Pyramid restoration (0-100)
# Fueled by relic_power. Milestones at 25/50/75/100 grant escalating bonuses.
@export var pyramid_restoration: int = 0
@export var pyramid_restored: bool = false

# Sunblessed unique: Solar Faith (0-100)
# High: +morale/healing. Drops on losses, rises on wins
@export var solar_faith: int = 50

# Sunblessed unique: Wisdom (accumulated from aiding allies)
# Boosts research speed, diplomacy standing gains, and educator aura radius
@export var wisdom: int = 0

# Empire unique: Imperial Authority (0-100, starts at 60)
# High = tribute/diplomacy/cheaper recruits. Low = rebellion risk, loyalty decay
@export var imperial_authority: int = 60
# Empire Edict: active policy choice (0=none, 1=military, 2=economic, 3=cultural, 4=diplomatic)
@export var imperial_edict: int = 0
@export var imperial_edict_turns: int = 0

# Forsaken: espionage operation cooldowns & tracking
@export var espionage_sabotage_cooldown: int = 0
@export var espionage_caught_by: Array[StringName] = [] # factions that detected your spies
@export var espionage_op_target: StringName = &"" # target of the pending operations dilemma

# Tainted Jade: Taint Focus (0=balanced, 1=verdant growth, 2=venomous war, 3=creeping doom)
@export var taint_focus: int = 0

# Cinderguard: Player-directed forge shift queued from dilemmas
@export var forge_shift_queued: int = 0 # -10 to +10 per dilemma choice
# Cinderguard: Dragon raid target settlement (set when raid triggers)
@export var dragon_raid_target: StringName = &""

# Moonspear: Lunar ritual state
@export var lunar_ritual_extended: int = 0 # extra turns on current phase
@export var lunar_skip_cooldown: int = 0

# Thunderswarm: Storm ability cooldowns
@export var storm_ability_cooldown: int = 0
@export var storm_wall_city: StringName = &""
@export var storm_wall_turns: int = 0

# Ivoryscar: Relic expedition cooldown
@export var relic_expedition_cooldown: int = 0

# Sunblessed: Solar Faith proximity tracking
@export var solar_faith_proximity_turns: int = 0

# Gladehost: last season seen (detects season change for the Festival dilemma)
@export var last_season: int = -1

# Sunblessed: Golden Age dilemma cooldown
@export var golden_age_cooldown: int = 0

# Research queue: techs to auto-start (in order) when the current one finishes
@export var research_queue: Array[StringName] = []

# Shard crystal sockets in research techs
# research_id -> realm (int) of socketed crystal
@export var research_sockets: Dictionary = {}
