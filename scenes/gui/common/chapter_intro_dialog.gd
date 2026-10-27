extends Control
## Modal shown at the start of a chapter: description on the left, a
## carousel of in-game screenshots on the right. Each slide showcases
## one concept as it appears in the hex editor.
##
## Control-based modal (not a Window subclass) — same shell as the
## pause menu so theme + sizing stay consistent across dialogs. The
## backdrop swallows clicks outside the panel; Esc closes via
## `_input` (consumed before reaching the editor's own Esc handler).

signal chapter_closed(chapter_id: String)

@onready var title_label: Label = %TitleLabel
@onready var description_label: RichTextLabel = %DescriptionLabel
@onready var screenshot_view: Control = %ScreenshotView
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var indicator_label: Label = %IndicatorLabel
@onready var _close_button: TextureButton = %CloseButton

var _current_chapter_id: String = ""
var _carousel_examples: Array = []
var _carousel_index: int = 0
var _carousel_current_content: Control = null


func _ready() -> void:
	visible = false
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	_close_button.pressed.connect(close)


func show_chapter(chapter_id: String, chapter_data: Dictionary) -> void:
	_current_chapter_id = chapter_id
	title_label.text = chapter_data.get("name", chapter_id)
	description_label.text = chapter_data.get("description", "")

	_carousel_examples = _collect_examples(chapter_data)
	_carousel_index = 0
	_rebuild_carousel()

	open()


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	_emit_close()


# Esc / `ui_cancel` closes the dialog. Consume the event before it
# reaches `_unhandled_input` so the editor's own Esc handler (which
# exits blueprint mode / closes the config sidebar / etc.) doesn't
# fire underneath the modal.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# A "screenshot example" is a `{name, screenshot, caption}` dict.
# `screenshot` is a `res://…` path to a PNG / JPG; `caption` is an
# optional one-line explainer rendered below the image. Legacy
# chapters that still carry `code` snippets fall back to a "(text
# example — see legacy text editor)" placeholder so older save data
# doesn't break the dialog.
func _collect_examples(chapter_data: Dictionary) -> Array:
	var examples_raw = chapter_data.get("examples", null)
	if not (examples_raw is Array):
		return []
	var out: Array = []
	for entry in examples_raw:
		if not (entry is Dictionary):
			continue
		var name: String = String(entry.get("name", "Example"))
		if entry.has("blueprint") or entry.has("screenshot"):
			out.append({
				"name": name,
				"blueprint": String(entry.get("blueprint", "")),
				"screenshot": String(entry.get("screenshot", "")),
				"caption": String(entry.get("caption", "")),
			})
		elif entry.has("code"):
			# Legacy code-example fallback (pre-v3 chapter data).
			out.append({
				"name": name,
				"screenshot": "",
				"caption": "(text snippet — open the legacy text editor to run it)",
			})
	return out


func _rebuild_carousel() -> void:
	# Clear previous content
	for child in screenshot_view.get_children():
		child.queue_free()
	_carousel_current_content = null

	if _carousel_examples.is_empty():
		var empty := Label.new()
		empty.text = "(no screenshots for this chapter yet)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		screenshot_view.add_child(empty)
		_carousel_current_content = empty
		prev_button.disabled = true
		next_button.disabled = true
		indicator_label.text = "0 / 0"
		return

	# Display current slide
	var entry: Dictionary = _carousel_examples[_carousel_index]
	var view := _build_screenshot_view(entry)
	screenshot_view.add_child(view)
	_carousel_current_content = view

	# Update navigation buttons
	prev_button.disabled = (_carousel_index == 0)
	next_button.disabled = (_carousel_index >= _carousel_examples.size() - 1)
	indicator_label.text = "%d / %d" % [_carousel_index + 1, _carousel_examples.size()]


# Build one slide's content: a TextureRect that fits-and-keeps-aspect
# the loaded screenshot, plus an optional caption Label below. When
# the screenshot file isn't on disk yet (the v3 chapter rewrite
# ships before the screenshot capture pass), render a "screenshot
# pending" placeholder so the dialog stays legible.
func _build_screenshot_view(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)

	var blueprint_string: String = String(entry.get("blueprint", ""))
	var screenshot_path: String = String(entry.get("screenshot", ""))
	var caption: String = String(entry.get("caption", ""))

	# Blueprint-based example: decode the hxk1:... string into a
	# read-only mini-canvas inside a SubViewport so wire-flow shaders
	# pulse live + the example scales with the dialog. Falls through
	# to the screenshot path when decoding fails.
	if not blueprint_string.is_empty():
		var preview := _build_blueprint_preview(blueprint_string)
		if preview != null:
			box.add_child(preview)
			if not caption.is_empty():
				box.add_child(_build_caption_label(caption))
			return box

	var texture: Texture2D = null
	if not screenshot_path.is_empty() and ResourceLoader.exists(screenshot_path):
		var loaded := load(screenshot_path)
		if loaded is Texture2D:
			texture = loaded

	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(rect)
	else:
		var placeholder := Label.new()
		placeholder.text = "(screenshot pending — place a hex graph and capture)"
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(placeholder)

	if not caption.is_empty():
		box.add_child(_build_caption_label(caption))
	return box


const BLUEPRINT_MINI_CANVAS := preload(
	"res://scenes/gui/blueprint_library/mini_canvas/blueprint_mini_canvas.tscn")


# SubViewport-rendered preview of a chapter example blueprint. Decodes
# the `hxk1:...` string into a read-only BlueprintMiniCanvas so the
# author's exported blueprint renders live, using the same wire-flow
# shaders + body visuals as the main editor. Returns null when decoding
# fails so the caller can fall through to the screenshot path.
func _build_blueprint_preview(encoded: String) -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(320, 240)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The preview auto-frames to fit (no pan/zoom gestures) — let
	# clicks fall through to the dialog.
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.transparent_bg = true
	container.add_child(viewport)

	var canvas := BLUEPRINT_MINI_CANVAS.instantiate()
	viewport.add_child(canvas)
	if not canvas.load_blueprint_string(encoded):
		container.queue_free()
		return null
	return container


func _build_caption_label(caption: String) -> RichTextLabel:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.text = caption
	lbl.add_theme_color_override("default_color", Color(0.88, 0.93, 1.0))
	lbl.add_theme_font_size_override("normal_font_size", 16)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _on_prev_pressed() -> void:
	if _carousel_index > 0:
		_carousel_index -= 1
		_rebuild_carousel()


func _on_next_pressed() -> void:
	if _carousel_index < _carousel_examples.size() - 1:
		_carousel_index += 1
		_rebuild_carousel()


func _emit_close() -> void:
	if _current_chapter_id == "":
		return
	var closed_id = _current_chapter_id
	_current_chapter_id = ""
	chapter_closed.emit(closed_id)
