extends GutTest
## letrec and let expression tests

var env: Env = Env.root()

func test_letrec_factorial():
	var fact_lambda = Expr.Lambda.new([
		Pattern.Var.new("n")
	], Ctrl.If.new(
		Operator.Equal.new(Expr.Var.new("n"), Expr.Int.new(0)),
		Expr.Int.new(1),
		Operator.Mult.new(Expr.Var.new("n"), Expr.App.new(Expr.Var.new("fact"), [Operator.Sub.new(Expr.Var.new("n"), Expr.Int.new(1))]))
	))

	var letrec_expr = Ctrl.LetRec.new("fact", fact_lambda, Expr.App.new(Expr.Var.new("fact"), [Expr.Int.new(5)]))
	var result = letrec_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 120)


func test_letrec_large_factorial():
	## Test robustness of stack-based evaluation with non-tail-optimized recursion
	## Factorial(20) = 2,432,902,008,176,640,000
	var fact_lambda = Expr.Lambda.new([
		Pattern.Var.new("n")
	], Ctrl.If.new(
		Operator.Equal.new(Expr.Var.new("n"), Expr.Int.new(0)),
		Expr.Int.new(1),
		Operator.Mult.new(Expr.Var.new("n"), Expr.App.new(Expr.Var.new("fact"), [Operator.Sub.new(Expr.Var.new("n"), Expr.Int.new(1))]))
	))

	var letrec_expr = Ctrl.LetRec.new("fact", fact_lambda, Expr.App.new(Expr.Var.new("fact"), [Expr.Int.new(20)]))
	var result = letrec_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 2432902008176640000)


func test_map_increment():
	var map_body = Ctrl.Match.new(Expr.Var.new("lst"), [
		Ctrl.Case.new(Pattern.List.new([]), Expr.Nil.new()),
		Ctrl.Case.new(
			Pattern.Cons.new(Pattern.Var.new("h"), Pattern.Var.new("t")),
			Operator.Cons.new(
				Expr.App.new(Expr.Var.new("f"), [Expr.Var.new("h")]),
				Expr.App.new(Expr.Var.new("map"), [Expr.Var.new("f"), Expr.Var.new("t")])
			)
		)
	])

	var map_lambda = Expr.Lambda.new([Pattern.Var.new("f"), Pattern.Var.new("lst")], map_body)

	var letrec_map = Ctrl.LetRec.new("map", map_lambda,
		Expr.App.new(Expr.Var.new("map"), [
			Expr.Lambda.new([Pattern.Var.new("x")], Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1))),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		])
	)
	var res = letrec_map.interpret(env).force()
	assert_eq(res.type, Value.Type.LIST)
	assert_eq(res.unwrap(), [2,3,4])


func test_fold_sum():
	var fold_body = Ctrl.Match.new(Expr.Var.new("lst"), [
		Ctrl.Case.new(Pattern.List.new([]), Expr.Var.new("acc")),
		Ctrl.Case.new(
			Pattern.Cons.new(Pattern.Var.new("h"), Pattern.Var.new("t")),
			Expr.App.new(Expr.Var.new("fold"), [
				Expr.Var.new("f"),
				Expr.App.new(Expr.Var.new("f"), [Expr.Var.new("acc"), Expr.Var.new("h")]),
				Expr.Var.new("t")
			])
		)
	])

	var fold_lambda = Expr.Lambda.new([Pattern.Var.new("f"), Pattern.Var.new("acc"), Pattern.Var.new("lst")], fold_body)

	var add_fn = Expr.Lambda.new([Pattern.Var.new("a"), Pattern.Var.new("b")], Operator.Add.new(Expr.Var.new("a"), Expr.Var.new("b")))

	var letrec_fold = Ctrl.LetRec.new("fold", fold_lambda,
		Expr.App.new(Expr.Var.new("fold"), [
			add_fn,
			Expr.Int.new(0),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		])
	)

	var sum_res = letrec_fold.interpret(env).force()
	assert_eq(sum_res.type, Value.Type.INT)
	assert_eq(sum_res.unwrap(), 6)


func test_let_simple_binding():
	var let_expr = Ctrl.Let.new("x", Expr.Int.new(42), Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1)))
	var result = let_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 43)


func test_nested_let_bindings():
	var inner_let = Ctrl.Let.new("y", Expr.Int.new(10), Operator.Add.new(Expr.Var.new("x"), Expr.Var.new("y")))
	var outer_let = Ctrl.Let.new("x", Expr.Int.new(5), inner_let)
	var result = outer_let.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 15)


func test_let_shadowing():
	var inner_let = Ctrl.Let.new("x", Expr.Int.new(20), Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1)))
	var outer_let = Ctrl.Let.new("x", Expr.Int.new(5), inner_let)
	var result = outer_let.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 21)


func test_nested_let_shadowing():
	var inner_let = Ctrl.Let.new("x", Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1)), Expr.Var.new("x"))
	var outer_let = Ctrl.Let.new("x", Expr.Int.new(5), inner_let)
	var result = outer_let.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 6)


func test_let_with_lambda():
	var let_expr = Ctrl.Let.new("inc", Expr.Lambda.new([Pattern.Var.new("x")], Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1))),
		Expr.App.new(Expr.Var.new("inc"), [Expr.Int.new(5)])
	)
	var result = let_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 6)


func test_fold_sum_large():
	## Test robustness with deep recursion over a large list (100 elements)
	## Creates a list [1, 2, 3, ..., 100] and sums to 5050
	var fold_body = Ctrl.Match.new(Expr.Var.new("lst"), [
		Ctrl.Case.new(Pattern.List.new([]), Expr.Var.new("acc")),
		Ctrl.Case.new(
			Pattern.Cons.new(Pattern.Var.new("h"), Pattern.Var.new("t")),
			Expr.App.new(Expr.Var.new("fold"), [
				Expr.Var.new("f"),
				Expr.App.new(Expr.Var.new("f"), [Expr.Var.new("acc"), Expr.Var.new("h")]),
				Expr.Var.new("t")
			])
		)
	])

	var fold_lambda = Expr.Lambda.new([Pattern.Var.new("f"), Pattern.Var.new("acc"), Pattern.Var.new("lst")], fold_body)
	var add_fn = Expr.Lambda.new([Pattern.Var.new("a"), Pattern.Var.new("b")], Operator.Add.new(Expr.Var.new("a"), Expr.Var.new("b")))

	# Build list [1, 2, 3, ..., 100]
	var list_expr: Expr = Expr.Nil.new()
	for i in range(100, 0, -1):
		list_expr = Operator.Cons.new(Expr.Int.new(i), list_expr)

	var letrec_fold = Ctrl.LetRec.new("fold", fold_lambda,
		Expr.App.new(Expr.Var.new("fold"), [
			add_fn,
			Expr.Int.new(0),
			list_expr
		])
	)

	var result = letrec_fold.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	# Sum of 1..100 = 100 * 101 / 2 = 5050
	assert_eq(result.unwrap(), 5050)
