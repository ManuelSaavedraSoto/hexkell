class_name Parser
extends RefCounted
## Pratt parser (top-down operator precedence) for the lazy functional language.
##
## Two entry points:
##   • [method parse_string] returns an [Array] of top-level [Expr] nodes
##     (each definition is desugared into a [Ctrl.LetRec]). Used by the legacy
##     REPL-style consumers and the exercise checker.
##   • [method parse_module] returns a single [Ctrl.Program] node that holds
##     every definition + a designated `main` expression. All definitions
##     share one environment so they can mutually recurse.
##
## A module is a list of declarations separated by whitespace at column 1.
## Continuations of a declaration must be indented. An explicit entry point
## is written `do <name> [params] = <expr>`; without one, the last
## declaration in the file is the implicit main.
##
## Precedence is encoded entirely in the [constant BP] table.
## To add a new infix operator, add one entry there and one match arm in
## [method _parse_led] — nothing else needs to change.
##
## Grammar reference: docs/LANG.md


# ── Binding-power table ─────────────────────────────────────────────────────
#
#   Each entry is [left_bp, right_bp].
#
#   left_bp   – how strongly this token binds to the expression on its LEFT.
#               The main loop continues as long as  left_bp > min_bp.
#
#   right_bp  – the minimum BP passed when recursing for the RIGHT operand.
#               left_bp == right_bp      → left-associative
#               right_bp == left_bp - 1  → right-associative

const BP: Dictionary = {
	# ── Logical ──────────────────────────────────────  L    R
	Token.Type.OR:          [10,  10],  # left-assoc
	Token.Type.AND:         [20,  20],  # left-assoc

	# ── Comparison ───────────────────────────────────
	Token.Type.LT:          [30,  30],
	Token.Type.GT:          [30,  30],
	Token.Type.LTE:         [30,  30],
	Token.Type.GTE:         [30,  30],
	Token.Type.EQ:          [30,  30],
	Token.Type.NEQ:         [30,  30],

	# ── Additive ─────────────────────────────────────
	Token.Type.PLUS:        [40,  41],  # left-assoc
	Token.Type.MINUS:       [40,  41],  # left-assoc
	Token.Type.CONCAT:      [40,  41],  # left-assoc  (++)

	# ── Cons (right-assoc: 1:2:[] == 1:(2:[])) ──────
	Token.Type.CONS:        [45,  44],  # right-assoc

	# ── Multiplicative ────────────────────────────────
	Token.Type.MULT:        [50,  51],  # left-assoc
	Token.Type.DIV:         [50,  51],  # left-assoc
	Token.Type.MOD:         [50,  51],  # left-assoc

	# ── Function composition (right-assoc: f.g.h == f.(g.h)) ─
	Token.Type.DOT:         [60,  59],  # right-assoc
}

## Binding power used for implicit function application.
## Any token that can start an expression is treated as a new argument
## rather than an infix operator when its effective LBP == APP_BP.
const APP_BP: int    = 70

## Binding power for prefix negation (!).
const PREFIX_BP: int = 80


# ── State ───────────────────────────────────────────────────────────────────

var _tokens: Array[Token]
var _pos:    int = 0
## When > 0, the expression parser stops at any token whose column is <= this
## value. Used to enforce that a new declaration starting at column 1
## terminates the previous declaration's body. Suspended inside grouping
## constructs (parens, brackets) via [method _suspend_layout].
var _layout_break_col: int = 0


func _init(tokens: Array[Token]) -> void:
	_tokens = tokens
	_pos    = 0


# ════════════════════════════════════════════════════════════════════════════
# Public API
# ════════════════════════════════════════════════════════════════════════════
static func parse_string(src: String) -> Array[Expr]:
	var tokens = Lexer.lex(src)
	return Parser.new(tokens).parse_program()


static func parse_expr(src: String) -> Expr:
	var tokens = Lexer.lex(src)
	return Parser.new(tokens).parse_expr_single()


## Parses the full token stream as a module and returns a [Ctrl.Program]
## node. Every top-level definition is collected into the program's binding
## list; the entry point is either the explicit `do <name> = ...` declaration
## or, when none is given, the last declaration in source order.
static func parse_module(src: String) -> Ctrl.Program:
	var tokens = Lexer.lex(src)
	return Parser.new(tokens).parse_module_internal()


