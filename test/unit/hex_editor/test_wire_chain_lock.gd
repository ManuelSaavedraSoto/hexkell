extends GutTest
## Chain-point (lock) bookkeeping on HexWire: pressing C pins the tail cell
## as a chain point, multiple presses stack waypoints, and toggling a
## locked cell drops it and every later chain point while re-opening the
## tail. Pure logic — no scene needed.

const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")


func _wire_with_cells(count: int) -> HexWire:
	var w := HexWire.new()
	for i in count:
		# Walk east one cell at a time; axials just need to be distinct.
		w.cells.append(HexWire.make_cell(Vector2i(i, 0), 0, 3))
	return w


func test_add_lock_pins_tail_and_sets_prefix() -> void:
	var w := _wire_with_cells(3)
	w.add_lock()
	assert_eq(w.lock_indices, [2] as Array[int], "tail index is recorded")
	assert_eq(w.anchored_count, 3, "routing prefix covers all cells")


func test_add_lock_is_idempotent_at_same_tail() -> void:
	var w := _wire_with_cells(3)
	w.add_lock()
	w.add_lock()
	assert_eq(w.lock_indices, [2] as Array[int], "no duplicate lock at same tail")


func test_second_lock_after_growth_stacks_waypoint() -> void:
	var w := _wire_with_cells(3)
	w.add_lock()
	w.cells.append(HexWire.make_cell(Vector2i(3, 0), 0, 3))
	w.cells.append(HexWire.make_cell(Vector2i(4, 0), 0, 3))
	w.add_lock()
	assert_eq(w.lock_indices, [2, 4] as Array[int], "two chain points")
	assert_eq(w.anchored_count, 5)


func test_unlock_from_axial_drops_it_and_later_points() -> void:
	var w := _wire_with_cells(5)
	w.cells[2].exit_edge = 3
	# Lock at index 2, then at index 4.
	w.lock_indices = [2, 4]
	w.anchored_count = 5
	var first_axial: Vector2i = w.cells[2].axial
	assert_true(w.unlock_from_axial(first_axial), "locked cell is found")
	assert_eq(w.lock_indices, [] as Array[int], "both chain points cleared")
	assert_eq(w.anchored_count, 0, "tail fully re-opened")


func test_unlock_later_point_keeps_earlier() -> void:
	var w := _wire_with_cells(5)
	w.lock_indices = [2, 4]
	w.anchored_count = 5
	var second_axial: Vector2i = w.cells[4].axial
	assert_true(w.unlock_from_axial(second_axial))
	assert_eq(w.lock_indices, [2] as Array[int], "earlier chain point survives")
	assert_eq(w.anchored_count, 3, "prefix shrinks to one past first lock")


func test_unlock_unlocked_cell_returns_false() -> void:
	var w := _wire_with_cells(3)
	w.add_lock()
	assert_false(w.unlock_from_axial(Vector2i(0, 0)), "cell 0 is not a chain point")
	assert_eq(w.lock_indices, [2] as Array[int], "lock state unchanged")


func test_locked_axials_maps_indices() -> void:
	var w := _wire_with_cells(5)
	w.lock_indices = [1, 3]
	assert_eq(w.locked_axials(), [Vector2i(1, 0), Vector2i(3, 0)])
