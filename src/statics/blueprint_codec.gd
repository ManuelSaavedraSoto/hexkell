class_name BlueprintCodec
extends RefCounted
## Blueprint serializer + string wrapper.
##
## See docs/BLUEPRINT_FORMAT.md for the contract.
##
## Two responsibilities:
##
##   • build / parse the JSON payload that represents a graph of hexes
##     (recursive across inner levels)
##   • wrap / unwrap that payload as a `hxk1:` Factorio-style string
##     (gzip + base64) so it can be pasted in chat
##
## The loader half (`stamp`) lives in BlueprintLoader — this class is
## the pure data layer with no editor / scene-tree dependencies, so the
## tests can exercise round-trips with a `MockCanvas`.

const SCHEMA_VERSION := 1
const STRING_PREFIX := "hxk1:"


# ── Serialize ───────────────────────────────────────────────────────────────

# Build a top-level blueprint payload from a root level. `do_node` is the
# DoHex fixture for that level (level 0 in a workspace tab); we skip
# emitting it (it's a fixture every editor recreates) but we do emit
# every wire feeding it so the stamp can re-attach the main expression.
#
# `label` / `description` / `icon` are user-authored metadata. `origin`
# is the axial coordinate that becomes the stamp anchor — defaults to
# (0, 0), which leaves every hex at its captured position.
static func serialize_root(
	level: HexLevel,
	canvas,
	do_node: HexNode,
	label: String,
	description: String = "",
	icon: String = "",
	origin: Vector2i = Vector2i.ZERO,
) -> Dictionary:
	var id_map: Dictionary = {}
	var payload := {
		"version": SCHEMA_VERSION,
		"kind": "blueprint",
		"label": label,
		"description": description,
		"icon": icon,
		"created_at": Time.get_datetime_string_from_system(),
		"origin": [origin.x, origin.y],
	}
	var body := _serialize_level(level, canvas, id_map, origin, do_node)
	payload["hexes"] = body["hexes"]
	payload["wires"] = body["wires"]
	if body.has("fixture_id"):
		payload["fixture_id"] = body["fixture_id"]
	# Capture the fixture's per-hex state separately so display-only
	# fields (DoHex.display_value, future auto-compute, etc.) round-trip
	# through previews even though the fixture itself isn't in `hexes`.
	if do_node != null:
		payload["fixture_state"] = do_node.serialize_state(canvas)
		# Where the fixture sat relative to the origin, so previews can
		# place their recreated DoHex where the author saw it.
		var frel: Vector2i = do_node.axial - origin
		payload["fixture_axial"] = [frel.x, frel.y]
	return payload


# Subset capture — used for "Capture selection as blueprint". Emits
# only `hexes` that appear in `subset` and only wires whose both
# endpoints are in the subset.
#
# A fixture (the DoHex) included in the subset is captured the same
# way `serialize_root` handles it: not emitted as a hex, but recorded
# as `fixture_id` / `fixture_axial` / `fixture_state` so previews can
# recreate it and wires feeding it round-trip. Stamping such a payload
# leaves those wires open (the stamp never spawns a second Do).
#
# `origin` defaults to the centroid of the subset's axials so a
# stamp anchored at the cursor lands the selection around it,
# rather than scrolling far away from the cursor.
static func serialize_subset(
	subset: Array,
	canvas,
	label: String,
	description: String = "",
	icon: String = "",
	origin = null,
) -> Dictionary:
	var ax_origin: Vector2i = origin if origin != null else _centroid_axial(subset)
	var id_map: Dictionary = {}
	var payload := {
		"version": SCHEMA_VERSION,
		"kind": "blueprint",
		"label": label,
		"description": description,
		"icon": icon,
		"created_at": Time.get_datetime_string_from_system(),
		"origin": [ax_origin.x, ax_origin.y],
	}
	# Pre-register every selected hex's id so wires can be filtered
	# against the subset cheaply.
	var subset_set: Dictionary = {}
	for h in subset:
		subset_set[h] = true
	# Register a selected fixture up front (id only — never emitted as
	# a hex) so wires touching it survive the subset filter below.
	for h in subset:
		if not h.is_fixture:
			continue
		var fid: int = _next_id(id_map)
		id_map[h] = fid
		payload["fixture_id"] = fid
		var frel: Vector2i = h.axial - ax_origin
		payload["fixture_axial"] = [frel.x, frel.y]
		payload["fixture_state"] = h.serialize_state(canvas)
		break
	var hexes_out: Array = []
	for h in subset:
		if h.is_fixture:
			continue
		var local_id: int = _next_id(id_map)
		id_map[h] = local_id
		var rel: Vector2i = h.axial - ax_origin
		var entry := {
			"id": local_id,
			"script": (h.get_script() as Script).resource_path,
			"class": _class_name_of(h),
			"axial": [rel.x, rel.y],
			"rotation": h.rotation_index,
			"state": h.serialize_state(canvas),
		}
		if h.has_inner_level() and h.inner_level != null:
			entry["inner"] = _serialize_inner(h.inner_level, canvas, id_map)
		hexes_out.append(entry)
	# Collect every wire whose BOTH endpoints fall inside the subset.
	# Wires that cross the boundary (one endpoint outside) and open /
	# unconnected wires (no input endpoint) are both dropped — keeping
	# them produces dangling cells that paste badly at a new anchor.
	# We walk each selected hex's level once; using a Dictionary as a
	# set keeps wires unique even when several selected hexes live on
	# the same level.
	var seen_wires: Dictionary = {}
	var wires_out: Array = []
	for h in subset:
		if h.level == null:
			continue
		for w in h.level.wires:
			if seen_wires.has(w):
				continue
			if not subset_set.has(w.output_node):
				continue
			if w.input_node == null or not subset_set.has(w.input_node):
				continue
			seen_wires[w] = true
			var sw = _serialize_wire(w, id_map, ax_origin)
			if sw != null:
				wires_out.append(sw)
	payload["hexes"] = hexes_out
	payload["wires"] = wires_out
	return payload


