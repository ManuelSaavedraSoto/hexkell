extends GutTest
## Phase 19 SaveManager extensions: jobs, hex unlocks, blueprints, tabs.
##
## SaveManager is a singleton, so each test snapshots and restores the
## `hex` section. That keeps the tests independent without touching the
## real save file on disk (the singleton writes through to
## user://saves/story_progress.json when auto_save is on; auto_save is
## off in fresh defaults and we keep it that way here).


var _saved_data: Dictionary
var _saved_library: Array
var _library_file_existed: bool


func before_each() -> void:
	_saved_data = SaveManager.current_data.duplicate(true)
	_saved_library = SaveManager._blueprint_library.duplicate(true)
	_library_file_existed = FileAccess.file_exists(SaveManager.BLUEPRINT_LIBRARY_PATH)
	# Tests should not write the save file to disk, and each test starts
	# from an empty in-memory blueprint library.
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["preferences"]["archmage"] = false
	SaveManager._blueprint_library = []


func after_each() -> void:
	SaveManager.current_data = _saved_data
	SaveManager._blueprint_library = _saved_library
	# Restore the on-disk library to its pre-test state.
	if _library_file_existed:
		SaveManager._save_blueprint_library()
	elif FileAccess.file_exists(SaveManager.BLUEPRINT_LIBRARY_PATH):
		DirAccess.remove_absolute(SaveManager.BLUEPRINT_LIBRARY_PATH)


# ── Unlocks ────────────────────────────────────────────────────────────────

func test_default_unlocks_are_int_only() -> void:
	# Scaffolding: a fresh player starts with ONLY the Int literal; every
	# other hex (arithmetic included) is earned through job rewards.
	var defaults: Array = SaveManager.DEFAULT_UNLOCKED_HEX_SCRIPTS
	assert_eq(defaults,
			["res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd"],
			"Starter set must contain exactly the Int literal hex")


func test_archmage_bypasses_unlock_gate() -> void:
	# Default state: archmage off. A non-starter hex (`match_hex`) is
	# locked. Flipping archmage on should make every hex read as
	# unlocked through `is_hex_unlocked`. Flipping it off again
	# restores the original gating.
	var path := "res://src/classes/hex_nodes/control/match_hex.gd"
	assert_false(SaveManager.is_archmage(),
			"Default state: archmage off")
	assert_false(SaveManager.is_hex_unlocked(path),
			"Match hex is not in the starter unlock set")
	SaveManager.set_archmage(true)
	assert_true(SaveManager.is_archmage())
	assert_true(SaveManager.is_hex_unlocked(path),
			"Archmage on must short-circuit is_hex_unlocked")
	SaveManager.set_archmage(false)
	assert_false(SaveManager.is_hex_unlocked(path),
			"Toggling archmage off restores the normal gate")


func test_unlock_hex_is_idempotent() -> void:
	var path := "res://src/classes/hex_nodes/control/match_hex.gd"
	# Match is not part of the starter set, so the first call should
	# add it and return true; the second should report no-op.
	assert_false(SaveManager.is_hex_unlocked(path))
	assert_true(SaveManager.unlock_hex(path))
	assert_true(SaveManager.is_hex_unlocked(path))
	assert_false(SaveManager.unlock_hex(path),
			"Re-unlocking should report false (no work done)")


# ── Solved jobs ────────────────────────────────────────────────────────────

func test_record_job_solved_first_time_vs_resubmit() -> void:
	var id := "job_test_solve_idempotency"
	# Make sure the test slot is empty.
	SaveManager.current_data["hex"]["solved_jobs"] = {}
	var first := SaveManager.record_job_solved(id, "42", 7)
	assert_true(first, "First solve should return true")
	assert_true(SaveManager.is_job_solved(id))
	assert_eq(SaveManager.get_solved_jobs()[id]["renown_awarded"], 7)
	# Resubmitting refreshes the snapshot but keeps the original reward.
	var second := SaveManager.record_job_solved(id, "43", 999)
	assert_false(second, "Re-solve should return false (no second reward)")
	assert_eq(SaveManager.get_solved_jobs()[id]["renown_awarded"], 7,
			"Re-solve must NOT inflate the awarded renown amount")
	assert_eq(SaveManager.get_solved_jobs()[id]["submitted_text"], "43",
			"Re-solve refreshes the stored submission text")


