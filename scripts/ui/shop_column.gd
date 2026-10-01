class_name ShopColumn
extends Control
## 商店里一个玩家的那一栏：标签页 → 货架 → 选中那件的详情和对比。
##
## **每人一栏、左右并排、各按各的手柄**（和人物设置界面一个路子）。
## 从上到下：谁在买 + 身上多少钱 → 标签页（LB/RB 切）→ 列头 → 货架 → 详情。
##
## 八个标签：背包 + 武器 + 六个防具部位。一行摆不下，所以做成**走马灯**——
## 只显示前一个 / 当前 / 后一个，**当前那个底边打开、和下面的货架连成一体**，这是标签页的视觉线索。
## 背包那页叫 `BAG` 不叫 `INVENTORY`：一栏内宽只有 236px，`TRINKET` 当前 + `INVENTORY` 在旁边
## 就要 247px，右边那个会戳出九宫格边框（`test_the_rows_stay_inside_the_window` 量得出来）。
##
## 谁能干什么：
## - **背包页**：A 穿上（等级不够穿不上）、X 卖掉（半价，身上穿着的也能卖，会自动脱下来）
## - **商店各页**：A 买下。**等级不够照样能买**，只是穿不上——看得见目标才有奔头。
## - 买和卖要先确认一句；穿不用确认（穿错了再换回来就是）。
##
## **装备只能在这里换**：人物设置界面的那八个格子是只读的，换装备统一在商店里。
## 界面一律英文大写（素材包的字模没有汉字，见 CLAUDE.md）。

## 这一栏逛完了 / 又回来了。
signal readiness_changed(done: bool)

const WIDTH := 300.0
const HEIGHT := 328.0
## 一页最多显示几行，多了滚动。**行高必须和 `MenuList.ROW_HEIGHT` 一样**——
## 金框是菜单自己按行高画的，货架上的字是这里自己画的，两边对不上框就会偏。
const ROW := MenuList.ROW_HEIGHT
const ROWS := 5

## 标签页：名字 + 收哪几个装备位。背包那页 `slots` 留空 = 自己拥有的全部。
const TABS: Array[Dictionary] = [
	{"name": "BAG", "slots": []},
	{"name": "WEAPONS", "slots": [Equipment.Slot.GUN, Equipment.Slot.GRENADE]},
	{"name": "HEAD", "slots": [Equipment.Slot.HEAD]},
	{"name": "BODY", "slots": [Equipment.Slot.BODY]},
	{"name": "LEGS", "slots": [Equipment.Slot.LEGS]},
	{"name": "FEET", "slots": [Equipment.Slot.FEET]},
	{"name": "HANDS", "slots": [Equipment.Slot.HANDS]},
	{"name": "TRINKET", "slots": [Equipment.Slot.TRINKET]},
]

## 一栏里从上往下摆在哪（相对窗口顶边）。
const TITLE_Y := 12.0
const TAB_Y := 32.0
const TAB_H := 20.0
const LIST_Y := 52.0
const HEAD_Y := 56.0
const ROWS_Y := 78.0
const CARD_Y := 210.0
const CARD_H := 112.0
## 确认框：第一行字离框顶多远、每行多高。
const ASK_TOP := 30.0
const ASK_LINE := 15.0

const RED := Color(0.86, 0.36, 0.36)
## 等级不够那一行整行画暗（还选得中、也买得了，只是穿不上）。
const LOCKED := Color(0.38, 0.42, 0.54)
const TAB_ON_FILL := Color(0.17, 0.21, 0.37)
const TAB_OFF_FILL := Color(0.10, 0.12, 0.23)
const TAB_OFF_EDGE := Color(0.22, 0.27, 0.42)
const LIST_EDGE := Color(0.27, 0.35, 0.55)
const LIST_FILL := Color(0.12, 0.15, 0.28)
## 列头和货物分开：偏暖的颜色，底下再划一条线。
const HEAD_TINT := Color(0.64, 0.58, 0.42)
const HEAD_RULE := Color(0.30, 0.34, 0.50)

