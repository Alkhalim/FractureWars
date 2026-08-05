extends SceneTree
## W5 (UI Polish Wave 2): pins two designer-reported campaign-start bugs for
## nomadic/cityless factions (Shardhorde, Sunblessed, etc — see
## GameManager.NOMADIC_FACTIONS):
##
## 1. HORDE CAMERA — designer: "horde army campaign starts should have the
##    camera on their largest current horde". campaign.gd._ready() used to
##    fall back to the bare map center whenever no player-owned capital
##    city exists (true for every nomadic start); it now centers on the
##    player's largest army instead, using the SAME power estimate the
##    pre-battle strength meter uses (_calc_army_power_estimate, loaded
##    fresh below — not reimplemented, so this can't drift out of sync).
##
## 2. TURN-1 VISION — designer: "i had 2 spots of vision but they did not
##    align with the action positions of my hordes... cleared up after
##    passing first turn". Root cause: _visible_tile_cache started as an
##    empty Dictionary and was only ever populated by _update_fog_of_war(),
##    previously first triggered deep inside TurnManager.start_game() (the
##    turn_started -> _on_turn_started signal) near the very END of
##    _ready(). _create_minimap()'s first paint (and _update_trade_routes())
##    ran BEFORE that, reading the still-empty cache — for a nomadic start
##    with zero owned-tile fallback vision, that first bad paint (a fully
##    black minimap, no army dots at all) IS the player's entire first
##    impression of their vision. Fixed by computing fog synchronously
##    right after _create_fog_overlay(), before anything else in _ready()
##    can read a stale/empty _visible_tile_cache.
##
## Run: godot --headless --path . -s res://tests/test_w5_horde_camera_vision.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	_check_faction(&"shardhorde", gm)
	# Let the freed campaign scene's queue_free() actually process (and its
	# EventBus signal connections disconnect) before the next scenario
	# instantiates a second campaign scene — otherwise the first instance's
	# still-connected _on_turn_started handler double-reacts to the second
	# scenario's TurnManager.start_game() signal, contaminating the check.
	await process_frame
	_check_faction(&"sunblessed", gm)
	await process_frame
	_check_load_game_fog(gm)
	if _fails == 0:
		print("HORDE CAMERA/VISION TEST PASSED")
		quit(0)
	else:
		print("HORDE CAMERA/VISION TEST FAILED (%d)" % _fails)
		quit(1)

func _check_ok(cond: bool, label: String) -> void:
	if cond:
		print("OK: %s" % label)
	else:
		_fails += 1
		print("FAIL: %s" % label)

