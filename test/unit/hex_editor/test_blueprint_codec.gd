extends GutTest
## Round-trip tests for the blueprint serializer (codec + loader).
##
## Strategy: build a hex graph the same way `test_text_emission.gd`
## does, serialize → encode → decode → instantiate, then assert that
## the rebuilt graph emits the same source text. Covers the JSON
## payload, the gzip+base64 string wrapper, fixture (do/anchor)
## binding, inner-level descent, and the locked-hex policy.

const HexLevel := preload("res://scenes/gui/hex_editor/hex_level.gd")
const HexMath := preload("res://src/statics/hex_math.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
const AnchorHex := preload("res://src/classes/hex_nodes/fixtures/anchor_hex.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload("res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const MulHex := preload("res://src/classes/hex_nodes/operators/arithmetic/mul_hex.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")
const LambdaHex := preload("res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd")
const IfHex := preload("res://src/classes/hex_nodes/control/if_hex.gd")
const TrueHex := preload("res://src/classes/hex_nodes/literals/booleans/true_hex.gd")
const TupleHex := preload("res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd")
const ListLiteralHex := preload("res://src/classes/hex_nodes/literals/list/list_literal_hex.gd")


class MockCanvas:
	extends RefCounted
	var wires: Array = []

	func get_input_for(node, edge: int):
		for w in wires:
			if w.input_node == node and w.input_edge == edge:
				return w.output_node
		return null


func before_all() -> void:
	# Register every script the codec / loader needs to resolve. In
	# the live editor `_seed_blueprint_registry` does this; tests skip
	# the editor scene so we register the scripts we use directly.
	BlueprintLoader.register_scripts([
		DoHex, AnchorHex, IntLiteralHex, AddHex, MulHex,
		IdentRefHex, LetHex, LambdaHex, IfHex, TrueHex,
		TupleHex, ListLiteralHex,
	])


func _attach(level, hex, axial := Vector2i.ZERO) -> HexNode:
	hex.level = level
	hex.axial = axial
	level.hexes.append(hex)
	return hex


func _wire(canvas, level, from_node, from_edge: int, to_node, to_edge: int) -> HexWire:
	var w := HexWire.new()
	w.output_node = from_node
	w.output_edge = from_edge
	w.input_node = to_node
	w.input_edge = to_edge
	w.anchor_node = from_node
	w.anchor_edge = from_edge
	w.anchor_is_output = true
	w.is_finalized = true
	level.wires.append(w)
	canvas.wires.append(w)
	return w


# Build the equivalent canvas + wires for a list of `built` hex
# entries (loader output), so a re-emitted graph can call to_source
# through MockCanvas.get_input_for. Recursive for inner levels.
func _attach_built(built: Dictionary, canvas, level) -> Dictionary:
	# Move hexes into the level + axial they were assigned.
	var nodes_by_id: Dictionary = {}
	for entry in built["hexes"]:
		var node: HexNode = entry.node
		node.level = level
		node.axial = entry.axial
		level.hexes.append(node)
		nodes_by_id[int(entry.id)] = node
	for w in built["wires"]:
		level.wires.append(w)
		canvas.wires.append(w)
	for inner in built.get("inner", []):
		var parent: HexNode = inner.parent
		var inner_level := HexLevel.new(parent)
		var anchor: HexNode = parent.create_inner_anchor()
		anchor.level = inner_level
		anchor.axial = Vector2i.ZERO
		inner_level.hexes.append(anchor)
		inner_level.anchor = anchor
		parent.inner_level = inner_level
		var inner_built = BlueprintLoader.instantiate_inner(inner.payload, anchor)
		_attach_built(inner_built, canvas, inner_level)
	return {"nodes_by_id": nodes_by_id}


# ── Tests ──────────────────────────────────────────────────────────────────

func test_int_literal_state_round_trip() -> void:
	var level := HexLevel.new()
	var lit = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(0, 0))
	lit.value = 42
	var payload := BlueprintCodec.serialize_root(level, MockCanvas.new(), null, "lit")
	# JSON-safe shape: every state value is a primitive.
	assert_eq(payload["hexes"][0]["state"]["value"], 42)
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO)
	var restored: HexNode = built["hexes"][0].node
	assert_eq(restored.value, 42, "restored int literal should carry its value")


