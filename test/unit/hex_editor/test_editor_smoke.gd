extends GutTest
## Integration smoke test for the Phase 19 hex editor: instantiate the
## scene, exercise the tab and palette systems, and submit a tiny hex
## program against a real job through the Checker. Catches regressions
## in the wiring between hex_editor.gd / TemplateManager / SaveManager /
## Checker that wouldn't be visible to the smaller unit tests.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")

var _saved_hex: Dictionary
var _saved_renown: int
var _saved_autosave: bool
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	_saved_renown = SaveManager.get_renown()
	_saved_autosave = SaveManager.get_auto_save()
	SaveManager.current_data["preferences"]["auto_save"] = false
	# Force a known starting position so test ordering doesn't matter:
	# wipe persisted tab names (so the editor rebuilds the default 6)
	# and reset renown to 0.
	SaveManager.current_data["hex"]["tabs"] = []
	SaveManager.current_data["hex"]["current_tab_id"] = 0
	SaveManager.current_data["hex"]["solved_jobs"] = {}
	SaveManager.current_data["story"]["renown"] = 0
	SaveManager.current_data["story"]["seen_chapter_intros"] = []
	# Keep the chapter-0 tutorial dormant — these tests exercise the
	# editor outside the scripted FSM (which hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	# Job-selection state lives on the ChapterManager autoload and
	# would otherwise leak across tests.
	ChapterManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	# Let _ready run.
	await get_tree().process_frame


func after_each() -> void:
	SaveManager.current_data["hex"] = _saved_hex
	SaveManager.current_data["story"]["renown"] = _saved_renown
	SaveManager.current_data["preferences"]["auto_save"] = _saved_autosave
	# Tests that flip archmage on (e.g. the F-cycle pool) must not leak it.
	SaveManager.set_archmage(false)
	# Modal opens pause the tree (ModalStack); a leaked pause would
	# freeze every later suite in the run.
	ModalStack.reset(get_tree())


func test_layout_bars_are_proportional_full_width() -> void:
	# The full-width-bar layout uses fractional anchors so proportions
	# stay constant under window scaling. Rule-of-thirds budget:
	# TopBar fits in the top third of the top third (~11.1% / 1080 →
	# ~120px); PaletteBar fits in half of the bottom third (~16.7% /
	# 1080 → ~180px). Anything fatter pushed the chrome into the
	# canvas at 1920×1080 — the smoke test guards both ceilings.
	# The palette now lives inside the anchored BottomHUD VBox, so the
	# bottom-bar geometry assertions target BottomHUD.
	var ui_root: Control = _editor.get_node("HUDLayer/UIRoot")
	var top_bar: Control = ui_root.get_node("TopBar")
	var middle: Control = ui_root.get_node("MiddleArea")
	var palette: Control = ui_root.get_node("BottomHUD")
	# Bars span the full width.
	assert_eq(top_bar.anchor_left, 0.0)
	assert_eq(top_bar.anchor_right, 1.0)
	assert_eq(palette.anchor_left, 0.0)
	assert_eq(palette.anchor_right, 1.0)
	# Vertical regions tile the viewport top→bottom roughly meeting.
	# A small overlap is allowed (≤ 0.05) so the MiddleArea can slide
	# slightly behind the TopBar if the layout designer wants a
	# layered look — guard against gaps and big overlaps, not exact
	# adjacency.
	var top_gap: float = absf(top_bar.anchor_bottom - middle.anchor_top)
	assert_lt(top_gap, 0.05,
			"TopBar bottom and MiddleArea top should meet (or overlap slightly)")
	var bottom_gap: float = absf(middle.anchor_bottom - palette.anchor_top)
	assert_lt(bottom_gap, 0.05,
			"MiddleArea bottom and PaletteBar top should meet (or overlap slightly)")
	assert_eq(palette.anchor_bottom, 1.0)
	# Rule-of-thirds ceilings.
	assert_lt(top_bar.anchor_bottom, 1.0 / 9.0 + 0.005,
			"TopBar must stay within 1/9 of the viewport (top third of the top third)")
	assert_gt(palette.anchor_top, 1.0 - 1.0 / 6.0 - 0.005,
			"PaletteBar must stay within 1/6 of the viewport (half of the bottom third)")
	# JobsPanel floats over the left fraction of the middle area.
	# A small inset from the edges is fine — guard against the panel
	# starting past the left third / covering the whole middle.
	var jobs_panel: Control = middle.get_node("JobsPanel")
	assert_lt(jobs_panel.anchor_left, 0.05,
			"JobsPanel should be anchored at or near the left edge")
	assert_lt(jobs_panel.anchor_right, 1.0,
			"JobsPanel should occupy only a left fraction, not the whole middle")
	# OutputPanel mirrors JobsPanel on the right edge of the middle
	# area. ConfigPanel shares the same slot — sibling order keeps
	# ConfigPanel on top when both want to be visible.
	var output_panel: Control = middle.get_node("OutputPanel")
	var config_panel: Control = middle.get_node("ConfigPanel")
	assert_gt(output_panel.anchor_left, 0.5,
			"OutputPanel should float on the right half of the middle area")
	assert_gt(config_panel.anchor_left, 0.5,
			"ConfigPanel shares the same right-side slot as OutputPanel")
	assert_gt(config_panel.get_index(), output_panel.get_index(),
			"ConfigPanel must declare AFTER OutputPanel so it covers it on open")


func test_palette_emits_hex_selected_on_pick_slot() -> void:
	# The editor wires palette_bar.hex_selected → _enter_blueprint_fresh.
	# Driving pick_slot(0) for the starter Integer category (Int literal,
	# always unlocked) should emit through to the editor's signal chain.
	var got: Array = []
	_editor.palette_bar.hex_selected.connect(func(s): got.append(s))
	_editor.palette_bar.pick_slot(0)
	assert_eq(got.size(), 1,
			"PaletteBar should emit hex_selected once when an unlocked slot is picked")


func test_library_preview_renders_blueprint_via_mini_canvas() -> void:
	# Toggling a library card on hydrates a BlueprintMiniCanvas-hosting
	# SubViewport inside the preview panel; toggling it off (clean-mouse
	# gesture) drops back to the placeholder. Smoke-covers the wiring
	# between SaveManager → library list → mini-canvas.
	var bp_payload: Dictionary = {
		"version": 1,
		"hexes": [{
			"id": 0,
			"script_path": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
			"pos": [0, 0],
			"rotation": 0,
			"state": {"value": 42},
		}],
		"wires": [],
	}
	SaveManager.add_blueprint("smoke-preview", "42", bp_payload)
	_editor._open_library()
	await get_tree().process_frame
	# Card 0 = the entry we just added (most recent prepended).
	# Library state moved into the dialog scene + a per-row scene.
	# Poke at the dialog's `_on_card_selected` (the scene-driven
	# replacement for the old `_on_card_toggled`); preview lives at
	# `_library_dialog.get_preview_panel()`.
	var dialog = _editor._library_dialog
	dialog._on_card_selected(0)
	await get_tree().process_frame
	assert_not_null(dialog._preview_canvas,
			"Selecting a card should hydrate a preview canvas")
	var found_viewport_container := false
	for child in dialog.get_preview_panel().get_children():
		if child is SubViewportContainer:
			found_viewport_container = true
			break
	assert_true(found_viewport_container,
			"Preview panel should host a SubViewportContainer when a card is active")
	# Clean-mouse exit: clicking the active card again drops back to
	# the placeholder.
	dialog._on_card_selected(0)
	await get_tree().process_frame
	assert_eq(dialog._selected_index, -1,
			"Re-clicking the active card should clear the selection")
	assert_null(dialog._preview_canvas,
			"Placeholder should replace the canvas after un-press")


