extends "res://tests/layered_checks.gd"
## 正式第二关（`scenes/level_2.tscn`，工业区）——2026-10 起是**分层的格子地图**
## （`tools/level2_map.py` 画、`tools/map_build.py` 查路和写场景）。
## 分层关共用的检查在 `layered_checks.gd`；这里只写**这一关独有的**，下半截拿真规则把几处必须绕的路跑一遍。

const LEVEL_INFO := "res://levels/level_2.tres"


func level_path() -> String:
	return "res://scenes/level_2.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "industrial"


func hanging() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in main.get_node("Enemies").get_children():
		var enemy := node as EnemyDropper
		if enemy != null:
			out.append(enemy)
	return out


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
