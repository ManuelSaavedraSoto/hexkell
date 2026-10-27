extends GutTest
## Single-slot fixtures: the DoHex main-expression slot and the
## inner-level AnchorHex return slot expose all six edges as one
## logical input — wire from any side, one wire total. These tests
## cover the any-side emission, the wired_input_edges helper, and the
## unwired / multi-feed validation errors. The editor-side group
## replace lives in hex_editor.gd and is exercised manually.

const HexLevel := preload("res://scenes/gui/hex_editor/hex_level.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
const AnchorHex := preload("res://src/classes/hex_nodes/fixtures/anchor_hex.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload("res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")


class MockCanvas:
	extends RefCounted
	var wires: Array = []

	func get_input_for(node, edge: int):
		for w in wires:
			if w.input_node == node and w.input_edge == edge:
				return w.output_node
		return null


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


func _attach(level, hex):
	hex.level = level
	level.hexes.append(hex)
	return hex


func _int(level, value: int):
	var lit = _attach(level, HexNode.from_script(IntLiteralHex))
	lit.value = value
	return lit


# Build the inner level + anchor for `hex` the way the editor does it.
func _grow_inner_level(hex):
	var inner := HexLevel.new(hex)
	var anchor = hex.create_inner_anchor()
	anchor.level = inner
	inner.hexes.append(anchor)
	inner.anchor = anchor
	hex.inner_level = inner
	return anchor


# ── wired_input_edges helper ────────────────────────────────────────────────

func test_wired_input_edges_reports_canonical_order() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var anchor = _attach(level, HexNode.from_script(AnchorHex))
	assert_eq(anchor.wired_input_edges(canvas), [], "nothing wired = empty")
	_wire(canvas, level, _int(level, 1), 0, anchor, 3)
	assert_eq(anchor.wired_input_edges(canvas), [3], "one side wired")
	_wire(canvas, level, _int(level, 2), 0, anchor, 1)
	assert_eq(anchor.wired_input_edges(canvas), [1, 3],
			"reported in canonical edge order, not wiring order")


# ── AnchorHex any-side emission ─────────────────────────────────────────────

func test_anchor_reads_body_from_any_side() -> void:
	# Wiring the body into a non-E side emits the same source as edge 0.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var anchor = _attach(level, HexNode.from_script(AnchorHex))
	_wire(canvas, level, _int(level, 7), 0, anchor, 4)  # NW, not E
	assert_eq(anchor.to_source(canvas), "7",
			"the return slot reads whichever side carries the body")


func test_let_body_wired_to_west_side_round_trips() -> void:
	# (let red = 5 in (red + 1)) with the body wired into anchor edge 3
	# (West) instead of the historical edge 0.
	var canvas := MockCanvas.new()
	var outer := HexLevel.new()
	var let_hex = _attach(outer, HexNode.from_script(LetHex))
	let_hex.palette_index = 0  # red
	_wire(canvas, outer, _int(outer, 5), 0, let_hex, 4)

	var anchor = _grow_inner_level(let_hex)
	var ident = _attach(let_hex.inner_level, HexNode.from_script(IdentRefHex))
	ident.palette_index = 0  # red
	var add = _attach(let_hex.inner_level, HexNode.from_script(AddHex))
	_wire(canvas, let_hex.inner_level, ident, 0, add, 4)
	_wire(canvas, let_hex.inner_level, _int(let_hex.inner_level, 1), 0, add, 2)
	_wire(canvas, let_hex.inner_level, add, 0, anchor, 3)  # West return

	assert_eq(let_hex.to_source(canvas), "(let red = 5 in (red + 1))",
			"the parent reads the anchor regardless of which side the body uses")


# ── AnchorHex validation ────────────────────────────────────────────────────

func test_anchor_unwired_return_errors() -> void:
	var canvas := MockCanvas.new()
	var anchor = _attach(HexLevel.new(), HexNode.from_script(AnchorHex))
	var v: Dictionary = anchor.validate(canvas)
	assert_eq(v.get("status", ""), "error")
	assert_string_contains(String(v.get("message", "")), "return slot",
			"an unwired anchor should still name the missing return")


func test_anchor_multi_feed_errors() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var anchor = _attach(level, HexNode.from_script(AnchorHex))
	_wire(canvas, level, _int(level, 1), 0, anchor, 0)
	_wire(canvas, level, _int(level, 2), 0, anchor, 3)
	var v: Dictionary = anchor.validate(canvas)
	assert_eq(v.get("status", ""), "error")
	assert_string_contains(String(v.get("message", "")), "takes one result",
			"two sides feeding the anchor should be flagged")


func test_anchor_single_feed_validates() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var anchor = _attach(level, HexNode.from_script(AnchorHex))
	_wire(canvas, level, _int(level, 1), 0, anchor, 2)
	assert_eq(anchor.validate(canvas).get("status", ""), "ok",
			"exactly one wired side is valid")


# ── DoHex validation ────────────────────────────────────────────────────────

func test_do_unwired_keeps_existing_message() -> void:
	var canvas := MockCanvas.new()
	var do_hex = _attach(HexLevel.new(), HexNode.from_script(DoHex))
	var v: Dictionary = do_hex.validate(canvas)
	assert_eq(v.get("status", ""), "error")
	assert_eq(String(v.get("message", "")), "no main expression wired to the Do hex")


func test_do_multi_feed_errors() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var do_hex = _attach(level, HexNode.from_script(DoHex))
	_wire(canvas, level, _int(level, 1), 0, do_hex, 0)
	_wire(canvas, level, _int(level, 2), 0, do_hex, 3)
	var v: Dictionary = do_hex.validate(canvas)
	assert_eq(v.get("status", ""), "error")
	assert_string_contains(String(v.get("message", "")), "takes one main expression",
			"two sides feeding the Do hex should be flagged")


func test_do_reads_from_any_side() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var do_hex = _attach(level, HexNode.from_script(DoHex))
	_wire(canvas, level, _int(level, 9), 0, do_hex, 5)  # NE only
	assert_eq(do_hex.to_source(canvas), "9")
	assert_eq(do_hex.validate(canvas).get("status", ""), "ok")


# ── exclusive_input_group flag wiring ───────────────────────────────────────

func test_single_slot_fixtures_declare_the_group() -> void:
	assert_true(HexNode.from_script(DoHex).exclusive_input_group,
			"Do hex is a single-wire group")
	assert_true(HexNode.from_script(AnchorHex).exclusive_input_group,
			"anchor return slot is a single-wire group")
	assert_false(HexNode.from_script(AddHex).exclusive_input_group,
			"ordinary operators keep independent input slots")
