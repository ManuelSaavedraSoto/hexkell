extends PanelContainer
## Per-hex config sidebar — shows the slot diagram + the hex's
## subclass-provided `build_config_ui()` widget. Open / close is
## driven by the editor (clicking a hex opens it; right-click /
## empty-cell click / level switch closes it).
##
## The editor still owns the "current target hex" state via
## `_config_target` — this script is just the view.

## Emitted when the player confirms (Enter / Space, or submitting a
## field). The editor closes the sidebar in response.
signal confirm_requested
signal clear_selection

## Mouse-only level navigation: the editor answers these by ascending to
## the parent level / descending into the configured hex's inner level
## (the keyboard equivalents are E / Q). The buttons are enabled per
## `set_nav_state`, called by the editor right after `open_for`.
signal ascend_requested
signal descend_requested

@onready var box: VBoxContainer = $ConfigMargin/ConfigBox
@onready var output: FoldableContainer = %OutputPanel

var _ascend_btn: Button
var _descend_btn: Button


func open_for(node: Node) -> void:
	clear()
	output.fold()
	# Inner anchors delegate their config to the outer hex that owns the
	# level, so clicking the anchor opens the same full sidebar (arity,
	# name, patterns) without ascending a level. Plain hexes are their
	# own delegate.
	var target: Node = node
	if node.has_method("config_delegate"):
		target = node.config_delegate()
	var title := Label.new()
	title.text = target.get_config_title()
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	box.add_child(HSeparator.new())
	box.add_child(_build_nav_row())
	box.add_child(HSeparator.new())
	# Slot positions (rotation-aware). The section refreshes every
	# time this runs, and the editor's _apply_rotate_hex reopens us
	# whenever the configured hex rotates so the labels stay in sync.
	var slots = target.build_slot_section()
	if slots != null:
		box.add_child(slots)
		box.add_child(HSeparator.new())
	var ui = target.build_config_ui()
	if ui != null:
		box.add_child(ui)
	elif slots == null:
		var msg := Label.new()
		msg.text = "(nothing to configure)"
		msg.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		msg.add_theme_font_size_override("font_size", 12)
		box.add_child(msg)
	# Enter in a focused number/text field confirms + closes (Space and
	# Enter elsewhere is handled in `_unhandled_key_input`).
	_connect_submit_handlers(box)
	show()
	# Defer focus until the panel has finished laying out — otherwise
	# `grab_focus` may run before the editor is ready to accept it.
	call_deferred("_focus_first_input")


# Level-navigation row: ascend to the parent level / descend into this
# hex's inner level without touching the keyboard. Rebuilt each open;
# the editor enables/disables the buttons via `set_nav_state`.
func _build_nav_row() -> HBoxContainer:
	var nav := HBoxContainer.new()
	_ascend_btn = Button.new()
	_ascend_btn.text = "▲ Ascend"
	_ascend_btn.tooltip_text = "Go up to the parent level (E)"
	_ascend_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ascend_btn.pressed.connect(func() -> void: ascend_requested.emit())
	nav.add_child(_ascend_btn)
	_descend_btn = Button.new()
	_descend_btn.text = "▼ Descend"
	_descend_btn.tooltip_text = "Enter this hex's inner level (Q)"
	_descend_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_descend_btn.pressed.connect(func() -> void: descend_requested.emit())
	nav.add_child(_descend_btn)
	return nav


# Enable/disable the ascend / descend buttons. Called by the editor right
# after `open_for`, once it knows the level depth and whether the
# configured hex can be descended into.
func set_nav_state(can_ascend: bool, can_descend: bool) -> void:
	if is_instance_valid(_ascend_btn):
		_ascend_btn.disabled = not can_ascend
	if is_instance_valid(_descend_btn):
		_descend_btn.disabled = not can_descend


# Close on Enter when the keystroke wasn't consumed by a focused field
# (a focused LineEdit/SpinBox eats Enter — `_connect_submit_handlers`
# covers that path). Space is deliberately NOT a close key.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# A focused SpinBox/LineEdit eats Enter itself: it commits the
		# typed value (→ value_changed → config_value_changed) and then
		# `_on_field_submitted` closes us. Pre-empting it here loses the
		# value and closes the panel early.
		if InputGates.text_input_focused(get_viewport()):
			return
		confirm_requested.emit()
		get_viewport().set_input_as_handled()


func _connect_submit_handlers(parent: Node) -> void:
	for c in parent.get_children():
		if c is SpinBox:
			var le := (c as SpinBox).get_line_edit()
			if not le.text_submitted.is_connected(_on_field_submitted):
				le.text_submitted.connect(_on_field_submitted)
		elif c is LineEdit:
			if not (c as LineEdit).text_submitted.is_connected(_on_field_submitted):
				(c as LineEdit).text_submitted.connect(_on_field_submitted)
		if c.get_child_count() > 0:
			_connect_submit_handlers(c)


func _on_field_submitted(_text: String) -> void:
	confirm_requested.emit()


func close() -> void:
	clear()
	clear_selection.emit()
	hide()


func clear() -> void:
	if box:
		for c in box.get_children():
			c.queue_free()


func _focus_first_input() -> void:
	_focus_first_input_in(box)


# Walk the sidebar tree depth-first, grab focus on the first editable
# control found. LineEdit content is selected so the user can
# immediately type-over.
func _focus_first_input_in(parent: Node) -> bool:
	for c in parent.get_children():
		if c is LineEdit:
			c.grab_focus()
			c.select_all()
			return true
		if c is SpinBox:
			c.get_line_edit().grab_focus()
			c.get_line_edit().select_all()
			return true
		if c is OptionButton or c is CheckButton or c is CheckBox:
			c.grab_focus()
			return true
		if c.get_child_count() > 0:
			if _focus_first_input_in(c):
				return true
	return false


func _on_output_panel_folding_changed(is_folded: bool) -> void:
	if not is_folded:
		close()
