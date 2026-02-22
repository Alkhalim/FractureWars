extends Node

var state: GameState
var current_phase: Enums.GamePhase = Enums.GamePhase.MAIN_MENU
var movement_system: MovementSystem
var city_system: CitySystem = CitySystem.new()
var diplomacy_system: DiplomacySystem = DiplomacySystem.new()
var research_system: ResearchSystem = ResearchSystem.new()
var policy_system: PolicySystem = PolicySystem.new()

func _ready() -> void:
	_setup_global_theme()

# ── UI Theme ─────────────────────────────────────────────────
# All three source images are 1536x1024. We use region_rect to crop
# to the visible element, then NinePatch margins on the cropped region.
# Adjust region_rect / margins here if borders look misaligned.

const _BTN_REGION := Rect2(55, 320, 1426, 384)    # Visible button area (wider crop)
const _BTN_MARGIN := 22                            # Border thickness in cropped region
const _FRAME_REGION := Rect2(5, 5, 1526, 1014)    # Panel frame incl. glow
const _FRAME_TEX_MARGIN := Vector4(90, 80, 90, 85) # L T R B — glow + gold border
const _FRAME_EXPAND := Vector4(80, 70, 80, 75)    # L T R B — push gold border to panel edge
const _FRAME_CONTENT := Vector4(45, 40, 45, 40)   # L T R B — text padding inside border
const _NOTIF_REGION := Rect2(20, 5, 1496, 1014)
const _NOTIF_TEX_MARGIN := Vector4(220, 270, 220, 190) # L T R B — columns + eagle + medallion
const _NOTIF_EXPAND := Vector4(25, 20, 25, 20)
const _NOTIF_CONTENT := Vector4(240, 290, 240, 210)

var _btn_texture: Texture2D
var _frame_texture: Texture2D
var _notif_texture: Texture2D

func _setup_global_theme() -> void:
	_btn_texture = load("res://assets/sprites/ui/button1.png") as Texture2D
	_frame_texture = load("res://assets/sprites/ui/frame1.png") as Texture2D
	_notif_texture = load("res://assets/sprites/ui/notification1.png") as Texture2D

	var theme := Theme.new()

	# ── Button styles ──
	if _btn_texture:
		var normal := _make_btn_style(Color.WHITE)
		theme.set_stylebox("normal", "Button", normal)
		theme.set_stylebox("hover", "Button", _make_btn_style(Color(1.25, 1.2, 1.1)))
		theme.set_stylebox("pressed", "Button", _make_btn_style(Color(0.75, 0.7, 0.65)))
		theme.set_stylebox("disabled", "Button", _make_btn_style(Color(0.5, 0.48, 0.45, 0.7)))
		theme.set_stylebox("focus", "Button", _make_btn_style(Color(1.15, 1.12, 1.05)))

	# Button font — brighter colors + outline for readability on marble
	theme.set_color("font_color", "Button", Color(0.95, 0.9, 0.75))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.97, 0.82))
	theme.set_color("font_pressed_color", "Button", Color(0.75, 0.7, 0.55))
	theme.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.4))
	theme.set_color("font_outline_color", "Button", Color(0.0, 0.0, 0.0, 0.9))
	theme.set_color("font_shadow_color", "Button", Color(0.0, 0.0, 0.0, 0.6))
	theme.set_constant("outline_size", "Button", 3)
	theme.set_constant("shadow_offset_x", "Button", 1)
	theme.set_constant("shadow_offset_y", "Button", 2)
	theme.set_font_size("font_size", "Button", 15)

	# ── Label readability — subtle outline on all labels ──
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.7))
	theme.set_constant("outline_size", "Label", 2)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.45))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# ── PanelContainer style (frame1) ──
	if _frame_texture:
		theme.set_stylebox("panel", "PanelContainer", make_panel_style())

	get_tree().root.theme = theme

func _make_btn_style(modulate: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _btn_texture
	s.region_rect = _BTN_REGION
	s.texture_margin_left = _BTN_MARGIN
	s.texture_margin_top = _BTN_MARGIN
	s.texture_margin_right = _BTN_MARGIN
	s.texture_margin_bottom = _BTN_MARGIN
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.modulate_color = modulate
	return s

## Creates a panel style using frame1.png. Gold border aligns with panel edge;
## glow extends beyond via expand_margin. Falls back to simple flat style if missing.
func make_panel_style() -> StyleBox:
	if _frame_texture == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.08, 0.07, 0.1, 0.95)
		flat.border_color = Color(0.55, 0.42, 0.2, 0.8)
		flat.set_border_width_all(2)
		flat.set_corner_radius_all(6)
		flat.set_content_margin_all(12)
		return flat
	var s := StyleBoxTexture.new()
	s.texture = _frame_texture
	s.region_rect = _FRAME_REGION
	s.texture_margin_left = _FRAME_TEX_MARGIN.x
	s.texture_margin_top = _FRAME_TEX_MARGIN.y
	s.texture_margin_right = _FRAME_TEX_MARGIN.z
	s.texture_margin_bottom = _FRAME_TEX_MARGIN.w
	s.expand_margin_left = _FRAME_EXPAND.x
	s.expand_margin_top = _FRAME_EXPAND.y
	s.expand_margin_right = _FRAME_EXPAND.z
	s.expand_margin_bottom = _FRAME_EXPAND.w
	s.content_margin_left = _FRAME_CONTENT.x
	s.content_margin_top = _FRAME_CONTENT.y
	s.content_margin_right = _FRAME_CONTENT.z
	s.content_margin_bottom = _FRAME_CONTENT.w
	return s

## Creates an ornate notification style using notification1.png (columns + eagle).
## Falls back to panel style if missing.
func make_notification_style() -> StyleBox:
	if _notif_texture == null:
		return make_panel_style()
	var s := StyleBoxTexture.new()
	s.texture = _notif_texture
	s.region_rect = _NOTIF_REGION
	s.texture_margin_left = _NOTIF_TEX_MARGIN.x
	s.texture_margin_top = _NOTIF_TEX_MARGIN.y
	s.texture_margin_right = _NOTIF_TEX_MARGIN.z
	s.texture_margin_bottom = _NOTIF_TEX_MARGIN.w
	s.expand_margin_left = _NOTIF_EXPAND.x
	s.expand_margin_top = _NOTIF_EXPAND.y
	s.expand_margin_right = _NOTIF_EXPAND.z
	s.expand_margin_bottom = _NOTIF_EXPAND.w
	s.content_margin_left = _NOTIF_CONTENT.x
	s.content_margin_top = _NOTIF_CONTENT.y
	s.content_margin_right = _NOTIF_CONTENT.z
	s.content_margin_bottom = _NOTIF_CONTENT.w
	return s

# Minor faction → parent faction mapping
const MINOR_FACTION_PARENTS := {
	&"crimson_legion": &"empire", &"aurentis_guard": &"empire",
	&"thornwardens": &"gladehost", &"miststriders": &"gladehost",
	&"obsidian_order": &"moonspear", &"luminarch": &"moonspear",
	&"stormbound": &"thunderswarm", &"skalvar_watch": &"thunderswarm",
	&"twilight_veil": &"tainted_jade", &"jade_conclave": &"tainted_jade",
	&"gorgonic_cult": &"ivoryscar", &"servants_of_reliquary": &"ivoryscar",
	&"salt_reavers": &"skulloath", &"ashbound": &"skulloath",
	&"crownfire": &"cinderguard", &"valkarn_garrison": &"cinderguard",
	&"bloodthrone": &"forsaken", &"blightcoven": &"forsaken",
	&"icebound": &"shardhorde", &"splinterbrood": &"shardhorde",
	&"oaseans": &"sunblessed", &"venerated": &"sunblessed",
}

# Nomadic factions don't get cities — they roam or use elderbeasts
const NOMADIC_FACTIONS := [&"shardhorde", &"icebound", &"splinterbrood", &"sunblessed", &"oaseans", &"venerated"]

