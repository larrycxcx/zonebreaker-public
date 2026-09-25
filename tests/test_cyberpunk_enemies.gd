extends GameTest
## 赛博朋克皮肤包的敌人贴图（目前是巡逻兵 A/B/C，素材 2 号换色；飞行的 E，素材 5 号无人机；炮台，素材 6 号加手改的斜炮管；D 滑板手 3 号；F 球棒手 1 号）。
##
## 和玩家那组（test_cyberpunk_skin.gd）守的是同一类东西：贴图齐全、左右严格镜像、脚底落在地面线上、
## 子弹从画面上的枪口出来，以及最要紧的——**换皮肤不改变规则**：同一个敌人用方块和用精灵图，
## 出膛点、碰撞体、巡逻走多远、趴下后多高，数字必须一模一样。
## 贴图由 tools/enemy_build.py 生成，改素材后要重新跑它。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART := "res://skins/cyberpunk/enemies"
const VARIANTS := [&"1_a", &"1_b", &"1_c"]
const CLIPS := [&"idle", &"walk", &"attack_level", &"attack_down", &"attack_up", &"prone", &"hurt", &"death"]
const FW := EnemySpriteAppearance.FRAME_W
const FH := EnemySpriteAppearance.FRAME_H
const AX := EnemySpriteAppearance.ANCHOR_X
const AY := EnemySpriteAppearance.ANCHOR_Y
## 素材里画的枪口火光（量枪口位置时不算它）。
const FLASH := [Color8(0xff, 0xda, 0x45), Color8(0xff, 0xdb, 0xa5), Color8(0xcc, 0xac, 0x68)]


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func image(variant: StringName, clip: StringName, side := "r") -> Image:
	return (load("%s/%s/%s_%s.png" % [ART, variant, clip, side]) as Texture2D).get_image()


## 某一帧里所有看得见的像素，换算成敌人本体坐标（原点 = 身体中心）。
func ink(img: Image, frame: int, skip_flash := false) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y in FH:
		for x in FW:
			var c := img.get_pixel(frame * FW + x, y)
			if c.a <= 0.03:
				continue
			if skip_flash and FLASH.any(func(f: Color) -> bool: return c.is_equal_approx(f)):
				continue
			out.append(Vector2(x - AX, y - AY))
	return out


## 沿 aim 方向最远的那一撮像素的中心（枪口）。`above` 只看这条线以上（斜下时脚尖比枪口还远）。
func tip(points: Array[Vector2], aim: Vector2, above := INF) -> Vector2:
	var direction := aim.normalized()
	var far := -INF
	for p in points:
		if p.y < above:
			far = maxf(far, p.dot(direction))
	var sum := Vector2.ZERO
	var n := 0
	for p in points:
		if p.y < above and p.dot(direction) >= far - 1.5:
			sum += p
			n += 1
	return sum / maxf(n, 1.0)


## 把 C 摆在右边空地上、面朝左，玩家在它前方（左边）。
## 别摆在 x 592..704：那是矮通道，净空只有 30px，32px 高的巡逻兵会被卡住走不动。
func place_c(pack: SkinPack, player_x := 760.0) -> EnemyWalker:
	await reset_scene(true, false, pack)
	keep_only_enemies(["WalkerC"])
	var c: EnemyWalker = main.get_node("Enemies/WalkerC")
	c.global_position = Vector2(900, 304)
	c.facing = -1
	c._apply_facing()
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	for i in 10:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	return c


# ---------------------------------------------------------------- 贴图本身

func test_every_clip_is_there_for_every_walker() -> void:
	for variant: StringName in VARIANTS:
		for clip: StringName in CLIPS:
			for side in ["r", "l"]:
				var path := "%s/%s/%s_%s.png" % [ART, variant, clip, side]
				var texture := load(path) as Texture2D
				check("%s %s_%s exists" % [variant, clip, side], texture != null, path)
				if texture != null:
					check("%s %s_%s is one row of %dx%d frames" % [variant, clip, side, FW, FH],
						texture.get_height() == FH and texture.get_width() % FW == 0,
						"%d x %d" % [texture.get_width(), texture.get_height()])


func test_the_two_facings_are_mirrors() -> void:
	for clip: StringName in [&"idle", &"attack_up", &"prone", &"death"]:
		var right := image(&"1_a", clip, "r")
		var left := image(&"1_a", clip, "l")
		var same := right.get_size() == left.get_size()
		if same:
			for y in right.get_height():
				for x in right.get_width():
					var f := x / FW
					var m := f * FW + 2 * AX - (x - f * FW)
					if m < f * FW or m >= (f + 1) * FW:
						continue
					var a := right.get_pixel(x, y)
					var b := left.get_pixel(m, y)
					if a.a != b.a or (a.a > 0.0 and a != b):
						same = false
		check("%s: left is the mirror of right around the anchor" % clip, same)


func test_the_three_walkers_differ_only_in_colour() -> void:
	# 同一套素材换色：轮廓（哪些像素不透明）一模一样，颜色不一样——一眼能分出 A/B/C，但动作完全同步
	for clip: StringName in [&"idle", &"attack_level"]:
		var a := image(&"1_a", clip)
		for other: StringName in [&"1_b", &"1_c"]:
			var b := image(other, clip)
			var same_shape := a.get_size() == b.get_size()
			var recoloured := 0
			if same_shape:
				for y in a.get_height():
					for x in a.get_width():
						var pa := a.get_pixel(x, y)
						var pb := b.get_pixel(x, y)
						if (pa.a > 0.03) != (pb.a > 0.03):
							same_shape = false
						elif pa.a > 0.03 and not pa.is_equal_approx(pb):
							recoloured += 1
			check("%s %s has the same outline as A" % [other, clip], same_shape)
			check("%s %s is recoloured" % [other, clip], recoloured > 20, "%d 个像素换了色" % recoloured)


