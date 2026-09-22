extends GameTest
## 敌人 D（冲锋型）：不开枪不趴下、巡逻用普通速度、240px 内看见玩家就用 150 的冲锋速度（比玩家走路慢）冲过去、
## 靠碰撞伤人、能跳墙跳平台、墙挡视线、追丢后会放弃。

const GROUND_ENEMY_Y := 306.0


## 只留 D，把它摆在地面 x 处朝 facing 站好；玩家先停在远处（射程外）。
func _setup_chaser(x: float, facing: int, keep_walls := false) -> EnemyChaser:
	await reset_scene(true, keep_walls)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	player.global_position = Vector2(x - 600.0 if x > 640.0 else x + 600.0, 304)
	player.velocity = Vector2.ZERO
	d.global_position = Vector2(x, GROUND_ENEMY_Y)
	d.velocity = Vector2.ZERO
	d.facing = facing
	d._apply_facing()
	await frames(10)
	return d


## 追击中每帧结束时，D 都应该面朝它正在追的位置（画面就是在这之后画的）。
## 光看「最后追没追到」不够：如果追击时也按巡逻规则在悬崖/墙前掉头，
## 它下一帧会重新转回来、照样追到，但画面上会看到它背对着玩家冲过来。
## 例外：玩家在正下方、它正走向平台边缘准备下去的时候（_drop_direction != 0），朝向由那个方向决定。
func _facing_wrong_way(d: EnemyChaser) -> bool:
	var offset_x := d._last_seen.x - d.global_position.x
	return d.is_chasing and d._drop_direction == 0 and absf(offset_x) > 4.0 and d.facing != signi(offset_x)


func _put_player(x: float, y := 304.0) -> void:
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO


func test_d_is_configured() -> void:
	await reset_scene(true)
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("D has as much health as the turret", d.max_health == turret.max_health and d.max_health == 6 * SHOT, "%d vs %d" % [d.max_health, turret.max_health])
	check("D has no gun", d.bullet_scene == null and d.get_node_or_null("Muzzle") == null)
	check("D never goes prone", not d.can_go_prone)
	check("D patrols at the normal enemy speed", d.move_speed == walker.move_speed, "%.1f vs %.1f" % [d.move_speed, walker.move_speed])
	check("D charges at 150", d.charge_speed == 150.0, "%.1f" % d.charge_speed)
	check("D charges slower than the player walks", d.charge_speed < player.move_speed, "%.1f vs %.1f" % [d.charge_speed, player.move_speed])
	check("D notices the player within 240px", d.detect_range == 240.0)
	check("D jumps like the player", d.jump_velocity == player.jump_velocity)


