class_name HexWire
extends RefCounted
## A wire connecting one hex's output side to another hex's input side
## (or ending unconnected at an empty cell, when `is_open`).
##
## Wires occupy a sequence of empty grid cells, entering each on one
## physical side and exiting on another, pivoting at the cell's center
## (Factorio-belt style). Adjacent cells share the boundary between
## their enter/exit edges, so the rendered polyline is continuous.
##
## Endpoints are stored as `output_node/edge` and `input_node/edge` for
## directional semantics (used by `get_input_for`). During routing,
## `anchor_*` records the slot the user clicked first — the wire grows
## from that slot toward the mouse, and the cell sequence is ordered
## anchor → cursor.

const _WIRE_SHADER := preload("res://assets/shaders/wire_flow.gdshader")
const _WIRE_TEXTURE := preload("res://assets/textures/white_pixel.png")

# Committed-wire look. The editor's interactive tints (preview /
# anchored / error) stay on hex_editor.gd; these are what a finalized
# wire renders with, shared with TabStore's load path.
const WIDTH := 4.0
const COLOR := Color(0.85, 0.8, 0.55, 0.9)
const OPEN_COLOR := Color(0.7, 0.7, 0.75, 0.8)

# A wire's cells are Dictionaries: { axial: Vector2i, enter_edge: int,
# exit_edge: int }, where `enter_edge` / `exit_edge` are physical edges
# (0..5) on the cell itself. `exit_edge == -1` means the wire dangles
# (no next cell yet — used while routing).

# Endpoint slots — wire flows from output_node to input_node.
var output_node: HexNode = null
var output_edge: int = -1     # logical edge on output_node
var input_node: HexNode = null
var input_edge: int = -1      # logical edge on input_node

# Ordered cells from anchor → cursor.
var cells: Array = []

# First `anchored_count` cells are locked: re-routing only affects the
# tail beyond `cells[anchored_count - 1]`.
var anchored_count: int = 0

# Indices into `cells` of the user's chain points (pressed C). Each entry
# is a "locked" cell the wire is pinned to. `anchored_count` stays in sync
# as the routing prefix (one past the last lock). Used only for routing
# feedback (the chain overlay) — finalized wires don't read it.
var lock_indices: Array[int] = []

# True once the wire is committed.
var is_finalized: bool = false

# True if the wire is finalized without a second endpoint — ends at the
# last cell's center as an unconnected stub (for cable-management
# planning). Open wires don't contribute to `get_input_for`.
var is_open: bool = false

# Set by the router when the tail couldn't reach the requested target
# (the wire is boxed in). The last cell renders in red.
var is_stuck: bool = false

# The endpoint the user clicked first (the wire's anchor). The cell
# sequence is ordered as if leaving from this slot.
var anchor_node: HexNode
var anchor_edge: int
var anchor_is_output: bool

# Rendering. The editor owns the Line2Ds; the wire just paints them.
# `line` is the main polyline; `error_line` overlays the last cell in
# red when `is_stuck`.
var line: Line2D = null
var error_line: Line2D = null

# Cache the last pulse-state pushed to the line's shader so paint()
# only re-pushes when the values actually change.
var _last_pulse_enabled: bool = false
var _last_flow_forward: bool = true


# Bind the wire-flow shader + 1×1 white texture to a Line2D so its
# fragment shader can animate a pulse along UV.x. Caller still sets
# `default_color` / `width` for the wire's base color and stroke; the
# shader multiplies `base_color * COLOR` and `base_color` defaults to
# white, so existing `default_color` behavior is preserved.
static func attach_shader_to(line: Line2D) -> void:
	if line == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _WIRE_SHADER
	line.material = mat
	line.texture = _WIRE_TEXTURE
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH


## Build the standard Line2D for a finalized wire (committed or open).
static func build_line(p_is_open: bool) -> Line2D:
	var line := Line2D.new()
	line.width = WIDTH
	line.default_color = OPEN_COLOR if p_is_open else COLOR
	attach_shader_to(line)
	return line


static func from_anchor(node: HexNode, edge: int, is_output: bool) -> HexWire:
	var w := HexWire.new()
	w.anchor_node = node
	w.anchor_edge = edge
	w.anchor_is_output = is_output
	if is_output:
		w.output_node = node
		w.output_edge = edge
	else:
		w.input_node = node
		w.input_edge = edge
	return w


# Bind the second endpoint and mark the wire finalized. Caller must have
# already routed `cells` so the last cell sits adjacent to the sink hex
# with its exit_edge pointing into the sink.
func finalize_with(node: HexNode, edge: int) -> void:
	if anchor_is_output:
		input_node = node
		input_edge = edge
	else:
		output_node = node
		output_edge = edge
	is_finalized = true
	is_open = false
	is_stuck = false


# Finalize as an open wire — ends at the last cell's center, no sink.
func finalize_open() -> void:
	is_finalized = true
	is_open = true
	is_stuck = false


