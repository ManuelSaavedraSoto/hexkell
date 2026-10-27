extends Node
## Manages loading and merging of templates from multiple sources

const DEFAULT_TEMPLATES_PATH := "res://data/static_data.json"
# Legacy Playground content (code-snippet templates + text-coding exercises)
# lives in its own file — static_data.json is reserved for the modern hex flow
# (chapters / jobs / examples). See docs/STATIC_DATA_FORMAT.md.
const LEGACY_PLAYGROUND_PATH := "res://data/legacy_playground.json"
const USER_TEMPLATES_DIR := "user://templates/"
const USER_SAVED_TEMPLATES_FILE := "user://custom_templates.json"
const UPLOADED_TEMPLATES_DIR := "user://uploaded_templates/"
const UPLOADED_EXERCISES_DIR := "user://uploaded_exercises/"

var templates: Dictionary = {}
var exercises: Dictionary = {}
var examples: Dictionary = {}
var chapters: Dictionary = {}
# Phase 19: jobs are the hex-editor's analogue of exercises. Same JSON
# shape (tests / variables / required_structures / etc.), plus an
# `unlocks_hexes` array of script paths to hand to SaveManager on solve.
var jobs: Dictionary = {}

# Settings for custom content
var use_custom_templates: bool = false
var use_custom_exercises: bool = false
var custom_templates_paths: Array = []
var custom_exercises_paths: Array = []


func _ready() -> void:
	# Ensure user directory exists
	_ensure_user_directories()
	
	# Load settings
	_load_settings()
	
	# Load default content
	_load_default_content()

	# Always load templates saved by the user through the app
	_load_user_saved_templates()

	# Load uploaded files only when enabled
	if use_custom_templates:
		_load_uploaded_custom_template_files()
	if use_custom_exercises:
		_load_uploaded_custom_exercise_files()


func _ensure_user_directories() -> void:
	var dir = DirAccess.open("user://")
	if dir == null:
		return
	if not dir.dir_exists("templates"):
		dir.make_dir("templates")
	if not dir.dir_exists("exercises"):
		dir.make_dir("exercises")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")
	if not dir.dir_exists("uploaded_templates"):
		dir.make_dir("uploaded_templates")
	if not dir.dir_exists("uploaded_exercises"):
		dir.make_dir("uploaded_exercises")


func _load_default_content() -> void:
	var default_data = StaticData.static_data
	examples = default_data.get("examples", {}).duplicate(true)
	chapters = default_data.get("chapters", {}).duplicate(true)
	jobs = default_data.get("jobs", {}).duplicate(true)
	# Deprecated Playground content is loaded from its own legacy file.
	var legacy = _load_json_file(LEGACY_PLAYGROUND_PATH)
	templates = legacy.get("templates", {}).duplicate(true)
	exercises = legacy.get("exercises", {}).duplicate(true)


## Load custom templates from a JSON file and merge with defaults
func load_custom_templates(file_path: String) -> bool:
	var custom_data = _load_json_file(file_path)
	
	if custom_data.is_empty():
		push_error("Failed to load custom templates from: %s" % file_path)
		return false
	
	if custom_data.has("templates"):
		# Merge with existing templates (custom overrides default)
		templates.merge(custom_data["templates"], true)
		print("Loaded %d custom templates" % custom_data["templates"].size())
	
	if custom_data.has("examples"):
		examples.merge(custom_data["examples"], true)
		print("Loaded %d custom examples" % custom_data["examples"].size())
	
	return true


func import_custom_template_file(source_path: String) -> bool:
	if source_path.is_empty():
		return false

	_ensure_user_directories()
	var destination = _clone_uploaded_file(source_path, UPLOADED_TEMPLATES_DIR)
	if destination.is_empty():
		return false

	custom_templates_paths.append(destination)
	_save_settings()
	if use_custom_templates:
		if not load_custom_templates(destination):
			custom_templates_paths.erase(destination)
			var dir = DirAccess.open(destination.get_base_dir())
			if dir and dir.file_exists(destination.get_file()):
				dir.remove(destination.get_file())
			_save_settings()
			return false
	
	return true


## Load custom exercises from a JSON file and merge with defaults
func load_custom_exercises(file_path: String) -> bool:
	var custom_data = _load_json_file(file_path)
	
	if custom_data.is_empty():
		push_error("Failed to load custom exercises from: %s" % file_path)
		return false
	
	if custom_data.has("exercises"):
		# Merge with existing exercises
		exercises.merge(custom_data["exercises"], true)
		print("Loaded %d custom exercises" % custom_data["exercises"].size())
	
	return true


func import_custom_exercise_file(source_path: String) -> bool:
	if source_path.is_empty():
		return false

	_ensure_user_directories()
	var destination = _clone_uploaded_file(source_path, UPLOADED_EXERCISES_DIR)
	if destination.is_empty():
		return false

	custom_exercises_paths.append(destination)
	_save_settings()
	if use_custom_exercises:
		if not load_custom_exercises(destination):
			custom_exercises_paths.erase(destination)
			var dir = DirAccess.open(destination.get_base_dir())
			if dir and dir.file_exists(destination.get_file()):
				dir.remove(destination.get_file())
			_save_settings()
			return false
	
	return true


