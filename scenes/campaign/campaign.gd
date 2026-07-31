extends Node2D

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]

# Hex outer radius (center to vertex) for flat-top hexes
const HEX_RADIUS := HexMapData.HEX_RADIUS  # single source of truth (shared with camera clamp)
# Derived spacing
const HEX_H_SPACING := HexMapData.HEX_H_SPACING # radius * 1.5 - horizontal center-to-center
const HEX_V_SPACING := HexMapData.HEX_V_SPACING # sqrt(3) * radius
const HEX_V_OFFSET := HEX_V_SPACING * 0.5 # Odd column vertical shift

# Maps neighbor direction index → hex polygon edge start corner.
# Edge e goes from hex_points[e] to hex_points[(e+1)%6].
# DIRECTIONS_EVEN/ODD don't follow the same angular order as polygon corners,
# so we need this lookup to draw the correct hex edge for each neighbor direction.
const DIR_TO_EDGE_EVEN := [0, 5, 4, 2, 3, 1]
const DIR_TO_EDGE_ODD  := [0, 5, 4, 3, 2, 1]

# Terrain base colors
# Base colors matching the v2 gouache tile palette (also used for shoreline
# bleed bands, the overview sprite, and the minimap)
const TERRAIN_COLORS := {
	Enums.TerrainType.PLAINS: Color(0.55, 0.55, 0.32),
	Enums.TerrainType.FOREST: Color(0.24, 0.35, 0.21),
	Enums.TerrainType.MOUNTAINS: Color(0.45, 0.42, 0.37),
	Enums.TerrainType.DESERT: Color(0.71, 0.62, 0.42),
	Enums.TerrainType.SWAMP: Color(0.32, 0.34, 0.22),
	Enums.TerrainType.WETLANDS: Color(0.30, 0.42, 0.36),
	Enums.TerrainType.TUNDRA: Color(0.66, 0.68, 0.66),
	Enums.TerrainType.SHARD_WASTES: Color(0.42, 0.36, 0.44),
	Enums.TerrainType.WATER: Color(0.13, 0.20, 0.34),
	Enums.TerrainType.JUNGLE: Color(0.16, 0.30, 0.17),
}

# Border color between tiles
const HEX_BORDER_COLOR := Color(0.12, 0.10, 0.08)

# Terrain elevation offsets (positive = raised, negative = lowered)
const TERRAIN_ELEVATION := {
	Enums.TerrainType.PLAINS: 0.0,
	Enums.TerrainType.FOREST: 2.0,
	Enums.TerrainType.MOUNTAINS: 5.0,
	Enums.TerrainType.DESERT: 0.0,
	Enums.TerrainType.SWAMP: -2.0,
	Enums.TerrainType.WETLANDS: -0.5,
	Enums.TerrainType.TUNDRA: 1.0,
	Enums.TerrainType.SHARD_WASTES: 0.0,
	Enums.TerrainType.WATER: -4.0,
	Enums.TerrainType.JUNGLE: 2.0,
}
var _hex_elevations: Dictionary = {} # Vector2i -> float

var selected_hex: Vector2i = Vector2i(-1, -1)
var selected_army_id: StringName = &""
var _selected_armies: Array[StringName] = [] # Multi-select (Shift+Click)
var _reachable_tiles: Dictionary = {} # coord -> remaining_mp
var _army_markers: Dictionary = {} # army_id -> Node2D
var _shard_markers: Dictionary = {} # shard_id -> Node2D
var _hex_visuals: Dictionary = {} # UNUSED — kept for compatibility
var _hex_chunks: Dictionary = {} # Vector2i(chunk_col, chunk_row) -> _HexChunkNode
var _hex_tile_chunk_data: Dictionary = {} # Vector2i(tile) -> {chunk_key, entry_idx, has_tex, terrain, coord}
const HEX_CHUNK_SIZE := 10  # tiles per chunk side
var _city_markers: Dictionary = {} # city_id -> Node2D
var _is_animating_move := false # Block input during movement animation
var _hovered_region_id: StringName = &"" # Currently hovered region for highlighting
var _last_path_preview_hex: Vector2i = Vector2i(-1, -1) # Cache last path-preview target
var _city_markers_dirty := true # Dirty flag for city marker rebuilds
var _region_highlight_nodes: Array[Node2D] = [] # Highlight overlay polygons for hovered region
var _region_tiles_cache: Dictionary = {} # region_id -> Array[Vector2i]
var _city_panel_open := false
var _selected_city_id: StringName = &""
var _elderbeast_markers: Dictionary = {} # beast_id -> Node2D
var _building_tile_markers: Array[Node2D] = [] # building markers on hex tiles
var _building_paths_node: Node2D = null # squiggly dirt paths city -> buildings
var _marker_zoom_boost := 1.0 # zoom-out readability boost applied to markers

# Click-cycling: cycle through multiple objects on the same hex
var _last_clicked_hex := Vector2i(-1, -1)
var _click_cycle_index := 0

# Viewport culling for hex tiles
var _last_cull_cam_pos := Vector2.ZERO
var _last_cull_cam_zoom := 1.0

# Minimap viewport tracking (to refresh when camera moves/zooms)
var _minimap_last_cam_pos := Vector2.ZERO
var _minimap_last_cam_zoom := 1.0
var _minimap_update_timer := 0.0
var _minimap_dirty := true  # Set true when content changes (turn/capture), redraw on next tick
var _minimap_content_cache: Image = null  # Cached minimap image without viewport rect
var _fog_dirty := false  # Deferred fog update flag — batches multiple _update_fog_of_war calls per frame
var _last_hover_hex := Vector2i(-1, -1)  # Throttle trade route hover to hex changes only
var _bounty_markers: Dictionary = {} # Vector2i -> Node2D
var bounty_markers_node: Node2D = null
var _bounty_tooltip: PanelContainer = null

# Pre-battle dialog state
var _pending_battle_attacker_id: StringName = &""
var _pending_battle_defender_id: StringName = &""
var _pending_battle_hex: Vector2i = Vector2i(-1, -1)
var _battle_dialog: PanelContainer = null
var _battle_report_panel: PanelContainer = null

# Settlement placement mode
var _settlement_placement_mode := false
var _settlement_parent_city_id: StringName = &""
var _settlement_valid_tiles: Array[Vector2i] = []
var _settlement_overlay_nodes: Array[Node2D] = []
var _settlement_preview_panel: PanelContainer = null
var _last_settlement_preview_hex := Vector2i(-9999, -9999)  # Gate preview rebuilds to hex changes

# Building tile placement mode
var _building_tile_mode := false
var _building_tile_valid: Array[Vector2i] = []
var _building_tile_overlays: Array[Node2D] = []

# Faction territory border lines
var _faction_border_node: Node2D
var _visual_faction_owner: Dictionary = {}  # Vector2i -> StringName (fills mountain/water gaps)

# Elderbeast terrain depletion overlay
var _beast_terrain_overlays: Array[Node2D] = []

# Terrain textures (loaded once in _render_hex_map)
var _terrain_textures: Dictionary = {}
var _river_textures: Array[Texture2D] = []

# Cloud shadow overlay
var _cloud_shadow_node: ColorRect
var _cloud_shadow_material: ShaderMaterial
var _cloud_time := 0.0

# Pre-computed hex polygons keyed by radius (avoids recomputing trig every call)
var _hex_polygon_cache: Dictionary = {} # float -> PackedVector2Array
var _terrain_detail_node: Node2D  # Batched terrain detail draw node

# LOD: overview sprite for zoomed-out rendering (1 sprite vs thousands of draw calls)
var _overview_sprite: Sprite2D  # Single sprite showing flat-color overview of entire map
var _overview_visible := false  # Track current LOD state
const LOD_ZOOM_THRESHOLD := 0.45  # Below this zoom, show overview instead of chunks

# Water animation overlay (single node with shader, drawn on top of water tiles)
var _water_overlay_node: Node2D

# SubViewport baking for hex map (converts thousands of draw calls → 1 sprite)
var _hex_map_viewport: SubViewport
var _hex_map_sprite: Node2D  # container holding the baked map piece sprites
var _hex_map_baked := false
var _bake_frames_remaining := -1

# Fog of war
var _fog_of_war_enabled := true
var _fog_draw_node: Node2D = null  # Batched fog draw node
# explored_tiles stored on GameManager to persist across scene reloads (battles)

# Trade route visualization
var _trade_route_draw_node: Node2D = null
var _trade_caravans: Array[Node2D] = []
var _trade_route_data: Array[Dictionary] = [] # Cached route pixel paths for caravans
var _trade_route_tooltip: PanelContainer = null

@onready var hex_map_layer: Node2D = $HexMapLayer
@onready var reachable_overlay: Node2D = $OverlayLayer/ReachableOverlay
@onready var path_overlay: Node2D = $OverlayLayer/PathOverlay
@onready var region_borders: Node2D = $OverlayLayer/RegionBorders
@onready var city_markers_node: Node2D = $EntityLayer/CityMarkers
@onready var army_markers_node: Node2D = $EntityLayer/ArmyMarkers
@onready var shard_markers_node: Node2D = $EntityLayer/ShardMarkers
@onready var region_labels_node: Node2D = $EntityLayer/RegionLabels
@onready var region_highlight_node: Node2D = $OverlayLayer/RegionHighlight
@onready var fog_overlay_node: Node2D = $OverlayLayer/FogOverlay
@onready var elderbeast_markers_node: Node2D = $EntityLayer/ElderbeastMarkers
@onready var camera: Camera2D = $Camera2D

const _RES_NAMES := {0: "Gold", 1: "Iron", 2: "Tech", 3: "Food", 4: "Shards", 5: "Wood", 6: "Captives"}
func _res_name(res_type: int) -> String:
	return _RES_NAMES.get(res_type, "???")

func _ready() -> void:
	_render_hex_map()
	_draw_region_borders()
	_draw_faction_borders()
	_create_region_labels()
	_update_political_overlay()
	_create_overview_sprite()
	_bake_hex_map_to_texture()
	_create_city_markers()
	_create_bounty_markers()
	_create_building_tile_markers()
	_create_army_markers()
	_city_markers_dirty = false  # Initial markers just created; skip redundant rebuild

	EventBus.army_moved.connect(_on_army_moved)
	EventBus.army_destroyed.connect(_on_army_destroyed)
	EventBus.region_ownership_changed.connect(_on_region_ownership_changed)
	# Battle resolution lives in the BattleResolver autoload now. This scene only
	# opts in to the player dialog + report while it is on-screen.
	BattleResolver.ui_active = true
	EventBus.battle_player_prompt.connect(_on_battle_player_prompt)
	EventBus.battle_auto_resolved.connect(_on_battle_auto_resolved)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.shardfall_occurred.connect(_on_shardfall_occurred)
	EventBus.city_captured.connect(_on_city_captured)
	EventBus.siege_started.connect(_on_siege_started)
	EventBus.siege_broken.connect(_on_siege_broken)
	EventBus.siege_progress_changed.connect(_on_siege_badge_update)
	EventBus.siege_started.connect(func(cid, _f): _refresh_siege_badge(cid))
	EventBus.siege_broken.connect(func(cid): _refresh_siege_badge(cid))
	EventBus.city_captured.connect(func(cid, _o, _n): _refresh_siege_badge(cid))
	EventBus.building_completed.connect(_on_building_completed)
	EventBus.building_demolished.connect(_on_building_demolished)
	EventBus.unit_recruited.connect(_on_unit_recruited)
	EventBus.shard_claimed.connect(_on_shard_claimed)
	EventBus.shard_expired.connect(_on_shard_expired)
	EventBus.battle_resolved.connect(_on_battle_resolved_sfx)

	_recreate_shard_markers()
	_create_elderbeast_markers()
	_build_region_tiles_cache()
	_create_fog_overlay()
	_update_trade_routes()
	# Ensure labels render above region borders; army markers above labels so
	# armies are never hidden behind city/region nameplates
	region_labels_node.z_index = 2
	city_markers_node.z_index = 2
	army_markers_node.z_index = 3
	_create_minimap()
	_create_cloud_shadows()
	EventBus.elderbeast_moved.connect(_on_elderbeast_moved)

	# Connect settlement placement signal from HUD
	var hud: Control = $UILayer/HUD
	if hud.has_signal("settlement_placement_requested"):
		hud.settlement_placement_requested.connect(_on_settlement_placement_requested)
	if hud.has_signal("building_tile_selection_requested"):
		hud.building_tile_selection_requested.connect(_on_building_tile_selection_requested)
	if hud.has_signal("building_queued"):
		hud.building_queued.connect(func():
			_invalidate_city_action_cache()
			_create_building_tile_markers()
			_fog_dirty = true)

	# Position camera on player's capital, fallback to map center
	var _cam_target := Vector2(HexMapData.MAP_WIDTH * HEX_H_SPACING * 0.5, HexMapData.MAP_HEIGHT * HEX_V_SPACING * 0.5)
	for cid in GameManager.state.cities:
		var c: CityState = GameManager.state.cities[cid]
		if c.faction_id == GameManager.state.player_faction_id and c.is_capital:
			_cam_target = _hex_to_pixel(c.hex_pos)
			break
	camera.position = _cam_target
	_update_lod()
	_cull_hex_tiles()

	AudioManager.play_faction_music(GameManager.state.player_faction_id, &"campaign")

	if not GameManager.has_meta("game_started"):
		GameManager.set_meta("game_started", true)
		TurnManager.start_game()
	elif GameManager.current_phase == Enums.GamePhase.CAMPAIGN:
		if not TurnManager.is_player_turn:
			TurnManager._end_current_faction_turn()

func _process(delta: float) -> void:
	# Bake countdown — each piece renders for 2 frames, then _finish_bake
	# captures it and arms the next piece
	if _bake_frames_remaining >= 0:
		_bake_frames_remaining -= 1
		if _bake_frames_remaining < 0:
			_finish_bake()

	# Deferred fog update — batches all _fog_dirty = true calls from the frame
	if _fog_dirty:
		_fog_dirty = false
		_update_fog_of_war()

	# Cloud shadow animation
	_cloud_time += delta
	if _cloud_shadow_material:
		_cloud_shadow_material.set_shader_parameter("time_val", _cloud_time)

	# Trade caravan animation
	if not _trade_caravans.is_empty():
		_process_trade_caravans(delta)

	# Refresh minimap on timer: dirty flag for content changes, camera for viewport
	_minimap_update_timer += delta
	if _minimap_update_timer >= 0.5:
		_minimap_update_timer = 0.0
		var cam_moved := camera and (camera.position != _minimap_last_cam_pos or camera.zoom.x != _minimap_last_cam_zoom)
		if cam_moved or _minimap_dirty:
			if camera:
				_minimap_last_cam_pos = camera.position
				_minimap_last_cam_zoom = camera.zoom.x
			if _minimap_dirty:
				_minimap_dirty = false
				_update_minimap()
			elif cam_moved:
				_update_minimap_viewport_only()

	# Viewport culling + LOD for hex tiles
	if camera:
		var cam_pos := camera.position
		var cam_zoom := camera.zoom.x
		# Only re-cull when camera has moved significantly (>1 hex worth)
		var hex_threshold := 40.0  # approximately 1 hex width
		if cam_pos.distance_to(_last_cull_cam_pos) > hex_threshold or absf(cam_zoom - _last_cull_cam_zoom) > 0.05:
			_last_cull_cam_pos = cam_pos
			_last_cull_cam_zoom = cam_zoom
			_update_lod()
			_update_close_lod()
			_cull_hex_tiles()
			_update_marker_zoom_scale(cam_zoom)

# ── Hex geometry ──────────────────────────────────────────────

func _hex_to_pixel(coord: Vector2i) -> Vector2:
	var x := coord.x * HEX_H_SPACING
	var y := coord.y * HEX_V_SPACING
	if coord.x & 1:
		y += HEX_V_OFFSET
	return Vector2(x, y)

func _pixel_to_hex(pixel: Vector2) -> Vector2i:
	var approx_col := int(round(pixel.x / HEX_H_SPACING))
	var approx_row := int(round(pixel.y / HEX_V_SPACING))
	var best := Vector2i(approx_col, approx_row)
	var best_dist := INF
	for col in range(maxi(0, approx_col - 2), mini(HexMapData.MAP_WIDTH, approx_col + 3)):
		for row in range(maxi(0, approx_row - 2), mini(HexMapData.MAP_HEIGHT, approx_row + 3)):
			var center := _hex_to_pixel(Vector2i(col, row))
			var dist := pixel.distance_squared_to(center)
			if dist < best_dist:
				best_dist = dist
				best = Vector2i(col, row)
	return best

func _make_hex_polygon(radius: float) -> PackedVector2Array:
	if _hex_polygon_cache.has(radius):
		return _hex_polygon_cache[radius]
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	_hex_polygon_cache[radius] = points
	return points

## Build an array of world-space hex polygons for [param coords] using a local
## polygon of [param radius].  This is the common overlay-tile pattern used by
## reachable tiles, path preview, region highlight, settlement overlay, etc.
func _build_world_hex_polys(coords: Array, radius: float) -> Array:
	var hex_poly := _make_hex_polygon(radius)
	var polys: Array = []
	for coord in coords:
		var pos := _hex_to_pixel(coord)
		var world_poly := PackedVector2Array()
		for p in hex_poly:
			world_poly.append(p + pos)
		polys.append(world_poly)
	return polys

# ── Viewport culling ──────────────────────────────────────────

func _cull_hex_tiles() -> void:
	if _overview_visible or _bake_frames_remaining >= 0:
		return
	if _hex_map_baked and not _chunks_live:
		return
	var vp_size := get_viewport_rect().size
	var cam_pos := camera.position
	var cam_zoom := camera.zoom.x
	# Visible area in world space (generous margin for chunk edges)
	var margin := float(HEX_CHUNK_SIZE) * HEX_H_SPACING + 80.0
	var half_w := (vp_size.x / cam_zoom) / 2.0 + margin
	var half_h := (vp_size.y / cam_zoom) / 2.0 + margin
	var vis_rect := Rect2(cam_pos.x - half_w, cam_pos.y - half_h, half_w * 2.0, half_h * 2.0)

	# Cull chunks (~120 nodes) instead of individual tiles (~9126 nodes)
	for chunk_key: Vector2i in _hex_chunks:
		var chunk: Node2D = _hex_chunks[chunk_key]
		# Estimate chunk center from its grid position
		var chunk_cx := (chunk_key.x * HEX_CHUNK_SIZE + HEX_CHUNK_SIZE * 0.5) * HEX_H_SPACING
		var chunk_cy := (chunk_key.y * HEX_CHUNK_SIZE + HEX_CHUNK_SIZE * 0.5) * HEX_V_SPACING
		chunk.visible = vis_rect.has_point(Vector2(chunk_cx, chunk_cy)) and not _overview_visible

func _create_overview_sprite() -> void:
	## Creates a low-res overview image of the map (flat terrain colors + political tint).
	## Rendered once at startup; toggled on when zoomed out for massive perf gain.
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	# Each tile gets a small block of pixels in the overview (3x3 for hex shape approx)
	var px_per_tile := 3
	var img_w: int = HexMapData.MAP_WIDTH * px_per_tile + px_per_tile
	var img_h: int = HexMapData.MAP_HEIGHT * px_per_tile + px_per_tile
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGB8)
	_fill_overview_image(img)

	_overview_sprite = Sprite2D.new()
	_overview_sprite.centered = false
	_overview_sprite.texture = ImageTexture.create_from_image(img)
	# Scale sprite so it aligns with the hex map world coordinates
	_overview_sprite.scale = Vector2(HEX_H_SPACING / float(px_per_tile), HEX_V_SPACING / float(px_per_tile))
	_overview_sprite.visible = false
	hex_map_layer.add_child(_overview_sprite)

func _fill_overview_image(img: Image) -> void:
	## Shared pixel fill for the overview sprite (create + in-place refresh).
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var px_per_tile := 3
	var img_w := img.get_width()
	var img_h := img.get_height()
	img.fill(Color(0.06, 0.05, 0.04))  # Dark background
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		# Apply slight faction tint
		if tile.owner_faction != &"" and tile.owner_faction != &"independent":
			var fd: FactionData = DataManager.get_faction(tile.owner_faction)
			if fd:
				color = color.lerp(fd.color, 0.12)
		# Map hex coords to pixel position (odd columns offset by half)
		var px: int = coord.x * px_per_tile
		var py: int = coord.y * px_per_tile + (px_per_tile / 2 if coord.x & 1 else 0)
		for dx in px_per_tile:
			for dy in px_per_tile:
				if px + dx < img_w and py + dy < img_h:
					img.set_pixel(px + dx, py + dy, color)

func _update_overview_colors() -> void:
	## Refreshes overview sprite pixels in place when political overlay changes
	## (previously freed and recreated the sprite + a new ImageTexture).
	if _overview_sprite == null:
		return
	var tex := _overview_sprite.texture as ImageTexture
	if tex == null:
		# Fallback: recreate from scratch (previous behavior)
		_overview_sprite.queue_free()
		_overview_sprite = null
		_create_overview_sprite()
		if _overview_visible:
			_overview_sprite.visible = true
		return
	var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGB8)
	_fill_overview_image(img)
	tex.update(img)
	_overview_sprite.visible = _overview_visible

func _update_lod() -> void:
	if camera == null or _overview_sprite == null or _bake_frames_remaining >= 0:
		return
	var should_overview := camera.zoom.x < LOD_ZOOM_THRESHOLD
	if should_overview == _overview_visible:
		return
	_overview_visible = should_overview
	_overview_sprite.visible = should_overview
	# When in overview mode, hide all hex_map_layer children except overview sprite and baked sprite
	for child in hex_map_layer.get_children():
		if child == _overview_sprite:
			continue
		if child == _hex_map_sprite:
			child.visible = not should_overview
			continue
		if child == _water_overlay_node:
			child.visible = not should_overview
			continue
		# Hide chunks/details/borders in overview (they're baked or not needed)
		child.visible = not should_overview

# Close-up LOD: past this zoom the baked bitmap looks pixelated, so the live
# chunk nodes are reparented back from the SubViewport and drawn directly
# (with viewport culling). Hysteresis avoids churn at the boundary.
const LIVE_ZOOM_ENTER := 1.1
const LIVE_ZOOM_EXIT := 1.0
var _baked_nodes: Array[Node] = []  # everything moved into the bake viewport
var _chunks_live := false
var _rebake_when_baked := false

func _update_close_lod() -> void:
	if not _hex_map_baked or _bake_frames_remaining >= 0:
		return
	var z := camera.zoom.x
	var want_live := z >= LIVE_ZOOM_ENTER if not _chunks_live else z > LIVE_ZOOM_EXIT
	if want_live == _chunks_live:
		return
	_chunks_live = want_live
	if want_live:
		# Only the CHUNK nodes come back (they cull per-chunk); the whole-map
		# batch nodes (borders/details/elevation — single uncullable items,
		# tens of thousands of commands) stay baked. The full-res sprite stays
		# visible beneath the live chunks to supply borders and shading.
		for node in _baked_nodes:
			if node is _HexChunkNode and node.get_parent() == _hex_map_viewport:
				_hex_map_viewport.remove_child(node)
				hex_map_layer.add_child(node)
		# Keep the animated water + overview above the live chunks
		if _water_overlay_node and _water_overlay_node.get_parent() == hex_map_layer:
			hex_map_layer.move_child(_water_overlay_node, hex_map_layer.get_child_count() - 1)
		if _overview_sprite and _overview_sprite.get_parent() == hex_map_layer:
			hex_map_layer.move_child(_overview_sprite, hex_map_layer.get_child_count() - 1)
		_cull_hex_tiles()
	else:
		for node in _baked_nodes:
			if node is _HexChunkNode and node.get_parent() == hex_map_layer:
				hex_map_layer.remove_child(node)
				_hex_map_viewport.add_child(node)
				node.visible = true
		if _rebake_when_baked:
			_rebake_when_baked = false
			_request_rebake()

# ── Tiled map bake ───────────────────────────────────────────
# The map is baked full-resolution in 2048x2048 pieces, captured sequentially
# from ONE small SubViewport (camera repositioned per piece) into a grid of
# sprites. 2048 render targets work on every GPU — the previous single
# 5704x4512 target hit driver limits/GL_FRAMEBUFFER_INCOMPLETE on some
# machines, falling back to live chunk rendering (~90 ms frames).
const BAKE_TILE_SIZE := 2048

var _bake_cam: Camera2D = null
var _bake_tiles: Array[Vector2i] = []       # pending piece origins (world px)
var _bake_sprite_map: Dictionary = {}        # origin -> Sprite2D

func _bake_hex_map_to_texture() -> void:
	_begin_map_bake()

func _begin_map_bake() -> void:
	# Remove water overlay from hex_map_layer before baking (keep it live for animation)
	if _water_overlay_node and _water_overlay_node.get_parent() == hex_map_layer:
		hex_map_layer.remove_child(_water_overlay_node)
	# Remove overview sprite too (not part of the bake)
	if _overview_sprite and _overview_sprite.get_parent() == hex_map_layer:
		hex_map_layer.remove_child(_overview_sprite)

	_hex_map_viewport = SubViewport.new()
	_hex_map_viewport.size = Vector2i(BAKE_TILE_SIZE, BAKE_TILE_SIZE)
	_hex_map_viewport.transparent_bg = true
	_hex_map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_hex_map_viewport)
	_bake_cam = Camera2D.new()
	_bake_cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_hex_map_viewport.add_child(_bake_cam)

	# Reparent all hex_map_layer children into SubViewport (list kept so the
	# close-up LOD can move them back for crisp rendering at high zoom)
	_baked_nodes.clear()
	for child in hex_map_layer.get_children():
		_baked_nodes.append(child)
	for child in _baked_nodes:
		hex_map_layer.remove_child(child)
		_hex_map_viewport.add_child(child)
	# All chunks must be visible for baking, and freshly redrawn — reparenting
	# into the SubViewport does not reliably carry existing draw commands over
	for chunk_key: Vector2i in _hex_chunks:
		_hex_chunks[chunk_key].visible = true
		_hex_chunks[chunk_key].queue_redraw()

	# Container for the baked piece sprites
	_hex_map_sprite = Node2D.new()
	hex_map_layer.add_child(_hex_map_sprite)
	_bake_sprite_map.clear()

	# Re-add water overlay and overview sprite on top
	if _water_overlay_node:
		hex_map_layer.add_child(_water_overlay_node)
	if _overview_sprite:
		hex_map_layer.add_child(_overview_sprite)

	_queue_all_bake_tiles()
	_start_next_bake_tile()

func _queue_all_bake_tiles() -> void:
	var map_w := ceili(HexMapData.MAP_WIDTH * HEX_H_SPACING + HEX_H_SPACING + 40.0)
	var map_h := ceili(HexMapData.MAP_HEIGHT * HEX_V_SPACING + HEX_V_SPACING + 40.0)
	_bake_tiles.clear()
	for ty in range(0, map_h, BAKE_TILE_SIZE):
		for tx in range(0, map_w, BAKE_TILE_SIZE):
			_bake_tiles.append(Vector2i(tx, ty))

func _start_next_bake_tile() -> void:
	if _bake_tiles.is_empty() or _hex_map_viewport == null:
		return
	_bake_cam.position = Vector2(_bake_tiles[0])
	_hex_map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bake_frames_remaining = 2

func _finish_bake() -> void:
	## Captures the current bake piece; starts the next or completes the bake.
	if _hex_map_viewport == null or _bake_tiles.is_empty():
		return
	var origin: Vector2i = _bake_tiles[0]
	_bake_tiles.remove_at(0)
	var img: Image = null
	var tex := _hex_map_viewport.get_texture()
	if tex:
		img = tex.get_image()
	var ok := img != null and not img.is_empty()
	if ok and origin == Vector2i.ZERO:
		# Validate the first piece (always contains map content): a fully
		# transparent readback means the render target never rendered
		ok = false
		for i in 8:
			if img.get_pixel(BAKE_TILE_SIZE * (i * 2 + 1) / 16, BAKE_TILE_SIZE / 2).a > 0.01:
				ok = true
				break
	if not ok:
		# 2048 targets should work everywhere; if not, restore live chunk
		# rendering (slower, but functional on any GPU)
		push_warning("Map bake unavailable on this GPU — using live chunk rendering")
		for node in _baked_nodes:
			if node.get_parent() == _hex_map_viewport:
				_hex_map_viewport.remove_child(node)
				hex_map_layer.add_child(node)
		_hex_map_viewport.queue_free()
		_hex_map_viewport = null
		_bake_cam = null
		_bake_tiles.clear()
		_cull_hex_tiles()
		return

	var spr: Sprite2D = _bake_sprite_map.get(origin)
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		spr.position = Vector2(origin)
		spr.texture = ImageTexture.create_from_image(img)
		_hex_map_sprite.add_child(spr)
		_bake_sprite_map[origin] = spr
	else:
		(spr.texture as ImageTexture).update(img)

	if _bake_tiles.is_empty():
		_hex_map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_hex_map_baked = true
	else:
		_start_next_bake_tile()

func _rebake_hex_map() -> void:
	if _hex_map_viewport == null or not _hex_map_baked:
		return
	if _chunks_live:
		# Chunks are currently in the main tree for close-up rendering —
		# rebake when they return to the SubViewport (zoom back out)
		_rebake_when_baked = true
		return
	if not _bake_tiles.is_empty():
		return  # A bake pass is already in flight
	for chunk_key: Vector2i in _hex_chunks:
		_hex_chunks[chunk_key].queue_redraw()
	_queue_all_bake_tiles()
	_start_next_bake_tile()

var _rebake_queued := false

func _request_rebake() -> void:
	## Coalesces multiple rebake requests in one frame into a single rebake.
	## _rebake_hex_map re-renders the whole map SubViewport and does a GPU
	## readback in _finish_bake — never do that more than once per frame.
	if _rebake_queued:
		return
	_rebake_queued = true
	call_deferred("_run_queued_rebake")

func _run_queued_rebake() -> void:
	_rebake_queued = false
	_rebake_hex_map()

# ── Rendering ─────────────────────────────────────────────────

func _load_terrain_textures() -> void:
	if not _terrain_textures.is_empty():
		return
	# Map terrain type to base filename (variants are name1.png, name2.png, etc.)
	var base_names := {
		Enums.TerrainType.PLAINS: "plains",
		Enums.TerrainType.FOREST: "forest",
		Enums.TerrainType.MOUNTAINS: "mountain",
		Enums.TerrainType.DESERT: "desert",
		Enums.TerrainType.SWAMP: "swamp",
		Enums.TerrainType.WETLANDS: "wetlands",
		Enums.TerrainType.TUNDRA: "tundra",
		Enums.TerrainType.SHARD_WASTES: "shardwaste",
		Enums.TerrainType.WATER: "water",
		Enums.TerrainType.JUNGLE: "jungle",
	}
	# v2 gouache tile set; falls back to the legacy campaign_map dir per terrain
	for terrain in base_names:
		var variants: Array[Texture2D] = []
		for dir in ["campaign_map_v2", "campaign_map"]:
			for i in range(1, 10):
				var path := "res://assets/sprites/%s/%s%d.png" % [dir, base_names[terrain], i]
				if ResourceLoader.exists(path):
					var tex = load(path)
					if tex:
						variants.append(tex)
				else:
					break
			if not variants.is_empty():
				break
		if not variants.is_empty():
			_terrain_textures[terrain] = variants
	# River variants (water tiles in narrow channels render as flowing water)
	_river_textures.clear()
	for i in range(1, 10):
		var rpath := "res://assets/sprites/campaign_map_v2/river%d.png" % i
		if ResourceLoader.exists(rpath):
			var rtex = load(rpath)
			if rtex:
				_river_textures.append(rtex)
		else:
			break