# ── Region → 3 cities each (81 cities total) ──────────────────
const REGION_CITIES := {
	# ── Empire Culture ──
	&"eternal_plains": [
		{name = "Aurelion", offset = Vector2i(-2, -2)},
		{name = "Marcellum", offset = Vector2i(2, 0)},
		{name = "Goldsward", offset = Vector2i(-1, 3)},
	],
	&"sunburst_valley": [
		{name = "Dawnhold", offset = Vector2i(-2, -1)},
		{name = "Solarius", offset = Vector2i(2, 1)},
		{name = "Cinderfall Keep", offset = Vector2i(0, 3)},
	],
	&"aurentis": [
		{name = "Aurentis Prime", offset = Vector2i(0, -2)},
		{name = "Goldwatch", offset = Vector2i(2, 1)},
		{name = "Whitegate", offset = Vector2i(-2, 2)},
	],
	# ── Gladehost Culture ──
	&"sainkhu_groves": [
		{name = "Heartwood", offset = Vector2i(-2, -1)},
		{name = "Willowmere", offset = Vector2i(2, 0)},
		{name = "Roothollow", offset = Vector2i(0, 3)},
	],
	&"verdant_glade": [
		{name = "Fernhall", offset = Vector2i(-1, -2)},
		{name = "Mosskeep", offset = Vector2i(2, 1)},
		{name = "Briargate", offset = Vector2i(-2, 2)},
	],
	&"orisyl": [
		{name = "Orisyl Canopy", offset = Vector2i(0, -2)},
		{name = "Dewspring", offset = Vector2i(2, 1)},
		{name = "Thornveil", offset = Vector2i(-2, 2)},
	],
	# ── Moonspear Culture ──
	&"iskar": [
		{name = "Iskar Citadel", offset = Vector2i(0, -2)},
		{name = "Moonwell", offset = Vector2i(2, 1)},
		{name = "Silver Archive", offset = Vector2i(-2, 2)},
	],
	&"nightfall_sanctum": [
		{name = "Obsidian Gate", offset = Vector2i(-2, -1)},
		{name = "Twilight Spire", offset = Vector2i(2, 0)},
		{name = "Sanctum Depths", offset = Vector2i(0, 3)},
	],
	&"asdrol": [
		{name = "Asdrol Haven", offset = Vector2i(0, -2)},
		{name = "Luminar Watch", offset = Vector2i(2, 1)},
		{name = "Pilgrim's Rest", offset = Vector2i(-2, 2)},
	],
	# ── Thunderswarm Culture ──
	&"dragonspire_mountains": [
		{name = "Stormforge", offset = Vector2i(-2, -1)},
		{name = "Thunder Keep", offset = Vector2i(2, 0)},
		{name = "Wyrmhold", offset = Vector2i(0, 3)},
	],
	&"thundercrest_peaks": [
		{name = "Thundercrest", offset = Vector2i(0, -2)},
		{name = "Galewatch", offset = Vector2i(2, 1)},
		{name = "Stonehorn", offset = Vector2i(-2, 2)},
	],
	&"skalvar": [
		{name = "Skalvar Hall", offset = Vector2i(-1, -2)},
		{name = "Ironpeak", offset = Vector2i(2, 1)},
		{name = "Windbreak", offset = Vector2i(-2, 2)},
	],
	# ── Tainted Jade Culture ──
	&"coatlantli": [
		{name = "Coatlantli", offset = Vector2i(0, -2)},
		{name = "Jade Fang Temple", offset = Vector2i(2, 1)},
		{name = "Serpent Pool", offset = Vector2i(-2, 3)},
	],
	&"southern_reach": [
		{name = "Xalapa", offset = Vector2i(-2, -1)},
		{name = "Emerald Port", offset = Vector2i(2, 0)},
		{name = "Thornmarsh", offset = Vector2i(0, 3)},
	],
	&"xotchi": [
		{name = "Xotchi Sanctuary", offset = Vector2i(0, -2)},
		{name = "Bloomheart", offset = Vector2i(2, 1)},
		{name = "Fungal Hollow", offset = Vector2i(-2, 2)},
	],
	# ── Skulloath Culture ──
	&"bataarbad": [
		{name = "Bataarbad", offset = Vector2i(-2, -1)},
		{name = "Bonecairn", offset = Vector2i(2, 0)},
		{name = "Dreadcamp", offset = Vector2i(0, 3)},
	],
	&"altaban": [
		{name = "Altaban Outpost", offset = Vector2i(0, -2)},
		{name = "Salt Hollow", offset = Vector2i(2, 1)},
		{name = "Reaver's Den", offset = Vector2i(-2, 2)},
	],
	&"tsagan": [
		{name = "Tsagan Camp", offset = Vector2i(-1, -2)},
		{name = "Ashbone", offset = Vector2i(2, 1)},
		{name = "Wailing Flats", offset = Vector2i(-2, 2)},
	],
	# ── Cinderguard Culture ──
	&"duststorm_valley": [
		{name = "Emberhold", offset = Vector2i(-2, -1)},
		{name = "Cinderwatch", offset = Vector2i(2, 0)},
		{name = "Furnace Gate", offset = Vector2i(0, 3)},
	],
	&"ashenmark": [
		{name = "Ashenmark Forge", offset = Vector2i(0, -2)},
		{name = "Crownfire Bastion", offset = Vector2i(2, 1)},
		{name = "Slagtown", offset = Vector2i(-2, 2)},
	],
	&"valkarn": [
		{name = "Valkarn Garrison", offset = Vector2i(-1, -2)},
		{name = "Molten Gate", offset = Vector2i(2, 1)},
		{name = "Sparkhaven", offset = Vector2i(-2, 2)},
	],
	# ── Forsaken Culture ──
	&"orenthal": [
		{name = "Orenthal Ruins", offset = Vector2i(-2, -1)},
		{name = "Blightspire", offset = Vector2i(2, 0)},
		{name = "Carrion Hold", offset = Vector2i(0, 3)},
	],
	&"morvane": [
		{name = "Morvane Citadel", offset = Vector2i(0, -2)},
		{name = "Bloodthrone Keep", offset = Vector2i(2, 1)},
		{name = "Rotmere", offset = Vector2i(-2, 2)},
	],
	&"weeping_barrows": [
		{name = "Barrow Gate", offset = Vector2i(-1, -2)},
		{name = "Blighthollow", offset = Vector2i(2, 1)},
		{name = "Gravemist", offset = Vector2i(-2, 2)},
	],
	# ── Ivoryscar Culture ──
	&"qareth": [
		{name = "Qareth Spire", offset = Vector2i(-2, -1)},
		{name = "Gorgon's Eye", offset = Vector2i(2, 0)},
		{name = "Petrified Gate", offset = Vector2i(0, 3)},
	],
	&"torgalun_desert": [
		{name = "Torgalun", offset = Vector2i(0, -2)},
		{name = "Sand Shrine", offset = Vector2i(2, 1)},
		{name = "Dustwalker Camp", offset = Vector2i(-2, 2)},
	],
	&"whispering_dunes": [
		{name = "Relic Court", offset = Vector2i(-1, -2)},
		{name = "Whisper Gate", offset = Vector2i(2, 1)},
		{name = "Ossuary", offset = Vector2i(-2, 2)},
	],
}

# ── Region → Culture mapping ──────────────────────────────────
const REGION_CULTURE := {
	&"eternal_plains": &"empire", &"sunburst_valley": &"empire", &"aurentis": &"empire",
	&"sainkhu_groves": &"gladehost", &"verdant_glade": &"gladehost", &"orisyl": &"gladehost",
	&"iskar": &"moonspear", &"nightfall_sanctum": &"moonspear", &"asdrol": &"moonspear",
	&"dragonspire_mountains": &"thunderswarm", &"thundercrest_peaks": &"thunderswarm", &"skalvar": &"thunderswarm",
	&"coatlantli": &"tainted_jade", &"southern_reach": &"tainted_jade", &"xotchi": &"tainted_jade",
	&"bataarbad": &"skulloath", &"altaban": &"skulloath", &"tsagan": &"skulloath",
	&"duststorm_valley": &"cinderguard", &"ashenmark": &"cinderguard", &"valkarn": &"cinderguard",
	&"orenthal": &"forsaken", &"morvane": &"forsaken", &"weeping_barrows": &"forsaken",
	&"qareth": &"ivoryscar", &"torgalun_desert": &"ivoryscar", &"whispering_dunes": &"ivoryscar",
}

# ── Culture → Regions mapping ─────────────────────────────────
const CULTURE_REGIONS := {
	&"empire": [&"eternal_plains", &"sunburst_valley", &"aurentis"],
	&"gladehost": [&"sainkhu_groves", &"verdant_glade", &"orisyl"],
	&"moonspear": [&"iskar", &"nightfall_sanctum", &"asdrol"],
	&"thunderswarm": [&"dragonspire_mountains", &"thundercrest_peaks", &"skalvar"],
	&"tainted_jade": [&"coatlantli", &"southern_reach", &"xotchi"],
	&"skulloath": [&"bataarbad", &"altaban", &"tsagan"],
	&"cinderguard": [&"duststorm_valley", &"ashenmark", &"valkarn"],
	&"forsaken": [&"orenthal", &"morvane", &"weeping_barrows"],
	&"ivoryscar": [&"qareth", &"torgalun_desert", &"whispering_dunes"],
}

