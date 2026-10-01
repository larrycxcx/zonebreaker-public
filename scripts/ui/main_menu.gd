class_name MainMenu
extends Node2D
## 主菜单：选几个人玩、每个人新建或读取一个角色，然后开始关卡。
##
## 几页拼起来的一个小流程（`Page`）：
## 标题（1 PLAYER / 2 PLAYERS / QUIT）→ **每个座位轮流**选 NEW 还是 LOAD →
## 选 LOAD 就从名册里挑一个（列表显示名字、等级、玩了多久、上次存档时间，可以删）→
## 都选完就 `change_scene_to_file` 进关卡。
##
## 人物设置界面（起名、选外观、加点、装备）还没做，现在选 NEW 直接现开一个默认角色就走；
## 那一步做好之后插在「选完 NEW / LOAD」和「进关卡」之间。
##
## 界面一律英文大写（素材包的字模没有汉字，见 CLAUDE.md）。

## 从哪一关开始：**扫 `levels/` 目录**得来的第一关（见 `Catalog`），不在代码里点名。
## 这样加一关就是往那儿丢一个 `.tres`，DLC 也走同一条路。
## （`scenes/main.tscn` 是测试关，不在清单里，测试直接加载它。）
static func level_scene() -> String:
	var first := Catalog.first_level()
	return first.scene_path if first != null else ""
## 游戏名，写在标题牌里那一格。以后定了再改这里。
const TITLE := "FIRST GAME"
const SUBTITLE := "A RUN AND GUN"

enum Page {
	TITLE,      ## 几个人玩
	SOURCE,     ## 这个座位新建还是读档
	LOAD_LIST,  ## 从名册里挑一个
	CONFIRM,    ## 真的要删吗
	SETUP,      ## 人物设置（每人一栏，都确定了才开始）
	STAGE,      ## 从解锁了的关卡里挑一关（只有一关可选时直接跳过）
}

## 名册列表一页显示几行。存档多过这个数就滚动，不是把后面的砍掉。
const ROWS := 6
## 列表里的窗口多宽多高。
const LIST_BOX := Vector2(480.0, 240.0)
## 九宫格边框四边各占这么多像素，字得落在里面，压在边上会被框子切掉。
const LIST_EDGE := 32.0
## 四列：标题、离内容左边多远、多宽。**右边那列的末尾要落在边框里面**
## （内容左边 = 窗口左边 + 40，所以最多能到 480 - 40 - 32 = 408）。
const LIST_COLUMNS := [["NAME", 0.0, 134.0], ["LV", 138.0, 40.0], ["PLAYED", 186.0, 84.0], ["SAVED", 278.0, 122.0]]

var _page := Page.TITLE
## 正在给第几个座位选。
var _seat := 0
## 列表里现在列的是哪些角色（下标和菜单项对得上）。
var _listed: Array[PlayerProgress] = []
## 要删的那个。
var _doomed: PlayerProgress
## 哪些座位是读档进来的（名字不能改）。
var _loaded: Array[int] = []
var _setup: SetupScreen
## 列表上那几行的文字（一行四个），滚动时改的是它们的内容，不是重新摆节点。
var _row_labels: Array[Array] = []
var _scroll_mark: Label

var _ui: CanvasLayer
var _body: Control
var _menu: MenuList
var _title: Label
var _hint: Label


func _ready() -> void:
	_add_backdrop()
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	# 背景是白天那套，挺亮的，压暗一层菜单的字才读得清
	var shade := UiKit.shade(0.34)
	_ui.add_child(shade)
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_body)
	_menu = MenuList.new()
	_body.add_child(_menu)
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	Music.play(&"intro")
	_show(Page.TITLE)


## 和关卡里同一套背景（素材包有就用，没有就露出清屏色）。
func _add_backdrop() -> void:
	var scene := Skins.backdrop()
	if scene == null:
		return
	var backdrop := scene.instantiate()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 0)


func page() -> Page:
	return _page


func seat() -> int:
	return _seat


## 列表上现在列着的角色（测试用）。
func listed() -> Array[PlayerProgress]:
	return _listed


## 人物设置那一页（测试用），没在那一页就是 null。
func setup() -> SetupScreen:
	return _setup if _page == Page.SETUP and is_instance_valid(_setup) else null


