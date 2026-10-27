extends GutTest
## PatternVariables.extract parses match-pattern strings into the
## list of identifier bindings they introduce. Literals (`0`, `red`
## when red isn't a palette name in the pattern position), the
## wildcard `_`, and `[]` bind nothing. Cons `(h:t)` binds {h,t}.
## Tuples bind every named slot.


func test_wildcard_binds_nothing() -> void:
	assert_eq(PatternVariables.extract("_"), [],
			"Wildcard pattern introduces no bindings")


func test_literal_binds_nothing() -> void:
	assert_eq(PatternVariables.extract("0"), [],
			"Integer literal pattern introduces no bindings")
	assert_eq(PatternVariables.extract("[]"), [],
			"Empty list literal introduces no bindings")


func test_single_palette_name_binds_one() -> void:
	# Standalone palette names act as variable binders.
	assert_eq(PatternVariables.extract("red"), ["red"],
			"`red` standalone binds {red}")


func test_cons_pattern_binds_both_sides() -> void:
	# Classic head-tail pattern.
	var got: Array = PatternVariables.extract("(red:green)")
	assert_true("red" in got and "green" in got,
			"`(red:green)` binds {red, green} — got %s" % str(got))
	assert_eq(got.size(), 2,
			"Two bindings, not duplicates")


func test_tuple_pattern_binds_every_slot() -> void:
	var got: Array = PatternVariables.extract("(red, green, blue)")
	for name in ["red", "green", "blue"]:
		assert_true(name in got,
				"`%s` should be in {red,green,blue} — got %s" % [name, str(got)])


func test_nested_pattern_recursion() -> void:
	# `((red, green) : blue)` — outer cons with a tuple head.
	var got: Array = PatternVariables.extract("((red, green) : blue)")
	for name in ["red", "green", "blue"]:
		assert_true(name in got,
				"`%s` should land in the nested pattern — got %s" % [name, str(got)])


func test_underscore_in_cons_drops_the_wildcard_side() -> void:
	var got: Array = PatternVariables.extract("(red : _)")
	assert_eq(got, ["red"],
			"Wildcard half should drop; the other half stays — got %s" % str(got))
