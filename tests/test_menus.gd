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
