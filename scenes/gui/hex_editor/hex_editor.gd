extends Node
## Hex-tile visual editor.
##
## World layout:
##   World (Node2D)              ← pan/zoom by mutating position/scale
##     GridRenderer (HexGridRenderer)
##     Connections (Node2D)      ← Line2D children, one polyline per wire
##     Nodes (Node2D)            ← HexNode children (placed hexes + blueprint preview)
##
## Wires occupy a sequence of empty grid cells, traversing each cell from
## one side to another and pivoting at the cell's center (Factorio-belt
## style). Click a slot to begin wiring — the wire follows the cursor;
## click a compatible slot on another hex to finalize. `C` while wiring
## anchors the current routed cells so further mouse motion only re-routes
## the tail beyond the anchor.

# ── Tutorial-facing signals ─────────────────────────────────────────────────
# Statically declared progress events for TutorialManager (and any other
# observer). Pure notifications — nothing inside the editor depends on
# them being connected. Job/chapter progression signals
# (job_selection_changed, job_solved, …) live on ChapterManager.
signal hex_placed(node: HexNode, at_axial: Vector2i)
signal hex_deleted(node: HexNode)
signal blueprint_mode_exited
signal config_opened(node: HexNode)
signal config_closed
signal wire_committed(wire: HexWire)
signal wire_deleted(wire: HexWire)
signal wire_locked
signal tab_cleared

# The palette + its full hex-script catalog live on PaletteBar
# (`scenes/gui/hex_editor/ui/palette_bar.gd`). The editor only
# directly references the few scripts that show up in `is`
# checks or fixture instantiation; everything else flows through
# the PaletteBar's CATEGORIES.
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")
const DefinitionHex := preload("res://src/classes/hex_nodes/control/definition_hex.gd")

const WorkspaceTab := preload("res://scenes/gui/hex_editor/workspace_tab.gd")
# BlueprintCodec and BlueprintLoader are available globally via their
# `class_name` declarations in src/statics/. No preload needed.

const CHAPTER_INTRO_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/common/chapter_intro_dialog.tscn")
const CODEX_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/hex_editor/dialogs/codex_dialog.tscn")
const KEYBINDINGS_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/hex_editor/dialogs/keybindings_dialog.tscn")
const BLUEPRINT_LIBRARY_DIALOG_SCENE: PackedScene = preload("res://scenes/gui/blueprint_library/blueprint_library_dialog.tscn")

const TAB_COUNT_DEFAULT := 6

const BLUEPRINT_TINT_OK := Color(1.0, 1.0, 1.0, 0.55)
const BLUEPRINT_TINT_BLOCKED := Color(1.4, 0.55, 0.55, 0.55)

# Delete feedback (wire width factor / hex scale): a pronounced pop, then a
# snap-to-nothing.
const DELETE_FX_POP := 1.4
const DELETE_FX_POP_SECS := 0.03
const DELETE_FX_SHRINK_SECS := 0.07

# Committed-wire look (color/width) lives on HexWire so TabStore can
# rebuild visuals on load without reaching into the editor; the
# interactive-only tints stay here.
const WIRE_COLOR := HexWire.COLOR
const WIRE_PREVIEW_COLOR := Color(1.0, 0.9, 0.5, 0.65)
const WIRE_OPEN_COLOR := HexWire.OPEN_COLOR
const WIRE_ERROR_COLOR := Color(1.0, 0.35, 0.35, 0.95)
const WIRE_WIDTH := HexWire.WIDTH
const ROUTE_MAX_CELLS := 60
# How far the interactive router will look ahead to detour around an
# obstacle. The wire glides straight in open space, but when the direct
# path is blocked it searches at most this many cells for a way back onto
# a closer track. Beyond that it halts and the whole wire renders red
# (rather than snaking the "least-bad" way around for dozens of cells).
const ROUTE_LOOKAHEAD_HEXES := 3

@onready var world: Node2D = %World
@onready var hex_camera: Camera2D = %HexCamera
@onready var palette_bar: PaletteBar = %PaletteBar
@onready var output_panel = %OutputPanel  # OutputPanel script: generated text + run log
# Top-bar action buttons are owned by the TopButtons HBoxContainer
# script (scenes/gui/hex_editor/ui/top_buttons.gd). The editor talks
# to it via signals instead of reaching for individual button refs.
@onready var top_buttons = %TopButtons
@onready var job_header = %TopLabels  # JobHeader script: name + description
@onready var config_sidebar = %ConfigPanel  # ConfigSidebar script: per-hex config view
@onready var breadcrumb = %BreadcrumbBox  # Breadcrumb script: clickable level path
# The workspace tab strip UI was retired; the single-workspace model
# (TabStore / WorkspaceTab) lives on. These stay null so the tab-intent
# handlers below remain wired-but-dormant without erroring.
@onready var tab_strip: HBoxContainer = get_node_or_null("%TabStrip")
@onready var new_tab_button: Button = get_node_or_null("%NewTabButton")
@onready var jobs_panel = %JobsPanel  # JobsPanel script: list + renown
@onready var quick_repl_dialog: Control = %QuickReplDialog
@onready var _pause_menu: Control = %PauseMenu

var environment: Env = Env.root()
var _spawn_counter: int = 0

# Per-tab state lives on the WorkspaceTab nodes under World; the
# editor reads/mutates the ACTIVE tab through these forwarders, so
# the per-level/undo logic below didn't have to churn. The getters
# return live references (not copies): `_level_stack.append(...)`
# mutates the active tab's stack directly.

var do_node: HexNode:
	get:
		var t := _active_tab()
		return t.do_node if t != null else null

# Navigation stack of levels — index 0 is always the program's main level;
# the top of the stack is what's currently visible. Hexes / wires per
# level live on HexLevel.hexes / HexLevel.wires; the editor uses
# `_current_level()` to scope per-level operations.
var _level_stack: Array[HexLevel]:
	get:
		var t := _active_tab()
		return t.level_stack if t != null else ([] as Array[HexLevel])

# Undo / redo stacks. Each entry is a Dictionary with a `type` field
# (`place_hex` / `delete_hex` / `place_wire` / `delete_wire` /
# `rotate_hex`) and per-type payload. Tab-scoped. Sidebar config
# changes are not tracked — they're easy enough to re-do by hand.
var _undo_stack: Array:
	get:
		var t := _active_tab()
		return t.undo_stack if t != null else []
var _redo_stack: Array:
	get:
		var t := _active_tab()
		return t.redo_stack if t != null else []

# Compat containers for the active level: hexes and wire Line2Ds now
# live under each level's own `Nodes` / `Connections` children, so
# these forward to the active level. Blueprint/stamp previews and
# in-flight wire visuals parent here (= into the visible level).
var nodes_layer: Node2D:
	get:
		var lvl := _current_level()
		return lvl.nodes if lvl != null else null
var connections_layer: Node2D:
	get:
		var lvl := _current_level()
		return lvl.connections if lvl != null else null

# Blueprint state (placement mode). While `_blueprint_node` is non-null,
# placed hexes are non-pickable and left-click commits a placement.
var _blueprint_node: HexNode = null
var _blueprint_class = null      # script class for fresh placement (null when carrying)
var _blueprint_rotation: int = 0
var _blueprint_carried: bool = false  # true if a clone is being placed (single-shot, no respawn)
var _blueprint_axial: Vector2i = Vector2i.ZERO

# Blueprint stamp mode (multi-hex). Activated when the player picks
# `Stamp` on a saved blueprint in the Library modal. Mutually exclusive
# with single-hex blueprint mode and with active wiring.
#
# Stamp previews don't render wires (kept lean — wires get built on
# commit). Each entry in `_stamp_previews` is { node, rel_axial,
# rotation } — `rel_axial` is the position relative to the cursor, so
# moving the cursor re-snaps every preview hex in one pass.
var _stamp_payload: Dictionary = {}
var _stamp_previews: Array = []
var _stamp_anchor_axial: Vector2i = Vector2i.ZERO
# Stamp rotation in 60° CW steps (0..5). R rotates while in stamp
# mode; the rotation is applied to every hex's relative axial AND
# rotation_index, and to every preview wire's cell axials + edges.
var _stamp_rotation: int = 0
# Preview wires built alongside the preview hexes — line geometry
# reflects the rotated cell sequence. Disposed on exit / commit, the
# same way HexWire visuals are disposed on real deletion.
var _stamp_preview_wires: Array[HexWire] = []

# Pickup "move" mode rides alongside the stamp machinery: double-clicking
# a placed hex parks the original (shown translucent as a ghost at its
# origin) and arms a single-shot stamp. Unlike clipboard stamping, a
# commit places once and exits, RMB cancels the move (restoring the
# original), and the whole move folds into one undo entry.
const PICKUP_GHOST_TINT := Color(1, 1, 1, 0.22)
var _pickup_active: bool = false
var _pickup_record: Dictionary = {}   # {hex, level, removed_wires}

# Level-transition animation: a parallel camera tween (pan + zoom) and a
# fade-in of the incoming level run on each descend / ascend. Cached so a
# rapid second transition kills the in-flight one instead of stacking.
var _transition_tween: Tween
var _fade_tween: Tween

# Multi-hex marquee (Phase 19.4 polish). Shift+LMB drag = selection
# box (selected hexes get a cyan tint until cleared); Shift+RMB drag
# = delete box (everything inside is deleted on release). Tracking
# is in world coordinates so panning / zooming during a drag stays
# coherent.
var _marquee_active: bool = false
var _marquee_is_delete: bool = false
var _marquee_start_world: Vector2 = Vector2.ZERO
var _marquee_fill: Polygon2D = null
var _marquee_outline: Line2D = null
var _selected_hexes: Array[HexNode] = []

# Session clipboard for Ctrl+C / Ctrl+V. Not persisted — lives only
# until the editor scene is freed. Ctrl+C copies the OS clipboard
# *also*, so the player can share even after restarting; this var is
# just the no-roundtrip-through-base64 fast path for Ctrl+V.
var _last_copied_payload: Dictionary = {}

# Auto-save debounce timer for per-tab hex-graph persistence. Every
# undoable action (`_push_undo`) restarts this timer; when it fires
# we serialize every tab through BlueprintCodec and write to the
# save file. Keeps us from JSON-ing 6 tabs on every keystroke / wire
# placement while still capturing changes within a second of the
# player going idle.
const AUTOSAVE_DEBOUNCE_SECONDS := 1.0
var _autosave_timer: Timer = null

const MARQUEE_FILL_SELECT := Color(0.4, 0.75, 1.0, 0.18)
const MARQUEE_OUTLINE_SELECT := Color(0.6, 0.9, 1.0, 0.9)
const MARQUEE_FILL_DELETE := Color(1.0, 0.45, 0.45, 0.18)
const MARQUEE_OUTLINE_DELETE := Color(1.0, 0.55, 0.55, 0.9)
const SELECTED_HEX_MODULATE := Color(0.7, 1.2, 1.5)

# Wiring state. `_active_wire` is the in-progress wire; mouse motion
# re-routes its tail toward the cursor cell.
var _active_wire: HexWire = null

# Hex-cell wireframe + lock markers shown while a wire is being routed.
# Created lazily, lives in connections_layer, cleared on commit/cancel.
var _wire_chain_overlay: WireChainOverlay = null

# In-flight wire-deletion tweens (HexWire -> Tween), so an undo during the
# pop-then-thin animation can cancel it before it parks the wire.
var _wire_fx_tweens: Dictionary = {}

# In-flight hex-deletion tweens (HexNode -> Tween), same purpose: an undo
# mid-animation cancels the shrink and restores a full-size hex.
var _hex_fx_tweens: Dictionary = {}

# The hex currently highlighted as the wire's hover target (body brightened
# while a dragged wire could snap onto it). Cleared on commit/cancel.
var _wire_hover_hex: HexNode = null

# Whichever placed hex is currently shown in the right-hand config
# sidebar (or null if the sidebar is closed).
var _config_target: HexNode = null

# True for the span of one RMB press once `_unhandled_input` has consumed
# it cancelling a mode/selection/panel. The same physical press also
# reaches the hex body's physics-picked delete path a beat later; the flag
# stops that second handler from deleting the hex the cancel just spared.
# Reset on RMB release.
var _rmb_cancelled_press: bool = false

# ── Phase 19 — Workspace tabs + jobs panel ─────────────────────────────────
#
# The editor's existing member vars (`_level_stack`, `_undo_stack`,
# `_redo_stack`, `do_node`) are *always* the active tab's state. On tab
# switch we snapshot them into the outgoing tab and load the incoming
# tab's stored snapshot back in. Per-level pan / zoom already lives on
# HexLevel, so just swapping the stack is enough to restore the view.
var _tabs: Array = []  # Array[WorkspaceTab]
var _active_tab_idx: int = 0
var _next_tab_id: int = 1
# Job selection / progression state lives on ChapterManager — the
# editor reads `ChapterManager.get_selected_job_id()` and reacts to
# its signals; nothing job-related is stored here anymore.

# Library modal: a Control-based dialog scene that owns its UI + the
# per-blueprint card buttons + the live preview. The editor only
# holds a reference and routes signals (capture / import / stamp).
var _library_dialog: Control = null

# Chapter intro modal: shown when ChapterManager requests an intro
# (fresh-save boot, or first job selected from an unseen chapter).
var _chapter_intro_dialog: Control = null

# Lazy-instantiated Control-based modals. Each owns its UI; the editor
# only holds a reference + the entry point that calls `.open()`.
var _codex_dialog: Control = null
var _keybindings_dialog: Control = null

# Modal gating: every Control modal (pause menu, quick REPL, the four
# refactored dialogs) opts in via `_track_modal()`, which pauses the
# SceneTree while any of them is visible (ModalStack). PAUSABLE nodes
# — this editor, the camera, every input handler — stop receiving
# _process/_unhandled_input while paused, so canvas controls can't
# fire underneath an open dialog without any per-handler gate checks.
# Dialogs themselves run at PROCESS_MODE_WHEN_PAUSED.


## Shim kept for TutorialManager + tests; the state lives in ModalStack.
func is_any_modal_open() -> bool:
	return ModalStack.is_open()


# Last-known `visible` per tracked modal, so spurious
# visibility_changed emissions (tree enter/exit, parent toggles)
# can't unbalance the acquire/release pairing.
var _modal_seen_visible: Dictionary = {}


func _track_modal(modal: Control) -> void:
	# `visibility_changed` fires synchronously on the same frame as
	# the `visible = true/false` assignment, so the pause snaps on the
	# same frame as `open()` / `close()`.
	modal.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_modal_seen_visible[modal] = modal.visible
	modal.visibility_changed.connect(func() -> void:
		var prev: bool = _modal_seen_visible.get(modal, false)
		if modal.visible == prev:
			return
		_modal_seen_visible[modal] = modal.visible
		if modal.visible:
			ModalStack.acquire(get_tree())
		else:
			ModalStack.release(get_tree()))


func _ready() -> void:
	environment = Env.root()
	Prelude.load_std_lib(environment)

	palette_bar.hex_selected.connect(_enter_blueprint_fresh)
	palette_bar.blueprint_mode_cancelled.connect(_exit_blueprint_mode)
	palette_bar.set_unlocked_scripts(SaveManager.get_unlocked_hex_scripts())
	palette_bar.set_archmage(SaveManager.is_archmage())

	# Phase 19.1 — Bootstrap workspace tabs. Each tab owns its own level 0
	# (anchorless main canvas) and DoHex fixture; the editor's per-level
	# member vars below are always the *active* tab's state. The active
	# tab index is restored from SaveManager so the user lands back on
	# whichever tab they last used.
	_bootstrap_tabs()
	_rebuild_tab_strip()
	_update_breadcrumb()

	top_buttons.generate_requested.connect(_on_generate_pressed)
	top_buttons.run_requested.connect(_on_run_pressed)
	top_buttons.copy_text_requested.connect(_copy_program_text_to_clipboard)

	# The strip owns its own view (buttons, context menu, rename dialog)
	# and hotkeys; the editor stays the model owner and answers the
	# intents. The strip UI is currently absent, so guard the wiring.
	if tab_strip != null:
		tab_strip.tab_new_requested.connect(_on_new_tab_pressed)
		tab_strip.tab_switch_requested.connect(_switch_to_tab)
		tab_strip.tab_close_requested.connect(_close_tab)
		tab_strip.tab_clear_requested.connect(_clear_tab)
		tab_strip.tab_copy_requested.connect(_copy_tab_blueprint_to_clipboard)
		tab_strip.tab_rename_requested.connect(_rename_tab)
	top_buttons.menu_requested.connect(_pause_menu.pause)
	_pause_menu.preferences_changed.connect(_refresh_after_preferences_change)
	_pause_menu.codex_requested.connect(_on_codex_requested)
	_pause_menu.keybindings_requested.connect(_show_help_overlay)
	top_buttons.help_requested.connect(_show_help_overlay)
	top_buttons.library_requested.connect(_open_library)
	top_buttons.codex_requested.connect(_on_codex_requested)
	jobs_panel.job_toggled.connect(ChapterManager.select_job)
	breadcrumb.jump_requested.connect(_jump_to_level)
	# Mouse-only level navigation from the config panel (keyboard: Q / E).
	if config_sidebar != null:
		config_sidebar.ascend_requested.connect(_try_ascend)
		config_sidebar.descend_requested.connect(func() -> void: _descend_into(_config_target))
	if new_tab_button != null:
		new_tab_button.pressed.connect(_on_new_tab_pressed)

	# Job/chapter progression lives on ChapterManager; the editor is a
	# thin view — these handlers only refresh widgets / show modals.
	# (Connections to a freed editor are dropped automatically.)
	ChapterManager.job_selection_changed.connect(_on_job_selection_changed)
	ChapterManager.renown_changed.connect(_on_renown_changed)
	ChapterManager.hexes_unlocked.connect(_on_hexes_unlocked)
	ChapterManager.chapter_intro_requested.connect(_on_chapter_intro_requested)
	ChapterManager.submit_completed.connect(_on_submit_completed)
	ChapterManager.templates_unlocked.connect(_on_templates_unlocked)

	# Seed the blueprint loader's class registry with every palette hex
	# script + the fixtures it might recreate (DoHex, AnchorHex,
	# MatchAnchor). Path lookups are the fast common case; the class
	# fallback matters when a script has been moved between builds.
	_seed_blueprint_registry()

	# Auto-save debounce: every undoable action restarts the timer,
	# we persist when it fires (or on tab close / scene tree exit so
	# pending changes always make it to disk).
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DEBOUNCE_SECONDS
	_autosave_timer.timeout.connect(_persist_tab_layout)
	add_child(_autosave_timer)

	_rebuild_jobs_list()
	_update_renown_label()
	# Re-sync the IdentifierPalette exposure gate with whatever job is
	# selected (ChapterManager state persists across scene loads).
	ChapterManager.apply_job_context()

	_refresh_job_display()

	# Setup chapter intro dialog
	_chapter_intro_dialog = CHAPTER_INTRO_DIALOG_SCENE.instantiate() as Control
	_chapter_intro_dialog.visible = false
	_chapter_intro_dialog.chapter_closed.connect(_on_chapter_intro_closed)
	_pause_menu.get_parent().add_child(_chapter_intro_dialog)
	_track_modal(_chapter_intro_dialog)

	# Always-present modals (instantiated by the editor's .tscn).
	# The lazy modals (library / codex / keybindings) opt in inside
	# their open helpers below.
	_track_modal(_pause_menu)
	_track_modal(quick_repl_dialog)

	# Chapter intros surface when the player selects a job belonging to
	# an unseen chapter (ChapterManager.select_job). Except on a fresh
	# save: the tutorial intro is the player's first contact with the
	# game, so it still pops immediately. Deferred so the dialog +
	# layout finish settling first.
	if SaveManager.get_seen_chapter_intros().is_empty():
		ChapterManager.maybe_show_next_chapter_intro.call_deferred()

	# Enter / Space (or submitting a field) in the config sidebar
	# confirms and closes it.
	if config_sidebar and not config_sidebar.confirm_requested.is_connected(_close_config_sidebar):
		config_sidebar.confirm_requested.connect(_close_config_sidebar)

	# Top-bar canvas buttons: undo / redo / clear (unique-named, so the
	# lookup is independent of where the layout parks them).
	var undo_btn := get_node_or_null("%Undo")
	if undo_btn != null:
		undo_btn.pressed.connect(_undo)
	var redo_btn := get_node_or_null("%Redo")
	if redo_btn != null:
		redo_btn.pressed.connect(_redo)
	var clear_btn := get_node_or_null("%Clear")
	if clear_btn != null:
		clear_btn.pressed.connect(_clear_active_tab)

	# Hand the scene to the tutorial director — a no-op once the
	# save's has_completed_tutorial flag is set.
	TutorialManager.attach(self)


