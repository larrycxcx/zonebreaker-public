class_name Sight
extends RefCounted
## 「两点之间有没有实心东西挡着」：敌人的视线、手雷爆炸波及范围都用这个，规则保持一致——
## 地面、墙、矮通道这些实心物体挡住；单向平台不挡（子弹、玩家都能从下面穿过去）。

## 物理层 1（world）：地面、平台、墙。
const WORLD_LAYER := 1


static func is_clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER)
	var ignored: Array[RID] = []
	# 一条射线最多穿过几块单向平台，给个上限防止意外死循环。
	for i in 8:
		query.exclude = ignored
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var platform := hit["collider"] as Platform
		if platform == null or not platform.one_way:
			return false
		ignored.append(hit["rid"])
	return false


## 从 from 往 to 走，**第一个实心物体**在哪儿（规则同上：单向平台不挡）；一路没挡就是 to。
## 地下室 Boss 的激光用它：射到墙为止，穿过单向平台。
static func first_solid(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER)
	var ignored: Array[RID] = []
	for i in 8:
		query.exclude = ignored
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return to
		var platform := hit["collider"] as Platform
		if platform == null or not platform.one_way:
			return hit["position"]
		ignored.append(hit["rid"])
	return to
