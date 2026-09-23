extends GameTest
## 正式第一关（`scenes/level_1.tscn`，`tools/level_build.py` 生成的）。
##
## 这一组读的是**生成出来的场景**，不是生成脚本里那张表——脚本自己也会自检，
## 但谁手改了 `.tscn`、或者哪天玩家的跳跃改了，只有从场景这边量才看得出来。
##
## 跳得过去的距离是**实测**的：在测试关的平地上按住跳跃 + 右走，量离地到落地之间走了多远。
## 不用公式算，这样玩家的重力、跳跃力、走路速度哪个变了，这里都会说话。

const LEVEL := "res://scenes/level_1.tscn"
const GROUND_Y := 320.0
## 站着 32 高过不去、站姿子弹离地 21~25 过得去，矮通道净空就卡在这中间（见 CLAUDE.md）。
const CRAWL_CLEAR := 30.0


func open_level() -> void:
	await reset_scene(true, true, null, 1, LEVEL)


## 关卡里所有的地形块（`Level` 底下的，含 `Level/Walls` 里的竖墙）。
func terrain() -> Array:
	var found := []
	for child in main.get_node("Level").get_children():
		if child is Platform:
			found.append(child)
		else:
			for grandchild in child.get_children():
				if grandchild is Platform:
					found.append(grandchild)
	return found


## 地面那几段，按左端排好：(左, 右)。
func ground_runs() -> Array[Vector2]:
	var runs: Array[Vector2] = []
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way and absf(slab.position.y - GROUND_Y) < 1.0:
			runs.append(Vector2(slab.position.x, slab.position.x + slab.size.x))
	runs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return runs


## 地面断开的那几处：(左岸右端, 右岸左端)。
func pits() -> Array[Vector2]:
	var found: Array[Vector2] = []
	var runs := ground_runs()
	for i in runs.size() - 1:
		found.append(Vector2(runs[i].y, runs[i + 1].x))
	return found


## 能站人的面：(左, 右, 顶边)。地面按段算，单向浮台各算一块。
func surfaces() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or absf(slab.position.y - GROUND_Y) < 1.0:
			found.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y])
	return found


## 一个坑要跳几次：坑里架了浮台的话，从左岸跳上去、再跳到右岸。返回每一跳多远。
func hops_across(pit: Vector2) -> Array[float]:
	var edges: Array[float] = [pit.x]
	for node in terrain():
		var slab := node as Platform
		if slab.one_way and slab.position.x >= pit.x and slab.position.x + slab.size.x <= pit.y:
			edges.append(slab.position.x)
			edges.append(slab.position.x + slab.size.x)
	edges.append(pit.y)
	edges.sort()
	var hops: Array[float] = []
	for i in range(0, edges.size() - 1, 2):
		hops.append(edges[i + 1] - edges[i])
	return hops


## 在平地上按住跳跃往前跳，实测离地到落地走了多远 —— 也就是能跨多宽的坑。
func jump_distance() -> float:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	Input.action_press("move_right")
	await frames(20)                      # 先加速到全速
	Input.action_press("jump")            # **按住**：提前松开是低跳，只有一半高
	var start := 0.0
	var airborne := false
	for i in 120:
		await tree.physics_frame
		if not airborne and not player.is_on_floor():
			airborne = true
			start = player.global_position.x
		elif airborne and player.is_on_floor():
			break
	release_all_input()
	return player.global_position.x - start


# ---------------------------------------------------------------- 关卡的形状

func test_the_level_is_ten_times_the_test_one() -> void:
	await open_level()
	var camera: Camera2D = main.get_node("Camera2D")
	check("the camera lets you walk twenty screens", camera.limit_right == 12800,
		str(camera.limit_right))
	var runs := ground_runs()
	check("setup: there is ground", not runs.is_empty())
	check("and the ground reaches the far wall", runs[runs.size() - 1].y >= 12800.0 - 1.0,
		str(runs[runs.size() - 1].y))
	check("the player starts at the near end", main.get_node("Player").position.x < 640.0,
		str(main.get_node("Player").position.x))


func test_it_really_has_pits() -> void:
	# 不先确认有坑的话，下面那条「每个坑都跳得过去」比的是空气
	await open_level()
	check("the ground is broken up", pits().size() >= 4, str(pits().size()))


func test_every_pit_can_be_jumped() -> void:
	var reach := await jump_distance()
	check("setup: a jump really covers some ground", reach > 80.0, "%.0f" % reach)
	await open_level()
	for pit in pits():
		for hop in hops_across(pit):
			check("the pit at %.0f can be cleared" % pit.x, hop <= reach,
				"%.0f wide, a jump covers %.0f" % [hop, reach])


