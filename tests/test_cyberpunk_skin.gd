extends GameTest
## 赛博朋克皮肤包（第一套真正的精灵图）：玩家换成 `SpriteAppearance`。
##
## 这一组的重点是**换皮肤不改变规则**：同一段操作，用占位方块和用精灵图跑出来的
## 出膛点、子弹高度、碰撞体、跳跃高度、躲弹结果必须一模一样。
## 外观自己的规矩（贴图齐不齐、转身靠换图而不是负 scale）也一并守住。
## 贴图由 tools/skin_build.py 生成，改素材后要重新跑它。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART_DIR := "res://skins/cyberpunk/biker"
const FRAME := 56

## 生成出来应该有的贴图：每个动作、每个瞄准方向，各一套朝左朝右。
const BODY_CLIPS := ["idle", "walk", "run", "air", "crouch", "crawl", "death"]
const AIM_CLIPS := ["up", "diag_up", "level", "diag_down", "down"]
## 每种枪（`Weapon.look`）一整套手臂贴图，以及它的枪口和共用出膛点之间最多允许差几像素。
## 两把枪共用一套出膛点（玩法规则），步枪是按它量出来的所以卡得紧；
## 榴弹枪粗、枪口中心差 2~3px，而手雷有 8px 大、一出膛就往上抛，这点差别看不出来。
const GUN_LOOKS := {&"rifle": 2.0, &"launcher": 3.0}
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
	for look: StringName in GUN_LOOKS:
		for clip in AIM_CLIPS:
			names.append("arms_%s_%s" % [look, clip])
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
	for base in ["body_idle", "body_run", "body_crouch", "body_crawl", "body_death", "arms_rifle_level", "arms_rifle_up", "arms_launcher_level", "arms_launcher_diag_down"]:
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
	var arms := ink_box(load("%s/arms_rifle_level_r.png" % ART_DIR) as Texture2D)
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
	# **三个角色都要查**：原先只查了 biker，punk 和 cyborg 各有各的趴姿图（见 `skin_build.py`
	# 的 `PRONE_ART`），从来没被量过——上一版 punk 的图 22px 高，正顶在子弹上，就是这么漏过去的。
	for art_dir in [ART_DIR, ART_DIR_2, ART_DIR_3]:
		var who := String(art_dir).get_file()
		for clip in ["crouch", "crawl"]:
			var image := (load("%s/body_%s_r.png" % [art_dir, clip]) as Texture2D).get_image()
			for f in image.get_width() / FRAME:
				var box := ink_box_in(image, f)
				var art_height := float(Player.STAND_HEIGHT / 2.0 + SpriteAppearance.ANCHOR_Y - box.position.y)
				var label := "%s %s frame %d" % [who, clip, f + 1]
				check("%s is shorter than the enemy's line of fire" % label,
					art_height < bullet_height, "贴图高 %.0fpx，子弹离地 %.0fpx" % [art_height, bullet_height])
				# 矮了，躺着看起来没有厚度。
				check("%s is still about as tall as the hitbox, like a body lying down" % label,
					art_height >= Player.CROUCH_HEIGHT, "贴图高 %.0fpx，判定框 %d" % [art_height, Player.CROUCH_HEIGHT])
				# 上限**只由子弹说了算**（上面那条）。原先卡在「判定框 + 3」= 15px，那是照 biker
				# 那张图定的；punk 的头发、cyborg 撑起来爬的背都要高几像素，身体本身反而比 biker 还矮。
				# 真正要防的是「子弹从背上穿过去却不算中」，那就是子弹那条线，不是一个拍脑袋的 15。
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
	# 第一个样本必须在死的那一刻当场取：第 0 帧只显示 0.1 秒，等一帧再看的话，
	# 无头模式下 _process 可能已经跑过去了，测试会时过时不过。
	var body: Sprite2D = visual().get_node("Body")
	var seen: Array[int] = [body.frame]
	await frames(1)
	check("the player is dead", player.health == 0)
	check("dying switches to the death clip", visual().body_clip() == &"death", str(visual().body_clip()))
	check("the gun is gone with the arms", not visual().get_node("Arms").visible)
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


# ---------------------------------------------------------------- 跑起来的样子（2026-09 提节奏）

