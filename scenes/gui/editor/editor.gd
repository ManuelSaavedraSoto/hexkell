extends Control
## Interactive editor for the functional language with exercises and templates for accessibility

@onready var code_editor: CodeEdit = %CodeEditor
@onready var output_label: RichTextLabel = %OutputLabel
@onready var template_container: VBoxContainer = %TemplateContainer
@onready var exercises_container: VBoxContainer = %ExercisesContainer
@onready var sidebar_static: VBoxContainer = %SidebarStatic
@onready var menu_button: Button = %MenuButton
@onready var save_template_button: Button = %SaveTemplateButton
@onready var manage_templates_button: Button = %ManageTemplatesButton

const TEMPLATE_NAME_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/common/template_accept_dialog.tscn")
const CHAPTER_INTRO_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/common/chapter_intro_dialog.tscn")
const TEMPLATE_HINT_TOAST_SCENE: PackedScene = preload("res://scenes/gui/common/template_hint_toast.tscn")
const QUICK_REPL_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/common/quick_repl_dialog.tscn")

var template_name_dialog: AcceptDialog
var template_manage_dialog: AcceptDialog
var chapter_intro_dialog: AcceptDialog
var template_hint_toast: PanelContainer
var quick_repl_dialog: Control
var menu_overlay: AcceptDialog
var menu_overlay_content: VBoxContainer
var encyclopedia_dialog: AcceptDialog
var encyclopedia_list: VBoxContainer
var custom_template_names: Array[String] = []  # Track custom templates

var chapters: Dictionary = {}  ## chapter_id -> chapter data
var chapter_ids: Array = []
var hinted_exercises_this_session: Dictionary = {}  ## exercise_id -> true once hint shown

var environment: Env = Env.root()

var templates: Dictionary = {} ## Template definitions for accessibility
var exercises: Dictionary = {} ## Exercise definitions
var current_exercise: Dictionary = {} ## Currently selected exercise
var current_exercise_id: String = "" ## ID of current exercise

var exercise_ids: Array = []
var exercise_buttons: Dictionary = {}  ## exercise_id -> Button
var pending_reveal_queue: Array = []   ## exercise_ids waiting to appear
var reveal_timer: Timer = null

var renown_label: Label = null
var clients_label: Label = null


func _ready() -> void:
	templates = TemplateManager.get_all_templates()
	exercises = TemplateManager.get_all_exercises()
	chapters = TemplateManager.get_all_chapters()
	chapter_ids = TemplateManager.get_chapter_ids()
	exercise_ids = exercises.keys()
	exercise_ids.sort()

	environment = Env.root()
	Prelude.load_std_lib(environment)

	code_editor.grab_focus()
	_setup_menu_overlay()
	_create_menu_buttons()
	_setup_template_dialogs()
	_setup_quick_repl()
	_connect_template_buttons()
	menu_button.pressed.connect(_toggle_menu_overlay)

	# Create template buttons for accessibility
	_create_template_buttons()
	_load_custom_template_names()

	# Build chapter-grouped exercise menu
	_setup_exercises()

	# First time entering the editor, automatically open the first exercise.
	# That fires the chapter 1 intro (which doubles as a "what is this game"
	# onboarding) and leaves the exercise's description + starter code waiting
	# in the editor behind the modal.
	_auto_load_first_exercise()


func _setup_quick_repl() -> void:
	quick_repl_dialog = QUICK_REPL_DIALOG_SCENE.instantiate() as Control
	quick_repl_dialog.visible = false
	add_child(quick_repl_dialog)


func _create_menu_buttons() -> void:
	_build_sidebar_static()
	_build_menu_overlay_content()


func _build_sidebar_static() -> void:
	# Progress (renown / completed clients) stays pinned in the sidebar.
	_add_section(sidebar_static, "Progress")
	renown_label = Label.new()
	renown_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	sidebar_static.add_child(renown_label)
	clients_label = Label.new()
	clients_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	sidebar_static.add_child(clients_label)
	_update_progress_labels()

	# File operations as a compact icon row, also in the sidebar.
	_add_section(sidebar_static, "File")
	var icon_row = HBoxContainer.new()
	icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_row.add_theme_constant_override("separation", 4)
	_add_icon_button(icon_row, "📄", "New file (clear editor)", _on_new_file_pressed)
	_add_icon_button(icon_row, "🧹", "Clear editor (Ctrl+L)", _on_clear_editor_pressed)
	_add_icon_button(icon_row, "✓", "Check answer (Ctrl+Enter)", _on_check_answer_pressed)
	sidebar_static.add_child(icon_row)


