extends GutTest
## Pause-based modal gating: while any Control modal (pause menu,
## quick REPL, library / codex / keybindings / chapter intro) is
## visible, the SceneTree is paused (ModalStack), so every PAUSABLE
## node — the editor, the camera, all input handlers — stops
## receiving _process / _unhandled_input. Dialogs run at
## PROCESS_MODE_WHEN_PAUSED.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")

var _editor: Node


func before_each() -> void:
	ModalStack.reset(get_tree())
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func after_each() -> void:
	# A leaked pause would freeze every later suite in the run.
	ModalStack.reset(get_tree())


func test_editor_boots_unpaused_with_no_modal_open() -> void:
	assert_false(_editor.is_any_modal_open(),
			"Editor should boot with no modal open")
	assert_false(get_tree().paused,
			"Editor should boot with the tree unpaused")


func test_opening_a_modal_pauses_the_tree() -> void:
	_editor._show_help_overlay()
	await get_tree().process_frame
	assert_true(_editor.is_any_modal_open(),
			"Opening keybindings should register a modal")
	assert_true(get_tree().paused,
			"Opening a modal must pause the tree")
	_editor._keybindings_dialog.close()
	await get_tree().process_frame
	assert_false(_editor.is_any_modal_open(),
			"Closing keybindings should drop the modal stack")
	assert_false(get_tree().paused,
			"Closing the last modal must unpause the tree")


func test_stacked_modals_unpause_only_when_all_close() -> void:
	_editor._show_help_overlay()
	_editor.quick_repl_dialog.open(Env.root())
	await get_tree().process_frame
	assert_true(get_tree().paused, "Two modals open → paused")
	_editor.quick_repl_dialog.close()
	await get_tree().process_frame
	assert_true(get_tree().paused,
			"One modal still open → tree must stay paused")
	_editor._keybindings_dialog.close()
	await get_tree().process_frame
	assert_false(get_tree().paused,
			"Last modal closed → tree must unpause")


func test_world_input_handlers_stop_while_paused() -> void:
	# PAUSABLE nodes report can_process() == false while paused —
	# that's the whole gate: no _process, no _unhandled_input.
	var camera = _editor.hex_camera
	assert_true(camera.can_process(),
			"Camera must process with no modal open")
	assert_true(_editor.can_process(),
			"Editor must process with no modal open")
	_editor._show_help_overlay()
	await get_tree().process_frame
	assert_false(camera.can_process(),
			"Camera must be frozen while a modal is open")
	assert_false(_editor.can_process(),
			"Editor must be frozen while a modal is open")
	assert_true(_editor._keybindings_dialog.can_process(),
			"The dialog itself must keep processing while paused")


func test_dialogs_run_when_paused() -> void:
	# Every tracked modal is switched to PROCESS_MODE_WHEN_PAUSED by
	# _track_modal so it can render and take input over the paused world.
	assert_eq(_editor.quick_repl_dialog.process_mode,
			Node.PROCESS_MODE_WHEN_PAUSED)
	assert_eq(_editor._pause_menu.process_mode,
			Node.PROCESS_MODE_WHEN_PAUSED)


func test_save_dialog_pauses_world_and_releases() -> void:
	# A blueprint-save dialog must pause the tree like any other modal so
	# typing the name (e.g. WASD) can't pan the camera or fire editor
	# shortcuts. Regression guard for the save dialog leaking keystrokes.
	_editor._prompt_save_payload({"label": "x", "program": ""}, "x")
	await get_tree().process_frame
	assert_true(get_tree().paused,
			"Opening the save dialog must pause the tree")
	assert_false(_editor.hex_camera.can_process(),
			"Camera must freeze while the save dialog is open (no WASD pan)")

	var dlg := _find_accept_dialog()
	assert_not_null(dlg, "Save dialog should be parented under the editor")
	dlg.canceled.emit()  # Escape / cancel
	dlg.queue_free()
	await get_tree().process_frame
	assert_false(get_tree().paused,
			"Closing the save dialog must unpause the tree")


func _find_accept_dialog() -> AcceptDialog:
	for c in _editor.get_children():
		if c is AcceptDialog:
			return c
	return null


func test_pause_menu_uses_the_shared_stack() -> void:
	_editor._pause_menu.pause()
	await get_tree().process_frame
	assert_true(get_tree().paused, "Pause menu must pause via ModalStack")
	assert_true(_editor.is_any_modal_open())
	_editor._pause_menu._on_resume_button_pressed()
	await get_tree().process_frame
	assert_false(get_tree().paused, "Resume must unpause")
	assert_false(_editor.is_any_modal_open())
