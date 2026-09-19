class_name EnemyTurret
extends Enemy
## 站桩敌人：玩家进入射程时转向玩家并定时开火——同一高度水平打，斜上/斜下方向瞄准后 45° 打；
## 玩家在同一高度趴下时它也趴下打低处。

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()

	var target := find_target()
	if target != null:
		_face_toward(target)
	var ready := update_aim(delta, target)
	update_prone(delta, target if not is_aiming_diagonally() else null)
	try_shoot(delta, ready)


func _face_toward(target: Node2D) -> void:
	var offset_x := target.global_position.x - global_position.x
	if offset_x == 0.0:
		return
	facing = signi(offset_x)
	_apply_visual_facing()
