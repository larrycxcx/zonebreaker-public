extends Node
## 背景音乐（autoload 单例 Music）：从当前素材包里按「用途」（`SkinPack.MUSIC_KEYS`）找曲子，走 Music 总线循环播放。
## 播放器挂在这个单例下，所以关卡重载（玩家死了重开）时音乐不会断，也不会从头再放一遍。
##
## 什么时候换曲：关卡加载时 `main.gd` 调 `play(&"level")`；Boss 出场（`boss_appear` 事件）切到 `boss`；
## 死了重开又回到 `level`。已经在放同一首就什么都不做。当前包没有这首就静音（默认包没有音乐）。

## 换曲（或停下）时发出。测试用它确认换到了哪首。
signal track_changed(key: StringName)

const BUS := &"Music"
## 音乐比音效轻一点，别盖过枪声。
const VOLUME_DB := -8.0

## 现在该放的是哪一首（用途名）；空表示没在放。
var current := &""

var _player: AudioStreamPlayer


func _ready() -> void:
	# 终极武器定格时整棵树暂停，音乐照放。
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
		# 背景音乐一律循环（MP3 / OGG 的 loop 属性）
		if &"loop" in stream:
			stream.set(&"loop", true)
		_player.play()
	track_changed.emit(key)


func stop() -> void:
	current = &""
	_player.stop()
	_player.stream = null


## 正在放的曲子（测试用），没在放返回 null。
func playing_stream() -> AudioStream:
	return _player.stream if _player.playing else null


func _on_event(event: StringName, _source: Node) -> void:
	if event == &"boss_appear":
		play(&"boss")


## 换了素材包：同一个用途重新从新包里找；曲子没变（同一个包、或者新包回落到同一首）就接着放。
func _restart() -> void:
	if current != &"":
		play(current)
