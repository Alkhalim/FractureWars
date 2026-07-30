extends SceneTree
## Temp tool: headless smoke test — new game, run 14 turns via the real
## end-turn flow, print faction mechanic states (exercises the new dilemma/AI
## paths for all factions). Delete after use.

var _started := false
var _frames := 0

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false, 0)
	gm._is_transitioning = false
	var tm: Node = root.get_node("/root/TurnManager")
	tm.start_game()
	_started = true

func _process(_delta: float) -> bool:
	if not _started:
		return false
	_frames += 1
	var gm: Node = root.get_node("/root/GameManager")
	var tm: Node = root.get_node("/root/TurnManager")
	if gm.state.current_turn >= 15 or _frames > 6000:
		print("SMOKE DONE turn=%d frames=%d" % [gm.state.current_turn, _frames])
		for fid in [&"skulloath", &"gladehost", &"tainted_jade", &"forsaken", &"sunblessed", &"shardhorde", &"moonspear"]:
			var fs = gm.state.faction_states.get(fid)
			if fs:
				print("  %s: corr=%d harm=%d lastSeason=%d taintF=%d espN=%d faith=%d wis=%d reso=%d shards=%d" % [
					fid, fs.corruption, fs.harmony, fs.last_season, fs.taint_focus,
					fs.espionage_network, fs.solar_faith, fs.wisdom,
					fs.shard_resonance.size(), fs.owned_shards.size()])
		quit()
		return false
	if tm.is_player_turn:
		var eb: Node = root.get_node("/root/EventBus")
		eb.end_turn_pressed.emit()
	return false
