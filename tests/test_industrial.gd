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
	check("it declares the three terrains, this stage's enemies and its boss",
		keys == ["2_a", "2_b", "2_boss", "2_c", "2_d", "2_e", "2_f",
			"terrain_ground", "terrain_ledge", "terrain_stone"], str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("industrial"), str(mine.backdrop))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	# **关卡那首是这一关独有的**，Boss 那首和音效照旧顺着 fallback 拿
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


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



# ---------------------------------------------------------------- 四种新打法

## 关卡里的地面顶边，以及站在上面时身体原点的高度。
const GROUND_TOP := 320.0
const STAND_Y := GROUND_TOP - 16.0
## 测试关 x 1096..1280 这一段**头顶什么都没有**（最后一块平台在 1000..1096）。
## 掉落和追击的用例都摆在这儿：摆在平台底下的话，人会落在平台上，
## 而站在单向平台上的追击兵会按 D 那条「走到边缘下去」的规矩往反方向走，
## 用例看到的就是「它朝着远离玩家的方向跑」。
const OPEN_SKY_X := 1180.0


## 敌人没了没有（`is_alive()` 是玩家那边的东西，敌人死了是直接删掉）。
## **参数不能标类型**：已经释放掉的对象传进一个标了 `Node` 的参数会当场报类型错误。
func gone(enemy: Variant) -> bool:
	return not is_instance_valid(enemy) or (enemy as Node).is_queued_for_deletion()


## 等这一把锤子**从头**抡起来。直接等 `is_swinging()` 不行：它可能正抡在半路上，
## 那样量出来的「起手到砸中」只剩个尾巴，用例会误报「还没砸就掉血了」。
func fresh_swing(hammer: EnemyHammer) -> void:
	hammer._swing_left = 0.0
	hammer._smash_timer = 0.0
	while not hammer.is_swinging():
		await tree.physics_frame


func test_the_worker_hangs_until_someone_walks_under_it() -> void:
	# 2-A 是这一关的伏击：吊在画面顶边以上，玩家一路走过来什么也看不见
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	var hung := worker.global_position
	await frames(60)
	check("it does not even fall while nobody is near", not worker.has_dropped
		and worker.global_position.is_equal_approx(hung), str(worker.global_position))
	player.global_position = Vector2(worker.global_position.x, STAND_Y)
	snap_camera()
	await frames(4)
	check("walking under it lets it go", worker.has_dropped)
	await frames(90)
	check("and it comes down to the ground", worker.is_on_floor()
		and absf(worker.global_position.y - STAND_Y) < 4.0, str(worker.global_position))
	check("it fell a long way to get there", worker.global_position.y - hung.y > 300.0,
		str(worker.global_position.y - hung.y))


func test_the_worker_lets_go_when_you_shoot_it() -> void:
	# 不然玩家发现了它也只能对着一个永远不还手的靶子打
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(OPEN_SKY_X - 400.0, STAND_Y)
	snap_camera()
	await frames(10)
	check("setup: it is still hanging", not worker.has_dropped)
	worker.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a hit brings it down", worker.has_dropped)


func test_the_worker_charges_once_it_lands() -> void:
	# 落地之后它就是一个普通的冲撞兵（D 那套），没有第二套 AI
	await reset_scene(false, true, pack())
	var worker := spawn("res://scenes/enemy_2_a.tscn", Vector2(OPEN_SKY_X, -40)) as EnemyDropper
	player.global_position = Vector2(OPEN_SKY_X - 80.0, STAND_Y)
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if worker.is_on_floor():
			break
	check("setup: it landed", worker.is_on_floor(), str(worker.global_position))
	check("it is a chaser underneath", worker is EnemyChaser)
	# 落地的时候人就在它脚边，早追到了——把玩家挪开，从头量一遍它追过来的这段
	player.global_position = Vector2(OPEN_SKY_X - 200.0, STAND_Y)
	snap_camera()
	await frames(2)
	# 量的是「有没有把距离拉近」而不是「往哪边走」：贴上之后它会被玩家顶开一段（D 那条规矩），
	# 正好撞上取样的那一刻的话，看到的就是它在往回走
	var gap: float = absf(worker.global_position.x - player.global_position.x)
	var closest := gap
	for i in 60:
		await tree.physics_frame
		closest = minf(closest, absf(worker.global_position.x - player.global_position.x))
	check("and it comes after you", closest < gap - 40.0, "%.0f -> %.0f" % [gap, closest])


