extends HexNode
## Anchor for an If inner level. Fixed two-slot shape: the then body
## wires into NW (logical 4) and the else body into SW (logical 2),
## branded by the base class's `input_role_labels` mechanism. The
## parent IfHex's `to_source` reads both slots off this anchor.

# Mirrors AnchorHex's shape so IdentifierScope can walk any anchor
# uniformly. If introduces no bindings, so both stay empty.
var emit_logical_edges: Array = []
var emit_labels: Array = []


func _init() -> void:
	is_fixture = true
	input_edges = [4, 2]
	input_role_names = {4: "then branch", 2: "else branch"}
	input_role_labels = {4: "then", 2: "else"}


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "if"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(60, 18)
	lbl.position = Vector2(-30, -8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "If Anchor"


# IfHex.to_source reads the then/else slots directly off this anchor;
# the anchor has no meaningful single-value source of its own.
func to_source(_canvas) -> String:
	return "_HOLE_"
