extends GutTest
## Editor-interaction QoL friction-pass coverage. Grows per QoL commit.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const HexMath := preload("res://src/statics/hex_math.gd")
const LetHex := preload("res://src/classes/hex_nodes/control/let_hex.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")


var _saved_hex: Dictionary
var _saved_autosave: bool
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	_saved_autosave = SaveManager.get_auto_save()
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
	SaveManager.current_data["preferences"]["auto_save"] = _saved_autosave
	SaveManager.set_archmage(false)
	ModalStack.reset(get_tree())


func _first_option_button(root: Node) -> OptionButton:
	for c in root.get_children():
		if c is OptionButton:
			return c
		var found := _first_option_button(c)
		if found != null:
			return found
	return null


func _place(script: Script, axial: Vector2i) -> HexNode:
	var hex: HexNode = HexNode.from_script(script)
	_editor.nodes_layer.add_child(hex)
	hex.set_axial(axial)
	hex.level = _editor._current_level()
	_editor._current_level().hexes.append(hex)
	_editor._wire_node_signals(hex)
	return hex


# Step 1: a long identifier name must not push the PanelContainer-backed
# config sidebar off-screen — the picker doesn't size to its longest item.
func test_identifier_config_option_does_not_fit_to_longest() -> void:
	var hex: HexNode = HexNode.from_script(IdentRefHex)
	add_child_autofree(hex)
	var ui := hex.build_config_ui()
	add_child_autofree(ui)
	var opt := _first_option_button(ui)
	assert_not_null(opt, "identifier config UI should expose an OptionButton")
	assert_false(opt.fit_to_longest_item,
			"identifier picker must not size to its longest item, or the config panel overflows")


# Step 2: opening the output panel (unfold) closes the config sidebar
# (wired in-scene: OutputPanel.folding_changed → config_sidebar handler).
func test_unfolding_output_closes_config() -> void:
	var lit := _place(IntLiteralHex, Vector2i(2, 0))
	_editor._open_config_sidebar(lit)
	assert_true(_editor.config_sidebar.visible, "config sidebar should be visible")
	# The output panel unfolding routes through this handler.
	_editor.config_sidebar._on_output_panel_folding_changed(false)
	assert_false(_editor.config_sidebar.visible,
			"opening the output panel should close the config sidebar")


# Step 3: RMB in stamp mode only exits stamp — it never deletes a hex.
func test_rmb_in_stamp_mode_exits_stamp_and_keeps_hexes() -> void:
	var a := _place(IntLiteralHex, Vector2i(2, 0))
	var b := _place(IntLiteralHex, Vector2i(3, 0))
	_editor._replace_selection([a] as Array[HexNode])
	_editor._ctrl_c_copy_selection_to_stamp()
	assert_false(_editor._stamp_previews.is_empty(), "sanity: stamp armed")
	# RMB over hex b while stamping.
	_editor._on_node_delete_requested(b)
	assert_true(_editor._stamp_previews.is_empty(),
			"RMB in stamp mode should exit stamp")
	assert_true(b in _editor._current_level().hexes,
			"RMB in stamp mode must NOT delete the hex")
	_editor._exit_stamp_mode()


# Step 3: RMB with the config panel open closes it instead of deleting.
func test_rmb_with_config_open_closes_it_without_deleting() -> void:
	var lit := _place(IntLiteralHex, Vector2i(4, 0))
	_editor._open_config_sidebar(lit)
	assert_true(_editor.is_config_open(), "sanity: config open")
	_editor._on_node_delete_requested(lit)
	assert_false(_editor.is_config_open(),
			"RMB should close the config panel")
	assert_true(lit in _editor._current_level().hexes,
			"RMB must not delete the hex while the config panel is active")


