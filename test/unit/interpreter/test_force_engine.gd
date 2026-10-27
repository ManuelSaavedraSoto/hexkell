extends GutTest
## The iterative reduction engine in Thunk.force flattens thunk chains
## AND strict-operator operand evaluation onto one heap stack. Its
## capability win: deep non-tail recursion evaluates correctly where
## the old mutually-recursive force/evaluate overflowed the native
## GDScript stack at a few thousand frames.


var env: Env


func before_each() -> void:
	env = Env.root()
	Prelude.load_std_lib(env)


func _eval(code: String) -> Value:
	var ast = Parser.new(Lexer.lex(code)).parse_program()
	var result: Value = ast[0].interpret(env)
	if result != null and result.type == Value.Type.THUNK:
		result = result.force()
	return result


func test_deep_nontail_recursion_evaluates() -> void:
	# 2000 pending `1 + …` continuations — previously a segfault.
	var result = _eval(
			"let rec f = \\x -> if x == 0 then 0 else 1 + f (x - 1) in f 2000")
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 2000)


func test_deep_tail_recursion_evaluates() -> void:
	var result = _eval(
			"let rec f = \\x -> if x == 0 then 42 else f (x - 1) in f 2000")
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 42)


func test_deeply_nested_strict_operands() -> void:
	# Strict operands nest through the OPERATOR/ARG_STORE arms.
	var result = _eval("1 + (2 * (3 + (4 * (5 - 3))))")
	assert_eq(result.unwrap(), 23)


func test_memoization_still_caches_chains() -> void:
	# Pass-through thunks must all cache the final value (THUNK_STORE).
	var ast = Parser.new(Lexer.lex("let x = 1 + 1 in let y = x in y")).parse_program()
	var thunk = ast[0].interpret(env)
	assert_eq(thunk.force().unwrap(), 2)
	assert_true(thunk.evaluated, "root thunk must be cached after force")
	assert_eq(thunk.force().unwrap(), 2)


func test_lazy_lists_unaffected() -> void:
	# A huge range stays lazy: take must force only its 5 cells.
	# (Parenthesized — the parser doesn't accept a list literal as a
	# bare application argument.)
	var result = _eval("(take 5) [1..1000000]")
	assert_eq(result.unwrap(), [1, 2, 3, 4, 5])


func test_mixed_strict_and_lazy_operators() -> void:
	# && is lazy (re-enters force natively); + is strict (flattened).
	var result = _eval("(1 + 2 == 3) && (10 / 2 == 5)")
	assert_eq(result.unwrap(), true)
