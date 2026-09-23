extends GameTest
## 主菜单：选几个人玩、每个座位新建或读档、删存档，然后进关卡。
##
## 菜单是单独一个场景（游戏启动时先进它），所以这一组**不用 `reset_scene()`**，
## 自己实例化 `main_menu.tscn` 来跑；关卡那边的老测试照旧直接加载 `main.tscn`，不受影响。

var menu: MainMenu


func open_menu() -> void:
	free_scene()
	tree.paused = false
	Progress.persist = false
	Progress.new_game()
	Session.set_player_count(1)
	Skins.use(Skins.default_skin())
	events.clear()
	if not GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.connect(_record_event)
	menu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	main = menu
	tree.root.add_child(menu)
	await frames(2)


## 菜单里按一下（菜单也是收物理帧里的按键，和游戏里一样）。
func press(action: StringName) -> void:
	await tap(action)


## 把光标挪到第 row 项。**按次数封顶**：挪不过去就算了，别把用例卡死——
## 出问题时要的是一条断言失败，不是 60 秒看门狗超时（那样连哪条断言错了都看不出来）。
func move_to(row: int) -> void:
	for i in 12:
		if menu._menu.index == row:
			return
		await press(&"aim_down")


## 走到第 index 项再确认。
func choose(index: int) -> void:
	await move_to(index)
	await press(&"jump")


# ---------------------------------------------------------------- 流程

func test_the_title_asks_how_many_are_playing() -> void:
	await open_menu()
	check("it opens on the title", menu.page() == MainMenu.Page.TITLE)
	check("with three choices", menu._menu._items == ["1 PLAYER", "2 PLAYERS", "QUIT"], str(menu._menu._items))
	await choose(0)
	check("picking one player moves on", menu.page() == MainMenu.Page.SOURCE and Session.player_count == 1,
		"%d 人" % Session.player_count)
	check("and it is the first seat's turn", menu.seat() == 0)


func test_two_players_each_get_a_turn() -> void:
	await open_menu()
	await choose(1)
	check("two players", Session.player_count == 2)
	check("the first seat picks first", menu.seat() == 0)
	await choose(0)                       # NEW
	check("then the second", menu.seat() == 1 and menu.page() == MainMenu.Page.SOURCE, str(menu.seat()))


func test_backing_out_walks_the_flow_backwards() -> void:
	await open_menu()
	await choose(1)
	await choose(0)                       # 1 号选完 NEW，轮到 2 号
	check("setup: on the second seat", menu.seat() == 1)
	await press(&"cancel")
	check("backing out goes to the seat before", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE)
	await press(&"cancel")
	check("and again to the title", menu.page() == MainMenu.Page.TITLE)


func test_a_new_character_takes_the_seat() -> void:
	await open_menu()
	var before := Progress.roster.size()
	await choose(0)                       # 1 PLAYER
	await choose(0)                       # NEW
	check("a character was made", Progress.roster.size() == before + 1, str(Progress.roster.size()))
	check("and it sits in the first seat", Progress.seat_of(Progress.of(0)) == 0)


# ---------------------------------------------------------------- 存档列表

func test_the_list_shows_what_is_in_the_roster() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_xp(Progress.balance.xp_to_next(1))
	mine.played_seconds = 3600.0 + 14.0 * 60.0
	Progress.create("NOVA")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	check("the list is up", menu.page() == MainMenu.Page.LOAD_LIST)
	var names := menu.listed().map(func(p: PlayerProgress) -> String: return p.character_name)
	check("both characters are on it", names.has("RYU") and names.has("NOVA"), str(names))
	check("playtime reads as hours and minutes", MainMenu.played_text(3600.0 + 14.0 * 60.0) == "1H 14M",
		MainMenu.played_text(3600.0 + 14.0 * 60.0))


