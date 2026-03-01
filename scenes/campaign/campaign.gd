extends Node2D

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Wetlands", "Tundra", "Shard Wastes", "Water", "Jungle"]
const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]

# Hex outer radius (center to vertex) for flat-top hexes
const HEX_RADIUS := 32.0
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
const TERRAIN_COLORS := {
	Enums.TerrainType.PLAINS: Color(0.62, 0.58, 0.42),
	Enums.TerrainType.FOREST: Color(0.28, 0.38, 0.22),
	Enums.TerrainType.MOUNTAINS: Color(0.45, 0.42, 0.38),
	Enums.TerrainType.DESERT: Color(0.72, 0.62, 0.40),
	Enums.TerrainType.SWAMP: Color(0.30, 0.32, 0.22),
	Enums.TerrainType.WETLANDS: Color(0.48, 0.52, 0.42),
	Enums.TerrainType.TUNDRA: Color(0.58, 0.56, 0.52),
	Enums.TerrainType.SHARD_WASTES: Color(0.42, 0.28, 0.38),
	Enums.TerrainType.WATER: Color(0.22, 0.30, 0.38),
	Enums.TerrainType.JUNGLE: Color(0.20, 0.34, 0.18),
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
var _hex_visuals: Dictionary = {} # Vector2i -> Node2D (hex tile container)
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

# Cloud shadow overlay
var _cloud_shadow_node: ColorRect
var _cloud_shadow_material: ShaderMaterial
var _cloud_time := 0.0

# Pre-computed hex polygons keyed by radius (avoids recomputing trig every call)
var _hex_polygon_cache: Dictionary = {} # float -> PackedVector2Array
var _terrain_detail_node: Node2D  # Batched terrain detail draw node

# Fog of war
var _fog_of_war_enabled := true
var _fog_draw_node: Node2D = null  # Batched fog draw node
var _explored_tiles: Dictionary = {} # coord -> true (tiles that have been seen at least once)

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

func _ready() -> void:
	_render_hex_map()
	_draw_region_borders()
	_draw_faction_borders()
	_create_region_labels()
	_update_political_overlay()
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
	# Ensure labels render above region borders
	region_labels_node.z_index = 2
	city_markers_node.z_index = 2
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
		hud.building_queued.connect(func(): _create_building_tile_markers(); _update_fog_of_war())

	# Position camera on player's capital, fallback to map center
	var _cam_target := Vector2(HexMapData.MAP_WIDTH * HEX_H_SPACING * 0.5, HexMapData.MAP_HEIGHT * HEX_V_SPACING * 0.5)
	for cid in GameManager.state.cities:
		var c: CityState = GameManager.state.cities[cid]
		if c.faction_id == GameManager.state.player_faction_id and c.is_capital:
			_cam_target = _hex_to_pixel(c.hex_pos)
			break
	camera.position = _cam_target
	_cull_hex_tiles()

	AudioManager.play_faction_music(GameManager.state.player_faction_id, &"campaign")

	if not GameManager.has_meta("game_started"):
		GameManager.set_meta("game_started", true)
		TurnManager.start_game()
	elif GameManager.current_phase == Enums.GamePhase.CAMPAIGN:
		if not TurnManager.is_player_turn:
			TurnManager._end_current_faction_turn()

func _process(delta: float) -> void:
	# Animated tiles now handled by shaders (hex_water.gdshader, hex_shard.gdshader)

	# Cloud shadow animation
	_cloud_time += delta
	if _cloud_shadow_material:
		_cloud_shadow_material.set_shader_parameter("time_val", _cloud_time)

	# Refresh minimap on timer: dirty flag for content changes, camera for viewport
	_minimap_update_timer += delta
	if _minimap_update_timer >= 0.5:
		_minimap_update_timer = 0.0
		var cam_moved := camera and (camera.position != _minimap_last_cam_pos or camera.zoom.x != _minimap_last_cam_zoom)
		if cam_moved or _minimap_dirty:
			if camera:
				_minimap_last_cam_pos = camera.position
				_minimap_last_cam_zoom = camera.zoom.x
			_minimap_dirty = false
			_update_minimap()

	# Viewport culling for hex tiles
	if camera:
		var cam_pos := camera.position
		var cam_zoom := camera.zoom.x
		# Only re-cull when camera has moved significantly (>1 hex worth)
		var hex_threshold := 40.0  # approximately 1 hex width
		if cam_pos.distance_to(_last_cull_cam_pos) > hex_threshold or absf(cam_zoom - _last_cull_cam_zoom) > 0.05:
			_last_cull_cam_pos = cam_pos
			_last_cull_cam_zoom = cam_zoom
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
	var vp_size := get_viewport_rect().size
	var cam_pos := camera.position
	var cam_zoom := camera.zoom.x
	# Visible area in world space (with 2 hex margin)
	var margin := 80.0  # ~2 hexes
	var half_w := (vp_size.x / cam_zoom) / 2.0 + margin
	var half_h := (vp_size.y / cam_zoom) / 2.0 + margin
	var vis_rect := Rect2(cam_pos.x - half_w, cam_pos.y - half_h, half_w * 2.0, half_h * 2.0)

	for coord in _hex_visuals:
		var node: Node2D = _hex_visuals[coord]
		var node_pos := node.position
		node.visible = vis_rect.has_point(node_pos)

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
	for terrain in base_names:
		var variants: Array[Texture2D] = []
		# Try base name (no number)
		var base_path := "res://assets/sprites/campaign_map/%s.png" % base_names[terrain]
		if ResourceLoader.exists(base_path):
			variants.append(load(base_path))
		# Try numbered variants (1-9)
		for i in range(1, 10):
			var path := "res://assets/sprites/campaign_map/%s%d.png" % [base_names[terrain], i]
			if ResourceLoader.exists(path):
				variants.append(load(path))
			else:
				break
		if not variants.is_empty():
			_terrain_textures[terrain] = variants

func _render_hex_map() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	_load_terrain_textures()

	var border_poly := _make_hex_polygon(HEX_RADIUS)
	var fill_poly := _make_hex_polygon(HEX_RADIUS * 0.96)
	var fill_r := HEX_RADIUS * 0.96

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

	var _water_shader := load("res://assets/shaders/hex_water.gdshader") as Shader
	var _shard_shader := load("res://assets/shaders/hex_shard.gdshader") as Shader

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var base_color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		var elevation: float = TERRAIN_ELEVATION.get(tile.terrain, 0.0)
		_hex_elevations[coord] = elevation

		# Container node with vertical offset for elevation (no border child needed)
		var container := Node2D.new()
		container.position = Vector2(pixel_pos.x, pixel_pos.y - elevation)

		# Fill hex — pick a random texture variant based on tile coordinate
		var fill := Polygon2D.new()
		fill.polygon = fill_poly
		var variants: Array = _terrain_textures.get(tile.terrain, [])
		var tex: Texture2D = null
		if not variants.is_empty():
			var variant_idx := absi(coord.x * 7 + coord.y * 13 + coord.x * coord.y) % variants.size()
			tex = variants[variant_idx]
		if tex:
			fill.texture = tex
			# Center-crop a square region from the texture, zoomed in 15% to cut off
			# any asymmetric edges. Same scale on both axes ensures uniform hex shape.
			var tex_size := tex.get_size()
			var crop := minf(tex_size.x, tex_size.y) * 0.85
			var cx := tex_size.x * 0.5
			var cy := tex_size.y * 0.5
			var scaled_uv := PackedVector2Array()
			for uv in hex_uvs:
				scaled_uv.append(Vector2(cx + (uv.x - 0.5) * crop, cy + (uv.y - 0.5) * crop))
			fill.uv = scaled_uv
			fill.color = Color.WHITE
		else:
			fill.color = base_color
		container.add_child(fill)

		# Apply shader material for animated terrains
		if tile.terrain == Enums.TerrainType.WATER and _water_shader:
			var mat := ShaderMaterial.new()
			mat.shader = _water_shader
			mat.set_shader_parameter("base_color", base_color)
			fill.material = mat
		elif tile.terrain == Enums.TerrainType.SHARD_WASTES and _shard_shader:
			var mat := ShaderMaterial.new()
			mat.shader = _shard_shader
			mat.set_shader_parameter("base_color", base_color)
			fill.material = mat

		# Procedural terrain details (only for terrains without textures)
		if not tex:
			_add_terrain_detail(container, tile.terrain, fill_poly, base_color)

		hex_map_layer.add_child(container)
		_hex_visuals[coord] = container

	# Add batched terrain detail node (all terrain decorations in one draw call)
	hex_map_layer.add_child(_terrain_detail_node)

	# Draw elevation shadow edges after all tiles
	_draw_elevation_edges()

	# Draw thick outlines around mountain range edges (only outer edges)
	_draw_mountain_outlines()

func _draw_elevation_edges() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS * 0.96)
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

