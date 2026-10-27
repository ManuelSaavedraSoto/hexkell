extends HexNode
## Function application `(f x)`. Inputs: NW = fn, SW = arg. Output: E.
## Multi-arg applications are built by chaining (language is left-associative).

func _init() -> void:
	input_edges = [4, 2]
	output_edges = [0]
	input_role_names = {4: "function", 2: "argument"}
	input_role_labels = {4: "fn", 2: "arg"}
	output_role_names = {0: "result"}


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "apply"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(80, 20)
	lbl.position = Vector2(-40, -10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "Apply"


func to_source(canvas) -> String:
	var f := _input_source(canvas, 4)
	var a := _input_source(canvas, 2)
	return "(%s %s)" % [f, a]