# ── Culture completion bonuses ────────────────────────────────
const CULTURE_BONUSES := {
	&"empire":       {type = "upkeep_reduction", value = 0.20, desc = "Imperial Dominion: -20% unit upkeep"},
	&"gladehost":    {type = "food_bonus", value = 0.30, desc = "Verdant Bounty: +30% food production"},
	&"moonspear":    {type = "tech_bonus", value = 0.25, desc = "Lunar Enlightenment: +25% technology"},
	&"thunderswarm": {type = "movement_bonus", value = 1.0, desc = "Storm March: +1 army movement"},
	&"tainted_jade": {type = "population_growth", value = 0.30, desc = "Jungle Vitality: +30% population growth"},
	&"skulloath":    {type = "combat_damage", value = 0.15, desc = "Steppe Fury: +15% combat damage"},
	&"cinderguard":  {type = "iron_bonus", value = 0.30, desc = "Forge Mastery: +30% iron production"},
	&"forsaken":     {type = "building_cost_reduction", value = 0.25, desc = "Ruinlore: -25% building costs"},
	&"ivoryscar":    {type = "shard_bonus", value = 0.25, desc = "Petrified Wisdom: +25% shard essence"},
}

# ── Faction leader names ──────────────────────────────────────
const FACTION_LEADER_NAMES := {
	&"empire": "Emperor Aurelian III",
	&"gladehost": "Archdruid Thalwen",
	&"moonspear": "High Priestess Selara",
	&"thunderswarm": "Warchief Groth",
	&"tainted_jade": "Serpent Queen Ixchala",
	&"skulloath": "Khan Borlag the Pale",
	&"cinderguard": "Forgemaster Valdris",
	&"forsaken": "The Hollow King",
	&"ivoryscar": "Oracle Medusa",
	&"shardhorde": "The Crystalmind",
	&"sunblessed": "Solar Archon Kael",
}

# ── Faction dialogue ──────────────────────────────────────────
const FACTION_DIALOGUE := {
	&"empire": {
		"greeting_friendly": "The Empire remembers its friends. What do you seek?",
		"greeting_hostile": "You dare approach the throne? Speak quickly.",
		"greeting_neutral": "State your business with the Empire.",
		"greeting_war": "Your audacity knows no bounds. Speak before we silence you.",
		"accept_trade": "The Empire's coffers benefit from fair trade.",
		"reject_trade": "These terms insult the Crown. Leave.",
		"accept_alliance": "Together we shall bring order to this fractured world.",
		"reject_alliance": "The Empire does not ally with the weak.",
		"accept_peace": "Very well. The Empire grants you respite... for now.",
		"reject_peace": "Your armies burn. There will be no peace.",
		"war_declared": "So be it. The legions march.",
		"threatened": "You would threaten the Empire? Bold... and foolish.",
	},
	&"gladehost": {
		"greeting_friendly": "The forest welcomes you, kindred spirit.",
		"greeting_hostile": "The roots remember your transgressions.",
		"greeting_neutral": "The grove listens. Speak.",
		"greeting_war": "You have disturbed the balance. Nature will correct this.",
		"accept_trade": "A fair exchange nourishes both sides.",
		"reject_trade": "The forest has no need of your trinkets.",
		"accept_alliance": "Our roots intertwine. We grow stronger together.",
		"reject_alliance": "The grove stands alone for now.",
		"accept_peace": "Let the land heal. We accept your peace.",
		"reject_peace": "The thorns will not be withdrawn.",
		"war_declared": "You have awoken the wrath of the wild.",
		"threatened": "Storms break upon ancient oaks. We do not bend.",
	},
	&"moonspear": {
		"greeting_friendly": "The moon smiles upon your visit, friend.",
		"greeting_hostile": "The stars foretold your coming... and your failure.",
		"greeting_neutral": "What guidance do you seek from the moon?",
		"greeting_war": "The divine light shall burn away your darkness.",
		"accept_trade": "The temple accepts this exchange in good faith.",
		"reject_trade": "The stars counsel against this arrangement.",
		"accept_alliance": "By moonlight we are bound. Our fates intertwine.",
		"reject_alliance": "The moon has not yet aligned for such a pact.",
		"accept_peace": "Let there be peace under the moon's gaze.",
		"reject_peace": "The divine mandate demands your submission.",
		"war_declared": "The moonspear shall pierce your heart.",
		"threatened": "We serve a higher power. Your threats are empty.",
	},
	&"thunderswarm": {
		"greeting_friendly": "Ha! A worthy ally approaches! Come, drink with us!",
		"greeting_hostile": "You smell of weakness. State your purpose.",
		"greeting_neutral": "The storms care not for pleasantries. Speak.",
		"greeting_war": "Your skull will join our collection.",
		"accept_trade": "Iron and gold flow like mountain rivers. Agreed.",
		"reject_trade": "Bah! Insulting terms. Begone.",
		"accept_alliance": "Together we are the storm! None shall stand before us!",
		"reject_alliance": "We fight our own battles. Ask again when you prove yourself.",
		"accept_peace": "The storm passes. For now.",
		"reject_peace": "THUNDER DOES NOT NEGOTIATE!",
		"war_declared": "STOOOOORM! The warhorns sound!",
		"threatened": "You threaten the storm? HAH! Amusing.",
	},
	&"tainted_jade": {
		"greeting_friendly": "The serpent coils gently for those it favors.",
		"greeting_hostile": "Careful where you tread. The jungle has teeth.",
		"greeting_neutral": "The jade throne acknowledges your presence.",
		"greeting_war": "Your blood will feed the jungle.",
		"accept_trade": "The serpent accepts. An equitable exchange.",
		"reject_trade": "You offer poison disguised as honey. Denied.",
		"accept_alliance": "Our venom and your strength... a potent combination.",
		"reject_alliance": "The jungle does not share its secrets lightly.",
		"accept_peace": "The serpent releases its prey... this time.",
		"reject_peace": "The jungle remembers every wound.",
		"war_declared": "The serpent strikes without warning.",
		"threatened": "Threaten us? The jungle laughs.",
	},
	&"skulloath": {
		"greeting_friendly": "You ride with honor. The horde respects this.",
		"greeting_hostile": "Your bones will decorate our standards.",
		"greeting_neutral": "Speak, outsider. The Khan listens.",
		"greeting_war": "The steppe will swallow your armies whole.",
		"accept_trade": "The caravan routes open. A fair exchange.",
		"reject_trade": "The Khan spits on your offer.",
		"accept_alliance": "Blood brothers! Together, the world trembles!",
		"reject_alliance": "The horde rides alone.",
		"accept_peace": "The raids cease. Your tribute is noted.",
		"reject_peace": "Peace is for the dead!",
		"war_declared": "The skull banner rises! War!",
		"threatened": "Threaten the horde? Your courage exceeds your wisdom.",
	},
	&"cinderguard": {
		"greeting_friendly": "The forges burn bright for allies. Welcome.",
		"greeting_hostile": "You stand in the shadow of the furnace. Choose wisely.",
		"greeting_neutral": "The Forgemaster has a moment. Make it count.",
		"greeting_war": "The furnace consumes all. You will be no different.",
		"accept_trade": "Iron meets iron. A solid deal.",
		"reject_trade": "Slag. Worthless. Leave my forge.",
		"accept_alliance": "Forged together, we are unbreakable.",
		"reject_alliance": "The forge needs no additional fuel.",
		"accept_peace": "The coals cool. Peace is granted.",
		"reject_peace": "The furnace does not forgive.",
		"war_declared": "The forge-fires of war are stoked.",
		"threatened": "Threaten the forge? You'll melt before us.",
	},
	&"forsaken": {
		"greeting_friendly": "Even in darkness, some lights are... tolerable.",
		"greeting_hostile": "Your presence offends what remains of our senses.",
		"greeting_neutral": "The Hollow King deigns to listen. Briefly.",
		"greeting_war": "All things end. Your time has come.",
		"accept_trade": "Even the dead have use for the living's trinkets.",
		"reject_trade": "We have no need of your pittance.",
		"accept_alliance": "In shadow, we are bound. A useful arrangement.",
		"reject_alliance": "Trust? We barely trust ourselves.",
		"accept_peace": "Death pauses... but never truly stops.",
		"reject_peace": "There is no peace in the grave.",
		"war_declared": "The hollow winds carry our armies forth.",
		"threatened": "What can you threaten the already-dead?",
	},
	&"ivoryscar": {
		"greeting_friendly": "The Oracle's eye sees a favorable future for us both.",
		"greeting_hostile": "The petrified gaze falls upon you. Be still.",
		"greeting_neutral": "The relics whisper. What do you bring?",
		"greeting_war": "Your fate was sealed the moment you opposed us.",
		"accept_trade": "Ancient wisdom says: a fair trade benefits all.",
		"reject_trade": "The sands bury worthless offers.",
		"accept_alliance": "Our visions align. Together we unearth greatness.",
		"reject_alliance": "The future does not yet show us as allies.",
		"accept_peace": "The Oracle decrees peace. So it shall be.",
		"reject_peace": "Your destruction has already been foretold.",
		"war_declared": "The desert's wrath is patient, but absolute.",
		"threatened": "We have seen civilizations rise and fall. You do not frighten us.",
	},
	&"shardhorde": {
		"greeting_friendly": "Crystal resonance... positive. Communication proceeds.",
		"greeting_hostile": "Foreign vibrations detected. Hostile intent registered.",
		"greeting_neutral": "The Crystalmind processes your signal. Transmit.",
		"greeting_war": "Elimination protocol engaged.",
		"accept_trade": "Resource exchange optimized. Agreement formed.",
		"reject_trade": "Exchange ratio suboptimal. Rejected.",
		"accept_alliance": "Symbiosis detected. Cooperation protocol initiated.",
		"reject_alliance": "Insufficient compatibility for merger.",
		"accept_peace": "Hostility termination accepted. Resources redirected.",
		"reject_peace": "Threat not neutralized. Conflict continues.",
		"war_declared": "Swarm vector locked. All units: converge.",
		"threatened": "Threat assessment: negligible.",
	},
	&"sunblessed": {
		"greeting_friendly": "The sun shines upon the righteous. Welcome, friend.",
		"greeting_hostile": "The sacred flame judges you... and finds you wanting.",
		"greeting_neutral": "Walk in the light, stranger. What do you seek?",
		"greeting_war": "The sun's justice is absolute. Prepare yourself.",
		"accept_trade": "A blessed exchange under the golden sky.",
		"reject_trade": "The sun does not bargain with shadows.",
		"accept_alliance": "Under the same sun, we march as one.",
		"reject_alliance": "The pilgrimage continues alone.",
		"accept_peace": "Let the dawn bring peace between us.",
		"reject_peace": "The sun sets on your pleas for mercy.",
		"war_declared": "By solar decree, you are judged!",
		"threatened": "The sun fears no darkness.",
	},
}

