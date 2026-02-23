class_name CityState
extends Resource

@export var city_id: StringName
@export var city_name: String = ""
@export var region_id: StringName
@export var faction_id: StringName
@export var hex_pos: Vector2i
@export var level: int = 1 # 1-5
@export var population: int = 100
@export var growth_points: int = 0 # accumulates toward next level
@export var buildings: Array[StringName] = [] # building_data_ids
@export var building_tiles: Dictionary = {} # building_id -> Vector2i (hex tile where building is placed)
@export var build_queue: Array[Dictionary] = [] # [{building_id, turns_remaining, tile_pos}]
@export var recruit_queue: Array[Dictionary] = [] # [{unit_data_id, turns_remaining}]
@export var is_under_siege: bool = false
@export var siege_faction: StringName = &""
@export var siege_turns: int = 0
@export var is_capital: bool = false
@export var can_found_settlement: bool = false
@export var loyalty: int = 20              # -100 to 100 (computed weighted average)
@export var class_loyalty: Dictionary = {
	"peasants": 20, "artisans": 20, "scholars": 20, "nobles": 20, "captives": 0
}
@export var original_faction_id: StringName = &""  # cultural origin, never changes
@export var turns_since_capture: int = -1  # -1 = never captured; 0+ = turns since capture
@export var upgrade_turns_remaining: int = 0 # 0 = no upgrade in progress; >0 = turns left

const GROWTH_THRESHOLDS := [200, 400, 700, 1100] # pop needed for levels 2-5

# Resource costs to upgrade to each level: {target_level: {ResourceType: amount}}
const UPGRADE_COSTS := {
	2: {0: 200, 1: 30, 5: 50},
	3: {0: 500, 1: 80, 5: 100},
	4: {0: 1000, 1: 150, 5: 200, 2: 30},
	5: {0: 2000, 1: 300, 5: 400, 2: 80},
}

# Turns required to complete upgrade to each level
const UPGRADE_TURNS := {
	2: 3,
	3: 4,
	4: 5,
	5: 6,
}

func get_max_building_slots() -> int:
	var base: int
	if is_capital:
		base = 2 + level # capital: 3 at L1, 4 at L2, ... 7 at L5
	else:
		base = level # settlement: 1 at L1, 2 at L2, etc.
	# Region completion bonus: +1 building slot
	if faction_id != &"" and faction_id != &"independent":
		var completed := GameManager.get_completed_regions(faction_id)
		if region_id in completed:
			base += 1
	return base

func get_available_building_slots() -> int:
	return get_max_building_slots() - buildings.size()

func get_occupied_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for bid in building_tiles:
		var pos = building_tiles[bid]
		if pos is Vector2i and not result.has(pos):
			result.append(pos)
	# Also count tiles reserved by build queue
	for item in build_queue:
		if item.has("tile_pos"):
			var tpos = item.tile_pos
			if tpos is Vector2i and not result.has(tpos):
				result.append(tpos)
	return result

func get_growth_threshold() -> int:
	if level - 1 < GROWTH_THRESHOLDS.size():
		return GROWTH_THRESHOLDS[level - 1]
	return -1 # max level

func get_population_cap() -> int:
	var threshold := get_growth_threshold()
	if threshold > 0:
		return int(threshold * 1.5)
	# Max level — cap at 150% of the last threshold
	return int(GROWTH_THRESHOLDS[GROWTH_THRESHOLDS.size() - 1] * 1.5)

func is_upgrade_available() -> bool:
	if upgrade_turns_remaining > 0:
		return false # already upgrading
	var threshold := get_growth_threshold()
	if threshold < 0:
		return false # max level
	return population >= threshold

func get_upgrade_cost() -> Dictionary:
	var target_level := level + 1
	return UPGRADE_COSTS.get(target_level, {})

func get_upgrade_time() -> int:
	var target_level := level + 1
	return UPGRADE_TURNS.get(target_level, 3)

func can_recruit(unit_data_id: StringName) -> bool:
	# Shardhorde: Crystal Swarmlings are always recruitable (no building needed)
	if unit_data_id == &"crystal_swarmling" and faction_id == &"shardhorde":
		return true
	for building_id in buildings:
		var current_id: StringName = building_id
		while current_id != &"":
			var building: BuildingData = DataManager.get_building(current_id)
			if building == null:
				break
			if building.unlocks_units.has(unit_data_id):
				return true
			current_id = building.upgrades_from
	return false

func get_display_name() -> String:
	if city_name != "":
		return city_name
	var region: RegionData = DataManager.get_region(region_id)
	var suffix := " Capital" if is_capital else " Settlement"
	if region:
		return region.display_name + suffix
	return str(region_id) + suffix
