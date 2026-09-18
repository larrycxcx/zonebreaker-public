extends GameTest
## 敌人行为、伤害判定、玩家血量与无敌帧。这组用例要保留敌人，所以都用 `reset_scene(true)`。


func test_level_setup() -> void:
	await reset_scene(true)
	check("5 enemies in the level", main.get_node("Enemies").get_child_count() == 5, str(main.get_node("Enemies").get_child_count()))
	check("player starts at full health", player.health == 3 and player.max_health == 3, str(player.health))
	check("hud shows one pip per health point", main.get_node("HUD/PipRow").get_child_count() == 3)


func test_enemies_stand_where_placed() -> void:
	await reset_scene(true)
	await frames(40)
	var walker1: EnemyWalker = main.get_node("Enemies/Walker1")
	var walker2: EnemyWalker = main.get_node("Enemies/Walker2")
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	check("ground walker stands on the ground", walker1.is_on_floor() and absf(walker1.global_position.y - 153.0) < 2.0, str(walker1.global_position))
	check("platform walker stands on its platform", walker2.is_on_floor() and absf(walker2.global_position.y - 89.0) < 2.0, str(walker2.global_position))
	check("turret stands on the ground", turret.is_on_floor(), str(turret.global_position))


func test_walker_patrols() -> void:
	await reset_scene(true)
	await frames(40)
	var walker: EnemyWalker = main.get_node("Enemies/Walker1")
	var start_x := walker.global_position.x
	await frames(60)
	check("walker moves along the ground", absf(walker.global_position.x - start_x) > 10.0, "%.1f -> %.1f" % [start_x, walker.global_position.x])


func test_walker_turns_at_ledges() -> void:
	await reset_scene(true)
	await frames(40)
	# Platform4：x 320..384。巡逻兵必须在边缘掉头，不能走下去。
	var walker: EnemyWalker = main.get_node("Enemies/Walker2")
	var fell := false
	for i in 300:
		await tree.physics_frame
		if walker.global_position.y > 100.0:
			fell = true
			break
	check("walker never walks off its platform", not fell, str(walker.global_position))
	check("walker stays within the platform", walker.global_position.x > 318.0 and walker.global_position.x < 386.0, str(walker.global_position.x))


func test_walker_turns_at_the_crawl_block() -> void:
	await reset_scene(true)
	# 矮通道（x 296..352，净空 12px）比巡逻兵矮，它得掉头而不是卡在那里推墙。
	var walker: EnemyWalker = main.get_node("Enemies/Walker1")
	walker.global_position = Vector2(270, 153)
	walker.direction = 1
	walker._apply_direction()
	var turned := false
	for i in 200:
		await tree.physics_frame
		if walker.direction == -1:
			turned = true
			break
	check("walker turns around instead of getting stuck", turned, str(walker.global_position))


func test_bullets_kill_the_walker() -> void:
	await reset_scene(true)
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/Walker1")
	check("walker has 2 health", walker.max_health == 2 and walker.health == 2)

	walker.take_damage(1)
	check("one hit does not kill a 2 health walker", is_instance_valid(walker) and walker.health == 1, str(walker.health))
	await frames(2)

	# GDScript 的 lambda 按值捕获局部变量，所以用数组这种引用类型来收信号。
	var death_signals := []
	walker.died.connect(func(): death_signals.append(true))

	player.global_position = walker.global_position + Vector2(-40, 0)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(2)
	player._fire_timer = 0.0
	player._shoot()
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
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")

	player.global_position = Vector2(32, 152) # 远离炮台
	var seen_while_far := 0
	for i in 90:
		await tree.physics_frame
		seen_while_far += bullets(16).size()
	check("turret holds fire while the player is far away", seen_while_far == 0, str(seen_while_far))

	player.global_position = turret.global_position + Vector2(-100, 0)
	player.velocity = Vector2.ZERO
	var directions := {}
	for i in 120:
		await tree.physics_frame
		for bullet in bullets(16):
			directions[bullet.direction] = true
	check("turret fires once the player is in range", directions.size() > 0, str(directions.keys()))
	check("turret bullets fly toward the player", directions.keys() == [Vector2.LEFT], str(directions.keys()))
	check("turret bullets hurt the player", player.health < 3, str(player.health))
	check("turret faces the player", turret.facing == -1, str(turret.facing))


func test_turret_flips_to_face_the_player() -> void:
	await reset_scene(true)
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	player.global_position = turret.global_position + Vector2(45, 0)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("turret turns to the other side", turret.facing == 1, str(turret.facing))


func test_player_invincibility_frames() -> void:
	await reset_scene(true)
	await frames(30)
	var health_events := []
	player.health_changed.connect(func(health, _max_health): health_events.append(health))

	player.take_damage(1, player.global_position + Vector2(20, 0))
	check("player loses one health", player.health == 2, str(player.health))
	check("health_changed fires", health_events == [2], str(health_events))
	check("knockback pushes away from the source", player.velocity.x < 0.0 and player.velocity.y < 0.0, str(player.velocity))
	check("hud dims the lost pip", main.get_node("HUD/PipRow").get_child(2).color == Color(0.25, 0.2, 0.25))

	player.take_damage(1, player.global_position)
	check("further damage is blocked while invincible", player.health == 2, str(player.health))

	await frames(70) # 无敌 1 秒 = 60 帧
	check("blinking stops afterwards", is_equal_approx(player._visual.modulate.a, 1.0), str(player._visual.modulate.a))
	player.take_damage(1, player.global_position)
	check("damage lands again once invincibility ends", player.health == 1, str(player.health))


func test_touching_an_enemy_hurts() -> void:
	await reset_scene(true)
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/Walker1")
	player.global_position = walker.global_position
	player.velocity = Vector2.ZERO
	await frames(4)
	check("standing on an enemy costs health", player.health == 2, str(player.health))


func test_player_death() -> void:
	await reset_scene(true)
	await frames(30)
	var death_signals := []
	player.died.connect(func(): death_signals.append(true))

	for i in 3:
		player._invincible_timer = 0.0
		player.take_damage(1, player.global_position + Vector2(20, 0))
		await frames(2)
	check("player dies at zero health", death_signals.size() == 1 and player.health == 0, str(player.health))
	check("game over message appears", main.get_node("HUD/Message").visible)

	var x_before := player.global_position.x
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check("a dead player ignores movement input", absf(player.global_position.x - x_before) < 12.0, str(player.global_position.x - x_before))

	Input.action_press("shoot")
	await frames(20)
	Input.action_release("shoot")
	check("a dead player cannot shoot", bullets(4).size() == 0, str(bullets(4).size()))
