extends GutTest
## TabStore — the tab generation + persistence layer. Codec payloads
## in, WorkspaceTab nodes out, and back again. The full save-file
## round trip is covered by the editor smoke suite; this exercises
## the static API directly.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")

var _editor: Node
var _saved_hex: Dictionary


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["hex"]["tabs"] = []
	SaveManager.current_data["hex"]["current_tab_id"] = 0
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	ChapterManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func after_each() -> void:
	SaveManager.current_data["hex"] = _saved_hex
	ModalStack.reset(get_tree())


func test_create_fresh_builds_a_ready_tab() -> void:
	var wired: Array = []
	var tab := TabStore.create_fresh(
			77, "Fresh", _editor.world, func(h): wired.append(h))
	autofree(tab)
	assert_not_null(tab.root_level(), "Fresh tab must have a root level")
	assert_not_null(tab.do_node, "Fresh tab must have its DoHex fixture")
	assert_eq(tab.do_node.get_parent(), tab.root_level().nodes,
			"DoHex must live in the root level's Nodes container")
	assert_eq(wired, [tab.do_node],
			"on_hex must announce every created hex for signal wiring")
	assert_false(tab.visible, "Fresh tabs start inactive")


func test_payload_round_trip_restores_the_graph() -> void:
	# Place an Int hex WEST of the DoHex (adjacency feeds Do's west
	# input), serialize, rehydrate into a brand-new tab, and compare.
	var tab: WorkspaceTab = _editor._tabs[0]
	var lit := HexNode.from_script(IntLiteralHex)
	tab.root_level().add_hex(lit)
	lit.set_axial(Vector2i(-1, 0))
	lit.value = 42
	_editor._wire_node_signals(lit)

	var payload := TabStore.to_payload(tab, _editor)
	assert_false(payload.is_empty())

	var clone := TabStore.create_fresh(
			88, "Clone", _editor.world, _editor._wire_node_signals)
	autofree(clone)
	var warnings := TabStore.install_payload(
			clone, payload, _editor._wire_node_signals)
	assert_eq(warnings, [], "Round trip must produce no loader warnings")
	# Root level: DoHex + the restored literal.
	assert_eq(clone.root_level().hexes.size(), 2)
	var restored: HexNode = null
	for h in clone.root_level().hexes:
		if h != clone.do_node:
			restored = h
	assert_not_null(restored)
	assert_eq(restored.axial, Vector2i(-1, 0), "Axial must round-trip")
	assert_eq(restored.value, 42, "Per-hex state must round-trip")
	assert_eq(restored.get_parent(), clone.root_level().nodes,
			"Restored hexes must land in the clone's own containers")


func test_persist_writes_the_same_save_shape() -> void:
	TabStore.persist(_editor._tabs, 0, _editor)
	var saved: Array = SaveManager.get_tab_payloads()
	assert_eq(saved.size(), _editor._tabs.size())
	assert_true(saved[0].has("name") and saved[0].has("payload"),
			"Save shape must stay {name, payload} — no format migration")
