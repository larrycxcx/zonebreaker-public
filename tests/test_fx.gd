extends GameTest
## 特效层（`Fx`）：听事件总线，在开枪、命中、撞墙的位置生成短命的占位特效。
## 特效只管显示——不能有碰撞、不能影响任何判定，而且要自己消失掉。

func fx() -> Fx:
	return main.get_node("Fx")


func effects() -> Array:
	return fx().get_children()


## 等出现一个特效，返回它；超时返回 null。
func wait_for_effect(limit := 120) -> Node2D:
	for i in limit:
		await frames(1)
		if not effects().is_empty():
			return effects()[0]
	return null


func test_level_has_an_fx_layer() -> void:
	await reset_scene()
	check("the level has an Fx node", fx() != null)
	check("muzzle flash assigned", fx().muzzle_flash_scene != null)
	check("hit spark assigned", fx().hit_spark_scene != null)
	check("impact spark assigned", fx().impact_spark_scene != null)
	check("starts empty", effects().is_empty())
	# 特效是纯显示的：整棵树里不许有碰撞体，否则会挡子弹、挡人
	# 循环变量要标类型：不标的话是 Variant，下面 := 推不出类型，整个脚本都编译不过（CLAUDE.md 里记过这个坑）
	for scene: PackedScene in [fx().muzzle_flash_scene, fx().hit_spark_scene, fx().impact_spark_scene]:
		var effect := scene.instantiate()
		check("%s is purely visual (no collision anywhere)" % scene.resource_path.get_file(), not has_collision(effect))
		effect.free()


## 这棵树里有没有碰撞体。
func has_collision(node: Node) -> bool:
	if node is CollisionObject2D:
		return true
	return node.get_children().any(func(child): return has_collision(child))


func test_every_enemy_shoot_event_makes_a_flash() -> void:
	# 加了新敌人却忘了把它的 shoot_event 登记到 Fx.SHOOT_EVENTS 里，它开枪就不会有枪口闪光
	await reset_scene(true)
	for enemy in main.get_node("Enemies").get_children():
		if enemy.bullet_scene == null:
			continue # 不开枪的敌人（D、F）
		check("%s's shoot event (%s) is listed in Fx" % [enemy.name, enemy.shoot_event],
			Fx.SHOOT_EVENTS.has(enemy.shoot_event), str(Fx.SHOOT_EVENTS))


func test_muzzle_flash_when_the_player_fires() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("shoot")
	var flash := await wait_for_effect()
	Input.action_release("shoot")
	check("firing makes a muzzle flash", flash != null)
	if flash == null:
		return
	check("at the muzzle", flash.global_position.distance_to(player.last_muzzle_position) < 1.0,
		"%s vs %s" % [flash.global_position, player.last_muzzle_position])
	check("turned along the shot", is_equal_approx(flash.rotation, player.last_shot_direction.angle()),
		"%.2f vs %.2f" % [flash.rotation, player.last_shot_direction.angle()])


func test_flash_follows_the_aim() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("aim_up")
	await frames(2)
	Input.action_press("shoot")
	var flash := await wait_for_effect()
	release_all_input()
	check("aiming up: flash points up", flash != null and is_equal_approx(flash.rotation, Vector2.UP.angle()),
		"%.2f" % (flash.rotation if flash != null else 0.0))


func test_impact_spark_where_a_bullet_hits_a_wall() -> void:
	await reset_scene(false, true)
	var wall := add_wall(600, 60)
	player.global_position = Vector2(520, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	player._shoot(Vector2.RIGHT)
	var hit: Node2D = null
	for i in 40:
		await frames(1)
		# 枪口闪光在玩家身上，命中火花在墙那边：按 x 挑出后者
		for effect in effects():
			if effect.global_position.x > wall.position.x - 12.0:
				hit = effect
				break
		if hit != null:
			break
	check("a bullet hitting a wall makes a spark", hit != null)
	if hit != null:
		check("the spark is at the wall", absf(hit.global_position.x - wall.position.x) < 12.0,
			"%.1f vs wall at %.1f" % [hit.global_position.x, wall.position.x])


func test_hit_spark_on_the_enemy_that_was_shot() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.max_health = 10
	c.health = 10
	c.global_position = Vector2(600, 306)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	for effect in effects():
		effect.free() # 清掉准备阶段的闪光
	player._shoot(Vector2.RIGHT)
	var spark: Node2D = null
	for i in 60:
		await frames(1)
		for effect in effects():
			if effect.global_position.distance_to(c.global_position) < 20.0:
				spark = effect
				break
		if spark != null:
			break
	check("hitting an enemy makes a spark on it", spark != null, "enemy at %s" % c.global_position)
	check("the enemy really took the hit", c.health < 10, str(c.health))


func test_effects_clean_themselves_up() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("shoot")
	# 闪光只活 0.06 秒（约 4 帧），射速 0.15 秒一发，所以要边打边看，不能打完再数
	var seen := false
	for i in 30:
		await frames(1)
		seen = seen or not effects().is_empty()
	Input.action_release("shoot")
	check("setup: effects were spawned", seen)
	for i in 90:
		await frames(1)
		if effects().is_empty():
			break
	check("they all disappear on their own", effects().is_empty(), "%d left" % effects().size())


func test_effects_do_not_touch_gameplay() -> void:
	# 特效层只是听众：把它摘掉，玩法（子弹、伤害）一模一样
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.global_position = Vector2(600, 306)
	fx().queue_free()
	await frames(2)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	var before := c.health
	player._shoot(Vector2.RIGHT)
	for i in 40:
		await frames(1)
		if not is_instance_valid(c) or c.health < before:
			break
	check("without the Fx layer the shot still hits", not is_instance_valid(c) or c.health < before,
		str(c.health) if is_instance_valid(c) else "dead")
