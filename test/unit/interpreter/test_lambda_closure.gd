extends GutTest
## Lambda, closure and application tests

var env: Env = Env.root()

func test_lambda_identity_application():
    var lambda_expr = Expr.Lambda.new([Pattern.Var.new("x")], Expr.Var.new("x"))
    var closure_val = lambda_expr.interpret(env)
    assert_eq(closure_val.type, Value.Type.CLOSURE)

    var app_expr = Expr.App.new(lambda_expr, [Expr.Int.new(5)])
    var app_result = app_expr.interpret(env).force()
    assert_eq(app_result.type, Value.Type.INT)
    assert_eq(app_result.unwrap(), 5)


func test_closure_captures_env():
    var outer_env = env.define_local("y", Value.Int.new(10))

    var lambda_expr = Expr.Lambda.new([], Expr.Var.new("y"))
    var app_expr = Expr.App.new(lambda_expr, [])
    var result = app_expr.interpret(outer_env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), 10)


func test_partial_and_full_application():
    var body = Operator.Add.new(Expr.Var.new("x"), Expr.Var.new("y"))
    var lam = Expr.Lambda.new([Pattern.Var.new("x"), Pattern.Var.new("y")], body)

    var partial_app = Expr.App.new(lam, [Expr.Int.new(3)])
    var partial_val = partial_app.interpret(env)
    assert_eq(partial_val.type, Value.Type.CLOSURE)

    var closure = partial_val as Value.Closure
    var second_result = closure.apply([Value.Thunk.new(Expr.Int.new(4), env)])
    assert_eq(second_result.type, Value.Type.THUNK)
    var final = second_result.force()
    assert_eq(final.type, Value.Type.INT)
    assert_eq(final.unwrap(), 7)