func test_nothing_is_higher_than_a_jump() -> void:
	var reach := await jump_distance()
	await open_level()
	# 竖墙：CLAUDE.md 的规矩是比跳跃高度至少低 12。跳跃高度这里按实测的横向距离折算不合适，
	# 所以直接量一次纵向的。
	var top := await jump_height()
	check("setup: the jump has some height", top > 60.0, "%.0f" % top)
	await open_level()
	for node in main.get_node("Level/Walls").get_children():
		var wall := node as Platform
		check("%s can be jumped" % wall.name, wall.size.y <= top - 12.0,
			"%.0f tall, the jump reaches %.0f" % [wall.size.y, top])
	# 浮台：每一块底下 120px 以内要有个够得着的面，否则那块就是上不去的
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			continue
		var best := INF
		for face in surfaces():
			var other: float = face[2]
			if other <= slab.position.y:
				continue
			if face[1] < slab.position.x - 120.0 or face[0] > slab.position.x + slab.size.x + 120.0:
				continue
			best = minf(best, other - slab.position.y)
		check("%s can be reached" % slab.name, best <= top,
			"%.0f up, the jump reaches %.0f" % [best, top])


## 在平地上按住跳跃，实测跳多高。
func jump_height() -> float:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var floor_y := player.global_position.y
	Input.action_press("jump")
	var top := floor_y
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
		if player.is_on_floor() and i > 5:
			break
	release_all_input()
	return floor_y - top


func test_the_crawl_passages_still_need_crouching() -> void:
	await open_level()
	var found := 0
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or absf(slab.position.y - GROUND_Y) < 1.0 or slab.size.x < 32.0:
			continue
		if slab.position.y <= 0.0:                 # 关卡两头的立墙
			continue
		var clear := GROUND_Y - (slab.position.y + slab.size.y)
		found += 1
		check("%s leaves exactly the crawl gap" % slab.name, absf(clear - CRAWL_CLEAR) < 0.5,
			"%.0f" % clear)
	check("setup: there are crawl passages", found >= 2, str(found))


## 敌人脚底的 y：判定框中心往下半个框高（Boss 的框比普通敌人高，所以按各自的形状算）。
func enemy_feet(enemy: Enemy) -> float:
	var box: CollisionShape2D = enemy.get_node("CollisionShape2D")
	return enemy.position.y + (box.shape as RectangleShape2D).size.y / 2.0 + box.position.y


# ---------------------------------------------------------------- 摆在里面的东西

func test_every_enemy_stands_on_something() -> void:
	await open_level()
	var checked := 0
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or enemy is EnemyFlyer:
			continue
		var feet: float = enemy_feet(enemy)
		var standing := false
		for face in surfaces():
			if face[0] - 8.0 <= enemy.position.x and enemy.position.x <= face[1] + 8.0 \
					and absf(face[2] - feet) < 2.0:
				standing = true
		checked += 1
		check("%s has ground under it" % enemy.name, standing,
			"feet at %.0f, x %.0f" % [feet, enemy.position.x])
	check("setup: there are enemies to check", checked >= 20, str(checked))


func test_no_enemy_is_stuck_in_a_crawl_passage() -> void:
	# 敌人 32 高、矮通道净空 30，摆进去就卡死不动（CLAUDE.md 里记过这条坑）
	await open_level()
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or enemy is EnemyFlyer:
			continue
		if absf(enemy_feet(enemy) - GROUND_Y) > 1.0:
			continue
		for slab_node in terrain():
			var slab := slab_node as Platform
			if slab.one_way or slab.position.y <= 0.0 or absf(slab.position.y - GROUND_Y) < 1.0:
				continue
			check("%s is clear of %s" % [enemy.name, slab.name],
				enemy.position.x < slab.position.x - 24.0
				or enemy.position.x > slab.position.x + slab.size.x + 24.0,
				"enemy at %.0f, passage %.0f..%.0f"
					% [enemy.position.x, slab.position.x, slab.position.x + slab.size.x])


func test_the_boss_waits_at_the_far_end() -> void:
	await open_level()
	var boss: Boss = null
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			boss = node
	check("there is a boss", boss != null)
	check("and it is in the last stretch", boss != null and boss.position.x > 12800.0 - 1280.0,
		"" if boss == null else str(boss.position.x))


func test_the_level_runs_on_its_own() -> void:
	# 一整关加载起来跑两秒：出生点没卡在地形里、没有脚本报错（runner 会把 SCRIPT ERROR 记成失败）
	await open_level()
	await frames(120)
	check("the player is still standing", player.is_alive(), str(player.health))
	check("and has not fallen out of the world", player.global_position.y < main.fall_y,
		str(player.global_position))