# Step 4: double-click pickup cuts the hex to the stamp for repositioning.
func test_pickup_removes_original_and_arms_stamp() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	_editor._pickup_hex(lit)
	assert_false(lit in _editor._current_level().hexes,
			"pickup should remove the original hex from the level")
	assert_false(_editor._stamp_previews.is_empty(),
			"pickup should arm the stamp so the hex can be re-placed")
	assert_false(_editor._last_copied_payload.is_empty(),
			"pickup should populate the stamp payload (config preserved)")
	_editor._exit_stamp_mode()


# Step 4: fixtures (level pivots) can't be picked up.
func test_pickup_ignores_fixtures() -> void:
	var fixture: HexNode = null
	for h in _editor._current_level().hexes:
		if h.is_fixture:
			fixture = h
			break
	assert_not_null(fixture, "level should have a fixture (DoHex anchor)")
	_editor._pickup_hex(fixture)
	assert_true(_editor._stamp_previews.is_empty(),
			"picking up a fixture must be a no-op")
	assert_true(fixture in _editor._current_level().hexes,
			"the fixture must remain in the level")


# Arm a pickup on `src` and drop it onto `target_axial` (no rotation).
func _pickup_commit(src: HexNode, target_axial: Vector2i) -> void:
	_editor._pickup_hex(src)
	var prev: Dictionary = _editor._stamp_previews[0]
	_editor._stamp_rotation = 0
	_editor._stamp_anchor_axial = target_axial - HexMath.rotate_axial(prev.rel_axial, 0)
	_editor._commit_stamp()


# Pickup: a translucent ghost of the original stays at its origin while moving.
func test_pickup_ghosts_original_in_place() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	_editor._pickup_hex(lit)
	assert_true(_editor._pickup_active, "pickup arms move mode")
	assert_false(lit in _editor._current_level().hexes,
			"the original leaves the active hex list while in hand")
	assert_true(lit.visible, "the ghost stays visible at its origin")
	assert_eq(lit.modulate, _editor.PICKUP_GHOST_TINT,
			"the origin hex renders as a translucent ghost")
	assert_eq(lit.axial, Vector2i(5, 0), "the ghost sits at the original cell")
	_editor._exit_stamp_mode()


# Pickup commit places once and EXITS (no Factorio-style re-arm).
func test_pickup_commit_exits_without_rearm() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	_pickup_commit(lit, Vector2i(-4, 0))
	assert_true(_editor._stamp_previews.is_empty(),
			"a move places once and exits — no re-armed stamp")
	assert_false(_editor._pickup_active, "pickup state cleared after the move")
	var at_target := 0
	for h in _editor._current_level().hexes:
		if h.axial == Vector2i(-4, 0):
			at_target += 1
	assert_eq(at_target, 1, "the hex landed at the drop cell")


# RMB cancels a move: the original returns to its origin, nothing pushed to undo.
func test_pickup_rmb_cancels_and_restores_original() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	var undo_before: int = _editor._undo_stack.size()
	_editor._pickup_hex(lit)
	# RMB while a pickup is armed routes through the stamp-cancel branch.
	assert_true(_editor._rmb_contextual_cancel(), "RMB consumes the cancel")
	assert_true(lit in _editor._current_level().hexes,
			"RMB returns the original to the level")
	assert_eq(lit.axial, Vector2i(5, 0), "restored at its original cell")
	assert_eq(lit.modulate, Color.WHITE, "ghost tint cleared on restore")
	assert_false(_editor._pickup_active, "pickup state cleared")
	assert_true(_editor._stamp_previews.is_empty(), "previews torn down")
	assert_eq(_editor._undo_stack.size(), undo_before,
			"a cancelled move pushes no undo entry")


