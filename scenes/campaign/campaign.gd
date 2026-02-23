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
var _reachable_tiles: Dictionary = {} # coord -> remaining_mp
var _army_markers: Dictionary = {} # army_id -> Node2D
var _shard_markers: Dictionary = {} # shard_id -> Node2D
var _hex_visuals: Dictionary = {} # Vector2i -> Node2D (hex tile container)
var _city_markers: Dictionary = {} # city_id -> Node2D
var _is_animating_move := false # Block input during movement animation
var _hovered_region_id: StringName = &"" # Currently hovered region for highlighting
var _region_highlight_nodes: Array[Node2D] = [] # Highlight overlay polygons for hovered region
var _region_tiles_cache: Dictionary = {} # region_id -> Array[Vector2i]
var _city_panel_open := false
var _selected_city_id: StringName = &""
var _elderbeast_markers: Dictionary = {} # beast_id -> Node2D
var _building_tile_markers: Array[Node2D] = [] # building markers on hex tiles

# Animated terrain timers
var _water_timer: float = 0.0
var _shard_waste_timer: float = 0.0
var _animated_tiles: Array[Dictionary] = []  # [{coord, fill, terrain, base_color}] — cached for perf

# Minimap viewport tracking (to refresh when camera moves/zooms)
var _minimap_last_cam_pos := Vector2.ZERO
var _minimap_last_cam_zoom := 1.0
var _minimap_update_timer := 0.0

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

# Fog of war
var _fog_of_war_enabled := true
var _fog_overlay_nodes: Dictionary = {} # coord -> Polygon2D
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
	EventBus.unit_recruited.connect(_on_unit_recruited)
	EventBus.shard_claimed.connect(_on_shard_claimed)
	EventBus.shard_expired.connect(_on_shard_expired)
	EventBus.battle_resolved.connect(_on_battle_resolved_sfx)

	_recreate_shard_markers()
	_create_elderbeast_markers()
	_build_region_tiles_cache()
	_create_fog_overlay()
	_create_minimap()
	EventBus.elderbeast_moved.connect(_on_elderbeast_moved)

	# Connect settlement placement signal from HUD
	var hud: Control = $UILayer/HUD
	if hud.has_signal("settlement_placement_requested"):
		hud.settlement_placement_requested.connect(_on_settlement_placement_requested)
	if hud.has_signal("building_tile_selection_requested"):
		hud.building_tile_selection_requested.connect(_on_building_tile_selection_requested)
	if hud.has_signal("building_queued"):
		hud.building_queued.connect(_create_building_tile_markers)

	# Position camera on player's capital, fallback to map center
	var _cam_target := Vector2(HexMapData.MAP_WIDTH * HEX_H_SPACING * 0.5, HexMapData.MAP_HEIGHT * HEX_V_SPACING * 0.5)
	for cid in GameManager.state.cities:
		var c: CityState = GameManager.state.cities[cid]
		if c.faction_id == GameManager.state.player_faction_id and c.is_capital:
			_cam_target = _hex_to_pixel(c.hex_pos)
			break
	camera.position = _cam_target

	AudioManager.play_faction_music(GameManager.state.player_faction_id, &"campaign")

	if not GameManager.has_meta("game_started"):
		GameManager.set_meta("game_started", true)
		TurnManager.start_game()
	elif GameManager.current_phase == Enums.GamePhase.CAMPAIGN:
		if not TurnManager.is_player_turn:
			TurnManager._end_current_faction_turn()

func _process(delta: float) -> void:
	# Animated water color cycling
	_water_timer += delta * 0.5
	# Shard waste shimmer
	_shard_waste_timer += delta * 1.2

	# Pre-compute sin values once per frame
	var water_sin1 := 0.02 * sin(_water_timer * 2.0)
	var water_sin2 := 0.04 * sin(_water_timer)
	var shard_sin1 := 0.04 * sin(_shard_waste_timer)
	var shard_sin2 := 0.06 * sin(_shard_waste_timer * 0.7)

	# Only iterate cached animated tiles (water + shard_wastes)
	for entry in _animated_tiles:
		var bc: Color = entry.base_color
		if entry.terrain == Enums.TerrainType.WATER:
			entry.fill.color = bc + Color(0, water_sin1, water_sin2, 0)
		else:
			entry.fill.color = bc + Color(shard_sin1, 0, shard_sin2, 0)

	# Refresh minimap viewport rect when camera moves or zooms
	_minimap_update_timer += delta
	if _minimap_update_timer >= 0.2:
		_minimap_update_timer = 0.0
		if camera and (camera.position != _minimap_last_cam_pos or camera.zoom.x != _minimap_last_cam_zoom):
			_minimap_last_cam_pos = camera.position
			_minimap_last_cam_zoom = camera.zoom.x
			_update_minimap()

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
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

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

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var base_color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		var elevation: float = TERRAIN_ELEVATION.get(tile.terrain, 0.0)
		_hex_elevations[coord] = elevation

		# Container node with vertical offset for elevation
		var container := Node2D.new()
		container.position = Vector2(pixel_pos.x, pixel_pos.y - elevation)

		# Border hex (slightly larger)
		var border := Polygon2D.new()
		border.polygon = border_poly
		border.color = HEX_BORDER_COLOR
		container.add_child(border)

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

		# Procedural terrain details (only for terrains without textures)
		if not tex:
			_add_terrain_detail(container, tile.terrain, fill_poly, base_color)

		hex_map_layer.add_child(container)
		_hex_visuals[coord] = container

	# Cache animated tiles (water + shard wastes) for fast _process iteration
	_animated_tiles.clear()
	for coord in _hex_visuals:
		var tile: HexMapData.TileState = hex_map.tiles.get(coord)
		if tile == null:
			continue
		if tile.terrain != Enums.TerrainType.WATER and tile.terrain != Enums.TerrainType.SHARD_WASTES:
			continue
		var cont: Node2D = _hex_visuals[coord]
		if cont.get_child_count() <= 1:
			continue
		var f: Polygon2D = cont.get_child(1)
		var has_tex := f.texture != null
		var bc: Color = Color.WHITE if has_tex else TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
		if tile.owner_faction != &"":
			var fd: FactionData = DataManager.get_faction(tile.owner_faction)
			if fd:
				bc = bc.lerp(fd.color, 0.12)
		_animated_tiles.append({coord = coord, fill = f, terrain = tile.terrain, base_color = bc})

	# Draw elevation shadow edges after all tiles
	_draw_elevation_edges()

	# Draw thick outlines around mountain range edges (only outer edges)
	_draw_mountain_outlines()

