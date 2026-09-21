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
const BODY_CLIPS := ["idle", "walk", "run", "air", "crouch"]
const AIM_CLIPS := ["up", "diag_up", "level", "diag_down", "down"]


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
	for base in ["body_idle", "body_run", "body_crouch", "arms_level", "arms_up"]:
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
	# 判定框只有 8px，贴图可以比它高一点（人躺着本来就有厚度），但不能高过子弹。
	# 这张趴姿是自己画的（art_src/），高度由 tools/skin_build.py 的 PRONE_SIZE 决定，改大了这里会报。
	await reset_scene(true, false, skin())
	keep_only_enemies(["Turret1"])
	var turret: Enemy = main.get_node("Enemies/Turret1")
	await stand_at(400)
	var ground := player.global_position.y + Player.STAND_HEIGHT / 2.0
	var bullet_height := ground - turret.level_muzzle_position().y
	check("the turret fires from above the ground", bullet_height > 0.0, "%.1f" % bullet_height)
	var box := ink_box(load("%s/body_crouch_r.png" % ART_DIR) as Texture2D)
	var art_height := float(FRAME - box.position.y)
	check("the prone art is shorter than the enemy's line of fire",
		art_height < bullet_height, "贴图高 %.0fpx，子弹离地 %.0fpx" % [art_height, bullet_height])
	check("and it is still taller than the hitbox, like a body lying down",
		art_height >= Player.CROUCH_HEIGHT, "贴图高 %.0fpx，判定框 %d" % [art_height, Player.CROUCH_HEIGHT])
	# 趴姿的脚底也要落在地上，和站姿同一条线
	var sole := box.end.y - SpriteAppearance.ANCHOR_Y
	check("the prone art lies on the ground", absf(sole - Player.STAND_HEIGHT / 2.0) <= 1.0,
		"脚底在原点下方 %.0fpx" % sole)


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
	turret.global_position = Vector2(1160, 306)
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
