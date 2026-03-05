#!/usr/bin/env python3
"""Second batch of research items to bring each faction closer to ~50."""

import os

TRES_TEMPLATE = """[gd_resource type="Resource" script_class="ResearchData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/research_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"{id}"
display_name = "{display_name}"
description = "{description}"
tech_cost = {tech_cost}
research_time = {research_time}
prerequisites = Array[StringName]([{prerequisites}])
effects = {{ {effects} }}
shard_bonuses = {{{shard_bonuses}}}
tier = {tier}
research_category = &"{category}"
faction_id = &"{faction_id}"
tree_angle = {tree_angle}
tree_branch = &"{tree_branch}"
"""

BASE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "research")
TIER_COSTS = {1: 50, 2: 90, 3: 130, 4: 180, 5: 250}
TIER_TIMES = {1: 8, 2: 12, 3: 16, 4: 20, 5: 26}

def fmt_prereqs(prereqs):
    return ", ".join(f'&"{p}"' for p in prereqs) if prereqs else ""

def fmt_effects(effects):
    return ", ".join(f'"{k}": {v}' for k, v in effects.items()) if effects else ""

def write_tres(faction_folder, data):
    folder = os.path.join(BASE_DIR, faction_folder)
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, f"{data['id']}.tres")
    if os.path.exists(filepath):
        return 0
    content = TRES_TEMPLATE.format(
        id=data["id"], display_name=data["display_name"], description=data["description"],
        tech_cost=data.get("tech_cost", TIER_COSTS[data["tier"]]),
        research_time=data.get("research_time", TIER_TIMES[data["tier"]]),
        prerequisites=fmt_prereqs(data.get("prerequisites", [])),
        effects=fmt_effects(data.get("effects", {})),
        shard_bonuses=data.get("shard_bonuses", ""),
        tier=data["tier"], category=data.get("category", "military"),
        faction_id=data.get("faction_id", ""), tree_angle=data.get("tree_angle", 0.0),
        tree_branch=data.get("tree_branch", ""),
    )
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content.lstrip())
    return 1

# Fill in missing T2-T3 items to create fuller branches
EMPIRE_B2 = [
    {"id": "emp_field_medicine", "display_name": "Field Medicine", "description": "Surgeons tend the wounded on the field.", "tier": 2, "category": "logistics", "prerequisites": ["stonework"], "effects": {"unit_hp_bonus": 5}, "tree_angle": 195.0, "tree_branch": "engineering"},
    {"id": "emp_tax_collectors", "display_name": "Tax Collectors", "description": "Efficient tax collection fills coffers.", "tier": 2, "category": "economy", "prerequisites": ["provincial_order"], "effects": {"income_gold_pct": 8}, "tree_angle": 285.0, "tree_branch": "governance"},
    {"id": "emp_auxiliary_corps", "display_name": "Auxiliary Corps", "description": "Foreign auxiliaries bolster the legions.", "tier": 2, "category": "military", "prerequisites": ["imperial_drill"], "effects": {"recruitment_cost_reduction": 8}, "tree_angle": 25.0, "tree_branch": "warfare"},
    {"id": "emp_war_academy", "display_name": "War Academy", "description": "Officers train in strategy and tactics.", "tier": 3, "category": "military", "prerequisites": ["centurion_tactics", "emp_auxiliary_corps"], "effects": {"unit_attack_bonus": 2, "flanking_damage_bonus": 10}, "tree_angle": 20.0, "tree_branch": "warfare"},
    {"id": "emp_supply_trains", "display_name": "Supply Trains", "description": "Organized supply trains sustain campaigns.", "tier": 3, "category": "logistics", "prerequisites": ["road_network", "logistics_reform_emp"], "effects": {"supply_range_bonus": 2, "movement_bonus": 1}, "tree_angle": 150.0, "tree_branch": "commerce"},
    {"id": "emp_court_mages", "display_name": "Court Mages", "description": "Imperial court mages advise the Emperor.", "tier": 3, "category": "arcane", "prerequisites": ["emp_battle_mages"], "effects": {"research_speed_bonus": 12}, "tree_angle": 45.0, "tree_branch": "arcane"},
    {"id": "emp_harbor_cities", "display_name": "Harbor Cities", "description": "Great ports bring wealth from sea trade.", "tier": 3, "category": "economy", "prerequisites": ["merchant_guilds", "road_network"], "effects": {"income_gold_pct": 10, "trade_income_bonus": 10}, "tree_angle": 105.0, "tree_branch": "commerce"},
    {"id": "emp_census", "display_name": "Imperial Census", "description": "Counting every citizen improves governance.", "tier": 3, "category": "economy", "prerequisites": ["senate_authority", "emp_tax_collectors"], "effects": {"income_gold_pct": 8, "upkeep_reduction": 5}, "tree_angle": 255.0, "tree_branch": "governance"},
    {"id": "emp_fortified_camps", "display_name": "Fortified Camps", "description": "Legions build fortified camps every night.", "tier": 3, "category": "logistics", "prerequisites": ["logistics_reform_emp", "emp_field_medicine"], "effects": {"defense_bonus": 4, "unit_hp_bonus": 5}, "tree_angle": 195.0, "tree_branch": "engineering"},
    {"id": "emp_triumphal_arches", "display_name": "Triumphal Arches", "description": "Monuments inspire morale across the empire.", "tier": 4, "category": "economy", "prerequisites": ["pax_imperialis", "emp_census"], "effects": {"unit_morale_bonus": 12}, "tree_angle": 260.0, "tree_branch": "governance"},
]

