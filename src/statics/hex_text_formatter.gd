class_name HexTextFormatter
extends RefCounted
## Pure text post-processing for the hex editor's generated program
## output. Lives outside the editor so the rules are obvious and
## independently testable.
##
## Two precedence-safe transforms:
##
##   • atom-paren stripping: `(red)` → `red`, `(5)` → `5`, `(-3)` → `-3`
##   • double-paren collapse: `((expr))` → `(expr)` (only when the
##     inner parens span exactly the inside of the outer pair)
##
## Both are idempotent; `clean` runs them to a fixpoint. Heavier
## cleanup (e.g. dropping outer parens around the top-level
## expression) needs precedence info and is deliberately not
## attempted here.

static func clean(text: String) -> String:
	var atom_re := RegEx.new()
	atom_re.compile("\\(\\s*(-?\\b\\d+\\b|\\b[a-zA-Z_]\\w*\\b)\\s*\\)")
	var prev := ""
	while text != prev:
		prev = text
		text = atom_re.sub(text, "$1", true)
		text = collapse_double_parens(text)
	return text


# Collapse `((…))` to `(…)` when the inner parens span exactly the inside
# of the outer pair. Uses a depth scan so nested structures like
# `((x) y)` are left alone.
static func collapse_double_parens(s: String) -> String:
	var i := 0
	while i < s.length() - 1:
		if s[i] != "(" or s[i + 1] != "(":
			i += 1
			continue
		var outer_close := matching_close(s, i)
		if outer_close == -1:
			return s
		if outer_close >= 2 and s[outer_close - 1] == ")":
			var inner_close := matching_close(s, i + 1)
			if inner_close == outer_close - 1:
				s = s.substr(0, i) + s.substr(i + 1, outer_close - i - 1) + s.substr(outer_close + 1)
				continue  # re-scan from same position
		i += 1
	return s


# Index of the `)` that matches `s[open_idx] == '('`, or -1 if none.
static func matching_close(s: String, open_idx: int) -> int:
	var depth := 0
	for j in range(open_idx, s.length()):
		var c := s[j]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return j
	return -1
