extends GutTest
## The jobs panel renders job descriptions in a wrapping, BBCode-stripped
## custom tooltip (Godot's default tooltip is single-line). These cover
## the shared builder both the title-bar and the job cards use.

const JobsPanel := preload("res://scenes/gui/hex_editor/ui/jobs_panel.gd")


func _label_in(ctl: Control) -> Label:
	for c in ctl.get_children():
		if c is Label:
			return c
	return null


# Build the minimal @onready subtree the script reaches for (the panel
# normally lives inside hex_editor.tscn), so _ready resolves cleanly and
# `jobs_list` is populatable.
func _make_panel() -> Node:
	var panel = JobsPanel.new()  # FoldableContainer
	var margin := MarginContainer.new(); margin.name = "JobsMargin"
	var body := VBoxContainer.new(); body.name = "JobsBody"
	var scroll := ScrollContainer.new(); scroll.name = "JobsScroll"
	var list := VBoxContainer.new(); list.name = "JobsList"
	var divider := HSeparator.new(); divider.name = "ListDivider"
	var top := VBoxContainer.new(); top.name = "TopLabels"
	var desc := RichTextLabel.new(); desc.name = "JobDescriptionLabel"
	panel.add_child(margin)
	margin.add_child(body)
	body.add_child(scroll)
	scroll.add_child(list)
	body.add_child(divider)
	body.add_child(top)
	top.add_child(desc)
	add_child_autofree(panel)
	return panel


func _card(id: String) -> Button:
	var c = JobsPanel._JobCard.new()
	c.toggle_mode = true
	c.job_id = id
	return c


func test_set_selected_moves_highlight_in_place() -> void:
	var panel := _make_panel()
	var list: VBoxContainer = panel.jobs_list
	var a := _card("job_a")
	var b := _card("job_b")
	list.add_child(a)
	list.add_child(b)

	panel.set_selected("job_b")
	assert_false(a.button_pressed, "non-selected card is not pressed")
	assert_true(b.button_pressed, "selected card is pressed")

	panel.set_selected("job_a")
	assert_true(a.button_pressed, "highlight flips to the new selection")
	assert_false(b.button_pressed)

	# No rebuild: the same card instances survive across set_selected.
	assert_eq(list.get_child_count(), 2, "set_selected must not add/remove cards")
	assert_same(list.get_child(0), a, "set_selected reuses the existing card nodes")
	assert_same(list.get_child(1), b)


func test_set_selected_with_empty_clears_all() -> void:
	var panel := _make_panel()
	var a := _card("job_a")
	panel.jobs_list.add_child(a)
	a.set_pressed_no_signal(true)
	panel.set_selected("")
	assert_false(a.button_pressed, "an empty selection presses no card")


func test_wrapped_tooltip_label_wraps_and_keeps_text() -> void:
	var ctl: Control = JobsPanel._build_wrapped_tooltip("First line\nSecond line")
	assert_not_null(ctl, "builder returns a Control")
	add_child_autofree(ctl)
	var lbl := _label_in(ctl)
	assert_not_null(lbl, "tooltip holds a Label")
	assert_eq(lbl.text, "First line\nSecond line", "text passes through verbatim")
	assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
			"long lines wrap instead of overflowing")
	assert_gt(lbl.custom_minimum_size.x, 0.0,
			"a fixed wrap width bounds the tooltip")
