extends GutTest
## On-canvas input-role labels: hexes whose argument order matters
## (sub, cons, if, …) declare `input_role_labels` and the base
## `HexNode` spawns a small word at each labeled edge midpoint,
## repositioning on rotation. Commutative operators declare nothing
## and stay clean.

const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const AddHex := preload(
		"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const SubHex := preload(
		"res://src/classes/hex_nodes/operators/arithmetic/sub_hex.gd")
const ConsHex := preload(
		"res://src/classes/hex_nodes/operators/list/cons_hex.gd")
const IfHex := preload(
		"res://src/classes/hex_nodes/control/if_hex.gd")
const IfAnchor := preload(
		"res://src/classes/hex_nodes/fixtures/if_anchor.gd")
const ComposeHex := preload(
		"res://src/classes/hex_nodes/operators/functional/compose_hex.gd")
const TupleHex := preload(
		"res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd")
const TupleAnchor := preload(
		"res://src/classes/hex_nodes/fixtures/tuple_anchor.gd")
const ListAnchor := preload(
		"res://src/classes/hex_nodes/fixtures/list_anchor.gd")
const LambdaHex := preload(
		"res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd")
const IdentifierPalette := preload(
		"res://scenes/gui/hex_editor/identifier_palette.gd")


func _spawn(script: Script) -> HexNode:
	var h: HexNode = HexNode.from_script(script)
	add_child_autofree(h)
	return h


func _label_texts(h: HexNode) -> Array:
	var texts := []
	for lbl in h._role_labels.values():
		texts.append((lbl as Label).text)
	texts.sort()
	return texts


func test_sub_hex_spawns_left_right_labels() -> void:
	var sub := _spawn(SubHex)
	assert_eq(_label_texts(sub), ["left", "right"],
			"Non-commutative − should label its operand edges")


func test_add_hex_spawns_no_labels() -> void:
	var add := _spawn(AddHex)
	assert_eq(add._role_labels.size(), 0,
			"Commutative + should stay unlabeled")


func test_if_hex_outer_face_is_cond_only() -> void:
	var if_hex := _spawn(IfHex)
	assert_eq(if_hex.input_edges.size(), 1,
			"If hex takes only the condition on its outer face")
	assert_eq(int(if_hex.input_edges[0]), 4, "Condition input sits on NW")
	assert_eq(if_hex._role_labels.size(), 0,
			"Single-input if hex needs no edge words (like let/match)")
	assert_true(if_hex.has_inner_level(),
			"Then/else bodies live one level down")


func test_if_anchor_brands_then_else_slots() -> void:
	var anchor := _spawn(IfAnchor)
	assert_eq(_label_texts(anchor), ["else", "then"],
			"If anchor words ride input_role_labels (no bespoke path)")
	assert_eq(anchor._role_labels.size(), 2,
			"Exactly one label per labeled edge")


func test_if_anchor_validate_mentions_then_branch() -> void:
	var anchor := _spawn(IfAnchor)
	var fake_canvas := _UnwiredCanvas.new()
	var v: Dictionary = anchor.validate(fake_canvas)
	assert_eq(v.get("status", ""), "error")
	assert_string_contains(String(v.get("message", "")), "then branch",
			"Unwired if anchor should name the missing branch role")


func test_compose_hex_spawns_f_g_labels() -> void:
	var compose := _spawn(ComposeHex)
	assert_eq(_label_texts(compose), ["f", "g"],
			"Compose should brand its outer/inner function edges")


func test_lambda_labels_param_with_its_glyph_and_colour() -> void:
	var lam := _spawn(LambdaHex)  # default arity 1, param identifier 0
	assert_eq(lam._role_labels.size(), 1, "one edge label per parameter")
	var edge: int = int(lam.input_edges[0])
	var lbl: Label = lam._role_labels[edge]
	assert_eq(lbl.text, IdentifierPalette.glyph_of(0),
			"label shows the parameter's identifier glyph")
	assert_eq(lbl.get_theme_color("font_color"), IdentifierPalette.color_of(0),
			"label is tinted by the parameter's identifier colour")


