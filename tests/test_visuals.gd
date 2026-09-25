extends GameTest
## 外观翻转：一律保持 scale 为正，靠镜像子节点的横向位置来左右翻转（见 VisualFlip）。
##
## 为什么要专门测：用负的 scale 翻转时，Visual 下的 ColorRect 算出来的绘制矩形是错的
## （位置整整偏出一个身宽、高度为负），引擎按它做屏幕剔除，角色在某些位置会整块不画出来——
## Boss A 跳到空中时偶尔整个消失就是这个原因。矩形对不对在无头模式下也能检查，不需要真的渲染。

## 关卡里各种角色的节点路径。
const ACTORS := [
	"Player", "Enemies/WalkerA", "Enemies/WalkerB", "Enemies/WalkerC",
	"Enemies/ChaserD", "Enemies/FlyerE", "Enemies/Turret1", "Enemies/WalkerF", "Enemies/BossMissile",
]


func actors() -> Array:
	var found := []
	for path in ACTORS:
		found.append(main.get_node(path))
	return found


## 让它朝某个方向。玩法只通过外观层的接口说「我朝这边」，剩下的它自己画。
func face(actor: Node, facing: int) -> void:
	actor.facing = facing
	if actor is Enemy:
		(actor as Enemy)._apply_visual_facing()
	else:
		(actor.get_node("Visual") as Appearance).face(facing)


## Visual 下所有的外观方块。
func rects(actor: Node) -> Array:
	return actor.get_node("Visual").get_children().filter(func(c): return c is Control)


func test_no_negative_scale() -> void:
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			var visual: Node2D = actor.get_node("Visual")
			check("%s: visual scale stays positive facing %d" % [actor.name, facing], visual.scale.x > 0.0, str(visual.scale))


func test_visual_rects_stay_valid() -> void:
	# 每个外观方块的全局矩形都要是正的尺寸、并且真的盖在身体上（这正是被引擎拿去剔除的矩形）
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			for rect in rects(actor):
				var r: Rect2 = rect.get_global_rect()
				check("%s/%s facing %d: rect has positive size" % [actor.name, rect.name, facing],
					r.size.x > 0.0 and r.size.y > 0.0, str(r))
				check("%s/%s facing %d: rect sits on the body" % [actor.name, rect.name, facing],
					r.grow(4.0).has_point(actor.global_position) or actor.global_position.distance_to(r.get_center()) < 48.0,
					"%s vs body at %s" % [r, actor.global_position])


func test_facing_left_mirrors_facing_right() -> void:
	# 朝左时的摆位正好是朝右时的镜像（E 的左右翅膀这种对称的一对会互换，也满足这条）
	await reset_scene(true)
	# 冻住 AI：敌人在屏幕里看得见玩家就会自己转身去追 / 瞄，会把这里设的朝向盖掉（这条只测外观镜像）
	for actor in actors():
		if actor is Enemy:
			actor.set_physics_process(false)
	for actor in actors():
		var moved := false
		for child in actor.get_node("Visual").get_children():
			face(actor, 1)
			await frames(1)
			var right := part_center(child)
			face(actor, -1)
			await frames(1)
			var left := part_center(child)
			moved = moved or absf(right) > 0.5
			check("%s/%s mirrors when turning around" % [actor.name, child.name], is_equal_approx(left, -right), "%.2f vs %.2f" % [left, right])
		check("%s has parts that actually change side" % actor.name, moved)


## 这个部件横向的中心位置（方块取矩形中心，枪口这类点取它自己）。
func part_center(child: Node) -> float:
	if child is Control:
		return (child as Control).position.x + (child as Control).size.x / 2.0
	return (child as Node2D).position.x


func test_no_judgement_points_under_visual() -> void:
	# 判定点（枪口、检测射线、受击框……）一律挂在本体上，不能放进 Visual：
	# 放进去的话，换皮肤、压扁外观、甚至开枪的后坐力位移都会跟着改变游戏规则。
	await reset_scene(true)
	for actor in actors():
		for child in actor.get_node("Visual").get_children():
			var judgement: bool = child is Marker2D or child is RayCast2D or child is ShapeCast2D or child is CollisionObject2D
			check("%s/Visual/%s is art, not a judgement point" % [actor.name, child.name], not judgement,
				child.get_class())


