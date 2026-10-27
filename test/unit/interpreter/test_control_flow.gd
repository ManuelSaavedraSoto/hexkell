extends GutTest
## Control flow tests

var env: Env = Env.root()

func test_if_then_true_condition():
    var if_expr = Ctrl.If.new(
        Expr.Bool.new(true),
        Expr.Int.new(42),
        Expr.Int.new(0)
    )
    var result = if_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), 42)


func test_if_then_false_condition():
    var if_expr = Ctrl.If.new(
        Expr.Bool.new(false),
        Expr.Int.new(42),
        Expr.Int.new(999)
    )
    var result = if_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), 999)


func test_if_lazy_evaluation():
    var if_expr = Ctrl.If.new(
        Expr.Bool.new(true),
        Expr.Int.new(10),
        Operator.Div.new(Expr.Int.new(1), Expr.Int.new(0))
    )
    var result = if_expr.interpret(env).force()
    assert_eq(result.unwrap(), 10)
