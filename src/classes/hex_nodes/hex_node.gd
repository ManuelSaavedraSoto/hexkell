class_name HexNode
extends Node2D
## Base class for hex-tile expression nodes.
## Uses a pre-built scene structure with 1 central Body area and 6 Edge areas.

signal node_grab_started(node: HexNode)
## Double-click on the body: the editor "picks up" the hex — cuts it to
## the stamp (preserving its full config / rotation / inner level) so the
## player can re-place it elsewhere.
signal node_pickup_requested(node: HexNode)
signal slot_grab_started(node: HexNode, edge: int, is_output: bool)
signal delete_requested(node: HexNode)
signal scrolled(node: HexNode, dir: int)
## Emitted by arity-configurable hexes (tuple / match / lambda /
## definition) when the player asks for a new arity. The editor owns the
## change: it calls `apply_arity`, drops only the wire(s) on any removed
## slot, and records an undoable action — the rest of the inner level
## (and the undo history) survives.
signal arity_change_requested(node: HexNode, new_arity: int)
## Emitted by subclasses whenever their user-editable config value
## changes (sidebar widget edit, body scroll, …). The tutorial listens
## for this on the placed Int hex during the "set the number" step.
signal config_value_changed(node: HexNode)

@export_group("Visuals")
@export var badge_texture: Texture2D
@export var body_color: Color = Color(0.18, 0.18, 0.22)
@export var body_texture: Texture2D
@export var input_color: Color = Color(0.45, 0.70, 1.0)
@export var output_color: Color = Color(1.0, 0.78, 0.40)
@export var disabled_edge_color: Color = Color(0.353, 0.353, 0.353)

const HEX_SIZE := 64.0
const SLOT_PICK_RADIUS := 8.0

var axial: Vector2i = Vector2i.ZERO
var input_edges: Array[int] = []   # logical edge indices (0..5)
var output_edges: Array[int] = []  # logical edge indices (0..5)

var input_role_names: Dictionary = {}
var output_role_names: Dictionary = {}
var optional_input_edges: Array[int] = []
# When true, every input edge is one logical slot — the hex takes a
# single wire total, approachable from any side (DoHex, AnchorHex).
# The editor's wire-commit replaces across the whole group, not just
# the same edge.
var exclusive_input_group: bool = false

# On-canvas slot words for hexes where argument order matters
# (logical edge → ≤5-char text, e.g. {4: "left", 2: "right"}).
# Empty (the default) means no labels — commutative operators stay
# clean. Labels follow rotation via `_build_slots`.
var input_role_labels: Dictionary = {}
# Optional per-label font colour (logical edge → Color). Empty entries
# fall back to the neutral default. Lets the lambda tint each
# parameter's glyph by its identifier colour.
var input_role_label_colors: Dictionary = {}
var _role_labels: Dictionary = {}  # logical edge → Label

# Per-edge "this input is fed" highlight. The editor recomputes the set
# after structural changes; `_build_slots` re-applies it so rotation /
# arity rebuilds don't clear the highlight.
var _connected_edges: Array = []
var _edge_flash_tweens: Dictionary = {}  # physical edge → Tween

var rotation_index: int = 0
var _pickable: bool = true
var is_fixture: bool = false
var level = null # Type: HexLevel
var inner_level = null # Type: HexLevel

var _content_root: Node2D
var _visiting: bool = false

# Scene References
@onready var _body_area: Area2D = %HexBodyArea
@onready var _body_poly: Polygon2D = %HexBodyArea/HexPolygon
@onready var _badge_sprite: Sprite2D = %BadgeSprite

