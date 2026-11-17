extends GameTest
## 赛博朋克皮肤包的地形和背景（tools/terrain_build.py 从 Green Zone Tileset 生成）。
##
## 地形不换 TileMap：还是 platform.tscn 搭的关卡，外观按平台大小九宫格平铺（TerrainAppearance）。
## 守的东西：九宫格怎么切是对的（铺满、不缩放、头尾描边都在）、每块平台挑对了地形、画面和判定框对得上
## （站立面就是判定框顶边，只有浮空平台底下的碎块往下挂几像素；矮通道顶块底边是平的，净空看着和实际一样），
## 以及**换皮肤不改变规则**——所有平台的碰撞体、站在平台上的高度、矮通道能不能过，方块和精灵图一模一样。
## 背景纯显示、在最底下，默认包没有背景。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func platforms() -> Array[Platform]:
	var out: Array[Platform] = []
	for node in main.get_node("Level").find_children("*", "Platform", true, false):
		out.append(node as Platform)
	return out


# ---------------------------------------------------------------- 九宫格怎么切

func test_pieces_cover_the_length_without_scaling() -> void:
	# 各种长度都要：从 0 连续铺到头、不重叠，每段取的源图都在源图里面（源图段和目标段一样长 = 只裁不缩）
	for case in [[96, 96, 32, 32], [112, 96, 32, 32], [128, 96, 32, 32], [16, 32, 3, 3], [8, 32, 3, 3],
			[40, 64, 32, 0], [1280, 32, 0, 0], [22, 32, 10, 12], [50, 32, 10, 3], [4, 32, 3, 3]]:
		var parts: Array = TerrainAppearance.pieces(case[0], case[1], case[2], case[3])
		var at := 0
		var ok := true
		for part in parts:
			ok = ok and part[0] == at and part[1] > 0 and part[2] >= 0 and part[2] + part[1] <= case[1]
			at += part[1]
		check("pieces %s tile the whole length" % [case], ok and at == case[0], str(parts))


func test_the_ends_keep_their_outline() -> void:
	# 头一段从源图第 0 列开始、尾一段以源图最后一列结束：平台两头的描边、圆角永远画得出来
	for case in [[112, 96, 32, 32], [8, 32, 3, 3], [22, 32, 10, 12]]:
		var parts: Array = TerrainAppearance.pieces(case[0], case[1], case[2], case[3])
		var last: Array = parts[-1]
		check("pieces %s start at the source's first column" % [case], parts[0][2] == 0, str(parts))
		check("pieces %s end at the source's last column" % [case], last[2] + last[1] == case[1], str(parts))


# ---------------------------------------------------------------- 接上去以后

func test_every_platform_wears_the_right_terrain() -> void:
	if needs_art(): return
	await reset_scene(true, true, skin())
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s is drawn by the skin" % p.name, visual is TerrainAppearance, str(visual))
		var want := &"terrain_ground" if p.name == "Ground" else (&"terrain_ledge" if p.one_way else &"terrain_stone")
		check("%s uses %s" % [p.name, want], p.terrain_key() == want, str(p.terrain_key()))
		if visual is TerrainAppearance:
			var look := visual as TerrainAppearance
			check("%s: the art is as wide as the platform" % p.name, look.drawn_size().x == roundi(p.size.x),
				"%s vs %s" % [look.drawn_size(), p.size])
			check("%s: the art starts at the platform's top-left (you stand on its top edge)" % p.name,
				look.position == Vector2.ZERO)
			check("%s: the art has no collision" % p.name,
				look.find_children("*", "CollisionObject2D", true, false).is_empty()
				and look.find_children("*", "CollisionShape2D", true, false).is_empty())


func test_only_ledges_hang_below_their_hitbox() -> void:
	await reset_scene(true, true, skin())
	for p in platforms():
		var look := p.get_node("Visual") as TerrainAppearance
		if look == null:
			continue
		var below := look.drawn_size().y - roundi(p.size.y)
		if p.one_way:
			# 浮空平台底下挂着碎块：只挂几像素，平台看起来不会比判定厚太多
			check("%s hangs only a little below its hitbox" % p.name, below > 0 and below <= 6, "%dpx" % below)
		else:
			# 实心块底边是平的：矮通道画出来的净空和实际一样
			check("%s ends exactly at its hitbox" % p.name, below == 0, "%dpx" % below)


func test_walls_built_in_tests_get_the_terrain_too() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	var wall := add_wall(400, 40)
	await frames(1)
	var look := wall.get_node("Visual") as TerrainAppearance
	check("a wall added later is drawn as stone", look != null and wall.terrain_key() == &"terrain_stone", str(wall.get_node("Visual")))
	if look != null:
		check("and fits the wall", look.drawn_size() == Vector2i(8, 40), str(look.drawn_size()))


func test_the_default_pack_keeps_the_blocks() -> void:
	await reset_scene(true, true)
	for p in platforms():
		check("%s keeps its placeholder block" % p.name, not (p.get_node("Visual") is TerrainAppearance))
	check("and there is no backdrop", main.get_node_or_null("Backdrop") == null)


func test_the_backdrop_is_behind_everything_and_pure_display() -> void:
	if needs_art(): return
	await reset_scene(true, true, skin())
	var backdrop := main.get_node_or_null("Backdrop")
	check("the skin puts a backdrop in the level", backdrop != null)
	if backdrop == null:
		return
	check("drawn first, behind everything", backdrop.get_index() == 0, str(backdrop.get_index()))
	check("it has parallax layers", backdrop.find_children("*", "Parallax2D", true, false).size() >= 4)
	check("it has no collision",
		backdrop.find_children("*", "CollisionObject2D", true, false).is_empty()
		and backdrop.find_children("*", "CollisionShape2D", true, false).is_empty())


# ---------------------------------------------------------------- 换皮肤不改变规则

func measure(pack: SkinPack) -> Dictionary:
	await reset_scene(false, true, pack)
	var out := {}
	var shapes := []
	for p in platforms():
		var shape := p.get_node("CollisionShape2D") as CollisionShape2D
		shapes.append([String(p.name), p.global_position + shape.position, (shape.shape as RectangleShape2D).size, shape.one_way_collision])
	out["platforms"] = str(shapes)
	# 落在一块浮空平台上：站的高度
	player.global_position = Vector2(208, 200)
	player.velocity = Vector2.ZERO
	await frames(40)
	out["stands_on_ledge_at"] = snappedf(player.global_position.y, 0.01)
	out["on_floor"] = player.is_on_floor()
	# 趴着钻矮通道：能从左边爬到右边
	player.global_position = Vector2(560, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(150)
	release_all_input()
	out["crawled_to"] = snappedf(player.global_position.x, 1.0)
	return out


func test_the_terrain_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var sprites := await measure(skin())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0, str(blocks))
	for key: String in blocks:
		check("%s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])
