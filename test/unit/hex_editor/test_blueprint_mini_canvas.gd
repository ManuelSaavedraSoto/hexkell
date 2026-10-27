extends GutTest
## BlueprintMiniCanvas — read-only viewer used by the chapter intro
## dialog (and, later, the blueprint library preview). Verifies the
## encode → decode → render round-trip pulls placed hexes back into
## the scene tree, that the DoHex fixture's `display_value` survives
## via the new `fixture_state` field on `serialize_root`, and that a
## malformed string fails gracefully so the dialog's fallback chain
## can keep going.

const MINI_CANVAS := preload(
	"res://scenes/gui/blueprint_library/mini_canvas/blueprint_mini_canvas.tscn")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
const IntLiteralHex := preload(
	"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")


func test_loads_string_and_populates_nodes() -> void:
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	var encoded := _encode_int_literal_only_payload(5, Vector2i(-2, 0))
	assert_true(mini.load_blueprint_string(encoded),
			"Decode + load should succeed on a well-formed payload")
	await get_tree().process_frame

	# One IntLiteralHex back in the tree (no fixture present in this
	# minimal payload — `serialize_subset` is used so no fixture_id).
	var nodes_layer: Node2D = mini.get_node("Nodes")
	assert_eq(nodes_layer.get_child_count(), 1,
			"Mini-canvas should render the single hex from the payload")


func test_round_trips_do_hex_display_value_via_fixture_state() -> void:
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	var encoded := _encode_root_with_do_display("42")
	assert_true(mini.load_blueprint_string(encoded))
	await get_tree().process_frame

	# The mini-canvas always creates a fresh DoHex when the payload has
	# a `fixture_id`; `restore_state` should have run with the saved
	# display_value so the body label shows "42" instead of "do".
	var nodes_layer: Node2D = mini.get_node("Nodes")
	var found: DoHex = null
	for child in nodes_layer.get_children():
		if child is DoHex:
			found = child
			break
	assert_not_null(found, "Mini-canvas should instantiate the DoHex fixture")
	assert_eq(found.display_value, "42",
			"DoHex.display_value should round-trip via fixture_state")


func test_auto_frame_fits_all_hexes_in_viewport() -> void:
	# The preview has no pan/zoom — the snug auto-fit must guarantee
	# every hex (center ± HEX_SIZE) lands inside the viewport.
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	var a: IntLiteralHex = HexNode.from_script(IntLiteralHex)
	var b: IntLiteralHex = HexNode.from_script(IntLiteralHex)
	add_child_autofree(a)
	add_child_autofree(b)
	await get_tree().process_frame
	a.set_axial(Vector2i(-4, 0))
	b.set_axial(Vector2i(4, 2))
	var payload := BlueprintCodec.serialize_subset(
		[a, b], null, "frame-smoke", "", "", Vector2i.ZERO)
	assert_true(mini.load_blueprint_dict(payload))
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera2D = mini.get_node("Camera2D")
	var zoom: float = cam.zoom.x
	assert_between(zoom, mini.ZOOM_MIN, mini.ZOOM_MAX,
			"Fitted zoom should respect the auto-fit bounds")
	var half_view: Vector2 = mini.get_viewport_rect().size / (2.0 * zoom)
	for hex in mini.get_node("Nodes").get_children():
		var offset: Vector2 = (hex as Node2D).position - cam.position
		assert_true(
				absf(offset.x) + HexNode.HEX_SIZE <= half_view.x + 0.5
				and absf(offset.y) + HexNode.HEX_SIZE <= half_view.y + 0.5,
				"Hex at %s should fit inside the framed view" % hex.position)


