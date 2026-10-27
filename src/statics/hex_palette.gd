class_name HexPalette
extends RefCounted
## Semantic accessors over the project's `HexLogicPalette` ColorPalette
## resource. The .tres is the authoritative source — edit it in
## Godot's palette editor to retune; this script only translates
## (family, shade) into the right ColorArray index.
##
## Resource layout (42 entries):
##   0      BLACK
##   1      WHITE
##   2-6    RED      family   (5 shades, dark-to-light)
##   7-11   GREEN    family
##   12-16  BLUE     family
##   17-21  CYAN     family
##   22-26  MAGENTA  family
##   27-31  YELLOW   family
##   32-36  COLD NEUTRAL family
##   37-41  WARM NEUTRAL family
##
## Within each 5-shade family the order is:
##   +0 DEEP_SHADOW  (darkest)
##   +1 SHADOW
##   +2 MIDTONE
##   +3 HIGHLIGHT
##   +4 EXTREME_HIGHLIGHT  (lightest)

const RESOURCE := preload("res://assets/resources/colour_palette.tres")

enum Shade {
	DEEP_SHADOW = 0,
	SHADOW = 1,
	MIDTONE = 2,
	HIGHLIGHT = 3,
	EXTREME_HIGHLIGHT = 4,
}

enum Family {
	RED = 0,
	GREEN = 1,
	BLUE = 2,
	CYAN = 3,
	MAGENTA = 4,
	YELLOW = 5,
	COLD_NEUTRAL = 6,
	WARM_NEUTRAL = 7,
}

const _FAMILY_BASE := {
	Family.RED: 2,
	Family.GREEN: 7,
	Family.BLUE: 12,
	Family.CYAN: 17,
	Family.MAGENTA: 22,
	Family.YELLOW: 27,
	Family.COLD_NEUTRAL: 32,
	Family.WARM_NEUTRAL: 37,
}

const BLACK_INDEX := 0
const WHITE_INDEX := 1


static func color(family: int, shade: int) -> Color:
	return RESOURCE.colors[int(_FAMILY_BASE[family]) + shade]


static func black() -> Color:
	return RESOURCE.colors[BLACK_INDEX]


static func white() -> Color:
	return RESOURCE.colors[WHITE_INDEX]


# Six hue midtones + white + black, in the same slot order as the
# legacy IdentifierPalette.ENTRIES so saved jobs that reference
# palette_index 0..7 keep their semantic identity. Only the
# rendered colors change.
static func identifier_color(idx: int) -> Color:
	match idx:
		0: return color(Family.RED, Shade.MIDTONE)
		1: return color(Family.GREEN, Shade.MIDTONE)
		2: return color(Family.BLUE, Shade.MIDTONE)
		3: return color(Family.CYAN, Shade.MIDTONE)
		4: return color(Family.MAGENTA, Shade.MIDTONE)
		5: return color(Family.YELLOW, Shade.MIDTONE)
		6: return white()
		7: return black()
		_: return color(Family.COLD_NEUTRAL, Shade.MIDTONE)


# Per-script body color: every hex of a family shares the same body
# (deep shadow). Siblings are distinguished by their content (labels
# and glyphs), not by body tone — the canvas reads as "all yellows =
# numbers, all greens = booleans" at a glance.
static func body_color_for(script: Script) -> Color:
	return color(family_for(script), Shade.DEEP_SHADOW)


# Per-script edge color: the family's SHADOW shade, applied to
# inactive rim segments via `HexNode.disabled_edge_color`. Active
# input/output edges keep their semantic blue/orange.
static func edge_color_for(script: Script) -> Color:
	return color(family_for(script), Shade.SHADOW)


# Family for a hex script. Falls back to COLD_NEUTRAL for anything
# missing from the table so a brand-new script still renders rather
# than crashing on a missing entry.
static func family_for(script: Script) -> int:
	if script == null:
		return Family.COLD_NEUTRAL
	var path: String = script.resource_path
	if SCRIPT_FAMILY.has(path):
		return SCRIPT_FAMILY[path]
	return Family.COLD_NEUTRAL


# Category → hue family. Used by `category_color()` for the
# palette-bar's per-row tint.
const CATEGORY_FAMILY := {
	"Integer": Family.RED,
	"Boolean": Family.GREEN,
	"Functions": Family.BLUE,
	"Structures": Family.CYAN,
	"Naming": Family.MAGENTA,
}


static func category_color(category: String, shade: int = Shade.MIDTONE) -> Color:
	if not CATEGORY_FAMILY.has(category):
		return color(Family.COLD_NEUTRAL, shade)
	return color(CATEGORY_FAMILY[category], shade)


# Same hue, half saturation — calmer palette-bar tint for inactive
# category buttons so the bar doesn't grab all the attention while
# still color-keying each row.
static func desaturated(c: Color, factor: float = 0.5) -> Color:
	return Color.from_hsv(c.h, c.s * factor, c.v, c.a)


# script_path → Family. Every entry maps a hex script to its hue
# family; the actual body/edge shades come from `body_color_for` and
# `edge_color_for` (uniform deep_shadow + shadow per family).
const SCRIPT_FAMILY := {
	# Integer
	"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/sub_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/mul_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/div_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/mod_hex.gd": Family.RED,
	"res://src/classes/hex_nodes/operators/arithmetic/neg_hex.gd": Family.RED,

	# Boolean
	"res://src/classes/hex_nodes/literals/booleans/true_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/literals/booleans/false_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/and_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/or_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/not_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/eq_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/neq_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/lt_hex.gd": Family.GREEN,
	"res://src/classes/hex_nodes/operators/logical/gte_hex.gd": Family.GREEN,

	# Functions
	"res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd": Family.BLUE,
	"res://src/classes/hex_nodes/control/if_hex.gd": Family.BLUE,
	"res://src/classes/hex_nodes/control/match_hex.gd": Family.BLUE,
	"res://src/classes/hex_nodes/operators/functional/apply_hex.gd": Family.BLUE,
	"res://src/classes/hex_nodes/operators/functional/compose_hex.gd": Family.BLUE,

	# Structures
	"res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd": Family.CYAN,
	"res://src/classes/hex_nodes/literals/list/list_literal_hex.gd": Family.CYAN,
	"res://src/classes/hex_nodes/operators/list/range_hex.gd": Family.CYAN,
	"res://src/classes/hex_nodes/operators/list/cons_hex.gd": Family.CYAN,
	"res://src/classes/hex_nodes/operators/list/concat_hex.gd": Family.CYAN,

	# Naming. ident_ref_hex overrides body_color from its bound
	# identifier; the family entry still drives edge color so the
	# rim color-keys with the rest of the Naming row.
	"res://src/classes/hex_nodes/control/let_hex.gd": Family.MAGENTA,
	"res://src/classes/hex_nodes/control/let_rec_hex.gd": Family.MAGENTA,
	"res://src/classes/hex_nodes/control/definition_hex.gd": Family.MAGENTA,
	"res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd": Family.MAGENTA,

	# Fixtures
	"res://src/classes/hex_nodes/fixtures/do_hex.gd": Family.COLD_NEUTRAL,
	"res://src/classes/hex_nodes/fixtures/anchor_hex.gd": Family.COLD_NEUTRAL,
	"res://src/classes/hex_nodes/fixtures/match_anchor.gd": Family.COLD_NEUTRAL,
}
