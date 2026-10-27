extends GutTest
## Wire auto-router behaviour: a straight glide in open space, bounded
## (<= ROUTE_LOOKAHEAD_HEXES) detours around obstacles, a full halt when
## boxed in, and the stuck wire rendering its ENTIRE length red.

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const HexMath := preload("res://src/statics/hex_math.gd")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")

var _saved_hex: Dictionary
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["hex"]["tabs"] = []
	SaveManager.current_data["hex"]["current_tab_id"] = 0
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	ChapterManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame
	# The router helpers use `_active_wire` as the except-wire when testing
	# whether a cell is blocked; any wire object will do.
	_editor._active_wire = HexWire.new()


func after_each() -> void:
	SaveManager.current_data["hex"] = _saved_hex
	ModalStack.reset(get_tree())


func _place(axial: Vector2i) -> HexNode:
	var hex: HexNode = HexNode.from_script(IntLiteralHex)
	_editor.nodes_layer.add_child(hex)
	hex.set_axial(axial)
	hex.level = _editor._current_level()
	_editor._current_level().hexes.append(hex)
	return hex


func _cell(axial: Vector2i, enter: int) -> Dictionary:
	return {"axial": axial, "enter_edge": enter, "exit_edge": -1}


# Open space: the next step heads straight at the target, no detour needed.
func test_glides_straight_toward_target_in_open_space() -> void:
	var cell := _cell(Vector2i(0, 0), 3)  # entered from the west
	var dir: int = _editor._best_progress_dir(cell, Vector2i(5, 0), {Vector2i(0, 0): true}, 5)
	assert_eq(dir, 0, "steps due East, straight at the target")


# A single blocker straight ahead: the direct step is gone, but a short
# way around exists well within the look-ahead budget.
func test_detours_around_a_single_blocker() -> void:
	_place(Vector2i(1, 0))  # block the cell straight ahead
	var cell := _cell(Vector2i(0, 0), 3)
	var visited := {Vector2i(0, 0): true}
	assert_eq(_editor._best_progress_dir(cell, Vector2i(3, 0), visited, 3), -1,
		"the straight step is blocked")
	var path: Array = _editor._bounded_detour_path(cell, Vector2i(3, 0), visited, 3)
	assert_false(path.is_empty(), "a short way around the single blocker is found")
	assert_true(path.size() <= 3, "the detour stays within the look-ahead budget")


# A wall taller than the budget can reach around: no valid <=3 hex detour
# lands the wire any closer, so the router reports no path (-> wire halts).
func test_wall_beyond_budget_yields_no_detour() -> void:
	for r in range(-3, 4):
		_place(Vector2i(1, r))  # solid one-column wall, 7 cells tall
	var cell := _cell(Vector2i(0, 0), 3)
	var path: Array = _editor._bounded_detour_path(cell, Vector2i(5, 0), {Vector2i(0, 0): true}, 5)
	assert_true(path.is_empty(),
		"no <=3 hex path slips past a wall this tall, so the router gives up")


# A stuck wire paints its WHOLE length onto the red error line, leaving the
# normal line empty — the loud "this route can't commit" signal.
func test_stuck_wire_paints_whole_length_red() -> void:
	var anchor := _place(Vector2i(0, 0))
	var w := HexWire.from_anchor(anchor, 0, true)
	w.cells = [_cell(Vector2i(1, 0), 3), _cell(Vector2i(2, 0), 3)]
	w.cells[0].exit_edge = 0
	w.line = HexWire.build_line(false)
	w.error_line = HexWire.build_line(true)

	w.is_stuck = false
	w.paint(Vector2(640.0, 0.0))
	assert_gt(w.line.get_point_count(), 0, "a healthy wire draws on the main line")
	assert_eq(w.error_line.get_point_count(), 0, "no red overlay while routing is valid")

	w.is_stuck = true
	w.paint(Vector2(640.0, 0.0))
	assert_eq(w.line.get_point_count(), 0, "a stuck wire clears the normal line")
	assert_gt(w.error_line.get_point_count(), 0, "the entire stuck wire renders red")

	w.line.queue_free()
	w.error_line.queue_free()
