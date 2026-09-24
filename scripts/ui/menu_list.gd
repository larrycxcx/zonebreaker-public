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
## 选中框比里面那几个字宽出多少。
const PADDING := 6.0

## 听第几号玩家的输入。-1 = 谁按都算（单人的暂停菜单就用这个）。
var listens_to := -1
## 一屏最多显示几行（0 = 有几项显示几项）。项数超过这个数时上下走会**滚动**：
## 行数不变，换的是行里显示的是第几项（存档列表那种会越攒越多的清单用它）。
var window_rows := 0
## 选中框画多宽：整行（加点界面、存档列表那样）还是只框住那几个字（菜单那样）。
var wide_highlight := false
## 每一行的选中框画在哪（这个菜单自己的坐标系）。留空就按行高自己算。
## 人物设置界面那种「一行一块内容、每块大小位置都不一样」的界面才需要填它。
## **是个 setter**：`build()` 里已经摆过一次框了，后填的框得让它重画一遍。
var row_boxes: Array[Rect2] = []:
	set(value):
		row_boxes = value
		_refresh()
## 现在选中第几项。**是个 setter**：直接赋值（`SetupColumn.go_to_row()`、测试里跳行）也要把选中框挪过去，
## 不然框会留在上一行上——按键走的那条路是 `_step()`，赋值这条路以前没人管。
var index := 0:
	set(value):
		index = value
		_refresh()

var _items: Array[String] = []
var _labels: Array[Label] = []
var _cursor: OutlineBox
## 第一行现在显示的是第几项（滚动到哪儿了）。
var _top := 0
## 换上这批项是第几个物理帧。**摆好的那一帧不收键**：上一页就是用这一下按键退出来的，
## 同一帧这一页不该再吃一次（一下 B 连退两页、一下 A 连选两层）。
var _built_frame := -1


## 摆出这几项。`width` 是这一列多宽（文字居中）。
func build(items: Array[String], width: float) -> void:
	_items = items
	_built_frame = Engine.get_physics_frames()
	for child in get_children():
		child.queue_free()
	_labels.clear()
	# 换了一批项就从头选起：不清的话从标题页的第 2 项过来，下一页也停在第 2 项上
	_top = 0
	index = 0
	var shown := rows_shown()
	size = Vector2(width, ROW_HEIGHT * shown)
	for i in shown:
		var row := UiKit.label(items[i], Rect2(0, i * ROW_HEIGHT, width, ROW_HEIGHT),
			UiKit.WHITE, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		add_child(row)
		_labels.append(row)
	_cursor = OutlineBox.new()
	add_child(_cursor)
	_refresh()


## 哪几项是灰的（选不动）。`disabled` 里是下标。
var greyed: Array[int] = []:
	set(value):
		greyed = value
		# 光标正停在一个选不动的项上就挪开：不挪的话框会整个藏起来，
		# 界面上看不出光标在哪，像是「上下根本选不动」。
		if greyed.has(index):
			for i in _items.size():
				if not greyed.has(i):
					index = i
					break
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
	if Engine.get_physics_frames() == _built_frame:
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


## **这一帧别收键**。盖在上面的面板（商店的确认框、改名字的字母格）就是用这一下按键关掉的，
## 同一帧露出来的这一层不该再吃一次——`build()` 自带这个保护，只是重新 `show()` 走不到那儿。
func ignore_this_frame() -> void:
	_built_frame = Engine.get_physics_frames()


## 这一项在哪一行（别的控件想跟着光标走时用）。
func row_top(row: int) -> float:
	return row * ROW_HEIGHT


## 一屏摆几行。
func rows_shown() -> int:
	return _items.size() if window_rows <= 0 else mini(_items.size(), window_rows)


## 第一行现在显示的是第几项（滚动到哪儿了）。列表自己画内容时要按它取数据。
func first_row() -> int:
	return _top


## 第几项的选中框画在哪。
func highlight_box(index: int) -> Rect2:
	if index < row_boxes.size():
		return row_boxes[index]
	if _labels.is_empty():
		return Rect2()
	# 滚动时这一项画在第几行；夹一下是因为 `_step()` 会先挪 index、再滚动，中间那一瞬会越界
	var row := clampi(index - _top, 0, _labels.size() - 1)
	var top := row_top(row) + 2.0
	if wide_highlight:
		return Rect2(0.0, top, size.x, ROW_HEIGHT - 4.0)
	var text_wide: float = _labels[row].get_theme_font("font").get_string_size(
		_items[index], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
	return Rect2((size.x - text_wide) / 2.0 - PADDING, top, text_wide + PADDING * 2.0, ROW_HEIGHT - 4.0)


func _step(by: int) -> void:
	var was := index
	for _try in _items.size():
		index = wrapi(index + by, 0, _items.size())
		if not greyed.has(index):
			break
	if index != was:
		_scroll_into_view()
		_refresh()
		GameEvents.report(&"menu_move", self)
		moved.emit(index)


## 把选中那一项滚进画面里。项数没超过一屏就永远不滚。
func _scroll_into_view() -> void:
	var shown := _labels.size()
	if shown <= 0 or shown >= _items.size():
		_top = 0
		return
	_top = clampi(clampi(_top, index - shown + 1, index), 0, _items.size() - shown)


func _refresh() -> void:
	if _items.is_empty() or _labels.is_empty():
		if _cursor != null:
			_cursor.hide()
		return
	for i in _labels.size():
		var item := _top + i
		_labels[i].text = _items[item] if item < _items.size() else ""
		var tint := UiKit.WHITE if item == index else UiKit.DIM
		if greyed.has(item):
			tint = UiKit.DIM.darkened(0.35)
		_labels[i].add_theme_color_override("font_color", tint)
	if _cursor != null:
		_cursor.frame(highlight_box(index))
		_cursor.visible = not greyed.has(index)


## 按了自己这一份的某个动作。`listens_to` 是 -1 就谁按都算，**单人时也一样**——
## 规则在 `Session.just_pressed()` 那儿，那边有为什么。
func _pressed(action: StringName) -> bool:
	return Session.just_pressed(action, listens_to)
