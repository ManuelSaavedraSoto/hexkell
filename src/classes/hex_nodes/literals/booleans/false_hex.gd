extends HexNode
## Boolean literal `false`. Output only.

func _init() -> void:
	output_edges = [0]
	output_role_names = {0: "value"}


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "false"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(80, 40)
	lbl.position = Vector2(-40, -22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "false"


func to_source(_canvas) -> String:
	return "false"
