extends GutTest
## Standard library tests

var env: Env = Env.root()


func before_all():
	Prelude.load_std_lib(env)


# ============================================================================
# MAP TESTS
# ============================================================================

func test_std_map():
	var map_expr = Expr.App.new(
		Expr.Var.new("map"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Operator.Add.new(Expr.Var.new("x"), Expr.Int.new(1))),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		]
	)
	var result = map_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [2,3,4])


func test_std_map_empty_list():
	var map_expr = Expr.App.new(
		Expr.Var.new("map"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Operator.Mult.new(Expr.Var.new("x"), Expr.Int.new(2))),
			Expr.Nil.new()
		]
	)
	var result = map_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_map_multiply():
	var map_expr = Expr.App.new(
		Expr.Var.new("map"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Operator.Mult.new(Expr.Var.new("x"), Expr.Int.new(2))),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		]
	)
	var result = map_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [2,4,6])


func test_std_append_lists():
	var append_expr = Operator.Append.new(
		Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.Nil.new())),
		Expr.List.new(Expr.Int.new(3), Expr.List.new(Expr.Int.new(4), Expr.Nil.new()))
	)
	var result = append_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [1,2,3,4])


func test_std_append_lazy_range():
	var append_expr = Operator.Append.new(
		Expr.LstRange.new(Expr.Int.new(1), Expr.Int.new(3)),
		Expr.List.new(Expr.Int.new(4), Expr.List.new(Expr.Int.new(5), Expr.Nil.new()))
	)
	var result = append_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [1,2,3,4,5])


# ============================================================================
# FOLDR TESTS
# ============================================================================

func test_std_foldr():
	var foldr_expr = Expr.App.new(
		Expr.Var.new("foldr"),
		[
			Expr.Lambda.new([Pattern.Var.new("x"), Pattern.Var.new("acc")], Operator.Add.new(Expr.Var.new("x"), Expr.Var.new("acc"))),
			Expr.Int.new(0),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		]
	)
	var result = foldr_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 6)


func test_std_foldr_empty_list():
	var foldr_expr = Expr.App.new(
		Expr.Var.new("foldr"),
		[
			Expr.Lambda.new([Pattern.Var.new("x"), Pattern.Var.new("acc")], Operator.Add.new(Expr.Var.new("x"), Expr.Var.new("acc"))),
			Expr.Int.new(100),
			Expr.Nil.new()
		]
	)
	var result = foldr_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 100)


func test_std_foldr_product():
	var foldr_expr = Expr.App.new(
		Expr.Var.new("foldr"),
		[
			Expr.Lambda.new([Pattern.Var.new("x"), Pattern.Var.new("acc")], Operator.Mult.new(Expr.Var.new("x"), Expr.Var.new("acc"))),
			Expr.Int.new(1),
			Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.List.new(Expr.Int.new(4), Expr.Nil.new())))
		]
	)
	var result = foldr_expr.interpret(env).force()
	assert_eq(result.unwrap(), 24)


# ============================================================================
# FILTER TESTS
# ============================================================================

func test_std_filter_even():
	# Filter for even numbers
	var filter_expr = Expr.App.new(
		Expr.Var.new("filter"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Operator.Equal.new(Operator.Mod.new(Expr.Var.new("x"), Expr.Int.new(2)), Expr.Int.new(0))),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.List.new(Expr.Int.new(4), Expr.Nil.new()))))
		]
	)
	var result = filter_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [2, 4])


func test_std_filter_empty_list():
	var filter_expr = Expr.App.new(
		Expr.Var.new("filter"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Expr.Bool.new(true)),
			Expr.Nil.new()
		]
	)
	var result = filter_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_filter_all_match():
	var filter_expr = Expr.App.new(
		Expr.Var.new("filter"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Expr.Bool.new(true)),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		]
	)
	var result = filter_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [1, 2, 3])


func test_std_filter_none_match():
	var filter_expr = Expr.App.new(
		Expr.Var.new("filter"),
		[
			Expr.Lambda.new([Pattern.Var.new("x")], Expr.Bool.new(false)),
			Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))
		]
	)
	var result = filter_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


# ============================================================================
# LENGTH TESTS
# ============================================================================

func test_std_length_empty():
	var length_expr = Expr.App.new(
		Expr.Var.new("length"),
		[Expr.Nil.new()]
	)
	var result = length_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 0)


