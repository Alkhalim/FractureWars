extends SceneTree
## W5 verification tool (UI Polish Wave 2): map sketch (coastline + terrain),
## Shardhorde campaign start (camera on largest horde, turn-1 vision aligned
## with army positions), and the Economy Overview panel next to the top bar
## (net income reconciliation). Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_w5.gd
## Kept committed (matches the W2/W3/W4 precedent of keeping windowed
## screenshot harnesses rather than deleting them).

var _frames := 0
var _phase := 0 # 0=faction select, 1=shardhorde campaign, 2=empire campaign
var _menu: Node = null
var _campaign: Node = null
var _hud: Control = null
var _phase_start_frame := 0

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var scene: PackedScene = load("res://scenes/main/main_menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _log_army_vision(faction_id: StringName) -> void:
	var gm: Node = root.get_node("/root/GameManager")
	print("--- army/vision log (%s) ---" % faction_id)
	for aid in gm.state.armies:
		var a = gm.state.armies[aid]
		if a.faction_id == faction_id:
			print("  ARMY %s hex_pos=%s" % [aid, str(a.hex_pos)])
	var cam = _campaign.get("camera")
	if cam:
		print("  CAMERA pos=%s" % str(cam.position))
	var vis = _campaign.get("_visible_tile_cache")
	if vis != null:
		for aid in gm.state.armies:
			var a = gm.state.armies[aid]
			if a.faction_id == faction_id:
				print("  army %s IN visible_tile_cache: %s" % [aid, vis.has(a.hex_pos)])

func _process(_delta: float) -> bool:
	_frames += 1
	var t := _frames - _phase_start_frame

	if _phase == 0: # ── Faction select: map sketch ──
		if t == 10:
			_menu.call("_show_faction_select")
		elif t == 20:
			_menu.call("_on_faction_list_clicked", &"tainted_jade")
		elif t == 35:
			_shot("w5_sketch_tainted_jade.png")
		elif t == 40:
			_menu.call("_on_faction_list_clicked", &"shardhorde")
		elif t == 55:
			_shot("w5_sketch_shardhorde.png") # confirms "Nomadic" caption + new layers coexist
		elif t == 60:
			_menu.queue_free()
			_menu = null
			_phase = 1
			_phase_start_frame = _frames
			var gm: Node = root.get_node("/root/GameManager")
			# campaign.gd._ready() only calls TurnManager.start_game() (the
			# real turn-1 kickoff, incl. the synchronous fog refresh) the
			# FIRST time a campaign loads this process -- reset so THIS
			# scene's load is a genuinely fresh "first campaign load" too,
			# same as any real player's actual first game of a session.
			gm.remove_meta("game_started")
			gm._is_transitioning = true
			gm.new_game(&"shardhorde", false, 0)
			gm._is_transitioning = false
			var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
			_campaign = scene.instantiate()
			root.add_child(_campaign)

	elif _phase == 1: # ── Shardhorde campaign start: camera + vision ──
		if t == 8:
			# Shot early (not at the usual +40 frames other harnesses use) —
			# there's no real mouse in this automated run, so
			# campaign_camera.gd's edge-pan treats the OS cursor's last real
			# position (often near a screen edge) as a continuous pan
			# input and drifts the camera off the horde over many frames.
			# That's a headless-automation artifact, not a real player
			# session (a real player's cursor isn't glued to one spot for
			# 40 unattended frames) — shoot right after _ready() settles
			# instead, while the fix's initial placement is still exact.
			_log_army_vision(&"shardhorde")
			_shot("w5_shardhorde_start.png")
		elif t == 45:
			_campaign.queue_free()
			_campaign = null
			_phase = 2
			_phase_start_frame = _frames
			var gm: Node = root.get_node("/root/GameManager")
			gm.remove_meta("game_started") # see shardhorde phase's comment above
			gm._is_transitioning = true
			gm.new_game(&"empire", false, 0)
			gm._is_transitioning = false
			var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
			_campaign = scene.instantiate()
			root.add_child(_campaign)

	elif _phase == 2: # ── Empire campaign: economy panel + top bar ──
		if t == 40:
			_hud = _campaign.get_node("UILayer/HUD")
			_hud.call("_toggle_economy_panel")
		elif t == 60:
			_shot("w5_eco_panel_topbar.png")
		elif t == 64:
			print("ALL DONE")
			quit()

	return false