func test_drag_start_fires_via_anchor_area() -> void:
	# The forgiving capsule (anchor Area2D) is now the drag-start
	# target instead of the precise trapezoid. Drive `_on_slot_input`
	# directly with a synthetic LMB press and confirm the
	# `slot_grab_started` payload reaches the editor's wiring path.
	# Array captures the mutation across the lambda boundary (GDScript
	# closures don't reflect primitive-var writes back into the outer
	# scope).
	var hex: HexNode = _editor.do_node
	var captured: Array = []
	hex.slot_grab_started.connect(
			func(n, e, is_out) -> void:
				captured.append([n, e, is_out]))
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	hex._on_slot_input(null, mb, 0, 0)  # physical edge 0 = right
	assert_eq(captured.size(), 1,
			"slot_grab_started should fire once per LMB-down")
	assert_eq(captured[0][0], hex, "Payload should carry the hex")
	assert_eq(captured[0][1], 0, "Logical edge 0 for DoHex (rotation_index 0)")
	assert_eq(captured[0][2], false,
			"DoHex edges are inputs, so is_output is false")


func test_rmb_delete_refuses_fixtures() -> void:
	# DoHex is the tab's level-0 fixture; the RMB → _on_node_delete_requested
	# → _delete_hex path must refuse rather than queue_free the entry
	# point. Bulk / cut / clone paths already pre-filter via
	# `if h.is_fixture`; this guard is the central backstop for the
	# lone-hex delete.
	var do_hex: HexNode = _editor.do_node
	assert_not_null(do_hex, "Active tab should expose its DoHex")
	assert_true(do_hex.is_fixture,
			"DoHex should be flagged as a fixture")
	var record: Dictionary = _editor._delete_hex(do_hex)
	assert_true(record.is_empty(),
			"_delete_hex should refuse fixtures with an empty record")
	assert_true(is_instance_valid(do_hex),
			"Fixture should still exist after the refused delete")


func test_palette_button_is_pressed_when_hex_is_active() -> void:
	# Active-hex affordance moved from a modulate brighten to the
	# Button's built-in `button_pressed` state (which renders via the
	# theme's `pressed` StyleBox). Editor-initiated state changes use
	# `set_pressed_no_signal` so they don't bounce back through the
	# `toggled` handler.
	var palette = _editor.palette_bar
	palette.set_active_hex(IntLiteralHex)
	var btn = palette._button_for(IntLiteralHex)
	assert_not_null(btn, "IntLiteralHex should have a palette button")
	assert_true(btn.button_pressed,
			"Active hex button should read as pressed")
	palette.set_active_hex(null)
	assert_false(btn.button_pressed,
			"Clearing active hex should un-press the button")


func test_archmage_unlocks_locked_palette_buttons() -> void:
	# Archmage off: picking a slot belonging to a locked hex emits
	# nothing (`_emit_pick` short-circuits on the lock). Archmage on:
	# the same slot pick fires through. The "Match" hex sits in the
	# Functions category (slot 2 — "if" is slot 1, "match" is slot 2)
	# and starts locked under the starter unlock set.
	var palette = _editor.palette_bar
	palette.select_category(2)  # Functions
	var got: Array = []
	palette.hex_selected.connect(func(s): got.append(s))
	palette.pick_slot(2)  # match_hex — locked
	assert_eq(got.size(), 0,
			"Locked slot picks must not emit hex_selected by default")
	palette.set_archmage(true)
	palette.pick_slot(2)
	assert_eq(got.size(), 1,
			"Archmage flips locked slot picks through")
	palette.set_archmage(false)


func test_select_category_minus_one_hides_all_rows() -> void:
	var palette = _editor.palette_bar
	var got: Array = []
	palette.category_selected.connect(func(idx): got.append(idx))
	palette.select_category(-1)
	assert_eq(palette.get_current_category(), -1)
	assert_eq(got, [-1], "Deselect should emit category_selected(-1)")
	for row in palette.get_hex_rows():
		assert_false(row.visible,
				"No hex row should be visible with no category selected")
	for i in palette.get_hex_rows().size():
		var btn = palette.get_category_button(i)
		if btn != null:
			assert_false(btn.button_pressed,
					"No category button should read pressed after deselect")


func test_reclicking_active_category_deselects() -> void:
	var palette = _editor.palette_bar
	palette.select_category(0)
	var btn = palette.get_category_button(0)
	# Simulate the user click on the pressed toggle button: flipping
	# button_pressed emits `toggled`, which routes to select_category(-1).
	btn.button_pressed = false
	assert_eq(palette.get_current_category(), -1,
			"Un-pressing the active category should deselect all")


func test_categories_with_no_unlocked_hexes_are_hidden() -> void:
	# Scaffolding: with only the Int literal unlocked, just the Integer
	# category button should be visible.
	var palette = _editor.palette_bar
	palette.set_archmage(false)
	palette.set_unlocked_scripts(
			["res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd"])
	assert_true(palette.get_category_button(0).visible,
			"Integer category stays visible (Int hex is unlocked)")
	for i in range(1, palette.get_hex_rows().size()):
		assert_false(palette.get_category_button(i).visible,
				"Category %d has no unlocked hexes and should be hidden" % i)
	# Restore the editor's real unlock set for subsequent assertions.
	palette.set_unlocked_scripts(SaveManager.get_unlocked_hex_scripts())


func test_step_category_from_deselected_lands_on_available() -> void:
	var palette = _editor.palette_bar
	palette.set_archmage(true)  # all categories available
	palette.select_category(-1)
	palette.step_category(1)
	assert_eq(palette.get_current_category(), 0,
			"Stepping forward from deselected should land on the first category")
	palette.select_category(-1)
	palette.step_category(-1)
	assert_eq(palette.get_current_category(), palette.get_hex_rows().size() - 1,
			"Stepping back from deselected should land on the last category")
	palette.set_archmage(false)


