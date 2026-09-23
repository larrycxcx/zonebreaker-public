extends GameTest
## 暂停界面和加点界面。
##
## 守的东西：两个玩家都能暂停、暂停时关卡真的停了、终极武器定格那两秒抢不走暂停、
## 加点界面按一下真的加一点、双人时两栏各按各的、加完点玩家身上的属性跟着变、返回能一层层退出来。

const STATS := 4


func menu() -> PauseMenu:
	return main.get_node("PauseMenu")


func skills() -> SkillsScreen:
	for child in menu().get_child(0).get_children():
		if child is SkillsScreen:
			return child
	return null


## 用第几号玩家的那套键按一下。
func tap_as(player_index: int, action: StringName) -> void:
	await tap(action if player_index == 0 else StringName("p%d_%s" % [player_index + 1, action]))


# ---------------------------------------------------------------- 暂停

func test_pausing_stops_the_level() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: running", not tree.paused and not menu().is_open())
	await tap(&"pause")
	check("the menu is up", menu().is_open())
	check("and the level is frozen", tree.paused)
	var spot := player.global_position
	Input.action_press("move_right")
	await frames(10)
	release_all_input()
	check("the player cannot move while paused", player.global_position == spot,
		str(player.global_position - spot))
	await tap(&"cancel")
	check("backing out closes it", not menu().is_open() and not tree.paused)


func test_a_closed_menu_does_not_listen() -> void:
	# 踩过的坑：菜单藏起来时只看 `visible`（那是节点自己的开关，父节点藏了它还是 true），
	# 结果没暂停的时候照样在收键——游戏里随手按「下下 A」就选中了 QUIT，整个进程直接退出。
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: the menu is closed", not menu().is_open())
	var list: MenuList = menu().menu_list()
	check("setup: its cursor is on the first item", list.index == 0, str(list.index))
	# 先只按一下「下」：这时候光标要是动了，再按「下 A」就会选中 QUIT 把进程关掉，
	# 测试连报错的机会都没有，所以断言卡在这一步，不往下走。
	await tap(&"aim_down")
	check("moving the stick while playing does not move a hidden cursor", list.index == 0, str(list.index))
	await tap(&"jump")
	check("and confirming does not open anything", not menu().is_open() and not tree.paused)


func test_reopening_puts_the_gold_box_back_on_resume() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await tap(&"pause")
	var list: MenuList = menu().menu_list()
	await tap(&"aim_down")
	check("setup: the cursor moved off RESUME", list.index == PauseMenu.SKILLS, str(list.index))
	await tap(&"cancel")
	await tap(&"pause")
	check("it reopens on RESUME", list.index == PauseMenu.RESUME, str(list.index))
	# 光标框是直接赋值挪过来的（不是按键走的那条路），框得跟着，不然它会留在 SKILLS 上
	check("and the gold box is on RESUME too",
		list._cursor.position.is_equal_approx(list.highlight_box(PauseMenu.RESUME).position),
		"%s vs %s" % [list._cursor.position, list.highlight_box(PauseMenu.RESUME).position])
	await tap(&"cancel")


func test_either_player_can_pause() -> void:
	await reset_scene(false, false, null, 2)
	# `pause` 一个动作绑了两个手柄的 Start，所以不分谁按
	var pads := InputMap.action_get_events(&"pause").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton)
	var devices := pads.map(func(e: InputEvent) -> int: return e.device)
	check("both gamepads can pause", devices.has(0) and devices.has(1), str(devices))
	check("and the keyboard too", InputMap.action_get_events(&"pause").any(func(e: InputEvent) -> bool:
		return e is InputEventKey))


func test_the_ultimate_freeze_keeps_the_pause_button_out() -> void:
	# 终极武器也用 tree.paused 定格，两边抢着改会互相解掉对方
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await tap(&"ultimate")
	check("setup: the ultimate froze the level", tree.paused and not menu().is_open())
	await tap(&"pause")
	check("pausing is refused while it lasts", not menu().is_open())
	for i in 300:
		if not tree.paused:
			break
		await tree.physics_frame
	check("and the freeze ended on its own", not tree.paused)
	await tap(&"pause")
	check("now it opens", menu().is_open())
	await tap(&"cancel")


# ---------------------------------------------------------------- 死亡选择

