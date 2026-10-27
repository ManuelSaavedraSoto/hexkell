extends GutTest
## Covers the tween/particle hex feedback that replaced the ripple shader:
## placement pop, connection edge-flash, and the wire-hover body highlight.

const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")


func _make_hex() -> HexNode:
	var h: HexNode = HexNode.from_script(IntLiteralHex)
	add_child_autofree(h)
	await get_tree().process_frame  # let _ready build the slots
	return h


# pop_in overshoots to 1.18x immediately, then springs back to 1.0.
func test_pop_in_overshoots_then_settles() -> void:
	var h := await _make_hex()
	h.pop_in()
	assert_almost_eq(h.scale.x, 1.18, 0.001, "pop starts scaled up")
	await wait_seconds(0.3)
	assert_almost_eq(h.scale.x, 1.0, 0.01, "pop settles back to resting scale")


# flash_edge brightens the connected edge's poly above its resting colour.
func test_flash_edge_brightens_then_is_set() -> void:
	var h := await _make_hex()
	var edges: Array = h.output_edges if not h.output_edges.is_empty() else h.input_edges
	assert_false(edges.is_empty(), "the test hex has at least one slot to flash")
	var logical: int = edges[0]
	var poly: Polygon2D = h._edge_nodes[h.physical_edge(logical)].poly
	var resting := poly.color
	h.flash_edge(logical)
	assert_gt(poly.color.v, resting.v, "the flashed edge is brighter than at rest")


# The wire-hover highlight brightens the body, and clearing restores it.
func test_wire_target_highlight_toggles_body_color() -> void:
	var h := await _make_hex()
	var resting := h.body_color
	h.set_wire_target_highlight(true)
	assert_eq(h._body_poly.color, resting.lightened(0.35), "highlight brightens the body")
	h.set_wire_target_highlight(false)
	assert_eq(h._body_poly.color, resting, "clearing restores the resting body colour")
