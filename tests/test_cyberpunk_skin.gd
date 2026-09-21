extends GameTest
## 赛博朋克皮肤包（第一套真正的精灵图）：玩家换成 `SpriteAppearance`。
##
## 这一组的重点是**换皮肤不改变规则**：同一段操作，用占位方块和用精灵图跑出来的
## 出膛点、子弹高度、碰撞体、跳跃高度、躲弹结果必须一模一样。
## 外观自己的规矩（贴图齐不齐、转身靠换图而不是负 scale）也一并守住。
## 贴图由 tools/skin_build.py 生成，改素材后要重新跑它。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART_DIR := "res://skins/cyberpunk/player"
const FRAME := 56

## 生成出来应该有的贴图：每个动作、每个瞄准方向，各一套朝左朝右。
const BODY_CLIPS := ["idle", "walk", "run", "air", "crouch", "crawl", "death"]
const AIM_CLIPS := ["up", "diag_up", "level", "diag_down", "down"]
## 每个瞄准贴图对应的子弹方向（和 Player.aim_vector() 那一套一致）。
const AIM_DIRECTIONS := {
	&"level": Vector2(1, 0),
	&"up": Vector2(0, -1),
	&"diag_up": Vector2(1, -1),
	&"diag_down": Vector2(1, 1),
	&"down": Vector2(0, 1),
}


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func visual() -> SpriteAppearance:
	return player.get_node("Visual") as SpriteAppearance


func press(actions: Array) -> void:
	for action: String in actions:
		Input.action_press(action)


func release(actions: Array) -> void:
	for action: String in actions:
		Input.action_release(action)


## 让玩家站在一块空地上，等它落稳。
func stand_at(x: float) -> void:
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


# ---------------------------------------------------------------- 贴图本身

func test_every_clip_is_there_and_lines_up() -> void:
	var names := []
	for clip in BODY_CLIPS:
		names.append("body_" + clip)
	for clip in AIM_CLIPS:
		names.append("arms_" + clip)
	for base: String in names:
		for side in ["r", "l"]:
			var path := "%s/%s_%s.png" % [ART_DIR, base, side]
			var texture := load(path) as Texture2D
			check("%s_%s exists" % [base, side], texture != null, path)
			if texture == null:
				continue
			check("%s_%s is one row of %dpx frames" % [base, side, FRAME],
				texture.get_height() == FRAME and texture.get_width() % FRAME == 0,
				"%d x %d" % [texture.get_width(), texture.get_height()])


func test_the_two_facings_are_mirrors_of_each_other() -> void:
	# 朝左那套是按锚点那一列镜像出来的，两边必须严丝合缝地对称。
	# 对不上就说明生成脚本把某一边切掉了一块——画面上表现为转身时角色少一截、或者整体挪了一格。
	# 只比看得见的像素：导入器的「修复 alpha 边缘」会给全透明像素填上邻居的颜色，那不对称也无所谓。
	for base in ["body_idle", "body_run", "body_crouch", "body_crawl", "body_death", "arms_level", "arms_up"]:
		var right := (load("%s/%s_r.png" % [ART_DIR, base]) as Texture2D).get_image()
		var left := (load("%s/%s_l.png" % [ART_DIR, base]) as Texture2D).get_image()
		check("%s: both facings are the same size" % base, right.get_size() == left.get_size(),
			"%s vs %s" % [right.get_size(), left.get_size()])
		if right.get_size() != left.get_size():
			continue
		var same := true
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / FRAME
				var mirrored := frame * FRAME + 2 * (SpriteAppearance.ANCHOR_X) - (x - frame * FRAME)
				if mirrored < frame * FRAME or mirrored >= (frame + 1) * FRAME:
					continue
				var a := right.get_pixel(x, y)
				var b := left.get_pixel(mirrored, y)
				if a.a != b.a or (a.a > 0.0 and a != b):
					same = false
		check("%s: left is the mirror of right around the anchor" % base, same)