# Commander name lists per faction
const COMMANDER_NAMES := {
	&"empire": [
		"Legate Aurelius", "Prefect Cassius", "Tribune Marcellus", "Centurion Varro",
		"Commander Gaius", "Marshal Tiberius", "Captain Lucius", "General Septimus",
		"Prefect Helena", "Legate Octavia", "Tribune Valeria", "Commander Flavia",
	],
	&"skulloath": [
		"Warchief Grak", "Bonelord Thresh", "Ravager Krul", "Dread Maw Vex",
		"Skull Warden Zhag", "Gore Fist Brul", "Howler Nix", "Bonecaller Dren",
		"War Mistress Skaela", "Dread Mother Vhul", "Ravager Ghast", "Blood Seer Morg",
	],
	&"gladehost": [
		"Grove Keeper Aelind", "Thorn Warden Sylara", "Root Guard Faelen", "Leaf Marshal Thandril",
		"Bark Shield Eryn", "Vine Watcher Olwen", "Shade Walker Miriel", "Canopy Lord Thaelen",
		"Branch Warden Ysviel", "Moss Sentinel Caedris", "Dew Guard Lirael", "Grove Marshal Alathir",
	],
	&"tainted_jade": [
		"Serpent Lord Ixcatl", "Jade Fang Quetzal", "Venom Priest Tlacael", "Shadow Coatl Xipe",
		"Scale Warden Cipac", "Mist Serpent Yaotl", "Jade Eye Necuame", "Fang Master Itzli",
		"Serpent Queen Malinal", "Venom Seer Xochitl", "Jade Priestess Atzi", "Coatl Keeper Izel",
	],
	&"shardhorde": [
		"Crystal Matriarch Zyx", "Shard Caller Prysm", "Hive Mind Kryl", "Crystal Warden Thex",
		"Swarm Lord Vyss", "Beast Keeper Nyx", "Void Herder Qal", "Crystal Seer Oryth",
		"Shard Mother Kael", "Hive Queen Zhyl", "Crystal Fang Drex", "Beast Lord Gryx",
	],
	&"moonspear": [
		"Sentinel Arathor", "Moon Warden Yselle", "Starlight Keeper Doran", "High Guard Caelen",
		"Dawn Shield Mirael", "Silver Lance Theron", "Crescent Blade Lirael", "Vigilant Aldric",
	],
	&"thunderswarm": [
		"Stormcaller Draken", "Thunder Lord Bjorn", "Lightning Warden Askari", "Storm Rider Volga",
		"Tempest Fang Ragnar", "Sky Breaker Haldis", "Gale Marshal Tormund", "Wind Rider Svara",
	],
	&"ivoryscar": [
		"Relic Seeker Asharan", "Bone Scholar Nephris", "Dust Warden Kaleth", "Tomb Walker Seris",
		"Ivory Sage Mithren", "Sand Oracle Zephra", "Ruin Guard Vashti", "Crypt Keeper Oshar",
	],
	&"cinderguard": [
		"Forge Master Vulkan", "Ember Warden Kael", "Ash Captain Brennan", "Fire Marshal Ignis",
		"Slag Knight Thorin", "Cinder Shield Pyra", "Furnace Lord Steren", "Coal Warden Ashlyn",
	],
	&"forsaken": [
		"Dusk Lord Morven", "Blight Warden Thessal", "Hollow Knight Cadeus", "Wraith Captain Vael",
		"Shadow Keeper Nyx", "Ruin Marshal Gharan", "Pale Sentinel Draven", "Void Walker Serath",
	],
	&"sunblessed": [
		"Radiant Seraph Aurel", "Sun Warden Solara", "Dawn Walker Helios", "Light Bearer Amara",
		"Golden Shield Darius", "Sacred Flame Pyriel", "Sun Pilgrim Eshara", "Bright Lance Oriel",
	],
}
var _commander_name_counters: Dictionary = {} # faction_id -> int

# ── Save / Load ─────────────────────────────────────────────

func save_game(slot: int) -> void:
	state.serialize_hex_map()
	state.turn_manager_state = TurnManager.serialize_state()
	DirAccess.make_dir_recursive_absolute("user://saves")
	ResourceSaver.save(state, "user://saves/save_%d.tres" % slot)
	state.hex_map_data = {} # Clear after save to save memory
	state.turn_manager_state = {}

func load_game(slot: int) -> void:
	var path := "user://saves/save_%d.tres" % slot
	if not ResourceLoader.exists(path):
		return
	state = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameState
	if state == null:
		return
	state.deserialize_hex_map()
	TurnManager.deserialize_state(state.turn_manager_state)
	state.turn_manager_state = {}
	movement_system = MovementSystem.new(state.hex_map)
	current_phase = Enums.GamePhase.CAMPAIGN
	_commander_name_counters.clear()
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")

static func has_save(slot: int) -> bool:
	return ResourceLoader.exists("user://saves/save_%d.tres" % slot)

func new_game(faction_id: StringName = &"empire") -> void:
	state = GameState.new()
	state.player_faction_id = faction_id

	# Generate hex map
	state.hex_map = MapGenerator.generate_hex_map(DataManager.regions)
	movement_system = MovementSystem.new(state.hex_map)

	_init_factions()
	_init_rebels_faction()
	_init_shard_guardians_faction()
	_init_independent_faction()
	_init_regions()
	_init_cities()
	_init_elderbeasts()
	_init_armies()
	_init_commander_pools()
	_init_diplomacy()
	current_phase = Enums.GamePhase.CAMPAIGN
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")

