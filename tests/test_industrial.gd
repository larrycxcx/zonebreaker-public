extends GameTest
## 工业区素材包（第二关那一套，`tools/terrain_build.py` 从 Industrial Zone Tileset 生成）。
##
## 它是**第二个区**，所以守的重点和赛博朋克那组不同：那组守的是九宫格的算法和「换皮肤不改变规则」，
## 这组守的是**「一个区只装自己独有的那几样、其余顺着 fallback 拿」这件事真的成立**——
## 23 关都要这么摆，第一个区搭错了后面 22 个跟着错。
## 另外两条是这次踩出来的：地砖别挑成半格的（薄条只画了上半格，当地面顶用的话上半截是透明的），
## 背景每层要一直画到画面底（不然坑里露出清屏色）。

const PACK := "res://skins/industrial/industrial_skin.tres"
const CYBERPUNK := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART := "res://skins/industrial"
## 画面高：背景素材只有 324 高，生成时要往下补到这儿（见 terrain_build.py 的 BACKDROP_HEIGHT）。
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

func test_the_pack_brings_its_own_terrain_and_a_backdrop() -> void:
	# 一个区独有的就这几样：三种地形 + 这一关的敌人 + 背景。
	# **玩家、子弹、特效、HUD 一个都不该在它自己的表里**——那些 23 关共用，配在这儿就等于抄了一份。
	var mine := pack()
	var keys: Array[String] = []
	for key: StringName in mine.appearances:
		keys.append(String(key))
	keys.sort()
	check("it declares the three terrains and this stage's enemies",
		keys == ["2_a", "2_b", "2_c", "2_d", "2_e", "2_f",
			"terrain_ground", "terrain_ledge", "terrain_stone"], str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("industrial"), str(mine.backdrop))
	check("sounds and music are left to the fallback", mine.sounds.is_empty() and mine.music.is_empty(),
		"%d sounds, %d tracks" % [mine.sounds.size(), mine.music.size()])


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	# 角色、子弹、特效、HUD、声音都得照常拿得到——拿不到的话第二关会变成一地占位方块。
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"1_a", &"enemy_bullet", &"1_boss"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)
	check("and the music", Skins.music(&"level") != null)


func test_the_terrain_art_is_this_zone_and_not_the_last_one() -> void:
	# 光有一份 `.tres` 不算换了皮肤：贴图得真的不一样
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		var theirs := (load("res://skins/cyberpunk/terrain/%s.png" % name) as Texture2D).get_image()
		check("%s is its own art" % name, mine.get_data() != theirs.get_data())


# ---------------------------------------------------------------- 这次踩出来的两条

func test_no_terrain_tile_is_half_empty() -> void:
	# 素材里薄条（16 高）和整砖（32 高）混在一起，编号又挨着。
	# 拿薄条当地面顶砖的话上半截是透明的，游戏里地面看着像一排护栏——所以每张图都不许有整行空的。
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
	# 素材只有 324 高，地面线以下什么都没有。关卡里有坑，坑那一块会露出清屏色、看着像块黑砖，
	# 所以生成时把最底下那一行往下重复到画面底。
	# **只有最后面那层要求不透明**：这套素材里 `sky` 画到地平线就没了，底下露出 `base` 那片雾色，
	# 那是画师的分层，不是漏画——挡住清屏色的是最后面那一层。
	for layer: String in ["base", "sky", "far", "mid", "near"]:
		var img := zone_art("backdrop/%s.png" % layer)
		check("%s covers the whole screen" % layer, img.get_height() >= SCREEN_HEIGHT,
			"%dx%d" % [img.get_width(), img.get_height()])
	var back := zone_art("backdrop/base.png")
	var gaps := 0
	for x in back.get_width():
		if back.get_pixel(x, SCREEN_HEIGHT - 1).a < 1.0:
			gaps += 1
	check("the backmost layer is solid along the bottom row, so pits never show the clear colour",
		gaps == 0, "%d 列是透的" % gaps)


# ---------------------------------------------------------------- 接上去以后