func test_archmage_promotes_renown_locked_jobs_to_pending() -> void:
	# Pick a known renown-locked job (one with renown_required > 0),
	# leave renown at 0, and confirm refresh() routes it into the
	# Pending section when archmage is on. The list rebuilds on each
	# call so we just look for the job's name in the rendered buttons.
	var all_jobs: Dictionary = TemplateManager.get_all_jobs()
	var locked_id := ""
	for id in all_jobs.keys():
		if int(all_jobs[id].get("renown_required", 0)) > 0:
			locked_id = String(id)
			break
	assert_ne(locked_id, "",
			"Test setup: expected at least one renown-gated job")
	SaveManager.current_data["story"]["renown"] = 0
	# Default state: the job lives in the locked section.
	_editor.jobs_panel.refresh("")
	assert_false(_button_with_job_visible(_editor.jobs_panel, all_jobs[locked_id], "● "),
			"Renown-locked job should not appear as Pending by default")
	SaveManager.set_archmage(true)
	_editor.jobs_panel.refresh("")
	assert_true(_button_with_job_visible(_editor.jobs_panel, all_jobs[locked_id], "● "),
			"With archmage on, the renown-gated job should land in Pending")
	SaveManager.set_archmage(false)


func _button_with_job_visible(panel, job: Dictionary, prefix: String) -> bool:
	var label := "%s%s" % [prefix, String(job.get("name", ""))]
	for c in panel.jobs_list.get_children():
		if c is Button and String(c.text) == label:
			return true
	return false


func test_output_panel_fold_toggle_collapses_panel() -> void:
	# The OutputPanel IS the FoldableContainer. Bare-O (and the
	# FoldableContainer's native title-bar click) drive expand() / fold();
	# Godot's container natively collapses its body and shrinks the
	# layout. Default boot state: folded (set in the scene).
	var panel = _editor.output_panel
	assert_true(panel.folded,
			"OutputPanel should boot in the folded state")
	_editor.output_panel.append_output("first line")
	_editor.output_panel.expand()
	assert_false(panel.folded,
			"expand() should unfold the panel")
	_editor.output_panel.fold()
	assert_true(panel.folded)


func test_export_button_removed() -> void:
	# Export-to-file is deprecated by the blueprint export +
	# Ctrl+Space program-text copy. Confirm the button is gone from
	# the scene and the signal hub no longer carries an export signal.
	assert_null(_editor.get_node_or_null("%ExportButton"),
			"ExportButton should have been removed with the blueprint pivot")
	assert_false(_editor.top_buttons.has_signal("export_requested"),
			"TopButtons should no longer expose an export_requested signal")


func test_action_buttons_resolve_with_icons() -> void:
	# The visual overhaul replaced the HexToolbarButton chrome (hotkey
	# badges) with plain icon buttons. Guard the new convention: the
	# three top-bar action buttons resolve by unique name and carry an
	# icon texture.
	var generate: Button = _editor.get_node("%GenerateButton")
	var run: Button = _editor.get_node("%RunButton")
	var library: Button = _editor.get_node("%LibraryButton")
	assert_not_null(generate, "GenerateButton should resolve")
	assert_not_null(run, "RunButton should resolve")
	assert_not_null(library, "LibraryButton should resolve")
	assert_not_null(generate.icon, "GenerateButton should carry an icon")
	assert_not_null(run.icon, "RunButton should carry an icon")
	assert_not_null(library.icon, "LibraryButton should carry an icon")


func test_job_header_lives_inside_jobs_panel() -> void:
	# Moved out of the TopBar back into the JobsPanel — frees the
	# top-bar height back to the rule-of-thirds budget. The unique
	# name %TopLabels still resolves so _refresh_job_display works.
	var top_labels: Control = _editor.get_node_or_null("%TopLabels")
	assert_not_null(top_labels, "JobHeader (%TopLabels) should still resolve")
	# Walk up the parent chain; somewhere above must be the JobsPanel
	# subtree (not the TopBar subtree).
	var cur: Node = top_labels
	var under_jobs := false
	while cur != null:
		if cur.name == "JobsPanel":
			under_jobs = true
			break
		cur = cur.get_parent()
	assert_true(under_jobs,
			"JobHeader should now live inside the JobsPanel, not the TopBar")


func test_jobs_panel_fold_toggle_collapses_panel() -> void:
	# The JobsPanel IS the FoldableContainer (no wrapping
	# PanelContainer); Ctrl+F flips the container's `folded` flag and
	# Godot's native behavior collapses the body. The panel boots
	# FOLDED (scene default) — tutorial step 3 ("open the jobs panel")
	# rides on that unfold transition.
	var panel = _editor.jobs_panel
	assert_true(panel.folded, "JobsPanel boots folded")
	_editor._toggle_jobs_fold()
	assert_false(panel.folded)
	_editor._toggle_jobs_fold()
	assert_true(panel.folded)


func test_ctrl_space_copies_program_text_to_clipboard() -> void:
	# Place a literal so the program text is something deterministic,
	# then drive the editor's copy helper. Headless Godot's clipboard
	# is a no-op (no window manager), so we verify the user-visible
	# confirmation message + the source-text being correct rather
	# than reading clipboard_get back.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(-1, 0))  # W neighbor of DoHex
	lit.value = 7
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	assert_eq(_editor._build_program_text(), "7",
			"Sanity: program text should be '7' for this setup")
	# Drive the helper and confirm it emitted the confirmation line
	# (the helper's user-visible behaviour beyond the clipboard write).
	_editor.output_panel.clear_output()
	_editor._copy_program_text_to_clipboard()
	# The output panel is a RichTextLabel; check its bbcode for the
	# confirmation substring.
	var output_text: String = _editor.output_panel.output_label.get_parsed_text()
	assert_string_contains(output_text, "copied to clipboard",
			"Ctrl+Space should announce the copy in the output panel")


func test_background_layer_is_independent_of_world_camera() -> void:
	# The shader-based hex grid renders into a dedicated CanvasLayer
	# (layer = -1) that wraps the Background ColorRect. It MUST be a
	# CanvasLayer, otherwise the Camera2D transforms the ColorRect's
	# on-screen position and the shader's FRAGCOORD only spans the
	# shifted rect — causing the grid to drift away from the placed
	# hexes when panning / zooming.
	var bg_layer: CanvasLayer = _editor.get_node_or_null("BackgroundLayer")
	assert_not_null(bg_layer,
			"A CanvasLayer must wrap the shader Background")
	assert_lt(bg_layer.layer, 0,
			"Background CanvasLayer should render behind the default world canvas (layer < 0)")
	var bg: ColorRect = bg_layer.get_node_or_null("Background")
	assert_not_null(bg, "Background ColorRect should live under the CanvasLayer")
	# Background fills its CanvasLayer (which mirrors the viewport),
	# so its anchors are full-rect.
	assert_eq(bg.anchor_right, 1.0)
	assert_eq(bg.anchor_bottom, 1.0)
	# Driving the camera should NOT translate the ColorRect — the
	# CanvasLayer is camera-immune. Snapshot its position, pan the
	# camera, confirm the rect is still at the same place.
	await get_tree().process_frame
	var bg_pos_before := bg.global_position
	_editor.hex_camera.position = Vector2(250, -125)
	await get_tree().process_frame
	assert_eq(bg.global_position, bg_pos_before,
			"Background must stay anchored to the viewport regardless of camera pan")
	# Cleanup.
	_editor.hex_camera.position = Vector2.ZERO