# Array of physical edges mapping to scene nodes.
# Indices strictly follow: 0:Right, 1:BottomRight, 2:BottomLeft, 3:Left, 4:TopLeft, 5:TopRight
# `area` = the precise trapezoid Area2D (the wire-drop snap target,
# queried via physics intersect_point). `anchor_area` = the forgiving
# capsule Area2D centered on the edge midpoint (the drag-start target,
# and the physics-overlap shape that lets adjacent hexes detect each
# other touching). The two never both receive input.
@onready var _edge_nodes: Array[Dictionary] = [
	{ "area": %EdgeRight, "poly": %EdgeRight/Polygon2D, "anchor": %EdgeRight/Anchor,
	  "anchor_area": %EdgeRight/Anchor/Area2D,
	  "anchor_shape": %EdgeRight/Anchor/Area2D/CollisionShape2D },
	{ "area": %EdgeBottomRight, "poly": %EdgeBottomRight/Polygon2D, "anchor": %EdgeBottomRight/Anchor,
	  "anchor_area": %EdgeBottomRight/Anchor/Area2D,
	  "anchor_shape": %EdgeBottomRight/Anchor/Area2D/CollisionShape2D },
	{ "area": %EdgeBottomLeft, "poly": %EdgeBottomLeft/Polygon2D, "anchor": %EdgeBottomLeft/Anchor,
	  "anchor_area": %EdgeBottomLeft/Anchor/Area2D,
	  "anchor_shape": %EdgeBottomLeft/Anchor/Area2D/CollisionShape2D },
	{ "area": %EdgeLeft, "poly": %EdgeLeft/Polygon2D, "anchor": %EdgeLeft/Anchor,
	  "anchor_area": %EdgeLeft/Anchor/Area2D,
	  "anchor_shape": %EdgeLeft/Anchor/Area2D/CollisionShape2D },
	{ "area": %EdgeTopLeft, "poly": %EdgeTopLeft/Polygon2D, "anchor": %EdgeTopLeft/Anchor,
	  "anchor_area": %EdgeTopLeft/Anchor/Area2D,
	  "anchor_shape": %EdgeTopLeft/Anchor/Area2D/CollisionShape2D },
	{ "area": %EdgeTopRight, "poly": %EdgeTopRight/Polygon2D, "anchor": %EdgeTopRight/Anchor,
	  "anchor_area": %EdgeTopRight/Anchor/Area2D,
	  "anchor_shape": %EdgeTopRight/Anchor/Area2D/CollisionShape2D }
]

# Maps active physical edges back to their logical definitions: { physical_idx: {"logical": int, "is_out": bool} }
var _active_edge_map: Dictionary = {}

func _ready() -> void:
	_content_root = Node2D.new()
	add_child(_content_root)

	# Palette-driven theming. Both fields are @export, so any
	# subclass _init() that wrote them is silently undone by the
	# scene loader applying @export defaults after `_init`. Setting
	# them here (before `_setup_content` / `_build_slots`) ensures
	# the polygon + rim pick up HexPalette colors regardless of how
	# the hex was instantiated. Subclasses that need a custom body
	# (ident_ref_hex) override during `_setup_content` and win.
	body_color = HexPalette.body_color_for(get_script())
	disabled_edge_color = HexPalette.edge_color_for(get_script())
	# Slot pips ride the cool/warm neutral families so they don't
	# read as members of any colorful hue family (e.g. cool grey
	# input pip alongside a BLUE-family Naming body — distinct).
	input_color = HexPalette.color(
			HexPalette.Family.COLD_NEUTRAL,
			HexPalette.Shade.HIGHLIGHT)
	output_color = HexPalette.color(
			HexPalette.Family.WARM_NEUTRAL,
			HexPalette.Shade.HIGHLIGHT)

	# Wire up body inputs
	_body_area.input_pickable = _pickable
	_body_area.input_event.connect(_on_body_input)

	# Wire up edge inputs on the forgiving capsule (the anchor area).
	# Per-edge capsule rotation lives in the .tscn so Godot's
	# collision-debug overlay reflects the final orientation; the
	# trapezoid area stays in the physics space (so `intersect_point`
	# queries from `_hit_slot_at` can find it for the precise wire
	# drop), but never receives mouse events directly — that's the
	# capsule's job. Capsule size was tuned so an adjacent hex's
	# matching capsule overlaps the shared seam, leaving
	# `area_entered` / `area_exited` as a one-line adjacency signal
	# for future "touching" features.
	for i in range(6):
		var data: Dictionary = _edge_nodes[i]
		data.anchor_area.input_event.connect(_on_slot_input.bind(i))
		data.area.input_pickable = false

	_setup_content()
	_build_slots()
	# Subclass `_init()` runs before `_ready`, so any `body_color =
	# Color(...)` it set never reached the scene polygon (the
	# `@onready` ref was still null). Push the @export value onto
	# the polygon now that the scene is wired up.
	set_body_color(body_color)

func set_axial(coord: Vector2i) -> void:
	axial = coord
	position = HexMath.axial_to_world(coord, HEX_SIZE)

# Instead of math, we return the position of the Anchor marker!
func slot_world_position(logical_edge: int) -> Vector2:
	var phys = physical_edge(logical_edge)
	return position + _edge_nodes[phys].anchor.position

func physical_edge(logical: int) -> int:
	return (logical + rotation_index) % 6

