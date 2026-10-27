extends HexNode
## Anchor of a non-level-0 level. Sits at (0,0) of its level as a fixture
## (cannot be deleted or picked up). Some sides can be configured to emit
## an identifier into local scope as a label; any free side is the body's
## return slot. The slot takes a single wire total — approachable from any
## of the six sides, but wiring a new side replaces the prior wire.
##
## `emit_logical_edges[i]` is the logical edge (0..5, rotation-invariant)
## of the i-th emission, and `emit_labels[i]` is the identifier name to
## display there. An emission edge can double as the wired return side.

# Logical edge the lone emission rides by default (West).
var emit_logical_edges: Array = [3]
# Identifier names broadcast on each corresponding emit side.
var emit_labels: Array = ["?"]

var _title_node: Label
var _emit_label_nodes: Array = []


func _init() -> void:
	# All six sides are the same logical return slot — wire the body's
	# result in from whichever side is geometrically convenient. One
	# wire total (see `exclusive_input_group`).
	input_edges = [0, 1, 2, 3, 4, 5]
	optional_input_edges = [0, 1, 2, 3, 4, 5]
	exclusive_input_group = true
	is_fixture = true


func _setup_content() -> void:
	_title_node = Label.new()
	_title_node.text = "ψ"
	_title_node.add_theme_font_size_override("font_size", 22)
	_title_node.add_theme_color_override("font_color", Color.WHITE)
	_title_node.size = Vector2(40, 26)
	_title_node.position = Vector2(-20, -14)
	_title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_title_node)
	_rebuild_emit_labels()


func _rebuild_emit_labels() -> void:
	for lbl in _emit_label_nodes:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_emit_label_nodes.clear()
	for i in emit_logical_edges.size():
		var edge: int = int(emit_logical_edges[i])
		var name: String = String(emit_labels[i]) if i < emit_labels.size() else "?"
		var lbl := Label.new()
		lbl.text = name
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0))
		lbl.size = Vector2(50, 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pos := HexMath.edge_offset(physical_edge(edge), HEX_SIZE) * 0.55
		lbl.position = pos - Vector2(25, 8)
		_content_root.add_child(lbl)
		_emit_label_nodes.append(lbl)


# Replace the emission set wholesale. Triggers a rebuild of the labels.
func set_emissions(edges: Array, labels: Array) -> void:
	emit_logical_edges = edges.duplicate()
	emit_labels = labels.duplicate()
	if _content_root:
		_rebuild_emit_labels()


# Convenience for single-emit anchors (Let, single-arity Lambda).
func set_emission(name: String) -> void:
	if emit_labels.is_empty():
		emit_labels = [name]
	else:
		emit_labels[0] = name
	if _emit_label_nodes.size() > 0 and is_instance_valid(_emit_label_nodes[0]):
		_emit_label_nodes[0].text = name


func set_emission_at(index: int, name: String) -> void:
	while emit_labels.size() <= index:
		emit_labels.append("?")
	emit_labels[index] = name
	if index < _emit_label_nodes.size() and is_instance_valid(_emit_label_nodes[index]):
		_emit_label_nodes[index].text = name


func set_rotation_index(r: int) -> void:
	super.set_rotation_index(r)
	for i in _emit_label_nodes.size():
		var lbl = _emit_label_nodes[i]
		if not is_instance_valid(lbl):
			continue
		var edge: int = int(emit_logical_edges[i])
		var pos := HexMath.edge_offset(physical_edge(edge), HEX_SIZE) * 0.55
		lbl.position = pos - Vector2(25, 8)


func get_config_title() -> String:
	return "Anchor"


# Clicking the anchor opens the owning hex's full config (Let / LetRec /
# Lambda / Definition) so the player can reconfigure from inside the body.
func config_delegate() -> HexNode:
	if level != null and level.parent_hex != null:
		return level.parent_hex
	return self


# Text emission: whichever side carries the body's result is the
# level's value (first wired in canonical order). Parent hexes recurse
# through here when they need the inner level's value.
func to_source(canvas) -> String:
	for edge in input_edges:
		if canvas.get_input_for(self, edge) != null:
			return _input_source(canvas, edge)
	return "_HOLE_"


# The body's result must feed exactly one side. Making every edge an
# optional input drops the base class's unwired check, so re-state it
# here (plus a multi-feed guard for adjacency double-feeds).
func validate(canvas) -> Dictionary:
	var fed := wired_input_edges(canvas)
	if fed.is_empty():
		return {
			"status": "error",
			"message": "the level's return slot is unwired — wire the body's result into the anchor",
		}
	if fed.size() > 1:
		return {
			"status": "error",
			"message": "the anchor's return slot is fed from %s and %s — it takes one result" % [
				HexMath.edge_name(physical_edge(int(fed[0]))),
				HexMath.edge_name(physical_edge(int(fed[1]))),
			],
		}
	return {"status": "ok", "message": ""}