func _build_menu_overlay_content() -> void:
	# Overlay shows only Navigation + Help, as a single flat column.
	_add_section(menu_overlay_content, "Navigation")
	_add_column_button(menu_overlay_content, "Main Menu", SceneManager.go_to_main_menu)
	_add_column_button(menu_overlay_content, "Exit", get_tree().quit)

	_add_section(menu_overlay_content, "Library")
	_add_column_button(menu_overlay_content, "📖 Encyclopedia", _show_encyclopedia)

	_add_section(menu_overlay_content, "Help")
	_add_column_button(menu_overlay_content, "Shortcuts", _show_shortcuts)
	_add_column_button(menu_overlay_content, "About", _show_about)


func _setup_menu_overlay() -> void:
	menu_overlay = AcceptDialog.new()
	menu_overlay.title = "Menu"
	menu_overlay.size = Vector2i(360, 380)
	menu_overlay.exclusive = false
	menu_overlay.get_ok_button().text = "Close"
	add_child(menu_overlay)

	menu_overlay_content = VBoxContainer.new()
	menu_overlay_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_overlay_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_overlay_content.add_theme_constant_override("separation", 4)
	menu_overlay.add_child(menu_overlay_content)


func _toggle_menu_overlay() -> void:
	if menu_overlay == null:
		return
	if menu_overlay.visible:
		menu_overlay.hide()
	else:
		menu_overlay.popup_centered()


func _add_section(parent: VBoxContainer, title: String) -> void:
	if parent.get_child_count() > 0:
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		parent.add_child(spacer)

	var label = Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)

	parent.add_child(HSeparator.new())


