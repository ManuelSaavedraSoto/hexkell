extends GutTest
## Arithmetic operator tests

var env: Env = Env.root()

func test_addition():
	var expr = Operator.Add.new(Expr.Int.new(5), Expr.Int.new(3))
	var result = expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 8)


func test_addition_with_thunk():
	var left = Expr.Int.new(10)
	var right = Expr.Int.new(20)
	var expr = Operator.Add.new(left, right)
	var thunk = expr.interpret(env)
	assert_eq(thunk.type, Value.Type.THUNK)
	var result = thunk.force()
	assert_eq(result.unwrap(), 30)


func test_subtraction():
	var expr = Operator.Sub.new(Expr.Int.new(10), Expr.Int.new(3))
	var result = expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 7)


func test_multiplication():
	var expr = Operator.Mult.new(Expr.Int.new(6), Expr.Int.new(7))
	var result = expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 42)


func test_division():
	var expr = Operator.Div.new(Expr.Int.new(20), Expr.Int.new(4))
	var result = expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 5)


func test_division_by_zero():
	var expr = Operator.Div.new(Expr.Int.new(5), Expr.Int.new(0))
	var result = expr.interpret(env).force()
	assert_true(result.is_error(), "Division by zero must return an ErrorValue")
	assert_string_contains(result.error_message(), "Division by zero")


func test_modulo():
	var expr = Operator.Mod.new(Expr.Int.new(17), Expr.Int.new(5))
	var result = expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 2)


func test_modulo_by_zero():
	var expr = Operator.Mod.new(Expr.Int.new(5), Expr.Int.new(0))
	var result = expr.interpret(env).force()
	assert_true(result.is_error(), "Modulo by zero must return an ErrorValue")
	assert_string_contains(result.error_message(), "Modulo by zero")