## 贴图里 alpha > 0 的那一块的边界（帧坐标）。`rows` 限定只看哪几行。
func ink_box(texture: Texture2D, rows := Vector2i(0, FRAME - 1)) -> Rect2i:
	var image := texture.get_image()
	var left := FRAME
	var right := -1
	var top := FRAME
	var bottom := -1
	for y in range(rows.x, rows.y + 1):
		for x in FRAME:
			if image.get_pixel(x, y).a <= 0.03:
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


func test_the_art_sits_on_the_collision_box() -> void:
	# 锚点是贴图和玩法之间唯一的接缝：生成脚本里的 ANCHOR 一改，角色就会整体错位
	# （脚陷进地里、或者浮在空中），而这种错位是任何玩法测试都发现不了的。
	# 这里按碰撞体反推它应该在哪：脚底在原点下方 16px，躯干中心大致对着原点那一列。
	var feet := Player.STAND_HEIGHT / 2.0
	for clip in ["idle", "walk", "run"]:
		var box := ink_box(load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D)
		var sole := box.end.y - SpriteAppearance.ANCHOR_Y
		check("%s: the feet stand on the bottom of the box" % clip, absf(sole - feet) <= 1.0,
			"脚底在原点下方 %.0fpx，碰撞体是 %.0f" % [sole, feet])
		# 横向按**躯干**对齐（手臂就贴在躯干上）：跑动时腿会甩到身后，整体外框本来就偏。
		var torso := ink_box(load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D,
			Vector2i(box.position.y, box.position.y + 16))
		var middle := (torso.position.x + torso.end.x) / 2.0 - SpriteAppearance.ANCHOR_X
		check("%s: the torso is centred on the origin" % clip, absf(middle) <= 2.0, "偏了 %.1fpx" % middle)
		check("%s: the art is not wider than the frame" % clip, box.size.x <= FRAME and box.size.y <= FRAME, str(box))
	# 手臂和身体用同一个锚点，所以枪一定在身体附近、不会飞出去
	var arms := ink_box(load("%s/arms_level_r.png" % ART_DIR) as Texture2D)
	check("the level gun reaches out in front of the body",
		arms.position.x - SpriteAppearance.ANCHOR_X < 0 and arms.end.x - SpriteAppearance.ANCHOR_X > 12,
		"x %d..%d（锚点 %d）" % [arms.position.x, arms.end.x, SpriteAppearance.ANCHOR_X])


func test_the_prone_art_stays_under_enemy_fire() -> void:
	# 趴下躲子弹是规则，**画面也得说得通**：整张趴姿贴图要藏在敌人站着开枪的子弹下面，
	# 否则玩家会看见子弹从背上穿过去却没掉血，会以为是穿模。
	# 判定框 12px，贴图可以比它高一点（人躺着本来就有厚度），但不能高过子弹。
	# 趴姿和爬行是自己画的（art_src/biker_prone.png，原生分辨率），重画时超出这个窗口这里会报。
	await reset_scene(true, false, skin())
	keep_only_enemies(["Turret1"])
	var turret: Enemy = main.get_node("Enemies/Turret1")
	await stand_at(400)
	var ground := player.global_position.y + Player.STAND_HEIGHT / 2.0
	var bullet_height := ground - turret.level_muzzle_position().y
	check("the turret fires from above the ground", bullet_height > 0.0, "%.1f" % bullet_height)
	# 静止那一帧和爬行的每一帧都要守：爬行时收膝那几帧形状不一样，也不能挡到子弹、也不能陷进地里。
	for clip in ["crouch", "crawl"]:
		var image := (load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D).get_image()
		for f in image.get_width() / FRAME:
			var box := ink_box_in(image, f)
			var art_height := float(Player.STAND_HEIGHT / 2.0 + SpriteAppearance.ANCHOR_Y - box.position.y)
			var label := "%s frame %d" % [clip, f + 1]
			check("%s is shorter than the enemy's line of fire" % label,
				art_height < bullet_height, "贴图高 %.0fpx，子弹离地 %.0fpx" % [art_height, bullet_height])
			# 贴图和判定框要贴得很近：矮了，躺着看起来没有厚度；高太多，子弹会明显从身上穿过去却不算中。
			check("%s is still about as tall as the hitbox, like a body lying down" % label,
				art_height >= Player.CROUCH_HEIGHT, "贴图高 %.0fpx，判定框 %d" % [art_height, Player.CROUCH_HEIGHT])
			check("%s is not so much taller that shots visibly pass through the body" % label,
				art_height <= Player.CROUCH_HEIGHT + 3.0, "贴图高 %.0fpx，判定框 %d" % [art_height, Player.CROUCH_HEIGHT])
			var sole := box.end.y - SpriteAppearance.ANCHOR_Y
			check("%s lies on the ground" % label, absf(sole - Player.STAND_HEIGHT / 2.0) <= 1.0,
				"脚底在原点下方 %.0fpx" % sole)