## Parses the full token stream and returns an array of top-level expressions.
func parse_program() -> Array[Expr]:
	var results: Array[Expr] = []
	_layout_break_col = 1
	while not _check(Token.Type.EOF):
		results.append(_parse_top_level())
	_layout_break_col = 0
	return results


## Parses a single expression (entry point for the REPL).
func parse_expr_single() -> Expr:
	var e = _parse_expr(0)
	_expect(Token.Type.EOF)
	return e


## Internal: produces a [Ctrl.Program] from the token stream.
func parse_module_internal() -> Ctrl.Program:
	_layout_break_col = 1
	var definitions: Array = []
	var bare_exprs: Array[Expr] = []
	var explicit_main: String = ""

	while not _check(Token.Type.EOF):
		if _check(Token.Type.DO):
			var def = _parse_do_declaration()
			if def == null:
				break
			definitions.append(def)
			explicit_main = def.name
		elif _check(Token.Type.ID) and _looks_like_definition():
			var def = _parse_definition_record()
			if def == null:
				break
			definitions.append(def)
		else:
			bare_exprs.append(_parse_expr(0))

	_layout_break_col = 0

	var main_expr: Expr
	if explicit_main != "":
		main_expr = Expr.Var.new(explicit_main)
	elif not bare_exprs.is_empty():
		main_expr = bare_exprs.back()
	elif not definitions.is_empty():
		main_expr = Expr.Var.new(definitions.back().name)
	else:
		main_expr = null

	return Ctrl.Program.new(definitions, main_expr, explicit_main)


# ════════════════════════════════════════════════════════════════════════════
# Top-level: definitions vs. bare expressions
# ════════════════════════════════════════════════════════════════════════════

func _parse_top_level() -> Expr:
	if _check(Token.Type.DO):
		# `do <name> [params] = body` — for parse_string callers we represent
		# this as a plain LetRec so the result still fits in Array[Expr].
		var def = _parse_do_declaration()
		if def == null:
			return null
		return Ctrl.LetRec.new(def.name, def.value_expr, Expr.Var.new(def.name))
	if _check(Token.Type.ID) and _looks_like_definition():
		return _parse_definition()
	return _parse_expr(0)


## Lookahead heuristic: we are at an ID token.
## A definition follows when the next token is '=', a pattern-start token,
## or a pipe for guarded equations.
func _looks_like_definition() -> bool:
	var i = _pos + 1
	if i >= _tokens.size():
		return false
	var next = _tokens[i].type
	return next in [
		Token.Type.EQUAL,
		Token.Type.PIPE,
		Token.Type.UNDER,
		Token.Type.LPAREN,
		Token.Type.LBRACK,
		Token.Type.INT,
		Token.Type.BOOL_T,
		Token.Type.BOOL_F,
		Token.Type.ID,
	]


## Parses `do <name> [params] = <expr>` and returns a definition record
## `{ name, value_expr }`. The `do` token has already been peeked but not
## consumed.
func _parse_do_declaration() -> Dictionary:
	_expect(Token.Type.DO)
	if not _check(Token.Type.ID):
		_error("Expected an identifier after `do`")
		return {}
	var name: String = _peek().value
	var equations: Array[Dictionary] = []
	while _check(Token.Type.ID) and _peek().value == name:
		equations.append(_parse_equation())
	if equations.is_empty():
		_error("Expected an equation for `do %s`" % name)
		return {}
	var value = _build_definition_value(name, equations)
	return {"name": name, "value_expr": value}


## Returns the same `{ name, value_expr }` shape as `_parse_do_declaration`,
## but for plain (non-`do`) top-level definitions.
func _parse_definition_record() -> Dictionary:
	var name = _peek().value
	var equations: Array[Dictionary] = []
	while _check(Token.Type.ID) and _peek().value == name:
		equations.append(_parse_equation())
	if equations.is_empty():
		_error("Expected at least one equation for '%s'" % name)
		return {}
	return {"name": name, "value_expr": _build_definition_value(name, equations)}


# ── Definition ───────────────────────────────────────────────────────────────
#
# Multiple equations for the same name are collected and desugared into a
# single lambda + match expression:
#
#   f 0 = 1
#   f n = n * f (n - 1)
#
# becomes (conceptually):
#
#   let rec f = \__a0__ -> match __a0__ with
#       | 0 = 1
#       | n = n * f (n - 1)

