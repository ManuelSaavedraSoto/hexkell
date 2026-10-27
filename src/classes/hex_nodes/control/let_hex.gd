extends HexNode
## `let NAME = V in B`. NW = value (wired on the outer face). The body
## `B` lives in an inner level: press Q over this hex to descend. The
## inner anchor emits NAME so the body can refer to it.
##
## Subclasses (LetRecHex) flip `is_rec` so the emitted keyword becomes
## `let rec`, making NAME available inside V as well — required for
## self-recursive function values.

var palette_index: int = 0
# Subclasses set this true; LetRecHex does. Switches the emitted
# keyword and the visible label.
var is_rec: bool = false

var _name_label: Label
var _glyph_label: Label
var _keyword_label: Label


func _init() -> void:
	input_edges = [4]        # NW = value
	output_edges = [0]       # E = the let expression's value
	input_role_names = {4: "value"}
	output_role_names = {0: "result"}


func _setup_content() -> void:
	_glyph_label = Label.new()
	_glyph_label.add_theme_font_size_override("font_size", 22)
	_glyph_label.add_theme_color_override("font_color", IdentifierPalette.color_of(palette_index))
	_glyph_label.size = Vector2(60, 26)
	_glyph_label.position = Vector2(-30, -28)
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_glyph_label)

	var keyword := Label.new()
	keyword.text = "let rec" if is_rec else "let"
	keyword.add_theme_font_size_override("font_size", 14)
	keyword.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	keyword.size = Vector2(60, 16)
	keyword.position = Vector2(-30, -4)
	keyword.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keyword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(keyword)
	_keyword_label = keyword

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_name_label.size = Vector2(60, 16)
	_name_label.position = Vector2(-30, 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_name_label)
	_refresh()


func _refresh() -> void:
	if _glyph_label:
		_glyph_label.text = IdentifierPalette.glyph_of(palette_index)
		_glyph_label.add_theme_color_override("font_color", IdentifierPalette.color_of(palette_index))
	if _name_label:
		_name_label.text = IdentifierPalette.name_of(palette_index)


func _copy_state_to(other: HexNode) -> void:
	other.palette_index = palette_index
	other.is_rec = is_rec


func serialize_state(_canvas) -> Dictionary:
	# `is_rec` is per-class (LetRecHex sets it in `_init`), so we don't
	# round-trip it — the `script` field on the wrapping payload already
	# distinguishes Let from LetRec.
	return {"palette_index": palette_index}


func restore_state(state: Dictionary, _canvas) -> void:
	palette_index = int(state.get("palette_index", 0))


func get_config_title() -> String:
	return "Let Rec Binding" if is_rec else "Let Binding"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Bound identifier"
	box.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in IdentifierPalette.user_count():
		opt.add_item("%s  %s" % [IdentifierPalette.glyph_of(i), IdentifierPalette.name_of(i)], i)
	opt.selected = palette_index
	opt.item_selected.connect(func(idx: int) -> void:
		palette_index = idx
		_refresh()
		# Keep the inner anchor's emission in sync.
		if inner_level != null and inner_level.anchor != null:
			inner_level.anchor.set_emission(IdentifierPalette.name_of(idx))
	)
	box.add_child(opt)
	var hint := Label.new()
	hint.text = "Press Q over the hex to enter its body."
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "%s %s" % ["let rec" if is_rec else "let", IdentifierPalette.name_of(palette_index)]


func create_inner_anchor() -> HexNode:
	var anchor: HexNode = HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/anchor_hex.gd"))
	anchor.emit_labels = [IdentifierPalette.name_of(palette_index)]
	return anchor


# Let-rec broadcasts its bound name wirelessly into the level it
# sits in so the value expression (which wires into the let-rec's
# NW slot at the SAME level — not the inner level where the body
# lives) can reference itself for recursion. Plain `let` doesn't
# contribute (only the body inside the inner level sees the binding
# via the anchor chain); returning empty silently no-ops in
# `IdentifierScope`.
func sibling_scope_name() -> String:
	return IdentifierPalette.name_of(palette_index) if is_rec else ""


func to_source(canvas) -> String:
	var v := _input_source(canvas, 4)
	var b := "_HOLE_"
	if inner_level != null and inner_level.anchor != null:
		# The body is whatever feeds the anchor's return slot. Recurse
		# through the anchor so `get_input_for` looks at the inner
		# level's wires (HexNode.level dispatches that for us).
		b = inner_level.anchor.to_source(canvas)
	var keyword := "let rec" if is_rec else "let"
	return "(%s %s = %s in %s)" % [keyword, IdentifierPalette.name_of(palette_index), v, b]
