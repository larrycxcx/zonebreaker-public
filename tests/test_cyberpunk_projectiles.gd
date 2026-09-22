extends GameTest
## 赛博朋克皮肤包的子弹和手雷（贴图由 tools/projectile_build.py 从素材包的 5 Bullets 生成）。
##
## 和角色贴图守的是同一类东西：贴图齐全、8 个方向之间严格是翻转 / 旋转关系、谁打出什么子弹对得上，
## 以及**换皮肤不改变规则**——子弹本体照样按飞行方向转（碰撞体是横着的细条，那是判定），
## 飞到哪、手雷落在哪，方块和精灵图一模一样；贴图自己把转角抵消掉，靠换图表示方向。

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"
const ART := "res://skins/cyberpunk/projectiles"
const BULLETS := [&"player_bullet", &"enemy_bullet", &"turret_bullet", &"flyer_bullet"]
const GRENADES := [&"player_grenade", &"enemy_grenade"]
## 圆的、不分方向的发射物（只有一张 ball.png）。
const BALLS := [&"player_grenade", &"enemy_grenade", &"boss_bullet"]
const DIRECTIONS := {
	&"right": Vector2(1, 0), &"left": Vector2(-1, 0), &"up": Vector2(0, -1), &"down": Vector2(0, 1),
	&"up_right": Vector2(1, -1), &"up_left": Vector2(-1, -1), &"down_right": Vector2(1, 1), &"down_left": Vector2(-1, 1),
}


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func drawing(who: StringName, name: StringName) -> Image:
	var texture := load("%s/%s/%s.png" % [ART, who, name]) as Texture2D
	return texture.get_image() if texture != null else null


## 两张图是不是按 transform（原图坐标 → 新图坐标）逐像素对应。
func same_after(a: Image, b: Image, transform: Callable) -> bool:
	if a == null or b == null:
		return false
	for y in a.get_height():
		for x in a.get_width():
			var to: Vector2i = transform.call(x, y, a.get_width(), a.get_height())
			if to.x < 0 or to.y < 0 or to.x >= b.get_width() or to.y >= b.get_height():
				return false
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(to.x, to.y)
			if pa.a != pb.a or (pa.a > 0.0 and pa != pb):
				return false
	return true


# ---------------------------------------------------------------- 贴图本身

func test_every_texture_is_there() -> void:
	for who: StringName in BULLETS:
		for name: StringName in DIRECTIONS:
			check("%s %s exists" % [who, name], drawing(who, name) != null)
	for who: StringName in BALLS:
		check("%s ball exists" % who, drawing(who, &"ball") != null)


func test_the_eight_directions_are_flips_of_two_drawings() -> void:
	# 素材只画了朝右、朝右下两张，其余都是翻转 / 旋转出来的——任何一张单独改坏了都会对不上
	var mirror_x := func(x: int, y: int, w: int, _h: int) -> Vector2i: return Vector2i(w - 1 - x, y)
	var mirror_y := func(x: int, y: int, _w: int, h: int) -> Vector2i: return Vector2i(x, h - 1 - y)
	var turn_cw := func(x: int, y: int, _w: int, h: int) -> Vector2i: return Vector2i(h - 1 - y, x)
	for who: StringName in BULLETS:
		check("%s: left mirrors right" % who, same_after(drawing(who, &"right"), drawing(who, &"left"), mirror_x))
		check("%s: down is right turned clockwise" % who, same_after(drawing(who, &"right"), drawing(who, &"down"), turn_cw))
		check("%s: up mirrors down" % who, same_after(drawing(who, &"down"), drawing(who, &"up"), mirror_y))
		check("%s: down_left mirrors down_right" % who, same_after(drawing(who, &"down_right"), drawing(who, &"down_left"), mirror_x))
		check("%s: up_right mirrors down_right" % who, same_after(drawing(who, &"down_right"), drawing(who, &"up_right"), mirror_y))
		check("%s: up_left mirrors up_right" % who, same_after(drawing(who, &"up_right"), drawing(who, &"up_left"), mirror_x))