func _render_hex_map() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	_load_terrain_textures()

	var border_poly := _make_hex_polygon(HEX_RADIUS)
	var fill_poly := _make_hex_polygon(HEX_RADIUS * 0.995)
	var fill_r := HEX_RADIUS * 0.995

	# Pre-compute normalized UV coordinates for hex polygon (centered 0-1 space)
	var hex_uvs := PackedVector2Array()
	for point in fill_poly:
		hex_uvs.append(Vector2(point.x / (2.0 * fill_r) + 0.5, point.y / (2.0 * fill_r) + 0.5))

	# Batch all hex borders into a single draw node (saves ~9000 Polygon2D)
	var all_border_polys: Array = []
	for coord in hex_map.tiles:
		var pixel_pos := _hex_to_pixel(coord)
		var elevation: float = TERRAIN_ELEVATION.get(hex_map.tiles[coord].terrain, 0.0)
		var offset := Vector2(pixel_pos.x, pixel_pos.y - elevation)
		var world_poly := PackedVector2Array()
		for p in border_poly:
			world_poly.append(p + offset)
		all_border_polys.append(world_poly)
	var border_batch := _OverlayDrawNode.new()
	border_batch.polys = all_border_polys
	border_batch.color = HEX_BORDER_COLOR
	hex_map_layer.add_child(border_batch)

	# Create batched terrain detail node (replaces individual Polygon2D/Line2D children)
	_terrain_detail_node = _BatchedTerrainDetailNode.new()
	_terrain_detail_node.z_index = 1

	# Build chunk data: group tiles into HEX_CHUNK_SIZE x HEX_CHUNK_SIZE chunks
	# Each chunk is a single _HexChunkNode with all its tiles batched into _draw()
	var chunk_entries: Dictionary = {}  # chunk_key -> Array of [world_poly, color, tex, uv]
	var chunk_shores: Dictionary = {}  # chunk_key -> Array of [band_poly, color]
	var chunk_foams: Dictionary = {}   # chunk_key -> Array of PackedVector2Array
	var water_polys: Array = []  # Collect water tile polygons for animation overlay

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var base_color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		var elevation: float = TERRAIN_ELEVATION.get(tile.terrain, 0.0)
		_hex_elevations[coord] = elevation

		var offset := Vector2(pixel_pos.x, pixel_pos.y - elevation)
		var world_poly := PackedVector2Array()
		for p in fill_poly:
			world_poly.append(p + offset)

		var chunk_key := Vector2i(coord.x / HEX_CHUNK_SIZE, coord.y / HEX_CHUNK_SIZE)

		# Determine texture — a water tile is a RIVER when its water neighbors
		# do not touch each other (a channel running through land); if any two
		# of its water neighbors are adjacent to one another it is part of an
		# open water body (ocean/lake), as is an isolated pond.
		var variants: Array = _terrain_textures.get(tile.terrain, [])
		var uv_rot := 0.0
		var is_river := false
		var neighbors := HexHelper.get_neighbors(coord)
		if tile.terrain == Enums.TerrainType.WATER and not _river_textures.is_empty():
			var dir_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD
			var water_idx: Array[int] = []  # edge indices (circular 0-5)
			var water_dirs: Array[Vector2] = []
			for ni in 6:
				var n: Vector2i = neighbors[ni]
				if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
					continue
				var ntile: HexMapData.TileState = hex_map.tiles.get(n)
				if ntile == null:
					continue
				if ntile.terrain == Enums.TerrainType.WATER:
					water_idx.append(dir_lut[ni])
					water_dirs.append(_hex_to_pixel(n) - pixel_pos)
			var open_water := water_idx.is_empty()  # isolated pond = still water
			for i in water_idx.size():
				for j in range(i + 1, water_idx.size()):
					var d := absi(water_idx[i] - water_idx[j])
					if d == 1 or d == 5:  # cyclically adjacent directions
						open_water = true
			if not open_water:
				variants = _river_textures
				is_river = true
				if water_dirs.size() >= 2:
					uv_rot = (water_dirs[0] - water_dirs[1]).angle()
				elif water_dirs.size() == 1:
					uv_rot = water_dirs[0].angle()
		if not is_river:
			# All tiles are painted top-down and rotation-safe, so each tile
			# also gets one of 6 hex rotations for extra variety (rivers keep
			# their flow-aligned rotation instead). Different hash than the
			# variant pick so rotation and variant vary independently.
			uv_rot = (TAU / 6.0) * float(posmod(coord.x * 5 + coord.y * 11 + coord.x * coord.y * 3, 6))
		var tex: Texture2D = null
		var scaled_uv: PackedVector2Array = PackedVector2Array()
		if not variants.is_empty():
			var variant_idx: int
			if variants.size() >= 7:
				# posmod(3x+5y, 7): every hex-neighbor delta is nonzero mod 7,
				# so adjacent tiles NEVER repeat the same variant
				variant_idx = posmod(coord.x * 3 + coord.y * 5, 7) % variants.size()
			else:
				variant_idx = absi(coord.x * 7 + coord.y * 13 + coord.x * coord.y) % variants.size()
			tex = variants[variant_idx]
		if tex:
			# draw_colored_polygon UVs are normalized 0-1, not pixel coordinates
			# Crop to center 85% of texture to avoid edge artifacts; rivers
			# additionally rotate UVs so the baked flow lines follow the channel
			var crop_factor := 0.85
			for uv in hex_uvs:
				var v := (uv - Vector2(0.5, 0.5)).rotated(uv_rot) * crop_factor
				scaled_uv.append(Vector2(0.5, 0.5) + v)

		# All tiles go into chunk batched _draw()
		var color: Color = Color.WHITE if tex else base_color
		if not chunk_entries.has(chunk_key):
			chunk_entries[chunk_key] = []
		# Direct coord -> chunk entry index (used by _update_political_overlay
		# instead of scanning ~100 entries per tile comparing polygon centers)
		_hex_tile_chunk_data[coord] = {chunk_key = chunk_key, entry_idx = chunk_entries[chunk_key].size()}
		chunk_entries[chunk_key].append([world_poly, color, tex, scaled_uv if tex else null])

		# Collect water polygons for animation overlay
		if tile.terrain == Enums.TerrainType.WATER:
			water_polys.append(world_poly)

		# Terrain bleed bands: neighbors softly bleed their color into this
		# tile along shared edges — a continuous, corner-rounding curve (no
		# pinched wedges). Water tiles receive strong bleed + foam from every
		# land neighbor (shoreline); land tiles receive a subtle bleed from
		# differing land neighbors (lower terrain enum bleeds onto higher).
		var is_water := tile.terrain == Enums.TerrainType.WATER
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD
		var edge_src: Array = [null, null, null, null, null, null]  # edge -> source tile or null
		for ni in 6:
			var n: Vector2i = neighbors[ni]
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var ntile: HexMapData.TileState = hex_map.tiles.get(n)
			if ntile == null or ntile.terrain == tile.terrain:
				continue
			if is_water:
				if ntile.terrain != Enums.TerrainType.WATER:
					edge_src[edge_lut[ni]] = ntile
			else:
				# Land-to-land bleed only, one direction per pair for stability
				if ntile.terrain != Enums.TerrainType.WATER and int(ntile.terrain) < int(tile.terrain):
					edge_src[edge_lut[ni]] = ntile
		var band_depth := HEX_RADIUS * (0.42 if is_water else 0.26)
		var band_alpha := 0.85 if is_water else 0.45
		for e in 6:
			if edge_src[e] == null:
				continue
			var v0: Vector2 = fill_poly[e] + offset
			var v1: Vector2 = fill_poly[(e + 1) % 6] + offset
			# Continue at full depth into corners shared with another bleeding
			# edge — the inner curve then wraps smoothly around the corner
			# instead of pinching into a wedge
			var prev_open: bool = edge_src[(e + 5) % 6] != null
			var next_open: bool = edge_src[(e + 1) % 6] != null
			var band := PackedVector2Array([v0, v1])
			var foam := PackedVector2Array()
			for k in 9:
				var t := 1.0 - float(k) / 8.0
				var base_pt := v0.lerp(v1, t)
				var fade_in := 1.0 if prev_open else clampf(t / 0.45, 0.0, 1.0)
				var fade_out := 1.0 if next_open else clampf((1.0 - t) / 0.45, 0.0, 1.0)
				var s := minf(fade_in, fade_out)
				s = s * s * (3.0 - 2.0 * s)  # smoothstep
				if s <= 0.001:
					continue  # closed end — point would duplicate the corner vertex
				# World-position noise — continuous across edges and tiles, so
				# open corners get IDENTICAL inner points on both edges (bands
				# meet exactly, no wedge gaps) and boundaries look organic
				var wob := sin(base_pt.x * 0.11 + base_pt.y * 0.07) * 2.6 \
					+ sin(base_pt.x * 0.31 + base_pt.y * 0.23) * 1.3
				var depth := (band_depth + wob) * s
				var inward := (offset - base_pt).normalized()
				band.append(base_pt + inward * depth)
				if is_water:
					foam.append(base_pt + inward * (depth + 1.4 * s))
			var src_col: Color = TERRAIN_COLORS.get((edge_src[e] as HexMapData.TileState).terrain, Color.GRAY)
			if not chunk_shores.has(chunk_key):
				chunk_shores[chunk_key] = []
				chunk_foams[chunk_key] = []
			chunk_shores[chunk_key].append([band, Color(src_col.r, src_col.g, src_col.b, band_alpha)])
			if is_water:
				foam.reverse()
				chunk_foams[chunk_key].append(foam)

		# Procedural terrain details (only for terrains without textures)
		if not tex:
			_add_terrain_detail(offset, tile.terrain, fill_poly, base_color)

	# Create chunk nodes
	for chunk_key in chunk_entries:
		var chunk := _HexChunkNode.new()
		chunk.tile_entries = chunk_entries[chunk_key]
		chunk.shore_entries = chunk_shores.get(chunk_key, [])
		chunk.foam_lines = chunk_foams.get(chunk_key, [])
		hex_map_layer.add_child(chunk)
		_hex_chunks[chunk_key] = chunk

	_hex_visuals.clear()  # No longer used for culling

	# Add batched terrain detail node (all terrain decorations in one draw call)
	hex_map_layer.add_child(_terrain_detail_node)

	# Water animation overlay — single node with shader on top of water tiles
	if not water_polys.is_empty():
		var water_shader := load("res://assets/shaders/hex_water.gdshader") as Shader
		if water_shader:
			_water_overlay_node = _WaterAnimOverlay.new()
			_water_overlay_node.water_polys = water_polys
			_water_overlay_node.z_index = 1
			var wmat := ShaderMaterial.new()
			wmat.shader = water_shader
			wmat.set_shader_parameter("base_color", TERRAIN_COLORS[Enums.TerrainType.WATER])
			_water_overlay_node.material = wmat
			hex_map_layer.add_child(_water_overlay_node)

	# Draw elevation shadow edges after all tiles
	_draw_elevation_edges()

	# Draw thick outlines around mountain range edges (only outer edges)
	_draw_mountain_outlines()

func _draw_elevation_edges() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS * 0.995)
	var cliff_polys: Array = []
	var medium_polys: Array = []
	var subtle_polys: Array = []
	var highlight_edges: Array = []

	for coord in hex_map.tiles:
		var my_elev: float = _hex_elevations.get(coord, 0.0)
		var my_pixel := _hex_to_pixel(coord)
		var neighbors := HexHelper.get_neighbors(coord)
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD
		for i in 6:
			var neighbor: Vector2i = neighbors[i]
			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			var n_elev: float = _hex_elevations.get(neighbor, 0.0)
			var elev_diff := my_elev - n_elev
			if elev_diff <= 0:
				continue
			var e: int = edge_lut[i]
			var v1: Vector2 = my_pixel + hex_points[e]
			var v2: Vector2 = my_pixel + hex_points[(e + 1) % 6]
			var drop := elev_diff * 1.5
			var shadow_poly := PackedVector2Array([
				Vector2(v1.x, v1.y - my_elev),
				Vector2(v2.x, v2.y - my_elev),
				Vector2(v2.x, v2.y - my_elev + drop),
				Vector2(v1.x, v1.y - my_elev + drop),
			])
			if elev_diff >= 3.0:
				cliff_polys.append(shadow_poly)
			elif elev_diff >= 1.5:
				medium_polys.append(shadow_poly)
			else:
				subtle_polys.append(shadow_poly)

		# Mountain highlight on top edges (edges 4 and 5 = north-facing)
		if hex_map.tiles[coord].terrain == Enums.TerrainType.MOUNTAINS:
			for edge_i in [4, 5]:
				var hv1: Vector2 = my_pixel + hex_points[edge_i]
				var hv2: Vector2 = my_pixel + hex_points[(edge_i + 1) % 6]
				highlight_edges.append([
					Vector2(hv1.x, hv1.y - my_elev),
					Vector2(hv2.x, hv2.y - my_elev),
				])

	var elev_node := _ElevationDrawNode.new()
	elev_node.cliff_polys = cliff_polys
	elev_node.medium_polys = medium_polys
	elev_node.subtle_polys = subtle_polys
	elev_node.highlight_edges = highlight_edges
	hex_map_layer.add_child(elev_node)

func _draw_mountain_outlines() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS)
	var all_outlines: Array = []
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.terrain != Enums.TerrainType.MOUNTAINS:
			continue
		var my_pixel := _hex_to_pixel(coord)
		var my_elev: float = _hex_elevations.get(coord, 0.0)
		var neighbors := HexHelper.get_neighbors(coord)
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD
		for i in 6:
			var neighbor: Vector2i = neighbors[i]
			var ntile := hex_map.get_tile(neighbor)
			if ntile == null or ntile.terrain != Enums.TerrainType.MOUNTAINS:
				var e: int = edge_lut[i]
				var v1: Vector2 = my_pixel + hex_points[e]
				var v2: Vector2 = my_pixel + hex_points[(e + 1) % 6]
				all_outlines.append([
					Vector2(v1.x, v1.y - my_elev),
					Vector2(v2.x, v2.y - my_elev),
				])
	var outline_node := _BorderDrawNode.new()
	outline_node.edges = all_outlines
	outline_node.line_color = Color(0.05, 0.04, 0.03, 0.9)
	outline_node.line_width = 3.0
	hex_map_layer.add_child(outline_node)

func _add_terrain_detail(world_pos: Vector2, terrain: Enums.TerrainType, _hex_poly: PackedVector2Array, base_color: Color) -> void:
	# Collect terrain details into batched draw node instead of individual child nodes
	if _terrain_detail_node == null:
		return
	var pos := world_pos
	var r := HEX_RADIUS * 0.96
	match terrain:
		Enums.TerrainType.FOREST:
			for offset in [Vector2(-6, -5), Vector2(4, -3), Vector2(-2, 5), Vector2(6, 4)]:
				_terrain_detail_node.polygon_data.append([_make_circle_at(pos + offset, 4.0, 6), base_color.darkened(0.25)])
		Enums.TerrainType.JUNGLE:
			for offset in [Vector2(-7, -6), Vector2(5, -4), Vector2(-3, 6), Vector2(7, 3), Vector2(0, -1), Vector2(-5, 2)]:
				_terrain_detail_node.polygon_data.append([_make_circle_at(pos + offset, 4.5, 6), base_color.darkened(0.2)])
		Enums.TerrainType.MOUNTAINS:
			_terrain_detail_node.polygon_data.append([PackedVector2Array([pos + Vector2(0, -8), pos + Vector2(-6, 4), pos + Vector2(6, 4)]), base_color.lightened(0.15)])
			_terrain_detail_node.polygon_data.append([PackedVector2Array([pos + Vector2(-7, -3), pos + Vector2(-12, 5), pos + Vector2(-2, 5)]), base_color.lightened(0.1)])
		Enums.TerrainType.DESERT:
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-r * 0.5, 2), pos + Vector2(0, -2), pos + Vector2(r * 0.5, 2)]), 1.5, base_color.lightened(0.15)])
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-r * 0.4, 7), pos + Vector2(r * 0.1, 4), pos + Vector2(r * 0.4, 7)]), 1.5, base_color.lightened(0.12)])
		Enums.TerrainType.SWAMP:
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(-3, -3), pos + Vector2(3, 3), pos + Vector2(8, 0)]), 1.5, Color(0.25, 0.5, 0.35, 0.6)])
		Enums.TerrainType.WATER:
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-8, -2), pos + Vector2(-3, -5), pos + Vector2(3, -2), pos + Vector2(8, -5)]), 1.5, base_color.lightened(0.2)])
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-6, 4), pos + Vector2(-1, 1), pos + Vector2(5, 4), pos + Vector2(10, 1)]), 1.5, base_color.lightened(0.15)])
		Enums.TerrainType.TUNDRA:
			for offset in [Vector2(-5, -3), Vector2(4, 5), Vector2(6, -4)]:
				_terrain_detail_node.polygon_data.append([PackedVector2Array([pos + offset + Vector2(0, -2), pos + offset + Vector2(2, 0), pos + offset + Vector2(0, 2), pos + offset + Vector2(-2, 0)]), Color(0.85, 0.88, 0.95, 0.6)])
		Enums.TerrainType.SHARD_WASTES:
			for offset in [Vector2(-4, -3), Vector2(5, 2), Vector2(-1, 6)]:
				_terrain_detail_node.polygon_data.append([PackedVector2Array([pos + offset + Vector2(0, -3), pos + offset + Vector2(2, 0), pos + offset + Vector2(0, 3), pos + offset + Vector2(-2, 0)]), Color(0.7, 0.3, 0.8, 0.7)])
		Enums.TerrainType.PLAINS:
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-4, 2), pos + Vector2(-3, -2), pos + Vector2(-2, 2)]), 1.0, base_color.lightened(0.12)])
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(3, 1), pos + Vector2(4, -3), pos + Vector2(5, 1)]), 1.0, base_color.lightened(0.12)])
		Enums.TerrainType.WETLANDS:
			_terrain_detail_node.line_data.append([PackedVector2Array([pos + Vector2(-7, 3), pos + Vector2(-2, 0), pos + Vector2(4, 3), pos + Vector2(8, 1)]), 1.5, Color(0.65, 0.6, 0.45, 0.5)])

func _make_circle_at(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

func _make_circle(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

func _draw_region_borders() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# For each hex, check each of 6 edges. If the neighbor belongs to a different
	# region (or is water/off-map), draw the shared hex edge as a border segment.
	var hex_points := _make_hex_polygon(HEX_RADIUS * 0.995)
	var all_edges: Array = []

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id == &"":
			continue

		var pixel_pos := _hex_to_pixel(coord)
		var neighbors := HexHelper.get_neighbors(coord)
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD

		for i in 6:
			var neighbor: Vector2i = neighbors[i]
			var draw_border := false

			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				draw_border = true
			else:
				var ntile := hex_map.get_tile(neighbor)
				if ntile == null or ntile.region_id != tile.region_id:
					draw_border = true

			if draw_border:
				var e: int = edge_lut[i]
				var v1: Vector2 = pixel_pos + hex_points[e]
				var v2: Vector2 = pixel_pos + hex_points[(e + 1) % 6]
				all_edges.append([v1, v2])

	# Draw using custom draw node (single draw call, clean lines)
	var draw_node := _BorderDrawNode.new()
	draw_node.edges = all_edges
	draw_node.line_color = Color(0.0, 0.0, 0.0, 1.0)
	draw_node.line_width = 2.5
	region_borders.add_child(draw_node)

func _draw_faction_borders() -> void:
	if _faction_border_node:
		_faction_border_node.queue_free()
	_faction_border_node = Node2D.new()
	_faction_border_node.z_index = 1
	$OverlayLayer.add_child(_faction_border_node)

	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# Build visual ownership via Voronoi against all cities (including independent).
	# This fills mountains/water gaps and assigns independent city territories.
	_visual_faction_owner.clear()
	var visual_owner := _visual_faction_owner

	# BFS Voronoi: expand outward from all cities simultaneously.
	# Each tile is claimed by the nearest city (by BFS hop count within its region).
	# This is O(tiles) instead of O(tiles * cities_per_region).
	var dist_map: Dictionary = {}  # coord -> int (BFS distance from nearest city)
	var bfs_queue: Array = []  # [coord, faction_id, region_id, distance]
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == &"":
			continue
		var cpos := city.hex_pos
		var tile := hex_map.get_tile(cpos)
		if tile == null:
			continue
		visual_owner[cpos] = city.faction_id
		dist_map[cpos] = 0
		bfs_queue.append([cpos, city.faction_id, tile.region_id, 0])

	var bfs_idx := 0
	while bfs_idx < bfs_queue.size():
		var entry: Array = bfs_queue[bfs_idx]
		bfs_idx += 1
		var coord: Vector2i = entry[0]
		var fid: StringName = entry[1]
		var rid: StringName = entry[2]
		var dist: int = entry[3]
		for n in HexHelper.get_neighbors(coord):
			if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				continue
			if dist_map.has(n):
				continue  # Already claimed by a closer city
			var ntile := hex_map.get_tile(n)
			if ntile == null or ntile.region_id != rid:
				continue  # Stay within the same region
			dist_map[n] = dist + 1
			visual_owner[n] = fid
			bfs_queue.append([n, fid, rid, dist + 1])

	# Pocket cleanup: BFS connected components per faction, reassign small isolated ones.
	# Run multiple passes to handle cascading reassignment.
	for _cleanup_pass in 3:
		var cleanup_changed := false
		var comp_id: Dictionary = {}
		var components: Array = []
		var current_comp := 0
		for coord in visual_owner:
			if comp_id.has(coord):
				continue
			var faction: StringName = visual_owner[coord]
			var comp_tiles: Array = [coord]
			comp_id[coord] = current_comp
			var bfs: Array = [coord]
			while not bfs.is_empty():
				var c: Vector2i = bfs.pop_back()
				for n in HexHelper.get_neighbors(c):
					if comp_id.has(n):
						continue
					if visual_owner.get(n, &"") == faction:
						comp_id[n] = current_comp
						comp_tiles.append(n)
						bfs.append(n)
			components.append({faction_id = faction, tiles = comp_tiles})
			current_comp += 1

		# Find largest component per faction
		var largest_per_faction: Dictionary = {}
		for comp in components:
			var sz: int = comp.tiles.size()
			if sz > largest_per_faction.get(comp.faction_id, 0):
				largest_per_faction[comp.faction_id] = sz

		for comp in components:
			var sz: int = comp.tiles.size()
			var largest: int = largest_per_faction.get(comp.faction_id, sz)
			# Skip if this IS the largest component or is big enough
			if sz == largest:
				continue
			if sz >= 8 and float(sz) / float(largest) >= 0.15:
				continue
			var surround_counts: Dictionary = {}
			for coord in comp.tiles:
				for n in HexHelper.get_neighbors(coord):
					var nf: StringName = visual_owner.get(n, &"")
					if nf != &"" and nf != comp.faction_id:
						surround_counts[nf] = surround_counts.get(nf, 0) + 1
			var best_faction: StringName = &""
			var best_count := 0
			for f in surround_counts:
				if surround_counts[f] > best_count:
					best_count = surround_counts[f]
					best_faction = f
			if best_faction != &"":
				for coord in comp.tiles:
					visual_owner[coord] = best_faction
				cleanup_changed = true
		if not cleanup_changed:
			break

	# Build faction color map (includes independent as grey)
	var faction_colors: Dictionary = {}
	for fid in GameManager.state.faction_states:
		var fd: FactionData = DataManager.get_faction(fid)
		if fd:
			var c: Color = fd.color.lightened(0.1)
			c.a = 0.7
			faction_colors[fid] = c
	faction_colors[&"independent"] = Color(0.7, 0.7, 0.7, 0.7)

	# Collect double-border edges: [v1, v2, inner_fid, outer_fid]
	# Collect from smaller coord only to avoid duplicates on shared edges
	var hex_points := _make_hex_polygon(HEX_RADIUS)
	var all_border_edges: Array = []

	for coord in visual_owner:
		var my_faction: StringName = visual_owner[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var neighbors := HexHelper.get_neighbors(coord)
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD

		for i in 6:
			var neighbor: Vector2i = neighbors[i]
			var n_faction: StringName = visual_owner.get(neighbor, &"")

			if n_faction == my_faction:
				continue

			# For shared edges between two owned hexes, collect from smaller coord only
			var is_map_edge := not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT)
			if not is_map_edge and n_faction != &"":
				if coord.x > neighbor.x or (coord.x == neighbor.x and coord.y > neighbor.y):
					continue

			var e: int = edge_lut[i]
			var v1: Vector2 = pixel_pos + hex_points[e]
			var v2: Vector2 = pixel_pos + hex_points[(e + 1) % 6]
			all_border_edges.append([v1, v2, my_faction, n_faction])

	var clean := _prune_faction_border_edges(all_border_edges)
	var draw_node := _DoubleBorderDrawNode.new()
	draw_node.edges = clean
	draw_node.faction_colors = faction_colors
	draw_node.line_width = 2.0
	draw_node.offset = 1.2
	_faction_border_node.add_child(draw_node)

# Removes dead-end stubs and small isolated loops from faction border edges.
# Uses coarse spatial hashing (÷16) for vertex matching — shared corners differ by
# ~0.002px (always same bucket), distinct corners are 32+px apart (always different buckets).
# Input/output edges are [v1, v2, inner_fid, outer_fid].
func _prune_faction_border_edges(raw_edges: Array) -> Array:
	if raw_edges.size() < 3:
		return raw_edges

	# Snap vertices to coarse grid for reliable matching
	# [snap_v1, snap_v2, real_v1, real_v2, inner_fid, outer_fid]
	var snap_edges: Array = []
	for edge in raw_edges:
		var v1: Vector2 = edge[0]
		var v2: Vector2 = edge[1]
		var s1 := Vector2i(roundi(v1.x / 16.0), roundi(v1.y / 16.0))
		var s2 := Vector2i(roundi(v2.x / 16.0), roundi(v2.y / 16.0))
		snap_edges.append([s1, s2, v1, v2, edge[2], edge[3]])

	# Build adjacency: vertex -> edge indices
	var adj: Dictionary = {}
	for idx in snap_edges.size():
		var s1: Vector2i = snap_edges[idx][0]
		var s2: Vector2i = snap_edges[idx][1]
		if not adj.has(s1): adj[s1] = []
		adj[s1].append(idx)
		if not adj.has(s2): adj[s2] = []
		adj[s2].append(idx)

	# Compute degrees and iteratively prune dead ends (degree-1 vertices)
	var degree: Dictionary = {}
	for v in adj:
		degree[v] = adj[v].size()
	var queue: Array = []
	for v in degree:
		if degree[v] == 1:
			queue.append(v)
	var removed: Dictionary = {}
	while queue.size() > 0:
		var v = queue.pop_front()
		if degree.get(v, 0) != 1:
			continue
		for eidx in adj[v]:
			if removed.has(eidx):
				continue
			removed[eidx] = true
			var se: Array = snap_edges[eidx]
			var other: Vector2i = se[0] if se[1] == v else se[1]
			degree[other] -= 1
			if degree[other] == 1:
				queue.append(other)
			break
		degree[v] = 0

	# Collect surviving edges and rebuild adjacency for component detection
	var surviving: Array = []
	var adj2: Dictionary = {}
	for idx in snap_edges.size():
		if removed.has(idx):
			continue
		surviving.append(idx)
		var s1: Vector2i = snap_edges[idx][0]
		var s2: Vector2i = snap_edges[idx][1]
		if not adj2.has(s1): adj2[s1] = []
		adj2[s1].append(idx)
		if not adj2.has(s2): adj2[s2] = []
		adj2[s2].append(idx)

	# BFS connected components — filter out very small artifact loops (< 3 edges)
	var visited: Dictionary = {}
	var result: Array = []
	for start_idx in surviving:
		if visited.has(start_idx):
			continue
		var bfs: Array = [start_idx]
		visited[start_idx] = true
		var comp: Array = []
		while bfs.size() > 0:
			var eidx: int = bfs.pop_front()
			comp.append(eidx)
			var se: Array = snap_edges[eidx]
			for sv in [se[0], se[1]]:
				for nb in adj2.get(sv, []):
					if not visited.has(nb):
						visited[nb] = true
						bfs.append(nb)
		if comp.size() >= 3:
			for eidx in comp:
				var se: Array = snap_edges[eidx]
				result.append([se[2], se[3], se[4], se[5]])
	return result

class _BorderDrawNode extends Node2D:
	var edges: Array = []
	var line_color: Color = Color.WHITE
	var line_width: float = 2.0
	func _draw() -> void:
		for edge in edges:
			draw_line(edge[0], edge[1], line_color, line_width, true)

class _OverlayDrawNode extends Node2D:
	var polys: Array = []  # Array of PackedVector2Array (world-space)
	var color: Color = Color.WHITE
	func _draw() -> void:
		for poly in polys:
			draw_colored_polygon(poly, color)

class _MultiColorOverlayDrawNode extends Node2D:
	var entries: Array = []  # Array of [PackedVector2Array, Color]
	func _draw() -> void:
		for entry in entries:
			draw_colored_polygon(entry[0], entry[1])

class _CaravanDrawNode extends Node2D:
	## Trade cart seen from ABOVE (like everything else on the map), tinted by
	## relation to the player: blue = yours, green = allied, white = neutral,
	## red = enemy. `heading` is set from its direction of travel each frame.
	var tint := Color(0.92, 0.92, 0.92)
	var heading := 0.0
	func _draw() -> void:
		var d := Vector2(cos(heading), sin(heading))
		var p := Vector2(-d.y, d.x)
		# Ground shadow
		draw_colored_polygon(PackedVector2Array([
			-d * 4.0 - p * 2.6 + Vector2(1, 1), d * 4.6 - p * 2.6 + Vector2(1, 1),
			d * 4.6 + p * 2.6 + Vector2(1, 1), -d * 4.0 + p * 2.6 + Vector2(1, 1)
		]), Color(0, 0, 0, 0.3))
		# Draught animal at the front
		draw_colored_polygon(PackedVector2Array([
			d * 4.4 - p * 1.3, d * 7.4 - p * 0.9, d * 7.4 + p * 0.9, d * 4.4 + p * 1.3
		]), Color(0.35, 0.26, 0.18))
		# Wheels (dark discs on both flanks, seen from above)
		for side: float in [-1.0, 1.0]:
			draw_circle(d * 2.2 + p * 2.9 * side, 1.5, Color(0.14, 0.11, 0.09))
			draw_circle(-d * 2.4 + p * 2.9 * side, 1.5, Color(0.14, 0.11, 0.09))
		# Cart bed + canvas tilt roof (the bit you actually see from above)
		draw_colored_polygon(PackedVector2Array([
			-d * 4.0 - p * 2.4, d * 4.2 - p * 2.4, d * 4.2 + p * 2.4, -d * 4.0 + p * 2.4
		]), Color(0.42, 0.3, 0.18))
		draw_colored_polygon(PackedVector2Array([
			-d * 3.2 - p * 1.9, d * 3.4 - p * 1.9, d * 3.4 + p * 1.9, -d * 3.2 + p * 1.9
		]), Color(0.88, 0.85, 0.76))
		# Relation stripe down the canvas
		draw_line(-d * 3.2, d * 3.4, tint, 1.6)

class _TradeRouteDrawNode extends Node2D:
	var routes: Array = [] # Array of {points: PackedVector2Array, color: Color}
	func _draw() -> void:
		var dash_len := 6.0
		var gap_len := 4.0
		for route in routes:
			var pts: PackedVector2Array = route.points
			var col: Color = route.color
			# Packed-earth road bed beneath the relation-tinted dashes. Thin —
			# many routes share the same corridors and a fat road turned the
			# map into spaghetti.
			if pts.size() >= 2:
				draw_polyline(pts, Color(0.32, 0.25, 0.17, 0.55), 3.0, true)
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var seg_len := a.distance_to(b)
				if seg_len < 0.1:
					continue
				var dir := (b - a) / seg_len
				var drawn := 0.0
				var is_dash := true
				while drawn < seg_len:
					var chunk := dash_len if is_dash else gap_len
					var end := minf(drawn + chunk, seg_len)
					if is_dash:
						draw_line(a + dir * drawn, a + dir * end, col, 1.4, true)
					drawn = end
					is_dash = not is_dash

class _HexChunkNode extends Node2D:
	## Batched hex tile renderer — draws all tiles in a chunk with a single _draw() call.
	## Each entry: [polygon, color, texture, uv_array]
	var tile_entries: Array = []  # Array of [PackedVector2Array, Color, Texture2D_or_null, PackedVector2Array_or_null]
	var shore_entries: Array = []  # Array of [band_poly, color] — land bleed into water tiles
	var foam_lines: Array = []     # Array of PackedVector2Array — foam line inside each band

	const _FOAM_COLOR := Color(0.85, 0.9, 0.92, 0.5)

	func _draw() -> void:
		for entry in tile_entries:
			var poly: PackedVector2Array = entry[0]
			var col: Color = entry[1]
			var tex: Texture2D = entry[2]
			if tex:
				draw_colored_polygon(poly, col, entry[3], tex)
			else:
				draw_colored_polygon(poly, col)
		for shore in shore_entries:
			draw_colored_polygon(shore[0], shore[1])
		for foam in foam_lines:
			draw_polyline(foam, _FOAM_COLOR, 1.8, true)

class _WaterAnimOverlay extends Node2D:
	## Single node that draws a transparent animated overlay on all water tiles.
	## All hexes are merged into ONE indexed triangle array — issuing one
	## polygon command per water tile (~2-3k) cost several ms of render-server
	## CPU every frame. The ShaderMaterial animates the waves.
	var water_polys: Array = []  # Array of PackedVector2Array (world-space)
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _idx := PackedInt32Array()

	func _draw() -> void:
		if _pts.is_empty():
			for poly in water_polys:
				var base := _pts.size()
				_pts.append_array(poly)
				for i in poly.size():
					_cols.append(Color.WHITE)
				for i in range(1, poly.size() - 1):
					_idx.append(base)
					_idx.append(base + i)
					_idx.append(base + i + 1)
		if _pts.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)

class _FogDrawNode extends Node2D:
	## Whole-map fog as ONE indexed triangle array. Geometry is built once;
	## fog changes only rewrite the per-vertex COLORS of affected tiles and
	## queue a single-command redraw. Camera moves cost nothing (the canvas
	## item persists; the GPU culls off-screen triangles). The previous
	## implementation issued up to ~9k draw_colored_polygon calls per redraw
	## and redrew on every camera move — ~90 ms frames while panning.
	var tile_polys: Dictionary = {}   # coord -> PackedVector2Array (world-space)
	var tile_alphas: Dictionary = {}  # coord -> float (0.0=visible, 0.45=explored, 0.75=hidden)

	const _FOG_BASE := Color(0.03, 0.02, 0.05)
	var _points := PackedVector2Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()
	var _tile_vert_start: Dictionary = {}  # coord -> first vertex index

	func build_geometry() -> void:
		_points.clear()
		_colors.clear()
		_indices.clear()
		_tile_vert_start.clear()
		for coord in tile_polys:
			var poly: PackedVector2Array = tile_polys[coord]
			var base := _points.size()
			_tile_vert_start[coord] = base
			_points.append_array(poly)
			var c := Color(_FOG_BASE.r, _FOG_BASE.g, _FOG_BASE.b, tile_alphas.get(coord, 0.0))
			for i in poly.size():
				_colors.append(c)
			for i in range(1, poly.size() - 1):
				_indices.append(base)
				_indices.append(base + i)
				_indices.append(base + i + 1)

	func set_tile_alpha(coord: Vector2i, alpha: float) -> void:
		tile_alphas[coord] = alpha
		var base: int = _tile_vert_start.get(coord, -1)
		if base < 0:
			return
		var c := Color(_FOG_BASE.r, _FOG_BASE.g, _FOG_BASE.b, alpha)
		for i in 6:
			_colors[base + i] = c

	func _draw() -> void:
		if _points.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)