func test_the_art_stands_on_the_collision_box() -> void:
	# 脚底落在身体原点下方 16px（碰撞体 32 高），和玩家同一条地面线
	for clip: StringName in [&"idle", &"walk", &"attack_level", &"death"]:
		var img := image(&"1_a", clip)
		for f in img.get_width() / FW:
			var lowest := -INF
			for p in ink(img, f):
				lowest = maxf(lowest, p.y)
			check("%s frame %d touches the ground" % [clip, f + 1], absf(lowest + 1.0 - 16.0) <= 1.0,
				"最低处在原点下方 %.0fpx" % (lowest + 1.0))


func test_the_prone_art_fits_the_rules() -> void:
	# 趴着的敌人：画面高度要和 12px 的判定框差不多，而且整个藏在玩家水平子弹下面——
	# 玩家站着平射本来就打不到趴着的敌人（得斜着往下打），画面上也不能看着像打中了。
	var shot_bottom := 16.0 - Player.LEVEL_MUZZLE.y - 2.0   # 玩家水平子弹最低处离地多高（子弹 4px 高）
	var img := image(&"1_c", &"prone")
	for f in img.get_width() / FW:
		var top := INF
		var lowest := -INF
		for p in ink(img, f, true):
			top = minf(top, p.y)
			lowest = maxf(lowest, p.y)
		var height := lowest + 1.0 - top
		check("prone frame %d lies on the ground" % (f + 1), absf(lowest + 1.0 - 16.0) <= 1.0,
			"最低处在原点下方 %.0fpx" % (lowest + 1.0))
		check("prone frame %d is about as tall as the hitbox" % (f + 1),
			height >= Enemy.PRONE_HEIGHT and height <= Enemy.PRONE_HEIGHT + 3.0,
			"贴图高 %.0fpx，判定框 %.0f" % [height, Enemy.PRONE_HEIGHT])
		check("prone frame %d stays under the player's level fire" % (f + 1), height < shot_bottom,
			"贴图高 %.0fpx，玩家水平子弹最低离地 %.0fpx" % [height, shot_bottom])


# ---------------------------------------------------------------- 子弹从画面上的枪口出来

func test_bullets_leave_from_the_gun_in_the_art() -> void:
	var c := await place_c(skin(), 460.0)
	c.set_physics_process(false)
	c.facing = 1
	# 水平
	c._burst_aim = Enemy.Aim.LEVEL
	c._burst_direction = Vector2.RIGHT
	var rule := c._muzzle_position() - c.global_position
	var art := tip(ink(image(&"1_c", &"attack_level"), 0, true), Vector2.RIGHT)
	check("level: shots leave from the barrel", art.distance_to(rule) <= 3.0, "贴图 %s，出膛点 %s" % [art, rule])
	# 斜上 / 斜下（斜下只看腰以上：脚尖比枪口还往右下）
	for pair in [[Enemy.Aim.DIAGONAL_UP, &"attack_up", Vector2(1, -1), INF],
			[Enemy.Aim.DIAGONAL_DOWN, &"attack_down", Vector2(1, 1), 8.0]]:
		c._burst_aim = pair[0]
		c._burst_direction = (pair[2] as Vector2).normalized()
		rule = c._muzzle_position() - c.global_position
		art = tip(ink(image(&"1_c", pair[1]), 0, true), pair[2], pair[3])
		check("%s: shots leave from the barrel" % pair[1], art.distance_to(rule) <= 3.0, "贴图 %s，出膛点 %s" % [art, rule])
	# 趴着
	c.set_prone(true)
	rule = c.level_muzzle_position() - c.global_position
	art = tip(ink(image(&"1_c", &"prone"), 0, true), Vector2.RIGHT)
	check("prone: shots leave from the barrel", art.distance_to(rule) <= 3.0, "贴图 %s，出膛点 %s" % [art, rule])


# ---------------------------------------------------------------- 换皮肤不改变规则

func measure(pack: SkinPack) -> Dictionary:
	var c := await place_c(pack, 460.0)   # 玩家在射程外：C 只管巡逻
	var out := {}
	out["level_muzzle"] = c.level_muzzle_position() - c.global_position
	out["body_center"] = c.body_center() - c.global_position
	out["box"] = (c._shape.shape as RectangleShape2D).size
	var x0 := c.global_position.x
	for i in 40:
		await tree.physics_frame
	out["patrol"] = snappedf(c.global_position.x - x0, 0.01)
	# 冻住 AI 再让它趴下：玩家没趴，不冻的话它下一帧就自己站起来，量到的又是站姿
	c.set_physics_process(false)
	c.set_prone(true)
	await frames(2)
	out["prone_box"] = (c._shape.shape as RectangleShape2D).size
	out["prone_muzzle"] = c.level_muzzle_position() - c.global_position
	return out


