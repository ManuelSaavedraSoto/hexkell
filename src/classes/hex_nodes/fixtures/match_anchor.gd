extends HexNode
## Anchor for a Match inner level. Each branch occupies one logical
## edge of the anchor and contributes two things on that side:
##
##   • a pattern inscription (label inside the hex)
##   • a wire input slot at the edge (the branch's body wire terminates
##     here)
##
## The parent MatchHex's `to_source` walks the anchor's branch_edges in
## order and emits `| pat = body` for each, producing the canonical
## `match S with | p1 = b1 | p2 = b2 | …` form.

# Pattern strings inscribed on each branch, indexed by branch.
var patterns: Array = []
# Logical edges (0..5, rotation-invariant) one per branch.
var branch_edges: Array = []
# Emission edges + labels, mirroring AnchorHex's shape so the scope
# walker (IdentifierScope) can pull pattern-bound identifiers into
# scope for any hex in the branch's body. Each branch's edge acts
# as both an input (where the body's result wires back) and an
# output that carries the pattern's bound variables.
var emit_logical_edges: Array = []
var emit_labels: Array = []

var _title_node: Label
var _pattern_label_nodes: Array = []


func _init() -> void:
	is_fixture = true


# Call before `add_child` so `_ready` sees the right `input_edges` and
# builds the matching wire slots.
func configure(patterns_in: Array, edges_in: Array) -> void:
	patterns = patterns_in.duplicate()
	branch_edges = edges_in.duplicate()
	input_edges.assign(edges_in)
	# Each branch's edge ALSO acts as an emission slot — the pattern's
	# bound identifiers come into scope for any hex in the branch's
	# body. `IdentifierScope` walks `patterns` directly (delegating to
	# `PatternVariables.extract`) so the picker on a nested IdentRef
	# greys out names that aren't introduced by any branch's pattern.
	# `emit_logical_edges` is set so renderers / wiring helpers that
	# check "is this slot an output?" treat the branch edges as both.
	emit_logical_edges = edges_in.duplicate()
	emit_labels = patterns_in.duplicate()


# Live arity change: re-apply `configure` on a node that's already in the
# tree, then repaint the wire slots + pattern inscriptions. Surviving
# branches keep their edge (prefix-stable order), so only an added slot
# appears empty and only a removed slot's wire is orphaned (the editor
# drops it).
func reconfigure(patterns_in: Array, edges_in: Array) -> void:
	configure(patterns_in, edges_in)
	rebuild_slots()
	_rebuild_pattern_labels()


func _setup_content() -> void:
	_title_node = Label.new()
	_title_node.text = "match"
	_title_node.add_theme_font_size_override("font_size", 13)
	_title_node.add_theme_color_override("font_color", Color.WHITE)
	_title_node.size = Vector2(60, 18)
	_title_node.position = Vector2(-30, -8)
	_title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_title_node)
	_rebuild_pattern_labels()


func _rebuild_pattern_labels() -> void:
	for lbl in _pattern_label_nodes:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_pattern_label_nodes.clear()
	for i in patterns.size():
		var edge: int = int(branch_edges[i])
		var pat: String = String(patterns[i])
		var lbl := Label.new()
		lbl.text = pat
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0))
		lbl.size = Vector2(54, 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Place the inscription inside the hex, between the centre and
		# the slot dot — about 45% out so it doesn't crowd the slot.
		var pos := HexMath.edge_offset(physical_edge(edge), HEX_SIZE) * 0.45
		lbl.position = pos - Vector2(27, 8)
		_content_root.add_child(lbl)
		_pattern_label_nodes.append(lbl)


func set_pattern_at(index: int, text: String) -> void:
	if index < 0 or index >= patterns.size():
		return
	patterns[index] = text
	# Keep `emit_labels` in lockstep with `patterns` so scope queries
	# (IdentifierScope) see the freshly typed pattern's variables
	# without needing a level re-enter.
	if index < emit_labels.size():
		emit_labels[index] = text
	if index < _pattern_label_nodes.size() and is_instance_valid(_pattern_label_nodes[index]):
		_pattern_label_nodes[index].text = text


func set_rotation_index(r: int) -> void:
	super.set_rotation_index(r)
	for i in _pattern_label_nodes.size():
		var lbl = _pattern_label_nodes[i]
		if not is_instance_valid(lbl):
			continue
		var edge: int = int(branch_edges[i])
		var pos := HexMath.edge_offset(physical_edge(edge), HEX_SIZE) * 0.45
		lbl.position = pos - Vector2(27, 8)


func get_config_title() -> String:
	return "Match Anchor"


# Clicking the anchor opens the owning MatchHex's config (branch count +
# per-branch patterns), so the player can reconfigure from inside a body.
func config_delegate() -> HexNode:
	if level != null and level.parent_hex != null:
		return level.parent_hex
	return self


# MatchHex.to_source walks branch_edges and calls _input_source per branch;
# the anchor doesn't have a meaningful single-value to_source on its own.
func to_source(_canvas) -> String:
	return "_HOLE_"