class _ElevationDrawNode extends Node2D:
	var cliff_polys: Array = []
	var medium_polys: Array = []
	var subtle_polys: Array = []
	var highlight_edges: Array = []
	func _draw() -> void:
		for poly in cliff_polys:
			draw_colored_polygon(poly, Color(0.06, 0.05, 0.04, 0.7))
		for poly in medium_polys:
			draw_colored_polygon(poly, Color(0.08, 0.07, 0.06, 0.5))
		for poly in subtle_polys:
			draw_colored_polygon(poly, Color(0.1, 0.09, 0.08, 0.35))
		for e in highlight_edges:
			draw_line(e[0], e[1], Color(0.65, 0.6, 0.55, 0.4), 1.5, true)

class _BatchedTerrainDetailNode extends Node2D:
	var polygon_data: Array = []  # Array of [PackedVector2Array, Color]
	var line_data: Array = []  # Array of [PackedVector2Array, float width, Color]
	func _draw() -> void:
		for entry in polygon_data:
			draw_colored_polygon(entry[0], entry[1])
		for entry in line_data:
			draw_polyline(entry[0], entry[2], entry[1])

class _DoubleBorderDrawNode extends Node2D:
	var edges: Array = []  # [v1, v2, inner_fid, outer_fid]
	var faction_colors: Dictionary = {}
	var line_width := 3.5
	var offset := 2.4
	var separator_width := 1.5
	func _draw() -> void:
		for edge in edges:
			var d: Vector2 = edge[1] - edge[0]
			# n points inward (toward source hex center) for CCW polygon winding
			var n := Vector2(-d.y, d.x).normalized()
			var ic: Color = faction_colors.get(edge[2], Color(0.7, 0.7, 0.7, 0.7))
			# Dark grey shadow on inner side of faction line (depth effect)
			draw_line(edge[0] + n * (offset + line_width * 0.5 + 0.8), edge[1] + n * (offset + line_width * 0.5 + 0.8), Color(0.15, 0.13, 0.12, 0.7), line_width * 0.6, true)
			# Inner faction line on inner side (+n = toward source hex)
			draw_line(edge[0] + n * offset, edge[1] + n * offset, ic, line_width, true)
			if edge[3] != &"":
				# Outer faction line on outer side (-n = toward neighbor hex)
				var oc: Color = faction_colors.get(edge[3], Color(0.7, 0.7, 0.7, 0.7))
				# Dark grey shadow on inner side of outer faction line
				draw_line(edge[0] - n * (offset + line_width * 0.5 + 0.8), edge[1] - n * (offset + line_width * 0.5 + 0.8), Color(0.15, 0.13, 0.12, 0.7), line_width * 0.6, true)
				draw_line(edge[0] - n * offset, edge[1] - n * offset, oc, line_width, true)
				# Black separator line between the two colored lines
				draw_line(edge[0], edge[1], Color(0.0, 0.0, 0.0, 0.9), separator_width, true)

func _refresh_faction_borders() -> void:
	_draw_faction_borders()

func _create_region_labels() -> void:
	for region_id in MapGenerator.REGION_SEEDS:
		var region: RegionData = DataManager.get_region(region_id)
		if region == null:
			continue
		var center: Vector2i = MapGenerator.REGION_SEEDS[region_id]
		var pixel_pos := _hex_to_pixel(center)

		# Panel background behind the label
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.04, 0.08, 0.75)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.45, 0.35, 0.2, 0.7)
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_right = 3
		style.corner_radius_bottom_left = 3
		style.content_margin_left = 4.0
		style.content_margin_top = 2.0
		style.content_margin_right = 4.0
		style.content_margin_bottom = 2.0
		panel.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.text = region.display_name
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7, 0.95))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("outline_size", 3)
		panel.add_child(label)

		panel.position = pixel_pos + Vector2(-50, 14)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_region_label_clicked.bind(region_id))
		region_labels_node.add_child(panel)

func _on_region_label_clicked(event: InputEvent, region_id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hud: Control = $UILayer/HUD
		hud._show_region_overview(region_id)

const CULTURE_COLORS := {
	&"frostlands": Color(0.55, 0.7, 0.9),
	&"storm_peaks": Color(0.6, 0.5, 0.8),
	&"western_marches": Color(0.3, 0.7, 0.45),
	&"imperial_heartland": Color(0.85, 0.75, 0.35),
	&"ashlands": Color(0.8, 0.4, 0.25),
	&"central_steppe": Color(0.65, 0.55, 0.35),
	&"emerald_south": Color(0.25, 0.6, 0.3),
	&"southern_reaches": Color(0.5, 0.4, 0.55),
	&"eastern_wastes": Color(0.75, 0.55, 0.5),
}

func _update_political_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# Recolor chunk tile entries via the coord -> entry index map built at
	# chunk creation. Track which chunks actually changed color so unchanged
	# chunks are not redrawn and a no-op update skips the overview rebuild
	# and the full map rebake entirely.
	var dirty_chunks: Dictionary = {}
	for coord in hex_map.tiles:
		var lookup: Dictionary = _hex_tile_chunk_data.get(coord, {})
		if lookup.is_empty():
			continue
		var chunk: _HexChunkNode = _hex_chunks.get(lookup.chunk_key)
		if chunk == null:
			continue
		var entry: Array = chunk.tile_entries[lookup.entry_idx]
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var has_tex: bool = entry[2] != null
		var new_color: Color = entry[1]
		if _minimap_view_mode == 1:
			if tile.owner_faction != &"" and tile.owner_faction != &"independent":
				var fd: FactionData = DataManager.get_faction(tile.owner_faction)
				if fd:
					var pc: Color = fd.color
					pc.s = minf(pc.s * 1.4, 1.0)
					new_color = pc.lightened(0.15)
				else:
					new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
			else:
				new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
		elif _minimap_view_mode == 2:
			var cul_id: StringName = GameManager.REGION_CULTURE.get(tile.region_id, &"")
			if cul_id != &"":
				var cc: Color = CULTURE_COLORS.get(cul_id, Color(0.5, 0.5, 0.5))
				cc.s = minf(cc.s * 1.3, 1.0)
				new_color = cc.lightened(0.1)
			else:
				new_color = Color(0.35, 0.33, 0.3) if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
		else:
			# Terrain view: restore original colors (with faction tint)
			var base_color: Color = Color.WHITE if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
			if tile.owner_faction != &"" and tile.owner_faction != &"independent":
				var fd2: FactionData = DataManager.get_faction(tile.owner_faction)
				if fd2:
					base_color = base_color.lerp(fd2.color, 0.12)
			new_color = base_color
		if new_color != entry[1]:
			entry[1] = new_color
			dirty_chunks[lookup.chunk_key] = true

	if dirty_chunks.is_empty():
		return # Nothing changed — skip chunk redraws, overview rebuild, and rebake

	for chunk_key: Vector2i in dirty_chunks:
		_hex_chunks[chunk_key].queue_redraw()
	_update_overview_colors()
	_request_rebake()

# ── Army markers ──────────────────────────────────────────────

func _create_army_markers() -> void:
	# Only rebuild if army set changed; otherwise just update positions
	var need_rebuild := false
	if _army_markers.size() != GameManager.state.armies.size():
		need_rebuild = true
	else:
		for army_id in GameManager.state.armies:
			if not _army_markers.has(army_id):
				need_rebuild = true
				break
	if not need_rebuild:
		# Fast path: just update positions
		for army_id in _army_markers:
			var army: ArmyState = GameManager.state.armies.get(army_id)
			if army:
				_army_markers[army_id].position = _hex_to_pixel(army.hex_pos)
		return

	for child in army_markers_node.get_children():
		child.queue_free()
	_army_markers.clear()

	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		_create_army_marker(army)

# ── Marker vector-art helpers ────────────────────────────────
# Shared visual language for map markers: dark silhouette outline, bronze/gold
# trim (matches the UI frames), faction color on cloth/roofs, soft ground shadow.
const _MARKER_OUTLINE := Color(0.07, 0.055, 0.045, 0.95)
const _MARKER_GOLD := Color(0.78, 0.62, 0.32)
const _MARKER_STONE := Color(0.42, 0.38, 0.33)
const _MARKER_STONE_LIGHT := Color(0.5, 0.46, 0.4)

func _marker_poly(parent: Node2D, pts: PackedVector2Array, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = color
	p.antialiased = true
	parent.add_child(p)
	return p

func _marker_line(parent: Node2D, pts: PackedVector2Array, color: Color, width: float, closed := false) -> Line2D:
	var l := Line2D.new()
	l.points = pts
	l.width = width
	l.default_color = color
	l.antialiased = true
	l.closed = closed
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(l)
	return l

func _ellipse_pts(center: Vector2, rx: float, ry: float, segs := 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _ellipse_arc_pts(center: Vector2, rx: float, ry: float, a0: float, a1: float, segs := 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var a := lerpf(a0, a1, float(i) / float(segs))
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

static func _scaled_pts(pts: PackedVector2Array, s: float, origin := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(origin + (p - origin) * s)
	return out

var _rounded_hex_cache: Dictionary = {}

## Hexagon (same flat-top orientation as the tiles) with rounded-off corners —
## used for the ownership ring that hugs the inner side of the tile border
func _rounded_hex_pts(radius: float, corner_r: float) -> PackedVector2Array:
	var key := Vector2(radius, corner_r)
	if _rounded_hex_cache.has(key):
		return _rounded_hex_cache[key]
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		var c := Vector2(cos(a), sin(a)) * radius
		var prev := Vector2(cos(a - deg_to_rad(60.0)), sin(a - deg_to_rad(60.0))) * radius
		var next := Vector2(cos(a + deg_to_rad(60.0)), sin(a + deg_to_rad(60.0))) * radius
		var p0 := c + (prev - c).normalized() * corner_r
		var p1 := c + (next - c).normalized() * corner_r
		for k in 4:
			var t := float(k) / 3.0
			pts.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
	_rounded_hex_cache[key] = pts
	return pts

## Ownership ring radius: just inside the tile's inner border
const _CITY_RING_RADIUS := 33.0
const _CITY_RING_CORNER := 6.5

## Markers grow when the camera zooms out so they stay readable
func _update_marker_zoom_scale(cam_zoom: float) -> void:
	var boost := clampf(1.0 / maxf(cam_zoom, 0.001), 1.0, 2.0)
	if is_equal_approx(boost, _marker_zoom_boost):
		return
	_marker_zoom_boost = boost
	for d: Dictionary in [_city_markers, _army_markers]:
		for k in d:
			var m: Node2D = d[k]
			if is_instance_valid(m):
				m.scale = Vector2.ONE * m.get_meta("base_scale", 1.0) * boost
	for m in _building_tile_markers:
		if is_instance_valid(m):
			m.scale = Vector2.ONE * m.get_meta("base_scale", 1.0) * boost

## Diplomatic relation color for marker base rings: blue = yours, green =
## allied, light green = friendly, red = at war/hostile, white = neutral.
func _relation_ring_color(faction_id: StringName) -> Color:
	var player_id := GameManager.state.player_faction_id
	if faction_id == player_id:
		return Color(0.3, 0.5, 1.0)
	if faction_id == &"" or faction_id == &"independent" or faction_id == &"rebels":
		return Color(0.9, 0.9, 0.9)
	var relation := GameManager.get_relation(player_id, faction_id)
	if relation == Enums.FactionRelation.ALLIED:
		return Color(0.2, 0.85, 0.3)
	if relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
		return Color(0.95, 0.2, 0.15)
	if relation == Enums.FactionRelation.FRIENDLY:
		return Color(0.2, 0.85, 0.3, 0.7)
	return Color(0.9, 0.9, 0.9)

## Culture that decides a faction's marker SHAPES. Minor factions use their
## parent's set but render in their own faction color, so subfactions stay
## distinguishable by color.
func _marker_culture(faction_id: StringName) -> StringName:
	var parent: StringName = GameManager.MINOR_FACTION_PARENTS.get(faction_id, faction_id)
	return parent

# ── Per-culture army shield art ──────────────────────────────
# Envelope roughly x in [-10, 10], y in [-13, 12]; the unit-count roundel
# (drawn by the caller) sits at (0, -3.5) r 6.2 and covers the center.

func _draw_army_shield_art(marker: Node2D, culture: StringName, fc: Color) -> void:
	match culture:
		&"empire": _shield_scutum(marker, fc)
		&"skulloath": _shield_horde_round(marker, fc)
		&"gladehost": _shield_leaf(marker, fc)
		&"tainted_jade": _shield_serpent_disc(marker, fc)
		&"moonspear": _shield_crescent(marker, fc)
		&"sunblessed": _shield_sunray(marker, fc)
		&"thunderswarm": _shield_bolt(marker, fc)
		&"cinderguard": _shield_kite(marker, fc)
		&"forsaken": _shield_tattered(marker, fc)
		&"ivoryscar": _shield_relic(marker, fc)
		&"shardhorde": _shield_crystal(marker, fc)
		_: _shield_heater(marker, fc)

func _shield_base(marker: Node2D, pts: PackedVector2Array, fc: Color, center := Vector2(0, -1)) -> void:
	# Outline silhouette → gold rim → faction-color field
	_marker_poly(marker, _scaled_pts(pts, 1.22, center), _MARKER_OUTLINE)
	_marker_poly(marker, _scaled_pts(pts, 1.1, center), _MARKER_GOLD)
	_marker_poly(marker, pts, fc)

func _shield_heater(marker: Node2D, fc: Color) -> void:
	var shield := PackedVector2Array([
		Vector2(-9, -11), Vector2(9, -11), Vector2(9, -3), Vector2(8, 2),
		Vector2(5.5, 6), Vector2(2.5, 8.6), Vector2(0, 10),
		Vector2(-2.5, 8.6), Vector2(-5.5, 6), Vector2(-8, 2), Vector2(-9, -3)
	])
	_shield_base(marker, shield, fc)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-9, -4), Vector2(0, 1), Vector2(9, -4),
		Vector2(9, 0), Vector2(0, 5), Vector2(-9, 0)
	]), fc.darkened(0.3))
	_marker_line(marker, PackedVector2Array([Vector2(-7.5, -10), Vector2(7.5, -10)]),
		Color(1, 1, 1, 0.3), 1.4)

func _shield_scutum(marker: Node2D, fc: Color) -> void:
	# Roman tower shield: chamfered rectangle, gold spine + wing chevrons
	var shield := PackedVector2Array([
		Vector2(-7, -12), Vector2(7, -12), Vector2(8.4, -10), Vector2(8.4, 8),
		Vector2(7, 10), Vector2(-7, 10), Vector2(-8.4, 8), Vector2(-8.4, -10)
	])
	_shield_base(marker, shield, fc)
	_marker_line(marker, PackedVector2Array([Vector2(0, -11.2), Vector2(0, 9.2)]),
		_MARKER_GOLD, 1.3)
	_marker_line(marker, PackedVector2Array([Vector2(-6.4, -10.4), Vector2(-3.2, -7.6)]),
		_MARKER_GOLD, 1.1)
	_marker_line(marker, PackedVector2Array([Vector2(6.4, -10.4), Vector2(3.2, -7.6)]),
		_MARKER_GOLD, 1.1)

func _shield_horde_round(marker: Node2D, fc: Color) -> void:
	# Round hide shield with horn studs on the rim
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		var tip := Vector2(0, -1) + Vector2(cos(a), sin(a)) * 12.6
		var b1 := Vector2(0, -1) + Vector2(cos(a + 0.18), sin(a + 0.18)) * 9.4
		var b2 := Vector2(0, -1) + Vector2(cos(a - 0.18), sin(a - 0.18)) * 9.4
		_marker_poly(marker, PackedVector2Array([tip, b1, b2]), Color(0.85, 0.8, 0.7))

func _shield_leaf(marker: Node2D, fc: Color) -> void:
	# Leaf-shaped wooden shield with vine trim
	var shield := PackedVector2Array([
		Vector2(0, -13), Vector2(5.5, -8), Vector2(7.5, -1), Vector2(5, 6),
		Vector2(0, 11), Vector2(-5, 6), Vector2(-7.5, -1), Vector2(-5.5, -8)
	])
	_shield_base(marker, shield, fc)
	_marker_line(marker, PackedVector2Array([
		Vector2(0, -12), Vector2(1.6, -8.4), Vector2(-1.2, -5.2), Vector2(1.2, 3.4), Vector2(0, 9.6)
	]), _MARKER_GOLD, 1.0)

func _shield_serpent_disc(marker: Node2D, fc: Color) -> void:
	# Jade disc with coiled serpent rings
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0, -1), 8.0, 8.0, -PI * 0.4, PI * 0.9, 10),
		fc.lightened(0.3), 1.2)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0, -1), 8.0, 8.0, PI * 0.55, PI * 0.75, 3),
		_MARKER_GOLD, 1.4)

func _shield_crescent(marker: Node2D, fc: Color) -> void:
	# Round shield with a gold crescent along the left rim
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0, -1), 7.6, 7.6, PI * 0.6, PI * 1.4, 10),
		_MARKER_GOLD, 2.0)

func _shield_sunray(marker: Node2D, fc: Color) -> void:
	# Round shield with gold rays radiating from the boss
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI / 8.0
		_marker_line(marker, PackedVector2Array([
			Vector2(0, -2.5) + Vector2(cos(a), sin(a)) * 6.8,
			Vector2(0, -2.5) + Vector2(cos(a), sin(a)) * 9.2
		]), _MARKER_GOLD, 1.3)

func _shield_bolt(marker: Node2D, fc: Color) -> void:
	# Round rimmed shield with a jagged lightning bolt across the face
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	_marker_line(marker, PackedVector2Array([
		Vector2(-3.2, -9.4), Vector2(0.8, -3.4), Vector2(-1.2, -2.2), Vector2(3.2, 7.2)
	]), _MARKER_GOLD, 1.6)

func _shield_kite(marker: Node2D, fc: Color) -> void:
	# Heavy riveted kite shield with an ember slit
	var shield := PackedVector2Array([
		Vector2(-8.5, -10), Vector2(8.5, -10), Vector2(7.8, -3),
		Vector2(5, 5), Vector2(0, 11), Vector2(-5, 5), Vector2(-7.8, -3)
	])
	_shield_base(marker, shield, fc)
	for i in 4:
		var rx := -6.0 + 4.0 * float(i)
		_marker_poly(marker, _ellipse_pts(Vector2(rx, -8.6), 0.7, 0.7, 6), _MARKER_GOLD)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-0.8, 3.4), Vector2(0.8, 3.4), Vector2(0.8, 7.6), Vector2(-0.8, 7.6)
	]), Color(0.95, 0.5, 0.15, 0.95))

func _shield_tattered(marker: Node2D, fc: Color) -> void:
	# Dark heater with a ragged bottom edge and pale dagger
	var shield := PackedVector2Array([
		Vector2(-9, -10), Vector2(9, -10), Vector2(9, -2), Vector2(7, 3),
		Vector2(5, 1.6), Vector2(4, 6), Vector2(1.5, 4), Vector2(0, 9),
		Vector2(-2, 4), Vector2(-4.5, 6.4), Vector2(-6, 1.6), Vector2(-8, 3.4), Vector2(-9, -2)
	])
	_shield_base(marker, shield, fc.darkened(0.15))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-0.9, -9), Vector2(0.9, -9), Vector2(0.9, 4), Vector2(0, 7), Vector2(-0.9, 4)
	]), Color(0.85, 0.82, 0.75, 0.75))

func _shield_relic(marker: Node2D, fc: Color) -> void:
	# Faction field with bone inner ring and relic eye below the boss
	var shield := _ellipse_pts(Vector2(0, -1), 10.0, 10.0, 18)
	_shield_base(marker, shield, fc)
	_marker_line(marker, _ellipse_pts(Vector2(0, -1), 8.6, 8.6, 16), Color(0.88, 0.84, 0.72), 1.2)
	_marker_line(marker, _ellipse_pts(Vector2(0, 5.8), 1.9, 1.1, 8), Color(0.88, 0.84, 0.72), 0.9)
	_marker_poly(marker, _ellipse_pts(Vector2(0, 5.8), 0.6, 0.6, 6), Color(0.1, 0.08, 0.06))

func _shield_crystal(marker: Node2D, fc: Color) -> void:
	# Jagged crystal-edged shield with facet lines
	var shield := PackedVector2Array([
		Vector2(-3, -12), Vector2(4, -10.5), Vector2(9, -4), Vector2(7.4, 2.4),
		Vector2(3, 10), Vector2(-2, 8.4), Vector2(-8, 5), Vector2(-9.4, -4.6)
	])
	_shield_base(marker, shield, fc)
	_marker_line(marker, PackedVector2Array([Vector2(-6.8, 3.6), Vector2(-2.2, -2.6)]),
		fc.lightened(0.35), 1.0)
	_marker_line(marker, PackedVector2Array([Vector2(5.6, -6.8), Vector2(2.4, -9.4)]),
		fc.lightened(0.35), 1.0)

# ── Top-down town art ────────────────────────────────────────
# Cities and settlements are drawn from ABOVE like the terrain, so growth is
# directly visible: footprint, building count, walls and the central landmark
# all scale with city level (1-5). Culture decides building shapes, wall style
# and the landmark; faction color stays on roofs and banners so subfactions
# remain distinguishable.

func _town_radius(level: int) -> float:
	return 8.5 + float(clampi(level, 1, 5)) * 2.6

func _town_style(culture: StringName) -> Dictionary:
	match culture:
		&"empire":
			return {"ground": Color(0.56, 0.51, 0.42), "roof": Color(0.63, 0.3, 0.22), "hut": "rect", "wall": "square"}
		&"skulloath":
			return {"ground": Color(0.5, 0.43, 0.33), "roof": Color(0.44, 0.35, 0.27), "hut": "yurt", "wall": "palisade"}
		&"gladehost":
			# Dirt clearing + wooden lodges so the city stays visible against
			# forest terrain (the great-tree landmark carries the tree identity)
			return {"ground": Color(0.46, 0.39, 0.27), "roof": Color(0.55, 0.42, 0.26), "hut": "rect", "wall": "palisade"}
		&"tainted_jade":
			return {"ground": Color(0.42, 0.46, 0.38), "roof": Color(0.24, 0.5, 0.38), "hut": "pagoda", "wall": "square"}
		&"moonspear":
			return {"ground": Color(0.44, 0.47, 0.54), "roof": Color(0.78, 0.82, 0.92), "hut": "crescent", "wall": "round"}
		&"sunblessed":
			return {"ground": Color(0.66, 0.58, 0.42), "roof": Color(0.88, 0.72, 0.34), "hut": "dome", "wall": "round"}
		&"thunderswarm":
			return {"ground": Color(0.42, 0.44, 0.5), "roof": Color(0.52, 0.58, 0.7), "hut": "spire", "wall": "round"}
		&"cinderguard":
			return {"ground": Color(0.46, 0.42, 0.38), "roof": Color(0.52, 0.48, 0.44), "hut": "rect", "wall": "fortress"}
		&"forsaken":
			return {"ground": Color(0.36, 0.34, 0.36), "roof": Color(0.32, 0.3, 0.34), "hut": "ruin", "wall": "round"}
		&"ivoryscar":
			return {"ground": Color(0.62, 0.56, 0.44), "roof": Color(0.82, 0.78, 0.66), "hut": "ziggurat", "wall": "square"}
		&"shardhorde":
			return {"ground": Color(0.46, 0.4, 0.48), "roof": Color(0.58, 0.42, 0.7), "hut": "crystal", "wall": "round"}
		_:
			return {"ground": Color(0.5, 0.47, 0.4), "roof": Color(0.46, 0.43, 0.39), "hut": "rect", "wall": "square"}

func _town_patch(rng: RandomNumberGenerator, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		var w := 1.0 + rng.randf_range(-0.07, 0.07)
		pts.append(Vector2(cos(a) * rx * w, sin(a) * ry * w))
	return pts

## Axis-aligned or rotated square centered on c with half-extent `half`
func _town_sq(marker: Node2D, c: Vector2, half: float, rot: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 4:
		var a := rot + PI * 0.25 + TAU * float(i) / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * half * 1.414)
	_marker_poly(marker, pts, color)

## One building seen from above, in the culture's shape language
func _town_building(marker: Node2D, rng: RandomNumberGenerator, hut: String, ground: Color, pos: Vector2, s: float, roof: Color) -> void:
	match hut:
		"yurt":
			_marker_poly(marker, _ellipse_pts(pos, s * 1.15, s * 1.15, 10), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(pos, s, s, 10), roof)
			for i in 5:
				var a := TAU * float(i) / 5.0 + 0.3
				_marker_line(marker, PackedVector2Array([pos, pos + Vector2(cos(a), sin(a)) * s * 0.9]),
					roof.darkened(0.25), 0.7)
			_marker_poly(marker, _ellipse_pts(pos, s * 0.28, s * 0.28, 6), roof.lightened(0.3))
		"canopy":
			_marker_poly(marker, _ellipse_pts(pos + Vector2(0.7, 0.9), s * 1.25, s * 1.25, 9), Color(0.1, 0.16, 0.09, 0.55))
			_marker_poly(marker, _ellipse_pts(pos, s * 1.2, s * 1.2, 9), roof.darkened(0.15))
			_marker_poly(marker, _ellipse_pts(pos + Vector2(-s * 0.25, -s * 0.25), s * 0.65, s * 0.65, 8), roof.lightened(0.18))
		"pagoda":
			_town_sq(marker, pos, s * 1.35, PI * 0.25, _MARKER_OUTLINE)
			_town_sq(marker, pos, s * 1.2, PI * 0.25, roof.darkened(0.2))
			_town_sq(marker, pos, s * 0.72, 0.0, roof)
			_marker_poly(marker, _ellipse_pts(pos, s * 0.2, s * 0.2, 6), _MARKER_GOLD)
		"crescent":
			# Moon-sanctum: pale disc with a crescent bite toward a random side
			_marker_poly(marker, _ellipse_pts(pos, s * 1.15, s * 1.15, 10), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(pos, s, s, 10), roof)
			var ba := rng.randf() * TAU
			_marker_poly(marker, _ellipse_pts(pos + Vector2(cos(ba), sin(ba)) * s * 0.55, s * 0.72, s * 0.72, 10), ground)
		"dome":
			_marker_poly(marker, _ellipse_pts(pos, s * 1.15, s * 1.15, 10), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(pos, s, s, 10), roof)
			_marker_poly(marker, _ellipse_pts(pos + Vector2(-s * 0.3, -s * 0.3), s * 0.35, s * 0.35, 8), roof.lightened(0.3))
			_marker_poly(marker, _ellipse_pts(pos, s * 0.22, s * 0.22, 6), _MARKER_GOLD)
		"spire":
			_marker_poly(marker, _ellipse_pts(pos, s * 0.85, s * 0.85, 8), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(pos, s * 0.7, s * 0.7, 8), roof)
			for i in 4:
				var a := TAU * float(i) / 4.0 + 0.4
				_marker_line(marker, PackedVector2Array([
					pos + Vector2(cos(a), sin(a)) * s * 0.5, pos + Vector2(cos(a), sin(a)) * s * 1.25
				]), roof.lightened(0.25), 0.8)
		"ziggurat":
			_town_sq(marker, pos, s * 1.3, 0.0, _MARKER_OUTLINE)
			_town_sq(marker, pos, s * 1.15, 0.0, roof.darkened(0.18))
			_town_sq(marker, pos, s * 0.7, 0.0, roof)
			_town_sq(marker, pos, s * 0.32, 0.0, roof.lightened(0.2))
		"crystal":
			var a := rng.randf() * TAU
			var d := Vector2(cos(a), sin(a))
			var p2 := Vector2(-d.y, d.x)
			var tip := pos + d * s * 1.7
			var waist := pos + d * s * 0.6
			_marker_poly(marker, PackedVector2Array([
				pos - d * s * 0.3, waist + p2 * s * 0.55, tip, waist - p2 * s * 0.55
			]), roof)
			_marker_line(marker, PackedVector2Array([pos, tip]), roof.lightened(0.35), 0.9)
		"ruin":
			var a := rng.randf() * TAU
			var d := Vector2(cos(a), sin(a))
			var p2 := Vector2(-d.y, d.x)
			var hl := d * s * 1.4
			var hw := p2 * s * 0.95
			_marker_poly(marker, PackedVector2Array([
				pos - hl - hw, pos + hl - hw, pos + hl + hw * 0.15, pos + hl * 0.35 + hw, pos - hl + hw
			]), roof)
			_marker_line(marker, PackedVector2Array([pos - hl * 0.6, pos + hl * 0.6]), roof.darkened(0.35), 0.7)
			_marker_poly(marker, _ellipse_pts(pos + hl * 0.9 + hw * 0.7, s * 0.22, s * 0.22, 5), roof.lightened(0.15))
		_:
			# Gable roof from above: ridge along the long axis splits lit/shadow
			var a := rng.randf() * TAU
			var d := Vector2(cos(a), sin(a))
			var p2 := Vector2(-d.y, d.x)
			var hl := d * s * 1.45
			var hw := p2 * s * 0.95
			_marker_poly(marker, PackedVector2Array([
				pos - hl * 1.12 - hw * 1.24, pos + hl * 1.12 - hw * 1.24,
				pos + hl * 1.12 + hw * 1.24, pos - hl * 1.12 + hw * 1.24
			]), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([pos - hl - hw, pos + hl - hw, pos + hl, pos - hl]), roof.lightened(0.12))
			_marker_poly(marker, PackedVector2Array([pos - hl, pos + hl, pos + hl + hw, pos - hl + hw]), roof.darkened(0.16))
			_marker_line(marker, PackedVector2Array([pos - hl, pos + hl]), roof.darkened(0.35), 0.7)
			# Chimney + skylight detail on larger roofs
			if s >= 2.4:
				_marker_poly(marker, _ellipse_pts(pos - hl * 0.55 - hw * 0.4, s * 0.22, s * 0.22, 6), Color(0.3, 0.26, 0.22))
				_marker_poly(marker, _ellipse_pts(pos + hl * 0.45 - hw * 0.35, s * 0.16, s * 0.16, 5), roof.lightened(0.3))

## Curtain wall ring with a south gate gap; style decides the material
func _town_wall(marker: Node2D, style: String, R: float, level: int) -> void:
	var wr := R
	var wry := R * 0.9
	var gate_half := 0.26
	var a0 := PI * 0.5 + gate_half
	var a1 := PI * 0.5 - gate_half + TAU
	match style:
		"palisade":
			var n := maxi(int(wr * 1.4), 14)
			for i in n:
				var a := lerpf(a0, a1, float(i) / float(n - 1))
				var p := Vector2(cos(a) * wr, sin(a) * wry)
				_marker_poly(marker, _ellipse_pts(p, 1.1, 1.1, 6), Color(0.33, 0.26, 0.2))
		"hedge":
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr, wry, a0, a1, 24), Color(0.22, 0.32, 0.16), 3.0)
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr * 0.97, wry * 0.97, a0, a1, 24), Color(0.32, 0.44, 0.22), 1.2)
		"fortress":
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr, wry, a0, a1, 24), _MARKER_STONE, 3.6)
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr, wry, a0, a1, 24), _MARKER_STONE_LIGHT, 1.2)
			for i in 4:
				var a := PI * 0.25 + TAU * float(i) / 4.0
				var p := Vector2(cos(a) * wr, sin(a) * wry)
				_town_sq(marker, p, 2.2, a, _MARKER_OUTLINE)
				_town_sq(marker, p, 1.8, a, _MARKER_STONE)
				_town_sq(marker, p, 0.9, a, _MARKER_STONE_LIGHT)
		"square":
			var hx := wr * 0.95
			var hy := wry * 0.92
			var gate_w := 3.2
			_marker_line(marker, PackedVector2Array([
				Vector2(gate_w, hy), Vector2(hx, hy), Vector2(hx, -hy),
				Vector2(-hx, -hy), Vector2(-hx, hy), Vector2(-gate_w, hy)
			]), _MARKER_STONE, 2.8)
			_marker_line(marker, PackedVector2Array([
				Vector2(gate_w, hy), Vector2(hx, hy), Vector2(hx, -hy),
				Vector2(-hx, -hy), Vector2(-hx, hy), Vector2(-gate_w, hy)
			]), _MARKER_STONE_LIGHT, 0.9)
			if level >= 4:
				for corner in [Vector2(hx, hy), Vector2(hx, -hy), Vector2(-hx, -hy), Vector2(-hx, hy)]:
					_marker_poly(marker, _ellipse_pts(corner, 2.2, 2.2, 8), _MARKER_OUTLINE)
					_marker_poly(marker, _ellipse_pts(corner, 1.7, 1.7, 8), _MARKER_STONE_LIGHT)
		_:
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr, wry, a0, a1, 24), _MARKER_STONE, 2.6)
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, wr, wry, a0, a1, 24), _MARKER_STONE_LIGHT, 0.9)
			if level >= 4:
				for i in 4:
					var a := PI * 0.25 + TAU * float(i) / 4.0
					var p := Vector2(cos(a) * wr, sin(a) * wry)
					_marker_poly(marker, _ellipse_pts(p, 2.1, 2.1, 8), _MARKER_OUTLINE)
					_marker_poly(marker, _ellipse_pts(p, 1.6, 1.6, 8), _MARKER_STONE_LIGHT)
	# Gate posts (gold, marking the south entrance)
	for side: float in [-1.0, 1.0]:
		var gp := Vector2(cos(PI * 0.5 + gate_half * side) * wr, sin(PI * 0.5 + gate_half * side) * wry)
		_marker_poly(marker, _ellipse_pts(gp, 1.15, 1.15, 6), _MARKER_GOLD)

