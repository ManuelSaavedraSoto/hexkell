extends Node
## Manages saving and loading game progress

const SAVE_FILE_PATH := "user://saves/story_progress.json"
const SAVE_VERSION := "1.0"

# Universal blueprint library. Lives OUTSIDE the save file on purpose:
# blueprints are workshop knowledge, not story progress, so they persist
# across save deletions (and, later, across multiple user profiles).
const BLUEPRINT_LIBRARY_PATH := "user://blueprint_library.json"
const BLUEPRINT_LIBRARY_VERSION := 1

# Default hex script paths that the player starts with. Anything not in
# this list (and not added via job rewards) is locked in the palette.
# Deliberately minimal — just the Int literal — so the tutorial's
# scaffolding holds: every other hex is earned through jobs (see each
# job's `unlocks_hexes` in data/static_data.json).
const DEFAULT_UNLOCKED_HEX_SCRIPTS := [
	"res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
]

# Story progress data
var current_data := _default_data()

var is_loaded := false

# Universal blueprint library, loaded from BLUEPRINT_LIBRARY_PATH. Entries
# share the legacy `hex.blueprints` shape: {name, program_text, created_at,
# payload?}. Mutations write through immediately (the library is small and
# universal, so it ignores the per-save `auto_save` preference).
var _blueprint_library: Array = []


# Single source of truth for the save schema. Used for both first-boot
# defaults and the post-`delete_save` reset, so new fields only need to
# be declared once.
static func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"story": {
			"current_level": 0,
			"completed_levels": [],
			"unlocked_patterns": [],
			"renown": 0,
			"total_clients_completed": 0,
			"seen_chapter_intros": [],
			# Flipped when the chapter-0 interactive tutorial finishes;
			# TutorialManager stays dormant while this is true.
			"has_completed_tutorial": false,
		},
		"stats": {
			"play_time_seconds": 0,
			"exercises_completed": [],
			"exercises_attempted": [],
			"total_code_runs": 0,
		},
		"preferences": {
			"show_hints": true,
			"auto_save": true,
		},
		# Phase 19: hex-editor gameplay loop.
		"hex": {
			# Player-named workspace tabs with their serialized hex
			# graphs (`{name, payload}` per entry).
			"tabs": [],
			"current_tab_id": 0,
			# job_id -> {submitted_text, solved_at, renown_awarded}
			"solved_jobs": {},
			# Legacy home of captured blueprints. Now drained into the
			# universal library file on load (see _migrate_blueprints_
			# to_library); kept so old saves merge cleanly.
			"blueprints": [],
			# Script paths the player has unlocked. Defaults populate on
			# first load (see _merge_save_data).
			"unlocked_hex_scripts": DEFAULT_UNLOCKED_HEX_SCRIPTS.duplicate(),
		},
		"timestamp": "",
	}


func _ready() -> void:
	_blueprint_library = _read_blueprint_library_file()
	load_game()


## Save current game progress
func save_game() -> bool:
	current_data["timestamp"] = Time.get_datetime_string_from_system()
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write save file: %s" % SAVE_FILE_PATH)
		return false
	
	var json_string = JSON.stringify(current_data, "\t")
	file.store_string(json_string)
	file.close()
	
	print("Game saved to: %s" % SAVE_FILE_PATH)
	return true


## Load game progress
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("No save file found, using default data")
		is_loaded = true
		return false
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read save file: %s" % SAVE_FILE_PATH)
		return false
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	
	if error != OK:
		push_error("Save file parse error: %s" % json.get_error_message())
		return false
	
	if json.data is Dictionary:
		# Merge loaded data with defaults (in case new fields were added)
		_merge_save_data(json.data)
		_migrate_blueprints_to_library()
		is_loaded = true
		print("Game loaded from: %s" % SAVE_FILE_PATH)
		return true

	return false


