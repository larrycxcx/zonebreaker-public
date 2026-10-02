extends GameTest
## 纵向关的引擎规则（第四关地下室是往上爬的，魂斗罗瀑布关那种）。
##
## 还没有真的纵向关卡，所以每条用例都在测试关上**临时往上搭几层浮台**当竖井用，
## 把摄像机切成 `only_up`、上边界放开。测的是规则本身：
## 画面只往上卷、掉出画面底边就按掉坑算、捞回到画面里、被甩在底下的敌人悄悄收走。
## 横向关一条都不受影响（`only_up` 默认关着），最后一条守着这个。

const GROUND_Y := 320.0
## 竖井往上放开多高（四屏）。
const SHAFT_TOP := -1440.0


func open_shaft(players := 1) -> void:
	await reset_scene(false, false, null, players)
	var rig := camera_rig()
	rig.only_up = true
	rig.limit_top = int(SHAFT_TOP)


## 搭一块单向浮台，顶边在 `top`。
func add_ledge(x: float, top: float, wide := 160.0) -> Platform:
	var ledge: Platform = load("res://scenes/platform.tscn").instantiate()
	ledge.one_way = true
	ledge.position = Vector2(x, top)
	ledge.size = Vector2(wide, 16)
	main.get_node("Level").add_child(ledge)
	return ledge


## 把人放到某块浮台上站稳（站稳了「最后站稳的地方」才会记下来）。
func stand_on(who: Player, ledge: Platform) -> void:
	who.global_position = Vector2(ledge.position.x + ledge.size.x / 2.0, ledge.position.y - 16.0)
	who.velocity = Vector2.ZERO
	await frames(12)


func test_the_screen_climbs_with_you_and_never_comes_back_down() -> void:
	await open_shaft()
	var high := add_ledge(240, -200)
	var lower := add_ledge(240, -100)
	await frames(5)
	var at_start := camera_rig().view_rect()
	await stand_on(player, high)
	var up_there := camera_rig().view_rect()
	check("the screen climbs with you", up_there.position.y < at_start.position.y - 100.0,
		"%.0f -> %.0f" % [at_start.position.y, up_there.position.y])
	# 往下走一层（还在画面里）：画面不跟着下来
	await stand_on(player, lower)
	var after := camera_rig().view_rect()
	check("setup: you really went down a floor", player.global_position.y > high.position.y + 50.0,
		str(player.global_position))
	check("but the screen stays where it got to", absf(after.position.y - up_there.position.y) < 0.5,
		"%.0f vs %.0f" % [after.position.y, up_there.position.y])


func test_on_a_side_scrolling_level_the_screen_still_follows_you_down() -> void:
	# 对照：同样的走法，横向关（`only_up` 关着）画面照常跟回来
	await reset_scene()
	camera_rig().limit_top = int(SHAFT_TOP)
	var high := add_ledge(240, -200)
	var lower := add_ledge(240, -100)
	await stand_on(player, high)
	var up_there := camera_rig().view_rect()
	await stand_on(player, lower)
	check("the camera comes back down with you",
		camera_rig().view_rect().position.y > up_there.position.y + 50.0,
		"%.0f vs %.0f" % [camera_rig().view_rect().position.y, up_there.position.y])


func test_dropping_out_of_the_bottom_of_the_screen_is_a_fall() -> void:
	await open_shaft()
	var high := add_ledge(240, -400)
	await stand_on(player, high)
	var full := player.health
	var stood := player.global_position
	var view := camera_rig().view_rect()
	# 画面底边以下一截——**比关卡固定的判定线（400）高得多**，横向关的规矩管不到这儿
	var below := view.end.y + 60.0
	check("setup: this is well above the old fixed line", below < main.fall_y - 200.0,
		"%.0f vs %.0f" % [below, main.fall_y])
	player.global_position = Vector2(320, below)
	await frames(3)
	var lost := full - player.health
	check("it costs a third, like any pit", absf(lost - player.max_health / 3.0) <= 1.0,
		"lost %d of %d" % [lost, player.max_health])
	check("and puts you back where you last stood", player.global_position.distance_to(stood) < 24.0,
		"%s vs %s" % [player.global_position, stood])
	check("which is on screen", camera_rig().view_rect().has_point(player.global_position))


func test_the_screen_follows_whoever_climbs_highest() -> void:
	await open_shaft(2)
	var high := add_ledge(240, -500)
	await frames(5)
	await stand_on(player, high)
	var view := camera_rig().view_rect()
	check("the leader is on screen", view.has_point(player.global_position),
		"%s in %s" % [player.global_position, view])
	check("and the screen has left the ground behind", view.end.y < GROUND_Y,
		"%.0f" % view.end.y)


func test_a_partner_left_behind_falls_out_and_lands_beside_the_leader() -> void:
	# 魂斗罗的规矩：领头的往上爬，落后的被甩出底边就算掉坑。
	# 但**捞回最后站稳的地方**在这儿行不通——那块地已经卷出画面了，捞回去马上又掉一次。
	await open_shaft(2)
	var high := add_ledge(240, -500)
	await frames(5)
	var full := player2.health
	await stand_on(player, high)
	await frames(5)
	var view := camera_rig().view_rect()
	var lost := full - player2.health
	check("the one left on the ground took a fall", absf(lost - player2.max_health / 3.0) <= 1.0,
		"lost %d of %d" % [lost, player2.max_health])
	check("and is back on screen", view.has_point(player2.global_position),
		"%s in %s" % [player2.global_position, view])
	check("next to the leader", player2.global_position.distance_to(player._safe_spot) < 24.0,
		"%s vs %s" % [player2.global_position, player._safe_spot])
	# 捞上来之后不该再掉一次
	var after := player2.health
	await frames(30)
	check("and stays there", player2.health == after, "%d -> %d" % [after, player2.health])


func test_enemies_left_far_below_are_cleared_without_a_reward() -> void:
	await open_shaft()
	var left_behind := (load("res://scenes/enemy_1_a.tscn") as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(left_behind)
	left_behind.global_position = Vector2(500, GROUND_Y - 16.0)
	var high := add_ledge(240, -500)
	var nearby := (load("res://scenes/enemy_1_a.tscn") as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(nearby)
	nearby.global_position = Vector2(high.position.x + 140.0, high.position.y - 16.0)
	nearby.set_physics_process(false)
	var money := player.progress.money
	var xp := player.progress.xp
	await stand_on(player, high)
	await frames(5)
	check("the one far below is gone", not is_instance_valid(left_behind))
	check("the one on screen is still there", is_instance_valid(nearby))
	check("no reward for it", player.progress.money == money and player.progress.xp == xp,
		"money %d -> %d, xp %d -> %d" % [money, player.progress.money, xp, player.progress.xp])
	check("and nobody reports it killed", not events.has(&"enemy_death"), str(events))


func test_side_scrolling_levels_do_not_switch_this_on() -> void:
	# 纵向的规矩是关卡自己开的：测试关和前三关都不开
	for path in ["res://scenes/main.tscn", "res://scenes/level_1.tscn",
			"res://scenes/level_2.tscn", "res://scenes/level_3.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var rig := scene.get_node("Camera2D") as CameraRig
		check("%s scrolls sideways" % path.get_file(), rig != null and not rig.only_up)
		scene.free()
