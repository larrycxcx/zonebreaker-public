extends "res://tests/layered_checks.gd"
## 正式第四关（`scenes/level_4.tscn`，地下室）——**纵向往上爬**，2026-10 起是**竖着的格子地图**
## （`tools/level4_map.py`，40 × 450 格，`map_build.py` 查路、挑砖、写场景，砖用 `THEMES["basement"]`）。
##
## 继承分层关那组（`layered_checks.gd`）：和方向无关的几条（装饰、重名、开场不挨打、没人自己走下平台、
## 梯子两头接在面上、浮台上得去、楼板底下没有半高的缝、摞满的箱子堵得死、敌人没嵌进墙、砖来自这一区、
## 油桶旁边有敌人）直接捡过来。横向专用的几条在这里**逐条覆盖**成纵向的：一屏宽 20 屏高、两侧墙通到底、
## 从地面爬得到 Boss 区（这回**算上梯子**）、出生那一屏没有敌人。下半截拿真规则跑几处必须绕的路。
##
## 尺子和横向关一样是**实测的**（`jump_height()`），玩家的跳跃改了这里立刻说话。

const LEVEL_INFO := "res://levels/level_4.tres"
const WIDTH := 640.0
const HEIGHT := 7200.0
const SCREEN_H := 360.0
## 跳上去的时候横向能差多少（留了一半余量）。
const REACH_X := 48.0
## 一段多高（格）：十段，每段两屏。
const SEG_ROWS := 45
## 两侧岩墙多厚（2 格）。
const WALL_W := 32.0
## 人多宽：起跳、落脚那一截被挡掉一部分以后，剩下的空当至少要这么宽
const BODY_W := 24.0


func level_path() -> String:
	return "res://scenes/level_4.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "basement"


## 第 seg 段（从下往上数，1 是出生那一段）段内第 row 行的顶边 y。
func seg_y(seg: int, row: int) -> float:
	return ((10 - seg) * SEG_ROWS + row) * CELL


## 能站人的面：[左, 右, 顶边, 是不是实心的, 名字, 底边]。两侧的墙不算（站不上去，它们是边界）。
func faces() -> Array:
	var out := []
	for node in terrain():
		var slab := node as Platform
		if slab.name.begins_with("Wall") or slab.position.y <= 0.0:
			continue
		# 两侧岩墙在格子地图里会被横贯的楼板切成一截一截（同一行整行实心就合成一块），那几截不是能站的面
		if slab.position.x + slab.size.x <= WALL_W or slab.position.x >= WIDTH - WALL_W:
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
	# 起跳、落脚在两块横向重叠的那一截（不重叠就是挨着的那一点）。那一截上方被实心挡住的部分扣掉，
	# **剩下的空当还放得下一个人**（`BODY_W`）就跳得上去。整块面上方都要求净空的话，竖井正中那道墙、
	# 货梯井那垛集装箱会把横贯两边的台子整个算成「跳不上去」
	var left := maxf(low[0], high[0])
	var right := maxf(minf(low[1], high[1]), left + BODY_W)
	var blocked: Array = []
	for other: Array in all:
		if not other[3] or other[4] == high[4] or other[4] == low[4]:
			continue
		if other[1] <= left or other[0] >= right:
			continue
		if other[5] > high[2] - 40.0 and other[2] < low[2]:
			blocked.append([maxf(other[0], left), minf(other[1], right)])
	blocked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor := left
	for span: Array in blocked:
		if span[0] - cursor >= BODY_W:
			return true
		cursor = maxf(cursor, span[1])
	return right - cursor >= BODY_W


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
	# 纵向的「过得去」= **从地面一路爬得到 Boss 区的地板**：往上跳（高出不超过一跳、横向差得不多、
	# 中间没被实心挡住）、往下走、**爬梯子**（梯子底下那块和梯子顶那块连通）。每一块单向台子都得爬得到。
	var jump := await jump_height()
	check("setup: the jump has some height", jump > 60.0, "%.0f" % jump)
	await open_level()
	var all := faces()
	var ladders := tree.get_nodes_in_group(Ladder.GROUP)
	check("setup: there are ledges and ladders", all.size() > 100 and ladders.size() >= 10,
		"%d / %d" % [all.size(), ladders.size()])
	var start: Array = all.filter(func(f: Array) -> bool: return f[2] >= HEIGHT - 60.0)
	var seen := {}
	var frontier: Array = []
	for f: Array in start:
		seen[f[4]] = true
		frontier.append(f)
	while not frontier.is_empty():
		var here: Array = frontier.pop_back()
		for face: Array in all:
			if seen.has(face[4]):
				continue
			var down: bool = face[2] > here[2] and gap_x(here, face) <= REACH_X
			var climb := false
			for node in ladders:
				var ladder := node as Ladder
				var x := ladder.global_position.x
				var foot := ladder.global_position.y + ladder.height
				if here[0] <= x and x <= here[1] and absf(here[2] - foot) < 1.0 \
						and face[0] - 32.0 <= x and x <= face[1] + 32.0 and absf(face[2] - ladder.global_position.y) < 1.0:
					climb = true
			if down or climb or reachable_up(here, face, all, jump):
				seen[face[4]] = true
				frontier.append(face)
	var lost: Array = all.filter(func(f: Array) -> bool: return not f[3] and not seen.has(f[4]))
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


