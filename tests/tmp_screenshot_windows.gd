extends SceneTree
## Temp tool: opens every major HUD window/dialog one at a time and screenshots
## each — audit of empty/unused space in windows. Delete after use.

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _steps: Array = []  # [frame_offset, callable, shot_name]
var _base_frame := 45
var _intro_done := false
# UI Polish Wave Task P1: faction selectable via trailing cmdline arg so the
# same sweep can be run for both empire and skulloath without duplicating the
# script — `-- empire` / `-- skulloath` (default skulloath, matches prior use).
var _faction_id := &"skulloath"

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_faction_id = StringName(args[0])
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(_faction_id, false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fname := "%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

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
			[func(): _hud.call("_toggle_victory_panel"), func(): _hud.call("_toggle_victory_panel"), "win_victory.png"],
			[func(): _hud.call("_toggle_diplomacy_panel"), func(): _hud.call("_toggle_diplomacy_panel"), "win_diplomacy.png"],
			[func(): _hud.call("_toggle_research_panel"), func(): _hud.call("_toggle_research_panel"), "win_research.png"],
			[func(): _hud.call("_toggle_faction_overview"), func(): _hud.call("_toggle_faction_overview"), "win_faction_overview.png"],
			[func(): _hud.call("_show_city_panel", city_id), func(): _hud.call("_hide_city_panel"), "win_city.png"],
			[func(): _hud.call("_show_event_dialog", {
				"title": "Wandering Prophet",
				"text": "A ragged prophet arrives at your gates, speaking of shard-fire and ruin. The crowd grows restless.",
				"choice_a": "Welcome the prophet", "choice_b": "Turn them away"}),
				func(): _pop_last_dialog(), "win_event_dialog.png"],
			[func(): _hud.call("_show_turn_summary"), func(): _pop_last_dialog(), "win_turn_summary.png"],
		]
		# Policies/Senate panel is Empire-only (_create_economy_panel only
		# builds _policies_panel when player_faction_id == "empire") — only
		# probe it when running the sweep as Empire, or _toggle_policies_panel
		# hits a null _policies_panel and throws (Task 4 windowed-sweep fix).
		if pid == &"empire":
			_steps.append([func(): _hud.call("_toggle_policies_panel"), func(): _hud.call("_toggle_policies_panel"), "win_policies.png"])
		if army_id != StringName():
			_steps.append([func(): _hud.call("_show_army_split_dialog", army_id), func(): _pop_last_dialog(), "win_army_split.png"])
			_steps.append([func(): _hud.call("_show_disband_dialog", army_id), func(): _pop_last_dialog(), "win_disband.png"])
			# Panel-layout audit (army panel + tile info + minimap, all on
			# screen together): the starting army sits on the starting city,
			# so selecting it via the same path a player click takes
			# (_select_army) opens the army panel AND the tile-info panel
			# (region_panel) at once — _select_army emits both army_selected
			# and hex_tile_selected for the army's hex.
			_steps.append([func(): _campaign.call("_select_army", army_id), func(): _campaign.call("_deselect_all"), "win_panels_layout.png"])
	# Each step: open at t, shot at t+20, close at t+24; next step at t+30.
	# Shot offset bumped from +6 to +20 (Task 4 windowed-sweep fix) — +6
	# landed mid-fade on panels that modulate-tween in over 0.2s, so shots
	# caught them translucent; +20 frames clears that at any reasonable
	# frame rate.
	var t := _frames - _base_frame
	if t >= 0 and _steps.size() > 0:
		var idx := t / 30
		var phase := t % 30
		if idx < _steps.size():
			var step: Array = _steps[idx]
			if phase == 0:
				step[0].call()
			elif phase == 20:
				_shot(step[2])
			elif phase == 24:
				step[1].call()
		elif idx >= _steps.size():
			print("ALL DONE")
			quit()
	return false
