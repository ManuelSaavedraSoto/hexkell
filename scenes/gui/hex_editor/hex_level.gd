class_name HexLevel
extends Node2D
## One "canvas" of the visual editor, now a real scene-tree container:
## the level node owns a `Connections` child (wire Line2Ds) and a
## `Nodes` child (this level's hexes). The editor navigates a stack of
## levels per tab; only the top-of-stack is active. Pressing `Q` over
## a hex with an inner level pushes onto the stack; `E` pops.
##
## Activation is one visibility flip on this node (children render or
## don't with it) plus an explicit pickability pass — Area2D picking
## ignores CanvasItem visibility, so hidden levels must also disable
## their hexes' areas.

# The hex this is the inner level of. Null for level 0 (the program's
# main canvas).
var parent_hex: HexNode = null

# The anchor at (0,0) of this level — emits identifier(s) into local
# scope and exposes a return slot fed by the level's body. Null for
# level 0 (it has no anchor; the DoHex and definition hexes float).
var anchor: HexNode = null

# Members of this level. Hexes include the anchor when present.
# Parked hexes (deleted-with-undo) are NOT in `hexes` but remain
# children of `nodes` (hidden + unpickable) so undo can restore them.
var hexes: Array = []
var wires: Array[HexWire] = []

# Per-level camera state. Saved on switch-away, restored on switch-
# back, so each level keeps its own viewpoint. `world_position` is the
# Camera2D's world-space position, `world_scale` its zoom scalar.
var world_position: Vector2 = Vector2.ZERO
var world_scale: float = 1.0

# Scene-tree containers, built by `create()`.
var nodes: Node2D = null
var connections: Node2D = null

var active: bool = false


# Constructible bare (`HexLevel.new(parent_hex)`) as a pure data
# container — the codec, the blueprint mini-canvas, and tests build
# levels that never enter the scene tree. Editor levels go through
# `create()`, which also builds the Nodes/Connections containers.
func _init(p_parent: HexNode = null) -> void:
	parent_hex = p_parent


## Factory for real scene-tree levels — builds the two container
## children. Starts inactive (hidden, nothing pickable).
static func create(p_parent: HexNode = null) -> HexLevel:
	var lvl := HexLevel.new()
	lvl.name = "HexLevel"
	lvl.parent_hex = p_parent
	lvl.connections = Node2D.new()
	lvl.connections.name = "Connections"
	lvl.add_child(lvl.connections)
	lvl.nodes = Node2D.new()
	lvl.nodes.name = "Nodes"
	lvl.add_child(lvl.nodes)
	lvl.visible = false
	return lvl


## Add a hex as a member of this level: parents it under `nodes`,
## binds the back-reference, and matches its pickability to the
## level's activation state.
func add_hex(hex: HexNode) -> void:
	nodes.add_child(hex)
	hex.level = self
	hexes.append(hex)
	hex.set_pickable(active)


## Parent a transient node (blueprint/stamp preview) under this
## level's containers WITHOUT making it a member — previews manage
## their own pickability and never appear in `hexes`.
func add_preview(hex: HexNode) -> void:
	nodes.add_child(hex)


func add_wire_line(line: Line2D) -> void:
	connections.add_child(line)


## One-flip show/hide for the whole level. Live hexes keep their
## individual `visible = true`; parked hexes stay individually hidden
## and aren't in `hexes`, so they stay invisible and unpickable.
func set_active(p_active: bool) -> void:
	active = p_active
	visible = p_active
	# Show opaque by default. The editor's level-transition fade drops
	# this to 0 and tweens it back up *after* calling set_active(true);
	# resetting here guarantees a level left mid-fade (interrupted Q/E, or
	# a tab switch) never reappears dimmed.
	if p_active:
		modulate.a = 1.0
	for h in hexes:
		if is_instance_valid(h):
			h.set_pickable(p_active)
