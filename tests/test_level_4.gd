extends "res://tests/level_checks.gd"
## 正式第四关（`scenes/level_4.tscn`，地下室）——**纵向往上爬**。
##
## 继承正式关卡的基类（`level_checks.gd`），是为了把**和方向无关的**那几条捡过来：装饰纯显示、画在最后面、删了照常跑、
## 会动的真的在动、没有重名、开场不挨打、没人自己走下平台、关卡自己跑得起来。
## 横向专用的几条（关卡宽 20 屏、有坑、矮通道、堵块有高路、开场那一屏按 x 量……）在这里**逐条覆盖**
## 成纵向的版本：每块平台都跳得上去、从地面爬得到顶、出生那一屏没有敌人。
##
## 尺子和横向关一样是**实测的**（`jump_height()`），玩家的跳跃改了这里立刻说话。

const LEVEL_INFO := "res://levels/level_4.tres"
const WIDTH := 640.0
const HEIGHT := 7200.0
const SCREEN_H := 360.0
## 跳上去的时候横向能差多少（和生成脚本 `vlevel_build.REACH_X` 一样，留了一半余量）。
const REACH_X := 48.0


func level_path() -> String:
	return "res://scenes/level_4.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


## 能站人的面：[左, 右, 顶边, 是不是实心的, 名字]。两侧的墙不算（站不上去，它们是边界）。
func faces() -> Array:
	var out := []
	for node in terrain():
		var slab := node as Platform
		if slab.name.begins_with("Wall"):
			continue
		out.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y,
			not slab.one_way, String(slab.name), slab.position.y + slab.size.y])
	return out


func gap_x(a: Array, b: Array) -> float:
	return maxf(0.0, maxf(a[0], b[0]) - minf(a[1], b[1]))


## 从 low 跳得上 high 吗：高出不超过一跳、横向差得不多、中间没有实心块挡着。
func reachable_up(low: Array, high: Array, all: Array, jump: float) -> bool:
	var step: float = low[2] - high[2]
	if step <= 0.0 or step > jump - 12.0 or gap_x(low, high) > REACH_X:
		return false
	for other: Array in all:
		if not other[3] or other[4] == high[4] or other[4] == low[4]:
			continue
		if other[1] <= high[0] - 8.0 or other[0] >= high[1] + 8.0:
			continue
		if other[5] > high[2] - 40.0 and other[2] < low[2]:
			return false
	return true


# ---------------------------------------------------------------- 关卡的形状（覆盖横向那几条）

func test_the_level_is_ten_times_the_test_one() -> void:
	# 纵向：一屏宽、20 屏高，摄像机只往上卷，人从最底下出发
	await open_level()
	var camera := main.get_node("Camera2D") as CameraRig
	check("one screen wide", camera.limit_right - camera.limit_left == int(WIDTH),
		"%d..%d" % [camera.limit_left, camera.limit_right])
	check("twenty screens tall", camera.limit_bottom - camera.limit_top == int(HEIGHT),
		"%d..%d" % [camera.limit_top, camera.limit_bottom])
	check("the screen only climbs", camera.only_up)
	check("the player starts at the bottom", player.global_position.y > HEIGHT - SCREEN_H,
		str(player.global_position))
	check("falling out is judged below the bottom of the level", main.fall_y > HEIGHT, str(main.fall_y))


func test_it_really_has_pits() -> void:
	# 纵向关没有坑（掉出画面底边就是坑）。换成：竖井两侧是一整条墙，没有缝能钻出去
	await open_level()
	for side: String in ["WallLeft", "WallRight"]:
		var wall := main.get_node("Level/" + side) as Platform
		check("%s runs the full height" % side, wall != null and wall.position.y <= 0.0
			and wall.position.y + wall.size.y >= HEIGHT, str(wall))


func test_every_pit_can_be_jumped() -> void:
	# 纵向的「跳得过去」= **每一块都能从底下某个面跳上来**
	var jump := await jump_height()
	check("setup: the jump has some height", jump > 60.0, "%.0f" % jump)
	await open_level()
	var all := faces()
	check("setup: there are ledges", all.size() > 100, str(all.size()))
	for face: Array in all:
		if face[4] == "Ground":
			continue
		var ok := false
		for low: Array in all:
			if low != face and reachable_up(low, face, all, jump):
				ok = true
				break
		check("%s can be reached from below" % face[4], ok, "y %.0f, x %.0f..%.0f" % [face[2], face[0], face[1]])


