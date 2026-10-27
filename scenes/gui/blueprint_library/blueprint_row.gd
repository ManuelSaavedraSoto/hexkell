extends Button
## One blueprint entry in the library list. The row is a toggle
## Button — clicking the panel (anywhere not on a nested action
## button) flips the `toggled` state, fires `selected`, and asks
## the dialog to preview this entry. Action buttons emit dedicated
## signals the dialog handles (rename / export / delete / stamp).
##
## Selection visual rides on the Button's native `pressed` state
## (Godot draws the pressed StyleBox while `button_pressed = true`).
## The dialog's single-selection bookkeeping flips siblings off via
## `set_selected(false)` so only the active row stays lit.

signal selected(index: int)
signal stamp_pressed(payload: Dictionary)
signal rename_pressed(index: int)
signal export_pressed(index: int)
signal delete_pressed(index: int)

@onready var _name_label: Label = %Name
@onready var _stamp_button: TextureButton = %Stamp
@onready var _rename_button: TextureButton = %Rename
@onready var _export_button: TextureButton = %Export
@onready var _delete_button: TextureButton = %Delete

var _index: int = -1
var _payload: Dictionary = {}


func _ready() -> void:
	# Row-press → emit `selected`. Nested action buttons consume
	# their clicks first (Button defaults to MOUSE_FILTER_STOP), so
	# pressing Stamp / Rename / Export / Delete doesn't double-fire
	# as a row selection.
	toggled.connect(_on_toggled)


func populate(idx: int, entry: Dictionary) -> void:
	_index = idx
	_payload = entry.get("payload", {})
	_name_label.text = String(entry.get("name", "(unnamed)"))

	_wire_stamp_button()
	_wire_export_button()

	_rename_button.pressed.connect(
			func() -> void: rename_pressed.emit(_index))
	_delete_button.pressed.connect(
			func() -> void: delete_pressed.emit(_index))


func _wire_stamp_button() -> void:
	if _payload.is_empty():
		_stamp_button.disabled = true
		_stamp_button.tooltip_text = (
				"Legacy text-only blueprint — no graph payload to stamp.")
		return
	var locked: Array = BlueprintLoader.locked_paths_in(
			_payload,
			func(p: String) -> bool: return SaveManager.is_hex_unlocked(p))
	if locked.is_empty():
		_stamp_button.pressed.connect(
				func() -> void: stamp_pressed.emit(_payload))
		return
	_stamp_button.disabled = true
	var names: Array[String] = []
	for p in locked:
		names.append(String(p).get_file().get_basename())
	_stamp_button.tooltip_text = (
			"Locked hex types in this blueprint:\n  • "
			+ "\n  • ".join(names))


func _wire_export_button() -> void:
	if _payload.is_empty():
		_export_button.disabled = true
		_export_button.tooltip_text = (
				"Legacy blueprint — nothing to encode.")
		return
	_export_button.tooltip_text = (
			"Copy this blueprint as a hxk1: string.")
	_export_button.pressed.connect(
			func() -> void: export_pressed.emit(_index))


func _on_toggled(_state: bool) -> void:
	# Emit on both press AND un-press: the dialog uses its own
	# `_selected_index` parity to interpret the event (a re-click on
	# the active row is the clean-mouse deselect gesture).
	selected.emit(_index)


# Dialog-driven highlight toggle. Setting `button_pressed` here
# (instead of forwarding to `set_pressed_no_signal` etc.) keeps the
# Button's native pressed StyleBox in sync with the dialog's
# single-selection bookkeeping without re-emitting `toggled`.
func set_selected(state: bool) -> void:
	if button_pressed == state:
		return
	set_pressed_no_signal(state)
