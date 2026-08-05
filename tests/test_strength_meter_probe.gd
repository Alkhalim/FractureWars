extends SceneTree
## UI Polish Wave 2, Task W4: strength-meter accuracy probe.
##
## Designer report: "I had a fight with better units and more of them but it
## still showed an advantage for my enemies. They had more hp on their
## units — might that be the reason?" Root cause: the shared power formula
## (campaign.gd's _calc_army_power_estimate, mirrored by battle_v3.gd's
## _calc_formation_power) weighs attack/defense/speed x headcount but never
## weighs max_hp/hp_per_soldier — hp_ratio (current/max) cancels the HP
## magnitude out entirely, so a unit with 10x the effective HP of another
## scores identically at full health.
##
## This probe builds REAL rosters (no synthetic UnitData — every unit here
## is loaded straight off DataManager, same data the live game uses) across
## 10 varied matchups (tanky-solo, ranged-kite, monster-stack, close-call
## same-faction pairs with comparable raw offense but divergent HP-per-
## soldier), computes the pre-battle meter's predicted winner via
## campaign.gd's REAL _calc_army_power_estimate() (loaded fresh, called
## directly — no reimplementation here to drift out of sync), then drives
## the REAL auto-resolver (BattleResolver.auto_resolve(), the exact function
## the in-game "Auto" button and all AI-vs-AI battles call) and compares.
##
## The meter is DISPLAY-ONLY: this probe drives the real simulator for the
## ground-truth winner, but the meter call itself never touches sim state
## (_calc_army_power_estimate only reads army.units + DataManager).
##
## Pass bar: meter direction must match the auto-resolve winner in >= 9/10
## matchups (stalemates/mutual-kills, if any, count as a miss since the
## meter can't express "draw").
##
## Run: godot --headless --path . -s res://tests/test_strength_meter_probe.gd

var _gm: Node
var _dm: Node
var _battle_resolver: Node
var _campaign_script: Node

