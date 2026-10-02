extends "res://tests/test_level_1.gd"
## 正式第二关（`scenes/level_2.tscn`，工业区）——2026-10 起是**分层的格子地图**
## （`tools/level2_map.py` 画、`tools/map_build.py` 查路和写场景）。
##
## 和方向无关的几条（敌人站在面上、开场不挨打、没人自己走下平台、装饰没有碰撞、没有重名、
## 关卡自己跑得起来、Boss 在最后）**从第一关那组继承**。横向关专用的几何检查在这里**逐条覆盖**成分层关的版本：
## 分层关的坑不一定跳得过（得走上面的钢梁）、墙不一定翻得过（得爬梯子），那正是设计。
## 下半截拿**真的游戏规则**把几处必须绕的路跑一遍。

const LEVEL_INFO := "res://levels/level_2.tres"
const CELL := 16.0
const SEGMENT := 80 * 16.0
const MIDDLE_FLOOR := 208.0


func level_path() -> String:
	return "res://scenes/level_2.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


## 第 seg 段（从 1 数）第 col 列的左边 x。
func col_x(seg: int, col: int) -> float:
	return (seg - 1) * SEGMENT + col * CELL


func feet() -> float:
	return player.global_position.y + 16.0


## 打开关卡、清掉所有敌人：下面那几条只测地形和机关，别人的流弹会打乱结果。
func open_empty() -> void:
	await open_level()
	keep_only_enemies([])
	await frames(2)


func hanging() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in main.get_node("Enemies").get_children():
		var enemy := node as EnemyDropper
		if enemy != null:
			out.append(enemy)
	return out


func solid_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			out.append(Rect2(slab.position, slab.size))
	return out


# ---------------------------------------------------------------- 覆盖：分层关的地形

## 地形块，**不含梯子顶上那块看不见的盖子**（它挂在梯子节点下面，原点是梯子顶，不是一块浮台）。
func terrain() -> Array:
	return super.terrain().filter(func(node: Node) -> bool: return not node.get_parent() is Ladder)


## 能站人的面：**所有**平台的顶边（分层关的楼板是实心的，不只是地面和单向浮台）。两侧的边墙不算。
func surfaces() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.position.y <= 0.0:
			continue
		found.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y])
	return found


## 地面是按格子合成的：传送带自己一块，和两边的地面首尾相接——接缝不是坑。
func pits() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for pit in super.pits():
		if pit.y - pit.x > 1.0:
			found.append(pit)
	return found


func test_it_really_has_pits() -> void:
	await open_level()
	check("the ground is broken up", pits().size() >= 3, str(pits().size()))


func test_every_pit_can_be_jumped() -> void:
	# 分层关的坑**不一定跳得过**（沉降池 12 格宽）——跳不过的，头顶上得有一串钢梁盖过去，
	# 一截一截之间的空当跳得过。两样都没有的坑就是死路。
	var reach := await jump_distance()
	check("setup: a jump really covers some ground", reach > 80.0, "%.0f" % reach)
	await open_level()
	var bridged := 0
	for pit in pits():
		if pit.y - pit.x <= reach:
			continue
		var overhead := []
		for face in surfaces():
			if face[2] < GROUND_Y and face[1] > pit.x and face[0] < pit.y:
				overhead.append(face)
		overhead.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var cursor := pit.x
		for face in overhead:
			if face[0] - cursor <= reach and face[1] > cursor:
				cursor = face[1]
		bridged += 1
		# 最后一截：从钢梁尽头跳 / 掉到对岸
		check("the wide pit at %.0f has walkways over it" % pit.x, pit.y - cursor <= reach,
			"covered up to %.0f of %.0f..%.0f" % [cursor, pit.x, pit.y])
	check("setup: some pits are too wide to jump", bridged >= 2, str(bridged))


func test_nothing_is_higher_than_a_jump() -> void:
	# 分层关里比一跳高的地方多的是（层高 96，正是设计），所以这一条改成：
	# **每架梯子两头都接在面上**，**每块浮台都有路上得去**（底下一跳够得着、梯子顶在它上面、
	# 旁边同一高度有一跳跨得过的面，或者头顶有面可以掉下来）。
	var top := await jump_height()
	var reach := await jump_distance()
	await open_level()
	var faces := surfaces()
	var ladders := tree.get_nodes_in_group(Ladder.GROUP)
	check("setup: the level has ladders", ladders.size() >= 10, str(ladders.size()))
	for node in ladders:
		var ladder := node as Ladder
		var x := ladder.global_position.x
		var top_ok := false
		var bottom_ok := false
		for face in faces:
			if face[0] < x and x < face[1] and absf(face[2] - (ladder.global_position.y + ladder.height)) < 1.0:
				bottom_ok = true
			if face[0] <= x + 16.0 and x - 16.0 <= face[1] and absf(face[2] - ladder.global_position.y) < 1.0:
				top_ok = true
		check("%s stands on a floor" % ladder.name, bottom_ok)
		check("%s comes out onto a floor" % ladder.name, top_ok)
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			continue
		var y := slab.position.y
		var left := slab.position.x
		var right := slab.position.x + slab.size.x
		var way := false
		for face in faces:
			var near: bool = face[1] >= left - 120.0 and face[0] <= right + 120.0
			if near and face[2] > y and face[2] - y <= top:
				way = true          # 底下一跳
			if absf(face[2] - y) < 1.0 and face[0] != left \
					and (absf(face[0] - right) <= reach or absf(left - face[1]) <= reach):
				way = true          # 同一高度、跨得过去
			if face[2] < y and face[0] < right and face[1] > left:
				way = true          # 头顶有面、掉得下来
		for lnode in ladders:
			var ladder := lnode as Ladder
			if absf(ladder.global_position.y - y) < 1.0 and left <= ladder.global_position.x \
					and ladder.global_position.x <= right:
				way = true          # 梯子顶就在它上面
		check("%s can be reached" % slab.name, way, "%.0f..%.0f at %.0f" % [left, right, y])


