class_name EnemyTurret
extends Enemy
## 站桩敌人：玩家进入射程且高度接近时，转向玩家并定时开火。

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()

	var target := find_target()
	if target != null:
		_face_toward(target)
	try_shoot(delta, target)


func _face_toward(target: Node2D) -> void:
	var offset_x := target.global_position.x - global_position.x
	if offset_x == 0.0:
		return
	facing = signi(offset_x)
	_visual.scale.x = facing
