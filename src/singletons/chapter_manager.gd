extends Node
## Chapter & job progression director. Owns job selection, solve/award
## bookkeeping, chapter unlock checks and intro scheduling — the pure
## logic extracted from hex_editor.gd. The editor (and any other UI)
## listens to the declared signals below and renders; nothing in here
## touches a scene node.
##
## Chapter intros surface in exactly two ways:
##   • the fresh-save boot path (`maybe_show_next_chapter_intro`)
##   • selecting a job from an unseen, unlocked chapter (`select_job`)
## Solving a job never pops an intro — the player meets a new chapter
## when they commit to one of its jobs, not mid-celebration.

signal job_selection_changed(id: String)            # "" = deselected
signal job_solved(job_id: String)                   # first-time solves only
signal renown_changed(total: int)
signal hexes_unlocked(paths: Array)
signal chapter_intro_requested(chapter_id: String, chapter: Dictionary)
signal templates_unlocked(names: Array)
## Async submit finished (or timed out). `result` is the same annotated
## dict `submit()` returns, plus `timed_out: true` when the watchdog
## tripped. Always emitted on the main thread.
signal submit_completed(job_id: String, result: Dictionary)

## Watchdog for background checks. The interpreter's step budgets make
## runaway evaluations terminate on their own (~4 s worst case); the
## watchdog is the belt-and-braces layer that keeps the UI honest if
## something slips past them.
const CHECK_TIMEOUT_SEC := 10.0

var _selected_job_id: String = ""

# One background check at a time. `_check_ticket` is a generation
# counter: a timed-out check bumps it, so the eventual late delivery
# from the worker recognises itself as stale and gets discarded.
var _check_thread: Thread = null
var _check_ticket: int = 0
# Threads abandoned by the watchdog. Destroying a still-running Thread
# is an error, so the reference must be kept — this leaks one zombie
# thread per timeout by design (unreachable in practice: the
# interpreter's fuel limits terminate every evaluation).
var _abandoned_threads: Array[Thread] = []


func _ready() -> void:
	# Warm the lazy Prelude.std_lib static initializer on the main
	# thread so a background check thread never runs it first.
	var _warm := Prelude.std_lib


# ── Selection ───────────────────────────────────────────────────────────────

func get_selected_job_id() -> String:
	return _selected_job_id


func get_selected_job() -> Dictionary:
	if _selected_job_id.is_empty():
		return {}
	return TemplateManager.get_job(_selected_job_id)


## Toggle-select a job: picking the current selection clears it.
## Selecting a job from a chapter the player hasn't been introduced to
## yet requests that chapter's intro — the main entry point for intros.
func select_job(id: String) -> void:
	# Tutorial gate: before the "select the job" step only the tutorial
	# job is clickable; afterwards the selection is pinned.
	if not TutorialManager.allows_job(id):
		return
	if _selected_job_id == id:
		_selected_job_id = ""
	else:
		_selected_job_id = id
	apply_job_context()
	_maybe_request_chapter_intro()
	job_selection_changed.emit(_selected_job_id)


## Step through the pending jobs (available + unsolved, in
## `TemplateManager.get_job_ids_sorted` order). `direction` is +1 for
## the F hotkey, -1 for Shift+F. The cycle includes an explicit
## "no job selected" sentinel slot, so one step past the last pending
## job clears the selection — that's how the player gets back to free-
## run mode without reaching for the panel.
func cycle_pending_jobs(direction: int) -> void:
	var pending: Array = pending_job_ids()
	if pending.is_empty():
		# Nothing to cycle. If a stale selection somehow lingers (a job
		# the player just solved, for instance), clear it.
		if not _selected_job_id.is_empty() and TutorialManager.allows_job(""):
			_selected_job_id = ""
			apply_job_context()
			job_selection_changed.emit(_selected_job_id)
		return
	# Slot layout: [empty, id_0, id_1, …]. The empty slot is index 0.
	var cur: int = 0
	if not _selected_job_id.is_empty():
		var found := pending.find(_selected_job_id)
		if found >= 0:
			cur = found + 1
		# A selection that's no longer pending (just-solved, or renown
		# requirements changed) falls through with cur=0 — the cycle
		# starts from "empty" toward the first pending id.
	var slots: int = pending.size() + 1
	var next: int = posmod(cur + direction, slots)
	var next_id: String = "" if next == 0 else String(pending[next - 1])
	# Same tutorial gate as select_job — the hotkey is just another
	# selection surface.
	if not TutorialManager.allows_job(next_id):
		return
	_selected_job_id = next_id
	apply_job_context()
	_maybe_request_chapter_intro()
	job_selection_changed.emit(_selected_job_id)


