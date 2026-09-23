extends GameTest
## 双人（第一步：输入分开、敌人认两个玩家）。
##
## 守的东西：双人时才生成 2 号；两套输入互不干扰；方向键双人时归 2 号、切回单人还给 1 号；
## 每个 2 号动作都有键盘和 2 号手柄的绑定；敌人打**最近的、打得着的**那个（最近的躲墙后就打另一个），
## 死掉的玩家不再被当目标；终极武器让两个人一起无敌。

const P1_ACTIONS := ["move_left", "move_right", "jump", "crouch", "sprint", "shoot", "switch_weapon", "ultimate", "aim_down", "aim_up"]


func arrows_of(action: StringName) -> Array:
	return InputMap.action_get_events(action).filter(func(event: InputEvent) -> bool:
		return event is InputEventKey and Session.SHARED_KEYS.has((event as InputEventKey).physical_keycode))


func pads_of(action: StringName) -> Array:
	return InputMap.action_get_events(action).filter(func(event: InputEvent) -> bool:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion)


# ---------------------------------------------------------------- 谁在场

func test_the_second_player_only_shows_up_in_two_player() -> void:
	await reset_scene()
	check("one player by default", player2 == null and tree.get_nodes_in_group(&"player").size() == 1)
	await reset_scene(false, false, null, 2)
	check("two players in co-op", player2 != null and tree.get_nodes_in_group(&"player").size() == 2)
	check("they are numbered", player.player_index == 0 and player2.player_index == 1)
	check("and start side by side", absf(player2.global_position.x - player.global_position.x) < 64.0
		and absf(player2.global_position.y - player.global_position.y) < 1.0, str(player2.global_position - player.global_position))


# ---------------------------------------------------------------- 输入分开

func test_every_action_has_a_second_player_copy() -> void:
	for action in P1_ACTIONS:
		var second := StringName("p2_" + action)
		check("%s has a second-player action" % action, InputMap.has_action(second))
		if not InputMap.has_action(second):
			continue
		var keys := InputMap.action_get_events(second).filter(func(event: InputEvent) -> bool: return event is InputEventKey)
		check("%s: keyboard and gamepad" % second, not keys.is_empty() and not pads_of(second).is_empty())
		check("%s: on the second gamepad" % second, pads_of(second).all(func(event: InputEvent) -> bool: return event.device == 1))
		check("%s: on the first gamepad" % action, pads_of(action).all(func(event: InputEvent) -> bool: return event.device == 0))


func test_the_arrow_keys_move_to_the_second_player_in_co_op() -> void:
	Session.set_player_count(1)
	var solo := arrows_of(&"move_left").size()
	check("solo: the first player keeps the arrow keys", solo > 0, str(solo))
	Session.set_player_count(2)
	check("co-op: the first player gives them up", arrows_of(&"move_left").is_empty())
	check("and the second player has them", not arrows_of(&"p2_move_left").is_empty())
	Session.set_player_count(1)
	check("back to solo: they come back", arrows_of(&"move_left").size() == solo, str(arrows_of(&"move_left").size()))


func test_each_player_answers_only_to_its_own_keys() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(300, 304)
	await frames(2)
	var start := [player.global_position.x, player2.global_position.x]
	Input.action_press("p2_move_right")
	await frames(20)
	release_all_input()
	check("the second player's key moves only the second player",
		player2.global_position.x - start[1] > 10.0 and absf(player.global_position.x - start[0]) < 1.0,
		"P1 %.1f, P2 %.1f" % [player.global_position.x - start[0], player2.global_position.x - start[1]])
	# 上一段松手后 2 号还有惯性，会再滑一小段：停稳了再看下一段
	player.velocity = Vector2.ZERO
	player2.velocity = Vector2.ZERO
	await frames(2)
	start = [player.global_position.x, player2.global_position.x]
	Input.action_press("move_right")
	await frames(20)
	release_all_input()
	check("and the first player's key moves only the first player",
		player.global_position.x - start[0] > 10.0 and absf(player2.global_position.x - start[1]) < 1.0,
		"P1 %.1f, P2 %.1f" % [player.global_position.x - start[0], player2.global_position.x - start[1]])