func test_loading_seats_the_character_you_picked() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_money(99)
	await choose(0)
	await choose(1)
	var row := menu.listed().find(mine)
	check("setup: RYU is on the list", row >= 0)
	await choose(row)
	check("RYU took the seat", Progress.of(0) == mine and Progress.of(0).money == 99, str(Progress.of(0).money))


func test_the_other_player_cannot_take_the_same_character() -> void:
	await open_menu()
	var one := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(1)                       # 2 PLAYERS
	await choose(1)                       # 1 号 LOAD
	await choose(menu.listed().find(one))
	check("setup: the second seat is choosing", menu.seat() == 1)
	await choose(1)                       # 2 号 LOAD
	var row := menu.listed().find(one)
	check("the one already playing is greyed out", menu._menu.greyed.has(row), str(menu._menu.greyed))


func test_deleting_a_character_asks_first() -> void:
	await open_menu()
	var doomed := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(0)
	await choose(1)
	var row := menu.listed().find(doomed)
	await move_to(row)
	await press(&"menu_delete")
	check("it asks first", menu.page() == MainMenu.Page.CONFIRM)
	check("and the character is still there", Progress.roster.has(doomed))
	await choose(0)                       # NO
	check("saying no keeps it", Progress.roster.has(doomed) and menu.page() == MainMenu.Page.LOAD_LIST)
	await move_to(menu.listed().find(doomed))
	await press(&"menu_delete")
	await choose(1)                       # YES
	check("saying yes deletes it", not Progress.roster.has(doomed))
	check("and the list no longer shows it",
		not menu.listed().any(func(p: PlayerProgress) -> bool: return p == doomed))


## 名册列表那一页里，内容都得落在窗口边框里面。
func list_box() -> Rect2:
	var screen := Vector2(640, 360)
	return Rect2((screen.x - MainMenu.LIST_BOX.x) / 2.0, 46.0, MainMenu.LIST_BOX.x, MainMenu.LIST_BOX.y)


func test_the_list_stays_inside_the_window() -> void:
	await open_menu()
	for n in ["LONGESTNAME", "NOVA"]:
		var who := Progress.create(PlayerProgress.sanitize_name(n))
		who.played_seconds = 10.0 * 3600.0
		who.saved_at = "2026-09-23T09:35:00"
	await choose(0)
	await choose(1)
	var inside := list_box().grow(-MainMenu.LIST_EDGE)
	var widest := 0.0
	for child in menu._body.get_children():
		if child is Label and not (child as Label).text.is_empty():
			var label := child as Label
			var wide: float = label.get_theme_font("font").get_string_size(
				label.text, label.horizontal_alignment, -1, UiKit.TEXT_SIZE).x
			# 靠右对齐的（滚动标记）从右边量起，别的从左边
			var right: float = (label.position.x + label.size.x if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
				else label.position.x + wide)
			if label.position.y >= inside.position.y:
				widest = maxf(widest, right)
	check("setup: something was measured", widest > 0.0)
	check("no row runs past the frame", widest <= inside.end.x, "%.0f > %.0f" % [widest, inside.end.x])
	var cursor: Rect2 = Rect2(menu._menu.position + menu._menu.highlight_box(0).position,
		menu._menu.highlight_box(0).size)
	check("and neither does the gold box", cursor.position.x >= inside.position.x - 0.5
		and cursor.end.x <= inside.end.x + 0.5, str(cursor))


func test_the_gold_box_is_drawn_over_the_window() -> void:
	await open_menu()
	Progress.create("RYU")
	await choose(0)
	await choose(1)
	# 窗口是每一页临时加的，加在菜单后面就会把选中框盖住——界面上看不出光标在哪
	check("the menu is the last thing drawn",
		menu._body.get_child(menu._body.get_child_count() - 1) == menu._menu,
		"第 %d 个，共 %d 个" % [menu._menu.get_index(), menu._body.get_child_count()])


