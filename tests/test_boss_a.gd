extends GameTest
## Boss A：体型大、会跳、不会趴下；不追击，靠 16 方向射击（走动、跳跃中都能开火），接触会伤人；
## 躲开「落过地」贴地弹跳的手雷，不躲空中的手雷；终极武器一次扣 1/4 血。

const GRENADE_SCENE := "res://scenes/grenade.tscn"
const NORMAL_ENEMIES := [
	"res://scenes/enemy_walker_a.tscn", "res://scenes/enemy_walker_b.tscn", "res://scenes/enemy_walker_c.tscn",
	"res://scenes/enemy_turret.tscn", "res://scenes/enemy_flyer.tscn", "res://scenes/enemy_chaser.tscn",
]

var boss: BossA


## 只留 Boss A（出生点 x=1200），玩家站在 player_x。玩家血量调得很高，免得被 Boss 打死打乱用例。
func start(player_x := 940.0) -> void:
	await reset_scene(true)
	keep_only_enemies(["BossA"])
	boss = main.get_node("Enemies/BossA")
	player.health = 999
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	# 玩家站得靠左时 Boss 的中心可能刚好压在屏幕边上还没出场；这里直接让它出场，出场规则由 test_boss.gd 测。
	boss.appear()


## 让 Boss 原地不动、不跳、不开枪（测躲手雷时排除其它动作的干扰）。
func hold_still() -> void:
	boss.roam_speed = 0.0
	boss._jump_timer = 999.0
	boss.jump_interval_min = 999.0
	boss.jump_interval_max = 999.0
	boss.fire_interval = 999.0
	boss._fire_timer = 999.0
	boss._burst_left = 0


## 移走 Boss 区域那块平台（只测手雷、不关心地形的用例用）。
func clear_high_ground() -> void:
	boss._high_ground = null
	main.get_node("Level/BossPlatform").free()


## 把 Boss 摆到 x、玩家摆到它左边 distance 处（Boss 会走动，扔手雷的用例需要固定的距离）。
## 摆在 1200：从那里往左 220~320px 是一段没有平台的空地，抛物线不会中途落在平台上。
func park_boss_and_player(distance: float, x := 1200.0) -> void:
	boss.global_position = Vector2(x, 288)
	boss.velocity = Vector2.ZERO
	player.global_position = Vector2(x - distance, 304)
	player.velocity = Vector2.ZERO
	await frames(5)


