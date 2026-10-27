@abstract
class_name Operator
extends Expr
## Abstract class for operators in the AST.
##
## All operators in the AST inherit from this class.


# Fallback strict evaluator for direct `evaluate()` calls. The hot
# path — strict operators reached through `Thunk.force()` — runs on
# the reduction engine in value.gd instead, which flattens operand
# evaluation onto the same heap stack as thunk chains.
static func evaluate_strictly(root_op: Operator, root_env: Env) -> Value:
	var stack: Array[_OpFrame] = [_OpFrame.new(root_op, root_env)]
	var last_result: Value = null

	while stack.size() > 0:
		var frame = stack.back()

		if frame.current_index > 0 and frame.args.size() < frame.current_index:
			frame.args.append(last_result)

		if frame.current_index == frame.operands.size():
			last_result = frame.op.compute(frame.args)
			if last_result == null:
				last_result = Value.error("internal: operator produced no value")
			if last_result.is_error():
				return last_result
			stack.pop_back()
			continue

		var next_expr = frame.operands[frame.current_index]
		frame.current_index += 1

		if next_expr is Operator and next_expr.get_strict_operands().size() > 0:
			stack.append(_OpFrame.new(next_expr, frame.env))
		else:
			var val = next_expr.interpret(frame.env)

			if val != null and val.type == Value.Type.THUNK:
				val = val.force()

			if val == null:
				val = Value.error("internal: expression produced no value")

			# Free-variable / runtime errors propagate upward via
			# ErrorValue. Short-circuit immediately so `compute()`
			# never sees an Error operand (it would crash trying to
			# read its missing `.value`); the runner inspects the
			# final ErrorValue and surfaces the message.
			if val.is_error():
				return val

			frame.args.append(val)

	return last_result


func interpret(env: Env) -> Value:
	return Value.Thunk.new(self, env)


func get_strict_operands() -> Array[Expr]:
	return []


func compute(_args: Array[Value]) -> Value:
	return null


## Computes the differed operation
##
## This method is called when the thunk is forced.
## Uses [param env] as the interpretation environment.
@abstract func evaluate(env: Env) -> Value


class _OpFrame extends RefCounted:
	var op: Operator
	var env: Env
	var operands: Array[Expr]
	var args: Array[Value] = []
	var current_index: int = 0

	func _init(o: Operator, e: Env) -> void:
		self.op = o
		self.env = e
		self.operands = o.get_strict_operands()


## Negation operator class
##
## Supports negation for integers and booleans.
class Negate extends Operator:
	var _operand: Expr


	func _init(operand: Expr) -> void:
		_operand = operand


	func _to_string() -> String:
		return "Expr.Negate(%s)" % _operand


	func evaluate(env: Env) -> Value:
		var operand_value = _operand.interpret(env)

		if operand_value == null:
			return Value.error("internal: negation operand produced no value")

		operand_value = operand_value.force()
		if operand_value == null:
			return Value.error("internal: negation operand produced no value")

		match operand_value.type:
			Value.Type.INT:
				return Value.Int.new(-operand_value.value)
			Value.Type.BOOL:
				return Value.Bool.new(not operand_value.value)
			Value.Type.ERROR:
				return operand_value
			_:
				return Value.error(
						"Negation operator not supported for type %s"
						% operand_value.type_to_string())


