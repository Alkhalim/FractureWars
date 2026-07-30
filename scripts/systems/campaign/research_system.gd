class_name ResearchSystem
extends RefCounted

# Cache for research effects per faction
var _effects_cache: Dictionary = {} # faction_id -> Dictionary

func get_available_research(faction_id: StringName) -> Array[ResearchData]:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return []
	var result: Array[ResearchData] = []
	for research_id in DataManager.research:
		var data: ResearchData = DataManager.research[research_id]
		# Skip if already completed
		if fs.completed_research.has(research_id):
			continue
		# Skip if currently researching
		if fs.current_research_id == research_id:
			continue
		# Skip faction-specific research for other factions (minor factions use parent's tree)
		var parent_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(fs.faction_data_id, fs.faction_data_id)
		if data.faction_id != &"" and data.faction_id != fs.faction_data_id and data.faction_id != parent_id:
			continue
		# Check prerequisites
		var prereqs_met := true
		for prereq in data.prerequisites:
			if not fs.completed_research.has(prereq):
				prereqs_met = false
				break
		if prereqs_met:
			result.append(data)
	return result

func start_research(faction_id: StringName, research_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return false
	var data: ResearchData = DataManager.research.get(research_id)
	if data == null:
		return false
	# Already researching this one
	if fs.current_research_id == research_id:
		return false
	# Check tech cost
	var tech_available: int = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)
	if tech_available < data.tech_cost:
		return false
	# Deduct tech cost
	fs.resources[Enums.ResourceType.TECHNOLOGY] = tech_available - data.tech_cost
	# Pause current research (save progress)
	if fs.current_research_id != &"" and fs.research_progress > 0:
		fs.paused_research_progress[fs.current_research_id] = fs.research_progress
	# Switch to new research — restore saved progress if any
	fs.current_research_id = research_id
	fs.research_progress = fs.paused_research_progress.get(research_id, 0)
	fs.paused_research_progress.erase(research_id)
	EventBus.research_started.emit(faction_id, research_id)
	return true

