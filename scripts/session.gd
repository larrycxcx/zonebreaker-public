extends Node
## 这一局的设置（autoload 单例 Session）：几个人玩。以后主菜单在这里设，关卡按它生成玩家。
##
## 输入：1 号玩家的动作名就是 `move_left`、`shoot`……，2 号是 `p2_move_left`、`p2_shoot`……（见 `Player.act()`）。
## 手柄分开：1 号手柄（device 0）只控制 1 号，2 号手柄（device 1）只控制 2 号。
## 键盘：方向键在单人时是 1 号的备用键；**双人时让给 2 号**（2 号用方向键移动 / 瞄准，
## `.` 跳、`/` 开火、`,` 趴下、`L` 奔跑、`;` 换武器、`'` 终极武器），切回单人时再还给 1 号。

const MAX_PLAYERS := 2
## 双人时从 1 号的动作里拿掉、让给 2 号的键。
const SHARED_KEYS: Array[int] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var player_count := 1

## 借给 2 号的键（动作 → 事件），切回单人时还回去。
var _lent := {}


func _ready() -> void:
	set_player_count(int(ProjectSettings.get_setting("game/player_count", 1)))


func set_player_count(count: int) -> void:
	player_count = clampi(count, 1, MAX_PLAYERS)
	if player_count >= 2:
		_lend_shared_keys()
	else:
		_take_back_shared_keys()


# ---------------------------------------------------------------- 界面收键

## 这个座位的这个动作，**这一帧刚被按下**吗。界面（`MenuList`、`ShopColumn`）收键一律走它。
##
## **单人时谁按都算**：按设备分开是为了让双人各按各的，一个人玩没有要分开的对象。
## 不这么做的话，同一套键在菜单前几页能用、到人物设置和商店（第一个按玩家过滤输入的页面）
## 就突然失灵——手柄插在第二个槽位上（前一个槽被没拔干净的幽灵设备占着是常事）整页全死，
## 键盘上的 ↑ 也会从「上移」变成「确认」（单人时 ↑ 是 1 号的跳跃、同时是 2 号的「上」）。
func just_pressed(action: StringName, seat: int) -> bool:
	if seat >= 0 and player_count >= 2:
		return _pressed(action_for(action, seat))
	for index in MAX_PLAYERS:
		if _pressed(action_for(action, index)):
			return true
	return false


## 第几号玩家的那份动作叫什么（1 号不带前缀）。
func action_for(action: StringName, seat: int) -> StringName:
	return action if seat <= 0 else StringName("p%d_%s" % [seat + 1, action])


## **没有这个动作就当没按**：问引擎一个不存在的动作它会报错，而且是每帧报一次。
## 界面上的动作不是每个玩家都配齐了（以后加第三个座位更是如此）。
func _pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _lend_shared_keys() -> void:
	if not _lent.is_empty():
		return
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_") or name.begins_with("p2_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and SHARED_KEYS.has((event as InputEventKey).physical_keycode):
				InputMap.action_erase_event(action, event)
				if not _lent.has(action):
					_lent[action] = []
				_lent[action].append(event)


func _take_back_shared_keys() -> void:
	for action: StringName in _lent:
		for event: InputEvent in _lent[action]:
			InputMap.action_add_event(action, event)
	_lent.clear()