# A completed move is a SINGLE undo entry: one Ctrl+Z reverts it fully.
func test_pickup_move_is_single_undo() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	var undo_before: int = _editor._undo_stack.size()
	_pickup_commit(lit, Vector2i(-4, 0))
	assert_eq(_editor._undo_stack.size(), undo_before + 1,
			"a move is exactly one undo entry")
	var action: Dictionary = _editor._undo_stack[-1]
	assert_eq(action.type, "place_stamp")
	assert_false(action.get("removed", []).is_empty(),
			"the move folds the original's removal into the entry")
	# One undo reverts the whole move.
	_editor._undo()
	assert_true(lit in _editor._current_level().hexes,
			"undo returns the original to its origin")
	assert_eq(lit.axial, Vector2i(5, 0))
	var at_target := 0
	for h in _editor._current_level().hexes:
		if h.axial == Vector2i(-4, 0):
			at_target += 1
	assert_eq(at_target, 0, "undo also removes the placed hex")
	# Redo re-applies the move.
	_editor._redo()
	assert_false(lit in _editor._current_level().hexes,
			"redo re-parks the original")


# A blocked commit (different-type hex at the drop cell) is a no-op that
# leaves the pickup armed — LMB must never silently eat the hex.
func test_pickup_blocked_commit_keeps_armed() -> void:
	var blocker := _place(LetHex, Vector2i(-4, 0))
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	_editor._pickup_hex(lit)
	var prev: Dictionary = _editor._stamp_previews[0]
	_editor._stamp_rotation = 0
	_editor._stamp_anchor_axial = Vector2i(-4, 0) - HexMath.rotate_axial(prev.rel_axial, 0)
	assert_true(_editor._stamp_has_collision(), "sanity: drop cell is blocked")
	_editor._commit_stamp()
	assert_true(_editor._pickup_active, "a blocked commit keeps the pickup armed")
	assert_false(_editor._stamp_previews.is_empty(), "previews persist")
	assert_false(lit in _editor._current_level().hexes, "original still parked")
	_editor._exit_stamp_mode()


# Switching context mid-pickup (modelled by _exit_stamp_mode) restores the hex.
func test_pickup_exit_stamp_mode_restores_original() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	_editor._pickup_hex(lit)
	_editor._exit_stamp_mode()
	assert_false(_editor._pickup_active, "pickup cleared on exit")
	assert_true(lit in _editor._current_level().hexes,
			"a mid-move context switch returns the hex")


# A pickup is a move, not a delete — it must not fire `hex_deleted`
# (which the tutorial treats as a required hex being destroyed).
func test_pickup_does_not_emit_hex_deleted() -> void:
	var lit := _place(IntLiteralHex, Vector2i(5, 0))
	var fired := [false]
	var on_deleted := func(_n): fired[0] = true
	_editor.hex_deleted.connect(on_deleted)
	_editor._pickup_hex(lit)
	assert_false(fired[0], "pickup must not emit hex_deleted")
	_editor.hex_deleted.disconnect(on_deleted)
	_editor._exit_stamp_mode()


# Step 5: stamping a same-type hex onto a placed one re-orients the
# existing hex (keeping its config) instead of placing a duplicate.
func test_same_type_overlap_rotates_existing_keeps_config() -> void:
	var target := _place(IntLiteralHex, Vector2i(5, 0))
	target.value = 42
	target.set_rotation_index(0)
	var source := _place(IntLiteralHex, Vector2i(8, 0))
	# Pick the source up (arms the stamp), then drop it on the target's
	# cell at a different rotation.
	_editor._pickup_hex(source)
	assert_false(_editor._stamp_previews.is_empty(), "sanity: stamp armed")
	var prev: Dictionary = _editor._stamp_previews[0]
	_editor._stamp_rotation = 2
	_editor._stamp_anchor_axial = target.axial - HexMath.rotate_axial(prev.rel_axial, 2)
	var hexes_before: int = _editor._current_level().hexes.size()
	_editor._commit_stamp()
	# The existing hex was re-oriented, not replaced.
	assert_true(target in _editor._current_level().hexes,
			"the existing hex must survive the overlap")
	assert_eq(target.rotation_index, 2,
			"the existing hex should take the stamp's rotation")
	assert_eq(target.value, 42, "the existing hex keeps its own config")
	# No duplicate landed on the cell.
	var at_cell := 0
	for h in _editor._current_level().hexes:
		if h.axial == target.axial:
			at_cell += 1
	assert_eq(at_cell, 1, "no duplicate hex should be placed on the cell")
	assert_eq(_editor._current_level().hexes.size(), hexes_before,
			"a same-type re-drop adds no net hexes")
	_editor._exit_stamp_mode()


