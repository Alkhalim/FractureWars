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

	# ── Shard ascension counts consumption ──
	var efs: FactionState = _gm.state.faction_states[&"empire"]
	_check(efs.shards_spent == 0, "shards_spent starts 0")
	# Craft a shard and invest it in research
	var shard := ShardInstance.new()
	shard.shard_id = &"test_shard_polish"
	shard.claimed_by = &"empire"
	shard.realm = 1
	_gm.state.active_shards[shard.shard_id] = shard
	efs.owned_shards.append(shard.shard_id)
	# Start any affordable research so invest_shard has a target
	for rid in root.get_node("/root/DataManager").research:
		if _gm.research_system.start_research(&"empire", rid):
			break
	if efs.current_research_id != &"":
		var before := efs.shards_spent
		if _gm.research_system.invest_shard(&"empire", shard.shard_id):
			_check(efs.shards_spent == before + 1, "invest_shard increments shards_spent")
	var _tm: Node = root.get_node("/root/TurnManager")
	_check(_tm.SHARD_ASCENSION_TARGET == 15, "SHARD_ASCENSION_TARGET is 15")
	_check(_tm.count_victory_alliances(&"empire") == 0, "own minors don't count as victory alliances")

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
