extends GutTest
## A single right-click that cancels a mode must NOT also delete the hex
## under the cursor. One physical RMB on a hex body is processed by BOTH
## the editor's `_unhandled_input` (the contextual-cancel cascade) AND the
## hex body's physics-picked `delete_requested` → `_on_node_delete_requested`
## path. When the config panel or a stamp is active, the first pass cancels
## it; the `_rmb_cancelled_press` guard then suppresses the second pass so
## the spared hex survives. Regression guard for "RMB to close config /
## exit stamp also deletes the hex".

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")

var _saved_hex: Dictionary
var _editor: Node


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


# Place a hex on the active level and register its editor signals (so
# `delete_requested` is wired to `_on_node_delete_requested`).
func _place(script: Script, axial: Vector2i) -> HexNode:
	var hex: HexNode = HexNode.from_script(script)
	_editor.nodes_layer.add_child(hex)
	hex.set_axial(axial)
	hex.level = _editor._current_level()
	_editor._current_level().hexes.append(hex)
	_editor._wire_node_signals(hex)
	return hex


func _rmb_press() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	return ev


func test_rmb_with_config_open_cancels_without_deleting() -> void:
	var hex := _place(IntLiteralHex, Vector2i(3, 0))
	_editor._open_config_sidebar(hex)
	assert_true(_editor.is_config_open(), "Config panel should be open")

	# 1) Editor's _unhandled_input consumes the RMB, cancelling the panel.
	_editor._unhandled_input(_rmb_press())
	assert_false(_editor.is_config_open(), "RMB should close the config panel")
	assert_true(_editor._rmb_cancelled_press,
			"The cancel must flag the press for the body-delete path")

	# 2) The physics-picked hex-body delete fires for the SAME press.
	_editor._on_node_delete_requested(hex)
	assert_true(is_instance_valid(hex) and hex.get_parent() != null,
			"RMB that closed the config panel must NOT delete the hex")
	assert_true(_editor._current_level().hexes.has(hex),
			"Hex stays registered in the level")
	assert_false(_editor._rmb_cancelled_press, "Guard is consumed once")


func test_rmb_exiting_stamp_cancels_without_deleting() -> void:
	var hex := _place(IntLiteralHex, Vector2i(3, 0))
	var payload := BlueprintCodec.serialize_subset(
			[hex], null, "stamp", "", "", Vector2i.ZERO)
	_editor._begin_stamp(payload)
	await get_tree().process_frame
	assert_false(_editor._stamp_previews.is_empty(), "Stamp mode should be active")

	_editor._unhandled_input(_rmb_press())
	assert_true(_editor._stamp_previews.is_empty(), "RMB should exit stamp mode")
	assert_true(_editor._rmb_cancelled_press,
			"The cancel must flag the press for the body-delete path")

	_editor._on_node_delete_requested(hex)
	assert_true(is_instance_valid(hex) and hex.get_parent() != null,
			"RMB that exited stamp must NOT delete the hex under the cursor")
	assert_false(_editor._rmb_cancelled_press, "Guard is consumed once")


func test_rmb_on_hex_with_nothing_active_still_deletes() -> void:
	# The guard must not break the ordinary RMB-deletes-a-hex behaviour:
	# with no mode active the cascade does nothing and the body path runs.
	var hex := _place(IntLiteralHex, Vector2i(3, 0))
	assert_false(_editor.is_config_open())
	assert_true(_editor._stamp_previews.is_empty())

	_editor._unhandled_input(_rmb_press())
	assert_false(_editor._rmb_cancelled_press,
			"Nothing to cancel → the press is not flagged")
	_editor._on_node_delete_requested(hex)
	assert_false(_editor._current_level().hexes.has(hex),
			"A plain RMB on a hex with nothing active still deletes it")
