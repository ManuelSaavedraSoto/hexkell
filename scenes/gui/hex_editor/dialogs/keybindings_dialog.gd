extends Control
## Read-only keybindings reference — Control-based modal mirroring
## the pause menu shell. Two-column body: category list on the left,
## bindings table on the right.
##
## "Showing only, no setter yet" — key labels derive from the live
## InputMap (via InputDisplay) wherever a row maps to an input action;
## rebinding still requires a hotkey-registry refactor.

signal closed

@onready var category_list: ItemList = %CategoryList
@onready var bindings_list: VBoxContainer = %BindingsList
@onready var _close_button: Button = %CloseButton

# Sections derive their key labels from the live InputMap wherever a
# binding maps to an input action, so the reference can't drift from
# project.godot. Three row flavors:
#   {"actions": [...]}  — keys rendered via InputDisplay from the
#                         action's events ("keyboard_only" skips mouse
#                         events the editor's mouse cascade owns);
#   {"keys_bb": "..."}  — hand-written BBCode for mouse gestures that
#                         aren't InputMap actions (drags, releases);
#   {"keys": "..."}     — plain-text notes (ranges, annotations).
static func _sections() -> Array:
	return [
		{
			"title": "Palette",
			"bindings": [
				{"keys": "Shift+1..5", "desc": "select category"},
				{"actions": ["cat_prev", "cat_next"], "desc": "step to previous / next category"},
				{"keys": "1..9, 0", "desc": "pick the Nth hex in the current category"},
				{"actions": ["hex_next", "hex_prev"], "desc": "cycle through the current category (Shift reverses)"},
			],
		},
		{
			"title": "Workspace tabs",
			"bindings": [
				{"keys": "Ctrl+1..9, 0", "desc": "jump to workspace tab"},
				{"actions": ["tab_next"], "desc": "cycle workspace tabs (Shift to reverse)"},
				{"actions": ["tab_new"], "desc": "open a new tab"},
				{"actions": ["tab_close"], "desc": "close the active tab"},
				{"keys_bb": InputDisplay.MOUSE_RMB, "desc": "on a tab: rename / clear / close"},
				{"keys": "(auto-save)", "desc": "tab contents auto-save ~1s after the last change"},
			],
		},
		{
			"title": "Jobs",
			"bindings": [
				{"actions": ["jobs_cycle_next", "jobs_cycle_prev"], "desc": "cycle pending jobs (Shift reverses)"},
				{"actions": ["jobs_toggle_view"], "desc": "swap jobs panel between list / description"},
				{"keys": "(wrap)", "desc": "cycling one past the last pending job clears the selection"},
				{"keys": "(run/submit)", "desc": "when a job is selected, Run becomes Submit"},
			],
		},
		{
			"title": "Canvas",
			"bindings": [
				{
					"actions": ["canvas_pan_up", "canvas_pan_left", "canvas_pan_down", "canvas_pan_right"],
					"desc": "pan (or hold middle mouse and drag)",
				},
				{"actions": ["canvas_zoom_in", "canvas_zoom_out"], "desc": "zoom in / out"},
				{"actions": ["canvas_home"], "desc": "center the camera on the active level"},
				{"actions": ["hex_descend", "hex_ascend"], "desc": "descend / ascend levels"},
				{"actions": ["hex_rotate_cw", "hex_rotate_ccw"], "desc": "rotate hex (under cursor or blueprint)"},
				{"actions": ["hex_pipette"], "desc": "copy hex under cursor (or anchor a wire)"},
				{"actions": ["hex_delete"], "keyboard_only": true, "desc": "delete hex under cursor"},
				{"keys_bb": "Shift+%s drag" % InputDisplay.MOUSE_LMB, "desc": "marquee select (highlights enclosed hexes)"},
				{"keys_bb": "Shift+%s drag" % InputDisplay.MOUSE_RMB, "desc": "marquee delete (removes enclosed hexes)"},
				{"actions": ["code_generate_text"], "desc": "regenerate program text"},
				{"actions": ["code_run"], "desc": "run (or submit if a job is selected)"},
				{"actions": ["code_copy_text"], "desc": "copy program text to clipboard"},
				{"actions": ["hex_toggle_output"], "desc": "expand / collapse the output panel"},
				{"actions": ["sys_help"], "desc": "this overlay (press again to close)"},
			],
		},
		{
			"title": "Wiring",
			"bindings": [
				{"keys": "Drag from slot", "desc": "start a wire"},
				{"keys": "Release on slot", "desc": "finalize to that slot"},
				{"keys": "Release on hex body", "desc": "finalize to the nearest compatible slot"},
				{"keys": "Release on open tip", "desc": "merge with another open wire"},
				{"keys": "Release on empty", "desc": "finalize as an open (unconnected) wire"},
			],
		},
		{
			"title": "Blueprints",
			"bindings": [
				{"actions": ["sys_open_library"], "desc": "open the Blueprint Library (press again to close)"},
				{"actions": ["sys_save"], "desc": "save current selection (or stamp / tab) as blueprint"},
				{"actions": ["sys_copy"], "desc": "copy selection → OS clipboard + enter stamp mode"},
				{"actions": ["sys_paste"], "desc": "paste latest copy / clipboard into stamp mode"},
				{
					"keys_bb": "Stamp %s / %s" % [InputDisplay.MOUSE_LMB, InputDisplay.MOUSE_RMB],
					"desc": "drop a copy (stays in mode) / exit stamp mode",
				},
				{"keys": "Library actions", "desc": "Capture / Stamp / Rename / Export / Import"},
			],
		},
		{
			"title": "Selection",
			"bindings": [
				{"keys_bb": "%s a hex" % InputDisplay.MOUSE_LMB, "desc": "single-select + open config panel"},
				{"keys_bb": "Shift+%s" % InputDisplay.MOUSE_LMB, "desc": "add the clicked hex to the selection"},
				{"keys_bb": "Shift+%s drag" % InputDisplay.MOUSE_LMB, "desc": "marquee select (adds to current set)"},
				{"keys_bb": "Shift+%s drag" % InputDisplay.MOUSE_RMB, "desc": "marquee delete (removes enclosed hexes)"},
				{"actions": ["hex_delete"], "keyboard_only": true, "desc": "delete selection (or hex under cursor)"},
				{"keys_bb": InputDisplay.MOUSE_RMB, "desc": "cancel contextual mode / clear selection (NOT a single-hex delete — use X)"},
			],
		},
		{
			"title": "Stamp mode",
			"bindings": [
				{"keys_bb": InputDisplay.MOUSE_LMB, "desc": "place a copy (stays in stamp mode)"},
				{"actions": ["hex_rotate_cw", "hex_rotate_ccw"], "desc": "rotate the stamp 60° CW / CCW"},
				{"keys_bb": "%s or [code]Esc[/code]" % InputDisplay.MOUSE_RMB, "desc": "exit stamp mode"},
			],
		},
		{
			"title": "Modes",
			"bindings": [
				{"keys_bb": InputDisplay.MOUSE_RMB, "desc": "blueprint cancel → wire cancel → close panel → delete"},
				{"actions": ["cancel"], "desc": "cancel current mode (or open the pause menu)"},
				{"actions": ["sys_undo"], "desc": "undo"},
				{"actions": ["sys_redo"], "desc": "redo"},
				{"actions": ["sys_open_repl"], "desc": "Quick REPL (evaluate against the editor's env)"},
				{"actions": ["sys_open_codex"], "desc": "open the Codex (press again to close)"},
			],
		},
	]

