extends Node2D
## Read-only blueprint renderer for embedding inside a SubViewport.
##
## Decodes a `hxk1:...` blueprint string (or an already-parsed dict)
## via the standard `BlueprintCodec` / `BlueprintLoader` path, parents
## the resulting `HexNode`s + wire `Line2D`s under its own scene tree,
## and frames the internal `Camera2D` to snugly fit every element.
## No input handling — the canvas is purely visual; hosts keep their
## SubViewportContainers at MOUSE_FILTER_IGNORE.
##
## Used by the chapter intro dialog and the blueprint library's
## "Preview" pane.

const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexLevel := preload("res://scenes/gui/hex_editor/hex_level.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")

const WIRE_WIDTH := 4.0
const WIRE_COLOR := Color(0.85, 0.8, 0.55, 0.9)
const WIRE_OPEN_COLOR := Color(0.7, 0.7, 0.75, 0.8)

# Auto-fit zoom bounds. The upper cap keeps single/small blueprints
# from blowing up past native pixel density; the floor is deliberately
# tiny so LARGE grids always fit inside the preview instead of
# clipping.
const ZOOM_MIN := 0.05
const ZOOM_MAX := 1.5

# Breathing room (fraction of the fitted zoom) around the hex bounding
# box when auto-framing.
const FIT_MARGIN := 0.06

var _camera: Camera2D
var _connections: Node2D
var _nodes: Node2D
var _background: ColorRect

var _level: HexLevel


# Lazy binding so callers can `add_child(canvas)` immediately followed
# by `load_blueprint_string(...)` without waiting for `_ready` — the
# packed-scene children already exist as `get_node` targets the moment
# the canvas enters the tree, but `@onready` only fires at `_ready`.
func _bind_refs() -> void:
	if _camera == null:
		_camera = $Camera2D
		_connections = $Connections
		_nodes = $Nodes
		_background = $CanvasLayer/Background


# Per-frame uniform sync so the hex-grid background tracks the
# mini-canvas's own camera (zoom + position). Mirrors the editor's
# main `background.gd` pattern. Cheap — three shader-parameter sets
# per frame.
func _process(_dt: float) -> void:
	if _background == null or _camera == null:
		return
	var mat: ShaderMaterial = _background.material
	if mat == null:
		return
	mat.set_shader_parameter("cam_pos", _camera.global_position)
	mat.set_shader_parameter("zoom", _camera.zoom.x)
	mat.set_shader_parameter(
			"screen_size", get_viewport().get_visible_rect().size)


# Hosts embed this canvas in stretch=true SubViewportContainers, so
# the SubViewport gets (re)sized by container layout after the load —
# re-frame whenever that happens so the snug fit tracks the real size.
func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if _nodes != null and _nodes.get_child_count() > 0:
		_auto_frame()


## Decode a `hxk1:...` string and load the resulting payload.
## Returns true on success; false (and a push_warning) on decode
## failure so a caller's fallback chain can pick the next branch.
func load_blueprint_string(encoded: String) -> bool:
	var payload = BlueprintCodec.decode(encoded.strip_edges())
	if payload == null:
		push_warning("BlueprintMiniCanvas: failed to decode blueprint string")
		return false
	return load_blueprint_dict(payload)


