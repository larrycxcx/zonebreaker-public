extends GameTest
## 奔跑与体力：加速、消耗、耗尽后的恢复门槛、停下后自动回复、HUD 体力条。

## 矮通道右边到右墙之间有 280px 的空地，够跑一段测速度。
const RUNWAY_X := 370.0


func start_on_runway() -> void:
	await reset_scene()
	player.global_position = Vector2(RUNWAY_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)


func fill_width() -> float:
	return (main.get_node("HUD/StaminaBar/Fill") as ColorRect).size.x


func bar_width() -> float:
	return (main.get_node("HUD/StaminaBar") as ColorRect).size.x


func test_starts_with_full_stamina() -> void:
	await start_on_runway()
	check("stamina starts full", player.stamina == player.max_stamina, "%.1f / %.1f" % [player.stamina, player.max_stamina])
	check("hud stamina bar is full", fill_width() == bar_width(), "%.0f / %.0f" % [fill_width(), bar_width()])
	check("not sprinting at rest", not player.is_sprinting and not player.is_exhausted())


func test_sprinting_is_faster() -> void:
	await start_on_runway()
	Input.action_press("move_right")
	await frames(30)
	var walking := absf(player.velocity.x)
	Input.action_press("sprint")
	await frames(20)
	var sprinting := absf(player.velocity.x)
	check("walk speed is the normal speed", is_equal_approx(walking, player.move_speed), "%.1f" % walking)
	check("sprint is 120% of normal speed", is_equal_approx(sprinting, player.move_speed * 1.2), "%.1f" % sprinting)
	check("is_sprinting is set", player.is_sprinting)

	Input.action_release("sprint")
	await frames(20)
	check("back to normal speed when released", is_equal_approx(absf(player.velocity.x), player.move_speed), "%.1f" % absf(player.velocity.x))


func test_sprint_drains_stamina_only_while_moving() -> void:
	await start_on_runway()
	# 原地按住奔跑键：不算奔跑，不耗体力。
	Input.action_press("sprint")
	await frames(30)
	check("holding sprint while standing still costs nothing", player.stamina == player.max_stamina and not player.is_sprinting, "%.1f" % player.stamina)

	Input.action_press("move_right")
	await frames(30) # 0.5 秒 × 35/秒 ≈ 17.5
	var spent := player.max_stamina - player.stamina
	check("sprinting drains stamina at ~35/s", absf(spent - 17.5) < 1.5, "spent %.1f" % spent)
	var expected_width := roundf(bar_width() * player.stamina / player.max_stamina)
	check("hud bar shrinks with stamina", fill_width() == expected_width and fill_width() < bar_width(), "%.0f (expected %.0f)" % [fill_width(), expected_width])


func test_cannot_sprint_while_lying_down() -> void:
	await start_on_runway()
	Input.action_press("crouch")
	await frames(5)
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(40)
	check("lying down ignores sprint", not player.is_sprinting, str(player.is_sprinting))
	check("speed stays at 60% while lying down", is_equal_approx(absf(player.velocity.x), player.move_speed * 0.6), "%.1f" % absf(player.velocity.x))
	check("no stamina spent while lying down", player.stamina == player.max_stamina, "%.1f" % player.stamina)


func test_running_out_of_stamina() -> void:
	await start_on_runway()
	player.stamina = 5.0
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(20) # 5 点体力大约 0.14 秒就跑光
	check("stamina runs out", player.stamina == 0.0, "%.2f" % player.stamina)
	check("player is exhausted", player.is_exhausted() and not player.is_sprinting)
	await frames(10)
	check("exhausted player drops back to normal speed", is_equal_approx(absf(player.velocity.x), player.move_speed), "%.1f" % absf(player.velocity.x))
	check("hud bar turns the tired colour", (main.get_node("HUD/StaminaBar/Fill") as ColorRect).color == preload("res://scripts/hud.gd").STAMINA_TIRED)


func test_exhausted_player_must_recover_before_sprinting_again() -> void:
	await start_on_runway()
	player.stamina = 3.0
	Input.action_press("sprint")
	Input.action_press("move_right")
	# 一直按着奔跑键：先耗尽，然后在体力回到 25% 之前都不能再跑。
	var was_exhausted := false
	var sprinted_while_exhausted := false
	var resumed_at := -1.0
	for i in 240:
		await tree.physics_frame
		# 别撞上右墙：贴墙时速度为 0，看不出是不是真的在跑。
		if player.global_position.x > 600.0:
			player.global_position.x = RUNWAY_X
		if player.is_exhausted():
			# 跑光的那一帧本身是在奔跑中用掉最后一点体力，is_sprinting 仍为真，属于正常交接；
			# 从下一帧起还在跑才是 bug。
			if was_exhausted and player.is_sprinting:
				sprinted_while_exhausted = true
			was_exhausted = true
			continue
		if was_exhausted and player.is_sprinting:
			# 恢复奔跑后 25 点体力很快又会跑光，再观察下去就是第二轮了，到此为止。
			resumed_at = player.stamina
			break
	check("stamina ran out first", was_exhausted)
	check("no sprinting until stamina recovers to 25%", not sprinted_while_exhausted)
	check("sprint resumes once recovered", resumed_at > 0.0, "resumed at %.1f" % resumed_at)
	check("resumed right around the 25% threshold", resumed_at >= 24.0 and resumed_at < 27.0, "%.1f" % resumed_at)


func test_stamina_regenerates_after_stopping() -> void:
	await start_on_runway()
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(40)
	Input.action_release("sprint")
	var after_sprint := player.stamina
	check("some stamina was spent", after_sprint < player.max_stamina - 10.0, "%.1f" % after_sprint)

	await frames(20) # 0.33 秒，还在 0.5 秒的恢复延迟内
	check("no regen during the short delay", player.stamina == after_sprint, "%.2f -> %.2f" % [after_sprint, player.stamina])

	await frames(30) # 过了延迟，再回复约 0.33 秒 × 25/秒
	check("stamina regenerates after the delay", player.stamina > after_sprint + 5.0, "%.2f -> %.2f" % [after_sprint, player.stamina])

	await frames(180)
	check("stamina refills to max and stops there", player.stamina == player.max_stamina, "%.2f" % player.stamina)
	check("hud bar is full again", fill_width() == bar_width())


func test_regen_also_works_while_walking() -> void:
	await start_on_runway()
	player.stamina = 50.0
	Input.action_press("move_left")
	await frames(60)
	check("walking without sprint regenerates stamina", player.stamina > 60.0, "%.1f" % player.stamina)