# ── Blueprints (universal library) ─────────────────────────────────────────

func test_add_and_remove_blueprint() -> void:
	SaveManager.add_blueprint("doubler", "\\x -> x * 2")
	SaveManager.add_blueprint("inc", "\\x -> x + 1")
	var bps: Array = SaveManager.get_blueprints()
	assert_eq(bps.size(), 2)
	assert_eq(bps[0]["name"], "doubler")
	assert_eq(bps[1]["program_text"], "\\x -> x + 1")
	SaveManager.remove_blueprint(0)
	bps = SaveManager.get_blueprints()
	assert_eq(bps.size(), 1)
	assert_eq(bps[0]["name"], "inc")


func test_blueprint_library_round_trips_through_file() -> void:
	# Mutations write through to user://blueprint_library.json; a fresh
	# read of that file must reproduce the in-memory library.
	SaveManager.add_blueprint("keeper", "6", {"version": 1, "hexes": []})
	var reread: Array = SaveManager._read_blueprint_library_file()
	assert_eq(reread.size(), 1)
	assert_eq(String(reread[0]["name"]), "keeper")
	assert_eq(int(reread[0]["payload"]["version"]), 1)


func test_blueprint_library_survives_save_reset() -> void:
	# The library lives outside the save schema: resetting current_data
	# to defaults (what delete_save does in memory) must not touch it.
	SaveManager.add_blueprint("survivor", "6")
	SaveManager.current_data = SaveManager._default_data()
	assert_eq(SaveManager.get_blueprints().size(), 1)
	assert_true(FileAccess.file_exists(SaveManager.BLUEPRINT_LIBRARY_PATH),
			"Library file must survive a save reset")


func test_delete_blueprint_library() -> void:
	SaveManager.add_blueprint("doomed", "6")
	assert_true(FileAccess.file_exists(SaveManager.BLUEPRINT_LIBRARY_PATH))
	SaveManager.delete_blueprint_library()
	assert_eq(SaveManager.get_blueprints(), [])
	assert_false(FileAccess.file_exists(SaveManager.BLUEPRINT_LIBRARY_PATH),
			"delete_blueprint_library must remove the file")


func test_legacy_blueprints_migrate_into_library() -> void:
	# Blueprints found in the save file's legacy hex.blueprints drain
	# into the universal library (deduped) and the legacy field clears.
	var legacy := {"name": "old", "program_text": "1", "created_at": "t0"}
	SaveManager.current_data["hex"]["blueprints"] = [legacy, legacy.duplicate()]
	SaveManager._migrate_blueprints_to_library()
	assert_eq(SaveManager.get_blueprints().size(), 1,
			"Duplicate legacy entries dedupe by name+created_at")
	assert_eq(SaveManager.current_data["hex"]["blueprints"], [],
			"Legacy field must be drained after migration")
	# Re-running is a no-op.
	SaveManager._migrate_blueprints_to_library()
	assert_eq(SaveManager.get_blueprints().size(), 1)


# ── Tutorial flag ──────────────────────────────────────────────────────────

func test_tutorial_flag_defaults_false_and_round_trips() -> void:
	assert_false(bool(SaveManager._default_data()["story"]["has_completed_tutorial"]),
			"Fresh saves must start with the tutorial pending")
	SaveManager.set_tutorial_completed(true)
	assert_true(SaveManager.has_completed_tutorial())
	SaveManager.set_tutorial_completed(false)
	assert_false(SaveManager.has_completed_tutorial())


