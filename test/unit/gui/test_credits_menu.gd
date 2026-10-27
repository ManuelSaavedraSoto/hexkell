extends GutTest
## Credits screen: reachable from the main menu, and it must display the
## license-REQUIRED music attribution ("Music by jhaeka") — that credit has to
## stay visible to end users.

const CREDITS_SCENE := preload("res://scenes/gui/credits_menu/credits_menu.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/gui/main_menu/main_menu.tscn")


func test_scene_manager_has_credits_route() -> void:
	assert_true(SceneManager.SCENES.has("credits"),
			"SceneManager should route to the credits scene")
	assert_true(SceneManager.has_method("go_to_credits"))


func test_main_menu_has_a_credits_button() -> void:
	var menu := MAIN_MENU_SCENE.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame
	assert_not_null(menu.get_node_or_null("%Credits"),
			"the main menu should expose a Credits button")


func test_credits_shows_required_music_attribution() -> void:
	var credits := CREDITS_SCENE.instantiate()
	add_child_autofree(credits)
	await get_tree().process_frame
	var label: RichTextLabel = credits.get_node("%CreditsLabel")
	assert_string_contains(label.text, "Music by jhaeka",
			"the license-required music attribution must be shown")
	assert_string_contains(label.text, "joshuuu.itch.io",
			"the required attribution link must be present")
	assert_string_contains(label.text, "Manuel Saavedra",
			"the author credit should be shown")
