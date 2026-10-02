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


# ---------------------------------------------------------------- 画面：砖（只管好看，不碰规则）

func tile_set(node_name: String) -> Dictionary:
	var art := main.get_node(node_name) as TileArt
	var cells := {}
	for i in range(0, art.cells.size(), 4):
		cells[Vector2i(art.cells[i], art.cells[i + 1])] = art.cells[i + 2]
	return cells


func test_the_tiles_are_pure_decoration() -> void:
	await open_demo()
	for node_name: String in ["BackTiles", "FrontTiles"]:
		var art := main.get_node(node_name)
		check("%s is tile art" % node_name, art is TileArt)
		check("%s has nothing to collide with" % node_name,
			art.find_children("*", "CollisionObject2D", true, false).is_empty())


func test_the_platforms_only_collide_and_the_tiles_draw() -> void:
	# 碰撞还是平台节点管；它们藏起来不画，不然砖和九宫格会叠成两层
	await open_demo()
	var front := tile_set("FrontTiles")
	var checked := 0
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab == null or slab.name.begins_with("Wall"):
			continue
		check("%s is hidden" % slab.name, not slab.visible)
		var x0 := int(slab.position.x / 16.0)
		var y0 := int(slab.position.y / 16.0)
		var missing := 0
		for cy in range(y0, y0 + int(slab.size.y / 16.0)):
			for cx in range(x0, x0 + int(slab.size.x / 16.0)):
				if not front.has(Vector2i(cx, cy)):
					missing += 1
		checked += 1
		check("every cell of %s is tiled" % slab.name, missing == 0, "%d 格没有砖" % missing)
	check("setup: there are platforms", checked >= 5, str(checked))


func test_indoor_rooms_have_a_wall_behind_them() -> void:
	# 中层、底层后面要是室内的墙，不是天空（用户要的「像宣传图」）
	await open_demo()
	var back := tile_set("BackTiles")
	for cell: Vector2i in [Vector2i(3, 10), Vector2i(20, 16), Vector2i(30, 11)]:
		check("indoor cell %s has wall behind it" % cell, back.has(cell))
	check("the sky above the top floor is left open", not back.has(Vector2i(30, 3)))


func test_the_walls_carry_numbered_pipes_like_the_promo() -> void:
	# 宣传图墙上的紫色大管子和「4」「3」：管道按块拼（直管 / 管头 / 圆盘接头），编号牌 = 圆盘 + 数字
	await open_demo()
	var signs := main.get_node("Decals").get_children()
	check("two number plates", signs.size() == 2, str(signs.size()))
	var digits: Array[String] = []
	for sign in signs:
		digits.append((sign as Sprite2D).texture.resource_path.get_file())
	digits.sort()
	check("reading 3 and 4", digits == ["digit_3.png", "digit_4.png"], str(digits))
	var back := tile_set("BackTiles")
	for sign in signs:
		var at := Vector2i(int((sign as Node2D).position.x / 16.0), int((sign as Node2D).position.y / 16.0))
		check("each sign sits on a pipe joint", back.get(at) == 39, str(back.get(at)))
	# 中层那条：左头是管头（38），往右是横管（20）
	check("the middle pipe starts with a cap", back.get(Vector2i(12, 8)) == 38, str(back.get(Vector2i(12, 8))))
	check("and runs on as a straight pipe", back.get(Vector2i(16, 8)) == 20, str(back.get(Vector2i(16, 8))))


func test_a_railing_runs_along_the_top_floor() -> void:
	await open_demo()
	var rail: Array[String] = []
	for prop in main.get_node("Props").get_children():
		var file := (prop as Sprite2D).texture.resource_path.get_file()
		if file.begins_with("fence"):
			rail.append(file)
	check("a railing with two ends and a middle", rail.size() >= 3 and rail.count("fence.png") == 1
		and rail.count("fence_end.png") == 1, str(rail))
