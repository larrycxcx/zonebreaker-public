extends GameTest
## 地下室（第四关）的六种敌人。打法 2026-10 和用户一起定的：这一关往上爬，威胁要从上下和侧面来。
##
## | 键 | 素材 | 打法 | 实现 |
## |---|---|---|---|
## | 4_a | 光膀子打手 | 从下面追上来，一层层跳上平台 | D（`EnemyChaser`），`climb_reach` 放宽 |
## | 4_b | 猫耳女 | 平台守卫，一刀扫过平台面 | 锤子兵（`EnemyHammer`），够得更远 |
## | 4_c | 西装男 | 三向枪手 | 巡逻兵 + 真斜射（和 3-B 一套） |
## | 4_d | 无人机 | 贴着玩家的高度飞、横着打 | **新的** `EnemyHoverGun` |
## | 4_e | 蜘蛛炮台 | 守层炮台，横着打一串 | 巡逻兵连发，矮判定框 |
## | 4_f | 骷髅衫打手 | 一胳膊把人抡下平台 | 锤子兵 + `smash_knockback` |

const PACK := "res://skins/basement/basement_skin.tres"
const ART := "res://skins/basement"
const GROUND_Y := 320.0
const STAND_Y := 304.0
## 键 → [帧宽, 帧高]。会飞的那架是 48×48、锚点在机身中心，别的都是 80×56。
const ENEMIES := {
	&"4_a": [80, 56], &"4_b": [80, 56], &"4_c": [80, 56],
	&"4_d": [48, 48], &"4_e": [80, 56], &"4_f": [80, 56],
}
const SCENES := {
	&"4_a": "res://scenes/enemy_4_a.tscn", &"4_b": "res://scenes/enemy_4_b.tscn",
	&"4_c": "res://scenes/enemy_4_c.tscn", &"4_d": "res://scenes/enemy_4_d.tscn",
	&"4_e": "res://scenes/enemy_4_e.tscn", &"4_f": "res://scenes/enemy_4_f.tscn",
}


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func sheet(key: StringName, clip: String, side := "r") -> Image:
	return (load("%s/enemies/%s/%s_%s.png" % [ART, key, clip, side]) as Texture2D).get_image()


func has_clip(key: StringName, clip: String) -> bool:
	return ResourceLoader.exists("%s/enemies/%s/%s_r.png" % [ART, key, clip])


## 外观场景里的锚点（贴图里哪一个像素对着敌人的原点）。
func anchor_of(key: StringName) -> Vector2i:
	var visual := pack().appearances[key].instantiate() as EnemySpriteAppearance
	var at := visual.anchor
	visual.free()
	return at


func spawn(key: StringName, at: Vector2) -> Enemy:
	var enemy := (load(SCENES[key]) as PackedScene).instantiate() as Enemy
	main.get_node("Enemies").add_child(enemy)
	enemy.global_position = at
	return enemy


## 只留地面：**测试关自己有 6 块单向浮台**，不清掉的话「它跳得上去吗」量的是它踩着关卡原有的浮台爬上去
## （写对照组时就是这么栽的：第一关的 D 也「爬」上去了）。
func open_floor(skin: SkinPack = null) -> void:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()


func add_ledge(x: float, top: float, wide := 160.0) -> Platform:
	var ledge: Platform = load("res://scenes/platform.tscn").instantiate()
	ledge.one_way = true
	ledge.position = Vector2(x, top)
	ledge.size = Vector2(wide, 16)
	main.get_node("Level").add_child(ledge)
	return ledge


func feet_of(enemy: Enemy) -> float:
	var box := enemy.get_node("CollisionShape2D") as CollisionShape2D
	return enemy.global_position.y + (box.shape as RectangleShape2D).size.y / 2.0 + box.position.y


## 贴图里离某一点最近的不透明像素有多远（看出膛点是不是落在画面上的枪口）。
func distance_to_art(img: Image, frame: int, frame_w: int, point: Vector2) -> float:
	var best := INF
	for y in img.get_height():
		for x in frame_w:
			if img.get_pixel(frame * frame_w + x, y).a > 0.0:
				best = minf(best, point.distance_to(Vector2(x, y)))
	return best


# ---------------------------------------------------------------- 贴图

func test_every_enemy_is_registered_and_has_art() -> void:
	for key: StringName in ENEMIES:
		check("%s is in the pack" % key, pack().appearances.has(key))
		check("%s has an idle, a hurt and a death" % key,
			has_clip(key, "idle") and has_clip(key, "hurt") and has_clip(key, "death"))
		var spec: Array = ENEMIES[key]
		var img := sheet(key, "idle")
		check("%s draws at %dx%d" % [key, spec[0], spec[1]],
			img.get_height() == spec[1] and img.get_width() % int(spec[0]) == 0,
			"%dx%d" % [img.get_width(), img.get_height()])
		check("%s has a scene" % key, ResourceLoader.exists(SCENES[key]))


