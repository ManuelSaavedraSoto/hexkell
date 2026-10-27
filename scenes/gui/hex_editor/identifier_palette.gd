class_name IdentifierPalette
extends RefCounted
## Fixed palette of identifiers the player can pick from.
## Each entry is `{color, name, glyph}`. The `name` is what gets emitted
## into the textual program; the `color` and `glyph` are how the player sees it.

## RGB-CMY signals are the six user-facing identifier colors. White and
## black are reserved as program parameters: the checker injects values
## into them when testing the user's program (when the hex editor is
## wired into the larger game flow). They remain in `ENTRIES` so the
## indices are stable and the runtime can refer to them by name, but
## the sidebar pickers iterate `user_count()` and therefore skip them.
##
## Colors source from `HexPalette` so the identifier list and the hex
## body palette stay in lockstep — editing the `.tres` retunes both.
## ENTRIES is a `static var` (not `const`) because `HexPalette.color()`
## isn't a constant expression.
static var ENTRIES: Array = [
	{"color": HexPalette.identifier_color(0), "name": "red",     "glyph": "●", "emoji": "🟥"},
	{"color": HexPalette.identifier_color(1), "name": "green",   "glyph": "◆", "emoji": "🟩"},
	{"color": HexPalette.identifier_color(2), "name": "blue",    "glyph": "★", "emoji": "🟦"},
	# No Unicode square exists for cyan; 💠 is the next-best canonical
	# cyan-tinted emoji.
	{"color": HexPalette.identifier_color(3), "name": "cyan",    "glyph": "◉", "emoji": "💠"},
	{"color": HexPalette.identifier_color(4), "name": "magenta", "glyph": "♥", "emoji": "🟪"},
	{"color": HexPalette.identifier_color(5), "name": "yellow",  "glyph": "▲", "emoji": "🟨"},
	{"color": HexPalette.identifier_color(6), "name": "white",   "glyph": "□", "emoji": "⬜"},
	{"color": HexPalette.identifier_color(7), "name": "black",   "glyph": "■", "emoji": "⬛"},
]

# Number of reserved entries at the end of `ENTRIES` that the user
# can't pick from sidebar dropdowns — currently `white` and `black`.
const RESERVED_COUNT := 2

# Names of reserved identifiers that the current gameplay context (a
# selected job whose `variables` injects them) has made pickable. The
# sidebar picker still lists every entry so the rest of the UI looks
# stable, but reserved entries that aren't in this set render disabled.
# Empty means the user is in free-run mode and `white` / `black` would
# resolve to undefined identifiers — `IdentRefHex` greys them out then.
static var _exposed_reserved: Array = []


static func count() -> int:
	return ENTRIES.size()


# Count of user-pickable identifiers — `count()` minus the
# reserved-parameter slots at the end.
static func user_count() -> int:
	return ENTRIES.size() - RESERVED_COUNT


# Editor calls this when the active job selection changes. `names` is
# the subset of reserved identifier names (`white` / `black`) that the
# job exposes. Pass `[]` to lock both back down.
static func set_exposed_reserved(names: Array) -> void:
	var clean: Array = []
	for n in names:
		var s := String(n)
		# Only reserved identifiers can be toggled; if the caller hands
		# us a non-reserved name it's a no-op (those are always pickable).
		if _name_is_reserved(s):
			if s not in clean:
				clean.append(s)
	_exposed_reserved = clean


static func get_exposed_reserved() -> Array:
	return _exposed_reserved.duplicate()


# True when the identifier at `idx` should be selectable in pickers.
# Always true for the user_count() leading entries; for reserved
# entries it's gated by `set_exposed_reserved`.
static func is_pickable(idx: int) -> bool:
	if idx < user_count():
		return true
	if idx >= ENTRIES.size():
		return false
	return ENTRIES[idx].name in _exposed_reserved


# Scope-aware variant. `in_scope` is the list of identifier names
# bound at the picker's hex (computed by IdentifierScope). Returns
# true only when both the global pickability gate and the lexical
# scope gate allow it.
static func is_pickable_in_scope(idx: int, in_scope: Array) -> bool:
	if not is_pickable(idx):
		return false
	if idx >= ENTRIES.size():
		return false
	return ENTRIES[idx].name in in_scope


static func _name_is_reserved(name: String) -> bool:
	for i in range(user_count(), ENTRIES.size()):
		if ENTRIES[i].name == name:
			return true
	return false


static func entry(i: int) -> Dictionary:
	return ENTRIES[posmod(i, ENTRIES.size())]


static func color_of(i: int) -> Color:
	return entry(i).color


static func name_of(i: int) -> String:
	return entry(i).name


static func glyph_of(i: int) -> String:
	return entry(i).glyph


static func emoji_of(i: int) -> String:
	return entry(i).emoji