func test_axial_offset_applied_on_stamp() -> void:
	# Capture at (1,0), stamp at anchor (5,7) — restored axial should
	# be the sum (offset is `anchor - origin` where origin = (0,0)).
	var level := HexLevel.new()
	_attach(level, HexNode.from_script(IntLiteralHex), Vector2i(1, 0))
	var payload := BlueprintCodec.serialize_root(
		level, MockCanvas.new(), null, "test", "", "", Vector2i.ZERO
	)
	var built := BlueprintLoader.instantiate(payload, Vector2i(5, 7))
	assert_eq(built["hexes"][0].axial, Vector2i(6, 7))


func test_arithmetic_graph_round_trip_emits_same_source() -> void:
	# Build (5 + 1) * 2 with a DoHex as the root fixture.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var do_hex = _attach(level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var lit5 = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(2, 0))
	lit5.value = 5
	var lit1 = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(3, 1))
	lit1.value = 1
	var lit2 = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(5, 0))
	lit2.value = 2
	var add = _attach(level, HexNode.from_script(AddHex), Vector2i(3, 0))
	var mul = _attach(level, HexNode.from_script(MulHex), Vector2i(4, 0))
	_wire(canvas, level, lit5, 0, add, 4)
	_wire(canvas, level, lit1, 0, add, 2)
	_wire(canvas, level, add, 0, mul, 4)
	_wire(canvas, level, lit2, 0, mul, 2)
	# The Do hex's main expression is whatever feeds it — wire mul to
	# it so the round-trip touches the fixture binding too.
	_wire(canvas, level, mul, 0, do_hex, 3)
	var expected := do_hex.to_source(canvas)
	assert_eq(expected, "((5 + 1) * 2)")
	# Serialize → encode → decode → instantiate.
	var payload := BlueprintCodec.serialize_root(level, canvas, do_hex, "(5+1)*2")
	var s: String = BlueprintCodec.encode(payload)
	assert_true(s.begins_with("hxk1:"), "encoded form must start with hxk1:")
	var decoded = BlueprintCodec.decode(s)
	assert_typeof(decoded, TYPE_DICTIONARY)
	# Restore against a fresh canvas + fresh DoHex (as the editor would
	# for a stamp on a new tab) and confirm the source emission matches.
	var fresh_canvas := MockCanvas.new()
	var fresh_level := HexLevel.new()
	var fresh_do = _attach(fresh_level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO, fresh_do)
	_attach_built(built, fresh_canvas, fresh_level)
	assert_eq(fresh_do.to_source(fresh_canvas), expected,
			"restored graph must emit the same source as the captured one")


func test_let_with_inner_level_round_trip() -> void:
	# Capture: (let red = 5 in (red + 1))
	var canvas := MockCanvas.new()
	var outer := HexLevel.new()
	var do_hex = _attach(outer, HexNode.from_script(DoHex), Vector2i(0, 0))
	var lit5 = _attach(outer, HexNode.from_script(IntLiteralHex), Vector2i(1, 0))
	lit5.value = 5
	var let_hex = _attach(outer, HexNode.from_script(LetHex), Vector2i(2, 0))
	let_hex.palette_index = 0  # red
	_wire(canvas, outer, lit5, 0, let_hex, 4)
	_wire(canvas, outer, let_hex, 0, do_hex, 3)
	# Build the inner level the same way the editor would.
	var inner := HexLevel.new(let_hex)
	var anchor: HexNode = let_hex.create_inner_anchor()
	anchor.level = inner
	anchor.axial = Vector2i.ZERO
	inner.hexes.append(anchor)
	inner.anchor = anchor
	let_hex.inner_level = inner
	var ident = _attach(inner, HexNode.from_script(IdentRefHex), Vector2i(1, 0))
	ident.palette_index = 0
	var lit1 = _attach(inner, HexNode.from_script(IntLiteralHex), Vector2i(1, 1))
	lit1.value = 1
	var add = _attach(inner, HexNode.from_script(AddHex), Vector2i(2, 0))
	_wire(canvas, inner, ident, 0, add, 4)
	_wire(canvas, inner, lit1, 0, add, 2)
	_wire(canvas, inner, add, 0, anchor, 0)
	var expected := do_hex.to_source(canvas)
	assert_eq(expected, "(let red = 5 in (red + 1))")
	# Round-trip through the string form too.
	var payload := BlueprintCodec.serialize_root(outer, canvas, do_hex, "let")
	var s: String = BlueprintCodec.encode(payload)
	var decoded = BlueprintCodec.decode(s)
	var fresh_canvas := MockCanvas.new()
	var fresh_level := HexLevel.new()
	var fresh_do = _attach(fresh_level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO, fresh_do)
	_attach_built(built, fresh_canvas, fresh_level)
	assert_eq(fresh_do.to_source(fresh_canvas), expected,
			"let with inner body must round-trip exactly")