func _add_icon_button(parent: Container, glyph: String, tooltip: String, callback: Callable) -> void:
	var button = Button.new()
	button.text = glyph
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(36, 36)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_column_button(parent: Container, text: String, callback: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _setup_exercises() -> void:
	var renown: int = SaveManager.get_renown()
	# Flat list inside the scrollable area; chapters are introduced via the modal only.
	for exercise_id in exercise_ids:
		var exercise: Dictionary = exercises[exercise_id]
		var button = Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.visible = false
		button.pressed.connect(_on_exercise_selected.bind(exercise_id, exercise))
		exercise_buttons[exercise_id] = button
		exercises_container.add_child(button)
		if int(exercise.get("renown_required", 0)) <= renown:
			button.visible = true
			_refresh_exercise_button(exercise_id)

	reveal_timer = Timer.new()
	reveal_timer.wait_time = 0.8
	reveal_timer.one_shot = false
	reveal_timer.timeout.connect(_on_reveal_timer_tick)
	add_child(reveal_timer)


func _reveal_exercise(exercise_id: String) -> void:
	if not exercise_buttons.has(exercise_id):
		return
	exercise_buttons[exercise_id].visible = true
	_refresh_exercise_button(exercise_id)
	var exercise_name: String = exercises.get(exercise_id, {}).get("name", exercise_id)
	_append_output("[color=cyan]🔓 Unlocked: %s[/color]" % exercise_name)


func _on_reveal_timer_tick() -> void:
	if pending_reveal_queue.is_empty():
		reveal_timer.stop()
		return
	var exercise_id: String = pending_reveal_queue.pop_front()
	_reveal_exercise(exercise_id)
	if pending_reveal_queue.is_empty():
		reveal_timer.stop()


func _refresh_exercise_button(exercise_id: String) -> void:
	if not exercise_buttons.has(exercise_id):
		return
	var button: Button = exercise_buttons[exercise_id]
	var exercise: Dictionary = exercises.get(exercise_id, {})
	var exercise_name: String = exercise.get("name", "Unknown")
	var completed: bool = SaveManager.is_exercise_completed(exercise_id)
	if completed:
		button.text = "✓ %s" % exercise_name
		button.tooltip_text = "Already completed"
	else:
		button.text = exercise_name
		var reward: int = int(exercise.get("renown_reward", 0))
		button.tooltip_text = "Reward: %d renown" % reward


func _refresh_all_exercise_buttons() -> void:
	for exercise_id in exercise_buttons.keys():
		if exercise_buttons[exercise_id].visible:
			_refresh_exercise_button(exercise_id)


func _update_progress_labels() -> void:
	if renown_label:
		renown_label.text = "  Renown: %d" % SaveManager.get_renown()
	if clients_label:
		var visible_count: int = 0
		var solved_count: int = 0
		for exercise_id in exercise_buttons.keys():
			if exercise_buttons[exercise_id].visible:
				visible_count += 1
				if SaveManager.is_exercise_completed(exercise_id):
					solved_count += 1
		clients_label.text = "  Solved: %d / %d" % [solved_count, visible_count]


func _on_template_button_pressed(button: Button) -> void:
	var template_text = button.get_meta("template")
	code_editor.insert_template_at_cursor(template_text)
	code_editor.grab_focus()


func _on_exercise_selected(exercise_id: String, exercise_data: Dictionary) -> void:
	current_exercise_id = exercise_id
	current_exercise = exercise_data

	SaveManager.attempt_exercise(exercise_id)

	# Display exercise description in the editor
	var description = exercise_data.get("description", "No description available")
	var header = "-- Exercise: %s\n-- %s\n\n" % [exercise_id, description]
	var starter = String(exercise_data.get("starter_code", ""))
	code_editor.text = header + starter

	# Show selection in output
	_append_output("[color=cyan]Exercise selected: %s[/color]" % exercise_id)
	var reward: int = int(exercise_data.get("renown_reward", 0))
	if reward > 0 and not SaveManager.is_exercise_completed(exercise_id):
		_append_output("[color=gray]Reward on first solve: %d renown[/color]" % reward)
	_append_output("")
	code_editor.grab_focus()

	# Surface chapter intro the first time the player enters this chapter,
	# then nudge them about relevant unlocked templates.
	var chapter_id: String = TemplateManager.get_chapter_for_exercise(exercise_id)
	if chapter_id != "":
		_show_chapter_intro(chapter_id)
	_maybe_show_template_hint(exercise_id, exercise_data)


func _on_check_answer_pressed() -> void:
	if current_exercise_id.is_empty():
		_append_output("[color=red]No exercise selected[/color]")
		return
	
	var code = code_editor.text.strip_edges()
	if code.is_empty():
		_append_output("[color=red]No code to check[/color]")
		return
	
	_append_output("[color=cyan]Checking answer...[/color]")
	
	# Use the Checker singleton to validate
	var result = Checker.check_answer(current_exercise, code)
	
	# Display results
	if result.get("correct", false):
		_append_output("[color=green]✓ Correct! %s[/color]" % result.get("message", ""))
		_award_exercise_completion(current_exercise_id, current_exercise)
	else:
		_append_output("[color=red]✗ Incorrect[/color]")
		_append_output("[color=yellow]%s[/color]" % result.get("message", "Unknown error"))
	
	# Show detailed test results if available
	if result.has("results") and result["results"].size() > 0:
		_append_output("[color=gray]Test details:[/color]")
		for i in range(result["results"].size()):
			var test_result = result["results"][i]
			var status = "✓" if test_result.get("passed", false) else "✗"
			var input_str = str(test_result.get("input", "<no input>"))
			_append_output("  %s Test %d (input: %s): %s" % [
				status,
				i + 1,
				input_str,
				test_result.get("message", "")
			])
	
	_append_output("")


func _award_exercise_completion(exercise_id: String, exercise_data: Dictionary) -> void:
	if exercise_id.is_empty():
		return

	var already_done: bool = SaveManager.is_exercise_completed(exercise_id)
	SaveManager.complete_exercise(exercise_id)
	SaveManager.complete_client()

	if already_done:
		_append_output("[color=gray](Already solved — no additional renown awarded.)[/color]")
	else:
		var reward: int = int(exercise_data.get("renown_reward", 0))
		if reward > 0:
			var prev_renown: int = SaveManager.get_renown()
			SaveManager.add_renown(reward)
			var new_renown: int = SaveManager.get_renown()
			_append_output("[color=yellow]+%d renown! (Total: %d)[/color]" % [reward, new_renown])
			_queue_unlocked_reveals(prev_renown, new_renown)

	_update_progress_labels()
	_refresh_all_exercise_buttons()


func _queue_unlocked_reveals(prev_renown: int, new_renown: int) -> void:
	var newly_unlocked: Array = []
	for exercise_id in exercise_ids:
		var required: int = int(exercises.get(exercise_id, {}).get("renown_required", 0))
		if required > prev_renown and required <= new_renown:
			newly_unlocked.append(exercise_id)

	if newly_unlocked.is_empty():
		return

	# Check if the player still has unsolved visible exercises to work on.
	var has_unsolved_visible: bool = false
	for exercise_id in exercise_buttons.keys():
		if exercise_buttons[exercise_id].visible and not SaveManager.is_exercise_completed(exercise_id):
			has_unsolved_visible = true
			break

	# Nothing left to do — reveal the first unlock immediately so the player isn't stuck.
	if not has_unsolved_visible:
		_reveal_exercise(newly_unlocked.pop_front())

	for exercise_id in newly_unlocked:
		pending_reveal_queue.append(exercise_id)

	if not pending_reveal_queue.is_empty() and reveal_timer.is_stopped():
		reveal_timer.start()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Escape opens the menu overlay. When the overlay is already showing,
		# AcceptDialog handles Escape itself to close it — don't fight that.
		if event.keycode == KEY_ESCAPE and not event.echo:
			if quick_repl_dialog and quick_repl_dialog.visible:
				return  # The quick-REPL dialog handles its own Escape.
			if menu_overlay and not menu_overlay.visible:
				menu_overlay.popup_centered()
				get_viewport().set_input_as_handled()
				return

		# Ctrl+Enter to check answer or evaluate
		if event.ctrl_pressed and event.keycode == KEY_ENTER:
			if current_exercise_id.is_empty():
				# If no exercise selected, just evaluate for testing
				_evaluate_code()
			else:
				# If exercise selected, check answer
				_on_check_answer_pressed()
			get_viewport().set_input_as_handled()

		# Ctrl+R toggles the modal quick-REPL search bar
		elif event.ctrl_pressed and event.keycode == KEY_R:
			_toggle_quick_repl()
			get_viewport().set_input_as_handled()

		# Ctrl+K to clear output
		elif event.ctrl_pressed and event.keycode == KEY_K:
			_clear_output()
			get_viewport().set_input_as_handled()

		# Ctrl+L to clear editor
		elif event.ctrl_pressed and event.keycode == KEY_L:
			_on_clear_editor_pressed()
			get_viewport().set_input_as_handled()


func _toggle_quick_repl() -> void:
	if quick_repl_dialog == null:
		return
	if quick_repl_dialog.visible:
		quick_repl_dialog.call("close")
	else:
		quick_repl_dialog.call("open", environment)


# ── Menu actions ────────────────────────────────────────────────────────────

func _on_new_file_pressed() -> void:
	code_editor.text = ""
	code_editor.grab_focus()
	_append_output("[color=cyan]Editor cleared[/color]")


func _show_shortcuts() -> void:
	_append_output("[color=cyan]Keyboard Shortcuts:[/color]")
	_append_output("  Ctrl+Enter  - Check answer or run code")
	_append_output("  Ctrl+R      - Open quick-REPL search bar (Esc to close)")
	_append_output("  Ctrl+L      - Clear editor")
	_append_output("  Ctrl+K      - Clear output")
	_append_output("  Tab         - Jump to next placeholder in template")
	_append_output("  Shift+Tab   - Jump to previous placeholder in template")
	_append_output("  Escape      - Open menu / dismiss popups")
	_append_output("  Up/Down     - Navigate quick-REPL history (when open)")
	_append_output("")
	_append_output("[color=cyan]Template Features:[/color]")
	_append_output("  • Click a template button to insert at cursor")
	_append_output("  • Drag a template button to any location in the editor")
	_append_output("  • Use Tab/Shift+Tab to navigate {placeholders} after inserting")
	_append_output("  • Type to replace selected placeholder text")
	_append_output("  • Right-click custom templates to delete them")
	_append_output("")
	_append_output("[color=cyan]Workflow:[/color]")
	_append_output("  1. Use template buttons to scaffold your code (accessibility & speed)")
	_append_output("  2. Navigate placeholders with Tab to fill in variable names")
	_append_output("  3. Click an exercise from the left sidebar")
	_append_output("  4. Read the description and test cases")
	_append_output("  5. Write your solution in the editor")
	_append_output("  6. Press Ctrl+Enter or click 'Check Answer'")
	_append_output("")



func _show_about() -> void:
	_append_output("[color=cyan]Functional Language Exercise System[/color]")
	_append_output("A lazy functional programming language with:")
	_append_output("  • Pattern matching")
	_append_output("  • Higher-order functions")
	_append_output("  • List comprehensions")
	_append_output("  • Lazy evaluation")
	_append_output("  • Recursive definitions")
	_append_output("")
	_append_output("[color=cyan]Features:[/color]")
	_append_output("  • Interactive exercises loaded from static data")
	_append_output("  • Automatic answer validation with multiple test cases")
	_append_output("  • Modal quick-REPL (Ctrl+R) for one-off expression tests")
	_append_output("  • Real-time syntax highlighting")
	_append_output("")


# ── Code evaluation ─────────────────────────────────────────────────────────

func _on_clear_editor_pressed() -> void:
	code_editor.clear()
	code_editor.grab_focus()


func _evaluate_code() -> void:
	var code = code_editor.text.strip_edges()

	if code.is_empty():
		_append_output("[color=yellow]No code to evaluate[/color]")
		return

	SaveManager.increment_code_runs()
	_append_output("[color=cyan]Evaluating...[/color]")

	# Parse the editor contents as a module. Every top-level definition is
	# installed into the persistent environment so the REPL below can see
	# them; the program's `main` expression is then evaluated and shown.
	var program: Ctrl.Program = Parser.parse_module(code)
	if program == null:
		_append_output("[color=red]Parse error - check console for details[/color]")
		return

	environment = program.install(environment)

	for def in program.get_definitions():
		_append_output("[color=#9fcfff]defined %s[/color]" % def.name)

	var main_expr: Expr = program.get_main_expr()
	if main_expr == null:
		_append_output("[color=gray](no main expression to evaluate)[/color]")
		_append_output("")
		return

	var result = main_expr.interpret(environment)
	if result == null:
		_append_output("[color=red]Runtime error - check console for details[/color]")
		return
	result = result.force()

	var label: String = "result"
	if program.has_explicit_main():
		label = program.get_main_name()
	elif main_expr is Expr.Var:
		label = (main_expr as Expr.Var)._name
	_append_output("[color=green]%s = %s[/color]" % [label, _value_to_string(result)])
	_append_output("")


func _clear_output() -> void:
	output_label.clear()
	_append_output("[color=gray]Output cleared[/color]")


func _value_to_string(value: Value) -> String:
	if value is Value.List:
		return str(value.unwrap())
	elif value is Value.Tuple:
		return str(value.unwrap())
	elif value is Value.Closure:
		return "<function>"
	elif value is Value.Bool:
		return "true" if value.unwrap() else "false"
	else:
		return str(value.unwrap())


func _append_output(text: String) -> void:
	output_label.append_text(text + "\n")
	
	# Auto-scroll to bottom
	await get_tree().process_frame
	output_label.scroll_to_line(output_label.get_line_count() - 1)


func _setup_template_dialogs() -> void:
	# Instantiate the shared template name dialog scene
	template_name_dialog = TEMPLATE_NAME_DIALOG_SCENE.instantiate() as AcceptDialog
	template_name_dialog.visible = false
	template_name_dialog.template_name_entered.connect(_on_template_name_entered)
	add_child(template_name_dialog)

	# Create template management dialog
	template_manage_dialog = AcceptDialog.new()
	template_manage_dialog.title = "Manage Custom Templates"
	template_manage_dialog.dialog_text = "Select templates to delete:"
	template_manage_dialog.size = Vector2i(400, 300)
	template_manage_dialog.ok_button_text = "Close"
	add_child(template_manage_dialog)

	# Chapter intro modal: shown once per chapter; unlocks that chapter's templates on dismissal.
	chapter_intro_dialog = CHAPTER_INTRO_DIALOG_SCENE.instantiate() as AcceptDialog
	chapter_intro_dialog.visible = false
	chapter_intro_dialog.chapter_closed.connect(_on_chapter_intro_closed)
	add_child(chapter_intro_dialog)

	# Encyclopedia: browsable list of chapter intros the player has unlocked.
	encyclopedia_dialog = AcceptDialog.new()
	encyclopedia_dialog.title = "Encyclopedia"
	encyclopedia_dialog.size = Vector2i(420, 460)
	encyclopedia_dialog.min_size = Vector2i(360, 320)
	encyclopedia_dialog.exclusive = false
	encyclopedia_dialog.get_ok_button().text = "Close"
	var enc_margin := MarginContainer.new()
	enc_margin.add_theme_constant_override("margin_left", 12)
	enc_margin.add_theme_constant_override("margin_right", 12)
	enc_margin.add_theme_constant_override("margin_top", 12)
	enc_margin.add_theme_constant_override("margin_bottom", 12)
	enc_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enc_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	encyclopedia_dialog.add_child(enc_margin)
	var enc_scroll := ScrollContainer.new()
	enc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enc_margin.add_child(enc_scroll)
	encyclopedia_list = VBoxContainer.new()
	encyclopedia_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encyclopedia_list.add_theme_constant_override("separation", 4)
	enc_scroll.add_child(encyclopedia_list)
	add_child(encyclopedia_dialog)

	# Non-focus toast that nudges the player about relevant unlocked templates.
	# Anchored to the top-right corner of the editor so it sits beside/above
	# the templates panel without grabbing keyboard focus.
	template_hint_toast = TEMPLATE_HINT_TOAST_SCENE.instantiate() as PanelContainer
	template_hint_toast.visible = false
	template_hint_toast.template_insert_requested.connect(_on_hint_template_inserted)
	template_hint_toast.anchor_left = 1.0
	template_hint_toast.anchor_right = 1.0
	template_hint_toast.anchor_top = 0.0
	template_hint_toast.anchor_bottom = 0.0
	# Keep the toast clear of the template sidebar on the right (≈180px panel
	# + 20px outer margin + breathing room) so it nudges instead of obscures.
	template_hint_toast.offset_left = -540
	template_hint_toast.offset_right = -220
	template_hint_toast.offset_top = 60
	template_hint_toast.offset_bottom = 60
	template_hint_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	template_hint_toast.grow_vertical = Control.GROW_DIRECTION_END
	add_child(template_hint_toast)


# ── Chapter intro & template hint popups ────────────────────────────────────

func _show_chapter_intro(chapter_id: String) -> void:
	var chapter: Dictionary = chapters.get(chapter_id, {})
	if chapter.is_empty():
		return
	if SaveManager.has_seen_chapter_intro(chapter_id):
		return
	SaveManager.mark_chapter_intro_seen(chapter_id)
	chapter_intro_dialog.call("show_chapter", chapter_id, chapter)


func _auto_load_first_exercise() -> void:
	# On a fresh save, auto-select the first exercise of the first chapter.
	# That populates the editor with its description + starter code and also
	# fires the chapter intro modal (which serves as game onboarding).
	if chapter_ids.is_empty():
		return
	var first_chapter_id: String = String(chapter_ids[0])
	if SaveManager.has_seen_chapter_intro(first_chapter_id):
		return  # Returning player — leave the editor as the player left it.
	var chapter: Dictionary = chapters.get(first_chapter_id, {})
	var ex_list: Array = chapter.get("exercises", [])
	if ex_list.is_empty():
		return
	var first_ex_id: String = String(ex_list[0])
	if not exercises.has(first_ex_id):
		return
	# Defer so the rest of _ready (layout, buttons) settles before the modal pops.
	call_deferred("_on_exercise_selected", first_ex_id, exercises[first_ex_id])


# ── Encyclopedia ────────────────────────────────────────────────────────────

func _show_encyclopedia() -> void:
	# Refresh the list each time — chapters may have been unlocked since the
	# dialog was last opened, and we want the current state.
	for child in encyclopedia_list.get_children():
		child.queue_free()

	var unlocked: Array = []
	for chapter_id in chapter_ids:
		if SaveManager.has_seen_chapter_intro(String(chapter_id)):
			unlocked.append(chapter_id)

	if unlocked.is_empty():
		var empty := Label.new()
		empty.text = "No chapters unlocked yet.\nComplete exercises to discover more."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		encyclopedia_list.add_child(empty)
	else:
		var header := Label.new()
		header.text = "Unlocked chapters — click to revisit:"
		header.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		header.add_theme_font_size_override("font_size", 13)
		encyclopedia_list.add_child(header)
		encyclopedia_list.add_child(HSeparator.new())

		for chapter_id in unlocked:
			var chapter: Dictionary = chapters.get(chapter_id, {})
			var button := Button.new()
			button.text = chapter.get("name", chapter_id)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 14)
			button.tooltip_text = "Open chapter introduction"
			button.pressed.connect(_on_encyclopedia_chapter_pressed.bind(String(chapter_id)))
			encyclopedia_list.add_child(button)

	encyclopedia_dialog.popup_centered()