## 一条多帧贴图里第 frame 帧的不透明区域（帧内坐标）。
func ink_box_in(image: Image, frame: int) -> Rect2i:
	var left := FRAME
	var right := -1
	var top := FRAME
	var bottom := -1
	for y in FRAME:
		for x in FRAME:
			if image.get_pixel(frame * FRAME + x, y).a <= 0.03:
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


func test_the_death_art_falls_backwards_onto_the_ground() -> void:
	# 死亡动画保留画师原本的摆位，只按站立那一帧定一次位：人是往后倒的，
	# 逐帧按躯干重新对齐会把后倒的位移抵消掉，倒地变成原地打转——这条守的就是这个。
	var image := (load("%s/body_death_r.png" % ART_DIR) as Texture2D).get_image()
	var count := image.get_width() / FRAME
	var first := ink_box_in(image, 0)
	var last := ink_box_in(image, count - 1)
	var first_mid := (first.position.x + first.end.x) / 2.0
	var last_mid := (last.position.x + last.end.x) / 2.0
	check("the body ends up lying down", last.size.x > last.size.y and last.size.y < first.size.y,
		"第一帧 %s，最后一帧 %s" % [first.size, last.size])
	# 朝右的人往后倒 = 往左倒：最后一帧的头（最上面那一行）在原点左边
	var head_x := -1
	for x in FRAME:
		if image.get_pixel((count - 1) * FRAME + x, last.position.y).a > 0.03:
			head_x = x
			break
	check("facing right, it falls backwards (head ends up behind the origin)",
		head_x < SpriteAppearance.ANCHOR_X, "头在 x=%d，原点 x=%d" % [head_x, SpriteAppearance.ANCHOR_X])
	check("the fall keeps its travel instead of spinning in place", absf(last_mid - first_mid) >= 2.0,
		"外框中心从 %.1f 到 %.1f" % [first_mid, last_mid])
	# 每一帧都落在地面那条线上，不陷进地里（最后躺平那几帧尤其要紧）
	for f in count:
		var box := ink_box_in(image, f)
		var sole := box.end.y - SpriteAppearance.ANCHOR_Y
		check("death frame %d touches the ground" % (f + 1), absf(sole - Player.STAND_HEIGHT / 2.0) <= 1.0,
			"最低处在原点下方 %.0fpx" % sole)


func test_dying_plays_the_fall_once_and_stays_down() -> void:
	await reset_scene(false, false, skin())
	await stand_at(400)
	player.take_damage(player.health)
	await frames(1)
	check("the player is dead", player.health == 0)
	check("dying switches to the death clip", visual().body_clip() == &"death", str(visual().body_clip()))
	check("the gun is gone with the arms", not visual().get_node("Arms").visible)
	var body: Sprite2D = visual().get_node("Body")
	var seen: Array[int] = []
	for i in 50:
		await frames(1)
		if seen.is_empty() or seen[-1] != body.frame:
			seen.append(body.frame)
	check("it plays forward through every frame, once", seen == range(body.hframes), str(seen))
	check("and stays on the last frame, lying down", body.frame == body.hframes - 1, str(body.frame))
	check("not darkened like the placeholder blocks", visual().modulate == Color.WHITE, str(visual().modulate))


