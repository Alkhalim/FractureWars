extends Node

const COMMANDER_UPKEEP := {Enums.ResourceType.GOLD: 5, Enums.ResourceType.FOOD: 3}

var skills: Dictionary = {} # id -> CommanderSkill
var items: Dictionary = {} # id -> CommanderItem
var traits_db: Dictionary = {} # id -> CommanderTrait

func _ready() -> void:
	_load_resources_from_dir("res://data/skills/", skills)
	_load_resources_from_dir("res://data/items/", items)
	_load_resources_from_dir("res://data/traits/", traits_db)

func _load_resources_from_dir(path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load(path + file_name)
			if res and "id" in res:
				target[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

# ── XP & Level-Up ────────────────────────────────────────────

func grant_battle_xp(commander: CommanderState, enemy_strength: int, won: bool, context: Array[StringName] = []) -> void:
	commander.level_up_context = context
	# Base XP: 15 for a win, 5 for a loss. Scaling capped so large battles
	# don't rocket through multiple levels at once.
	# 25% XP boost (minor skills removed — compensate with faster leveling)
	var xp_gain := int(((15 if won else 5) + mini(enemy_strength / 25, 40)) * 1.25)
	# Apply xp_gain_mult from traits
	var xp_mult := _get_trait_effect(commander, "xp_gain_mult")
	if xp_mult != 0.0:
		xp_gain = int(float(xp_gain) * (1.0 + xp_mult))
	commander.xp += xp_gain
	# Cap to at most 2 level-ups per battle
	var levels_gained := 0
	while levels_gained < 2:
		if not _try_level_up(commander):
			break
		levels_gained += 1

func grant_passive_xp(commander: CommanderState, context: Array[StringName] = [], amount: int = 2) -> void:
	commander.level_up_context = context
	var boosted := int(float(amount) * 1.25)
	var xp_mult := _get_trait_effect(commander, "xp_gain_mult")
	if xp_mult != 0.0:
		boosted = int(float(boosted) * (1.0 + xp_mult))
	commander.xp += boosted
	_check_level_up(commander)

func _try_level_up(commander: CommanderState) -> bool:
	if commander.level >= 10:
		return false
	var threshold: int = CommanderState.XP_THRESHOLDS[commander.level]
	if commander.xp >= threshold:
		commander.level += 1
		_apply_level_up(commander)
		return true
	return false

func _check_level_up(commander: CommanderState) -> void:
	_try_level_up(commander)

func _apply_level_up(commander: CommanderState) -> void:
	EventBus.commander_level_up.emit(commander)

func get_major_skill_choices(commander: CommanderState) -> Array[Dictionary]:
	var all_choices: Array[Dictionary] = []
	# Existing skills that can be leveled up
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		if level < 10:
			var skill: CommanderSkill = skills.get(skill_id)
			if skill:
				all_choices.append({"skill_id": skill_id, "is_levelup": true, "current_level": level})
	# New skills not yet learned
	for skill_id in skills:
		var skill: CommanderSkill = skills[skill_id]
		if not commander.skill_levels.has(skill_id):
			all_choices.append({"skill_id": skill_id, "is_levelup": false, "current_level": 0})

	var context := commander.level_up_context

	# Separate into contextual matches and general
	var contextual: Array[Dictionary] = []
	var general: Array[Dictionary] = []
	for choice in all_choices:
		var skill: CommanderSkill = skills.get(choice.skill_id)
		if skill and _matches_context(skill, context):
			contextual.append(choice)
		else:
			general.append(choice)

	contextual.shuffle()
	general.shuffle()

	var result: Array[Dictionary] = []
	# Slot 1: contextual pick (if available)
	if contextual.size() > 0:
		result.append(contextual.pop_front())
	# Fill remaining slots from general pool, then overflow contextual
	var remaining := general + contextual
	remaining.shuffle()
	while result.size() < 3 and remaining.size() > 0:
		result.append(remaining.pop_front())

	return result

func choose_major_skill(commander: CommanderState, skill_id: StringName) -> void:
	if commander.skill_levels.has(skill_id):
		commander.skill_levels[skill_id] = mini(commander.skill_levels[skill_id] + 1, 10)
	else:
		commander.skill_levels[skill_id] = 1

# ── Item Drops ────────────────────────────────────────────────

static func get_max_item_slots(commander: CommanderState) -> int:
	if commander.level >= 5:
		return 5
	elif commander.level >= 3:
		return 4
	return 3

func apply_item_drop(commander: CommanderState, defeated_faction: StringName) -> String:
	if commander.is_elderbeast:
		return ""
	const PITY_THRESHOLD := 4
	var base_chance := 0.3
	if commander.items.size() == 0:
		base_chance = 0.6
	elif commander.items.size() == 1:
		base_chance = 0.4
	if randf() > base_chance:
		commander.battles_won_no_drop += 1
		if commander.battles_won_no_drop < PITY_THRESHOLD:
			return ""
		# Pity triggered — fall through to guaranteed drop
	commander.battles_won_no_drop = 0
	var possible_items := _get_items_for_faction(defeated_faction)
	if possible_items.is_empty():
		return ""
	var item := _weighted_random_item(possible_items)
	if item == null:
		return ""
	var max_slots := get_max_item_slots(commander)
	if commander.items.size() < max_slots:
		commander.items.append(item.id)
		return item.display_name
	else:
		# Overflow to faction storage
		var fs: FactionState = GameManager.state.faction_states.get(commander.faction_id)
		if fs:
			fs.item_storage.append(item.id)
		EventBus.commander_item_full.emit(commander, item)
		return item.display_name

func _get_items_for_faction(faction_id: StringName) -> Array[CommanderItem]:
	var result: Array[CommanderItem] = []
	for item_id in items:
		var item: CommanderItem = items[item_id]
		if item.source_factions.is_empty() or item.source_factions.has(faction_id):
			result.append(item)
	return result

func _weighted_random_item(possible: Array[CommanderItem]) -> CommanderItem:
	if possible.is_empty():
		return null
	var weights: Array[float] = []
	for item in possible:
		match item.rarity:
			&"common": weights.append(60.0)
			&"rare": weights.append(30.0)
			&"legendary": weights.append(10.0)
			_: weights.append(60.0)
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	var cumulative := 0.0
	for i in possible.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return possible[i]
	return possible[possible.size() - 1]

# ── Bonus Calculations ────────────────────────────────────────

func get_commander_army_bonuses(commander: CommanderState) -> Dictionary:
	var bonuses := {
		"attack_bonus": 0,
		"defense_bonus": 0,
		"speed_bonus": 0,
		"movement_bonus": 0.0,
		"heal_per_turn": 0,
	}
	if commander == null:
		return bonuses
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		var effects := _get_effects_for_id(skill_id)
		_accumulate_army_bonuses(bonuses, effects, level)
	for trait_id in commander.traits:
		var trait_def: CommanderTrait = traits_db.get(trait_id)
		if trait_def:
			_accumulate_army_bonuses(bonuses, trait_def.effects, 1)
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		_accumulate_army_bonuses(bonuses, effects, 1)
	for follower_id in commander.followers:
		var follower: FollowerData = DataManager.get_follower(follower_id)
		if follower:
			_accumulate_army_bonuses(bonuses, follower.bonus_effect, 1)
			_accumulate_army_bonuses(bonuses, follower.malus_effect, 1)
	return bonuses

func _accumulate_army_bonuses(bonuses: Dictionary, effects: Dictionary, level: int = 1) -> void:
	if effects.has("army_attack_bonus"):
		bonuses.attack_bonus += effects.army_attack_bonus * level
	if effects.has("army_defense_bonus"):
		bonuses.defense_bonus += effects.army_defense_bonus * level
	if effects.has("army_speed_bonus"):
		bonuses.speed_bonus += effects.army_speed_bonus * level
	if effects.has("army_movement_bonus"):
		bonuses.movement_bonus += effects.army_movement_bonus * level
	if effects.has("heal_per_turn"):
		bonuses.heal_per_turn += effects.heal_per_turn * level
	# Behavioral modifiers (passed through to battle simulator)
	for bkey in ["charge_damage_mult", "retreat_morale_threshold", "captive_chance_mod",
				  "morale_recovery_mult", "ambush_attack_bonus", "unit_morale_bonus",
				  "upkeep_mult", "enemy_army_morale_penalty"]:
		if effects.has(bkey):
			bonuses[bkey] = bonuses.get(bkey, 0) + effects[bkey] * level
	# Tag-specific bonuses (e.g. cavalry_attack_bonus, vs_ranged_defense_bonus, terrain_forest_attack_bonus)
	for key in effects:
		if key.ends_with("_attack_bonus") or key.ends_with("_defense_bonus") or key.ends_with("_speed_bonus"):
			if not key.begins_with("army_"):
				bonuses[key] = bonuses.get(key, 0) + effects[key] * level

func get_commander_city_effects(commander: CommanderState, is_friendly: bool) -> Dictionary:
	var effects_total := {}
	if commander == null:
		return effects_total
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		var effects := _get_effects_for_id(skill_id)
		_accumulate_city_effects(effects_total, effects, is_friendly, level)
	for trait_id in commander.traits:
		var trait_def: CommanderTrait = traits_db.get(trait_id)
		if trait_def:
			_accumulate_city_effects(effects_total, trait_def.effects, is_friendly, 1)
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		_accumulate_city_effects(effects_total, effects, is_friendly, 1)
	for follower_id in commander.followers:
		var follower: FollowerData = DataManager.get_follower(follower_id)
		if follower:
			_accumulate_city_effects(effects_total, follower.bonus_effect, is_friendly, 1)
			_accumulate_city_effects(effects_total, follower.malus_effect, is_friendly, 1)
	return effects_total

func _accumulate_city_effects(total: Dictionary, effects: Dictionary, is_friendly: bool, level: int = 1) -> void:
	if is_friendly:
		for key in ["city_gold_bonus", "city_growth_bonus", "city_defense_bonus", "recruit_speed_bonus"]:
			if effects.has(key):
				total[key] = total.get(key, 0) + effects[key] * level
	else:
		for key in ["enemy_city_growth_penalty", "enemy_army_morale_penalty"]:
			if effects.has(key):
				total[key] = total.get(key, 0) + effects[key] * level

func _get_effects_for_id(skill_id: StringName) -> Dictionary:
	if skills.has(skill_id):
		return skills[skill_id].effects
	return {}

func _get_item_effects(item_id: StringName) -> Dictionary:
	if items.has(item_id):
		return items[item_id].effects
	return {}

func get_scouting_bonus(commander: CommanderState) -> int:
	var bonus := 0
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		var effects := _get_effects_for_id(skill_id)
		if effects.has("scouting_bonus"):
			bonus += effects.scouting_bonus * level
	for trait_id in commander.traits:
		var trait_def: CommanderTrait = traits_db.get(trait_id)
		if trait_def and trait_def.effects.has("scouting_bonus"):
			bonus += trait_def.effects.scouting_bonus
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		if effects.has("scouting_bonus"):
			bonus += effects.scouting_bonus
	for follower_id in commander.followers:
		var follower: FollowerData = DataManager.get_follower(follower_id)
		if follower:
			if follower.bonus_effect.has("scouting_bonus"):
				bonus += follower.bonus_effect.scouting_bonus
			if follower.malus_effect.has("scouting_bonus"):
				bonus += follower.malus_effect.scouting_bonus
	return bonus

# ── Trait System ─────────────────────────────────────────────

func evaluate_traits(commander: CommanderState, context: Array[StringName]) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []

	# --- Acquisition: check all traits not yet owned ---
	for trait_id in traits_db:
		var trait_def: CommanderTrait = traits_db[trait_id]
		if commander.traits.has(trait_id):
			continue
		if trait_def.acquire_context.is_empty():
			continue
		# Check exclusion
		var excluded := false
		for ex in trait_def.excludes:
			if commander.traits.has(ex):
				excluded = true
				break
		if excluded:
			continue
		# Count matching context tags
		var matches := 0
		for tag in trait_def.acquire_context:
			if context.has(tag):
				matches += 1
		if matches > 0:
			var key := "gain_" + str(trait_id)
			commander.trait_progress[key] = commander.trait_progress.get(key, 0) + matches
			if commander.trait_progress[key] >= trait_def.acquire_threshold:
				commander.traits.append(trait_id)
				commander.trait_progress.erase(key)
				# Remove excluded traits
				for ex in trait_def.excludes:
					if commander.traits.has(ex):
						commander.traits.erase(ex)
						changes.append({"action": "lost", "trait_id": ex})
				changes.append({"action": "gained", "trait_id": trait_id})

	# --- Loss: check all owned traits for countering context ---
	for trait_id in commander.traits.duplicate():
		var trait_def: CommanderTrait = traits_db.get(trait_id)
		if trait_def == null or trait_def.lose_context.is_empty():
			continue
		var matches := 0
		for tag in trait_def.lose_context:
			if context.has(tag):
				matches += 1
		if matches > 0:
			var key := "lose_" + str(trait_id)
			commander.trait_progress[key] = commander.trait_progress.get(key, 0) + matches
			if commander.trait_progress[key] >= trait_def.lose_threshold:
				commander.traits.erase(trait_id)
				commander.trait_progress.erase(key)
				changes.append({"action": "lost", "trait_id": trait_id})

	return changes

func assign_starting_traits(commander: CommanderState) -> void:
	var positive_pool: Array[CommanderTrait] = []
	var negative_pool: Array[CommanderTrait] = []
	for trait_id in traits_db:
		var t: CommanderTrait = traits_db[trait_id]
		if t.is_positive:
			positive_pool.append(t)
		else:
			negative_pool.append(t)
	positive_pool.shuffle()
	negative_pool.shuffle()

	# Pick 3 traits: guarantee at least 1 positive
	# ~65:35 ratio -> 2 positive + 1 negative is the default
	var picked: Array[StringName] = []
	# First: 1 guaranteed positive
	var first := _pick_non_excluded(positive_pool, picked)
	if not first.is_empty():
		picked.append(first)
	# Second: ~65% positive, 35% negative
	if randf() < 0.65 and positive_pool.size() > 0:
		var second := _pick_non_excluded(positive_pool, picked)
		if not second.is_empty():
			picked.append(second)
	elif negative_pool.size() > 0:
		var second := _pick_non_excluded(negative_pool, picked)
		if not second.is_empty():
			picked.append(second)
	else:
		var second := _pick_non_excluded(positive_pool, picked)
		if not second.is_empty():
			picked.append(second)
	# Third: fill remaining ratio
	if picked.size() < 3:
		if randf() < 0.35 and negative_pool.size() > 0:
			var third := _pick_non_excluded(negative_pool, picked)
			if not third.is_empty():
				picked.append(third)
		else:
			var third := _pick_non_excluded(positive_pool, picked)
			if not third.is_empty():
				picked.append(third)
	# Fallback: if still under 3, fill from whichever pool has remaining
	while picked.size() < 3:
		var any := _pick_non_excluded(positive_pool, picked)
		if any.is_empty():
			any = _pick_non_excluded(negative_pool, picked)
		if any.is_empty():
			break
		picked.append(any)

	commander.traits = picked

func _pick_non_excluded(pool: Array[CommanderTrait], already_picked: Array[StringName]) -> StringName:
	for t in pool:
		if already_picked.has(t.id):
			continue
		var excluded := false
		for ex in t.excludes:
			if already_picked.has(ex):
				excluded = true
				break
		if not excluded:
			pool.erase(t)
			return t.id
	return &""

func _get_trait_effect(commander: CommanderState, effect_key: String) -> float:
	var total := 0.0
	for trait_id in commander.traits:
		var trait_def: CommanderTrait = traits_db.get(trait_id)
		if trait_def and trait_def.effects.has(effect_key):
			total += float(trait_def.effects[effect_key])
	return total

# ── Context Helpers ───────────────────────────────────────────

func _matches_context(skill: CommanderSkill, context: Array[StringName]) -> bool:
	for tag in skill.context_tags:
		if context.has(tag):
			return true
	return false

# ── AI Skill Selection ────────────────────────────────────────

static func get_max_follower_slots(commander: CommanderState) -> int:
	if commander.level >= 5:
		return 2
	return 1

func ai_auto_pick_major_skill(commander: CommanderState) -> void:
	var choices := get_major_skill_choices(commander)
	if choices.size() > 0:
		var choice: Dictionary = choices[0]
		choose_major_skill(commander, choice.skill_id)
