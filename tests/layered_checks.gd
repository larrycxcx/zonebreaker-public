extends "res://tests/level_checks.gd"
## **分层关卡**（格子地图，`tools/map_build.py` 生成）共用的检查：第一关、第二关都继承这一组。
##
## 和方向无关的几条（敌人站在面上、开场不挨打、没人自己走下平台、装饰没有碰撞、没有重名、
## 关卡自己跑得起来、Boss 在最后）从横向关那组（`level_checks.gd`）继承。横向关专用的几何检查在这里**逐条覆盖**：
## 分层关的坑不一定跳得过（得走上面的台子）、墙不一定翻得过（得爬梯子），那正是设计。
## 子类覆盖 `level_path()` / `level_stage()` / `zone()`，再写这一关自己的、拿**真规则**跑那几处必须绕的路。


## 这一关的砖从哪个素材包的总图里取（`skins/<zone>/tiles/atlas.png`）。
func zone() -> String:
	return ""


const CELL := 16.0
const SEGMENT := 80 * 16.0
const MIDDLE_FLOOR := 208.0


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


## 这一关至少有几个坑（不先确认有坑的话，下面那条比的是空气）。
func min_pits() -> int:
	return 3


func test_it_really_has_pits() -> void:
	await open_level()
	check("the ground is broken up", pits().size() >= min_pits(), str(pits().size()))


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
	check("setup: the level has ladders", ladders.size() >= 6, str(ladders.size()))
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



# ---------------------------------------------------------------- 分层关都该有的

func test_the_tiles_come_from_this_zones_atlas() -> void:
	# 画面交给砖（`TileArt`），碰撞的平台都藏着
	await open_level()
	for layer in ["FrontTiles", "BackTiles"]:
		var art := main.get_node(layer) as TileArt
		check("%s draws %s tiles" % [layer, zone()], art != null and art.atlas != null
			and art.atlas.resource_path.begins_with("res://skins/%s/" % zone()))
	var shown := 0
	for node in terrain():
		if (node as Platform).visible and (node as Platform).position.y > 0.0:
			shown += 1
	check("and the collision platforms are hidden", shown == 0, str(shown))


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
