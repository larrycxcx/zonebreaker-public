extends GameTest
## 跳下平台（魂斗罗式）：站在单向平台上按住「下」再按跳跃，就从平台上穿下去，而不是起跳。
## 实心地面上按同样的键照常起跳。

## Platform1：x 160..256，顶面 y=256。
const PLATFORM := "Level/Platform1"
const PLATFORM_TOP := 256.0


func platform() -> Platform:
	return main.get_node(PLATFORM)


## 站到 Platform1 上（脚底贴着顶面），等它真的踩稳。
func stand_on_platform() -> void:
	await reset_scene()
	player.global_position = Vector2(208, PLATFORM_TOP - 24.0)
	player.velocity = Vector2.ZERO
	for i in 60:
		await frames(1)
		if player.is_on_floor() and player.global_position.y > PLATFORM_TOP - 24.0:
			break
	check("setup: standing on the platform", player.is_on_floor() and absf(player.global_position.y - (PLATFORM_TOP - 16.0)) < 4.0,
		"y=%.1f" % player.global_position.y)


func feet() -> float:
	return player.global_position.y + 16.0


func test_down_and_jump_drops_through() -> void:
	await stand_on_platform()
	Input.action_press("aim_down")
	await tap("jump")
	var below := false
	for i in 60:
		await frames(1)
		if feet() > PLATFORM_TOP + 4.0:
			below = true
			break
	check("drops through the platform", below, "feet at %.1f, platform at %.1f" % [feet(), PLATFORM_TOP])
	check("it falls instead of jumping", player.velocity.y > 0.0, str(player.velocity.y))
	# 一路落到地面上
	for i in 90:
		await frames(1)
		if player.is_on_floor():
			break
	check("lands on the ground below", player.is_on_floor() and player.global_position.y > 280.0, str(player.global_position.y))
	Input.action_release("aim_down")


func test_jump_alone_still_jumps() -> void:
	await stand_on_platform()
	var start_y := player.global_position.y
	Input.action_press("jump") # 按住：一按就松是低跳，高度不够看
	var top := start_y
	for i in 40:
		await frames(1)
		top = minf(top, player.global_position.y)
	Input.action_release("jump")
	check("jumping without down goes up", top < start_y - 40.0, "%.1f -> %.1f" % [start_y, top])
	check("and stays above the platform", feet() <= PLATFORM_TOP + 4.0, "feet at %.1f" % feet())


func test_down_and_jump_on_solid_ground_jumps() -> void:
	# 实心地面上按「下 + 跳」照常起跳（地面不是单向平台，跳不下去）
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	var start_y := player.global_position.y
	Input.action_press("aim_down")
	Input.action_press("jump")
	var top := start_y
	for i in 40:
		await frames(1)
		top = minf(top, player.global_position.y)
	release_all_input()
	check("still jumps on solid ground", top < start_y - 40.0, "%.1f -> %.1f" % [start_y, top])
	check("and does not sink into the ground", player.global_position.y <= start_y + 1.0, str(player.global_position.y))


func test_cannot_drop_through_in_mid_air() -> void:
	# 空中按「下 + 跳」不会有任何「穿过」效果：该落下就落下，不会二段跳
	await stand_on_platform()
	await tap("jump")
	await frames(6)
	check("setup: airborne", not player.is_on_floor())
	var before := player.velocity.y
	Input.action_press("aim_down")
	await tap("jump")
	Input.action_release("aim_down")
	check("no mid-air jump", player.velocity.y >= before - 20.0, "%.1f -> %.1f" % [before, player.velocity.y])


func test_the_platform_is_solid_again_afterwards() -> void:
	# 穿下去之后碰撞要恢复：跳回来还能站上去（不能留下一块永远穿得过的平台）
	await stand_on_platform()
	Input.action_press("aim_down")
	await tap("jump")
	for i in 60:
		await frames(1)
		if player.is_on_floor() and feet() > PLATFORM_TOP + 4.0:
			break
	Input.action_release("aim_down")
	check("setup: dropped to the ground", feet() > PLATFORM_TOP + 4.0, "feet at %.1f" % feet())
	await frames(20) # 等忽略碰撞的那 0.25 秒走完
	check("the exception was cleared", player._dropping_platform == null)
	# 从下面跳回平台上
	player.global_position = Vector2(208, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("jump")
	var landed := false
	for i in 90:
		await frames(1)
		if player.is_on_floor() and absf(feet() - PLATFORM_TOP) < 4.0:
			landed = true
			break
	Input.action_release("jump")
	check("can stand on that same platform again", landed, "feet at %.1f" % feet())


func test_dropping_while_lying_down() -> void:
	# 趴在平台上也能跳下去（趴下用 Ctrl，跳下用「下 + 跳」，互不冲突）
	await stand_on_platform()
	Input.action_press("crouch")
	await frames(6)
	check("setup: lying down on the platform", player.is_crouching and player.is_on_floor())
	Input.action_press("aim_down")
	await tap("jump")
	var below := false
	for i in 60:
		await frames(1)
		if feet() > PLATFORM_TOP + 4.0:
			below = true
			break
	release_all_input()
	check("drops through while lying down", below, "feet at %.1f" % feet())