func test_lambda_seeds_distinct_rgb_as_arity_grows() -> void:
	var lam := _spawn(LambdaHex)
	lam.param_palette_indices.assign([0])
	while lam.param_palette_indices.size() < 3:
		lam.param_palette_indices.append(lam._next_free_param_index())
	assert_eq(lam.param_palette_indices, [0, 1, 2],
			"new params seed red → green → blue (distinct identifiers)")
	lam.arity = 3
	lam.input_edges.assign(HexMath.edges_for_arity(3))
	lam._refresh()
	var glyphs := _label_texts(lam)
	var expect := [IdentifierPalette.glyph_of(0), IdentifierPalette.glyph_of(1),
			IdentifierPalette.glyph_of(2)]
	expect.sort()
	assert_eq(glyphs, expect, "three distinct param glyphs, one per edge")


func test_lambda_removes_stale_labels_when_arity_shrinks() -> void:
	var lam := _spawn(LambdaHex)
	lam.param_palette_indices.assign([0, 1, 2])
	lam.arity = 3
	lam.input_edges.assign(HexMath.edges_for_arity(3))
	lam._refresh()
	assert_eq(lam._role_labels.size(), 3)
	lam.param_palette_indices.assign([0])
	lam.arity = 1
	lam.input_edges.assign(HexMath.edges_for_arity(1))
	lam._refresh()
	assert_eq(lam._role_labels.size(), 1,
			"shrinking arity frees the dropped parameters' labels")


func test_tuple_anchor_brands_ordinal_slots() -> void:
	# Configure before add_child, the way TupleHex.create_inner_anchor
	# does it, so _ready builds the right slots.
	var anchor: HexNode = HexNode.from_script(TupleAnchor)
	anchor.configure(HexMath.edges_for_arity(3))
	add_child_autofree(anchor)
	assert_eq(_label_texts(anchor), ["1st", "2nd", "3rd"],
			"Tuple anchor brands one ordinal per element slot")


func test_tuple_without_inner_level_fails_validation() -> void:
	var tup := _spawn(TupleHex)
	var v: Dictionary = tup.validate(_UnwiredCanvas.new())
	assert_eq(v.get("status", ""), "error",
			"An untouched tuple emits holes and must not validate clean")


func test_list_anchor_brands_ordinal_slots() -> void:
	var anchor := _spawn(ListAnchor)
	assert_eq(_label_texts(anchor), ["1st", "2nd", "3rd", "4th", "5th", "6th"],
			"List anchor brands all six optional slots")
	var v: Dictionary = anchor.validate(_UnwiredCanvas.new())
	assert_eq(v.get("status", ""), "ok",
			"All list slots are optional — empty block validates clean")


func test_labels_follow_rotation() -> void:
	var sub := _spawn(SubHex)
	sub.set_rotation_index(1)
	for logical in sub.input_role_labels:
		var lbl: Label = sub._role_labels[logical]
		var expected: Vector2 = HexMath.edge_offset(
				sub.physical_edge(logical), HexNode.HEX_SIZE) * 0.55 \
				- lbl.get_minimum_size() * 0.5
		assert_eq(lbl.position, expected,
				"Label %d should track its rotated physical edge" % logical)


func test_cons_validate_mentions_head() -> void:
	# Cons overrides input_role_names so the validator (and config
	# sidebar) speak head/tail instead of the generic left/right.
	var cons := _spawn(ConsHex)
	var fake_canvas := _UnwiredCanvas.new()
	var v: Dictionary = cons.validate(fake_canvas)
	assert_eq(v.get("status", ""), "error")
	assert_string_contains(String(v.get("message", "")), "head",
			"Unwired cons input should name the head role")


class _UnwiredCanvas:
	func get_input_for(_node, _edge):
		return null
