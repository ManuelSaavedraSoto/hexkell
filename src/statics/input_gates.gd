class_name InputGates
## Shared input-gate predicates for the decentralized input handlers.
##
## Modal gating needs no predicate here — an open modal pauses the
## tree (ModalStack) and PAUSABLE handlers stop receiving input
## callbacks entirely. The one gate that remains is text focus:
## typing into a LineEdit must not trigger canvas hotkeys.


static func text_input_focused(viewport: Viewport) -> bool:
	var f := viewport.gui_get_focus_owner()
	if f == null:
		return false
	if f is LineEdit or f is TextEdit:
		return true
	# SpinBox's editable region is an internal LineEdit; check its parent.
	var p := f.get_parent()
	return p != null and p is SpinBox