func _draw_elevation_edges() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS * 0.96)
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

			# Draw shadow quad on the lower side of the shared edge
			var e: int = edge_lut[i]
			var v1: Vector2 = my_pixel + hex_points[e]
			var v2: Vector2 = my_pixel + hex_points[(e + 1) % 6]
			# Offset vertices down by elevation difference
			var drop := elev_diff * 1.5
			var shadow_poly := PackedVector2Array([
				Vector2(v1.x, v1.y - my_elev),
				Vector2(v2.x, v2.y - my_elev),
				Vector2(v2.x, v2.y - my_elev + drop),
				Vector2(v1.x, v1.y - my_elev + drop),
			])
			var shadow := Polygon2D.new()
			shadow.polygon = shadow_poly
			if elev_diff >= 3.0:
				shadow.color = Color(0.06, 0.05, 0.04, 0.7)  # Cliff
			elif elev_diff >= 1.5:
				shadow.color = Color(0.08, 0.07, 0.06, 0.5)  # Medium
			else:
				shadow.color = Color(0.1, 0.09, 0.08, 0.35)  # Subtle
			hex_map_layer.add_child(shadow)

		# Mountain highlight on top edges (edges 4 and 5 = north-facing)
		if hex_map.tiles[coord].terrain == Enums.TerrainType.MOUNTAINS:
			for edge_i in [4, 5]:
				var hv1: Vector2 = my_pixel + hex_points[edge_i]
				var hv2: Vector2 = my_pixel + hex_points[(edge_i + 1) % 6]
				var highlight := Line2D.new()
				highlight.points = PackedVector2Array([
					Vector2(hv1.x, hv1.y - my_elev),
					Vector2(hv2.x, hv2.y - my_elev),
				])
				highlight.width = 1.5
				highlight.default_color = Color(0.65, 0.6, 0.55, 0.4)
				hex_map_layer.add_child(highlight)

func _draw_mountain_outlines() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var hex_points := _make_hex_polygon(HEX_RADIUS)
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
			# Only draw outline on edges facing non-mountain tiles
			if ntile == null or ntile.terrain != Enums.TerrainType.MOUNTAINS:
				var e: int = edge_lut[i]
				var v1: Vector2 = my_pixel + hex_points[e]
				var v2: Vector2 = my_pixel + hex_points[(e + 1) % 6]
				var outline := Line2D.new()
				outline.points = PackedVector2Array([
					Vector2(v1.x, v1.y - my_elev),
					Vector2(v2.x, v2.y - my_elev),
				])
				outline.width = 3.0
				outline.default_color = Color(0.05, 0.04, 0.03, 0.9)
				hex_map_layer.add_child(outline)

