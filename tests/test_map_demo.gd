extends GameTest
## 格子地图（`tools/map_build.py`）生成的第一段：用户示意图那一屏（`tools/level_maps.py` 的 `DEMO`）。
##
## 生成脚本自己会在格子上找路，这里拿**真的游戏规则**再跑一遍那条路线：
## 上层被 1 号块挡住 → 从 2 号缺口掉到中层 → （可以顺 4 号梯子下底层）→ 中层跳不回上层 →
## 底层敌人的子弹从单向那截地板穿得上来 → 顺 5 号梯子爬回上层出口。

const DEMO := "res://scenes/map_demo.tscn"
const TOP_FLOOR := 112.0
const MIDDLE_FLOOR := 208.0
const GROUND := 320.0


func open_demo(keep_enemies := false) -> void:
	await reset_scene(keep_enemies, true, null, 1, DEMO)


func feet() -> float:
	return player.global_position.y + 16.0


func ladder_at(x: float) -> Ladder:
	for node in get_tree_ladders():
		if absf((node as Ladder).global_position.x - x) < 24.0:
			return node
	return null


func get_tree_ladders() -> Array:
	return tree.get_nodes_in_group(Ladder.GROUP)


func test_the_top_route_is_blocked() -> void:
	# 1 号块从画面顶一直压到楼板：上层往右走、跳都过不去
	await open_demo()
	player.global_position = Vector2(200, TOP_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(60)
	release_all_input()
	check("you stop at the block", player.global_position.x < 16 * 16.0, str(player.global_position))


func test_the_gap_drops_you_to_the_middle() -> void:
	await open_demo()
	player.global_position = Vector2(100, TOP_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	await frames(25)
	release_all_input()
	await frames(40)
	check("you fell through the gap onto the middle floor", absf(feet() - MIDDLE_FLOOR) < 1.0,
		"feet at %.1f, x %.0f" % [feet(), player.global_position.x])


func test_you_cannot_jump_back_up_through_the_gap() -> void:
	# 两层隔 96、一跳实测约 92：站在 2 号缺口正下方往上跳，头伸得出去，**脚站不上去**——只能走梯子。
	# 只差 4 像素：改跳跃高度的话这里最先出事（见 CLAUDE.md）
	await open_demo()
	player.global_position = Vector2(9 * 16.0 + 8.0, MIDDLE_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"jump")
	var stood_on_top := false
	for i in 50:
		await tree.physics_frame
		if player.is_on_floor() and absf(feet() - TOP_FLOOR) < 2.0:
			stood_on_top = true
	release_all_input()
	await frames(20)
	check("you never get a foot on the floor above", not stood_on_top)
	check("and land back in the middle", absf(feet() - MIDDLE_FLOOR) < 1.0, "feet at %.1f" % feet())


func test_ladder_four_takes_you_down_and_back() -> void:
	await open_demo()
	var ladder := ladder_at(14 * 16.0)
	check("setup: ladder 4 is there", ladder != null)
	player.global_position = Vector2(ladder.global_position.x, MIDDLE_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"aim_down")
	for i in 150:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("down to the bottom room", absf(feet() - GROUND) < 1.0, "feet at %.1f" % feet())
	Input.action_press(&"aim_up")
	for i in 150:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("and back up to the middle", absf(feet() - MIDDLE_FLOOR) < 1.0, "feet at %.1f" % feet())


func test_the_shooter_below_can_hit_the_press_corridor() -> void:
	# 中层压机那一截是单向的：底层那个 2-C 斜着往上打，子弹穿得上来（这是「不打很难过」的来由）
	await open_demo(true)
	var shooter: Enemy = null
	for enemy in enemies():
		if (enemy as Enemy).global_position.y > MIDDLE_FLOOR + 32.0:
			shooter = enemy
		else:
			(enemy as Enemy).free()
	for node in main.get_node("Traps").get_children():
		node.free()
	check("setup: the shooter is down in the bottom room", shooter != null)
	if shooter == null:
		return
	player.global_position = Vector2(shooter.global_position.x - 110.0, MIDDLE_FLOOR - 16.0)
	snap_camera()
	var full := player.health
	await frames(240)
	check("its shots come up through the floor and hit you", player.health < full,
		"%d -> %d" % [full, player.health])


func test_ladder_five_takes_you_up_to_the_exit() -> void:
	await open_demo()
	var ladder := ladder_at(37 * 16.0)
	check("setup: ladder 5 is there", ladder != null)
	player.global_position = Vector2(ladder.global_position.x, MIDDLE_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"aim_up")
	for i in 150:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("up on the top floor, past the block", absf(feet() - TOP_FLOOR) < 1.0
		and player.global_position.x > 26 * 16.0, "feet at %.1f, x %.0f" % [feet(), player.global_position.x])
