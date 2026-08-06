extends SceneTree
## Temp tool (Task R2 review, IMPORTANT item): grid-search the strength-meter
## power-estimate constants at the NEW (post-rescale) scale. Reuses the exact
## 10 matchups from tests/test_strength_meter_probe.gd. Runs each matchup's
## REAL auto_resolve ONCE to get ground truth (actual winner) and snapshots
## each unit's pre-battle stats, then searches parameter space OFFLINE
## (no more battle re-runs -- combat outcome doesn't depend on meter
## constants) so a few hundred candidate combinations run in seconds.
## Delete after use.
##   godot --headless --path . -s res://tests/tmp_meter_grid_search.gd

var _gm: Node
var _dm: Node
var _battle_resolver: Node

const SEED_BASE := 918273

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_battle_resolver = root.get_node("/root/BattleResolver")
	_gm.new_game(&"empire", false, 0)

	var hex := _find_empty_hex()
	var matchups := _matchups()

	# ── Phase 1: capture ground truth + pre-battle stat snapshots (once) ──
	var cases: Array[Dictionary] = []
	for i in matchups.size():
		var m: Dictionary = matchups[i]
		seed(SEED_BASE + i)
		var atk_id := StringName("grid_atk_%d" % i)
		var def_id := StringName("grid_def_%d" % i)
		var atk_army := _build_army(atk_id, m["a"], hex)
		var def_army := _build_army(def_id, m["b"], hex)
		_gm.state.armies[atk_id] = atk_army
		_gm.state.armies[def_id] = def_army

		var atk_units := _snapshot_units(atk_army)
		var def_units := _snapshot_units(def_army)

		_battle_resolver.auto_resolve(atk_id, def_id, hex)

		var atk_survived: bool = _gm.state.armies.has(atk_id)
		var def_survived: bool = _gm.state.armies.has(def_id)
		var decisive: bool = atk_survived != def_survived
		var actual_atk_won: bool = atk_survived and not def_survived

		cases.append({
			"name": m["name"], "atk_units": atk_units, "def_units": def_units,
			"decisive": decisive, "actual_atk_won": actual_atk_won,
		})

		_gm.state.armies.erase(atk_id)
		_gm.state.armies.erase(def_id)

	# ── Phase 2: grid search ──
	var def_w_grid := [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0]
	var ent_melee_grid := [0.6, 0.7, 0.8, 0.9, 1.0]
	var ent_ranged_grid := [0.8, 0.9, 1.0, 1.1, 1.2]
	var toughness_exp_grid := [0.5, 0.7, 1.0] # sqrt, mild, linear

	var best_score := -1
	var best_params: Array = []
	var best_ties: Array = []
	var total_tested := 0

	for def_w in def_w_grid:
		for ent_m in ent_melee_grid:
			for ent_r in ent_ranged_grid:
				for tough_exp in toughness_exp_grid:
					total_tested += 1
					var score := _score_params(cases, def_w, ent_m, ent_r, tough_exp)
					if score > best_score:
						best_score = score
						best_params = [def_w, ent_m, ent_r, tough_exp]
						best_ties = [[def_w, ent_m, ent_r, tough_exp]]
					elif score == best_score:
						best_ties.append([def_w, ent_m, ent_r, tough_exp])

	print("Tested %d parameter combinations." % total_tested)
	print("Current shipped params (def_w=0.5, ent_melee=0.8, ent_ranged=1.0, toughness_exp=1.0) score: %d/10" % _score_params(cases, 0.5, 0.8, 1.0, 1.0))
	print("BEST score: %d/10, %d tied combination(s), first few:" % [best_score, best_ties.size()])
	for t in best_ties.slice(0, 10):
		print("  def_w=%.2f ent_melee=%.2f ent_ranged=%.2f toughness_exp=%.2f" % [t[0], t[1], t[2], t[3]])

	# Print per-case detail for the FIRST best combo so we can see which
	# case(s) still miss even at the best-found frontier.
	if not best_params.is_empty():
		print("--- Detail for first best combo ---")
		_score_params(cases, best_params[0], best_params[1], best_params[2], best_params[3], true)

	quit(0)

