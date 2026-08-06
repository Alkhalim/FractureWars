extends SceneTree
## Task R1 (Unit Stat Rescale): A/B parity harness.
##
## The designer is dividing every combat-scale unit number by 10 (attack
## 70→7, max_hp 3750→375). That touches formulas (int() truncation of
## percentage bonuses at a smaller base, min-1 damage/attrition floors
## becoming relatively harsher, flat bonuses like vs_attack_bonuses becoming
## relatively stronger) as well as data, so a straight "does the game still
## play the same" check is needed before and after. This harness drives 20
## pinned, deterministic matchups through the REAL BattleResolver.auto_resolve
## (scripts/systems/battle/battle_resolver.gd -- the exact function AI-vs-AI
## and the in-game "Auto" button call; it internally runs BattleSimulatorV2,
## NOT V3 -- see the R1 report for why that matters: several flat combat
## bonuses this rescale must touch, e.g. vs_attack_bonuses, siege_bonus,
## flying_unit_attack_bonus, thunder wall +8, relic defense +3, and the whole
## sub-faction identity-modifier block, live ONLY in V3's _create_formation
## and are never read by V2, so they don't affect this A/B's outcomes even
## though they're inventoried and rescale-classified in the report).
##
## CAPTURE mode runs the matchups and writes winner + per-side casualty
## fraction (1 - post-battle HP / pre-battle HP) for each to the baseline
## JSON. COMPARE mode (used by Task R2, after the ÷10 data + formula changes
## land) re-runs the same matchups and reports winner agreement and mean
## casualty-fraction delta against that baseline. Balance-parity bar (task
## brief): winner agreement >= 18/20 AND mean casualty-fraction delta <= 10%.
##
## Army/matchup construction is modeled on tests/test_strength_meter_probe.gd
## (real DataManager units, no synthetic UnitData, StringName army ids built
## per-matchup, single reusable cityless hex, per-matchup RNG reseed via
## `seed(SEED_BASE + i)`, erase-both-army-ids cleanup after each matchup).
##
## Run:
##   Capture (current scale, THIS task):
##     godot --headless --path . -s res://tests/test_rescale_parity.gd -- --capture
##   Compare (after a rescale lands, Task R2):
##     godot --headless --path . -s res://tests/test_rescale_parity.gd

const BASELINE_DIR := "res://tests/baselines"
const BASELINE_PATH := BASELINE_DIR + "/rescale_ab_baseline.json"
const SEED_BASE := 2608061 # arbitrary fixed seed, unrelated to any other test's seed

const WINNER_AGREEMENT_BAR := 18 # out of 20, per task brief's balance-parity bar
const CASUALTY_DELTA_BAR := 0.10 # mean |delta| across all matchups/sides, per task brief

var _gm: Node
var _dm: Node
var _battle_resolver: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_battle_resolver = root.get_node("/root/BattleResolver")
	_gm.new_game(&"empire", false, 0)

	var hex := _find_empty_hex()
	var matchups := _build_matchups()
	var results: Array[Dictionary] = []

	for i in matchups.size():
		var m: Dictionary = matchups[i]
		seed(SEED_BASE + i)
		var atk_id := StringName("rescale_atk_%d" % i)
		var def_id := StringName("rescale_def_%d" % i)
		var atk_army := _build_army(atk_id, m["a"], hex, false)
		var def_army := _build_army(def_id, m["b"], hex, m.get("garrison", false))
		_gm.state.armies[atk_id] = atk_army
		_gm.state.armies[def_id] = def_army

		var atk_pre := atk_army.get_total_strength()
		var def_pre := def_army.get_total_strength()

		_battle_resolver.auto_resolve(atk_id, def_id, hex)

		# Read post-battle strength off our own held ArmyState references, not
		# state.armies -- auto_resolve calls GameManager.remove_army() on the
		# loser (dropping it from state.armies entirely), but the object we
		# still hold has its `.units` already trimmed to survivors with
		# updated current_hp by _apply_auto_battle_results, so this is accurate
		# for both winner and loser.
		var atk_post := atk_army.get_total_strength()
		var def_post := def_army.get_total_strength()
		var atk_survived: bool = _gm.state.armies.has(atk_id)
		var def_survived: bool = _gm.state.armies.has(def_id)

		results.append({
			"name": m["name"],
			"category": m["category"],
			"winner": _classify_winner(atk_survived, def_survived),
			"atk_pre_strength": atk_pre,
			"def_pre_strength": def_pre,
			"atk_post_strength": atk_post,
			"def_post_strength": def_post,
			"atk_casualty_frac": _casualty_frac(atk_pre, atk_post),
			"def_casualty_frac": _casualty_frac(def_pre, def_post),
		})

		# Clean up so the next matchup starts fresh at the same hex (mirrors
		# test_strength_meter_probe.gd; erase() is a harmless no-op for
		# whichever id auto_resolve already removed via GameManager.remove_army).
		_gm.state.armies.erase(atk_id)
		_gm.state.armies.erase(def_id)

	var capture_mode := "--capture" in OS.get_cmdline_user_args()
	if capture_mode:
		_run_capture(results)
	else:
		_run_compare(results)

