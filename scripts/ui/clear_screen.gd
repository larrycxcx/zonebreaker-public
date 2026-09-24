class_name ClearScreen
extends CanvasLayer
## 通关结算：Boss 倒下之后停住关卡，摆出这一关每个人赚了多少，再问下一步去哪。
##
## 以前关卡只有一个出口——全灭。打死 Boss 什么都不会发生，你可以继续往右走到墙边站着。
## 23 关要接得上，就得有「打完了」这件事。
##
## **双人时两个人的成绩都显示**（左右两栏），因为经验和金钱是各算各的——
## 谁打死的记谁头上（见 `Progress` 的奖励归属）。
##
## 和死亡页是同一套零件（`UiKit` + `MenuList`），也一样把整棵树定住；
## 区别是这一页有「下一关」，而且它是**好消息**，所以不压暗那么狠。

## 打开了。
signal opened
## 选了第几项（选完才发，测试用）。
signal chosen(index: int)

## 开着的时候在这个组里。暂停菜单据此让路——两边都在改 `tree.paused`。
const GROUP := &"clear_screen"
const NEXT := 0
const MAIN_MENU := 1
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## 一栏多宽（双人时两栏并排）。
const COLUMN := 280.0
const GAP := 16.0

var _root: Control
var _menu: MenuList
var _title: Label
var _panels: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(UiKit.shade(0.5))
	var screen := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	_title = UiKit.label("STAGE CLEAR", Rect2(0, 24.0, screen.x, 34.0), UiKit.GOLD,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_title)
	_panels = Control.new()
	_panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panels)
	_menu = MenuList.new()
	_root.add_child(_menu)
	_menu.position = Vector2(0, screen.y - 78.0)
	_menu.chosen.connect(_on_chosen)
	_root.hide()


func is_open() -> bool:
	return _root.visible


## 菜单那一列（测试用）。
func menu_list() -> MenuList:
	return _menu


## 摆出成绩单。`results` 一人一份：`{"name", "level", "levels_gained", "xp", "money"}`。
## `has_next` 决定菜单上有没有「下一关」。
func open(results: Array, has_next: bool) -> void:
	if is_open():
		return
	for child in _panels.get_children():
		child.queue_free()
	var screen_x := float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var total := COLUMN * results.size() + GAP * maxf(results.size() - 1, 0)
	var left := (screen_x - total) / 2.0
	for i in results.size():
		_panels.add_child(_panel(results[i], left + i * (COLUMN + GAP)))
	var items: Array[String] = []
	if has_next:
		items.append("NEXT STAGE")
	items.append("MAIN MENU")
	_menu.build(items, screen_x)
	_root.show()
	add_to_group(GROUP)
	get_tree().paused = true
	opened.emit()


## 一个人的成绩：名字、等级（升了几级）、这一关赚的经验和金钱。
func _panel(result: Dictionary, x: float) -> Control:
	var box := UiKit.window(Rect2(x, 74.0, COLUMN, 150.0))
	var left := 24.0
	box.add_child(UiKit.label(String(result.get("name", "")), Rect2(left, 26.0, COLUMN - 48.0, 18.0),
		UiKit.CYAN))
	var gained: int = result.get("levels_gained", 0)
	var level_text := "LEVEL %d" % int(result.get("level", 1))
	if gained > 0:
		level_text += "   +%d" % gained
	box.add_child(UiKit.label(level_text, Rect2(left, 56.0, COLUMN - 48.0, 18.0),
		UiKit.GOLD if gained > 0 else UiKit.WHITE))
	var rows := [["XP", UiKit.number(int(result.get("xp", 0))), UiKit.WHITE],
		["CASH", UiKit.number(int(result.get("money", 0))), UiKit.GREEN]]
	for i in rows.size():
		var row: Array = rows[i]
		var top := 86.0 + i * 20.0
		box.add_child(UiKit.label(String(row[0]), Rect2(left, top, 90.0, 18.0), UiKit.DIM))
		box.add_child(UiKit.label("+" + String(row[1]), Rect2(left + 90.0, top, COLUMN - 138.0, 18.0),
			row[2], UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	return box


func _on_chosen(index: int) -> void:
	var tree := get_tree()
	var items := _menu._items
	_root.hide()
	remove_from_group(GROUP)
	tree.paused = false
	Progress.save_game()
	chosen.emit(index)
	if items[index] == "MAIN MENU":
		tree.change_scene_to_file(MENU_SCENE)
		return
	var next := Catalog.levels()
	var at := Catalog.index_of(Stage.current)
	if at >= 0 and at + 1 < next.size():
		Stage.use(next[at + 1])
		# 测试里关卡是手动实例化的，没有 current_scene，那就只是收起来
		if tree.current_scene != null:
			tree.change_scene_to_file(next[at + 1].scene_path)
