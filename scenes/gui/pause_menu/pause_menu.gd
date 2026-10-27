extends Control
## Pause menu script

# Emitted when a preference changes via the Settings modal — the
# editor listens so the palette / jobs panel can re-refresh while
# the pause overlay is still up.
signal preferences_changed

# Codex / keybindings entries route through the editor (which owns
# the dialog scenes) — the pause menu just signals intent.
signal codex_requested
signal keybindings_requested

const SETTINGS_SCENE := preload("res://scenes/gui/settings_menu/settings_menu.tscn")

@onready var resume: Button = %Resume
@onready var codex: Button = %Codex
@onready var help: Button = %Keybinds
@onready var settings_button: Button = %Settings
@onready var main_menu: Button = %MainMenu
@onready var exit: Button = %Exit


func _ready() -> void:
	resume.pressed.connect(self._on_resume_button_pressed)
	main_menu.pressed.connect(self._main_menu)
	exit.pressed.connect(get_tree().quit)
	settings_button.pressed.connect(_open_settings)
	codex.pressed.connect(_on_codex_pressed)
	help.pressed.connect(_on_keybindings_pressed)
	# Duck the music while the pause menu is up; restore it on every hide
	# (resume, Escape, or the codex / keybindings shortcuts which resume first).
	visibility_changed.connect(func() -> void: BgmManager.set_paused(visible))


# The editor owns the codex / keybindings dialog instances; the
# pause menu unpaused the tree so the dialog renders cleanly without
# the game time-freeze, then forwards the request upstream.
func _on_codex_pressed() -> void:
	_on_resume_button_pressed()
	codex_requested.emit()


func _on_keybindings_pressed() -> void:
	_on_resume_button_pressed()
	keybindings_requested.emit()


# Showing/hiding is all it takes: the editor tracks this modal via
# _track_modal, whose visibility hook pauses/unpauses the tree
# through ModalStack (this menu runs at PROCESS_MODE_WHEN_PAUSED).
func pause() -> void:
	show()


func _on_resume_button_pressed() -> void:
	hide()


func _open_settings() -> void:
	var modal: Control = SETTINGS_SCENE.instantiate()
	add_child(modal)
	modal.set_modal(true)
	modal.close_requested.connect(modal.queue_free)
	modal.archmage_changed.connect(_on_modal_archmage_changed)


func _on_modal_archmage_changed(_enabled: bool) -> void:
	preferences_changed.emit()
	

func _main_menu() ->void:
	# Swapping scenes while paused would freeze the next scene; drop
	# the whole modal stack, not just this menu's own visibility.
	ModalStack.reset(get_tree())
	# This path doesn't hide the menu, so restore the volume explicitly so the
	# main menu doesn't inherit the ducked level.
	BgmManager.set_paused(false)
	SceneManager.go_to_main_menu()
