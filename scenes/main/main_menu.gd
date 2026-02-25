extends Control

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
var continue_button: Button
var load_button: Button
var options_button: Button

# Faction selection
var _faction_select_panel: Control

func _ready() -> void:
	# Load background image
	var bg_tex := load("res://assets/sprites/ui/MainMenuBackground.png") as Texture2D
	if bg_tex:
		$Background.texture = bg_tex

	new_game_button.pressed.connect(_on_new_game)
	quit_button.pressed.connect(_on_quit)

	# Add Continue button (auto-save slot 0)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(0, 96)
	continue_button.add_theme_font_size_override("font_size", 18)
	continue_button.visible = GameManager.has_save(0)
	continue_button.pressed.connect(_on_continue)
	$VBoxContainer.add_child(continue_button)
	$VBoxContainer.move_child(continue_button, $VBoxContainer.get_children().find(new_game_button))

	# Add Load Game button
	load_button = Button.new()
	load_button.text = "Load Game"
	load_button.custom_minimum_size = Vector2(0, 96)
	load_button.add_theme_font_size_override("font_size", 18)
	load_button.visible = _has_any_save()
	load_button.pressed.connect(_on_load_game)
	$VBoxContainer.add_child(load_button)
	$VBoxContainer.move_child(load_button, $VBoxContainer.get_children().find(new_game_button) + 1)

	# Add Options button (before Quit)
	options_button = Button.new()
	options_button.text = "Options"
	options_button.custom_minimum_size = Vector2(0, 96)
	options_button.add_theme_font_size_override("font_size", 18)
	options_button.pressed.connect(_on_options)
	$VBoxContainer.add_child(options_button)
	$VBoxContainer.move_child(options_button, $VBoxContainer.get_children().find(quit_button))

	AudioManager.play_music(&"music_menu")

func _has_any_save() -> bool:
	for i in range(0, 4):
		if GameManager.has_save(i):
			return true
	return false

func _on_new_game() -> void:
	AudioManager.play_sfx(&"ui_click")
	_show_faction_select()

func _on_continue() -> void:
	AudioManager.play_sfx(&"ui_click")
	GameManager.load_game(0)

func _on_load_game() -> void:
	_show_load_menu()

func _on_options() -> void:
	AudioManager.play_sfx(&"ui_click")
	AudioManager.create_options_panel(self)

func _on_quit() -> void:
	get_tree().quit()

# ── Faction Selection ───────────────────────────────────────

var _selected_faction_id: StringName = &""
var _faction_info_label: Label
var _faction_desc_label: Label
var _faction_traits_label: Label
var _faction_region_label: Label
var _faction_color_rect: ColorRect
var _faction_start_btn: Button
var _faction_buttons: Dictionary = {} # faction_id -> Button
var _faction_emblem: _FactionEmblem
var _leader_name_label: Label
var _leader_bonus_label: Label
var _selected_leader_indices: Dictionary = {} # faction_id -> int