func _add_terrain_detail(container: Node2D, terrain: Enums.TerrainType, _hex_poly: PackedVector2Array, base_color: Color) -> void:
	var r := HEX_RADIUS * 0.96
	match terrain:
		Enums.TerrainType.FOREST:
			# Tree circles
			for offset in [Vector2(-6, -5), Vector2(4, -3), Vector2(-2, 5), Vector2(6, 4)]:
				var tree := Polygon2D.new()
				tree.polygon = _make_circle(4.0, 6)
				tree.position = offset
				tree.color = base_color.darkened(0.25)
				container.add_child(tree)
		Enums.TerrainType.JUNGLE:
			# Dense vegetation - more and bigger circles
			for offset in [Vector2(-7, -6), Vector2(5, -4), Vector2(-3, 6), Vector2(7, 3), Vector2(0, -1), Vector2(-5, 2)]:
				var tree := Polygon2D.new()
				tree.polygon = _make_circle(4.5, 6)
				tree.position = offset
				tree.color = base_color.darkened(0.2)
				container.add_child(tree)
		Enums.TerrainType.MOUNTAINS:
			# Triangle peaks
			var peak := Polygon2D.new()
			peak.polygon = PackedVector2Array([Vector2(0, -8), Vector2(-6, 4), Vector2(6, 4)])
			peak.color = base_color.lightened(0.15)
			container.add_child(peak)
			var peak2 := Polygon2D.new()
			peak2.polygon = PackedVector2Array([Vector2(-7, -3), Vector2(-12, 5), Vector2(-2, 5)])
			peak2.color = base_color.lightened(0.1)
			container.add_child(peak2)
		Enums.TerrainType.DESERT:
			# Dune lines
			var line := Line2D.new()
			line.points = PackedVector2Array([Vector2(-r * 0.5, 2), Vector2(0, -2), Vector2(r * 0.5, 2)])
			line.width = 1.5
			line.default_color = base_color.lightened(0.15)
			container.add_child(line)
			var line2 := Line2D.new()
			line2.points = PackedVector2Array([Vector2(-r * 0.4, 7), Vector2(r * 0.1, 4), Vector2(r * 0.4, 7)])
			line2.width = 1.5
			line2.default_color = base_color.lightened(0.12)
			container.add_child(line2)
		Enums.TerrainType.SWAMP:
			# Wavy water lines
			var line := Line2D.new()
			line.points = PackedVector2Array([Vector2(-8, 0), Vector2(-3, -3), Vector2(3, 3), Vector2(8, 0)])
			line.width = 1.5
			line.default_color = Color(0.25, 0.5, 0.35, 0.6)
			container.add_child(line)
		Enums.TerrainType.WATER:
			# Wave lines
			var line := Line2D.new()
			line.points = PackedVector2Array([Vector2(-8, -2), Vector2(-3, -5), Vector2(3, -2), Vector2(8, -5)])
			line.width = 1.5
			line.default_color = base_color.lightened(0.2)
			container.add_child(line)
			var line2 := Line2D.new()
			line2.points = PackedVector2Array([Vector2(-6, 4), Vector2(-1, 1), Vector2(5, 4), Vector2(10, 1)])
			line2.width = 1.5
			line2.default_color = base_color.lightened(0.15)
			container.add_child(line2)
		Enums.TerrainType.TUNDRA:
			# Ice crystal dots
			for offset in [Vector2(-5, -3), Vector2(4, 5), Vector2(6, -4)]:
				var dot := Polygon2D.new()
				dot.polygon = PackedVector2Array([Vector2(0, -2), Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0)])
				dot.position = offset
				dot.color = Color(0.85, 0.88, 0.95, 0.6)
				container.add_child(dot)
		Enums.TerrainType.SHARD_WASTES:
			# Glowing shard fragments
			for offset in [Vector2(-4, -3), Vector2(5, 2), Vector2(-1, 6)]:
				var shard := Polygon2D.new()
				shard.polygon = PackedVector2Array([Vector2(0, -3), Vector2(2, 0), Vector2(0, 3), Vector2(-2, 0)])
				shard.position = offset
				shard.color = Color(0.7, 0.3, 0.8, 0.7)
				container.add_child(shard)
		Enums.TerrainType.PLAINS:
			# Subtle grass lines
			var line := Line2D.new()
			line.points = PackedVector2Array([Vector2(-4, 2), Vector2(-3, -2), Vector2(-2, 2)])
			line.width = 1.0
			line.default_color = base_color.lightened(0.12)
			container.add_child(line)
			var line2 := Line2D.new()
			line2.points = PackedVector2Array([Vector2(3, 1), Vector2(4, -3), Vector2(5, 1)])
			line2.width = 1.0
			line2.default_color = base_color.lightened(0.12)
			container.add_child(line2)
		Enums.TerrainType.WETLANDS:
			# Wetlands reeds
			var line := Line2D.new()
			line.points = PackedVector2Array([Vector2(-7, 3), Vector2(-2, 0), Vector2(4, 3), Vector2(8, 1)])
			line.width = 1.5
			line.default_color = Color(0.65, 0.6, 0.45, 0.5)
			container.add_child(line)

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

	# Build visual ownership map: use region ownership to fill mountain/water gaps
	# so borders follow region boundaries cleanly instead of outlining every unowned tile.
	_visual_faction_owner.clear()
	var visual_owner := _visual_faction_owner

	# Determine which faction controls each region (majority of cities)
	var region_faction_counts: Dictionary = {}  # region_id -> {faction_id -> count}
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == &"" or city.faction_id == &"independent":
			continue
		if not region_faction_counts.has(city.region_id):
			region_faction_counts[city.region_id] = {}
		var rc: Dictionary = region_faction_counts[city.region_id]
		rc[city.faction_id] = rc.get(city.faction_id, 0) + 1
	var region_owners: Dictionary = {}  # region_id -> faction_id
	for region_id in region_faction_counts:
		var rc: Dictionary = region_faction_counts[region_id]
		var best_fid: StringName = &""
		var best_count := 0
		for fid in rc:
			if rc[fid] > best_count:
				best_count = rc[fid]
				best_fid = fid
		if best_fid != &"":
			region_owners[region_id] = best_fid

	# Assign visual ownership: owned tiles use actual owner, unowned use region owner
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.owner_faction != &"" and tile.owner_faction != &"independent":
			visual_owner[coord] = tile.owner_faction
		elif tile.region_id != &"":
			var reg_owner: StringName = region_owners.get(tile.region_id, &"")
			if reg_owner != &"":
				visual_owner[coord] = reg_owner

	# Use full HEX_RADIUS (no 0.96 inset) so shared vertices between adjacent hexes
	# match exactly — required for reliable snap-based vertex matching in pruning.
	var hex_points := _make_hex_polygon(HEX_RADIUS)
	var border_edges: Dictionary = {}  # faction_id -> Array of [v1, v2]

	for coord in visual_owner:
		var my_faction: StringName = visual_owner[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var neighbors := HexHelper.get_neighbors(coord)
		var edge_lut: Array = DIR_TO_EDGE_EVEN if (coord.x & 1 == 0) else DIR_TO_EDGE_ODD

		for i in 6:
			var neighbor: Vector2i = neighbors[i]
			var draw_border := false

			if not HexHelper.is_valid(neighbor, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
				draw_border = true
			else:
				var n_faction: StringName = visual_owner.get(neighbor, &"")
				if n_faction != my_faction:
					draw_border = true

			if draw_border:
				var e: int = edge_lut[i]
				var v1: Vector2 = pixel_pos + hex_points[e]
				var v2: Vector2 = pixel_pos + hex_points[(e + 1) % 6]
				if not border_edges.has(my_faction):
					border_edges[my_faction] = []
				border_edges[my_faction].append([v1, v2])

	for faction_id in border_edges:
		var fd: FactionData = DataManager.get_faction(faction_id)
		var border_color: Color = fd.color.lightened(0.1) if fd else Color.WHITE
		border_color.a = 0.7
		var clean := _prune_faction_border_edges(border_edges[faction_id])
		var draw_node := _BorderDrawNode.new()
		draw_node.edges = clean
		draw_node.line_color = border_color
		draw_node.line_width = 2.5
		_faction_border_node.add_child(draw_node)

# Removes dead-end stubs and small isolated loops from faction border edges.
# Uses coarse spatial hashing (÷16) for vertex matching — shared corners differ by
# ~0.002px (always same bucket), distinct corners are 32+px apart (always different buckets).
func _prune_faction_border_edges(raw_edges: Array) -> Array:
	if raw_edges.size() < 3:
		return raw_edges

	# Snap vertices to coarse grid for reliable matching
	var snap_edges: Array = []  # [Vector2i snap_v1, Vector2i snap_v2, Vector2 real_v1, Vector2 real_v2]
	for edge in raw_edges:
		var v1: Vector2 = edge[0]
		var v2: Vector2 = edge[1]
		var s1 := Vector2i(roundi(v1.x / 16.0), roundi(v1.y / 16.0))
		var s2 := Vector2i(roundi(v2.x / 16.0), roundi(v2.y / 16.0))
		snap_edges.append([s1, s2, v1, v2])

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

	# BFS connected components — filter out small ones (< 12 edges)
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
		if comp.size() >= 12:
			for eidx in comp:
				result.append([snap_edges[eidx][2], snap_edges[eidx][3]])
	return result

class _BorderDrawNode extends Node2D:
	var edges: Array = []
	var line_color: Color = Color.WHITE
	var line_width: float = 2.0
	func _draw() -> void:
		for edge in edges:
			draw_line(edge[0], edge[1], line_color, line_width, true)

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
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7, 0.95))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("outline_size", 2)
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

		# The fill polygon is child 1 (child 0 is border)
		if container.get_child_count() > 1:
			var fill: Polygon2D = container.get_child(1)
			var has_texture := fill.texture != null
			var base_color: Color = Color.WHITE if has_texture else TERRAIN_COLORS.get(tile.terrain, Color.GRAY)
			if tile.owner_faction != &"":
				var faction_data: FactionData = DataManager.get_faction(tile.owner_faction)
				if faction_data:
					base_color = base_color.lerp(faction_data.color, 0.12)
			fill.color = base_color

