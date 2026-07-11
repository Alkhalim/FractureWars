extends Node2D

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]

# Hex outer radius (center to vertex) for flat-top hexes
const HEX_RADIUS := 38.0  # +20% over the original 32 — more room for tile detail and buildings
# Derived spacing
const HEX_H_SPACING := HEX_RADIUS * 1.5 # 36.0 - horizontal center-to-center
const HEX_V_SPACING := HEX_RADIUS * 1.732 # sqrt(3) * radius ≈ 41.57
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
	_create_building_tile_markers()
	_create_army_markers()
	_city_markers_dirty = false  # Initial markers just created; skip redundant rebuild

	EventBus.army_moved.connect(_on_army_moved)
	EventBus.army_destroyed.connect(_on_army_destroyed)
	EventBus.region_ownership_changed.connect(_on_region_ownership_changed)
	EventBus.battle_initiated.connect(_on_battle_initiated)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.shardfall_occurred.connect(_on_shardfall_occurred)
	EventBus.city_captured.connect(_on_city_captured)
	EventBus.siege_started.connect(_on_siege_started)
	EventBus.siege_broken.connect(_on_siege_broken)
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
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.5, Color(0.75, 0.55, 0.2, 0.9))
		draw_circle(Vector2.ZERO, 2.0, Color(0.95, 0.8, 0.4, 0.95))

class _TradeRouteDrawNode extends Node2D:
	var routes: Array = [] # Array of {points: PackedVector2Array, color: Color}
	func _draw() -> void:
		var dash_len := 6.0
		var gap_len := 4.0
		for route in routes:
			var pts: PackedVector2Array = route.points
			var col: Color = route.color
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
						draw_line(a + dir * drawn, a + dir * end, col, 2.0, true)
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

# ── Per-culture settlement art ───────────────────────────────
# Envelope: x in [-9, 9], ground y = 5, top around y = -11.

func _draw_settlement_art(marker: Node2D, culture: StringName, fc: Color) -> void:
	match culture:
		&"empire": _stl_empire(marker, fc)
		&"skulloath": _stl_skulloath(marker, fc)
		&"gladehost": _stl_gladehost(marker, fc)
		&"tainted_jade": _stl_tainted_jade(marker, fc)
		&"moonspear": _stl_moonspear(marker, fc)
		&"sunblessed": _stl_sunblessed(marker, fc)
		&"thunderswarm": _stl_thunderswarm(marker, fc)
		&"cinderguard": _stl_cinderguard(marker, fc)
		&"forsaken": _stl_forsaken(marker, fc)
		&"ivoryscar": _stl_ivoryscar(marker, fc)
		&"shardhorde": _stl_shardhorde(marker, fc)
		_: _stl_generic(marker, fc)

func _stl_body(marker: Node2D, pts: PackedVector2Array, center: Vector2, color: Color) -> void:
	_marker_poly(marker, _scaled_pts(pts, 1.16, center), _MARKER_OUTLINE)
	_marker_poly(marker, pts, color)

func _stl_empire(marker: Node2D, fc: Color) -> void:
	# Villa: stone box, shallow faction-color gable, portico columns
	_stl_body(marker, PackedVector2Array([
		Vector2(-7.5, 5), Vector2(7.5, 5), Vector2(7.5, -3), Vector2(-7.5, -3)
	]), Vector2(0, 1), _MARKER_STONE_LIGHT)
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(-8.6, -3), Vector2(8.6, -3), Vector2(0, -9.4)
	]), 1.12, Vector2(0, -5)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-8.6, -3), Vector2(8.6, -3), Vector2(0, -9.4)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-3.2, 5), Vector2(-3.2, -2.4)]), _MARKER_STONE, 1.2)
	_marker_line(marker, PackedVector2Array([Vector2(3.2, 5), Vector2(3.2, -2.4)]), _MARKER_STONE, 1.2)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.4, 5), Vector2(1.4, 5), Vector2(1.4, 0.6), Vector2(-1.4, 0.6)
	]), Color(0.14, 0.1, 0.08))

func _stl_skulloath(marker: Node2D, fc: Color) -> void:
	# Single yurt: faction dome, dark door, smoke hole
	var dome := _ellipse_arc_pts(Vector2(0, 5), 8.0, 10.5, PI, TAU, 12)
	dome.append(Vector2(8.0, 5))
	_marker_poly(marker, _scaled_pts(dome, 1.14, Vector2(0, 0)), _MARKER_OUTLINE)
	_marker_poly(marker, dome, fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0, 5), 8.0, 10.5, PI + 0.35, TAU - 0.35, 8),
		Color(0.2, 0.15, 0.12, 0.6), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.8, 5), Vector2(1.8, 5), Vector2(1.8, 0.6), Vector2(0, -0.6), Vector2(-1.8, 0.6)
	]), Color(0.12, 0.09, 0.07))
	_marker_poly(marker, _ellipse_pts(Vector2(0, -5.2), 1.2, 0.8, 8), Color(0.14, 0.11, 0.09))

func _stl_gladehost(marker: Node2D, fc: Color) -> void:
	# Moss-roofed hut against a sapling
	_marker_line(marker, PackedVector2Array([Vector2(5.6, 5), Vector2(6.4, -6.4)]),
		Color(0.3, 0.23, 0.16), 1.4)
	_marker_poly(marker, _ellipse_pts(Vector2(6.6, -8.2), 3.4, 2.8, 10), fc.darkened(0.15))
	_stl_body(marker, PackedVector2Array([
		Vector2(-7, 5), Vector2(2.5, 5), Vector2(2.5, -1.5), Vector2(-7, -1.5)
	]), Vector2(-2.2, 1.8), _MARKER_STONE)
	var roof := _ellipse_arc_pts(Vector2(-2.2, -1.5), 6.2, 5.4, PI, TAU, 10)
	_marker_poly(marker, _scaled_pts(roof, 1.12, Vector2(-2.2, -1.5)), _MARKER_OUTLINE)
	_marker_poly(marker, roof, fc)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-3.6, 5), Vector2(-1.0, 5), Vector2(-1.0, 1), Vector2(-3.6, 1)
	]), Color(0.12, 0.09, 0.07))

func _stl_tainted_jade(marker: Node2D, fc: Color) -> void:
	# Thatched jungle hut on a low stone base
	_stl_body(marker, PackedVector2Array([
		Vector2(-8, 5), Vector2(8, 5), Vector2(7, 2.2), Vector2(-7, 2.2)
	]), Vector2(0, 3.6), _MARKER_STONE)
	_stl_body(marker, PackedVector2Array([
		Vector2(-5.4, 2.2), Vector2(5.4, 2.2), Vector2(5.4, -2), Vector2(-5.4, -2)
	]), Vector2(0, 0), Color(0.4, 0.32, 0.22))
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(-6.8, -2), Vector2(6.8, -2), Vector2(0, -9.8)
	]), 1.12, Vector2(0, -4.5)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-6.8, -2), Vector2(6.8, -2), Vector2(0, -9.8)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-4.4, -3.8), Vector2(4.4, -3.8)]),
		fc.darkened(0.25), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.5, 2.2), Vector2(1.5, 2.2), Vector2(1.5, -1.4), Vector2(-1.5, -1.4)
	]), Color(0.1, 0.08, 0.06))

func _stl_moonspear(marker: Node2D, fc: Color) -> void:
	# Dome hut with a tiny crescent finial
	var dome := _ellipse_arc_pts(Vector2(0, 5), 7.2, 9.4, PI, TAU, 12)
	dome.append(Vector2(7.2, 5))
	_marker_poly(marker, _scaled_pts(dome, 1.14, Vector2(0, 0.5)), _MARKER_OUTLINE)
	_marker_poly(marker, dome, fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0.6, -6.2), 1.4, 1.5, PI * 0.65, PI * 1.9, 7),
		_MARKER_GOLD, 1.1)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.7, 5), Vector2(1.7, 5), Vector2(1.7, 0.8), Vector2(0, -0.4), Vector2(-1.7, 0.8)
	]), Color(0.12, 0.1, 0.12))
	_marker_poly(marker, _ellipse_pts(Vector2(-3.4, -1.6), 0.7, 0.7, 6), Color(0.92, 0.9, 0.7, 0.9))

func _stl_sunblessed(marker: Node2D, fc: Color) -> void:
	# Adobe flat-roof house with a gold sun mark over the door
	_stl_body(marker, PackedVector2Array([
		Vector2(-7.5, 5), Vector2(7.5, 5), Vector2(7, -4.5), Vector2(-7, -4.5)
	]), Vector2(0, 0.2), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-7, -4.4), Vector2(7, -4.4)]),
		fc.darkened(0.25), 1.2)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.6, 5), Vector2(1.6, 5), Vector2(1.6, 0.4), Vector2(-1.6, 0.4)
	]), Color(0.14, 0.1, 0.08))
	_marker_poly(marker, _ellipse_pts(Vector2(0, -1.8), 1.1, 1.1, 8), _MARKER_GOLD)