func test_the_second_player_shoots_with_its_own_key() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(300, 304)
	await frames(2)
	Input.action_press("p2_shoot")
	await frames(3)
	release_all_input()
	var shots := bullets(4)
	check("the second player fires", not shots.is_empty())
	if not shots.is_empty():
		check("from the second player, not the first",
			shots.all(func(shot: Bullet) -> bool: return absf(shot.global_position.x - player2.global_position.x) < 60.0), str(shots.size()))


# ---------------------------------------------------------------- 共用摄像机

func test_the_camera_belongs_to_the_level_not_to_a_player() -> void:
	await reset_scene()
	check("the level owns the camera", camera_rig() != null and camera_rig() is CameraRig)
	check("and no player carries one", player.get_node_or_null("Camera2D") == null)


func test_solo_keeps_the_camera_on_the_one_player() -> void:
	# 单人时中点就是这个玩家本人，画面和摄像机还挂在玩家身上那会儿一模一样。
	await reset_scene()
	player.global_position = Vector2(400, 304)
	await frames(3)
	check("the camera sits on the player", absf(camera_rig().global_position.x - player.global_position.x) < 0.5,
		"%.1f vs %.1f" % [camera_rig().global_position.x, player.global_position.x])
	# 对照：单人永远夹不到人，走到哪都不会被镜头推着走
	var spot := player.global_position
	await frames(5)
	check("and never pushes them around", absf(player.global_position.x - spot.x) < 0.5, str(player.global_position - spot))


func test_co_op_follows_the_middle_of_the_two() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(500, 304)
	await frames(3)
	check("the camera sits between them",
		absf(camera_rig().global_position.x - 400.0) < 1.0, "%.1f" % camera_rig().global_position.x)


func test_neither_player_can_be_pushed_off_screen() -> void:
	# 魂斗罗的规矩：镜头跟中点，谁落在画面外就被拖回来。分头走只能走到画面两边为止。
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(1100, 304)
	await frames(3)
	var view := camera_rig().view_rect()
	check("setup: they are further apart than one screen", view.size.x < 900.0, "画面宽 %.0f" % view.size.x)
	for who in [player, player2]:
		check("%s is back inside the view" % who.name, view.grow(-1.0).has_point(who.global_position),
			"x=%.1f，画面 %.1f..%.1f" % [who.global_position.x, view.position.x, view.end.x])
	check("and they really did get dragged together",
		absf(player2.global_position.x - player.global_position.x) < 900.0,
		"%.1f" % absf(player2.global_position.x - player.global_position.x))


func test_a_dead_player_neither_drags_the_camera_nor_gets_dragged() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(700, 304)
	await frames(3)
	check("setup: the camera is between them", absf(camera_rig().global_position.x - 500.0) < 1.0,
		"%.1f" % camera_rig().global_position.x)
	player2.take_damage(player2.health)
	await frames(3)
	check("once one dies the camera follows the living one",
		absf(camera_rig().global_position.x - player.global_position.x) < 1.0,
		"%.1f vs %.1f" % [camera_rig().global_position.x, player.global_position.x])


# ---------------------------------------------------------------- 各存各的成长进度

const SAVE_FOR_TEST := "user://test_coop_progress.json"


func drop_test_save() -> void:
	Progress.persist = false
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


func test_each_player_has_their_own_progress() -> void:
	await reset_scene(false, false, null, 2)
	check("two separate profiles", Progress.of(0) != Progress.of(1))
	check("each player holds their own", player.progress == Progress.of(0) and player2.progress == Progress.of(1))
	Progress.of(0).add_xp(Progress.balance.xp_to_next(1))
	Progress.of(0).add_money(50)
	await frames(2)
	check("levelling one does not level the other",
		Progress.of(0).level == 2 and Progress.of(1).level == 1,
		"P1 Lv%d, P2 Lv%d" % [Progress.of(0).level, Progress.of(1).level])
	check("and the money stays apart", Progress.of(0).money == 50 and Progress.of(1).money == 0,
		"P1 $%d, P2 $%d" % [Progress.of(0).money, Progress.of(1).money])


