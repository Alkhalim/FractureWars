extends Node2D

const TERRAIN_NAMES := ["Plains", "Forest", "Mountains", "Desert", "Swamp", "Coast", "Tundra", "Shard Wastes", "Water", "Jungle"]
const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]

# Hex outer radius (center to vertex) for flat-top hexes
const HEX_RADIUS := 24.0
# Derived spacing
const HEX_H_SPACING := HEX_RADIUS * 1.5 # 36.0 - horizontal center-to-center
const HEX_V_SPACING := HEX_RADIUS * 1.732 # sqrt(3) * radius ≈ 41.57
const HEX_V_OFFSET := HEX_V_SPACING * 0.5 # Odd column vertical shift

# Terrain base colors
const TERRAIN_COLORS := {
	Enums.TerrainType.PLAINS: Color(0.62, 0.58, 0.42),
	Enums.TerrainType.FOREST: Color(0.28, 0.38, 0.22),
	Enums.TerrainType.MOUNTAINS: Color(0.45, 0.42, 0.38),
	Enums.TerrainType.DESERT: Color(0.72, 0.62, 0.40),
	Enums.TerrainType.SWAMP: Color(0.30, 0.32, 0.22),
	Enums.TerrainType.COAST: Color(0.48, 0.52, 0.42),
	Enums.TerrainType.TUNDRA: Color(0.58, 0.56, 0.52),
	Enums.TerrainType.SHARD_WASTES: Color(0.42, 0.28, 0.38),
	Enums.TerrainType.WATER: Color(0.22, 0.30, 0.38),
	Enums.TerrainType.JUNGLE: Color(0.20, 0.34, 0.18),
}

# Border color between tiles
const HEX_BORDER_COLOR := Color(0.12, 0.10, 0.08)

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

@onready var hex_map_layer: Node2D = $HexMapLayer
@onready var reachable_overlay: Node2D = $OverlayLayer/ReachableOverlay
@onready var path_overlay: Node2D = $OverlayLayer/PathOverlay
@onready var region_borders: Node2D = $OverlayLayer/RegionBorders
@onready var city_markers_node: Node2D = $EntityLayer/CityMarkers
@onready var army_markers_node: Node2D = $EntityLayer/ArmyMarkers
@onready var shard_markers_node: Node2D = $EntityLayer/ShardMarkers
@onready var region_labels_node: Node2D = $EntityLayer/RegionLabels
@onready var region_highlight_node: Node2D = $OverlayLayer/RegionHighlight
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	_render_hex_map()
	_draw_region_borders()
	_create_region_labels()
	_update_political_overlay()
	_create_city_markers()
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

	_recreate_shard_markers()
	_build_region_tiles_cache()

	# Connect settlement placement signal from HUD
	var hud: Control = $UILayer/HUD
	if hud.has_signal("settlement_placement_requested"):
		hud.settlement_placement_requested.connect(_on_settlement_placement_requested)

	# Position camera at map center
	var center_x := HexMapData.MAP_WIDTH * HEX_H_SPACING * 0.5
	var center_y := HexMapData.MAP_HEIGHT * HEX_V_SPACING * 0.5
	camera.position = Vector2(center_x, center_y)

	if not GameManager.has_meta("game_started"):
		GameManager.set_meta("game_started", true)
		TurnManager.start_game()
	elif GameManager.current_phase == Enums.GamePhase.CAMPAIGN:
		if not TurnManager.is_player_turn:
			TurnManager._end_current_faction_turn()

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

func _render_hex_map() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	var border_poly := _make_hex_polygon(HEX_RADIUS)
	var fill_poly := _make_hex_polygon(HEX_RADIUS * 0.92)

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var pixel_pos := _hex_to_pixel(coord)
		var base_color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)

		# Container node
		var container := Node2D.new()
		container.position = pixel_pos

		# Border hex (slightly larger)
		var border := Polygon2D.new()
		border.polygon = border_poly
		border.color = HEX_BORDER_COLOR
		container.add_child(border)

		# Fill hex
		var fill := Polygon2D.new()
		fill.polygon = fill_poly
		fill.color = base_color
		container.add_child(fill)

		# Terrain texture details
		_add_terrain_detail(container, tile.terrain, fill_poly, base_color)

		hex_map_layer.add_child(container)
		_hex_visuals[coord] = container

