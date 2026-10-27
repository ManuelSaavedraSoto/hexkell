extends GutTest
## Lock-cell pop feedback on the wire chain overlay: pinning a chain point
## bounces that cell's cyan marker. Covers `pop_cell` / `clear` state.

const WireChainOverlay := preload("res://scenes/gui/hex_editor/wire_chain_overlay.gd")


func _overlay() -> WireChainOverlay:
	var o := WireChainOverlay.new()
	add_child_autofree(o)
	return o


func test_pop_cell_starts_a_bounce() -> void:
	var o := _overlay()
	await get_tree().process_frame
	o.pop_cell(Vector2i(2, 0))
	assert_eq(o._pop_axial, Vector2i(2, 0), "the popped cell is recorded")
	assert_not_null(o._pop_tween, "a bounce tween is running")
	await wait_seconds(0.35)
	assert_almost_eq(o._pop_scale, 1.0, 0.001, "the bounce settles back to 1.0")


func test_clear_kills_the_bounce() -> void:
	var o := _overlay()
	await get_tree().process_frame
	o.pop_cell(Vector2i(1, 0))
	o.clear()
	assert_null(o._pop_tween, "clear stops the bounce")
	assert_almost_eq(o._pop_scale, 1.0, 0.001, "scale resets on clear")
