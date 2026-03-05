#!/usr/bin/env python3
"""Generate expanded tech tree research .tres files for FractureWars.
Each faction expands from 15 to ~50 items across 5 tiers and 5-6 branches."""

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

# Tech cost and research time by tier
TIER_COSTS = {1: 50, 2: 90, 3: 130, 4: 180, 5: 250}
TIER_TIMES = {1: 8, 2: 12, 3: 16, 4: 20, 5: 26}

def fmt_prereqs(prereqs):
    if not prereqs:
        return ""
    return ", ".join(f'&"{p}"' for p in prereqs)

def fmt_effects(effects):
    if not effects:
        return ""
    parts = []
    for k, v in effects.items():
        if isinstance(v, int):
            parts.append(f'"{k}": {v}')
        elif isinstance(v, float):
            parts.append(f'"{k}": {v}')
        else:
            parts.append(f'"{k}": {v}')
    return ", ".join(parts)

def write_tres(faction_folder, data):
    folder = os.path.join(BASE_DIR, faction_folder)
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, f"{data['id']}.tres")
    if os.path.exists(filepath):
        return  # Don't overwrite existing
    content = TRES_TEMPLATE.format(
        id=data["id"],
        display_name=data["display_name"],
        description=data["description"],
        tech_cost=data.get("tech_cost", TIER_COSTS[data["tier"]]),
        research_time=data.get("research_time", TIER_TIMES[data["tier"]]),
        prerequisites=fmt_prereqs(data.get("prerequisites", [])),
        effects=fmt_effects(data.get("effects", {})),
        shard_bonuses=data.get("shard_bonuses", ""),
        tier=data["tier"],
        category=data.get("category", "military"),
        faction_id=data.get("faction_id", ""),
        tree_angle=data.get("tree_angle", 0.0),
        tree_branch=data.get("tree_branch", ""),
    )
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content.lstrip())


# ═══════════════════════════════════════════════════════════════
# COMMON / UNIVERSAL RESEARCH
# ═══════════════════════════════════════════════════════════════
COMMON = [
    # Existing: advanced_agriculture(T1), improved_metallurgy(T1), arcane_studies(T1),
    # fortification_mastery(T1), logistics_reform(T2), steel_tempering(T2),
    # divine_communion(T2), imperial_supremacy(T3)
    # New T2-T5 to expand from 8 to ~15
    {"id": "advanced_scouting", "display_name": "Advanced Scouting", "description": "Extended reconnaissance reveals hidden threats.", "tier": 2, "category": "logistics", "prerequisites": ["fortification_mastery"], "effects": {"vision_range_bonus": 1}},
    {"id": "trade_standardization", "display_name": "Trade Standardization", "description": "Unified weights and measures boost commerce.", "tier": 2, "category": "economy", "prerequisites": ["advanced_agriculture"], "effects": {"trade_income_bonus": 10}},
    {"id": "arcane_fortification", "display_name": "Arcane Fortification", "description": "Magic-infused walls withstand any siege.", "tier": 3, "category": "arcane", "prerequisites": ["divine_communion", "fortification_mastery"], "effects": {"defense_bonus": 3}},
    {"id": "siege_engineering", "display_name": "Siege Engineering", "description": "Advanced siege techniques break the strongest walls.", "tier": 3, "category": "logistics", "prerequisites": ["steel_tempering"], "effects": {"siege_bonus": 15}},
    {"id": "grand_logistics", "display_name": "Grand Logistics", "description": "A continent-spanning supply network feeds your armies.", "tier": 4, "category": "logistics", "prerequisites": ["logistics_reform", "advanced_scouting"], "effects": {"supply_range_bonus": 2, "movement_bonus": 1}},
    {"id": "arcane_mastery", "display_name": "Arcane Mastery", "description": "The deepest secrets of magic are unlocked.", "tier": 4, "category": "arcane", "prerequisites": ["arcane_fortification"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}},
    {"id": "world_domination", "display_name": "World Domination", "description": "Total supremacy in every sphere of war and governance.", "tier": 5, "category": "military", "prerequisites": ["imperial_supremacy", "grand_logistics"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}},
]

