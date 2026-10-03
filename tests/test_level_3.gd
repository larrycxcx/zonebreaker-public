extends "res://tests/layered_checks.gd"
## 正式第三关（`scenes/level_3.tscn`，酒吧街）——2026-10 起是**分层的格子地图**
## （`tools/level3_map.py` 画、`tools/map_build.py` 查路和写场景，砖用 `THEMES["bar"]`）。
## 分层关共用的检查在 `layered_checks.gd`；这里只写**这一关独有的**：夜景（楼面、光照层）、
## 贴地开枪的鲨鱼机、独轮机甲那片空地，以及拿真规则跑几处必须绕的路。

const LEVEL_INFO := "res://levels/level_3.tres"


func level_path() -> String:
	return "res://scenes/level_3.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "bar_street"


func the_boss() -> Boss:
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			return node
	return null


func test_it_is_the_third_stage_in_the_catalog() -> void:
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and it brings the bar street pack", info.skin != null
		and info.skin.resource_path.contains("bar_street"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up as the third one",
		levels.size() >= 3 and levels[2].scene_path == level_path(),
		"" if levels.size() < 3 else levels[2].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("3_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 3", wrong.is_empty(), str(wrong))
	check("and all six types plus the boss show up", kinds.size() >= 7, str(kinds.keys()))


func test_the_low_shooters_sit_on_the_ground_not_in_it() -> void:
	# 3-E 只有 12 高，脚底在原点下方 6（别人是 16）。按别人的高度摆会陷进地里 10px，
	# 「脚下有面」那条只看得出悬空，看不出陷进去——所以这里真跑一下，它不该被地面顶动
	await open_level()
	var sharks: Array[Enemy] = []
	for enemy in enemies():
		if enemy.skin_key == &"3_e":
			sharks.append(enemy)
	check("setup: there are sharks", sharks.size() >= 5, str(sharks.size()))
	var start := {}
	for shark in sharks:
		start[shark] = shark.position
	await frames(30)
	for shark in sharks:
		check("%s stays put" % shark.name, shark.position.distance_to(start[shark]) < 1.0,
			"%s -> %s" % [start[shark], shark.position])


func test_the_boss_has_clear_flat_ground_to_roll_on() -> void:
	# 独轮机甲**站在地上**，冲撞那一下不受地盘限制（一直滚到时间到或者撞墙）：
	# 二阶段约 334px，加上地盘本身 220，离出生点 550 以内都可能滚到。
	# 这一片里有坑它会自己滚下去摔死；有墙会挡住它看玩家的视线（它就什么都不做）。
	await open_level()
	var boss := the_boss()
	check("there is a boss", boss != null)
	if boss == null:
		return
	check("it stands on the ground", boss.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	var reach := 600.0
	for pit in pits():
		check("no pit within its reach (%.0f)" % pit.x, pit.y < boss.position.x - reach
			or pit.x > boss.position.x + reach,
			"pit %.0f..%.0f, boss at %.0f" % [pit.x, pit.y, boss.position.x])
	for rect in solid_rects():
		if rect.end.y <= GROUND_Y + 0.5 and rect.position.y > 0.0 \
				and rect.end.x > boss.position.x - reach and rect.position.x < boss.position.x + reach:
			check("nothing solid stands in the arena", false, "%s, boss at %.0f" % [rect, boss.position.x])


# ---------------------------------------------------------------- 夜景：楼面和光照层

func facades() -> Array[Prop]:
	var out: Array[Prop] = []
	for node in props():
		if (node as Prop).texture.resource_path.get_file().begins_with("facade_"):
			out.append(node)
	return out


func test_the_street_is_lined_with_buildings() -> void:
	# 宣传图里街边那排楼：素材包只给了砖，楼是 terrain_build.py 拼出来的
	await open_level()
	var found := facades()
	check("there are buildings along the street", found.size() >= 30, str(found.size()))
	for facade in found:
		check("%s comes from this zone" % facade.name,
			facade.texture.resource_path.begins_with("res://skins/bar_street/props/facade_"),
			facade.texture.resource_path)


func test_the_buildings_stand_behind_the_rest_of_the_scenery() -> void:
	# 先摆的先画：楼要排在吧台、酒桶、招牌前面，不然一栋楼把它们全盖住
	await open_level()
	var last_facade := -1
	var first_other := 1 << 30
	for node in props():
		if (node as Prop).texture.resource_path.get_file().begins_with("facade_"):
			last_facade = maxi(last_facade, node.get_index())
		else:
			first_other = mini(first_other, node.get_index())
	check("every building is drawn before the small props", last_facade < first_other,
		"%d vs %d" % [last_facade, first_other])


func test_no_building_stands_over_a_pit() -> void:
	# 楼的整个底边都要落在同一块面上（街面、骑楼顶），悬在坑上看着就是一栋飘着的楼
	await open_level()
	var faces := surfaces()
	for facade in facades():
		var left := facade.position.x
		var right := left + facade.texture.get_width() / float(facade.frames)
		var on_ground := false
		for face in faces:
			if face[0] <= left + 0.5 and right <= face[1] + 0.5 and absf(face[2] - facade.position.y) < 0.5:
				on_ground = true
		check("%s stands on something along its whole width" % facade.name, on_ground,
			"%.0f..%.0f at %.0f" % [left, right, facade.position.y])


func test_no_building_is_drawn_over_an_indoor_wall() -> void:
	# 楼面画在室内墙那一层上面：摆进楼里（头顶有楼板的地方）就把墙盖住了
	await open_level()
	var solids := solid_rects()
	for facade in facades():
		var middle := facade.position.x + facade.texture.get_width() / float(facade.frames) / 2.0
		var roofed := false
		for rect in solids:
			if rect.position.x <= middle and middle <= rect.end.x and rect.end.y <= facade.position.y - 32.0 \
					and rect.position.y > 0.0:
				roofed = true
		check("%s stands in the open" % facade.name, not roofed, "x %.0f" % middle)


func test_the_neon_light_falls_on_the_set_not_on_the_cast() -> void:
	# 光照层要夹在地形和人中间：背景、楼、装饰、地形被染色，人和子弹保持原色
	await open_level()
	var light := main.get_node_or_null("Lighting")
	check("the level is lit", light is ScreenLight, str(light))
	if light == null:
		return
	var at := light.get_index()
	check("over the scenery", main.get_node("Props").get_index() < at)
	check("over the tiles", main.get_node("FrontTiles").get_index() < at)
	check("over the terrain", main.get_node("Level").get_index() < at)
	check("under the enemies", at < main.get_node("Enemies").get_index())
	check("under the player", at < main.get_node("Player").get_index())
	check("under the effects", at < main.get_node("Fx").get_index())


func test_the_light_is_pure_decoration_and_covers_the_screen() -> void:
	await open_level()
	var light := main.get_node_or_null("Lighting") as ScreenLight
	check("setup: the level is lit", light != null)
	if light == null:
		return
	check("it never takes the mouse", light.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var stack: Array[Node] = [light]
	var shapes := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D or node is CollisionShape2D:
			shapes += 1
		stack.append_array(node.get_children())
	check("and has nothing to collide with", shapes == 0, str(shapes))
	player.global_position = Vector2(6400, 200)
	await frames(30)
	var viewport := light.get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	var covered := Rect2(light.global_position, light.size)
	check("it follows the camera and covers the whole view", covered.encloses(view),
		"%s vs %s" % [covered, view])


func test_the_test_level_stays_unlit() -> void:
	await reset_scene()
	check("no lighting on the default pack", main.get_node_or_null("Lighting") == null)


# ---------------------------------------------------------------- 装饰里不许有像拾取物的东西

## 2026-10 试玩反馈：酒瓶、酒杯、飞钞、飘牌摆在地上看着就像能捡的东西。
## 分层版截图又看出两样：`bin`（其实是一个牛头骨）和 `crate`（一把平放的刀），小小一个摆满地板。
const PICKUP_LOOKALIKES := ["bottle", "glass", "money", "card", "bin", "crate"]


func test_nothing_lying_around_looks_like_a_pickup() -> void:
	await open_level()
	check("setup: the street is dressed", props().size() >= 100, str(props().size()))
	for node in props():
		var path := (node as Sprite2D).texture.resource_path.get_file()
		for word: String in PICKUP_LOOKALIKES:
			check("%s is not a %s" % [node.name, word], not path.begins_with(word), path)


## 基类那条查「会动的装饰真的在动」。这一关会动的两件（飞钞、飘牌）正是像拾取物的那两样，
## 已经拿掉了，所以改成反过来守：**没有**会动的装饰混进来。
func test_the_fountain_actually_runs() -> void:
	await open_level()
	for node in props():
		check("%s stays still" % node.name, (node as Prop).frames <= 1, str((node as Prop).frames))


# ---------------------------------------------------------------- 必须绕的路，拿真规则跑一遍

func climb(direction: StringName) -> void:
	Input.action_press(direction)
	for i in 180:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func push_right(frames_held := 150, jumping := true) -> void:
	Input.action_press(&"move_right")
	if jumping:
		Input.action_press(&"jump")
	await frames(frames_held)
	release_all_input()


func test_the_first_bar_is_a_dead_end_downstairs() -> void:
	# 第 1 段：酒吧一楼走到头是墙，顺梯子上二楼
	await open_empty()
	player.global_position = Vector2(col_x(1, 60), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("walking and jumping right gets you nowhere", player.global_position.x < col_x(1, 70),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(1, 65), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the ladder takes you upstairs", absf(feet() - MIDDLE_FLOOR) < 1.0, "feet %.1f" % feet())


func test_the_cellar_is_shuttered_from_the_street() -> void:
	# 第 3 段：地窖临街那一面是拉下来的卷帘，从街上进不去；酒吧里往右走到头，活板门掉进地窖
	await open_empty()
	player.global_position = Vector2(col_x(3, 0) - 40.0, GROUND_Y - 16.0)
	await frames(3)
	await push_right(90, false)
	check("the shutter keeps you out", player.global_position.x < col_x(3, 3),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 44), MIDDLE_FLOOR - 16.0)
	await frames(3)
	await push_right()
	check("the bar ends at a wall", player.global_position.x < col_x(3, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 41), MIDDLE_FLOOR - 16.0)
	await frames(60)
	check("the trapdoor drops you into the cellar", absf(feet() - GROUND_Y) < 1.0, "feet %.1f" % feet())


func test_the_street_ends_below_the_rooftops() -> void:
	# 第 7 段：街到这儿是死路（第一栋楼的墙一直落到地上），顺消防梯爬上屋顶
	await open_empty()
	player.global_position = Vector2(col_x(7, 3), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("the first building walls off the street", player.global_position.x < col_x(7, 10),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(7, 9), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the fire escape takes you to the roof", absf(feet() - 8 * CELL) < 1.0, "feet %.1f" % feet())


func test_the_alley_is_sealed_with_crates() -> void:
	# 第 9 段：后巷里两摞箱子把路堵死，打烂才过得去
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - col_x(9, 26)) < 1.0:
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 3, str(stack.size()))
	player.global_position = Vector2(col_x(9, 20), GROUND_Y - 16.0)
	await frames(3)
	await push_right(120)
	check("you cannot get past the stack", player.global_position.x < col_x(9, 26),
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	await push_right(60, false)
	check("shot apart, the way is open", player.global_position.x > col_x(9, 30),
		"x %.0f" % player.global_position.x)
