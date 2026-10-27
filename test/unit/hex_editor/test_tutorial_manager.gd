extends GutTest
## Chapter-0 tutorial FSM. The manager funnels every tracked signal
## into one `_on_event(kind, payload)` entry point, which makes the
## machine drivable here without a live editor: instantiate the script
## directly, force `running`, and feed synthetic events.

const TutorialScript := preload("res://src/singletons/tutorial_manager.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload(
		"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")

var _tm: Node
var _saved_story: Dictionary
var _saved_autosave: bool


func before_each() -> void:
	_saved_story = SaveManager.current_data["story"].duplicate(true)
	_saved_autosave = SaveManager.get_auto_save()
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["story"]["has_completed_tutorial"] = false
	_tm = TutorialScript.new()
	add_child_autofree(_tm)


func after_each() -> void:
	SaveManager.current_data["story"] = _saved_story
	SaveManager.current_data["preferences"]["auto_save"] = _saved_autosave
	TutorialManager.reset()


# Drive the FSM to a given step id by replaying the happy path.
func _play_until(stop_id: StringName) -> void:
	_tm.running = true
	_tm._begin()
	var script := [
		[&"kb_pan", Vector2(400, 0)],
		[&"zoom", 1.2],
		[&"jobs_fold", false],
		[&"job_selected", "job_01_any_number"],
		[&"category", 0],
		[&"hex_pick", load(TutorialScript.INT_HEX_PATH)],
		[&"hex_placed", {"node": null, "axial": TutorialScript.TARGET_AXIAL}],
		[&"blueprint_exit", null],
		[&"config_opened", null],
		[&"value_changed", null],
		[&"config_closed", null],
	]
	for ev in script:
		if _current_id() == stop_id:
			return
		_tm._on_event(ev[0], ev[1])


func _current_id() -> StringName:
	if _tm._step_idx < 0 or _tm._step_idx >= _tm._steps.size():
		return &""
	return _tm._steps[_tm._step_idx].get("id", &"")


func test_inactive_when_flag_already_set() -> void:
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	var tm := TutorialScript.new()
	add_child_autofree(tm)
	assert_false(tm.active, "Completed tutorial must boot dormant")


func test_happy_path_advances_in_order() -> void:
	_tm.running = true
	_tm._begin()
	assert_eq(_current_id(), &"move_camera_wasd")
	# Below the accumulation threshold: no advance yet.
	_tm._on_event(&"kb_pan", Vector2(100, 0))
	assert_eq(_current_id(), &"move_camera_wasd",
			"100px of WASD travel should not clear the 300px goal")
	_tm._on_event(&"kb_pan", Vector2(250, 0))
	assert_eq(_current_id(), &"pan_zoom_mouse")
	# Zoom alone clears the mouse step (alt_event).
	_tm._on_event(&"zoom", 1.2)
	assert_eq(_current_id(), &"open_jobs_panel")
	# Folding (not UNfolding) must not advance.
	_tm._on_event(&"jobs_fold", true)
	assert_eq(_current_id(), &"open_jobs_panel")
	_tm._on_event(&"jobs_fold", false)
	assert_eq(_current_id(), &"select_job")


func test_out_of_order_events_are_ignored() -> void:
	_tm.running = true
	_tm._begin()
	# Events for later steps arrive while step 1 is active: no motion.
	_tm._on_event(&"jobs_fold", false)
	_tm._on_event(&"category", 0)
	_tm._on_event(&"job_solved", "job_01_any_number")
	assert_eq(_current_id(), &"move_camera_wasd",
			"Only the current step's event may advance the FSM")


func test_wrong_payload_does_not_advance() -> void:
	_play_until(&"select_job")
	_tm._on_event(&"job_selected", "job_06_double_white")
	assert_eq(_current_id(), &"select_job",
			"Selecting a different job must not clear the step")
	_tm._on_event(&"job_selected", "job_01_any_number")
	assert_eq(_current_id(), &"select_category")


func test_gating_per_step() -> void:
	_play_until(&"select_job")
	assert_true(_tm.allows_job("job_01_any_number"))
	assert_false(_tm.allows_job("job_02_double_white"))
	assert_false(_tm.allows(&"run"), "Run is gated until the last step")
	assert_false(_tm.allows_category(0), "Palette dead before its step")
	assert_true(_tm.allows_category(-1), "Manager-initiated deselect always passes")
	_play_until(&"select_category")
	assert_true(_tm.allows_category(0))
	assert_false(_tm.allows_category(1))
	_play_until(&"place_hex")
	assert_true(_tm.allows_placement(TutorialScript.TARGET_AXIAL))
	assert_false(_tm.allows_placement(Vector2i(5, 5)))
	_play_until(&"wire_to_do")
	assert_false(_tm.allows_placement(TutorialScript.TARGET_AXIAL),
			"No placements outside the placement step")


func test_gating_open_when_not_running() -> void:
	assert_true(_tm.allows(&"run"))
	assert_true(_tm.allows_job("job_08_pick_bigger"))
	assert_true(_tm.allows_category(3))
	assert_true(_tm.allows_placement(Vector2i(9, 9)))


func test_completion_sets_save_flag() -> void:
	_play_until(&"wire_to_do")
	# Synthetic wire payloads can't satisfy the endpoint checks without an
	# editor; skip the routing-lesson steps straight to the run step.
	_tm._step_idx = _tm._step_index(&"run_job")
	assert_eq(_current_id(), &"run_job")
	_tm._on_event(&"job_solved", "job_01_any_number")
	assert_eq(_current_id(), &"clear_board",
			"running advances to the clear-board step, not straight to completion")
	_tm._on_event(&"board_cleared", null)
	assert_true(SaveManager.has_completed_tutorial(),
			"Finishing the last step must persist the flag immediately")
	assert_false(_tm.running)


