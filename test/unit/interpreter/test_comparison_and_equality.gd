extends GutTest
## Comparison and equality operator tests

var env: Env = Env.root()

func test_lesser_than_true():
    var expr = Operator.LesserThan.new(Expr.Int.new(3), Expr.Int.new(5))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_lesser_than_false():
    var expr = Operator.LesserThan.new(Expr.Int.new(5), Expr.Int.new(3))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_greater_than_true():
    var expr = Operator.GreaterThan.new(Expr.Int.new(5), Expr.Int.new(3))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_greater_than_false():
    var expr = Operator.GreaterThan.new(Expr.Int.new(3), Expr.Int.new(5))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_less_than_or_equal_true():
    var expr = Operator.LessThanOrEqual.new(Expr.Int.new(3), Expr.Int.new(3))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_greater_than_or_equal_true():
    var expr = Operator.GreaterThanOrEqual.new(Expr.Int.new(5), Expr.Int.new(5))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_equal_ints_true():
    var expr = Operator.Equal.new(Expr.Int.new(42), Expr.Int.new(42))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_equal_ints_false():
    var expr = Operator.Equal.new(Expr.Int.new(42), Expr.Int.new(43))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_equal_bools_true():
    var expr = Operator.Equal.new(Expr.Bool.new(true), Expr.Bool.new(true))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_not_equal_ints_true():
    var expr = Operator.NotEqual.new(Expr.Int.new(5), Expr.Int.new(10))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_not_equal_ints_false():
    var expr = Operator.NotEqual.new(Expr.Int.new(7), Expr.Int.new(7))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)
