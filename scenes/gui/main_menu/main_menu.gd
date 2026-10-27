extends Control
## Main menu script
##
## Reusable for any control node that loads a control menu scene

@onready var story : Button = %StoryMode
@onready var playground : Button = %Playground
@onready var settings : Button = %Settings
@onready var credits : Button = %Credits
@onready var exit : Button = %Exit


func _ready() -> void:
	# Phase 19.10 — Story Mode is now the hex editor. The legacy text
	# editor ("Editor" button → editor) stays reachable as the
	# "Classic" path.
	story.pressed.connect(SceneManager.go_to_hex_editor)
	playground.pressed.connect(SceneManager.go_to_editor)
	settings.pressed.connect(SceneManager.go_to_settings)
	credits.pressed.connect(SceneManager.go_to_credits)
	exit.pressed.connect(get_tree().quit)
