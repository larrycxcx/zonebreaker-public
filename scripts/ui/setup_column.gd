class_name SetupColumn
extends Control
## 人物设置界面里的一栏：一个玩家的名字、外观、加点、装备。
##
## 一栏 = **一列从上往下选的行**：名字 / 外观 / 四个属性 / 装备 / 商店 / 确定。
## 上下换行，左右在行内选（换角色、在八个装备格之间挪），A 确认，B 返回。
## 这样只有一套导航规则，手柄上的手不用换位置，两栏也能各按各的。
##
## **装备那一行是只读的**：左右挪着看身上穿的是什么，按 A 不会换——换装备统一在商店的背包页
## （`ShopColumn`）。不这么分的话同一件事有两个入口，两边的规则（等级门槛、卖出）迟早要打架。
##
## 界面一律英文大写（素材包的字模没有汉字，见 CLAUDE.md）。

## 这一栏确定了 / 取消了确定。
signal readiness_changed(confirmed: bool)
## 这一栏按了返回（还没确定的时候）。
signal backed_out
## 打开了 / 关上了一个盖在这一栏上的小面板（改名字）。
## 外面据此知道这一栏正忙着，别的地方先别抢键。
signal overlay_changed(open: bool)
## 这一栏要进商店（整个界面共用一个商店，所以由 `SetupScreen` 去开）。
signal shop_requested

const WIDTH := 300.0
const HEIGHT := 338.0
## 行的意思。属性那四行是 STAT 到 GEAR 之间。
enum Row { NAME, LOOK, STAT, GEAR = 6, SHOP, ACCEPT }
const ROW_COUNT := 9

## 头像格比素材包那张 `portrait.png`（22×36）各边大 2px，人整个装在框里。
## 图变了这里要跟着变，`test_cyberpunk_skin.gd` 有一条量着。
const PORTRAIT := Vector2(26, 40)
## 装备格：图标 32×32、里头的内容最大 30×30，格子做到 36 图标四周才留得出两三像素。
## 34 的时候图标四角正好压在描边上，看着就是「东西太大装不下」；
## 再大就挤不下了——一栏总共就 338 高，八个格子两行，上面还有名字、头像、四个属性。
const SLOT := Vector2(36, 36)
const SLOTS_PER_LINE := 4

## 一栏里每一块从上往下摆在哪（相对窗口顶边）。挤是挤了点，但两栏要同时塞进 640×360。
const TITLE_Y := 16.0
const NAME_Y := 34.0
const LOOK_Y := 60.0
const STATS_Y := 106.0
## 属性一行占多高。**由图标说了算，不是由字说了算**：字只有 10px 高，但属性图标那 32×32 的图里
## 画着的东西有 20px（`stat_*.png` 的 y 6..25）。行距 16 的时候上下两行的图标会叠在一起、
## 选中的金框也盖到邻居的图标上（试玩截图里一眼就能看见）。
const STAT_STEP := 20.0
const POINTS_Y := 186.0
const GEAR_Y := 206.0
const DETAIL_Y := 282.0
const FOOT_Y := 300.0

## 可选角色，顺序就是界面上从左到右——**扫 `characters/` 目录**得来的（见 `Catalog`），
## 不在代码里点名，所以 DLC 丢个 `.tres` 进来就多一个角色。
static func looks() -> Array[StringName]:
	var keys: Array[StringName] = []
	for look in Catalog.looks():
		keys.append(look.key)
	return keys
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
## 盖在这一栏上的小面板：改名字的字母格。
var _grid: LetterGrid
## 另一个玩家选了哪个外观（那个就不能选了，两个人长一样同屏分不清）。
var _taken := &""
## 这一栏能选的几个角色（`Catalog.looks()` 的键）。扫一次记下来，不是每帧去翻目录。
var _looks: Array[StringName] = []
## 这一栏里内容那一片的左边和宽度（`_boxes()` 要按它算每一行的选中框）。
var _left := 0.0
var _wide := 0.0


