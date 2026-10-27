extends GutTest

## Unit tests exercising the Lexer implementation and edge cases.

func _token_types(src: String) -> Array:
	var toks = Lexer.lex(src)
	var types: Array = []
	for t in toks:
		types.append(t.type)
	return types

func test_empty_input():
	var toks = Lexer.lex("")
	assert_eq(toks.size(), 1)
	assert_eq(toks[0].type, Token.Type.EOF)

func test_simple_integer_and_identifier():
	var toks = Lexer.lex("123 abc")
	assert_eq(toks.size(), 3)  # INT, ID, EOF
	assert_eq(toks[0].type, Token.Type.INT)
	assert_eq(toks[0].value, 123)
	assert_eq(toks[1].type, Token.Type.ID)
	assert_eq(toks[1].value, "abc")

func test_number_followed_by_letters():
	# digits should stop at first non-digit, then identifier created
	var toks = Lexer.lex("123abc")
	assert_eq(toks.size(), 3)
	assert_eq(toks[0].type, Token.Type.INT)
	assert_eq(toks[0].value, 123)
	assert_eq(toks[1].type, Token.Type.ID)
	assert_eq(toks[1].value, "abc")

func test_keywords_vs_identifiers():
	var code = "if then else match with let rec in true false foo"
	var types = _token_types(code)
	# last token (foo) should be ID, plus EOF at end
	assert_eq(types, [Token.Type.IF, Token.Type.THEN, Token.Type.ELSE,
					   Token.Type.MATCH, Token.Type.WITH, Token.Type.LET,
					   Token.Type.REC, Token.Type.IN, Token.Type.BOOL_T,
					   Token.Type.BOOL_F, Token.Type.ID, Token.Type.EOF])

func test_keyword_substrings_are_identifiers():
	var toks = Lexer.lex("ifx theny")
	assert_eq(toks[0].type, Token.Type.ID)
	assert_eq(toks[0].value, "ifx")
	assert_eq(toks[1].type, Token.Type.ID)
	assert_eq(toks[1].value, "theny")
	assert_eq(toks[2].type, Token.Type.EOF)

func test_symbol_tokens():
	var code = "+ - * / % < <= > >= == != && || : ++ .. -> <- |_ ()[] ,"
	# note: pipe alone followed by space becomes PIPE token; '|_' should
	# generate PIPE then UNDER.
	var types = _token_types(code)
	var expected = [Token.Type.PLUS, Token.Type.MINUS,
					Token.Type.MULT, Token.Type.DIV, Token.Type.MOD,
					Token.Type.LT, Token.Type.LTE, Token.Type.GT,
					Token.Type.GTE, Token.Type.EQ, Token.Type.NEQ,
					Token.Type.AND, Token.Type.OR,
					Token.Type.CONS, Token.Type.CONCAT,
					Token.Type.DOTDOT,
					Token.Type.RARROW, Token.Type.LARROW,
					Token.Type.PIPE, Token.Type.UNDER,
					Token.Type.LPAREN, Token.Type.RPAREN,
					Token.Type.LBRACK, Token.Type.RBRACK,
					Token.Type.COMMA, Token.Type.EOF]
	assert_eq(types, expected)

func test_pipe_underscore_pair():
	var toks = Lexer.lex("|_")
	assert_eq(toks[0].type, Token.Type.PIPE)
	assert_eq(toks[1].type, Token.Type.UNDER)
	assert_eq(toks[2].type, Token.Type.EOF)

func test_underscore_handling():
	var toks = Lexer.lex("_ _foo foo_")
	assert_eq(toks[0].type, Token.Type.UNDER)
	assert_eq(toks[1].type, Token.Type.ID)
	assert_eq(toks[1].value, "_foo")
	assert_eq(toks[2].type, Token.Type.ID)
	assert_eq(toks[2].value, "foo_")
	assert_eq(toks[3].type, Token.Type.EOF)

func test_line_comment_skipped():
	var toks = Lexer.lex("1 -- this is a comment\n2")
	assert_eq(toks[0].type, Token.Type.INT)
	assert_eq(toks[0].value, 1)
	assert_eq(toks[1].type, Token.Type.INT)
	assert_eq(toks[1].value, 2)
	assert_eq(toks[2].type, Token.Type.EOF)

func test_nested_block_comments_are_ignored():
	var src = "1 {- outer {- inner -} still -} 2"
	var toks = Lexer.lex(src)
	assert_eq(toks[0].type, Token.Type.INT)
	assert_eq(toks[0].value, 1)
	assert_eq(toks[1].type, Token.Type.INT)
	assert_eq(toks[1].value, 2)
	assert_eq(toks[2].type, Token.Type.EOF)

func test_unterminated_block_comment_triggers_error():
	var toks = Lexer.lex("{- no end")
	# lexer will still eventually return EOF
	assert_eq(toks.back().type, Token.Type.EOF)
	assert_push_error("Lexer Error: Unterminated block comment")

func test_illegal_character_generates_error_token():
	var toks = Lexer.lex("&")
	assert_eq(toks.size(), 1)
	assert_eq(toks[0].type, Token.Type.ERROR)
	assert_eq(toks[0].value, "'&' must be '&&'")
