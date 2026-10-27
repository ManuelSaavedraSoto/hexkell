extends HexNode
## Anonymous function `\p1 p2 … -> body`. Arity 1–5; the outer face
## carries one wired argument input per parameter (each optional —
## leaving them empty produces the function value; wiring all of them
## produces a fully applied form; mixing is allowed and gets emitted
## as partial application).
##
## Inner level holds the body. The anchor at (0,0) emits the parameter
## names on the same edges the outer face takes their arguments from,
## so the inner anchor's geometry mirrors the outer hex. Slot edges
## follow the canonical clockwise-from-NE order (`HexMath.edges_for_arity`)
## so changing arity grows/shrinks the outer param face in place.

var arity: int = 1
var param_palette_indices: Array[int] = [0]

var _keyword_label: Label


func _init() -> void:
	# `.assign` (not `=`) keeps the `Array[int]` type tag on
	# `input_edges` / `optional_input_edges` — assigning the untyped
	# const array via `=` trips the runtime type check and silently
	# leaves the field empty.
	input_edges.assign(HexMath.edges_for_arity(arity))
	output_edges = [0]
	output_role_names = {0: "function value"}
	_apply_role_names()
	optional_input_edges.assign(HexMath.edges_for_arity(arity))


func _apply_role_names() -> void:
	# Each parameter brands its own input edge with the identifier's
	# glyph, tinted by that identifier's colour. Defaults seed
	# red → green → blue → … as arity grows (see `_next_free_param_index`).
	input_role_names.clear()
	input_role_labels.clear()
	input_role_label_colors.clear()
	for i in input_edges.size():
		var edge: int = input_edges[i]
		input_role_names[edge] = "arg %d" % (i + 1)
		var pidx: int = param_palette_indices[i] if i < param_palette_indices.size() else 0
		input_role_labels[edge] = IdentifierPalette.glyph_of(pidx)
		input_role_label_colors[edge] = IdentifierPalette.color_of(pidx)


# Lowest identifier index not already bound by another parameter, so a
# new param defaults to a distinct colour cycling red → green → blue → …
func _next_free_param_index() -> int:
	for cand in IdentifierPalette.user_count():
		if cand not in param_palette_indices:
			return cand
	return 0


func _setup_content() -> void:
	_keyword_label = Label.new()
	_keyword_label.text = "λ"
	_keyword_label.add_theme_font_size_override("font_size", 24)
	_keyword_label.add_theme_color_override("font_color", Color.WHITE)
	_keyword_label.size = Vector2(60, 28)
	_keyword_label.position = Vector2(-30, -24)
	_keyword_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keyword_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_keyword_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_keyword_label)
	# Per-param glyphs live on their edges now (see `_apply_role_names`),
	# so there's no shared centre label to build.
	_refresh()


func _refresh() -> void:
	# Rebuild the per-edge glyph labels + colours from the current
	# parameters and repaint them.
	_apply_role_names()
	_update_role_labels()


func _copy_state_to(other: HexNode) -> void:
	other.arity = arity
	other.param_palette_indices = param_palette_indices.duplicate()
	other.input_edges.assign(HexMath.edges_for_arity(arity))
	other.optional_input_edges.assign(HexMath.edges_for_arity(arity))
	other._apply_role_names()


func serialize_state(_canvas) -> Dictionary:
	return {
		"arity": arity,
		"param_palette_indices": param_palette_indices.duplicate(),
	}


func restore_state(state: Dictionary, _canvas) -> void:
	arity = clamp(int(state.get("arity", 1)), 1, HexMath.MAX_ARITY)
	var raw: Array = state.get("param_palette_indices", [])
	param_palette_indices = []
	for i in arity:
		var v: int = int(raw[i]) if i < raw.size() else 0
		param_palette_indices.append(v)
	# `.assign` preserves the declared `Array[int]` typing on
	# `input_edges` — plain `=` from an untyped const array trips the
	# runtime type check.
	input_edges.assign(HexMath.edges_for_arity(arity))
	optional_input_edges.assign(HexMath.edges_for_arity(arity))
	_apply_role_names()


func get_config_title() -> String:
	return "Lambda"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()

	# Arity SpinBox. The editor owns the change (`arity_change_requested`):
	# it grows/shrinks the outer param face + the anchor's emissions in
	# place and drops only a removed param's argument wire.
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

	# Per-parameter identifier picker.
	for i in param_palette_indices.size():
		var row := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Param %d" % (i + 1)
		row.add_child(lbl)
		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for j in IdentifierPalette.user_count():
			opt.add_item("%s  %s" % [IdentifierPalette.glyph_of(j), IdentifierPalette.name_of(j)], j)
		opt.selected = param_palette_indices[i]
		var captured_idx := i
		opt.item_selected.connect(func(idx: int) -> void:
			param_palette_indices[captured_idx] = idx
			_refresh()
			if inner_level != null and inner_level.anchor != null:
				inner_level.anchor.set_emission_at(captured_idx, IdentifierPalette.name_of(idx))
		)
		row.add_child(opt)
		box.add_child(row)

	var hint := Label.new()
	hint.text = "Press Q over the hex to enter its body."
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	if param_palette_indices.is_empty():
		return "λ"
	return "λ %s" % IdentifierPalette.name_of(param_palette_indices[0])


func create_inner_anchor() -> HexNode:
	var anchor: HexNode = HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/anchor_hex.gd"))
	anchor.emit_logical_edges = HexMath.edges_for_arity(arity)
	var labels: Array[String] = []
	for idx in param_palette_indices:
		labels.append(IdentifierPalette.name_of(idx))
	anchor.emit_labels = labels
	return anchor


# Grow / shrink the parameter set in place. Params ride the OUTER face,
# so this rebuilds the hex's own input slots (prefix-stable edge order,
# surviving args keep their slot + wire) and updates the inner anchor's
# emitted parameter names.
func apply_arity(n: int) -> void:
	arity = n
	while param_palette_indices.size() < arity:
		param_palette_indices.append(_next_free_param_index())
	while param_palette_indices.size() > arity:
		param_palette_indices.pop_back()
	input_edges.assign(HexMath.edges_for_arity(arity))
	optional_input_edges.assign(HexMath.edges_for_arity(arity))
	_refresh()
	rebuild_slots()
	if inner_level != null and inner_level.anchor != null:
		var labels: Array[String] = []
		for idx in param_palette_indices:
			labels.append(IdentifierPalette.name_of(idx))
		inner_level.anchor.set_emissions(HexMath.edges_for_arity(arity), labels)


# A lambda's parameters live on its OUTER face, so a shrink orphans an
# outer argument wire (not an inner-body wire).
func arity_slot_node() -> HexNode:
	return self


func to_source(canvas) -> String:
	var pnames: Array[String] = []
	for idx in param_palette_indices:
		pnames.append(IdentifierPalette.name_of(idx))
	var body := "_HOLE_"
	if inner_level != null and inner_level.anchor != null:
		body = inner_level.anchor.to_source(canvas)
	var lam := "(\\%s -> %s)" % [" ".join(pnames), body]
	# Emit application as `(lam a1 a2 ...)` for whichever args are wired.
	# Skipping unwired slots produces partial application.
	var args: Array[String] = []
	for edge in input_edges:
		var arg_node = canvas.get_input_for(self, edge)
		if arg_node != null:
			args.append(arg_node.to_source(canvas))
	if args.is_empty():
		return lam
	return "(%s %s)" % [lam, " ".join(args)]