func _score_params(cases: Array[Dictionary], def_w: float, ent_melee: float, ent_ranged: float, tough_exp: float, verbose: bool = false) -> int:
	var pass_count := 0
	for c: Dictionary in cases:
		var atk_power := _power(c["atk_units"], def_w, ent_melee, ent_ranged, tough_exp)
		var def_power := _power(c["def_units"], def_w, ent_melee, ent_ranged, tough_exp)
		var meter_predicts_atk: bool = atk_power > def_power
		var meter_tie: bool = is_equal_approx(atk_power, def_power)
		var matched: bool = c["decisive"] and not meter_tie and (meter_predicts_atk == c["actual_atk_won"])
		if matched:
			pass_count += 1
		if verbose:
			var outcome := "N/A (stalemate)" if not c["decisive"] else ("ATK won" if c["actual_atk_won"] else "DEF won")
			print("[%s] meter=%s (atk %.0f vs def %.0f) actual=%s -> %s" % [
				c["name"], ("ATK" if meter_predicts_atk else "DEF"), atk_power, def_power, outcome,
				("MATCH" if matched else "MISS"),
			])
	return pass_count

func _power(units: Array, def_w: float, ent_melee: float, ent_ranged: float, tough_exp: float) -> float:
	var power := 0.0
	for u: Dictionary in units:
		var hp_ratio: float = u["hp_ratio"]
		var stat_value: float = float(u["attack"]) + float(u["melee_defense"]) * def_w + float(u["speed"]) * 0.03
		if u["attack_range"] > 1:
			stat_value += float(u["attack_range"]) * 0.04
		var toughness := maxf(1.0, pow(float(u["hp_per_entity"]), tough_exp))
		var entities_exp: float = ent_ranged if u["attack_range"] > 1 else ent_melee
		var effective_count := pow(float(maxi(1, u["squad_size"])), entities_exp)
		power += hp_ratio * stat_value * effective_count * toughness
	return power

func _snapshot_units(army: ArmyState) -> Array:
	var out: Array = []
	for u in army.units:
		var ud: UnitData = _dm.get_unit(u.unit_data_id)
		if ud == null or ud.max_hp <= 0:
			continue
		var hp_per_entity := float(ud.hp_per_soldier) if ud.hp_per_soldier > 0 and ud.squad_size > 1 else float(ud.max_hp)
		out.append({
			"attack": ud.attack, "melee_defense": ud.melee_defense, "speed": ud.speed,
			"attack_range": ud.attack_range, "squad_size": ud.squad_size,
			"hp_per_entity": hp_per_entity,
			"hp_ratio": clampf(float(u.current_hp) / float(ud.max_hp), 0.0, 1.0),
		})
	return out

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
			push_error("tmp_meter_grid_search: missing unit data %s" % uid)
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
	for coord in _gm.state.hex_map.tiles:
		var tile = _gm.state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if _gm.city_system.get_city_at_hex(coord) != null:
			continue
		return coord
	return Vector2i(10, 10)

## Identical to test_strength_meter_probe.gd's matchup table (kept in sync
## deliberately -- this tool searches parameters for THAT test's pass bar).
func _matchups() -> Array[Dictionary]:
	return [
		{"name": "tanky_solo_vs_glass_ranged", "a": [{"id": &"war_ballista", "n": 1}], "b": [{"id": &"root_sentinel", "n": 1}]},
		{"name": "mammoth_vs_lone_wolfpack", "a": [{"id": &"guardian_wolf", "n": 1}], "b": [{"id": &"guardian_mammoth", "n": 1}]},
		{"name": "tanky_solo_vs_monster_pack", "a": [{"id": &"dragon_hatchling", "n": 1}], "b": [{"id": &"marching_bastion", "n": 1}]},
		{"name": "war_yak_vs_frost_mage", "a": [{"id": &"frost_mage", "n": 1}], "b": [{"id": &"war_yak", "n": 1}]},
		{"name": "close_offense_brutes_vs_cavalry", "a": [{"id": &"glade_cavalry", "n": 1}], "b": [{"id": &"rebel_brutes", "n": 1}]},
		{"name": "close_offense_lancer_vs_valkyrie", "a": [{"id": &"sylvan_lancer", "n": 1}], "b": [{"id": &"valkyrie", "n": 1}]},
		{"name": "monster_vs_jaguar_pack", "a": [{"id": &"guardian_jaguar", "n": 1}], "b": [{"id": &"dragon_hatchling", "n": 1}]},
		{"name": "gladehost_sentinel_vs_cavalry_swarm", "a": [{"id": &"glade_cavalry", "n": 3}], "b": [{"id": &"root_sentinel", "n": 2}]},
		{"name": "guardian_mammoth_vs_wolfpack", "a": [{"id": &"guardian_wolf", "n": 4}], "b": [{"id": &"guardian_mammoth", "n": 1}]},
		{"name": "storm_caller_kite_vs_valkyrie_rush", "a": [{"id": &"storm_caller", "n": 2}], "b": [{"id": &"valkyrie", "n": 2}]},
	]
