extends SceneTree
## Temp tool: runs full AI-vs-AI games headlessly and logs every faction's
## economy each round, so we can see who snowballs, who death-spirals, and
## which strategies actually pay. Prints CSV. Delete after use.
##   godot --headless --path . -s res://tests/tmp_econ_sim.gd -- <seed> <turns>

const DEFAULT_TURNS := 70

var _gm: Node
var _tm: Node
var _dm: Node
var _eb: Node
var _turns := DEFAULT_TURNS
var _seed := 1
var _done := false
var _last_logged := -1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_seed = int(args[0])
	if args.size() >= 2:
		_turns = int(args[1])
	seed(_seed)
	_gm = root.get_node("/root/GameManager")
	_tm = root.get_node("/root/TurnManager")
	_dm = root.get_node("/root/DataManager")
	_eb = root.get_node("/root/EventBus")
	_gm._is_transitioning = true
	_gm.new_game(&"empire", false, _seed)
	_gm._is_transitioning = false
	# No human: every faction is played by the AI, so each turn self-advances
	_gm.state.player_faction_id = &"__observer__"
	# Fast-forward: skip the UI-responsiveness yields (headless has no UI)
	_tm.skip_ai_turn = true
	print("seed,turn,faction,gold,food,iron,wood,tech,cities,settlements,armies,units,pop,upkeep_gold,income_gold,net_gold,avg_loyalty,defeated,iron_income,wood_income,vigilance,vigilance_target,scrap,pumps")
	_tm.start_game()

func _log_round() -> void:
	var turn: int = _gm.state.current_turn
	for fid in _gm.state.faction_states:
		var fs = _gm.state.faction_states[fid]
		if _gm.MINOR_FACTION_PARENTS.has(fid):
			continue  # majors only, keeps the CSV readable
		var cities := 0
		var settlements := 0
		var pop := 0
		var loy_sum := 0.0
		var loy_n := 0
		var upkeep := 0
		for cid in fs.owned_cities:
			var c = _gm.state.cities.get(cid)
			if c == null:
				continue
			if c.is_settlement:
				settlements += 1
			else:
				cities += 1
			pop += c.population
			for cls in c.class_loyalty:
				loy_sum += float(c.class_loyalty[cls])
				loy_n += 1
			# Building upkeep (gold) -- was missing entirely, so this column
			# understated the true drain and made faction economies look
			# healthier than they actually are. See _deduct_upkeep's building
			# loop in city_system.gd for the real deduction this mirrors.
			for bid in c.buildings:
				var bld = _dm.get_building(bid)
				if bld:
					upkeep += int(_gm.city_system.get_building_upkeep(bld).get(0, 0))
		var armies := 0
		var units := 0
		for aid in _gm.state.armies:
			var a = _gm.state.armies[aid]
			if a.faction_id != fid or a.is_garrison:
				continue
			armies += 1
			units += a.units.size()
			for u in a.units:
				var ud = _dm.get_unit(u.unit_data_id)
				if ud:
					upkeep += int(ud.upkeep_cost.get(0, 0))
		var income := 0
		var iron_income := 0
		var wood_income := 0
		var pump_ids: Array[StringName] = [&"ember_foundry", &"volcanic_smelter", &"cinder_mine", &"magma_vent", &"molten_core_forge"]
		var pumps_owned: Array[String] = []
		for cid in fs.owned_cities:
			var c2 = _gm.state.cities.get(cid)
			if c2:
				var inc = _gm.city_system.calculate_city_income(c2)
				income += int(inc.get(0, 0))
				iron_income += int(inc.get(1, 0))
				wood_income += int(inc.get(5, 0))
				for pid in pump_ids:
					if c2.buildings.has(pid):
						pumps_owned.append(str(pid))
		var vigilance: int = fs.border_vigilance if fid == &"cinderguard" else -1
		var vigilance_target: int = fs.vigilance_target if fid == &"cinderguard" else -1
		var scrap: int = fs.scavenge_stockpile if fid == &"cinderguard" else -1
		var pumps_str := ";".join(pumps_owned)
		print("%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.1f,%d,%d,%d,%d,%d,%d,%s" % [
			_seed, turn, fid,
			int(fs.resources.get(0, 0)), int(fs.resources.get(3, 0)), int(fs.resources.get(1, 0)),
			int(fs.resources.get(5, 0)), int(fs.resources.get(2, 0)),
			cities, settlements, armies, units, pop,
			upkeep, income, income - upkeep,
			(loy_sum / maxf(loy_n, 1)), (1 if fs.is_defeated else 0),
			iron_income, wood_income, vigilance, vigilance_target, scrap, pumps_str])

## Task 6 (bounty-gated-techs, AI settlement scoring): summary of how many
## bounty-gated techs each major faction actually finished by game end --
## the thing the CSV columns can't show (TECHNOLOGY stockpile is a scalar,
## not a per-tech breakdown). Printed once at quit() time, not per-round.
func _log_gated_tech_completions() -> void:
	var gated_ids: Array[StringName] = []
	for research_id in _dm.research:
		var d: ResearchData = _dm.research[research_id]
		if not d.requires_bounty_types.is_empty():
			gated_ids.append(research_id)
	print("# gated_tech_summary: %d gated techs in data" % gated_ids.size())
	var total := 0
	for fid in _gm.state.faction_states:
		if _gm.MINOR_FACTION_PARENTS.has(fid):
			continue
		var fs = _gm.state.faction_states[fid]
		var done: Array[StringName] = []
		for rid in gated_ids:
			if fs.completed_research.has(rid):
				done.append(rid)
		total += done.size()
		print("# gated_tech_summary,%s,%d,%s" % [fid, done.size(), ";".join(done)])
		# Diagnostics: is this faction's research pipeline stalled at all (not
		# just for gated techs), and how many gated techs are it currently
		# blocked on only by the bounty gate.
		var avail: Array = _gm.research_system.get_available_research(fid)
		var locked: Array = _gm.research_system.get_bounty_locked_research(fid)
		print("# research_diag,%s,completed=%d,current=%s,tech_bank=%d,available=%d,bounty_locked=%d" % [
			fid, fs.completed_research.size(), str(fs.current_research_id),
			int(fs.resources.get(2, 0)), avail.size(), locked.size()])
	print("# gated_tech_summary_total,%d" % total)

func _process(_delta: float) -> bool:
	if _gm == null or _gm.state == null:
		return false
	var turn: int = _gm.state.current_turn
	if turn != _last_logged and _tm.current_faction_index == 0:
		_last_logged = turn
		_log_round()
	if turn > _turns:
		_log_gated_tech_completions()
		quit()
		return false
	# The observer faction sits at faction_order[0] and is treated as a PLAYER
	# turn, so the turn cycle waits for an end-turn that no human will send.
	# Pump it here so the all-AI game actually advances.
	if _tm.is_player_turn:
		_eb.end_turn_pressed.emit()
	return false
