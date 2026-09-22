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
