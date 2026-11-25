class_name EnemyTurret
extends Enemy
## Stationary enemy: when the player comes into range it turns to face them and fires on a timer — level shots at the same height, 45° shots after aiming diagonally up/down;
## when the player lies prone at the same height it lies down too to fire low.

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