# ── Modes ───────────────────────────────────────────────────────

func _run_capture(results: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE_DIR))
	var payload := {
		"schema": 1,
		"seed_base": SEED_BASE,
		"matchup_count": results.size(),
		"results": results,
	}
	var f := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
	if f == null:
		printerr("Could not open %s for writing" % BASELINE_PATH)
		quit(1)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	var winner_counts := {}
	for r in results:
		var w: String = r["winner"]
		winner_counts[w] = winner_counts.get(w, 0) + 1
	print("--- Rescale A/B Baseline CAPTURE ---")
	for r in results:
		print("[%s/%s] winner=%s atk_cas=%.2f def_cas=%.2f" % [
			r["category"], r["name"], r["winner"], r["atk_casualty_frac"], r["def_casualty_frac"],
		])
	print("Winner distribution: %s" % [winner_counts])
	print("BASELINE WRITTEN: %s (%d matchups)" % [BASELINE_PATH, results.size()])
	quit(0)

func _run_compare(results: Array[Dictionary]) -> void:
	var f := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f == null:
		print("MISSING BASELINE -- run with -- --capture first")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary) or not parsed.has("results"):
		printerr("Could not parse baseline JSON at %s" % BASELINE_PATH)
		quit(1)
		return
	var baseline_results: Array = parsed["results"]

	if baseline_results.size() != results.size():
		print("MATCHUP COUNT MISMATCH: baseline=%d current=%d -- harness definitions changed, re-capture" % [
			baseline_results.size(), results.size(),
		])
		quit(1)
		return

	var winner_agree := 0
	var delta_sum := 0.0
	var delta_n := 0
	print("--- Rescale A/B Baseline COMPARE ---")
	for i in results.size():
		var cur: Dictionary = results[i]
		var base: Dictionary = baseline_results[i]
		if base.get("name", "") != cur["name"]:
			print("NAME MISMATCH at index %d: baseline=%s current=%s -- matchup order changed, re-capture" % [
				i, base.get("name", "?"), cur["name"],
			])
			quit(1)
			return
		var same_winner: bool = base.get("winner", "") == cur["winner"]
		if same_winner:
			winner_agree += 1
		var atk_delta := absf(float(base.get("atk_casualty_frac", 0.0)) - float(cur["atk_casualty_frac"]))
		var def_delta := absf(float(base.get("def_casualty_frac", 0.0)) - float(cur["def_casualty_frac"]))
		delta_sum += atk_delta + def_delta
		delta_n += 2
		print("[%s/%s] base_winner=%s cur_winner=%s %s | atk_cas Δ%.3f def_cas Δ%.3f" % [
			cur["category"], cur["name"], base.get("winner", "?"), cur["winner"],
			("MATCH" if same_winner else "MISS"), atk_delta, def_delta,
		])

	var mean_delta := delta_sum / maxf(1.0, float(delta_n))
	print("Winner agreement: %d/%d (bar: >= %d)" % [winner_agree, results.size(), WINNER_AGREEMENT_BAR])
	print("Mean casualty-fraction delta: %.4f (bar: <= %.2f)" % [mean_delta, CASUALTY_DELTA_BAR])

	var pass_bar := winner_agree >= WINNER_AGREEMENT_BAR and mean_delta <= CASUALTY_DELTA_BAR
	if pass_bar:
		print("RESCALE A/B PARITY PASSED")
		quit(0)
	else:
		print("RESCALE A/B PARITY FAILED")
		quit(1)

