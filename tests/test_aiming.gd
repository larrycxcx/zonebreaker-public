extends GameTest
## Contra-style aiming: W + left/right is diagonally up while walking, W alone straight up on the spot; S + left/right diagonally down while walking, S alone diagonally down on the ground and straight down in the air;
## W and S together cancel out; always level while prone (Ctrl / LT). Also confirms the keys: S/↓ aims down, Ctrl/LT goes prone, Alt/LB runs.

const OPEN_X := 400.0


func start(x := OPEN_X, y := 304.0) -> void:
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


## Hold these keys for some frames and return the aim direction.
func aim_with(actions: Array, hold := 3) -> Player.Aim:
	press(actions)
	await frames(hold)
	var result := player.aim
	release(actions)
	await frames(2)
	return result


## Fire one shot and return that bullet (null if none came out).
func fire_once() -> Bullet:
	player.current_slot().cooldown_left = 0.0
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


# ---------------------------------------------------------------- Keys

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


# ---------------------------------------------------------------- Aiming rules

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
		Player.Aim.FORWARD: art(player, "Gun"), Player.Aim.UP: art(player, "GunUp"),
		Player.Aim.DIAGONAL_UP: art(player, "GunDiagonalUp"), Player.Aim.DIAGONAL_DOWN: art(player, "GunDiagonalDown"),
	}
	for setup in [[], ["aim_up"], ["aim_up", "move_right"], ["aim_down"]]:
		press(setup)
		await frames(2)
		var shown := guns.keys().filter(func(a): return guns[a].visible)
		check("exactly the %s gun is shown for %s" % [Player.Aim.keys()[player.aim], setup], shown == [player.aim] and not art(player, "GunDown").visible, str(shown))
		release(setup)
		await frames(2)


# ---------------------------------------------------------------- Bullets

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
		player.global_position = Vector2(OPEN_X, 304)
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
			# The muzzle is outside the body, on the side the bullet flies to.
			check("%s: leaves from the side it flies toward" % c[2], offset.dot(c[1]) > 12.0, str(offset))
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
		check("from the gun at the hip, beside the body", bullet.global_position.y > player.global_position.y and absf(bullet.global_position.x - player.global_position.x) < 20.0, str(bullet.global_position - player.global_position))


func test_walking_while_firing_diagonally() -> void:
	await start()
	press(["aim_up", "move_right", "shoot"])
	player.current_slot().cooldown_left = 0.0
	var directions := {}
	for i in 30:
		await tree.physics_frame
		for b in bullets(4):
			directions[b.direction.snappedf(0.01)] = true
	check("keeps walking at full speed while firing diagonally", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	check("every shot goes diagonally up", directions.size() == 1 and directions.keys()[0].x > 0.0 and directions.keys()[0].y < 0.0, str(directions.keys()))


func test_diagonal_down_on_flat_ground_hits_the_ground() -> void:
	# Like Contra: firing diagonally down on flat ground, the muzzle is only a few pixels above the floor and the bullet hits the ground at once.
	await start()
	Input.action_press("aim_down")
	await frames(2)
	var bullet := await fire_once()
	check("the bullet is fired", bullet != null)
	await frames(4)
	check("and hits the ground right away", bullet == null or not is_instance_valid(bullet))
	check("with an impact sound", events.has(&"bullet_impact"))


# ---------------------------------------------------------------- In action

func test_diagonal_up_hits_a_flyer() -> void:
	await reset_scene(true)
	keep_only_enemies(["FlyerE"])
	var flyer: EnemyFlyer = main.get_node("Enemies/FlyerE")
	player.global_position = Vector2(200, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	# Diagonally up at 90°: the muzzle is up and right of the body centre at (18, -18); rising 198px to E's height means going 198px right.
	flyer.set_anchor(Vector2(200 + 18 + 198, 88))
	flyer.move_speed = 0.0
	flyer.follow_speed = 0.0 # It flies over when it sees the player: freeze it so the diagonal trajectory can be tested
	flyer.wave_amplitude = 0.0
	var deaths := []
	flyer.died.connect(func(): deaths.append(true))
	# Each shot goes back to the start position and fires holding W + right (diagonally up while walking); one frame of walking only moves 1.5px, which does not affect the aim line.
	for shot in 4:
		player.global_position = Vector2(200, 304)
		player.velocity = Vector2.ZERO
		press(["aim_up", "move_right"])
		player.current_slot().cooldown_left = 0.0
		Input.action_press("shoot")
		await frames(1)
		release(["shoot", "move_right", "aim_up"])
		await frames(40)
	check("two diagonal shots bring E down", deaths.size() == 1)


func test_shooting_down_through_a_platform() -> void:
	# The player stands on Platform1 (one-way, x 160..128, top y=256) and jumps to fire down, with patroller A on the ground right below the platform.
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(208, 304)
	walker.move_speed = 0.0
	player.global_position = Vector2(208, 240)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("standing on the platform", player.is_on_floor() and player.global_position.y < 250.0, str(player.global_position))
	var hits := []
	walker.died.connect(func(): hits.append(true))
	var health_before := walker.health
	Input.action_press("jump")
	await frames(6)
	Input.action_press("aim_down")
	player.current_slot().cooldown_left = 0.0
	Input.action_press("shoot")
	for i in 40:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not hits.is_empty():
			break
	check("straight-down shots pass the platform and hit the walker below", not hits.is_empty() or (is_instance_valid(walker) and walker.health < health_before))


func test_diagonal_down_from_a_ledge() -> void:
	# The player stands on the right edge of Platform1 and fires diagonally down to the right, with the patroller on the ground below to the right.
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	player.global_position = Vector2(240, 240)
	player.velocity = Vector2.ZERO
	await frames(10)
	# The muzzle is at (258, 248); going down at 90° to the patroller's body centre line at y=306 takes 58px.
	walker.global_position = Vector2(258 + 58, 306)
	walker.move_speed = 0.0
	walker.facing = 1
	walker._apply_facing()
	var health_before := walker.health
	player.facing = 1
	player._visual.scale.x = 1
	Input.action_press("aim_down")
	await frames(2)
	player.current_slot().cooldown_left = 0.0
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
