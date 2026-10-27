class_name IdentifierScope
extends RefCounted
## Lexical scope walker for the hex editor. Walks a hex node's
## ancestor levels (HexLevel chain) and collects identifier names
## emitted by each level's anchor — plus any reserved identifiers
## the current job exposes via `IdentifierPalette.set_exposed_reserved`.
##
## Used by the IdentRefHex sidebar to grey out names that aren't
## bound at the hex's current location, and by the editor's
## pre-flight validator to fail closed instead of letting a free
## identifier reach the runtime.


# Return the set of identifier names in scope at `hex`'s current
# level. Order is innermost-first (the immediately-enclosing
# binding before any outer one) so callers that care about
# shadowing can pick the first match; uniqueness is preserved.
static func names_in_scope(hex: HexNode) -> Array:
	var out: Array = []
	if hex == null:
		return out
	var lvl: HexLevel = hex.level
	while lvl != null:
		_collect_from_anchor(lvl.anchor, out)
		_collect_from_level_siblings(lvl, hex, out)
		var parent: HexNode = lvl.parent_hex
		lvl = parent.level if parent != null else null
	for r in IdentifierPalette.get_exposed_reserved():
		var s: String = String(r)
		if not s.is_empty() and not s in out:
			out.append(s)
	return out


# Pull every binding the anchor exposes into `out`. Anchors that
# emit single identifiers (Let, Definition's per-pattern slots)
# contribute their `emit_labels` verbatim. Anchors carrying compound
# patterns (MatchAnchor's `(h:t)`, `(a,b)`) — whose `emit_labels`
# OR `patterns` carry the raw pattern string — delegate to
# `PatternVariables.extract` so multi-binder patterns surface every
# variable they introduce.
static func _collect_from_anchor(anchor: HexNode, out: Array) -> void:
	if anchor == null:
		return
	if "emit_labels" in anchor:
		for label in anchor.emit_labels:
			_collect_label(String(label), out)
	if "patterns" in anchor:
		for pat in anchor.patterns:
			_collect_label(String(pat), out)


# Attempt to interpret `label` as a palette identifier name; if not
# a match, fall back to pattern parsing so multi-variable bindings
# (`(h:t)`, `(a, b)`) still surface every introduced name.
static func _collect_label(label: String, out: Array) -> void:
	if label.is_empty() or label in out:
		return
	for i in IdentifierPalette.user_count():
		if label == IdentifierPalette.name_of(i):
			out.append(label)
			return
	for name in PatternVariables.extract(label):
		_collect_binding(String(name), out)


# Wireless level-mate emitters: DefinitionHex (function name) and
# LetRecHex (recursive binding) broadcast their bound name into the
# level they sit in, not via an anchor. Walk the level's hexes and
# ask each one if it contributes a sibling-scope name. Skips
# `exclude` (the hex whose scope we're computing) and the level's
# anchor (already collected by `_collect_from_anchor`).
static func _collect_from_level_siblings(
		lvl: HexLevel, exclude: HexNode, out: Array) -> void:
	if lvl == null:
		return
	for h in lvl.hexes:
		if h == exclude or h == lvl.anchor:
			continue
		if h.has_method("sibling_scope_name"):
			_collect_label(String(h.sibling_scope_name()), out)


static func _collect_binding(name: String, out: Array) -> void:
	if name.is_empty() or name in out:
		return
	# Anchor emit_labels can carry pattern strings whole (e.g. the
	# user typed "_" or "0" into a Definition's pattern slot). Only
	# names that match a palette identifier are real bindings.
	for i in IdentifierPalette.user_count():
		if name == IdentifierPalette.name_of(i):
			out.append(name)
			return