## Delete save file. The universal blueprint library deliberately
## survives this — it has its own `delete_blueprint_library()`.
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_FILE_PATH):
		DirAccess.remove_absolute(SAVE_FILE_PATH)
		print("Save file deleted")

	# Reset to defaults
	current_data = _default_data()


## Check if a save file exists
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)


# ── Story Progress Methods ──────────────────────────────────────────────────

func get_current_level() -> int:
	return current_data["story"]["current_level"]


func set_current_level(level: int) -> void:
	current_data["story"]["current_level"] = level
	if current_data["preferences"]["auto_save"]:
		save_game()


func complete_level(level: int) -> void:
	if level not in current_data["story"]["completed_levels"]:
		current_data["story"]["completed_levels"].append(level)
	
	# Advance to next level
	if level >= current_data["story"]["current_level"]:
		current_data["story"]["current_level"] = level + 1
	
	if current_data["preferences"]["auto_save"]:
		save_game()


func is_level_completed(level: int) -> bool:
	return level in current_data["story"]["completed_levels"]


func add_renown(amount: int) -> void:
	current_data["story"]["renown"] += amount
	if current_data["preferences"]["auto_save"]:
		save_game()


func get_renown() -> int:
	return current_data["story"]["renown"]


func unlock_pattern(pattern_name: String) -> void:
	if pattern_name not in current_data["story"]["unlocked_patterns"]:
		current_data["story"]["unlocked_patterns"].append(pattern_name)
		if current_data["preferences"]["auto_save"]:
			save_game()


func is_pattern_unlocked(pattern_name: String) -> bool:
	return pattern_name in current_data["story"]["unlocked_patterns"]


func get_unlocked_patterns() -> Array:
	return current_data["story"]["unlocked_patterns"]


func complete_client() -> void:
	current_data["story"]["total_clients_completed"] += 1
	if current_data["preferences"]["auto_save"]:
		save_game()


func has_seen_chapter_intro(chapter_id: String) -> bool:
	var seen: Array = current_data["story"].get("seen_chapter_intros", [])
	return chapter_id in seen


func get_seen_chapter_intros() -> Array:
	return current_data["story"].get("seen_chapter_intros", [])


func mark_chapter_intro_seen(chapter_id: String) -> void:
	if not current_data["story"].has("seen_chapter_intros"):
		current_data["story"]["seen_chapter_intros"] = []
	if chapter_id not in current_data["story"]["seen_chapter_intros"]:
		current_data["story"]["seen_chapter_intros"].append(chapter_id)
		if current_data["preferences"]["auto_save"]:
			save_game()


# Forget that a chapter intro was shown — used by the settings menu's
# "Replay tutorial" so the chapter-0 intro pops again alongside the
# interactive steps.
func unmark_chapter_intro_seen(chapter_id: String) -> void:
	var seen: Array = current_data["story"].get("seen_chapter_intros", [])
	if chapter_id in seen:
		seen.erase(chapter_id)
		if current_data["preferences"]["auto_save"]:
			save_game()


func has_completed_tutorial() -> bool:
	return bool(current_data["story"].get("has_completed_tutorial", false))


func set_tutorial_completed(done: bool) -> void:
	current_data["story"]["has_completed_tutorial"] = done
	if current_data["preferences"]["auto_save"]:
		save_game()


# ── Stats Methods ───────────────────────────────────────────────────────────

func add_play_time(seconds: float) -> void:
	current_data["stats"]["play_time_seconds"] += int(seconds)


func get_play_time() -> int:
	return current_data["stats"]["play_time_seconds"]


func complete_exercise(exercise_id: String) -> void:
	if exercise_id not in current_data["stats"]["exercises_completed"]:
		current_data["stats"]["exercises_completed"].append(exercise_id)
	
	if current_data["preferences"]["auto_save"]:
		save_game()


func attempt_exercise(exercise_id: String) -> void:
	if exercise_id not in current_data["stats"]["exercises_attempted"]:
		current_data["stats"]["exercises_attempted"].append(exercise_id)