# ── Helpers ─────────────────────────────────────────────────────

func _classify_winner(atk_survived: bool, def_survived: bool) -> String:
	if atk_survived and not def_survived:
		return "attacker"
	if def_survived and not atk_survived:
		return "defender"
	if atk_survived and def_survived:
		return "stalemate"
	return "mutual_kill"

func _casualty_frac(pre: int, post: int) -> float:
	if pre <= 0:
		return 0.0
	return clampf(1.0 - float(post) / float(pre), 0.0, 1.0)

func _build_army(id: StringName, specs: Array, hex: Vector2i, is_garrison: bool) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = id
	army.hex_pos = hex
	army.is_garrison = is_garrison
	var n := 0
	var faction_id: StringName = &""
	for spec: Dictionary in specs:
		var uid: StringName = spec["id"]
		var count: int = spec["n"]
		var ud: UnitData = _dm.get_unit(uid)
		if ud == null:
			push_error("test_rescale_parity: missing unit data %s" % uid)
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
	## Any land tile with no city on it -- armies just need somewhere to
	## stand; a cityless tile keeps auto_resolve's siege/garrison-merge
	## branches inert except for the explicit `garrison` flag matchups below.
	for coord in _gm.state.hex_map.tiles:
		var tile = _gm.state.hex_map.tiles[coord]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		if _gm.city_system.get_city_at_hex(coord) != null:
			continue
		return coord
	return Vector2i(10, 10)