# ═══════════════════════════════════════════════════════════════
# EMPIRE RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing branches: warfare(0°), commerce(90°), engineering(180°), governance(270°)
# New branches: arcane(60°), supremacy(300°)
EMPIRE = [
    # ── Warfare branch (0°) ── T4-T5 additions
    {"id": "emp_veteran_legions", "display_name": "Veteran Legions", "description": "Seasoned soldiers fight harder and longer.", "tier": 4, "category": "military", "prerequisites": ["imperial_supremacy_faction", "legion_standards"], "effects": {"unit_attack_bonus": 3, "unit_morale_bonus": 10}, "tree_angle": 350.0, "tree_branch": "warfare"},
    {"id": "emp_shield_wall", "display_name": "Shield Wall Mastery", "description": "Impenetrable shield formations deflect all attacks.", "tier": 4, "category": "military", "prerequisites": ["imperial_supremacy_faction"], "effects": {"unit_defense_bonus": 5}, "tree_angle": 10.0, "tree_branch": "warfare"},
    {"id": "emp_invincible_legion", "display_name": "Invincible Legion", "description": "The Empire's legions become an unstoppable force.", "tier": 5, "category": "military", "prerequisites": ["emp_veteran_legions", "emp_shield_wall"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 5, "unit_morale_bonus": 15}, "tree_angle": 0.0, "tree_branch": "warfare"},
    # ── Arcane branch (60°) ── NEW, T1-T5
    {"id": "emp_arcane_academy", "display_name": "Arcane Academy", "description": "Mages train alongside legionaries.", "tier": 1, "category": "arcane", "prerequisites": [], "effects": {"research_speed_bonus": 10}, "tree_angle": 60.0, "tree_branch": "arcane"},
    {"id": "emp_battle_mages", "display_name": "Battle Mages", "description": "Warmages join the front lines.", "tier": 2, "category": "arcane", "prerequisites": ["emp_arcane_academy"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "arcane"},
    {"id": "emp_enchanted_arms", "display_name": "Enchanted Arms", "description": "Magic-infused weapons cut through armor.", "tier": 2, "category": "arcane", "prerequisites": ["emp_arcane_academy"], "effects": {"unit_attack_bonus": 1, "siege_bonus": 5}, "tree_angle": 70.0, "tree_branch": "arcane"},
    {"id": "emp_arcane_artillery", "display_name": "Arcane Artillery", "description": "Devastating magical siege weapons.", "tier": 3, "category": "arcane", "prerequisites": ["emp_battle_mages", "emp_enchanted_arms"], "effects": {"siege_bonus": 15, "unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "arcane"},
    {"id": "emp_ward_masters", "display_name": "Ward Masters", "description": "Protective magical barriers shield armies.", "tier": 3, "category": "arcane", "prerequisites": ["emp_battle_mages"], "effects": {"unit_defense_bonus": 3}, "tree_angle": 70.0, "tree_branch": "arcane"},
    {"id": "emp_arcane_dominion", "display_name": "Arcane Dominion", "description": "Imperial magic overwhelms all opposition.", "tier": 4, "category": "arcane", "prerequisites": ["emp_arcane_artillery", "emp_ward_masters"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 3}, "tree_angle": 60.0, "tree_branch": "arcane"},
    {"id": "emp_imperial_arcanum", "display_name": "Imperial Arcanum", "description": "The pinnacle of Imperial magical achievement.", "tier": 5, "category": "arcane", "prerequisites": ["emp_arcane_dominion", "emp_invincible_legion"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4, "research_speed_bonus": 15}, "tree_angle": 60.0, "tree_branch": "arcane"},
    # ── Commerce branch (90°) ── T4-T5 additions
    {"id": "emp_banking_houses", "display_name": "Banking Houses", "description": "Imperial banks finance expansion.", "tier": 4, "category": "economy", "prerequisites": ["imperial_treasury", "road_network"], "effects": {"trade_income_bonus": 20, "income_gold_pct": 15}, "tree_angle": 85.0, "tree_branch": "commerce"},
    {"id": "emp_merchant_fleet", "display_name": "Merchant Fleet", "description": "Naval trade dominance.", "tier": 4, "category": "economy", "prerequisites": ["imperial_treasury"], "effects": {"trade_income_bonus": 25}, "tree_angle": 100.0, "tree_branch": "commerce"},
    {"id": "emp_economic_hegemony", "display_name": "Economic Hegemony", "description": "The Empire controls all trade.", "tier": 5, "category": "economy", "prerequisites": ["emp_banking_houses", "emp_merchant_fleet"], "effects": {"income_gold_pct": 25, "trade_income_bonus": 30}, "tree_angle": 90.0, "tree_branch": "commerce"},
    # ── Engineering branch (180°) ── T4-T5 additions
    {"id": "emp_aqueducts", "display_name": "Imperial Aqueducts", "description": "Water networks boost city growth.", "tier": 3, "category": "logistics", "prerequisites": ["logistics_reform_emp"], "effects": {"income_food_pct": 10}, "tree_angle": 170.0, "tree_branch": "engineering"},
    {"id": "emp_fortress_design", "display_name": "Fortress Design", "description": "Impregnable fortress architecture.", "tier": 4, "category": "logistics", "prerequisites": ["siege_mastery", "emp_aqueducts"], "effects": {"defense_bonus": 8, "siege_bonus": 10}, "tree_angle": 175.0, "tree_branch": "engineering"},
    {"id": "emp_war_machines", "display_name": "War Machines", "description": "Devastating siege engines of Imperial design.", "tier": 4, "category": "logistics", "prerequisites": ["siege_mastery"], "effects": {"siege_bonus": 20}, "tree_angle": 190.0, "tree_branch": "engineering"},
    {"id": "emp_engineering_marvel", "display_name": "Engineering Marvel", "description": "The Empire's engineering is beyond compare.", "tier": 5, "category": "logistics", "prerequisites": ["emp_fortress_design", "emp_war_machines"], "effects": {"defense_bonus": 10, "siege_bonus": 25, "movement_bonus": 2}, "tree_angle": 180.0, "tree_branch": "engineering"},
    # ── Governance branch (270°) ── T4-T5 additions
    {"id": "emp_provincial_governors", "display_name": "Provincial Governors", "description": "Efficient governance stabilizes conquered lands.", "tier": 3, "category": "economy", "prerequisites": ["senate_authority", "imperial_edict"], "effects": {"income_gold_pct": 10, "upkeep_reduction": 5}, "tree_angle": 280.0, "tree_branch": "governance"},
    {"id": "emp_imperial_law", "display_name": "Imperial Law", "description": "Codified laws bring order to the realm.", "tier": 4, "category": "economy", "prerequisites": ["pax_imperialis", "emp_provincial_governors"], "effects": {"income_gold_pct": 15, "unit_morale_bonus": 10}, "tree_angle": 265.0, "tree_branch": "governance"},
    {"id": "emp_divine_mandate", "display_name": "Divine Right of Empire", "description": "The Emperor rules by divine decree.", "tier": 4, "category": "economy", "prerequisites": ["pax_imperialis"], "effects": {"unit_morale_bonus": 15, "upkeep_reduction": 10}, "tree_angle": 280.0, "tree_branch": "governance"},
    {"id": "emp_eternal_empire", "display_name": "Eternal Empire", "description": "The Empire shall endure forever.", "tier": 5, "category": "economy", "prerequisites": ["emp_imperial_law", "emp_divine_mandate"], "effects": {"income_gold_pct": 20, "unit_morale_bonus": 20, "upkeep_reduction": 15}, "tree_angle": 270.0, "tree_branch": "governance"},
    # ── Supremacy branch (300°) ── NEW capstone T3-T5
    {"id": "emp_military_reforms", "display_name": "Military Reforms", "description": "Sweeping reforms modernize the army.", "tier": 3, "category": "military", "prerequisites": ["centurion_tactics", "senate_authority"], "effects": {"unit_attack_bonus": 2, "unit_speed_bonus": 1}, "tree_angle": 310.0, "tree_branch": "supremacy"},
    {"id": "emp_combined_arms", "display_name": "Combined Arms", "description": "Infantry, cavalry, and mages fight as one.", "tier": 4, "category": "military", "prerequisites": ["emp_military_reforms", "emp_arcane_dominion"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 305.0, "tree_branch": "supremacy"},
    {"id": "emp_total_war", "display_name": "Total War", "description": "The Empire marshals all resources for conquest.", "tier": 4, "category": "military", "prerequisites": ["emp_military_reforms", "emp_fortress_design"], "effects": {"unit_attack_bonus": 3, "recruitment_cost_reduction": 15}, "tree_angle": 320.0, "tree_branch": "supremacy"},
    {"id": "emp_pax_aeterna", "display_name": "Pax Aeterna", "description": "Absolute dominion brings eternal peace—through strength.", "tier": 5, "category": "military", "prerequisites": ["emp_combined_arms", "emp_total_war"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 6, "unit_morale_bonus": 20}, "tree_angle": 310.0, "tree_branch": "supremacy"},
]

# ═══════════════════════════════════════════════════════════════
# GLADEHOST RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: nature_bond(0°), wardenship(90°), spirit_lore(180°), herbalism(270°)
# New: beast_affinity(60°), world_tree(300°)
GLADEHOST = [
    # nature_bond T4-T5
    {"id": "gh_ancient_roots", "display_name": "Ancient Roots", "description": "Roots of the eldest trees provide strength.", "tier": 4, "category": "arcane", "prerequisites": ["heart_of_the_forest"], "effects": {"unit_defense_bonus": 4, "unit_hp_bonus": 10}, "tree_angle": 350.0, "tree_branch": "nature_bond"},
    {"id": "gh_world_seed", "display_name": "World Seed", "description": "The seed of a new world tree awakens.", "tier": 5, "category": "arcane", "prerequisites": ["gh_ancient_roots", "gh_primal_communion"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 5, "income_food_pct": 20}, "tree_angle": 0.0, "tree_branch": "nature_bond"},
    # wardenship T4-T5
    {"id": "gh_ambush_mastery", "display_name": "Ambush Mastery", "description": "Forest defenders strike from every shadow.", "tier": 4, "category": "military", "prerequisites": ["entangling_roots", "thornguard"], "effects": {"unit_attack_bonus": 4, "flanking_damage_bonus": 15}, "tree_angle": 85.0, "tree_branch": "wardenship"},
    {"id": "gh_living_fortress", "display_name": "Living Fortress", "description": "Trees themselves form impenetrable walls.", "tier": 4, "category": "military", "prerequisites": ["entangling_roots"], "effects": {"defense_bonus": 8}, "tree_angle": 100.0, "tree_branch": "wardenship"},
    {"id": "gh_forest_sovereign", "display_name": "Forest Sovereign", "description": "The forest itself fights for the Gladehost.", "tier": 5, "category": "military", "prerequisites": ["gh_ambush_mastery", "gh_living_fortress"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 5, "defense_bonus": 10}, "tree_angle": 90.0, "tree_branch": "wardenship"},
    # spirit_lore T4-T5
    {"id": "gh_spirit_army", "display_name": "Spirit Army", "description": "Ethereal warriors join the fight.", "tier": 4, "category": "arcane", "prerequisites": ["avatar_of_the_wild"], "effects": {"unit_attack_bonus": 3, "unit_morale_bonus": 15}, "tree_angle": 175.0, "tree_branch": "spirit_lore"},
    {"id": "gh_primal_communion", "display_name": "Primal Communion", "description": "Direct communion with primordial nature spirits.", "tier": 4, "category": "arcane", "prerequisites": ["avatar_of_the_wild", "gh_ancient_roots"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3, "research_speed_bonus": 10}, "tree_angle": 190.0, "tree_branch": "spirit_lore"},
    {"id": "gh_spirit_ascension", "display_name": "Spirit Ascension", "description": "The boundary between material and spirit dissolves.", "tier": 5, "category": "arcane", "prerequisites": ["gh_spirit_army", "gh_primal_communion"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 4, "unit_morale_bonus": 20}, "tree_angle": 180.0, "tree_branch": "spirit_lore"},
    # herbalism T4-T5
    {"id": "gh_lifeblooms", "display_name": "Lifeblooms", "description": "Magical flowers heal all nearby.", "tier": 4, "category": "economy", "prerequisites": ["grove_sanctuary"], "effects": {"unit_hp_bonus": 15, "income_food_pct": 15}, "tree_angle": 265.0, "tree_branch": "herbalism"},
    {"id": "gh_garden_eternal", "display_name": "Garden Eternal", "description": "An eternal garden sustains all life.", "tier": 5, "category": "economy", "prerequisites": ["gh_lifeblooms", "gh_world_seed"], "effects": {"income_food_pct": 25, "unit_hp_bonus": 20}, "tree_angle": 270.0, "tree_branch": "herbalism"},
    # beast_affinity (60°) NEW
    {"id": "gh_beast_tongue", "display_name": "Beast Tongue", "description": "Communicate with forest creatures.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_speed_bonus": 1}, "tree_angle": 60.0, "tree_branch": "beast_affinity"},
    {"id": "gh_dire_companions", "display_name": "Dire Companions", "description": "Great forest beasts fight alongside warriors.", "tier": 2, "category": "military", "prerequisites": ["gh_beast_tongue"], "effects": {"unit_attack_bonus": 2, "unit_speed_bonus": 1}, "tree_angle": 55.0, "tree_branch": "beast_affinity"},
    {"id": "gh_hawk_scouts", "display_name": "Hawk Scouts", "description": "Trained hawks provide aerial reconnaissance.", "tier": 2, "category": "logistics", "prerequisites": ["gh_beast_tongue"], "effects": {"vision_range_bonus": 1, "movement_bonus": 1}, "tree_angle": 70.0, "tree_branch": "beast_affinity"},
    {"id": "gh_treant_allies", "display_name": "Treant Allies", "description": "Ancient tree guardians join the warhost.", "tier": 3, "category": "military", "prerequisites": ["gh_dire_companions"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 55.0, "tree_branch": "beast_affinity"},
    {"id": "gh_beast_horde", "display_name": "Beast Horde", "description": "A tide of forest creatures overwhelms foes.", "tier": 4, "category": "military", "prerequisites": ["gh_treant_allies", "gh_hawk_scouts"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 2}, "tree_angle": 60.0, "tree_branch": "beast_affinity"},
    # world_tree (300°) capstone
    {"id": "gh_sacred_grove", "display_name": "Sacred Grove", "description": "A holy grove empowers all nearby.", "tier": 3, "category": "arcane", "prerequisites": ["spirit_pact", "seed_scattering"], "effects": {"unit_morale_bonus": 10, "income_food_pct": 10}, "tree_angle": 305.0, "tree_branch": "world_tree"},
    {"id": "gh_world_tree_roots", "display_name": "World Tree Roots", "description": "The World Tree's roots span the continent.", "tier": 4, "category": "arcane", "prerequisites": ["gh_sacred_grove", "gh_beast_horde"], "effects": {"movement_bonus": 2, "supply_range_bonus": 2}, "tree_angle": 300.0, "tree_branch": "world_tree"},
    {"id": "gh_avatar_verdant", "display_name": "Avatar of Verdance", "description": "The World Tree manifests its will through the Gladehost.", "tier": 5, "category": "arcane", "prerequisites": ["gh_world_tree_roots", "gh_forest_sovereign"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 6, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "world_tree"},
]

# ═══════════════════════════════════════════════════════════════
# SKULLOATH RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: raiding(0°), steppe_craft(90°), ancestor_rites(180°), horde_unity(270°)
# New: warg_mastery(60°), skull_throne(300°)
SKULLOATH = [
    # raiding T4-T5
    {"id": "sk_lightning_raids", "display_name": "Lightning Raids", "description": "Strike fast, loot everything, vanish.", "tier": 4, "category": "military", "prerequisites": ["skull_banner"], "effects": {"unit_speed_bonus": 3, "unit_attack_bonus": 3}, "tree_angle": 350.0, "tree_branch": "raiding"},
    {"id": "sk_dread_riders", "display_name": "Dread Riders", "description": "The most feared cavalry in the known world.", "tier": 5, "category": "military", "prerequisites": ["sk_lightning_raids", "sk_warg_lords"], "effects": {"unit_attack_bonus": 6, "unit_speed_bonus": 4, "unit_morale_bonus": 15}, "tree_angle": 0.0, "tree_branch": "raiding"},
    # steppe_craft T4-T5
    {"id": "sk_vast_herds", "display_name": "Vast Herds", "description": "Enormous herds sustain the horde.", "tier": 4, "category": "economy", "prerequisites": ["great_yurt", "caravan_routes"], "effects": {"income_food_pct": 20, "upkeep_reduction": 10}, "tree_angle": 85.0, "tree_branch": "steppe_craft"},
    {"id": "sk_steppe_empire", "display_name": "Steppe Empire", "description": "From horizon to horizon, the steppe obeys.", "tier": 5, "category": "economy", "prerequisites": ["sk_vast_herds"], "effects": {"income_gold_pct": 20, "income_food_pct": 25, "trade_income_bonus": 20}, "tree_angle": 90.0, "tree_branch": "steppe_craft"},
    # ancestor_rites T4-T5
    {"id": "sk_spirit_riders", "display_name": "Spirit Riders", "description": "Ghostly ancestors ride alongside the living.", "tier": 4, "category": "arcane", "prerequisites": ["pale_ascension"], "effects": {"unit_attack_bonus": 3, "unit_morale_bonus": 15}, "tree_angle": 175.0, "tree_branch": "ancestor_rites"},
    {"id": "sk_eternal_hunt", "display_name": "Eternal Hunt", "description": "The ancestors demand endless conquest.", "tier": 5, "category": "arcane", "prerequisites": ["sk_spirit_riders", "sk_dread_riders"], "effects": {"unit_attack_bonus": 5, "unit_speed_bonus": 3, "unit_morale_bonus": 20}, "tree_angle": 180.0, "tree_branch": "ancestor_rites"},
    # horde_unity T4-T5
    {"id": "sk_great_muster", "display_name": "Great Muster", "description": "All clans answer the Khan's call.", "tier": 4, "category": "military", "prerequisites": ["endless_horde"], "effects": {"recruitment_cost_reduction": 15, "unit_morale_bonus": 10}, "tree_angle": 265.0, "tree_branch": "horde_unity"},
    {"id": "sk_unstoppable_tide", "display_name": "Unstoppable Tide", "description": "A horde without end sweeps all before it.", "tier": 5, "category": "military", "prerequisites": ["sk_great_muster", "sk_steppe_empire"], "effects": {"unit_attack_bonus": 5, "unit_speed_bonus": 3, "recruitment_cost_reduction": 20}, "tree_angle": 270.0, "tree_branch": "horde_unity"},
    # warg_mastery (60°) NEW
    {"id": "sk_warg_pens", "display_name": "Warg Pens", "description": "Breeding pens produce fiercer wargs.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_speed_bonus": 1}, "tree_angle": 60.0, "tree_branch": "warg_mastery"},
    {"id": "sk_pack_tactics", "display_name": "Pack Tactics", "description": "Wargs hunt in coordinated packs.", "tier": 2, "category": "military", "prerequisites": ["sk_warg_pens"], "effects": {"unit_attack_bonus": 2, "flanking_damage_bonus": 10}, "tree_angle": 55.0, "tree_branch": "warg_mastery"},
    {"id": "sk_dire_wargs", "display_name": "Dire Wargs", "description": "Enormous dire wargs carry armored riders.", "tier": 2, "category": "military", "prerequisites": ["sk_warg_pens"], "effects": {"unit_attack_bonus": 1, "unit_hp_bonus": 5}, "tree_angle": 70.0, "tree_branch": "warg_mastery"},
    {"id": "sk_warg_riders", "display_name": "Warg Rider Elite", "description": "Elite warg cavalry terrorize the battlefield.", "tier": 3, "category": "military", "prerequisites": ["sk_pack_tactics", "sk_dire_wargs"], "effects": {"unit_attack_bonus": 3, "unit_speed_bonus": 2}, "tree_angle": 60.0, "tree_branch": "warg_mastery"},
    {"id": "sk_warg_lords", "display_name": "Warg Lords", "description": "Supreme warg riders command the pack.", "tier": 4, "category": "military", "prerequisites": ["sk_warg_riders"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 3}, "tree_angle": 60.0, "tree_branch": "warg_mastery"},
    # skull_throne (300°) capstone
    {"id": "sk_blood_oath", "display_name": "Blood Oath", "description": "Warriors sworn to fight to the death.", "tier": 3, "category": "military", "prerequisites": ["terror_tactics", "ancestor_call"], "effects": {"unit_attack_bonus": 2, "unit_morale_bonus": 10}, "tree_angle": 310.0, "tree_branch": "skull_throne"},
    {"id": "sk_khan_fury", "display_name": "Khan's Fury", "description": "The Khan's rage empowers all warriors.", "tier": 4, "category": "military", "prerequisites": ["sk_blood_oath", "sk_spirit_riders"], "effects": {"unit_attack_bonus": 4, "unit_morale_bonus": 15}, "tree_angle": 305.0, "tree_branch": "skull_throne"},
    {"id": "sk_world_conqueror", "display_name": "World Conqueror", "description": "All peoples shall kneel before the Skulloath.", "tier": 5, "category": "military", "prerequisites": ["sk_khan_fury", "sk_unstoppable_tide"], "effects": {"unit_attack_bonus": 7, "unit_speed_bonus": 4, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "skull_throne"},
]

# ═══════════════════════════════════════════════════════════════
# MOONSPEAR RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: lunar_doctrine(0°), silver_arms(120°), enlightenment(240°)
# New: celestial_magic(60°), holy_order(180°), convergence(300°)
MOONSPEAR = [
    # lunar_doctrine T4-T5
    {"id": "ms_eclipse_rites", "display_name": "Eclipse Rites", "description": "Power drawn from sacred eclipses.", "tier": 4, "category": "arcane", "prerequisites": ["divine_mandate", "moon_oracle"], "effects": {"unit_attack_bonus": 4, "unit_morale_bonus": 15}, "tree_angle": 350.0, "tree_branch": "lunar_doctrine"},
    {"id": "ms_lunar_apotheosis", "display_name": "Lunar Apotheosis", "description": "The Moon Goddess grants her full blessing.", "tier": 5, "category": "arcane", "prerequisites": ["ms_eclipse_rites"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 5, "unit_morale_bonus": 20}, "tree_angle": 0.0, "tree_branch": "lunar_doctrine"},
    # silver_arms T4-T5
    {"id": "ms_silver_knights", "display_name": "Silver Knights", "description": "Holy knights in silver armor.", "tier": 4, "category": "military", "prerequisites": ["moonspear_elite", "lunar_convergence"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 115.0, "tree_branch": "silver_arms"},
    {"id": "ms_celestial_host", "display_name": "Celestial Host", "description": "An army blessed by the heavens.", "tier": 5, "category": "military", "prerequisites": ["ms_silver_knights", "ms_lunar_apotheosis"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 6}, "tree_angle": 120.0, "tree_branch": "silver_arms"},
    # enlightenment T4-T5
    {"id": "ms_sacred_archives", "display_name": "Sacred Archives", "description": "Ancient wisdom accelerates all research.", "tier": 4, "category": "economy", "prerequisites": ["divine_radiance", "tithe_of_light"], "effects": {"research_speed_bonus": 20, "income_gold_pct": 10}, "tree_angle": 235.0, "tree_branch": "enlightenment"},
    {"id": "ms_eternal_light", "display_name": "Eternal Light", "description": "The light of knowledge illuminates all.", "tier": 5, "category": "economy", "prerequisites": ["ms_sacred_archives"], "effects": {"research_speed_bonus": 25, "income_gold_pct": 20}, "tree_angle": 240.0, "tree_branch": "enlightenment"},
    # celestial_magic (60°) NEW
    {"id": "ms_stargazing", "display_name": "Stargazing", "description": "Reading the stars reveals hidden truths.", "tier": 1, "category": "arcane", "prerequisites": [], "effects": {"research_speed_bonus": 5}, "tree_angle": 60.0, "tree_branch": "celestial_magic"},
    {"id": "ms_star_bolts", "display_name": "Star Bolts", "description": "Celestial energy forms deadly projectiles.", "tier": 2, "category": "arcane", "prerequisites": ["ms_stargazing"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "celestial_magic"},
    {"id": "ms_constellation_ward", "display_name": "Constellation Ward", "description": "Star patterns create protective barriers.", "tier": 2, "category": "arcane", "prerequisites": ["ms_stargazing"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 70.0, "tree_branch": "celestial_magic"},
    {"id": "ms_astral_storm", "display_name": "Astral Storm", "description": "A storm of celestial energy devastates foes.", "tier": 3, "category": "arcane", "prerequisites": ["ms_star_bolts"], "effects": {"unit_attack_bonus": 3, "siege_bonus": 10}, "tree_angle": 55.0, "tree_branch": "celestial_magic"},
    {"id": "ms_celestial_shield", "display_name": "Celestial Shield", "description": "An impenetrable shield of starlight.", "tier": 4, "category": "arcane", "prerequisites": ["ms_astral_storm", "ms_constellation_ward"], "effects": {"unit_defense_bonus": 4, "unit_attack_bonus": 3}, "tree_angle": 60.0, "tree_branch": "celestial_magic"},
    # holy_order (180°) NEW
    {"id": "ms_temple_tithes", "display_name": "Temple Tithes", "description": "The faithful donate generously.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_gold_pct": 5}, "tree_angle": 180.0, "tree_branch": "holy_order"},
    {"id": "ms_holy_warriors", "display_name": "Holy Warriors", "description": "Zealous warriors fight with divine purpose.", "tier": 2, "category": "military", "prerequisites": ["ms_temple_tithes"], "effects": {"unit_morale_bonus": 8}, "tree_angle": 175.0, "tree_branch": "holy_order"},
    {"id": "ms_crusade", "display_name": "Holy Crusade", "description": "A righteous war to purify the land.", "tier": 3, "category": "military", "prerequisites": ["ms_holy_warriors"], "effects": {"unit_attack_bonus": 3, "unit_morale_bonus": 10}, "tree_angle": 180.0, "tree_branch": "holy_order"},
    {"id": "ms_divine_army", "display_name": "Divine Army", "description": "An army empowered by the goddess.", "tier": 4, "category": "military", "prerequisites": ["ms_crusade", "ms_celestial_shield"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3, "unit_morale_bonus": 15}, "tree_angle": 180.0, "tree_branch": "holy_order"},
    # convergence (300°) capstone
    {"id": "ms_moon_covenant", "display_name": "Moon Covenant", "description": "A sacred pact with the Moon Goddess.", "tier": 3, "category": "arcane", "prerequisites": ["celestial_insight", "pilgrim_network"], "effects": {"unit_morale_bonus": 10, "research_speed_bonus": 10}, "tree_angle": 305.0, "tree_branch": "convergence"},
    {"id": "ms_silver_dawn", "display_name": "Silver Dawn", "description": "The silver dawn heralds a new age.", "tier": 4, "category": "arcane", "prerequisites": ["ms_moon_covenant", "ms_divine_army"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}, "tree_angle": 300.0, "tree_branch": "convergence"},
    {"id": "ms_avatar_moon", "display_name": "Avatar of the Moon", "description": "The Moon Goddess incarnates through the Moonspear.", "tier": 5, "category": "arcane", "prerequisites": ["ms_silver_dawn", "ms_celestial_host"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 6, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "convergence"},
]

# ═══════════════════════════════════════════════════════════════
# THUNDERSWARM RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: storm_mastery(0°), mountain_hold(120°), war_fury(240°)
# New: sky_lords(60°), iron_peak(180°), wrath(300°)
THUNDERSWARM = [
    # storm_mastery T4-T5
    {"id": "ts_chain_lightning", "display_name": "Chain Lightning", "description": "Lightning arcs between multiple targets.", "tier": 4, "category": "arcane", "prerequisites": ["eye_of_the_storm"], "effects": {"unit_attack_bonus": 4, "siege_bonus": 10}, "tree_angle": 350.0, "tree_branch": "storm_mastery"},
    {"id": "ts_storm_god", "display_name": "Storm God's Wrath", "description": "Channel the full fury of the Storm God.", "tier": 5, "category": "arcane", "prerequisites": ["ts_chain_lightning", "ts_sky_fortress"], "effects": {"unit_attack_bonus": 6, "siege_bonus": 20}, "tree_angle": 0.0, "tree_branch": "storm_mastery"},
    # mountain_hold T4-T5
    {"id": "ts_deep_mines", "display_name": "Deep Mines", "description": "Delve deeper for richer ore.", "tier": 4, "category": "economy", "prerequisites": ["storm_forge", "dragon_roost"], "effects": {"income_gold_pct": 15, "shard_harvest_bonus": 10}, "tree_angle": 115.0, "tree_branch": "mountain_hold"},
    {"id": "ts_mountain_king", "display_name": "Mountain King", "description": "Absolute ruler of the peaks.", "tier": 5, "category": "economy", "prerequisites": ["ts_deep_mines"], "effects": {"income_gold_pct": 20, "defense_bonus": 10}, "tree_angle": 120.0, "tree_branch": "mountain_hold"},
    # war_fury T4-T5
    {"id": "ts_blood_frenzy", "display_name": "Blood Frenzy", "description": "Warriors enter an unstoppable frenzy.", "tier": 4, "category": "military", "prerequisites": ["stormborn", "warcry"], "effects": {"unit_attack_bonus": 5, "unit_speed_bonus": 2}, "tree_angle": 235.0, "tree_branch": "war_fury"},
    {"id": "ts_ragnarok", "display_name": "Ragnarok", "description": "The final battle — all or nothing.", "tier": 5, "category": "military", "prerequisites": ["ts_blood_frenzy", "ts_storm_god"], "effects": {"unit_attack_bonus": 7, "unit_speed_bonus": 3, "unit_morale_bonus": 20}, "tree_angle": 240.0, "tree_branch": "war_fury"},
    # sky_lords (60°) NEW
    {"id": "ts_eagle_riders", "display_name": "Eagle Riders", "description": "Soar above the battlefield on giant eagles.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_speed_bonus": 1, "movement_bonus": 1}, "tree_angle": 60.0, "tree_branch": "sky_lords"},
    {"id": "ts_aerial_assault", "display_name": "Aerial Assault", "description": "Dive-bombing attacks from the sky.", "tier": 2, "category": "military", "prerequisites": ["ts_eagle_riders"], "effects": {"unit_attack_bonus": 2, "flanking_damage_bonus": 10}, "tree_angle": 55.0, "tree_branch": "sky_lords"},
    {"id": "ts_storm_hawks", "display_name": "Storm Hawks", "description": "Lightning-infused raptors scout ahead.", "tier": 2, "category": "logistics", "prerequisites": ["ts_eagle_riders"], "effects": {"vision_range_bonus": 1, "unit_speed_bonus": 1}, "tree_angle": 70.0, "tree_branch": "sky_lords"},
    {"id": "ts_thunderbird", "display_name": "Thunderbird", "description": "The legendary thunderbird joins the swarm.", "tier": 3, "category": "military", "prerequisites": ["ts_aerial_assault"], "effects": {"unit_attack_bonus": 3, "siege_bonus": 10}, "tree_angle": 55.0, "tree_branch": "sky_lords"},
    {"id": "ts_sky_fortress", "display_name": "Sky Fortress", "description": "A floating fortress of storm clouds.", "tier": 4, "category": "military", "prerequisites": ["ts_thunderbird", "ts_storm_hawks"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3, "movement_bonus": 2}, "tree_angle": 60.0, "tree_branch": "sky_lords"},
    # iron_peak (180°) NEW
    {"id": "ts_runic_forging", "display_name": "Runic Forging", "description": "Ancient runes empower forged weapons.", "tier": 1, "category": "arcane", "prerequisites": [], "effects": {"unit_attack_bonus": 1}, "tree_angle": 180.0, "tree_branch": "iron_peak"},
    {"id": "ts_thunder_weapons", "display_name": "Thunder Weapons", "description": "Lightning-charged weapons strike with fury.", "tier": 2, "category": "arcane", "prerequisites": ["ts_runic_forging"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 175.0, "tree_branch": "iron_peak"},
    {"id": "ts_rune_armor", "display_name": "Rune Armor", "description": "Rune-inscribed armor deflects blows.", "tier": 2, "category": "arcane", "prerequisites": ["ts_runic_forging"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 190.0, "tree_branch": "iron_peak"},
    {"id": "ts_master_runes", "display_name": "Master Runes", "description": "The most powerful runes known.", "tier": 3, "category": "arcane", "prerequisites": ["ts_thunder_weapons", "ts_rune_armor"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 180.0, "tree_branch": "iron_peak"},
    {"id": "ts_runic_mastery", "display_name": "Runic Mastery", "description": "Absolute mastery of runic magic.", "tier": 4, "category": "arcane", "prerequisites": ["ts_master_runes"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 180.0, "tree_branch": "iron_peak"},
    # wrath (300°) capstone
    {"id": "ts_war_drums", "display_name": "War Drums of Thunder", "description": "Drums that shake the earth.", "tier": 3, "category": "military", "prerequisites": ["warband_unity", "avalanche_tactics"], "effects": {"unit_morale_bonus": 10, "unit_attack_bonus": 2}, "tree_angle": 310.0, "tree_branch": "wrath"},
    {"id": "ts_berserker_lords", "display_name": "Berserker Lords", "description": "Unstoppable champions of rage.", "tier": 4, "category": "military", "prerequisites": ["ts_war_drums", "ts_runic_mastery"], "effects": {"unit_attack_bonus": 5, "unit_speed_bonus": 2}, "tree_angle": 305.0, "tree_branch": "wrath"},
    {"id": "ts_thunder_god_avatar", "display_name": "Thunder God Incarnate", "description": "The Thunder God himself walks among mortals.", "tier": 5, "category": "military", "prerequisites": ["ts_berserker_lords", "ts_ragnarok"], "effects": {"unit_attack_bonus": 8, "unit_speed_bonus": 4, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "wrath"},
]

# ═══════════════════════════════════════════════════════════════
# TAINTED JADE RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: serpent_lore(0°), dark_botany(120°), blood_rites(240°)
# New: venom_mastery(60°), fungal_network(180°), jade_throne(300°)
TAINTED_JADE = [
    # serpent_lore T4-T5
    {"id": "tj_serpent_kings", "display_name": "Serpent Kings", "description": "Great serpents serve as war beasts.", "tier": 4, "category": "military", "prerequisites": ["serpent_god_favor", "emerald_canopy"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 2}, "tree_angle": 350.0, "tree_branch": "serpent_lore"},
    {"id": "tj_serpent_apotheosis", "display_name": "Serpent Apotheosis", "description": "Become one with the Great Serpent.", "tier": 5, "category": "military", "prerequisites": ["tj_serpent_kings", "tj_jade_avatar"], "effects": {"unit_attack_bonus": 6, "unit_speed_bonus": 3, "unit_morale_bonus": 20}, "tree_angle": 0.0, "tree_branch": "serpent_lore"},
    # dark_botany T4-T5
    {"id": "tj_plague_garden", "display_name": "Plague Garden", "description": "A garden of disease and death.", "tier": 4, "category": "arcane", "prerequisites": ["living_city"], "effects": {"siege_bonus": 15, "unit_attack_bonus": 3}, "tree_angle": 115.0, "tree_branch": "dark_botany"},
    {"id": "tj_world_vine", "display_name": "World Vine", "description": "A vine that spans the world.", "tier": 5, "category": "arcane", "prerequisites": ["tj_plague_garden"], "effects": {"unit_attack_bonus": 5, "income_food_pct": 20}, "tree_angle": 120.0, "tree_branch": "dark_botany"},
    # blood_rites T4-T5
    {"id": "tj_blood_frenzy", "display_name": "Blood Frenzy", "description": "Sacrificial blood drives warriors mad.", "tier": 4, "category": "arcane", "prerequisites": ["blood_pact", "jade_apotheosis"], "effects": {"unit_attack_bonus": 5, "unit_morale_bonus": 10}, "tree_angle": 235.0, "tree_branch": "blood_rites"},
    {"id": "tj_blood_god", "display_name": "Blood God Awakened", "description": "The blood god stirs from ancient slumber.", "tier": 5, "category": "arcane", "prerequisites": ["tj_blood_frenzy", "tj_serpent_apotheosis"], "effects": {"unit_attack_bonus": 7, "unit_morale_bonus": 25}, "tree_angle": 240.0, "tree_branch": "blood_rites"},
    # venom_mastery (60°) NEW
    {"id": "tj_poison_blades", "display_name": "Poison Blades", "description": "Weapons coated in lethal venom.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_attack_bonus": 1}, "tree_angle": 60.0, "tree_branch": "venom_mastery"},
    {"id": "tj_toxic_darts", "display_name": "Toxic Darts", "description": "Ranged weapons tipped with poison.", "tier": 2, "category": "military", "prerequisites": ["tj_poison_blades"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "venom_mastery"},
    {"id": "tj_paralytic_venom", "display_name": "Paralytic Venom", "description": "Venom that freezes enemies in place.", "tier": 2, "category": "military", "prerequisites": ["tj_poison_blades"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 70.0, "tree_branch": "venom_mastery"},
    {"id": "tj_venom_lord", "display_name": "Venom Lord", "description": "Master of all poisons and toxins.", "tier": 3, "category": "military", "prerequisites": ["tj_toxic_darts", "tj_paralytic_venom"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 60.0, "tree_branch": "venom_mastery"},
    {"id": "tj_death_cloud", "display_name": "Death Cloud", "description": "A cloud of lethal poison engulfs the field.", "tier": 4, "category": "military", "prerequisites": ["tj_venom_lord"], "effects": {"unit_attack_bonus": 4, "siege_bonus": 10}, "tree_angle": 60.0, "tree_branch": "venom_mastery"},
    # fungal_network (180°) NEW
    {"id": "tj_mushroom_farms", "display_name": "Mushroom Farms", "description": "Cultivated fungi feed the jungle tribes.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_food_pct": 5}, "tree_angle": 180.0, "tree_branch": "fungal_network"},
    {"id": "tj_spore_scouts", "display_name": "Spore Scouts", "description": "Fungal spores relay information.", "tier": 2, "category": "logistics", "prerequisites": ["tj_mushroom_farms"], "effects": {"vision_range_bonus": 1}, "tree_angle": 175.0, "tree_branch": "fungal_network"},
    {"id": "tj_mycelium_web", "display_name": "Mycelium Web", "description": "Underground networks connect settlements.", "tier": 2, "category": "logistics", "prerequisites": ["tj_mushroom_farms"], "effects": {"movement_bonus": 1, "supply_range_bonus": 1}, "tree_angle": 190.0, "tree_branch": "fungal_network"},
    {"id": "tj_fungal_hive", "display_name": "Fungal Hive Mind", "description": "A psychic network of fungal intelligence.", "tier": 3, "category": "arcane", "prerequisites": ["tj_spore_scouts", "tj_mycelium_web"], "effects": {"research_speed_bonus": 15}, "tree_angle": 180.0, "tree_branch": "fungal_network"},
    {"id": "tj_fungal_titan", "display_name": "Fungal Titan", "description": "A massive fungal war creature.", "tier": 4, "category": "arcane", "prerequisites": ["tj_fungal_hive"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 3}, "tree_angle": 180.0, "tree_branch": "fungal_network"},
    # jade_throne (300°) capstone
    {"id": "tj_ritual_war", "display_name": "Ritual War", "description": "War itself becomes a sacred ritual.", "tier": 3, "category": "military", "prerequisites": ["serpent_strike", "blood_magic"], "effects": {"unit_attack_bonus": 2, "unit_morale_bonus": 10}, "tree_angle": 310.0, "tree_branch": "jade_throne"},
    {"id": "tj_jade_avatar", "display_name": "Jade Avatar", "description": "An avatar of jade power.", "tier": 4, "category": "arcane", "prerequisites": ["tj_ritual_war", "tj_death_cloud"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 300.0, "tree_branch": "jade_throne"},
    {"id": "tj_jade_god", "display_name": "Jade God Reborn", "description": "The ancient Jade God walks the earth again.", "tier": 5, "category": "arcane", "prerequisites": ["tj_jade_avatar", "tj_world_vine"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 5, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "jade_throne"},
]

# ═══════════════════════════════════════════════════════════════
# CINDERGUARD RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: forging(0°), flamecraft(120°), garrison_duty(240°)
# New: magma(60°), industry(180°), eternal_flame(300°)
CINDERGUARD = [
    # forging T4-T5
    {"id": "cg_master_alloys", "display_name": "Master Alloys", "description": "Alloys harder than any known metal.", "tier": 4, "category": "economy", "prerequisites": ["industrial_revolution"], "effects": {"unit_defense_bonus": 4, "unit_attack_bonus": 2}, "tree_angle": 350.0, "tree_branch": "forging"},
    {"id": "cg_forge_eternal", "display_name": "Forge Eternal", "description": "A forge that never dims.", "tier": 5, "category": "economy", "prerequisites": ["cg_master_alloys", "cg_volcanic_lord"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 5, "income_gold_pct": 20}, "tree_angle": 0.0, "tree_branch": "forging"},
    # flamecraft T4-T5
    {"id": "cg_firestorm", "display_name": "Firestorm", "description": "Unleash devastating firestorms.", "tier": 4, "category": "arcane", "prerequisites": ["inferno_engine", "molten_moat"], "effects": {"unit_attack_bonus": 5, "siege_bonus": 15}, "tree_angle": 115.0, "tree_branch": "flamecraft"},
    {"id": "cg_phoenix_fire", "display_name": "Phoenix Fire", "description": "Fire that gives life as well as death.", "tier": 5, "category": "arcane", "prerequisites": ["cg_firestorm"], "effects": {"unit_attack_bonus": 6, "unit_hp_bonus": 15}, "tree_angle": 120.0, "tree_branch": "flamecraft"},
    # garrison_duty T4-T5
    {"id": "cg_bastion_lords", "display_name": "Bastion Lords", "description": "Unbreakable fortress commanders.", "tier": 4, "category": "military", "prerequisites": ["eternal_watch"], "effects": {"defense_bonus": 10, "unit_morale_bonus": 15}, "tree_angle": 235.0, "tree_branch": "garrison_duty"},
    {"id": "cg_iron_citadel", "display_name": "Iron Citadel", "description": "The ultimate defensive fortification.", "tier": 5, "category": "military", "prerequisites": ["cg_bastion_lords", "cg_forge_eternal"], "effects": {"defense_bonus": 15, "unit_defense_bonus": 5, "unit_morale_bonus": 20}, "tree_angle": 240.0, "tree_branch": "garrison_duty"},
    # magma (60°) NEW
    {"id": "cg_lava_channels", "display_name": "Lava Channels", "description": "Controlled lava flows power industry.", "tier": 1, "category": "arcane", "prerequisites": [], "effects": {"income_gold_pct": 5}, "tree_angle": 60.0, "tree_branch": "magma"},
    {"id": "cg_magma_weapons", "display_name": "Magma Weapons", "description": "Weapons forged in living magma.", "tier": 2, "category": "arcane", "prerequisites": ["cg_lava_channels"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "magma"},
    {"id": "cg_obsidian_armor", "display_name": "Obsidian Armor", "description": "Volcanic glass armor with magical hardness.", "tier": 2, "category": "arcane", "prerequisites": ["cg_lava_channels"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 70.0, "tree_branch": "magma"},
    {"id": "cg_volcanic_wrath", "display_name": "Volcanic Wrath", "description": "Channel volcanic fury into battle.", "tier": 3, "category": "arcane", "prerequisites": ["cg_magma_weapons", "cg_obsidian_armor"], "effects": {"unit_attack_bonus": 3, "siege_bonus": 10}, "tree_angle": 60.0, "tree_branch": "magma"},
    {"id": "cg_volcanic_lord", "display_name": "Volcanic Lord", "description": "Master of fire and earth.", "tier": 4, "category": "arcane", "prerequisites": ["cg_volcanic_wrath"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 60.0, "tree_branch": "magma"},
    # industry (180°) NEW
    {"id": "cg_coal_mines", "display_name": "Coal Mines", "description": "Deep coal mines fuel the forges.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_gold_pct": 5}, "tree_angle": 180.0, "tree_branch": "industry"},
    {"id": "cg_blast_furnace", "display_name": "Blast Furnace", "description": "Industrial-scale metal production.", "tier": 2, "category": "economy", "prerequisites": ["cg_coal_mines"], "effects": {"income_gold_pct": 8}, "tree_angle": 175.0, "tree_branch": "industry"},
    {"id": "cg_rail_carts", "display_name": "Rail Carts", "description": "Mine carts speed supply lines.", "tier": 2, "category": "logistics", "prerequisites": ["cg_coal_mines"], "effects": {"movement_bonus": 1, "supply_range_bonus": 1}, "tree_angle": 190.0, "tree_branch": "industry"},
    {"id": "cg_mass_production", "display_name": "Mass Production", "description": "Standardized production lowers costs.", "tier": 3, "category": "economy", "prerequisites": ["cg_blast_furnace", "cg_rail_carts"], "effects": {"recruitment_cost_reduction": 10, "upkeep_reduction": 8}, "tree_angle": 180.0, "tree_branch": "industry"},
    {"id": "cg_industrial_might", "display_name": "Industrial Might", "description": "Unmatched industrial capacity.", "tier": 4, "category": "economy", "prerequisites": ["cg_mass_production"], "effects": {"income_gold_pct": 15, "recruitment_cost_reduction": 15}, "tree_angle": 180.0, "tree_branch": "industry"},
    # eternal_flame (300°) capstone
    {"id": "cg_flame_ward", "display_name": "Flame Ward", "description": "Fire protects as well as destroys.", "tier": 3, "category": "military", "prerequisites": ["scorched_earth", "magma_channeling"], "effects": {"defense_bonus": 5, "unit_defense_bonus": 2}, "tree_angle": 310.0, "tree_branch": "eternal_flame"},
    {"id": "cg_cinder_lords", "display_name": "Cinder Lords", "description": "Warriors of living flame.", "tier": 4, "category": "military", "prerequisites": ["cg_flame_ward", "cg_volcanic_lord"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}, "tree_angle": 305.0, "tree_branch": "eternal_flame"},
    {"id": "cg_eternal_flame", "display_name": "The Eternal Flame", "description": "The fire that shall never be extinguished.", "tier": 5, "category": "military", "prerequisites": ["cg_cinder_lords", "cg_iron_citadel"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 6, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "eternal_flame"},
]

# ═══════════════════════════════════════════════════════════════
# FORSAKEN RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: necromancy(0°), decay(120°), shadow_war(240°)
# New: soul_magic(60°), blight(180°), death_throne(300°)
FORSAKEN = [
    # necromancy T4-T5
    {"id": "fk_lich_lords", "display_name": "Lich Lords", "description": "Undead sorcerers of immense power.", "tier": 4, "category": "arcane", "prerequisites": ["undying_legion"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 350.0, "tree_branch": "necromancy"},
    {"id": "fk_death_eternal", "display_name": "Death Eternal", "description": "Death itself serves the Forsaken.", "tier": 5, "category": "arcane", "prerequisites": ["fk_lich_lords", "fk_soul_harvest"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 5, "unit_hp_bonus": 20}, "tree_angle": 0.0, "tree_branch": "necromancy"},
    # decay T4-T5
    {"id": "fk_plague_lords", "display_name": "Plague Lords", "description": "Masters of disease and decay.", "tier": 4, "category": "arcane", "prerequisites": ["miasma_cloud"], "effects": {"unit_attack_bonus": 4, "siege_bonus": 15}, "tree_angle": 115.0, "tree_branch": "decay"},
    {"id": "fk_world_rot", "display_name": "World Rot", "description": "All things decay. All things fall.", "tier": 5, "category": "arcane", "prerequisites": ["fk_plague_lords"], "effects": {"unit_attack_bonus": 5, "siege_bonus": 20}, "tree_angle": 120.0, "tree_branch": "decay"},
    # shadow_war T4-T5
    {"id": "fk_shadow_lords", "display_name": "Shadow Lords", "description": "Masters of shadow and stealth.", "tier": 4, "category": "military", "prerequisites": ["hollow_throne"], "effects": {"unit_attack_bonus": 4, "flanking_damage_bonus": 20}, "tree_angle": 235.0, "tree_branch": "shadow_war"},
    {"id": "fk_void_army", "display_name": "Void Army", "description": "An army that exists between worlds.", "tier": 5, "category": "military", "prerequisites": ["fk_shadow_lords", "fk_death_eternal"], "effects": {"unit_attack_bonus": 6, "unit_speed_bonus": 3, "flanking_damage_bonus": 25}, "tree_angle": 240.0, "tree_branch": "shadow_war"},
    # soul_magic (60°) NEW
    {"id": "fk_soul_siphon", "display_name": "Soul Siphon", "description": "Drain life force from enemies.", "tier": 1, "category": "arcane", "prerequisites": [], "effects": {"unit_attack_bonus": 1}, "tree_angle": 60.0, "tree_branch": "soul_magic"},
    {"id": "fk_spirit_chains", "display_name": "Spirit Chains", "description": "Bind spirits to serve in death.", "tier": 2, "category": "arcane", "prerequisites": ["fk_soul_siphon"], "effects": {"unit_attack_bonus": 2}, "tree_angle": 55.0, "tree_branch": "soul_magic"},
    {"id": "fk_wraith_guard", "display_name": "Wraith Guard", "description": "Ghostly warriors that cannot be slain.", "tier": 2, "category": "arcane", "prerequisites": ["fk_soul_siphon"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 70.0, "tree_branch": "soul_magic"},
    {"id": "fk_soul_storm", "display_name": "Soul Storm", "description": "A storm of tortured souls.", "tier": 3, "category": "arcane", "prerequisites": ["fk_spirit_chains", "fk_wraith_guard"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 60.0, "tree_branch": "soul_magic"},
    {"id": "fk_soul_harvest", "display_name": "Soul Harvest", "description": "Reap the souls of the fallen.", "tier": 4, "category": "arcane", "prerequisites": ["fk_soul_storm"], "effects": {"unit_attack_bonus": 4, "unit_hp_bonus": 10}, "tree_angle": 60.0, "tree_branch": "soul_magic"},
    # blight (180°) NEW
    {"id": "fk_dark_harvest", "display_name": "Dark Harvest", "description": "Blighted crops still feed the dead.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_food_pct": 5}, "tree_angle": 180.0, "tree_branch": "blight"},
    {"id": "fk_bone_trade", "display_name": "Bone Trade", "description": "Trading in bones and relics.", "tier": 2, "category": "economy", "prerequisites": ["fk_dark_harvest"], "effects": {"income_gold_pct": 8, "trade_income_bonus": 5}, "tree_angle": 175.0, "tree_branch": "blight"},
    {"id": "fk_corpse_labor", "display_name": "Corpse Labor", "description": "The dead toil endlessly.", "tier": 2, "category": "economy", "prerequisites": ["fk_dark_harvest"], "effects": {"upkeep_reduction": 5, "recruitment_cost_reduction": 5}, "tree_angle": 190.0, "tree_branch": "blight"},
    {"id": "fk_necropolis", "display_name": "Necropolis", "description": "Cities of the dead thrive.", "tier": 3, "category": "economy", "prerequisites": ["fk_bone_trade", "fk_corpse_labor"], "effects": {"income_gold_pct": 12, "upkeep_reduction": 8}, "tree_angle": 180.0, "tree_branch": "blight"},
    {"id": "fk_blight_empire", "display_name": "Blight Empire", "description": "An empire of undeath.", "tier": 4, "category": "economy", "prerequisites": ["fk_necropolis"], "effects": {"income_gold_pct": 15, "recruitment_cost_reduction": 15}, "tree_angle": 180.0, "tree_branch": "blight"},
    # death_throne (300°) capstone
    {"id": "fk_dark_pact", "display_name": "Dark Pact", "description": "A pact with powers beyond death.", "tier": 3, "category": "arcane", "prerequisites": ["soul_binding", "night_ambush"], "effects": {"unit_attack_bonus": 2, "unit_morale_bonus": 10}, "tree_angle": 310.0, "tree_branch": "death_throne"},
    {"id": "fk_death_king", "display_name": "Death King", "description": "The Death King rises.", "tier": 4, "category": "arcane", "prerequisites": ["fk_dark_pact", "fk_soul_harvest"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}, "tree_angle": 300.0, "tree_branch": "death_throne"},
    {"id": "fk_lord_undeath", "display_name": "Lord of Undeath", "description": "All shall serve in death eternal.", "tier": 5, "category": "arcane", "prerequisites": ["fk_death_king", "fk_void_army"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 6, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "death_throne"},
]

# ═══════════════════════════════════════════════════════════════
# IVORYSCAR RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: petrification(0°), relics(120°), void_sight(240°)
# New: desert_power(60°), tomb_lords(180°), medusa_crown(300°)
IVORYSCAR = [
    # petrification T4-T5
    {"id": "iv_stone_army", "display_name": "Stone Army", "description": "Petrified enemies become your army.", "tier": 4, "category": "arcane", "prerequisites": ["petrified_legion"], "effects": {"unit_defense_bonus": 5, "unit_attack_bonus": 3}, "tree_angle": 350.0, "tree_branch": "petrification"},
    {"id": "iv_gorgon_queen", "display_name": "Gorgon Queen", "description": "The Gorgon Queen's gaze turns all to stone.", "tier": 5, "category": "arcane", "prerequisites": ["iv_stone_army", "iv_medusa_avatar"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 6}, "tree_angle": 0.0, "tree_branch": "petrification"},
    # relics T4-T5
    {"id": "iv_relic_army", "display_name": "Relic Army", "description": "Armies armed with ancient relics.", "tier": 4, "category": "military", "prerequisites": ["dust_trader_network", "reliquary_vault"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 115.0, "tree_branch": "relics"},
    {"id": "iv_eternal_tomb", "display_name": "Eternal Tomb", "description": "The greatest tomb holds the greatest power.", "tier": 5, "category": "military", "prerequisites": ["iv_relic_army"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 5, "defense_bonus": 10}, "tree_angle": 120.0, "tree_branch": "relics"},
    # void_sight T4-T5
    {"id": "iv_void_seers", "display_name": "Void Seers", "description": "Those who see through the void.", "tier": 4, "category": "arcane", "prerequisites": ["all_seeing_eye", "medusa_ascension"], "effects": {"unit_attack_bonus": 4, "vision_range_bonus": 2}, "tree_angle": 235.0, "tree_branch": "void_sight"},
    {"id": "iv_void_crown", "display_name": "Void Crown", "description": "Crown of infinite sight.", "tier": 5, "category": "arcane", "prerequisites": ["iv_void_seers"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 4, "research_speed_bonus": 20}, "tree_angle": 240.0, "tree_branch": "void_sight"},
    # desert_power (60°) NEW
    {"id": "iv_sandstone_walls", "display_name": "Sandstone Walls", "description": "Walls that blend with the desert.", "tier": 1, "category": "logistics", "prerequisites": [], "effects": {"defense_bonus": 3}, "tree_angle": 60.0, "tree_branch": "desert_power"},
    {"id": "iv_dust_warriors", "display_name": "Dust Warriors", "description": "Warriors hardened by desert life.", "tier": 2, "category": "military", "prerequisites": ["iv_sandstone_walls"], "effects": {"unit_defense_bonus": 2, "unit_speed_bonus": 1}, "tree_angle": 55.0, "tree_branch": "desert_power"},
    {"id": "iv_oasis_control", "display_name": "Oasis Control", "description": "Control water, control the desert.", "tier": 2, "category": "economy", "prerequisites": ["iv_sandstone_walls"], "effects": {"income_food_pct": 8, "income_gold_pct": 5}, "tree_angle": 70.0, "tree_branch": "desert_power"},
    {"id": "iv_sand_magic", "display_name": "Sand Magic", "description": "Magic drawn from the endless sands.", "tier": 3, "category": "arcane", "prerequisites": ["iv_dust_warriors", "iv_oasis_control"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 60.0, "tree_branch": "desert_power"},
    {"id": "iv_desert_lords", "display_name": "Desert Lords", "description": "Absolute rulers of the wastelands.", "tier": 4, "category": "military", "prerequisites": ["iv_sand_magic"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3}, "tree_angle": 60.0, "tree_branch": "desert_power"},
    # tomb_lords (180°) NEW
    {"id": "iv_tomb_builders", "display_name": "Tomb Builders", "description": "Ancient tombs hold ancient power.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_gold_pct": 5}, "tree_angle": 180.0, "tree_branch": "tomb_lords"},
    {"id": "iv_tomb_guardians", "display_name": "Tomb Guardians", "description": "Eternal guardians of sacred tombs.", "tier": 2, "category": "military", "prerequisites": ["iv_tomb_builders"], "effects": {"unit_defense_bonus": 2, "unit_morale_bonus": 5}, "tree_angle": 175.0, "tree_branch": "tomb_lords"},
    {"id": "iv_death_masks", "display_name": "Death Masks", "description": "Funeral masks grant power over death.", "tier": 2, "category": "arcane", "prerequisites": ["iv_tomb_builders"], "effects": {"unit_attack_bonus": 1, "unit_morale_bonus": 5}, "tree_angle": 190.0, "tree_branch": "tomb_lords"},
    {"id": "iv_pharaoh_guard", "display_name": "Pharaoh's Guard", "description": "Elite guards of the ancient pharaohs.", "tier": 3, "category": "military", "prerequisites": ["iv_tomb_guardians", "iv_death_masks"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 3}, "tree_angle": 180.0, "tree_branch": "tomb_lords"},
    {"id": "iv_eternal_dynasty", "display_name": "Eternal Dynasty", "description": "A dynasty that transcends death.", "tier": 4, "category": "economy", "prerequisites": ["iv_pharaoh_guard"], "effects": {"income_gold_pct": 15, "unit_morale_bonus": 10}, "tree_angle": 180.0, "tree_branch": "tomb_lords"},
    # medusa_crown (300°) capstone
    {"id": "iv_stone_gaze", "display_name": "Stone Gaze Mastery", "description": "Perfect the art of petrification.", "tier": 3, "category": "arcane", "prerequisites": ["ivory_curse", "void_lens"], "effects": {"unit_attack_bonus": 2, "unit_defense_bonus": 2}, "tree_angle": 310.0, "tree_branch": "medusa_crown"},
    {"id": "iv_medusa_avatar", "display_name": "Medusa Avatar", "description": "Channel the full power of the Medusa.", "tier": 4, "category": "arcane", "prerequisites": ["iv_stone_gaze", "iv_desert_lords"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}, "tree_angle": 300.0, "tree_branch": "medusa_crown"},
    {"id": "iv_stone_god", "display_name": "Stone God Awakened", "description": "The Stone God awakens from eternal slumber.", "tier": 5, "category": "arcane", "prerequisites": ["iv_medusa_avatar", "iv_gorgon_queen"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 7, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "medusa_crown"},
]

# ═══════════════════════════════════════════════════════════════
# SHARDHORDE RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: crystal_evolution(0°), swarm_tactics(120°), shard_communion(240°)
# New: beast_mastery(60°), hive_network(180°), shard_ascension(300°)
SHARDHORDE = [
    # crystal_evolution T4-T5
    {"id": "sh_crystal_titan", "display_name": "Crystal Titan", "description": "A massive crystalline war creature.", "tier": 4, "category": "arcane", "prerequisites": ["shard_apotheosis"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4}, "tree_angle": 350.0, "tree_branch": "crystal_evolution"},
    {"id": "sh_crystal_god", "display_name": "Crystal God", "description": "Ascend to crystalline divinity.", "tier": 5, "category": "arcane", "prerequisites": ["sh_crystal_titan", "sh_shard_god"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 6, "shard_harvest_bonus": 20}, "tree_angle": 0.0, "tree_branch": "crystal_evolution"},
    # swarm_tactics T4-T5
    {"id": "sh_swarm_lords", "display_name": "Swarm Lords", "description": "Alpha beasts command vast swarms.", "tier": 4, "category": "military", "prerequisites": ["unstoppable_swarm", "elderbeast_evolution"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 3}, "tree_angle": 115.0, "tree_branch": "swarm_tactics"},
    {"id": "sh_infinite_swarm", "display_name": "Infinite Swarm", "description": "An endless tide of crystal creatures.", "tier": 5, "category": "military", "prerequisites": ["sh_swarm_lords"], "effects": {"unit_attack_bonus": 6, "unit_speed_bonus": 4, "recruitment_cost_reduction": 20}, "tree_angle": 120.0, "tree_branch": "swarm_tactics"},
    # shard_communion T4-T5
    {"id": "sh_resonance_lords", "display_name": "Resonance Lords", "description": "Masters of crystal resonance.", "tier": 4, "category": "arcane", "prerequisites": ["crystal_network", "crystal_storm"], "effects": {"unit_attack_bonus": 4, "shard_harvest_bonus": 15}, "tree_angle": 235.0, "tree_branch": "shard_communion"},
    {"id": "sh_shard_god", "display_name": "Shard God Awakened", "description": "The Shard itself becomes a god.", "tier": 5, "category": "arcane", "prerequisites": ["sh_resonance_lords"], "effects": {"unit_attack_bonus": 6, "shard_harvest_bonus": 25}, "tree_angle": 240.0, "tree_branch": "shard_communion"},
    # beast_mastery (60°) NEW
    {"id": "sh_beast_bond", "display_name": "Beast Bond", "description": "Bond with crystal beasts.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_attack_bonus": 1}, "tree_angle": 60.0, "tree_branch": "beast_mastery"},
    {"id": "sh_beast_breeding", "display_name": "Beast Breeding", "description": "Breed stronger crystal beasts.", "tier": 2, "category": "military", "prerequisites": ["sh_beast_bond"], "effects": {"unit_attack_bonus": 2, "unit_hp_bonus": 5}, "tree_angle": 55.0, "tree_branch": "beast_mastery"},
    {"id": "sh_war_beasts", "display_name": "Crystal War Beasts", "description": "Crystal-armored war beasts.", "tier": 2, "category": "military", "prerequisites": ["sh_beast_bond"], "effects": {"unit_defense_bonus": 2, "unit_speed_bonus": 1}, "tree_angle": 70.0, "tree_branch": "beast_mastery"},
    {"id": "sh_alpha_pack", "display_name": "Alpha Pack", "description": "Elite beast packs led by alphas.", "tier": 3, "category": "military", "prerequisites": ["sh_beast_breeding", "sh_war_beasts"], "effects": {"unit_attack_bonus": 3, "unit_speed_bonus": 2}, "tree_angle": 60.0, "tree_branch": "beast_mastery"},
    {"id": "sh_beast_lords", "display_name": "Beast Lords", "description": "Supreme commanders of crystal beasts.", "tier": 4, "category": "military", "prerequisites": ["sh_alpha_pack"], "effects": {"unit_attack_bonus": 4, "unit_speed_bonus": 3}, "tree_angle": 60.0, "tree_branch": "beast_mastery"},
    # hive_network (180°) NEW
    {"id": "sh_crystal_tunnels", "display_name": "Crystal Tunnels", "description": "Underground crystal passages.", "tier": 1, "category": "logistics", "prerequisites": [], "effects": {"movement_bonus": 1}, "tree_angle": 180.0, "tree_branch": "hive_network"},
    {"id": "sh_shard_miners", "display_name": "Shard Miners", "description": "Specialized crystal harvesters.", "tier": 2, "category": "economy", "prerequisites": ["sh_crystal_tunnels"], "effects": {"shard_harvest_bonus": 8, "income_gold_pct": 5}, "tree_angle": 175.0, "tree_branch": "hive_network"},
    {"id": "sh_hive_comms", "display_name": "Hive Communications", "description": "Crystal resonance enables instant communication.", "tier": 2, "category": "logistics", "prerequisites": ["sh_crystal_tunnels"], "effects": {"supply_range_bonus": 1, "vision_range_bonus": 1}, "tree_angle": 190.0, "tree_branch": "hive_network"},
    {"id": "sh_crystal_fortress", "display_name": "Crystal Fortress", "description": "Fortresses grown from living crystal.", "tier": 3, "category": "logistics", "prerequisites": ["sh_shard_miners", "sh_hive_comms"], "effects": {"defense_bonus": 5, "shard_harvest_bonus": 10}, "tree_angle": 180.0, "tree_branch": "hive_network"},
    {"id": "sh_hive_mind", "display_name": "Hive Mind", "description": "A collective crystal consciousness.", "tier": 4, "category": "logistics", "prerequisites": ["sh_crystal_fortress"], "effects": {"movement_bonus": 2, "supply_range_bonus": 2, "research_speed_bonus": 15}, "tree_angle": 180.0, "tree_branch": "hive_network"},
    # shard_ascension (300°) capstone
    {"id": "sh_crystal_rage", "display_name": "Crystal Rage", "description": "Crystal energy fuels berserker fury.", "tier": 3, "category": "military", "prerequisites": ["alpha_command", "resonance_field"], "effects": {"unit_attack_bonus": 3, "unit_speed_bonus": 1}, "tree_angle": 310.0, "tree_branch": "shard_ascension"},
    {"id": "sh_shard_champions", "display_name": "Shard Champions", "description": "Elite warriors infused with shard power.", "tier": 4, "category": "military", "prerequisites": ["sh_crystal_rage", "sh_beast_lords"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 3}, "tree_angle": 305.0, "tree_branch": "shard_ascension"},
    {"id": "sh_shard_ascendant", "display_name": "Shard Ascendant", "description": "Transcend mortal form through crystal power.", "tier": 5, "category": "military", "prerequisites": ["sh_shard_champions", "sh_infinite_swarm"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 5, "unit_morale_bonus": 25, "shard_harvest_bonus": 20}, "tree_angle": 300.0, "tree_branch": "shard_ascension"},
]

# ═══════════════════════════════════════════════════════════════
# SUNBLESSED RESEARCH
# ═══════════════════════════════════════════════════════════════
# Existing: solar_faith(0°), pilgrimage(120°), sacred_flame(240°)
# New: dawn_guard(60°), sun_harvest(180°), solar_throne(300°)
SUNBLESSED = [
    # solar_faith T4-T5
    {"id": "sb_sun_priests", "display_name": "Sun Priests", "description": "Holy priests channel the sun's power.", "tier": 4, "category": "arcane", "prerequisites": ["solar_ascension", "oasis_blessing"], "effects": {"unit_attack_bonus": 3, "unit_hp_bonus": 10}, "tree_angle": 350.0, "tree_branch": "solar_faith"},
    {"id": "sb_solar_god", "display_name": "Solar God Incarnate", "description": "The Sun God walks among mortals.", "tier": 5, "category": "arcane", "prerequisites": ["sb_sun_priests", "sb_solar_champion"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 5, "unit_morale_bonus": 20}, "tree_angle": 0.0, "tree_branch": "solar_faith"},
    # pilgrimage T4-T5
    {"id": "sb_pilgrim_army", "display_name": "Pilgrim Army", "description": "A vast army of devout pilgrims.", "tier": 4, "category": "military", "prerequisites": ["holy_caravan", "desert_endurance"], "effects": {"unit_morale_bonus": 15, "movement_bonus": 2}, "tree_angle": 115.0, "tree_branch": "pilgrimage"},
    {"id": "sb_holy_land", "display_name": "The Holy Land", "description": "Claim the sacred lands of the sun.", "tier": 5, "category": "military", "prerequisites": ["sb_pilgrim_army"], "effects": {"income_gold_pct": 20, "unit_morale_bonus": 20}, "tree_angle": 120.0, "tree_branch": "pilgrimage"},
    # sacred_flame T4-T5
    {"id": "sb_flame_knights", "display_name": "Flame Knights", "description": "Knights wreathed in sacred fire.", "tier": 4, "category": "military", "prerequisites": ["cleansing_light", "eternal_sun"], "effects": {"unit_attack_bonus": 5, "unit_defense_bonus": 3}, "tree_angle": 235.0, "tree_branch": "sacred_flame"},
    {"id": "sb_purifying_fire", "display_name": "Purifying Fire", "description": "The sacred flame purifies all.", "tier": 5, "category": "military", "prerequisites": ["sb_flame_knights", "sb_solar_god"], "effects": {"unit_attack_bonus": 6, "unit_defense_bonus": 5, "siege_bonus": 15}, "tree_angle": 240.0, "tree_branch": "sacred_flame"},
    # dawn_guard (60°) NEW
    {"id": "sb_dawn_watch", "display_name": "Dawn Watch", "description": "Vigilant guards greet each dawn.", "tier": 1, "category": "military", "prerequisites": [], "effects": {"unit_defense_bonus": 1}, "tree_angle": 60.0, "tree_branch": "dawn_guard"},
    {"id": "sb_sun_shields", "display_name": "Sun Shields", "description": "Shields that reflect the sun's light.", "tier": 2, "category": "military", "prerequisites": ["sb_dawn_watch"], "effects": {"unit_defense_bonus": 2}, "tree_angle": 55.0, "tree_branch": "dawn_guard"},
    {"id": "sb_dawn_cavalry", "display_name": "Dawn Cavalry", "description": "Swift cavalry charging with the dawn.", "tier": 2, "category": "military", "prerequisites": ["sb_dawn_watch"], "effects": {"unit_speed_bonus": 1, "unit_attack_bonus": 1}, "tree_angle": 70.0, "tree_branch": "dawn_guard"},
    {"id": "sb_golden_legion", "display_name": "Golden Legion", "description": "An elite legion clad in gold.", "tier": 3, "category": "military", "prerequisites": ["sb_sun_shields", "sb_dawn_cavalry"], "effects": {"unit_attack_bonus": 3, "unit_defense_bonus": 2}, "tree_angle": 60.0, "tree_branch": "dawn_guard"},
    {"id": "sb_solar_champion", "display_name": "Solar Champion", "description": "A champion blessed by the sun.", "tier": 4, "category": "military", "prerequisites": ["sb_golden_legion"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 3, "unit_morale_bonus": 10}, "tree_angle": 60.0, "tree_branch": "dawn_guard"},
    # sun_harvest (180°) NEW
    {"id": "sb_desert_farms", "display_name": "Desert Farms", "description": "Irrigated farms thrive in the desert.", "tier": 1, "category": "economy", "prerequisites": [], "effects": {"income_food_pct": 5}, "tree_angle": 180.0, "tree_branch": "sun_harvest"},
    {"id": "sb_sun_temples", "display_name": "Sun Temples", "description": "Temples collect tithes and offerings.", "tier": 2, "category": "economy", "prerequisites": ["sb_desert_farms"], "effects": {"income_gold_pct": 8}, "tree_angle": 175.0, "tree_branch": "sun_harvest"},
    {"id": "sb_trade_caravans", "display_name": "Trade Caravans", "description": "Desert caravans connect far markets.", "tier": 2, "category": "economy", "prerequisites": ["sb_desert_farms"], "effects": {"trade_income_bonus": 10}, "tree_angle": 190.0, "tree_branch": "sun_harvest"},
    {"id": "sb_golden_age", "display_name": "Golden Age", "description": "An age of prosperity and plenty.", "tier": 3, "category": "economy", "prerequisites": ["sb_sun_temples", "sb_trade_caravans"], "effects": {"income_gold_pct": 12, "income_food_pct": 10}, "tree_angle": 180.0, "tree_branch": "sun_harvest"},
    {"id": "sb_sun_empire", "display_name": "Sun Empire", "description": "An empire blessed by eternal sun.", "tier": 4, "category": "economy", "prerequisites": ["sb_golden_age"], "effects": {"income_gold_pct": 20, "trade_income_bonus": 15}, "tree_angle": 180.0, "tree_branch": "sun_harvest"},
    # solar_throne (300°) capstone
    {"id": "sb_solar_rites", "display_name": "Solar Rites", "description": "Sacred sun rituals empower warriors.", "tier": 3, "category": "arcane", "prerequisites": ["radiant_aura", "sun_warriors"], "effects": {"unit_morale_bonus": 10, "unit_attack_bonus": 2}, "tree_angle": 310.0, "tree_branch": "solar_throne"},
    {"id": "sb_sun_king", "display_name": "Sun King", "description": "The Sun King leads the faithful.", "tier": 4, "category": "arcane", "prerequisites": ["sb_solar_rites", "sb_solar_champion"], "effects": {"unit_attack_bonus": 4, "unit_defense_bonus": 4, "unit_morale_bonus": 15}, "tree_angle": 300.0, "tree_branch": "solar_throne"},
    {"id": "sb_avatar_sun", "display_name": "Avatar of the Sun", "description": "The Sun itself descends to lead the Sunblessed.", "tier": 5, "category": "arcane", "prerequisites": ["sb_sun_king", "sb_purifying_fire"], "effects": {"unit_attack_bonus": 7, "unit_defense_bonus": 6, "unit_morale_bonus": 25}, "tree_angle": 300.0, "tree_branch": "solar_throne"},
]


def main():
    count = 0
    # Common
    for item in COMMON:
        item["faction_id"] = ""
        write_tres("common", item)
        count += 1

    # Factions
    factions = {
        "empire": EMPIRE,
        "gladehost": GLADEHOST,
        "skulloath": SKULLOATH,
        "moonspear": MOONSPEAR,
        "thunderswarm": THUNDERSWARM,
        "tainted_jade": TAINTED_JADE,
        "cinderguard": CINDERGUARD,
        "forsaken": FORSAKEN,
        "ivoryscar": IVORYSCAR,
        "shardhorde": SHARDHORDE,
        "sunblessed": SUNBLESSED,
    }

    for faction_id, items in factions.items():
        for item in items:
            item["faction_id"] = faction_id
            write_tres(faction_id, item)
            count += 1

    print(f"Generated {count} new research .tres files.")
    # Count total per faction
    for faction_id in factions:
        folder = os.path.join(BASE_DIR, faction_id)
        total = len([f for f in os.listdir(folder) if f.endswith(".tres")])
        print(f"  {faction_id}: {total} total items")
    common_folder = os.path.join(BASE_DIR, "common")
    total_common = len([f for f in os.listdir(common_folder) if f.endswith(".tres")])
    print(f"  common: {total_common} total items")

if __name__ == "__main__":
    main()
