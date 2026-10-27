extends Node
## Chapter-0 tutorial director. A strict finite state machine: each
## step names ONE expected event (plus an optional payload check); the
## editor's statically-declared signals funnel into `_on_event`, and
## only the current step's event advances the FSM. Hard gating — the
## `allows_*` queries below — keeps the player from acting out of
## order at the five choke points (category select, hex pick, hex
## placement, job select, run).
##
## Lifecycle: this autoload reads `SaveManager.has_completed_tutorial()`
## at boot; the hex editor calls `attach(self)` at the end of its
## `_ready`. While the flag is set the manager is fully dormant. The
## settings menu's "Replay tutorial" clears the flag and calls
## `reset()` — the tutorial then re-runs on the next editor entry.

const TUTORIAL_JOB_ID := "job_01_any_number"
const TUTORIAL_CHAPTER_ID := "chapter_0_tutorial"
const INT_HEX_PATH := "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd"
const INTEGER_CATEGORY_IDX := 0
# Deliberately NOT adjacent to the DoHex at (0,0): adjacent hexes
# auto-connect, which would skip the wiring step entirely.
const TARGET_AXIAL := Vector2i(3, 0)
# Three cells NE of the Do hex (0,0) — the lock-hint ring for the bend step.
const LOCK_HINT_AXIAL := Vector2i(3, -3)
const KB_PAN_GOAL := 300.0     # world-px of WASD travel for step 1
const MOUSE_PAN_GOAL := 200.0  # world-px of MMB-drag travel for step 2
const CONGRATS_DELAY_SECONDS := 1.5

# `active`: the tutorial still needs to run sometime this session.
# `running`: attached to a live editor with steps in flight.
var active := false
var running := false

var _editor: Node = null
var _hud: TutorialHud = null
var _marker: TutorialTileMarker = null
var _steps: Array[Dictionary] = []
var _step_idx := -1
var _kb_pan_accum := 0.0
var _mouse_pan_accum := 0.0
var _placed_hex: Node2D = null
# Set when the player presses C (locks a chain point) during the bend step.
var _used_chain_lock := false


func _ready() -> void:
	active = not SaveManager.has_completed_tutorial()
	_steps = _build_steps()


# Settings-menu hook: re-arm after the save flag was cleared (or
# disarm if it was just set). Takes effect on the next editor entry.
func reset() -> void:
	active = not SaveManager.has_completed_tutorial()
	_step_idx = -1
	_kb_pan_accum = 0.0
	_mouse_pan_accum = 0.0
	_placed_hex = null
	_used_chain_lock = false


# ── Editor attachment ───────────────────────────────────────────────────────

func attach(editor: Node) -> void:
	if not active or running:
		return
	_editor = editor
	editor.tree_exiting.connect(_on_editor_exiting)

	# Scripted placement/wiring needs a predictable board: if the
	# current tab already has content (replay on a veteran save),
	# move to a fresh "Tutorial" tab.
	editor.ensure_fresh_tutorial_tab()

	# Funnel every progress signal into the single `_on_event` entry
	# point. All of these are statically declared on their nodes.
	var cam = editor.hex_camera
	cam.panned_keyboard.connect(func(d: Vector2): _on_event(&"kb_pan", d))
	cam.panned_mouse.connect(func(d: Vector2): _on_event(&"mouse_pan", d))
	cam.zoomed.connect(func(z: float): _on_event(&"zoom", z))
	editor.jobs_panel.folding_changed.connect(
			func(is_folded: bool): _on_event(&"jobs_fold", is_folded))
	# ChapterManager outlives the editor (autoload) — guard against
	# double-connecting across tutorial replays.
	if not ChapterManager.job_selection_changed.is_connected(_on_cm_job_selected):
		ChapterManager.job_selection_changed.connect(_on_cm_job_selected)
	editor.palette_bar.category_selected.connect(func(idx: int): _on_event(&"category", idx))
	editor.palette_bar.hex_selected.connect(func(s): _on_event(&"hex_pick", s))
	editor.hex_placed.connect(_on_hex_placed)
	editor.hex_deleted.connect(_on_hex_deleted)
	editor.blueprint_mode_exited.connect(func(): _on_event(&"blueprint_exit"))
	editor.config_opened.connect(func(node): _on_event(&"config_opened", node))
	editor.config_closed.connect(func(): _on_event(&"config_closed"))
	editor.wire_committed.connect(func(wire): _on_event(&"wire", wire))
	editor.wire_deleted.connect(func(wire): _on_event(&"wire_deleted", wire))
	editor.wire_locked.connect(_on_wire_locked)
	editor.tab_cleared.connect(func(): _on_event(&"board_cleared"))
	if not ChapterManager.job_solved.is_connected(_on_cm_job_solved):
		ChapterManager.job_solved.connect(_on_cm_job_solved)

	_hud = TutorialHud.new()
	editor.add_child(_hud)
	_marker = TutorialTileMarker.new()
	editor.world.add_child(_marker)

	running = true
	_step_idx = -1

	# Step 1 starts once the chapter-0 intro closes. The editor only
	# auto-pops that intro when NO intro has ever been seen (fresh
	# save); in every other arrangement (replay on an old save) start
	# immediately.
	if SaveManager.get_seen_chapter_intros().is_empty():
		editor._chapter_intro_dialog.chapter_closed.connect(
				func(_id: String): _begin(), CONNECT_ONE_SHOT)
	else:
		_begin()


