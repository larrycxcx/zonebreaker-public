class_name ShopColumn
extends Control
## One player's column in the shop: tabs → shelf → details and comparison of the selected item.
##
## **One column per player, side by side, each driven by its own pad** (the same approach as character setup).
## Top to bottom: who is buying + how much money they have → tabs (switched with LB/RB) → column headings → shelf → details.
##
## Eight tabs: bag + weapons + six armour slots. They do not fit on one row, so they work like a **carousel** —
## only the previous / current / next are shown, and **the current one is open at the bottom, joined to the shelf below**, which is the visual cue of a tab.
## The bag page is called `BAG` rather than `INVENTORY`: a column is only 236px wide inside, and `TRINKET` current + `INVENTORY` beside it
## needs 247px, pushing the right one out of the nine-slice frame (`test_the_rows_stay_inside_the_window` measures it).
##
## What you can do where:
## - **Bag page**: A equips (not if the level is too low), X sells (half price; equipped items can be sold too and are taken off automatically)
## - **Shop pages**: A buys. **You can buy even if your level is too low**, you just cannot wear it yet — seeing the goal keeps you going.
## - Buying and selling ask for confirmation first; equipping does not (if you equip the wrong thing just change back).
##
## **Gear can only be changed here**: the eight boxes in character setup are read-only, and gear is always changed in the shop.
## The UI is always English upper case (the pack's font has no Chinese glyphs, see CLAUDE.md).

## This column finished shopping / came back.
signal readiness_changed(done: bool)

const WIDTH := 300.0
const HEIGHT := 328.0
## Most rows per page, scrolling beyond that. **The row height has to equal `MenuList.ROW_HEIGHT`** —
## the gold box is drawn by the menu from its own row height while the shelf text is drawn here; if the two disagree the box is off.
const ROW := MenuList.ROW_HEIGHT
const ROWS := 5

## Tabs: name + which gear slots they hold. The bag page leaves `slots` empty = everything you own.
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

## Where things go from top to bottom in a column (relative to the window top).
const TITLE_Y := 12.0
const TAB_Y := 32.0
const TAB_H := 20.0
const LIST_Y := 52.0
const HEAD_Y := 56.0
const ROWS_Y := 78.0
const CARD_Y := 210.0
const CARD_H := 112.0
## Confirm box: distance of the first line from the top of the box, and line height.
const ASK_TOP := 30.0
const ASK_LINE := 15.0

const RED := Color(0.86, 0.36, 0.36)
## Rows whose level requirement is too high are drawn dark as a whole (still selectable and buyable, just not wearable).
const LOCKED := Color(0.38, 0.42, 0.54)
const TAB_ON_FILL := Color(0.17, 0.21, 0.37)
const TAB_OFF_FILL := Color(0.10, 0.12, 0.23)
const TAB_OFF_EDGE := Color(0.22, 0.27, 0.42)
const LIST_EDGE := Color(0.27, 0.35, 0.55)
const LIST_FILL := Color(0.12, 0.15, 0.28)
## Column headings set apart from the goods: a warmer colour with a line drawn underneath.
const HEAD_TINT := Color(0.64, 0.58, 0.42)
const HEAD_RULE := Color(0.30, 0.34, 0.50)

var who: Player
var progress: PlayerProgress
## Finished shopping? (In co-op it only leaves once both have finished.)
var done := false
## Which page it is on now.
var tab := 0

var _menu: MenuList
var _tabs: Control
var _rows: Control
var _card: Control
var _money: Label
var _shelf: Array[Equipment] = []
## The confirm box before buying / selling; while it is open the shelf takes no keys (the menu is `hide()`n).
var _ask: Control
var _ask_menu: MenuList
var _ask_sell := false
## "Waiting for the other player", covering this column after it is done.
var _idle: Control
var _idle_menu: MenuList

var _left := 0.0
var _wide := 0.0


func build(player: Player) -> void:
	who = player
	progress = player.progress
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	# The content area: **text has to fall inside the nine-slice frame** (32 each side), and the box sits 6px further out, just against the inner edge of the frame
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
	# The gold box is drawn by the menu from its own row height, the shelf text is drawn here: **the first rows of both must line up**
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
	elif in_bag() and _pressed(&"menu_delete"):   # X: sell
		start_deal(true)


func _pressed(action: StringName) -> bool:
	return Session.just_pressed(action, who.player_index)


## Switch pages: rebuild the shelf, cursor back to the first row.
func show_tab(index: int) -> void:
	tab = index
	_shelf = _stock()
	var blanks: Array[String] = []
	for i in _shelf.size():
		blanks.append("")
	_menu.build(blanks, _wide + 12.0)
	_draw_tabs()
	_refresh()


## Which goods this page shows.
func _stock() -> Array[Equipment]:
	var slots: Array = TABS[tab]["slots"]
	if slots.is_empty():
		return progress.owned.duplicate()      # Bag: everything you own
	var found: Array[Equipment] = []
	# **Items above your level are still on the shelf** (buyable, not wearable), just drawn dark — seeing the goal keeps you going
	for item in Catalog.gear_for_sale():
		if slots.has(item.slot):
			found.append(item)
	for item in progress.owned:
		if slots.has(item.slot) and not found.has(item):
			found.append(item)
	found.sort_custom(func(a: Equipment, b: Equipment) -> bool: return a.price < b.price)
	return found


## What is on the shelf now (for tests).
func shelf() -> Array[Equipment]:
	return _shelf


## Which item the cursor rests on.
func picked() -> Equipment:
	return _shelf[_menu.index] if _menu != null and _menu.index < _shelf.size() else null


