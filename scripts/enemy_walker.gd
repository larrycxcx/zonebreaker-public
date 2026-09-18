class_name EnemyWalker
extends Enemy
## 巡逻敌人：左右走，撞墙或走到平台边缘时掉头，碰到玩家造成伤害，
## 并且会朝自己正前方开火（不会回头瞄准，转向完全由巡逻决定）。

@export var move_speed := 30.0
@export_enum("左:-1", "右:1") var start_direction := -1

@onready var _floor_check: RayCast2D = $FloorCheck
@onready var _wall_check: RayCast2D = $WallCheck


func _ready() -> void:
	super()
	facing = start_direction
	_apply_facing()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_speed * facing
	move_and_slide()

	# 脚下没路（悬空）或前方被挡住就掉头。
	# is_on_wall() 是必要的补充：矮天花板挡住的是身体上半部分，WallCheck 那条射线打不到。
	if is_on_floor() and (not _floor_check.is_colliding() or _wall_check.is_colliding() or is_on_wall()):
		facing = -facing
		_apply_facing()

	try_shoot(delta, _target_in_front())


## 只打正前方的玩家：背后的够不着也不回头。
func _target_in_front() -> Node2D:
	var target := find_target()
	if target == null:
		return null
	var offset_x := target.global_position.x - global_position.x
	return target if signi(offset_x) == facing else null


func _apply_facing() -> void:
	_visual.scale.x = facing
	_floor_check.position.x = absf(_floor_check.position.x) * facing
	_wall_check.target_position.x = absf(_wall_check.target_position.x) * facing
	# 掉头后立刻重算，避免下一帧还用旧结果导致反复抖动。
	_floor_check.force_raycast_update()
	_wall_check.force_raycast_update()