func _init_factions() -> void:
	_commander_name_counters.clear()
	for faction_id in DataManager.factions:
		var fs := FactionState.new()
		fs.faction_data_id = faction_id
		var is_minor := MINOR_FACTION_PARENTS.has(faction_id)
		if faction_id in NOMADIC_FACTIONS and _is_shardhorde_type(faction_id):
			# Shardhorde-type nomads: crystal/shard economy
			fs.resources = {
				Enums.ResourceType.GOLD: 60 if is_minor else 100,
				Enums.ResourceType.IRON: 30 if is_minor else 50,
				Enums.ResourceType.FOOD: 100 if is_minor else 150,
				Enums.ResourceType.TECHNOLOGY: 10 if is_minor else 15,
				Enums.ResourceType.SHARD_ESSENCE: 10 if is_minor else 20,
				Enums.ResourceType.WOOD: 20 if is_minor else 40,
				Enums.ResourceType.CAPTIVES: 0,
			}
		elif is_minor:
			# Minor factions: reduced starting resources
			fs.resources = {
				Enums.ResourceType.GOLD: 100,
				Enums.ResourceType.IRON: 50,
				Enums.ResourceType.FOOD: 80,
				Enums.ResourceType.TECHNOLOGY: 15,
				Enums.ResourceType.SHARD_ESSENCE: 0,
				Enums.ResourceType.WOOD: 40,
				Enums.ResourceType.CAPTIVES: 0,
			}
		else:
			# Major factions: full starting resources
			fs.resources = {
				Enums.ResourceType.GOLD: 150,
				Enums.ResourceType.IRON: 80,
				Enums.ResourceType.FOOD: 120,
				Enums.ResourceType.TECHNOLOGY: 30,
				Enums.ResourceType.SHARD_ESSENCE: 0,
				Enums.ResourceType.WOOD: 60,
				Enums.ResourceType.CAPTIVES: 0,
			}
		state.faction_states[faction_id] = fs

static func _is_shardhorde_type(faction_id: StringName) -> bool:
	return faction_id == &"shardhorde" or faction_id == &"icebound" or faction_id == &"splinterbrood"

static func is_npc_faction(faction_id: StringName) -> bool:
	return faction_id == &"rebels" or faction_id == &"shard_guardians" or faction_id == &"independent"

func _init_rebels_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"rebels"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"rebels"] = fs

func _init_shard_guardians_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"shard_guardians"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"shard_guardians"] = fs

func _init_independent_faction() -> void:
	var fs := FactionState.new()
	fs.faction_data_id = &"independent"
	fs.resources = {
		Enums.ResourceType.GOLD: 0,
		Enums.ResourceType.IRON: 0,
		Enums.ResourceType.FOOD: 0,
		Enums.ResourceType.TECHNOLOGY: 0,
		Enums.ResourceType.SHARD_ESSENCE: 0,
		Enums.ResourceType.WOOD: 0,
		Enums.ResourceType.CAPTIVES: 0,
	}
	state.faction_states[&"independent"] = fs

func _init_regions() -> void:
	# Assign starting regions to factions via hex map tile ownership
	for faction_id in DataManager.factions:
		var faction_data: FactionData = DataManager.factions[faction_id]
		var fs: FactionState = state.faction_states[faction_id]
		for region_id in faction_data.starting_regions:
			state.hex_map.set_region_owner(region_id, faction_id)
			fs.owned_regions.append(region_id)

# Hardcoded starting armies for factions with custom unit rosters
const MAJOR_STARTING_ARMIES := {
	&"empire": [&"legionary", &"legionary", &"emberlight_auxilia", &"dracarii_riders", &"marching_bastion"],
	&"gladehost": [&"grove_warden", &"grove_warden", &"thornbow_scout", &"thornbow_scout", &"stag_rider", &"dryad"],
	&"tainted_jade": [&"jade_fang", &"jade_fang", &"jungle_stalker", &"serpent_guardian", &"coatl_shaman"],
	&"skulloath": [&"warband_raider", &"warband_raider", &"steppe_rider", &"skulloath_raider", &"bonecaller", &"runebound_wyvern", &"dread_riders"],
}

func _init_armies() -> void:
	for faction_id in DataManager.factions:
		if _is_shardhorde_type(faction_id):
			continue # Shardhorde-type armies handled in _init_shardhorde_armies
		if faction_id in NOMADIC_FACTIONS:
			_init_nomadic_army(faction_id)
			continue
		var faction_data: FactionData = DataManager.factions[faction_id]
		if faction_data.starting_regions.is_empty():
			continue

		var center := MapGenerator.get_region_center(faction_data.starting_regions[0])

		# Use hardcoded composition if available, otherwise build from faction units
		var unit_ids: Array = MAJOR_STARTING_ARMIES.get(faction_id, [])
		if unit_ids.is_empty():
			unit_ids = _get_generic_starting_units(faction_id)
		if unit_ids.is_empty():
			continue

		var army := _create_army(faction_id, center, unit_ids)
		state.armies[army.army_id] = army

	# Shardhorde elderbeasts + escort armies
	_init_shardhorde_armies()

func _get_generic_starting_units(faction_id: StringName) -> Array:
	# Build a starting army from whatever units exist for this faction
	var faction_units: Array = []
	for unit_id in DataManager.units:
		var ud: UnitData = DataManager.units[unit_id]
		if ud.faction_id == faction_id:
			faction_units.append(ud.id)
	if faction_units.is_empty():
		# Try parent faction units for minor factions
		var parent_id: StringName = MINOR_FACTION_PARENTS.get(faction_id, &"")
		if parent_id != &"":
			for unit_id in DataManager.units:
				var ud: UnitData = DataManager.units[unit_id]
				if ud.faction_id == parent_id:
					faction_units.append(ud.id)
	if faction_units.is_empty():
		return []

	# Major factions get 4 units, minor factions get 3
	var is_minor := MINOR_FACTION_PARENTS.has(faction_id)
	var count := 3 if is_minor else 4
	var result: Array = []
	for i in count:
		result.append(faction_units[i % faction_units.size()])
	return result

func _init_nomadic_army(faction_id: StringName) -> void:
	# Nomadic non-shardhorde factions (e.g. sunblessed) get an army at a random neutral tile
	var unit_ids := _get_generic_starting_units(faction_id)
	if unit_ids.is_empty():
		return
	# Find a suitable spawn position (neutral tile near center)
	var spawn_pos := Vector2i(32, 22)
	for coord in state.hex_map.tiles:
		var tile: HexMapData.TileState = state.hex_map.tiles[coord]
		if tile.terrain != Enums.TerrainType.WATER and tile.owner_faction == &"":
			if HexHelper.hex_distance(coord, Vector2i(32, 22)) < 12:
				spawn_pos = coord
				break
	var army := _create_army(faction_id, spawn_pos, unit_ids)
	state.armies[army.army_id] = army

func _init_shardhorde_armies() -> void:
	var beast_ids := state.elderbeasts.keys()
	if beast_ids.size() >= 1:
		var beast1: ElderbeastState = state.elderbeasts[beast_ids[0]]
		var escort := _create_army(&"shardhorde", beast1.hex_pos,
			[&"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling", &"crystalback_raptor"])
		escort.elderbeast_id = beast1.beast_id
		state.armies[escort.army_id] = escort
		beast1.escort_army_id = escort.army_id
		_add_elderbeast_to_army(beast1, escort)
		beast1.commander = _create_commander(&"shardhorde")
		beast1.commander.name = beast1.name
		beast1.commander.is_elderbeast = true
		escort.commander = beast1.commander
		escort.commander_name = beast1.commander.name
	if beast_ids.size() >= 2:
		var beast2: ElderbeastState = state.elderbeasts[beast_ids[1]]
		var raider := _create_army(&"shardhorde", beast2.hex_pos,
			[&"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling", &"crystal_swarmling"])
		raider.elderbeast_id = beast2.beast_id
		state.armies[raider.army_id] = raider
		beast2.escort_army_id = raider.army_id
		_add_elderbeast_to_army(beast2, raider)
		beast2.commander = _create_commander(&"shardhorde")
		beast2.commander.name = beast2.name
		beast2.commander.is_elderbeast = true
		raider.commander = beast2.commander
		raider.commander_name = beast2.commander.name

func _create_army(faction_id: StringName, hex_pos: Vector2i, unit_ids: Array) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = state.generate_id()
	army.faction_id = faction_id
	army.hex_pos = hex_pos
	army.movement_remaining = 2.0

	for uid in unit_ids:
		var unit_data := DataManager.get_unit(uid)
		if unit_data:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, state.generate_id())
			army.units.append(instance)

	# Set max movement from unit composition
	army.movement_remaining = army.get_max_movement()
	return army

