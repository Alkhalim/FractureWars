class_name GameState
extends Resource

@export var current_turn: int = 1
@export var current_month: int = 0 # 0-9 index into calendar months
@export var current_year: int = 174 # Year S.F.
@export var player_faction_id: StringName = &"empire"
@export var faction_states: Dictionary = {} # faction_id -> FactionState
@export var armies: Dictionary = {} # army_id -> ArmyState
@export var active_shards: Dictionary = {} # shard_instance_id -> ShardInstance
@export var cities: Dictionary = {} # city_id -> CityState
@export var diplomacy: Dictionary = {} # "factionA:factionB" -> FactionRelation enum value
@export var diplomacy_state: DiplomacyState = DiplomacyState.new()
@export var elderbeasts: Dictionary = {} # beast_id -> ElderbeastState
@export var selected_army_id: StringName = &""
@export var next_id: int = 0

var hex_map: HexMapData # Runtime hex map state (not serialized)

func generate_id() -> StringName:
	next_id += 1
	return StringName(str(next_id))

func get_region_owner(region_id: StringName) -> StringName:
	if hex_map:
		return hex_map.get_region_owner(region_id)
	return &""