func _stl_thunderswarm(marker: Node2D, fc: Color) -> void:
	# Turf-roofed longhut
	_stl_body(marker, PackedVector2Array([
		Vector2(-8.5, 5), Vector2(8.5, 5), Vector2(8.5, 0.5), Vector2(-8.5, 0.5)
	]), Vector2(0, 2.7), Color(0.35, 0.29, 0.22))
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(-9.6, 0.5), Vector2(9.6, 0.5), Vector2(0, -7.4)
	]), 1.12, Vector2(0, -2)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-9.6, 0.5), Vector2(9.6, 0.5), Vector2(0, -7.4)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-2.4, -5.4), Vector2(2.4, -5.4)]),
		fc.darkened(0.3), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.6, 5), Vector2(1.6, 5), Vector2(1.6, 1.4), Vector2(-1.6, 1.4)
	]), Color(0.12, 0.09, 0.07))

func _stl_cinderguard(marker: Node2D, fc: Color) -> void:
	# Stone cottage with ember chimney
	_stl_body(marker, PackedVector2Array([
		Vector2(-7, 5), Vector2(7, 5), Vector2(7, -2), Vector2(-7, -2)
	]), Vector2(0, 1.5), Color(0.34, 0.3, 0.28))
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(-8, -2), Vector2(8, -2), Vector2(0, -8.6)
	]), 1.12, Vector2(0, -4)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-8, -2), Vector2(8, -2), Vector2(0, -8.6)
	]), fc)
	_marker_poly(marker, PackedVector2Array([
		Vector2(3.2, -3.4), Vector2(5.2, -3.4), Vector2(5.2, -9.4), Vector2(3.2, -9.4)
	]), Color(0.28, 0.24, 0.22))
	_marker_poly(marker, _ellipse_pts(Vector2(4.2, -9.9), 1.0, 0.8, 8), Color(0.95, 0.5, 0.15, 0.95))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.5, 5), Vector2(1.5, 5), Vector2(1.5, 1), Vector2(-1.5, 1)
	]), Color(0.12, 0.09, 0.07))

func _stl_forsaken(marker: Node2D, fc: Color) -> void:
	# Leaning shack with one lit window
	_stl_body(marker, PackedVector2Array([
		Vector2(-6.5, 5), Vector2(6, 5), Vector2(7, -3.5), Vector2(-4.5, -2.5)
	]), Vector2(0, 1), Color(0.26, 0.23, 0.24))
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(-6, -2.4), Vector2(8.4, -3.6), Vector2(0.6, -8.8)
	]), 1.12, Vector2(1, -4.5)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-6, -2.4), Vector2(8.4, -3.6), Vector2(0.6, -8.8)
	]), fc.darkened(0.25))
	_marker_poly(marker, PackedVector2Array([
		Vector2(1.8, 0.4), Vector2(3.6, 0.3), Vector2(3.6, 2.1), Vector2(1.8, 2.2)
	]), Color(0.95, 0.75, 0.35, 0.85))

func _stl_ivoryscar(marker: Node2D, fc: Color) -> void:
	# Bone-frame tent: pale hide with rib supports and faction band
	_stl_body(marker, PackedVector2Array([
		Vector2(-8, 5), Vector2(8, 5), Vector2(0, -9)
	]), Vector2(0, 1), Color(0.82, 0.78, 0.66))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-5.4, 5), Vector2(5.4, 5), Vector2(4.4, 3.2), Vector2(-4.4, 3.2)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-4.6, 3.4), Vector2(0, -8.2)]),
		Color(0.62, 0.58, 0.48), 1.0)
	_marker_line(marker, PackedVector2Array([Vector2(4.6, 3.4), Vector2(0, -8.2)]),
		Color(0.62, 0.58, 0.48), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.4, 5), Vector2(1.4, 5), Vector2(0, 1.6)
	]), Color(0.12, 0.1, 0.08))

func _stl_shardhorde(marker: Node2D, fc: Color) -> void:
	# Lean-to slab against a glowing crystal
	_marker_poly(marker, _scaled_pts(PackedVector2Array([
		Vector2(1.4, 5), Vector2(5.6, 5), Vector2(3.4, -8.8)
	]), 1.14, Vector2(3.4, 0)), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(1.4, 5), Vector2(5.6, 5), Vector2(3.4, -8.8)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(3.2, 3.6), Vector2(3.5, -6.4)]),
		fc.lightened(0.35), 0.9)
	_stl_body(marker, PackedVector2Array([
		Vector2(-8.5, 5), Vector2(0.5, 5), Vector2(-6.5, -4.5)
	]), Vector2(-4.5, 2), Color(0.36, 0.32, 0.28))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-4.4, 5), Vector2(-1.6, 5), Vector2(-4.2, 1.4)
	]), Color(0.12, 0.09, 0.07))

func _stl_generic(marker: Node2D, fc: Color) -> void:
	# Neutral hamlet (previous design)
	var rear_roof := PackedVector2Array([Vector2(2, -2)])
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		rear_roof.append(Vector2(5.5, -2) + Vector2(cos(a) * 4.0, sin(a) * 4.5))
	rear_roof.append(Vector2(9.5, -2))
	rear_roof.append(Vector2(9.5, 3))
	rear_roof.append(Vector2(2, 3))
	_marker_poly(marker, _scaled_pts(rear_roof, 1.16, Vector2(5.5, 0.5)), _MARKER_OUTLINE)
	_marker_poly(marker, rear_roof, fc.darkened(0.35))
	var body := PackedVector2Array([
		Vector2(-8, 5), Vector2(-8, -2), Vector2(4, -2), Vector2(4, 5)
	])
	_marker_poly(marker, _scaled_pts(body, 1.18, Vector2(-2, 1.5)), _MARKER_OUTLINE)
	_marker_poly(marker, body, _MARKER_STONE)
	var roof := PackedVector2Array()
	for i in 11:
		var a := PI + PI * float(i) / 10.0
		roof.append(Vector2(-2, -2) + Vector2(cos(a) * 7.4, sin(a) * 6.4))
	_marker_poly(marker, _scaled_pts(roof, 1.12, Vector2(-2, -2)), _MARKER_OUTLINE)
	_marker_poly(marker, roof, fc)
	_marker_line(marker, PackedVector2Array([Vector2(-8.6, -2.4), Vector2(4.6, -2.4)]),
		_MARKER_GOLD, 1.1)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-3.6, 5), Vector2(-3.6, 0.5), Vector2(-0.4, 0.5), Vector2(-0.4, 5)
	]), Color(0.16, 0.12, 0.09))
	_marker_poly(marker, PackedVector2Array([
		Vector2(1.2, 0.2), Vector2(3.0, 0.2), Vector2(3.0, 2.0), Vector2(1.2, 2.0)
	]), Color(0.95, 0.8, 0.35, 0.9))

# ── Per-culture city art ─────────────────────────────────────
# Envelope: x in [-13, 13], ground y = 8, structures top out near y = -20
# (the universal capital crown sits at -22.5 .. -27.5).

func _draw_city_art(marker: Node2D, culture: StringName, fc: Color, is_capital: bool) -> void:
	match culture:
		&"empire": _city_empire(marker, fc, is_capital)
		&"skulloath": _city_skulloath(marker, fc, is_capital)
		&"gladehost": _city_gladehost(marker, fc, is_capital)
		&"tainted_jade": _city_tainted_jade(marker, fc, is_capital)
		&"moonspear": _city_moonspear(marker, fc, is_capital)
		&"sunblessed": _city_sunblessed(marker, fc, is_capital)
		&"thunderswarm": _city_thunderswarm(marker, fc, is_capital)
		&"cinderguard": _city_cinderguard(marker, fc, is_capital)
		&"forsaken": _city_forsaken(marker, fc, is_capital)
		&"ivoryscar": _city_ivoryscar(marker, fc, is_capital)
		&"shardhorde": _city_shardhorde(marker, fc, is_capital)
		_: _city_generic(marker, fc)

func _city_wall(marker: Node2D, top_y := -5.0) -> void:
	# Shared curtain wall with crenellation teeth + gold trim
	_marker_poly(marker, PackedVector2Array([
		Vector2(-12.6, 8), Vector2(12.6, 8), Vector2(12.6, top_y), Vector2(-12.6, top_y)
	]), _MARKER_STONE)
	for i in 4:
		var tx := [-11.2, -6.6, 6.6, 11.2][i] as float
		_marker_poly(marker, PackedVector2Array([
			Vector2(tx - 1.2, top_y), Vector2(tx + 1.2, top_y),
			Vector2(tx + 1.2, top_y - 2.4), Vector2(tx - 1.2, top_y - 2.4)
		]), _MARKER_STONE)
	_marker_line(marker, PackedVector2Array([Vector2(-12.6, top_y + 0.1), Vector2(12.6, top_y + 0.1)]),
		_MARKER_GOLD, 1.1)

func _city_gate(marker: Node2D) -> void:
	var gate_pts := PackedVector2Array([Vector2(-3, 8)])
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		gate_pts.append(Vector2(0, 2.5) + Vector2(cos(a) * 3.0, sin(a) * 3.5))
	gate_pts.append(Vector2(3, 8))
	_marker_poly(marker, gate_pts, Color(0.1, 0.07, 0.05, 0.9))

func _city_backplate(marker: Node2D, pts: PackedVector2Array, center: Vector2) -> void:
	_marker_poly(marker, _scaled_pts(pts, 1.14, center), _MARKER_OUTLINE)

