extends GutTest
## Auto-computed DoHex display value (docs/TODO.md → "Editor canvas
## auto-computes DoHex.display_value"). When the chain wired into the
## active tab's Do is a literal-only static expression, the editor
## evaluates it via the interpreter and bakes the result into the Do
## body; dynamic or incomplete chains clear it back to "do".

const HEX_EDITOR_SCENE := preload("res://scenes/gui/hex_editor/hex_editor.tscn")
const HexWire := preload("res://scenes/gui/hex_editor/hex_wire.gd")
const HexNode := preload("res://src/classes/hex_nodes/hex_node.gd")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const AddHex := preload("res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd")
const IdentRefHex := preload("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd")

var _saved_hex: Dictionary
var _saved_autosave: bool
var _editor: Node


func before_each() -> void:
	_saved_hex = SaveManager.current_data["hex"].duplicate(true)
	_saved_autosave = SaveManager.get_auto_save()
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["hex"]["tabs"] = []
	SaveManager.current_data["hex"]["current_tab_id"] = 0
	# Keep the chapter-0 tutorial dormant (it hard-gates interactions).
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_editor = HEX_EDITOR_SCENE.instantiate()
	add_child_autofree(_editor)
	await get_tree().process_frame


func after_each() -> void:
	SaveManager.current_data["hex"] = _saved_hex
	SaveManager.current_data["preferences"]["auto_save"] = _saved_autosave


# Place `hex` on the active level and register it with the editor's
# node layer so to_source / get_input_for can see it.
func _attach(hex: HexNode, axial: Vector2i) -> HexNode:
	var level = _editor._current_level()
	hex.level = level
	hex.axial = axial
	level.hexes.append(hex)
	_editor.nodes_layer.add_child(hex)
	return hex


func _wire(from_node: HexNode, from_edge: int, to_node: HexNode, to_edge: int) -> void:
	var w := HexWire.new()
	w.output_node = from_node
	w.output_edge = from_edge
	w.input_node = to_node
	w.input_edge = to_edge
	var level = _editor._current_level()
	level.wires.append(w)


func test_literal_chain_bakes_static_value() -> void:
	var do_hex: HexNode = _editor.do_node
	var lit := _attach(HexNode.from_script(IntLiteralHex), Vector2i(4, 0))
	lit.value = 5
	# Far placement avoids the adjacency fallback kicking in for the
	# wrong edge; the explicit wire is what's under test.
	_wire(lit, 0, do_hex, 0)
	_editor._refresh_do_display_value()
	assert_eq(do_hex.display_value, "5",
			"An int literal wired into Do should bake its value")


func test_operator_chain_evaluates() -> void:
	var do_hex: HexNode = _editor.do_node
	var a := _attach(HexNode.from_script(IntLiteralHex), Vector2i(6, 0))
	a.value = 2
	var b := _attach(HexNode.from_script(IntLiteralHex), Vector2i(8, 0))
	b.value = 3
	var add := _attach(HexNode.from_script(AddHex), Vector2i(4, 4))
	_wire(a, 0, add, add.input_edges[0])
	_wire(b, 0, add, add.input_edges[1])
	_wire(add, add.output_edges[0], do_hex, 0)
	_editor._refresh_do_display_value()
	assert_eq(do_hex.display_value, "5",
			"2 + 3 wired through an Add hex should bake to 5")


func test_identifier_chain_stays_dynamic() -> void:
	var do_hex: HexNode = _editor.do_node
	do_hex.set_display_value("stale")
	var ident := _attach(HexNode.from_script(IdentRefHex), Vector2i(4, 0))
	_wire(ident, ident.output_edges[0], do_hex, 0)
	_editor._refresh_do_display_value()
	assert_eq(do_hex.display_value, "",
			"An identifier reference is not static — display must clear")


func test_incomplete_chain_clears_value() -> void:
	var do_hex: HexNode = _editor.do_node
	do_hex.set_display_value("stale")
	var add := _attach(HexNode.from_script(AddHex), Vector2i(4, 4))
	_wire(add, add.output_edges[0], do_hex, 0)  # both add inputs unwired
	_editor._refresh_do_display_value()
	assert_eq(do_hex.display_value, "",
			"A chain with unwired required inputs must clear the display")


func test_unwired_do_clears_value() -> void:
	var do_hex: HexNode = _editor.do_node
	do_hex.set_display_value("stale")
	_editor._refresh_do_display_value()
	assert_eq(do_hex.display_value, "",
			"An unwired Do shows the keyword, not a stale value")