func _add_terrain_detail(container: Node2D, terrain: Enums.TerrainType, _hex_poly: PackedVector2Array, base_color: Color) -> void:
	# Collect terrain details into batched draw node instead of individual child nodes
	if _terrain_detail_node == null:
		return
	var pos := container.position  # World position of this hex
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
	var hex_points := _make_hex_polygon(HEX_RADIUS * 0.96)
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

	# Group cities by region for efficient lookup
	var region_cities: Dictionary = {}
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if not region_cities.has(city.region_id):
			region_cities[city.region_id] = []
		region_cities[city.region_id].append(city)

	# Visual Voronoi: every tile gets the faction of the closest city in its region
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id == &"":
			continue
		var rcities: Array = region_cities.get(tile.region_id, [])
		if rcities.is_empty():
			continue
		var closest_fid: StringName = &""
		var closest_dist := 999
		for city in rcities:
			var dist := HexHelper.hex_distance(coord, city.hex_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_fid = city.faction_id
		if closest_fid != &"":
			visual_owner[coord] = closest_fid

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

class _FogDrawNode extends Node2D:
	var tile_polys: Dictionary = {}   # coord -> PackedVector2Array (world-space)
	var tile_alphas: Dictionary = {}  # coord -> float (0.0=visible, 0.45=explored, 0.75=hidden)
	func _draw() -> void:
		var fog_base := Color(0.03, 0.02, 0.05)
		for coord in tile_alphas:
			var alpha: float = tile_alphas[coord]
			if alpha <= 0.0:
				continue
			draw_colored_polygon(tile_polys[coord], Color(fog_base.r, fog_base.g, fog_base.b, alpha))

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

func _update_political_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	for coord in _hex_visuals:
		var container: Node2D = _hex_visuals[coord]
		var tile: HexMapData.TileState = hex_map.tiles[coord]

		# The fill polygon is child 0 (borders are batched separately)
		if container.get_child_count() > 0:
			var fill: Polygon2D = container.get_child(0)
			var has_texture := fill.texture != null
			if _minimap_political_mode:
				if tile.owner_faction != &"" and tile.owner_faction != &"independent":
					var faction_data: FactionData = DataManager.get_faction(tile.owner_faction)
					if faction_data:
						# Use vibrant faction color — texture contours/patterns still show through
						var pol_color: Color = faction_data.color
						pol_color.s = minf(pol_color.s * 1.4, 1.0)  # Boost saturation
						fill.color = pol_color.lightened(0.15)
					else:
						fill.color = Color(0.35, 0.33, 0.3) if has_texture else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
				else:
					# Unowned: desaturated grey so owned territory pops
					fill.color = Color(0.35, 0.33, 0.3) if has_texture else TERRAIN_COLORS.get(tile.terrain, Color.GRAY).darkened(0.3)
			else:
				# Normal mode: subtle faction tint
				var base_color: Color = Color.WHITE if has_texture else TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
				if tile.owner_faction != &"" and tile.owner_faction != &"independent":
					var faction_data: FactionData = DataManager.get_faction(tile.owner_faction)
					if faction_data:
						base_color = base_color.lerp(faction_data.color, 0.12)
				fill.color = base_color

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

func _create_army_marker(army: ArmyState) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(army.hex_pos)
	var faction_data: FactionData = DataManager.get_faction(army.faction_id)
	var faction_color: Color = faction_data.color if faction_data else Color.WHITE

	# Banner/shield shape (pointed bottom)
	var shield_poly := PackedVector2Array([
		Vector2(-10, -12), Vector2(10, -12), Vector2(10, 4),
		Vector2(0, 12), Vector2(-10, 4)
	])

	# Outer border (gold/bronze)
	var border := Polygon2D.new()
	var border_poly := PackedVector2Array()
	for pt in shield_poly:
		border_poly.append(pt * 1.2)
	border.polygon = border_poly
	border.color = Color(0.72, 0.58, 0.3) # Bronze
	marker.add_child(border)

	# Inner shield fill
	var fill := Polygon2D.new()
	fill.polygon = shield_poly
	fill.color = faction_color
	marker.add_child(fill)

	# Unit count emblem
	var emblem := Polygon2D.new()
	emblem.polygon = _make_circle(6.0, 8)
	emblem.position = Vector2(0, -3)
	emblem.color = faction_color.darkened(0.3)
	marker.add_child(emblem)

	var label := Label.new()
	label.text = str(army.units.size())
	label.position = Vector2(-4, -10)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_child(label)

	# Top-edge highlight on shield for bevel effect
	var bevel_highlight := Line2D.new()
	bevel_highlight.points = PackedVector2Array([
		Vector2(-9, -11.5), Vector2(9, -11.5)
	])
	bevel_highlight.width = 1.5
	bevel_highlight.default_color = Color(1, 1, 1, 0.35)
	marker.add_child(bevel_highlight)

	# Small sword/spear cross icon on shield face
	var sword_v := Line2D.new()
	sword_v.points = PackedVector2Array([Vector2(0, -8), Vector2(0, 3)])
	sword_v.width = 1.2
	sword_v.default_color = Color(1, 1, 1, 0.5)
	marker.add_child(sword_v)
	var sword_h := Line2D.new()
	sword_h.points = PackedVector2Array([Vector2(-3.5, -4), Vector2(3.5, -4)])
	sword_h.width = 1.2
	sword_h.default_color = Color(1, 1, 1, 0.5)
	marker.add_child(sword_h)

	# Banner pole extending above shield
	var banner_pole := Line2D.new()
	banner_pole.points = PackedVector2Array([Vector2(6, -12), Vector2(6, -28)])
	banner_pole.width = 1.5
	banner_pole.default_color = Color(0.55, 0.42, 0.22)
	marker.add_child(banner_pole)

	# Triangular pennant flag at pole top in faction color
	var pennant := Polygon2D.new()
	pennant.polygon = PackedVector2Array([
		Vector2(6, -28), Vector2(6, -20), Vector2(16, -24)
	])
	pennant.color = faction_color
	marker.add_child(pennant)

	# Inner stripe on flag for detail
	var flag_stripe := Polygon2D.new()
	flag_stripe.polygon = PackedVector2Array([
		Vector2(6, -25.5), Vector2(6, -22.5), Vector2(13, -24)
	])
	flag_stripe.color = faction_color.lightened(0.3)
	marker.add_child(flag_stripe)

	# Selection ring (hidden by default, shown when selected)
	var sel_ring := Polygon2D.new()
	sel_ring.name = "SelectionRing"
	sel_ring.polygon = _make_circle(16.0, 12)
	sel_ring.color = Color(1, 0.85, 0.2, 0.35)
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

	if city.is_settlement:
		# Settlement icon: smaller house shape
		var house := Polygon2D.new()
		house.polygon = PackedVector2Array([
			Vector2(-7, 4), Vector2(-7, -3), Vector2(0, -9), Vector2(7, -3), Vector2(7, 4)
		])
		house.color = faction_color.darkened(0.15)
		marker.add_child(house)

		# Thatch texture: 2-3 horizontal stripes on roof
		var thatch1 := Line2D.new()
		thatch1.points = PackedVector2Array([Vector2(-5, -5), Vector2(5, -5)])
		thatch1.width = 0.8
		thatch1.default_color = faction_color.darkened(0.35)
		marker.add_child(thatch1)
		var thatch2 := Line2D.new()
		thatch2.points = PackedVector2Array([Vector2(-3.5, -7), Vector2(3.5, -7)])
		thatch2.width = 0.8
		thatch2.default_color = faction_color.darkened(0.35)
		marker.add_child(thatch2)
		var thatch3 := Line2D.new()
		thatch3.points = PackedVector2Array([Vector2(-1.5, -8.5), Vector2(1.5, -8.5)])
		thatch3.width = 0.7
		thatch3.default_color = faction_color.darkened(0.35)
		marker.add_child(thatch3)

		# Small chimney rectangle on roof side
		var chimney := Polygon2D.new()
		chimney.polygon = PackedVector2Array([
			Vector2(3, -6), Vector2(5, -6), Vector2(5, -9), Vector2(3, -9)
		])
		chimney.color = faction_color.darkened(0.45)
		marker.add_child(chimney)

		# Warm-glowing window square on house face
		var window := Polygon2D.new()
		window.polygon = PackedVector2Array([
			Vector2(-5, -1), Vector2(-3, -1), Vector2(-3, 1), Vector2(-5, 1)
		])
		window.color = Color(0.95, 0.8, 0.35, 0.9)
		marker.add_child(window)

		# Door
		var door := Polygon2D.new()
		door.polygon = PackedVector2Array([
			Vector2(-2, 4), Vector2(-2, 0), Vector2(2, 0), Vector2(2, 4)
		])
		door.color = faction_color.darkened(0.4)
		marker.add_child(door)
	else:
		# City/Capital icon: castle with towers

		# Drop shadow (offset darker copy beneath the city)
		var shadow_offset := Vector2(2, 3)
		var shadow_color := Color(0, 0, 0, 0.3)
		var shadow_base := Polygon2D.new()
		shadow_base.polygon = PackedVector2Array([
			Vector2(-10, -8) + shadow_offset, Vector2(10, -8) + shadow_offset,
			Vector2(10, 8) + shadow_offset, Vector2(-10, 8) + shadow_offset
		])
		shadow_base.color = shadow_color
		shadow_base.z_index = -1
		marker.add_child(shadow_base)
		var shadow_tl := Polygon2D.new()
		shadow_tl.polygon = PackedVector2Array([
			Vector2(-12, -14) + shadow_offset, Vector2(-6, -14) + shadow_offset,
			Vector2(-6, -6) + shadow_offset, Vector2(-12, -6) + shadow_offset
		])
		shadow_tl.color = shadow_color
		shadow_tl.z_index = -1
		marker.add_child(shadow_tl)
		var shadow_tr := Polygon2D.new()
		shadow_tr.polygon = PackedVector2Array([
			Vector2(6, -14) + shadow_offset, Vector2(12, -14) + shadow_offset,
			Vector2(12, -6) + shadow_offset, Vector2(6, -6) + shadow_offset
		])
		shadow_tr.color = shadow_color
		shadow_tr.z_index = -1
		marker.add_child(shadow_tr)
		var shadow_tc := Polygon2D.new()
		shadow_tc.polygon = PackedVector2Array([
			Vector2(-4, -18) + shadow_offset, Vector2(4, -18) + shadow_offset,
			Vector2(4, -6) + shadow_offset, Vector2(-4, -6) + shadow_offset
		])
		shadow_tc.color = shadow_color
		shadow_tc.z_index = -1
		marker.add_child(shadow_tc)

		var base := Polygon2D.new()
		base.polygon = PackedVector2Array([
			Vector2(-10, -8), Vector2(10, -8), Vector2(10, 8),
			Vector2(-10, 8)
		])
		base.color = faction_color.darkened(0.2)
		marker.add_child(base)

		# Dark arch gate shape at base center
		var gate := Polygon2D.new()
		gate.polygon = PackedVector2Array([
			Vector2(-3, 8), Vector2(-3, 3), Vector2(-2, 1),
			Vector2(0, 0), Vector2(2, 1), Vector2(3, 3), Vector2(3, 8)
		])
		gate.color = Color(0.08, 0.05, 0.05, 0.85)
		marker.add_child(gate)

		# Tower left
		var tower_l := Polygon2D.new()
		tower_l.polygon = PackedVector2Array([
			Vector2(-12, -14), Vector2(-6, -14), Vector2(-6, -6), Vector2(-12, -6)
		])
		tower_l.color = faction_color.darkened(0.1)
		marker.add_child(tower_l)

		# Left tower crenellations (2 teeth)
		var cren_l1 := Polygon2D.new()
		cren_l1.polygon = PackedVector2Array([
			Vector2(-12, -16.5), Vector2(-10, -16.5), Vector2(-10, -14), Vector2(-12, -14)
		])
		cren_l1.color = faction_color.darkened(0.1)
		marker.add_child(cren_l1)
		var cren_l2 := Polygon2D.new()
		cren_l2.polygon = PackedVector2Array([
			Vector2(-8, -16.5), Vector2(-6, -16.5), Vector2(-6, -14), Vector2(-8, -14)
		])
		cren_l2.color = faction_color.darkened(0.1)
		marker.add_child(cren_l2)

		# Tower right
		var tower_r := Polygon2D.new()
		tower_r.polygon = PackedVector2Array([
			Vector2(6, -14), Vector2(12, -14), Vector2(12, -6), Vector2(6, -6)
		])
		tower_r.color = faction_color.darkened(0.1)
		marker.add_child(tower_r)

		# Right tower crenellations (2 teeth)
		var cren_r1 := Polygon2D.new()
		cren_r1.polygon = PackedVector2Array([
			Vector2(6, -16.5), Vector2(8, -16.5), Vector2(8, -14), Vector2(6, -14)
		])
		cren_r1.color = faction_color.darkened(0.1)
		marker.add_child(cren_r1)
		var cren_r2 := Polygon2D.new()
		cren_r2.polygon = PackedVector2Array([
			Vector2(10, -16.5), Vector2(12, -16.5), Vector2(12, -14), Vector2(10, -14)
		])
		cren_r2.color = faction_color.darkened(0.1)
		marker.add_child(cren_r2)

		# Center tower (taller)
		var is_player_capital := city.is_capital and city.faction_id == GameManager.state.player_faction_id
		var tower_c := Polygon2D.new()
		tower_c.polygon = PackedVector2Array([
			Vector2(-4, -18), Vector2(4, -18), Vector2(4, -6), Vector2(-4, -6)
		])
		tower_c.color = faction_color.lightened(0.15) if is_player_capital else faction_color
		marker.add_child(tower_c)

		# Center tower crenellations (3 narrower teeth)
		var cren_c1 := Polygon2D.new()
		cren_c1.polygon = PackedVector2Array([
			Vector2(-4, -20), Vector2(-2.5, -20), Vector2(-2.5, -18), Vector2(-4, -18)
		])
		cren_c1.color = faction_color.lightened(0.15) if is_player_capital else faction_color
		marker.add_child(cren_c1)
		var cren_c2 := Polygon2D.new()
		cren_c2.polygon = PackedVector2Array([
			Vector2(-0.75, -20), Vector2(0.75, -20), Vector2(0.75, -18), Vector2(-0.75, -18)
		])
		cren_c2.color = faction_color.lightened(0.15) if is_player_capital else faction_color
		marker.add_child(cren_c2)
		var cren_c3 := Polygon2D.new()
		cren_c3.polygon = PackedVector2Array([
			Vector2(2.5, -20), Vector2(4, -20), Vector2(4, -18), Vector2(2.5, -18)
		])
		cren_c3.color = faction_color.lightened(0.15) if is_player_capital else faction_color
		marker.add_child(cren_c3)

		# Faction banner detail (small colored triangle on tallest tower)
		var banner := Polygon2D.new()
		banner.polygon = PackedVector2Array([
			Vector2(4, -17), Vector2(8, -14), Vector2(4, -11)
		])
		banner.color = faction_color.lightened(0.25)
		marker.add_child(banner)

		# Gold diamond indicator on player capital
		if is_player_capital:
			var crown := Polygon2D.new()
			crown.polygon = PackedVector2Array([
				Vector2(0, -26), Vector2(4, -22), Vector2(0, -18), Vector2(-4, -22)
			])
			crown.color = Color(0.95, 0.85, 0.3)
			marker.add_child(crown)

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
		var glow_tween := create_tween().set_loops()
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
		var htween := create_tween().set_loops()
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
	var player_id := GameManager.state.player_faction_id
	var outline_color: Color
	if city.faction_id == player_id:
		outline_color = Color(0.3, 0.5, 1.0)  # Blue — own city
	elif city.faction_id == &"" or city.faction_id == &"independent" or city.faction_id == &"rebels":
		outline_color = Color(0.9, 0.9, 0.9)  # White — neutral
	else:
		var relation := GameManager.get_relation(player_id, city.faction_id)
		if relation == Enums.FactionRelation.ALLIED:
			outline_color = Color(0.2, 0.85, 0.3)  # Green — allied
		elif relation == Enums.FactionRelation.WAR or relation == Enums.FactionRelation.HOSTILE:
			outline_color = Color(0.95, 0.2, 0.15)  # Red — enemy
		elif relation == Enums.FactionRelation.FRIENDLY:
			outline_color = Color(0.2, 0.85, 0.3, 0.7)  # Light green — friendly
		else:
			outline_color = Color(0.9, 0.9, 0.9)  # White — neutral
	outline.default_color = outline_color
	outline.points = PackedVector2Array([
		Vector2(-12, -20), Vector2(12, -20), Vector2(12, 8),
		Vector2(-12, 8), Vector2(-12, -20)
	])
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

	# Category-colored diamond shape at center of hex
	var cat_color: Color = BUILDING_CATEGORY_COLORS.get(
		building.category if building else &"economic",
		Color(0.5, 0.5, 0.5, 0.7)
	)
	if under_construction:
		cat_color.a = 0.35 # fainter for buildings in progress

	# Small diamond (rotated square)
	var diamond := Polygon2D.new()
	var s := 5.0
	diamond.polygon = PackedVector2Array([
		Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)
	])
	diamond.color = cat_color
	marker.add_child(diamond)

	# Faction-colored ring around the diamond
	var ring := Line2D.new()
	ring.width = 1.0
	ring.default_color = Color(faction_color.r, faction_color.g, faction_color.b, 0.6 if not under_construction else 0.3)
	var ring_r := 7.0
	var ring_pts := PackedVector2Array()
	for i in 8:
		var angle := TAU * i / 8.0
		ring_pts.append(Vector2(cos(angle) * ring_r, sin(angle) * ring_r))
	ring_pts.append(ring_pts[0]) # close the loop
	ring.points = ring_pts
	marker.add_child(ring)

	# Construction scaffolding indicator (small lines)
	if under_construction:
		var scaffold := Line2D.new()
		scaffold.width = 1.0
		scaffold.default_color = Color(0.7, 0.6, 0.3, 0.5)
		scaffold.points = PackedVector2Array([Vector2(-4, -3), Vector2(0, -7), Vector2(4, -3)])
		marker.add_child(scaffold)

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
	var tween := create_tween().set_loops()
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
	var tween2 := create_tween().set_loops()
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
	_update_fog_of_war()