func test_a_long_roster_scrolls_instead_of_being_cut_off() -> void:
	await open_menu()
	var names: Array[String] = []
	for i in MainMenu.ROWS + 3:
		names.append("HERO%d" % i)
		Progress.create(names[i])
	await choose(0)
	await choose(1)
	check("every character is on the list", menu.listed().size() == names.size(), str(menu.listed().size()))
	check("but only a screenful is drawn", menu._menu.rows_shown() == MainMenu.ROWS,
		str(menu._menu.rows_shown()))
	check("starting at the top", menu._menu.first_row() == 0)
	for i in MainMenu.ROWS:
		await press(&"aim_down")
	check("walking past the last drawn row scrolls", menu._menu.first_row() > 0,
		str(menu._menu.first_row()))
	check("the one you are on is still drawn",
		menu._menu.index - menu._menu.first_row() < MainMenu.ROWS
		and menu._menu.index >= menu._menu.first_row(),
		"%d / %d" % [menu._menu.index, menu._menu.first_row()])
	# 一路走到底，最后一个也够得着
	for i in names.size():
		await press(&"aim_down")
	check("and the last one can be reached", menu._menu.index == menu.listed().size() - 1
		or menu._menu.first_row() > 0, str(menu._menu.index))


func test_the_cursor_starts_on_a_row_that_can_be_picked() -> void:
	await open_menu()
	var one := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(1)                       # 2 PLAYERS
	await choose(1)                       # 1 号 LOAD
	await choose(menu.listed().find(one))
	await choose(1)                       # 2 号 LOAD
	var taken := menu.listed().find(one)
	check("setup: the one already playing is greyed out", menu._menu.greyed.has(taken), str(menu._menu.greyed))
	if taken == 0:
		check("the cursor does not start on it", menu._menu.index != 0, str(menu._menu.index))
	check("and the gold box is visible", menu._menu._cursor.visible)


func test_one_press_does_not_fall_through_two_pages() -> void:
	# 退出人物设置那一下 B，同一帧就把 NEW/LOAD 那一页摆了出来。那一页的菜单**不该再吃一次**，
	# 否则一下 B 连退两页，直接回到标题。
	await reach_setup(1)
	await press(&"cancel")
	check("backing out of setup lands on the source page and stops there",
		menu.page() == MainMenu.Page.SOURCE, str(menu.page()))


# ---------------------------------------------------------------- 人物设置

## 走到「选完 NEW / LOAD」那一步，停在人物设置界面上。
func reach_setup(players: int) -> void:
	await open_menu()
	await choose(players - 1)             # 1 PLAYER / 2 PLAYERS
	for i in players:
		await choose(0)                   # NEW
	await frames(2)


## 某一栏走到某一行（界面上就是按上下，这里直接放光标，省得一路敲）。
func at_row(column: SetupColumn, row: int) -> void:
	column.go_to_row(row)
	await frames(1)


func test_the_setup_screen_comes_before_the_level() -> void:
	await reach_setup(1)
	check("setup is up", menu.setup() != null)
	check("with one column", menu.setup() != null and menu.setup().columns().size() == 1)
	check("and the level has not started", tree.current_scene == null, str(tree.current_scene))


func test_two_players_get_a_column_each() -> void:
	await reach_setup(2)
	check("two columns", menu.setup().columns().size() == 2)
	var looks := menu.setup().columns().map(func(c: SetupColumn) -> StringName: return c.progress.look)
	check("and they start on different characters", looks[0] != looks[1], str(looks))


func test_left_and_right_change_the_character() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.LOOK)
	var before := column.progress.look
	await press(&"move_right")
	check("the look changed", column.progress.look != before, "%s -> %s" % [before, column.progress.look])
	await press(&"move_left")
	check("and comes back", column.progress.look == before, str(column.progress.look))


func test_the_other_player_s_character_is_skipped() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_row(one, SetupColumn.Row.LOOK)
	for i in SetupColumn.LOOKS.size() + 1:
		await press(&"move_right")
		check("never lands on what the other player wears", one.progress.look != two.progress.look,
			"%s / %s" % [one.progress.look, two.progress.look])


