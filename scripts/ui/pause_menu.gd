class_name PauseMenu
extends CanvasLayer
## 暂停界面：按 Start（或 Esc）定住整个关卡，弹出 RESUME / SKILLS / QUIT。
##
## **两个玩家都能暂停**——`pause` 这个动作两个手柄的 Start 都绑了。
## 菜单本身谁都能操作（`MenuList.listens_to` 留 -1），加点界面里才分你我。
##
## 节点是 `PROCESS_MODE_ALWAYS`：整棵树被 `get_tree().paused` 停住之后，只有它还在跑，才收得到按键。
## **终极武器定格那两秒不让暂停**：那边也在用 `tree.paused`，两边抢着改会互相把对方解掉。

signal opened
signal closed

const ITEMS: Array[String] = ["RESUME", "SKILLS", "MAIN MENU"]
const RESUME := 0
const SKILLS := 1
const MAIN_MENU := 2
## 回主菜单去哪个场景。
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _shade: ColorRect
var _window: Control
var _title: Label
var _menu: MenuList
var _skills: SkillsScreen
var _root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_shade = UiKit.shade()
	_root.add_child(_shade)
	var screen := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	var box := Rect2(screen.x / 2.0 - 128.0, 96.0, 256.0, 160.0)
	_window = UiKit.window(box)
	_root.add_child(_window)
	_title = UiKit.label("PAUSED", Rect2(box.position + Vector2(0, 22.0), Vector2(box.size.x, 30.0)),
		UiKit.CYAN, UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_title)
	_menu = MenuList.new()
	_root.add_child(_menu)
	_menu.build(ITEMS, box.size.x)
	_menu.position = box.position + Vector2(0, 74.0)
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(close)
	_root.hide()


func is_open() -> bool:
	return _root.visible


## 菜单那一列（测试用）。
func menu_list() -> MenuList:
	return _menu


func _physics_process(_delta: float) -> void:
	if not is_open() and Input.is_action_just_pressed(&"pause") and _may_open():
		open()


## 终极武器正在定格、或者已经全灭在等玩家选的时候不让暂停：
## 那两边也在用 `tree.paused`，抢起来会互相把对方解掉。
func _may_open() -> bool:
	var tree := get_tree()
	if not tree.get_nodes_in_group(Ultimate.GROUP).is_empty():
		return false
	if not tree.get_nodes_in_group(ClearScreen.GROUP).is_empty():
		return false
	return tree.get_nodes_in_group(DeathScreen.GROUP).is_empty()


func open() -> void:
	if is_open():
		return
	_root.show()
	_show_menu()
	get_tree().paused = true
	GameEvents.report(&"menu_select", self)
	opened.emit()


func close() -> void:
	if not is_open():
		return
	_drop_skills()
	_root.hide()
	get_tree().paused = false
	GameEvents.report(&"menu_back", self)
	closed.emit()


func _on_chosen(index: int) -> void:
	match index:
		RESUME:
			close()
		SKILLS:
			_open_skills()
		MAIN_MENU:
			_to_main_menu()


func _show_menu() -> void:
	for node in [_window, _title, _menu]:
		node.show()
	_menu.index = RESUME


func _open_skills() -> void:
	for node in [_window, _title, _menu]:
		node.hide()
	_skills = SkillsScreen.new()
	_root.add_child(_skills)
	_skills.build(_players())
	_skills.closed.connect(func() -> void:
		_drop_skills()
		_show_menu())


func _drop_skills() -> void:
	if _skills != null and is_instance_valid(_skills):
		_skills.queue_free()
	_skills = null


## 回主菜单：先把暂停解掉，否则新场景一进来就是停的。
func _to_main_menu() -> void:
	var tree := get_tree()
	_drop_skills()
	_root.hide()
	tree.paused = false
	Progress.save_game()
	tree.change_scene_to_file(MENU_SCENE)


## 场上的玩家，按编号排。
func _players() -> Array[Player]:
	var found: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		found.append(node as Player)
	found.sort_custom(func(a: Player, b: Player) -> bool: return a.player_index < b.player_index)
	return found
