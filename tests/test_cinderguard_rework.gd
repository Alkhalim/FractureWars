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
