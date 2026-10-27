extends GutTest
## Round-trip tests for the hex editor's text emission: build a hex
## graph programmatically, call `to_source` (with the parser as a
## downstream confidence check), and assert the result is what we
## expect.
##
## Each test uses a `MockCanvas` that implements just enough of the
## editor's interface — `get_input_for(node, edge)` — for `_input_source`
## to recurse through.

const HexLevel := preload("res://scenes/gui/hex_editor/hex_level.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const AnchorHex := preload("res://src/classes/hex_nodes/fixtures/anchor_hex.gd")

const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload("res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const MulHex := preload("res://src/classes/hex_nodes/operators/arithmetic/mul_hex.gd")
const ConsHex := preload("res://src/classes/hex_nodes/operators/list/cons_hex.gd")
const ConcatHex := preload("res://src/classes/hex_nodes/operators/list/concat_hex.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")
const IfHex := preload("res://src/classes/hex_nodes/control/if_hex.gd")
const TrueHex := preload("res://src/classes/hex_nodes/literals/booleans/true_hex.gd")
const ComposeHex := preload("res://src/classes/hex_nodes/operators/functional/compose_hex.gd")
const TupleHex := preload("res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd")
const ListLiteralHex := preload("res://src/classes/hex_nodes/literals/list/list_literal_hex.gd")


class MockCanvas:
	extends RefCounted
	var wires: Array = []

	func get_input_for(node, edge: int):
		for w in wires:
			if w.input_node == node and w.input_edge == edge:
				return w.output_node
		# Adjacency fallback to mirror the editor's behavior — irrelevant
		# in these tests since no two hexes share axials, but worth
		# matching so semantics line up if a test ever uses adjacency.
		return null


func _level_with_canvas() -> Dictionary:
	return {"level": HexLevel.new(), "canvas": MockCanvas.new()}


# Wire `from_node`'s output edge `from_edge` to `to_node`'s input edge
# `to_edge`. Returns the constructed HexWire.
func _wire(canvas, level, from_node, from_edge: int, to_node, to_edge: int) -> HexWire:
	var w := HexWire.new()
	w.output_node = from_node
	w.output_edge = from_edge
	w.input_node = to_node
	w.input_edge = to_edge
	w.is_finalized = true
	level.wires.append(w)
	canvas.wires.append(w)
	return w


# Attach the hex to a level (the editor normally does this through
# `_commit_blueprint`). We instantiate via `script.new()` and skip
# `add_child` since the test doesn't need Godot rendering.
func _attach(level, hex):
	hex.level = level
	level.hexes.append(hex)
	return hex


# ── Tests ──────────────────────────────────────────────────────────────────

func test_int_plus_one() -> void:
	# Expression:  5 + 1
	#   Int(5) → NW of Add; Int(1) → SW of Add.
	var ctx := _level_with_canvas()
	var lit5 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit5.value = 5
	var lit1 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit1.value = 1
	var add = _attach(ctx.level, HexNode.from_script(AddHex))
	_wire(ctx.canvas, ctx.level, lit5, 0, add, 4)
	_wire(ctx.canvas, ctx.level, lit1, 0, add, 2)
	assert_eq(add.to_source(ctx.canvas), "(5 + 1)")


func test_arithmetic_grouping() -> void:
	# Expression:  (5 + 1) * 2
	var ctx := _level_with_canvas()
	var lit5 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit5.value = 5
	var lit1 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit1.value = 1
	var lit2 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit2.value = 2
	var add = _attach(ctx.level, HexNode.from_script(AddHex))
	var mul = _attach(ctx.level, HexNode.from_script(MulHex))
	_wire(ctx.canvas, ctx.level, lit5, 0, add, 4)
	_wire(ctx.canvas, ctx.level, lit1, 0, add, 2)
	_wire(ctx.canvas, ctx.level, add, 0, mul, 4)
	_wire(ctx.canvas, ctx.level, lit2, 0, mul, 2)
	assert_eq(mul.to_source(ctx.canvas), "((5 + 1) * 2)")


func test_cons_concat_argument_order() -> void:
	# The on-canvas role labels (head NW / tail SW, front/back) must
	# agree with emission order: NW is always the left operand.
	var ctx := _level_with_canvas()
	var lit1 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit1.value = 1
	var lit2 = _attach(ctx.level, HexNode.from_script(IntLiteralHex))
	lit2.value = 2
	var cons = _attach(ctx.level, HexNode.from_script(ConsHex))
	_wire(ctx.canvas, ctx.level, lit1, 0, cons, 4)  # head
	_wire(ctx.canvas, ctx.level, lit2, 0, cons, 2)  # tail
	assert_eq(cons.to_source(ctx.canvas), "(1 : 2)",
			"NW = head, SW = tail")

	var ctx2 := _level_with_canvas()
	var lit3 = _attach(ctx2.level, HexNode.from_script(IntLiteralHex))
	lit3.value = 3
	var lit4 = _attach(ctx2.level, HexNode.from_script(IntLiteralHex))
	lit4.value = 4
	var concat = _attach(ctx2.level, HexNode.from_script(ConcatHex))
	_wire(ctx2.canvas, ctx2.level, lit3, 0, concat, 4)  # front
	_wire(ctx2.canvas, ctx2.level, lit4, 0, concat, 2)  # back
	assert_eq(concat.to_source(ctx2.canvas), "(3 ++ 4)",
			"NW = front, SW = back")


func test_let_x_eq_5_in_x_plus_1() -> void:
	# Expression:  let red = 5 in red + 1
	# Outer level: Let (name=red), with Int(5) wired to NW value input.
	# Inner level: IdentRef(red) + Int(1) wired to Add, Add's output
	#   wired to anchor's return slot (E = 0).
	var canvas := MockCanvas.new()

	var outer_level := HexLevel.new()
	var let_hex = HexNode.from_script(LetHex)
	let_hex.palette_index = 0  # "red"
	let_hex.level = outer_level
	outer_level.hexes.append(let_hex)

	var lit5 := HexNode.from_script(IntLiteralHex)
	lit5.value = 5
	lit5.level = outer_level
	outer_level.hexes.append(lit5)

	# Wire Int(5) → NW of Let (logical edge 4 = value input).
	_wire(canvas, outer_level, lit5, 0, let_hex, 4)

	# Build the inner level + anchor exactly the way the editor does it.
	var inner_level := HexLevel.new(let_hex)
	var anchor = let_hex.create_inner_anchor()
	anchor.level = inner_level
	inner_level.hexes.append(anchor)
	inner_level.anchor = anchor
	let_hex.inner_level = inner_level

	var ident := HexNode.from_script(IdentRefHex)
	ident.palette_index = 0  # "red"
	ident.level = inner_level
	inner_level.hexes.append(ident)

	var lit1 := HexNode.from_script(IntLiteralHex)
	lit1.value = 1
	lit1.level = inner_level
	inner_level.hexes.append(lit1)

	var add := HexNode.from_script(AddHex)
	add.level = inner_level
	inner_level.hexes.append(add)

	_wire(canvas, inner_level, ident, 0, add, 4)
	_wire(canvas, inner_level, lit1, 0, add, 2)
	_wire(canvas, inner_level, add, 0, anchor, 0)

	assert_eq(let_hex.to_source(canvas), "(let red = 5 in (red + 1))")


func test_if_bodies_live_in_inner_level() -> void:
	# Expression:  if true then -12 else 12
	# Outer level: If, with True wired to NW cond input.
	# Inner level: Int(-12) → anchor's then slot (NW = 4),
	#              Int(12)  → anchor's else slot (SW = 2).
	var canvas := MockCanvas.new()

	var outer_level := HexLevel.new()
	var if_hex = HexNode.from_script(IfHex)
	if_hex.level = outer_level
	outer_level.hexes.append(if_hex)

	var cond := HexNode.from_script(TrueHex)
	cond.level = outer_level
	outer_level.hexes.append(cond)
	_wire(canvas, outer_level, cond, 0, if_hex, 4)

	# Unwired bodies emit holes.
	var inner_level := HexLevel.new(if_hex)
	var anchor = if_hex.create_inner_anchor()
	anchor.level = inner_level
	inner_level.hexes.append(anchor)
	inner_level.anchor = anchor
	if_hex.inner_level = inner_level
	assert_eq(if_hex.to_source(canvas), "(if true then _HOLE_ else _HOLE_)")

	var then_lit := HexNode.from_script(IntLiteralHex)
	then_lit.value = -12
	then_lit.level = inner_level
	inner_level.hexes.append(then_lit)

	var else_lit := HexNode.from_script(IntLiteralHex)
	else_lit.value = 12
	else_lit.level = inner_level
	inner_level.hexes.append(else_lit)

	_wire(canvas, inner_level, then_lit, 0, anchor, 4)
	_wire(canvas, inner_level, else_lit, 0, anchor, 2)

	assert_eq(if_hex.to_source(canvas), "(if true then -12 else 12)")


func test_compose_takes_wired_functions() -> void:
	# Expression:  (red . blue)  — both functions arrive by wire, so
	# any expression (not just a palette pick) can be composed.
	var ctx := _level_with_canvas()
	var f = _attach(ctx.level, HexNode.from_script(IdentRefHex))
	f.palette_index = 0
	var g = _attach(ctx.level, HexNode.from_script(IdentRefHex))
	g.palette_index = 1
	var compose = _attach(ctx.level, HexNode.from_script(ComposeHex))
	_wire(ctx.canvas, ctx.level, f, 0, compose, 4)  # outer f
	_wire(ctx.canvas, ctx.level, g, 0, compose, 2)  # inner g
	assert_eq(compose.to_source(ctx.canvas), "(red . green)",
			"NW = f, SW = g around the dot")


# Build an inner level + anchor for `hex` exactly the way the editor
# does it (create_inner_anchor at (0,0)). Returns the anchor.
func _grow_inner_level(hex):
	var inner_level := HexLevel.new(hex)
	var anchor = hex.create_inner_anchor()
	anchor.level = inner_level
	inner_level.hexes.append(anchor)
	inner_level.anchor = anchor
	hex.inner_level = inner_level
	return anchor


func _int(level, value: int):
	var lit = _attach(level, HexNode.from_script(IntLiteralHex))
	lit.value = value
	return lit


func test_tuple_elements_live_in_inner_level() -> void:
	# Expression:  (1, 2) — elements wire into the TupleAnchor's
	# ordinal slots, not the outer face.
	var ctx := _level_with_canvas()
	var tup = _attach(ctx.level, HexNode.from_script(TupleHex))

	# No inner level yet: holes for every arity slot.
	assert_eq(tup.to_source(ctx.canvas), "(_HOLE_, _HOLE_)")

	var anchor = _grow_inner_level(tup)
	_wire(ctx.canvas, tup.inner_level, _int(tup.inner_level, 1), 0, anchor, 5)  # 1st slot (NE)
	assert_eq(tup.to_source(ctx.canvas), "(1, _HOLE_)",
			"unwired element slots stay holes — tuples have fixed shape")
	_wire(ctx.canvas, tup.inner_level, _int(tup.inner_level, 2), 0, anchor, 0)  # 2nd slot (E)
	assert_eq(tup.to_source(ctx.canvas), "(1, 2)")


func test_tuple_arity_3_uses_canonical_slot_order() -> void:
	# Wire out of order; emission follows the anchor's canonical
	# clockwise-from-NE edge order (NE → E → SE), not wiring order.
	var ctx := _level_with_canvas()
	var tup = _attach(ctx.level, HexNode.from_script(TupleHex))
	tup.arity = 3
	var anchor = _grow_inner_level(tup)
	_wire(ctx.canvas, tup.inner_level, _int(tup.inner_level, 30), 0, anchor, 1)  # 3rd (SE)
	_wire(ctx.canvas, tup.inner_level, _int(tup.inner_level, 10), 0, anchor, 5)  # 1st (NE)
	_wire(ctx.canvas, tup.inner_level, _int(tup.inner_level, 20), 0, anchor, 0)  # 2nd (E)
	assert_eq(tup.to_source(ctx.canvas), "(10, 20, 30)")


func test_empty_list_emits_brackets() -> void:
	var ctx := _level_with_canvas()
	var lst = _attach(ctx.level, HexNode.from_script(ListLiteralHex))
	assert_eq(lst.to_source(ctx.canvas), "[]", "no inner level = empty list")
	_grow_inner_level(lst)
	assert_eq(lst.to_source(ctx.canvas), "[]", "nothing wired = empty list")


func test_list_sliding_window_skips_unwired_slots() -> void:
	# Slots 1st, 3rd, 5th wired → three elements, canonical order.
	var ctx := _level_with_canvas()
	var lst = _attach(ctx.level, HexNode.from_script(ListLiteralHex))
	var anchor = _grow_inner_level(lst)
	_wire(ctx.canvas, lst.inner_level, _int(lst.inner_level, 3), 0, anchor, 1)  # 3rd (SE)
	_wire(ctx.canvas, lst.inner_level, _int(lst.inner_level, 1), 0, anchor, 5)  # 1st (NE)
	_wire(ctx.canvas, lst.inner_level, _int(lst.inner_level, 5), 0, anchor, 3)  # 5th (W)
	assert_eq(lst.to_source(ctx.canvas), "[1, 3, 5]")


func test_list_continuation_chain_flattens() -> void:
	# A full first block plus two elements on the continuation anchor
	# emit one flat literal.
	var ctx := _level_with_canvas()
	var lst = _attach(ctx.level, HexNode.from_script(ListLiteralHex))
	var anchor = _grow_inner_level(lst)
	var edges: Array = anchor.input_edges.duplicate()
	for i in edges.size():
		_wire(ctx.canvas, lst.inner_level, _int(lst.inner_level, i + 1), 0, anchor, edges[i])
	assert_eq(lst.to_source(ctx.canvas), "[1, 2, 3, 4, 5, 6]")

	var cont = _grow_inner_level(anchor)
	var cont_edges: Array = cont.input_edges.duplicate()
	_wire(ctx.canvas, anchor.inner_level, _int(anchor.inner_level, 7), 0, cont, cont_edges[0])  # 1st
	_wire(ctx.canvas, anchor.inner_level, _int(anchor.inner_level, 8), 0, cont, cont_edges[1])  # 2nd
	assert_eq(lst.to_source(ctx.canvas), "[1, 2, 3, 4, 5, 6, 7, 8]")


func test_list_anchor_descend_gate() -> void:
	# can_descend: false until all six slots are wired; true once a
	# continuation exists, even if a slot is later unwired.
	var ctx := _level_with_canvas()
	var lst = _attach(ctx.level, HexNode.from_script(ListLiteralHex))
	var anchor = _grow_inner_level(lst)
	assert_true(lst.can_descend(ctx.canvas), "default can_descend stays open")
	assert_false(anchor.can_descend(ctx.canvas), "empty block can't grow")

	var edges: Array = anchor.input_edges.duplicate()
	var wires: Array = []
	for i in edges.size():
		wires.append(_wire(ctx.canvas, lst.inner_level,
				_int(lst.inner_level, i + 1), 0, anchor, edges[i]))
		if i < edges.size() - 1:
			assert_false(anchor.can_descend(ctx.canvas),
					"%d/%d wired isn't full" % [i + 1, edges.size()])
	assert_true(anchor.can_descend(ctx.canvas), "6/6 wired opens the gate")

	_grow_inner_level(anchor)
	ctx.canvas.wires.erase(wires[0])
	lst.inner_level.wires.erase(wires[0])
	assert_true(anchor.can_descend(ctx.canvas),
			"existing continuation stays reachable after unwiring")
