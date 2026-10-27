extends GutTest
## HexPalette guards: the resource has the expected shape, family
## midtones land where we think they do, and key per-hex overrides
## resolve. Keeps the palette resource + the SCRIPT_COLORS table in
## lockstep against accidental drift.

const HexPalette := preload("res://src/statics/hex_palette.gd")
const IdentifierPalette := preload("res://scenes/gui/hex_editor/identifier_palette.gd")
const HexNodeBase := preload("res://src/classes/hex_nodes/hex_node.gd")
const IntLiteralHex := preload("res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd")
const TrueHex := preload("res://src/classes/hex_nodes/literals/booleans/true_hex.gd")
const FalseHex := preload("res://src/classes/hex_nodes/literals/booleans/false_hex.gd")
const DoHex := preload("res://src/classes/hex_nodes/fixtures/do_hex.gd")


func test_resource_has_forty_two_colors() -> void:
	# Black + white + 6 hue families * 5 shades + 2 neutrals * 5 shades.
	# A trim would silently break the family-index math; this guards it.
	assert_eq(HexPalette.RESOURCE.colors.size(), 42,
			"HexLogicPalette resource should expose exactly 42 colors")


func test_red_midtone_resolves_to_vivid_red() -> void:
	var red_mid: Color = HexPalette.color(
			HexPalette.Family.RED, HexPalette.Shade.MIDTONE)
	assert_almost_eq(red_mid.r, 0.86, 0.02)
	assert_almost_eq(red_mid.g, 0.03, 0.02)
	assert_almost_eq(red_mid.b, 0.14, 0.02)


func test_yellow_midtone_resolves_to_golden_yellow() -> void:
	# Yellow family is the last hue family before the neutrals; an
	# off-by-one in `_FAMILY_BASE` would land us on a magenta tone.
	# (Values track the retuned palette from the visual overhaul.)
	var yellow_mid: Color = HexPalette.color(
			HexPalette.Family.YELLOW, HexPalette.Shade.MIDTONE)
	assert_almost_eq(yellow_mid.r, 1.0, 0.02)
	assert_almost_eq(yellow_mid.g, 0.87, 0.02)
	assert_almost_eq(yellow_mid.b, 0.23, 0.02)


func test_shade_ordering_runs_dark_to_light() -> void:
	# Deep shadow should be the darkest entry of a family; extreme
	# highlight the lightest. Any swap would silently invert the
	# visual semantics of every per-hex override.
	var deep: Color = HexPalette.color(
			HexPalette.Family.GREEN, HexPalette.Shade.DEEP_SHADOW)
	var extreme: Color = HexPalette.color(
			HexPalette.Family.GREEN, HexPalette.Shade.EXTREME_HIGHLIGHT)
	assert_lt(deep.get_luminance(), extreme.get_luminance(),
			"DEEP_SHADOW should be darker than EXTREME_HIGHLIGHT")


func test_black_and_white_indices() -> void:
	assert_eq(HexPalette.black(), Color(0, 0, 0, 1))
	assert_eq(HexPalette.white(), Color(1, 1, 1, 1))


func test_identifier_palette_aligns_to_hex_palette() -> void:
	# Indices 0-5 are the six hue midtones in RGB-CMY order; 6 is
	# white; 7 is black. Saved jobs reference palette_index 0..7 so
	# a misalignment here would silently recolor every IdentRefHex.
	for i in 8:
		assert_eq(IdentifierPalette.ENTRIES[i].color,
				HexPalette.identifier_color(i),
				"IdentifierPalette[%d].color should equal HexPalette.identifier_color(%d)" % [i, i])


func test_body_color_is_family_deep_shadow() -> void:
	# Every hex of a family shares the same body (deep shadow) so the
	# canvas reads as "all reds = numbers" at a glance. Siblings
	# are distinguished by their content, not their body tone.
	var c: Color = HexPalette.body_color_for(IntLiteralHex)
	var expected: Color = HexPalette.color(
			HexPalette.Family.RED, HexPalette.Shade.DEEP_SHADOW)
	assert_eq(c, expected,
			"IntLiteralHex body should be RED DEEP_SHADOW")


