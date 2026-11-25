class_name ShopScreen
extends Control
## Shop: **one column per player, side by side, each driven by its own pad**; it only closes once both players are done.
##
## This only lays out the columns, darkens the background and wraps up; a column's own business is all in `ShopColumn`
## (the same split as character setup's `SetupScreen` / `SetupColumn`).
##
## Two entry points: before a stage (SHOP in the character setup column) and the results screen after clearing a stage.
## Both are **outside the stages** — on purpose: gear cannot change in the middle of fighting, only between stages.

## Everyone is done; time to leave.
signal finished

const PROMPT := "A CHOOSE   LB RB TAB   X SELL   B LEAVE"
const GAP := 16.0

var _columns: Array[ShopColumn] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lay out a column for each of these players. `players` can be the real players of a stage or stand-ins like those of character setup
## (the shop only uses `player_index` and `progress`).
func build(players: Array) -> void:
	for child in get_children():
		child.queue_free()
	_columns.clear()
	add_child(UiKit.shade(0.72))
	var screen := _screen()
	var total := ShopColumn.WIDTH * players.size() + GAP * maxf(players.size() - 1, 0)
	var left := (screen.x - total) / 2.0
	var top := (screen.y - ShopColumn.HEIGHT - 16.0) / 2.0
	for i in players.size():
		var column := ShopColumn.new()
		column.position = Vector2(left + i * (ShopColumn.WIDTH + GAP), top)
		add_child(column)
		column.build(players[i])
		column.readiness_changed.connect(_on_readiness_changed)
		_columns.append(column)
	add_child(UiKit.label(PROMPT, Rect2(0.0, screen.y - 16.0, screen.x, 16.0),
		Color(0.74, 0.80, 0.92), UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func columns() -> Array[ShopColumn]:
	return _columns


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))


## It only leaves once **everyone** is done. A column that finishes first turns into "waiting for the other player" by itself,
## with BACK TO SHOP left on it, so nobody is stuck with nothing to do.
func _on_readiness_changed(_done: bool) -> void:
	if _columns.all(func(column: ShopColumn) -> bool: return column.done):
		Progress.save_game()
		finished.emit()