func _city_empire(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Roman castrum: wall + basilica with faction-color pediment + gate columns
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -6), Vector2(6.5, -6),
		Vector2(6.5, -14), Vector2(0, -20.2), Vector2(-6.5, -14), Vector2(-6.5, -6), Vector2(-13.6, -6)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_city_wall(marker)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, -13.5), Vector2(-5, -13.5)
	]), _MARKER_STONE_LIGHT)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-6.2, -13.5), Vector2(6.2, -13.5), Vector2(0, -19.2)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-6.2, -13.4), Vector2(6.2, -13.4)]),
		_MARKER_GOLD, 1.0)
	_marker_line(marker, PackedVector2Array([Vector2(-2.6, -5.4), Vector2(-2.6, -13)]),
		_MARKER_STONE, 1.4)
	_marker_line(marker, PackedVector2Array([Vector2(2.6, -5.4), Vector2(2.6, -13)]),
		_MARKER_STONE, 1.4)
	_city_gate(marker)
	if is_capital:
		# Gold laurel wreath on the pediment
		_marker_line(marker, _ellipse_arc_pts(Vector2(0, -15.2), 2.2, 2.2, 0.6, TAU - 0.6, 10),
			_MARKER_GOLD, 1.1)

func _city_skulloath(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Khan's enclosure: palisade + yurt domes + horned totem
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -4), Vector2(6, -4),
		Vector2(5, -12), Vector2(-5, -12), Vector2(-6, -4), Vector2(-13.6, -4)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	# Palisade wall with stake lines
	_marker_poly(marker, PackedVector2Array([
		Vector2(-12.6, 8), Vector2(12.6, 8), Vector2(12.6, -3), Vector2(-12.6, -3)
	]), Color(0.36, 0.3, 0.24))
	for i in 6:
		var sx := -10.5 + 4.2 * float(i)
		_marker_line(marker, PackedVector2Array([Vector2(sx, 8), Vector2(sx, -3.6)]),
			Color(0.24, 0.19, 0.15), 1.0)
	# Side yurts
	for s in 2:
		var cx := -7.2 + 14.4 * float(s)
		_marker_poly(marker, _ellipse_arc_pts(Vector2(cx, -3), 3.6, 5.4, PI, TAU, 8), fc.darkened(0.2))
	# Great yurt (faction color dome) + dark door
	_marker_poly(marker, _ellipse_arc_pts(Vector2(0, -3), 5.8, 9.0, PI, TAU, 10), fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(0, -3), 5.8, 9.0, PI + 0.35, TAU - 0.35, 8),
		_MARKER_GOLD, 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.6, -3), Vector2(1.6, -3), Vector2(1.6, -7), Vector2(0, -8.2), Vector2(-1.6, -7)
	]), Color(0.12, 0.09, 0.07))
	# Horned totem above the great yurt
	_marker_line(marker, PackedVector2Array([Vector2(0, -12), Vector2(0, -17.5)]),
		Color(0.3, 0.24, 0.18), 1.4)
	_marker_line(marker, _ellipse_arc_pts(Vector2(-2.6, -17.2), 2.6, 3.4, -PI * 0.5, -PI * 0.05, 6),
		Color(0.85, 0.8, 0.7), 1.3)
	_marker_line(marker, _ellipse_arc_pts(Vector2(2.6, -17.2), 2.6, 3.4, -PI * 0.5, -PI * 0.95, 6),
		Color(0.85, 0.8, 0.7), 1.3)
	if is_capital:
		_marker_poly(marker, _ellipse_pts(Vector2(0, -18.2), 1.8, 1.8, 8), _MARKER_GOLD)

func _city_gladehost(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Great-tree city: trunk, faction-color canopy, platform walkway, root gate
	var canopy_c := Vector2(0, -12.5)
	_marker_poly(marker, _ellipse_pts(canopy_c, 12.2, 8.6, 16), _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-4.4, 9), Vector2(4.4, 9), Vector2(2.6, -8), Vector2(-2.6, -8)
	]), _MARKER_OUTLINE)
	# Trunk
	_marker_poly(marker, PackedVector2Array([
		Vector2(-3.6, 8), Vector2(3.6, 8), Vector2(2.2, -8), Vector2(-2.2, -8)
	]), Color(0.34, 0.26, 0.18))
	# Root gate
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.7, 8), Vector2(1.7, 8), Vector2(1.4, 3.6), Vector2(0, 2.6), Vector2(-1.4, 3.6)
	]), Color(0.1, 0.07, 0.05, 0.9))
	# Canopy blobs (faction color)
	_marker_poly(marker, _ellipse_pts(Vector2(-5.4, -10.6), 5.8, 4.9, 12), fc.darkened(0.15))
	_marker_poly(marker, _ellipse_pts(Vector2(5.4, -10.6), 5.8, 4.9, 12), fc.darkened(0.15))
	_marker_poly(marker, _ellipse_pts(Vector2(0, -13.8), 6.8, 5.6, 12), fc)
	# Platform walkway ring on the trunk
	_marker_line(marker, PackedVector2Array([Vector2(-5.4, -2.5), Vector2(5.4, -2.5)]),
		_MARKER_GOLD, 1.2)
	if is_capital:
		# Golden bloom in the crown
		for i in 6:
			var a := TAU * float(i) / 6.0
			_marker_line(marker, PackedVector2Array([
				Vector2(0, -14.5), Vector2(0, -14.5) + Vector2(cos(a), sin(a)) * 2.6
			]), _MARKER_GOLD, 1.2)

func _city_tainted_jade(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Stepped pyramid with faction-color temple and serpent stair rails
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(9.4, 0.4), Vector2(6.2, -6.4),
		Vector2(3.4, -18.8), Vector2(-3.4, -18.8), Vector2(-6.2, -6.4), Vector2(-9.4, 0.4)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-12.6, 8), Vector2(12.6, 8), Vector2(8.6, 1), Vector2(-8.6, 1)
	]), _MARKER_STONE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-8.6, 1), Vector2(8.6, 1), Vector2(5.6, -5.6), Vector2(-5.6, -5.6)
	]), _MARKER_STONE_LIGHT)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-5.6, -5.6), Vector2(5.6, -5.6), Vector2(3.4, -11), Vector2(-3.4, -11)
	]), _MARKER_STONE)
	# Temple top (faction color)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-3, -11), Vector2(3, -11), Vector2(3, -16.4), Vector2(-3, -16.4)
	]), fc)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-3.8, -16.4), Vector2(3.8, -16.4), Vector2(0, -18.6)
	]), fc.darkened(0.2))
	# Central stair strip
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.7, 8), Vector2(1.7, 8), Vector2(1.2, -11), Vector2(-1.2, -11)
	]), Color(0.55, 0.52, 0.44))
	# Serpent-head stair rails (small gold hooks at the base)
	_marker_line(marker, _ellipse_arc_pts(Vector2(-3.2, 7), 1.6, 1.6, PI * 0.5, PI * 1.5, 6),
		_MARKER_GOLD, 1.2)
	_marker_line(marker, _ellipse_arc_pts(Vector2(3.2, 7), 1.6, 1.6, PI * 0.5, -PI * 0.5, 6),
		_MARKER_GOLD, 1.2)
	if is_capital:
		# Gold sun-serpent disc above the temple
		_marker_line(marker, _ellipse_pts(Vector2(0, -20.4), 1.7, 1.7, 10), _MARKER_GOLD, 1.1)

func _city_moonspear(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Domed sanctum + crescent-tipped spire
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -4), Vector2(8.6, -4),
		Vector2(7.4, -19), Vector2(4.4, -19), Vector2(2.2, -4), Vector2(-13.6, -4)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_city_wall(marker, -3.0)
	# Sanctum dome (faction color)
	_marker_poly(marker, _ellipse_arc_pts(Vector2(-3, -3), 7.2, 9.8, PI, TAU, 12), fc)
	_marker_line(marker, _ellipse_arc_pts(Vector2(-3, -3), 7.2, 9.8, PI + 0.3, TAU - 0.3, 10),
		_MARKER_GOLD, 1.0)
	# Star lantern dots on the dome
	_marker_poly(marker, _ellipse_pts(Vector2(-5.4, -8.2), 0.8, 0.8, 6), Color(0.92, 0.9, 0.7, 0.9))
	_marker_poly(marker, _ellipse_pts(Vector2(-0.8, -10.2), 0.8, 0.8, 6), Color(0.92, 0.9, 0.7, 0.9))
	# Spire
	_marker_poly(marker, PackedVector2Array([
		Vector2(4.6, -4), Vector2(7.2, -4), Vector2(6.4, -18.2), Vector2(5.4, -18.2)
	]), _MARKER_STONE_LIGHT)
	# Gold crescent tip
	_marker_line(marker, _ellipse_arc_pts(Vector2(5.9, -19.6), 1.9, 2.1, PI * 0.65, PI * 1.9, 8),
		_MARKER_GOLD, 1.3)
	if is_capital:
		_marker_poly(marker, _ellipse_pts(Vector2(-3, -14.6), 1.7, 1.7, 10), _MARKER_GOLD)

