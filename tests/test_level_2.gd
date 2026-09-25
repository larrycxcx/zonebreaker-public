extends "res://tests/test_level_1.gd"
## 正式第二关（`scenes/level_2.tscn`，工业区）。
##
## **整套几何检查是从第一关那组继承下来的**——坑跳得过去、墙翻得过去、堵块有高路、
## 矮通道净空还是 30、敌人没悬空也没塞进矮通道、装饰没有碰撞、没有重名、关卡自己跑得起来。
## 每加一关都把那些重写一遍，迟早会漏掉一条。这里只写**这一关独有的**。

const LEVEL_INFO := "res://levels/level_2.tres"


func level_path() -> String:
	return "res://scenes/level_2.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func hanging() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in main.get_node("Enemies").get_children():
		var enemy := node as EnemyDropper
		if enemy != null:
			out.append(enemy)
	return out


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


func test_the_terrain_wears_the_industrial_art() -> void:
	await open_level()
	var checked := 0
	for node in terrain():
		var visual := (node as Platform).get_node("Visual")
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes its art from this zone" % node.name,
				texture != null and texture.resource_path.begins_with("res://skins/industrial"),
				str(texture))
	check("setup: the terrain is skinned at all", checked > 20, str(checked))


func test_the_workers_hang_above_the_screen_over_solid_ground() -> void:
	# 2-A 是这一关的伏击：摆在画面顶边以上，玩家一路走过来什么也看不见。
	# **底下得是实地**——吊在坑上面的话，它掉下去就摔死了，伏击白布置。
	await open_level()
	var found := hanging()
	check("there are ambushers", found.size() >= 3, str(found.size()))
	for worker in found:
		check("%s hangs off the top of the screen" % worker.name, worker.position.y < 0.0,
			str(worker.position))
		var over_ground := false
		for run in ground_runs():
			if run.x <= worker.position.x and worker.position.x <= run.y:
				over_ground = true
		check("%s has solid ground to land on" % worker.name, over_ground,
			"x %.0f" % worker.position.x)


func test_the_ambush_holds_until_you_walk_under_it() -> void:
	# 上一条量的是位置，这一条是真跑：从出生点站着不动，没人该掉下来
	await open_level()
	await frames(120)
	for worker in hanging():
		check("%s is still up there" % worker.name, not worker.has_dropped
			and worker.position.y < 0.0, str(worker.position))


func test_the_boss_has_platforms_to_climb() -> void:
	# Boss 飘在空中、不追出地盘（见 boss_operator.gd），所以**玩家得跳上去才够得着它**。
	# 它那块地盘周围没有浮台的话，这场仗就只能站在地上挨打。
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
		# 它的地盘是以出生点为中心的一块，浮台要在这一块的左右范围里
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
	# 每关的敌人是各自的一套（血量伤害直接写在各自的场景里），第一关那批不该混进来
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
