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


func test_points_can_be_spent_from_the_setup_screen() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var points := column.progress.points
	check("setup: a new character has points", points > 0, str(points))
	await at_row(column, SetupColumn.Row.STAT)          # 第一个属性
	await press(&"jump")
	check("one point went in", column.progress.points == points - 1, str(column.progress.points))
	check("and it landed on life", column.progress.allocated.get(Balance.LIFE, 0) == 1,
		str(column.progress.allocated))


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
