extends SceneTree
## Temp tool: measures every unit's REAL combat output in the battle simulator
## (not the HUD's estimate) by fighting each one against a fixed reference
## opponent, then prints a CSV. Delete after use.
##   godot --headless --path . -s res://tests/tmp_unit_audit.gd > audit.csv

const REF_UNIT := &"legionary"   # fixed sparring partner for every measurement
const TICKS := 900

var _gm: Node
var _dm: Node

func _init() -> void:
	call_deferred("_run")

func _make_army(uid: StringName, aid: StringName, fid: StringName) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = aid
	army.faction_id = fid
	army.hex_pos = Vector2i(10, 10)
	var ud: UnitData = _dm.get_unit(uid)
	if ud == null:
		return army
	var inst := UnitInstance.new()
	inst.init_from_data(ud, StringName("%s_u0" % aid))
	army.units.append(inst)
	return army

func _measure(uid: StringName) -> Dictionary:
	var ud: UnitData = _dm.get_unit(uid)
	if ud == null:
		return {}
	seed(90210)
	var sim = load("res://scripts/systems/battle/battle_simulator_v3.gd").new()
	sim.setup_terrain(Enums.TerrainType.PLAINS, Vector2i(10, 10))
	sim.setup_attacker_formations(_make_army(uid, &"a", ud.faction_id))
	sim.setup_defender_formations(_make_army(REF_UNIT, &"d", &"empire"))
	if sim.attacker_formations.is_empty() or sim.defender_formations.is_empty():
		return {}
	var atk = sim.attacker_formations[0]
	var def = sim.defender_formations[0]
	# Realistic engagement: they start at deployment distance and advance, so
	# archers and mages get their volleys off before contact
	for t in TICKS:
		sim.simulate_tick()
		if sim.is_finished:
			break
	# damage_dealt = offense against a standard target
	# hp lost by the reference = same thing; hp the unit kept = defensive value
	var hp_frac: float = float(maxi(atk.current_hp, 0)) / float(maxi(atk.max_hp, 1))
	return {
		"dmg": atk.damage_dealt,
		"taken": def.damage_dealt,     # damage the reference dealt back to it
		"hp_left_pct": int(hp_frac * 100.0),
		"alive": 0 if atk.is_dead else 1,
	}

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)
	print("faction,unit,role,squad,attack,hp,mdef,speed,cost,gold,sim_damage,sim_taken,hp_left_pct,survived")
	for uid in _dm.units:
		var ud: UnitData = _dm.units[uid]
		var r := _measure(uid)
		if r.is_empty():
			continue
		var role := "infantry"
		if ud.tags.has("mage"):
			role = "mage"
		elif ud.tags.has("monster") or ud.tags.has("beast"):
			role = "monster"
		elif ud.tags.has("cavalry"):
			role = "cavalry"
		elif ud.tags.has("ranged"):
			role = "ranged"
		var cost := 0
		var gold := 0
		for k in ud.recruit_cost:
			cost += int(ud.recruit_cost[k])
			if int(k) == 0:
				gold = int(ud.recruit_cost[k])
		print("%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			ud.faction_id, uid, role, ud.squad_size, ud.attack, ud.max_hp,
			ud.melee_defense, ud.speed, cost, gold,
			r.dmg, r.taken, r.hp_left_pct, r.alive])
	quit()
