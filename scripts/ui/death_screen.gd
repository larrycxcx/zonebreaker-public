class_name DeathScreen
extends CanvasLayer
## The choice after everyone is down: try again, or back to the main menu.
##
## It used to reload the stage automatically 1.2 seconds after dying; the player had no say and could not stop to switch characters.
## Now those 1.2 seconds remain (letting the death animation and sound finish), then this pops up and **freezes the whole tree** until the player chooses.
##
## Built from the same parts as the pause menu (`UiKit` + `MenuList`), only without going back — you are dead, there is no "cancel".
## In co-op anyone's press counts (`listens_to` left at -1), because you lost together.

## Opened.
signal opened
## Which item was chosen (emitted after choosing, for tests).
signal chosen(index: int)

## In this group while open. The pause menu gives way because of it — both change `tree.paused`, and fighting over it they would undo each other.
const GROUP := &"death_screen"
const ITEMS: Array[String] = ["RETRY", "MAIN MENU"]
const RETRY := 0
const MAIN_MENU := 1
## Which scene "back to the main menu" goes to.
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _root: Control
var _window: Control
var _title: Label
var _menu: MenuList


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# One layer above the pause menu: if the pause menu happens to be open at the moment of death, this has to cover it
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(UiKit.shade())
	var screen := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	# **The "GAME OVER" line belongs here**, not to the HUD: the darkening layer is on this layer,
	# and the HUD is a lower layer, so written there it would be darkened into an unreadable grey.
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


## The menu column (for tests).
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
	# In tests the stage is instantiated by hand and there is no current_scene, so just close it (a scene that does not exist cannot be reloaded)
	if tree.current_scene != null:
		tree.reload_current_scene()