func _active_tab() -> WorkspaceTab:
	if _active_tab_idx < 0 or _active_tab_idx >= _tabs.size():
		return null
	return _tabs[_active_tab_idx]


func _current_level() -> HexLevel:
	var t := _active_tab()
	return t.current_level() if t != null else null


# Tutorial support: the scripted placement/wiring steps need a
# pristine board (just the DoHex, no wires). When the active canvas
# already has content — a replay on a lived-in save — create and
# switch to a fresh "Tutorial" tab instead of touching it.
func ensure_fresh_tutorial_tab() -> void:
	var t := _active_tab()
	if t != null and _level_stack.size() == 1 and t.is_empty():
		return
	_create_tab("Tutorial", true)


# ── Phase 19 — Workspace tabs ──────────────────────────────────────────────

var _bootstrap_done: bool = false


func _bootstrap_tabs() -> void:
	# Restore tabs + their hex graphs from the save file. Each saved
	# entry is `{name, payload}`; an empty payload means a brand-new
	# tab with no hex content yet (the tab still gets its name + a
	# fresh DoHex). Legacy `tabs: [String]` saves are migrated up to
	# the new shape by SaveManager.get_tab_payloads.
	var saved: Array = SaveManager.get_tab_payloads()
	if saved.is_empty():
		for i in range(TAB_COUNT_DEFAULT):
			_create_tab("Tab %d" % (i + 1), false)
	else:
		for entry in saved:
			var name := String(entry.get("name", ""))
			if name.is_empty():
				name = "Tab %d" % (_tabs.size() + 1)
			var tab := _create_tab(name, false)
			var payload: Dictionary = entry.get("payload", {})
			if not payload.is_empty():
				_install_tab_payload(tab, payload)
	var saved_active: int = SaveManager.get_current_tab_id()
	# Saved index could be stale (e.g. tab list shrank) — clamp.
	if saved_active < 0 or saved_active >= _tabs.size():
		saved_active = 0
	_active_tab_idx = saved_active
	_load_tab_state(_tabs[_active_tab_idx])
	# From now on tab mutations write through to the save file.
	_bootstrap_done = true
	_persist_tab_layout()


# Rehydrate `tab`'s root level from a saved blueprint payload —
# TabStore owns the loader plumbing; the editor only surfaces the
# warnings.
func _install_tab_payload(tab: WorkspaceTab, payload: Dictionary) -> void:
	for warning in TabStore.install_payload(tab, payload, _wire_node_signals):
		push_warning("Tab '%s' bootstrap: %s" % [tab.tab_name, String(warning)])


# Create a new tab node under World and append it to `_tabs`.
# `make_active` decides whether to switch to it once built.
func _create_tab(p_name: String, make_active: bool) -> WorkspaceTab:
	var tab := TabStore.create_fresh(_next_tab_id, p_name, world, _wire_node_signals)
	_next_tab_id += 1
	_tabs.append(tab)
	if make_active:
		_switch_to_tab(_tabs.size() - 1)
	_persist_tab_layout()
	return tab


# Stash the latest pan/zoom onto the active tab's top level before
# switching away — `_push_level` / `_pop_level` already do this on
# level changes, but not on a tab switch. Everything else (stacks,
# undo/redo, do_node) already lives on the tab node.
func _save_active_tab_state() -> void:
	var t := _active_tab()
	if t != null and hex_camera != null:
		t.store_view(hex_camera.position, hex_camera.zoom.x)


# Activate `t`'s subtree (the caller has already pointed
# `_active_tab_idx` at it): one visibility flip per tab node, then
# camera + chrome refresh for the incoming top level.
func _load_tab_state(t: WorkspaceTab) -> void:
	# Cancel transient modes that point at the outgoing tab's nodes.
	if _current_level() != null:
		_exit_blueprint_mode()
		_exit_stamp_mode()
		_cancel_active_wire()
		_cancel_marquee()
		_clear_selection()
		_close_config_sidebar()
	for tab in _tabs:
		if tab != t:
			tab.set_active(false)
	t.set_active(true)
	_apply_level_view(_current_level())
	_update_breadcrumb()
	_refresh_do_display_value()


func _switch_to_tab(idx: int) -> void:
	if idx < 0 or idx >= _tabs.size():
		return
	if idx == _active_tab_idx:
		return
	_save_active_tab_state()
	_active_tab_idx = idx
	_load_tab_state(_tabs[idx])
	_rebuild_tab_strip()
	_persist_tab_layout()


func _on_new_tab_pressed() -> void:
	_create_tab("Tab %d" % (_tabs.size() + 1), true)
	_rebuild_tab_strip()


func _rename_tab(idx: int, p_name: String) -> void:
	if idx < 0 or idx >= _tabs.size():
		return
	if _tabs[idx].rename(p_name):
		_rebuild_tab_strip()
	_persist_tab_layout()


# Wipe everything in a tab (recursively frees inner levels, drops all
# wires) but keep the tab itself + its DoHex fixture so the index stays
# stable.
func _clear_tab(idx: int) -> void:
	if idx < 0 or idx >= _tabs.size():
		return
	var was_active := (idx == _active_tab_idx)
	# Save outgoing state first if this is the active tab so we don't
	# stomp on the editor's member vars mid-clear.
	if was_active:
		_save_active_tab_state()
	_tabs[idx].clear_content()
	if was_active:
		_load_tab_state(_tabs[idx])
	_rebuild_tab_strip()


# Undoable "clear the tab": delete every non-fixture hex (their inner
# levels ride along, parked, so one Ctrl+Z restores the lot) and slerp
# the camera back to the Do hex. Unlike `_clear_tab`, this keeps the
# undo/redo history and is itself a single undo step.
func _clear_active_tab() -> void:
	# Surface to the root level — the Do fixture lives there, and a hex
	# we're currently inside can't be deleted anyway.
	while _level_stack.size() > 1:
		_pop_level(false)
	var level := _current_level()
	if level == null:
		return
	var snapshot: Array = []
	for h in level.hexes:
		if not h.is_fixture:
			snapshot.append(h)
	_clear_selection()
	var records: Array = []
	for h in snapshot:
		var rec := _delete_hex(h, false, false)
		if not rec.is_empty():
			records.append(rec)
	if not records.is_empty():
		_push_undo({
			"type": "delete_hexes_bulk",
			"level": level,
			"entries": records,
		})
		SfxManager.play("delete")  # only when the clear actually removed hexes
		tab_cleared.emit()
	_slerp_camera_to_origin()


# Smoothly glide the camera to the current level's fixture (every
# level's anchor / Do hex sits at the origin) at 1:1 zoom — the
# animated cousin of the old H "home" snap.
func _slerp_camera_to_origin() -> void:
	if hex_camera == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(hex_camera, "position", Vector2.ZERO, 0.4)
	tw.tween_property(hex_camera, "zoom", Vector2.ONE, 0.4)
	var lvl := _current_level()
	if lvl != null:
		lvl.world_position = Vector2.ZERO
		lvl.world_scale = 1.0


# H — recenter on the current level's fixture (stays on this level).
func _home_camera() -> void:
	_slerp_camera_to_origin()


# Ctrl+H — drop to the root (Do) level, then slerp to the centre hex.
func _home_to_do() -> void:
	# Snap through intermediate levels; the slerp owns the camera move so
	# it doesn't fight a per-pop transition tween.
	while _level_stack.size() > 1:
		_pop_level(false)
	_slerp_camera_to_origin()


func _rebuild_tab_strip() -> void:
	if tab_strip != null:
		tab_strip.rebuild(_tab_names(), _active_tab_idx)


func _tab_names() -> Array:
	var names: Array = []
	for t in _tabs:
		names.append(t.tab_name)
	return names


func _close_tab(idx: int) -> void:
	if _tabs.size() <= 1:
		return
	if idx < 0 or idx >= _tabs.size():
		return
	var t: WorkspaceTab = _tabs[idx]
	# Closing the active tab: transient previews (blueprint, stamp,
	# in-flight wire) live inside its level containers — cancel the
	# modes BEFORE freeing the subtree so their exit paths don't touch
	# freed nodes.
	if idx == _active_tab_idx:
		_exit_blueprint_mode()
		_exit_stamp_mode()
		_cancel_active_wire()
		_cancel_marquee()
		_clear_selection()
		_close_config_sidebar()
	# The tab is one subtree now — freeing it frees every level, hex,
	# and wire Line2D it contains.
	t.queue_free()
	if idx == _active_tab_idx:
		# Pick a sensible neighbor before removing.
		var fallback := idx - 1 if idx > 0 else 0
		_tabs.remove_at(idx)
		_active_tab_idx = clamp(fallback, 0, _tabs.size() - 1)
		_load_tab_state(_tabs[_active_tab_idx])
	else:
		_tabs.remove_at(idx)
		if _active_tab_idx > idx:
			_active_tab_idx -= 1
	_rebuild_tab_strip()
	_persist_tab_layout()


func _persist_tab_layout() -> void:
	if not _bootstrap_done:
		return
	# Flush the active tab's camera state first so the serializer reads
	# the latest pan/zoom; TabStore owns the codec round-trip.
	_save_active_tab_state()
	TabStore.persist(_tabs, _active_tab_idx, self)



# ── Node lifecycle ──────────────────────────────────────────────────────────

func _wire_node_signals(node: HexNode) -> void:
	node.slot_grab_started.connect(_on_slot_pressed)
	node.node_grab_started.connect(_on_hex_body_pressed)
	node.node_pickup_requested.connect(_pickup_hex)
	node.delete_requested.connect(_on_node_delete_requested)
	node.arity_change_requested.connect(_on_arity_change_requested)


# Non-destructive arity change. The hex applies the structural change in
# place (`apply_arity`) — surviving slots keep their edge + wire on the
# prefix-stable order — and we drop only the wire(s) on any slot a shrink
# removed, recording one undoable action. The inner level and the undo
# history are preserved (contrast `_on_inner_level_invalidated`).
func _on_arity_change_requested(hex: HexNode, new_arity: int) -> void:
	if new_arity == hex.arity:
		return
	var old_arity: int = hex.arity
	var slot_node: HexNode = hex.arity_slot_node()
	var before: Array = slot_node.input_edges.duplicate() if slot_node != null else []
	hex.apply_arity(new_arity)
	var slot_level: HexLevel = slot_node.level if slot_node != null else null
	var dropped: Array[HexWire] = []
	if slot_node != null and slot_level != null:
		var after: Array = slot_node.input_edges
		var removed: Array = []
		for e in before:
			if e not in after:
				removed.append(e)
		if not removed.is_empty():
			for w in slot_level.wires:
				if w.input_node == slot_node and int(w.input_edge) in removed:
					dropped.append(w)
			for w in dropped:
				slot_level.wires.erase(w)
				_park_wire(w)
	_push_undo({
		"type": "arity",
		"hex": hex,
		"old": old_arity,
		"new": new_arity,
		"slot_level": slot_level,
		"dropped": dropped,
	})
	_reopen_config_for_arity(hex)


# Reopen the config sidebar after an arity change so the SpinBox + per-
# slot editors track the new shape. The target is the outer hex when the
# change came from its own sidebar, or the inner anchor when it came from
# inside via the delegating anchor (see `config_delegate`).
func _reopen_config_for_arity(hex: HexNode) -> void:
	if _config_target == hex:
		_open_config_sidebar(hex)
	elif _config_target != null and hex.inner_level != null \
			and _config_target == hex.inner_level.anchor:
		_open_config_sidebar(_config_target)


# Shared right-click contextual-cancel cascade, used by BOTH right-click
# paths — the hex-body one (`_on_node_delete_requested`) and the empty-
# canvas one (`_unhandled_input`). Returns true when the click was
# consumed cancelling a mode / selection / panel; false means "nothing to
# cancel", and the caller falls through to its own delete (the hex under
# the cursor, or a wire under the cursor).
#
# Single source of truth for the friction-pass invariants:
#   • RMB in stamp mode ONLY exits stamp — never deletes.
#   • RMB in single-hex blueprint mode ONLY exits blueprint.
#   • RMB mid-wire cancels the wire; with a selection, clears it; with the
#     config panel open, closes it.
#   • A hex (or wire) is deleted only when none of the above is active.
func _rmb_contextual_cancel() -> bool:
	if not _stamp_previews.is_empty():
		_exit_stamp_mode()
		return true
	if _blueprint_node != null:
		_exit_blueprint_mode()
		return true
	if _active_wire != null:
		_cancel_active_wire()
		return true
	if not _selected_hexes.is_empty():
		_clear_selection()
		if _config_target != null:
			_close_config_sidebar()
		return true
	if _config_target != null:
		_close_config_sidebar()
		return true
	return false


func _on_node_delete_requested(node: HexNode) -> void:
	# RMB on a hex body. A single physical RMB reaches BOTH this
	# physics-picked path AND the editor's `_unhandled_input` RMB branch.
	# If that branch already consumed the click cancelling a mode
	# (stamp/config/selection), the cascade below would no longer see it
	# and would wrongly delete the hex — so honour the one-press guard.
	if _rmb_cancelled_press:
		_rmb_cancelled_press = false
		return
	# Contextual-cancel gets first dibs; only when nothing is active does
	# the click delete the hex under the cursor.
	if _rmb_contextual_cancel():
		return
	_delete_hex(node)


# Free a hex and everything that depends on it: its incoming/outgoing
# wires at the parent level, the config sidebar if it was being shown,
# and the contents of any inner level (recursively).
func _delete_hex(node: HexNode, push_undo: bool = true, play_sfx: bool = true,
		animate: bool = true) -> Dictionary:
	# Returns the removal record `{hex, level, removed_wires}` (or `{}`
	# when the delete was refused) so bulk callers — Shift+RMB marquee,
	# Ctrl+X cut — can collect each per-hex record into a single
	# `delete_hexes_bulk` undo entry instead of pushing one entry per
	# hex. Set `push_undo = false` to skip the per-hex undo push.
	# Fixtures (DoHex, AnchorHex, MatchAnchor) are the tab's entry
	# points / level pivots and must never be torn out via RMB. The
	# cut/clone/cycle/bulk paths already pre-filter on `is_fixture`;
	# this is the central backstop covering the RMB → delete path.
	if node.is_fixture:
		return {}
	if node.level == null:
		return {}
	# Refuse if the user is currently *inside* this hex's inner level
	# (would strand them in a now-orphaned canvas).
	if node.inner_level != null and _level_stack.has(node.inner_level):
		return {}
	var level = node.level
	var removed_wires: Array[HexWire] = []
	for w in level.wires:
		if w.output_node == node or w.input_node == node:
			removed_wires.append(w)
	_apply_delete_hex(node, level, removed_wires, animate)
	var record := {
		"hex": node,
		"level": level,
		"removed_wires": removed_wires,
	}
	if push_undo:
		var entry := record.duplicate()
		entry["type"] = "delete_hex"
		_push_undo(entry)
	# Notify listeners (the tutorial recovers if its placed hex is torn out).
	hex_deleted.emit(node)
	# Sound rides the actual deletion (so RMB / under-mouse / etc. all cue
	# without a per-caller play, and a refused delete above stays silent).
	# Bulk callers pass play_sfx=false and fire one cue for the whole batch.
	if play_sfx:
		SfxManager.play("delete")
	return record


# Park strategy: hide + remove from the level lists instead of
# `queue_free`-ing. Lets `_undo_delete_hex` restore the hex (and its
# wires + its preserved inner level) by un-hiding and re-adding to the
# level lists.
func _apply_delete_hex(node: HexNode, level: HexLevel, removed_wires: Array,
		animate: bool = false) -> void:
	for w in removed_wires:
		level.wires.erase(w)
		_park_wire(w)
	level.hexes.erase(node)
	if animate:
		_animate_hex_deletion(node)  # pop + shrink, then park
	else:
		_park_hex(node)


# Pop-then-shrink a user-deleted hex before parking it (kept alive for undo).
# Mirrors _animate_wire_deletion: the logical-park bits happen now, the hide is
# deferred to the tween end, and the tween is tracked so an undo mid-animation
# can cancel it (_restore_hex).
func _animate_hex_deletion(node: HexNode) -> void:
	if _config_target == node:
		_close_config_sidebar()
	node.set_pickable(false)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * DELETE_FX_POP, DELETE_FX_POP_SECS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ZERO, DELETE_FX_SHRINK_SECS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_hex_fx_tweens.erase(node)
		node.visible = false
		node.scale = Vector2.ONE)
	_hex_fx_tweens[node] = tw


func _undo_delete_hex(action: Dictionary) -> void:
	_restore_hex(action.hex)
	action.level.hexes.append(action.hex)
	for w in action.removed_wires:
		action.level.wires.append(w)
		_restore_wire(w)


func _park_hex(node: HexNode) -> void:
	if _config_target == node:
		_close_config_sidebar()
	node.visible = false
	node.set_pickable(false)


func _restore_hex(node: HexNode) -> void:
	# Cancel an in-flight delete animation so its park callback can't fire
	# after the restore, and undo any shrink it applied.
	if _hex_fx_tweens.has(node):
		_hex_fx_tweens[node].kill()
		_hex_fx_tweens.erase(node)
	node.scale = Vector2.ONE
	node.visible = true
	# A restored hex always returns to its normal opaque look — clears any
	# lingering tint (e.g. the translucent pickup ghost) so undoing a move
	# doesn't bring the original back stuck in the ghost state.
	node.modulate = Color.WHITE
	# Pickability follows the owning level's activation — an undo can
	# restore a hex on a level that isn't the current top of stack.
	node.set_pickable(node.level != null and node.level.active)


func _park_wire(w: HexWire) -> void:
	if w.line:
		w.line.visible = false
	if w.error_line:
		w.error_line.visible = false


