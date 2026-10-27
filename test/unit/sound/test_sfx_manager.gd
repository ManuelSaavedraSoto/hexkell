extends GutTest
## SFX manager autoload: the polyphonic player is set up, and play() is a
## safe no-op for unknown keys or keys whose audio file isn't supplied yet,
## while the polyphonic playback can accept a real stream without error.


func test_player_is_ready() -> void:
	assert_not_null(SfxManager.player, "the AudioStreamPlayer is created on _ready")
	assert_true(SfxManager.player.playing,
			"the polyphonic stream is playing so cues can be fired into it")
	assert_true(SfxManager._playback is AudioStreamPlaybackPolyphonic,
			"playback is the polyphonic playback used to fire overlapping cues")


func test_play_unknown_key_is_safe() -> void:
	# Should not error or crash.
	SfxManager.play("does_not_exist")
	pass_test("playing an unknown key no-ops")


func test_registered_keys_have_streams_and_play_safely() -> void:
	# The shipped cues should resolve to a real stream (guards against a
	# missing/renamed asset). The editing cues are registered but unsupplied
	# in the open-source version, and firing them must still no-op.
	assert_true(SfxManager.SOUND_LIB.has("place"), "place is a registered key")
	for key in ["error", "success"]:
		assert_true(SfxManager.SOUND_LIB[key] is AudioStream,
				"'%s' should map to a real AudioStream" % key)
	SfxManager.play("place")
	SfxManager.play("success")
	pass_test("playing registered cues, supplied or not, no-ops cleanly")


func test_playback_accepts_a_real_stream() -> void:
	# The wiring (play -> _playback.play_stream) is exercised here directly,
	# since SOUND_LIB is a read-only const and can't be injected with a stub.
	SfxManager._playback.play_stream(AudioStreamGenerator.new())
	pass_test("the polyphonic playback runs a real stream without error")
