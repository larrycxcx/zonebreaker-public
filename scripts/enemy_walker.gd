class_name EnemyWalker
extends Enemy
## 巡逻敌人：左右走，撞墙或走到平台边缘时掉头，碰到玩家造成伤害，
## 并且会朝自己正前方开火（不会回头瞄准，转向完全由巡逻决定）。
## 正前方的玩家趴下时，它会停下来趴着开枪，玩家站起来后它也站起来继续巡逻。
## 能斜射的（B、C）遇到正前方斜上/斜下的玩家时停下来瞄准开火，玩家回到水平方向或离开后继续巡逻。

@export var move_speed := 60.0
@export_enum("左:-1", "右:1") var start_direction := -1

@onready var _floor_check: RayCast2D = $FloorCheck
@onready var _wall_check: RayCast2D = $WallCheck


func _ready() -> void:
	super()
	facing = start_direction
	_apply_facing()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	# 趴下、斜向瞄准时都站在原地开枪。
	var standing_still := is_prone or is_aiming_diagonally()
	velocity.x = 0.0 if standing_still else move_speed * facing
	move_and_slide()

	if not standing_still and _should_turn_around():
		facing = -facing
		_apply_facing()

	var target := _target_in_front()
	var ready := update_aim(delta, target)
	# 只在玩家和自己差不多高时才跟着趴下；斜着往下打的时候保持站立。
	update_prone(delta, target if not is_aiming_diagonally() else null)
	try_shoot(delta, ready)


## 巡逻时脚下没路（悬空）或前方被挡住就该掉头。
## is_on_wall() 是必要的补充：矮天花板挡住的是身体上半部分，WallCheck 那条射线打不到。
func _should_turn_around() -> bool:
	return is_on_floor() and (not _floor_check.is_colliding() or _wall_ahead() or is_on_wall())


## 正前方有没有挡路的东西。单向平台的侧面不算：横着本来就能穿过去（玩家也一样）。
func _wall_ahead() -> bool:
	if not _wall_check.is_colliding():
		return false
	var platform := _wall_check.get_collider() as Platform
	return platform == null or not platform.one_way


## 只打正前方的玩家：背后的够不着也不回头。
func _target_in_front() -> Node2D:
	var target := find_target()
	if target == null:
		return null
	var offset_x := target.global_position.x - global_position.x
	return target if signi(offset_x) == facing else null


func _apply_facing() -> void:
	_apply_visual_facing()
	_floor_check.position.x = absf(_floor_check.position.x) * facing
	_wall_check.target_position.x = absf(_wall_check.target_position.x) * facing
	# 掉头后立刻重算，避免下一帧还用旧结果导致反复抖动。
	_floor_check.force_raycast_update()
	_wall_check.force_raycast_update()
