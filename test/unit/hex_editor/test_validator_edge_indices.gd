extends GutTest
## Validator regression: a wired input must read as wired
## regardless of whether the hex has been rotated. The bug under
## test was `get_input_for` returning a wire's null output_node
## (open wire), short-circuiting the adjacency fallback and
## making a perfectly wired neighbor look unwired.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const IntLiteralHex := preload(
		"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload(
		"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")

var _editor: Node


func before_each() -> void:
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func _place(script: Script, axial: Vector2i) -> HexNode:
	var h: HexNode = HexNode.from_script(script)
	h.level = _editor._level_stack[0]
	_editor._level_stack[0].hexes.append(h)
	add_child_autofree(h)
	h.set_axial(axial)
	await get_tree().process_frame
	return h


func test_wired_input_reads_as_wired() -> void:
	# Wire IntLiteral → AddHex.NW (logical edge 4). Validator should
	# treat the input as wired.
	var lit := await _place(IntLiteralHex, Vector2i(0, -1))
	var add := await _place(AddHex, Vector2i(0, 0))
	var w := HexWire.new()
	w.output_node = lit
	w.output_edge = 0
	w.input_node = add
	w.input_edge = 4
	_editor._level_stack[0].wires.append(w)
	var got: HexNode = _editor.get_input_for(add, 4)
	assert_eq(got, lit,
			"get_input_for should return the upstream node for a real wire")


func test_open_wire_doesnt_block_real_explicit_wire() -> void:
	# Two wires terminate at the same input slot — one is "open"
	# (anchored at the slot but released in empty space, so
	# output_node stays null) and one is a real connection to an
	# upstream IntLiteral. `get_input_for` used to return the FIRST
	# matching wire's `output_node` unconditionally — handing back
	# `null` from the open wire and never finding the real one.
	# After the fix, open-side wires are skipped so the real wire
	# wins.
	var lit := await _place(IntLiteralHex, Vector2i(0, -1))
	var add := await _place(AddHex, Vector2i(0, 0))
	# Orphan wire first in the list so the fix has to skip it.
	var orphan := HexWire.new()
	orphan.input_node = add
	orphan.input_edge = 4
	_editor._level_stack[0].wires.append(orphan)
	# Real wire second.
	var real := HexWire.new()
	real.output_node = lit
	real.output_edge = 0
	real.input_node = add
	real.input_edge = 4
	_editor._level_stack[0].wires.append(real)
	var got: HexNode = _editor.get_input_for(add, 4)
	assert_eq(got, lit,
			"Real wire wins; orphan with null output_node is skipped")


func test_validate_passes_on_wired_input_after_rotation() -> void:
	# Wire IntLit → AddHex's NW input (logical 4). Rotate AddHex.
	# The wire's logical edge stays at 4 across rotation; validator
	# should still report `ok`.
	var lit := await _place(IntLiteralHex, Vector2i(0, -1))
	var add := await _place(AddHex, Vector2i(0, 0))
	var w := HexWire.new()
	w.output_node = lit
	w.output_edge = 0
	w.input_node = add
	w.input_edge = 4
	_editor._level_stack[0].wires.append(w)
	# Wire the SW input too so validate doesn't trip on the other
	# missing operand.
	var lit2 := await _place(IntLiteralHex, Vector2i(-1, 1))  # SW neighbor
	var w2 := HexWire.new()
	w2.output_node = lit2
	w2.output_edge = 0
	w2.input_node = add
	w2.input_edge = 2
	_editor._level_stack[0].wires.append(w2)

	add.set_rotation_index(1)
	await get_tree().process_frame
	var v: Dictionary = add.validate(_editor)
	assert_eq(v.get("status", ""), "ok",
			"Wired AddHex should remain valid after rotation: %s" % str(v))
