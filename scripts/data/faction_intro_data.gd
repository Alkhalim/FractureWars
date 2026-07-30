class_name FactionIntroData
extends RefCounted
## One-screen onboarding blurb per playable faction, shown once at campaign
## start. Content mirrors the actual mechanics in turn_manager.gd.

const INTROS := {
	&"empire": {
		title = "The Empire — Stable Hegemon",
		mechanic = "Imperial Authority (0-100) rises with territory, cultural buildings and a tech lead. At 75+ your treasury and diplomacy flourish; below 25 your cities slide toward crisis.",
		dilemma = "Every 5 turns the Senate offers an Edict: Military (+attack), Economic (+gold), Cultural (+loyalty) or Diplomatic (+standing). Senate policies and class politics are yours alone to manage.",
		resource = "Affinity resource: Saffron Reeds (+trade gold). Your legions favor heavy infantry and disciplined lines.",
		opening = "Expand steadily, keep Authority high, and pivot Edicts to match the moment. Watch your class loyalties in the Senate.",
	},
	&"skulloath": {
		title = "Skulloath — The Corruption Path",
		mechanic = "Corruption (0-100) is a slider between two identities: stay Pure (≤20) for loyalty, food and defense, or embrace the demonic (61+) for up to +30% attack and captive-fueled industry.",
		dilemma = "Every 4 turns the Dark Bargain lets you push either way: sacrifice captives to rise, spend gold on rites to fall, or walk the line for technology.",
		resource = "Affinity resource: Bloodsalt (+captive conversion). Your roster is fast raider cavalry — hit, take captives, vanish.",
		opening = "Pick your path early. Captives are fuel either way — raid often.",
	},
	&"gladehost": {
		title = "Gladehost — Harmony and the Seasons",
		mechanic = "Harmony (0-100) multiplies your seasonal income — but over-building drains it. Spring feeds, Summer arms, Autumn enriches, Winter tests you.",
		dilemma = "Each season change offers a Festival: feast for harmony, toil for resources, or rest quietly.",
		resource = "Affinity resource: Heartwood (+food). Wood-hungry defensive roster with healing and armor auras.",
		opening = "Build LESS than you think you should. Hold forests, ride the seasons, let attackers break on your groves.",
	},
	&"moonspear": {
		title = "Moonspear — The Lunar Cycle",
		mechanic = "The moon cycles every 4 turns: New Moon sharpens attack, Waxing hastens marches, Full Moon hardens defense, Waning mends wounds. Your ethereal soldiers dodge blows but carry less flesh.",
		dilemma = "At each phase change you may pay to extend a favorable moon or rush past a poor one.",
		resource = "Affinity resource: Moonsilver (-heavy recruit cost). Silver knights and lunar archers reward timing your wars to the sky.",
		opening = "Attack under the New Moon, defend under the Full. Extend the phase that matches your plan.",
	},
	&"sunblessed": {
		title = "Sunblessed — Faith and Wisdom",
		mechanic = "Solar Faith (0-100) grows as your armies walk among foreign cities and blesses your blades at 70+. Wisdom (0-200) accumulates near allies, feeding technology and speeding research.",
		dilemma = "At overflowing Faith (85+), proclaim a Golden Age for a burst of gold and knowledge — or convert zeal into Wisdom.",
		resource = "Affinity resource: Sunstone (+cultural income). A ranged-heavy zealot host with holy beasts.",
		opening = "March pilgrims beside friendly cities in peacetime — faith and wisdom flow from proximity, not conquest.",
	},
	&"shardhorde": {
		title = "Shardhorde — The Devouring Swarm",
		mechanic = "No settlements — your elderbeasts ARE your home. Consume claimed shards for 6-turn realm resonances: iron, gold, food, tech or healing depending on the shard's realm.",
		dilemma = "Manage your Shard Reserve: every crystal eaten is power now instead of research later.",
		resource = "Affinity resource: Shardglass (+arcane research). Giant monsters with double everyone's hit points.",
		opening = "Chase shardfalls relentlessly. Time your consumption windows to your offensives.",
	},
	&"thunderswarm": {
		title = "Thunderswarm — Ride the Fury",
		mechanic = "Storm Fury (0-100) builds from battle and mountain camps, decaying in idleness. High fury electrifies your attacks (+22% at 80).",
		dilemma = "Every 3 turns at 35+ fury, spend it: Storm March (+movement), Thunder Wall (city shield) or Tempest Harvest (resources).",
		resource = "Affinity resource: Stormcrystal (+army speed). Fast fliers and lightning callers built for momentum.",
		opening = "Never stop moving. Fury feeds on war and starves in peace.",
	},
	&"cinderguard": {
		title = "Cinderguard — The Border Forge",
		mechanic = "Border Vigilance swings between Fortress mode (low: +20% defense, thriving settlements) and War Forge (high: +15% attack, iron flowing). Dragon raids strike your settlements every few turns — survive them and grow harder.",
		dilemma = "Frontier Orders every 4 turns shift your posture or raise border fortresses from scavenged scrap.",
		resource = "Affinity resource: Deepiron (+home defense). Iron-clad desert wardens with anti-monster training.",
		opening = "Settle wide, fortify everything, and choose posture deliberately — you cannot be both anvil and hammer at once.",
	},
	&"forsaken": {
		title = "The Forsaken — Shadow Network",
		mechanic = "Your Espionage Network (0-50) grows with territory and spy dens. It reveals enemy capitals, steals gold and research, saboteurs their construction, and at its peak wounds enemy commanders.",
		dilemma = "When agents stand ready you choose the operation — and weigh the detection risk that turns all courts against you.",
		resource = "Undead swarms and fear: many cheap bodies, terrifying auras, ambush bonuses on the attack.",
		opening = "Grow the network before the war. Strike rich enemies from the shadows and let fear finish the rest.",
	},
	&"ivoryscar": {
		title = "Ivoryscar — The Black Pyramid",
		mechanic = "Relic Power flows from shard wastes and hoarded crystals, armoring your tomb legions. Feed gold, iron, essence and whole shards into the Black Pyramid — restore it fully for a permanent empire-wide ascension.",
		dilemma = "Every 5 turns choose: fund expeditions, study quietly, fortify, or invest in the Pyramid itself.",
		resource = "Affinity resource: Shardglass (+arcane research). Slow undead tanks that grind attackers to dust.",
		opening = "Turtle on the wastes, hoard shards, and build toward the Pyramid — your late game is the strongest in the world.",
	},
	&"tainted_jade": {
		title = "Tainted Jade — The Spreading Taint",
		mechanic = "Taint Power grows from processed captives and shattered shards, feeding technology and rotting enemy shards. High taint scars even your own lands.",
		dilemma = "Every 4 turns set your Focus: Verdant (growth), Venomous War (jungle combat), or Creeping Doom (decay and erosion).",
		resource = "Affinity resource: Bloodsalt (+captive conversion). Poison skirmishers strongest in jungle and swamp.",
		opening = "Fight where the jungle favors you, feed the taint with captives, and choose the Focus your era demands.",
	},
}
