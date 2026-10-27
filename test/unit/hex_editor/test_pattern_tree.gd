extends GutTest
## PatternTree — the parse ↔ source model behind the match pattern Tree
## widget. The widget itself is exercised through the editor; this pins
## the pure model so the round trips can't silently drift.


func test_leaf_kinds_round_trip() -> void:
	for src in ["_", "0", "-3", "true", "false"]:
		assert_eq(PatternTree.to_source(PatternTree.parse(src)), src,
				"Leaf %s must round-trip" % src)


func test_variable_name_parses_as_var() -> void:
	var node := PatternTree.parse("red")
	assert_eq(node["kind"], "var")
	assert_eq(node["value"], "red")
	assert_eq(PatternTree.to_source(node), "red")


func test_empty_string_is_a_slot_emitting_wildcard() -> void:
	var node := PatternTree.parse("")
	assert_eq(node["kind"], "slot")
	assert_eq(PatternTree.to_source(node), "_")


func test_cons_is_right_associative() -> void:
	var node := PatternTree.parse("h : t")
	assert_eq(node["kind"], "cons")
	assert_eq(node["children"][0]["value"], "h")
	assert_eq(node["children"][1]["value"], "t")
	assert_eq(PatternTree.to_source(node), "(h : t)")

	var nested := PatternTree.parse("a : b : c")
	assert_eq(nested["children"][1]["kind"], "cons", "tail of a:b:c is itself cons")
	assert_eq(PatternTree.to_source(nested), "(a : (b : c))")


func test_tuple_parses_each_element() -> void:
	var node := PatternTree.parse("(a, 0, _)")
	assert_eq(node["kind"], "tuple")
	assert_eq(node["children"].size(), 3)
	assert_eq(node["children"][0]["kind"], "var")
	assert_eq(node["children"][1]["kind"], "int")
	assert_eq(node["children"][2]["kind"], "wild")
	assert_eq(PatternTree.to_source(node), "(a, 0, _)")


func test_single_parens_group_rather_than_tuple() -> void:
	var node := PatternTree.parse("(x)")
	assert_eq(node["kind"], "var", "a single parenthesised pattern is a group, not a 1-tuple")
	assert_eq(node["value"], "x")


func test_empty_and_populated_lists() -> void:
	var empty := PatternTree.parse("[]")
	assert_eq(empty["kind"], "list")
	assert_eq(empty["children"].size(), 0)
	assert_eq(PatternTree.to_source(empty), "[]")

	var populated := PatternTree.parse("[a, b]")
	assert_eq(populated["children"].size(), 2)
	assert_eq(PatternTree.to_source(populated), "[a, b]")


func test_nested_compound_round_trips() -> void:
	# `((a, b) : rest)` — tuple head, variable tail.
	var src := "((a, b) : rest)"
	var node := PatternTree.parse(src)
	assert_eq(node["kind"], "cons")
	assert_eq(node["children"][0]["kind"], "tuple")
	assert_eq(node["children"][1]["value"], "rest")
	assert_eq(PatternTree.to_source(node), src)


func test_make_seeds_compound_minimums() -> void:
	assert_eq(PatternTree.make("cons")["children"].size(), 2)
	assert_eq(PatternTree.make("tuple")["children"].size(), 2)
	assert_eq(PatternTree.make("list")["children"].size(), 0)
	assert_eq(PatternTree.make("wild"), {"kind": "wild"})


func test_invalid_int_value_falls_back_to_zero() -> void:
	assert_eq(PatternTree.to_source({"kind": "int", "value": "oops"}), "0")
