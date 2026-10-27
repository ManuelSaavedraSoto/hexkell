extends Node
## Global scene manager

const SCENES : Dictionary = {
	"main_menu": "res://scenes/gui/main_menu/main_menu.tscn",
	"editor": "res://scenes/gui/editor/editor.tscn",
	"settings": "res://scenes/gui/settings_menu/settings_menu.tscn",
	"hex_editor": "res://scenes/gui/hex_editor/hex_editor.tscn",
	"credits": "res://scenes/gui/credits_menu/credits_menu.tscn",
}

var current_scene : String = "main_menu"


func change_scene(scene_name : String) -> void:
	if not SCENES.has(scene_name):
		push_error("Scene '%s' does not exist in the scene manager." % scene_name)
		return
	
	current_scene = scene_name
	get_tree().change_scene_to_file(SCENES[scene_name])


func go_to_main_menu() -> void:
	change_scene("main_menu")


func go_to_editor() -> void:
	change_scene("editor")


func go_to_settings() -> void:
	change_scene("settings")


func go_to_credits() -> void:
	change_scene("credits")


func go_to_hex_editor() -> void:
	change_scene("hex_editor")