# ── Army markers ──────────────────────────────────────────────

func _create_army_markers() -> void:
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

	# Castle base (square with crenellations)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-10, -8), Vector2(10, -8), Vector2(10, 8),
		Vector2(-10, 8)
	])
	base.color = faction_color.darkened(0.2)
	marker.add_child(base)

	# Tower left
	var tower_l := Polygon2D.new()
	tower_l.polygon = PackedVector2Array([
		Vector2(-12, -14), Vector2(-6, -14), Vector2(-6, -6), Vector2(-12, -6)
	])
	tower_l.color = faction_color.darkened(0.1)
	marker.add_child(tower_l)

	# Tower right
	var tower_r := Polygon2D.new()
	tower_r.polygon = PackedVector2Array([
		Vector2(6, -14), Vector2(12, -14), Vector2(12, -6), Vector2(6, -6)
	])
	tower_r.color = faction_color.darkened(0.1)
	marker.add_child(tower_r)

	# Center tower (taller)
	var is_player_capital := city.is_capital and city.faction_id == GameManager.state.player_faction_id
	var tower_c := Polygon2D.new()
	tower_c.polygon = PackedVector2Array([
		Vector2(-4, -18), Vector2(4, -18), Vector2(4, -6), Vector2(-4, -6)
	])
	tower_c.color = faction_color.lightened(0.15) if is_player_capital else faction_color
	marker.add_child(tower_c)

	# Gold diamond indicator on player capital
	if is_player_capital:
		var crown := Polygon2D.new()
		crown.polygon = PackedVector2Array([
			Vector2(0, -24), Vector2(4, -20), Vector2(0, -16), Vector2(-4, -20)
		])
		crown.color = Color(0.95, 0.85, 0.3)
		marker.add_child(crown)

	# City level glow — scales with city level, larger for capitals
	if city.faction_id == GameManager.state.player_faction_id:
		var glow_base_radius := 14.0 + city.level * 2.0
		if city.is_capital:
			glow_base_radius += 6.0
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
	label.position = Vector2(-4, -16)
	label.add_theme_font_size_override("font_size", 10)
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
		Vector2(-12, -18), Vector2(12, -18), Vector2(12, 8),
		Vector2(-12, 8), Vector2(-12, -18)
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
			_add_building_tile_marker(tile_pos, building, faction_color, false)

		# Draw markers for buildings under construction
		for item in city.build_queue:
			if item.has("tile_pos"):
				var building: BuildingData = DataManager.get_building(item.building_id)
				_add_building_tile_marker(item.tile_pos, building, faction_color, true)