func is_exercise_completed(exercise_id: String) -> bool:
	return exercise_id in current_data["stats"]["exercises_completed"]


func increment_code_runs() -> void:
	current_data["stats"]["total_code_runs"] += 1


# ── Preferences Methods ─────────────────────────────────────────────────────

func set_show_hints(enabled: bool) -> void:
	current_data["preferences"]["show_hints"] = enabled
	save_game()


func get_show_hints() -> bool:
	return current_data["preferences"]["show_hints"]


func set_auto_save(enabled: bool) -> void:
	current_data["preferences"]["auto_save"] = enabled
	save_game()


func get_auto_save() -> bool:
	return current_data["preferences"]["auto_save"]


# ── Hex Editor (Phase 19) ───────────────────────────────────────────────────
#
# The hex editor's gameplay loop replaces "exercises" with "jobs" and
# "templates" with "blueprints"; progression unlocks "hex script paths"
# rather than text snippets. The keys live under `current_data.hex` so
# everything story-related (renown, chapter intros) can stay shared
# between the text editor and the hex editor.

func get_unlocked_hex_scripts() -> Array:
	return _hex_section().get("unlocked_hex_scripts", [])


func is_hex_unlocked(script_path: String) -> bool:
	if is_archmage():
		return true
	return script_path in get_unlocked_hex_scripts()


# Archmage / debug mode: when enabled, every hex is treated as
# unlocked (here) and every renown threshold is bypassed in the
# jobs panel + palette. Stored under `preferences` so it persists
# across sessions like `auto_save` and `show_hints`.
func is_archmage() -> bool:
	return bool(current_data["preferences"].get("archmage", false))


func set_archmage(enabled: bool) -> void:
	current_data["preferences"]["archmage"] = enabled
	if get_auto_save():
		save_game()


func unlock_hex(script_path: String) -> bool:
	var unlocked: Array = _hex_section().get("unlocked_hex_scripts", [])
	if script_path in unlocked:
		return false
	unlocked.append(script_path)
	_hex_section()["unlocked_hex_scripts"] = unlocked
	if current_data["preferences"]["auto_save"]:
		save_game()
	return true


func get_solved_jobs() -> Dictionary:
	return _hex_section().get("solved_jobs", {})


func is_job_solved(job_id: String) -> bool:
	return job_id in get_solved_jobs()


# Record a solve. Returns true the FIRST time `job_id` is recorded
# (caller uses this to decide whether to award renown + unlocks).
# Re-solves are idempotent: the snapshot text is refreshed but no
# additional renown is granted.
func record_job_solved(job_id: String, submitted_text: String, renown_awarded: int) -> bool:
	var solved: Dictionary = _hex_section().get("solved_jobs", {})
	var first_time := not solved.has(job_id)
	var existing_renown: int = 0
	if not first_time:
		existing_renown = int(solved[job_id].get("renown_awarded", 0))
	solved[job_id] = {
		"submitted_text": submitted_text,
		"solved_at": Time.get_datetime_string_from_system(),
		"renown_awarded": renown_awarded if first_time else existing_renown,
	}
	_hex_section()["solved_jobs"] = solved
	if current_data["preferences"]["auto_save"]:
		save_game()
	return first_time


# ── Universal blueprint library ─────────────────────────────────────────────
#
# Blueprints live in their own file (BLUEPRINT_LIBRARY_PATH) so they
# survive save deletion. The public API kept its pre-library shape, so
# the editor and the library dialog needed no changes.

func get_blueprints() -> Array:
	return _blueprint_library


# Append a captured blueprint. `program_text` is the human-readable
# fallback (preserved for legacy display); `payload` is the structured
# blueprint dict from BlueprintCodec — the actual round-trippable
# form. Older callers that only pass `program_text` still work; the
# blueprint will simply lack a stamp body.
func add_blueprint(name: String, program_text: String, payload: Dictionary = {}) -> void:
	var entry := {
		"name": name,
		"program_text": program_text,
		"created_at": Time.get_datetime_string_from_system(),
	}
	if not payload.is_empty():
		entry["payload"] = payload
	_blueprint_library.append(entry)
	_save_blueprint_library()


