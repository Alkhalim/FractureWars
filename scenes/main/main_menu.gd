extends Control

@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
var continue_button: Button
var load_button: Button
var options_button: Button

# Faction selection
var _faction_select_panel: Control

func _ready() -> void:
	# THEME RESET (designer 2026-08-04): returning to the main menu from a
	# campaign previously kept whatever faction's chrome was last applied —
	# apply_faction_theme() is only ever called by GameManager.new_game()/
	# load_game(), never reset, so the global theme + UIPalette stayed on
	# e.g. Skulloath's blood-red skin after quitting back to the menu. Reset
	# to neutral HERE, on every main-menu scene entry (fresh boot AND the
	# campaign's "Main Menu" button transition_to_scene() path both run this
	# same _ready()), so the menu always starts from the neutral chrome
	# regardless of what was active before.
	GameManager.apply_faction_theme(&"neutral")

	# Load background image
	var bg_tex := load("res://assets/sprites/ui/MainMenuBackground.png") as Texture2D
	if bg_tex:
		$Background.texture = bg_tex

	# Radial vignette (designer 2026-08-04: background read as "a blank
	# mono-colored slab"). Root cause was NOT source pixelation — inspected
	# MainMenuBackground.png/factionselectionbackground.png directly: both
	# are clean 1536x1024 painted art, not blocky. The flat ~55%-alpha
	# near-black ColorRect overlay (.tscn's old BackgroundOverlay color) was
	# crushing that art's actual color into near-monochrome everywhere. Fix:
	# the flat overlay is now a light uniform tint (.tscn, 0.22) plus this
	# radial vignette layered on top, so the art's color reads through in
	# the open middle while corners/edges still darken enough for text/
	# button contrast. Also enabled mipmaps on both source .import files and
	# set explicit LINEAR_WITH_MIPMAPS filtering (.tscn's Background node)
	# so upscaling to larger-than-1536px windows stays smooth.
	_install_vignette(self, 2)

	# Title has no color override in the .tscn, so it falls through to the
	# theme's default Label color (dark INK_BODY) — unreadable over the dark
	# sky background image. Impressive treatment (designer 2026-08-04):
	# Cinzel display face (HeaderLarge) at 56px (.tscn), parchment-gold
	# fill, a strong dark outline, and a soft drop shadow for depth — same
	# font_outline_color/outline_size pattern battle_v3.gd uses for its
	# player/enemy titles over busy backdrops, pushed further for a
	# marquee-scale title.
	var title_label: Label = $VBoxContainer/Title
	title_label.theme_type_variation = &"HeaderLarge"
	title_label.add_theme_color_override("font_color", UIPalette.ACCENT)
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title_label.add_theme_constant_override("outline_size", 7)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 4)

	# Subtitle: same display-face family, smaller and softer so the
	# hierarchy reads title > subtitle at a glance.
	var subtitle_label: Label = $VBoxContainer/Subtitle
	subtitle_label.theme_type_variation = &"HeaderMedium"
	subtitle_label.add_theme_font_size_override("font_size", 24)
	subtitle_label.add_theme_color_override("font_color", UIPalette.PARCHMENT_ACCENT)
	subtitle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	subtitle_label.add_theme_constant_override("outline_size", 3)

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

	# Add Demo Map button (small map for testing)
	var demo_button := Button.new()
	demo_button.text = "Demo Map"
	demo_button.custom_minimum_size = Vector2(0, 96)
	demo_button.add_theme_font_size_override("font_size", 18)
	demo_button.pressed.connect(_on_demo)
	$VBoxContainer.add_child(demo_button)
	$VBoxContainer.move_child(demo_button, $VBoxContainer.get_children().find(quit_button))

	# Version label in bottom-right corner
	var version_label := Label.new()
	version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.0.0")
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45, 0.6))
	version_label.layout_mode = 1
	version_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	version_label.anchor_left = 1.0
	version_label.anchor_top = 1.0
	version_label.anchor_right = 1.0
	version_label.anchor_bottom = 1.0
	version_label.offset_left = -120.0
	version_label.offset_top = -30.0
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version_label)

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

func _on_demo() -> void:
	AudioManager.play_sfx(&"ui_click")
	# Start a demo game with the Empire on a small map
	GameManager.new_game(&"empire", true)

func _on_quit() -> void:
	get_tree().quit()

# ── Background vignette (shared by the main menu and faction-select) ──────

## Builds and inserts a full-rect radial-gradient TextureRect ("vignette":
## transparent center, dark edges/corners) into `parent`. `at_index`, if
## >= 0, moves it to that child index after adding (so callers can control
## z-order relative to siblings added earlier in a .tscn, e.g. sitting above
## Background/BackgroundOverlay but below VBoxContainer's buttons).
func _install_vignette(parent: Control, at_index: int = -1) -> void:
	var vign := TextureRect.new()
	vign.texture = _make_vignette_texture()
	vign.anchor_left = 0
	vign.anchor_top = 0
	vign.anchor_right = 1
	vign.anchor_bottom = 1
	vign.stretch_mode = TextureRect.STRETCH_SCALE
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vign)
	if at_index >= 0:
		parent.move_child(vign, at_index)