var who: Player
var progress: PlayerProgress
## 逛完了没有（双人时两个人都逛完才离开）。
var done := false
## 现在在第几页。
var tab := 0

var _menu: MenuList
var _tabs: Control
var _rows: Control
var _card: Control
var _money: Label
var _shelf: Array[Equipment] = []
## 买卖前那个确认框；开着的时候货架不收键（菜单 `hide()` 了）。
var _ask: Control
var _ask_menu: MenuList
var _ask_sell := false
## 逛完之后盖在这一栏上的「等另一个人」。
var _idle: Control
var _idle_menu: MenuList

var _left := 0.0
var _wide := 0.0


func build(player: Player) -> void:
	who = player
	progress = player.progress
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	# 内容那一片：**字要落在九宫格边框里面**（左右各 32），框比它往外让 6px，正好贴着边框内沿
	_left = UiKit.PANEL_MARGIN
	_wide = WIDTH - UiKit.PANEL_MARGIN * 2.0
	add_child(UiKit.window(Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))))
	add_child(UiKit.label("PLAYER %d" % (player.player_index + 1),
		Rect2(_left, TITLE_Y, 100.0, 18.0), UiKit.GOLD))
	add_child(UiKit.label("LV %d" % progress.level, Rect2(_left + 100.0, TITLE_Y, 60.0, 18.0),
		UiKit.DIM))
	_money = UiKit.label("", Rect2(_left, TITLE_Y, _wide, 18.0), UiKit.GREEN,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_money)
	_tabs = _holder()
	_rows = _holder()
	_card = _holder()
	_menu = MenuList.new()
	_menu.listens_to = player.player_index
	_menu.wide_highlight = true
	_menu.window_rows = ROWS
	add_child(_menu)
	# 金框是菜单按自己的行高画的，货架的字是这里自己画的：**两边的第一行要对齐**
	_menu.position = Vector2(_left - 6.0, ROWS_Y - 3.0)
	_menu.moved.connect(func(_index: int) -> void: _refresh())
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	show_tab(0)


func _holder() -> Control:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


func _physics_process(_delta: float) -> void:
	if done or _ask != null or not is_visible_in_tree():
		return
	if _pressed(&"sprint"):                       # LB
		show_tab(wrapi(tab - 1, 0, TABS.size()))
	elif _pressed(&"switch_weapon"):              # RB
		show_tab(wrapi(tab + 1, 0, TABS.size()))
	elif in_bag() and _pressed(&"menu_delete"):   # X：卖
		start_deal(true)


func _pressed(action: StringName) -> bool:
	return Session.just_pressed(action, who.player_index)


## 换一页：重算货架，光标回到第一行。
func show_tab(index: int) -> void:
	tab = index
	_shelf = _stock()
	var blanks: Array[String] = []
	for i in _shelf.size():
		blanks.append("")
	_menu.build(blanks, _wide + 12.0)
	_draw_tabs()
	_refresh()


## 这一页摆什么货。
func _stock() -> Array[Equipment]:
	var slots: Array = TABS[tab]["slots"]
	if slots.is_empty():
		return progress.owned.duplicate()      # 背包：自己拥有的全部
	var found: Array[Equipment] = []
	# **等级不够的照样上架**（买得到、穿不上），只是画暗——看得见目标才有奔头
	for item in Catalog.gear_for_sale():
		if slots.has(item.slot):
			found.append(item)
	for item in progress.owned:
		if slots.has(item.slot) and not found.has(item):
			found.append(item)
	found.sort_custom(func(a: Equipment, b: Equipment) -> bool: return a.price < b.price)
	return found


## 货架上现在有什么（测试用）。
func shelf() -> Array[Equipment]:
	return _shelf


## 光标停在哪一件上。
func picked() -> Equipment:
	return _shelf[_menu.index] if _menu != null and _menu.index < _shelf.size() else null


func menu_list() -> MenuList:
	return _menu


## 确认框那一列（开着才有）。
func ask_menu() -> MenuList:
	return _ask_menu if is_instance_valid(_ask_menu) else null