const FACTION_LEADERS := {
	&"empire": [
		{"name": "Emperor Aurelian III", "portrait": "warrior_leader", "bonuses": [
			{&"label": "Legionaries cost -20% Gold", &"key": "unit_discount_legionary", &"value": 20},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "Starts with Market Square", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "market_square", "army_override": [&"legionary", &"legionary", &"legionary", &"emberlight_auxilia", &"centurion_guard"]},
		{"name": "Senator Livia", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+20% Gold Income", &"key": "income_gold", &"value": 20},
			{&"label": "All upkeep costs -15%", &"key": "upkeep_reduction", &"value": 15},
			{&"label": "+15 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 15},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"levy_conscripts", &"levy_conscripts", &"legionary", &"border_mercenaries", &"border_mercenaries"]},
		{"name": "General Crassus", "portrait": "warrior_leader", "bonuses": [
			{&"label": "Elite Legionaries cost -25% Gold", &"key": "unit_discount_elite_legionaries", &"value": 25},
			{&"label": "+8% Army Attack", &"key": "army_attack", &"value": 8},
			{&"label": "Starts with Shieldwall Grounds", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "starting_building": "shieldwall_grounds", "army_override": [&"legionary", &"legionary", &"elite_legionaries", &"emberlight_auxilia", &"border_mercenaries"]},
	],
	&"skulloath": [
		{"name": "Khan Borlag the Pale", "portrait": "warrior_leader", "bonuses": [
			{&"label": "Steppe Riders cost -20% Gold", &"key": "unit_discount_steppe_rider", &"value": 20},
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Starts with Beast Pens", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Food Income", &"key": "income_food", &"value": -15},
		], "starting_building": "beast_pens", "army_override": [&"warband_raider", &"steppe_rider", &"steppe_rider", &"steppe_archers", &"bonecaller"]},
		{"name": "Bone Witch Vashra", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Ancestor Spirits cost -25% Gold", &"key": "unit_discount_ancestor_spirit", &"value": 25},
			{&"label": "Corruption drifts -1 per turn", &"key": "corruption_drift", &"value": -1},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "army_override": [&"warband_raider", &"warband_raider", &"bonecaller", &"pale_touched", &"ancestor_spirit"]},
		{"name": "Warlord Dregg", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "+15% Iron Income", &"key": "income_iron", &"value": 15},
			{&"label": "Starts with War Forge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "war_forge", "army_override": [&"warband_raider", &"warband_raider", &"warband_raider", &"steppe_archers", &"steppe_archers"]},
	],
	&"gladehost": [
		{"name": "Archdruid Thalwen", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+10 Harmony at start", &"key": "harmony_bonus", &"value": 10},
			{&"label": "Dryads cost -20% Gold", &"key": "unit_discount_dryad", &"value": 20},
			{&"label": "Starts with Sacred Grove", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Attack", &"key": "army_attack", &"value": -8},
		], "starting_building": "sacred_grove", "army_override": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"dryad", &"hawk_scout"]},
		{"name": "Warden Elowen", "portrait": "warrior_leader", "bonuses": [
			{&"label": "Stag Riders cost -20% Gold", &"key": "unit_discount_stag_rider", &"value": 20},
			{&"label": "+8% Army Defense", &"key": "army_defense", &"value": 8},
			{&"label": "+10% Food Income", &"key": "income_food", &"value": 10},
			{&"label": "-10% Gold Income", &"key": "income_gold", &"value": -10},
		], "army_override": [&"grove_warden", &"grove_warden", &"stag_rider", &"stag_rider", &"thornbow_scout"]},
		{"name": "Grove Speaker Faelen", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+15 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 15},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-10% Army HP", &"key": "army_hp", &"value": -10},
		], "army_override": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"hawk_scout", &"hawk_scout"]},
	],
	&"moonspear": [
		{"name": "High Priestess Selara", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Starweavers cost -25% Gold", &"key": "unit_discount_starweaver", &"value": 25},
			{&"label": "Starts with Moon Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "starting_building": "moon_shrine", "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"lunar_archer", &"starweaver", &"moonhound"]},
		{"name": "Moon Guardian Theron", "portrait": "warrior_leader", "bonuses": [
			{&"label": "Silverguard cost -20% Gold", &"key": "unit_discount_silverguard", &"value": 20},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Starts with Sentinel Hall", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Gold Income", &"key": "income_gold", &"value": -10},
		], "starting_building": "sentinel_hall", "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"moonspear_sentinel", &"silverguard", &"lunar_archer"]},
		{"name": "Starweaver Lunara", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-8% Army Attack", &"key": "army_attack", &"value": -8},
		], "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"lunar_archer", &"lunar_archer", &"frost_volunteer"]},
	],
	&"thunderswarm": [
		{"name": "Warchief Groth", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+12% Army Attack", &"key": "army_attack", &"value": 12},
			{&"label": "Warriors cost -15% Gold", &"key": "unit_discount_thunderswarm_warrior", &"value": 15},
			{&"label": "+10 Storm Fury at start", &"key": "storm_fury_bonus", &"value": 10},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"highland_skirmisher"]},
		{"name": "Storm Shaman Kira", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Storm Hounds cost -25% Gold", &"key": "unit_discount_storm_hound", &"value": 25},
			{&"label": "Starts with Lightning Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "starting_building": "lightning_shrine", "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"storm_hound", &"storm_hound", &"storm_shaman"]},
		{"name": "Thundercaller Borak", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+15% Iron Income", &"key": "income_iron", &"value": 15},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Starts with Storm Forge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "storm_forge", "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"highland_skirmisher", &"highland_skirmisher"]},
	],
	&"tainted_jade": [
		{"name": "Serpent Queen Ixchala", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Jade Fangs cost -20% Gold", &"key": "unit_discount_jade_fang", &"value": 20},
			{&"label": "+5 Taint Power at start", &"key": "taint_power_bonus", &"value": 5},
			{&"label": "-10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": -10},
		], "army_override": [&"jade_fang", &"jade_fang", &"jade_fang", &"jungle_stalker", &"coatl_shaman"]},
		{"name": "Venom Lord Sethis", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "+8% Army Defense", &"key": "army_defense", &"value": 8},
			{&"label": "Starts with Serpent Pit", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "serpent_pit", "army_override": [&"jade_fang", &"jade_fang", &"jungle_stalker", &"thrall_swarm", &"thrall_swarm"]},
		{"name": "Jade Seer Mayana", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+10% Shard Essence Income", &"key": "income_shard", &"value": 10},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"jade_fang", &"jade_fang", &"coatl_shaman", &"coatl_shaman", &"thrall_swarm"]},
	],
	&"cinderguard": [
		{"name": "Forgemaster Valdris", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+20% Iron Income", &"key": "income_iron", &"value": 20},
			{&"label": "Forgeborn cost -15% Gold", &"key": "unit_discount_cinderguard_forgeborn", &"value": 15},
			{&"label": "Starts with Ember Foundry", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "ember_foundry", "army_override": [&"cinderguard_forgeborn", &"cinderguard_forgeborn", &"cinderguard_forgeborn", &"ember_crossbow", &"ember_crossbow"]},
		{"name": "Flame Templar Ignis", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "+8% Army HP", &"key": "army_hp", &"value": 8},
			{&"label": "+10 Forge Heat at start", &"key": "forge_heat_bonus", &"value": 10},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "army_override": [&"cinderguard_forgeborn", &"cinderguard_forgeborn", &"cinderguard_forgeborn", &"cinderguard_forgeborn", &"ember_crossbow"]},
		{"name": "Ember Priestess Pyra", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Starts with Flame Sanctum", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Iron Income", &"key": "income_iron", &"value": -10},
		], "starting_building": "flame_sanctum", "army_override": [&"cinderguard_forgeborn", &"cinderguard_forgeborn", &"ember_crossbow", &"ember_mage", &"cinder_militia"]},
	],
	&"forsaken": [
		{"name": "The Hollow King", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "Wretches cost -30% Gold", &"key": "unit_discount_forsaken_wretch", &"value": 30},
			{&"label": "Starts with Plague Workshop", &"key": "starting_building", &"value": 0},
			{&"label": "-10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": -10},
		], "starting_building": "plague_workshop", "army_override": [&"forsaken_wretch", &"forsaken_wretch", &"forsaken_wretch", &"forsaken_wretch", &"plague_thrower"]},
		{"name": "Plague Mother Neth", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Food Income", &"key": "income_food", &"value": 15},
			{&"label": "Bat Swarms cost -25% Gold", &"key": "unit_discount_bat_swarm", &"value": 25},
			{&"label": "+8% Army HP", &"key": "army_hp", &"value": 8},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"forsaken_wretch", &"forsaken_wretch", &"bat_swarm", &"bat_swarm", &"bat_swarm"]},
		{"name": "Void Prophet Malachar", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Starts with Blighted Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Army Defense", &"key": "army_defense", &"value": -15},
		], "starting_building": "blighted_shrine", "army_override": [&"forsaken_wretch", &"forsaken_wretch", &"plague_thrower", &"plague_thrower", &"bat_swarm"]},
	],
	&"ivoryscar": [
		{"name": "Oracle Medusa", "portrait": "merchant_leader", "bonuses": [
			{&"label": "+20% Gold Income", &"key": "income_gold", &"value": 20},
			{&"label": "+10% Shard Essence Income", &"key": "income_shard", &"value": 10},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"ivoryscar_seeker", &"ivoryscar_seeker", &"scarab_swarm", &"scarab_swarm", &"relic_skirmisher"]},
		{"name": "Tomb King Ankaris", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+12% Army Defense", &"key": "army_defense", &"value": 12},
			{&"label": "Tomb Guards cost -20% Gold", &"key": "unit_discount_tomb_guard", &"value": 20},
			{&"label": "Starts with Bone Arsenal", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "bone_arsenal", "army_override": [&"ivoryscar_seeker", &"tomb_guard", &"tomb_guard", &"scarab_swarm", &"bone_archer"]},
		{"name": "Relic Seeker Dara", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+20% Shard Essence Income", &"key": "income_shard", &"value": 20},
			{&"label": "+8% Army Speed", &"key": "army_speed", &"value": 8},
			{&"label": "Starts with Seekers Lodge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Defense", &"key": "army_defense", &"value": -10},
		], "starting_building": "seekers_lodge", "army_override": [&"ivoryscar_seeker", &"ivoryscar_seeker", &"ivoryscar_seeker", &"scarab_swarm", &"relic_skirmisher"]},
	],
	&"shardhorde": [
		{"name": "The Crystalmind", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "+8% Army Attack", &"key": "army_attack", &"value": 8},
			{&"label": "Elderbeast HP +10%", &"key": "elderbeast_hp", &"value": 10},
			{&"label": "-10% Army Defense", &"key": "army_defense", &"value": -10},
		]},
		{"name": "Shard Matriarch", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Elderbeast Regen +2/turn", &"key": "elderbeast_regen", &"value": 2},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		]},
	],
	&"sunblessed": [
		{"name": "Solar Archon Kael", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "+10 Solar Faith at start", &"key": "solar_faith_bonus", &"value": 10},
			{&"label": "Starts with Sunfire Altar", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Food Income", &"key": "income_food", &"value": -10},
		], "starting_building": "sunfire_altar", "army_override": [&"dawn_militia", &"dawn_militia", &"sun_archer", &"sun_archer", &"dawn_crusader"]},
		{"name": "Dawn Priestess Amara", "portrait": "scholar_leader", "bonuses": [
			{&"label": "+15% Food Income", &"key": "income_food", &"value": 15},
			{&"label": "+15 Solar Faith at start", &"key": "solar_faith_bonus", &"value": 15},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"dawn_militia", &"dawn_militia", &"dawn_militia", &"sun_archer", &"radiant_priest"]},
		{"name": "Radiant Champion Sol", "portrait": "warrior_leader", "bonuses": [
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Dawn Crusaders cost -20% Gold", &"key": "unit_discount_dawn_crusader", &"value": 20},
			{&"label": "Starts with Solar Chapter House", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "starting_building": "solar_chapter_house", "army_override": [&"dawn_militia", &"dawn_militia", &"dawn_crusader", &"sun_archer", &"sun_archer"]},
	],
}

