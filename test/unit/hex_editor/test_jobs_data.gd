extends GutTest
## Phase 19.2 — sanity-check that the bundled jobs in static_data.json
## (loaded by TemplateManager) are well-formed: each has a name +
## description + tests, all referenced unlock paths point at real
## hex scripts, and the renown-required ordering produces a stable
## sorted list.


func test_jobs_load_from_template_manager() -> void:
	var jobs: Dictionary = TemplateManager.get_all_jobs()
	assert_false(jobs.is_empty(),
			"At least one job must ship with the project (data/static_data.json)")


func test_every_job_has_required_fields() -> void:
	for id in TemplateManager.get_all_jobs().keys():
		var job: Dictionary = TemplateManager.get_job(id)
		assert_true(job.has("name"), "Job %s is missing 'name'" % id)
		assert_true(job.has("description"), "Job %s is missing 'description'" % id)
		assert_true(job.has("tests"), "Job %s is missing 'tests'" % id)
		assert_true(job.get("tests") is Array,
				"Job %s 'tests' must be an Array" % id)
		assert_false((job.get("tests") as Array).is_empty(),
				"Job %s must have at least one test case" % id)
		# renown_reward defaults to 0 in SaveManager.record_job_solved but
		# every shipped job should have a positive reward — otherwise
		# solving it doesn't move progression.
		assert_gt(int(job.get("renown_reward", 0)), 0,
				"Job %s has no renown_reward — progression is broken" % id)


func test_unlocks_hexes_paths_exist() -> void:
	for id in TemplateManager.get_all_jobs().keys():
		var ids: Array = TemplateManager.get_job(id).get("unlocks_hexes", [])
		for p in ids:
			var sp := StaticData.hex_path(String(p))
			assert_ne(sp, "", "Job %s unlocks an unknown hex id: %s" % [id, p])
			assert_true(ResourceLoader.exists(sp),
					"Job %s unlocks a missing script: %s" % [id, sp])


func test_progression_chain_is_solvable_with_starter_set() -> void:
	# Walk the jobs in their intended renown order and confirm every
	# job's `unlocks_hexes` is fully unlocked by the time we reach a
	# later job that *depends* on those hexes — i.e. no job requires
	# (via its description, encoded here as a structural sanity
	# check) a hex that the player hasn't earned yet.
	#
	# We can't infer "requires hex X" from the JSON alone, so this
	# test is intentionally narrow: it confirms that the very early
	# jobs run against just the starter set, and that the `if` /
	# `lambda` unlocks land BEFORE the jobs whose descriptions name
	# those hexes ("pick_bigger" needs if; "increment_fn" needs λ).
	var ids: Array = TemplateManager.get_job_ids_sorted()
	var unlocked: Array = SaveManager.DEFAULT_UNLOCKED_HEX_SCRIPTS.duplicate()
	for id in ids:
		var job: Dictionary = TemplateManager.get_job(id)
		var desc: String = String(job.get("name", "") + " " + job.get("description", "")).to_lower()
		if "if " in desc or "if[/" in desc:
			assert_true("res://src/classes/hex_nodes/control/if_hex.gd" in unlocked,
					"Job %s mentions `if`, but the If hex is still locked at this point in the progression chain" % id)
		if "λ" in desc or "lambda" in desc:
			assert_true("res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd" in unlocked,
					"Job %s mentions a lambda, but the λ hex is still locked at this point in the progression chain" % id)
		# Scaffolding checks for the shrunken starter set (Int only):
		# booleans and comparisons must be earned before the jobs that
		# name them.
		if "[b]true[/b]" in desc or "[b]false[/b]" in desc:
			assert_true("res://src/classes/hex_nodes/literals/booleans/true_hex.gd" in unlocked,
					"Job %s mentions a bool literal, but the true hex is still locked at this point in the progression chain" % id)
		if "comparison" in desc or "less than" in desc:
			assert_true("res://src/classes/hex_nodes/operators/logical/lt_hex.gd" in unlocked,
					"Job %s needs a comparison, but the < hex is still locked at this point in the progression chain" % id)
		if "[b]id[/b]" in desc or "identifier" in desc:
			assert_true("res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd" in unlocked,
					"Job %s needs identifiers, but the id hex is still locked at this point in the progression chain" % id)
		for entry in job.get("unlocks_hexes", []):
			var path := StaticData.hex_path(String(entry))
			if path != "" and path not in unlocked:
				unlocked.append(path)


func test_compare_white_black_rejects_literal_true() -> void:
	# job_07_compare_white_black requires the player to wire a real
	# comparison (uses `binary_op` + `variable`) and forbids any
	# `bool` literal in the AST, so a degenerate `true` answer must
	# fail with a structure error.
	var job: Dictionary = TemplateManager.get_job("job_07_compare_white_black")
	if job.is_empty():
		# Job was removed / renamed — the test is no longer
		# applicable, but we shouldn't fail loudly.
		return
	var result: Dictionary = Checker.check_answer(job, "true")
	assert_false(result.get("correct", false),
			"compare_white_black must reject a bare `true` answer")
	assert_true(String(result.get("message", "")).find("Forbidden") != -1,
			"Rejection should cite the forbidden `bool` structure; got: %s" % result.get("message"))


