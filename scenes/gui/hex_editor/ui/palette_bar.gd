class_name PaletteBar
extends PanelContainer
## Bottom-bar palette: category buttons + hex buttons.
##
## All buttons live in the scene tree, declared under
## `%CategoryTabRow` (5 `HexToolbarButton`s, one per category) and
## `%HexButtonRow` (5 `<Category>HexRow` HBoxContainer subgroups,
## each holding its hex buttons). Each hex button carries its
## script class via `HexToolbarButton.hex_script` (set in the
## scene), so this script never builds buttons procedurally.
##
## Editor-facing API:
##   palette_bar.set_unlocked_scripts(unlocked: Array[String])
##   palette_bar.select_category(idx: int)        # ⇧1..⇧5
##   palette_bar.step_category(±1)                # PageUp / PageDown
##   palette_bar.cycle_hex(±1)                    # Tab / Shift+Tab
##   palette_bar.pick_slot(slot: int)             # 1..9, 0
##   palette_bar.set_active_hex(script)           # called whenever
##                                                  _blueprint_class
##                                                  changes
##
## Emits `hex_selected(script)` when the user picks an unlocked hex
## (button press or keyboard slot). Emits `blueprint_mode_cancelled`
## when the player clicks the active button again to un-press it
## (clean-mouse exit). The editor reacts to both.

signal hex_selected(script_class)
signal blueprint_mode_cancelled
## Emitted on every category change; -1 means "none selected" (all
## rows hidden). The tutorial tracks this to verify the player found
## the Integer category on their own.
signal category_selected(idx: int)

const HEX_BUTTON_INACTIVE_MODULATE := Color.WHITE
const LOCKED_HEX_MODULATE := Color(0.55, 0.55, 0.6)

@onready var _hex_button_row: HBoxContainer = %HexButtonRow
@onready var _category_tab_row: HBoxContainer = %CategoryTabRow

var _current_category: int = 0
var _unlocked: Dictionary = {}  # script_path → true
var _active_script: Script = null
# Debug / archmage flag: when true, `_is_unlocked` returns true for
# every script regardless of the `_unlocked` dictionary contents.
var _archmage: bool = false

# Scene-cached views of the children: the 5 category buttons + the 5
# subgroup containers. Populated in `_ready`.
var _category_buttons: Array[HexToolbarButton] = []
var _hex_rows: Array[HBoxContainer] = []


func _ready() -> void:
	_category_buttons.clear()
	_hex_rows.clear()
	for child in _category_tab_row.get_children():
		if child is HexToolbarButton:
			_category_buttons.append(child)
	for child in _hex_button_row.get_children():
		if child is HBoxContainer:
			_hex_rows.append(child)
	# Wire category buttons: toggling one on selects it; toggling the
	# active one off deselects ALL categories (idx -1, rows hidden).
	# Editor/tutorial-initiated changes go through `select_category`,
	# which uses `set_pressed_no_signal` and so never re-enters here.
	for i in _category_buttons.size():
		var idx := i
		_category_buttons[i].toggled.connect(func(state: bool) -> void:
			if state:
				select_category(idx)
			elif idx == _current_category:
				# During the tutorial the player is locked to the Integer
				# category — deselecting strands the hex shelf and later
				# steps gate re-selection. Re-press and ignore the un-click.
				if TutorialManager.running:
					_category_buttons[idx].set_pressed_no_signal(true)
				else:
					select_category(-1)
		)
	# Wire hex buttons (children of each subgroup). The button's own
	# `hex_script` carries the script class — no name-lookup catalog.
	# Toggle-driven: pressing fires `hex_selected`; un-pressing the
	# active button fires `blueprint_mode_cancelled` (clean-mouse exit).
	for row in _hex_rows:
		for child in row.get_children():
			if child is HexToolbarButton and child.hex_script != null:
				var hex_btn: HexToolbarButton = child
				hex_btn.toggled.connect(
						func(state: bool) -> void:
							_on_hex_button_toggled(state, hex_btn.hex_script))