func test_a_stat_point_only_reaches_its_own_player() -> void:
	await reset_scene(false, false, null, 2)
	var before := [player.max_health, player2.max_health]
	check("setup: both start the same", before[0] == before[1], str(before))
	Progress.of(1).points = 1
	Progress.of(1).spend_point(Balance.LIFE)
	await frames(2)
	check("the second player gets tougher", player2.max_health > before[1],
		"%d -> %d" % [before[1], player2.max_health])
	check("the first player is untouched", player.max_health == before[0],
		"%d -> %d" % [before[0], player.max_health])


func test_the_kill_pays_whoever_made_it() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["WalkerA"])
	var walker: Enemy = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(500, 304)
	walker._fire_timer = 999.0
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(400, 304)
	await frames(2)
	var before := [Progress.of(0).xp, Progress.of(1).xp]
	Input.action_press("p2_shoot")
	for i in 120:
		await tree.physics_frame
		if not is_instance_valid(walker):
			break
	release_all_input()
	check("the second player shot it dead", not is_instance_valid(walker))
	check("so the second player is paid", Progress.of(1).xp > before[1],
		"%d -> %d" % [before[1], Progress.of(1).xp])
	check("and the first player, who never fired, is not", Progress.of(0).xp == before[0],
		"%d -> %d" % [before[0], Progress.of(0).xp])


func test_the_save_holds_both_players() -> void:
	await reset_scene(false, false, null, 2)
	Progress.save_path = SAVE_FOR_TEST
	Progress.persist = true
	Progress.of(0).add_money(30)
	Progress.of(1).add_money(70)
	Progress.new_game()
	check("setup: a new game forgets it all", Progress.of(0).money == 0 and Progress.of(1).money == 0)
	Progress.load_game()
	check("both purses come back", Progress.of(0).money == 30 and Progress.of(1).money == 70,
		"P1 $%d, P2 $%d" % [Progress.of(0).money, Progress.of(1).money])
	drop_test_save()


func test_a_save_from_before_co_op_still_loads() -> void:
	# 双人之前的存档是一份进度直接摊在最外层，没有 players 这一项。读到那种就当成 1 号的。
	await reset_scene(false, false, null, 2)
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"level": 3, "xp": 4, "money": 99, "points": 2}))
	file.close()
	Progress.save_path = SAVE_FOR_TEST
	Progress.load_game()
	check("the old save becomes the first player", Progress.of(0).level == 3 and Progress.of(0).money == 99,
		"Lv%d $%d" % [Progress.of(0).level, Progress.of(0).money])
	check("and the second player starts fresh", Progress.of(1).level == 1 and Progress.of(1).money == 0,
		"Lv%d $%d" % [Progress.of(1).level, Progress.of(1).money])
	drop_test_save()


# ---------------------------------------------------------------- 敌人认两个玩家

func test_an_enemy_goes_for_the_nearest_player_it_can_see() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600, 306)
	d.velocity = Vector2.ZERO
	player.global_position = Vector2(300, 304)   # 远
	player2.global_position = Vector2(700, 304)  # 近
	snap_camera()
	await frames(5)
	check("it charges the nearer player", d.is_chasing and d.velocity.x > 0.0, "vx %.1f" % d.velocity.x)
	# 近的那个躲到墙后：改打看得见的那个（不是简单挑最近的）
	add_wall(660, 60)
	await frames(5)
	check("with the nearer one behind a wall, it goes for the other", d.velocity.x < 0.0, "vx %.1f" % d.velocity.x)


func test_a_dead_player_is_no_longer_a_target() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600, 306)
	d.velocity = Vector2.ZERO
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(700, 304)
	snap_camera()
	await frames(5)
	check("setup: chasing the nearer (second) player", d.velocity.x > 0.0, "vx %.1f" % d.velocity.x)
	player2.take_damage(player2.health)
	await frames(5)
	check("once it dies, the enemy turns to the living one", d.velocity.x < 0.0, "vx %.1f" % d.velocity.x)


func test_the_ultimate_protects_both_players() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(240, 304)
	await frames(2)
	Input.action_press("ultimate")
	await frames(2)
	release_all_input()
	check("both players are invincible during the freeze", player.is_invincible() and player2.is_invincible())
	for i in 300:
		if not tree.paused:
			break
		await tree.physics_frame
	tree.paused = false
