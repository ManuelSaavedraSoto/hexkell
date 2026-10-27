class_name Checker
extends Node
## Singleton responsible for checking the correctness of answers for the exercises.
##
## It receives the answer and the exercise, returning a boolean indicating whether 
## the answer is correct, along with detailed feedback about all test cases.
##
## Exercise Dictionary Format:
## {
##   "tests": [
##     {
##       "input": Variant or Array,       # argument(s) to pass to the answer function
##       "expected": Variant,       # expected result for this test case
##       "expected_type": Value.Type      # optional type check
##     }
##   ],
##   "variables": {                       # optional variables to inject
##     "var_name": Expr or Variant,       # pre-parsed or raw values
##   },
##   "required_structures": Array[String] # e.g., ["lambda", "letrec"]
##   "forbidden_structures": Array[String] # e.g., ["if"]
## }


## Check if an answer is correct for a given exercise.
## Returns a dictionary with:
##   - "correct": bool
##   - "passed_tests": int (number of tests that passed)
##   - "total_tests": int (total number of tests)
##   - "results": Array of test results
##   - "message": Overall feedback string
static func check_answer(exercise: Dictionary, answer: String) -> Dictionary:
	# Parse the answer
	var parse_result = _parse_answer(answer)
	if parse_result.has("error"):
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": "Parse error: " + parse_result["error"]
		}
	
	var ast: Array[Expr] = parse_result["ast"]
	
	# Check for forbidden structures
	var forbidden_check = _check_forbidden_structures(ast, exercise)
	if forbidden_check.has("error"):
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": forbidden_check["error"]
		}
	
	# Build environment with injected variables
	var env = _build_environment_with_variables(exercise)
	
	# Interpret the answer within the environment
	var interpret_result = _interpret_answer(ast, env)
	if interpret_result.has("error"):
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": "Runtime error: " + interpret_result["error"]
		}
	
	var answer_value: Value = interpret_result["value"]
	if answer_value == null:
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": "Runtime error: null result"
		}
	
	# Check required structures
	var required_check = _check_required_structures(ast, exercise)
	if required_check.has("error"):
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": required_check["error"]
		}

	# Bind the job's reserved parameters (white / black) to `main`. When
	# a job exposes them, the editor emits `do main white black = <expr>`,
	# so `main` evaluates to a closure expecting those values as its
	# leading arguments — apply them here, in palette order, before
	# testing. Older bare-expression answers reference the reserved names
	# directly and are bound through the environment instead, so a
	# non-closure answer is left untouched.
	var reserved_args := _reserved_param_values(exercise)
	if not reserved_args.is_empty():
		if answer_value.type == Value.Type.THUNK:
			answer_value = answer_value.force()
		if answer_value != null and answer_value.type == Value.Type.CLOSURE:
			answer_value = answer_value.apply(reserved_args)
			if answer_value == null:
				return {
					"correct": false,
					"passed_tests": 0,
					"total_tests": 0,
					"results": [],
					"message": "Runtime error: failed to apply reserved parameters to main"
				}

	# Run all test cases
	if not exercise.has("tests"):
		return {
			"correct": false,
			"passed_tests": 0,
			"total_tests": 0,
			"results": [],
			"message": "No test cases provided in exercise"
		}
	
	var tests: Array = exercise["tests"]
	var test_results: Array = []
	var passed_count = 0
	
	for test in tests:
		var test_result = _run_test_case(answer_value, test)
		test_results.append(test_result)
		if test_result.get("passed", false):
			passed_count += 1
	
	var all_passed = (passed_count == tests.size())
	var message = "%d/%d tests passed" % [passed_count, tests.size()]
	if all_passed:
		message = "Correct! All %d tests passed." % tests.size()
	else:
		# Find first failing test for detailed message
		for result in test_results:
			if not result.get("passed", false):
				message += " - First failure: " + result.get("message", "Unknown error")
				break
	
	return {
		"correct": all_passed,
		"passed_tests": passed_count,
		"total_tests": tests.size(),
		"results": test_results,
		"message": message
	}


