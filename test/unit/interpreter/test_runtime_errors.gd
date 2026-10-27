extends GutTest
## Runtime errors must surface as structured ErrorValues with readable
## messages — never as push_error script-error floods, null cascades,
## stack overflows, or freezes. These are regression tests for the
## playtest failures: int-vs-bool submissions crashing the checker and
## cyclic/infinite recursion hanging the game.


var env: Env


func before_each() -> void:
	env = Env.root()
	Prelude.load_std_lib(env)


func _eval(code: String) -> Value:
	var ast = Parser.new(Lexer.lex(code)).parse_program()
	var result: Value = null
	for expr in ast:
		result = expr.interpret(env)
	if result != null and result.type == Value.Type.THUNK:
		result = result.force()
	return result


func _assert_error_contains(code: String, fragment: String) -> void:
	var result = _eval(code)
	assert_not_null(result, "%s must produce a value, not null" % code)
	if result == null:
		return
	assert_true(result.is_error(),
			"%s must produce an ErrorValue, got %s" % [code, result])
	if result.is_error():
		assert_string_contains(result.error_message(), fragment)


# ── Operator type mismatches ───────────────────────────────────────────────

func test_add_int_and_bool_returns_error() -> void:
	_assert_error_contains("5 + true", "Addition expected (Int, Int)")


func test_compare_int_and_bool_returns_error() -> void:
	_assert_error_contains("5 < true", "LesserThan expected (Int, Int)")


func test_and_with_int_returns_error() -> void:
	_assert_error_contains("5 && true", "AND expected (Bool, Bool)")


func test_equal_int_and_bool_returns_error() -> void:
	_assert_error_contains("5 == true", "Equal expected")


func test_negate_list_returns_error() -> void:
	_assert_error_contains("![1, 2]", "Negation operator not supported")


func test_if_with_int_condition_returns_error() -> void:
	_assert_error_contains("if 5 then 1 else 2", "If condition must be Bool")


func test_division_by_zero_returns_error() -> void:
	_assert_error_contains("1 / 0", "Division by zero")


func test_calling_non_function_returns_error() -> void:
	_assert_error_contains("5 6", "non-function")


func test_over_application_returns_error() -> void:
	_assert_error_contains("(\\x -> x) 1 2", "non-function")


func test_free_variable_returns_error() -> void:
	_assert_error_contains("nope + 1", "Free variable 'nope'")


func test_non_exhaustive_match_returns_error() -> void:
	_assert_error_contains("match 5 with | 1 = true", "Non-exhaustive")


func test_error_propagates_through_nesting() -> void:
	# The error from the innermost operand must come out the top
	# unchanged — no cascading nulls, no secondary messages.
	_assert_error_contains("1 + (2 * (3 - (4 / 0)))", "Division by zero")


# ── Anti-freeze fuel limits ────────────────────────────────────────────────

func test_length_of_cyclic_list_returns_error() -> void:
	# `let rec xs = 1 : xs in length xs` used to freeze the game
	# forever (unbounded while-loop in Prelude.length).
	_assert_error_contains("let rec xs = 1 : xs in length xs",
			"length: list exceeds")


func test_infinite_tail_recursion_returns_budget_error() -> void:
	# Used to segfault: the engine kept reducing on the heap, but the
	# abandoned thunk/env chain crashed Godot's recursive teardown.
	_assert_error_contains("let rec f = \\x -> f x in f 1",
			"evaluation exceeded")


func test_infinite_nontail_recursion_returns_budget_error() -> void:
	# Used to overflow the GDScript stack and flood thousands of errors.
	_assert_error_contains("let rec f = \\x -> 1 + f x in f 1",
			"evaluation exceeded")


func test_budget_error_is_cached() -> void:
	# Re-forcing an exhausted thunk must answer instantly from cache
	# instead of re-spinning the whole step budget.
	var ast = Parser.new(Lexer.lex("let rec f = \\x -> f x in f 1")).parse_program()
	var thunk = ast[0].interpret(env)
	var first = thunk.force()
	assert_true(first.is_error())
	var t0 := Time.get_ticks_msec()
	var second = thunk.force()
	var elapsed := Time.get_ticks_msec() - t0
	assert_true(second.is_error())
	assert_lt(elapsed, 100, "cached budget error must return instantly")


# ── Checker integration ────────────────────────────────────────────────────

func test_checker_int_vs_bool_expected_fails_cleanly() -> void:
	# The original playtest bug: submitting an Int program against a
	# Bool-expected job raised "Invalid operands 'int' and 'bool' in
	# operator '=='" inside _values_equal. Now it's just a failed test.
	var job := {"tests": [{"expected": true}]}
	var result: Dictionary = Checker.check_answer(job, "5")
	assert_false(result["correct"])
	assert_string_contains(String(result["message"]), "Expected true but got 5")


func test_checker_runtime_error_surfaces_message() -> void:
	var job := {"tests": [{"expected": 8}]}
	var result: Dictionary = Checker.check_answer(job, "5 + true")
	assert_false(result["correct"])
	assert_string_contains(String(result["message"]), "Addition expected (Int, Int)")


func test_checker_infinite_loop_terminates_with_message() -> void:
	var job := {"tests": [{"expected": 1}]}
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = Checker.check_answer(
			job, "let rec xs = 1 : xs in length xs")
	var elapsed := Time.get_ticks_msec() - t0
	assert_false(result["correct"])
	assert_lt(elapsed, 8000, "cyclic-list check must terminate, not freeze")