## Save a template collection to a JSON file
func export_templates(file_path: String, template_dict: Dictionary) -> bool:
	var data = {
		"templates": template_dict,
		"metadata": {
			"exported_at": Time.get_datetime_string_from_system(),
			"version": "1.0"
		}
	}
	
	return _save_json_file(file_path, data)


## Create a new custom template
@warning_ignore("shadowed_variable_base_class")
func add_custom_template(name: String, template_text: String) -> void:
	templates[name] = template_text
	
	# Save to custom templates file
	var custom_templates = _load_custom_templates_for_editing()
	custom_templates[name] = template_text
	_save_custom_templates(custom_templates)


## Remove a custom template
@warning_ignore("shadowed_variable_base_class")
func remove_custom_template(name: String) -> void:
	templates.erase(name)
	
	var custom_templates = _load_custom_templates_for_editing()
	custom_templates.erase(name)
	_save_custom_templates(custom_templates)


## Get all templates (merged default + custom)
func get_all_templates() -> Dictionary:
	return templates.duplicate(true)


## Get all exercises (merged default + custom)
func get_all_exercises() -> Dictionary:
	return exercises.duplicate(true)


## Get all examples
func get_all_examples() -> Dictionary:
	return examples.duplicate(true)


## Get all chapters (ordered by key)
func get_all_chapters() -> Dictionary:
	return chapters.duplicate(true)


## Get all hex-editor jobs (Phase 19). Same JSON shape as exercises,
## consumable by Checker.check_answer.
func get_all_jobs() -> Dictionary:
	return jobs.duplicate(true)


## Return job ids ordered by ascending renown_required (then alpha).
## Gives the jobs panel a stable progression order without forcing the
## JSON author to keep them sorted by hand.
func get_job_ids_sorted() -> Array:
	var ids: Array = jobs.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = int(jobs[a].get("renown_required", 0))
		var rb: int = int(jobs[b].get("renown_required", 0))
		if ra != rb:
			return ra < rb
		return a < b
	)
	return ids


func get_job(job_id: String) -> Dictionary:
	return jobs.get(job_id, {}).duplicate(true)


## Get a single chapter definition, or {} if missing
func get_chapter(chapter_id: String) -> Dictionary:
	return chapters.get(chapter_id, {}).duplicate(true)


## Return the ordered list of chapter ids (sorted alphabetically so chapter_1, chapter_2... line up)
func get_chapter_ids() -> Array:
	var ids: Array = chapters.keys()
	ids.sort()
	return ids


## Look up which chapter (if any) owns a given exercise id
func get_chapter_for_exercise(exercise_id: String) -> String:
	for chapter_id in chapters.keys():
		var exercise_ids = chapters[chapter_id].get("exercises", [])
		if exercise_id in exercise_ids:
			return chapter_id
	return ""


## Look up which chapter (if any) owns a given job id
func get_chapter_for_job(job_id: String) -> String:
	for chapter_id in chapters.keys():
		var job_ids = chapters[chapter_id].get("jobs", [])
		if job_id in job_ids:
			return chapter_id
	return ""


# ── Private helper methods ──────────────────────────────────────────────────

func _load_user_saved_templates() -> void:
	if FileAccess.file_exists(USER_SAVED_TEMPLATES_FILE):
		var data = _load_json_file(USER_SAVED_TEMPLATES_FILE)
		if data.has("templates"):
			templates.merge(data["templates"], true)
			print("Loaded %d user-saved templates" % data["templates"].size())
		if data.has("examples"):
			examples.merge(data["examples"], true)
			print("Loaded %d user-saved examples" % data["examples"].size())


func _load_uploaded_custom_template_files() -> void:
	var needs_save = false
	for source_path in custom_templates_paths.duplicate(true):
		if FileAccess.file_exists(source_path):
			load_custom_templates(source_path)
		else:
			push_error("Missing uploaded template file: %s" % source_path)
			custom_templates_paths.erase(source_path)
			needs_save = true
	if needs_save:
		_save_settings()


func _load_uploaded_custom_exercise_files() -> void:
	var needs_save = false
	for source_path in custom_exercises_paths.duplicate(true):
		if FileAccess.file_exists(source_path):
			load_custom_exercises(source_path)
		else:
			push_error("Missing uploaded exercise file: %s" % source_path)
			custom_exercises_paths.erase(source_path)
			needs_save = true
	if needs_save:
		_save_settings()


func _load_custom_templates_for_editing() -> Dictionary:
	if FileAccess.file_exists(USER_SAVED_TEMPLATES_FILE):
		var data = _load_json_file(USER_SAVED_TEMPLATES_FILE)
		return data.get("templates", {})
	return {}


