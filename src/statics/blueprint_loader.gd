class_name BlueprintLoader
extends RefCounted
## Loader half of the blueprint system. Splits "build a graph of
## HexNodes + HexWires from a payload" (pure data → object work, easy
## to unit-test) from "wire that graph into the live editor"
## (add_child + Line2Ds + signals — handled in hex_editor.gd by
## consuming the structure this loader returns).
##
## Two entry points:
##
##   • `instantiate(payload)` — builds detached hexes/wires in memory.
##     Used by the editor for stamping, and by tests for round-trip
##     verification.
##   • `class_registry()` — script-path → Script map built lazily from
##     a probe walk of the editor's PALETTE_CATEGORIES (passed in by
##     the editor). Used for fallback lookup when a stored script_path
##     no longer exists.

# BlueprintCodec is reachable via its `class_name`; the local consts
# below are the scene-tree types this loader instantiates.
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const HexLevel := preload("res://scenes/gui/hex_editor/hex_level.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")

# script_path → Script, populated by `register_scripts`. Falls back on
# class_name match when the path is missing (script moved between
# builds). Empty until the editor seeds it on startup.
static var _registry_by_path: Dictionary = {}
static var _registry_by_class: Dictionary = {}


# Editor calls this once at startup with every Script it cares about
# (every entry in PALETTE_CATEGORIES). Idempotent and cheap to re-run.
static func register_scripts(scripts: Array) -> void:
	for s in scripts:
		if s == null:
			continue
		var path: String = (s as Script).resource_path
		if not path.is_empty():
			_registry_by_path[path] = s
		var cname: String = (s as Script).get_global_name()
		if not cname.is_empty():
			_registry_by_class[cname] = s


# Look up a Script from a hex entry. Prefers the stored `script` path;
# falls back to `class` if the path has gone missing.
static func resolve_script(entry: Dictionary):
	var path: String = String(entry.get("script", ""))
	if not path.is_empty() and _registry_by_path.has(path):
		return _registry_by_path[path]
	# Path-based ResourceLoader lookup catches scripts that were never
	# explicitly registered (e.g. anchors created via `create_inner_anchor`
	# whose path the editor never registered).
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	var cname: String = String(entry.get("class", ""))
	if not cname.is_empty() and _registry_by_class.has(cname):
		return _registry_by_class[cname]
	return null


# ── Locked-hex policy ──────────────────────────────────────────────────────

# Currently REFUSE only — see docs/BLUEPRINT_FORMAT.md for the other
# two modes. Returns the locked script paths present in the payload
# (empty when every hex is unlocked).
static func locked_paths_in(payload: Dictionary, is_unlocked: Callable) -> Array:
	var locked: Array = []
	_collect_locked_paths(payload.get("hexes", []), is_unlocked, locked)
	return locked


static func _collect_locked_paths(hexes: Array, is_unlocked: Callable, out: Array) -> void:
	for entry in hexes:
		var path: String = String(entry.get("script", ""))
		if not path.is_empty() and not bool(is_unlocked.call(path)) and path not in out:
			out.append(path)
		if entry.has("inner"):
			var inner: Dictionary = entry["inner"]
			_collect_locked_paths(inner.get("hexes", []), is_unlocked, out)


# ── Instantiation ──────────────────────────────────────────────────────────

# Build a detached graph from `payload`. Returns:
#   {
#     hexes:        Array[Dictionary] — { node, axial, rotation, id } per
#                                       hex at root level (axials offset
#                                       by `anchor_axial` already)
#     wires:        Array[HexWire]   — every root-level wire, cells
#                                       already offset
#     inner:        Array[Dictionary] — { parent, payload } pairs the
#                                       editor must recursively stamp
#                                       after creating each parent's
#                                       inner level + anchor
#     warnings:     Array[String]    — non-fatal issues
#   }
#
# Nothing here is parented or added to a level — the editor does that
# after running collision / locked checks against the live canvas.
# `fixture` (optional) is pre-bound to the level's `fixture_id` slot in
# id_map so wires touching it round-trip. At root, pass the tab's
# DoHex; for inner levels, the editor passes the freshly-created anchor
# via `instantiate_inner` instead. `rotation` (0..5) rotates the
# blueprint by k*60° CW around its origin before applying the anchor
# offset — used by the stamp cursor's R key.
static func instantiate(
	payload: Dictionary,
	anchor_axial: Vector2i,
	fixture: HexNode = null,
	rotation: int = 0,
) -> Dictionary:
	var warnings: Array[String] = []
	# Round-trip display-only fixture state (e.g. DoHex.display_value)
	# captured by `serialize_root` so previews see the same body the
	# author saw. Older blueprints without `fixture_state` are a no-op.
	if fixture != null and payload.has("fixture_state"):
		fixture.restore_state(payload["fixture_state"], null)
	var built := _instantiate_level(
		payload.get("hexes", []),
		payload.get("wires", []),
		anchor_axial,
		warnings,
		_seed_id_map(payload, fixture),
		rotation,
	)
	# A level-body `inner` key is the fixture's OWN inner level (a
	# ListAnchor continuation block); queue it like any hex's inner
	# payload so `TabStore.install_built` recurses into it.
	if fixture != null and payload.has("inner"):
		built["inner"].append({"parent": fixture, "payload": payload["inner"]})
	built["warnings"] = warnings
	return built


