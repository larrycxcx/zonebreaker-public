extends GameTest
## 敌人 E（飞行）：不受重力、固定高度波浪巡逻、玩家到正下方才开火并在上空跟随、
## 子弹竖直向下且穿过单向平台、实心物体挡视线、跟丢后放弃。

const ALTITUDE := 88.0


## 只留 E，把它放到 pos 作为波浪高度和巡逻中心；玩家先停在远处（不在它下方）。
func _setup_flyer(pos: Vector2, keep_walls := false) -> EnemyFlyer:
	await reset_scene(true, keep_walls)
	keep_only_enemies(["FlyerE"])
	var e: EnemyFlyer = main.get_node("Enemies/FlyerE")
	e.set_anchor(pos)
	e.velocity = Vector2.ZERO
	player.global_position = Vector2(pos.x + 400.0 if pos.x < 640.0 else pos.x - 400.0, 304)
	player.velocity = Vector2.ZERO
	await frames(3)
	return e


func _put_player(x: float) -> void:
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO


func test_e_is_configured() -> void:
	await reset_scene(true, true)
	var e: EnemyFlyer = main.get_node("Enemies/FlyerE")
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("E flies at the normal enemy speed", e.move_speed == walker.move_speed, "%.1f" % e.move_speed)
	check("E fires straight down", e.shoot_direction() == Vector2.DOWN)
	check("E has a gun", e.bullet_scene != null)
	check("E's muzzle is on its body, not inside Visual", e.get_node_or_null("Muzzle") != null and e.get_node_or_null("Visual/Muzzle") == null)
	check("E never goes prone", not e.can_go_prone)
	# 飞行高度要高过所有平台和墙，包括波浪最低点。
	var lowest_top := INF
	for node in main.get_node("Level").get_children():
		if node is Platform and String(node.name).begins_with("Platform") or node.name == "CrawlBlock":
			lowest_top = minf(lowest_top, (node as Platform).position.y)
	for w in main.get_node("Level/Walls").get_children():
		lowest_top = minf(lowest_top, (w as Platform).position.y)
	var body_bottom: float = e.global_position.y + 20.0 + e.wave_amplitude
	check("E flies above every platform and wall", body_bottom < lowest_top, "bottom %.1f vs highest top %.1f" % [body_bottom, lowest_top])


func test_e_flies_without_falling() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	var lowest := -INF
	for i in 180:
		await tree.physics_frame
		lowest = maxf(lowest, e.global_position.y)
	check("E never drops below its wave", lowest <= ALTITUDE + e.wave_amplitude + 0.5, "lowest y %.1f" % lowest)


func test_e_patrols_in_a_wave() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	var top := INF
	var bottom := -INF
	var x0 := e.global_position.x
	for i in 150: # 2.5 秒，超过一个 2 秒的周期
		await tree.physics_frame
		top = minf(top, e.global_position.y)
		bottom = maxf(bottom, e.global_position.y)
	var swing := bottom - top
	check("E bobs up and down by twice the wave amplitude", absf(swing - 2.0 * e.wave_amplitude) < 2.0, "%.1f px" % swing)
	check("the wave is centred on its altitude", absf((top + bottom) / 2.0 - ALTITUDE) < 2.0, "centre %.1f" % ((top + bottom) / 2.0))
	check("E moves sideways at the normal enemy speed", is_equal_approx(absf(e.velocity.x), e.move_speed), "%.1f" % absf(e.velocity.x))
	check("and actually travels", absf(e.global_position.x - x0) > 60.0, "%.1f px" % absf(e.global_position.x - x0))


func test_e_patrols_within_its_range() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	var turns := 0
	var last_facing := e.facing
	var farthest := 0.0
	for i in 600: # 10 秒，够来回好几趟
		await tree.physics_frame
		farthest = maxf(farthest, absf(e.global_position.x - 400.0))
		if e.facing != last_facing:
			turns += 1
			last_facing = e.facing
	check("E turns around at the ends of its patrol", turns >= 2, "%d turns" % turns)
	check("E stays within its patrol range", farthest <= e.patrol_distance + 4.0, "%.1f px from centre" % farthest)