func test_d_patrols_at_normal_speed() -> void:
	var d := await _setup_chaser(500.0, 1)
	await frames(20)
	check("D patrols while the player is far away", not d.is_chasing)
	check("patrol speed is the normal enemy speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_charges_when_it_sees_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(300.0)
	await frames(5)
	check("D starts chasing", d.is_chasing)
	check("D charges at 150", is_equal_approx(d.velocity.x, -150.0), "%.1f" % d.velocity.x)


func test_d_turns_around_for_a_player_behind_it() -> void:
	# D 看的是直线距离，不分前后：玩家在背后也会转身冲过去（巡逻兵只看正前方）。
	var d := await _setup_chaser(500.0, 1)
	_put_player(300.0)
	await frames(5)
	check("D turns toward a player behind it", d.facing == -1 and d.velocity.x < 0.0, "facing %d, vx %.1f" % [d.facing, d.velocity.x])


func test_d_ignores_a_player_beyond_120px() -> void:
	var d := await _setup_chaser(500.0, 1)
	_put_player(240.0) # 260px，刚好在发现距离外
	await frames(30)
	check("D keeps patrolling at 130px", not d.is_chasing and d.facing == 1)
	check("still at patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_never_shoots_or_lies_down() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(360.0)
	Input.action_press("crouch")
	var ever_prone := false
	var enemy_bullets := 0
	for i in 150:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_prone = ever_prone or d.is_prone
		enemy_bullets += bullets(16).size()
	check("D never fires", enemy_bullets == 0, str(enemy_bullets))
	check("D never lies down", not ever_prone)


func test_d_hurts_by_touching_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(380.0)
	var hurt_at := -1
	for i in 120:
		await tree.physics_frame
		if player.health < player.max_health:
			hurt_at = i
			break
	check("D reaches the player and hurts it by contact", hurt_at >= 0, "hurt after %d frames" % hurt_at)
	check("no bullets were involved", bullets(16).is_empty())


func test_walls_block_d_vision() -> void:
	# Wall2：x 800..816，高 56。D 在墙右边，玩家在墙左边，距离 140px（在 240 以内）。
	var d := await _setup_chaser(900.0, 1, true)
	_put_player(760.0)
	var ever_chased := false
	var crossed := false
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_chased = ever_chased or d.is_chasing
		crossed = crossed or d.global_position.x < 816.0
	check("D does not notice a player hidden behind a wall", not ever_chased)
	check("so it never comes over the wall", not crossed, "x=%.1f" % d.global_position.x)


func test_d_follows_the_player_over_a_wall() -> void:
	# D 先看见玩家（中间没墙），玩家再翻过 Wall2 逃跑：D 要追到最后看见的位置并跳墙追过去。
	var d := await _setup_chaser(1040.0, -1, true)
	_put_player(880.0)
	await frames(5)
	check("D spots the player first", d.is_chasing)
	Input.action_press("move_left")
	var jumped := false
	var crossed_at := -1
	var wrong_way_frames := 0
	for i in 300:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		wrong_way_frames += 1 if _facing_wrong_way(d) else 0
		if not jumped and player.global_position.x < 860.0:
			Input.action_press("jump")
			jumped = true
		if d.global_position.x < 800.0:
			crossed_at = i
			break
	check("D jumps over the wall after the player", crossed_at >= 0, "D at x=%.1f" % d.global_position.x)
	check("D faces where it is heading the whole time", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_jumps_up_onto_a_platform() -> void:
	# 玩家站在 Platform1（单向，x 160..256，顶面 y=256）上，D 在下面的地面上。
	var d := await _setup_chaser(380.0, -1)
	_put_player(208.0, 240.0)
	var landed := false
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if d.is_on_floor() and absf(d.global_position.y - 240.0) < 1.5:
			landed = true
			break
	check("D jumps up and lands on the player's platform", landed, "D at %s" % d.global_position)


func test_d_charges_off_its_platform() -> void:
	# 关卡里的真实摆放：D 在 Platform6（x 1000..1096，顶面 y=184）上，玩家走到下面的地面上。
	await reset_scene(true, true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	_put_player(920.0)
	var reached_ground := false
	var wrong_way_frames := 0
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		wrong_way_frames += 1 if _facing_wrong_way(d) else 0
		if d.is_on_floor() and d.global_position.y > 300.0:
			reached_ground = true
			break
	check("D drops off its platform to chase the player", reached_ground, "D at %s" % d.global_position)
	check("D lands near the player instead of overshooting", absf(d.global_position.x - player.global_position.x) < 100.0, "D at x=%.1f, player at x=%.1f" % [d.global_position.x, player.global_position.x])
	check("D does not turn away at the platform edge", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_gives_up_after_losing_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(360.0)
	await frames(5)
	check("D is chasing", d.is_chasing)
	_put_player(1120.0) # 突然跑出 240px 外
	var gave_up_at := -1
	for i in 240:
		await tree.physics_frame
		if not d.is_chasing:
			gave_up_at = i
			break
	check("D gives up within its 2s memory", gave_up_at >= 0 and gave_up_at <= 125, "after %d frames" % gave_up_at)
	await frames(10)
	check("and goes back to patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_gets_down_when_the_player_is_right_below() -> void:
	# D 站在 Platform1（单向，x 160..256，顶面 y=256）正中间，玩家就在它正下方的地面上。
	# 单向平台不挡视线，D 一直看得见玩家；它必须自己走下平台，而不是停在头顶干等。
	await reset_scene(true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(208, 240)
	d.velocity = Vector2.ZERO
	_put_player(208.0)
	var reached_ground_at := -1
	var hurt := false
	for i in 180:
		await tree.physics_frame
		if reached_ground_at < 0 and d.is_on_floor() and d.global_position.y > 300.0:
			reached_ground_at = i
		# 不能一碰到玩家就跳出：D 是边往下掉边撞上玩家的，那时它还没落地，
		# 提前 break 会让「它确实自己下来了」这条断言永远看不到落地那一帧。
		hurt = hurt or player.health < player.max_health
	check("D walks off the platform to get to the player below", reached_ground_at >= 0, "D at %s" % d.global_position)
	check("and then reaches the player", hurt)
	check("it lands close to the player", absf(d.global_position.x - 208.0) < 60.0, "x=%.1f" % d.global_position.x)


func test_one_way_platform_sides_do_not_make_d_jump() -> void:
	# D 站在 Wall2 顶上（x 800..816，顶面 y=264），正前方是 Platform5（单向，x 840..936，y 248..264）的侧面，
	# 高度正好对着它的前方检测射线。单向平台横着能穿过去，D 应该直接走过去追玩家，而不是当成墙起跳。
	await reset_scene(true, true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(808, 250)
	d.velocity = Vector2.ZERO
	d.facing = 1
	d._apply_facing()
	_put_player(960.0)
	var ever_rose := false
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_rose = ever_rose or d.velocity.y < 0.0
		if d.is_on_floor() and d.global_position.y > 300.0:
			break
	check("D does not jump at the side of a one-way platform", not ever_rose)
	check("D gets down to the player", d.global_position.y > 300.0, "D at %s" % d.global_position)


## D 冲锋时，玩家往反方向跑，隔 1 秒前后比较双方的距离。
func _gap_after_running_away(sprint: bool) -> Array:
	var d := await _setup_chaser(760.0, 1)
	_put_player(840.0)
	await frames(5)
	var chasing := d.is_chasing
	Input.action_press("move_right")
	if sprint:
		Input.action_press("sprint")
	await frames(20) # 先让双方都加速到稳定速度
	var gap_before := player.global_position.x - d.global_position.x
	await frames(60)
	var gap_after := player.global_position.x - d.global_position.x
	release_all_input()
	return [chasing, gap_before, gap_after]


func test_walking_away_keeps_ahead_of_d() -> void:
	var r := await _gap_after_running_away(false)
	check("D was chasing", r[0])
	check("walking away, D does not close the gap", r[2] >= r[1], "%.1f -> %.1f" % [r[1], r[2]])


func test_sprinting_away_outruns_d() -> void:
	var r := await _gap_after_running_away(true)
	check("D was chasing", r[0])
	# 奔跑 270 对冲锋 150，一秒拉开约 120px。
	check("sprinting away opens a clear gap", r[2] - r[1] > 80.0, "%.1f -> %.1f" % [r[1], r[2]])
