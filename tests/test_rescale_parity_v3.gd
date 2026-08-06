extends SceneTree
## Task R2 (Unit Stat Rescale), amendment A: V3 parity harness.
##
## R1's headline finding: BattleResolver.auto_resolve (what tests/test_rescale_parity.gd
## drives) always runs BattleSimulatorV2, never V3. V3 is the "manual Fight"
## sim (scenes/battle/battle_v3.gd) and is the ONLY place the bulk of this
## rescale's flat-bonus conversions live: vs_attack_bonuses/vs_defense_bonuses,
## armor_aura, siege_bonus, unit_ranged_bonus, flying_unit_attack_bonus, the
## whole ~30-entry sub-faction identity-modifier block, Thunder Wall, Ivoryscar
## relic defense/pyramid flat, Empire anti-mage/Cinderguard anti-monster
## vs_attack_bonuses. None of those move test_rescale_parity.gd's numbers even
## after R2 lands. This harness drives BattleSimulatorV3 DIRECTLY (same API
## shape as scenes/battle/battle_v3.gd's _start_battle and
## tests/test_battle_determinism.gd's _run_v3) so those conversions get a
## real A/B check.
##
## 10 pinned, deterministic matchups, chosen to exercise the V3-only paths
## amendment A calls out: 2x sub-faction identity modifiers, 2x ranged-heavy
## (validates the per-entity ranged damage floor decision), 2x terrain
## home-bonus (Gladehost forest, Ivoryscar desert), 2x city-battle/siege
## (siege_bonus research + Ivoryscar relic-defense expedition), 1x Thunder
## Wall (Thunderswarm defending its own warded city), 1x mixed combined-arms.
##
## CAPTURE mode (this task, OLD scale) writes winner + per-side casualty
## fraction to tests/baselines/rescale_ab_baseline_v3.json. COMPARE mode
## (after the rescale lands) re-runs the same matchups against that baseline.
## Bar (per the coordinator's amendment): winner agreement >= capture_count - 1
## (i.e. at most one flip allowed out of 10), mean casualty-fraction delta
## <= 10% (same numeric bar as the V2 harness, task brief).
##
## Task R3 follow-up (2026-08-06): +3 tainted_jade matchups (`tj_reference:
## true`), added because R3's econ investigation found tainted_jade had NO
## controlled A/B coverage in either harness while its econ-sim signal was
## the one flagged UNRESOLVED (see task-R3-report.md §6). Unlike the
## original 10, these have no pre-rescale baseline to diff against (the data
## is already rescaled repo-wide) -- they're captured at CURRENT scale as a
## pinned regression reference instead: `_run_compare` checks them for exact
## winner/casualty reproduction (tight tolerance, NOT the 10% rescale-noise
## bar) so a future change to the taint-scaling formulas gets caught, and
## excludes them from the `winner_agreement_bar` parity aggregate (that bar
## is specifically about old-vs-new-scale drift, which doesn't apply here).
## `_run_capture` is now merge-aware: it never overwrites an existing named
## entry (so re-running --capture can't accidentally clobber the original
## 10's old-scale pins), it only appends matchups not yet in the baseline.
##
## Run:
##   Capture (current scale, THIS task):
##     godot --headless --path . -s res://tests/test_rescale_parity_v3.gd -- --capture
##   Compare (after the rescale lands):
##     godot --headless --path . -s res://tests/test_rescale_parity_v3.gd

const BASELINE_DIR := "res://tests/baselines"
const BASELINE_PATH := BASELINE_DIR + "/rescale_ab_baseline_v3.json"
const SEED_BASE := 2608161 # distinct from test_rescale_parity.gd's SEED_BASE

const CASUALTY_DELTA_BAR := 0.10 # same numeric bar as the V2 harness, task brief

