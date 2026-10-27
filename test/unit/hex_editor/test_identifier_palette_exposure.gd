extends GutTest
## Phase 19.6 — the IdentifierPalette gate for reserved `white` / `black`
## entries. The hex editor flips this on/off based on the active job's
## variables, and IdentRefHex's picker reads it to decide which dropdown
## items to disable.


var _saved_exposed: Array


func before_each() -> void:
	_saved_exposed = IdentifierPalette.get_exposed_reserved()
	IdentifierPalette.set_exposed_reserved([])


func after_each() -> void:
	IdentifierPalette.set_exposed_reserved(_saved_exposed)


func test_user_entries_are_always_pickable() -> void:
	# Red / green / blue / cyan / magenta / yellow — the leading
	# user_count() entries — must always be selectable regardless of
	# job context.
	for i in IdentifierPalette.user_count():
		assert_true(IdentifierPalette.is_pickable(i),
				"User entry %s should always be pickable" % IdentifierPalette.name_of(i))


func test_reserved_entries_default_to_locked() -> void:
	# With no job selected, white / black must not be pickable.
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		assert_false(IdentifierPalette.is_pickable(i),
				"Reserved entry %s should be locked by default" % IdentifierPalette.name_of(i))


func test_exposing_white_only_keeps_black_locked() -> void:
	IdentifierPalette.set_exposed_reserved(["white"])
	var white_idx := -1
	var black_idx := -1
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		match IdentifierPalette.name_of(i):
			"white": white_idx = i
			"black": black_idx = i
	assert_true(IdentifierPalette.is_pickable(white_idx))
	assert_false(IdentifierPalette.is_pickable(black_idx))


func test_exposing_both_unlocks_both() -> void:
	IdentifierPalette.set_exposed_reserved(["white", "black"])
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		assert_true(IdentifierPalette.is_pickable(i),
				"Both reserved entries should unlock when both names are exposed")


func test_set_exposed_reserved_ignores_non_reserved_names() -> void:
	# Calling with `red` (a user entry) should not silently demote
	# anything; the user entries are always pickable, and reserved
	# stays locked.
	IdentifierPalette.set_exposed_reserved(["red", "green"])
	assert_eq(IdentifierPalette.get_exposed_reserved(), [],
			"Non-reserved names must be filtered out of the exposure list")
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		assert_false(IdentifierPalette.is_pickable(i))


func test_clearing_exposure_relocks() -> void:
	IdentifierPalette.set_exposed_reserved(["white", "black"])
	IdentifierPalette.set_exposed_reserved([])
	for i in range(IdentifierPalette.user_count(), IdentifierPalette.count()):
		assert_false(IdentifierPalette.is_pickable(i),
				"Clearing the exposure list must re-lock reserved entries")
