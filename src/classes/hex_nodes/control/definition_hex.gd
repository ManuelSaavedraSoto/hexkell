extends HexNode
## Top-level definition `NAME pat1 pat2 … = body`.
##
## Definitions float at level 0 alongside the Do hex. They have no
## wired slots on their outer face — the identifier is wirelessly
## emitted into the level-0 scope, and the patterns are inscribed in
## the sidebar (and on the inner anchor's emit sides).
##
## Press Q to descend into the body; the inner-level anchor emits one
## binding per pattern, plus a return slot the body wires into.
## Multiple DefinitionHex instances with the same identifier become
## multi-equation pattern matching (the language parser merges them
## into one curried `match`). For now ordering follows the level's
## `hexes` array order — placement order.

var identifier_palette_index: int = 0
var arity: int = 1
var patterns: Array = ["_"]

var _name_label: Label
var _glyph_label: Label
var _keyword_label: Label


func _init() -> void:
	# No wired inputs and no wired outputs: definitions are wireless at
	# level 0. The identifier is in scope; the body lives inside.
	input_edges = []
	output_edges = []


func _setup_content() -> void:
	_glyph_label = Label.new()
	_glyph_label.add_theme_font_size_override("font_size", 22)
	_glyph_label.size = Vector2(80, 26)
	_glyph_label.position = Vector2(-40, -28)
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_glyph_label)

	_keyword_label = Label.new()
	_keyword_label.text = "def"
	_keyword_label.add_theme_font_size_override("font_size", 13)
	_keyword_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	_keyword_label.size = Vector2(80, 16)
	_keyword_label.position = Vector2(-40, -4)
	_keyword_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keyword_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_keyword_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	_name_label.size = Vector2(80, 16)
	_name_label.position = Vector2(-40, 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_name_label)
	_refresh()


func _refresh() -> void:
	if _glyph_label:
		_glyph_label.text = IdentifierPalette.glyph_of(identifier_palette_index)
		_glyph_label.add_theme_color_override("font_color", IdentifierPalette.color_of(identifier_palette_index))
	if _name_label:
		_name_label.text = IdentifierPalette.name_of(identifier_palette_index)


func _copy_state_to(other: HexNode) -> void:
	other.identifier_palette_index = identifier_palette_index
	other.arity = arity
	other.patterns = patterns.duplicate()


func serialize_state(_canvas) -> Dictionary:
	var pats: Array = []
	for p in patterns:
		pats.append(String(p))
	return {
		"identifier_palette_index": identifier_palette_index,
		"arity": arity,
		"patterns": pats,
	}


func restore_state(state: Dictionary, _canvas) -> void:
	identifier_palette_index = int(state.get("identifier_palette_index", 0))
	arity = clamp(int(state.get("arity", 1)), 1, HexMath.MAX_ARITY)
	var raw: Array = state.get("patterns", [])
	patterns = []
	for i in arity:
		patterns.append(String(raw[i]) if i < raw.size() else "_")


func get_config_title() -> String:
	return "Definition"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()

	# Identifier picker.
	var name_row := VBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Name"
	name_row.add_child(name_lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in IdentifierPalette.user_count():
		opt.add_item("%s  %s" % [IdentifierPalette.glyph_of(i), IdentifierPalette.name_of(i)], i)
	opt.selected = identifier_palette_index
	opt.item_selected.connect(func(idx: int) -> void:
		identifier_palette_index = idx
		_refresh()
	)
	name_row.add_child(opt)
	box.add_child(name_row)

	# Arity SpinBox.
	var arity_row := VBoxContainer.new()
	var arity_lbl := Label.new()
	arity_lbl.text = "Arity"
	arity_row.add_child(arity_lbl)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 5
	spin.step = 1
	spin.value = arity
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void:
		arity_change_requested.emit(self, int(v))
	)
	arity_row.add_child(spin)
	box.add_child(arity_row)

	# Pattern editors per argument.
	for i in patterns.size():
		var row := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Arg %d pattern" % (i + 1)
		row.add_child(lbl)
		var le := LineEdit.new()
		le.text = patterns[i]
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var captured_idx := i
		le.text_changed.connect(func(new_text: String) -> void:
			patterns[captured_idx] = new_text
			if inner_level != null and inner_level.anchor != null:
				inner_level.anchor.set_emission_at(captured_idx, new_text)
		)
		row.add_child(le)
		box.add_child(row)

	var hint := Label.new()
	hint.text = "Emits  NAME pat1 pat2 … = body  at level 0.\nMultiple Definition hexes with the same name become\nmulti-equation pattern matching.\nChanging arity keeps the body; only the emitted patterns change."
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "def %s" % IdentifierPalette.name_of(identifier_palette_index)


func create_inner_anchor() -> HexNode:
	var anchor: HexNode = HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/anchor_hex.gd"))
	anchor.emit_logical_edges = HexMath.edges_for_arity(arity)
	anchor.emit_labels = patterns.duplicate()
	return anchor


# Grow / shrink the argument-pattern set in place. Definitions are
# wireless on the outer face and their inner anchor exposes a single
# shared return slot, so no wire is ever orphaned — only the emitted
# pattern bindings change.
func apply_arity(n: int) -> void:
	arity = n
	while patterns.size() < arity:
		patterns.append("_")
	while patterns.size() > arity:
		patterns.pop_back()
	if inner_level != null and inner_level.anchor != null:
		inner_level.anchor.set_emissions(HexMath.edges_for_arity(arity), patterns.duplicate())


# Definitions are wireless level-0 bindings: the function name is in
# scope for every sibling at the same level (including the DoHex's
# main expression). `IdentifierScope` calls this on each sibling to
# fold the name in.
func sibling_scope_name() -> String:
	return IdentifierPalette.name_of(identifier_palette_index)


func to_source(canvas) -> String:
	var name := IdentifierPalette.name_of(identifier_palette_index)
	var pats: Array[String] = []
	for p in patterns:
		pats.append(String(p))
	var body := "_HOLE_"
	if inner_level != null and inner_level.anchor != null:
		body = inner_level.anchor.to_source(canvas)
	if pats.is_empty():
		return "%s = %s" % [name, body]
	return "%s %s = %s" % [name, " ".join(pats), body]