# Inner-level entry point: same as `instantiate` but axials are taken
# as-is (inner levels store everything relative to their anchor at
# (0,0), so no anchor_axial offset is applied).
static func instantiate_inner(payload: Dictionary, anchor: HexNode) -> Dictionary:
	var warnings: Array[String] = []
	var built := _instantiate_level(
		payload.get("hexes", []),
		payload.get("wires", []),
		Vector2i.ZERO,
		warnings,
		_seed_id_map(payload, anchor),
	)
	# Continuation chain: the anchor itself may own an inner level.
	if anchor != null and payload.has("inner"):
		built["inner"].append({"parent": anchor, "payload": payload["inner"]})
	built["warnings"] = warnings
	return built


static func _seed_id_map(payload: Dictionary, fixture) -> Dictionary:
	var seed: Dictionary = {}
	if fixture != null and payload.has("fixture_id"):
		seed[int(payload["fixture_id"])] = fixture
	return seed


# Walk a level's hexes / wires arrays. `axial_offset` is applied to every
# hex's relative axial AND to every wire's cell axials — at root the
# offset is the stamp anchor; for inner levels it's Vector2i.ZERO
# (inner-level axials are already relative to the inner anchor).
static func _instantiate_level(
	hexes_in: Array,
	wires_in: Array,
	axial_offset: Vector2i,
	warnings: Array,
	seed_id_map: Dictionary = {},
	rotation: int = 0,
) -> Dictionary:
	var hexes_out: Array = []
	var inner_out: Array = []
	# id_map: local blueprint id → HexNode. Seeded with the fixture
	# binding so wires touching it can resolve their endpoint.
	var id_map: Dictionary = seed_id_map.duplicate()
	for entry in hexes_in:
		var script = resolve_script(entry)
		if script == null:
			warnings.append("Skipped hex (missing script): %s" % String(entry.get("script", "?")))
			continue
		var hex: HexNode = HexNode.from_script(script as Script)
		hex.restore_state(entry.get("state", {}), null)
		var axial_raw: Array = entry.get("axial", [0, 0])
		var rel_axial := Vector2i(int(axial_raw[0]), int(axial_raw[1]))
		var rot_axial := HexMath.rotate_axial(rel_axial, rotation)
		var local_id: int = int(entry.get("id", -1))
		if local_id >= 0:
			id_map[local_id] = hex
		hexes_out.append({
			"node": hex,
			"axial": rot_axial + axial_offset,
			"rotation": int(entry.get("rotation", 0)) + rotation,
			"id": local_id,
		})
		if entry.has("inner"):
			# Defer inner-level instantiation; the editor needs to create
			# the parent's inner_level + anchor first (`_create_inner_level_for`)
			# before we can add the inner hexes to it. We just record the
			# payload here.
			inner_out.append({"parent": hex, "payload": entry["inner"]})
	var wires_out: Array = []
	for w_entry in wires_in:
		var w = _instantiate_wire(w_entry, id_map, axial_offset, warnings, rotation)
		if w != null:
			wires_out.append(w)
	return {"hexes": hexes_out, "wires": wires_out, "inner": inner_out, "id_map": id_map}


static func _instantiate_wire(
	entry: Dictionary,
	id_map: Dictionary,
	axial_offset: Vector2i,
	warnings: Array,
	rotation: int = 0,
):
	var out_pair: Array = entry.get("output", [-1, -1])
	var in_pair: Array = entry.get("input", [-1, -1])
	var out_id := int(out_pair[0])
	var in_id := int(in_pair[0])
	if not id_map.has(out_id):
		# Endpoint hex was skipped (missing script). The wire makes no
		# sense without its source — drop it.
		warnings.append("Skipped wire (missing output hex %d)" % out_id)
		return null
	var w := HexWire.new()
	w.output_node = id_map[out_id]
	# Edges are logical (rotation-invariant) — the hex's
	# rotation_index handles the physical mapping. So `output_edge`
	# and `input_edge` survive a stamp rotation unchanged; only the
	# wire's *cell* enter/exit edges (which are physical) need
	# rotating.
	w.output_edge = int(out_pair[1])
	if in_id >= 0 and id_map.has(in_id):
		w.input_node = id_map[in_id]
		w.input_edge = int(in_pair[1])
	w.anchor_node = w.output_node
	w.anchor_edge = w.output_edge
	w.anchor_is_output = true
	w.is_finalized = true
	w.is_open = bool(entry.get("open", false)) or w.input_node == null
	for cell_raw in entry.get("cells", []):
		var ax_raw: Array = cell_raw.get("axial", [0, 0])
		# Cell axials are stored relative to the blueprint's origin —
		# rotate around (0,0), then translate by the stamp anchor.
		var local := Vector2i(int(ax_raw[0]), int(ax_raw[1]))
		var ax := HexMath.rotate_axial(local, rotation) + axial_offset
		var enter := int(cell_raw.get("enter", 0))
		var exit := int(cell_raw.get("exit", -1))
		# enter / exit are physical edges on the cell, so they rotate
		# with the blueprint. exit == -1 marks a dangling tail and
		# stays unchanged.
		enter = posmod(enter + rotation, 6)
		if exit >= 0:
			exit = posmod(exit + rotation, 6)
		w.cells.append(HexWire.make_cell(ax, enter, exit))
	w.anchored_count = w.cells.size()
	return w
