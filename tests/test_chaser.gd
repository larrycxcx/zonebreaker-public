extends GameTest
## 敌人 D（冲锋型）：不开枪不趴下、巡逻用普通速度、150px 内看见玩家就用 1.7 倍速冲过去、
## 靠碰撞伤人、能跳墙跳平台、墙挡视线、追丢后会放弃。

const GROUND_ENEMY_Y := 153.0


## 只留 D，把它摆在地面 x 处朝 facing 站好；玩家先停在远处（射程外）。
func _setup_chaser(x: float, facing: int, keep_walls := false) -> EnemyChaser:
	await reset_scene(true, keep_walls)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	player.global_position = Vector2(x - 300.0 if x > 320.0 else x + 300.0, 152)
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
func _facing_wrong_way(d: EnemyChaser) -> bool:
	var offset_x := d._last_seen.x - d.global_position.x
	return d.is_chasing and absf(offset_x) > 4.0 and d.facing != signi(offset_x)


func _put_player(x: float, y := 152.0) -> void:
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO


func test_d_is_configured() -> void:
	await reset_scene(true)
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("D has as much health as the turret", d.max_health == turret.max_health and d.max_health == 6, "%d vs %d" % [d.max_health, turret.max_health])
	check("D has no gun", d.bullet_scene == null and d.get_node_or_null("Visual/Muzzle") == null)
	check("D never goes prone", not d.can_go_prone)
	check("D patrols at the normal enemy speed", d.move_speed == walker.move_speed, "%.1f vs %.1f" % [d.move_speed, walker.move_speed])
	check("D charges 70% faster", is_equal_approx(d.charge_speed_scale, 1.7))
	check("D notices the player within 150px", d.detect_range == 150.0)
	check("D jumps like the player", d.jump_velocity == player.jump_velocity)


func test_d_patrols_at_normal_speed() -> void:
	var d := await _setup_chaser(250.0, 1)
	await frames(20)
	check("D patrols while the player is far away", not d.is_chasing)
	check("patrol speed is the normal enemy speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_charges_when_it_sees_the_player() -> void:
	var d := await _setup_chaser(250.0, -1)
	_put_player(150.0)
	await frames(5)
	check("D starts chasing", d.is_chasing)
	check("D charges at 1.7x its patrol speed", is_equal_approx(d.velocity.x, -d.move_speed * 1.7), "%.1f" % d.velocity.x)


func test_d_turns_around_for_a_player_behind_it() -> void:
	# D 看的是直线距离，不分前后：玩家在背后也会转身冲过去（巡逻兵只看正前方）。
	var d := await _setup_chaser(250.0, 1)
	_put_player(150.0)
	await frames(5)
	check("D turns toward a player behind it", d.facing == -1 and d.velocity.x < 0.0, "facing %d, vx %.1f" % [d.facing, d.velocity.x])


func test_d_ignores_a_player_beyond_150px() -> void:
	var d := await _setup_chaser(250.0, 1)
	_put_player(80.0) # 170px
	await frames(30)
	check("D keeps patrolling at 170px", not d.is_chasing and d.facing == 1)
	check("still at patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_never_shoots_or_lies_down() -> void:
	var d := await _setup_chaser(250.0, -1)
	_put_player(180.0)
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
	var d := await _setup_chaser(250.0, -1)
	_put_player(190.0)
	var hurt_at := -1
	for i in 120:
		await tree.physics_frame
		if player.health < player.max_health:
			hurt_at = i
			break
	check("D reaches the player and hurts it by contact", hurt_at >= 0, "hurt after %d frames" % hurt_at)
	check("no bullets were involved", bullets(16).is_empty())


func test_walls_block_d_vision() -> void:
	# Wall2：x 400..408，高 28。D 在墙右边，玩家在墙左边，距离 70px（在 150 以内）。
	var d := await _setup_chaser(450.0, 1, true)
	_put_player(380.0)
	var ever_chased := false
	var crossed := false
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_chased = ever_chased or d.is_chasing
		crossed = crossed or d.global_position.x < 408.0
	check("D does not notice a player hidden behind a wall", not ever_chased)
	check("so it never comes over the wall", not crossed, "x=%.1f" % d.global_position.x)


func test_d_follows_the_player_over_a_wall() -> void:
	# D 先看见玩家（中间没墙），玩家再翻过 Wall2 逃跑：D 要追到最后看见的位置并跳墙追过去。
	var d := await _setup_chaser(520.0, -1, true)
	_put_player(440.0)
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
		if not jumped and player.global_position.x < 430.0:
			Input.action_press("jump")
			jumped = true
		if d.global_position.x < 400.0:
			crossed_at = i
			break
	check("D jumps over the wall after the player", crossed_at >= 0, "D at x=%.1f" % d.global_position.x)
	check("D faces where it is heading the whole time", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_jumps_up_onto_a_platform() -> void:
	# 玩家站在 Platform1（单向，x 80..128，顶面 y=128）上，D 在下面的地面上。
	var d := await _setup_chaser(190.0, -1)
	_put_player(104.0, 120.0)
	var landed := false
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if d.is_on_floor() and absf(d.global_position.y - 121.0) < 1.5:
			landed = true
			break
	check("D jumps up and lands on the player's platform", landed, "D at %s" % d.global_position)


func test_d_charges_off_its_platform() -> void:
	# 关卡里的真实摆放：D 在 Platform6（x 500..548，顶面 y=92）上，玩家走到下面的地面上。
	await reset_scene(true, true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	_put_player(460.0)
	var reached_ground := false
	var wrong_way_frames := 0
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		wrong_way_frames += 1 if _facing_wrong_way(d) else 0
		if d.is_on_floor() and d.global_position.y > 150.0:
			reached_ground = true
			break
	check("D drops off its platform to chase the player", reached_ground, "D at %s" % d.global_position)
	check("D does not turn away at the platform edge", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_gives_up_after_losing_the_player() -> void:
	var d := await _setup_chaser(250.0, -1)
	_put_player(180.0)
	await frames(5)
	check("D is chasing", d.is_chasing)
	_put_player(560.0) # 突然跑出 150px 外
	var gave_up_at := -1
	for i in 240:
		await tree.physics_frame
		if not d.is_chasing:
			gave_up_at = i
			break
	check("D gives up within its 2s memory", gave_up_at >= 0 and gave_up_at <= 125, "after %d frames" % gave_up_at)
	await frames(10)
	check("and goes back to patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))