func test_body_text_uses_the_small_font_and_titles_the_big_one() -> void:
	# 位图字体只有做出来的那个尺寸是清楚的，所以正文和标题各用各的图集，不让引擎去缩。
	await open_menu()
	var title: Label = null
	var item: Label = menu._menu._labels[0]
	for child in menu._body.get_children():
		if child is Label and (child as Label).text == MainMenu.TITLE:
			title = child
	check("setup: the title is on screen", title != null)
	check("the title is drawn from the big glyphs",
		title.get_theme_font("font").resource_path == UiKit.FONT,
		title.get_theme_font("font").resource_path)
	check("and the menu items from the small ones",
		item.get_theme_font("font").resource_path == UiKit.FONT_SMALL,
		item.get_theme_font("font").resource_path)
	check("which really are smaller", UiKit.TEXT_SIZE < 14, str(UiKit.TEXT_SIZE))
	var small: Font = load(UiKit.FONT_SMALL)
	var big: Font = load(UiKit.FONT)
	check("a line of text takes less room than it used to",
		small.get_string_size("CASH 1250", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
		< big.get_string_size("CASH 1250", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)


func test_the_column_says_what_level_the_character_is() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_xp(Progress.balance.xp_to_next(1) + Progress.balance.xp_to_next(2))
	check("setup: RYU levelled up", mine.level >= 3, str(mine.level))
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the level is written beside the faces", column._level.text == "LEVEL %d" % mine.level,
		column._level.text)
	var faces := column._portraits[SetupColumn.LOOKS.size() - 1]
	check("and it sits to their right", column._level.position.x >= faces.position.x + faces.size.x,
		"%.0f vs %.0f" % [column._level.position.x, faces.position.x + faces.size.x])
	check("with room for the words", column._level.position.x + column._level.get_theme_font("font")
		.get_string_size(column._level.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
		<= SetupColumn.WIDTH - 26.0, column._level.text)


func test_points_go_in_and_out_with_left_and_right() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var points := column.progress.points
	check("setup: a new character has points", points > 0, str(points))
	await at_row(column, SetupColumn.Row.STAT)          # 第一个属性
	await press(&"move_right")
	check("right puts one point in", column.progress.points == points - 1, str(column.progress.points))
	check("and it landed on life", column.progress.allocated.get(Balance.LIFE, 0) == 1,
		str(column.progress.allocated))
	await press(&"move_right")
	check("again for a second", column.progress.allocated.get(Balance.LIFE, 0) == 2,
		str(column.progress.allocated))
	await press(&"move_left")
	check("left takes one back out", column.progress.allocated.get(Balance.LIFE, 0) == 1
		and column.progress.points == points - 1, str(column.progress.allocated))


func test_points_stop_at_none_left_and_at_the_starting_value() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.STAT)
	# 一路加到点数见底
	for i in column.progress.points + 3:
		await press(&"move_right")
	check("it stops when the points run out", column.progress.points == 0, str(column.progress.points))
	var spent: int = column.progress.allocated.get(Balance.LIFE, 0)
	check("setup: they all went into life", spent > 0, str(spent))
	# 一路退回去，退到一点都没加为止
	for i in spent + 3:
		await press(&"move_left")
	check("and it stops again at the starting value", not column.progress.allocated.has(Balance.LIFE),
		str(column.progress.allocated))
	check("with every point back in hand", column.progress.points == spent, str(column.progress.points))


func test_a_point_always_reads_as_plus_one() -> void:
	# 每点加的量各不相同（生命 +10、攻击 +1、防御速度 +5），金色那列照实写的话，
	# 同样按一下右，三个属性冒出来的数字不一样，玩家会以为自己按错了键。写的是**投了几点**。
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	for i in Balance.STATS.size():
		await at_row(column, SetupColumn.Row.STAT + i)
		await press(&"move_right")
		check("one point in %s reads as +1" % Balance.STATS[i],
			column._stat_rows[i]["bonus"].text == "+1", column._stat_rows[i]["bonus"].text)
	await at_row(column, SetupColumn.Row.STAT)
	await press(&"move_right")
	check("two points read as +2", column._stat_rows[0]["bonus"].text == "+2",
		column._stat_rows[0]["bonus"].text)
	check("and the value beside it is still the real one",
		column._stat_rows[0]["value"].text == str(roundi(column.progress.stat(Balance.LIFE))),
		column._stat_rows[0]["value"].text)
	await press(&"move_left")
	await press(&"move_left")
	check("taking them all back leaves nothing", column._stat_rows[0]["bonus"].text == "",
		column._stat_rows[0]["bonus"].text)


func test_the_arrows_only_show_on_the_stat_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.STAT)
	check("the row you are on offers to add", column._stat_rows[0]["more"].visible)
	check("but not to take away yet", not column._stat_rows[0]["less"].visible)
	check("and the next row shows nothing", not column._stat_rows[1]["more"].visible)
	await press(&"move_right")
	check("once a point is in, taking it back is offered", column._stat_rows[0]["less"].visible)


