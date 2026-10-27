extends GutTest
## MatchPatternTree widget — verifies the Tree actually builds its rows
## from branch strings and re-emits a branch's source when its model
## changes. UI hit-testing (clicking option buttons) isn't simulated;
## the edit handlers are driven through the model the same way the Tree's
## `item_edited` path does.

const MatchPatternTree := preload("res://scenes/gui/hex_editor/ui/match_pattern_tree.gd")


func _make_tree(patterns: Array) -> Tree:
	var tree = MatchPatternTree.new()
	add_child_autofree(tree)
	tree.set_branches(patterns)
	return tree


func test_builds_one_row_per_branch() -> void:
	var tree = _make_tree(["_", "(a, b)"])
	var root: TreeItem = tree.get_root()
	assert_not_null(root, "Tree must have a (hidden) root")
	assert_eq(root.get_child_count(), 2, "One row per branch")
	assert_eq(root.get_child(0).get_text(0), "Branch 1")
	assert_eq(root.get_child(1).get_text(0), "Branch 2")


func test_compound_branch_grows_child_rows() -> void:
	var tree = _make_tree(["(a, b, c)"])
	var tuple_row: TreeItem = tree.get_root().get_child(0)
	assert_eq(tuple_row.get_child_count(), 3, "Tuple branch shows a row per element")
	# The kind cell reflects the parsed kind via its RANGE index.
	assert_eq(int(tuple_row.get_range(MatchPatternTree.COL_KIND)),
			PatternTree.KINDS.find("tuple"))


func test_cons_branch_shows_head_and_tail() -> void:
	var tree = _make_tree(["h : t"])
	var cons_row: TreeItem = tree.get_root().get_child(0)
	assert_eq(cons_row.get_child_count(), 2)
	assert_eq(cons_row.get_child(0).get_text(0), "head")
	assert_eq(cons_row.get_child(1).get_text(0), "tail")


func test_pattern_edited_fires_with_updated_source() -> void:
	var tree = _make_tree(["_"])
	var seen: Array = []
	tree.pattern_edited.connect(func(idx: int, src: String) -> void:
		seen.append([idx, src]))
	# Drive the model the way the kind option button would, then let the
	# widget recompute + emit.
	tree._set_kind(tree._node_at([0]), "list")
	tree._emit_branch(0)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], 0)
	assert_eq(seen[0][1], "[]", "An empty list branch emits []")
