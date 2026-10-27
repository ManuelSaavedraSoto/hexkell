extends FoldableContainer
## Output panel — generated text preview + run/submit log. The
## `FoldableContainer` itself IS the panel: it carries the
## right-edge anchors, owns the title bar (used as the folded-state
## last-line preview), and inherits the theme's transparent panel
## stylebox so the canvas behind shows through when folded.
##
## Inside the container the player flips between two views (Log /
## generated Text) via the TabSwitcher. The editor pushes text in
## through the standard sink API (`set_generated_text`,
## `append_output`, `clear_output`). The folded-state title shows
## the *outcome* of the last run/submit (`set_status`) rather than
## whatever log line happened to print last — verdicts and results
## survive the renown/unlock lines that follow them. Plain
## `append_output` lines only title the strip while no status is
## active. A hex-unlock notice (`notify_unlock`) cycles with the
## status on a timer and pulses the title gold until the player
## unfolds the panel to look.

const FALLBACK_TITLE := "Output"
const TITLE_MAX_CHARS := 80
const UNLOCK_CYCLE_SECS := 3.0
const UNLOCK_PULSE_COLOR := Color(1.0, 0.85, 0.42)
const SOLVE_COLOR := Color("15cb67")
const ERROR_COLOR := Color("dc0724")

@onready var generated_text: TextEdit = $OutputMargin/OutputBody/GeneratedText
@onready var output_label: RichTextLabel = $OutputMargin/OutputBody/OutputLabel

@onready var _tab_switcher: HBoxContainer = $OutputMargin/OutputBody/TabSwitcher
@onready var _log_tab: Button = $OutputMargin/OutputBody/TabSwitcher/LogTabButton
@onready var _text_tab: Button = $OutputMargin/OutputBody/TabSwitcher/TextTabButton

var _current_view: String = "log"
var _last_output_line: String = ""

# Outcome of the last run/submit. `_status_kind` is one of
# result / pass / fail / error / warning / pending — kept for
# future per-kind styling; only the text reaches the title today.
var _status_kind: String = ""
var _status_text: String = ""

# Transient unlock notice: alternates with the status text on
# `_cycle_timer` and pulses the title color until dismissed
# (unfold, next status, or clear).
var _unlock_text: String = ""
var _cycle_showing_unlock := false
var _cycle_timer: Timer
var _pulse_tween: Tween

# Outcome highlight on the title bar: "" / "solve" (green) / "error" (red).
# Persists until the panel is unfolded (the dismiss path clears it).
var _outcome: String = ""


func _ready() -> void:
	_log_tab.pressed.connect(func(): set_view("log"))
	_text_tab.pressed.connect(func(): set_view("text"))
	_cycle_timer = Timer.new()
	_cycle_timer.wait_time = UNLOCK_CYCLE_SECS
	_cycle_timer.one_shot = false
	_cycle_timer.timeout.connect(_on_unlock_cycle_timeout)
	add_child(_cycle_timer)
	_apply_view()
	_refresh_title()


# ── Editor-facing API ──────────────────────────────────────────────────────

func set_generated_text(text: String) -> void:
	if generated_text and generated_text.text != text:
		generated_text.text = text


func append_output(line: String) -> void:
	if output_label:
		output_label.append_text(line + "\n")
	_last_output_line = line
	_refresh_title()


func clear_output() -> void:
	if output_label:
		output_label.clear()
	_last_output_line = ""
	_status_kind = ""
	_status_text = ""
	_outcome = ""
	_dismiss_unlock_notice()
	_refresh_title()


## Record the outcome of the last run/submit. Owns the folded-state
## title until the next status or `clear_output`; informational
## `append_output` lines can no longer bury it.
func set_status(kind: String, text: String) -> void:
	_status_kind = kind
	_status_text = text
	_dismiss_unlock_notice()
	# A solved job pulses the title green; an error or wrong answer pulses red;
	# any other outcome (pending / result / warning) clears the highlight.
	if kind == "pass":
		_outcome = "solve"
	elif kind == "error" or kind == "fail":
		_outcome = "error"
	else:
		_outcome = ""
	_refresh_pulse()
	_refresh_title()


## Announce newly unlocked hexes: the title alternates between the
## current status and `text` every few seconds, pulsing gold, until
## the player unfolds the panel (or the next status arrives).
func notify_unlock(text: String) -> void:
	_unlock_text = text
	_cycle_showing_unlock = true
	_cycle_timer.start()
	_refresh_pulse()
	_refresh_title()


