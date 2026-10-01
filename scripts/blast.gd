class_name Blast
## 爆炸的共用规则：**炸得到谁、各受多少伤害**。手雷和自爆的机器人用的是同一套。
##
## 规则写两遍迟早会分叉（一边改了半径、另一边没改），所以和 `Sight`（「两点之间有没有实心物体」）
## 一样提出来放一个地方。谁能被炸到由 `target_layer` 决定，所以两边都炸不到自己人。


## 这一圈里炸得到的目标：在半径内、能 `take_damage`、**中间没被实心物体挡住**。
## 挡住就炸不到，和敌人的视线同一条规则（`Sight.is_clear`）。
static func victims(space: PhysicsDirectSpaceState2D, at: Vector2, radius: float,
		layer: int) -> Array[Node2D]:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = layer
	var out: Array[Node2D] = []
	for hit in space.intersect_shape(query, 32):
		var victim := hit["collider"] as Node2D
		if victim == null or not victim.has_method("take_damage"):
			continue
		# 已经打死、正排队等删的不再算一次（否则事件会报两遍、奖励发两份）
		if victim is Enemy and (victim as Enemy).health <= 0:
			continue
		if Sight.is_clear(space, at, victim.global_position):
			out.append(victim)
	return out


## 离爆炸中心这么远该受多少伤害：**中心 `max_damage`、边缘 `min_damage`，线性**。
## 所以站在边上只擦一下，正中间才是满伤害——躲的办法是离远点，不是硬扛。
static func damage_at(distance: float, radius: float, max_damage: int, min_damage: int) -> int:
	var falloff := clampf(distance / maxf(1.0, radius), 0.0, 1.0)
	return roundi(lerpf(max_damage, min_damage, falloff))
