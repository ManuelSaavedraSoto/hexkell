class_name TutorialTileMarker
extends Node2D
## World-space tutorial marker. Lives inside the editor's World node so
## the camera transform applies for free. Two modes:
##   • target tile — pulsing ring around the axial cell the player must
##     place the Int hex on (with a brief red flash on rejected clicks)
##   • edge points — pulsing dots over wire endpoints (the placed hex's
##     output slot + the Do hex) during the wiring step.

const TILE_RADIUS := 58.0
const POINT_RADIUS := 14.0
const RING_WIDTH := 4.0
const BASE_COLOR := Color(1.0, 0.85, 0.35)
const REJECT_COLOR := Color(1.0, 0.3, 0.3)
const REJECT_FLASH_SECONDS := 0.35

var _tile_world: Vector2 = Vector2.ZERO
var _has_tile := false
var _points: Array[Vector2] = []
var _reject_until_msec := 0


func _ready() -> void:
	z_index = 100
	visible = false


func set_target_tile(world_pos: Vector2) -> void:
	_tile_world = world_pos
	_has_tile = true
	visible = true


func set_edge_points(points: Array[Vector2]) -> void:
	_points = points
	_has_tile = false
	visible = true


func clear() -> void:
	_has_tile = false
	_points = []
	visible = false


# Brief red flash on the target ring so a swallowed misplaced click
# reads as "wrong spot", not as a dead button.
func flash_reject() -> void:
	_reject_until_msec = Time.get_ticks_msec() + int(REJECT_FLASH_SECONDS * 1000.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var rejecting := Time.get_ticks_msec() < _reject_until_msec
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 240.0)
	var color := REJECT_COLOR if rejecting else BASE_COLOR
	color.a = 1.0 if rejecting else pulse
	if _has_tile:
		draw_arc(to_local(_tile_world), TILE_RADIUS, 0.0, TAU, 48, color, RING_WIDTH)
	for p in _points:
		draw_arc(to_local(p), POINT_RADIUS, 0.0, TAU, 24, color, RING_WIDTH)