## Small faction pennant — stylized ownership mark, kept even in top-down view
func _town_banner(marker: Node2D, pos: Vector2, fc: Color) -> void:
	_marker_line(marker, PackedVector2Array([pos, pos + Vector2(0, -4.2)]), Color(0.35, 0.28, 0.2), 1.0)
	_marker_poly(marker, PackedVector2Array([
		pos + Vector2(0, -4.2), pos + Vector2(3.2, -3.3), pos + Vector2(0, -2.4)
	]), fc)

## Central landmark per culture; scale and elaborateness grow with level
func _town_landmark(marker: Node2D, culture: StringName, fc: Color, level: int, ground: Color) -> void:
	var s := 3.4 + float(level) * 0.8
	match culture:
		&"empire":
			# Forum → basilica → colosseum ring
			_town_sq(marker, Vector2.ZERO, s * 1.2, 0.0, _MARKER_OUTLINE)
			_town_sq(marker, Vector2.ZERO, s * 1.05, 0.0, _MARKER_STONE_LIGHT)
			_town_sq(marker, Vector2.ZERO, s * 0.58, 0.0, fc)
			if level >= 3:
				for i in 8:
					var a := TAU * float(i) / 8.0
					_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.45, 0.7, 0.7, 6), _MARKER_STONE_LIGHT)
			if level >= 5:
				_marker_line(marker, _ellipse_pts(Vector2.ZERO, s * 1.8, s * 1.6, 18), _MARKER_GOLD, 1.0, true)
		&"skulloath":
			# Great yurt of the khan, horn standards from level 4
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.3, s * 1.3, 12), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.15, s * 1.15, 12), fc)
			for i in 6:
				var a := TAU * float(i) / 6.0
				_marker_line(marker, PackedVector2Array([Vector2.ZERO, Vector2(cos(a), sin(a)) * s * 1.05]),
					fc.darkened(0.3), 0.8)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.3, s * 0.3, 8), fc.lightened(0.3))
			if level >= 4:
				for hs: float in [-1.0, 1.0]:
					_marker_line(marker, _ellipse_arc_pts(Vector2(hs * s * 1.5, -s * 0.9), s * 0.5, s * 0.65,
						PI * 0.9, PI * 1.7, 6), Color(0.85, 0.8, 0.7), 1.2)
			if level >= 5:
				for i in 6:
					var a := TAU * float(i) / 6.0 + 0.26
					_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.75, 0.8, 0.8, 6), Color(0.3, 0.24, 0.18))
		&"gladehost":
			# The great tree, ringed by a walkway then a stone circle
			_marker_poly(marker, _ellipse_pts(Vector2(0.8, 1.0), s * 1.5, s * 1.5, 12), Color(0.08, 0.14, 0.07, 0.55))
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.45, s * 1.45, 12), fc.darkened(0.2))
			_marker_poly(marker, _ellipse_pts(Vector2(-s * 0.3, -s * 0.3), s * 0.85, s * 0.85, 10), fc)
			_marker_poly(marker, _ellipse_pts(Vector2(-s * 0.45, -s * 0.45), s * 0.35, s * 0.35, 8), fc.lightened(0.25))
			if level >= 4:
				_marker_line(marker, _ellipse_pts(Vector2.ZERO, s * 1.7, s * 1.7, 16), Color(0.45, 0.36, 0.24), 1.1, true)
			if level >= 5:
				for i in 7:
					var a := TAU * float(i) / 7.0
					_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 2.0, 0.75, 0.75, 6), _MARKER_STONE_LIGHT)
		&"tainted_jade":
			# Tiered jade pagoda
			if level >= 5:
				_town_sq(marker, Vector2.ZERO, s * 1.55, PI * 0.25, Color(0.16, 0.34, 0.26))
			_town_sq(marker, Vector2.ZERO, s * 1.3, PI * 0.25, _MARKER_OUTLINE)
			_town_sq(marker, Vector2.ZERO, s * 1.15, PI * 0.25, Color(0.2, 0.42, 0.32))
			_town_sq(marker, Vector2.ZERO, s * 0.78, 0.0, fc)
			_town_sq(marker, Vector2.ZERO, s * 0.4, PI * 0.25, Color(0.3, 0.56, 0.42))
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.16, s * 0.16, 6), _MARKER_GOLD)
		&"moonspear":
			# Moonwell sanctum of the spirit crusaders: glowing well embraced by
			# a silver crescent, spirit wisps and spear pennants at high levels
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.6, s * 1.6, 14), Color(0.75, 0.85, 1.0, 0.16))
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.85, s * 0.85, 12), Color(0.45, 0.62, 0.85))
			_marker_poly(marker, _ellipse_pts(Vector2(-s * 0.16, -s * 0.16), s * 0.45, s * 0.45, 10), Color(0.85, 0.93, 1.0))
			_marker_line(marker, _ellipse_arc_pts(Vector2.ZERO, s * 1.2, s * 1.2, PI * 0.85, TAU + PI * 0.15, 16),
				Color(0.88, 0.9, 0.98), maxf(1.6, s * 0.3))
			if level >= 3:
				for i in 3 + level - 3:
					var a := TAU * float(i) / float(3 + level - 3) + 0.7
					_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.55, 0.55, 0.55, 6),
						Color(0.8, 0.9, 1.0, 0.7))
			if level >= 4:
				for i in 4:
					var a := PI * 0.25 + TAU * float(i) / 4.0
					var bp := Vector2(cos(a), sin(a)) * s * 1.9
					_marker_line(marker, PackedVector2Array([bp, bp + Vector2(0, -3.6)]), Color(0.75, 0.8, 0.9), 0.9)
					_marker_poly(marker, PackedVector2Array([
						bp + Vector2(0, -3.6), bp + Vector2(2.4, -2.9), bp + Vector2(0, -2.2)
					]), fc)
			if level >= 5:
				_marker_line(marker, _ellipse_pts(Vector2.ZERO, s * 2.1, s * 2.1, 18), Color(0.88, 0.9, 0.98, 0.55), 1.0, true)
		&"sunblessed":
			# Golden sun-dome radiating rays
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.25, s * 1.25, 12), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.1, s * 1.1, 12), Color(0.9, 0.72, 0.3))
			_marker_poly(marker, _ellipse_pts(Vector2(-s * 0.3, -s * 0.3), s * 0.4, s * 0.4, 8), Color(0.98, 0.88, 0.55))
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.2, s * 0.2, 6), fc)
			if level >= 3:
				for i in 8:
					var a := TAU * float(i) / 8.0
					_marker_line(marker, PackedVector2Array([
						Vector2(cos(a), sin(a)) * s * 1.3, Vector2(cos(a), sin(a)) * s * (1.7 + 0.15 * float(level))
					]), _MARKER_GOLD, 1.1)
			if level >= 5:
				_marker_line(marker, _ellipse_pts(Vector2.ZERO, s * 2.2, s * 2.2, 18), _MARKER_GOLD, 0.9, true)
		&"thunderswarm":
			# Storm spire with a lightning sigil
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.2, s * 1.2, 12), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.05, s * 1.05, 12), Color(0.3, 0.34, 0.42))
			_marker_line(marker, PackedVector2Array([
				Vector2(-s * 0.35, -s * 0.75), Vector2(s * 0.1, -s * 0.1),
				Vector2(-s * 0.15, s * 0.05), Vector2(s * 0.35, s * 0.8)
			]), Color(0.95, 0.9, 0.5), maxf(1.2, s * 0.22))
			if level >= 4:
				for i in 6:
					var a := TAU * float(i) / 6.0 + 0.3
					_marker_line(marker, PackedVector2Array([
						Vector2(cos(a), sin(a)) * s * 1.3, Vector2(cos(a), sin(a)) * s * 1.75
					]), Color(0.6, 0.66, 0.78), 1.0)
			if level >= 5:
				_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.25, s * 0.25, 6), fc)
		&"cinderguard":
			# Bastion keep: thick double walls, ember watch-fires
			if level >= 5:
				_town_sq(marker, Vector2.ZERO, s * 1.6, 0.0, _MARKER_STONE)
				_town_sq(marker, Vector2.ZERO, s * 1.45, 0.0, ground)
			_town_sq(marker, Vector2.ZERO, s * 1.25, 0.0, _MARKER_OUTLINE)
			_town_sq(marker, Vector2.ZERO, s * 1.1, 0.0, _MARKER_STONE)
			_town_sq(marker, Vector2.ZERO, s * 0.6, 0.0, _MARKER_STONE_LIGHT)
			_town_sq(marker, Vector2.ZERO, s * 0.28, 0.0, fc)
			for i in mini(2 + level, 5):
				var a := TAU * float(i) / float(mini(2 + level, 5)) + 0.5
				_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 0.88, 0.5, 0.5, 6), Color(0.95, 0.55, 0.2))
		&"forsaken":
			# Shadow sanctum ringed by hooded congregants
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.2, s * 1.2, 12), Color(0.14, 0.12, 0.16))
			_marker_line(marker, PackedVector2Array([Vector2(-s * 0.55, 0), Vector2(s * 0.55, 0)]), Color(0.6, 0.58, 0.66, 0.7), 0.8)
			_marker_line(marker, PackedVector2Array([Vector2(0, -s * 0.55), Vector2(0, s * 0.55)]), Color(0.6, 0.58, 0.66, 0.7), 0.8)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.22, s * 0.22, 6), fc)
			for i in mini(3 + level, 7):
				var a := TAU * float(i) / float(mini(3 + level, 7)) + 0.4
				_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.55, 0.7, 0.7, 6), Color(0.2, 0.18, 0.22))
			if level >= 5:
				for i in 4:
					var a := PI * 0.25 + TAU * float(i) / 4.0
					_marker_line(marker, PackedVector2Array([
						Vector2(cos(a), sin(a)) * s * 1.3, Vector2(cos(a), sin(a)) * s * 2.0
					]), Color(0.16, 0.14, 0.2), 1.4)
		&"ivoryscar":
			# Stepped ivory pyramid seen from above
			_town_sq(marker, Vector2.ZERO, s * 1.35, 0.0, _MARKER_OUTLINE)
			_town_sq(marker, Vector2.ZERO, s * 1.2, 0.0, Color(0.72, 0.68, 0.56))
			_town_sq(marker, Vector2.ZERO, s * 0.85, 0.0, Color(0.82, 0.78, 0.66))
			_town_sq(marker, Vector2.ZERO, s * 0.5, 0.0, Color(0.9, 0.87, 0.76))
			_marker_line(marker, PackedVector2Array([Vector2(-s * 1.2, -s * 1.2), Vector2(s * 1.2, s * 1.2)]),
				Color(0.6, 0.56, 0.46), 0.7)
			_marker_line(marker, PackedVector2Array([Vector2(s * 1.2, -s * 1.2), Vector2(-s * 1.2, s * 1.2)]),
				Color(0.6, 0.56, 0.46), 0.7)
			_town_sq(marker, Vector2.ZERO, s * 0.2, 0.0, fc if level < 5 else _MARKER_GOLD)
		&"shardhorde":
			# Crystal throne: shards radiating from a resonance glow
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.5, s * 1.5, 12), Color(0.62, 0.45, 0.75, 0.18))
			var n := 3 + int(float(level) * 0.8)
			for i in n:
				var a := TAU * float(i) / float(n) + 0.35
				var d := Vector2(cos(a), sin(a))
				var p2 := Vector2(-d.y, d.x)
				var tip := d * s * (1.15 + 0.35 * float(i % 2))
				var waist := d * s * 0.45
				_marker_poly(marker, PackedVector2Array([
					Vector2.ZERO, waist + p2 * s * 0.3, tip, waist - p2 * s * 0.3
				]), fc if i % 3 == 0 else Color(0.58, 0.42, 0.7))
				_marker_line(marker, PackedVector2Array([Vector2.ZERO, tip]), Color(0.78, 0.62, 0.88), 0.8)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.28, s * 0.28, 6), Color(0.85, 0.72, 0.95))
		_:
			# Neutral keep
			_town_sq(marker, Vector2.ZERO, s * 1.15, 0.0, _MARKER_OUTLINE)
			_town_sq(marker, Vector2.ZERO, s, 0.0, _MARKER_STONE)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.5, s * 0.5, 8), _MARKER_STONE_LIGHT)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.2, s * 0.2, 6), fc)

func _draw_settlement_art(marker: Node2D, culture: StringName, fc: Color) -> void:
	# Hamlet: a tiny top-down cluster — dirt patch, path, three buildings
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(culture) * 977 + 5
	var st := _town_style(culture)
	var ground: Color = st["ground"]
	var roof: Color = st["roof"]
	var hut: String = st["hut"]
	_marker_poly(marker, _town_patch(rng, 10.0, 8.2), ground.darkened(0.25))
	_marker_poly(marker, _town_patch(rng, 9.2, 7.6), ground)
	_marker_line(marker, PackedVector2Array([Vector2(0, 7.6), Vector2(0, 1.0)]), ground.darkened(0.18), 1.8)
	for i in 3:
		var a := TAU * float(i) / 3.0 - PI * 0.5 + 0.55
		var p := Vector2(cos(a) * 4.8, sin(a) * 4.2)
		_town_building(marker, rng, hut, ground, p, 2.4 + rng.randf() * 0.5, fc if i == 0 else roof)
	_town_banner(marker, Vector2(3.6, 7.0), fc)

