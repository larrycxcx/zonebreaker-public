extends GameTest
## Pad controls: every action has a pad binding, the button layout follows the convention, and simulated pad events (Input.parse_input_event)
## measure dead zones, full-speed movement, and diagonal pushes not triggering prone / aiming by accident — behaviour only sticks have.
##
## Button convention (Xbox layout, the same positions on a PS pad):
## move left stick / d-pad left and right · jump A · fire RT · switch weapon X · aim up left stick up / d-pad up · aim down left stick down / d-pad down
## · prone LT · run LB

const OPEN_X := 400.0


## Simulated input events are only processed when the next main loop iteration starts. If the previous frame stalled, this iteration runs several physics frames in a row to catch up,
## and a case sending an event during the catch-up and checking after a few frames may find it not processed yet — the A jump failed intermittently like this the first time this suite ran
## (an artificial stall reproduces it 20 times out of 20). So flush right after sending, making it take effect on the current physics frame for stable results.
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


## Sticks and triggers back to centre, every button released. Called at the start and end of every case so pad state does not leak into other cases.
func joy_neutral() -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		joy_axis(axis, 0.0)
	for button in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		joy_button(button, false)


func start() -> void:
	joy_neutral()
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


func has_button(action: StringName, index: JoyButton) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton and e.button_index == index)