func _check_faction(faction_id: StringName, gm: Node) -> void:
	# campaign.gd._ready() only calls TurnManager.start_game() (the real
	# turn-1 kickoff, including the synchronous fog refresh this test is
	# probing) the FIRST time a campaign scene loads in this process —
	# GameManager.has_meta("game_started") gates it, same as a real app
	# session. Clear it before each scenario so a second faction checked in
	# the same test run gets a genuinely fresh "first campaign load" too,
	# not the degraded elif branch a real player would never hit on an
	# actual first game start.
	gm.remove_meta("game_started")
	gm._is_transitioning = true
	gm.new_game(faction_id, false, 0)
	gm._is_transitioning = false

	# Independently determine the expected largest-power army using the
	# SAME estimator campaign.gd's camera fix calls (loaded fresh, not
	# hand-copied). gm.new_game() above already warmed the autoload-
	# dependent scripts (godot-test-harness gotcha).
	var camscript := load("res://scenes/campaign/campaign.gd") as GDScript
	var probe: Node2D = camscript.new()
	var best_army: ArmyState = null
	var best_power := -1.0
	for aid in gm.state.armies:
		var a: ArmyState = gm.state.armies[aid]
		if a.faction_id != faction_id:
			continue
		var p: float = probe._calc_army_power_estimate(a)
		if best_army == null or p > best_power:
			best_power = p
			best_army = a
	probe.free()
	_check_ok(best_army != null, "%s: has at least one starting army" % faction_id)
	if best_army == null:
		return

	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	var campaign := scene.instantiate()
	root.add_child(campaign)

	# 1) Camera fix — centers on the largest army, not the bare map center.
	var expected_cam: Vector2 = campaign.call("_hex_to_pixel", best_army.hex_pos)
	var cam: Camera2D = campaign.get("camera")
	_check_ok(cam.position.distance_to(expected_cam) < 0.5,
		"%s: camera centers on largest army (got %s, expected %s)" % [faction_id, str(cam.position), str(expected_cam)])

	# 2) Vision fix, main map — _visible_tile_cache populated synchronously
	# in _ready(), BEFORE any _process() frame, and includes every player
	# army's hex.
	var vis_cache: Dictionary = campaign.get("_visible_tile_cache")
	_check_ok(vis_cache != null and not vis_cache.is_empty(),
		"%s: _visible_tile_cache populated synchronously in _ready()" % faction_id)
	for aid in gm.state.armies:
		var a: ArmyState = gm.state.armies[aid]
		if a.faction_id == faction_id:
			_check_ok(bool(vis_cache.get(a.hex_pos, false)),
				"%s: army %s hex %s is in visible_tile_cache" % [faction_id, aid, str(a.hex_pos)])

	# 3) Vision fix, minimap layer — the FIRST minimap paint (inside
	# _create_minimap(), which runs before the periodic/deferred minimap
	# refresh) must already show each army as a lit dot, not the dark
	# "unexplored" fill. This is the concrete mechanism behind the
	# designer's "2 spots of vision that don't align with my hordes" report
	# for a faction with zero owned-tile fallback vision.
	var minimap_content: Image = campaign.get("_minimap_content_cache")
	_check_ok(minimap_content != null, "%s: minimap content cache built during _ready()" % faction_id)
	if minimap_content != null:
		for aid in gm.state.armies:
			var a: ArmyState = gm.state.armies[aid]
			if a.faction_id == faction_id:
				var px: int = a.hex_pos.x * 4 + 2
				var py: int = a.hex_pos.y * 4 + 2
				var c: Color = minimap_content.get_pixel(px, py)
				# Dark "unexplored" fill is Color(0.05, 0.04, 0.07); any real
				# army-dot color (faction color .lightened(0.4)) has
				# noticeably higher channel sum than that.
				_check_ok(c.r + c.g + c.b > 0.3,
					"%s: minimap shows army %s as a lit dot on the first paint (got %s)" % [faction_id, aid, str(c)])

	campaign.queue_free()

## Old-save load sanity (the vision fix touches fog init, which only ever
## runs once per campaign SCENE load, whether that load came from
## new_game() or load_game() — verify the fix applies equally to a loaded
## save, not just a brand new game).
func _check_load_game_fog(gm: Node) -> void:
	gm.remove_meta("game_started")
	gm._is_transitioning = true
	gm.new_game(&"shardhorde", false, 0)
	gm._is_transitioning = false
	gm.save_game(99)

	# Switch to a totally different in-memory state first so load_game()
	# below is a genuine round-trip read, not a no-op over already-correct
	# state.
	gm.remove_meta("game_started")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false

	gm.remove_meta("game_started")
	gm._is_transitioning = true
	gm.load_game(99)
	gm._is_transitioning = false

	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	var campaign := scene.instantiate()
	root.add_child(campaign)

	var vis_cache: Dictionary = campaign.get("_visible_tile_cache")
	_check_ok(vis_cache != null and not vis_cache.is_empty(),
		"load_game: _visible_tile_cache re-derives (populated) on load")
	var player_id: StringName = gm.state.player_faction_id
	_check_ok(player_id == &"shardhorde", "load_game: loaded state is the saved Shardhorde game, not the intervening Empire one")
	for aid in gm.state.armies:
		var a: ArmyState = gm.state.armies[aid]
		if a.faction_id == player_id:
			_check_ok(bool(vis_cache.get(a.hex_pos, false)),
				"load_game: army %s hex %s is in visible_tile_cache after load" % [aid, str(a.hex_pos)])

	campaign.queue_free()