const FACTION_DETAILS := {
	&"empire": {
		"traits": "Balanced army, strong constructs, defensive formations, arcane regulation",
		"playstyle": "Build a stable economy, field disciplined legions, and conquer through superior logistics. Your Marching Bastions and Dracarii Riders form the backbone of a formidable war machine.",
		"unique": "Senate system with political dilemmas, Forsaken corruption mechanic",
	},
	&"skulloath": {
		"traits": "Aggressive raiders, fast cavalry, bone magic, corruption-fueled power",
		"playstyle": "Strike hard and fast with mounted raiders and undead horrors. Corruption makes your armies stronger but alienates potential allies. Raid enemy lands for captives and resources.",
		"unique": "Corruption mechanic - higher corruption = stronger armies but worse diplomacy",
	},
	&"gladehost": {
		"traits": "Defensive forest-dwellers, strong ranged units, nature magic, harmony",
		"playstyle": "Defend your sacred groves with thornbow scouts and stag riders. Build harmony with nature to unlock powerful bonuses. Use diplomacy to forge alliances against aggressors.",
		"unique": "Harmony mechanic - maintain balance with nature for combat and diplomacy bonuses",
	},
	&"tainted_jade": {
		"traits": "Serpent warriors, jungle ambushers, taint magic, thrall armies",
		"playstyle": "Spread the Taint across the land, converting captives into thralls for your armies. Use jungle stalkers and vine golems to ambush enemies. Serpent guardians protect your sacred temples.",
		"unique": "Taint Power mechanic - spread corruption to weaken enemies and empower your forces",
	},
	&"shardhorde": {
		"traits": "Crystal swarm, elderbeasts as mobile cities, shard-powered evolution",
		"playstyle": "A unique nomadic faction with no cities. Your elderbeasts serve as mobile bases that recruit units and evolve with buildings. Consume crystal shards to fuel your horde's growth.",
		"unique": "Elderbeasts replace cities - mobile bases that move, fight, recruit, and evolve",
	},
	&"moonspear": {
		"traits": "Moon-blessed warriors, sentinel discipline, nocturnal bonuses",
		"playstyle": "Command disciplined sentinels who draw strength from the moon. Sturdy defensive formations and mystical lunar enchantments make the Moonspear a reliable bulwark.",
		"unique": "Lunar cycle bonuses - combat effectiveness shifts with the passage of turns",
	},
	&"thunderswarm": {
		"traits": "Fast skirmishers, lightning strikes, tribal fury, overwhelming numbers",
		"playstyle": "Overwhelm enemies with speed and fury. Thunderswarm warriors hit hard and move fast, striking before opponents can react. Tribal bonds make your hordes fight harder together.",
		"unique": "Storm Surge - chain attacks grow stronger as more allies engage",
	},
	&"cinderguard": {
		"traits": "Forgeborn infantry, fire magic, heavy armor, industrial economy",
		"playstyle": "Forge an industrial powerhouse and field heavily armored warriors tempered in flame. Cinderguard units are tough to kill and hit like a siege hammer.",
		"unique": "Forge Heat - buildings produce bonus resources when adjacent to other industrial structures",
	},
	&"forsaken": {
		"traits": "Blighted wretches, numbers over quality, dark rituals, desperation",
		"playstyle": "The Forsaken fight with the desperation of the doomed. Cheap, expendable hordes bolstered by dark rituals. What they lack in quality they make up in sheer, terrifying numbers.",
		"unique": "Desperation mechanic - units fight harder when outnumbered or at low HP",
	},
	&"ivoryscar": {
		"traits": "Relic hunters, ancient weapons, adaptive seekers, forbidden knowledge",
		"playstyle": "Seek out and harness ancient relics scattered across the land. Ivoryscar seekers adapt to any challenge, growing stronger as they uncover the secrets of the world.",
		"unique": "Relic Mastery - discovered artifacts provide permanent faction-wide bonuses",
	},
	&"sunblessed": {
		"traits": "Nomadic pilgrims, solar faith, desert endurance, divine blessings",
		"playstyle": "A semi-nomadic people blessed by the Eternal Sun. Pilgrims wander the wastes, founding oases and spreading their faith. Divine blessings make them resilient against the harshest conditions.",
		"unique": "Solar Faith - prayer generates divine favor which powers powerful faction abilities",
	},
}

