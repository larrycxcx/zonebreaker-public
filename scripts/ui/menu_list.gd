class_name MenuList
extends Control
## A column of menu items to pick from up and down. It draws its own cursor and handles its own keys, emitting `chosen` on a selection.
##
## It uses **the game's own inputs**, not Godot's `ui_*`: up / down with `aim_up` / `aim_down` (d-pad up / down),
## confirm with `jump` (A), back with `cancel` (B). So hands on the pad never have to move, and two players each press their own
## (`player_index` decides whose to listen to, see the prefix rule of `Player.act()`).

## Which item was chosen.
signal chosen(index: int)
## Back was pressed.
signal cancelled
## Left / right was pressed on this item (`direction` is -1 / 1). The menu does not care what it means; that is up to the screen using it
## (character setup uses it to switch characters and move between gear boxes).
signal nudged(index: int, direction: int)
## The cursor moved to an item (for sound effects).
signal moved(index: int)

const ROW_HEIGHT := 24.0
## How much wider than the text inside the selection box is.
const PADDING := 6.0

## Which player's input to listen to. -1 = anyone's press counts (the single-player pause menu uses this).
var listens_to := -1
## Most rows shown at once (0 = as many as there are items). With more items than this, moving up and down **scrolls**:
## the number of rows stays the same and what changes is which item each row shows (used for lists that keep growing, like the save list).
var window_rows := 0
## How wide the selection box is drawn: the whole row (like the skill screen and save list) or just around the text (like menus).
var wide_highlight := false
## Where each row's selection box goes (in this menu's own coordinates). Empty works it out from the row height.
## Only screens like character setup — "one block of content per row, each a different size and position" — need to fill this in.
## **It is a setter**: `build()` has already placed the box once, and boxes filled in later need it redrawn.
var row_boxes: Array[Rect2] = []:
	set(value):
		row_boxes = value
		_refresh()
## The item selected now. **It is a setter**: assigning it directly (`SetupColumn.go_to_row()`, jumping rows in tests) must also move the selection box,
## otherwise the box stays on the previous row — key presses go through `_step()`, and nobody used to handle this assignment path.
var index := 0:
	set(value):
		index = value
		_refresh()

var _items: Array[String] = []
var _labels: Array[Label] = []
var _cursor: OutlineBox
## Which item the first row shows now (how far it has scrolled).
var _top := 0
## The physics frame on which this set of items was put in. **No keys are taken on the frame it is built**: the previous page was left with this very key press,
## and this page should not take it again on the same frame (one B going back two pages, one A choosing two levels deep).
var _built_frame := -1


## Lay out these items. `width` is how wide this column is (text centred).
func build(items: Array[String], width: float) -> void:
	_items = items
	_built_frame = Engine.get_physics_frames()
	for child in get_children():
		child.queue_free()
	_labels.clear()
	# A new set of items starts from the top: without clearing, coming from item 2 on the title page would leave the next page on item 2 as well
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


## Which items are grey (cannot be chosen). `disabled` holds indexes.
var greyed: Array[int] = []:
	set(value):
		greyed = value
		# If the cursor rests on an item that cannot be chosen, move it off: otherwise the box would hide entirely,
		# and with no visible cursor it would look like "up and down do not work at all".
		if greyed.has(index):
			for i in _items.size():
				if not greyed.has(i):
					index = i
					break
		_refresh()


func _ready() -> void:
	# When paused the whole tree stops; the menu has to keep running itself, or nobody would take the keys
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	# **It has to check is_visible_in_tree(), not visible**: `visible` only says whether this node itself is switched on,
	# and it stays true when a parent is hidden. When the pause menu is not open its whole UI is hidden,
	# and looking only at visible this would still take keys — pressing "down down A" in the game would pick QUIT and close the game.
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


## **Take no keys this frame**. The panel on top (the shop's confirm box, the name letter grid) was closed with this very press,
## and the layer revealed on the same frame should not take it again — `build()` has this protection built in, but showing it again with `show()` never gets there.
func ignore_this_frame() -> void:
	_built_frame = Engine.get_physics_frames()


## Which row this item is on (for other controls that want to follow the cursor).
func row_top(row: int) -> float:
	return row * ROW_HEIGHT


## How many rows fit on one screen.
func rows_shown() -> int:
	return _items.size() if window_rows <= 0 else mini(_items.size(), window_rows)


## Which item the first row shows now (how far it has scrolled). Lists that draw their own content take their data by this.
func first_row() -> int:
	return _top


## Where the selection box of an item goes.
func highlight_box(index: int) -> Rect2:
	if index < row_boxes.size():
		return row_boxes[index]
	if _labels.is_empty():
		return Rect2()
	# Which row this item is drawn on while scrolling; clamped because `_step()` moves index first and scrolls after, so for an instant it is out of range
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


## Scroll the selected item into view. Never scrolls when the items fit on one screen.
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


## One of this player's own actions was pressed. With `listens_to` at -1 anyone's press counts, **and so it does when playing alone** —
## the rule lives in `Session.just_pressed()`, which explains why.
func _pressed(action: StringName) -> bool:
	return Session.just_pressed(action, listens_to)
