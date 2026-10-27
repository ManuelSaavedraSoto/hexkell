extends GutTest
## Outcome highlights on the Output and Jobs panel title bars: a solved job
## pulses green (held until opened / until the job changes), an error pulses
## red, and opening the output panel (or switching jobs) clears the pulse.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")

var _editor: Node


func before_each() -> void:
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


# ── Output panel ────────────────────────────────────────────────────────────

func test_pass_status_starts_a_solve_pulse() -> void:
	var op = _editor.output_panel
	op.set_status("pass", "✓ solved — 3/3 tests passed")
	assert_eq(op._outcome, "solve", "a passing submit flags the solve outcome")
	assert_not_null(op._pulse_tween, "the solve outcome pulses the title")


func test_error_status_starts_an_error_pulse() -> void:
	var op = _editor.output_panel
	op.set_status("error", "Runtime error")
	assert_eq(op._outcome, "error", "an error flags the error outcome")
	assert_not_null(op._pulse_tween, "the error outcome pulses the title")


func test_neutral_status_clears_the_outcome() -> void:
	var op = _editor.output_panel
	op.set_status("error", "boom")
	op.set_status("result", "=> 42")
	assert_eq(op._outcome, "", "a plain result clears the prior outcome")
	assert_null(op._pulse_tween, "no pulse on a neutral result")


func test_opening_output_panel_dismisses_the_pulse() -> void:
	var op = _editor.output_panel
	op.set_status("pass", "✓ solved")
	# The folded setter is silent, so unfold then invoke the handler the
	# scene wires to folding_changed (mirrors a real title-bar click open).
	op.folded = false
	op._on_folding_changed(false)
	assert_eq(op._outcome, "", "opening the panel clears the outcome")
	assert_null(op._pulse_tween, "opening the panel stops the pulse")


# ── Jobs panel ──────────────────────────────────────────────────────────────

func test_flag_solved_pulses_until_job_changes() -> void:
	var jp = _editor.jobs_panel
	jp.set_selected_job("Job A", "desc")
	jp.flag_solved()
	assert_true(jp._solved, "the solved highlight is active")
	assert_not_null(jp._pulse_tween, "the jobs title pulses green")
	# Re-selecting the same job (the post-solve refresh) keeps the highlight.
	jp.set_selected_job("Job A", "desc")
	assert_true(jp._solved, "re-selecting the same job keeps the highlight")
	# Moving to a different job ends it.
	jp.set_selected_job("Job B", "desc")
	assert_false(jp._solved, "switching jobs clears the highlight")
	assert_null(jp._pulse_tween, "switching jobs stops the pulse")
