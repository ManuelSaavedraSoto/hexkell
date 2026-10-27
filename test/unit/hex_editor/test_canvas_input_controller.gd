extends GutTest
## Decentralized keyboard input: actions dispatch from each owner's
## _unhandled_input to the right behavior. Events are synthesized
## InputEventKeys that match the InputMap bindings (physical
## keycodes), fed straight to the owners' handlers.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")

var _editor: Node
var _saved_hex: Dictionary


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["hex"]["tabs"] = []
	SaveManager.current_data["hex"]["current_tab_id"] = 0
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	ChapterManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func after_each() -> void:
	SaveManager.current_data["hex"] = _saved_hex
	ModalStack.reset(get_tree())


func _key(physical: Key, shift := false, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	return ev


func _controller() -> Node:
	return _editor.get_node("CanvasInputController")


func test_cancel_action_exits_blueprint_mode() -> void:
	_editor._enter_blueprint_fresh(IntLiteralHex)
	assert_not_null(_editor._blueprint_node, "Setup: blueprint mode active")
	_controller()._unhandled_input(_key(KEY_ESCAPE))
	assert_null(_editor._blueprint_node,
			"cancel action must exit blueprint mode")


func test_library_action_opens_the_dialog_and_pauses() -> void:
	_controller()._unhandled_input(_key(KEY_B))
	await get_tree().process_frame
	assert_not_null(_editor._library_dialog, "B must open the library")
	assert_true(_editor._library_dialog.visible)
	assert_true(get_tree().paused, "Open library modal must pause the tree")
	_editor._library_dialog.close()
	await get_tree().process_frame
	assert_false(get_tree().paused)


func test_undo_action_reverts_a_placement() -> void:
	var lvl = _editor._current_level()
	var before: int = lvl.hexes.size()
	_editor._enter_blueprint_fresh(IntLiteralHex)
	_editor._commit_blueprint()
	_editor._exit_blueprint_mode()
	assert_eq(lvl.hexes.size(), before + 1, "Setup: one hex placed")
	_controller()._unhandled_input(_key(KEY_Z, false, true))
	assert_eq(lvl.hexes.size(), before, "Ctrl+Z must undo the placement")


func test_palette_slot_action_picks_a_hex() -> void:
	var got: Array = []
	_editor.palette_bar.hex_selected.connect(func(s): got.append(s))
	_editor.palette_bar.select_category(0)
	_editor.palette_bar._unhandled_input(_key(KEY_1))
	assert_eq(got.size(), 1, "Pressing 1 must pick palette slot 0")


func test_output_toggle_action_flips_fold() -> void:
	var before: bool = _editor.output_panel.folded
	_editor.output_panel._unhandled_input(_key(KEY_O))
	assert_eq(_editor.output_panel.folded, not before,
			"O must toggle the output panel fold")


func test_rotate_action_rotates_blueprint_preview() -> void:
	_editor._enter_blueprint_fresh(IntLiteralHex)
	var node = _editor._blueprint_node
	var before: int = node.rotation_index
	_controller()._unhandled_input(_key(KEY_R))
	assert_eq(node.rotation_index, (before + 1) % 6,
			"R must rotate the blueprint preview clockwise")
	_controller()._unhandled_input(_key(KEY_R, true))
	assert_eq(node.rotation_index, before,
			"Shift+R must rotate counter-clockwise")
	_editor._exit_blueprint_mode()