func test_if_with_inner_level_round_trip() -> void:
	# Capture: (if true then -12 else 12) — bodies live one level down,
	# wired into the IfAnchor's then (NW=4) / else (SW=2) slots.
	var canvas := MockCanvas.new()
	var outer := HexLevel.new()
	var do_hex = _attach(outer, HexNode.from_script(DoHex), Vector2i(0, 0))
	var cond = _attach(outer, HexNode.from_script(TrueHex), Vector2i(1, 0))
	var if_hex = _attach(outer, HexNode.from_script(IfHex), Vector2i(2, 0))
	_wire(canvas, outer, cond, 0, if_hex, 4)
	_wire(canvas, outer, if_hex, 0, do_hex, 3)
	var inner := HexLevel.new(if_hex)
	var anchor: HexNode = if_hex.create_inner_anchor()
	anchor.level = inner
	anchor.axial = Vector2i.ZERO
	inner.hexes.append(anchor)
	inner.anchor = anchor
	if_hex.inner_level = inner
	var then_lit = _attach(inner, HexNode.from_script(IntLiteralHex), Vector2i(1, 0))
	then_lit.value = -12
	var else_lit = _attach(inner, HexNode.from_script(IntLiteralHex), Vector2i(1, 1))
	else_lit.value = 12
	_wire(canvas, inner, then_lit, 0, anchor, 4)
	_wire(canvas, inner, else_lit, 0, anchor, 2)
	var expected := do_hex.to_source(canvas)
	assert_eq(expected, "(if true then -12 else 12)")
	var payload := BlueprintCodec.serialize_root(outer, canvas, do_hex, "if")
	var s: String = BlueprintCodec.encode(payload)
	var decoded = BlueprintCodec.decode(s)
	var fresh_canvas := MockCanvas.new()
	var fresh_level := HexLevel.new()
	var fresh_do = _attach(fresh_level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO, fresh_do)
	_attach_built(built, fresh_canvas, fresh_level)
	assert_eq(fresh_do.to_source(fresh_canvas), expected,
			"if with inner bodies must round-trip exactly")


func test_chapter_5_if_example_blueprint_loads() -> void:
	# Guards the hand-migrated example in static_data.json: it must
	# decode, instantiate with its inner level, and emit the if form.
	var f := FileAccess.open("res://data/static_data.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var bp: String = data["chapters"]["chapter_5_conditionals"]["examples"][0]["blueprint"]
	var decoded = BlueprintCodec.decode(bp)
	assert_typeof(decoded, TYPE_DICTIONARY)
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO)
	assert_eq((built["warnings"] as Array).size(), 0,
			"example blueprint should load without warnings")
	_attach_built(built, canvas, level)
	var if_hex: HexNode = null
	for h in level.hexes:
		if (h.get_script() as Script).resource_path.ends_with("if_hex.gd"):
			if_hex = h
	assert_not_null(if_hex, "example blueprint should contain an if hex")
	assert_eq(if_hex.to_source(canvas), "(if (false || true) then 1 else 0)")


# Build an inner level + anchor for `hex` the way the editor does it.
# Returns the anchor.
func _grow_inner_level(hex: HexNode) -> HexNode:
	var inner := HexLevel.new(hex)
	var anchor: HexNode = hex.create_inner_anchor()
	anchor.level = inner
	anchor.axial = Vector2i.ZERO
	inner.hexes.append(anchor)
	inner.anchor = anchor
	hex.inner_level = inner
	return anchor


