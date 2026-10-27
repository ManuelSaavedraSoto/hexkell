extends FoldableContainer
## Jobs panel — wraps the job list + selected-job header. The
## `FoldableContainer` itself is the panel: it carries the anchors,
## owns the title bar (used as the folded-state job name), and
## exposes its `tooltip_text` (= the job description) over the
## title-bar area. No wrapping `PanelContainer` needed — the
## container's own panel stylebox handles the visual chrome.
##
## When folded, the body collapses into the layout's minimum size
## and the empty body region passes mouse events through to the
## canvas below (via `mouse_filter = PASS` on the container).

signal job_toggled(id: String)

const FALLBACK_TITLE := "No job selected"
const TOOLTIP_MAX_WIDTH := 320
const SOLVE_COLOR := Color("15cb67")


# Job-card button that renders its (already BBCode-stripped) tooltip in a
# wrapping panel instead of Godot's single-line default. Reaches the
# shared builder via a self-preload (the enclosing script has no
# class_name, and an inner class can't see the outer scope directly).
class _JobCard extends Button:
	var job_id: String
	func _make_custom_tooltip(text: String) -> Object:
		var self_script := preload("res://scenes/gui/hex_editor/ui/jobs_panel.gd")
		return self_script._build_wrapped_tooltip(text)


# Build a wrapping, plain-text tooltip panel (mirrors HexToolbarButton's
# custom tooltip). `text` is expected already stripped of BBCode.
static func _build_wrapped_tooltip(text: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.97)
	sb.border_color = Color(0.40, 0.50, 0.65, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.82, 0.87, 0.95))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(TOOLTIP_MAX_WIDTH, 0)
	panel.add_child(lbl)
	return panel


# Title-bar tooltip (the folded-state job description) — wrap it too.
func _make_custom_tooltip(text: String) -> Object:
	if text.is_empty():
		return null
	return _build_wrapped_tooltip(text)

# Renown lives in the top bar's left corner; resolved by unique name.
@onready var renown_label: Label = get_node_or_null("%RenownLabel")
@onready var jobs_list: VBoxContainer = $JobsMargin/JobsBody/JobsScroll/JobsList
@onready var jobs_scroll: ScrollContainer = $JobsMargin/JobsBody/JobsScroll
@onready var list_divider: HSeparator = $JobsMargin/JobsBody/ListDivider
@onready var job_header_node: VBoxContainer = $JobsMargin/JobsBody/TopLabels
@onready var job_description_label: RichTextLabel = $JobsMargin/JobsBody/TopLabels/JobDescriptionLabel

var _selected_name: String = ""
var _selected_description: String = ""

# "Solved" highlight: the title bar pulses green after the selected job is
# completed, until the player moves to a different job.
var _solved := false
var _pulse_tween: Tween


func _ready() -> void:
	_refresh_title()


func set_renown(amount: int) -> void:
	if renown_label:
		renown_label.text = "Renown: %d" % amount


# Editor-driven selection state: title = job name; tooltip =
# description (shown when hovering the FoldableContainer's title
# bar, including in the folded state). Pass `""` for the
# "no job" case.
func set_selected_job(name: String, description: String) -> void:
	# Moving to a different job ends the solved-green highlight; re-selecting
	# the same job (the post-solve refresh) keeps it.
	if _solved and name != _selected_name:
		_clear_solved()
	_selected_name = name
	_selected_description = description
	_refresh_title()


# Pulse the title bar green to celebrate solving the selected job. Held until
# the player moves to another job (see set_selected_job).
func flag_solved() -> void:
	_solved = true
	_start_pulse(get_theme_color("collapsed_font_color"), SOLVE_COLOR)


func _clear_solved() -> void:
	_solved = false
	_stop_pulse()


func _start_pulse(a: Color, b: Color) -> void:
	_stop_pulse()
	# Tweened theme-color override — same mechanism as the output panel.
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


# Ctrl+F's handler — toggles the FoldableContainer's `folded`. The
# `folded` setter is silent (only title-bar clicks emit
# `folding_changed`), so mirror it manually — otherwise listeners like
# the tutorial's "open the Jobs panel" step never see the Ctrl+F open.
func toggle_fold() -> void:
	folded = not folded
	folding_changed.emit(folded)