func test_the_hammer_only_hurts_you_when_it_lands() -> void:
	# 画面上锤子还举在半空人就掉血的话，玩家没法从动作判断该什么时候躲
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	# 接触伤害是另一套机制（基类那条，另有用例守着），这儿关掉：两种伤害都是 42，混在一起分不清谁打的
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	var before: int = player.health
	check("it winds up first", hammer.is_swinging())
	await frames(int(EnemyHammer.HIT_DELAY * 60.0) - 4)
	check("still nothing while the hammer is in the air", player.health == before,
		"%d -> %d" % [before, player.health])
	await frames(8)
	check("and it lands on you", player.health < before, "%d -> %d" % [before, player.health])


func test_stepping_back_after_the_windup_dodges_the_hammer() -> void:
	# 抡的这段时间它站着不动，所以退出锤子够得着的范围就躲掉了
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	# 接触伤害是另一套机制（基类那条，另有用例守着），这儿关掉：两种伤害都是 42，混在一起分不清谁打的
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	var before: int = player.health
	player.global_position = Vector2(200, STAND_Y)
	await frames(int(EnemyHammer.HIT_DELAY * 60.0) + 10)
	check("the hammer comes down on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_hammer_never_shoots() -> void:
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	check("it has no gun", hammer.bullet_scene == null)
	hammer.facing = -1
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(150)
	check("and never puts a bullet on the field", bullets(16).is_empty())


func test_the_alarmobot_stops_and_blows_up_next_to_you() -> void:
	# 点火之后停住不动：一直贴着追的话玩家根本躲不掉
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(420, STAND_Y)) as EnemyBomber
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("setup: it has not gone off yet", not bot.is_lit() and not gone(bot))
	var before: int = player.health
	for i in 200:
		await tree.physics_frame
		if gone(bot):
			break
	check("it reaches you and goes off", gone(bot))
	check("and the blast hurts", player.health < before, "%d -> %d" % [before, player.health])


