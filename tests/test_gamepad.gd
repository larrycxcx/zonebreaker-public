extends GameTest
## 手柄操作：每个动作都有手柄绑定，按键分配符合约定，并用模拟的手柄事件（Input.parse_input_event）
## 实测死区、全速移动、斜推不误触发趴下/瞄准等只有摇杆才有的行为。
##
## 按键约定（Xbox 布局，PS 手柄对应位置相同）：
##   移动 左摇杆/十字键左右 · 跳跃 A · 开火 X 或 RT · 趴下 左摇杆下/十字键下 · 向上瞄准 左摇杆上/十字键上 · 奔跑 LT

const OPEN_X := 200.0


## 模拟的输入事件默认要等下一轮主循环开始才被处理。如果上一帧卡了一下，这一轮主循环会连续补跑好几个物理帧，
## 用例在补帧期间发出事件、只等几帧就检查，事件可能还没被处理——第一次跑这组用例时 A 键跳跃就这样偶发失败过
## （人为制造卡顿可以 10 次复现 10 次）。所以发完事件立刻 flush，让它在当前物理帧就生效，结果稳定。
func joy_button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## 摇杆、扳机回中，按钮全部松开。每条用例开头结尾都调用，免得手柄状态带进别的用例。
func joy_neutral() -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		joy_axis(axis, 0.0)
	for button in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		joy_button(button, false)


func start() -> void:
	joy_neutral()
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)


func has_button(action: StringName, index: JoyButton) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton and e.button_index == index)


func has_axis(action: StringName, axis: JoyAxis, positive: bool) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadMotion and e.axis == axis and (e.axis_value > 0.0) == positive)


func test_every_action_works_on_both_keyboard_and_gamepad() -> void:
	await reset_scene()
	for action in ACTIONS:
		var events := InputMap.action_get_events(action)
		check("%s has a keyboard binding" % action, events.any(func(e): return e is InputEventKey))
		check("%s has a gamepad binding" % action, events.any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion))


func test_gamepad_layout() -> void:
	await reset_scene()
	check("move left: left stick / d-pad left", has_axis("move_left", JOY_AXIS_LEFT_X, false) and has_button("move_left", JOY_BUTTON_DPAD_LEFT))
	check("move right: left stick / d-pad right", has_axis("move_right", JOY_AXIS_LEFT_X, true) and has_button("move_right", JOY_BUTTON_DPAD_RIGHT))
	check("jump: A", has_button("jump", JOY_BUTTON_A))
	check("shoot: X or RT", has_button("shoot", JOY_BUTTON_X) and has_axis("shoot", JOY_AXIS_TRIGGER_RIGHT, true))
	check("crouch: left stick down / d-pad down", has_axis("crouch", JOY_AXIS_LEFT_Y, true) and has_button("crouch", JOY_BUTTON_DPAD_DOWN))
	check("aim up: left stick up / d-pad up", has_axis("aim_up", JOY_AXIS_LEFT_Y, false) and has_button("aim_up", JOY_BUTTON_DPAD_UP))
	check("sprint: LT", has_axis("sprint", JOY_AXIS_TRIGGER_LEFT, true))
	check("stick needs a 50% push to crouch or aim", InputMap.action_get_deadzone("crouch") == 0.5 and InputMap.action_get_deadzone("aim_up") == 0.5)


func test_a_jumps() -> void:
	await start()
	joy_button(JOY_BUTTON_A, true)
	await frames(3)
	check("A makes the player jump", player.velocity.y < 0.0 and not player.is_on_floor(), str(player.velocity))
	joy_neutral()