## Fire the selected job's chapter intro the first time the player
## reaches an unlocked chapter they haven't been introduced to. Shared
## by every selection surface (panel click + F/Shift+F cycle) so they
## can't drift. `request_chapter_intro` already guards has-seen and
## marks it seen, so this is idempotent.
func _maybe_request_chapter_intro() -> void:
	if _selected_job_id.is_empty():
		return
	var chapter_id: String = TemplateManager.get_chapter_for_job(_selected_job_id)
	if (
		not chapter_id.is_empty()
		and not SaveManager.has_seen_chapter_intro(chapter_id)
		and chapter_is_unlocked(TemplateManager.get_chapter(chapter_id))
	):
		request_chapter_intro(chapter_id)


## Pending = available (predecessor solved) and not yet solved. Mirrors
## the bucket logic in the jobs panel so the F hotkey advances through
## exactly the cards the panel renders under "Pending".
func pending_job_ids() -> Array:
	var pending: Array = []
	for id in TemplateManager.get_job_ids_sorted():
		if SaveManager.is_job_solved(id):
			continue
		if is_job_available(id):
			pending.append(id)
	return pending


## Sequential unlock gate. A job becomes available once the job right
## before it — in the canonical renown-ordered sequence
## (`get_job_ids_sorted`) — has been solved. Renown is still tracked and
## awarded as a score, but it no longer gates anything: the player simply
## clears jobs in order. Archmage opens everything at once.
func is_job_available(job_id: String) -> bool:
	if SaveManager.is_archmage():
		return true
	var ids: Array = TemplateManager.get_job_ids_sorted()
	var idx: int = ids.find(job_id)
	if idx < 0:
		return false
	if idx == 0:
		return true
	return SaveManager.is_job_solved(String(ids[idx - 1]))


## Push the currently-selected job's reserved-parameter exposure into
## the global IdentifierPalette gate. White / black are the reserved
## parameter slots: a job that injects `white` exposes it; one that
## also injects `black` exposes both. Other variable names ride
## through the prelude env unchanged.
func apply_job_context() -> void:
	var exposed: Array = []
	if not _selected_job_id.is_empty():
		var job: Dictionary = TemplateManager.get_job(_selected_job_id)
		var variables: Dictionary = job.get("variables", {})
		if variables.has("white"):
			exposed.append("white")
		if variables.has("black"):
			exposed.append("black")
	IdentifierPalette.set_exposed_reserved(exposed)


# ── Submission ──────────────────────────────────────────────────────────────

## Check `code` against the selected job. The editor builds + validates
## the program text and renders the returned result; this owns the
## Checker call and ALL solve bookkeeping. The result dict is the
## Checker's, augmented with:
##   first_time:     bool  — this submit recorded a brand-new solve
##   renown_awarded: int   — renown granted (0 on re-solves)
##   unlocked_hexes: Array — script paths newly unlocked by this solve
func submit(code: String) -> Dictionary:
	if _selected_job_id.is_empty():
		return {}
	var job: Dictionary = TemplateManager.get_job(_selected_job_id)
	if job.is_empty():
		return {}
	var result: Dictionary = Checker.check_answer(job, code)
	_finish_submit(_selected_job_id, job, code, result)
	return result


## Background variant of `submit`: runs the Checker on a worker thread
## and emits `submit_completed(job_id, result)` on the main thread when
## done. Returns false (and does nothing) when no job is selected or a
## check is already in flight — the authoritative double-submit guard.
##
## Thread-safety: the worker runs only the pure static
## `Checker.check_answer` on a deep copy of the job. The shared
## `Prelude.std_lib` env is never mutated after init (lookup caches
## land on the per-check frames, not the terminal std frame), and all
## solve bookkeeping (`_finish_submit` — SaveManager writes,
## progression signals) happens back on the main thread via
## call_deferred.
func submit_async(code: String) -> bool:
	if _selected_job_id.is_empty() or _check_thread != null:
		return false
	var job: Dictionary = TemplateManager.get_job(_selected_job_id)
	if job.is_empty():
		return false
	_check_ticket += 1
	var ticket := _check_ticket
	var job_id := _selected_job_id
	var job_copy: Dictionary = job.duplicate(true)
	_check_thread = Thread.new()
	# NOTE: never emit signals from the worker — emission would run
	# handlers on the worker thread. call_deferred is the only exit.
	_check_thread.start(func() -> void:
		var result: Dictionary = Checker.check_answer(job_copy, code)
		_deliver_check_result.call_deferred(ticket, job_id, job_copy, code, result)
	)
	get_tree().create_timer(CHECK_TIMEOUT_SEC).timeout.connect(
			_on_check_timeout.bind(ticket, job_id))
	return true


func is_checking() -> bool:
	return _check_thread != null


# Main-thread landing point for the worker's result (via call_deferred).
func _deliver_check_result(ticket: int, job_id: String, job: Dictionary,
		code: String, result: Dictionary) -> void:
	if ticket != _check_ticket:
		# The watchdog already reported this check as timed out. Join
		# the zombie (it has finished — delivering was its last act)
		# and discard the result WITHOUT awarding: granting a solve
		# after the player saw "aborted" would be confusing, and
		# re-submitting costs nothing.
		for t in _abandoned_threads:
			if not t.is_alive():
				t.wait_to_finish()
				_abandoned_threads.erase(t)
				break
		return
	_check_thread.wait_to_finish()
	_check_thread = null
	_finish_submit(job_id, job, code, result)
	submit_completed.emit(job_id, result)