## Parse the answer string into an AST.
static func _parse_answer(answer: String) -> Dictionary:
	if answer.is_empty():
		return {"error": "Empty answer"}
	
	var tokens = Lexer.lex(answer)
	
	# Check for lexer errors
	for token in tokens:
		if token.type == Token.Type.ERROR:
			return {"error": token.value}
	
	var ast = Parser.new(tokens).parse_program()
	
	if ast.is_empty():
		return {"error": "No expression provided"}
	
	return {"ast": ast}


## Build an environment with injected variables from the exercise.
static func _build_environment_with_variables(exercise: Dictionary, _use_std: bool = true) -> Env:
	var env = Env.root()
	if _use_std:
		Prelude.load_std_lib(env)
	
	if not exercise.has("variables"):
		return env
	
	var variables: Dictionary = exercise["variables"]
	var bindings: Dictionary[String, Value] = {}
	
	for var_name in variables.keys():
		var var_value = variables[var_name]
		
		# If it's already a Value, use it directly
		if var_value is Value:
			bindings[var_name] = var_value
		# If it's an Expr, interpret it in root environment
		elif var_value is Expr:
			var result = var_value.interpret(env)
			if result:
				bindings[var_name] = result
		# Otherwise try to wrap raw values
		else:
			var wrapped = _wrap_test_value(var_value)
			if wrapped:
				bindings[var_name] = wrapped
	
	return env.define_in_new_frame_batch(bindings)


## Reserved identifier names (white / black) the exercise injects, in
## palette order — the same order the editor emits them as `main`
## parameters in `do main white black = <expr>`.
static func _reserved_param_names(exercise: Dictionary) -> Array:
	var names: Array = []
	if not exercise.has("variables"):
		return names
	var variables: Dictionary = exercise["variables"]
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		var rname := IdentifierPalette.name_of(i)
		if variables.has(rname):
			names.append(rname)
	return names


## The values for those reserved parameters, wrapped as interpreter
## Values, ready to apply to `main` as leading arguments.
static func _reserved_param_values(exercise: Dictionary) -> Array[Value]:
	var out: Array[Value] = []
	if not exercise.has("variables"):
		return out
	var variables: Dictionary = exercise["variables"]
	for rname in _reserved_param_names(exercise):
		var raw = variables[rname]
		var v: Value = null
		if raw is Value:
			v = raw
		elif raw is Expr:
			v = raw.interpret(Env.root())
		else:
			v = _wrap_test_value(raw)
		if v != null:
			out.append(v)
	return out


## Interpret the parsed AST within a given environment.
static func _interpret_answer(ast: Array[Expr], env: Env) -> Dictionary:
	if ast.is_empty():
		return {"error": "Empty AST"}
	
	# If there are multiple expressions, the last one is the result
	var result: Value = null
	for expr in ast:
		result = expr.interpret(env)
	
	if result == null:
		return {"error": "no result"}

	# Force evaluation if it's a thunk
	if result.type == Value.Type.THUNK:
		result = result.force()

	if result == null:
		return {"error": "no result"}

	if result.is_error():
		return {"error": result.error_message()}

	return {"value": result}