func _parse_definition() -> Expr:
	var record = _parse_definition_record()
	if record.is_empty():
		return null
	# Wrap as LetRec(name, value, Var(name)) so evaluating a top-level
	# definition with the legacy [method parse_string] still yields the
	# function itself (the exercise checker relies on this).
	return Ctrl.LetRec.new(record.name, record.value_expr, Expr.Var.new(record.name))


## Parses one equation:  name { pattern } ( = expr | guards )
func _parse_equation() -> Dictionary:
	_advance()  # consume the name identifier

	var params: Array[Pattern] = []
	while not _check(Token.Type.EQUAL) and not _check(Token.Type.PIPE) \
			and not _check(Token.Type.EOF):
		params.append(_parse_pattern())

	var body: Expr
	if _check(Token.Type.PIPE):
		body = _parse_guarded_body()
	else:
		_expect(Token.Type.EQUAL)
		body = _parse_expr(0)

	return {params = params, body = body}


# ── Layout helpers ──────────────────────────────────────────────────────────
#
# Inside grouping constructs (parens, brackets) the layout rule must be
# suspended so that line breaks within an expression don't fool the parser
# into thinking a new top-level declaration has started.

func _suspend_layout() -> int:
	var prev = _layout_break_col
	_layout_break_col = 0
	return prev


func _restore_layout(prev: int) -> void:
	_layout_break_col = prev


func _should_layout_break(tok: Token) -> bool:
	return _layout_break_col > 0 \
			and tok.column > 0 \
			and tok.column <= _layout_break_col \
			and tok.type != Token.Type.EOF


## Parses guarded alternatives:  | cond = expr  { | cond = expr }
## Desugared into a nested if-then-else chain.
func _parse_guarded_body() -> Expr:
	var guards: Array[Dictionary] = []

	while _match_token(Token.Type.PIPE):
		# `otherwise` and bare `true` are unconditional fallthrough guards.
		if (_check(Token.Type.ID) and _peek().value == "otherwise") \
				or _check(Token.Type.BOOL_T):
			_advance()
			_expect(Token.Type.EQUAL)
			guards.append({cond = null, body = _parse_expr(0)})
		else:
			var cond = _parse_expr(0)
			_expect(Token.Type.EQUAL)
			guards.append({cond = cond, body = _parse_expr(0)})

	# Build if-then-else chain right-to-left.
	var result: Expr = null
	for i in range(guards.size() - 1, -1, -1):
		var g = guards[i]
		if g.cond == null:
			result = g.body
		elif result == null:
			result = Ctrl.If.new(g.cond, g.body, _make_error_expr("Non-exhaustive guards"))
		else:
			result = Ctrl.If.new(g.cond, g.body, result)

	return result


## Returns the [Expr] that should be bound to [param name] — i.e. the value
## side of a top-level definition, without the surrounding LetRec wrapper.
## Multiple equations are merged into a single curried match expression.
func _build_definition_value(name: String, equations: Array[Dictionary]) -> Expr:
	# Simple case: single equation with no parameters → plain value.
	if equations.size() == 1 and equations[0].params.is_empty():
		return equations[0].body

	var arity: int = equations[0].params.size()

	# Generate fresh argument names __a0__, __a1__, ...
	var arg_names: Array[String] = []
	for i in range(arity):
		arg_names.append("__a%d__" % i)

	# Build Case branches.
	var branches: Array[Ctrl.Case] = []
	for eq in equations:
		var branch_pattern: Pattern
		if arity == 1:
			branch_pattern = eq.params[0]
		else:
			branch_pattern = Pattern.Tuple.new(eq.params)
		branches.append(Ctrl.Case.new(branch_pattern, eq.body))

	# Build scrutinee.
	var scrutinee: Expr
	if arity == 1:
		scrutinee = Expr.Var.new(arg_names[0])
	else:
		var elems: Array[Expr] = []
		for a in arg_names:
			elems.append(Expr.Var.new(a))
		scrutinee = Expr.Tuple.new(elems)

	# Wrap match in nested single-arg lambdas to get automatic currying.
	var body: Expr = Ctrl.Match.new(scrutinee, branches)
	for i in range(arg_names.size() - 1, -1, -1):
		body = Expr.Lambda.new([Pattern.Var.new(arg_names[i])], body)

	return body