func test_the_crawl_passages_still_need_crouching() -> void:
	# 这一关没有矮通道。要守的是反过来那条：**楼板底下要么贴着（0），要么站得下人**——
	# 留一道 1~39 的缝，人钻不过去、子弹也卡一半，一看就是画错了。
	await open_level()
	var faces := surfaces()
	var checked := 0
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		var bottom := slab.position.y + slab.size.y
		if bottom >= GROUND_Y:
			continue
		var below := INF
		for face in faces:
			if face[2] >= bottom and face[0] < slab.position.x + slab.size.x and face[1] > slab.position.x:
				below = minf(below, face[2] - bottom)
		if below == INF:
			continue
		checked += 1
		check("%s leaves no half-height slot under it" % slab.name, below < 0.5 or below >= 40.0,
			"%.0f" % below)
	check("setup: there are floors over other floors", checked >= 20, str(checked))


func crate_stacks() -> Dictionary:
	var stacks := {}
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null:
			var key := int(crate.position.x)
			if not stacks.has(key):
				stacks[key] = []
			(stacks[key] as Array).append(crate)
	return stacks


func test_the_blocked_routes_really_block_and_really_have_a_way_over() -> void:
	# 横向关的「堵块」在这一关是**摞到顶的箱子**：打烂才过得去。摞满的那几摞和天花板之间
	# 要钻不过一个人（32），不然打都不用打。
	await open_level()
	var sealed := 0
	for key: int in crate_stacks():
		var stack: Array = crate_stacks()[key]
		var top := INF
		var bottom := -INF
		for crate: BreakableCrate in stack:
			top = minf(top, crate.position.y)
			bottom = maxf(bottom, crate.position.y + BreakableCrate.SIZE.y)
		var ceiling := -INF
		for rect in solid_rects():
			if rect.position.x < key + 32.0 and rect.end.x > key and rect.end.y <= top + 0.5:
				ceiling = maxf(ceiling, rect.end.y)
		if stack.size() >= 3:
			sealed += 1
			check("the stack at %d reaches the ceiling" % key, top - ceiling < 32.0,
				"%.0f left over it" % (top - ceiling))
	check("setup: some corridors are sealed with crates", sealed >= 2, str(sealed))


func test_no_enemy_is_stuck_in_a_crawl_passage() -> void:
	# 分层关里的说法：**没有敌人的身子嵌在实心里**（摆错一行就是这样）
	await open_level()
	var solids := solid_rects()
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or hangs_in_the_air(enemy):
			continue
		var body := Rect2(enemy.position.x - 11.0, enemy_feet(enemy) - 31.0, 22.0, 30.0)
		for rect in solids:
			check("%s is not inside the floor" % enemy.name, not body.intersects(rect),
				"%s vs %s" % [body, rect])


# ---------------------------------------------------------------- 这一关自己的