func test_auto_frame_single_hex_uses_fit_math_not_fixed_zoom() -> void:
	# A single hex used to short-circuit to zoom=1; the grown bbox now
	# routes it through the same snug-fit path (capped at ZOOM_MAX).
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	var encoded := _encode_int_literal_only_payload(7, Vector2i(3, -1))
	assert_true(mini.load_blueprint_string(encoded))
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera2D = mini.get_node("Camera2D")
	var hex: Node2D = mini.get_node("Nodes").get_child(0)
	assert_almost_eq(cam.position, hex.position, Vector2(0.01, 0.01),
			"Camera should center on the lone hex")
	var vp: Vector2 = mini.get_viewport_rect().size
	var expected: float = clampf(
			minf(vp.x, vp.y) / (HexNode.HEX_SIZE * 2.0)
					* (1.0 - mini.FIT_MARGIN),
			mini.ZOOM_MIN, mini.ZOOM_MAX)
	assert_almost_eq(cam.zoom.x, expected, 0.01,
			"Single hex should get the snug fit, not a hardcoded zoom")


func test_preview_applies_saved_rotation_to_slots() -> void:
	# A hex saved with a non-zero rotation must render rotated in the
	# preview: rotation is baked by `_build_slots()` remapping each logical
	# edge to physical `(logical + rotation_index) % 6`. The bug set
	# `rotation_index` AFTER `add_child` (which runs `_ready`/`_build_slots`
	# synchronously), so slots built at rotation 0 and never rebuilt.
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	# IntLiteralHex outputs on logical edge 0; rotated 2 steps its output
	# slot must light physical edge (0 + 2) % 6 == 2, not 0.
	var src: IntLiteralHex = HexNode.from_script(IntLiteralHex)
	add_child_autofree(src)
	await_idle_frame()
	src.value = 9
	src.set_axial(Vector2i.ZERO)
	src.set_rotation_index(2)
	var payload := BlueprintCodec.serialize_subset(
		[src], null, "rot", "", "", Vector2i.ZERO)

	assert_true(mini.load_blueprint_dict(payload))
	await get_tree().process_frame
	await get_tree().process_frame

	var hex: HexNode = mini.get_node("Nodes").get_child(0)
	assert_eq(hex.rotation_index, 2, "Saved rotation should round-trip")
	assert_true(hex._active_edge_map.has(2),
			"Output slot must be remapped to the rotated physical edge (2)")
	assert_false(hex._active_edge_map.has(0),
			"Unrotated physical edge 0 must NOT be the active output")


func test_decode_failure_returns_false_and_does_not_crash() -> void:
	var mini := MINI_CANVAS.instantiate()
	add_child_autofree(mini)
	await get_tree().process_frame

	assert_false(mini.load_blueprint_string("not a blueprint"),
			"Malformed strings should fail gracefully")


# ── helpers ───────────────────────────────────────────────────────

func _encode_int_literal_only_payload(value: int, axial: Vector2i) -> String:
	# `serialize_subset` produces a fixture-free payload; perfect for
	# verifying the bare populate-nodes path without dragging the
	# DoHex fixture into the assertion.
	var hex: IntLiteralHex = HexNode.from_script(IntLiteralHex)
	add_child_autofree(hex)
	await_idle_frame()
	hex.value = value
	hex.set_axial(axial)
	var payload := BlueprintCodec.serialize_subset(
		[hex], null, "smoke", "", "", Vector2i.ZERO)
	return BlueprintCodec.encode(payload)


func _encode_root_with_do_display(display: String) -> String:
	var level: HexLevel = HexLevel.new()
	var do_hex: DoHex = HexNode.from_script(DoHex)
	add_child_autofree(do_hex)
	await_idle_frame()
	do_hex.set_display_value(display)
	level.hexes.append(do_hex)
	var payload := BlueprintCodec.serialize_root(
		level, null, do_hex, "smoke", "", "", Vector2i.ZERO)
	return BlueprintCodec.encode(payload)


func await_idle_frame() -> void:
	# from_script() instantiates a scene — we need one frame for its
	# @onready refs to bind before the test mutates state on it.
	await get_tree().process_frame