func test_the_art_is_mirrored_about_the_anchor() -> void:
	for key: StringName in ENEMIES:
		var w: int = ENEMIES[key][0]
		var ax := anchor_of(key).x
		var right := sheet(key, "idle")
		var left := sheet(key, "idle", "l")
		var wrong := 0
		for y in right.get_height():
			for x in right.get_width():
				var frame := x / w
				var sx := frame * w + 2 * ax - x % w
				if sx < frame * w or sx >= (frame + 1) * w:
					continue
				if right.get_pixel(x, y) != left.get_pixel(sx, y):
					wrong += 1
		check("%s mirrors about its anchor" % key, wrong == 0, "%d 个像素对不上" % wrong)


func test_feet_meet_the_bottom_of_the_hit_box() -> void:
	# 走地上的：贴图最低一行 = 锚点 + 判定框半高 - 1。蜘蛛炮台的判定框矮（22），锚点跟着往下挪了
	for key: StringName in ENEMIES:
		if key == &"4_d":
			continue
		var enemy := (load(SCENES[key]) as PackedScene).instantiate() as Enemy
		var box := enemy.get_node("CollisionShape2D") as CollisionShape2D
		var half := (box.shape as RectangleShape2D).size.y / 2.0
		enemy.free()
		var img := sheet(key, "idle")
		var lowest := -1
		for y in img.get_height():
			for x in int(ENEMIES[key][0]):
				if img.get_pixel(x, y).a > 0.0:
					lowest = y
					break
		check("%s stands on the bottom of its hit box" % key,
			lowest == anchor_of(key).y + int(half) - 1,
			"最低一行 y=%d，锚点 %d + 半高 %d" % [lowest, anchor_of(key).y, half])


func test_the_drone_was_turned_round_to_face_right() -> void:
	# 素材是**朝左**画的（枪管在左），生成时翻过来。`_r` 必须是朝右的：红色尾灯在后面（左边）
	var img := sheet(&"4_d", "idle")
	var ax := anchor_of(&"4_d").x
	var behind := 0
	var ahead := 0
	for y in img.get_height():
		for x in 48:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.r > 0.55 and c.r > c.g + 0.3:
				if x < ax:
					behind += 1
				else:
					ahead += 1
	check("setup: there are tail lights", behind + ahead > 0)
	check("and they are behind it", behind > ahead, "后 %d 前 %d" % [behind, ahead])


func test_shots_leave_from_the_guns_in_the_art() -> void:
	# 出膛点（相对原点）放回贴图里，离画面上的枪 / 火光不超过 3 像素
	var cases := [
		[&"4_c", "attack_level", 1, "level"], [&"4_c", "attack_up", 1, "up"],
		[&"4_c", "attack_down", 1, "down"], [&"4_e", "attack_level", 1, "level"],
		[&"4_d", "idle", 0, "level"],
	]
	for case: Array in cases:
		var key: StringName = case[0]
		var enemy := (load(SCENES[key]) as PackedScene).instantiate() as Enemy
		var offset: Vector2
		match case[3]:
			"up":
				offset = enemy.diagonal_up_muzzle
			"down":
				offset = enemy.diagonal_down_muzzle
			_:
				offset = (enemy.get_node("Muzzle") as Marker2D).position
		enemy.free()
		var point := Vector2(anchor_of(key)) + offset
		var gap := distance_to_art(sheet(key, case[1]), case[2], ENEMIES[key][0], point)
		check("%s %s leaves from the gun" % [key, case[3]], gap <= 3.0, "%.1f px" % gap)


# ---------------------------------------------------------------- 4-A 追兵

func test_the_climber_follows_you_up_the_ledges() -> void:
	# D 原来只在玩家就在头顶附近（水平 48 以内）才起跳；4-A 放宽了，玩家在上面它就一路往上跳
	await open_floor()
	var low := add_ledge(260, 250)
	var high := add_ledge(420, 180)
	var climber := spawn(&"4_a", Vector2(200, STAND_Y)) as EnemyChaser
	player.global_position = Vector2(500, high.position.y - 16.0)
	snap_camera()
	var best := INF
	for i in 240:
		await tree.physics_frame
		if climber.is_on_floor():
			best = minf(best, feet_of(climber))
	check("setup: the ledges are above the floor", low.position.y < GROUND_Y)
	check("it climbed to the top ledge", absf(best - high.position.y) < 2.0,
		"站得最高的面 y=%.0f，顶上那块 %.0f" % [best, high.position.y])


