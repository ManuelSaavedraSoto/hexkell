extends Control
## Codex / concepts dialog — Control-based modal mirroring the pause
## menu shell (backdrop + centered PanelContainer). Two-column body:
## concept list on the left, concept details on the right.
##
## Scaffold only this round. The `set_concepts()` / `show_concept()`
## API lets a future codex source-of-truth hook in without scene
## churn; for now both columns ship empty.

signal closed

const BLUEPRINT_MINI_CANVAS := preload(
	"res://scenes/gui/blueprint_library/mini_canvas/blueprint_mini_canvas.tscn")

@onready var concept_list: ItemList = %ConceptList
@onready var content_label: RichTextLabel = %ContentLabel
@onready var right_header: Label = %RightHeader
@onready var _close_button: Button = %CloseButton

# concept_id → {title, body, blueprint} for `show_concept` lookups.
# Populated by `set_concepts()` from whoever owns the canonical concept
# catalog (the editor's `_build_codex_concepts`).
var _concepts: Dictionary = {}
var _concept_ids: Array = []

# Lazily built SubViewport preview that renders a chapter's example
# blueprint live above the detail text. Reused across selections.
var _preview_container: SubViewportContainer = null
var _preview_viewport: SubViewport = null


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	concept_list.item_selected.connect(_on_concept_selected)


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	# Esc closes the dialog — consume the event so the editor's own
	# `_unhandled_input` Esc handler doesn't fire underneath.
	# `sys_open_codex` (G) toggles: the paused tree freezes the
	# CanvasInputController, so the dialog handles its own hotkey.
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("sys_open_codex"):
		close()
		get_viewport().set_input_as_handled()


# concepts: Array of {"id": String, "title": String, "body": String}.
# Replaces the left-column list and indexes content for `show_concept`.
# Auto-selects the first concept so the detail pane is never blank;
# falls back to an empty-state message when there's nothing to show.
func set_concepts(concepts: Array) -> void:
	_concepts.clear()
	_concept_ids.clear()
	concept_list.clear()
	for entry in concepts:
		if not (entry is Dictionary):
			continue
		var id := String(entry.get("id", ""))
		if id.is_empty():
			continue
		_concept_ids.append(id)
		_concepts[id] = {
			"title": String(entry.get("title", id)),
			"body": String(entry.get("body", "")),
			"blueprint": String(entry.get("blueprint", "")),
		}
		concept_list.add_item(_concepts[id].title)
	if _concept_ids.is_empty():
		right_header.text = "Codex"
		content_label.text = "No concepts yet — chapters appear here once you've met them."
		return
	concept_list.select(0)
	show_concept(_concept_ids[0])


func show_concept(id: String) -> void:
	if not _concepts.has(id):
		return
	var entry: Dictionary = _concepts[id]
	right_header.text = entry.title
	content_label.text = entry.body
	_set_preview(String(entry.get("blueprint", "")))


func _on_concept_selected(idx: int) -> void:
	if idx < 0 or idx >= _concept_ids.size():
		return
	show_concept(_concept_ids[idx])


# Render `encoded` (an `hxk1:...` blueprint string) in the detail pane's
# mini-canvas, lazily creating the SubViewport on first use and reusing
# it thereafter. Hides the preview when the chapter has no blueprint or
# the string fails to decode, so the detail text stands alone.
func _set_preview(encoded: String) -> void:
	if encoded.is_empty():
		if _preview_container != null:
			_preview_container.visible = false
		return
	_ensure_preview_container()
	# Swap in a fresh canvas — the mini-canvas decodes once at load.
	for child in _preview_viewport.get_children():
		child.queue_free()
	var canvas := BLUEPRINT_MINI_CANVAS.instantiate()
	_preview_viewport.add_child(canvas)
	_preview_container.visible = canvas.load_blueprint_string(encoded)


func _ensure_preview_container() -> void:
	if _preview_container != null:
		return
	_preview_container = SubViewportContainer.new()
	_preview_container.stretch = true
	_preview_container.custom_minimum_size = Vector2(420, 220)
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(420, 220)
	_preview_viewport.transparent_bg = true
	_preview_container.add_child(_preview_viewport)
	# Sit the preview directly under the header, above the body text.
	var column := right_header.get_parent()
	column.add_child(_preview_container)
	column.move_child(_preview_container, right_header.get_index() + 1)
