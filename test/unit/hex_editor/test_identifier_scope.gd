extends GutTest
## IdentifierScope guards: walks a hex's enclosing levels and
## returns the names bound by every reachable anchor, plus the
## job-exposed reserved identifiers. Used by IdentRefHex's
## sidebar and by the editor's free-identifier pre-flight.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload(
		"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const IdentRefHex := preload(
		"res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")
const LetRecHex := preload("res://src/classes/hex_nodes/control/let_rec_hex.gd")
const DefinitionHex := preload("res://src/classes/hex_nodes/control/definition_hex.gd")
const MatchHex := preload("res://src/classes/hex_nodes/control/match_hex.gd")
const AnchorHex := preload("res://src/classes/hex_nodes/fixtures/anchor_hex.gd")
const MatchAnchor := preload("res://src/classes/hex_nodes/fixtures/match_anchor.gd")

var _editor: Node


func before_each() -> void:
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame
	# Reset reserved exposure between tests so one job's spillover
	# can't leak in.
	IdentifierPalette.set_exposed_reserved([])


func _make_hex(script: Script, lvl: HexLevel) -> HexNode:
	var h: HexNode = HexNode.from_script(script)
	h.level = lvl
	add_child_autofree(h)
	return h


func test_level_0_hex_with_no_binding_has_empty_scope() -> void:
	# IdentRefHex placed at level 0 (no enclosing let / lambda / etc.)
	# sees no identifier names in scope.
	var ref := _make_hex(IdentRefHex, _editor._level_stack[0])
	await get_tree().process_frame
	var in_scope: Array = IdentifierScope.names_in_scope(ref)
	assert_eq(in_scope.size(), 0,
			"No bindings, no exposed reserved → empty scope")


func test_let_body_sees_bound_identifier() -> void:
	# Build a Let whose inner anchor emits `red`. A hex placed in
	# the inner level should report `red` as in-scope.
	var lvl := HexLevel.new()
	var anchor: HexNode = HexNode.from_script(AnchorHex)
	anchor.emit_labels = ["red"]
	anchor.level = lvl
	lvl.anchor = anchor
	add_child_autofree(anchor)
	# The Let's outer hex parents the inner level so the walker has
	# something to ascend out of.
	var let_hex: HexNode = HexNode.from_script(LetHex)
	let_hex.palette_index = 0
	let_hex.level = _editor._level_stack[0]
	add_child_autofree(let_hex)
	lvl.parent_hex = let_hex

	var body_hex: HexNode = HexNode.from_script(IntLiteralHex)
	body_hex.level = lvl
	add_child_autofree(body_hex)

	var in_scope: Array = IdentifierScope.names_in_scope(body_hex)
	assert_true("red" in in_scope,
			"Let's anchor emits `red`; body should see it")


func test_outside_let_doesnt_see_binding() -> void:
	# A hex at level 0, sibling to a Let, sees NOTHING from the Let's
	# inner scope.
	var ref := _make_hex(IdentRefHex, _editor._level_stack[0])
	await get_tree().process_frame
	var in_scope: Array = IdentifierScope.names_in_scope(ref)
	assert_false("red" in in_scope,
			"Outside the Let, the binding is unreachable")


func test_exposed_reserved_is_always_in_scope() -> void:
	# Reserved white / black come into scope when the job exposes
	# them via `set_exposed_reserved`. The walker should surface
	# them regardless of where the hex sits.
	IdentifierPalette.set_exposed_reserved(["white"])
	var ref := _make_hex(IdentRefHex, _editor._level_stack[0])
	await get_tree().process_frame
	var in_scope: Array = IdentifierScope.names_in_scope(ref)
	assert_true("white" in in_scope,
			"Exposed reserved identifier should be in scope at any hex")


