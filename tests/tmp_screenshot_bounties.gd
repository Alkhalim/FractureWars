extends SceneTree
## Temp tool: verifies bounty corner icons render on the campaign map + hover
## tooltip wiring compiles, then verifies the resource-bar "Bounties: N" entry
## and its hover tooltip. Delete after use.

var _frames := 0
var _campaign: Node = null
var _bounty_coord := Vector2i(-9999, -9999)
var _pinned := false
var _special_coord := Vector2i(-9999, -9999)
var _landmark_coord := Vector2i(-9999, -9999)
var _gallery_pts: Array[Vector2i] = []
var _gallery_cam_pos := Vector2.ZERO

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	# Unrelated feature (added by a later SDD cycle): the once-per-game faction
	# onboarding dialog pops up on HUD _ready() and would cover the whole map
	# for this harness's bounty-icon screenshot. Pre-mark it shown so it never
	# appears — nothing here exercises that dialog.
	gm.state.faction_intro_shown = true
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

	if _frames == 70 and _special_coord != Vector2i(-9999, -9999):
		# Extra debug capture, taken BEFORE the hover tooltip (frame 78) so the
		# new deposit-tier art is visible unobstructed (the tooltip lands
		# right on top of the tile-centered special marker at frame 80). Also
		# hide the still-visible Phase-1 bounty tooltip (never got a real
		# mouse_exited, so it lingers at the same screen-center-ish spot).
		# Give the renderer a couple frames to pick up the visibility change
		# before capturing (get_texture() reflects the prior rendered frame).
		var leftover_tip: Node = _campaign.get("_bounty_tooltip")
		if leftover_tip:
			leftover_tip.visible = false

	if _frames == 73 and _special_coord != Vector2i(-9999, -9999):
		var img_dbg := root.get_viewport().get_texture().get_image()
		img_dbg.save_png("user://win_special_marker_notip.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_special_marker_notip.png"))

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

	# ── Phase 5: Landmark star marker + hover tooltip ───────────────────────
	if _frames == 82:
		var gm: Node = root.get_node("/root/GameManager")
		var map = gm.state.hex_map
		for coord in map.tiles:
			var tile = map.tiles[coord]
			if tile.landmark_id != &"":
				_landmark_coord = coord
				break
		print("LANDMARK TILE: ", _landmark_coord, " type=", map.get_tile(_landmark_coord).landmark_id if _landmark_coord != Vector2i(-9999, -9999) else &"")
		# Fog is already disabled (Phase 1); refresh so the star marker shows.
		_campaign.set("_fog_dirty", true)
		_campaign.call("_refresh_bounty_marker_visibility")
		if _landmark_coord != Vector2i(-9999, -9999):
			var cam: Camera2D = _campaign.get("camera")
			if cam:
				cam.position = _campaign.call("_hex_to_pixel", _landmark_coord)
				cam.zoom = Vector2(1, 1)

	if _frames == 90 and _landmark_coord != Vector2i(-9999, -9999):
		# Extra debug capture, taken BEFORE the hover tooltip (frame 94) so the
		# new landmark-tier art is visible unobstructed (the tooltip lands
		# right on top of the tile-centered marker at frame 96, same as the
		# special-deposit phase above). Hide any leftover tooltip from an
		# earlier phase too.
		var leftover_tip2: Node = _campaign.get("_bounty_tooltip")
		if leftover_tip2:
			leftover_tip2.visible = false

	if _frames == 93 and _landmark_coord != Vector2i(-9999, -9999):
		var img_dbg2 := root.get_viewport().get_texture().get_image()
		img_dbg2.save_png("user://win_landmark_marker_notip.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_landmark_marker_notip.png"))

	if _frames == 94:
		if _landmark_coord != Vector2i(-9999, -9999):
			var center := root.get_viewport().get_visible_rect().size / 2
			root.get_viewport().warp_mouse(center)
			_campaign.call("_update_bounty_hover", _landmark_coord)
			var tip: Node = _campaign.get("_bounty_tooltip")
			if tip:
				print("LANDMARK TOOLTIP visible=", tip.visible, " text=[", tip.get_node("Text").text, "]")
			else:
				print("WARNING: _bounty_tooltip is null after landmark _update_bounty_hover")
		else:
			print("WARNING: no landmark tile found on the map")

	if _frames == 96:
		var img5 := root.get_viewport().get_texture().get_image()
		img5.save_png("user://win_landmark_marker.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_landmark_marker.png"))

	# ── Phase 6: GALLERY — landmark + deposit + bounty cluster, one frame ──
	# Seed 0 doesn't naturally place all three tiers next to each other, so
	# this crafts a tight cluster near the Phase 5 landmark tile: a deposit
	# and two distinct bounty types on nearby clear land tiles, then reframes
	# the camera on the cluster's centroid at zoom 1.6 for the final art
	# verdict. Crafting is fine here — this is a presentation shot, not a
	# gameplay assertion.
	if _frames == 98:
		if _landmark_coord == Vector2i(-9999, -9999):
			print("WARNING: gallery phase skipped, no landmark tile found")
		else:
			var gm: Node = root.get_node("/root/GameManager")
			var map = gm.state.hex_map
			var craft_targets: Array[Vector2i] = []
			var used: Dictionary = {_landmark_coord: true}
			for radius in range(1, 4):
				if craft_targets.size() >= 3:
					break
				for coord in map.tiles:
					if craft_targets.size() >= 3:
						break
					if used.has(coord):
						continue
					if HexHelper.hex_distance(_landmark_coord, coord) != radius:
						continue
					var t = map.tiles[coord]
					if t.terrain == Enums.TerrainType.WATER:
						continue
					if t.bounty_id != &"" or t.special_id != &"" or t.landmark_id != &"":
						continue
					craft_targets.append(coord)
					used[coord] = true
			if craft_targets.size() < 3:
				print("WARNING: gallery could not find 3 clear land tiles near the landmark to craft")
			else:
				map.tiles[craft_targets[0]].special_id = &"moonsilver"
				map.tiles[craft_targets[1]].bounty_id = &"orchards"
				map.tiles[craft_targets[2]].bounty_id = &"vineyards"
				print("GALLERY CRAFTED: deposit=", craft_targets[0], " bounty1=", craft_targets[1], " bounty2=", craft_targets[2])
			_gallery_pts = [_landmark_coord]
			for c in craft_targets:
				_gallery_pts.append(c)
			_campaign.call("_create_bounty_markers")
			_campaign.set("_fog_dirty", true)
			var centroid := Vector2.ZERO
			for p in _gallery_pts:
				centroid += (_campaign.call("_hex_to_pixel", p) as Vector2)
			centroid /= _gallery_pts.size()
			_gallery_cam_pos = centroid
			# Hide any leftover tooltip from Phase 5.
			var leftover_tip3: Node = _campaign.get("_bounty_tooltip")
			if leftover_tip3:
				leftover_tip3.visible = false
			# campaign_camera.gd smoothly lerps `zoom` back toward its own
			# internal `_target_zoom` (stuck at the never-touched default 1.0,
			# since no wheel event ever fires in this harness) and drags
			# `position` along with it via a "keep the point under the cursor
			# stable" adjustment anchored at a never-set (0,0) zoom-focus — a
			# one-shot zoom assignment other than 1.0 gets silently pulled
			# away over the next few frames (Phase 1's zoom=2 close-up avoids
			# this only because it reasserts every frame in its own window;
			# Phases 4/5 avoid it only because they happen to set zoom to
			# exactly 1.0, the untouched default target). Setting
			# `_target_zoom` to match stops the lerp at the source instead of
			# fighting it frame-by-frame.
			var cam: Camera2D = _campaign.get("camera")
			if cam:
				cam.position = _gallery_cam_pos
				cam.zoom = Vector2(1.6, 1.6)
				cam.set("_target_zoom", 1.6)

	if _frames == 109:
		var img6 := root.get_viewport().get_texture().get_image()
		img6.save_png("user://win_art_gallery.png")
		print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://win_art_gallery.png"))
		quit()
	return false