func _add_building_tile_marker(tile_pos: Vector2i, building: BuildingData, faction_color: Color, under_construction: bool) -> void:
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

	city_markers_node.add_child(marker)
	_building_tile_markers.append(marker)

# ── Elderbeast markers ────────────────────────────────────────

func _create_elderbeast_markers() -> void:
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

func _refresh_city_markers() -> void:
	_create_city_markers()
	_create_building_tile_markers()
	_update_city_glow_states()

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
	var highlight_poly := _make_hex_polygon(HEX_RADIUS * 0.94)
	for coord in tiles:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = highlight_poly
		polygon.position = pixel_pos
		polygon.color = Color(1.0, 0.9, 0.5, 0.12)
		region_highlight_node.add_child(polygon)
		_region_highlight_nodes.append(polygon)

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
			# Army is selected: left-click on another player army = switch selection
			var clicked_army := _get_army_at_click(world_pos)
			if clicked_army != &"" and clicked_army != selected_army_id:
				var clicked: ArmyState = GameManager.state.armies.get(clicked_army)
				if clicked and clicked.faction_id == GameManager.state.player_faction_id:
					_select_army(clicked_army)
					return
			# Otherwise deselect, then handle the hex
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
			if selected_army_id != &"":
				_handle_move_command(hex_coord)

	# Fog of war toggle
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_fog_of_war_enabled = not _fog_of_war_enabled
		_update_fog_of_war()

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

	# Check for player army at click position (marker hit-test first)
	var clicked_army := _get_army_at_click(get_global_mouse_position())
	if clicked_army != &"":
		var army: ArmyState = GameManager.state.armies.get(clicked_army)
		if army and army.faction_id == GameManager.state.player_faction_id:
			_select_army(clicked_army)
			return
		elif army and tile_visible:
			# Enemy army — only inspect if in current LOS
			_show_inspect_army(army)
			return

	# Check for player army at hex (fallback)
	var army_at := GameManager.get_army_at_tile(hex_coord)
	if army_at:
		if army_at.faction_id == GameManager.state.player_faction_id:
			_select_army(army_at.army_id)
			return
		elif tile_visible:
			# Enemy army — only inspect if in current LOS
			_show_inspect_army(army_at)
			return

	# Check for elderbeast at hex
	var beast_at := GameManager.get_elderbeast_at_tile(hex_coord)
	if beast_at:
		if beast_at.faction_id == GameManager.state.player_faction_id:
			_select_elderbeast(beast_at.beast_id)
			return

	# Check for city at hex
	var city_at := GameManager.city_system.get_city_at_hex(hex_coord)
	if city_at:
		if city_at.faction_id == GameManager.state.player_faction_id:
			_open_city_panel(city_at.city_id)
		elif tile_visible:
			# Enemy city — only inspect if in current LOS
			_show_inspect_city(city_at)
		return

	# Empty hex — close city panel if open, select hex for region info
	if _city_panel_open:
		_close_city_panel()
	_select_hex(hex_coord)

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
		army.hex_pos, hex_coord, army.faction_id, army.movement_remaining, army.army_id, army.can_cross_mountains())
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
			_reachable_tiles.clear()
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
			var target_pixel := _hex_to_pixel(tile_coord)
			var tween := create_tween()
			tween.tween_property(marker, "position", target_pixel, 0.15)
			await tween.finished

		# Now process this single step via GameManager
		var single_step: Array[Vector2i] = [tile_coord]
		GameManager.move_army_along_path(army_id, single_step)

		# Check if battle triggered or army destroyed
		if not GameManager.state.armies.has(army_id):
			return
		if GameManager.current_phase != Enums.GamePhase.CAMPAIGN:
			return

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
	_selected_beast_id = &""
	GameManager.state.selected_army_id = &""
	_reachable_tiles.clear()
	_clear_reachable_overlay()
	_clear_path_overlay()
	_clear_beast_terrain_overlay()
	EventBus.army_deselected.emit()
	EventBus.hex_tile_deselected.emit()

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

func _show_reachable_tiles(army: ArmyState) -> void:
	_clear_reachable_overlay()
	_reachable_tiles = GameManager.movement_system.get_reachable_tiles(
		army.hex_pos, army.movement_remaining, army.faction_id, army.army_id, army.can_cross_mountains())

	for coord in _reachable_tiles:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = _make_hex_polygon(HEX_RADIUS * 0.88)
		polygon.position = pixel_pos
		polygon.color = Color(0.2, 0.8, 0.2, 0.25)
		reachable_overlay.add_child(polygon)

