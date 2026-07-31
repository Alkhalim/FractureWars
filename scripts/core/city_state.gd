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
@export var siege_turns: float = 0.0 # Accumulated siege pressure (was an int turn counter)
@export var is_capital: bool = false
@export var is_settlement: bool = false
@export var can_found_settlement: bool = false
@export var loyalty: int = 20              # -100 to 100 (computed weighted average)
@export var class_loyalty: Dictionary = {
	"peasants": 20, "artisans": 20, "scholars": 20, "nobles": 20, "captives": 0
}
@export var original_faction_id: StringName = &""  # cultural origin, never changes
@export var turns_since_capture: int = -1  # -1 = never captured; 0+ = turns since capture
@export var upgrade_turns_remaining: int = 0 # 0 = no upgrade in progress; >0 = turns left
@export var garrison_defeated_turn: int = -1 # Turn when garrison was last defeated (-1 = never)
@export var garrison_hp_ratio: float = 1.0 # 0.0 = destroyed, 1.0 = full; heals over time when not sieged
@export var garrison_units: Array[Dictionary] = [] # Independent cities: persistent garrison [{unit_id, count}]
@export var building_recruit_queues: Dictionary = {} # building_id -> Array[Dict] (per-building training queues)
@export var is_mobile_camp: bool = false # Sunblessed: PERMANENT camp identity (set once by setup_sunblessed_camp, never cleared -- keeps full faction building access despite is_settlement=true). The separate "currently marching, 80% income" check lives in CitySystem._camp_is_currently_marching, derived from the linked army's is_camp flag, not this field.
@export var production_disabled_turns: int = 0 # >0: evacuated/offline, calculate_city_income() returns {}

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
	var parent_fid: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	if is_capital:
		base = 2 + level # capital: 3 at L1, 4 at L2, ... 7 at L5
	elif is_settlement and parent_fid == &"cinderguard":
		# Cinderguard settlements are fortified outposts with extra slots
		base = 1 + level # 2 at L1, 3 at L2, ... 6 at L5 (vs normal 1-5)
	else:
		base = level # settlement: 1 at L1, 2 at L2, etc.
	# Region completion bonus: +1 building slot
	if faction_id != &"" and faction_id != &"independent":
		var completed := GameManager.get_completed_regions(faction_id)
		if region_id in completed:
			base += 1
	# Research: capital building slots bonus
	var r_eff := GameManager.research_system.get_research_effects(parent_fid)
	base += r_eff.get("capital_building_slots", 0)
	# Cinderguard border fortress bonus slots
	if is_settlement and parent_fid == &"cinderguard":
		var fs: FactionState = GameManager.state.faction_states.get(faction_id) if GameManager.state else null
		if fs and fs.border_fortresses.get(city_id, 0) >= 3:
			base += 1 # Full border fort grants +1 extra slot
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
		return int(threshold * 1.2)
	# Max level — cap at 120% of the last threshold
	return int(GROWTH_THRESHOLDS[GROWTH_THRESHOLDS.size() - 1] * 1.2)

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

# Basic units every city can recruit without buildings (faction-specific)
const FACTION_BASIC_UNITS := {
	&"empire": &"levy_conscripts",
	&"gladehost": &"thornbow_scout",
	&"tainted_jade": &"jade_fang",
	&"skulloath": &"steppe_rider",
	&"moonspear": &"moonspear_sentinel",
	&"thunderswarm": &"thunderswarm_warrior",
	&"cinderguard": &"cinderguard_warden",
	&"forsaken": &"bat_swarm",
	&"ivoryscar": &"scarab_swarm",
	&"shardhorde": &"crystal_swarmling",
	&"sunblessed": &"sunblessed_pilgrim",
}

func can_recruit(unit_data_id: StringName) -> bool:
	# Basic unit: always recruitable for the faction (no building needed)
	var basic_unit: StringName = FACTION_BASIC_UNITS.get(faction_id, &"")
	if basic_unit != &"" and unit_data_id == basic_unit:
		return true
	# Also check parent faction for minor factions
	var parent_id: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, &"")
	if parent_id != &"":
		var parent_basic: StringName = FACTION_BASIC_UNITS.get(parent_id, &"")
		if parent_basic != &"" and unit_data_id == parent_basic:
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
	var suffix := " Capital" if is_capital else (" Settlement" if is_settlement else "")
	if region:
		return region.display_name + suffix
	return str(region_id) + suffix
