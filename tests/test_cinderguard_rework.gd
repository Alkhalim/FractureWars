extends SceneTree
## Task 1 (Package A) of the Cinderguard rework: halve the iron pumps, kill
## the hidden per-city vigilance-iron layer, add the Smelt Surplus sink.
## Run: godot --headless --path . -s res://tests/test_cinderguard_rework.gd

var _fails := 0
var _gm: Node
var _tm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_tm = root.get_node("/root/TurnManager")
	var dm = root.get_node("/root/DataManager")
	_gm.new_game(&"cinderguard", false, 0)

	# ── Building data cuts (halved iron pumps) ──
	_check(dm.get_building(&"ember_foundry").income_bonus.get(1, 0) == 45, "ember foundry iron 45")
	_check(dm.get_building(&"ember_foundry").display_name == "Ember Foundry II", "armory renamed")
	_check(dm.get_building(&"volcanic_smelter").income_bonus.get(1, 0) == 35, "smelter 35")
	_check(dm.get_building(&"cinder_mine").income_bonus.get(1, 0) == 20, "mine 20")
	_check(dm.get_building(&"magma_vent").income_bonus.get(1, 0) == 16, "vent 16")
	_check(dm.get_building(&"molten_core_forge").income_bonus.get(1, 0) == 28, "arsenal 28")

	# ── deepiron extractor untouched (not part of this cut) ──
	_check(dm.get_building(&"extractor_deepiron").income_bonus.get(1, 0) == 20, "deepiron extractor untouched at 20")

	# ── Hidden vigilance-iron layer deleted (income delta parity) ──
	# Isolate the mechanic-income-modifier stage directly: no captives and no
	# forge building present, so the ONLY thing that could move iron here
	# (pre-fix) is the vigilance*0.06 term. Post-fix it must be zero and must
	# not vary with vigilance at all.
	var cg_fs: FactionState = _gm.state.faction_states[&"cinderguard"]
	var vig_city := CityState.new()
	vig_city.faction_id = &"cinderguard"
	cg_fs.resources[Enums.ResourceType.CAPTIVES] = 0
	cg_fs.border_vigilance = 50
	var result_50: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	cg_fs.border_vigilance = 80
	var result_80: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	_check(int(result_50.income_delta.get(Enums.ResourceType.IRON, 0)) == 0, "no vigilance iron bonus at vigilance 50")
	_check(int(result_80.income_delta.get(Enums.ResourceType.IRON, 0)) == 0, "no vigilance iron bonus at vigilance 80")
	_check(int(result_50.income_delta.get(Enums.ResourceType.IRON, 0)) == int(result_80.income_delta.get(Enums.ResourceType.IRON, 0)), "vigilance 50 vs 80 iron income identical")

	# ── Captive forge conversion KEPT (a real trade, not the hidden layer) ──
	cg_fs.resources[Enums.ResourceType.CAPTIVES] = 10
	vig_city.buildings.append(&"ember_foundry")
	var result_forge: Dictionary = _gm.city_system.compute_faction_income_modifier_effects(&"cinderguard", cg_fs, vig_city, {})
	_check(int(result_forge.income_delta.get(Enums.ResourceType.IRON, 0)) == 18, "captive forge conversion kept (+18 iron)")
	_check(int(result_forge.captive_consumption) == 4, "captive forge conversion still consumes 4 captives")

	# ── Smelt Surplus applier: -40 iron, +20 scrap ──
	var cfs: FactionState = _gm.state.faction_states[&"cinderguard"]
	cfs.resources[Enums.ResourceType.IRON] = 100
	var scrap_before: float = cfs.scavenge_stockpile
	_tm._on_faction_dilemma_resolved(&"cinderguard", &"forge_allocation", "forge_smelt")
	_check(int(cfs.resources[Enums.ResourceType.IRON]) == 60, "smelt consumed 40 iron")
	_check(cfs.scavenge_stockpile == scrap_before + 20, "smelt produced 20 scrap")

	# ── Task 2: vigilance is a chosen posture, not a coinflip ──────────
	# Isolate _process_cinderguard_forge from real settlements/buildings so
	# the drift and economics math can be checked exactly.
	var real_owned_cities: Array[StringName] = cg_fs.owned_cities.duplicate()
	cg_fs.owned_cities = []

	# Target-seeking drift: rises ~4/turn toward the target, no auto-centering to 50.
	cg_fs.vigilance_target = 85
	cg_fs.border_vigilance = 50
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 54, "drift +4 toward target 85 (tick 1)")
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 58, "drift +4 toward target 85 (tick 2)")
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 62, "drift +4 toward target 85 (tick 3), not centered back to 50")

	# Posture economics: war footing (>=60) pays iron for gold+food.
	cg_fs.vigilance_target = 80
	cg_fs.border_vigilance = 80
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(cg_fs.border_vigilance == 80, "vigilance holds when already at target (no auto-center)")
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 132, "war footing (80) nets +int(80*0.4)=32 iron")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 92, "war footing (80) costs -int(80*0.1)=8 gold")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 92, "war footing (80) costs -int(80*0.1)=8 food")

	# Mid-band (41-59): flat +2 iron, no gold/food cost.
	cg_fs.vigilance_target = 50
	cg_fs.border_vigilance = 50
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 102, "mid-band nets flat +2 iron")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 100, "mid-band gold untouched")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 100, "mid-band food untouched")

	# Fortress mode (<=40): old flat iron tiers gone (iron +0), loyalty/pop/food perk kept.
	cg_fs.vigilance_target = 15
	cg_fs.border_vigilance = 15
	cg_fs.resources[Enums.ResourceType.IRON] = 100
	cg_fs.resources[Enums.ResourceType.GOLD] = 100
	cg_fs.resources[Enums.ResourceType.FOOD] = 100
	_tm._process_cinderguard_forge(cg_fs)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 100, "fortress mode grants no iron (old flat tiers removed)")
	_check(int(cg_fs.resources[Enums.ResourceType.FOOD]) == 106, "fortress mode still grants +6 food")
	_check(int(cg_fs.resources[Enums.ResourceType.GOLD]) == 104, "fortress mode still grants +4 gold")

	# Threshold-crossing turn_log entries at 30/75 (matches the battle-sim tiers).
	_tm.turn_log.clear()
	cg_fs.vigilance_target = 90
	cg_fs.border_vigilance = 72
	_tm._process_cinderguard_forge(cg_fs) # 72 -> 76, crosses 75 upward
	var crossed_war := false
	for entry in _tm.turn_log:
		if "War Footing" in str(entry.text):
			crossed_war = true
	_check(crossed_war, "crossing 75 upward logs a War Footing turn_log entry")

	_tm.turn_log.clear()
	cg_fs.vigilance_target = 10
	cg_fs.border_vigilance = 33
	_tm._process_cinderguard_forge(cg_fs) # 33 -> 29, crosses 30 downward
	var crossed_fortress := false
	for entry in _tm.turn_log:
		if "Fortress doctrine" in str(entry.text):
			crossed_fortress = true
	_check(crossed_fortress, "crossing 30 downward logs a Fortress doctrine turn_log entry")

	# Exit logging: leaving a combat band (dropping out of War Footing, or
	# rising out of Fortress doctrine) must ALSO log a turn_log entry — a
	# player silently losing +15% attack or +20% defense is a transparency
	# bug just as much as silently gaining it.
	_tm.turn_log.clear()
	cg_fs.vigilance_target = 10
	cg_fs.border_vigilance = 76
	_tm._process_cinderguard_forge(cg_fs) # 76 -> 72, drops below 75 (exits War Footing)
	var left_war := false
	for entry in _tm.turn_log:
		if "War Footing" in str(entry.text) and "cool" in str(entry.text):
			left_war = true
	_check(left_war, "dropping below 75 logs a War Footing EXIT turn_log entry")

	_tm.turn_log.clear()
	cg_fs.vigilance_target = 90
	cg_fs.border_vigilance = 28
	_tm._process_cinderguard_forge(cg_fs) # 28 -> 32, rises above 30 (exits Fortress doctrine)
	var left_fortress := false
	for entry in _tm.turn_log:
		if "Fortress doctrine" in str(entry.text) and "stirs" in str(entry.text):
			left_fortress = true
	_check(left_fortress, "rising above 30 logs a Fortress doctrine EXIT turn_log entry")

	cg_fs.owned_cities = real_owned_cities

	# ── AI posture selection: War Footing at war, Fortress Doctrine at peace ──
	var no_settlements: Array[StringName] = []
	cg_fs.border_fortresses.clear()
	cg_fs.scavenge_stockpile = 0
	cg_fs.resources[Enums.ResourceType.IRON] = 50
	_gm._set_relation(&"cinderguard", &"empire", Enums.FactionRelation.WAR)
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(cg_fs.vigilance_target == 85, "AI sets War Footing target (85) while at war")

	_gm._set_relation(&"cinderguard", &"empire", Enums.FactionRelation.HOSTILE)
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(cg_fs.vigilance_target == 15, "AI sets Fortress Doctrine target (15) when not at war")

	# AI smelts surplus iron instead of touching posture when iron is very high.
	cg_fs.vigilance_target = 50
	cg_fs.resources[Enums.ResourceType.IRON] = 350
	var scrap_before2: float = cg_fs.scavenge_stockpile
	_tm._ai_handle_frontier_orders(cg_fs, no_settlements)
	_check(int(cg_fs.resources[Enums.ResourceType.IRON]) == 310, "AI smelts 40 iron when surplus > 300")
	_check(cg_fs.scavenge_stockpile == scrap_before2 + 20, "AI smelt produces 20 scrap")
	_check(cg_fs.vigilance_target == 50, "AI smelt tick leaves posture target untouched")

	if _fails == 0:
		print("CINDERGUARD REWORK TEST PASSED")
		quit(0)
	else:
		print("CINDERGUARD REWORK TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
