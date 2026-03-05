class_name ShardInstance
extends Resource

@export var shard_id: StringName
@export var realm: Enums.Realm
@export var power_level: int = 1
@export var hex_pos: Vector2i # Position on hex grid
@export var claimed_by: StringName = &"" # faction_id, empty if unclaimed
@export var turns_remaining: int = -1 # -1 = no decay
@export var guardian_army_id: StringName = &""

func get_region_id() -> StringName:
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(hex_pos)
		if tile:
			return tile.region_id
	return &""
