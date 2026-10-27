extends GutTest
## The config sidebar must not pre-empt Enter when a text field is
## focused: a focused SpinBox/LineEdit commits the typed value first (and
## its `text_submitted` then closes the panel). Only an Enter with nothing
## focused should close the panel directly. Regression guard for the
## tutorial `set_value` step losing the typed integer.

const ConfigSidebarScript := preload("res://scenes/gui/hex_editor/ui/config_sidebar.gd")


func _make_sidebar() -> Node:
	# The script reaches for `$ConfigMargin/ConfigBox` and `%OutputPanel`
	# in `@onready` (it normally lives inside hex_editor.tscn). Build that
	# minimal named subtree — with owners so the unique-name `%` resolves —
	# before the node enters the tree, so `_ready` stays error-free.
	var sidebar = ConfigSidebarScript.new()  # extends PanelContainer
	var margin := MarginContainer.new()
	margin.name = "ConfigMargin"
	sidebar.add_child(margin)
	margin.owner = sidebar
	var cbox := VBoxContainer.new()
	cbox.name = "ConfigBox"
	margin.add_child(cbox)
	cbox.owner = sidebar
	var out := FoldableContainer.new()
	out.name = "OutputPanel"
	sidebar.add_child(out)
	out.owner = sidebar
	out.unique_name_in_owner = true
	add_child_autofree(sidebar)
	sidebar.show()
	return sidebar


func _enter_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	return ev


func test_enter_ignored_while_a_field_is_focused() -> void:
	var sidebar := _make_sidebar()
	var le := LineEdit.new()
	add_child_autofree(le)
	le.grab_focus()
	var got: Array = []
	sidebar.confirm_requested.connect(func() -> void: got.append(1))
	sidebar._unhandled_key_input(_enter_event())
	assert_eq(got.size(), 0,
			"Enter must defer to the focused field so it can commit its value")


func test_enter_closes_when_nothing_is_focused() -> void:
	var sidebar := _make_sidebar()
	var le := LineEdit.new()
	add_child_autofree(le)
	le.grab_focus()
	le.release_focus()
	var got: Array = []
	sidebar.confirm_requested.connect(func() -> void: got.append(1))
	sidebar._unhandled_key_input(_enter_event())
	assert_eq(got.size(), 1,
			"Enter with no focused field confirms + closes the panel")
