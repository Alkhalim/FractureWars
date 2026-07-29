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
@export var hex_map_data: Dictionary = {} # Serialized hex map for save/load
@export var turn_manager_state: Dictionary = {} # Serialized TurnManager AI state
@export var game_over: bool = false
@export var victory_type: StringName = &""
@export var game_mode: int = Enums.GameMode.SANDBOX
@export var quickmatch_won: bool = false
@export var tutorial_enabled: bool = true
@export var tutorial_step: int = 0
@export var encountered_factions: Dictionary = {} # faction_id -> true (factions the player has seen)

var hex_map: HexMapData # Runtime hex map state (not serialized)

func generate_id() -> StringName:
	next_id += 1
	return StringName(str(next_id))

func get_region_owner(region_id: StringName) -> StringName:
	if hex_map:
		return hex_map.get_region_owner(region_id)
	return &""

func serialize_hex_map() -> void:
	if hex_map == null:
		hex_map_data = {}
		return
	var data := {}
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var key := "%d,%d" % [coord.x, coord.y]
		data[key] = {
			"terrain": tile.terrain,
			"region_id": str(tile.region_id),
			"road_level": tile.road_level,
			"realm_influence": tile.realm_influence,
			"development_level": tile.development_level,
			"owner_faction": str(tile.owner_faction),
			"bounty_id": str(tile.bounty_id),
		}
	hex_map_data = data

func deserialize_hex_map() -> void:
	hex_map = HexMapData.new()
	for key in hex_map_data:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var coord := Vector2i(int(parts[0]), int(parts[1]))
		var tile_data: Dictionary = hex_map_data[key]
		var tile := HexMapData.TileState.new()
		tile.terrain = tile_data.get("terrain", 0)
		tile.region_id = StringName(tile_data.get("region_id", ""))
		tile.road_level = tile_data.get("road_level", 0)
		tile.realm_influence = tile_data.get("realm_influence", 0)
		tile.development_level = tile_data.get("development_level", 0)
		tile.owner_faction = StringName(tile_data.get("owner_faction", ""))
		tile.bounty_id = StringName(tile_data.get("bounty_id", ""))
		hex_map.tiles[coord] = tile
	hex_map_data = {} # Clear serialized data to save memory