## 20 pinned matchups, 4 per category, spanning the compositions the task
## brief calls out: tanky-few vs many-cheap, ranged-heavy, monster stacks,
## mixed (combined-arms), garrison-defense (defender flagged is_garrison).
## Each `a`/`b` side is single-faction (mixing factions within one side
## would make ArmyState.faction_id -- last-unit-wins in _build_army -- and
## the per-unit faction-mechanic combat bonuses in battle_simulator_v2.gd's
## _create_formation ambiguous). Unit ids are real DataManager data, same as
## test_strength_meter_probe.gd's approach; counts are separate UnitInstance
## "squads" (each already carrying its own squad_size headcount).
func _build_matchups() -> Array[Dictionary]:
	return [
		# ── tanky-few vs many-cheap ──
		{
			"name": "iron_colossus_pair_vs_cinder_militia_horde", "category": "tanky_few_vs_many_cheap",
			"a": [{"id": &"iron_colossus", "n": 2}],
			"b": [{"id": &"cinder_militia", "n": 1}],
		},
		{
			"name": "root_sentinel_pair_vs_dawn_militia_horde", "category": "tanky_few_vs_many_cheap",
			"a": [{"id": &"root_sentinel", "n": 2}],
			"b": [{"id": &"dawn_militia", "n": 1}],
		},
		{
			"name": "bone_colossus_solo_vs_ghoul_pack_horde", "category": "tanky_few_vs_many_cheap",
			"a": [{"id": &"bone_colossus", "n": 1}],
			"b": [{"id": &"ghoul_pack", "n": 1}],
		},
		{
			"name": "shard_colossus_solo_vs_crystal_swarmling_horde", "category": "tanky_few_vs_many_cheap",
			"a": [{"id": &"shard_colossus", "n": 1}],
			"b": [{"id": &"crystal_swarmling", "n": 2}],
		},
		# ── ranged-heavy ──
		{
			"name": "thornbow_scout_volley_vs_thornback_guardian", "category": "ranged_heavy",
			"a": [{"id": &"thornbow_scout", "n": 3}],
			"b": [{"id": &"thornback_guardian", "n": 1}],
		},
		{
			"name": "stormbow_raider_flight_vs_thunderswarm_warrior", "category": "ranged_heavy",
			"a": [{"id": &"stormbow_raider", "n": 1}],
			"b": [{"id": &"thunderswarm_warrior", "n": 1}],
		},
		{
			"name": "bone_archer_volley_vs_bone_colossus", "category": "ranged_heavy",
			"a": [{"id": &"bone_archer", "n": 1}],
			"b": [{"id": &"bone_colossus", "n": 1}],
		},
		{
			"name": "sun_archer_line_vs_solar_champion", "category": "ranged_heavy",
			"a": [{"id": &"sun_archer", "n": 1}],
			"b": [{"id": &"solar_champion", "n": 1}],
		},
		# ── monster stacks ──
		{
			"name": "steppe_mammoth_duo_vs_frost_hydra_duo", "category": "monster_stacks",
			"a": [{"id": &"steppe_mammoth", "n": 2}],
			"b": [{"id": &"frost_hydra", "n": 2}],
		},
		{
			"name": "thunderwyrm_duo_vs_tainted_colossus_solo", "category": "monster_stacks",
			"a": [{"id": &"thunderwyrm", "n": 1}],
			"b": [{"id": &"tainted_colossus", "n": 1}],
		},
		{
			"name": "treant_duo_vs_steppe_mammoth_herd", "category": "monster_stacks",
			"a": [{"id": &"treant", "n": 1}],
			"b": [{"id": &"steppe_mammoth", "n": 2}],
		},
		{
			"name": "shard_colossus_solo_vs_thunderwyrm_duo", "category": "monster_stacks",
			"a": [{"id": &"shard_colossus", "n": 1}],
			"b": [{"id": &"thunderwyrm", "n": 1}],
		},
		# ── mixed (combined-arms) ──
		{
			"name": "empire_legion_line_vs_gladehost_woodland_host", "category": "mixed",
			"a": [{"id": &"legionary", "n": 1}, {"id": &"imperial_crossbow", "n": 1}],
			"b": [{"id": &"oakguard", "n": 1}, {"id": &"thornbow_scout", "n": 1}],
		},
		{
			"name": "skulloath_raiders_vs_forsaken_undead_host", "category": "mixed",
			"a": [{"id": &"skull_reavers", "n": 1}, {"id": &"steppe_skirmishers", "n": 1}],
			"b": [{"id": &"void_berserker", "n": 1}, {"id": &"cursed_archer", "n": 1}],
		},
		{
			"name": "ivoryscar_desert_host_vs_cinderguard_forge_host", "category": "mixed",
			"a": [{"id": &"tomb_guard", "n": 1}, {"id": &"bone_archer", "n": 1}],
			"b": [{"id": &"ember_cavalry", "n": 1}, {"id": &"ember_crossbow", "n": 1}],
		},
		{
			"name": "thunderswarm_storm_host_vs_sunblessed_dawn_host", "category": "mixed",
			"a": [{"id": &"thunderswarm_warrior", "n": 1}, {"id": &"stormbow_raider", "n": 1}],
			"b": [{"id": &"dawn_militia", "n": 1}, {"id": &"sun_archer", "n": 1}],
		},
		# ── garrison-defense (defender flagged is_garrison) ──
		{
			"name": "garrison_cinder_militia_holds_vs_empire_legion", "category": "garrison_defense",
			"a": [{"id": &"elite_legionaries", "n": 2}],
			"b": [{"id": &"cinder_militia", "n": 2}], "garrison": true,
		},
		{
			"name": "garrison_bone_archer_line_vs_skulloath_raiders", "category": "garrison_defense",
			"a": [{"id": &"skull_reavers", "n": 2}],
			"b": [{"id": &"bone_archer", "n": 2}], "garrison": true,
		},
		{
			"name": "garrison_root_sentinel_vs_thunderwyrm_assault", "category": "garrison_defense",
			"a": [{"id": &"thunderwyrm", "n": 1}],
			"b": [{"id": &"root_sentinel", "n": 2}], "garrison": true,
		},
		{
			"name": "garrison_dawn_militia_vs_forsaken_raid", "category": "garrison_defense",
			"a": [{"id": &"ghoul_pack", "n": 2}],
			"b": [{"id": &"dawn_militia", "n": 2}], "garrison": true,
		},
	]