func test_running_away_from_a_lit_alarmobot_works() -> void:
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(420, STAND_Y)) as EnemyBomber
	player.global_position = Vector2(390, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if bot.is_lit():
			break
	check("setup: the fuse is lit", bot.is_lit())
	var stood: float = bot.global_position.x
	var fuse := bot.fuse_time
	var before: int = player.health
	player.global_position = Vector2(stood - 300.0, STAND_Y)
	# 引信走完它就没了，所以「它没有追过来」要在还活着的时候量
	var moved := 0.0
	for i in int(fuse * 60.0) - 4:
		await tree.physics_frame
		if gone(bot):
			break
		moved = absf(bot.global_position.x - stood)
	check("it does not chase you once it is lit", moved < 2.0, "%.1f" % moved)
	await frames(30)
	check("it still goes off", gone(bot))
	check("but it goes off on nothing", player.health == before, "%d -> %d" % [before, player.health])


func test_the_copter_drops_bombs_on_what_is_under_it() -> void:
	await reset_scene(false, true, pack())
	var copter := spawn("res://scenes/enemy_2_e.tscn", Vector2(400, 120)) as EnemyCopter
	copter.set_anchor(Vector2(400, 120))
	player.global_position = Vector2(400, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it has no gun, only bombs", copter.bullet_scene == null and copter.bomb_scene != null)
	var dropped: Array[Node] = []
	for i in 200:
		await tree.physics_frame
		for node in tree.get_nodes_in_group(Grenade.GROUP):
			if not dropped.has(node):
				dropped.append(node)
		if not dropped.is_empty():
			break
	check("it drops one", not dropped.is_empty())
	if dropped.is_empty():
		return
	var bomb := dropped[0] as Grenade
	# **要看速度，不能只看位置**：刚出手那一刻炸弹就在机腹下面，往前扔还是往下丢位置都一样，
	# 方向只体现在速度上（F 是往前抛的，这一架是直着松手）
	check("it is released straight down, not thrown forward",
		absf(bomb.velocity.x) <= 1.0 and bomb.velocity.y > 0.0, str(bomb.velocity))
	check("out of its belly", absf(bomb.global_position.x - copter.global_position.x) <= 2.0
		and bomb.global_position.y > copter.global_position.y,
		str(bomb.global_position - copter.global_position))
	check("and it is the enemies' grenade, so it cannot hurt its own side",
		bomb.target_layer == 2, str(bomb.target_layer))


# ---------------------------------------------------------------- 这一关的 Boss

## Boss 摆在半空的高度（它不受重力，飘在这儿）。
const BOSS_Y := 170.0


func spawn_boss() -> BossOperator:
	var boss := (load("res://scenes/boss_2.tscn") as PackedScene).instantiate() as BossOperator
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(OPEN_SKY_X, BOSS_Y)
	boss._home = boss.global_position
	return boss


## 摆好 Boss 和玩家，等它出场。
func face_the_operator(player_at: Vector2) -> BossOperator:
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	player.global_position = player_at
	player.health = 9999
	snap_camera()
	await frames(4)
	boss.appear()
	await frames(2)
	return boss


func test_the_operator_is_a_boss_and_shows_up_on_the_hud() -> void:
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	check("it is a boss", boss is Boss)
	check("it hangs in the air, no gravity", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING)
	check("it brings a portrait from this pack's art",
		boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.begins_with("%s/enemies/2_boss" % ART),
		str(boss.hud_portrait()))
	check("the ultimate only takes a quarter off it",
		boss.ultimate_damage() == roundi(boss.max_health * 0.25), str(boss.ultimate_damage()))


func test_it_drifts_in_eight_directions() -> void:
	# 「八个方向飞」这件事**直接问方向选取**，不要靠实跑去撞：
	# 五秒里它只挑三四次方向，全挑成竖直的概率有百分之一——那样用例会偶发失败，
	# 而且失败的时候看着像 Boss 坏了。
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	var seen := {}
	for i in 400:
		boss._pick_heading()
		seen[boss._heading.snapped(Vector2(0.01, 0.01))] = true
	check("all eight headings come up", seen.size() == 8, str(seen.size()))
	var flat := 0
	var slanted := 0
	for heading: Vector2 in seen:
		if is_zero_approx(heading.y):
			flat += 1
		elif not is_zero_approx(heading.x):
			slanted += 1
	check("two of them are straight across", flat == 2, str(flat))
	check("and four are diagonal", slanted == 4, str(slanted))


func test_it_never_leaves_its_own_patch_of_air() -> void:
	# 它不追人——追击是 D 的定位，它靠居高临下压制，所以不能跟着玩家跑出地盘
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 500.0, STAND_Y))
	var home: Vector2 = boss._home
	var moved := 0.0
	var strayed := Vector2.ZERO
	for i in 300:
		await tree.physics_frame
		var off: Vector2 = boss.global_position - home
		moved = maxf(moved, off.length())
		strayed = Vector2(maxf(strayed.x, absf(off.x) - boss.roam_range.x),
			maxf(strayed.y, absf(off.y) - boss.roam_range.y))
	check("it really moves", moved > 20.0, "%.0f" % moved)
	check("but never leaves its patch", strayed.x < 16.0 and strayed.y < 16.0, str(strayed))