func _city_sunblessed(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Sun temple: gold-trimmed dome between two obelisks, sun disc over gate
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -4), Vector2(10.6, -4),
		Vector2(9.6, -16), Vector2(7, -16), Vector2(6.4, -4), Vector2(-6.4, -4),
		Vector2(-7, -16), Vector2(-9.6, -16), Vector2(-10.6, -4), Vector2(-13.6, -4)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_city_wall(marker, -3.0)
	# Obelisks
	for s in 2:
		var ox := -8.3 + 16.6 * float(s)
		_marker_poly(marker, PackedVector2Array([
			Vector2(ox - 1.2, -3), Vector2(ox + 1.2, -3),
			Vector2(ox + 0.7, -14.6), Vector2(ox - 0.7, -14.6)
		]), _MARKER_STONE_LIGHT)
		_marker_poly(marker, PackedVector2Array([
			Vector2(ox - 0.7, -14.6), Vector2(ox + 0.7, -14.6), Vector2(ox, -16.4)
		]), _MARKER_GOLD)
	# Dome (faction color, gold base line)
	_marker_poly(marker, _ellipse_arc_pts(Vector2(0, -3), 6.4, 9.6, PI, TAU, 12), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-6.4, -3.2), Vector2(6.4, -3.2)]),
		_MARKER_GOLD, 1.2)
	# Sun disc over the gate
	_marker_poly(marker, _ellipse_pts(Vector2(0, 0.2), 1.6, 1.6, 8), _MARKER_GOLD)
	if is_capital:
		for i in 8:
			var a := TAU * float(i) / 8.0
			_marker_line(marker, PackedVector2Array([
				Vector2(0, -12.4) + Vector2(cos(a), sin(a)) * 2.0,
				Vector2(0, -12.4) + Vector2(cos(a), sin(a)) * 3.6
			]), _MARKER_GOLD, 1.0)

func _city_thunderswarm(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Storm hall: longhouse with faction roof + lightning-rod mast
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -1), Vector2(3.4, -12),
		Vector2(2.6, -20), Vector2(0.6, -20), Vector2(-0.4, -12), Vector2(-13.6, -1)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	# Hall walls
	_marker_poly(marker, PackedVector2Array([
		Vector2(-11.6, 8), Vector2(11.6, 8), Vector2(11.6, -0.6), Vector2(-11.6, -0.6)
	]), Color(0.35, 0.29, 0.22))
	# Steep faction-color roof
	_marker_poly(marker, PackedVector2Array([
		Vector2(-12.8, -0.6), Vector2(12.8, -0.6), Vector2(1.6, -11.4)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-12.8, -0.5), Vector2(12.8, -0.5)]),
		_MARKER_GOLD, 1.0)
	# Crossed gable beams
	_marker_line(marker, PackedVector2Array([Vector2(-1.4, -12.2), Vector2(4.6, -6.4)]),
		Color(0.3, 0.24, 0.18), 1.2)
	_marker_line(marker, PackedVector2Array([Vector2(4.6, -12.2), Vector2(-1.4, -6.4)]),
		Color(0.3, 0.24, 0.18), 1.2)
	# Lightning-rod mast with crackling gold tip
	_marker_line(marker, PackedVector2Array([Vector2(1.6, -11.4), Vector2(1.6, -19)]),
		Color(0.3, 0.24, 0.18), 1.3)
	_marker_line(marker, PackedVector2Array([
		Vector2(1.6, -19), Vector2(3.2, -16.8), Vector2(1.9, -16.2), Vector2(3.6, -13.6)
	]), _MARKER_GOLD, 1.2)
	# Dark door
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.6, 8), Vector2(1.6, 8), Vector2(1.6, 2.6), Vector2(-1.6, 2.6)
	]), Color(0.12, 0.09, 0.07))
	if is_capital:
		_marker_poly(marker, PackedVector2Array([
			Vector2(-4.6, -14.2), Vector2(-2.6, -17.8), Vector2(-3.4, -15.4),
			Vector2(-1.8, -15.8), Vector2(-4.4, -12.2), Vector2(-3.8, -14.4)
		]), _MARKER_GOLD)

func _city_cinderguard(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Squat bastion: angled walls, ember forge chimney, portcullis gate
	var body := PackedVector2Array([
		Vector2(-14.2, 9), Vector2(14.2, 9), Vector2(11, -9), Vector2(7.6, -9),
		Vector2(7.2, -17.6), Vector2(4, -17.6), Vector2(3.8, -9), Vector2(-11, -9)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	# Angled bastion wall
	_marker_poly(marker, PackedVector2Array([
		Vector2(-13.2, 8), Vector2(13.2, 8), Vector2(10, -8), Vector2(-10, -8)
	]), Color(0.34, 0.3, 0.28))
	for i in 3:
		var tx := -7.2 + 7.2 * float(i)
		_marker_poly(marker, PackedVector2Array([
			Vector2(tx - 1.3, -8), Vector2(tx + 1.3, -8),
			Vector2(tx + 1.3, -10.4), Vector2(tx - 1.3, -10.4)
		]), Color(0.34, 0.3, 0.28))
	_marker_line(marker, PackedVector2Array([Vector2(-10, -7.9), Vector2(10, -7.9)]),
		_MARKER_GOLD, 1.1)
	# Faction banner strip across the wall
	_marker_poly(marker, PackedVector2Array([
		Vector2(-8.4, -1), Vector2(8.4, -1), Vector2(8.4, -4.6), Vector2(-8.4, -4.6)
	]), fc)
	# Forge chimney with ember glow
	_marker_poly(marker, PackedVector2Array([
		Vector2(4.6, -8), Vector2(6.8, -8), Vector2(6.6, -16.6), Vector2(4.8, -16.6)
	]), Color(0.28, 0.24, 0.22))
	_marker_poly(marker, _ellipse_pts(Vector2(5.7, -17.2), 1.3, 1.0, 8), Color(0.95, 0.5, 0.15, 0.95))
	# Portcullis gate (vertical bars)
	_city_gate(marker)
	for i in 3:
		var gx := -1.5 + 1.5 * float(i)
		_marker_line(marker, PackedVector2Array([Vector2(gx, 8), Vector2(gx, 1.6)]),
			Color(0.5, 0.44, 0.36), 0.8)
	if is_capital:
		# Gold anvil crest
		_marker_poly(marker, PackedVector2Array([
			Vector2(-4.4, -13.2), Vector2(-0.6, -13.2), Vector2(-1.2, -14.6),
			Vector2(-1.8, -14.6), Vector2(-1.8, -15.8), Vector2(-3.2, -15.8),
			Vector2(-3.2, -14.6), Vector2(-3.8, -14.6)
		]), _MARKER_GOLD)

func _city_forsaken(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Shrouded citadel: hooded tower, narrow lit windows, tattered banner
	var body := PackedVector2Array([
		Vector2(-13.6, 9), Vector2(13.6, 9), Vector2(13.6, -3), Vector2(6.6, -3),
		Vector2(5.4, -13), Vector2(7.8, -15.4), Vector2(0.6, -20.6), Vector2(-4.6, -14),
		Vector2(-5.4, -3), Vector2(-13.6, -3)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_city_wall(marker, -2.0)
	# Hooded tower (tapering, with overhanging cowl)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-4.4, -2), Vector2(4.4, -2), Vector2(3.2, -13.6), Vector2(-3.4, -13.6)
	]), Color(0.26, 0.23, 0.24))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-4.4, -12.6), Vector2(6.6, -14.4), Vector2(0.4, -19.6), Vector2(-3.6, -15.4)
	]), Color(0.2, 0.17, 0.19))
	# Narrow lit windows
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.6, -6), Vector2(-0.8, -6), Vector2(-0.8, -9.6), Vector2(-1.6, -9.6)
	]), Color(0.95, 0.75, 0.35, 0.9))
	_marker_poly(marker, PackedVector2Array([
		Vector2(1.2, -5), Vector2(2.0, -5), Vector2(2.0, -8.2), Vector2(1.2, -8.2)
	]), Color(0.95, 0.75, 0.35, 0.75))
	# Tattered faction banner off the cowl
	_marker_poly(marker, PackedVector2Array([
		Vector2(4.4, -14.8), Vector2(7.4, -15.2), Vector2(7.2, -10.4), Vector2(6.4, -12),
		Vector2(5.8, -9.6), Vector2(5.0, -11.6)
	]), fc)
	if is_capital:
		# Gold eye crest on the cowl
		_marker_line(marker, _ellipse_pts(Vector2(0.4, -16.4), 1.9, 1.1, 8), _MARKER_GOLD, 0.9)
		_marker_poly(marker, _ellipse_pts(Vector2(0.4, -16.4), 0.6, 0.6, 6), _MARKER_GOLD)

