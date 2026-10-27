class_name HexMath
extends RefCounted
## Pointy-top axial-coordinate math.
##
## Axial: (q, r), r increasing downward (screen y-down convention).
## Edges/neighbor directions numbered clockwise from East:
##   0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE.

const SQRT3 := 1.7320508075688772

const EDGE_DELTAS: Array[Vector2i] = [
	Vector2i( 1,  0),  # 0 E
	Vector2i( 0,  1),  # 1 SE
	Vector2i(-1,  1),  # 2 SW
	Vector2i(-1,  0),  # 3 W
	Vector2i( 0, -1),  # 4 NW
	Vector2i( 1, -1),  # 5 NE
]

const EDGE_NAMES: Array[String] = ["E", "SE", "SW", "W", "NW", "NE"]

# Slot edges for an arity-N fixture, in a fixed prefix-stable order
# clockwise from NE: NE, E, SE, SW, W, NW. Arity N takes the first N, so
# growing arity appends the next edge and shrinking pops the last — every
# existing slot (and its wire) keeps its edge. This is what lets arity
# changes be incremental instead of purging the inner level. Mirrors
# `ListAnchor.SLOT_EDGES`.
const EDGE_ORDER: Array[int] = [5, 0, 1, 2, 3, 4]
# Arity-configurable fixtures (tuple / match / lambda / definition) cap
# here; the list anchor uses all six edges via `EDGE_ORDER` directly.
const MAX_ARITY := 5


static func edge_name(edge: int) -> String:
	return EDGE_NAMES[((edge % 6) + 6) % 6]


# The first `n` slot edges in canonical clockwise-from-NE order.
static func edges_for_arity(n: int) -> Array:
	return EDGE_ORDER.slice(0, clampi(n, 0, EDGE_ORDER.size()))


static func axial_to_world(coord: Vector2i, size: float) -> Vector2:
	var q := float(coord.x)
	var r := float(coord.y)
	return Vector2(size * SQRT3 * (q + r * 0.5), size * 1.5 * r)


# Rotate an axial coord by `k * 60°` clockwise around the origin.
# One step CW in cube space: (q, r) → (-r, q + r). Repeated k times
# (posmod into 0..5 so callers can pass any int).
static func rotate_axial(coord: Vector2i, k: int) -> Vector2i:
	var n := posmod(k, 6)
	var result := coord
	for _i in n:
		result = Vector2i(-result.y, result.x + result.y)
	return result


# Cube-distance between two axial coords. The two cells share a
# face when this returns 1.
static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	var ds := -dq - dr
	return int((abs(dq) + abs(dr) + abs(ds)) / 2)


# Direction index (0..5) such that `to == from + EDGE_DELTAS[d]`, or
# -1 if `from` and `to` are not axial neighbors. Used by the wire
# router to figure out which physical edge to leave through.
static func step_direction(from: Vector2i, to: Vector2i) -> int:
	var delta: Vector2i = to - from
	for d in 6:
		if EDGE_DELTAS[d] == delta:
			return d
	return -1


static func world_to_axial(world: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * world.x - world.y / 3.0) / size
	var r := (world.y * 2.0 / 3.0) / size
	return _axial_round(q, r)


static func _axial_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx = round(x)
	var ry = round(y)
	var rz = round(z)
	var dx = abs(rx - x)
	var dy = abs(ry - y)
	var dz = abs(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy <= dz:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


# Local offset (relative to a hex center) of the midpoint of edge `i`.
static func edge_offset(i: int, size: float) -> Vector2:
	var ang := deg_to_rad(60.0 * i)
	var apothem := size * SQRT3 / 2.0
	return Vector2(cos(ang), sin(ang)) * apothem


# Local offset of vertex `i`. Vertex 0 is the top of the hex (pointy-top).
static func vertex_offset(i: int, size: float) -> Vector2:
	var ang := deg_to_rad(-90.0 + 60.0 * i)
	return Vector2(cos(ang), sin(ang)) * size


static func hex_polygon(size: float) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in 6:
		arr.append(vertex_offset(i, size))
	return arr