func test_grandfather_rule_marks_tutorial_done_for_veterans() -> void:
	# A save written before the flag existed, with solved jobs, belongs
	# to a player who doesn't need the tutorial.
	SaveManager.current_data = SaveManager._default_data()
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager._merge_save_data({
		"story": {"renown": 10},
		"hex": {"solved_jobs": {"job_01_any_number": {"submitted_text": "6"}}},
	})
	assert_true(SaveManager.has_completed_tutorial(),
			"Pre-flag saves with solved jobs are grandfathered in")


func test_grandfather_rule_skips_fresh_pre_flag_saves() -> void:
	SaveManager.current_data = SaveManager._default_data()
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager._merge_save_data({"story": {"renown": 0}, "hex": {}})
	assert_false(SaveManager.has_completed_tutorial(),
			"A pre-flag save with no solves still gets the tutorial")


func test_unmark_chapter_intro_seen() -> void:
	SaveManager.mark_chapter_intro_seen("chapter_0_tutorial")
	assert_true(SaveManager.has_seen_chapter_intro("chapter_0_tutorial"))
	SaveManager.unmark_chapter_intro_seen("chapter_0_tutorial")
	assert_false(SaveManager.has_seen_chapter_intro("chapter_0_tutorial"))


# ── Tabs ───────────────────────────────────────────────────────────────────

func test_set_and_get_tabs() -> void:
	# Bare-string input is accepted and lifted into the new
	# {name, payload} shape for backwards compatibility.
	SaveManager.set_tabs(["a", "b", "c"], 1)
	assert_eq(SaveManager.get_tab_names(), ["a", "b", "c"])
	assert_eq(SaveManager.get_current_tab_id(), 1)


func test_set_tabs_round_trips_payloads() -> void:
	# The shape we actually store + read back: each tab carries a
	# `name` and a structured `payload` (the BlueprintCodec dict —
	# any JSON-safe value works here).
	var entries := [
		{"name": "first", "payload": {"version": 1, "hexes": [], "wires": []}},
		{"name": "second", "payload": {}},
	]
	SaveManager.set_tabs(entries, 0)
	var loaded: Array = SaveManager.get_tab_payloads()
	assert_eq(loaded.size(), 2)
	assert_eq(String(loaded[0]["name"]), "first")
	assert_eq(int(loaded[0]["payload"]["version"]), 1)
	assert_true(Dictionary(loaded[1]["payload"]).is_empty(),
			"empty payload should round-trip unchanged")
	# The name-only derived view still works.
	assert_eq(SaveManager.get_tab_names(), ["first", "second"])


func test_legacy_string_tabs_migrate_on_read() -> void:
	# Simulate a save written by an older build that stored the tabs
	# list as plain strings. The next read should migrate them in
	# place to the {name, payload: {}} shape.
	SaveManager.current_data["hex"]["tabs"] = ["alpha", "beta"]
	var loaded: Array = SaveManager.get_tab_payloads()
	assert_eq(loaded.size(), 2)
	assert_eq(String(loaded[0]["name"]), "alpha")
	assert_true(Dictionary(loaded[0]["payload"]).is_empty())
	# Migration is sticky — the in-memory tabs array now holds the
	# new shape, so subsequent reads don't re-migrate.
	assert_true(SaveManager.current_data["hex"]["tabs"][0] is Dictionary,
			"After read, the legacy strings should be replaced in place")


# ── Backfill on legacy saves ───────────────────────────────────────────────

func test_hex_section_backfills_on_missing_keys() -> void:
	# Simulate a pre-Phase-19 save file that has no `hex` section.
	SaveManager.current_data.erase("hex")
	# Any accessor should lazily reconstruct the section with defaults.
	var unlocked: Array = SaveManager.get_unlocked_hex_scripts()
	assert_false(unlocked.is_empty(),
			"Legacy save must backfill starter unlocks, not return empty")
	assert_eq(SaveManager.get_solved_jobs(), {})
	assert_eq(SaveManager.get_blueprints(), [])