func test_tuple_with_inner_level_round_trip() -> void:
	# Capture: (1, 2) — elements live one level down in the TupleAnchor.
	var canvas := MockCanvas.new()
	var outer := HexLevel.new()
	var do_hex = _attach(outer, HexNode.from_script(DoHex), Vector2i(0, 0))
	var tup = _attach(outer, HexNode.from_script(TupleHex), Vector2i(2, 0))
	_wire(canvas, outer, tup, 0, do_hex, 3)
	var anchor := _grow_inner_level(tup)
	var lit1 = _attach(tup.inner_level, HexNode.from_script(IntLiteralHex), Vector2i(-1, 0))
	lit1.value = 1
	var lit2 = _attach(tup.inner_level, HexNode.from_script(IntLiteralHex), Vector2i(-1, 1))
	lit2.value = 2
	_wire(canvas, tup.inner_level, lit1, 0, anchor, 5)  # 1st slot (NE)
	_wire(canvas, tup.inner_level, lit2, 0, anchor, 0)  # 2nd slot (E)
	var expected := do_hex.to_source(canvas)
	assert_eq(expected, "(1, 2)")
	var payload := BlueprintCodec.serialize_root(outer, canvas, do_hex, "tuple")
	var decoded = BlueprintCodec.decode(BlueprintCodec.encode(payload))
	var fresh_canvas := MockCanvas.new()
	var fresh_level := HexLevel.new()
	var fresh_do = _attach(fresh_level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO, fresh_do)
	_attach_built(built, fresh_canvas, fresh_level)
	assert_eq(fresh_do.to_source(fresh_canvas), expected,
			"tuple with inner elements must round-trip exactly")


func test_list_continuation_round_trip() -> void:
	# Capture: [1, 2, 3, 4, 5, 6, 7, 8] — a full first block (six slots)
	# plus two elements on the ListAnchor's own continuation level.
	# Regression guard for the codec's level-body `inner` key (the
	# fixture isn't in `hexes`, so its chain needs the dedicated path).
	var canvas := MockCanvas.new()
	var outer := HexLevel.new()
	var do_hex = _attach(outer, HexNode.from_script(DoHex), Vector2i(0, 0))
	var lst = _attach(outer, HexNode.from_script(ListLiteralHex), Vector2i(2, 0))
	_wire(canvas, outer, lst, 0, do_hex, 3)
	var anchor := _grow_inner_level(lst)
	var edges: Array = anchor.input_edges.duplicate()
	for i in edges.size():
		var lit = _attach(lst.inner_level,
				HexNode.from_script(IntLiteralHex), Vector2i(-1, i))
		lit.value = i + 1
		_wire(canvas, lst.inner_level, lit, 0, anchor, edges[i])
	var cont := _grow_inner_level(anchor)
	for i in 2:
		var lit = _attach(anchor.inner_level,
				HexNode.from_script(IntLiteralHex), Vector2i(-1, i))
		lit.value = 7 + i
		_wire(canvas, anchor.inner_level, lit, 0, cont, edges[i])
	var expected := do_hex.to_source(canvas)
	assert_eq(expected, "[1, 2, 3, 4, 5, 6, 7, 8]")

	var payload := BlueprintCodec.serialize_root(outer, canvas, do_hex, "list")
	# The list hex's inner level body must carry the anchor's own
	# continuation under a level-body `inner` key.
	var lst_entry: Dictionary = {}
	for entry in payload["hexes"]:
		if String(entry["script"]).ends_with("list_literal_hex.gd"):
			lst_entry = entry
	assert_true(lst_entry.has("inner"), "list hex serializes its inner level")
	assert_true((lst_entry["inner"] as Dictionary).has("inner"),
			"the ListAnchor's continuation rides on the level body")

	var decoded = BlueprintCodec.decode(BlueprintCodec.encode(payload))
	var fresh_canvas := MockCanvas.new()
	var fresh_level := HexLevel.new()
	var fresh_do = _attach(fresh_level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var built := BlueprintLoader.instantiate(decoded, Vector2i.ZERO, fresh_do)
	_attach_built(built, fresh_canvas, fresh_level)
	assert_eq(fresh_do.to_source(fresh_canvas), expected,
			"list continuation chain must round-trip exactly")


func test_subset_capture_preserves_list_continuation() -> void:
	# Copy/paste of a list hex carries the whole chain along.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var lst = _attach(level, HexNode.from_script(ListLiteralHex), Vector2i(0, 0))
	var anchor := _grow_inner_level(lst)
	var edges: Array = anchor.input_edges.duplicate()
	for i in edges.size():
		var lit = _attach(lst.inner_level,
				HexNode.from_script(IntLiteralHex), Vector2i(-1, i))
		lit.value = i + 1
		_wire(canvas, lst.inner_level, lit, 0, anchor, edges[i])
	var cont := _grow_inner_level(anchor)
	var lit7 = _attach(anchor.inner_level,
			HexNode.from_script(IntLiteralHex), Vector2i(-1, 0))
	lit7.value = 7
	_wire(canvas, anchor.inner_level, lit7, 0, cont, edges[0])

	var payload := BlueprintCodec.serialize_subset([lst], canvas, "list-frag")
	var entry: Dictionary = payload["hexes"][0]
	assert_true(entry.has("inner"))
	assert_true((entry["inner"] as Dictionary).has("inner"),
			"subset capture keeps the continuation chain")


func test_lambda_arity_state_round_trip() -> void:
	# Lambda with arity 2 needs `input_edges` rebuilt from arity during
	# restore so the right slots exist on _ready.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var lam = _attach(level, HexNode.from_script(LambdaHex), Vector2i(0, 0))
	lam.arity = 2
	var pals: Array[int] = [0, 1]
	lam.param_palette_indices = pals
	lam.input_edges.assign(HexMath.edges_for_arity(2))
	lam.optional_input_edges.assign(HexMath.edges_for_arity(2))
	var payload := BlueprintCodec.serialize_root(level, canvas, null, "lam")
	var entry: Dictionary = payload["hexes"][0]
	assert_eq(entry["state"]["arity"], 2)
	assert_eq(entry["state"]["param_palette_indices"], [0, 1])
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO)
	var restored = built["hexes"][0].node
	assert_eq(restored.arity, 2)
	assert_eq(restored.param_palette_indices, [0, 1])
	# Input edges should follow arity.
	assert_eq(restored.input_edges.size(), 2,
			"restored lambda should have one input slot per parameter")


