extends GutTest
## Exercises the per-tab node in isolation: factory + level creation,
## activation (one visibility flip + pickability reconcile), and the
## `is_empty` helper used by the jobs panel UI. The swap-on-tab-switch
## logic itself is exercised by launching hex_editor.tscn in the
## integration harness.

const WorkspaceTabScript := preload("res://scenes/gui/hex_editor/workspace_tab.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const LambdaHex := preload("res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd")


func _make_tab(id: int, p_name: String) -> WorkspaceTab:
	var t := WorkspaceTabScript.create(id, p_name)
	add_child_autofree(t)
	return t


func test_fresh_tab_is_empty() -> void:
	var t := _make_tab(1, "Scratch")
	# A tab with no levels is trivially empty.
	assert_true(t.is_empty())
	# A tab whose level 0 is empty is still empty.
	t.create_root_level()
	assert_true(t.is_empty())


func test_tab_with_a_real_hex_is_not_empty() -> void:
	var t := _make_tab(2, "Scratch")
	var lvl := t.create_root_level()
	var lit := HexNode.from_script(IntLiteralHex)
	lit.is_fixture = false
	lvl.add_hex(lit)
	assert_false(t.is_empty(),
			"A level with a non-fixture hex should make the tab non-empty")
	assert_eq(lit.get_parent(), lvl.nodes,
			"add_hex must parent the hex under the level's Nodes container")
	assert_eq(lit.level, lvl, "add_hex must bind the level back-reference")


func test_tab_with_only_fixtures_is_empty() -> void:
	var t := _make_tab(3, "Scratch")
	var lvl := t.create_root_level()
	var fixture := HexNode.from_script(IntLiteralHex)
	fixture.is_fixture = true
	lvl.add_hex(fixture)
	assert_true(t.is_empty(),
			"Fixtures (DoHex / anchors) should not count toward emptiness")


func test_tab_name_is_independent_of_node_name() -> void:
	# Node.name sanitizes and dedupes; the display name must not.
	var a := _make_tab(4, "My Tab")
	var b := _make_tab(5, "My Tab")
	assert_eq(a.tab_name, "My Tab")
	assert_eq(b.tab_name, "My Tab")
	assert_ne(String(a.name), String(b.name),
			"Node names must stay unique per sibling")


func test_clear_content_strips_to_do_hex_and_clears_history() -> void:
	var t := _make_tab(10, "Scratch")
	var lvl := t.create_root_level()
	var do_hex := HexNode.from_script(IntLiteralHex)
	do_hex.is_fixture = true
	lvl.add_hex(do_hex)
	t.do_node = do_hex
	var lit := HexNode.from_script(IntLiteralHex)
	lvl.add_hex(lit)
	t.undo_stack.append({"type": "place_hex"})
	t.redo_stack.append({"type": "place_hex"})
	t.clear_content()
	assert_eq(lvl.hexes.size(), 1, "Only the DoHex fixture survives")
	assert_eq(lvl.hexes[0], do_hex)
	assert_true(t.undo_stack.is_empty(), "History is wiped")
	assert_true(t.redo_stack.is_empty())
	assert_eq(t.level_stack, [lvl] as Array[HexLevel])


func test_clear_content_frees_inner_levels() -> void:
	var t := _make_tab(11, "Scratch")
	var lvl := t.create_root_level()
	var do_hex := HexNode.from_script(IntLiteralHex)
	do_hex.is_fixture = true
	lvl.add_hex(do_hex)
	t.do_node = do_hex
	var lam := HexNode.from_script(LambdaHex)
	lvl.add_hex(lam)
	var inner := t.create_inner_level_for(lam)
	assert_eq(t.levels.get_child_count(), 2, "root + one inner level")
	t.clear_content()
	await get_tree().process_frame
	assert_false(is_instance_valid(inner), "The inner level is freed")
	assert_eq(t.levels.get_child_count(), 1, "Only the root level remains")


func test_store_view_writes_the_top_level() -> void:
	var t := _make_tab(12, "Scratch")
	var lvl := t.create_root_level()
	t.store_view(Vector2(120, -40), 0.5)
	assert_eq(lvl.world_position, Vector2(120, -40))
	assert_eq(lvl.world_scale, 0.5)


func test_rename_sets_name_and_rejects_blank() -> void:
	var t := _make_tab(13, "Old")
	assert_true(t.rename("  New Name  "), "A real name renames")
	assert_eq(t.tab_name, "New Name", "Surrounding whitespace is stripped")
	assert_false(t.rename("   "), "A blank name is rejected")
	assert_eq(t.tab_name, "New Name", "A rejected rename leaves the name intact")


func test_set_active_flips_visibility_and_pickability() -> void:
	var t := _make_tab(6, "Scratch")
	var lvl := t.create_root_level()
	var lit := HexNode.from_script(IntLiteralHex)
	lvl.add_hex(lit)
	assert_false(t.visible, "Tabs start hidden")
	assert_false(lvl.active, "Levels start inactive")
	t.set_active(true)
	assert_true(t.visible)
	assert_true(lvl.active, "Activating the tab activates the stack top")
	t.set_active(false)
	assert_false(t.visible)
	assert_false(lvl.active)
