extends GutTest
## Wire legality on rotation + blueprint open-wire auto-connect.
##  - Rotating a hex deletes any wire the rotation strands (and undo/redo
##    restores / re-removes it).
##  - A stamped open (grey) wire whose tail lands on a compatible free slot
##    snaps shut instead of dangling.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const HexMath := preload("res://src/statics/hex_math.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")

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


func _place(axial: Vector2i) -> HexNode:
	var hex: HexNode = HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(hex)
	hex.set_axial(axial)
	hex.level = _editor._current_level()
	_editor._current_level().hexes.append(hex)
	return hex


func _wire(src: HexNode, out_edge: int, sink: HexNode, in_edge: int) -> HexWire:
	var w := HexWire.new()
	w.output_node = src
	w.output_edge = out_edge
	w.input_node = sink
	w.input_edge = in_edge
	w.anchor_node = src
	w.anchor_edge = out_edge
	w.anchor_is_output = true
	w.is_finalized = true
	w.line = HexWire.build_line(false)
	_editor._current_level().add_wire_line(w.line)
	_editor._current_level().wires.append(w)
	return w


# Rotating a hex so its output slot now faces a blocked cell strands the
# wire — it must be auto-deleted, and undo/redo must round-trip it.
func test_rotation_deletes_stranded_wire_and_round_trips() -> void:
	var level = _editor._current_level()
	var src := _place(Vector2i(0, 0))   # output_edge 0 (E) → leaves at (1,0)
	var sink := _place(Vector2i(3, 0))  # input via edge 3 (W) → approach (2,0)
	_place(Vector2i(0, 1))              # blocker on the SE exit after rotation
	var w := _wire(src, 0, sink, 3)

	_editor._rotate_hex_command(src, 1)  # edge 0 now physical SE → start (0,1) blocked
	assert_false(w in level.wires, "the stranded wire is auto-deleted on rotation")
	assert_eq(_editor._undo_stack[-1].type, "rotate_hex")
	assert_true(w in _editor._undo_stack[-1].deleted_wires,
			"the deleted wire is recorded on the rotate action for undo")

	_editor._undo()
	assert_true(w in level.wires, "undo restores both the rotation and the wire")
	assert_false(w.is_stuck, "the restored wire routes cleanly at the original facing")

	_editor._redo()
	assert_false(w in level.wires, "redo re-rotates and re-deletes the wire")


# An open wire whose dangling tail sits on a hex's free output slot's
# approach cell binds to that slot when auto-connect runs.
func test_open_wire_snaps_onto_a_compatible_free_slot() -> void:
	var level = _editor._current_level()
	var bound := _place(Vector2i(10, 0))   # the wire's already-bound (input) end
	var target := _place(Vector2i(3, 0))   # the slot the open tail lands on
	var out_edge: int = target.output_edges[0]
	var approach: Vector2i = target.axial + HexMath.EDGE_DELTAS[target.physical_edge(out_edge)]

	# Open wire missing its OUTPUT end, tail parked on the slot's approach cell.
	var w := HexWire.new()
	w.input_node = bound
	w.input_edge = 0
	w.anchor_node = bound
	w.anchor_edge = 0
	w.anchor_is_output = false  # anchor is the bound input; open end is the output
	w.is_open = true
	w.is_finalized = true
	w.cells = [HexWire.make_cell(approach, 0, -1)]
	w.line = HexWire.build_line(true)
	level.add_wire_line(w.line)

	_editor._auto_connect_open_wire(w, level)

	assert_false(w.is_open, "the open wire closed onto the slot")
	assert_eq(w.output_node, target, "it bound to the hex at the endpoint")
	assert_eq(w.output_edge, out_edge, "it bound to that hex's output slot")
	assert_eq(w.cells[-1].exit_edge, (target.physical_edge(out_edge) + 3) % 6,
			"the tail cell now exits toward the connected hex")