func _animate_siege_ring(ring: Polygon2D) -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(ring, "modulate:a", 0.3, 0.6)
	tween.tween_property(ring, "modulate:a", 1.0, 0.6)

## Rebuild city markers only when something has changed (_city_markers_dirty).
## Multiple callers in the same frame will only trigger one actual rebuild.
func _refresh_city_markers() -> void:
	if not _city_markers_dirty:
		return
	_city_markers_dirty = false
	_create_city_markers()
	_create_building_tile_markers()
	_update_city_glow_states()
	_update_fog_of_war()

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

func _city_has_available_action(city: CityState) -> bool:
	if not city.build_queue.is_empty():
		return false
	var available := GameManager.city_system.get_available_buildings(city)
	return available.size() > 0

func _add_build_glow(marker: Node2D) -> void:
	var glow := Polygon2D.new()
	glow.name = "BuildGlow"
	glow.polygon = _make_circle(20.0, 12)
	glow.color = Color(0.2, 0.8, 0.3, 0.25)
	glow.z_index = -1
	marker.add_child(glow)
	var tween := create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.4, 1.0)
	tween.tween_property(glow, "modulate:a", 1.0, 1.0)

func _add_settle_glow(marker: Node2D) -> void:
	var glow := Polygon2D.new()
	glow.name = "SettleGlow"
	glow.polygon = _make_circle(22.0, 12)
	glow.color = Color(0.95, 0.85, 0.2, 0.3)
	glow.z_index = -1
	marker.add_child(glow)
	var tween := create_tween().set_loops()
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
					_update_fog_of_war()
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
				_update_fog_of_war()
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
			KEY_A:
				$UILayer/HUD._toggle_army_overview()

	# Hover: region highlighting + path preview
	if event is InputEventMouseMotion:
		var world_pos := get_global_mouse_position()
		_update_region_hover(world_pos)
		if selected_army_id != &"":
			var hex_coord := _pixel_to_hex(world_pos)
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
		_update_fog_of_war()
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
				var tween := create_tween()
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
		_update_fog_of_war()
		if is_player_army:
			_update_political_overlay()
		_minimap_dirty = true
	elif is_player_army:
		# Player army moved — always update fog
		_update_fog_of_war()
		_minimap_dirty = true