func test_pan_zoom_drives_camera2d_not_world_transform() -> void:
	# Migration guard: pan/zoom now flows through a Camera2D
	# (`%HexCamera`) so a future shader-based hex grid can read the
	# camera transform. The World node itself stays at the identity
	# transform; level-state still saves/restores the camera through
	# the `HexLevel.world_position` / `world_scale` fields (kept for
	# save compatibility, now interpreted as camera coords).
	assert_eq(_editor.world.position, Vector2.ZERO,
			"World Node2D must stay at the identity transform now that " +
			"pan/zoom flow through the Camera2D")
	assert_eq(_editor.world.scale, Vector2.ONE)
	assert_not_null(_editor.hex_camera,
			"HexCamera should be available via %HexCamera")
	# Zoom: factor > 1 means zoom in (Godot 4 Camera2D semantics).
	# Drive zoom through the camera controller (owns pan + zoom now);
	# pivot doesn't matter since the headless mouse pos defaults to
	# (0,0).
	var before: float = _editor.hex_camera.zoom.x
	_editor.hex_camera._zoom_around_cursor(1.1)
	assert_almost_eq(_editor.hex_camera.zoom.x, before * 1.1, 0.001)
	# Restore so other tests sharing the smoke editor see a fresh
	# camera state.
	_editor.hex_camera.zoom = Vector2.ONE
	_editor.hex_camera.position = Vector2.ZERO


func test_per_level_state_round_trips_through_camera() -> void:
	# Push a fake level state into the active HexLevel, switch via
	# _apply_level_view, confirm the camera moves; switching back
	# restores the prior view.
	var level = _editor._current_level()
	level.world_position = Vector2(123, 456)
	level.world_scale = 0.5
	_editor._apply_level_view(level)
	assert_eq(_editor.hex_camera.position, Vector2(123, 456))
	assert_almost_eq(_editor.hex_camera.zoom.x, 0.5, 0.001)
	# Cleanup: reset so other tests sharing the smoke editor see a
	# fresh camera state.
	level.world_position = Vector2.ZERO
	level.world_scale = 1.0
	_editor._apply_level_view(level)


func test_corner_buttons_resolve_by_unique_name() -> void:
	# The buttons live in the left/right corner panels now, but the
	# TopButtons signal hub finds them by unique name. Confirm the
	# Run button resolved (set_run_tooltip relies on it) and that
	# Menu/Help/Codex are reachable from the scene root.
	assert_not_null(_editor.top_buttons.run_button,
			"TopButtons hub should resolve %RunButton by unique name")
	assert_not_null(_editor.get_node_or_null("%MenuButton"))
	assert_not_null(_editor.get_node_or_null("%CodexButton"))
	assert_not_null(_editor.get_node_or_null("%RenownLabel"))


func test_editor_boots_with_default_tabs() -> void:
	assert_eq(_editor._tabs.size(), 6,
			"A fresh editor should bootstrap %d default tabs" % 6)
	assert_eq(_editor._active_tab_idx, 0)
	assert_not_null(_editor.do_node,
			"The active tab's DoHex must be available as `do_node`")


func test_tutorial_chapter_intro_fires_on_entry() -> void:
	# A fresh save (renown 0, no seen intros) should surface the
	# tutorial chapter's intro when the editor opens — the deferred
	# `_maybe_show_next_chapter_intro` runs after _ready. The
	# tutorial's first job is gated at renown 0, so it's unlocked.
	await get_tree().process_frame  # let the deferred call land
	assert_true(SaveManager.has_seen_chapter_intro("chapter_0_tutorial"),
			"Entering the editor on a fresh save should fire (and mark seen) the tutorial intro")


func test_locked_chapter_intro_does_not_fire_on_entry() -> void:
	# Chapter 1's job is renown-gated above 0, so on a fresh save
	# (renown 0) its intro must NOT fire yet.
	await get_tree().process_frame
	assert_false(SaveManager.has_seen_chapter_intro("chapter_1_integer_operators"),
			"A renown-locked chapter should not fire its intro on a fresh save")


func test_chapter_unlock_gate_is_sequential() -> void:
	# Direct unit-check of the gate helper, independent of the deferred
	# entry flow. Unlock is sequential now: solving the predecessor job
	# opens the chapter; renown does not gate it.
	var last_ch: Dictionary = TemplateManager.get_chapter("chapter_8_structures")
	assert_false(last_ch.is_empty())
	SaveManager.current_data["hex"]["solved_jobs"] = {}
	assert_false(ChapterManager.chapter_is_unlocked(last_ch),
			"The last chapter should be locked until its predecessor job is solved")
	var ids: Array = TemplateManager.get_job_ids_sorted()
	SaveManager.record_job_solved(String(ids[ids.size() - 2]), "", 0)
	assert_true(ChapterManager.chapter_is_unlocked(last_ch),
			"The last chapter should unlock once its predecessor job is solved")


func test_switching_tabs_swaps_do_node() -> void:
	var first_do = _editor.do_node
	_editor._switch_to_tab(2)
	assert_eq(_editor._active_tab_idx, 2)
	assert_not_null(_editor.do_node)
	assert_ne(_editor.do_node, first_do,
			"Each tab owns its own DoHex; switching must swap the editor's do_node pointer")


func test_locked_palette_entry_refuses_blueprint() -> void:
	# Match hex is intentionally NOT in the starter unlock set.
	# Loaded via ResourceLoader so the static type checker doesn't try
	# to look up `resource_path` on a GDScript class symbol.
	var match_script: Variant = load("res://src/classes/hex_nodes/control/match_hex.gd")
	assert_false(SaveManager.is_hex_unlocked(match_script.resource_path))
	_editor._enter_blueprint_fresh(match_script)
	assert_null(_editor._blueprint_node,
			"Locked hex types must not enter blueprint mode")


func test_unlock_after_award_lets_blueprint_in() -> void:
	var match_script: Variant = load("res://src/classes/hex_nodes/control/match_hex.gd")
	SaveManager.unlock_hex(match_script.resource_path)
	_editor.palette_bar.set_unlocked_scripts(SaveManager.get_unlocked_hex_scripts())
	_editor._enter_blueprint_fresh(match_script)
	assert_not_null(_editor._blueprint_node,
			"After unlock, the same script should enter blueprint mode")
	# Clean up so we don't leak the preview node into the scene tree.
	_editor._exit_blueprint_mode()


func test_submit_solves_a_real_job_end_to_end() -> void:
	# Pick the simplest shipped job. The job's only requirement is "the
	# program returns an Int", so wiring a single literal into the
	# active tab's DoHex via adjacency is enough.
	var jobs: Array = TemplateManager.get_job_ids_sorted()
	assert_false(jobs.is_empty(), "Test requires at least one shipped job")
	var job_id: String = jobs[0]
	var job: Dictionary = TemplateManager.get_job(job_id)

	# Build the tiniest valid program: an Int hex placed WEST of DoHex
	# at axial (-1, 0) so its eastward output edge (logical 0,
	# rotation 0) feeds DoHex's west input via the adjacency fallback.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(-1, 0))
	lit.level = _editor._current_level()
	lit.value = 42
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)

	# Run check_answer ourselves so we can assert against its result
	# without depending on the rendering / output panel.
	var code: String = _editor._build_program_text()
	var result: Dictionary = Checker.check_answer(job, code)
	assert_true(result.get("correct", false),
			"check_answer should accept '%s' against job %s. message=%s" % [
					code, job_id, result.get("message", "?")])

	# Now drive the editor's submit path so the unlock + renown cascade
	# fires. The check runs on a background thread; await its delivery.
	ChapterManager._selected_job_id = job_id
	_editor._on_submit_pressed()
	await wait_for_signal(ChapterManager.submit_completed, 10)

	assert_true(SaveManager.is_job_solved(job_id),
			"After submit, the job must be recorded as solved")
	assert_gt(SaveManager.get_renown(), 0,
			"Solving a job with a positive renown_reward must increase renown")
	# If the job unlocks any hex types, they should now be in the
	# unlock set.
	for entry in job.get("unlocks_hexes", []):
		var path := StaticData.hex_path(String(entry))
		assert_true(SaveManager.is_hex_unlocked(path),
				"Job's unlock cascade missed %s" % entry)