## 现在是背包页吗（能穿、能卖，不能买）。
func in_bag() -> bool:
	return tab == 0


# ---------------------------------------------------------------- 画

func _draw_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	var middle := WIDTH / 2.0
	var here := _text_wide(TABS[tab]["name"]) + 20.0
	_tab(middle - here / 2.0, TAB_Y, TAB_H, here, TABS[tab]["name"], true)
	var before := wrapi(tab - 1, 0, TABS.size())
	var before_wide := _text_wide(TABS[before]["name"]) + 14.0
	_tab(middle - here / 2.0 - before_wide - 2.0, TAB_Y + 3.0, TAB_H - 3.0, before_wide,
		TABS[before]["name"], false)
	var after := wrapi(tab + 1, 0, TABS.size())
	_tab(middle + here / 2.0 + 2.0, TAB_Y + 3.0, TAB_H - 3.0,
		_text_wide(TABS[after]["name"]) + 14.0, TABS[after]["name"], false)


## 一个标签底。`open` = 当前那页：**底边打开**，和下面的货架框连成一体。
func _tab(x: float, y: float, high: float, wide: float, text: String, open: bool) -> void:
	_tabs.add_child(UiKit.box(Rect2(x, y, wide, high + 2.0),
		UiKit.GOLD if open else TAB_OFF_EDGE, TAB_ON_FILL if open else TAB_OFF_FILL))
	if open:
		# 把标签底边那条描边盖掉，一直糊到货架框顶上：不盖的话中间横着一条线，
		# 看着就是上下两块不相干的东西，标签页的意思就没了
		var joint := ColorRect.new()
		joint.color = TAB_ON_FILL
		joint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		joint.position = Vector2(x + 1.0, y + high - 1.0)
		joint.size = Vector2(wide - 2.0, LIST_Y - (y + high) + 2.0)
		_tabs.add_child(joint)
	_tabs.add_child(UiKit.label(text, Rect2(x, y + (high - 14.0) / 2.0, wide, 14.0),
		UiKit.WHITE if open else UiKit.DIM, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	_money.text = "CASH %s" % UiKit.number(progress.money)
	_draw_rows()
	_draw_card()


func _draw_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var high := ROWS_Y - LIST_Y + ROWS * ROW + 6.0
	_rows.add_child(UiKit.box(Rect2(_left - 6.0, LIST_Y, _wide + 12.0, high), LIST_EDGE, LIST_FILL))
	var bag := in_bag()
	_rows.add_child(UiKit.label("ITEM", Rect2(_left, HEAD_Y, 120.0, 18.0), HEAD_TINT))
	_rows.add_child(UiKit.label("LV", Rect2(_left + 118.0, HEAD_Y, 26.0, 18.0), HEAD_TINT,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_rows.add_child(UiKit.label("EQ" if bag else "OWN", Rect2(_left + 150.0, HEAD_Y, 34.0, 18.0),
		HEAD_TINT, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	_rows.add_child(UiKit.label("SELL" if bag else "PRICE", Rect2(_left, HEAD_Y, _wide, 18.0),
		HEAD_TINT, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	var rule := ColorRect.new()
	rule.color = HEAD_RULE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2(_left - 2.0, HEAD_Y + 17.0)
	rule.size = Vector2(_wide + 4.0, 1.0)
	_rows.add_child(rule)
	if _shelf.is_empty():
		_rows.add_child(UiKit.label("NOTHING HERE", Rect2(_left, ROWS_Y + 28.0, _wide, 18.0),
			UiKit.DIM, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var first := _menu.first_row()
	for i in mini(ROWS, _shelf.size() - first):
		_draw_row(_shelf[first + i], ROWS_Y + i * ROW, bag)


func _draw_row(item: Equipment, y: float, bag: bool) -> void:
	var locked := not progress.can_equip(item)
	var has := progress.owned.has(item)
	var broke := not bag and not has and item.price > progress.money
	var tint := UiKit.WHITE
	if locked:
		tint = LOCKED
	elif broke:
		tint = UiKit.DIM
	_rows.add_child(UiKit.label(item.display_name, Rect2(_left, y, 118.0, 18.0), tint))
	_rows.add_child(UiKit.label(str(item.min_level), Rect2(_left + 118.0, y, 26.0, 18.0),
		RED if locked else UiKit.DIM, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	var flag := ""
	var flag_tint := UiKit.DIM
	if bag and progress.gear(item.slot) == item:
		flag = "ON"
		flag_tint = UiKit.GREEN
	elif not bag and has:
		flag = "YES"
	_rows.add_child(UiKit.label(flag, Rect2(_left + 150.0, y, 34.0, 18.0), flag_tint,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	var text := UiKit.number(PlayerProgress.sell_price(item) if bag else item.price)
	var price_tint := UiKit.GREEN
	if bag and not PlayerProgress.can_sell(item):
		text = "-"                        # 白给的东西卖不掉，别写成「值 0 块」
		price_tint = UiKit.DIM
	elif not bag and has:
		text = "-"
		price_tint = UiKit.DIM
	elif broke:
		price_tint = RED
	_rows.add_child(UiKit.label(text, Rect2(_left, y, _wide, 18.0), price_tint,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))


func _draw_card() -> void:
	for child in _card.get_children():
		child.queue_free()
	_card.add_child(UiKit.box(Rect2(_left - 6.0, CARD_Y, _wide + 12.0, CARD_H)))
	var item := picked()
	if item == null:
		return
	if item.icon != null:
		var icon := UiKit.picture("", Vector2(_left - 2.0, CARD_Y + 8.0))
		icon.texture = item.icon
		_card.add_child(icon)
	_card.add_child(UiKit.label(item.display_name, Rect2(_left + 36.0, CARD_Y + 8.0, 160.0, 18.0),
		UiKit.CYAN))
	_card.add_child(UiKit.label(Equipment.SLOT_NAMES[item.slot],
		Rect2(_left + 36.0, CARD_Y + 24.0, 160.0, 18.0), UiKit.DIM))
	_draw_compare(item)
	_card.add_child(UiKit.label(_action_text(item), Rect2(_left, CARD_Y + 90.0, _wide, 18.0),
		UiKit.GOLD))
	if not progress.can_equip(item):
		_card.add_child(UiKit.label("NEEDS LV %d" % item.min_level,
			Rect2(_left, CARD_Y + 90.0, _wide, 18.0), RED, UiKit.TEXT_SIZE,
			HORIZONTAL_ALIGNMENT_RIGHT))


## 「现在 → 换上之后」。背包里**身上正穿着的**那件比的是脱下来会掉多少，别的都比穿上会涨多少。
##
## **武器比的是武器自己的数字**（每发伤害、每秒几发），不是属性——武器的强弱全在
## `power` 和 `cooldown` 里，按属性比的话两把枪每一行都相同，看着像买了个寂寞（试玩反馈）。
## 比的对象是**身上那个位置现在装着的那把**，所以「换上之后」是真的换上之后。
func _draw_compare(item: Equipment) -> void:
	var wearing := in_bag() and progress.gear(item.slot) == item
	var line := 0
	var weapon := item as Weapon
	if weapon != null:
		var mine := progress.gear(weapon.slot) as Weapon
		var theirs := progress.weapon_numbers(weapon)
		# 身上这个位置还空着、或者选的就是身上那把，就没得比——直接把它自己的数字写出来
		var now_numbers: Dictionary = progress.weapon_numbers(mine) if mine != null and mine != weapon 			else {}
		for key: StringName in [&"damage", &"rate", &"ammo"]:
			if not theirs.has(key) or line >= 3:
				continue
			var later: float = theirs[key]
			var now: float = now_numbers.get(key, later)
			line += 1
			_compare_row(GUN_LABELS[key], now, later, CARD_Y + 46.0 + (line - 1) * 14.0,
				key == &"rate")
	var after: Dictionary = progress.stat_preview(item, not wearing)
	for name: StringName in Balance.STATS:
		var now := progress.stat(name)
		var later: float = after.get(name, now)
		var changes := not is_equal_approx(now, later)
		# **这件东西加了这一项就写出来，哪怕数字没动**：属性有上限，满级玩家换一顶头盔
		# 四行全都「没变」，详情框整个空着，看着像这件装备什么用都没有（2026-09 试玩反馈）。
		# 没动的那一行写 `MAX`，玩家才知道是顶到头了、不是装备没数值。
		if not changes and not item.bonuses.has(name):
			continue
		if line >= 3:
			continue
		line += 1
		_compare_row(String(name).substr(0, 3).to_upper(), now, later,
			CARD_Y + 46.0 + (line - 1) * 14.0, false,
			"" if changes else "MAX")


## 武器那几行的叫法。`RATE` 是每秒几发，`AMMO` 是弹药上限。
const GUN_LABELS := {&"damage": "DMG", &"rate": "RATE", &"ammo": "AMMO"}


## 一行「名字  现在 > 之后  差多少」。两个数一样就只写一个，不画箭头——
## 身上那个位置还空着的时候，写 `10 > 10  +0` 看着像它没用。
func _compare_row(label: String, now: float, later: float, y: float, fractional := false,
		note := "") -> void:
	var tint := UiKit.GREEN if later > now else (RED if later < now else UiKit.WHITE)
	_card.add_child(UiKit.label(label, Rect2(_left, y, 40.0, 14.0), UiKit.DIM))
	if is_equal_approx(now, later):
		_card.add_child(UiKit.label(_number(later, fractional),
			Rect2(_left + 34.0, y, 40.0, 14.0), UiKit.WHITE, UiKit.TEXT_SIZE,
			HORIZONTAL_ALIGNMENT_RIGHT))
		if not note.is_empty():
			_card.add_child(UiKit.label(note, Rect2(_left + 80.0, y, 60.0, 14.0), UiKit.DIM))
		return
	_card.add_child(UiKit.label(_number(now, fractional), Rect2(_left + 34.0, y, 40.0, 14.0),
		UiKit.WHITE, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_card.add_child(UiKit.label(">", Rect2(_left + 80.0, y, 12.0, 14.0), UiKit.DIM))
	_card.add_child(UiKit.label(_number(later, fractional), Rect2(_left + 92.0, y, 40.0, 14.0),
		tint, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	var gap := later - now
	_card.add_child(UiKit.label("%s%s" % ["+" if gap > 0.0 else "-", _number(absf(gap), fractional)],
		Rect2(_left + 140.0, y, 60.0, 14.0), tint))


## 射速要留一位小数（1.0 和 1.4 差得远），别的取整。
func _number(value: float, fractional: bool) -> String:
	return "%.1f" % value if fractional else str(roundi(value))


## 详情框最下面那一行写什么（在这件东西上按 A / X 会发生什么）。
func _action_text(item: Equipment) -> String:
	var sell := ("X SELL  %s" % UiKit.number(PlayerProgress.sell_price(item))
		if PlayerProgress.can_sell(item) else "")
	if in_bag():
		if progress.gear(item.slot) != item and progress.can_equip(item):
			return ("A EQUIP      " + sell) if not sell.is_empty() else "A EQUIP"
		# 白给的东西穿着又卖不掉，那一行就空了——写一句，别留一块空白让人以为没画出来
		return sell if not sell.is_empty() else "EQUIPPED"
	if progress.owned.has(item):
		return "OWNED"
	if item.price > progress.money:
		return "NOT ENOUGH CASH"
	return "A BUY  %s" % UiKit.number(item.price)


func _text_wide(text: String) -> float:
	return UiKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x


# ---------------------------------------------------------------- 选了什么

func _on_chosen(_index: int) -> void:
	var item := picked()
	if item == null:
		return
	if in_bag():
		# 穿不用确认——穿错了再换回来就是
		if progress.gear(item.slot) != item and progress.equip(item):
			_refresh()
		return
	start_deal(false)


## 买卖之前问一句。买不起、已经有了、背包里没有的都不问，直接不理。
func start_deal(sell: bool) -> void:
	var item := picked()
	if item == null or _ask != null or done:
		return
	if sell and (not progress.owned.has(item) or not PlayerProgress.can_sell(item)):
		return
	if not sell and (progress.owned.has(item) or item.price > progress.money):
		return
	_ask_sell = sell
	_menu.hide()
	# **高度按内容算**：三行字 + 两行菜单 + 九宫格上下各 32 的边。
	# 随手写个 96 的话 NO 那一行会掉到窗口外面（截图才看出来）。
	var high := ASK_TOP + ASK_LINE * 3.0 + MenuList.ROW_HEIGHT * 2.0 + 26.0
	var box := Rect2(_left + 4.0, (HEIGHT - high) / 2.0, _wide - 8.0, high)
	_ask = UiKit.window(box)
	add_child(_ask)
	var lines := [["%s?" % ("SELL" if sell else "BUY"), UiKit.WHITE], [item.display_name, UiKit.CYAN],
		[UiKit.number(PlayerProgress.sell_price(item) if sell else item.price), UiKit.GREEN]]
	for i in lines.size():
		_ask.add_child(UiKit.label(String(lines[i][0]),
			Rect2(0.0, ASK_TOP + i * ASK_LINE, box.size.x, ASK_LINE), lines[i][1],
			UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	_ask_menu = MenuList.new()
	_ask_menu.listens_to = who.player_index
	add_child(_ask_menu)
	_ask_menu.build(["YES", "NO"], box.size.x)
	_ask_menu.position = box.position + Vector2(0.0, ASK_TOP + ASK_LINE * 3.0)
	_ask_menu.chosen.connect(_on_ask_chosen)
	_ask_menu.cancelled.connect(_close_ask)


func _on_ask_chosen(index: int) -> void:
	var item := picked()
	var yes := index == 0 and item != null
	_close_ask()
	if not yes:
		return
	if _ask_sell:
		progress.sell(item)
	else:
		progress.buy(item)
	# 货架变了：卖掉的从背包里没了，买下的成了 OWNED
	show_tab(tab)


func _close_ask() -> void:
	if is_instance_valid(_ask):
		_ask.queue_free()
	if is_instance_valid(_ask_menu):
		_ask_menu.queue_free()
	_ask = null
	_ask_menu = null
	_menu.show()
	# 确认框就是用这一下 A / B 关掉的，同一帧货架不该再吃一次（否则一下 A 连买两件）
	_menu.ignore_this_frame()
	_refresh()


# ---------------------------------------------------------------- 逛完了

func _on_cancelled() -> void:
	set_done(true)


## 逛完之后整栏换成「等另一个人」，中间留一个 BACK TO SHOP 让人反悔。
## 单人时外面看见这个就直接走人，这一页根本来不及显示。
func set_done(value: bool) -> void:
	if done == value:
		return
	done = value
	for part: Control in [_menu, _tabs, _rows, _card]:
		part.visible = not done
	if done:
		_idle = _holder()
		_idle.add_child(UiKit.label("DONE", Rect2(_left, TITLE_Y, _wide, 18.0), UiKit.GREEN,
			UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
		_idle.add_child(UiKit.label("WAITING FOR THE OTHER PLAYER",
			Rect2(_left, 130.0, _wide, 18.0), UiKit.DIM, UiKit.TEXT_SIZE,
			HORIZONTAL_ALIGNMENT_CENTER))
		_idle_menu = MenuList.new()
		_idle_menu.listens_to = who.player_index
		add_child(_idle_menu)
		_idle_menu.build(["BACK TO SHOP"], WIDTH)
		_idle_menu.position = Vector2(0.0, 170.0)
		_idle_menu.chosen.connect(func(_i: int) -> void: set_done(false))
	else:
		if is_instance_valid(_idle):
			_idle.queue_free()
		if is_instance_valid(_idle_menu):
			_idle_menu.queue_free()
		_idle = null
		_idle_menu = null
		_menu.ignore_this_frame()   # BACK TO SHOP 那一下 A 不该顺手买一件
		_refresh()
	readiness_changed.emit(done)
