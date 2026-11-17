extends GameTest
## 地下室素材包（第四关那一套，`tools/terrain_build.py basement` 从 Basement Tileset 生成）。
##
## 和工业区、酒吧街守的是同一批：一个区只装自己独有的、其余顺着 fallback 拿，地砖别挑成半格的。
## 这一关独有的：**关卡是纵向往上爬的**，所以背景不是横着视差滚动，而是一面拼出来的内墙
## **竖着无缝平铺**；以及「像拾取物的东西不要」（Card / Money、墙上那些小灯）。

const PACK := "res://skins/basement/basement_skin.tres"
const ART := "res://skins/basement"
const SCREEN := Vector2(640, 360)


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func zone_art(rel: String) -> Image:
	return (load("%s/%s" % [ART, rel]) as Texture2D).get_image()


# ---------------------------------------------------------------- 只装自己独有的

func test_the_pack_brings_terrain_a_backdrop_light_and_its_own_track() -> void:
	if needs_art(): return
	var mine := pack()
	for key: StringName in [&"terrain_ground", &"terrain_ledge", &"terrain_stone"]:
		check("it declares %s" % key, mine.appearances.has(key))
	check("a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("basement"), str(mine.backdrop))
	check("a light of its own", mine.lighting != null
		and mine.lighting.resource_path.contains("basement"), str(mine.lighting))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	if needs_art(): return
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"enemy_bullet", &"player_grenade"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)


func test_the_track_is_this_zone_and_loops_cleanly() -> void:
	if needs_art(): return
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	check("and it is an ogg", track is AudioStreamOggVorbis, track.get_class())


func test_each_zone_plays_its_own_track() -> void:
	if needs_art(): return
	var heard := {}
	for path: String in [PACK, "res://skins/bar_street/bar_street_skin.tres",
			"res://skins/industrial/industrial_skin.tres", "res://skins/cyberpunk/cyberpunk_skin.tres"]:
		Skins.use(load(path) as SkinPack)
		var track := Skins.music(&"level")
		if track != null:
			heard[track.resource_path] = true
	check("four zones, four different tracks", heard.size() == 4, str(heard.keys()))


# ---------------------------------------------------------------- 地砖

func test_the_terrain_art_is_this_zone_and_not_another() -> void:
	if needs_art(): return
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial", "bar_street"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
	# 41~44 那排薄条只画了上半格，生成时裁到 16 行；裁漏了九宫格会把空白也当成边
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


func test_walls_are_a_full_nine_slice() -> void:
	if needs_art(): return
	# 竖井两侧的墙和堵块都是大块头，要四角、四边、中间齐全才拼得出一整块岩体
	var stone := zone_art("terrain/stone.png")
	check("the stone source is three tiles each way", stone.get_size() == Vector2i(96, 96),
		str(stone.get_size()))
	var ledge := zone_art("terrain/ledge.png")
	check("the ledge is one thin strip", ledge.get_size() == Vector2i(96, 16), str(ledge.get_size()))


# ---------------------------------------------------------------- 背景：竖着铺的内墙

func backdrop_layers() -> Array[Parallax2D]:
	var out: Array[Parallax2D] = []
	var scene := pack().backdrop.instantiate()
	for child in scene.get_children():
		if child is Parallax2D:
			out.append(child)
	(func() -> void: scene.free()).call_deferred()
	return out


func test_the_backdrop_repeats_upwards_without_end() -> void:
	if needs_art(): return
	# 关卡有 20 屏高：背景得竖着重复，而且一层的高度就是重复的间距，否则会露缝或者重叠
	var layers := backdrop_layers()
	check("setup: there are layers", layers.size() >= 2, str(layers.size()))
	for layer in layers:
		var sprite := layer.get_node("Sprite") as Sprite2D
		var size := sprite.texture.get_size()
		check("%s repeats vertically at its own height" % layer.name,
			layer.repeat_size.y == size.y and size.y > 0.0, "%s vs %s" % [layer.repeat_size, size])
		check("%s spans the screen's width" % layer.name, size.x >= SCREEN.x, str(size))
		check("%s scrolls slower than the level, so it sits behind" % layer.name,
			layer.scroll_scale.y > 0.0 and layer.scroll_scale.y < 1.0, str(layer.scroll_scale))