func test_anchor_with_pattern_emit_label_surfaces_variables() -> void:
	# MatchAnchor.configure() sets emit_labels to the raw pattern
	# strings. IdentifierScope's `_collect_from_anchor` should run
	# each emit_label through `PatternVariables.extract` so multi-
	# variable patterns (cons / tuple) introduce all their named
	# slots into scope. Use AnchorHex (which has emit_labels) with
	# a pattern-shaped string to exercise the path without needing
	# the MatchAnchor .tscn (which is a fixture scene that doesn't
	# materialize cleanly under headless tests).
	var anchor: HexNode = HexNode.from_script(AnchorHex)
	anchor.emit_labels = ["(red:_)"]
	add_child_autofree(anchor)
	var lvl := HexLevel.new()
	lvl.anchor = anchor
	anchor.level = lvl

	var body_hex: HexNode = HexNode.from_script(IntLiteralHex)
	add_child_autofree(body_hex)
	body_hex.level = lvl

	var in_scope: Array = IdentifierScope.names_in_scope(body_hex)
	assert_true("red" in in_scope,
			"Pattern emit_label `(red:_)` should make `red` in scope; got %s" % str(in_scope))
	assert_false("blue" in in_scope,
			"Names not introduced by the pattern stay out of scope")


func test_let_rec_name_is_in_scope_at_value_expression_level() -> void:
	# let-rec broadcasts its bound name into the OUTER level (where
	# the value expression lives), not just the inner body level.
	# The user's repro:
	#   `let rec red = (\green -> ... (red yellow) ...) in (red cyan)`
	# `red` must be in scope where the lambda sits — that's the
	# let-rec's own level, not its inner level.
	var let_rec: HexNode = HexNode.from_script(LetRecHex)
	let_rec.palette_index = 0  # red
	let_rec.level = _editor._level_stack[0]
	_editor._level_stack[0].hexes.append(let_rec)
	add_child_autofree(let_rec)

	var sibling: HexNode = HexNode.from_script(IntLiteralHex)
	sibling.level = _editor._level_stack[0]
	_editor._level_stack[0].hexes.append(sibling)
	add_child_autofree(sibling)

	var in_scope: Array = IdentifierScope.names_in_scope(sibling)
	assert_true("red" in in_scope,
			"let-rec broadcasts its name to siblings; got %s" % str(in_scope))


func test_regular_let_does_not_leak_into_sibling_scope() -> void:
	# Non-rec let: bound name is body-only (the inner-level anchor
	# surfaces it). Siblings at the let's own level shouldn't see it.
	# Use a fresh level (don't share with _editor._level_stack[0],
	# which may have a persisted DefinitionHex sibling from saved
	# tab state that pollutes the scope walk).
	var lvl := HexLevel.new()
	var let_hex: HexNode = HexNode.from_script(LetHex)
	let_hex.palette_index = 0  # red
	let_hex.is_rec = false
	let_hex.level = lvl
	lvl.hexes.append(let_hex)
	add_child_autofree(let_hex)
	assert_false(let_hex.is_rec,
			"from_script(LetHex) should yield a non-rec let; got is_rec=true")
	assert_eq(let_hex.sibling_scope_name(), "",
			"Non-rec LetHex.sibling_scope_name() should be empty")

	var sibling: HexNode = HexNode.from_script(IntLiteralHex)
	sibling.level = lvl
	lvl.hexes.append(sibling)
	add_child_autofree(sibling)

	var in_scope: Array = IdentifierScope.names_in_scope(sibling)
	assert_false("red" in in_scope,
			"Plain let's binding stays in its body; got %s" % str(in_scope))


func test_definition_name_is_in_scope_at_level_zero() -> void:
	# `blue cyan = …` makes `blue` callable from anywhere at level 0
	# — including the DoHex's main expression. Without this fix the
	# IdentRef picker at level 0 greyed out the function name and
	# pre-flight rejected the program as a free variable.
	var defn: HexNode = HexNode.from_script(DefinitionHex)
	defn.identifier_palette_index = 2  # blue
	defn.level = _editor._level_stack[0]
	_editor._level_stack[0].hexes.append(defn)
	add_child_autofree(defn)

	var caller: HexNode = HexNode.from_script(IdentRefHex)
	caller.level = _editor._level_stack[0]
	_editor._level_stack[0].hexes.append(caller)
	add_child_autofree(caller)

	var in_scope: Array = IdentifierScope.names_in_scope(caller)
	assert_true("blue" in in_scope,
			"Definition's name should be in level-0 scope; got %s" % str(in_scope))