func test_std_length_three():
	var length_expr = Expr.App.new(
		Expr.Var.new("length"),
		[Expr.List.new(Expr.Int.new(10), Expr.List.new(Expr.Int.new(20), Expr.List.new(Expr.Int.new(30), Expr.Nil.new())))]
	)
	var result = length_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 3)


func test_std_length_single():
	var length_expr = Expr.App.new(
		Expr.Var.new("length"),
		[Expr.List.new(Expr.Int.new(42), Expr.Nil.new())]
	)
	var result = length_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 1)


# ============================================================================
# HEAD TESTS
# ============================================================================

func test_std_head():
	var head_expr = Expr.App.new(
		Expr.Var.new("head"),
		[Expr.List.new(Expr.Int.new(42), Expr.List.new(Expr.Int.new(10), Expr.Nil.new()))]
	)
	var result = head_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 42)


func test_std_head_empty_list():
	var head_expr = Expr.App.new(
		Expr.Var.new("head"),
		[Expr.Nil.new()]
	)
	var result = head_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_head_single():
	var head_expr = Expr.App.new(
		Expr.Var.new("head"),
		[Expr.List.new(Expr.Int.new(99), Expr.Nil.new())]
	)
	var result = head_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.INT)
	assert_eq(result.unwrap(), 99)


# ============================================================================
# TAIL TESTS
# ============================================================================

func test_std_tail():
	var tail_expr = Expr.App.new(
		Expr.Var.new("tail"),
		[Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.Nil.new())))]
	)
	var result = tail_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [2, 3])


func test_std_tail_empty_list():
	var tail_expr = Expr.App.new(
		Expr.Var.new("tail"),
		[Expr.Nil.new()]
	)
	var result = tail_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_tail_single():
	var tail_expr = Expr.App.new(
		Expr.Var.new("tail"),
		[Expr.List.new(Expr.Int.new(42), Expr.Nil.new())]
	)
	var result = tail_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


# ============================================================================
# TAKE TESTS
# ============================================================================

func test_std_take():
	var range_expr = Expr.LstRange.new(Expr.Int.new(1), null)
	var take_expr = Expr.App.new(
		Expr.Var.new("take"),
		[Expr.Int.new(5), range_expr]
	)
	var result = take_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	var elements = result.unwrap()
	assert_eq(elements.size(), 5)
	assert_eq(elements[0], 1)
	assert_eq(elements[4], 5)


func test_std_take_zero():
	var take_expr = Expr.App.new(
		Expr.Var.new("take"),
		[Expr.Int.new(0), Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.Nil.new()))]
	)
	var result = take_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_take_more_than_available():
	var take_expr = Expr.App.new(
		Expr.Var.new("take"),
		[Expr.Int.new(10), Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.Nil.new()))]
	)
	var result = take_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap().size(), 2)


func test_std_take_from_empty():
	var take_expr = Expr.App.new(
		Expr.Var.new("take"),
		[Expr.Int.new(5), Expr.Nil.new()]
	)
	var result = take_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


# ============================================================================
# DROP TESTS
# ============================================================================

func test_std_drop():
	var drop_expr = Expr.App.new(
		Expr.Var.new("drop"),
		[Expr.Int.new(2), Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.List.new(Expr.Int.new(3), Expr.List.new(Expr.Int.new(4), Expr.Nil.new()))))]
	)
	var result = drop_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [3, 4])


func test_std_drop_zero():
	var drop_expr = Expr.App.new(
		Expr.Var.new("drop"),
		[Expr.Int.new(0), Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.Nil.new()))]
	)
	var result = drop_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [1, 2])


func test_std_drop_more_than_available():
	var drop_expr = Expr.App.new(
		Expr.Var.new("drop"),
		[Expr.Int.new(10), Expr.List.new(Expr.Int.new(1), Expr.List.new(Expr.Int.new(2), Expr.Nil.new()))]
	)
	var result = drop_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])


func test_std_drop_from_empty():
	var drop_expr = Expr.App.new(
		Expr.Var.new("drop"),
		[Expr.Int.new(5), Expr.Nil.new()]
	)
	var result = drop_expr.interpret(env).force()
	assert_eq(result.type, Value.Type.LIST)
	assert_eq(result.unwrap(), [])