func test_half_a_stick_push_walks_at_full_speed() -> void:
	await start()
	joy_axis(JOY_AXIS_LEFT_X, 0.45)
	await frames(30)
	check("a 45% push walks at full speed", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	joy_axis(JOY_AXIS_LEFT_X, -0.45)
	await frames(40)
	check("same the other way", is_equal_approx(player.velocity.x, -player.move_speed), "%.1f" % player.velocity.x)
	joy_neutral()


func test_small_stick_drift_is_ignored() -> void:
	await start()
	var x0 := player.global_position.x
	joy_axis(JOY_AXIS_LEFT_X, 0.2) # 死区 0.3 以内：摇杆回中不准时的漂移
	await frames(30)
	check("a 20% push does not move the player", absf(player.global_position.x - x0) < 0.5, "moved %.2f" % (player.global_position.x - x0))
	joy_neutral()


func test_dpad_moves() -> void:
	await start()
	joy_button(JOY_BUTTON_DPAD_RIGHT, true)
	await frames(30)
	check("d-pad right walks at full speed", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	joy_neutral()


func test_stick_down_crouches_only_past_half() -> void:
	await start()
	joy_axis(JOY_AXIS_LEFT_Y, 0.4)
	await frames(5)
	check("a 40% push down does not lie down", not player.is_crouching)
	joy_axis(JOY_AXIS_LEFT_Y, 0.8)
	await frames(5)
	check("an 80% push down lies down", player.is_crouching)
	joy_neutral()
	await frames(5)
	joy_button(JOY_BUTTON_DPAD_DOWN, true)
	await frames(5)
	check("d-pad down lies down too", player.is_crouching)
	joy_neutral()


func test_running_with_a_slightly_diagonal_stick() -> void:
	# 往右推的时候手指难免带一点上下：不能因此突然趴下或举枪。
	await start()
	joy_axis(JOY_AXIS_LEFT_X, 0.9)
	joy_axis(JOY_AXIS_LEFT_Y, 0.4)
	await frames(20)
	check("slightly down-right keeps walking upright", not player.is_crouching and is_equal_approx(player.velocity.x, player.move_speed), "crouching %s, vx %.1f" % [player.is_crouching, player.velocity.x])
	joy_axis(JOY_AXIS_LEFT_Y, -0.4)
	await frames(5)
	check("slightly up-right does not raise the gun", player._gun.visible and not player._gun_up.visible)
	joy_neutral()


func test_stick_up_and_x_shoots_straight_up() -> void:
	await start()
	player._fire_timer = 0.0
	joy_axis(JOY_AXIS_LEFT_Y, -0.8)
	joy_button(JOY_BUTTON_X, true)
	await frames(2)
	var shots := bullets(4)
	check("stick up + X fires one bullet", shots.size() == 1, str(shots.size()))
	check("straight up", shots.size() == 1 and shots[0].direction == Vector2.UP)
	joy_neutral()


func test_x_and_rt_both_fire_sideways() -> void:
	await start()
	player._fire_timer = 0.0
	joy_button(JOY_BUTTON_X, true)
	await frames(2)
	joy_button(JOY_BUTTON_X, false)
	check("X fires sideways", bullets(4).size() == 1 and bullets(4)[0].direction == Vector2.RIGHT)
	for b in bullets(4):
		b.free()
	await frames(15)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(2)
	check("RT fires sideways too", bullets(4).size() == 1 and bullets(4)[0].direction == Vector2.RIGHT, str(bullets(4).size()))
	joy_neutral()


func test_lt_sprints() -> void:
	await start()
	player.global_position = Vector2(370, 152) # 矮通道右边的空地，够跑
	joy_axis(JOY_AXIS_LEFT_X, 1.0)
	joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames(20)
	check("LT + stick sprints", player.is_sprinting and is_equal_approx(player.velocity.x, player.move_speed * player.sprint_speed_scale), "%.1f" % player.velocity.x)
	joy_neutral()


func test_prone_shooting_rules_on_the_gamepad() -> void:
	await start()
	joy_axis(JOY_AXIS_LEFT_Y, 0.8)
	await frames(5)
	player._fire_timer = 0.0
	# 摇杆往右下：趴着爬行，不能开枪。
	joy_axis(JOY_AXIS_LEFT_X, 0.9)
	joy_button(JOY_BUTTON_X, true)
	await frames(20)
	check("crawling with the stick: X does not fire", player.is_crouching and bullets(4).is_empty(), str(bullets(4).size()))
	# 摇杆只往下：趴着不动，可以开枪。
	joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await frames(5)
	check("lying still with the stick: X fires", player.is_crouching and bullets(4).size() >= 1, str(bullets(4).size()))
	joy_neutral()