func _on_check_timeout(ticket: int, job_id: String) -> void:
	if ticket != _check_ticket or _check_thread == null:
		return  # delivered already (or superseded) — nothing to do
	_check_ticket += 1  # invalidates the in-flight delivery
	_abandoned_threads.append(_check_thread)
	_check_thread = null
	submit_completed.emit(job_id, {
		"timed_out": true,
		"correct": false,
		"passed_tests": 0,
		"total_tests": 0,
		"results": [],
		"message": "Check aborted after %d s — the program took too long to evaluate." % int(CHECK_TIMEOUT_SEC),
		"first_time": false,
		"renown_awarded": 0,
		"unlocked_hexes": [],
	})


# Shared submit tail: annotate the Checker result and run all solve
# bookkeeping. Main thread only — SaveManager writes and progression
# signals must never run on a worker.
func _finish_submit(job_id: String, job: Dictionary, code: String, result: Dictionary) -> void:
	result["first_time"] = false
	result["renown_awarded"] = 0
	result["unlocked_hexes"] = []
	if result.get("correct", false):
		_award_job_solved(job_id, job, code, result)


# Record a solve. First-time solves grant renown + hex unlocks and
# emit the progression signals; re-solves only refresh the stored
# submission. Deliberately does NOT pop the next chapter's intro —
# that fires from select_job when the player commits to the chapter.
func _award_job_solved(job_id: String, job: Dictionary, code: String, result: Dictionary) -> void:
	var reward: int = int(job.get("renown_reward", 0))
	var first_time := SaveManager.record_job_solved(job_id, code, reward)
	result["first_time"] = first_time
	if not first_time:
		return
	if reward > 0:
		SaveManager.add_renown(reward)
		result["renown_awarded"] = reward
	var unlocked_paths: Array = []
	for entry in job.get("unlocks_hexes", []):
		var path := StaticData.hex_path(String(entry))
		if path != "" and SaveManager.unlock_hex(path):
			unlocked_paths.append(path)
	result["unlocked_hexes"] = unlocked_paths
	job_solved.emit(job_id)
	if reward > 0:
		renown_changed.emit(SaveManager.get_renown())
	if not unlocked_paths.is_empty():
		hexes_unlocked.emit(unlocked_paths)


# ── Chapters ────────────────────────────────────────────────────────────────

## A chapter is unlocked once any of its jobs is reachable — already
## solved, or available because the job before it in the sequence is
## solved. Chapters with no jobs (pure-reference chapters) count as
## unlocked so their intro still fires.
func chapter_is_unlocked(chapter: Dictionary) -> bool:
	var job_ids: Array = chapter.get("jobs", [])
	if job_ids.is_empty():
		return true
	for job_id in job_ids:
		var jid := String(job_id)
		if SaveManager.is_job_solved(jid) or is_job_available(jid):
			return true
	return false


## Fresh-save boot path: surface the first unlocked-but-unseen chapter
## (chapter 0 on a brand-new save). One intro at a time.
func maybe_show_next_chapter_intro() -> void:
	for chapter_id in TemplateManager.get_chapter_ids():
		if SaveManager.has_seen_chapter_intro(chapter_id):
			continue
		if not chapter_is_unlocked(TemplateManager.get_chapter(chapter_id)):
			continue
		request_chapter_intro(chapter_id)
		return


## Mark the chapter seen and ask the UI (whoever owns the intro dialog)
## to display it.
func request_chapter_intro(chapter_id: String) -> void:
	var chapter: Dictionary = TemplateManager.get_chapter(chapter_id)
	if chapter.is_empty():
		return
	if SaveManager.has_seen_chapter_intro(chapter_id):
		return
	SaveManager.mark_chapter_intro_seen(chapter_id)
	chapter_intro_requested.emit(chapter_id, chapter)


## Called by the dialog owner when the intro closes: unlock the
## chapter's templates (idempotent) and announce any new ones.
func notify_intro_closed(chapter_id: String) -> void:
	var chapter: Dictionary = TemplateManager.get_chapter(chapter_id)
	if chapter.is_empty():
		return
	var unlocked: Array = []
	for template_name in chapter.get("unlocks_templates", []):
		if not SaveManager.is_pattern_unlocked(template_name):
			SaveManager.unlock_pattern(template_name)
			unlocked.append(template_name)
	if not unlocked.is_empty():
		templates_unlocked.emit(unlocked)


# Test / save-deletion hook: drop selection state and re-sync the
# identifier exposure gate.
func reset() -> void:
	_selected_job_id = ""
	apply_job_context()