func _draw_city_art(marker: Node2D, culture: StringName, fc: Color, is_capital: bool, level := 3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(culture) * 977 + level * 31 + (7 if is_capital else 0)
	var st := _town_style(culture)
	var ground: Color = st["ground"]
	var roof: Color = st["roof"]
	var hut: String = st["hut"]
	var R := _town_radius(level)
	# Cleared ground footprint with a darker rim
	_marker_poly(marker, _town_patch(rng, R * 1.34, R * 1.13), ground.darkened(0.25))
	_marker_poly(marker, _town_patch(rng, R * 1.26, R * 1.06), ground)
	# South road into the central plaza
	var plaza_r := 3.2 + float(level) * 1.0
	_marker_line(marker, PackedVector2Array([Vector2(0, R * 1.1), Vector2(0, plaza_r * 0.4)]),
		ground.darkened(0.18), 2.4)
	_marker_poly(marker, _ellipse_pts(Vector2.ZERO, plaza_r + 1.6, plaza_r + 1.3, 12), ground.lightened(0.1))
	# Market clutter on the plaza edge from level 2 (crates and barrels)
	if level >= 2:
		for i in 2 + level / 2:
			var ca := rng.randf() * TAU
			var cp := Vector2(cos(ca), sin(ca)) * (plaza_r * 0.75)
			if i % 2 == 0:
				_town_sq(marker, cp, 1.1, ca, Color(0.5, 0.38, 0.24))
			else:
				_marker_poly(marker, _ellipse_pts(cp, 1.2, 1.2, 6), Color(0.44, 0.32, 0.2))
	# Buildings around the plaza (a second outer ring from level 4); the
	# south corridor stays clear so the road reads
	var count: int = [3, 5, 7, 9, 11][clampi(level, 1, 5) - 1]
	var inner_n := mini(count, 6)
	var ring1 := R * 0.58
	for i in inner_n:
		var a := TAU * float(i) / float(inner_n) + 0.35 + rng.randf() * 0.25
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.38:
			continue
		var p := Vector2(cos(a) * ring1, sin(a) * ring1 * 0.92)
		_town_building(marker, rng, hut, ground, p, 2.6 + rng.randf() * 0.7, fc if i % 3 == 0 else roof)
	if count > 6:
		var outer_n := count - 6
		var ring2 := R * 0.85
		for i in outer_n:
			var a := TAU * float(i) / float(outer_n) + 1.1 + rng.randf() * 0.3
			if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.3:
				continue
			var p := Vector2(cos(a) * ring2, sin(a) * ring2 * 0.92)
			_town_building(marker, rng, hut, ground, p, 2.1 + rng.randf() * 0.6, fc if i % 3 == 1 else roof)
	# Wall from level 3
	if level >= 3:
		_town_wall(marker, String(st["wall"]), R, level)
	# Central landmark (grows with level)
	_town_landmark(marker, culture, fc, level, ground)
	# Faction banners flanking the gate
	_town_banner(marker, Vector2(-4.4, R * 1.04), fc)
	if level >= 3:
		_town_banner(marker, Vector2(4.8, R * 1.04), fc)

func _create_army_marker(army: ArmyState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(army.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color.WHITE

	# Ground shadow
	_marker_poly(marker, _ellipse_pts(Vector2(0, 10.5), 11.0, 3.5), Color(0, 0, 0, 0.3))

	# Faction-flavored shield (culture decides shape, faction color the field);
	# drawn slightly larger to match the bigger terrain tiles
	var shield_root := Node2D.new()
	shield_root.scale = Vector2(1.18, 1.18)
	marker.add_child(shield_root)
	_draw_army_shield_art(shield_root, _marker_culture(army.faction_id), faction_color)

	# Relation ring (front arc) at the shield base — same read as city markers
	var rel_ring := _marker_line(marker,
		_ellipse_arc_pts(Vector2(0, 10.5), 11.0, 3.4, -0.35, PI + 0.35, 14),
		_relation_ring_color(army.faction_id), 2.0)
	rel_ring.name = "RelationRing"
	rel_ring.z_index = 1

	# Unit count roundel
	var roundel_pos := Vector2(0, -3.5)
	var roundel := _marker_poly(marker, _make_circle(6.2, 14), Color(0.1, 0.08, 0.06, 0.92))
	roundel.position = roundel_pos
	var rim := _marker_line(marker, _make_circle(6.2, 14), _MARKER_GOLD, 1.2, true)
	rim.position = roundel_pos

	var label := Label.new()
	label.text = str(army.units.size())
	label.position = Vector2(-8, -12)
	label.custom_minimum_size = Vector2(16, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(label)

	# Selection ring (hidden by default, shown when selected)
	var sel_ring := Polygon2D.new()
	sel_ring.name = "SelectionRing"
	sel_ring.polygon = _make_circle(16.0, 16)
	sel_ring.color = Color(1, 0.85, 0.2, 0.35)
	sel_ring.antialiased = true
	sel_ring.visible = false
	marker.add_child(sel_ring)

	marker.set_meta("base_scale", 1.0)
	marker.scale = Vector2.ONE * _marker_zoom_boost
	army_markers_node.add_child(marker)
	_army_markers[army.army_id] = marker

# ── City markers ─────────────────────────────────────────────

func _create_city_markers() -> void:
	for child in city_markers_node.get_children():
		child.queue_free()
	_city_markers.clear()

	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		_create_city_marker(city)

const LANDMARK_COLORS := {
	&"dragonbone_fields": Color(0.85, 0.80, 0.65),
	&"everfrost_core": Color(0.55, 0.80, 0.95),
	&"sungold_vein": Color(0.95, 0.78, 0.25),
	&"worldroot_nexus": Color(0.35, 0.75, 0.35),
	&"voidglass_rift": Color(0.60, 0.35, 0.85),
	&"titan_forge_ruin": Color(0.80, 0.45, 0.25),
	&"leyline_well": Color(0.40, 0.85, 0.85),
}

## Generated resource-tier art (bounty/deposit/landmark) lives under
## assets/sprites/resources/; null when a given id's PNG hasn't been
## generated yet, so callers fall back to the programmatic markers.
func _load_resource_art(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

func _create_bounty_markers() -> void:
	if bounty_markers_node == null:
		bounty_markers_node = Node2D.new()
		bounty_markers_node.name = "BountyMarkers"
		bounty_markers_node.z_index = 1 # above terrain, below cities (2)
		$EntityLayer.add_child(bounty_markers_node)
	for child in bounty_markers_node.get_children():
		child.queue_free()
	_bounty_markers.clear()
	var map = GameManager.state.hex_map
	if map == null:
		return
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.bounty_id == &"":
			continue
		var marker := Node2D.new()
		# Top-right corner of the hex tile
		marker.position = _hex_to_pixel(coord) + Vector2(HEX_RADIUS * 0.45, -HEX_RADIUS * 0.55)
		var b_tex := _load_resource_art("res://assets/sprites/resources/bounty_%s.png" % tile.bounty_id)
		if b_tex:
			var spr := Sprite2D.new()
			spr.texture = b_tex
			spr.scale = Vector2(0.30, 0.30)  # 64px -> ~19px on map
			marker.add_child(spr)
		else:
			# fallback: existing chip polygons (keep verbatim)
			var bg := Polygon2D.new()
			bg.polygon = _make_circle(7.0, 10)
			bg.color = Color(0.08, 0.07, 0.05, 0.9)
			marker.add_child(bg)
			var rim := Polygon2D.new()
			rim.polygon = _make_circle(7.0, 10)
			rim.color = Color(0.78, 0.62, 0.32, 0.9)
			rim.scale = Vector2(1.15, 1.15)
			rim.z_index = -1
			marker.add_child(rim)
			var glyph := Label.new()
			glyph.text = String(BountySystem.BOUNTY_TYPES[tile.bounty_id].name).left(1)
			glyph.add_theme_font_size_override("font_size", 9)
			glyph.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
			glyph.position = Vector2(-4, -8)
			marker.add_child(glyph)
		marker.visible = GameManager.explored_tiles.has(coord)
		bounty_markers_node.add_child(marker)
		_bounty_markers[coord] = marker

	# Special deposits — distinct diamond marker, tile-centered (specials
	# dominate their tile, unlike the bounty's corner-flag treatment).
	var diamond_pts := PackedVector2Array([Vector2(0, -9), Vector2(9, 0), Vector2(0, 9), Vector2(-9, 0)])
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.special_id == &"":
			continue
		var marker := Node2D.new()
		marker.position = _hex_to_pixel(coord)
		var s_tex := _load_resource_art("res://assets/sprites/resources/deposit_%s.png" % tile.special_id)
		if s_tex:
			var spr := Sprite2D.new()
			spr.texture = s_tex
			spr.scale = Vector2(0.36, 0.36)  # 128px -> ~46px on map
			marker.add_child(spr)
		else:
			# fallback: existing purple-diamond chip (keep verbatim)
			var bg := Polygon2D.new()
			bg.polygon = diamond_pts
			bg.color = Color(0.08, 0.07, 0.05, 0.9)
			marker.add_child(bg)
			var rim := Polygon2D.new()
			rim.polygon = diamond_pts
			rim.color = Color(0.65, 0.45, 0.85, 0.95)
			rim.scale = Vector2(1.15, 1.15)
			rim.z_index = -1
			marker.add_child(rim)
			var glyph := Label.new()
			glyph.text = String(SpecialResourceSystem.SPECIAL_TYPES[tile.special_id].name).left(2)
			glyph.add_theme_font_size_override("font_size", 9)
			glyph.add_theme_color_override("font_color", Color(0.95, 0.88, 0.98))
			glyph.custom_minimum_size = Vector2(18, 0)
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph.position = Vector2(-9, -6)
			marker.add_child(glyph)
		marker.visible = GameManager.explored_tiles.has(coord)
		bounty_markers_node.add_child(marker)
		_bounty_markers[coord] = marker

	# Landmarks — tile-dominating generated art (or a fallback 6-point star +
	# glyph), tile-centered (Landmarks dominate a region and are the rarest
	# resource, so they get the boldest marker).
	for coord in map.tiles:
		var tile = map.tiles[coord]
		if tile.landmark_id == &"":
			continue
		var ldef: Dictionary = LandmarkSystem.LANDMARK_TYPES[tile.landmark_id]
		var lcolor: Color = LANDMARK_COLORS.get(tile.landmark_id, Color.WHITE)
		var marker := Node2D.new()
		marker.position = _hex_to_pixel(coord)
		var l_tex := _load_resource_art("res://assets/sprites/resources/landmark_%s.png" % tile.landmark_id)
		if l_tex:
			var spr := Sprite2D.new()
			spr.texture = l_tex
			spr.scale = Vector2(0.17, 0.17)  # 512px -> ~87px, slightly over the hex so landmarks dominate their tile
			marker.add_child(spr)
		else:
			# fallback: existing star + glyph chip (keep verbatim)
			var bg := Polygon2D.new()
			bg.polygon = _make_circle(13.0, 14)
			bg.color = Color(0.06, 0.05, 0.05, 0.9)
			marker.add_child(bg)
			# Outer tips land on the horizontal axis (angle 0) so the widest part
			# of the star sits behind the glyph row instead of a concave notch.
			var star_pts := PackedVector2Array()
			for i in 12:
				var angle := TAU * i / 12.0
				var r := 12.0 if i % 2 == 0 else 6.0
				star_pts.append(Vector2(cos(angle) * r, sin(angle) * r))
			var star := Polygon2D.new()
			star.polygon = star_pts
			star.color = lcolor
			marker.add_child(star)
			var glyph := Label.new()
			glyph.text = String(ldef.name).left(3)
			glyph.add_theme_font_size_override("font_size", 8)
			glyph.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06))
			glyph.custom_minimum_size = Vector2(24, 0)
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph.position = Vector2(-12, -5)
			marker.add_child(glyph)
		marker.visible = GameManager.explored_tiles.has(coord)
		bounty_markers_node.add_child(marker)
		_bounty_markers[coord] = marker

func _refresh_bounty_marker_visibility() -> void:
	for coord in _bounty_markers:
		var marker: Node2D = _bounty_markers[coord]
		marker.visible = GameManager.explored_tiles.has(coord)

func _create_city_marker(city: CityState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(city.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(city.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color.WHITE

	var culture := _marker_culture(city.faction_id)
	var R := _town_radius(city.level)
	if city.is_settlement:
		# Soft drop shadow + top-down culture-flavored hamlet
		_marker_poly(marker, _ellipse_pts(Vector2(1.2, 1.6), 10.6, 8.7), Color(0, 0, 0, 0.25))
		_draw_settlement_art(marker, culture, faction_color)
	else:
		# Soft drop shadow + top-down town that grows with level; universal
		# crown badge floats above capitals
		_marker_poly(marker, _ellipse_pts(Vector2(1.5, 2.0), R * 1.34, R * 1.12), Color(0, 0, 0, 0.25))
		_draw_city_art(marker, culture, faction_color, city.is_capital, city.level)
		if city.is_capital:
			# Crown floats above the level badge at the ring's top
			var crown := _marker_poly(marker, PackedVector2Array([
				Vector2(-4.5, 0), Vector2(-4.5, -3.5), Vector2(-2.2, -1.4),
				Vector2(0, -4.5), Vector2(2.2, -1.4), Vector2(4.5, -3.5), Vector2(4.5, 0)
			]), Color(0.95, 0.85, 0.3))
			crown.position = Vector2(0, -(_CITY_RING_RADIUS * 0.866 + 10.5))
			crown.z_index = 2

	# City level glow — scales with the footprint, larger for capitals
	if city.faction_id == GameManager.state.player_faction_id:
		var glow_base_radius := R * 1.3
		if city.is_capital:
			glow_base_radius += 5.0
		elif city.is_settlement:
			glow_base_radius = 12.0
		var glow_alpha := clampf(0.15 + city.level * 0.04, 0.15, 0.45)
		# Outer soft glow
		var glow_outer := Polygon2D.new()
		glow_outer.name = "CityGlowOuter"
		glow_outer.polygon = _make_circle(glow_base_radius + 4.0, 16)
		glow_outer.color = Color(faction_color.r, faction_color.g, faction_color.b, glow_alpha * 0.5)
		glow_outer.z_index = -1
		marker.add_child(glow_outer)
		# Inner bright glow
		var glow_inner := Polygon2D.new()
		glow_inner.name = "CityGlowInner"
		glow_inner.polygon = _make_circle(glow_base_radius, 16)
		glow_inner.color = Color(faction_color.r, faction_color.g, faction_color.b, glow_alpha)
		glow_inner.z_index = -1
		marker.add_child(glow_inner)
		# Gentle pulse animation
		var glow_tween := marker.create_tween().set_loops()
		glow_tween.tween_property(glow_outer, "modulate:a", 0.5, 2.0).set_trans(Tween.TRANS_SINE)
		glow_tween.tween_property(glow_outer, "modulate:a", 1.0, 2.0).set_trans(Tween.TRANS_SINE)

	# Level badge — a roundel sitting ON TOP of the ownership ring (12 o'clock)
	var ring_col := _relation_ring_color(city.faction_id)
	var badge_r := 5.2 if city.is_settlement else 6.4
	var badge_pos := Vector2(0, -_CITY_RING_RADIUS * 0.866)
	var badge := _marker_poly(marker, _make_circle(badge_r, 12), Color(0.1, 0.08, 0.06, 0.95))
	badge.position = badge_pos
	badge.z_index = 2
	var badge_rim := _marker_line(marker, _make_circle(badge_r, 12), ring_col, 1.4, true)
	badge_rim.position = badge_pos
	badge_rim.z_index = 2
	var label := Label.new()
	label.text = str(city.level)
	label.position = badge_pos + Vector2(-8, -9)
	label.custom_minimum_size = Vector2(16, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 2
	label.add_theme_font_size_override("font_size", 9 if city.is_settlement else 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(label)

	# Siege indicator (red pulsing ring, hidden by default)
	var siege_ring := Polygon2D.new()
	siege_ring.name = "SiegeRing"
	siege_ring.polygon = _make_circle(14.0 if city.is_settlement else R * 1.5, 12)
	siege_ring.color = Color(0.9, 0.15, 0.1, 0.4)
	siege_ring.visible = city.is_under_siege
	marker.add_child(siege_ring)

	if city.is_under_siege:
		_animate_siege_ring(siege_ring)
		_refresh_siege_bar(marker, city)

	# Construction indicator (hammer symbol, visible when building something)
	var is_constructing := not city.build_queue.is_empty()
	if not is_constructing:
		for _bq_key in city.building_recruit_queues:
			if city.building_recruit_queues[_bq_key].size() > 0:
				is_constructing = true
				break
	if not is_constructing:
		is_constructing = not city.recruit_queue.is_empty()

	var hammer := Node2D.new()
	hammer.name = "ConstructionHammer"
	hammer.position = Vector2(9, -11) if city.is_settlement else Vector2(R * 0.95, -R * 0.9)
	hammer.visible = is_constructing

	# Hammer head (rectangle)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-4, -3), Vector2(4, -3), Vector2(4, 1), Vector2(-4, 1)
	])
	head.color = Color(0.75, 0.55, 0.2)
	hammer.add_child(head)

	# Hammer handle (thin rectangle)
	var handle := Polygon2D.new()
	handle.polygon = PackedVector2Array([
		Vector2(-1, 1), Vector2(1, 1), Vector2(1, 7), Vector2(-1, 7)
	])
	handle.color = Color(0.5, 0.35, 0.15)
	hammer.add_child(handle)

	marker.add_child(hammer)

	if is_constructing:
		var htween := marker.create_tween().set_loops()
		htween.tween_property(hammer, "modulate:a", 0.5, 0.8)
		htween.tween_property(hammer, "modulate:a", 1.0, 0.8)

	# City name plaque below the marker — all cities except settlements
	if not city.is_settlement:
		var city_text: String = city.city_name if city.city_name != "" else str(city.city_id)
		var plaque := PanelContainer.new()
		plaque.name = "CityPlaque"
		var plaque_style := StyleBoxFlat.new()
		plaque_style.bg_color = Color(faction_color.r * 0.3, faction_color.g * 0.3, faction_color.b * 0.3, 0.85)
		plaque_style.border_color = Color(faction_color.r, faction_color.g, faction_color.b, 0.6)
		plaque_style.set_border_width_all(1)
		plaque_style.set_corner_radius_all(2)
		plaque_style.set_content_margin_all(0)
		plaque_style.content_margin_left = 3
		plaque_style.content_margin_right = 3
		plaque_style.content_margin_top = 1
		plaque_style.content_margin_bottom = 1
		plaque.add_theme_stylebox_override("panel", plaque_style)
		var name_label := Label.new()
		name_label.text = city_text
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		name_label.add_theme_constant_override("outline_size", 2)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plaque.add_child(name_label)
		# Size to text width + padding, centered under marker
		var char_width := city_text.length() * 5.0 + 10.0
		var plaque_w := maxf(char_width, 24.0)
		plaque.size = Vector2(plaque_w, 14)
		plaque.position = Vector2(-plaque_w * 0.5, _CITY_RING_RADIUS * 0.866 + 3.0)
		marker.add_child(plaque)

	# Ownership ring: hugs the inner side of the tile border (rounded-off hex)
	var outline := Line2D.new()
	outline.name = "CityOutline"
	outline.width = 2.2
	outline.default_color = ring_col
	outline.points = _rounded_hex_pts(_CITY_RING_RADIUS, _CITY_RING_CORNER)
	outline.closed = true
	outline.antialiased = true
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.z_index = 1
	marker.add_child(outline)

	marker.set_meta("base_scale", 1.0)
	marker.scale = Vector2.ONE * _marker_zoom_boost
	city_markers_node.add_child(marker)
	_city_markers[city.city_id] = marker

# ── Building tile markers ────────────────────────────────────

const BUILDING_CATEGORY_COLORS := {
	&"economic": Color(0.85, 0.75, 0.2, 0.7),   # gold
	&"military": Color(0.8, 0.2, 0.15, 0.7),     # red
	&"defensive": Color(0.25, 0.45, 0.8, 0.7),   # blue
	&"cultural": Color(0.6, 0.25, 0.7, 0.7),     # purple
}

func _create_building_tile_markers() -> void:
	for node in _building_tile_markers:
		if is_instance_valid(node):
			node.queue_free()
	_building_tile_markers.clear()
	if is_instance_valid(_building_paths_node):
		_building_paths_node.queue_free()
	# Squiggly dirt paths render beneath every marker (first child, same z)
	_building_paths_node = Node2D.new()
	_building_paths_node.name = "BuildingPaths"
	city_markers_node.add_child(_building_paths_node)
	city_markers_node.move_child(_building_paths_node, 0)

	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var faction_data: FactionData = DataManager.get_faction(city.faction_id)
		var faction_color: Color = faction_data.color if faction_data else Color.WHITE
		var city_px := _hex_to_pixel(city.hex_pos)

		# Draw markers for completed buildings
		for bid in city.building_tiles:
			var tile_pos: Vector2i = city.building_tiles[bid]
			var building: BuildingData = DataManager.get_building(bid)
			_add_building_path(city_px, _hex_to_pixel(tile_pos), city.faction_id, tile_pos)
			_add_building_tile_marker(tile_pos, building, faction_color, false, city.faction_id)

		# Draw markers for buildings under construction
		for item in city.build_queue:
			if item.has("tile_pos"):
				var building: BuildingData = DataManager.get_building(item.building_id)
				_add_building_path(city_px, _hex_to_pixel(item.tile_pos), city.faction_id, item.tile_pos)
				_add_building_tile_marker(item.tile_pos, building, faction_color, true, city.faction_id)

## Realistically squiggly dirt path from the city footprint to a building pad.
## World-position sine noise keeps it deterministic and organic.
func _add_building_path(from: Vector2, to: Vector2, faction_id: StringName = &"", bhex: Vector2i = Vector2i(-1, -1)) -> void:
	var dirv := to - from
	var lenv := dirv.length()
	if lenv < 1.0:
		return
	var d := dirv / lenv
	var perp := Vector2(-d.y, d.x)
	var a := from + d * 15.0   # leave the town at its edge
	var b := to - d * 8.0      # arrive at the building pad edge
	var seg_len := (b - a).length()
	var n := maxi(int(seg_len / 8.0), 6)
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var base := a.lerp(b, t)
		var wob := sin(base.x * 0.23 + base.y * 0.17) * 2.2 + sin(base.x * 0.07 - base.y * 0.11) * 3.0
		pts.append(base + perp * wob * sin(t * PI))
	var l := Line2D.new()
	l.points = pts
	l.width = 2.6
	l.default_color = Color(0.42, 0.34, 0.24, 0.55)
	l.antialiased = true
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.set_meta("faction_id", faction_id)
	l.set_meta("hex_pos", bhex)
	_building_paths_node.add_child(l)

## Small keyword-derived symbol stamped beside the structure. This is what
## makes each building TYPE visually unique without hand-authoring 248 sprites.
func _building_emblem(marker: Node2D, building: BuildingData, s: float, rng: RandomNumberGenerator) -> void:
	if building == null:
		return
	var key := String(building.id)
	var ep := Vector2(s * 1.5, s * 1.3)  # emblem pad, SE of the structure
	if key.contains("forge") or key.contains("smelt") or key.contains("foundry") or key.contains("kiln") or key.contains("workshop"):
		# Anvil + ember glow
		_marker_poly(marker, PackedVector2Array([
			ep + Vector2(-2.6, 0.4), ep + Vector2(2.8, 0.4), ep + Vector2(1.8, -1.4), ep + Vector2(-1.4, -1.4)
		]), Color(0.2, 0.18, 0.17))
		_marker_poly(marker, _ellipse_pts(ep + Vector2(0, 1.4), 1.6, 0.7, 6), Color(0.95, 0.5, 0.15, 0.8))
	elif key.contains("market") or key.contains("bazaar") or key.contains("trade") or key.contains("exchange") or key.contains("emporium") or key.contains("caravansary"):
		# Striped stall awning
		_marker_poly(marker, PackedVector2Array([
			ep + Vector2(-2.8, -1.8), ep + Vector2(2.8, -1.8), ep + Vector2(2.8, 1.8), ep + Vector2(-2.8, 1.8)
		]), Color(0.85, 0.82, 0.72))
		for k in 2:
			var sx := -1.7 + float(k) * 2.2
			_marker_poly(marker, PackedVector2Array([
				ep + Vector2(sx, -1.8), ep + Vector2(sx + 1.1, -1.8), ep + Vector2(sx + 1.1, 1.8), ep + Vector2(sx, 1.8)
			]), Color(0.75, 0.28, 0.22))
	elif key.contains("temple") or key.contains("shrine") or key.contains("altar") or key.contains("sanctum") or key.contains("cathedral") or key.contains("court"):
		# Gold finial star
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI / 4.0
			_marker_line(marker, PackedVector2Array([ep, ep + Vector2(cos(a), sin(a)) * 2.6]), _MARKER_GOLD, 1.2)
		_marker_poly(marker, _ellipse_pts(ep, 1.1, 1.1, 6), _MARKER_GOLD)
	elif key.contains("farm") or key.contains("orchard") or key.contains("grove") or key.contains("garden") or key.contains("pasture") or key.contains("ranch") or key.contains("harvest") or key.contains("field"):
		# Green sprout row
		for k in 3:
			var sp := ep + Vector2(float(k - 1) * 2.2, rng.randf_range(-0.6, 0.6))
			_marker_poly(marker, _ellipse_pts(sp, 1.0, 1.0, 6), Color(0.35, 0.55, 0.25))
			_marker_line(marker, PackedVector2Array([sp, sp + Vector2(0, 1.6)]), Color(0.3, 0.42, 0.2), 0.8)
	elif key.contains("mine") or key.contains("quarry") or key.contains("pit") or key.contains("vein"):
		# Rock pile
		_marker_poly(marker, _ellipse_pts(ep + Vector2(-1.2, 0.4), 1.6, 1.3, 7), _MARKER_STONE)
		_marker_poly(marker, _ellipse_pts(ep + Vector2(1.3, 0.6), 1.3, 1.0, 7), _MARKER_STONE_LIGHT)
		_marker_poly(marker, _ellipse_pts(ep + Vector2(0.2, -0.9), 1.1, 0.9, 7), _MARKER_STONE)
	elif key.contains("academ") or key.contains("librar") or key.contains("scriptorium") or key.contains("codex") or key.contains("observ") or key.contains("scholar") or key.contains("lodge"):
		# Open book
		_marker_poly(marker, PackedVector2Array([
			ep + Vector2(-2.6, -1.2), ep + Vector2(-0.2, -0.6), ep + Vector2(-0.2, 1.6), ep + Vector2(-2.6, 1.0)
		]), Color(0.9, 0.87, 0.78))
		_marker_poly(marker, PackedVector2Array([
			ep + Vector2(2.6, -1.2), ep + Vector2(0.2, -0.6), ep + Vector2(0.2, 1.6), ep + Vector2(2.6, 1.0)
		]), Color(0.82, 0.79, 0.7))
	elif key.contains("pens") or key.contains("stable") or key.contains("roost") or key.contains("lair") or key.contains("aviary") or key.contains("den") or key.contains("kennel") or key.contains("hatchery"):
		# Paw print
		_marker_poly(marker, _ellipse_pts(ep + Vector2(0, 0.6), 1.3, 1.1, 7), Color(0.25, 0.2, 0.16))
		for k in 3:
			var a := -PI * 0.75 + float(k) * PI * 0.25
			_marker_poly(marker, _ellipse_pts(ep + Vector2(cos(a), sin(a)) * 1.9, 0.55, 0.55, 5), Color(0.25, 0.2, 0.16))
	elif key.contains("well") or key.contains("spring") or key.contains("oasis") or key.contains("cistern") or key.contains("canal"):
		# Water droplet
		_marker_poly(marker, _ellipse_pts(ep + Vector2(0, 0.5), 1.5, 1.5, 8), Color(0.35, 0.55, 0.8))
		_marker_poly(marker, PackedVector2Array([ep + Vector2(-1.1, 0.1), ep + Vector2(0, -2.2), ep + Vector2(1.1, 0.1)]), Color(0.35, 0.55, 0.8))
	elif key.contains("wall") or key.contains("bastion") or key.contains("rampart") or key.contains("fortress") or key.contains("citadel") or key.contains("barricade"):
		# Crenellated wall stub
		_marker_poly(marker, PackedVector2Array([
			ep + Vector2(-2.6, 1.4), ep + Vector2(2.6, 1.4), ep + Vector2(2.6, -0.6), ep + Vector2(-2.6, -0.6)
		]), _MARKER_STONE)
		for k in 3:
			var tx := -1.8 + float(k) * 1.8
			_marker_poly(marker, PackedVector2Array([
				ep + Vector2(tx - 0.5, -0.6), ep + Vector2(tx + 0.5, -0.6), ep + Vector2(tx + 0.5, -1.6), ep + Vector2(tx - 0.5, -1.6)
			]), _MARKER_STONE_LIGHT)
	# (no match: the structure + roof shade variation already carry identity)

## Upgrade tier of a building (1 = base, 2/3 = upgraded versions) — drives the
## visible progression of the tile graphic
func _building_tier(building: BuildingData) -> int:
	var tier := 1
	var cur := building
	while cur and cur.upgrades_from != &"" and tier < 3:
		cur = DataManager.get_building(cur.upgrades_from)
		tier += 1
	return tier

func _add_building_tile_marker(tile_pos: Vector2i, building: BuildingData, faction_color: Color, under_construction: bool, city_faction_id: StringName = &"") -> void:
	var pixel_pos := _hex_to_pixel(tile_pos)
	var marker := Node2D.new()
	marker.position = pixel_pos
	# Slightly larger to match the enlarged terrain tiles + zoom-out boost
	marker.set_meta("base_scale", 1.25)
	marker.scale = Vector2.ONE * 1.25 * _marker_zoom_boost

	# Top-down building in the owning culture's shape language; the roof keeps
	# the category color for at-a-glance reading, the tier grows the compound.
	var cat: StringName = building.category if building else &"economic"
	var cat_color: Color = BUILDING_CATEGORY_COLORS.get(cat, Color(0.5, 0.5, 0.5, 0.7))
	cat_color.a = 1.0
	var culture := _marker_culture(city_faction_id)
	var st := _town_style(culture)
	var ground: Color = st["ground"]
	var hut: String = st["hut"]
	var tier := _building_tier(building)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(building.id if building else &"b") * 53 + tile_pos.x * 7 + tile_pos.y * 13
	var s := 2.7 + float(tier) * 0.55
	# Per-building-TYPE identity: stable hash drives a lightness shift on the
	# category roof, so two different buildings of the same category read as
	# different structures on the map
	var id_hash: int = absi(hash(building.id if building else &"b"))
	cat_color = cat_color.lightened(float(id_hash % 5) * 0.05 - 0.1)

	# Cleared ground pad
	_marker_poly(marker, _town_patch(rng, s * 2.7, s * 2.25), ground.darkened(0.22))
	_marker_poly(marker, _town_patch(rng, s * 2.45, s * 2.05), ground)

	# Main structure per category
	match cat:
		&"defensive":
			# Watchtower from above: stone drum, crenel teeth, category core
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.25, s * 1.25, 10), _MARKER_OUTLINE)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 1.1, s * 1.1, 10), _MARKER_STONE)
			for i in 6:
				var a := TAU * float(i) / 6.0
				_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.05, s * 0.22, s * 0.22, 5), _MARKER_STONE_LIGHT)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.45, s * 0.45, 8), cat_color)
			if tier >= 2:
				# Second smaller tower joined by a wall stub
				var tp := Vector2(s * 1.9, -s * 0.9)
				_marker_line(marker, PackedVector2Array([Vector2.ZERO, tp]), _MARKER_STONE, 1.8)
				_marker_poly(marker, _ellipse_pts(tp, s * 0.6, s * 0.6, 8), _MARKER_STONE)
				_marker_poly(marker, _ellipse_pts(tp, s * 0.25, s * 0.25, 6), cat_color)
		&"military":
			_town_building(marker, rng, hut, ground, Vector2.ZERO, s, cat_color)
			# Crossed spears emblem beside the hall
			var ep := Vector2(-s * 1.7, s * 0.9)
			_marker_line(marker, PackedVector2Array([ep + Vector2(-s * 0.5, s * 0.6), ep + Vector2(s * 0.5, -s * 0.6)]), Color(0.8, 0.76, 0.66), 1.0)
			_marker_line(marker, PackedVector2Array([ep + Vector2(s * 0.5, s * 0.6), ep + Vector2(-s * 0.5, -s * 0.6)]), Color(0.8, 0.76, 0.66), 1.0)
			if tier >= 2:
				# Training yard: pale square with drill dots
				var yp := Vector2(s * 1.8, s * 0.7)
				_town_sq(marker, yp, s * 0.75, 0.0, ground.lightened(0.14))
				for i in 3:
					_marker_poly(marker, _ellipse_pts(yp + Vector2(float(i - 1) * s * 0.42, 0), s * 0.12, s * 0.12, 5), cat_color)
		&"cultural":
			_town_building(marker, rng, hut, ground, Vector2.ZERO, s, cat_color)
			_marker_poly(marker, _ellipse_pts(Vector2.ZERO, s * 0.22, s * 0.22, 6), _MARKER_GOLD)
			if tier >= 2:
				# Processional dots leading to the shrine
				for i in 4:
					var a := TAU * float(i) / 4.0 + 0.4
					_marker_poly(marker, _ellipse_pts(Vector2(cos(a), sin(a)) * s * 1.8, s * 0.16, s * 0.16, 5), _MARKER_GOLD)
		_:
			# Economic: hall + field strips
			_town_building(marker, rng, hut, ground, Vector2.ZERO, s, cat_color)
			var fp := Vector2(s * 1.6, s * 1.0).rotated(rng.randf_range(-0.4, 0.4))
			for i in 3:
				var off := fp + Vector2(float(i) * s * 0.34 - s * 0.34, float(i) * s * 0.1)
				_marker_line(marker, PackedVector2Array([off + Vector2(-s * 0.55, s * 0.3), off + Vector2(s * 0.55, -s * 0.3)]),
					Color(0.62, 0.56, 0.32, 0.9), 1.1)
			if tier >= 2:
				# Storage annex
				_town_building(marker, rng, hut, ground, Vector2(-s * 1.8, -s * 0.8), s * 0.55, cat_color.darkened(0.15))

	# Tier 3: boundary fence around the compound (gap toward the path, south)
	if tier >= 3:
		var fence_n := 10
		for i in fence_n:
			var a := lerpf(PI * 0.5 + 0.5, PI * 0.5 - 0.5 + TAU, float(i) / float(fence_n - 1))
			_marker_poly(marker, _ellipse_pts(Vector2(cos(a) * s * 2.5, sin(a) * s * 2.1), 0.55, 0.55, 5),
				Color(0.36, 0.29, 0.21))

	# Trade-sign emblem: a small symbol derived from the building's NAME so
	# every building type is recognizable at a glance (forge anvil, market
	# awning, shrine finial, farm sprouts, mine rocks, book, paw, droplet...)
	_building_emblem(marker, building, s, rng)

	# Faction pennant (ownership at a glance)
	_marker_line(marker, PackedVector2Array([Vector2(s * 1.6, -s * 1.2), Vector2(s * 1.6, -s * 1.2 - 6.0)]),
		Color(0.4, 0.3, 0.18), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(s * 1.6, -s * 1.2 - 6.0), Vector2(s * 1.6 + 3.2, -s * 1.2 - 5.0), Vector2(s * 1.6, -s * 1.2 - 4.0)
	]), faction_color)

	if under_construction:
		# In progress: ghosted + scaffold cross-beams
		marker.modulate = Color(1, 1, 1, 0.45)
		_marker_line(marker, PackedVector2Array([Vector2(-s * 1.6, s * 1.3), Vector2(s * 1.6, -s * 1.3)]),
			Color(0.75, 0.62, 0.35), 1.2)
		_marker_line(marker, PackedVector2Array([Vector2(s * 1.6, s * 1.3), Vector2(-s * 1.6, -s * 1.3)]),
			Color(0.75, 0.62, 0.35), 1.2)

	marker.set_meta("hex_pos", tile_pos)
	marker.set_meta("faction_id", city_faction_id)
	city_markers_node.add_child(marker)
	_building_tile_markers.append(marker)

# ── Elderbeast markers ────────────────────────────────────────

func _create_elderbeast_markers() -> void:
	# Only rebuild if beast set changed; otherwise just update positions
	var need_rebuild := false
	if _elderbeast_markers.size() != GameManager.state.elderbeasts.size():
		need_rebuild = true
	else:
		for beast_id in GameManager.state.elderbeasts:
			if not _elderbeast_markers.has(beast_id):
				need_rebuild = true
				break
	if not need_rebuild:
		# Fast path: just update positions
		for beast_id in _elderbeast_markers:
			var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
			if beast:
				_elderbeast_markers[beast_id].position = _hex_to_pixel(beast.hex_pos)
		return

	for child in elderbeast_markers_node.get_children():
		child.queue_free()
	_elderbeast_markers.clear()

	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		_create_elderbeast_marker(beast)

func _create_elderbeast_marker(beast: ElderbeastState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(beast.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(beast.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color(0.7, 0.3, 0.6)

	# Large diamond shape (bigger than cities)
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(14, 0), Vector2(0, 18), Vector2(-14, 0)
	])
	diamond.color = faction_color.darkened(0.15)
	marker.add_child(diamond)

	# Inner diamond
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([
		Vector2(0, -13), Vector2(10, 0), Vector2(0, 13), Vector2(-10, 0)
	])
	inner.color = faction_color
	marker.add_child(inner)

	# 4 crystal spike triangles radiating from diamond corners
	var spike_top := Polygon2D.new()
	spike_top.polygon = PackedVector2Array([
		Vector2(-3, -18), Vector2(0, -26), Vector2(3, -18)
	])
	spike_top.color = faction_color.lightened(0.2)
	marker.add_child(spike_top)
	var spike_right := Polygon2D.new()
	spike_right.polygon = PackedVector2Array([
		Vector2(14, -3), Vector2(22, 0), Vector2(14, 3)
	])
	spike_right.color = faction_color.lightened(0.2)
	marker.add_child(spike_right)
	var spike_bottom := Polygon2D.new()
	spike_bottom.polygon = PackedVector2Array([
		Vector2(-3, 18), Vector2(0, 26), Vector2(3, 18)
	])
	spike_bottom.color = faction_color.lightened(0.2)
	marker.add_child(spike_bottom)
	var spike_left := Polygon2D.new()
	spike_left.polygon = PackedVector2Array([
		Vector2(-14, -3), Vector2(-22, 0), Vector2(-14, 3)
	])
	spike_left.color = faction_color.lightened(0.2)
	marker.add_child(spike_left)

	# Inner rune glyph (small hexagon) at center
	var rune := Polygon2D.new()
	rune.polygon = _make_circle(4.0, 6)
	rune.color = Color(faction_color.r, faction_color.g, faction_color.b, 0.5)
	marker.add_child(rune)

	# Small bone/claw detail marks between inner and outer diamond
	var claw_marks: Array[Line2D] = []
	var claw_positions := [
		[Vector2(4, -15), Vector2(6, -11)],   # top-right gap
		[Vector2(-4, -15), Vector2(-6, -11)],  # top-left gap
		[Vector2(4, 15), Vector2(6, 11)],      # bottom-right gap
		[Vector2(-4, 15), Vector2(-6, 11)],    # bottom-left gap
	]
	for claw_pair in claw_positions:
		var claw := Line2D.new()
		claw.points = PackedVector2Array([claw_pair[0], claw_pair[1]])
		claw.width = 1.0
		claw.default_color = Color(0.9, 0.85, 0.7, 0.6)
		marker.add_child(claw)
		claw_marks.append(claw)

	# Crystal glow ring (pulsing)
	var glow := Polygon2D.new()
	glow.name = "GlowRing"
	glow.polygon = PackedVector2Array([
		Vector2(0, -22), Vector2(17, 0), Vector2(0, 22), Vector2(-17, 0)
	])
	glow.color = Color(faction_color.r, faction_color.g, faction_color.b, 0.25)
	marker.add_child(glow)
	var tween := marker.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.3, 0.9)
	tween.tween_property(glow, "modulate:a", 1.0, 0.9)

	# Second glow ring with offset pulse timing for layered shimmer
	var glow2 := Polygon2D.new()
	glow2.name = "GlowRing2"
	glow2.polygon = PackedVector2Array([
		Vector2(0, -25), Vector2(20, 0), Vector2(0, 25), Vector2(-20, 0)
	])
	glow2.color = Color(faction_color.r, faction_color.g, faction_color.b, 0.15)
	marker.add_child(glow2)
	var tween2 := marker.create_tween().set_loops()
	tween2.tween_property(glow2, "modulate:a", 1.0, 0.6)
	tween2.tween_property(glow2, "modulate:a", 0.3, 1.2)

	# Level label
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.text = str(beast.level)
	level_label.position = Vector2(-4, -10)
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color.WHITE)
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(level_label)

	# HP bar below
	var hp_ratio := float(beast.hp) / float(beast.max_hp)
	var hp_bg := Polygon2D.new()
	hp_bg.polygon = PackedVector2Array([
		Vector2(-12, 20), Vector2(12, 20), Vector2(12, 24), Vector2(-12, 24)
	])
	hp_bg.color = Color(0.15, 0.08, 0.08, 0.8)
	marker.add_child(hp_bg)

	var hp_fill := Polygon2D.new()
	hp_fill.name = "HPFill"
	var fill_width := 24.0 * hp_ratio
	hp_fill.polygon = PackedVector2Array([
		Vector2(-12, 20), Vector2(-12 + fill_width, 20),
		Vector2(-12 + fill_width, 24), Vector2(-12, 24)
	])
	hp_fill.color = Color(0.2, 0.7, 0.25) if hp_ratio > 0.5 else (Color(0.85, 0.65, 0.15) if hp_ratio > 0.25 else Color(0.8, 0.2, 0.15))
	marker.add_child(hp_fill)

	elderbeast_markers_node.add_child(marker)
	_elderbeast_markers[beast.beast_id] = marker

func _on_elderbeast_moved(beast_id: StringName, _from_hex: Vector2i, to_hex: Vector2i) -> void:
	var marker: Node2D = _elderbeast_markers.get(beast_id)
	if marker:
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
		var is_player := beast and beast.faction_id == GameManager.state.player_faction_id
		if is_player or _is_tile_visible(to_hex):
			var target_pos := _hex_to_pixel(to_hex)
			var tween := create_tween()
			tween.tween_property(marker, "position", target_pos, 0.3)
		else:
			marker.position = _hex_to_pixel(to_hex)
	_fog_dirty = true

func _animate_siege_ring(ring: Polygon2D) -> void:
	var tween := ring.create_tween().set_loops()
	tween.tween_property(ring, "modulate:a", 0.3, 0.6)
	tween.tween_property(ring, "modulate:a", 1.0, 0.6)

## Rebuild city markers only when something has changed (_city_markers_dirty).
## Multiple callers in the same frame will only trigger one actual rebuild.
func _refresh_city_markers() -> void:
	if not _city_markers_dirty:
		return
	_city_markers_dirty = false
	_invalidate_city_action_cache()
	_create_city_markers()
	_create_building_tile_markers()
	_update_city_glow_states()
	_fog_dirty = true

func _update_city_glow_states() -> void:
	for city_id in _city_markers:
		var city: CityState = GameManager.state.cities.get(city_id)
		if city == null or city.faction_id != GameManager.state.player_faction_id:
			continue
		var marker: Node2D = _city_markers[city_id]
		var build_glow = marker.get_node_or_null("BuildGlow")
		var settle_glow = marker.get_node_or_null("SettleGlow")
		var has_building_action := _city_has_available_action(city)
		var has_settle_action := city.is_capital and city.can_found_settlement

		# Glow radius must clear the town footprint or it hides beneath it
		var glow_r := 14.0 if city.is_settlement else _town_radius(city.level) * 1.5

		# Building/upgrade available glow (green)
		if has_building_action and build_glow == null:
			_add_build_glow(marker, glow_r)
		elif not has_building_action and build_glow:
			build_glow.queue_free()

		# Settlement founding glow (gold)
		if has_settle_action and settle_glow == null:
			_add_settle_glow(marker, glow_r + 2.0)
		elif not has_settle_action and settle_glow:
			settle_glow.queue_free()

		# Update construction hammer
		var hammer_node := marker.get_node_or_null("ConstructionHammer")
		if hammer_node:
			var constructing := not city.build_queue.is_empty()
			if not constructing:
				for _bq_key in city.building_recruit_queues:
					if city.building_recruit_queues[_bq_key].size() > 0:
						constructing = true
						break
			if not constructing:
				constructing = not city.recruit_queue.is_empty()
			hammer_node.visible = constructing

var _city_action_cache: Dictionary = {} # city_id -> bool; cleared on building/turn events

func _city_has_available_action(city: CityState) -> bool:
	if not city.build_queue.is_empty():
		return false
	if _city_action_cache.has(city.city_id):
		return _city_action_cache[city.city_id]
	var available := GameManager.city_system.get_available_buildings(city)
	var result := available.size() > 0
	_city_action_cache[city.city_id] = result
	return result

func _invalidate_city_action_cache() -> void:
	_city_action_cache.clear()

func _add_build_glow(marker: Node2D, radius := 20.0) -> void:
	var glow := Polygon2D.new()
	glow.name = "BuildGlow"
	glow.polygon = _make_circle(radius, 12)
	glow.color = Color(0.2, 0.8, 0.3, 0.25)
	glow.z_index = -1
	marker.add_child(glow)
	var tween := marker.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.4, 1.0)
	tween.tween_property(glow, "modulate:a", 1.0, 1.0)

func _add_settle_glow(marker: Node2D, radius := 22.0) -> void:
	var glow := Polygon2D.new()
	glow.name = "SettleGlow"
	glow.polygon = _make_circle(radius, 12)
	glow.color = Color(0.95, 0.85, 0.2, 0.3)
	glow.z_index = -1
	marker.add_child(glow)
	var tween := marker.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.3, 1.5)
	tween.tween_property(glow, "modulate:a", 1.0, 1.5)

# ── City management panel ────────────────────────────────────

func _open_city_panel(city_id: StringName) -> void:
	_selected_city_id = city_id
	_city_panel_open = true
	var hud: Control = $UILayer/HUD
	hud._show_city_panel(city_id)

func _close_city_panel() -> void:
	_city_panel_open = false
	_selected_city_id = &""
	var hud: Control = $UILayer/HUD
	hud._hide_city_panel()

# ── Region hover highlighting ────────────────────────────────

func _build_region_tiles_cache() -> void:
	_region_tiles_cache.clear()
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id == &"":
			continue
		if not _region_tiles_cache.has(tile.region_id):
			_region_tiles_cache[tile.region_id] = []
		_region_tiles_cache[tile.region_id].append(coord)

func _update_region_hover(world_pos: Vector2) -> void:
	var hex_coord := _pixel_to_hex(world_pos)
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var region_id: StringName = &""
	if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
		var tile := hex_map.get_tile(hex_coord)
		if tile:
			region_id = tile.region_id

	if region_id == _hovered_region_id:
		return

	_hovered_region_id = region_id
	_clear_region_highlight()

	if region_id == &"":
		return

	var tiles: Array = _region_tiles_cache.get(region_id, [])
	var polys := _build_world_hex_polys(tiles, HEX_RADIUS * 0.94)
	var draw_node := _OverlayDrawNode.new()
	draw_node.polys = polys
	draw_node.color = Color(1.0, 0.9, 0.5, 0.12)
	region_highlight_node.add_child(draw_node)
	_region_highlight_nodes.append(draw_node)

func _clear_region_highlight() -> void:
	for node in _region_highlight_nodes:
		node.queue_free()
	_region_highlight_nodes.clear()

# ── Input ─────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not TurnManager.is_player_turn or _is_animating_move:
		return

	# Settlement placement mode input handling
	if _settlement_placement_mode:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var world_pos := get_global_mouse_position()
				var hex_coord := _pixel_to_hex(world_pos)
				if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
					_handle_settlement_click(hex_coord)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_settlement_placement()
		if event is InputEventMouseMotion:
			var world_pos := get_global_mouse_position()
			var hex_coord := _pixel_to_hex(world_pos)
			_update_region_hover(world_pos)
			if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				# Preview panel content and position depend only on the hex —
				# rebuild it (free + recreate + income preview calc) only when
				# the hovered hex actually changes (mirrors _last_hover_hex).
				if hex_coord != _last_settlement_preview_hex:
					_last_settlement_preview_hex = hex_coord
					_show_settlement_preview(hex_coord)
		return

	# Building tile placement mode input handling
	if _building_tile_mode:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var world_pos := get_global_mouse_position()
				var hex_coord := _pixel_to_hex(world_pos)
				if _building_tile_valid.has(hex_coord):
					_cancel_building_tile_overlays()
					$UILayer/HUD.confirm_building_tile(hex_coord)
					_create_building_tile_markers()
					_fog_dirty = true
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_building_tile_overlays()
				$UILayer/HUD.cancel_building_tile()
		return

	# LEFT CLICK — select / deselect
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := get_global_mouse_position()
		var hex_coord := _pixel_to_hex(world_pos)
		if not HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			_deselect_all()
			return

		if selected_army_id != &"":
			# Army is selected: left-click on another army
			var clicked_army := _get_army_at_click(world_pos)
			if clicked_army != &"":
				var clicked: ArmyState = GameManager.state.armies.get(clicked_army)
				# Shift+Click on player army: add/remove from multi-selection
				if event.shift_pressed and clicked and clicked.faction_id == GameManager.state.player_faction_id:
					_toggle_army_multiselect(clicked_army)
					return
				if clicked_army == selected_army_id:
					# Clicking the same army — keep it selected, do nothing
					return
				if clicked and clicked.faction_id == GameManager.state.player_faction_id:
					_select_army(clicked_army)
					return
				elif clicked and clicked.faction_id != GameManager.state.player_faction_id:
					# Inspect enemy army WITHOUT deselecting player army
					_show_inspect_army(clicked)
					return
			# Clicked empty hex — deselect, then handle the hex
			_deselect_all()
			_handle_hex_left_click(hex_coord)
		else:
			_handle_hex_left_click(hex_coord)

	# RIGHT CLICK — move command (on release, only if not consumed by camera drag)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if camera._did_pan:
			return  # Camera drag consumed this right-click
		var world_pos := get_global_mouse_position()
		var hex_coord := _pixel_to_hex(world_pos)
		if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			if _selected_armies.size() > 1:
				_handle_multi_move_command(hex_coord)
			elif selected_army_id != &"":
				_handle_move_command(hex_coord)

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F:
				_fog_of_war_enabled = not _fog_of_war_enabled
				_fog_dirty = true
			KEY_SPACE, KEY_ENTER:
				if TurnManager.is_player_turn:
					EventBus.end_turn_pressed.emit()
			KEY_TAB:
				_cycle_player_armies()
			KEY_ESCAPE:
				_deselect_all()
				if _city_panel_open:
					_city_panel_open = false
					if city_markers_node:
						$UILayer/HUD._close_city_panel()
			KEY_C:
				if _selected_city_id != &"":
					$UILayer/HUD._show_city_panel(_selected_city_id)
			KEY_M:
				_toggle_minimap()
			KEY_O:
				$UILayer/HUD._toggle_army_overview()

	# Hover: region highlighting + path preview + trade route tooltip
	if event is InputEventMouseMotion:
		var world_pos := get_global_mouse_position()
		var hex_coord := _pixel_to_hex(world_pos)
		# Only do expensive hover work when the hovered hex actually changes
		if hex_coord != _last_hover_hex:
			_last_hover_hex = hex_coord
			_update_region_hover(world_pos)
			_update_trade_route_hover(world_pos)
			_update_bounty_hover(hex_coord)
			if selected_army_id != &"":
				if _reachable_tiles.has(hex_coord):
					_show_path_preview(hex_coord)
				else:
					_clear_path_overlay()