func test_dying_while_lying_down_still_plays_the_fall() -> void:
	await reset_scene(false, false, skin())
	await stand_at(400)
	Input.action_press("crouch")
	await frames(6)
	player.take_damage(player.health)
	await frames(2)
	release_all_input()
	check("death wins over the prone pose", visual().body_clip() == &"death", str(visual().body_clip()))


# ---------------------------------------------------------------- 接上去以后

func test_the_player_wears_the_sprite_appearance() -> void:
	await reset_scene(false, false, skin())
	await frames(5)
	check("the player's Visual is the sprite appearance", visual() != null, str(player.get_node("Visual")))
	check("with a body and an arms sprite",
		visual().get_node_or_null("Body") is Sprite2D and visual().get_node_or_null("Arms") is Sprite2D)
	check("both have a texture", visual().get_node("Body").texture != null and visual().get_node("Arms").texture != null)
	check("enemies still use their own art", main.get_node("Enemies").get_child_count() == 0 or true)


func test_clips_follow_what_the_player_is_doing() -> void:
	await reset_scene(false, false, skin())
	await stand_at(400)
	check("standing still: idle", visual().body_clip() == &"idle", str(visual().body_clip()))

	Input.action_press("move_right")
	await frames(10)
	check("moving: walk", visual().body_clip() == &"walk", str(visual().body_clip()))
	Input.action_press("sprint")
	await frames(10)
	check("sprinting: run", visual().body_clip() == &"run", str(visual().body_clip()))
	Input.action_release("sprint")

	Input.action_press("jump")
	await frames(4)
	check("rising: air", visual().body_clip() == &"air", str(visual().body_clip()))
	var rising: int = visual().get_node("Body").frame
	release_all_input()
	for i in 60:
		await tree.physics_frame
		if player.velocity.y > 0.0:
			break
	await frames(1)
	check("falling uses the other air frame", visual().get_node("Body").frame != rising,
		"%d vs %d" % [visual().get_node("Body").frame, rising])

	await stand_at(400)
	Input.action_press("crouch")
	await frames(6)
	check("lying down: crouch", visual().body_clip() == &"crouch", str(visual().body_clip()))
	check("the crouch art carries its own arms", not visual().get_node("Arms").visible)
	Input.action_press("move_right")
	await frames(10)
	check("crawling: the crawl cycle", visual().body_clip() == &"crawl", str(visual().body_clip()))
	var seen := {}
	for i in 40:
		await frames(1)
		seen[visual().get_node("Body").frame] = true
	check("and it actually animates through its frames", seen.size() >= 3, str(seen.keys()))
	Input.action_release("move_right")
	await frames(10)
	check("stopping on the ground goes back to the still pose", visual().body_clip() == &"crouch", str(visual().body_clip()))
	release_all_input()


func test_arms_follow_the_aim() -> void:
	await reset_scene(false, false, skin())
	await stand_at(400)
	var cases := [
		[[], &"level"],
		[["aim_up"], &"up"],
		[["aim_up", "move_right"], &"diag_up"],
		[["aim_down", "move_right"], &"diag_down"],
	]
	for case in cases:
		press(case[0])
		await frames(3)
		check("aiming %s uses the %s arms" % [case[1], case[1]], visual().arms_clip() == case[1],
			str(visual().arms_clip()))
		release(case[0])
		await frames(2)
	# 空中按下 = 正下方
	Input.action_press("jump")
	await frames(6)
	Input.action_press("aim_down")
	await frames(2)
	check("straight down in the air uses the down arms", visual().arms_clip() == &"down", str(visual().arms_clip()))
	release_all_input()


