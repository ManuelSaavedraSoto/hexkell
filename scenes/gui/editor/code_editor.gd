extends CodeEdit
## Enhanced CodeEdit with draggable templates and QoL features

## Regex pattern to match placeholder sections in templates
## Matches: {placeholder_name}, {- placeholder -}, <!-- placeholder_name -->, or __FILL_THIS__
const PLACEHOLDER_PATTERN = r"\{-[\s\S]*?-\}|\{[^}]+\}|<!--[^>]+-->|__[A-Z_]+__"

var _placeholder_regions: Array[Dictionary] = []  ## [{line: int, column: int, length: int, text: String}]
var _current_placeholder_index: int = 0
var _saved_selection: Dictionary = {}  ## Selection saved when focus is lost, so button clicks can still replace it


func _ready() -> void:
	# Enable drag and drop
	set_drag_forwarding(Callable(), _can_drop_data_fw, _drop_data_fw)

	# Customize selection colors for better placeholder visibility
	add_theme_color_override("selection_color", Color(0.2, 0.5, 0.9, 0.8))  # Bright blue with good contrast
	add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0, 1.0))  # White text for contrast

	# Clear placeholder regions when user edits text
	text_changed.connect(func():
		# Only clear if user is actually editing (not from programmatic insertion)
		if not is_placeholder_selected():
			_placeholder_regions.clear()
	)

	focus_exited.connect(func():
		if has_selection():
			_saved_selection = {
				"from_line": get_selection_from_line(),
				"from_col": get_selection_from_column(),
				"to_line": get_selection_to_line(),
				"to_col": get_selection_to_column(),
			}
		else:
			_saved_selection.clear()
	)
	focus_entered.connect(func(): _saved_selection.clear())


func is_placeholder_selected() -> bool:
	"""Check if current selection is a placeholder"""
	if _placeholder_regions.is_empty() or get_selected_text().is_empty():
		return false
	
	var start_line = get_selection_origin_line()
	var start_col = get_selection_origin_column()
	
	for placeholder in _placeholder_regions:
		if placeholder.line == start_line and placeholder.column == start_col:
			return true
	
	return false


## Insert template at current cursor position, replacing any active or saved selection
func insert_template_at_cursor(template_text: String) -> void:
	var start_line: int

	begin_complex_operation()
	if has_selection():
		start_line = get_selection_from_line()
		# insert_text_at_caret deletes the live selection internally
	elif not _saved_selection.is_empty():
		var s = _saved_selection
		start_line = s.from_line
		remove_text(s.from_line, s.from_col, s.to_line, s.to_col)
		set_caret_line(s.from_line)
		set_caret_column(s.from_col)
	else:
		start_line = get_caret_line()
	_saved_selection.clear()

	insert_text_at_caret(template_text)
	end_complex_operation()

	_find_placeholders(start_line, template_text.split("\n").size())
	_select_next_placeholder()
	grab_focus()


## Replace all editor content with template (original behavior)
func insert_template_replace_all(template_text: String) -> void:
	text = template_text
	_find_placeholders(0, get_line_count())
	_select_next_placeholder()


## Find all placeholder regions in the specified line range
func _find_placeholders(start_line: int, line_count: int) -> void:
	_placeholder_regions.clear()
	_current_placeholder_index = 0
	
	var regex = RegEx.new()
	regex.compile(PLACEHOLDER_PATTERN)
	
	var end_line = min(start_line + line_count, get_line_count())
	
	for line_idx in range(start_line, end_line):
		var line_text = get_line(line_idx)
		var matches = regex.search_all(line_text)
		
		for match in matches:
			_placeholder_regions.append({
				"line": line_idx,
				"column": match.get_start(),
				"length": match.get_string().length(),
				"text": match.get_string()
			})


## Select the next placeholder region
func _select_next_placeholder() -> void:
	if _placeholder_regions.is_empty():
		return
	
	if _current_placeholder_index >= _placeholder_regions.size():
		_current_placeholder_index = 0
		return
	
	var placeholder = _placeholder_regions[_current_placeholder_index]
	
	# Move cursor to start of placeholder
	set_caret_line(placeholder.line)
	set_caret_column(placeholder.column)
	
	# Select the placeholder text
	select(placeholder.line, placeholder.column, 
		   placeholder.line, placeholder.column + placeholder.length)
	
	# Center view on the selected text
	center_viewport_to_caret()
	
	_current_placeholder_index += 1


## Select the previous placeholder region
func _select_previous_placeholder() -> void:
	if _placeholder_regions.is_empty():
		return
	
	_current_placeholder_index -= 2  # -1 to undo the increment, -1 to go back
	if _current_placeholder_index < 0:
		_current_placeholder_index = _placeholder_regions.size() - 1
	
	_select_next_placeholder()


## Handle keyboard shortcuts
func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Tab: Jump to next placeholder
		if event.keycode == KEY_TAB and not event.shift_pressed:
			# If no placeholders found, search the entire editor
			if _placeholder_regions.is_empty():
				_find_placeholders(0, get_line_count())
			
			if not _placeholder_regions.is_empty():
				_select_next_placeholder()
				accept_event()  # Prevent default tab behavior
				return
		
		# Shift+Tab: Jump to previous placeholder
		elif event.keycode == KEY_TAB and event.shift_pressed:
			# If no placeholders found, search the entire editor
			if _placeholder_regions.is_empty():
				_find_placeholders(0, get_line_count())
			
			if not _placeholder_regions.is_empty():
				_select_previous_placeholder()
				accept_event()
				return
		
		# Escape: Clear placeholder navigation
		elif event.keycode == KEY_ESCAPE and not _placeholder_regions.is_empty():
			_placeholder_regions.clear()
			deselect()
			return
	
	# For all other input, let the parent handle it normally


## Drag and drop support
func _can_drop_data_fw(_at_position: Vector2, data: Variant) -> bool:
	# Check if data contains a template
	if data is Dictionary and data.has("template_text"):
		return true
	return false


func _drop_data_fw(at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.has("template_text"):
		if not has_selection():
			var drop_pos = get_line_column_at_pos(at_position)
			set_caret_line(drop_pos.y)
			set_caret_column(drop_pos.x)

		insert_template_at_cursor(data.template_text)