func remove_blueprint(index: int) -> void:
	if index < 0 or index >= _blueprint_library.size():
		return
	_blueprint_library.remove_at(index)
	_save_blueprint_library()


func rename_blueprint(index: int, new_name: String) -> void:
	if index < 0 or index >= _blueprint_library.size():
		return
	var clean := new_name.strip_edges()
	if clean.is_empty():
		return
	_blueprint_library[index]["name"] = clean
	_save_blueprint_library()


func delete_blueprint_library() -> void:
	_blueprint_library = []
	if FileAccess.file_exists(BLUEPRINT_LIBRARY_PATH):
		DirAccess.remove_absolute(BLUEPRINT_LIBRARY_PATH)
		print("Blueprint library deleted")


func _read_blueprint_library_file() -> Array:
	if not FileAccess.file_exists(BLUEPRINT_LIBRARY_PATH):
		return []
	var file = FileAccess.open(BLUEPRINT_LIBRARY_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read blueprint library: %s" % BLUEPRINT_LIBRARY_PATH)
		return []
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK or not (json.data is Dictionary):
		push_error("Blueprint library parse error: %s" % json.get_error_message())
		return []
	var bps = json.data.get("blueprints", [])
	return bps if bps is Array else []


func _save_blueprint_library() -> bool:
	var file = FileAccess.open(BLUEPRINT_LIBRARY_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write blueprint library: %s" % BLUEPRINT_LIBRARY_PATH)
		return false
	file.store_string(JSON.stringify({
		"version": BLUEPRINT_LIBRARY_VERSION,
		"blueprints": _blueprint_library,
	}, "\t"))
	file.close()
	return true


# One-way migration: drain any blueprints still living in the save
# file's legacy `hex.blueprints` into the universal library (deduped by
# name + created_at), then clear the legacy field so they aren't
# re-imported next boot.
func _migrate_blueprints_to_library() -> void:
	var legacy: Array = _hex_section().get("blueprints", [])
	if legacy.is_empty():
		return
	var known := {}
	for bp in _blueprint_library:
		known["%s|%s" % [bp.get("name", ""), bp.get("created_at", "")]] = true
	var added := false
	for bp in legacy:
		if not (bp is Dictionary):
			continue
		var key := "%s|%s" % [bp.get("name", ""), bp.get("created_at", "")]
		if known.has(key):
			continue
		_blueprint_library.append(bp)
		known[key] = true
		added = true
	_hex_section()["blueprints"] = []
	if added:
		_save_blueprint_library()
	# Persist the drained legacy field; with auto_save off the migration
	# simply re-runs (and re-dedupes) on the next boot.
	if current_data["preferences"]["auto_save"]:
		save_game()


# Tab payloads are stored as `[{name, payload, …}, …]`. `payload` is
# the dict `BlueprintCodec.serialize_root` returns — empty `{}` for a
# brand-new tab that the player hasn't built anything on yet. The
# legacy save format stored plain strings here (just tab names); we
# migrate those on read into the new shape with empty payloads, so
# old saves load without losing tab names.
func get_tab_payloads() -> Array:
	return _migrate_legacy_tabs(_hex_section().get("tabs", []))


# Convenience: derive the bare tab-name list from the payloads.
# Lets callers that only care about names skip the wrapper-dict
# unpacking.
func get_tab_names() -> Array:
	var names: Array = []
	for entry in get_tab_payloads():
		names.append(String(entry.get("name", "")))
	return names


# Persist the tabs. `payloads` is a list of dicts shaped
# `{name: String, payload: Dictionary}` — `payload` may be empty for
# tabs that have no hex content yet. `current_tab_id` is the
# editor's active-tab index.
func set_tabs(payloads: Array, current_tab_id: int) -> void:
	# Defensive copy + reshape: callers may hand us raw payloads
	# without the wrapper (or legacy bare strings during testing); we
	# normalize to the {name, payload} shape on the way in.
	var clean: Array = []
	for entry in payloads:
		if entry is String:
			clean.append({"name": String(entry), "payload": {}})
		elif entry is Dictionary:
			clean.append({
				"name": String(entry.get("name", "")),
				"payload": entry.get("payload", {}),
			})
	_hex_section()["tabs"] = clean
	_hex_section()["current_tab_id"] = current_tab_id
	if current_data["preferences"]["auto_save"]:
		save_game()


# Migrate legacy `tabs: [String]` saves to the new
# `tabs: [{name, payload}]` shape in place. Idempotent — payloads
# that are already dicts pass through unchanged.
func _migrate_legacy_tabs(raw: Array) -> Array:
	var migrated: Array = []
	var needed := false
	for entry in raw:
		if entry is String:
			migrated.append({"name": String(entry), "payload": {}})
			needed = true
		elif entry is Dictionary:
			migrated.append(entry)
	if needed:
		_hex_section()["tabs"] = migrated
	return migrated


func get_current_tab_id() -> int:
	return int(_hex_section().get("current_tab_id", 0))


# Internal accessor that lazily backfills the `hex` section when an
# older save predates Phase 19 (the merge ensures top-level keys exist
# but nested defaults can be missing on old saves).
func _hex_section() -> Dictionary:
	if not current_data.has("hex") or not (current_data["hex"] is Dictionary):
		current_data["hex"] = {}
	var hex: Dictionary = current_data["hex"]
	if not hex.has("unlocked_hex_scripts"):
		hex["unlocked_hex_scripts"] = DEFAULT_UNLOCKED_HEX_SCRIPTS.duplicate()
	else:
		_migrate_legacy_unlock_paths(hex)
	if not hex.has("solved_jobs"):
		hex["solved_jobs"] = {}
	if not hex.has("blueprints"):
		hex["blueprints"] = []
	if not hex.has("tabs"):
		hex["tabs"] = []
	if not hex.has("current_tab_id"):
		hex["current_tab_id"] = 0
	return hex


# Saves written before the hex-node files moved to `src/classes/hex_nodes/`
# carry their legacy `scenes/gui/hex_editor/nodes/` paths. Retarget them
# in place so the unlock set lines up with the current palette paths.
func _migrate_legacy_unlock_paths(hex: Dictionary) -> void:
	var unlocked: Array = hex["unlocked_hex_scripts"]
	var changed := false
	for i in range(unlocked.size()):
		var p := String(unlocked[i])
		if p.begins_with("res://scenes/gui/hex_editor/nodes/"):
			unlocked[i] = p.replace(
				"res://scenes/gui/hex_editor/nodes/",
				"res://src/classes/hex_nodes/")
			changed = true
	if changed:
		hex["unlocked_hex_scripts"] = unlocked


# ── Private Methods ─────────────────────────────────────────────────────────

func _merge_save_data(loaded_data: Dictionary) -> void:
	# Recursively merge loaded data with defaults
	_deep_merge(current_data, loaded_data)
	# Backfill Phase 19 defaults on saves that predate it.
	_hex_section()
	# Grandfather rule: saves that predate the tutorial flag but have
	# already solved jobs belong to players who clearly don't need the
	# chapter-0 hand-holding — mark the tutorial done for them.
	var loaded_story: Dictionary = loaded_data.get("story", {})
	if not loaded_story.has("has_completed_tutorial") \
			and not _hex_section().get("solved_jobs", {}).is_empty():
		current_data["story"]["has_completed_tutorial"] = true


func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		if key in target and target[key] is Dictionary and source[key] is Dictionary:
			_deep_merge(target[key], source[key])
		else:
			target[key] = source[key]