## Run one test case against the answer result.
static func _run_test_case(answer_value: Value, test: Dictionary) -> Dictionary:
	var value = answer_value
	if value.type == Value.Type.THUNK:
		value = value.force()
	
	# If test has input/args, the answer must be a function
	if test.has("input") or test.has("args"):
		if value.type != Value.Type.CLOSURE:
			return {
				"passed": false,
				"input": test.get("input", test.get("args")),
				"expected": test.get("expected"),
				"actual": null,
				"message": "Answer must return a function when test includes inputs"
			}
		
		var args_result = _build_test_args(test)
		if args_result.has("error"):
			return {
				"passed": false,
				"input": test.get("input", test.get("args")),
				"expected": test.get("expected"),
				"actual": null,
				"message": args_result["error"]
			}
		var args: Array[Value] = args_result.get("args", [])
		
		value = value.apply(args)
		if value == null:
			return {
				"passed": false,
				"input": test.get("input", test.get("args")),
				"expected": test.get("expected"),
				"actual": null,
				"message": "Runtime error while applying test inputs"
			}

	if value.type == Value.Type.THUNK:
		value = value.force()

	if value == null or value.is_error():
		var detail: String = "no result" if value == null else value.error_message()
		return {
			"passed": false,
			"input": test.get("input", test.get("args")),
			"expected": test.get("expected"),
			"actual": null,
			"message": "Runtime error: " + detail
		}

	var unwrapped = value.unwrap()
	var expected = test.get("expected")

	# When `expected` is provided, the value must match exactly. If it is omitted,
	# the test is checking the *kind* of value via `expected_type` only.
	if test.has("expected"):
		var value_matches = _values_equal(unwrapped, expected)
		if not value_matches:
			return {
				"passed": false,
				"input": test.get("input", test.get("args")),
				"expected": expected,
				"actual": unwrapped,
				"message": "Expected %s but got %s" % [str(expected), str(unwrapped)]
			}
	
	# Check type match if specified
	if test.has("expected_type"):
		var expected_type = test["expected_type"]
		if value.type != expected_type:
			return {
				"passed": false,
				"input": test.get("input", test.get("args")),
				"expected": expected,
				"actual": unwrapped,
				"message": "Type mismatch: expected %s but got %s" % [
					_type_to_string(expected_type),
					_type_to_string(value.type)
				]
			}
	
	return {
		"passed": true,
		"input": test.get("input", test.get("args")),
		"expected": expected,
		"actual": unwrapped,
		"message": "Passed"
	}


## Build a list of argument values for a test case.
## Returns a dictionary with either "args" key containing the array, or "error" key with message.
static func _build_test_args(test: Dictionary) -> Dictionary:
	var raw_args = null
	if test.has("args"):
		raw_args = test["args"]
	elif test.has("input"):
		raw_args = test["input"]
	else:
		var empty_args: Array[Value] = []
		return {"args": empty_args}
	
	if raw_args is Array:
		var args: Array[Value] = []
		for raw in raw_args:
			var wrapped = _wrap_test_value(raw)
			if wrapped == null:
				return {"error": "Failed to wrap test input: %s" % str(raw)}
			args.append(wrapped)
		return {"args": args}
	
	var wrapped_value = _wrap_test_value(raw_args)
	if wrapped_value == null:
		return {"error": "Failed to wrap test input: %s" % str(raw_args)}
	
	var typed_args: Array[Value] = [wrapped_value]
	return {"args": typed_args}


## Convert a raw test value into an interpreter Value.
static func _wrap_test_value(raw: Variant) -> Value:
	if raw is int:
		return Value.Int.new(raw)
	elif raw is float:
		return Value.Int.new(int(raw))  # Convert float to int
	elif raw is bool:
		return Value.Bool.new(raw)
	elif raw is Array:
		var tail = Value.List.new()
		for i in range(raw.size() - 1, -1, -1):
			tail = Value.List.new(_wrap_test_value(raw[i]), tail)
		return tail
	elif raw == null:
		return Value.List.new()
	else:
		push_error("Unsupported test input type: %s" % typeof(raw))
		return null


## Check if required structures are present in the AST.
static func _check_required_structures(ast: Array[Expr], exercise: Dictionary) -> Dictionary:
	if not exercise.has("required_structures"):
		return {}
	
	var required: Array = exercise["required_structures"]
	if required.is_empty():
		return {}
	
	var found_structures = _find_structures(ast)
	
	for structure in required:
		if structure not in found_structures:
			return {"error": "Missing required structure: %s" % structure}
	
	return {}


## Check if forbidden structures are present in the AST.
static func _check_forbidden_structures(ast: Array[Expr], exercise: Dictionary) -> Dictionary:
	if not exercise.has("forbidden_structures"):
		return {}
	
	var forbidden: Array = exercise["forbidden_structures"]
	if forbidden.is_empty():
		return {}
	
	var found_structures = _find_structures(ast)
	
	for structure in forbidden:
		if structure in found_structures:
			return {"error": "Forbidden structure used: %s" % structure}
	
	return {}


## Find all structures used in the AST.
static func _find_structures(ast: Array[Expr]) -> Array[String]:
	var structures: Array[String] = []
	
	for expr in ast:
		_collect_structures(expr, structures)
	
	return structures


