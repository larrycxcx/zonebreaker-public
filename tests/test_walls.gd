extends GameTest
## 竖墙：高度不超过跳跃高度（能翻过去）、挡路、挡子弹、挡敌人视线，巡逻兵碰到会掉头。
## 这组用例要保留墙，所以都用 reset_scene(…, true)。

const GROUND_Y := 160.0


func walls() -> Array[Platform]:
	var found: Array[Platform] = []
	for wall in main.get_node("Level/Walls").get_children():
		found.append(wall as Platform)
	return found


func wall(wall_name: String) -> Platform:
	return main.get_node("Level/Walls/" + wall_name) as Platform


## 实测玩家在平地上一次完整跳跃能把脚抬多高。
func measure_jump_height() -> float:
	await reset_scene()
	await frames(20)
	var ground := player.global_position.y
	var top := ground
	Input.action_press("jump")
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
	Input.action_release("jump")
	return ground - top


func test_level_has_vertical_walls() -> void:
	await reset_scene(false, true)
	var all := walls()
	check("the level has 3 walls", all.size() == 3, str(all.size()))
	for w in all:
		check("%s is solid, not a one-way platform" % w.name, not w.one_way)
		check("%s is taller than it is wide" % w.name, w.size.y > w.size.x, str(w.size))
		check("%s stands on the ground" % w.name, is_equal_approx(w.position.y + w.size.y, GROUND_Y), "bottom at %.1f" % (w.position.y + w.size.y))


func test_walls_are_lower_than_the_jump() -> void:
	var jump_height := await measure_jump_height()
	await reset_scene(false, true)
	for w in walls():
		# 至少留 6px 余量，正常起跳就能翻过去，不需要卡极限。
		check("%s (%dpx) is at least 6px lower than the %.0fpx jump" % [w.name, int(w.size.y), jump_height], w.size.y <= jump_height - 6.0)


func test_player_can_jump_over_every_wall() -> void:
	for wall_name in ["Wall1", "Wall2", "Wall3"]:
		await reset_scene(false, true)
		var w := wall(wall_name)
		# 从墙左边 40px 处往右跑，离墙 22px 时起跳并按住跳跃键。
		# Wall1 左边上方有 Platform1，改从右边往左翻，免得跳到平台上去。
		var from_left: bool = wall_name != "Wall1"
		var direction := 1 if from_left else -1
		var face_x := w.position.x if from_left else w.position.x + w.size.x
		player.global_position = Vector2(face_x - 40.0 * direction, 152)
		player.velocity = Vector2.ZERO
		await frames(5)
		Input.action_press("move_right" if from_left else "move_left")
		var jumped := false
		for i in 120:
			await tree.physics_frame
			if not jumped and absf(player.global_position.x - face_x) < 22.0:
				Input.action_press("jump")
				jumped = true
		release_all_input()
		var crossed: bool = player.global_position.x > w.position.x + w.size.x if from_left else player.global_position.x < w.position.x
		check("player jumps over %s (%dpx)" % [wall_name, int(w.size.y)], crossed, "ended at x=%.1f" % player.global_position.x)


func test_walls_block_walking() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	player.global_position = Vector2(w.position.x - 30.0, 152)
	player.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await frames(90)
	check("walking into a wall stops the player", player.global_position.x < w.position.x, "x=%.1f" % player.global_position.x)
	Input.action_press("sprint")
	await frames(60)
	check("sprinting into it does not get through either", player.global_position.x < w.position.x, "x=%.1f" % player.global_position.x)


func test_walls_stop_player_bullets() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	player.global_position = Vector2(w.position.x - 40.0, 152)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	var passed := false
	for i in 30:
		await tree.physics_frame
		for b in bullets(4):
			passed = passed or b.global_position.x > w.position.x + w.size.x
	check("player bullets never get past the wall", not passed)
	check("the bullet is destroyed at the wall", bullets(4).is_empty(), str(bullets(4).size()))


func test_walls_stop_enemy_bullets() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	# 直接在墙右边生成一颗往左飞的敌人子弹，玩家站在墙左边。
	player.global_position = Vector2(w.position.x - 30.0, 152)
	var bullet: Bullet = load("res://scenes/enemy_bullet.tscn").instantiate()
	bullet.direction = Vector2.LEFT
	main.add_child(bullet)
	bullet.global_position = Vector2(w.position.x + w.size.x + 20.0, 153)
	await frames(40)
	check("enemy bullets are destroyed by the wall", not is_instance_valid(bullet))
	check("the player behind the wall is not hit", player.health == player.max_health, str(player.health))


func test_turret_cannot_see_through_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	var w := wall("Wall3") # 36px 高，挡在炮台（x=580）前面
	var shots := [0]
	turret.shot_fired.connect(func(): shots[0] += 1)
	# 玩家站在墙左边，炮台射程内（200px）。
	player.global_position = Vector2(w.position.x - 40.0, 152)
	player.velocity = Vector2.ZERO
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("turret holds fire at a player hidden behind the wall", shots[0] == 0, str(shots[0]))
	check("find_target reports nothing", turret.find_target() == null)

	Input.action_press("crouch")
	await frames(60)
	check("turret does not go prone for a player it cannot see", not turret.is_prone)
	Input.action_release("crouch")

	# 对照组：拆掉墙，同一位置马上就会被打。
	w.free()
	await frames(2)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("without the wall the turret fires at the same spot", shots[0] > 0, str(shots[0]))


func test_walker_cannot_see_through_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	var w := wall("Wall2")
	# C 的射程 200px。它站在墙右边朝左，玩家在墙左边。
	walker.global_position = Vector2(w.position.x + w.size.x + 40.0, 153)
	walker.move_speed = 0.0
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(w.position.x - 40.0, 152)
	player.velocity = Vector2.ZERO
	var shots := [0]
	walker.shot_fired.connect(func(): shots[0] += 1)
	Input.action_press("crouch")
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("walker holds fire at a player behind the wall", shots[0] == 0, str(shots[0]))
	check("walker does not go prone for a player it cannot see", not walker.is_prone)


func test_line_of_sight_passes_one_way_platforms() -> void:
	await reset_scene(true, false)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	# 只测射线本身：停掉炮台的物理，免得挪到矮通道下面时和顶板重叠被推开。
	turret.set_physics_process(false)
	# 从炮台枪口看 Platform1（单向，x 80..128，y 128..136）正上方的一个点：视线要穿过平台。
	turret.global_position = Vector2(104, 153)
	await frames(3)
	check("one-way platforms do not block line of sight", turret.has_line_of_sight(Vector2(104, 110)))
	# 同样的方式看 CrawlBlock（实心，x 296..352，y 120..148）上方：会被挡住。
	turret.global_position = Vector2(324, 153)
	await frames(3)
	check("solid blocks do block line of sight", not turret.has_line_of_sight(Vector2(324, 110)))


func test_walker_turns_around_at_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var w := wall("Wall1")
	walker.global_position = Vector2(w.position.x + w.size.x + 30.0, 153)
	walker.facing = -1
	walker._apply_facing()
	var crossed := false
	var turned := false
	for i in 200:
		await tree.physics_frame
		crossed = crossed or walker.global_position.x < w.position.x
		turned = turned or walker.facing == 1
	check("walker turns around at the wall", turned)
	check("walker never walks through the wall", not crossed, "x=%.1f" % walker.global_position.x)
