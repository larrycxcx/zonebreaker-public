extends GameTest
## 下蹲：碰撞体压低、脚底不动、头顶阻挡、矮通道通行。

## 关卡里的矮通道：x 296..352，天花板底边 y=148，地面 y=160，净空 12px。
const TUNNEL_X := 324.0
## 一段没有平台也没有天花板的空地，用来测「头顶没东西」的情况。
const OPEN_X := 200.0


func shape_height() -> float:
	return (player._shape.shape as RectangleShape2D).size.y


## 碰撞体底边的世界坐标。下蹲前后这个值必须一模一样，否则玩家会陷进地里或者被弹起来。
func feet_y() -> float:
	return player.global_position.y + player._shape.position.y + shape_height() / 2.0


func test_crouch_and_stand_up() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(20)
	check("starts standing", not player.is_crouching and shape_height() == 16.0, str(shape_height()))
	var standing_feet := feet_y()

	Input.action_press("crouch")
	await frames(3)
	check("crouches on the ground", player.is_crouching and shape_height() == Player.CROUCH_HEIGHT, str(shape_height()))
	check("feet stay exactly put", absf(feet_y() - standing_feet) < 0.5, "%.2f -> %.2f" % [standing_feet, feet_y()])
	check("hurtbox shrinks as well", (player._hurtbox_shape.shape as RectangleShape2D).size.y == Player.HURTBOX_STAND_HEIGHT - (Player.STAND_HEIGHT - Player.CROUCH_HEIGHT), str((player._hurtbox_shape.shape as RectangleShape2D).size.y))
	check("visual is squashed and lowered", is_equal_approx(player._visual.scale.y, Player.CROUCH_HEIGHT / Player.STAND_HEIGHT) and is_equal_approx(player._visual.position.y, (Player.STAND_HEIGHT - Player.CROUCH_HEIGHT) / 2.0), "%s %s" % [player._visual.scale, player._visual.position])
	check("still standing on the floor", player.is_on_floor())

	Input.action_release("crouch")
	await frames(3)
	check("stands up again in the open", not player.is_crouching and shape_height() == 16.0, str(shape_height()))
	check("feet unchanged after standing up", absf(feet_y() - standing_feet) < 0.5, "%.2f" % feet_y())


func test_crouch_walk_is_slower() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)

	Input.action_press("move_right")
	await frames(40)
	var standing_speed := absf(player.velocity.x)
	Input.action_press("crouch")
	await frames(40)
	var crouching_speed := absf(player.velocity.x)
	check("crouch walk is slower", crouching_speed < standing_speed * 0.8 and crouching_speed > 1.0, "%.1f vs %.1f" % [crouching_speed, standing_speed])
	check("crouch speed is 60% of walking", absf(crouching_speed - standing_speed * 0.6) < 1.0, "%.1f" % crouching_speed)


func test_cannot_crouch_in_mid_air() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 100)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(3)
	check("holding crouch in the air does nothing", not player.is_crouching and not player.is_on_floor())
	await frames(60)
	check("crouches as soon as it lands", player.is_crouching and player.is_on_floor())


func test_low_ceiling_keeps_the_player_down() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)

	Input.action_press("crouch")
	await frames(3)
	Input.action_press("move_right")
	var entered := false
	for i in 400:
		await tree.physics_frame
		if player.global_position.x > TUNNEL_X:
			entered = true
			break
	Input.action_release("move_right")
	check("crawls into the tunnel", entered, str(player.global_position))

	Input.action_release("crouch")
	await frames(20)
	check("cannot stand up under the low ceiling", player.is_crouching and shape_height() == Player.CROUCH_HEIGHT, str(shape_height()))
	check("head check reports blocked", player._head_blocked())

	var y_before := player.global_position.y
	Input.action_press("jump")
	await frames(6)
	Input.action_release("jump")
	check("cannot jump under the low ceiling", absf(player.global_position.y - y_before) < 1.0, "%.2f" % (player.global_position.y - y_before))

	Input.action_press("move_right")
	for i in 400:
		await tree.physics_frame
		if not player.is_crouching:
			break
	Input.action_release("move_right")
	check("stands up automatically after leaving the tunnel", not player.is_crouching and player.global_position.x > 352.0, str(player.global_position))


