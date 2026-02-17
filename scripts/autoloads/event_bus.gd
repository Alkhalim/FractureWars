extends Node

# Turn signals
signal turn_started(turn_number: int, faction_id: StringName)
signal turn_ended(turn_number: int, faction_id: StringName)
signal round_ended(turn_number: int)

# Region signals
signal region_selected(region_id: StringName)
signal region_deselected()
signal region_ownership_changed(region_id: StringName, old_owner: StringName, new_owner: StringName)

# Army signals
signal army_selected(army_id: StringName)
signal army_deselected()
signal army_moved(army_id: StringName, from_hex: Vector2i, to_hex: Vector2i)
signal army_destroyed(army_id: StringName, faction_id: StringName)

# Battle signals
signal battle_initiated(attacker_army_id: StringName, defender_army_id: StringName, hex_pos: Vector2i)
signal battle_resolved(winner_faction: StringName, hex_pos: Vector2i)

# Shard signals
signal shardfall_occurred(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm)
signal shard_claimed(shard_id: StringName, faction_id: StringName)
signal shard_expired(shard_id: StringName)

# Hex map signals
signal hex_tile_selected(coord: Vector2i)
signal hex_tile_deselected()

# City signals
signal city_captured(city_id: StringName, old_owner: StringName, new_owner: StringName)
signal building_completed(city_id: StringName, building_id: StringName)
signal unit_recruited(city_id: StringName, unit_data_id: StringName, army_id: StringName)
signal siege_started(city_id: StringName, faction_id: StringName)
signal siege_broken(city_id: StringName)

# Commander signals
signal commander_level_up(commander: CommanderState)
signal commander_item_full(commander: CommanderState, item: CommanderItem)

# Random event signals
signal random_event_triggered(event_data: Dictionary)

# Elderbeast signals
signal elderbeast_moved(beast_id: StringName, from_hex: Vector2i, to_hex: Vector2i)

# Army retreat signal
signal army_retreated(army_id: StringName, from_hex: Vector2i, to_hex: Vector2i, losses: int)

# Revolt signals
signal revolt_triggered(city_id: StringName, faction_id: StringName)

# UI signals
signal end_turn_pressed()
