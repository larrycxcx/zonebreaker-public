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
