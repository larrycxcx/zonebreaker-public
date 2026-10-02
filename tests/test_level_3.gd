extends "res://tests/test_level_1.gd"
## 正式第三关（`scenes/level_3.tscn`，酒吧街）。
##
## 几何检查整套从第一关那组继承（见 `test_level_2.gd` 开头那段）。这里只写**这一关独有的**。

const LEVEL_INFO := "res://levels/level_3.tres"


func level_path() -> String:
	return "res://scenes/level_3.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


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


func test_the_terrain_wears_the_bar_street_art() -> void:
	await open_level()
	var checked := 0
	for node in terrain():
		var visual := (node as Platform).get_node("Visual")
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes its art from this zone" % node.name,
				texture != null and texture.resource_path.begins_with("res://skins/bar_street"),
				str(texture))
	check("setup: the terrain is skinned at all", checked > 20, str(checked))


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
	# 二阶段 260 / 0.7 × 0.9 ≈ 334px，加上地盘本身 220，离出生点 550 以内都可能滚到。
	# 这一片里有坑它会自己滚下去摔死；有墙会挡住它看玩家的视线（它就什么都不做）。
	await open_level()
	var boss := the_boss()
	check("there is a boss", boss != null)
	if boss == null:
		return
	check("it stands on the ground", boss.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	var reach := 600.0
	var left := boss.position.x - reach
	for pit in pits():
		check("no pit within its reach (%.0f)" % pit.x, pit.y < left or pit.x > boss.position.x + reach,
			"pit %.0f..%.0f, boss at %.0f" % [pit.x, pit.y, boss.position.x])
	for node in standing_solids():
		var slab := node as Platform
		check("nothing solid stands in the arena (%s)" % slab.name,
			slab.position.x + slab.size.x < left or slab.position.x > boss.position.x + reach,
			"%s at %.0f, boss at %.0f" % [slab.name, slab.position.x, boss.position.x])


# ---------------------------------------------------------------- 夜景：楼面和光照层

func facades() -> Array[Prop]:
	var out: Array[Prop] = []
	for node in props():
		if String(node.name).begins_with("Facade"):
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
	# 先声明的先画：楼要排在吧台、酒桶、招牌前面，不然一栋楼把它们全盖住
	await open_level()
	var last_facade := -1
	var first_other := 1 << 30
	for node in props():
		if String(node.name).begins_with("Facade"):
			last_facade = maxi(last_facade, node.get_index())
		else:
			first_other = mini(first_other, node.get_index())
	check("every building is drawn before the small props", last_facade < first_other,
		"%d vs %d" % [last_facade, first_other])


func test_no_building_stands_over_a_pit() -> void:
	await open_level()
	var runs := ground_runs()
	for facade in facades():
		var left := facade.position.x
		var right := left + facade.texture.get_width()
		var on_ground := false
		for run in runs:
			if run.x <= left and right <= run.y:
				on_ground = true
		check("%s stands on solid ground" % facade.name, on_ground,
			"%.0f..%.0f" % [left, right])
		check("%s has its feet on the street" % facade.name,
			absf(facade.position.y - GROUND_Y) < 0.5, str(facade.position.y))


func test_the_neon_light_falls_on_the_set_not_on_the_cast() -> void:
	# 光照层要夹在地形和人中间：背景、楼、装饰、地形被染色，人和子弹保持原色，
	# 染了色的人糊在霓虹里就看不清了
	await open_level()
	var light := main.get_node_or_null("Lighting")
	check("the level is lit", light is ScreenLight, str(light))
	if light == null:
		return
	var at := light.get_index()
	check("over the scenery", main.get_node("Props").get_index() < at)
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
	# 跑到关卡中间去，光照层要跟着摄像机走、整块盖住画面
	player.global_position = Vector2(6400, 200)
	await frames(30)
	var viewport := light.get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	var covered := Rect2(light.global_position, light.size)
	check("it follows the camera and covers the whole view", covered.encloses(view),
		"%s vs %s" % [covered, view])


func test_the_test_level_stays_unlit() -> void:
	# 光照是素材包的事：默认包没有，测试关上就不该冒出这一层
	await reset_scene()
	check("no lighting on the default pack", main.get_node_or_null("Lighting") == null)
