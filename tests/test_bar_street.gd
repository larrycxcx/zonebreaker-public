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
	if needs_art(): return
	var mine := pack()
	var keys: Array[String] = []
	for key: StringName in mine.appearances:
		keys.append(String(key))
	keys.sort()
	check("it declares the three terrains, this stage's enemies and its boss",
		keys == ["3_a", "3_b", "3_boss", "3_c", "3_d", "3_e", "3_f",
			"terrain_ground", "terrain_ledge", "terrain_stone"], str(keys))
	check("and a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("bar_street"), str(mine.backdrop))
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
	# **循环的曲子必须是 OGG**：MP3 编码器会在开头结尾各补一小段静音，转一圈能听出来接缝
	check("and it is an ogg", track is AudioStreamOggVorbis, track.get_class())


func test_each_zone_plays_its_own_track() -> void:
	if needs_art(): return
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
	if needs_art(): return
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
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
	if needs_art(): return
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
	if needs_art(): return
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
	if needs_art(): return
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


# ---------------------------------------------------------------- 这一关的敌人

## 皮肤键 → [帧宽, 帧高, 锚点 x, 锚点 y]。**3-E 的锚点往下挪了**：
## 它趴在地上只有 11px 高，判定框 28×12，锚点不挪的话贴图会陷进地里。
const ENEMIES := {
	&"3_a": [80, 56, 40, 40],   # 刀客：蓄一下急冲去刺
	&"3_b": [80, 56, 40, 40],   # 枪手：巡逻 + 射击 + 真斜射
	&"3_c": [80, 56, 40, 40],   # 剑客：跳向玩家、落地横扫
	&"3_d": [80, 56, 40, 40],   # 壮汉：正面扛伤害，不冲锋
	&"3_e": [80, 56, 40, 49],   # 鲨鱼机：固定在地面，贴着地面开枪
	&"3_f": [80, 56, 40, 40],   # 炮车：慢速移动的炮台
}
const STAND_Y := 304.0


func sheet(key: StringName, clip: String, side := "r") -> Image:
	return (load("%s/enemies/%s/%s_%s.png" % [ART, key, clip, side]) as Texture2D).get_image()


func has_clip(key: StringName, clip: String) -> bool:
	return ResourceLoader.exists("%s/enemies/%s/%s_r.png" % [ART, key, clip])


func spawn(scene_path: String, at: Vector2) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


func test_every_enemy_the_pack_names_really_has_art() -> void:
	if needs_art(): return
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
	if needs_art(): return
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var right := sheet(key, "idle")
		var left := sheet(key, "idle", "l")
		var wrong := 0
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / int(spec[0])
				var within := x % int(spec[0])
				var sx := frame * int(spec[0]) + 2 * int(spec[2]) - within
				if sx < 0 or sx >= right.get_width() or sx / int(spec[0]) != frame:
					continue
				if right.get_pixel(x, y) != left.get_pixel(sx, y):
					wrong += 1
		check("%s mirrors about its anchor" % key, wrong == 0, "%d 个像素对不上" % wrong)


func test_everyone_stands_on_the_same_line() -> void:
	if needs_art(): return
	# 脚底落在锚点下方 16px（生成脚本的约定）。**3-E 的锚点另算**：
	# 它的贴图照样是脚底在帧底边，只是外观场景把锚点往下挪了，好对上矮判定框。
	for key: StringName in ENEMIES:
		var spec: Array = ENEMIES[key]
		var img := sheet(key, "idle")
		var lowest := -1
		for y in img.get_height():
			for x in int(spec[0]):
				if img.get_pixel(x, y).a > 0.0:
					lowest = y
					break
		check("%s has its feet on the generator's ground line" % key, lowest == 40 + 16 - 1,
			"最低一行 y=%d" % lowest)


func test_the_gunman_brings_real_diagonal_art() -> void:
	if needs_art(): return
	# **第二关 2-C 缺的就是这个**：那套素材只画了水平开火，斜着打时画面是水平端枪的。
	# 这一关的枪手自带三个角度，所以规则和画面终于对得上。
	check("it has a level firing pose", has_clip(&"3_b", "attack_level"))
	check("and one for aiming up", has_clip(&"3_b", "attack_up"))
	check("and one for aiming down", has_clip(&"3_b", "attack_down"))
	# 三组得真的不一样（照搬同一张的话等于没画）
	var level := sheet(&"3_b", "attack_level").get_data()
	check("the three are really different poses",
		sheet(&"3_b", "attack_up").get_data() != level
		and sheet(&"3_b", "attack_down").get_data() != level)


func test_the_ones_that_fight_have_the_frames_their_behaviour_needs() -> void:
	if needs_art(): return
	check("3-A has a charging pose for its lunge", has_clip(&"3_a", "run"))
	check("3-C has an airborne pose for its leap", has_clip(&"3_c", "air"))
	check("3-E has a firing pose", has_clip(&"3_e", "attack_level"))
	check("but no walk — it is bolted to the ground", not has_clip(&"3_e", "walk"))
	check("3-F has a firing pose", has_clip(&"3_f", "attack_level"))


# ---------------------------------------------------------------- 接上去的三种

func test_the_gunman_patrols_and_shoots_off_the_level() -> void:
	await reset_scene(false, true, pack())
	var gun := spawn("res://scenes/enemy_3_b.tscn", Vector2(500, STAND_Y))
	gun.facing = -1
	player.global_position = Vector2(380, STAND_Y)
	snap_camera()
	await frames(4)
	check("it can aim off the level", gun.can_aim_diagonally)
	var stood := player.global_position
	player.global_position = stood + Vector2(0, -104)
	check("a player up on a ledge is a diagonal target",
		gun.aim_for(player) == Enemy.Aim.DIAGONAL_UP, str(gun.aim_for(player)))
	player.global_position = stood
	var fired: Array[int] = []
	gun.shot_fired.connect(func() -> void: fired.append(1))
	await frames(180)
	check("and it really fires", not fired.is_empty(), str(fired.size()))


func test_the_cannon_lobs_grenades_instead_of_shooting() -> void:
	# 2026-10 试玩后改的：原来是开枪连发的炮台，现在**从炮管里打手雷**——
	# 整套就是第一关 F 那个「只扔手雷」的行为（`EnemyGrenadier`），只是慢慢挪、出手点在炮管口。
	await reset_scene(false, true, pack())
	var cannon := spawn("res://scenes/enemy_3_f.tscn", Vector2(500, STAND_Y)) as EnemyGrenadier
	check("it is a grenadier", cannon != null)
	if cannon == null:
		return
	check("it moves, but slowly", cannon.move_speed > 0.0 and cannon.move_speed < 60.0,
		str(cannon.move_speed))
	check("it carries no gun", cannon.bullet_scene == null)
	check("it loads enemy grenades (they only hurt players)", cannon.grenade_scene != null
		and cannon.grenade_scene.resource_path == "res://scenes/enemy_grenade.tscn",
		str(cannon.grenade_scene))
	# 炮管口是按贴图量的（原来开枪时的出膛点就是这个），F 的那个是挥棒弧光的位置
	check("they leave from the barrel, not from F's bat swing",
		cannon.throw_offset == Vector2(18, -9), str(cannon.throw_offset))
	cannon.facing = 1
	player.global_position = Vector2(700, STAND_Y)
	snap_camera()
	var thrown: Array[Node2D] = []
	var shots: Array[int] = []
	cannon.shot_fired.connect(func() -> void: shots.append(1))
	# `launch_projectile()` 是加进树**之后**才摆位置的，所以只记下节点，过一帧再看它在哪
	var watch := func(node: Node) -> void:
		if node is Grenade:
			thrown.append(node as Node2D)
	tree.node_added.connect(watch)
	var first_seen := Vector2.INF
	for i in 150:
		await tree.physics_frame
		if first_seen == Vector2.INF and not thrown.is_empty() and is_instance_valid(thrown[0]):
			first_seen = thrown[0].global_position
	tree.node_added.disconnect(watch)
	check("it really lobs them at a player in front", thrown.size() >= 1, str(thrown.size()))
	check("and never fires a bullet", shots.is_empty(), str(shots.size()))
	check("the grenade comes out ahead of the barrel, towards the player",
		first_seen != Vector2.INF and first_seen.x > cannon.global_position.x + 10.0,
		"%s vs cannon at %s" % [first_seen, cannon.global_position])


func test_the_shark_is_bolted_down_and_fires_along_the_floor() -> void:
	# **这一关的新规矩**：现有的敌人站着开枪，子弹离地 21~25，趴下能躲过。
	# 这个贴着地面打，**趴下躲不掉，只能跳过去**——正好反过来。
	await reset_scene(false, true, pack())
	var shark := spawn("res://scenes/enemy_3_e.tscn", Vector2(500, STAND_Y)) as Enemy
	await frames(4)
	var box := shark.get_node("CollisionShape2D") as CollisionShape2D
	var size := (box.shape as RectangleShape2D).size
	check("it is a low thing", size.y <= 16.0, str(size))
	check("it never walks", not (shark is EnemyWalker))
	var floor_y: float = shark.global_position.y + size.y / 2.0
	var muzzle: float = shark.level_muzzle_position().y
	check("and its gun hugs the floor", floor_y - muzzle < Player.CROUCH_HEIGHT,
		"离地 %.0f，趴下高 %.0f" % [floor_y - muzzle, Player.CROUCH_HEIGHT])


func test_crouching_does_not_dodge_the_shark() -> void:
	await reset_scene(false, true, pack())
	var shark := spawn("res://scenes/enemy_3_e.tscn", Vector2(560, STAND_Y))
	shark.contact_damage = 0
	player.global_position = Vector2(360, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	Input.action_press("crouch")
	await frames(10)
	check("setup: the player really is prone", player.is_crouching)
	var before: int = player.health
	for i in 240:
		await tree.physics_frame
		if player.health < before:
			break
	release_all_input()
	check("ducking under it does not work", player.health < before,
		"%d -> %d" % [before, player.health])


# ---------------------------------------------------------------- 三种新打法

func test_the_knifeman_winds_up_before_it_lunges() -> void:
	# **蓄力那一下就是留给玩家的**：冲起来比玩家走路（180）快得多，跑是跑不掉的，
	# 只能在它定住的那零点几秒里跳开。没有这段预兆就成了没法躲。
	await reset_scene(false, true, pack())
	var knife := spawn("res://scenes/enemy_3_a.tscn", Vector2(500, STAND_Y)) as EnemyLunger
	knife.facing = -1
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	check("it is faster than the player can walk", knife.lunge_speed > player.move_speed,
		"%.0f / %.0f" % [knife.lunge_speed, player.move_speed])
	var winding := false
	var dashing := false
	for i in 120:
		await tree.physics_frame
		if knife.is_winding_up():
			winding = true
			check("it holds still while winding up", absf(knife.velocity.x) < 1.0,
				"%.1f" % knife.velocity.x)
		if knife.is_dashing():
			dashing = true
			break
	check("it winds up first", winding)
	check("then it goes", dashing)


func test_the_lunge_commits_to_one_direction() -> void:
	# 起手之后它认准那个方向冲出去，不跟着人转——跟着转的话「跳开就躲掉了」就没意义了
	await reset_scene(false, true, pack())
	var knife := spawn("res://scenes/enemy_3_a.tscn", Vector2(500, STAND_Y)) as EnemyLunger
	knife.facing = -1
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 120:
		await tree.physics_frame
		if knife.is_winding_up():
			break
	check("setup: winding up, facing the player", knife.is_winding_up() and knife.facing == -1)
	player.global_position = Vector2(700, STAND_Y)      # 绕到背后
	await frames(10)
	check("it still goes the way it committed to", knife.facing == -1, str(knife.facing))


func test_the_swordsman_leaps_over_things() -> void:
	# 它是这一关唯一会主动越过地形的——矮墙挡不住它，躲在掩体后面慢慢打对它不管用
	await reset_scene(false, true, pack())
	var sword := spawn("res://scenes/enemy_3_c.tscn", Vector2(500, STAND_Y)) as EnemyLeaper
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(4)
	for i in 200:
		await tree.physics_frame
		if sword.is_leaping():
			break
	check("it leaps", sword.is_leaping())
	# **高度要在起跳之后量**：上面那个循环是在变成「空中」那一帧就跳出来的，那会儿还没升起来
	var highest: float = sword.global_position.y
	for i in 60:
		await tree.physics_frame
		highest = minf(highest, sword.global_position.y)
	check("and really gets off the ground", STAND_Y - highest > 20.0,
		"%.0f" % (STAND_Y - highest))


func test_stepping_aside_dodges_the_landing_slash() -> void:
	# 落点在起跳那一刻就定了，人往旁边走一步那一刀就落空
	await reset_scene(false, true, pack())
	var sword := spawn("res://scenes/enemy_3_c.tscn", Vector2(500, STAND_Y)) as EnemyLeaper
	sword.contact_damage = 0
	player.global_position = Vector2(420, STAND_Y)
	player.health = 9999
	snap_camera()
	for i in 200:
		await tree.physics_frame
		if sword.is_leaping():
			break
	check("setup: it is in the air", sword.is_leaping())
	var before: int = player.health
	# **跑到另一边，而且要留在它够得着的范围里**：跑太远的话它就算会掉头也不会掉，
	# 这条用例就什么都没测到（第一版放到 820，超出 `leap_range` 了）。
	var behind: float = sword.global_position.x + 90.0
	for i in 120:
		await tree.physics_frame
		player.global_position = Vector2(behind, STAND_Y)
		player.health = 9999 if player.health > before else player.health
		if not sword.is_leaping():
			break
	check("it does not turn round in mid air", sword.facing == -1, str(sword.facing))
	check("the slash lands on nothing", player.health == before,
		"%d -> %d" % [before, player.health])


func test_the_brute_shrugs_off_shots_from_the_front() -> void:
	# 胸甲和护肩都在身前：**从正面打伤害减半，从背后是全额**。
	# 逼你绕后、跳过去、或者把手雷扔过它头顶（抛物线会落在它身后）。
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	await frames(2)
	check("it really has armour", brute.front_armour < 1.0, str(brute.front_armour))
	# **朝向要在挨打那一刻定**：它会转过去朝着玩家走，`await` 一帧朝向就变了，
	# 「正面」那一下会变成背后——第一版就是这么量反的。
	player.global_position = Vector2(-4000, STAND_Y)
	brute.facing = 1
	var full: int = brute.health
	brute.take_damage(40, Vector2(600, STAND_Y), player)        # 它面朝右，这是正面
	var from_front: int = full - brute.health
	brute.health = full
	brute.take_damage(40, Vector2(400, STAND_Y), player)        # 背后
	var from_behind: int = full - brute.health
	check("a shot from the front is blunted", from_front < from_behind,
		"正面 %d，背后 %d" % [from_front, from_behind])
	check("and from behind it lands in full", from_behind == 40, str(from_behind))
	check("the front hit matches the armour",
		from_front == maxi(1, roundi(40 * brute.front_armour)), str(from_front))


func test_the_brute_does_not_charge() -> void:
	# 说好的「不冲锋」：它就是一堵慢慢压过来的墙，走位全在玩家手上
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	check("it never moves faster than it walks", brute.charge_speed <= brute.move_speed,
		"%.0f / %.0f" % [brute.charge_speed, brute.move_speed])
	check("but it is slower than the player", brute.move_speed < player.move_speed,
		"%.0f / %.0f" % [brute.move_speed, player.move_speed])
	brute.facing = 1
	player.global_position = Vector2(300, STAND_Y)
	player.health = 9999
	snap_camera()
	await frames(6)
	check("and it still turns to come at you", brute.facing == -1, str(brute.facing))


func test_armour_does_not_apply_to_damage_with_no_direction() -> void:
	# 来源不明的（持续伤害、掉出关卡）不减——护甲挡的是打过来的东西，不是所有伤害
	await reset_scene(false, true, pack())
	var brute := spawn("res://scenes/enemy_3_d.tscn", Vector2(500, STAND_Y)) as EnemyBrute
	await frames(2)
	player.global_position = Vector2(-4000, STAND_Y)
	brute.facing = 1
	var full: int = brute.health
	brute.take_damage(40)
	check("an undirected hit lands in full", full - brute.health == 40, str(full - brute.health))


# ---------------------------------------------------------------- 这一关的 Boss

func spawn_boss() -> BossWheel:
	var boss := (load("res://scenes/boss_3.tscn") as PackedScene).instantiate() as BossWheel
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(900, STAND_Y - 12.0)
	boss._home = boss.global_position
	return boss


## 摆好 Boss 和玩家。**墙要去掉**（第二个参数 false）：测试关 x=800 那道墙正好在它和玩家之间，
## 而它是**站在地上**的——视线从身体中心发出，会被墙挡住，`find_target()` 一直是 null，
## 它就什么也不做。前两个 Boss 要么飞要么高，射线从墙顶过去了，所以没撞上这个。
func face_the_mech(player_at: Vector2) -> BossWheel:
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	player.global_position = player_at
	player.health = 99999
	snap_camera()
	await frames(4)
	boss.appear()
	await frames(2)
	return boss


func test_the_mech_is_a_boss_and_stands_on_the_ground() -> void:
	if needs_art(): return
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	check("it is a boss", boss is Boss)
	# **前两个 Boss 一个飞一个走，这个是地面重装**：踩着独轮滚，受重力
	check("it is not a floating one", boss.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	check("it brings a portrait from this pack's art",
		boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.begins_with("%s/enemies/3_boss" % ART),
		str(boss.hud_portrait()))
	check("the ultimate only takes a quarter off it",
		boss.ultimate_damage() == roundi(boss.max_health * 0.25), str(boss.ultimate_damage()))


func test_its_three_moves_come_round_in_turn() -> void:
	# **三招轮着来，不是随机挑**：打两轮就能背下节奏，死了也知道自己错在哪。
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	var seen: Array[int] = []
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		var now := boss.move_kind()
		if (now == BossWheel.Move.SHOOT or now == BossWheel.Move.LOB
				or now == BossWheel.Move.WINDUP) and (seen.is_empty() or seen[-1] != now):
			seen.append(now)
		if seen.size() >= 4:
			break
	check("it uses the cannon", seen.has(BossWheel.Move.SHOOT), str(seen))
	check("and the lob", seen.has(BossWheel.Move.LOB), str(seen))
	check("and the roll", seen.has(BossWheel.Move.WINDUP), str(seen))
	check("and it never does the same one twice in a row",
		seen.size() < 2 or seen[0] != seen[1], str(seen))


func test_the_roll_is_telegraphed() -> void:
	# 蓄力那一下就是留给玩家跳开的。没有预兆就成了没法躲。
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	check("there really is a wind-up", boss.roll_windup > 0.2, str(boss.roll_windup))
	var held := true
	var rolled := false
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		if boss.move_kind() == BossWheel.Move.WINDUP:
			held = held and absf(boss.velocity.x) < 1.0
		if boss.move_kind() == BossWheel.Move.ROLL:
			rolled = true
			break
	check("it holds still while winding up", held)
	check("then it rolls", rolled)
	check("and the roll is faster than it patrols", boss.roll_speed > boss.roam_speed,
		"%.0f / %.0f" % [boss.roll_speed, boss.roam_speed])


func test_the_lob_arcs_over_cover() -> void:
	# **这一招专治「躲在平台后面慢慢磨」**：炸弹是抛物线，越得过掩体。
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	var thrown: Array[Node] = []
	for i in 900:
		await tree.physics_frame
		player.global_position = Vector2(640, STAND_Y)
		player.health = 99999
		for node in tree.get_nodes_in_group(Grenade.GROUP):
			if not thrown.has(node):
				thrown.append(node)
		if not thrown.is_empty():
			break
	check("it lobs something", not thrown.is_empty())
	if thrown.is_empty():
		return
	var bomb := thrown[0] as Grenade
	# 抛物线：出手时是斜着往上的，不是直着飞
	check("and it really arcs, not flies straight", bomb.velocity.y < 0.0, str(bomb.velocity))
	check("towards the player", signf(bomb.velocity.x) == signf(640.0 - boss.global_position.x),
		str(bomb.velocity))
	check("and it is the enemies' bomb, so it cannot hurt its own side",
		bomb.target_layer == 2, str(bomb.target_layer))


func test_it_never_leaves_its_patch() -> void:
	# 不追出地盘——走位是玩家的事（和前两个 Boss 一个道理）。
	# **不能只断言「没超出它自己的 `roam_range`」**：把那个数调大它自然就不超了，等于什么都没测。
	# 要测的是「它不会朝玩家一路压过来」。
	var boss := await face_the_mech(Vector2(200, STAND_Y))
	var home: Vector2 = boss._home
	var strayed := 0.0
	var closest := absf(boss.global_position.x - 200.0)
	for i in 400:
		await tree.physics_frame
		player.global_position = Vector2(200, STAND_Y)
		player.health = 99999
		strayed = maxf(strayed, absf(boss.global_position.x - home.x) - boss.roam_range)
		closest = minf(closest, absf(boss.global_position.x - 200.0))
	check("it stays in its patch", strayed < 40.0, "%.0f" % strayed)
	check("and never comes over to get you", closest > 300.0, "最近 %.0f" % closest)
	# **地盘要装得进 Boss 区**：它左右各漫游 `roam_range`，整块不能超过一屏，
	# 否则关卡里给它摆的那片平台就够不着它了（这条约束是关卡设计给的，不是它自己的）。
	check("and its patch fits on one screen", boss.roam_range * 2.0 <= 640.0,
		str(boss.roam_range))


func test_it_turns_nasty_below_half_and_says_so() -> void:
	var boss := await face_the_mech(Vector2(640, STAND_Y))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("a scratch does not flip it", not boss.is_enraged() and not events.has(&"boss_enrage"))
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("crossing half flips it", boss.is_enraged())
	check("and it says so", events.has(&"boss_enrage"), str(events))
	events.clear()
	boss.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("but only once", not events.has(&"boss_enrage"), str(events))


func test_hurt_it_rolls_faster_and_rests_less() -> void:
	await reset_scene(false, false, pack())
	var boss := spawn_boss()
	var calm_roll: float = boss._speed(boss.roll_speed)
	var calm_rest: float = boss._timing(boss.attack_rest)
	boss.take_damage(boss.max_health / 2, Vector2.INF, player)
	await frames(2)
	check("setup: it is enraged", boss.is_enraged())
	check("it rolls faster", boss._speed(boss.roll_speed) > calm_roll,
		"%.0f -> %.0f" % [calm_roll, boss._speed(boss.roll_speed)])
	check("and pauses less between moves", boss._timing(boss.attack_rest) < calm_rest,
		"%.2f -> %.2f" % [calm_rest, boss._timing(boss.attack_rest)])


func test_the_boss_skin_changes_nothing_about_the_rules() -> void:
	var out := []
	for skin: SkinPack in [Skins.default_skin(), pack()]:
		await reset_scene(false, false, skin)
		var boss := spawn_boss()
		boss.appear()
		await frames(2)
		var shape := boss.get_node("CollisionShape2D") as CollisionShape2D
		out.append({
			"box": (shape.shape as RectangleShape2D).size,
			"muzzle": boss._muzzle_position() - boss.global_position,
			"health": boss.max_health,
			"roam": boss.roam_range,
		})
	for key: String in out[0]:
		check("%s is the same with either skin" % key, out[0][key] == out[1][key],
			"方块 %s，酒吧街 %s" % [out[0][key], out[1][key]])
