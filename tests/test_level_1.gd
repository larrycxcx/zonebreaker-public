extends "res://tests/layered_checks.gd"
## 正式第一关（`scenes/level_1.tscn`，绿区）——2026-10 起是**分层的格子地图**
## （`tools/level1_map.py` 画、`tools/map_build.py` 查路和写场景，砖用绿区那套 `THEMES["green"]`）。
## 分层关共用的检查在 `layered_checks.gd`；这里只写**这一关独有的**，下半截拿真规则把几处必须绕的路跑一遍。

const LEVEL_INFO := "res://levels/level_1.tres"


func level_path() -> String:
	return "res://scenes/level_1.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "cyberpunk"


## 这一关的地面只断开两处（大坑、空岛），别的「低处」都是山洞——不是坑
func min_pits() -> int:
	return 2


func boss() -> Boss:
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			return node
	return null


# ---------------------------------------------------------------- 这一关自己的

func test_it_is_the_first_stage_in_the_catalog() -> void:
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and brings the green zone pack", info.skin != null
		and info.skin.resource_path.contains("cyberpunk"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog lists it first", not levels.is_empty() and levels[0].scene_path == level_path(),
		"" if levels.is_empty() else levels[0].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("1_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 1", wrong.is_empty(), str(wrong))
	check("and all seven types plus the boss show up", kinds.size() >= 8, str(kinds.keys()))


func test_crates_and_barrels_wear_the_pack_art() -> void:
	# 赛博朋克包（绿区）原来没有这两样，占位色块混在像素画里一眼就看得出来
	await open_level()
	var crates := 0
	var barrels := 0
	for node in main.get_node("Traps").get_children():
		if node is BreakableCrate or node is ExplosiveBarrel:
			var visual := (node as Node).get_node("Visual")
			check("%s is drawn from the pack" % node.name, visual is CrateSpriteAppearance, str(visual))
			if node is BreakableCrate:
				crates += 1
			else:
				barrels += 1
	check("setup: there are crates and barrels", crates >= 6 and barrels >= 6, "%d / %d" % [crates, barrels])


func test_the_boss_arena_is_flat_open_ground() -> void:
	# Boss A 站在地上、在出生点左右 160 里走位、还会跳：那片地上不能有坑，也不能有挡视线的墙
	# （视线从身体中心发出，被墙挡住它就什么都不做）；头顶要有台子给玩家躲扇形
	await open_level()
	var b := boss()
	check("there is a boss", b != null)
	if b == null:
		return
	check("it stands on the ground", absf(enemy_feet(b) - GROUND_Y) < 1.0, "%.1f" % enemy_feet(b))
	for pit in pits():
		check("no pit near it (%.0f..%.0f)" % [pit.x, pit.y], pit.y < b.position.x - 480.0
			or pit.x > b.position.x + 480.0)
	for rect in solid_rects():
		if rect.end.y <= GROUND_Y - 0.5 and rect.position.y > 0.0 \
				and rect.end.x > b.position.x - 400.0 and rect.position.x < b.position.x + 400.0:
			check("nothing solid stands in its arena", false, str(rect))
	var above := 0
	for face in surfaces():
		if face[2] < GROUND_Y and face[1] > b.position.x - 400.0 and face[0] < b.position.x + 400.0:
			above += 1
	check("there are platforms above the arena", above >= 4, str(above))


# ---------------------------------------------------------------- 必须绕的路，拿真规则跑一遍

func climb(direction: StringName) -> void:
	Input.action_press(direction)
	for i in 180:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func test_the_rock_in_the_park_is_climbed_not_jumped() -> void:
	# 第 1 段：石山从第 8 行一直到地面（高过一跳），只能顺左边的梯子上去
	await open_empty()
	player.global_position = Vector2(col_x(1, 40), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(150)
	release_all_input()
	check("walking and jumping into it gets you nowhere", player.global_position.x < col_x(1, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(1, 47), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the ladder takes you to the top of the rock", absf(feet() - 8 * CELL) < 1.0, "feet %.1f" % feet())


func test_the_burrow_mouth_is_sealed_and_the_hilltop_ends_at_a_cliff() -> void:
	# 第 3 段：洞口被石头封死，得先上山顶；山顶又被石崖挡住，得从地上的口子掉进洞里
	await open_empty()
	player.global_position = Vector2(col_x(3, 0) - 40.0, GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	await frames(90)
	release_all_input()
	check("the cave mouth is walled up", player.global_position.x < col_x(3, 3),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 44), MIDDLE_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(150)
	release_all_input()
	check("the cliff on the hilltop stops you", player.global_position.x < col_x(3, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 41), MIDDLE_FLOOR - 16.0)
	await frames(60)
	check("the gap in the hilltop drops you into the cave", absf(feet() - GROUND_Y) < 1.0,
		"feet %.1f" % feet())


func test_the_chasm_cannot_be_jumped_from_the_ground() -> void:
	# 第 4 段：地面断开 48 格，助跑跳也过不去，得爬梯子上那一串台子
	await open_empty()
	player.global_position = Vector2(col_x(4, 6), GROUND_Y - 16.0)
	await frames(3)
	var hp := player.health
	Input.action_press(&"sprint")
	Input.action_press(&"move_right")
	await frames(30)
	Input.action_press(&"jump")
	await frames(90)
	release_all_input()
	await frames(30)
	check("a running jump ends in the chasm", player.health < hp or player.global_position.x < col_x(4, 64),
		"x %.0f hp %d" % [player.global_position.x, player.health])


func test_the_tunnel_is_sealed_with_crates() -> void:
	# 第 9 段：地道里两摞箱子把路堵死，打烂才过得去
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - col_x(9, 26)) < 1.0:
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 3, str(stack.size()))
	player.global_position = Vector2(col_x(9, 20), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(120)
	release_all_input()
	check("you cannot get past the stack", player.global_position.x < col_x(9, 26),
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	Input.action_press(&"move_right")
	await frames(60)
	release_all_input()
	check("shot apart, the way is open", player.global_position.x > col_x(9, 30),
		"x %.0f" % player.global_position.x)
