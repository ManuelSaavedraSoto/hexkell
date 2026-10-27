extends GutTest
## Negation operator tests

var env: Env = Env.root()

func test_negate_integer():
    var expr = Operator.Negate.new(Expr.Int.new(42))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), -42)


func test_negate_boolean_true():
    var expr = Operator.Negate.new(Expr.Bool.new(true))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_negate_boolean_false():
    var expr = Operator.Negate.new(Expr.Bool.new(false))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)
