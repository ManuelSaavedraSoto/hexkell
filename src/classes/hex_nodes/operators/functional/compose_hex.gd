extends HexNode
## Function composition `(f . g)`. Inputs: NW = outer function f,
## SW = inner function g. Output: E carries the composed function as a
## value, so arbitrary expressions (lambdas, partial applications,
## other compositions) can be composed by wiring.


func _init() -> void:
	input_edges = [4, 2]
	output_edges = [0]
	input_role_names = {4: "outer function", 2: "inner function"}
	input_role_labels = {4: "f", 2: "g"}
	output_role_names = {0: "composed function"}


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "∘"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(60, 28)
	lbl.position = Vector2(-30, -14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "Compose"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Composes f after g:\n((f . g) x) = (f (g x))"
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func to_source(canvas) -> String:
	var f := _input_source(canvas, 4)
	var g := _input_source(canvas, 2)
	return "(%s . %s)" % [f, g]