func test_every_platform_wears_this_zone_terrain() -> void:
	await reset_scene(true, true, pack())
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s wears terrain art" % p.name, visual is TerrainAppearance, str(visual))
		if visual is TerrainAppearance:
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes it from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))


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
	var industrial := await measure(pack())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0,
		str(blocks))
	for key: String in blocks:
		check("%s is the same in this zone" % key, blocks[key] == industrial[key],
			"方块 %s，工业区 %s" % [blocks[key], industrial[key]])


# ---------------------------------------------------------------- 这一关的敌人

## 这一关的六种敌人：皮肤键 → [外观帧宽, 帧高, 锚点 x, 锚点 y, 有没有脚（飞的那个没有）]
const ENEMIES := {
	&"2_a": [80, 56, 40, 40, true],   # Worker：从天而降，落地冲人
	&"2_b": [80, 56, 40, 40, true],   # Heaver：冲撞
	&"2_c": [80, 56, 40, 40, true],   # Specialist：巡逻 + 射击 + 斜射
	&"2_d": [80, 56, 40, 40, true],   # Hammer：走近了抡锤
	&"2_e": [48, 48, 24, 24, false],  # Copter：飞在头顶投弹
	&"2_f": [80, 56, 40, 40, true],   # Alarmobot：冲过来自爆
}
## 脚底落在锚点下方这么多像素（和玩家、第一关的敌人同一条线）。
const FOOT_BELOW_ANCHOR := 16


func sheet(key: StringName, clip: String, side := "r") -> Image:
	return (load("%s/enemies/%s/%s_%s.png" % [ART, key, clip, side]) as Texture2D).get_image()


func has_clip(key: StringName, clip: String) -> bool:
	return ResourceLoader.exists("%s/enemies/%s/%s_r.png" % [ART, key, clip])


func test_every_enemy_the_pack_names_really_has_art() -> void:
	# 包里填了键却没贴图的话，游戏里那个敌人是一团看不见的东西——照样会打你
	var mine := pack()
	for key: StringName in ENEMIES:
		var scene := mine.appearances.get(key) as PackedScene
		check("%s is registered" % key, scene != null)
		check("%s has an idle, a hurt and a death" % key,
			has_clip(key, "idle") and has_clip(key, "hurt") and has_clip(key, "death"))
		var spec: Array = ENEMIES[key]
		var img := sheet(key, "idle")
		check("%s draws at %dx%d" % [key, spec[0], spec[1]],
			img.get_height() == spec[1] and img.get_width() % spec[0] == 0,
			"%dx%d" % [img.get_width(), img.get_height()])


func test_the_art_is_mirrored_left_and_right() -> void:
	# 转身只是换一张贴图（不用 flip_h，更不用负的 scale），所以两张必须是严格的镜像
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var anchor: int = spec[2]
		var right := sheet(key, "idle")
		var left := sheet(key, "idle", "l")
		var wrong := 0
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / int(spec[0])
				var within := x % int(spec[0])
				var sx := frame * int(spec[0]) + 2 * anchor - within
				if sx < 0 or sx >= right.get_width() or sx / int(spec[0]) != frame:
					continue
				if right.get_pixel(x, y) != left.get_pixel(sx, y):
					wrong += 1
		check("%s mirrors about its anchor" % key, wrong == 0, "%d 个像素对不上" % wrong)


func test_the_ones_that_walk_stand_on_the_same_line() -> void:
	# 脚底落在锚点下方 16px：和玩家、和第一关的敌人同一条线，换关不会有人陷进地里或者浮着
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		if not spec[4]:
			continue
		var img := sheet(key, "idle")
		var lowest := -1
		for y in img.get_height():
			for x in int(spec[0]):
				if img.get_pixel(x, y).a > 0.0:
					lowest = y
					break
		check("%s has its feet on the ground line" % key,
			lowest == int(spec[3]) + FOOT_BELOW_ANCHOR - 1,
			"最低一行 y=%d，应该是 %d" % [lowest, int(spec[3]) + FOOT_BELOW_ANCHOR - 1])