## Recursively collect structures from an expression.
static func _collect_structures(expr: Expr, structures: Array[String]) -> void:
	if expr == null:
		return
	
	# Determine the structure type
	var structure_name = _get_expr_type_name(expr)
	if not structure_name.is_empty() and structure_name not in structures:
		structures.append(structure_name)
	
	# Recursively check child expressions
	if expr is Expr.Lambda:
		_collect_structures(expr._body, structures)
	elif expr is Expr.App:
		_collect_structures(expr._func, structures)
		for arg in expr._args:
			_collect_structures(arg, structures)
	elif expr is Expr.Tuple:
		for element in expr._elements:
			_collect_structures(element, structures)
	elif expr is Expr.List:
		_collect_structures(expr._head, structures)
		_collect_structures(expr._tail, structures)
	elif expr is Expr.LstRange:
		_collect_structures(expr._start, structures)
		if expr._end != null:
			_collect_structures(expr._end, structures)
	elif expr is Ctrl.If:
		_collect_structures(expr._cond, structures)
		_collect_structures(expr._then, structures)
		_collect_structures(expr._else, structures)
	elif expr is Ctrl.Match:
		_collect_structures(expr._scrutinee, structures)
		for case in expr._cases:
			_collect_structures(case._body, structures)
	elif expr is Ctrl.Let:
		_collect_structures(expr._value_expr, structures)
		_collect_structures(expr._body, structures)
	elif expr is Ctrl.LetRec:
		_collect_structures(expr._value_expr, structures)
		_collect_structures(expr._body, structures)
	elif expr is Expr.NativeCall:
		for arg in expr._args:
			if arg is Expr:
				_collect_structures(arg, structures)
	elif expr is Operator:
		# Binary operators ( + - * / % == != < <= > >= && || : ++ . ) are
		# Operator subclasses with `_left` / `_right` children. Without
		# this branch, structure analysis sees them as opaque leaves —
		# required_structures: ["variable"] inside `white < black`
		# wouldn't fire because the Vars are hidden behind the operator.
		if "_left" in expr:
			_collect_structures(expr._left, structures)
		if "_right" in expr:
			_collect_structures(expr._right, structures)


## Get the name of an expression type (structure name).
static func _get_expr_type_name(expr: Expr) -> String:
	if expr is Expr.Int:
		return "int"
	elif expr is Expr.Bool:
		return "bool"
	elif expr is Expr.Tuple:
		return "tuple"
	elif expr is Expr.Nil:
		return "list"
	elif expr is Expr.List:
		return "list"
	elif expr is Expr.LstRange:
		return "range"
	elif expr is Expr.Lambda:
		return "lambda"
	elif expr is Expr.App:
		return "application"
	elif expr is Expr.Var:
		return "variable"
	elif expr is Ctrl.If:
		return "if"
	elif expr is Ctrl.Match:
		return "match"
	elif expr is Ctrl.Let:
		return "let"
	elif expr is Ctrl.LetRec:
		return "letrec"
	elif expr is Expr.NativeCall:
		return "native_call"
	elif expr is Operator:
		return "binary_op"
	else:
		return ""


## Compare two values for equality.
static func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	
	# Handle arrays (lists)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _values_equal(a[i], b[i]):
				return false
		return true
	
	# int vs float must stay comparable: job data comes from JSON, where
	# every number parses as a float (expected: 8.0), while the
	# interpreter produces ints.
	var a_num := a is int or a is float
	var b_num := b is int or b is float
	if a_num and b_num:
		return a == b

	# Other mixed Variant types never compare equal — and comparing them
	# with `==` raises "Invalid operands" in GDScript (e.g. int vs bool),
	# which surfaced as a script error instead of a failed test.
	if typeof(a) != typeof(b):
		return false

	# Handle other types
	return a == b


## Convert Value.Type to string for error messages.
static func _type_to_string(type: int) -> String:
	match type:
		Value.Type.INT:
			return "INT"
		Value.Type.BOOL:
			return "BOOL"
		Value.Type.TUPLE:
			return "TUPLE"
		Value.Type.LIST:
			return "LIST"
		Value.Type.CLOSURE:
			return "CLOSURE"
		Value.Type.THUNK:
			return "THUNK"
		_:
			return "UNKNOWN"
