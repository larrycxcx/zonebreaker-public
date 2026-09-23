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
## 想改名字。
signal rename_wanted
## 想换某个位置的装备。
signal gear_wanted(slot: int)

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
## 光标在每一行的纵向位置（相对窗口顶边）。属性那几行和装备那块高度不一样，单独排。
const ROW_TOPS := [NAME_Y + 4.0, LOOK_Y + 16.0, STATS_Y, STATS_Y + 18.0, STATS_Y + 36.0, STATS_Y + 54.0,
	GEAR_Y + 22.0, FOOT_Y, FOOT_Y]

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
var _points: Label
var _money: Label
var _detail: Label
var _detail_stats: Label
var _shop: Label
var _accept: Label
var _portraits: Array[ColorRect] = []
var _stat_rows: Array[Dictionary] = []
var _slot_boxes: Array[ColorRect] = []
var _slot_icons: Array[TextureRect] = []
## 另一个玩家选了哪个外观（那个就不能选了，两个人长一样同屏分不清）。
var _taken := &""


func build(player: Player, index: int, taken_look: StringName) -> void:
	who = player
	progress = player.progress
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	add_child(UiKit.window(Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))))
	var left := 26.0
	var wide := WIDTH - 52.0
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
	for i in Balance.STATS.size():
		var top := STATS_Y + i * 18.0
		var stat: StringName = Balance.STATS[i]
		var colour: Color = UiKit.STAT_COLORS.get(stat, UiKit.WHITE)
		add_child(UiKit.picture("%s/stat_%s.png" % [UiKit.DIR, stat], Vector2(left + 10.0, top - 7.0), colour))
		var name_label := UiKit.label(STAT_LABELS[stat], Rect2(left + 46.0, top, 90.0, 18.0), UiKit.DIM)
		var value := UiKit.label("", Rect2(left + 126.0, top, 56.0, 18.0), colour, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bonus := UiKit.label("", Rect2(left + 190.0, top, 56.0, 18.0), UiKit.GOLD)
		for node in [name_label, value, bonus]:
			add_child(node)
		_stat_rows.append({"name": name_label, "value": value, "bonus": bonus})
	_points = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GOLD)
	add_child(_points)
	_money = UiKit.label("", Rect2(left, POINTS_Y, wide, 18.0), UiKit.GREEN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_money)
	for i in Equipment.Slot.size():
		var at := Vector2(left + (i % SLOTS_PER_LINE) * (SLOT.x + 4.0), GEAR_Y + (i / SLOTS_PER_LINE) * (SLOT.y + 4.0))
		var box := UiKit.box(Rect2(at, SLOT))
		add_child(box)
		_slot_boxes.append(box)
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
	_menu.cursor_at_left = true
	add_child(_menu)
	_menu.build(_blank(ROW_COUNT), 12.0)
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
	_name.text = progress.character_name + ("" if can_rename else " *")
	_points.text = "POINTS %d" % progress.points
	_points.add_theme_color_override("font_color", UiKit.GOLD if progress.points > 0 else UiKit.DIM)
	# **字模里没有 `$`**（素材包的符号表里就没有），写出来是个缺字方块，所以用 CASH 这个词
	_money.text = "CASH %d" % progress.money
	_ready_mark.text = "READY" if confirmed else ""
	for i in LOOKS.size():
		var chosen := i == look_index()
		var blocked := LOOKS[i] == _taken
		_portraits[i].color = UiKit.GOLD if chosen else (Color(0.2, 0.22, 0.34) if blocked else Color(0.27, 0.35, 0.55))
	for i in Balance.STATS.size():
		var stat: StringName = Balance.STATS[i]
		var added: float = progress.allocated.get(stat, 0) * progress.balance.per_point.get(stat, 0.0)
		_stat_rows[i]["value"].text = str(roundi(progress.stat(stat)))
		_stat_rows[i]["bonus"].text = "+%d" % roundi(added) if added > 0.0 else ""
	for i in Equipment.Slot.size():
		var item := progress.gear(i)
		_slot_icons[i].texture = item.icon if item != null else null
		_slot_boxes[i].color = UiKit.GOLD if i == slot and _menu.index == Row.GEAR else Color(0.27, 0.35, 0.55)
	var picked := progress.gear(slot)
	_detail.text = picked.display_name if picked != null else "%s EMPTY" % Equipment.SLOT_NAMES[slot]
	_detail_stats.text = _bonus_text(picked)
	_shop.add_theme_color_override("font_color", UiKit.WHITE if progress.money > 0 else UiKit.DIM.darkened(0.3))
	_accept.add_theme_color_override("font_color", UiKit.GREEN if confirmed else UiKit.WHITE)
	_place_cursor()


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


func _place_cursor() -> void:
	if _menu == null:
		return
	_menu.position = Vector2(8.0, ROW_TOPS[mini(_menu.index, ROW_TOPS.size() - 1)])


func _on_chosen(index: int) -> void:
	match _row_kind(index):
		Row.NAME:
			if can_rename:
				rename_wanted.emit()
		Row.STAT:
			if progress.spend_point(Balance.STATS[index - Row.STAT]):
				refresh()
		Row.GEAR:
			gear_wanted.emit(slot)
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