func test_standing_player_cannot_pass_the_crawl_block() -> void:
	await reset_scene()
	player.global_position = Vector2(280, 152)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("move_right")
	await frames(240)
	Input.action_release("move_right")
	check("standing player is stopped by the crawl block", player.global_position.x < 300.0, str(player.global_position))


func test_one_way_platform_does_not_block_standing() -> void:
	await reset_scene()
	# Platform1：x 80..128，y 128..136。站在它正下方，头顶虽然有平台但可以穿过去。
	player.global_position = Vector2(104, 152)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("crouch")
	await frames(5)
	check("crouches under a one-way platform", player.is_crouching)
	Input.action_release("crouch")
	await frames(5)
	check("a one-way platform never blocks standing up", not player.is_crouching, str(player._head_blocked()))


func test_jumping_from_a_crouch() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("crouch")
	await frames(5)
	Input.action_press("jump")
	await frames(3)
	check("jumping from a crouch stands up and jumps", not player.is_crouching and player.velocity.y < 0.0, str(player.velocity))


func test_cannot_shoot_while_lying_down() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("crouch")
	await frames(5)

	player._fire_timer = 0.0
	Input.action_press("shoot")
	await frames(30)
	Input.action_release("shoot")
	check("J does nothing while lying down", bullets(4).size() == 0, str(bullets(4).size()))

	Input.action_press("aim_up")
	Input.action_press("shoot")
	await frames(30)
	check("W + J does nothing while lying down", bullets(4).size() == 0, str(bullets(4).size()))
	check("the gun is not raised while lying down", player._gun.visible and not player._gun_up.visible)
	Input.action_release("aim_up")
	Input.action_release("shoot")

	# 趴着仍然可以移动。
	var x_before := player.global_position.x
	Input.action_press("move_right")
	await frames(30)
	check("can still crawl while lying down", player.is_crouching and player.global_position.x > x_before + 15.0, "%.1f -> %.1f" % [x_before, player.global_position.x])
	Input.action_release("move_right")

	# 站起来立刻就能开火（证明上面没开火是因为趴着，而不是别的原因）。
	Input.action_release("crouch")
	await frames(3)
	Input.action_press("shoot")
	await frames(2)
	check("shooting works again after standing up", bullets(4).size() == 1, str(bullets(4).size()))


## 敌人子弹离地面只有 6~8px，趴下的玩家必须矮到让它们从头顶飞过去。
## 这两条用例同时确认「子弹确实飞过了玩家所在位置」，否则没开火也会误判为躲开了。
func _assert_crouch_dodges(enemy_name: String, enemy_pos: Vector2, facing: int) -> void:
	await reset_scene(true)
	keep_only_enemies([enemy_name])
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	await frames(10)
	enemy.global_position = enemy_pos
	enemy.facing = facing
	enemy._visual.scale.x = facing
	if enemy is EnemyWalker:
		(enemy as EnemyWalker).move_speed = 0.0
		(enemy as EnemyWalker)._apply_facing()
	player.global_position = enemy_pos + Vector2(70 * facing, -1)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(10)
	check(enemy_name + ": player is lying down", player.is_crouching and player.is_on_floor())

	var passed_player := false
	for i in 150:
		await tree.physics_frame
		for bullet in bullets(16):
			if signf(player.global_position.x - bullet.global_position.x) == float(facing):
				continue
			passed_player = true
	check(enemy_name + ": bullets fly past the player", passed_player)
	check(enemy_name + ": lying down dodges every bullet", player.health == 3, str(player.health))

	# 对照组：站起来就会中弹，证明躲开靠的是高度而不是别的原因。
	Input.action_release("crouch")
	await frames(3)
	check(enemy_name + ": player stands up again", not player.is_crouching)
	for i in 150:
		await tree.physics_frame
		if player.health < 3:
			break
	check(enemy_name + ": standing up gets the player hit", player.health < 3, str(player.health))


func test_lying_down_dodges_turret_fire() -> void:
	await _assert_crouch_dodges("Turret1", Vector2(580, 153), -1)


func test_lying_down_dodges_walker_fire() -> void:
	await _assert_crouch_dodges("Walker1", Vector2(250, 153), -1)
