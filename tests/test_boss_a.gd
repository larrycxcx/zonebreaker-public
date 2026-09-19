extends GameTest
## Boss A：体型大、会跳、不会趴下；不追击，靠 8 方向射击（走动、跳跃中都能开火），接触会伤人；
## 躲开「落过地」贴地弹跳的手雷，不躲空中的手雷；终极武器一次扣 1/4 血。

const GRENADE_SCENE := "res://scenes/grenade.tscn"
const NORMAL_ENEMIES := [
	"res://scenes/enemy_walker_a.tscn", "res://scenes/enemy_walker_b.tscn", "res://scenes/enemy_walker_c.tscn",
	"res://scenes/enemy_turret.tscn", "res://scenes/enemy_flyer.tscn", "res://scenes/enemy_chaser.tscn",
]

var boss: BossA


## 只留 Boss A（出生点 x=600），玩家站在 player_x。玩家血量调得很高，免得被 Boss 打死打乱用例。
func start(player_x := 470.0) -> void:
	await reset_scene(true)
	keep_only_enemies(["BossA"])
	boss = main.get_node("Enemies/BossA")
	player.health = 999
	player.global_position = Vector2(player_x, 152)
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
	await start(470)
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
	check("stays near home, does not chase the player", far <= boss.roam_range + 8.0, "%.1f px from home" % far)
	check("jumps", airborne)
	check("jumps high", home - home + (144.0 - top) > 30.0, "%.1f px" % (144.0 - top))


func test_never_lies_down() -> void:
	await start(480)
	Input.action_press("crouch")
	var prone := false
	for i in 120:
		await frames(1)
		prone = prone or boss.is_prone or shape_size(boss).y != 32.0
	Input.action_release("crouch")
	check("setup: player lying down", true)
	check("boss never lies down", not prone)


func test_snap_direction() -> void:
	var cases := {
		Vector2(1, 0): Vector2(1, 0), Vector2(1, 0.3): Vector2(1, 0), Vector2(-5, 1): Vector2(-1, 0),
		Vector2(1, -1): Vector2(1, -1).normalized(), Vector2(2, -1.5): Vector2(1, -1).normalized(),
		Vector2(0.2, -1): Vector2(0, -1), Vector2(-1, -1): Vector2(-1, -1).normalized(),
		Vector2(-1, 1): Vector2(-1, 1).normalized(), Vector2(0.1, 3): Vector2(0, 1), Vector2(1, 1.2): Vector2(1, 1).normalized(),
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
		# Boss 悬在半空（每帧拉回原处），玩家放在它的这个方向上 60px
		for f in 20:
			boss.global_position = Vector2(560, 90)
			boss.velocity = Vector2.ZERO
			player.global_position = boss.global_position + dir * 60.0
			player.velocity = Vector2.ZERO
			await frames(1)
			if boss.last_shot_direction != Vector2.ZERO:
				break
		check("fires toward %s" % dir, boss.last_shot_direction.is_equal_approx(dir), str(boss.last_shot_direction))


func test_level_shots_fly_at_standing_height() -> void:
	# 水平子弹离地 7px：和普通敌人一样，趴下的玩家能躲开
	await start(480)
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
		check("level shot leaves 7px above the ground", absf((160.0 - shots[0]) - 7.0) < 0.5, str(160.0 - shots[0]))


func test_fires_while_moving_and_in_the_air() -> void:
	await start(480)
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
	await start(470)
	hold_still()
	player.health = 3
	player.global_position = Vector2(boss.global_position.x - 14, 152)
	await frames(5)
	check("touching the boss hurts", player.health < 3)


func test_dodges_a_grenade_on_the_ground() -> void:
	for side in [-1, 1]:
		await start(470)
		hold_still()
		var x0 := boss.global_position.x
		place_grenade(Vector2(x0 + side * 30, 156), true)
		var jumped := false
		for i in 20:
			await frames(1)
			jumped = jumped or not boss.is_on_floor()
		var moved := boss.global_position.x - x0
		check("grenade on the %s: moves away" % ("left" if side < 0 else "right"), signf(moved) == -side and absf(moved) > 10.0, "%.1f" % moved)
		check("grenade on the %s: jumps" % ("left" if side < 0 else "right"), jumped)


func test_ignores_a_grenade_in_the_air() -> void:
	await start(470)
	hold_still()
	var x0 := boss.global_position.x
	place_grenade(Vector2(x0 - 30, 110), false)
	var jumped := false
	for i in 20:
		await frames(1)
		jumped = jumped or not boss.is_on_floor()
	check("does not move", absf(boss.global_position.x - x0) < 0.5)
	check("does not jump", not jumped)


func test_grenade_lands_and_is_dodged() -> void:
	# 真的扔一颗：落在 Boss 前面、弹向它，Boss 躲开，不掉血
	await start(440)
	hold_still()
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
	await start(490)
	hold_still()
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
	grenade.velocity = Vector2(200, 0)
	grenade.gravity = 0.0
	main.add_child(grenade)
	grenade.global_position = Vector2(620, 100)
	var bounced := false
	for i in 20:
		await frames(1)
		if grenade.velocity.x < 0.0:
			bounced = true
			break
	check("setup: bounced off the right wall", bounced)
	check("a wall bounce does not count as landing", not grenade.landed)
	grenade.queue_free()
