extends HexNode
## Identifier reference. Tinted by the chosen palette color; the glyph
## sits in the center. Click body to pick a name in the config sidebar.

var palette_index: int = 0
var _glyph_label: Label
var _name_label: Label


func _init() -> void:
	output_edges = [0]
	output_role_names = {0: "value"}
	_refresh_colors()


func _setup_content() -> void:
	_glyph_label = Label.new()
	_glyph_label.add_theme_font_size_override("font_size", 28)
	_glyph_label.add_theme_color_override("font_color", Color.WHITE)
	_glyph_label.size = Vector2(80, 36)
	_glyph_label.position = Vector2(-40, -28)
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_glyph_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_name_label.size = Vector2(80, 16)
	_name_label.position = Vector2(-40, 6)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_name_label)
	# Re-run color setup now that the labels exist so reserved-white
	# identifiers flip both labels to dark for contrast.
	_refresh_colors()
	_refresh_content()


func _on_scroll(dir: int) -> void:
	palette_index = posmod(palette_index + dir, IdentifierPalette.user_count())
	_refresh_colors()
	_refresh_content()


func _refresh_colors() -> void:
	var base := IdentifierPalette.color_of(palette_index)
	# Mid-tones are already deep enough; a light darken keeps the
	# identifier's hue recognizable on the hex body. The reserved
	# `white` slot (and any other light identifier) flips its labels
	# to dark so the text stays legible against a near-white body.
	var body := base.darkened(0.20)
	set_body_color(body)
	var label_color := HexPalette.white() if body.get_luminance() < 0.5 else HexPalette.black()
	if _glyph_label:
		_glyph_label.add_theme_color_override("font_color", label_color)
	if _name_label:
		_name_label.add_theme_color_override("font_color", label_color)


func _refresh_content() -> void:
	if _glyph_label:
		_glyph_label.text = IdentifierPalette.glyph_of(palette_index)
	if _name_label:
		_name_label.text = IdentifierPalette.name_of(palette_index)


func _copy_state_to(other: HexNode) -> void:
	other.palette_index = palette_index


func serialize_state(_canvas) -> Dictionary:
	return {"palette_index": palette_index}


func restore_state(state: Dictionary, _canvas) -> void:
	palette_index = int(state.get("palette_index", 0))
	_refresh_colors()


func get_config_title() -> String:
	return "Identifier"


func build_config_ui() -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Identifier"
	box.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.fit_to_longest_item = false
	# Show every entry — including the reserved `white` / `black` — so
	# the player sees them as discoverable options. Entries that
	# aren't bound at this hex's lexical position (no enclosing
	# Let / Lambda / Definition / Match-branch introduces them) read
	# as disabled with a hint, mirroring the reserved-without-job
	# treatment.
	var in_scope: Array = IdentifierScope.names_in_scope(self)
	for i in IdentifierPalette.count():
		var label_text := "%s  %s" % [IdentifierPalette.glyph_of(i), IdentifierPalette.name_of(i)]
		var pickable_here: bool = IdentifierPalette.is_pickable_in_scope(i, in_scope)
		if not pickable_here:
			if i >= IdentifierPalette.user_count() and not IdentifierPalette.is_pickable(i):
				label_text += " (reserved param)"
			else:
				label_text += " (not in scope)"
		opt.add_item(label_text, i)
		# OptionButton item indices line up with `i` because we add
		# them in order with `add_item(text, id=i)`. `set_item_disabled`
		# operates on the position index (== i here).
		opt.set_item_disabled(i, not pickable_here)
	opt.selected = palette_index
	opt.item_selected.connect(func(idx: int) -> void:
		# OptionButton's `item_selected` won't fire for a disabled item,
		# but defensively re-check rather than trust the framework.
		if not IdentifierPalette.is_pickable_in_scope(idx, in_scope):
			opt.selected = palette_index
			return
		palette_index = idx
		_refresh_colors()
		_refresh_content()
	)
	box.add_child(opt)
	return box


func to_source(_canvas) -> String:
	return IdentifierPalette.name_of(palette_index)