func build(player: Player, index: int, taken_look: StringName) -> void:
	who = player
	progress = player.progress
	_looks = looks()
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
	for i in _looks.size():
		var at := Vector2(left + i * (PORTRAIT.x + 8.0), LOOK_Y)
		var box := UiKit.box(Rect2(at, PORTRAIT))
		add_child(box)
		_portraits.append(box)
		var face := UiKit.picture("", at + Vector2(2.0, 2.0))
		face.texture = UiKit.portrait(_looks[i])
		add_child(face)
	# 头像右边那块空地：这个角色练到几级了（读档进来的一眼就看得到）。
	# 经验值没跟着写：那一行放得下 `LEVEL 10`，放不下 `XP 3500/3844`（130px 的地方要 150px）。
	var beside := left + _looks.size() * (PORTRAIT.x + 8.0) + 4.0
	_level = UiKit.label("", Rect2(beside, LOOK_Y + 12.0, left + wide - beside, 18.0), UiKit.GOLD)
	add_child(_level)
	for i in Balance.STATS.size():
		var top := STATS_Y + i * STAT_STEP
		var stat: StringName = Balance.STATS[i]
		var colour: Color = UiKit.STAT_COLORS.get(stat, UiKit.WHITE)
		# 图标 32×32、里面画着的那块在 y 6..25，摆在 top - 6 正好把一行 20px 填满、不越界
		var icon := UiKit.picture("%s/stat_%s.png" % [UiKit.DIR, stat], Vector2(left + 10.0, top - 6.0), colour)
		add_child(icon)
		var name_label := UiKit.label(STAT_LABELS[stat], Rect2(left + 46.0, top, 90.0, 18.0), UiKit.DIM)
		var value := UiKit.label("", Rect2(left + 122.0, top, 56.0, 18.0), colour, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bonus := UiKit.label("", Rect2(left + 202.0, top, 46.0, 18.0), UiKit.GOLD)
		# 选中这一行时，数字两边冒出一对小箭头，提示可以左右加减
		var less := UiKit.label("<", Rect2(left + 104.0, top, 14.0, 18.0), UiKit.GOLD, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		var more := UiKit.label(">", Rect2(left + 182.0, top, 14.0, 18.0), UiKit.GOLD, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
		for node in [name_label, value, bonus, less, more]:
			add_child(node)
		_stat_rows.append({"name": name_label, "value": value, "bonus": bonus, "less": less,
			"more": more, "icon": icon})
	_points = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GOLD)
	add_child(_points)
	_money = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GREEN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_money)
	for i in Equipment.Slot.size():
		var at := slot_rect(i).position
		add_child(UiKit.box(Rect2(at, SLOT)))
		# 图标在格子正中：(36 - 32) / 2 = 2。原先写的是 at - 1，
		# 整张图往左上顶出一格、四角压在描边上，看着就是「太大装不下」。
		var icon := UiKit.picture("", at + Vector2(2.0, 2.0))
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
	# **读档进来直接停在 ACCEPT 上**：名字改不了，点数和装备都是上次留下的，
	# 多半是按一下就开打；要改什么再往上走。新建的角色照旧从第一行（名字）开始。
	if not can_rename:
		_menu.index = Row.ACCEPT
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	_menu.nudged.connect(_on_nudged)
	# 换行也要重画：属性行的 `<` `>`、SHOP / ACCEPT 的亮暗都跟着光标在哪走。
	# （`go_to_row()` 自己会调 refresh，所以只用按键走的那条路缺这一下——测试差点没抓到。）
	_menu.moved.connect(func(_index: int) -> void: refresh())
	set_taken_look(taken_look)


func set_taken_look(taken: StringName) -> void:
	_taken = taken
	if progress != null and progress.look == _taken:
		_pick_look(1)
	refresh()


func look_index() -> int:
	return maxi(0, _looks.find(progress.look))


func row() -> int:
	return _menu.index


func menu_list() -> MenuList:
	return _menu


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
	_money.text = "CASH %s" % UiKit.number(progress.money)
	_ready_mark.text = "READY" if confirmed else ""
	for i in _looks.size():
		var chosen := i == look_index()
		var blocked := _looks[i] == _taken
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
	# **只有光标那一行是亮的**：SHOP / ACCEPT 一直画成纯白的话，它们比金框还抢眼，
	# 读档进来名字又是淡的，看上去就像光标默认停在 ACCEPT 上。
	var on_shop := _menu != null and _menu.index == Row.SHOP
	var on_accept := _menu != null and _menu.index == Row.ACCEPT
	# 没钱也进得去：商店里还能卖东西，钱是在那儿挣出来的
	_shop.add_theme_color_override("font_color", UiKit.WHITE if on_shop else UiKit.DIM)
	_accept.add_theme_color_override("font_color",
		UiKit.GREEN if confirmed else (UiKit.WHITE if on_accept else UiKit.DIM))
	# 装备那一行的选中框框的是**当前那一格**，所以挪格子要重新给一遍
	if _menu != null:
		_menu.row_boxes = _boxes()


## 这一格里那件东西的数字。
## **武器写的是它到底干什么用的**（每发多少伤害、每秒几发），不是属性加成——
## 武器的强弱全在 `power` 和 `cooldown` 里，不写出来的话，两把枪看着只差一个名字（试玩反馈）。
## 防具还是写加成（ATK +2  SPD +5）。
func _bonus_text(item: Equipment) -> String:
	if item == null:
		return ""
	var weapon := item as Weapon
	if weapon != null:
		return gun_text(progress.weapon_numbers(weapon))
	var parts := []
	for stat: StringName in Balance.STATS:
		var amount: float = item.bonuses.get(stat, 0.0)
		if amount != 0.0:
			parts.append("%s %+d" % [String(STAT_LABELS[stat]).substr(0, 3), roundi(amount)])
	return "  ".join(parts)


## 一把武器的数字写成一行：`DMG 10  RATE 6.7/S`。商店那边也用它，所以是 static 的。
## 弹药无限的根本不在表里（见 `PlayerProgress.weapon_numbers()`），所以这儿不用再判一次。
static func gun_text(numbers: Dictionary) -> String:
	if numbers.is_empty():
		return ""
	var parts := []
	if numbers.has(&"damage"):
		parts.append("DMG %d" % roundi(numbers[&"damage"]))
	if numbers.has(&"rate"):
		parts.append("RATE %.1f/S" % numbers[&"rate"])
	if numbers.has(&"ammo"):
		parts.append("AMMO %d" % roundi(numbers[&"ammo"]))
	return "  ".join(parts)


## 每一行的选中框框住哪一块。**框住的是那块内容本身**（名字框、三个头像、一行属性、整片装备格），
## 不是一条等高的空行——这样一眼看得出选的是什么。
func _boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	boxes.append(Rect2(_left - 3.0, NAME_Y - 2.0, _wide + 6.0, 26.0))
	boxes.append(Rect2(_left - 3.0, LOOK_Y - 3.0, PORTRAIT.x * 3.0 + 16.0 + 6.0, PORTRAIT.y + 6.0))
	for i in Balance.STATS.size():
		boxes.append(Rect2(_left - 3.0, STATS_Y + i * STAT_STEP - 1.0, _wide + 6.0, STAT_STEP))
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
			pass          # 只读：换装备在商店的背包页
		Row.SHOP:
			shop_requested.emit()
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
	for _try in _looks.size():
		at = wrapi(at + direction, 0, _looks.size())
		if _looks[at] != _taken:
			break
	progress.look = _looks[at]
	refresh()


# ---------------------------------------------------------------- 改名字

## 正忙着改名字吗（忙着的时候这一栏自己的上下选不动）。
func busy() -> bool:
	return is_instance_valid(_grid)


func grid() -> LetterGrid:
	return _grid if is_instance_valid(_grid) else null


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
	_menu.ignore_this_frame()
	refresh()
	overlay_changed.emit(false)
