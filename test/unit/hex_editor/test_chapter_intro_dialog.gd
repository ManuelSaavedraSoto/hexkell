extends GutTest
## Chapter intro dialog — screenshot-based after the v3 chapter
## rewrite. Verifies the data layer (TemplateManager.get_chapter)
## hands the dialog the expected shape and that the dialog renders
## screenshot tabs (falling back to a placeholder when the image
## isn't on disk yet).

const CHAPTER_INTRO_SCENE := preload("res://scenes/gui/common/chapter_intro_dialog.tscn")


# ── Data shape ─────────────────────────────────────────────────────────────

func test_tutorial_chapter_uses_screenshot_examples() -> void:
	# The post-canvas chapter restructure swaps the legacy `code`
	# field for `screenshot` + `caption`. Each example must carry
	# both keys (or at least screenshot) so the dialog has something
	# to point its TextureRect at.
	var chapter: Dictionary = TemplateManager.get_chapter("chapter_0_tutorial")
	assert_false(chapter.is_empty(),
			"chapter_0_tutorial should be defined in static_data.json")
	# Post-breakdown the tutorial is a single-concept chapter (placing
	# one hex), so check the example shape across every chapter rather
	# than a slide count on chapter 0 alone.
	for chapter_id in TemplateManager.get_chapter_ids():
		var examples: Array = TemplateManager.get_chapter(chapter_id).get("examples", [])
		assert_true(examples.size() >= 1,
				"%s should ship at least one example slide" % chapter_id)
		for entry in examples:
			assert_true(entry is Dictionary)
			assert_true(entry.has("screenshot"),
					"Example should carry a `screenshot` field, got %s" % entry)
			assert_true(entry.has("caption"))
			# No leftover legacy `code` field — those were retired
			# with the screenshot pivot.
			assert_false(entry.has("code"),
					"Legacy `code` field should have been removed from examples")


func test_structures_chapter_covers_canvas_flow() -> void:
	var chapter: Dictionary = TemplateManager.get_chapter("chapter_8_structures")
	assert_false(chapter.is_empty())
	# After the lambda split, the Structures chapter's spine is tuples,
	# lists, cons/concat, pattern matching, and list-recursion (lambdas
	# moved to their own chapter). Spot-check the tab names.
	var names: Array = []
	for e in chapter.get("examples", []):
		names.append(String(e.get("name", "")))
	assert_true("Tuples" in names)
	assert_true("Lists" in names)
	assert_true("Pattern match" in names)
	assert_false("Lambdas" in names,
			"The Lambdas slide moved to the dedicated Lambdas chapter")
	# The split-off Lambdas chapter carries the Lambdas slide.
	var lambda_names: Array = []
	for e in TemplateManager.get_chapter("chapter_6_lambdas").get("examples", []):
		lambda_names.append(String(e.get("name", "")))
	assert_true("Lambdas" in lambda_names,
			"The Lambdas chapter should ship the Lambdas example")


# ── Dialog rendering ───────────────────────────────────────────────────────

func test_dialog_renders_a_placeholder_when_screenshot_missing() -> void:
	# Screenshots aren't on disk yet — the carousel should gracefully
	# show a placeholder slide instead of crashing or leaving the
	# view empty.
	var dialog := CHAPTER_INTRO_SCENE.instantiate()
	add_child_autofree(dialog)
	await get_tree().process_frame
	dialog.show_chapter("chapter_8_structures",
			TemplateManager.get_chapter("chapter_8_structures"))
	await get_tree().process_frame
	# The carousel holds one slide at a time; the indicator reports the
	# total. The Structures chapter ships several example slides.
	assert_true(dialog._carousel_examples.size() >= 4,
			"Structures chapter should have loaded several carousel slides")
	assert_string_contains(dialog.indicator_label.text, "/",
			"Indicator should read like '1 / N'")
	# The current slide's content node should be present with children
	# (a TextureRect when the screenshot resolved, or a Label
	# placeholder while screenshots are still pending).
	assert_not_null(dialog._carousel_current_content)
	assert_gt(dialog._carousel_current_content.get_child_count(), 0,
			"Current slide should have built a screenshot view, not be empty")
	# Next advances the carousel; prev is disabled on the first slide.
	assert_true(dialog.prev_button.disabled,
			"Prev should be disabled on the first slide")
	dialog._on_next_pressed()
	assert_false(dialog.prev_button.disabled,
			"Prev should enable after advancing past the first slide")


func test_dialog_renders_blueprint_example_via_subviewport() -> void:
	# Blueprint-based example: when an entry carries a `blueprint`
	# field with a valid hxk1:... string, the dialog decodes it into
	# a read-only mini-canvas hosted inside a SubViewportContainer.
	var dialog := CHAPTER_INTRO_SCENE.instantiate()
	add_child_autofree(dialog)
	await get_tree().process_frame

	# Encode a single-DoHex blueprint inline so the test has no
	# external file dependency.
	const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
	var level: HexLevel = HexLevel.new()
	var do_hex: DoHex = HexNode.from_script(DoHex)
	add_child_autofree(do_hex)
	await get_tree().process_frame
	do_hex.set_display_value("5")
	level.hexes.append(do_hex)
	var payload := BlueprintCodec.serialize_root(
		level, null, do_hex, "test", "", "", Vector2i.ZERO)
	var encoded := BlueprintCodec.encode(payload)

	dialog.show_chapter("chapter_test", {
		"name": "Test",
		"description": "",
		"examples": [{
			"name": "Numbers",
			"blueprint": encoded,
			"caption": "test",
		}],
	})
	await get_tree().process_frame
	assert_not_null(dialog._carousel_current_content)
	assert_true(_walk_for_subviewport_container(dialog._carousel_current_content),
			"Blueprint-based example must render via a SubViewportContainer.")


func _walk_for_subviewport_container(root: Node) -> bool:
	if root is SubViewportContainer:
		return true
	for child in root.get_children():
		if _walk_for_subviewport_container(child):
			return true
	return false


func test_do_hex_displays_baked_value() -> void:
	# When a chapter scene bakes a `display_value` on its DoHex, the
	# label-over-body switches from "do" to the static value and
	# stays visible after the scene enters the tree.
	const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
	var do_hex := HexNode.from_script(DoHex)
	add_child_autofree(do_hex)
	await get_tree().process_frame
	do_hex.set_display_value("42")
	assert_eq(do_hex._display_label.text, "42")
	assert_true(do_hex._display_label.visible)
	assert_false(do_hex._keyword_label.visible,
			"The 'do' keyword should hide when a display value takes over")
	do_hex.set_display_value("")
	assert_false(do_hex._display_label.visible)
	assert_true(do_hex._keyword_label.visible)


func test_dialog_emits_close_signal_on_close() -> void:
	# `chapter_closed(id)` is what the editor listens for to advance
	# the encyclopedia / mark intros seen. Verify the signal fires
	# exactly once with the right id even after a close-via-confirm.
	var dialog := CHAPTER_INTRO_SCENE.instantiate()
	add_child_autofree(dialog)
	await get_tree().process_frame
	var seen_ids: Array[String] = []
	dialog.chapter_closed.connect(func(id: String) -> void: seen_ids.append(id))
	dialog.show_chapter("chapter_0_tutorial", TemplateManager.get_chapter("chapter_0_tutorial"))
	await get_tree().process_frame
	dialog.close()  # Simulate the player clicking Close
	assert_eq(seen_ids, ["chapter_0_tutorial"],
			"Closing should emit chapter_closed exactly once with the chapter id")
