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

	# Scenario 5 (Task W5, UI Polish Wave 2): the Economy Overview panel's
	# "Net Income per Turn" row must match the top bar's per-resource delta
	# exactly -- designer report: "the net income per round in the eco
	# overview does not line up with the info displayed in the numbers
	# below the resource bar on top". Root cause: the panel was a SEPARATE,
	# hand-rolled (City Income total - unit-only upkeep total) that skipped
	# every _generate_income() modifier stage (research/heartwood/trade/
	# senate/region/culture/shard/debt/faction bonuses), commander upkeep,
	# population food consumption, captive camp decay, trade treaties,
	# elderbeast income, and trade-route plunder -- AND never filtered
	# sieged cities out of its income total (city_system.process_turn skips
	# _generate_income entirely for a sieged city; the panel didn't), so it
	# could even overstate income for a player with a besieged city. Fixed
	# by making the panel's Net Income row call the SAME
	# _calculate_income_breakdown() the top bar's _calculate_projected_income()
	# calls. This reads back the panel's ACTUAL RENDERED numbers (not a
	# reimplementation of the formula) after instantiating the real
	# campaign scene and opening the real panel, under a state exercising
	# both bugs at once (debt penalty + a besieged second city + a
	# commander), so a future edit that reintroduces a hand-rolled net
	# calculation fails this test.
	_check_panel_matches_topbar()

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

func _check_panel_matches_topbar() -> void:
	# Block new_game()'s own trailing transition_to_scene() call (a tweened
	# get_tree().change_scene_to_file, unsuitable for a script-mode test) --
	# same _is_transitioning guard the tmp_screenshot_*.gd windowed harnesses
	# use, set BEFORE new_game() so its internal call is a no-op.
	_gm._is_transitioning = true
	_gm.new_game(&"empire", false, 0)
	_gm._is_transitioning = false
	var pid: StringName = _gm.state.player_faction_id
	var fs: FactionState = _gm.state.faction_states[pid]

	# Exercise both bugs the panel had at once:
	# 1) Debt penalty (-66% income) drives several modifier-stage rows the
	#    old panel formula never applied.
	fs.resources[Enums.ResourceType.GOLD] = -50
	# 2) A besieged second city — city_system.process_turn() (and the
	#    breakdown's per-city memo) skip income for it entirely; the old
	#    panel formula counted its raw income anyway.
	if fs.owned_cities.size() > 1:
		var siege_city: CityState = _gm.state.cities[fs.owned_cities[1]]
		siege_city.is_under_siege = true
	# 3) A commander — the old panel's upkeep loop only ever summed unit
	#    upkeep, silently omitting commander upkeep.
	for aid in _gm.state.armies:
		var army: ArmyState = _gm.state.armies[aid]
		if army.faction_id == pid:
			army.commander = _gm._create_commander(pid)
			break

	# Instantiate the REAL campaign scene (same pattern the tmp_screenshot_*
	# windowed harnesses use) so this reads the panel's ACTUAL rendered
	# output, not a second reimplementation of the formula.
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	var campaign := scene.instantiate()
	root.add_child(campaign)
	var hud = campaign.get_node("UILayer/HUD")

	# Top-bar-equivalent: exactly what _update_resource_display() feeds the
	# per-resource delta labels under the resource bar.
	var expected: Array[int] = []
	var display_types := [0, 1, 2, 3, 5, 6]
	if pid == &"shardhorde":
		display_types = [0, 1, 2, 3, 4, 5, 6]
	for res_type in display_types:
		var net: int = hud._calculate_income_breakdown(res_type).net
		if net != 0:
			expected.append(net)

	# Panel's actual rendered "Net Income per Turn" row.
	hud._refresh_economy_panel()
	var vbox: VBoxContainer = hud.economy_panel.get_child(0).get_node("EconomyVBox")
	var net_header_idx := -1
	for i in vbox.get_child_count():
		var child: Node = vbox.get_child(i)
		if child is Label and (child as Label).text == "Net Income per Turn":
			net_header_idx = i
			break
	if net_header_idx == -1 or net_header_idx + 1 >= vbox.get_child_count():
		_fails += 1
		print("MISMATCH (panel vs top bar): could not find 'Net Income per Turn' row in the rendered panel")
		campaign.queue_free()
		return

	var actual: Array[int] = []
	var row: Node = vbox.get_child(net_header_idx + 1)
	# If net_all was empty, row is the "Balanced (no net change)" Label
	# instead of a cost row -- actual stays [] to match, no special-casing
	# needed here.
	if row is HBoxContainer:
		for child in (row as Container).get_children():
			# Skip the prefix Label ("  ") -- only HBoxContainer "pairs"
			# (icon + value Label, built by GameManager.make_cost_row) hold
			# resource values.
			if child is HBoxContainer:
				var value_label: Label = (child as Container).get_child((child as Container).get_child_count() - 1)
				actual.append(int(value_label.text.lstrip("+")))

	if actual != expected:
		_fails += 1
		print("MISMATCH (panel vs top bar): panel Net Income row=%s, top-bar breakdown=%s" % [str(actual), str(expected)])

	campaign.queue_free()