func test_wire_lock_and_clear_steps() -> void:
	_play_until(&"wire_to_do")
	# `_play_until` runs `_begin`, which clears `_placed_hex`; set the editor
	# stand-in + placed hex afterwards so the wiring checks can resolve.
	var stub := _StubEditor.new()
	# Wire endpoints are typed HexNode, so use real hex instances (identity
	# is all the checks compare).
	var placed: HexNode = HexNode.from_script(IntLiteralHex)
	var do: HexNode = HexNode.from_script(IntLiteralHex)
	add_child_autofree(stub)
	add_child_autofree(placed)
	add_child_autofree(do)
	stub.do_node = do
	_tm._editor = stub
	_tm._placed_hex = placed
	# A wire connecting hex ↔ Do clears the (straight) wire step.
	var w1 := HexWire.new()
	w1.output_node = placed
	w1.input_node = do
	w1.is_open = false
	_tm._on_event(&"wire", w1)
	assert_eq(_current_id(), &"delete_wire")
	# Deleting that wire clears the delete step.
	_tm._on_event(&"wire_deleted", w1)
	assert_eq(_current_id(), &"route_locked_bend")
	# A straight (unlocked) re-wire must NOT advance — the lesson needs C.
	var w2 := HexWire.new()
	w2.output_node = placed
	w2.input_node = do
	w2.is_open = false
	_tm._on_event(&"wire", w2)
	assert_eq(_current_id(), &"route_locked_bend",
			"a wire committed without pressing C doesn't satisfy the bend step")
	# Pressing C during the step sets the flag; the same re-wire now advances.
	_tm._on_wire_locked()
	_tm._on_event(&"wire", w2)
	assert_eq(_current_id(), &"run_job")
	_tm._on_event(&"job_solved", "job_01_any_number")
	assert_eq(_current_id(), &"clear_board")
	# Clearing the board deletes the placed hex — at this step that must NOT
	# trip the re-place safeguard (which would revert to place_hex).
	_tm._on_hex_deleted(placed)
	assert_eq(_current_id(), &"clear_board",
			"deleting the placed hex while clearing doesn't revert the tutorial")
	# Drop the editor so completion tears down without the congrats timer.
	_tm._editor = null
	_tm._on_event(&"board_cleared", null)
	assert_true(SaveManager.has_completed_tutorial(),
			"clearing the board finishes the tutorial")


func test_deleting_placed_hex_rolls_back_to_place_step() -> void:
	_play_until(&"open_config")
	assert_eq(_current_id(), &"open_config", "Drove past the place step")
	var dummy := Node2D.new()
	add_child_autofree(dummy)
	_tm._placed_hex = dummy
	_tm._on_hex_deleted(dummy)
	assert_eq(_current_id(), &"place_hex",
			"Deleting the placed hex rolls the tutorial back to the place step")
	assert_null(_tm._placed_hex, "The stale placed-hex ref is cleared")


# Minimal editor stand-in exposing just the open-state getter the
# close_config skip predicate reads. Extends Node to satisfy the
# manager's `var _editor: Node`.
class _StubEditor extends Node:
	var config_open := false
	var do_node: Node = null
	func is_config_open() -> bool:
		return config_open


func test_close_config_skips_when_panel_already_closed() -> void:
	# Enter both sets the value and closes the panel: `config_closed`
	# fires before the FSM reaches close_config, so the step must
	# auto-skip rather than strand the player on an already-closed panel.
	_play_until(&"set_value")
	assert_eq(_current_id(), &"set_value", "Drove to the set-value step")
	var stub := _StubEditor.new()
	add_child_autofree(stub)
	stub.config_open = false
	_tm._editor = stub
	_tm._on_event(&"value_changed", null)
	assert_eq(_current_id(), &"wire_to_do",
			"close_config auto-skips when the config is already closed")


func test_close_config_shows_when_panel_still_open() -> void:
	# Scroll-to-set leaves the panel open, so close_config is a real step.
	_play_until(&"set_value")
	var stub := _StubEditor.new()
	add_child_autofree(stub)
	stub.config_open = true
	_tm._editor = stub
	_tm._on_event(&"value_changed", null)
	assert_eq(_current_id(), &"close_config",
			"close_config stays put while the panel is still open")
	_tm._on_event(&"config_closed", null)
	assert_eq(_current_id(), &"wire_to_do",
			"closing the panel then advances to wiring")


func test_deleting_some_other_hex_does_not_roll_back() -> void:
	_play_until(&"open_config")
	var placed := Node2D.new()
	var other := Node2D.new()
	add_child_autofree(placed)
	add_child_autofree(other)
	_tm._placed_hex = placed
	_tm._on_hex_deleted(other)
	assert_eq(_current_id(), &"open_config",
			"Deleting an unrelated hex must not disturb the FSM")
	assert_eq(_tm._placed_hex, placed, "The placed-hex ref is untouched")


func test_reset_rearms_after_flag_clear() -> void:
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	_tm.reset()
	assert_false(_tm.active)
	SaveManager.current_data["story"]["has_completed_tutorial"] = false
	_tm.reset()
	assert_true(_tm.active)
	assert_eq(_tm._step_idx, -1)
