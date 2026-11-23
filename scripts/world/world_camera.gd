class_name WorldCamera
extends Camera2D
## Smooth cursor-centered zoom and panning clamped strictly to the framed rectangular world.

@export var map_size: Vector2 = Vector2(2048.0, 1024.0)
@export var border_margin: Vector2 = Vector2(96.0, 68.0)
@export var max_zoom: float = 6.5
@export var zoom_step: float = 1.18
@export var pan_speed: float = 720.0
@export var smoothing_rate: float = 16.0

var _target_zoom: float = 1.0
var _target_pos: Vector2 = Vector2(1024.0, 512.0)
var _min_zoom: float = 0.45
var _is_dragging: bool = false
var _drag_button: int = 0
var _drag_total_dist: float = 0.0
var _last_drag_screen: Vector2 = Vector2.ZERO


func _ready() -> void:
	position = map_size * 0.5
	_target_pos = position
	_recompute_min_zoom()
	_target_zoom = _min_zoom
	zoom = Vector2(_target_zoom, _target_zoom)
	get_viewport().size_changed.connect(_on_viewport_resized)


func reset_view() -> void:
	_recompute_min_zoom()
	_target_zoom = _min_zoom
	_target_pos = map_size * 0.5


func _on_viewport_resized() -> void:
	_recompute_min_zoom()
	_target_zoom = clampf(_target_zoom, _min_zoom, max_zoom)
	_clamp_target_pos()


func _recompute_min_zoom() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return
	var framed := map_size + border_margin * 2.0
	_min_zoom = clampf(minf(vp_size.x / framed.x, vp_size.y / framed.y), 0.30, 1.5)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		_target_pos += dir.normalized() * (pan_speed / maxf(_target_zoom, 0.25)) * delta
		_clamp_target_pos()

	var t: float = 1.0 - exp(-smoothing_rate * delta)
	zoom = zoom.lerp(Vector2(_target_zoom, _target_zoom), t)
	position = position.lerp(_target_pos, t)
	_clamp_current_pos()


func handle_map_input(event: InputEvent) -> bool:
	"""Returns true if event consumed as camera drag/zoom (suppresses province selection)."""
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom_at_screen_pos(_target_zoom * zoom_step, mb.position)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom_at_screen_pos(_target_zoom / zoom_step, mb.position)
			return true
		if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT]:
			if mb.pressed:
				_is_dragging = true
				_drag_button = mb.button_index
				_drag_total_dist = 0.0
				_last_drag_screen = mb.position
			elif _is_dragging and mb.button_index == _drag_button:
				var was_pan: bool = (_drag_total_dist > 6.0) or (_drag_button == MOUSE_BUTTON_MIDDLE)
				_is_dragging = false
				_drag_button = 0
				return was_pan
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var screen_delta: Vector2 = mm.position - _last_drag_screen
		_last_drag_screen = mm.position
		_drag_total_dist += screen_delta.length()
		if _drag_button != MOUSE_BUTTON_LEFT or _drag_total_dist > 6.0:
			_target_pos -= screen_delta / maxf(zoom.x, 0.1)
			_clamp_target_pos()
			return true
	return false


func _apply_zoom_at_screen_pos(new_zoom_scalar: float, screen_pos: Vector2) -> void:
	var clamped_zoom: float = clampf(new_zoom_scalar, _min_zoom, max_zoom)
	if is_equal_approx(clamped_zoom, _target_zoom):
		return
	var vp_center: Vector2 = get_viewport_rect().size * 0.5
	var offset_from_center: Vector2 = screen_pos - vp_center
	var world_under_cursor: Vector2 = _target_pos + offset_from_center / _target_zoom
	_target_zoom = clamped_zoom
	_target_pos = world_under_cursor - offset_from_center / _target_zoom
	_clamp_target_pos()


func _clamp_target_pos() -> void:
	_target_pos = _clamp_pos_for_zoom(_target_pos, _target_zoom)


func _clamp_current_pos() -> void:
	position = _clamp_pos_for_zoom(position, zoom.x)


func _clamp_pos_for_zoom(p: Vector2, z: float) -> Vector2:
	var vp_half: Vector2 = (get_viewport_rect().size * 0.5) / maxf(z, 0.1)
	var min_bound := -border_margin
	var max_bound := map_size + border_margin
	var span := max_bound - min_bound

	var out_x: float = p.x
	var out_y: float = p.y
	if vp_half.x * 2.0 >= span.x:
		out_x = map_size.x * 0.5
	else:
		out_x = clampf(p.x, min_bound.x + vp_half.x, max_bound.x - vp_half.x)

	if vp_half.y * 2.0 >= span.y:
		out_y = map_size.y * 0.5
	else:
		out_y = clampf(p.y, min_bound.y + vp_half.y, max_bound.y - vp_half.y)
	return Vector2(out_x, out_y)
