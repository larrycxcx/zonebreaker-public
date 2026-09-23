class_name LetterGrid
extends Control
## 用手柄打字：一格一个字母的网格，上下左右挪、A 输入、B 完成。
##
## 名字只允许**大写字母、数字和空格**（素材包的字模就只有这些，见 CLAUDE.md），
## 所以这张网格正好 6×6 装下 A–Z 和 0–9，最后一行放空格、退格、完成。
##
## 只听一个玩家的键（`listens_to`），所以双人时两个人可以各改各的名字，互不干扰。

## 名字改了。
signal changed(text: String)
## 打完了（按了 OK 或者 B）。
signal done

const COLUMNS := 6
## 格子要比字宽出一截：最后一行那三个词（SPC / DEL / OK）占两列，
## 一列 17px 的时候 34px 刚好被字填满，三个词挤成一串「SPCDELOK」。
const CELL := Vector2(21, 16)
## 最后一行那三个宽格子。名字短是因为格子只有两列宽（`SPACE` 那么长会压到旁边那格上）。
const SPACE := "SPC"
const BACK := "DEL"
const OK := "OK"

## 听第几号玩家的键。
var listens_to := 0
## 正在编辑的名字。
var text := ""

var _cells: Array[String] = []
var _labels: Array[Label] = []
var _cursor := 0
var _limit := PlayerProgress.NAME_LIMIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 摆出网格。`start` 是进来时已有的名字。
func build(start: String, player_index: int) -> void:
	listens_to = player_index
	text = start
	_cells.clear()
	_labels.clear()
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
		_cells.append(ch)
	_cells.append_array([SPACE, BACK, OK])
	var rows := int(ceil(float(_cells.size() - 3) / COLUMNS)) + 1
	size = Vector2(COLUMNS * CELL.x, rows * CELL.y)
	# 垫在底下的盒子比字母格宽不少：盖住整栏才像个面板，不然背后的属性数字会从缝里露出来
	add_child(UiKit.box(Rect2(-10.0, -8.0, size.x + 150.0, size.y + 14.0)))
	for i in _cells.size():
		var label := UiKit.label(_cells[i], Rect2(_cell_at(i), _cell_size(i)), UiKit.DIM,
			UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		add_child(label)
		_labels.append(label)
	_refresh()


## 第几格摆在哪。最后三格（空格 / 退格 / 完成）单独占一行，一格两列宽。
func _cell_at(index: int) -> Vector2:
	if index < _cells.size() - 3:
		return Vector2((index % COLUMNS) * CELL.x, (index / COLUMNS) * CELL.y)
	var last := index - (_cells.size() - 3)
	return Vector2(last * 2 * CELL.x, (size.y / CELL.y - 1) * CELL.y)


func _cell_size(index: int) -> Vector2:
	return CELL if index < _cells.size() - 3 else Vector2(CELL.x * 2.0, CELL.y)


func cursor() -> int:
	return _cursor


func _physics_process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _pressed(&"move_left"):
		_step(-1)
	elif _pressed(&"move_right"):
		_step(1)
	elif _pressed(&"aim_up"):
		_step(-COLUMNS)
	elif _pressed(&"aim_down"):
		_step(COLUMNS)
	elif _pressed(&"jump"):
		_type(_cells[_cursor])
	elif _pressed(&"cancel"):
		GameEvents.report(&"menu_back", self)
		done.emit()


func _step(by: int) -> void:
	_cursor = wrapi(_cursor + by, 0, _cells.size())
	GameEvents.report(&"menu_move", self)
	_refresh()


func _type(cell: String) -> void:
	GameEvents.report(&"menu_select", self)
	match cell:
		OK:
			done.emit()
			return
		BACK:
			text = text.substr(0, maxi(0, text.length() - 1))
		SPACE:
			if text.length() < _limit and not text.is_empty():
				text += " "
		_:
			if text.length() < _limit:
				text += cell
	changed.emit(text)


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].add_theme_color_override("font_color", UiKit.GOLD if i == _cursor else UiKit.DIM)


func _pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action if listens_to == 0
		else StringName("p%d_%s" % [listens_to + 1, action]))
