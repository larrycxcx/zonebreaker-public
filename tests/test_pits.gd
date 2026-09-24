extends GameTest
## 坑：掉出关卡就死。
##
## 关卡的地面在 y=320、画面底边 360，`Main.fall_y`（400）再往下 40px 才算掉出去——
## 贴着地面跑不会误判，掉进坑里立刻就死。测试关（`main.tscn`）的地面是一整条、没有坑，
## 所以这里一律把人直接放到坑底下的高度来测这条规则本身。

## 坑底下（关卡判定线以下）。
func below_the_level() -> float:
	return (main.fall_y as float) + 40.0


func test_falling_into_a_pit_costs_a_third_of_your_health() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var full := player.health
	check("setup: at full health on the ground", full == player.max_health)
	player.global_position = Vector2(400, below_the_level())
	await frames(3)
	var lost := full - player.health
	check("it costs about a third", absf(lost - player.max_health / 3.0) <= 1.0,
		"lost %d of %d" % [lost, player.max_health])
	check("but you are still in the game", player.is_alive() and not player.is_downed())


func test_a_fall_puts_you_back_where_you_last_stood() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	Input.action_press("move_right")
	await frames(30)
	release_all_input()
	await frames(5)
	var stood := player.global_position
	check("setup: it walked somewhere", stood.x > 240.0, str(stood))
	player.global_position = Vector2(stood.x + 400.0, below_the_level())
	await frames(3)
	check("it is back on solid ground", player.global_position.distance_to(stood) < 24.0,
		"%s vs %s" % [player.global_position, stood])
	check("standing still, not still falling", absf(player.velocity.y) < 200.0, str(player.velocity))
	check("with a moment of safety", player.is_invincible())


func test_enough_falls_still_finish_you_off() -> void:
	# 扣到没血就照常走死亡那条路（单人直接死，双人是倒地）
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	for i in 6:
		player._shield_timer = 0.0
		player.global_position = Vector2(200, below_the_level())
		await frames(3)
		if not player.is_alive():
			break
	check("the pit gets you in the end", not player.is_alive() and player.health == 0,
		str(player.health))


func test_a_pit_does_not_care_about_the_invincible_frames() -> void:
	# 刚挨完打的那一秒无敌不该让你在坑里飘着
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var full := player.health
	player.take_damage(HIT, player.global_position + Vector2(40, 0))
	await frames(2)
	check("setup: invincible right now", player.is_invincible())
	player.global_position = Vector2(200, below_the_level())
	await frames(3)
	check("the pit takes its cut anyway", player.health < full - HIT, str(player.health))


func test_in_co_op_a_downed_player_is_fished_out_too() -> void:
	# 倒地的人已经没血可扣，但扔在坑底下队友永远够不着，所以也要捞回来
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(600, 304)
	await frames(5)
	player2.take_damage(player2.max_health)
	await frames(2)
	check("setup: down, not dead", player2.is_downed())
	player2.global_position = Vector2(600, below_the_level())
	await frames(3)
	check("it is back on the ground", player2.global_position.y < main.fall_y,
		str(player2.global_position))
	check("and still down, waiting for help", player2.is_downed())


func test_an_enemy_that_falls_in_is_cleaned_up() -> void:
	# 把追着你的 D 引到坑边推下去是玩家该有的手段，掉下去就算它死了
	await reset_scene(true)
	keep_only_enemies(["ChaserD"])
	var d: Enemy = main.get_node("Enemies/ChaserD")
	var deaths := []
	d.died.connect(func() -> void: deaths.append(true))
	d.global_position = Vector2(300, below_the_level())
	await frames(4)
	check("it dies when it drops out", deaths.size() == 1, str(deaths.size()))
	check("and does not die twice", not is_instance_valid(d) or d.is_queued_for_deletion())
