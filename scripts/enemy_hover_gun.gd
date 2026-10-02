class_name EnemyHoverGun
extends Enemy
## 地下室 4-D 无人机：**贴着玩家的高度飞**，一对齐就横着开枪。
##
## 第一关的 E 是「跟着你的横向位置、往正下方打」；这个反过来——**横向不动，跟着你的高度**。
## 它守在竖井的一侧（出生点那一列），你往上爬它也往上爬，甩不掉，只能打掉。
## 为纵向关做的：横版关里玩家的高度基本不变，它就只是一个站桩的炮台。
##
## - 不受重力（`motion_mode` = floating），在出生点上下 `leash` 以内活动——
##   不拴着的话它会跟着玩家一路飞出自己那一段，几架挤到一起。
## - 爬升速度 `climb_speed` 比玩家跳一下慢：玩家一跳会先甩开它一截，落脚站稳它才追上来对齐。
##   对齐（身体中心高度差在 `align_tolerance` 以内）才开火，所以那一截空当就是躲它的机会。
## - 朝向跟着玩家在哪一边（它悬在空中，左右都能打）。
## - 开火走基类那一套（冷却、连发、出膛点 = 碰撞体中心 + `Muzzle` 偏移、视线），子弹水平飞。
## - 看不见目标时就地悬停，带一点上下浮动（喷口在喷，不能是死的）。

@export_group("Hover")
## 跟玩家高度时上下飞多快。
@export var climb_speed := 90.0
## 以出生点为中心，上下最多飞多远。
@export var leash := 220.0
## 身体中心和玩家身体中心的高度差在这以内就算对齐，可以开火。
@export var align_tolerance := 14.0
## 悬停时上下浮动的幅度和周期。
@export var bob_amplitude := 3.0
@export var bob_period := 1.2

var _home := Vector2.ZERO
var _bob_time := 0.0
## 正在跟的高度（世界坐标，测试用）。
var target_height := 0.0


func _ready() -> void:
	super()
	_home = global_position
	target_height = global_position.y


## 把它放到 position，以这里为上下活动的中心。
func set_anchor(position_: Vector2) -> void:
	global_position = position_
	_home = position_
	target_height = position_.y


func _physics_process(delta: float) -> void:
	_bob_time += delta
	var target := find_target()
	if target != null:
		var side := signi(target.global_position.x - global_position.x)
		if side != 0 and side != facing:
			facing = side
			_apply_visual_facing()
		target_height = clampf((target as Player).body_center().y, _home.y - leash, _home.y + leash)
	var bob := bob_amplitude * sin(TAU * _bob_time / bob_period) if target == null else 0.0
	var goal := target_height + bob
	velocity.x = (_home.x - global_position.x) / delta
	velocity.y = clampf((goal - global_position.y) / delta, -climb_speed, climb_speed)
	move_and_slide()
	try_shoot(delta, target if target != null and is_aligned_with(target) else null)


## 和这个玩家对齐了吗：身体中心的高度差在 `align_tolerance` 以内。
func is_aligned_with(target: Node2D) -> bool:
	var player := target as Player
	var at := player.body_center().y if player != null else target.global_position.y
	return absf(at - body_center().y) <= align_tolerance


## 能跟的玩家：够得着（在屏幕里，或者直线距离在 detect_range 以内）、看得见。**不分上下左右**。
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position)) \
		and has_line_of_sight(player.body_center())


## 横着打，朝着玩家那一边。
func shoot_direction() -> Vector2:
	return Vector2(facing, 0)