func test_job_selection_exposes_reserved_identifiers() -> void:
	# Before any selection, white / black must be locked.
	IdentifierPalette.set_exposed_reserved([])
	# Locate the first job whose `variables` includes both white and
	# black so we can exercise the two-arg path. If none of the
	# shipped jobs do, this test is a no-op (it would still fail
	# loudly if the gate is misbehaving).
	var two_arg_id := ""
	var one_arg_id := ""
	for id in TemplateManager.get_all_jobs().keys():
		var vars: Dictionary = TemplateManager.get_job(id).get("variables", {})
		if vars.has("white") and vars.has("black") and two_arg_id == "":
			two_arg_id = id
		elif vars.has("white") and not vars.has("black") and one_arg_id == "":
			one_arg_id = id
	if one_arg_id != "":
		ChapterManager._selected_job_id = ""
		ChapterManager.select_job(one_arg_id)  # toggles select on
		var exposed: Array = IdentifierPalette.get_exposed_reserved()
		assert_true("white" in exposed,
				"Single-arg job (%s) should expose `white`" % one_arg_id)
		assert_false("black" in exposed,
				"Single-arg job (%s) should NOT expose `black`" % one_arg_id)
	if two_arg_id != "":
		ChapterManager._selected_job_id = ""
		ChapterManager.select_job(two_arg_id)
		var exposed: Array = IdentifierPalette.get_exposed_reserved()
		assert_true("white" in exposed,
				"Two-arg job (%s) should expose `white`" % two_arg_id)
		assert_true("black" in exposed,
				"Two-arg job (%s) should expose `black`" % two_arg_id)
	# Deselecting (re-toggling the same id off) must relock both.
	if one_arg_id != "" or two_arg_id != "":
		var id_to_toggle: String = two_arg_id if two_arg_id != "" else one_arg_id
		ChapterManager.select_job(id_to_toggle)  # toggles back off
		assert_eq(IdentifierPalette.get_exposed_reserved(), [],
				"Deselecting the job must relock all reserved identifiers")


func test_run_button_submits_when_a_job_is_selected() -> void:
	# Build the same minimal valid program as the submit test.
	var jobs: Array = TemplateManager.get_job_ids_sorted()
	var job_id: String = jobs[0]
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(-1, 0))
	lit.level = _editor._current_level()
	lit.value = 42
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	# Pick the job — Run should now go through the (async) submit path.
	ChapterManager._selected_job_id = job_id
	_editor._on_run_pressed()
	await wait_for_signal(ChapterManager.submit_completed, 10)
	assert_true(SaveManager.is_job_solved(job_id),
			"With a job selected, Run must drive the submit path so the solve registers.")


func test_f_cycles_pending_jobs_and_returns_to_empty() -> void:
	# The sequential gate keeps exactly one job pending at a time, so use
	# archmage to open every job at once — the only state with a
	# multi-job pending pool for the cycler to round-trip. after_each
	# clears archmage.
	SaveManager.set_archmage(true)
	SaveManager.current_data["hex"]["solved_jobs"] = {}
	var pending: Array = ChapterManager.pending_job_ids()
	assert_true(pending.size() >= 2,
			"Test requires at least two pending jobs to round-trip the cycler")
	# Start from empty selection. F steps to the first pending job.
	ChapterManager._selected_job_id = ""
	ChapterManager.cycle_pending_jobs(1)
	assert_eq(ChapterManager.get_selected_job_id(), String(pending[0]))
	# Stepping forward through every pending job lands on the empty
	# sentinel one step past the last one.
	for i in range(1, pending.size()):
		ChapterManager.cycle_pending_jobs(1)
		assert_eq(ChapterManager.get_selected_job_id(), String(pending[i]),
				"F should walk through the pending list in order")
	ChapterManager.cycle_pending_jobs(1)
	assert_eq(ChapterManager.get_selected_job_id(), "",
			"One step past the last pending job must clear the selection")
	# Shift+F (direction=-1) from empty goes to the last pending job.
	ChapterManager.cycle_pending_jobs(-1)
	assert_eq(ChapterManager.get_selected_job_id(), String(pending[pending.size() - 1]),
			"Shift+F from empty should wrap to the last pending job")


func test_palette_excludes_lte_and_gt() -> void:
	# Decluttering decision: `<=` and `>` are gone from the palette
	# because `<` and `>=` cover the same operator semantics. Guard
	# against accidental re-introduction.
	var labels: Array = _editor.palette_bar.scripts_in_category("Boolean")
	assert_false("<=" in labels, "Less-or-equal hex should not be in the palette")
	assert_false(">" in labels, "Greater-than hex should not be in the palette")
	assert_true("<" in labels)
	assert_true(">=" in labels)


func test_marquee_delete_bulks_into_one_undo_step() -> void:
	# Place three Int hexes, bulk-delete them, then Ctrl+Z once.
	# Every hex should come back in a single undo step.
	var lits: Array = []
	for ax in [Vector2i(-2, 0), Vector2i(0, 0), Vector2i(2, 0)]:
		var h := HexNode.from_script(IntLiteralHex)
		_editor.nodes_layer.add_child(h)
		h.set_axial(ax)
		h.level = _editor._current_level()
		_editor._current_level().hexes.append(h)
		_editor._wire_node_signals(h)
		lits.append(h)
	# Drive _delete_hex with push_undo=false and stash the records under
	# one bulk entry — mirrors what _commit_marquee does.
	var records: Array = []
	for h in lits:
		records.append(_editor._delete_hex(h, false))
	_editor._push_undo({
		"type": "delete_hexes_bulk",
		"level": _editor._current_level(),
		"entries": records,
	})
	for h in lits:
		assert_false(h in _editor._current_level().hexes,
				"hex should be removed before undo")
	_editor._undo()
	for h in lits:
		assert_true(h in _editor._current_level().hexes,
				"All marquee-deleted hexes should be restored by one Ctrl+Z")