func _show_path_preview(target: Vector2i) -> void:
	_clear_path_overlay()
	var army: ArmyState = GameManager.state.armies.get(selected_army_id)
	if army == null:
		return
	var path := GameManager.movement_system.find_path(
		army.hex_pos, target, army.faction_id, army.movement_remaining, army.army_id, army.can_cross_mountains())
	for coord in path:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = _make_hex_polygon(HEX_RADIUS * 0.6)
		polygon.position = pixel_pos
		polygon.color = Color(1.0, 1.0, 0.3, 0.45)
		path_overlay.add_child(polygon)

func _clear_reachable_overlay() -> void:
	for child in reachable_overlay.get_children():
		child.queue_free()

func _clear_path_overlay() -> void:
	for child in path_overlay.get_children():
		child.queue_free()

# ── Signal handlers ───────────────────────────────────────────

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

	# Only update heavy visuals if move was visible to player
	if move_visible:
		_update_fog_of_war()
		_update_political_overlay()
		_update_minimap()
	elif is_player_army:
		# Player army moved — always update fog
		_update_fog_of_war()
		_update_minimap()

func _on_army_destroyed(army_id: StringName, _faction_id: StringName) -> void:
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		marker.queue_free()
		_army_markers.erase(army_id)

func _on_region_ownership_changed(_region_id: StringName, _old: StringName, _new: StringName) -> void:
	_update_political_overlay()
	_refresh_faction_borders()
	_update_fog_of_war()

func _on_battle_initiated(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

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
	get_tree().change_scene_to_file("res://scenes/battle/battle_v3.tscn")

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

	if not atk_alive:
		GameManager.remove_army(attacker_id)
	if not def_alive:
		GameManager.remove_army(defender_id)

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
	if atk_alive and not def_alive:
		EventBus.battle_resolved.emit(attacker_army.faction_id, hex_pos)
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id != attacker_army.faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_army.faction_id)
		elif city_at and city_at.faction_id == attacker_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
	elif def_alive and not atk_alive:
		EventBus.battle_resolved.emit(defender_army.faction_id, hex_pos)
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
		if atk_alive and not def_alive:
			CommanderSystem.apply_item_drop(attacker_army.commander, defender_army.faction_id)
	if defender_army.commander:
		CommanderSystem.grant_battle_xp(defender_army.commander, atk_strength_pre, def_alive, def_ctx)
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
	# Brief turn transition fade
	_flash_turn_transition()
	if faction_id == GameManager.state.player_faction_id:
		AudioManager.play_sfx(&"turn_chime")
		_show_notification("Your turn - Turn " + str(GameManager.state.current_turn))
	# Refresh markers
	_refresh_city_markers()
	_create_army_markers()
	_create_elderbeast_markers()
	_update_fog_of_war()
	_update_minimap()
	_update_city_glow_states()
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
	_refresh_city_markers()
	_update_political_overlay()
	_refresh_faction_borders()