func test_the_gold_box_follows_the_row_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.NAME)
	var on_name := column._menu.highlight_box(column.row())
	check("the box sits on the name", column._menu._cursor.position.is_equal_approx(on_name.position),
		"%s vs %s" % [column._menu._cursor.position, on_name.position])
	await at_row(column, SetupColumn.Row.STAT)
	var on_stat := column._menu.highlight_box(column.row())
	check("moving down really picks another block", not on_stat.position.is_equal_approx(on_name.position))
	check("and the box moved with it", column._menu._cursor.position.is_equal_approx(on_stat.position),
		"%s vs %s" % [column._menu._cursor.position, on_stat.position])


func test_the_gold_box_frames_the_gear_slot_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	var first := column._menu._cursor.position
	check("it frames the first slot", first.is_equal_approx(column.slot_rect(0).grow(2.0).position),
		str(first))
	await press(&"move_right")
	check("moving a slot over moves the box", not column._menu._cursor.position.is_equal_approx(first))
	check("onto that slot", column._menu._cursor.position.is_equal_approx(
		column.slot_rect(column.slot).grow(2.0).position), str(column._menu._cursor.position))


func test_the_look_you_picked_is_not_marked_in_gold() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.LOOK)
	var mark: ColorRect = column._portraits[column.look_index()]
	check("the picked face is marked", mark.color == UiKit.GREEN, str(mark.color))
	check("in a colour the cursor never uses", mark.color != UiKit.GOLD)


func test_the_gear_row_walks_the_slots() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	check("it starts on the gun", column.slot == Equipment.Slot.GUN)
	await press(&"move_right")
	check("right moves to the next slot", column.slot == Equipment.Slot.GRENADE, str(column.slot))
	await press(&"move_left")
	await press(&"move_left")
	check("and it wraps around", column.slot == Equipment.Slot.TRINKET, str(column.slot))


func test_a_loaded_character_cannot_be_renamed() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	check("setup is up", menu.setup() != null)
	check("and the name is locked", not menu.setup().columns()[0].can_rename)


# ---------------------------------------------------------------- 改名字

func test_typing_a_name_on_the_letter_grid() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	# 打字是接着现有名字打的（可以小改），所以先把名字弄短一点再测
	column.progress.character_name = "X"
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	check("the letter grid is up", column.grid() != null)
	check("and the column stops listening", column.busy())
	# 光标从 A 开始：A，右一格是 B，再往下一行是 H（一行 6 个）
	await press(&"jump")
	await press(&"move_right")
	await press(&"jump")
	await press(&"aim_down")
	await press(&"jump")
	check("the letters land in order", column.grid().text == "XABH", column.grid().text)
	# 退格那一格在最后一行中间
	column.grid()._cursor = column.grid()._cells.find(LetterGrid.BACK)
	await press(&"jump")
	check("and delete takes one off", column.grid().text == "XAB", column.grid().text)
	await press(&"cancel")
	check("backing out closes the grid", column.grid() == null and not column.busy())
	check("and keeps what was typed", column.progress.character_name == "XAB", column.progress.character_name)