# The panel owns its hotkeys: F / Shift+F cycle pending jobs (the
# selection model lives on the ChapterManager autoload), Ctrl+F flips
# list/description view. Modal gating is free: this PAUSABLE node
# receives no input while a dialog is open.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if InputGates.text_input_focused(get_viewport()):
		return
	if event.is_action_pressed("jobs_toggle_view", false, true):
		toggle_fold()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jobs_cycle_next", false, true):
		ChapterManager.cycle_pending_jobs(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jobs_cycle_prev", false, true):
		ChapterManager.cycle_pending_jobs(-1)
		get_viewport().set_input_as_handled()


# Rebuild the panel's job list. The editor calls this whenever any
# state the list shows could have changed (selection toggled, job
# solved, renown awarded, palette unlock cascade).
func refresh(selected_id: String) -> void:
	if jobs_list == null:
		return
	for c in jobs_list.get_children():
		c.queue_free()
	var all_jobs: Dictionary = TemplateManager.get_all_jobs()
	var ids: Array = TemplateManager.get_job_ids_sorted()
	var available: Array = []
	var locked: Array = []
	var done: Array = []
	for id in ids:
		if SaveManager.is_job_solved(id):
			done.append(id)
		elif ChapterManager.is_job_available(id):
			available.append(id)
		else:
			locked.append(id)
	if not available.is_empty():
		jobs_list.add_child(_section_header("Pending", Color(0.8, 0.95, 1, 1)))
		for id in available:
			jobs_list.add_child(_build_card(id, all_jobs[id], "pending", selected_id))
	if not done.is_empty():
		jobs_list.add_child(_section_header("Completed", Color(0.6, 1.0, 0.7, 1)))
		for id in done:
			jobs_list.add_child(_build_card(id, all_jobs[id], "done", selected_id))
	if not locked.is_empty():
		jobs_list.add_child(_section_header("Locked (finish earlier jobs first)", Color(0.7, 0.7, 0.75, 1)))
		for id in locked:
			jobs_list.add_child(_build_card(id, all_jobs[id], "locked", selected_id))
	if available.is_empty() and done.is_empty() and locked.is_empty():
		var empty := Label.new()
		empty.text = "(no jobs defined)"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		jobs_list.add_child(empty)


# Move the selected-card highlight without rebuilding the list. A
# selection toggle never changes the pending/done/locked buckets, so the
# full refresh() is reserved for solve/renown/unlock changes. Cards
# connect `pressed` (user interaction only), not `toggled`, and there's
# no ButtonGroup, so set_pressed_no_signal can't re-emit job_toggled.
func set_selected(selected_id: String) -> void:
	if jobs_list == null:
		return
	for c in jobs_list.get_children():
		if c is _JobCard:
			(c as _JobCard).set_pressed_no_signal(c.job_id == selected_id)


func _refresh_title() -> void:
	title = _selected_name if not _selected_name.is_empty() else FALLBACK_TITLE
	# Tooltips are plain text — the description's BBCode (bold, hex
	# icons) would render verbatim.
	tooltip_text = TextUtils.strip_bbcode(_selected_description)


# ── List rendering ────────────────────────────────────────────────────────

func _section_header(title: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 11)
	return lbl


func _build_card(id: String, job: Dictionary, state: String, selected_id: String) -> Control:
	var btn := _JobCard.new()
	btn.job_id = id
	btn.toggle_mode = (state != "locked")
	btn.disabled = (state == "locked")
	btn.button_pressed = (id == selected_id)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	var prefix := ""
	match state:
		"pending": prefix = "● "
		"done": prefix = "✓ "
		"locked": prefix = "🔒 "
	btn.text = "%s%s" % [prefix, String(job.get("name", id))]
	var lines: Array[String] = []
	var reward: int = int(job.get("renown_reward", 0))
	if reward > 0:
		lines.append("Reward: +%d renown" % reward)
	if state == "locked":
		lines.append("Locked — finish the earlier jobs first.")
	lines.append(TextUtils.strip_bbcode(String(job.get("description", ""))))
	if job.has("variables"):
		lines.append("")
		lines.append("Inputs: %s" % str(job["variables"]))
	if state == "done":
		var snap: String = String(SaveManager.get_solved_jobs().get(id, {}).get("submitted_text", ""))
		if not snap.is_empty():
			lines.append("")
			lines.append("Your solution:")
			lines.append(snap)
	btn.tooltip_text = "\n".join(lines)
	if state != "locked":
		btn.pressed.connect(func() -> void: job_toggled.emit(id))
	return btn
