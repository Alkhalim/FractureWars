extends Camera2D

const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const ZOOM_SPEED := 0.1
const PAN_SPEED := 400.0
const MAP_MARGIN := 100.0
const EDGE_PAN_MARGIN := 20.0
const EDGE_PAN_SPEED := 600.0

var _is_panning := false
var _pan_start := Vector2.ZERO
var _did_pan := false # True if mouse moved while panning (distinguishes drag from click)
var _target_zoom := 1.0
var _zoom_focus_world := Vector2.ZERO
var _zoom_focus_screen := Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	# Don't process mouse events if hovering over UI
	if event is InputEventMouse and _is_mouse_over_ui():
		return

	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_focus_screen = get_viewport().get_mouse_position()
			_zoom_focus_world = get_global_mouse_position()
			_zoom_camera(ZOOM_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_focus_screen = get_viewport().get_mouse_position()
			_zoom_focus_world = get_global_mouse_position()
			_zoom_camera(-ZOOM_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_panning = true
				_did_pan = false
				_pan_start = event.position
			else:
				_is_panning = false
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_is_panning = true
				_did_pan = false
				_pan_start = event.position
			else:
				_is_panning = false
				if _did_pan:
					get_viewport().set_input_as_handled()

	# Pan with middle-mouse drag
	if event is InputEventMouseMotion and _is_panning:
		var move_delta: Vector2 = _pan_start - event.position
		if move_delta.length() > 2.0:
			_did_pan = true
		var delta: Vector2 = move_delta / zoom
		position += delta
		_pan_start = event.position
		_clamp_position()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# WASD / Arrow key panning
	var pan_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		pan_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		pan_dir.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		pan_dir.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		pan_dir.y += 1

	if pan_dir != Vector2.ZERO:
		position += pan_dir.normalized() * PAN_SPEED * delta / zoom.x
		_clamp_position()

	# Edge-of-screen panning (only when window is focused)
	if not _is_panning and DisplayServer.window_is_focused():
		var mouse_pos := get_viewport().get_mouse_position()
		var vp_size := get_viewport_rect().size
		var edge_dir := Vector2.ZERO
		if mouse_pos.x < EDGE_PAN_MARGIN:
			edge_dir.x = -1.0
		elif mouse_pos.x > vp_size.x - EDGE_PAN_MARGIN:
			edge_dir.x = 1.0
		if mouse_pos.y < EDGE_PAN_MARGIN:
			edge_dir.y = -1.0
		elif mouse_pos.y > vp_size.y - EDGE_PAN_MARGIN:
			edge_dir.y = 1.0
		if edge_dir != Vector2.ZERO:
			position += edge_dir.normalized() * EDGE_PAN_SPEED * delta / zoom.x
			_clamp_position()

	# Smooth zoom lerp toward target
	if not is_equal_approx(zoom.x, _target_zoom):
		var old_zoom := zoom.x
		var new_zoom := lerpf(zoom.x, _target_zoom, 1.0 - exp(-12.0 * delta))
		if absf(new_zoom - _target_zoom) < 0.001:
			new_zoom = _target_zoom
		zoom = Vector2(new_zoom, new_zoom)
		# Adjust position so the world point under the cursor stays stable
		var mouse_screen := _zoom_focus_screen
		var vp_size_zoom := get_viewport_rect().size
		var old_world_at_mouse := position + (mouse_screen - vp_size_zoom / 2.0) / Vector2(old_zoom, old_zoom)
		var new_world_at_mouse := position + (mouse_screen - vp_size_zoom / 2.0) / Vector2(new_zoom, new_zoom)
		position += old_world_at_mouse - new_world_at_mouse
		_clamp_position()

func _zoom_camera(amount: float) -> void:
	_target_zoom = clampf(_target_zoom + amount, MIN_ZOOM, MAX_ZOOM)

var _hud_cache: Control = null  # Cached ../UILayer/HUD lookup (resolved lazily, revalidated if freed)

func _is_mouse_over_ui() -> bool:
	# Check if the mouse is hovering over any visible UI panel
	if _hud_cache == null or not is_instance_valid(_hud_cache):
		_hud_cache = get_node_or_null("../UILayer/HUD") as Control
	var hud := _hud_cache
	if hud == null:
		return false
	var mouse_pos: Vector2 = hud.get_global_mouse_position()
	# Only check top-level visible panels (not deep-iterating)
	for child in hud.get_children():
		if child is Control and child.visible and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if child.get_global_rect().has_point(mouse_pos):
				return true
	return false

func _clamp_position() -> void:
	# Hex map bounds in pixels (flat-top hex: h_spacing = radius * 1.5, v_spacing = radius * sqrt(3))
	const HEX_RADIUS := 32.0
	const HEX_H_SPACING := HEX_RADIUS * 1.5 # 48.0
	const HEX_V_SPACING := HEX_RADIUS * 1.732 # ~55.42
	var map_w := float(HexMapData.MAP_WIDTH) * HEX_H_SPACING
	var map_h := float(HexMapData.MAP_HEIGHT) * HEX_V_SPACING
	# Account for zoom: allow camera center to move so the viewport edge reaches map edges
	var vp_half := get_viewport_rect().size / zoom / 2.0
	var margin := MAP_MARGIN
	position.x = clampf(position.x, -margin + vp_half.x, map_w + margin - vp_half.x)
	position.y = clampf(position.y, -margin + vp_half.y, map_h + margin - vp_half.y)
	# When zoomed out far enough to see the whole map, center it
	if -margin + vp_half.x > map_w + margin - vp_half.x:
		position.x = map_w / 2.0
	if -margin + vp_half.y > map_h + margin - vp_half.y:
		position.y = map_h / 2.0
