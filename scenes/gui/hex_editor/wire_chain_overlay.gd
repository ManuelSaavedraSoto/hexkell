class_name WireChainOverlay
extends Node2D
## Draws a hex-cell wireframe over the cells the active wire passes through
## while it's being routed. Pinned (chain / locked) cells are tinted cyan
## with a lock icon in the centre; everything else is a faint gray outline.
## Lives only during routing — the editor calls `set_wire` while a wire is
## active and `clear` on commit/cancel.

const HexMath := preload("res://src/statics/hex_math.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")

const LOCK_ICON := preload("res://assets/icons/buttons/locked.tres")

# Faint outline for every traversed cell; cyan for pinned chain points.
const FRAME_COLOR := Color(0.8, 0.8, 0.85, 0.5)
const LOCK_COLOR := Color(0.55, 0.85, 1.0, 0.9)
const OUTLINE_WIDTH := 2.0
const LOCK_ICON_SIZE := 28.0

var wire: HexWire = null

# Transient scale-bounce on the cell that was just locked, for tactile
# feedback. Only the cell at `_pop_axial` is scaled, by `_pop_scale`.
var _pop_axial: Vector2i = Vector2i.ZERO
var _pop_scale: float = 1.0
var _pop_tween: Tween


func set_wire(w: HexWire) -> void:
	wire = w
	queue_redraw()


func clear() -> void:
	wire = null
	_kill_pop()
	queue_redraw()


# Pop the just-locked cell at `axial`: a quick scale-bounce on its cyan
# outline + lock icon when the player pins a chain point.
func pop_cell(axial: Vector2i) -> void:
	_pop_axial = axial
	_kill_pop()
	_pop_tween = create_tween()
	_pop_tween.tween_method(_set_pop_scale, 1.4, 1.0, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pop_scale(s: float) -> void:
	_pop_scale = s
	queue_redraw()


func _kill_pop() -> void:
	if _pop_tween:
		_pop_tween.kill()
		_pop_tween = null
	_pop_scale = 1.0


func _draw() -> void:
	if wire == null or wire.cells.is_empty():
		return
	var locked := wire.locked_axials()
	for cell in wire.cells:
		var center := HexMath.axial_to_world(cell.axial, HexNode.HEX_SIZE)
		var is_locked: bool = cell.axial in locked
		# Only the freshly-locked cell bounces; everything else draws at 1.0.
		var s: float = _pop_scale if (is_locked and cell.axial == _pop_axial) else 1.0
		var outline := PackedVector2Array()
		for v in HexMath.hex_polygon(HexNode.HEX_SIZE):
			outline.append(center + v * s)
		outline.append(outline[0])  # close the loop
		draw_polyline(outline, LOCK_COLOR if is_locked else FRAME_COLOR, OUTLINE_WIDTH)
		if is_locked:
			var size := LOCK_ICON_SIZE * s
			var half := size * 0.5
			draw_texture_rect(
				LOCK_ICON,
				Rect2(center - Vector2(half, half), Vector2(size, size)),
				false,
				LOCK_COLOR,
			)
