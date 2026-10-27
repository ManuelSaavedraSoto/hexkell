class_name TutorialHud
extends CanvasLayer
## Tutorial instruction strip + control highlighter. Built entirely in
## code (no .tscn) and instantiated by TutorialManager when a tutorial
## session attaches to the hex editor. Deliberately NOT registered with
## the editor's modal gate — instructions must never block input.

var highlight_rect: TutorialHighlightRect

var _panel: PanelContainer
var _text_label: RichTextLabel
var _counter_label: Label


func _ready() -> void:
	layer = 99

	highlight_rect = TutorialHighlightRect.new()
	add_child(highlight_rect)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_top = 104.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_counter_label = Label.new()
	_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_counter_label)

	_text_label = RichTextLabel.new()
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(560, 0)
	box.add_child(_text_label)


func show_step(text: String, step_number: int, total: int) -> void:
	if _panel == null:
		return
	_counter_label.text = "Tutorial — step %d / %d" % [step_number, total]
	_text_label.text = "[center]%s[/center]" % text
	_panel.visible = true
	# Re-center: anchors pin the panel's left edge to the middle, so
	# shift by half the (freshly laid-out) width.
	_panel.reset_size()
	_panel.offset_left = -_panel.size.x / 2.0


func hide_panel() -> void:
	if _panel:
		_panel.visible = false
	if highlight_rect:
		highlight_rect.clear()