## Actions only used in the UI and unreachable while playing (Godot's own ui_*, plus our menu_*).
func _menu_only(action: StringName) -> bool:
	var name := String(action)
	return name.begins_with("ui_") or name.begins_with("menu_") or name.begins_with("p2_menu_")


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
	check("shoot: RT", has_axis("shoot", JOY_AXIS_TRIGGER_RIGHT, true))
	check("X is no longer a fire button", not has_button("shoot", JOY_BUTTON_X))
	check("switch weapon: RB", has_button("switch_weapon", JOY_BUTTON_RIGHT_SHOULDER))
	# Weapon switching moved to the index finger (RB) so the thumb never leaves A; X is left free for future actions.
	# **While playing** X must have no action — deleting in menus (`menu_delete`) uses it, but that is a screen only reached after a stage,
	# which is something else entirely from "pressing X by accident mid-fight".
	var game_actions := InputMap.get_actions().filter(func(a): return not _menu_only(a))
	check("X is free during play", game_actions.all(func(a): return not has_button(a, JOY_BUTTON_X)), str(game_actions.filter(func(a): return has_button(a, JOY_BUTTON_X))))
	check("and the menu's delete is what took it", has_button(&"menu_delete", JOY_BUTTON_X))
	check("ultimate: Y", has_button("ultimate", JOY_BUTTON_Y))
	check("aim up: left stick up / d-pad up", has_axis("aim_up", JOY_AXIS_LEFT_Y, false) and has_button("aim_up", JOY_BUTTON_DPAD_UP))
	check("aim down: left stick down / d-pad down", has_axis("aim_down", JOY_AXIS_LEFT_Y, true) and has_button("aim_down", JOY_BUTTON_DPAD_DOWN))
	check("lie down: LT", has_axis("crouch", JOY_AXIS_TRIGGER_LEFT, true))
	check("lying down is no longer on the stick or d-pad", not has_axis("crouch", JOY_AXIS_LEFT_Y, true) and not has_button("crouch", JOY_BUTTON_DPAD_DOWN))
	check("sprint: LB", has_button("sprint", JOY_BUTTON_LEFT_SHOULDER) and not has_axis("sprint", JOY_AXIS_TRIGGER_LEFT, true))
	check("stick needs a 50% push to aim up or down", InputMap.action_get_deadzone("aim_up") == 0.5 and InputMap.action_get_deadzone("aim_down") == 0.5)


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
	check("a 90% push walks at full speed", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	joy_axis(JOY_AXIS_LEFT_X, -0.45)
	await frames(40)
	check("same the other way", is_equal_approx(player.velocity.x, -player.move_speed), "%.1f" % player.velocity.x)
	joy_neutral()


func test_small_stick_drift_is_ignored() -> void:
	await start()
	var x0 := player.global_position.x
	joy_axis(JOY_AXIS_LEFT_X, 0.2) # Within the 0.3 dead zone: drift from a stick not returning to centre exactly
	await frames(30)
	check("a 40% push does not move the player", absf(player.global_position.x - x0) < 0.5, "moved %.2f" % (player.global_position.x - x0))
	joy_neutral()


func test_dpad_moves() -> void:
	await start()
	joy_button(JOY_BUTTON_DPAD_RIGHT, true)
	await frames(30)
	check("d-pad right walks at full speed", is_equal_approx(player.velocity.x, player.move_speed), "%.1f" % player.velocity.x)
	joy_neutral()


func test_stick_down_aims_down_only_past_half() -> void:
	await start()
	joy_axis(JOY_AXIS_LEFT_Y, 0.4)
	await frames(5)
	check("a 80% push down does not aim down", player.aim == Player.Aim.FORWARD, str(player.aim))
	joy_axis(JOY_AXIS_LEFT_Y, 0.8)
	await frames(5)
	check("an 160% push down aims down (and does not lie down)", player.aim == Player.Aim.DIAGONAL_DOWN and not player.is_crouching, str(player.aim))
	joy_neutral()
	await frames(5)
	joy_button(JOY_BUTTON_DPAD_DOWN, true)
	await frames(5)
	check("d-pad down aims down too", player.aim == Player.Aim.DIAGONAL_DOWN, str(player.aim))
	joy_neutral()


func test_lt_lies_down() -> void:
	await start()
	joy_axis(JOY_AXIS_TRIGGER_LEFT, 0.3)
	await frames(5)
	check("a light LT squeeze does not lie down", not player.is_crouching)
	joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames(5)
	check("pulling LT lies down", player.is_crouching)
	joy_neutral()
	await frames(5)
	check("releasing LT stands up", not player.is_crouching)

func test_running_with_a_slightly_diagonal_stick() -> void:
	# Pushing right, the finger inevitably adds a little up or down: that must not suddenly make you lie down or raise the gun.
	await start()
	joy_axis(JOY_AXIS_LEFT_X, 0.9)
	joy_axis(JOY_AXIS_LEFT_Y, 0.4)
	await frames(20)
	check("slightly down-right keeps walking upright", not player.is_crouching and is_equal_approx(player.velocity.x, player.move_speed), "crouching %s, vx %.1f" % [player.is_crouching, player.velocity.x])
	joy_axis(JOY_AXIS_LEFT_Y, -0.4)
	await frames(5)
	check("slightly up-right does not raise the gun", art(player, "Gun").visible and not art(player, "GunUp").visible)
	joy_neutral()


func test_stick_up_and_rt_shoots_straight_up() -> void:
	await start()
	player.current_slot().cooldown_left = 0.0
	joy_axis(JOY_AXIS_LEFT_Y, -0.8)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(2)
	var shots := bullets(4)
	check("stick up + RT fires one bullet", shots.size() == 1, str(shots.size()))
	check("straight up", shots.size() == 1 and shots[0].direction == Vector2.UP)
	joy_neutral()


func test_rt_fires_sideways() -> void:
	await start()
	player.current_slot().cooldown_left = 0.0
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(2)
	check("RT fires sideways", bullets(4).size() == 1 and bullets(4)[0].direction == Vector2.RIGHT, str(bullets(4).size()))
	joy_neutral()


func test_rb_switches_weapons() -> void:
	await start()
	check("starts with the rifle", player.current_weapon == 0)
	joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(2)
	check("RB switches to the next weapon", player.current_weapon == 1)
	joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames(2)
	joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(2)
	check("pressing RB again cycles back", player.current_weapon == 0)
	check("switching does not fire anything", bullets(4).is_empty())
	joy_neutral()


func test_rb_switches_while_firing_and_jumping() -> void:
	# The reason weapon switching moved to the index finger: with the thumb on A to jump and the index finger on RT to fire, you can still switch weapons
	await start()
	joy_button(JOY_BUTTON_A, true)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(6)
	check("setup: jumping and firing", not player.is_on_floor() and not bullets(4).is_empty())
	joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(2)
	check("RB still switches mid-air while holding fire", player.current_weapon == 1)
	joy_neutral()


func test_lb_sprints() -> void:
	await start()
	player.global_position = Vector2(740, 304) # The empty ground right of the crawl passage, room enough to run
	joy_axis(JOY_AXIS_LEFT_X, 1.0)
	joy_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await frames(20)
	check("LB + stick sprints", player.is_sprinting and is_equal_approx(player.velocity.x, player.move_speed * player.sprint_speed_scale), "%.1f" % player.velocity.x)
	joy_neutral()


func test_cannot_fire_while_lying_down_on_the_gamepad() -> void:
	await start()
	joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames(5)
	player.current_slot().cooldown_left = 0.0
	# Hold LT to lie down, then push the stick: crawling prone, no firing.
	joy_axis(JOY_AXIS_LEFT_X, 0.9)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(20)
	check("crawling with the stick: RT does not fire", player.is_crouching and bullets(4).is_empty(), str(bullets(4).size()))
	# Stick back to centre: lying still, still no firing.
	joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await frames(20)
	check("lying still: RT does not fire either", player.is_crouching and bullets(4).is_empty(), str(bullets(4).size()))
	# Release LT to stand up: you can fire right away.
	joy_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await frames(10)
	check("RT fires again once standing", not player.is_crouching and not bullets(4).is_empty(), str(bullets(4).size()))
	joy_neutral()
