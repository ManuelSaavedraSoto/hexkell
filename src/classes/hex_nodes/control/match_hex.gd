extends HexNode
## `match S with | pat1 = body1 | pat2 = body2 | …`.
##
## Outer face:
##   NW (logical 4) → scrutinee `S`
##   E  (logical 0) → matched value
##
## Inner level: a MatchAnchor at (0,0) with one branch per pattern.
## Each branch carries a pattern inscription and a wire-receiving slot
## on the same edge; the user wires that branch's body (built using
## the pattern's bindings) into the slot.
##
## Arity is 1–5, configurable from the sidebar. Changing arity grows or
## shrinks the inner anchor in place (clockwise-from-NE edge order, via
## `HexMath.edges_for_arity`): adding a branch appends an empty slot and
## removing one drops only that branch's slot and its wire — the rest of
## the body survives. Default arity is 2.

var arity: int = 2
var patterns: Array = ["_", "_"]

var _title_node: Label


func _init() -> void:
	input_edges = [4]    # NW = scrutinee
	output_edges = [0]   # E  = matched value
	input_role_names = {4: "scrutinee"}
	output_role_names = {0: "result"}


func _setup_content() -> void:
	_title_node = Label.new()
	_title_node.text = "match"
	_title_node.add_theme_font_size_override("font_size", 20)
	_title_node.add_theme_color_override("font_color", Color.WHITE)
	_title_node.size = Vector2(80, 28)
	_title_node.position = Vector2(-40, -14)
	_title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_title_node)


func _copy_state_to(other: HexNode) -> void:
	other.arity = arity
	other.patterns = patterns.duplicate()


func serialize_state(_canvas) -> Dictionary:
	var pats: Array = []
	for p in patterns:
		pats.append(String(p))
	return {"arity": arity, "patterns": pats}


func restore_state(state: Dictionary, _canvas) -> void:
	arity = clamp(int(state.get("arity", 2)), 1, HexMath.MAX_ARITY)
	var raw: Array = state.get("patterns", [])
	patterns = []
	for i in arity:
		patterns.append(String(raw[i]) if i < raw.size() else "_")


func get_config_title() -> String:
	return "Match"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()

	# Arity SpinBox. The editor owns the change (`arity_change_requested`):
	# it grows/shrinks the anchor in place and drops only a removed
	# branch's wire, then reopens the sidebar to rebuild this UI.
	var arity_row := VBoxContainer.new()
	var arity_lbl := Label.new()
	arity_lbl.text = "Branches"
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

	# Per-branch pattern builder. The Tree's leaf option buttons pick a
	# pattern kind; compound kinds (cons / tuple / list) grow follow-up
	# sub-slots. Each branch re-emits its canonical source string, which
	# we keep storing (save format + scope stay string-based).
	var tree := MatchPatternTree.new()
	tree.custom_minimum_size = Vector2(0, 150)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.set_branches(patterns)
	tree.pattern_edited.connect(func(idx: int, src: String) -> void:
		if idx < 0 or idx >= patterns.size():
			return
		patterns[idx] = src
		if inner_level != null and inner_level.anchor != null:
			inner_level.anchor.set_pattern_at(idx, src)
	)
	box.add_child(tree)

	var hint := Label.new()
	hint.text = "Pick a kind per branch; cons / tuple / list grow sub-slots.\nNames bind variables from the identifier palette.\nRemoving a branch deletes only that branch's body wire."
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func has_inner_level() -> bool:
	return true


func level_label() -> String:
	return "match"


func create_inner_anchor() -> HexNode:
	var anchor = HexNode.from_script(load("res://src/classes/hex_nodes/fixtures/match_anchor.gd"))
	anchor.configure(patterns.duplicate(), HexMath.edges_for_arity(arity))
	return anchor


# Grow / shrink the branch set in place. Resizes `patterns` and, when the
# inner level already exists, reconfigures the live anchor on the
# prefix-stable edge order so surviving branches keep their slot + wire.
func apply_arity(n: int) -> void:
	arity = n
	while patterns.size() < arity:
		patterns.append("_")
	while patterns.size() > arity:
		patterns.pop_back()
	if inner_level != null and inner_level.anchor != null:
		inner_level.anchor.reconfigure(patterns.duplicate(), HexMath.edges_for_arity(arity))


func to_source(canvas) -> String:
	var scrutinee := _input_source(canvas, 4)
	var branches: Array[String] = []
	if inner_level != null and inner_level.anchor != null:
		var anchor = inner_level.anchor
		for i in anchor.patterns.size():
			var edge: int = int(anchor.branch_edges[i])
			var body_node = canvas.get_input_for(anchor, edge)
			var body: String = "_HOLE_"
			if body_node != null:
				body = body_node.to_source(canvas)
			branches.append("| %s = %s" % [String(anchor.patterns[i]), body])
	if branches.is_empty():
		for pat in patterns:
			branches.append("| %s = _HOLE_" % String(pat))
	return "(match %s with %s)" % [scrutinee, " ".join(branches)]
