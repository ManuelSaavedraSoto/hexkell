extends HexNode
## Tuple literal `(a, b, …)`. Output-only on the outer face (E); the
## elements live in an inner level (Q to descend) wired into a
## TupleAnchor with one ordinal-branded slot per element. Arity 2–5,
## configured via the sidebar; changing it grows/shrinks the anchor in
## place (clockwise-from-NE edge order) so existing element wires survive
## — only a removed slot's wire is dropped.

var arity: int = 2

var _label: Label


func _init() -> void:
	output_edges = [0]
	output_role_names = {0: "tuple"}


func _setup_content() -> void:
	_label = Label.new()
	_label.text = "( , )"
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.size = Vector2(80, 28)
	_label.position = Vector2(-40, -14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_label)


func _copy_state_to(other: HexNode) -> void:
	other.arity = arity


func serialize_state(_canvas) -> Dictionary:
	return {"arity": arity}


func restore_state(state: Dictionary, _canvas) -> void:
	arity = clamp(int(state.get("arity", 2)), 2, HexMath.MAX_ARITY)


func get_config_title() -> String:
	return "Tuple"


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "tuple"


func create_inner_anchor() -> HexNode:
	var anchor = HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/tuple_anchor.gd"))
	anchor.configure(HexMath.edges_for_arity(arity))
	return anchor


# Grow / shrink the element set in place. When the inner level already
# exists, the live anchor is reconfigured on the prefix-stable edge order
# so surviving elements keep their slot + wire.
func apply_arity(n: int) -> void:
	arity = n
	if inner_level != null and inner_level.anchor != null:
		inner_level.anchor.reconfigure(HexMath.edges_for_arity(arity))


func build_config_ui() -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Arity"
	box.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 2
	spin.max_value = 5
	spin.step = 1
	spin.value = arity
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void:
		arity_change_requested.emit(self, int(v))
	)
	box.add_child(spin)
	var hint := Label.new()
	hint.text = "Removing an element deletes only that slot's wire."
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func validate(canvas) -> Dictionary:
	if inner_level == null:
		return {
			"status": "error",
			"message": "tuple has no elements — press Q over it to wire them",
		}
	return super.validate(canvas)


func to_source(canvas) -> String:
	var parts: Array[String] = []
	if inner_level != null and inner_level.anchor != null:
		var anchor = inner_level.anchor
		for edge in anchor.input_edges:
			var src = canvas.get_input_for(anchor, edge)
			var part: String = "_HOLE_"
			if src != null:
				part = src.to_source(canvas)
			parts.append(part)
	else:
		for i in arity:
			parts.append("_HOLE_")
	return "(%s)" % ", ".join(parts)
