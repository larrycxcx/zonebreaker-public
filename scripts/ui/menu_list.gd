class_name MenuList
extends Control
## 一列可以上下选的菜单项。自己画光标、自己收键，选中了就发 `chosen`。
##
## 用的是**游戏里那套输入**，不是 Godot 的 `ui_*`：上下用 `aim_up` / `aim_down`（十字键上下）、
## 确认用 `jump`（A）、返回用 `cancel`（B）。这样手柄上的手不用换位置，两个玩家也各按各的
## （`player_index` 决定听谁的，见 `Player.act()` 那套前缀规则）。

## 选中了第几项。
signal chosen(index: int)
## 按了返回。
signal cancelled
## 在这一项上按了左 / 右（`direction` 是 -1 / 1）。菜单自己不管这是什么意思，交给用它的界面
## （人物设置界面就靠它换角色、在装备格之间挪）。
signal nudged(index: int, direction: int)
## 光标移到了第几项（放音效用）。
signal moved(index: int)

const ROW_HEIGHT := 24.0
const CURSOR_GAP := 14.0

## 听第几号玩家的输入。-1 = 谁按都算（单人的暂停菜单就用这个）。
var listens_to := -1
## 光标贴在这一行的左边（加点界面那样每行左边一个），而不是紧挨着居中的文字（菜单那样）。
var cursor_at_left := false
## 现在选中第几项。
var index := 0

var _items: Array[String] = []
var _labels: Array[Label] = []
var _cursor: TextureRect


## 摆出这几项。`width` 是这一列多宽（文字居中）。
func build(items: Array[String], width: float) -> void:
	_items = items
	for child in get_children():
		child.queue_free()
	_labels.clear()
	size = Vector2(width, ROW_HEIGHT * items.size())
	for i in items.size():
		var row := UiKit.label(items[i], Rect2(0, i * ROW_HEIGHT, width, ROW_HEIGHT),
			UiKit.WHITE, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		add_child(row)
		_labels.append(row)
	_cursor = UiKit.picture(UiKit.CURSOR, Vector2.ZERO, UiKit.GOLD)
	add_child(_cursor)
	_refresh()


## 哪几项是灰的（选不动）。`disabled` 里是下标。
var greyed: Array[int] = []:
	set(value):
		greyed = value
		_refresh()


func _ready() -> void:
	# 暂停时整棵树停了，菜单自己得继续跑，不然按键没人收
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	# **要看 is_visible_in_tree()，不是 visible**：`visible` 只说自己这个节点的开关，
	# 父节点被藏起来时它照样是 true。暂停菜单没打开时整棵界面是藏着的，
	# 光看 visible 的话这里还在收键——游戏里随手按「下下 A」就会选中 QUIT 把游戏关掉。
	if _items.is_empty() or not is_visible_in_tree():
		return
	if _pressed(&"aim_up"):
		_step(-1)
	elif _pressed(&"aim_down"):
		_step(1)
	elif _pressed(&"jump"):
		if not greyed.has(index):
			GameEvents.report(&"menu_select", self)
			chosen.emit(index)
	elif _pressed(&"cancel"):
		GameEvents.report(&"menu_back", self)
		cancelled.emit()
	elif _pressed(&"move_left"):
		nudged.emit(index, -1)
	elif _pressed(&"move_right"):
		nudged.emit(index, 1)


## 这一项在哪一行（别的控件想跟着光标走时用）。
func row_top(row: int) -> float:
	return row * ROW_HEIGHT


func _step(by: int) -> void:
	var was := index
	for _try in _items.size():
		index = wrapi(index + by, 0, _items.size())
		if not greyed.has(index):
			break
	if index != was:
		_refresh()
		GameEvents.report(&"menu_move", self)
		moved.emit(index)


func _refresh() -> void:
	if _items.is_empty():
		if _cursor != null:
			_cursor.hide()
		return
	for i in _labels.size():
		var tint := UiKit.WHITE if i == index else UiKit.DIM
		if greyed.has(i):
			tint = UiKit.DIM.darkened(0.35)
		_labels[i].add_theme_color_override("font_color", tint)
	if _cursor != null:
		var left := 0.0
		if not cursor_at_left:
			var wide: float = _labels[index].get_theme_font("font").get_string_size(
				_items[index], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
			left = (size.x - wide) / 2.0 - CURSOR_GAP
		_cursor.position = Vector2(left, row_top(index) + 8.0)
		_cursor.visible = not greyed.has(index)


## 按了自己这一份的某个动作。`listens_to` 是 -1 就谁按都算。
func _pressed(action: StringName) -> bool:
	if listens_to >= 0:
		return Input.is_action_just_pressed(_named(action, listens_to))
	for index_ in Session.MAX_PLAYERS:
		if Input.is_action_just_pressed(_named(action, index_)):
			return true
	return false


func _named(action: StringName, player: int) -> StringName:
	return action if player == 0 else StringName("p%d_%s" % [player + 1, action])