var _gm: Node
var _dm: Node
var _ts_city_id: StringName = &""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_dm = root.get_node("/root/DataManager")
	_gm.new_game(&"empire", false, 0)

	var matchups := _build_matchups()
	var results: Array[Dictionary] = []

	for i in matchups.size():
		var m: Dictionary = matchups[i]
		seed(SEED_BASE + i)
		var r := _run_matchup(m, i)
		results.append(r)

	var capture_mode := "--capture" in OS.get_cmdline_user_args()
	if capture_mode:
		_run_capture(results)
	else:
		_run_compare(results)

# ── Matchup execution ──────────────────────────────────────────

func _run_matchup(m: Dictionary, idx: int) -> Dictionary:
	var atk_id := StringName("rescale_v3_atk_%d" % idx)
	var def_id := StringName("rescale_v3_def_%d" % idx)
	var hex: Vector2i = m.get("hex", _find_empty_hex())
	var terrain: Enums.TerrainType = m.get("terrain", Enums.TerrainType.PLAINS)

	if m.has("setup"):
		m["setup"].call()

	var atk_army := _build_army(atk_id, m["a"], hex)
	var def_army := _build_army(def_id, m["b"], hex)

	var sim = load("res://scripts/systems/battle/battle_simulator_v3.gd").new()
	sim.setup_terrain(terrain, hex)
	sim.setup_attacker_formations(atk_army)
	sim.setup_defender_formations(def_army)
	sim.assign_ai_orders(0)
	sim.assign_ai_orders(1)

	var atk_pre := _sum_hp(sim.attacker_formations)
	var def_pre := _sum_hp(sim.defender_formations)

	for tick in range(sim.max_ticks):
		sim.simulate_tick()
		if sim.is_finished:
			break

	var atk_post := _sum_hp(sim.attacker_formations)
	var def_post := _sum_hp(sim.defender_formations)

	if m.has("teardown"):
		m["teardown"].call()

	return {
		"name": m["name"],
		"category": m["category"],
		"tj_reference": m.get("tj_reference", false),
		"winner": _classify_winner(sim),
		"ticks": sim.tick_count,
		"atk_pre_hp": atk_pre,
		"def_pre_hp": def_pre,
		"atk_post_hp": atk_post,
		"def_post_hp": def_post,
		"atk_casualty_frac": _casualty_frac(atk_pre, atk_post),
		"def_casualty_frac": _casualty_frac(def_pre, def_post),
	}

func _classify_winner(sim) -> String:
	if not sim.is_finished:
		return "stalemate" # timed out (tick cap) still contested
	if sim.winner_side == 0:
		return "attacker"
	if sim.winner_side == 1:
		return "defender"
	return "mutual_kill" # is_finished with winner_side == -1: both wiped or routing tie

func _sum_hp(formations: Array) -> int:
	var total := 0
	for f in formations:
		total += maxi(0, f.current_hp)
	return total

func _casualty_frac(pre: int, post: int) -> float:
	if pre <= 0:
		return 0.0
	return clampf(1.0 - float(post) / float(pre), 0.0, 1.0)

# ── Modes ───────────────────────────────────────────────────────