func _show_faction_select() -> void:
	if _faction_select_panel:
		_faction_select_panel.queue_free()

	# Full-screen container
	_faction_select_panel = Control.new()
	_faction_select_panel.anchor_left = 0
	_faction_select_panel.anchor_top = 0
	_faction_select_panel.anchor_right = 1
	_faction_select_panel.anchor_bottom = 1
	add_child(_faction_select_panel)

	# Background image
	var bg_img := TextureRect.new()
	bg_img.texture = load("res://assets/sprites/ui/factionselectionbackground.png") as Texture2D
	bg_img.anchor_left = 0
	bg_img.anchor_top = 0
	bg_img.anchor_right = 1
	bg_img.anchor_bottom = 1
	bg_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_select_panel.add_child(bg_img)

	# Dark overlay for readability
	var overlay := ColorRect.new()
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.color = Color(0.05, 0.03, 0.08, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_select_panel.add_child(overlay)

	var margin := MarginContainer.new()
	margin.anchor_left = 0
	margin.anchor_top = 0
	margin.anchor_right = 1
	margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_faction_select_panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(outer_vbox)

	# Title
	var title := Label.new()
	title.text = "CHOOSE YOUR FACTION"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	# Main content: faction list (left) + info panel (right)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(hbox)

	# Left side: faction list in a scroll container
	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	left_panel.custom_minimum_size = Vector2(320, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 12)
	left_margin.add_theme_constant_override("margin_right", 12)
	left_margin.add_theme_constant_override("margin_top", 12)
	left_margin.add_theme_constant_override("margin_bottom", 12)
	left_panel.add_child(left_margin)

	var left_outer_vbox := VBoxContainer.new()
	left_outer_vbox.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_outer_vbox)

	var list_title := Label.new()
	list_title.text = "FACTIONS"
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_outer_vbox.add_child(list_title)

	# Scrollable faction list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_outer_vbox.add_child(scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 4)
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(left_vbox)

	var factions: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"shardhorde", &"moonspear", &"thunderswarm", &"cinderguard", &"forsaken", &"ivoryscar", &"sunblessed"]
	_faction_buttons.clear()
	for faction_id in factions:
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data == null:
			continue
		var btn := Button.new()
		btn.text = faction_data.display_name
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 15)
		var captured_id := faction_id
		btn.pressed.connect(_on_faction_list_clicked.bind(captured_id))
		left_vbox.add_child(btn)
		_faction_buttons[faction_id] = btn

	# Tutorial toggle below scroll
	var tutorial_cb := CheckBox.new()
	tutorial_cb.name = "TutorialCheck"
	tutorial_cb.text = "Enable Tutorial"
	tutorial_cb.button_pressed = true
	tutorial_cb.add_theme_font_size_override("font_size", 13)
	tutorial_cb.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	left_outer_vbox.add_child(tutorial_cb)

	# Right side: faction info panel
	var right_panel := PanelContainer.new()
	right_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 20)
	right_margin.add_theme_constant_override("margin_right", 20)
	right_margin.add_theme_constant_override("margin_top", 16)
	right_margin.add_theme_constant_override("margin_bottom", 16)
	right_panel.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	right_margin.add_child(right_vbox)

	# Header row: color bar + faction name
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	right_vbox.add_child(header_hbox)

	_faction_color_rect = ColorRect.new()
	_faction_color_rect.custom_minimum_size = Vector2(6, 36)
	_faction_color_rect.color = Color(0.5, 0.5, 0.5, 0.5)
	header_hbox.add_child(_faction_color_rect)

	_faction_info_label = Label.new()
	_faction_info_label.text = "Select a faction"
	_faction_info_label.add_theme_font_size_override("font_size", 22)
	_faction_info_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	header_hbox.add_child(_faction_info_label)

	var sep_top := HSeparator.new()
	sep_top.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	right_vbox.add_child(sep_top)

	# ── Faction Overview (scrollable) ──
	var desc_scroll := ScrollContainer.new()
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vbox.add_child(desc_scroll)

	var desc_vbox := VBoxContainer.new()
	desc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_vbox.add_theme_constant_override("separation", 10)
	desc_scroll.add_child(desc_vbox)

	_faction_desc_label = Label.new()
	_faction_desc_label.text = "Choose a faction from the list to see details about their playstyle, unique mechanics, and starting position."
	_faction_desc_label.add_theme_font_size_override("font_size", 14)
	_faction_desc_label.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	_faction_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_desc_label)

	_faction_traits_label = Label.new()
	_faction_traits_label.text = ""
	_faction_traits_label.add_theme_font_size_override("font_size", 13)
	_faction_traits_label.add_theme_color_override("font_color", Color(0.7, 0.82, 0.65))
	_faction_traits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_traits_label)

	_faction_region_label = Label.new()
	_faction_region_label.text = ""
	_faction_region_label.add_theme_font_size_override("font_size", 13)
	_faction_region_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.85))
	_faction_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_region_label)

	# ── Leader Selection Section (below faction overview) ──
	var sep_leader := HSeparator.new()
	sep_leader.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	right_vbox.add_child(sep_leader)

	# Leader name + counter
	_leader_name_label = Label.new()
	_leader_name_label.name = "LeaderLabel"
	_leader_name_label.text = ""
	_leader_name_label.add_theme_font_size_override("font_size", 15)
	_leader_name_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	right_vbox.add_child(_leader_name_label)

	# Leader row: portrait (left) + bonuses (right)
	var leader_section := HBoxContainer.new()
	leader_section.add_theme_constant_override("separation", 14)
	right_vbox.add_child(leader_section)

	# Portrait column with arrows below
	var portrait_section := VBoxContainer.new()
	portrait_section.add_theme_constant_override("separation", 4)
	portrait_section.alignment = BoxContainer.ALIGNMENT_CENTER
	leader_section.add_child(portrait_section)

	_faction_emblem = _FactionEmblem.new()
	_faction_emblem.custom_minimum_size = Vector2(160, 200)
	portrait_section.add_child(_faction_emblem)

	var arrow_hbox := HBoxContainer.new()
	arrow_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow_hbox.add_theme_constant_override("separation", 12)
	portrait_section.add_child(arrow_hbox)

	var left_arrow := Button.new()
	left_arrow.text = "< Prev"
	left_arrow.custom_minimum_size = Vector2(65, 26)
	left_arrow.add_theme_font_size_override("font_size", 12)
	left_arrow.pressed.connect(_cycle_leader.bind(-1))
	arrow_hbox.add_child(left_arrow)

	var right_arrow := Button.new()
	right_arrow.text = "Next >"
	right_arrow.custom_minimum_size = Vector2(65, 26)
	right_arrow.add_theme_font_size_override("font_size", 12)
	right_arrow.pressed.connect(_cycle_leader.bind(1))
	arrow_hbox.add_child(right_arrow)

	# Bonus list column (right of portrait)
	var bonus_vbox := VBoxContainer.new()
	bonus_vbox.name = "LeaderBonusVBox"
	bonus_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bonus_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bonus_vbox.add_theme_constant_override("separation", 3)
	leader_section.add_child(bonus_vbox)

	var bonus_header := Label.new()
	bonus_header.text = "Leader Bonuses:"
	bonus_header.add_theme_font_size_override("font_size", 13)
	bonus_header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	bonus_vbox.add_child(bonus_header)

	# Placeholder label (replaced dynamically by _update_leader_display)
	_leader_bonus_label = Label.new()
	_leader_bonus_label.text = ""
	_leader_bonus_label.add_theme_font_size_override("font_size", 12)
	_leader_bonus_label.visible = false
	bonus_vbox.add_child(_leader_bonus_label)

	# Start button (disabled until faction selected)
	_faction_start_btn = Button.new()
	_faction_start_btn.text = "START GAME"
	_faction_start_btn.custom_minimum_size = Vector2(0, 50)
	_faction_start_btn.add_theme_font_size_override("font_size", 20)
	_faction_start_btn.disabled = true
	_faction_start_btn.pressed.connect(_on_faction_confirmed)
	right_vbox.add_child(_faction_start_btn)

	# Bottom bar: cancel button
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(bottom_hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Back to Main Menu"
	cancel_btn.custom_minimum_size = Vector2(240, 48)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): _faction_select_panel.queue_free())
	bottom_hbox.add_child(cancel_btn)