func test_cut_copies_to_stamp_and_deletes_originals() -> void:
	# Place two Int hexes, select them, Ctrl+X. The stamp should
	# carry the payload, the originals should be gone, and Ctrl+Z
	# should restore both originals in one step.
	var lits: Array[HexNode] = []
	for ax in [Vector2i(-2, 0), Vector2i(2, 0)]:
		var h := HexNode.from_script(IntLiteralHex)
		_editor.nodes_layer.add_child(h)
		h.set_axial(ax)
		h.level = _editor._current_level()
		_editor._current_level().hexes.append(h)
		_editor._wire_node_signals(h)
		lits.append(h)
	_editor._replace_selection(lits)
	_editor._ctrl_x_cut_selection_to_stamp()
	for h in lits:
		assert_false(h in _editor._current_level().hexes,
				"Originals should be removed after cut")
	assert_false(_editor._stamp_previews.is_empty(),
			"Cut should leave the stamp mode armed with a payload")
	_editor._exit_stamp_mode()
	_editor._undo()
	for h in lits:
		assert_true(h in _editor._current_level().hexes,
				"One Ctrl+Z should restore every cut hex in a single step")


func test_marquee_select_highlights_enclosed_hexes() -> void:
	# Place three hexes in a horizontal row; the marquee covers the
	# middle two only.
	var lits: Array[IntLiteralHex] = []
	for ax in [Vector2i(-2, 0), Vector2i(0, 0), Vector2i(2, 0)]:
		var h := HexNode.from_script(IntLiteralHex)
		_editor.nodes_layer.add_child(h)
		h.set_axial(ax)
		h.level = _editor._current_level()
		_editor._current_level().hexes.append(h)
		_editor._wire_node_signals(h)
		lits.append(h)
	# Drag a tight rect over the middle hex's axial. World coords scale
	# axials by HEX_SIZE-derived offsets — keep the rect modest so it
	# only touches the (0, 0) hex.
	_editor._marquee_active = true
	_editor._marquee_is_delete = false
	_editor._marquee_start_world = Vector2(-30, -50)
	# Override _mouse_world by feeding the rect computation manually:
	# we replace `_marquee_world_rect` indirectly by populating both
	# endpoints. (The helper reads `_mouse_world()` which is the real
	# cursor; in headless mode that's somewhere offscreen.)
	var rect := Rect2(Vector2(-30, -50), Vector2(60, 100))
	var hits: Array[HexNode] = []
	for h in _editor._current_level().hexes:
		if h.is_fixture:
			continue
		if rect.has_point(HexMath.axial_to_world(h.axial, HexNode.HEX_SIZE)):
			hits.append(h)
	_editor._replace_selection(hits)
	assert_eq(_editor._selected_hexes.size(), 1,
			"Only the middle Int should fall inside the tight rect")
	assert_eq(_editor._selected_hexes[0], lits[1])
	# Esc clears selection.
	_editor._clear_selection()
	assert_true(_editor._selected_hexes.is_empty())
	assert_eq(lits[1].modulate, Color.WHITE,
			"Clearing the selection should restore the hex's default tint")


func test_marquee_delete_removes_hexes_in_rect() -> void:
	# Two hexes, drag a rect covering both → both get deleted.
	var a := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(a)
	a.set_axial(Vector2i(3, 0))
	a.level = _editor._current_level()
	_editor._current_level().hexes.append(a)
	_editor._wire_node_signals(a)
	var b := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(b)
	b.set_axial(Vector2i(4, 0))
	b.level = _editor._current_level()
	_editor._current_level().hexes.append(b)
	_editor._wire_node_signals(b)
	# Drive the deletion path the same way _commit_marquee does, but
	# with an explicit hit set (avoids depending on the real cursor in
	# the headless harness).
	var hits: Array[HexNode] = [a, b]
	for h in hits:
		_editor._delete_hex(h)
	assert_false(a in _editor._current_level().hexes,
			"hex 'a' must be removed from the level after marquee delete")
	assert_false(b in _editor._current_level().hexes,
			"hex 'b' must be removed from the level after marquee delete")


func test_job_display_reflects_selection() -> void:
	# No selection → neutral label.
	ChapterManager._selected_job_id = ""
	_editor._refresh_job_display()
	assert_eq(_editor.job_header.name_label.text, "No job selected")
	# Selected → name appears in the large label, description in the
	# rich-text label.
	var jobs: Array = TemplateManager.get_job_ids_sorted()
	var job_id: String = jobs[0]
	var job: Dictionary = TemplateManager.get_job(job_id)
	ChapterManager._selected_job_id = job_id
	_editor._refresh_job_display()
	assert_eq(_editor.job_header.name_label.text, String(job.get("name", job_id)))
	assert_true(_editor.job_header.description_label.text.find(
			String(job.get("description", ""))) >= 0,
			"Description label must carry the job's description text")


func test_clicking_a_hex_tints_it_cyan() -> void:
	# Opening the config sidebar should also place the hex in the
	# selection set (single-hex selection) — clicking IS selecting,
	# per the Phase 19.4 polish.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(2, 2))
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	_editor._open_config_sidebar(lit)
	assert_eq(_editor._selected_hexes.size(), 1,
			"Opening the config sidebar must single-select the hex")
	assert_eq(_editor._selected_hexes[0], lit)
	assert_ne(lit.modulate, Color.WHITE,
			"Selected hex should carry the cyan tint, not the default WHITE")


func test_extend_selection_adds_without_replacing() -> void:
	# Place three hexes, single-select one, then extend with the other
	# two — final selection size is 3.
	var lits: Array[IntLiteralHex] = []
	for ax in [Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2)]:
		var h := HexNode.from_script(IntLiteralHex)
		_editor.nodes_layer.add_child(h)
		h.set_axial(ax)
		h.level = _editor._current_level()
		_editor._current_level().hexes.append(h)
		_editor._wire_node_signals(h)
		lits.append(h)
	# Single-select the first.
	_editor._replace_selection([lits[0]] as Array[HexNode])
	assert_eq(_editor._selected_hexes.size(), 1)
	# Shift-extend with the other two.
	_editor._extend_selection([lits[1], lits[2]] as Array[HexNode])
	assert_eq(_editor._selected_hexes.size(), 3,
			"Shift-extend should add to the existing selection, not replace it")
	# Extending with a hex that's already selected is a no-op.
	_editor._extend_selection([lits[1]] as Array[HexNode])
	assert_eq(_editor._selected_hexes.size(), 3,
			"Re-adding an already-selected hex should not duplicate it")


func test_x_with_selection_bulk_deletes() -> void:
	# X with a non-empty selection deletes every selected hex
	# (the keyboard mirror of Shift+RMB drag-to-delete).
	var a := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(a)
	a.set_axial(Vector2i(7, 0))
	a.level = _editor._current_level()
	_editor._current_level().hexes.append(a)
	_editor._wire_node_signals(a)
	var b := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(b)
	b.set_axial(Vector2i(7, 1))
	b.level = _editor._current_level()
	_editor._current_level().hexes.append(b)
	_editor._wire_node_signals(b)
	_editor._replace_selection([a, b] as Array[HexNode])
	_editor._delete_selection()
	assert_false(a in _editor._current_level().hexes,
			"X with a selection must remove every selected hex")
	assert_false(b in _editor._current_level().hexes)
	assert_true(_editor._selected_hexes.is_empty(),
			"Selection should be cleared once its members are deleted")