## Procedural radial vignette texture — transparent center fading to a dark
## (UIPalette-derived, not a raw literal) tone at the corners. Built fresh
## per screen open rather than cached: cheap (single small GradientTexture2D)
## and keeps the tone in sync if UIPalette.rebuild() ran since last use.
func _make_vignette_texture() -> GradientTexture2D:
	var dark := UIPalette.PARCHMENT_DARK.darkened(0.75)
	var grad := Gradient.new()
	grad.set_color(0, Color(dark.r, dark.g, dark.b, 0.0))
	grad.set_color(1, Color(dark.r, dark.g, dark.b, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex

# ── Faction Selection ───────────────────────────────────────

var _selected_faction_id: StringName = &""
var _faction_info_label: Label
var _faction_desc_label: Label
var _faction_traits_label: Label
var _faction_unique_label: Label
var _faction_region_label: Label
var _faction_color_rect: ColorRect
var _faction_start_btn: Button
var _faction_buttons: Dictionary = {} # faction_id -> Button
var _faction_emblem: _FactionEmblem
var _map_sketch: _MapSketch
var _leader_name_label: Label
var _leader_bonus_label: Label
var _selected_leader_indices: Dictionary = {} # faction_id -> int

## Every faction the select screen offers. Single source of truth for the
## sidebar row list AND (Task P2) the "START AS X" button width computation
## and the map sketch's region-marker set — all three used to read this same
## set of ids from three separately-typed local literals.
const PLAYABLE_FACTIONS: Array[StringName] = [&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"shardhorde", &"moonspear", &"thunderswarm", &"cinderguard", &"forsaken", &"ivoryscar", &"sunblessed"]

## Fix-round (review defect): floor height for the faction-overview "chip"
## (desc_scroll) so a very short blurb never collapses to a sliver — and the
## chip's own content-margin (all sides), reused both for the stylebox and
## for the height calc that keeps the chip fit to its wrapped text.
const DESC_CHIP_MIN_HEIGHT := 90.0
const DESC_CHIP_CONTENT_MARGIN := 12.0

const FACTION_LEADERS := {
	&"empire": [
		{"name": "Emperor Aurelian III", "portrait": "res://assets/sprites/factions/empire/leaders/nonbiristudios_An_emperor_of_the_empire_purple_and_black_clot_c9c9bdc9-5915-4c09-a954-842fe2313c6c_0.png", "bonuses": [
			{&"label": "Legionaries cost -20% Gold", &"key": "unit_discount_legionary", &"value": 20},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "Starts with Market Square", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "market_square", "army_override": [&"legionary", &"legionary", &"legionary", &"emberlight_auxilia", &"centurion_guard"]},
		{"name": "Senator Livia", "portrait": "res://assets/sprites/factions/empire/leaders/nonbiristudios_A_matriarch_of_the_empire_wealthy_mature_woman_347aa1c6-9295-4967-931f-0b1c9bd61540_1.png", "bonuses": [
			{&"label": "+20% Gold Income", &"key": "income_gold", &"value": 20},
			{&"label": "All upkeep costs -15%", &"key": "upkeep_reduction", &"value": 15},
			{&"label": "+15 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 15},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"levy_conscripts", &"levy_conscripts", &"legionary", &"border_mercenaries", &"border_mercenaries"]},
		{"name": "General Crassus", "portrait": "res://assets/sprites/factions/empire/leaders/nonbiristudios_A_senator_of_the_empire_ancient_roman_flat_fan_6672dc4f-bdc4-4124-8eeb-3cdf367f08d7_2.png", "bonuses": [
			{&"label": "Elite Legionaries cost -25% Gold", &"key": "unit_discount_elite_legionaries", &"value": 25},
			{&"label": "+8% Army Attack", &"key": "army_attack", &"value": 8},
			{&"label": "Starts with Shieldwall Grounds", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "starting_building": "shieldwall_grounds", "army_override": [&"legionary", &"legionary", &"elite_legionaries", &"emberlight_auxilia", &"border_mercenaries"]},
	],
	&"skulloath": [
		{"name": "Khan Borlag the Pale", "portrait": "res://assets/sprites/factions/skulloath/leaders/nonbiristudios_War_Khan_evil_mongolian_hun_flat_fantasy_illus_0db13fcf-8787-446b-93de-3b8a276577d4_3.png", "bonuses": [
			{&"label": "Steppe Riders cost -20% Gold", &"key": "unit_discount_steppe_rider", &"value": 20},
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Starts with Beast Pens", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Food Income", &"key": "income_food", &"value": -15},
		], "starting_building": "beast_pens", "army_override": [&"warband_raider", &"steppe_rider", &"steppe_rider", &"steppe_archers", &"bonecaller"]},
		{"name": "Bone Witch Vashra", "portrait": "res://assets/sprites/factions/skulloath/leaders/nonbiristudios_female_Khan_muscular_scarred_undercut_shaved_s_fd657081-2e34-4648-82b5-39328907f5bd_1.png", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Ancestor Spirits cost -25% Gold", &"key": "unit_discount_ancestor_spirit", &"value": 25},
			{&"label": "Corruption drifts -1 per turn", &"key": "corruption_drift", &"value": -1},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "army_override": [&"warband_raider", &"warband_raider", &"bonecaller", &"pale_touched", &"ancestor_spirit"]},
		{"name": "Warlord Dregg", "portrait": "res://assets/sprites/factions/skulloath/leaders/nonbiristudios_Frail_Shaman_thin_anorexic_evil_mongolian_hun__981c4ada-24aa-4c7c-9af1-5ea6ddf85acc_1.png", "bonuses": [
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "+15% Iron Income", &"key": "income_iron", &"value": 15},
			{&"label": "Starts with War Forge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "war_forge", "army_override": [&"warband_raider", &"warband_raider", &"warband_raider", &"steppe_archers", &"steppe_archers"]},
	],
	&"gladehost": [
		{"name": "Archdruid Thalwen", "portrait": "res://assets/sprites/factions/gladehost/leaders/nonbiristudios_A_samurai_warlord_of_the_Gladehost_Japanese-Ce_69d5aded-446f-4a34-b5fe-c84f50f07f1c_2.png", "bonuses": [
			{&"label": "+10 Harmony at start", &"key": "harmony_bonus", &"value": 10},
			{&"label": "Dryads cost -20% Gold", &"key": "unit_discount_dryad", &"value": 20},
			{&"label": "Starts with Sacred Grove", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Attack", &"key": "army_attack", &"value": -8},
		], "starting_building": "sacred_grove", "army_override": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"dryad", &"hawk_scout"]},
		{"name": "Warden Elowen", "portrait": "res://assets/sprites/factions/thornwardens/leaders/nonbiristudios_A_dryad_of_the_Gladehost_bark_skin_female_woad_9dc5becd-4c10-4858-91a8-6cdd287fc30e_1.png", "bonuses": [
			{&"label": "Stag Riders cost -20% Gold", &"key": "unit_discount_stag_rider", &"value": 20},
			{&"label": "+8% Army Defense", &"key": "army_defense", &"value": 8},
			{&"label": "+10% Food Income", &"key": "income_food", &"value": 10},
			{&"label": "-10% Gold Income", &"key": "income_gold", &"value": -10},
		], "army_override": [&"grove_warden", &"grove_warden", &"stag_rider", &"stag_rider", &"thornbow_scout"]},
		{"name": "Grove Speaker Faelen", "portrait": "res://assets/sprites/factions/thornwardens/leaders/nonbiristudios_A_treefolk_druid_of_the_Gladehost_Japanese-Cel_28ea0af1-1ec1-472e-9cc2-c5d4969f9512_0.png", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+15 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 15},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-10% Army HP", &"key": "army_hp", &"value": -10},
		], "army_override": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"hawk_scout", &"hawk_scout"]},
	],
	&"moonspear": [
		{"name": "High Priestess Selara", "portrait": "res://assets/sprites/factions/moonspear/leaders/nonbiristudios_ancient_greek_moon_priestess_flat_fantasy_illu_79f0156c-9193-4933-a30c-d5885d8bed89_1.png", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Starweavers cost -25% Gold", &"key": "unit_discount_starweaver", &"value": 25},
			{&"label": "Starts with Moon Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "starting_building": "moon_shrine", "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"lunar_archer", &"starweaver", &"moonhound"]},
		{"name": "Moon Guardian Theron", "portrait": "res://assets/sprites/factions/skalvar_watch/leaders/nonbiristudios_A_sneaky_smuggler_of_the_Gladehost_Japanese-Ce_3c675508-36d7-4352-bd6a-12d6c43138b2_3.png", "bonuses": [
			{&"label": "Silverguard cost -20% Gold", &"key": "unit_discount_silverguard", &"value": 20},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Starts with Sentinel Hall", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Gold Income", &"key": "income_gold", &"value": -10},
		], "starting_building": "sentinel_hall", "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"moonspear_sentinel", &"silverguard", &"lunar_archer"]},
		{"name": "Starweaver Lunara", "portrait": "res://assets/sprites/factions/miststriders/leaders/nonbiristudios_A_dryad_of_the_Gladehost_bark_skin_female_woad_06d096e4-12ea-4eb5-acee-a7f0a1d00fd7_3.png", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-8% Army Attack", &"key": "army_attack", &"value": -8},
		], "army_override": [&"moonspear_sentinel", &"moonspear_sentinel", &"lunar_archer", &"lunar_archer", &"frost_volunteer"]},
	],
	&"thunderswarm": [
		{"name": "Warchief Groth", "portrait": "res://assets/sprites/factions/thunderswarm/leaders/nonbiristudios_angry_norse_angel_flat_fantasy_illustration_gr_29f2042f-913f-4cd7-a2a9-48af71c9e2bd_3.png", "bonuses": [
			{&"label": "+12% Army Attack", &"key": "army_attack", &"value": 12},
			{&"label": "Warriors cost -15% Gold", &"key": "unit_discount_thunderswarm_warrior", &"value": 15},
			{&"label": "+10 Storm Fury at start", &"key": "storm_fury_bonus", &"value": 10},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"highland_skirmisher"]},
		{"name": "Storm Shaman Kira", "portrait": "res://assets/sprites/factions/thunderswarm/leaders/nonbiristudios_ancient_greek_moon_priestess_flat_fantasy_illu_f0827001-866b-4bd4-aa33-5bf2d40cd888_3.png", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Storm Hounds cost -25% Gold", &"key": "unit_discount_storm_hound", &"value": 25},
			{&"label": "Starts with Lightning Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-8% Army Defense", &"key": "army_defense", &"value": -8},
		], "starting_building": "lightning_shrine", "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"storm_hound", &"storm_hound", &"storm_shaman"]},
		{"name": "Thundercaller Borak", "portrait": "res://assets/sprites/factions/thunderswarm/leaders/nonbiristudios_norse_dragon_with_reindeer_horns_flat_fantasy__dcb3d6d2-32f9-4901-855d-54a9b110c2e8_3.png", "bonuses": [
			{&"label": "+15% Iron Income", &"key": "income_iron", &"value": 15},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Starts with Storm Forge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "storm_forge", "army_override": [&"thunderswarm_warrior", &"thunderswarm_warrior", &"thunderswarm_warrior", &"highland_skirmisher", &"highland_skirmisher"]},
	],
	&"tainted_jade": [
		{"name": "Serpent Queen Ixchala", "portrait": "res://assets/sprites/factions/blightcoven/leaders/nonbiristudios_female_bog_witch_persian_ancient_roman_deathly_f7c6af81-c998-421c-b4e7-a9db122950c4_2.png", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Jade Fangs cost -20% Gold", &"key": "unit_discount_jade_fang", &"value": 20},
			{&"label": "+5 Taint Power at start", &"key": "taint_power_bonus", &"value": 5},
			{&"label": "-10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": -10},
		], "army_override": [&"jade_fang", &"jade_fang", &"jade_fang", &"jungle_stalker", &"coatl_shaman"]},
		{"name": "Venom Lord Sethis", "portrait": "res://assets/sprites/factions/tainted_jade/leaders/nonbiristudios_ancient_aztec_evil_mushroom_cultist_flat_fanta_5ccc3098-194b-4de8-b1e1-2dbd246f4fc9_2.png", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "+8% Army Defense", &"key": "army_defense", &"value": 8},
			{&"label": "Starts with Serpent Pit", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "serpent_pit", "army_override": [&"jade_fang", &"jade_fang", &"jungle_stalker", &"thrall_swarm", &"thrall_swarm"]},
		{"name": "Jade Seer Mayana", "portrait": "res://assets/sprites/factions/miststriders/leaders/nonbiristudios_A_dryad_of_the_Gladehost_bark_skin_female_woad_b6119727-7323-4668-92e1-07ea04449f27_3.png", "bonuses": [
			{&"label": "+15% Gold Income", &"key": "income_gold", &"value": 15},
			{&"label": "+10% Shard Essence Income", &"key": "income_shard", &"value": 10},
			{&"label": "All upkeep costs -10%", &"key": "upkeep_reduction", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"jade_fang", &"jade_fang", &"coatl_shaman", &"coatl_shaman", &"thrall_swarm"]},
	],
	&"cinderguard": [
		{"name": "Warden-Commander Valdris", "portrait": "res://assets/sprites/factions/ashbound/leaders/nonbiristudios_War_Khan_demonic_mongolian_hun_flat_fantasy_il_a866c270-2af9-44b6-95bd-d6856bdaf8ba_0.png", "bonuses": [
			{&"label": "+20% Iron Income", &"key": "income_iron", &"value": 20},
			{&"label": "Wardens cost -15% Gold", &"key": "unit_discount_cinderguard_warden", &"value": 15},
			{&"label": "Starts with Ember Foundry", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "ember_foundry", "army_override": [&"cinderguard_warden", &"cinderguard_warden", &"cinderguard_warden", &"ember_crossbow", &"ember_crossbow"]},
		{"name": "Border Captain Ignis", "portrait": "res://assets/sprites/factions/miststriders/leaders/nonbiristudios_A_sneaky_smuggler_of_the_Gladehost_Japanese-Ce_c829e141-3e02-4c1d-ba14-630fceb748aa_1.png", "bonuses": [
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "+8% Army HP", &"key": "army_hp", &"value": 8},
			{&"label": "+10 Vigilance at start", &"key": "border_vigilance_bonus", &"value": 10},
			{&"label": "-15% Gold Income", &"key": "income_gold", &"value": -15},
		], "army_override": [&"cinderguard_warden", &"cinderguard_warden", &"cinderguard_warden", &"cinderguard_warden", &"ember_crossbow"]},
		{"name": "Ember Priestess Pyra", "portrait": "res://assets/sprites/factions/ashbound/leaders/nonbiristudios_war-succubus_mongolian_pelt_armor_demonic_mong_caf41ae1-7663-4e69-86ea-e04dea06bb3c_2.png", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "Starts with Flame Sanctum", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Iron Income", &"key": "income_iron", &"value": -10},
		], "starting_building": "flame_sanctum", "army_override": [&"cinderguard_warden", &"cinderguard_warden", &"ember_crossbow", &"ember_mage", &"cinder_militia"]},
	],
	&"forsaken": [
		{"name": "Lord Noctis", "portrait": "res://assets/sprites/factions/forsaken/leaders/nonbiristudios_persian_ancient_roman_vampire_lord_aristocrati_5b7625b0-df62-45c2-b984-cf8021939b56_2.png", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "Thralls cost -30% Gold", &"key": "unit_discount_shadow_thrall", &"value": 30},
			{&"label": "Starts with Necromancer Sanctum", &"key": "starting_building", &"value": 0},
			{&"label": "-10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": -10},
		], "starting_building": "necromancer_sanctum", "army_override": [&"shadow_thrall", &"shadow_thrall", &"shadow_thrall", &"shadow_thrall", &"death_mage"]},
		{"name": "Countess Neshara", "portrait": "res://assets/sprites/factions/bloodthrone/leaders/nonbiristudios_persian_ancient_roman_vampire_queen_aristocrat_9d095022-e3b5-45ab-8212-72ecad11d93e_2.png", "bonuses": [
			{&"label": "+15% Food Income", &"key": "income_food", &"value": 15},
			{&"label": "Bat Swarms cost -25% Gold", &"key": "unit_discount_bat_swarm", &"value": 25},
			{&"label": "+8% Army HP", &"key": "army_hp", &"value": 8},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"shadow_thrall", &"shadow_thrall", &"bat_swarm", &"bat_swarm", &"bat_swarm"]},
		{"name": "Void Prophet Malachar", "portrait": "res://assets/sprites/factions/blightcoven/leaders/nonbiristudios_persian_ancient_roman_vampire_lord_aristocrati_5b7625b0-df62-45c2-b984-cf8021939b56_2.png", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "Starts with Shadow Shrine", &"key": "starting_building", &"value": 0},
			{&"label": "-15% Army Defense", &"key": "army_defense", &"value": -15},
		], "starting_building": "blighted_shrine", "army_override": [&"shadow_thrall", &"shadow_thrall", &"death_mage", &"death_mage", &"bat_swarm"]},
	],
	&"ivoryscar": [
		{"name": "Oracle Medusa", "portrait": "res://assets/sprites/factions/ivoryscar/leaders/nonbiristudios_ancient_egyptian_female_Angel_that_is_half_dem_0caed725-5289-49dd-b0e9-9d6707de1a4f_0.png", "bonuses": [
			{&"label": "+20% Gold Income", &"key": "income_gold", &"value": 20},
			{&"label": "+10% Shard Essence Income", &"key": "income_shard", &"value": 10},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"ivoryscar_seeker", &"ivoryscar_seeker", &"scarab_swarm", &"scarab_swarm", &"relic_skirmisher"]},
		{"name": "Tomb King Ankaris", "portrait": "res://assets/sprites/factions/aurentis_guard/leaders/nonbiristudios_dockmaster_venetian_flat_fantasy_illustration__ecf9cd06-bada-4081-b765-cf4617dd9a6f_3.png", "bonuses": [
			{&"label": "+12% Army Defense", &"key": "army_defense", &"value": 12},
			{&"label": "Tomb Guards cost -20% Gold", &"key": "unit_discount_tomb_guard", &"value": 20},
			{&"label": "Starts with Bone Arsenal", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		], "starting_building": "bone_arsenal", "army_override": [&"ivoryscar_seeker", &"tomb_guard", &"tomb_guard", &"scarab_swarm", &"bone_archer"]},
		{"name": "Relic Seeker Dara", "portrait": "res://assets/sprites/factions/aurentis_guard/leaders/nonbiristudios_A_matriarch_of_the_empire_wealthy_mature_woman_7a3cece7-4e24-4d58-8e35-a5c213b3f8a5_3.png", "bonuses": [
			{&"label": "+20% Shard Essence Income", &"key": "income_shard", &"value": 20},
			{&"label": "+8% Army Speed", &"key": "army_speed", &"value": 8},
			{&"label": "Starts with Seekers Lodge", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Army Defense", &"key": "army_defense", &"value": -10},
		], "starting_building": "seekers_lodge", "army_override": [&"ivoryscar_seeker", &"ivoryscar_seeker", &"ivoryscar_seeker", &"scarab_swarm", &"relic_skirmisher"]},
	],
	&"shardhorde": [
		{"name": "The Crystalmind", "portrait": "res://assets/sprites/factions/shardhorde/leaders/nonbiristudios_stone_age_tribe_shaman_flat_fantasy_illustrati_0137b5e3-d245-407e-bc40-1971df55923a_3.png", "bonuses": [
			{&"label": "+15% Shard Essence Income", &"key": "income_shard", &"value": 15},
			{&"label": "+8% Army Attack", &"key": "army_attack", &"value": 8},
			{&"label": "Elderbeast HP +10%", &"key": "elderbeast_hp", &"value": 10},
			{&"label": "-10% Army Defense", &"key": "army_defense", &"value": -10},
		]},
		{"name": "Shard Matriarch", "portrait": "res://assets/sprites/factions/salt_reavers/leaders/nonbiristudios_female_Khan_muscular_scarred_evil_mongolian_hu_54966e97-220a-4135-ad26-fc3ec829edbd_1.png", "bonuses": [
			{&"label": "+12% Army HP", &"key": "army_hp", &"value": 12},
			{&"label": "+10% Army Defense", &"key": "army_defense", &"value": 10},
			{&"label": "Elderbeast Regen +2/turn", &"key": "elderbeast_regen", &"value": 2},
			{&"label": "-10% Army Speed", &"key": "army_speed", &"value": -10},
		]},
	],
	&"sunblessed": [
		{"name": "Solar Archon Kael", "portrait": "res://assets/sprites/factions/sunblessed/leaders/nonbiristudios_ancient_mayan_grand_mage_friendly_educator_fla_c896c925-982e-441b-8e78-fb509604e2e6_2.png", "bonuses": [
			{&"label": "+10% Army Attack", &"key": "army_attack", &"value": 10},
			{&"label": "+10 Solar Faith at start", &"key": "solar_faith_bonus", &"value": 10},
			{&"label": "Starts with Sunfire Altar", &"key": "starting_building", &"value": 0},
			{&"label": "-10% Food Income", &"key": "income_food", &"value": -10},
		], "starting_building": "sunfire_altar", "army_override": [&"dawn_militia", &"dawn_militia", &"sun_archer", &"sun_archer", &"dawn_crusader"]},
		{"name": "Dawn Priestess Amara", "portrait": "res://assets/sprites/factions/aurentis_guard/leaders/nonbiristudios_A_sneaky_smuggler_of_the_Gladehost_Japanese-Ce_dd68cf67-57e4-434f-9977-edb6dfaba618_0.png", "bonuses": [
			{&"label": "+15% Food Income", &"key": "income_food", &"value": 15},
			{&"label": "+15 Solar Faith at start", &"key": "solar_faith_bonus", &"value": 15},
			{&"label": "+10 Diplomacy with all factions", &"key": "diplomacy_standing", &"value": 10},
			{&"label": "-10% Army Attack", &"key": "army_attack", &"value": -10},
		], "army_override": [&"dawn_militia", &"dawn_militia", &"dawn_militia", &"sun_archer", &"radiant_priest"]},
		{"name": "Radiant Champion Sol", "portrait": "res://assets/sprites/factions/salt_reavers/leaders/nonbiristudios_mayan_chinese_evil_cultist_leader_flat_fantasy_20698cd7-b944-4bc2-bc24-22593f60f1a6_1.png", "bonuses": [
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
		"traits": "Exiled vampire aristocrats, undead hordes, necromancy, underground caverns",
		"playstyle": "The Forsaken fight with the ruthlessness of immortal exiles. Cheap, expendable undead hordes bolstered by blood magic and necromancy. What they lack in quality they make up in sheer, terrifying numbers.",
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
	bg_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_select_panel.add_child(bg_img)

	# Dark overlay for readability — lighter flat base than before (see the
	# vignette comment in _ready()); the radial vignette added right after
	# does the heavy lifting so the marble art's color still reads through.
	var overlay := ColorRect.new()
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.color = Color(0.05, 0.03, 0.08, 0.22)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_select_panel.add_child(overlay)
	_install_vignette(_faction_select_panel)

	var margin := MarginContainer.new()
	margin.anchor_left = 0
	margin.anchor_top = 0
	margin.anchor_right = 1
	margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	_faction_select_panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(outer_vbox)

	# Title
	var title := Label.new()
	title.text = "CHOOSE YOUR FACTION"
	title.theme_type_variation = &"HeaderLarge"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UIPalette.PARCHMENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	# Main content: faction list (left) + info panel (right)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(hbox)

	# Left side: faction list in a scroll container
	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	left_panel.custom_minimum_size = Vector2(290, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_panel)

	# Panel style already provides its own content margins — no extra margin needed
	var left_outer_vbox := VBoxContainer.new()
	left_outer_vbox.add_theme_constant_override("separation", 4)
	left_panel.add_child(left_outer_vbox)

	var list_title := Label.new()
	list_title.text = "FACTIONS"
	list_title.add_theme_font_size_override("font_size", 15)
	list_title.add_theme_color_override("font_color", UIPalette.INK_TITLE)
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

	# Faction rows, fully faction-styled (designer 2026-08-04): each button
	# wears ITS OWN faction's baked chrome (btn_normal/hover/pressed/
	# disabled StyleBoxTexture overrides sourced from
	# GameManager.make_faction_button_stylebox — per-button, NOT a per-row
	# theme rebuild) plus that faction's seal as a row icon and a
	# heraldry-tinted name. toggle_mode + a shared ButtonGroup gives a
	# persistent "selected" visual (the pressed state's baked texture is
	# heraldry-FILLED) without hand-rolled highlight bookkeeping.
	var faction_group := ButtonGroup.new()
	_faction_buttons.clear()
	for faction_id in PLAYABLE_FACTIONS:
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data == null:
			continue
		var btn := Button.new()
		btn.text = faction_data.display_name
		btn.custom_minimum_size = Vector2(0, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		btn.toggle_mode = true
		btn.button_group = faction_group
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.icon = _load_faction_seal(faction_id)
		if btn.icon:
			btn.add_theme_constant_override("icon_max_width", 24)
			btn.add_theme_constant_override("h_separation", 8)

		var normal_sb := GameManager.make_faction_button_stylebox(faction_id, "btn_normal")
		if normal_sb:
			var hover_sb := GameManager.make_faction_button_stylebox(faction_id, "btn_hover")
			var pressed_sb := GameManager.make_faction_button_stylebox(faction_id, "btn_pressed", true)
			var disabled_sb := GameManager.make_faction_button_stylebox(faction_id, "btn_disabled")
			btn.add_theme_stylebox_override("normal", normal_sb)
			btn.add_theme_stylebox_override("hover", hover_sb if hover_sb else normal_sb)
			btn.add_theme_stylebox_override("pressed", pressed_sb if pressed_sb else normal_sb)
			btn.add_theme_stylebox_override("hover_pressed", pressed_sb if pressed_sb else normal_sb)
			btn.add_theme_stylebox_override("disabled", disabled_sb if disabled_sb else normal_sb)
			btn.add_theme_stylebox_override("focus", hover_sb if hover_sb else normal_sb)

		# heraldry(fid) — not ACCENT/INK_TITLE — for the normal/hover text: the
		# baked btn_normal fill is light parchment, so a dark faction-specific
		# ink tone stays legible AND doubles as the row's color identity.
		# btn_pressed flips to a heraldry-FILLED background per the
		# generator's own "light text expected" note, so the pressed/selected
		# state needs light text instead or it goes invisible on its own fill.
		var tint := UIPalette.heraldry(faction_id)
		btn.add_theme_color_override("font_color", tint)
		btn.add_theme_color_override("font_hover_color", tint.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", UIPalette.PARCHMENT)
		btn.add_theme_color_override("font_hover_pressed_color", UIPalette.PARCHMENT)
		btn.add_theme_color_override("font_focus_color", tint)

		var captured_id := faction_id
		btn.pressed.connect(_on_faction_list_clicked.bind(captured_id))
		left_vbox.add_child(btn)
		_faction_buttons[faction_id] = btn

	# Tutorial toggle below scroll
	var tutorial_cb := CheckBox.new()
	tutorial_cb.name = "TutorialCheck"
	tutorial_cb.text = "Enable Tutorial"
	tutorial_cb.button_pressed = true
	tutorial_cb.add_theme_font_size_override("font_size", 14)
	tutorial_cb.add_theme_color_override("font_color", UIPalette.INK_BODY)
	# Root-caused (Task 8 coherence pass): button_pressed defaults true (tutorial
	# ON by default), and CheckBox has no CheckBox-specific "font_pressed_color"
	# in either theme builder, so it class-hierarchy-cascades to Button's
	# font_pressed_color = UIPalette.PARCHMENT (light — correct for a
	# heraldry-filled PRESSED BUTTON, but CheckBox never gets a fill; its
	# "pressed"/checked state is StyleBoxEmpty, so it's still sitting on this
	# panel's light parchment). Light-on-light made the whole label vanish
	# despite the font_color override above (which only covers the unchecked
	# state). This is the only CheckBox in the game that both defaults checked
	# AND sits directly on light parchment (campaign_hud.gd's checkboxes are
	# either unchecked by default or sit on dark chips/dialog backdrops, where
	# the light pressed color is correct) — fixed locally rather than in the
	# shared theme to avoid regressing those correct cases.
	tutorial_cb.add_theme_color_override("font_pressed_color", UIPalette.INK_BODY)
	tutorial_cb.add_theme_color_override("font_hover_pressed_color", UIPalette.INK_TITLE)
	tutorial_cb.add_theme_color_override("font_focus_color", UIPalette.INK_BODY)
	left_outer_vbox.add_child(tutorial_cb)

	# Right side: faction info panel
	var right_panel := PanelContainer.new()
	right_panel.add_theme_stylebox_override("panel", GameManager.make_panel_style())
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_panel)

	# Panel style already provides its own content margins — no extra margin needed
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)

	# Header row: color bar + faction name
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	right_vbox.add_child(header_hbox)

	_faction_color_rect = ColorRect.new()
	_faction_color_rect.custom_minimum_size = Vector2(6, 40)
	_faction_color_rect.color = Color(0.5, 0.5, 0.5, 0.5)
	header_hbox.add_child(_faction_color_rect)

	_faction_info_label = Label.new()
	_faction_info_label.text = "Select a faction"
	_faction_info_label.theme_type_variation = &"HeaderLarge"
	_faction_info_label.add_theme_font_size_override("font_size", 26)
	_faction_info_label.add_theme_color_override("font_color", UIPalette.INK_TITLE)
	header_hbox.add_child(_faction_info_label)

	var sep_top := HSeparator.new()
	sep_top.add_theme_color_override("separator_color", Color(UIPalette.CHIP_BORDER, 0.5))
	right_vbox.add_child(sep_top)

	# ── LAYOUT REWORK (designer 2026-08-04): the info area splits into a
	# left two-thirds (faction bonus list/details + map sketch) and a right
	# third (leader portrait + leader bonuses). size_flags_stretch_ratio
	# 2.0 : 1.0 inside this HBoxContainer gives the exact 2/3 : 1/3 split. ──
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(content_hbox)

	# ── Left two-thirds: faction overview + map sketch ──
	var content_left := VBoxContainer.new()
	content_left.add_theme_constant_override("separation", 8)
	content_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_left.size_flags_stretch_ratio = 2.0
	content_hbox.add_child(content_left)

	# Faction overview (fix round, review defect: this chip previously used
	# SIZE_EXPAND_FILL, which forced it to fill ALL remaining vertical space
	# in content_left regardless of how little text it held — rendering as
	# a small paragraph on top of a large empty dark rectangle. Fix: SIZE_FILL
	# (shrink to content) with a modest floor for very short blurbs; the
	# actual height is kept in sync with the wrapped text via the
	# desc_vbox.resized handler below (ScrollContainer does not propagate a
	# scrolling child's minimum size to its own — confirmed empirically —
	# so the chip's height must be set explicitly). The freed space is
	# reallocated to the map sketch below (see its SIZE_EXPAND_FILL). Dark
	# chip backdrop keeps the description text off the raw leather.
	var desc_scroll := ScrollContainer.new()
	desc_scroll.size_flags_vertical = Control.SIZE_FILL
	desc_scroll.custom_minimum_size = Vector2(0, DESC_CHIP_MIN_HEIGHT)
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var desc_chip := StyleBoxFlat.new()
	desc_chip.bg_color = UIPalette.CHIP_BG
	desc_chip.set_corner_radius_all(5)
	desc_chip.set_content_margin_all(DESC_CHIP_CONTENT_MARGIN)
	desc_scroll.add_theme_stylebox_override("panel", desc_chip)
	content_left.add_child(desc_scroll)

	var desc_vbox := VBoxContainer.new()
	desc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_vbox.add_theme_constant_override("separation", 8)
	desc_scroll.add_child(desc_vbox)
	# Re-fit the chip to its wrapped content every time desc_vbox's own
	# computed minimum size changes (label text set/replaced, or width
	# settles after the first layout pass) — resized fires after Godot has
	# already re-wrapped the Labels at the container's current width, so
	# get_combined_minimum_size() below reflects the real line count.
	desc_vbox.resized.connect(func():
		var needed: float = desc_vbox.get_combined_minimum_size().y + DESC_CHIP_CONTENT_MARGIN * 2.0
		desc_scroll.custom_minimum_size.y = maxf(DESC_CHIP_MIN_HEIGHT, needed)
	)

	_faction_desc_label = Label.new()
	_faction_desc_label.text = "Choose a faction from the list to see details about their playstyle, unique mechanics, and starting position."
	_faction_desc_label.add_theme_font_size_override("font_size", 16)
	_faction_desc_label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.72))
	_faction_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_desc_label)

	_faction_traits_label = Label.new()
	_faction_traits_label.text = ""
	_faction_traits_label.add_theme_font_size_override("font_size", 16)
	_faction_traits_label.add_theme_color_override("font_color", Color(0.7, 0.82, 0.65))
	_faction_traits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_traits_label)

	_faction_unique_label = Label.new()
	_faction_unique_label.text = ""
	_faction_unique_label.add_theme_font_size_override("font_size", 16)
	_faction_unique_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	_faction_unique_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_unique_label)

	_faction_region_label = Label.new()
	_faction_region_label.text = ""
	_faction_region_label.add_theme_font_size_override("font_size", 16)
	_faction_region_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	_faction_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_faction_region_label)

	# ── MAP SKETCH (designer 2026-08-04): rough stylized parchment sketch
	# of the world showing the selected faction's starting position. Drawn
	# directly from MapGenerator's region/anchor data (LANDMASS_BLOBS for
	# the silhouette, REGION_SEEDS for marker positions) rather than a live
	# per-campaign generation — every real campaign map rerolls a random
	# seed (MapGenerator._map_salt), so there is no single "the map" to bake
	# a thumbnail from before a game exists. This reads the SAME seed-space
	# data the generator anchors every campaign's starting regions to, so
	# the marker position is accurate to where the faction will actually
	# start; the coastline/terrain around it is an approximate sketch, not
	# the exact generated shape (documented in the task report). ──
	var sketch_caption := Label.new()
	sketch_caption.text = "Starting Position (rough sketch)"
	sketch_caption.add_theme_font_size_override("font_size", 13)
	sketch_caption.add_theme_color_override("font_color", Color(UIPalette.INK_BODY, 0.85))
	content_left.add_child(sketch_caption)

	_map_sketch = _MapSketch.new()
	# Fix round (review defect): 170px used to be a FIXED height (SIZE_FILL,
	# the container default) while desc_scroll above ate all the flexible
	# space via SIZE_EXPAND_FILL. Now that the chip shrinks to its content
	# (see desc_scroll above), the sketch is the one that should absorb the
	# freed space — 170px becomes a MINIMUM via SIZE_EXPAND_FILL, so the
	# sketch actually grows to fill content_left's remaining height instead
	# of leaving it as a second empty band below a short chip.
	_map_sketch.custom_minimum_size = Vector2(0, 170)
	_map_sketch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_sketch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_sketch.playable_factions = PLAYABLE_FACTIONS
	for seal_fid in PLAYABLE_FACTIONS:
		var seal_tex := _load_faction_seal(seal_fid)
		if seal_tex:
			_map_sketch.seal_textures[seal_fid] = seal_tex
	content_left.add_child(_map_sketch)

	# ── Right third: leader portrait + leader bonuses ──
	var content_right := PanelContainer.new()
	var leader_style := StyleBoxFlat.new()
	leader_style.bg_color = Color(UIPalette.CHIP_BG, 0.7)
	leader_style.border_color = Color(UIPalette.CHIP_BORDER, 0.5)
	leader_style.set_border_width_all(1)
	leader_style.set_corner_radius_all(4)
	leader_style.set_content_margin_all(12)
	content_right.add_theme_stylebox_override("panel", leader_style)
	content_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_right.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(content_right)

	var leader_inner_vbox := VBoxContainer.new()
	leader_inner_vbox.add_theme_constant_override("separation", 8)
	# Fix round (review, MINOR): content_right matches content_left's full
	# height for column symmetry, but the leader portrait + bonus chips
	# rarely fill it — explicit top alignment (BoxContainer default, made
	# explicit here rather than left implicit) plus a trailing SIZE_EXPAND_
	# FILL spacer (added as the last child below) makes the leftover space
	# read as a deliberate bottom margin instead of a stray empty panel.
	leader_inner_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	content_right.add_child(leader_inner_vbox)

	# Leader name + counter
	_leader_name_label = Label.new()
	_leader_name_label.name = "LeaderLabel"
	_leader_name_label.text = ""
	_leader_name_label.add_theme_font_size_override("font_size", 18)
	_leader_name_label.add_theme_color_override("font_color", UIPalette.PARCHMENT)
	_leader_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leader_inner_vbox.add_child(_leader_name_label)

	# Portrait, centered, with prev/next arrows below — the column is only
	# 1/3 of the info panel now, so portrait + bonuses stack vertically
	# instead of sitting side by side.
	var portrait_section := VBoxContainer.new()
	portrait_section.add_theme_constant_override("separation", 4)
	portrait_section.alignment = BoxContainer.ALIGNMENT_CENTER
	leader_inner_vbox.add_child(portrait_section)

	_faction_emblem = _FactionEmblem.new()
	_faction_emblem.custom_minimum_size = Vector2(200, 240)
	_faction_emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_section.add_child(_faction_emblem)

	var arrow_hbox := HBoxContainer.new()
	arrow_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow_hbox.add_theme_constant_override("separation", 12)
	portrait_section.add_child(arrow_hbox)

	var left_arrow := Button.new()
	left_arrow.text = "< Prev"
	left_arrow.custom_minimum_size = Vector2(80, 30)
	left_arrow.add_theme_font_size_override("font_size", 14)
	left_arrow.pressed.connect(_cycle_leader.bind(-1))
	arrow_hbox.add_child(left_arrow)

	var right_arrow := Button.new()
	right_arrow.text = "Next >"
	right_arrow.custom_minimum_size = Vector2(80, 30)
	right_arrow.add_theme_font_size_override("font_size", 14)
	right_arrow.pressed.connect(_cycle_leader.bind(1))
	arrow_hbox.add_child(right_arrow)

	# Bonus chip list (below the portrait — readable body-15 chips, not
	# plain text, per designer feedback "leader bonuses are hard to read")
	var bonus_vbox := VBoxContainer.new()
	bonus_vbox.name = "LeaderBonusVBox"
	bonus_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bonus_vbox.add_theme_constant_override("separation", 5)
	leader_inner_vbox.add_child(bonus_vbox)

	var bonus_header := Label.new()
	bonus_header.text = "Leader Bonuses:"
	bonus_header.add_theme_font_size_override("font_size", 17)
	bonus_header.add_theme_color_override("font_color", UIPalette.PARCHMENT)
	bonus_vbox.add_child(bonus_header)

	# Placeholder label (replaced dynamically by _update_leader_display)
	_leader_bonus_label = Label.new()
	_leader_bonus_label.text = ""
	_leader_bonus_label.add_theme_font_size_override("font_size", 15)
	_leader_bonus_label.visible = false
	bonus_vbox.add_child(_leader_bonus_label)

	# Trailing spacer: absorbs whatever height content_right has beyond the
	# portrait/bonuses so the empty band below reads as intentional bottom
	# padding rather than unfilled leftover space.
	var leader_spacer := Control.new()
	leader_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	leader_inner_vbox.add_child(leader_spacer)

	# ── Start button (designer 2026-08-04): black text outline, fixed width
	# sized to the longest possible faction name (computed across
	# PLAYABLE_FACTIONS at build time, not per-selection), centered rather
	# than stretched full-width. ──
	_faction_start_btn = Button.new()
	_faction_start_btn.text = "START GAME"
	_faction_start_btn.add_theme_font_size_override("font_size", 20)
	_faction_start_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_faction_start_btn.add_theme_constant_override("outline_size", 3)
	_faction_start_btn.disabled = true
	_faction_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_faction_start_btn.pressed.connect(_on_faction_confirmed)
	right_vbox.add_child(_faction_start_btn)
	_faction_start_btn.custom_minimum_size = Vector2(_compute_start_button_width(), 54)

	# Bottom bar: cancel button
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(bottom_hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Back to Main Menu"
	cancel_btn.custom_minimum_size = Vector2(200, 36)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(func(): _faction_select_panel.queue_free())
	bottom_hbox.add_child(cancel_btn)

## Longest "START AS <NAME>" text width across every selectable faction
## (queried from DataManager at build time, not hardcoded), measured with
## the button's own resolved font/size so the fixed width always fits
## whichever faction turns out longest without per-selection resizing.
## `_faction_start_btn` must already be in the tree (font resolution needs
## an active Theme) and have its font_size override applied before this runs.
func _compute_start_button_width() -> float:
	var font: Font = _faction_start_btn.get_theme_font("font")
	var font_size: int = _faction_start_btn.get_theme_font_size("font_size")
	var max_w := 0.0
	for faction_id in PLAYABLE_FACTIONS:
		var fd: FactionData = DataManager.get_faction(faction_id)
		if fd == null:
			continue
		var btn_text := "START AS " + fd.display_name.to_upper()
		var w: float = font.get_string_size(btn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	return max_w + 64.0 # button content margins + breathing room

func _load_faction_seal(faction_id: StringName) -> Texture2D:
	var path := "res://assets/sprites/ui/generated/%s_seal.png" % String(faction_id)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _on_faction_list_clicked(faction_id: StringName) -> void:
	_selected_faction_id = faction_id
	var faction_data: FactionData = DataManager.get_faction(faction_id)
	if faction_data == null:
		return

	AudioManager.play_sfx(&"ui_click")

	# Keep the row's toggle state in sync even when this is invoked directly
	# (e.g. a screenshot/test harness calling the method without a real
	# click) rather than only via the Button's own pressed signal. The
	# shared ButtonGroup un-toggles every other row automatically.
	if _faction_buttons.has(faction_id):
		_faction_buttons[faction_id].button_pressed = true

	# Update info panel
	var tint := UIPalette.heraldry(faction_id)
	_faction_color_rect.color = tint
	_faction_info_label.text = faction_data.display_name

	# Update emblem and leader display
	_faction_emblem.faction_color = faction_data.color
	_update_leader_display()

	# Update map sketch highlight
	if _map_sketch:
		_map_sketch.faction_id = faction_id
		_map_sketch.queue_redraw()

	var details: Dictionary = FACTION_DETAILS.get(faction_id, {})
	_faction_desc_label.text = faction_data.description
	if details.has("playstyle"):
		_faction_desc_label.text += "\n\n" + details["playstyle"]

	if details.has("traits"):
		_faction_traits_label.text = "Traits:  " + details["traits"]
	else:
		_faction_traits_label.text = ""
	if details.has("unique"):
		_faction_unique_label.text = "Unique:  " + details["unique"]
	else:
		_faction_unique_label.text = ""

	# Starting regions
	var region_names: Array[String] = []
	for region_id in faction_data.starting_regions:
		var region := DataManager.get_region(region_id)
		if region:
			region_names.append(region.display_name)
		else:
			region_names.append(str(region_id).capitalize())
	if region_names.size() > 0:
		_faction_region_label.text = "Starting Region:  " + ", ".join(region_names)
	else:
		_faction_region_label.text = "Starting Region:  Nomadic (no fixed start)"

	_faction_start_btn.disabled = false
	_faction_start_btn.text = "START AS " + faction_data.display_name.to_upper()
	_faction_start_btn.add_theme_color_override("font_color", tint.lightened(0.2))

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
		_faction_emblem.portrait_texture = null
		_faction_emblem.queue_redraw()
		if _leader_name_label:
			_leader_name_label.text = GameManager.FACTION_LEADER_NAMES.get(_selected_faction_id, "")
		_clear_bonus_labels()
		return
	var leader: Dictionary = leaders[idx]
	# Pre-load portrait texture (do NOT load inside _draw)
	var portrait_key: String = leader.get("portrait", "")
	var tex: Texture2D = null
	if portrait_key != "":
		if portrait_key.begins_with("res://"):
			if ResourceLoader.exists(portrait_key):
				tex = load(portrait_key) as Texture2D
			if tex == null:
				push_warning("FactionSelect: Failed to load portrait: %s (exists=%s)" % [portrait_key, ResourceLoader.exists(portrait_key)])
		else:
			var path := "res://assets/sprites/leaders/%s.png" % portrait_key
			if ResourceLoader.exists(path):
				tex = load(path) as Texture2D
	_faction_emblem.faction_id = _selected_faction_id
	_faction_emblem.portrait_texture = tex
	_faction_emblem.queue_redraw()
	# Update leader name
	if _leader_name_label:
		_leader_name_label.text = "Leader: %s  (%d/%d)" % [leader.get("name", ""), idx + 1, leaders.size()]
	# Update bonus list with individually colored, readable chips
	_clear_bonus_labels()
	var bonus_vbox: VBoxContainer = _faction_select_panel.find_child("LeaderBonusVBox", true, false) if _faction_select_panel else null
	if bonus_vbox == null:
		return
	var bonuses: Array = leader.get("bonuses", [])
	for bonus in bonuses:
		var label_text: String = bonus.get(&"label", "")
		var val: int = bonus.get(&"value", 0)
		bonus_vbox.add_child(_make_bonus_chip(label_text, val >= 0))

## Readable chip wrapper for a single leader bonus line (designer 2026-08-04:
## "leader bonuses are a bit hard to read"). Body-15 text on a small tinted
## panel, not bare text on the raw leader chip backdrop. Uses SUCCESS_BRIGHT/
## DANGER_BRIGHT (not the plain dark-ink SUCCESS/DANGER) because this chip
## sits on `content_right`'s near-black CHIP_BG panel — see ui_palette.gd's
## own doc comment on why the dark-ink variants go low-contrast there.
func _make_bonus_chip(text: String, positive: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "BonusChip"
	var tint: Color = UIPalette.SUCCESS_BRIGHT if positive else UIPalette.DANGER_BRIGHT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.14)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	chip.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", tint)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip.add_child(lbl)
	return chip

func _clear_bonus_labels() -> void:
	var bonus_vbox: VBoxContainer = _faction_select_panel.find_child("LeaderBonusVBox", true, false) if _faction_select_panel else null
	if bonus_vbox == null:
		return
	# Remove all children except the first one (the "Leader Bonuses:" header)
	var children := bonus_vbox.get_children()
	for i in range(children.size() - 1, 0, -1):
		var child := children[i]
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
				if flat_bonuses.has("border_vigilance_bonus"):
					player_fs.border_vigilance = clampi(player_fs.border_vigilance + int(flat_bonuses["border_vigilance_bonus"]), 0, 100)
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
	title.theme_type_variation = &"HeaderLarge"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIPalette.INK_TITLE)
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
			meta_lbl.add_theme_color_override("font_color", UIPalette.INK_BODY)
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
	var portrait_texture: Texture2D = null  # Pre-loaded outside _draw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		# Background with faction tint
		draw_rect(rect, faction_color.darkened(0.75))
		# Subtle inner glow
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), faction_color.darkened(0.6), false, 1.0)
		# Border
		draw_rect(rect, faction_color.darkened(0.1), false, 2.0)

		if faction_id == &"":
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(size.x * 0.5 - 10, size.y * 0.5 + 4), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 24, Color(0.4, 0.38, 0.35))
			return

		# Use pre-loaded portrait texture (loaded in _update_leader_display)
		var portrait: Texture2D = portrait_texture
		if portrait == null:
			portrait = DataManager.get_leader_portrait(faction_id)
		if portrait:
			var inner := Rect2(Vector2(3, 3), size - Vector2(6, 6))
			draw_texture_rect(portrait, inner, false)
			# Gradient overlay at bottom for name readability
			for i in range(5):
				var y_off := size.y - 32.0 + i * 6.0
				var alpha := 0.1 + i * 0.14
				draw_rect(Rect2(3, y_off, size.x - 6, 6), Color(0, 0, 0, alpha))
		else:
			# Fallback: dark faction-tinted rect with icon hint
			var inner := Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8))
			draw_rect(inner, faction_color.darkened(0.65))
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(size.x * 0.5 - 8, size.y * 0.5 + 6), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 28, faction_color.lightened(0.2))

		# Faction name at bottom
		var font := ThemeDB.fallback_font
		var s := minf(size.x / 100.0, size.y / 130.0)
		var font_size := int(12 * s)
		var faction_data: FactionData = DataManager.get_faction(faction_id)
		if faction_data:
			draw_string(font, Vector2(4, size.y - 7 * s), faction_data.display_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, font_size, Color(0.95, 0.9, 0.8))

