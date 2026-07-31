extends SceneTree
## Temp tool (Task 2, Settlement Building Partition verification): runs a
## full AI-vs-AI game headlessly, identical seeding/observer-mode/fast-forward
## pattern to tests/tmp_econ_sim.gd, and at the target turn dumps every
## AI-owned settlement's city.buildings (id + settlement_only/settlement_allowed/
## requires_region_resource/requires_region_landmark flags) instead of a
## per-round CSV. Answers "what do AI settlements actually build under the
## partition?" Delete after use.
##   godot --headless --path . -s res://tests/tmp_settlement_sample.gd -- <seed> <turns>

const DEFAULT_TURNS := 40

var _gm: Node
var _tm: Node
var _dm: Node
var _eb: Node
var _turns := DEFAULT_TURNS
var _seed := 1
var _dumped := false

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
	_gm.state.player_faction_id = &"__observer__"
	_tm.skip_ai_turn = true
	_tm.start_game()

func _dump_settlements() -> void:
	print("=== TOTAL BUILDINGS/UNITS SUMMARY @ turn ", _gm.state.current_turn, " (seed ", _seed, ") — Task-D-comparable ===")
	for fid in _gm.state.faction_states:
		var fs0 = _gm.state.faction_states[fid]
		if _gm.MINOR_FACTION_PARENTS.has(fid):
			continue
		var total_buildings := 0
		for cid0 in fs0.owned_cities:
			var c0 = _gm.state.cities.get(cid0)
			if c0:
				total_buildings += c0.buildings.size()
		var total_units := 0
		for aid in _gm.state.armies:
			var a = _gm.state.armies[aid]
			if a.faction_id == fid and not a.is_garrison:
				total_units += a.units.size()
		print("  ", fid, ": buildings=", total_buildings, " units=", total_units)

	print("=== RESOURCE_LEASE TREATIES @ turn ", _gm.state.current_turn, " (seed ", _seed, ") ===")
	var any_lease := false
	for t_id in _gm.state.diplomacy_state.treaties:
		var t = _gm.state.diplomacy_state.treaties[t_id]
		if t.treaty_type == Enums.TreatyType.RESOURCE_LEASE:
			any_lease = true
			print("  lease: ", t.faction_a, " -> ", t.faction_b, " special=", t.terms.get("special_id", &""), " turns_remaining=", t.turns_remaining)
	if not any_lease:
		print("  (no RESOURCE_LEASE treaties active)")

	print("=== SETTLEMENT BUILDING SAMPLE @ turn ", _gm.state.current_turn, " (seed ", _seed, ") ===")
	var any_settlement := false
	for fid in _gm.state.faction_states:
		var fs = _gm.state.faction_states[fid]
		if _gm.MINOR_FACTION_PARENTS.has(fid):
			continue
		for cid in fs.owned_cities:
			var c = _gm.state.cities.get(cid)
			if c == null or not c.is_settlement or c.is_mobile_camp:
				continue
			any_settlement = true
			print("--- ", fid, " settlement ", cid, " level=", c.level, " region=", c.region_id, " ---")
			for bid in c.buildings:
				var bd = _dm.get_building(bid)
				if bd == null:
					print("    ", bid, " (no BuildingData found)")
					continue
				var tags: Array[String] = []
				if bd.settlement_only:
					tags.append("settlement_only")
				if bd.settlement_allowed:
					tags.append("settlement_allowed")
				if bd.requires_region_resource != &"":
					tags.append("extractor:" + str(bd.requires_region_resource))
				if bd.requires_region_landmark != &"":
					tags.append("landmark:" + str(bd.requires_region_landmark))
				if tags.is_empty():
					tags.append("UNTAGGED-city-building")
				print("    ", bid, "  [", ", ".join(tags), "]")
	if not any_settlement:
		print("(no AI-owned settlements exist at this turn)")
	print("=== END SAMPLE ===")

func _process(_delta: float) -> bool:
	if _gm == null or _gm.state == null:
		return false
	var turn: int = _gm.state.current_turn
	if turn > _turns:
		if not _dumped:
			_dumped = true
			_dump_settlements()
		quit()
		return false
	if _tm.is_player_turn:
		_eb.end_turn_pressed.emit()
	return false