func _handle_hex_left_click(hex_coord: Vector2i) -> void:
	var tile_visible := _is_tile_visible(hex_coord)

	# Build list of all selectable objects at this hex
	var objects: Array = []  # Array of {type, id, data}

	# All armies at hex (player first, then others)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.hex_pos == hex_coord and not army.is_garrison:
			if army.faction_id == GameManager.state.player_faction_id:
				objects.insert(0, {type = "army", id = army.army_id, data = army})
			elif tile_visible:
				objects.append({type = "army", id = army.army_id, data = army})

	# Elderbeasts at hex
	for beast_id in GameManager.state.elderbeasts:
		var beast: ElderbeastState = GameManager.state.elderbeasts[beast_id]
		if beast.hex_pos == hex_coord:
			if beast.faction_id == GameManager.state.player_faction_id:
				objects.insert(mini(1, objects.size()), {type = "beast", id = beast.beast_id, data = beast})
			elif tile_visible:
				objects.append({type = "beast", id = beast.beast_id, data = beast})

	# City at hex
	var city_at := GameManager.city_system.get_city_at_hex(hex_coord)
	if city_at:
		if city_at.faction_id == GameManager.state.player_faction_id or tile_visible:
			objects.append({type = "city", id = city_at.city_id, data = city_at})

	if objects.is_empty():
		# Empty hex — close city panel if open, select hex for region info
		if _city_panel_open:
			_close_city_panel()
		_select_hex(hex_coord)
		_last_clicked_hex = Vector2i(-1, -1)
		return

	# Cycle logic — repeated clicks on same hex cycle through objects
	if hex_coord == _last_clicked_hex:
		_click_cycle_index = (_click_cycle_index + 1) % objects.size()
	else:
		_click_cycle_index = 0
		_last_clicked_hex = hex_coord

	var selected_obj = objects[_click_cycle_index]
	match selected_obj.type:
		"army":
			if selected_obj.data.faction_id == GameManager.state.player_faction_id:
				_select_army(selected_obj.id)
			else:
				_show_inspect_army(selected_obj.data)
		"beast":
			if selected_obj.data.faction_id == GameManager.state.player_faction_id:
				_select_elderbeast(selected_obj.id)
		"city":
			if selected_obj.data.faction_id == GameManager.state.player_faction_id:
				_open_city_panel(selected_obj.id)
			elif tile_visible:
				_show_inspect_city(selected_obj.data)

func _handle_move_command(hex_coord: Vector2i) -> void:
	var army: ArmyState = GameManager.state.armies.get(selected_army_id)
	if army == null or army.movement_remaining <= 0 or army.battle_exhausted:
		return
	if army.is_camp:
		return # Camped armies cannot move — break camp first
	if _reachable_tiles.has(hex_coord):
		_move_army_to(army, hex_coord)
	else:
		var closest := _find_closest_reachable_toward(army.hex_pos, hex_coord)
		if closest != Vector2i(-1, -1):
			_move_army_to(army, closest)

func _show_inspect_army(army: ArmyState) -> void:
	# Show commander panel in read-only mode for enemy armies
	var hud: Control = $UILayer/HUD
	hud._update_commander_panel(army)
	# Also show the army panel (unit cards)
	EventBus.army_selected.emit(army.army_id)

func _show_inspect_city(city: CityState) -> void:
	# Show city panel in read-only mode for enemy cities
	_selected_city_id = city.city_id
	_city_panel_open = true
	var hud: Control = $UILayer/HUD
	hud._show_city_panel(city.city_id)

func _get_army_at_click(world_pos: Vector2) -> StringName:
	# Check if click is within any army marker's bounds (22x22 px centered on marker)
	var click_radius := 14.0
	for army_id in _army_markers:
		var marker: Node2D = _army_markers[army_id]
		var dist := world_pos.distance_to(marker.global_position)
		if dist <= click_radius:
			return army_id
	return &""

func _move_army_to(army: ArmyState, hex_coord: Vector2i) -> void:
	var path := GameManager.movement_system.find_path(
		army.hex_pos, hex_coord, army.faction_id, army.movement_remaining, army.army_id, army.can_cross_mountains(), army)
	if path.size() > 0:
		_clear_reachable_overlay()
		_clear_path_overlay()
		_is_animating_move = true
		await _animate_army_along_path(selected_army_id, path)
		_is_animating_move = false
		# Refresh reachable tiles if army still exists and has movement
		army = GameManager.state.armies.get(selected_army_id)
		if army and army.movement_remaining > 0:
			_show_reachable_tiles(army)
			EventBus.army_selected.emit(selected_army_id)
		else:
			_reachable_tiles = {}
		# Refresh beast terrain overlay after movement
		if army and army.elderbeast_id != &"":
			var beast: ElderbeastState = GameManager.state.elderbeasts.get(army.elderbeast_id)
			if beast:
				_show_beast_terrain_overlay(beast)

func _animate_army_along_path(army_id: StringName, path: Array[Vector2i]) -> void:
	# Move army tile by tile with animation between each step
	# Process one tile at a time via GameManager, animate between each
	var marker: Node2D = _army_markers.get(army_id)

	for i in path.size():
		var army: ArmyState = GameManager.state.armies.get(army_id)
		if army == null:
			break

		var tile_coord := path[i]
		var cost := GameManager.state.hex_map.get_movement_cost(tile_coord, army.faction_id)
		# Apply army terrain stride modifier (junglestrider, desertstrider, etc.)
		var _tile := GameManager.state.hex_map.get_tile(tile_coord)
		if _tile:
			cost *= army.get_terrain_stride_modifier(_tile.terrain)
		if army.movement_remaining < cost:
			break

		# Animate marker to next tile position BEFORE processing game logic
		if marker:
			var prev_pos := marker.position
			var target_pixel := _hex_to_pixel(tile_coord)
			var tween := create_tween()
			tween.tween_property(marker, "position", target_pixel, 0.15)
			await tween.finished
			# Spawn dust cloud at previous position
			_spawn_dust_cloud(prev_pos, army.hex_pos)

		# Now process this single step via GameManager
		var single_step: Array[Vector2i] = [tile_coord]
		GameManager.move_army_along_path(army_id, single_step)

		# Check if battle triggered or army destroyed
		if not GameManager.state.armies.has(army_id):
			return
		if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
			return

	# Flush deferred fog/overlay updates now that movement is complete
	if _fog_update_pending:
		_fog_update_pending = false
		_fog_dirty = true
	_update_political_overlay()
	_create_army_markers()
	# Re-show selection ring on the moving army if it still exists
	if GameManager.state.armies.has(army_id):
		var new_marker: Node2D = _army_markers.get(army_id)
		if new_marker:
			var ring := new_marker.get_node_or_null("SelectionRing")
			if ring:
				ring.visible = true
		# Refresh army panel
		EventBus.army_selected.emit(army_id)

func _spawn_dust_cloud(world_pos: Vector2, hex_pos: Vector2i) -> void:
	# Spawn 3-4 small circles that fade out over 0.5s with slight upward drift
	var tile := GameManager.state.hex_map.get_tile(hex_pos)
	var dust_color := Color(0.55, 0.48, 0.35, 0.4)  # Default tan
	if tile:
		match tile.terrain:
			Enums.TerrainType.FOREST, Enums.TerrainType.JUNGLE:
				dust_color = Color(0.35, 0.38, 0.28, 0.35)
			Enums.TerrainType.DESERT:
				dust_color = Color(0.65, 0.55, 0.38, 0.45)
			Enums.TerrainType.TUNDRA:
				dust_color = Color(0.7, 0.7, 0.72, 0.35)
			Enums.TerrainType.SWAMP, Enums.TerrainType.WETLANDS:
				dust_color = Color(0.4, 0.38, 0.28, 0.3)
			Enums.TerrainType.MOUNTAINS:
				dust_color = Color(0.5, 0.48, 0.44, 0.4)
	for j in randi_range(3, 4):
		var particle := Polygon2D.new()
		var r := randf_range(3.0, 6.0)
		var pts := PackedVector2Array()
		for k in 6:
			var angle := TAU * float(k) / 6.0
			pts.append(Vector2(cos(angle) * r, sin(angle) * r))
		particle.polygon = pts
		particle.color = dust_color
		particle.position = world_pos + Vector2(randf_range(-8, 8), randf_range(-4, 4))
		army_markers_node.add_child(particle)
		var tw := create_tween()
		tw.tween_property(particle, "position:y", particle.position.y - randf_range(8, 14), 0.5)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, 0.5)
		tw.tween_callback(particle.queue_free)

func _find_closest_reachable_toward(from: Vector2i, target: Vector2i) -> Vector2i:
	# Find the reachable tile closest to the target
	var best := Vector2i(-1, -1)
	var best_dist := 9999
	for coord in _reachable_tiles:
		var dist := HexHelper.hex_distance(coord, target)
		if dist < best_dist:
			best_dist = dist
			best = coord
		elif dist == best_dist:
			# Tie-break: prefer tile closer to start (shorter path)
			var d1 := HexHelper.hex_distance(from, coord)
			var d2 := HexHelper.hex_distance(from, best)
			if d1 < d2:
				best = coord
	return best

func _select_army(army_id: StringName) -> void:
	# Hide previous selection ring
	_hide_all_selection_rings()
	selected_army_id = army_id
	_selected_armies = [army_id]
	GameManager.state.selected_army_id = army_id
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army:
		selected_hex = army.hex_pos
		if army.faction_id == GameManager.state.player_faction_id:
			_show_reachable_tiles(army)
	# Show selection ring
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		var ring := marker.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = true
	EventBus.army_selected.emit(army_id)
	EventBus.hex_tile_selected.emit(selected_hex)

	# Also open city panel if player army is standing on a player city
	if army and army.faction_id == GameManager.state.player_faction_id:
		var city_at := GameManager.city_system.get_city_at_hex(army.hex_pos)
		if city_at and city_at.faction_id == GameManager.state.player_faction_id:
			_open_city_panel(city_at.city_id)

	# Show elderbeast panel and terrain overlay if army escorts a beast
	if army and army.elderbeast_id != &"":
		_selected_beast_id = army.elderbeast_id
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(army.elderbeast_id)
		if beast:
			var hud: Control = $UILayer/HUD
			if hud.has_method("_show_elderbeast_panel"):
				hud._show_elderbeast_panel(beast)
			_show_beast_terrain_overlay(beast)

func _select_hex(hex_coord: Vector2i) -> void:
	selected_hex = hex_coord
	selected_army_id = &""
	GameManager.state.selected_army_id = &""
	_clear_reachable_overlay()
	_clear_path_overlay()
	EventBus.hex_tile_selected.emit(hex_coord)

func _deselect_all() -> void:
	_hide_all_selection_rings()
	selected_hex = Vector2i(-1, -1)
	selected_army_id = &""
	_selected_armies.clear()
	_selected_beast_id = &""
	GameManager.state.selected_army_id = &""
	_reachable_tiles = {}
	_clear_reachable_overlay()
	_clear_path_overlay()
	_clear_beast_terrain_overlay()
	EventBus.army_deselected.emit()
	EventBus.hex_tile_deselected.emit()

func _toggle_army_multiselect(army_id: StringName) -> void:
	# Ensure primary selection is in the multi-select list
	if _selected_armies.is_empty() and selected_army_id != &"":
		_selected_armies.append(selected_army_id)
	if _selected_armies.has(army_id):
		_selected_armies.erase(army_id)
		# Hide ring for removed army
		var marker: Node2D = _army_markers.get(army_id)
		if marker:
			var ring := marker.get_node_or_null("SelectionRing")
			if ring:
				ring.visible = false
		# If we removed the primary, switch to first in list
		if army_id == selected_army_id and _selected_armies.size() > 0:
			selected_army_id = _selected_armies[0]
			GameManager.state.selected_army_id = selected_army_id
		elif _selected_armies.is_empty():
			_deselect_all()
	else:
		_selected_armies.append(army_id)
		# Show ring for added army
		var marker: Node2D = _army_markers.get(army_id)
		if marker:
			var ring := marker.get_node_or_null("SelectionRing")
			if ring:
				ring.visible = true

func _handle_multi_move_command(hex_coord: Vector2i) -> void:
	# Move all selected armies independently toward the target hex
	for army_id in _selected_armies:
		var army: ArmyState = GameManager.state.armies.get(army_id)
		if army == null or army.movement_remaining <= 0 or army.battle_exhausted:
			continue
		GameManager.movement_system.refresh_caches()
		var reachable := GameManager.movement_system.get_reachable_tiles(
			army.hex_pos, army.movement_remaining, army.faction_id, army.army_id, army.can_cross_mountains(), army)
		if reachable.has(hex_coord):
			_move_army_to(army, hex_coord)
		else:
			# Find closest reachable tile toward target
			var best := Vector2i(-1, -1)
			var best_dist := 9999
			for coord in reachable:
				var d := HexHelper.hex_distance(coord, hex_coord)
				if d < best_dist:
					best_dist = d
					best = coord
			if best != Vector2i(-1, -1):
				_move_army_to(army, best)
		# Wait for animation to finish before moving next army
		if _is_animating_move:
			await get_tree().process_frame

func _cycle_player_armies() -> void:
	var player_armies: Array[StringName] = []
	for aid in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[aid]
		if army.faction_id == GameManager.state.player_faction_id and not army.is_garrison:
			player_armies.append(aid)
	if player_armies.is_empty():
		return
	var current_idx := -1
	if selected_army_id != &"":
		current_idx = player_armies.find(selected_army_id)
	var next_idx := (current_idx + 1) % player_armies.size()
	_select_army(player_armies[next_idx])
	var army: ArmyState = GameManager.state.armies.get(player_armies[next_idx])
	if army and camera:
		camera.position = _hex_to_pixel(army.hex_pos)

var _city_cycle_index: int = -1

func _cycle_player_cities() -> void:
	var player_cities: Array[StringName] = []
	for cid in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[cid]
		if city.faction_id == GameManager.state.player_faction_id:
			player_cities.append(cid)
	if player_cities.is_empty():
		return
	_city_cycle_index = (_city_cycle_index + 1) % player_cities.size()
	var city_id := player_cities[_city_cycle_index]
	var city: CityState = GameManager.state.cities[city_id]
	_selected_city_id = city_id
	if camera:
		camera.position = _hex_to_pixel(city.hex_pos)
	$UILayer/HUD._show_city_panel(city_id)

func _toggle_minimap() -> void:
	var minimap := get_node_or_null("UILayer/Minimap")
	if minimap:
		minimap.visible = not minimap.visible

func _hide_all_selection_rings() -> void:
	for army_id in _army_markers:
		var marker: Node2D = _army_markers[army_id]
		var ring := marker.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = false
	for beast_id in _elderbeast_markers:
		var marker: Node2D = _elderbeast_markers[beast_id]
		var ring := marker.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = false

var _reachable_draw_node: Node2D = null
var _path_draw_node: Node2D = null

func _show_reachable_tiles(army: ArmyState) -> void:
	_clear_reachable_overlay()
	_reachable_tiles = GameManager.movement_system.get_reachable_tiles(
		army.hex_pos, army.movement_remaining, army.faction_id, army.army_id, army.can_cross_mountains(), army)

	var polys := _build_world_hex_polys(_reachable_tiles.keys(), HEX_RADIUS * 0.88)
	_reachable_draw_node = _OverlayDrawNode.new()
	_reachable_draw_node.polys = polys
	_reachable_draw_node.color = Color(0.2, 0.8, 0.2, 0.25)
	reachable_overlay.add_child(_reachable_draw_node)

func _show_path_preview(target: Vector2i) -> void:
	# Skip recomputation if hovered hex hasn't changed
	if target == _last_path_preview_hex:
		return
	_clear_path_overlay()
	_last_path_preview_hex = target
	var army: ArmyState = GameManager.state.armies.get(selected_army_id)
	if army == null:
		return
	var path := GameManager.movement_system.find_path(
		army.hex_pos, target, army.faction_id, army.movement_remaining, army.army_id, army.can_cross_mountains(), army)
	var polys := _build_world_hex_polys(path, HEX_RADIUS * 0.6)
	_path_draw_node = _OverlayDrawNode.new()
	_path_draw_node.polys = polys
	_path_draw_node.color = Color(1.0, 1.0, 0.3, 0.45)
	path_overlay.add_child(_path_draw_node)
	# Movement cost label at end of path
	if path.size() > 0:
		var total_cost := 0.0
		for tile_coord in path:
			var tile_cost := GameManager.state.hex_map.get_movement_cost(tile_coord, army.faction_id)
			var tile_data := GameManager.state.hex_map.get_tile(tile_coord)
			if tile_data:
				tile_cost *= army.get_terrain_stride_modifier(tile_data.terrain)
			total_cost += tile_cost
		var cost_label := Label.new()
		cost_label.text = "MP: %.1f" % total_cost
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		cost_label.add_theme_constant_override("outline_size", 2)
		cost_label.position = _hex_to_pixel(path[-1]) + Vector2(-20, -24)
		path_overlay.add_child(cost_label)

func _clear_reachable_overlay() -> void:
	if _reachable_draw_node and is_instance_valid(_reachable_draw_node):
		_reachable_draw_node.queue_free()
	_reachable_draw_node = null
	for child in reachable_overlay.get_children():
		child.queue_free()

func _clear_path_overlay() -> void:
	_last_path_preview_hex = Vector2i(-1, -1)
	if _path_draw_node and is_instance_valid(_path_draw_node):
		_path_draw_node.queue_free()
	_path_draw_node = null
	for child in path_overlay.get_children():
		child.queue_free()

# ── Signal handlers ───────────────────────────────────────────

var _fog_update_pending := false  # Deferred fog update during animated movement

func _on_army_moved(army_id: StringName, from_hex: Vector2i, to_hex: Vector2i) -> void:
	var army: ArmyState = GameManager.state.armies.get(army_id)
	var is_player_army := army and army.faction_id == GameManager.state.player_faction_id

	# During AI turns, skip all heavy visual updates — they'll be rebuilt on player turn start
	if not TurnManager.is_player_turn and not is_player_army:
		# Just snap marker position silently
		var marker: Node2D = _army_markers.get(army_id)
		if marker:
			marker.position = _hex_to_pixel(to_hex)
		return

	var from_visible := _is_tile_visible(from_hex)
	var to_visible := _is_tile_visible(to_hex)
	var move_visible := is_player_army or from_visible or to_visible

	# Only play march sound if movement is visible in LOS
	if move_visible:
		AudioManager.play_sfx(&"march")

	# If we're animating player movement, the animation handles marker position.
	# For other armies: only animate if destination is visible to the player.
	if not _is_animating_move:
		var marker: Node2D = _army_markers.get(army_id)
		if marker:
			if is_player_army or to_visible:
				var target_pos := _hex_to_pixel(to_hex)
				var tween := marker.create_tween()
				tween.tween_property(marker, "position", target_pos, 0.08)
			else:
				# Snap position silently (marker is hidden by fog anyway)
				marker.position = _hex_to_pixel(to_hex)

	# During animated player movement, defer heavy fog/overlay updates to movement end.
	# This avoids rebuilding the entire visible tile cache on EVERY tile step.
	if _is_animating_move:
		_fog_update_pending = true
		_minimap_dirty = true
		return

	# Only update heavy visuals if move was visible to player
	if move_visible:
		_fog_dirty = true
		if is_player_army:
			_update_political_overlay()
		_minimap_dirty = true
	elif is_player_army:
		# Player army moved — always update fog
		_fog_dirty = true
		_minimap_dirty = true

func _on_army_destroyed(army_id: StringName, _faction_id: StringName) -> void:
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		marker.queue_free()
		_army_markers.erase(army_id)
	# A destroyed/disbanded army must never stay selected: the stale id left
	# the reachable overlay and the move/commander paths pointing at a freed
	# army, which crashed on the next click.
	_selected_armies.erase(army_id)
	if selected_army_id == army_id:
		_deselect_all()

func _on_region_ownership_changed(_region_id: StringName, _old: StringName, _new: StringName) -> void:
	# Defer heavy visual work during AI turns — will be rebuilt on player turn start
	if not TurnManager.is_player_turn:
		_minimap_terrain_dirty = true
		return
	_update_political_overlay()
	_refresh_faction_borders()
	_fog_dirty = true
	_minimap_terrain_dirty = true

func _exit_tree() -> void:
	# No campaign UI once this scene leaves — battles auto-resolve headlessly.
	BattleResolver.ui_active = false

## Player army met an enemy while this scene is on-screen — BattleResolver has
## already merged garrison reinforcements and now asks us to prompt the player.
func _on_battle_player_prompt(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return
	_pending_battle_attacker_id = attacker_id
	_pending_battle_defender_id = defender_id
	_pending_battle_hex = hex_pos
	_show_battle_dialog(attacker_army, defender_army)

## BattleResolver finished an auto-resolved battle. Refresh markers and, if the
## player was involved, show the battle report.
func _on_battle_auto_resolved(report: Dictionary) -> void:
	_create_army_markers()
	if not report.is_empty():
		_show_battle_report(report)

func _show_battle_dialog(attacker_army: ArmyState, defender_army: ArmyState) -> void:
	if _battle_dialog:
		_battle_dialog.queue_free()

	# Hide army panel so it doesn't block battle dialog buttons
	var hud_node := $UILayer/HUD
	if hud_node.has_method("_close_army_panel"):
		hud_node._close_army_panel()
	elif hud_node.has_node("SelectedArmyPanel"):
		hud_node.get_node("SelectedArmyPanel").visible = false

	var atk_faction: FactionData = DataManager.get_faction(attacker_army.faction_id)
	var def_faction: FactionData = DataManager.get_faction(defender_army.faction_id)
	var atk_name: String = atk_faction.display_name if atk_faction else str(attacker_army.faction_id)
	var def_name: String = def_faction.display_name if def_faction else str(defender_army.faction_id)

	_battle_dialog = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	_battle_dialog.add_theme_stylebox_override("panel", style)

	# Center on screen
	_battle_dialog.anchors_preset = Control.PRESET_CENTER
	_battle_dialog.anchor_left = 0.5
	_battle_dialog.anchor_top = 0.5
	_battle_dialog.anchor_right = 0.5
	_battle_dialog.anchor_bottom = 0.5
	_battle_dialog.offset_left = -200
	_battle_dialog.offset_top = -150
	_battle_dialog.offset_right = 200
	_battle_dialog.offset_bottom = 150
	_battle_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_battle_dialog.z_index = 50  # Ensure battle dialog is always on top of other panels

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_battle_dialog.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "BATTLE!"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep)

	# Attacker info
	var atk_label := Label.new()
	atk_label.text = "%s  (%d units)" % [atk_name, attacker_army.units.size()]
	atk_label.add_theme_font_size_override("font_size", 14)
	atk_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35, 1))
	atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(atk_label)

	# Unit list for attacker
	var atk_units := Label.new()
	var atk_texts: Array[String] = []
	for u in attacker_army.units:
		var ud := DataManager.get_unit(u.unit_data_id)
		if ud:
			atk_texts.append("  %s (HP:%d)" % [ud.display_name, u.current_hp])
	atk_units.text = "\n".join(atk_texts) if atk_texts.size() > 0 else "  (no units)"
	atk_units.add_theme_font_size_override("font_size", 11)
	atk_units.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65, 1))
	vbox.add_child(atk_units)

	# VS
	var vs := Label.new()
	vs.text = "VS"
	vs.add_theme_font_size_override("font_size", 16)
	vs.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55, 1))
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(vs)

	# Defender info
	var def_label := Label.new()
	def_label.text = "%s  (%d units)" % [def_name, defender_army.units.size()]
	def_label.add_theme_font_size_override("font_size", 14)
	def_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.85, 1))
	def_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(def_label)

	var def_units := Label.new()
	var def_texts: Array[String] = []
	for u in defender_army.units:
		var ud := DataManager.get_unit(u.unit_data_id)
		if ud:
			def_texts.append("  %s (HP:%d)" % [ud.display_name, u.current_hp])
	def_units.text = "\n".join(def_texts) if def_texts.size() > 0 else "  (no units)"
	def_units.add_theme_font_size_override("font_size", 11)
	def_units.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65, 1))
	vbox.add_child(def_units)

	# Bonuses summary
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep2)

	var bonus_label := Label.new()
	bonus_label.add_theme_font_size_override("font_size", 11)
	bonus_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	var bonus_parts: Array[String] = []

	# Terrain
	var campaign_terrain := Enums.TerrainType.PLAINS
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(_pending_battle_hex)
		if tile:
			campaign_terrain = tile.terrain
	var terrain_names := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
	var t_name: String = terrain_names[campaign_terrain] if campaign_terrain < terrain_names.size() else "Unknown"
	bonus_parts.append("Terrain: %s" % t_name)

	# Commander bonuses
	var player_fid := GameManager.state.player_faction_id
	var player_army: ArmyState = attacker_army if attacker_army.faction_id == player_fid else defender_army
	if player_army.commander:
		var cmd_bonuses := CommanderSystem.get_commander_army_bonuses(player_army.commander)
		var cmd_parts: Array[String] = []
		if cmd_bonuses.get("attack_bonus", 0) != 0:
			cmd_parts.append("ATK %+d (per entity)" % cmd_bonuses.attack_bonus)
		if cmd_bonuses.get("defense_bonus", 0) != 0:
			cmd_parts.append("DEF %+d" % cmd_bonuses.defense_bonus)
		if cmd_bonuses.get("speed_bonus", 0) != 0:
			cmd_parts.append("SPD %+d" % cmd_bonuses.speed_bonus)
		if cmd_parts.size() > 0:
			bonus_parts.append("Commander: " + ", ".join(cmd_parts))

	# Research bonuses
	var r_effects := GameManager.research_system.get_research_effects(player_fid)
	if r_effects.size() > 0:
		var r_parts: Array[String] = []
		if r_effects.get("unit_attack_pct", 0) != 0:
			r_parts.append("ATK %+d%%" % r_effects["unit_attack_pct"])
		if r_effects.get("unit_defense_pct", 0) != 0:
			r_parts.append("DEF %+d%%" % r_effects["unit_defense_pct"])
		if r_parts.size() > 0:
			bonus_parts.append("Research: " + ", ".join(r_parts))

	bonus_label.text = "\n".join(bonus_parts)
	vbox.add_child(bonus_label)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep3)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var manual_btn := Button.new()
	manual_btn.text = "Manual Battle"
	manual_btn.custom_minimum_size = Vector2(130, 36)
	manual_btn.pressed.connect(_on_battle_dialog_manual)
	btn_row.add_child(manual_btn)

	var retreat_btn := Button.new()
	retreat_btn.text = "Retreat"
	retreat_btn.custom_minimum_size = Vector2(130, 36)
	retreat_btn.pressed.connect(_on_battle_dialog_retreat)
	# Disable for siege battles
	var city := GameManager.city_system.get_city_at_hex(_pending_battle_hex)
	if city and city.is_under_siege:
		retreat_btn.disabled = true
		retreat_btn.tooltip_text = "Cannot retreat during siege"
	btn_row.add_child(retreat_btn)

	var auto_btn := Button.new()
	auto_btn.text = "Auto-Resolve"
	auto_btn.custom_minimum_size = Vector2(130, 36)
	auto_btn.pressed.connect(_on_battle_dialog_auto)
	btn_row.add_child(auto_btn)

	$UILayer/HUD.add_child(_battle_dialog)
	_battle_dialog.move_to_front()

func _on_battle_dialog_manual() -> void:
	if _battle_dialog:
		_battle_dialog.queue_free()
		_battle_dialog = null
	GameManager.current_phase = Enums.GamePhase.BATTLE_SETUP
	GameManager.set_meta("battle_attacker", _pending_battle_attacker_id)
	GameManager.set_meta("battle_defender", _pending_battle_defender_id)
	GameManager.set_meta("battle_hex_pos", _pending_battle_hex)
	GameManager.transition_to_scene("res://scenes/battle/battle_v3.tscn")

func _on_battle_dialog_retreat() -> void:
	if _battle_dialog:
		_battle_dialog.queue_free()
		_battle_dialog = null
	_execute_retreat(_pending_battle_attacker_id, _pending_battle_defender_id, _pending_battle_hex)

func _on_battle_dialog_auto() -> void:
	if _battle_dialog:
		_battle_dialog.queue_free()
		_battle_dialog = null
	BattleResolver.auto_resolve(_pending_battle_attacker_id, _pending_battle_defender_id, _pending_battle_hex)

func _execute_retreat(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var player_fid := GameManager.state.player_faction_id
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

	# Determine which is the player army
	var player_army: ArmyState
	var enemy_army: ArmyState
	if attacker_army.faction_id == player_fid:
		player_army = attacker_army
		enemy_army = defender_army
	else:
		player_army = defender_army
		enemy_army = attacker_army

	# Calculate speed ratio
	var player_avg_speed := 0.0
	for unit in player_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			player_avg_speed += ud.speed
	if player_army.units.size() > 0:
		player_avg_speed /= player_army.units.size()

	var enemy_avg_speed := 0.0
	for unit in enemy_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud:
			enemy_avg_speed += ud.speed
	if enemy_army.units.size() > 0:
		enemy_avg_speed /= enemy_army.units.size()

	var speed_ratio := player_avg_speed / maxf(enemy_avg_speed, 1.0)

	# Count enemy ranged units
	var enemy_ranged_count := 0
	for unit in enemy_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		if ud and (ud.tags.has("ranged") or ud.tags.has("mage")):
			enemy_ranged_count += 1

	var base_loss_chance := clampf(0.40 - speed_ratio * 0.15, 0.05, 0.50)
	base_loss_chance += enemy_ranged_count * 0.05
	base_loss_chance = minf(base_loss_chance, 0.60)

	# Apply losses
	var lost_count := 0
	var surviving_units: Array[UnitInstance] = []
	for unit in player_army.units:
		if randf() < base_loss_chance:
			lost_count += 1
		else:
			# Survivors take 10-30% HP loss
			var hp_loss := int(unit.current_hp * randf_range(0.10, 0.30))
			unit.current_hp = maxi(1, unit.current_hp - hp_loss)
			surviving_units.append(unit)
	player_army.units = surviving_units

	# Move army back one hex
	var from_hex := player_army.hex_pos
	var retreat_hex := _find_retreat_hex(player_army, enemy_army.hex_pos)
	if retreat_hex != Vector2i(-1, -1):
		player_army.hex_pos = retreat_hex
		GameManager.movement_system.invalidate_positions()

	# Remove army if no survivors
	if surviving_units.is_empty():
		GameManager.remove_army(player_army.army_id)

	EventBus.army_retreated.emit(player_army.army_id, from_hex, retreat_hex, lost_count)

	# Show retreat summary
	_show_retreat_report(player_army, lost_count, from_hex, retreat_hex)
	_create_army_markers()

func _find_retreat_hex(army: ArmyState, enemy_hex: Vector2i) -> Vector2i:
	# Find adjacent hex that's farthest from enemy and passable
	var neighbors := HexHelper.get_neighbors(army.hex_pos)
	var best_hex := Vector2i(-1, -1)
	var best_dist := -1
	for n in neighbors:
		if not GameManager.state.hex_map.tiles.has(n):
			continue
		var tile: HexMapData.TileState = GameManager.state.hex_map.tiles[n]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(n, enemy_hex)
		if dist > best_dist:
			best_dist = dist
			best_hex = n
	return best_hex

func _show_retreat_report(army: ArmyState, losses: int, from_hex: Vector2i, to_hex: Vector2i) -> void:
	if _battle_report_panel:
		_battle_report_panel.queue_free()

	_battle_report_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	_battle_report_panel.add_theme_stylebox_override("panel", style)
	_battle_report_panel.anchors_preset = Control.PRESET_CENTER
	_battle_report_panel.anchor_left = 0.5
	_battle_report_panel.anchor_top = 0.5
	_battle_report_panel.anchor_right = 0.5
	_battle_report_panel.anchor_bottom = 0.5
	_battle_report_panel.offset_left = -150
	_battle_report_panel.offset_top = -80
	_battle_report_panel.offset_right = 150
	_battle_report_panel.offset_bottom = 80
	_battle_report_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_report_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "RETREAT"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var info := Label.new()
	info.text = "Your army retreated from battle.\nUnits lost: %d\nSurvivors: %d" % [losses, army.units.size()]
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)

	var close_btn := Button.new()
	close_btn.text = "OK"
	close_btn.custom_minimum_size = Vector2(80, 30)
	close_btn.pressed.connect(func() -> void:
		if _battle_report_panel:
			_battle_report_panel.queue_free()
			_battle_report_panel = null
	)
	vbox.add_child(close_btn)

	_battle_report_panel.add_child(vbox)
	$UILayer/HUD.add_child(_battle_report_panel)