func _on_encyclopedia_chapter_pressed(chapter_id: String) -> void:
	var chapter: Dictionary = chapters.get(chapter_id, {})
	if chapter.is_empty():
		return
	# Close the encyclopedia first so the intro dialog isn't stacked behind it.
	encyclopedia_dialog.hide()
	chapter_intro_dialog.call("show_chapter", chapter_id, chapter)


func _on_chapter_intro_closed(chapter_id: String) -> void:
	var chapter: Dictionary = chapters.get(chapter_id, {})
	if chapter.is_empty():
		return
	var unlocked_any: bool = false
	for template_name in chapter.get("unlocks_templates", []):
		if templates.has(template_name) and not SaveManager.is_pattern_unlocked(template_name):
			SaveManager.unlock_pattern(template_name)
			unlocked_any = true
	if unlocked_any:
		_refresh_template_buttons()
		_append_output("[color=cyan]🔓 New templates unlocked — check the right panel.[/color]")


func _maybe_show_template_hint(exercise_id: String, exercise_data: Dictionary) -> void:
	# Honor the user's hints preference and avoid nagging within a single session.
	if not SaveManager.get_show_hints():
		return
	if hinted_exercises_this_session.get(exercise_id, false):
		return

	var hint_names: Array = exercise_data.get("template_hints", [])
	if hint_names.is_empty():
		return

	# Only remind about templates the player has actually unlocked.
	var entries: Array = []
	for template_name in hint_names:
		if not templates.has(template_name):
			continue
		if not SaveManager.is_pattern_unlocked(template_name):
			continue
		entries.append({
			"name": template_name,
			"text": templates[template_name],
		})

	if entries.is_empty():
		return

	hinted_exercises_this_session[exercise_id] = true
	var exercise_name: String = exercise_data.get("name", exercise_id)
	template_hint_toast.call("show_hint", exercise_name, entries)


