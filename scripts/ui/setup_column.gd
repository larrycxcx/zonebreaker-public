class_name SetupColumn
extends Control
## 人物设置界面里的一栏：一个玩家的名字、外观、加点、装备。
##
## 一栏 = **一列从上往下选的行**：名字 / 外观 / 四个属性 / 装备 / 商店 / 确定。
## 上下换行，左右在行内选（换角色、在八个装备格之间挪），A 确认，B 返回。
## 这样只有一套导航规则，手柄上的手不用换位置，两栏也能各按各的。
##
## 界面一律英文大写（素材包的字模没有汉字，见 CLAUDE.md）。

## 这一栏确定了 / 取消了确定。
signal readiness_changed(confirmed: bool)
## 这一栏按了返回（还没确定的时候）。
signal backed_out
## 打开了 / 关上了一个盖在这一栏上的小面板（改名字、换装备）。
## 外面据此知道这一栏正忙着，别的地方先别抢键。
signal overlay_changed(open: bool)

const WIDTH := 300.0
const HEIGHT := 338.0
## 行的意思。属性那四行是 STAT 到 GEAR 之间。
enum Row { NAME, LOOK, STAT, GEAR = 6, SHOP, ACCEPT }
const ROW_COUNT := 9

## 头像格比裁出来的那块（`UiKit.PORTRAIT_CROP`）各边大 2px，人整个装在框里。
const PORTRAIT := Vector2(30, 43)
## 装备格比图标（32×32）各边大 1px，图标不会顶出格子。
const SLOT := Vector2(34, 34)
const SLOTS_PER_LINE := 4

## 一栏里每一块从上往下摆在哪（相对窗口顶边）。挤是挤了点，但两栏要同时塞进 640×360。
const TITLE_Y := 18.0
const NAME_Y := 38.0
const LOOK_Y := 64.0
const STATS_Y := 114.0
const POINTS_Y := 190.0
const GEAR_Y := 208.0
const DETAIL_Y := 282.0
const FOOT_Y := 300.0

## 三个可选角色，顺序就是界面上从左到右。
const LOOKS: Array[StringName] = [&"biker", &"punk", &"cyborg"]
const STAT_LABELS := {&"life": "LIFE", &"attack": "ATTACK", &"defense": "DEFENSE", &"speed": "SPEED"}

var who: Player
var progress: PlayerProgress
## 名字能不能改（读档进来的不能改）。
var can_rename := true
## 确定了没有。**别叫 `ready`**：那是 Node 自带的信号名，重名会让整个脚本解析不过。
var confirmed := false
## 装备格选到第几个。
var slot := 0

var _menu: MenuList
var _ready_mark: Label
var _name: Label
var _level: Label
var _points: Label
var _money: Label
var _detail: Label
var _detail_stats: Label
var _shop: Label
var _accept: Label
var _portraits: Array[ColorRect] = []
var _stat_rows: Array[Dictionary] = []
var _slot_icons: Array[TextureRect] = []
## 盖在这一栏上的小面板：改名字的字母格 / 换装备的列表。同时只会有一个。
var _grid: LetterGrid
var _bag: Control
var _bag_menu: MenuList
var _bag_items: Array[Equipment] = []
## 另一个玩家选了哪个外观（那个就不能选了，两个人长一样同屏分不清）。
var _taken := &""
## 这一栏里内容那一片的左边和宽度（`_boxes()` 要按它算每一行的选中框）。
var _left := 0.0
var _wide := 0.0