func _on_editor_exiting() -> void:
	# HUD + marker die with the editor (they're its children); just
	# drop refs. `active` is untouched, so an unfinished tutorial
	# restarts on the next editor entry.
	_editor = null
	_hud = null
	_marker = null
	running = false
	_step_idx = -1


# ── FSM core ────────────────────────────────────────────────────────────────

func _begin() -> void:
	_kb_pan_accum = 0.0
	_mouse_pan_accum = 0.0
	_placed_hex = null
	_used_chain_lock = false
	_step_idx = 0
	_enter_step()


# The single FSM entry point: every tracked signal lands here. Only
# the current step's `event` (or `alt_event`) moves the machine.
func _on_event(kind: StringName, payload: Variant = null) -> void:
	if not running or _step_idx < 0 or _step_idx >= _steps.size():
		return
	var step: Dictionary = _steps[_step_idx]
	if kind == step.get("alt_event", &""):
		_advance()
		return
	if kind != step.get("event", &""):
		return
	var check: Variant = step.get("check")
	if check is Callable and not (check as Callable).call(payload):
		return
	_advance()


func _advance() -> void:
	_step_idx += 1
	if _step_idx >= _steps.size():
		_finish_steps()
		return
	_enter_step()


func _enter_step() -> void:
	var step: Dictionary = _steps[_step_idx]
	# A step whose completion condition is already met is skipped before
	# it ever shows — e.g. the player closed the config in the same Enter
	# press that set the value, so `config_closed` landed before the FSM
	# reached `close_config`. Safe to recurse: a true `skip_if` advances
	# and returns, so this call sets no marker/HUD/highlight.
	var skip_if: Variant = step.get("skip_if")
	if skip_if is Callable and (skip_if as Callable).call():
		_advance()
		return
	if _marker:
		_marker.clear()
	if _hud:
		_hud.highlight_rect.clear()
		_hud.show_step(String(step.get("text", "")), _step_idx + 1, _steps.size())
	if _editor == null:
		return
	var on_enter: Variant = step.get("on_enter")
	if on_enter is Callable:
		(on_enter as Callable).call()
	var hl: Variant = step.get("highlight")
	if hl is Callable and _hud != null:
		_hud.highlight_rect.highlight(hl as Callable)


# ── Step table ──────────────────────────────────────────────────────────────
#
# Each step: id, HUD text, the ONE event that completes it (+ optional
# payload `check` and `alt_event` escape hatch), the gated-action
# tokens it allows (see allows_*), and optional on_enter / highlight
# hooks. Hooks are method Callables so highlight targets re-resolve
# lazily and never go stale when the UI rebuilds.

# Inline-icon helpers for the HUD's RichTextLabel (bbcode). Each
# returns an `[img]` tag sized to sit on the text baseline.
func _kbd(letter: String) -> String:
	return "[img valign=center, width=24]res://assets/icons/input/keyboard/letters/%s.tres[/img]" % letter

func _special(name: String) -> String:
	# The Ctrl key art is wide — at the standard 24px it shrinks too
	# short to read, so render it at double width.
	var w := 48 if name == "control" else 24
	return "[img valign=center, width=%d]res://assets/icons/input/keyboard/special/%s.tres[/img]" % [w, name]

func _mouse(name: String) -> String:
	return "[img valign=center, width=24]res://assets/icons/input/mouse/%s.tres[/img]" % name