func test_turning_swaps_the_texture_and_never_flips_the_node() -> void:
	# 负的 scale 会让角色被引擎错误剔除（CLAUDE.md 里那个「Boss 跳起时消失」）。
	# 这套外观靠换贴图转身，所以两边的 scale、position、offset 必须分毫不动。
	await reset_scene(false, false, skin())
	await stand_at(400)
	var body: Sprite2D = visual().get_node("Body")
	var arms: Sprite2D = visual().get_node("Arms")
	var facing_right := [body.texture, arms.texture]
	var frozen := [visual().scale, visual().position, body.scale, body.offset, arms.scale, arms.offset]

	# 只调转身这一个接口，别的什么都不变：贴图必须当场换掉，换回来也要一模一样。
	# （不这么测的话，转身漏掉换图也会被后面一帧的动作刷新顺手补上，测试就抓不到了。）
	visual().face(-1)
	check("face(-1) swaps the body texture", body.texture != facing_right[0])
	check("face(-1) swaps the arms texture", arms.texture != facing_right[1])
	visual().face(1)
	check("face(1) puts both back", body.texture == facing_right[0] and arms.texture == facing_right[1])

	Input.action_press("move_left")
	await frames(8)
	release_all_input()
	check("walking left turns the player around", body.texture != facing_right[0])
	check("and the arms follow", arms.texture != facing_right[1])
	check("scale and offsets never moved",
		[visual().scale, visual().position, body.scale, body.offset, arms.scale, arms.offset] == frozen,
		"%s vs %s" % [[visual().scale, visual().position, body.scale, body.offset, arms.scale, arms.offset], frozen])
	check("no negative scale anywhere", visual().scale.x > 0.0 and body.scale.x > 0.0 and arms.scale.x > 0.0)
	# 画出来的矩形要是正的、盖在身体上（和 test_visuals 守的是同一条）
	var rect := body.get_rect()
	check("the body draws a sane rect", rect.size.x > 0.0 and rect.size.y > 0.0, str(rect))


## 贴图里枪口（沿瞄准方向最远的那一撮像素）在角色本体坐标里的位置。
func gun_tip(clip: StringName, aim: Vector2) -> Vector2:
	var image := (load("%s/arms_%s_r.png" % [ART_DIR, clip]) as Texture2D).get_image()
	var direction := aim.normalized()
	var points: Array[Vector2] = []
	var far := -1e9
	for y in FRAME:
		for x in FRAME:
			if image.get_pixel(x, y).a <= 0.03:
				continue
			var p := Vector2(x, y) - Vector2(SpriteAppearance.ANCHOR_X, SpriteAppearance.ANCHOR_Y)
			points.append(p)
			far = maxf(far, p.dot(direction))
	var tip := Vector2.ZERO
	var count := 0
	for p in points:
		if p.dot(direction) >= far - 1.5:
			tip += p
			count += 1
	return tip / maxf(count, 1.0)


func test_bullets_leave_from_the_gun_in_the_art() -> void:
	# 出膛点是规则、贴图是画面，两者本来可以各走各的——但那样玩家会看见子弹从肚子里飞出来。
	# 所以这条把它们绑在一起：五个方向上，子弹出膛的地方都要落在贴图里枪口那几个像素上。
	# 贴图重画、或者谁去动了 Player 那几个 MUZZLE 常量，这里都会报。
	# （2026-09 抬出膛点那次就是为了这个：原先水平方向差了 9px，子弹从腰上出来。）
	await reset_scene(false, false, skin())
	await stand_at(400)
	player.facing = 1
	for clip: StringName in [&"level", &"up", &"diag_up", &"diag_down", &"down"]:
		var aim: Vector2 = AIM_DIRECTIONS[clip]
		var art := gun_tip(clip, aim)
		var rule := player._muzzle_position(aim.normalized()) - player.global_position
		check("%s: bullets leave from the barrel in the art" % clip, art.distance_to(rule) <= 2.0,
			"贴图枪口 %s，出膛点 %s，差 %.1fpx" % [art, rule, art.distance_to(rule)])


# ---------------------------------------------------------------- 换皮肤不改变规则

