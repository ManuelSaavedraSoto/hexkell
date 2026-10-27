extends GutTest
## Chapter progression invariants. The chapter intros gate which
## blueprint templates the player receives (via `unlocks_templates`), so
## their ordering is load-bearing: handing out `let rec` before the
## player has met `if` invites base-case-less recursion that loops
## forever. These tests pin the Identifiers → Conditionals → Bindings →
## Lambdas sequence that keeps recursion teachable.


# chapter id (sorted) → ordinal, mirroring TemplateManager.get_chapter_ids().
func _chapter_order() -> Dictionary:
	var order: Dictionary = {}
	var ids: Array = TemplateManager.get_chapter_ids()
	for i in ids.size():
		order[ids[i]] = i
	return order


# First chapter (in progression order) whose intro unlocks `template`.
func _chapter_unlocking(template: String) -> String:
	for cid in TemplateManager.get_chapter_ids():
		if template in TemplateManager.get_chapter(cid).get("unlocks_templates", []):
			return cid
	return ""


func test_letrec_template_unlocks_after_conditionals() -> void:
	var order := _chapter_order()
	var if_chapter := _chapter_unlocking("if")
	var letrec_chapter := _chapter_unlocking("let_rec")
	assert_false(if_chapter.is_empty(), "some chapter must unlock the `if` template")
	assert_false(letrec_chapter.is_empty(), "some chapter must unlock the `let_rec` template")
	assert_true(order[if_chapter] < order[letrec_chapter],
			"`let rec` must be taught after `if`, so recursion can have a base case " +
			"(if @ %s, let rec @ %s)" % [if_chapter, letrec_chapter])


func test_identifiers_chapter_teaches_no_bindings() -> void:
	# The split moved declarations out of the identifiers chapter; it now
	# only introduces reading names, never binding them.
	var templates: Array = TemplateManager.get_chapter("chapter_4_identifiers").get("unlocks_templates", [])
	assert_does_not_have(templates, "let")
	assert_does_not_have(templates, "let_rec")


func test_lambdas_sit_between_conditionals_and_bindings() -> void:
	# Lambdas were split out of the old combined chapter and moved ahead of
	# Bindings, because the Bindings-era jobs already use lambdas.
	var order := _chapter_order()
	for cid in ["chapter_5_conditionals", "chapter_6_lambdas",
			"chapter_7_bindings", "chapter_8_structures"]:
		assert_true(order.has(cid), "%s should exist" % cid)
	assert_true(order["chapter_5_conditionals"] < order["chapter_6_lambdas"],
			"Lambdas comes after Conditionals")
	assert_true(order["chapter_6_lambdas"] < order["chapter_7_bindings"],
			"Lambdas is taught before Bindings (lambdas are used before lets)")
	assert_true(order["chapter_7_bindings"] < order["chapter_8_structures"],
			"Bindings comes before Structures")


func test_lambda_template_unlocks_before_let() -> void:
	# The whole point of the split: the `lambda` template must be handed out
	# before `let`/`let_rec`, since the lambda jobs precede the let job.
	var order := _chapter_order()
	var lambda_chapter := _chapter_unlocking("lambda")
	var let_chapter := _chapter_unlocking("let")
	assert_false(lambda_chapter.is_empty(), "some chapter must unlock `lambda`")
	assert_false(let_chapter.is_empty(), "some chapter must unlock `let`")
	assert_true(order[lambda_chapter] < order[let_chapter],
			"`lambda` must be taught before `let` (lambda @ %s, let @ %s)"
			% [lambda_chapter, let_chapter])


func test_template_chapters_own_a_renown_gated_job() -> void:
	# A template-unlocking chapter needs at least one job, or its intro
	# never fires (and the templates never unlock). Check both the Lambdas
	# and Bindings chapters, and that their jobs gate after Conditionals'.
	var cond_jobs: Array = TemplateManager.get_chapter("chapter_5_conditionals").get("jobs", [])
	var cond_renown: int = int(TemplateManager.get_job(String(cond_jobs[0])).get("renown_required", 0))
	for cid in ["chapter_6_lambdas", "chapter_7_bindings"]:
		var jobs: Array = TemplateManager.get_chapter(cid).get("jobs", [])
		assert_false(jobs.is_empty(), "%s needs a job so its intro can fire" % cid)
		var renown: int = int(TemplateManager.get_job(String(jobs[0])).get("renown_required", 0))
		assert_gt(renown, cond_renown,
				"%s's job should gate after the Conditionals job" % cid)
