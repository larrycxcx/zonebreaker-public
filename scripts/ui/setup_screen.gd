class_name SetupScreen
extends Control
## Character setup: one column per player (name, look, points, gear), **both shown at once, each driven by its own pad**;
## the game starts once both players have pressed ACCEPT.
##
## This only lays out the columns and wraps up; a column's own business is in `SetupColumn`.
## The players on this screen are **made up for the moment** (the stage has not started, there are no real player nodes yet),
## just so `SetupColumn` can get a `player_index` and `progress` — sharing the same parts as the skill screen.

## Everyone has confirmed.
signal finished
## Someone pressed back while not confirmed.
signal cancelled

const GAP := 16.0

var _columns: Array[SetupColumn] = []
var _stand_ins: Array[Player] = []
## The open shop (**one for the whole screen**: two columns side by side, whoever presses SHOP opens this one).
var _shop: ShopScreen
## The hint line at the bottom. It has to hide while the shop is open — the shop writes a line in the same place.
var _prompt: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lay out a column for each of these seats. `locked` holds the seats loaded from a save (names cannot change).
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
	_prompt = UiKit.label("A CHOOSE    B BACK", Rect2(0, screen.y - 16.0, screen.x, 16.0),
		Color(0.74, 0.80, 0.92), UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_prompt)


func columns() -> Array[SetupColumn]:
	return _columns


## The open shop, null if it is not open (for tests).
func shop() -> ShopScreen:
	return _shop if is_instance_valid(_shop) else null


## Enter the shop. **Both players' columns open together**: when one wants to buy something, the other might as well browse —
## entering and leaving separately, the two screens would fight for the same piece of screen. The setup columns are hidden first so they do not take keys too
## (`MenuList` looks at `is_visible_in_tree()`).
func _open_shop() -> void:
	if is_instance_valid(_shop):
		return
	for column in _columns:
		column.hide()
	# **Its own hint line must hide too**: the shop writes a line at the same y, and two centred lines on top of each other blur into a mess
	# (found in a 2026-09 playtest screenshot; headless tests cannot measure it).
	if is_instance_valid(_prompt):
		_prompt.hide()
	_shop = ShopScreen.new()
	add_child(_shop)
	_shop.build(_stand_ins)
	_shop.finished.connect(_close_shop)


func _close_shop() -> void:
	if is_instance_valid(_shop):
		_shop.queue_free()
	_shop = null
	if is_instance_valid(_prompt):
		_prompt.show()
	for column in _columns:
		column.show()
		# The shop was closed with this press of B; this layer should not take it again on the same frame (that would back out of the whole page)
		column.menu_list().ignore_this_frame()
		column.refresh()


## There is no real player yet, so make a stand-in carrying just the number and progress for this column.
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


## Tell each column "which look the other player picked", so that one cannot be chosen.
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