func test_decode_rejects_prefix_mismatch() -> void:
	# The prefix gate is the cheap-and-quiet first line of defence —
	# anything not starting with `hxk1:` shouldn't even attempt base64
	# / gzip decoding (those paths push engine errors on garbage,
	# which is ugly to surface to the player).
	assert_eq(BlueprintCodec.decode(""), null)
	assert_eq(BlueprintCodec.decode("not a blueprint"), null)
	assert_eq(BlueprintCodec.decode("hxk2:abc"), null)


func test_decode_rejects_future_schema() -> void:
	var future := {
		"version": BlueprintCodec.SCHEMA_VERSION + 5,
		"hexes": [],
		"wires": [],
	}
	var s: String = BlueprintCodec.encode(future)
	assert_eq(BlueprintCodec.decode(s), null,
			"forward-incompatible schema bumps must be rejected")


func test_locked_paths_detection() -> void:
	var payload := {
		"version": 1,
		"hexes": [
			{
				"id": 0,
				"script": "res://src/classes/hex_nodes/control/match_hex.gd",
				"class": "MatchHex",
				"axial": [0, 0],
				"rotation": 0,
				"state": {},
			},
			{
				"id": 1,
				"script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
				"class": "IntLiteralHex",
				"axial": [1, 0],
				"rotation": 0,
				"state": {"value": 0},
			},
		],
		"wires": [],
	}
	# Pretend `match_hex.gd` is locked but `int_literal_hex.gd` isn't.
	var is_unlocked := func(p: String) -> bool:
		return p != "res://src/classes/hex_nodes/control/match_hex.gd"
	var locked: Array = BlueprintLoader.locked_paths_in(payload, is_unlocked)
	assert_eq(locked.size(), 1)
	assert_eq(String(locked[0]), "res://src/classes/hex_nodes/control/match_hex.gd")


func test_rotate_axial_round_trip() -> void:
	# Six 60° CW rotations should return any axial to itself.
	for a in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, -3), Vector2i(-4, 5)]:
		var r: Vector2i = a
		for i in 6:
			r = HexMath.rotate_axial(r, 1)
		assert_eq(r, a, "Six CW rotations should be the identity")
	# Three rotations of (1, 0) lands at (-1, 0) — the opposite cell.
	assert_eq(HexMath.rotate_axial(Vector2i(1, 0), 3), Vector2i(-1, 0))


