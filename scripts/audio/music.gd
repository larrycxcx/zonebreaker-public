extends Node
## Background music (the autoload singleton Music): finds a track in the current skin pack by "purpose" (`SkinPack.MUSIC_KEYS`) and loops it on the Music bus.
## The player hangs under this singleton, so reloading a stage (restarting after dying) does not cut the music or start it over.
##
## When the track changes: on stage load `main.gd` calls `play(&"level")`; a boss appearing (`boss_appear` event) switches to `boss`;
## restarting after dying goes back to `level`. If the same track is already playing nothing happens. If the current pack lacks the track it goes silent (the default pack has no music).

## Emitted on changing (or stopping) the track. Tests use it to confirm which track it switched to.
signal track_changed(key: StringName)

const BUS := &"Music"
## Music a little quieter than the sound effects, so it does not drown out the gunfire.
const VOLUME_DB := -8.0

## Which track should be playing now (purpose name); empty means nothing is playing.
var current := &""

var _player: AudioStreamPlayer


func _ready() -> void:
	# When the ultimate freezes things the whole tree pauses, but the music keeps playing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = VOLUME_DB
	add_child(_player)
	GameEvents.event_happened.connect(_on_event)
	Skins.skin_changed.connect(func(_skin: SkinPack) -> void: _restart())


func play(key: StringName) -> void:
	var stream := Skins.music(key)
	if key == current and _player.stream == stream and (_player.playing or stream == null):
		return
	current = key
	_player.stop()
	_player.stream = stream
	if stream != null:
		# Background music always loops (the loop property of MP3 / OGG)
		if &"loop" in stream:
			stream.set(&"loop", true)
		_player.play()
	track_changed.emit(key)


func stop() -> void:
	current = &""
	_player.stop()
	_player.stream = null


## The track playing now (for tests), null if nothing is playing.
func playing_stream() -> AudioStream:
	return _player.stream if _player.playing else null


func _on_event(event: StringName, _source: Node) -> void:
	if event == &"boss_appear":
		play(&"boss")


## The skin pack changed: look the same purpose up again in the new pack; if the track is the same (same pack, or the new pack falls back to the same track) it keeps playing.
func _restart() -> void:
	if current != &"":
		play(current)