func _build_steps() -> Array[Dictionary]:
	return [
		{
			"id": &"move_camera_wasd",
			"text": "Welcome to the workshop!\nMove the camera with " \
					+ _kbd("w") + _kbd("a") + _kbd("s") + _kbd("d") + ".",
			"event": &"kb_pan",
			"check": _check_kb_pan,
		},
		{
			"id": &"pan_zoom_mouse",
			"text": "The mouse works too: hold the " + _mouse("middle_mb") \
					+ " [b]middle button[/b] and drag to pan, or " \
					+ _mouse("scroll_wheel") + " [b]scroll[/b] to zoom.",
			"event": &"mouse_pan",
			"check": _check_mouse_pan,
			"alt_event": &"zoom",
		},
		{
			"id": &"open_jobs_panel",
			"text": "Clients post work in the [b]Jobs[/b] panel. Click its " \
					+ "title bar — or press " + _special("control") + _kbd("f") \
					+ " — to unfold it.",
			"event": &"jobs_fold",
			"check": _check_unfolded,
			"highlight": _hl_jobs_panel,
		},
		{
			"id": &"select_job",
			"text": "Select the job [b]Pick a number[/b] — click it, or cycle " \
					+ "with " + _kbd("f") + ".",
			"event": &"job_selected",
			"check": _check_tutorial_job,
			"allowed": [&"select_job"],
			"highlight": _hl_jobs_panel,
		},
		{
			"id": &"select_category",
			"text": "Hexes live in the palette at the bottom. Click the " \
					+ "[b]Integer[/b] category to open its shelf.",
			"event": &"category",
			"check": _check_integer_category,
			"allowed": [&"palette_category"],
			"on_enter": _deselect_palette,
			"highlight": _hl_category_button,
		},
		{
			"id": &"select_int_hex",
			"text": "Pick the [b]Int[/b] hex — a number literal.",
			"event": &"hex_pick",
			"check": _check_int_hex_pick,
			"allowed": [&"palette_pick"],
			"highlight": _hl_int_hex_button,
		},
		{
			"id": &"place_hex",
			"text": "Place it on the highlighted tile with " + _mouse("left_mb") \
					+ ". (" + _kbd("r") + " rotates the stamp.)",
			"event": &"hex_placed",
			"check": _check_placed_on_target,
			# palette_pick stays allowed so a player who cancels the
			# stamp mid-step can grab the Int hex again (no softlock).
			"allowed": [&"palette_pick"],
			"on_enter": _mark_target_tile,
		},
		{
			"id": &"exit_stamp_mode",
			"text": "The stamp stays on your cursor for repeat placement. Press " \
					+ _mouse("right_mb") + " to put it away.",
			"event": &"blueprint_exit",
		},
		{
			"id": &"open_config",
			"text": "Click the placed [b]Int[/b] hex with " + _mouse("left_mb") \
					+ " to open its config panel.",
			"event": &"config_opened",
			"check": _check_config_on_placed,
		},
		{
			"id": &"set_value",
			"text": "Set the value — [b]6[/b] is a fine number. (Type it in the " \
					+ "panel, or " + _mouse("scroll_wheel") + " scroll over the hex.)",
			"event": &"value_changed",
		},
		{
			"id": &"close_config",
			"text": "Press " + _mouse("right_mb") + " (or " + _special("enter") \
					+ ") to close the config panel.",
			"event": &"config_closed",
			# Enter can set the value AND close the panel in one press; if
			# the panel's already gone, there's nothing left to close.
			"skip_if": _config_already_closed,
		},
		{
			"id": &"wire_to_do",
			"text": "Now wire it up: click the hex's glowing [b]output edge[/b] " \
					+ "and drag the wire onto the [b]Do[/b] hex, then release.",
			"event": &"wire",
			"check": _check_wire_to_do,
			"on_enter": _mark_wire_endpoints,
		},
		{
			"id": &"delete_wire",
			"text": "Changed your mind? " + _mouse("right_mb") \
					+ " deletes whatever it's over — a [b]wire[/b] or a [b]hex[/b]. " \
					+ "Right-click the [b]wire[/b] to remove it.",
			"event": &"wire_deleted",
			"check": _check_wire_deleted,
			"on_enter": _mark_wire_endpoints,
		},
		{
			"id": &"route_locked_bend",
			"text": "Wire it again, but make it [b]bend[/b]: while dragging, press " \
					+ _kbd("c") + " to lock a corner so the wire keeps the bend " \
					+ "instead of snapping straight — then drop it on the [b]Do[/b] hex.",
			"event": &"wire",
			"check": _check_wire_bend_lock,
			"on_enter": _mark_lock_hint,
		},
		{
			"id": &"run_job",
			"text": "Everything's in place — hit [b]Run[/b] to submit the job!",
			"event": &"job_solved",
			"check": _check_tutorial_job,
			"allowed": [&"run"],
			"highlight": _hl_run_button,
		},
		{
			"id": &"clear_board",
			"text": "One last tool — the [b]Clear[/b] (trash) button wipes the " \
					+ "workspace. Give it a click (or " + _special("control") \
					+ _kbd("d") + ").",
			"event": &"board_cleared",
			"highlight": _hl_clear_button,
		},
	]


