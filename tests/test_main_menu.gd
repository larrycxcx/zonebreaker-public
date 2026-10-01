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
	# 手柄绑定是改 InputMap 的，那是全局状态——上一条用例认领过的得还原
	Session.reset_pads()
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


## **按当前这一页听的那个座位的键**。写着 PLAYER 2 的那几页只认 `p2_*`——
## 用 1 号的键去敲 2 号那一页，界面根本不动，用例会卡在那儿（这正是要守的规则）。
func press_here(action: StringName) -> void:
	await tap(Session.action_for(action, maxi(0, menu._menu.listens_to)))


## 把光标挪到第 row 项。**按次数封顶**：挪不过去就算了，别把用例卡死——
## 出问题时要的是一条断言失败，不是 60 秒看门狗超时（那样连哪条断言错了都看不出来）。
func move_to(row: int) -> void:
	for i in 12:
		if menu._menu.index == row:
			return
		await press_here(&"aim_down")


## 走到第 index 项再确认。
func choose(index: int) -> void:
	await move_to(index)
	await press_here(&"jump")


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
	# **按这一页听的那个座位的键**：2 号那一页不认 1 号的 B
	await press_here(&"cancel")
	check("backing out goes to the seat before", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE)
	await press_here(&"cancel")
	check("and again to the title", menu.page() == MainMenu.Page.TITLE)


func test_a_new_character_takes_the_seat() -> void:
	await open_menu()
	var before := Progress.roster.size()
	await choose(0)                       # 1 PLAYER
	await choose(0)                       # NEW
	check("a character was made", Progress.roster.size() == before + 1, str(Progress.roster.size()))
	check("and it sits in the first seat", Progress.seat_of(Progress.of(0)) == 0)


func test_the_hint_names_a_key_that_actually_works() -> void:
	# 标题上原来写的是「ENTER OR A TO START」，可 Enter 根本没绑——菜单确认走的是 `jump`。
	# 提示上写哪个键，那个键就得真的按得动。
	await open_menu()
	var hint := ""
	for child in menu._body.get_children():
		if child is Label and (child as Label).text.ends_with("TO START"):
			hint = (child as Label).text
	check("the title says how to start", hint != "", hint)
	var named := hint.split(" ")[0]
	var bound := false
	for event in InputMap.action_get_events(&"jump"):
		var key := event as InputEventKey
		if key != null and OS.get_keycode_string(key.physical_keycode).to_upper() == named:
			bound = true
	check("and %s really is bound to confirm" % named, bound, hint)


func test_the_menu_switches_the_music_over_to_its_own_slot() -> void:
	# 主菜单归 `intro` 这个用途管。**现在包里没有这首**（原来那首不合适，撤了等换），
	# 所以进菜单是安静的；以后往包里放一首就会响，这条测试两种情况都成立。
	await open_menu()
	check("the menu took over the music slot", Music.current == &"intro", str(Music.current))
	var track := Skins.music(&"intro")
	if track == null:
		check("no track in the pack, so it stays quiet", Music.playing_stream() == null,
			str(Music.playing_stream()))
	else:
		check("the pack's track is the one playing", Music.playing_stream() == track)


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
	for i in SetupColumn.looks().size() + 1:
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
	var faces := column._portraits[SetupColumn.looks().size() - 1]
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


func test_only_the_row_you_are_on_is_lit_up() -> void:
	# ACCEPT 一直画成纯白的话，它比金框还抢眼——读档进来名字是淡的，看上去就像光标停在 ACCEPT 上。
	# **用按键走，不用 go_to_row**：换行时重画是单独接的一条线，go_to_row 自己会 refresh，走那条路测不出来。
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	check("setup: starting on the name", column.row() == SetupColumn.Row.NAME)
	check("accept is not lit up yet", column._accept.get_theme_color("font_color") == UiKit.DIM,
		str(column._accept.get_theme_color("font_color")))
	for i in SetupColumn.Row.ACCEPT:
		await press(&"aim_down")
	check("setup: walked down to accept", column.row() == SetupColumn.Row.ACCEPT, str(column.row()))
	check("now it lights up", column._accept.get_theme_color("font_color") == UiKit.WHITE,
		str(column._accept.get_theme_color("font_color")))
	await press(&"aim_up")
	check("and goes back down when you leave", column._shop.get_theme_color("font_color") != UiKit.DIM
		or column._accept.get_theme_color("font_color") == UiKit.DIM)


