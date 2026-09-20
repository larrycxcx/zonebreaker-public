extends GameTest
## 外观翻转：一律保持 scale 为正，靠镜像子节点的横向位置来左右翻转（见 VisualFlip）。
##
## 为什么要专门测：用负的 scale 翻转时，Visual 下的 ColorRect 算出来的绘制矩形是错的
## （位置整整偏出一个身宽、高度为负），引擎按它做屏幕剔除，角色在某些位置会整块不画出来——
## Boss A 跳到空中时偶尔整个消失就是这个原因。矩形对不对在无头模式下也能检查，不需要真的渲染。

## 关卡里各种角色的节点路径。
const ACTORS := [
	"Player", "Enemies/WalkerA", "Enemies/WalkerB", "Enemies/WalkerC",
	"Enemies/ChaserD", "Enemies/FlyerE", "Enemies/Turret1", "Enemies/WalkerF", "Enemies/BossA",
]


func actors() -> Array:
	var found := []
	for path in ACTORS:
		found.append(main.get_node(path))
	return found


## 让它朝某个方向，并按各自的方式刷新外观。
func face(actor: Node, facing: int) -> void:
	actor.facing = facing
	if actor is Player:
		VisualFlip.apply(actor._visual_bases, facing)
	else:
		(actor as Enemy)._apply_visual_facing()


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
					r.grow(2.0).has_point(actor.global_position) or actor.global_position.distance_to(r.get_center()) < 24.0,
					"%s vs body at %s" % [r, actor.global_position])


func test_facing_left_mirrors_facing_right() -> void:
	# 朝左时的摆位正好是朝右时的镜像（E 的左右翅膀这种对称的一对会互换，也满足这条）
	await reset_scene(true)
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
	c.get_node("Visual").position = Vector2(0, -100) # 把外观挪走也不该影响判定
	await frames(2)
	check("hiding the art does not move the muzzle", is_equal_approx(c.level_muzzle_position().y, standing),
		"%.1f vs %.1f" % [c.level_muzzle_position().y, standing])
	c.set_prone(true)
	await frames(2)
	check("going prone lowers it", c.level_muzzle_position().y > standing + 3.0,
		"%.1f -> %.1f" % [standing, c.level_muzzle_position().y])