func test_the_crawl_passages_still_need_crouching() -> void:
	# 分层那一层的版本只看地面线以上（横向关），竖井里每一块都在「地面线」以下，所以这里照同样的规矩重量一遍：
	# 实心块底下要么贴着、要么站得下人（不许有 1~39 的缝）
	await open_level()
	var all := faces()
	var checked := 0
	for block: Array in all:
		if not block[3] or block[2] >= HEIGHT - 60.0:
			continue
		var below := INF
		for face: Array in all:
			if face != block and face[2] >= block[5] and face[0] < block[1] and face[1] > block[0]:
				below = minf(below, face[2] - block[5])
		if below == INF:
			continue
		checked += 1
		check("%s leaves no half-height slot under it" % block[4], below < 0.5 or below >= 40.0, "%.0f" % below)
	check("setup: there are floors over other floors", checked >= 20, str(checked))


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
	# 半腰：第 5 段（货梯井）左边那一串台子，周围没有箱子、机关
	player.global_position = Vector2(8.5 * CELL, seg_y(5, 35) - 16.0)
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


# ---------------------------------------------------------------- 必须绕的路，拿真规则跑一遍

## 按住上 / 下爬梯子：**先等它真的抓住梯子**（最多半秒），再等它爬到头松手。
## 只等固定几帧就开始看「是不是还在爬」的话，整套连着跑时偶尔慢一拍，还没抓住就当成「爬完了」（全量跑时撞到过）。
func climb(direction: StringName) -> void:
	await frames(10)
	Input.action_press(direction)
	for i in 30:
		await tree.physics_frame
		if player.is_climbing():
			break
	for i in 240:
		await tree.physics_frame
		if not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func put_player(x: float, feet_y: float) -> void:
	player.global_position = Vector2(x, feet_y - 16.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await frames(3)


func test_the_sump_ceiling_is_climbed_not_jumped() -> void:
	# 第 1 段：头顶一整块**实心**楼板，只有右头那架梯子上得去。
	# 从楼板正下方往上跳（满速起跳）：要是这块是单向的，人就从底下穿上去了
	# 横向摆在第 26 行那块台子正上方：弹回来落在它上面（只掉 40）。摆在别处的话会掉到画面底边以下
	# ——摄像机只往上卷，这一下起跳把画面带上去了，掉下去就是「掉坑」，连掉几次人就没了
	await open_empty()
	await put_player(29.5 * CELL, seg_y(1, 26))
	player.global_position = Vector2(29.5 * CELL, seg_y(1, 22) + 24.0)
	player.velocity = Vector2(0, -560)
	await frames(40)
	check("a jump from right under the slab bounces off it", player.global_position.y > seg_y(1, 22),
		"y %.0f, slab bottom %.0f" % [player.global_position.y, seg_y(1, 22)])
	check("and lands back on the ledge, alive", player.is_alive() and absf(feet() - seg_y(1, 26)) < 1.0,
		"feet %.1f hp %d" % [feet(), player.health])


func test_the_sump_ladder_goes_up_through_the_slab() -> void:
	# 和上一条分开，各开一个干净的场景
	await open_empty()
	await put_player(33 * CELL, seg_y(1, 26))
	await climb(&"aim_up")
	check("the ladder takes you onto the slab", absf(feet() - seg_y(1, 20)) < 1.0, "feet %.1f" % feet())


func press_jump_held(n: int) -> void:
	Input.action_press(&"jump")
	await frames(n)
	release_all_input()
	await frames(20)


func test_the_boiler_room_ladder_is_walled_off_with_crates() -> void:
	# 第 3 段：屋里右头那架梯子前面一整摞箱子，打烂了才走得到
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - 30 * CELL) < 1.0 and crate.position.y > seg_y(3, 28) \
				and crate.position.y < seg_y(3, 36):
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 4, str(stack.size()))
	await put_player(24 * CELL, seg_y(3, 36))
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(120)
	release_all_input()
	check("you cannot get past the stack", player.global_position.x < 30 * CELL,
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	Input.action_press(&"move_right")
	await frames(60)
	release_all_input()
	check("shot apart, the ladder is in reach", player.global_position.x > 33 * CELL,
		"x %.0f" % player.global_position.x)


func test_the_lift_shaft_only_goes_up_on_the_left() -> void:
	# 第 5 段：正中一大垛集装箱、右边那条缝底下封死，入口那条台子往右走就撞上集装箱
	await open_empty()
	await put_player(6 * CELL, seg_y(5, 42))
	Input.action_press(&"move_right")
	await frames(90)
	release_all_input()
	check("the container stack stops you", player.global_position.x < 12 * CELL,
		"x %.0f" % player.global_position.x)

