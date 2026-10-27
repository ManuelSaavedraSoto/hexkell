extends PanelContainer
## Non-focus-stealing toast that nudges the player about useful unlocked templates.
##
## Pinned to the editor's top-right corner. Mouse input on the toast itself is
## handled (so the close × and Insert buttons work), but the toast never grabs
## keyboard focus, so the player's editing flow is not interrupted.

signal template_insert_requested(template_text: String)

@onready var title_label: Label = %TitleLabel
@onready var message_label: RichTextLabel = %MessageLabel
@onready var template_list: VBoxContainer = %TemplateList
@onready var close_button: Button = %CloseButton
@onready var auto_hide_timer: Timer = $AutoHideTimer

const AUTO_HIDE_SECONDS := 12.0


func _ready() -> void:
	close_button.pressed.connect(hide_toast)
	auto_hide_timer.timeout.connect(hide_toast)
	# Toast is decorative; don't take keyboard focus away from the editor.
	focus_mode = Control.FOCUS_NONE


## entries is an Array of {"name": String, "text": String}
func show_hint(exercise_name: String, entries: Array) -> void:
	title_label.text = "💡 Tip — %s" % exercise_name
	message_label.text = "You've already unlocked these templates that may help:"

	for child in template_list.get_children():
		child.queue_free()

	for entry in entries:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = "• %s" % entry.get("name", "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78))
		row.add_child(name_label)

		var insert_button = Button.new()
		insert_button.text = "Insert"
		insert_button.tooltip_text = "Insert this template at the cursor"
		insert_button.focus_mode = Control.FOCUS_NONE
		var template_text: String = entry.get("text", "")
		insert_button.pressed.connect(func():
			template_insert_requested.emit(template_text)
			# Bump the auto-hide timer so the toast lingers a bit if the user is using it.
			auto_hide_timer.start(AUTO_HIDE_SECONDS)
		)
		row.add_child(insert_button)

		template_list.add_child(row)

	visible = true
	auto_hide_timer.start(AUTO_HIDE_SECONDS)


func hide_toast() -> void:
	visible = false
	auto_hide_timer.stop()