# ════════════════════════════════════════════════════════════════════════════
# Pratt expression parser
# ════════════════════════════════════════════════════════════════════════════

func _parse_expr(min_bp: int) -> Expr:
	var left: Expr = _parse_nud()

	while true:
		var tok     = _peek()
		# Layout rule: a token at column 1 (or shallower than the active
		# layout column) starts a new declaration — stop extending the
		# current expression instead of swallowing it.
		if _should_layout_break(tok):
			break

		var left_bp = _lbp(tok)
		if left_bp <= min_bp:
			break

		if left_bp == APP_BP:
			left = _parse_application(left)
		else:
			_advance()
			left = _parse_led(left, tok)

	return left


# ── NUD: atoms, prefix operators, and keyword expressions ───────────────────

func _parse_nud() -> Expr:
	var tok = _advance()

	match tok.type:
		# ── Atoms ──────────────────────────────────────────────────────
		Token.Type.INT:
			return Expr.Int.new(tok.value)

		Token.Type.BOOL_T:
			return Expr.Bool.new(true)

		Token.Type.BOOL_F:
			return Expr.Bool.new(false)

		Token.Type.ID:
			return Expr.Var.new(tok.value)

		# ── Prefix logical negation: !expr ────────────────────────────
		Token.Type.NOT:
			return Operator.Negate.new(_parse_expr(PREFIX_BP))

		# ── Unary minus: only valid directly before an integer literal.
		#    `f -3`  → App(f, Int(-3))
		#    `x - 3` → Sub(x, Int(3))  — handled by LED via the BP table
		Token.Type.MINUS:
			if _check(Token.Type.INT):
				return Expr.Int.new(-_advance().value)
			_error("Unary minus is only supported before integer literals. "
				 + "Use (0 - expr) for general negation.")
			return null

		# ── Parenthesised expression, tuple, or operator section ────────
		Token.Type.LPAREN:
			return _parse_paren_expr()

		# ── List literal, range, or list comprehension ──────────────────
		Token.Type.LBRACK:
			return _parse_bracket_expr()

		# ── Lambda: \p1 p2 -> body ──────────────────────────────────────
		Token.Type.LAMBDA:
			return _parse_lambda()

		# ── if-then-else ────────────────────────────────────────────────
		Token.Type.IF:
			return _parse_if()

		# ── let / let rec ───────────────────────────────────────────────
		Token.Type.LET:
			return _parse_let()

		# ── match-with ──────────────────────────────────────────────────
		Token.Type.MATCH:
			return _parse_match()

		_:
			_error("Unexpected token '%s'" % tok)
			return null


# ── LED: infix operators ─────────────────────────────────────────────────────

func _parse_led(left: Expr, op: Token) -> Expr:
	var right: Expr = _parse_expr(_rbp_for(op))

	match op.type:
		Token.Type.PLUS:    return Operator.Add.new(left, right)
		Token.Type.MINUS:   return Operator.Sub.new(left, right)
		Token.Type.MULT:    return Operator.Mult.new(left, right)
		Token.Type.DIV:     return Operator.Div.new(left, right)
		Token.Type.MOD:     return Operator.Mod.new(left, right)
		Token.Type.LT:      return Operator.LesserThan.new(left, right)
		Token.Type.GT:      return Operator.GreaterThan.new(left, right)
		Token.Type.LTE:     return Operator.LessThanOrEqual.new(left, right)
		Token.Type.GTE:     return Operator.GreaterThanOrEqual.new(left, right)
		Token.Type.EQ:      return Operator.Equal.new(left, right)
		Token.Type.NEQ:     return Operator.NotEqual.new(left, right)
		Token.Type.AND:     return Operator.And.new(left, right)
		Token.Type.OR:      return Operator.Or.new(left, right)
		Token.Type.CONS:    return Operator.Cons.new(left, right)
		Token.Type.CONCAT:  return Operator.Append.new(left, right)
		Token.Type.DOT:     return Operator.Dot.new(left, right)
		_:
			_error("Unknown infix operator '%s'" % op)
			return null


# ── Application: collect adjacent argument atoms into one App node ───────────
#
#   f a b c  →  App(f, [a, b, c])
#
# _parse_nud() is called per argument (not _parse_expr) so we only consume
# true atoms and parenthesised groups, never infix operators.

