extends HexNode
## List literal `[a, b, …]`. Output-only on the outer face (E); the
## elements live in an inner level (Q to descend) wired into a
## ListAnchor with six optional slots (NE clockwise). A full anchor
## can itself be descended into for a continuation block, indefinitely
## — `to_source` flattens the whole chain into one flat literal. No
## inner level (or nothing wired) emits the empty list `[]`.

var _label: Label


func _init() -> void:
	output_edges = [0]
	output_role_names = {0: "list"}


func _setup_content() -> void:
	_label = Label.new()
	_label.text = "[ , , ]"
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.size = Vector2(90, 28)
	_label.position = Vector2(-45, -14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_label)


func get_config_title() -> String:
	return "List"


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "list"


func create_inner_anchor() -> HexNode:
	return HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/list_anchor.gd"))


func to_source(canvas) -> String:
	var parts: Array[String] = []
	# Flatten the continuation chain: each anchor contributes its wired
	# slots in canonical order (sliding window), then hands over to the
	# next block.
	var anchor = inner_level.anchor if inner_level != null else null
	while anchor != null:
		for edge in anchor.input_edges:
			var src = canvas.get_input_for(anchor, edge)
			if src != null:
				parts.append(src.to_source(canvas))
		anchor = anchor.inner_level.anchor if anchor.inner_level != null else null
	return "[%s]" % ", ".join(parts)