# Fire the one-shot star burst sitting on the given logical edge's slot.
# Used when a wire snaps onto this hex so the connection point pops.
func burst_slot_particles(logical_edge: int) -> void:
	var phys := physical_edge(logical_edge)
	var anchor: Node = _edge_nodes[phys].anchor
	var emitter := anchor.get_node_or_null("GPUParticles2D") as GPUParticles2D
	if emitter:
		emitter.restart()  # one_shot=true → a single burst at the slot

func set_rotation_index(r: int) -> void:
	rotation_index = ((r % 6) + 6) % 6
	_build_slots() # Re-map and re-color edges

func set_pickable(p: bool) -> void:
	_pickable = p
	if _body_area:
		_body_area.input_pickable = p
	# Edge input lives on the anchor capsule now; the trapezoid area
	# is a physics-only target. Only enable pickable on ACTIVE edges.
	for phys_idx in _active_edge_map.keys():
		_edge_nodes[phys_idx].anchor_area.input_pickable = p

# ── Visual construction (Scene-based) ────────────────────────────────────────

func rebuild_slots() -> void:
	_build_slots()

func _build_slots() -> void:
	_active_edge_map.clear()

	# 1. Reset all edges to "disabled": rim painted with the family
	#    shadow, anchor capsule un-pickable (no drag-start affordance).
	for edge in _edge_nodes:
		edge.poly.color = disabled_edge_color
		edge.anchor_area.input_pickable = false

	# 2. Activate Input edges
	for logical_in in input_edges:
		var phys = physical_edge(logical_in)
		_edge_nodes[phys].poly.color = input_color
		_edge_nodes[phys].anchor_area.input_pickable = _pickable
		_active_edge_map[phys] = {"logical": logical_in, "is_out": false}

	# 3. Activate Output edges
	for logical_out in output_edges:
		var phys = physical_edge(logical_out)
		_edge_nodes[phys].poly.color = output_color
		_edge_nodes[phys].anchor_area.input_pickable = _pickable
		_active_edge_map[phys] = {"logical": logical_out, "is_out": true}

	_update_role_labels()
	# Re-light any fed input edges (rotation / arity rebuilds reset the
	# poly colours above).
	_apply_connection_colors()

# Spawn / reposition the on-canvas slot words declared in
# `input_role_labels`. Runs from `_build_slots` so labels exist by
# `_ready` and track every rotation for free. Derived visuals only —
# nothing here is serialized.
func _update_role_labels() -> void:
	if _content_root == null:
		return
	# Drop labels whose edge is no longer declared (e.g. lambda arity
	# shrank). `keys()` returns a copy, so erasing while iterating is safe.
	for logical in _role_labels.keys():
		if not input_role_labels.has(logical):
			var stale: Label = _role_labels[logical]
			if is_instance_valid(stale):
				stale.queue_free()
			_role_labels.erase(logical)
	for logical in input_role_labels:
		var lbl: Label = _role_labels.get(logical)
		if lbl == null:
			lbl = Label.new()
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content_root.add_child(lbl)
			_role_labels[logical] = lbl
		# Text + colour are refreshed every call so dynamic labels (the
		# lambda's per-param glyphs) track edits and identifier re-picks.
		lbl.text = String(input_role_labels[logical])
		lbl.add_theme_color_override("font_color",
				input_role_label_colors.get(logical, Color(0.85, 0.85, 0.95)))
		# Center the word on the edge midpoint — half the minimum size
		# rather than a fixed offset so "start" sits as true as "fn".
		var pos := HexMath.edge_offset(physical_edge(logical), HEX_SIZE) * 0.55
		lbl.position = pos - lbl.get_minimum_size() * 0.5

# ── Connected-edge highlight ─────────────────────────────────────────────────

# `fed` is the list of logical input edges currently receiving a source
# (the editor computes it via `wired_input_edges`). For an exclusive
# input group (Do / Anchor) one fed edge lights the whole slot.
func set_connected_input_edges(fed: Array) -> void:
	var new_set: Array = []
	if exclusive_input_group and not fed.is_empty():
		new_set = input_edges.duplicate()
	else:
		for e in fed:
			if e in input_edges:
				new_set.append(e)
	var newly: Array = []
	for e in new_set:
		if e not in _connected_edges:
			newly.append(e)
	for e in _connected_edges:
		if e not in new_set:
			_kill_edge_flash(physical_edge(e))
	_connected_edges = new_set
	_apply_connection_colors()
	for e in newly:
		_flash_edge(e)