func test_a_name_that_is_taken_is_refused() -> void:
	await open_menu()
	Progress.create("AB")
	await choose(0)
	await choose(0)
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	column.progress.character_name = "A"
	var before := column.progress.character_name
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	await press(&"move_right")
	await press(&"jump")                      # 打成 AB，而 AB 已经有人用了
	check("setup: typed a name somebody already has", column.grid().text == "AB", column.grid().text)
	await press(&"cancel")
	check("the old name stays", column.progress.character_name == before, column.progress.character_name)


func test_a_loaded_name_cannot_be_typed_over() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)
	await choose(1)
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	check("no grid for a loaded character", column.grid() == null)


# ---------------------------------------------------------------- 换装备

func test_swapping_what_is_in_a_slot() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	check("setup: the gun slot has the rifle", column.progress.gear(Equipment.Slot.GUN) != null)
	await press(&"jump")
	check("the bag opens", column.bag() != null and column.busy())
	await press(&"jump")                      # 第一项是 NONE
	check("picking none empties the slot", column.progress.gear(Equipment.Slot.GUN) == null)
	check("and the bag closes", column.bag() == null and not column.busy())
	await press(&"jump")
	await press(&"aim_down")
	await press(&"jump")                      # 再选回来
	check("the rifle goes back on", column.progress.gear(Equipment.Slot.GUN) != null,
		str(column.progress.gear(Equipment.Slot.GUN)))


func test_an_empty_slot_only_offers_none() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	for i in Equipment.Slot.HEAD:
		await press(&"move_right")
	check("setup: on the head slot", column.slot == Equipment.Slot.HEAD, str(column.slot))
	await press(&"jump")
	check("the bag opens with nothing to wear", column.bag() != null and column.bag()._items.size() == 1,
		str(column.bag()._items if column.bag() != null else []))
	await press(&"cancel")
	check("and closes again", column.bag() == null)


func test_everyone_has_to_accept_before_the_level_starts() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_row(one, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("the first player is ready", one.confirmed)
	check("but the level waits", tree.current_scene == null, str(tree.current_scene))
	await at_row(two, SetupColumn.Row.ACCEPT)
	await tap(&"p2_jump")
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null:
			break
	check("once both are ready it starts", tree.current_scene != null and tree.current_scene.name == "Main",
		str(tree.current_scene))
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_backing_out_of_ready_and_then_out_of_setup() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("setup: ready", column.confirmed)
	await press(&"cancel")
	check("backing out cancels ready first", not column.confirmed and menu.setup() != null)
	await press(&"cancel")
	check("and again leaves the setup screen", menu.setup() == null and menu.page() == MainMenu.Page.SOURCE)


func test_finishing_the_last_seat_starts_the_level() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null and tree.current_scene.name == "Main":
			break
	check("the level is loaded", tree.current_scene != null and tree.current_scene.name == "Main",
		str(tree.current_scene))
	# 收尾要收两样东西，少收一样都会祸害后面的用例：
	# 1. **菜单节点自己**——它是手动 add_child 到 root 上的，`change_scene_to_file` 只换 current_scene，
	#    不会动它。留着的话它还在每帧收按键，后面的用例一按 A 就被它当成菜单确认。
	# 2. **current_scene**——只 free() 的话 SceneTree 还记着那个已经没了的节点，后面玩家一死，
	#    `main.gd` 会对着它调 `reload_current_scene()`，协程当场断掉，表现成一堆莫名其妙的「事件没报」。
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null