func test_the_two_grenades_differ_only_in_colour() -> void:
	var mine := drawing(&"player_grenade", &"ball")
	var theirs := drawing(&"enemy_grenade", &"ball")
	var same_shape := mine.get_size() == theirs.get_size()
	var recoloured := 0
	if same_shape:
		for y in mine.get_height():
			for x in mine.get_width():
				var a := mine.get_pixel(x, y)
				var b := theirs.get_pixel(x, y)
				if (a.a > 0.03) != (b.a > 0.03):
					same_shape = false
				elif a.a > 0.03 and not a.is_equal_approx(b):
					recoloured += 1
	check("F's grenade has the same outline as the player's", same_shape)
	check("but another colour", recoloured > 4, "%d 个像素换了色" % recoloured)


# ---------------------------------------------------------------- 谁打出什么

func test_each_shooter_fires_its_own_projectile() -> void:
	var rifle := (load("res://weapons/rifle.tres") as Weapon).projectile.instantiate()
	var grenade := (load("res://weapons/grenade.tres") as Weapon).projectile.instantiate()
	check("the rifle fires player bullets", rifle.skin_key == &"player_bullet", str(rifle.skin_key))
	check("the launcher fires player grenades", grenade.skin_key == &"player_grenade", str(grenade.skin_key))
	rifle.free()
	grenade.free()
	await reset_scene(true)
	for pair in [["WalkerA", &"enemy_bullet"], ["WalkerB", &"enemy_bullet"], ["WalkerC", &"enemy_bullet"],
			["BossA", &"boss_bullet"], ["Turret1", &"turret_bullet"], ["FlyerE", &"flyer_bullet"]]:
		var enemy: Enemy = main.get_node("Enemies/" + pair[0])
		var shot := enemy.bullet_scene.instantiate()
		check("%s fires %s" % [pair[0], pair[1]], shot.skin_key == pair[1], str(shot.skin_key))
		shot.free()
	var f: EnemyGrenadier = main.get_node("Enemies/WalkerF")
	var theirs := f.grenade_scene.instantiate()
	check("F bats enemy grenades", theirs.skin_key == &"enemy_grenade", str(theirs.skin_key))
	theirs.free()


func test_turret_and_flyer_shots_are_enemy_bullets_in_another_look() -> void:
	# 炮台、E、Boss 各有自己的子弹场景，只是为了换个样子：规则必须和敌人子弹完全一样
	# （尤其要在 enemy_bullets 组里，终极武器靠它清弹）
	var base := (load("res://scenes/enemy_bullet.tscn") as PackedScene).instantiate() as Bullet
	for path in ["res://scenes/turret_bullet.tscn", "res://scenes/flyer_bullet.tscn", "res://scenes/boss_bullet.tscn"]:
		var shot := (load(path) as PackedScene).instantiate() as Bullet
		for property in ["speed", "lifetime", "damage", "collision_layer", "collision_mask"]:
			check("%s: %s as an enemy bullet" % [path.get_file(), property], shot.get(property) == base.get(property),
				"%s vs %s" % [shot.get(property), base.get(property)])
		check("%s: same hitbox" % path.get_file(),
			(shot.get_node("CollisionShape2D").shape as RectangleShape2D).size == (base.get_node("CollisionShape2D").shape as RectangleShape2D).size)
		check("%s: cleared by the ultimate like any enemy bullet" % path.get_file(), shot.is_in_group(&"enemy_bullets"))
		shot.free()
	base.free()


# ---------------------------------------------------------------- 接上去以后

## 在关卡里朝 direction 放一颗 scene 的子弹，返回它。
func fire(scene: String, direction: Vector2) -> Bullet:
	var shot := (load(scene) as PackedScene).instantiate() as Bullet
	shot.launch(direction.normalized())
	main.add_child(shot)
	shot.global_position = Vector2(400, 200)
	return shot


