extends AcceptDialog
## Dialog for entering a template name

signal template_name_entered(template_name: String)

@onready var name_input: LineEdit = %NameInput
@onready var error_label: Label = %ErrorLabel


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	close_requested.connect(_on_canceled)
	
	# Focus input when dialog opens
	about_to_popup.connect(func(): 
		name_input.clear()
		error_label.hide()
		name_input.grab_focus()
	)


func _on_confirmed() -> void:
	var template_name = name_input.text.strip_edges()
	
	if template_name.is_empty():
		error_label.text = "Template name cannot be empty"
		error_label.show()
		return
	
	if not _is_valid_template_name(template_name):
		error_label.text = "Invalid name. Use letters, numbers, spaces, - and _"
		error_label.show()
		return
	
	template_name_entered.emit(template_name)
	hide()


func _on_canceled() -> void:
	hide()


func show_error(message: String) -> void:
	error_label.text = message
	error_label.show()
	name_input.grab_focus()


func _is_valid_template_name(template_name: String) -> bool:
	# Allow alphanumeric, spaces, hyphens, and underscores
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9\\s_-]+$")
	return regex.search(template_name) != null
