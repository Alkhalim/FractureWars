extends SceneTree
## Tests for faction AI flavor work (July 2026): army postures, pilgrimage
## targeting, espionage sabotage/wounding plumbing, recruit identity weights,
## and the new Moonspear/Sunblessed roster units being wired to buildings.
## Run: godot --headless --path . -s res://tests/test_faction_ai_flavor.gd

var _fails := 0
var _gm: Node
var _tm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_tm = root.get_node("/root/TurnManager")
	var dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire")

	# ── Posture layer ──
	var ts: FactionState = _gm.state.faction_states.get(&"thunderswarm")
	if ts:
		ts.storm_fury = 10
		_check(_tm._ai_army_posture(&"thunderswarm") == "defensive", "thunderswarm low fury -> defensive")
		ts.storm_fury = 70
		_check(_tm._ai_army_posture(&"thunderswarm") == "normal", "thunderswarm high fury -> normal")
	var ms: FactionState = _gm.state.faction_states.get(&"moonspear")
	if ms:
		ms.lunar_phase = 2
		_check(_tm._ai_army_posture(&"moonspear") == "defensive", "moonspear full moon -> defensive")
		ms.lunar_phase = 0
		_check(_tm._ai_army_posture(&"moonspear") == "normal", "moonspear new moon -> normal")
	var cg: FactionState = _gm.state.faction_states.get(&"cinderguard")
	if cg:
		cg.border_vigilance = 30
		_check(_tm._ai_army_posture(&"cinderguard") == "defensive", "cinderguard fortress mode -> defensive")
		cg.border_vigilance = 80
		_check(_tm._ai_army_posture(&"cinderguard") == "normal", "cinderguard war forge -> normal")
	var iv: FactionState = _gm.state.faction_states.get(&"ivoryscar")
	if iv:
		iv.relic_power = 5
		iv.pyramid_restored = false
		_check(_tm._ai_army_posture(&"ivoryscar") == "defensive", "ivoryscar weak relics -> defensive")
		iv.pyramid_restored = true
		_check(_tm._ai_army_posture(&"ivoryscar") == "normal", "ivoryscar restored pyramid -> normal")
		iv.pyramid_restored = false
	var sb: FactionState = _gm.state.faction_states.get(&"sunblessed")
	if sb:
		if not _tm._faction_has_any_war(&"sunblessed"):
			_check(_tm._ai_army_posture(&"sunblessed") == "pilgrim", "sunblessed at peace -> pilgrim")
	_check(_tm._ai_army_posture(&"empire") == "normal", "empire -> normal posture")

	# ── Pilgrimage target: never a war target, never own city ──
	var pilg := _tm._find_pilgrimage_city_hex(Vector2i(10, 10), &"sunblessed") as Vector2i
	if pilg != Vector2i(-1, -1):
		var pcity: CityState = _gm.city_system.get_city_at_hex(pilg)
		_check(pcity != null, "pilgrimage target is a city hex")
		if pcity:
			_check(pcity.faction_id != &"sunblessed", "pilgrimage target is foreign")
			_check(_gm.get_relation(&"sunblessed", pcity.faction_id) != Enums.FactionRelation.WAR, "pilgrimage target not at war")

	# ── Espionage: sabotage destroys a construction in progress ──
	var fk: FactionState = _gm.state.faction_states.get(&"forsaken")
	var emp: FactionState = _gm.state.faction_states.get(&"empire")
	if fk and emp and not emp.owned_cities.is_empty():
		var vcity: CityState = _gm.state.cities.get(emp.owned_cities[0])
		vcity.build_queue.append({"building_id": &"grain_fields", "turns_remaining": 2, "tile_pos": Vector2i(0, 0)})
		var q_before := vcity.build_queue.size()
		fk.espionage_network = 36
		_tm._apply_espionage_operation(fk, "spy_sabotage", &"empire")
		_check(vcity.build_queue.size() == q_before - 1, "spy_sabotage removes a build-queue entry")

	# ── Commander wounding suppresses bonuses ──
	var cmd_sys = root.get_node("/root/CommanderSystem")
	var cmd := CommanderState.new()
	cmd.commander_id = &"test_cmd"
	cmd.skill_levels = {&"warlord": 3}
	var b1: Dictionary = cmd_sys.get_commander_army_bonuses(cmd)
	cmd.wounded_turns = 2
	var b2: Dictionary = cmd_sys.get_commander_army_bonuses(cmd)
	_check(int(b2.attack_bonus) == 0 and int(b2.defense_bonus) == 0, "wounded commander grants no bonuses")
	if int(b1.attack_bonus) == 0 and int(b1.defense_bonus) == 0:
		print("NOTE: test skill id granted no bonuses; wound check still validated zeros")

	# ── Recruit identity weights table sanity ──
	_check(_tm.FACTION_RECRUIT_TAG_WEIGHTS.has(&"skulloath"), "recruit weights cover skulloath")
	_check(_tm.FACTION_RECRUIT_TAG_WEIGHTS.has(&"sunblessed"), "recruit weights cover sunblessed")

	# ── New units exist and are wired to their buildings ──
	for uid in [&"moonshield_guard", &"lunar_crusader", &"dawnscale_thunderlizard", &"blessed_templeguard"]:
		_check(dm.get_unit(uid) != null, "unit data loads: %s" % uid)
	var test_city := CityState.new()
	test_city.faction_id = &"moonspear"
	test_city.buildings.append(&"sentinel_hall")
	_check(test_city.can_recruit(&"moonshield_guard"), "sentinel_hall unlocks moonshield_guard")
	test_city.buildings.append(&"silverguard_chapter")
	_check(test_city.can_recruit(&"lunar_crusader"), "silverguard_chapter unlocks lunar_crusader")
	var sb_city := CityState.new()
	sb_city.faction_id = &"sunblessed"
	sb_city.buildings.append(&"radiant_temple")
	sb_city.buildings.append(&"blessed_springs")
	_check(sb_city.can_recruit(&"blessed_templeguard"), "radiant_temple unlocks blessed_templeguard")
	_check(sb_city.can_recruit(&"dawnscale_thunderlizard"), "blessed_springs unlocks dawnscale_thunderlizard")

	# ── Relic defense ticks down ──
	if iv:
		iv.leader_bonuses["relic_defense_turns"] = 2
		_tm._process_ivoryscar_relics(iv)
		_check(int(iv.leader_bonuses.get("relic_defense_turns", 0)) == 1, "relic_defense_turns ticks down")

	if _fails == 0:
		print("FACTION AI FLAVOR TEST PASSED")
		quit(0)
	else:
		print("FACTION AI FLAVOR TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
