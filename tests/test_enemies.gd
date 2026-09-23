extends GameTest
## 敌人行为、伤害判定、玩家血量与无敌帧。这组用例要保留敌人，所以都用 `reset_scene(true)`。


func test_level_setup() -> void:
	await reset_scene(true)
	check("9 enemies in the level (8 normal + 1 boss)", enemies().size() == 9, str(main.get_node("Enemies").get_child_count()))
	check("player starts at full health: three hits", player.health == 3 * HIT and player.max_health == 3 * HIT, str(player.health))
	check("hud health bar starts full", (main.get_node("HUD/HealthBar/Fill") as ColorRect).size.x == (main.get_node("HUD/HealthBar") as ColorRect).size.x)


func test_enemies_stand_where_placed() -> void:
	await reset_scene(true)
	await frames(40)
	var walker1: EnemyWalker = main.get_node("Enemies/WalkerA")
	var walker2: EnemyWalker = main.get_node("Enemies/WalkerB")
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	check("ground walker stands on the ground", walker1.is_on_floor() and absf(walker1.global_position.y - 306.0) < 4.0, str(walker1.global_position))
	check("platform walker stands on its platform", walker2.is_on_floor() and absf(walker2.global_position.y - 178.0) < 4.0, str(walker2.global_position))
	check("turret stands on the ground", turret.is_on_floor(), str(turret.global_position))


func test_walker_patrols() -> void:
	await reset_scene(true)
	await frames(40)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var start_x := walker.global_position.x
	await frames(60)
	check("walker moves along the ground", absf(walker.global_position.x - start_x) > 20.0, "%.1f -> %.1f" % [start_x, walker.global_position.x])


func test_walker_turns_at_ledges() -> void:
	await reset_scene(true)
	await frames(40)
	# Platform4：x 640..384。巡逻兵必须在边缘掉头，不能走下去。
	var walker: EnemyWalker = main.get_node("Enemies/WalkerB")
	var fell := false
	for i in 300:
		await tree.physics_frame
		if walker.global_position.y > 200.0:
			fell = true
			break
	check("walker never walks off its platform", not fell, str(walker.global_position))
	check("walker stays within the platform", walker.global_position.x > 636.0 and walker.global_position.x < 772.0, str(walker.global_position.x))


func test_walker_turns_at_the_crawl_block() -> void:
	await reset_scene(true)
	# 矮通道（x 592..704，净空 30px）比巡逻兵（32px 高）矮，它得掉头而不是卡在那里推墙。
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(540, 304)
	walker.facing = 1
	walker._apply_facing()
	var turned := false
	for i in 200:
		await tree.physics_frame
		if walker.facing == -1:
			turned = true
			break
	check("walker turns around instead of getting stuck", turned, str(walker.global_position))


func test_bullets_kill_the_walker() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("walker takes two shots", walker.max_health == 2 * SHOT and walker.health == 2 * SHOT)

	walker.take_damage(SHOT)
	check("one shot does not kill a walker", is_instance_valid(walker) and walker.health == SHOT, str(walker.health))
	await frames(2)

	# GDScript 的 lambda 按值捕获局部变量，所以用数组这种引用类型来收信号。
	var death_signals := []
	walker.died.connect(func(): death_signals.append(true))

	player.global_position = walker.global_position + Vector2(-80, 0)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(2)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2(player.facing, 0))
	for i in 30:
		await tree.physics_frame
		if not is_instance_valid(walker):
			break
	check("the next bullet kills it", death_signals.size() == 1 and not is_instance_valid(walker), str(death_signals))


func test_collision_masks_keep_sides_apart() -> void:
	await reset_scene(true)
	var player_bullet: Bullet = load("res://scenes/bullet.tscn").instantiate()
	var enemy_bullet: Bullet = load("res://scenes/enemy_bullet.tscn").instantiate()
	check("player bullets ignore the player", (player_bullet.collision_mask & 2) == 0)
	check("player bullets hit enemies", (player_bullet.collision_mask & 8) != 0)
	check("enemy bullets ignore enemies", (enemy_bullet.collision_mask & 8) == 0)
	check("enemy bullets hit the player", (enemy_bullet.collision_mask & 2) != 0)
	player_bullet.free()
	enemy_bullet.free()


