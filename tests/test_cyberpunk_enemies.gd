extends GameTest
## 赛博朋克皮肤包的敌人贴图（目前是巡逻兵 A/B/C，素材 2 号换色；飞行的 E，素材 5 号无人机）。
##
## 和玩家那组（test_cyberpunk_skin.gd）守的是同一类东西：贴图齐全、左右严格镜像、脚底落在地面线上、
## 子弹从画面上的枪口出来，以及最要紧的——**换皮肤不改变规则**：同一个敌人用方块和用精灵图，
## 出膛点、碰撞体、巡逻走多远、趴下后多高，数字必须一模一样。
## 贴图由 tools/enemy_build.py 生成，改素材后要重新跑它。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART := "res://skins/cyberpunk/enemies"
const VARIANTS := [&"walker_a", &"walker_b", &"walker_c"]
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
		var right := image(&"walker_a", clip, "r")
		var left := image(&"walker_a", clip, "l")
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
		var a := image(&"walker_a", clip)
		for other: StringName in [&"walker_b", &"walker_c"]:
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
		var img := image(&"walker_a", clip)
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
	var img := image(&"walker_c", &"prone")
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
	var art := tip(ink(image(&"walker_c", &"attack_level"), 0, true), Vector2.RIGHT)
	check("level: shots leave from the barrel", art.distance_to(rule) <= 3.0, "贴图 %s，出膛点 %s" % [art, rule])
	# 斜上 / 斜下（斜下只看腰以上：脚尖比枪口还往右下）
	for pair in [[Enemy.Aim.DIAGONAL_UP, &"attack_up", Vector2(1, -1), INF],
			[Enemy.Aim.DIAGONAL_DOWN, &"attack_down", Vector2(1, 1), 8.0]]:
		c._burst_aim = pair[0]
		c._burst_direction = (pair[2] as Vector2).normalized()
		rule = c._muzzle_position() - c.global_position
		art = tip(ink(image(&"walker_c", pair[1]), 0, true), pair[2], pair[3])
		check("%s: shots leave from the barrel" % pair[1], art.distance_to(rule) <= 3.0, "贴图 %s，出膛点 %s" % [art, rule])
	# 趴着
	c.set_prone(true)
	rule = c.level_muzzle_position() - c.global_position
	art = tip(ink(image(&"walker_c", &"prone"), 0, true), Vector2.RIGHT)
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
	for name in ["WalkerA", "WalkerB", "WalkerC"]:
		var visual: Node = main.get_node("Enemies/%s/Visual" % name)
		check("%s wears the sprite appearance" % name, visual is EnemySpriteAppearance, str(visual))
		if visual is EnemySpriteAppearance:
			check("%s uses its own art" % name, (visual as EnemySpriteAppearance).art_dir.ends_with(name.to_lower().replace("walker", "walker_")),
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
	return (load("%s/flyer/%s_%s.png" % [ART, clip, side]) as Texture2D).get_image()


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
	player.global_position = Vector2(x + 400.0, 304)
	player.velocity = Vector2.ZERO
	await frames(3)
	return e


func test_every_clip_is_there_for_the_flyer() -> void:
	for clip: StringName in E_CLIPS:
		for side in ["r", "l"]:
			var path := "%s/flyer/%s_%s.png" % [ART, clip, side]
			var texture := load(path) as Texture2D
			check("flyer %s_%s exists" % [clip, side], texture != null, path)
			if texture != null:
				check("flyer %s_%s is one row of %dx%d frames" % [clip, side, E_SIZE, E_SIZE],
					texture.get_height() == E_SIZE and texture.get_width() % E_SIZE == 0,
					"%d x %d" % [texture.get_width(), texture.get_height()])
	var scene: EnemySpriteAppearance = (load("res://scenes/skins/cyberpunk_flyer.tscn") as PackedScene).instantiate()
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
		check("E uses the drone art", (visual as EnemySpriteAppearance).art_dir.ends_with("/flyer"),
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