func test_compare_white_black_accepts_real_comparison() -> void:
	var job: Dictionary = TemplateManager.get_job("job_07_compare_white_black")
	if job.is_empty():
		return
	var result: Dictionary = Checker.check_answer(job, "white < black")
	assert_true(result.get("correct", false),
			"compare_white_black must accept `white < black` (got: %s)" % result.get("message"))


# ── New-ladder structural lessons ──────────────────────────────────────────
# Each teaching job rejects answers that skip its new hex; the lesson
# is enforced by required/forbidden structures, not just the value.

func test_add_crates_rejects_pretotalled_literal() -> void:
	var job: Dictionary = TemplateManager.get_job("job_02_add_crates")
	assert_false(job.is_empty(), "job_02_add_crates must ship")
	assert_false(Checker.check_answer(job, "8").get("correct", false),
			"A bare 8 skips the + hex and must be rejected")
	assert_true(Checker.check_answer(job, "5 + 3").get("correct", false),
			"5 + 3 is the intended solution")


func test_quality_check_rejects_bare_true() -> void:
	var job: Dictionary = TemplateManager.get_job("job_04_quality_check")
	assert_false(job.is_empty(), "job_04_quality_check must ship")
	assert_false(Checker.check_answer(job, "true").get("correct", false),
			"A bare true skips the comparison and must be rejected")
	assert_true(Checker.check_answer(job, "3 < 5").get("correct", false),
			"3 < 5 is the intended solution")


func test_let_binding_requires_a_let() -> void:
	var job: Dictionary = TemplateManager.get_job("job_10_let_binding")
	assert_false(job.is_empty(), "job_10_let_binding must ship")
	# A bare literal that hits the value but skips the let is rejected by
	# the required-structure auditor; binding white+1 with a let passes.
	assert_false(Checker.check_answer(job, "49").get("correct", false),
			"A bare 49 skips the let and must be rejected")
	assert_true(Checker.check_answer(job, "let m = white + 1 in m * m").get("correct", false),
			"Binding white+1 with a let is the intended solution")


func test_echo_white_rejects_hardcoded_int() -> void:
	var job: Dictionary = TemplateManager.get_job("job_05_echo_white")
	assert_false(job.is_empty(), "job_05_echo_white must ship")
	assert_false(Checker.check_answer(job, "7").get("correct", false),
			"Hard-coding the shipment count must be rejected — the id hex IS the lesson")
	assert_true(Checker.check_answer(job, "white").get("correct", false),
			"Wiring the white identifier straight into Do is the intended solution")


# ── Reserved parameters on `main` ────────────────────────────────────────────
# When a job exposes reserved identifiers (white / black) the editor emits
# `do main white black = <expr>`, so `main` is a closure and the checker
# binds the job's injected values to those parameters in palette order.

func test_reserved_params_applied_to_main_closure() -> void:
	var exercise := {
		"variables": {"white": 3, "black": 4},
		"tests": [{"expected": 7}],
	}
	var result: Dictionary = Checker.check_answer(
			exercise, "do main white black = white + black")
	assert_true(result.get("correct", false),
			"main's reserved params must be bound from variables (got: %s)"
			% result.get("message"))


func test_reserved_params_respect_palette_order() -> void:
	# white (index 6) is applied before black (index 7); subtraction is
	# order-sensitive, so a wrong order would yield 1 instead of -1.
	var exercise := {
		"variables": {"white": 3, "black": 4},
		"tests": [{"expected": -1}],
	}
	var result: Dictionary = Checker.check_answer(
			exercise, "do main white black = white - black")
	assert_true(result.get("correct", false),
			"Reserved params must apply in palette order white-before-black (got: %s)"
			% result.get("message"))


func test_reserved_var_bare_expression_still_env_injected() -> void:
	# Backward compatibility: an answer that references the reserved name
	# directly (no `do main` wrapper) is still bound through the env.
	var exercise := {
		"variables": {"white": 7},
		"tests": [{"expected": 7}],
	}
	assert_true(Checker.check_answer(exercise, "white").get("correct", false),
			"A bare reserved reference must still resolve via env injection")
	assert_true(Checker.check_answer(exercise, "do main white = white").get("correct", false),
			"The `do main white = white` form must resolve via parameter binding")


func test_get_job_ids_sorted_orders_by_renown_required() -> void:
	# get_job_ids_sorted must return ids in non-decreasing renown_required.
	var ids: Array = TemplateManager.get_job_ids_sorted()
	if ids.size() < 2:
		# Can't validate ordering with fewer than two jobs.
		return
	var prev_renown: int = -1
	for id in ids:
		var r: int = int(TemplateManager.get_job(id).get("renown_required", 0))
		assert_true(r >= prev_renown,
				"Jobs out of order at %s (renown %d follows %d)" % [id, r, prev_renown])
		prev_renown = r
