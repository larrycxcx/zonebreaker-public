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


## 悬在半空的实心块 = **矮通道顶块**：底边够不着地面，底下留出一条缝。
## 竖墙和堵块是站在地上的（底边落到地面线），不算。
func crawl_passages() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		if absf(slab.position.y - GROUND_Y) < 1.0:           # 地面自己
			continue
		if slab.position.y + slab.size.y < GROUND_Y - 1.0:   # 底下还有缝
			found.append(slab)
	return found


## 站在地上的实心块：竖墙（16 宽，跳得过去）和**堵块**（比一跳还高，下面那条路走不通）。
func standing_solids() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		if absf(slab.position.y - GROUND_Y) < 1.0:
			continue
		if slab.position.y + slab.size.y >= GROUND_Y - 1.0:
			found.append(slab)
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
	var passages := crawl_passages()
	check("setup: there are crawl passages", passages.size() >= 4, str(passages.size()))
	for node in passages:
		var slab := node as Platform
		var clear := GROUND_Y - (slab.position.y + slab.size.y)
		check("%s leaves exactly the crawl gap" % slab.name, absf(clear - CRAWL_CLEAR) < 0.5,
			"%.0f" % clear)


func test_the_blocked_routes_really_block_and_really_have_a_way_over() -> void:
	# 「底下堵死、必须走上面」是这一关的骨架之一：块本身要高过一次跳，
	# 上面还得有一整块盖过去的浮台，否则那儿就是死路。
	var top := await jump_height()
	await open_level()
	var blocks := []
	for node in standing_solids():
		var slab := node as Platform
		if slab.size.y > top:
			blocks.append(slab)
	check("setup: the level blocks the low road somewhere", blocks.size() >= 3, str(blocks.size()))
	for node in blocks:
		var slab := node as Platform
		var covered := false
		for face in surfaces():
			if face[2] <= slab.position.y - 16.0 and face[0] <= slab.position.x 					and face[1] >= slab.position.x + slab.size.x:
				covered = true
		check("%s has a ledge going over it" % slab.name, covered,
			"block %.0f..%.0f, top %.0f" % [slab.position.x, slab.position.x + slab.size.x,
				slab.position.y])


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
		for slab_node in crawl_passages():
			var slab := slab_node as Platform
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


func test_nobody_walks_off_a_ledge_on_their_own() -> void:
	# 浮台上摆了一半的敌人，要是有谁一开场就自己走下去摔死，关卡会悄悄变空。
	# 巡逻兵在边缘会掉头，但摆错地方（半个身子悬空）照样会掉，所以放着跑两秒看看。
	await open_level()
	# **数敌人，不数子节点**：敌人的子弹和手雷也挂在 `Enemies` 下（见 CLAUDE.md），
	# 数子节点的话开几枪就多几个，过一会儿子弹没了又少几个
	var before := enemies().size()
	check("setup: the level is full of enemies", before >= 80, str(before))
	await frames(120)
	var after := enemies().size()
	check("they are all still there", after >= before, "%d -> %d" % [before, after])


# ---------------------------------------------------------------- 装饰

func props() -> Array:
	var found := []
	for child in main.get_node("Props").get_children():
		found.append(child)
	return found


func test_the_scenery_is_pure_decoration() -> void:
	# 和特效同一条规矩：装饰里**不许有碰撞体**，不然一棵树就能把人挡住、把子弹吃掉。
	await open_level()
	check("setup: the level is dressed up", props().size() >= 100, str(props().size()))
	var bodies := 0
	var shapes := 0
	var stack := props().duplicate()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D:
			bodies += 1
		if node is CollisionShape2D or node is CollisionPolygon2D:
			shapes += 1
		for child in node.get_children():
			stack.append(child)
	check("no collision bodies among the scenery", bodies == 0, str(bodies))
	check("and no collision shapes either", shapes == 0, str(shapes))


func test_the_scenery_is_drawn_behind_everything() -> void:
	# 画的顺序就是子节点的顺序：装饰要排在地形、敌人、玩家前面（= 画在它们后面），
	# 否则一棵树会盖住正在朝你开枪的敌人。
	await open_level()
	var order := {}
	for child in main.get_children():
		order[child.name] = child.get_index()
	check("scenery comes before the terrain", order["Props"] < order["Level"],
		"%d vs %d" % [order["Props"], order["Level"]])
	check("and before the enemies and the player",
		order["Props"] < order["Enemies"] and order["Props"] < order["Player"])


func test_the_level_plays_the_same_without_any_scenery() -> void:
	# 纯装饰的意思就是：整个删掉，关卡照常跑
	await open_level()
	main.get_node("Props").free()
	await frames(60)
	check("the level runs on without it", player.is_alive() and main.get_node_or_null("Props") == null)


func test_the_fountain_actually_runs() -> void:
	await open_level()
	var animated: Prop = null
	for node in props():
		var prop := node as Prop
		if prop != null and prop.frames > 1:
			animated = prop
	check("there is something that moves", animated != null)
	if animated == null:
		return
	var first := animated.region_rect
	for i in 60:
		await tree.physics_frame
		if animated.region_rect != first:
			break
	check("and it really cycles its frames", animated.region_rect != first,
		"%s vs %s" % [animated.region_rect, first])


func test_nothing_in_the_level_shares_a_name() -> void:
	# 同名节点会让引擎的子节点名字表对不上——free 一批敌人时刷一屏
	# 「Children name does not match parent name in hashtable, this is a bug」。
	# 生成脚本给每个敌人编号就是为了这个。
	await open_level()
	for group in ["Enemies", "Level", "Props"]:
		var seen := {}
		for child in main.get_node(group).get_children():
			check("%s/%s appears once" % [group, child.name], not seen.has(child.name), str(child.name))
			seen[child.name] = true


func test_the_level_runs_on_its_own() -> void:
	# 一整关加载起来跑两秒：出生点没卡在地形里、没有脚本报错（runner 会把 SCRIPT ERROR 记成失败）
	await open_level()
	await frames(120)
	check("the player is still standing", player.is_alive(), str(player.health))
	check("and has not fallen out of the world", player.global_position.y < main.fall_y,
		str(player.global_position))
