class_name ModalStack
## Tree-pause-based modal gate.
##
## A modal opening pauses the SceneTree; PAUSABLE nodes (the editor,
## the camera, every decentralized input handler) then stop receiving
## _process / _unhandled_input entirely, so no per-component gate
## checks are needed. Dialogs run at PROCESS_MODE_WHEN_PAUSED.
##
## The depth counter handles stacked modals (chapter intro under the
## pause menu, settings over the pause menu): the tree unpauses only
## when the last modal closes.

static var _depth: int = 0


static func acquire(tree: SceneTree) -> void:
	_depth += 1
	tree.paused = true


static func release(tree: SceneTree) -> void:
	_depth = max(0, _depth - 1)
	tree.paused = _depth > 0


static func is_open() -> bool:
	return _depth > 0


## Test / scene-change hygiene: drop all modal state and unpause.
## Called before scene swaps (a paused tree would freeze the next
## scene) and from GUT after_each hooks.
static func reset(tree: SceneTree) -> void:
	_depth = 0
	tree.paused = false