# ── Keyboard input (decentralized, action-based) ──────────────────────────
# The palette owns its hotkeys: 1-9/0 pick a slot, Shift+1-5 switch
# category, Tab/Shift+Tab cycle hexes, PageUp/PageDown step categories.
# All slot actions are bound by physical keycode, so layouts where
# Shift+1 produces "!" still address slot 1. Modal gating is free:
# this PAUSABLE node receives no input while a dialog is open.

const _HEX_SLOT_ACTIONS := [
	"hex_slot_1", "hex_slot_2", "hex_slot_3", "hex_slot_4", "hex_slot_5",
	"hex_slot_6", "hex_slot_7", "hex_slot_8", "hex_slot_9", "hex_slot_0",
]
const _CAT_SLOT_ACTIONS := [
	"cat_slot_1", "cat_slot_2", "cat_slot_3", "cat_slot_4", "cat_slot_5",
]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if InputGates.text_input_focused(get_viewport()):
		return
	if event.is_action_pressed("hex_next", false, true):
		cycle_hex(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hex_prev", false, true):
		cycle_hex(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cat_next", false, true):
		step_category(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cat_prev", false, true):
		step_category(-1)
		get_viewport().set_input_as_handled()
	else:
		for i in _HEX_SLOT_ACTIONS.size():
			if event.is_action_pressed(_HEX_SLOT_ACTIONS[i], false, true):
				pick_slot(i)
				get_viewport().set_input_as_handled()
				return
		for i in _CAT_SLOT_ACTIONS.size():
			if event.is_action_pressed(_CAT_SLOT_ACTIONS[i], false, true):
				select_category(i)
				get_viewport().set_input_as_handled()
				return


# ── Editor-facing API ──────────────────────────────────────────────────────

func set_unlocked_scripts(unlocked: Array) -> void:
	_unlocked.clear()
	for p in unlocked:
		_unlocked[String(p)] = true
	if is_inside_tree():
		_refresh_lock_state()
		_refresh_highlight()


# Companion to `set_unlocked_scripts`: when archmage is enabled,
# the unlock dictionary is ignored and every button reads as
# unlocked. Re-paints the rows immediately so the flip is visible
# without waiting for the player to switch categories.
func set_archmage(enabled: bool) -> void:
	if _archmage == enabled:
		return
	_archmage = enabled
	if is_inside_tree():
		_refresh_lock_state()
		_refresh_highlight()


# Select a category row by index; -1 deselects everything (no row
# visible, no button pressed) — the palette's resting state during the
# tutorial and after a deselect-on-reclick.
func select_category(idx: int) -> void:
	if idx >= _category_buttons.size():
		return
	idx = maxi(idx, -1)
	# Tutorial gate: outside the "find the Integer category" step the
	# palette is inert (deselects always pass — only the tutorial's
	# own on_enter issues those). Re-sync pressed states so a blocked
	# click doesn't leave its button looking engaged.
	if not TutorialManager.allows_category(idx):
		for i in _category_buttons.size():
			_category_buttons[i].set_pressed_no_signal(i == _current_category)
		return
	_current_category = idx
	for i in _category_buttons.size():
		_category_buttons[i].set_pressed_no_signal(i == idx)
	for i in _hex_rows.size():
		_hex_rows[i].visible = (i == idx)
	_refresh_highlight()
	category_selected.emit(idx)


func step_category(direction: int) -> void:
	if _category_buttons.is_empty():
		return
	# From the deselected state, step into the first/last available
	# category instead of feeding -1 into the wraparound math.
	var start: int = _current_category
	if start < 0:
		start = 0 if direction > 0 else _category_buttons.size() - 1
		if _category_is_available(start):
			select_category(start)
			return
	# Walk past categories whose every hex is still locked.
	for offset in range(1, _category_buttons.size() + 1):
		var idx := posmod(start + direction * offset, _category_buttons.size())
		if _category_is_available(idx):
			select_category(idx)
			return


func cycle_hex(direction: int) -> void:
	var row := _active_row()
	if row == null:
		return
	var buttons: Array = _hex_buttons_of(row)
	if buttons.is_empty():
		return
	var cur := -1
	if _active_script != null:
		for i in buttons.size():
			if buttons[i].hex_script == _active_script:
				cur = i
				break
	var next: int = posmod(cur + direction, buttons.size())
	_emit_pick(buttons[next].hex_script)


func pick_slot(slot: int) -> void:
	var row := _active_row()
	if row == null:
		return
	var buttons: Array = _hex_buttons_of(row)
	if slot < 0 or slot >= buttons.size():
		return
	_emit_pick(buttons[slot].hex_script)


func set_active_hex(script_class) -> void:
	_active_script = script_class
	_refresh_highlight()


# ── Lock + highlight ───────────────────────────────────────────────────────

func _refresh_lock_state() -> void:
	for i in _hex_rows.size():
		var row := _hex_rows[i]
		var category := _category_name_for_row(i)
		var unlocked_tint := _hex_button_tint_for_category(category)
		for btn in _hex_buttons_of(row):
			var locked := not _is_unlocked(btn.hex_script)
			btn.disabled = locked
			btn.modulate = LOCKED_HEX_MODULATE if locked else unlocked_tint
			if locked and not btn.tooltip_body.begins_with("🔒"):
				btn.tooltip_body = "🔒 Locked — earn renown by completing jobs to unlock.\n\n" + btn.tooltip_body
			elif not locked and btn.tooltip_body.begins_with("🔒"):
				# Strip the lock prefix once the type is unlocked.
				var split: int = btn.tooltip_body.find("\n\n")
				if split != -1:
					btn.tooltip_body = btn.tooltip_body.substr(split + 2)
	_refresh_category_availability()


# Scaffolding: a category whose every hex is still locked doesn't show
# its button at all — the bar literally grows as the player earns hexes.
# If the active category just locked away (e.g. custom unlock list
# shrank), fall back to the deselected state.
func _refresh_category_availability() -> void:
	for i in _category_buttons.size():
		_category_buttons[i].visible = _category_is_available(i)
	if _current_category >= 0 and not _category_is_available(_current_category):
		select_category(-1)


func _category_is_available(idx: int) -> bool:
	if idx < 0 or idx >= _hex_rows.size():
		return false
	for btn in _hex_buttons_of(_hex_rows[idx]):
		if _is_unlocked(btn.hex_script):
			return true
	return false


# Strip the `HexRow` suffix from a category row's node name to recover
# the canonical category name used by `HexPalette.CATEGORY_FAMILY`
# (e.g. "IntegerHexRow" → "Integer").
func _category_name_for_row(row_idx: int) -> String:
	if row_idx < 0 or row_idx >= _hex_rows.size():
		return ""
	var name: String = _hex_rows[row_idx].name
	if name.ends_with("HexRow"):
		return name.substr(0, name.length() - "HexRow".length())
	return name


# Wash toward the category midtone: 30% color, 70% white. Keeps icons
# legible while clearly tagging the row's hue family.
func _hex_button_tint_for_category(category: String) -> Color:
	var cat_color := HexPalette.category_color(category)
	return HexPalette.white().lerp(cat_color, 0.30)


func _refresh_highlight() -> void:
	# Walk every category's buttons (not just the active row) so a
	# category switch correctly un-presses hex buttons that lived in
	# the row we just left. The pressed-state border comes from the
	# theme's `pressed` StyleBox; no modulate involved.
	for row in _hex_rows:
		for btn in _hex_buttons_of(row):
			var active = (_active_script != null
					and btn.hex_script == _active_script
					and _is_unlocked(btn.hex_script))
			btn.set_pressed_no_signal(active)


# ── Helpers ────────────────────────────────────────────────────────────────

func _on_hex_button_toggled(state: bool, script_class) -> void:
	# Pressed: same effect as the old `pressed` signal — emit the pick
	# and let the editor enter blueprint mode.
	# Un-pressed via user click on the active button: exit blueprint
	# mode (clean-mouse gesture, mirrors the library-card flow).
	# Editor-initiated state changes use `set_pressed_no_signal` and
	# so never reach this handler.
	if state:
		_emit_pick(script_class)
	elif script_class == _active_script:
		_active_script = null
		blueprint_mode_cancelled.emit()


func _emit_pick(script_class) -> void:
	# Lock gate + tutorial gate share the same un-press cleanup so a
	# swallowed click never leaves the button looking engaged.
	if not _is_unlocked(script_class) \
			or not TutorialManager.allows_hex_pick(script_class):
		var btn := _button_for(script_class)
		if btn != null:
			btn.set_pressed_no_signal(false)
		return
	hex_selected.emit(script_class)


# Return the HexToolbarButton whose `hex_script == script`, or null
# if no such button exists. Used by tests + by `_emit_pick` to clear
# accidental presses on locked buttons.
func _button_for(script_class) -> HexToolbarButton:
	if script_class == null:
		return null
	for row in _hex_rows:
		for btn in _hex_buttons_of(row):
			if btn.hex_script == script_class:
				return btn
	return null


func _is_unlocked(script_class) -> bool:
	if script_class == null:
		return false
	if _archmage:
		return true
	var path: String = script_class.resource_path
	if path.is_empty():
		return true  # built-in / preloaded with no path — never lock
	return _unlocked.get(path, false)


func _active_row() -> HBoxContainer:
	if _current_category < 0 or _current_category >= _hex_rows.size():
		return null
	return _hex_rows[_current_category]


func _hex_buttons_of(row: HBoxContainer) -> Array:
	var out: Array = []
	for child in row.get_children():
		if child is HexToolbarButton and child.hex_script != null:
			out.append(child)
	return out


# Flat list of every palette hex script (across all categories).
# Used by `_seed_blueprint_registry()` so the loader can resolve hex
# scripts referenced by saved blueprints.
func get_all_scripts() -> Array:
	var out: Array = []
	for row in _hex_rows:
		for btn in _hex_buttons_of(row):
			out.append(btn.hex_script)
	return out


# Per-category script lists; used by tests that probe the palette's
# composition (e.g. asserting Boolean has no `<=` / `>` entries).
func scripts_in_category(name: String) -> Array:
	# The scene names each subgroup `<Key>HexRow` (IntegerHexRow,
	# BooleanHexRow, …); look it up by lowercasing the prefix.
	for row in _hex_rows:
		if row.name.to_lower().begins_with(name.to_lower()):
			return get_labels_in_row(row)
	return []


# Labels (button.text) of an active row's buttons. Tests use this to
# verify which operator glyphs the Boolean category exposes, etc.
func get_labels_in_row(row: HBoxContainer) -> Array:
	var out: Array = []
	for btn in _hex_buttons_of(row):
		out.append(btn.text)
	return out


# Public read for tests / debugging — Array[HBoxContainer] of the
# 5 category subgroups in declaration order.
func get_hex_rows() -> Array:
	return _hex_rows.duplicate()


func get_current_category() -> int:
	return _current_category


# Highlight targets for the tutorial: the category button at `idx`,
# and the hex button whose script lives at `script_path`.
func get_category_button(idx: int) -> HexToolbarButton:
	if idx < 0 or idx >= _category_buttons.size():
		return null
	return _category_buttons[idx]


func get_hex_button(script_path: String) -> HexToolbarButton:
	for row in _hex_rows:
		for btn in _hex_buttons_of(row):
			if btn.hex_script != null and btn.hex_script.resource_path == script_path:
				return btn
	return null