func _apply_connection_colors() -> void:
	if _edge_nodes.is_empty():
		return
	for logical in input_edges:
		var phys := physical_edge(logical)
		var lit: bool = logical in _connected_edges
		_edge_nodes[phys].poly.color = input_color.lightened(0.5) if lit else input_color

func _flash_edge(logical: int) -> void:
	if _edge_nodes.is_empty() or not is_inside_tree():
		return
	var phys := physical_edge(logical)
	var poly: Polygon2D = _edge_nodes[phys].poly
	if poly == null:
		return
	_kill_edge_flash(phys)
	poly.color = input_color.lightened(0.85)
	var tw := create_tween()
	tw.tween_property(poly, "color", input_color.lightened(0.5), 0.3)
	_edge_flash_tweens[phys] = tw

func _kill_edge_flash(phys: int) -> void:
	var prev = _edge_flash_tweens.get(phys)
	if prev != null and prev.is_valid():
		prev.kill()
	_edge_flash_tweens.erase(phys)

# ── Setters for external color tweaks ───────────────────────────────────────
func set_body_color(c: Color) -> void:
	body_color = c
	if _body_poly:
		_body_poly.color = c

func set_badge(tex: Texture2D) -> void:
	badge_texture = tex
	if _badge_sprite:
		_badge_sprite.texture = tex

# ── Input handlers ──────────────────────────────────────────────────────────

func _on_body_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.shift_pressed:
		return # Let editor handle marquee

	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if mb.double_click:
			# Double-click picks the hex up for repositioning. The single
			# press that precedes it already fired node_grab_started (which
			# opens config); the editor's pickup handler supersedes it.
			node_pickup_requested.emit(self)
		else:
			node_grab_started.emit(self)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		delete_requested.emit(self)
		get_viewport().set_input_as_handled()

func _on_slot_input(_viewport: Node, event: InputEvent, _shape_idx: int, physical_edge_idx: int) -> void:
	if not _active_edge_map.has(physical_edge_idx):
		return # Ignore clicks on inactive edges
		
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.shift_pressed:
			return # Let editor handle marquee
			
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var mapping = _active_edge_map[physical_edge_idx]
			slot_grab_started.emit(self, mapping.logical, mapping.is_out)
			get_viewport().set_input_as_handled()

# Reverse lookup used by `_hit_slot_at`'s physics intersect_point
# query: an `Area2D` hit returned by the physics space → the edge
# index it belongs to (or -1 if the area isn't one of ours).
func edge_index_for_area(area: Area2D) -> int:
	for i in 6:
		if _edge_nodes[i].area == area:
			return i
	return -1


# ── Blueprint, Cloning, Validation & Source (Unchanged Logic) ───────────────

# Scene-aware instantiation. Every concrete subclass owns a `.tscn`
# at `<script>.tscn` that inherits `hex_node.tscn` and binds the
# subclass script. `script.new()` produces a script-less Node2D with
# no body / no edges; always go through this factory instead.
static func from_script(script: Script) -> HexNode:
	var scene_path := script.resource_path.replace(".gd", ".tscn")
	var packed := load(scene_path) as PackedScene
	return packed.instantiate() as HexNode


func clone() -> HexNode:
	var copy: HexNode = HexNode.from_script(get_script())
	copy.rotation_index = rotation_index
	_copy_state_to(copy)
	return copy

func _copy_state_to(_other: HexNode) -> void: pass
func serialize_state(_canvas) -> Dictionary: return {}
func restore_state(_state: Dictionary, _canvas) -> void: pass
func build_config_ui() -> Control: return null
func get_config_title() -> String: return "Hex"
# The hex an inner anchor delegates its config to. The base hex is its
# own delegate; anchors override to forward to their outer hex so
# clicking the anchor opens the same sidebar.
func config_delegate() -> HexNode: return self
# Arity-configurable hexes override these. `apply_arity` performs the
# whole structural change in place (resize state, grow/shrink the live
# anchor and/or outer face, rebuild visuals) WITHOUT touching wires or
# undo — the editor handles those around the call. `arity_slot_node`
# names the node whose input slots grow/shrink with arity, so the editor
# can drop only the wire on a removed slot; null means none.
func apply_arity(_n: int) -> void: pass
func arity_slot_node() -> HexNode:
	return inner_level.anchor if inner_level != null else null
