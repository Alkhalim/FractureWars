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
@export var map_seed: int = 0 # Per-campaign map generation seed (Task 1B); 0 = legacy/default map
@export var hex_map_data: Dictionary = {} # Serialized hex map for save/load
@export var turn_manager_state: Dictionary = {} # Serialized TurnManager AI state
@export var game_over: bool = false
@export var victory_type: StringName = &""
@export var game_mode: int = Enums.GameMode.SANDBOX
@export var quickmatch_won: bool = false
@export var tutorial_enabled: bool = true
@export var tutorial_step: int = 0
@export var encountered_factions: Dictionary = {} # faction_id -> true (factions the player has seen)
@export var faction_intro_shown: bool = false # Show-once onboarding panel (Polish Pass 1, Task 1)
# Save-data schema version (unit-stat-rescale final review, structural fix
# replacing the old-save HP-backfill magnitude heuristic). Default 0 means
# "pre-rescale / predates this field" -- any save written before this field
# existed deserializes with the class default (Godot Resource loading uses
# the script default for any property absent from the serialized data), so
# 0 unambiguously means "needs backfill", no guessing from HP magnitudes.
# GameManager stamps every new/saved game to GameState.SAVE_SCHEMA_VERSION
# (new_game() and every save_game() write); load_game()'s backfill gates on
# `state.save_schema_version < SAVE_SCHEMA_VERSION` and sets it to current
# once backfill runs, so it fires exactly once per old save.
@export var save_schema_version: int = 0
const SAVE_SCHEMA_VERSION := 1 # bump when a future save-breaking change needs its own backfill

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
			"special_id": str(tile.special_id),
			"landmark_id": str(tile.landmark_id),
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
		tile.special_id = StringName(tile_data.get("special_id", ""))
		tile.landmark_id = StringName(tile_data.get("landmark_id", ""))
		hex_map.tiles[coord] = tile
	hex_map_data = {} # Clear serialized data to save memory
