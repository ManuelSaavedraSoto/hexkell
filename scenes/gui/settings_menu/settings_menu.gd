extends Control
## Settings menu — reachable from the main menu (full-screen, opaque
## background) and from the in-editor pause menu (modal, blurred
## background). `set_modal(blur: bool)` flips the background; the
## back button emits `close_requested` for the caller to handle
## (return to main menu vs. queue_free the modal). The Archmage
## CheckButton emits `archmage_changed` so a live editor can refresh
## its palette / jobs lock state without closing the modal.

signal close_requested
signal archmage_changed(enabled: bool)

@onready var back_button: Button = %BackButton
@onready var custom_templates_toggle: CheckButton = %CustomTemplatesToggle
@onready var custom_templates_path_button: Button = %CustomTemplatesPathButton
@onready var unload_custom_templates_button: Button = %UnloadTemplatesButton
@onready var custom_exercises_toggle: CheckButton = %CustomExercisesToggle
@onready var custom_exercises_path_button: Button = %CustomExercisesPathButton
@onready var unload_custom_exercises_button: Button = %UnloadExercisesButton
@onready var delete_save_button: Button = %DeleteSaveButton
@onready var delete_blueprints_button: Button = %DeleteBlueprintsButton
@onready var replay_tutorial_button: Button = %ReplayTutorialButton
@onready var archmage_toggle: CheckButton = %ArchmageToggle
@onready var _color_rect: ColorRect = %ColorRect
@onready var _blur_rect: ColorRect = %BlurRect

var file_dialog: FileDialog
var _modal: bool = false


func _ready() -> void:
	_setup_file_dialog()
	_load_settings()
	_connect_signals()


# Flip the scene's backdrop. When `blur` is true, the opaque
# ColorRect hides and the blur-shader ColorRect shows — used when
# the scene is instantiated as a modal over the running editor.
# The default (false) preserves the main-menu full-screen look.
func set_modal(blur: bool) -> void:
	_modal = blur
	if _color_rect:
		_color_rect.visible = not blur
	if _blur_rect:
		_blur_rect.visible = blur
	if blur:
		# Modal sits over a paused editor tree.
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _setup_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.json", "JSON Files")
	add_child(file_dialog)


func _load_settings() -> void:
	custom_templates_toggle.button_pressed = TemplateManager.use_custom_templates
	custom_exercises_toggle.button_pressed = TemplateManager.use_custom_exercises
	archmage_toggle.button_pressed = SaveManager.is_archmage()
	_update_templates_file_buttons()
	_update_exercises_file_buttons()


func _connect_signals() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	custom_templates_toggle.toggled.connect(_on_custom_templates_toggled)
	custom_templates_path_button.pressed.connect(_on_select_templates_file)
	unload_custom_templates_button.pressed.connect(_on_unload_templates_pressed)

	custom_exercises_toggle.toggled.connect(_on_custom_exercises_toggled)
	custom_exercises_path_button.pressed.connect(_on_select_exercises_file)
	unload_custom_exercises_button.pressed.connect(_on_unload_exercises_pressed)

	delete_save_button.pressed.connect(_on_delete_save_pressed)
	delete_blueprints_button.pressed.connect(_on_delete_blueprints_pressed)
	replay_tutorial_button.pressed.connect(_on_replay_tutorial_pressed)
	archmage_toggle.toggled.connect(_on_archmage_toggled)


func _on_archmage_toggled(enabled: bool) -> void:
	SaveManager.set_archmage(enabled)
	archmage_changed.emit(enabled)


func _on_custom_templates_toggled(enabled: bool) -> void:
	TemplateManager.set_custom_templates_enabled(enabled)


func _on_custom_exercises_toggled(enabled: bool) -> void:
	TemplateManager.set_custom_exercises_enabled(enabled)


func _on_select_templates_file() -> void:
	file_dialog.file_selected.connect(_on_templates_file_selected, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2i(800, 600))


func _on_templates_file_selected(path: String) -> void:
	if TemplateManager.import_custom_template_file(path):
		_update_templates_file_buttons()
		print("Custom templates imported from: %s" % path)
	else:
		push_error("Failed to import custom templates")


func _on_select_exercises_file() -> void:
	file_dialog.file_selected.connect(_on_exercises_file_selected, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2i(800, 600))


func _on_exercises_file_selected(path: String) -> void:
	if TemplateManager.import_custom_exercise_file(path):
		_update_exercises_file_buttons()
		print("Custom exercises imported from: %s" % path)
	else:
		push_error("Failed to import custom exercises")


func _update_templates_file_buttons() -> void:
	var paths = TemplateManager.get_custom_template_file_paths()
	custom_templates_path_button.text = "Select file..." if paths.is_empty() else "Add file... (%d)" % paths.size()
	unload_custom_templates_button.disabled = paths.is_empty()


func _update_exercises_file_buttons() -> void:
	var paths = TemplateManager.get_custom_exercise_file_paths()
	custom_exercises_path_button.text = "Select file..." if paths.is_empty() else "Add file... (%d)" % paths.size()
	unload_custom_exercises_button.disabled = paths.is_empty()


func _on_unload_templates_pressed() -> void:
	var file_paths = TemplateManager.get_custom_template_file_paths()
	var popup = PopupMenu.new()
	for i in file_paths.size():
		popup.add_item(file_paths[i].get_file(), i)
	popup.add_separator()
	popup.add_item("Unload all", 1000)
	popup.id_pressed.connect(func(id):
		if id == 1000:
			TemplateManager.unload_all_custom_template_files()
		else:
			TemplateManager.unload_custom_template_file(file_paths[id])
		_update_templates_file_buttons()
	)
	popup.about_to_hide.connect(popup, "queue_free")
	add_child(popup)
	popup.popup_centered()


func _on_unload_exercises_pressed() -> void:
	var file_paths = TemplateManager.get_custom_exercise_file_paths()
	var popup = PopupMenu.new()
	for i in file_paths.size():
		popup.add_item(file_paths[i].get_file(), i)
	popup.add_separator()
	popup.add_item("Unload all", 1000)
	popup.id_pressed.connect(func(id):
		if id == 1000:
			TemplateManager.unload_all_custom_exercise_files()
		else:
			TemplateManager.unload_custom_exercise_file(file_paths[id])
		_update_exercises_file_buttons()
	)
	popup.about_to_hide.connect(popup, "queue_free")
	add_child(popup)
	popup.popup_centered()


func _on_delete_save_pressed() -> void:
	# Will implement with SaveManager
	SaveManager.delete_save()
	print("Save file deleted")


func _on_delete_blueprints_pressed() -> void:
	# Destructive + cross-save, so confirm first (the blueprint library
	# survives save deletion on purpose; this is its only kill switch).
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete blueprint library"
	dialog.dialog_text = "Delete all saved blueprints? They are shared across save files and this cannot be undone."
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		SaveManager.delete_blueprint_library()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _on_replay_tutorial_pressed() -> void:
	# Flag flip only — the tutorial re-arms on the next hex-editor
	# entry rather than yanking the player out of the current scene.
	SaveManager.set_tutorial_completed(false)
	SaveManager.unmark_chapter_intro_seen("chapter_0_tutorial")
	var tm := get_node_or_null("/root/TutorialManager")
	if tm:
		tm.reset()
	print("Tutorial re-armed — it will replay on the next editor visit")


func _on_back_pressed() -> void:
	close_requested.emit()
	if not _modal:
		# Default (full-screen) route: hand off to the main menu.
		SceneManager.go_to_main_menu()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