func test_nothing_is_higher_than_a_jump() -> void:
	# 从地面出发，往上跳、往下走，要能到**每一块**，最后到 Boss 区的地板
	var jump := await jump_height()
	await open_level()
	var all := faces()
	var seen := {"Ground": true}
	var frontier: Array = all.filter(func(f: Array) -> bool: return f[4] == "Ground")
	while not frontier.is_empty():
		var here: Array = frontier.pop_back()
		for face: Array in all:
			if seen.has(face[4]):
				continue
			var down: bool = face[2] > here[2] and gap_x(here, face) <= REACH_X
			if down or reachable_up(here, face, all, jump):
				seen[face[4]] = true
				frontier.append(face)
	var lost: Array = all.filter(func(f: Array) -> bool: return not seen.has(f[4]))
	check("every ledge can be climbed to from the floor", lost.is_empty(),
		str(lost.map(func(f: Array) -> String: return f[4]).slice(0, 8)))
	check("including the arena floor at the top", seen.has(arena_floor()[4]), arena_floor()[4])


func arena_floor() -> Array:
	# 最上面一屏里最宽的那块
	var best := []
	for face: Array in faces():
		if face[2] < SCREEN_H and (best.is_empty() or face[1] - face[0] > best[1] - best[0]):
			best = face
	return best


func test_the_crawl_passages_still_need_crouching() -> void:
	# 纵向关没有矮通道（往上爬时趴着没用）。换成：实心块底下都留得出一个人
	await open_level()
	var all := faces()
	for block: Array in all:
		if not block[3] or block[4] == "Ground":
			continue
		for face: Array in all:
			if face == block or face[1] <= block[0] or face[0] >= block[1]:
				continue
			var room: float = face[2] - block[5]
			if room >= 0.0:
				check("%s leaves room to stand under %s" % [face[4], block[4]], room >= 40.0,
					"%.0f" % room)


func test_the_blocked_routes_really_block_and_really_have_a_way_over() -> void:
	# 纵向的「堵路」= 实心块：从下面穿不上去，得绕。要真的有，而且真是实心的
	await open_level()
	var blocks: Array = faces().filter(func(f: Array) -> bool: return f[3] and f[4] != "Ground")
	check("setup: the shaft has solid blocks to go round", blocks.size() >= 3, str(blocks.size()))
	for node in terrain():
		var slab := node as Platform
		if slab.name.begins_with("Block"):
			check("%s cannot be jumped through" % slab.name, not slab.one_way)


func test_every_enemy_stands_on_something() -> void:
	await open_level()
	var all := faces()
	var checked := 0
	for enemy in enemies():
		if hangs_in_the_air(enemy):
			continue
		var feet := enemy_feet(enemy)
		var standing := false
		for face: Array in all:
			if face[0] + 8.0 <= enemy.position.x and enemy.position.x <= face[1] - 8.0 \
					and absf(face[2] - feet) < 2.0:
				standing = true
		checked += 1
		check("%s has something under it" % enemy.name, standing,
			"feet at %.0f, x %.0f" % [feet, enemy.position.x])
	check("setup: there are enemies to check", checked >= 50, str(checked))


func test_the_player_gets_a_moment_before_the_first_enemy() -> void:
	# 纵向：出生那一屏（最底下一屏）里没有敌人
	await open_level()
	var lowest := -INF
	for enemy in enemies():
		lowest = maxf(lowest, enemy.position.y)
	check("setup: there are enemies further up", lowest > -INF)
	check("but none on the opening screen", lowest < HEIGHT - SCREEN_H,
		"the lowest one is at y %.0f" % lowest)


func test_the_boss_waits_at_the_far_end() -> void:
	# 纵向：Boss 在**最上面一屏**，那儿有一整层地板，除了它没有别的敌人
	await open_level()
	var boss: Boss = null
	for node in enemies():
		if node is Boss:
			boss = node
	check("there is a boss", boss is BossSkull, str(boss))
	if boss == null:
		return
	check("up in the last screen", boss.position.y < SCREEN_H, str(boss.position))
	var floor_ := arena_floor()
	check("there is an arena floor at the top", not floor_.is_empty())
	if floor_.is_empty():
		return
	check("it spans the shaft", floor_[1] - floor_[0] >= 500.0, "%.0f" % (floor_[1] - floor_[0]))
	# 它最低的时候，激光正好对准站在地板上的人
	var low := boss.position.y + BossSkull.BEAM_ORIGIN.y
	check("at its lowest its beam meets a player on the floor", absf(low - (floor_[2] - 16.0)) <= 1.0,
		"%.0f vs %.0f" % [low, floor_[2] - 16.0])
	for enemy in enemies():
		if enemy is Boss:
			continue
		check("%s is not in the arena" % enemy.name, enemy.position.y > SCREEN_H, str(enemy.position))


# ---------------------------------------------------------------- 这一关独有的