func test_edge_color_is_family_shadow() -> void:
	# The rim sits one shade lighter than the center, giving the hex
	# a depth-from-vignette read against the canvas background.
	var c: Color = HexPalette.edge_color_for(TrueHex)
	var expected: Color = HexPalette.color(
			HexPalette.Family.GREEN, HexPalette.Shade.SHADOW)
	assert_eq(c, expected,
			"TrueHex edges should be GREEN SHADOW")


func test_true_and_false_share_body_color() -> void:
	# Sibling distinction is content-driven (True text vs False text),
	# not body color. Both should resolve to identical family tones.
	assert_eq(HexPalette.body_color_for(TrueHex),
			HexPalette.body_color_for(FalseHex),
			"Siblings in the same family share body color")


func test_unknown_script_falls_back_to_cold_neutral() -> void:
	# Anything not in SCRIPT_FAMILY renders as cold-neutral so a new
	# script still draws rather than crashing on a missing entry.
	assert_eq(HexPalette.family_for(HexNodeBase),
			HexPalette.Family.COLD_NEUTRAL)


func test_do_hex_picks_up_cold_neutral_family() -> void:
	# DoHex is the always-on fixture; cold-neutral family reads as
	# "background" against the colorful hue families.
	assert_eq(HexPalette.family_for(DoHex),
			HexPalette.Family.COLD_NEUTRAL)


func test_desaturated_preserves_hue() -> void:
	# Inactive category buttons use a half-saturated midtone — the
	# hue stays for color-keying, only the saturation drops so the
	# bar doesn't grab attention.
	var mid: Color = HexPalette.category_color("Integer")
	var dim: Color = HexPalette.desaturated(mid, 0.5)
	assert_almost_eq(dim.h, mid.h, 0.01,
			"Desaturation should preserve hue")
	assert_almost_eq(dim.s, mid.s * 0.5, 0.01,
			"Desaturation should halve saturation at factor 0.5")


func test_hex_instance_has_palette_body_and_edge_colors() -> void:
	# End-to-end: instantiate via the same scene-based factory the
	# editor uses for placement, add to tree so _ready fires, and
	# confirm the @export fields reflect HexPalette — not a stale
	# .tscn-baked override. Regression for the disabled_edge_color
	# clobber that hex_node.tscn used to apply post-_init.
	var hex: HexNode = HexNodeBase.from_script(IntLiteralHex)
	add_child_autofree(hex)
	await get_tree().process_frame
	assert_eq(hex.body_color, HexPalette.color(
			HexPalette.Family.RED, HexPalette.Shade.DEEP_SHADOW),
			"Body should land on RED DEEP_SHADOW")
	assert_eq(hex.disabled_edge_color, HexPalette.color(
			HexPalette.Family.RED, HexPalette.Shade.SHADOW),
			"Rim should land on RED SHADOW")


func test_input_output_colors_use_neutral_highlights() -> void:
	# Slot pips ride the cool/warm neutral families so they don't
	# read as members of any colorful hue family — cool grey input
	# pip alongside a BLUE-family Naming body, etc.
	var hex: HexNode = HexNodeBase.from_script(IntLiteralHex)
	add_child_autofree(hex)
	await get_tree().process_frame
	assert_eq(hex.input_color, HexPalette.color(
			HexPalette.Family.COLD_NEUTRAL,
			HexPalette.Shade.HIGHLIGHT),
			"Input pip should be COLD_NEUTRAL HIGHLIGHT")
	assert_eq(hex.output_color, HexPalette.color(
			HexPalette.Family.WARM_NEUTRAL,
			HexPalette.Shade.HIGHLIGHT),
			"Output pip should be WARM_NEUTRAL HIGHLIGHT")
