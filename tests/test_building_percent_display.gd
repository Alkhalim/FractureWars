extends SceneTree
## Quick-fix Item B: fractional building special_effects (e.g. relic_sanctum's
## commander_xp_bonus = 0.15) must display as a whole percent ("+15%"), not
## int(value) truncated straight through to "+0%". _format_building_special_effect
## (campaign_hud.gd) already multiplied research_speed_bonus by 100 but not
## commander_xp_bonus -- this is the RED->GREEN regression guard for that fix,
## plus a sibling data-sweep: swarm_nest.tres's recruit_cost_discount_pct was
## stored as a fraction (0.1) where the "_pct" convention (see guild_hall.tres's
## whole-number 15) expects a whole percent -- city_system.gd's real recruit-
## cost math truncates that the same way int(value) truncates the display.
## Run: godot --headless --path . -s res://tests/test_building_percent_display.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# campaign_hud.gd only compiles headless AFTER a new_game() has loaded and
	# warmed its dependency scripts (GameManager/CityState/etc.) -- loading it
	# cold here fails with "Identifier not found: EventBus" and the static call
	# then explodes. Same load-late + instantiate pattern as
	# test_income_breakdown_equivalence.gd:111.
	var gm = root.get_node("/root/GameManager")
	gm.new_game(&"empire", false, 42)
	var hud = (load("res://scenes/campaign/campaign_hud.gd") as GDScript).new()

	var got_xp: String = hud._format_building_special_effect("commander_xp_bonus", 0.15)
	_check(got_xp == "+15% Commander XP", "commander_xp_bonus 0.15 displays as +15%%, got %s" % got_xp)

	# Regression guard: research_speed_bonus was already correct -- must stay so.
	var got_research_15: String = hud._format_building_special_effect("research_speed_bonus", 0.15)
	_check(got_research_15 == "+15% Research Speed", "research_speed_bonus 0.15 displays as +15%%, got %s" % got_research_15)
	var got_research_25: String = hud._format_building_special_effect("research_speed_bonus", 0.25)
	_check(got_research_25 == "+25% Research Speed", "research_speed_bonus 0.25 displays as +25%%, got %s" % got_research_25)

	var dm = root.get_node("/root/DataManager")
	var relic = dm.get_building(&"relic_sanctum")
	_check(relic != null, "relic_sanctum building data exists")
	if relic:
		_check(float(relic.special_effects.get("commander_xp_bonus", -1)) == 0.15,
			"relic_sanctum.commander_xp_bonus == 0.15, got %s" % [relic.special_effects.get("commander_xp_bonus")])
		var card_text: String = hud._format_building_special_effect("commander_xp_bonus", relic.special_effects["commander_xp_bonus"])
		_check(card_text == "+15% Commander XP", "relic_sanctum's building-card text reads +15%% Commander XP, got %s" % card_text)

	var swarm = dm.get_building(&"swarm_nest")
	_check(swarm != null, "swarm_nest building data exists")
	if swarm:
		var disc: float = float(swarm.special_effects.get("recruit_cost_discount_pct", 0))
		_check(disc >= 1.0, "swarm_nest recruit_cost_discount_pct is a whole percent (>=1), not a fraction truncating to 0, got %s" % [disc])

	hud.free()

	if _fails == 0:
		print("BUILDING PERCENT DISPLAY TEST PASSED")
		quit(0)
	else:
		print("BUILDING PERCENT DISPLAY TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