func test_the_old_chaser_would_not_have_bothered() -> void:
	# 对照：同样的摆法，第一关的 D（climb_reach 48）不会往上跳——证明是数据在起作用
	await open_floor()
	add_ledge(260, 250)
	var high := add_ledge(420, 180)
	var old := (load("res://scenes/enemy_1_d.tscn") as PackedScene).instantiate() as EnemyChaser
	main.get_node("Enemies").add_child(old)
	old.global_position = Vector2(200, STAND_Y)
	player.global_position = Vector2(500, high.position.y - 16.0)
	snap_camera()
	var best := INF
	for i in 240:
		await tree.physics_frame
		if old.is_on_floor():
			best = minf(best, feet_of(old))
	check("D stays below", best > high.position.y + 2.0, "y=%.0f" % best)


# ---------------------------------------------------------------- 4-B 平台守卫

func test_the_guard_reaches_further_than_the_hammer() -> void:
	var guard := (load(SCENES[&"4_b"]) as PackedScene).instantiate() as EnemyHammer
	var hammer := (load("res://scenes/enemy_2_d.tscn") as PackedScene).instantiate() as EnemyHammer
	check("the slash reaches further than the hammer", guard.smash_range > hammer.smash_range + 12.0,
		"%.0f vs %.0f" % [guard.smash_range, hammer.smash_range])
	check("and it guards rather than charges", guard.charge_speed <= guard.move_speed)
	guard.free()
	hammer.free()


func test_the_guard_cuts_you_on_her_ledge_at_the_slash_frame() -> void:
	await open_floor()
	var guard := spawn(&"4_b", Vector2(300, STAND_Y)) as EnemyHammer
	guard.facing = 1
	guard._apply_facing()
	player.global_position = Vector2(300 + 56.0, STAND_Y)
	snap_camera()
	var full := player.health
	await frames(3)
	check("setup: she starts the swing", guard.is_swinging())
	var early := int(guard.hit_delay() * 60.0) - 4
	await frames(early)
	check("not yet — the blade is still up", player.health == full, "%d" % player.health)
	await frames(10)
	check("then the slash lands at 56 px", player.health < full, "%d -> %d" % [full, player.health])


# ---------------------------------------------------------------- 4-C 三向枪手

func test_the_suit_shoots_up_at_a_climber() -> void:
	await open_floor()
	var suit := spawn(&"4_c", Vector2(300, STAND_Y))
	suit.facing = 1
	suit._apply_facing()
	var ledge := add_ledge(380, 200, 120)
	player.global_position = Vector2(430, ledge.position.y - 16.0)
	snap_camera()
	await frames(5)
	check("a player up on a ledge is a diagonal target",
		suit.aim_for(player) == Enemy.Aim.DIAGONAL_UP, str(suit.aim_for(player)))
	var fired: Array[Vector2] = []
	suit.shot_fired.connect(func() -> void: fired.append(suit.last_shot_direction))
	await frames(200)
	check("it fires", not fired.is_empty())
	if not fired.is_empty():
		check("upwards", fired[0].y < -0.5, str(fired[0]))


# ---------------------------------------------------------------- 4-D 无人机

func spawn_drone(at: Vector2) -> EnemyHoverGun:
	var drone := spawn(&"4_d", at) as EnemyHoverGun
	drone.set_anchor(at)
	return drone


func test_the_drone_rises_to_your_height() -> void:
	await open_floor()
	var drone := spawn_drone(Vector2(560, 280))
	var ledge := add_ledge(120, 160, 160)
	player.global_position = Vector2(200, ledge.position.y - 16.0)
	snap_camera()
	await frames(150)
	check("it climbed to the player's height",
		absf(drone.body_center().y - player.body_center().y) <= drone.align_tolerance,
		"%.0f vs %.0f" % [drone.body_center().y, player.body_center().y])
	check("without leaving its side of the shaft", absf(drone.global_position.x - 560.0) < 1.0,
		str(drone.global_position.x))


func test_the_drone_fires_sideways_once_level() -> void:
	await open_floor()
	var drone := spawn_drone(Vector2(560, player.global_position.y))
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	var fired: Array[Vector2] = []
	drone.shot_fired.connect(func() -> void: fired.append(drone.last_shot_direction))
	await frames(150)
	check("it fires", not fired.is_empty())
	if not fired.is_empty():
		check("straight across, at the player", fired[0].is_equal_approx(Vector2.LEFT), str(fired[0]))


func test_the_drone_holds_fire_while_you_are_above_it() -> void:
	# 对不齐就不开火：玩家一跳先甩开它一截，那一截空当就是躲它的机会
	await open_floor()
	var drone := spawn_drone(Vector2(560, 300))
	drone.climb_speed = 0.0
	var ledge := add_ledge(120, 160, 160)
	player.global_position = Vector2(200, ledge.position.y - 16.0)
	snap_camera()
	var fired: Array[int] = []
	drone.shot_fired.connect(func() -> void: fired.append(1))
	await frames(150)
	check("no shots while it is out of line", fired.is_empty(), str(fired.size()))


