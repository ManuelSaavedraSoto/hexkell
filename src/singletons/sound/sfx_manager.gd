extends Node
## SFX manager
##
## Plays one-shot sound effects during gameplay. Registered as the
## `SfxManager` autoload, so any script can fire a cue with
## `SfxManager.play("place")`.
##
## Sounds are keyed by name in `SOUND_LIB`. A `null` (or unsupplied) stream
## is a silent no-op, so a call site can be wired before its audio file
## lands (drop the file in `res://assets/audio/sfx/` and add the preload).
##
## Playback rides an `AudioStreamPolyphonic`, so distinct cues can overlap
## without one cutting another off.

## The editing cues (place / connect / delete / pickup / rotate) are left
## unsupplied in the open-source version: the original sounds are licensed
## for use in builds only and can't be redistributed as raw files.
const SOUND_LIB: Dictionary[String, AudioStream] = {
	"place": null,
	"connect": null,
	"delete": null,
	"pickup": null,
	"rotate": null,
	"error": preload("res://assets/audio/sfx/error_006.ogg"),
	"success": preload("res://assets/audio/sfx/confirmation_004.ogg"),
}

var player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.set_max_polyphony(3)
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 3
	player.stream = poly
	add_child(player)
	player.volume_db = -8.0
	player.play()
	_playback = player.get_stream_playback() as AudioStreamPlaybackPolyphonic


## Play the sound effect registered under `name`. Unknown keys, keys whose
## stream isn't supplied yet, or a missing playback all no-op safely.
func play(name: String) -> void:
	var stream: AudioStream = SOUND_LIB.get(name)
	if stream == null or _playback == null:
		return
	_playback.play_stream(stream)
