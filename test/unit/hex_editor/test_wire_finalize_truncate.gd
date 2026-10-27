extends GutTest
## Releasing an illegal (stuck) wire drops its un-routable tail back to the
## last locked chain point, or removes the wire entirely when nothing was
## locked. Legal open stubs (not stuck) are untouched — covered elsewhere.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const AddHex := preload(
		"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")

var _saved_hex: Dictionary
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
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


func _source_hex() -> HexNode:
	var h: HexNode = HexNode.from_script(AddHex)
	h.level = _editor._current_level()
	_editor._current_level().hexes.append(h)
	add_child_autofree(h)
	h.set_axial(Vector2i(10, 10))
	await get_tree().process_frame
	return h


func test_stuck_wire_truncates_to_last_lock() -> void:
	var src := await _source_hex()
	_editor._start_wiring(src, 0, true)
	var w = _editor._active_wire
	var before: int = _editor._current_level().wires.size()
	w.cells = [
		HexWire.make_cell(Vector2i(11, 10), 3, 0),
		HexWire.make_cell(Vector2i(12, 10), 3, 0),
		HexWire.make_cell(Vector2i(13, 10), 3, -1),
	]
	w.lock_indices = [1] as Array[int]
	w.anchored_count = 2  # locked prefix ends at cell index 1
	w.is_stuck = true
	_editor._finalize_active_wire_open()
	var wires: Array = _editor._current_level().wires
	assert_eq(wires.size(), before + 1, "the locked prefix survives as an open stub")
	assert_eq(wires[wires.size() - 1].cells.size(), 2,
			"the un-routable tail is dropped back to the lock")


func test_stuck_wire_with_no_locks_is_removed() -> void:
	var src := await _source_hex()
	_editor._start_wiring(src, 0, true)
	var w = _editor._active_wire
	var before: int = _editor._current_level().wires.size()
	w.cells = [
		HexWire.make_cell(Vector2i(11, 10), 3, 0),
		HexWire.make_cell(Vector2i(12, 10), 3, -1),
	]
	w.lock_indices = [] as Array[int]
	w.anchored_count = 0
	w.is_stuck = true
	_editor._finalize_active_wire_open()
	assert_null(_editor._active_wire, "the wire is cancelled back to the source")
	assert_eq(_editor._current_level().wires.size(), before, "no stub left behind")


# Undoing a wire delete restores it at full width even if the delete
# animation had thinned the line away (guards the pop-then-thin teardown).
func test_restore_wire_resets_width_and_visibility() -> void:
	var w := HexWire.new()
	var line := Line2D.new()
	_editor.connections_layer.add_child(line)
	w.line = line
	# Simulate a finished delete animation: thinned to nothing and parked.
	line.width = 0.0
	line.visible = false
	_editor._restore_wire(w)
	assert_eq(line.width, HexWire.WIDTH, "restore resets the wire to full width")
	assert_true(line.visible, "restore makes the wire visible again")