func test_the_one_that_flies_is_centred_on_its_anchor() -> void:
	# 走地上的靠脚底那条线对齐，飞的没有脚——它的判定框 28×20 是**以原点为中心**的，
	# 所以横向要对准锚点那一列。差几像素的话，玩家瞄着机身打却打空。
	var spec: Array = ENEMIES[&"2_e"]
	var img := sheet(&"2_e", "idle")
	var left := int(spec[0])
	var right := -1
	for y in img.get_height():
		for x in int(spec[0]):
			if img.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	var middle := (left + right) / 2.0
	check("2-E's body sits on the anchor column", absf(middle - float(spec[2])) <= 1.0,
		"机身 x %d..%d，中心 %.1f，锚点 %d" % [left, right, middle, spec[2]])


func test_the_ones_that_fight_have_the_frames_their_behaviour_needs() -> void:
	# 每种敌人的打法都卡在某一帧上，贴图少一组的话行为就没有画面
	check("2-C has a firing pose", has_clip(&"2_c", "attack_level"))
	check("2-D has the full hammer swing", has_clip(&"2_d", "attack_level")
		and sheet(&"2_d", "attack_level").get_width() / 80 == 8,
		str(sheet(&"2_d", "attack_level").get_width() / 80))
	check("2-E has the bomb drop", has_clip(&"2_e", "attack_down"))
	check("2-F has the siren it flashes before it blows", has_clip(&"2_f", "attack_level"))
	for key: StringName in [&"2_a", &"2_b", &"2_f"]:
		check("%s has a charging pose" % key, has_clip(key, "run"))


# ---------------------------------------------------------------- 接上去的两种

func spawn(scene_path: String, at: Vector2) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


func test_the_heaver_charges_like_the_chaser_does() -> void:
	await reset_scene(false, true, pack())
	var heaver := spawn("res://scenes/enemy_2_b.tscn", Vector2(500, 300))
	player.global_position = Vector2(340, 304)
	snap_camera()
	await frames(4)
	var started: float = heaver.global_position.x
	await frames(40)
	check("it is a chaser", heaver is EnemyChaser)
	check("and it really closes in", heaver.global_position.x < started - 20.0,
		"%.0f -> %.0f" % [started, heaver.global_position.x])
	check("it wears this zone's art", (heaver.get_node("Visual") as Node).get("art_dir") == "%s/enemies/2_b" % ART,
		str((heaver.get_node("Visual") as Node).get("art_dir")))


func test_the_specialist_shoots_and_can_aim_off_the_level() -> void:
	await reset_scene(false, true, pack())
	var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, 300))
	spec.facing = -1
	player.global_position = Vector2(380, 304)
	snap_camera()
	await frames(4)
	check("it never lies down — this pack has no prone art", not spec.can_go_prone)
	check("but it can aim off the level", spec.can_aim_diagonally)
	# 斜射判定是纯函数，**当场问它**：让玩家自己飞上去不行，重力会立刻把人拽回地面，
	# 瞄的就成了水平，这条用例会变成「测了个水平射击」还照样绿。
	var stood := player.global_position
	player.global_position = stood + Vector2(0, -104)
	check("a player up on a ledge is a diagonal target",
		spec.aim_for(player) == Enemy.Aim.DIAGONAL_UP, str(spec.aim_for(player)))
	player.global_position = stood + Vector2(0, 104)
	check("and one down in a pit is the other way",
		spec.aim_for(player) == Enemy.Aim.DIAGONAL_DOWN, str(spec.aim_for(player)))
	player.global_position = stood
	# `shot_fired` 不带参数，lambda 的参数多一个就连不上（表现成「一枪都没开」）
	var fired: Array[int] = []
	spec.shot_fired.connect(func() -> void: fired.append(1))
	await frames(180)
	check("and it really fires at the player in front of it", not fired.is_empty(), str(fired.size()))


func test_this_zone_enemies_change_nothing_about_the_rules() -> void:
	# 贴图换了，判定框、巡逻、出膛点都不该跟着动
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, true, skin)
		var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, 300))
		player.global_position = Vector2(-4000, 304)
		snap_camera()
		await frames(4)
		var shape := spec.get_node("CollisionShape2D") as CollisionShape2D
		var walked_from: float = spec.global_position.x
		await frames(90)
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": spec.level_muzzle_position() - spec.global_position,
			"walked": snappedf(absf(spec.global_position.x - walked_from), 0.5),
		})
	check("it really patrolled in this test", out[0]["walked"] > 20.0, str(out[0]))
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"方块 %s，工业区 %s" % [out[0][key], out[1][key]])

