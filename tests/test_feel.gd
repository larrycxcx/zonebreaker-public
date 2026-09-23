extends GameTest
## 打击感：屏幕抖动（摄像机 `ScreenShake`）和开枪后坐力（玩家外观弹一下）。
## 两者都只改表现——抖动只动摄像机 offset，后坐力只动 Visual 的位置，玩法判定一点都不碰。

func camera() -> ScreenShake:
	return main.get_node("Camera2D")


## 报告一个事件，等抖动生效。
## 抖动在 _process 里更新（每个画面帧一次），所以要等一个 process_frame，光等物理帧可能还没轮到。
func report(event: StringName) -> void:
	GameEvents.report(event, player)
	await tree.process_frame
	await frames(1)


func test_camera_shakes_on_events() -> void:
	await reset_scene()
	await frames(5)
	check("the camera has the shake script", camera() is ScreenShake)
	check("resting still", camera().offset == Vector2.ZERO, str(camera().offset))
	await report(&"explosion")
	check("an explosion shakes the screen", camera().offset != Vector2.ZERO, str(camera().offset))
	# 自己停下来
	for i in 60:
		await frames(1)
		if camera().offset == Vector2.ZERO:
			break
	check("and settles back on its own", camera().offset == Vector2.ZERO, str(camera().offset))


func test_bigger_events_shake_harder() -> void:
	await reset_scene()
	await frames(5)
	var shot: float = ScreenShake.SHAKES[&"player_shoot"]
	var blast: float = ScreenShake.SHAKES[&"ultimate_blast"]
	check("firing barely shakes", shot <= 2.0, str(shot))
	check("the ultimate shakes hard", blast >= 6.0, str(blast))
	check("an explosion shakes more than a shot", ScreenShake.SHAKES[&"explosion"] > shot)
	# 强度直接反映在抖动幅度上
	camera()._strength = 0.0
	await report(&"player_shoot")
	var small := camera().offset.length()
	camera()._strength = 0.0
	await report(&"ultimate_blast")
	check("a blast moves the camera further than a shot", camera().offset.length() > small,
		"%.1f vs %.1f" % [camera().offset.length(), small])


func test_shake_does_not_move_the_camera_itself() -> void:
	# 抖动只改 offset：摄像机跟随玩家的位置和关卡边界都不受影响
	await reset_scene()
	player.global_position = Vector2(400, 304)
	await frames(5)
	var position_ := camera().position
	await report(&"explosion")
	await frames(3)
	check("camera position untouched", camera().position == position_, str(camera().position))
	check("limits untouched", camera().limit_left == 0 and camera().limit_right == 1280)


func test_shake_can_be_turned_off() -> void:
	await reset_scene()
	await frames(5)
	camera().strength_scale = 0.0
	await report(&"ultimate_blast")
	await frames(3)
	check("strength_scale 0 means no shake at all", camera().offset == Vector2.ZERO, str(camera().offset))


func test_shake_runs_during_the_ultimate_freeze() -> void:
	# 终极武器把整棵树暂停了，那一下的抖动还得看得见
	await reset_scene()
	check("the camera keeps processing while paused", camera().process_mode == Node.PROCESS_MODE_ALWAYS)


func test_firing_kicks_the_visual_back() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	check("setup: visual at rest", player._visual.position == Vector2.ZERO, str(player._visual.position))
	var body := player.global_position
	player._shoot(Vector2.RIGHT)
	await frames(1)
	check("firing right kicks the visual left", player._visual.position.x < 0.0, str(player._visual.position))
	check("the body itself does not move", player.global_position == body, str(player.global_position))
	for i in 30:
		await frames(1)
		if player._visual.position == Vector2.ZERO:
			break
	check("the kick springs back", player._visual.position == Vector2.ZERO, str(player._visual.position))


func test_the_kick_follows_the_shot_direction() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	player._shoot(Vector2.UP)
	await frames(1)
	check("firing up kicks the visual down", player._visual.position.y > 0.0, str(player._visual.position))


func test_recoil_does_not_break_lying_down() -> void:
	# 趴下会把整个 Visual 下移，后坐力是加在那个位置上的偏移，两者不能打架
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	# 开枪之后立刻趴下：这一帧「趴下的下移」和「后坐力的偏移」必须同时生效，谁也别把谁抹掉
	player._shoot(Vector2.RIGHT)
	Input.action_press("crouch")
	await frames(1)
	var both := player._visual.position
	check("the kick and lying down stack instead of overwriting each other",
		both.x < 0.0 and both.y > 0.0, str(both))
	await frames(10)
	var lowered := player._visual.position
	check("lying down lowers the visual", lowered.y > 0.0, str(lowered))
	check("and the kick is gone by then", is_zero_approx(lowered.x), str(lowered))
	Input.action_release("crouch")
	await frames(20)
	check("standing up puts it back exactly", player._visual.position == Vector2.ZERO, str(player._visual.position))
