class_name BossPlaceholder
extends Boss
## 占位 Boss：用来验证 Boss 的通用规则（出场、HUD、终极武器），攻击方式之后逐个 Boss 设计时替换。
## 现在的攻击：站着不动，转向玩家，水平连发（射击参数都在场景的导出属性里）。


func _boss_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	var target := find_target()
	if target != null:
		var offset_x := target.global_position.x - global_position.x
		if offset_x != 0.0:
			facing = signi(offset_x)
			_visual.scale.x = facing
			_muzzle.position.x = absf(_muzzle.position.x) * facing
	try_shoot(delta, target)