func _on_army_destroyed(army_id: StringName, _faction_id: StringName) -> void:
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		marker.queue_free()
		_army_markers.erase(army_id)

func _on_region_ownership_changed(_region_id: StringName, _old: StringName, _new: StringName) -> void:
	_update_political_overlay()
	_refresh_faction_borders()
	_update_fog_of_war()
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

	# Grant veterancy XP to surviving units
	_grant_auto_veterancy_xp(attacker_army, atk_survivors, def_strength_pre)
	_grant_auto_veterancy_xp(defender_army, def_survivors, atk_strength_pre)

	var atk_alive := atk_survivors.size() > 0
	var def_alive := def_survivors.size() > 0

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

	# Garrison assault failure: attacker didn't win — force retreat 1 tile
	var garrison_retreat := false
	var def_faction_id := defender_army.faction_id
	if defender_army.is_garrison and def_alive:
		# Attacker failed to defeat garrison — retreat with survivors or die
		GameManager.remove_army(defender_id) # garrison regenerates next attack
		def_alive = false
		if atk_alive:
			# Retreat attacker 1 tile back from the city
			var retreat_hex := _find_retreat_hex(attacker_army, hex_pos)
			if retreat_hex != Vector2i(-1, -1):
				attacker_army.hex_pos = retreat_hex
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
	if atk_alive and not def_alive:
		var loot_gold := int(def_strength_pre * 0.1)
		var loot_iron := int(def_strength_pre * 0.03)
		var wfs: FactionState = GameManager.state.faction_states.get(attacker_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + loot_iron
	elif def_alive and not atk_alive:
		var loot_gold := int(atk_strength_pre * 0.1)
		var loot_iron := int(atk_strength_pre * 0.03)
		var wfs: FactionState = GameManager.state.faction_states.get(defender_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + loot_iron

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
		var report := {
			"atk_faction": attacker_army.faction_id,
			"def_faction": defender_army.faction_id,
			"atk_snapshot": atk_snapshot,
			"def_snapshot": def_snapshot,
			"atk_hp_after": atk_hp_after,
			"def_hp_after": def_hp_after,
			"atk_alive": atk_alive,
			"def_alive": def_alive,
			"captives": sim.captives.get(0 if attacker_army.faction_id == player_fid else 1, 0),
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

func _grant_auto_veterancy_xp(army: ArmyState, survivors: Array[BattleSimulatorV2.BattleFormation], enemy_strength: int) -> void:
	var formation_damage: Dictionary = {} # instance_id -> damage_dealt
	for f in survivors:
		formation_damage[f.instance_id] = f.damage_dealt
	var base_xp := 8 + mini(enemy_strength / 50, 20)
	for unit in army.units:
		var dmg: int = formation_damage.get(unit.instance_id, 0)
		var damage_bonus := mini(dmg / 40, 10)
		unit.grant_xp(base_xp + damage_bonus)

func _separate_armies_stalemate(army_a: ArmyState, army_b: ArmyState) -> void:
	var hex_map := GameManager.state.hex_map
	# Move army_a away from army_b
	var best_a := army_a.hex_pos
	var best_a_dist := 0
	for neighbor in HexHelper.get_neighbors(army_a.hex_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(neighbor) if hex_map else null
		if tile and tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(neighbor, army_b.hex_pos)
		if dist > best_a_dist:
			best_a_dist = dist
			best_a = neighbor
	# Move army_b away from army_a
	var best_b := army_b.hex_pos
	var best_b_dist := 0
	for neighbor in HexHelper.get_neighbors(army_b.hex_pos):
		if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			continue
		var tile := hex_map.get_tile(neighbor) if hex_map else null
		if tile and tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(neighbor, army_a.hex_pos)
		if dist > best_b_dist:
			best_b_dist = dist
			best_b = neighbor
	army_a.hex_pos = best_a
	army_b.hex_pos = best_b

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
		# Full marker refresh only on player turn
		_city_markers_dirty = true
		_refresh_city_markers()
		_minimap_terrain_dirty = true
		# Full visual refresh only on player turn (army markers, fog, minimap)
		_create_army_markers()
		_create_elderbeast_markers()
		_update_fog_of_war()
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
	var tween := create_tween().set_loops()
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
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			var faction: FactionData = DataManager.get_faction(new_owner)
			var fname: String = faction.display_name if faction else str(new_owner)
			_show_notification(fname + " captured " + city.get_display_name() + "!")
	_city_markers_dirty = true
	_refresh_city_markers()
	_update_political_overlay()
	_refresh_faction_borders()
	_minimap_terrain_dirty = true

func _on_siege_started(city_id: StringName, faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			var faction: FactionData = DataManager.get_faction(faction_id)
			var fname: String = faction.display_name if faction else str(faction_id)
			_show_notification(fname + " is besieging " + city.get_display_name() + "!")
	_city_markers_dirty = true
	_refresh_city_markers()

func _on_siege_broken(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			_show_notification("Siege of " + city.get_display_name() + " broken!")
	_city_markers_dirty = true
	_refresh_city_markers()

func _on_building_completed(city_id: StringName, building_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"build_complete")
		var building: BuildingData = DataManager.get_building(building_id)
		var bname: String = building.display_name if building else str(building_id)
		_show_notification(bname + " completed in " + city.get_display_name())
	_update_city_glow_states()
	_create_building_tile_markers()
	_update_fog_of_war()

func _on_building_demolished(city_id: StringName, _building_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		_show_notification("Building demolished in " + city.get_display_name())
	_city_markers_dirty = true
	_refresh_city_markers()

func _on_battle_resolved_sfx(_winner_faction: StringName, hex_pos: Vector2i) -> void:
	if _is_tile_visible(hex_pos):
		AudioManager.play_sfx(&"battle_hit")

func _on_unit_recruited(city_id: StringName, unit_data_id: StringName, _army_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		var unit_data: UnitData = DataManager.get_unit(unit_data_id)
		var uname: String = unit_data.display_name if unit_data else str(unit_data_id)
		_show_notification(uname + " recruited in " + city.get_display_name())
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
	fog_overlay_node.add_child(_fog_draw_node)
	_update_fog_of_war()

var _visible_tile_cache: Dictionary = {}  # coord -> bool, rebuilt per fog update

func _rebuild_visible_tile_cache() -> void:
	_visible_tile_cache.clear()
	if not _fog_of_war_enabled:
		return
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var player_id := GameManager.state.player_faction_id

	# Cache allied factions
	var allied_factions: Dictionary = {}
	for faction_id in DataManager.factions:
		if faction_id == player_id:
			continue
		var rel := GameManager.get_relation(player_id, faction_id)
		if rel == Enums.FactionRelation.FRIENDLY or rel == Enums.FactionRelation.ALLIED:
			allied_factions[faction_id] = true

	# Fast pass: mark all player-owned and ally-owned tiles visible
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.owner_faction == player_id:
			_visible_tile_cache[coord] = true
		elif tile.owner_faction != &"" and allied_factions.has(tile.owner_faction):
			_visible_tile_cache[coord] = true

	# BFS from player cities (radius 2) — O(cities * radius^2) instead of O(tiles * cities)
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
		for coord in _fog_draw_node.tile_alphas:
			var visible_tile: bool = bool(_visible_tile_cache.get(coord, false)) if _fog_of_war_enabled else true
			var new_alpha: float
			if visible_tile:
				_explored_tiles[coord] = true
				new_alpha = 0.0
			elif _explored_tiles.has(coord):
				new_alpha = 0.45
			else:
				new_alpha = 0.75
			if _fog_draw_node.tile_alphas[coord] != new_alpha:
				_fog_draw_node.tile_alphas[coord] = new_alpha
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
			var explored := _explored_tiles.has(city.hex_pos)
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
			var explored := _explored_tiles.has(bhex)
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
	# Check visible tiles for faction ownership
	var hex_map := GameManager.state.hex_map
	if hex_map:
		for coord in _visible_tile_cache:
			if not _visible_tile_cache[coord]:
				continue
			var tile: HexMapData.TileState = hex_map.tiles.get(coord)
			if tile and tile.owner_faction != &"" and tile.owner_faction != player_id:
				enc[tile.owner_faction] = true
	# Check visible cities
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == player_id or city.faction_id == &"" or city.faction_id == &"independent":
			continue
		if _visible_tile_cache.get(city.hex_pos, false) or _explored_tiles.has(city.hex_pos):
			enc[city.faction_id] = true
	# Check visible armies
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id or army.faction_id == &"":
			continue
		if _visible_tile_cache.get(army.hex_pos, false):
			enc[army.faction_id] = true
	# Also mark factions we have diplomatic relations with (war, alliance, etc.)
	for key in GameManager.state.diplomacy:
		var parts := str(key).split(":")
		if parts.size() != 2:
			continue
		if parts[0] == str(player_id):
			enc[StringName(parts[1])] = true
		elif parts[1] == str(player_id):
			enc[StringName(parts[0])] = true

# ── Settlement Placement Mode ─────────────────────────────────

func _on_settlement_placement_requested(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	_settlement_placement_mode = true
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

const MINIMAP_SIZE := Vector2(380, 240)
const MINIMAP_MARGIN := Vector2(10, 10)
var _minimap_panel: PanelContainer
var _minimap_image: TextureRect
var _minimap_political_mode := false
var _minimap_dragging := false
var _minimap_terrain_cache: Image  # Cached terrain-only base image (no fog/armies/viewport)
var _minimap_terrain_dirty := true  # True when territory/ownership changes require terrain recache
var _minimap_fogged_cache: Image  # Terrain + fog dimming (no armies/viewport)
var _minimap_fog_dirty := true  # True when fog state changes

func _create_minimap() -> void:
	# Outer container for button + minimap
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 2)

	# Political toggle button above the minimap
	var toggle_btn := Button.new()
	toggle_btn.text = "Political View"
	toggle_btn.toggle_mode = true
	toggle_btn.custom_minimum_size = Vector2(0, 24)
	toggle_btn.add_theme_font_size_override("font_size", 11)
	toggle_btn.toggled.connect(func(pressed: bool):
		_minimap_political_mode = pressed
		toggle_btn.text = "Terrain View" if pressed else "Political View"
		_minimap_terrain_dirty = true
		_update_minimap()
		_update_political_overlay()
	)
	outer_vbox.add_child(toggle_btn)

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

	# Position in bottom-right of screen
	outer_vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	outer_vbox.anchor_left = 1.0
	outer_vbox.anchor_top = 1.0
	outer_vbox.anchor_right = 1.0
	outer_vbox.anchor_bottom = 1.0
	outer_vbox.offset_left = -MINIMAP_SIZE.x - MINIMAP_MARGIN.x - 12
	outer_vbox.offset_top = -MINIMAP_SIZE.y - MINIMAP_MARGIN.y - 38
	outer_vbox.offset_right = -MINIMAP_MARGIN.x
	outer_vbox.offset_bottom = -MINIMAP_MARGIN.y

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
			if _minimap_political_mode:
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = faction_colors[tile.owner_faction].darkened(0.15)
				else:
					color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3)).darkened(0.3)
			else:
				color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3))
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = color.lerp(faction_colors[tile.owner_faction], 0.15)
				color = color.darkened(0.3)
			var px := x * 4
			var py := y * 4
			for dx in 4:
				for dy in 4:
					if px + dx < px_w and py + dy < px_h:
						img.set_pixel(px + dx, py + dy, color)

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
				var is_explored: bool = bool(_explored_tiles.get(coord, false))
				var px := x * 4
				var py := y * 4
				if not is_explored:
					for ddx in 4:
						for ddy in 4:
							if px + ddx < px_w and py + ddy < px_h:
								img.set_pixel(px + ddx, py + ddy, dark_color)
				else:
					for ddx in 4:
						for ddy in 4:
							if px + ddx < px_w and py + ddy < px_h:
								var c: Color = img.get_pixel(px + ddx, py + ddy)
								img.set_pixel(px + ddx, py + ddy, c.darkened(explored_dim))

	# Dim explored-but-not-visible cities
	if _fog_of_war_enabled:
		for city_id in GameManager.state.cities:
			var city: CityState = GameManager.state.cities[city_id]
			if not bool(_visible_tile_cache.get(city.hex_pos, false)) and bool(_explored_tiles.get(city.hex_pos, false)):
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

	# Draw camera viewport indicator
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_top_left := camera.position - viewport_size / 2.0
	var cam_bottom_right := camera.position + viewport_size / 2.0
	var map_pixel_w := float(w) * HEX_H_SPACING
	var map_pixel_h := float(h) * HEX_V_SPACING
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

	_minimap_image.texture = ImageTexture.create_from_image(img)

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
	_update_minimap()
