extends GutTest
## InputDisplay — InputMap action → icon-BBCode rendering used by the
## keybindings dialog (and any future control-hint text). Covers the
## icon-asset path, the [code] text fallback, modifier prefixes, and
## mouse-button events.


func test_letter_icon_action() -> void:
	# sys_open_library = B, which ships a letter icon asset.
	var s := InputDisplay.action_bbcode("sys_open_library")
	assert_string_contains(s, "letters/b.tres")
	assert_string_contains(s, "[img valign=center, width=24]")


func test_modifier_prefix_and_text_fallback() -> void:
	# sys_undo = Ctrl+Z: control modifier icon + no Z asset → [code]Z[/code].
	var s := InputDisplay.action_bbcode("sys_undo")
	assert_string_contains(s, "special/control.tres")
	assert_string_contains(s, "[code]Z[/code]")


func test_shift_modifier_with_icon_key() -> void:
	# hex_rotate_ccw = Shift+R: shift icon then the R letter icon.
	var s := InputDisplay.action_bbcode("hex_rotate_ccw")
	assert_string_contains(s, "special/shift.tres")
	assert_string_contains(s, "letters/r.tres")
	assert_true(s.find("special/shift.tres") < s.find("letters/r.tres"),
			"Modifier icon should precede the key icon")


func test_wheel_event_renders_scroll_icon() -> void:
	# canvas_zoom_in carries `=` plus a wheel-up mouse event.
	var s := InputDisplay.action_bbcode("canvas_zoom_in")
	assert_string_contains(s, "mouse/scroll_wheel.tres")


func test_unknown_action_is_empty() -> void:
	assert_eq(InputDisplay.action_bbcode("no_such_action"), "")


func test_mouse_button_event() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	assert_string_contains(InputDisplay.event_bbcode(ev), "mouse/right_mb.tres")
