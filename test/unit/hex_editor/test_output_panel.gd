extends GutTest
## OutputPanel folded-state title regression: BBCode tags must be
## stripped before assigning to FoldableContainer.title (a plain-text
## Label) so log messages don't render as literal `[color=...]...
## [/color]` in the title strip. The body's RichTextLabel keeps the
## raw tagged text untouched — only the title gets the strip.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")

var _editor: Node


func before_each() -> void:
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func test_title_strips_bbcode_color_tags() -> void:
	_editor.output_panel.append_output(
			"[color=#9fcfff]Saved blueprint 'foo'.[/color]")
	assert_eq(_editor.output_panel.title, "Saved blueprint 'foo'.",
			"Color tags should drop from the folded-state title")


func test_title_normalizes_backslash_close() -> void:
	# `[\bold]` is a common typo for `[/bold]`. Normalize before
	# stripping so authors don't have to babysit the title preview.
	_editor.output_panel.append_output("[bold]Boom[\\bold]")
	assert_eq(_editor.output_panel.title, "Boom",
			"Both [bold] and [\\bold] should drop from the title")


func test_title_falls_back_when_no_output_yet() -> void:
	assert_eq(_editor.output_panel.title, "Output",
			"Empty output state should show the FALLBACK_TITLE")


func test_body_retains_raw_bbcode() -> void:
	# Title is plain-text; body is a RichTextLabel that parses BBCode.
	# Guard that the strip only touches the title, not the body's
	# text source.
	_editor.output_panel.append_output("[color=red]bad[/color]")
	assert_string_contains(
			_editor.output_panel.output_label.get_parsed_text(), "bad",
			"Body should still render the tagged text")


# ── Outcome-aware status title ─────────────────────────────────────────────

func test_status_drives_title() -> void:
	_editor.output_panel.set_status("result", "=> 8")
	assert_eq(_editor.output_panel.title, "=> 8",
			"set_status should own the folded-state title")


func test_info_lines_do_not_bury_status() -> void:
	_editor.output_panel.set_status("pass", "✓ Solved — 3/3 tests passed")
	_editor.output_panel.append_output("[color=#ffd86b]+5 renown.[/color]")
	assert_eq(_editor.output_panel.title, "✓ Solved — 3/3 tests passed",
			"Trailing info lines must not overwrite the verdict title")


func test_status_strips_bbcode_too() -> void:
	_editor.output_panel.set_status("error", "[color=red]Runtime error[/color]")
	assert_eq(_editor.output_panel.title, "Runtime error",
			"Status text should strip BBCode like log lines do")


func test_title_ellipsizes_long_status() -> void:
	var long_text := "x".repeat(120)
	_editor.output_panel.set_status("result", long_text)
	assert_eq(_editor.output_panel.title.length(),
			_editor.output_panel.TITLE_MAX_CHARS,
			"Over-long titles should clamp to TITLE_MAX_CHARS")
	assert_true(_editor.output_panel.title.ends_with("…"),
			"Clamped titles end with an ellipsis")


func test_unlock_notice_cycles_with_status() -> void:
	var panel = _editor.output_panel
	panel.set_status("pass", "✓ Solved — 1/1 tests passed")
	panel.notify_unlock("🔓 2 new hex type(s) unlocked")
	assert_eq(panel.title, "🔓 2 new hex type(s) unlocked",
			"Notice shows immediately on arrival")
	panel._cycle_timer.timeout.emit()
	assert_eq(panel.title, "✓ Solved — 1/1 tests passed",
			"First cycle flips back to the verdict")
	panel._cycle_timer.timeout.emit()
	assert_eq(panel.title, "🔓 2 new hex type(s) unlocked",
			"Second cycle returns to the notice")


func test_unfolding_dismisses_unlock_notice() -> void:
	var panel = _editor.output_panel
	panel.set_status("pass", "✓ Solved — 1/1 tests passed")
	panel.notify_unlock("🔓 1 new hex type(s) unlocked")
	panel.expand()  # panel starts folded; this unfolds it
	assert_eq(panel.title, "✓ Solved — 1/1 tests passed",
			"Unfolding dismisses the notice back to the status")
	assert_true(panel._cycle_timer.is_stopped(),
			"Dismissal stops the cycle timer")


func test_o_toggles_box_open_and_closed_on_log_view() -> void:
	var panel = _editor.output_panel  # starts folded
	panel.toggle_log_view()
	assert_false(panel.folded, "O opens the output box")
	assert_eq(panel._current_view, "log", "O lands on the log view")
	panel.toggle_log_view()
	assert_true(panel.folded, "O again closes the box")


func test_switching_between_views_keeps_the_box_open() -> void:
	var panel = _editor.output_panel
	panel.toggle_text_view()  # open straight to the text view
	assert_false(panel.folded)
	assert_eq(panel._current_view, "text")
	panel.toggle_log_view()   # switch to log, must stay open
	assert_false(panel.folded, "switching view doesn't close the box")
	assert_eq(panel._current_view, "log")


func test_clear_output_resets_status_and_notice() -> void:
	var panel = _editor.output_panel
	panel.set_status("result", "=> 8")
	panel.notify_unlock("🔓 1 new hex type(s) unlocked")
	panel.clear_output()
	assert_eq(panel.title, "Output",
			"clear_output returns the title to the fallback")
