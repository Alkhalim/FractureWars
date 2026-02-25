class_name DiplomacyState
extends Resource

@export var standing: Dictionary = {} # "factionA:factionB" -> int (-100 to 100)
@export var standing_log: Dictionary = {} # "factionA:factionB" -> Array[{reason, delta, turn}]
@export var treaties: Dictionary = {} # treaty_id -> TreatyInstance
@export var cooldowns: Dictionary = {} # "factionA:factionB:action" -> turns remaining
@export var gifts_this_turn: Dictionary = {} # "factionA:factionB" -> true (reset each round)