func _parse_application(func_expr: Expr) -> Expr:
	var args: Array[Expr] = []
	while _can_start_expr(_peek()):
		# Don't pull a column-1 identifier in as another argument — it's the
		# start of the next declaration, not part of this application.
		if _should_layout_break(_peek()):
			break
		args.append(_parse_nud())
	if args.is_empty():
		return func_expr
	return Expr.App.new(func_expr, args)


# ════════════════════════════════════════════════════════════════════════════
# Specialised sub-parsers
# ════════════════════════════════════════════════════════════════════════════

# ── ( ... ) : grouped expression, tuple, or operator section ────────────────

# helper used only by _parse_paren_expr.  We need a variant of
# _parse_expr that will stop *before* a trailing binary operator when that
# operator is immediately followed by a closing parenthesis.  This allows
# right‑section syntax "(expr op)" to be recognised without letting
# _parse_expr eat the operator and then crash trying to parse its missing
# right-hand side.
func _parse_expr_no_trailing_op(min_bp: int) -> Expr:
	var left: Expr = _parse_nud()
	while true:
		var tok = _peek()
		# if we see `op )` we should break; the operator belongs to a
		# potential right section rather than the current sub-expression.
		if _is_binary_op_token(tok) and _peek(1).type == Token.Type.RPAREN:
			break

		var left_bp = _lbp(tok)
		if left_bp <= min_bp:
			break

		if left_bp == APP_BP:
			left = _parse_application(left)
		else:
			_advance()
			left = _parse_led(left, tok)
		
	return left

func _parse_paren_expr() -> Expr:
	# Grouping suspends the layout rule: a line break inside `( ... )` is
	# just whitespace, not a new declaration boundary.
	var saved = _suspend_layout()
	var result = _parse_paren_expr_inner()
	_restore_layout(saved)
	return result


func _parse_paren_expr_inner() -> Expr:
	# Unit: ()
	if _check(Token.Type.RPAREN):
		_advance()
		return Expr.Tuple.new([])

	# Operator section with a leading operator token: (+), (*3)
	if _is_binary_op_token(_peek()):
		return _parse_operator_section_leading()

	# parse inner expression but avoid consuming a trailing operator that is
	# part of a right section (see helper above)
	var first = _parse_expr_no_trailing_op(0)

	# Right section: (expr op)  e.g. (1+)  →  \__s__ -> 1 + __s__
	if _is_binary_op_token(_peek()) and _peek(1).type == Token.Type.RPAREN:
		var op = _advance()
		_advance()  # consume )
		var body = _make_infix_node(op, first, Expr.Var.new("__s__"))
		return Expr.Lambda.new([Pattern.Var.new("__s__")], body)

	# Tuple: (expr, expr, ...)
	if _check(Token.Type.COMMA):
		var elements: Array[Expr] = [first]
		while _match_token(Token.Type.COMMA):
			elements.append(_parse_expr(0))
		_expect(Token.Type.RPAREN)
		return Expr.Tuple.new(elements)

	# Plain grouped expression.
	_expect(Token.Type.RPAREN)
	return first


## Parses a leading-operator section: (op) or (op expr).
##   (+)   →  \__x__ __y__ -> __x__ + __y__
##   (* 3) →  \__x__       -> __x__ * 3
func _parse_operator_section_leading() -> Expr:
	var op = _advance()
	var body: Expr

	# (op) — fully unapplied, 2-arg lambda.
	if _check(Token.Type.RPAREN):
		_advance()
		body = _make_infix_node(op, Expr.Var.new("__x__"), Expr.Var.new("__y__"))
		return Expr.Lambda.new([Pattern.Var.new("__x__"), Pattern.Var.new("__y__")], body)

	# (op expr) — left section, 1-arg lambda  \__x__ -> __x__ `op` expr.
	var right = _parse_expr(0)
	_expect(Token.Type.RPAREN)
	body = _make_infix_node(op, Expr.Var.new("__x__"), right)
	return Expr.Lambda.new([Pattern.Var.new("__x__")], body)


# ── [ ... ] : empty list, list literal, range, or list comprehension ─────────

func _parse_bracket_expr() -> Expr:
	# Brackets suspend the layout rule for the same reason parens do.
	var saved = _suspend_layout()
	var result = _parse_bracket_expr_inner()
	_restore_layout(saved)
	return result