func _flash_turn_transition() -> void:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0.4)
	fade.anchor_left = 0
	fade.anchor_top = 0
	fade.anchor_right = 1
	fade.anchor_bottom = 1
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, 0.4)
	tween.tween_callback(fade.queue_free)

func _on_turn_started(_turn: int, faction_id: StringName) -> void:
	var is_player := faction_id == GameManager.state.player_faction_id
	# Brief turn transition fade — only on player turn to avoid AI flicker
	if is_player:
		_flash_turn_transition()
		AudioManager.play_sfx(&"turn_chime")
		_show_notification("Your turn - Turn " + str(GameManager.state.current_turn))
		# Full marker refresh only on player turn (catches all deferred AI-turn changes)
		_city_markers_dirty = true
		_refresh_city_markers()
		_create_building_tile_markers()
		_update_city_glow_states()
		_minimap_terrain_dirty = true
		# Full visual refresh only on player turn (army markers, fog, minimap, territory)
		_update_political_overlay()
		_refresh_faction_borders()
		_create_army_markers()
		_create_elderbeast_markers()
		# Apply fog SYNCHRONOUSLY here: the markers were just recreated (visible by
		# default), so a deferred fog pass would let fogged enemy armies flash for a
		# frame at turn start before being hidden. Run it now, before this frame draws.
		_update_fog_of_war()
		_update_trade_routes()
		_minimap_dirty = true
		if selected_army_id != &"":
			var army: ArmyState = GameManager.state.armies.get(selected_army_id)
			if army:
				_show_reachable_tiles(army)
				EventBus.army_selected.emit(selected_army_id)
		# Refresh beast terrain overlay if an elderbeast is still selected
		if _selected_beast_id != &"":
			var beast: ElderbeastState = GameManager.state.elderbeasts.get(_selected_beast_id)
			if beast:
				_show_beast_terrain_overlay(beast)
		# Refresh city panel if open
		if _city_panel_open and _selected_city_id != &"":
			_open_city_panel(_selected_city_id)
	else:
		# During AI turns, only mark minimap as dirty (cheap flag).
		# Skip expensive marker/fog rebuilds — they'll refresh when player turn starts.
		_minimap_dirty = true

func _on_shardfall_occurred(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm) -> void:
	_create_shard_marker(shard_id, hex_pos, realm)
	_create_army_markers() # Refresh to show guardian army
	if _is_tile_visible(hex_pos):
		AudioManager.play_sfx(&"shard_claim")
		var realm_name := ShardfallSystem.get_realm_name(realm)
		var tile := GameManager.state.hex_map.get_tile(hex_pos)
		var region_name := ""
		if tile:
			var region := DataManager.get_region(tile.region_id)
			region_name = region.display_name if region else str(tile.region_id)
		_show_notification("SHARDFALL! A " + realm_name + " shard has fallen in " + region_name + "! Guardians protect it.")

func _on_shard_claimed(shard_id: StringName, faction_id: StringName) -> void:
	if _shard_markers.has(shard_id):
		_shard_markers[shard_id].queue_free()
		_shard_markers.erase(shard_id)
	if faction_id == GameManager.state.player_faction_id:
		var shard: ShardInstance = GameManager.state.active_shards.get(shard_id)
		var shard_value: int = shard.power_level * 5 if shard else 5
		_show_notification("Shard claimed! +%d Shards" % shard_value)

func _on_shard_expired(shard_id: StringName) -> void:
	if _shard_markers.has(shard_id):
		_shard_markers[shard_id].queue_free()
		_shard_markers.erase(shard_id)

func _create_shard_marker(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(hex_pos) + Vector2(0, -12)
	var base_color := ShardfallSystem.get_realm_color(realm)

	# Glow underneath
	var glow := Polygon2D.new()
	glow.polygon = _make_circle(10.0, 8)
	glow.color = Color(base_color.r, base_color.g, base_color.b, 0.25)
	marker.add_child(glow)

	# Main crystal body (hexagonal prism cross-section)
	var crystal_main := Polygon2D.new()
	crystal_main.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(5, -6), Vector2(5, 2),
		Vector2(0, 6), Vector2(-5, 2), Vector2(-5, -6)
	])
	crystal_main.color = base_color
	marker.add_child(crystal_main)

	# Left facet (darker)
	var facet_l := Polygon2D.new()
	facet_l.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(-5, -6), Vector2(-5, 2), Vector2(0, 6)
	])
	facet_l.color = base_color.darkened(0.25)
	marker.add_child(facet_l)

	# Right highlight (lighter)
	var facet_r := Polygon2D.new()
	facet_r.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(5, -6), Vector2(3, -2), Vector2(0, -4)
	])
	facet_r.color = base_color.lightened(0.3)
	facet_r.color.a = 0.6
	marker.add_child(facet_r)

	# Small secondary crystal shard (offset)
	var shard_small := Polygon2D.new()
	shard_small.polygon = PackedVector2Array([
		Vector2(0, -6), Vector2(3, -3), Vector2(3, 1), Vector2(0, 3), Vector2(-1, 0), Vector2(-1, -4)
	])
	shard_small.color = base_color.lightened(0.1)
	shard_small.position = Vector2(5, 2)
	shard_small.scale = Vector2(0.6, 0.6)
	marker.add_child(shard_small)

	# Pulsing glow animation
	var tween := marker.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.3, 0.8)
	tween.tween_property(glow, "modulate:a", 1.0, 0.8)

	shard_markers_node.add_child(marker)
	_shard_markers[shard_id] = marker

func _recreate_shard_markers() -> void:
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if shard.claimed_by == &"":
			_create_shard_marker(shard_id, shard.hex_pos, shard.realm)

func _on_city_captured(city_id: StringName, _old_owner: StringName, new_owner: StringName) -> void:
	_invalidate_city_action_cache()
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			var faction: FactionData = DataManager.get_faction(new_owner)
			var fname: String = faction.display_name if faction else str(new_owner)
			_show_notification(fname + " captured " + city.get_display_name() + "!")
	if new_owner == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"victory")
	_city_markers_dirty = true
	_minimap_terrain_dirty = true
	# Defer heavy visual work during AI turns
	if TurnManager.is_player_turn:
		_refresh_city_markers()
		_update_political_overlay()
		_refresh_faction_borders()

func _on_siege_started(city_id: StringName, faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			AudioManager.play_sfx(&"march")
			var faction: FactionData = DataManager.get_faction(faction_id)
			var fname: String = faction.display_name if faction else str(faction_id)
			_show_notification(fname + " is besieging " + city.get_display_name() + "!")
	_city_markers_dirty = true
	if TurnManager.is_player_turn:
		_refresh_city_markers()

func _on_siege_broken(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			AudioManager.play_sfx(&"battle_hit")
			_show_notification("Siege of " + city.get_display_name() + " broken!")
	_city_markers_dirty = true
	if TurnManager.is_player_turn:
		_refresh_city_markers()

func _on_siege_badge_update(city_id: StringName, _pressure: float, _threshold: int) -> void:
	_refresh_siege_badge(city_id)

func _refresh_siege_badge(city_id: StringName) -> void:
	var marker: Node2D = _city_markers.get(city_id)
	if marker == null:
		return
	var badge: Label = marker.get_node_or_null("SiegeBadge")
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null or not city.is_under_siege:
		if badge:
			badge.queue_free()
		var stale_bar := marker.get_node_or_null("SiegeBar")
		if stale_bar:
			stale_bar.queue_free()
		return
	if badge == null:
		badge = Label.new()
		badge.name = "SiegeBadge"
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		badge.add_theme_color_override("font_outline_color", Color(0.4, 0.03, 0.02))
		badge.add_theme_constant_override("outline_size", 6)
		badge.z_index = 5
		# Offset up-and-right of the level badge / capital crown (which sit
		# centered around x=0, y=-29 to -43) so the two don't overlap.
		badge.position = Vector2(10, -46)
		marker.add_child(badge)
	var threshold := GameManager.city_system.get_siege_threshold(city)
	var falls_in := int(ceil(maxf(0.0, float(threshold) - city.siege_turns)))
	badge.text = "⚔%d" % falls_in
	_refresh_siege_bar(marker, city)

## Small siege-progress bar under a besieged city marker (mirrors the city-panel
## bar). Created inline like SiegeRing so it survives marker rebuilds; the fill
## width tracks siege pressure / threshold. Uses Polygon2D (Node2D-native).
func _refresh_siege_bar(marker: Node2D, city: CityState) -> void:
	const BAR_W := 30.0
	const BAR_H := 5.0
	var bar: Node2D = marker.get_node_or_null("SiegeBar")
	if not city.is_under_siege:
		if bar:
			bar.queue_free()
		return
	if bar == null:
		bar = Node2D.new()
		bar.name = "SiegeBar"
		bar.z_index = 5
		# Centered horizontally, sitting just below the city marker.
		bar.position = Vector2(-BAR_W * 0.5, 15.0)
		var bg := Polygon2D.new()
		bg.name = "BG"
		bg.polygon = PackedVector2Array([
			Vector2(-1, -1), Vector2(BAR_W + 1, -1),
			Vector2(BAR_W + 1, BAR_H + 1), Vector2(-1, BAR_H + 1)])
		bg.color = Color(0.08, 0.05, 0.04, 0.9)
		bar.add_child(bg)
		var fill := Polygon2D.new()
		fill.name = "Fill"
		fill.color = Color(0.9, 0.25, 0.2)
		bar.add_child(fill)
		marker.add_child(bar)
	var threshold := GameManager.city_system.get_siege_threshold(city)
	var frac := clampf(city.siege_turns / float(maxi(1, threshold)), 0.0, 1.0)
	var w := BAR_W * frac
	var fill_node: Polygon2D = bar.get_node("Fill")
	if w <= 0.0:
		fill_node.polygon = PackedVector2Array()
	else:
		fill_node.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(w, 0), Vector2(w, BAR_H), Vector2(0, BAR_H)])

func _on_building_completed(city_id: StringName, building_id: StringName) -> void:
	_invalidate_city_action_cache()
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"build_complete")
		var building: BuildingData = DataManager.get_building(building_id)
		var bname: String = building.display_name if building else str(building_id)
		_show_notification(bname + " completed in " + city.get_display_name())
		var hud: Control = $UILayer/HUD
		if hud.has_method("_update_resource_display"):
			hud._update_resource_display()
	# Defer heavy visual work during AI turns
	if TurnManager.is_player_turn:
		_update_city_glow_states()
		_create_building_tile_markers()
		_fog_dirty = true

func _on_building_demolished(city_id: StringName, _building_id: StringName) -> void:
	_invalidate_city_action_cache()
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"demolish")
		_show_notification("Building demolished in " + city.get_display_name())
		var hud: Control = $UILayer/HUD
		if hud.has_method("_update_resource_display"):
			hud._update_resource_display()
	_city_markers_dirty = true
	if TurnManager.is_player_turn:
		_refresh_city_markers()

func _on_battle_resolved_sfx(_winner_faction: StringName, hex_pos: Vector2i) -> void:
	if _is_tile_visible(hex_pos):
		AudioManager.play_sfx(&"battle_hit")

func _on_unit_recruited(city_id: StringName, unit_data_id: StringName, _army_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"recruit_start")
		var unit_data: UnitData = DataManager.get_unit(unit_data_id)
		var uname: String = unit_data.display_name if unit_data else str(unit_data_id)
		_show_notification(uname + " recruited in " + city.get_display_name())
	# During AI turns, skip the marker rebuild — player turn start calls
	# _create_army_markers(), matching the deferral pattern of the
	# neighboring handlers (_on_army_moved / _on_region_ownership_changed).
	if not TurnManager.is_player_turn:
		return
	_create_army_markers()

func _show_notification(text: String) -> void:
	var notif_label: Label = $UILayer/HUD/NotificationLabel
	if notif_label:
		notif_label.text = text
		notif_label.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_interval(2.0)
		tween.tween_property(notif_label, "modulate:a", 0.0, 0.5)

# ── Battle Report ─────────────────────────────────────────────

func _show_battle_report(report: Dictionary) -> void:
	if _battle_report_panel:
		_battle_report_panel.queue_free()

	_battle_report_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.2, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	_battle_report_panel.add_theme_stylebox_override("panel", style)

	_battle_report_panel.anchors_preset = Control.PRESET_CENTER
	_battle_report_panel.anchor_left = 0.5
	_battle_report_panel.anchor_top = 0.5
	_battle_report_panel.anchor_right = 0.5
	_battle_report_panel.anchor_bottom = 0.5
	_battle_report_panel.offset_left = -220
	_battle_report_panel.offset_top = -200
	_battle_report_panel.offset_right = 220
	_battle_report_panel.offset_bottom = 200
	_battle_report_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_report_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_battle_report_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "BATTLE REPORT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep)

	# Attacker section
	var atk_faction := DataManager.get_faction(report.atk_faction)
	var atk_header := Label.new()
	atk_header.text = "ATTACKER: " + (atk_faction.display_name if atk_faction else str(report.atk_faction))
	atk_header.add_theme_font_size_override("font_size", 14)
	atk_header.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
	vbox.add_child(atk_header)

	var atk_snapshot: Array = report.atk_snapshot
	var atk_hp_after: Dictionary = report.atk_hp_after
	for i in atk_snapshot.size():
		var snap: Dictionary = atk_snapshot[i]
		var unit_label := Label.new()
		unit_label.add_theme_font_size_override("font_size", 12)
		if atk_hp_after.has(i):
			unit_label.text = "  %s: %d -> %d HP" % [snap.name, snap.hp_before, atk_hp_after[i]]
			unit_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		else:
			unit_label.text = "  %s: %d -> KILLED" % [snap.name, snap.hp_before]
			unit_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		vbox.add_child(unit_label)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.3))
	vbox.add_child(sep2)

	# Defender section
	var def_faction := DataManager.get_faction(report.def_faction)
	var def_header := Label.new()
	def_header.text = "DEFENDER: " + (def_faction.display_name if def_faction else str(report.def_faction))
	def_header.add_theme_font_size_override("font_size", 14)
	def_header.add_theme_color_override("font_color", Color(0.35, 0.4, 0.85))
	vbox.add_child(def_header)

	var def_snapshot: Array = report.def_snapshot
	var def_hp_after: Dictionary = report.def_hp_after
	for i in def_snapshot.size():
		var snap: Dictionary = def_snapshot[i]
		var unit_label := Label.new()
		unit_label.add_theme_font_size_override("font_size", 12)
		if def_hp_after.has(i):
			unit_label.text = "  %s: %d -> %d HP" % [snap.name, snap.hp_before, def_hp_after[i]]
			unit_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
		else:
			unit_label.text = "  %s: %d -> KILLED" % [snap.name, snap.hp_before]
			unit_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		vbox.add_child(unit_label)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep3)

	# Winner
	var winner_label := Label.new()
	winner_label.add_theme_font_size_override("font_size", 16)
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if report.atk_alive and not report.def_alive:
		winner_label.text = "ATTACKER VICTORY"
		winner_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
	elif report.def_alive and not report.atk_alive:
		winner_label.text = "DEFENDER VICTORY"
		winner_label.add_theme_color_override("font_color", Color(0.35, 0.4, 0.85))
	elif not report.atk_alive and not report.def_alive:
		winner_label.text = "MUTUAL DESTRUCTION"
		winner_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))
	else:
		winner_label.text = "STALEMATE"
		winner_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	vbox.add_child(winner_label)

	# Spoils of war (loot + captives)
	var loot_gold: int = report.get("loot_gold", 0)
	var loot_iron: int = report.get("loot_iron", 0)
	var captives_gained: int = report.get("captives", 0)
	if loot_gold > 0 or loot_iron > 0 or captives_gained > 0:
		var spoils_label := Label.new()
		spoils_label.add_theme_font_size_override("font_size", 12)
		spoils_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
		spoils_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var spoils_parts: Array[String] = []
		if loot_gold > 0:
			spoils_parts.append("+%d Gold" % loot_gold)
		if loot_iron > 0:
			spoils_parts.append("+%d Iron" % loot_iron)
		if captives_gained > 0:
			spoils_parts.append("+%d Captives" % captives_gained)
		spoils_label.text = "Spoils: " + "  ".join(spoils_parts)
		vbox.add_child(spoils_label)

	# Continue button
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(120, 36)
	btn.pressed.connect(_on_battle_report_continue)
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_child(btn)
	vbox.add_child(btn_container)

	$UILayer/HUD.add_child(_battle_report_panel)

func _on_battle_report_continue() -> void:
	if _battle_report_panel:
		_battle_report_panel.queue_free()
		_battle_report_panel = null

# ── Fog of War ────────────────────────────────────────────────

const FOG_SCOUT_RADIUS := 2

func _create_cloud_shadows() -> void:
	var shader := load("res://assets/shaders/cloud_shadows.gdshader")
	if shader == null:
		return
	var map_w := HexMapData.MAP_WIDTH * HEX_H_SPACING + HEX_H_SPACING
	var map_h := HexMapData.MAP_HEIGHT * HEX_V_SPACING + HEX_V_SPACING
	_cloud_shadow_node = ColorRect.new()
	_cloud_shadow_node.position = Vector2(-HEX_H_SPACING, -HEX_V_SPACING)
	_cloud_shadow_node.size = Vector2(map_w + HEX_H_SPACING * 2, map_h + HEX_V_SPACING * 2)
	_cloud_shadow_node.z_index = 1
	_cloud_shadow_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cloud_shadow_material = ShaderMaterial.new()
	_cloud_shadow_material.shader = shader
	_cloud_shadow_material.set_shader_parameter("map_size", Vector2(map_w + HEX_H_SPACING * 2, map_h + HEX_V_SPACING * 2))
	_cloud_shadow_material.set_shader_parameter("shadow_strength", 0.18)
	_cloud_shadow_material.set_shader_parameter("cloud_scale", 0.0005)
	_cloud_shadow_material.set_shader_parameter("time_val", 0.0)
	_cloud_shadow_node.material = _cloud_shadow_material
	$OverlayLayer.add_child(_cloud_shadow_node)

func _create_fog_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS)
	_fog_draw_node = _FogDrawNode.new()
	_fog_draw_node.z_index = 1
	for coord in hex_map.tiles:
		var elevation: float = _hex_elevations.get(coord, 0.0)
		var pos := _hex_to_pixel(coord)
		pos.y -= elevation
		var world_poly := PackedVector2Array()
		for p in hex_points:
			world_poly.append(p + pos)
		_fog_draw_node.tile_polys[coord] = world_poly
		_fog_draw_node.tile_alphas[coord] = 0.75
	_fog_draw_node.build_geometry()
	fog_overlay_node.add_child(_fog_draw_node)
	_fog_dirty = true

func _update_trade_routes() -> void:
	# Remove old draw node and caravans
	if _trade_route_draw_node:
		_trade_route_draw_node.queue_free()
		_trade_route_draw_node = null
	for caravan in _trade_caravans:
		if is_instance_valid(caravan):
			caravan.queue_free()
	_trade_caravans.clear()
	_trade_route_data.clear()

	var diplo: DiplomacySystem = GameManager.diplomacy_system
	if diplo == null:
		return
	var routes := diplo.get_active_trade_routes()
	if routes.is_empty():
		return

	_trade_route_draw_node = _TradeRouteDrawNode.new()
	_trade_route_draw_node.z_index = 1
	var player_id := GameManager.state.player_faction_id

	for route in routes:
		var hex_path := DiplomacySystem.get_trade_route_hex_path(route.city_a_hex, route.city_b_hex)
		if hex_path.size() < 2:
			continue
		var pixel_path := PackedVector2Array()
		var visible_any := false
		for coord in hex_path:
			var elevation: float = _hex_elevations.get(coord, 0.0)
			var px := _hex_to_pixel(coord)
			px.y -= elevation
			pixel_path.append(px)
			if _is_tile_visible(coord) or GameManager.explored_tiles.has(coord):
				visible_any = true
		if not visible_any:
			continue
		# Relation tint: blue = your route, green = an ally's, white = neutral,
		# red = enemy trade (a tempting plunder target)
		var tint := Color(0.92, 0.92, 0.92, 0.75)
		if route.faction_a == player_id or route.faction_b == player_id:
			tint = Color(0.45, 0.7, 1.0, 0.85)
		elif GameManager.get_relation(player_id, route.faction_a) == Enums.FactionRelation.ALLIED \
				or GameManager.get_relation(player_id, route.faction_b) == Enums.FactionRelation.ALLIED:
			tint = Color(0.35, 0.9, 0.4, 0.85)
		elif GameManager.get_relation(player_id, route.faction_a) == Enums.FactionRelation.WAR \
				or GameManager.get_relation(player_id, route.faction_b) == Enums.FactionRelation.WAR:
			tint = Color(0.95, 0.3, 0.25, 0.85)
		_trade_route_draw_node.routes.append({points = pixel_path, color = tint, faction_a = route.faction_a, faction_b = route.faction_b})
		_trade_route_data.append({pixel_path = pixel_path, progress = randf()})

		# Rolling cart, tinted like its route
		var caravan := _CaravanDrawNode.new()
		caravan.tint = Color(tint.r, tint.g, tint.b)
		caravan.z_index = 2
		$OverlayLayer.add_child(caravan)
		_trade_caravans.append(caravan)

	$OverlayLayer.add_child(_trade_route_draw_node)
	# Move trade routes below fog overlay
	$OverlayLayer.move_child(_trade_route_draw_node, fog_overlay_node.get_index())

func _process_trade_caravans(delta: float) -> void:
	for i in _trade_caravans.size():
		if i >= _trade_route_data.size():
			break
		var caravan := _trade_caravans[i]
		if not is_instance_valid(caravan):
			continue
		var data: Dictionary = _trade_route_data[i]
		var pixel_path: PackedVector2Array = data.pixel_path
		if pixel_path.size() < 2:
			caravan.visible = false
			continue
		# Advance progress (loop back and forth)
		var speed := 0.8 * delta # ~1 hex per 1.25s (slower caravan movement)
		var total_len: float = data.get("cached_total_len", 0.0)
		if total_len == 0.0:
			for j in pixel_path.size() - 1:
				total_len += pixel_path[j].distance_to(pixel_path[j + 1])
			data["cached_total_len"] = total_len
		if total_len < 1.0:
			caravan.visible = false
			continue
		data.progress = fmod(data.progress + speed / total_len * HEX_H_SPACING, 2.0)
		var t: float = data.progress
		if t > 1.0:
			t = 2.0 - t # Bounce back
		# Find position along path at t
		var target_dist := t * total_len
		var accumulated := 0.0
		var pos := pixel_path[0]
		var seg_dir := Vector2.RIGHT
		for j in pixel_path.size() - 1:
			var seg_len := pixel_path[j].distance_to(pixel_path[j + 1])
			if accumulated + seg_len >= target_dist:
				var seg_t := (target_dist - accumulated) / seg_len if seg_len > 0 else 0.0
				pos = pixel_path[j].lerp(pixel_path[j + 1], seg_t)
				if seg_len > 0.01:
					seg_dir = (pixel_path[j + 1] - pixel_path[j]) / seg_len
				break
			accumulated += seg_len
		caravan.position = pos
		# Point the (top-down) cart along its direction of travel — reversed on
		# the return leg of the bounce
		if data.progress > 1.0:
			seg_dir = -seg_dir
		if caravan.heading != seg_dir.angle():
			caravan.heading = seg_dir.angle()
			caravan.queue_redraw()
		# Check fog visibility at caravan position
		var caravan_hex := _pixel_to_hex(pos)
		caravan.visible = _is_tile_visible(caravan_hex) or GameManager.explored_tiles.has(caravan_hex)