func _on_siege_started(city_id: StringName, faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			var faction: FactionData = DataManager.get_faction(faction_id)
			var fname: String = faction.display_name if faction else str(faction_id)
			_show_notification(fname + " is besieging " + city.get_display_name() + "!")
	_refresh_city_markers()

func _on_siege_broken(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		if _is_tile_visible(city.hex_pos):
			_show_notification("Siege of " + city.get_display_name() + " broken!")
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

func _create_fog_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return
	var fog_poly := _make_hex_polygon(HEX_RADIUS)
	for coord in hex_map.tiles:
		var elevation: float = _hex_elevations.get(coord, 0.0)
		var fog := Polygon2D.new()
		fog.polygon = fog_poly
		fog.position = Vector2(_hex_to_pixel(coord).x, _hex_to_pixel(coord).y - elevation)
		fog.color = Color(0.03, 0.02, 0.05, 0.75)
		fog.z_index = 1  # Render above terrain
		fog_overlay_node.add_child(fog)
		_fog_overlay_nodes[coord] = fog
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

	# Collect player cities and armies once
	var player_cities: Array[Vector2i] = []
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if city.faction_id == player_id:
			player_cities.append(city.hex_pos)

	var player_army_sources: Array[Dictionary] = []  # [{pos, radius}]
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if army.faction_id == player_id:
			var sr := FOG_SCOUT_RADIUS
			if army.commander:
				sr += CommanderSystem.get_scouting_bonus(army.commander)
			player_army_sources.append({pos = army.hex_pos, radius = sr})

	# Cache allied factions
	var allied_factions: Dictionary = {}
	for faction_id in DataManager.factions:
		if faction_id == player_id:
			continue
		var rel := GameManager.get_relation(player_id, faction_id)
		if rel == Enums.FactionRelation.FRIENDLY or rel == Enums.FactionRelation.ALLIED:
			allied_factions[faction_id] = true

	# Build visibility for all tiles in one pass
	const SETTLEMENT_LOS_BONUS := 2
	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		# Owned by player
		if tile.owner_faction == player_id:
			_visible_tile_cache[coord] = true
			continue
		# Owned by ally
		if tile.owner_faction != &"" and allied_factions.has(tile.owner_faction):
			_visible_tile_cache[coord] = true
			continue
		# Near player city
		var found := false
		for city_pos in player_cities:
			if HexHelper.hex_distance(coord, city_pos) <= SETTLEMENT_LOS_BONUS:
				found = true
				break
		if found:
			_visible_tile_cache[coord] = true
			continue
		# Near player army
		for src in player_army_sources:
			if HexHelper.hex_distance(coord, src.pos) <= src.radius:
				found = true
				break
		if found:
			_visible_tile_cache[coord] = true

func _is_tile_visible(coord: Vector2i) -> bool:
	if not _fog_of_war_enabled:
		return true
	return _visible_tile_cache.get(coord, false)

func _update_fog_of_war() -> void:
	_rebuild_visible_tile_cache()

	for coord in _fog_overlay_nodes:
		var fog: Polygon2D = _fog_overlay_nodes[coord]
		var visible_tile: bool = bool(_visible_tile_cache.get(coord, false)) if _fog_of_war_enabled else true
		if visible_tile:
			_explored_tiles[coord] = true
			fog.visible = false
		elif _explored_tiles.has(coord):
			fog.visible = true
			fog.color = Color(0.03, 0.02, 0.05, 0.45)
		else:
			fog.visible = true
			fog.color = Color(0.03, 0.02, 0.05, 0.75)

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

	# Show overlay on valid tiles with resource-based gradient
	for coord in _settlement_valid_tiles:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = _make_hex_polygon(HEX_RADIUS * 0.88)
		polygon.position = pixel_pos
		var val: int = resource_values.get(coord, 0)
		var t := 0.5
		if max_val > min_val:
			t = float(val - min_val) / float(max_val - min_val)
		# Red (low) -> Green (high)
		polygon.color = Color(0.8 * (1.0 - t), 0.8 * t, 0.1, 0.35)
		reachable_overlay.add_child(polygon)
		_settlement_overlay_nodes.append(polygon)

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
		_create_city_markers()
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

	# Show green overlay on valid tiles, red on invalid neighbors
	var hex_poly := _make_hex_polygon(HEX_RADIUS * 0.88)
	for coord in all_neighbors:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = hex_poly
		polygon.position = pixel_pos
		if _building_tile_valid.has(coord):
			polygon.color = Color(0.15, 0.8, 0.25, 0.4)  # Green = valid
		else:
			polygon.color = Color(0.8, 0.2, 0.15, 0.3)  # Red = invalid
		reachable_overlay.add_child(polygon)
		_building_tile_overlays.append(polygon)

	# Also highlight any valid tiles that aren't direct neighbors (e.g. upgrade tiles)
	for coord in _building_tile_valid:
		if not all_neighbors.has(coord):
			var pixel_pos := _hex_to_pixel(coord)
			var polygon := Polygon2D.new()
			polygon.polygon = hex_poly
			polygon.position = pixel_pos
			polygon.color = Color(0.15, 0.8, 0.25, 0.4)
			reachable_overlay.add_child(polygon)
			_building_tile_overlays.append(polygon)

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
	for tile_pos in tiles:
		var depletion_mult := beast.get_depletion_multiplier(tile_pos)
		# Green (full yield) → Red (depleted), lerp based on multiplier
		var color := Color(0.15, 0.8, 0.25, 0.35).lerp(Color(0.8, 0.2, 0.15, 0.35), 1.0 - depletion_mult)
		var polygon := Polygon2D.new()
		polygon.polygon = hex_poly
		polygon.position = _hex_to_pixel(tile_pos)
		polygon.color = color
		reachable_overlay.add_child(polygon)
		_beast_terrain_overlays.append(polygon)

func _clear_beast_terrain_overlay() -> void:
	for node in _beast_terrain_overlays:
		if is_instance_valid(node):
			node.queue_free()
	_beast_terrain_overlays.clear()

# ── Minimap ──────────────────────────────────────────────────

const MINIMAP_SIZE := Vector2(354, 220)
const MINIMAP_MARGIN := Vector2(10, 10)
var _minimap_panel: PanelContainer
var _minimap_image: TextureRect
var _minimap_political_mode := false
var _minimap_dragging := false

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
		_update_minimap()
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
	outer_vbox.offset_left = -380.0
	outer_vbox.offset_top = -MINIMAP_SIZE.y - MINIMAP_MARGIN.y - 34
	outer_vbox.offset_right = -10.0
	outer_vbox.offset_bottom = -MINIMAP_MARGIN.y

	# Click to navigate
	_minimap_image.gui_input.connect(_on_minimap_click)

	$UILayer/HUD.add_child(outer_vbox)
	_update_minimap()

func _update_minimap() -> void:
	if _minimap_image == null:
		return
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var w: int = HexMapData.MAP_WIDTH
	var h: int = HexMapData.MAP_HEIGHT
	# Each hex becomes ~3x3 pixels for a compact minimap
	var px_w: int = w * 3
	var px_h: int = h * 3
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.07, 0.1, 1.0))

	# Faction color map (exclude independent)
	var faction_colors: Dictionary = {}
	for fid in GameManager.state.faction_states:
		var fd := DataManager.get_faction(fid)
		faction_colors[fid] = fd.color if fd else Color(0.5, 0.5, 0.5)

	var fog_active := _fog_of_war_enabled

	# Draw terrain/ownership
	for x in w:
		for y in h:
			var coord := Vector2i(x, y)
			var tile := hex_map.get_tile(coord)
			if tile == null:
				continue

			# Fog of war check for minimap
			var is_visible: bool = not fog_active or bool(_visible_tile_cache.get(coord, false))
			var is_explored: bool = not fog_active or bool(_explored_tiles.get(coord, false))

			var color: Color
			if not is_explored:
				# Never seen — dark
				color = Color(0.05, 0.04, 0.07)
			elif not is_visible:
				# Explored but not currently visible — muted terrain only
				color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3))
				color = color.darkened(0.6)
			elif _minimap_political_mode:
				# Political view: faction-owned tiles show faction color
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = faction_colors[tile.owner_faction]
					color = color.darkened(0.15)
				else:
					color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3))
					color = color.darkened(0.3)
			else:
				# Terrain view: subtle faction tint
				color = TERRAIN_COLORS.get(tile.terrain, Color(0.3, 0.3, 0.3))
				if tile.owner_faction != &"" and tile.owner_faction != &"independent" and faction_colors.has(tile.owner_faction):
					color = color.lerp(faction_colors[tile.owner_faction], 0.15)
				color = color.darkened(0.3)

			var px := x * 3
			var py := y * 3
			for dx in 3:
				for dy in 3:
					if px + dx < px_w and py + dy < px_h:
						img.set_pixel(px + dx, py + dy, color)

	# Draw faction territory borders on minimap using visual ownership (fills mountain/water gaps)
	for x in w:
		for y in h:
			var coord := Vector2i(x, y)
			var my_faction: StringName = _visual_faction_owner.get(coord, &"")
			if my_faction == &"":
				continue
			if fog_active and not bool(_visible_tile_cache.get(coord, false)) and not bool(_explored_tiles.get(coord, false)):
				continue
			var fc: Color = faction_colors.get(my_faction, Color.WHITE)
			var border_color: Color = fc.darkened(0.2) if _minimap_political_mode else fc.darkened(0.1)
			border_color.a = 0.9
			# Check if any neighbor has a different visual owner
			for n in HexHelper.get_neighbors(coord):
				var n_faction: StringName = _visual_faction_owner.get(n, &"")
				if n_faction != my_faction:
					var dx: int = n.x - coord.x
					var dy: int = n.y - coord.y
					var bx: int = coord.x * 3 + 1 + clampi(dx, -1, 1)
					var by: int = coord.y * 3 + 1 + clampi(dy, -1, 1)
					if bx >= 0 and bx < px_w and by >= 0 and by < px_h:
						img.set_pixel(bx, by, border_color)

	# Draw armies as bright dots (only if visible)
	for army_id in GameManager.state.armies:
		var army: ArmyState = GameManager.state.armies[army_id]
		if fog_active and not bool(_visible_tile_cache.get(army.hex_pos, false)):
			continue
		var px: int = army.hex_pos.x * 3 + 1
		var py: int = army.hex_pos.y * 3 + 1
		var a_color: Color = faction_colors.get(army.faction_id, Color.WHITE).lightened(0.4)
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, a_color)
			if px + 1 < px_w:
				img.set_pixel(px + 1, py, a_color)
			if py + 1 < px_h:
				img.set_pixel(px, py + 1, a_color)

	# Draw cities (only if visible or explored)
	var player_id := GameManager.state.player_faction_id
	for city_id in GameManager.state.cities:
		var city: CityState = GameManager.state.cities[city_id]
		if fog_active and not bool(_visible_tile_cache.get(city.hex_pos, false)) and not bool(_explored_tiles.get(city.hex_pos, false)):
			continue
		var px: int = city.hex_pos.x * 3 + 1
		var py: int = city.hex_pos.y * 3 + 1
		var city_color: Color
		if city.faction_id == player_id:
			city_color = Color(0.3, 0.5, 1.0)  # Blue — own
		elif city.faction_id == &"" or city.faction_id == &"independent" or city.faction_id == &"rebels":
			city_color = Color(0.9, 0.9, 0.9)  # White — neutral
		else:
			var rel := GameManager.get_relation(player_id, city.faction_id)
			if rel == Enums.FactionRelation.ALLIED or rel == Enums.FactionRelation.FRIENDLY:
				city_color = Color(0.2, 0.85, 0.3)  # Green — allied/friendly
			elif rel == Enums.FactionRelation.WAR or rel == Enums.FactionRelation.HOSTILE:
				city_color = Color(0.95, 0.2, 0.15)  # Red — enemy
			else:
				city_color = Color(0.9, 0.9, 0.9)  # White — neutral
		if fog_active and not bool(_visible_tile_cache.get(city.hex_pos, false)):
			city_color = city_color.darkened(0.4)  # Explored but not visible: dim
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, city_color)

	# Draw shards as purple dots (only if visible)
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if fog_active and not bool(_visible_tile_cache.get(shard.hex_pos, false)):
			continue
		var px: int = shard.hex_pos.x * 3 + 1
		var py: int = shard.hex_pos.y * 3 + 1
		if px >= 0 and px < px_w and py >= 0 and py < px_h:
			img.set_pixel(px, py, Color(0.7, 0.3, 0.9))

	# Draw camera viewport indicator (account for camera zoom)
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_top_left := camera.position - viewport_size / 2.0
	var cam_bottom_right := camera.position + viewport_size / 2.0
	# Convert world coords to minimap pixels
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
