extends GutTest

## Unit tests for the Parser.  Many cases are evaluated through the
## interpreter so that we exercise both parsing and semantics.

var env: Env = Env.root()

func before_all():
	# parser tests often evaluate small expressions; load stdlib so
	# builtins like map/filter used by list comprehension are defined.
	Prelude.load_std_lib(env)

# helpers using the public static API
func parse_expr(src: String) -> Expr:
	return Parser.parse_expr(src)

# AST utilities used in tests
func _contains_var(e: Expr, name: String) -> bool:
	if e is Expr.Var:
		return e._name == name
	elif e is Expr.App:
		if _contains_var(e._func, name):
			return true
		for a in e._args:
			if _contains_var(a, name):
				return true
		return false
	elif e is Expr.Lambda:
		return _contains_var(e._body, name)
	elif e is Expr.NativeCall:
		for a in e._args:
			if a is Expr and _contains_var(a, name):
				return true
		return false
	elif e is Expr.Tuple:
		for v in e._elements:
			if _contains_var(v, name):
				return true
		return false
	elif e is Expr.List:
		return _contains_var(e._head, name) or _contains_var(e._tail, name)
	elif e is Expr.Nil:
		return false
	elif e is Expr.LstRange:
		return _contains_var(e._start, name) or (e._end and _contains_var(e._end, name))
	elif e is Expr.App or e is Expr.NativeCall or e is Expr.Lambda or e is Expr.Tuple:
		# covered above
		pass
	# other expression types may embed children; default to false
	return false

func eval(src: String) -> Value:
	var e = parse_expr(src)
	if e == null:
		return null
	var v = e.interpret(env)
	if v == null:
		return null
	return v.force()

# ---------- basic expressions ------------------------------------------------

func test_integer_expression():
	var res = eval("42")
	assert_eq(res.type, Value.Type.INT)
	assert_eq(res.unwrap(), 42)

func test_arithmetic_precedence():
	# multiplication binds tighter than addition
	assert_eq(eval("1 + 2 * 3").unwrap(), 7)
	# left-associative plus
	assert_eq(eval("1 - 2 - 3").unwrap(), -4)
	# right-associative cons
	var cons_res = eval("1 : 2 : []")
	assert_eq(cons_res.unwrap(), [1, 2])

func test_function_application_associativity():
	# f a b may be represented either as a single App with two args or as
	# nested Apps; both are semantically equivalent.  Check for one of the
	# two forms instead of demanding a specific string.
	var ast = parse_expr("f a b")
	var s = ast._to_string()
	assert_true(
		s.begins_with("Expr.App(Expr.App") or s.begins_with("Expr.App(Expr.Var(f), [Expr.Var(a),"),
		"Unexpected application AST: %s" % s)

# ---------- operator sections ------------------------------------------------

func test_fully_unapplied_section():
	# (+) should be a two-arg lambda; applying to 1 and 2 yields 3
	assert_eq(eval("((+) 1 2)").unwrap(), 3)

func test_left_section():
	# (op expr) produces \x -> x op expr
	assert_eq(eval("((+ 1) 2)").unwrap(), 3)

func test_right_section():
	# (expr op) produces \s -> expr op s; also ensure nested parentheses
	assert_eq(eval("(1 +) 2").unwrap(), 3)
	assert_eq(eval("((1 +) 2)").unwrap(), 3)

# ---------- groupings, tuples, lists ----------------------------------------

func test_tuple_and_grouping():
	var ast1 = parse_expr("(1, 2, 3)")
	assert_true(ast1 is Expr.Tuple, "Expected tuple AST, got %s" % ast1._to_string())
	var ast2 = parse_expr("((1))")
	assert_true(ast2 is Expr.Int, "Expected integer AST, got %s" % ast2._to_string())

func test_list_and_range():
	assert_eq(eval("[1,2,3]").unwrap(), [1,2,3])
	assert_eq(eval("[1..3]").type, Value.Type.LIST)

func test_list_comprehension():
	# simple generator; result should be identical to input
	assert_eq(eval("[x | x <- [1,2,3]]").unwrap(), [1,2,3])

func test_list_comprehension_desugaring():
	# AST should use static calls rather than variable names.  ensure
	# no Var nodes referring to prelude functions.
	var ast = parse_expr("[x | x <- [1,2,3]]")
	assert_false(_contains_var(ast, "map"), "Unexpected Var(map) in %s" % ast._to_string())
	assert_false(_contains_var(ast, "foldr"), "Unexpected Var(foldr) in %s" % ast._to_string())
	# evaluation still works even without stdlib (verified by next test)

func test_comprehension_without_stdlib():
	# parsing result should evaluate correctly even if stdlib isn't loaded
	var env2 = Env.root()
	var e = parse_expr("[x | x <- [1,2,3]]")
	var v = e.interpret(env2).force()
	assert_eq(v.unwrap(), [1,2,3])