func test_the_drone_stays_on_its_leash() -> void:
	await open_floor()
	camera_rig().limit_top = -2000
	var drone := spawn_drone(Vector2(560, 280))
	# 玩家远在 600px 以上、它又在画面外——不放大发现距离的话它根本看不见人，
	# 「没飞出拴绳」比的就是一架从头到尾没动过的飞机
	drone.detect_range = 2000.0
	var ledge := add_ledge(120, -300, 160)
	player.global_position = Vector2(200, ledge.position.y - 16.0)
	snap_camera()
	await frames(400)
	check("setup: it really went after the player", drone.global_position.y < 280.0 - 150.0,
		"%.0f" % drone.global_position.y)
	check("but stops at the end of its leash", drone.global_position.y >= 280.0 - drone.leash - 1.0,
		"%.0f" % drone.global_position.y)


# ---------------------------------------------------------------- 4-E 蜘蛛炮台

func test_the_spider_fires_a_burst_along_its_floor() -> void:
	await open_floor()
	var spider := spawn(&"4_e", Vector2(500, GROUND_Y - 11.0))
	spider.facing = -1
	spider._apply_facing()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	var fired: Array[Vector2] = []
	spider.shot_fired.connect(func() -> void: fired.append(spider.last_shot_direction))
	await frames(200)
	check("it fires more than one shot", fired.size() >= 2, str(fired.size()))
	check("all of them flat", fired.all(func(d: Vector2) -> bool: return absf(d.y) < 0.01))
	check("and it never aims off the level", not spider.can_aim_diagonally)


func test_the_spider_is_low_and_its_shots_clear_a_crouch() -> void:
	await open_floor()
	var spider := spawn(&"4_e", Vector2(500, GROUND_Y - 11.0))
	await frames(5)
	check("it sits on the floor", absf(feet_of(spider) - GROUND_Y) < 1.0, "%.1f" % feet_of(spider))
	var gun := GROUND_Y - spider.level_muzzle_position().y
	check("its gun is above a crouching player", gun > Player.CROUCH_HEIGHT,
		"离地 %.0f，趴下高 %.0f" % [gun, Player.CROUCH_HEIGHT])
	check("and low enough to hit a standing one", gun < 32.0, "离地 %.0f" % gun)


# ---------------------------------------------------------------- 4-F 打飞人

## 让 4-F 在一块浮台上对着玩家抡一下，返回 1 秒后玩家的位置。
## `knock` 传 null 就用场景里配的那个（**测的是场景本身**，不能在这儿替它填数）。
func shove_test(knock: Variant = null) -> Dictionary:
	await open_floor()
	var ledge := add_ledge(200, 200, 160)
	var top := ledge.position.y
	var shover := spawn(&"4_f", Vector2(250, top - 16.0)) as EnemyHammer
	if knock != null:
		shover.smash_knockback = knock
	shover.charge_speed = 0.0
	shover.move_speed = 0.0
	shover.facing = 1
	shover._apply_facing()
	player.global_position = Vector2(290, top - 16.0)
	snap_camera()
	var full := player.health
	await frames(60)
	return {"y": player.global_position.y, "top": top, "hurt": player.health < full}


func test_the_shover_throws_you_off_the_ledge() -> void:
	var hit: Dictionary = await shove_test()
	check("setup: it landed a blow", hit["hurt"])
	check("you are flung off the ledge", hit["y"] > hit["top"] + 40.0,
		"y=%.0f，浮台顶 %.0f" % [hit["y"], hit["top"]])


func test_without_the_shove_the_same_blow_leaves_you_standing() -> void:
	# 对照：同一下，不带额外击退，玩家只是被推开一点、还站在浮台上
	var hit: Dictionary = await shove_test(Vector2.ZERO)
	check("setup: it landed a blow", hit["hurt"])
	check("you keep your footing", absf(hit["y"] - (hit["top"] - 16.0)) < 2.0,
		"y=%.0f，浮台顶 %.0f" % [hit["y"], hit["top"]])


# ---------------------------------------------------------------- 换皮肤不改规则

func test_every_one_runs_in_the_pack_without_errors() -> void:
	# 换上这套包，六种都摆到玩家面前跑两秒：贴图缺哪一组的话会刷「Resource file not found」（runner 记成失败）
	await reset_scene(false, false, pack())
	var x := 360.0
	for key: StringName in SCENES:
		var y := GROUND_Y - (11.0 if key == &"4_e" else 16.0)
		if key == &"4_d":
			y = STAND_Y - 40.0
		var enemy := spawn(key, Vector2(x, y))
		if enemy is EnemyHoverGun:
			(enemy as EnemyHoverGun).set_anchor(enemy.global_position)
		x += 40.0
	player.global_position = Vector2(200, STAND_Y)
	snap_camera()
	await frames(120)
	check("the level ran", player != null)