func test_the_sprite_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var sprites := await measure(skin())
	check("the walker really lies down in this test", blocks["prone_box"].y == Enemy.PRONE_HEIGHT, str(blocks["prone_box"]))
	# 先确认真的在巡逻：卡住不动的话下面「两种皮肤走得一样远」比的是两个 0，什么也证明不了
	check("the walker really patrols in this test", absf(blocks["patrol"]) > 20.0, str(blocks["patrol"]))
	for key: String in blocks:
		check("%s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])


# ---------------------------------------------------------------- 接上去以后

func test_each_walker_wears_its_own_colours() -> void:
	await reset_scene(true, false, skin())
	# 测试关（`main.tscn`）里的节点名还是老的 WalkerA/B/C（那是夹具，被一堆用例引用着），
	# 贴图目录已经按新编号改成 1_a/1_b/1_c，所以这里要把两边对起来。
	for pair in [["WalkerA", "1_a"], ["WalkerB", "1_b"], ["WalkerC", "1_c"]]:
		var name: String = pair[0]
		var visual: Node = main.get_node("Enemies/%s/Visual" % name)
		check("%s wears the sprite appearance" % name, visual is EnemySpriteAppearance, str(visual))
		if visual is EnemySpriteAppearance:
			check("%s uses its own art" % name, (visual as EnemySpriteAppearance).art_dir.ends_with(pair[1]),
				(visual as EnemySpriteAppearance).art_dir)


func test_clips_follow_what_the_walker_is_doing() -> void:
	var c := await place_c(skin(), 460.0)
	var visual: EnemySpriteAppearance = c.get_node("Visual")
	await frames(5)
	check("patrolling: walk", visual.clip() == &"walk", str(visual.clip()))
	c.move_speed = 0.0
	await frames(3)
	check("standing still: idle", visual.clip() == &"idle", str(visual.clip()))
	# 开一枪：播一遍水平开火，然后回到待机
	visual.fire()
	check("firing plays the level shot", visual.clip() == &"attack_level", str(visual.clip()))
	var seen := {}
	for i in 30:
		await frames(1)
		seen[visual.clip()] = true
	check("and goes back to idle when the shot is done", visual.clip() == &"idle", str(visual.clip()))
	# 斜着瞄准：举着枪停在第一帧，开火才播
	visual.aim(Vector2(-1, -1).normalized())
	await frames(2)
	check("aiming up holds the up pose", visual.clip() == &"attack_up" and visual.get_node("Body").frame == 0,
		"%s / %d" % [visual.clip(), visual.get_node("Body").frame])
	visual.aim(Vector2(-1, 1).normalized())
	await frames(2)
	check("aiming down holds the down pose", visual.clip() == &"attack_down", str(visual.clip()))
	visual.aim(Vector2.LEFT)
	# 趴下（冻住 C 的 AI：玩家没趴，它下一帧会自己站起来）
	c.set_physics_process(false)
	c.set_prone(true)
	await frames(2)
	check("lying down: prone, still", visual.clip() == &"prone" and visual.get_node("Body").frame == 0, str(visual.clip()))
	visual.fire()
	await frames(8)   # 12 帧/秒：等 0.13 秒才翻到第 2 帧
	check("firing while prone plays the prone shot", visual.clip() == &"prone" and visual.get_node("Body").frame > 0,
		str(visual.get_node("Body").frame))
	c.set_prone(false)
	# 受伤
	c.take_damage(1)
	check("getting hit plays the hurt clip", visual.clip() == &"hurt", str(visual.clip()))


func test_the_walker_really_fires_its_shot_pose() -> void:
	# 真打一枪（玩家在它正前方）：玩法调 fire()，外观就播开火
	var c := await place_c(skin())
	var visual: EnemySpriteAppearance = c.get_node("Visual")
	var fired := false
	for i in 200:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() == &"attack_level":
			fired = true
			break
	check("the walker shows its shot pose when it fires", fired)
	check("and a bullet really left", not bullets(16).is_empty())


func test_dying_leaves_a_body_that_falls_and_fades() -> void:
	var c := await place_c(skin(), 460.0)
	var visual: EnemySpriteAppearance = c.get_node("Visual")
	c.take_damage(c.health)
	await frames(1)
	check("the enemy itself is gone at once", not is_instance_valid(c))
	check("its body stays behind in the effects layer", is_instance_valid(visual) and visual.get_parent() is Fx,
		str(visual.get_parent()) if is_instance_valid(visual) else "freed")
	if not is_instance_valid(visual):
		return
	check("and plays the fall", visual.clip() == &"death", str(visual.clip()))
	check("the body has no collision (pure effect)", visual.find_children("*", "CollisionObject2D", true, false).is_empty())
	var gone_at := -1
	for i in 150:
		await tree.physics_frame
		if not is_instance_valid(visual):
			gone_at = i
			break
	check("then fades out and removes itself", gone_at > 30, "第 %d 帧消失" % gone_at)


# ---------------------------------------------------------------- 飞行的 E（5 号无人机）
# 它不站在地上：判定框 28×20 以原点为中心，所以贴图对的是机身中心，帧也是另一种尺寸（48×48，锚点 24, 24）。

const E_CLIPS := [&"idle", &"attack_down", &"hurt", &"death"]
const E_SIZE := 48
const E_ANCHOR := 24
## 素材里往下劈的闪电（E 的子弹在画面上从这里出来）。
const BOLT := Color8(91, 236, 241)


func e_image(clip: StringName, side := "r") -> Image:
	return (load("%s/1_e/%s_%s.png" % [ART, clip, side]) as Texture2D).get_image()


## E 某一帧看得见的像素（本体坐标）；only_bolt 只要闪电，否则只要机身（不算闪电）。
func e_ink(img: Image, frame: int, only_bolt := false) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y in E_SIZE:
		for x in E_SIZE:
			var c := img.get_pixel(frame * E_SIZE + x, y)
			if c.a <= 0.03 or c.is_equal_approx(BOLT) != only_bolt:
				continue
			out.append(Vector2(x - E_ANCHOR, y - E_ANCHOR))
	return out


## 只留 E、以 x 上空为巡逻中心，玩家先放在远处（不在它下方）。
func place_e(pack: SkinPack, x := 400.0) -> EnemyFlyer:
	await reset_scene(true, false, pack)
	keep_only_enemies(["FlyerE"])
	var e: EnemyFlyer = main.get_node("Enemies/FlyerE")
	e.set_anchor(Vector2(x, 88))
	e.is_following = false # 关卡加载时它可能已经看见玩家开始跟随了
	player.global_position = Vector2(x + 700.0, 304) # E 在屏幕外、看不见玩家，照常巡逻
	player.velocity = Vector2.ZERO
	snap_camera()
	await frames(3)
	return e


func test_every_clip_is_there_for_the_flyer() -> void:
	for clip: StringName in E_CLIPS:
		for side in ["r", "l"]:
			var path := "%s/1_e/%s_%s.png" % [ART, clip, side]
			var texture := load(path) as Texture2D
			check("flyer %s_%s exists" % [clip, side], texture != null, path)
			if texture != null:
				check("flyer %s_%s is one row of %dx%d frames" % [clip, side, E_SIZE, E_SIZE],
					texture.get_height() == E_SIZE and texture.get_width() % E_SIZE == 0,
					"%d x %d" % [texture.get_width(), texture.get_height()])
	var scene: EnemySpriteAppearance = (load("res://scenes/skins/cyberpunk_1_e.tscn") as PackedScene).instantiate()
	check("the flyer scene uses the flyer frame size", scene.frame_size == Vector2i(E_SIZE, E_SIZE)
		and scene.anchor == Vector2i(E_ANCHOR, E_ANCHOR), "%s / %s" % [scene.frame_size, scene.anchor])
	scene.free()


func test_the_flyer_facings_are_mirrors() -> void:
	for clip: StringName in E_CLIPS:
		var right := e_image(clip, "r")
		var left := e_image(clip, "l")
		var same := right.get_size() == left.get_size()
		if same:
			for y in right.get_height():
				for x in right.get_width():
					var f := x / E_SIZE
					var m := f * E_SIZE + 2 * E_ANCHOR - (x - f * E_SIZE)
					if m < f * E_SIZE or m >= (f + 1) * E_SIZE:
						continue
					var a := right.get_pixel(x, y)
					var b := left.get_pixel(m, y)
					if a.a != b.a or (a.a > 0.0 and a != b):
						same = false
		check("flyer %s: left is the mirror of right around the anchor" % clip, same)


func test_the_flyer_art_sits_on_its_hitbox() -> void:
	# 判定框 28×20 以原点为中心：悬停那几帧的飞行器（含螺旋桨）要落在框里，而且居中。
	# 素材的悬停动画自己会上下浮动 3px，纵向留这点余量
	var box := Vector2(28, 20)
	var bob := 3.0
	var img := e_image(&"idle")
	for f in img.get_width() / E_SIZE:
		var points := e_ink(img, f)
		var r := Rect2(points[0], Vector2.ZERO)
		for p in points:
			r = r.expand(p)
		r.size += Vector2.ONE
		check("idle frame %d is inside the hitbox" % (f + 1),
			r.position.x >= -box.x / 2.0 and r.end.x <= box.x / 2.0
			and r.position.y >= -box.y / 2.0 - bob and r.end.y <= box.y / 2.0 + bob, str(r))
		check("idle frame %d is centred on it" % (f + 1),
			absf(r.get_center().x) <= 1.5 and absf(r.get_center().y) <= bob, str(r.get_center()))


func test_the_flyer_shoots_from_the_bolt_in_the_art() -> void:
	# 放电那几帧：闪电从机身底下劈出来，E 的子弹也要从那里出来。
	# 只看前 3 帧：第 4 帧闪电已经散成火花，没有「起点」。机身在浮动，起点跟着上下差 4px，出膛点取中间
	var e := await place_e(skin())
	e.set_physics_process(false)
	e._burst_aim = Enemy.Aim.LEVEL
	e._burst_direction = Vector2.DOWN
	var rule := e._muzzle_position() - e.global_position
	var img := e_image(&"attack_down")
	var starts: Array[Vector2] = []
	for f in 3:
		var bolt := e_ink(img, f, true)
		if bolt.is_empty():
			continue
		var top := INF
		for p in bolt:
			top = minf(top, p.y)
		var nearest := Vector2(INF, top)
		for p in bolt:
			if p.y == top and absf(p.x) < absf(nearest.x):
				nearest = p
		starts.append(nearest)
	check("the bolt is drawn in the attack frames", starts.size() == 3, str(starts))
	for s in starts:
		check("the bolt starts where the shots leave (%s)" % s, s.distance_to(rule) <= 3.0,
			"贴图 %s，出膛点 %s" % [s, rule])


func measure_e(pack: SkinPack) -> Dictionary:
	var e := await place_e(pack)
	var out := {}
	out["muzzle"] = e.level_muzzle_position() - e.global_position
	out["box"] = (e._shape.shape as RectangleShape2D).size
	var start := e.global_position
	for i in 40:
		await tree.physics_frame
	out["travel"] = (e.global_position - start).snappedf(0.01)
	return out


func test_the_flyer_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure_e(Skins.default_skin())
	var sprites := await measure_e(skin())
	# 先确认真的在飞：停着不动的话「两种皮肤飞得一样」比的是两个 0
	check("the flyer really moves in this test",
		absf(blocks["travel"].x) > 20.0 and absf(blocks["travel"].y) > 1.0, str(blocks["travel"]))
	for key: String in blocks:
		check("flyer %s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])


func test_the_flyer_wears_the_drone() -> void:
	await reset_scene(true, false, skin())
	var visual: Node = main.get_node("Enemies/FlyerE/Visual")
	check("E wears the sprite appearance", visual is EnemySpriteAppearance, str(visual))
	if visual is EnemySpriteAppearance:
		check("E uses the drone art", (visual as EnemySpriteAppearance).art_dir.ends_with("/1_e"),
			(visual as EnemySpriteAppearance).art_dir)


func test_the_flyer_hovers_and_zaps() -> void:
	# E 一直朝正下方瞄准，但那不是「举着枪等开火」：平时要显示悬停，只有开火那一下才放电
	var e := await place_e(skin())
	var visual: EnemySpriteAppearance = e.get_node("Visual")
	var body: Sprite2D = visual.get_node("Body")
	await frames(5)
	check("patrolling: hovers", visual.clip() == &"idle", str(visual.clip()))
	var frames_seen := {}
	for i in 30:
		await frames(1)
		frames_seen[body.frame] = true
	check("and the rotor spins", frames_seen.size() > 1, str(frames_seen.keys()))
	e.move_speed = 0.0
	e.set_anchor(Vector2(400, 88))
	player.global_position = Vector2(400, 304)
	var zapped := false
	for i in 60:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() == &"attack_down":
			zapped = true
			break
	check("E zaps when it fires", zapped)
	check("and a bullet really left", not bullets(16).is_empty())
	var back := false
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() == &"idle":
			back = true
			break
	check("then goes back to hovering", back)
	e.take_damage(1)
	check("getting hit plays the hurt clip", visual.clip() == &"hurt", str(visual.clip()))


func test_a_shot_down_flyer_falls_and_fades() -> void:
	var e := await place_e(skin())
	var visual: EnemySpriteAppearance = e.get_node("Visual")
	e.take_damage(e.health)
	await frames(1)
	check("E itself is gone at once", not is_instance_valid(e))
	check("the wreck stays behind in the effects layer", is_instance_valid(visual) and visual.get_parent() is Fx)
	if is_instance_valid(visual):
		check("and plays the crash", visual.clip() == &"death", str(visual.clip()))


# ---------------------------------------------------------------- 炮台（6 号履带炮塔）
# 素材只有水平炮管，斜上 / 斜下是手改的，由生成脚本移植到攻击、受伤帧上。

const T_CLIPS := [&"idle", &"idle_up", &"idle_down", &"attack_level", &"attack_up", &"attack_down",
	&"hurt", &"hurt_up", &"hurt_down", &"death"]


func t_image(clip: StringName, side := "r") -> Image:
	return image(&"1_g", clip, side)


## 只留一座炮台，摆在右边空地上朝左；玩家在 player_x（默认在射程外）。
func place_turret(pack: SkinPack, player_x := 400.0) -> EnemyTurret:
	await reset_scene(true, false, pack)
	keep_only_enemies(["Turret1"])
	var t: EnemyTurret = main.get_node("Enemies/Turret1")
	t.global_position = Vector2(1000, 304)
	t.facing = -1
	t._apply_visual_facing()
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	for i in 10:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	return t


func test_every_clip_is_there_for_the_turret() -> void:
	for clip: StringName in T_CLIPS:
		for side in ["r", "l"]:
			var path := "%s/1_g/%s_%s.png" % [ART, clip, side]
			var texture := load(path) as Texture2D
			check("turret %s_%s exists" % [clip, side], texture != null, path)
			if texture != null:
				check("turret %s_%s is one row of %dx%d frames" % [clip, side, FW, FH],
					texture.get_height() == FH and texture.get_width() % FW == 0,
					"%d x %d" % [texture.get_width(), texture.get_height()])


func test_the_turret_facings_are_mirrors() -> void:
	for clip: StringName in [&"idle", &"attack_up", &"hurt_down", &"death"]:
		var right := t_image(clip, "r")
		var left := t_image(clip, "l")
		var same := right.get_size() == left.get_size()
		if same:
			for y in right.get_height():
				for x in right.get_width():
					var f := x / FW
					var m := f * FW + 2 * AX - (x - f * FW)
					if m < f * FW or m >= (f + 1) * FW:
						continue
					var a := right.get_pixel(x, y)
					var b := left.get_pixel(m, y)
					if a.a != b.a or (a.a > 0.0 and a != b):
						same = false
		check("turret %s: left is the mirror of right around the anchor" % clip, same)


func test_the_turret_stands_on_the_ground() -> void:
	# 履带底落在原点下方 16px（碰撞体 32 高），不管炮管朝哪
	for clip: StringName in [&"idle", &"idle_up", &"idle_down", &"attack_up", &"attack_down"]:
		var img := t_image(clip)
		for f in img.get_width() / FW:
			var lowest := -INF
			for p in ink(img, f):
				lowest = maxf(lowest, p.y)
			check("turret %s frame %d stands on the ground" % [clip, f + 1], absf(lowest + 1.0 - 16.0) <= 1.0,
				"最低处在原点下方 %.0fpx" % (lowest + 1.0))


func test_turret_shots_leave_from_the_barrel_in_the_art() -> void:
	var t := await place_turret(skin())
	t.set_physics_process(false)
	t.facing = 1
	for case in [[Enemy.Aim.LEVEL, &"attack_level", Vector2.RIGHT],
			[Enemy.Aim.DIAGONAL_UP, &"attack_up", Vector2(1, -1)],
			[Enemy.Aim.DIAGONAL_DOWN, &"attack_down", Vector2(1, 1)]]:
		t._burst_aim = case[0]
		t._burst_direction = (case[2] as Vector2).normalized()
		var rule := t._muzzle_position() - t.global_position
		# 只看炮管那一侧、履带以上（斜下时履带前端比炮口还往右下）
		var barrel: Array[Vector2] = []
		for p in ink(t_image(case[1]), 0):
			if p.x > 6.0 and p.y < 7.0:
				barrel.append(p)
		var art := tip(barrel, case[2])
		check("turret %s: shots leave from the barrel" % case[1], art.distance_to(rule) <= 3.0,
			"贴图 %s，出膛点 %s" % [art, rule])


func measure_turret(pack: SkinPack) -> Dictionary:
	var t := await place_turret(pack, 760.0)   # 玩家在射程内、同一高度：炮台转过来开火
	var out := {}
	out["level_muzzle"] = t.level_muzzle_position() - t.global_position
	out["diagonal_up"] = t.diagonal_up_muzzle
	out["diagonal_down"] = t.diagonal_down_muzzle
	out["box"] = (t._shape.shape as RectangleShape2D).size
	var shots := 0
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not bullets(16).is_empty():
			shots += 1
	out["facing"] = t.facing
	out["fired"] = shots > 0
	var found := bullets(16)
	out["shot_y"] = snappedf(found[0].global_position.y, 0.01) if not found.is_empty() else INF
	return out


func test_the_turret_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure_turret(Skins.default_skin())
	var sprites := await measure_turret(skin())
	check("the turret really turns and fires in this test", blocks["fired"] and blocks["facing"] == -1, str(blocks))
	for key: String in blocks:
		check("turret %s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])


func test_the_turret_wears_its_art() -> void:
	await reset_scene(true, false, skin())
	for name in ["Turret1", "Turret2"]:
		var visual: Node = main.get_node("Enemies/%s/Visual" % name)
		check("%s wears the sprite appearance" % name, visual is EnemySpriteAppearance, str(visual))
		if visual is EnemySpriteAppearance:
			check("%s uses the turret art" % name, (visual as EnemySpriteAppearance).art_dir.ends_with("/1_g"),
				(visual as EnemySpriteAppearance).art_dir)
			var sprite := visual as EnemySpriteAppearance
			check("%s draws the art at its anchor" % name, sprite.frame_size == Vector2i(FW, FH) and sprite.anchor == Vector2i(AX, AY),
				"%s / %s" % [sprite.frame_size, sprite.anchor])


func test_turret_clips_follow_its_aim() -> void:
	var t := await place_turret(skin())
	t.set_physics_process(false)
	var visual: EnemySpriteAppearance = t.get_node("Visual")
	var body: Sprite2D = visual.get_node("Body")
	check("idle: level barrel", visual.clip() == &"idle", str(visual.clip()))
	# 斜着瞄准：斜炮管照样有待机的上下浮动，不是定住
	visual.aim(Vector2(-1, -1).normalized())
	var seen := {}
	for i in 30:
		await frames(1)
		seen[body.frame] = true
	check("aiming up: the up barrel idles", visual.clip() == &"idle_up" and seen.size() > 1,
		"%s / 帧 %s" % [visual.clip(), seen.keys()])
	visual.fire()
	check("firing up plays the up shot", visual.clip() == &"attack_up", str(visual.clip()))
	for i in 30:
		await frames(1)
	check("and goes back to the up idle", visual.clip() == &"idle_up", str(visual.clip()))
	# 斜着挨打：用斜炮管那套受伤帧，炮管不会跳回水平
	visual.flash_hit()
	check("hit while aiming up keeps the up barrel", visual.clip() == &"hurt_up", str(visual.clip()))
	visual.aim(Vector2(-1, 1).normalized())
	await frames(20)
	check("aiming down: the down barrel idles", visual.clip() == &"idle_down", str(visual.clip()))
	visual.aim(Vector2.LEFT)
	await frames(2)
	check("back to level", visual.clip() == &"idle", str(visual.clip()))
	visual.flash_hit()
	check("hit while level: the level hurt", visual.clip() == &"hurt", str(visual.clip()))


func test_the_turret_really_fires_its_shot_pose() -> void:
	var t := await place_turret(skin(), 760.0)
	var visual: EnemySpriteAppearance = t.get_node("Visual")
	var fired := false
	for i in 200:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() == &"attack_level":
			fired = true
			break
	check("the turret shows its shot pose when it fires", fired)
	check("and a bullet really left", not bullets(16).is_empty())


# ---------------------------------------------------------------- D（3 号滑板手）和 F（1 号球棒手）

const SINGLE_CLIPS := {
	&"1_d": [&"idle", &"walk", &"run", &"air", &"hurt", &"death"],
	&"1_f": [&"idle", &"walk", &"attack_level", &"hurt", &"death"],
}


## 只留一个敌人，摆在右边空地上朝左；玩家在 player_x（默认远在射程外）。
func place_one(pack: SkinPack, node: String, player_x := 300.0) -> EnemyWalker:
	await reset_scene(true, false, pack)
	keep_only_enemies([node])
	var e: EnemyWalker = main.get_node("Enemies/" + node)
	e.global_position = Vector2(1000, 304)
	e.facing = -1
	e._apply_facing()
	# 关卡加载那两帧它可能已经开过火 / 扔过手雷：冷却清零，免得带进测量
	e._fire_timer = 0.0
	if e is EnemyGrenadier:
		(e as EnemyGrenadier)._throw_timer = 0.0
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	for i in 10:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	return e


func test_every_clip_is_there_for_d_and_f() -> void:
	for who: StringName in SINGLE_CLIPS:
		for clip: StringName in SINGLE_CLIPS[who]:
			for side in ["r", "l"]:
				var path := "%s/%s/%s_%s.png" % [ART, who, clip, side]
				var texture := load(path) as Texture2D
				check("%s %s_%s exists" % [who, clip, side], texture != null, path)
				if texture != null:
					check("%s %s_%s is one row of %dx%d frames" % [who, clip, side, FW, FH],
						texture.get_height() == FH and texture.get_width() % FW == 0,
						"%d x %d" % [texture.get_width(), texture.get_height()])


func test_d_and_f_facings_are_mirrors() -> void:
	for who: StringName in SINGLE_CLIPS:
		for clip: StringName in SINGLE_CLIPS[who]:
			var right := image(who, clip, "r")
			var left := image(who, clip, "l")
			var same := right.get_size() == left.get_size()
			if same:
				for y in right.get_height():
					for x in right.get_width():
						var f := x / FW
						var m := f * FW + 2 * AX - (x - f * FW)
						if m < f * FW or m >= (f + 1) * FW:
							continue
						var a := right.get_pixel(x, y)
						var b := left.get_pixel(m, y)
						if a.a != b.a or (a.a > 0.0 and a != b):
							same = false
			check("%s %s: left is the mirror of right around the anchor" % [who, clip], same)


func test_d_and_f_stand_on_the_ground() -> void:
	for who: StringName in SINGLE_CLIPS:
		for clip: StringName in SINGLE_CLIPS[who]:
			if clip == &"air" or clip == &"death":
				continue # 空中那帧本来就离地；倒地的最后几帧人扑在地上，脚不在最低处
			var img := image(who, clip)
			for f in img.get_width() / FW:
				var lowest := -INF
				for p in ink(img, f):
					lowest = maxf(lowest, p.y)
				check("%s %s frame %d stands on the ground" % [who, clip, f + 1], absf(lowest + 1.0 - 16.0) <= 1.0,
					"最低处在原点下方 %.0fpx" % (lowest + 1.0))


func test_d_and_f_wear_their_art() -> void:
	await reset_scene(true, false, skin())
	for pair in [["ChaserD", "/1_d"], ["WalkerF", "/1_f"]]:
		var visual: Node = main.get_node("Enemies/%s/Visual" % pair[0])
		check("%s wears the sprite appearance" % pair[0], visual is EnemySpriteAppearance, str(visual))
		if visual is EnemySpriteAppearance:
			var sprite := visual as EnemySpriteAppearance
			check("%s uses its own art" % pair[0], sprite.art_dir.ends_with(pair[1]), sprite.art_dir)
			check("%s draws the art at its anchor" % pair[0], sprite.frame_size == Vector2i(FW, FH) and sprite.anchor == Vector2i(AX, AY),
				"%s / %s" % [sprite.frame_size, sprite.anchor])


func test_d_skates_charges_and_jumps() -> void:
	var d := await place_one(skin(), "ChaserD") as EnemyChaser
	var visual: EnemySpriteAppearance = d.get_node("Visual")
	await frames(5)
	check("patrolling: skates along", visual.clip() == &"walk", str(visual.clip()))
	# 玩家走进它的视线：冲过来，换成站在板上冲的那组
	player.global_position = Vector2(820, 304)
	var charged := false
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if d.is_chasing and visual.clip() == &"run":
			charged = true
			break
	check("charging: rides the board", charged, "%s / chasing %s" % [visual.clip(), d.is_chasing])
	# 起跳：空中那一帧
	d.velocity.y = d.jump_velocity
	var airborne := false
	for i in 10:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not d.is_on_floor() and visual.clip() == &"air":
			airborne = true
			break
	check("jumping: the air pose", airborne, str(visual.clip()))
	d.take_damage(1)
	check("getting hit plays the hurt clip", visual.clip() == &"hurt", str(visual.clip()))


func measure_d(pack: SkinPack) -> Dictionary:
	var d := await place_one(pack, "ChaserD") as EnemyChaser
	var out := {}
	out["box"] = (d._shape.shape as RectangleShape2D).size
	var x0 := d.global_position.x
	for i in 40:
		await tree.physics_frame
	out["patrol"] = snappedf(d.global_position.x - x0, 0.01)
	player.global_position = Vector2(820, 304)
	x0 = d.global_position.x
	for i in 40:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	out["chasing"] = d.is_chasing
	out["charge"] = snappedf(d.global_position.x - x0, 0.01)
	return out


func test_d_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure_d(Skins.default_skin())
	var sprites := await measure_d(skin())
	check("D really patrols and charges in this test",
		absf(blocks["patrol"]) > 20.0 and blocks["chasing"] and absf(blocks["charge"]) > 60.0, str(blocks))
	for key: String in blocks:
		check("D %s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])


func test_f_bats_the_grenade_out_of_the_swing() -> void:
	# 出手点落在挥棒那一帧的弧光上：画面上手雷是从球棒打到的地方飞出去的
	var offset := EnemyGrenadier.THROW_OFFSET
	var near := INF
	for p in ink(image(&"1_f", &"attack_level"), 0):
		near = minf(near, p.distance_to(offset))
	check("the grenade leaves from the swing", near <= 2.0, "出手点 %s 离弧光最近 %.1fpx" % [offset, near])


func test_f_swings_when_it_throws() -> void:
	var f := await place_one(skin(), "WalkerF", 800.0) as EnemyGrenadier
	var visual: EnemySpriteAppearance = f.get_node("Visual")
	var swung := false
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() == &"attack_level":
			swung = true
			break
	check("F swings its bat when it throws", swung)
	check("and a grenade really flew", not tree.get_nodes_in_group(Grenade.GROUP).is_empty())
	var back := false
	for i in 40:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if visual.clip() != &"attack_level":
			back = true
			break
	check("then goes back to walking", back, str(visual.clip()))


func measure_f(pack: SkinPack) -> Dictionary:
	var f := await place_one(pack, "WalkerF", 800.0) as EnemyGrenadier
	var out := {}
	out["box"] = (f._shape.shape as RectangleShape2D).size
	# 手雷飞一会儿就炸了、被释放，所以一看到就记下位置
	var thrown: Array = []
	var first_from := Vector2.INF
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		for g: Node2D in tree.get_nodes_in_group(Grenade.GROUP):
			if not thrown.has(g):
				if thrown.is_empty():
					first_from = g.global_position.snappedf(0.01)
				thrown.append(g)
	out["throws"] = thrown.size()
	out["first_from"] = first_from
	return out


func test_f_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure_f(Skins.default_skin())
	var sprites := await measure_f(skin())
	check("F really throws in this test", blocks["throws"] > 0, str(blocks))
	for key: String in blocks:
		check("F %s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])


# ---------------------------------------------------------------- Boss A（boss 包 2 号，导弹机甲）
# 素材不缩放：判定框按它改成 56×48；帧 96×80、锚点 (48, 56)，脚底在原点下方 24px。

const B_CLIPS := [&"idle", &"walk", &"attack_level", &"attack_walk", &"air", &"hurt", &"death"]
const B_W := 96
const B_H := 80
const B_AX := 48
const B_AY := 56


## Boss 某一帧看得见的像素（本体坐标）。
func b_ink(img: Image, frame: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y in B_H:
		for x in B_W:
			if img.get_pixel(frame * B_W + x, y).a > 0.03:
				out.append(Vector2(x - B_AX, y - B_AY))
	return out


## 只留 Boss、让它出场、站定不跳，玩家在 player_x。
func place_boss(pack: SkinPack, player_x := 900.0) -> BossMissile:
	await reset_scene(true, false, pack)
	keep_only_enemies(["BossMissile"])
	var boss: BossMissile = main.get_node("Enemies/BossMissile")
	player.health = 999
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	boss.appear()
	return boss


func test_every_clip_is_there_for_the_boss() -> void:
	for clip: StringName in B_CLIPS:
		for side in ["r", "l"]:
			var path := "%s/1_boss/%s_%s.png" % [ART, clip, side]
			var texture := load(path) as Texture2D
			check("boss %s_%s exists" % [clip, side], texture != null, path)
			if texture != null:
				check("boss %s_%s is one row of %dx%d frames" % [clip, side, B_W, B_H],
					texture.get_height() == B_H and texture.get_width() % B_W == 0,
					"%d x %d" % [texture.get_width(), texture.get_height()])


func test_the_boss_facings_are_mirrors() -> void:
	for clip: StringName in [&"idle", &"attack_walk", &"air", &"death"]:
		var right := image(&"1_boss", clip, "r")
		var left := image(&"1_boss", clip, "l")
		var same := right.get_size() == left.get_size()
		if same:
			for y in right.get_height():
				for x in right.get_width():
					var f := x / B_W
					var m := f * B_W + 2 * B_AX - (x - f * B_W)
					if m < f * B_W or m >= (f + 1) * B_W:
						continue
					var a := right.get_pixel(x, y)
					var b := left.get_pixel(m, y)
					if a.a != b.a or (a.a > 0.03 and a != b):
						same = false
		check("boss %s: left is the mirror of right around the anchor" % clip, same)


func test_the_boss_art_fits_its_hitbox() -> void:
	# 脚底落在判定框底边（原点下方 24px），机身和判定框差不多大（判定框略小一圈，擦边不算打中）
	var box := Vector2(56, 48)
	for clip: StringName in [&"idle", &"walk", &"attack_level", &"attack_walk", &"hurt"]:
		var img := image(&"1_boss", clip)
		for f in img.get_width() / B_W:
			var points := b_ink(img, f)
			var r := Rect2(points[0], Vector2.ZERO)
			for p in points:
				r = r.expand(p)
			r.size += Vector2.ONE
			check("boss %s frame %d stands on the ground" % [clip, f + 1], absf(r.end.y - box.y / 2.0) <= 1.0,
				"最低处在原点下方 %.0fpx" % r.end.y)
			check("boss %s frame %d is about the size of its hitbox" % [clip, f + 1],
				r.size.x >= box.x and r.size.x <= box.x + 12.0 and r.size.y >= box.y and r.size.y <= box.y + 8.0, str(r))
			# 走路那几帧后腿往后甩一大步，包围盒中心会偏 3~4px，是步态不是没对齐
			check("boss %s frame %d is centred on it" % [clip, f + 1], absf(r.get_center().x) <= 4.0, str(r.get_center()))


func test_missiles_leave_from_the_pod_in_the_art() -> void:
	# 出膛点在画面上的导弹巢口：离它最近的机身像素不超过 3px，而且在机身顶部那一截
	var muzzle := BossMissile.POD_MUZZLE
	var near := INF
	for p in b_ink(image(&"1_boss", &"attack_level"), 1):
		near = minf(near, p.distance_to(muzzle))
	check("the missile pod mouth is on the art", near <= 3.0, "出膛点 %s 离贴图最近 %.1fpx" % [muzzle, near])
	check("and it is up on the pod, not the hull", muzzle.y < -16.0, str(muzzle))


func test_the_boss_wears_its_art_and_portrait() -> void:
	var boss := await place_boss(skin())
	var visual: Node = boss.get_node("Visual")
	check("the boss wears the sprite appearance", visual is EnemySpriteAppearance, str(visual))
	if visual is EnemySpriteAppearance:
		var sprite := visual as EnemySpriteAppearance
		check("the boss draws its art at its anchor", sprite.frame_size == Vector2i(B_W, B_H) and sprite.anchor == Vector2i(B_AX, B_AY),
			"%s / %s" % [sprite.frame_size, sprite.anchor])
	var hud_portrait: TextureRect = main.get_node("HUD/BossBar/Portrait")
	check("the HUD shows the skin's portrait", hud_portrait.texture != null and hud_portrait.texture == boss.hud_portrait()
		and hud_portrait.texture != boss.portrait, str(hud_portrait.texture))
	# 默认包：还是场景里配的占位头像
	var plain := await place_boss(Skins.default_skin())
	check("the default pack keeps the placeholder portrait", (main.get_node("HUD/BossBar/Portrait") as TextureRect).texture == plain.portrait)


func test_boss_clips_follow_what_it_does() -> void:
	var boss := await place_boss(skin())
	var visual: EnemySpriteAppearance = boss.get_node("Visual")
	boss._fire_timer = 999.0
	var seen := {}
	for i in 240:
		await frames(1)
		seen[visual.clip()] = true
	check("walks around (walk)", seen.has(&"walk"), str(seen.keys()))
	check("jumps (air)", seen.has(&"air"), str(seen.keys()))
	# 边走边打：播边走边发射那组
	visual.motion(Appearance.Motion.WALK)
	visual.fire()
	check("firing while walking: attack_walk", visual.clip() == &"attack_walk", str(visual.clip()))
	await frames(40)
	visual.motion(Appearance.Motion.IDLE)
	visual.fire()
	check("firing while standing: attack_level", visual.clip() == &"attack_level", str(visual.clip()))
	boss.take_damage(1)
	check("getting hit: hurt", visual.clip() == &"hurt", str(visual.clip()))


func measure_boss(pack: SkinPack) -> Dictionary:
	var boss := await place_boss(pack)
	seed(7)
	boss.roam_speed = 0.0
	boss._jump_timer = 999.0
	boss.jump_interval_min = 999.0
	boss.jump_interval_max = 999.0
	var out := {}
	out["box"] = (boss._shape.shape as RectangleShape2D).size
	out["muzzle"] = boss._muzzle_position() - boss.global_position
	boss._fire_timer = 0.0
	var volley := []
	for i in 30:
		player._invincible_timer = 1000.0
		await frames(1)
		volley = bullets(16)
		if not volley.is_empty():
			break
	out["volley"] = volley.size()
	out["directions"] = str(volley.map(func(b: Bullet) -> Vector2: return b.direction.snapped(Vector2(0.001, 0.001))))
	out["resting_y"] = snappedf(boss.global_position.y, 0.01)
	return out


func test_the_boss_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure_boss(Skins.default_skin())
	var sprites := await measure_boss(skin())
	check("the boss really fires a volley in this test", blocks["volley"] > 1, str(blocks))
	for key: String in blocks:
		check("boss %s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])
