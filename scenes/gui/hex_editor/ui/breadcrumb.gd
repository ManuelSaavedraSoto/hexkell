extends HBoxContainer
## Breadcrumb — clickable path through the level stack. Editor calls
## `set_labels(["main", "let red", …])` whenever the stack changes;
## clicking a segment emits `jump_requested(idx)`.

signal jump_requested(target_idx: int)


func set_labels(labels: Array) -> void:
	for c in get_children():
		if c is TextureRect:
			continue
		c.queue_free()
	for i in labels.size():
		var btn := Button.new()
		btn.text = String(labels[i])
		btn.flat = true
		btn.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		btn.add_theme_font_size_override("font_size", 18)
		var target_idx := i
		btn.pressed.connect(func() -> void: jump_requested.emit(target_idx))
		add_child(btn)
		if i < labels.size() - 1:
			var sep := Label.new()
			sep.text = "▸"
			sep.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8))
			sep.add_theme_font_size_override("font_size", 14)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sep)