func _save_custom_templates(custom_templates: Dictionary) -> void:
	var data = {
		"templates": custom_templates,
		"metadata": {
			"modified_at": Time.get_datetime_string_from_system()
		}
	}
	_save_json_file(USER_SAVED_TEMPLATES_FILE, data)


func _clone_uploaded_file(source_path: String, destination_dir: String) -> String:
	if source_path.is_empty():
		return ""
	var dir = DirAccess.open(destination_dir)
	if dir == null:
		var root = DirAccess.open("user://")
		if root != null and not root.dir_exists(destination_dir.replace("user://", "")):
			root.make_dir(destination_dir.replace("user://", ""))
		dir = DirAccess.open(destination_dir)
	if dir == null:
		push_error("Unable to create upload directory: %s" % destination_dir)
		return ""

	var base_name = source_path.get_file().get_basename()
	var dest_name = "%s_%d.json" % [base_name, Time.get_unix_time_from_system()]
	var destination = destination_dir + dest_name
	var counter = 0
	while FileAccess.file_exists(destination):
		counter += 1
		destination = "%s%s_%d_%d.json" % [destination_dir, base_name, Time.get_unix_time_from_system(), counter]

	if DirAccess.copy_absolute(source_path, destination) != OK:
		push_error("Failed to clone custom file: %s" % source_path)
		return ""
	return destination


func get_custom_template_file_paths() -> Array:
	return custom_templates_paths.duplicate(true)


func get_custom_exercise_file_paths() -> Array:
	return custom_exercises_paths.duplicate(true)


func unload_custom_template_file(path: String) -> void:
	if path in custom_templates_paths:
		custom_templates_paths.erase(path)
		var dir = DirAccess.open(path.get_base_dir())
		if dir and dir.file_exists(path.get_file()):
			dir.remove(path.get_file())
		_save_settings()
		if use_custom_templates:
			_reload_custom_templates()


func unload_all_custom_template_files() -> void:
	for path in custom_templates_paths.duplicate(true):
		var dir = DirAccess.open(path.get_base_dir())
		if dir and dir.file_exists(path.get_file()):
			dir.remove(path.get_file())
	custom_templates_paths.clear()
	_save_settings()
	if use_custom_templates:
		_reload_custom_templates()


func unload_custom_exercise_file(path: String) -> void:
	if path in custom_exercises_paths:
		custom_exercises_paths.erase(path)
		var dir = DirAccess.open(path.get_base_dir())
		if dir and dir.file_exists(path.get_file()):
			dir.remove(path.get_file())
		_save_settings()
		if use_custom_exercises:
			_reload_custom_exercises()


func unload_all_custom_exercise_files() -> void:
	for path in custom_exercises_paths.duplicate(true):
		var dir = DirAccess.open(path.get_base_dir())
		if dir and dir.file_exists(path.get_file()):
			dir.remove(path.get_file())
	custom_exercises_paths.clear()
	_save_settings()
	if use_custom_exercises:
		_reload_custom_exercises()


func _reload_custom_templates() -> void:
	_load_default_content()
	_load_user_saved_templates()
	if use_custom_templates:
		_load_uploaded_custom_template_files()


func _reload_custom_exercises() -> void:
	_load_default_content()
	_load_user_saved_templates()
	if use_custom_templates:
		_load_uploaded_custom_template_files()
	if use_custom_exercises:
		_load_uploaded_custom_exercise_files()


func _load_json_file(filepath: String) -> Dictionary:
	if not FileAccess.file_exists(filepath):
		return {}
	
	var file = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		push_error("Cannot open file: %s" % filepath)
		return {}
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	
	if error != OK:
		push_error("JSON parse error in %s: %s" % [filepath, json.get_error_message()])
		return {}
	
	if json.data is Dictionary:
		return json.data
	
	return {}


func _save_json_file(filepath: String, data: Dictionary) -> bool:
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write to file: %s" % filepath)
		return false
	
	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	
	return true


# ── Settings persistence ────────────────────────────────────────────────────

func _load_settings() -> void:
	var settings_path = "user://template_settings.json"
	var settings = _load_json_file(settings_path)
	
	use_custom_templates = settings.get("use_custom_templates", false)
	use_custom_exercises = settings.get("use_custom_exercises", false)
	custom_templates_paths = settings.get("custom_templates_paths", [])
	custom_exercises_paths = settings.get("custom_exercises_paths", [])


func _save_settings() -> void:
	var settings = {
		"use_custom_templates": use_custom_templates,
		"use_custom_exercises": use_custom_exercises,
		"custom_templates_paths": custom_templates_paths,
		"custom_exercises_paths": custom_exercises_paths
	}
	
	_save_json_file("user://template_settings.json", settings)


## Enable/disable custom templates
func set_custom_templates_enabled(enabled: bool) -> void:
	use_custom_templates = enabled
	_save_settings()

	# Reload everything
	_reload_custom_templates()


## Enable/disable custom exercises
func set_custom_exercises_enabled(enabled: bool) -> void:
	use_custom_exercises = enabled
	_save_settings()

	# Reload everything
	_reload_custom_exercises()
