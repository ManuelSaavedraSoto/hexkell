extends HexNode
## Root of the visual program. Conceptually a single input — the
## program's main expression — that the user can wire from any of the
## six surrounding cells. The other slots aren't separate inputs;
## they're additional approach points to the same logical input.
##
## `to_source` returns the source of whichever slot is wired (first
## non-null in canonical order). `validate` requires at least one
## slot to carry an expression.
##
## Doubles as a display hex: when `display_value` is non-empty, a
## label over the body shows the static result of the wired input.
## Authors set it via the config sidebar before exporting a blueprint;
## the value round-trips through `serialize_state` so chapter intro
## previews (and any future blueprint preview surface) see it.

@export var display_value: String = "":
	set(value):
		display_value = value
		_refresh_display()

var _keyword_label: Label
var _display_label: Label


func _init() -> void:
	# All six sides offer an approach to the same logical "main"
	# input. Each is individually optional, but the hex is invalid
	# when none of them is wired (see `validate` override).
	input_edges = [0, 1, 2, 3, 4, 5]
	input_role_names = {
		0: "main expression",
		1: "main expression",
		2: "main expression",
		3: "main expression",
		4: "main expression",
		5: "main expression",
	}
	optional_input_edges = [0, 1, 2, 3, 4, 5]
	exclusive_input_group = true  # one wire total across all six sides
	is_fixture = true  # level-0 fixture: rotatable but not picked up / deleted


func _setup_content() -> void:
	_keyword_label = Label.new()
	_keyword_label.text = "do"
	_keyword_label.add_theme_font_size_override("font_size", 26)
	_keyword_label.add_theme_color_override("font_color", Color.WHITE)
	_keyword_label.size = Vector2(60, 36)
	_keyword_label.position = Vector2(-30, -18)
	_keyword_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keyword_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_keyword_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_keyword_label)

	_display_label = Label.new()
	_display_label.add_theme_font_size_override("font_size", 28)
	_display_label.add_theme_color_override("font_color", Color.WHITE)
	_display_label.size = Vector2(80, 40)
	_display_label.position = Vector2(-40, -22)
	_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_display_label)
	_refresh_display()


# Public setter (mirrors the @export setter) for the eventual
# editor-driven auto-compute pass.
func set_display_value(value: String) -> void:
	display_value = value


# Hides the keyword label and shows the computed value (and vice
# versa) so the DoHex body reads either as "do" (unwired / dynamic
# program) or as the static result.
func _refresh_display() -> void:
	if _display_label == null:
		return
	var has_value := not display_value.is_empty()
	_display_label.text = display_value
	_display_label.visible = has_value
	if _keyword_label != null:
		_keyword_label.visible = not has_value


func serialize_state(_canvas) -> Dictionary:
	return {"display_value": display_value}


func restore_state(state: Dictionary, _canvas) -> void:
	set_display_value(String(state.get("display_value", "")))


func _copy_state_to(other: HexNode) -> void:
	other.set_display_value(display_value)


func get_config_title() -> String:
	return "Do (main)"


# Archmage-only debug surface: lets chapter-example authors bake a
# preview value into the DoHex body before exporting the blueprint.
# Hidden from normal players — the field has no in-game effect and
# would just confuse anyone who hasn't pivoted into authoring mode.
func build_config_ui() -> Control:
	if not SaveManager.is_archmage():
		return null
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Display value (archmage)"
	box.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = display_value
	edit.placeholder_text = "Optional preview value"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(v: String) -> void:
		set_display_value(v))
	box.add_child(edit)
	return box


func to_source(canvas) -> String:
	for edge in input_edges:
		if canvas.get_input_for(self, edge) != null:
			return _input_source(canvas, edge)
	return "_HOLE_"


# Exactly one of the six approach slots must carry the main expression.
func validate(canvas) -> Dictionary:
	var fed := wired_input_edges(canvas)
	if fed.is_empty():
		return {
			"status": "error",
			"message": "no main expression wired to the Do hex",
		}
	if fed.size() > 1:
		return {
			"status": "error",
			"message": "the Do hex is fed from %s and %s — it takes one main expression" % [
				HexMath.edge_name(physical_edge(int(fed[0]))),
				HexMath.edge_name(physical_edge(int(fed[1]))),
			],
		}
	return {"status": "ok", "message": ""}
