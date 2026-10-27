extends Node
## Top-bar action signal hub. Emits a semantic signal per press so
## the editor can route the action without knowing where the buttons
## physically live in the scene tree.
##
## The buttons are unique-named scene nodes (`unique_name_in_owner`)
## that the new full-width-bar layout distributes across the left and
## right corner panels. This node looks them up by unique name rather
## than as direct children, so moving a button between corners is a
## pure-scene change that never touches this script.

signal help_requested
signal library_requested
signal generate_requested
signal run_requested
signal menu_requested
signal codex_requested
signal copy_text_requested

var run_button: Button = null


func _ready() -> void:
	_connect("%HelpButton", help_requested)
	_connect("%LibraryButton", library_requested)
	_connect("%GenerateButton", generate_requested)
	_connect("%RunButton", run_requested)
	_connect("%MenuButton", menu_requested)
	_connect("%CodexButton", codex_requested)
	run_button = get_node_or_null("%RunButton")


# The run/generate/copy hotkeys live with the buttons they mirror:
# Space → generate text preview, Shift+Space → run/submit,
# Ctrl+Space → copy program text. Re-emitted through the same signals
# the buttons use, so the editor has a single handler per action.
# Modal gating is free: this PAUSABLE node receives no input while a
# dialog is open.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if InputGates.text_input_focused(get_viewport()):
		return
	if event.is_action_pressed("code_copy_text", false, true):
		copy_text_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("code_run", false, true):
		run_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("code_generate_text", false, true):
		generate_requested.emit()
		get_viewport().set_input_as_handled()


# Wire a unique-named button's `pressed` to a re-emit of `sig`.
# Tolerates a missing node (e.g. an optional Codex placeholder that a
# future layout may drop) so the hub never hard-fails on absence.
func _connect(unique_path: String, sig: Signal) -> void:
	var btn: Button = get_node_or_null(unique_path)
	if btn:
		btn.pressed.connect(func() -> void: sig.emit())


# The Run button's tooltip flips between "free run" and "submit
# against selected job" copy. Editor pushes the current tooltip
# down via this setter rather than reaching into the node directly.
func set_run_tooltip(text: String) -> void:
	if run_button:
		run_button.tooltip_text = text


# Disabled while a background check is in flight so the player can't
# stack submissions; re-enabled from the submit_completed handler.
func set_run_enabled(enabled: bool) -> void:
	if run_button:
		run_button.disabled = not enabled
