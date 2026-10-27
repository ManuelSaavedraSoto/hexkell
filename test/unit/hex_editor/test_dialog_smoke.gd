extends GutTest
## Guard against the Control-based dialog shells regressing back to
## Window subclasses (the user's "no AcceptDialog" rule from the
## dialog-refactor pass) and confirm each scene exposes the same
## public API the editor relies on.

const ChapterIntroScene := preload(
		"res://scenes/gui/common/chapter_intro_dialog.tscn")
const BlueprintLibraryScene := preload(
		"res://scenes/gui/blueprint_library/blueprint_library_dialog.tscn")
const KeybindingsScene := preload(
		"res://scenes/gui/hex_editor/dialogs/keybindings_dialog.tscn")
const CodexScene := preload(
		"res://scenes/gui/hex_editor/dialogs/codex_dialog.tscn")


func test_chapter_intro_dialog_is_control_based() -> void:
	# Chapter intro got refactored to the pause-menu pattern this pass.
	var d = ChapterIntroScene.instantiate()
	add_child_autofree(d)
	await get_tree().process_frame
	assert_true(d is Control,
			"Chapter intro should match the pause-menu Control pattern")
	assert_false(d is Window,
			"Chapter intro should no longer extend AcceptDialog")


func test_blueprint_library_dialog_is_control_based() -> void:
	var d = BlueprintLibraryScene.instantiate()
	add_child_autofree(d)
	await get_tree().process_frame
	assert_true(d is Control,
			"Library dialog should be a Control, not a Window subclass")
	assert_not_null(d.get_preview_panel(),
			"Library dialog should expose its preview panel for tests")


func test_keybindings_dialog_is_control_based() -> void:
	var d = KeybindingsScene.instantiate()
	add_child_autofree(d)
	await get_tree().process_frame
	assert_true(d is Control,
			"Keybindings dialog should be a Control, not a Window subclass")
	assert_eq(d.get_section_count(), 9,
			"Should expose all sections of the keybindings reference")


func test_keybindings_rows_derive_from_input_map() -> void:
	# Action-backed rows must resolve to icon/text BBCode pulled from
	# the live InputMap — the whole point of dropping the hardcoded
	# key strings.
	var d = KeybindingsScene.instantiate()
	add_child_autofree(d)
	await get_tree().process_frame
	var derived: String = d._binding_keys_bbcode({"actions": ["sys_open_library"]})
	assert_string_contains(derived, "letters/b.tres",
			"B-bound action should render the letter icon asset")
	for section in d._sections():
		for binding in section.bindings:
			if binding.has("actions"):
				assert_false(
						String(d._binding_keys_bbcode(binding)).is_empty(),
						"Action row '%s' should derive non-empty keys"
						% String(binding.desc))


func test_dialogs_close_on_their_own_toggle_action() -> void:
	# While a modal is open the tree is paused and the editor-side
	# CanvasInputController is frozen — each dialog must consume its
	# own opening hotkey to toggle closed.
	var cases := [
		[KeybindingsScene, KEY_SLASH, true],   # sys_help = Shift+/
		[BlueprintLibraryScene, KEY_B, false],  # sys_open_library
		[CodexScene, KEY_G, false],             # sys_open_codex
	]
	for c in cases:
		var d = (c[0] as PackedScene).instantiate()
		add_child_autofree(d)
		await get_tree().process_frame
		d.open()
		assert_true(d.visible)
		var ev := InputEventKey.new()
		ev.physical_keycode = c[1]
		ev.shift_pressed = c[2]
		ev.pressed = true
		d._input(ev)
		assert_false(d.visible,
				"Dialog %s should close on its toggle action" % d.name)


func test_codex_dialog_is_control_based() -> void:
	var d = CodexScene.instantiate()
	add_child_autofree(d)
	await get_tree().process_frame
	assert_true(d is Control,
			"Codex dialog should be a Control, not a Window subclass")
	# The set_concepts / show_concept API must exist for the future
	# codex content rollout. Calling with an empty array should not
	# error.
	d.set_concepts([])


func test_blueprint_row_scene_populates_without_error() -> void:
	# Per-blueprint row is its own scene (post-scenefication of the
	# library card). The dialog spawns instances + calls populate();
	# this guards that the scene's @onready bindings resolve and
	# populate() doesn't crash on a minimal entry.
	var card = preload(
			"res://scenes/gui/blueprint_library/blueprint_row.tscn"
	).instantiate()
	add_child_autofree(card)
	await get_tree().process_frame
	assert_true(card is Button,
			"Row root is a toggle Button (its `pressed` StyleBox is the selection highlight)")
	card.populate(0, {
		"name": "test-row",
		"payload": {"hexes": [], "wires": []},
	})
	await get_tree().process_frame
	assert_eq(card._name_label.text, "test-row",
			"populate() should write the entry name into the label")


func test_all_dialogs_open_and_close_cleanly() -> void:
	# Each dialog should be hidden by default, `open()` shows it, and
	# `close()` hides it — the canonical lifecycle for the Control
	# modals.
	for scene in [BlueprintLibraryScene, KeybindingsScene, CodexScene]:
		var d = scene.instantiate()
		add_child_autofree(d)
		await get_tree().process_frame
		assert_false(d.visible,
				"Dialog %s should default to hidden" % d.name)
		d.open()
		await get_tree().process_frame
		assert_true(d.visible,
				"Dialog %s should be visible after open()" % d.name)
		d.close()
		await get_tree().process_frame
		assert_false(d.visible,
				"Dialog %s should be hidden after close()" % d.name)