func test_rmb_on_hex_without_context_deletes_it() -> void:
	# RMB is the contextual-cancel button — but only contextual.
	# With no selection, no wire, no open sidebar there's nothing to
	# cancel, so RMB falls through to the `hex_delete` action and
	# removes the clicked hex. (The keyboard route is still `X`.)
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(9, 0))
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	# Make sure no context is active.
	_editor._clear_selection()
	if _editor._config_target != null:
		_editor._close_config_sidebar()
	_editor._on_node_delete_requested(lit)
	assert_false(lit in _editor._current_level().hexes,
			"RMB on a hex with no contextual state should delete it")


func test_right_click_on_hex_with_selection_clears_instead_of_deleting() -> void:
	# Single-click a hex (selects it), then simulate the body's RMB
	# emission. Selection should clear; the hex should still be alive.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(2, 3))
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	_editor._open_config_sidebar(lit)
	assert_false(_editor._selected_hexes.is_empty())
	_editor._on_node_delete_requested(lit)
	assert_true(_editor._selected_hexes.is_empty(),
			"RMB with a selection must clear the selection")
	assert_true(lit in _editor._current_level().hexes,
			"RMB must NOT delete the hex on first press when a selection exists")


func test_ctrl_c_copies_selection_and_enters_stamp_mode() -> void:
	# Build a tiny selection (one Int), Ctrl+C, confirm stamp mode is
	# active and the session clipboard holds the payload.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(4, 4))
	lit.value = 99
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	_editor._replace_selection([lit] as Array[HexNode])
	_editor._ctrl_c_copy_selection_to_stamp()
	assert_false(_editor._stamp_payload.is_empty(),
			"Ctrl+C should immediately enter stamp mode")
	assert_false(_editor._stamp_previews.is_empty())
	assert_false(_editor._last_copied_payload.is_empty(),
			"Ctrl+C should populate the session clipboard")
	# Selection cleared once it's in stamp mode (it's the cursor's job now).
	assert_true(_editor._selected_hexes.is_empty())
	_editor._exit_stamp_mode()


func test_commit_stamp_re_arms_for_repeat_placement() -> void:
	# Build a 1-hex blueprint payload, enter stamp mode, commit at a
	# fixed anchor, confirm stamp mode is still active (re-armed).
	var canvas_payload := BlueprintCodec.serialize_subset(
		[(func() -> Node:
			var l := HexNode.from_script(IntLiteralHex)
			_editor.nodes_layer.add_child(l)
			l.set_axial(Vector2i(8, 8))
			l.level = _editor._current_level()
			l.value = 5
			_editor._current_level().hexes.append(l)
			_editor._wire_node_signals(l)
			return l).call()],
		_editor,
		"stampable",
	)
	_editor._begin_stamp(canvas_payload)
	assert_false(_editor._stamp_previews.is_empty())
	_editor._stamp_anchor_axial = Vector2i(20, 20)
	for entry in _editor._stamp_previews:
		entry.node.set_axial(_editor._stamp_anchor_axial + entry.rel_axial)
	_editor._commit_stamp()
	await get_tree().process_frame
	# Factorio-style: the stamp re-arms with the same payload so a
	# subsequent left-click drops another copy.
	assert_false(_editor._stamp_payload.is_empty(),
			"After commit, stamp mode should re-arm for repeat placement")
	assert_false(_editor._stamp_previews.is_empty())
	_editor._exit_stamp_mode()


func test_stamp_rotation_persists_across_exit() -> void:
	# Build a 1-hex blueprint, enter stamp mode, rotate twice, exit,
	# re-enter — rotation should still be 2 (Factorio-style sticky
	# rotation).
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(11, 0))
	lit.value = 1
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	var payload := BlueprintCodec.serialize_subset(
		[lit], _editor, "rot-persist"
	)
	_editor._begin_stamp(payload)
	_editor._rotate_stamp(1)
	_editor._rotate_stamp(1)
	assert_eq(_editor._stamp_rotation, 2,
			"Sanity: rotate_stamp should increment _stamp_rotation")
	_editor._exit_stamp_mode()
	_editor._begin_stamp(payload)
	assert_eq(_editor._stamp_rotation, 2,
			"Rotation should persist across stamp exit / re-enter")
	_editor._exit_stamp_mode()


func test_lmb_on_empty_cell_clears_selection() -> void:
	# Single-select a hex, then simulate a plain LMB press on a
	# clearly-empty cell (no hex, no wire) — selection should clear.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(13, 0))
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	_editor._replace_selection([lit] as Array[HexNode])
	assert_false(_editor._selected_hexes.is_empty(),
			"Sanity: selection should be non-empty before the click")
	# Drive the empty-cell branch directly — we can't synthesize an
	# accurate mouse press in headless mode, but the user-facing
	# behaviour comes down to: when LMB lands on a non-hex / non-wire
	# cell with no shift / blueprint / stamp / wire-active, close
	# config AND clear selection.
	_editor._close_config_sidebar()
	_editor._clear_selection()
	assert_true(_editor._selected_hexes.is_empty(),
			"Plain LMB on empty canvas should clear the selection")


func test_new_and_close_tab_helpers() -> void:
	# Ctrl+T's handler is _on_new_tab_pressed; Ctrl+W's is _close_tab.
	# Drive them directly — the keybinding wiring itself is part of
	# the unhandled-input dispatcher and isn't exercised by the
	# headless harness, but the helpers ARE the meaningful surface.
	var initial: int = _editor._tabs.size()
	_editor._on_new_tab_pressed()
	await get_tree().process_frame
	assert_eq(_editor._tabs.size(), initial + 1,
			"Ctrl+T (via _on_new_tab_pressed) should add a tab")
	# Close the tab we just created. _close_tab refuses to close the
	# last remaining tab, so this is always safe when count >= 2.
	var new_idx: int = _editor._active_tab_idx
	_editor._close_tab(new_idx)
	await get_tree().process_frame
	assert_eq(_editor._tabs.size(), initial,
			"Ctrl+W (via _close_tab) should remove the active tab")


func test_tab_persistence_round_trips_a_graph() -> void:
	# Build a 1-hex graph on the active tab, drive _persist_tab_layout,
	# then simulate a session restart by tearing the editor down and
	# spinning up a fresh one. The new editor's active tab should
	# carry the same Int hex (and emit the same generated text).
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(-1, 0))  # W neighbor of DoHex
	lit.value = 99
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	assert_eq(_editor._build_program_text(), "99")
	_editor._persist_tab_layout()
	# Confirm the saved tab payload actually has hexes.
	var saved: Array = SaveManager.get_tab_payloads()
	var active_payload: Dictionary = saved[_editor._active_tab_idx].get("payload", {})
	assert_false(Dictionary(active_payload).is_empty(),
			"Active tab's payload should round-trip with content")
	assert_true(active_payload.get("hexes", []).size() >= 1,
			"Persisted payload should include the placed Int hex")
	# Spin up a fresh editor instance — the bootstrap path is what
	# we want to exercise. autofree handles cleanup.
	var fresh: Node = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(fresh)
	await get_tree().process_frame
	# Switch to the tab the original was on, then read its program.
	fresh._switch_to_tab(_editor._active_tab_idx)
	await get_tree().process_frame
	assert_eq(fresh._build_program_text(), "99",
			"Restored tab should emit the same program text as the captured one")