func _physics_process(_delta: float) -> void:
	# **按这个座位自己那一份**（双人时 1 号是 `menu_delete`、2 号是 `p2_menu_delete`）：
	# 两个座位轮流选，删的是轮到谁的那一页，不该被另一只手柄按到。单人时谁按都算。
	if _page == Page.LOAD_LIST and not _listed.is_empty() and Session.just_pressed(&"menu_delete", _seat):
		_doomed = _listed[_menu.index]
		_show(Page.CONFIRM)


# ---------------------------------------------------------------- 画每一页

## 每一页听谁的键。**写着 PLAYER N 的那几页只听那个座位自己的手柄**——
## 不分的话，拿 2 号手柄的人可以把角色选进 1 号座位，然后一进人物设置界面
## （那一栏只听 1 号手柄）他就变成 2 号了（2026-09 试玩报的「手柄错位」）。
## 「几个人玩」「选哪一关」是**大家一起定的**，所以留 -1（谁按都算），和死亡页同一个道理。
## 删存档本来就是按座位取的（`_physics_process`），这里只是把导航那一半补齐。
## 单人时 `Session.just_pressed()` 一律谁按都算，所以这几页在单人下行为不变。
const LISTENS := {
	Page.TITLE: -1,
	Page.SETUP: -1,
	Page.STAGE: -1,
}


func _show(page_: Page) -> void:
	_page = page_
	for child in _body.get_children():
		if child != _menu:
			child.queue_free()
	_menu.listens_to = LISTENS.get(page_, _seat)
	var screen := _screen()
	match page_:
		Page.TITLE:
			_draw_title(screen)
			_lay_out(["1 PLAYER", "2 PLAYERS", "QUIT"], screen, 186.0, "SPACE OR A TO START")
		Page.SOURCE:
			_heading("PLAYER %d" % (_seat + 1), screen)
			_lay_out(["NEW CHARACTER", "LOAD CHARACTER", "BACK"], screen, 150.0, "A CHOOSE    B BACK")
		Page.LOAD_LIST:
			_draw_list(screen)
		Page.CONFIRM:
			_heading("DELETE %s" % _doomed.character_name, screen)
			_lay_out(["NO", "YES"], screen, 170.0, "THIS CANNOT BE UNDONE")
		Page.SETUP:
			_menu.build([], 0.0)
			_setup = SetupScreen.new()
			_body.add_child(_setup)
			_setup.build(Session.player_count, _loaded)
			_setup.finished.connect(_after_setup)
			_setup.cancelled.connect(_back_to_source)
		Page.STAGE:
			_heading("SELECT STAGE", screen)
			var names: Array[String] = []
			for level in _unlocked():
				names.append("%d  %s" % [Catalog.index_of(level) + 1, level.display_name])
			_lay_out(names, screen, 130.0, "A CHOOSE    B BACK")
			# 光标停在最靠后的那一关 = 「接着上次打」，想重打前面的往上走
			_menu.index = maxi(0, names.size() - 1)
	# 菜单是 `_ready` 里就加好的，每页的窗口都是后加的——**后加的画在上面**，
	# 不挪的话金色选中框会被窗口盖住，界面上看不出光标在哪。
	_body.move_child(_menu, -1)


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))


