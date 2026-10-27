extends GutTest
## BGM manager autoload: the single looping track is wired into an
## AudioStreamPlayer on _ready, loops, and play()/stop() are safe.


func test_player_is_ready_and_playing() -> void:
	assert_not_null(BgmManager.player, "the AudioStreamPlayer is created on _ready")
	assert_eq(BgmManager.player.stream, BgmManager.TRACK,
			"the player carries the single BGM track")


func test_track_loops() -> void:
	assert_true(BgmManager.TRACK is AudioStreamOggVorbis,
			"the BGM track is an Ogg stream")
	assert_true(BgmManager.TRACK.loop,
			"the track loops so the single track plays continuously")


func test_stop_and_play_are_safe() -> void:
	BgmManager.stop()
	assert_false(BgmManager.player.playing, "stop() halts playback")
	BgmManager.play()
	assert_true(BgmManager.player.playing, "play() resumes playback")


func test_runs_during_pause() -> void:
	assert_eq(BgmManager.process_mode, Node.PROCESS_MODE_ALWAYS,
			"the BGM keeps playing (and fading) while the tree is paused")


func test_pause_ducks_then_restores_volume() -> void:
	BgmManager.set_paused(true)
	await wait_seconds(0.7)
	assert_almost_eq(BgmManager.player.volume_db, BgmManager.PAUSE_VOLUME_DB, 0.5,
			"pausing fades the music down to the duck volume")
	BgmManager.set_paused(false)
	await wait_seconds(0.7)
	assert_almost_eq(BgmManager.player.volume_db, BgmManager.DEFAULT_VOLUME_DB, 0.5,
			"resuming fades the music back up")