## Addition operator class
##
## Supports addition of [Value.Int] types.
class Add extends Operator:
	var _left: Expr
	var _right: Expr

	
	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Add(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(_args: Array[Value]) -> Value:
		var _left_value = _args[0]
		var _right_value = _args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"Addition expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Int.new(_left_value.unwrap() + _right_value.unwrap())


## Substraction operator class
##
## Supports subtraction of [Value.Int] types.
class Sub extends Operator:
	var _left: Expr
	var _right: Expr

	
	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Sub(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"Subtraction expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Int.new(_left_value.unwrap() - _right_value.unwrap())


## Multiplication operator class
##
## Supports multiplication of [Value.Int] types.
class Mult extends Operator:
	var _left: Expr
	var _right: Expr

	
	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Mult(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"Multiplication expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Int.new(_left_value.unwrap() * _right_value.unwrap())


## Division operator class
##
## Supports division of [Value.Int] types.
class Div extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right

	
	func _to_string() -> String:
		return "Expr.Div(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"Division expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		if _right_value.unwrap() == 0:
			return Value.error("Division by zero")

		return Value.Int.new(_left_value.unwrap() / _right_value.unwrap())


## Modulo operator class
##
## Supports modulo of [Value.Int] types.
class Mod extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Mod(%s, %s)" % [_left, _right]

	
	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"Modulo expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		if _right_value.unwrap() == 0:
			return Value.error("Modulo by zero")

		return Value.Int.new(_left_value.unwrap() % _right_value.unwrap())


## Lesser than operator class
##
## Supports lesser than comparison of [Value.Int] types.
class LesserThan extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.LesserThan(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"LesserThan expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_left_value.unwrap() < _right_value.unwrap())


## Greater than operator class
##
## Supports greater than comparison of [Value.Int] types.
class GreaterThan extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.GreaterThan(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"GreaterThan expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_left_value.unwrap() > _right_value.unwrap())


## Lesser than or equal operator class
##
## Supports lesser than or equal comparison of [Value.Int] types.
class LessThanOrEqual extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.LessThanOrEqual(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"LessThanOrEqual expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_left_value.unwrap() <= _right_value.unwrap())


## Greater than or equal operator class
##
## Supports greater than or equal comparison of [Value.Int] types.
class GreaterThanOrEqual extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.GreaterThanOrEqual(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if _left_value.type != Value.Type.INT or _right_value.type != Value.Type.INT:
			return Value.error(
					"GreaterThanOrEqual expected (Int, Int), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_left_value.unwrap() >= _right_value.unwrap())


## Equality operator class
##
## Supports equality comparison of [Value.Int] and [Value.Bool] types.
class Equal extends Operator:
	var _left: Expr
	var _right: Expr
	var _allowed_types: Array = [[Value.Type.INT, Value.Type.INT],
								 [Value.Type.BOOL, Value.Type.BOOL]]


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Equal(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if [_left_value.type, _right_value.type] in _allowed_types:
			return Value.Bool.new(_left_value.unwrap() == _right_value.unwrap())
		else:
			return Value.error(
					"Equal expected types %s, but received (%s, %s)"
							% [str(_allowed_types), _left_value.type_to_string(), _right_value.type_to_string()])


## Not equal operator class
##
## Supports not equal comparison of [Value.Int] and [Value.Bool] types.
class NotEqual extends Operator:
	var _left: Expr
	var _right: Expr
	var _allowed_types: Array = [[Value.Type.INT, Value.Type.INT],
								 [Value.Type.BOOL, Value.Type.BOOL]]


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.NotEqual(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		return Operator.evaluate_strictly(self, env)


	func get_strict_operands() -> Array[Expr]:
		return [_left, _right]


	func compute(args: Array[Value]) -> Value:
		var _left_value = args[0]
		var _right_value = args[1]

		if [_left_value.type, _right_value.type] in _allowed_types:
			return Value.Bool.new(_left_value.unwrap() != _right_value.unwrap())
		else:
			return Value.error(
					"NotEqual expected types %s, but received (%s, %s)"
							% [str(_allowed_types), _left_value.type_to_string(), _right_value.type_to_string()])


## And operator class
##
## Supports logical AND of [Value.Bool] types.
class And extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.And(%s, %s)" % [_left, _right]

	
	func evaluate(env: Env) -> Value:
		var _left_value = _left.interpret(env)
		var _right_value = _right.interpret(env)

		if _left_value.type == Value.Type.THUNK:
			_left_value = _left_value.force()

		if _left_value == null:
			return Value.error("internal: AND operand produced no value")

		if _left_value.is_error():
			return _left_value

		if _left_value.type == Value.Type.BOOL and not _left_value.unwrap():
			return Value.Bool.new(false)

		if _right_value.type == Value.Type.THUNK:
			_right_value = _right_value.force()

		if _right_value == null:
			return Value.error("internal: AND operand produced no value")

		if _right_value.is_error():
			return _right_value

		if _left_value.type != Value.Type.BOOL or _right_value.type != Value.Type.BOOL:
			return Value.error(
					"AND expected (Bool, Bool), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_right_value.unwrap())


## Or operator class
##
## Supports logical OR of [Value.Bool] types.
class Or extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Or(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		var _left_value = _left.interpret(env)
		var _right_value = _right.interpret(env)

		if _left_value.type == Value.Type.THUNK:
			_left_value = _left_value.force()

		if _left_value == null:
			return Value.error("internal: OR operand produced no value")

		if _left_value.is_error():
			return _left_value

		if _left_value.type == Value.Type.BOOL and _left_value.unwrap():
			return Value.Bool.new(true)

		if _right_value.type == Value.Type.THUNK:
			_right_value = _right_value.force()

		if _right_value == null:
			return Value.error("internal: OR operand produced no value")

		if _right_value.is_error():
			return _right_value

		if _left_value.type != Value.Type.BOOL or _right_value.type != Value.Type.BOOL:
			return Value.error(
					"OR expected (Bool, Bool), but received (%s, %s)"
							% [_left_value.type_to_string(), _right_value.type_to_string()])

		return Value.Bool.new(_right_value.unwrap())


## Construct operator class
##
## Supports constructing [Value.List] from [Value].
class Cons extends Operator:
	var _head: Expr
	var _tail: Expr


	func _init(head: Expr, tail: Expr) -> void:
		_head = head
		_tail = tail

	
	func _to_string() -> String:
		return "Expr.Cons(%s, %s)" % [_head, _tail]

	
	func evaluate(env: Env) -> Value:
		var _head_thunk = Value.Thunk.new(_head, env)
		var _tail_thunk = Value.Thunk.new(_tail, env)

		return Value.List.new(_head_thunk, _tail_thunk)


## Append operator class
##
## Supports appending two [Value.List] values.
class Append extends Operator:
	var _left: Expr
	var _right: Expr


	func _init(left: Expr, right: Expr) -> void:
		_left = left
		_right = right


	func _to_string() -> String:
		return "Expr.Append(%s, %s)" % [_left, _right]


	func evaluate(env: Env) -> Value:
		var left = _left.interpret(env).force()

		if left == null:
			return Value.error("internal: append operand produced no value")

		if left.is_error():
			return left

		if left.type != Value.Type.LIST:
			return Value.error(
					"Append expected a List on the left, but received %s"
					% left.type_to_string())

		if left.is_empty:
			return _right.interpret(env)

		return Value.List.new(
			left.head,
			Value.Thunk.new(
				Operator.Append.new(
					Expr.Constant.new(left.tail),
					_right
				),
				env
			)
		)


## Compose operator class
##
## Supports composing functions.
## Given two functions f and g, returns a new function h such that h(x) = f(g(x)) = f . g x
class Dot extends Operator:
	var _f: Expr
	var _g: Expr


	func _init(f: Expr, g: Expr) -> void:
		_f = f
		_g = g

	
	func _to_string() -> String:
		return "Expr.Dot(%s, %s)" % [_f, _g]


	func evaluate(env: Env) -> Value:
		var args = Pattern.Var.new("__args__")
		var g_app = App.new(_g, [Expr.Var.new("__args__")])
		var f_app = App.new(_f, [g_app])

		return Value.Closure.new(f_app, [args], env)
