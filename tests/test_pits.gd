extends GameTest
## 坑：掉出关卡就死。
##
## 关卡的地面在 y=320、画面底边 360，`Main.fall_y`（400）再往下 40px 才算掉出去——
## 贴着地面跑不会误判，掉进坑里立刻就死。测试关（`main.tscn`）的地面是一整条、没有坑，
## 所以这里一律把人直接放到坑底下的高度来测这条规则本身。

## 坑底下（关卡判定线以下）。
func below_the_level() -> float:
	return (main.fall_y as float) + 40.0


func test_falling_out_of_the_level_kills_the_player() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: alive on the ground", player.is_alive())
	player.global_position = Vector2(200, below_the_level())
	await frames(2)
	check("falling out kills", not player.is_alive() and player.health == 0, str(player.health))
	check("and it is a real death, not a knockdown", not player.is_downed())


func test_the_ground_is_never_mistaken_for_a_pit() -> void:
	# 判定线要在地面**下面**留出余量：站着、跑着、跳着都不能误判
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	Input.action_press("move_right")
	for i in 60:
		await tree.physics_frame
		if not player.is_alive():
			break
	release_all_input()
	check("running along the ground is safe", player.is_alive(), str(player.global_position))
	check("and the line really is below the floor", main.fall_y > player.global_position.y,
		"%.0f vs %.0f" % [main.fall_y, player.global_position.y])


func test_a_pit_beats_the_invincible_frames() -> void:
	# 刚挨完打的那一秒无敌不该让你在坑里飘着
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	player.take_damage(HIT, player.global_position + Vector2(40, 0))
	await frames(2)
	check("setup: invincible right now", player.is_invincible())
	player.global_position = Vector2(200, below_the_level())
	await frames(2)
	check("the pit kills anyway", not player.is_alive())


func test_in_co_op_a_pit_kills_outright() -> void:
	# 人在坑底，队友走不过去也救不了，挂个救不起来的倒计时只是让人干等
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(260, 304)
	await frames(2)
	check("setup: two players up and about", player.is_alive() and player2.is_alive())
	player.global_position = Vector2(200, below_the_level())
	await frames(2)
	check("the one who fell is dead, not down", not player.is_alive() and not player.is_downed())
	check("and the team mate carries on", player2.is_alive())


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