# Anchor all current cells — they can no longer be re-routed away. Note
# that the LAST anchored cell's `exit_edge` is still recomputed each
# frame by the editor's router (it's the seed for the dynamic tail).
# Earlier anchored cells (indices 0..anchored_count-2) have their
# exit_edges frozen.
func anchor_here() -> void:
	add_lock()


# Pin the current tail cell as a chain point (the user pressed C). Records
# its index in `lock_indices` and advances the routing prefix. No-op if
# there are no cells yet or the tail is already the last lock.
func add_lock() -> void:
	if cells.is_empty():
		return
	var idx := cells.size() - 1
	if lock_indices.is_empty() or lock_indices.back() != idx:
		lock_indices.append(idx)
	anchored_count = cells.size()


# Unlock the chain point at `axial` (and every later one), re-opening the
# tail for routing. Returns true if a locked cell sat at `axial`.
func unlock_from_axial(axial: Vector2i) -> bool:
	for p in lock_indices.size():
		var idx: int = lock_indices[p]
		if idx < cells.size() and cells[idx].axial == axial:
			lock_indices = lock_indices.slice(0, p)
			anchored_count = 0 if lock_indices.is_empty() else lock_indices.back() + 1
			return true
	return false


# The axials of the wire's current chain points, for the routing overlay.
func locked_axials() -> Array:
	var out: Array = []
	for idx in lock_indices:
		if idx < cells.size():
			out.append(cells[idx].axial)
	return out


# Truncate the tail back to the anchored prefix. Used before re-routing
# in response to mouse motion.
func truncate_to_anchored() -> void:
	while cells.size() > anchored_count:
		cells.pop_back()


# Return true if any cell of this wire sits at `axial`.
func contains_axial(axial: Vector2i) -> bool:
	for cell in cells:
		if cell.axial == axial:
			return true
	return false


# Repaint the polyline. `tail_world_pos` is used when the wire is still
# routing (it dangles toward the cursor). When `is_stuck`, the last
# cell's segments are split off onto `error_line` (red); the main
# `line` stops at the last cell's enter-midpoint.
func paint(tail_world_pos: Vector2) -> void:
	if line == null:
		return
	line.clear_points()
	if error_line:
		error_line.clear_points()

	var pts := _polyline_points(tail_world_pos)

	# When the router gave up (no valid path within the look-ahead budget)
	# the ENTIRE wire renders red, not just the dead-end cell — a loud
	# signal that this route can't be committed. Otherwise the normal
	# `line` (preview / anchored / committed colour) carries the polyline.
	var target_line := error_line if (is_stuck and error_line != null) else line
	for p in pts:
		target_line.add_point(p)
	_refresh_pulse_uniforms()


# Build the continuous polyline for the wire: anchor slot → each cell
# (center, then exit-edge midpoint) → tail. The tail is the sink slot for
# a committed wire, the last cell's center for an open wire, or the live
# cursor while the wire is still routing.
func _polyline_points(tail_world_pos: Vector2) -> Array:
	var pts: Array = []
	if cells.is_empty():
		# Degenerate: no cells yet. A short hint from anchor toward tail.
		pts.append(anchor_node.slot_world_position(anchor_edge))
		if not is_finalized:
			pts.append(tail_world_pos)
		return pts

	pts.append(anchor_node.slot_world_position(anchor_edge))
	for cell in cells:
		var center := HexMath.axial_to_world(cell.axial, HexNode.HEX_SIZE)
		pts.append(center)
		if cell.exit_edge >= 0:
			pts.append(center + HexMath.edge_offset(cell.exit_edge, HexNode.HEX_SIZE))

	if is_finalized:
		if not is_open:
			var sink := input_node if anchor_is_output else output_node
			var sink_e := input_edge if anchor_is_output else output_edge
			pts.append(sink.slot_world_position(sink_e))
		# Open finalized: tail = last cell's center (already added).
	else:
		pts.append(tail_world_pos)
	return pts


# Push the pulse uniforms onto `line.material`. Called at the tail of
# `paint()`. Cached so we only `set_shader_parameter` when the values
# actually change (paint() runs every frame).
func _refresh_pulse_uniforms() -> void:
	if line == null:
		return
	var mat := line.material as ShaderMaterial
	if mat == null:
		return
	var pulse_enabled := is_finalized and not is_open and not is_stuck
	var flow_forward := anchor_is_output
	if pulse_enabled != _last_pulse_enabled:
		mat.set_shader_parameter("pulse_enabled", pulse_enabled)
		_last_pulse_enabled = pulse_enabled
	if flow_forward != _last_flow_forward:
		mat.set_shader_parameter("flow_forward", flow_forward)
		_last_flow_forward = flow_forward


# Make a fresh cell dictionary.
static func make_cell(axial: Vector2i, enter_edge: int, exit_edge: int = -1) -> Dictionary:
	return {"axial": axial, "enter_edge": enter_edge, "exit_edge": exit_edge}