func _on_hint_template_inserted(template_text: String) -> void:
	code_editor.insert_template_at_cursor(template_text)
	# Do not grab_focus on the editor here — selecting Insert should feel like
	# a gentle nudge; the player keeps whatever focus they had.


func _connect_template_buttons() -> void:
	if save_template_button:
		save_template_button.pressed.connect(_on_save_template_pressed)
	if manage_templates_button:
		manage_templates_button.pressed.connect(_on_manage_templates_pressed)


func _load_custom_template_names() -> void:
	# Load the list of custom template names from TemplateManager
	var all_templates = TemplateManager.get_all_templates()
	var default_templates = StaticData.static_data.get("templates", {})
	
	custom_template_names.clear()
	for template_name in all_templates.keys():
		if template_name not in default_templates:
			custom_template_names.append(template_name)


# ── Save Template Functionality ────────────────────────────────────────────

func _on_save_template_pressed() -> void:
	var code = code_editor.text.strip_edges()
	
	if code.is_empty():
		_append_output("[color=yellow]Cannot save empty template[/color]")
		return
	
	template_name_dialog.popup_centered()


func _on_template_name_entered(template_name: String) -> void:
	# Check if template already exists
	var existing_templates = TemplateManager.get_all_templates()
	if template_name in existing_templates:
		template_name_dialog.call("show_error", "Template '%s' already exists" % template_name)
		return
	
	# Save the template
	var code = code_editor.text.strip_edges()
	TemplateManager.add_custom_template(template_name, code)
	
	# Add to custom templates list
	if template_name not in custom_template_names:
		custom_template_names.append(template_name)
	
	# Refresh template buttons
	_refresh_template_buttons()
	
	_append_output("[color=green]✓ Template '%s' saved successfully[/color]" % template_name)


