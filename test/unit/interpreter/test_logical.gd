extends GutTest
## Logical operator tests

var env: Env = Env.root()

func test_and_both_true():
    var expr = Operator.And.new(Expr.Bool.new(true), Expr.Bool.new(true))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_and_left_false():
    var expr = Operator.And.new(Expr.Bool.new(false), Expr.Bool.new(true))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_and_short_circuit():
    var left = Expr.Bool.new(false)
    var right = Operator.Div.new(Expr.Int.new(1), Expr.Int.new(0))
    var expr = Operator.And.new(left, right)
    var result = expr.interpret(env).force()
    assert_eq(result.unwrap(), false)


func test_or_both_false():
    var expr = Operator.Or.new(Expr.Bool.new(false), Expr.Bool.new(false))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_or_left_true():
    var expr = Operator.Or.new(Expr.Bool.new(true), Expr.Bool.new(false))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_or_short_circuit():
    var left = Expr.Bool.new(true)
    var right = Operator.Div.new(Expr.Int.new(1), Expr.Int.new(0))
    var expr = Operator.Or.new(left, right)
    var result = expr.interpret(env).force()
    assert_eq(result.unwrap(), true)