# ── Step checks ─────────────────────────────────────────────────────────────

func _check_kb_pan(delta: Vector2) -> bool:
	_kb_pan_accum += delta.length()
	return _kb_pan_accum >= KB_PAN_GOAL


func _check_mouse_pan(delta: Vector2) -> bool:
	_mouse_pan_accum += delta.length()
	return _mouse_pan_accum >= MOUSE_PAN_GOAL


func _check_unfolded(is_folded: bool) -> bool:
	return not is_folded


func _check_tutorial_job(id: String) -> bool:
	return id == TUTORIAL_JOB_ID


func _check_integer_category(idx: int) -> bool:
	return idx == INTEGER_CATEGORY_IDX


func _check_int_hex_pick(script: Variant) -> bool:
	return script != null and script.resource_path == INT_HEX_PATH


func _check_placed_on_target(payload: Dictionary) -> bool:
	if payload.get("axial") != TARGET_AXIAL:
		return false
	_placed_hex = payload.get("node")
	# Step 9's value_changed event lives on the hex itself — it only
	# exists from this moment on.
	if _placed_hex and not _placed_hex.config_value_changed.is_connected(_on_value_changed):
		_placed_hex.config_value_changed.connect(_on_value_changed)
	return true


func _check_config_on_placed(node: Variant) -> bool:
	return node == _placed_hex


func _check_wire_to_do(wire: Variant) -> bool:
	if wire == null or wire.is_open or _editor == null:
		return false
	var ends := [wire.output_node, wire.input_node]
	return _placed_hex in ends and _editor.do_node in ends


# The only wire on the tutorial board is the placed-hex → Do wire, so any
# delete that touches the placed hex clears the delete-wire step.
func _check_wire_deleted(wire: Variant) -> bool:
	return wire != null and _placed_hex in [wire.output_node, wire.input_node]


# Re-wire that reconnects hex ↔ Do AND was bent with a chain lock. The lock is
# tracked by `_used_chain_lock` (set on the C-press) rather than read off the
# committed wire — lock state lives on the transient active wire while routing.
func _check_wire_bend_lock(wire: Variant) -> bool:
	if wire == null or wire.is_open or _editor == null:
		return false
	var ends := [wire.output_node, wire.input_node]
	return _placed_hex in ends and _editor.do_node in ends and _used_chain_lock


# The player pressed C to pin a chain point while wiring — remember it so the
# bend step accepts the next hex → Do connection.
func _on_wire_locked() -> void:
	if running:
		_used_chain_lock = true


func _on_hex_placed(node: Node2D, axial: Vector2i) -> void:
	_on_event(&"hex_placed", {"node": node, "axial": axial})


# The placed Int hex was torn out (X / right-click / clear). Roll the FSM
# back to the place step so the player can pick + drop a new one —
# `place_hex` re-marks the target and already allows `palette_pick`.
func _on_hex_deleted(node) -> void:
	if not running or _placed_hex == null or node != _placed_hex:
		return
	# The clear-board step deletes the placed hex on purpose — don't treat that
	# as an accidental loss and revert to the place step.
	if _current_step_id() == &"clear_board":
		return
	_placed_hex = null
	var idx := _step_index(&"place_hex")
	if idx >= 0:
		_step_idx = idx
		_enter_step()


func _current_step_id() -> StringName:
	if _step_idx < 0 or _step_idx >= _steps.size():
		return &""
	return _steps[_step_idx].get("id", &"")


func _step_index(id: StringName) -> int:
	for i in _steps.size():
		if _steps[i].get("id", &"") == id:
			return i
	return -1


func _on_cm_job_selected(id: String) -> void:
	_on_event(&"job_selected", id)


func _on_cm_job_solved(id: String) -> void:
	_on_event(&"job_solved", id)


func _on_value_changed(node: Variant) -> void:
	if node == _placed_hex and node.get("value") != 0:
		_on_event(&"value_changed", node)