func test_capture_and_stamp_round_trip() -> void:
	# Build a tiny program on the active tab (Int(7) adjacent to DoHex
	# so the auto-adjacency feeds it), capture it as a blueprint, open
	# a fresh tab, stamp the blueprint, confirm the generated text
	# matches.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(-1, 0))  # W neighbor of DoHex at (0,0)
	lit.value = 7
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	var original_text: String = _editor._build_program_text()
	assert_eq(original_text, "7")
	# Capture (drive `_do_capture` directly — the dialog flow only
	# collects the name).
	var tab = _editor._tabs[_editor._active_tab_idx]
	_editor._do_capture(tab, "seven")
	var bps: Array = SaveManager.get_blueprints()
	assert_true(bps.size() >= 1)
	var saved: Dictionary = bps[bps.size() - 1]
	assert_eq(String(saved["name"]), "seven")
	assert_true(saved.has("payload"),
			"captured blueprint must carry a structured payload")
	# Stamp into a fresh tab so the assertion is unambiguous (no
	# pre-existing hexes in the way).
	_editor._on_new_tab_pressed()
	await get_tree().process_frame
	_editor._begin_stamp(saved["payload"])
	assert_false(_editor._stamp_previews.is_empty(),
			"stamp mode should have produced previews")
	# Force the anchor to (0,0) so the Int (which was at relative
	# (-1, 0)) lands adjacent to the new tab's DoHex, mirroring the
	# original capture's adjacency.
	_editor._stamp_anchor_axial = Vector2i.ZERO
	for entry in _editor._stamp_previews:
		entry.node.set_axial(_editor._stamp_anchor_axial + entry.rel_axial)
	_editor._commit_stamp()
	await get_tree().process_frame
	var stamped_text: String = _editor._build_program_text()
	assert_eq(stamped_text, original_text,
			"stamped blueprint should emit the same source as the capture")
	# Round-trip through the string form too.
	var encoded: String = BlueprintCodec.encode(saved["payload"])
	assert_true(encoded.begins_with("hxk1:"),
			"encoded form should carry the schema prefix")
	var decoded = BlueprintCodec.decode(encoded)
	assert_typeof(decoded, TYPE_DICTIONARY)
	assert_eq(int(decoded["version"]), BlueprintCodec.SCHEMA_VERSION)


func test_quick_repl_open_does_not_parse_program() -> void:
	# Place an Int hex that's NOT wired so the program text contains a
	# `_HOLE_` placeholder — parsing would push a `Free variable
	# _HOLE_` runtime error if the REPL eagerly evaluated.
	# Drop the IntLiteralHex without adjacency to keep DoHex unwired.
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(5, 5))  # nowhere near DoHex
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	# Sanity: the program text now contains the unconnected marker.
	var code: String = _editor._build_program_text()
	assert_true(code.find("_HOLE_") != -1,
			"Test setup: program text should contain _HOLE_ when DoHex is unwired")
	# Opening the REPL must not parse / interpret the program. The
	# editor's `environment` member is whatever was last installed
	# (here, just Prelude from _ready), and the REPL opens against it.
	_editor._open_quick_repl()
	assert_true(_editor.quick_repl_dialog.visible,
			"Quick REPL must open even when the program text is malformed")
	# Hide it again so other tests aren't surprised by an open overlay.
	_editor.quick_repl_dialog.close()


func test_category_switch_takes_one_click() -> void:
	# Regression: the category buttons used to share a ButtonGroup while
	# palette_bar.gd also managed exclusivity manually. The group's
	# unpress-old-before-press-new ordering ran the old button's
	# toggled(false) → select_category(-1) → set_pressed_no_signal(false)
	# on the button being clicked, so the click's own toggled emission
	# fired with false: first click deselected everything, second click
	# selected. With the group removed, one click must switch categories.
	var palette = _editor.palette_bar
	palette.select_category(0)
	assert_eq(palette.get_current_category(), 0)
	var btn = palette.get_category_button(1)
	btn.button_pressed = true  # real setter — emits toggled, like a click
	assert_eq(palette.get_current_category(), 1,
			"One click on category 1 must select it (not deselect to -1)")
	assert_true(palette.get_hex_rows()[1].visible,
			"Category 1's hex row must be visible after a single click")
	assert_false(palette.get_category_button(0).button_pressed,
			"Old category button must be unpressed by the script's own radio logic")


func test_hex_switch_takes_one_click() -> void:
	# Same regression for the hex buttons' shared ButtonGroup: clicking
	# hex B while hex A is active must activate B in one toggle and must
	# not fire blueprint_mode_cancelled on the way.
	var palette = _editor.palette_bar
	palette.set_archmage(true)  # renown is 0 in this suite; unlock everything
	palette.select_category(0)
	var cancelled := [0]
	palette.blueprint_mode_cancelled.connect(func(): cancelled[0] += 1)
	var buttons: Array = palette._hex_buttons_of(palette.get_hex_rows()[0])
	assert_gt(buttons.size(), 1, "Integer category needs ≥2 buttons for this test")
	# The editor re-validates against SaveManager in _enter_blueprint_fresh,
	# so the palette-side archmage flag alone isn't enough.
	SaveManager.unlock_hex(buttons[1].hex_script.resource_path)
	buttons[0].button_pressed = true
	assert_eq(palette._active_script, buttons[0].hex_script,
			"First hex click must activate its script")
	buttons[1].button_pressed = true
	assert_eq(palette._active_script, buttons[1].hex_script,
			"Switching hexes must take one click")
	assert_false(buttons[0].button_pressed,
			"Old hex button must be unpressed via set_pressed_no_signal")
	assert_eq(cancelled[0], 0,
			"Switching hexes must not emit blueprint_mode_cancelled")


# A user delete pops + shrinks the hex (tracked tween), and a restore
# (undo) cancels that animation and brings the hex back at full size.
func test_hex_delete_animation_and_restore() -> void:
	var lit := HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(lit)
	lit.set_axial(Vector2i(2, -2))  # empty cell, not adjacent to the Do fixture
	lit.level = _editor._current_level()
	_editor._current_level().hexes.append(lit)
	_editor._wire_node_signals(lit)
	var rec: Dictionary = _editor._delete_hex(lit)
	assert_false(rec.is_empty(), "deleting a normal hex returns a record")
	assert_false(lit in _editor._current_level().hexes,
			"the hex is removed from the level immediately")
	assert_true(_editor._hex_fx_tweens.has(lit),
			"a delete animation tween is running")
	# Restore (as undo does) cancels the shrink and resets the hex.
	_editor._restore_hex(lit)
	assert_false(_editor._hex_fx_tweens.has(lit), "the delete tween is cancelled")
	assert_eq(lit.scale, Vector2.ONE, "the restored hex is back at full size")
	assert_true(lit.visible, "the restored hex is visible again")
