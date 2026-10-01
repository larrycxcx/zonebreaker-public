extends GameTest
## 酒吧街素材包（第三关那一套，`tools/terrain_build.py` 从 Bar Street Tileset 生成）。
##
## 守的和工业区那组是同一批：**一个区只装自己独有的、其余顺着 fallback 拿**、
## 地砖别挑成半格的、背景补到画面底、换皮肤不改变规则。
## 这一关独有的一条：**这套素材是「街景立面」不是地形包**（砖墙、窗、卷帘、遮阳棚），
## 所以挑出来的三种地形是「砖地 / 遮阳棚 / 卷帘门」，不是「草地 / 浮台 / 石砖」。

const PACK := "res://skins/bar_street/bar_street_skin.tres"
const ART := "res://skins/bar_street"
const SCREEN_HEIGHT := 360


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func zone_art(rel: String) -> Image:
	return (load("%s/%s" % [ART, rel]) as Texture2D).get_image()


func platforms() -> Array[Platform]:
	var out: Array[Platform] = []
	for node in main.get_node("Level").find_children("*", "Platform", true, false):
		out.append(node as Platform)
	return out


# ---------------------------------------------------------------- 只装自己独有的

func test_the_pack_brings_terrain_a_backdrop_and_its_own_track() -> void:
	var mine := pack()
	var keys: Array[String] = []
	for key: StringName in mine.appearances:
		keys.append(String(key))
	keys.sort()
	check("it declares the three terrains", keys == ["terrain_ground", "terrain_ledge", "terrain_stone"],
		str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("bar_street"), str(mine.backdrop))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"enemy_bullet", &"player_grenade"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)


func test_the_track_is_this_zone_and_loops_cleanly() -> void:
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	# **循环的曲子必须是 OGG**：MP3 编码器会在开头结尾各补一小段静音，转一圈能听出来接缝
	check("and it is an ogg", track is AudioStreamOggVorbis, track.get_class())


func test_each_zone_plays_its_own_track() -> void:
	var heard := {}
	for path: String in [PACK, "res://skins/industrial/industrial_skin.tres",
			"res://skins/cyberpunk/cyberpunk_skin.tres"]:
		Skins.use(load(path) as SkinPack)
		var track := Skins.music(&"level")
		check("%s has level music" % path.get_file(), track != null)
		if track != null:
			heard[track.resource_path] = true
	check("three zones, three different tracks", heard.size() == 3, str(heard.keys()))


# ---------------------------------------------------------------- 地砖挑得对不对

func test_the_terrain_art_is_this_zone_and_not_another() -> void:
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	# 这套里 16 高的薄条（遮阳棚）和整砖混在一起。拿薄条当地面顶砖的话上半截是透明的。
	for name: String in ["ground", "ledge", "stone"]:
		var img := zone_art("terrain/%s.png" % name)
		var empty := 0
		for y in img.get_height():
			var blank := true
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					blank = false
					break
			if blank:
				empty += 1
		check("%s has no blank rows" % name, empty == 0, "%d 行是空的（%dx%d）"
			% [empty, img.get_width(), img.get_height()])


func test_the_backdrop_reaches_the_bottom_of_the_screen() -> void:
	# 素材只有 324 高，关卡里有坑，坑那一块会露出清屏色——生成时往下补到画面底。
	for layer: String in ["sky", "far", "mid", "near", "street"]:
		var img := zone_art("backdrop/%s.png" % layer)
		check("%s covers the whole screen" % layer, img.get_height() >= SCREEN_HEIGHT,
			"%dx%d" % [img.get_width(), img.get_height()])
	var back := zone_art("backdrop/sky.png")
	var gaps := 0
	for x in back.get_width():
		if back.get_pixel(x, SCREEN_HEIGHT - 1).a < 1.0:
			gaps += 1
	check("the backmost layer is solid along the bottom row, so pits never show the clear colour",
		gaps == 0, "%d 列是透的" % gaps)


# ---------------------------------------------------------------- 接上去以后

func test_every_platform_wears_this_zone_terrain() -> void:
	await reset_scene(true, true, pack())
	var checked := 0
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s wears terrain art" % p.name, visual is TerrainAppearance, str(visual))
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes it from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))
	check("setup: the terrain is skinned at all", checked > 5, str(checked))


func test_the_backdrop_goes_in_behind_everything() -> void:
	await reset_scene(true, true, pack())
	var backdrop := main.get_node_or_null("Backdrop")
	check("the level gets a backdrop", backdrop != null)
	if backdrop == null:
		return
	check("drawn first, behind everything", backdrop.get_index() == 0, str(backdrop.get_index()))
	check("it has parallax layers", backdrop.find_children("*", "Parallax2D", true, false).size() == 5)
	check("and no collision at all",
		backdrop.find_children("*", "CollisionObject2D", true, false).is_empty()
		and backdrop.find_children("*", "CollisionShape2D", true, false).is_empty())


# ---------------------------------------------------------------- 换皮肤不改变规则

func measure(skin: SkinPack) -> Dictionary:
	await reset_scene(false, true, skin)
	var out := {}
	var shapes := []
	for p in platforms():
		var shape := p.get_node("CollisionShape2D") as CollisionShape2D
		shapes.append([String(p.name), p.global_position + shape.position,
			(shape.shape as RectangleShape2D).size, shape.one_way_collision])
	out["platforms"] = str(shapes)
	player.global_position = Vector2(208, 200)
	player.velocity = Vector2.ZERO
	await frames(40)
	out["stands_on_ledge_at"] = snappedf(player.global_position.y, 0.01)
	out["on_floor"] = player.is_on_floor()
	player.global_position = Vector2(560, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(150)
	release_all_input()
	out["crawled_to"] = snappedf(player.global_position.x, 1.0)
	return out


func test_this_zone_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var street := await measure(pack())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0,
		str(blocks))
	for key: String in blocks:
		check("%s is the same in this zone" % key, blocks[key] == street[key],
			"方块 %s，酒吧街 %s" % [blocks[key], street[key]])
