class_name Token
extends RefCounted
## Token class representing a single token produced by the lexer.
##
## Each token has a type, an optional value, for literals and identifiers,
## and position information (line and column) for error reporting.

enum Type {
	# Literals
	INT,    ## Integer token.
	BOOL_F, ## Boolean `false` token.
	BOOL_T, ## Boolean `true` token.
	
	# Identifiers
	ID,     ## Identifier token.
	
	# Reserved Keywords
	# Control Flow
	IF,     ## `if` token.
	THEN,   ## `then` token.
	ELSE,   ## `else` token.
	MATCH,  ## `match` token.
	WITH,   ## `with` token.
	LET,	## `let` token.
	REC,    ## `rec` token.
	IN,     ## `in` token.
	DO,     ## `do` token — marks the explicit main declaration of a module.
	
	# Symbols
	PLUS,   ## `+` token.
	MINUS,  ## `-` token.
	MULT,   ## `*` token.
	DIV,    ## `/` token.
	MOD,	## `%` token.
	LT,	    ## `<` token.
	GT,     ## `>` token.
	NOT,	## `!` token.
	EQUAL,  ## `=` token.
	PIPE,   ## `|` token.
	LAMBDA, ## `\` token.
	DOT,    ## `.` token.
	CONS,   ## `:` token.
	EQ,     ## `==` token.
	LTE,    ## `<=` token.
	GTE,    ## `>=` token.
	NEQ,    ## `!=` token.
	AND,    ## `&&` token.
	OR,     ## `||` token.
	RARROW, ## `->` token.
	LARROW, ## `<-` token.
	CONCAT, ## `++` token.
	DOTDOT, ## `..` token.
	
	# Delimeters
	LPAREN,     ## `(` token.
	RPAREN,     ## `)` token.
	LBRACK,     ## `[` token.
	RBRACK,     ## `]` token.
	COMMA,      ## `,` token.
	UNDER,      ## `_` token.
	
	# Special
	EOF,    ## End of file token.
	ERROR   ## Error token, used for invalid tokens or lexing errors.
}

var type: Type
var value: Variant
var line: int
var column: int

func _init(t: Type, v:Variant = null, l:int = 0, c:int=0) -> void:
	type = t
	value = v
	line = l
	column = c

func _to_string() -> String:
	match type:
		Type.INT:
			return "INT(%s)" % str(value)
		Type.BOOL_F:
			return "BOOL_FALSE"
		Type.BOOL_T:
			return "BOOL_TRUE"
		Type.ID:
			return "ID(%s)" % str(value)
		Type.EOF:
			return "EOF"
		Type.IF:
			return "IF"
		Type.THEN:
			return "THEN"
		Type.ELSE:
			return "ELSE"
		Type.MATCH:
			return "MATCH"
		Type.WITH:
			return "WITH"
		Type.LET:
			return "LET"
		Type.REC:
			return "REC"
		Type.IN:
			return "IN"
		Type.DO:
			return "DO"
		Type.PLUS:
			return "PLUS"
		Type.MINUS:
			return "MINUS"
		Type.MULT:
			return "MULT"
		Type.DIV:
			return "DIV"
		Type.MOD:
			return "MOD"
		Type.LT:
			return "LT"
		Type.GT:
			return "GT"
		Type.NOT:
			return "NOT"
		Type.EQUAL:
			return "EQUAL"
		Type.PIPE:
			return "PIPE"
		Type.LAMBDA:
			return "LAMBDA"
		Type.DOT:
			return "DOT"
		Type.CONS:
			return "CONS"
		Type.EQ:
			return "EQ"
		Type.LTE:
			return "LTE"
		Type.GTE:
			return "GTE"
		Type.NEQ:
			return "NEQ"
		Type.AND:
			return "AND"
		Type.OR:
			return "OR"
		Type.RARROW:
			return "RARROW"
		Type.LARROW:
			return "LARROW"
		Type.CONCAT:
			return "CONCAT"
		Type.DOTDOT:
			return "DOTDOT"
		Type.LPAREN:
			return "LPAREN"
		Type.RPAREN:
			return "RPAREN"
		Type.LBRACK:
			return "LBRACK"
		Type.RBRACK:
			return "RBRACK"
		Type.COMMA:
			return "COMMA"
		Type.UNDER:
			return "UNDER"
		Type.ERROR:
			return "ERROR(%s)" % str(value)
		_:
			return "UNKNOWN"