func _city_ivoryscar(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Black pyramid with ivory capstone seam and relic light at the apex
	var body := PackedVector2Array([
		Vector2(-14.2, 9), Vector2(14.2, 9), Vector2(0.0, -20.2)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-13.2, 8), Vector2(13.2, 8), Vector2(0, -19)
	]), Color(0.16, 0.14, 0.15))
	# Faction color band at the base
	_marker_poly(marker, PackedVector2Array([
		Vector2(-13.2, 8), Vector2(13.2, 8), Vector2(11.4, 5.2), Vector2(-11.4, 5.2)
	]), fc)
	# Ivory capstone seam
	_marker_line(marker, PackedVector2Array([Vector2(-3.4, -12), Vector2(3.4, -12)]),
		Color(0.88, 0.84, 0.72), 1.3)
	# Relic light at the apex
	_marker_poly(marker, _ellipse_pts(Vector2(0, -16.2), 1.4, 1.4, 8), Color(0.9, 0.85, 0.6, 0.95))
	# Dark entry
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.8, 8), Vector2(1.8, 8), Vector2(0, 3.6)
	]), Color(0.06, 0.05, 0.05))
	if is_capital:
		# Gold scarab crest (oval + wing notches)
		_marker_poly(marker, _ellipse_pts(Vector2(0, -7.4), 1.6, 2.0, 8), _MARKER_GOLD)
		_marker_line(marker, PackedVector2Array([Vector2(-3.2, -8.4), Vector2(-1.4, -7.4)]), _MARKER_GOLD, 1.0)
		_marker_line(marker, PackedVector2Array([Vector2(3.2, -8.4), Vector2(1.4, -7.4)]), _MARKER_GOLD, 1.0)

func _city_shardhorde(marker: Node2D, fc: Color, is_capital: bool) -> void:
	# Crystal hold: rock base with jutting faction-color shard towers
	var body := PackedVector2Array([
		Vector2(-14, 9), Vector2(14, 9), Vector2(12, -1), Vector2(8.6, -2),
		Vector2(10.4, -13), Vector2(5.4, -4), Vector2(2.2, -20), Vector2(-3.4, -4.6),
		Vector2(-8.2, -14.6), Vector2(-8.4, -2), Vector2(-12, -1)
	])
	_marker_poly(marker, body, _MARKER_OUTLINE)
	# Rock mound
	_marker_poly(marker, PackedVector2Array([
		Vector2(-13, 8), Vector2(13, 8), Vector2(11, -0.6), Vector2(4.4, -2.8),
		Vector2(-4.4, -2.8), Vector2(-11, -0.6)
	]), Color(0.3, 0.27, 0.25))
	# Side shards
	_marker_poly(marker, PackedVector2Array([
		Vector2(-9.4, -1), Vector2(-5.8, -2.4), Vector2(-7.4, -13.4)
	]), fc.darkened(0.2))
	_marker_poly(marker, PackedVector2Array([
		Vector2(6.4, -1.6), Vector2(9.8, -0.6), Vector2(9.4, -11.8)
	]), fc.darkened(0.25))
	# Great resonating crystal
	_marker_poly(marker, PackedVector2Array([
		Vector2(-2.8, -2.8), Vector2(3.4, -2.8), Vector2(1.6, -18.8)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(0.2, -3.2), Vector2(1.4, -16.4)]),
		fc.lightened(0.35), 1.1)
	# Dark entry in the rock
	_marker_poly(marker, PackedVector2Array([
		Vector2(-1.8, 8), Vector2(1.8, 8), Vector2(1.4, 3.4), Vector2(0, 2.4), Vector2(-1.4, 3.4)
	]), Color(0.08, 0.06, 0.06))
	if is_capital:
		# Gold shard-star at the crystal tip
		for i in 4:
			var a := TAU * float(i) / 4.0 + PI / 4.0
			_marker_line(marker, PackedVector2Array([
				Vector2(1.6, -19.6), Vector2(1.6, -19.6) + Vector2(cos(a), sin(a)) * 2.4
			]), _MARKER_GOLD, 1.1)

func _city_generic(marker: Node2D, fc: Color) -> void:
	# Neutral/independent: the standard stone keep
	_marker_poly(marker, PackedVector2Array([
		Vector2(-14, 9.5), Vector2(-14, -8), Vector2(-11.5, -8), Vector2(-11.5, -15.5),
		Vector2(-6, -15.5), Vector2(-6, -8), Vector2(-5.6, -8), Vector2(-5.6, -19.5),
		Vector2(5.6, -19.5), Vector2(5.6, -8), Vector2(6, -8), Vector2(6, -15.5),
		Vector2(11.5, -15.5), Vector2(11.5, -8), Vector2(14, -8), Vector2(14, 9.5)
	]), _MARKER_OUTLINE)
	_city_wall(marker, -6.5)
	for side: float in [-1.0, 1.0]:
		var cx := 8.75 * side
		_marker_poly(marker, PackedVector2Array([
			Vector2(cx - 2.4, -6.5), Vector2(cx + 2.4, -6.5),
			Vector2(cx + 2.4, -13.5), Vector2(cx - 2.4, -13.5)
		]), _MARKER_STONE_LIGHT)
		_marker_poly(marker, PackedVector2Array([
			Vector2(cx - 3.1, -13.5), Vector2(cx + 3.1, -13.5), Vector2(cx, -18.2)
		]), fc.darkened(0.12))
	_marker_poly(marker, PackedVector2Array([
		Vector2(-4.6, -6.5), Vector2(4.6, -6.5), Vector2(4.6, -18.5), Vector2(-4.6, -18.5)
	]), _MARKER_STONE_LIGHT)
	for kx: float in [-3.4, 0.0, 3.4]:
		_marker_poly(marker, PackedVector2Array([
			Vector2(kx - 1.0, -18.5), Vector2(kx + 1.0, -18.5),
			Vector2(kx + 1.0, -20.8), Vector2(kx - 1.0, -20.8)
		]), _MARKER_STONE_LIGHT)
	_marker_poly(marker, PackedVector2Array([
		Vector2(-2.2, -17.5), Vector2(2.2, -17.5), Vector2(2.2, -9.5),
		Vector2(0, -7.5), Vector2(-2.2, -9.5)
	]), fc)
	_marker_line(marker, PackedVector2Array([Vector2(-2.4, -17.5), Vector2(2.4, -17.5)]),
		_MARKER_GOLD, 1.0)
	_city_gate(marker)