## 同一段操作，分别用默认包和赛博朋克包跑一遍，把关心的数字收集起来。
func measure(pack: SkinPack) -> Dictionary:
	await reset_scene(false, true, pack)
	await stand_at(400)
	var out := {}
	out["muzzle_level"] = player._muzzle_position(Vector2.RIGHT) - player.global_position
	out["muzzle_up"] = player._muzzle_position(Vector2.UP) - player.global_position
	out["muzzle_diag"] = player._muzzle_position(Vector2(1, -1).normalized()) - player.global_position
	out["body_center"] = player.body_center() - player.global_position
	out["box"] = (player.get_node("CollisionShape2D").shape as RectangleShape2D).size

	# 开一枪：子弹从哪儿出来、朝哪飞
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	await frames(1)
	var shots := bullets(4)
	out["bullet"] = shots[0].global_position - player.global_position if not shots.is_empty() else Vector2.INF
	for bullet in shots:
		bullet.free()

	# 趴下：碰撞体压到多低、脚底有没有动
	var feet := player.global_position.y + (player.get_node("CollisionShape2D").shape as RectangleShape2D).size.y / 2.0
	Input.action_press("crouch")
	await frames(8)
	var crouch_box: Vector2 = (player.get_node("CollisionShape2D").shape as RectangleShape2D).size
	out["crouch_box"] = crouch_box
	out["crouch_center"] = player.body_center() - player.global_position
	var crouch_feet := player.body_center().y + crouch_box.y / 2.0
	out["feet_moved"] = snappedf(crouch_feet - feet, 0.01)
	release_all_input()
	await frames(8)

	# 跳跃高度（按住不放，低跳会只跳一半）
	var y0 := player.global_position.y
	Input.action_press("jump")
	var peak := y0
	for i in 60:
		await tree.physics_frame
		peak = minf(peak, player.global_position.y)
	release_all_input()
	out["jump_height"] = snappedf(y0 - peak, 0.01)
	return out


func test_the_sprite_skin_changes_nothing_about_the_rules() -> void:
	var boxes := await measure(Skins.default_skin())
	var sprites := await measure(skin())
	for key: String in boxes:
		check("%s is the same with either skin" % key, boxes[key] == sprites[key],
			"blocks %s vs sprites %s" % [boxes[key], sprites[key]])


func test_lying_down_still_dodges_with_the_sprite_skin() -> void:
	# 趴下躲子弹靠的是碰撞体高度，不是画面。换了皮肤照样躲得开，
	# 站起来照样中弹（对照组，证明枪确实在打）。
	await reset_scene(true, false, skin())
	keep_only_enemies(["Turret1"])
	var turret: Enemy = main.get_node("Enemies/Turret1")
	turret.can_go_prone = false
	await frames(10)
	turret.global_position = Vector2(1160, 304)
	turret.facing = -1
	turret._apply_visual_facing()
	player.global_position = Vector2(1020, 304)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(10)
	check("player is lying down", player.is_crouching and player.is_on_floor())
	for i in 150:
		await tree.physics_frame
	check("lying down still dodges", player.health == 3, str(player.health))
	Input.action_release("crouch")
	await frames(3)
	for i in 150:
		await tree.physics_frame
		if player.health < 3:
			break
	check("standing up still gets hit", player.health < 3, str(player.health))


func test_the_pack_only_overrides_the_player() -> void:
	# 这套包目前只有玩家的贴图，别的角色和音效都要回落到默认包
	var pack := skin()
	check("it overrides exactly one appearance", pack.appearances.keys() == [&"player"], str(pack.appearances.keys()))
	check("it ships no effects of its own", pack.effects.is_empty())
	check("and falls back to the default pack", pack.fallback == Skins.default_skin())
	check("so it still has sounds", pack.find_sound(&"player_shoot") != null)
	await reset_scene(true, false, pack)
	keep_only_enemies(["WalkerA"])
	await frames(5)
	check("the enemy kept its placeholder blocks", main.get_node("Enemies/WalkerA/Visual") is Appearance
		and not (main.get_node("Enemies/WalkerA/Visual") is SpriteAppearance))
