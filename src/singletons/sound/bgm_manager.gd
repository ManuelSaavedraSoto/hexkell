extends Node
## Background music. A single looping track that plays from game start.
## Exposes play / stop / volume plus a fade helper for future settings or
## menu transitions. Mirrors SfxManager's shape, but uses a single
## (non-polyphonic) AudioStreamPlayer since music never overlaps itself.

const TRACK := preload("res://assets/audio/bgm/Warmth.ogg")
const DEFAULT_VOLUME_DB := -24.0
const PAUSE_VOLUME_DB := -32.0

var player: AudioStreamPlayer


func _ready() -> void:
	# Keep playing (and keep the fade tween advancing) while the tree is paused,
	# so pausing ducks the music instead of hard-cutting it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	var stream := TRACK
	# The .ogg imports with loop=false; loop it at runtime so the single
	# track plays continuously without touching the import settings.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	player.stream = stream
	player.volume_db = DEFAULT_VOLUME_DB
	add_child(player)
	player.play()


func play() -> void:
	if player and not player.playing:
		player.play()


func stop() -> void:
	if player:
		player.stop()


func set_volume_db(db: float) -> void:
	if player:
		player.volume_db = db


## Duck the music down while paused, fade it back up on resume.
func set_paused(paused: bool) -> void:
	fade_to(PAUSE_VOLUME_DB if paused else DEFAULT_VOLUME_DB)


## Smoothly ramp the volume (e.g. duck under a menu, or fade back in).
func fade_to(db: float, secs: float = 0.5) -> void:
	if player == null:
		return
	create_tween().tween_property(player, "volume_db", db, secs)
