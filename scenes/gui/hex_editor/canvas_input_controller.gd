extends Node
## Keyboard input for canvas-context actions, routed through input
## actions (project.godot [input]). These are the keys that act on
## the editor's mode state or the hex under the mouse — rotate,
## delete, clone, descend/ascend, undo/redo, clipboard, the Escape
## cancel cascade, and the dialog-opening hotkeys — so they can't
## live on a leaf component, but they don't belong in the editor's
## mouse handler either.
##
## Mouse input stays in hex_editor.gd (_unhandled_input): RMB/LMB
## behavior depends on stamp/blueprint/wire/selection/sidebar context
## that only the editor sees as a whole.
##
## Modal gating is free: this PAUSABLE node receives no input while a
## dialog is open (ModalStack pauses the tree).

@onready var _editor: Node = get_parent()


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard only — some actions (hex_delete) also carry mouse-button
	# events that the editor's central mouse cascade owns.
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var text_focused := InputGates.text_input_focused(get_viewport())

	# ── Quick REPL / rotate (Ctrl+R vs R / Shift+R) ─────────────────
	if event.is_action_pressed("sys_open_repl", false, true):
		if not text_focused:
			_editor._open_quick_repl()
	elif event.is_action_pressed("hex_rotate_cw", false, true) \
			or event.is_action_pressed("hex_rotate_ccw", false, true):
		var ccw := event.is_action_pressed("hex_rotate_ccw", false, true)
		# Rotation only acts on the placement preview (stamp/blueprint).
		# Placed hexes are no longer rotated on hover — pick one up
		# (double-click) to rotate it as a move instead.
		if not _editor._stamp_previews.is_empty():
			_editor._rotate_stamp(-1 if ccw else 1)
			SfxManager.play("rotate")
		elif _editor._blueprint_node:
			_editor._rotate_blueprint(ccw)
			SfxManager.play("rotate")

	# ── Delete / cut (X vs Ctrl+X) ──────────────────────────────────
	elif event.is_action_pressed("sys_cut", false, true):
		if _editor._blueprint_node == null and _editor._active_wire == null \
				and not text_focused:
			_editor._ctrl_x_cut_selection_to_stamp()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hex_delete", false, true):
		if _editor._blueprint_node == null and _editor._active_wire == null \
				and not text_focused:
			if not _editor._selected_hexes.is_empty():
				_editor._delete_selection()
			else:
				_editor._try_delete_under_mouse()

	# ── Level navigation ────────────────────────────────────────────
	elif event.is_action_pressed("hex_descend", false, true):
		if _editor._blueprint_node == null and _editor._active_wire == null:
			_editor._try_descend()
	elif event.is_action_pressed("hex_ascend", false, true):
		if _editor._blueprint_node == null and _editor._active_wire == null:
			_editor._try_ascend()

	# ── Camera home ─────────────────────────────────────────────────
	elif event.is_action_pressed("canvas_home_root", false, true):
		if not text_focused:
			_editor._home_to_do()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("canvas_home", false, true):
		if not text_focused:
			_editor._home_camera()
			get_viewport().set_input_as_handled()

	# ── Undo / redo ─────────────────────────────────────────────────
	elif event.is_action_pressed("sys_undo", false, true):
		if not text_focused:
			_editor._undo()
	elif event.is_action_pressed("sys_redo", false, true):
		if not text_focused:
			_editor._redo()
	elif event.is_action_pressed("hex_clear_canvas", false, true):
		if not text_focused and _editor._blueprint_node == null \
				and _editor._active_wire == null and _editor._stamp_previews.is_empty():
			_editor._clear_active_tab()
			get_viewport().set_input_as_handled()

	# ── Clipboard / save ────────────────────────────────────────────
	elif event.is_action_pressed("sys_save", false, true):
		if not text_focused:
			_editor._ctrl_s_save()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sys_copy", false, true):
		if not text_focused:
			_editor._ctrl_c_copy_selection_to_stamp()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hex_pipette", false, true):
		# Plain C: anchor an in-flight wire, else clone under cursor.
		if _editor._active_wire:
			_editor._anchor_active_wire()
		elif _editor._blueprint_node == null:
			_editor._try_clone_under_mouse()
	elif event.is_action_pressed("sys_paste", false, true):
		if not text_focused:
			_editor._ctrl_v_paste_to_stamp()
			get_viewport().set_input_as_handled()

	# ── Dialogs ─────────────────────────────────────────────────────
	elif event.is_action_pressed("sys_help", false, true):
		if not text_focused:
			_editor._show_help_overlay()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sys_open_library", false, true):
		if not text_focused:
			_editor._open_library()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sys_open_codex", false, true):
		if not text_focused:
			_editor._on_codex_requested()
			get_viewport().set_input_as_handled()

	# ── Escape: contextual cancel cascade ───────────────────────────
	# (Open modals never reach here — the tree is paused and this node
	# is frozen, so the REPL/library special cases are gone.)
	elif event.is_action_pressed("cancel", false, true):
		if _editor._marquee_active:
			_editor._cancel_marquee()
		elif not _editor._selected_hexes.is_empty():
			_editor._clear_selection()
		elif not _editor._stamp_previews.is_empty():
			_editor._exit_stamp_mode()
		elif _editor._blueprint_node:
			_editor._exit_blueprint_mode()
		elif _editor._active_wire:
			_editor._cancel_active_wire()
		elif _editor._config_target != null:
			_editor._close_config_sidebar()
		else:
			_editor._pause_menu.pause()
