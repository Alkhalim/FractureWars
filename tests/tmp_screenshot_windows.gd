extends SceneTree
## Temp tool: opens every major HUD window/dialog one at a time and screenshots
## each — audit of empty/unused space in windows. Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _steps: Array = []  # [frame_offset, callable, shot_name]
var _base_frame := 45
var _intro_done := false

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _pop_last_dialog() -> void:
	# Ad-hoc dialogs are add_child'ed to the HUD last — free the newest child
	var last := _hud.get_child(_hud.get_child_count() - 1)
	_hud.remove_child(last)
	last.queue_free()

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _hud == null and _campaign.has_node("UILayer/HUD"):
		_hud = _campaign.get_node("UILayer/HUD")
	# Faction intro (Task 1): HUD._ready shows it automatically on a fresh
	# game (faction_intro_shown starts false) — capture it FIRST, then flip
	# the flag and free the dialog child before the other phases run so it
	# doesn't sit on top of everything below.
	if not _intro_done:
		if _frames == 15:
			_shot("win_faction_intro.png")
		elif _frames == 18:
			var gm: Node = root.get_node("/root/GameManager")
			gm.state.faction_intro_shown = true
			if _hud and _hud.get_child_count() > 0:
				_pop_last_dialog()
			_intro_done = true
	if _frames == _base_frame - 5:
		_hud = _campaign.get_node("UILayer/HUD")
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		var city_id := StringName()
		for cid in gm.state.cities:
			if gm.state.cities[cid].faction_id == pid:
				city_id = cid
				break
		var army_id := StringName()
		for aid in gm.state.armies:
			if gm.state.armies[aid].faction_id == pid:
				army_id = aid
				break
		print("CITY: %s  ARMY: %s" % [city_id, army_id])
		# Build the step list: [open_call, close_call, shot_name]
		_steps = [
			[func(): _hud.call("_toggle_economy_panel"), func(): _hud.call("_toggle_economy_panel"), "win_economy.png"],
			[func(): _hud.call("_toggle_diplomacy_panel"), func(): _hud.call("_toggle_diplomacy_panel"), "win_diplomacy.png"],
			[func(): _hud.call("_toggle_research_panel"), func(): _hud.call("_toggle_research_panel"), "win_research.png"],
			[func(): _hud.call("_toggle_policies_panel"), func(): _hud.call("_toggle_policies_panel"), "win_policies.png"],
			[func(): _hud.call("_toggle_faction_overview"), func(): _hud.call("_toggle_faction_overview"), "win_faction_overview.png"],
			[func(): _hud.call("_show_city_panel", city_id), func(): _hud.call("_hide_city_panel"), "win_city.png"],
			[func(): _hud.call("_show_event_dialog", {
				"title": "Wandering Prophet",
				"text": "A ragged prophet arrives at your gates, speaking of shard-fire and ruin. The crowd grows restless.",
				"choice_a": "Welcome the prophet", "choice_b": "Turn them away"}),
				func(): _pop_last_dialog(), "win_event_dialog.png"],
			[func(): _hud.call("_show_turn_summary"), func(): _pop_last_dialog(), "win_turn_summary.png"],
		]
		if army_id != StringName():
			_steps.append([func(): _hud.call("_show_army_split_dialog", army_id), func(): _pop_last_dialog(), "win_army_split.png"])
			_steps.append([func(): _hud.call("_show_disband_dialog", army_id), func(): _pop_last_dialog(), "win_disband.png"])
	# Each step: open at t, shot at t+6, close at t+8; next step at t+10
	var t := _frames - _base_frame
	if t >= 0 and _steps.size() > 0:
		var idx := t / 10
		var phase := t % 10
		if idx < _steps.size():
			var step: Array = _steps[idx]
			if phase == 0:
				step[0].call()
			elif phase == 6:
				_shot(step[2])
			elif phase == 8:
				step[1].call()
		elif idx >= _steps.size():
			print("ALL DONE")
			quit()
	return false