func _update_bounty_hover(hex_coord: Vector2i) -> void:
	var map = GameManager.state.hex_map
	var tile = map.get_tile(hex_coord) if map else null
	var has_content: bool = tile != null and (tile.bounty_id != &"" or tile.special_id != &"" or tile.landmark_id != &"") and GameManager.explored_tiles.has(hex_coord)
	if not has_content:
		if _bounty_tooltip:
			_bounty_tooltip.visible = false
		return
	if _bounty_tooltip == null:
		_bounty_tooltip = PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
		style.border_color = Color(0.55, 0.42, 0.2, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(8)
		_bounty_tooltip.add_theme_stylebox_override("panel", style)
		var lbl := Label.new()
		lbl.name = "Text"
		lbl.add_theme_font_size_override("font_size", 12)
		_bounty_tooltip.add_child(lbl)
		$UILayer.add_child(_bounty_tooltip)
	if tile.landmark_id != &"":
		# Landmark — takes precedence over a special/bounty on the same tile
		# (map-gen never stacks these, but the branch order documents intent).
		var ldef: Dictionary = LandmarkSystem.LANDMARK_TYPES[tile.landmark_id]
		var lowner_id: StringName = GameManager.state.get_region_owner(tile.region_id)
		var lowner_txt := "Unowned region"
		if lowner_id != &"":
			var lofd: FactionData = DataManager.get_faction(lowner_id)
			lowner_txt = "Region: " + (lofd.display_name if lofd else String(lowner_id))
		var lbuilding_txt := "Built"
		if not LandmarkSystem.region_has_landmark_building(tile.region_id):
			var lbd: BuildingData = DataManager.get_building(ldef.building_id)
			lbuilding_txt = "Requires %s (build in a city of this region)" % (lbd.display_name if lbd else String(ldef.building_id))
		_bounty_tooltip.get_node("Text").text = "%s (Landmark)\n%s\n%s\n%s" % [ldef.name, LandmarkSystem.describe(tile.landmark_id), lowner_txt, lbuilding_txt]
	elif tile.special_id != &"":
		# Special deposit — takes precedence over a bounty on the same tile
		# (map-gen never stacks the two, but the branch order documents intent).
		var sdef: Dictionary = SpecialResourceSystem.SPECIAL_TYPES[tile.special_id]
		var owner_id: StringName = GameManager.state.get_region_owner(tile.region_id)
		var owner_txt := "Unowned region"
		if owner_id != &"":
			var ofd: FactionData = DataManager.get_faction(owner_id)
			owner_txt = "Region: " + (ofd.display_name if ofd else String(owner_id))
		var extract_txt := "Extractor built" if SpecialResourceSystem.region_has_extractor(tile.region_id) else "Requires %s (build in a city of this region)" % DataManager.get_building(sdef.extractor_id).display_name
		var lease_txt := ""
		if owner_id != &"":
			var lease := SpecialResourceSystem.lease_for_special(owner_id, tile.special_id)
			if lease:
				var lfd: FactionData = DataManager.get_faction(lease.faction_b)
				lease_txt = "\nLeased to %s (%d turns)" % [lfd.display_name if lfd else String(lease.faction_b), lease.turns_remaining]
		_bounty_tooltip.get_node("Text").text = "%s (Special)\n%s\n%s\n%s%s" % [sdef.name, SpecialResourceSystem.describe(tile.special_id), owner_txt, extract_txt, lease_txt]
	else:
		var def: Dictionary = BountySystem.BOUNTY_TYPES[tile.bounty_id]
		var claimant := BountySystem.claimant_for(hex_coord)
		var claim_text := "Unclaimed — settle within %d tiles" % BountySystem.CLAIM_RADIUS
		if claimant != &"":
			var c: CityState = GameManager.state.cities.get(claimant)
			claim_text = "Claimed by " + (c.get_display_name() if c else String(claimant))
		_bounty_tooltip.get_node("Text").text = "%s\n%s\n%s" % [def.name, BountySystem.describe(tile.bounty_id), claim_text]
	_bounty_tooltip.position = get_viewport().get_mouse_position() + Vector2(15, -30)
	_bounty_tooltip.visible = true

func _update_trade_route_hover(world_pos: Vector2) -> void:
	if _trade_route_draw_node == null or not _trade_route_draw_node.is_inside_tree():
		if _trade_route_tooltip and _trade_route_tooltip.visible:
			_trade_route_tooltip.visible = false
		return
	var hover_dist := 18.0  # Max pixel distance to count as hovering
	var best_idx := -1
	var best_d := hover_dist
	for i in _trade_route_draw_node.routes.size():
		var pts: PackedVector2Array = _trade_route_draw_node.routes[i].points
		for j in pts.size() - 1:
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[j + 1]
			var seg := b - a
			var seg_len := seg.length()
			if seg_len < 0.1:
				continue
			var t := clampf((world_pos - a).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
			var closest := a + seg * t
			var d := world_pos.distance_to(closest)
			if d < best_d:
				best_d = d
				best_idx = i
	if best_idx >= 0:
		var route_info: Dictionary = _trade_route_draw_node.routes[best_idx]
		var fa: StringName = route_info.get("faction_a", &"")
		var fb: StringName = route_info.get("faction_b", &"")
		var fa_data = DataManager.get_faction(fa)
		var fb_data = DataManager.get_faction(fb)
		var name_a: String = fa_data.display_name if fa_data else str(fa)
		var name_b: String = fb_data.display_name if fb_data else str(fb)
		var tip_text := "%s - %s" % [name_a, name_b]
		# Show total traded resources (combined, not in/out)
		var diplo: DiplomacySystem = GameManager.diplomacy_system
		if diplo:
			for tid in GameManager.state.diplomacy_state.treaties:
				var t: TreatyInstance = GameManager.state.diplomacy_state.treaties[tid]
				if (t.faction_a == fa and t.faction_b == fb) or (t.faction_a == fb and t.faction_b == fa):
					if t.treaty_type == Enums.TreatyType.TRADE_DEAL:
						var give_res: int = t.terms.get("give_resource", 0)
						var recv_res: int = t.terms.get("receive_resource", 0)
						var give_amt: int = t.terms.get("give_amount", 0)
						var recv_amt: int = t.terms.get("receive_amount", 0)
						if give_res == recv_res:
							tip_text += "\nTrading %d %s" % [give_amt + recv_amt, _res_name(give_res)]
						else:
							tip_text += "\nTrading %d %s, %d %s" % [give_amt, _res_name(give_res), recv_amt, _res_name(recv_res)]
					elif t.treaty_type == Enums.TreatyType.TRADE_RELATIONS:
						var res_a: int = t.terms.get("resource_a", 0)
						var res_b: int = t.terms.get("resource_b", 0)
						var turns_active: int = t.terms.get("turns_active", 0)
						var share_pct := diplo.get_trade_relations_share(turns_active) / 100.0
						var inc_a := diplo.get_faction_resource_income(t.faction_a, res_a)
						var inc_b := diplo.get_faction_resource_income(t.faction_b, res_b)
						var amt_to_b := maxi(1, int(float(inc_a) * share_pct))
						var amt_to_a := maxi(1, int(float(inc_b) * share_pct))
						if res_a == res_b:
							tip_text += "\nSharing %d %s" % [amt_to_b + amt_to_a, _res_name(res_a)]
						else:
							tip_text += "\nSharing %d %s, %d %s" % [amt_to_b, _res_name(res_a), amt_to_a, _res_name(res_b)]
					break
		if _trade_route_tooltip == null:
			var panel := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.11, 0.14, 0.88)
			style.border_color = Color(0.45, 0.42, 0.35, 0.7)
			style.set_border_width_all(1)
			style.set_corner_radius_all(3)
			style.content_margin_left = 6
			style.content_margin_right = 6
			style.content_margin_top = 3
			style.content_margin_bottom = 3
			panel.add_theme_stylebox_override("panel", style)
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
			panel.add_child(lbl)
			panel.name = "TradeTooltipPanel"
			$UILayer.add_child(panel)
			_trade_route_tooltip = panel
		_trade_route_tooltip.get_child(0).text = tip_text
		_trade_route_tooltip.position = get_viewport().get_mouse_position() + Vector2(15, -30)
		_trade_route_tooltip.visible = true
	else:
		if _trade_route_tooltip and _trade_route_tooltip.visible:
			_trade_route_tooltip.visible = false

var _visible_tile_cache: Dictionary = {}  # coord -> bool, rebuilt per fog update

func _rebuild_visible_tile_cache() -> void:
	_visible_tile_cache.clear()
	if not _fog_of_war_enabled:
		return
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var player_id := GameManager.state.player_faction_id
	var player_fs: FactionState = GameManager.state.faction_states.get(player_id)

	# Vision sharing: allies only by default — mere friendliness no longer
	# reveals whole empires. Others require an explicit Share Vision treaty.
	var allied_factions: Dictionary = {}
	for faction_id in DataManager.factions:
		if faction_id == player_id:
			continue
		if GameManager.diplomacy_system.has_shared_vision(player_id, faction_id):
			allied_factions[faction_id] = true

	# Mark all player-owned and ally-owned tiles visible
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.owner_faction == player_id:
			_visible_tile_cache[coord] = true
		elif tile.owner_faction != &"" and allied_factions.has(tile.owner_faction):
			_visible_tile_cache[coord] = true

	# BFS from player cities (radius 2) — O(cities * radius^2)
	const SETTLEMENT_LOS_BONUS := 2
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id != player_id:
			continue
		_mark_visible_bfs(city.hex_pos, SETTLEMENT_LOS_BONUS)

	# BFS from player armies (scout radius) — O(player_armies * radius^2)
	for army: ArmyState in GameManager.get_all_faction_armies(player_id):
		var sr := FOG_SCOUT_RADIUS
		if army.commander:
			sr += CommanderSystem.get_scouting_bonus(army.commander)
		_mark_visible_bfs(army.hex_pos, sr)

func _mark_visible_bfs(center: Vector2i, radius: int) -> void:
	if radius <= 0:
		_visible_tile_cache[center] = true
		return
	# BFS outward from center up to radius (hex distance)
	var visited: Dictionary = {center: true}
	_visible_tile_cache[center] = true
	var frontier: Array[Vector2i] = [center]
	for _r in radius:
		var next_frontier: Array[Vector2i] = []
		for coord in frontier:
			for n in HexHelper.get_neighbors(coord):
				if visited.has(n):
					continue
				if not HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
					continue
				visited[n] = true
				_visible_tile_cache[n] = true
				next_frontier.append(n)
		frontier = next_frontier

func _is_tile_visible(coord: Vector2i) -> bool:
	if not _fog_of_war_enabled:
		return true
	return _visible_tile_cache.get(coord, false)

func _update_fog_of_war() -> void:
	_rebuild_visible_tile_cache()

	if _fog_draw_node:
		var changed := false
		var fog_enabled := _fog_of_war_enabled
		var alphas: Dictionary = _fog_draw_node.tile_alphas
		var vis_cache: Dictionary = _visible_tile_cache
		for coord in alphas:
			var new_alpha: float
			if not fog_enabled or vis_cache.has(coord):
				GameManager.explored_tiles[coord] = true
				new_alpha = 0.0
			elif GameManager.explored_tiles.has(coord):
				new_alpha = 0.45
			else:
				new_alpha = 0.75
			if alphas[coord] != new_alpha:
				_fog_draw_node.set_tile_alpha(coord, new_alpha)
				changed = true
		if changed:
			_fog_draw_node.queue_redraw()
			_minimap_fog_dirty = true

	var player_id := GameManager.state.player_faction_id

	# Show/hide army markers — enemy armies only visible in current LOS
	for army_id in _army_markers:
		var army: ArmyState = GameManager.state.armies.get(army_id)
		var marker: Node2D = _army_markers[army_id]
		if army == null:
			continue
		if army.faction_id == player_id:
			marker.visible = true
		else:
			marker.visible = bool(_visible_tile_cache.get(army.hex_pos, false)) if _fog_of_war_enabled else true

	# City markers
	for city_id in _city_markers:
		var city: CityState = GameManager.state.cities.get(city_id)
		var marker: Node2D = _city_markers[city_id]
		if city == null:
			continue
		if city.faction_id == player_id:
			marker.visible = true
			marker.modulate = Color.WHITE
		else:
			var in_los: bool = bool(_visible_tile_cache.get(city.hex_pos, false)) if _fog_of_war_enabled else true
			var explored := GameManager.explored_tiles.has(city.hex_pos)
			if in_los:
				marker.visible = true
				marker.modulate = Color.WHITE
			elif explored:
				marker.visible = true
				marker.modulate = Color(0.5, 0.5, 0.5, 0.6)
			else:
				marker.visible = false

	# Building tile markers (expansion dots) — follow same rules as city markers
	for bmarker in _building_tile_markers:
		if not is_instance_valid(bmarker):
			continue
		var bfaction: StringName = bmarker.get_meta("faction_id", &"")
		if bfaction == player_id:
			bmarker.visible = true
			bmarker.modulate = Color.WHITE
		else:
			var bhex: Vector2i = bmarker.get_meta("hex_pos", Vector2i(-1, -1))
			var in_los: bool = bool(_visible_tile_cache.get(bhex, false)) if _fog_of_war_enabled else true
			var explored := GameManager.explored_tiles.has(bhex)
			if in_los:
				bmarker.visible = true
				bmarker.modulate = Color.WHITE
			elif explored:
				bmarker.visible = true
				bmarker.modulate = Color(0.5, 0.5, 0.5, 0.6)
			else:
				bmarker.visible = false

	# Building paths follow the same fog rules as the building they lead to —
	# a road must never betray an unspotted city or building
	if is_instance_valid(_building_paths_node):
		for pline in _building_paths_node.get_children():
			var pfaction: StringName = pline.get_meta("faction_id", &"")
			if pfaction == player_id:
				pline.visible = true
				continue
			var phex: Vector2i = pline.get_meta("hex_pos", Vector2i(-1, -1))
			var p_in_los: bool = bool(_visible_tile_cache.get(phex, false)) if _fog_of_war_enabled else true
			var p_explored := GameManager.explored_tiles.has(phex)
			pline.visible = p_in_los or p_explored
			pline.modulate = Color.WHITE if p_in_los else Color(0.5, 0.5, 0.5, 0.6)

	# Show/hide elderbeast markers — only in current LOS
	for beast_id in _elderbeast_markers:
		var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
		var marker: Node2D = _elderbeast_markers[beast_id]
		if beast == null:
			continue
		if beast.faction_id == player_id:
			marker.visible = true
		else:
			marker.visible = bool(_visible_tile_cache.get(beast.hex_pos, false)) if _fog_of_war_enabled else true

	# Bounty resource markers — visible once the tile has been explored
	_refresh_bounty_marker_visibility()

	# Track encountered factions from visible tiles, cities, and armies
	_update_encountered_factions(player_id)

func _update_encountered_factions(player_id: StringName) -> void:
	var enc := GameManager.state.encountered_factions
	# Skip if all playable factions already encountered
	if enc.size() >= GameManager.state.faction_states.size() - 1:
		return
	# Check visible cities (cheap — small list, high hit rate)
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == player_id or city.faction_id == &"" or city.faction_id == &"independent":
			continue
		if enc.has(city.faction_id):
			continue
		if _visible_tile_cache.get(city.hex_pos, false) or GameManager.explored_tiles.has(city.hex_pos):
			enc[city.faction_id] = true
	# Check visible armies (only for un-encountered factions)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id or army.faction_id == &"":
			continue
		if enc.has(army.faction_id):
			continue
		if _visible_tile_cache.get(army.hex_pos, false):
			enc[army.faction_id] = true
	# Note: Diplomatic relations are NOT used for discovery because _init_diplomacy
	# pre-populates relations for all faction pairs. Discovery happens through
	# visual contact (tiles, cities, armies) and diplomatic events (standing changes).

# ── Settlement Placement Mode ─────────────────────────────────

func _on_settlement_placement_requested(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	_settlement_placement_mode = true
	_last_settlement_preview_hex = Vector2i(-9999, -9999)
	_settlement_parent_city_id = city_id
	_close_city_panel()
	_deselect_all()

	# Get valid tiles for settlement in this city's territory within the region
	_settlement_valid_tiles = GameManager.city_system.get_valid_settlement_tiles(
		city.faction_id, city.region_id, city.city_id)

	# Pre-calculate resource values for color gradient
	var resource_values: Dictionary = {}
	var min_val := 999
	var max_val := 0
	for coord in _settlement_valid_tiles:
		var income := GameManager.city_system.calculate_settlement_income_preview(coord)
		var total := 0
		for res in income:
			total += income[res]
		resource_values[coord] = total
		min_val = mini(min_val, total)
		max_val = maxi(max_val, total)

	# Show overlay on valid tiles with resource-based gradient (batched)
	var hex_poly := _make_hex_polygon(HEX_RADIUS * 0.88)
	var entries: Array = []
	for coord in _settlement_valid_tiles:
		var pos := _hex_to_pixel(coord)
		var world_poly := PackedVector2Array()
		for p in hex_poly:
			world_poly.append(p + pos)
		var val: int = resource_values.get(coord, 0)
		var t := 0.5
		if max_val > min_val:
			t = float(val - min_val) / float(max_val - min_val)
		entries.append([world_poly, Color(0.8 * (1.0 - t), 0.8 * t, 0.1, 0.35)])
	var draw_node := _MultiColorOverlayDrawNode.new()
	draw_node.entries = entries
	reachable_overlay.add_child(draw_node)
	_settlement_overlay_nodes.append(draw_node)

	_show_notification("Click a highlighted tile to found a settlement (Right-click to cancel)")

func _cancel_settlement_placement() -> void:
	_settlement_placement_mode = false
	_last_settlement_preview_hex = Vector2i(-9999, -9999)
	_settlement_parent_city_id = &""
	_settlement_valid_tiles.clear()
	for node in _settlement_overlay_nodes:
		node.queue_free()
	_settlement_overlay_nodes.clear()
	if _settlement_preview_panel:
		_settlement_preview_panel.queue_free()
		_settlement_preview_panel = null

func _handle_settlement_click(hex_coord: Vector2i) -> void:
	if not _settlement_valid_tiles.has(hex_coord):
		return

	var new_city_id := GameManager.found_settlement(
		GameManager.state.player_faction_id, hex_coord, _settlement_parent_city_id)

	if new_city_id != &"":
		_cancel_settlement_placement()
		_city_markers_dirty = true
		_refresh_city_markers()
		_show_notification("Settlement founded!")
		# Update resource display immediately (new city affects income)
		var hud: Control = $UILayer/HUD
		if hud.has_method("_update_resource_display"):
			hud._update_resource_display()

# ── Building Tile Placement Mode ──────────────────────────────

func _on_building_tile_selection_requested(city_id: StringName, building_id: StringName, valid_tiles: Array) -> void:
	_building_tile_mode = true
	_building_tile_valid.clear()
	for t in valid_tiles:
		_building_tile_valid.append(t as Vector2i)

	var hex_map := GameManager.state.hex_map
	var city: CityState = GameManager.state.cities.get(city_id)

	# Get all neighbor tiles of the city to show red/green
	var all_neighbors: Array[Vector2i] = []
	if city:
		for neighbor in HexHelper.get_neighbors(city.hex_pos):
			if HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				all_neighbors.append(neighbor)

	# Show green overlay on valid tiles, red on invalid neighbors (batched)
	var hex_poly := _make_hex_polygon(HEX_RADIUS * 0.88)
	var entries: Array = []
	for coord in all_neighbors:
		var pos := _hex_to_pixel(coord)
		var world_poly := PackedVector2Array()
		for p in hex_poly:
			world_poly.append(p + pos)
		if _building_tile_valid.has(coord):
			entries.append([world_poly, Color(0.15, 0.8, 0.25, 0.4)])
		else:
			entries.append([world_poly, Color(0.8, 0.2, 0.15, 0.3)])

	# Also highlight any valid tiles that aren't direct neighbors (e.g. upgrade tiles)
	for coord in _building_tile_valid:
		if not all_neighbors.has(coord):
			var pos := _hex_to_pixel(coord)
			var world_poly := PackedVector2Array()
			for p in hex_poly:
				world_poly.append(p + pos)
			entries.append([world_poly, Color(0.15, 0.8, 0.25, 0.4)])

	var draw_node := _MultiColorOverlayDrawNode.new()
	draw_node.entries = entries
	reachable_overlay.add_child(draw_node)
	_building_tile_overlays.append(draw_node)

	_show_notification("Click a GREEN tile to place the building (Right-click to cancel)")

func _cancel_building_tile_overlays() -> void:
	_building_tile_mode = false
	_building_tile_valid.clear()
	for node in _building_tile_overlays:
		if is_instance_valid(node):
			node.queue_free()
	_building_tile_overlays.clear()

func _show_settlement_preview(hex_coord: Vector2i) -> void:
	if _settlement_preview_panel:
		_settlement_preview_panel.queue_free()

	if not _settlement_valid_tiles.has(hex_coord):
		_settlement_preview_panel = null
		return

	var income := GameManager.city_system.calculate_settlement_income_preview(hex_coord)
	var claimable := BountySystem.bounties_claimable_at(hex_coord)
	if income.is_empty() and claimable.is_empty():
		return

	var resource_names := ["Gold", "Iron", "Technology", "Food", "Shards", "Wood"]

	_settlement_preview_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.8, 0.3, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	_settlement_preview_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var terrain_names := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
	var tile := GameManager.state.hex_map.get_tile(hex_coord)
	var terrain_name: String = terrain_names[tile.terrain] if tile and tile.terrain < terrain_names.size() else "Unknown"

	var header := Label.new()
	header.text = "Settlement at " + terrain_name
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(header)

	var total_value := 0
	for res_type in income:
		if income[res_type] > 0:
			var rname: String = resource_names[res_type] if res_type < resource_names.size() else "?"
			var rlabel := Label.new()
			rlabel.text = "  +" + str(income[res_type]) + " " + rname
			rlabel.add_theme_font_size_override("font_size", 11)
			rlabel.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
			vbox.add_child(rlabel)
			total_value += income[res_type]

	# Bounty resources this settlement would claim (special_resources_design)
	if not claimable.is_empty():
		var b_header := Label.new()
		b_header.text = "Claims resources:"
		b_header.add_theme_font_size_override("font_size", 11)
		b_header.add_theme_color_override("font_color", Color(0.72, 0.85, 0.55))
		vbox.add_child(b_header)
		for entry in claimable:
			var b_lbl := Label.new()
			b_lbl.text = "  %s (%s)" % [entry.name, BountySystem.describe(entry.id)]
			b_lbl.add_theme_font_size_override("font_size", 11)
			b_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
			vbox.add_child(b_lbl)

	var total_label := Label.new()
	total_label.text = "Total: %d resources/turn" % total_value
	total_label.add_theme_font_size_override("font_size", 11)
	total_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(total_label)

	_settlement_preview_panel.add_child(vbox)

	# Position near mouse
	var pixel_pos := _hex_to_pixel(hex_coord)
	var screen_pos := pixel_pos - camera.position + get_viewport_rect().size / 2.0
	_settlement_preview_panel.position = Vector2(screen_pos.x + 30, screen_pos.y - 40)
	$UILayer/HUD.add_child(_settlement_preview_panel)

# ── Elderbeast Selection & Movement ─────────────────────────

var _selected_beast_id: StringName = &""

func _select_elderbeast(beast_id: StringName) -> void:
	var beast: ElderbeastState = GameManager.state.elderbeasts.get(beast_id)
	if beast == null:
		return
	# Elderbeasts travel with armies — find and select the escort army
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.elderbeast_id == beast_id:
			_select_army(army_id)
			return
	# Fallback: no army attached — just show the elderbeast panel
	_deselect_all()
	_selected_beast_id = beast_id
	if _elderbeast_markers.has(beast_id):
		var marker: Node2D = _elderbeast_markers[beast_id]
		for child in marker.get_children():
			if child.name == "SelectionRing":
				child.visible = true
	var hud: Control = $UILayer/HUD
	if hud.has_method("_show_elderbeast_panel"):
		hud._show_elderbeast_panel(beast)
	_show_beast_terrain_overlay(beast)

func _show_beast_terrain_overlay(beast: ElderbeastState) -> void:
	_clear_beast_terrain_overlay()
	var hex_poly := _make_hex_polygon(HEX_RADIUS * 0.88)
	var tiles: Array[Vector2i] = [beast.hex_pos]
	for n in HexHelper.get_neighbors(beast.hex_pos):
		if HexHelper.is_valid(n, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			tiles.append(n)
	var entries: Array = []
	for tile_pos in tiles:
		var depletion_mult := beast.get_depletion_multiplier(tile_pos)
		var color := Color(0.15, 0.8, 0.25, 0.35).lerp(Color(0.8, 0.2, 0.15, 0.35), 1.0 - depletion_mult)
		var pos := _hex_to_pixel(tile_pos)
		var world_poly := PackedVector2Array()
		for p in hex_poly:
			world_poly.append(p + pos)
		entries.append([world_poly, color])
	var draw_node := _MultiColorOverlayDrawNode.new()
	draw_node.entries = entries
	reachable_overlay.add_child(draw_node)
	_beast_terrain_overlays.append(draw_node)

func _clear_beast_terrain_overlay() -> void:
	for node in _beast_terrain_overlays:
		if is_instance_valid(node):
			node.queue_free()
	_beast_terrain_overlays.clear()

# ── Minimap ──────────────────────────────────────────────────

const MINIMAP_SIZE := Vector2(360, 220)
const MINIMAP_MARGIN := Vector2(0, 0)  # flush to the screen corner (UI baseline)
var _minimap_panel: PanelContainer
var _minimap_image: TextureRect
var _minimap_view_mode := 0  # 0=terrain, 1=political, 2=culture
var _minimap_political_mode := false  # Kept for backward compatibility
var _minimap_dragging := false
var _minimap_terrain_cache: Image  # Cached terrain-only base image (no fog/armies/viewport)
var _minimap_terrain_dirty := true  # True when territory/ownership changes require terrain recache
var _minimap_fogged_cache: Image  # Terrain + fog dimming (no armies/viewport)
var _minimap_fog_dirty := true  # True when fog state changes

func _create_minimap() -> void:
	# Outer container for button + minimap. Compact gold theme keeps the
	# buttons narrow enough to fit and matches the game's UI style.
	var outer_vbox := VBoxContainer.new()
	outer_vbox.theme = GameManager.get_compact_theme()
	outer_vbox.add_theme_constant_override("separation", 2)

	# Map view mode buttons (Terrain | Political | Culture)
	var view_btn_row := HBoxContainer.new()
	view_btn_row.add_theme_constant_override("separation", 2)
	var view_names := ["Terrain", "Political", "Culture"]
	var _view_buttons: Array[Button] = []
	for i in view_names.size():
		var btn := Button.new()
		btn.text = view_names[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == _minimap_view_mode)
		btn.custom_minimum_size = Vector2(0, 24)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		if i == _minimap_view_mode:
			btn.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		var idx := i
		btn.pressed.connect(func():
			_minimap_view_mode = idx
			_minimap_political_mode = (idx == 1)
			for j in _view_buttons.size():
				_view_buttons[j].button_pressed = (j == idx)
				if j == idx:
					_view_buttons[j].add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
				else:
					_view_buttons[j].remove_theme_color_override("font_color")
			_minimap_terrain_dirty = true
			_update_minimap()
			_update_political_overlay()
		)
		_view_buttons.append(btn)
		view_btn_row.add_child(btn)
	outer_vbox.add_child(view_btn_row)

	# Select Next Army / Next City buttons
	var cycle_row := HBoxContainer.new()
	cycle_row.add_theme_constant_override("separation", 4)
	var next_army_btn := Button.new()
	next_army_btn.text = "Next Army"
	next_army_btn.custom_minimum_size = Vector2(0, 24)
	next_army_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_army_btn.add_theme_font_size_override("font_size", 11)
	next_army_btn.pressed.connect(_cycle_player_armies)
	cycle_row.add_child(next_army_btn)
	var next_city_btn := Button.new()
	next_city_btn.text = "Next City"
	next_city_btn.custom_minimum_size = Vector2(0, 24)
	next_city_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_city_btn.add_theme_font_size_override("font_size", 11)
	next_city_btn.pressed.connect(_cycle_player_cities)
	cycle_row.add_child(next_city_btn)
	outer_vbox.add_child(cycle_row)

	_minimap_panel = PanelContainer.new()
	_minimap_panel.custom_minimum_size = MINIMAP_SIZE + Vector2(8, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.35, 0.25, 0.7)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	_minimap_panel.add_theme_stylebox_override("panel", style)

	_minimap_image = TextureRect.new()
	_minimap_image.custom_minimum_size = MINIMAP_SIZE
	_minimap_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# The generated map image is MAP_WIDTH*4 x MAP_HEIGHT*4 px (e.g. 468x312
	# for a 117x78 map) — well past the intended 360x220 display size. With
	# the default EXPAND_KEEP_SIZE, TextureRect's minimum size tracks the raw
	# texture instead of custom_minimum_size, so the panel/button column above
	# it ballooned to fit the full-res image (mostly empty/fogged) rather than
	# the compact minimap box. IGNORE_SIZE makes custom_minimum_size win, and
	# stretch_mode scales the big source image down to actually fill the box.
	_minimap_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap_panel.add_child(_minimap_image)
	outer_vbox.add_child(_minimap_panel)

	# Position in bottom-right of screen with safe margins. Grow toward the
	# top-left so oversized content can never spill off-screen.
	outer_vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	outer_vbox.anchor_left = 1.0
	outer_vbox.anchor_top = 1.0
	outer_vbox.anchor_right = 1.0
	outer_vbox.anchor_bottom = 1.0
	var total_btn_height := 60  # Two button rows
	outer_vbox.offset_left = -MINIMAP_SIZE.x - MINIMAP_MARGIN.x - 16
	outer_vbox.offset_top = -MINIMAP_SIZE.y - MINIMAP_MARGIN.y - total_btn_height - 16
	outer_vbox.offset_right = -MINIMAP_MARGIN.x
	outer_vbox.offset_bottom = -MINIMAP_MARGIN.y
	outer_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	outer_vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Click to navigate
	_minimap_image.gui_input.connect(_on_minimap_click)

	$UILayer/HUD.add_child(outer_vbox)
	_update_minimap()

func _rebuild_minimap_terrain_cache() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var w: int = HexMapData.MAP_WIDTH
	var h: int = HexMapData.MAP_HEIGHT
	var px_w: int = w * 4
	var px_h: int = h * 4
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.07, 0.1, 1.0))

	var faction_colors: Dictionary = {}
	for fid in GameManager.state.faction_states:
		var fd := DataManager.get_faction(fid)
		faction_colors[fid] = fd.color if fd else Color(0.5, 0.5, 0.5)

	# Draw terrain/ownership (no fog — this is the base layer)
	for x in w:
		for y in h:
			var coord := Vector2i(x, y)
			var tile := hex_map.get_tile(coord)
			if tile == null:
				continue
			var color: Color
			if _minimap_view_mode == 1:
				# Political mode
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = faction_colors[tile.owner_faction].darkened(0.15)
				else:
					color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3)).darkened(0.3)
			elif _minimap_view_mode == 2:
				# Culture mode
				var cul_id: StringName = GameManager.REGION_CULTURE.get(tile.region_id, &"")
				if cul_id != &"":
					color = CULTURE_COLORS.get(cul_id, Color(0.5, 0.5, 0.5)).darkened(0.15)
				else:
					color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3)).darkened(0.3)
			else:
				# Terrain mode
				color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3))
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = color.lerp(faction_colors[tile.owner_faction], 0.15)
				color = color.darkened(0.3)
			var px := x * 4
			var py := y * 4
			img.fill_rect(Rect2i(px, py, mini(4, px_w - px), mini(4, px_h - py)), color)

	# Draw faction territory borders
	for x in w:
		for y in h:
			var coord := Vector2i(x, y)
			var my_faction: StringName = _visual_faction_owner.get(coord, &"")
			if my_faction == &"":
				continue
			var fc: Color = faction_colors.get(my_faction, Color.WHITE)
			var border_color: Color = fc.darkened(0.2) if _minimap_political_mode else fc.darkened(0.1)
			border_color.a = 0.9
			for n in HexHelper.get_neighbors(coord):
				var n_faction: StringName = _visual_faction_owner.get(n, &"")
				if n_faction != my_faction:
					var ddx: int = n.x - coord.x
					var ddy: int = n.y - coord.y
					var bx: int = coord.x * 4 + 2 + clampi(ddx, -1, 1)
					var by: int = coord.y * 4 + 2 + clampi(ddy, -1, 1)
					if bx >= 0 and bx < px_w and by >= 0 and by < px_h:
						img.set_pixel(bx, by, border_color)

	# Draw cities (static positions)
	var player_id := GameManager.state.player_faction_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var px: int = city.hex_pos.x * 4 + 2
		var py: int = city.hex_pos.y * 4 + 2
		var city_color: Color
		if city.faction_id == player_id:
			city_color = Color(0.3, 0.5, 1.0)
		elif city.faction_id == &"" or city.faction_id == &"independent" or city.faction_id == &"rebels":
			city_color = Color(0.9, 0.9, 0.9)
		else:
			var rel := GameManager.get_relation(player_id, city.faction_id)
			if rel == Enums.FactionRelation.ALLIED or rel == Enums.FactionRelation.FRIENDLY:
				city_color = Color(0.2, 0.85, 0.3)
			elif rel == Enums.FactionRelation.WAR or rel == Enums.FactionRelation.HOSTILE:
				city_color = Color(0.95, 0.2, 0.15)
			else:
				city_color = Color(0.9, 0.9, 0.9)
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, city_color)

	# Draw trade routes as subtle gold dots
	var diplo: DiplomacySystem = GameManager.diplomacy_system
	if diplo:
		var trade_routes := diplo.get_active_trade_routes()
		var route_dot_color := Color(0.85, 0.7, 0.3, 0.7)
		for route in trade_routes:
			var hex_path := DiplomacySystem.get_trade_route_hex_path(route.city_a_hex, route.city_b_hex)
			for coord in hex_path:
				var rpx: int = coord.x * 4 + 2
				var rpy: int = coord.y * 4 + 2
				if rpx >= 0 and rpx < px_w and rpy >= 0 and rpy < px_h:
					img.set_pixel(rpx, rpy, route_dot_color)

	_minimap_terrain_cache = img
	_minimap_terrain_dirty = false

func _rebuild_minimap_fogged_cache() -> void:
	if _minimap_terrain_cache == null:
		return
	var w: int = HexMapData.MAP_WIDTH
	var h: int = HexMapData.MAP_HEIGHT
	var px_w: int = w * 4
	var px_h: int = h * 4
	var img := _minimap_terrain_cache.duplicate()

	if _fog_of_war_enabled:
		var dark_color := Color(0.05, 0.04, 0.07)
		var explored_dim := 0.6
		for x in w:
			for y in h:
				var coord := Vector2i(x, y)
				var is_visible: bool = bool(_visible_tile_cache.get(coord, false))
				if is_visible:
					continue
				var is_explored: bool = bool(GameManager.explored_tiles.get(coord, false))
				var px := x * 4
				var py := y * 4
				var rw := mini(4, px_w - px)
				var rh := mini(4, px_h - py)
				if not is_explored:
					img.fill_rect(Rect2i(px, py, rw, rh), dark_color)
				else:
					# Each 4x4 tile block is a single color, so read one pixel and fill
					var c: Color = img.get_pixel(px, py).darkened(explored_dim)
					img.fill_rect(Rect2i(px, py, rw, rh), c)

	# Dim explored-but-not-visible cities
	if _fog_of_war_enabled:
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			if not bool(_visible_tile_cache.get(city.hex_pos, false)) and bool(GameManager.explored_tiles.get(city.hex_pos, false)):
				var px: int = city.hex_pos.x * 4 + 2
				var py: int = city.hex_pos.y * 4 + 2
				if px >= 0 and px < px_w and py >= 0 and py < px_h:
					var c: Color = img.get_pixel(px, py)
					img.set_pixel(px, py, c.darkened(0.4))

	_minimap_fogged_cache = img
	_minimap_fog_dirty = false

func _update_minimap() -> void:
	if _minimap_image == null:
		return
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	# Layer 1: Rebuild terrain base if ownership/political mode changed
	if _minimap_terrain_dirty or _minimap_terrain_cache == null:
		_rebuild_minimap_terrain_cache()
		_minimap_fog_dirty = true  # Terrain changed, fog layer needs rebuild too

	# Layer 2: Rebuild fogged layer if fog state changed
	if _minimap_fog_dirty or _minimap_fogged_cache == null:
		_rebuild_minimap_fogged_cache()

	var w: int = HexMapData.MAP_WIDTH
	var h: int = HexMapData.MAP_HEIGHT
	var px_w: int = w * 4
	var px_h: int = h * 4

	# Copy the fogged cache (terrain + fog dimming), then overlay dynamic elements
	var img := _minimap_fogged_cache.duplicate()
	var fog_active := _fog_of_war_enabled

	# Faction color map for army dots
	var faction_colors: Dictionary = {}
	for fid in GameManager.state.faction_states:
		var fd := DataManager.get_faction(fid)
		faction_colors[fid] = fd.color if fd else Color(0.5, 0.5, 0.5)

	# Draw armies as bright dots (only if visible)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if fog_active and not bool(_visible_tile_cache.get(army.hex_pos, false)):
			continue
		var px: int = army.hex_pos.x * 4 + 2
		var py: int = army.hex_pos.y * 4 + 2
		var a_color: Color = faction_colors.get(army.faction_id, Color.WHITE).lightened(0.4)
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, a_color)
			if px + 1 < px_w:
				img.set_pixel(px + 1, py, a_color)
			if py + 1 < px_h:
				img.set_pixel(px, py + 1, a_color)

	# Draw shards as purple dots (only if visible)
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if fog_active and not bool(_visible_tile_cache.get(shard.hex_pos, false)):
			continue
		var px: int = shard.hex_pos.x * 4 + 2
		var py: int = shard.hex_pos.y * 4 + 2
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, Color(0.7, 0.3, 0.9))

	# Cache the content image (before viewport rect) for lightweight camera-only updates
	_minimap_content_cache = img.duplicate()

	# Draw camera viewport indicator
	_draw_minimap_viewport_rect(img, px_w, px_h)
	_set_minimap_texture(img)

func _set_minimap_texture(img: Image) -> void:
	## Reuses the existing ImageTexture via update() when dimensions/format
	## match (every update after the first); creates it otherwise.
	var tex := _minimap_image.texture as ImageTexture
	if tex and tex.get_width() == img.get_width() and tex.get_height() == img.get_height() \
			and tex.get_format() == img.get_format():
		tex.update(img)
	else:
		_minimap_image.texture = ImageTexture.create_from_image(img)

func _update_minimap_viewport_only() -> void:
	# Lightweight update: only redraws the viewport rectangle using cached content
	if _minimap_content_cache == null or _minimap_image == null:
		_update_minimap()
		return
	var w: int = HexMapData.MAP_WIDTH
	var h: int = HexMapData.MAP_HEIGHT
	var px_w: int = w * 4
	var px_h: int = h * 4
	var img := _minimap_content_cache.duplicate()
	_draw_minimap_viewport_rect(img, px_w, px_h)
	_set_minimap_texture(img)

func _draw_minimap_viewport_rect(img: Image, px_w: int, px_h: int) -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_top_left := camera.position - viewport_size / 2.0
	var cam_bottom_right := camera.position + viewport_size / 2.0
	var map_pixel_w := float(HexMapData.MAP_WIDTH) * HEX_H_SPACING
	var map_pixel_h := float(HexMapData.MAP_HEIGHT) * HEX_V_SPACING
	var vp_left: int = clampi(int(cam_top_left.x / map_pixel_w * float(px_w)), 0, px_w - 1)
	var vp_top: int = clampi(int(cam_top_left.y / map_pixel_h * float(px_h)), 0, px_h - 1)
	var vp_right: int = clampi(int(cam_bottom_right.x / map_pixel_w * float(px_w)), 0, px_w - 1)
	var vp_bottom: int = clampi(int(cam_bottom_right.y / map_pixel_h * float(px_h)), 0, px_h - 1)
	var vp_color := Color(1.0, 1.0, 1.0, 0.6)
	for px in range(vp_left, vp_right + 1):
		if vp_top >= 0 and vp_top < px_h:
			img.set_pixel(px, vp_top, vp_color)
		if vp_bottom >= 0 and vp_bottom < px_h:
			img.set_pixel(px, vp_bottom, vp_color)
	for py in range(vp_top, vp_bottom + 1):
		if vp_left >= 0 and vp_left < px_w:
			img.set_pixel(vp_left, py, vp_color)
		if vp_right >= 0 and vp_right < px_w:
			img.set_pixel(vp_right, py, vp_color)

func _on_minimap_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_minimap_dragging = true
			_minimap_move_camera(event.position)
		else:
			_minimap_dragging = false
	elif event is InputEventMouseMotion and _minimap_dragging:
		_minimap_move_camera(event.position)

func _minimap_move_camera(local_pos: Vector2) -> void:
	var minimap_size := _minimap_image.size
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var map_pixel_w := float(HexMapData.MAP_WIDTH) * HEX_H_SPACING
	var map_pixel_h := float(HexMapData.MAP_HEIGHT) * HEX_V_SPACING
	var ratio_x := clampf(local_pos.x / minimap_size.x, 0.0, 1.0)
	var ratio_y := clampf(local_pos.y / minimap_size.y, 0.0, 1.0)
	camera.position = Vector2(ratio_x * map_pixel_w, ratio_y * map_pixel_h)
	camera._clamp_position()
	# Camera move changes only the viewport rectangle — army/shard/fog content
	# is unchanged, so skip duplicating the fogged cache and rescanning armies.
	_update_minimap_viewport_only()