static func _centroid_axial(subset: Array) -> Vector2i:
	if subset.is_empty():
		return Vector2i.ZERO
	var sx: int = 0
	var sy: int = 0
	for h in subset:
		sx += h.axial.x
		sy += h.axial.y
	# Integer rounding to the nearest axial cell. The cursor lands on
	# (or near) the geometric middle of the selection, which feels
	# more natural than min-axial (which puts the anchor at the
	# top-left corner of the bounding box).
	return Vector2i(
		int(roundf(float(sx) / float(subset.size()))),
		int(roundf(float(sy) / float(subset.size()))),
	)


# Recursive worker. `id_map` is `{HexNode -> int}` populated as we walk
# so wires can reference their endpoints by id. `skip` is the optional
# fixture (DoHex at root, anchor at inner levels) that we don't emit as
# a hex but DO record an id for, so wires touching it round-trip.
static func _serialize_level(
	level: HexLevel,
	canvas,
	id_map: Dictionary,
	origin: Vector2i,
	skip: HexNode = null,
) -> Dictionary:
	var hexes_out: Array = []
	var fixture_id: int = -1
	# Pre-assign an id to `skip` so wires touching it know their endpoint.
	# The skipped fixture itself is NOT emitted in `hexes` — it gets
	# recreated by the editor when the blueprint is stamped (DoHex at
	# root, anchor at an inner level). `fixture_id` is recorded in the
	# returned level dict so the loader knows which id to rebind to its
	# own fresh fixture instance.
	if skip != null:
		fixture_id = _next_id(id_map)
		id_map[skip] = fixture_id
	for h in level.hexes:
		if h == skip:
			continue
		if h.is_fixture:
			# Other fixtures (a Match anchor sitting in a non-skip role,
			# for instance) aren't user-placed; emit their id only.
			id_map[h] = _next_id(id_map)
			continue
		var local_id: int = _next_id(id_map)
		id_map[h] = local_id
		var rel: Vector2i = h.axial - origin
		var entry := {
			"id": local_id,
			"script": (h.get_script() as Script).resource_path,
			"class": _class_name_of(h),
			"axial": [rel.x, rel.y],
			"rotation": h.rotation_index,
			"state": h.serialize_state(canvas),
		}
		if h.has_inner_level() and h.inner_level != null:
			entry["inner"] = _serialize_inner(h.inner_level, canvas, id_map)
		hexes_out.append(entry)
	var wires_out: Array = []
	for w in level.wires:
		var serialized_wire = _serialize_wire(w, id_map, origin)
		if serialized_wire != null:
			wires_out.append(serialized_wire)
	var result := {"hexes": hexes_out, "wires": wires_out}
	if fixture_id >= 0:
		result["fixture_id"] = fixture_id
	# A fixture can own an inner level of its own (a ListAnchor's
	# continuation block). It isn't emitted in `hexes`, so its chain
	# would be lost without a level-body `inner` key. Root levels are
	# unaffected — the DoHex has no inner level.
	if skip != null and skip.has_inner_level() and skip.inner_level != null:
		result["inner"] = _serialize_inner(skip.inner_level, canvas, id_map)
	return result