func test_muzzles_follow_facing() -> void:
	# 出膛点要跟着朝向换边，子弹才会从正确的一侧飞出去。
	# 看的是真正用来生成子弹的那个点（按碰撞体算出来的），不是某个 Marker 摆在哪。
	await reset_scene(true)
	for actor in actors():
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			var reach := 0.0
			if actor is Player:
				reach = (actor as Player)._muzzle_position(Vector2(facing, 0)).x - actor.global_position.x
			elif (actor as Enemy)._muzzle == null or is_zero_approx((actor as Enemy)._muzzle.position.x):
				continue # D 没有枪口，E 是朝正下方开火
			else:
				reach = (actor as Enemy).level_muzzle_position().x - actor.global_position.x
			check("%s: fires from its front when facing %d" % [actor.name, facing], signf(reach) == float(facing),
				"%.1f" % reach)


func test_muzzle_height_comes_from_the_collision_box() -> void:
	# 趴下把碰撞体压低，出膛点必须跟着下来——这条规则要依赖碰撞体，而不是依赖占位方块被压扁。
	# 所以这里把外观整个藏起来再测一遍：结果必须一模一样。
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	await frames(5)
	c.set_physics_process(false) # 冻结 AI：玩家没趴下，它每帧都会把自己重新站起来
	var standing := c.level_muzzle_position().y
	c.get_node("Visual").hide()
	c.get_node("Visual").position = Vector2(0, -200) # 把外观挪走也不该影响判定
	await frames(2)
	check("hiding the art does not move the muzzle", is_equal_approx(c.level_muzzle_position().y, standing),
		"%.1f vs %.1f" % [c.level_muzzle_position().y, standing])
	c.set_prone(true)
	await frames(2)
	check("going prone lowers it", c.level_muzzle_position().y > standing + 6.0,
		"%.1f -> %.1f" % [standing, c.level_muzzle_position().y])


# ---------------------------------------------------------------- 外观接口（第 8 步）

func test_every_character_has_an_appearance_layer() -> void:
	# 玩法和「长什么样」之间只有这一个接口
	await reset_scene(true)
	for actor in actors():
		check("%s's Visual is an Appearance" % actor.name, actor.get_node("Visual") is Appearance)


func test_gameplay_runs_on_a_replaced_appearance() -> void:
	# 把玩家和敌人的外观整个换成「什么都不画」的替身：游戏照常跑、判定分毫不差，
	# 而且能看到玩法确实是通过接口（朝向/姿势/瞄准/受击/闪烁）跟外观打交道的。
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.bullet_scene = null # 别让它开枪：挨一枪会被击飞，下面就趴不下去了
	c.max_health = 100
	c.health = 100
	c.global_position = Vector2(600, 304)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	# 换皮肤之前先记下判定点（相对身体的偏移）
	var player_muzzle := player._muzzle_position(Vector2.RIGHT) - player.global_position
	var enemy_muzzle := c.level_muzzle_position() - c.global_position

	var stub := load("res://tests/stub_appearance.gd")
	player.get_node("Visual").set_script(stub)
	c.get_node("Visual").set_script(stub)
	await frames(2)

	check("judgement points are unchanged: player", player._muzzle_position(Vector2.RIGHT) - player.global_position == player_muzzle,
		str(player._muzzle_position(Vector2.RIGHT) - player.global_position))
	check("judgement points are unchanged: enemy", c.level_muzzle_position() - c.global_position == enemy_muzzle,
		str(c.level_muzzle_position() - c.global_position))

	# 照常玩：走、开枪打中敌人、趴下、挨一下
	Input.action_press("move_right")
	await frames(6)
	Input.action_release("move_right")
	check("still moves", player.global_position.x > 480.0, str(player.global_position.x))
	player._shoot(Vector2.RIGHT)
	for i in 40:
		await frames(1)
		if c.health < 10:
			break
	check("still shoots and hits", c.health < 100, str(c.health))
	Input.action_press("crouch")
	await frames(6)
	check("still lies down", player.is_crouching and (player._shape.shape as RectangleShape2D).size.y == Player.CROUCH_HEIGHT)
	Input.action_release("crouch")
	await frames(6)
	player.take_damage(HIT)
	await frames(2)
	check("still takes damage", player.health < player.max_health, str(player.health))

	# 敌人这边也走一遍：趴下、转身
	c.set_prone(true)
	c.facing = -c.facing
	c._apply_visual_facing()
	await frames(2)

	var player_calls: Array = player.get_node("Visual").calls
	var enemy_calls: Array = c.get_node("Visual").calls
	for call_name in ["face", "aim", "pose", "kick", "blink"]:
		check("the player's logic calls appearance.%s()" % call_name, player_calls.has(call_name), str(player_calls))
	for call_name in ["face", "aim", "pose", "flash_hit"]:
		check("the enemy's logic calls appearance.%s()" % call_name, enemy_calls.has(call_name), str(enemy_calls))
	release_all_input()
