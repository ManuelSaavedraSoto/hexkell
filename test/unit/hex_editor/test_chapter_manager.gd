extends GutTest
## ChapterManager: job selection, solve/award bookkeeping, chapter
## unlock gating, and intro scheduling — all scene-free, so we drive a
## fresh instance of the script directly (signals stay isolated from
## the autoload) and snapshot SaveManager around each test.

const ChapterScript := preload("res://src/singletons/chapter_manager.gd")

var _cm: Node
var _saved_data: Dictionary


func before_each() -> void:
	_saved_data = SaveManager.current_data.duplicate(true)
	SaveManager.current_data["preferences"]["auto_save"] = false
	SaveManager.current_data["story"]["renown"] = 0
	SaveManager.current_data["story"]["seen_chapter_intros"] = []
	SaveManager.current_data["hex"]["solved_jobs"] = {}
	# Reset hex unlocks to the starter set: the award tests assert
	# hexes_unlocked fires, which it only does for NEW unlocks — a
	# leftover save (earlier suites in this run, or a previous run's
	# persisted file) would otherwise make the unlock a no-op.
	SaveManager.current_data["hex"]["unlocked_hex_scripts"] = \
			SaveManager.DEFAULT_UNLOCKED_HEX_SCRIPTS.duplicate()
	# Tutorial dormant — its gate would otherwise block selections.
	SaveManager.current_data["story"]["has_completed_tutorial"] = true
	TutorialManager.reset()
	_cm = ChapterScript.new()
	add_child_autofree(_cm)


func after_each() -> void:
	SaveManager.current_data = _saved_data
	IdentifierPalette.set_exposed_reserved([])
	ChapterManager.reset()


func _first_job_id() -> String:
	return String(TemplateManager.get_job_ids_sorted()[0])


func test_select_job_toggles() -> void:
	var got: Array = []
	_cm.job_selection_changed.connect(func(id): got.append(id))
	var id := _first_job_id()
	_cm.select_job(id)
	assert_eq(_cm.get_selected_job_id(), id)
	_cm.select_job(id)
	assert_eq(_cm.get_selected_job_id(), "",
			"Re-selecting the pinned job must clear the selection")
	assert_eq(got, [id, ""],
			"Every selection change must emit job_selection_changed")


func test_submit_without_selection_is_a_noop() -> void:
	assert_eq(_cm.submit("6"), {},
			"Submitting with no job selected returns an empty result")


func test_submit_awards_once_and_emits_in_order() -> void:
	var order: Array = []
	_cm.job_solved.connect(func(_id): order.append("job_solved"))
	_cm.renown_changed.connect(func(_t): order.append("renown_changed"))
	_cm.hexes_unlocked.connect(func(_p): order.append("hexes_unlocked"))
	var id := _first_job_id()
	var job: Dictionary = TemplateManager.get_job(id)
	_cm.select_job(id)
	var result: Dictionary = _cm.submit("6")
	assert_true(result.get("correct", false),
			"'6' should satisfy the first job (any integer)")
	assert_true(result.get("first_time", false))
	assert_eq(int(result.get("renown_awarded", -1)), int(job.get("renown_reward", 0)))
	assert_eq(SaveManager.get_renown(), int(job.get("renown_reward", 0)))
	assert_eq(order, ["job_solved", "renown_changed", "hexes_unlocked"],
			"First-time solve must emit progression signals in order")
	# Re-solve: result stays correct but nothing is re-awarded.
	order.clear()
	var again: Dictionary = _cm.submit("7")
	assert_true(again.get("correct", false))
	assert_false(again.get("first_time", true),
			"A re-solve must not count as first_time")
	assert_eq(int(again.get("renown_awarded", -1)), 0)
	assert_eq(order, [], "Re-solves emit no progression signals")


func test_submit_never_requests_a_chapter_intro() -> void:
	# The bug this guards: solving a job used to pop the next chapter's
	# intro the moment Run succeeded. Intros may only fire from
	# select_job (or the fresh-save boot path).
	var intros: Array = []
	_cm.chapter_intro_requested.connect(func(id, _ch): intros.append(id))
	var id := _first_job_id()
	# Mark this job's own chapter seen so select_job stays quiet too.
	var own_chapter := TemplateManager.get_chapter_for_job(id)
	SaveManager.mark_chapter_intro_seen(own_chapter)
	_cm.select_job(id)
	var result: Dictionary = _cm.submit("6")
	assert_true(result.get("correct", false))
	assert_eq(intros, [],
			"Solving (and crossing the next chapter's renown gate) must not pop an intro")


func test_select_job_from_unseen_chapter_requests_intro() -> void:
	var intros: Array = []
	_cm.chapter_intro_requested.connect(func(id, _ch): intros.append(id))
	var id := _first_job_id()
	var chapter_id := TemplateManager.get_chapter_for_job(id)
	_cm.select_job(id)
	assert_eq(intros, [chapter_id],
			"First selection of an unseen chapter's job must request its intro")
	assert_true(SaveManager.has_seen_chapter_intro(chapter_id),
			"Requesting the intro marks the chapter seen")
	# Toggling off and on again: seen now, so no second request.
	_cm.select_job(id)
	_cm.select_job(id)
	assert_eq(intros, [chapter_id], "Intros are once per chapter")