func _add_terrain_detail(container: Node2D, terrain: Enums.TerrainType, _hex_poly: PackedVector2Array, base_color: Color) -> void:
	var r := HEX_RADIUS * 0.92
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
		Enums.TerrainType.COAST:
			# Sandy shore dots
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

	for coord in hex_map.tiles:
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		if tile.region_id == &"":
			continue

		var pixel_pos := _hex_to_pixel(coord)
		var neighbors := HexHelper.get_neighbors(coord)

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
				# Draw the hex edge between vertex i and vertex (i+1)%6
				var v1: Vector2 = pixel_pos + hex_points[i]
				var v2: Vector2 = pixel_pos + hex_points[(i + 1) % 6]
				var line := Line2D.new()
				line.points = PackedVector2Array([v1, v2])
				line.width = 2.5
				line.default_color = Color(0.0, 0.0, 0.0, 1.0)
				region_borders.add_child(line)

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
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		panel.add_child(label)

		panel.position = pixel_pos - Vector2(50, 12)
		region_labels_node.add_child(panel)

func _update_political_overlay() -> void:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return

	for coord in _hex_visuals:
		var container: Node2D = _hex_visuals[coord]
		var tile: HexMapData.TileState = hex_map.tiles[coord]
		var base_color: Color = TERRAIN_COLORS.get(tile.terrain, Color.GRAY)

		if tile.owner_faction != &"":
			var faction_data: FactionData = DataManager.get_faction(tile.owner_faction)
			if faction_data:
				base_color = base_color.lerp(faction_data.color, 0.12)

		# The fill polygon is child 1 (child 0 is border)
		if container.get_child_count() > 1:
			var fill: Polygon2D = container.get_child(1)
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
	var tower_c := Polygon2D.new()
	tower_c.polygon = PackedVector2Array([
		Vector2(-4, -18), Vector2(4, -18), Vector2(4, -6), Vector2(-4, -6)
	])
	tower_c.color = faction_color
	marker.add_child(tower_c)

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

	city_markers_node.add_child(marker)
	_city_markers[city.city_id] = marker

func _animate_siege_ring(ring: Polygon2D) -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(ring, "modulate:a", 0.3, 0.6)
	tween.tween_property(ring, "modulate:a", 1.0, 0.6)

func _refresh_city_markers() -> void:
	_create_city_markers()

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

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := get_global_mouse_position()
		var hex_coord := _pixel_to_hex(world_pos)
		if HexHelper.is_valid(hex_coord, HexMapData.MAP_WIDTH, HexMapData.MAP_HEIGHT):
			_handle_hex_click(hex_coord)
		else:
			_deselect_all()

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click release (only if camera didn't consume it as a drag)
		if selected_army_id != &"":
			_deselect_all()

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

func _handle_hex_click(hex_coord: Vector2i) -> void:
	# First check: did we click directly on an army marker?
	var clicked_army := _get_army_at_click(get_global_mouse_position())
	if clicked_army != &"":
		var army: ArmyState = GameManager.state.armies.get(clicked_army)
		if army and army.faction_id == GameManager.state.player_faction_id:
			_select_army(clicked_army)
			return

	if selected_army_id != &"":
		var army: ArmyState = GameManager.state.armies.get(selected_army_id)
		if army and army.movement_remaining > 0:
			if _reachable_tiles.has(hex_coord):
				_move_army_to(army, hex_coord)
				return
			else:
				var closest := _find_closest_reachable_toward(army.hex_pos, hex_coord)
				if closest != Vector2i(-1, -1):
					_move_army_to(army, closest)
					return

	# Check if there's a player army at this hex (fallback)
	var army_at := GameManager.get_army_at_tile(hex_coord)
	if army_at and army_at.faction_id == GameManager.state.player_faction_id:
		_select_army(army_at.army_id)
	else:
		# Check if there's a player city at this hex
		var city_at := GameManager.city_system.get_city_at_hex(hex_coord)
		if city_at and city_at.faction_id == GameManager.state.player_faction_id:
			_deselect_all()
			_open_city_panel(city_at.city_id)
		else:
			if _city_panel_open:
				_close_city_panel()
			if selected_army_id != &"":
				_deselect_all()
			_select_hex(hex_coord)

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
		army.hex_pos, hex_coord, army.faction_id, army.movement_remaining)
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
	var army: ArmyState = GameManager.state.armies.get(army_id)
	if army:
		selected_hex = army.hex_pos
		_show_reachable_tiles(army)
	# Show selection ring
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		var ring := marker.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = true
	EventBus.army_selected.emit(army_id)
	EventBus.hex_tile_selected.emit(selected_hex)

func _select_hex(hex_coord: Vector2i) -> void:
	selected_hex = hex_coord
	selected_army_id = &""
	_clear_reachable_overlay()
	_clear_path_overlay()
	EventBus.hex_tile_selected.emit(hex_coord)

func _deselect_all() -> void:
	_hide_all_selection_rings()
	selected_hex = Vector2i(-1, -1)
	selected_army_id = &""
	_reachable_tiles.clear()
	_clear_reachable_overlay()
	_clear_path_overlay()
	EventBus.army_deselected.emit()
	EventBus.hex_tile_deselected.emit()

func _hide_all_selection_rings() -> void:
	for army_id in _army_markers:
		var marker: Node2D = _army_markers[army_id]
		var ring := marker.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = false

