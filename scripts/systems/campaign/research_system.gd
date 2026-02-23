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
	if fs.research_progress >= data.research_time:
		_complete_research(faction_id, fs)

func _complete_research(faction_id: StringName, fs: FactionState) -> void:
	var research_id := fs.current_research_id
	fs.completed_research.append(research_id)
	fs.current_research_id = &""
	fs.research_progress = 0
	_invalidate_cache(faction_id)
	EventBus.research_completed.emit(faction_id, research_id)

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
	_effects_cache[faction_id] = combined
	return combined

func _invalidate_cache(faction_id: StringName) -> void:
	_effects_cache.erase(faction_id)

# ── AI Research ─────────────────────────────────────────────

func execute_ai_research(faction_id: StringName) -> void:
	var fs: FactionState = GameManager.state.faction_states.get(faction_id)
	if fs == null or fs.current_research_id != &"":
		return
	var available := get_available_research(faction_id)
	if available.is_empty():
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
	var best: ResearchData = available[0]
	var best_score := -999.0
	for data in available:
		var weight: float = float(weights.get(data.research_category, 1))
		var tier_factor := maxf(1.0, float(6 - data.tier))  # Lower tier = higher priority
		var score := weight * tier_factor
		if score > best_score:
			best_score = score
			best = data
	start_research(faction_id, best.id)
