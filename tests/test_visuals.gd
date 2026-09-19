extends GameTest
## 外观翻转：一律保持 scale 为正，靠镜像子节点的横向位置来左右翻转（见 VisualFlip）。
##
## 为什么要专门测：用负的 scale 翻转时，Visual 下的 ColorRect 算出来的绘制矩形是错的
## （位置整整偏出一个身宽、高度为负），引擎按它做屏幕剔除，角色在某些位置会整块不画出来——
## Boss A 跳到空中时偶尔整个消失就是这个原因。矩形对不对在无头模式下也能检查，不需要真的渲染。

## 关卡里各种角色的节点路径。
const ACTORS := [
	"Player", "Enemies/WalkerA", "Enemies/WalkerB", "Enemies/WalkerC",
	"Enemies/ChaserD", "Enemies/FlyerE", "Enemies/Turret1", "Enemies/BossA",
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


func test_muzzles_follow_facing() -> void:
	# 枪口跟着换边，子弹才会从正确的一侧飞出去
	await reset_scene(true)
	for actor in actors():
		var muzzle := actor.get_node_or_null("Visual/Muzzle") as Marker2D
		if muzzle == null:
			continue
		for facing in [-1, 1]:
			face(actor, facing)
			await frames(1)
			check("%s: muzzle is in front when facing %d" % [actor.name, facing], signf(muzzle.position.x) == float(facing), str(muzzle.position))
