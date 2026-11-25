class_name LetterGrid
extends Control
## Typing with a pad: a grid with one letter per cell; move up / down / left / right, A enters, B finishes.
##
## Names only allow **upper-case letters, digits and spaces** (that is all the pack's font has, see CLAUDE.md),
## so this grid is exactly 6×6 to hold A–Z and 0–9, with space, backspace and done on the last row.
##
## It only listens to one player's keys (`listens_to`), so in co-op both players can edit their own names without getting in each other's way.

## The name changed.
signal changed(text: String)
## Finished (OK or B pressed).
signal done

const COLUMNS := 6
## Cells must be noticeably wider than the text: the three words on the last row (SPC / DEL / OK) take two columns each,
## and at 17px per column the 34px was filled exactly by the text, squeezing the three words into one string "SPCDELOK".
const CELL := Vector2(21, 16)
## The three wide cells on the last row. The names are short because a cell is only two columns wide (something as long as `SPACE` would spill onto the next cell).
const SPACE := "SPC"
const BACK := "DEL"
const OK := "OK"

## Which player's keys to listen to.
var listens_to := 0
## The name being edited.
var text := ""

var _cells: Array[String] = []
var _labels: Array[Label] = []
var _cursor := 0
var _limit := PlayerProgress.NAME_LIMIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Lay out the grid. `start` is the name already there on entering.
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
	# The box underneath is quite a bit wider than the letter cells: covering the whole column makes it look like a panel, otherwise the stat numbers behind it would show through the gaps
	add_child(UiKit.box(Rect2(-10.0, -8.0, size.x + 150.0, size.y + 14.0)))
	for i in _cells.size():
		var label := UiKit.label(_cells[i], Rect2(_cell_at(i), _cell_size(i)), UiKit.DIM,
			UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		add_child(label)
		_labels.append(label)
	_refresh()


## Where each cell goes. The last three cells (space / backspace / done) get a row of their own, each two columns wide.
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