func _on_faction_list_clicked(faction_id: StringName) -> void:
	_selected_faction_id = faction_id
	var faction_data: FactionData = DataManager.get_faction(faction_id)
	if faction_data == null:
		return

	AudioManager.play_sfx(&"ui_click")

	# Highlight selected button
	for fid in _faction_buttons:
		var btn: Button = _faction_buttons[fid]
		if fid == faction_id:
			btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
		else:
			btn.remove_theme_color_override("font_color")

	# Update info panel
	_faction_color_rect.color = faction_data.color
	_faction_info_label.text = faction_data.display_name

	# Update emblem and leader display
	_faction_emblem.faction_color = faction_data.color
	_update_leader_display()

	var details: Dictionary = FACTION_DETAILS.get(faction_id, {})
	var desc_text := faction_data.description
	if details.has("playstyle"):
		desc_text += "\n\n" + details["playstyle"]
	_faction_desc_label.text = desc_text

	if details.has("traits"):
		_faction_traits_label.text = "Traits: " + details["traits"]
	if details.has("unique"):
		_faction_traits_label.text += "\n\nUnique: " + details["unique"]

	# Starting regions
	var region_names: Array[String] = []
	for region_id in faction_data.starting_regions:
		var region := DataManager.get_region(region_id)
		if region:
			region_names.append(region.display_name)
		else:
			region_names.append(str(region_id).capitalize())
	if region_names.size() > 0:
		_faction_region_label.text = "Starting Region: " + ", ".join(region_names)
	else:
		_faction_region_label.text = "Starting Region: Nomadic (no fixed start)"

	_faction_start_btn.disabled = false
	_faction_start_btn.text = "START AS " + faction_data.display_name.to_upper()