func test_the_arm_only_comes_down_on_someone_underneath() -> void:
	# 缆绳只能往正下方放，站在它侧下方是安全的
	var boss := await face_the_operator(Vector2(OPEN_SKY_X + 200.0, STAND_Y))
	# **把飘动钉住**：横向地盘本来就有 200px，它自己飘过去就站到这个玩家头上了，
	# 那样这条用例测的就不是「侧下方安全」而是「它这几秒有没有飘过来」。
	boss.roam_range = Vector2.ZERO
	await frames(120)
	check("nobody underneath, so the arm stays in",
		boss.arm_state() == BossOperator.Arm.IN and is_zero_approx(boss.arm_length()),
		"%d / %.0f" % [boss.arm_state(), boss.arm_length()])
	# 换到正下方；纵向也钉住，免得它飘到缆绳够不着的高度，那是另一回事
	boss.roam_range = Vector2.ZERO
	player.global_position = Vector2(boss.global_position.x, STAND_Y)
	var out := false
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if boss.arm_length() > 0.0:
			out = true
			break
	check("standing under it brings the arm down", out)


func test_the_claw_only_bites_when_it_shuts() -> void:
	# 放缆绳要时间，这段时间玩家看得见也跑得开——和锤子兵同一条道理
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# 纵向钉住：飘高了缆绳够不着，它会改打枪，用例就等不到手臂
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is on its way down", boss.arm_state() == BossOperator.Arm.OUT)
	var before: int = player.health
	while boss.arm_state() == BossOperator.Arm.OUT:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		check("no bite while the cable is still paying out", player.health == before)
		break
	# 一路跟到底：爪子合上那一刻才该掉血
	var bitten := false
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if player.health < before:
			bitten = boss.arm_state() == BossOperator.Arm.GRAB \
				or boss.arm_state() == BossOperator.Arm.BACK
			break
	check("and it bites when the claw shuts at the bottom", bitten)


func test_stepping_aside_dodges_the_claw() -> void:
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# 纵向钉住：飘高了缆绳够不着，它会改打枪，用例就等不到手臂
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is coming down", boss.arm_state() == BossOperator.Arm.OUT)
	var before: int = player.health
	player.global_position = Vector2(boss.global_position.x - 200.0, STAND_Y)
	for i in 120:
		await tree.physics_frame
		if boss.arm_state() == BossOperator.Arm.IN:
			break
	check("the claw closes on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_volley_all_goes_one_way() -> void:
	# 和 Boss A 最大的区别：那个铺一个扇形，这个一串子弹全沿同一条线
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var shots: Array[Node] = []
	for i in 400:
		await tree.physics_frame
		for b in bullets(16):
			if not shots.has(b):
				shots.append(b)
		if shots.size() >= boss.burst_min:
			break
	check("it puts a volley on the field", shots.size() >= boss.burst_min, str(shots.size()))
	if shots.size() < 2:
		return
	var spread := 0.0
	var first: Vector2 = (shots[0] as Bullet).direction
	for b in shots:
		spread = maxf(spread, rad_to_deg(absf(first.angle_to((b as Bullet).direction))))
	check("every shot in it goes the same way", spread < 1.0, "最大差 %.1f 度" % spread)
	check("and it is aimed at the player, not straight ahead",
		absf(first.y) > 0.1, str(first))


func test_the_two_attacks_take_turns() -> void:
	# 「两种方式交替」是这个 Boss 的设计，只会一种的话打起来就是一个节奏
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# **把它钉在够得着的高度上**：让它自己上下飘的话，飘高了缆绳够不着、它会改打枪，
	# 于是「只会伸手臂」这种毛病也能混过去——看到的那发子弹是够不着逼出来的，不是轮换逼出来的。
	boss.roam_range.y = 0.0
	var seen_arm := false
	var seen_volley := false
	for i in 600:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_length() > 0.0:
			seen_arm = true
		if not bullets(16).is_empty():
			seen_volley = true
		if seen_arm and seen_volley:
			break
	check("it uses the arm", seen_arm)
	check("and the gun", seen_volley)


func test_the_boss_skin_changes_nothing_about_the_rules() -> void:
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, true, skin)
		var boss := spawn_boss()
		boss.appear()
		await frames(2)
		var shape := boss.get_node("CollisionShape2D") as CollisionShape2D
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": boss._muzzle_position() - boss.global_position,
			"arm_reach": boss.arm_max_length,
			"health": boss.max_health,
		})
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"方块 %s，工业区 %s" % [out[0][key], out[1][key]])