func _run_capture(results: Array[Dictionary]) -> void:
	## Merge-aware (Task R3 follow-up): an existing baseline entry (matched by
	## `name`) is NEVER overwritten -- only matchups not yet present get
	## appended. This is what makes it safe to add the tj_reference matchups
	## via --capture without risk of re-running --capture someday and
	## clobbering the original 10's old-scale pins with current-scale data
	## (which would silently turn the rescale A/B parity check into a no-op).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE_DIR))
	var existing_by_name := {}
	var f_read := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f_read:
		var parsed: Variant = JSON.parse_string(f_read.get_as_text())
		f_read.close()
		if parsed is Dictionary and parsed.has("results"):
			for r in parsed["results"]:
				existing_by_name[r.get("name", "")] = r

	var merged: Array = []
	var newly_added: Array[String] = []
	var parity_count := 0
	for r in results:
		if existing_by_name.has(r["name"]):
			merged.append(existing_by_name[r["name"]])
		else:
			merged.append(r)
			newly_added.append(r["name"])
		if not bool(r.get("tj_reference", false)):
			parity_count += 1

	var payload := {
		"schema": 1,
		"seed_base": SEED_BASE,
		"matchup_count": merged.size(),
		"winner_agreement_bar": maxi(0, parity_count - 1),
		"results": merged,
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
	print("--- Rescale A/B Baseline V3 CAPTURE ---")
	for r in results:
		var is_new: bool = r["name"] in newly_added
		print("[%s/%s]%s winner=%s ticks=%d atk_cas=%.2f def_cas=%.2f" % [
			r["category"], r["name"], (" NEW" if is_new else ""), r["winner"], r["ticks"], r["atk_casualty_frac"], r["def_casualty_frac"],
		])
	print("Winner distribution: %s" % [winner_counts])
	print("Newly added (appended, prior entries preserved untouched): %s" % [newly_added])
	print("BASELINE WRITTEN: %s (%d matchups, %d parity + %d tj_reference)" % [
		BASELINE_PATH, merged.size(), parity_count, merged.size() - parity_count,
	])
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
	var winner_bar: int = int(parsed.get("winner_agreement_bar", baseline_results.size() - 1))

	if baseline_results.size() != results.size():
		print("MATCHUP COUNT MISMATCH: baseline=%d current=%d -- harness definitions changed, re-capture" % [
			baseline_results.size(), results.size(),
		])
		quit(1)
		return

	## tj_reference entries (Task R3 follow-up) are pinned-regression checks
	## against a CURRENT-scale baseline (there's no old-scale data for them),
	## not old-vs-new rescale-drift checks -- so they're tallied separately
	## and held to a tight tolerance instead of folding into the 10%
	## rescale-noise bar/aggregate below.
	const TJ_REF_CASUALTY_TOLERANCE := 0.02

	var winner_agree := 0
	var delta_sum := 0.0
	var delta_n := 0
	var parity_total := 0
	var tj_ref_ok := true
	var tj_ref_total := 0
	var tj_ref_match := 0
	print("--- Rescale A/B Baseline V3 COMPARE ---")
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
		var atk_delta := absf(float(base.get("atk_casualty_frac", 0.0)) - float(cur["atk_casualty_frac"]))
		var def_delta := absf(float(base.get("def_casualty_frac", 0.0)) - float(cur["def_casualty_frac"]))
		var is_tj_ref: bool = bool(base.get("tj_reference", false)) or bool(cur.get("tj_reference", false))

		if is_tj_ref:
			tj_ref_total += 1
			var tj_ok := same_winner and atk_delta <= TJ_REF_CASUALTY_TOLERANCE and def_delta <= TJ_REF_CASUALTY_TOLERANCE
			if tj_ok:
				tj_ref_match += 1
			else:
				tj_ref_ok = false
			print("[TJ_REF %s/%s] base_winner=%s cur_winner=%s %s | atk_cas Δ%.3f def_cas Δ%.3f" % [
				cur["category"], cur["name"], base.get("winner", "?"), cur["winner"],
				("MATCH" if tj_ok else "DRIFT"), atk_delta, def_delta,
			])
			continue

		parity_total += 1
		if same_winner:
			winner_agree += 1
		delta_sum += atk_delta + def_delta
		delta_n += 2
		print("[%s/%s] base_winner=%s cur_winner=%s %s | atk_cas Δ%.3f def_cas Δ%.3f" % [
			cur["category"], cur["name"], base.get("winner", "?"), cur["winner"],
			("MATCH" if same_winner else "MISS"), atk_delta, def_delta,
		])

	var mean_delta := delta_sum / maxf(1.0, float(delta_n))
	print("Winner agreement: %d/%d (bar: >= %d)" % [winner_agree, parity_total, winner_bar])
	print("Mean casualty-fraction delta: %.4f (bar: <= %.2f)" % [mean_delta, CASUALTY_DELTA_BAR])
	if tj_ref_total > 0:
		print("TJ reference: %d/%d matched (tolerance %.2f, regression tripwire not rescale-parity)" % [
			tj_ref_match, tj_ref_total, TJ_REF_CASUALTY_TOLERANCE,
		])

	var pass_bar := winner_agree >= winner_bar and mean_delta <= CASUALTY_DELTA_BAR and tj_ref_ok
	if pass_bar:
		print("RESCALE A/B PARITY V3 PASSED")
		quit(0)
	else:
		print("RESCALE A/B PARITY V3 FAILED")
		quit(1)

# ── Helpers ─────────────────────────────────────────────────────

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
			push_error("test_rescale_parity_v3: missing unit data %s" % uid)
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

func _find_city_hex(faction_id: StringName) -> Dictionary:
	## Prefers a city owned by `faction_id` (needed for ownership-gated
	## mechanics like Thunder Wall); falls back to any city if that faction
	## has none on the generated map (still a valid, deterministic city
	## battle, just won't exercise the ownership-specific branch).
	var fallback: Dictionary = {}
	for cid in _gm.state.cities:
		var c: CityState = _gm.state.cities[cid]
		if fallback.is_empty():
			fallback = {"hex": c.hex_pos, "city_id": cid}
		if c.faction_id == faction_id:
			return {"hex": c.hex_pos, "city_id": cid}
	return fallback

## 10 pinned matchups. Real DataManager units, single-faction per side (see
## test_rescale_parity.gd's header comment for why -- ArmyState.faction_id
## is last-unit-wins and per-unit faction-mechanic bonuses need it
## unambiguous). `setup`/`teardown` callables poke FactionState directly for
## mechanics with no in-battle trigger path (research completion, Thunder
## Wall, relic defense expedition) -- there's no dilemma-resolution flow
## available in a short headless harness.
func _build_matchups() -> Array[Dictionary]:
	var vg_city := _find_city_hex(&"valkarn_garrison")
	var ts_city := _find_city_hex(&"thunderswarm")
	_ts_city_id = ts_city.get("city_id", &"")

	return [
		# ── sub-faction identity modifiers (V3-only, ~30-entry block) ──
		{
			"name": "crimson_legion_infantry_vs_valkarn_garrison_defenders", "category": "subfaction_identity",
			"a": [{"id": &"crimson_centurion", "n": 2}], # crimson_legion: infantry/heavy +3 atk
			"b": [{"id": &"valkarn_defender", "n": 2}], # valkarn_garrison: +3 def (open field, no city bonus here)
		},
		{
			"name": "gorgonic_cult_beastmaster_vs_twilight_veil_assassins", "category": "subfaction_identity",
			"a": [{"id": &"basilisk_rider", "n": 1}], # gorgonic_cult: vs monster/beast +2/+2, own monster/beast tags +2 atk
			"b": [{"id": &"veil_assassin", "n": 2}], # twilight_veil: infantry/light +4 atk, -2 def
		},
		# ── ranged-heavy (validates per-entity ranged damage floor, R1 §2.1) ──
		{
			"name": "stormbound_storm_archer_volley_vs_stormforged_champion", "category": "ranged_heavy",
			"a": [{"id": &"storm_archer", "n": 3}], # stormbound: ranged +2 atk, +1 speed
			"b": [{"id": &"stormforged_champion", "n": 1}],
		},
		{
			"name": "thunderswarm_highland_skirmisher_volley_vs_thunderwyrm", "category": "ranged_heavy",
			"a": [{"id": &"highland_skirmisher", "n": 3}],
			"b": [{"id": &"thunderwyrm", "n": 1}],
		},
		# ── terrain home-bonus (per-unit terrain_bonuses + faction-mechanic terrain branches) ──
		{
			"name": "gladehost_oakguard_forest_defense_vs_empire_legion", "category": "terrain_home_bonus",
			"a": [{"id": &"legionary", "n": 2}],
			"b": [{"id": &"oakguard", "n": 2}], # gladehost: forest +3 def/+2 atk
			"terrain": Enums.TerrainType.FOREST,
		},
		{
			"name": "ivoryscar_tomb_guard_desert_defense_vs_cinderguard_cavalry", "category": "terrain_home_bonus",
			"a": [{"id": &"ember_cavalry", "n": 2}],
			"b": [{"id": &"tomb_guard", "n": 2}], # ivoryscar: desert/wastes +2 def, +1 speed
			"terrain": Enums.TerrainType.DESERT,
		},
		# ── city-battle / siege_bonus (research-driven, V3-only consumption) ──
		{
			"name": "empire_siege_mastery_attack_vs_valkarn_garrison_city", "category": "city_siege",
			"a": [{"id": &"legionary", "n": 3}],
			"b": [{"id": &"valkarn_defender", "n": 2}], # +2 more def + 5 morale in city battle (sub-faction bonus)
			"hex": vg_city.get("hex", Vector2i(10, 10)),
			"setup": Callable(self, "_setup_siege_mastery"),
			"teardown": Callable(self, "_teardown_siege_mastery"),
		},
		{
			"name": "ivoryscar_relic_defense_expedition_city_holds_vs_forsaken_raid", "category": "city_siege",
			"a": [{"id": &"void_berserker", "n": 2}],
			"b": [{"id": &"tomb_guard", "n": 2}],
			"hex": _find_city_hex(&"ivoryscar").get("hex", Vector2i(10, 10)),
			"setup": Callable(self, "_setup_relic_defense"),
			"teardown": Callable(self, "_teardown_relic_defense"),
		},
		# ── Thunder Wall (Thunderswarm defending its own warded city, +8 def) ──
		{
			"name": "thunderswarm_thunder_wall_city_holds_vs_cinderguard_siege", "category": "thunder_wall",
			"a": [{"id": &"ember_cavalry", "n": 2}],
			"b": [{"id": &"thunderswarm_warrior", "n": 2}],
			"hex": ts_city.get("hex", Vector2i(10, 10)),
			"setup": Callable(self, "_setup_thunder_wall"),
			"teardown": Callable(self, "_teardown_thunder_wall"),
		},
		# ── mixed combined-arms ──
		{
			"name": "crimson_legion_combined_arms_vs_valkarn_garrison_combined_arms", "category": "mixed",
			"a": [{"id": &"crimson_centurion", "n": 1}, {"id": &"crimson_ballistarius", "n": 1}],
			"b": [{"id": &"valkarn_defender", "n": 1}, {"id": &"desert_outrider", "n": 1}],
		},
		# ── Task R3 follow-up: tainted_jade taint-scaling coverage ──────────
		# `tj_reference: true` -- these have no pre-rescale baseline (see
		# harness header comment); captured/compared at current scale only,
		# as a pinned regression reference, not old-vs-new rescale parity.
		# Each exercises a different taint_power tier (line ~499-532 of
		# battle_simulator_v3.gd) plus a jungle/swamp terrain regen floor
		# (Task R3 follow-up item 1's fix site) or the sibling Skulloath
		# corruption scaling block, so together they cover all three named
		# "taint/corruption scaling sites".
		{
			"name": "tainted_jade_venomous_taint_vs_empire_legion", "category": "tj_taint_scaling",
			"tj_reference": true,
			"a": [{"id": &"tainted_warrior", "n": 3}], # taint_power 45 (40-59 tier, +15% def) + Venomous War (+15% atk in jungle) + anti-mage vs_defense
			"b": [{"id": &"legionary", "n": 3}],
			"terrain": Enums.TerrainType.JUNGLE, # exercises the 0.05 hp_regen_per_tick floor fix (item 1)
			"setup": Callable(self, "_setup_tj_taint_venomous"),
			"teardown": Callable(self, "_teardown_tj_taint"),
		},
		{
			"name": "tainted_jade_swamp_taint_vs_skulloath_dread_riders", "category": "tj_taint_scaling",
			"tj_reference": true,
			"a": [{"id": &"jade_fang", "n": 3}], # taint_power 65 (60+ tier, +20% def)
			"b": [{"id": &"dread_riders", "n": 2}], # skulloath cavalry; default corruption=20 (<=20 tier, -8% atk) needs no setup
			"terrain": Enums.TerrainType.SWAMP, # exercises the 0.03 hp_regen_per_tick floor fix (item 1)
			"setup": Callable(self, "_setup_tj_taint_high"),
			"teardown": Callable(self, "_teardown_tj_taint"),
		},
		{
			"name": "tainted_jade_serpent_guardian_vs_gladehost_treant", "category": "tj_taint_scaling",
			"tj_reference": true,
			"a": [{"id": &"serpent_guardian", "n": 2}], # taint_power 25 (20-39 tier, +10% def) -- mirror-adjacent guardian archetype vs Gladehost's own heavy melee construct
			"b": [{"id": &"treant", "n": 1}], # gladehost default harmony=75 (>=70 tier, +12 morale/+5% def) needs no setup
			"terrain": Enums.TerrainType.FOREST, # Gladehost home bonus; no TJ terrain branch on FOREST (only jungle/swamp)
			"setup": Callable(self, "_setup_tj_taint_low"),
			"teardown": Callable(self, "_teardown_tj_taint"),
		},
	]

# ── Named setup/teardown (GDScript multi-line lambdas inside a Dictionary
# literal don't indent-parse reliably, so these are plain methods referenced
# via Callable(self, "...") from the matchup table above) ─────────────────

func _setup_siege_mastery() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"empire")
	if fs and not fs.completed_research.has(&"siege_mastery"):
		# rescale-note (Task R3, 2026-08-06): siege_bonus is DATA (a research
		# effects-dict value, not a code-side literal), so unlike the
		# hardcoded V3 sub-faction/terrain constants below (which keep their
		# pre-rescale literal as the _atk_pct/_def_pct helper argument), the
		# stored value itself changed: old flat 30 -> new global-reference
		# pct 43 (round(30/70*100)) when R2's data sweep landed.
		fs.completed_research.append(&"siege_mastery") # siege_bonus: 43 (was 30 pre-rescale)
		_gm.research_system._invalidate_cache(&"empire")

