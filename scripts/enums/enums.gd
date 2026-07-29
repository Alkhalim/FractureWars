class_name Enums

enum Realm {
	DIVINE,
	VOID,
	ELEMENTAL,
	NATURE,
	MORTAL
}

enum ResourceType {
	GOLD,
	IRON,
	TECHNOLOGY,
	FOOD,
	SHARD_ESSENCE,
	WOOD,
	CAPTIVES
}

enum BattleOrder {
	ADVANCE,
	HOLD,
	FLANK_LEFT,
	FLANK_RIGHT,
	CHARGE,
	RETREAT
}

enum TerrainType {
	PLAINS,
	FOREST,
	MOUNTAINS,
	DESERT,
	SWAMP,
	WETLANDS,
	TUNDRA,
	SHARD_WASTES,
	WATER,
	JUNGLE
}

enum UnitStance {
	AGGRESSIVE,
	DEFENSIVE,
	FLANKING,
	SUPPORT
}

enum TargetPriority {
	CLOSEST,
	WEAKEST,
	STRONGEST,
	RANGED_FIRST,
	SUPPORT_FIRST
}

enum FactionRelation {
	WAR,
	HOSTILE,
	NEUTRAL,
	FRIENDLY,
	ALLIED
}

enum GamePhase {
	MAIN_MENU,
	CAMPAIGN,
	BATTLE_SETUP,
	BATTLE_SIMULATION,
	BATTLE_RESULT,
	EVENT
}

enum BattleTerrain {
	OPEN,
	FOREST,
	ROCK,
	WATER,
	SAND,
	MUD,
	ICE,
	CRYSTAL,
	BRUSH,
	CALTROPS,  # Slow + tick damage
	DITCH,     # Heavy slow
	PALING,    # Damage on charge
	MINE,      # Invisible, one-time explosion
}

enum FormationShape { LINE, LOOSE_LINE, WEDGE, BLOCK, SINGLE, SWARM }

enum DiplomacyAction { DECLARE_WAR, PROPOSE_PEACE, PROPOSE_ALLIANCE, OFFER_TRADE, GIFT_RESOURCES, OFFER_SHARD, THREATEN, PROPOSE_NON_AGGRESSION, DEMAND_TRIBUTARY, OFFER_TRIBUTARY, BREAK_TREATY, DEMAND_RESOURCES, PROPOSE_FREE_PASSAGE, OFFER_CITY, DEMAND_CITY, GIFT_ITEM }
enum TreatyType { PEACE, ALLIANCE, TRADE_DEAL, TRADE_RELATIONS, NON_AGGRESSION_PACT, TRIBUTARY, FREE_PASSAGE, SHARE_VISION, RESOURCE_LEASE }
enum PolicyCategory { TAXATION, MILITARY, CULTURAL, LABOR }
enum VictoryType { NONE, DOMINATION, DIPLOMATIC, SHARD_ASCENSION, ELIMINATION, DEFEAT, CULTURE_VICTORY, LONG_VICTORY, WORLD_CONQUEST }
enum GameMode { QUICKMATCH, SANDBOX }

enum QueueCommand {
	ADVANCE, HOLD, CHARGE, FLANK_LEFT, FLANK_RIGHT, RETREAT,
	FALL_BACK,           # Retreat short distance then hold
	FOCUS_MAGE,          # Advance, prioritize mage targets
	FOCUS_RANGED,        # Advance, prioritize ranged targets
	FOCUS_MONSTER,       # Advance, prioritize monster/beast targets
	FOCUS_CAVALRY,       # Advance, prioritize cavalry targets
	FOCUS_INFANTRY,      # Advance, prioritize infantry/melee targets
}
