class_name ShopScreen
extends Control
## 商店：**每个玩家一栏、左右并排、各按各的手柄**，两个人都逛完了才离开。
##
## 这里只管摆栏、压暗背景和收尾，一栏自己的事全在 `ShopColumn` 里
## （和人物设置界面 `SetupScreen` / `SetupColumn` 是同一个分法）。
##
## 两个入口：关卡开始前（人物设置那一栏的 SHOP）和打完一关的结算页。
## 两处都是**关卡之外**——这是有意的：打着打着不能换装备，要换就在两关之间。

## 都逛完了，可以走了。
signal finished

const PROMPT := "A CHOOSE   LB RB TAB   X SELL   B LEAVE"
const GAP := 16.0

var _columns: Array[ShopColumn] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 给这几个玩家各摆一栏。`players` 可以是关卡里真的玩家，也可以是人物设置界面那种替身
## （商店只用到 `player_index` 和 `progress`）。
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


## **所有人**都逛完了才走。一个人先逛完的那一栏自己会变成「等另一个人」，
## 上面留着 BACK TO SHOP，所以不会干等着没事干。
func _on_readiness_changed(_done: bool) -> void:
	if _columns.all(func(column: ShopColumn) -> bool: return column.done):
		Progress.save_game()
		finished.emit()