func _teardown_siege_mastery() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"empire")
	if fs:
		fs.completed_research.erase(&"siege_mastery")
		_gm.research_system._invalidate_cache(&"empire")

func _setup_relic_defense() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"ivoryscar")
	if fs:
		fs.leader_bonuses["relic_defense_turns"] = 3 # +3 def, side==1 && is_city_battle

func _teardown_relic_defense() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"ivoryscar")
	if fs:
		fs.leader_bonuses.erase("relic_defense_turns")

func _setup_thunder_wall() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"thunderswarm")
	if fs and _ts_city_id != &"":
		fs.storm_wall_turns = 3
		fs.storm_wall_city = _ts_city_id

func _teardown_thunder_wall() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"thunderswarm")
	if fs:
		fs.storm_wall_turns = 0
		fs.storm_wall_city = &""

## Task R3 follow-up: tainted_jade taint_power/taint_focus setup, one per
## tier so the 3 tj_reference matchups collectively cover all three
## taint_power thresholds (>=20/>=40/>=60) in battle_simulator_v3.gd's
## `elif parent_fid == &"tainted_jade":` block. Default taint_power is 0
## (see FactionState), so unlike Skulloath's default corruption=20 (already
## live without setup) these need an explicit poke.
func _setup_tj_taint_venomous() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"tainted_jade")
	if fs:
		fs.taint_power = 45
		fs.taint_focus = 2 # Venomous War: +atk in jungle/swamp once taint_power >= 20

func _setup_tj_taint_high() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"tainted_jade")
	if fs:
		fs.taint_power = 65

func _setup_tj_taint_low() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"tainted_jade")
	if fs:
		fs.taint_power = 25

func _teardown_tj_taint() -> void:
	var fs: FactionState = _gm.state.faction_states.get(&"tainted_jade")
	if fs:
		fs.taint_power = 0
		fs.taint_focus = 0