## Load an already-parsed payload. Useful for the library-preview
## case where the dict is already in memory.
func load_blueprint_dict(payload: Dictionary) -> bool:
	_bind_refs()
	_clear()
	# HexLevel is a Node now (was RefCounted) but is used here purely
	# as a data container that never enters the tree — `_clear` /
	# `_exit_tree` free it explicitly so preview hydration can't leak
	# orphans.
	_level = HexLevel.new()

	# Recreate the fixture (DoHex) when the payload carries one — root
	# captures always do, selection captures do when the Do was part of
	# the drag-select. The loader needs it to rebind wires touching the
	# fixture id; we also need it parented so the visual matches what
	# the author saw. `fixture_axial` (relative to the capture origin)
	# places it; older payloads without the field default to (0,0).
	var fixture: HexNode = null
	if payload.has("fixture_id"):
		fixture = HexNode.from_script(DoHex)
		_nodes.add_child(fixture)
		var fa: Array = payload.get("fixture_axial", [0, 0])
		fixture.set_axial(Vector2i(int(fa[0]), int(fa[1])))
		_level.hexes.append(fixture)

	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO, fixture, 0)

	# `_nodes` is already inside the SubViewport tree, so `add_child`
	# fires each hex's `_ready` SYNCHRONOUSLY — and `_ready` calls
	# `_build_slots()`, which bakes the rotation in via
	# `physical_edge() = (logical + rotation_index) % 6`. So the rotation
	# field must be set BEFORE `add_child`, or the slots build at rotation
	# 0 and never rebuild (the preview would ignore the saved rotation).
	# Write the field directly rather than `set_rotation_index()`: the
	# setter re-runs `_build_slots()`, which touches the `@onready var
	# _edge_nodes` typed array — null until `_ready`, so calling it here
	# (or were `_ready` ever deferred) would fault.
	var pending_wires: Array = built.get("wires", [])
	for record in built.get("hexes", []):
		var hex: HexNode = record["node"]
		hex.rotation_index = int(record.get("rotation", 0))
		_nodes.add_child(hex)
		hex.set_axial(record["axial"])
		_level.hexes.append(hex)

	# Wires depend on each hex's `slot_world_position` (which reads
	# `_edge_nodes`) — defer their install until after `_ready` has
	# fired for every hex we just added.
	call_deferred("_finish_wires", pending_wires)
	return true


func _finish_wires(wires: Array) -> void:
	for w in wires:
		_install_wire(w)
	_auto_frame()


# Build the Line2D for a freshly instantiated wire, parent it, paint it.
# Mirrors `hex_editor.gd::_install_loaded_wire` minus the per-level
# bookkeeping that doesn't apply to a read-only canvas.
func _install_wire(w: HexWire) -> void:
	var line := Line2D.new()
	line.width = WIRE_WIDTH
	line.default_color = WIRE_OPEN_COLOR if w.is_open else WIRE_COLOR
	HexWire.attach_shader_to(line)
	_connections.add_child(line)
	w.line = line
	w.paint(Vector2.ZERO)
	_level.wires.append(w)


func _clear() -> void:
	for child in _nodes.get_children():
		child.queue_free()
	for child in _connections.get_children():
		child.queue_free()
	if _level != null:
		_level.free()  # data-only Node, never in the tree
	_level = null


func _exit_tree() -> void:
	if _level != null:
		_level.free()
		_level = null


# Center the camera on the hex bounding-box centroid; pick the zoom
# that snugly fits the box within the viewport. The bbox spans hex
# *centers*, so grow it by one HEX_SIZE per side to cover each hex's
# own extent — that also gives a single hex a real (non-zero) box, so
# every payload goes through the same fit math. Empty payload →
# push_warning + leave camera at origin.
func _auto_frame() -> void:
	if _nodes.get_child_count() == 0:
		push_warning("BlueprintMiniCanvas: payload contains no hexes to frame")
		return
	var first := true
	var bbox := Rect2()
	for child in _nodes.get_children():
		var p: Vector2 = (child as Node2D).position
		if first:
			bbox = Rect2(p, Vector2.ZERO)
			first = false
		else:
			bbox = bbox.expand(p)
	bbox = bbox.grow(HexNode.HEX_SIZE)
	_camera.position = bbox.get_center()
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_camera.zoom = Vector2.ONE
		return
	var fit := minf(
		viewport_size.x / bbox.size.x,
		viewport_size.y / bbox.size.y,
	) * (1.0 - FIT_MARGIN)
	_camera.zoom = Vector2.ONE * clampf(fit, ZOOM_MIN, ZOOM_MAX)