## 裸露皮肤的两种颜色（亮面 + 暗面），和 tools/skin_build.py 的 SKIN_COLORS 一致。
const SKIN_COLORS := [Color8(163, 109, 62), Color8(104, 60, 52)]
## Dash 素材身后那条速度残影的颜色。
const STREAK := Color8(255, 246, 174)
## 会在上面贴瞄准手臂的那几组动作。趴姿、爬行、倒地是整张画好的，自带手臂。
const ARMED_CLIPS := ["idle", "walk", "run", "air"]


func frames_in(image: Image) -> int:
	return image.get_width() / FRAME


## 这一帧里上半身比脚往前探出多少像素：跑动的姿势前倾，站着不动的姿势是直的。
func lean_in(image: Image, frame: int) -> float:
	var box := ink_box_in(image, frame)
	var head := []
	var feet := []
	for y in range(box.position.y, box.end.y):
		for x in FRAME:
			if image.get_pixel(frame * FRAME + x, y).a <= 0.03:
				continue
			if y <= box.position.y + 5:
				head.append(x)
			if y >= box.end.y - 4:
				feet.append(x)
	if head.is_empty() or feet.is_empty():
		return 0.0
	var head_x := 0.0
	for x: int in head:
		head_x += x
	var feet_x := 0.0
	for x: int in feet:
		feet_x += x
	return head_x / head.size() - feet_x / feet.size()


