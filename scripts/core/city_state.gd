class_name CityState
extends Resource

@export var city_id: StringName
@export var region_id: StringName
@export var faction_id: StringName
@export var hex_pos: Vector2i
@export var level: int = 1 # 1-5
@export var population: int = 100
@export var growth_points: int = 0 # accumulates toward next level
@export var buildings: Array[StringName] = [] # building_data_ids
@export var build_queue: Array[Dictionary] = [] # [{building_id, turns_remaining}]
@export var recruit_queue: Array[Dictionary] = [] # [{unit_data_id, turns_remaining}]
@export var is_under_siege: bool = false
@export var siege_faction: StringName = &""
@export var siege_turns: int = 0
@export var is_capital: bool = false
@export var can_found_settlement: bool = false

const GROWTH_THRESHOLDS := [200, 400, 700, 1100] # pop needed for levels 2-5

func get_max_building_slots() -> int:
	if is_capital:
		return 2 + level # capital: 3 at L1, 4 at L2, ... 7 at L5
	return level # settlement: 1 at L1, 2 at L2, etc.

func get_available_building_slots() -> int:
	return get_max_building_slots() - buildings.size()

func get_growth_threshold() -> int:
	if level - 1 < GROWTH_THRESHOLDS.size():
		return GROWTH_THRESHOLDS[level - 1]
	return -1 # max level

func can_recruit(unit_data_id: StringName) -> bool:
	for building_id in buildings:
		var building: BuildingData = DataManager.get_building(building_id)
		if building and building.unlocks_units.has(unit_data_id):
			return true
	return false

func get_display_name() -> String:
	var region: RegionData = DataManager.get_region(region_id)
	var suffix := " Capital" if is_capital else " Settlement"
	if region:
		return region.display_name + suffix
	return str(region_id) + suffix