# O — the panel owns its own fold hotkey (action-based). Modal gating
# is free: this PAUSABLE node receives no input while a dialog is open.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("hex_toggle_output", false, true) \
			and not InputGates.text_input_focused(get_viewport()):
		toggle_log_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hex_toggle_text", false, true) \
			and not InputGates.text_input_focused(get_viewport()):
		toggle_text_view()
		get_viewport().set_input_as_handled()


# T — open the output box straight to the generated-text view, or close
# it if it's already open on that view. From the log view, switch to
# text without closing.
func toggle_text_view() -> void:
	_toggle_view("text")


# O — same gesture as T, but for the log view.
func toggle_log_view() -> void:
	_toggle_view("log")


# Open the box on `name`; close it if already open on `name`; from the
# other view, switch to `name` without closing.
func _toggle_view(name: String) -> void:
	if is_folded():
		set_view(name)
		expand()
	elif _current_view == name:
		fold()
	else:
		set_view(name)


func set_view(name: String) -> void:
	if name != "log" and name != "text":
		return
	_current_view = name
	_apply_view()


# ── State application ──────────────────────────────────────────────────────

func _apply_view() -> void:
	_log_tab.button_pressed = _current_view == "log"
	_text_tab.button_pressed = _current_view == "text"
	output_label.visible = _current_view == "log"
	generated_text.visible = _current_view == "text"


func _refresh_title() -> void:
	var source := ""
	if _cycle_showing_unlock and not _unlock_text.is_empty():
		source = _unlock_text
	elif not _status_text.is_empty():
		source = _status_text
	else:
		source = _last_output_line
	if source.is_empty():
		title = FALLBACK_TITLE
		return
	# FoldableContainer's title is a plain-text Label; BBCode tags in
	# log lines would render as literal text.
	var plain := TextUtils.strip_bbcode(source)
	if plain.length() > TITLE_MAX_CHARS:
		plain = plain.left(TITLE_MAX_CHARS - 1) + "…"
	title = plain


# ── Unlock notice cycling + pulse ──────────────────────────────────────────

func _on_unlock_cycle_timeout() -> void:
	_cycle_showing_unlock = not _cycle_showing_unlock
	_refresh_title()


func _on_folding_changed(_is_folded: bool) -> void:
	# Unfolding means the player looked — the notice did its job.
	if not is_folded():
		_dismiss_unlock_notice()
		_refresh_title()


func _dismiss_unlock_notice() -> void:
	_unlock_text = ""
	_cycle_showing_unlock = false
	if _cycle_timer:
		_cycle_timer.stop()
	_outcome = ""
	_stop_pulse()


# Decide the title pulse from the current outcome + unlock state and
# (re)start it. Priority: a solve that also unlocked hexes pulses green↔gold;
# a plain solve pulses green; an error pulses red; a legacy unlock-only notice
# pulses gold; otherwise no pulse.
func _refresh_pulse() -> void:
	var base := get_theme_color("collapsed_font_color")
	var has_unlock := _cycle_showing_unlock or not _unlock_text.is_empty()
	if _outcome == "solve" and has_unlock:
		_start_pulse(SOLVE_COLOR, UNLOCK_PULSE_COLOR)
	elif _outcome == "solve":
		_start_pulse(base, SOLVE_COLOR)
	elif _outcome == "error":
		_start_pulse(base, ERROR_COLOR)
	elif has_unlock:
		_start_pulse(base, UNLOCK_PULSE_COLOR)
	else:
		_stop_pulse()


func _start_pulse(a: Color, b: Color) -> void:
	_stop_pulse()
	# A tweened theme-color override gives the attention pulse
	# without a per-control shader. `collapsed_font_color` paints
	# the folded title (the state the notice targets); `font_color`
	# covers the brief unfolded frame before dismissal lands.
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(_set_title_color, a, b, 0.6)
	_pulse_tween.tween_method(_set_title_color, b, a, 0.6)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	remove_theme_color_override("font_color")
	remove_theme_color_override("collapsed_font_color")


func _set_title_color(color: Color) -> void:
	add_theme_color_override("font_color", color)
	add_theme_color_override("collapsed_font_color", color)