func death() -> DeathScreen:
	return main.get_node("DeathScreen")


## 把玩家打死，等那一页弹出来。**先把两段延时调短**（默认 0.5 + 0.7 秒），省得每条用例等 72 帧。
func die_and_wait() -> void:
	main.game_over_delay = 0.05
	main.respawn_delay = 0.1
	player.take_damage(player.max_health)
	for i in 60:
		await tree.physics_frame
		if death().is_open():
			return


func test_dying_offers_a_choice_instead_of_just_reloading() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: alive and running", player.is_alive() and not death().is_open())
	await die_and_wait()
	check("the choice comes up", death().is_open())
	# 「GAME OVER」写在这一层上，不在 HUD 上：压暗那层就在这儿，写在 HUD 上会被压暗、灰得看不清
	check("and it says what happened", death()._title.visible and death()._title.text == "GAME OVER",
		death()._title.text)
	check("with retry and main menu on it", death().menu_list()._items == DeathScreen.ITEMS,
		str(death().menu_list()._items))
	check("and the level is frozen while you pick", tree.paused)
	check("starting on retry", death().menu_list().index == DeathScreen.RETRY)
	await tap(&"cancel")
	check("there is no backing out of being dead", death().is_open() and tree.paused)
	await tap(&"jump")


func test_retry_lets_the_level_run_again() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	var picked := []
	death().chosen.connect(func(index: int) -> void: picked.append(index))
	await tap(&"jump")
	check("retry was taken", picked == [DeathScreen.RETRY], str(picked))
	check("the page is gone", not death().is_open())
	check("and the level runs again", not tree.paused)


func test_the_death_screen_keeps_the_pause_button_out() -> void:
	# 两边都在改 `tree.paused`，抢起来会互相把对方解掉（终极武器定格那条是同一个道理）
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	await tap(&"pause")
	check("pausing does nothing while you are choosing", not menu().is_open())
	check("and the choice is still up", death().is_open() and tree.paused)
	await tap(&"jump")


func test_main_menu_leaves_the_level() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	await tap(&"aim_down")
	check("setup: on main menu", death().menu_list().index == DeathScreen.MAIN_MENU)
	await tap(&"jump")
	await frames(3)
	check("the level is left for the menu", tree.current_scene is MainMenu, str(tree.current_scene))
	check("and nothing is left frozen", not tree.paused)
	# **收干净**：菜单还挂在树上的话，后面的用例一按 A 就被它当成「菜单确认」接走（见 CLAUDE.md 踩过的坑）
	tree.unload_current_scene()
	await frames(2)


# ---------------------------------------------------------------- HUD

func hud() -> CanvasLayer:
	return main.get_node("HUD")


func test_the_hud_writes_in_the_pixel_font() -> void:
	await reset_scene()
	await frames(2)
	var label: Label = hud().get_node("ProgressLabel")
	var font := label.get_theme_font("font")
	# 正文用的是小那套字模（10px）；大那套 14px 留给标题，两套都只按整数倍放大
	check("the level / cash line uses the pack's small font",
		font != null and font.resource_path == UiKit.FONT_SMALL,
		"" if font == null else font.resource_path)
	check("in gold, not white", label.get_theme_color("font_color") == UiKit.GOLD,
		str(label.get_theme_color("font_color")))
	# HUD 的字直接压在关卡画面上，天空一亮笔画就糊成一团，背后得垫一层暗影。
	# **看颜色，不能只看偏移**：Label 自带的主题里偏移本来就是 1，是影子的颜色默认全透明。
	var shade := label.get_theme_color("font_shadow_color")
	check("with a shadow behind it that is dark and solid",
		shade.get_luminance() < 0.2 and shade.a > 0.5, str(shade))
	check("and offset off the glyph", label.get_theme_constant("shadow_offset_x") > 0
		and label.get_theme_constant("shadow_offset_y") > 0,
		"%d,%d" % [label.get_theme_constant("shadow_offset_x"), label.get_theme_constant("shadow_offset_y")])


