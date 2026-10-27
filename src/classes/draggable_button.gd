extends Button
## Draggable template button for code editor

## The template text to insert
@export_multiline var template_text: String = ""

## Display name for the template
@export var template_name: String = "Template"

## Optional tooltip describing what the template does
@export_multiline var template_description: String = ""

var is_dragging: bool = false
var drag_preview: Control = null


func _ready() -> void:
	text = template_name
	focus_mode = FOCUS_NONE  # Don't steal focus from the code editor on click
	if not template_description.is_empty():
		tooltip_text = template_description

	# Connect signals
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_pressed() -> void:
	# When clicked, insert template at cursor in the focused code editor
	var code_editor = _find_code_editor()
	if code_editor and code_editor.has_method("insert_template_at_cursor"):
		code_editor.insert_template_at_cursor(template_text)
		code_editor.grab_focus()


func _on_mouse_entered() -> void:
	# Show preview tooltip on hover
	if not template_text.is_empty():
		var preview = template_text
		if preview.length() > 200:
			preview = preview.substr(0, 200) + "..."
		tooltip_text = template_description + "\n\n" + preview if template_description else preview


func _on_mouse_exited() -> void:
	if template_description:
		tooltip_text = template_description


## Enable dragging
func _get_drag_data(_at_position: Vector2) -> Variant:
	# Create drag preview
	var preview = Label.new()
	preview.text = template_name
	preview.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	
	var panel = PanelContainer.new()
	panel.add_child(preview)
	panel.modulate.a = 0.8
	
	set_drag_preview(panel)
	
	# Return template data
	return {
		"template_text": template_text,
		"template_name": template_name,
		"source": self
	}


## Find the code editor in the scene tree
func _find_code_editor() -> CodeEdit:
	# Try to find a focused CodeEdit first
	var focused = get_viewport().gui_get_focus_owner()
	if focused is CodeEdit:
		return focused
	
	# Otherwise, find any CodeEdit in the scene
	return _find_code_edit_recursive(get_tree().root)


func _find_code_edit_recursive(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node
	
	for child in node.get_children():
		var result = _find_code_edit_recursive(child)
		if result:
			return result
	
	return null
