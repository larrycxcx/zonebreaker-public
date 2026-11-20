class_name EnemyMutant
extends EnemyHammer
## 第五关的变异体（5-C，科学家变身之后也是它）：走近、举手、**砸地**。
##
## 砸地那一下除了锤子兵那套「锤头周围挨打」，还有一圈**震波**：左右 `shock_radius` 以内、
## **脚踩在地上**、和它站在同一层（脚底差不到 `shock_height`）的玩家都挨一下，被往上弹起来。
## **跳起来就躲得掉**（人在空中不算）——举手那一下就是让你起跳的时机。
## 走近、转身、起手、伤害卡在砸到底那一帧，全是 `EnemyHammer` 的（`hit_frame` 配素材第 4 帧）。

@export_group("Shockwave")
@export var shock_radius := 72.0
@export var shock_height := 20.0
@export var shock_damage := 24
## 被震起来的力度（往上弹）。
@export var shock_lift := 260.0


func _land_the_blow() -> void:
	var direct: Array[Player] = []
	var at := smash_point()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= smash_radius:
			direct.append(player)
	super()
	var feet := global_position.y + feet_offset()
	for player in players_by_distance():
		if direct.has(player) or not shaken(player, feet):
			continue
		var landed := not player.is_invincible()
		player.take_damage(roundi(shock_damage * Stage.damage_scale()), global_position, self)
		if landed:
			player.shove(Vector2(0.0, -shock_lift))


## 这个玩家会不会被震到：在左右范围内、脚踩在地上、和它脚底差不多高。
func shaken(player: Player, feet: float) -> bool:
	if not player.is_on_floor():
		return false
	if absf(player.global_position.x - global_position.x) > shock_radius:
		return false
	return absf(player.global_position.y + 16.0 - feet) <= shock_height


## 自己的脚底在原点下方多少（判定框底边）。
func feet_offset() -> float:
	return 16.0
