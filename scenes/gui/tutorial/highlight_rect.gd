class_name TutorialHighlightRect
extends Control
## Pulsing border parked over an arbitrary Control. The tutorial HUD
## owns one of these; each step re-targets it via `highlight()` with a
## Callable so rebuilt targets (job cards, palette rows) re-resolve
## every frame instead of going stale.

const PADDING := 6.0
const BORDER_WIDTH := 3.0
const BASE_COLOR := Color(1.0, 0.85, 0.35)

# Returns the Control to track, or null to hide. A Callable (not a
# direct ref) so targets that get freed/rebuilt never dangle.
var _target_getter: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func highlight(getter: Callable) -> void:
	_target_getter = getter


func clear() -> void:
	_target_getter = Callable()
	visible = false


func _process(_delta: float) -> void:
	if not _target_getter.is_valid():
		visible = false
		return
	var target = _target_getter.call()
	if target == null or not (target is Control) or not target.is_visible_in_tree():
		visible = false
		return
	var rect: Rect2 = (target as Control).get_global_rect().grow(PADDING)
	global_position = rect.position
	size = rect.size
	visible = true
	queue_redraw()


func _draw() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 240.0)
	var color := BASE_COLOR
	color.a = pulse
	draw_rect(Rect2(Vector2.ZERO, size), color, false, BORDER_WIDTH)
