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
	# Ensure path ends with a slash
	if not path.ends_with("/"):
		path += "/"
		
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Could not open directory: " + path)
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir():
			# In exported builds, .tres becomes .tres.remap
			# We strip the .remap or .import to get the original resource path
			var clean_path := path + file_name.replace(".remap", "").replace(".import", "")
			
			# Check if the base file (after stripping) is a .tres
			if clean_path.ends_with(".tres"):
				var res = load(clean_path)
				if res and "id" in res:
					target[res.id] = res
				else:
					push_error("Failed to load resource or missing 'id': " + clean_path)
					
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
	# Major factions
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
	# Sub-factions (fallback when no faction-specific art folder)
	&"ashbound": "evil_leader",
	&"aurentis_guard": "good_leader",
	&"blightcoven": "evil_leader",
	&"bloodthrone": "evil_leader",
	&"crimson_legion": "good_leader",
	&"crownfire": "good_leader",
	&"gorgonic_cult": "evil_leader",
	&"icebound": "good_leader",
	&"independent": "good_leader",
	&"jade_conclave": "evil_leader",
	&"luminarch": "good_leader",
	&"miststriders": "good_leader",
	&"oaseans": "good_leader",
	&"obsidian_order": "evil_leader",
	&"salt_reavers": "evil_leader",
	&"servants_of_reliquary": "good_leader",
	&"shard_guardians": "evil_leader",
	&"skalvar_watch": "good_leader",
	&"splinterbrood": "evil_leader",
	&"stormbound": "good_leader",
	&"thornwardens": "good_leader",
	&"twilight_veil": "evil_leader",
	&"valkarn_garrison": "good_leader",
	&"venerated": "evil_leader",
	&"rebels": "evil_leader",
}

var _leader_cache: Dictionary = {}

