extends Node

const COMMANDER_UPKEEP := {Enums.ResourceType.GOLD: 5, Enums.ResourceType.FOOD: 3}

var skills: Dictionary = {} # id -> CommanderSkill
var items: Dictionary = {} # id -> CommanderItem

func _ready() -> void:
	_load_resources_from_dir("res://data/skills/", skills)
	_load_resources_from_dir("res://data/items/", items)

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

func grant_battle_xp(commander: CommanderState, enemy_strength: int, won: bool) -> void:
	var xp_gain := (20 if won else 8) + enemy_strength / 10
	commander.xp += xp_gain
	_check_level_up(commander)

func grant_passive_xp(commander: CommanderState) -> void:
	commander.xp += 2
	_check_level_up(commander)

func _check_level_up(commander: CommanderState) -> void:
	if commander.level >= 10:
		return
	var threshold: int = CommanderState.XP_THRESHOLDS[commander.level]
	if commander.xp >= threshold:
		commander.level += 1
		_apply_level_up(commander)

func _apply_level_up(commander: CommanderState) -> void:
	# Minor skill: either level up an existing one or gain a new one
	var existing_minor: Array[StringName] = []
	for sid in commander.skill_levels:
		var skill: CommanderSkill = skills.get(sid)
		if skill and skill.is_minor and commander.skill_levels[sid] < 10:
			existing_minor.append(sid)
	var new_minor := _get_available_minor_skills(commander)

	if existing_minor.size() > 0 and (new_minor.is_empty() or randf() < 0.5):
		# Level up a random existing minor skill
		var sid: StringName = existing_minor.pick_random()
		commander.skill_levels[sid] = mini(commander.skill_levels[sid] + 1, 10)
	elif new_minor.size() > 0:
		# Gain a new minor skill at level 1
		commander.skill_levels[new_minor.pick_random().id] = 1

	EventBus.commander_level_up.emit(commander)

func get_major_skill_choices(commander: CommanderState) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	# Existing major skills that can be leveled up
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		if level < 10:
			var skill: CommanderSkill = skills.get(skill_id)
			if skill and not skill.is_minor:
				choices.append({"skill_id": skill_id, "is_levelup": true, "current_level": level})
	# New major skills not yet learned
	for skill_id in skills:
		var skill: CommanderSkill = skills[skill_id]
		if not skill.is_minor and not commander.skill_levels.has(skill_id):
			choices.append({"skill_id": skill_id, "is_levelup": false, "current_level": 0})
	choices.shuffle()
	return choices.slice(0, 3)

func choose_major_skill(commander: CommanderState, skill_id: StringName) -> void:
	if commander.skill_levels.has(skill_id):
		commander.skill_levels[skill_id] = mini(commander.skill_levels[skill_id] + 1, 10)
	else:
		commander.skill_levels[skill_id] = 1

# ── Item Drops ────────────────────────────────────────────────

func apply_item_drop(commander: CommanderState, defeated_faction: StringName) -> void:
	var base_chance := 0.3
	if commander.items.size() == 0:
		base_chance = 0.6
	elif commander.items.size() == 1:
		base_chance = 0.4
	if randf() > base_chance:
		return
	var possible_items := _get_items_for_faction(defeated_faction)
	if possible_items.is_empty():
		return
	var item := _weighted_random_item(possible_items)
	if item == null:
		return
	if commander.items.size() < 3:
		commander.items.append(item.id)
	else:
		EventBus.commander_item_full.emit(commander, item)

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
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		_accumulate_army_bonuses(bonuses, effects, 1)
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

func get_commander_city_effects(commander: CommanderState, is_friendly: bool) -> Dictionary:
	var effects_total := {}
	if commander == null:
		return effects_total
	for skill_id in commander.skill_levels:
		var level: int = commander.skill_levels[skill_id]
		var effects := _get_effects_for_id(skill_id)
		_accumulate_city_effects(effects_total, effects, is_friendly, level)
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		_accumulate_city_effects(effects_total, effects, is_friendly, 1)
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
	for item_id in commander.items:
		var effects := _get_item_effects(item_id)
		if effects.has("scouting_bonus"):
			bonus += effects.scouting_bonus
	return bonus

# ── Skill Helpers ─────────────────────────────────────────────

func _get_available_minor_skills(commander: CommanderState) -> Array[CommanderSkill]:
	var result: Array[CommanderSkill] = []
	for skill_id in skills:
		var skill: CommanderSkill = skills[skill_id]
		if skill.is_minor and not commander.skill_levels.has(skill_id):
			result.append(skill)
	return result

func _get_available_major_skills(commander: CommanderState) -> Array[CommanderSkill]:
	var result: Array[CommanderSkill] = []
	for skill_id in skills:
		var skill: CommanderSkill = skills[skill_id]
		if not skill.is_minor and not commander.skill_levels.has(skill_id):
			result.append(skill)
	return result

# ── AI Skill Selection ────────────────────────────────────────

func ai_auto_pick_major_skill(commander: CommanderState) -> void:
	var choices := get_major_skill_choices(commander)
	if choices.size() > 0:
		var choice: Dictionary = choices[0]
		choose_major_skill(commander, choice.skill_id)
