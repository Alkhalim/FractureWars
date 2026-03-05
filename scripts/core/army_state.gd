class_name ArmyState
extends Resource

@export var army_id: StringName
@export var faction_id: StringName
@export var hex_pos: Vector2i # Tile coordinates on hex grid
@export var units: Array[UnitInstance] = []
@export var movement_remaining: float = 2.0
@export var has_moved: bool = false
@export var commander: CommanderState = null
@export var commander_name: String = "" # Legacy fallback, use commander.name when available
@export var is_garrison: bool = false # City garrison, not player-controlled, no upkeep
@export var elderbeast_id: StringName = &"" # Shardhorde: elderbeast attached to this army
@export var battle_exhausted: bool = false # Cannot move or fight again this turn (stalemate)
@export var is_camp: bool = false # Sunblessed: army has set up camp (can build)
@export var camp_city_id: StringName = &"" # Sunblessed: city created by this camp
@export var camp_saved_buildings: Array[StringName] = [] # Saved buildings from previous camp
@export var camp_saved_build_queue: Array[Dictionary] = [] # Saved build queue from previous camp

func get_region_id() -> StringName:
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(hex_pos)
		if tile:
			return tile.region_id
	return &""

func get_max_movement() -> float:
	var total_mp := 0.0
	var count := 0
	for unit in units:
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data:
			total_mp += float(unit_data.movement_points)
			count += 1
	if count == 0:
		return 2.0
	var base_mp := total_mp / float(count)
	if commander:
		var bonuses := CommanderSystem.get_commander_army_bonuses(commander)
		base_mp += bonuses.get("movement_bonus", 0.0)
	# Research movement bonuses
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	base_mp += r_eff.get("movement_bonus", 0)
	base_mp += r_eff.get("army_movement_bonus", 0)
	# Moonspear waxing moon bonus (lunar_phase 1)
	if faction_id == &"moonspear":
		var mfs: FactionState = GameManager.state.faction_states.get(faction_id) if GameManager.state else null
		if mfs and mfs.lunar_phase == 1:
			base_mp += 0.5
	# Sunblessed camp building movement bonus (Wanderer's Rest etc.)
	if camp_city_id != &"" and GameManager.state:
		var camp_city: CityState = GameManager.state.cities.get(camp_city_id)
		if camp_city:
			for bid in camp_city.buildings:
				var bdata: BuildingData = DataManager.get_building(bid)
				if bdata and bdata.special_effects.has("army_movement_bonus"):
					base_mp += float(bdata.special_effects["army_movement_bonus"])
	return base_mp * 1.2

func get_vision_range() -> int:
	var base_vision := 3
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	base_vision += r_eff.get("vision_range_bonus", 0)
	if commander:
		var bonuses := CommanderSystem.get_commander_army_bonuses(commander)
		base_vision += bonuses.get("vision_range_bonus", 0)
	return base_vision

func get_max_army_size() -> int:
	var base_size := 8
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	base_size += r_eff.get("max_army_size_bonus", 0)
	return base_size

func get_attrition_reduction() -> float:
	var r_eff := GameManager.research_system.get_research_effects(faction_id)
	return float(r_eff.get("attrition_reduction_pct", 0)) / 100.0

func get_commander_name() -> String:
	if commander:
		return commander.name
	return commander_name

func get_total_strength() -> int:
	var strength := 0
	for unit in units:
		strength += unit.current_hp
	return strength

func can_cross_mountains() -> bool:
	var flying_count := 0
	var total := 0
	for unit in units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			total += 1
			if "flying" in ud.tags:
				flying_count += 1
	return total > 0 and float(flying_count) / float(total) >= 0.5

## Returns a cost multiplier (<1.0 = cheaper) for the given terrain based on unit tags.
## If any unit in the army has a terrain-stride tag, the whole army benefits.
## If ALL units are flying, non-forest difficult terrain gets a significant discount.
func get_terrain_stride_modifier(terrain: Enums.TerrainType) -> float:
	# All-flying army: significant discount on difficult terrain (except forest — dense canopy)
	if terrain in [Enums.TerrainType.MOUNTAINS, Enums.TerrainType.SWAMP,
			Enums.TerrainType.JUNGLE, Enums.TerrainType.DESERT,
			Enums.TerrainType.SHARD_WASTES, Enums.TerrainType.TUNDRA]:
		var all_flying := true
		var unit_count := 0
		for unit in units:
			var ud := DataManager.get_unit(unit.unit_data_id)
			if ud:
				unit_count += 1
				if "flying" not in ud.tags:
					all_flying = false
					break
		if unit_count > 0 and all_flying:
			return 0.6

	for unit in units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud == null:
			continue
		match terrain:
			Enums.TerrainType.JUNGLE:
				if "junglestrider" in ud.tags:
					return 0.85
			Enums.TerrainType.TUNDRA:
				if "tundrawalker" in ud.tags:
					return 0.85
			Enums.TerrainType.DESERT:
				if "desertstrider" in ud.tags:
					return 0.85
			Enums.TerrainType.WETLANDS:
				if "coastalstrider" in ud.tags:
					return 0.85
			Enums.TerrainType.SHARD_WASTES:
				if "shardwalker" in ud.tags:
					return 0.85
			Enums.TerrainType.SWAMP:
				if "swampstrider" in ud.tags:
					return 0.80
				if "coastalstrider" in ud.tags:
					return 0.9
	return 1.0

func is_alive() -> bool:
	for unit in units:
		if unit.current_hp > 0:
			return true
	return false
