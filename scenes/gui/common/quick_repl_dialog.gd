extends Control
## Centered, modal "quick search"-style REPL.
##
## Opens via a keybinding from the editor. Lets the user type a one-shot
## expression, evaluates it against the editor's live environment (so
## anything the editor has defined is visible), and shows the result inline
## without disturbing the code in the editor.
##
## Closes on Escape, click-outside, or the ✕ button.

signal expression_evaluated(input: String)

@onready var backdrop: ColorRect = %Backdrop
@onready var repl_input: LineEdit = %ReplInput
@onready var close_button: Button = %CloseButton
@onready var result_label: RichTextLabel = %ResultLabel

## Environment used when interpreting expressions. The editor injects the
## live environment so top-level definitions written in the editor are
## reachable from the REPL.
var environment: Env = null

var _history: Array[String] = []
var _history_index: int = -1


func _ready() -> void:
	# Make the dialog overlay the whole viewport regardless of where it's
	# instantiated in the tree.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	repl_input.text_submitted.connect(_on_submitted)
	repl_input.gui_input.connect(_on_input_key_event)
	close_button.pressed.connect(close)
	backdrop.gui_input.connect(_on_backdrop_input)


# ── Public API ──────────────────────────────────────────────────────────────

func open(env: Env) -> void:
	environment = env
	visible = true
	repl_input.text = ""
	result_label.text = ""
	_history_index = -1
	repl_input.grab_focus()


func close() -> void:
	visible = false
	# Don't leak focus into hidden controls.
	repl_input.release_focus()


# ── Input handling ──────────────────────────────────────────────────────────

func _on_backdrop_input(event: InputEvent) -> void:
	# Click anywhere on the dim backdrop to dismiss.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _on_input_key_event(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close()
		accept_event()
	elif event.keycode == KEY_UP:
		_navigate_history(-1)
		accept_event()
	elif event.keycode == KEY_DOWN:
		_navigate_history(1)
		accept_event()


func _navigate_history(direction: int) -> void:
	if _history.is_empty():
		return
	_history_index += direction
	_history_index = clampi(_history_index, 0, _history.size())
	if _history_index < _history.size():
		repl_input.text = _history[_history.size() - 1 - _history_index]
		repl_input.caret_column = repl_input.text.length()
	else:
		repl_input.text = ""


# ── Evaluation ──────────────────────────────────────────────────────────────

func _on_submitted(text: String) -> void:
	var src: String = text.strip_edges()
	if src.is_empty():
		return

	_history.append(src)
	_history_index = -1
	expression_evaluated.emit(src)

	if environment == null:
		_show_error("REPL has no environment — open it from the editor.")
		return

	var expr: Expr = Parser.parse_expr(src)
	if expr == null:
		_show_error("Parse error")
		return

	var result: Value = expr.interpret(environment)
	if result == null:
		_show_error("Runtime error (check console)")
		return
	result = result.force()
	if result == null:
		_show_error("Runtime error (check console)")
		return

	result_label.text = "[color=#86e08a]= %s[/color]" % _value_to_string(result)
	repl_input.select_all()


func _show_error(message: String) -> void:
	result_label.text = "[color=#ff7777]%s[/color]" % message


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
