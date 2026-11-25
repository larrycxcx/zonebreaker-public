extends Node
## Sound effect player (the autoload singleton Sfx): listens to GameEvents and plays the matching sound from the current skin pack.
## The players hang under this singleton, so a sound still playing when a stage reloads (e.g. game_over) is not cut off.

## Emitted every time a sound actually plays. Tests use it to confirm "which event played which sound".
signal sound_played(event: StringName, stream: AudioStream)

## How many sounds can play at once.
const POOL_SIZE := 16
## How many copies of the same sound can play at once: when a row of bullets hits a wall together, stacking more only makes it louder.
const MAX_PER_EVENT := 3
const BUS := &"SFX"

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _warned := {}


func _ready() -> void:
	# The whole tree pauses when the ultimate fires, and sound effects must keep playing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	GameEvents.event_happened.connect(func(event: StringName, _source: Node) -> void: play(event))


func play(event: StringName) -> void:
	var stream := Skins.sound(event)
	if stream == null:
		# A skin pack may leave out some sounds (when it has no fallback); warn once and do not interrupt the game.
		if not _warned.has(event):
			_warned[event] = true
			push_warning("Sfx: current skin has no sound for event '%s'" % event)
		return
	var player := _pick_player(event)
	player.stream = stream
	player.set_meta(&"event", event)
	player.play()
	sound_played.emit(event, stream)


## Number of players currently playing a given event.
func playing_count(event: StringName) -> int:
	return _players.filter(func(p: AudioStreamPlayer) -> bool: return p.playing and p.get_meta(&"event", &"") == event).size()


## If the event already has MAX_PER_EVENT copies playing, reuse the one that has played longest; otherwise find an idle player; if all are busy, take one in turn.
func _pick_player(event: StringName) -> AudioStreamPlayer:
	var same := _players.filter(func(p: AudioStreamPlayer) -> bool: return p.playing and p.get_meta(&"event", &"") == event)
	if same.size() >= MAX_PER_EVENT:
		same.sort_custom(func(a: AudioStreamPlayer, b: AudioStreamPlayer) -> bool: return a.get_playback_position() > b.get_playback_position())
		return same[0]
	for player in _players:
		if not player.playing:
			return player
	_next = (_next + 1) % POOL_SIZE
	return _players[_next]
