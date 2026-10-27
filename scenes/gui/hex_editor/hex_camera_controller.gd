extends Camera2D
class_name HexCameraController

# Owns pan + zoom for the hex editor's canvas viewport. Keeps the
# editor's `_unhandled_input` out of the business of moving the
# camera around: keyboard pan polls the InputMap each frame, wheel
# zoom + middle-drag pan come in through `_unhandled_input` and pivot
# the camera around the mouse cursor.

# Tutorial-facing movement signals: the FSM accumulates pan distance /
# counts zoom steps to verify the player tried each control. Emitted
# only on actual movement (gated input and clamped zoom stay silent).
signal panned_keyboard(world_delta: Vector2)
signal panned_mouse(world_delta: Vector2)
signal zoomed(new_zoom: float)

const PAN_KB_SPEED := 600.0  # pixels per second in screen space
const ZOOM_STEP := 1.1       # mouse-wheel multiplicative step
const ZOOM_KB_RATE := 2.0    # factor per second when zoom key is held
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0

var _panning: bool = false


# Modal gating is pause-based (ModalStack): an open dialog pauses the
# tree and this PAUSABLE camera stops receiving _process and
# _unhandled_input entirely, so no explicit modal checks are needed.
func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_keyboard_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	# H / Ctrl+H recenter the camera — handled by the editor (it owns
	# the level stack + the slerp tween).
	if event is InputEventMouseMotion:
		if _panning:
			var mm := event as InputEventMouseMotion
			# Camera moves opposite the drag (drag right → world scrolls
			# left). Divide by zoom so a 1-screen-pixel drag is always
			# 1 screen pixel of visual motion.
			var pan_delta := mm.relative / zoom.x
			position -= pan_delta
			panned_mouse.emit(pan_delta)
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("canvas_zoom_in", false, true):
			_zoom_around_cursor(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("canvas_zoom_out", false, true):
			_zoom_around_cursor(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()


func _handle_keyboard_pan(delta: float) -> void:
	if _is_input_gated():
		return
	var move := Vector2.ZERO
	if Input.is_action_pressed("canvas_pan_up"):
		move.y += 1
	if Input.is_action_pressed("canvas_pan_down"):
		move.y -= 1
	if Input.is_action_pressed("canvas_pan_left"):
		move.x += 1
	if Input.is_action_pressed("canvas_pan_right"):
		move.x -= 1
	if move == Vector2.ZERO:
		return
	# WASD moves the camera the same way arrow-keys would; the visible
	# world shifts in the OPPOSITE direction of camera motion. Divide
	# by zoom so a zoomed-in view pans at the same on-screen px/sec
	# as a zoomed-out one.
	var pan_delta := -move.normalized() * PAN_KB_SPEED * delta / zoom.x
	position += pan_delta
	panned_keyboard.emit(pan_delta)


func _handle_keyboard_zoom(delta: float) -> void:
	if _is_input_gated():
		return
	var dir := 0.0
	if Input.is_action_pressed("canvas_zoom_in"):
		dir += 1.0
	if Input.is_action_pressed("canvas_zoom_out"):
		dir -= 1.0
	if dir == 0.0:
		return
	var factor: float = pow(ZOOM_KB_RATE, dir * delta)
	_zoom_around_cursor(factor)


func _zoom_around_cursor(factor: float) -> void:
	# Pivot the zoom on the cursor: keep the world-space point the
	# mouse hovers stationary as the zoom changes. Camera2D.zoom
	# semantics (Godot 4): higher = zoomed IN.
	var old_zoom := zoom.x
	var new_zoom: float = clamp(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var mouse_world_before := get_global_mouse_position()
	zoom = Vector2.ONE * new_zoom
	var mouse_world_after := get_global_mouse_position()
	position += mouse_world_before - mouse_world_after
	zoomed.emit(new_zoom)


func _is_input_gated() -> bool:
	# Typing into a LineEdit shouldn't drift the camera. (Modal
	# dialogs need no check here — they pause the tree, which stops
	# this node's _process from polling at all.)
	return InputGates.text_input_focused(get_viewport())
