extends HexNode
## Integer literal. Output only. Click body to edit `value` in the
## right-hand config sidebar.

var value: int = 0
var _label: Label


func _init() -> void:
	output_edges = [0]
	output_role_names = {0: "value"}


func _setup_content() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.size = Vector2(80, 40)
	_label.position = Vector2(-40, -22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_label)
	_refresh()


func _on_scroll(dir: int) -> void:
	value += dir
	_refresh()
	config_value_changed.emit(self)


func _refresh() -> void:
	if _label:
		_label.text = str(value)


func _copy_state_to(other: HexNode) -> void:
	other.value = value


func serialize_state(_canvas) -> Dictionary:
	return {"value": value}


func restore_state(state: Dictionary, _canvas) -> void:
	value = int(state.get("value", 0))


func get_config_title() -> String:
	return "Integer Literal"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Value"
	box.add_child(lbl)
	var spin := SpinBox.new()
	spin.update_on_text_changed = true
	spin.min_value = -1_000_000
	spin.max_value = 1_000_000
	spin.step = 1
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void:
		value = int(v)
		_refresh()
		config_value_changed.emit(self)
	)
	box.add_child(spin)
	return box


func to_source(_canvas) -> String:
	return str(value)