func test_the_progress_line_leaves_room_for_the_other_player() -> void:
	# 双人时左右各一套，挤成一行的话（LV / XP / CASH / PTS）最宽要 414px，在屏幕中间就撞上了
	await reset_scene()
	await frames(2)
	# 20 级是这个游戏现实的上限（经验每级 ×1.5，再往上数字就有七位了，见 hud.gd 的说明）
	var me := player.progress
	me.level = 20
	me.xp = me.balance.xp_to_next(20) - 1
	me.money = 999999
	me.points = 99
	me.progress_changed.emit()
	await frames(1)
	var label: Label = hud().get_node("ProgressLabel")
	var lines := label.text.split("
")
	check("it is written on two lines", lines.size() == 2, label.text)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, label.get_theme_font("font").get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x)
	var half := 640.0 / 2.0 - 12.0
	check("even at the biggest numbers it stays in its half", widest <= half,
		"%.0f > %.0f" % [widest, half])


# ---------------------------------------------------------------- 加点

func test_spending_a_point_raises_the_stat_and_the_player() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	var before := player.max_health
	var points := player.progress.points
	check("setup: there are points to spend", points > 0, str(points))
	await tap(&"pause")
	await tap(&"aim_down")        # RESUME -> SKILLS
	await tap(&"jump")            # 进加点界面
	check("the skills screen is up", skills() != null)
	await tap(&"jump")            # 第一项是 LIFE，加一点
	check("one point is gone", player.progress.points == points - 1, str(player.progress.points))
	check("life went up", player.progress.stat(Balance.LIFE) > before, str(player.progress.stat(Balance.LIFE)))
	check("and the player got tougher right away", player.max_health > before,
		"%d -> %d" % [before, player.max_health])
	await tap(&"cancel")
	check("back to the pause menu", skills() == null and menu().is_open())
	await tap(&"cancel")
	check("and back to the game", not menu().is_open() and not tree.paused)


func test_the_cursor_picks_which_stat_gets_the_point() -> void:
	await reset_scene()
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	await tap(&"aim_down")        # LIFE -> ATTACK
	await tap(&"jump")
	check("attack took the point", player.progress.allocated.get(Balance.ATTACK, 0) == 1,
		str(player.progress.allocated))
	check("and life did not", player.progress.allocated.get(Balance.LIFE, 0) == 0, str(player.progress.allocated))


func test_the_skills_screen_also_counts_points_not_stat_points() -> void:
	# 和人物设置界面同一条规矩：金色那列写投了几点，不写属性涨了多少（生命一点涨 10）。
	await reset_scene()
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	var rows: Array = skills()._columns[0]["rows"]
	check("setup: nothing spent yet", rows[0]["bonus"].text == "", rows[0]["bonus"].text)
	await tap(&"jump")            # 第一项是 LIFE
	check("one point in life reads as +1", rows[0]["bonus"].text == "+1", rows[0]["bonus"].text)
	check("and the value beside it is the real one",
		rows[0]["value"].text == str(roundi(player.progress.stat(Balance.LIFE))), rows[0]["value"].text)
	await tap(&"cancel")
	await tap(&"cancel")


func test_running_out_of_points_stops_the_spending() -> void:
	await reset_scene()
	await frames(2)
	player.progress.points = 1
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	await tap(&"jump")
	check("setup: the last point is spent", player.progress.points == 0)
	var allocated: int = player.progress.allocated.get(Balance.LIFE, 0)
	await tap(&"jump")
	check("pressing again does nothing", player.progress.allocated.get(Balance.LIFE, 0) == allocated,
		str(player.progress.allocated))


func test_in_co_op_each_player_spends_their_own_points() -> void:
	await reset_scene(false, false, null, 2)
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	check("the screen shows a column for each player", skills() != null)
	var before := [player.progress.points, player2.progress.points]
	await tap_as(1, &"aim_down")   # 2 号把光标挪到 ATTACK
	await tap_as(1, &"jump")
	check("the second player spent one", player2.progress.points == before[1] - 1, str(player2.progress.points))
	check("on their own attack", player2.progress.allocated.get(Balance.ATTACK, 0) == 1,
		str(player2.progress.allocated))
	check("the first player's points are untouched", player.progress.points == before[0], str(player.progress.points))
	check("and so are their stats", player.progress.allocated.is_empty(), str(player.progress.allocated))
	# 两个人都按返回才退出加点界面
	await tap_as(0, &"cancel")
	check("one player backing out is not enough", skills() != null)
	await tap_as(1, &"cancel")
	check("both of them is", skills() == null and menu().is_open())
	await tap(&"cancel")