const SEED_BASE := 918273

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_battle_resolver = root.get_node("/root/BattleResolver")
	_gm.new_game(&"empire", false, 0)

	# campaign.gd is a scene-attached script (Node2D) with autoload-dependent
	# class-level references; it only compiles once autoloads have been
	# warmed by a real new_game() call (see godot-test-harness memory notes /
	# tests/test_income_breakdown_equivalence.gd:111 for the same pattern).
	_campaign_script = (load("res://scenes/campaign/campaign.gd") as GDScript).new()

	var hex := _find_empty_hex()

	# Each entry: name, side_a (attacker) unit specs, side_b (defender) unit
	# specs. Every unit id is real DataManager data — counts are how many
	# separate UnitInstance "squads" of that type go into the army (each
	# instance already carries its own squad_size/hp_per_soldier headcount).
	# Factions were chosen to avoid the 8 factions whose _create_formation()
	# combat bonus depends on a battle-mutable faction-mechanic value
	# (skulloath/tainted_jade/shardhorde/moonspear/thunderswarm/cinderguard/
	# ivoryscar/sunblessed) so repeated matchups can't drift the odds via
	# feedback (thunderswarm storm_fury / sunblessed solar_faith are both
	# nudged by auto_resolve() itself).
	# Combined headcount kept roughly <=130: an early draft using large single
	# squads (200-450 combined entities) mostly timed out at max_ticks with
	# both sides still standing (a "stalemate" the meter can't be scored
	# against, since it can't express "draw") -- contact caps mean a huge
	# horde can't concentrate enough simultaneous attackers to finish a huge
	# HP pool within the tick budget, and vice versa. Shrinking to
	# small-to-mid squads lets fights actually resolve.
	var matchups: Array[Dictionary] = [
		{
			"name": "tanky_solo_vs_glass_ranged",
			"a": [{"id": &"war_ballista", "n": 1}],
			"b": [{"id": &"root_sentinel", "n": 1}],
		},
		{
			"name": "mammoth_vs_lone_wolfpack",
			"a": [{"id": &"guardian_wolf", "n": 1}],
			"b": [{"id": &"guardian_mammoth", "n": 1}],
		},
		{
			"name": "tanky_solo_vs_monster_pack",
			"a": [{"id": &"dragon_hatchling", "n": 1}],
			"b": [{"id": &"marching_bastion", "n": 1}],
		},
		{
			"name": "war_yak_vs_frost_mage",
			"a": [{"id": &"frost_mage", "n": 1}],
			"b": [{"id": &"war_yak", "n": 1}],
		},
		{
			"name": "close_offense_brutes_vs_cavalry",
			"a": [{"id": &"glade_cavalry", "n": 1}],
			"b": [{"id": &"rebel_brutes", "n": 1}],
		},
		{
			"name": "close_offense_lancer_vs_valkyrie",
			"a": [{"id": &"sylvan_lancer", "n": 1}],
			"b": [{"id": &"valkyrie", "n": 1}],
		},
		{
			"name": "monster_vs_jaguar_pack",
			"a": [{"id": &"guardian_jaguar", "n": 1}],
			"b": [{"id": &"dragon_hatchling", "n": 1}],
		},
		{
			"name": "gladehost_sentinel_vs_cavalry_swarm",
			"a": [{"id": &"glade_cavalry", "n": 3}],
			"b": [{"id": &"root_sentinel", "n": 2}],
		},
		{
			"name": "guardian_mammoth_vs_wolfpack",
			"a": [{"id": &"guardian_wolf", "n": 4}],
			"b": [{"id": &"guardian_mammoth", "n": 1}],
		},
		{
			"name": "storm_caller_kite_vs_valkyrie_rush",
			"a": [{"id": &"storm_caller", "n": 2}],
			"b": [{"id": &"valkyrie", "n": 2}],
		},
	]

	var pass_count := 0
	var results: Array[String] = []
	for i in matchups.size():
		var m: Dictionary = matchups[i]
		seed(SEED_BASE + i)
		var atk_id := StringName("probe_atk_%d" % i)
		var def_id := StringName("probe_def_%d" % i)
		var atk_army := _build_army(atk_id, m["a"], hex)
		var def_army := _build_army(def_id, m["b"], hex)
		_gm.state.armies[atk_id] = atk_army
		_gm.state.armies[def_id] = def_army

		var atk_power: float = _campaign_script._calc_army_power_estimate(atk_army)
		var def_power: float = _campaign_script._calc_army_power_estimate(def_army)
		var meter_predicts_atk: bool = atk_power > def_power
		var meter_tie: bool = is_equal_approx(atk_power, def_power)

		_battle_resolver.auto_resolve(atk_id, def_id, hex)

		var atk_survived: bool = _gm.state.armies.has(atk_id)
		var def_survived: bool = _gm.state.armies.has(def_id)
		var decisive: bool = atk_survived != def_survived
		var actual_atk_won: bool = atk_survived and not def_survived

		var matched: bool = decisive and not meter_tie and (meter_predicts_atk == actual_atk_won)
		if matched:
			pass_count += 1

		var outcome_str: String
		if not decisive:
			outcome_str = "DRAW/STALEMATE (atk_alive=%s def_alive=%s)" % [atk_survived, def_survived]
		else:
			outcome_str = "ATK won" if actual_atk_won else "DEF won"
		results.append("[%s] meter=%s (atk %.0f vs def %.0f, atk_ratio=%.2f) actual=%s -> %s" % [
			m["name"], ("ATK" if meter_predicts_atk else "DEF"), atk_power, def_power,
			(atk_power / maxf(1.0, atk_power + def_power)), outcome_str,
			("MATCH" if matched else "MISS"),
		])

		# Clean up so the next matchup starts fresh at the same hex.
		_gm.state.armies.erase(atk_id)
		_gm.state.armies.erase(def_id)

	print("--- Strength Meter Probe Results ---")
	for line in results:
		print(line)
	print("SCORE: %d/%d" % [pass_count, matchups.size()])

	_campaign_script.free()

	var required := ceili(matchups.size() * 0.9)
	if pass_count >= required:
		print("STRENGTH METER PROBE PASSED")
		quit(0)
	else:
		print("STRENGTH METER PROBE FAILED (%d/%d, need >= %d)" % [pass_count, matchups.size(), required])
		quit(1)

func _build_army(id: StringName, specs: Array, hex: Vector2i) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = id
	army.hex_pos = hex
	var n := 0
	var faction_id: StringName = &""
	for spec: Dictionary in specs:
		var uid: StringName = spec["id"]
		var count: int = spec["n"]
		var ud: UnitData = _dm.get_unit(uid)
		if ud == null:
			push_error("test_strength_meter_probe: missing unit data %s" % uid)
			continue
		faction_id = ud.faction_id
		for c in count:
			var inst := UnitInstance.new()
			inst.init_from_data(ud, StringName("%s_u%d" % [id, n]))
			army.units.append(inst)
			n += 1
	army.faction_id = faction_id
	return army

func _find_empty_hex() -> Vector2i:
	## Any land tile with no city on it — armies just need somewhere to
	## stand; picking a cityless tile keeps auto_resolve's siege/garrison
	## branches inert so every matchup is a clean field battle.
	for coord in _gm.state.hex_map.tiles:
		var tile = _gm.state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if _gm.city_system.get_city_at_hex(coord) != null:
			continue
		return coord
	return Vector2i(10, 10)