func build(player: Player, index: int, taken_look: StringName) -> void:
	who = player
	progress = player.progress
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	add_child(UiKit.window(Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))))
	var left := 26.0
	var wide := WIDTH - 52.0
	_left = left
	_wide = wide
	add_child(UiKit.label("PLAYER %d" % (index + 1), Rect2(left, TITLE_Y, wide, 18.0), UiKit.GOLD))
	_ready_mark = UiKit.label("", Rect2(left, TITLE_Y, wide, 18.0), UiKit.GREEN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_ready_mark)
	add_child(UiKit.box(Rect2(left, NAME_Y, wide, 22.0)))
	_name = UiKit.label("", Rect2(left + 6.0, NAME_Y + 2.0, wide - 12.0, 18.0), UiKit.CYAN)
	add_child(_name)
	for i in LOOKS.size():
		var at := Vector2(left + i * (PORTRAIT.x + 8.0), LOOK_Y)
		var box := UiKit.box(Rect2(at, PORTRAIT))
		add_child(box)
		_portraits.append(box)
		var face := UiKit.picture("", at + Vector2(2.0, 2.0))
		face.texture = UiKit.portrait(LOOKS[i])
		add_child(face)
	# 头像右边那块空地：这个角色练到几级了（读档进来的一眼就看得到）。
	# 经验值没跟着写：那一行放得下 `LEVEL 10`，放不下 `XP 3500/3844`（130px 的地方要 150px）。
	var beside := left + LOOKS.size() * (PORTRAIT.x + 8.0) + 4.0
	_level = UiKit.label("", Rect2(beside, LOOK_Y + 12.0, left + wide - beside, 18.0), UiKit.GOLD)
	add_child(_level)
	for i in Balance.STATS.size():
		var top := STATS_Y + i * 18.0
		var stat: StringName = Balance.STATS[i]
		var colour: Color = UiKit.STAT_COLORS.get(stat, UiKit.WHITE)
		add_child(UiKit.picture("%s/stat_%s.png" % [UiKit.DIR, stat], Vector2(left + 10.0, top - 7.0), colour))
		var name_label := UiKit.label(STAT_LABELS[stat], Rect2(left + 46.0, top, 90.0, 18.0), UiKit.DIM)
		var value := UiKit.label("", Rect2(left + 122.0, top, 56.0, 18.0), colour, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bonus := UiKit.label("", Rect2(left + 202.0, top, 46.0, 18.0), UiKit.GOLD)
		# 选中这一行时，数字两边冒出一对小箭头，提示可以左右加减
		var less := UiKit.label("<", Rect2(left + 104.0, top, 14.0, 18.0), UiKit.GOLD, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		var more := UiKit.label(">", Rect2(left + 182.0, top, 14.0, 18.0), UiKit.GOLD, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		for node in [name_label, value, bonus, less, more]:
			add_child(node)
		_stat_rows.append({"name": name_label, "value": value, "bonus": bonus, "less": less, "more": more})
	_points = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GOLD)
	add_child(_points)
	_money = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GREEN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_money)
	for i in Equipment.Slot.size():
		var at := slot_rect(i).position
		add_child(UiKit.box(Rect2(at, SLOT)))
		var icon := UiKit.picture("", at - Vector2(1.0, 1.0))
		add_child(icon)
		_slot_icons.append(icon)
	_detail = UiKit.label("", Rect2(left, DETAIL_Y, wide, 18.0), UiKit.CYAN)
	add_child(_detail)
	_detail_stats = UiKit.label("", Rect2(left, DETAIL_Y, wide, 18.0), UiKit.DIM, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_detail_stats)
	_shop = UiKit.label("SHOP", Rect2(left, FOOT_Y, wide / 2.0, 18.0), UiKit.DIM)
	add_child(_shop)
	_accept = UiKit.label("ACCEPT", Rect2(left + wide / 2.0, FOOT_Y, wide / 2.0, 18.0), UiKit.WHITE,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_accept)
	_menu = MenuList.new()
	_menu.listens_to = player.player_index
	add_child(_menu)
	_menu.build(_blank(ROW_COUNT), WIDTH)
	_menu.position = Vector2.ZERO
	_menu.row_boxes = _boxes()
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	_menu.nudged.connect(_on_nudged)
	set_taken_look(taken_look)


func set_taken_look(taken: StringName) -> void:
	_taken = taken
	if progress != null and progress.look == _taken:
		_pick_look(1)
	refresh()


func look_index() -> int:
	return maxi(0, LOOKS.find(progress.look))


func row() -> int:
	return _menu.index


## 光标挪到第几行（测试用；界面上就是按上下）。
func go_to_row(index: int) -> void:
	_menu.index = clampi(index, 0, ROW_COUNT - 1)
	refresh()


func _blank(count: int) -> Array[String]:
	var rows: Array[String] = []
	for i in count:
		rows.append("")
	return rows


func refresh() -> void:
	# 读档进来的名字改不了，画淡一点表示（别用 `*` 之类的符号，字模里没有）
	_name.text = progress.character_name
	_name.add_theme_color_override("font_color", UiKit.CYAN if can_rename else UiKit.DIM)
	_level.text = "LEVEL %d" % progress.level
	_points.text = "POINTS %d" % progress.points
	_points.add_theme_color_override("font_color", UiKit.GOLD if progress.points > 0 else UiKit.DIM)
	# **字模里没有 `$`**（素材包的符号表里就没有），写出来是个缺字方块，所以用 CASH 这个词
	_money.text = "CASH %d" % progress.money
	_ready_mark.text = "READY" if confirmed else ""
	for i in LOOKS.size():
		var chosen := i == look_index()
		var blocked := LOOKS[i] == _taken
		# 选中的那个用**绿色**，不用金色：金框专门表示「光标现在在哪」，两个都金的话分不清
		_portraits[i].color = UiKit.GREEN if chosen else (Color(0.2, 0.22, 0.34) if blocked else Color(0.27, 0.35, 0.55))
	for i in Balance.STATS.size():
		var stat: StringName = Balance.STATS[i]
		# 金色那列写的是**投了几点**，不是属性涨了多少：每点加的量各不相同
		# （生命 +10、攻击 +1、防御速度 +5），照实写出来玩家会以为自己按了不一样的键。
		var spent: int = progress.allocated.get(stat, 0)
		_stat_rows[i]["value"].text = str(roundi(progress.stat(stat)))
		_stat_rows[i]["bonus"].text = "+%d" % spent if spent > 0 else ""
		var on_this := _menu != null and _menu.index == Row.STAT + i
		_stat_rows[i]["less"].visible = on_this and progress.allocated.get(stat, 0) > 0
		_stat_rows[i]["more"].visible = on_this and progress.points > 0
	for i in Equipment.Slot.size():
		var item := progress.gear(i)
		_slot_icons[i].texture = item.icon if item != null else null
	var picked := progress.gear(slot)
	_detail.text = picked.display_name if picked != null else "%s EMPTY" % Equipment.SLOT_NAMES[slot]
	_detail_stats.text = _bonus_text(picked)
	_shop.add_theme_color_override("font_color", UiKit.WHITE if progress.money > 0 else UiKit.DIM.darkened(0.3))
	_accept.add_theme_color_override("font_color", UiKit.GREEN if confirmed else UiKit.WHITE)
	# 装备那一行的选中框框的是**当前那一格**，所以挪格子要重新给一遍
	if _menu != null:
		_menu.row_boxes = _boxes()


## 一件装备加了些什么，写成 ATK +2  SPD +5。
func _bonus_text(item: Equipment) -> String:
	if item == null:
		return ""
	var parts := []
	for stat: StringName in Balance.STATS:
		var amount: float = item.bonuses.get(stat, 0.0)
		if amount != 0.0:
			parts.append("%s %+d" % [String(STAT_LABELS[stat]).substr(0, 3), roundi(amount)])
	return "  ".join(parts)


## 每一行的选中框框住哪一块。**框住的是那块内容本身**（名字框、三个头像、一行属性、整片装备格），
## 不是一条等高的空行——这样一眼看得出选的是什么。
func _boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	boxes.append(Rect2(_left - 3.0, NAME_Y - 2.0, _wide + 6.0, 26.0))
	boxes.append(Rect2(_left - 3.0, LOOK_Y - 3.0, PORTRAIT.x * 3.0 + 16.0 + 6.0, PORTRAIT.y + 6.0))
	for i in Balance.STATS.size():
		boxes.append(Rect2(_left - 3.0, STATS_Y + i * 18.0 - 1.0, _wide + 6.0, 20.0))
	boxes.append(slot_rect(slot).grow(2.0))
	boxes.append(Rect2(_left - 3.0, FOOT_Y - 1.0, _wide / 2.0, 20.0))
	boxes.append(Rect2(_left + _wide / 2.0 - 3.0, FOOT_Y - 1.0, _wide / 2.0 + 6.0, 20.0))
	return boxes


## 第几个装备格在哪（选中框要框住的就是这一格）。
func slot_rect(index: int) -> Rect2:
	return Rect2(Vector2(_left + (index % SLOTS_PER_LINE) * (SLOT.x + 4.0),
		GEAR_Y + (index / SLOTS_PER_LINE) * (SLOT.y + 4.0)), SLOT)


func _on_chosen(index: int) -> void:
	match _row_kind(index):
		Row.NAME:
			if can_rename:
				_open_grid()
		Row.STAT:
			# A 和「右」一个意思，按哪个都行
			if progress.spend_point(Balance.STATS[index - Row.STAT]):
				refresh()
		Row.GEAR:
			_open_bag()
		Row.ACCEPT:
			confirmed = not confirmed
			refresh()
			readiness_changed.emit(confirmed)
		_:
			pass


func _on_cancelled() -> void:
	if confirmed:
		confirmed = false
		refresh()
		readiness_changed.emit(false)
	else:
		backed_out.emit()


func _on_nudged(index: int, direction: int) -> void:
	match _row_kind(index):
		Row.LOOK:
			_pick_look(direction)
		Row.STAT:
			# 右边加一点（加到点数用完），左边退一点（退到初始值为止）
			var stat: StringName = Balance.STATS[index - Row.STAT]
			if direction > 0:
				progress.spend_point(stat)
			else:
				progress.unspend_point(stat)
			refresh()
		Row.GEAR:
			slot = wrapi(slot + direction, 0, Equipment.Slot.size())
			refresh()
		_:
			pass


## 第几行是什么意思（属性那四行都算 STAT）。
func _row_kind(index: int) -> int:
	if index >= Row.STAT and index < Row.GEAR:
		return Row.STAT
	return index


## 换个外观，跳过另一个玩家已经选走的那个。
func _pick_look(direction: int) -> void:
	var at := look_index()
	for _try in LOOKS.size():
		at = wrapi(at + direction, 0, LOOKS.size())
		if LOOKS[at] != _taken:
			break
	progress.look = LOOKS[at]
	refresh()


# ---------------------------------------------------------------- 改名字 / 换装备

## 正忙着改名字或换装备吗（忙着的时候这一栏自己的上下选不动）。
func busy() -> bool:
	return is_instance_valid(_grid) or is_instance_valid(_bag)


func grid() -> LetterGrid:
	return _grid if is_instance_valid(_grid) else null


func bag() -> MenuList:
	return _bag_menu if is_instance_valid(_bag) else null


## 字母格盖在头像和属性那一片上，名字那一行还露着，边打边看得见。
func _open_grid() -> void:
	_menu.hide()
	_grid = LetterGrid.new()
	_grid.position = Vector2(30.0, LOOK_Y + 4.0)
	add_child(_grid)
	_grid.build(progress.character_name, who.player_index)
	# 光标用 `|`：字模里有它，下划线和星号都没有（写出来是缺字方块）
	_grid.changed.connect(func(text: String) -> void:
		_name.text = text + "|"
	)
	_grid.done.connect(_close_grid)
	_name.text = progress.character_name + "|"
	overlay_changed.emit(true)


## 打完收工：名字**重了或者空的就不改**，退回原来那个。
func _close_grid() -> void:
	var wanted := PlayerProgress.sanitize_name(_grid.text)
	if not wanted.is_empty() and not Progress.name_taken(wanted, progress):
		progress.character_name = wanted
	_grid.queue_free()
	_grid = null
	_menu.show()
	refresh()
	overlay_changed.emit(false)


## 换装备：列出背包里装得到这个位置上的东西，外加一个「空着」。
func _open_bag() -> void:
	_menu.hide()
	_bag_items = progress.fits(slot)
	var rows: Array[String] = ["NONE"]
	for item in _bag_items:
		rows.append(item.display_name)
	_bag = UiKit.box(Rect2(20.0, GEAR_Y - 6.0, WIDTH - 40.0, 24.0 + rows.size() * MenuList.ROW_HEIGHT))
	add_child(_bag)
	# 标题挂在盒子里面，关的时候跟着一起没
	_bag.add_child(UiKit.label(Equipment.SLOT_NAMES[slot], Rect2(10.0, 6.0, WIDTH - 60.0, 18.0), UiKit.DIM))
	_bag_menu = MenuList.new()
	_bag_menu.listens_to = who.player_index
	add_child(_bag_menu)
	_bag_menu.build(rows, WIDTH - 60.0)
	_bag_menu.position = Vector2(20.0, GEAR_Y + 18.0)
	_bag_menu.chosen.connect(_on_bag_chosen)
	_bag_menu.cancelled.connect(_close_bag)
	overlay_changed.emit(true)


func _on_bag_chosen(index: int) -> void:
	if index == 0:
		progress.unequip(slot)
	else:
		progress.equip(_bag_items[index - 1])
	_close_bag()


func _close_bag() -> void:
	if is_instance_valid(_bag):
		_bag.queue_free()
	if is_instance_valid(_bag_menu):
		_bag_menu.queue_free()
	_bag = null
	_bag_menu = null
	_menu.show()
	refresh()
	overlay_changed.emit(false)