func has_inner_level() -> bool: return false
# Gates Q-descend when wiring state matters (e.g. a ListAnchor only
# grows a continuation once all its slots are wired). `canvas` is the
# editor (get_input_for lives there).
func can_descend(_canvas) -> bool: return true
func level_label() -> String: return get_config_title()
func create_inner_anchor() -> HexNode:
	return HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/anchor_hex.gd"))
func to_source(_canvas) -> String: return "_HOLE_"
func _setup_content() -> void: pass
func _on_scroll(_dir: int) -> void: pass

func _input_source(canvas, edge: int, placeholder: String = "_HOLE_") -> String:
	if _visiting:
		return "_CYCLE_"
	var from_node = canvas.get_input_for(self, edge)
	if from_node == null:
		return placeholder
	_visiting = true
	var s := (from_node as HexNode).to_source(canvas)
	_visiting = false
	return s

# Logical input edges that actually carry a source right now, in
# canonical order. Used by single-slot fixtures (Do, anchor) to
# detect "nothing wired" and "fed from more than one side".
func wired_input_edges(canvas) -> Array:
	var fed: Array = []
	for e in input_edges:
		if canvas.get_input_for(self, e) != null:
			fed.append(e)
	return fed

func validate(canvas) -> Dictionary:
	for e in input_edges:
		if e in optional_input_edges:
			continue
		if canvas.get_input_for(self, e) == null:
			return {
				"status": "error",
				"message": "%s input on %s is unwired" % [
					String(input_role_names.get(e, "input %d" % e)),
					HexMath.edge_name(physical_edge(e)),
				],
			}
	return {"status": "ok", "message": ""}

func build_slot_section() -> Control:
	if input_role_names.is_empty() and output_role_names.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.text = "Slots"
	header.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	header.add_theme_font_size_override("font_size", 12)
	box.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	for logical in input_edges:
		if not input_role_names.has(logical):
			continue
		_append_slot_row(grid, logical, "in",  input_role_names[logical])
	for logical in output_edges:
		if not output_role_names.has(logical):
			continue
		_append_slot_row(grid, logical, "out", output_role_names[logical])
	box.add_child(grid)
	return box

func _append_slot_row(grid: GridContainer, logical: int, dir: String, role: String) -> void:
	var pos_lbl := Label.new()
	pos_lbl.text = HexMath.edge_name(physical_edge(logical))
	pos_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.55))
	pos_lbl.add_theme_font_size_override("font_size", 12)
	pos_lbl.custom_minimum_size = Vector2(32, 0)
	grid.add_child(pos_lbl)
	var dir_lbl := Label.new()
	dir_lbl.text = dir
	dir_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	dir_lbl.add_theme_font_size_override("font_size", 11)
	dir_lbl.custom_minimum_size = Vector2(28, 0)
	grid.add_child(dir_lbl)
	var role_lbl := Label.new()
	role_lbl.text = role
	role_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	role_lbl.add_theme_font_size_override("font_size", 12)
	grid.add_child(role_lbl)
	
# Placement feedback: a quick "pop" — the hex overshoots to 1.18x then
# springs back to its resting scale. HexNode's polygons are all centred on
# the origin, so the scale reads as centred.
func pop_in() -> void:
	scale = Vector2(1.18, 1.18)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


# Connection feedback: briefly light up `logical_edge`, then settle back to
# its resting colour. Works for input and output slots (the input-fed
# highlight resting colour is honoured), reusing the edge-flash tween slot
# so it co-operates with `set_connected_input_edges`.
func flash_edge(logical_edge: int) -> void:
	if _edge_nodes.is_empty() or not is_inside_tree():
		return
	var phys := physical_edge(logical_edge)
	var poly: Polygon2D = _edge_nodes[phys].poly
	if poly == null:
		return
	var is_output: bool = logical_edge in output_edges
	var base: Color = output_color if is_output else input_color
	var resting := base
	if not is_output and logical_edge in _connected_edges:
		resting = input_color.lightened(0.5)
	_kill_edge_flash(phys)
	poly.color = base.lightened(0.85)
	var tw := create_tween()
	tw.tween_property(poly, "color", resting, 0.3)
	_edge_flash_tweens[phys] = tw


# Wire-routing feedback: brighten the whole body while a wire being dragged
# is hovering this hex as a valid connection target. `off` restores the
# resting body colour.
func set_wire_target_highlight(on: bool) -> void:
	if _body_poly == null:
		return
	_body_poly.color = body_color.lightened(0.35) if on else body_color
