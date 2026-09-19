extends Node
## 音效播放器（autoload 单例 Sfx）：监听 GameEvents，到当前素材包里找对应的声音播放。
## 播放器挂在这个单例下，所以关卡重载时正在播的声音（比如 game_over）不会被截断。

## 每次真的播放一个声音时发出。测试用它确认「哪个事件播了哪个声音」。
signal sound_played(event: StringName, stream: AudioStream)

## 同时最多有几个声音在响。
const POOL_SIZE := 16
## 同一种声音最多同时响几个：一排子弹同时打墙时，再多叠加只会更吵。
const MAX_PER_EVENT := 3
const BUS := &"SFX"

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _warned := {}


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	GameEvents.event_happened.connect(func(event: StringName, _source: Node) -> void: play(event))


func play(event: StringName) -> void:
	var stream := Skins.sound(event)
	if stream == null:
		# 素材包可以不提供某些声音（没有备用包时），只提醒一次，不中断游戏。
		if not _warned.has(event):
			_warned[event] = true
			push_warning("Sfx: current skin has no sound for event '%s'" % event)
		return
	var player := _pick_player(event)
	player.stream = stream
	player.set_meta(&"event", event)
	player.play()
	sound_played.emit(event, stream)


## 正在播放某个事件的播放器数量。
func playing_count(event: StringName) -> int:
	return _players.filter(func(p: AudioStreamPlayer) -> bool: return p.playing and p.get_meta(&"event", &"") == event).size()


## 同一事件已经响满 MAX_PER_EVENT 个就复用其中播得最久的；否则找空闲的；都忙就按顺序抢一个。
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
