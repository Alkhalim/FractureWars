extends SceneTree
## Task 4 (Polish Pass 1): honest income breakdown.
##
## The income breakdown tooltip (campaign_hud._calculate_income_breakdown) no
## longer re-implements city_system's income math from a hand-copied
## snapshot — every faction-level stage calls the SAME pure helper functions
## city_system._generate_income() calls (apply_research_income_percentages,
## apply_heartwood_income_bonus, compute_faction_income_modifier_effects,
## etc). This test proves that by comparing the breakdown's per-resource
## totals, computed from the CURRENT (pre-turn) state, against what a real
## _generate_income() call actually credits to fs.resources for that same
## state. Any future income modifier added to _generate_income() without
## being wired into the breakdown will show up here as a mismatch.
##
## Scope: this covers the INCOME side of _generate_income() only — one real
## _generate_income() call per owned, non-sieged city (the same per-city
## work process_turn() does in a turn), summed into one before/after
## fs.resources delta per resource type. Explicitly EXCLUDED (because
## _generate_income() doesn't touch them either):
##   - army/commander upkeep (_deduct_upkeep, a separate process_turn() step)
##   - captive camp decay (_process_captive_decay, a separate step — the
##     "Camp Decay" tooltip row for Captives is informational only)
##   - diplomacy trade-deal/trade-relations transfers and trade-route
##     plunder (diplomacy_system, not city_system)
##   - elderbeast income (TurnManager._get_elderbeast_income)
## The reconciliation below adds upkeep and camp decay back out of
## breakdown.net (since _calculate_income_breakdown() nets them into the
## displayed "net" for the tooltip) so the comparison isolates exactly what
## _generate_income() itself credits.
##
## Run: godot --headless --path . -s res://tests/test_income_breakdown_equivalence.gd

var _fails := 0
var _gm: Node

# All resource types the breakdown supports, regardless of UI display
# filtering (which hides Shard Essence for non-Shardhorde factions — that's
# a display concern, not a correctness one).
const ALL_RES_TYPES := [0, 1, 2, 3, 4, 5, 6]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")

	# Scenario 1: fresh empire state (seed=0 for determinism).
	_gm.new_game(&"empire", false, 0)
	_check_parity("empire, initial state")

	# Scenario 2: debt penalty (-66% income) + low loyalty + empire's
	# captive-consuming faction modifier (Imperial Work Yard). Captives are
	# kept comfortably above 10 (calculate_city_income()'s labor-camp output
	# multiplier saturates at captives >= 10) so that multiplier stays
	# pinned at 1.0 for every owned city regardless of processing order —
	# calculate_city_income() itself re-reads the LIVE captive count each
	# time it's called, and the real per-city turn pass depletes captives
	# between cities while the memo snapshots calculate_city_income() once
	# upfront. That specific cross-city drift is a pre-existing quirk of
	# calculate_city_income()'s captive scaling, orthogonal to what this
	# task is fixing (faction-level income modifiers), so the scenario
	# avoids crossing that saturation boundary rather than simulating it.
	_gm.new_game(&"empire", false, 0)
	var fs2: FactionState = _gm.state.faction_states[_gm.state.player_faction_id]
	fs2.resources[Enums.ResourceType.GOLD] = -50
	fs2.resources[Enums.ResourceType.CAPTIVES] = 50
	if fs2.owned_cities.size() > 0:
		var c2a: CityState = _gm.state.cities[fs2.owned_cities[0]]
		c2a.loyalty = -10
		if not c2a.buildings.has(&"imperial_work_yard"):
			c2a.buildings.append(&"imperial_work_yard")
	if fs2.owned_cities.size() > 1:
		# A second qualifying building on another city exercises the
		# sequential captive-depletion threading across multiple cities.
		var c2b: CityState = _gm.state.cities[fs2.owned_cities[1]]
		if not c2b.buildings.has(&"labor_camp"):
			c2b.buildings.append(&"labor_camp")
	_check_parity("empire, debt penalty + low loyalty + captive consumption")

	# Scenario 3: skulloath (corruption-based food modifier + Blood Altar
	# captive consumption) — exercises a different faction-modifier branch.
	_gm.new_game(&"skulloath", false, 0)
	var fs3: FactionState = _gm.state.faction_states[_gm.state.player_faction_id]
	fs3.resources[Enums.ResourceType.CAPTIVES] = 10
	fs3.corruption = 20
	if fs3.owned_cities.size() > 0:
		var c3: CityState = _gm.state.cities[fs3.owned_cities[0]]
		if not c3.buildings.has(&"blood_altar"):
			c3.buildings.append(&"blood_altar")
	_check_parity("skulloath, corruption bonus + blood altar")

	# Scenario 4: siege a city (memo membership / per-city loop changes).
	if fs3.owned_cities.size() > 1:
		var c3b: CityState = _gm.state.cities[fs3.owned_cities[1]]
		c3b.is_under_siege = true
	_check_parity("skulloath, one city under siege")

	if _fails == 0:
		print("INCOME EQUIVALENCE TEST PASSED")
		quit(0)
	else:
		print("INCOME EQUIVALENCE TEST FAILED (%d)" % _fails)
		quit(1)

func _check_parity(label: String) -> void:
	var player_id: StringName = _gm.state.player_faction_id
	var fs: FactionState = _gm.state.faction_states[player_id]

	# Breakdown computed from the CURRENT (pre-turn) state — this is exactly
	# when the real tooltip is shown, projecting the upcoming turn's income.
	var hud = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()
	var breakdown_by_type: Dictionary = {}
	for res_type in ALL_RES_TYPES:
		breakdown_by_type[res_type] = hud._calculate_income_breakdown(res_type)
	hud.free()

	var before: Dictionary = fs.resources.duplicate()

	# Run ONE real _generate_income() per owned, non-sieged city — exactly
	# the income-generating work process_turn() performs in one turn.
	for city_id in fs.owned_cities:
		var city: CityState = _gm.state.cities.get(city_id)
		if city and not city.is_under_siege:
			_gm.city_system._generate_income(city, player_id)

	for res_type in ALL_RES_TYPES:
		var credited: int = fs.resources.get(res_type, 0) - before.get(res_type, 0)
		var bd: Dictionary = breakdown_by_type[res_type]

		# breakdown.net already subtracts army/commander upkeep and captive
		# camp decay, but _generate_income() never touches either — add them
		# back so the comparison isolates only what _generate_income() does.
		var upkeep_total := 0
		for tag in bd.upkeep:
			upkeep_total += bd.upkeep[tag]
		var camp_decay := 0
		if res_type == Enums.ResourceType.CAPTIVES and fs.resources.get(Enums.ResourceType.CAPTIVES, 0) > 0:
			camp_decay = _gm.city_system.calculate_captive_camp_decay(player_id)
		var expected: int = bd.net + upkeep_total + camp_decay

		if credited != expected:
			_fails += 1
			print("MISMATCH (%s) res=%d: _generate_income credited=%d, breakdown expected=%d (net=%d upkeep=%d camp_decay=%d)" % [label, res_type, credited, expected, bd.net, upkeep_total, camp_decay])
