extends SceneTree
## Temp tool: UI Polish Wave Task P1 — zooms the campaign camera to MAX_ZOOM
## (3.0, campaign_camera.gd) centered on the player's capital city and
## screenshots it, to verify map-label sharpness (region/city name Labels)
## after enabling MSDF on the bundled fonts. Also takes a zoomed-OUT
## comparison shot (MIN_ZOOM 0.5) for reference. Delete after use.

var _frames := 0
var _campaign: Node = null
var _city_pos := Vector2.ZERO

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false, 0)
	gm._is_transitioning = false
	# Skip the faction-intro dialog and tutorial-hint overlay entirely (both
	# would otherwise sit on top of the map when the HUD's _ready() runs) —
	# this tool only cares about map-label sharpness, not the onboarding flow.
	gm.state.faction_intro_shown = true
	gm.state.tutorial_enabled = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 20:
		var gm: Node = root.get_node("/root/GameManager")
		# Reveal the map so fog-of-war doesn't hide the label
		_campaign.set("_fog_of_war_enabled", false)
		_campaign.set("_fog_dirty", true)
		var pid: StringName = gm.state.player_faction_id
		var city_id := StringName()
		for cid in gm.state.cities:
			if gm.state.cities[cid].faction_id == pid:
				city_id = cid
				break
		if city_id != StringName():
			var city = gm.state.cities[city_id]
			_city_pos = _campaign.call("_hex_to_pixel", city.hex_pos)
			print("CITY: %s at %s" % [city_id, str(_city_pos)])
	if _frames >= 20 and _city_pos != Vector2.ZERO:
		var cam: Camera2D = _campaign.get("camera")
		cam.position = _city_pos
		# Frames 20-39: MAX_ZOOM (fully zoomed in) — the case under test.
		# Frames 40-59: MIN_ZOOM (fully zoomed out) — comparison reference.
		if _frames < 40:
			cam.zoom = Vector2(3.0, 3.0)
			cam.set("_target_zoom", 3.0)
		else:
			cam.zoom = Vector2(0.5, 0.5)
			cam.set("_target_zoom", 0.5)
	if _frames == 39:
		_shot("map_zoomed_in_label.png")
	if _frames == 59:
		_shot("map_zoomed_out_label.png")
		quit()
	return false