func test_turret_only_fires_in_range() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")

	player.global_position = Vector2(64, 304) # 远离炮台
	var seen_while_far := 0
	for i in 90:
		await tree.physics_frame
		seen_while_far += bullets(16).size()
	check("turret holds fire while the player is far away", seen_while_far == 0, str(seen_while_far))

	player.global_position = turret.global_position + Vector2(-200, 0)
	player.velocity = Vector2.ZERO
	var directions := {}
	for i in 120:
		await tree.physics_frame
		for bullet in bullets(16):
			directions[bullet.direction] = true
	check("turret fires once the player is in range", directions.size() > 0, str(directions.keys()))
	check("turret bullets fly toward the player", directions.keys() == [Vector2.LEFT], str(directions.keys()))
	check("turret bullets hurt the player", player.health < player.max_health, str(player.health))
	check("turret faces the player", turret.facing == -1, str(turret.facing))


func test_turret_flips_to_face_the_player() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	player.global_position = turret.global_position + Vector2(90, 0)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("turret turns to the other side", turret.facing == 1, str(turret.facing))


func test_walker_shoots_at_the_player() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	await frames(20)

	# 站到巡逻兵正前方、同高度，射程之内。
	walker.global_position = Vector2(400, 304)
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(280, 304)
	player.velocity = Vector2.ZERO

	var directions := {}
	for i in 160:
		await tree.physics_frame
		for bullet in bullets(16):
			directions[bullet.direction] = true
	check("walker fires at the player", directions.size() > 0, str(directions.keys()))
	check("walker bullets fly toward the player", directions.keys() == [Vector2.LEFT], str(directions.keys()))
	check("walker bullets hurt the player", player.health < player.max_health, str(player.health))


func test_walker_does_not_shoot_backwards() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	await frames(20)

	# 玩家在身后：巡逻兵不该回头瞄准，转向只由巡逻决定。
	walker.global_position = Vector2(400, 304)
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(520, 304)
	player.velocity = Vector2.ZERO

	var shots := 0
	for i in 100:
		await tree.physics_frame
		# 让它一直朝左走，避免中途掉头把玩家转到正面来。
		walker.facing = -1
		shots += bullets(16).size()
	check("walker holds fire when the player is behind it", shots == 0, str(shots))
	check("walker keeps facing away", walker.facing == -1 and player.health == player.max_health, str(player.health))


func test_walker_and_turret_level_shots_hit_standing_and_miss_prone() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "Turret1"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	await frames(30)

	# 两种敌人站在同一块地上：世界坐标只要求亚像素级一致——巡逻兵在移动，CharacterBody2D 的碰撞安全边距（默认 0.08）
	# 会让它悬在地面上方约 0.07px，而站着不动的炮台贴得严丝合缝。
	var body_gap := absf(walker.global_position.y - turret.global_position.y)
	check("both rest on the ground within a sub-pixel", body_gap < 0.5, "%.3f px" % body_gap)

	# 两者的枪口高度不必相同（巡逻兵的枪举在胸口，炮台的炮管按素材低 4px），
	# 但站着平射的子弹都必须落在同一个区间里：打得中站着的玩家，从趴着的玩家头顶飞过。
	# 光看 Marker 不够，要看真打出来的子弹。
	walker.facing = -1
	turret.facing = -1
	walker.try_shoot(1998.0, player)
	turret.try_shoot(1998.0, player)
	await frames(1)
	var shots := bullets(16)
	check("both actually fired", shots.size() == 2, str(shots.size()))
	var ground := turret.global_position.y + 16.0
	for shot: Node2D in shots:
		var half := ((shot.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size.y / 2.0
		var bottom := ground - (shot.global_position.y + half)
		var top := ground - (shot.global_position.y - half)
		check("a level shot passes over a prone player (bottom %.1f px above ground)" % bottom, bottom > Player.CROUCH_HEIGHT)
		check("a level shot still hits a standing player (top %.1f px above ground)" % top, top < Player.STAND_HEIGHT)


func test_enemy_bullets_do_not_hurt_other_enemies() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "WalkerB"])
	var shooter: EnemyWalker = main.get_node("Enemies/WalkerA")
	var victim: EnemyWalker = main.get_node("Enemies/WalkerB")
	await frames(20)

	# 把另一只巡逻兵直接摆在枪口前面，玩家挪到远处不干扰。
	player.global_position = Vector2(1200, 304)
	shooter.global_position = Vector2(480, 304)
	shooter.facing = -1
	shooter._apply_facing()
	victim.global_position = Vector2(400, 304)
	victim.facing = -1
	victim._apply_facing()
	victim.move_speed = 0.0
	shooter.move_speed = 0.0
	await frames(2)

	var victim_health := victim.health
	var deaths := []
	victim.died.connect(func(): deaths.append(true))
	shooter.try_shoot(1998.0, player)
	await frames(2)
	check("a bullet is in the air", bullets(16).size() == 1, str(bullets(16).size()))

	# 子弹飞过同伴身上所需的帧数：80px / (300px/s / 60) = 16 帧，留足余量。
	await frames(40)
	check("the other enemy takes no damage", victim.health == victim_health and deaths.is_empty(), str(victim.health))
	check("it is still alive", is_instance_valid(victim) and not victim.is_queued_for_deletion())


