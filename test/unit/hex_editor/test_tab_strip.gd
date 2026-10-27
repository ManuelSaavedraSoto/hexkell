extends GutTest
## The tab strip owns its own view: it builds a button per tab from the
## editor-supplied names + active index, and re-emits clicks as
## `tab_switch_requested` intents. (Context menu / rename dialog are
## exercised in the integration harness.)

const TabStripScript := preload("res://scenes/gui/hex_editor/ui/tab_strip.gd")


func _make_strip() -> Node:
	var strip = TabStripScript.new()  # extends HBoxContainer
	add_child_autofree(strip)
	return strip


func _buttons(strip: Node) -> Array:
	var out: Array = []
	for c in strip.get_children():
		if c is Button:
			out.append(c)
	return out


func test_rebuild_makes_a_button_per_tab_with_active_pressed() -> void:
	var strip := _make_strip()
	strip.rebuild(["Tab 1", "Tab 2", "Tab 3"], 1)
	var btns := _buttons(strip)
	assert_eq(btns.size(), 3, "One button per tab name")
	assert_eq(btns[0].text, "Tab 1")
	assert_true(btns[1].button_pressed, "The active tab's button is pressed")
	assert_false(btns[0].button_pressed)


func test_button_press_emits_switch_intent() -> void:
	var strip := _make_strip()
	strip.rebuild(["A", "B"], 0)
	var got: Array = []
	strip.tab_switch_requested.connect(func(idx: int) -> void: got.append(idx))
	_buttons(strip)[1].pressed.emit()
	assert_eq(got, [1], "Pressing tab button 1 emits tab_switch_requested(1)")