func _is_valid_template_name(_name: String) -> bool:
	# Allow alphanumeric, spaces, hyphens, and underscores
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9\\s_-]+$")
	return regex.search(_name) != null


# ── Manage Templates Functionality ─────────────────────────────────────────

func _on_manage_templates_pressed() -> void:
	# Clear previous content
	for child in template_manage_dialog.get_children():
		if child is ScrollContainer:
			child.queue_free()
	
	if custom_template_names.is_empty():
		var label = Label.new()
		label.text = "No custom templates yet.\nSave some code as a template to get started!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		template_manage_dialog.add_child(label)
		template_manage_dialog.popup_centered()
		return
	
	# Create scrollable list of custom templates
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	for template_name in custom_template_names:
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = template_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		var delete_button = Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(_on_delete_template.bind(template_name))
		hbox.add_child(delete_button)
		
		vbox.add_child(hbox)
	
	scroll.add_child(vbox)
	template_manage_dialog.add_child(scroll)
	template_manage_dialog.popup_centered()


func _on_delete_template(template_name: String) -> void:
	# Close the manage dialog first to avoid exclusive popup conflicts
	template_manage_dialog.hide()

	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Delete template '%s'?\nThis cannot be undone." % template_name
	confirm_dialog.exclusive = false
	var deletion_state = {"confirmed": false}
	confirm_dialog.confirmed.connect(func():
		deletion_state["confirmed"] = true
		# Remove from TemplateManager
		TemplateManager.remove_custom_template(template_name)
		
		# Remove from local list
		custom_template_names.erase(template_name)
		
		# Refresh UI
		_refresh_template_buttons()
		_on_manage_templates_pressed()  # Refresh the manage dialog
		
		_append_output("[color=yellow]Template '%s' deleted[/color]" % template_name)
	)
	confirm_dialog.connect("popup_hide", func():
		if not deletion_state["confirmed"]:
			_on_manage_templates_pressed()
		confirm_dialog.queue_free()
	)
	template_manage_dialog.add_child(confirm_dialog)
	confirm_dialog.popup_centered()