# Copy `src` to the stamp and commit it onto `target_axial` (no
# rotation), then drop out of the re-armed stamp mode. Returns nothing;
# the caller inspects the editor's level / undo stack.
func _copy_stamp_commit(src: HexNode, target_axial: Vector2i, rot: int = 0) -> void:
	_editor._replace_selection([src] as Array[HexNode])
	_editor._ctrl_c_copy_selection_to_stamp()
	var prev: Dictionary = _editor._stamp_previews[0]
	_editor._stamp_rotation = rot
	_editor._stamp_anchor_axial = target_axial - HexMath.rotate_axial(prev.rel_axial, rot)
	_editor._commit_stamp()
	_editor._exit_stamp_mode()


# A stamp commit is now a single undoable bulk action — it must NOT wipe
# earlier undo history, and undoing it removes exactly the placed hexes.
func test_stamp_commit_is_undoable_and_keeps_history() -> void:
	var src := _place(IntLiteralHex, Vector2i(8, 0))
	var before: int = _editor._current_level().hexes.size()
	_copy_stamp_commit(src, Vector2i(-3, 0))
	assert_eq(_editor._undo_stack.size(), 1, "first stamp pushes one undo entry")
	assert_eq(_editor._undo_stack[-1].type, "place_stamp")
	assert_eq(_editor._current_level().hexes.size(), before + 1,
			"the stamp placed one new hex")
	# A second stamp must preserve the first entry (no undo-stack wipe).
	_copy_stamp_commit(src, Vector2i(-5, 0))
	assert_eq(_editor._undo_stack.size(), 2,
			"stamping must not clear earlier undo history")
	assert_eq(_editor._current_level().hexes.size(), before + 2)
	# Undo the second stamp.
	_editor._undo()
	assert_eq(_editor._current_level().hexes.size(), before + 1,
			"undo removes only the last stamp's hex")
	assert_eq(_editor._undo_stack.size(), 1)
	# Redo restores it.
	_editor._redo()
	assert_eq(_editor._current_level().hexes.size(), before + 2,
			"redo re-places the stamp's hex")


# The same-type re-orient applied by a stamp is reversible.
func test_same_type_overlap_reorient_is_undoable() -> void:
	var target := _place(IntLiteralHex, Vector2i(5, 0))
	target.set_rotation_index(0)
	var source := _place(IntLiteralHex, Vector2i(9, 0))
	_copy_stamp_commit(source, target.axial, 3)
	assert_eq(target.rotation_index, 3, "stamp re-oriented the existing hex")
	assert_eq(_editor._undo_stack[-1].type, "place_stamp")
	_editor._undo()
	assert_eq(target.rotation_index, 0,
			"undo restores the pre-stamp facing of the re-oriented hex")
	_editor._redo()
	assert_eq(target.rotation_index, 3, "redo re-applies the re-orient")


