extends GutTest
## List operations, ranges and cons

var env: Env = Env.root()

func test_cons_operator():
    var nil = Expr.Nil.new()
    var tail = Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), nil))
    var head = Expr.Int.new(1)
    var expr = Operator.Cons.new(head, tail)
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.LIST)
    var elements = result.unwrap()
    assert_eq(elements.size(), 3)
    assert_eq(elements[0], 1)
    assert_eq(elements[1], 2)
    assert_eq(elements[2], 3)


func test_cons_with_empty_list():
    var nil = Expr.Nil.new()
    var head = Expr.Int.new(42)
    var expr = Operator.Cons.new(head, nil)
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.LIST)
    var elements = result.unwrap()
    assert_eq(elements.size(), 1)
    assert_eq(elements[0], 42)


func test_range():
    var expr = Expr.LstRange.new(Expr.Int.new(1), Expr.Int.new(5))
    var result = expr.interpret(env).force()
    assert_eq(result.type, Value.Type.LIST)
    var range_val = result.unwrap()
    assert_eq(range_val.size(), 5)
    assert_eq(range_val[0], 1)
    assert_eq(range_val[4], 5)


func test_infinite_range():
    var range_expr = Expr.LstRange.new(Expr.Int.new(1), null)
    var range_val = range_expr.interpret(env).force()
    assert_eq(range_val.type, Value.Type.LIST)
    var elements = []
    for i in range(10000):
        elements.append(range_val.head.unwrap())
        range_val = range_val.tail
    assert_eq(elements, range(1, 10001))
