extends Node

var factions: Dictionary = {} # id -> FactionData
var units: Dictionary = {} # id -> UnitData
var regions: Dictionary = {} # id -> RegionData
var buildings: Dictionary = {} # id -> BuildingData
var followers: Dictionary = {} # id -> FollowerData
var research: Dictionary = {} # id -> ResearchData
var policies: Dictionary = {} # id -> PolicyData

var calendar_months: Array[Dictionary] = [
	{name = "Moonwatch", realms = [Enums.Realm.DIVINE]},
	{name = "Ashwake", realms = [Enums.Realm.VOID]},
	{name = "Stormturn", realms = [Enums.Realm.ELEMENTAL]},
	{name = "Bloomrest", realms = [Enums.Realm.NATURE]},
	{name = "Steelmarch", realms = [Enums.Realm.MORTAL]},
	{name = "Goldtide", realms = [Enums.Realm.DIVINE, Enums.Realm.MORTAL]},
	{name = "Shatterwane", realms = [Enums.Realm.VOID, Enums.Realm.ELEMENTAL]},
	{name = "Deeproot", realms = [Enums.Realm.NATURE, Enums.Realm.VOID]},
	{name = "Brightfall", realms = [Enums.Realm.ELEMENTAL, Enums.Realm.DIVINE]},
	{name = "Cindernight", realms = [Enums.Realm.MORTAL, Enums.Realm.VOID]},
]

func _ready() -> void:
	_load_factions()
	_load_units()
	_load_regions()
	_load_buildings()
	_load_followers()
	_load_research()
	_load_policies()

func _load_factions() -> void:
	_load_resources_from_dir("res://data/factions/", factions)

func _load_units() -> void:
	_load_resources_from_dir("res://data/units/empire/", units)
	_load_resources_from_dir("res://data/units/skulloath/", units)
	_load_resources_from_dir("res://data/units/gladehost/", units)
	_load_resources_from_dir("res://data/units/tainted_jade/", units)
	_load_resources_from_dir("res://data/units/shardhorde/", units)
	_load_resources_from_dir("res://data/units/shard_guardians/", units)

func _load_regions() -> void:
	_load_resources_from_dir("res://data/regions/", regions)

func _load_buildings() -> void:
	_load_resources_from_dir("res://data/buildings/", buildings)

func _load_followers() -> void:
	_load_resources_from_dir("res://data/followers/", followers)

func _load_research() -> void:
	_load_resources_from_dir("res://data/research/", research)

func _load_policies() -> void:
	_load_resources_from_dir("res://data/policies/", policies)

func _load_resources_from_dir(path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Could not open directory: " + path)
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

func get_faction(id: StringName) -> FactionData:
	return factions.get(id)

func get_unit(id: StringName) -> UnitData:
	return units.get(id)

func get_region(id: StringName) -> RegionData:
	return regions.get(id)

func get_building(id: StringName) -> BuildingData:
	return buildings.get(id)

func get_follower(id: StringName) -> FollowerData:
	return followers.get(id)

func get_research(id: StringName) -> ResearchData:
	return research.get(id)

func get_policy(id: StringName) -> PolicyData:
	return policies.get(id)

func get_month_name(index: int) -> String:
	if index >= 0 and index < calendar_months.size():
		return calendar_months[index].name
	return "Unknown"