# ── Template Button Management ─────────────────────────────────────────────

func _refresh_template_buttons() -> void:
	# Clear existing buttons
	for child in template_container.get_children():
		child.queue_free()
	
	# Reload templates
	templates = TemplateManager.get_all_templates()
	
	# Recreate template buttons
	_create_template_buttons()


func _create_template_buttons() -> void:
	# Sort templates: default first, then custom. Default templates are hidden
	# until unlocked by a chapter intro; custom templates are always available.
	var default_templates = StaticData.static_data.get("templates", {})
	var default_keys: Array[String] = []
	var custom_keys: Array[String] = []

	for template_name in templates.keys():
		if template_name in default_templates:
			if SaveManager.is_pattern_unlocked(template_name):
				default_keys.append(template_name)
		else:
			custom_keys.append(template_name)

	default_keys.sort()
	custom_keys.sort()

	# Add default (unlocked) templates
	if not default_keys.is_empty():
		var default_label = Label.new()
		default_label.text = "Unlocked Templates"
		default_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		default_label.add_theme_font_size_override("font_size", 11)
		template_container.add_child(default_label)

		for template_name in default_keys:
			_create_template_button(template_name, false)
	else:
		var empty_label = Label.new()
		empty_label.text = "No templates yet.\nFinish a chapter intro to unlock some."
		empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty_label.add_theme_font_size_override("font_size", 11)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		template_container.add_child(empty_label)
	
	# Add custom templates with visual distinction
	if not custom_keys.is_empty():
		var separator = HSeparator.new()
		template_container.add_child(separator)
		
		var custom_label = Label.new()
		custom_label.text = "My Templates"
		custom_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1))
		custom_label.add_theme_font_size_override("font_size", 11)
		template_container.add_child(custom_label)
		
		for template_name in custom_keys:
			_create_template_button(template_name, true)


