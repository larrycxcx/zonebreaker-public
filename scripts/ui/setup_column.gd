class_name SetupColumn
extends Control
## One column of character setup: a player's name, look, points and gear.
##
## A column = **a list of rows chosen top to bottom**: name / look / four stats / gear / shop / accept.
## Up and down change rows, left and right choose within a row (switch characters, move between the eight gear boxes), A confirms, B goes back.
## So there is only one set of navigation rules, hands on the pad never have to move, and the two columns can each be driven by their own player.
##
## **The gear row is read-only**: move left and right to see what is equipped, A does not change anything — gear is changed only in the shop's bag page
## (`ShopColumn`). Without that split the same thing would have two entry points, and their rules (level requirements, selling) would clash sooner or later.
##
## The UI is always English upper case (the pack's font has no Chinese glyphs, see CLAUDE.md).

## This column was confirmed / unconfirmed.
signal readiness_changed(confirmed: bool)
## Back was pressed in this column (while not yet confirmed).
signal backed_out
## A small panel covering this column was opened / closed (renaming).
## The outside uses this to know the column is busy and nothing else should grab the keys.
signal overlay_changed(open: bool)
## This column wants to open the shop (the whole screen shares one shop, so `SetupScreen` opens it).
signal shop_requested

const WIDTH := 300.0
const HEIGHT := 338.0
## What the rows mean. The four stat rows lie between STAT and GEAR.
## **SHOP and ACCEPT are one row** (drawn on the same line, one left and one right): left / right chooses between them, not up / down.
## As two rows, two blocks clearly side by side on screen would be switched with up / down, going exactly against this column's rule
## "up / down changes rows, left / right chooses within a row" (2026-09 playtest feedback).
enum Row { NAME, LOOK, STAT, GEAR = 6, FOOT }
## Which one of the last row is selected.
enum Foot { SHOP, ACCEPT }
const ROW_COUNT := 8

## The portrait box is 2px bigger on each side than the pack's `portrait.png` (22×36), so the character fits entirely inside.
## If the image changes this has to change too; `test_cyberpunk_skin.gd` has a check measuring it.
const PORTRAIT := Vector2(26, 40)
## Gear boxes: icons are 32×32 with content up to 30×30, and a box of 36 leaves two or three pixels around the icon.
## At 34 the icon's corners sat right on the outline, looking like "the thing is too big to fit";
## any bigger and it would not fit — a column is only 338 tall, with eight boxes in two rows plus the name, portrait and four stats above.
const SLOT := Vector2(36, 36)
const SLOTS_PER_LINE := 4

## Where each block of a column goes from top to bottom (relative to the window top). Somewhat cramped, but two columns have to fit into 640×360 together.
const TITLE_Y := 16.0
const NAME_Y := 34.0
const LOOK_Y := 60.0
const STATS_Y := 106.0
## Height of a stat row. **Decided by the icon, not the text**: the text is only 10px tall, but the drawing inside the 32×32 stat icon
## is 20px (y 6..25 of `stat_*.png`). With a row spacing of 16 the icons of neighbouring rows overlapped,
## and the gold selection box covered the neighbour's icon too (obvious at a glance in the playtest screenshot).
const STAT_STEP := 20.0
const POINTS_Y := 186.0
const GEAR_Y := 206.0
const DETAIL_Y := 282.0
const FOOT_Y := 300.0

## Selectable characters, in left-to-right order on screen — found by **scanning the `characters/` directory** (see `Catalog`),
## not named in code, so a DLC dropping in a `.tres` adds a character.
static func looks() -> Array[StringName]:
	var keys: Array[StringName] = []
	for look in Catalog.looks():
		keys.append(look.key)
	return keys
const STAT_LABELS := {&"life": "LIFE", &"attack": "ATTACK", &"defense": "DEFENSE", &"speed": "SPEED"}

var who: Player
var progress: PlayerProgress
## Whether the name can be changed (not for characters loaded from a save).
var can_rename := true
## Confirmed or not. **Do not call it `ready`**: that is a signal name Node already has, and the clash makes the whole script fail to parse.
var confirmed := false
## Which gear box is selected.
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
## The small panel covering this column: the name letter grid.
## Which half of the last row is selected now (SHOP or ACCEPT).
var _foot := Foot.SHOP