func _draw_title(screen: Vector2) -> void:
	var plate := UiKit.picture(UiKit.DIR + "/title_plate.png", Vector2.ZERO)
	plate.position = Vector2((screen.x - plate.texture.get_width()) / 2.0, 14.0)
	_body.add_child(plate)
	_body.add_child(UiKit.label(TITLE, Rect2(0, 40.0, screen.x, 34.0), UiKit.CYAN,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(UiKit.label(SUBTITLE, Rect2(0, 98.0, screen.x, 20.0), Color(0.62, 0.68, 0.82),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func _heading(text: String, screen: Vector2) -> void:
	_title = UiKit.label(text, Rect2(0, 64.0, screen.x, 34.0), UiKit.CYAN,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_title)


func _lay_out(items: Array[String], screen: Vector2, top: float, hint: String) -> void:
	_menu.wide_highlight = false
	_menu.row_boxes = []
	_menu.greyed = []
	_menu.window_rows = 0
	_menu.build(items, screen.x)
	_menu.position = Vector2(0, top)
	_hint = UiKit.label(hint, Rect2(0, screen.y - 40.0, screen.x, 20.0), Color(0.74, 0.80, 0.92),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_hint)


## 名册列表：一行一个角色，名字 / 等级 / 玩了多久 / 上次存档。已经被另一个座位选走的置灰。
func _draw_list(screen: Vector2) -> void:
	_listed = Progress.by_recent()
	var box := Rect2((screen.x - LIST_BOX.x) / 2.0, 46.0, LIST_BOX.x, LIST_BOX.y)
	_body.add_child(UiKit.window(box))
	# 标题要落在窗口**里面**：九宫格的边框占 32px，压在边上会被框子切掉
	_body.add_child(UiKit.label("PLAYER %d" % (_seat + 1), Rect2(box.position + Vector2(0, 30.0), Vector2(box.size.x, 22.0)),
		UiKit.CYAN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	var left := box.position.x + 40.0
	var head := box.position.y + 60.0
	for column in LIST_COLUMNS:
		_body.add_child(UiKit.label(column[0], Rect2(Vector2(left + column[1], head), Vector2(column[2], 20.0)), UiKit.DIM))
	# 滚到第几个了（存档多过一屏时才写）。摆在标题那一行的右头，不去挤 SAVED 那一列
	_scroll_mark = UiKit.label("", Rect2(box.position + Vector2(LIST_EDGE, 30.0),
		Vector2(box.size.x - LIST_EDGE * 2.0 - 8.0, 22.0)), UiKit.DIM,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	_body.add_child(_scroll_mark)
	var rows: Array[String] = []
	var taken: Array[int] = []
	for i in _listed.size():
		rows.append("")
		if Progress.seat_of(_listed[i]) >= 0 and Progress.seat_of(_listed[i]) != _seat:
			taken.append(i)
	_menu.wide_highlight = true
	_menu.row_boxes = []
	_menu.window_rows = ROWS
	# 选中框正好贴着边框内沿：左边 32、宽度 480 - 32 × 2
	_menu.build(rows, box.size.x - LIST_EDGE * 2.0)
	_menu.position = Vector2(box.position.x + LIST_EDGE, head + 22.0)
	_menu.greyed = taken
	_row_labels.clear()
	for i in _menu.rows_shown():
		var y := head + 22.0 + i * MenuList.ROW_HEIGHT
		var line: Array[Label] = []
		for column in LIST_COLUMNS:
			var label := UiKit.label("", Rect2(Vector2(left + column[1], y), Vector2(column[2], 20.0)), UiKit.WHITE)
			_body.add_child(label)
			line.append(label)
		_row_labels.append(line)
	_fill_rows()
	if not _menu.moved.is_connected(_on_list_moved):
		_menu.moved.connect(_on_list_moved)
	_hint = UiKit.label("A LOAD    X DELETE    B BACK",
		Rect2(0, _screen().y - 40.0, _screen().x, 20.0), Color(0.74, 0.80, 0.92),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_hint)


func _on_list_moved(_index: int) -> void:
	if _page == Page.LOAD_LIST:
		_fill_rows()


## 把现在滚到的那几个角色写进那几行里。**节点不重摆，只换文字**——
## 滚动时重建一堆 Label 会让这一页每按一下就闪一下。
func _fill_rows() -> void:
	var first := _menu.first_row()
	for i in _row_labels.size():
		var at := first + i
		var line: Array = _row_labels[i]
		if at >= _listed.size():
			for label: Label in line:
				label.text = ""
			continue
		var profile := _listed[at]
		var texts := [profile.character_name, str(profile.level),
			played_text(profile.played_seconds), saved_text(profile.saved_at)]
		var tint := UiKit.DIM.darkened(0.35) if _menu.greyed.has(at) else UiKit.WHITE
		for j in line.size():
			var label: Label = line[j]
			label.text = texts[j]
			label.add_theme_color_override("font_color", tint)
	if _scroll_mark != null:
		_scroll_mark.text = ("%d/%d" % [_menu.index + 1, _listed.size()]
			if _listed.size() > _row_labels.size() else "")


## 玩了多久，写成 `2H 14M`。
static func played_text(seconds: float) -> String:
	var whole := int(seconds)
	return "%dH %02dM" % [whole / 3600, (whole % 3600) / 60]


## 存档时间里的日期和时分，写成 `09 21 22 40`（全用空格分隔，最省事也最耐看）。
static func saved_text(stamp: String) -> String:
	if stamp.length() < 16:
		return ""
	return "%s %s %s %s" % [stamp.substr(5, 2), stamp.substr(8, 2), stamp.substr(11, 2), stamp.substr(14, 2)]


# ---------------------------------------------------------------- 选了什么

func _on_chosen(index: int) -> void:
	match _page:
		Page.TITLE:
			if index == 2:
				get_tree().quit()
				return
			Session.set_player_count(index + 1)
			_seat = 0
			_loaded.clear()
			_show(Page.SOURCE)
		Page.SOURCE:
			match index:
				0:
					Progress.take_seat(_seat, Progress.fresh(_seat))
					_loaded.erase(_seat)
					_next_seat()
				1:
					if Progress.roster.is_empty():
						return
					_show(Page.LOAD_LIST)
				2:
					_on_cancelled()
		Page.LOAD_LIST:
			Progress.take_seat(_seat, _listed[index])
			if not _loaded.has(_seat):
				_loaded.append(_seat)
			_next_seat()
		Page.CONFIRM:
			if index == 1:
				Progress.remove(_doomed)
			_doomed = null
			_show(Page.LOAD_LIST)
		Page.STAGE:
			var picked := _unlocked()
			if index < picked.size():
				start_game(picked[index])


func _on_cancelled() -> void:
	match _page:
		Page.TITLE:
			pass
		Page.SOURCE:
			if _seat == 0:
				_show(Page.TITLE)
			else:
				_seat -= 1
				_show(Page.SOURCE)
		Page.LOAD_LIST:
			_show(Page.SOURCE)
		Page.CONFIRM:
			_doomed = null
			_show(Page.LOAD_LIST)
		Page.SETUP:
			pass
		Page.STAGE:
			_show(Page.SETUP)


## 项目设置里的开关：打开时**所有关卡都能选**，不管打到哪儿了。
## 做关卡的时候要随时跳到任意一关去试，不然每调一次第 5 关就得先把前四关打一遍。
## **发布前记得关掉**——开着就没有「一关一关打过去」这回事了。
const UNLOCK_ALL := "game/unlock_all_levels"


## 解锁了的那几关。**双人取两个人里最高的**：老手带新人时朋友也能一起往后打，
## 不用卡着新角色重打十几关（通关时两个人的进度都往前推，见 `main.gd._unlock_next()`）。
func _unlocked() -> Array[LevelInfo]:
	var all := Catalog.levels()
	if ProjectSettings.get_setting(UNLOCK_ALL, false):
		return all
	var reached := 1
	for index in Session.player_count:
		reached = maxi(reached, Progress.of(index).reached)
	return all.slice(0, clampi(reached, 1, all.size()))


## 人物都设置好了：只解锁了一关就直接开打，有得选才问一句。
func _after_setup() -> void:
	if _unlocked().size() <= 1:
		start_game(Catalog.first_level())
		return
	_show(Page.STAGE)


## 从人物设置退回来：回到第一个座位重新选 NEW / LOAD。
func _back_to_source() -> void:
	_seat = 0
	_show(Page.SOURCE)


## 这个座位选完了：还有人没选就轮到下一个，都选完就去设置人物。
func _next_seat() -> void:
	_seat += 1
	if _seat < Session.player_count:
		_show(Page.SOURCE)
	else:
		_show(Page.SETUP)


## 开打。**关卡加载之前**先把「打的是哪一关」定下来：
## 敌人和平台在各自的 `_ready` 里就要问这一关的素材包要外观、按倍率缩放强度。
func start_game(level: LevelInfo = null) -> void:
	var going: LevelInfo = level if level != null else Catalog.first_level()
	Stage.use(going)
	Progress.save_game()
	if going != null:
		get_tree().change_scene_to_file(going.scene_path)
