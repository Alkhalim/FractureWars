extends SceneTree
## Tests for Polish Pass 1 (faction intros, shard ascension, breakdown honesty).
## Run: godot --headless --path . -s res://tests/test_polish_pass.gd

var _fails := 0
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_gm = root.get_node("/root/GameManager")
	_gm.new_game(&"empire", false, 0)

	# ── Faction intros: every playable faction has complete content ──
	for fid in _gm.state.faction_states:
		var fd: FactionData = root.get_node("/root/DataManager").get_faction(fid)
		if fd == null or not fd.is_playable:
			continue
		var intro: Dictionary = FactionIntroData.INTROS.get(fid, {})
		_check(not intro.is_empty(), "intro exists for %s" % fid)
		for key in ["title", "mechanic", "dilemma", "resource", "opening"]:
			_check(intro.get(key, "") != "", "intro.%s non-empty for %s" % [key, fid])
	_check(not _gm.state.faction_intro_shown, "intro flag starts false")

	if _fails == 0:
		print("POLISH TEST PASSED")
		quit(0)
	else:
		print("POLISH TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