# `skip_if` for the close_config step. Null-editor safe so the headless
# FSM tests (which run without an editor) never auto-skip.
func _config_already_closed() -> bool:
	return _editor != null and not _editor.is_config_open()


# ── on_enter hooks + highlight getters ──────────────────────────────────────

func _deselect_palette() -> void:
	_editor.palette_bar.select_category(-1)


func _mark_target_tile() -> void:
	if _marker:
		_marker.set_target_tile(
				HexMath.axial_to_world(TARGET_AXIAL, HexNode.HEX_SIZE))


func _mark_wire_endpoints() -> void:
	if _marker and _placed_hex and _editor:
		var points: Array[Vector2] = [
			_placed_hex.slot_world_position(0),
			_editor.do_node.position,
		]
		_marker.set_edge_points(points)


# Bend step: only locks made from here on count, and ring the cell three
# cells NE of the Do hex so the player sees where to pin the corner.
func _mark_lock_hint() -> void:
	_used_chain_lock = false
	if _marker:
		_marker.set_target_tile(
				HexMath.axial_to_world(LOCK_HINT_AXIAL, HexNode.HEX_SIZE))


func _hl_jobs_panel() -> Control:
	return _editor.jobs_panel


func _hl_category_button() -> Control:
	return _editor.palette_bar.get_category_button(INTEGER_CATEGORY_IDX)


func _hl_int_hex_button() -> Control:
	return _editor.palette_bar.get_hex_button(INT_HEX_PATH)


func _hl_run_button() -> Control:
	return _editor.top_buttons.run_button


func _hl_clear_button() -> Control:
	return _editor.get_node_or_null("%Clear")


# ── Gating (the five choke points call these) ───────────────────────────────

# Generic token check against the current step's `allowed` list.
func allows(action: StringName) -> bool:
	if not running or _step_idx < 0 or _step_idx >= _steps.size():
		return true
	var allowed: Array = _steps[_step_idx].get("allowed", [])
	return action in allowed


func allows_job(id: String) -> bool:
	if not running:
		return true
	return allows(&"select_job") and id == TUTORIAL_JOB_ID


func allows_category(idx: int) -> bool:
	if not running:
		return true
	# Manager-initiated deselects (`select_category(-1)` in on_enter)
	# must always pass; the player can only ever *select*.
	if idx == -1:
		return true
	return allows(&"palette_category") and idx == INTEGER_CATEGORY_IDX


func allows_hex_pick(script: Variant) -> bool:
	if not running:
		return true
	return allows(&"palette_pick") \
			and script != null and script.resource_path == INT_HEX_PATH


func allows_placement(axial: Vector2i) -> bool:
	if not running:
		return true
	var step: Dictionary = {}
	if _step_idx >= 0 and _step_idx < _steps.size():
		step = _steps[_step_idx]
	if step.get("event", &"") != &"hex_placed":
		return false
	if axial == TARGET_AXIAL:
		return true
	if _marker:
		_marker.flash_reject()
	return false


# ── Completion ──────────────────────────────────────────────────────────────

func _finish_steps() -> void:
	# Persist immediately — a crash between here and the popup must
	# not replay the tutorial.
	SaveManager.set_tutorial_completed(true)
	if _hud:
		_hud.hide_panel()
	if _marker:
		_marker.clear()
	if _editor == null:
		_teardown()
		return
	# The fresh solve just popped the chapter-1 intro (renown 2 meets
	# its gate); give the player a beat to read the output, then show
	# the congrats once no modal is in the way.
	get_tree().create_timer(CONGRATS_DELAY_SECONDS).timeout.connect(_show_congrats)


func _show_congrats() -> void:
	if _editor == null:
		_teardown()
		return
	if _editor.is_any_modal_open():
		# Chapter-1 intro (or another modal) is up — slot in after it.
		_editor._chapter_intro_dialog.chapter_closed.connect(
				func(_id: String): _show_congrats(), CONNECT_ONE_SHOT)
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Congratulations!"
	dialog.dialog_text = (
		"You ran your first program — an Int hex wired into Do.\n\n"
		+ "Chapter 1 is unlocked: new jobs and new hexes await in the Jobs panel."
	)
	dialog.exclusive = true
	_editor.add_child(dialog)
	dialog.confirmed.connect(_teardown)
	dialog.canceled.connect(_teardown)
	dialog.popup_centered()


func _teardown() -> void:
	running = false
	active = false
	if _hud:
		_hud.queue_free()
		_hud = null
	if _marker:
		_marker.queue_free()
		_marker = null
	_placed_hex = null
	_step_idx = -1
