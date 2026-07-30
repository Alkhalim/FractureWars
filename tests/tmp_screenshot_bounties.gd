extends SceneTree
## Temp tool: verifies bounty corner icons render on the campaign map + hover
## tooltip wiring compiles, then verifies the resource-bar "Bounties: N" entry
## and its hover tooltip. Delete after use.

var _frames := 0
var _campaign: Node = null
var _bounty_coord := Vector2i(-9999, -9999)
var _pinned := false
var _special_coord := Vector2i(-9999, -9999)

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

	if _frames >= 40 and _frames < 66 and _bounty_coord != Vector2i(-9999, -9999):
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

	# ── Phase 3: settlement founding preview lists claimable bounties ──────
	if _frames == 62:
		var gm: Node = root.get_node("/root/GameManager")
		var capital: CityState = null
		for city_id in gm.state.cities:
			var city: CityState = gm.state.cities[city_id]
			if city.faction_id == gm.state.player_faction_id and city.is_capital:
				capital = city
				break
		if capital == null:
			print("WARNING: no player capital found for settle-preview phase")
		else:
			# Populate _settlement_valid_tiles first, then hunt for a valid tile
			# that has an unclaimed, bounty-free land hex within CLAIM_RADIUS (2)
			# of it — craft the bounty there so the chosen valid tile actually
			# claims it (exercises the real _show_settlement_preview render path
			# rather than the early-return fallback).
			_campaign.call("_on_settlement_placement_requested", capital.city_id)
			var valid_tiles = _campaign.get("_settlement_valid_tiles")
			var map = gm.state.hex_map
			var settle_hex := Vector2i(-9999, -9999)
			var bounty_coord := Vector2i(-9999, -9999)
			if valid_tiles:
				for v in valid_tiles:
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var cand := Vector2i(v.x + dx, v.y + dy)
							if HexHelper.hex_distance(v, cand) > 2:
								continue
							var ctile = map.get_tile(cand)
							if ctile == null or ctile.terrain == Enums.TerrainType.WATER:
								continue
							if ctile.bounty_id != &"":
								continue
							if BountySystem.claimant_for(cand) != &"":
								continue
							settle_hex = v
							bounty_coord = cand
							break
						if bounty_coord != Vector2i(-9999, -9999):
							break
					if bounty_coord != Vector2i(-9999, -9999):
						break
			var found_valid := bounty_coord != Vector2i(-9999, -9999)
			if not found_valid:
				# Fallback per brief: exercise the function even without a
				# guaranteed intersection (won't render a panel, but confirms
				# no crash / compile error along this path).
				print("WARNING: no valid-tile/bounty intersection found; using fallback hex")
				settle_hex = capital.hex_pos
				for coord in map.tiles:
					var tile = map.tiles[coord]
					if tile.terrain == Enums.TerrainType.WATER or tile.bounty_id != &"":
						continue
					var d := HexHelper.hex_distance(capital.hex_pos, coord)
					if d < 4 or d > 6:
						continue
					bounty_coord = coord
					break
			if bounty_coord != Vector2i(-9999, -9999):
				map.get_tile(bounty_coord).bounty_id = &"orchards"
			print("SETTLE-PREVIEW BOUNTY CRAFTED AT: ", bounty_coord, " claimant=[", BountySystem.claimant_for(bounty_coord), "]")
			print("SETTLE-PREVIEW TILE: ", settle_hex, " in_valid_set=", found_valid)
			var cam: Camera2D = _campaign.get("camera")
			if cam:
				cam.position = _campaign.call("_hex_to_pixel", settle_hex)
				cam.zoom = Vector2(1.5, 1.5)
			_campaign.call("_show_settlement_preview", settle_hex)

	if _frames == 64:
		var img3 := root.get_viewport().get_texture().get_image()
		img3.save_png("user://win_settle_preview.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_settle_preview.png"))

	# ── Phase 4: special-deposit diamond marker + hover tooltip ────────────
	if _frames == 66:
		# Dismiss the Phase 3 settlement-preview overlay (still open) so its
		# candidate-site rings/labels don't cover the special marker, and hide
		# the Phase 2 resource-bar tooltip (never got a real mouse_exited).
		_campaign.call("_cancel_settlement_placement")
		var hud2: Node = _campaign.get_node("UILayer/HUD")
		var bar_tip2: Node = hud2.get("_bounty_bar_tooltip")
		if bar_tip2:
			bar_tip2.visible = false
		var gm: Node = root.get_node("/root/GameManager")
		var map = gm.state.hex_map
		# Pick a deposit tile a few hexes clear of any city marker — city art
		# (z_index 2, sizable radius) draws above the special marker (z_index
		# 1) and, at this zoom, can visually cover a same-hex OR adjacent-hex
		# deposit.
		var city_hexes: Array[Vector2i] = []
		for city_id in gm.state.cities:
			city_hexes.append(gm.state.cities[city_id].hex_pos)
		for coord in map.tiles:
			var tile = map.tiles[coord]
			if tile.special_id == &"":
				continue
			var clear_of_cities := true
			for chex in city_hexes:
				if HexHelper.hex_distance(coord, chex) < 3:
					clear_of_cities = false
					break
			if clear_of_cities:
				_special_coord = coord
				break
		print("SPECIAL DEPOSIT TILE: ", _special_coord, " type=", map.get_tile(_special_coord).special_id if _special_coord != Vector2i(-9999, -9999) else &"")
		if _special_coord != Vector2i(-9999, -9999):
			var cam: Camera2D = _campaign.get("camera")
			if cam:
				cam.position = _campaign.call("_hex_to_pixel", _special_coord)
				cam.zoom = Vector2(1, 1)

	if _frames == 78:
		if _special_coord != Vector2i(-9999, -9999):
			var center := root.get_viewport().get_visible_rect().size / 2
			root.get_viewport().warp_mouse(center)
			_campaign.call("_update_bounty_hover", _special_coord)
			var tip: Node = _campaign.get("_bounty_tooltip")
			if tip:
				print("SPECIAL TOOLTIP visible=", tip.visible, " text=[", tip.get_node("Text").text, "]")
			else:
				print("WARNING: _bounty_tooltip is null after special _update_bounty_hover")
		else:
			print("WARNING: no special deposit tile found on the map")

	if _frames == 80:
		var img4 := root.get_viewport().get_texture().get_image()
		img4.save_png("user://win_special_marker.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_special_marker.png"))
		quit()
	return false
