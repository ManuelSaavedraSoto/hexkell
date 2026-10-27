extends GutTest
## Codex dialog — verifies `set_concepts` populates the left-column list,
## indexes bodies for `show_concept`, auto-selects the first entry, and
## degrades to an empty-state message when handed nothing.

const CODEX_DIALOG_SCENE := preload("res://scenes/gui/hex_editor/dialogs/codex_dialog.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload(
	"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")


func _make_dialog() -> Control:
	var dialog: Control = CODEX_DIALOG_SCENE.instantiate()
	add_child_autofree(dialog)
	return dialog


# A minimal, well-formed `hxk1:...` blueprint string (one int literal).
func _sample_blueprint() -> String:
	var hex: IntLiteralHex = HexNode.from_script(IntLiteralHex)
	add_child_autofree(hex)
	await get_tree().process_frame
	hex.value = 7
	hex.set_axial(Vector2i(-1, 0))
	var payload := BlueprintCodec.serialize_subset(
		[hex], null, "codex", "", "", Vector2i.ZERO)
	return BlueprintCodec.encode(payload)


func test_set_concepts_lists_titles_and_selects_first() -> void:
	var dialog := _make_dialog()
	dialog.set_concepts([
		{"id": "a", "title": "Alpha", "body": "[b]first[/b]"},
		{"id": "b", "title": "Beta", "body": "second"},
	])
	assert_eq(dialog.concept_list.item_count, 2, "Both concepts listed")
	assert_eq(dialog.concept_list.get_item_text(0), "Alpha")
	# First concept auto-shown so the detail pane is never blank.
	assert_eq(dialog.right_header.text, "Alpha")
	assert_eq(dialog.content_label.text, "[b]first[/b]")


func test_show_concept_switches_body() -> void:
	var dialog := _make_dialog()
	dialog.set_concepts([
		{"id": "a", "title": "Alpha", "body": "first"},
		{"id": "b", "title": "Beta", "body": "second"},
	])
	dialog.show_concept("b")
	assert_eq(dialog.right_header.text, "Beta")
	assert_eq(dialog.content_label.text, "second")


func test_entries_without_id_are_skipped() -> void:
	var dialog := _make_dialog()
	dialog.set_concepts([
		{"title": "No id", "body": "x"},
		{"id": "ok", "title": "Kept", "body": "y"},
	])
	assert_eq(dialog.concept_list.item_count, 1, "Only the id-bearing entry survives")
	assert_eq(dialog.concept_list.get_item_text(0), "Kept")


func test_empty_concepts_show_placeholder() -> void:
	var dialog := _make_dialog()
	dialog.set_concepts([])
	assert_eq(dialog.concept_list.item_count, 0)
	assert_string_contains(dialog.content_label.text, "No concepts yet")


# A concept carrying an example blueprint renders a live mini-canvas
# preview above the body text.
func test_concept_with_blueprint_builds_preview() -> void:
	var encoded: String = await _sample_blueprint()
	var dialog := _make_dialog()
	dialog.set_concepts([
		{"id": "a", "title": "Alpha", "body": "first", "blueprint": encoded},
	])
	assert_not_null(dialog._preview_container,
			"a blueprint-bearing concept should build the preview")
	assert_true(dialog._preview_container.visible,
			"the preview should be visible for a decodable blueprint")
	assert_eq(dialog._preview_viewport.get_child_count(), 1,
			"the preview viewport holds exactly one mini-canvas")


# A concept without a blueprint leaves the preview hidden (the lazy
# container is only created once any concept needs it, then re-hidden).
func test_concept_without_blueprint_hides_preview() -> void:
	var encoded: String = await _sample_blueprint()
	var dialog := _make_dialog()
	dialog.set_concepts([
		{"id": "a", "title": "Alpha", "body": "first", "blueprint": encoded},
		{"id": "b", "title": "Beta", "body": "second"},
	])
	# Selecting the blueprint-free concept hides the preview built for "a".
	dialog.show_concept("b")
	assert_false(dialog._preview_container.visible,
			"a concept with no blueprint must not show a stale preview")