## 把一个敌人摆好位置：朝左站在 pos，巡逻兵不再走动。
func _place_enemy(enemy: Enemy, pos: Vector2) -> void:
	enemy.global_position = pos
	enemy.facing = -1
	enemy._visual.scale.x = -1
	if enemy is EnemyWalker:
		(enemy as EnemyWalker)._apply_facing()


## 把 C 摆在 x=1000 朝左站定（不巡逻），玩家在它正前方 140px。
func _setup_c_facing_player() -> EnemyWalker:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(c, Vector2(1000, 304))
	c.move_speed = 0.0
	player.global_position = Vector2(860, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	return c


func test_c_goes_prone_when_the_player_does() -> void:
	var c := await _setup_c_facing_player()
	check("C stands while the player stands", not c.is_prone)

	Input.action_press("crouch")
	await frames(15) # 0.25 秒，还在 0.4 秒的反应时间内
	check("C waits a moment before going prone", not c.is_prone)
	await frames(15)
	check("C goes prone after the reaction time", c.is_prone)
	var shape_height := (c._shape.shape as RectangleShape2D).size.y
	check("prone C is as low as a prone player", shape_height == Enemy.PRONE_HEIGHT, str(shape_height))
	check("prone C keeps its feet on the ground", c.is_on_floor(), str(c.global_position))
	# 出膛点按碰撞体中心算，所以趴下压低碰撞体时它自己就跟着贴地了（不再依赖占位方块被压扁）
	var prone_muzzle := c.level_muzzle_position().y
	check("prone muzzle drops to skim the ground", prone_muzzle > 312.0 and prone_muzzle < 318.0, "y=%.1f" % prone_muzzle)

	Input.action_release("crouch")
	await frames(2)
	check("C stands up as soon as the player does", not c.is_prone and (c._shape.shape as RectangleShape2D).size.y == 32.0)


func test_turret_never_lies_down() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	await frames(10)
	_place_enemy(turret, Vector2(1000, 304))
	player.global_position = Vector2(860, 304)
	player.velocity = Vector2.ZERO
	check("turrets cannot go prone", not turret.can_go_prone)
	var shots := [0]
	turret.shot_fired.connect(func(): shots[0] += 1)
	Input.action_press("crouch")
	var ever_prone := false
	for i in 150:
		await tree.physics_frame
		ever_prone = ever_prone or turret.is_prone
	check("a turret stays upright when the player lies down", not ever_prone)
	# 于是在同一高度趴下能完全躲开炮台：它站着水平开的枪从趴着的玩家头顶飞过。
	check("the turret keeps firing", shots[0] >= 2, str(shots[0]))
	check("and every shot flies over the prone player", player.health == player.max_health, str(player.health))


func test_prone_enemy_hits_a_prone_player() -> void:
	var c := await _setup_c_facing_player()
	Input.action_press("crouch")
	# 第一发在 C 趴下之前打出，从头顶飞过；之后 C 趴下，下一发贴地打过来。
	for i in 180:
		await tree.physics_frame
		if player.health < player.max_health:
			break
	check("lying down no longer dodges a prone enemy", player.health < player.max_health, str(player.health))
	check("the hit came while both were prone", player.is_crouching and c.is_prone)


func test_type_c_stops_and_lies_down_to_shoot() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(walker, Vector2(500, 304))
	player.global_position = Vector2(360, 304) # 在巡逻兵正前方（左边）
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(40)
	check("walker lies down when the player ahead does", walker.is_prone)
	var x_prone := walker.global_position.x
	await frames(30)
	check("walker stays put while prone", absf(walker.global_position.x - x_prone) < 0.5, "%.2f -> %.2f" % [x_prone, walker.global_position.x])

	Input.action_release("crouch")
	await frames(30)
	check("walker gets up when the player does", not walker.is_prone)
	check("walker resumes its patrol", absf(walker.global_position.x - x_prone) > 10.0, "%.2f -> %.2f" % [x_prone, walker.global_position.x])


func test_type_c_ignores_a_prone_player_behind_it() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(walker, Vector2(400, 304))
	player.global_position = Vector2(500, 304) # 在背后（右边）
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	var ever_prone := false
	for i in 40:
		await tree.physics_frame
		ever_prone = ever_prone or walker.is_prone
		walker.facing = -1 # 别让它中途掉头把玩家转到正面
	check("walker does not lie down for a player behind it", not ever_prone)


func test_standing_shots_fly_over_a_prone_enemy() -> void:
	var c := await _setup_c_facing_player()
	# 玩家站着时敌人不会主动趴下，这里直接让它趴下并冻结 AI，只验证高度关系。
	c.set_prone(true)
	c.set_physics_process(false)
	player.global_position = Vector2(880, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	await frames(40)
	check("a standing shot flies over a prone enemy", c.health == c.max_health, str(c.health))

	# 对照组：同一枪在敌人站起来后就打得中，证明刚才是被高度躲掉的，不是根本没打出去。
	# （玩家趴下不能开枪，所以对照组换成让敌人站起来。）
	c.set_prone(false)
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	await frames(40)
	check("the same shot hits it once it stands up", not is_instance_valid(c) or c.health < c.max_health, str(c.health) if is_instance_valid(c) else "dead")


func test_player_invincibility_frames() -> void:
	# 这条只关心玩家和 HUD，清掉敌人免得中途被冷不丁打一枪。
	await reset_scene()
	await frames(30)
	var health_events := []
	player.health_changed.connect(func(health, _max_health): health_events.append(health))

	player.take_damage(HIT, player.global_position + Vector2(40, 0))
	check("player loses one hit", player.health == 2 * HIT, str(player.health))
	check("health_changed fires", health_events == [2 * HIT], str(health_events))
	check("knockback pushes away from the source", player.velocity.x < 0.0 and player.velocity.y < 0.0, str(player.velocity))
	var bar := main.get_node("HUD/HealthBar") as ColorRect
	check("hud bar drops by a third", absf((bar.get_node("Fill") as ColorRect).size.x - bar.size.x * 2.0 / 3.0) <= 1.0,
		str((bar.get_node("Fill") as ColorRect).size.x))

	player.take_damage(HIT, player.global_position)
	check("further damage is blocked while invincible", player.health == 2 * HIT, str(player.health))

	await frames(70) # 无敌 1 秒 = 60 帧
	check("blinking stops afterwards", is_equal_approx(player._visual.modulate.a, 1.0), str(player._visual.modulate.a))
	player.take_damage(HIT, player.global_position)
	check("damage lands again once invincibility ends", player.health == HIT, str(player.health))


func test_touching_an_enemy_hurts() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	player.global_position = walker.global_position
	player.velocity = Vector2.ZERO
	await frames(4)
	check("standing on an enemy costs one hit", player.health == 2 * HIT, str(player.health))


func test_player_death() -> void:
	await reset_scene()
	await frames(30)
	var death_signals := []
	player.died.connect(func(): death_signals.append(true))

	for i in 3:
		player._invincible_timer = 0.0
		player.take_damage(HIT, player.global_position + Vector2(40, 0))
		await frames(2)
	check("player dies at zero health", death_signals.size() == 1 and player.health == 0, str(player.health))
	# 「GAME OVER」和「再来一次 / 回主菜单」那一页归 `DeathScreen` 管，测试在 test_menus.gd

	var x_before := player.global_position.x
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check("a dead player ignores movement input", absf(player.global_position.x - x_before) < 24.0, str(player.global_position.x - x_before))

	Input.action_press("shoot")
	await frames(20)
	Input.action_release("shoot")
	check("a dead player cannot shoot", bullets(4).size() == 0, str(bullets(4).size()))


# ---------------------------------------------------------------- 视野对等：玩家看得见的敌人，也得看得见玩家

## 玩家贴着关卡左边（摄像机停在左边界上，画面 = x 0..640），敌人摆在 x 处面朝左，冷却清零。
func _face_off(enemy_name: String, x: float) -> Enemy:
	await reset_scene(true)
	keep_only_enemies([enemy_name])
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	player.global_position = Vector2(100, 304)
	player.velocity = Vector2.ZERO
	player.health = 999
	var y := 88.0 if enemy is EnemyFlyer else 304.0
	if enemy is EnemyFlyer:
		(enemy as EnemyFlyer).set_anchor(Vector2(x, y))
		(enemy as EnemyFlyer).is_following = false
		(enemy as EnemyFlyer).move_speed = 0.0
	else:
		enemy.global_position = Vector2(x, y)
		enemy.velocity = Vector2.ZERO
	enemy.facing = -1
	enemy._apply_visual_facing()
	if enemy is EnemyWalker:
		(enemy as EnemyWalker).move_speed = 0.0
	enemy._fire_timer = 0.0
	enemy._burst_left = 0
	if enemy is EnemyGrenadier:
		(enemy as EnemyGrenadier)._throw_timer = 0.0
	if enemy is EnemyChaser:
		(enemy as EnemyChaser)._memory_left = 0.0
		(enemy as EnemyChaser).is_chasing = false
	for grenade in tree.get_nodes_in_group(Grenade.GROUP):
		grenade.free()
	for shot in bullets(16):
		shot.free()
	snap_camera()
	return enemy


## 这个敌人在 frame_count 帧里有没有对玩家起反应（开火、扔雷、冲锋、跟随）。
func _reacts(enemy: Enemy, frame_count := 90) -> bool:
	var fired := [false]
	enemy.shot_fired.connect(func() -> void: fired[0] = true)
	for i in frame_count:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not is_instance_valid(enemy):
			return false
		if fired[0] or not tree.get_nodes_in_group(Grenade.GROUP).is_empty():
			return true
		if enemy is EnemyChaser and (enemy as EnemyChaser).is_chasing:
			return true
		if enemy is EnemyFlyer and (enemy as EnemyFlyer).is_following:
			return true
	return false


func test_every_enemy_on_screen_reacts_to_the_player() -> void:
	# 480px：比 A/B（220）、C 和炮台（400）、D（240）、F（300）的发现距离都远，但还在屏幕里——
	# 以前玩家能在屏幕里先把它们打死，它们没反应
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC", "Turret1", "ChaserD", "FlyerE", "WalkerF"]:
		var enemy := await _face_off(enemy_name, 580.0)
		check("setup: %s is on screen, beyond its detect range" % enemy_name,
			enemy.is_partly_on_screen() and 480.0 > enemy.detect_range, str(enemy.detect_range))
		check("%s reacts to a player it is on screen with" % enemy_name, await _reacts(enemy))


func test_enemies_off_screen_and_out_of_range_stay_unaware() -> void:
	# 对照：在屏幕外、又在发现距离外，照旧发现不了（不然它们隔着整个关卡就开始打）
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC", "Turret1", "ChaserD", "FlyerE", "WalkerF"]:
		var enemy := await _face_off(enemy_name, 1000.0)
		check("setup: %s is off screen and out of range" % enemy_name, not enemy.is_partly_on_screen() and 900.0 > enemy.detect_range)
		check("%s does not react" % enemy_name, not await _reacts(enemy, 60))