func test_bullets_pick_the_drawing_for_their_direction() -> void:
	await reset_scene(false, false, skin())
	for name: StringName in DIRECTIONS:
		var shot := fire("res://scenes/bullet.tscn", DIRECTIONS[name])
		var visual := shot.get_node("Visual")
		check("%s: drawn by the skin" % name, visual is ProjectileAppearance, str(visual))
		if visual is ProjectileAppearance:
			var look := visual as ProjectileAppearance
			check("%s: picks the %s drawing" % [name, name], look.texture_name() == name, str(look.texture_name()))
			check("%s: the drawing is not turned (the art already points that way)" % name,
				is_zero_approx(look.global_rotation), "%.3f" % look.global_rotation)
		# 规则不变：本体照样按飞行方向转（碰撞体是横着的细条）
		check("%s: the bullet itself still turns to fly" % name,
			is_equal_approx(shot.rotation, (DIRECTIONS[name] as Vector2).angle()), "%.3f" % shot.rotation)
		shot.free()


func test_projectile_art_is_pure_display() -> void:
	await reset_scene(false, false, skin())
	for scene in ["res://scenes/bullet.tscn", "res://scenes/enemy_bullet.tscn", "res://scenes/turret_bullet.tscn",
			"res://scenes/flyer_bullet.tscn", "res://scenes/boss_bullet.tscn"]:
		var shot := fire(scene, Vector2.RIGHT)
		var visual := shot.get_node("Visual")
		check("%s: drawn by the skin" % scene.get_file(), visual is ProjectileAppearance, str(visual))
		check("%s: the drawing has no collision" % scene.get_file(),
			visual.find_children("*", "CollisionObject2D", true, false).is_empty()
			and visual.find_children("*", "CollisionShape2D", true, false).is_empty())
		shot.free()


func test_placeholder_bullets_still_turn_with_the_shot() -> void:
	# 默认包没有子弹贴图：用场景自带的细条，跟着本体一起转（向上打时是竖条）
	await reset_scene()
	var shot := fire("res://scenes/bullet.tscn", Vector2.UP)
	var visual := shot.get_node("Visual")
	check("the default pack keeps the placeholder", not (visual is ProjectileAppearance), str(visual))
	check("and it turns with the shot", is_equal_approx((visual as Node2D).global_rotation, -PI / 2.0),
		"%.3f" % (visual as Node2D).global_rotation)
	shot.free()


func test_grenades_wear_their_ball() -> void:
	await reset_scene(true, false, skin())
	for pair in [["res://scenes/grenade.tscn", "/player_grenade"], ["res://scenes/enemy_grenade.tscn", "/enemy_grenade"]]:
		var grenade := (load(pair[0]) as PackedScene).instantiate() as Grenade
		grenade.launch(Vector2.RIGHT)
		main.add_child(grenade)
		grenade.global_position = Vector2(400, 200)
		var visual := grenade.get_node("Visual")
		check("%s: drawn by the skin" % pair[0].get_file(), visual is ProjectileAppearance, str(visual))
		if visual is ProjectileAppearance:
			var look := visual as ProjectileAppearance
			check("%s: its own ball" % pair[0].get_file(), look.art_dir.ends_with(pair[1]) and look.texture_name() == &"ball",
				"%s / %s" % [look.art_dir, look.texture_name()])
		grenade.free()


func measure(pack: SkinPack) -> Dictionary:
	await reset_scene(false, false, pack)
	var out := {}
	var shot := fire("res://scenes/bullet.tscn", Vector2(1, -1))
	var start := shot.global_position
	await frames(10)
	out["bullet_travel"] = (shot.global_position - start).snappedf(0.01) if is_instance_valid(shot) else Vector2.INF
	# 手雷：玩家朝前扔一颗，记下它 20 帧后在哪
	player.global_position = Vector2(300, 304)
	await frames(5)
	player.current_weapon = 1
	player._shoot(Vector2.RIGHT)
	var grenades := tree.get_nodes_in_group(Grenade.GROUP)
	out["grenades"] = grenades.size()
	await frames(20)
	out["grenade_at"] = (grenades[0] as Node2D).global_position.snappedf(0.01) \
		if not grenades.is_empty() and is_instance_valid(grenades[0]) else Vector2.INF
	return out


func test_the_projectile_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var sprites := await measure(skin())
	check("the shots really flew in this test", blocks["grenades"] == 1 and blocks["bullet_travel"].length() > 20.0
		and blocks["grenade_at"] != Vector2.INF, str(blocks))
	for key: String in blocks:
		check("%s is the same with either skin" % key, blocks[key] == sprites[key],
			"方块 %s，精灵图 %s" % [blocks[key], sprites[key]])
