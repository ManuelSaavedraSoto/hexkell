extends HBoxContainer
## Workspace tab strip — owns the strip's VIEW: it builds its own tab
## buttons, the right-click context menu, and the rename dialog, and
## re-emits everything as intents. The editor stays the model owner
## (it holds the tab list + active index and decides what each intent
## means); it hands the strip a list of names + the active index via
## `rebuild`.
##
## Hotkeys: Ctrl+T new tab, Ctrl+W close active, Ctrl+Tab / Ctrl+Shift+
## Tab cycle, Ctrl+1..9 jump to slot. Slot actions are bound by physical
## keycode for layout stability. Modal gating is free: this PAUSABLE
## node receives no input while a dialog is open.

signal tab_new_requested
signal tab_switch_requested(idx: int)
signal tab_close_requested(idx: int)
signal tab_clear_requested(idx: int)
signal tab_copy_requested(idx: int)
signal tab_rename_requested(idx: int, new_name: String)

const TAB_BUTTON_GROUP := preload("res://assets/resources/button_groups/tab_button_group.tres")
const TAB_BUTTON_THEME := preload("res://assets/resources/themes/tab_button_theme.tres")
const TAB_BUTTON_ACTIVE_MODULATE := Color(0.482, 0.549, 0.573, 1.0)
const TAB_BUTTON_INACTIVE_MODULATE := Color.WHITE

const _TAB_SLOT_ACTIONS := [
	"tab_slot_1", "tab_slot_2", "tab_slot_3", "tab_slot_4", "tab_slot_5",
	"tab_slot_6", "tab_slot_7", "tab_slot_8", "tab_slot_9",
]

var _names: Array = []
var _active_idx: int = 0
var _count: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if InputGates.text_input_focused(get_viewport()):
		return
	if event.is_action_pressed("tab_new", false, true):
		tab_new_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tab_close", false, true):
		tab_close_requested.emit(_active_idx)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tab_next", false, true):
		if _count > 0:
			tab_switch_requested.emit(posmod(_active_idx + 1, _count))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tab_prev", false, true):
		if _count > 0:
			tab_switch_requested.emit(posmod(_active_idx - 1, _count))
		get_viewport().set_input_as_handled()
	else:
		for i in _TAB_SLOT_ACTIONS.size():
			if event.is_action_pressed(_TAB_SLOT_ACTIONS[i], false, true):
				tab_switch_requested.emit(i)
				get_viewport().set_input_as_handled()
				return


## Rebuild the strip from the editor's tab names + active index. Each
## button click emits `tab_switch_requested(idx)`; right-click opens the
## per-tab context menu.
func rebuild(names: Array, active_idx: int) -> void:
	_names = names
	_active_idx = active_idx
	_count = names.size()
	for c in get_children():
		c.queue_free()
	for i in names.size():
		var btn := Button.new()
		btn.text = String(names[i])
		btn.toggle_mode = true
		btn.button_pressed = (i == active_idx)
		btn.modulate = TAB_BUTTON_ACTIVE_MODULATE if i == active_idx else TAB_BUTTON_INACTIVE_MODULATE
		btn.tooltip_text = "Ctrl+%d" % (i + 1) if i < 9 else String(names[i])
		btn.button_group = TAB_BUTTON_GROUP
		btn.theme = TAB_BUTTON_THEME
		var idx := i
		btn.pressed.connect(func() -> void: tab_switch_requested.emit(idx))
		btn.gui_input.connect(func(ev: InputEvent) -> void: _on_button_input(ev, idx))
		add_child(btn)


# Right-click on a tab button → context menu (rename / clear / copy /
# close). Built lazily so the strip rebuild stays cheap.
func _on_button_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var menu := PopupMenu.new()
	menu.add_item("Rename…", 0)
	menu.add_item("Clear", 1)
	menu.add_item("Copy blueprint", 2)
	if _count > 1:
		menu.add_item("Close", 3)
	add_child(menu)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.id_pressed.connect(func(id: int) -> void:
		match id:
			0: _prompt_rename(idx)
			1: tab_clear_requested.emit(idx)
			2: tab_copy_requested.emit(idx)
			3: tab_close_requested.emit(idx)
		menu.queue_free()
	)
	menu.close_requested.connect(menu.queue_free)
	menu.popup()


func _prompt_rename(idx: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Rename tab"
	var input := LineEdit.new()
	input.text = String(_names[idx]) if idx >= 0 and idx < _names.size() else ""
	input.custom_minimum_size = Vector2(280, 0)
	dialog.add_child(input)
	add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()
	input.select_all()
	dialog.confirmed.connect(func() -> void:
		tab_rename_requested.emit(idx, input.text)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
