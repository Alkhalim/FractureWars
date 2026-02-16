extends Camera2D

const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const ZOOM_SPEED := 0.1
const PAN_SPEED := 400.0
const MAP_MARGIN := 100.0

var _is_panning := false
var _pan_start := Vector2.ZERO
var _did_pan := false # True if mouse moved while panning (distinguishes drag from click)

func _unhandled_input(event: InputEvent) -> void:
	# Don't process mouse events if hovering over UI
	if event is InputEventMouse and _is_mouse_over_ui():
		return

	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(ZOOM_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-ZOOM_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_is_panning = true
				_did_pan = false
				_pan_start = event.position
			else:
				_is_panning = false
				if _did_pan:
					get_viewport().set_input_as_handled() # Consume release if we dragged
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			_pan_start = event.position
			get_viewport().set_input_as_handled()

	# Pan with right-click or middle-mouse drag
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
	if Input.is_action_pressed("ui_left"):
		pan_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		pan_dir.x += 1
	if Input.is_action_pressed("ui_up"):
		pan_dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		pan_dir.y += 1

	if pan_dir != Vector2.ZERO:
		position += pan_dir.normalized() * PAN_SPEED * delta / zoom.x
		_clamp_position()

func _zoom_camera(amount: float) -> void:
	var new_zoom := clampf(zoom.x + amount, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	_clamp_position()

func _is_mouse_over_ui() -> bool:
	# Check if the mouse is hovering over any visible UI panel
	var hud := get_node_or_null("../UILayer/HUD")
	if hud == null:
		return false
	var mouse_pos: Vector2 = hud.get_global_mouse_position()
	for child in hud.get_children():
		if child is Control and child.visible and child.get_global_rect().has_point(mouse_pos):
			return true
	return false

func _clamp_position() -> void:
	# Hex map bounds in pixels (flat-top hex: h_spacing = radius * 1.5, v_spacing = radius * sqrt(3))
	const HEX_RADIUS := 24.0
	const HEX_H_SPACING := HEX_RADIUS * 1.5 # 36.0
	const HEX_V_SPACING := HEX_RADIUS * 1.732 # ~41.57
	var map_width := HexMapData.MAP_WIDTH * HEX_H_SPACING + MAP_MARGIN
	var map_height := HexMapData.MAP_HEIGHT * HEX_V_SPACING + MAP_MARGIN
	position.x = clampf(position.x, -MAP_MARGIN, map_width)
	position.y = clampf(position.y, -MAP_MARGIN, map_height)