# ---------- lambdas and let/if/match ----------------------------------------

func test_lambda_and_application():
	assert_eq(eval("(\\x -> x + 1) 5").unwrap(), 6)

func test_if_then_else():
	assert_eq(eval("if 1 < 2 then 3 else 4").unwrap(), 3)

func test_let_binding():
	assert_eq(eval("let x = 5 in x + 1").unwrap(), 6)

func test_match_with_simple():
	assert_eq(eval("match 1 with | 1 = 42 | _ = 0").unwrap(), 42)

# ---------- syntax errors ---------------------------------------------------

func test_unmatched_paren_error():
	# parser may return a partial expression but must push an error
	var e = parse_expr("(1 + 2")
	assert_not_null(e, "Parser unexpectedly returned null")
	assert_push_error("Parser Error")

# ---------- top-level/program parsing ---------------------------------------

func test_definition_parsing():
	var prog = Parser.parse_string("f x = x + 1")
	assert_eq(prog.size(), 1)
	assert_not_null(prog[0])


# ---------- top-level declarations (Haskell-style, no semicolon) -------------

func eval_prog(src: String) -> Value:
	var exprs = Parser.parse_string(src)
	if exprs.is_empty():
		return null
	var result: Value = null
	for e in exprs:
		result = e.interpret(env)
	if result == null:
		return null
	return result.force()

func test_top_level_definition_returns_function():
	# `f x = body` at the top level evaluates to the function itself.
	var v = eval_prog("triple x = x * 3")
	assert_not_null(v)
	assert_eq(v.type, Value.Type.CLOSURE)
	var args: Array[Value] = [Value.Int.new(4)]
	var result = (v as Value.Closure).apply(args).force()
	assert_eq(result.unwrap(), 12)

func test_top_level_definition_is_recursive():
	# Top-level definitions desugar to LetRec, so self-reference works.
	var v = eval_prog("fact n = if n == 0 then 1 else n * fact (n - 1)")
	assert_not_null(v)
	assert_eq(v.type, Value.Type.CLOSURE)
	var args: Array[Value] = [Value.Int.new(5)]
	var result = (v as Value.Closure).apply(args).force()
	assert_eq(result.unwrap(), 120)

func test_let_in_still_works():
	# Ensure the traditional `let f x = body in expr` form is unchanged.
	assert_eq(eval("let f x = x + 1 in f 4").unwrap(), 5)

# ---------- parse_module / Program -------------------------------------------

func test_module_implicit_main_is_last_declaration():
	# Without `do`, the last declaration is the implicit main.
	var prog = Parser.parse_module("double x = x * 2\nsquare x = x * x")
	assert_not_null(prog)
	var result = prog.interpret(env).force()
	assert_not_null(result)
	assert_eq(result.type, Value.Type.CLOSURE)
	var args: Array[Value] = [Value.Int.new(4)]
	assert_eq((result as Value.Closure).apply(args).force().unwrap(), 16)

func test_module_explicit_do_main():
	# `do <name> = ...` designates the entry point regardless of order.
	var src = "double x = x * 2\ndo main = double 21\nsquare x = x * x"
	var prog = Parser.parse_module(src)
	assert_not_null(prog)
	assert_true(prog.has_explicit_main())
	assert_eq(prog.get_main_name(), "main")
	var result = prog.interpret(env).force()
	assert_eq(result.unwrap(), 42)

func test_module_definition_plus_do_main_application():
	# Regression: the hex editor emits `<def>\ndo main = <expr>` once the board
	# has a DefinitionHex. Earlier it emitted `do\n<expr>`, which the grammar
	# (do <name> = body) rejected with "Expected an identifier after `do`".
	var src = "red blue = blue + 1\ndo main = red 0"
	var prog = Parser.parse_module(src)
	assert_not_null(prog)
	assert_eq(prog.interpret(env).force().unwrap(), 1)

func test_module_mutual_recursion():
	# Top-level definitions share one environment, so they can mutually
	# recurse — something the old sequential model couldn't express.
	var src = (
		"even n = if n == 0 then true else odd (n - 1)\n"
		+ "odd  n = if n == 0 then false else even (n - 1)\n"
		+ "do main = even 6"
	)
	var prog = Parser.parse_module(src)
	var result = prog.interpret(env).force()
	assert_eq(result.unwrap(), true)

func test_module_layout_separates_adjacent_defs():
	# Two definitions on consecutive lines (no semicolon, no separator):
	# the layout rule must terminate the first at the column-1 start of
	# the second.
	var src = "f x = x + 1\ng y = y * 2"
	var prog = Parser.parse_module(src)
	assert_not_null(prog)
	assert_eq(prog.get_definitions().size(), 2)
	assert_eq(prog.get_definitions()[0].name, "f")
	assert_eq(prog.get_definitions()[1].name, "g")