func _parse_bracket_expr_inner() -> Expr:
	# []
	if _check(Token.Type.RBRACK):
		_advance()
		return Expr.Nil.new()

	var first = _parse_expr(0)

	# [expr | generators]  — list comprehension
	if _match_token(Token.Type.PIPE):
		return _parse_list_comprehension(first)

	# [expr ..]  or  [expr .. expr]  — lazy range
	if _match_token(Token.Type.DOTDOT):
		var end_expr: Expr = null
		if not _check(Token.Type.RBRACK):
			end_expr = _parse_expr(0)
		_expect(Token.Type.RBRACK)
		return Expr.LstRange.new(first, end_expr)

	# [expr, expr, ...]  — list literal, desugared to Expr.List chain.
	var elements: Array[Expr] = [first]
	while _match_token(Token.Type.COMMA):
		elements.append(_parse_expr(0))
	_expect(Token.Type.RBRACK)

	var result: Expr = Expr.Nil.new()
	for i in range(elements.size() - 1, -1, -1):
		result = Expr.List.new(elements[i], result)
	return result


## Parses generators and guards after the pipe in [body | gen, gen, ...].
##
## Three generator forms (per LANG.md):
##   pattern <- expr       — draw from a list
##   expr                  — boolean guard
##   let identifier = expr — local binding
##
## Desugared into nested map / filter / concat calls around the body.
func _parse_list_comprehension(body: Expr) -> Expr:
	var generators: Array[Dictionary] = []
	generators.append(_parse_generator())
	while _match_token(Token.Type.COMMA):
		generators.append(_parse_generator())
	_expect(Token.Type.RBRACK)

	# Desugar right-to-left so the innermost generator wraps the body first.
	var result: Expr = body
	for i in range(generators.size() - 1, -1, -1):
		var g = generators[i]
		match g.kind:
			"draw":
				var lam    = Expr.Lambda.new([g.pattern], result)
				# call prelude map directly rather than using a variable lookup
				var mapped = Expr.NativeCall.new(Prelude.map, [lam, g.source])
				# Flatten the outer list produced by map when there are
				# inner generators (each body is itself a list).
				if i < generators.size() - 1:
				# foldr takes three arguments: function, initial acc, list
					result = Expr.NativeCall.new(Prelude.foldr, [_make_concat_lambda(), Expr.Nil.new(), mapped])
				result = mapped

			"guard":
				result = Ctrl.If.new(g.cond, result, Expr.Nil.new())

			"let":
				result = Ctrl.Let.new(g.name, g.value_expr, result)

	return result


func _parse_generator() -> Dictionary:
	# let identifier = expr
	if _check(Token.Type.LET):
		_advance()
		var id = _expect(Token.Type.ID).value
		_expect(Token.Type.EQUAL)
		return {kind = "let", name = id, value_expr = _parse_expr(0)}

	# Parse an expression; if '<-' follows it was really a pattern.
	var first = _parse_expr(0)
	if _match_token(Token.Type.LARROW):
		return {kind = "draw", pattern = _expr_to_pattern(first), source = _parse_expr(0)}

	return {kind = "guard", cond = first}


# ── \p1 p2 ... -> body ───────────────────────────────────────────────────────

func _parse_lambda() -> Expr:
	var params: Array[Pattern] = []
	while not _check(Token.Type.RARROW) and not _check(Token.Type.EOF):
		params.append(_parse_pattern())
	_expect(Token.Type.RARROW)
	return Expr.Lambda.new(params, _parse_expr(0))


# ── if expr then expr else expr ──────────────────────────────────────────────

func _parse_if() -> Expr:
	var cond  = _parse_expr(0)
	_expect(Token.Type.THEN)
	var then_ = _parse_expr(0)
	_expect(Token.Type.ELSE)
	return Ctrl.If.new(cond, then_, _parse_expr(0))


# ── let [rec] identifier [params] = expr in expr ────────────────────────────
#
# `let [rec] f x = body in expr` is the only local-binding form. For a
# standalone, file-level definition, use the layout-based top-level form:
#
#   f x = body
#
# which is desugared by [method _parse_definition_record] / [method
# _build_definition_value].