func menu_list() -> MenuList:
	return _menu


## The confirm box's column (only there while open).
func ask_menu() -> MenuList:
	return _ask_menu if is_instance_valid(_ask_menu) else null


## Is this the bag page? (Equip and sell, no buying.)
func in_bag() -> bool:
	return tab == 0


# ---------------------------------------------------------------- Drawing

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


## A tab background. `open` = the current page: **open at the bottom**, joined to the shelf frame below.
func _tab(x: float, y: float, high: float, wide: float, text: String, open: bool) -> void:
	_tabs.add_child(UiKit.box(Rect2(x, y, wide, high + 2.0),
		UiKit.GOLD if open else TAB_OFF_EDGE, TAB_ON_FILL if open else TAB_OFF_FILL))
	if open:
		# Cover the outline at the bottom of the tab, all the way down to the top of the shelf frame: without it a line runs across the middle
		# and it looks like two unrelated blocks, losing the sense of a tab
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
		text = "-"                        # Free items cannot be sold; do not write "worth 0"
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


## "Now → after switching". For the item **currently worn** in the bag it compares how much taking it off loses; everything else compares how much putting it on gains.
##
## **Weapons compare their own numbers** (damage per shot, shots per second), not stats — a weapon's strength is all
## in `power` and `cooldown`, and compared by stats two guns showed identical rows, like buying nothing (playtest feedback).
## The comparison is against **the weapon currently in that slot**, so "after switching" really is after switching.
func _draw_compare(item: Equipment) -> void:
	var wearing := in_bag() and progress.gear(item.slot) == item
	var line := 0
	var weapon := item as Weapon
	if weapon != null:
		var mine := progress.gear(weapon.slot) as Weapon
		var theirs := progress.weapon_numbers(weapon)
		# If that slot is empty or the selection is the one already equipped, there is nothing to compare — just write its own numbers
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
		# **Show every stat the item adds, even when the number does not move**: stats are capped, and a max-level player swapping a helmet
		# would see all four rows "unchanged", the details box completely empty, as if the item did nothing at all (2026-09 playtest feedback).
		# A row that did not move says `MAX`, so the player knows it hit the cap rather than the item having no stats.
		if not changes and not item.bonuses.has(name):
			continue
		if line >= 3:
			continue
		line += 1
		_compare_row(String(name).substr(0, 3).to_upper(), now, later,
			CARD_Y + 46.0 + (line - 1) * 14.0, false,
			"" if changes else "MAX")


## Labels of the weapon rows. `RATE` is shots per second, `AMMO` the ammo cap.
const GUN_LABELS := {&"damage": "DMG", &"rate": "RATE", &"ammo": "AMMO"}


## One row "name  now > after  difference". When both numbers are the same only one is written, without an arrow —
## with the slot still empty, `10 > 10  +0` would look as if it did nothing.
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


## Fire rate keeps one decimal (1.0 and 1.4 are far apart); the rest are rounded.
func _number(value: float, fractional: bool) -> String:
	return "%.1f" % value if fractional else str(roundi(value))


## What the bottom line of the details box says (what pressing A / X on this item would do).
func _action_text(item: Equipment) -> String:
	var sell := ("X SELL  %s" % UiKit.number(PlayerProgress.sell_price(item))
		if PlayerProgress.can_sell(item) else "")
	if in_bag():
		if progress.gear(item.slot) != item and progress.can_equip(item):
			return ("A EQUIP      " + sell) if not sell.is_empty() else "A EQUIP"
		# A free item that is worn and cannot be sold would leave the line empty — say something, do not leave a blank that looks like it failed to draw
		return sell if not sell.is_empty() else "EQUIPPED"
	if progress.owned.has(item):
		return "OWNED"
	if item.price > progress.money:
		return "NOT ENOUGH CASH"
	return "A BUY  %s" % UiKit.number(item.price)


func _text_wide(text: String) -> float:
	return UiKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x


# ---------------------------------------------------------------- What was chosen

func _on_chosen(_index: int) -> void:
	var item := picked()
	if item == null:
		return
	if in_bag():
		# Equipping needs no confirmation — if you equip the wrong thing just change back
		if progress.gear(item.slot) != item and progress.equip(item):
			_refresh()
		return
	start_deal(false)


## Ask before buying or selling. Things you cannot afford, already own or do not have in the bag are not asked about, just ignored.
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
	# **The height follows the content**: three lines of text + two menu rows + the nine-slice frame's 32 at top and bottom.
	# A casual 96 would push the NO row outside the window (only seen in a screenshot).
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
	# The shelf changed: what was sold has gone from the bag, what was bought is now OWNED
	show_tab(tab)


func _close_ask() -> void:
	if is_instance_valid(_ask):
		_ask.queue_free()
	if is_instance_valid(_ask_menu):
		_ask_menu.queue_free()
	_ask = null
	_ask_menu = null
	_menu.show()
	# The confirm box was closed with this press of A / B; the shelf should not take it again on the same frame (otherwise one A buys two)
	_menu.ignore_this_frame()
	_refresh()


# ---------------------------------------------------------------- Done shopping

func _on_cancelled() -> void:
	set_done(true)


## Once done, the whole column turns into "waiting for the other player", with a BACK TO SHOP in the middle in case you change your mind.
## When playing alone the outside leaves as soon as it sees this, so this page never even gets shown.
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
		_menu.ignore_this_frame()   # The A that pressed BACK TO SHOP should not buy something on the way
		_refresh()
	readiness_changed.emit(done)