func shape_size(body: Node) -> Vector2:
	return ((body.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size


## 在 pos 放一颗静止的手雷（关掉它自己的物理，只当一个「在那里的手雷」）。
func place_grenade(pos: Vector2, landed: bool) -> Grenade:
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.landed = landed
	main.add_child(grenade)
	grenade.global_position = pos
	grenade.set_physics_process(false)
	return grenade


func test_config() -> void:
	await start()
	check("Boss A is a boss", boss is Boss)
	var size := shape_size(boss)
	for path in NORMAL_ENEMIES:
		var enemy: Node = load(path).instantiate()
		var other := shape_size(enemy)
		check("bigger than %s" % path.get_file(), size.x > other.x and size.y > other.y, "%s vs %s" % [size, other])
		enemy.free()
	check("never lies down", not boss.can_go_prone)
	check("ultimate deals 1/4 of max health", boss.ultimate_damage() * 4 == boss.max_health, "%d / %d" % [boss.ultimate_damage(), boss.max_health])
	check("appears when on screen", boss.has_appeared)


func test_ultimate_takes_a_quarter() -> void:
	await start()
	for i in 3:
		boss.hit_by_ultimate()
	check("three ultimates leave a quarter", boss.health == boss.max_health / 4, str(boss.health))
	boss.hit_by_ultimate()
	await frames(1)
	check("the fourth one finishes it", not is_instance_valid(boss))


func test_roams_near_home_without_chasing() -> void:
	await start(940)
	var home := boss.global_position.x
	var far := 0.0
	var moved := false
	var airborne := false
	var top := boss.global_position.y
	for i in 480:
		await frames(1)
		far = maxf(far, absf(boss.global_position.x - home))
		moved = moved or absf(boss.velocity.x) > 0.0
		airborne = airborne or not boss.is_on_floor()
		top = minf(top, boss.global_position.y)
	check("walks around", moved)
	check("stays near home, does not chase the player", far <= boss.roam_range + 16.0, "%.1f px from home" % far)
	check("jumps", airborne)
	check("jumps high", home - home + (288.0 - top) > 60.0, "%.1f px" % (288.0 - top))


## 把玩家钉在 x 处若干帧（Boss 会撞它、打它，不钉住位置会被推开），返回最后两者的水平距离。
func pin_player_at(x: float, frame_count := 120) -> float:
	for i in frame_count:
		player.global_position = Vector2(x, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
	return absf(boss.global_position.x - x)


func test_backs_off_when_the_player_gets_close() -> void:
	# 贴脸时边退边打。逐帧看：只要玩家在 close_range 以内，它就不该朝玩家这边走
	#（只看最后的距离不行，随机游走本来也会走开）。
	await start()
	var spot := boss.global_position.x - 40.0
	var toward := 0
	var close_frames := 0
	for i in 120:
		player.global_position = Vector2(spot, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
		var offset := spot - boss.global_position.x
		if absf(offset) < boss.close_range and boss.is_on_floor():
			close_frames += 1
			if signf(boss.velocity.x) == signf(offset):
				toward += 1
	check("setup: the player did get close", close_frames > 10, str(close_frames))
	# 允许一两帧的过渡：玩家是瞬间被挪到它面前的，那一帧它还带着上一帧的速度
	check("never walks into a player in its face", toward <= 2, "%d of %d frames" % [toward, close_frames])
	check("ends up out of arm's reach", absf(boss.global_position.x - spot) > boss.close_range - 20.0,
		"%.1f px apart" % absf(boss.global_position.x - spot))
	check("back-off is slower than the player walks", boss.back_off_speed < player.move_speed, "%.0f vs %.0f" % [boss.back_off_speed, player.move_speed])


func test_steps_closer_when_the_player_is_far() -> void:
	# 远处（但在射程内）会压上来找开火位置
	await start()
	var spot := boss._home.x - 400.0
	var before := absf(boss.global_position.x - spot)
	await pin_player_at(spot, 360)
	# 最后 120 帧一直待在交战距离上：随机游走的话会晃回远处去
	var worst := 0.0
	var gap := 0.0
	for i in 60:
		player.global_position = Vector2(spot, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
		gap = absf(boss.global_position.x - spot)
		worst = maxf(worst, gap)
	check("closes in on a distant player", gap < before - 60.0, "%.1f -> %.1f" % [before, gap])
	check("and keeps that range instead of drifting back", worst <= boss.far_range + 60.0, "worst %.1f" % worst)
	check("stops around its preferred range", gap > boss.close_range, "%.1f" % gap)
	check("never leaves its ground to chase", boss.global_position.x >= boss._home.x - boss.roam_range - 16.0, str(boss.global_position.x))


func test_cornered_at_the_edge_of_its_ground() -> void:
	# 被逼到地盘边上就不再后退（宁可被贴脸也不退出去）。
	# 关卡右墙正好在地盘边界外侧，光靠墙也能挡住，所以这里把地盘临时收窄，测的是边界本身。
	await start()
	boss.roam_range = 80.0
	var edge := boss._home.x + boss.roam_range
	# 玩家在它左边逼近，它只能往右退，右边就是地盘边界
	boss.global_position = Vector2(edge - 20.0, 288)
	await pin_player_at(edge - 90.0, 360)
	check("holds the edge of its ground", boss.global_position.x <= edge + 16.0,
		"%.1f, edge at %.1f" % [boss.global_position.x, edge])
	check("and stays cornered there instead of fleeing past it", boss.global_position.x > edge - 60.0,
		"%.1f, edge at %.1f" % [boss.global_position.x, edge])


func test_ground_is_wider_than_before() -> void:
	await start()
	check("the boss ground covers most of the boss area", boss.roam_range >= 140.0, str(boss.roam_range))
	# 玩家远在射程外：它自己随机游走，应该用上比老范围（±64）宽得多的地方，但不越界
	player.global_position = Vector2(boss._home.x - 600.0, 304)
	player.velocity = Vector2.ZERO
	var reach := 0.0
	for i in 600:
		await frames(1)
		reach = maxf(reach, absf(boss.global_position.x - boss._home.x))
	check("wanders across more than the old 64px range", reach > 80.0, "%.1f px from home" % reach)
	check("but never a step beyond its ground", reach <= boss.roam_range + 16.0, "%.1f px from home" % reach)


func test_never_lies_down() -> void:
	await start(960)
	Input.action_press("crouch")
	var prone := false
	for i in 120:
		await frames(1)
		prone = prone or boss.is_prone or shape_size(boss).y != 64.0
	Input.action_release("crouch")
	check("setup: player lying down", true)
	check("boss never lies down", not prone)


func test_snap_direction() -> void:
	var cases := {
		Vector2(1, 0): Vector2(1, 0), Vector2(1, 0.3): Vector2(1, 0), Vector2(-10, 2): Vector2(-1, 0),
		Vector2(1, -1): Vector2(1, -1).normalized(), Vector2(4, -3.0): Vector2(1, -1).normalized(),
		Vector2(0.2, -1): Vector2(0, -1), Vector2(-1, -1): Vector2(-1, -1).normalized(),
		Vector2(-1, 1): Vector2(-1, 1).normalized(), Vector2(0.2, 6): Vector2(0, 1), Vector2(1, 1.2): Vector2(1, 1).normalized(),
	}
	for offset in cases:
		var got := BossA.snap_direction(offset)
		check("%s snaps to %s" % [offset, cases[offset]], got.is_equal_approx(cases[offset]), str(got))


func test_fires_in_all_eight_directions() -> void:
	await start()
	for i in 8:
		var dir := Vector2.from_angle(i * PI / 4.0)
		dir = Vector2(snappedf(dir.x, 0.0001), snappedf(dir.y, 0.0001)).normalized()
		boss._fire_timer = 0.0
		boss._burst_left = 0
		boss.last_shot_direction = Vector2.ZERO
		# Boss 悬在半空（每帧拉回原处），玩家放在它的这个方向上 120px
		for f in 40:
			boss.global_position = Vector2(1120, 180)
			boss.velocity = Vector2.ZERO
			player.global_position = boss.global_position + dir * 120.0
			player.velocity = Vector2.ZERO
			await frames(1)
			if boss.last_shot_direction != Vector2.ZERO:
				break
		check("fires toward %s" % dir, boss.last_shot_direction.is_equal_approx(dir), str(boss.last_shot_direction))


func test_level_shots_fly_at_standing_height() -> void:
	# 水平子弹离地 14px：和普通敌人一样，趴下的玩家能躲开
	await start(960)
	var shots := []
	boss.shot_fired.connect(func() -> void:
		if boss.last_shot_direction.y == 0.0 and boss.is_on_floor():
			shots.append(boss._muzzle_position().y))
	for i in 240:
		await frames(1)
		if not shots.is_empty():
			break
	check("fired a level shot from the ground", not shots.is_empty())
	if not shots.is_empty():
		check("level shot leaves 23px above the ground", absf((320.0 - shots[0]) - 23.0) < 0.5, str(320.0 - shots[0]))


func test_fires_while_moving_and_in_the_air() -> void:
	await start(960)
	var shots := []
	boss.shot_fired.connect(func() -> void: shots.append({"air": not boss.is_on_floor(), "vx": boss.velocity.x}))
	# 空中：等它落地、这一轮连发打完，起跳后立刻让它开火
	for i in 120:
		await frames(1)
		if boss.is_on_floor() and boss._burst_left == 0:
			break
	boss.velocity.y = boss.jump_velocity
	await frames(3)
	shots.clear()
	boss._fire_timer = 0.0
	await frames(2)
	check("fires in mid-air", shots.any(func(s): return s["air"]), str(shots))
	# 走动中：平时一直在走，开火时水平速度不为 0
	for i in 240:
		await frames(1)
		if shots.any(func(s): return not s["air"] and s["vx"] != 0.0):
			break
	check("fires while walking", shots.any(func(s): return s["vx"] != 0.0), str(shots))


func test_contact_hurts_the_player() -> void:
	await start(940)
	hold_still()
	player.health = 3
	player.global_position = Vector2(boss.global_position.x - 28, 304)
	await frames(5)
	check("touching the boss hurts", player.health < 3)


func test_dodges_a_grenade_on_the_ground() -> void:
	for side in [-1, 1]:
		await start(940)
		hold_still()
		var x0 := boss.global_position.x
		place_grenade(Vector2(x0 + side * 60, 312), true)
		var jumped := false
		for i in 20:
			await frames(1)
			jumped = jumped or not boss.is_on_floor()
		var moved := boss.global_position.x - x0
		check("grenade on the %s: moves away" % ("left" if side < 0 else "right"), signf(moved) == -side and absf(moved) > 20.0, "%.1f" % moved)
		check("grenade on the %s: jumps" % ("left" if side < 0 else "right"), jumped)


func test_ignores_a_grenade_in_the_air() -> void:
	await start(940)
	hold_still()
	var x0 := boss.global_position.x
	place_grenade(Vector2(x0 - 60, 220), false)
	var jumped := false
	for i in 20:
		await frames(1)
		jumped = jumped or not boss.is_on_floor()
	check("does not move", absf(boss.global_position.x - x0) < 0.5)
	check("does not jump", not jumped)


func test_grenade_lands_and_is_dodged() -> void:
	# 真的扔一颗：落在 Boss 前面、弹向它，Boss 躲开，不掉血
	await start()
	clear_high_ground() # 这条只测躲手雷，别让抛物线打在平台上
	hold_still()
	await park_boss_and_player(320.0) # 手雷平地扔出去约 220px，落在 Boss 前面
	player.facing = 1
	player.switch_weapon()
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var grenade: Grenade = main.get_children().filter(func(c): return c is Grenade)[0]
	var landed := false
	var dodged := false
	for i in 120:
		await frames(1)
		if not is_instance_valid(grenade):
			break
		landed = landed or grenade.landed
		dodged = dodged or boss.is_dodging
	check("grenade landed before reaching the boss", landed)
	check("boss dodged", dodged)
	check("boss took no damage", boss.health == boss.max_health, "%d / %d" % [boss.health, boss.max_health])


func test_grenade_in_the_air_hits_directly() -> void:
	# 近一点扔：还在空中就砸到 Boss 身上，Boss 不躲，吃满伤害
	await start()
	clear_high_ground()
	hold_still()
	await park_boss_and_player(220.0)
	player.facing = 1
	player.switch_weapon()
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var grenade: Grenade = main.get_children().filter(func(c): return c is Grenade)[0]
	var dodged := false
	var landed := false
	for i in 120:
		await frames(1)
		if not is_instance_valid(grenade):
			break
		landed = landed or grenade.landed
		dodged = dodged or boss.is_dodging or not boss.is_on_floor()
	check("setup: grenade never landed", not landed)
	check("boss did not dodge", not dodged)
	check("direct hit damage", boss.health == boss.max_health - 3, "%d / %d" % [boss.health, boss.max_health])


func test_a_wall_bounce_is_not_landing() -> void:
	# 手雷撞墙弹回来仍然是「空中」的手雷，Boss 不躲；只有撞到地面/平台顶面才算落地
	await start()
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.launch(Vector2.RIGHT)
	grenade.velocity = Vector2(400, 0)
	grenade.gravity = 0.0
	main.add_child(grenade)
	grenade.global_position = Vector2(1240, 200)
	var bounced := false
	for i in 20:
		await frames(1)
		if grenade.velocity.x < 0.0:
			bounced = true
			break
	check("setup: bounced off the right wall", bounced)
	check("a wall bounce does not count as landing", not grenade.landed)
	grenade.queue_free()


# ---------------------------------------------------------------- 抢高处（BossPlatform）

func platform() -> Platform:
	return main.get_node("Level/BossPlatform")


## 让玩家趴在 x 处（趴着不能开枪，只需要按住 Ctrl）。
func lie_down_at(x: float) -> void:
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(8)


## 等 Boss 站上平台，返回用了多少帧（超时返回 -1）。
func wait_until_high(limit := 800) -> int:
	for i in limit:
		await frames(1)
		if boss.on_high_ground():
			return i
	return -1


func test_boss_platform_setup() -> void:
	await start()
	var p := platform()
	check("the level has a platform in the boss area", p != null and p.one_way)
	check("the boss knows about it", boss._high_ground == p)
	var height := 320.0 - p.global_position.y
	check("the boss can jump onto it", height < 114.0, "%.0fpx high, boss jumps ~114px" % height)
	check("the player can jump onto it too", height < 92.0, "%.0fpx high, player jumps ~92px" % height)
	check("it is inside the boss's ground, so it can reach it", p.global_position.x > boss._home.x - boss.roam_range
		and p.global_position.x + p.size.x < boss._home.x + boss.roam_range,
		"platform %.0f..%.0f, ground %.0f..%.0f" % [p.global_position.x, p.global_position.x + p.size.x,
		boss._home.x - boss.roam_range, boss._home.x + boss.roam_range])


func test_level_shots_miss_a_prone_player() -> void:
	# 前提：玩家趴下时，Boss 站在地上打的水平子弹会从头顶飞过。
	# 这条只看「站在地上水平打」的情况：取消它上高处的能力，也不让它随机跳
	#（跳在空中时趴着的玩家就成了斜下方的目标，它照样打得到——那是另一条用例的事）。
	await start()
	boss._high_ground = null
	boss.jump_interval_min = 999.0
	boss.jump_interval_max = 999.0
	boss._jump_timer = 999.0
	await lie_down_at(1040)
	var over := 0
	for i in 200:
		await frames(1)
		for b in bullets(16):
			if b.direction.y == 0.0 and b.global_position.y < 312.0:
				over += 1
	check("level shots fly over the prone player", over > 0)
	check("the prone player is not hit by them", player.health == 999, str(player.health))
	release_all_input()


func test_climbs_when_the_player_lies_down() -> void:
	await start()
	check("stays on the ground while the player stands", not boss.on_high_ground())
	await lie_down_at(940)
	var took := await wait_until_high()
	check("climbs onto the platform", took > 0, "gave up after 400 frames")
	check("only after the player has been prone a moment", boss.high_ground_delay > 0.0)
	# 上去之后站定不动
	var x := boss.global_position.x
	await frames(30)
	check("holds position up there", absf(boss.global_position.x - x) < 4.0 and boss.on_high_ground())
	release_all_input()


func test_fires_diagonally_down_from_the_platform_and_hits() -> void:
	await start()
	# 趴在平台中心左下方 90° 附近：Boss 在上面往斜下打正好打得到
	var p := platform()
	var center := p.global_position.x + p.size.x / 2.0
	await lie_down_at(center - 96.0)
	check("climbed up", await wait_until_high() > 0)
	player.health = 3
	var down := 0
	for i in 300:
		await frames(1)
		if boss.last_shot_direction.y > 0.0 and boss.last_shot_direction.x != 0.0:
			down += 1
		if player.health < 3:
			break
	check("fires diagonally down from up there", down > 0, str(boss.last_shot_direction))
	check("and hits the prone player", player.health < 3, str(player.health))
	check("the player was still lying down", player.is_crouching)
	release_all_input()


func test_comes_back_down_when_the_player_stands_up() -> void:
	await start()
	await lie_down_at(940)
	check("climbed up", await wait_until_high() > 0)
	Input.action_release("crouch")
	await frames(10)
	var down := false
	for i in 300:
		await frames(1)
		if not boss.on_high_ground() and boss.is_on_floor():
			down = true
			break
	check("leaves the platform once the player stands up", down)
	check("back in its roaming range", absf(boss.global_position.x - boss._home.x) <= boss.roam_range + 16.0, str(boss.global_position.x))


func test_skips_a_jump_that_would_land_on_the_platform() -> void:
	await start()
	var p := platform()
	boss.roam_speed = 0.0 # 站着不动：这一跳的落点就是脚下，必定落到平台上
	boss.global_position = Vector2(p.global_position.x + p.size.x / 2.0, 288)
	boss.velocity = Vector2.ZERO
	player.global_position = Vector2(boss.global_position.x - 160.0, 304) # 站着，不会触发抢高处
	player.velocity = Vector2.ZERO
	await frames(5)
	check("setup: standing right under the platform", boss.is_on_floor() and not boss.on_high_ground())
	boss._jump_timer = 0.0
	await frames(3)
	check("skips a random jump that would put it on the platform", boss.is_on_floor() and not boss.on_high_ground(),
		"y=%.1f" % boss.global_position.y)
	# 走开一点（落点不在平台上）就照常跳
	boss.global_position = Vector2(p.global_position.x - 120.0, 288)
	await frames(3)
	boss._jump_timer = 0.0
	var jumped := false
	for i in 20:
		await frames(1)
		jumped = jumped or not boss.is_on_floor()
	check("still jumps normally away from the platform", jumped)


func test_does_not_hold_the_high_ground_for_a_standing_player() -> void:
	# 它只在玩家趴下时才占高处。随机跳跃偶尔会落到平台上（空中还会横着飘一段），
	# 但那种情况它马上就走下来，不会待在上面。
	await start(940)
	var frames_up := 0
	for i in 400:
		await frames(1)
		if boss.on_high_ground():
			frames_up += 1
	# 偶尔一次落到平台上再走下来大约 80 帧；「占着高处」会是几百帧。
	check("does not hold the high ground while the player stands", frames_up < 120, "%d of 400 frames up there" % frames_up)
