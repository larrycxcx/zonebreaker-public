class_name ClearScreen
extends CanvasLayer
## Stage clear results: after the boss falls the stage freezes, shows how much each player earned this stage, then asks where to go next.
##
## Stages used to have only one way out — everyone dying. Killing the boss did nothing, and you could keep walking right until you stood at the wall.
## For 23 stages to connect there has to be "cleared".
##
## **In co-op both players' results are shown** (left and right columns), because XP and money are counted separately —
## each kill is credited to whoever made it (see reward attribution in `Progress`).
##
## Built from the same parts as the death screen (`UiKit` + `MenuList`), and it freezes the whole tree too;
## the difference is that this one has "next stage", and it is **good news**, so it does not darken as heavily.

## Opened.
signal opened
## Which item was chosen (emitted after choosing, for tests).
signal chosen(index: int)

## In this group while open. The pause menu gives way because of it — both change `tree.paused`.
const GROUP := &"clear_screen"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## The menu items. **Identified by name, not index**: whether there is "next stage" depends on whether the stage just cleared was the last one.
const NEXT_STAGE := "NEXT STAGE"
const SHOP := "SHOP"
const MAIN_MENU := "MAIN MENU"

## Width of a column (two side by side in co-op).
const COLUMN := 280.0
const GAP := 16.0

var _root: Control
var _menu: MenuList
var _title: Label
var _panels: Control
## The open shop (**this is the only other entry point between stages**; the other is in character setup).
var _shop: ShopScreen


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


## The menu column (for tests).
func menu_list() -> MenuList:
	return _menu


## Show the results. `results` has one entry per player: `{"name", "level", "levels_gained", "xp", "money"}`.
## `has_next` decides whether the menu has "next stage".
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
		items.append(NEXT_STAGE)
	# **Right after clearing a stage is the time to go shopping**: spend what you just earned and change gear before the next stage
	items.append(SHOP)
	items.append(MAIN_MENU)
	_menu.build(items, screen_x)
	_root.show()
	add_to_group(GROUP)
	get_tree().paused = true
	opened.emit()


## One player's results: name, level (how many levels gained), the XP and money earned this stage.
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


## The open shop, null if it is not open (for tests).
func shop() -> ShopScreen:
	return _shop if is_instance_valid(_shop) else null


## Entering the shop: hide the results first (otherwise two menus would take input together), and come back after shopping.
func _open_shop() -> void:
	if is_instance_valid(_shop):
		return
	_root.hide()
	var players: Array = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.progress != null:
			players.append(player)
	players.sort_custom(func(a: Player, b: Player) -> bool:
		return a.player_index < b.player_index)
	_shop = ShopScreen.new()
	add_child(_shop)
	_shop.build(players)
	_shop.finished.connect(_close_shop)


func _close_shop() -> void:
	if is_instance_valid(_shop):
		_shop.queue_free()
	_shop = null
	_root.show()
	_menu.ignore_this_frame()   # The shop was closed with this press of B


func _on_chosen(index: int) -> void:
	var items := _menu._items
	if items[index] == SHOP:
		_open_shop()
		return
	var tree := get_tree()
	_root.hide()
	remove_from_group(GROUP)
	tree.paused = false
	Progress.save_game()
	chosen.emit(index)
	if items[index] == MAIN_MENU:
		tree.change_scene_to_file(MENU_SCENE)
		return
	var next := Catalog.levels()
	var at := Catalog.index_of(Stage.current)
	if at >= 0 and at + 1 < next.size():
		Stage.use(next[at + 1])
		# In tests the stage is instantiated by hand and there is no current_scene, so just close it
		if tree.current_scene != null:
			tree.change_scene_to_file(next[at + 1].scene_path)
