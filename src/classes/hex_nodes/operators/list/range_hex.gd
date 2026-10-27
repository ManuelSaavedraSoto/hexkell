extends HexNode
## Range `[start..end]` or `[start..]`. NW = start (wired), SW = end
## (optional). Output on E. An unwired end produces the infinite range
## form `[start..]`, matching the language's lazy-list semantics.

func _init() -> void:
	input_edges = [4, 2]   # NW = start, SW = end (optional)
	output_edges = [0]
	input_role_names = {4: "start", 2: "end (optional)"}
	input_role_labels = {4: "start", 2: "end"}
	output_role_names = {0: "range"}
	optional_input_edges = [2]


func _setup_content() -> void:
	var keyword := Label.new()
	keyword.text = "[ .. ]"
	keyword.add_theme_font_size_override("font_size", 20)
	keyword.add_theme_color_override("font_color", Color.WHITE)
	keyword.size = Vector2(80, 28)
	keyword.position = Vector2(-40, -14)
	keyword.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keyword.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keyword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(keyword)


func get_config_title() -> String:
	return "Range"


func to_source(canvas) -> String:
	var start := _input_source(canvas, 4)
	var end_node = canvas.get_input_for(self, 2)
	if end_node == null:
		return "[%s..]" % start
	return "[%s..%s]" % [start, end_node.to_source(canvas)]
