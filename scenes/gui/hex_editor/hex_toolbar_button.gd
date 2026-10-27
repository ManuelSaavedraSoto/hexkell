extends Button
class_name HexToolbarButton
## Toolbar button used by the hex editor's bottom palette. Lays out the
## main label in the center (where future icons will live) and a small
## slot-number badge in the bottom-right corner. Hovering shows a
## custom title-plus-body tooltip panel — set via `tooltip_title` and
## `tooltip_body`. Set `tooltip_text` (anything non-empty) to opt into
## tooltip display; `_make_custom_tooltip` ignores its argument and
## builds from the fields below.
##
## Live tuning lives in `assets/resources/hud_theme.tres` — change the
## `HexToolbarButton/constants/badge_*` / `colors/badge_font_color` /
## `font_sizes/badge_font_size` entries there and every toolbar button
## picks it up. The constants below are only fallbacks for cases where
## the theme isn't propagating (button instantiated outside the hex
## editor scene).

const BADGE_FONT_SIZE_DEFAULT := 11
const BADGE_COLOR_DEFAULT := Color(0.187, 0.131, 0.088, 1.0)
const BADGE_MARGIN_RIGHT_DEFAULT := 10
const BADGE_MARGIN_BOTTOM_DEFAULT := 6
const TOOLTIP_BG := Color(0.10, 0.12, 0.16, 0.97)
const TOOLTIP_BORDER := Color(0.40, 0.50, 0.65, 1.0)
const TOOLTIP_MAX_WIDTH := 280

@export var badge_text: String = ""        # "1".."9", "0", "⇧1", or ""
@export var tooltip_title: String = ""
@export var tooltip_body: String = ""
# Optional palette payload — when set, identifies the hex type this
# button represents. PaletteBar uses this to dispatch `hex_selected`
# without keeping a parallel name → script catalog in code.
@export var hex_script: Script = null

var _badge_label: Label
var _badge_margin: MarginContainer


func _ready() -> void:
	if badge_text.is_empty():
		return
	# A MarginContainer is the cleanest "pin to corner with padding"
	# layout — gives the badge a tight bounding box AND keeps the
	# margin values readable / editable from the theme.
	_badge_margin = MarginContainer.new()
	_badge_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badge_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge_margin)

	_badge_label = Label.new()
	_badge_label.text = badge_text
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Align to the bottom-right within the margin container.
	_badge_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_badge_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_badge_margin.add_child(_badge_label)

	_apply_badge_theme()
	# Refresh once the theme is fully resolved so an ancestor-propagated
	# theme wins over the hardcoded fallbacks.
	call_deferred("_apply_badge_theme")


# Read badge font / color / margins from the theme (with fallbacks)
# and push them onto the badge label + its margin container.
func _apply_badge_theme() -> void:
	if _badge_label == null or _badge_margin == null:
		return
	var size_pt := _theme_font_size("badge_font_size", BADGE_FONT_SIZE_DEFAULT)
	var color := _theme_color("badge_font_color", BADGE_COLOR_DEFAULT)
	var margin_right := _theme_constant("badge_margin_right", BADGE_MARGIN_RIGHT_DEFAULT)
	var margin_bottom := _theme_constant("badge_margin_bottom", BADGE_MARGIN_BOTTOM_DEFAULT)
	_badge_label.add_theme_font_size_override("font_size", size_pt)
	_badge_label.add_theme_color_override("font_color", color)
	_badge_margin.add_theme_constant_override("margin_right", margin_right)
	_badge_margin.add_theme_constant_override("margin_bottom", margin_bottom)


func _theme_constant(name: String, fallback: int) -> int:
	if has_theme_constant(name, "HexToolbarButton"):
		return get_theme_constant(name, "HexToolbarButton")
	return fallback


func _theme_color(name: String, fallback: Color) -> Color:
	if has_theme_color(name, "HexToolbarButton"):
		return get_theme_color(name, "HexToolbarButton")
	return fallback


func _theme_font_size(name: String, fallback: int) -> int:
	if has_theme_font_size(name, "HexToolbarButton"):
		return get_theme_font_size(name, "HexToolbarButton")
	return fallback


func set_badge(text: String) -> void:
	badge_text = text
	if _badge_label:
		_badge_label.text = text


# Godot's tooltip system requires `tooltip_text` to be non-empty before
# `_make_custom_tooltip` is called. The argument is ignored — we read
# from `tooltip_title` / `tooltip_body` so the call sites can keep
# tooltip data structured.
func _make_custom_tooltip(_text: String) -> Object:
	if tooltip_title.is_empty() and tooltip_body.is_empty():
		return null
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TOOLTIP_BG
	sb.border_color = TOOLTIP_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	if not tooltip_title.is_empty():
		var title_lbl := Label.new()
		title_lbl.text = tooltip_title
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		title_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(title_lbl)
	if not tooltip_body.is_empty():
		if not tooltip_title.is_empty():
			vbox.add_child(HSeparator.new())
		var body_lbl := Label.new()
		body_lbl.text = tooltip_body
		body_lbl.add_theme_color_override("font_color", Color(0.82, 0.87, 0.95))
		body_lbl.add_theme_font_size_override("font_size", 11)
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_lbl.custom_minimum_size = Vector2(TOOLTIP_MAX_WIDTH, 0)
		vbox.add_child(body_lbl)
	panel.add_child(vbox)
	return panel