func test_e_ignores_a_player_not_below_it() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	e.move_speed = 0.0 # 停住，免得巡逻时自己飞到玩家头顶
	_put_player(500.0)
	var shots := 0
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		shots += bullets(16).size()
	check("E holds fire when the player is off to the side", shots == 0, str(shots))
	check("and does not start following", not e.is_following)


func test_e_fires_down_when_the_player_is_below() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	e.move_speed = 0.0
	_put_player(400.0)
	var shot: Bullet = null
	for i in 20:
		await tree.physics_frame
		var found := bullets(16)
		if not found.is_empty():
			shot = found[0]
			break
	check("E opens fire at a player right below it", shot != null)
	check("E starts following", e.is_following)
	if shot != null:
		check("the bullet flies straight down", shot.direction == Vector2.DOWN, str(shot.direction))
		check("the bullet is turned upright", is_equal_approx(shot.rotation, PI / 2.0), "%.3f" % shot.rotation)
		check("the bullet starts under E", shot.global_position.y > e.global_position.y and absf(shot.global_position.x - e.global_position.x) < 4.0, str(shot.global_position))
	var hit := false
	for i in 90:
		await tree.physics_frame
		if player.health < player.max_health:
			hit = true
			break
	check("the bullet reaches the player", hit)


func test_e_follows_the_player_overhead() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	_put_player(400.0)
	await frames(5)
	check("E is following", e.is_following)
	# 玩家往右挪 120px：E 以跟随速度飞过去，重新对准后接着开火。
	_put_player(520.0)
	var shots := [0]
	e.shot_fired.connect(func(): shots[0] += 1)
	await frames(30)
	check("E flies toward the player at its follow speed", is_equal_approx(e.velocity.x, e.follow_speed) and e.facing == 1, "vx %.1f" % e.velocity.x)
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("E ends up right above the player", absf(e.global_position.x - 520.0) <= e.below_width, "x=%.1f" % e.global_position.x)
	check("and fires again once it is above", shots[0] > 0, str(shots[0]))


func test_e_bullets_pass_through_platforms() -> void:
	# 玩家站在 Platform1（单向，x 160..256，y 256..272）正下方，E 在它上空。
	var e := await _setup_flyer(Vector2(208, ALTITUDE))
	e.move_speed = 0.0
	_put_player(208.0)
	var hit := false
	for i in 120:
		await tree.physics_frame
		if player.health < player.max_health:
			hit = true
			break
	check("E sees and hits a player under a one-way platform", hit)


func test_solid_blocks_hide_the_player_from_e() -> void:
	# 玩家趴在矮通道（CrawlBlock，实心，x 592..352，y 240..148）里，E 在正上方。
	var e := await _setup_flyer(Vector2(324, ALTITUDE))
	e.move_speed = 0.0
	player.global_position = Vector2(648, 304)
	player._set_crouching(true) # 直接趴下放进去，站着会和顶板重叠
	Input.action_press("crouch")
	var shots := 0
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		shots += bullets(16).size()
	check("E cannot see a player inside the tunnel", not e.is_following)
	check("so it never fires", shots == 0, str(shots))


func test_e_gives_up_after_losing_the_player() -> void:
	var e := await _setup_flyer(Vector2(400, ALTITUDE))
	_put_player(400.0)
	await frames(5)
	check("E is following", e.is_following)
	_put_player(1120.0) # 一下子跑出 follow_range
	var gave_up_at := -1
	for i in 180:
		await tree.physics_frame
		if not e.is_following:
			gave_up_at = i
			break
	check("E gives up after its 1.5s memory", gave_up_at >= 85 and gave_up_at <= 95, "after %d frames" % gave_up_at)
	var x_at_give_up := e.global_position.x
	await frames(30)
	check("then patrols again at the normal speed", is_equal_approx(absf(e.velocity.x), e.move_speed), "%.1f" % absf(e.velocity.x))
	check("around where it lost the player, not back at its spawn", absf(e._patrol_center_x - x_at_give_up) < 1.0)


func test_player_can_shoot_e_down() -> void:
	var e := await _setup_flyer(Vector2(120, ALTITUDE))
	_put_player(120.0)
	var deaths := []
	e.died.connect(func(): deaths.append(true))
	Input.action_press("aim_up")
	Input.action_press("shoot")
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not deaths.is_empty():
			break
	check("aiming up and firing brings E down", deaths.size() == 1)
