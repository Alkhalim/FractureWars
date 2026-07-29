extends SceneTree
## Temp tool: verifies bounty corner icons render on the campaign map + hover
## tooltip wiring compiles, then verifies the resource-bar "Bounties: N" entry
## and its hover tooltip. Delete after use.

var _frames := 0
var _campaign: Node = null
var _bounty_coord := Vector2i(-9999, -9999)
var _pinned := false

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	if _frames == 40:
		var gm: Node = root.get_node("/root/GameManager")
		var map = gm.state.hex_map
		for coord in map.tiles:
			var tile = map.tiles[coord]
			if tile.bounty_id != &"":
				_bounty_coord = coord
				break
		print("BOUNTY TILE: ", _bounty_coord)
		# Disable fog so the icon + tooltip fog-gate can't hide the result, then
		# force every bounty marker visible (mirrors what a real fog update would do).
		_campaign.set("_fog_of_war_enabled", false)
		_campaign.set("_fog_dirty", true)
		_campaign.call("_refresh_bounty_marker_visibility")

	if _frames >= 40 and _bounty_coord != Vector2i(-9999, -9999):
		var cam: Camera2D = _campaign.get("camera")
		if cam:
			cam.position = _campaign.call("_hex_to_pixel", _bounty_coord)
			cam.zoom = Vector2(2, 2)
			_pinned = true

	if _frames == 54 and _bounty_coord != Vector2i(-9999, -9999):
		# Exercise the hover tooltip directly (no real mouse-motion event fires
		# in a headed -s run without simulated input) and center the mouse so the
		# tooltip lands on-screen for the frame-55 screenshot.
		var center := root.get_viewport().get_visible_rect().size / 2
		root.get_viewport().warp_mouse(center)
		_campaign.call("_update_bounty_hover", _bounty_coord)
		var tip: Node = _campaign.get("_bounty_tooltip")
		if tip:
			print("TOOLTIP visible=", tip.visible, " text=[", tip.get_node("Text").text, "]")
		else:
			print("WARNING: _bounty_tooltip is null after _update_bounty_hover")

	if _frames == 55:
		if not _pinned:
			print("WARNING: no bounty tile found / camera not pinned")
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://win_bounty_icons.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_bounty_icons.png"))

	# ── Phase 2: resource-bar "Bounties: N" entry + hover tooltip ──────────
	if _frames == 56:
		# Dismiss the turn-1 tutorial hint so it doesn't cover the tooltip.
		var hud: Node = _campaign.get_node("UILayer/HUD")
		var overlay: Node = hud.get("_tutorial_overlay")
		if overlay:
			overlay.queue_free()
			hud.set("_tutorial_overlay", null)

	if _frames == 58:
		var gm: Node = root.get_node("/root/GameManager")
		var hud: Node = _campaign.get_node("UILayer/HUD")
		var n_before: int = BountySystem.bounties_of_faction(gm.state.player_faction_id).size()
		print("BOUNTIES HELD BEFORE CRAFT: ", n_before)
		if n_before == 0:
			# Craft a claim: find the player capital, then a land tile at hex
			# distance 2 with no bounty yet, and give it one.
			var capital: CityState = null
			for city_id in gm.state.cities:
				var city: CityState = gm.state.cities[city_id]
				if city.faction_id == gm.state.player_faction_id and city.is_capital:
					capital = city
					break
			if capital:
				var map = gm.state.hex_map
				var crafted := false
				for coord in map.tiles:
					var tile = map.tiles[coord]
					if tile.terrain == Enums.TerrainType.WATER:
						continue
					if HexHelper.hex_distance(capital.hex_pos, coord) != 2:
						continue
					if tile.bounty_id != &"":
						continue
					tile.bounty_id = &"orchards"
					crafted = true
					print("CRAFTED BOUNTY CLAIM AT: ", coord)
					break
				if not crafted:
					print("WARNING: no eligible tile found to craft a bounty claim")
			else:
				print("WARNING: no player capital found for crafted claim")
		hud.call("_update_resource_display")
		print("BOUNTIES HELD AFTER CRAFT: ", BountySystem.bounties_of_faction(gm.state.player_faction_id).size())
		print("BOUNTY BAR LABEL: text=[", hud.get("bounty_bar_label").text, "] visible=", hud.get("bounty_bar_label").visible)
		hud.call("_on_bounty_bar_hover")
		var bar_tip: Node = hud.get("_bounty_bar_tooltip")
		if bar_tip:
			print("BOUNTY BAR TOOLTIP visible=", bar_tip.visible, " text=[", bar_tip.get_node("TooltipText").text, "]")
		else:
			print("WARNING: _bounty_bar_tooltip is null after _on_bounty_bar_hover")

	if _frames == 60:
		var img2 := root.get_viewport().get_texture().get_image()
		img2.save_png("user://win_bounty_bar.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_bounty_bar.png"))
		quit()
	return false