func test_it_is_the_fourth_stage_in_the_catalog() -> void:
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and it brings the basement pack", info.skin != null
		and info.skin.resource_path.contains("basement"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up as the fourth one",
		levels.size() >= 4 and levels[3].scene_path == level_path(),
		"" if levels.size() < 4 else levels[3].scene_path)


func test_the_terrain_wears_the_basement_art() -> void:
	await open_level()
	var checked := 0
	for node in terrain():
		var visual := (node as Platform).get_node("Visual")
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes its art from this zone" % node.name,
				texture != null and texture.resource_path.begins_with("res://skins/basement"), str(texture))
	check("setup: the terrain is skinned at all", checked > 100, str(checked))


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("4_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 4", wrong.is_empty(), str(wrong))
	check("and all six types show up", kinds.size() >= 6, str(kinds.keys()))


func test_the_drones_hug_the_walls() -> void:
	# 会飞的贴着两侧墙：它横向不动，摆在中间的话就挡在人往上爬的路上了
	await open_level()
	var found := 0
	for enemy in enemies():
		if enemy is EnemyHoverGun:
			found += 1
			var x: float = enemy.position.x
			check("%s is by a wall" % enemy.name, x < 128.0 or x > WIDTH - 128.0, "x %.0f" % x)
	check("setup: there are drones", found >= 5, str(found))


func test_climbing_then_dropping_out_costs_a_fall_and_lands_you_on_screen() -> void:
	# 拿真关卡跑一遍纵向规则：爬到半腰，画面跟着上去；掉出画面底边扣血、捞回画面里。
	# 先把敌人清掉：不然掉的那点血可能是挨打掉的，量的就不是「掉坑」了
	await open_level()
	for enemy in enemies():
		enemy.free()
	var all := faces()
	var mid: Array = all.filter(func(f: Array) -> bool:
		return not f[3] and absf(f[2] - HEIGHT / 2.0) < 120.0)[0]
	player.global_position = Vector2((mid[0] + mid[1]) / 2.0, mid[2] - 16.0)
	player.velocity = Vector2.ZERO
	await frames(15)
	var stood := player.global_position
	var view := camera_rig().view_rect()
	check("the screen followed you up", view.has_point(stood), "%s in %s" % [stood, view])
	var full := player.health
	player.global_position = Vector2(stood.x, view.end.y + 60.0)
	await frames(3)
	check("dropping out of the bottom is a fall", player.health < full, "%d -> %d" % [full, player.health])
	check("and you land back on screen", camera_rig().view_rect().has_point(player.global_position),
		str(player.global_position))


func test_enemies_you_climb_past_are_cleared_without_pay() -> void:
	await open_level()
	var before := enemies().size()
	var xp := player.progress.xp
	var money := player.progress.money
	var high: Array = faces().filter(func(f: Array) -> bool:
		return not f[3] and f[2] < HEIGHT / 2.0 and f[2] > HEIGHT / 2.0 - 200.0)[0]
	player.global_position = Vector2((high[0] + high[1]) / 2.0, high[2] - 16.0)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("the ones far below are gone", enemies().size() < before, "%d -> %d" % [before, enemies().size()])
	check("and nobody was paid for them", player.progress.xp == xp and player.progress.money == money,
		"xp %d -> %d" % [xp, player.progress.xp])


func test_the_boss_stays_on_screen_while_you_stand_on_the_arena_floor() -> void:
	# 截图看出来的：摄像机以人为中心的话，人站在 Boss 区地板上时 Boss 飘高了就出了画面
	await open_level()
	var boss: BossSkull = null
	for node in enemies():
		if node is BossSkull:
			boss = node
		else:
			node.free()
	check("setup: there is the skull", boss != null)
	if boss == null:
		return
	var floor_ := arena_floor()
	player.global_position = Vector2(200, floor_[2] - 16.0)
	player.velocity = Vector2.ZERO
	await frames(10)
	var view := camera_rig().view_rect()
	var box := (boss.get_node("CollisionShape2D").shape as RectangleShape2D).size
	var highest := boss._home.y - boss.rise - box.y / 2.0
	check("its highest point is on screen", highest >= view.position.y,
		"Boss 最高 %.0f，画面顶 %.0f" % [highest, view.position.y])
	check("and so is its lowest", boss._home.y + box.y / 2.0 <= view.end.y)
	# 每一层都对得准：最高那块平台上的人，它飘得到
	var top_center := INF
	for face: Array in faces():
		if face[2] < SCREEN_H:
			top_center = minf(top_center, face[2] - 16.0)
	check("it can rise to line up with the highest ledge",
		boss._home.y - boss.rise + BossSkull.BEAM_ORIGIN.y <= top_center,
		"最高能打到 %.0f，最高那层的人在 %.0f" % [boss._home.y - boss.rise + BossSkull.BEAM_ORIGIN.y, top_center])