const KEYS_COLUMN_WIDTH := 180


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)
	_populate()
	category_list.item_selected.connect(_on_category_selected)


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# `sys_help` toggles: the tree is paused while this modal is open, so
# the editor-side CanvasInputController can't see the hotkey — the
# dialog itself handles the press-again-to-close.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("sys_help"):
		close()
		get_viewport().set_input_as_handled()


# Test-facing accessor: confirms the static sections data is wired
# through to the populated UI without exposing internal node paths.
func get_section_count() -> int:
	return _sections().size()


# Populate left-column category list + right-column bindings table.
# Each section gets a header label + a row per binding (keys cell +
# description label).
func _populate() -> void:
	category_list.clear()
	for child in bindings_list.get_children():
		child.queue_free()
	for section in _sections():
		category_list.add_item(String(section.title))
		bindings_list.add_child(_build_section(section))


func _build_section(section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = String(section.title)
	header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	header.add_theme_font_size_override("font_size", 14)
	box.add_child(header)

	for binding in section.bindings:
		box.add_child(_build_binding_row(binding))
	return box


func _build_binding_row(binding: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	# RichTextLabel so key/mouse icon BBCode renders; plain-text rows
	# pass through unchanged (no brackets in them).
	var keys := RichTextLabel.new()
	keys.bbcode_enabled = true
	keys.fit_content = true
	keys.scroll_active = false
	keys.autowrap_mode = TextServer.AUTOWRAP_OFF
	keys.custom_minimum_size = Vector2(KEYS_COLUMN_WIDTH, 0)
	keys.text = "[right]%s[/right]" % _binding_keys_bbcode(binding)
	keys.add_theme_color_override("default_color", Color(0.85, 0.9, 1.0))
	row.add_child(keys)

	var desc := Label.new()
	desc.text = String(binding.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(desc)
	return row


static func _binding_keys_bbcode(binding: Dictionary) -> String:
	if binding.has("actions"):
		return _actions_bbcode(binding.actions, binding.get("keyboard_only", false))
	if binding.has("keys_bb"):
		return String(binding.keys_bb)
	return String(binding.get("keys", ""))


# Multi-action rows dedupe across the whole row (canvas_zoom_in/out
# both carry a scroll-wheel event — render the wheel icon once).
static func _actions_bbcode(actions: Array, keyboard_only: bool) -> String:
	var parts: Array[String] = []
	for action in actions:
		for event in InputMap.action_get_events(action):
			if keyboard_only and not (event is InputEventKey):
				continue
			var s := InputDisplay.event_bbcode(event)
			if not s.is_empty() and not parts.has(s):
				parts.append(s)
	return " / ".join(parts)


func _on_category_selected(idx: int) -> void:
	if idx < 0 or idx >= bindings_list.get_child_count():
		return
	# Scroll the right column to the selected section.
	var scroll: ScrollContainer = bindings_list.get_parent()
	var section: Control = bindings_list.get_child(idx)
	scroll.scroll_vertical = int(section.position.y)
