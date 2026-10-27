@abstract
class_name Ctrl
extends Expr
## Abstract control expression class
##
## Control flow expressions inherit from this class.


## If expression class
##
## Represents an if-then-else expression with a condition, a then branch and an else branch.
## The condition is evaluated first; then only the corresponding branch is evaluated.
class If extends Ctrl:
	var _cond: Expr
	var _then: Expr
	var _else: Expr


	func _init(cond: Expr, then: Expr, else_: Expr) -> void:
		_cond = cond
		_then = then
		_else = else_

	
	func _to_string() -> String:
		return "Expr.If(%s, %s, %s)" % [_cond, _then, _else]

	
	func interpret(env: Env) -> Value:
		var cond_val = _cond.interpret(env)

		if cond_val != null and cond_val.type == Value.Type.THUNK:
			cond_val = cond_val.force()

		if cond_val == null:
			return Value.error("internal: if condition produced no value")

		if cond_val.is_error():
			return cond_val

		if cond_val.type != Value.Type.BOOL:
			return Value.error(
					"If condition must be Bool, got %s" % cond_val.type_to_string())

		if cond_val.unwrap():
			return Value.Thunk.new(_then, env)
		else:
			return Value.Thunk.new(_else, env)


## Case expression class
##
## Represents a case expression for pattern matching.
## It contains a scrutinee expression and a list of branches.
class Case extends RefCounted:
	var _pattern: Pattern
	var _body: Expr


	func _init(pattern: Pattern, body: Expr) -> void:
		_pattern = pattern
		_body = body


	func _to_string() -> String:
		return "Expr.Case(%s, %s)" % [_pattern, _body]


	func try_match(value: Value, env: Env) -> Dictionary:
		var match_result = _pattern.match(value)

		if match_result.has("matched") and match_result["matched"]:
			var bindings: Dictionary[String, Value] = {}
			
			if match_result.has("bindings"):
				bindings.merge(match_result["bindings"])

			var result_value = Value.Thunk.new(_body, env.define_in_new_frame_batch(bindings))
			return {"matched": true, "value": result_value}

		return {"matched": false, "value": null}


## Match expression class
##
## Represents a match expression with a value to match and a list of cases.
## Each case consists of a pattern and an expression to evaluate if the pattern matches.
class Match extends Ctrl:
	var _scrutinee: Expr
	var _cases: Array[Case]

	
	func _init(scrutinee: Expr, cases: Array[Case]) -> void:
		_scrutinee = scrutinee
		_cases = cases

	
	func _to_string() -> String:
		var case_strings = []
		for case in _cases:
			case_strings.append(case.to_string())
		return "Expr.Match(%s, [%s])" % [_scrutinee, ", ".join(case_strings)]


	func interpret(env: Env) -> Value:
		var scrutinee_val = _scrutinee.interpret(env)

		if scrutinee_val != null and scrutinee_val.type == Value.Type.THUNK:
			scrutinee_val = scrutinee_val.force()

		if scrutinee_val == null:
			return Value.error("internal: match scrutinee produced no value")

		if scrutinee_val.is_error():
			return scrutinee_val

		for case in _cases:
			var result = case.try_match(scrutinee_val, env)
			if result["matched"]:
				return result["value"]

		return Value.error("Non-exhaustive pattern match")


## Let expression class
##
## Represents a let-binding expression for defining local variables.
class Let extends Ctrl:
	var _name: String
	var _value_expr: Expr
	var _body: Expr


	func _init(name: String, value_expr: Expr, body: Expr) -> void:
		_name = name
		_value_expr = value_expr
		_body = body


	func _to_string() -> String:
		return "Expr.Let(%s, %s, %s)" % [_name, _value_expr, _body]

	
	func interpret(env: Env) -> Value:
		var thunk = Value.Thunk.new(_value_expr, env)
		var extended_env = env.define_local(_name, thunk)

		return Value.Thunk.new(_body, extended_env)


## LetRec expression class
##
## Represents a letrec expression for defining recursive functions.
class LetRec extends Ctrl:
	var _name: String
	var _value_expr: Expr
	var _body: Expr


	func _init(name: String, value_expr: Expr, body: Expr) -> void:
		_name = name
		_value_expr = value_expr
		_body = body


	func _to_string() -> String:
		return "Expr.LetRec(%s, %s, %s)" % [_name, _value_expr, _body]


	func interpret(env: Env) -> Value:
		var thunk = Value.Thunk.new(_value_expr, env)
		var extended_env = env.define_local(_name, thunk)
		thunk._env = extended_env
		return Value.Thunk.new(_body, extended_env)


## Program node — the root of a parsed module.
##
## A program is an ordered list of top-level definitions plus a single
## "main" expression to evaluate once those definitions are in scope.
## All definitions share one extended environment, so any top-level
## binding can reference any other (mutual recursion is permitted).
##
## `install(env)` returns the extended env without evaluating main, which
## is useful when running in an editor that wants definitions to persist
## across REPL invocations.
class Program extends Ctrl:
	## Each definition is a Dictionary `{ "name": String, "value_expr": Expr }`.
	var _definitions: Array
	var _main: Expr
	var _main_name: String  # explicit main name when set by `do <name> = ...`, else ""


	func _init(definitions: Array, main: Expr, main_name: String = "") -> void:
		_definitions = definitions
		_main = main
		_main_name = main_name


	func _to_string() -> String:
		var names: Array = []
		for d in _definitions:
			names.append(d.name)
		return "Expr.Program(defs=[%s], main=%s)" % [", ".join(names), _main]


	## Bind all top-level definitions into a single extended environment so
	## that every definition's thunk can see every other (mutual recursion).
	func install(env: Env) -> Env:
		var thunks: Dictionary[String, Value] = {}
		for def in _definitions:
			thunks[def.name] = Value.Thunk.new(def.value_expr, env)
		var extended: Env = env.define_local_batch(thunks)
		for name in thunks:
			(thunks[name] as Value.Thunk)._env = extended
		return extended


	func interpret(env: Env) -> Value:
		var extended: Env = install(env)
		if _main == null:
			return Value.List.new()
		return _main.interpret(extended)


	## True if an explicit `do <name> = ...` declaration was present in the source.
	func has_explicit_main() -> bool:
		return _main_name != ""


	func get_main_name() -> String:
		return _main_name


	func get_definitions() -> Array:
		return _definitions


	func get_main_expr() -> Expr:
		return _main
