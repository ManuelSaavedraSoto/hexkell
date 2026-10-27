extends HexNode
## If expression. Outer face:
##   NW (logical 4) → condition
##   E  (logical 0) → result
##
## Inner level: an IfAnchor at (0,0) with two branded slots — then on
## NW, else on SW — matching the let / lambda / match convention that
## bodies live one level down.


func _init() -> void:
	input_edges = [4]
	output_edges = [0]
	input_role_names = {4: "condition"}
	output_role_names = {0: "result"}


func _setup_content() -> void:
	var lbl := Label.new()
	lbl.text = "if"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.size = Vector2(60, 30)
	lbl.position = Vector2(-30, -16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(lbl)


func get_config_title() -> String:
	return "If"


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "if"


func create_inner_anchor() -> HexNode:
	return HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/if_anchor.gd"))


func to_source(canvas) -> String:
	var c := _input_source(canvas, 4)
	var t := "_HOLE_"
	var e := "_HOLE_"
	if inner_level != null and inner_level.anchor != null:
		var anchor = inner_level.anchor
		var then_node = canvas.get_input_for(anchor, 4)
		if then_node != null:
			t = then_node.to_source(canvas)
		var else_node = canvas.get_input_for(anchor, 2)
		if else_node != null:
			e = else_node.to_source(canvas)
	return "(if %s then %s else %s)" % [c, t, e]