# ── Map Sketch Drawing (Task P2, UI Polish Wave) ────────────

## Rough stylized parchment sketch of the world, marking every playable
## faction's starting region with a small dot and the SELECTED faction with
## its seal + a highlight ring. Reads MapGenerator.LANDMASS_BLOBS (continent
## silhouette ellipses) and MapGenerator.REGION_SEEDS (region anchor
## positions) directly, normalized against HexMapData.MAP_WIDTH/HEIGHT — the
## same grid space every real campaign map is generated into — rather than
## a hardcoded copy or a live per-campaign generation (see the call site's
## comment for why: campaign maps reroll a random seed, so there's no single
## canonical map to bake a thumbnail from before a game exists).
## `playable_factions`/`seal_textures` are populated by the OUTER script
## before this is added to the tree (same "pre-load outside _draw()"
## discipline as _FactionEmblem's portrait_texture).
class _MapSketch extends Control:
	var faction_id: StringName = &"" # currently selected faction; drives the highlight marker
	var playable_factions: Array[StringName] = []
	var seal_textures: Dictionary = {} # faction_id -> Texture2D, pre-loaded

	func _draw() -> void:
		# Fix round (review defect): these were raw Color() literals — routed
		# through UIPalette now, same "base color + .darkened()/.lightened()
		# modifier" pattern _make_vignette_texture() already uses elsewhere in
		# this file. Backdrop/land use PARCHMENT rather than PARCHMENT_DARK:
		# tried PARCHMENT_DARK first, but darkened()/lightened() only ever
		# SHRINK a color's channel gaps (never grow them — verified: for any
		# amount `a`, lightened(c1)-lightened(c2) == (c1-c2)*(1-a), and
		# darkened() scales identically), and the neutral PARCHMENT_DARK tone
		# is already fairly desaturated (small channel gaps) — lightening it
		# toward the target brightness flattened the warm tan/brown hue into
		# a near-flat gray (screenshotted, looked visibly worse than the
		# original). PARCHMENT is much closer in hue to begin with, so
		# .darkened() preserves the warm parchment tone properly. The faction-
		# select screen stays on the neutral chrome set throughout (per the
		# row-styling design note above — no per-row theme rebuild), so these
		# read the neutral tones; the SELECTED faction's own marker already
		# sources its color from UIPalette.heraldry(fid) below, unaffected.
		var ink := UIPalette.INK_BODY
		var backdrop := UIPalette.PARCHMENT.darkened(0.1)
		var land := UIPalette.PARCHMENT.darkened(0.55)

		var rect := Rect2(Vector2.ZERO, size)
		# Parchment sketch backdrop + ink border
		draw_rect(rect, backdrop)
		draw_rect(rect, ink, false, 2.0)

		var mw := float(HexMapData.MAP_WIDTH)
		var mh := float(HexMapData.MAP_HEIGHT)
		var pad := 8.0
		var draw_w := size.x - pad * 2.0
		var draw_h := size.y - pad * 2.0
		if draw_w <= 0.0 or draw_h <= 0.0:
			return

		# Continent silhouette — overlapping semi-transparent ink ellipses
		# built from the same blob data _carve_landmass() uses, so the shape
		# is a genuine (rough) reading of the actual generated world, not an
		# arbitrary doodle.
		for blob in MapGenerator.LANDMASS_BLOBS:
			var c := Vector2(pad + (float(blob.cx) / mw) * draw_w, pad + (float(blob.cy) / mh) * draw_h)
			var r := Vector2((float(blob.rx) / mw) * draw_w, (float(blob.ry) / mh) * draw_h)
			var alpha: float = clampf(float(blob.w) * 0.4, 0.16, 0.42)
			_draw_ellipse(c, r, Color(land.r, land.g, land.b, alpha))

		# Region markers
		var selected_pos := Vector2.ZERO
		var selected_seal: Texture2D = null
		var selected_tint := ink
		var has_selected_marker := false
		for fid in playable_factions:
			var fd: FactionData = DataManager.get_faction(fid)
			if fd == null or fd.starting_regions.is_empty():
				continue # nomadic factions have no fixed capital to pin
			var region_id: StringName = fd.starting_regions[0]
			if not MapGenerator.REGION_SEEDS.has(region_id):
				continue
			var seed_pos: Vector2i = MapGenerator.REGION_SEEDS[region_id]
			var pos := Vector2(pad + (float(seed_pos.x) / mw) * draw_w, pad + (float(seed_pos.y) / mh) * draw_h)
			if fid == faction_id:
				selected_pos = pos
				selected_seal = seal_textures.get(fid)
				selected_tint = UIPalette.heraldry(fid)
				has_selected_marker = true
			else:
				draw_circle(pos, 3.5, Color(ink.r, ink.g, ink.b, 0.65))

		if has_selected_marker:
			draw_circle(selected_pos, 13.0, Color(selected_tint.r, selected_tint.g, selected_tint.b, 0.35))
			draw_circle(selected_pos, 13.0, Color(selected_tint.r, selected_tint.g, selected_tint.b, 0.9), false, 1.5)
			if selected_seal:
				draw_texture_rect(selected_seal, Rect2(selected_pos - Vector2(11, 11), Vector2(22, 22)), false)
			else:
				draw_circle(selected_pos, 6.0, selected_tint)
		elif faction_id != &"":
			# Selected faction is nomadic (no starting_regions) — no fixed
			# capital to pin, caption instead.
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(pad, size.y - pad), "Nomadic — no fixed starting position", HORIZONTAL_ALIGNMENT_LEFT, draw_w, 12, ink)

	func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 20) -> void:
		if radii.x <= 0.0 or radii.y <= 0.0:
			return
		var points := PackedVector2Array()
		for i in range(segments):
			var t := TAU * float(i) / float(segments)
			points.append(center + Vector2(cos(t) * radii.x, sin(t) * radii.y))
		draw_colored_polygon(points, color)
