@abstract
class_name Expr
extends RefCounted
## Abstract class for expressions in the AST.
##
## Literals, variables, lambda expressions and application inherit from this class.


## Lazily interprets the expression within a given environment.[br]
## Returns a [Value], often a [Value.Thunk].
@abstract func interpret(env: Env) -> Value


## Constant expression class
##
## Wraps a [Value] that has already been computed in a [Expr].
class Constant extends Expr:
	var _value: Value


	func _init(value: Value) -> void:
		_value = value


	func interpret(_env: Env) -> Value:
		return _value


## Integer expression class
class Int extends Expr:
	var _value: int


	func _init(value: int) -> void:
		_value = value
	
	
	func _to_string() -> String:
		return "Expr.Int(%d)" % _value


	func interpret(_env: Env) -> Value:
		return Value.Int.new(_value)


## Boolean expression class
class Bool extends Expr:
	var _value: bool


	func _init(value: bool) -> void:
		_value = value


	func _to_string() -> String:
		return "Expr.Bool(%s)" % str(_value)


	func interpret(_env: Env) -> Value:
		return Value.Bool.new(_value)


## Tuple expression class
class Tuple extends Expr:
	var _elements: Array[Expr]


	func _init(elements: Array[Expr]) -> void:
		_elements = elements


	func _to_string() -> String:
		return "Expr.Tuple(%s)" % str(_elements)


	func interpret(env: Env) -> Value:
		var deferred_elements: Array[Value] = []
		for element in _elements:
			deferred_elements.append(Value.Thunk.new(element, env))
		
		return Value.Tuple.new(deferred_elements)


## Base list expression class
@abstract
class ListExpr extends Expr:


	@abstract func interpret(env: Env) -> Value


## Empty list expression class
class Nil extends ListExpr:


	func _to_string() -> String:
		return "Expr.Nil()"


	func interpret(_env: Env) -> Value:
		return Value.List.new()


## List expression class
class List extends ListExpr:
	var _head: Expr
	var _tail: ListExpr


	func _init(head: Expr, tail: ListExpr) -> void:
		_head = head
		_tail = tail

	
	func _to_string() -> String:
		return "Expr.List(%s, %s)" % [_head._to_string(), _tail._to_string()]


	func interpret(env: Env) -> Value:
		var head_thunk = Value.Thunk.new(_head, env)
		var tail_thunk = Value.Thunk.new(_tail, env)
		return Value.List.new(head_thunk, tail_thunk)


## Range expression class
##
## Represents a lazy range of integers, e.g. `[1..10]` or `[1..]`.
class LstRange extends Expr:
	var _start: Expr
	var _end: Expr


	func _init(start: Expr, end: Expr = null) -> void:
		_start = start
		_end = end


	func _to_string() -> String:
		return "Expr.Range(%s, %s)" % [_start, _end]


	func interpret(env: Env) -> Value:
		var start_val = _start.interpret(env).force()
		var end_val = _end.interpret(env).force() if _end != null else Value.List.new()

		var call_expr = Expr.NativeCall.new(Prelude.range_step, [start_val, end_val])
		return Value.Thunk.new(call_expr, env)


## Lambda expression class
class Lambda extends Expr:
	var _params: Array[Pattern]
	var _body: Expr


	func _init(params: Array[Pattern], body: Expr) -> void:
		_params = params
		_body = body


	func _to_string() -> String:
		return "Expr.Lambda(%s, %s)" % [str(_params), _body._to_string()]


	func interpret(env: Env) -> Value:
		return Value.Closure.new(_body, _params, env)


## Application expression class
##
## Represents the application of a function to a single argument, e.g. `f x`.
class App extends Expr:
	var _func: Expr
	var _args: Array[Expr]

	
	func _init(func_expr: Expr, args: Array[Expr]) -> void:
		_func = func_expr
		_args = args


	func _to_string() -> String:
		return "Expr.App(%s, %s)" % [_func._to_string(), str(_args)]


	func interpret(env: Env) -> Value:
		var func_value = _func.interpret(env)

		if func_value != null and func_value.type == Value.Type.THUNK:
			func_value = func_value.force()

		if func_value == null:
			return Value.error("internal: applied expression produced no value")

		if func_value.is_error():
			return func_value

		if func_value.type != Value.Type.CLOSURE:
			return Value.error(
					"Attempted to call a non-function value (%s)"
					% func_value.type_to_string())

		var arg_values: Array[Value] = []
		for arg_expr in _args:
			arg_values.append(Value.Thunk.new(arg_expr, env))

		return func_value.apply(arg_values)


## Variable expression class
class Var extends Expr:
	var _name: String


	func _init(name: String) -> void:
		_name = name


	func _to_string() -> String:
		return "Expr.Var(%s)" % _name

	
	func interpret(env: Env) -> Value:
		if env.has(_name):
			return env.lookup(_name)
		# Free identifier: return a structured ErrorValue rather
		# than `null`. Parent operators that force this value
		# propagate the same error upward via `is_error()` checks
		# (see Operator.evaluate_strictly + the runner in
		# hex_editor.gd), so the player sees a clean message in the
		# output panel instead of a stack-trace crash on null deref.
		# No `push_error` — the structured ErrorValue is the
		# canonical signal, and the pre-flight validator catches
		# the common cases before the runner is reached.
		return Value.error("Free variable '%s'" % _name)


## Native function call expression class
##
## Calls a native function wrapped by a [Value.NativeClosure] with the given arguments.
class NativeCall extends Expr:
	var _callback: Callable
	var _args: Array

	func _init(callback: Callable, args: Array) -> void:
		_callback = callback
		_args = args

	
	func _to_string() -> String:
		return "Expr.NativeCall(%s, %s)" % [_callback, str(_args)]


	func interpret(env: Env) -> Value:
		var resolved_args: Array[Value] = []
		
		for arg in _args:
			if arg is Expr:
				# Resolve identifiers or nested expressions here
				resolved_args.append(arg.interpret(env))
			elif arg is Value:
				resolved_args.append(arg)
		
		# Now the static function receives only Values
		return _callback.call(resolved_args)
