extends GutTest
## Non-destructive arity: growing / shrinking a Tuple, Match or Lambda
## keeps the inner level intact. Surviving slots hold their edge (the
## prefix-stable clockwise-from-NE order) and their wire; only a removed
## slot's wire is dropped, and an undo brings it back. Driven through a
## real editor instance so the wire-drop + undo bookkeeping is exercised.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const TupleHex := preload("res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd")
const LambdaHex := preload("res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd")
const MatchHex := preload("res://src/classes/hex_nodes/control/match_hex.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")

var _saved_hex: Dictionary
var _saved_autosave: bool
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	_saved_autosave = SaveManager.get_auto_save()
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
	SaveManager.current_data["preferences"]["auto_save"] = _saved_autosave
	SaveManager.set_archmage(false)
	ModalStack.reset(get_tree())


# Place a hex on the active level and register it with the editor.
func _place(script: Script, axial: Vector2i) -> HexNode:
	var hex: HexNode = HexNode.from_script(script)
	_editor.nodes_layer.add_child(hex)
	hex.set_axial(axial)
	hex.level = _editor._current_level()
	_editor._current_level().hexes.append(hex)
	_editor._wire_node_signals(hex)
	return hex


# Finalized wire feeding `value` into `sink`'s input `edge` on `level`.
func _wire_into(level: HexLevel, sink: HexNode, edge: int, value: int) -> HexWire:
	var src: HexNode = HexNode.from_script(IntLiteralHex)
	level.nodes.add_child(src)
	src.level = level
	src.value = value
	level.hexes.append(src)
	var w := HexWire.new()
	w.output_node = src
	w.output_edge = 0
	w.input_node = sink
	w.input_edge = edge
	w.is_finalized = true
	level.wires.append(w)
	return w


func _wired_edges_of(level: HexLevel, sink: HexNode) -> Array:
	var edges: Array = []
	for w in level.wires:
		if w.input_node == sink:
			edges.append(int(w.input_edge))
	edges.sort()
	return edges


# ── Tuple: variable slots live on the inner anchor ──────────────────────

func test_grow_preserves_existing_element_wires() -> void:
	var tup := _place(TupleHex, Vector2i(2, 0))
	_editor._create_inner_level_for(tup)
	await get_tree().process_frame
	var anchor: HexNode = tup.inner_level.anchor
	# Arity 2 → slots on edges [5, 0].
	_wire_into(tup.inner_level, anchor, 5, 1)
	_wire_into(tup.inner_level, anchor, 0, 2)
	_editor._on_arity_change_requested(tup, 3)
	assert_eq(tup.arity, 3, "arity should grow to 3")
	assert_eq(anchor.input_edges, [5, 0, 1],
			"growing appends the next clockwise-from-NE edge")
	assert_eq(_wired_edges_of(tup.inner_level, anchor), [0, 5],
			"both existing element wires survive a grow")


func test_shrink_drops_only_the_removed_slot_wire() -> void:
	var tup := _place(TupleHex, Vector2i(2, 0))
	tup.arity = 3
	_editor._create_inner_level_for(tup)
	await get_tree().process_frame
	var anchor: HexNode = tup.inner_level.anchor
	# Arity 3 → slots [5, 0, 1], all wired.
	_wire_into(tup.inner_level, anchor, 5, 1)
	_wire_into(tup.inner_level, anchor, 0, 2)
	_wire_into(tup.inner_level, anchor, 1, 3)
	_editor._on_arity_change_requested(tup, 2)
	assert_eq(tup.arity, 2)
	assert_eq(anchor.input_edges, [5, 0], "shrink pops the last edge")
	assert_eq(_wired_edges_of(tup.inner_level, anchor), [0, 5],
			"only the removed slot's (edge 1) wire is dropped; the rest stay")


func test_shrink_then_undo_restores_the_dropped_wire() -> void:
	var tup := _place(TupleHex, Vector2i(2, 0))
	tup.arity = 3
	_editor._create_inner_level_for(tup)
	await get_tree().process_frame
	var anchor: HexNode = tup.inner_level.anchor
	_wire_into(tup.inner_level, anchor, 5, 1)
	_wire_into(tup.inner_level, anchor, 0, 2)
	_wire_into(tup.inner_level, anchor, 1, 3)
	_editor._on_arity_change_requested(tup, 2)
	assert_eq(_wired_edges_of(tup.inner_level, anchor), [0, 5])
	_editor._undo()
	assert_eq(tup.arity, 3, "undo restores the arity")
	assert_eq(anchor.input_edges, [5, 0, 1], "undo regrows the slot")
	assert_eq(_wired_edges_of(tup.inner_level, anchor), [0, 1, 5],
			"undo brings the dropped element wire back intact")


# ── Lambda: variable slots live on the OUTER face ───────────────────────

func test_lambda_shrink_drops_outer_argument_wire() -> void:
	var lam := _place(LambdaHex, Vector2i(2, 0))
	lam.apply_arity(2)
	# Arity 2 → outer param face on edges [5, 0]; feed an argument into
	# each.
	_wire_into(_editor._current_level(), lam, 5, 10)
	_wire_into(_editor._current_level(), lam, 0, 20)
	_editor._on_arity_change_requested(lam, 1)
	assert_eq(lam.arity, 1)
	assert_eq(lam.input_edges, [5], "lambda outer face shrinks to one param")
	assert_eq(_wired_edges_of(_editor._current_level(), lam), [5],
			"only the removed param's (edge 0) argument wire is dropped")
	_editor._undo()
	assert_eq(lam.arity, 2)
	assert_eq(_wired_edges_of(_editor._current_level(), lam), [0, 5],
			"undo restores the dropped argument wire")


# ── Inner-anchor config delegation ──────────────────────────────────────

func _sidebar_label_texts() -> Array:
	var texts: Array = []
	_collect_labels(_editor.config_sidebar, texts)
	return texts


func _collect_labels(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Label:
			out.append(String((c as Label).text))
		_collect_labels(c, out)


func test_tuple_anchor_delegates_config_to_outer_hex() -> void:
	var tup := _place(TupleHex, Vector2i(2, 0))
	_editor._create_inner_level_for(tup)
	await get_tree().process_frame
	var anchor: HexNode = tup.inner_level.anchor
	assert_eq(anchor.config_delegate(), tup,
			"Tuple anchor should delegate its config to the owning TupleHex")
	# Opening the sidebar on the anchor builds the TupleHex's config UI.
	_editor._open_config_sidebar(anchor)
	var titles := _sidebar_label_texts()
	assert_true("Tuple" in titles,
			"Anchor sidebar shows the outer hex's title (delegated), got %s" % str(titles))
	assert_false("Tuple Anchor" in titles,
			"Delegation should replace the anchor's own bare config")


func test_match_anchor_delegates_config_to_outer_hex() -> void:
	var m := _place(MatchHex, Vector2i(3, 0))
	_editor._create_inner_level_for(m)
	await get_tree().process_frame
	assert_eq(m.inner_level.anchor.config_delegate(), m,
			"Match anchor should delegate its config to the owning MatchHex")


func test_let_anchor_delegates_config_to_outer_hex() -> void:
	var let_hex := _place(LetHex, Vector2i(4, 0))
	_editor._create_inner_level_for(let_hex)
	await get_tree().process_frame
	assert_eq(let_hex.inner_level.anchor.config_delegate(), let_hex,
			"The shared AnchorHex should delegate to its owning Let/Lambda/Definition")
