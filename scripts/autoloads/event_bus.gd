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
# Emitted by BattleResolver when a player army meets an enemy and a UI is
# present, so the campaign scene can show its fight/auto/retreat dialog.
signal battle_player_prompt(attacker_army_id: StringName, defender_army_id: StringName, hex_pos: Vector2i)
# Emitted by BattleResolver after an auto-resolved battle. `report` is empty
# for AI-vs-AI battles, or a populated dict when the player was involved.
signal battle_auto_resolved(report: Dictionary)

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
signal building_demolished(city_id: StringName, building_id: StringName)
signal unit_recruited(city_id: StringName, unit_data_id: StringName, army_id: StringName)
signal siege_started(city_id: StringName, faction_id: StringName)
signal siege_broken(city_id: StringName)
signal city_joined(city_id: StringName, faction_id: StringName)
signal siege_choice_needed(city_id: StringName, faction_id: StringName) # Skulloath post-siege choice

# Commander signals
signal commander_level_up(commander: CommanderState)
signal commander_item_full(commander: CommanderState, item: CommanderItem)
signal commander_trait_changed(commander: CommanderState, action: String, trait_id: StringName)

# Random event signals
signal random_event_triggered(event_data: Dictionary)

# Elderbeast signals
signal elderbeast_moved(beast_id: StringName, from_hex: Vector2i, to_hex: Vector2i)
signal elderbeast_destroyed(beast_id: StringName, faction_id: StringName)

# Army retreat signal
signal army_retreated(army_id: StringName, from_hex: Vector2i, to_hex: Vector2i, losses: int)

# Revolt signals
signal revolt_triggered(city_id: StringName, faction_id: StringName)

# Bankruptcy: unpaid units desert when the treasury goes negative
signal units_deserted(faction_id: StringName, unit_names: Array, count: int)

# Diplomacy signals
signal diplomacy_action(action_type: int, faction_a: StringName, faction_b: StringName)
signal treaty_created(treaty_id: StringName, treaty_type: int, faction_a: StringName, faction_b: StringName)
signal treaty_expired(treaty_id: StringName)
signal standing_changed(faction_a: StringName, faction_b: StringName, new_standing: int)
signal trade_intercepted(interceptor_faction: StringName, treaty_id: StringName, gold_stolen: int)

# Research signals
signal research_started(faction_id: StringName, research_id: StringName)
signal research_completed(faction_id: StringName, research_id: StringName)

# Policy signals
signal policy_enacted(faction_id: StringName, policy_id: StringName)
signal policy_revoked(faction_id: StringName, policy_id: StringName)

# Senate / Forsaken signals
signal forsaken_offer(faction_id: StringName, offer: Dictionary)
signal senate_dilemma(faction_id: StringName, dilemma: Dictionary)

# Faction mechanic dilemma (Empire edicts, Tainted Jade focus, Moonspear rituals, etc.)
signal dilemma_triggered(faction_id: StringName, dilemma_type: StringName, dilemma_data: Dictionary)
signal dilemma_resolved(faction_id: StringName, dilemma_type: StringName, choice_effect: String)

# Victory / defeat signals
signal game_over(faction_id: StringName, victory_type: int, is_player: bool)
signal faction_defeated(faction_id: StringName)  # Non-player faction eliminated

# AI diplomacy offer to player
signal ai_diplomacy_offer(from_faction: StringName, offer_type: StringName, offer_data: Dictionary)

# UI signals
signal end_turn_pressed()
