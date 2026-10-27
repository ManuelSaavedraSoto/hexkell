extends GutTest
## Tests for literal expressions and simple collections.

var env: Env = Env.root()

func test_integer_literal():
    var random_int = randi() % 1000
    var expr = Expr.Int.new(random_int)
    var result = expr.interpret(env)
    assert_eq(result.type, Value.Type.INT)
    assert_eq(result.unwrap(), random_int)


func test_boolean_literal():
    var random_bool = randi_range(0, 1) == 1
    var expr = Expr.Bool.new(random_bool)
    var result = expr.interpret(env)
    assert_eq(result.type, Value.Type.BOOL)
    assert_eq(result.unwrap(), random_bool)


func test_tuple_expression():
    var int_expr = Expr.Int.new(42)
    var bool_expr = Expr.Bool.new(true)
    var tuple_expr = Expr.Tuple.new([int_expr, bool_expr])
    var result = tuple_expr.interpret(env)
    assert_eq(result.type, Value.Type.TUPLE)
    var elements = result.unwrap()
    assert_eq(elements.size(), 2)
    assert_eq(elements[0], 42)
    assert_eq(elements[1], true)


func test_list_expression():
    var nil = Expr.Nil.new()
    var list_expr = Expr.List.new(
        Expr.Int.new(1),
        Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), nil))
    )
    var result = list_expr.interpret(env)
    assert_eq(result.type, Value.Type.LIST)
    var elements = result.unwrap()
    assert_eq(elements.size(), 3)
    assert_eq(elements[0], 1)
    assert_eq(elements[1], 2)
    assert_eq(elements[2], 3)


func test_empty_list():
    var list_expr = Expr.Nil.new()
    var result = list_expr.interpret(env)
    assert_eq(result.type, Value.Type.LIST)
    assert_eq(result.unwrap(), [])
