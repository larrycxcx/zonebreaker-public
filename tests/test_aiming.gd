extends GameTest
## 魂斗罗式 8 方向瞄准：W + 左右边走边斜上，只按 W 原地正上；S + 左右边走边斜下，只按 S 地面上斜下、空中正下；
## W、S 同时按抵消；趴下（Ctrl / LT）时一律水平。另外确认按键：S/↓ 是向下瞄准，Ctrl/LT 趴下，Alt/LB 奔跑。

const OPEN_X := 200.0


func start(x := OPEN_X, y := 152.0) -> void:
	await reset_scene()
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	await frames(10)


func press(actions: Array) -> void:
	for action in actions:
		Input.action_press(action)


func release(actions: Array) -> void:
	for action in actions:
		Input.action_release(action)


## 按住这些键若干帧，返回瞄准方向。
func aim_with(actions: Array, hold := 3) -> Player.Aim:
	press(actions)
	await frames(hold)
	var result := player.aim
	release(actions)
	await frames(2)
	return result


## 开一枪，返回这颗子弹（没开出来返回 null）。
func fire_once() -> Bullet:
	player._primary.cooldown_left = 0.0
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("shoot")
	var shots := bullets(4)
	return shots[0] if shots.size() == 1 else null


func key_event(physical_keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# ---------------------------------------------------------------- 按键

func test_keyboard_layout() -> void:
	await reset_scene()
	var down_keys := keyboard_keys("aim_down")
	check("aim down: S and Down", down_keys.size() == 2 and down_keys.has(KEY_S) and down_keys.has(KEY_DOWN), str(down_keys))
	check("lie down: Ctrl only", keyboard_keys("crouch") == [KEY_CTRL], str(keyboard_keys("crouch")))
	check("sprint: Alt", keyboard_keys("sprint") == [KEY_ALT], str(keyboard_keys("sprint")))


func test_real_s_and_ctrl_keys() -> void:
	await start()
	key_event(KEY_S, true)
	await frames(3)
	check("pressing S aims down instead of lying down", player.aim == Player.Aim.DIAGONAL_DOWN and not player.is_crouching, str(player.aim))
	key_event(KEY_S, false)
	key_event(KEY_CTRL, true)
	await frames(3)
	check("pressing Ctrl lies down", player.is_crouching)
	key_event(KEY_CTRL, false)
	await frames(3)
	check("releasing Ctrl stands up", not player.is_crouching)


# ---------------------------------------------------------------- 瞄准规则

func test_aim_on_the_ground() -> void:
	await start()
	check("no aim keys: forward", await aim_with([]) == Player.Aim.FORWARD)
	check("W standing still: straight up", await aim_with(["aim_up"]) == Player.Aim.UP)
	check("W + move: diagonal up", await aim_with(["aim_up", "move_right"]) == Player.Aim.DIAGONAL_UP)
	check("S standing still: diagonal down", await aim_with(["aim_down"]) == Player.Aim.DIAGONAL_DOWN)
	check("S + move: diagonal down", await aim_with(["aim_down", "move_left"]) == Player.Aim.DIAGONAL_DOWN)
	check("W and S together cancel out", await aim_with(["aim_up", "aim_down"]) == Player.Aim.FORWARD)


func test_aim_in_the_air() -> void:
	await start()
	Input.action_press("jump")
	await frames(4)
	check("jumping", not player.is_on_floor())
	Input.action_press("aim_down")
	await frames(2)
	check("S in the air: straight down", player.aim == Player.Aim.DOWN, str(player.aim))
	Input.action_press("move_right")
	await frames(2)
	check("S + move in the air: diagonal down", player.aim == Player.Aim.DIAGONAL_DOWN, str(player.aim))
	release(["aim_down", "move_right"])
	Input.action_press("aim_up")
	await frames(2)
	check("W in the air: straight up", player.aim == Player.Aim.UP, str(player.aim))


func test_lying_down_ignores_aiming() -> void:
	await start()
	Input.action_press("crouch")
	await frames(3)
	check("lying down + W: forward", await aim_with(["aim_up"]) == Player.Aim.FORWARD)
	check("lying down + S: forward", await aim_with(["aim_down"]) == Player.Aim.FORWARD)


func test_gun_follows_the_aim() -> void:
	await start()
	var guns := {
		Player.Aim.FORWARD: player._gun, Player.Aim.UP: player._gun_up, Player.Aim.DIAGONAL_UP: player._gun_diagonal_up,
		Player.Aim.DIAGONAL_DOWN: player._gun_diagonal_down,
	}
	for setup in [[], ["aim_up"], ["aim_up", "move_right"], ["aim_down"]]:
		press(setup)
		await frames(2)
		var shown := guns.keys().filter(func(a): return guns[a].visible)
		check("exactly the %s gun is shown for %s" % [Player.Aim.keys()[player.aim], setup], shown == [player.aim] and not player._gun_down.visible, str(shown))
		release(setup)
		await frames(2)


# ---------------------------------------------------------------- 子弹

func test_bullet_directions_and_muzzles() -> void:
	await start()
	var diagonal := 1.0 / sqrt(2.0)
	var cases := [
		[[], Vector2(1, 0), "forward"],
		[["aim_up"], Vector2(0, -1), "up"],
		[["aim_up", "move_right"], Vector2(diagonal, -diagonal), "diagonal up"],
		[["aim_down", "move_right"], Vector2(diagonal, diagonal), "diagonal down"],
		[["aim_up", "move_left"], Vector2(-diagonal, -diagonal), "diagonal up, facing left"],
	]
	for c in cases:
		player.global_position = Vector2(OPEN_X, 152)
		press(c[0])
		await frames(2)
		var center := player.global_position
		var bullet := await fire_once()
		release(c[0])
		check("%s: one bullet" % c[2], bullet != null)
		if bullet != null:
			check("%s: flies %s" % [c[2], c[1]], bullet.direction.is_equal_approx(c[1]), str(bullet.direction))
			check("%s: drawn along its path" % c[2], is_equal_approx(bullet.rotation, c[1].angle()), "%.3f" % bullet.rotation)
			var offset: Vector2 = bullet.global_position - center
			# 出膛点在身体外、朝子弹飞的那一边。
			check("%s: leaves from the side it flies toward" % c[2], offset.dot(c[1]) > 6.0, str(offset))
			bullet.free()
		await frames(12)


func test_straight_down_from_the_air() -> void:
	await start()
	Input.action_press("jump")
	await frames(6)
	Input.action_press("aim_down")
	await frames(1)
	var bullet := await fire_once()
	check("S + J in the air fires one bullet", bullet != null)
	if bullet != null:
		check("straight down", bullet.direction == Vector2.DOWN)
		check("from under the feet", bullet.global_position.y > player.global_position.y + 8.0 and absf(bullet.global_position.x - player.global_position.x) < 2.0, str(bullet.global_position - player.global_position))


func test_walking_while_firing_diagonally() -> void:
	await start()
	press(["aim_up", "move_right", "shoot"])
	player._primary.cooldown_left = 0.0
	var directions := {}
	for i in 30:
		await tree.physics_frame
		for b in bullets(4):
			directions[b.direction.snappedf(0.01)] = true
	check("keeps walking at full speed while firing diagonally", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	check("every shot goes diagonally up", directions.size() == 1 and directions.keys()[0].x > 0.0 and directions.keys()[0].y < 0.0, str(directions.keys()))


func test_diagonal_down_on_flat_ground_hits_the_ground() -> void:
	# 和魂斗罗一样：在平地上斜下开枪，枪口离地面只有几个像素，子弹马上打在地上。
	await start()
	Input.action_press("aim_down")
	await frames(2)
	var bullet := await fire_once()
	check("the bullet is fired", bullet != null)
	await frames(4)
	check("and hits the ground right away", bullet == null or not is_instance_valid(bullet))
	check("with an impact sound", events.has(&"bullet_impact"))


# ---------------------------------------------------------------- 实战

func test_diagonal_up_hits_a_flyer() -> void:
	await reset_scene(true)
	keep_only_enemies(["FlyerE"])
	var flyer: EnemyFlyer = main.get_node("Enemies/FlyerE")
	player.global_position = Vector2(100, 152)
	player.velocity = Vector2.ZERO
	await frames(5)
	# 斜上 45°：出膛点在身体中心右上 (9, -9)，要升 99px 到 E 的高度，就得往右 99px。
	flyer.set_anchor(Vector2(100 + 9 + 99, 44))
	flyer.move_speed = 0.0
	flyer.wave_amplitude = 0.0
	var deaths := []
	flyer.died.connect(func(): deaths.append(true))
	# 每发都回到原位按住 W + 右开一枪（边走边斜上）；走一帧只挪 1.5px，不影响瞄准线。
	for shot in 2:
		player.global_position = Vector2(100, 152)
		player.velocity = Vector2.ZERO
		press(["aim_up", "move_right"])
		player._primary.cooldown_left = 0.0
		Input.action_press("shoot")
		await frames(1)
		release(["shoot", "move_right", "aim_up"])
		await frames(40)
	check("two diagonal shots bring E down", deaths.size() == 1)


func test_shooting_down_through_a_platform() -> void:
	# 玩家站在 Platform1（单向，x 80..128，顶面 y=128）上起跳往下打，巡逻兵 A 在平台正下方的地面上。
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(104, 153)
	walker.move_speed = 0.0
	player.global_position = Vector2(104, 120)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("standing on the platform", player.is_on_floor() and player.global_position.y < 125.0, str(player.global_position))
	var hits := []
	walker.died.connect(func(): hits.append(true))
	var health_before := walker.health
	Input.action_press("jump")
	await frames(6)
	Input.action_press("aim_down")
	player._primary.cooldown_left = 0.0
	Input.action_press("shoot")
	for i in 40:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not hits.is_empty():
			break
	check("straight-down shots pass the platform and hit the walker below", not hits.is_empty() or (is_instance_valid(walker) and walker.health < health_before))


func test_diagonal_down_from_a_ledge() -> void:
	# 玩家站在 Platform1 右边缘朝右斜下打，巡逻兵在右下方的地面上。
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	player.global_position = Vector2(120, 120)
	player.velocity = Vector2.ZERO
	await frames(10)
	# 出膛点在 (129, 124)，45° 往下到巡逻兵身体中线 y=153 要走 29px。
	walker.global_position = Vector2(129 + 29, 153)
	walker.move_speed = 0.0
	walker.facing = 1
	walker._apply_facing()
	var health_before := walker.health
	player.facing = 1
	player._visual.scale.x = 1
	Input.action_press("aim_down")
	await frames(2)
	player._primary.cooldown_left = 0.0
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	await frames(20)
	check("a diagonal-down shot from a ledge hits the enemy below", not is_instance_valid(walker) or walker.health < health_before)


func test_gamepad_diagonal_aim() -> void:
	await start()
	var stick := func(x: float, y: float) -> void:
		for pair in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
			var event := InputEventJoypadMotion.new()
			event.device = 0
			event.axis = pair[0]
			event.axis_value = pair[1]
			Input.parse_input_event(event)
		Input.flush_buffered_events()
	stick.call(0.75, -0.75)
	await frames(3)
	check("stick up-right: walk and aim diagonally up", player.aim == Player.Aim.DIAGONAL_UP and player.velocity.x > 0.0, "%s %.1f" % [player.aim, player.velocity.x])
	stick.call(-0.75, 0.75)
	await frames(3)
	check("stick down-left: walk and aim diagonally down", player.aim == Player.Aim.DIAGONAL_DOWN and player.facing == -1 and not player.is_crouching, str(player.aim))
	stick.call(0.0, 0.0)