func _parse_let() -> Expr:
	var is_rec = _match_token(Token.Type.REC)
	var name   = _expect(Token.Type.ID).value

	var params: Array[Pattern] = []
	while not _check(Token.Type.EQUAL) and not _check(Token.Type.IN) \
			and not _check(Token.Type.EOF):
		params.append(_parse_pattern())

	_expect(Token.Type.EQUAL)
	var value: Expr = _parse_expr(0)

	if not params.is_empty():
		value = Expr.Lambda.new(params, value)

	_expect(Token.Type.IN)
	var body: Expr = _parse_expr(0)

	if is_rec:
		return Ctrl.LetRec.new(name, value, body)
	return Ctrl.Let.new(name, value, body)


# ── match expr with [|] pattern = expr { | pattern = expr } ─────────────────

func _parse_match() -> Expr:
	var scrutinee = _parse_expr(0)
	_expect(Token.Type.WITH)
	_match_token(Token.Type.PIPE)  # leading pipe is optional

	var branches: Array[Ctrl.Case] = []
	branches.append(_parse_case_branch())
	while _match_token(Token.Type.PIPE):
		branches.append(_parse_case_branch())

	return Ctrl.Match.new(scrutinee, branches)


func _parse_case_branch() -> Ctrl.Case:
	var pattern = _parse_pattern()
	_expect(Token.Type.EQUAL)
	return Ctrl.Case.new(pattern, _parse_expr(0))


# ════════════════════════════════════════════════════════════════════════════
# Pattern parser
# ════════════════════════════════════════════════════════════════════════════
#
# Patterns appear in: lambda heads, case branches, equation parameters.
#
#   pattern = identifier | literal
#           | "(" pattern {"," pattern} ")"
#           | "[" pattern {"," pattern} "]" | "[]"
#           | pattern ":" pattern
#           | "_"
#
# Cons (:) is right-associative at pattern level.

func _parse_pattern() -> Pattern:
	var base = _parse_pattern_atom()

	if _check(Token.Type.CONS):
		_advance()
		return Pattern.Cons.new(base, _parse_pattern())  # right-recursive

	return base


func _parse_pattern_atom() -> Pattern:
	var tok = _advance()

	match tok.type:
		Token.Type.UNDER:
			return Pattern.Wildcard.new()

		Token.Type.INT:
			return Pattern.Int.new(tok.value)

		Token.Type.BOOL_T:
			return Pattern.Bool.new(true)

		Token.Type.BOOL_F:
			return Pattern.Bool.new(false)

		Token.Type.MINUS:
			return Pattern.Int.new(-_expect(Token.Type.INT).value)

		Token.Type.ID:
			return Pattern.Var.new(tok.value)

		# Tuple pattern (p, p, ...) or grouped pattern (p)
		Token.Type.LPAREN:
			if _check(Token.Type.RPAREN):
				_advance()
				return Pattern.Tuple.new([])  # unit

			var first = _parse_pattern()

			if _check(Token.Type.COMMA):
				var pats: Array[Pattern] = [first]
				while _match_token(Token.Type.COMMA):
					pats.append(_parse_pattern())
				_expect(Token.Type.RPAREN)
				return Pattern.Tuple.new(pats)

			_expect(Token.Type.RPAREN)
			return first  # grouped, not a tuple

		# List pattern [p, p, ...] or []
		Token.Type.LBRACK:
			if _check(Token.Type.RBRACK):
				_advance()
				return Pattern.List.new([])

			var pats: Array[Pattern] = [_parse_pattern()]
			while _match_token(Token.Type.COMMA):
				pats.append(_parse_pattern())
			_expect(Token.Type.RBRACK)
			return Pattern.List.new(pats)

		_:
			_error("Expected a pattern, got '%s'" % tok)
			return null


# ════════════════════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════════════════════

# ── Token navigation ─────────────────────────────────────────────────────────

func _peek(offset: int = 0) -> Token:
	var i = _pos + offset
	if i >= _tokens.size():
		return Token.new(Token.Type.EOF)
	return _tokens[i]


func _advance() -> Token:
	var t = _tokens[_pos]
	_pos += 1
	return t


func _check(type: Token.Type) -> bool:
	return _peek().type == type


func _match_token(type: Token.Type) -> bool:
	if _check(type):
		_advance()
		return true
	return false


func _expect(type: Token.Type) -> Token:
	if not _check(type):
		var got = _peek()
		push_error("Parser Error [line %d, col %d]: Expected %s, got %s"
				   % [got.line, got.column, type, got])
		return Token.new(Token.Type.ERROR)
	return _advance()