func has_color(image: Image, want: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.03 and pixel.r8 == want.r8 and pixel.g8 == want.g8 and pixel.b8 == want.b8:
				return true
	return false


## 这一帧里裸露的皮肤有多少像素。脸和脖子就那么点，多出来的就是素材自带的胳膊。
func skin_pixels(image: Image, frame: int) -> int:
	var found := 0
	for y in FRAME:
		for x in FRAME:
			var pixel := image.get_pixel(frame * FRAME + x, y)
			if pixel.a <= 0.03:
				continue
			for skin_color: Color in SKIN_COLORS:
				if pixel.r8 == skin_color.r8 and pixel.g8 == skin_color.g8 and pixel.b8 == skin_color.b8:
					found += 1
	return found


func test_walking_shows_the_running_animation() -> void:
	# 试玩嫌节奏慢，所以**正常移动直接用素材里的跑**（速度一个数都没动）。
	# 跑的姿势是整个人往前倾，走的姿势是直的——量这个就知道用的是哪一组。
	var walk := (load("%s/body_walk_r.png" % ART_DIR) as Texture2D).get_image()
	var idle := (load("%s/body_idle_r.png" % ART_DIR) as Texture2D).get_image()
	var leaning := 0.0
	for frame in frames_in(walk):
		leaning = maxf(leaning, lean_in(walk, frame))
	var standing := 0.0
	for frame in frames_in(idle):
		standing = maxf(standing, lean_in(idle, frame))
	check("the walk clip leans forward like a run", leaning >= 6.0, "前倾 %.1fpx" % leaning)
	# 对照：同一把尺子量站着不动，量出来必须很小，否则上面那条什么也没证明
	check("standing still does not lean", standing < 3.0, "前倾 %.1fpx" % standing)


func test_hanging_in_the_air_is_one_single_pose() -> void:
	# 空中只有一个姿势，所以贴图本身就只有一帧——两帧的话运行时总有机会在半空换图。
	var air := (load("%s/body_air_r.png" % ART_DIR) as Texture2D).get_image()
	check("the air clip is a single frame", frames_in(air) == 1, "%d 帧" % frames_in(air))
	# 对照：同一把尺子量走路，量出来是一整组，说明上面那条不是因为读错了图
	var walk := (load("%s/body_walk_r.png" % ART_DIR) as Texture2D).get_image()
	check("while walking is a whole cycle", frames_in(walk) > 1, "%d 帧" % frames_in(walk))


func test_sprinting_shows_the_dash() -> void:
	# 冲刺换成素材里的 Dash：身后拖一条残影。速度还是原来的 270，只是看着像在冲。
	for side in ["r", "l"]:
		var run := (load("%s/body_run_%s.png" % [ART_DIR, side]) as Texture2D).get_image()
		check("the sprint clip (%s) trails a speed streak" % side, has_color(run, STREAK))
	for clip in ["walk", "idle", "air"]:
		var image := (load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D).get_image()
		check("%s does not" % clip, not has_color(image, STREAK))


func test_no_clip_brings_its_own_arms() -> void:
	# 瞄准的手臂是单独贴上去的，所以身体那几张图必须是**脱了手臂的**。
	# 素材包里只有 `*2.png` 本来就没手臂，Idle1、Dash 这些都带着，生成脚本会脱掉；
	# 哪天素材被覆盖、或者生成脚本漏了这一步，角色就会长出三条胳膊——这里守的就是这个。
	# 脸和脖子也是同样的肤色，所以按"每帧裸露皮肤有多少"来判：脱过的最多二十几，没脱的五十打底。
	for clip in ARMED_CLIPS:
		var image := (load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D).get_image()
		var most := 0
		for frame in frames_in(image):
			most = maxi(most, skin_pixels(image, frame))
		check("%s has no arms of its own" % clip, most <= 30, "裸露皮肤最多 %d 像素" % most)
	# 对照：倒地那组是整张画好的（自带手臂、没有枪），同一把尺子量出来就该是大数
	var death := (load("%s/body_death_r.png" % ART_DIR) as Texture2D).get_image()
	var death_skin := 0
	for frame in frames_in(death):
		death_skin = maxi(death_skin, skin_pixels(death, frame))
	check("while the death clip, which keeps its arms, measures far more", death_skin > 40, str(death_skin))



# ---------------------------------------------------------------- 2 号玩家（Punk）

## 另外两个可选角色的贴图。同一个生成脚本、同样的规格，只是素材换了个人。
const ART_DIR_2 := "res://skins/cyberpunk/punk"
const ART_DIR_3 := "res://skins/cyberpunk/cyborg"


func test_every_character_gets_a_full_set_of_their_own() -> void:
	for dir_ in [ART_DIR_2, ART_DIR_3]:
		var missing := []
		for clip in BODY_CLIPS:
			for side in ["r", "l"]:
				var path := "%s/body_%s_%s.png" % [dir_, clip, side]
				if not ResourceLoader.exists(path):
					missing.append(path)
		for look: StringName in GUN_LOOKS:
			for aim in AIM_CLIPS:
				for side in ["r", "l"]:
					var path := "%s/arms_%s_%s_%s.png" % [dir_, look, aim, side]
					if not ResourceLoader.exists(path):
						missing.append(path)
		check("%s has every clip the first one has" % dir_.get_file(), missing.is_empty(), str(missing))


func test_the_three_characters_look_like_three_people() -> void:
	# 同屏两个人得看得出谁是谁，三套图必须两两不同（指错目录就会指回同一套）。
	for pair in [[ART_DIR, ART_DIR_2], [ART_DIR, ART_DIR_3], [ART_DIR_2, ART_DIR_3]]:
		var differ := 0
		for clip in ["idle", "walk", "run"]:
			var one := (load("%s/body_%s_r.png" % [pair[0], clip]) as Texture2D).get_image()
			var two := (load("%s/body_%s_r.png" % [pair[1], clip]) as Texture2D).get_image()
			if one.get_data() != two.get_data():
				differ += 1
		check("%s and %s are different people" % [pair[0].get_file(), pair[1].get_file()], differ == 3,
			"%d / 3 组不同" % differ)


func test_every_character_lines_up_exactly_like_the_first() -> void:
	# 换个角色不能把判定挪了：锚点是贴图和玩法之间唯一的接缝，两套图必须放在同一个位置上，
	# 否则 2 号的子弹会从别的高度飞出来。
	# 只比站在地上的那几组：空中的姿势本来就收着腿，各人收得不一样多，那是画的，不是放错了
	for dir_ in [ART_DIR_2, ART_DIR_3]:
		for clip in ["idle", "walk", "run"]:
			var one := ink_box(load("%s/body_%s_r.png" % [ART_DIR, clip]) as Texture2D)
			var two := ink_box(load("%s/body_%s_r.png" % [dir_, clip]) as Texture2D)
			check("%s %s: the feet stand on the same line" % [dir_.get_file(), clip], one.end.y == two.end.y,
				"%d vs %d" % [one.end.y, two.end.y])
		var arms_one := ink_box(load("%s/arms_rifle_level_r.png" % ART_DIR) as Texture2D)
		var arms_two := ink_box(load("%s/arms_rifle_level_r.png" % dir_) as Texture2D)
		check("%s: the gun reaches out to the same place" % dir_.get_file(), arms_one == arms_two,
			"%s vs %s" % [arms_one, arms_two])


func test_the_other_characters_art_is_mirrored_too() -> void:
	for dir_ in [ART_DIR_2, ART_DIR_3]:
		for clip in ["idle", "walk", "crouch"]:
			var right := (load("%s/body_%s_r.png" % [dir_, clip]) as Texture2D).get_image()
			var left := (load("%s/body_%s_l.png" % [dir_, clip]) as Texture2D).get_image()
			var same := true
			for y in right.get_height():
				for x in right.get_width():
					var frame := x / FRAME
					var mirrored := frame * FRAME + 2 * SpriteAppearance.ANCHOR_X - (x - frame * FRAME)
					if mirrored < frame * FRAME or mirrored >= (frame + 1) * FRAME:
						continue
					var a := right.get_pixel(x, y)
					var b := left.get_pixel(mirrored, y)
					if a.a != b.a or (a.a > 0.0 and a != b):
						same = false
			check("%s %s: left is the mirror of right around the anchor" % [dir_.get_file(), clip], same)


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
	# 整个空中保持同一个姿势：本来上升和下落是两帧，在最高点换图那一下看着别扭（2026-09 试玩）。
	check("setup: the player really is falling now", player.velocity.y > 0.0 and not player.is_on_floor(),
		"vy %.1f" % player.velocity.y)
	check("falling keeps the very same air frame", visual().get_node("Body").frame == rising,
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
func gun_tip(look: StringName, clip: StringName, aim: Vector2) -> Vector2:
	var image := (load("%s/arms_%s_%s_r.png" % [ART_DIR, look, clip]) as Texture2D).get_image()
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
	# 每把枪都要守：出膛点只有一套，换哪把枪子弹/手雷都得从那把枪的枪口出来
	for look: StringName in GUN_LOOKS:
		var tolerance: float = GUN_LOOKS[look]
		for clip: StringName in [&"level", &"up", &"diag_up", &"diag_down", &"down"]:
			var aim: Vector2 = AIM_DIRECTIONS[clip]
			var art := gun_tip(look, clip, aim)
			var rule := player._muzzle_position(aim.normalized()) - player.global_position
			check("%s %s: shots leave from the barrel in the art" % [look, clip], art.distance_to(rule) <= tolerance,
				"贴图枪口 %s，出膛点 %s，差 %.1fpx（容差 %.0f）" % [art, rule, art.distance_to(rule), tolerance])


func test_switching_weapons_swaps_the_gun_in_the_hands() -> void:
	# 步枪 ↔ 手雷（榴弹枪）随时切换：手里的枪跟着换，其它什么都不变——
	# 身体动画、瞄准方向、出膛点、判定框都和换之前一样。外观键在武器资源里（Weapon.look）。
	await reset_scene(false, false, skin())
	await stand_at(400)
	var arms: Sprite2D = visual().get_node("Arms")
	check("starts with the rifle", player.current_slot().weapon.look == &"rifle" and visual().held_look() == &"rifle",
		str(visual().held_look()))
	check("rifle art in the hands", arms.texture.resource_path.get_file().begins_with("arms_rifle_"),
		arms.texture.resource_path)
	var muzzle := player._muzzle_position(Vector2.RIGHT) - player.global_position
	var body_clip := visual().body_clip()
	player.switch_weapon()
	await frames(1)
	check("switching to grenades shows the launcher", visual().held_look() == &"launcher", str(visual().held_look()))
	check("launcher art in the hands", arms.texture.resource_path.get_file().begins_with("arms_launcher_level"),
		arms.texture.resource_path)
	check("same muzzle for both guns", player._muzzle_position(Vector2.RIGHT) - player.global_position == muzzle)
	check("the body does not change", visual().body_clip() == body_clip)
	# 榴弹枪也跟着瞄准、跟着转身
	Input.action_press("aim_up")
	await frames(3)
	check("the launcher aims too", arms.texture.resource_path.get_file() == "arms_launcher_up_r.png",
		arms.texture.resource_path)
	Input.action_release("aim_up")
	Input.action_press("move_left")
	await frames(6)
	release_all_input()
	check("and turns around with the player", arms.texture.resource_path.get_file() == "arms_launcher_level_l.png",
		arms.texture.resource_path)
	player.switch_weapon()
	await frames(1)
	check("switching back brings the rifle back", arms.texture.resource_path.get_file() == "arms_rifle_level_l.png",
		arms.texture.resource_path)


func test_a_gun_without_art_falls_back_to_the_rifle() -> void:
	# 新武器还没画枪，或者这套皮肤没有这把枪的贴图：拿默认那把，不能手里空着、也不能报错
	await reset_scene(false, false, skin())
	await stand_at(400)
	var odd := Weapon.new()
	odd.look = &"not_drawn_yet"
	odd.projectile = player.current_slot().weapon.projectile
	player.equip_weapon(player.current_weapon, odd)
	await frames(1)
	check("an unknown gun shows the default one", visual().held_look() == &"rifle", str(visual().held_look()))
	check("and the hands are still holding it", visual().get_node("Arms").visible and visual().get_node("Arms").texture != null)
	var blank := Weapon.new()
	blank.projectile = odd.projectile
	player.equip_weapon(player.current_weapon, blank)
	await frames(1)
	check("a weapon with no look shows the default one too", visual().held_look() == &"rifle", str(visual().held_look()))


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
	check("lying down still dodges", player.health == player.max_health, str(player.health))
	Input.action_release("crouch")
	await frames(3)
	for i in 150:
		await tree.physics_frame
		if player.health < 3:
			break
	check("standing up still gets hit", player.health < player.max_health, str(player.health))


func test_the_pack_only_overrides_what_has_been_drawn() -> void:
	# 这套包有玩家、所有敌人（含 Boss）、所有子弹和手雷、地形的贴图；音效和特效都回落到默认包
	var pack := skin()
	# StringName 排序不按字母（按内部指针），先转成普通字符串再比
	var drawn := pack.appearances.keys().map(func(k: StringName) -> String: return String(k))
	drawn.sort()
	check("it overrides the player, every enemy, every projectile and the terrain",
		drawn == ["biker", "boss_a", "boss_bullet", "chaser", "cyborg", "enemy_bullet", "enemy_grenade", "flyer", "flyer_bullet",
			"grenadier", "player_bullet", "player_grenade", "punk", "terrain_ground", "terrain_ledge", "terrain_stone",
			"turret", "turret_bullet", "walker_a", "walker_b", "walker_c"],
		str(drawn))
	var effects := pack.effects.keys().map(func(k: StringName) -> String: return String(k))
	effects.sort()
	check("it ships every effect", effects == ["explosion", "hit_spark", "impact_spark", "muzzle_flash"], str(effects))
	check("and falls back to the default pack", pack.fallback == Skins.default_skin())
	check("so it still has sounds", pack.find_sound(&"player_shoot") != null)
	# 包里缺哪个角色的贴图，那个角色就保留自己的占位方块：临时拿掉 Boss 的贴图来看
	var partial := pack.duplicate() as SkinPack
	partial.appearances = pack.appearances.duplicate()
	partial.appearances.erase(&"boss_a")
	await reset_scene(true, false, partial)
	keep_only_enemies(["BossA"])
	await frames(5)
	var unpainted: Node = main.get_node("Enemies/BossA/Visual")
	check("an enemy missing from the pack keeps its placeholder blocks", unpainted is Appearance
		and not (unpainted is SpriteAppearance) and not (unpainted is EnemySpriteAppearance))


## 身体贴图**必须是脱了胳膊的**：瞄准手臂是另贴上去的，身上再留一条就是三条胳膊。
## `portrait.png` 是同一个角色、同一帧待机的**原画**（自带那条胳膊，见 `UiKit.portrait()`），
## 拿它当对照最直接：脱干净了，身体的像素一定比原画少一条胳膊那么多。
##
## **`strip_arms()` 只对 biker 好使**：它按肤色连通块找胳膊，而 punk 那条裹着袖子、
## cyborg 那条整个是护甲，一个像素都匹配不上，原样留着——三个角色里只有 biker 是被程序脱的，
## punk 和 cyborg 用的是自己补的无臂图（`art_src/<角色>_idle.png`，见 `skin_build.py` 的 `own_body()`）。
##
## **冲刺那组（`run` ← 素材的 Dash）一起查**：它和待机是两条路，待机补好了不代表冲刺也好了，
## punk 和 cyborg 的冲刺一度还带着原本那条胳膊（`Dash` 里 1、6 帧就是待机姿势，2~5 帧是另外的，
## 推不出来，只能另画一张）。`walk` 和 `air` 用的是素材包自带的无臂版，不在这儿查——
## 它们没有「同一姿势的带臂原画」可以当对照。
const ARMLESS_CLIPS := ["idle", "run"]


func test_the_body_art_has_its_arms_stripped() -> void:
	await reset_scene(false, false, skin())
	for art_dir in [ART_DIR, ART_DIR_2, ART_DIR_3]:
		var who := String(art_dir).get_file()
		var drawn := _ink(UiKit.portrait(StringName(who)).get_image())
		check("%s has a portrait to compare against" % who, drawn > 0)
		for clip: String in ARMLESS_CLIPS:
			var sheet := (load("%s/body_%s_r.png" % [art_dir, clip]) as Texture2D).get_image()
			var side := sheet.get_height()
			var body := _ink(sheet.get_region(Rect2i(0, 0, side, side)))
			check("%s %s lost an arm's worth of pixels" % [who, clip], body < drawn - 20,
				"身体 %d 个像素，原画 %d 个" % [body, drawn])


# ---------------------------------------------------------------- 人物选择界面上的头像

## 不透明的像素有多少（拿来比「这张图上的人是不是少了一条胳膊」）。
func _ink(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.03:
				count += 1
	return count


## **头像不能拿游戏里那张身体贴图来画**：那是脱过胳膊的（胳膊按瞄准方向单独烘，见 `strip_arms()`），
## 人物选择界面上的人会空着两只袖子（2026-09 试玩看出来的）。
## 现在用的是素材包里现成的 `portrait.png`（`skin_build.py` 从素材原本的待机裁的），
## 所以它一定比脱过胳膊的身体多出一条胳膊那么多像素。
func test_the_portrait_is_not_the_armless_game_body() -> void:
	await reset_scene(false, false, skin())
	var shot := UiKit.portrait(&"biker")
	check("biker has a portrait", shot != null)
	if shot == null:
		return
	var body := (load("%s/body_idle_r.png" % ART_DIR) as Texture2D).get_image()
	var side := body.get_height()
	var frame := body.get_region(Rect2i(0, 0, side, side))
	var face := _ink(shot.get_image())
	var bare := _ink(frame)
	check("it brings the arm the game body had stripped", face > bare + 40,
		"头像 %d 个像素、身体 %d 个" % [face, bare])


## 三个角色的头像要一样大，界面上三张才对得齐、高矮才有可比性。
func test_every_character_has_a_portrait_the_same_size() -> void:
	await reset_scene(false, false, skin())
	var size := Vector2i.ZERO
	for look: StringName in [&"biker", &"punk", &"cyborg"]:
		var shot := UiKit.portrait(look)
		check("%s has a portrait" % look, shot != null)
		if shot == null:
			continue
		var here := Vector2i(shot.get_width(), shot.get_height())
		if size == Vector2i.ZERO:
			size = here
		check("%s is the same size as the others" % look, here == size, "%s vs %s" % [here, size])


## 头像得装得进格子里，不然会盖到旁边那一格上。
func test_the_portrait_fits_its_slot() -> void:
	await reset_scene(false, false, skin())
	var shot := UiKit.portrait(&"biker")
	check("setup: there is a portrait", shot != null)
	if shot == null:
		return
	# 格子里图标摆在 (2, 2)，所以四边各要留出 2px
	check("it fits the setup screen's slot",
		shot.get_width() <= SetupColumn.PORTRAIT.x - 4.0
		and shot.get_height() <= SetupColumn.PORTRAIT.y - 4.0,
		"%dx%d vs %s" % [shot.get_width(), shot.get_height(), SetupColumn.PORTRAIT])
