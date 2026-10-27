extends GutTest
## A hex dropped edge-to-edge against a compatible neighbour should be
## detected as an immediate connection (so placement plays the "connect" cue
## instead of "place"). Covers the editor's `_placed_connection_edge` helper,
## which mirrors the adjacency rule in `get_input_for` in both directions.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload(
		"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload(
		"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")

const POP_SCALE := 1.18

var _saved_hex: Dictionary
var _editor: Node


func before_each() -> void:
	# A clean, empty story tab so the level holds only the hexes we place.
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


func _place(script: Script, axial: Vector2i, rotation := 0) -> HexNode:
	var h: HexNode = HexNode.from_script(script)
	h.level = _editor._current_level()
	_editor._current_level().hexes.append(h)
	add_child_autofree(h)
	h.set_axial(axial)
	if rotation != 0:
		h.set_rotation_index(rotation)
	await get_tree().process_frame
	return h


# IntLiteral broadcasts East (output edge 0). Place it on an empty cell and an
# AddHex at its East neighbour, rotated so the Add's SW input (logical 2)
# physically faces West back into the literal. Both ends report the connection.
func test_slap_adjacency_is_detected_both_ways() -> void:
	var lit := await _place(IntLiteralHex, Vector2i(10, 10))
	var add := await _place(AddHex, Vector2i(11, 10), 1)
	assert_eq(_editor._placed_connection_edge(lit), 0,
			"the literal's output edge feeds the adjacent Add")
	assert_eq(_editor._placed_connection_edge(add), 2,
			"the Add's rotated SW input is fed by the adjacent literal")


# An isolated hex with no neighbours forms no connection.
func test_isolated_hex_has_no_connection() -> void:
	var lit := await _place(IntLiteralHex, Vector2i(20, 20))
	assert_eq(_editor._placed_connection_edge(lit), -1,
			"a hex with no neighbours reports no edge connection")


# An edge-to-edge placement pops the neighbour it bonded to (not just the
# freshly dropped hex, which is popped at the drop site).
func test_placement_fx_pops_the_neighbour() -> void:
	var lit := await _place(IntLiteralHex, Vector2i(10, 10))
	var add := await _place(AddHex, Vector2i(11, 10), 1)
	# Fire as if `add` was just dropped against `lit` on its SW input (edge 2).
	_editor._fire_placement_connect_fx(add, 2)
	assert_almost_eq(lit.scale.x, POP_SCALE, 0.001,
			"the bonded neighbour pops on an edge-to-edge placement")


# A wire connecting two hexes pops BOTH endpoints.
func test_wire_connect_pops_both_ends() -> void:
	var lit := await _place(IntLiteralHex, Vector2i(10, 10))
	var add := await _place(AddHex, Vector2i(11, 10), 1)
	var w := HexWire.new()
	w.output_node = lit
	w.output_edge = 0
	w.input_node = add
	w.input_edge = 2
	_editor._fire_wire_connect_fx(w)
	assert_almost_eq(lit.scale.x, POP_SCALE, 0.001, "the output end pops")
	assert_almost_eq(add.scale.x, POP_SCALE, 0.001, "the input end pops")
