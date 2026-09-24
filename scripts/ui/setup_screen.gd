class_name SetupScreen
extends Control
## 人物设置界面：每个玩家一栏（名字、外观、加点、装备），**两栏同时显示、各按各的手柄**，
## 两个人都按了 ACCEPT 才开始游戏。
##
## 这里只管摆栏和收尾，一栏自己的事在 `SetupColumn` 里。
## 界面上的玩家是**临时造出来的**（还没进关卡，场上没有真玩家节点），
## 只为了让 `SetupColumn` 能拿到 `player_index` 和 `progress`——和加点界面共用同一套零件。

## 所有人都确定了。
signal finished
## 有人在没确定的时候按了返回。
signal cancelled

const GAP := 16.0

var _columns: Array[SetupColumn] = []
var _stand_ins: Array[Player] = []
## 开着的商店（**整个界面共用一个**：两栏并排，谁按 SHOP 都是开这一个）。
var _shop: ShopScreen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 给这几个座位各摆一栏。`locked` 里是读档进来的座位（名字不能改）。
func build(seats: int, locked: Array[int] = []) -> void:
	for child in get_children():
		child.queue_free()
	_columns.clear()
	_stand_ins.clear()
	var screen := _screen()
	var total := SetupColumn.WIDTH * seats + GAP * (seats - 1)
	var left := (screen.x - total) / 2.0
	for i in seats:
		var column := SetupColumn.new()
		column.position = Vector2(left + i * (SetupColumn.WIDTH + GAP), 4.0)
		add_child(column)
		column.can_rename = not locked.has(i)
		column.build(_stand_in(i), i, &"")
		column.readiness_changed.connect(_on_readiness_changed)
		column.backed_out.connect(func() -> void: cancelled.emit())
		column.shop_requested.connect(_open_shop)
		_columns.append(column)
	_share_looks()
	add_child(UiKit.label("A CHOOSE    B BACK", Rect2(0, screen.y - 16.0, screen.x, 16.0),
		Color(0.74, 0.80, 0.92), UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func columns() -> Array[SetupColumn]:
	return _columns


## 开着的商店，没开就是 null（测试用）。
func shop() -> ShopScreen:
	return _shop if is_instance_valid(_shop) else null


## 进商店。**两个人的栏一起开**：一个人要买东西，另一个也就顺便逛了——
## 分别进出的话两边的界面会在同一块屏幕上抢地方。设置界面这几栏先藏起来，免得它们也在收键
## （`MenuList` 看的是 `is_visible_in_tree()`）。
func _open_shop() -> void:
	if is_instance_valid(_shop):
		return
	for column in _columns:
		column.hide()
	_shop = ShopScreen.new()
	add_child(_shop)
	_shop.build(_stand_ins)
	_shop.finished.connect(_close_shop)


func _close_shop() -> void:
	if is_instance_valid(_shop):
		_shop.queue_free()
	_shop = null
	for column in _columns:
		column.show()
		# 商店就是用这一下 B 退出来的，同一帧这一层不该再吃一次（那会把整页退回去）
		column.menu_list().ignore_this_frame()
		column.refresh()


## 场上还没有真玩家，造一个只带编号和进度的替身给这一栏用。
func _stand_in(index: int) -> Player:
	var stand_in := Player.new()
	stand_in.player_index = index
	stand_in.progress = Progress.of(index)
	_stand_ins.append(stand_in)
	return stand_in


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))


func _on_readiness_changed(_confirmed: bool) -> void:
	_share_looks()
	if _columns.all(func(column: SetupColumn) -> bool: return column.confirmed):
		finished.emit()


## 告诉每一栏「另一个人选了哪个外观」，那个就选不动了。
func _share_looks() -> void:
	if _columns.size() < 2:
		return
	for i in _columns.size():
		var other: SetupColumn = _columns[1 - i]
		_columns[i].set_taken_look(other.progress.look)


func _exit_tree() -> void:
	for stand_in in _stand_ins:
		if is_instance_valid(stand_in):
			stand_in.free()
