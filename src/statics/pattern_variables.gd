class_name PatternVariables
extends RefCounted
## Extract the identifier-binding names from a match-pattern
## string. Patterns like `(h:t)` bind `{h, t}`; `(a, b)` binds
## `{a, b}`; literal patterns (`0`, `red` when red is a value),
## the wildcard `_`, and `[]` bind nothing.
##
## Used by `IdentifierScope` to surface match-branch pattern
## variables as in-scope names within that branch's body.


# Return Array[String] — the palette identifier names introduced
# as bindings by `pattern`. Anything that isn't a palette name
# (literals, `_`, `[]`) is silently dropped. Duplicates collapse.
static func extract(pattern: String) -> Array:
	var out: Array = []
	var tokens: Array = _tokenize(pattern)
	for tok in tokens:
		var name: String = String(tok).strip_edges()
		if name.is_empty() or name == "_":
			continue
		if _is_palette_name(name) and not name in out:
			out.append(name)
	return out


# Flatten the pattern into a sequence of variable-position tokens.
# The grammar this needs to handle:
#   `_`                     → []
#   `0`, `red`, `[]`        → ["0"] / ["red"] / ["[]"]
#   `(h:t)`                 → ["h", "t"]
#   `(a, b)`, `(a, b, c)`   → ["a", "b"], ["a", "b", "c"]
#   `((a, b) : rest)`       → ["a", "b", "rest"]   (nested ok)
# Strategy: peel matching outer parens, then split on top-level
# `:` and `,` (skipping any that sit inside nested parens).
static func _tokenize(pattern: String) -> Array:
	var s: String = pattern.strip_edges()
	if s.is_empty():
		return []
	s = _strip_outer_parens(s)
	var parts: Array = _split_top_level(s, [":".unicode_at(0), ",".unicode_at(0)])
	if parts.size() == 1 and parts[0] == s:
		# Atomic — either a single identifier or a literal.
		return [s]
	var out: Array = []
	for part in parts:
		for sub in _tokenize(String(part)):
			out.append(sub)
	return out


static func _strip_outer_parens(s: String) -> String:
	if s.length() < 2:
		return s
	if not (s.begins_with("(") and s.ends_with(")")):
		return s
	# Confirm the leading `(` matches the trailing `)` so we don't
	# strip parens off something like `(a):(b)`.
	var depth: int = 0
	for i in s.length():
		var ch: int = s.unicode_at(i)
		if ch == 40:  # `(`
			depth += 1
		elif ch == 41:  # `)`
			depth -= 1
			if depth == 0 and i < s.length() - 1:
				return s
	return s.substr(1, s.length() - 2).strip_edges()


# Split `s` on any of the separator codepoints in `seps`, but only
# at paren-depth 0. Returns Array[String]; never empty.
static func _split_top_level(s: String, seps: Array) -> Array:
	var out: Array = []
	var depth: int = 0
	var start: int = 0
	for i in s.length():
		var ch: int = s.unicode_at(i)
		if ch == 40:
			depth += 1
		elif ch == 41:
			depth -= 1
		elif depth == 0 and ch in seps:
			out.append(s.substr(start, i - start).strip_edges())
			start = i + 1
	out.append(s.substr(start, s.length() - start).strip_edges())
	return out


static func _is_palette_name(name: String) -> bool:
	for i in IdentifierPalette.user_count():
		if name == IdentifierPalette.name_of(i):
			return true
	return false