func _create_army_marker(army: ArmyState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(army.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color.WHITE

	# Ground shadow
	_marker_poly(marker, _ellipse_pts(Vector2(0, 10.5), 11.0, 3.5), Color(0, 0, 0, 0.3))

	# Faction-flavored shield (culture decides shape, faction color the field)
	_draw_army_shield_art(marker, _marker_culture(army.faction_id), faction_color)

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

func _create_city_marker(city: CityState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(city.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(city.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color.WHITE

	var culture := _marker_culture(city.faction_id)
	if city.is_settlement:
		# Ground shadow + culture-flavored hamlet
		_marker_poly(marker, _ellipse_pts(Vector2(0, 5), 9.5, 3.0), Color(0, 0, 0, 0.3))
		_draw_settlement_art(marker, culture, faction_color)
	else:
		# Ground shadow + culture-flavored city, universal crown on capitals
		_marker_poly(marker, _ellipse_pts(Vector2(0, 8.5), 14.5, 4.0), Color(0, 0, 0, 0.3))
		_draw_city_art(marker, culture, faction_color, city.is_capital)
		if city.is_capital:
			_marker_poly(marker, PackedVector2Array([
				Vector2(-4.5, -23), Vector2(-4.5, -26.5), Vector2(-2.2, -24.4),
				Vector2(0, -27.5), Vector2(2.2, -24.4), Vector2(4.5, -26.5), Vector2(4.5, -23)
			]), Color(0.95, 0.85, 0.3))

	# City level glow — scales with city level, larger for capitals
	if city.faction_id == GameManager.state.player_faction_id:
		var glow_base_radius := 14.0 + city.level * 2.0
		if city.is_capital:
			glow_base_radius += 6.0
		elif city.is_settlement:
			glow_base_radius -= 4.0
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

	# Level label
	var label := Label.new()
	label.text = str(city.level)
	var label_offset := Vector2(-3, -8) if city.is_settlement else Vector2(-4, -16)
	label.position = label_offset
	label.add_theme_font_size_override("font_size", 8 if city.is_settlement else 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(label)

	# Siege indicator (red pulsing ring, hidden by default)
	var siege_ring := Polygon2D.new()
	siege_ring.name = "SiegeRing"
	siege_ring.polygon = _make_circle(18.0, 12)
	siege_ring.color = Color(0.9, 0.15, 0.1, 0.4)
	siege_ring.visible = city.is_under_siege
	marker.add_child(siege_ring)

	if city.is_under_siege:
		_animate_siege_ring(siege_ring)

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
	hammer.position = Vector2(12, -18)
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
		plaque.position = Vector2(-plaque_w * 0.5, 10)
		marker.add_child(plaque)

	# Colored outline around castle shape based on relationship to player
	var outline := Line2D.new()
	outline.name = "CityOutline"
	outline.width = 2.0
	outline.default_color = _relation_ring_color(city.faction_id)
	# Relation ring at the marker's base — only the FRONT arc is drawn; the
	# part that would pass "behind" the structure stays hidden
	var ring_center := Vector2(0, 5) if city.is_settlement else Vector2(0, 8.5)
	var ring_rx := 11.0 if city.is_settlement else 16.0
	var ring_ry := 3.4 if city.is_settlement else 5.0
	outline.points = _ellipse_arc_pts(ring_center, ring_rx, ring_ry, -0.35, PI + 0.35, 16)
	outline.antialiased = true
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	outline.z_index = 1
	marker.add_child(outline)

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

	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		var faction_data: FactionData = DataManager.get_faction(city.faction_id)
		var faction_color: Color = faction_data.color if faction_data else Color.WHITE

		# Draw markers for completed buildings
		for bid in city.building_tiles:
			var tile_pos: Vector2i = city.building_tiles[bid]
			var building: BuildingData = DataManager.get_building(bid)
			_add_building_tile_marker(tile_pos, building, faction_color, false, city.faction_id)

		# Draw markers for buildings under construction
		for item in city.build_queue:
			if item.has("tile_pos"):
				var building: BuildingData = DataManager.get_building(item.building_id)
				_add_building_tile_marker(item.tile_pos, building, faction_color, true, city.faction_id)

func _add_building_tile_marker(tile_pos: Vector2i, building: BuildingData, faction_color: Color, under_construction: bool, city_faction_id: StringName = &"") -> void:
	var pixel_pos := _hex_to_pixel(tile_pos)
	var marker := Node2D.new()
	marker.position = pixel_pos

	# Small building graphic per category — deliberately more modest than the
	# city marker (which stays the visual anchor and the only one ringed).
	# The roof carries the category color for at-a-glance reading; a small
	# faction-color pennant marks ownership.
	var cat: StringName = building.category if building else &"economic"
	var cat_color: Color = BUILDING_CATEGORY_COLORS.get(cat, Color(0.5, 0.5, 0.5, 0.7))
	cat_color.a = 1.0

	# Ground shadow
	_marker_poly(marker, _ellipse_pts(Vector2(0, 4), 7.0, 2.2), Color(0, 0, 0, 0.25))

	match cat:
		&"military":
			# Barracks tent: wide low body + peaked category roof
			_marker_poly(marker, _scaled_pts(PackedVector2Array([
				Vector2(-6.5, 4), Vector2(6.5, 4), Vector2(0, -6.5)
			]), 1.2, Vector2(0, 0.5)), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-6.5, 4), Vector2(6.5, 4), Vector2(0, -6.5)
			]), cat_color.darkened(0.15))
			_marker_line(marker, PackedVector2Array([Vector2(0, -6.5), Vector2(0, 4)]),
				cat_color.darkened(0.45), 1.0)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-1.4, 4), Vector2(1.4, 4), Vector2(0, 0.8)
			]), Color(0.12, 0.09, 0.07))
		&"defensive":
			# Mini watchtower: tapered stone tower with crenellated top
			_marker_poly(marker, _scaled_pts(PackedVector2Array([
				Vector2(-3.4, 4), Vector2(3.4, 4), Vector2(2.6, -6), Vector2(-2.6, -6)
			]), 1.25, Vector2(0, -0.5)), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-3.4, 4), Vector2(3.4, 4), Vector2(2.6, -6), Vector2(-2.6, -6)
			]), _MARKER_STONE)
			for tx: float in [-2.4, 0.0, 2.4]:
				_marker_poly(marker, PackedVector2Array([
					Vector2(tx - 0.8, -6), Vector2(tx + 0.8, -6),
					Vector2(tx + 0.8, -7.8), Vector2(tx - 0.8, -7.8)
				]), _MARKER_STONE)
			_marker_line(marker, PackedVector2Array([Vector2(-2.6, -5.9), Vector2(2.6, -5.9)]),
				cat_color, 1.1)
		&"cultural":
			# Small shrine: stone base + category-colored dome + gold finial
			_marker_poly(marker, _scaled_pts(PackedVector2Array([
				Vector2(-4.5, 4), Vector2(4.5, 4), Vector2(4.5, -1), Vector2(-4.5, -1)
			]), 1.2, Vector2(0, 1.5)), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-4.5, 4), Vector2(4.5, 4), Vector2(4.5, -1), Vector2(-4.5, -1)
			]), _MARKER_STONE_LIGHT)
			_marker_poly(marker, _ellipse_arc_pts(Vector2(0, -1), 4.2, 5.6, PI, TAU, 10), cat_color)
			_marker_poly(marker, _ellipse_pts(Vector2(0, -6.9), 0.9, 0.9, 6), _MARKER_GOLD)
		_:
			# Economic: barn — stone body + category-colored gable roof
			_marker_poly(marker, _scaled_pts(PackedVector2Array([
				Vector2(-5.5, 4), Vector2(5.5, 4), Vector2(5.5, -1.5), Vector2(-5.5, -1.5)
			]), 1.2, Vector2(0, 1.2)), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-5.5, 4), Vector2(5.5, 4), Vector2(5.5, -1.5), Vector2(-5.5, -1.5)
			]), _MARKER_STONE)
			_marker_poly(marker, _scaled_pts(PackedVector2Array([
				Vector2(-6.3, -1.5), Vector2(6.3, -1.5), Vector2(0, -7)
			]), 1.12, Vector2(0, -3.5)), _MARKER_OUTLINE)
			_marker_poly(marker, PackedVector2Array([
				Vector2(-6.3, -1.5), Vector2(6.3, -1.5), Vector2(0, -7)
			]), cat_color.darkened(0.1))
			_marker_poly(marker, PackedVector2Array([
				Vector2(-1.3, 4), Vector2(1.3, 4), Vector2(1.3, 1), Vector2(-1.3, 1)
			]), Color(0.12, 0.09, 0.07))

	# Faction pennant (ownership at a glance)
	_marker_line(marker, PackedVector2Array([Vector2(5.2, -3), Vector2(5.2, -9.5)]),
		Color(0.4, 0.3, 0.18), 1.0)
	_marker_poly(marker, PackedVector2Array([
		Vector2(5.2, -9.5), Vector2(8.4, -8.4), Vector2(5.2, -7.3)
	]), faction_color)

	if under_construction:
		# In progress: ghosted + scaffold cross-beams
		marker.modulate = Color(1, 1, 1, 0.45)
		_marker_line(marker, PackedVector2Array([Vector2(-5.5, 3.5), Vector2(5.5, -6)]),
			Color(0.75, 0.62, 0.35), 1.2)
		_marker_line(marker, PackedVector2Array([Vector2(5.5, 3.5), Vector2(-5.5, -6)]),
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

		# Building/upgrade available glow (green)
		if has_building_action and build_glow == null:
			_add_build_glow(marker)
		elif not has_building_action and build_glow:
			build_glow.queue_free()

		# Settlement founding glow (gold)
		if has_settle_action and settle_glow == null:
			_add_settle_glow(marker)
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

func _add_build_glow(marker: Node2D) -> void:
	var glow := Polygon2D.new()
	glow.name = "BuildGlow"
	glow.polygon = _make_circle(20.0, 12)
	glow.color = Color(0.2, 0.8, 0.3, 0.25)
	glow.z_index = -1
	marker.add_child(glow)
	var tween := marker.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.4, 1.0)
	tween.tween_property(glow, "modulate:a", 1.0, 1.0)

func _add_settle_glow(marker: Node2D) -> void:
	var glow := Polygon2D.new()
	glow.name = "SettleGlow"
	glow.polygon = _make_circle(22.0, 12)
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

func _on_region_ownership_changed(_region_id: StringName, _old: StringName, _new: StringName) -> void:
	# Defer heavy visual work during AI turns — will be rebuilt on player turn start
	if not TurnManager.is_player_turn:
		_minimap_terrain_dirty = true
		return
	_update_political_overlay()
	_refresh_faction_borders()
	_fog_dirty = true
	_minimap_terrain_dirty = true

func _on_battle_initiated(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

	# Garrison reinforcements: if defender is in their own/allied city, merge garrison units
	_merge_garrison_reinforcements(defender_army, hex_pos)
	# Also check attacker (if attacker is in their own city — rare but possible)
	_merge_garrison_reinforcements(attacker_army, hex_pos)

	# AI vs AI: always auto-resolve silently
	var player_fid := GameManager.state.player_faction_id
	if attacker_army.faction_id != player_fid and defender_army.faction_id != player_fid:
		_auto_resolve_battle(attacker_id, defender_id, hex_pos)
		return

	# Player involved: show battle choice dialog
	_pending_battle_attacker_id = attacker_id
	_pending_battle_defender_id = defender_id
	_pending_battle_hex = hex_pos
	_show_battle_dialog(attacker_army, defender_army)

## Merge garrison units from a city into a defending army
func _merge_garrison_reinforcements(army: ArmyState, hex_pos: Vector2i) -> void:
	if army.is_garrison:
		return  # Garrison armies don't merge with themselves
	var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
	if city_at == null:
		return
	# City must be owned by the army's faction or allied
	if city_at.faction_id != army.faction_id:
		var relation := GameManager.get_relation(city_at.faction_id, army.faction_id)
		if relation != Enums.FactionRelation.ALLIED:
			return
	# Generate garrison units and add to army
	var garrison_comp: Array = GameManager.city_system._get_garrison_composition(city_at)
	var reinforcement_count := 0
	for entry in garrison_comp:
		var uid: StringName = entry.unit_id
		var unit_data := DataManager.get_unit(uid)
		if unit_data == null:
			continue
		for i in entry.count:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, GameManager.state.generate_id())
			army.units.append(instance)
			reinforcement_count += 1
	# Store count so we can strip them back out after battle
	if reinforcement_count > 0:
		army.set_meta("garrison_reinforcement_count", reinforcement_count)

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
		if r_effects.get("unit_attack_bonus", 0) != 0:
			r_parts.append("ATK %+d (per entity)" % r_effects["unit_attack_bonus"])
		if r_effects.get("unit_defense_bonus", 0) != 0:
			r_parts.append("DEF %+d" % r_effects["unit_defense_bonus"])
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
	_auto_resolve_battle(_pending_battle_attacker_id, _pending_battle_defender_id, _pending_battle_hex)