func get_leader_portrait(faction_id: StringName) -> Texture2D:
	if _leader_cache.has(faction_id):
		return _leader_cache[faction_id]
	# Try faction-specific leader folder first
	var faction_leader_dir := "res://assets/sprites/factions/" + str(faction_id) + "/leaders/"
	var dir := DirAccess.open(faction_leader_dir)
	if dir:
		var images: Array[String] = []
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".webp"):
				images.append(faction_leader_dir + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		if not images.is_empty():
			var pick: String = images[randi() % images.size()]
			if ResourceLoader.exists(pick):
				var tex: Texture2D = load(pick)
				_leader_cache[faction_id] = tex
				return tex
	# Fallback to generic leader
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

var _commander_portrait_cache: Dictionary = {}

func get_commander_portrait(commander: CommanderState) -> Texture2D:
	if commander == null:
		return null
	var cid: StringName = commander.commander_id
	if _commander_portrait_cache.has(cid):
		return _commander_portrait_cache[cid]
	if commander.portrait_path != "":
		if ResourceLoader.exists(commander.portrait_path):
			var tex: Texture2D = load(commander.portrait_path)
			_commander_portrait_cache[cid] = tex
			return tex
	# Fallback to faction default
	var tex := get_leader_portrait(commander.faction_id)
	_commander_portrait_cache[cid] = tex
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
	&"imperial_chariot": "empire_cav",
	&"imperial_crossbow": "basic_legionnaire",
	&"imperial_taskmaster": "legionnaire",
	&"praetorian_champion": "legionnaire",
	&"iron_colossus": "construct",
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
	&"skull_reavers": "evil_leader",
	&"steppe_skirmishers": "skulloath_cavalry",
	&"steppe_mammoth": "elderbeast",
	&"bone_priest": "mage",
	&"dread_knight": "evil_leader",
	# Gladehost
	&"dryad": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_dryad_warrior_of_the_Gladehost_Japanese-Celt_4295e63e-e38a-4861-ae80-04dceb28a5ce_1.png",
	&"grove_warden": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_dryad_warrior_of_the_Gladehost_Japanese-Celt_46726a8c-4121-431a-9b6b-ccbfb3ba87a0_1.png",
	&"blade_dancer": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_samurai_warrior_of_the_Gladehost_Japanese-Ce_16770c3f-c4bb-4dfb-8a07-d6b282666cad_2.png",
	&"stag_rider": "dryad",
	&"thornbow_scout": "dryad",
	&"hawk_scout": "dryad",
	&"bear_companion": "elderbeast",
	&"root_sentinel": "construct",
	&"war_elephant": "res://assets/sprites/factions/gladehost/units/nonbiristudios_war_elephant_Gladehost_Japanese-Celtic_fusion__16abc2e6-d01a-440e-bd9c-dccce618830a_3.png",
	&"glade_cavalry": "dryad",
	&"oakguard": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_dryad_warrior_of_the_Gladehost_Japanese-Celt_4295e63e-e38a-4861-ae80-04dceb28a5ce_1.png",
	&"windrunner": "dryad",
	&"fae_enchanter": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_mage_of_the_Gladehost_Japanese-Celtic_fusion_cbc82e93-b7e7-4f16-8095-4d4bc2bac270_0.png",
	&"wildwood_shaman": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_mage_of_the_Gladehost_Japanese-Celtic_fusion_cbc82e93-b7e7-4f16-8095-4d4bc2bac270_0.png",
	&"treant": "res://assets/sprites/factions/gladehost/units/nonbiristudios_war_elephant_Gladehost_Japanese-Celtic_fusion__5b4ae113-d16e-4e9d-b955-e4e530aa0283_0.png",
	&"sylvan_lancer": "res://assets/sprites/factions/gladehost/units/nonbiristudios_A_samurai_warrior_of_the_Gladehost_Japanese-Ce_16770c3f-c4bb-4dfb-8a07-d6b282666cad_2.png",
	&"thornback_guardian": "res://assets/sprites/factions/gladehost/units/nonbiristudios_war_elephant_Gladehost_Japanese-Celtic_fusion__ee081113-02ce-4c73-8c03-498e44ff5ab1_0.png",
	# Tainted Jade
	&"jade_fang": "seeker",
	&"jungle_stalker": "seeker",
	&"coatl_shaman": "mage",
	&"serpent_guardian": "construct",
	&"vine_golem": "construct",
	&"thrall_swarm": "crystal_swarm",
	&"taint_beast": "dragon",
	&"jade_warrior": "seeker",
	&"jade_cavalry": "seeker",
	&"swamp_rider": "elderbeast",
	&"swamp_runner": "seeker",
	&"jungle_archer": "lunar_archer",
	&"serpent_priestess": "mage",
	&"taint_whisperer": "mage",
	&"spore_shaman": "mage",
	&"fungal_horror": "elderbeast",
	&"mangrove_stalker": "seeker",
	&"venom_assassin": "seeker",
	&"tainted_colossus": "construct",
	&"tainted_warrior": "seeker",
	# Moonspear
	&"lunar_archer": "lunar_archer",
	&"moonspear_sentinel": "lunar_archer",
	&"lunar_priestess": "mage",
	&"moonlance_rider": "empire_cav",
	&"crescent_ranger": "lunar_archer",
	&"starlight_archer": "lunar_archer",
	&"moonstone_golem": "construct",
	&"nightrider": "skulloath_cavalry",
	&"star_falcon": "dragon",
	&"frost_hydra": "dragon",
	&"moonhound": "elderbeast",
	&"eclipse_champion": "good_leader",
	&"seal_mage": "mage",
	&"shadow_dancer": "seeker",
	&"night_stalker": "seeker",
	# Ivoryscar
	&"ivoryscar_seeker": "seeker",
	&"bone_cavalry": "skulloath_cavalry",
	&"scarab_swarm": "crystal_swarm",
	&"tomb_guard": "basic_legionnaire",
	&"bone_archer": "lunar_archer",
	&"sand_mage": "mage",
	&"sand_wyrm": "dragon",
	&"sand_scorpion": "elderbeast",
	&"great_scarab": "elderbeast",
	&"desert_outrider": "skulloath_cavalry",
	&"relic_excavator": "seeker",
	&"relic_skirmisher": "seeker",
	&"relic_golem": "construct",
	&"bone_golem": "construct",
	&"bone_colossus": "construct",
	&"tomb_jackal": "elderbeast",
	&"relic_scholar": "mage",
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
	&"crystal_menders": "mage",
	&"shardback_behemoth": "elderbeast",
	&"crystalwing_swoopers": "dragon",
	&"shard_colossus": "construct",
	&"crystal_golem": "construct",
	&"crystal_archer": "lunar_archer",
	&"crystal_cavalry": "crystal_swarm",
	&"shard_swarm": "crystal_swarm",
	# Shard Guardians
	&"guardian_wolf": "elderbeast",
	&"guardian_bear": "elderbeast",
	&"guardian_jaguar": "elderbeast",
	&"guardian_eagle": "elderbeast",
	&"guardian_serpent": "elderbeast",
	&"guardian_scorpion": "elderbeast",
	&"guardian_mammoth": "elderbeast",
	&"guardian_crawler": "elderbeast",
	# Thunderswarm
	&"thunderswarm_warrior": "evil_leader",
	&"stormbow_raider": "lunar_archer",
	&"storm_caller": "mage",
	&"thundercaller": "mage",
	&"storm_shaman": "mage",
	&"storm_drummer": "evil_leader",
	&"storm_archer": "lunar_archer",
	&"tempest_eagle": "dragon",
	&"thunderwyrm": "dragon",
	&"storm_drakes": "dragon",
	&"dragon_hatchling": "dragon",
	&"storm_hound": "elderbeast",
	&"ram_rider": "skulloath_cavalry",
	&"wind_elemental": "mage",
	&"lightning_golem": "construct",
	&"stormforged_champion": "evil_leader",
	# Cinderguard
	&"cinderguard_warden": "basic_legionnaire",
	&"ember_crossbow": "basic_legionnaire",
	&"ember_mage": "mage",
	&"ember_cavalry": "empire_cav",
	&"cinder_drake": "dragon",
	&"cinder_militia": "basic_legionnaire",
	&"cinder_rider": "empire_cav",
	&"magma_crawler": "elderbeast",
	&"forge_warden": "basic_legionnaire",
	&"forge_priest": "mage",
	&"forge_colossus": "construct",
	&"watchfire_keeper": "basic_legionnaire",
	&"flame_templar": "good_leader",
	&"fire_vanguard": "basic_legionnaire",
	# Forsaken
	&"void_berserker": "evil_leader",
	&"void_prophet": "mage",
	&"cursed_archer": "lunar_archer",
	&"ghoul_pack": "crystal_swarm",
	&"vampire_lord": "evil_leader",
	&"shadow_wyrm": "dragon",
	&"blood_shaman": "mage",
	&"hex_knight": "evil_leader",
	&"bound_fiend": "evil_leader",
	&"coven_witch": "mage",
	&"deathshriek_bat": "crystal_swarm",
	&"blood_bat_swarm": "crystal_swarm",
	# Sunblessed
	&"sunblessed_pilgrim": "mage",
	&"sun_archer": "lunar_archer",
	&"sun_oracle": "mage",
	&"dawn_crusader": "good_leader",
	&"dawn_guardian": "good_leader",
	&"dawn_militia": "basic_legionnaire",
	&"sunfire_lancer": "empire_cav",
	&"sunfire_mage": "mage",
	&"solar_champion": "good_leader",
	&"solar_cavalry_archer": "empire_cav",
	&"solar_crocodilian": "elderbeast",
	&"phoenix": "dragon",
	&"celestial_oracle": "mage",
	&"temple_defender": "good_leader",
	&"temple_initiate": "basic_legionnaire",
	&"radiant_priest": "mage",
	&"sacred_hawk": "dragon",
	&"griffin": "dragon",
	&"sun_slinger": "lunar_archer",
	# Sub-factions
	&"ash_berserker": "evil_leader",
	&"ash_ritualist": "mage",
	&"ashen_champion": "evil_leader",
	&"frost_swarmling": "crystal_swarm",
	&"frost_mage": "mage",
	&"frost_volunteer": "basic_legionnaire",
	&"frost_wyvern": "dragon",
	&"oasean_herald": "seeker",
	&"oasis_guardian": "elderbeast",
	&"salt_marauder": "evil_leader",
	&"corsair_captain": "evil_leader",
	&"boarding_crew": "evil_leader",
	&"sea_witch": "mage",
	&"skalvar_sentinel": "good_leader",
	&"mountain_guardian": "good_leader",
	&"mountain_scout": "seeker",
	&"highland_patrol": "basic_legionnaire",
	&"highland_skirmisher": "basic_legionnaire",
	&"thorn_knight": "good_leader",
	&"thorn_archer": "lunar_archer",
	&"briar_golem": "construct",
	&"crimson_centurion": "legionnaire",
	&"crimson_praetorian": "legionnaire",
	&"crimson_shieldwall": "basic_legionnaire",
	&"crimson_ballistarius": "basic_legionnaire",
	&"aurentis_defender": "good_leader",
	&"merchant_crossbow": "basic_legionnaire",
	&"canal_gondolier": "empire_cav",
	&"gilded_champion": "good_leader",
	&"mist_ranger": "lunar_archer",
	&"fog_weaver": "mage",
	&"obsidian_blade": "seeker",
	&"obsidian_phalanx": "basic_legionnaire",
	&"light_templar": "good_leader",
	&"crusading_knight": "good_leader",
	&"restoration_mage": "mage",
	&"veil_assassin": "seeker",
	&"dusksworn": "seeker",
	&"shadow_mage": "mage",
	&"jade_golem": "construct",
	&"stone_gazer": "construct",
	&"cult_fanatic": "evil_leader",
	&"demon_caller": "mage",
	&"oracle_diviner": "mage",
	&"relic_guardian": "construct",
	&"sand_scholar": "mage",
	&"enchanted_guardian": "construct",
	&"dragonkeeper": "good_leader",
	&"valkarn_defender": "good_leader",
	&"blood_knight": "evil_leader",
	&"blight_walker": "evil_leader",
	&"plague_shaman": "mage",
	&"splinter_drone": "crystal_swarm",
	&"splinter_spitter": "crystal_swarm",
	&"venerated_guardian": "construct",
	&"shadow_thrall": "evil_leader",
	&"death_mage": "mage",
	&"bat_swarm": "crystal_swarm",
	&"familiar_swarm": "crystal_swarm",
	&"bloodraven": "evil_leader",
	&"thrall_guard": "evil_leader",
	&"silverguard": "good_leader",
	&"ice_hunter": "seeker",
	&"wasteland_enforcer": "evil_leader",
	&"chain_catcher": "seeker",
	&"light_crossbow": "lunar_archer",
	&"barrier_priest": "mage",
	&"zealot_preacher": "mage",
	&"field_medic": "basic_legionnaire",
	&"ancient_champion": "good_leader",
	&"storm_healer": "mage",
	&"basilisk_rider": "elderbeast",
	# Independent / Rebels
	&"citizen_phalanx": "basic_legionnaire",
	&"hoplite_guard": "good_leader",
	&"toxotes": "lunar_archer",
	&"citizen_cavalry": "empire_cav",
	&"war_ballista": "construct",
	&"rebel_militia": "evil_leader",
	&"rebel_archer": "lunar_archer",
	&"rebel_horseman": "skulloath_cavalry",
	&"rebel_warbeast": "elderbeast",
	&"rebel_brutes": "evil_leader",
	# Stormbound (valkyrie etc)
	&"valkyrie": "good_leader",
}

var _portrait_cache: Dictionary = {}

func get_unit_portrait(unit_id: StringName) -> Texture2D:
	if _portrait_cache.has(unit_id):
		return _portrait_cache[unit_id]
	var filename: String = UNIT_PORTRAIT_MAP.get(unit_id, "")
	if filename == "":
		_portrait_cache[unit_id] = null
		return null
	var tex: Texture2D = null
	if filename.begins_with("res://"):
		# Full path to faction-specific portrait
		if ResourceLoader.exists(filename):
			tex = load(filename)
	else:
		var path := PORTRAIT_DIR + filename + ".png"
		if ResourceLoader.exists(path):
			tex = load(path)
	_portrait_cache[unit_id] = tex
	return tex