func invest_shard(faction_id: StringName, shard_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.current_research_id == &"":
		return false
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null or shard.claimed_by != faction_id:
		return false
	# Record the realm of the invested shard
	var research_id := fs.current_research_id
	if not fs.research_invested_shards.has(research_id):
		fs.research_invested_shards[research_id] = []
	fs.research_invested_shards[research_id].append(shard.realm)
	# Remove shard from faction ownership
	fs.owned_shards.erase(shard_id)
	fs.shards_spent += 1
	# Remove from active shards (consumed)
	GameManager.state.active_shards.erase(shard_id)
	return true

func process_research(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.current_research_id == &"":
		return
	var data: ResearchData = DataManager.research.get(fs.current_research_id)
	if data == null:
		fs.current_research_id = &""
		return
	fs.research_progress += 1
	# Culture building research speed bonus: accumulate fractional progress
	var bonus := _get_faction_research_speed_bonus(faction_id)
	# Shardglass / Voidglass Rift: +% progress on arcane techs (fractional
	# accumulation, folded into the same accumulator/drain as the culture
	# bonus above so it never gets stuck)
	if data.research_category == &"arcane":
		var arcane_bonus := SpecialResourceSystem.modifier_strength(faction_id, &"shardglass")
		if LandmarkSystem.has_landmark(faction_id, &"voidglass_rift"):
			arcane_bonus += 0.10
		if arcane_bonus > 0.0:
			bonus += arcane_bonus
	if bonus > 0.0:
		fs.research_speed_accumulator += bonus
		while fs.research_speed_accumulator >= 1.0:
			fs.research_progress += 1
			fs.research_speed_accumulator -= 1.0
	if fs.research_progress >= data.research_time:
		_complete_research(faction_id, fs)

func _complete_research(faction_id: StringName, fs: FactionState) -> void:
	var research_id := fs.current_research_id
	fs.completed_research.append(research_id)
	fs.current_research_id = &""
	fs.research_progress = 0
	_invalidate_cache(faction_id)
	EventBus.research_completed.emit(faction_id, research_id)
	_advance_queue(faction_id, fs)

## Auto-advance: start the first queued tech whose prerequisites are met and
## whose cost is affordable. Unmet entries stay queued for the next completion.
func _advance_queue(faction_id: StringName, fs: FactionState) -> void:
	var i := 0
	while i < fs.research_queue.size():
		var next_id: StringName = fs.research_queue[i]
		var nd: ResearchData = DataManager.research.get(next_id)
		if nd == null or fs.completed_research.has(next_id):
			fs.research_queue.remove_at(i)  # stale entry
			continue
		var prereqs_met := true
		for prereq in nd.prerequisites:
			if not fs.completed_research.has(prereq):
				prereqs_met = false
				break
		if prereqs_met and start_research(faction_id, next_id):
			fs.research_queue.remove_at(i)
			return
		i += 1

func queue_research(faction_id: StringName, research_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return false
	var data: ResearchData = DataManager.research.get(research_id)
	if data == null or fs.completed_research.has(research_id):
		return false
	if fs.current_research_id == research_id or fs.research_queue.has(research_id):
		return false
	if fs.research_queue.size() >= 5:
		return false
	fs.research_queue.append(research_id)
	# Nothing active? Try to start right away.
	if fs.current_research_id == &"":
		_advance_queue(faction_id, fs)
	return true

func unqueue_research(faction_id: StringName, research_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs:
		fs.research_queue.erase(research_id)

func cancel_research(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.current_research_id == &"":
		return
	# Clear invested shards for this research (they're already consumed)
	fs.research_invested_shards.erase(fs.current_research_id)
	fs.current_research_id = &""
	fs.research_progress = 0

func get_research_effects(faction_id: StringName) -> Dictionary:
	if _effects_cache.has(faction_id):
		return _effects_cache[faction_id]
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return {}
	var combined: Dictionary = {}
	for research_id in fs.completed_research:
		var data: ResearchData = DataManager.research.get(research_id)
		if data == null:
			continue
		# Base effects
		for key in data.effects:
			combined[key] = combined.get(key, 0) + data.effects[key]
		# Shard bonuses
		var invested_realms: Array = fs.research_invested_shards.get(research_id, [])
		for realm in invested_realms:
			if data.shard_bonuses.has(realm):
				var bonus: Dictionary = data.shard_bonuses[realm]
				for key in bonus:
					combined[key] = combined.get(key, 0) + bonus[key]
		# Socket bonuses (removable crystal embedded in completed tech)
		# Leyline Well (Landmark): socketed crystal bonuses count +50% stronger.
		if fs.research_sockets.has(research_id) and not data.socket_bonus.is_empty():
			var socket_mult := 1.5 if LandmarkSystem.has_landmark(faction_id, &"leyline_well") else 1.0
			for key in data.socket_bonus:
				combined[key] = combined.get(key, 0) + int(round(data.socket_bonus[key] * socket_mult))
	_effects_cache[faction_id] = combined
	return combined

func _get_faction_research_speed_bonus(faction_id: StringName) -> float:
	var total := 0.0
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != faction_id:
			continue
		for building_id in city.buildings:
			var bld: BuildingData = DataManager.get_building(building_id)
			if bld and bld.special_effects.has("research_speed_bonus"):
				total += float(bld.special_effects["research_speed_bonus"])
	# Research: research_speed_bonus from completed research (fractional accumulation)
	var r_eff := get_research_effects(faction_id)
	total += float(r_eff.get("research_speed_bonus", 0)) / 100.0
	# Sunblessed Wisdom: scholars accelerate research — up to +50% at 200 wisdom
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	if parent_fid == &"sunblessed":
		var fs: FactionState = GameManager.state.faction_states.get(faction_id)
		if fs and fs.wisdom > 0:
			total += float(fs.wisdom) / 400.0
	return total

func _invalidate_cache(faction_id: StringName) -> void:
	_effects_cache.erase(faction_id)

# ── Shard Crystal Sockets ──────────────────────────────────

## Category -> required crystal realm mapping
const CATEGORY_SOCKET_REALM := {
	&"military": Enums.Realm.ELEMENTAL,
	&"economy": Enums.Realm.MORTAL,
	&"arcane": Enums.Realm.VOID,
	&"logistics": Enums.Realm.NATURE,
}

func socket_shard(faction_id: StringName, research_id: StringName, shard_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return false
	var data: ResearchData = DataManager.research.get(research_id)
	if data == null or data.socket_realm < 0:
		return false
	# Must be completed research
	if not fs.completed_research.has(research_id):
		return false
	# Already has a crystal socketed
	if fs.research_sockets.has(research_id):
		return false
	# Check shard exists and is owned
	if not fs.owned_shards.has(shard_id):
		return false
	var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
	if shard == null:
		return false
	# Check realm matches
	if shard.realm != data.socket_realm:
		return false
	# Socket the crystal — reversible banking, not consumption: unsocket_shard()
	# below hands back an equivalent shard, so this does NOT increment shards_spent
	fs.owned_shards.erase(shard_id)
	GameManager.state.active_shards.erase(shard_id)
	fs.research_sockets[research_id] = int(shard.realm)
	_invalidate_cache(faction_id)
	return true

func unsocket_shard(faction_id: StringName, research_id: StringName) -> bool:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or not fs.research_sockets.has(research_id):
		return false
	var realm: int = fs.research_sockets[research_id]
	fs.research_sockets.erase(research_id)
	# Create a new shard and place it at the faction's capital
	var new_shard := ShardInstance.new()
	new_shard.shard_id = StringName("socket_return_%s_%d" % [research_id, GameManager.state.current_turn])
	new_shard.realm = realm as Enums.Realm
	new_shard.power_level = 1
	new_shard.turns_remaining = -1
	# Find capital hex position
	var capital_pos := Vector2i.ZERO
	if not fs.owned_cities.is_empty():
		var city: CityState = GameManager.state.cities.get(fs.owned_cities[0])
		if city:
			capital_pos = city.hex_pos
	new_shard.hex_pos = capital_pos
	new_shard.claimed_by = faction_id
	GameManager.state.active_shards[new_shard.shard_id] = new_shard
	fs.owned_shards.append(new_shard.shard_id)
	_invalidate_cache(faction_id)
	return true

func get_socketable_shards(faction_id: StringName, research_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null:
		return result
	var data: ResearchData = DataManager.research.get(research_id)
	if data == null or data.socket_realm < 0:
		return result
	for shard_id in fs.owned_shards:
		var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
		if shard and shard.realm == data.socket_realm:
			result.append(shard_id)
	return result

# ── AI Shard Socketing ─────────────────────────────────────

func execute_ai_socketing(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.owned_shards.is_empty():
		return
	# Try to socket crystals into completed techs with empty sockets
	for research_id in fs.completed_research:
		if fs.research_sockets.has(research_id):
			continue
		var data: ResearchData = DataManager.research.get(research_id)
		if data == null or data.socket_realm < 0 or data.socket_bonus.is_empty():
			continue
		# Find a matching shard
		for shard_id in fs.owned_shards:
			var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
			if shard and shard.realm == data.socket_realm:
				socket_shard(faction_id, research_id, shard_id)
				break
		if fs.owned_shards.is_empty():
			break

# ── AI Research ─────────────────────────────────────────────

func execute_ai_research(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.current_research_id != &"":
		return
	var available := get_available_research(faction_id)
	if available.is_empty():
		return

	# Filter by affordability
	var tech_available: int = fs.resources.get(Enums.ResourceType.TECHNOLOGY, 0)
	var affordable: Array[ResearchData] = []
	for data in available:
		if data.tech_cost <= tech_available:
			affordable.append(data)
	if affordable.is_empty():
		return

	# Faction-specific category preferences (higher = more preferred)
	var category_weights := {
		&"empire": {&"military": 2, &"economy": 2, &"arcane": 1, &"logistics": 2},
		&"gladehost": {&"military": 1, &"economy": 2, &"arcane": 2, &"logistics": 2},
		&"skulloath": {&"military": 3, &"economy": 1, &"arcane": 1, &"logistics": 1},
		&"moonspear": {&"military": 1, &"economy": 2, &"arcane": 3, &"logistics": 1},
		&"thunderswarm": {&"military": 3, &"economy": 1, &"arcane": 1, &"logistics": 2},
		&"tainted_jade": {&"military": 2, &"economy": 2, &"arcane": 3, &"logistics": 1},
		&"cinderguard": {&"military": 2, &"economy": 3, &"arcane": 1, &"logistics": 1},
		&"forsaken": {&"military": 2, &"economy": 1, &"arcane": 3, &"logistics": 1},
		&"ivoryscar": {&"military": 1, &"economy": 2, &"arcane": 3, &"logistics": 1},
		&"shardhorde": {&"military": 3, &"economy": 1, &"arcane": 2, &"logistics": 1},
		&"sunblessed": {&"military": 2, &"economy": 1, &"arcane": 2, &"logistics": 2},
	}
	# Minor factions use parent faction's weights
	var parent_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	var weights: Dictionary = category_weights.get(parent_id, {&"military": 2, &"economy": 2, &"arcane": 1, &"logistics": 1})

	# Score each research by preference weight * tier (lower tier = faster to complete)
	var best: ResearchData = affordable[0]
	var best_score := -999.0
	for data in affordable:
		var weight: float = float(weights.get(data.research_category, 1))
		var tier_factor := maxf(1.0, float(6 - data.tier))  # Lower tier = higher priority
		var score := weight * tier_factor
		if score > best_score:
			best_score = score
			best = data
	start_research(faction_id, best.id)
