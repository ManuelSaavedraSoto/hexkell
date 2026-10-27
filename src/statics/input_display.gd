class_name InputDisplay
## InputMap action → icon-BBCode rendering for RichTextLabels.
##
## Mirrors the chapter-0 description convention in static_data.json:
## key/mouse icons as `[img valign=center, width=24]res://assets/
## icons/input/...[/img]`, with a `[code]Key[/code]` text fallback for
## keys that have no icon asset (Z, X, H, Esc, PgUp, ...). Used by the
## keybindings dialog to derive its rows from the live InputMap so the
## reference can't drift from project.godot again.

const _ICON_FMT := "[img valign=center, width=24]%s[/img]"

# Hand-written gesture rows (marquee drags, MMB pan, ...) reuse these
# instead of repeating the asset paths.
const MOUSE_LMB := "[img valign=center, width=24]res://assets/icons/input/mouse/left_mb.tres[/img]"
const MOUSE_RMB := "[img valign=center, width=24]res://assets/icons/input/mouse/right_mb.tres[/img]"
const MOUSE_MMB := "[img valign=center, width=24]res://assets/icons/input/mouse/middle_mb.tres[/img]"
const MOUSE_WHEEL := "[img valign=center, width=24]res://assets/icons/input/mouse/scroll_wheel.tres[/img]"
const MOUSE_ALL_DIRECTIONS := "[img valign=center, width=32]res://assets/icons/input/mouse/all_directions.tres[/img]"

# Keys that ship an icon asset. Everything else renders as
# [code]Label[/code] via OS.get_keycode_string.
const _KEY_ICONS := {
	KEY_A: "res://assets/icons/input/keyboard/letters/a.tres",
	KEY_B: "res://assets/icons/input/keyboard/letters/b.tres",
	KEY_D: "res://assets/icons/input/keyboard/letters/d.tres",
	KEY_E: "res://assets/icons/input/keyboard/letters/e.tres",
	KEY_F: "res://assets/icons/input/keyboard/letters/f.tres",
	KEY_G: "res://assets/icons/input/keyboard/letters/g.tres",
	KEY_Q: "res://assets/icons/input/keyboard/letters/q.tres",
	KEY_R: "res://assets/icons/input/keyboard/letters/r.tres",
	KEY_S: "res://assets/icons/input/keyboard/letters/s.tres",
	KEY_T: "res://assets/icons/input/keyboard/letters/t.tres",
	KEY_W: "res://assets/icons/input/keyboard/letters/w.tres",
	KEY_0: "res://assets/icons/input/keyboard/numbers/0.tres",
	KEY_1: "res://assets/icons/input/keyboard/numbers/1.tres",
	KEY_2: "res://assets/icons/input/keyboard/numbers/2.tres",
	KEY_3: "res://assets/icons/input/keyboard/numbers/3.tres",
	KEY_4: "res://assets/icons/input/keyboard/numbers/4.tres",
	KEY_5: "res://assets/icons/input/keyboard/numbers/5.tres",
	KEY_6: "res://assets/icons/input/keyboard/numbers/6.tres",
	KEY_7: "res://assets/icons/input/keyboard/numbers/7.tres",
	KEY_8: "res://assets/icons/input/keyboard/numbers/8.tres",
	KEY_9: "res://assets/icons/input/keyboard/numbers/9.tres",
	KEY_SPACE: "res://assets/icons/input/keyboard/special/space.tres",
	KEY_TAB: "res://assets/icons/input/keyboard/special/tab.tres",
}

const _MOUSE_ICONS := {
	MOUSE_BUTTON_LEFT: "res://assets/icons/input/mouse/left_mb.tres",
	MOUSE_BUTTON_RIGHT: "res://assets/icons/input/mouse/right_mb.tres",
	MOUSE_BUTTON_MIDDLE: "res://assets/icons/input/mouse/middle_mb.tres",
	MOUSE_BUTTON_WHEEL_UP: "res://assets/icons/input/mouse/scroll_wheel.tres",
	MOUSE_BUTTON_WHEEL_DOWN: "res://assets/icons/input/mouse/scroll_wheel.tres",
}


## All of an action's bound events as icon BBCode, alternatives joined
## with a slash separator. Empty string for unknown / unbound actions.
static func action_bbcode(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action):
		var s := event_bbcode(event)
		# Wheel-up + wheel-down both render the same scroll icon — keep
		# one (canvas_zoom_in/out style bindings).
		if not s.is_empty() and not parts.has(s):
			parts.append(s)
	return "  /  ".join(parts)


static func event_bbcode(event: InputEvent) -> String:
	if event is InputEventKey:
		return _key_bbcode(event)
	if event is InputEventMouseButton:
		return _MOUSE_ICONS.get(
				(event as InputEventMouseButton).button_index, "")
	return ""


static func _key_bbcode(e: InputEventKey) -> String:
	var out := ""
	if e.ctrl_pressed:
		out += _ICON_FMT % "res://assets/icons/input/keyboard/special/control.tres"
	if e.shift_pressed:
		out += _ICON_FMT % "res://assets/icons/input/keyboard/special/shift.tres"
	if e.alt_pressed:
		out += "[code]Alt[/code]+"
	# project.godot binds physical keycodes (keycode stays 0); accept
	# either so hand-built events in tests/data also render.
	var key: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	if _KEY_ICONS.has(key):
		return out + _ICON_FMT % _KEY_ICONS[key]
	return out + "[code]%s[/code]" % OS.get_keycode_string(key)