func test_it_holds_still_while_the_arm_is_out() -> void:
	# 缆绳是吊着的：一边放一边飘的话爪子会落到瞄好的位置以外，
	# 玩家明明没动也可能被抓不中、或者站着没动反而被抓中。停住也让这一下看得清、躲得掉。
	var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
	boss.contact_damage = 0
	# 纵向钉住：飘高了缆绳够不着，它会改打枪，用例就等不到手臂
	boss.roam_range.y = 0.0
	for i in 300:
		await tree.physics_frame
		player.global_position = Vector2(boss.global_position.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.OUT:
			break
	check("setup: the arm is on its way down", boss.arm_state() == BossOperator.Arm.OUT)
	var anchored: Vector2 = boss.global_position
	var strayed := 0.0
	for i in 200:
		await tree.physics_frame
		player.global_position = Vector2(anchored.x, STAND_Y)
		player.health = 9999
		if boss.arm_state() == BossOperator.Arm.IN:
			break
		strayed = maxf(strayed, boss.global_position.distance_to(anchored))
	check("it stays put from the moment the cable pays out", strayed < 2.0, "%.1f" % strayed)
	check("setup: the arm really finished in this test", boss.arm_state() == BossOperator.Arm.IN)


func test_aiming_off_the_level_falls_back_to_the_art_this_pack_has() -> void:
	# **这套素材只画了水平开火**（赛博朋克那个巡逻兵自带水平 / 斜上 / 斜下三组）。
	# 2-C 照样会斜着打——规则不变，只是画面上还是水平端枪的样子。
	# 没有这条兜底的话，它一斜着瞄就去加载一张不存在的图，刷一屏「Resource file not found」，
	# 画面上那一帧也没了。**这是截图才发现的**：无头测试一条都没红。
	check("setup: this pack really has no diagonal firing art",
		not has_clip(&"2_c", "attack_up") and not has_clip(&"2_c", "attack_down"))
	await reset_scene(false, true, pack())
	var spec := spawn("res://scenes/enemy_2_c.tscn", Vector2(500, STAND_Y))
	var visual: EnemySpriteAppearance = spec.get_node("Visual")
	for aim: Vector2 in [Vector2(1, 0), Vector2(1, -1), Vector2(1, 1)]:
		visual.aim(aim)
		visual.fire()
		var clip := visual.clip()
		check("aiming %s picks a clip this pack actually has" % aim,
			ResourceLoader.exists("%s/enemies/2_c/%s_r.png" % [ART, clip]), String(clip))


func test_the_characters_still_have_faces_in_this_zone() -> void:
	# **每关的包只装这一关独有的**，角色是 23 关共用的、只在最底下那个包里有一份。
	# 头像一开始是直接按当前包的目录拼路径的，打完第二关回主菜单时当前包是工业区、
	# 那儿一个角色目录都没有，三个头像就全空了（试玩发现）。现在顺着 fallback 找。
	Skins.use(pack())
	for look: StringName in [&"biker", &"punk", &"cyborg"]:
		var face := UiKit.portrait(look)
		check("%s still has a face here" % look, face != null,
			"包里找到的是 %s" % Skins.file("%s/portrait.png" % look))
	check("and the pack itself really has no character art",
		Skins.file("biker/portrait.png").contains("cyberpunk"),
		Skins.file("biker/portrait.png"))


# ---------------------------------------------------------------- Boss 的第二阶段

func test_the_operator_turns_nasty_below_half_health() -> void:
	# **第一阶段只会一条线，站开就躲掉了**——血过半之后再不变招，后半场就是站着磨（试玩反馈）
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	check("it starts out calm", not boss.is_enraged(), "%d/%d" % [boss.health, boss.max_health])
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("and turns nasty once it is down to half", boss.is_enraged(),
		"%d/%d" % [boss.health, boss.max_health])


func test_it_flies_faster_once_it_is_hurt() -> void:
	var out := []
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		# 方向是随机挑的，所以比的是**速度的长度**，不是跑了多远
		var fastest := 0.0
		for i in 240:
			await tree.physics_frame
			if boss.arm_state() == BossOperator.Arm.IN:
				fastest = maxf(fastest, boss.velocity.length())
		out.append(fastest)
	check("setup: it really drifts in both runs", out[0] > 1.0, "%.0f" % out[0])
	check("hurt, it moves faster", out[1] > out[0] * 1.2, "%.0f -> %.0f" % [out[0], out[1]])


func test_the_volley_opens_into_a_fan_once_it_is_hurt() -> void:
	# 第一阶段一条线（横向闪开），第二阶段一把扇形（站进两发之间的空隙）——躲法整个变了
	var spreads := []
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		var shots: Array[Node] = []
		for i in 400:
			await tree.physics_frame
			for b in bullets(16):
				if not shots.has(b):
					shots.append(b)
			if shots.size() >= boss.burst_min:
				break
		check("it puts a volley on the field", shots.size() >= 2, str(shots.size()))
		var widest := 0.0
		if shots.size() >= 2:
			var first: Vector2 = (shots[0] as Bullet).direction
			for b in shots:
				widest = maxf(widest, rad_to_deg(absf(first.angle_to((b as Bullet).direction))))
		spreads.append(widest)
	check("calm, every shot goes the same way", spreads[0] < 1.0, "%.1f 度" % spreads[0])
	check("hurt, the volley opens up", spreads[1] > 10.0, "%.1f 度" % spreads[1])


func test_the_fan_is_still_dodgeable() -> void:
	# 扇形要有缝才叫「躲得掉」：每发之间的夹角要够大，不能糊成一堵墙
	await reset_scene(false, true, pack())
	var boss := spawn_boss()
	check("the shots are spread wide enough to stand between",
		boss.enrage_fan_spread >= 12.0, str(boss.enrage_fan_spread))
	check("and there are only a few of them", boss.enrage_fan_count <= 3
		and boss.enrage_fan_count >= 2, str(boss.enrage_fan_count))


# ---------------------------------------------------------------- 这一关的音乐

func test_the_zone_has_a_track_of_its_own() -> void:
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	# **循环的曲子必须是 OGG**：MP3 编码器会在开头结尾各补一小段静音，转一圈能听出来接缝
	check("and it is an ogg, so the loop is seamless", track is AudioStreamOggVorbis,
		track.get_class())
	check("the boss track still comes from the pack behind it",
		Skins.music(&"boss") != null and Skins.music(&"boss").resource_path.contains("cyberpunk"),
		str(Skins.music(&"boss")))


func test_each_zone_plays_its_own_music() -> void:
	# 两个区的关卡曲子得真的不一样——登记错了的话第二关会放第一关那首
	Skins.use(pack())
	var mine := Skins.music(&"level")
	Skins.use(load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack)
	var theirs := Skins.music(&"level")
	check("setup: both zones have one", mine != null and theirs != null)
	check("and they are different tracks", mine != theirs,
		"%s vs %s" % [mine.resource_path if mine else "", theirs.resource_path if theirs else ""])


# ---------------------------------------------------------------- 自爆的伤害

func test_the_alarmobot_blast_falls_off_like_a_grenade() -> void:
	# 「和手雷一样」：中心满伤害，边缘只擦一下——躲的办法是**离远点**，不是硬扛。
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
	check("it uses the same blast rule as a grenade",
		bot.blast_max_damage > bot.blast_min_damage, "%d / %d"
			% [bot.blast_max_damage, bot.blast_min_damage])
	var centre := Blast.damage_at(0.0, bot.blast_radius, bot.blast_max_damage, bot.blast_min_damage)
	var edge := Blast.damage_at(bot.blast_radius, bot.blast_radius,
		bot.blast_max_damage, bot.blast_min_damage)
	check("dead centre hurts most", centre == bot.blast_max_damage, str(centre))
	check("the edge only grazes", edge == bot.blast_min_damage, str(edge))
	check("and it tails off in between",
		Blast.damage_at(bot.blast_radius / 2.0, bot.blast_radius,
			bot.blast_max_damage, bot.blast_min_damage) < centre)


func test_standing_at_the_edge_of_the_blast_hurts_less_than_hugging_it() -> void:
	# **两档都要在接触范围（26px）之外**：贴在它身上的话每帧挨一次接触判定，
	# 无敌帧还没过爆炸就来了，量到的是 0。它点火的距离（36）本来就在接触范围之外，
	# 所以正常打起来不会出现「贴着反而不疼」。
	# **而且要先点火再摆玩家**：它冲得很快（220px/s，两帧就贴上来了），
	# 先摆玩家的话它会自己冲到跟前，两档量出来是同一个距离。
	var taken := []
	for gap: float in [28.0, 54.0]:
		await reset_scene(false, true, pack())
		var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
		bot.contact_damage = 0
		player.global_position = Vector2(-2000, STAND_Y)     # 先支开，免得它冲过来
		snap_camera()
		await frames(2)
		bot._light_the_fuse()                                # 点了火它就站住不动了
		var stood: float = bot.global_position.x
		player.global_position = Vector2(stood - gap, STAND_Y)
		player.health = 9999
		snap_camera()
		var before: int = player.health
		for i in 120:
			await tree.physics_frame
			player.global_position = Vector2(stood - gap, STAND_Y)
			if gone(bot):
				break
		taken.append(before - player.health)
	check("setup: both got hit", taken[0] > 0 and taken[1] > 0, str(taken))
	check("close in hurts much more than standing at the edge", taken[0] > taken[1] + 20,
		"近处 %d，边缘 %d" % [taken[0], taken[1]])


func test_the_blast_cannot_reach_through_a_wall() -> void:
	# 和手雷同一条：中心到目标之间被实心物体挡住就炸不到
	await reset_scene(false, true, pack())
	var bot := spawn("res://scenes/enemy_2_f.tscn", Vector2(500, STAND_Y)) as EnemyBomber
	bot.contact_damage = 0
	add_wall(480.0, 56.0)
	player.global_position = Vector2(462, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(2)
	var before: int = player.health
	bot._light_the_fuse()
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(462, STAND_Y)
		if gone(bot):
			break
	check("setup: it went off", gone(bot))
	check("but the wall took it", player.health == before, "%d -> %d" % [before, player.health])


# ---------------------------------------------------------------- 锤子会冲过来

func test_the_hammer_charges_at_you() -> void:
	# 原来它只按巡逻速度溜达，玩家站着不动都挨不到——没什么威胁（2026-09 试玩反馈）
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.facing = 1                      # 背对玩家：它要**转过来**才算数
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it turns to face you", hammer.facing == -1, str(hammer.facing))
	check("and it is charging", hammer.is_charging())
	var gap: float = absf(hammer.global_position.x - player.global_position.x)
	await frames(40)
	var closed: float = absf(hammer.global_position.x - player.global_position.x)
	check("it closes the distance", closed < gap - 40.0, "%.0f -> %.0f" % [gap, closed])


func test_the_charge_is_slower_than_walking_away() -> void:
	# 和 D 一个道理：走开追不上，它只能逼你且战且退——不然就成了甩不掉的狗皮膏药
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	check("charging is faster than patrolling", hammer.charge_speed > hammer.move_speed,
		"%.0f / %.0f" % [hammer.charge_speed, hammer.move_speed])
	check("but slower than the player walks", hammer.charge_speed < player.move_speed,
		"%.0f / %.0f" % [hammer.charge_speed, player.move_speed])


func test_it_does_not_track_you_mid_swing() -> void:
	# 抡到一半还跟着人转的话，「起手之后退开就躲掉了」这条就没意义了
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	await fresh_swing(hammer)
	check("setup: mid swing", hammer.is_swinging())
	player.global_position = Vector2(700, STAND_Y)     # 绕到背后
	await frames(4)
	check("it stops hunting while it swings", not hammer.is_charging())
	check("it does not spin round to follow", hammer.facing == -1, str(hammer.facing))


func test_the_second_phase_announces_itself() -> void:
	# **不报一声玩家根本不知道它变了**：飞快一点、子弹多两发，都不够显眼
	# （2026-09 试玩反馈「没出现第二阶段」，其实出现了，只是看不出来）。
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a scratch does not flip it", not boss.is_enraged() and not events.has(&"boss_enrage"))
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("crossing half flips it", boss.is_enraged())
	check("and it says so", events.has(&"boss_enrage"), str(events))
	# **只报一次**：每挨一下报一次的话，后半场警报会一直响
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("but only once", not events.has(&"boss_enrage"), str(events))


func test_the_second_phase_shows_up_in_the_arm_too() -> void:
	# **玩家多半站在它正下方**，那时它一直在用机械臂——只改飞行速度和子弹扇形的话，
	# 二阶段在最常见的位置上根本看不出来。
	var slow := 0.0
	var quick := 0.0
	for hurt: bool in [false, true]:
		var boss := await face_the_operator(Vector2(OPEN_SKY_X, STAND_Y))
		boss.contact_damage = 0
		boss.roam_range.y = 0.0
		if hurt:
			boss.take_damage(boss.max_health / 2, Vector2.INF, player)
		# 量「缆绳从开始放到放到底要多少帧」
		for i in 400:
			await tree.physics_frame
			player.global_position = Vector2(boss.global_position.x, STAND_Y)
			player.health = 9999
			if boss.arm_state() == BossOperator.Arm.OUT:
				break
		var frames_out := 0
		for i in 200:
			await tree.physics_frame
			player.global_position = Vector2(boss.global_position.x, STAND_Y)
			player.health = 9999
			if boss.arm_state() != BossOperator.Arm.OUT:
				break
			frames_out += 1
		if hurt:
			quick = float(frames_out)
		else:
			slow = float(frames_out)
	check("setup: the arm really came down both times", slow > 2.0 and quick > 0.0,
		"%.0f / %.0f" % [slow, quick])
	check("hurt, the claw comes down faster", quick < slow, "%.0f -> %.0f 帧" % [slow, quick])


func test_the_hammer_swing_makes_a_noise() -> void:
	await reset_scene(false, true, pack())
	var hammer := spawn("res://scenes/enemy_2_d.tscn", Vector2(500, STAND_Y)) as EnemyHammer
	hammer.contact_damage = 0
	hammer.facing = -1
	player.global_position = Vector2(500 - hammer.smash_range + 8.0, STAND_Y)
	player.health = 9999
	snap_camera()
	events.clear()
	for i in 180:
		await tree.physics_frame
		player.health = 9999
		if events.has(&"hammer_smash"):
			break
	check("it reports a swing", events.has(&"hammer_smash"), str(events))


func test_a_big_hit_that_jumps_past_half_still_flips_it() -> void:
	# 判断是**小于等于**半血，不是等于：一发大伤害（手雷、终极武器）会从半血以上
	# 直接打到半血以下，正好踩在那条线上的概率很小。
	# 写成「等于」的话，绝大多数打法都跨过去了，二阶段永远不出现。
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var half := boss.max_health / 2
	boss.take_damage(boss.max_health - half - SHOT, Vector2.INF, player)   # 打到半血**以上**
	await frames(2)
	check("setup: still above half", boss.health > half and not boss.is_enraged(),
		"%d / %d" % [boss.health, half])
	# 一下打过线，而且不是正好落在半血上
	boss.take_damage(boss.health - half + SHOT * 3, Vector2.INF, player)
	await frames(2)
	check("setup: it landed well below half, not exactly on it",
		boss.health < half and boss.health > 0, "%d / %d" % [boss.health, half])
	check("jumping straight past half still flips it", boss.is_enraged())


func test_landing_exactly_on_half_counts_as_below() -> void:
	# 边界本身也要算：正好打到半血那一下就该换挡，不用再挨一下
	var boss := await face_the_operator(Vector2(OPEN_SKY_X - 240.0, STAND_Y))
	var half := boss.max_health / 2
	boss.take_damage(boss.max_health - half, Vector2.INF, player)
	await frames(2)
	check("setup: exactly on half", boss.health == half, "%d / %d" % [boss.health, half])
	check("that already counts", boss.is_enraged())
