extends Node
## 这一局的设置（autoload 单例 Session）：几个人玩。以后主菜单在这里设，关卡按它生成玩家。
##
## 输入：1 号玩家的动作名就是 `move_left`、`shoot`……，2 号是 `p2_move_left`、`p2_shoot`……（见 `Player.act()`）。
## 手柄分开：一个座位一只手柄。**哪只手柄是几号，由玩家在标题页按下的那一下决定**（`claim_pads()`），
## 不是写死 device 0 / 1——Godot 的 device 号是按插入顺序给的，玩家手里的「1 号手柄」
## 完全可能是 device 1（前一个槽被没拔干净的幽灵设备占着是常事）。
## 键盘：方向键在单人时是 1 号的备用键；**双人时让给 2 号**（2 号用方向键移动 / 瞄准，
## `.` 跳、`/` 开火、`,` 趴下、`L` 奔跑、`;` 换武器、`'` 终极武器），切回单人时再还给 1 号。

const MAX_PLAYERS := 2
## 双人时从 1 号的动作里拿掉、让给 2 号的键。
const SHARED_KEYS: Array[int] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var player_count := 1

## **最后一只按过键的手柄**的 device 号，-1 = 还没有（或者刚按的是键盘）。
## 标题页用它决定「谁是 1 号」。
var last_pad := -1

## 借给 2 号的键（动作 → 事件），切回单人时还回去。
var _lent := {}
## 每个座位现在绑的是哪只手柄。默认就是 `project.godot` 里配的那样（座位 N ↔ device N）。
var _pads: Array[int] = [0, 1]
## **故意绑了不止一只手柄的动作**（动作名 → 拿来复制的那个手柄事件）：
## `pause` 就是这种——两个玩家都能暂停，所以它上面有两只手柄的 Start。
## 按座位重绑会把它压成一只手柄（认领之后只剩一个人能暂停），
## 所以每次重绑之后都由 `_spread_shared()` 把它重新铺到每只手柄上。
## **要在任何重绑之前算出来**，不然重绑完就看不出它原来是共用的了。
var _shared: Dictionary = {}


func _ready() -> void:
	_find_shared_actions()
	set_player_count(int(ProjectSettings.get_setting("game/player_count", 1)))


## 记下最后按键的是哪只手柄。摇杆要推过死区才算——松手回弹那一下也会发事件。
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		last_pad = event.device
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			last_pad = event.device


# ---------------------------------------------------------------- 哪只手柄是几号

## **按下这一下的那只手柄就是 1 号**，其余连着的按顺序往后排。
## 在标题页（选完几个人玩）调一次。`first` 是 -1（刚才按的是键盘）就什么都不动。
##
## 为什么要有这个：Godot 的 device 号是**按插入顺序**给的，和玩家心里的「1 号手柄」没关系。
## 写死「座位 0 ↔ device 0」的话，玩家手里那只如果是 device 1，
## 他在标题页（谁按都算）一切正常，一到写着 PLAYER 1 的那页就按不动了，
## 另一只手柄反而能动——2026-09 试玩报的就是这个。
func claim_pads(first: int) -> void:
	if first < 0:
		return
	# **两个座位不能共用一只手柄**：认领的这只本来是别的座位的，就和它对换。
	# 不换的话，只插了一只手柄又选了双人时，两个座位会同时听同一只——一个人动，两个角色都动。
	var was: int = _pads[0]
	for seat in range(1, MAX_PLAYERS):
		if _pads[seat] == first:
			_bind_pad(seat, was)
	_bind_pad(0, first)
	var others: Array = Input.get_connected_joypads().filter(
		func(device: int) -> bool: return device != first)
	for seat in range(1, MAX_PLAYERS):
		if others.size() >= seat:
			_bind_pad(seat, others[seat - 1])
	_spread_shared()


## 这个座位现在绑的是哪只手柄（测试用）。
func pad_of(seat: int) -> int:
	return _pads[seat] if seat >= 0 and seat < _pads.size() else -1


## 回到 `project.godot` 里配的那样（座位 N ↔ device N）。
## **InputMap 是全局状态**，测试每条用例都要还原，不然认领过的那一下会带进后面的用例。
func reset_pads() -> void:
	last_pad = -1
	for seat in MAX_PLAYERS:
		_bind_pad(seat, seat)
	_spread_shared()


## 把这个座位所有动作上的**手柄事件**改成这只手柄。键盘那几个事件一个都不碰。
func _bind_pad(seat: int, device: int) -> void:
	if device < 0:
		return
	_pads[seat] = device
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_"):
			continue
		if name.begins_with("p2_") != (seat == 1):
			continue
		for event in InputMap.action_get_events(action):
			if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			# **erase 之后换一份新的再 add**：直接改拿出来那一份的 `device`，
			# InputMap 内部按设备分的索引不会跟着更新。
			InputMap.action_erase_event(action, event)
			var moved := event.duplicate()
			moved.device = device
			InputMap.action_add_event(action, moved)


## 哪些动作本来就绑了不止一只手柄。**只在启动时算一次**。
func _find_shared_actions() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var devices := {}
		var sample: InputEvent = null
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				devices[event.device] = true
				if sample == null:
					sample = event
		if devices.size() > 1:
			_shared[action] = sample


## 把共用的动作铺到**每个座位现在那只手柄**上，一只一份。
func _spread_shared() -> void:
	for action: StringName in _shared:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		for device in _pads:
			var copy: InputEvent = (_shared[action] as InputEvent).duplicate()
			copy.device = device
			InputMap.action_add_event(action, copy)


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
