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
	# Dynamically scan all subdirectories under data/units/
	var base_path := "res://data/units/"
	var dir := DirAccess.open(base_path)
	if dir == null:
		push_warning("Could not open units directory: " + base_path)
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			_load_resources_from_dir(base_path + folder + "/", units)
		folder = dir.get_next()
	dir.list_dir_end()

func _load_regions() -> void:
	_load_resources_from_dir("res://data/regions/", regions)

func _load_buildings() -> void:
	_load_resources_from_dir("res://data/buildings/", buildings)

func _load_followers() -> void:
	_load_resources_from_dir("res://data/followers/", followers)

func _load_research() -> void:
	var base_path := "res://data/research/"
	# Load root-level research files
	_load_resources_from_dir(base_path, research)
	# Load faction subdirectories
	var dir := DirAccess.open(base_path)
	if dir == null:
		push_warning("Could not open research directory: " + base_path)
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			_load_resources_from_dir(base_path + folder + "/", research)
		folder = dir.get_next()
	dir.list_dir_end()

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

# --- Leader Portrait System ---
const LEADER_DIR := "res://assets/sprites/leaders/"

const LEADER_PORTRAIT_MAP := {
	&"empire": "good_leader",
	&"gladehost": "good_leader",
	&"moonspear": "good_leader",
	&"cinderguard": "good_leader",
	&"sunblessed": "good_leader",
	&"skulloath": "evil_leader",
	&"tainted_jade": "evil_leader",
	&"forsaken": "evil_leader",
	&"thunderswarm": "evil_leader",
	&"ivoryscar": "evil_leader",
	&"shardhorde": "evil_leader",
}

var _leader_cache: Dictionary = {}

func get_leader_portrait(faction_id: StringName) -> Texture2D:
	if _leader_cache.has(faction_id):
		return _leader_cache[faction_id]
	var filename: String = LEADER_PORTRAIT_MAP.get(faction_id, "")
	if filename == "":
		_leader_cache[faction_id] = null
		return null
	var path := LEADER_DIR + filename + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_leader_cache[faction_id] = tex
	return tex

# --- Unit Portrait System ---
const PORTRAIT_DIR := "res://assets/sprites/units/portraits/"

# Maps unit_data_id -> portrait filename (without extension)
const UNIT_PORTRAIT_MAP := {
	# Empire
	&"legionary": "legionnaire",
	&"elite_legionaries": "legionnaire",
	&"centurion_guard": "good_leader",
	&"levy_conscripts": "basic_legionnaire",
	&"border_mercenaries": "basic_legionnaire",
	&"dracarii_riders": "empire_cav",
	&"imperial_sky_lancers": "empire_cav",
	&"emberlight_auxilia": "mage",
	&"sentinel_construct": "construct",
	&"marching_bastion": "construct",
	# Skulloath
	&"skulloath_raider": "evil_leader",
	&"warband_raider": "evil_leader",
	&"bonecaller": "evil_leader",
	&"pale_touched": "evil_leader",
	&"ancestor_spirit": "evil_leader",
	&"dread_riders": "skulloath_cavalry",
	&"steppe_rider": "skulloath_cavalry",
	&"steppe_archers": "skulloath_cavalry",
	&"runebound_wyvern": "dragon",
	# Gladehost
	&"dryad": "dryad",
	&"grove_warden": "dryad",
	&"blade_dancer": "dryad",
	&"stag_rider": "dryad",
	&"thornbow_scout": "dryad",
	&"hawk_scout": "dryad",
	&"bear_companion": "elderbeast",
	&"root_sentinel": "construct",
	# Tainted Jade
	&"jade_fang": "seeker",
	&"jungle_stalker": "seeker",
	&"coatl_shaman": "mage",
	&"serpent_guardian": "construct",
	&"vine_golem": "construct",
	&"thrall_swarm": "crystal_swarm",
	&"taint_beast": "dragon",
	# Moonspear
	&"lunar_archer": "lunar_archer",
	&"moonspear_sentinel": "lunar_archer",
	# Ivoryscar
	&"ivoryscar_seeker": "seeker",
	&"bone_cavalry": "skulloath_cavalry",
	&"scarab_swarm": "crystal_swarm",
	# Shardhorde
	&"crystal_swarmling": "crystal_swarm",
	&"shard_crawler": "crystal_swarm",
	&"shard_stalker": "crystal_swarm",
	&"void_skirmisher": "crystal_swarm",
	&"crystalback_raptor": "crystal_swarm",
	&"void_weaver": "mage",
	&"shard_wyrm": "dragon",
	&"elder_ceratops": "elderbeast",
	&"elderbeast_lv1": "elderbeast",
	&"elderbeast_lv2": "elderbeast",
	&"elderbeast_lv3": "elderbeast",
	# Shard Guardians
	&"guardian_wolf": "elderbeast",
	&"guardian_bear": "elderbeast",
	&"guardian_jaguar": "elderbeast",
	&"guardian_eagle": "elderbeast",
	&"guardian_serpent": "elderbeast",
	&"guardian_scorpion": "elderbeast",
	&"guardian_mammoth": "elderbeast",
	&"guardian_crawler": "elderbeast",
	# Cinderguard
	&"cinderguard_forgeborn": "construct",
	&"ember_crossbow": "basic_legionnaire",
	# Sub-factions and independents
	&"ash_berserker": "evil_leader",
	&"frost_swarmling": "crystal_swarm",
	&"oasean_herald": "seeker",
	&"salt_marauder": "evil_leader",
	&"skalvar_sentinel": "good_leader",
	&"thorn_knight": "good_leader",
	&"crimson_centurion": "legionnaire",
	&"aurentis_defender": "good_leader",
	&"thunderswarm_warrior": "evil_leader",
	&"stormbow_raider": "lunar_archer",
	&"sunblessed_pilgrim": "mage",
	&"mist_ranger": "lunar_archer",
	&"obsidian_blade": "seeker",
	&"light_templar": "good_leader",
	&"storm_caller": "mage",
	&"veil_assassin": "seeker",
	&"jade_golem": "construct",
	&"stone_gazer": "construct",
	&"relic_guardian": "construct",
	&"fire_vanguard": "basic_legionnaire",
	&"valkarn_defender": "good_leader",
	&"blood_knight": "evil_leader",
	&"blight_walker": "evil_leader",
	&"splinter_drone": "crystal_swarm",
	&"venerated_guardian": "construct",
	&"forsaken_wretch": "evil_leader",
	&"plague_thrower": "evil_leader",
	&"bat_swarm": "crystal_swarm",
}

var _portrait_cache: Dictionary = {}

func get_unit_portrait(unit_id: StringName) -> Texture2D:
	if _portrait_cache.has(unit_id):
		return _portrait_cache[unit_id]
	var filename: String = UNIT_PORTRAIT_MAP.get(unit_id, "")
	if filename == "":
		_portrait_cache[unit_id] = null
		return null
	var path := PORTRAIT_DIR + filename + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_portrait_cache[unit_id] = tex
	return tex
