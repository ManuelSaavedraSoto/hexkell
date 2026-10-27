extends GutTest
## Free-identifier failsafe: pre-flight in
## `_collect_validation_errors` catches IdentRefHex nodes whose
## chosen name isn't bound by any enclosing scope, and Expr.Var
## returns a structured ErrorValue at runtime so nested free
## variables don't crash the interpreter on null deref.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IdentRefHex := preload(
		"res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")

var _editor: Node


func before_each() -> void:
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame
	IdentifierPalette.set_exposed_reserved([])


func test_unbound_identref_surfaces_as_validation_error() -> void:
	# Place an IdentRefHex(red) at level 0 with no enclosing
	# `let red = …`. The pre-flight should fail with a clean error.
	var ref: HexNode = HexNode.from_script(IdentRefHex)
	ref.palette_index = 0  # red
	ref.level = _editor._level_stack[0]
	add_child_autofree(ref)
	_editor._level_stack[0].hexes.append(ref)
	await get_tree().process_frame
	var errors: Array[String] = _editor._collect_validation_errors()
	var found_free := false
	for e in errors:
		if "'red'" in e and "not bound" in e:
			found_free = true
			break
	assert_true(found_free,
			"Pre-flight should report a free-identifier error: got %s" % str(errors))


func test_var_interpret_returns_error_value_for_free_identifier() -> void:
	# Direct unit test of the runtime path: Expr.Var.interpret on an
	# empty env should return a Value.ErrorValue (not null), so
	# downstream operators can short-circuit without crashing.
	var env: Env = Env.root()
	var var_expr: Expr = Expr.Var.new("red")
	var result: Value = var_expr.interpret(env)
	assert_not_null(result,
			"Free identifier should not return null — returns an ErrorValue")
	assert_true(result.is_error(),
			"Returned value's is_error() should report true")
	assert_string_contains(result.error_message(), "red",
			"Error message should mention the missing name")


func test_operator_strict_eval_propagates_error_value() -> void:
	# `(+ 1 free)` where `free` is unbound — Operator.evaluate_strictly
	# should short-circuit on the ErrorValue from the second operand
	# and return it upward instead of crashing on `.value` access.
	var env: Env = Env.root()
	Prelude.load_std_lib(env)
	var left: Expr = Expr.Int.new(1)
	var right: Expr = Expr.Var.new("totally_unbound_name")
	var add: Operator = Operator.Add.new(left, right)
	var result: Value = Operator.evaluate_strictly(add, env)
	assert_not_null(result,
			"Strict-eval should produce a Value, not null")
	assert_true(result.is_error(),
			"Operator should propagate the ErrorValue from the unbound operand")
