class_name BinaryOpHex
extends HexNode
## Base class for binary infix operators. Inputs on NW (left operand)
## and SW (right operand); output on E. Subclasses set `op_text` and
## the fill / border colors in their `_init`; everything else — slot
## layout, label rendering, generated text — is inherited.

var op_text: String = "?"

var _label: Label


func _init() -> void:
	input_edges = [4, 2]   # NW = left, SW = right
	output_edges = [0]     # E  = result
	input_role_names = {4: "left", 2: "right"}
	output_role_names = {0: "result"}


func _setup_content() -> void:
	_label = Label.new()
	_label.text = op_text
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.size = Vector2(80, 40)
	_label.position = Vector2(-40, -22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_label)


func get_config_title() -> String:
	return "Operator  %s" % op_text


func to_source(canvas) -> String:
	var l := _input_source(canvas, 4)
	var r := _input_source(canvas, 2)
	return "(%s %s %s)" % [l, op_text, r]