func _cycle_leader(delta: int) -> void:
	if _selected_faction_id == &"":
		return
	var leaders: Array = FACTION_LEADERS.get(_selected_faction_id, [])
	if leaders.is_empty():
		return
	AudioManager.play_sfx(&"ui_click")
	var idx: int = _selected_leader_indices.get(_selected_faction_id, 0)
	idx = (idx + delta) % leaders.size()
	if idx < 0:
		idx += leaders.size()
	_selected_leader_indices[_selected_faction_id] = idx
	_update_leader_display()

func _update_leader_display() -> void:
	if _selected_faction_id == &"":
		return
	var leaders: Array = FACTION_LEADERS.get(_selected_faction_id, [])
	var idx: int = _selected_leader_indices.get(_selected_faction_id, 0)
	if leaders.is_empty():
		_faction_emblem.faction_id = _selected_faction_id
		_faction_emblem.queue_redraw()
		if _leader_name_label:
			_leader_name_label.text = GameManager.FACTION_LEADER_NAMES.get(_selected_faction_id, "")
		_clear_bonus_labels()
		return
	var leader: Dictionary = leaders[idx]
	# Update portrait
	_faction_emblem.faction_id = _selected_faction_id
	_faction_emblem.portrait_key = leader.get("portrait", "")
	_faction_emblem.queue_redraw()
	# Update leader name
	if _leader_name_label:
		_leader_name_label.text = "Leader: %s  (%d/%d)" % [leader.get("name", ""), idx + 1, leaders.size()]
	# Update bonus list with individually colored lines
	_clear_bonus_labels()
	var bonus_vbox: VBoxContainer = _faction_select_panel.find_child("LeaderBonusVBox", true, false) if _faction_select_panel else null
	if bonus_vbox == null:
		return
	var bonuses: Array = leader.get("bonuses", [])
	for bonus in bonuses:
		var lbl := Label.new()
		lbl.name = "BonusLine"
		var label_text: String = bonus.get(&"label", "")
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 13)
		var val: int = bonus.get(&"value", 0)
		if val >= 0:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.85, 0.4))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
		bonus_vbox.add_child(lbl)

