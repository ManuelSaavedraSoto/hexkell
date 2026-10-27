extends GutTest
## Checker structure analysis — regression coverage for `_collect_structures`,
## which walks the parsed AST to enforce required/forbidden structures.
## The Let / LetRec branches used to read non-existent members (`_value`,
## `_values`) and crashed on any answer containing a binding — including
## a bare top-level definition like `do main white = white`.


func test_collect_structures_walks_letrec_without_crashing() -> void:
	# letrec f = (\n -> if n then 1 else f) in f
	var lam := Expr.Lambda.new(
		[Pattern.Var.new("n")],
		Ctrl.If.new(Expr.Var.new("n"), Expr.Int.new(1), Expr.Var.new("f")))
	var letrec := Ctrl.LetRec.new("f", lam, Expr.Var.new("f"))
	var ast: Array[Expr] = [letrec]

	var found := Checker._find_structures(ast)
	assert_has(found, "letrec", "the letrec itself is recorded")
	assert_has(found, "lambda", "recurses into the bound value")
	assert_has(found, "if")
	assert_has(found, "variable", "recurses into the body")


func test_collect_structures_walks_let_without_crashing() -> void:
	# let x = 5 in (x, x)
	var let_expr := Ctrl.Let.new(
		"x", Expr.Int.new(5),
		Expr.Tuple.new([Expr.Var.new("x"), Expr.Var.new("x")]))
	var ast: Array[Expr] = [let_expr]

	var found := Checker._find_structures(ast)
	assert_has(found, "let")
	assert_has(found, "int", "recurses into the bound value")
	assert_has(found, "tuple", "recurses into the body")


func test_forbidden_check_tolerates_a_top_level_definition() -> void:
	# The exact shape from the bug report: a self-referential top-level
	# definition desugars to a LetRec. With a non-empty forbidden list the
	# analyser runs; letrec isn't forbidden here, so no error is raised.
	var exercise := {"tests": [], "forbidden_structures": ["if"]}
	var result := Checker.check_answer(exercise, "do main white = white")
	assert_true(result.has("correct"), "check_answer returns a result, not a crash")


func test_letrec_is_detected_when_forbidden() -> void:
	var exercise := {"tests": [], "forbidden_structures": ["letrec"]}
	var result := Checker.check_answer(exercise, "do main white = white")
	assert_false(result["correct"])
	assert_string_contains(result["message"], "letrec")