func _add_elderbeast_to_army(beast: ElderbeastState, army: ArmyState) -> void:
	var unit_data := DataManager.get_unit(beast.get_unit_data_id())
	if unit_data == null:
		return
	var instance := UnitInstance.new()
	instance.instance_id = beast.beast_id # Use beast_id as instance_id for easy lookup
	instance.unit_data_id = unit_data.id
	instance.current_hp = beast.hp
	beast.unit_instance_id = instance.instance_id
	army.units.insert(0, instance)
	# Set elderbeast commander as army general
	if beast.commander:
		army.commander = beast.commander
		army.commander_name = beast.commander.name

func _generate_commander_name(faction_id: StringName) -> String:
	var names: Array = COMMANDER_NAMES.get(faction_id, [])
	if names.is_empty():
		return "Commander"
	var idx: int = _commander_name_counters.get(faction_id, 0)
	var name: String = names[idx % names.size()]
	_commander_name_counters[faction_id] = idx + 1
	return name

func _get_faction_starting_city_count(faction_id: StringName) -> int:
	if faction_id == &"" or faction_id in NOMADIC_FACTIONS:
		return 0
	if MINOR_FACTION_PARENTS.has(faction_id):
		return 1  # Minor factions: 1 city
	return 2  # Major factions: 2 cities

func _get_region_starting_faction(region_id: StringName) -> StringName:
	for faction_id in DataManager.factions:
		var fd: FactionData = DataManager.factions[faction_id]
		if region_id in fd.starting_regions:
			return faction_id
	return &""

func _find_valid_city_pos(region_center: Vector2i, offset: Vector2i) -> Vector2i:
	var target := region_center + offset
	# Clamp to map bounds
	target.x = clampi(target.x, 0, HexMapData.MAP_WIDTH - 1)
	target.y = clampi(target.y, 0, HexMapData.MAP_HEIGHT - 1)
	# Check if the target tile is valid land
	var tile := state.hex_map.get_tile(target)
	if tile and tile.terrain != Enums.TerrainType.WATER:
		return target
	# Fallback: spiral search for nearest land tile
	for radius in range(1, 5):
		for neighbor in HexHelper.get_neighbors(target):
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile := state.hex_map.get_tile(neighbor)
			if ntile and ntile.terrain != Enums.TerrainType.WATER:
				return neighbor
	return region_center  # Ultimate fallback

func _init_cities() -> void:
	# Faction-specific starting buildings
	var faction_starting_buildings := {
		&"empire": &"cohort_barracks",
		&"skulloath": &"raiders_den",
		&"gladehost": &"ranger_outpost",
		&"tainted_jade": &"serpent_pit",
	}

	for region_id in REGION_CITIES:
		var slots: Array = REGION_CITIES[region_id]
		var region_center := MapGenerator.get_region_center(region_id)

		# Determine which faction owns this region
		var owning_faction := _get_region_starting_faction(region_id)
		var faction_cities_placed := 0
		var max_faction_cities := _get_faction_starting_city_count(owning_faction)

		for i in slots.size():
			var slot: Dictionary = slots[i]
			var city_pos := _find_valid_city_pos(region_center, slot.offset)
			var city := CityState.new()
			city.city_id = state.generate_id()
			city.city_name = slot.name
			city.region_id = region_id
			city.hex_pos = city_pos
			city.level = 1
			city.population = 80
			city.loyalty = 40
			city.class_loyalty = {
				"peasants": 40, "artisans": 40, "scholars": 40, "nobles": 40, "captives": 0
			}
			city.original_faction_id = owning_faction if owning_faction != &"" else &"independent"
			city.turns_since_capture = -1

			# First N cities go to the owning faction, rest are independent
			if owning_faction != &"" and owning_faction not in NOMADIC_FACTIONS and faction_cities_placed < max_faction_cities:
				city.faction_id = owning_faction
				city.loyalty = 50
				city.population = 100
				city.class_loyalty = {
					"peasants": 50, "artisans": 50, "scholars": 50, "nobles": 50, "captives": 0
				}
				if faction_cities_placed == 0:
					city.is_capital = true
					# Faction-specific starting building
					var building: StringName = faction_starting_buildings.get(owning_faction, &"")
					if building != &"":
						city.buildings.append(building)
					# Grant player a free settlement founding on turn 1
					if owning_faction == state.player_faction_id:
						city.can_found_settlement = true
				faction_cities_placed += 1
				var fs: FactionState = state.faction_states.get(owning_faction)
				if fs:
					fs.owned_cities.append(city.city_id)
			else:
				city.faction_id = &"independent"
				city.loyalty = 60  # Independent cities are self-content
				city.class_loyalty = {
					"peasants": 60, "artisans": 60, "scholars": 60, "nobles": 60, "captives": 0
				}

			state.cities[city.city_id] = city

func _init_elderbeasts() -> void:
	var shard_data: FactionData = DataManager.get_faction(&"shardhorde")
	if shard_data == null:
		return

	# Shardhorde is nomadic — spawn elderbeasts near Skulloath territory (central steppe)
	var region_id: StringName = &"bataarbad"
	var center := MapGenerator.get_region_center(region_id)

	# Find suitable hex positions near center (doesn't need to be in the region)
	var hex_map := state.hex_map
	var valid_hexes: Array[Vector2i] = []
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.WETLANDS:
			if HexHelper.hex_distance(coord, center) <= 8:
				valid_hexes.append(coord)

	var beast1_pos := center
	var beast2_pos := center
	# Find a second position away from center
	for coord in valid_hexes:
		if HexHelper.hex_distance(coord, center) >= 3 and HexHelper.hex_distance(coord, center) <= 5:
			beast2_pos = coord
			break

	# Create first elderbeast with barracks
	var beast1 := ElderbeastState.new()
	beast1.beast_id = state.generate_id()
	beast1.faction_id = &"shardhorde"
	beast1.hex_pos = beast1_pos
	beast1.name = "Elder Crystalhorn"
	beast1.level = 1
	beast1.apply_level_stats()
	beast1.hp = beast1.max_hp
	# Elderbeasts recruit all faction units directly — no barracks needed
	state.elderbeasts[beast1.beast_id] = beast1

	# Create second elderbeast empty
	var beast2 := ElderbeastState.new()
	beast2.beast_id = state.generate_id()
	beast2.faction_id = &"shardhorde"
	beast2.hex_pos = beast2_pos
	beast2.name = "Ancient Shardback"
	beast2.level = 1
	beast2.apply_level_stats()
	beast2.hp = beast2.max_hp
	state.elderbeasts[beast2.beast_id] = beast2

func _create_commander(faction_id: StringName) -> CommanderState:
	var cmd := CommanderState.new()
	cmd.commander_id = state.generate_id()
	cmd.name = _generate_commander_name(faction_id)
	cmd.faction_id = faction_id
	cmd.level = 1
	cmd.xp = 0
	if CommanderSystem and CommanderSystem.skills.size() > 0:
		var minor_skills: Array[StringName] = []
		for skill_id in CommanderSystem.skills:
			var skill: CommanderSkill = CommanderSystem.skills[skill_id]
			if skill.is_minor:
				minor_skills.append(skill_id)
		if minor_skills.size() > 0:
			cmd.skill_levels[minor_skills.pick_random()] = 1
	return cmd

func _init_commander_pools() -> void:
	for faction_id in state.faction_states:
		var fs: FactionState = state.faction_states[faction_id]
		var cmd := _create_commander(faction_id)
		# Auto-assign the first commander to the first army without one
		var armies := get_faction_armies(faction_id)
		var assigned := false
		for army in armies:
			if army.commander == null:
				army.commander = cmd
				army.commander_name = cmd.name
				assigned = true
				break
		if not assigned:
			fs.commander_pool.append(cmd)

func assign_commander_to_army(army_id: StringName, commander_id: StringName) -> bool:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or army.commander != null:
		return false
	if army.elderbeast_id != &"":
		return false
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs == null:
		return false
	for i in fs.commander_pool.size():
		if fs.commander_pool[i].commander_id == commander_id:
			army.commander = fs.commander_pool[i]
			army.commander_name = army.commander.name
			fs.commander_pool.remove_at(i)
			return true
	return false

func unassign_commander_from_army(army_id: StringName) -> bool:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or army.commander == null:
		return false
	if army.elderbeast_id != &"":
		return false
	var fs: FactionState = state.faction_states.get(army.faction_id)
	if fs == null:
		return false
	fs.commander_pool.append(army.commander)
	army.commander = null
	army.commander_name = ""
	return true

func get_available_commanders(faction_id: StringName) -> Array[CommanderState]:
	var fs: FactionState = state.faction_states.get(faction_id)
	if fs == null:
		return []
	return fs.commander_pool

