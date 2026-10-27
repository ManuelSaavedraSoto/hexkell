extends GutTest
## Pattern matching tests

var env: Env = Env.root()

func test_match_int_pattern_match():
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.Int.new(42), Expr.Bool.new(true)),
        Ctrl.Case.new(Pattern.Int.new(0), Expr.Bool.new(false))
    ]
    var match_expr = Ctrl.Match.new(Expr.Int.new(42), cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_match_int_pattern_no_match():
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.Int.new(42), Expr.Bool.new(true)),
        Ctrl.Case.new(Pattern.Int.new(0), Expr.Bool.new(false))
    ]
    var match_expr = Ctrl.Match.new(Expr.Int.new(0), cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_match_bool_pattern():
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.Bool.new(true), Expr.Int.new(1)),
        Ctrl.Case.new(Pattern.Bool.new(false), Expr.Int.new(0))
    ]
    var match_expr = Ctrl.Match.new(Expr.Bool.new(true), cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), 1)


func test_match_wildcard_pattern():
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.Int.new(42), Expr.Bool.new(true)),
        Ctrl.Case.new(Pattern.Wildcard.new(), Expr.Bool.new(false))
    ]
    var match_expr = Ctrl.Match.new(Expr.Int.new(99), cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), false)


func test_match_tuple_pattern():
    var tuple_expr = Expr.Tuple.new([Expr.Int.new(1), Expr.Bool.new(true)])
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.Tuple.new([Pattern.Int.new(1), Pattern.Bool.new(true)]), Expr.Int.new(1)),
        Ctrl.Case.new(Pattern.Wildcard.new(), Expr.Int.new(0))
    ]
    var match_expr = Ctrl.Match.new(tuple_expr, cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), 1)


func test_match_list_pattern_exact():
    var nil = Expr.Nil.new()
    var list_expr = Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), nil)))
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(Pattern.List.new([Pattern.Int.new(1), Pattern.Int.new(2), Pattern.Int.new(3)]), Expr.Bool.new(true)),
        Ctrl.Case.new(Pattern.Wildcard.new(), Expr.Bool.new(false))
    ]
    var match_expr = Ctrl.Match.new(list_expr, cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), true)


func test_match_cons_bindings():
    var nil = Expr.Nil.new()
    var list_expr = Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), nil)))
    var cons_pattern = Pattern.Cons.new(Pattern.Var.new("h"), Pattern.Var.new("t"))
    var cases:Array[Ctrl.Case] = [
        Ctrl.Case.new(cons_pattern, Expr.Tuple.new([Expr.Var.new("h"), Expr.Var.new("t")])),
        Ctrl.Case.new(Pattern.Wildcard.new(), Expr.Tuple.new([Expr.Int.new(0), Expr.Nil.new()]))
    ]
    var match_expr = Ctrl.Match.new(list_expr, cases)
    var result = match_expr.interpret(env).force()
    assert_eq(result.type, Value.Type.TUPLE)
    var elements = result.unwrap()
    assert_eq(elements.size(), 2)
    assert_eq(elements[0], 1)
    assert_eq(elements[1].size(), 2)
    assert_eq(elements[1][0], 2)
    assert_eq(elements[1][1], 3)