# Wiring a new source into an already-fed input parks (not disposes) the
# displaced wire so undo can bring the original connection back.
func test_wire_overwrite_is_undoable() -> void:
	var level = _editor._current_level()
	var sink := _place(IntLiteralHex, Vector2i(2, 0))
	var src1 := _place(IntLiteralHex, Vector2i(4, 0))
	var src2 := _place(IntLiteralHex, Vector2i(6, 0))
	# Pre-existing wire src1 → sink (input edge 0).
	var w1 := HexWire.new()
	w1.output_node = src1
	w1.output_edge = 0
	w1.input_node = sink
	w1.input_edge = 0
	w1.is_finalized = true
	w1.anchor_node = src1
	w1.anchor_edge = 0
	w1.anchor_is_output = true
	w1.line = HexWire.build_line(false)
	level.add_wire_line(w1.line)
	level.wires.append(w1)
	# Draw a second wire into the same input slot and commit it.
	var w2 := HexWire.new()
	w2.output_node = src2
	w2.output_edge = 0
	w2.input_node = sink
	w2.input_edge = 0
	w2.anchor_node = src2
	w2.anchor_edge = 0
	w2.anchor_is_output = true
	w2.line = HexWire.build_line(false)
	level.add_wire_line(w2.line)
	_editor._active_wire = w2
	_editor._commit_active_wire()
	# The new wire took the slot; the old one was parked, not destroyed.
	assert_true(w2 in level.wires, "the new wire holds the input")
	assert_false(w1 in level.wires, "the displaced wire left the active list")
	assert_true(is_instance_valid(w1.line), "the displaced wire's visual survives (parked)")
	assert_eq(_editor._undo_stack[-1].type, "place_wire")
	assert_true(w1 in _editor._undo_stack[-1].overwritten,
			"the displaced wire is recorded for undo")
	# Undo restores the original connection.
	_editor._undo()
	assert_true(w1 in level.wires, "undo brings the original wire back")
	assert_false(w2 in level.wires, "undo removes the replacement wire")
	# Redo re-applies the overwrite.
	_editor._redo()
	assert_true(w2 in level.wires, "redo restores the replacement wire")
	assert_false(w1 in level.wires, "redo re-parks the displaced wire")


# Step 6: the config panel's ascend / descend buttons navigate levels.
func test_config_nav_buttons_drive_level_navigation() -> void:
	var let_hex := _place(LetHex, Vector2i(3, 0))
	_editor._open_config_sidebar(let_hex)
	var sidebar = _editor.config_sidebar
	assert_false(sidebar._descend_btn.disabled,
			"descend enabled for a hex with an inner level")
	assert_true(sidebar._ascend_btn.disabled, "ascend disabled at the root level")
	assert_eq(_editor._level_stack.size(), 1)
	# Descend via the panel button.
	sidebar.descend_requested.emit()
	assert_eq(_editor._level_stack.size(), 2, "descend should push the inner level")
	# Open config on the inner anchor; ascend is now enabled.
	_editor._open_config_sidebar(let_hex.inner_level.anchor)
	assert_false(sidebar._ascend_btn.disabled, "ascend enabled below the root")
	# Ascend via the panel button.
	sidebar.ascend_requested.emit()
	assert_eq(_editor._level_stack.size(), 1, "ascend should pop back to root")


# Step 7: a non-animated level view still snaps the camera instantly
# (keeps tab-switching / per-level state deterministic).
func test_apply_level_view_snaps_without_animation() -> void:
	var level = _editor._current_level()
	level.world_position = Vector2(123, -45)
	level.world_scale = 1.0
	_editor._apply_level_view(level)
	assert_eq(_editor.hex_camera.position, Vector2(123, -45),
			"non-animated apply should snap the camera immediately")


# Step 7: descending fades the incoming level in and lerps the camera to
# its view (settling opaque + on-target once the tweens finish).
func test_descend_fades_in_and_settles() -> void:
	var let_hex := _place(LetHex, Vector2i(3, 0))
	_editor._descend_into(let_hex)
	assert_eq(_editor._level_stack.size(), 2, "descend pushes the inner level")
	var inner = _editor._current_level()
	assert_lt(inner.modulate.a, 1.0,
			"incoming level starts faded for the transition")
	await wait_seconds(0.35)
	assert_almost_eq(inner.modulate.a, 1.0, 0.01, "level finishes opaque")
	assert_almost_eq(_editor.hex_camera.position.x, inner.world_position.x, 1.0,
			"camera lerps to the inner level's view")