func _show_reachable_tiles(army: ArmyState) -> void:
	_clear_reachable_overlay()
	_reachable_tiles = GameManager.movement_system.get_reachable_tiles(
		army.hex_pos, army.movement_remaining, army.faction_id)

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
		army.hex_pos, target, army.faction_id, army.movement_remaining)
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

func _on_army_moved(army_id: StringName, _from_hex: Vector2i, to_hex: Vector2i) -> void:
	# If we're animating player movement, the animation handles marker position.
	# This handles AI army movement and any other external army_moved signals.
	if not _is_animating_move:
		var marker: Node2D = _army_markers.get(army_id)
		if marker:
			var target_pos := _hex_to_pixel(to_hex)
			var tween := create_tween()
			tween.tween_property(marker, "position", target_pos, 0.2)
	_update_political_overlay()

func _on_army_destroyed(army_id: StringName, _faction_id: StringName) -> void:
	var marker: Node2D = _army_markers.get(army_id)
	if marker:
		marker.queue_free()
		_army_markers.erase(army_id)

func _on_region_ownership_changed(_region_id: StringName, _old: StringName, _new: StringName) -> void:
	_update_political_overlay()

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

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator_color", Color(0.55, 0.42, 0.2, 0.5))
	vbox.add_child(sep2)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var manual_btn := Button.new()
	manual_btn.text = "Manual Battle"
	manual_btn.custom_minimum_size = Vector2(150, 36)
	manual_btn.pressed.connect(_on_battle_dialog_manual)
	btn_row.add_child(manual_btn)

	var auto_btn := Button.new()
	auto_btn.text = "Auto-Resolve"
	auto_btn.custom_minimum_size = Vector2(150, 36)
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
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

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

	# Create headless battle simulation
	var sim := BattleSimulator.new()
	var terrain := BattleTerrainGen.generate(Enums.TerrainType.PLAINS, hex_pos.x * 1000 + hex_pos.y)
	sim.setup_terrain(terrain)

	# Setup attacker units
	for i in attacker_army.units.size():
		var unit: UnitInstance = attacker_army.units[i]
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data == null:
			continue
		var col: int = (10 - attacker_army.units.size() / 2 + i * 3) % 20
		if col < 0: col = 0
		var pos := Vector2i(col, 12)
		while sim.grid.has(pos):
			pos.x = (pos.x + 1) % 20
		sim.setup_unit(unit, unit_data, 0, pos, Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Setup defender units
	for i in defender_army.units.size():
		var unit: UnitInstance = defender_army.units[i]
		var unit_data := DataManager.get_unit(unit.unit_data_id)
		if unit_data == null:
			continue
		var col: int = (10 - defender_army.units.size() / 2 + i * 3) % 20
		if col < 0: col = 0
		var pos := Vector2i(col, 2)
		while sim.grid.has(pos):
			pos.x = (pos.x + 1) % 20
		sim.setup_unit(unit, unit_data, 1, pos, Enums.UnitStance.AGGRESSIVE, Enums.TargetPriority.CLOSEST)

	# Run simulation to completion
	for tick in range(100):
		sim.simulate_tick()
		if sim.is_finished:
			break

	# Apply results
	var atk_survivors := sim.get_surviving_units(0)
	var def_survivors := sim.get_surviving_units(1)

	_apply_auto_battle_results(attacker_army, atk_survivors)
	_apply_auto_battle_results(defender_army, def_survivors)

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

	if not atk_alive:
		GameManager.remove_army(attacker_id)
	if not def_alive:
		GameManager.remove_army(defender_id)

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
		}
		_show_battle_report(report)

	# Refresh visuals
	_create_army_markers()

func _apply_auto_battle_results(army: ArmyState, survivors: Array[BattleSimulator.BattleUnit]) -> void:
	var surviving_ids: Dictionary = {}
	for bu in survivors:
		surviving_ids[bu.instance_id] = bu.current_hp

	var updated_units: Array[UnitInstance] = []
	for unit in army.units:
		if surviving_ids.has(unit.instance_id):
			unit.current_hp = surviving_ids[unit.instance_id]
			updated_units.append(unit)
	army.units = updated_units

func _on_turn_started(_turn: int, faction_id: StringName) -> void:
	if faction_id == GameManager.state.player_faction_id:
		_show_notification("Your turn - Turn " + str(GameManager.state.current_turn))
	# Refresh markers
	_refresh_city_markers()
	_create_army_markers()
	if selected_army_id != &"":
		var army: ArmyState = GameManager.state.armies.get(selected_army_id)
		if army:
			_show_reachable_tiles(army)
			EventBus.army_selected.emit(selected_army_id)
	# Refresh city panel if open
	if _city_panel_open and _selected_city_id != &"":
		_open_city_panel(_selected_city_id)

