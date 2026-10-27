extends HexNode
## Base class for prefix unary operators. Single input on NW; output
## on E. Subclasses set `op_text` and colors in `_init`.

var op_text: String = "?"

var _label: Label


func _init() -> void:
	input_edges = [4]
	output_edges = [0]
	input_role_names = {4: "operand"}
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
	var a := _input_source(canvas, 4)
	return "(%s %s)" % [op_text, a]