func _clear_bonus_labels() -> void:
	var bonus_vbox: VBoxContainer = _faction_select_panel.find_child("LeaderBonusVBox", true, false) if _faction_select_panel else null
	if bonus_vbox == null:
		return
	var to_remove: Array[Node] = []
	for child in bonus_vbox.get_children():
		if String(child.name).begins_with("BonusLine"):
			to_remove.append(child)
	for child in to_remove:
		bonus_vbox.remove_child(child)
		child.free()

func _on_faction_confirmed() -> void:
	if _selected_faction_id == &"":
		return
	var tutorial_on := true
	if _faction_select_panel:
		var cb: CheckBox = null
		# Find the tutorial checkbox
		var stack: Array[Node] = [_faction_select_panel]
		while stack.size() > 0:
			var node: Node = stack.pop_back()
			if node.name == "TutorialCheck" and node is CheckBox:
				cb = node
				break
			for child in node.get_children():
				stack.append(child)
		if cb:
			tutorial_on = cb.button_pressed
		_faction_select_panel.queue_free()
	# Get selected leader data before starting game
	var leader_idx: int = _selected_leader_indices.get(_selected_faction_id, 0)
	var leaders: Array = FACTION_LEADERS.get(_selected_faction_id, [])
	var selected_leader: Dictionary = leaders[leader_idx] if leader_idx < leaders.size() else {}

	# Pass army override to GameManager so _init_armies uses it
	var army_override: Array = selected_leader.get("army_override", [])
	if not army_override.is_empty():
		GameManager._leader_army_override = army_override
		GameManager._leader_army_override_faction = _selected_faction_id
	else:
		GameManager._leader_army_override = []
		GameManager._leader_army_override_faction = &""

	GameManager.new_game(_selected_faction_id)
	if GameManager.state:
		GameManager.state.tutorial_enabled = tutorial_on
		# Apply selected leader bonuses and name
		if not selected_leader.is_empty():
			var player_fs: FactionState = GameManager.state.faction_states.get(_selected_faction_id)
			if player_fs:
				# Convert bonus array to flat dict: {key: value, ...}
				var flat_bonuses: Dictionary = {}
				var bonus_arr: Array = selected_leader.get("bonuses", [])
				for b in bonus_arr:
					var k: String = b.get(&"key", "")
					if k != "":
						flat_bonuses[k] = flat_bonuses.get(k, 0) + b.get(&"value", 0)
				player_fs.leader_bonuses = flat_bonuses

				# ── Starting building: place in city with most free slots ──
				var start_bld: String = selected_leader.get("starting_building", "")
				if start_bld != "":
					var best_city: CityState = null
					var best_free_slots: int = -1
					for city_id in GameManager.state.cities:
						var city: CityState = GameManager.state.cities[city_id]
						if city.faction_id == _selected_faction_id:
							var free: int = city.get_available_building_slots()
							if free > best_free_slots:
								best_free_slots = free
								best_city = city
					if best_city and best_free_slots > 0:
						if not best_city.buildings.has(StringName(start_bld)):
							best_city.buildings.append(StringName(start_bld))

				# ── Diplomacy standing bonus ──
				var diplo_bonus: int = flat_bonuses.get("diplomacy_standing", 0)
				if diplo_bonus != 0:
					for other_fid in GameManager.state.faction_states:
						if other_fid != _selected_faction_id and not GameManager.is_npc_faction(other_fid):
							GameManager.diplomacy_system.modify_standing(_selected_faction_id, other_fid, diplo_bonus, "Leader bonus")

				# ── Faction-specific mechanic bonuses ──
				if flat_bonuses.has("harmony_bonus"):
					player_fs.harmony = clampi(player_fs.harmony + int(flat_bonuses["harmony_bonus"]), 0, 100)
				if flat_bonuses.has("storm_fury_bonus"):
					player_fs.storm_fury = clampi(player_fs.storm_fury + int(flat_bonuses["storm_fury_bonus"]), 0, 100)
				if flat_bonuses.has("forge_heat_bonus"):
					player_fs.forge_heat = clampi(player_fs.forge_heat + int(flat_bonuses["forge_heat_bonus"]), 0, 100)
				if flat_bonuses.has("solar_faith_bonus"):
					player_fs.solar_faith = clampi(player_fs.solar_faith + int(flat_bonuses["solar_faith_bonus"]), 0, 100)
				if flat_bonuses.has("taint_power_bonus"):
					player_fs.taint_power = clampi(player_fs.taint_power + int(flat_bonuses["taint_power_bonus"]), 0, 100)
				if flat_bonuses.has("corruption_drift"):
					# corruption_drift is per-turn, store it; initial corruption stays at default
					pass # Already stored in leader_bonuses, applied during turn processing

			# Override leader name with the selected one
			GameManager.FACTION_LEADER_NAMES[_selected_faction_id] = selected_leader.get("name", "")

	# Clean up temporary override state
	GameManager._leader_army_override = []
	GameManager._leader_army_override_faction = &""