var _grid: LetterGrid
## Which look the other player picked (that one cannot be picked; two identical characters on one screen could not be told apart).
var _taken := &""
## The characters this column can pick (keys of `Catalog.looks()`). Scanned once and kept, not read from the directory every frame.
var _looks: Array[StringName] = []
## Left edge and width of the content area of this column (`_boxes()` works out each row's selection box from it).
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
	# The empty space right of the portrait: what level this character has reached (visible at a glance when loaded from a save).
	# XP is not written alongside: the row fits `LEVEL 10` but not `XP 3500/3844` (150px needed where there are 130px).
	var beside := left + _looks.size() * (PORTRAIT.x + 8.0) + 4.0
	_level = UiKit.label("", Rect2(beside, LOOK_Y + 12.0, left + wide - beside, 18.0), UiKit.GOLD)
	add_child(_level)
	for i in Balance.STATS.size():
		var top := STATS_Y + i * STAT_STEP
		var stat: StringName = Balance.STATS[i]
		var colour: Color = UiKit.STAT_COLORS.get(stat, UiKit.WHITE)
		# The icon is 32×32 with the drawing at y 6..25; placed at top - 6 it fills a 20px row exactly without spilling over
		var icon := UiKit.picture("%s/stat_%s.png" % [UiKit.DIR, stat], Vector2(left + 10.0, top - 6.0), colour)
		add_child(icon)
		var name_label := UiKit.label(STAT_LABELS[stat], Rect2(left + 46.0, top, 90.0, 18.0), UiKit.DIM)
		var value := UiKit.label("", Rect2(left + 122.0, top, 56.0, 18.0), colour, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bonus := UiKit.label("", Rect2(left + 202.0, top, 46.0, 18.0), UiKit.GOLD)
		# When this row is selected a pair of small arrows appears either side of the number, hinting that left / right adds and removes
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
		# The icon sits in the middle of the box: (36 - 32) / 2 = 2. It used to be at - 1,
		# pushing the whole image a cell up and to the left with its corners on the outline, looking "too big to fit".
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
	# **Characters loaded from a save start right on ACCEPT**: the name cannot change and points and gear are as they were left,
	# so most of the time it is one press and play; move up to change something. New characters start from the first row (name) as before.
	if not can_rename:
		_foot = Foot.ACCEPT
		_menu.index = Row.FOOT
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	_menu.nudged.connect(_on_nudged)
	# Changing rows needs a redraw too: the `<` `>` on stat rows and the brightness of SHOP / ACCEPT follow where the cursor is.
	# (`go_to_row()` calls refresh itself, so only the key-press path was missing this — the tests nearly missed it.)
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


## Whether SHOP or ACCEPT is selected in the last row now.
func foot() -> int:
	return _foot


## Put the cursor straight on one half of the last row (when loading from a save, and for tests).
func go_to_foot(which: int) -> void:
	_foot = clampi(which, Foot.SHOP, Foot.ACCEPT) as Foot
	go_to_row(Row.FOOT)    # It calls refresh(), so the box follows correctly


func menu_list() -> MenuList:
	return _menu


## Move the cursor to a row (for tests; in the UI it is pressing up and down).
func go_to_row(index: int) -> void:
	_menu.index = clampi(index, 0, ROW_COUNT - 1)
	refresh()


func _blank(count: int) -> Array[String]:
	var rows: Array[String] = []
	for i in count:
		rows.append("")
	return rows


func refresh() -> void:
	# Names loaded from a save cannot be changed, shown by drawing them faded (do not use symbols like `*`, the font does not have them)
	_name.text = progress.character_name
	_name.add_theme_color_override("font_color", UiKit.CYAN if can_rename else UiKit.DIM)
	_level.text = "LEVEL %d" % progress.level
	_points.text = "POINTS %d" % progress.points
	_points.add_theme_color_override("font_color", UiKit.GOLD if progress.points > 0 else UiKit.DIM)
	# **The font has no `$`** (it is not in the pack's symbol set), which would come out as a missing-glyph box, so the word CASH is used
	_money.text = "CASH %s" % UiKit.number(progress.money)
	_ready_mark.text = "READY" if confirmed else ""
	for i in _looks.size():
		var chosen := i == look_index()
		var blocked := _looks[i] == _taken
		# The picked one is marked in **green**, not gold: the gold box means only "where the cursor is now", and two gold ones would be confusing
		_portraits[i].color = UiKit.GREEN if chosen else (Color(0.2, 0.22, 0.34) if blocked else Color(0.27, 0.35, 0.55))
	for i in Balance.STATS.size():
		var stat: StringName = Balance.STATS[i]
		# The gold column shows **how many points were put in**, not how much the stat grew: each point adds a different amount
		# (life +10, attack +1, defence / speed +5), and writing the real amounts would make players think they pressed different keys.
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
	# **Only the cursor's row is bright**: drawn pure white all the time, SHOP / ACCEPT stood out more than the gold box,
	# and with the name faded when loaded from a save it looked as if the cursor started on ACCEPT.
	var on_foot := _menu != null and _menu.index == Row.FOOT
	var on_shop := on_foot and _foot == Foot.SHOP
	var on_accept := on_foot and _foot == Foot.ACCEPT
	# You can go in without money: you can still sell things in the shop, and that is where money is earned
	_shop.add_theme_color_override("font_color", UiKit.WHITE if on_shop else UiKit.DIM)
	_accept.add_theme_color_override("font_color",
		UiKit.GREEN if confirmed else (UiKit.WHITE if on_accept else UiKit.DIM))
	# The selection box of the gear row frames **the current box**, so moving between boxes has to give it again
	if _menu != null:
		_menu.row_boxes = _boxes()


## The numbers of the item in this box.
## **Weapons show what they actually do** (damage per shot, shots per second), not stat bonuses —
## a weapon's strength is all in `power` and `cooldown`, and without showing them two guns looked different only by name (playtest feedback).
## Armour still shows its bonuses (ATK +2  SPD +5).
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


## A weapon's numbers on one line: `DMG 10  RATE 6.7/S`. The shop uses it too, hence static.
## Unlimited ammo is not in the table at all (see `PlayerProgress.weapon_numbers()`), so there is no need to check again here.
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


## What each row's selection box frames. **It frames the content itself** (the name box, the three portraits, a row of stats, the whole set of gear boxes),
## not an empty strip of equal height — so you can see at a glance what is selected.
func _boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	boxes.append(Rect2(_left - 3.0, NAME_Y - 2.0, _wide + 6.0, 26.0))
	boxes.append(Rect2(_left - 3.0, LOOK_Y - 3.0, PORTRAIT.x * 3.0 + 16.0 + 6.0, PORTRAIT.y + 6.0))
	for i in Balance.STATS.size():
		boxes.append(Rect2(_left - 3.0, STATS_Y + i * STAT_STEP - 1.0, _wide + 6.0, STAT_STEP))
	boxes.append(slot_rect(slot).grow(2.0))
	# The last row only gets a box around **the half selected now**
	boxes.append(foot_rect(_foot))
	return boxes


## Where SHOP / ACCEPT each sit in the last row (the selection box frames one of them).
func foot_rect(which: int) -> Rect2:
	return Rect2(_left - 3.0, FOOT_Y - 1.0, _wide / 2.0, 20.0) if which == Foot.SHOP 		else Rect2(_left + _wide / 2.0 - 3.0, FOOT_Y - 1.0, _wide / 2.0 + 6.0, 20.0)


## Where a given gear box is (the box the selection frames).
func slot_rect(index: int) -> Rect2:
	return Rect2(Vector2(_left + (index % SLOTS_PER_LINE) * (SLOT.x + 4.0),
		GEAR_Y + (index / SLOTS_PER_LINE) * (SLOT.y + 4.0)), SLOT)


func _on_chosen(index: int) -> void:
	match _row_kind(index):
		Row.NAME:
			if can_rename:
				_open_grid()
		Row.STAT:
			# A means the same as "right", either works
			if progress.spend_point(Balance.STATS[index - Row.STAT]):
				refresh()
		Row.GEAR:
			pass          # Read-only: gear is changed on the shop's bag page
		Row.FOOT:
			if _foot == Foot.SHOP:
				shop_requested.emit()
			else:
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
		Row.FOOT:
			# Moving the box to the other half is handled by `refresh()` (it gives `row_boxes` again anyway)
			_foot = clampi(_foot + direction, Foot.SHOP, Foot.ACCEPT) as Foot
			refresh()
		Row.LOOK:
			_pick_look(direction)
		Row.STAT:
			# Right adds a point (until the points run out), left takes one back (down to the starting value)
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


## What a row means (all four stat rows count as STAT).
func _row_kind(index: int) -> int:
	if index >= Row.STAT and index < Row.GEAR:
		return Row.STAT
	return index


## Switch looks, skipping the one the other player already took.
func _pick_look(direction: int) -> void:
	var at := look_index()
	for _try in _looks.size():
		at = wrapi(at + direction, 0, _looks.size())
		if _looks[at] != _taken:
			break
	progress.look = _looks[at]
	refresh()


# ---------------------------------------------------------------- Renaming

## Busy renaming? (While busy, this column's own up / down does not work.)
func busy() -> bool:
	return is_instance_valid(_grid)


func grid() -> LetterGrid:
	return _grid if is_instance_valid(_grid) else null


## The letter grid covers the portrait and stats, leaving the name row visible so you can see it as you type.
func _open_grid() -> void:
	_menu.hide()
	_grid = LetterGrid.new()
	_grid.position = Vector2(30.0, LOOK_Y + 4.0)
	add_child(_grid)
	_grid.build(progress.character_name, who.player_index)
	# The cursor is `|`: the font has it, but neither underscore nor asterisk (they would come out as missing-glyph boxes)
	_grid.changed.connect(func(text: String) -> void:
		_name.text = text + "|"
	)
	_grid.done.connect(_close_grid)
	_name.text = progress.character_name + "|"
	overlay_changed.emit(true)


## Done: if the name **is a duplicate or empty it does not change**, going back to the original one.
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
