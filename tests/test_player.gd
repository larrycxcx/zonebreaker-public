extends GameTest
## 玩家基础操作：移动、跳跃、射击、单向平台。


func test_input_actions_exist() -> void:
	await reset_scene()
	for action in ACTIONS:
		check("action defined: " + action, InputMap.has_action(action))


func test_lands_on_ground() -> void:
	await reset_scene()
	await frames(30)
	check("lands on ground", player.is_on_floor(), str(player.global_position))
	check("feet rest on ground top", is_equal_approx(player.global_position.y, 152.0), str(player.global_position.y))


func test_moves_and_turns() -> void:
	await reset_scene()
	await frames(20)
	var start_x := player.global_position.x

	Input.action_press("move_right")
	await frames(30)
	check("moves right", player.global_position.x > start_x + 20.0, str(player.global_position.x))
	check("faces right", player.facing == 1 and player._visual.scale.x == 1.0)

	Input.action_release("move_right")
	await frames(30)
	check("stops when key released", is_zero_approx(player.velocity.x))

	start_x = player.global_position.x
	Input.action_press("move_left")
	await frames(20)
	check("moves left", player.global_position.x < start_x - 10.0, str(player.global_position.x))
	check("faces left", player.facing == -1 and player._visual.scale.x == -1.0)


func test_jump_height_and_short_hop() -> void:
	await reset_scene()
	await frames(20)
	var ground_y := player.global_position.y

	# 一直按住：完整跳跃高度。
	var top := ground_y
	Input.action_press("jump")
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
	Input.action_release("jump")
	var full_height := ground_y - top
	check("full jump height ~46px", full_height > 38.0 and full_height < 50.0, "%.1f" % full_height)
	await frames(60)
	check("lands again after jumping", player.is_on_floor())

	# 早松手：低跳。
	top = ground_y
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
	var short_height := ground_y - top
	check("short hop is clearly lower", short_height > 2.0 and short_height < full_height - 8.0, "%.1f vs %.1f" % [short_height, full_height])


func test_no_double_jump() -> void:
	await reset_scene()
	await frames(20)
	Input.action_press("jump")
	await frames(20)
	Input.action_release("jump")
	await frames(1)
	# 在空中再按一次，不应该获得新的向上速度。
	Input.action_press("jump")
	await frames(1)
	check("cannot jump again in mid-air", player.velocity.y > -100.0, str(player.velocity.y))


func test_one_way_platform() -> void:
	await reset_scene()
	# Platform1：x 80..128，顶面 y=128。站到它正下方往上跳。
	player.global_position = Vector2(100, 152)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	await frames(30)
	check("jumps up through a one-way platform and lands on it", player.is_on_floor() and is_equal_approx(player.global_position.y, 120.0), str(player.global_position))


func test_shooting() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 152)
	player.velocity = Vector2.ZERO
	await frames(20)

	player._fire_timer = 0.0
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("shoot")
	var shots := bullets(4)
	check("one shot spawns one bullet", shots.size() == 1, str(shots.size()))
	if shots.size() == 1:
		var bullet: Bullet = shots[0]
		check("bullet starts at the muzzle", bullet.global_position.x > player.global_position.x + 8.0, str(bullet.global_position))
		check("bullet flies the way the player faces", bullet.direction == Vector2.RIGHT)
		var bullet_x: float = bullet.global_position.x
		await frames(10)
		check("bullet travels", is_instance_valid(bullet) and bullet.global_position.x > bullet_x + 30.0)


func test_auto_fire_is_rate_limited() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 152)
	player.velocity = Vector2.ZERO
	await frames(20)

	player._fire_timer = 0.0
	Input.action_press("shoot")
	await frames(30) # 0.5 秒，射速 0.15 秒一发 → 3~4 发
	Input.action_release("shoot")
	var shots := bullets(4)
	check("holding fire is rate limited", shots.size() >= 3 and shots.size() <= 5, str(shots.size()))


func test_bullets_despawn() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 152)
	player.velocity = Vector2.ZERO
	await frames(20)
	player._fire_timer = 0.0
	player._shoot()
	await frames(90) # 存活时间 1.2 秒 = 72 帧
	check("bullet disappears after its lifetime", bullets(4).size() == 0, str(bullets(4).size()))

	# 贴着左墙开火：应该马上撞墙消失，而不是等超时。
	player.global_position = Vector2(30, 152)
	player.velocity = Vector2.ZERO
	player.facing = -1
	player._visual.scale.x = -1
	await frames(5)
	player._fire_timer = 0.0
	player._shoot()
	await frames(20) # 0.33 秒，按速度本该飞 86px，但墙只有 20px 远
	check("bullet is destroyed by a wall well before its lifetime", bullets(4).size() == 0, str(bullets(4).size()))
