extends HexNode
## Anchor for a List inner level. Six optional element slots branded
## `1st`…`6th` (sliding window: only wired slots count, in canonical
## order). A list has no reserved "output" edge, so every face is an
## element slot — they start on the NE edge and spin clockwise, which
## also makes the literal's element order read clockwise around the
## hex. The anchor itself can "go deeper": once every slot is wired,
## Q over it descends to a continuation ListAnchor for more elements —
## lists grow indefinitely, one full cell block at a time, in contrast
## to the tuple's fixed shape. The parent ListLiteralHex's `to_source`
## flattens the whole continuation chain into one `[a, b, …]` literal.

const SLOT_EDGES: Array = [5, 0, 1, 2, 3, 4] # NE, E, SE, SW, W, NW (CW)
const ORDINALS := ["1st", "2nd", "3rd", "4th", "5th", "6th"]

# Mirrors AnchorHex's shape so IdentifierScope can walk any anchor
# uniformly. Lists introduce no bindings, so both stay empty.
var emit_logical_edges: Array = []
var emit_labels: Array = []


func _init() -> void:
	is_fixture = true
	input_edges.assign(SLOT_EDGES)
	optional_input_edges.assign(SLOT_EDGES)
	for i in SLOT_EDGES.size():
		input_role_names[SLOT_EDGES[i]] = ORDINALS[i]
		input_role_labels[SLOT_EDGES[i]] = ORDINALS[i]


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "list"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(60, 18)
	lbl.position = Vector2(-30, -8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "List Anchor"


func has_inner_level() -> bool:
	return true


# Only grow a continuation once this block is full — but never lock
# the player out of a continuation that already exists (unwiring a
# slot above must not strand the elements below).
func can_descend(canvas) -> bool:
	if inner_level != null:
		return true
	for e in input_edges:
		if canvas.get_input_for(self, e) == null:
			return false
	return true


func level_label() -> String:
	return "list…"


func create_inner_anchor() -> HexNode:
	return HexNode.from_script(get_script())


# ListLiteralHex.to_source reads the element slots directly off the
# anchor chain; an anchor has no single-value source of its own.
func to_source(_canvas) -> String:
	return "_HOLE_"
