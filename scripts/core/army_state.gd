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
	return base_mp

func get_commander_name() -> String:
	if commander:
		return commander.name
	return commander_name

func get_total_strength() -> int:
	var strength := 0
	for unit in units:
		strength += unit.current_hp
	return strength

func is_alive() -> bool:
	for unit in units:
		if unit.current_hp > 0:
			return true
	return false