func _restore_wire(w: HexWire) -> void:
	# Cancel an in-flight delete animation so its park callback can't fire
	# after the restore, and reset the width the animation may have shrunk.
	if _wire_fx_tweens.has(w):
		_wire_fx_tweens[w].kill()
		_wire_fx_tweens.erase(w)
	if w.line:
		w.line.visible = true
		w.line.width = HexWire.WIDTH
	if w.error_line:
		w.error_line.visible = true
		w.error_line.width = HexWire.WIDTH


# ── Undo / Redo ─────────────────────────────────────────────────────────────

func _push_undo(action: Dictionary) -> void:
	_undo_stack.append(action)
	_redo_stack.clear()
	_schedule_autosave()
	_refresh_do_display_value()


# Restart the debounce timer. Calling start() while the timer is
# already running resets the countdown, so a burst of mutations
# collapses into a single save when the player pauses.
func _schedule_autosave() -> void:
	if _autosave_timer and _bootstrap_done:
		_autosave_timer.start()


# Flush any pending debounced save on scene exit (player navigated
# away, app closing). The save itself is idempotent, so it's safe
# even when nothing was actually pending.
func _exit_tree() -> void:
	if _bootstrap_done:
		_persist_tab_layout()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var a: Dictionary = _undo_stack.pop_back()
	match a.type:
		"place_hex":
			_undo_place_hex(a)
		"delete_hex":
			_undo_delete_hex(a)
		"delete_hexes_bulk":
			_undo_delete_hexes_bulk(a)
		"place_stamp":
			_undo_place_stamp(a)
		"place_wire":
			_undo_place_wire(a)
		"delete_wire":
			_undo_delete_wire(a)
		"rotate_hex":
			_undo_rotate_hex(a)
		"arity":
			_undo_arity(a)
	_redo_stack.append(a)
	_refresh_do_display_value()


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	var a: Dictionary = _redo_stack.pop_back()
	match a.type:
		"place_hex":
			_redo_place_hex(a)
		"delete_hex":
			_redo_delete_hex(a)
		"delete_hexes_bulk":
			_redo_delete_hexes_bulk(a)
		"place_stamp":
			_redo_place_stamp(a)
		"place_wire":
			_redo_place_wire(a)
		"delete_wire":
			_redo_delete_wire(a)
		"rotate_hex":
			_redo_rotate_hex(a)
		"arity":
			_redo_arity(a)
	_undo_stack.append(a)
	_refresh_do_display_value()


# Group undo for marquee delete + Ctrl+X cut. `entries` is an
# ordered list of {hex, level, removed_wires} records produced by
# `_delete_hex(node, false)` in the original delete order. Undo
# walks them in reverse so each restoration's `_undo_delete_hex`
# sees the hex's wires after later-deleted siblings are already
# back in place.
func _undo_delete_hexes_bulk(action: Dictionary) -> void:
	var entries: Array = action.get("entries", [])
	for i in range(entries.size() - 1, -1, -1):
		_undo_delete_hex(entries[i])


func _redo_delete_hexes_bulk(action: Dictionary) -> void:
	for entry in action.get("entries", []):
		_apply_delete_hex(entry.hex, entry.level, entry.removed_wires)


# Reverse a whole stamp commit in one step. Wires go first (they depend
# on the hexes), then the placed hexes (each carries its inner level
# along, parked — same preservation as a deleted hex), then the
# re-orientations applied to pre-existing same-type hexes roll back to
# their prior facing.
func _undo_place_stamp(action: Dictionary) -> void:
	var level: HexLevel = action.level
	for w in action.get("wires", []):
		level.wires.erase(w)
		_park_wire(w)
	for hex in action.get("hexes", []):
		level.hexes.erase(hex)
		_park_hex(hex)
	for r in action.get("reorients", []):
		_reapply_reorient(r.hex, r.old)
	# A move folds the picked-up original's removal into this entry —
	# restore it (back to its origin cell + wires) when undoing the move.
	for rec in action.get("removed", []):
		_undo_delete_hex(rec)


func _redo_place_stamp(action: Dictionary) -> void:
	var level: HexLevel = action.level
	for hex in action.get("hexes", []):
		level.hexes.append(hex)
		_restore_hex(hex)
	for w in action.get("wires", []):
		level.wires.append(w)
		_restore_wire(w)
	for r in action.get("reorients", []):
		_reapply_reorient(r.hex, r.new)
	# Re-park the picked-up original (mirrors the undo restore above).
	for rec in action.get("removed", []):
		_apply_delete_hex(rec.hex, rec.level, rec.removed_wires)


# Set a hex's rotation directly (no wire re-route delta) and refresh the
# sidebar if it's the configured hex, mirroring the live re-orient path.
func _reapply_reorient(hex: HexNode, index: int) -> void:
	hex.set_rotation_index(index)
	if hex.level != null:
		for w in hex.level.wires:
			if not w.is_open and (w.output_node == hex or w.input_node == hex):
				_rebuild_wire_cells(w)
	if _config_target == hex:
		_open_config_sidebar(hex)


func _undo_place_hex(action: Dictionary) -> void:
	action.level.hexes.erase(action.hex)
	_park_hex(action.hex)


func _redo_place_hex(action: Dictionary) -> void:
	action.level.hexes.append(action.hex)
	_restore_hex(action.hex)


func _redo_delete_hex(action: Dictionary) -> void:
	_apply_delete_hex(action.hex, action.level, action.removed_wires)


func _undo_place_wire(action: Dictionary) -> void:
	action.level.wires.erase(action.wire)
	_park_wire(action.wire)
	# Bring back any wire this one displaced when it took over the input.
	for w in action.get("overwritten", []):
		action.level.wires.append(w)
		_restore_wire(w)


func _redo_place_wire(action: Dictionary) -> void:
	for w in action.get("overwritten", []):
		action.level.wires.erase(w)
		_park_wire(w)
	action.level.wires.append(action.wire)
	_restore_wire(action.wire)


func _undo_delete_wire(action: Dictionary) -> void:
	action.level.wires.append(action.wire)
	_restore_wire(action.wire)


func _redo_delete_wire(action: Dictionary) -> void:
	action.level.wires.erase(action.wire)
	_park_wire(action.wire)


# Arity change. `apply_arity` re-grows / re-shrinks the slots in place;
# the parked wire(s) on the (un)removed slot are restored or re-dropped
# to match. The wire objects survive parked between undo/redo, so an undo
# brings a shrunk-away element's wire back intact.
func _undo_arity(action: Dictionary) -> void:
	action.hex.apply_arity(action.old)
	for w in action.dropped:
		action.slot_level.wires.append(w)
		_restore_wire(w)
	_reopen_config_for_arity(action.hex)


func _redo_arity(action: Dictionary) -> void:
	action.hex.apply_arity(action.new)
	for w in action.dropped:
		action.slot_level.wires.erase(w)
		_park_wire(w)
	_reopen_config_for_arity(action.hex)


func _undo_rotate_hex(action: Dictionary) -> void:
	# Restore wires the rotation stranded before reversing it: the inverse
	# rotation rebuilds their cells back at the orientation where they
	# routed cleanly.
	var level: HexLevel = action.hex.level
	for w in action.get("deleted_wires", []):
		if level != null and not level.wires.has(w):
			level.wires.append(w)
		_restore_wire(w)
	_apply_rotate_hex(action.hex, -action.delta)


func _redo_rotate_hex(action: Dictionary) -> void:
	_apply_rotate_hex(action.hex, action.delta)
	# Re-strand the same wires the original rotation removed.
	var level: HexLevel = action.hex.level
	for w in action.get("deleted_wires", []):
		if level != null:
			level.wires.erase(w)
		_park_wire(w)


# Apply a rotation delta and re-route attached non-open wires. Shared
# between the live rotate command and undo/redo.
func _apply_rotate_hex(hex: HexNode, delta: int) -> void:
	hex.set_rotation_index(hex.rotation_index + delta)
	if hex.level != null:
		for w in hex.level.wires:
			if w.is_open:
				continue
			if w.output_node == hex or w.input_node == hex:
				_rebuild_wire_cells(w)
	# Slot positions changed — rebuild the sidebar so the Slots section
	# (and any rotation-aware hints inside `build_config_ui`) reflects
	# the new physical edges.
	if _config_target == hex:
		_open_config_sidebar(hex)


# Returns the finalized wire (at the current level) whose cells include
# `axial`, or null.
func _wire_at_axial(axial: Vector2i) -> HexWire:
	for w in _current_level().wires:
		if w.contains_axial(axial):
			return w
	return null


# Delete the wire under the cursor (right-click on a wired empty cell).
func _try_delete_wire_under_mouse() -> void:
	var axial := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	var w := _wire_at_axial(axial)
	if w == null:
		return
	var level := _current_level()
	level.wires.erase(w)
	SfxManager.play("delete")
	_animate_wire_deletion(w)  # pop, thin to nothing, then park
	wire_deleted.emit(w)
	_push_undo({"type": "delete_wire", "wire": w, "level": level})