func _error(msg: String) -> void:
	var t = _peek()
	push_error("Parser Error [line %d, col %d]: %s" % [t.line, t.column, msg])


# ── Binding-power look-up ────────────────────────────────────────────────────

func _lbp(token: Token) -> int:
	if token.type in BP:
		return BP[token.type][0]
	if _can_start_expr(token):
		return APP_BP
	return 0


func _rbp_for(token: Token) -> int:
	if token.type in BP:
		return BP[token.type][1]
	return 0


# ── Token classification ──────────────────────────────────────────────────────

func _can_start_expr(token: Token) -> bool:
	return token.type in [
		Token.Type.INT,
		Token.Type.BOOL_T,
		Token.Type.BOOL_F,
		Token.Type.ID,
		Token.Type.LPAREN,
		Token.Type.LBRACK,
	]


func _is_binary_op_token(token: Token) -> bool:
	return token.type in [
		Token.Type.PLUS,  Token.Type.MINUS, Token.Type.MULT,
		Token.Type.DIV,   Token.Type.MOD,   Token.Type.LT,
		Token.Type.GT,    Token.Type.LTE,   Token.Type.GTE,
		Token.Type.EQ,    Token.Type.NEQ,   Token.Type.AND,
		Token.Type.OR,    Token.Type.CONS,  Token.Type.CONCAT,
		Token.Type.DOT,
	]


# ── AST construction helpers ─────────────────────────────────────────────────

## Builds the correct binary AST node for [param op] without consuming tokens.
func _make_infix_node(op: Token, left: Expr, right: Expr) -> Expr:
	match op.type:
		Token.Type.PLUS:    return Operator.Add.new(left, right)
		Token.Type.MINUS:   return Operator.Sub.new(left, right)
		Token.Type.MULT:    return Operator.Mult.new(left, right)
		Token.Type.DIV:     return Operator.Div.new(left, right)
		Token.Type.MOD:     return Operator.Mod.new(left, right)
		Token.Type.LT:      return Operator.LesserThan.new(left, right)
		Token.Type.GT:      return Operator.GreaterThan.new(left, right)
		Token.Type.LTE:     return Operator.LessThanOrEqual.new(left, right)
		Token.Type.GTE:     return Operator.GreaterThanOrEqual.new(left, right)
		Token.Type.EQ:      return Operator.Equal.new(left, right)
		Token.Type.NEQ:     return Operator.NotEqual.new(left, right)
		Token.Type.AND:     return Operator.And.new(left, right)
		Token.Type.OR:      return Operator.Or.new(left, right)
		Token.Type.CONS:    return Operator.Cons.new(left, right)
		Token.Type.CONCAT:  return Operator.Append.new(left, right)
		Token.Type.DOT:     return Operator.Dot.new(left, right)
		_:
			_error("Unknown operator '%s'" % op)
			return null


## Produces  \__acc__ __x__ -> __acc__ ++ __x__  for comprehension desugaring.
func _make_concat_lambda() -> Expr:
	var body = Operator.Append.new(Expr.Var.new("__acc__"), Expr.Var.new("__x__"))
	return Expr.Lambda.new(
		[Pattern.Var.new("__acc__"), Pattern.Var.new("__x__")],
		body
	)


## Produces a match with no branches, which will push_error at runtime.
func _make_error_expr(msg: String) -> Expr:
	push_error("Parser: %s" % msg)
	return Ctrl.Match.new(Expr.Bool.new(false), [])


## Best-effort conversion of a simple expression back into a pattern.
## Used when a list-comprehension generator is parsed as an expression
## before the '<-' token is discovered.
func _expr_to_pattern(e: Expr) -> Pattern:
	if e is Expr.Var:
		if e._name == "_":
			return Pattern.Wildcard.new()
		return Pattern.Var.new(e._name)

	if e is Expr.Int:
		return Pattern.Int.new(e._value)

	if e is Expr.Bool:
		return Pattern.Bool.new(e._value)

	if e is Expr.Tuple:
		var pats: Array[Pattern] = []
		for el in e._elements:
			pats.append(_expr_to_pattern(el))
		return Pattern.Tuple.new(pats)

	_error("Cannot convert expression to pattern in list comprehension generator")
	return Pattern.Wildcard.new()