func _init_diplomacy() -> void:
	# ── Minor factions are ALLIED with their parent, FRIENDLY with siblings ──
	for minor_id in MINOR_FACTION_PARENTS:
		if not state.faction_states.has(minor_id):
			continue
		var parent_id: StringName = MINOR_FACTION_PARENTS[minor_id]
		if state.faction_states.has(parent_id):
			_set_relation(minor_id, parent_id, Enums.FactionRelation.ALLIED)
		# Friendly with other minors of same parent
		for other_minor in MINOR_FACTION_PARENTS:
			if other_minor == minor_id:
				continue
			if MINOR_FACTION_PARENTS[other_minor] == parent_id:
				if state.faction_states.has(other_minor):
					_set_relation(minor_id, other_minor, Enums.FactionRelation.FRIENDLY)

	# ── Major faction relationships ──
	# Western Basin: Empire + Gladehost (allies)
	_set_relation(&"empire", &"gladehost", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"empire", &"moonspear", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"empire", &"sunblessed", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"gladehost", &"moonspear", Enums.FactionRelation.FRIENDLY)

	# Empire conflicts
	_set_relation(&"empire", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"empire", &"tainted_jade", Enums.FactionRelation.WAR)
	_set_relation(&"empire", &"forsaken", Enums.FactionRelation.HOSTILE)
	_set_relation(&"empire", &"shardhorde", Enums.FactionRelation.HOSTILE)

	# Northern belt: Moonspear + Thunderswarm (uneasy neighbors)
	_set_relation(&"moonspear", &"thunderswarm", Enums.FactionRelation.FRIENDLY)
	_set_relation(&"moonspear", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"moonspear", &"ivoryscar", Enums.FactionRelation.HOSTILE)
	_set_relation(&"moonspear", &"forsaken", Enums.FactionRelation.HOSTILE)

	_set_relation(&"thunderswarm", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"thunderswarm", &"cinderguard", Enums.FactionRelation.HOSTILE)

	# Southern: Tainted Jade vs their neighbors
	_set_relation(&"gladehost", &"tainted_jade", Enums.FactionRelation.WAR)
	_set_relation(&"tainted_jade", &"skulloath", Enums.FactionRelation.WAR)
	_set_relation(&"tainted_jade", &"shardhorde", Enums.FactionRelation.NEUTRAL)

	# Central: Skulloath + Cinderguard (rivals)
	_set_relation(&"skulloath", &"cinderguard", Enums.FactionRelation.HOSTILE)
	_set_relation(&"skulloath", &"forsaken", Enums.FactionRelation.HOSTILE)
	_set_relation(&"skulloath", &"shardhorde", Enums.FactionRelation.HOSTILE)

	# Eastern: Forsaken + Ivoryscar (uneasy neighbors)
	_set_relation(&"forsaken", &"ivoryscar", Enums.FactionRelation.HOSTILE)
	_set_relation(&"cinderguard", &"forsaken", Enums.FactionRelation.HOSTILE)

	# Shardhorde vs most
	_set_relation(&"shardhorde", &"gladehost", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"moonspear", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"thunderswarm", Enums.FactionRelation.HOSTILE)
	_set_relation(&"shardhorde", &"forsaken", Enums.FactionRelation.HOSTILE)

	# ── Minor factions inherit their parent's wars ──
	for minor_id in MINOR_FACTION_PARENTS:
		if not state.faction_states.has(minor_id):
			continue
		var parent_id: StringName = MINOR_FACTION_PARENTS[minor_id]
		for other_faction in state.faction_states:
			if other_faction == minor_id or other_faction == parent_id:
				continue
			if MINOR_FACTION_PARENTS.get(other_faction, &"") == parent_id:
				continue # Same-parent minor, already set above
			# Check if parent has a relation with this faction
			var parent_rel := _get_set_relation(parent_id, other_faction)
			if parent_rel != -1:
				var current := _get_set_relation(minor_id, other_faction)
				if current == -1: # Only set if not already defined
					_set_relation(minor_id, other_faction, parent_rel as Enums.FactionRelation)

	# ── Rebels at WAR with all ──
	for faction_id in state.faction_states:
		if faction_id != &"rebels":
			_set_relation(&"rebels", faction_id, Enums.FactionRelation.WAR)
	# ── Shard Guardians at WAR with all ──
	for faction_id in state.faction_states:
		if faction_id != &"shard_guardians":
			_set_relation(&"shard_guardians", faction_id, Enums.FactionRelation.WAR)

	# ── Initialize diplomacy standing from relations ──
	for key in state.diplomacy:
		var parts := str(key).split(":")
		if parts.size() != 2:
			continue
		var a := StringName(parts[0])
		var b := StringName(parts[1])
		if str(a) > str(b):
			continue
		var relation: int = state.diplomacy[key]
		var initial_standing := 0
		match relation:
			Enums.FactionRelation.WAR: initial_standing = -30
			Enums.FactionRelation.HOSTILE: initial_standing = -15
			Enums.FactionRelation.NEUTRAL: initial_standing = 0
			Enums.FactionRelation.FRIENDLY: initial_standing = 20
			Enums.FactionRelation.ALLIED: initial_standing = 50
		var standing_key_ab := str(a) + ":" + str(b)
		var standing_key_ba := str(b) + ":" + str(a)
		state.diplomacy_state.standing[standing_key_ab] = initial_standing
		state.diplomacy_state.standing[standing_key_ba] = initial_standing

func _set_relation(a: StringName, b: StringName, relation: Enums.FactionRelation) -> void:
	state.diplomacy[StringName(str(a) + ":" + str(b))] = relation
	state.diplomacy[StringName(str(b) + ":" + str(a))] = relation

func _get_set_relation(a: StringName, b: StringName) -> int:
	var key := StringName(str(a) + ":" + str(b))
	if state.diplomacy.has(key):
		return state.diplomacy[key]
	return -1

