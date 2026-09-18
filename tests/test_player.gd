extends GameTest
## 玩家基础操作：移动、跳跃、射击（水平和向上）、单向平台。

## 出生点附近头顶完全空旷的一段地面（第一个平台从 x=80 开始），用来测向上开枪。
const OPEN_SKY_X := 50.0


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
	player._shoot(Vector2(player.facing, 0))
	await frames(90) # 存活时间 1.2 秒 = 72 帧
	check("bullet disappears after its lifetime", bullets(4).size() == 0, str(bullets(4).size()))

	# 贴着左墙开火：应该马上撞墙消失，而不是等超时。
	player.global_position = Vector2(30, 152)
	player.velocity = Vector2.ZERO
	player.facing = -1
	player._visual.scale.x = -1
	await frames(5)
	player._fire_timer = 0.0
	player._shoot(Vector2(player.facing, 0))
	await frames(20) # 0.33 秒，按速度本该飞 86px，但墙只有 20px 远
	check("bullet is destroyed by a wall well before its lifetime", bullets(4).size() == 0, str(bullets(4).size()))


func test_w_aims_instead_of_jumping() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_SKY_X, 152)
	await frames(20)
	var y_before := player.global_position.y
	Input.action_press("aim_up")
	await frames(20)
	check("W does not make the player jump", player.is_on_floor() and absf(player.global_position.y - y_before) < 0.5, "%.2f" % (player.global_position.y - y_before))
	check("W alone does not fire", bullets(4).size() == 0, str(bullets(4).size()))
	check("gun is raised while holding W", player._gun_up.visible and not player._gun.visible)
	Input.action_release("aim_up")
	await frames(2)
	check("gun goes back down after releasing W", player._gun.visible and not player._gun_up.visible)

	var jump_keys := InputMap.action_get_events("jump").map(func(e): return (e as InputEventKey).physical_keycode)
	check("jump is bound to Space and Up only", jump_keys.size() == 2 and jump_keys.has(KEY_SPACE) and jump_keys.has(KEY_UP), str(jump_keys))
	var aim_keys := InputMap.action_get_events("aim_up").map(func(e): return (e as InputEventKey).physical_keycode)
	check("aim_up is bound to W", aim_keys == [KEY_W], str(aim_keys))


func test_shooting_straight_up() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_SKY_X, 152)
	player.velocity = Vector2.ZERO
	await frames(20)

	player._fire_timer = 0.0
	Input.action_press("aim_up")
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("shoot")
	var shots := bullets(4)
	check("W + J fires one bullet", shots.size() == 1, str(shots.size()))
	if shots.size() == 1:
		var bullet: Bullet = shots[0]
		var x0: float = bullet.global_position.x
		var y0: float = bullet.global_position.y
		check("bullet flies straight up", bullet.direction == Vector2.UP)
		check("bullet is turned upright", is_equal_approx(bullet.rotation, -PI / 2.0), "%.3f" % bullet.rotation)
		check("bullet starts above the head", y0 < player.global_position.y - 8.0 and absf(x0 - player.global_position.x) < 4.0, str(bullet.global_position))
		await frames(10)
		check("bullet keeps rising without drifting sideways", is_instance_valid(bullet) and bullet.global_position.y < y0 - 30.0 and is_equal_approx(bullet.global_position.x, x0))


func test_holding_aim_and_fire_auto_fires_upward() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_SKY_X, 152)
	player.velocity = Vector2.ZERO
	await frames(20)

	player._fire_timer = 0.0
	var directions := {}
	var spawned := {}
	Input.action_press("aim_up")
	Input.action_press("shoot")
	for i in 30:
		await tree.physics_frame
		for bullet in bullets(4):
			spawned[bullet.get_instance_id()] = true
			directions[bullet.direction] = true
	check("every shot goes up while aiming", directions.keys() == [Vector2.UP], str(directions.keys()))
	check("aiming up keeps the normal fire rate", spawned.size() >= 3 and spawned.size() <= 5, str(spawned.size()))


func test_can_move_while_aiming_up() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_SKY_X, 152)
	await frames(10)
	var x_before := player.global_position.x
	Input.action_press("aim_up")
	Input.action_press("move_right")
	await frames(20)
	check("moving while aiming up works", player.global_position.x > x_before + 15.0 and player._gun_up.visible, "%.1f -> %.1f" % [x_before, player.global_position.x])


func test_shooting_up_passes_one_way_platforms() -> void:
	# Turret2 站在 Platform2（x 160..208，y 100..108）上。从正下方往上打，
	# 子弹要穿过单向平台打中它；高度差太大，炮台不会还击。
	await reset_scene(true)
	keep_only_enemies(["Turret2"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret2")
	await frames(20)
	player.global_position = Vector2(turret.global_position.x, 152)
	player.velocity = Vector2.ZERO
	await frames(5)
	var deaths := []
	turret.died.connect(func(): deaths.append(true))
	player._fire_timer = 0.0
	Input.action_press("aim_up")
	Input.action_press("shoot")
	for i in 60:
		await tree.physics_frame
		if not deaths.is_empty():
			break
	check("bullets pass through the platform and kill the turret on it", deaths.size() == 1, "turret health %s" % (str(turret.health) if is_instance_valid(turret) else "dead"))
	check("the player was never shot back", player.health == 3, str(player.health))


func test_solid_ceiling_still_stops_upward_shots() -> void:
	await reset_scene()
	# 单向平台放行，实心方块照样要挡住。CrawlBlock（x 296..352，y 120..148）是实心的，
	# 直接在它正下方的缝里生成一颗向上的子弹。
	var bullet: Bullet = player.bullet_scene.instantiate()
	bullet.direction = Vector2.UP
	main.add_child(bullet)
	bullet.global_position = Vector2(324, 156)
	await frames(10)
	check("a solid block stops an upward bullet", not is_instance_valid(bullet), "still flying" if is_instance_valid(bullet) else "")