# ── Load Menu ───────────────────────────────────────────────

func _show_load_menu() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	panel.anchors_preset = Control.PRESET_CENTER
	panel.size = Vector2(450, 620)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "LOAD GAME"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var slot_names := ["Auto-Save", "Save Slot 1", "Save Slot 2", "Save Slot 3"]
	for i in range(0, 4):
		var slot_box := VBoxContainer.new()
		slot_box.add_theme_constant_override("separation", 2)

		var btn := Button.new()
		var has_save := GameManager.has_save(i)
		btn.disabled = not has_save
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 16)
		var slot := i

		# Show metadata if available
		var meta := GameManager.get_save_metadata(i)
		if has_save and not meta.is_empty():
			btn.text = "%s  —  %s  |  Turn %d  |  %s" % [slot_names[i], meta.get("faction_name", ""), meta.get("turn", 0), meta.get("date", "")]
		else:
			btn.text = slot_names[i]

		btn.pressed.connect(func():
			panel.queue_free()
			GameManager.load_game(slot)
		)
		slot_box.add_child(btn)

		# Metadata subtitle
		if has_save and not meta.is_empty():
			var meta_lbl := Label.new()
			meta_lbl.text = "Saved: %s" % meta.get("timestamp", "Unknown")
			meta_lbl.add_theme_font_size_override("font_size", 10)
			meta_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
			meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot_box.add_child(meta_lbl)

		vbox.add_child(slot_box)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 96)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(func(): panel.queue_free())
	vbox.add_child(cancel)

# ── Faction Emblem Drawing ──────────────────────────────────

class _FactionEmblem extends Control:
	var faction_color: Color = Color(0.3, 0.3, 0.3)
	var faction_id: StringName = &""
	var portrait_key: String = ""

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		# Background with faction tint
		draw_rect(rect, faction_color.darkened(0.75))
		# Border
		draw_rect(rect, faction_color.darkened(0.2), false, 2.0)

		if faction_id == &"":
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(size.x * 0.5 - 10, size.y * 0.5 + 4), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 24, Color(0.4, 0.38, 0.35))
			return

		# Leader portrait image - use portrait_key if set, otherwise fall back to faction default
		var portrait: Texture2D = null
		if portrait_key != "":
			var path := "res://assets/sprites/leaders/%s.png" % portrait_key
			if ResourceLoader.exists(path):
				portrait = load(path) as Texture2D
		if portrait == null:
			portrait = DataManager.get_leader_portrait(faction_id)
		if portrait:
			var inner := Rect2(Vector2(3, 3), size - Vector2(6, 6))
			draw_texture_rect(portrait, inner, false, Color(1, 1, 1, 1))
			# Faction color tint overlay at bottom for name
			draw_rect(Rect2(3, size.y - 26, size.x - 6, 23), Color(faction_color.r * 0.3, faction_color.g * 0.3, faction_color.b * 0.3, 0.75))
		else:
			var inner := Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8))
			draw_rect(inner, faction_color.darkened(0.65))

		# Faction name at bottom
		var font := ThemeDB.fallback_font
		var s := minf(size.x / 100.0, size.y / 130.0)
		var font_size := int(11 * s)
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data:
			draw_string(font, Vector2(4, size.y - 8 * s), faction_data.display_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, font_size, Color(0.95, 0.9, 0.8))
