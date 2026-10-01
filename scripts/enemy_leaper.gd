class_name EnemyLeaper
extends EnemyWalker
## 3-C 剑客：巡逻兵的一种，**不开枪**——看见玩家就**蓄一下然后跳过去，落地横扫一刀**。
##
## 它是这一关里唯一会主动越过地形的敌人：矮墙、浮台都挡不住它，
## 所以「躲在掩体后面慢慢打」对它不管用。**躲法是横向拉开**——
## 跳的落点在起跳那一刻就定了，人往旁边走一步，那一刀就落空。
##
## 刀是**落地那一刻**结算的（和抡锤一样）：在空中追着人改落点的话，这条躲法就没意义了。

enum Leap { NONE, WINDUP, AIR, REST }

@export_group("Leap")
## 这个距离以内就起跳（直线距离，不分前后——它会转过去）。
@export var leap_range := 170.0
## 蓄力多久。留给玩家横向走开的时间。
@export var leap_windup := 0.35
## 跳出去的速度：横向朝玩家那边，纵向往上。
@export var leap_speed := 170.0
@export var leap_jump := -520.0
## 落地之后歇多久。
@export var leap_rest := 1.4
## 落地那一刀：这个半径里的玩家挨打。
@export var slash_offset := Vector2(20, 0)
@export var slash_radius := 26.0
@export var slash_damage := 44

var _leap := Leap.NONE
var _left := 0.0
func _physics_process(delta: float) -> void:
	# **只在地上转向**：空中不再改朝向，横向速度是 `walk_speed() * facing`，
	# 一改朝向它就会在半空掉头飞回去，「落点在起跳那一刻就定了」这条躲法就没了。
	if _leap == Leap.NONE or _leap == Leap.WINDUP:
		var target := leap_target()
		if target != null:
			var side := signi(target.global_position.x - global_position.x)
			if side != 0:
				facing = side
				_apply_facing()
	if _leap == Leap.AIR and is_on_floor() and velocity.y >= 0.0:
		_land()
	super(delta)
	_update_leap(delta)


func is_leaping() -> bool:
	return _leap == Leap.AIR


func is_winding_up() -> bool:
	return _leap == Leap.WINDUP


## 空中按起跳时定下的方向飞；蓄力和歇着的时候站定；别的时候照常巡逻。
func walk_speed() -> float:
	return leap_speed if _leap == Leap.AIR else move_speed


func patrolling() -> bool:
	return _leap == Leap.NONE


func is_engaged(_target: Node2D) -> bool:
	return _leap == Leap.WINDUP or _leap == Leap.REST


func _update_leap(delta: float) -> void:
	if _leap == Leap.NONE:
		if leap_target() != null and is_on_floor():
			_leap = Leap.WINDUP
			_left = leap_windup
		return
	if _leap == Leap.AIR:
		return      # 落地那一下由 `_land()` 结束，不看表
	_left -= delta
	if _left > 0.0:
		return
	if _leap == Leap.WINDUP:
		_leap = Leap.AIR
		velocity.y = leap_jump
	else:
		_leap = Leap.NONE


## 落地：横扫一刀，这个半径里的玩家挨打。**落点在起跳那一刻就定了**，
## 所以人往旁边走一步就躲掉了。
func _land() -> void:
	_leap = Leap.REST
	_left = leap_rest
	_visual.fire()
	var at := body_center() + Vector2(slash_offset.x * facing, slash_offset.y)
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= slash_radius:
			player.take_damage(roundi(slash_damage * Stage.damage_scale()), at, self)


## 够得着、看得见的玩家（**不分前后**——它会转过去跳）。
func leap_target() -> Node2D:
	for player in players_by_distance():
		if not within_reach(global_position.distance_to(player.global_position)):
			continue
		if global_position.distance_to(player.global_position) > leap_range:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null