func test_instantiate_applies_rotation_to_hex_axials_and_orientation() -> void:
	# A hex at relative (1, 0) rotated 1 step CW should land at the
	# CW neighbor of origin: (0, 1).
	var payload := {
		"version": 1,
		"hexes": [
			{
				"id": 0,
				"script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
				"class": "IntLiteralHex",
				"axial": [1, 0],
				"rotation": 0,
				"state": {"value": 1},
			},
		],
		"wires": [],
	}
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO, null, 1)
	assert_eq(built["hexes"][0].axial, Vector2i(0, 1),
			"Loader should rotate relative axials by the requested step")
	# Each hex's rotation_index also picks up the stamp's k*60° so
	# the visual orientation stays consistent with the rotated layout.
	assert_eq(int(built["hexes"][0].rotation), 1,
			"Loader should add the stamp rotation to each hex's rotation_index")


func test_instantiate_applies_rotation_to_wire_cells() -> void:
	# A wire cell at relative (1, 0) with enter=3 (W) / exit=0 (E)
	# rotated 1 step CW: axial → (0, 1), edges → 4 (NW) and 1 (SE).
	var payload := {
		"version": 1,
		"hexes": [
			{
				"id": 0,
				"script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
				"class": "IntLiteralHex",
				"axial": [0, 0],
				"rotation": 0,
				"state": {},
			},
			{
				"id": 1,
				"script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
				"class": "IntLiteralHex",
				"axial": [2, 0],
				"rotation": 0,
				"state": {},
			},
		],
		"wires": [
			{
				"output": [0, 0],
				"input": [1, 3],
				"cells": [{"axial": [1, 0], "enter": 3, "exit": 0}],
				"open": false,
			},
		],
	}
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO, null, 1)
	var wire = built["wires"][0]
	assert_eq(wire.cells.size(), 1)
	assert_eq(wire.cells[0].axial, Vector2i(0, 1),
			"Cell axial should rotate around the blueprint origin")
	assert_eq(int(wire.cells[0].enter_edge), 4,
			"Cell enter edge should rotate with the blueprint")
	assert_eq(int(wire.cells[0].exit_edge), 1,
			"Cell exit edge should rotate with the blueprint")


func test_serialize_subset_drops_wires_crossing_the_boundary() -> void:
	# Build (1 + 2) — Int(1) + Int(2) wired into Add. Select only
	# Int(1) + Add (omitting Int(2)). The wire feeding Add's right
	# input crosses the boundary and must be dropped; the wire
	# feeding Add's left input stays.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var lit1 = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(0, 0))
	lit1.value = 1
	var lit2 = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(0, 1))
	lit2.value = 2
	var add = _attach(level, HexNode.from_script(AddHex), Vector2i(1, 0))
	_wire(canvas, level, lit1, 0, add, 4)
	_wire(canvas, level, lit2, 0, add, 2)
	# Subset capture without Int(2).
	var payload := BlueprintCodec.serialize_subset(
		[lit1, add], canvas, "partial"
	)
	assert_eq(payload["hexes"].size(), 2,
			"subset should emit only the two included hexes")
	assert_eq(payload["wires"].size(), 1,
			"the wire whose source is outside the subset must be dropped")
	# Origin is the centroid of the subset axials.
	var ax_origin: Vector2i = Vector2i(
		int(payload["origin"][0]), int(payload["origin"][1])
	)
	# Centroid of [(0,0), (1,0)] rounds to (1,0) → 0,0 wide, no off-by-one
	# (roundf(0.5)→1 in GDScript). Just sanity-check the field exists.
	assert_eq(payload["hexes"][0]["axial"][0] + ax_origin.x, 0)
	assert_eq(payload["hexes"][1]["axial"][0] + ax_origin.x, 1)