# ── Region & Culture Completion ──────────────────────────────
func get_completed_regions(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for region_id in REGION_CITIES:
		var all_owned := true
		for city_id in state.cities:
			var city: CityState = state.cities[city_id]
			if city.region_id == region_id and city.faction_id != faction_id:
				all_owned = false
				break
		if all_owned:
			result.append(region_id)
	return result

func get_completed_cultures(faction_id: StringName) -> Array[StringName]:
	var completed_regions := get_completed_regions(faction_id)
	var result: Array[StringName] = []
	for culture_id in CULTURE_REGIONS:
		var regions: Array = CULTURE_REGIONS[culture_id]
		var all_complete := true
		for r in regions:
			if r not in completed_regions:
				all_complete = false
				break
		if all_complete:
			result.append(culture_id)
	return result

func has_culture_bonus(faction_id: StringName, bonus_type: String) -> bool:
	var completed := get_completed_cultures(faction_id)
	for culture_id in completed:
		var bonus: Dictionary = CULTURE_BONUSES.get(culture_id, {})
		if bonus.get("type", "") == bonus_type:
			return true
	return false

func get_culture_bonus_value(faction_id: StringName, bonus_type: String) -> float:
	var total := 0.0
	var completed := get_completed_cultures(faction_id)
	for culture_id in completed:
		var bonus: Dictionary = CULTURE_BONUSES.get(culture_id, {})
		if bonus.get("type", "") == bonus_type:
			total += bonus.get("value", 0.0)
	return total

func get_elderbeast_at_tile(coord: Vector2i) -> ElderbeastState:
	for beast_id in state.elderbeasts:
		var beast: ElderbeastState = state.elderbeasts[beast_id]
		if beast.hex_pos == coord:
			return beast
	return null

func get_faction_elderbeasts(faction_id: StringName) -> Array[ElderbeastState]:
	var result: Array[ElderbeastState] = []
	for beast_id in state.elderbeasts:
		var beast: ElderbeastState = state.elderbeasts[beast_id]
		if beast.faction_id == faction_id:
			result.append(beast)
	return result

func get_army_at_tile(coord: Vector2i) -> ArmyState:
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			return army
	return null

func get_armies_at_tile(coord: Vector2i) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			result.append(army)
	return result

func get_enemies_at_tile(coord: Vector2i, my_faction: StringName) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army in get_armies_at_tile(coord):
		if army.faction_id == my_faction:
			continue
		var relation := get_relation(my_faction, army.faction_id)
		if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
			result.append(army)
	return result

func get_relation(faction_a: StringName, faction_b: StringName) -> Enums.FactionRelation:
	if faction_a == faction_b:
		return Enums.FactionRelation.ALLIED
	var key := StringName(str(faction_a) + ":" + str(faction_b))
	return state.diplomacy.get(key, Enums.FactionRelation.NEUTRAL)

func merge_armies_at_tile(coord: Vector2i, faction_id: StringName, prefer_army_id: StringName = &"") -> void:
	var armies_here: Array[ArmyState] = []
	for aid in state.armies:
		var army: ArmyState = state.armies[aid]
		if army.hex_pos == coord and army.faction_id == faction_id and not army.is_garrison:
			armies_here.append(army)
	if armies_here.size() <= 1:
		return
	# Prefer the specified army as merge target
	var target: ArmyState = armies_here[0]
	if prefer_army_id != &"":
		for a in armies_here:
			if a.army_id == prefer_army_id:
				target = a
				break
	for a in armies_here:
		if a.army_id == target.army_id:
			continue
		for unit in a.units:
			target.units.append(unit)
		# Keep the higher-level commander, return the other to pool
		if a.commander and target.commander:
			if a.commander.level > target.commander.level:
				# Return target's weaker commander to pool
				var fs: FactionState = state.faction_states.get(faction_id)
				if fs:
					fs.commander_pool.append(target.commander)
				target.commander = a.commander
				target.commander_name = a.commander.name
			# The merged army's commander will be returned by remove_army
		elif a.commander and target.commander == null:
			target.commander = a.commander
			target.commander_name = a.commander.name
		# Clear commander before remove_army so it doesn't double-return
		a.commander = null
		remove_army(a.army_id)

func can_afford_settlement(faction_id: StringName) -> bool:
	var fs: FactionState = state.faction_states.get(faction_id)
	if fs == null:
		return false
	for res_type in CitySystem.SETTLEMENT_FOUNDING_COST:
		if fs.resources.get(res_type, 0) < CitySystem.SETTLEMENT_FOUNDING_COST[res_type]:
			return false
	return true

func found_settlement(faction_id: StringName, hex_pos: Vector2i, parent_city_id: StringName) -> StringName:
	var parent_city: CityState = state.cities.get(parent_city_id)
	if parent_city == null:
		return &""

	var tile := state.hex_map.get_tile(hex_pos)
	if tile == null:
		return &""

	# Deduct founding cost
	var fs: FactionState = state.faction_states.get(faction_id)
	if fs:
		for res_type in CitySystem.SETTLEMENT_FOUNDING_COST:
			fs.resources[res_type] = fs.resources.get(res_type, 0) - CitySystem.SETTLEMENT_FOUNDING_COST[res_type]

	var city := CityState.new()
	city.city_id = state.generate_id()
	city.region_id = tile.region_id
	city.faction_id = faction_id
	city.hex_pos = hex_pos
	city.level = 1
	city.population = 50
	city.is_capital = false
	city.original_faction_id = faction_id
	city.loyalty = 50
	city.class_loyalty = {
		"peasants": 50, "artisans": 50, "scholars": 50, "nobles": 50, "captives": 0
	}
	city.turns_since_capture = -1
	state.cities[city.city_id] = city

	if fs:
		fs.owned_cities.append(city.city_id)

	# Mark parent capital as having used its founding ability
	parent_city.can_found_settlement = false

	return city.city_id

func get_faction_armies(faction_id: StringName) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.faction_id == faction_id and not army.is_garrison:
			result.append(army)
	return result

func move_army_along_path(army_id: StringName, path: Array[Vector2i]) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or path.is_empty():
		return
	# Injured elderbeast prevents army movement
	if army.elderbeast_id != &"":
		var beast: ElderbeastState = state.elderbeasts.get(army.elderbeast_id)
		if beast and beast.is_injured():
			return

	for tile_coord in path:
		var cost := state.hex_map.get_movement_cost(tile_coord, army.faction_id)
		if army.movement_remaining < cost:
			break

		# Check if army is leaving a besieged city hex
		_check_siege_departure(army)

		var from_pos := army.hex_pos
		army.hex_pos = tile_coord
		army.movement_remaining -= cost
		army.has_moved = true
		# Sync elderbeast position with army
		if army.elderbeast_id != &"":
			var beast: ElderbeastState = state.elderbeasts.get(army.elderbeast_id)
			if beast:
				var old_beast_pos := beast.hex_pos
				beast.hex_pos = tile_coord
				EventBus.elderbeast_moved.emit(beast.beast_id, old_beast_pos, tile_coord)
		EventBus.army_moved.emit(army_id, from_pos, tile_coord)

		# Check for battle
		var enemies := get_enemies_at_tile(tile_coord, army.faction_id)
		if enemies.size() > 0:
			EventBus.battle_initiated.emit(army_id, enemies[0].army_id, tile_coord)
			return

		# Check for enemy city at this hex → garrison battle or siege
		var city_at := city_system.get_city_at_hex(tile_coord)
		if city_at and city_at.faction_id != army.faction_id:
			if not city_at.is_under_siege or city_at.siege_faction != army.faction_id:
				# Spawn garrison army and fight before siege can begin
				var garrison := city_system.create_garrison_army(city_at)
				state.armies[garrison.army_id] = garrison
				EventBus.battle_initiated.emit(army_id, garrison.army_id, tile_coord)
				return

		# Break siege on own cities if army arrives
		if city_at and city_at.faction_id == army.faction_id and city_at.is_under_siege:
			city_system.break_siege(city_at.city_id)

		# Claim unclaimed shards
		_try_claim_shard(tile_coord, army.faction_id)

		# Merge with friendly army at this tile
		var friendly_armies := get_armies_at_tile(tile_coord)
		if friendly_armies.size() > 1:
			merge_armies_at_tile(tile_coord, army.faction_id, army_id)
			if not state.armies.has(army_id):
				return # This army was absorbed into another

		# Take ownership of neutral tiles in the region
		var tile := state.hex_map.get_tile(tile_coord)
		if tile and tile.owner_faction == &"":
			tile.owner_faction = army.faction_id

func _check_siege_departure(army: ArmyState) -> void:
	# If this army was besieging a city and is now leaving, check if any other
	# friendly army remains. If not, break siege.
	var city_at := city_system.get_city_at_hex(army.hex_pos)
	if city_at == null or not city_at.is_under_siege:
		return
	if city_at.siege_faction != army.faction_id:
		return
	# Check if any OTHER friendly army remains at this hex
	var other_present := false
	for aid in state.armies:
		var a: ArmyState = state.armies[aid]
		if a.army_id != army.army_id and a.hex_pos == army.hex_pos and a.faction_id == army.faction_id:
			other_present = true
			break
	if not other_present:
		city_system.break_siege(city_at.city_id)

func _try_claim_shard(hex_pos: Vector2i, faction_id: StringName) -> void:
	# Block claiming if shard guardian army still alive at this hex
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.faction_id == &"shard_guardians" and army.hex_pos == hex_pos:
			return
	for shard_id in state.active_shards:
		var shard: ShardInstance = state.active_shards[shard_id]
		if shard.hex_pos == hex_pos and shard.claimed_by == &"":
			shard.claimed_by = faction_id
			var fs: FactionState = state.faction_states.get(faction_id)
			if fs:
				fs.owned_shards.append(shard_id)
				# Award Shard Essence based on power_level (15 base + 5 per extra power)
				var shard_value: int = 15 + (shard.power_level - 1) * 5
				fs.resources[Enums.ResourceType.SHARD_ESSENCE] = fs.resources.get(Enums.ResourceType.SHARD_ESSENCE, 0) + shard_value
			EventBus.shard_claimed.emit(shard_id, faction_id)
			break

func remove_army(army_id: StringName) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army:
		# Return commander to pool if army had one
		if army.commander:
			var fs: FactionState = state.faction_states.get(army.faction_id)
			if fs:
				fs.commander_pool.append(army.commander)
			army.commander = null
		EventBus.army_destroyed.emit(army_id, army.faction_id)
		state.armies.erase(army_id)

func change_region_owner(region_id: StringName, new_owner: StringName) -> void:
	var old_owner := state.get_region_owner(region_id)

	# Remove from old owner
	if old_owner != &"":
		var old_fs: FactionState = state.faction_states.get(old_owner)
		if old_fs:
			old_fs.owned_regions.erase(region_id)

	# Set all tiles in region to new owner
	state.hex_map.set_region_owner(region_id, new_owner)

	# Add to new owner
	if new_owner != &"":
		var new_fs: FactionState = state.faction_states.get(new_owner)
		if new_fs and not new_fs.owned_regions.has(region_id):
			new_fs.owned_regions.append(region_id)

	EventBus.region_ownership_changed.emit(region_id, old_owner, new_owner)