func test_the_back_wall_is_solid() -> void:
	if needs_art(): return
	# 最后面那层是整面墙：哪怕一个像素透了，竖井里就会露出清屏色
	var wall := zone_art("backdrop/wall.png")
	var holes := 0
	for y in wall.get_height():
		for x in wall.get_width():
			if wall.get_pixel(x, y).a < 1.0:
				holes += 1
	check("not a single hole", holes == 0, str(holes))


func test_the_back_wall_sits_behind_the_terrain() -> void:
	if needs_art(): return
	# 墙是往后压暗过的：亮的那一截不到地形的一半，不然平台糊进墙里（不压暗时是 0.27 对 0.41，压了是 0.15）。
	# **比亮的那一截，不比平均**：岩块中间是一大片深紫填充，平均下来本来就暗；
	# 让平台和墙从背景里跳出来的是它那圈浅色描边。
	var wall := _bright_end(zone_art("backdrop/wall.png"))
	for name: String in ["stone", "ledge", "ground"]:
		var rock := _bright_end(zone_art("terrain/%s.png" % name))
		check("the wall is darker than the %s" % name, wall < rock * 0.5,
			"%.3f vs %.3f" % [wall, rock])


## 第 90 百分位的亮度：图里「亮的那部分」有多亮。
func _bright_end(img: Image) -> float:
	var values: Array[float] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				values.append(c.get_luminance())
	values.sort()
	return values[int(values.size() * 0.9)] if not values.is_empty() else 0.0


# ---------------------------------------------------------------- 光照、装饰

func test_the_light_is_the_neon_overlay_of_this_zone() -> void:
	if needs_art(): return
	var light := pack().lighting.instantiate()
	check("it is a screen light", light is ScreenLight, str(light))
	var material := (light as CanvasItem).material as ShaderMaterial
	var glow := material.get_shader_parameter(&"glow") as Texture2D if material != null else null
	check("with this zone's glow", glow != null and glow.resource_path.begins_with(ART), str(glow))
	light.free()


## 第三关的教训：小小一个、亮晶晶地摆在地上的，看着就是能捡的东西。
const PICKUP_LOOKALIKES := ["card", "money", "lamp", "bottle", "glass", "coin"]


func test_no_prop_looks_like_a_pickup() -> void:
	if needs_art(): return
	var files := DirAccess.get_files_at("%s/props" % ART)
	var pngs := 0
	for file in files:
		if not file.ends_with(".png"):
			continue
		pngs += 1
		for word: String in PICKUP_LOOKALIKES:
			check("%s is not a %s" % [file, word], not file.begins_with(word), file)
	check("setup: there are props", pngs >= 10, str(pngs))


func test_the_steam_is_the_one_thing_that_moves() -> void:
	if needs_art(): return
	# 会动的只要蒸汽：288×48 = 6 帧
	var smoke := zone_art("props/smoke.png")
	check("six square frames of steam", smoke.get_width() == smoke.get_height() * 6,
		str(smoke.get_size()))


# ---------------------------------------------------------------- 接上去以后

func test_every_platform_wears_this_zone_terrain() -> void:
	if needs_art(): return
	await reset_scene(true, true, pack())
	var checked := 0
	for p in main.get_node("Level").find_children("*", "Platform", true, false):
		var visual := p.get_node("Visual")
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes its art from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))
	check("setup: the platforms are skinned at all", checked >= 5, str(checked))


func test_the_level_is_lit_and_the_rules_do_not_change() -> void:
	if needs_art(): return
	# 换上这套包，测试关照常跑：玩家站得住、光照层夹在地形和人中间
	await reset_scene(true, true, pack())
	await frames(30)
	check("the player stands", player.is_on_floor() and player.is_alive(), str(player.global_position))
	var light := main.get_node_or_null("Lighting")
	check("the level is lit", light is ScreenLight)
	if light != null:
		check("under the player", light.get_index() < main.get_node("Player").get_index())