func _auto_resolve_battle(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

	# Snapshot HP before battle for report
	var atk_snapshot: Array[Dictionary] = []
	for unit in attacker_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		atk_snapshot.append({
			"name": ud.display_name if ud else str(unit.unit_data_id),
			"hp_before": unit.current_hp,
			"max_hp": ud.max_hp if ud else unit.current_hp,
		})
	var def_snapshot: Array[Dictionary] = []
	for unit in defender_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		def_snapshot.append({
			"name": ud.display_name if ud else str(unit.unit_data_id),
			"hp_before": unit.current_hp,
			"max_hp": ud.max_hp if ud else unit.current_hp,
		})

	# Calculate commander bonuses for both sides
	var atk_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(attacker_army.commander)
	var def_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(defender_army.commander)
	# Apply camp building bonuses (Sunblessed Sunfire Forge etc.)
	_apply_camp_building_bonuses(attacker_army, atk_cmd_bonuses)
	_apply_camp_building_bonuses(defender_army, def_cmd_bonuses)

	# Snapshot army strengths before battle (for loot and XP calculation)
	var atk_strength_pre := attacker_army.get_total_strength()
	var def_strength_pre := defender_army.get_total_strength()

	# Create V2 headless battle simulation
	var campaign_terrain := Enums.TerrainType.PLAINS
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(hex_pos)
		if tile:
			campaign_terrain = tile.terrain

	var sim := BattleSimulatorV2.new()
	sim.compute_grid_size(attacker_army, defender_army)
	var terrain := BattleTerrainGen.generate(campaign_terrain, hex_pos.x * 1000 + hex_pos.y, sim.grid_width, sim.grid_height)
	sim.setup_terrain(terrain)
	sim.setup_attacker_formations(attacker_army, atk_cmd_bonuses)
	sim.setup_defender_formations(defender_army, def_cmd_bonuses)
	sim.assign_ai_orders_both_sides()

	# Run simulation to completion
	for tick in range(sim.max_ticks):
		sim.simulate_tick()
		if sim.is_finished:
			break

	# Apply results
	var atk_survivors := sim.get_surviving_formations(0)
	var def_survivors := sim.get_surviving_formations(1)

	_apply_auto_battle_results(attacker_army, atk_survivors)
	_apply_auto_battle_results(defender_army, def_survivors)

	# Elderbeast recovery: if a beast's escort army lost, apply recovery mechanic
	for side_army in [attacker_army, defender_army]:
		if side_army.elderbeast_id != &"":
			_handle_elderbeast_battle_aftermath(side_army)

	# Grant veterancy XP to surviving units
	_grant_auto_veterancy_xp(attacker_army, atk_survivors, def_strength_pre)
	_grant_auto_veterancy_xp(defender_army, def_survivors, atk_strength_pre)

	var atk_alive := atk_survivors.size() > 0 or attacker_army.elderbeast_id != &""
	var def_alive := def_survivors.size() > 0 or defender_army.elderbeast_id != &""

	# Build HP after data for report
	var atk_hp_after: Dictionary = {} # index -> hp
	for bu in atk_survivors:
		for i in atk_snapshot.size():
			if i < attacker_army.units.size() and attacker_army.units[i].instance_id == bu.instance_id:
				atk_hp_after[i] = bu.current_hp
	var def_hp_after: Dictionary = {}
	for bu in def_survivors:
		for i in def_snapshot.size():
			if i < defender_army.units.size() and defender_army.units[i].instance_id == bu.instance_id:
				def_hp_after[i] = bu.current_hp

	# Award captives
	var winner_side := sim.winner_side
	if winner_side >= 0:
		var winner_faction := attacker_army.faction_id if winner_side == 0 else defender_army.faction_id
		var winner_captives: int = sim.captives.get(winner_side, 0)
		if winner_captives > 0:
			var wfs: FactionState = GameManager.state.faction_states.get(winner_faction)
			if wfs:
				wfs.resources[Enums.ResourceType.CAPTIVES] = wfs.resources.get(Enums.ResourceType.CAPTIVES, 0) + winner_captives

	if not def_alive:
		# Mark garrison as defeated so it doesn't respawn at full strength
		if defender_army.is_garrison:
			var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0
		GameManager.remove_army(defender_id)

	# Garrison assault: check if attacker won (morale/routing victory counts)
	var garrison_retreat := false
	var def_faction_id := defender_army.faction_id
	if defender_army.is_garrison and def_alive:
		var attacker_won_garrison := (winner_side == 0 and atk_alive)
		if attacker_won_garrison:
			# Attacker won — garrison overrun, treat as destroyed
			var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0
			GameManager.remove_army(defender_id)
			def_alive = false
		else:
			# Attacker failed to defeat garrison — retreat with survivors or die
			GameManager.remove_army(defender_id) # garrison regenerates next attack
			def_alive = false
			if atk_alive:
				# Retreat attacker 1 tile back from the city
				var retreat_hex := _find_retreat_hex(attacker_army, hex_pos)
				if retreat_hex != Vector2i(-1, -1):
					attacker_army.hex_pos = retreat_hex
					GameManager.movement_system.invalidate_positions()
				attacker_army.movement_remaining = 0.0
				attacker_army.battle_exhausted = true
				garrison_retreat = true
				# Persist garrison damage — surviving garrison spawns with reduced HP
				var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
				if garrison_city:
					var total_max := 0
					var total_current := 0
					for unit in defender_army.units:
						var data := DataManager.get_unit(unit.unit_data_id)
						if data:
							total_max += data.max_hp
						total_current += unit.current_hp
					if total_max > 0:
						garrison_city.garrison_hp_ratio = clampf(float(total_current) / float(total_max), 0.01, 1.0)
			else:
				GameManager.remove_army(attacker_id)
	elif not atk_alive:
		GameManager.remove_army(attacker_id)

	# Remove surviving garrison armies (they regenerate on next attack)
	if def_alive and defender_army.is_garrison:
		GameManager.remove_army(defender_id)
		def_alive = false

	# Stalemate: both armies survive — separate and exhaust
	if atk_alive and def_alive:
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		defender_army.battle_exhausted = true
		defender_army.movement_remaining = 0.0
		_separate_armies_stalemate(attacker_army, defender_army)

	# Handle siege consequences (same as manual battle)
	if atk_alive and not def_alive and not garrison_retreat:
		attacker_army.hex_pos = hex_pos
		GameManager.movement_system.invalidate_positions()
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		EventBus.battle_resolved.emit(attacker_army.faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(attacker_army.faction_id, def_faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id != attacker_army.faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_army.faction_id)
		elif city_at and city_at.faction_id == attacker_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
	elif garrison_retreat:
		EventBus.battle_resolved.emit(def_faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(def_faction_id, attacker_army.faction_id, 5)
	elif def_alive and not atk_alive:
		EventBus.battle_resolved.emit(defender_army.faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(defender_army.faction_id, attacker_army.faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id == defender_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)

	# Build battle context for context-aware skill selection
	var base_ctx: Array[StringName] = []
	var ctx_tile := GameManager.state.hex_map.get_tile(hex_pos)
	if ctx_tile:
		base_ctx.append(StringName("terrain_" + Enums.TerrainType.keys()[ctx_tile.terrain].to_lower()))
	if GameManager.city_system.get_city_at_hex(hex_pos):
		base_ctx.append(&"in_city")

	# Collect used and faced unit tags from both sides
	var unit_tag_types := ["cavalry", "ranged", "mage", "infantry", "beast", "monster", "construct"]
	var atk_used_tags: Dictionary = {}
	var def_faced_tags: Dictionary = {}
	for f in sim.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_used_tags[tag] = true
	for f in sim.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_faced_tags[tag] = true
	var def_used_tags: Dictionary = {}
	var atk_faced_tags: Dictionary = {}
	for f in sim.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_used_tags[tag] = true
	for f in sim.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_faced_tags[tag] = true

	var atk_ctx: Array[StringName] = base_ctx.duplicate()
	atk_ctx.append(&"was_attacker")
	atk_ctx.append(&"battle_won" if atk_alive else &"battle_lost")
	atk_ctx.append(StringName("enemy_" + defender_army.faction_id))
	for tag in def_faced_tags:
		atk_ctx.append(StringName("faced_" + tag))
	for tag in atk_used_tags:
		atk_ctx.append(StringName("used_" + tag))

	var def_ctx: Array[StringName] = base_ctx.duplicate()
	def_ctx.append(&"was_defender")
	def_ctx.append(&"battle_won" if def_alive else &"battle_lost")
	def_ctx.append(StringName("enemy_" + attacker_army.faction_id))
	for tag in atk_faced_tags:
		def_ctx.append(StringName("faced_" + tag))
	for tag in def_used_tags:
		def_ctx.append(StringName("used_" + tag))

	# Commander XP and item drops (use pre-battle strengths)
	if attacker_army.commander:
		CommanderSystem.grant_battle_xp(attacker_army.commander, def_strength_pre, atk_alive, atk_ctx)
		var atk_trait_changes := CommanderSystem.evaluate_traits(attacker_army.commander, atk_ctx)
		for change in atk_trait_changes:
			EventBus.commander_trait_changed.emit(attacker_army.commander, change.action, change.trait_id)
		if atk_alive and not def_alive:
			CommanderSystem.apply_item_drop(attacker_army.commander, defender_army.faction_id)
	if defender_army.commander:
		CommanderSystem.grant_battle_xp(defender_army.commander, atk_strength_pre, def_alive, def_ctx)
		var def_trait_changes := CommanderSystem.evaluate_traits(defender_army.commander, def_ctx)
		for change in def_trait_changes:
			EventBus.commander_trait_changed.emit(defender_army.commander, change.action, change.trait_id)
		if def_alive and not atk_alive:
			CommanderSystem.apply_item_drop(defender_army.commander, attacker_army.faction_id)

	# Battle loot for the winner
	var _loot_gold := 0
	var _loot_iron := 0
	var _loot_captives := 0
	if atk_alive and not def_alive:
		_loot_gold = int(sqrt(def_strength_pre) * 1.26)
		_loot_iron = int(sqrt(def_strength_pre) * 0.31)
		var wfs: FactionState = GameManager.state.faction_states.get(attacker_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + _loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + _loot_iron
	elif def_alive and not atk_alive:
		_loot_gold = int(sqrt(atk_strength_pre) * 1.26)
		_loot_iron = int(sqrt(atk_strength_pre) * 0.31)
		var wfs: FactionState = GameManager.state.faction_states.get(defender_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + _loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + _loot_iron

	# Faction mechanic: Thunderswarm storm fury rises from battles
	for fid in [attacker_army.faction_id, defender_army.faction_id]:
		if fid == &"thunderswarm":
			var tfs: FactionState = GameManager.state.faction_states.get(fid)
			if tfs:
				tfs.storm_fury = mini(tfs.storm_fury + 15, 100)

	# Faction mechanic: Sunblessed solar faith changes from battle results
	for battle_pair in [[attacker_army.faction_id, atk_alive], [defender_army.faction_id, def_alive]]:
		if battle_pair[0] == &"sunblessed":
			var sfs: FactionState = GameManager.state.faction_states.get(battle_pair[0])
			if sfs:
				if battle_pair[1]:
					sfs.solar_faith = mini(sfs.solar_faith + 10, 100)
				else:
					sfs.solar_faith = maxi(sfs.solar_faith - 15, 0)

	# Show battle report for player-involved battles
	var player_fid := GameManager.state.player_faction_id
	var player_involved := attacker_army.faction_id == player_fid or defender_army.faction_id == player_fid
	if player_involved:
		var player_won := (attacker_army.faction_id == player_fid and atk_alive and not def_alive) or \
			(defender_army.faction_id == player_fid and def_alive and not atk_alive)
		var report := {
			"atk_faction": attacker_army.faction_id,
			"def_faction": defender_army.faction_id,
			"atk_snapshot": atk_snapshot,
			"def_snapshot": def_snapshot,
			"atk_hp_after": atk_hp_after,
			"def_hp_after": def_hp_after,
			"atk_alive": atk_alive,
			"def_alive": def_alive,
			"captives": sim.captives.get(0 if attacker_army.faction_id == player_fid else 1, 0) if player_won else 0,
			"loot_gold": _loot_gold if player_won else 0,
			"loot_iron": _loot_iron if player_won else 0,
		}
		_show_battle_report(report)

	# Refresh visuals
	_create_army_markers()

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

func _apply_camp_building_bonuses(army: ArmyState, cmd_bonuses: Dictionary) -> void:
	if army.camp_city_id == &"":
		return
	var camp_city: CityState = GameManager.state.cities.get(army.camp_city_id)
	if camp_city == null:
		return
	for bid in camp_city.buildings:
		var bdata: BuildingData = DataManager.get_building(bid)
		if bdata and bdata.special_effects.has("army_attack_bonus"):
			cmd_bonuses["attack_bonus"] = cmd_bonuses.get("attack_bonus", 0) + int(bdata.special_effects["army_attack_bonus"])

func _apply_auto_battle_results(army: ArmyState, survivors: Array[BattleSimulatorV2.BattleFormation]) -> void:
	var surviving_ids: Dictionary = {}
	for f in survivors:
		surviving_ids[f.instance_id] = f.current_hp

	var updated_units: Array[UnitInstance] = []
	for unit in army.units:
		if surviving_ids.has(unit.instance_id):
			unit.current_hp = surviving_ids[unit.instance_id]
			updated_units.append(unit)
	army.units = updated_units

func _handle_elderbeast_battle_aftermath(army: ArmyState) -> void:
	var beast: ElderbeastState = GameManager.state.elderbeasts.get(army.elderbeast_id)
	if beast == null:
		return
	# Check if beast unit survived in the army
	var beast_alive := false
	for unit in army.units:
		if unit.instance_id == beast.unit_instance_id:
			beast.hp = unit.current_hp
			beast_alive = true
			break
	if beast_alive:
		return
	# Beast unit was killed — check recovery eligibility
	var other_units_alive := army.units.size() > 0
	if other_units_alive and not beast.is_injured():
		# Recovery: beast flees with 1 HP and becomes injured for 3 turns
		beast.hp = 1
		beast.injured_turns = 3
		beast.movement_remaining = 0.0
		# Re-add beast unit to army at 1 HP
		var unit_data := DataManager.get_unit(beast.get_unit_data_id())
		if unit_data:
			var instance := UnitInstance.new()
			instance.instance_id = beast.unit_instance_id
			instance.unit_data_id = unit_data.id
			instance.current_hp = 1
			army.units.insert(0, instance)
		# Spawn emergency escort units (2 basic crystal swarmlings)
		var swarmling_data := DataManager.get_unit(&"crystal_swarmling")
		if swarmling_data:
			for i in 2:
				var escort := UnitInstance.new()
				escort.instance_id = StringName("emergency_%s_%d" % [beast.beast_id, i])
				escort.unit_data_id = &"crystal_swarmling"
				escort.current_hp = swarmling_data.max_hp
				army.units.append(escort)
	else:
		# Beast dies permanently (already injured, or entire army wiped)
		beast.hp = 0
		GameManager.state.elderbeasts.erase(beast.beast_id)
		EventBus.elderbeast_destroyed.emit(beast.beast_id, beast.faction_id)
		army.elderbeast_id = &""

func _grant_auto_veterancy_xp(army: ArmyState, survivors: Array[BattleSimulatorV2.BattleFormation], enemy_strength: int) -> void:
	var formation_damage: Dictionary = {} # instance_id -> damage_dealt
	for f in survivors:
		formation_damage[f.instance_id] = f.damage_dealt
	var base_xp := 8 + mini(enemy_strength / 50, 20)
	for unit in army.units:
		var dmg: int = formation_damage.get(unit.instance_id, 0)
		var damage_bonus := mini(dmg / 40, 10)
		unit.grant_xp(base_xp + damage_bonus)

func _separate_armies_stalemate(attacker: ArmyState, defender: ArmyState) -> void:
	# Defender stays at battle hex, attacker retreats to adjacent tile
	var battle_hex := defender.hex_pos
	var retreat_hex := _find_retreat_hex(attacker, battle_hex)
	if retreat_hex != Vector2i(-1, -1):
		attacker.hex_pos = retreat_hex
		GameManager.movement_system.invalidate_positions()
	else:
		# No valid retreat tile — push defender instead as fallback
		var def_retreat := _find_retreat_hex(defender, attacker.hex_pos)
		if def_retreat != Vector2i(-1, -1):
			defender.hex_pos = def_retreat
			GameManager.movement_system.invalidate_positions()

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
		_fog_dirty = true
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
	var route_color := Color(0.85, 0.7, 0.3, 0.5)

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
		_trade_route_draw_node.routes.append({points = pixel_path, color = route_color, faction_a = route.faction_a, faction_b = route.faction_b})
		_trade_route_data.append({pixel_path = pixel_path, progress = randf()})

		# Create caravan sprite (small gold dot)
		var caravan := _CaravanDrawNode.new()
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
		for j in pixel_path.size() - 1:
			var seg_len := pixel_path[j].distance_to(pixel_path[j + 1])
			if accumulated + seg_len >= target_dist:
				var seg_t := (target_dist - accumulated) / seg_len if seg_len > 0 else 0.0
				pos = pixel_path[j].lerp(pixel_path[j + 1], seg_t)
				break
			accumulated += seg_len
		caravan.position = pos
		# Check fog visibility at caravan position
		var caravan_hex := _pixel_to_hex(pos)
		caravan.visible = _is_tile_visible(caravan_hex) or GameManager.explored_tiles.has(caravan_hex)

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

	# Cache allied factions
	var allied_factions: Dictionary = {}
	for faction_id in DataManager.factions:
		if faction_id == player_id:
			continue
		var rel := GameManager.get_relation(player_id, faction_id)
		if rel == Enums.FactionRelation.FRIENDLY or rel == Enums.FactionRelation.ALLIED:
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
	if income.is_empty():
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
