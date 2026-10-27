class_name WorkspaceTab
extends Node2D
## A persistent workspace tab — now a real node under the editor's
## World. Each tab node contains its levels (HexLevel nodes under
## `Levels`, flat — the logical nesting lives in `parent_hex` /
## `hex.inner_level` refs), so switching tabs is one visibility flip
## instead of a per-hex reconcile, and each tab keeps its own undo /
## redo stacks and DoHex fixture.
##
## The view (pan / zoom) is stored per-level on `HexLevel`; the editor
## saves/applies the camera around switches.

var id: int
# Display name — distinct from Node.name, which sanitizes characters
# and auto-renames on sibling collisions.
var tab_name: String = ""

# Navigation stack: level 0 is always at index 0, the top is whatever
# the user was viewing. Levels are children of `levels` whether or not
# they're currently on the stack (inner levels persist off-stack).
var level_stack: Array[HexLevel] = []

# Tab-scoped undo/redo: an undo on tab 3 must never mutate tab 5.
var undo_stack: Array = []
var redo_stack: Array = []

# The DoHex fixture for this tab's level 0.
var do_node: HexNode = null

var levels: Node2D = null


## Factory for the template tab scene. `load()` (not preload) avoids a
## scene↔script load cycle.
static func create(p_id: int, p_name: String) -> WorkspaceTab:
	var tab: WorkspaceTab = (
		load("res://scenes/gui/hex_editor/workspace_tab.tscn") as PackedScene
	).instantiate()
	tab.id = p_id
	tab.tab_name = p_name
	tab.name = "Tab_%d" % p_id
	tab.visible = false
	return tab


func _ready() -> void:
	levels = $Levels


## Build level 0. Called once, after the tab enters the tree.
func create_root_level() -> HexLevel:
	var lvl := HexLevel.create(null)
	levels.add_child(lvl)
	level_stack = [lvl] as Array[HexLevel]
	return lvl


## Build an inner level for `hex`, anchored at (0,0). The caller wires
## the returned level's `anchor` signals (editor-owned handlers).
func create_inner_level_for(hex: HexNode) -> HexLevel:
	var level := HexLevel.create(hex)
	levels.add_child(level)
	var anchor: HexNode = hex.create_inner_anchor()
	level.add_hex(anchor)
	anchor.set_axial(Vector2i.ZERO)
	level.anchor = anchor
	hex.inner_level = level
	return level


func root_level() -> HexLevel:
	return level_stack[0] if not level_stack.is_empty() else null


func current_level() -> HexLevel:
	return level_stack.back() if not level_stack.is_empty() else null


## One-flip tab switch: hide/show this tab's subtree, and reconcile
## level activation so only the stack top is pickable when active.
func set_active(p_active: bool) -> void:
	visible = p_active
	if levels != null:
		for lvl in levels.get_children():
			if lvl is HexLevel and lvl != current_level():
				lvl.set_active(false)
	var top := current_level()
	if top != null:
		top.set_active(p_active)


# True if every level in the tab is empty except for fixtures (DoHex /
# anchors). Used by the jobs panel to label tabs as "scratch" in a UI
# pass — not currently consumed, but cheap to expose.
func is_empty() -> bool:
	if level_stack.is_empty():
		return true
	for lvl in level_stack:
		for h in lvl.hexes:
			if not h.is_fixture:
				return false
		if not lvl.wires.is_empty():
			return false
	return true


## Wipe the tab back to a bare root level + DoHex: free every inner
## level (they're flat siblings under `levels`, so one pass covers list
## continuations too), drop the root's non-fixture hexes and their wire
## visuals, reset the view, and clear the undo/redo history. Self-
## contained — frees its own subtree nodes, so the editor doesn't have
## to lend its `_dispose_wire_visuals` helper.
func clear_content() -> void:
	var root := root_level()
	if root == null:
		return
	if levels != null:
		for lvl in levels.get_children():
			if lvl != root:
				lvl.queue_free()
	for h in root.hexes.duplicate():
		if h == do_node:
			continue
		h.inner_level = null
		root.hexes.erase(h)
		h.queue_free()
	for w in root.wires:
		if w.line:
			w.line.queue_free()
		if w.error_line:
			w.error_line.queue_free()
	root.wires.clear()
	level_stack = [root] as Array[HexLevel]
	root.world_position = Vector2.ZERO
	root.world_scale = 1.0
	undo_stack = []
	redo_stack = []


## Stash the camera pan/zoom on the level the user is currently viewing
## (the editor saves it here on switch-away / persist).
func store_view(pos: Vector2, zoom: float) -> void:
	var top := current_level()
	if top != null:
		top.world_position = pos
		top.world_scale = zoom


## Rename the tab. Returns false (leaving the name untouched) when the
## new name is blank, so callers can skip a needless strip rebuild.
func rename(p_name: String) -> bool:
	var clean := p_name.strip_edges()
	if clean.is_empty():
		return false
	tab_name = clean
	return true