static func _serialize_inner(level: HexLevel, canvas, id_map: Dictionary) -> Dictionary:
	# Inner levels anchor at (0,0) — their hexes' axials are already
	# relative to the anchor, so no offset is applied. The anchor itself
	# is the "skip" (fixture) for this level; the editor recreates it
	# from the parent hex's `create_inner_anchor`.
	var body := _serialize_level(level, canvas, id_map, Vector2i.ZERO, level.anchor)
	body["kind"] = "level"
	return body


static func _serialize_wire(w: HexWire, id_map: Dictionary, origin: Vector2i):
	if w.output_node == null or not id_map.has(w.output_node):
		return null
	# Open (unconnected) wires are valid blueprint content — they capture
	# cable-planning intent. Inputless wires have a null input_node.
	var out_id: int = id_map[w.output_node]
	var in_id: int = -1
	var in_edge: int = -1
	if w.input_node != null and id_map.has(w.input_node):
		in_id = id_map[w.input_node]
		in_edge = w.input_edge
	# Canonicalize the cell sequence to always run output → input,
	# regardless of which end the user clicked first when drawing the
	# wire. The loader trusts this invariant and reconstructs with
	# `anchor_is_output = true`.
	var cells: Array = []
	if w.anchor_is_output:
		for cell in w.cells:
			var rel: Vector2i = cell.axial - origin
			cells.append({
				"axial": [rel.x, rel.y],
				"enter": cell.enter_edge,
				"exit": cell.exit_edge,
			})
	else:
		for i in range(w.cells.size() - 1, -1, -1):
			var cell = w.cells[i]
			var rel: Vector2i = cell.axial - origin
			cells.append({
				"axial": [rel.x, rel.y],
				"enter": cell.exit_edge,
				"exit": cell.enter_edge,
			})
	return {
		"output": [out_id, w.output_edge],
		"input": [in_id, in_edge],
		"cells": cells,
		"open": w.is_open,
	}


# Walk a hex's class hierarchy (script + base scripts) for the first
# `class_name` declaration. Falls back to the script's file basename
# when no `class_name` is declared (most leaf node scripts).
static func _class_name_of(node: Node) -> String:
	var s: Script = node.get_script()
	while s != null:
		var name: String = s.get_global_name()
		if not name.is_empty():
			return name
		s = s.get_base_script()
	# Last-resort fallback: derive a name from the script path.
	var path: String = (node.get_script() as Script).resource_path
	if path.is_empty():
		return ""
	return path.get_file().get_basename()


static func _next_id(id_map: Dictionary) -> int:
	return id_map.size()


# ── String wrapping ─────────────────────────────────────────────────────────

# Wrap a payload as `hxk1:<base64(gzip(json))>`. Compact (no whitespace)
# JSON keeps the string short enough to paste into chat.
static func encode(payload: Dictionary) -> String:
	var json: String = JSON.stringify(payload)
	var raw: PackedByteArray = json.to_utf8_buffer()
	var gz: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	return STRING_PREFIX + Marshalls.raw_to_base64(gz)


# Inverse of `encode`. Returns null on malformed input (bad prefix,
# corrupt base64, gzip / JSON failure, schema mismatch).
static func decode(s: String) -> Variant:
	if not s.begins_with(STRING_PREFIX):
		return null
	var b64: String = s.substr(STRING_PREFIX.length()).strip_edges()
	var gz: PackedByteArray = Marshalls.base64_to_raw(b64)
	if gz.is_empty():
		return null
	# Decompressed size is unknown ahead of time. GZIP carries it in its
	# trailer, but PackedByteArray.decompress() needs a buffer size — we
	# pass a generous upper bound; the helper truncates to the real size.
	var raw: PackedByteArray = gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		return null
	if not (json.data is Dictionary):
		return null
	var payload: Dictionary = json.data
	if int(payload.get("version", 0)) > SCHEMA_VERSION:
		# Forward-incompatible — surface as null so the loader can show
		# a clear message. Equal or lower versions are accepted.
		return null
	return payload
