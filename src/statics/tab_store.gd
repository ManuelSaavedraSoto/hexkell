class_name TabStore
## Tab generation + persistence layer — codec in, codec out.
##
## Owns building WorkspaceTab nodes (fresh, or rehydrated from a
## BlueprintCodec payload via BlueprintLoader) and serializing them
## back to payloads for SaveManager. The editor only asks for tab
## nodes and says when to persist; everything stays on the same
## JSON/codec save format as before (tab persistence deliberately
## does NOT use PackedScenes — instantiating .tscn from user:// can
## execute embedded scripts).
##
## Hexes created here are announced through the `on_hex` Callable so
## the editor can wire its own signal handlers (those connections are
## editor behavior, not tab data).

const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")

# Monotonic name suffix for loaded hexes (display/debug uniqueness).
static var _spawn_counter: int = 0


## Build a fresh tab under `parent`: tab node + root level + DoHex.
static func create_fresh(id: int, p_name: String, parent: Node, on_hex: Callable) -> WorkspaceTab:
	var tab := WorkspaceTab.create(id, p_name)
	parent.add_child(tab)
	var lvl0 := tab.create_root_level()
	var do_hex: HexNode = HexNode.from_script(DoHex)
	do_hex.name = "DoNode_t%d" % tab.id
	lvl0.add_hex(do_hex)
	do_hex.set_axial(Vector2i(0, 0))
	tab.do_node = do_hex
	on_hex.call(do_hex)
	return tab


## Rehydrate a tab's root level from a saved codec payload. The tab
## already has its DoHex fixture (from `create_fresh`); the loader
## binds it to the payload's fixture id so wires feeding the Do
## round-trip. Returns the loader's warnings.
static func install_payload(tab: WorkspaceTab, payload: Dictionary, on_hex: Callable) -> Array:
	var built := BlueprintLoader.instantiate(payload, Vector2i.ZERO, tab.do_node)
	install_built(built, tab.root_level(), tab, on_hex)
	return built.get("warnings", [])


## Install a BlueprintLoader build (hexes + wires + nested inner
## payloads) into `level`. Shared by tab rehydration and the editor's
## stamp-commit path. Recursion builds inner levels through the tab's
## own API so the level nodes land in the right subtree.
static func install_built(built: Dictionary, level: HexLevel, tab: WorkspaceTab, on_hex: Callable) -> void:
	for entry in built["hexes"]:
		var node: HexNode = entry.node
		# `level.add_hex` parents under the TARGET level (which may be
		# an inactive tab during bootstrap, or an inner level during a
		# recursive install) and matches pickability to its activation.
		level.add_hex(node)
		node.set_axial(entry.axial)
		node.set_rotation_index(int(entry.rotation))
		_spawn_counter += 1
		node.name = "HexNode_%d" % _spawn_counter
		node.modulate = Color.WHITE
		on_hex.call(node)
	for w in built["wires"]:
		install_loaded_wire(w, level)
	for inner_entry in built.get("inner", []):
		var parent: HexNode = inner_entry.parent
		if not parent.has_inner_level():
			continue
		if parent.inner_level == null:
			var inner := tab.create_inner_level_for(parent)
			on_hex.call(inner.anchor)
		var inner_built := BlueprintLoader.instantiate_inner(
			inner_entry.payload, parent.inner_level.anchor
		)
		install_built(inner_built, parent.inner_level, tab, on_hex)


## Build Line2D visuals for a freshly instantiated wire and attach to
## the level. Mirrors what the editor's _commit_active_wire does at
## the end of an interactive draw, minus the picker / open-wire
## bookkeeping that only matters mid-drag.
static func install_loaded_wire(w: HexWire, level: HexLevel) -> void:
	var line := HexWire.build_line(w.is_open)
	level.add_wire_line(line)
	w.line = line
	# `paint` consults the wire's anchor_*; loader sets anchor to the
	# output side, so the polyline runs output → cells → input.
	w.paint(Vector2.ZERO)
	level.wires.append(w)


## Serialize one tab back to a codec payload. `canvas` answers
## `get_input_for` during emission (the editor passes itself).
static func to_payload(tab: WorkspaceTab, canvas) -> Dictionary:
	var root := tab.root_level()
	if root == null or tab.do_node == null:
		return {}
	return BlueprintCodec.serialize_root(
		root, canvas, tab.do_node, tab.tab_name, "", "", Vector2i.ZERO
	)


## Write the whole tab set through to the save file — same
## `{name, payload}` shape as always.
static func persist(tabs: Array, active_idx: int, canvas) -> void:
	var payloads: Array = []
	for t in tabs:
		payloads.append({"name": t.tab_name, "payload": to_payload(t, canvas)})
	SaveManager.set_tabs(payloads, active_idx)
