class_name DeathScreen
extends CanvasLayer
## 全灭之后的选择：再来一次，还是回主菜单。
##
## 以前是死了 1.2 秒自动重载本关，玩家没得选，也没法中途收手去换个角色。
## 现在那 1.2 秒照旧（让死亡动画和音效走完），到点弹出这个，**把整棵树定住**等玩家选。
##
## 和暂停界面是同一套零件（`UiKit` + `MenuList`），只是没有返回——死都死了，没有「取消」这回事。
## 双人时谁按都算（`listens_to` 留 -1），因为两个人一起输的。

## 打开了。
signal opened
## 选了第几项（选完才发，测试用）。
signal chosen(index: int)

## 开着的时候在这个组里。暂停菜单据此让路——两边都在改 `tree.paused`，抢起来会互相解掉。
const GROUP := &"death_screen"
const ITEMS: Array[String] = ["RETRY", "MAIN MENU"]
const RETRY := 0
const MAIN_MENU := 1
## 回主菜单去哪个场景。
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _root: Control
var _window: Control
var _title: Label
var _menu: MenuList


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 比暂停界面高一层：死掉那一刻万一暂停界面还开着，这个要盖在上面
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(UiKit.shade())
	var screen := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	# **「GAME OVER」这行字归这里写**，不归 HUD：压暗那层就在这一层上，
	# HUD 是更低的一层，写在那边会被压暗、灰得看不清。
	_title = UiKit.label("GAME OVER", Rect2(0, 140.0, screen.x, 34.0), UiKit.WHITE,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_title)
	var box := Rect2(screen.x / 2.0 - 104.0, 188.0, 208.0, 100.0)
	_window = UiKit.window(box)
	_root.add_child(_window)
	_menu = MenuList.new()
	_root.add_child(_menu)
	_menu.build(ITEMS, box.size.x)
	_menu.position = box.position + Vector2(0, 26.0)
	_menu.chosen.connect(_on_chosen)
	_root.hide()


func is_open() -> bool:
	return _root.visible


## 菜单那一列（测试用）。
func menu_list() -> MenuList:
	return _menu


func open() -> void:
	if is_open():
		return
	_root.show()
	_menu.index = RETRY
	add_to_group(GROUP)
	get_tree().paused = true
	opened.emit()


func _on_chosen(index: int) -> void:
	var tree := get_tree()
	_root.hide()
	remove_from_group(GROUP)
	tree.paused = false
	Progress.save_game()
	chosen.emit(index)
	if index == MAIN_MENU:
		tree.change_scene_to_file(MENU_SCENE)
		return
	# 测试里关卡是手动实例化的，没有 current_scene，那就只是收起来（不能重载一个不存在的场景）
	if tree.current_scene != null:
		tree.reload_current_scene()
