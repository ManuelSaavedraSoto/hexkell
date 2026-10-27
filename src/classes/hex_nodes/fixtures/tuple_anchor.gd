extends HexNode
## Anchor for a Tuple inner level. One required slot per element,
## branded `1st`…`5th` by the base class's `input_role_labels`
## mechanism. The parent TupleHex configures the slot edges for its
## arity before adding the anchor; changing arity purges the level and
## rebuilds the anchor. TupleHex's `to_source` reads the element slots
## off this anchor in canonical order.

const ORDINALS := ["1st", "2nd", "3rd", "4th", "5th"]

# Mirrors AnchorHex's shape so IdentifierScope can walk any anchor
# uniformly. Tuples introduce no bindings, so both stay empty.
var emit_logical_edges: Array = []
var emit_labels: Array = []


func _init() -> void:
	is_fixture = true


# Call before `add_child` so `_ready` sees the right `input_edges` and
# builds the matching wire slots.
func configure(edges_in: Array) -> void:
	input_edges.assign(edges_in)
	input_role_names.clear()
	input_role_labels.clear()
	for i in edges_in.size():
		input_role_names[edges_in[i]] = ORDINALS[i]
		input_role_labels[edges_in[i]] = ORDINALS[i]


# Live arity change: re-apply `configure` on a node that's already in the
# tree, then repaint the wire slots + ordinal labels. Surviving elements
# keep their edge (prefix-stable order).
func reconfigure(edges_in: Array) -> void:
	configure(edges_in)
	rebuild_slots()


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "tuple"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(60, 18)
	lbl.position = Vector2(-30, -8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "Tuple Anchor"


# Clicking the anchor opens the owning TupleHex's config (arity), so the
# player can change the element count from inside the level.
func config_delegate() -> HexNode:
	if level != null and level.parent_hex != null:
		return level.parent_hex
	return self


# TupleHex.to_source reads the element slots directly off this anchor;
# the anchor has no meaningful single-value source of its own.
func to_source(_canvas) -> String:
	return "_HOLE_"
