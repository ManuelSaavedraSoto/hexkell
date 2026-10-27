class_name Lexer
extends RefCounted
## Lexer class for the language.
##
## Takes an input string and produces a list of tokens for the parser.

var _source: String
var _pos: int
var _line: int
var _col: int
var _start_col: int  # column at the start of the current token


static func lex(source: String) -> Array[Token]:
	return Lexer.new(source).tokenize()


func _init(source: String) -> void:
	_source = source
	_pos = 0
	_line = 1
	_col = 1


# ── Public API ──────────────────────────────────────────────────────────────

func tokenize() -> Array[Token]:
	var tokens: Array[Token] = []
	while true:
		var tok = _next_token()
		tokens.append(tok)
		if tok.type == Token.Type.EOF or tok.type == Token.Type.ERROR:
			break
	return tokens


# ── Internal navigation ─────────────────────────────────────────────────────

func _peek(offset: int = 0) -> String:
	var i = _pos + offset
	if i >= _source.length():
		return ""
	return _source[i]

func _advance() -> String:
	var c = _source[_pos]
	_pos += 1
	if c == "\n":
		_line += 1
		_col = 1
	else:
		_col += 1
	return c

func _at_end() -> bool:
	return _pos >= _source.length()

func _make(type: Token.Type, value: Variant = null) -> Token:
	return Token.new(type, value, _line, _start_col)

func _error(msg: String) -> Token:
	return Token.new(Token.Type.ERROR, msg, _line, _start_col)


# ── Core loop ───────────────────────────────────────────────────────────────

func _next_token() -> Token:
	_skip_whitespace_and_comments()

	if _at_end():
		return _make(Token.Type.EOF)

	_start_col = _col
	var c = _peek()

	if _is_digit(c):
		return _read_int()

	# underscore is ambiguous: standalone wildcard or start of identifier
	# but the symbol logic handles both cases, so handle it before
	# treating underscores as alphabetic identifiers.
	if c == "_":
		return _read_symbol()

	if _is_alpha(c):
		return _read_identifier_or_keyword()

	# Symbols (ordered so multi-char tokens are checked before single-char)
	return _read_symbol()


# ── Whitespace & comments ───────────────────────────────────────────────────

func _skip_whitespace_and_comments() -> void:
	while not _at_end():
		var c = _peek()

		# Whitespace
		if c in [" ", "\t", "\r", "\n"]:
			_advance()

		# Line comment: --
		elif c == "-" and _peek(1) == "-":
			while not _at_end() and _peek() != "\n":
				_advance()

		# Block comment: {- ... -}
		elif c == "{" and _peek(1) == "-":
			_advance(); _advance()  # consume {-
			_skip_block_comment()

		else:
			break


func _skip_block_comment() -> void:
	var depth = 1
	while not _at_end() and depth > 0:
		if _peek() == "{" and _peek(1) == "-":
			_advance(); _advance()
			depth += 1
		elif _peek() == "-" and _peek(1) == "}":
			_advance(); _advance()
			depth -= 1
		else:
			_advance()

	if depth > 0:
		push_error("Lexer Error: Unterminated block comment at line %d" % _line)


# ── Integer literals ────────────────────────────────────────────────────────

func _read_int() -> Token:
	var start = _pos
	while not _at_end() and _is_digit(_peek()):
		_advance()
	var text = _source.substr(start, _pos - start)
	return _make(Token.Type.INT, int(text))


# ── Identifiers & keywords ──────────────────────────────────────────────────

const KEYWORDS: Dictionary = {
	"if":    Token.Type.IF,
	"then":  Token.Type.THEN,
	"else":  Token.Type.ELSE,
	"match": Token.Type.MATCH,
	"with":  Token.Type.WITH,
	"let":   Token.Type.LET,
	"rec":   Token.Type.REC,
	"in":    Token.Type.IN,
	"do":    Token.Type.DO,
	"true":  Token.Type.BOOL_T,
	"false": Token.Type.BOOL_F,
}

func _read_identifier_or_keyword() -> Token:
	var start = _pos
	while not _at_end() and _is_alnum(_peek()):
		_advance()
	var text = _source.substr(start, _pos - start)

	if text in KEYWORDS:
		return _make(KEYWORDS[text])

	return _make(Token.Type.ID, text)


# ── Symbols ─────────────────────────────────────────────────────────────────

func _read_symbol() -> Token:
	var c = _advance()

	match c:
		"+":
			if _peek() == "+":
				_advance(); return _make(Token.Type.CONCAT)   # ++
			return _make(Token.Type.PLUS)

		"-":
			if _peek() == ">":
				_advance(); return _make(Token.Type.RARROW)   # ->
			return _make(Token.Type.MINUS)

		"*":  return _make(Token.Type.MULT)
		"/":  return _make(Token.Type.DIV)
		"%":  return _make(Token.Type.MOD)

		"<":
			if _peek() == "=":
				_advance(); return _make(Token.Type.LTE)      # <=
			if _peek() == "-":
				_advance(); return _make(Token.Type.LARROW)   # <-
			return _make(Token.Type.LT)

		">":
			if _peek() == "=":
				_advance(); return _make(Token.Type.GTE)      # >=
			return _make(Token.Type.GT)

		"=":
			if _peek() == "=":
				_advance(); return _make(Token.Type.EQ)       # ==
			return _make(Token.Type.EQUAL)

		"!":
			if _peek() == "=":
				_advance(); return _make(Token.Type.NEQ)      # !=
			return _make(Token.Type.NOT)

		"&":
			if _peek() == "&":
				_advance(); return _make(Token.Type.AND)      # &&
			return _error("'&' must be '&&'")

		"|":
			if _peek() == "|":
				_advance(); return _make(Token.Type.OR)       # ||
			return _make(Token.Type.PIPE)

		".":
			if _peek() == ".":
				_advance(); return _make(Token.Type.DOTDOT)   # ..
			return _make(Token.Type.DOT)

		":":
			return _make(Token.Type.CONS)

		"\\":  return _make(Token.Type.LAMBDA)
		"(":   return _make(Token.Type.LPAREN)
		")":   return _make(Token.Type.RPAREN)
		"[":   return _make(Token.Type.LBRACK)
		"]":   return _make(Token.Type.RBRACK)
		",":   return _make(Token.Type.COMMA)
		"_":
			# Could be start of an identifier like _foo, or a wildcard
			if not _at_end() and _is_alnum(_peek()):
				# treat _foo as a regular identifier
				var start = _pos - 1
				while not _at_end() and _is_alnum(_peek()):
					_advance()
				return _make(Token.Type.ID, _source.substr(start, _pos - start))
			return _make(Token.Type.UNDER)

		_:
			return _error("Unexpected character '%s'" % c)


# ── Character classification ─────────────────────────────────────────────────

func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"

func _is_alpha(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

func _is_alnum(c: String) -> bool:
	return _is_alpha(c) or _is_digit(c)