GLADEHOST_B2 = [
    {"id": "gh_root_bridges", "display_name": "Root Bridges", "description": "Living bridges connect forest canopy.", "tier": 2, "category": "logistics", "prerequisites": ["deep_roots"], "effects": {"movement_bonus": 1}, "tree_angle": 340.0, "tree_branch": "nature_bond"},
    {"id": "gh_bark_armor", "display_name": "Bark Armor", "description": "Enchanted bark harder than steel.", "tier": 2, "category": "military", "prerequisites": ["forest_ambush"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 80.0, "tree_branch": "wardenship"},
    {"id": "gh_spirit_sight", "display_name": "Spirit Sight", "description": "Spirits reveal hidden threats.", "tier": 2, "category": "arcane", "prerequisites": ["spirit_whispers"], "effects": {"vision_range_bonus": 1}, "tree_angle": 195.0, "tree_branch": "spirit_lore"},
    {"id": "gh_herb_gardens", "display_name": "Herb Gardens", "description": "Cultivated healing herbs sustain armies.", "tier": 2, "category": "economy", "prerequisites": ["healing_salves"], "effects": {"income_food_pct": 8}, "tree_angle": 285.0, "tree_branch": "herbalism"},
    {"id": "gh_forest_trade", "display_name": "Forest Trade", "description": "Rare forest goods fetch high prices.", "tier": 3, "category": "economy", "prerequisites": ["gh_herb_gardens", "seed_scattering"], "effects": {"trade_income_bonus": 12, "income_gold_pct": 8}, "tree_angle": 300.0, "tree_branch": "herbalism"},
    {"id": "gh_wild_hunt", "display_name": "Wild Hunt", "description": "The legendary Wild Hunt rides forth.", "tier": 3, "category": "military", "prerequisites": ["gh_dire_companions", "living_walls"], "effects": {"unit_attack_bonus": 3, "unit_speed_bonus": 2}, "tree_angle": 75.0, "tree_branch": "beast_affinity"},
    {"id": "gh_nature_ward", "display_name": "Nature Ward", "description": "Forest magic protects all within.", "tier": 3, "category": "arcane", "prerequisites": ["spirit_pact", "gh_spirit_sight"], "effects": {"unit_defense_bonus": 3, "defense_bonus": 4}, "tree_angle": 200.0, "tree_branch": "spirit_lore"},
    {"id": "gh_woodsingers", "display_name": "Woodsingers", "description": "Singers who shape living wood.", "tier": 3, "category": "arcane", "prerequisites": ["verdant_growth", "gh_root_bridges"], "effects": {"defense_bonus": 5, "income_food_pct": 8}, "tree_angle": 345.0, "tree_branch": "nature_bond"},
    {"id": "gh_verdant_tide", "display_name": "Verdant Tide", "description": "Forest reclaims conquered lands.", "tier": 4, "category": "arcane", "prerequisites": ["heart_of_the_forest", "gh_woodsingers"], "effects": {"unit_defense_bonus": 3, "defense_bonus": 6}, "tree_angle": 10.0, "tree_branch": "nature_bond"},
    {"id": "gh_spirit_healers", "display_name": "Spirit Healers", "description": "Spirit-touched healers mend all wounds.", "tier": 4, "category": "economy", "prerequisites": ["grove_sanctuary", "gh_forest_trade"], "effects": {"unit_hp_bonus": 12, "income_food_pct": 10}, "tree_angle": 280.0, "tree_branch": "herbalism"},
    {"id": "gh_forest_wrath", "display_name": "Forest's Wrath", "description": "The forest itself strikes down invaders.", "tier": 4, "category": "military", "prerequisites": ["entangling_roots", "gh_wild_hunt"], "effects": {"unit_attack_bonus": 3, "defense_bonus": 5}, "tree_angle": 80.0, "tree_branch": "wardenship"},
]

SKULLOATH_B2 = [
    {"id": "sk_mounted_archers", "display_name": "Mounted Archers", "description": "Rain arrows from horseback.", "tier": 2, "category": "military", "prerequisites": ["horseback_archery"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 30.0, "tree_branch": "raiding"},
    {"id": "sk_yurt_camps", "display_name": "Yurt Camps", "description": "Mobile camps sustain long campaigns.", "tier": 2, "category": "logistics", "prerequisites": ["pasture_mastery"], "effects": {"supply_range_bonus": 1, "movement_bonus": 1}, "tree_angle": 105.0, "tree_branch": "steppe_craft"},
    {"id": "sk_bone_armor", "display_name": "Bone Armor", "description": "Armor crafted from ancestor bones.", "tier": 2, "category": "arcane", "prerequisites": ["bone_rituals"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 165.0, "tree_branch": "ancestor_rites"},
    {"id": "sk_raid_spoils", "display_name": "Raid Spoils", "description": "Plunder enriches the horde.", "tier": 3, "category": "economy", "prerequisites": ["terror_tactics", "steppe_ambush"], "effects": {"income_gold_pct": 12, "trade_income_bonus": 8}, "tree_angle": 15.0, "tree_branch": "raiding"},
    {"id": "sk_horse_lords", "display_name": "Horse Lords", "description": "Supreme mastery of mounted warfare.", "tier": 3, "category": "military", "prerequisites": ["sk_mounted_archers", "steppe_ambush"], "effects": {"unit_speed_bonus": 2, "unit_attack_bonus": 2}, "tree_angle": 30.0, "tree_branch": "raiding"},
    {"id": "sk_leather_works", "display_name": "Leather Works", "description": "Hide and leather goods fuel trade.", "tier": 3, "category": "economy", "prerequisites": ["caravan_routes", "sk_yurt_camps"], "effects": {"income_gold_pct": 8, "upkeep_reduction": 5}, "tree_angle": 105.0, "tree_branch": "steppe_craft"},
    {"id": "sk_spirit_totems", "display_name": "Spirit Totems", "description": "Totems channel ancestral power.", "tier": 3, "category": "arcane", "prerequisites": ["ancestor_call", "sk_bone_armor"], "effects": {"unit_morale_bonus": 10, "unit_defense_bonus": 2}, "tree_angle": 170.0, "tree_branch": "ancestor_rites"},
    {"id": "sk_clan_bonds", "display_name": "Clan Bonds", "description": "Unbreakable bonds between warrior clans.", "tier": 3, "category": "military", "prerequisites": ["warg_breeding", "nomad_resilience"], "effects": {"unit_morale_bonus": 10, "recruitment_cost_reduction": 8}, "tree_angle": 280.0, "tree_branch": "horde_unity"},
    {"id": "sk_vast_camps", "display_name": "Vast Encampments", "description": "Enormous camps house the growing horde.", "tier": 4, "category": "logistics", "prerequisites": ["great_yurt", "sk_leather_works"], "effects": {"supply_range_bonus": 2, "income_food_pct": 12}, "tree_angle": 95.0, "tree_branch": "steppe_craft"},
    {"id": "sk_death_riders", "display_name": "Death Riders", "description": "Riders who have conquered death itself.", "tier": 4, "category": "military", "prerequisites": ["skull_banner", "sk_horse_lords"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 2}, "tree_angle": 10.0, "tree_branch": "raiding"},
    {"id": "sk_war_council", "display_name": "War Council", "description": "The Great Khan's war council plans conquest.", "tier": 4, "category": "military", "prerequisites": ["endless_horde", "sk_clan_bonds"], "effects": {"unit_morale_bonus": 12, "unit_attack_bonus": 2}, "tree_angle": 275.0, "tree_branch": "horde_unity"},
]

MOONSPEAR_B2 = [
    {"id": "ms_moon_shields", "display_name": "Moon Shields", "description": "Shields blessed by moonlight.", "tier": 2, "category": "military", "prerequisites": ["silverforging"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 110.0, "tree_branch": "silver_arms"},
    {"id": "ms_prophet_visions", "display_name": "Prophet Visions", "description": "Prophets foresee enemy movements.", "tier": 2, "category": "arcane", "prerequisites": ["moonlit_prayers"], "effects": {"vision_range_bonus": 1}, "tree_angle": 30.0, "tree_branch": "lunar_doctrine"},
    {"id": "ms_temple_wealth", "display_name": "Temple Wealth", "description": "Temple treasuries overflow.", "tier": 2, "category": "economy", "prerequisites": ["sacred_texts"], "effects": {"income_gold_pct": 8}, "tree_angle": 225.0, "tree_branch": "enlightenment"},
    {"id": "ms_silver_mines", "display_name": "Silver Mines", "description": "Sacred silver mines enrich the faith.", "tier": 3, "category": "economy", "prerequisites": ["crescent_shield", "ms_moon_shields"], "effects": {"income_gold_pct": 10}, "tree_angle": 105.0, "tree_branch": "silver_arms"},
    {"id": "ms_lunar_knights", "display_name": "Lunar Knights", "description": "Knights sworn to the moon's service.", "tier": 3, "category": "military", "prerequisites": ["temple_guard", "ms_moon_shields"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 130.0, "tree_branch": "silver_arms"},
    {"id": "ms_holy_archives", "display_name": "Holy Archives", "description": "Vast archives accelerate learning.", "tier": 3, "category": "economy", "prerequisites": ["pilgrim_network", "ms_temple_wealth"], "effects": {"research_speed_bonus": 12}, "tree_angle": 235.0, "tree_branch": "enlightenment"},
    {"id": "ms_moon_phases", "display_name": "Moon Phase Mastery", "description": "Each moon phase grants different power.", "tier": 3, "category": "arcane", "prerequisites": ["celestial_insight", "ms_prophet_visions"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 15.0, "tree_branch": "lunar_doctrine"},
    {"id": "ms_star_navigation", "display_name": "Star Navigation", "description": "Navigate by the stars across any terrain.", "tier": 3, "category": "logistics", "prerequisites": ["ms_star_bolts", "astral_navigation"], "effects": {"movement_bonus": 2, "vision_range_bonus": 1}, "tree_angle": 65.0, "tree_branch": "celestial_magic"},
    {"id": "ms_moon_healers", "display_name": "Moon Healers", "description": "Moonlight itself heals the faithful.", "tier": 3, "category": "economy", "prerequisites": ["ms_holy_warriors", "ms_temple_wealth"], "effects": {"unit_hp_bonus": 8}, "tree_angle": 195.0, "tree_branch": "holy_order"},
    {"id": "ms_silver_treasury", "display_name": "Silver Treasury", "description": "Holy silver fills the coffers.", "tier": 4, "category": "economy", "prerequisites": ["ms_silver_mines", "ms_holy_archives"], "effects": {"income_gold_pct": 15, "trade_income_bonus": 10}, "tree_angle": 125.0, "tree_branch": "silver_arms"},
    {"id": "ms_cosmic_wisdom", "display_name": "Cosmic Wisdom", "description": "Wisdom of the cosmos guides all decisions.", "tier": 4, "category": "arcane", "prerequisites": ["ms_moon_phases", "ms_eclipse_rites"], "effects": {"research_speed_bonus": 15, "unit_morale_bonus": 10}, "tree_angle": 20.0, "tree_branch": "lunar_doctrine"},
]

THUNDERSWARM_B2 = [
    {"id": "ts_mountain_paths", "display_name": "Mountain Paths", "description": "Secret paths through the mountains.", "tier": 2, "category": "logistics", "prerequisites": ["peak_fortresses"], "effects": {"movement_bonus": 1}, "tree_angle": 140.0, "tree_branch": "mountain_hold"},
    {"id": "ts_battle_cry", "display_name": "Battle Cry", "description": "A terrifying war cry shakes morale.", "tier": 3, "category": "military", "prerequisites": ["warcry", "warband_unity"], "effects": {"unit_morale_bonus": 10, "unit_attack_bonus": 1}, "tree_angle": 250.0, "tree_branch": "war_fury"},
    {"id": "ts_iron_weapons", "display_name": "Iron Weapons", "description": "Superior mountain iron forged into weapons.", "tier": 2, "category": "military", "prerequisites": ["lightning_strike"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 25.0, "tree_branch": "storm_mastery"},
    {"id": "ts_storm_shields", "display_name": "Storm Shields", "description": "Lightning-resistant shields.", "tier": 3, "category": "military", "prerequisites": ["thunder_call", "ts_iron_weapons"], "effects": {"unit_defense_bonus": 3}, "tree_angle": 30.0, "tree_branch": "storm_mastery"},
    {"id": "ts_highland_trade", "display_name": "Highland Trade", "description": "Mountain passes become trade routes.", "tier": 3, "category": "economy", "prerequisites": ["stonecutter_guild", "ts_mountain_paths"], "effects": {"trade_income_bonus": 10, "income_gold_pct": 8}, "tree_angle": 140.0, "tree_branch": "mountain_hold"},
    {"id": "ts_wind_riders", "display_name": "Wind Riders", "description": "Ride the mountain winds into battle.", "tier": 3, "category": "military", "prerequisites": ["ts_aerial_assault", "ts_storm_hawks"], "effects": {"unit_speed_bonus": 2, "movement_bonus": 1}, "tree_angle": 65.0, "tree_branch": "sky_lords"},
    {"id": "ts_forge_masters", "display_name": "Forge Masters", "description": "Master smiths create unbreakable weapons.", "tier": 3, "category": "economy", "prerequisites": ["ts_thunder_weapons", "ts_rune_armor"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 185.0, "tree_branch": "iron_peak"},
    {"id": "ts_storm_harvest", "display_name": "Storm Harvest", "description": "Harness lightning for power.", "tier": 4, "category": "economy", "prerequisites": ["ts_deep_mines", "ts_highland_trade"], "effects": {"income_gold_pct": 15, "shard_harvest_bonus": 8}, "tree_angle": 130.0, "tree_branch": "mountain_hold"},
    {"id": "ts_thunder_lords", "display_name": "Thunder Lords", "description": "The mightiest warriors command storms.", "tier": 4, "category": "military", "prerequisites": ["ts_storm_shields", "ts_chain_lightning"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 2}, "tree_angle": 15.0, "tree_branch": "storm_mastery"},
]

TAINTED_JADE_B2 = [
    {"id": "tj_poison_traps", "display_name": "Poison Traps", "description": "Hidden traps laced with venom.", "tier": 2, "category": "military", "prerequisites": ["venomcraft"], "effects": {"defense_bonus": 3}, "tree_angle": 30.0, "tree_branch": "serpent_lore"},
    {"id": "tj_ritual_drums", "display_name": "Ritual Drums", "description": "Drums that drive warriors into frenzy.", "tier": 2, "category": "military", "prerequisites": ["sacrificial_altars"], "effects": {"unit_morale_bonus": 5, "unit_attack_bonus": 1}, "tree_angle": 230.0, "tree_branch": "blood_rites"},
    {"id": "tj_canopy_network", "display_name": "Canopy Network", "description": "Treetop pathways speed movement.", "tier": 3, "category": "logistics", "prerequisites": ["jungle_camouflage", "tj_poison_traps"], "effects": {"movement_bonus": 2}, "tree_angle": 25.0, "tree_branch": "serpent_lore"},
    {"id": "tj_blood_harvest", "display_name": "Blood Harvest", "description": "Sacrifices fuel the economy.", "tier": 3, "category": "economy", "prerequisites": ["blood_magic", "tj_ritual_drums"], "effects": {"income_gold_pct": 10}, "tree_angle": 245.0, "tree_branch": "blood_rites"},
    {"id": "tj_living_weapons", "display_name": "Living Weapons", "description": "Weapons grown from living plants.", "tier": 3, "category": "military", "prerequisites": ["dark_botany", "tj_toxic_darts"], "effects": {"unit_attack_bonus": 3}, "tree_angle": 95.0, "tree_branch": "dark_botany"},
    {"id": "tj_swamp_defenses", "display_name": "Swamp Defenses", "description": "Natural swamp defenses enhanced.", "tier": 3, "category": "logistics", "prerequisites": ["tj_mycelium_web", "fungal_cultivation"], "effects": {"defense_bonus": 5}, "tree_angle": 195.0, "tree_branch": "fungal_network"},
    {"id": "tj_sacrificial_fury", "display_name": "Sacrificial Fury", "description": "Blood sacrifices empower warriors.", "tier": 4, "category": "military", "prerequisites": ["blood_pact", "tj_blood_harvest"], "effects": {"unit_attack_bonus": 4, "unit_morale_bonus": 10}, "tree_angle": 250.0, "tree_branch": "blood_rites"},
    {"id": "tj_jungle_empire", "display_name": "Jungle Empire", "description": "An empire hidden within the jungle.", "tier": 4, "category": "economy", "prerequisites": ["living_city", "tj_living_weapons"], "effects": {"income_gold_pct": 15, "income_food_pct": 12}, "tree_angle": 110.0, "tree_branch": "dark_botany"},
    {"id": "tj_venom_masters", "display_name": "Venom Masters", "description": "Supreme masters of all poisons.", "tier": 3, "category": "military", "prerequisites": ["tj_toxic_darts", "tj_paralytic_venom"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 50.0, "tree_branch": "venom_mastery"},
]

CINDERGUARD_B2 = [
    {"id": "cg_heat_shields", "display_name": "Heat Shields", "description": "Shields resistant to extreme heat.", "tier": 2, "category": "military", "prerequisites": ["garrison_doctrine"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 230.0, "tree_branch": "garrison_duty"},
    {"id": "cg_ember_scouts", "display_name": "Ember Scouts", "description": "Scouts who navigate volcanic terrain.", "tier": 2, "category": "logistics", "prerequisites": ["cinder_scouts"], "effects": {"movement_bonus": 1, "vision_range_bonus": 1}, "tree_angle": 45.0, "tree_branch": "forging"},
    {"id": "cg_forge_priests", "display_name": "Forge Priests", "description": "Holy smiths bless weapons in flame.", "tier": 3, "category": "arcane", "prerequisites": ["master_smithing", "cg_ember_scouts"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 40.0, "tree_branch": "forging"},
    {"id": "cg_fire_moat", "display_name": "Fire Moat", "description": "Moats of liquid fire defend walls.", "tier": 3, "category": "logistics", "prerequisites": ["firebreak_walls", "cg_heat_shields"], "effects": {"defense_bonus": 6}, "tree_angle": 235.0, "tree_branch": "garrison_duty"},
    {"id": "cg_smoke_screen", "display_name": "Smoke Screen", "description": "Thick smoke conceals troop movements.", "tier": 3, "category": "military", "prerequisites": ["ember_medicine", "magma_channeling"], "effects": {"flanking_damage_bonus": 10, "unit_defense_bonus": 2}, "tree_angle": 130.0, "tree_branch": "flamecraft"},
    {"id": "cg_foundry_cities", "display_name": "Foundry Cities", "description": "Entire cities dedicated to metalwork.", "tier": 3, "category": "economy", "prerequisites": ["cg_blast_furnace", "volcanic_glass"], "effects": {"income_gold_pct": 10, "recruitment_cost_reduction": 8}, "tree_angle": 175.0, "tree_branch": "industry"},
    {"id": "cg_magma_lords", "display_name": "Magma Lords", "description": "Warriors who command living magma.", "tier": 3, "category": "arcane", "prerequisites": ["cg_magma_weapons", "cg_obsidian_armor"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 55.0, "tree_branch": "magma"},
    {"id": "cg_iron_walls", "display_name": "Iron Walls", "description": "Walls forged from solid iron.", "tier": 4, "category": "military", "prerequisites": ["eternal_watch", "cg_fire_moat"], "effects": {"defense_bonus": 8, "unit_defense_bonus": 3}, "tree_angle": 245.0, "tree_branch": "garrison_duty"},
    {"id": "cg_war_forges", "display_name": "War Forges", "description": "Massive forges produce weapons endlessly.", "tier": 4, "category": "economy", "prerequisites": ["cg_foundry_cities", "cg_industrial_might"], "effects": {"recruitment_cost_reduction": 15, "income_gold_pct": 10}, "tree_angle": 185.0, "tree_branch": "industry"},
]

FORSAKEN_B2 = [
    {"id": "fk_shadow_scouts", "display_name": "Shadow Scouts", "description": "Scouts that move through shadows.", "tier": 2, "category": "military", "prerequisites": ["shadow_blades"], "effects": {"vision_range_bonus": 1, "movement_bonus": 1}, "tree_angle": 225.0, "tree_branch": "shadow_war"},
    {"id": "fk_bone_walls", "display_name": "Bone Walls", "description": "Walls built from the bones of the dead.", "tier": 2, "category": "logistics", "prerequisites": ["death_whispers"], "effects": {"defense_bonus": 3}, "tree_angle": 345.0, "tree_branch": "necromancy"},
    {"id": "fk_rot_weapons", "display_name": "Rot Weapons", "description": "Weapons that spread disease.", "tier": 3, "category": "military", "prerequisites": ["blighted_earth", "withering_touch"], "effects": {"unit_attack_bonus": 3}, "tree_angle": 105.0, "tree_branch": "decay"},
    {"id": "fk_shadow_army", "display_name": "Shadow Army", "description": "An army of living shadows.", "tier": 3, "category": "military", "prerequisites": ["dread_presence", "night_ambush"], "effects": {"unit_attack_bonus": 2, "flanking_damage_bonus": 12}, "tree_angle": 225.0, "tree_branch": "shadow_war"},
    {"id": "fk_death_trade", "display_name": "Death Trade", "description": "The dead have their own economy.", "tier": 3, "category": "economy", "prerequisites": ["fk_bone_trade", "grave_tithe"], "effects": {"income_gold_pct": 10, "upkeep_reduction": 5}, "tree_angle": 345.0, "tree_branch": "necromancy"},
    {"id": "fk_plague_wind", "display_name": "Plague Wind", "description": "Winds carry disease to enemy cities.", "tier": 3, "category": "arcane", "prerequisites": ["rot_harvest", "blighted_earth"], "effects": {"siege_bonus": 10, "unit_attack_bonus": 2}, "tree_angle": 135.0, "tree_branch": "decay"},
    {"id": "fk_darkness_falls", "display_name": "Darkness Falls", "description": "Supernatural darkness blankets the land.", "tier": 4, "category": "arcane", "prerequisites": ["hollow_throne", "fk_shadow_army"], "effects": {"unit_attack_bonus": 3, "flanking_damage_bonus": 15}, "tree_angle": 230.0, "tree_branch": "shadow_war"},
    {"id": "fk_undead_lords", "display_name": "Undead Lords", "description": "Powerful undead command vast legions.", "tier": 4, "category": "arcane", "prerequisites": ["undying_legion", "fk_death_trade"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 3}, "tree_angle": 355.0, "tree_branch": "necromancy"},
]

IVORYSCAR_B2 = [
    {"id": "iv_desert_scouts", "display_name": "Desert Scouts", "description": "Scouts skilled in desert survival.", "tier": 2, "category": "logistics", "prerequisites": ["desert_whispers"], "effects": {"movement_bonus": 1, "vision_range_bonus": 1}, "tree_angle": 225.0, "tree_branch": "void_sight"},
    {"id": "iv_stone_masons", "display_name": "Stone Masons", "description": "Master builders of stone monuments.", "tier": 2, "category": "economy", "prerequisites": ["relic_weapons"], "effects": {"income_gold_pct": 5, "defense_bonus": 2}, "tree_angle": 105.0, "tree_branch": "relics"},
    {"id": "iv_sand_storms", "display_name": "Sand Storms", "description": "Conjure devastating sand storms.", "tier": 3, "category": "arcane", "prerequisites": ["void_lens", "mirage_tactics"], "effects": {"unit_attack_bonus": 2, "siege_bonus": 8}, "tree_angle": 250.0, "tree_branch": "void_sight"},
    {"id": "iv_relic_forge", "display_name": "Relic Forge", "description": "Forge new relics from ancient knowledge.", "tier": 3, "category": "economy", "prerequisites": ["tomb_raiding", "iv_stone_masons"], "effects": {"unit_attack_bonus": 2, "income_gold_pct": 8}, "tree_angle": 110.0, "tree_branch": "relics"},
    {"id": "iv_petrify_mastery", "display_name": "Petrification Mastery", "description": "Refine the art of turning foes to stone.", "tier": 3, "category": "arcane", "prerequisites": ["ivory_curse", "petrified_walls"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 10.0, "tree_branch": "petrification"},
    {"id": "iv_desert_trade", "display_name": "Desert Trade Routes", "description": "Profitable trade routes cross the desert.", "tier": 3, "category": "economy", "prerequisites": ["iv_oasis_control", "sand_warriors"], "effects": {"trade_income_bonus": 12, "income_gold_pct": 8}, "tree_angle": 75.0, "tree_branch": "desert_power"},
    {"id": "iv_tomb_wealth", "display_name": "Tomb Wealth", "description": "Ancient tombs yield incredible riches.", "tier": 3, "category": "economy", "prerequisites": ["iv_tomb_guardians", "iv_death_masks"], "effects": {"income_gold_pct": 10, "shard_harvest_bonus": 5}, "tree_angle": 185.0, "tree_branch": "tomb_lords"},
    {"id": "iv_void_walkers", "display_name": "Void Walkers", "description": "Warriors who step through the void.", "tier": 4, "category": "military", "prerequisites": ["all_seeing_eye", "iv_sand_storms"], "effects": {"unit_speed_bonus": 3, "flanking_damage_bonus": 15}, "tree_angle": 245.0, "tree_branch": "void_sight"},
    {"id": "iv_ancient_pharaoh", "display_name": "Ancient Pharaoh", "description": "An ancient pharaoh returns from the tomb.", "tier": 4, "category": "military", "prerequisites": ["iv_pharaoh_guard", "iv_tomb_wealth"], "effects": {"unit_attack_bonus": 3, "unit_morale_bonus": 12}, "tree_angle": 185.0, "tree_branch": "tomb_lords"},
]

SHARDHORDE_B2 = [
    {"id": "sh_crystal_scouts", "display_name": "Crystal Scouts", "description": "Small crystal creatures scout ahead.", "tier": 2, "category": "logistics", "prerequisites": ["shard_infusion"], "effects": {"vision_range_bonus": 1, "movement_bonus": 1}, "tree_angle": 30.0, "tree_branch": "crystal_evolution"},
    {"id": "sh_shard_growth", "display_name": "Shard Growth Acceleration", "description": "Crystals grow faster and stronger.", "tier": 2, "category": "economy", "prerequisites": ["shard_communion"], "effects": {"shard_harvest_bonus": 8}, "tree_angle": 225.0, "tree_branch": "shard_communion"},
    {"id": "sh_crystal_armor", "display_name": "Crystal Armor", "description": "Armor grown from living crystal.", "tier": 3, "category": "military", "prerequisites": ["crystal_carapace", "sh_crystal_scouts"], "effects": {"unit_defense_bonus": 3}, "tree_angle": 20.0, "tree_branch": "crystal_evolution"},
    {"id": "sh_swarm_frenzy", "display_name": "Swarm Frenzy", "description": "Crystal swarms attack in a frenzy.", "tier": 3, "category": "military", "prerequisites": ["feral_charge", "alpha_command"], "effects": {"unit_attack_bonus": 3, "unit_speed_bonus": 1}, "tree_angle": 130.0, "tree_branch": "swarm_tactics"},
    {"id": "sh_resonance_web", "display_name": "Resonance Web", "description": "A web of crystal resonance.", "tier": 3, "category": "arcane", "prerequisites": ["resonance_field", "shard_parasites"], "effects": {"unit_attack_bonus": 2, "shard_harvest_bonus": 8}, "tree_angle": 245.0, "tree_branch": "shard_communion"},
    {"id": "sh_beast_evolution", "display_name": "Beast Evolution", "description": "Crystal beasts evolve rapidly.", "tier": 3, "category": "military", "prerequisites": ["sh_beast_breeding", "sh_war_beasts"], "effects": {"unit_attack_bonus": 2, "unit_hp_bonus": 8}, "tree_angle": 65.0, "tree_branch": "beast_mastery"},
    {"id": "sh_crystal_economy", "display_name": "Crystal Economy", "description": "Trade in refined crystal goods.", "tier": 3, "category": "economy", "prerequisites": ["sh_shard_miners", "sh_hive_comms"], "effects": {"income_gold_pct": 10, "trade_income_bonus": 8}, "tree_angle": 185.0, "tree_branch": "hive_network"},
    {"id": "sh_elder_bond", "display_name": "Elder Bond", "description": "Deeper bond with the elderbeast.", "tier": 4, "category": "arcane", "prerequisites": ["elderbeast_evolution", "sh_crystal_armor"], "effects": {"unit_attack_bonus": 3, "unit_hp_bonus": 10}, "tree_angle": 10.0, "tree_branch": "crystal_evolution"},
    {"id": "sh_crystal_wealth", "display_name": "Crystal Wealth", "description": "Refined crystals command vast wealth.", "tier": 4, "category": "economy", "prerequisites": ["sh_crystal_fortress", "sh_crystal_economy"], "effects": {"income_gold_pct": 15, "shard_harvest_bonus": 12}, "tree_angle": 185.0, "tree_branch": "hive_network"},
]

SUNBLESSED_B2 = [
    {"id": "sb_sun_archers", "display_name": "Sun Archers", "description": "Archers who fire arrows of light.", "tier": 2, "category": "military", "prerequisites": ["sacred_flame"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 225.0, "tree_branch": "sacred_flame"},
    {"id": "sb_oasis_trade", "display_name": "Oasis Trade", "description": "Desert oases become trading posts.", "tier": 2, "category": "economy", "prerequisites": ["waystone_network"], "effects": {"trade_income_bonus": 8}, "tree_angle": 145.0, "tree_branch": "pilgrimage"},
    {"id": "sb_sun_forging", "display_name": "Sun Forging", "description": "Weapons forged in concentrated sunlight.", "tier": 3, "category": "military", "prerequisites": ["sb_sun_shields", "sb_dawn_cavalry"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 65.0, "tree_branch": "dawn_guard"},
    {"id": "sb_pilgrim_roads", "display_name": "Pilgrim Roads", "description": "Well-maintained roads for pilgrims.", "tier": 3, "category": "logistics", "prerequisites": ["pilgrim_zeal", "sb_oasis_trade"], "effects": {"movement_bonus": 2, "supply_range_bonus": 1}, "tree_angle": 130.0, "tree_branch": "pilgrimage"},
    {"id": "sb_fire_priests", "display_name": "Fire Priests", "description": "Priests who command sacred fire.", "tier": 3, "category": "arcane", "prerequisites": ["righteous_fury", "sun_warriors"], "effects": {"unit_attack_bonus": 3}, "tree_angle": 250.0, "tree_branch": "sacred_flame"},
    {"id": "sb_solar_temples", "display_name": "Solar Temples", "description": "Great temples to the Sun God.", "tier": 3, "category": "economy", "prerequisites": ["sb_sun_temples", "sb_trade_caravans"], "effects": {"income_gold_pct": 10, "research_speed_bonus": 8}, "tree_angle": 185.0, "tree_branch": "sun_harvest"},
    {"id": "sb_radiant_guard", "display_name": "Radiant Guard", "description": "Elite guard in sunlit armor.", "tier": 3, "category": "military", "prerequisites": ["radiant_aura", "dawn_meditation"], "effects": {"unit_defense_bonus": 3, "unit_morale_bonus": 8}, "tree_angle": 20.0, "tree_branch": "solar_faith"},
    {"id": "sb_desert_lords", "display_name": "Desert Lords", "description": "Mighty lords of the desert.", "tier": 4, "category": "military", "prerequisites": ["holy_caravan", "sb_pilgrim_roads"], "effects": {"unit_attack_bonus": 3, "movement_bonus": 1}, "tree_angle": 125.0, "tree_branch": "pilgrimage"},
    {"id": "sb_eternal_sun", "display_name": "Eternal Sunlight", "description": "The sun never sets on the Sunblessed.", "tier": 4, "category": "economy", "prerequisites": ["sb_golden_age", "sb_solar_temples"], "effects": {"income_gold_pct": 15, "income_food_pct": 12}, "tree_angle": 185.0, "tree_branch": "sun_harvest"},
]


def main():
    count = 0
    factions = {
        "empire": EMPIRE_B2,
        "gladehost": GLADEHOST_B2,
        "skulloath": SKULLOATH_B2,
        "moonspear": MOONSPEAR_B2,
        "thunderswarm": THUNDERSWARM_B2,
        "tainted_jade": TAINTED_JADE_B2,
        "cinderguard": CINDERGUARD_B2,
        "forsaken": FORSAKEN_B2,
        "ivoryscar": IVORYSCAR_B2,
        "shardhorde": SHARDHORDE_B2,
        "sunblessed": SUNBLESSED_B2,
    }
    for faction_id, items in factions.items():
        for item in items:
            item["faction_id"] = faction_id
            count += write_tres(faction_id, item)

    print(f"Generated {count} additional research .tres files.")
    for faction_id in factions:
        folder = os.path.join(BASE_DIR, faction_id)
        total = len([f for f in os.listdir(folder) if f.endswith(".tres")])
        print(f"  {faction_id}: {total} total items")

if __name__ == "__main__":
    main()