func test_the_stat_arrows_follow_the_keys_too() -> void:
	# 同上：走按键那条路，确认换行真的会重画（`go_to_row` 那条路会掩盖掉漏接的信号）
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await press(&"aim_down")              # NAME -> LOOK
	await press(&"aim_down")              # LOOK -> 第一个属性
	check("setup: on the first stat", column.row() == SetupColumn.Row.STAT, str(column.row()))
	check("its arrow showed up", column._stat_rows[0]["more"].visible)
	await press(&"aim_down")
	check("and moves off with the cursor", not column._stat_rows[0]["more"].visible)
	check("onto the next one", column._stat_rows[1]["more"].visible)


func test_the_gear_icon_sits_inside_its_slot() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var slot := column.slot_rect(Equipment.Slot.GUN)
	var icon: TextureRect = column._slot_icons[Equipment.Slot.GUN]
	check("setup: there is a gun to show", icon.texture != null)
	var size: Vector2 = icon.texture.get_size()
	check("the icon is inside the frame", icon.position.x > slot.position.x
		and icon.position.y > slot.position.y
		and icon.position.x + size.x < slot.end.x
		and icon.position.y + size.y < slot.end.y,
		"%s %s vs %s" % [icon.position, size, slot])


## 一张图里真正画着东西的那几行（从贴图上数出来，换了图这条测试跟着变）。
func ink_rows(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	var top := -1.0
	var bottom := -1.0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				if top < 0.0:
					top = y
				bottom = y
				break
	return Vector2(top, bottom)


func test_the_stat_rows_leave_room_for_their_icons() -> void:
	# 行距是**图标**说了算，不是字：字才 10px 高，属性图标里画着的东西有 20px。
	# 挨太近的话上下两行的图标会叠在一起，选中的金框也会盖到邻居的图标上。
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var boxes: Array[Rect2] = []
	for i in Balance.STATS.size():
		var icon: TextureRect = column._stat_rows[i]["icon"]
		var rows := ink_rows(icon.texture)
		var top: float = icon.position.y + rows.x
		var bottom: float = icon.position.y + rows.y
		var box := column._menu.highlight_box(SetupColumn.Row.STAT + i)
		boxes.append(box)
		check("row %d's box holds its whole icon" % i, box.position.y <= top and box.end.y >= bottom,
			"icon %.0f..%.0f vs box %.0f..%.0f" % [top, bottom, box.position.y, box.end.y])
	for i in boxes.size() - 1:
		check("row %d's box does not reach into the next one" % i,
			boxes[i].end.y <= boxes[i + 1].position.y,
			"%.0f > %.0f" % [boxes[i].end.y, boxes[i + 1].position.y])


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


func test_a_loaded_character_starts_on_accept() -> void:
	# 读档进来多半是「就这样，开打」，所以光标直接停在 ACCEPT 上，按一下就走。
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the cursor waits on accept", column.row() == SetupColumn.Row.ACCEPT, str(column.row()))
	check("and it is the lit-up row", column._accept.get_theme_color("font_color") == UiKit.WHITE,
		str(column._accept.get_theme_color("font_color")))
	await press(&"jump")
	# **按下去之后这一栏就没了**（设置界面整个被选关页换掉），所以查的是页面，不是 `column.confirmed`
	check("so one press is enough to finish setting up",
		menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_a_new_character_starts_at_the_top_of_the_column() -> void:
	# 新建的什么都还没填，从名字那一行开始
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the cursor is on the first row", column.row() == SetupColumn.Row.NAME, str(column.row()))


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


## **一个人玩的时候，人物设置界面不该只认 1 号那套键**。
## 前面几页的菜单 `listens_to` 是 -1（谁按都算），人物设置是整个菜单里第一个按玩家过滤输入的页面，
## 所以同一只手柄在前几页好好的、到这一页整页全死——手柄插在第二个槽位上就会这样
## （前一个槽被没拔干净的幽灵设备占着是常事）。键盘上的 ↑ 同理：单人时它既是 1 号的跳跃、
## 又是 2 号的「上」，只认 1 号那套的话它在这一页从「上移」变成了「确认」。
func test_playing_alone_is_not_tied_to_one_controller() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	await tap(&"p2_aim_down")
	check("the other seat's keys still move the cursor", column.row() == SetupColumn.Row.SHOP,
		str(column.row()))
	await tap(&"p2_jump")
	check("and still choose", menu.setup().shop() != null)
	await tap(&"p2_cancel")
	await frames(2)
	check("and still back out", menu.setup().shop() == null)


## 双人时反过来：每个座位只认自己那套，不然两个人会互相把对方的光标带着走。
func test_two_players_stay_on_their_own_controllers() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_row(one, SetupColumn.Row.GEAR)
	await at_row(two, SetupColumn.Row.GEAR)
	await tap(&"p2_aim_down")
	check("player two moved", two.row() == SetupColumn.Row.SHOP, str(two.row()))
	check("player one did not", one.row() == SetupColumn.Row.GEAR, str(one.row()))


# ---------------------------------------------------------------- 装备格 / 商店入口

func test_the_gear_row_only_shows_what_you_are_wearing() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	check("setup: the gun slot has the rifle", column.progress.gear(Equipment.Slot.GUN) != null)
	await press(&"jump")
	# **只读**：装备只能在商店的背包页换，这里按 A 什么也不该发生
	check("A does not open anything", not column.busy() and menu.setup().shop() == null)
	check("and the rifle is still on", column.progress.gear(Equipment.Slot.GUN) != null)
	for i in Equipment.Slot.HEAD:
		await press(&"move_right")
	check("left and right still walk the slots", column.slot == Equipment.Slot.HEAD, str(column.slot))


func test_the_shop_row_opens_the_shop() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.SHOP)
	await press(&"jump")
	var shop := menu.setup().shop()
	check("the shop opens", shop != null and shop.columns().size() == 1)
	check("and the setup column stops listening", not column.is_visible_in_tree())
	await press(&"cancel")
	await frames(2)
	check("backing out closes it again", menu.setup().shop() == null)
	check("and the setup column is back", column.is_visible_in_tree())
	# 退出商店那一下 B **不该**被设置界面再吃一次（那会把整页退回去）
	check("without falling out of setup", menu.page() == MainMenu.Page.SETUP,
		str(menu.page()))


func test_both_players_shop_side_by_side() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	await at_row(one, SetupColumn.Row.SHOP)
	await press(&"jump")
	var shop := menu.setup().shop()
	check("one player asking opens both columns", shop != null and shop.columns().size() == 2)
	await press(&"cancel")
	await frames(2)
	check("and one player leaving is not enough", menu.setup().shop() != null)
	check("that column waits for the other", shop.columns()[0].done and not shop.columns()[1].done)
	await tap(&"p2_cancel")
	await frames(2)
	check("both leaving closes the shop", menu.setup().shop() == null)


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
	await frames(2)
	check("once both are ready setting up is done",
		menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	await choose(0)
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null:
			break
	check("and picking a stage starts it", tree.current_scene != null
		and tree.current_scene.scene_file_path != "", str(tree.current_scene))
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_backing_out_of_ready_and_then_out_of_setup() -> void:
	# **这条得用双人来测**：单人按一下 ACCEPT 就整页翻到选关了，那一栏当场被拆掉，
	# 「先取消 ACCEPT、再退出设置」这两步只有在「另一个人还没好」的时候才走得到。
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	await at_row(one, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("setup: ready, and still on the setup screen because the other one is not",
		one.confirmed and menu.page() == MainMenu.Page.SETUP)
	await press(&"cancel")
	check("backing out cancels ready first", not one.confirmed and menu.setup() != null)
	await press(&"cancel")
	check("and again leaves the setup screen",
		menu.setup() == null and menu.page() == MainMenu.Page.SOURCE)


func test_backing_out_of_the_stage_list_returns_to_setup() -> void:
	# 选关页是设置界面之后那一页，B 退回来还能改人
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("setup: it moved on to the stage list", menu.page() == MainMenu.Page.STAGE,
		str(menu.page()))
	await press(&"cancel")
	check("backing out comes back to the setup screen",
		menu.page() == MainMenu.Page.SETUP and menu.setup() != null, str(menu.page()))
	check("and nothing was started", tree.current_scene == null, str(tree.current_scene))


func test_every_stage_is_listed_while_the_unlock_switch_is_on() -> void:
	# 项目设置 `game/unlock_all_levels`：开着时选关页列出全部关卡，不看打到哪儿了。
	# 做关卡时要随时跳到任意一关去试——**发布前要关掉**。
	check("the switch is on while levels are being built",
		ProjectSettings.get_setting("game/unlock_all_levels", false), "记得发布前关掉")
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("setup: the stage list is up", menu.page() == MainMenu.Page.STAGE)
	var listed := menu._unlocked()
	check("a brand new character can still pick any stage",
		listed.size() == Catalog.levels().size(),
		"%d / %d，角色只解锁了 %d 关"
			% [listed.size(), Catalog.levels().size(), Progress.of(0).reached])
	check("setup: this character really has not unlocked them all",
		Progress.of(0).reached < Catalog.levels().size(), str(Progress.of(0).reached))


func test_finishing_the_last_seat_starts_the_level() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.ACCEPT)
	await press(&"jump")
	check("setting up is done", menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	await choose(0)
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null:
			break
	# 按**场景文件**认，不按根节点的名字：正式关卡是 level_N.tscn，测试关才叫 main.tscn
	check("the level is loaded", tree.current_scene != null
		and tree.current_scene.scene_file_path == Catalog.levels()[0].scene_path,
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


func test_the_shop_does_not_print_two_hints_on_top_of_each_other() -> void:
	# 设置界面底下那行 `A CHOOSE  B BACK` 和商店那行 `A CHOOSE … B LEAVE` 在**同一个 y**，
	# 两行居中的字叠在一起会糊成一团（2026-09 试玩截图看出来的，无头测试量不到位置重叠，
	# 所以守的是「商店开着时只剩一行在显示」）。
	await reach_setup(2)
	var setup := menu.setup()
	var hints := _visible_hints(setup)
	check("setup: the setup screen has its own hint", hints.size() == 1, str(hints))
	setup._open_shop()
	await frames(2)
	check("the shop is open", setup.shop() != null)
	hints = _visible_hints(setup)
	check("and only one hint is showing", hints.size() == 1, str(hints))
	check("the one that belongs to the shop",
		hints.size() == 1 and hints[0].contains("LEAVE"), str(hints))
	setup._close_shop()
	await frames(2)
	hints = _visible_hints(setup)
	check("closing it brings the other one back",
		hints.size() == 1 and hints[0].contains("BACK"), str(hints))


## 现在屏幕上**看得见的**那几行操作提示（设置界面一行、商店一行，都贴在画面底边）。
func _visible_hints(setup: SetupScreen) -> Array[String]:
	var out: Array[String] = []
	for node in setup.find_children("*", "Label", true, false):
		var label := node as Label
		if label.is_visible_in_tree() and label.text.contains("A CHOOSE"):
			out.append(label.text)
	return out


func test_a_seat_can_only_be_filled_by_its_own_controller() -> void:
	# **试玩报的「手柄错位」**：1 号 LOAD 完进人物设置界面，发现自己是 2 号。
	# 原因是写着 PLAYER 1 的那几页**谁按都算**——拿 2 号手柄的人把角色选进了 1 号座位，
	# 一进设置界面（那一栏只听 1 号手柄）他就只能操作 2 号那一栏了。
	# 删存档本来就是按座位取的，漏的是导航这一半。
	await open_menu()
	await choose(1)                       # 2 PLAYERS
	check("setup: it is the first seat's turn", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("the second pad cannot move the first seat's cursor", menu._menu.index == at,
		"%d -> %d" % [at, menu._menu.index])
	await tap(&"p2_jump")
	check("nor choose for it", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE,
		"座位 %d，第 %d 页" % [menu.seat(), menu.page()])
	await press(&"jump")                  # 1 号自己按 NEW
	check("the first pad does", menu.seat() == 1 and menu.page() == MainMenu.Page.SOURCE)
	# 轮到 2 号了，这回反过来
	at = menu._menu.index
	await tap(&"aim_down")
	check("and now the first pad cannot move the second seat's cursor", menu._menu.index == at,
		"%d -> %d" % [at, menu._menu.index])
	await tap(&"p2_jump")
	check("while the second pad can", menu.page() == MainMenu.Page.SETUP, str(menu.page()))


func test_the_shared_pages_still_take_anybody() -> void:
	# 「几个人玩」和「选哪一关」是大家一起定的，不该按座位分
	# （那时候还没人有座位 / 两个人打的是同一关），和死亡页同一个道理。
	await open_menu()
	check("setup: on the title", menu.page() == MainMenu.Page.TITLE)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("the second pad moves the title cursor too", menu._menu.index != at,
		"%d -> %d" % [at, menu._menu.index])
	check("the title listens to everyone", menu._menu.listens_to == -1,
		str(menu._menu.listens_to))


func test_playing_alone_is_never_locked_out_by_which_slot_the_pad_is_in() -> void:
	# 单人时谁按都算（规则在 `Session.just_pressed()`）：手柄插在第二个槽位上是常事，
	# 按座位过滤的话一个人玩会整页按不动。
	await open_menu()
	await choose(0)                       # 1 PLAYER
	check("setup: one player, first seat", Session.player_count == 1 and menu.seat() == 0)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("a pad in the second slot still drives the menu", menu._menu.index != at,
		"%d -> %d" % [at, menu._menu.index])


# ---------------------------------------------------------------- 哪只手柄是几号

func test_the_pad_that_starts_the_game_becomes_player_one() -> void:
	# **Godot 的 device 号是按插入顺序给的**，和玩家心里的「1 号手柄」没关系：
	# 前一个槽被没拔干净的幽灵设备占着是常事，手里那只就成了 device 1。
	# 写死「座位 0 ↔ device 0」的话，他在标题页（谁按都算）一切正常，
	# 一到写着 PLAYER 1 的那页就按不动了，另一只手柄反而能动（2026-09 试玩报的）。
	await open_menu()
	check("setup: it starts on the project's own wiring",
		Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	Session.claim_pads(1)
	check("the pad that pressed becomes the first seat's", Session.pad_of(0) == 1,
		str(Session.pad_of(0)))
	check("and the first seat's buttons now listen to it",
		_pad_devices(&"jump") == [1], str(_pad_devices(&"jump")))
	# **键盘的键一个都不许碰**：它们的 `device` 是 -1（任意设备），
	# 跟着改成某一只手柄的号就等于把键盘绑死在那只设备上
	check("while the keyboard keys are untouched",
		_key_devices(&"jump") == [-1], str(_key_devices(&"jump")))


func test_claiming_a_pad_does_not_disturb_the_keyboard() -> void:
	await open_menu()
	var before := _has_key_event(&"move_left") and _has_key_event(&"p2_move_left")
	Session.claim_pads(1)
	check("setup: both seats had keyboard keys", before)
	check("and they still do", _has_key_event(&"move_left") and _has_key_event(&"p2_move_left"))
	check("still on any device", _key_devices(&"move_left") == [-1]
		and _key_devices(&"p2_move_left") == [-1],
		"%s / %s" % [_key_devices(&"move_left"), _key_devices(&"p2_move_left")])


func test_a_keyboard_start_leaves_the_pads_alone() -> void:
	# 用键盘开的局（`last_pad` 还是 -1）不该把手柄绑定搅乱
	await open_menu()
	Session.claim_pads(-1)
	check("nothing moved", Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])


func test_the_title_hands_out_the_pads() -> void:
	# 标题页选完几个人玩那一下就认领——那是第一个「谁按的」有意义的时刻
	await open_menu()
	Session.last_pad = 1
	await choose(0)                       # 1 PLAYER
	check("leaving the title claims the pad that was pressing", Session.pad_of(0) == 1,
		str(Session.pad_of(0)))


func test_resetting_puts_the_pads_back() -> void:
	# InputMap 是全局状态，每条用例跑完要还原（`GameTest.reset_scene()` 里调）
	await open_menu()
	Session.claim_pads(1)
	check("setup: it moved", Session.pad_of(0) == 1)
	Session.reset_pads()
	check("reset puts it back", Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("and the buttons follow", _pad_devices(&"jump") == [0], str(_pad_devices(&"jump")))


## 这个动作上的手柄事件各绑在哪只手柄上（排好序，去掉重复）。
func _pad_devices(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if not out.has(event.device):
				out.append(event.device)
	out.sort()
	return out


## 这个动作上的键盘事件各绑在哪个设备上（正常都是 -1 = 任意设备）。
func _key_devices(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and not out.has(event.device):
			out.append(event.device)
	out.sort()
	return out


## 这个动作上还有没有键盘的键。
func _has_key_event(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


func test_two_seats_never_share_one_pad() -> void:
	# 只插了一只手柄又选了双人：1 号认领了它，2 号要是还绑在同一只上，
	# 一个人动两个角色都动。认领时和原来占着它的那个座位**对换**。
	await open_menu()
	check("setup: the seats start on different pads", Session.pad_of(0) != Session.pad_of(1),
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	Session.claim_pads(1)                 # 1 号认领了本来属于 2 号的那只
	check("they still have one each", Session.pad_of(0) != Session.pad_of(1),
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("and they simply swapped", Session.pad_of(0) == 1 and Session.pad_of(1) == 0,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("the buttons followed", _pad_devices(&"jump") == [1]
		and _pad_devices(&"p2_jump") == [0],
		"%s / %s" % [_pad_devices(&"jump"), _pad_devices(&"p2_jump")])


func test_both_pads_can_still_pause_after_claiming() -> void:
	# `pause` **故意绑了两只手柄的 Start**（两个玩家都能暂停）。
	# 按座位一刀切地重绑会把它压成一只手柄——认领之后只剩一个人能暂停。
	await open_menu()
	check("setup: both pads start out able to pause", _pad_devices(&"pause") == [0, 1],
		str(_pad_devices(&"pause")))
	Session.claim_pads(1)
	check("after claiming, two pads can still pause", _pad_devices(&"pause").size() == 2,
		"%s，座位 %d / %d" % [_pad_devices(&"pause"), Session.pad_of(0), Session.pad_of(1)])
	for seat in 2:
		check("seat %d's pad is among them" % seat,
			_pad_devices(&"pause").has(Session.pad_of(seat)), str(_pad_devices(&"pause")))
	check("and the keyboard still pauses", _has_key_event(&"pause"))
