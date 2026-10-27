extends Control
## Blueprint library — Control-based modal mirroring the pause menu
## shell. Two-column body: blueprint cards + capture/import actions
## on the left, live preview pane on the right.
##
## Owns library-internal flows (rename, delete, export, preview).
## Signals up to the editor for actions that need editor state
## (`capture_requested`, `stamp_requested`, `import_requested`).
## The editor calls `refresh()` after each external mutation.

signal capture_requested
signal import_requested
signal stamp_requested(payload: Dictionary)
signal closed

const BLUEPRINT_MINI_CANVAS_SCENE := preload(
		"res://scenes/gui/blueprint_library/mini_canvas/blueprint_mini_canvas.tscn")
const BLUEPRINT_ROW_SCENE := preload(
		"res://scenes/gui/blueprint_library/blueprint_row.tscn")

@onready var _capture_button: Button = %CaptureButton
@onready var _import_button: Button = %ImportButton
@onready var _list_box: VBoxContainer = %ListBox
@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _close_button: Button = %CloseButton

# Per-blueprint row instances, parallel to `SaveManager.get_blueprints()`.
# Used by `_on_card_selected` to flip the highlight on the prior
# selection when a new card is clicked.
var _cards: Array = []
var _selected_index: int = -1
var _preview_canvas: Node = null


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	_capture_button.pressed.connect(func() -> void: capture_requested.emit())
	_import_button.pressed.connect(func() -> void: import_requested.emit())


func open() -> void:
	# Runtime-added Controls don't pick up the .tscn's anchor preset
	# from the parent's rect — force the full-rect layout so the
	# backdrop fills the viewport and the CenterContainer can center
	# the panel inside it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	_clear_preview()
	closed.emit()


# `sys_open_library` (B) toggles: the tree is paused while this modal
# is open, so the editor-side CanvasInputController can't see the
# hotkey — the dialog itself handles the press-again-to-close.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("sys_open_library"):
		close()
		get_viewport().set_input_as_handled()


# Test-facing accessor — the smoke test pokes at the preview panel
# to confirm the SubViewportContainer is hosted there after a card
# is selected.
func get_preview_panel() -> PanelContainer:
	return _preview_panel


# Rebuild the card list from SaveManager. Called on open + after any
# mutation (rename / delete / capture / import).
func refresh() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		c.queue_free()
	_cards.clear()
	_selected_index = -1
	_clear_preview()
	var bps: Array = SaveManager.get_blueprints()
	if bps.is_empty():
		var empty := Label.new()
		empty.text = "(no blueprints — capture a tab to save one)"
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
		_list_box.add_child(empty)
		return
	for i in bps.size():
		var card := BLUEPRINT_ROW_SCENE.instantiate()
		_list_box.add_child(card)
		card.populate(i, bps[i])
		card.selected.connect(_on_card_selected)
		card.stamp_pressed.connect(
				func(payload: Dictionary) -> void: stamp_requested.emit(payload))
		card.rename_pressed.connect(_prompt_rename)
		card.export_pressed.connect(_export)
		card.delete_pressed.connect(_confirm_delete)
		_cards.append(card)


# Single-selection bookkeeping moved here from the legacy ButtonGroup.
# Clicking a different card flips the prior selection off + highlights
# the new one. Clicking the active card drops back to the placeholder
# (same clean-mouse gesture as the palette bar).
func _on_card_selected(index: int) -> void:
	if _selected_index == index:
		_cards[_selected_index].set_selected(false)
		_selected_index = -1
		_show_preview_placeholder("(select a blueprint)")
		return
	if _selected_index >= 0 and _selected_index < _cards.size():
		_cards[_selected_index].set_selected(false)
	_selected_index = index
	_cards[_selected_index].set_selected(true)
	_load_preview(index)


func _load_preview(index: int) -> void:
	if _preview_panel == null:
		return
	for child in _preview_panel.get_children():
		child.queue_free()
	_preview_canvas = null
	var bps: Array = SaveManager.get_blueprints()
	if index < 0 or index >= bps.size():
		_show_preview_placeholder("(select a blueprint)")
		return
	var entry: Dictionary = bps[index]
	var payload = entry.get("payload", null)
	if not (payload is Dictionary) or payload.is_empty():
		# Pre-Phase-19 entries carry only `program_text` — there's no
		# graph to render. Surface the reason so the player isn't left
		# wondering why the pane is blank.
		_show_preview_placeholder(
				"(legacy entry — no graph payload to render)")
		return
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The preview auto-frames to fit (no pan/zoom gestures) — let
	# clicks fall through to the dialog.
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 280)
	viewport.transparent_bg = true
	container.add_child(viewport)
	_preview_canvas = BLUEPRINT_MINI_CANVAS_SCENE.instantiate()
	viewport.add_child(_preview_canvas)
	_preview_canvas.load_blueprint_dict(payload)
	_preview_panel.add_child(container)


func _show_preview_placeholder(message: String) -> void:
	if _preview_panel == null:
		return
	for child in _preview_panel.get_children():
		child.queue_free()
	_preview_canvas = null
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_panel.add_child(label)


func _clear_preview() -> void:
	# Drop the SubViewport so it stops ticking, leave the placeholder
	# behind for the next open.
	_show_preview_placeholder("(select a blueprint)")
	_selected_index = -1



# Small inline AcceptDialog for rename — kept procedural since the
# user's "Control instead of Window" rule was specifically about
# top-level dialogs. A quick one-shot text field is fine here.
func _prompt_rename(index: int) -> void:
	var bps: Array = SaveManager.get_blueprints()
	if index < 0 or index >= bps.size():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Rename blueprint"
	var line := LineEdit.new()
	line.text = String(bps[index].get("name", ""))
	line.custom_minimum_size = Vector2(320, 0)
	dialog.add_child(line)
	add_child(dialog)
	dialog.popup_centered()
	line.grab_focus()
	line.select_all()
	dialog.confirmed.connect(func() -> void:
		SaveManager.rename_blueprint(index, line.text)
		refresh()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


func _confirm_delete(index: int) -> void:
	var bps: Array = SaveManager.get_blueprints()
	if index < 0 or index >= bps.size():
		return
	var name := String(bps[index].get("name", ""))
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete blueprint"
	dialog.dialog_text = "Delete '%s'? This can't be undone." % name
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		SaveManager.remove_blueprint(index)
		refresh()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


func _export(index: int) -> void:
	var bps: Array = SaveManager.get_blueprints()
	if index < 0 or index >= bps.size():
		return
	var payload: Dictionary = bps[index].get("payload", {})
	if payload.is_empty():
		return
	var s: String = BlueprintCodec.encode(payload)
	DisplayServer.clipboard_set(s)
	# Surface the string in a one-shot AcceptDialog so the player can
	# copy it manually if clipboard access is sandboxed.
	var dialog := AcceptDialog.new()
	dialog.title = "Blueprint exported"
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Copied to clipboard. Manual copy below:"
	box.add_child(lbl)
	var te := TextEdit.new()
	te.text = s
	te.editable = false
	te.custom_minimum_size = Vector2(520, 200)
	box.add_child(te)
	dialog.add_child(box)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