func _on_shardfall_occurred(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm) -> void:
	_create_shard_marker(shard_id, hex_pos, realm)
	var realm_name := ShardfallSystem.get_realm_name(realm)
	var tile := GameManager.state.hex_map.get_tile(hex_pos)
	var region_name := ""
	if tile:
		var region := DataManager.get_region(tile.region_id)
		region_name = region.display_name if region else str(tile.region_id)
	_show_notification("SHARDFALL! A " + realm_name + " shard has fallen in " + region_name + "!")

func _create_shard_marker(shard_id: StringName, hex_pos: Vector2i, realm: Enums.Realm) -> void:
	var marker := Node2D.new()
	marker.position = _hex_to_pixel(hex_pos) + Vector2(0, -12)

	var diamond := ColorRect.new()
	diamond.size = Vector2(12, 12)
	diamond.position = Vector2(-6, -6)
	diamond.color = ShardfallSystem.get_realm_color(realm)
	diamond.rotation = PI / 4

	var glow := ColorRect.new()
	glow.size = Vector2(16, 16)
	glow.position = Vector2(-8, -8)
	var glow_color := ShardfallSystem.get_realm_color(realm)
	glow_color.a = 0.3
	glow.color = glow_color
	glow.rotation = PI / 4

	marker.add_child(glow)
	marker.add_child(diamond)

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
		var faction := DataManager.get_faction(new_owner)
		var fname := faction.display_name if faction else str(new_owner)
		_show_notification(fname + " captured " + city.get_display_name() + "!")
	_refresh_city_markers()
	_update_political_overlay()

func _on_siege_started(city_id: StringName, faction_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		var faction := DataManager.get_faction(faction_id)
		var fname := faction.display_name if faction else str(faction_id)
		_show_notification(fname + " is besieging " + city.get_display_name() + "!")
	_refresh_city_markers()

func _on_siege_broken(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city:
		_show_notification("Siege of " + city.get_display_name() + " broken!")
	_refresh_city_markers()

func _on_building_completed(city_id: StringName, building_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		var building := DataManager.get_building(building_id)
		var bname := building.display_name if building else str(building_id)
		_show_notification(bname + " completed in " + city.get_display_name())

func _on_unit_recruited(city_id: StringName, unit_data_id: StringName, _army_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city and city.faction_id == GameManager.state.player_faction_id:
		var unit_data := DataManager.get_unit(unit_data_id)
		var uname := unit_data.display_name if unit_data else str(unit_data_id)
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

# ── Settlement Placement Mode ─────────────────────────────────

func _on_settlement_placement_requested(city_id: StringName) -> void:
	var city: CityState = GameManager.state.cities.get(city_id)
	if city == null:
		return

	_settlement_placement_mode = true
	_settlement_parent_city_id = city_id
	_close_city_panel()
	_deselect_all()

	# Get valid tiles for settlement in this region
	_settlement_valid_tiles = GameManager.city_system.get_valid_settlement_tiles(
		city.faction_id, city.region_id)

	# Show overlay on valid tiles
	for coord in _settlement_valid_tiles:
		var pixel_pos := _hex_to_pixel(coord)
		var polygon := Polygon2D.new()
		polygon.polygon = _make_hex_polygon(HEX_RADIUS * 0.88)
		polygon.position = pixel_pos
		polygon.color = Color(0.4, 0.8, 0.3, 0.3)
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

func _show_settlement_preview(hex_coord: Vector2i) -> void:
	if _settlement_preview_panel:
		_settlement_preview_panel.queue_free()

	if not _settlement_valid_tiles.has(hex_coord):
		_settlement_preview_panel = null
		return

	var income := GameManager.city_system.calculate_settlement_income_preview(hex_coord)
	if income.is_empty():
		return

	var resource_names := ["Gold", "Iron", "Technology", "Food", "Shard Essence", "Wood"]

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

	var header := Label.new()
	header.text = "Settlement Income Preview"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	vbox.add_child(header)

	for res_type in income:
		if income[res_type] > 0:
			var rname: String = resource_names[res_type] if res_type < resource_names.size() else "?"
			var rlabel := Label.new()
			rlabel.text = "  +" + str(income[res_type]) + " " + rname
			rlabel.add_theme_font_size_override("font_size", 11)
			rlabel.add_theme_color_override("font_color", Color(0.5, 0.75, 0.45))
			vbox.add_child(rlabel)

	_settlement_preview_panel.add_child(vbox)

	# Position near mouse
	var pixel_pos := _hex_to_pixel(hex_coord)
	var screen_pos := pixel_pos - camera.position + get_viewport_rect().size / 2.0
	_settlement_preview_panel.position = Vector2(screen_pos.x + 30, screen_pos.y - 40)
	$UILayer/HUD.add_child(_settlement_preview_panel)
