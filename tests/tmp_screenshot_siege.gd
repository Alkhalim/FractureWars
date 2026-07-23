extends SceneTree
## Temp tool: visual verification for the siege pressure meter UI (Task 7).
## Puts an enemy city under siege at ~60% of its threshold, then screenshots
## the map's turns-to-fall badge and the city panel's bar + "falls in ~N
## turns" readout. Run WITHOUT --headless:
##   & <godot> --path . --resolution 1920x1080 -s res://tests/tmp_screenshot_siege.gd
## Delete after use.

var _frames := 0
var _campaign: Node = null
var _city_id: StringName = &""
var _city_pos := Vector2.ZERO
var _eb: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true  # Block new_game's campaign scene transition
	gm.new_game(&"empire", false)
	gm._is_transitioning = false

	_eb = root.get_node("/root/EventBus")
	var cs: CitySystem = gm.city_system

	# Pick a city not owned by the player or the besieger, then start a siege.
	# start_siege() no-ops on allied/friendly relations, so try a few candidates.
	for cid in gm.state.cities:
		var c = gm.state.cities[cid]
		if c.faction_id == &"empire" or c.faction_id == &"skulloath":
			continue
		cs.start_siege(cid, &"skulloath")
		if c.is_under_siege:
			_city_id = cid
			break

	if _city_id == &"":
		print("NO SIEGABLE CITY FOUND")
	else:
		var city = gm.state.cities[_city_id]
		var threshold: int = cs.get_siege_threshold(city)
		city.siege_turns = float(threshold) * 0.6
		print("SIEGE SET: city=%s turns=%f threshold=%d" % [_city_id, city.siege_turns, threshold])

	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

	if _city_id != &"":
		_city_pos = _campaign.call("_hex_to_pixel", gm.state.cities[_city_id].hex_pos)
	# Reveal the map so the besieged city's marker renders at full brightness
	# instead of dimmed/hidden by fog of war (it's an independent city, likely
	# outside the player's starting line-of-sight).
	_campaign.set("_fog_of_war_enabled", false)
	_campaign.set("_fog_dirty", true)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	# start_siege()/the initial pressure set in _start() happened before the
	# campaign scene (and thus campaign.gd's badge-refresh listeners) existed,
	# so re-fire the pressure signal now that they're wired, to populate the
	# map badge.
	if _frames == 5 and _city_id != &"":
		var gm: Node = root.get_node("/root/GameManager")
		var city = gm.state.cities[_city_id]
		var cs: CitySystem = gm.city_system
		var threshold := cs.get_siege_threshold(city)
		_eb.siege_progress_changed.emit(_city_id, city.siege_turns, threshold)

	# Camera controller edge-pans/zoom-lerps on its own each frame, so pin it
	# every frame rather than once. Offset the city left of center so it
	# isn't hidden behind the city panel once that opens.
	if _city_pos != Vector2.ZERO:
		var cam: Camera2D = _campaign.get("camera")
		cam.position = _city_pos + Vector2(240, 0)
		cam.zoom = Vector2(1.6, 1.6)
		cam.set("_target_zoom", 1.6)

	if _frames == 20:
		_shot("siege_badge.png")
	if _frames == 25 and _city_id != &"":
		var hud: Control = _campaign.get_node("UILayer/HUD")
		hud.call("_show_city_panel", _city_id)
	if _frames == 35:
		_shot("siege_meter.png")
		quit()
	return false