# Visual feedback for a user-deleted wire: a quick pop wider then a thin-out
# to zero width, after which the wire is parked (kept alive for undo). The
# tween is tracked so an undo mid-animation can cancel it (_restore_wire).
func _animate_wire_deletion(w: HexWire) -> void:
	if w.line == null:
		_park_wire(w)
		return
	var setter := func(f: float) -> void:
		if is_instance_valid(w.line):
			w.line.width = HexWire.WIDTH * f
		if is_instance_valid(w.error_line):
			w.error_line.width = HexWire.WIDTH * f
	var tw := create_tween()
	tw.tween_method(setter, 1.0, DELETE_FX_POP, DELETE_FX_POP_SECS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(setter, DELETE_FX_POP, 0.0, DELETE_FX_SHRINK_SECS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_wire_fx_tweens.erase(w)
		_park_wire(w))
	_wire_fx_tweens[w] = tw


# Hex nodes belonging to the level currently being viewed (excludes a
# blueprint preview parented under nodes_layer — those are tracked via
# `_blueprint_node`, not the level).
func _all_hex_nodes() -> Array:
	return _current_level().hexes.duplicate()


func _node_at_axial(coord: Vector2i, except: HexNode = null) -> HexNode:
	for n in _all_hex_nodes():
		if n == except:
			continue
		if n.axial == coord:
			return n
	return null


func _is_axial_occupied(coord: Vector2i, except: HexNode) -> bool:
	return _node_at_axial(coord, except) != null


# ── Cell occupancy (for wire routing) ───────────────────────────────────────

# True if `axial` is occupied by anything that blocks a wire from passing
# through: a placed hex (always), or a wire cell that isn't part of
# `except_wire`.
func _is_cell_blocked_for_wire(axial: Vector2i, except_wire: HexWire, level: HexLevel = null) -> bool:
	var lvl: HexLevel = level if level != null else _current_level()
	for h in lvl.hexes:
		if h.axial == axial:
			return true
	for w in lvl.wires:
		if w == except_wire:
			continue
		for cell in w.cells:
			if cell.axial == axial:
				return true
	return false


# ── Blueprint mode ──────────────────────────────────────────────────────────

func _enter_blueprint_fresh(script_class) -> void:
	# Refuse locked hex types regardless of how the user picked them.
	# The palette emits `hex_selected` only for unlocked scripts, but the
	# editor reaches this method via other paths (clone, paste) where the
	# script may not be in the unlocked set yet.
	var path: String = script_class.resource_path
	if not path.is_empty() and not SaveManager.is_hex_unlocked(path):
		return
	# Preserve `_blueprint_rotation` across calls (Factorio: rotation sticks).
	_exit_blueprint_mode()
	_cancel_active_wire()
	_close_config_sidebar()
	_blueprint_class = script_class
	_blueprint_carried = false
	var preview: HexNode = HexNode.from_script(script_class)
	preview._pickable = false  # consumed by _ready when building areas
	nodes_layer.add_child(preview)
	preview.set_rotation_index(_blueprint_rotation)
	preview.modulate = BLUEPRINT_TINT_OK
	_blueprint_node = preview
	_disable_pickup_on_placed()
	_snap_blueprint_to_mouse()
	palette_bar.set_active_hex(_blueprint_class)


# Clone an existing placed hex onto the cursor (single-shot placement).
# Settings and rotation are copied; the original stays put.
func _enter_blueprint_clone(source: HexNode) -> void:
	if source.is_fixture:
		return
	_exit_blueprint_mode()
	_cancel_active_wire()
	_close_config_sidebar()
	_blueprint_class = null
	_blueprint_carried = true  # carried path on commit → no auto-respawn
	_blueprint_rotation = source.rotation_index
	var copy: HexNode = source.clone()
	copy._pickable = false
	nodes_layer.add_child(copy)
	copy.set_rotation_index(_blueprint_rotation)
	copy.modulate = BLUEPRINT_TINT_OK
	_blueprint_node = copy
	_disable_pickup_on_placed()
	_snap_blueprint_to_mouse()


func _exit_blueprint_mode() -> void:
	var was_active := _blueprint_node != null
	if _blueprint_node:
		# Both fresh previews and clones are throwaway when cancelled —
		# the clone's source is still on the grid untouched.
		_blueprint_node.queue_free()
	_blueprint_node = null
	_blueprint_class = null
	_blueprint_carried = false
	_enable_pickup_on_placed()
	palette_bar.set_active_hex(_blueprint_class)
	# Only a real cancel counts — this gets called defensively from
	# several flows that never had a preview up.
	if was_active:
		blueprint_mode_exited.emit()


func _disable_pickup_on_placed() -> void:
	for n in _all_hex_nodes():
		if n == _blueprint_node:
			continue
		n.set_pickable(false)


func _enable_pickup_on_placed() -> void:
	for n in _all_hex_nodes():
		n.set_pickable(true)


func _snap_blueprint_to_mouse() -> void:
	if _blueprint_node == null:
		return
	_blueprint_axial = HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	_blueprint_node.set_axial(_blueprint_axial)
	_refresh_blueprint_tint()


func _refresh_blueprint_tint() -> void:
	if _blueprint_node == null:
		return
	var blocked := _is_axial_occupied(_blueprint_axial, _blueprint_node)
	_blueprint_node.modulate = BLUEPRINT_TINT_BLOCKED if blocked else BLUEPRINT_TINT_OK


func _rotate_blueprint(ccw: bool = false) -> void:
	if _blueprint_node == null:
		return
	var delta := -1 if ccw else 1
	_blueprint_rotation = posmod(_blueprint_rotation + delta, 6)
	_blueprint_node.set_rotation_index(_blueprint_rotation)


func _commit_blueprint() -> void:
	if _blueprint_node == null:
		return
	if _is_axial_occupied(_blueprint_axial, _blueprint_node):
		SfxManager.play("error")
		return  # collision — click is a no-op
	# Tutorial gate: placement only lands on the highlighted target
	# tile during the placement step (the marker flashes red on a
	# rejected cell so the no-op reads as intentional).
	if not TutorialManager.allows_placement(_blueprint_axial):
		return

	if _blueprint_carried:
		# Single-shot placement (clone path).
		var placed := _blueprint_node
		placed.modulate = Color.WHITE
		placed.set_axial(_blueprint_axial)
		_spawn_counter += 1
		placed.name = "HexNode_%d" % _spawn_counter
		placed.level = _current_level()
		_current_level().hexes.append(placed)
		_wire_node_signals(placed)
		_blueprint_node = null
		_blueprint_carried = false
		_enable_pickup_on_placed()
		placed.set_pickable(true)
		_push_undo({"type": "place_hex", "hex": placed, "level": placed.level})
		placed.pop_in()
		var ce := _placed_connection_edge(placed)
		if ce >= 0:
			_fire_placement_connect_fx(placed, ce)
		else:
			SfxManager.play("place")
		hex_placed.emit(placed, _blueprint_axial)
		return

	# Fresh placement: keep the preview as the placed node, then spawn a new
	# preview at the same rotation for Factorio-style repeat placement.
	var placed_new := _blueprint_node
	placed_new.modulate = Color.WHITE
	placed_new.set_axial(_blueprint_axial)
	_spawn_counter += 1
	placed_new.name = "HexNode_%d" % _spawn_counter
	placed_new.level = _current_level()
	_current_level().hexes.append(placed_new)
	_wire_node_signals(placed_new)
	placed_new.set_pickable(true)
	_push_undo({"type": "place_hex", "hex": placed_new, "level": placed_new.level})
	placed_new.pop_in()
	var ce_new := _placed_connection_edge(placed_new)
	if ce_new >= 0:
		_fire_placement_connect_fx(placed_new, ce_new)
	else:
		SfxManager.play("place")
	hex_placed.emit(placed_new, _blueprint_axial)

	var cls = _blueprint_class
	_blueprint_node = null  # detach so _exit doesn't free the placed node
	_enter_blueprint_fresh(cls)


# ── Wiring (drag model) ─────────────────────────────────────────────────────
#
# Wiring is a drag: left-press on a slot starts a wire from that slot
# (or, if pressed on an open wire's tail cell, reactivates that wire for
# continued routing). The wire's tail follows the cursor while the
# button is held. Left-release dispatches via `_finalize_at_cursor`:
#
#   • released on a compatible slot         → finalize to that slot
#   • released on a hex body (not source)   → finalize to nearest slot
#   • released on another open wire's tail  → merge the two wires
#   • released on the source hex            → cancel
#   • released on an empty cell             → finalize open (planning)

func _on_slot_pressed(node: HexNode, edge: int, is_output: bool) -> void:
	if _blueprint_node != null:
		return  # blueprint mode owns the mouse
	if _active_wire != null:
		return  # already in a drag — can't start a new one mid-press
	_start_wiring(node, edge, is_output)


# Left-press on a hex's body (the click missed all its slots) opens the
# configuration sidebar for that hex. Body presses don't start wires —
# wires only begin on slot presses.
func _on_hex_body_pressed(node: HexNode) -> void:
	if _blueprint_node != null:
		return
	if _active_wire != null:
		return
	_open_config_sidebar(node)


# Double-click pickup: lift this hex into a single-shot "move" so the
# player can re-place it elsewhere with its config / rotation / inner
# level intact. The original is parked and shown translucent as a ghost
# at its origin; LMB places once and exits, RMB cancels and returns the
# hex, and a completed move is one undo entry. Distinct from clipboard
# stamping (Ctrl+X/C/V), which repeat-places and leaves no ghost.
# Ignored for fixtures (level pivots) and while another canvas mode owns
# the cursor.
func _pickup_hex(node: HexNode) -> void:
	if node == null or node.is_fixture:
		return
	if not _stamp_previews.is_empty() or _blueprint_node != null or _active_wire != null:
		return
	# Bypassing `_delete_hex` below means we own its guards: refuse if the
	# hex isn't on a level, or if the player is currently inside its inner
	# level (parking it would strand them).
	if node.level == null:
		return
	if node.inner_level != null and _level_stack.has(node.inner_level):
		return
	if _config_target != null:
		_close_config_sidebar()
	# Serialize the single hex for the cursor-following preview (and keep
	# the clipboard / Ctrl+V path consistent).
	_replace_selection([node] as Array[HexNode])
	var payload := _build_selection_payload("cut")
	_last_copied_payload = payload
	DisplayServer.clipboard_set(BlueprintCodec.encode(payload))
	_clear_selection()
	_begin_stamp(payload)
	# `_begin_stamp` bails on an unstampable payload; don't strand the
	# original if so.
	if _stamp_previews.is_empty():
		return
	# Park the original WITHOUT `_delete_hex` — that emits `hex_deleted`,
	# which the tutorial treats as "a required hex was destroyed". A move
	# isn't a delete. `_apply_delete_hex` just parks hex + wires (no signal,
	# no undo) and preserves the inner level on the node.
	var removed_wires: Array[HexWire] = []
	for w in node.level.wires:
		if w.output_node == node or w.input_node == node:
			removed_wires.append(w)
	var level: HexLevel = node.level
	_apply_delete_hex(node, level, removed_wires)
	_pickup_record = {"hex": node, "level": level, "removed_wires": removed_wires}
	# Re-show the parked original in place as the ghost (it sits at its own
	# axial with its real rotation / config), non-pickable + translucent.
	node.visible = true
	node.modulate = PICKUP_GHOST_TINT
	node.set_pickable(false)
	_pickup_active = true
	SfxManager.play("pickup")


# Restore the picked-up original to its level (model only — the caller
# tears the stamp previews down via `_exit_stamp_mode`). Pushes no undo
# entry: a cancelled move is a net no-op.
func _cancel_pickup() -> void:
	if not _pickup_active:
		return
	var rec := _pickup_record
	var hex: HexNode = rec.hex
	hex.modulate = Color.WHITE
	rec.level.hexes.append(hex)
	_restore_hex(hex)
	for w in rec.removed_wires:
		rec.level.wires.append(w)
		_restore_wire(w)
	_pickup_active = false
	_pickup_record = {}


func _start_wiring(node: HexNode, edge: int, is_output: bool) -> void:
	_active_wire = HexWire.from_anchor(node, edge, is_output)
	var line := Line2D.new()
	line.width = WIRE_WIDTH
	line.default_color = WIRE_PREVIEW_COLOR
	HexWire.attach_shader_to(line)
	connections_layer.add_child(line)
	_active_wire.line = line
	var err_line := Line2D.new()
	err_line.width = WIRE_WIDTH
	err_line.default_color = WIRE_ERROR_COLOR
	HexWire.attach_shader_to(err_line)
	connections_layer.add_child(err_line)
	_active_wire.error_line = err_line
	_ensure_chain_overlay()
	_wire_chain_overlay.set_wire(_active_wire)
	_route_active_wire_to_mouse()


# Lazily create the routing wireframe overlay, parented above the wire
# lines in connections_layer so its lock icons stay visible.
func _ensure_chain_overlay() -> void:
	if _wire_chain_overlay != null:
		return
	_wire_chain_overlay = WireChainOverlay.new()
	connections_layer.add_child(_wire_chain_overlay)


# Returns a finalized open wire whose tail cell is at `axial`, or null.
# Open wires expose their tail cell as a virtual connection point —
# pressing on it reactivates the wire for further routing, and dragging
# another wire to it merges the two.
func _open_wire_endpoint_at(axial: Vector2i) -> HexWire:
	for w in _current_level().wires:
		if not w.is_open:
			continue
		if w.cells.is_empty():
			continue
		if w.cells[w.cells.size() - 1].axial == axial:
			return w
	return null


# Pick up an existing open wire as the active wire so the user can
# continue routing from its tail. All current cells are anchored.
func _reactivate_open_wire(w: HexWire) -> void:
	_current_level().wires.erase(w)
	w.is_open = false
	w.is_finalized = false
	w.is_stuck = false
	w.anchored_count = w.cells.size()
	if w.line:
		w.line.default_color = WIRE_PREVIEW_COLOR
	if w.error_line == null:
		var err_line := Line2D.new()
		err_line.width = WIRE_WIDTH
		err_line.default_color = WIRE_ERROR_COLOR
		HexWire.attach_shader_to(err_line)
		connections_layer.add_child(err_line)
		w.error_line = err_line
	_active_wire = w
	_ensure_chain_overlay()
	_wire_chain_overlay.set_wire(w)
	_route_active_wire_to_mouse()


func _cancel_active_wire() -> void:
	if _active_wire == null:
		return
	if _active_wire.line:
		_active_wire.line.queue_free()
	if _active_wire.error_line:
		_active_wire.error_line.queue_free()
	if _wire_chain_overlay:
		_wire_chain_overlay.clear()
	_set_wire_hover_hex(null)
	_active_wire = null


# Finalize the active wire as unconnected — ends at the last cell's
# center. Used when the user left-clicks on empty canvas during wiring
# (cable-management planning).
func _finalize_active_wire_open() -> void:
	if _active_wire == null:
		return
	if _active_wire.cells.is_empty():
		_cancel_active_wire()
		return
	# An illegal (stuck/red) wire can't be left dangling: drop the un-routable
	# tail back to the last locked chain point, or remove the wire entirely
	# (back to the source hex) when nothing was locked. A legal stub left in
	# open space is untouched — that stays as a cable-planning stub.
	if _active_wire.is_stuck:
		_active_wire.truncate_to_anchored()
		if _active_wire.cells.is_empty():
			_cancel_active_wire()
			return
	# Force the last cell to be a dangling tail (no exit_edge).
	var last = _active_wire.cells[_active_wire.cells.size() - 1]
	last.exit_edge = -1
	_active_wire.finalize_open()
	_commit_active_wire()


# Toggle a chain point under the cursor. Over an already-locked cell this
# unlocks it (and any later chain points), re-opening the tail; otherwise
# it pins the current tail cell. The wire keeps its preview color — the
# lock markers live on the chain overlay.
func _anchor_active_wire() -> void:
	if _active_wire == null:
		return
	var cursor := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	var locked := false
	if not _active_wire.unlock_from_axial(cursor):
		_active_wire.add_lock()
		locked = true
	_route_active_wire_to_mouse()
	if locked:
		wire_locked.emit()
	if _wire_chain_overlay:
		_wire_chain_overlay.set_wire(_active_wire)
		# Feedback on a fresh pin: pop the cyan cell and play the place cue.
		if locked:
			var pins := _active_wire.locked_axials()
			if not pins.is_empty():
				_wire_chain_overlay.pop_cell(pins.back())
			SfxManager.play("place")


# Re-route the active wire's tail to follow the cursor (or the cursor's
# nearest compatible slot when hovering over a hex).
func _route_active_wire_to_mouse() -> void:
	if _active_wire == null:
		return
	var target := _compute_routing_target()
	_route_active_wire_to(target)
	_active_wire.paint(_mouse_world())
	if _wire_chain_overlay:
		_wire_chain_overlay.queue_redraw()
	_update_wire_hover_highlight()


# Brighten the hex the cursor is over while routing, when it's a valid
# connection target (not the anchor hex, and it has a compatible slot).
func _update_wire_hover_highlight() -> void:
	var mouse_axial := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	var hex := _node_at_axial(mouse_axial)
	if hex != null and hex != _active_wire.anchor_node \
			and _nearest_compatible_slot_edge(hex) != -1:
		_set_wire_hover_hex(hex)
	else:
		_set_wire_hover_hex(null)


# Move the wire hover highlight to `hex` (or clear it with null). No-op when
# the target is unchanged so we don't re-tween the body colour every frame.
func _set_wire_hover_hex(hex: HexNode) -> void:
	if hex == _wire_hover_hex:
		return
	if _wire_hover_hex != null and is_instance_valid(_wire_hover_hex):
		_wire_hover_hex.set_wire_target_highlight(false)
	_wire_hover_hex = hex
	if hex != null:
		hex.set_wire_target_highlight(true)


# Where should the wire's tail aim? If the cursor is over an empty cell
# or the source hex itself, target that cell. If it's over another hex,
# aim at the approach cell of that hex's compatible slot closest to the
# cursor — so the wire glides toward whichever input/output the user
# would commit to with a click.
func _compute_routing_target() -> Vector2i:
	var mouse_axial := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	var hex := _node_at_axial(mouse_axial)
	if hex == null or hex == _active_wire.anchor_node:
		return mouse_axial
	var slot_edge := _nearest_compatible_slot_edge(hex)
	if slot_edge == -1:
		return mouse_axial  # no compatible slot — let routing stop near it
	var phys := hex.physical_edge(slot_edge)
	return hex.axial + HexMath.EDGE_DELTAS[phys]


# Returns the logical edge of the slot on `hex` closest to the mouse that
# is compatible with the active wire's anchor (output if anchor is input,
# input if anchor is output). Returns -1 if `hex` has none.
func _nearest_compatible_slot_edge(hex: HexNode) -> int:
	var want_output := not _active_wire.anchor_is_output
	var candidate_edges: Array = hex.output_edges if want_output else hex.input_edges
	if candidate_edges.is_empty():
		return -1
	var mouse := _mouse_world()
	var best_edge := -1
	var best_d := INF
	for e in candidate_edges:
		var d := hex.slot_world_position(e).distance_to(mouse)
		if d < best_d:
			best_d = d
			best_edge = e
	return best_edge


# Hit-test for a slot near `pos`. Returns a dict {node, edge, is_output}
# if a slot is found within SLOT_PICK_RADIUS, or null otherwise.
# Excludes `except_node` from the search.
func _hit_slot_at(pos: Vector2, except_node: HexNode = null):
	# Wire-drop snap target: the precise trapezoid Area2D on each edge.
	# We query physics space for areas containing `pos`, then look up
	# the edge mapping on each hex and pick the closest active slot.
	# Drag-start uses the forgiving capsule on the anchor (handled
	# elsewhere); the trapezoid here keeps the drop endpoint precise.
	var space := world.get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hits := space.intersect_point(params, 32)
	var best_hit = null
	var best_dist := INF
	for hit in hits:
		var area = hit.get("collider")
		if not (area is Area2D):
			continue
		var hex = area.get_parent()
		if not (hex is HexNode):
			continue
		if hex == except_node:
			continue
		var phys_idx: int = hex.edge_index_for_area(area)
		if phys_idx == -1:
			continue
		if not hex._active_edge_map.has(phys_idx):
			continue
		var mapping = hex._active_edge_map[phys_idx]
		var slot_pos = hex.slot_world_position(mapping.logical)
		var d: float = slot_pos.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_hit = {
				"node": hex,
				"edge": mapping.logical,
				"is_output": mapping.is_out,
			}
	return best_hit


# Greedy-route the active wire toward `target`. The anchored prefix is
# preserved; the LAST anchored cell's `exit_edge` is recomputed each
# call (it's the seed for the dynamic tail). Earlier anchored cells
# keep their frozen exit_edges.
func _route_active_wire_to(target: Vector2i) -> void:
	var w := _active_wire
	w.truncate_to_anchored()
	w.is_stuck = false

	var visited: Dictionary = {}
	for cell in w.cells:
		visited[cell.axial] = true

	# Bootstrap the first cell from the anchor slot if the wire is empty.
	if w.cells.is_empty():
		var anchor_phys := w.anchor_node.physical_edge(w.anchor_edge)
		var first_axial: Vector2i = w.anchor_node.axial + HexMath.EDGE_DELTAS[anchor_phys]
		if _is_cell_blocked_for_wire(first_axial, w):
			# Can't even leave the source hex.
			w.is_stuck = true
			return
		w.cells.append(HexWire.make_cell(first_axial, (anchor_phys + 3) % 6, -1))
		visited[first_axial] = true

	# Grow the tail toward `target`. In open space we take a single step
	# that strictly reduces hex-distance (a straight glide). When every
	# closer neighbour is blocked we're up against an obstacle: instead of
	# wandering the least-bad way around (the old greedy "snake"), we look
	# ahead at most ROUTE_LOOKAHEAD_HEXES cells for a detour that lands us
	# strictly closer again. If none exists within that budget we halt and
	# mark the wire stuck — `paint()` then renders the whole thing red.
	var steps := 0
	while steps < ROUTE_MAX_CELLS:
		var last_idx := w.cells.size() - 1
		var current = w.cells[last_idx]
		if current.axial == target:
			current.exit_edge = -1
			break

		var cur_dist := HexMath.axial_distance(current.axial, target)
		var step_dir := _best_progress_dir(current, target, visited, cur_dist)
		var path: Array = [step_dir] if step_dir != -1 \
			else _bounded_detour_path(current, target, visited, cur_dist)

		if path.is_empty():
			# No way forward within the look-ahead budget — stop and go red.
			current.exit_edge = -1
			w.is_stuck = true
			break

		# Lay down the chosen step (one cell for a straight glide, or the
		# whole short detour found around an obstacle).
		for dir in path:
			var head = w.cells[w.cells.size() - 1]
			head.exit_edge = dir
			var next_axial: Vector2i = head.axial + HexMath.EDGE_DELTAS[dir]
			w.cells.append(HexWire.make_cell(next_axial, (dir + 3) % 6, -1))
			visited[next_axial] = true
			steps += 1


# Direction of the unblocked, unused neighbour of `cell` that lands
# strictly closer to `target` than `cell` is now (the biggest single-step
# gain). Returns -1 when the straight path is blocked — the caller then
# tries a bounded detour. `cur_dist` is `cell`'s current hex-distance.
func _best_progress_dir(cell: Dictionary, target: Vector2i, visited: Dictionary, cur_dist: int) -> int:
	var best_dir := -1
	var best_dist := cur_dist
	for dir in 6:
		if dir == cell.enter_edge:
			continue
		var neighbor: Vector2i = cell.axial + HexMath.EDGE_DELTAS[dir]
		if visited.has(neighbor):
			continue
		if _is_cell_blocked_for_wire(neighbor, _active_wire):
			continue
		var d := HexMath.axial_distance(neighbor, target)
		if d < best_dist:
			best_dist = d
			best_dir = dir
	return best_dir


# Breadth-first search up to ROUTE_LOOKAHEAD_HEXES cells out from `cell`,
# returning the shortest sequence of step directions that reaches a cell
# strictly closer to `target` than `cell` is now — i.e. a way around the
# obstacle that resumes progress. Returns an empty array if no such detour
# exists within the budget (the wire is boxed in). Cells already used by
# the wire (`visited`) and blocked cells are excluded.
func _bounded_detour_path(cell: Dictionary, target: Vector2i, visited: Dictionary, cur_dist: int) -> Array:
	var seen: Dictionary = {cell.axial: true}
	var frontier: Array = [{"axial": cell.axial, "path": []}]
	for _depth in ROUTE_LOOKAHEAD_HEXES:
		var next_frontier: Array = []
		var best_path: Array = []
		var best_dist := cur_dist
		for entry in frontier:
			for dir in 6:
				var nb: Vector2i = entry.axial + HexMath.EDGE_DELTAS[dir]
				if seen.has(nb) or visited.has(nb):
					continue
				if _is_cell_blocked_for_wire(nb, _active_wire):
					continue
				seen[nb] = true
				var step_path: Array = entry.path.duplicate()
				step_path.append(dir)
				var d := HexMath.axial_distance(nb, target)
				if d < best_dist:
					best_dist = d
					best_path = step_path
				next_frontier.append({"axial": nb, "path": step_path})
		if not best_path.is_empty():
			return best_path  # shortest detour wins (closest at this depth)
		frontier = next_frontier
	return []


# Try to bind the active wire's open end to the clicked slot.
func _try_finalize_wiring(node: HexNode, edge: int, is_output: bool) -> void:
	var w := _active_wire
	# Same direction (two outputs / two inputs) — incompatible.
	if is_output == w.anchor_is_output:
		return
	# Same hex on both ends — self-loop disallowed.
	if node == w.anchor_node:
		return

	var sink_phys := node.physical_edge(edge)
	var approach_axial: Vector2i = node.axial + HexMath.EDGE_DELTAS[sink_phys]

	# Source and sink are direct neighbors? Use the zero-cell shortcut.
	if approach_axial == w.anchor_node.axial:
		var anchor_phys := w.anchor_node.physical_edge(w.anchor_edge)
		if w.anchor_node.axial + HexMath.EDGE_DELTAS[anchor_phys] != node.axial:
			# They aren't actually adjacent on this side — refuse.
			return
		w.cells.clear()
		w.finalize_with(node, edge)
		_commit_active_wire()
		return

	# Otherwise we need a route that ends with a cell at `approach_axial`
	# whose exit_edge points into `node` ( = (sink_phys + 3) % 6 ).
	_route_active_wire_to(approach_axial)
	if w.cells.is_empty():
		return
	var last = w.cells[w.cells.size() - 1]
	if last.axial != approach_axial:
		return  # routing didn't reach the sink's approach cell
	# Set the last cell's exit toward the sink hex.
	last.exit_edge = (sink_phys + 3) % 6
	w.finalize_with(node, edge)
	_commit_active_wire()


# Dispatch a left-release at the current cursor position. Tries the
# most-specific match first (slot → body → open-wire tail → empty cell),
# falling back to an open finalize when nothing better lands.
func _finalize_at_cursor() -> void:
	if _active_wire == null:
		return
	var mouse := _mouse_world()
	var axial := HexMath.world_to_axial(mouse, HexNode.HEX_SIZE)

	# Released back over the source hex itself? Cancel (matches Esc).
	if _node_at_axial(axial) == _active_wire.anchor_node:
		_cancel_active_wire()
		return

	# Released near a slot on another hex? Try to bind to it.
	var slot_hit = _hit_slot_at(mouse, _active_wire.anchor_node)
	if slot_hit:
		_try_finalize_wiring(slot_hit.node, slot_hit.edge, slot_hit.is_output)
		if _active_wire:
			_finalize_active_wire_open()  # routing failed — keep as open
		return

	# Released on a hex body (not the source)? Bind to its nearest
	# compatible slot.
	var hex := _node_at_axial(axial)
	if hex != null:
		var edge := _nearest_compatible_slot_edge(hex)
		if edge != -1:
			var want_output := not _active_wire.anchor_is_output
			_try_finalize_wiring(hex, edge, want_output)
			if _active_wire:
				_finalize_active_wire_open()
			return
		_finalize_active_wire_open()
		return

	# Released on the tail cell of another open wire? Merge.
	var open_w := _open_wire_endpoint_at(axial)
	if open_w != null and open_w != _active_wire:
		if _try_merge_with_open_endpoint(open_w):
			return
		# Merge couldn't go through (incompatible / not adjacent) —
		# fall through to open finalize.

	# Plain empty cell: leave the wire as an unconnected stub.
	_finalize_active_wire_open()


# Merge the active wire with `open_w`. Their orientations must be
# opposite (one anchored at an output, the other at an input). The
# active wire's last cell must be axial-adjacent to `open_w`'s tail.
# On success, the active wire ends up finalized from one anchor slot
# to the other, and `open_w` is removed.
func _try_merge_with_open_endpoint(open_w: HexWire) -> bool:
	var active := _active_wire
	if active.anchor_is_output == open_w.anchor_is_output:
		return false
	if active.cells.is_empty() or open_w.cells.is_empty():
		return false

	var active_last = active.cells[active.cells.size() - 1]
	var open_tail = open_w.cells[open_w.cells.size() - 1]
	var dir := HexMath.step_direction(active_last.axial, open_tail.axial)
	if dir == -1:
		return false

	# Active's last cell now exits toward open's tail cell.
	active_last.exit_edge = dir

	# Build the merged cell that sits at open's tail axial. It enters
	# from the side adjacent to active's last cell, and exits toward
	# open's previous cell (if any).
	var merged_enter := (dir + 3) % 6
	var merged_exit := -1
	if open_w.cells.size() >= 2:
		# `open_tail.enter_edge` is the side of the tail cell adjacent
		# to open's second-to-last cell — exactly where the merged wire
		# wants to exit on its way to open's anchor.
		merged_exit = open_tail.enter_edge
	active.cells.append(HexWire.make_cell(open_tail.axial, merged_enter, merged_exit))

	# Walk open's earlier cells in reverse, flipping enter/exit on each
	# (we're traversing them in the opposite direction now).
	for i in range(open_w.cells.size() - 2, -1, -1):
		var orig = open_w.cells[i]
		active.cells.append({
			"axial": orig.axial,
			"enter_edge": orig.exit_edge,
			"exit_edge": orig.enter_edge,
		})

	# Bind the other endpoint to open's anchor slot.
	if active.anchor_is_output:
		active.input_node = open_w.anchor_node
		active.input_edge = open_w.anchor_edge
	else:
		active.output_node = open_w.anchor_node
		active.output_edge = open_w.anchor_edge
	active.is_finalized = true
	active.is_open = false
	active.is_stuck = false

	_dispose_wire_visuals(open_w)
	_current_level().wires.erase(open_w)

	_commit_active_wire()
	return true


# Promote the active wire into the persistent `wires` list.
func _commit_active_wire() -> void:
	var w := _active_wire
	var level := _current_level()

	# An input holds at most one source. Drop any prior wire feeding the
	# same input slot — but only for non-open wires (open wires have no
	# bound input). For single-slot fixtures (Do, anchor) every side is
	# the same logical slot, so drop across the whole group.
	var overwritten: Array[HexWire] = []
	if not w.is_open and w.input_node != null:
		var keep: Array[HexWire] = []
		for existing in level.wires:
			if existing.input_node == w.input_node and (
					existing.input_edge == w.input_edge
					or w.input_node.exclusive_input_group):
				# Park (don't dispose) so undo can restore the wire this
				# replacement displaced — otherwise undoing the new wire
				# would leave the input with no source at all.
				_park_wire(existing)
				overwritten.append(existing)
			else:
				keep.append(existing)
		level.wires = keep

	w.line.default_color = WIRE_OPEN_COLOR if w.is_open else WIRE_COLOR
	if w.error_line:
		# Finalized wires never render error overlay.
		w.error_line.queue_free()
		w.error_line = null
	w.is_stuck = false
	w.paint(Vector2.ZERO)  # tail unused when finalized
	if _wire_chain_overlay:
		_wire_chain_overlay.clear()
	_set_wire_hover_hex(null)
	level.wires.append(w)
	_active_wire = null
	_push_undo({
		"type": "place_wire",
		"wire": w,
		"level": level,
		"overwritten": overwritten,
	})
	_fire_wire_connect_fx(w)
	wire_committed.emit(w)


# Feedback when a wire connects two hexes: both endpoints pop, flash the
# connected edge, and burst their slot particles. Open wires (no sink) don't
# connect to anything, so they're skipped.
func _fire_wire_connect_fx(w: HexWire) -> void:
	if w.is_open:
		return
	if w.input_node != null:
		_connect_fx(w.input_node, w.input_edge)
	if w.output_node != null:
		_connect_fx(w.output_node, w.output_edge)
	SfxManager.play("connect")


# Pop a hex, flash the connected edge, and burst its slot particles.
func _connect_fx(node: HexNode, edge: int) -> void:
	node.pop_in()
	node.flash_edge(edge)
	node.burst_slot_particles(edge)


# Snap a stamped open wire onto a hex when its dangling tail cell sits on
# the approach cell of a compatible, free slot. The open end is whichever
# endpoint the blueprint left unbound (loaded wires run output→input with
# anchor_is_output=true, so it's normally the input — but handle both).
func _auto_connect_open_wire(w: HexWire, level: HexLevel) -> bool:
	if not w.is_open or w.cells.is_empty():
		return false
	var need_output := w.output_node == null
	var need_input := w.input_node == null
	if need_output == need_input:
		return false  # both or neither bound — not a simple open stub
	var tail_axial: Vector2i = w.cells[w.cells.size() - 1].axial
	var bound_hex: HexNode = w.output_node if need_input else w.input_node
	# A slot whose approach cell is the tail lies on a neighbour of the tail.
	for dir in 6:
		var hex := _node_at_axial(tail_axial + HexMath.EDGE_DELTAS[dir])
		if hex == null or hex == bound_hex:
			continue  # empty cell, or would self-loop onto the bound end
		var edges: Array = hex.output_edges if need_output else hex.input_edges
		for e in edges:
			# The slot's approach cell must be exactly this tail cell.
			if hex.axial + HexMath.EDGE_DELTAS[hex.physical_edge(e)] != tail_axial:
				continue
			# Never steal an input that already has a source.
			if need_input and _input_slot_taken(hex, e, w, level):
				continue
			# Bind: tail cell exits toward the hex (`dir`), finalize_with
			# fills the correct end from anchor_is_output, repaint as solid.
			w.cells[w.cells.size() - 1].exit_edge = dir
			w.finalize_with(hex, e)
			w.line.default_color = WIRE_COLOR
			w.paint(Vector2.ZERO)
			_fire_wire_connect_fx(w)
			return true
	return false


# Whether a non-open wire (other than `except`) already feeds hex's input
# slot `edge`. Exclusive-input fixtures (Do / anchors) treat every input as
# the same slot, so any wire into them counts.
func _input_slot_taken(hex: HexNode, edge: int, except: HexWire, level: HexLevel) -> bool:
	for ex in level.wires:
		if ex == except or ex.is_open:
			continue
		if ex.input_node == hex and (ex.input_edge == edge or hex.exclusive_input_group):
			return true
	return false


func _dispose_wire_visuals(w: HexWire) -> void:
	if w.line:
		w.line.queue_free()
		w.line = null
	if w.error_line:
		w.error_line.queue_free()
		w.error_line = null


# Used by HexNode subclasses' `_input_source()` during text emission.
# Looks up wires on the queried node's own level, so recursion across
# inner levels (LetHex body, future Lambda/Match) routes through the
# correct per-level wire list.
func get_input_for(node: HexNode, edge: int) -> HexNode:
	if node.level == null:
		return null
	# Explicit wires win — but only when the wire actually has an
	# output endpoint. An "open" wire that the player anchored at the
	# input slot without dragging it to an output has
	# `output_node == null`; skip those so the adjacency check below
	# can still find an implicit connection (otherwise the validator
	# falsely reports the input as unwired even when an adjacent hex
	# is broadcasting into it).
	for w in node.level.wires:
		if w.input_node == node and w.input_edge == edge and w.output_node != null:
			return w.output_node
	# Adjacency fallback: if the neighbor hex on this input's physical edge
	# has an output edge facing back into us, treat it as an implicit
	# connection. Lets the user "slap" hexes next to each other without
	# routing a wire.
	var phys := node.physical_edge(edge)
	var neighbor_axial: Vector2i = node.axial + HexMath.EDGE_DELTAS[phys]
	for n in node.level.hexes:
		if n == node:
			continue
		if n.axial != neighbor_axial:
			continue
		var facing_phys := (phys + 3) % 6
		var facing_logical = (facing_phys - n.rotation_index + 6) % 6
		if facing_logical in n.output_edges:
			return n
		break  # one hex per cell — no further candidates
	return null


# A logical edge of `hex` that forms an immediate edge-to-edge connection with an
# adjacent hex (our input fed by a neighbour's output, or our output feeding a
# neighbour's input), or -1 if none. No explicit wire exists yet on a fresh drop,
# so this only finds the "slap two hexes together" case. Mirrors the adjacency
# rule in get_input_for(), checked in both directions.
func _placed_connection_edge(hex: HexNode) -> int:
	if hex.level == null:
		return -1
	for edge in hex.input_edges:
		if get_input_for(hex, edge) != null:  # neighbour broadcasts into us
			return edge
	for edge in hex.output_edges:  # we broadcast into a neighbour
		var phys := hex.physical_edge(edge)
		var na: Vector2i = hex.axial + HexMath.EDGE_DELTAS[phys]
		for n in hex.level.hexes:
			if n == hex or n.axial != na:
				continue
			var facing: int = ((phys + 3) % 6 - n.rotation_index + 6) % 6
			if facing in n.input_edges:
				return edge
			break  # one hex per cell
	return -1


# The hex adjacent to `hex` across logical `edge`, and that neighbour's facing
# logical edge, as [node, edge]; [] if the cell is empty.
func _connecting_neighbour(hex: HexNode, edge: int) -> Array:
	if hex.level == null:
		return []
	var phys := hex.physical_edge(edge)
	var na: Vector2i = hex.axial + HexMath.EDGE_DELTAS[phys]
	for n in hex.level.hexes:
		if n == hex or n.axial != na:
			continue
		return [n, ((phys + 3) % 6 - n.rotation_index + 6) % 6]
	return []


# Fire the "wired" feedback when a freshly placed hex lands edge-to-edge against
# a neighbour. The placed hex is already popped at the drop site, so it gets
# flash + burst; the neighbour it bonded to gets the full pop + flash + burst.
func _fire_placement_connect_fx(hex: HexNode, edge: int, play_sfx := true) -> void:
	hex.flash_edge(edge)
	hex.burst_slot_particles(edge)
	var nb := _connecting_neighbour(hex, edge)
	if not nb.is_empty():
		_connect_fx(nb[0], nb[1])
	if play_sfx:
		SfxManager.play("connect")


# ── Process: wire repaint ───────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# Repaint finalized wires of the current level (cheap; few wires). The
	# other levels' line2Ds are hidden, so their geometry doesn't matter.
	for w in _current_level().wires:
		w.paint(Vector2.ZERO)
	if _active_wire:
		_route_active_wire_to_mouse()
	if _blueprint_node:
		_snap_blueprint_to_mouse()
	if not _stamp_previews.is_empty():
		_snap_stamp_to_mouse()
	if _marquee_active:
		_refresh_marquee_visual()
	_refresh_live_preview()


# Re-emit the program's display text into the GeneratedText panel
# every frame, but only when the result actually changed. Lets the
# user see the canonical form update as they build (Phase 16: live
# text preview).
func _refresh_live_preview() -> void:
	if output_panel == null:
		return
	output_panel.set_generated_text(_display_text(_build_program_text()))


# ── World input ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# No modal gate needed here: an open modal pauses the tree
	# (ModalStack via _track_modal) and this PAUSABLE node then stops
	# receiving _unhandled_input entirely. Mouse events are also
	# absorbed by each dialog's backdrop `mouse_filter = STOP`.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.shift_pressed and not _marquee_active:
					_start_marquee(false)
				elif not _stamp_previews.is_empty():
					_commit_stamp()
				elif _blueprint_node:
					_commit_blueprint()
				elif _active_wire == null:
					# Empty-cell press: if this is the tail of an open
					# wire, reactivate it so the user can keep dragging
					# the wire from that point. Otherwise dismiss any
					# open config sidebar AND clear the selection —
					# plain LMB on empty canvas is the "deselect-all"
					# gesture (Shift+LMB still grows the selection).
					var axial := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
					var open_w := _open_wire_endpoint_at(axial)
					if open_w != null:
						_reactivate_open_wire(open_w)
					else:
						_close_config_sidebar()
						_clear_selection()
			else:
				# Release: commit a marquee (if dragging) or a wire (if
				# routing). The two are mutually exclusive — `_start_marquee`
				# cancels any in-flight wire on press.
				if _marquee_active and not _marquee_is_delete:
					_commit_marquee()
				elif _active_wire:
					_finalize_at_cursor()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if mb.shift_pressed and not _marquee_active:
					_start_marquee(true)
				elif _rmb_contextual_cancel():
					# Stamp / blueprint / wire / selection / config — the
					# shared cascade consumed the click. Flag it so the same
					# press doesn't also delete via the hex-body path.
					_rmb_cancelled_press = true
				else:
					# Right-click on empty canvas with nothing to cancel:
					# delete a wire here if any. Right-clicks on hex bodies
					# are captured by the body Area2D and routed via
					# `delete_requested`.
					_rmb_cancelled_press = false
					_try_delete_wire_under_mouse()
			else:
				# Release ends the press; clear the one-press cancel guard.
				_rmb_cancelled_press = false
				if _marquee_active and _marquee_is_delete:
					_commit_marquee()
		return

	# Keyboard input is decentralized: CanvasInputController owns the
	# canvas-context hotkeys (rotate/delete/clone/undo/clipboard/
	# Escape/dialogs), and the palette / tab strip / jobs panel /
	# output panel / top buttons / camera each handle their own
	# actions. Only mouse input stays here — RMB and LMB behavior
	# depends on stamp/blueprint/wire/selection/sidebar context that
	# only the editor sees as a whole.


# Rotate `hex` by `delta` as a single undoable command, auto-deleting any
# wire the rotation strands. Rotation re-routes the rotated hex's wires;
# any that can no longer reach their endpoint are now illegal (left red /
# is_stuck), so we remove them rather than leaving dead wires on the board.
# Only wires touching the rotated node are ever affected (its center stays
# fixed), which is exactly the "prioritize the rotated node" intent.
func _rotate_hex_command(node: HexNode, delta: int) -> void:
	_apply_rotate_hex(node, delta)
	var deleted: Array = []
	if node.level != null:
		for w in node.level.wires:
			if w.is_open:
				continue
			if w.is_stuck and (w.output_node == node or w.input_node == node):
				deleted.append(w)
		for w in deleted:
			node.level.wires.erase(w)
			_park_wire(w)
	_push_undo({
		"type": "rotate_hex",
		"hex": node,
		"delta": delta,
		"deleted_wires": deleted,
	})


# Re-run greedy routing for a finalized wire between its current endpoints.
# Used when one of the endpoints rotates so the wire's geometry follows
# the slot's new physical position.
func _rebuild_wire_cells(w: HexWire) -> void:
	if w.output_node == null or w.input_node == null:
		return
	# Use the wire's own level for blocking checks so undo / redo from a
	# different currently-displayed level still routes against the right
	# canvas.
	var level: HexLevel = w.output_node.level
	if level == null:
		level = w.input_node.level
	if level == null:
		return
	var out_phys := w.output_node.physical_edge(w.output_edge)
	var in_phys := w.input_node.physical_edge(w.input_edge)
	var start_axial: Vector2i = w.output_node.axial + HexMath.EDGE_DELTAS[out_phys]
	var target_axial: Vector2i = w.input_node.axial + HexMath.EDGE_DELTAS[in_phys]

	w.cells.clear()
	w.anchored_count = 0
	w.is_stuck = false

	# Direct adjacency (output's neighbor IS the input hex) — degenerate
	# zero-cell wire that paints as anchor-slot → sink-slot (same point).
	if start_axial == w.input_node.axial:
		return

	if _is_cell_blocked_for_wire(start_axial, w, level):
		w.is_stuck = true
		return

	w.cells.append(HexWire.make_cell(start_axial, (out_phys + 3) % 6, -1))
	var visited: Dictionary = {start_axial: true}
	var steps := 0
	while steps < ROUTE_MAX_CELLS:
		var last_idx := w.cells.size() - 1
		var current = w.cells[last_idx]
		if current.axial == target_axial:
			current.exit_edge = (in_phys + 3) % 6
			return
		var best_dir := -1
		var best_dist := INF
		for dir in 6:
			if dir == current.enter_edge:
				continue
			var neighbor: Vector2i = current.axial + HexMath.EDGE_DELTAS[dir]
			if visited.has(neighbor):
				continue
			if _is_cell_blocked_for_wire(neighbor, w, level):
				continue
			var d := HexMath.axial_distance(neighbor, target_axial)
			if d < best_dist:
				best_dist = d
				best_dir = dir
		if best_dir == -1:
			current.exit_edge = -1
			w.is_stuck = true
			return
		current.exit_edge = best_dir
		var next_axial: Vector2i = current.axial + HexMath.EDGE_DELTAS[best_dir]
		var next_enter: int = (best_dir + 3) % 6
		w.cells.append(HexWire.make_cell(next_axial, next_enter, -1))
		visited[next_axial] = true
		steps += 1


func _try_clone_under_mouse() -> void:
	var node := _node_under_mouse()
	if node == null or node.is_fixture:
		return
	_enter_blueprint_clone(node)


func _try_delete_under_mouse() -> void:
	var node := _node_under_mouse()
	if node == null or node.is_fixture:
		return
	_delete_hex(node)  # plays the delete cue on a real removal


func _node_under_mouse() -> HexNode:
	var coord := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	return _node_at_axial(coord)


# ── Level navigation ────────────────────────────────────────────────────────

func _try_descend() -> void:
	_descend_into(_node_under_mouse())


# Descend into `hex`'s inner level (creating it on first entry). Shared by
# the Q-key path (`_try_descend`, hex under the mouse) and the config
# panel's Descend button (the configured hex). A null / non-descendable
# hex is a no-op.
func _descend_into(hex: HexNode) -> void:
	if hex == null:
		return
	if not hex.has_inner_level():
		return
	if not hex.can_descend(self):
		return
	if hex.inner_level == null:
		_create_inner_level_for(hex)
	_push_level(hex.inner_level)


func _try_ascend() -> void:
	if _level_stack.size() <= 1:
		return
	_pop_level()


func _create_inner_level_for(hex: HexNode) -> void:
	# The tab builds the level node + anchor (hidden until descended
	# into); the editor only wires its own signal handlers.
	var level := _active_tab().create_inner_level_for(hex)
	_wire_node_signals(level.anchor)


func _push_level(target: HexLevel, animate: bool = true) -> void:
	# Stash the current view, hide the level, switch.
	_exit_stamp_mode()
	_cancel_marquee()
	_clear_selection()
	var current := _current_level()
	if hex_camera != null:
		current.world_position = hex_camera.position
		current.world_scale = hex_camera.zoom.x
	current.set_active(false)
	_level_stack.append(target)
	target.set_active(true)
	_apply_level_view(target, animate)
	if animate:
		_fade_in_level(target)
	_close_config_sidebar()
	_update_breadcrumb()


func _pop_level(animate: bool = true) -> void:
	_exit_stamp_mode()
	_cancel_marquee()
	_clear_selection()
	var current := _current_level()
	if hex_camera != null:
		current.world_position = hex_camera.position
		current.world_scale = hex_camera.zoom.x
	current.set_active(false)
	_level_stack.pop_back()
	var target := _current_level()
	target.set_active(true)
	_apply_level_view(target, animate)
	if animate:
		_fade_in_level(target)
	_close_config_sidebar()
	_update_breadcrumb()


# Move the camera to a level's stored view. `animate` tweens the pan +
# zoom (descend / ascend / breadcrumb jump); the default snaps instantly,
# which keeps tab-switching and per-level state round-trips deterministic.
func _apply_level_view(level: HexLevel, animate: bool = false) -> void:
	# `HexLevel.world_position` / `world_scale` now describe the
	# camera state for that level — same semantics, lifted off the
	# old `world` Node2D transform.
	if hex_camera != null:
		if animate:
			_tween_camera_to(level.world_position, level.world_scale)
		else:
			hex_camera.position = level.world_position
			hex_camera.zoom = Vector2.ONE * level.world_scale
	_refresh_connection_visuals()


# Tween the camera's pan + zoom toward a level's stored view. Reuses the
# `_slerp_camera_to_origin` easing; a fresh transition kills the prior
# one so rapid Q / E presses don't stack competing tweens.
func _tween_camera_to(pos: Vector2, zoom_scalar: float, dur: float = 0.2) -> void:
	if hex_camera == null:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(hex_camera, "position", pos, dur)
	_transition_tween.tween_property(hex_camera, "zoom", Vector2.ONE * zoom_scalar, dur)


# Fade the incoming level in over the camera move. `set_active(true)`
# already reset its modulate to opaque, so we drop alpha to 0 and tween
# back up; a prior fade is killed first.
func _fade_in_level(level: HexLevel, dur: float = 0.2) -> void:
	if level == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	level.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(level, "modulate:a", 1.0, dur)


func _update_breadcrumb() -> void:
	if breadcrumb == null:
		return
	var labels: Array = []
	for i in _level_stack.size():
		if i == 0:
			labels.append("main")
		else:
			var p := _level_stack[i].parent_hex
			labels.append(p.level_label() if p != null else "?")
	breadcrumb.set_labels(labels)


# Pop levels until `target_idx` is the top of the stack. Intermediate
# pops snap instantly (each keeps its own level's saved view consistent);
# only the final hop animates, so a breadcrumb jump lerps the camera
# toward the target fixture instead of snapping.
func _jump_to_level(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= _level_stack.size():
		return
	while _level_stack.size() - 1 > target_idx:
		_pop_level(_level_stack.size() - 2 == target_idx)


# ── Help overlay ───────────────────────────────────────────────────────────

func _show_help_overlay() -> void:
	if _keybindings_dialog == null:
		_keybindings_dialog = KEYBINDINGS_DIALOG_SCENE.instantiate() as Control
		_pause_menu.get_parent().add_child(_keybindings_dialog)
		_track_modal(_keybindings_dialog)
	_keybindings_dialog.open()


# ── Config sidebar ──────────────────────────────────────────────────────────

func _open_config_sidebar(node: HexNode) -> void:
	if config_sidebar:
		config_sidebar.open_for(node)
		# Enable the panel's ascend / descend buttons for the depth we're
		# at and whether this hex has an inner level to enter. Uses the
		# actual clicked node (a delegating inner anchor descends into its
		# own continuation, e.g. ListAnchor; leaf anchors stay disabled).
		config_sidebar.set_nav_state(
			_level_stack.size() > 1,
			node.has_inner_level() and node.can_descend(self))
	_config_target = node
	# Opening the config sidebar IS a single-hex selection — the
	# configured hex gets the same cyan tint as a marquee-selected
	# one. Replaces any prior selection so the visual stays anchored
	# on what the player is editing.
	_replace_selection([node] as Array[HexNode])
	config_opened.emit(node)


## True while the per-hex config sidebar is showing a hex. Lets the
## tutorial skip its "close the config" step when the panel is already
## gone (e.g. Enter both set the value and closed the panel in one press).
func is_config_open() -> bool:
	return _config_target != null


func _close_config_sidebar() -> void:
	var had_target := _config_target != null
	if config_sidebar:
		config_sidebar.close()
	_config_target = null
	# Literal-value edits in the sidebar mutate the hex directly
	# without telling the editor; flush the static Do display here.
	_refresh_do_display_value()
	# Called defensively from many flows (tab switches, level loads);
	# only an actual open→close transition is a progress event.
	if had_target:
		config_closed.emit()


# World-space position of the OS mouse cursor. With a Camera2D in
# place, `get_global_mouse_position()` already returns canvas
# coordinates accounting for the camera transform — the helper stays
# as a single entry point so callers don't need to remember that.
# Queried via `world` (the root is a plain Node, not a CanvasItem;
# WorldLayer has follow_viewport_enabled so the values match).
func _mouse_world() -> Vector2:
	return world.get_global_mouse_position()


# ── Generate / Run ──────────────────────────────────────────────────────────

func _on_generate_pressed() -> void:
	output_panel.set_generated_text(_display_text(_build_program_text()))


# Walk every hex in every level (the level stack covers the visible
# ones; the deeper levels are reached via `inner_level`) and collect
# any hex's validation error. Inner-level Anchor hexes are checked
# too — their return slot being unwired means the level produces no
# body expression.
func _collect_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if _level_stack.is_empty():
		return errors
	_collect_errors_in_level(_level_stack[0], "main", errors)
	return errors


func _collect_errors_in_level(level: HexLevel, path: String, errors: Array) -> void:
	for h in level.hexes:
		var v = h.validate(self)
		if v.get("status", "ok") != "ok":
			errors.append("%s — %s: %s" % [path, h.get_config_title(), v.get("message", "")])
		# Pre-flight free-identifier check. An IdentRefHex whose
		# chosen palette name isn't bound by any enclosing Let /
		# Lambda / Definition / Match-branch would crash the runtime
		# at lookup; surface it here so the player sees a clean
		# error in the output panel instead.
		if h.get_script() == IdentRefHex:
			var name: String = IdentifierPalette.name_of(h.palette_index)
			var in_scope: Array = IdentifierScope.names_in_scope(h)
			if not name in in_scope:
				errors.append(
						"%s — Identifier: '%s' is not bound in any enclosing scope"
						% [path, name])
		if h.inner_level != null:
			var p := path
			if h.has_method("level_label"):
				p = "%s ▸ %s" % [path, h.level_label()]
			_collect_errors_in_level(h.inner_level, p, errors)


# Assemble the program: all level-0 DefinitionHex instances (one
# equation each, in placement order — multiple defs for the same
# name become multi-equation pattern matching), then the main
# expression from the Do hex bound as the `do main = <expr>` entry
# point (the canonical form the parser's `do <name> = body` grammar
# expects).
#
# When the active job exposes reserved identifiers (white / black),
# they become explicit parameters of `main` — `do main white black =
# <expr>` — so the generated text clarifies that main is expected to
# handle them. The checker binds the job's injected values to those
# parameters in the same palette order. If there are no definitions
# and no reserved parameters, just emit the bare main expression.
func _build_program_text() -> String:
	var defs: Array[String] = []
	if _level_stack.size() > 0:
		for h in _level_stack[0].hexes:
			if h is DefinitionHex:
				defs.append(h.to_source(self))
	var main_text := do_node.to_source(self)
	# `get_exposed_reserved()` is already in palette order (white before
	# black) — the checker relies on that order when applying values.
	var params: Array = IdentifierPalette.get_exposed_reserved()
	if defs.is_empty() and params.is_empty():
		return main_text
	var entry := "do main"
	for p in params:
		entry += " " + String(p)
	entry += " = " + main_text
	if defs.is_empty():
		return entry
	return "\n".join(defs) + "\n" + entry


# Display-only transform: strip redundant parens. Plain identifier
# names (`red`, `green`, …) stay as-is — the bundled font doesn't
# render the colored-emoji glyphs reliably and the player asked for
# plain text in the panel readout.
func _display_text(code: String) -> String:
	return HexTextFormatter.clean(code)


func _on_run_pressed() -> void:
	# Tutorial gate: no premature runs on a half-built board.
	if not TutorialManager.allows(&"run"):
		return
	# When a job is selected, Run *is* Submit — there's no separate
	# submit button anymore. Free-run is the no-job-selected path.
	if not ChapterManager.get_selected_job_id().is_empty():
		_on_submit_pressed()
		return
	var code := _build_program_text()
	output_panel.set_generated_text(_display_text(code))
	output_panel.clear_output()
	_append_output("[color=cyan]Generated:[/color] %s" % _display_text(code))

	# Soft enforcement (Phase 15): collect per-hex validation errors
	# before letting the parser see the text. Lists every issue —
	# unconnected required inputs are the most common — so the user
	# can fix several in one pass.
	var errors := _collect_validation_errors()
	if not errors.is_empty():
		_append_output("[color=yellow]Program is malformed — not running.[/color]")
		for e in errors:
			_append_output("  • " + e)
		output_panel.set_status("error", "Program is malformed — not running.")
		return
	if code.find("_HOLE_") != -1:
		_append_output("[color=yellow]Program has unconnected slots — not running.[/color]")
		output_panel.set_status("error", "Program has unconnected slots — not running.")
		return
	if code.find("_CYCLE_") != -1:
		_append_output("[color=red]Program has a cycle — not running.[/color]")
		output_panel.set_status("error", "Program has a cycle — not running.")
		return

	var program: Ctrl.Program = Parser.parse_module(code)
	if program == null:
		_append_output("[color=red]Parse error[/color]")
		output_panel.set_status("error", "Parse error")
		return

	environment = Env.root()
	Prelude.load_std_lib(environment)
	environment = program.install(environment)

	var main_expr: Expr = program.get_main_expr()
	if main_expr == null:
		_append_output("[color=gray](no main expression)[/color]")
		output_panel.set_status("warning", "(no main expression)")
		return

	var result = main_expr.interpret(environment)
	if result == null:
		_append_output("[color=red]Runtime error[/color]")
		output_panel.set_status("error", "Runtime error")
		return
	result = result.force()
	if result == null:
		_append_output("[color=red]Runtime error[/color]")
		output_panel.set_status("error", "Runtime error")
		return
	if result.is_error():
		_append_output("[color=red]Runtime error: %s[/color]" % result.error_message())
		output_panel.set_status("error", "Runtime error: %s" % result.error_message())
		return
	_append_output("[color=green]=> %s[/color]" % _value_to_string(result))
	output_panel.set_status("result", "=> %s" % _value_to_string(result))


func _append_output(line: String) -> void:
	output_panel.append_output(line)


func _value_to_string(value: Value) -> String:
	if value is Value.List:
		return str(value.unwrap())
	if value is Value.Tuple:
		return str(value.unwrap())
	if value is Value.Int:
		return str(value.unwrap())
	if value is Value.Bool:
		return str(value.unwrap())
	return str(value)


# ── Auto-computed Do display value ──────────────────────────────────────────
#
# When the chain wired into the active tab's DoHex is a literal-only
# static expression (literals + operators + `if` — no identifiers, no
# binders, no sub-levels), the editor evaluates it through the normal
# interpreter and bakes the result into the DoHex body via
# `set_display_value`. Anything dynamic or incomplete clears it back
# to the "do" keyword. Refreshes ride the same events that already
# mark the graph dirty: undo-stack pushes, undo/redo, tab loads, and
# config-sidebar closes (literal value edits don't notify the editor,
# so the close is their flush point).

# Script-path prefixes whose hexes are statically evaluable. Binders
# (lambda/let/match/definition) and identifier references are out:
# their value depends on context the static pass doesn't model.
const _STATIC_DISPLAY_PREFIXES: Array[String] = [
	"res://src/classes/hex_nodes/literals/integer/",
	"res://src/classes/hex_nodes/literals/booleans/",
	"res://src/classes/hex_nodes/operators/",
	"res://src/classes/hex_nodes/control/if_hex.gd",
]


func _refresh_do_display_value() -> void:
	_refresh_connection_visuals()
	var dh := do_node as DoHex
	if dh == null or _level_stack.is_empty():
		return
	var value := _compute_static_do_value()
	if dh.display_value != value:
		dh.set_display_value(value)


# Light up each hex's fed input edges on the active level. Called after
# any structural change (it rides every `_refresh_do_display_value`
# site: wire commit/delete, hex place/move/delete, undo/redo, tab load)
# and on level switch via `_apply_level_view`.
func _refresh_connection_visuals() -> void:
	if _level_stack.is_empty():
		return
	var lvl := _current_level()
	if lvl == null:
		return
	for h in lvl.hexes:
		if h.input_edges.is_empty():
			continue
		h.set_connected_input_edges(h.wired_input_edges(self))


func _compute_static_do_value() -> String:
	# Find the hex wired into Do (any of the six approach slots).
	var root_src: HexNode = null
	for edge in do_node.input_edges:
		root_src = get_input_for(do_node, edge)
		if root_src != null:
			break
	if root_src == null:
		return ""
	# Walk the input chain; bail on the first non-static hex. The
	# `seen` set doubles as a cycle guard.
	var pending: Array[HexNode] = [root_src]
	var seen := {}
	while not pending.is_empty():
		var h: HexNode = pending.pop_back()
		if seen.has(h):
			continue
		seen[h] = true
		if not _is_static_display_hex(h):
			return ""
		for edge in h.input_edges:
			var src := get_input_for(h, edge)
			if src == null:
				if edge in h.optional_input_edges:
					continue
				return ""  # unwired required input — incomplete chain
			pending.append(src)
	var code: String = root_src.to_source(self)
	if code.find("_HOLE_") != -1 or code.find("_CYCLE_") != -1:
		return ""
	var program: Ctrl.Program = Parser.parse_module(code)
	if program == null:
		return ""
	var env: Env = Env.root()
	Prelude.load_std_lib(env)
	env = program.install(env)
	var main_expr: Expr = program.get_main_expr()
	if main_expr == null:
		return ""
	var result = main_expr.interpret(env)
	if result == null:
		return ""
	result = result.force()
	if result == null or result.is_error():
		return ""
	return _value_to_string(result)


func _is_static_display_hex(h: HexNode) -> bool:
	var script: Script = h.get_script()
	if script == null:
		return false
	var path := script.resource_path
	for prefix in _STATIC_DISPLAY_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false


# ── Phase 19.2 — Jobs panel ────────────────────────────────────────────────
#
# A job is the hex-editor analogue of an exercise: a name + description +
# (optional) variables + tests + (optional) required/forbidden structures +
# `unlocks_hexes` (script paths) awarded on first solve. We reuse
# Checker.check_answer verbatim — the JSON shape is intentionally
# Checker-compatible. The panel lists pending jobs (renown_required met,
# unsolved) and completed jobs side by side; Submit dispatches against
# the current tab's program text.

func _rebuild_jobs_list() -> void:
	if jobs_panel:
		jobs_panel.refresh(ChapterManager.get_selected_job_id())
	_update_submit_button()


# ChapterManager.job_selection_changed handler — mirror the new
# selection into every widget that shows it, and refresh any open
# IdentRefHex config sidebar so its picker reflects the new reserved-
# identifier exposure without a close/reopen.
func _on_job_selection_changed(id: String) -> void:
	_refresh_job_display()
	# A selection toggle doesn't change the list's contents, only which
	# card is highlighted — move the highlight in place instead of
	# rebuilding every card (that full rebuild on each switch was the
	# FPS hiccup). Structural changes (solve/renown/unlock) still go
	# through _rebuild_jobs_list via their own signals.
	if jobs_panel:
		jobs_panel.set_selected(id)
	_update_submit_button()
	if _config_target is IdentRefHex:
		_open_config_sidebar(_config_target)


# Refresh the top-bar job display. Mirrors the selection state into
# the two labels under TopLabels — name in large gold, description in
# white. The description carries BBCode from static_data.json (job
# descriptions use `[b]…[/b]` to highlight identifiers), so it goes
# into the RichTextLabel verbatim.
func _refresh_job_display() -> void:
	if job_header == null:
		return
	var selected: String = ChapterManager.get_selected_job_id()
	var job: Dictionary = ChapterManager.get_selected_job()
	var solved: bool = (
		SaveManager.is_job_solved(selected)
		if not selected.is_empty()
		else false
	)
	job_header.set_job(selected, job, solved)
	# Mirror the selection into the jobs panel so its fold-header
	# title strip reflects the current pick.
	if jobs_panel and jobs_panel.has_method("set_selected_job"):
		var fold_name: String = ""
		var fold_desc: String = ""
		if not selected.is_empty() and not job.is_empty():
			var prefix := "✓ " if solved else ""
			fold_name = "%s%s" % [prefix, String(job.get("name", selected))]
			fold_desc = String(job.get("description", ""))
		jobs_panel.set_selected_job(fold_name, fold_desc)


# Refresh the Run button's tooltip so its dual role (free run vs.
# submit-against-selected-job) is at least discoverable on hover. The
# label itself stays a constant "▶ Run" — the job display in the top
# bar carries the contextual info instead.
func _update_submit_button() -> void:
	if top_buttons == null:
		return
	var selected: String = ChapterManager.get_selected_job_id()
	if selected.is_empty():
		top_buttons.set_run_tooltip("Evaluate the active tab against the prelude.\n(Shift+Space)")
	else:
		var job: Dictionary = ChapterManager.get_selected_job()
		var solved := SaveManager.is_job_solved(selected)
		var verb := "Re-submit" if solved else "Submit"
		top_buttons.set_run_tooltip("%s → %s\n(Shift+Space)" % [
			verb,
			String(job.get("name", selected)),
		])


func _update_renown_label() -> void:
	if jobs_panel:
		jobs_panel.set_renown(SaveManager.get_renown())


# ChapterManager.renown_changed handler — a fresh award can promote
# locked jobs to pending and flip the selected card to solved.
func _on_renown_changed(_total: int) -> void:
	_update_renown_label()
	_rebuild_jobs_list()
	_refresh_job_display()


# ChapterManager.hexes_unlocked handler — repaint the palette's lock
# state. The celebratory output lines render in the submit flow (which
# has the result context); this stays widget-only.
func _on_hexes_unlocked(_paths: Array) -> void:
	palette_bar.set_unlocked_scripts(SaveManager.get_unlocked_hex_scripts())


func _on_submit_pressed() -> void:
	var selected: String = ChapterManager.get_selected_job_id()
	if selected.is_empty():
		return
	var job: Dictionary = ChapterManager.get_selected_job()
	if job.is_empty():
		_append_output("[color=red]Job %s no longer exists.[/color]" % selected)
		return
	var code := _build_program_text()
	output_panel.set_generated_text(_display_text(code))
	output_panel.clear_output()
	_append_output("[color=cyan]Submitting tab '%s' → %s[/color]" % [_tabs[_active_tab_idx].tab_name, String(job.get("name", selected))])
	# Validate the visual program first; the parser would just fail on
	# `_HOLE_` placeholders, but the structured error list points the
	# player at which hex is unwired.
	var errors := _collect_validation_errors()
	if not errors.is_empty():
		_append_output("[color=yellow]Program is malformed — not submitting.[/color]")
		for e in errors:
			_append_output("  • " + e)
		output_panel.set_status("error", "Program is malformed — not submitting.")
		return
	if code.find("_HOLE_") != -1:
		_append_output("[color=yellow]Program has unconnected slots — not submitting.[/color]")
		output_panel.set_status("error", "Program has unconnected slots — not submitting.")
		return
	# ChapterManager owns the Checker call + all solve bookkeeping
	# (renown, hex unlocks, signals); we render its annotated result
	# from the submit_completed handler. The check runs on a background
	# thread so a slow evaluation never freezes the UI. Free-run and
	# the quick REPL stay synchronous — the interpreter's fuel limits
	# bound those, and their results feed straight back into the panel.
	if not ChapterManager.submit_async(code):
		_append_output("[color=yellow]A check is already running — wait for it to finish.[/color]")
		return
	_append_output("[color=gray]Checking…[/color]")
	output_panel.set_status("pending", "Checking…")
	top_buttons.set_run_enabled(false)


# ChapterManager.submit_completed handler — render the annotated result
# (or the watchdog's timeout message) and re-enable the Run button.
# The award bookkeeping already happened on the autoload, so an editor
# rebuilt mid-check still shows correct progression state.
func _on_submit_completed(_job_id: String, result: Dictionary) -> void:
	top_buttons.set_run_enabled(true)
	if result.get("timed_out", false):
		var message := String(result.get("message", "Check timed out."))
		_append_output("[color=#ff8888]%s[/color]" % message)
		output_panel.set_status("error", message)
		SfxManager.play("error")
		return
	_render_check_result(result)
	if result.get("correct", false):
		SfxManager.play("success")
		_render_award(result)
	else:
		SfxManager.play("error")


func _render_check_result(result: Dictionary) -> void:
	var passed: int = int(result.get("passed_tests", 0))
	var total: int = int(result.get("total_tests", 0))
	var correct: bool = bool(result.get("correct", false))
	if correct:
		_append_output("[color=#86e08a]✓ %s[/color]" % String(result.get("message", "")))
	else:
		_append_output("[color=#ff8888]✗ %s[/color]" % String(result.get("message", "")))
	_append_output("[color=gray]%d / %d tests passed[/color]" % [passed, total])
	# The collapsed title carries verdict + count in one line; the
	# renown/unlock lines that follow can no longer bury it.
	var verdict_icon := "✓" if correct else "✗"
	output_panel.set_status("pass" if correct else "fail",
			"%s %s — %d/%d tests passed" % [verdict_icon, String(result.get("message", "")), passed, total])
	for r in result.get("results", []):
		var passed_test: bool = bool(r.get("passed", false))
		var icon := "✓" if passed_test else "✗"
		var color := "#86e08a" if passed_test else "#ff8888"
		var input_text: String = ""
		if r.has("input") and r["input"] != null:
			input_text = "  in=%s" % str(r["input"])
		var expected_text := "  expect=%s" % str(r.get("expected"))
		var actual_text := "  got=%s" % str(r.get("actual"))
		_append_output("  [color=%s]%s[/color]%s%s%s" % [color, icon, input_text, expected_text, actual_text])


# Narrate a correct submit from ChapterManager's annotated result.
# The bookkeeping (renown, unlocks, signals) already happened inside
# `ChapterManager.submit`; this is output-panel text only. Widget
# refreshes ride the renown_changed / hexes_unlocked signals — but a
# re-solve emits neither, so refresh the job display here too (the
# selected card flips to ✓ either way).
func _render_award(result: Dictionary) -> void:
	if result.get("first_time", false):
		var reward: int = int(result.get("renown_awarded", 0))
		if reward > 0:
			_append_output("[color=#ffd86b]+%d renown.[/color]" % reward)
		var unlocked: Array = result.get("unlocked_hexes", [])
		if not unlocked.is_empty():
			_append_output("[color=#9fcfff]Unlocked %d new hex type(s):[/color]" % unlocked.size())
			for p in unlocked:
				_append_output("  • %s" % String(p).get_file().get_basename())
			output_panel.notify_unlock("🔓 %d new hex type(s) unlocked" % unlocked.size())
	else:
		_append_output("[color=gray]Already solved — no additional renown.[/color]")
	_refresh_job_display()
	_rebuild_jobs_list()
	# Flag the solved job green AFTER the refreshes re-select the same job, so
	# the highlight survives until the player moves to a different job.
	jobs_panel.flag_solved()


# ── Phase 19.4 — Marquee select / delete ───────────────────────────────────

func _start_marquee(is_delete: bool) -> void:
	# Cancel anything that would fight the drag for mouse ownership.
	_exit_blueprint_mode()
	_exit_stamp_mode()
	_cancel_active_wire()
	_marquee_active = true
	_marquee_is_delete = is_delete
	_marquee_start_world = _mouse_world()
	_marquee_fill = Polygon2D.new()
	_marquee_fill.color = MARQUEE_FILL_DELETE if is_delete else MARQUEE_FILL_SELECT
	world.add_child(_marquee_fill)
	_marquee_outline = Line2D.new()
	# Keep the outline visually consistent across zoom levels —
	# the camera's zoom multiplies world-space line widths on screen.
	var zoom_x: float = hex_camera.zoom.x if hex_camera != null else 1.0
	_marquee_outline.width = max(1.0, 1.5 / max(zoom_x, 0.01))
	_marquee_outline.default_color = (
		MARQUEE_OUTLINE_DELETE if is_delete else MARQUEE_OUTLINE_SELECT
	)
	world.add_child(_marquee_outline)
	_refresh_marquee_visual()


func _refresh_marquee_visual() -> void:
	if not _marquee_active or _marquee_fill == null or _marquee_outline == null:
		return
	var a := _marquee_start_world
	var b := _mouse_world()
	var pts := PackedVector2Array([
		Vector2(min(a.x, b.x), min(a.y, b.y)),
		Vector2(max(a.x, b.x), min(a.y, b.y)),
		Vector2(max(a.x, b.x), max(a.y, b.y)),
		Vector2(min(a.x, b.x), max(a.y, b.y)),
	])
	_marquee_fill.polygon = pts
	_marquee_outline.clear_points()
	for p in pts:
		_marquee_outline.add_point(p)
	_marquee_outline.add_point(pts[0])


func _commit_marquee() -> void:
	if not _marquee_active:
		return
	var rect := _marquee_world_rect()
	var degenerate := rect.size.length() < HexNode.HEX_SIZE * 0.5
	var hits: Array[HexNode] = []
	if degenerate:
		# Shift+click without motion: hit-test the hex under the
		# cursor instead of relying on the (near-zero) rect. Empty if
		# the click lands on a wire / empty cell.
		var ax := HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
		var n := _node_at_axial(ax)
		if n != null:
			hits.append(n)
	else:
		for h in _current_level().hexes:
			if h.is_fixture:
				continue
			var center := HexMath.axial_to_world(h.axial, HexNode.HEX_SIZE)
			if rect.has_point(center):
				hits.append(h)
	if _marquee_is_delete:
		# Destructive — refuse the degenerate case so a stray
		# Shift+RMB click can't nuke the hex under the cursor.
		# Bulk delete uses X with a selection (or a real drag).
		if degenerate:
			_cancel_marquee()
			return
		# Collect every per-hex removal record and stash them under a
		# single `delete_hexes_bulk` undo entry so one Ctrl+Z restores
		# the whole marquee instead of one hex at a time.
		var records: Array = []
		for h in hits:
			if h.level == null:
				continue
			var rec := _delete_hex(h, false, false)
			if not rec.is_empty():
				records.append(rec)
		if not records.is_empty():
			_push_undo({
				"type": "delete_hexes_bulk",
				"level": _current_level(),
				"entries": records,
			})
			SfxManager.play("delete")  # one cue for the marquee batch
		# Marquee delete also clears any prior selection so the next
		# action starts from a clean slate.
		_clear_selection()
	else:
		# Shift is the universal additive modifier — marquee adds to
		# the existing selection rather than replacing it. Click on
		# canvas (no shift) is how the player gets back to single-
		# hex selection (handled by `_open_config_sidebar`).
		_extend_selection(hits)
	_cancel_marquee()


func _cancel_marquee() -> void:
	if _marquee_fill != null:
		_marquee_fill.queue_free()
	if _marquee_outline != null:
		_marquee_outline.queue_free()
	_marquee_fill = null
	_marquee_outline = null
	_marquee_active = false


func _marquee_world_rect() -> Rect2:
	var a := _marquee_start_world
	var b := _mouse_world()
	var origin := Vector2(min(a.x, b.x), min(a.y, b.y))
	var size := Vector2(abs(b.x - a.x), abs(b.y - a.y))
	return Rect2(origin, size)


func _replace_selection(hexes: Array[HexNode]) -> void:
	_clear_selection()
	for h in hexes:
		if h.is_fixture:
			continue
		_selected_hexes.append(h)
		h.modulate = SELECTED_HEX_MODULATE


# Add hexes to the current selection without clearing first. Used by
# Shift+LMB (single click adds the clicked hex; drag adds every
# enclosed hex). Duplicates are silently skipped — clicking a hex
# that's already selected is a no-op.
func _extend_selection(hexes: Array[HexNode]) -> void:
	for h in hexes:
		if h.is_fixture or h in _selected_hexes:
			continue
		_selected_hexes.append(h)
		h.modulate = SELECTED_HEX_MODULATE


func _clear_selection() -> void:
	for h in _selected_hexes:
		if is_instance_valid(h):
			h.modulate = Color.WHITE
	_selected_hexes.clear()


# Delete every selected hex (X with a selection, called from the
# key handler). Skips fixtures defensively even though
# `_replace_selection` already filters them out.
func _delete_selection() -> void:
	var deleted_any := false
	for h in _selected_hexes.duplicate():
		if not is_instance_valid(h) or h.is_fixture:
			continue
		_delete_hex(h, true, false)  # one cue for the batch, below
		deleted_any = true
	if deleted_any:
		SfxManager.play("delete")
	_clear_selection()


# Drop selection entries for hexes that have left the current level
# (deletes, level changes). Called after each marquee delete so the
# remaining cyan-tinted hexes stay consistent with what's on screen.
func _prune_selection() -> void:
	var kept: Array[HexNode] = []
	var level := _current_level()
	for h in _selected_hexes:
		if is_instance_valid(h) and h.level == level and h in level.hexes:
			kept.append(h)
		elif is_instance_valid(h):
			h.modulate = Color.WHITE
	_selected_hexes = kept


# ── Phase 19.10 — Quick REPL ───────────────────────────────────────────────
#
# Ctrl+R opens a centered REPL overlay that evaluates expressions
# against the editor's persistent `environment`. The REPL does NOT
# re-parse the program text when opening — live-parsing a hex program
# mid-edit (when some hexes still emit `_HOLE_`) would push errors and
# disrupt the player. Instead, `environment` is refreshed only when
# the player explicitly runs or submits (`_on_run_pressed` /
# `_on_submit_pressed`), so the REPL sees whatever was last evaluated
# — same contract as the text editor (see editor.gd:_toggle_quick_repl).

func _open_quick_repl() -> void:
	if quick_repl_dialog == null:
		return
	quick_repl_dialog.open(environment)


# ── Phase 19.4 — Blueprints (library / capture / stamp) ────────────────────
#
# Players save the current tab's root level as a named blueprint and
# stamp it back into any tab. The wire format and JSON schema live in
# `BlueprintCodec`; this section is the editor glue:
#
#   • capture          — serialize the active tab's level 0 + emit the
#                        Factorio-style string fallback
#   • library modal    — list, rename, delete, import, export, stamp
#   • stamp mode       — multi-hex cursor preview + atomic commit
#
# Locked-hex policy is REFUSE: a blueprint with a hex the player hasn't
# unlocked yet shows its locked types in the Stamp button's tooltip and
# disables the action.

# Re-push every preference-dependent piece of editor state. Fires
# when the in-game settings modal changes a value (archmage, for
# now — other preferences ride the same signal when they land).
func _refresh_after_preferences_change() -> void:
	palette_bar.set_unlocked_scripts(SaveManager.get_unlocked_hex_scripts())
	palette_bar.set_archmage(SaveManager.is_archmage())
	jobs_panel.refresh(ChapterManager.get_selected_job_id())


func _seed_blueprint_registry() -> void:
	var scripts: Array = palette_bar.get_all_scripts()
	# Fixtures the loader recreates on demand still need their script
	# resolved when wires reference them.
	scripts.append(DoHex)
	scripts.append(preload("res://src/classes/hex_nodes/fixtures/anchor_hex.gd"))
	scripts.append(preload("res://src/classes/hex_nodes/fixtures/match_anchor.gd"))
	BlueprintLoader.register_scripts(scripts)


# Capture the active tab's level 0 as a blueprint. Prompts for a name
# Present an on-the-fly AcceptDialog as a tree-pausing modal: while it is
# open the SceneTree is paused (ModalStack), so the camera and the
# decentralized canvas input handlers freeze and keystrokes typed into the
# dialog can't leak into the editor (e.g. WASD panning the camera, or a
# bare letter firing a shortcut). The dialog itself runs WHEN_PAUSED so it
# stays interactive over the frozen world; the pause is released exactly
# once — when the dialog confirms, cancels, or leaves the tree.
#
# `_track_modal` can't be reused here: it takes an in-scene Control toggled
# via `visible`, whereas these AcceptDialogs are Windows created and freed
# on demand.
func _present_modal_dialog(dialog: AcceptDialog) -> void:
	dialog.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(dialog)
	dialog.popup_centered()
	ModalStack.acquire(get_tree())
	var released := [false]
	var release := func() -> void:
		if released[0]:
			return
		released[0] = true
		ModalStack.release(get_tree())
	dialog.confirmed.connect(release)
	dialog.canceled.connect(release)
	dialog.tree_exiting.connect(release)


# (defaulting to the tab name), then writes both the structured payload
# and the textual program form into SaveManager.
func _capture_current_tab_blueprint() -> void:
	if _tabs.is_empty() or _active_tab_idx < 0 or _active_tab_idx >= _tabs.size():
		return
	var tab: WorkspaceTab = _tabs[_active_tab_idx]
	if tab.level_stack.is_empty():
		return
	# Save outgoing state so the captured payload reflects the latest
	# pan/zoom + level snapshot. (Capture only walks the root level, so
	# pan/zoom isn't actually used — but the consistency is cheap.)
	if _active_tab_idx >= 0:
		_save_active_tab_state()
	var dialog := AcceptDialog.new()
	dialog.title = "Capture blueprint"
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Name this blueprint:"
	box.add_child(lbl)
	var line := LineEdit.new()
	line.text = tab.tab_name
	line.custom_minimum_size = Vector2(320, 0)
	box.add_child(line)
	dialog.add_child(box)
	_present_modal_dialog(dialog)
	line.grab_focus()
	line.select_all()
	# Enter in the name field saves (a focused LineEdit eats the key, so
	# AcceptDialog wouldn't confirm on its own).
	line.text_submitted.connect(func(_t: String) -> void:
		dialog.hide()
		dialog.confirmed.emit())
	dialog.confirmed.connect(func() -> void:
		var name := line.text.strip_edges()
		if name.is_empty():
			name = tab.tab_name
		_do_capture(tab, name)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


func _do_capture(tab: WorkspaceTab, name: String) -> void:
	var root: HexLevel = tab.level_stack[0]
	var payload: Dictionary = BlueprintCodec.serialize_root(
		root, self, tab.do_node, name, "", "", Vector2i.ZERO
	)
	var program_text: String = _build_program_text()
	SaveManager.add_blueprint(name, program_text, payload)
	_append_output("[color=#9fcfff]Saved blueprint '%s'.[/color]" % name)
	if _library_dialog != null and _library_dialog.visible:
		_rebuild_library_list()


# ── Ctrl+S / Ctrl+C / Ctrl+V — selection clipboard ────────────────────────

# Ctrl+S behaviour fans out by mode:
#   • in stamp mode  → prompt-and-save the active stamp payload
#                      (player just pasted, now wants to keep it)
#   • selection set  → prompt-and-save just the selected hexes
#   • neither        → fall back to "capture current tab" so Ctrl+S
#                      always does *something* save-shaped
func _ctrl_s_save() -> void:
	if not _stamp_payload.is_empty():
		_prompt_save_payload(_stamp_payload, "stamped blueprint")
		return
	if not _selected_hexes.is_empty():
		var payload := _build_selection_payload("selection")
		_prompt_save_payload(payload, "selection")
		return
	_capture_current_tab_blueprint()


# Ctrl+C — encode the selection to the OS clipboard, stash it for
# Ctrl+V, and immediately enter stamp mode so the cursor carries
# the copy ready to drop. No save — the player gets a frictionless
# duplicate without polluting the library.
func _ctrl_c_copy_selection_to_stamp() -> void:
	if _selected_hexes.is_empty():
		_append_output("[color=#ffd86b]Nothing selected to copy.[/color]")
		return
	var payload := _build_selection_payload("copy")
	_last_copied_payload = payload
	DisplayServer.clipboard_set(BlueprintCodec.encode(payload))
	_clear_selection()
	_begin_stamp(payload)


# Ctrl+X — cut: same as Ctrl+C, plus deletes the originals. The
# deletes are stashed under a single `delete_hexes_bulk` undo
# entry so one Ctrl+Z restores every cut hex in one step.
func _ctrl_x_cut_selection_to_stamp() -> void:
	if _selected_hexes.is_empty():
		_append_output("[color=#ffd86b]Nothing selected to cut.[/color]")
		return
	var payload := _build_selection_payload("cut")
	_last_copied_payload = payload
	DisplayServer.clipboard_set(BlueprintCodec.encode(payload))
	# Snapshot the selection before clearing — deletes invalidate it.
	var snapshot: Array = _selected_hexes.duplicate()
	_clear_selection()
	var records: Array = []
	for h in snapshot:
		# Cut is a pick-up, not a destroy — no shrink animation.
		var rec := _delete_hex(h, false, false, false)
		if not rec.is_empty():
			records.append(rec)
	if not records.is_empty():
		_push_undo({
			"type": "delete_hexes_bulk",
			"level": _current_level(),
			"entries": records,
		})
		SfxManager.play("pickup")  # cut acts as a pick-up of the whole area
	_begin_stamp(payload)


# Ctrl+V — pull `_last_copied_payload` (in-session) and enter stamp
# mode with it. Falls back to parsing the OS clipboard if the
# session var is empty (e.g. first action after relaunching), so a
# blueprint string pasted from chat lands the same way.
func _ctrl_v_paste_to_stamp() -> void:
	var payload: Dictionary = _last_copied_payload
	if payload.is_empty():
		var clip := DisplayServer.clipboard_get()
		var decoded = BlueprintCodec.decode(String(clip).strip_edges())
		if decoded is Dictionary:
			payload = decoded
			_last_copied_payload = payload
	if payload.is_empty():
		_append_output("[color=#ffd86b]Nothing to paste — copy a selection with Ctrl+C first.[/color]")
		return
	_begin_stamp(payload)


# Build a subset payload from the current selection. The DoHex rides
# along when drag-selected: the codec captures it as fixture metadata
# (never a stampable hex), so previews show it and wires feeding it
# round-trip.
func _build_selection_payload(label: String) -> Dictionary:
	var subset: Array = []
	for h in _selected_hexes:
		if not is_instance_valid(h):
			continue
		subset.append(h)
	return BlueprintCodec.serialize_subset(subset, self, label)


# Shared name-prompt → save-to-library dialog for Ctrl+S in stamp
# mode and Ctrl+S over a selection. Defaults the name to whatever
# the payload was labelled when built.
func _prompt_save_payload(payload: Dictionary, default_name: String) -> void:
	if payload.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Save blueprint"
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Name this blueprint:"
	box.add_child(lbl)
	var line := LineEdit.new()
	line.text = String(payload.get("label", default_name))
	line.custom_minimum_size = Vector2(320, 0)
	box.add_child(line)
	dialog.add_child(box)
	_present_modal_dialog(dialog)
	line.grab_focus()
	line.select_all()
	# Enter in the name field saves (a focused LineEdit eats the key, so
	# AcceptDialog wouldn't confirm on its own).
	line.text_submitted.connect(func(_t: String) -> void:
		dialog.hide()
		dialog.confirmed.emit())
	dialog.confirmed.connect(func() -> void:
		var nm := line.text.strip_edges()
		if nm.is_empty():
			nm = default_name
		var stored: Dictionary = payload.duplicate(true)
		stored["label"] = nm
		SaveManager.add_blueprint(nm, "", stored)
		_append_output("[color=#9fcfff]Saved blueprint '%s'.[/color]" % nm)
		if _library_dialog != null and _library_dialog.visible:
			_rebuild_library_list()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


# ── Library modal ──────────────────────────────────────────────────────────

func _open_library() -> void:
	if _library_dialog == null:
		_library_dialog = BLUEPRINT_LIBRARY_DIALOG_SCENE.instantiate() as Control
		_library_dialog.capture_requested.connect(_capture_current_tab_blueprint)
		_library_dialog.import_requested.connect(_show_import_dialog)
		_library_dialog.stamp_requested.connect(_begin_stamp)
		_pause_menu.get_parent().add_child(_library_dialog)
		_track_modal(_library_dialog)
	_library_dialog.open()


func _close_library() -> void:
	if _library_dialog != null and _library_dialog.visible:
		_library_dialog.close()


# Editor-side refresh: called after `_capture_current_tab_blueprint`,
# `_show_import_dialog`, and any other path that mutates SaveManager's
# blueprint list while the dialog is open.
func _rebuild_library_list() -> void:
	if _library_dialog != null:
		_library_dialog.refresh()


func _show_import_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Import blueprint"
	dialog.get_ok_button().text = "Import"
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Paste a blueprint string (starts with hxk1:)."
	box.add_child(lbl)
	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Name "
	name_row.add_child(name_lbl)
	var name_input := LineEdit.new()
	name_input.text = "imported blueprint"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_input)
	box.add_child(name_row)
	var te := TextEdit.new()
	te.placeholder_text = "hxk1:…"
	te.custom_minimum_size = Vector2(520, 200)
	box.add_child(te)
	dialog.add_child(box)
	_present_modal_dialog(dialog)
	te.grab_focus()
	dialog.confirmed.connect(func() -> void:
		var payload = BlueprintCodec.decode(te.text.strip_edges())
		if payload == null:
			_append_output("[color=#ff8888]Import failed: malformed blueprint string.[/color]")
		else:
			var nm := name_input.text.strip_edges()
			if nm.is_empty():
				nm = String(payload.get("label", "imported"))
			SaveManager.add_blueprint(nm, "", payload)
			_rebuild_library_list()
			_append_output("[color=#9fcfff]Imported blueprint '%s'.[/color]" % nm)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


# ── Stamp mode ────────────────────────────────────────────────────────────

func _begin_stamp(payload: Dictionary, preserve_rotation: bool = true) -> void:
	# Cancel anything that conflicts with stamp ownership of the mouse.
	_exit_blueprint_mode()
	_exit_stamp_mode()
	_cancel_active_wire()
	_close_config_sidebar()
	_close_library()
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO)
	if built["hexes"].is_empty():
		_append_output("[color=#ff8888]Blueprint has no stampable hexes.[/color]")
		return
	_stamp_payload = payload
	_stamp_previews = []
	# Rotation is session-scoped — preserved across every stamp the
	# player triggers (library, Ctrl+V, repeated commits, etc.) until
	# they explicitly press R again. Matches Factorio's "rotation
	# sticks" muscle memory. `preserve_rotation = false` is reserved
	# for future callers that want a clean re-arm.
	if not preserve_rotation:
		_stamp_rotation = 0
	for entry in built["hexes"]:
		var node: HexNode = entry.node
		node._pickable = false  # picked up by `_ready` when areas are built
		nodes_layer.add_child(node)
		node.modulate = BLUEPRINT_TINT_OK
		_stamp_previews.append({
			"node": node,
			"rel_axial": entry.axial,
			"rel_rotation": int(entry.rotation),
		})
	# Build preview wires too — same Line2D treatment as committed
	# wires but tinted with the in-progress alpha. The wire's
	# output_node / input_node already point at our preview hex
	# instances (loader built both as a single pass), so paint reads
	# their live world positions and the polyline follows the cursor.
	_stamp_preview_wires.clear()
	for w in built["wires"]:
		var line := Line2D.new()
		line.width = WIRE_WIDTH
		line.default_color = (
			WIRE_OPEN_COLOR if w.is_open else WIRE_COLOR
		) * BLUEPRINT_TINT_OK
		HexWire.attach_shader_to(line)
		connections_layer.add_child(line)
		w.line = line
		_stamp_preview_wires.append(w)
	# Stash the original (un-rotated) wire cells so each rotation
	# step can re-derive cells from the source-of-truth, not stack
	# its rotation onto an already-rotated copy.
	for w in _stamp_preview_wires:
		w.set_meta("source_cells", w.cells.duplicate(true))
	_disable_pickup_on_placed()
	_snap_stamp_to_mouse()


func _exit_stamp_mode() -> void:
	# A live pickup is a parked original waiting to be re-placed; tearing the
	# stamp down (RMB, Escape, tab/level switch) must return it, not lose it.
	if _pickup_active:
		_cancel_pickup()
	if _stamp_previews.is_empty() and _stamp_payload.is_empty() and _stamp_preview_wires.is_empty():
		return
	for entry in _stamp_previews:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	_stamp_previews.clear()
	for w in _stamp_preview_wires:
		if w.line:
			w.line.queue_free()
	_stamp_preview_wires.clear()
	_stamp_payload = {}
	# Rotation deliberately survives the exit — see `_begin_stamp`.
	_enable_pickup_on_placed()


# Rotate the stamp by `delta` 60° steps (CW for +1, CCW for -1).
# Recomputes axials + per-hex rotation + per-wire cells in one pass,
# then re-snaps to the cursor.
func _rotate_stamp(delta: int) -> void:
	if _stamp_previews.is_empty():
		return
	_stamp_rotation = posmod(_stamp_rotation + delta, 6)
	_snap_stamp_to_mouse()


func _snap_stamp_to_mouse() -> void:
	if _stamp_previews.is_empty():
		return
	_stamp_anchor_axial = HexMath.world_to_axial(_mouse_world(), HexNode.HEX_SIZE)
	var blocked: bool = _stamp_has_collision()
	var tint := BLUEPRINT_TINT_BLOCKED if blocked else BLUEPRINT_TINT_OK
	for entry in _stamp_previews:
		var rot_ax := HexMath.rotate_axial(entry.rel_axial, _stamp_rotation)
		entry.node.set_axial(_stamp_anchor_axial + rot_ax)
		entry.node.set_rotation_index(int(entry.rel_rotation) + _stamp_rotation)
		entry.node.modulate = tint
	# Rebuild each preview wire's cells from the cached source cells,
	# rotating axials around (0,0) and bumping enter/exit edges. The
	# wire's output_node / input_node already follow the hexes (those
	# are HexNodes whose `axial` we just updated), so `paint` walks
	# the rotated cell sequence between matching slot positions.
	var line_color := WIRE_COLOR * tint
	for w in _stamp_preview_wires:
		var source_cells: Array = w.get_meta("source_cells", [])
		var rebuilt: Array = []
		for cell in source_cells:
			var rot_cell_ax := HexMath.rotate_axial(cell.axial, _stamp_rotation) + _stamp_anchor_axial
			rebuilt.append({
				"axial": rot_cell_ax,
				"enter_edge": posmod(int(cell.enter_edge) + _stamp_rotation, 6),
				"exit_edge": -1 if int(cell.exit_edge) < 0 else posmod(int(cell.exit_edge) + _stamp_rotation, 6),
			})
		w.cells = rebuilt
		w.anchored_count = rebuilt.size()
		if w.line:
			w.line.default_color = (WIRE_OPEN_COLOR if w.is_open else WIRE_COLOR) * tint
		w.paint(Vector2.ZERO)


# A stamp is blocked only by a DIFFERENT-type hex under one of its
# previews. Landing on a same-type hex is allowed: the commit re-orients
# that existing hex to the stamp's rotation (keeping its config) instead
# of placing a duplicate — see `_apply_stamp_rotation_overlaps`.
func _stamp_has_collision() -> bool:
	var level := _current_level()
	for entry in _stamp_previews:
		var ax: Vector2i = _stamp_anchor_axial + HexMath.rotate_axial(entry.rel_axial, _stamp_rotation)
		for h in level.hexes:
			if h.axial == ax and h.get_script() != entry.node.get_script():
				return true
	return false


func _commit_stamp() -> void:
	if _stamp_previews.is_empty():
		return
	if _stamp_has_collision():
		SfxManager.play("error")
		for entry in _stamp_previews:
			entry.node.pop_in()  # bounce the blocked stamp for visual feedback
		return  # caller (left-click) is a no-op while blocked — pickup stays armed
	# A pickup commit is a single-shot MOVE: place once, fold the original's
	# removal into this same undo entry, and exit (no re-arm). Captured before
	# the action is built so `_finish_pickup_commit` can clear the state.
	var was_pickup := _pickup_active
	# Tear the preview down before instantiating fresh objects for the
	# real commit — preview hexes and wires are throwaway visuals
	# bound to the stamp; the committed wires are reconstructed from
	# the payload with the current rotation baked in so they bind to
	# the new node identities.
	for entry in _stamp_previews:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	_stamp_previews.clear()
	for w in _stamp_preview_wires:
		if w.line:
			w.line.queue_free()
	_stamp_preview_wires.clear()
	var anchor := _stamp_anchor_axial
	var rotation := _stamp_rotation
	var payload := _stamp_payload
	var level := _current_level()
	var built := BlueprintLoader.instantiate(payload, anchor, null, rotation)
	var reorients := _apply_stamp_rotation_overlaps(built, level)
	_install_built_level(built, level)
	# An open (grey) wire whose dangling tail landed on a compatible, free
	# slot should snap shut — a blueprint placed "into" a hex must connect.
	# A snap (or a hex slapped edge-to-edge onto a neighbour) makes this a
	# connection, so the whole drop plays the "connect" cue instead of "place".
	# _auto_connect_open_wire already plays "connect" itself, so track that
	# separately from slap-adjacency to avoid firing the cue twice.
	var wire_connected := false
	for w in built.get("wires", []):
		if _auto_connect_open_wire(w, level):  # plays "connect" internally
			wire_connected = true
	# Pop each freshly stamped hex into place; flash any edge-to-edge slap.
	var slap_connected := false
	for e in built.get("hexes", []):
		e.node.pop_in()
		if not wire_connected:
			var ce := _placed_connection_edge(e.node)
			if ce >= 0:
				_fire_placement_connect_fx(e.node, ce, false)
				slap_connected = true
	if not built.get("hexes", []).is_empty():
		if wire_connected:
			pass  # "connect" already played by the auto-snap path
		elif slap_connected:
			SfxManager.play("connect")
		else:
			SfxManager.play("place")
	for warning in built.get("warnings", []):
		_append_output("[color=#ffd86b]Blueprint warning: %s[/color]" % String(warning))
	# The stamp is a single undoable bulk action: the hexes and wires it
	# just installed at this level (each placed hex carries its inner level
	# along, exactly like a parked delete) plus the re-orientations applied
	# to pre-existing same-type hexes. Undoing reverses all of it in one
	# step without disturbing earlier history.
	var placed_hexes: Array = []
	for e in built.get("hexes", []):
		placed_hexes.append(e.node)
	var action := {
		"type": "place_stamp",
		"level": level,
		"hexes": placed_hexes,
		"wires": built.get("wires", []).duplicate(),
		"reorients": reorients,
	}
	# For a move, the picked-up original's removal rides in the SAME entry so
	# one Ctrl+Z reverts the whole move (placement gone, original back).
	if was_pickup:
		_finish_pickup_commit(action)
	_push_undo(action)
	_enable_pickup_on_placed()
	if was_pickup:
		# Single-shot move: clear the lingering stamp payload + re-enable
		# pickup (previews already freed above). `_pickup_active` is false
		# now, so the pickup-restore branch inside is inert.
		_exit_stamp_mode()
	else:
		# Re-arm stamp mode with the same payload — Factorio-style repeat
		# placement, so the player can paint several copies without
		# re-opening the library / re-pressing Ctrl+V. Rotation persists
		# across the re-arm so each repeat keeps the player's facing.
		_begin_stamp(payload, true)


# Fold the picked-up original into the move's `place_stamp` entry and clear
# pickup state. The original stays parked + hidden (it's already out of
# `level.hexes`) so undo can restore it and redo can re-park it.
func _finish_pickup_commit(action: Dictionary) -> void:
	action["removed"] = [_pickup_record]
	_pickup_record.hex.visible = false
	_pickup_active = false
	_pickup_record = {}


# Install a `BlueprintLoader.instantiate(...)` result into `level`,
# walking inner-level payloads recursively. Stand-alone so both the
# root stamp and each inner descent re-use the same logic.
func _install_built_level(built: Dictionary, level: HexLevel) -> void:
	TabStore.install_built(built, level, _active_tab(), _wire_node_signals)


# Same-type overlap resolution (friction pass). Where a freshly built
# stamp hex lands on an existing hex OF THE SAME TYPE we don't install a
# duplicate — we re-orient the existing hex to the stamp's rotation and
# keep its configuration. Different-type overlaps never reach here
# (`_stamp_has_collision` blocks the commit). Mutates `built`, dropping
# each superseded hex plus any stamp-internal wire / inner payload that
# referenced it. Returns the list of `{hex, old, new}` re-orient records
# so the caller can fold them into the stamp's undo entry (the rotation
# change is reversible alongside the rest of the commit).
func _apply_stamp_rotation_overlaps(built: Dictionary, level: HexLevel) -> Array:
	var superseded: Array = []
	var kept_hexes: Array = []
	var reorients: Array = []
	for entry in built.get("hexes", []):
		var existing: HexNode = null
		for h in level.hexes:
			if h.axial == entry.axial and h.get_script() == entry.node.get_script():
				existing = h
				break
		if existing != null:
			var new_index := int(entry.rotation)
			reorients.append({
				"hex": existing,
				"old": existing.rotation_index,
				"new": new_index,
			})
			# Re-routes attached wires and refreshes the sidebar — same
			# helper the undo/redo path uses, so all three stay in sync.
			_reapply_reorient(existing, new_index)
			superseded.append(entry.node)
			entry.node.queue_free()
		else:
			kept_hexes.append(entry)
	if superseded.is_empty():
		return reorients
	built["hexes"] = kept_hexes
	var kept_wires: Array = []
	for w in built.get("wires", []):
		if w.output_node in superseded or w.input_node in superseded:
			if w.line:
				w.line.queue_free()
		else:
			kept_wires.append(w)
	built["wires"] = kept_wires
	var kept_inner: Array = []
	for inner in built.get("inner", []):
		if inner.get("parent") not in superseded:
			kept_inner.append(inner)
	built["inner"] = kept_inner
	return reorients


# ── Chapter intro modal ──────────────────────────────────────────────────────
#
# Chapters gate the gameplay flow described in docs/CANVAS.canvas.
# Each chapter owns a `jobs` array (jobs deprecate the old text-editor
# exercises) and a `renown`-gated availability that mirrors the jobs
# panel: a chapter is "unlocked" once at least one of its jobs has its
# renown_required met. On editor entry we show the intro for the
# first chapter (id order) that is unlocked but not yet seen — so a
# fresh save lands on the tutorial, and later chapters surface the
# next time the editor opens after their jobs come within reach.

# Codex button placeholder. Disabled in the scene until the
# chapter / concepts library is built (docs/TODO.md → Chapter intros
# + encyclopedia); the handler exists so the signal wiring is in
# place for that pass.
func _on_codex_requested() -> void:
	if _codex_dialog == null:
		_codex_dialog = CODEX_DIALOG_SCENE.instantiate() as Control
		_pause_menu.get_parent().add_child(_codex_dialog)
		_track_modal(_codex_dialog)
	# Rebuild on every open so newly-met chapters appear as the player
	# progresses.
	_codex_dialog.set_concepts(_build_codex_concepts())
	_codex_dialog.open()


# Codex entries are the chapters the player has already met (their intro
# has fired), in chapter order. Each chapter's rich-text description is
# the concept body, so the codex is a persistent re-read of everything
# the intros have taught — no spoilers for chapters still ahead.
func _build_codex_concepts() -> Array:
	var concepts: Array = []
	for chapter_id in TemplateManager.get_chapter_ids():
		if not SaveManager.has_seen_chapter_intro(chapter_id):
			continue
		var chapter: Dictionary = TemplateManager.get_chapter(chapter_id)
		if chapter.is_empty():
			continue
		concepts.append({
			"id": chapter_id,
			"title": chapter.get("name", chapter_id),
			"body": chapter.get("description", ""),
			# The first example's blueprint renders as a live mini-canvas
			# preview in the codex detail pane (empty string → no preview).
			"blueprint": _first_chapter_blueprint(chapter),
		})
	return concepts


# First non-empty example blueprint string for a chapter, or "" when the
# chapter ships no renderable example.
func _first_chapter_blueprint(chapter: Dictionary) -> String:
	var examples = chapter.get("examples", null)
	if not (examples is Array):
		return ""
	for entry in examples:
		if entry is Dictionary:
			var bp := String(entry.get("blueprint", ""))
			if not bp.is_empty():
				return bp
	return ""


# Ctrl+Space copies the active tab's program text to the OS clipboard.
# Replaces the old Export-to-file button; the player wanted that path
# folded into the blueprint flow, and this covers the "I just want
# the raw text" need without a FileDialog round-trip.
func _copy_program_text_to_clipboard() -> void:
	var code: String = _build_program_text()
	DisplayServer.clipboard_set(code)
	_append_output("[color=#86e08a]Program text copied to clipboard (%d chars).[/color]" % code.length())


# Tab context-menu "Copy blueprint": one-click copy of a tab's root
# level as an encoded blueprint string (hxk1:...). Collapses the old
# chapter-author flow of Library → Capture → Export into one press;
# the string pastes straight into a chapter entry's `blueprint` field.
func _copy_tab_blueprint_to_clipboard(idx: int) -> void:
	if idx < 0 or idx >= _tabs.size():
		return
	var tab: WorkspaceTab = _tabs[idx]
	if tab.level_stack.is_empty() or tab.do_node == null:
		_append_output("[color=#ffd86b]Nothing to copy — tab has no canvas.[/color]")
		return
	# The active tab's level stack lives partly in editor-scoped vars;
	# flush them so the snapshot reflects what's on screen.
	if idx == _active_tab_idx:
		_save_active_tab_state()
	var root: HexLevel = tab.level_stack[0]
	var payload: Dictionary = BlueprintCodec.serialize_root(
		root, self, tab.do_node, tab.tab_name, "", "", Vector2i.ZERO
	)
	var encoded: String = BlueprintCodec.encode(payload)
	DisplayServer.clipboard_set(encoded)
	_append_output("[color=#86e08a]Blueprint string copied to clipboard (%d chars).[/color]" % encoded.length())


# Ctrl+F handler. Asks the jobs panel to flip between list view (the
# scrollable cards) and description view (the selected job's full
# description expanded). The panel handles the no-op when the toggle
# doesn't change anything.
# Ctrl+F handler — folds / unfolds the jobs panel. When folded, the
# panel's title shows the selected job name and the description sits
# in the tooltip; the rest of the panel collapses to the header strip.
func _toggle_jobs_fold() -> void:
	if jobs_panel and jobs_panel.has_method("toggle_fold"):
		jobs_panel.toggle_fold()


# ChapterManager.chapter_intro_requested handler — the editor owns the
# modal instance; the manager owns the when/which.
func _on_chapter_intro_requested(chapter_id: String, chapter: Dictionary) -> void:
	_chapter_intro_dialog.call("show_chapter", chapter_id, chapter)


func _on_chapter_intro_closed(chapter_id: String) -> void:
	ChapterManager.notify_intro_closed(chapter_id)


# ChapterManager.templates_unlocked handler.
func _on_templates_unlocked(_names: Array) -> void:
	_append_output("[color=cyan]🔓 New templates unlocked — check the templates panel.[/color]")
