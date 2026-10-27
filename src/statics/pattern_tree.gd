class_name PatternTree
extends RefCounted
## Structured model behind the match-config pattern tree.
##
## A pattern is a tree of plain Dictionaries so it round-trips trivially
## and stays decoupled from the Tree widget that edits it:
##
##   {"kind": "slot"}                       unfilled — renders an option button
##   {"kind": "wild"}                       `_`
##   {"kind": "int",  "value": "0"}         integer literal
##   {"kind": "bool", "value": "true"}      boolean literal
##   {"kind": "var",  "value": "red"}       variable binding (palette name)
##   {"kind": "cons", "children": [h, t]}   `(h : t)`
##   {"kind": "tuple","children": [...]}    `(a, b, …)`
##   {"kind": "list", "children": [...]}    `[a, b, …]`  / `[]`
##
## The canonical pattern STRING remains the source of truth elsewhere
## (save format, scope queries, text emission), so the editor only ever
## stores `to_source(node)`. On reopen we `parse(str)` back into a tree.

## Selectable kinds, in option-button order. `slot` is the placeholder
## ("choose…") leaf; everything else is a concrete pattern.
const KINDS: Array = ["slot", "wild", "int", "bool", "var", "cons", "tuple", "list"]

## Tuples grow up to this many elements; lists are unbounded.
const MAX_TUPLE := 5


## Build a fresh node of `kind` with sensible defaults (compound kinds
## seed their minimum children as empty slots).
static func make(kind: String) -> Dictionary:
	match kind:
		"wild":
			return {"kind": "wild"}
		"int":
			return {"kind": "int", "value": "0"}
		"bool":
			return {"kind": "bool", "value": "true"}
		"var":
			return {"kind": "var", "value": _first_var_name()}
		"cons":
			return {"kind": "cons", "children": [make("slot"), make("slot")]}
		"tuple":
			return {"kind": "tuple", "children": [make("slot"), make("slot")]}
		"list":
			return {"kind": "list", "children": []}
		_:
			return {"kind": "slot"}


## Canonical pattern source for `node`. Unfilled slots read as `_` so the
## emitted text is always a valid pattern.
static func to_source(node: Dictionary) -> String:
	match String(node.get("kind", "slot")):
		"slot", "wild":
			return "_"
		"int":
			var v := String(node.get("value", "0")).strip_edges()
			return v if _is_int(v) else "0"
		"bool":
			return "true" if String(node.get("value", "true")) == "true" else "false"
		"var":
			var n := String(node.get("value", "")).strip_edges()
			return n if not n.is_empty() else "_"
		"cons":
			var ch: Array = node.get("children", [])
			var h := to_source(ch[0]) if ch.size() > 0 else "_"
			var t := to_source(ch[1]) if ch.size() > 1 else "_"
			return "(%s : %s)" % [h, t]
		"tuple":
			return "(%s)" % ", ".join(_child_sources(node))
		"list":
			return "[%s]" % ", ".join(_child_sources(node))
	return "_"


## Best-effort parse of a pattern string back into a tree. Mirrors the
## parser's grammar (cons is right-associative; parens group or tuple;
## brackets list). Anything unrecognised becomes a `var` leaf.
static func parse(s: String) -> Dictionary:
	var t := s.strip_edges()
	if t.is_empty():
		return make("slot")
	var colon := _find_top_level(t, ":".unicode_at(0))
	if colon >= 0:
		var left := t.substr(0, colon)
		var right := t.substr(colon + 1)
		return {"kind": "cons", "children": [_parse_atom(left), parse(right)]}
	return _parse_atom(t)


static func _parse_atom(s: String) -> Dictionary:
	var t := s.strip_edges()
	if t.is_empty():
		return make("slot")
	if t == "_":
		return {"kind": "wild"}
	if t == "true" or t == "false":
		return {"kind": "bool", "value": t}
	if _is_int(t):
		return {"kind": "int", "value": t}
	if t.begins_with("(") and _outer_balanced(t):
		var inner := t.substr(1, t.length() - 2).strip_edges()
		if inner.is_empty():
			return {"kind": "tuple", "children": []}
		var parts := _split_top_level(inner, ",".unicode_at(0))
		if parts.size() == 1:
			return parse(parts[0])  # grouped single pattern
		return {"kind": "tuple", "children": parts.map(func(p): return parse(p))}
	if t.begins_with("[") and _outer_balanced(t):
		var inner2 := t.substr(1, t.length() - 2).strip_edges()
		if inner2.is_empty():
			return {"kind": "list", "children": []}
		var parts2 := _split_top_level(inner2, ",".unicode_at(0))
		return {"kind": "list", "children": parts2.map(func(p): return parse(p))}
	return {"kind": "var", "value": t}


static func _child_sources(node: Dictionary) -> Array:
	var out: Array = []
	for c in node.get("children", []):
		out.append(to_source(c))
	return out


static func _first_var_name() -> String:
	if IdentifierPalette.user_count() > 0:
		return IdentifierPalette.name_of(0)
	return ""


static func _is_int(v: String) -> bool:
	return v.strip_edges().is_valid_int()


# Index of the first `sep` codepoint at bracket-depth 0, or -1. Both
# `()` and `[]` contribute to depth so separators inside a nested group
# are skipped.
static func _find_top_level(s: String, sep: int) -> int:
	var depth := 0
	for i in s.length():
		var ch := s.unicode_at(i)
		if ch == 40 or ch == 91:        # ( [
			depth += 1
		elif ch == 41 or ch == 93:      # ) ]
			depth -= 1
		elif depth == 0 and ch == sep:
			return i
	return -1


# Split `s` on `sep` at depth 0; never empty.
static func _split_top_level(s: String, sep: int) -> Array:
	var out: Array = []
	var depth := 0
	var start := 0
	for i in s.length():
		var ch := s.unicode_at(i)
		if ch == 40 or ch == 91:
			depth += 1
		elif ch == 41 or ch == 93:
			depth -= 1
		elif depth == 0 and ch == sep:
			out.append(s.substr(start, i - start))
			start = i + 1
	out.append(s.substr(start))
	return out


# True when the opening bracket at index 0 is closed only by the final
# character (so `(a):(b)` is NOT treated as a parenthesised whole).
static func _outer_balanced(s: String) -> bool:
	if s.length() < 2:
		return false
	var depth := 0
	for i in s.length():
		var ch := s.unicode_at(i)
		if ch == 40 or ch == 91:
			depth += 1
		elif ch == 41 or ch == 93:
			depth -= 1
			if depth == 0:
				return i == s.length() - 1
	return false