func test_cycle_pending_jobs_from_unseen_chapter_requests_intro() -> void:
	# The F hotkey is just another selection surface: cycling onto a job
	# in an unseen, unlocked chapter must fire its intro like a click does.
	var intros: Array = []
	_cm.chapter_intro_requested.connect(func(id, _ch): intros.append(id))
	var first := _first_job_id()
	var chapter_id := TemplateManager.get_chapter_for_job(first)
	_cm.cycle_pending_jobs(1)
	assert_eq(_cm.get_selected_job_id(), first,
			"Cycling forward from no selection lands on the first pending job")
	assert_eq(intros, [chapter_id],
			"Cycling onto an unseen chapter's job must request its intro")


func test_chapter_unlock_gate() -> void:
	# Sequential gate: a chapter stays locked until the job right before
	# its own first job is solved — renown no longer matters.
	var ids: Array = TemplateManager.get_job_ids_sorted()
	var last_id: String = String(ids.back())
	var chapter_id := TemplateManager.get_chapter_for_job(last_id)
	var chapter: Dictionary = TemplateManager.get_chapter(chapter_id)
	SaveManager.current_data["story"]["renown"] = 9999  # high renown must NOT unlock
	assert_false(_cm.chapter_is_unlocked(chapter),
			"The final chapter must be locked until its predecessor job is solved")
	SaveManager.record_job_solved(String(ids[ids.size() - 2]), "", 0)
	assert_true(_cm.chapter_is_unlocked(chapter),
			"Solving the preceding job unlocks the final chapter")


func test_jobs_unlock_one_at_a_time() -> void:
	# The defining property of the sequential gate: at any point exactly
	# one unsolved job is available — the next one in the sequence.
	var ids: Array = TemplateManager.get_job_ids_sorted()
	assert_true(_cm.is_job_available(String(ids[0])),
			"The first job is always available")
	assert_false(_cm.is_job_available(String(ids[1])),
			"The second job is locked until the first is solved")
	SaveManager.record_job_solved(String(ids[0]), "", 0)
	assert_true(_cm.is_job_available(String(ids[1])),
			"Solving job 1 opens job 2")
	assert_false(_cm.is_job_available(String(ids[2])),
			"...but not job 3 yet")
	assert_eq(_cm.pending_job_ids(), [ids[1]],
			"Pending holds exactly the next unsolved job")


func test_notify_intro_closed_unlocks_templates_once() -> void:
	# Find a chapter that ships template unlocks.
	var target := ""
	for chapter_id in TemplateManager.get_chapter_ids():
		if not TemplateManager.get_chapter(chapter_id).get("unlocks_templates", []).is_empty():
			target = chapter_id
			break
	if target.is_empty():
		pass_test("No chapter ships template unlocks — nothing to verify")
		return
	var got: Array = []
	_cm.templates_unlocked.connect(func(names): got.append(names))
	_cm.notify_intro_closed(target)
	assert_eq(got.size(), 1, "Closing the intro should unlock its templates")
	for name in got[0]:
		assert_true(SaveManager.is_pattern_unlocked(String(name)))
	# Idempotent: a second close emits nothing.
	_cm.notify_intro_closed(target)
	assert_eq(got.size(), 1, "Re-closing must not re-emit")


func test_submit_async_completes_and_awards_on_main_thread() -> void:
	var id := _first_job_id()
	_cm.select_job(id)
	var completions: Array = []
	_cm.submit_completed.connect(func(job_id, result):
		completions.append([job_id, result, OS.get_thread_caller_id()]))
	assert_true(_cm.submit_async("6"), "submit_async must accept a valid submit")
	assert_true(_cm.is_checking())
	await wait_for_signal(_cm.submit_completed, 10)
	assert_eq(completions.size(), 1)
	assert_eq(completions[0][0], id)
	assert_eq(completions[0][2], OS.get_main_thread_id(),
			"submit_completed must be emitted on the main thread")
	assert_false(_cm.is_checking(), "worker must be joined after delivery")
	var result: Dictionary = completions[0][1]
	# job_01 expects an Int — "6" is a correct first-time solve.
	assert_true(result.get("correct", false),
			"6 should solve the first job (got: %s)" % result.get("message"))
	assert_true(result.get("first_time", false))
	assert_true(SaveManager.is_job_solved(id),
			"async submit must run the same award bookkeeping as sync submit")


func test_submit_async_rejects_double_submit() -> void:
	var id := _first_job_id()
	_cm.select_job(id)
	assert_true(_cm.submit_async("6"))
	assert_false(_cm.submit_async("6"),
			"a second submit while one is in flight must be rejected")
	await wait_for_signal(_cm.submit_completed, 10)
	assert_false(_cm.is_checking())


func test_submit_async_without_selection_returns_false() -> void:
	assert_false(_cm.submit_async("6"))