func test_it_is_a_second_stage_in_the_catalog() -> void:
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("it comes after the first one", info.order > 0, str(info.order))
	check("and it brings the industrial pack", info.skin != null
		and info.skin.resource_path.contains("industrial"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up", levels.size() >= 2, str(levels.size()))
	check("as the second one", levels.size() >= 2 and levels[1].scene_path == level_path(),
		"" if levels.size() < 2 else levels[1].scene_path)


func test_the_tiles_come_from_the_industrial_atlas() -> void:
	# 画面交给砖（`TileArt`），碰撞的平台都藏着
	await open_level()
	for layer in ["FrontTiles", "BackTiles"]:
		var art := main.get_node(layer) as TileArt
		check("%s draws industrial tiles" % layer, art != null and art.atlas != null
			and art.atlas.resource_path.begins_with("res://skins/industrial"))
	var shown := 0
	for node in terrain():
		if (node as Platform).visible and (node as Platform).position.y > 0.0:
			shown += 1
	check("and the collision platforms are hidden", shown == 0, str(shown))


func test_the_workers_hang_above_the_screen_over_something_to_land_on() -> void:
	# 2-A 是这一关的伏击：摆在画面顶边以上，走到它脚下才砸下来。
	# 底下得有个面接着它（地面也好、钢梁也好）——吊在坑上面的话它掉下去就摔死了。
	await open_level()
	var found := hanging()
	check("there are ambushers", found.size() >= 3, str(found.size()))
	for worker in found:
		check("%s hangs off the top of the screen" % worker.name, worker.position.y < 0.0,
			str(worker.position))
		var under := false
		for face in surfaces():
			if face[0] <= worker.position.x and worker.position.x <= face[1]:
				under = true
		check("%s has something to land on" % worker.name, under, "x %.0f" % worker.position.x)


func test_the_ambush_holds_until_you_walk_under_it() -> void:
	await open_level()
	await frames(120)
	for worker in hanging():
		check("%s is still up there" % worker.name, not worker.has_dropped
			and worker.position.y < 0.0, str(worker.position))


func test_the_boss_has_platforms_to_climb() -> void:
	# Boss 飘在空中、不追出地盘，**玩家得跳上去才够得着它**
	await open_level()
	var boss: Boss = null
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			boss = node
	check("there is a boss", boss != null)
	if boss == null:
		return
	check("it floats", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING)
	var reach := 0
	var high := 0
	for face in surfaces():
		if face[1] < boss.position.x - 400.0 or face[0] > boss.position.x + 400.0:
			continue
		if face[2] >= GROUND_Y:
			continue
		reach += 1
		if face[2] <= boss.position.y + 80.0:
			high += 1
	check("its arena is full of platforms", reach >= 5, str(reach))
	check("including ones up at its own height", high >= 2, str(high))


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("2_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 2", wrong.is_empty(), str(wrong))
	check("and all six types show up", kinds.size() >= 7, str(kinds.keys()))


func test_every_barrel_stands_next_to_an_enemy() -> void:
	# 用户要的就是「放在敌人旁边，打一枪就炸」——摆在空地上的油桶只是个会炸的装饰
	await open_level()
	var barrels := 0
	for node in main.get_node("Traps").get_children():
		var barrel := node as ExplosiveBarrel
		if barrel == null:
			continue
		barrels += 1
		var nearest := INF
		for enemy in enemies():
			var e := enemy as Enemy
			if hangs_in_the_air(e) or absf(e.position.y - barrel.position.y) > 24.0:
				continue
			nearest = minf(nearest, absf(e.position.x - barrel.position.x))
		check("%s has an enemy right beside it" % barrel.name, nearest <= 72.0, "%.0f" % nearest)
	check("setup: the level has barrels", barrels >= 10, str(barrels))


# ---------------------------------------------------------------- 必须绕的路，拿真规则跑一遍

func test_the_first_hall_is_a_dead_end_on_the_ground_floor() -> void:
	# 第 1 段：厂房一楼走到头是墙（78 列），得顺 56 列的梯子上二楼
	await open_empty()
	player.global_position = Vector2(col_x(1, 64), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(180)
	release_all_input()
	check("walking and jumping right gets you nowhere", player.global_position.x < col_x(1, 78),
		"x %.0f" % player.global_position.x)
	check("and you are still on the ground floor", absf(feet() - GROUND_Y) < 1.0, "feet %.1f" % feet())
	player.global_position = Vector2(col_x(1, 57), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"aim_up")
	for i in 150:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)
	check("the ladder takes you up to the first floor", absf(feet() - MIDDLE_FLOOR) < 1.0,
		"feet %.1f" % feet())


func test_the_first_floor_belt_pushes_you_back() -> void:
	await open_empty()
	player.global_position = Vector2(col_x(1, 70), MIDDLE_FLOOR - 16.0)
	await frames(10)
	var x0 := player.global_position.x
	await frames(60)
	check("standing still on the belt carries you back toward the ladder",
		x0 - player.global_position.x > 40.0, "%.1f" % (player.global_position.x - x0))


func test_the_crates_in_the_press_hall_must_be_shot_away() -> void:
	# 第 4 段：一楼右半间被一整摞箱子堵死
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - col_x(4, 70)) < 1.0:
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 4, str(stack.size()))
	player.global_position = Vector2(col_x(4, 64), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(120)
	release_all_input()
	check("you cannot get past the stack", player.global_position.x < col_x(4, 70),
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	Input.action_press(&"move_right")
	await frames(90)
	release_all_input()
	check("shot apart, the way is open", player.global_position.x > col_x(4, 73),
		"x %.0f" % player.global_position.x)


func test_the_settling_pits_need_the_walkway() -> void:
	# 第 5 段：坑 12 格宽，从地面跳不过去，要爬梯子上钢梁
	await open_empty()
	player.global_position = Vector2(col_x(5, 11), GROUND_Y - 16.0)
	await frames(3)
	var hp := player.health
	Input.action_press(&"sprint")
	Input.action_press(&"move_right")
	await frames(8)
	Input.action_press(&"jump")
	await frames(90)
	release_all_input()
	await frames(30)
	check("a running jump from the ground ends in the pit", player.health < hp
		or player.global_position.x < col_x(5, 28), "x %.0f hp %d" % [player.global_position.x, player.health])