func test_serialize_subset_drops_open_wires() -> void:
	# Open wires (no input endpoint) shouldn't ride along with a
	# subset capture — their dangling cells make pasting feel
	# unpredictable. Build a graph with one normal wire + one open
	# wire from the same Int, capture the subset, expect only the
	# fully-connected wire to survive.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var lit = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(0, 0))
	lit.value = 7
	var add = _attach(level, HexNode.from_script(AddHex), Vector2i(1, 0))
	# Normal wire — both endpoints in subset.
	_wire(canvas, level, lit, 0, add, 4)
	# Open wire from the same Int — input_node stays null. We attach
	# directly to the level since `_wire` always binds an input.
	var open_w := HexWire.new()
	open_w.output_node = lit
	open_w.output_edge = 0
	open_w.input_node = null
	open_w.anchor_node = lit
	open_w.anchor_edge = 0
	open_w.anchor_is_output = true
	open_w.is_finalized = true
	open_w.is_open = true
	open_w.cells.append(HexWire.make_cell(Vector2i(0, 1), 4, 1))
	level.wires.append(open_w)
	var payload := BlueprintCodec.serialize_subset(
		[lit, add], canvas, "no-open-wires"
	)
	assert_eq(payload["wires"].size(), 1,
			"subset capture should drop open / unconnected wires")


func test_serialize_subset_captures_included_fixture() -> void:
	# A drag-select that includes the DoHex captures it as fixture
	# metadata: never a stampable hex, but previews recreate it (at
	# fixture_axial) and the wire feeding it survives the subset filter.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var do_hex = _attach(level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var lit = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(2, 0))
	lit.value = 6
	_wire(canvas, level, lit, 0, do_hex, 3)
	var payload := BlueprintCodec.serialize_subset(
		[lit, do_hex], canvas, "with-do"
	)
	assert_true(payload.has("fixture_id"),
			"a selected fixture should be recorded as fixture_id")
	assert_true(payload.has("fixture_axial"),
			"fixture position (relative to origin) should be recorded")
	assert_true(payload.has("fixture_state"),
			"fixture display state should ride along")
	assert_eq(payload["hexes"].size(), 1,
			"the fixture itself must not be emitted as a stampable hex")
	assert_eq(payload["wires"].size(), 1,
			"the wire feeding the selected fixture must survive")
	# Centroid of [(2,0), (0,0)] is (1,0); the Do sat at (0,0) → (-1,0).
	assert_eq(payload["fixture_axial"], [-1, 0])
	# Stamping the payload with a fresh DoHex bound to the fixture id
	# rebinds the wire — the same path root blueprints take.
	var fresh_do: HexNode = HexNode.from_script(DoHex)
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO, fresh_do)
	assert_eq(built["wires"].size(), 1)
	assert_eq(built["wires"][0].input_node, fresh_do,
			"the captured wire should rebind to the provided fixture")


func test_serialize_subset_without_fixture_has_no_fixture_id() -> void:
	# Fixture metadata only appears when a fixture was actually
	# selected — freestanding fragments stay freestanding.
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var lit = _attach(level, HexNode.from_script(IntLiteralHex), Vector2i(0, 0))
	lit.value = 1
	var payload := BlueprintCodec.serialize_subset([lit], canvas, "plain")
	assert_false(payload.has("fixture_id"))
	assert_false(payload.has("fixture_axial"))


func test_serialize_root_emits_fixture_axial() -> void:
	var canvas := MockCanvas.new()
	var level := HexLevel.new()
	var do_hex = _attach(level, HexNode.from_script(DoHex), Vector2i(0, 0))
	var payload := BlueprintCodec.serialize_root(level, canvas, do_hex, "root")
	assert_eq(payload["fixture_axial"], [0, 0],
			"root captures should record where the Do sits relative to origin")


func test_missing_script_skips_hex_with_warning() -> void:
	var payload := {
		"version": 1,
		"hexes": [
			{
				"id": 0,
				"script": "res://src/classes/hex_nodes/nonexistent.gd",
				"class": "NopeHex",
				"axial": [0, 0],
				"rotation": 0,
				"state": {},
			},
			{
				"id": 1,
				"script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
				"class": "IntLiteralHex",
				"axial": [1, 0],
				"rotation": 0,
				"state": {"value": 7},
			},
		],
		"wires": [
			{
				"output": [0, 0],
				"input": [1, 4],
				"cells": [],
				"open": false,
			},
		],
	}
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO)
	# The unresolved hex is skipped; the wire touching it is dropped.
	assert_eq(built["hexes"].size(), 1)
	assert_eq(built["wires"].size(), 0)
	assert_true(built["warnings"].size() >= 2,
			"missing script + dropped wire each contribute a warning")