func _create_template_button(template_name: String, is_custom: bool) -> void:
	var button = Button.new()
	button.text = template_name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Visual distinction for custom templates
	if is_custom:
		button.text = "★ " + template_name  # Add star icon
		button.tooltip_text = "Custom template - drag to insert, right-click to delete"
	else:
		button.tooltip_text = "Drag to insert or click to insert at cursor"
	
	# Store template content in button meta
	button.set_meta("template", templates[template_name])
	button.set_meta("template_text", templates[template_name])
	button.set_meta("template_name", template_name)
	button.set_meta("is_custom", is_custom)
	
	# Connect to insert function on click
	button.pressed.connect(_on_template_button_pressed.bind(button))
	
	# Enable drag and drop for this button
	button.set_drag_forwarding(
		_get_template_drag_data.bind(button),
		Callable(),
		Callable()
	)
	
	# Add right-click menu for custom templates
	if is_custom:
		button.gui_input.connect(_on_template_button_gui_input.bind(template_name))
	
	template_container.add_child(button)


func _on_template_button_gui_input(event: InputEvent, template_name: String) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Show context menu for custom templates
			var popup = PopupMenu.new()
			popup.add_item("Delete Template", 0)
			popup.id_pressed.connect(func(id):
				if id == 0:
					_on_delete_template(template_name)
			)
			add_child(popup)
			popup.popup(Rect2(get_global_mouse_position(), Vector2.ZERO))


func _get_template_drag_data(_from_pos: Vector2, button: Button) -> Variant:
	"""Generate drag data for template button"""
	# Create visual drag preview
	var preview = Label.new()
	var template_name = button.get_meta("template_name")
	preview.text = template_name
	preview.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	
	var panel = PanelContainer.new()
	panel.add_child(preview)
	panel.modulate.a = 0.8
	button.set_drag_preview(panel)
	
	# Return template data for drop handler
	return {
		"template_text": button.get_meta("template_text"),
		"template_name": button.get_meta("template_name")
	}


# Update the existing _create_template_buttons method to use the new one
# Replace the old method body with just:
func _create_template_buttons_old() -> void:
	_create_template_buttons()
