extends GutTest
## Guards the static_data.json modernization: the bundled file carries only the
## modern hex keys (chapters/jobs/examples), the deprecated Playground content
## lives in legacy_playground.json, and TemplateManager still surfaces both so
## the Playground keeps working. Also pins the documented job record shape.

const LEGACY_PATH := "res://data/legacy_playground.json"
const HexPalette := preload("res://src/statics/hex_palette.gd")


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s exists" % path)
	if f == null:
		return {}
	var json := JSON.new()
	assert_eq(json.parse(f.get_as_text()), OK, "%s parses" % path)
	f.close()
	return json.data if json.data is Dictionary else {}


func test_static_data_is_modernized() -> void:
	var d: Dictionary = StaticData.static_data
	for key in ["chapters", "jobs", "examples"]:
		assert_true(d.has(key), "static_data.json keeps the modern key '%s'" % key)
	assert_false(d.has("templates"), "deprecated top-level 'templates' is gone")
	assert_false(d.has("exercises"), "deprecated top-level 'exercises' is gone")


func test_legacy_file_holds_moved_content() -> void:
	var legacy := _load_json(LEGACY_PATH)
	assert_true(legacy.has("templates"), "legacy file holds templates")
	assert_true(legacy.has("exercises"), "legacy file holds exercises")
	assert_false(legacy.get("templates", {}).is_empty(), "templates moved over")
	assert_false(legacy.get("exercises", {}).is_empty(), "exercises moved over")


func test_template_manager_surfaces_both_sources() -> void:
	# Playground content (from the legacy file) and modern content (from
	# static_data.json) are both available after boot.
	assert_false(TemplateManager.get_all_templates().is_empty(),
			"templates resolve via the legacy file")
	assert_false(TemplateManager.get_all_exercises().is_empty(),
			"exercises resolve via the legacy file")
	assert_false(TemplateManager.get_all_jobs().is_empty(), "jobs resolve")
	assert_false(TemplateManager.get_all_chapters().is_empty(), "chapters resolve")


func test_job_record_shape() -> void:
	var jobs: Dictionary = TemplateManager.get_all_jobs()
	for job_id in jobs:
		var job: Dictionary = jobs[job_id]
		for field in ["name", "description", "renown_required", "renown_reward", "tests"]:
			assert_true(job.has(field), "%s has documented field '%s'" % [job_id, field])
		assert_true(job["tests"] is Array and not job["tests"].is_empty(),
				"%s has at least one test case" % job_id)


func test_hex_path_resolves_ids_and_passes_through() -> void:
	assert_eq(StaticData.hex_path("hex_add"),
			"res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd",
			"a known id resolves to its script path")
	var raw := "res://src/classes/hex_nodes/control/if_hex.gd"
	assert_eq(StaticData.hex_path(raw), raw, "a raw res:// path passes through")
	assert_eq(StaticData.hex_path("hex_nope"), "", "an unknown id resolves to empty")
	assert_eq(StaticData.hex_paths(["hex_add", "hex_nope", "hex_let"]),
			["res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd",
			"res://src/classes/hex_nodes/control/let_hex.gd"],
			"hex_paths resolves and drops failures")
	# The two unknown-id lookups above each log a push_error by design.
	assert_push_error_count(2, "unknown ids report an error")


func test_registry_paths_exist() -> void:
	for id in StaticData.HEX_REGISTRY:
		var path: String = StaticData.HEX_REGISTRY[id]
		assert_true(id.begins_with("hex_"), "registry key '%s' follows the hex_ convention" % id)
		assert_true(FileAccess.file_exists(path), "registry path exists: %s" % path)


func test_every_unlocks_hex_id_resolves() -> void:
	var jobs: Dictionary = TemplateManager.get_all_jobs()
	for job_id in jobs:
		for entry in jobs[job_id].get("unlocks_hexes", []):
			var path := StaticData.hex_path(String(entry))
			assert_ne(path, "", "%s unlocks_hexes id '%s' resolves" % [job_id, entry])
			assert_true(FileAccess.file_exists(path),
					"%s unlocks_hexes id '%s' points at a real file" % [job_id, entry])


# Every placeable hex (HexPalette.SCRIPT_FAMILY) must have a registry id so a
# newly added hex can't drift out of sync with the resolver.
func test_registry_covers_script_family() -> void:
	var registry_paths := StaticData.HEX_REGISTRY.values()
	for path in HexPalette.SCRIPT_FAMILY:
		assert_true(path in registry_paths,
				"HEX_REGISTRY is missing an id for %s" % path)
